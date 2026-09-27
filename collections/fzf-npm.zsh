#!/usr/bin/env zsh
# 上面这行是文件元数据（供编辑器与格式化工具识别），不是解释器指令。
# 本文件是库文件，由 fzf-collection.plugin.zsh 以 source 方式加载。
# 它仅含函数定义、无顶层入口，即使赋予执行权限直接运行也只会是空操作，
# 且缺少 base.zsh 的依赖必然失败。文件模式保持 100644，不要 chmod +x。

# https://docs.npmjs.com/cli/v8/using-npm/config#shorthands-and-other-cli-niceties

_npmf() {
  npm "$1" --quiet --no-fund --no-audit --global "${@:2}"
}

# ---- 列表查询：输出 name<TAB>rest，由 _pkg_render 上色 ----

_npmf_list_outdated() {
  _npmf outdated --json \
    | jq -r 'to_entries[] | "\(.key)\t\(.value.current)\t=>\t\(.value.latest)"'
}

_npmf_list_installed() {
  _npmf list --json \
    | jq -r '.dependencies | to_entries[] | "\(.key)\t\(.value.version)"'
}

_npmf_list_available() {
  all-the-package-names
}

# ---- 版本相关：全部显式收参，不再读调用者作用域 ----

_npmf_version_list() {
  npm info "$1" versions --json 2>/dev/null | jq -r 'reverse | .[]' 2>/dev/null
}

# `npm list --depth 0` 每行是 `pkg@version`，取自己那个 pkg 的版本。
# 原来用 perl 的 \Q$pkg\E@ 锚定；zsh 里用同样的字面匹配，
# 整行含 $pkg@ 才会命中，所以别的包的行不会被误取。
_npmf_version_current() {
  local line
  _npmf list --depth 0 2>/dev/null | while IFS= read -r line; do
    [[ $line == *"$1@"* ]] || continue
    print -r -- "${line#*"$1"@}"
    break
  done
}

_npmf_version_install() {
  print -r -- "Install $1@$2"
  _npmf install "$1@$2" 2>/dev/null
}

# ---- 动作适配器 ----

_npmf_act() {              # 原生透传，保留旧驱动 update 前的提示
  [[ $1 == update ]] && print -r -- "upgrade $2"
  _npmf "$1" "$2"
}

_npmf_info() { npm view "$1" | _fzf_pager }
_npmf_deps() { npm view "$1" dependencies }
_npmf_homepage() { _fzf_homepage "$(npm view "$1" homepage)" }
_npmf_rollback() { _pkg_rollback npm "$1" }

# ---- 注册表 ----

# base.zsh 已用 typeset -gA 声明过；这里再确认一次，使本文件即使被单独 source
# 也不会把 PKG 变成普通数组（下标里的 ':' 会被当成算术求值）。
[[ ${(t)PKG} == association ]] || typeset -gA PKG

PKG+=(
  'npm:title'          'Npm'
  'npm:views'          'outdated search manage'
  'npm:runner'         '_npmf_act'

  'npm:outdated'       '_npmf_list_outdated'
  'npm:outdated:title' 'Npm Outdated'
  'npm:outdated:opt'   '--tiebreak=index'
  'npm:outdated:actions' 'update uninstall rollback homepage deps info'
  'npm:outdated:cols'  'name have sep want'

  'npm:search'         '_npmf_list_available'
  'npm:search:title'   'Npm Search'
  'npm:search:opt'     '--tiebreak=begin,length,index'
  'npm:search:actions' 'install rollback homepage deps info'
  'npm:search:cols'    'name'

  'npm:manage'         '_npmf_list_installed'
  'npm:manage:title'   'Npm Manage'
  'npm:manage:actions' 'uninstall rollback homepage deps info'
  'npm:manage:cols'    'name have'

  'npm:mutating'           'uninstall'
  'npm:outdated:mutating'  'update uninstall'
  'npm:loop'           'homepage deps info'

  'npm:rollback'       '_npmf_rollback'
  'npm:info'           '_npmf_info'
  'npm:deps'           '_npmf_deps'
  'npm:homepage'       '_npmf_homepage'
  'npm:version-list'     '_npmf_version_list'
  'npm:version-current'  '_npmf_version_current'
  'npm:version-install'  '_npmf_version_install'
)

npmf() {
  # REQUIRE npm install -g all-the-package-names
  if ! _fzf_exist all-the-package-names; then
    print -r -- 'Error! please run "npm i -g all-the-package-names" first!'
    return 0
  fi
  _pkg_cmd npm
}
