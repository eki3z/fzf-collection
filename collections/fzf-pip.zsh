#!/usr/bin/env zsh
# 上面这行是文件元数据（供编辑器与格式化工具识别），不是解释器指令。
# 本文件是库文件，由 fzf-collection.plugin.zsh 以 source 方式加载。
# 它仅含函数定义、无顶层入口，即使赋予执行权限直接运行也只会是空操作，
# 且缺少 base.zsh 的依赖必然失败。文件模式保持 100644，不要 chmod +x。

_pipf() {
  pip3 --disable-pip-version-check "$@"
}

# ---- 列表查询：输出 name<TAB>rest ----

_pipf_list_installed() {
  # SEE https://unix.stackexchange.com/a/615709
  _pipf list --format=json | jq -r '.[] | "\(.name)\t\(.version)"'
}

_pipf_list_outdated() {
  _pipf list --format=json --outdated \
    | jq -r '.[] | "\(.name)\t\(.version)\t=>\t\(.latest_version)"'
}

# 从 pip index 页面抠包名。
_pipf_list_available() {
  # 整条链必须留在 C 程序里：index 页有 87 万行。
  # 原来用 while-read 逐行抠 >…</a>，28s；换成 grep -o + sed 是 0.9s，
  # 输出逐字节相同（md5 一致）—— grep -o 把一行里的每个锚点都单独打出来，
  # 正好等价于原来那个 while 内层循环「一次吐一个」的语义；
  # 而贪婪匹配的 sed 一行只能吐最后一个，所以必须靠 grep -o 先切开。
  curl -s "$(pip config get global.index-url)/" \
    | grep -o '>[^<]*</a>' \
    | sed -e 's/^>//' -e 's|</a>$||'
}

# ---- pip show 字段提取（显式收参） ----

# 整行含 "<key>: " 才命中，取冒号后的内容。
# perl 版是 -slne '/^\Q$f\E: (.+)$/' 加 -s（-s 剥掉打印行的前导空白），
# 所以冒号后若还有多余空格也要剥掉。
_pipf_extract() {
  local line
  _pipf show "$1" 2>/dev/null | while IFS= read -r line; do
    [[ $line == *"$2: "* ]] || continue
    line=${line#*"$2: "}
    while [[ $line == [[:space:]]* ]]; do line=${line#?}; done
    print -r -- "$line"
    break
  done
}

# ---- 版本相关：显式收参 ----

_pipf_version_list() {
  local line s
  _pipf index versions --pre "$1" 2>/dev/null | while IFS= read -r line; do
    [[ $line == *'Available versions: '* ]] || continue
    s=${line#*'Available versions: '}
    # 换行必须走变量：${s//, /$'\n'} 里的 $'\n' 不被求值，
    # 会原样输出这四个字符。flag 参数是字面量，替换位同理。
    print -r -- "${s//, /$_FC_NL}"
    break
  done
}

_pipf_version_current() {
  _pipf_extract "$1" Version 2>/dev/null
}

_pipf_version_install() {
  _pipf install --user --upgrade --force-reinstall "$1==$2" 2>/dev/null
}

# ---- 动作适配器 ----

_pipf_install() {
  _pipf install --user "$@"
}

_pipf_uninstall() {
  if [[ $1 == pip ]]; then
    print -r -- "Package [pip] can not be uninstalled !"
    return 1
  fi
  # REQUIRE pip install pip-autoremove
  if _fc_have_cmd pip-autoremove && [[ $1 != pip-autoremove ]]; then
    pip-autoremove "$1" --yes
  else
    _pipf uninstall --yes "$1"
  fi
}

_pipf_act() {
  case $1 in
    upgrade)   _pipf_install --upgrade "$2" ;;
    uninstall) _pipf_uninstall "$2" ;;
    install)   _pipf_install "$2" ;;
    *)         _pipf "$1" "$2" ;;
  esac
}

_pipf_info() { _pipf show "$1" | _fc_pager }
_pipf_deps() { _pipf_extract "$1" Requires }
_pipf_use() { _pipf_extract "$1" Required-by }
_pipf_homepage() { _fc_homepage "$(_pipf_extract "$1" Home-page)" }
_pipf_rollback() { _fc_rollback pip "$1" }

# ---- 注册表 ----

# 换行用 base.zsh 的 _FC_NL。这里原来自己声明过一份 _FC_NL。

_FC_REG+=(
  'pip:title'          'Pip'
  'pip:views'          'outdated search manage'
  'pip:runner'         '_pipf_act'

  'pip:outdated'       '_pipf_list_outdated'
  'pip:outdated:title' 'Pip Outdated'
  'pip:outdated:opt'   '--tiebreak=index'
  'pip:outdated:actions' 'upgrade uninstall rollback deps use info'
  'pip:outdated:cols'  'name have sep want'

  'pip:search'         '_pipf_list_available'
  'pip:search:title'   'Pip Search'
  # search 列的是**还没装**的包，所以这里不能有 uninstall —— 对一个没装的包
  # 卸载没有意义，卸载入口只留在 manage。去掉它之后本视图也不再需要缓存列表，
  # 于是走流式路径（见 base.zsh 的 _fc_view_streamable）。
  'pip:search:actions' 'install rollback'
  'pip:search:cols'    'name'

  'pip:manage'         '_pipf_list_installed'
  'pip:manage:title'   'Pip Manage'
  'pip:manage:actions' 'uninstall rollback homepage deps use info'
  'pip:manage:cols'    'name have'

  'pip:mutating'           'uninstall'
  'pip:outdated:mutating'  'upgrade uninstall'
  'pip:loop'           'homepage deps use info'

  'pip:rollback'       '_pipf_rollback'
  'pip:info'           '_pipf_info'
  'pip:deps'           '_pipf_deps'
  'pip:use'            '_pipf_use'
  'pip:homepage'       '_pipf_homepage'
  'pip:version-list'     '_pipf_version_list'
  'pip:version-current'  '_pipf_version_current'
  'pip:version-install'  '_pipf_version_install'
)

pipf() { _fc_cmd pip }
