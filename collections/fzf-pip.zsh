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

_pipf_list_available() {
  curl -s "$(pip config get global.index-url)/" \
    | perl -lne '/">(.*?)<\/a>/ && print $1'
}

# ---- pip show 字段提取（显式收参） ----

_pipf_extract() {
  _pipf show "$1" 2>/dev/null | perl -slne '/^\Q$f\E: (.+)$/ && print "$1"' -- -f="$2"
}

# ---- 版本相关：显式收参 ----

_pipf_version_list() {
  _pipf index versions --pre "$1" 2>/dev/null \
    | perl -lne '/Available versions: (.*)$/m && print $1' \
    | perl -pe 's/, /\n/g'
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
