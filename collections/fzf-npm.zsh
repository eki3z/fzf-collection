#!/usr/bin/env zsh
# Library file, sourced by fzf-collection.plugin.zsh. No top-level entry point;
# mode 100644.

# https://docs.npmjs.com/cli/v8/using-npm/config#shorthands-and-other-cli-niceties

_npmf() {
  npm "$1" --quiet --no-fund --no-audit --global "${@:2}"
}

# ---- List queries: emit name<TAB>rest, coloured by _fc_render ----

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

# ---- Versions: every argument taken explicitly ----

_npmf_version_list() {
  npm info "$1" versions --json 2>/dev/null | jq -r 'reverse | .[]' 2>/dev/null
}

# Each line of `npm list --depth 0` is `pkg@version`; only a line containing
# `pkg@` matches, so lines of other packages are never picked up by mistake.
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

# ---- Action adapters ----

_npmf_act() {              # Pass through natively; print a notice before update
  [[ $1 == update ]] && print -r -- "upgrade $2"
  _npmf "$1" "$2"
}

_npmf_info() { npm view "$1" | _fc_pager }
_npmf_deps() { npm view "$1" dependencies }
_npmf_homepage() { _fc_homepage "$(npm view "$1" homepage)" }
_npmf_rollback() { _fc_rollback npm "$1" }

# ---- Registry ----

_FC_REG+=(
  'npm:title'          'Npm'
  'npm:requires'       'npm all-the-package-names'
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
  _fc_cmd npm
}
