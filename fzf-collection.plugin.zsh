#!/usr/bin/env zsh
# The only entry point, loaded by oh-my-zsh (or by sourcing it by hand).
# ${0:h:A} locates this file and sources the body below; the body is all zsh
# code.

# set options if not defined
if [[ -z ${FZF_COLLECTION_OPTS:-} ]]; then
  FZF_COLLECTION_OPTS="
  --header-first
  --ansi
  --reverse
  --cycle
  --no-multi
  --sort
  --exact
  --info=inline
  --tiebreak=begin,index
  --bind=change:first,btab:up+toggle,ctrl-n:down,ctrl-p:up
  --bind=ctrl-u:cancel,ctrl-l:jump,ctrl-t:toggle-all,ctrl-v:clear-selection"
fi

if [[ -z ${FZF_COLLECTION_MODULES:-} ]]; then
  FZF_COLLECTION_MODULES=(
    brew
    npm
    pnpm
    pip
    uv
    gem
    gh
    other
  )
fi

source "${0:h:A}/base.zsh"

# ---- Colour switch ----
#
# Computed once at load time. It cannot be tested in the display layer: that
# layer's stdout is a pipe into fzf, where [[ -t 1 ]] is always false, which
# would switch colour off entirely.
#
# Precedence: FZF_COLLECTION_COLOR=0|1 > a non-empty NO_COLOR > an empty or dumb
# TERM > [[ -t 1 ]]. When it is off _fc_sgr_prefix emits nothing at all, the row
# content is byte-for-byte the same as when it is on, just without the escapes.
typeset -gi _FC_COLOR=1
if [[ -z ${FZF_COLLECTION_COLOR:-} ]]; then
  if [[ -n ${NO_COLOR:-} ]] || [[ ${TERM:-dumb} == dumb ]] || [[ ! -t 1 ]]; then
    _FC_COLOR=0
  fi
else
  [[ ${FZF_COLLECTION_COLOR} == 0 ]] && _FC_COLOR=0 || _FC_COLOR=1
fi

for f in "${FZF_COLLECTION_MODULES[@]}"; do
  source "${0:h:A}/collections/fzf-${f}.zsh"
done
