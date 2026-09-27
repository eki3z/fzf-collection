#!/usr/bin/env zsh
# Library file, sourced by fzf-collection.plugin.zsh. No top-level entry point;
# mode 100644.

# SEE https://gist.github.com/steakknife/8294792

_brewf() {
  # HOMEBREW_NO_INSTALL_FROM_API=1 turns off the API, so brew reads the local
  # tap.
  brew "$@"
}

# ---- List queries: emit name<TAB>rest ----

# Each `brew outdated --verbose` line looks like
#   git (2.30.1) < 2.35.1, 2.36.0 [pinned at 2.30.1]
# Strip the parens, turn `, ` into `|`, then split on whitespace: field 4 holds
# every version we can upgrade to.
_brewf_list_outdated() {
  local line name
  local -a f
  brew update &>/dev/null
  brew outdated --verbose | grep -Fv 'pinned at' | while IFS= read -r line; do
    line=${line//[()]/}
    line=${line//, /|}
    f=(${(z)line})
    (( ${#f} >= 4 )) || continue
    name=${f[1]}
    print -r -- "$name${_FC_TAB}${f[2]}${_FC_TAB}=>${_FC_TAB}${f[4]}"
  done
}

# Each `brew list --versions` line is `name 1.2 3.4`; several versions are
# joined with `|`.
_brewf_list_installed() {
  local line
  local -a f
  _brewf list --versions | while IFS= read -r line; do
    f=(${(z)line})
    (( ${#f} >= 2 )) || continue
    print -r -- "${f[1]}${_FC_TAB}${(j:|:)f[2,-1]}"
  done
}

# `brew ls --pinned --versions` has the same shape as list --versions.
_brewf_list_pinned() {
  local line
  local -a f
  brew ls --pinned --versions | while IFS= read -r line; do
    f=(${(z)line})
    (( ${#f} >= 2 )) || continue
    print -r -- "${f[1]}${_FC_TAB}${(j:|:)f[2,-1]}"
  done
}

_brewf_list_available() {
  brew formulae
  brew casks
}

_brewf_list_tap() { brew tap }

# ---- Rollback ----
# The generic _fc_rollback is not used here: it first has to locate the tap
# directory that holds the formula before it can `git checkout` the single file,
# and that directory is derived from the package name, so this layer brings its
# own. For the same reason the three keys versions / current / install are not
# registered.

_brewf_brewdir() {           # $1=pkg -> directory holding the formula
  local f=$1.rb
  dirname "$(find "$(brew --repository)" -name "$f" | head -n 1)"
}

_brewf_version_current() {   # $1=pkg
  local line
  local -a f
  local -a rows
  rows=(${(f)"$(_brewf list --versions)"})
  for line in $rows; do
    f=(${(z)line})
    [[ ${f[1]:-} == "$1" ]] || continue
    print -r -- "${(j: :)f[2,-1]}"
    return 0
  done
  return 0
}

_brewf_version_list() {      # $1=pkg -> git log, one `hash subject` per line
  local dir
  dir=$(_brewf_brewdir "$1")
  [[ -n $dir ]] || return 0
  git -C "$dir" log --color=always --pretty='format:%C(magenta)%h%C(reset) %s' -- "$1.rb"
}

_brewf_is_pinned() {         # $1=pkg
  local line
  local -a f pins
  pins=(${(f)"$(brew ls --pinned --versions 2>/dev/null)"})
  for line in $pins; do
    f=(${(z)line})
    [[ ${f[1]:-} == "$1" ]] && return 0
  done
  return 1
}

# $1=pkg $2=target commit $3=version from before the rollback
_brewf_checkout() {
  local dir
  dir=$(_brewf_brewdir "$1")
  brew unpin "$1" &>/dev/null
  git -C "$dir" checkout "$2" "$1.rb"
  (HOMEBREW_NO_AUTO_UPDATE=1 && brew reinstall "$1")
  git -C "$dir" checkout HEAD "$1.rb"
  # Pinned before the rollback? Pin it again — look at the real state, not at
  # the view we came from.
  _brewf_is_pinned "$1" && brew pin "$1" &>/dev/null
  return 0
}

_brewf_rollback() {          # $1=pkg
  local pkg=$1 dir old new
  # _fc_fzf_read reads _FC_HEADER through dynamic scoping, so a local here
  # overrides it without touching the outer one.
  local _FC_HEADER="Rollback $pkg"
  dir=$(_brewf_brewdir "$pkg")
  if [[ -z $dir ]]; then
    _fc_msg "No formulae or cask exists." "$pkg" && return 0
  fi
  old=$(_brewf_version_current "$pkg")
  _fc_msg "${old:-Not-installed}" "$pkg"
  # git log is newest-first by default; --tiebreak=index keeps fzf from
  # reordering it.
  new=$(print -l -- ${(f)"$(_brewf_version_list "$pkg")"} \
    | _fc_fzf_read --tiebreak=index --query="$pkg")
  if [[ -z $new ]]; then
    _fc_msg "Rollback cancel." "$pkg" && return 0
    return 0
  fi
  # _fc_fzf_read returns the whole line verbatim, so we have to take the hash
  # ourselves.
  _brewf_checkout "$pkg" "${new%% *}" "$old"
}

# ---- Action adapters ----

_brewf_info() { _brewf info "$1" | _fc_pager }
_brewf_uses() { _brewf uses --installed "$1" }
_brewf_deps() { _brewf deps "$1" --tree }
# ${VISUAL:-${EDITOR:-vi}}: a bare $EDITOR under `setopt nounset` errors with
# parameter not set when it is unset, and nounset is a global option the user
# turned on themselves, so the whole action should not die over it.
# VISUAL wins by convention (the vi / emacs family uses it to override the line
# editing mode of EDITOR).
_brewf_edit() { ${VISUAL:-${EDITOR:-vi}} "$(_brewf formula "$1")" }

# The remaining actions (homepage / options / cat / link / unlink / pin /
# install / tap-info) all fall through to `*)` and are passed through verbatim.
_brewf_act() {
  case $1 in
    upgrade) _brewf upgrade --yes "$2" ;;
    edit)    _brewf_edit "$2" ;;
    uses)    _brewf_uses "$2" ;;
    deps)    _brewf_deps "$2" ;;
    info)    _brewf_info "$2" ;;
    *)       _brewf "$1" "$2" ;;
  esac
}

# ---- Registry ----

_FC_REG+=(
  'brew:title'  'Brew'
  'brew:requires' 'brew'
  'brew:views'  'outdated search manage pinned tap'
  'brew:fallback' '_brewf_act'

  'brew:outdated'       '_brewf_list_outdated'
  'brew:outdated:title' 'Brew Outdated'
  'brew:outdated:fzf-opts'   '--tiebreak=index'
  'brew:outdated:actions' 'upgrade uninstall rollback options homepage info deps uses edit cat'
  'brew:outdated:cols'  'name have sep want'

  'brew:search'         '_brewf_list_available'
  'brew:search:title'   'Brew Search'
  # search lists the formulae/casks that are **not** installed yet, so uninstall
  # (uninstalling a package you do not have) and unpin (there is nothing
  # installed to pin) belong in neither — both are in the manage and pinned
  # views. That leaves this view with no mutating action, so it takes the
  # streaming path (_fc_view_streamable in base.zsh), re-running brew formulae
  # on every return to the list.
  'brew:search:actions' 'install rollback options homepage info deps uses edit cat link unlink pin'
  'brew:search:cols'    'name'

  'brew:manage'         '_brewf_list_installed'
  'brew:manage:title'   'Brew Manage'
  'brew:manage:actions' 'uninstall rollback homepage link unlink pin unpin options info deps uses edit cat'
  'brew:manage:cols'    'name have'

  'brew:pinned'         '_brewf_list_pinned'
  'brew:pinned:title'   'Brew Pinned'
  'brew:pinned:actions' 'unpin rollback uninstall homepage link unlink options info deps uses edit cat'
  'brew:pinned:cols'    'name have'

  'brew:tap'            '_brewf_list_tap'
  'brew:tap:title'      'Brew Tap'
  'brew:tap:actions'    'untap tap-info'
  'brew:tap:cols'       'name'

  # Actions that drop the row out of the list. rollback deletes no row but does
  # return to the list, so it is not here.
  'brew:mutating' 'upgrade uninstall untap unpin'

  # Actions that stay in the action menu. unlink does change brew state and
  # still stays here; keeping the status quo for now.
  'brew:stay' 'install options homepage info deps uses edit cat link unlink pin'

  'brew:rollback' '_brewf_rollback'
)

brewf() {
  _fc_cmd brew
}
