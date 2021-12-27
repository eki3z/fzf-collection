#!/usr/bin/env bash

## Uppercase every first letter and downcase other letter in every word in string.
__capitalize_first() {
  sed -E 's/(\w)(\w*)/\U\1\L\2/g' <<<"$1"
}

## Add underline
__underline_string() {
  printf '%s\n' "$1"
  printf '%*s' ${#1} ' ' | sed 's/ /▔/g'
}

## return brewf-* header
_headerf() {
  __underline_string "${1:-$header}"
}

_fzf_single() {
  fzf "${fzf_opts[@]}" "$@"
}

_fzf_multi() {
  fzf "${fzf_opts[@]}" --multi "$@"
}

_fzf_single_header() {
  fzf \
    "${fzf_opts[@]}" \
    --header \
    "$(__underline_string "$header")" \
    "$@"
}

_fzf_multi_header() {
  fzf \
    "${fzf_opts[@]}" \
    --multi \
    --header \
    "$(__underline_string "$header")" \
    "$@"
}
