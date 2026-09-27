#!/usr/bin/env zsh
# Library file, sourced by fzf-collection.plugin.zsh. No top-level entry point;
# mode 100644.

# ---- List queries: emit name<TAB>rest ----

# Query it once per whole session: the action menu is reopened over and over.
typeset -g _GHF_USER

_ghf_user() {
  [[ -n $_GHF_USER ]] || _GHF_USER=$(gh api user --jq '.login')
  print -r -- "$_GHF_USER"
}

_ghf_list_repos() {
  gh api "users/$(_ghf_user)/repos" --paginate --jq '.[].name'
}

# ---- Action adapters ----

# gh is not a package manager: no rollback / info / deps, and the repository
# detail is fetched on its own by `gh repo view`.
_ghf_act() {
  case $1 in
    delete-repo) gh delete-repo "$(_ghf_user)/$2" ;;
    browse)      gh browse --repo "$(_ghf_user)/$2" ;;
    *)           gh "$1" "$(_ghf_user)/$2" ;;
  esac
}

# ---- Registry ----

_FC_REG+=(
  'gh:title'  'Gh'
  'gh:requires' 'gh'
  'gh:views'  'repos'
  'gh:fallback' '_ghf_act'

  'gh:repos'         '_ghf_list_repos'
  'gh:repos:title'   'Gh Repos'
  'gh:repos:actions' 'delete-repo browse'
  'gh:repos:cols'    'name'

  # No stay key: after browse you go back to the list, so it should not
  # linger in the action menu.
  'gh:mutating' 'delete-repo'
)

# No view menu; go straight to the list. That also means this bypasses
# _fc_cmd, and with it the requirement check every other entry goes through, so
# ghf has to ask for itself.
ghf() {
  _fc_require gh || return 0
  _fc_session gh repos
}
