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

# 从 pip index 页面抠包名。锚点是第一个 `">` 到第一个 `</a>`，
# 对应 perl 的非贪婪 /(.*?)<\/a>/。
_pipf_list_available() {
  local line rest
  curl -s "$(pip config get global.index-url)/" | while IFS= read -r line; do
    while [[ $line == *'>'*'</a>'* ]]; do
      rest=${line#*>}
      print -r -- "${rest%%</a>*}"
      line=${line#*</a>}
    done
  done
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
    print -r -- "${s//, /$_PIP_NL}"
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
  if _fzf_exist pip-autoremove && [[ $1 != pip-autoremove ]]; then
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

_pipf_info() { _pipf show "$1" | _fzf_pager }
_pipf_deps() { _pipf_extract "$1" Requires }
_pipf_use() { _pipf_extract "$1" Required-by }
_pipf_homepage() { _fzf_homepage "$(_pipf_extract "$1" Home-page)" }
_pipf_rollback() { _pkg_rollback pip "$1" }

# ---- 注册表 ----

# base.zsh 已用 typeset -gA 声明过；这里再确认一次，使本文件即使被单独 source
# 也不会把 PKG 变成普通数组（下标里的 ':' 会被当成算术求值）。
[[ ${(t)PKG} == association ]] || typeset -gA PKG

# 换行符。${s//, /$'\n'} 里的 $'\n' 不会被求值（替换位和 flag 参数一样是字面量），
# 会原样输出这四个字符，所以只能走变量。必须在文件顶层声明 ——
# 循环体内的标量 local 会往 stdout 打一行赋值，混进候选列表。
typeset -g _PIP_NL=$'\n'

PKG+=(
  'pip:title'          'Pip'
  'pip:views'          'outdated search manage'
  'pip:runner'         '_pipf_act'

  'pip:outdated'       '_pipf_list_outdated'
  'pip:outdated:title' 'Pip Outdated'
  'pip:outdated:opt'   '--tiebreak=index'
  'pip:outdated:actions' 'upgrade uninstall rollback deps use info'
  'pip:outdated:cols'  '0,34,0,33'

  'pip:search'         '_pipf_list_available'
  'pip:search:title'   'Pip Search'
  'pip:search:actions' 'install uninstall rollback'
  'pip:search:cols'    '0'

  'pip:manage'         '_pipf_list_installed'
  'pip:manage:title'   'Pip Manage'
  'pip:manage:actions' 'uninstall rollback homepage deps use info'
  'pip:manage:cols'    '0,34'

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

pipf() { _pkg_cmd pip }
