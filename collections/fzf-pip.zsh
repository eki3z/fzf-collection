#!/usr/bin/env zsh
# Library file, sourced by fzf-collection.plugin.zsh. No top-level entry point;
# mode 100644.

_pipf() {
  pip3 --disable-pip-version-check "$@"
}

# ---- List queries: emit name<TAB>rest ----

# Each entry of `pip list --format=json` is {"name": ..., "version": ...}.
_pipf_list_installed() {
  _pipf list --format=json | jq -r '.[] | "\(.name)\t\(.version)"'
}

_pipf_list_outdated() {
  _pipf list --format=json --outdated \
    | jq -r '.[] | "\(.name)\t\(.version)\t=>\t\(.latest_version)"'
}

# Scrapes package names out of the pip index page.
_pipf_list_available() {
  # The whole chain has to stay inside C programs: the index page has 870k
  # lines, and grep -o + sed takes about 0.9s.
  # grep -o prints each anchor of a line separately, which is the same as
  # "emit one at a time"; a greedy sed can only emit the last one per line, so
  # grep -o has to cut every anchor apart first.
  curl -s "$(pip config get global.index-url)/" \
    | grep -o '>[^<]*</a>' \
    | sed -e 's/^>//' -e 's|</a>$||'
}

# ---- pip show field extraction (explicit args) ----

# Pull one field out of the `pip show` output, one `Key: value` per line, e.g.
#   Home-page: https://requests.readthedocs.io
#   Requires: certifi, idna, urllib3
# Only a line containing "<key>: " matches; take what follows the colon and
# strip the leftover whitespace.
_pipf_extract() {
  local line
  _pipf show "$1" 2>/dev/null | while IFS= read -r line; do
    [[ $line == *"$2: "* ]] || continue
    line=${line#*"$2: "}
    _fc_ltrim line
    print -r -- "$line"
    break
  done
}

# ---- Versions: every argument taken explicitly ----

_pipf_version_list() {
  local line s
  _pipf index versions --pre "$1" 2>/dev/null | while IFS= read -r line; do
    [[ $line == *'Available versions: '* ]] || continue
    s=${line#*'Available versions: '}
    # Newlines go through the _FC_NL variable: a $'\n' in the replacement is
    # not evaluated, so it would print those four characters verbatim.
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

# ---- Action adapters ----

_pipf_install() {
  _pipf install --user "$@"
}

_pipf_uninstall() {
  if [[ $1 == pip ]]; then
    print -r -- "Package [pip] can not be uninstalled !"
    return 1
  fi
  # Needs `pip install pip-autoremove` first.
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

# ---- Registry ----

# Newlines use _FC_NL from base.zsh; the collection declares no global.

_FC_REG+=(
  'pip:title'          'Pip'
  'pip:requires'       'pip3|pip'
  'pip:views'          'outdated search manage'
  'pip:fallback'         '_pipf_act'

  'pip:outdated'       '_pipf_list_outdated'
  'pip:outdated:title' 'Pip Outdated'
  'pip:outdated:fzf-opts'   '--tiebreak=index'
  'pip:outdated:actions' 'upgrade uninstall rollback deps use info'
  'pip:outdated:cols'  'name have sep want'

  'pip:search'         '_pipf_list_available'
  'pip:search:title'   'Pip Search'
  # search lists packages that are **not installed yet**, so uninstall means
  # nothing here; its entry point stays in manage only.
  # Therefore this view has no reachable mutating action and takes the
  # streaming path (see _fc_view_streamable in base.zsh).
  'pip:search:actions' 'install rollback'
  'pip:search:cols'    'name'

  'pip:manage'         '_pipf_list_installed'
  'pip:manage:title'   'Pip Manage'
  'pip:manage:actions' 'uninstall rollback homepage deps use info'
  'pip:manage:cols'    'name have'

  'pip:mutating'           'uninstall'
  'pip:outdated:mutating'  'upgrade uninstall'
  'pip:stay'           'homepage deps use info'

  'pip:rollback'       '_pipf_rollback'
  'pip:info'           '_pipf_info'
  'pip:deps'           '_pipf_deps'
  'pip:use'            '_pipf_use'
  'pip:homepage'       '_pipf_homepage'
  'pip:list-versions'     '_pipf_version_list'
  'pip:current-version'  '_pipf_version_current'
  'pip:install-version'  '_pipf_version_install'
)

pipf() { _fc_cmd pip }
