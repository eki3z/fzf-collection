#!/usr/bin/env zsh
# 库文件，由 fzf-collection.plugin.zsh source 加载；无顶层入口，模式 100644。

# https://docs.npmjs.com/cli/v8/using-npm/config#shorthands-and-other-cli-niceties

_npmf() {
  npm "$1" --quiet --no-fund --no-audit --global "${@:2}"
}

# ---- 列表查询：输出 name<TAB>rest，由 _fc_render 上色 ----

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

# ---- 版本相关：全部显式收参 ----

_npmf_version_list() {
  npm info "$1" versions --json 2>/dev/null | jq -r 'reverse | .[]' 2>/dev/null
}

# `npm list --depth 0` 每行是 `pkg@version`；整行含 `pkg@` 才命中，所以别的包
# 的行不会被误取。
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

_npmf_act() {              # 原生透传；update 之前先打一行提示
  [[ $1 == update ]] && print -r -- "upgrade $2"
  _npmf "$1" "$2"
}

_npmf_info() { npm view "$1" | _fc_pager }
_npmf_deps() { npm view "$1" dependencies }
_npmf_homepage() { _fc_homepage "$(npm view "$1" homepage)" }
_npmf_rollback() { _fc_rollback npm "$1" }

# ---- 注册表 ----

_FC_REG+=(
  'npm:title'          'Npm'
  'npm:views'          'outdated search manage'
  'npm:fallback'         '_npmf_act'

  'npm:outdated'       '_npmf_list_outdated'
  'npm:outdated:title' 'Npm Outdated'
  'npm:outdated:fzf-opts'   '--tiebreak=index'
  'npm:outdated:actions' 'update uninstall rollback homepage deps info'
  'npm:outdated:cols'  'name have sep want'

  'npm:search'         '_npmf_list_available'
  'npm:search:title'   'Npm Search'
  'npm:search:fzf-opts'     '--tiebreak=begin,length,index'
  'npm:search:actions' 'install rollback homepage deps info'
  'npm:search:cols'    'name'

  'npm:manage'         '_npmf_list_installed'
  'npm:manage:title'   'Npm Manage'
  'npm:manage:actions' 'uninstall rollback homepage deps info'
  'npm:manage:cols'    'name have'

  'npm:mutating'           'uninstall'
  'npm:outdated:mutating'  'update uninstall'
  'npm:stay'           'homepage deps info'

  'npm:rollback'       '_npmf_rollback'
  'npm:info'           '_npmf_info'
  'npm:deps'           '_npmf_deps'
  'npm:homepage'       '_npmf_homepage'
  'npm:list-versions'     '_npmf_version_list'
  'npm:current-version'  '_npmf_version_current'
  'npm:install-version'  '_npmf_version_install'
)

npmf() {
  # REQUIRE npm install -g all-the-package-names
  if ! _fc_have_cmd all-the-package-names; then
    print -r -- 'Error! please run "npm i -g all-the-package-names" first!'
    return 0
  fi
  _fc_cmd npm
}
