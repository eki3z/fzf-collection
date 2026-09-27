#!/usr/bin/env zsh
# Library file, sourced by fzf-collection.plugin.zsh. No top-level entry point;
# mode 100644.

# FZF_COLLECTION_OPTS is a string, split on whitespace into an array. ${=var} is
# zsh's flag that forces word splitting.
typeset -ga _FC_OPTS=(${=FZF_COLLECTION_OPTS})

_fc_have_cmd() {
  command -v "$@" &>/dev/null
}

# Strip leading whitespace, rewriting in place. $1 is a variable NAME, not a value.
#
# In place because _other_format calls it once per line and a return value would
# need a command substitution per line (pathf has ~4900 lines). eval because zsh
# 5.9 has no nameref. localoptions because ${s##[[:space:]]#} needs extendedglob:
# without it there is no error, it just silently strips nothing.
_fc_ltrim() {              # $1=variable name
  setopt localoptions extendedglob
  eval "$1=\${$1##[[:space:]]#}"
}

# $1=message $2=label (what triggered it, usually a package name). The label must
# be passed explicitly.
_fc_msg() {
  printf "\n%s: %s\n" "$(_fc_sgr_paint msg "${2:-fzf-collection}")" "$1"
}

_fc_pager() {
  local pager
  pager="${PAGER:-less}"
  if [ "$pager" = "less" ] && _fc_have_cmd less; then
    less -R
  elif _fc_have_cmd "$pager"; then
    $pager
  else
    cat
  fi
}

# Draw a rule of the same length under the title.
# SEE https://stackoverflow.com/a/68093509/13194984
_fc_rule() {
  printf -- '%s\n' "$1"
  printf -- '▔%.0s' {1..$#1}
}

_fc_homepage() {
  if [ -n "$1" ]; then
    echo "Open: $1 ..."
    open "$1"
  else
    echo "No homepage."
  fi
}

# ---- Defaults for the overridable knobs ----
#
# These three are the defaults behind documented environment variables; every call
# site spells ${_ENV_VAR:-$_FC_...}. The environment variable is an override, not
# a requirement.
#
#   _FC_ENVF_WIDTH      How wide envf shows a value. 80 suits a narrow terminal;
#                       PATH runs to thousands of characters, so raise it on a
#                       wide one.
#   _FC_PYPI_INDEX      The index page uvf's search scrapes names from. Anyone on
#                       a mirror must change it, and it cannot be discovered:
#                       uv has no subcommand that prints the index it resolved.
#   _FC_PYPI_JSON_BASE  Root of the PyPI JSON API, used by list-versions / info /
#                       deps / homepage. **Deliberately NOT following
#                       _FC_PYPI_INDEX**: a mirror's JSON snapshot can be very
#                       stale (tuna's ruff was still 0.5.7 while PyPI was 0.16.9),
#                       and these four need fresh metadata -- otherwise rollback
#                       offers versions that cannot be installed.
typeset -g _FC_ENVF_WIDTH=80
typeset -g _FC_PYPI_INDEX='https://pypi.org/simple'
typeset -g _FC_PYPI_JSON_BASE='https://pypi.org/pypi'

# ---- Colour and SGR ----
#
# CSI sequences appear only in this section. Painting goes through
# _fc_sgr_prefix, stripping through _fc_sgr_strip, and switching theme means
# editing _FC_SGR and nothing else.

# Separators. TAB and newline must land in variables first: inside a replacement
# or a flag argument $'\n' is a literal, so without a variable those characters
# would be printed as-is. Must be declared at file top level: a scalar local
# inside a loop body makes zsh 5.9 print an assignment line to stdout, which
# becomes a bogus candidate.
typeset -g _FC_TAB=$'\t'
typeset -g _FC_NL=$'\n'

# Palette: role name -> SGR prefix. Role names rather than colour names, so that
# cols reads as self-documenting ('name have sep want') and a theme change is a
# change to this one table.
#
# An empty value means "explicitly no colour", not "not configured". That is why
# the resolver must look the key up with [[ -v ]]: testing the value for
# emptiness would silently degrade a typo just like `name` does.
typeset -gA _FC_SGR=(
  name ''          # package name / first field
  have $'\e[34m'   # installed version, description text
  sep  ''          # a connector like '=>'
  want $'\e[33m'   # target version
  msg  $'\e[34m'   # _fc_msg's label
)
# Warn once per session about an unknown role name, and warn BEFORE the colour
# switch is consulted: a misconfiguration should be reported even when colour is
# off. De-duplication relies on this flag being assigned in the current shell, so
# _fc_sgr_prefix has to go through an output variable.
typeset -gi _FC_SGR_WARNED=0
# _fc_sgr_prefix's output. The result lands in a global; the function neither
# prints nor forks.
typeset -g _FC_SGR_PREFIX=''

# $'\e[34m' inside double quotes is not evaluated (same as $'\n'), so it has to
# land in a variable first.
typeset -g _FC_SGR_RESET=$'\e[0m'

# Resolve a colour spec (a key of _FC_SGR) into _FC_SGR_PREFIX. An empty result
# means "do not paint". Goes through an output variable rather than print +
# $(...): a command substitution runs in a subshell, _FC_SGR_WARNED's assignment
# would not come back out, and de-duplication would stop working.
#
# A spec only accepts role names. Whether a role is painted is the palette's
# value, not something the spec spells.
_fc_sgr_prefix() {            # $1=spec
  local s=$1
  _FC_SGR_PREFIX=''
  [[ -n $s ]] || return 0
  # Block ']' first: in [[ -v _FC_SGR[$s] ]] zsh evaluates what is inside the
  # brackets as a subscript expression, and a spec is data from the registry.
  if [[ $s == *[^a-z0-9_-]* ]] || [[ ! -v _FC_SGR[$s] ]]; then
    if (( ! _FC_SGR_WARNED )); then
      _FC_SGR_WARNED=1
      print -ru2 -- "fzf-collection: unknown colour role '${s}', treating it as no colour"
    fi
    return 0
  fi
  s=${_FC_SGR[$s]}
  # Validity first, switch second: a misconfiguration must be reported even when
  # colour is off.
  (( _FC_COLOR )) || return 0
  _FC_SGR_PREFIX=$s
}

# Paint text and print it unchanged otherwise. Entry layer only -- **do not** call
# it per cell: a command substitution per cell forks per cell, which measured
# 51s for 20k rows x 4 columns against 0.3s for plain concatenation. For per-row
# or per-column work, resolve the prefix once outside the loop and concatenate
# inside it -- see _other_format and _fc_render.
_fc_sgr_paint() {             # $1=spec $2=text
  local p
  _fc_sgr_prefix "$1"
  p=$_FC_SGR_PREFIX
  [[ -n $p ]] || { print -r -- "$2"; return 0 }
  print -r -- "$p$2$_FC_SGR_RESET"
}

# Strip every SGR sequence from a line. extendedglob is required:
# ${1//$'\e'\[[0-9;]#m/} does not match under zsh 5.9 (the [ in flag position is
# read as a bracket expression), while ${1//$'\e'\[[0-9;]*m/} over-matches,
# greedily eating the whole line up to the last m.
_fc_sgr_strip() {           # $1=line
  setopt localoptions extendedglob
  print -r -- "${1//$'\e'\[[0-9;]#m/}"
}

# ---- Driver layer ----
#
# All seven package-manager collections come through here:
#   - the list is structured lines, name<TAB>f2<TAB>...
#   - one query per session, cached in _FC_ROWS; rows are dropped from memory
#     after an action
#   - exception: a single-column view with no mutating action streams instead,
#     see _fc_view_streamable
#   - no temporary files under /tmp
#   - function dispatch is an indirect expansion, "$fn" (zsh's nameref cannot
#     dispatch a function)
#
# pathf and envf do not come through here: they are not package managers and
# have no view / action concept.

# -g is deliberate: when this file is sourced from inside a function, a plain
# typeset would make _FC_REG local, and after the function returns the ':' in a
# subscript would be evaluated as arithmetic -- "bad math expression".
#
# This is the only place in the repo that declares _FC_REG: a collection assumes
# the load path of this file declared it first.
typeset -gA _FC_REG         # registry: _FC_REG[<eco>[:<view>]][:<field>] = value
typeset -ga _FC_ROWS    # the current session's list, owned by _fc_session
typeset -ga _FC_FIELDS # _fc_split_row's output
typeset -gi _FC_STREAM # 1 = the current view takes the streaming path (used by
                       # _fc_feed), see _fc_view_streamable

# These five used to be out of place: _FC_ACTIONS / _FC_MUTATING were created
# implicitly by assignment (never declared at top level), and _FC_PICKED /
# _FC_DONE / _FC_FAILED were declared inside the body of _fc_session. All of them
# therefore existed only after their first call, so under nounset reading them
# before a session terminated the script outright -- measured: _t_snapshot in
# tests/cases.sh died there and not a single case ran.
#
# Declaring them at top level also fixes the other half of nounset: places where
# the driver itself reads _FC_STREAM and friends no longer depend on "who ran
# first".
typeset -ga _FC_ACTIONS _FC_MUTATING
typeset -ga _FC_PICKED _FC_DONE _FC_FAILED
typeset -gi _FC_PENDING _FC_RC

# The current screen's title, set by _fc_cmd / _fc_session, read by
# _fc_fzf_read.
#
# A global rather than a parameter, and **please do not turn it back into a
# parameter**: three places read the title (the action submenu, rollback's
# version picker, the view menu) and all of them sit behind the dispatch chain
# _fc_apply -> _fc_act -> handler, so threading it through would add a parameter
# to five signatures while most handlers do not care about it.
typeset -g _FC_HEADER=''

# Registry read. The key must be assembled in a variable before it is used as a
# subscript: ${_FC_REG[$eco:title]} makes zsh read ':t' as the `tail` modifier
# and silently return empty. The fields that have bitten this way: title / stay /
# fallback / homepage / rollback / search / tap.
_fc_reg_get() {
  local key=$1 part
  shift
  for part in "$@"; do key="${key}:${part}"; done
  [[ -n ${_FC_REG[$key]:-} ]] && print -r -- "${_FC_REG[$key]}"
}

# Read a view-level field _FC_REG[<eco>:<view>:<field>]. Split into its own
# function to keep the segment order in one place: _fc_reg_get means "whatever
# follows eco", so using it for a view field builds eco:actions:view, silently
# returns empty, and pressing enter then has no submenu to open.
_fc_reg_view_get() {           # $1=eco $2=view $3=field
  local key=$1
  key="${key}:${2}:${3}"
  [[ -n ${_FC_REG[$key]:-} ]] && print -r -- "${_FC_REG[$key]}"
}

# Join items with ", " on stdout. Written out rather than done with ${(j:, )@}:
# flags are themselves comma-separated, so a ',' inside a flag's JOIN argument
# is a flag error at runtime, and ${(j: :)@} would join with a bare space.
_fc_list() {                 # $@=items
  local out='' item sep=''
  for item in "$@"; do
    out+="${sep}${item}"
    sep=', '
  done
  print -r -- "$out"
}

# Say what is missing, in one wording. $@=the commands that were not found.
_fc_missing() {
  print -r -- "fzf-collection: missing $(_fc_list "$@")."
  print -r -- "  Install $(_fc_list "$@") and try again."
}

# Check a list of requirement specs and say what is missing. $@=specs, where a
# spec is either a command that must exist or a '|'-separated list of
# alternatives of which one must exist. Prints nothing and returns 0 when
# everything is there.
_fc_need() {
  local spec alt
  local -a missing
  missing=()
  for spec in "$@"; do
    if [[ $spec == *'|'* ]]; then
      for alt in ${(s:|:)spec}; do
        _fc_have_cmd "$alt" && continue 2
      done
      missing+=("$spec")
    elif ! _fc_have_cmd "$spec"; then
      missing+=("$spec")
    fi
  done
  (( ${#missing} )) || return 0
  _fc_missing "${missing[@]}"
  return 1
}

# Check an ecosystem's declared requirements: the registry key is
# '<eco>:requires', a space-separated list of the same specs _fc_need takes.
#
# fzf is checked here rather than listed in each ecosystem, because every
# command needs it and repeating it seven times is seven places to forget.
#
# **Returns 0 whether or not the check passed**, and so does every *f command on
# every path (a cancelled session is 0, see _fc_cmd): the exit code carries no
# information anywhere, and making this one case return 1 would only make "the
# user pressed Ctrl-C" and "the session never started" disagree. Callers just
# `return` when this fails.
_fc_require() {                 # $1=eco
  local req
  local -a reqs
  req=$(_fc_reg_get "$1" requires)
  # ${(s: :)req} with no `$` inside the braces: ${(s: :)$req} reports "bad
  # substitution". The form used everywhere else here, ${(s: :)$(...)}, only
  # works because a command substitution is what follows the flag. An empty req
  # would split into one empty element, which would then be reported as a missing
  # command, so it is left as an empty array instead.
  (( ${#req} )) && reqs=(${(s: :)req})
  _fc_need fzf "${reqs[@]}"
}

# The fzf read. The only place in the repo that invokes fzf. The exit code is
# passed through; callers rely on it to tell a selection from a cancel.
#
# Three options can only be given here:
#   --tabstop=1  the row convention is "tab = column separator, rendered as
#                exactly one space"; column alignment is done by padding in
#                _fc_render, not left to the tab stop
#   --ansi       candidate rows carry SGR sequences. Without it fzf reads
#                \e[34m as 5 ordinary characters: no colour, and those 5+4
#                bytes count towards the display width, so long rows get
#                truncated early
#   --header     taken from _FC_HEADER
_fc_fzf_read() {
  fzf "${_FC_OPTS[@]}" --tabstop=1 --ansi \
    --header "$(_fc_rule "$_FC_HEADER")" "$@"
}

# Split a line on tabs. ${(ps:\t:)var} cannot be used: a flag argument does not
# accept $'\t'.
_fc_split_row() {        # $1=line -> _FC_FIELDS
  local rest=$1
  _FC_FIELDS=()
  while :; do
    case $rest in
      *$'\t'*) _FC_FIELDS+=("${rest%%$'\t'*}"); rest=${rest#*$'\t'} ;;
      *)       _FC_FIELDS+=("$rest"); break ;;
    esac
  done
}

# Display layer: render _FC_ROWS (clean name<TAB>f2<TAB>...) into aligned rows
# with per-column colouring.
#
# The column count and the colours come from <eco>:<view>:cols, space
# separated, one role name per column:
#   'name have sep want'   outdated's four columns
#   'name have'            manage's two columns
#   'name'                 a single column, i.e. search
# An undeclared cols is treated as a single column.
#
# Each column is padded to that column's maximum width, the last one is not
# (to avoid trailing whitespace). The padding occupies its own tab segment, so
# the name that ${line%%$'\t'*} yields is naturally clean; together with
# --tabstop=1 that reproduces `column -t` alignment.
_fc_render() {           # $1=eco $2=view (both optional; omitted = single column)
  # ${1:-} / ${2:-} rather than bare $1 / $2: this function can be called with
  # no arguments (that is exactly the no-cols single-column meaning), and a bare
  # positional parameter that was not passed reports "parameter not set" under
  # nounset, turning the whole render into empty output. The driver always passes
  # two (see _fc_feed), so this only matters on a direct call.
  local eco=${1:-} view=${2:-}
  local line cell seg out k first w
  local -a cols widths flds segs
  local -a pre post
  local i nf n
  # Every local is declared at the top of the function and **never** inside a
  # loop body: under zsh 5.9 a scalar local executed in a loop body prints a
  # `NAME=<value>` line to stdout, and this function's stdout feeds fzf
  # directly, so that line would become a bogus candidate.
  local -i csep=${_FC_COLUMN_GAP:-5}

  n=${#_FC_ROWS}
  (( n )) || return 0

  cols=(${(s: :)$(_fc_reg_view_get "$eco" "$view" cols)})
  nf=$#cols
  (( nf )) || { cols=(name); nf=1 }

  # The per-column prefix and suffix are resolved once here so the loop only
  # concatenates strings: one _fc_sgr_paint per cell is one fork per cell,
  # measured 51s against 0.28s.
  #
  # The width pre-scan still runs after padding and before colouring -- colour
  # codes do not count towards ${#cell}, so alignment and colour do not disturb
  # each other.
  for (( i = 1; i <= nf; i++ )); do
    _fc_sgr_prefix "${cols[i]}"
    pre[i]=$_FC_SGR_PREFIX
    if [[ -n ${pre[i]} ]]; then post[i]=$_FC_SGR_RESET; else post[i]=''; fi
  done

  widths=()
  for (( i = 1; i <= nf; i++ )); do widths[i]=0; done
  # A single column never uses widths (padding only happens in the i < nf branch,
  # and a single column has no such branch), so the whole pre-scan can be
  # skipped: it would walk the entire table a second time, which is 3-4s wasted
  # on 40k rows.
  if (( nf > 1 )); then
    for line in "${_FC_ROWS[@]}"; do
      _fc_split_row "$line"
      flds=("${_FC_FIELDS[@]}")
      for (( i = 1; i <= nf; i++ )); do
        cell=${flds[i]:-}
        (( ${#cell} > widths[i] )) && widths[i]=${#cell}
      done
    done
  fi

  for line in "${_FC_ROWS[@]}"; do
    _fc_split_row "$line"
    flds=("${_FC_FIELDS[@]}")
    segs=()
    for (( i = 1; i <= nf; i++ )); do
      cell=${flds[i]:-}
      if (( i == 1 )); then
        # The name is left as it is and the padding gets a tab segment of its
        # own, so reading the name back needs no space stripping. For a single
        # column (search and friends) there is no following column, so a padding
        # segment would only leave a trailing tab and spaces on every row --
        # ugly, and it makes fzf's matching count that trailing whitespace.
        #
        # ${(l:N:: :)} evaluates to an empty string, so it is not "left-align
        # some value to N" but rather **generates N spaces** as a standalone tab
        # segment. Two things fail under nounset here, and both silently empty
        # the whole list:
        #   1. an arithmetic expression cannot be written inline in a flag
        #      argument (${(l:$(( ... )):: :)})
        #   2. the value cannot be omitted -- ${(l:$w:: :)} with nothing after it
        #      makes zsh read an undefined parameter and report "parameter not
        #      set". Give it ${:-}.
        segs+=("$cell")
        if (( nf > 1 )); then
          w=$(( widths[1] - ${#cell} ))
          segs+=("${(l:$w:: :)${:-}}")
        fi
      else
        # Same reason: the width goes into a variable first; $widths[i] does not
        # go inside the flag argument.
        if (( i < nf )); then
          w=$widths[i]
          cell="${(r:$w:: :)cell}"
        fi
        segs+=("$pre[i]$cell$post[i]")
      fi
    done
    # Fields are separated by COLSEP tabs, which --tabstop=1 renders as that
    # many spaces. The default of 5 is wider than a single space and reads better
    # between columns; set _FC_COLUMN_GAP to change it.
    #
    # The tabs must be concatenated by hand with $'\t'. ${(j:\t:)segs} does not
    # work -- a flag's argument is a literal, so '\t' is not interpreted as an
    # escape and the two characters come out as-is; a variable does not work
    # either, ${(j:$sep:)...} does not expand either.
    #
    # "${segs[@]}" must be quoted. An unquoted array expansion drops empty
    # elements -- and the padding segment is exactly empty on the longest row,
    # so that row loses a tab and the whole line shifts left.
    #
    # csep / k / first are declared at the top of the function, for the reason
    # above. first has to be reset per row and must be a plain assignment rather
    # than a local -- a local in a loop body pollutes stdout.
    first=1
    out=""
    for seg in "${segs[@]}"; do
      if (( ! first )); then
        for (( k = 1; k <= csep; k++ )); do out+=$'\t'; done
      fi
      first=0
      out+="$seg"
    done
    # No trailing tab. An empty padding segment leaves consecutive tabs, which
    # render as consecutive spaces -- exactly the column gap.
    print -r -- "$out"
  done
}

# Collect a query's result into _FC_ROWS (clean name<TAB>rest, no colour and no
# alignment padding).
#
# It has to slurp once and then split by line: zsh's arr+=() reallocates the whole
# array on every append, so a while-read loop is O(n^2) (measured 172s for 80k
# rows). ${(@f)$(cat)} does 800k rows in 0.4s. The cost is that the whole list
# briefly lives in a single string; only views on the buffered path get here, and
# their row counts are in the thousands.
_fc_load_rows() {
  local -a lines
  lines=("${(@f)$(cat)}")
  # A command substitution eats the trailing newline, so the split can leave one
  # extra empty element at the end; ${(@)arr:#} removes every empty string.
  _FC_ROWS=("${(@)lines:#}")
}

# Whether this view can take the streaming path (nothing lands in _FC_ROWS, the
# query is piped straight into fzf). Two conditions:
#   1. cols declares a single column. With one column the net effect of
#      _fc_render is "take the first field", so the whole layer can degrade to
#      cut -f1.
#   2. No mutating action -- with nothing dropping rows there is no reason for
#      _FC_ROWS to exist.
#
# When they hold, the candidate chain is _fc_reg_query | cut -f1 | grep -v '^$' |
# fzf: the same semantics as the buffered path with zsh not touching a single
# line. The cost is that returning to the list re-runs the query (0.7s).
_fc_view_streamable() {        # $1=eco $2=view -> return 0 means streamable
  local eco=$1 view=$2 a m
  local -a acts muts cols
  acts=(${(s: :)$(_fc_reg_view_get "$eco" "$view" actions)})
  (( ${#acts} )) || acts=(${(s: :)$(_fc_reg_get "$eco" actions)})
  _fc_reg_view_mutating "$eco" "$view"
  muts=("${_FC_MUTATING[@]}")
  for a in "${acts[@]}"; do
    for m in "${muts[@]}"; do
      [[ $a == "$m" ]] && return 1
    done
  done
  # _fc_render treats an undeclared cols as a single column, so it has to be
  # counted the same way here.
  cols=(${(s: :)$(_fc_reg_view_get "$eco" "$view" cols)})
  (( ${#cols} <= 1 )) || return 1
  return 0
}

# Hand candidates to fzf and print the selected rows. $1=eco $2=view; the rest is
# passed through to _fc_fzf_read. The two paths differ only in where the
# candidates come from; the action and submenu logic is entirely shared.
_fc_feed() {
  local eco=$1 view=$2
  shift 2
  if (( _FC_STREAM )); then
    _fc_reg_query "$eco" "$view" | cut -f1 | grep -v '^$' | _fc_fzf_read "$@"
  else
    # An emptied list must not print one empty line: that would become a
    # selectable blank candidate.
    if (( ${#_FC_ROWS} )); then
      print -rl -- "${_FC_ROWS[@]}" | _fc_render "$eco" "$view" | _fc_fzf_read "$@"
    fi
  fi
}

# Call the query function the registry names. Once per session on the buffered
# path, once per render on the streaming path.
_fc_reg_query() {
  local fn
  fn=$(_fc_reg_get "$1" "$2") || return 1
  "$fn"
}

# Drop exactly the rows whose first field is one of the given names. All of them
# in one pass: dropping k rows one at a time walked the whole table k times, which
# shows on a list as large as npm's.
#
# ${(@)rows:#pat} cannot be used: it globs the whole element, and an element
# contains a tab while a flag argument cannot hold $'\t'.
_fc_drop_rows() {        # $@=names
  local name line
  local -A drop
  local -a keep
  for name in "$@"; do drop[$name]=1; done
  for line in "${_FC_ROWS[@]}"; do
    [[ -n ${drop[${line%%$'\t'*}]:-} ]] || keep+=("$line")
  done
  _FC_ROWS=("${keep[@]}")
}

# Action dispatch is decided entirely by the registry; no concrete action name
# appears in the driver:
#   _FC_REG[<eco>:<act>] exists -> a dedicated handler, taking one package name
#   otherwise                   -> _FC_REG[<eco>:fallback], passed through
#                                  natively, taking (act, package name)
_fc_act() {               # $1=eco $2=view $3=act $4=name
  local act=$3 fn
  fn=$(_fc_reg_get "$1" "$act")
  if [[ -n $fn ]]; then
    "$fn" "$4"
  else
    fn=$(_fc_reg_get "$1" fallback) || return 1
    "$fn" "$act" "$4"
  fi
}

_fc_reg_view_actions() {      # $1=eco $2=view -> _FC_ACTIONS (returns 1 if none)
  local -a acts
  acts=(${(s: :)$(_fc_reg_view_get "$1" "$2" actions)})
  (( ! ${#acts} )) && acts=(${(s: :)$(_fc_reg_get "$1" actions)})
  (( ${#acts} )) || return 1
  _FC_ACTIONS=("${acts[@]}")
}

_fc_actions() {           # $1=eco $2=view
  _fc_reg_view_actions "$1" "$2" || return 1
  print -l -- "${_FC_ACTIONS[@]}" | _fc_fzf_read
}

# The actions that take rows out of the list. A view-level override wins; the
# eco-level value is only the fallback.
_fc_reg_view_mutating() {     # $1=eco $2=view -> _FC_MUTATING
  local -a m
  m=(${(s: :)$(_fc_reg_view_get "$1" "$2" mutating)})
  (( ! ${#m} )) && m=(${(s: :)$(_fc_reg_get "$1" mutating)})
  _FC_MUTATING=("${m[@]}")
}

# Roll back to a chosen version. The versions list is fetched here and only
# here; it is not cached across the session.
#
# The three data keys are deliberately not called versions / current / install:
# `install` is a legal action name in the search view, and _fc_act looks up a
# dedicated handler with _FC_REG[<eco>:<action name>] -- naming a key `install`
# would make the user picking "install" land in rollback's installer.
# Verb-noun names do not collide.
_fc_rollback() {          # $1=eco $2=pkg
  local eco=$1 pkg=$2 versions old new fn
  fn=$(_fc_reg_get "$eco" list-versions) || return 1
  versions=$("$fn" "$pkg")
  if [[ -z $versions ]]; then
    _fc_msg "No versions." "$pkg"; return 0
  fi
  old=$("$(_fc_reg_get "$eco" current-version)" "$pkg")
  _fc_msg "${old:-Not-installed}" "$pkg"
  new=$(print -l -- ${(f)versions} | _fc_fzf_read)
  if [[ -z $new ]]; then
    _fc_msg "Rollback cancel." "$pkg"; return 0
  fi
  [[ $new == "$old" ]] && { print -n $'\nREINSTALL THE SAME VERSION after 2 seconds\n'; sleep 2 }
  # The third argument is the version from before the rollback: most ecosystems
  # do not need it, gem uses it to uninstall first. The existing handlers only
  # read $1 and $2, and an extra argument does no harm.
  "$(_fc_reg_get "$eco" install-version)" "$pkg" "$new" "$old"
}

# Run one action over the selected batch of packages.
#
# $4=1 means a mutating action: stop at the first failure (return 1). A read-only
# action passes 0: it changed no state, so aborting is meaningless, and
# "failure" usually just means "no result" (brew uses finding no dependents, for
# instance). The results go into _FC_DONE / _FC_FAILED, and _fc_session decides
# whether to drop the rows.
_fc_apply() {           # $1=eco $2=view $3=act $4=mutating?
  local eco=$1 view=$2 act=$3 strict=$4 p name
  _FC_DONE=()
  _FC_FAILED=()
  _FC_RC=0
  for p in "${(@f)_FC_PICKED}"; do
    # _fc_render puts the alignment padding after the first tab, so the name
    # taken here is naturally clean.
    name=${p%%$'\t'*}
    if _fc_act "$eco" "$view" "$act" "$name"; then
      _FC_DONE+=("$name")
      print
    else
      # The exit code has to be read first: the array append below clears $?.
      _FC_RC=$?
      _FC_FAILED+=("$name")
      (( strict )) && return 1
    fi
  done
  return 0
}

# The summary after a failed action: which item failed, which never ran, how many
# succeeded.
_fc_report() {          # $1=act
  print -r -- ""
  # 130 = 128 + SIGINT. Ctrl-C while downloading formulae is routine, and calling
  # that a "failure" makes the user think the package is broken when in fact
  # nothing changed.
  if (( _FC_RC == 130 )); then
    print -r -- "  ${_FC_FAILED[1]}: action '$1' interrupted by Ctrl-C, stopped"
  else
    print -r -- "  ${_FC_FAILED[1]}: action '$1' failed (exit code $_FC_RC), stopped"
  fi
  (( ${#_FC_DONE} )) && print -r -- "  ${#_FC_DONE} done and dropped from the list"
  print -r -- "  the other ${_FC_PENDING} did not run and are still in the list"
}

# The view loop. On the buffered path the whole session queries once, drops rows
# from memory after an action, and neither re-queries nor touches the disk; on
# the streaming path every return to the list re-queries, but the list is never
# read into zsh.
_fc_session() {           # $1=eco $2=view
  local eco=$1 view=$2 sel act p
  local -i strict
  local -a picked mutating stay fzfopts
  # _FC_PICKED / _FC_DONE / _FC_FAILED / _FC_PENDING / _FC_RC / _FC_STREAM are all
  # declared at the top level of base.zsh and are not repeated here -- that top
  # level is the single declaration site.

  _FC_HEADER=$(_fc_reg_view_get "$eco" "$view" title)
  [[ -n $_FC_HEADER ]] || _FC_HEADER=$(_fc_reg_get "$eco" title)
  _fc_reg_view_mutating "$eco" "$view"
  mutating=("${_FC_MUTATING[@]}")
  stay=(${(s: :)$(_fc_reg_get "$eco" stay)})
  fzfopts=(${(s: :)$(_fc_reg_view_get "$eco" "$view" fzf-opts)})

  _FC_STREAM=0
  if _fc_view_streamable "$eco" "$view"; then
    _FC_STREAM=1
    # Clear the previous batch: _FC_ROWS is global, and leaving it behind makes
    # it look as if this view had buffered too.
    _FC_ROWS=()
  else
    _fc_reg_query "$eco" "$view" | _fc_load_rows
    if (( ! ${#_FC_ROWS} )); then
      _fc_msg "Nothing to show." "$_FC_HEADER"; return 0
    fi
  fi

  while :; do
    # The list has to be piped into fzf, otherwise fzf reads the terminal and
    # takes the user's typing as the candidate list.
    #
    # fzfopts is the view-level fzf-opts, placed after --multi: fzf takes the
    # last flag, so a view can override the driver default by passing --no-multi.
    # A quoted expansion makes an empty array contribute zero arguments, so views
    # that declare no fzf-opts are unaffected.
    sel=$(_fc_feed "$eco" "$view" --multi "${fzfopts[@]}") || break
    [[ -n $sel ]] || break
    # It has to be ${(f)sel} or "${(@f)sel}": ${(f)"$sel"} is invalid syntax, and
    # it only reports bad substitution at run time, which zsh -n cannot catch.
    picked=("${(@f)sel}")
    (( ${#picked} )) || continue
    _FC_PICKED=("${picked[@]}")

    # The inner loop: the action menu. An action in stay stays put after running,
    # so several read-only actions can be run in a row.
    while :; do
      act=$(_fc_actions "$eco" "$view") || break
      [[ -n $act ]] || break

      strict=0
      (( ${mutating[(Ie)$act]} )) && strict=1

      if _fc_apply "$eco" "$view" "$act" "$strict"; then
        # Everything succeeded
        if (( strict )); then
          _fc_drop_rows "${_FC_DONE[@]}"
          break
        fi
        (( ${stay[(Ie)$act]} )) || break
        continue
      fi

      # Only a mutating action gets here. Whatever took effect has to leave the
      # list, or the user will think it is still there; the failed and the
      # un-run items stay exactly as they are so they can be retried directly.
      _fc_drop_rows "${_FC_DONE[@]}"
      _FC_PENDING=$(( ${#_FC_PICKED} - ${#_FC_DONE} - ${#_FC_FAILED} ))
      _fc_report "$act"
      break
    done
  done
}

_fc_cmd() {               # $1=eco
  local eco=$1 v
  local -a views
  # Requirements first: a missing package manager is worth saying before the view
  # menu opens, not after the user has picked a view.
  _fc_require "$eco" || return 0
  views=(${(s: :)$(_fc_reg_get "$eco" views)})
  (( ${#views} )) || return 1
  _FC_HEADER=$(_fc_reg_get "$eco" title)
  while :; do
    v=$(print -l -- "${views[@]}" | _fc_fzf_read) || return 0
    [[ -n $v ]] || return 0
    _fc_session "$eco" "$v" || return 0
  done
}
