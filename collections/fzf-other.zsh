#!/usr/bin/env zsh
# Library file, sourced by fzf-collection.plugin.zsh. No top-level entry point;
# mode 100644.

# These two commands (pathf / envf) are not package managers: they have no
# view / action concept, so they are not in the registry, and each one carries
# its own _FC_HEADER.

# _other_format colours the candidates, so fzf has to know that the candidates
# carry SGR sequences: _fc_fzf_read passes --ansi unconditionally. A user who
# overrides it through FZF_COLLECTION_OPTS gets fzf reading \e[34m as 5 ordinary
# characters: no colour, and those 5+4 bytes count towards the display width,
# so long rows get truncated early.

# Everything after the first field: strip the alignment padding and the colour
# codes. fzf's output is already stripped when it runs with --ansi, so the
# _fc_sgr_strip step is only a backstop.
_other_value() {             # $1=line
  local t=${1#"${1%%[[:space:]]*}"}
  _fc_ltrim t
  t=$(_fc_sgr_strip "$t")
  print -r -- "$t"
}

# ---- Table layout: a reimplementation of column -t ----

# The layout needs the palette, so these two functions call base.zsh's
# _fc_sgr_prefix. The first field goes through verbatim, everything after it is
# merged into one segment and painted blue, and the row is aligned by the width
# of the first field.
_other_format() {          # first field verbatim, the rest merged and blue
  local line first rest
  local pre post
  # The marker between the first field and the merged segment. It must not look
  # like whitespace, or _other_align cannot tell "split on it" from "split on
  # whitespace".
  local sep='^^'
  local -a lines out
  # The colouring is resolved once outside the loop: the colour codes are the
  # same on every row, while a per-row _fc_sgr_paint is one command substitution
  # per row. pre / post are kept apart so the suffix is empty when nothing is
  # painted, otherwise a bare \e[0m would be left behind.
  _fc_sgr_prefix have
  pre=$_FC_SGR_PREFIX
  if [[ -n $pre ]]; then post=$_FC_SGR_RESET; else post=''; fi
  # When the last line has no newline read returns non-zero but still fills the
  # variable, so an extra check is needed.
  while IFS= read -r line || [[ -n $line ]]; do lines+=("$line"); done
  # Print nothing when the input is all blank lines.
  local any=0
  for line in "${lines[@]}"; do
    [[ -n ${line//[[:space:]]/} ]] && { any=1; break; }
  done
  (( any )) || return 0
  for line in "${lines[@]}"; do
    _fc_ltrim line
    first=${line%%[[:space:]]*}
    rest=${line#"$first"}
    # Everything after the first field is reassembled on whitespace: tabs and
    # runs of spaces are both squeezed into a single space.
    rest=${rest//[[:space:]]/ }
    while [[ $rest == *"  "* ]]; do rest=${rest//  / }; done
    while [[ $rest == ' '* ]]; do rest=${rest# }; done
    while [[ $rest == *' ' ]]; do rest=${rest% }; done
    out+=("$first$sep$pre$rest$post")
  done
  print -rl -- "${out[@]}" | _other_align "$sep"
}

# Align into a table on the separator: drop blank lines -> cut the columns ->
# pad every column to that column's maximum width -> 2 spaces between columns ->
# the last column is not padded. $1 is the optional separator: given, cut on it
# (a reimplementation of `column -s X -t`); omitted, cut on whitespace (a
# reimplementation of `column -s ' ' -t`).

# A few counter-intuitive details: consecutive separators count as one, and
# **empty fields are dropped entirely** (they take no width and no gap); the
# column numbering follows the number of surviving fields; whitespace mode
# strips each row's leading whitespace and collapses runs of spaces, while a
# specified separator mode does not strip; a tab is **not** a separator in
# whitespace mode (`-s ' '` only means a literal space).

# Known limitation: column measures display width, zsh's ${#} counts characters,
# so alignment drifts when wide characters are involved. Every field of the
# current callers is ASCII.
_other_align() {          # $1=optional separator
  local delim=$1 line cell
  local -a rows cells keep widths
  local i

  while IFS= read -r line; do
    if [[ -n $delim ]]; then
      [[ -n $line ]] || continue
    else
      while [[ $line == ' '* ]]; do line=${line# }; done
      while [[ $line == *' ' ]]; do line=${line% }; done
      [[ -n $line ]] || continue
      while [[ $line == *"  "* ]]; do line=${line//  / }; done
    fi
    rows+=("$line")
  done

  widths=()
  for line in "${rows[@]}"; do
    cells=()
    if [[ -n $delim ]]; then
      # With the separator in a variable ${(s:$delim)var} does not expand (a
      # flag argument is a literal), so substitute newlines first and then cut
      # by line. $delim is quoted so that it is not taken as a glob.
      keep=("${(@f)${line//"$delim"/$_FC_NL}}")
    else
      keep=("${(@s: :)line}")
    fi
    # column drops empty fields entirely: no width and no gap, and the column
    # numbering follows the surviving fields.
    for cell in "${keep[@]}"; do
      [[ -n $cell ]] && cells+=("$cell")
    done
    for (( i = 1; i <= ${#cells}; i++ )); do
      (( ${#cells[i]} > ${widths[i]:-0} )) && widths[i]=${#cells[i]}
    done
  done

  for line in "${rows[@]}"; do
    cells=()
    if [[ -n $delim ]]; then
      keep=("${(@f)${line//"$delim"/$_FC_NL}}")
    else
      keep=("${(@s: :)line}")
    fi
    for cell in "${keep[@]}"; do
      [[ -n $cell ]] && cells+=("$cell")
    done
    line=''
    for (( i = 1; i <= ${#cells}; i++ )); do
      if (( i < ${#cells} )); then
        line+="${(r:${widths[i]}:: :)${cells[i]}}  "
      else
        line+="${cells[i]}"
      fi
    done
    print -r -- "$line"
  done
}

# [P]ath [F]ind
# -d prints directories only, without the file name.

pathf() {
  local _FC_HEADER line dir
  local i
  # Calling it with no arguments is the normal usage, so $1 has to be taken as
  # ${1:-}: a bare $1 reports "parameter not set" right away under
  # `setopt nounset`, which makes pathf unusable altogether.
  local opt=${1:-}
  # pathf is not an ecosystem, so it has no registry key; it declares what it
  # needs here. fzf has to be listed too because it does not go through
  # _fc_require, which is where the other commands get it.
  _fc_need fzf find uniq || return 0
  _FC_HEADER="Find Path"

  for i in "${(@s.:.)PATH}"; do
    if [ -d "$i" ]; then
      # -H keeps the symlink at root_path resolving as usual:
      # https://www.gnu.org/software/findutils/manual/html_node/find_html/Symbolic-Links.html
      find -H "$i" -maxdepth 1 -executable -type f,l -printf "%f ${i/$HOME/~}\n"
    fi
  done \
    | _other_format \
    | uniq \
    | _fc_fzf_read --tiebreak=index \
    | while IFS= read -r line; do
        # This while has to sit in the pipeline: written as a statement of its
        # own it reads the function's own stdin, not fzf's output.
        dir=$(_other_value "$line")
        [[ $dir == '~'* ]] && dir=$HOME${dir#\~}
        if [[ $opt == "-d" ]]; then
          print -r -- "$dir/"
        else
          print -r -- "$dir/${line%%[[:space:]]*}"
        fi
      done
}

# [E]nv

envf() {
  # key / val are for the while below, and all of them are declared here: a
  # scalar local inside a loop body prints an assignment line to stdout, which
  # mixes into the candidates (zsh 5.9).
  local _FC_HEADER rec line key val
  local valmax=${_ENVF_VALMAX:-$_FC_ENVF_WIDTH}
  # Same as pathf: not an ecosystem, no registry key, so it declares its own
  # requirements -- fzf included, since _fc_require is not on this path.
  _fc_need fzf printenv sort || return 0
  _FC_HEADER="Env"

  # Reading NUL-separated is what keeps a value containing newlines from being
  # split into two records; zsh's read -d handles NUL, so tr is not needed.
  # Once read in, newlines are squeezed into spaces and key / val are cut on
  # the first =.

  # The display layer cuts the value to valmax characters ($_ENVF_VALMAX, 80 by
  # default). It has to: PATH's value measured 1994 characters, and FPATH /
  # LS_COLORS / __MISE_ZSH_ACTIVATE_PATH are all wider than the screen too, so
  # fzf can only scroll sideways, a row then looks like it holds nothing but its
  # tail, and the whole list looks misaligned. The truncation only affects the
  # display; after a selection the full value is read out of the environment by
  # key.
  while IFS= read -r -d $'\0' rec; do
    rec=${rec//$'\n'/ }
    [[ $rec == *=* ]] || continue
    key=${rec%%=*}
    val=${rec#*=}
    if (( ${#val} > valmax )); then
      val="${val[1,$valmax]}..."
    fi
    print -r -- "$key $val"
  done < <(printenv --null) \
    | sort -u \
    | _other_format \
    | _fc_fzf_read \
    | while IFS= read -r line; do
        # The value on the display row has already been truncated, so the full
        # value is read out of the environment by key. Existence is tested with
        # parameters, not by "is ${(P)key} empty": an environment variable with
        # an empty value is legal, and that test would fall back to the
        # truncated value.
        key=${line%%[[:space:]]*}
        if (( ${+parameters[$key]} )); then
          print -r -- "$key = ${(P)key}"
        else
          print -r -- "$key = $(_other_value "$line")"
        fi
      done
}
