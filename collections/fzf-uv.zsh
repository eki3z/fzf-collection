#!/usr/bin/env zsh
# 库文件，由 fzf-collection.plugin.zsh source 加载；无顶层入口，模式 100644。

# 管的是 `uv tool` 装出来的全局命令，不是 uv 项目里的依赖。它的
# tool install/list/uninstall/upgrade 都不接受 --format json，三个视图的行全靠下面
# 这几个函数从文本输出解析，上游一改格式这里就瞎。

_uvf() {
  uv "$@"
}

# ---- 列表查询：输出 name<TAB>rest ----

# `uv tool list` 的顶层行是 `name v1.2.3`，紧跟的 `- exe` 行是该工具的可执行
# 文件（一行一个，可能多个，也可能没有）。顶层行随 --show-* 长出方括号注解：
#   v0.1.0 [required: ==0.1.0] [CPython 3.14.7] [latest: 0.16.9] (/path/to/env)
# 所以从第一个 ` [` 截断，注解不进列，否则 version 会变成 `1.0.0]`。

# 截断模式里的 `[` 必须转义成 \[ ：参数展开的模式中 `[` 是字符组的开头，写成
# ${line%% [*} 会被当成未闭合的字符组，每行都报 "bad pattern"，整个列表变空。

# 工具目录为空时 uv 打的是 "No tools installed"，**走 stderr**，所以
# 2>/dev/null 之后这里天然是空输出，驱动会打 "Nothing to show."。
_uvf_list_installed() {
  local line
  local -a f
  uv tool list 2>/dev/null | while IFS= read -r line; do
    [[ $line == '- '* ]] && continue
    line=${line%% \[*}
    f=(${(z)line})
    (( ${#f} >= 2 )) || continue
    # 顶层行是 `name v1.2.3`，uv 自己带 v 前缀，去掉它与 pipf / npmf 对齐。
    print -r -- "${f[1]}${_FC_TAB}${f[2]#v}"
  done
}

# `uv tool list --outdated` 只列有更新的，已是最新的一律不出现（uv 0.11.0 起）。
# 行形状与上面相同，只在行尾多了 `[latest: X]`，所以要先摘 X 再截断注解。

# 已知会误报的一种：从 git 装来的工具，uv 拿同名 PyPI 包比版本，回一个与那个
# checkout 毫无关系的版本号，upgrade 也只会说 Nothing to upgrade。故意不识别：
# 识别要读每个工具的 uv-receipt.toml，而从索引装的工具不会用到那条分支。
_uvf_list_outdated() {
  local line latest
  local -a f
  uv tool list --outdated 2>/dev/null | while IFS= read -r line; do
    [[ $line == '- '* ]] && continue
    latest=''
    if [[ $line == *'[latest: '* ]]; then
      latest=${line##*'[latest: '}
      latest=${latest%%']'*}
    fi
    line=${line%% \[*}
    f=(${(z)line})
    (( ${#f} >= 2 )) || continue
    # 四列与 pipf / npmf 同形：名字 | 当前 | => | 最新。
    print -r -- "${f[1]}${_FC_TAB}${f[2]#v}${_FC_TAB}=>${_FC_TAB}${latest}"
  done
}

# uv 没有 search 子命令，只能抓 simple index。整条链必须留在 C 程序里：index 页
# 87 万行（pypi.org 约 45MB）；grep -o 把一行里的每个锚点单独打出来，正好等价于
# 逐行 while 抠 `>…</a>` 的「一次吐一个」语义，贪婪匹配的 sed 一行只能吐最后一个。

# index 取 ${_UVF_INDEX:-$_FC_PYPI_INDEX}，默认 pypi.org，环境变量是覆盖。斜杠
# 必须自己拼在 `}` 后面：URL 不带斜杠时 index 会 301 到带斜杠的那份，而 curl 不带
# -L 不跟随，于是拿到的是 169 字节的重定向页，一个包名都抠不出来。
_uvf_list_available() {
  curl -s "${_UVF_INDEX:-$_FC_PYPI_INDEX}/" \
    | grep -o '>[^<]*</a>' \
    | sed -e 's/^>//' -e 's|</a>$||'
}

# **抓回来的东西无法保证是 tool**：索引上绝大多数包不提供入口点，uv 装它们会失败
# 并返回 2，驱动照实报出来。install 不是 mutating 动作，失败的行留在列表里可改选。

# PyPI JSON API，供 list-versions / info / deps / homepage 用。根取
# ${_UVF_PYPI_JSON:-$_FC_PYPI_JSON_BASE}，环境变量是覆盖。

# 刻意**不**跟着 _UVF_INDEX 走：镜像的 JSON 快照可能很旧（实测 tuna 的
# /pypi/ruff/json 还停在 0.5.7，PyPI 已经是 0.16.9），拿旧快照列版本，rollback 会
# 给出一堆装不上的选项。search 抓名字不在乎新旧，所以那处用镜像。
_uvf_pypi() {         # $1=pkg $2=jq 过滤器
  curl -fsS "${_UVF_PYPI_JSON:-$_FC_PYPI_JSON_BASE}/$1/json" 2>/dev/null | jq -r "$2"
}

# uv 没有 per-tool 的 show（`uv tool list` 只能整表列），所以从整表里按名字
# 截出那一块：顶层行 + 它的可执行文件行，供 info 用。
_uvf_show_entry() {   # $1=pkg -> 该工具在 uv tool list 里的原始块
  local pkg=$1 line take=0
  while IFS= read -r line; do
    if [[ $line == '- '* ]]; then
      (( take )) && print -r -- "$line"
      continue
    fi
    take=0
    [[ ${line%% *} == "$pkg" ]] || continue
    take=1
    print -r -- "$line"
  done
}

# ---- 版本相关：显式收参 ----

# available versions 只能从 PyPI JSON 的 releases 取 —— uv 没有 `index versions`
# 的等价物。两个坑：releases 的**键序不是上传序**（ruff 的 0.16.9 在 425 个键里排
# 第 361 位，末尾反而是 0.9.x），必须按 upload_time 排；空数组的版本是 yank 掉的。
_uvf_version_list() {
  _uvf_pypi "$1" '[.releases | to_entries[] | select(.value | length > 0)
                   | {v: .key, t: (.value | map(.upload_time) | max)}]
                 | sort_by(.t) | reverse | .[].v'
}

# 装没装得从 uv 自己那份表里查，与 manage 列表同一份数据。
_uvf_version_current() {
  local line
  while IFS= read -r line; do
    [[ ${line%%$'\t'*} == "$1" ]] || continue
    print -r -- "${line#*$'\t'}"
    return 0
  done < <(_uvf_list_installed)
}

# 实测 `uv tool install pkg==ver` 双向都行：装低版本就是降级，不需要 --force，
# 装高版本就是升级。它也是三个 mutating 动作里唯一能换版本的。
_uvf_version_install() {
  _uvf tool install "$1==$2"
}

# ---- 动作适配器 ----

# 三个 mutating 动作都是 `uv tool <动作> <包名>`，形状一致，原生透传就够。
# info / deps / homepage / rollback 在注册表里有各自的键，不会落到这里。
_uvf_act() { _uvf tool "$1" "$2" }

# uv 自己的那一段：装了就给路径、版本限定符、Python 版本，没装说清楚。摘要与
# requires-python 只能问 PyPI，所以两段拼在一起给。
_uvf_info() {
  local block
  block=$(uv tool list --show-paths --show-version-specifiers --show-python 2>/dev/null \
    | _uvf_show_entry "$1")
  if [[ -n $block ]]; then
    print -r -- "$block"
  else
    print -r -- "Not installed: $1"
  fi
  print -r -- ''
  # grep -v ': $' 丢掉取不到的字段（ruff 没有 requires_dist 之类），否则每次 info
  # 都跟着四行空标签。
  _uvf_pypi "$1" '.info
                 | "version: \(.version // "")",
                   "summary: \(.summary // "")",
                   "requires-python: \(.requires_python // "")",
                   "home-page: \(.project_urls.Homepage // .home_page // .project_url // "")"' \
    | grep -v ': $'
}

# 装了的读它自己的 venv —— 那才是这个工具实际拿到的依赖（含 --with 装进去的额外
# 依赖，那正是 `uv tool list --outdated` 不检查的部分）。没装的退到 requires_dist。
_uvf_deps() {
  local pkg=$1 py
  # 不用 local x=$(...)：那会把退出码吞掉，uv 不在时后面 || 不触发。
  py="$(_uvf tool dir)/$pkg/bin/python"
  if [[ -x $py ]]; then
    _uvf pip freeze --python "$py"
  else
    _uvf_pypi "$pkg" '.info.requires_dist // [] | .[]'
  fi
}

_uvf_homepage() {
  _fc_homepage "$(_uvf_pypi "$1" '.info | .project_urls.Homepage // .home_page // .project_url // ""')"
}

_uvf_rollback() { _fc_rollback uv "$1" }

# ---- 注册表 ----

_FC_REG+=(
  'uv:title'          'Uv'
  'uv:views'          'outdated search manage'
  'uv:fallback'         '_uvf_act'

  'uv:outdated'       '_uvf_list_outdated'
  'uv:outdated:title' 'Uv Tool Outdated'
  'uv:outdated:fzf-opts'   '--tiebreak=index'
  'uv:outdated:actions' 'upgrade uninstall rollback homepage deps info'
  'uv:outdated:cols'  'name have sep want'

  'uv:search'         '_uvf_list_available'
  'uv:search:title'   'Uv Tool Search'
  # search 列的是索引上**全部**包，绝大多数不是 tool，uninstall 对它们没有意义。
  # 没有可达的 mutating 动作，于是本视图走流式路径（见 base.zsh 的
  # _fc_view_streamable）：87 万行不落进 zsh 内存，每次回到列表重抓一次。
  'uv:search:actions' 'install rollback homepage deps info'
  'uv:search:cols'    'name'

  'uv:manage'         '_uvf_list_installed'
  'uv:manage:title'   'Uv Tool Manage'
  'uv:manage:actions' 'uninstall rollback homepage deps info'
  'uv:manage:cols'    'name have'

  # upgrade 只在 outdated 出现、uninstall 只在 manage 出现，两个视图互不覆盖，
  # 所以在 eco 级声明一次就够，不需要 view 级覆盖。
  'uv:mutating' 'upgrade uninstall'
  'uv:stay'     'homepage deps info'

  'uv:rollback'         '_uvf_rollback'
  'uv:info'             '_uvf_info'
  'uv:deps'             '_uvf_deps'
  'uv:homepage'         '_uvf_homepage'
  'uv:list-versions'     '_uvf_version_list'
  'uv:current-version'  '_uvf_version_current'
  'uv:install-version'  '_uvf_version_install'
)

uvf() {
  if ! _fc_have_cmd uv; then
    print -r -- 'Error! uv is required.'
    return 0
  fi
  _fc_cmd uv
}
