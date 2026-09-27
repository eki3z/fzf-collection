#!/usr/bin/env zsh
# Library file, sourced by fzf-collection.plugin.zsh. No top-level entry point;
# mode 100644.

# Pull one field out of the indented output of `gem info <name>`, shaped like
#   bigdecimal (1.4.1)
#       Homepage: https://...
# A line only matches when it contains "<field>: ", so take what is after the
# colon and strip the leftover whitespace.
_gemf_extract() {
  local line
  gem info "$1" --exact --prerelease 2>/dev/null | while IFS= read -r line; do
    [[ $line == *"$2: "* ]] || continue
    line=${line#*"$2: "}
    _fc_ltrim line
    print -r -- "$line"
    break
  done
}

# ---- List queries: emit name<TAB>rest ----

# Each `gem info --prerelease` line is `name (1.0.0, 2.0.0.pre)`; several
# installed versions are separated by `, `. Swap that for `|` so multiple
# versions are shown the same way brew shows them.
_gemf_list_installed() {
  local line name vers
  gem info --prerelease | while IFS= read -r line; do
    [[ $line == *' ('*')' ]] || continue
    name=${line%%' ('*}
    vers=${line#*' ('}
    vers=${vers%')'}
    print -r -- "$name${_FC_TAB}${vers//, /|}"
  done
}

# Each `gem outdated` line is `name (1.0.0) < 2.0.0, 3.0.0`. Strip the parens
# and split on whitespace; the last field keeps gem's own `< 2.0.0` notation,
# and the display layer supplies the `=>`.
_gemf_list_outdated() {
  local line name rest cur tail
  gem outdated | while IFS= read -r line; do
    line=${line//[()]/}
    name=${line%% *}
    rest=${line#* }
    cur=${rest%% *}
    tail=${rest#* }
    print -r -- "$name${_FC_TAB}$cur${_FC_TAB}=>${_FC_TAB}$tail"
  done
}

_gemf_list_available() {
  gem search --remote --no-versions
}

# ---- Versions: every argument taken explicitly ----

# Every version, installed or not, one per line. Each
# `gem search X --all --remote --exact` line is
#   json (3.0.2 ruby java, 3.0.1 ruby java, ...)
# so take the part inside the parens and split that on `, `.
_gemf_version_list() {
  local line s
  gem search "$1" --all --remote --exact 2>/dev/null | while IFS= read -r line; do
    [[ $line == *'('*')' ]] || continue
    s=${line##*\(}
    s=${s%\)}
    # Splice the newline in through a variable: the $'\n' inside ${s//, /$'\n'}
    # is not evaluated
    print -r -- "${s//, /$_FC_NL}"
  done
}

# The newest installed version: from `name (v1, v2)`, take everything before the
# first comma (or the closing paren) inside the parens
_gemf_version_current() {
  local line s
  gem info "$1" --exact --prerelease 2>/dev/null | while IFS= read -r line; do
    [[ $line == *'('*')' ]] || continue
    s=${line##*\(}
    print -r -- "${s%%[,)]*}"
    break
  done
}

# $1=pkg $2=target version $3=version from before the rollback. gem lets several
# versions coexist, so an upgrade only has to install the new one, but a
# rollback must first uninstall the current one — otherwise gem sees the
# target version as already installed and skips it.
_gemf_version_install() {
  local dir
  print -r -- "Install $1@$2"
  if [[ -n $3 ]]; then
    dir=$(_gemf_extract "$1" "$3")
    gem uninstall "$1" --version "$3" --executables --install-dir $dir
  fi
  gem install "$1" --version "$2" 2>/dev/null
}

# ---- Action adapters ----

_gemf_rollback() { _fc_rollback gem "$1" }

_gemf_info() { gem info "$1" | _fc_pager }
_gemf_deps() { gem dependency "^$1\$" --prerelease }
_gemf_homepage() { _fc_homepage "$(_gemf_extract "$1" Homepage)" }

# Each mutating action adds the flags gem needs; read-only and unknown actions
# are passed straight through.
_gemf_act() {
  case $1 in
    # No update branch: the action name is upgrade, and update falling through
    # to *) still runs gem update.
    upgrade)    gem update "$2" --prerelease --minimal-deps ;;
    uninstall)  gem uninstall "$2" --all --executables ;;
    install)    gem install "$2" --prerelease ;;
    *)          gem "$1" "$2" ;;
  esac
}

# ---- Registry ----

# The separators are base.zsh's _FC_TAB / _FC_NL; a collection never declares
# globals of its own.

_FC_REG+=(
  'gem:title'   'Gem'
  'gem:requires' 'gem'
  'gem:views'   'outdated search manage'
  'gem:fallback'  '_gemf_act'

  'gem:outdated'       '_gemf_list_outdated'
  'gem:outdated:title' 'Gem Outdated'
  'gem:outdated:fzf-opts'   '--tiebreak=index'
  'gem:outdated:actions' 'upgrade uninstall rollback deps info'
  'gem:outdated:cols'  'name have sep want'

  'gem:search'         '_gemf_list_available'
  'gem:search:title'   'Gem Search'
  # search lists the gems that are **not** installed yet, so uninstall means
  # nothing here and the entry only lives in manage. That leaves this view with
  # no reachable mutating action, so it takes the streaming path (see
  # _fc_view_streamable in base.zsh).
  'gem:search:actions' 'install rollback'
  'gem:search:cols'    'name'

  'gem:manage'         '_gemf_list_installed'
  'gem:manage:title'   'Gem Manage'
  'gem:manage:actions' 'uninstall rollback homepage deps info'
  'gem:manage:cols'    'name have'

  # Actions that drop the row out of the list. rollback deletes no row and only
  # returns to the list, so it is not here.
  'gem:mutating'           'uninstall'
  'gem:outdated:mutating'  'upgrade uninstall'
  # Actions that stay in the action menu: once installed you can carry straight
  # on with the same batch of packages
  'gem:stay'          'install homepage deps info'

  'gem:rollback'  '_gemf_rollback'
  'gem:info'      '_gemf_info'
  'gem:deps'      '_gemf_deps'
  'gem:homepage'  '_gemf_homepage'
  'gem:list-versions'     '_gemf_version_list'
  'gem:current-version'  '_gemf_version_current'
  'gem:install-version'  '_gemf_version_install'
)

gemf() {
  _fc_cmd gem
}
