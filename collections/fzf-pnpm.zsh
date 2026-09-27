#!/usr/bin/env zsh
# 上面这行是文件元数据（供编辑器与格式化工具识别），不是解释器指令。
# 本文件是库文件，由 fzf-collection.plugin.zsh 以 source 方式加载。
# 它仅含函数定义、无顶层入口，即使赋予执行权限直接运行也只会是空操作，
# 且缺少 base.zsh 的依赖必然失败。文件模式保持 100644，不要 chmod +x。

_pnpmf() {
  pnpm "$1" --global "${@:2}"
}

# ---- 列表查询：输出 name<TAB>rest ----

_pnpmf_list_outdated() {
  _pnpmf outdated --json \
    | jq -r 'to_entries[] | "\(.key)\t\(.value.current)\t=>\t\(.value.latest)"'
}

_pnpmf_list_installed() {
  _pnpmf list --json \
    | jq -r '.[].dependencies | values[] | "\(.from)\t\(.version)"'
}

_pnpmf_list_available() {
  all-the-package-names
}

# ---- 版本相关：显式收参 ----

_pnpmf_version_list() {
  pnpm info "$1" versions --json 2>/dev/null | jq -r 'reverse | .[]' 2>/dev/null
}

_pnpmf_version_current() {
  _pnpmf list --json "$1" 2>/dev/null | jq -r '.[].dependencies | values[].version'
}

_pnpmf_version_install() {
  print -r -- "Install $1@$2"
  _pnpmf add "$1@$2" 2>/dev/null
}

# ---- 动作适配器 ----

# 改动类动作走 _pnpmf（带 --global）；只读与未知动作走原生 pnpm，
# 与旧 _pnpmf_switch 的分支保持一致。
_pnpmf_act() {
  case $1 in
    # pnpm update 默认不会跨大版本升，需显式 --latest
    # SEE https://github.com/pnpm/pnpm/issues/5365#issuecomment-1252398786
    update)  print -r -- "update $2"; _pnpmf update --latest "$2" ;;
    remove | add)                  _pnpmf "$1" "$2" ;;
    *)                             pnpm "$1" "$2" ;;
  esac
}

_pnpmf_info() { pnpm view "$1" | _fzf_pager }
_pnpmf_deps() { pnpm view "$1" dependencies }
_pnpmf_homepage() { _fzf_homepage "$(pnpm view "$1" homepage)" }
_pnpmf_rollback() { _pkg_rollback pnpm "$1" }

# ---- 注册表 ----

# base.zsh 已用 typeset -gA 声明过；这里再确认一次，使本文件即使被单独 source
# 也不会把 PKG 变成普通数组（下标里的 ':' 会被当成算术求值）。
[[ ${(t)PKG} == association ]] || typeset -gA PKG

PKG+=(
  'pnpm:title'          'Pnpm'
  'pnpm:views'          'outdated search manage'
  'pnpm:runner'         '_pnpmf_act'

  'pnpm:outdated'       '_pnpmf_list_outdated'
  'pnpm:outdated:title' 'Pnpm Outdated'
  'pnpm:outdated:opt'   '--tiebreak=index'
  'pnpm:outdated:actions' 'update remove rollback homepage deps info'
  'pnpm:outdated:cols' 'name have sep want'

  'pnpm:search'         '_pnpmf_list_available'
  'pnpm:search:title'   'Pnpm Search'
  'pnpm:search:opt'     '--tiebreak=begin,length,index'
  'pnpm:search:actions' 'add rollback homepage deps info'
  'pnpm:search:cols'   'name'

  'pnpm:manage'         '_pnpmf_list_installed'
  'pnpm:manage:title'   'Pnpm Manage'
  'pnpm:manage:actions' 'remove rollback homepage deps info'
  'pnpm:manage:cols'   'name have'

  'pnpm:mutating'           'remove'
  'pnpm:outdated:mutating'  'update remove'
  'pnpm:loop'           'homepage deps info'

  'pnpm:rollback'       '_pnpmf_rollback'
  'pnpm:info'           '_pnpmf_info'
  'pnpm:deps'           '_pnpmf_deps'
  'pnpm:homepage'       '_pnpmf_homepage'
  'pnpm:version-list'     '_pnpmf_version_list'
  'pnpm:version-current'  '_pnpmf_version_current'
  'pnpm:version-install'  '_pnpmf_version_install'
)

pnpmf() {
  # REQUIRE pnpm add -g all-the-package-names
  if ! _fzf_exist all-the-package-names; then
    print -r -- 'Error! please run "pnpm add -g all-the-package-names" first!'
    return 0
  fi
  _pkg_cmd pnpm
}
