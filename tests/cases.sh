# Behaviour baseline test cases.
#
# This file is only sourced under zsh. The body is zsh-only and does not have to
# hold under bash -- it used to say here that it was "sourced by bash 3.2 / bash
# 5.3 / zsh 5.9 respectively", while run.sh has only ever run zsh: a constraint
# left over from when the project was still bash, and never once executed.
#
# Only the deterministic, side-effect-free pure functions are covered; not
# _fc_pager (it starts less), _fc_homepage (it opens a browser) or _fc_cmd (it
# needs a real fzf and a real package manager).
#
# **The baseline only records text, it cannot tell "correct" from "wrong the same
# way every time".** This repo has already missed three gates because of that:
# _fzf_opts cleared by the previous case, $root not exported, and a case that
# called a function which had been deleted, recording command not found as the
# expected output. Think it through before writing a new case: what does it print
# when it fails, and will that line be taken for correct or for wrong in the
# baseline.

# The divider between cases, so a diff points at the right one
t_sep() {
  printf '\n===== %s =====\n' "$1"
}

# 1. _fc_rule: the header underline, whose length should equal the string's.
#    Note {1..$#1} prints a single character under bash: brace expansion runs
#    before parameter expansion.
t_case_rule() {
  local s
  for s in "Header Text" "abc" "Find Path" "Env" "Npm Outdated"; do
    printf -- '--- [%s] (len=%s) ---\n' "$s" "${#s}"
    _fc_rule "$s"
    printf '\n'
  done
}

# 2. _other_format: render name<TAB>rest into aligned, coloured rows.
t_case_format() {
  t_sep "basic: the first field is aligned, the rest merges into one run, in blue"
  printf 'lodash\t4.17.21\tsome description here\nreact\t18.2.0\tdesc\n' \
    | _other_format
  t_sep "tabs and runs of spaces both collapse to a single space (matching perl join)"
  printf 'a\tb  c\ndd\tee\tff\n' | _other_format
  t_sep "empty input prints nothing"
  printf '' | _other_format
  print -r -- "  (the above should be empty)"
}

# 3. _fc_fzf_read: fzf in non-interactive mode (--filter), and exit-code passthrough.
#    The exit code must pass through, the caller relies on it to tell "selected"
#    from "cancelled" and to break the loop. Any pipe on the end swallows it (the
#    exit code of the last stage of a pipe is what becomes $?).
t_case_read() {
  _FC_OPTS=()
  _FC_HEADER="Test"

  t_sep "exit code: on a match"
  printf 'alpha\nbeta\n' | _fc_fzf_read --filter=alp >/dev/null
  print -r -- "  _fc_fzf_read exit code = $?"
  printf 'alpha\nbeta\n' | fzf --filter=alp >/dev/null
  print -r -- "  bare fzf call  exit code = $?   <- the two must agree"

  t_sep "exit code: with no match, fzf's 1 must pass through"
  printf 'alpha\nbeta\n' | _fc_fzf_read --filter=zzzz >/dev/null
  print -r -- "  _fc_fzf_read exit code = $?   <- must be 1, never constantly 0"
  printf 'alpha\nbeta\n' | fzf --filter=zzzz >/dev/null
  print -r -- "  bare fzf call  exit code = $?"
}

# 4. _fc_msg: the format of the message output. The label must be passed
#    explicitly; a one-argument call prints an empty label.
t_case_msg() {
  t_sep "with a pkg"
  _fc_msg "some message" "mypkg"
  t_sep "without a pkg: falls back to a fixed label, no longer depends on \$caller"
  caller="MYFUNC"
  _fc_msg "another message"
}

# 5. Splitting the fields: the body has to split "name<TAB>version..."
#    Of the three forms, only the third is what the body actually uses
#    (_fc_split_row). The first two look portable but are traps, and they are
#    written down here so nobody picks them up again:
#      - IFS=$'\t' read -r -a arr fails outright under zsh: bad option: -a (that
#        is the bash form)
#      - read -r x y z depends on IFS taking effect, and zsh's read does not
#        take a leading assignment like that
t_case_split_row() {
  local row x y z
  row="lodash	4.17.21	1.2M"
  t_sep "take the first field (parameter expansion)"
  printf '  first=[%s]\n' "${row%%	*}"
  t_sep "fixed-length variable split (depends on read's IFS behaviour, which differs under zsh)"
  IFS=$'\t' read -r x y z <<< "$row"
  printf '  x=[%s] y=[%s] z=[%s]\n' "$x" "$y" "$z"
  t_sep "while + parameter expansion split (this is the one the body uses; it copes with a varying field count)"
  local rest="$row" field
  while [ -n "$rest" ]; do
    case $rest in
      *'	'*) field=${rest%%	*}; rest=${rest#*	} ;;
      *)      field=$rest; rest="" ;;
    esac
    printf '  field=[%s]\n' "$field"
  done
}

# 7. Looping over a multi-line result: the behaviour of `for f in $(echo "$inst")`
#    in the body (zsh word-splits a command substitution on whitespace; the
#    unquoted loop variable is the body's existing style)
t_case_loop() {
  local inst f
  inst="alpha
beta
gamma"
  t_sep "for f in \$(echo ...)"
  for f in $(echo "$inst"); do
    printf '  f=[%s]\n' "$f"
  done
}

# 8. _fc_render: structured row -> an aligned, coloured fzf display row
#    Row structure: name<TAB><padding><TAB>rest. The padding comes after the
#    first tab, so taking the name needs no whitespace stripping. Alignment
#    happens only at this layer; _FC_ROWS holds clean data.
t_case_render() {
  local line out row segs2 c i
  local -a start ref
  # start/segs2 are also used by the alignment assertion below
  t_sep "with a display: every column aligns on its own, a real tab between columns"
  _FC_ROWS=("lodash	4.17.21" "my package	1.0.0 some desc")
  _fc_render | cat -v
  t_sep "without a display (the search view): printed as is, no padding"
  _FC_ROWS=("all-the-package-names" "left-pad")
  _fc_render | cat -v
  t_sep "reading the name back: a multi-word package name is intact, and has no trailing space to begin with"
  _FC_ROWS=("my package	1.0.0")
  line=$(_fc_render)
  printf '  display row=[%s]\n' "$line"
  printf '  name=[%s]\n' "${line%%	*}"
  t_sep "_FC_ROWS stays clean (not polluted by the display layer)"
  _FC_ROWS=("alpha	1" "beta	2" "a-very-long-name	3")
  _fc_render >/dev/null
  printf '  [%s]\n' "${(j:,:)${_FC_ROWS}}"

  # A character-level assertion: a literal backslash must never appear in a
  # display row. The flag argument of ${(j:\t:)segs} is a literal and does not
  # interpret escapes, so the output is all literal \t; the baseline only records
  # the status quo and cannot catch this class of bug.
  t_sep "character-level assertion: no literal backslash"
  _FC_ROWS=("a	1" "bb	2")
  out=$(_fc_render)
  if [[ $out == *'\'* ]]; then
    print -r -- '  *** error: a literal backslash is in the display row, the tab join is wrong ***'
  else
    print -r -- '  OK no literal backslash'
  fi
  [[ $out == *$'\t'* ]] && print -r -- '  contains a real tab: yes' || print -r -- '  contains a real tab: no'

  # The alignment assertion: every data column has to start in the same column.
  # The array expansion must be quoted, otherwise zsh drops the empty elements,
  # and on the longest row the padding segment is exactly the empty one -- that
  # row loses one tab and the whole row shifts left. The number of tabs between
  # columns is not fixed, so only the data columns themselves are compared.
  t_sep "alignment assertion: the data columns must all start in the same column"
  _FC_REG+=('al:manage:cols' 'name have sep want')
  _FC_ROWS=("a	1	=>	1"
             "much-longer-name	22	=>	22"
             "mid	333	=>	333")
  for row in "${(@f)$(_fc_render al manage)}"; do
    row=$(_fc_sgr_strip "$row")
    _fc_split_row "$row"
    segs2=("${_FC_FIELDS[@]}")
    c=0; start=()
    for (( i = 2; i <= ${#segs2}; i++ )); do
      c=$(( c + 1 + ${#segs2[i-1]} ))
      [[ -n ${segs2[i]} ]] && start+=($c)      # skip the empty padding segment
    done
    # The last 3 non-empty segments are f2 / => / f4; the padding comes before
    # them, so it does not affect this
    start=("${(@)start[-3,-1]}")
    print -r -- "  [${segs2[1]}] f2/=>/f4 start columns: ${(j:,:)start}"
    if (( ${#ref} == 0 )); then
      ref=("${start[@]}")
    elif [[ ${(j:,:)start} != "${(j:,:)ref}" ]]; then
      print -r -- "  *** misaligned: should be ${(j:,:)ref} ***"
    fi
  done
  (( ${#ref} == 3 )) && print -r -- '  OK the data columns start alike in every row'
  unset '_FC_REG[al:manage:cols]'

  # The purity assertion: every row has to start with the package name. A scalar
  # local inside a loop body makes zsh 5.9 print a `NAME=<value>` line to stdout,
  # and this function's stdout feeds fzf directly, so that line becomes a bogus
  # candidate. zsh -n cannot see it and the static gate at tests/run.sh --hygiene
  # catches it at write time; this catches the symptom.
  t_sep "purity assertion: every row must start with the package name (no NAME= pollution, no leading tab)"
  _FC_ROWS=("a	1	=>	1"
             "much-longer-name	22	=>	22"
             "mid	333	=>	333")
  _FC_REG+=('al:manage:cols' 'name have sep want')
  local -a names
  names=()
  for row in "${(@f)$(_fc_render al manage)}"; do
    names+=("${row%%	*}")
  done
  print -r -- "  first segment of each row: ${(j: | :)names}"
  local expect=('a' 'much-longer-name' 'mid')
  if [[ ${(j:|:)names} == "${(j:|:)expect}" ]]; then
    print -r -- '  OK the first segments correspond one to one to the package names'
  else
    print -r -- "  *** error: the first segments do not match the package names -- a non-data row got into the output ***"
  fi
  unset '_FC_REG[al:manage:cols]'
}

# 9. _fc_drop_rows: remove exactly the rows whose first field matches, from
#    _FC_ROWS.
#    ${(@)rows:#pat} cannot be used: it globs the whole element, so a * ? or [
#    inside a name is treated as a pattern.
#    All the names go in one call: the driver drops a whole batch of finished
#    packages at once, and one call per name walked the table once per name.
t_case_drop_rows() {
  t_sep "drop a row that exists"
  _FC_ROWS=("alpha	1" "beta	2" "gamma	3")
  _fc_drop_rows "beta"
  printf '  n=%d  [%s]\n' ${#_FC_ROWS} "${(j:,:)${_FC_ROWS}}"
  t_sep "multi-word package name (exact match, must not hit the others)"
  _FC_ROWS=("my package	1" "other-pkg	2" "my package extra	3")
  _fc_drop_rows "my package"
  printf '  n=%d  [%s]\n' ${#_FC_ROWS} "${(j:,:)${_FC_ROWS}}"
  t_sep "a name that does not exist must drop nothing"
  _FC_ROWS=("a*x	1" "ab	2" "axb	3")
  _fc_drop_rows "a*x"
  printf '  n=%d  [%s]\n' ${#_FC_ROWS} "${(j:,:)${_FC_ROWS}}"
  t_sep "several names in one call"
  _FC_ROWS=("a	1" "b	2" "c	3" "d	4")
  _fc_drop_rows "b" "d"
  printf '  n=%d  [%s]\n' ${#_FC_ROWS} "${(j:,:)${_FC_ROWS}}"
  t_sep "no names at all: nothing is dropped (the array was empty)"
  _FC_ROWS=("a	1" "b	2")
  _fc_drop_rows "${_FC_DONE[@]}"
  printf '  n=%d  [%s]\n' ${#_FC_ROWS} "${(j:,:)${_FC_ROWS}}"
  t_sep "for comparison: the glob form does collateral damage (why it is unused)"
  _FC_ROWS=("a*x	1" "ab	2" "axb	3")
  printf '  ${(@)_FC_ROWS:#*x*} -> n=%d (all 3 rows deleted)\n' ${#${(@)_FC_ROWS:#*x*}}
}

# 10. Action membership: ${arr[(Ie)act]} is the only thing that decides whether
#     an action "drops the row and goes back to the list" or "stays in the action
#     menu"
t_case_membership() {
  local -a mutating stay
  local act m l
  mutating=(uninstall)
  stay=(homepage deps info)
  t_sep "act / mutating / stay"
  for act in update uninstall rollback install homepage deps info; do
    (( ${mutating[(Ie)$act]} )) && m=mutating || m='-'
    (( ${stay[(Ie)$act]} )) && l=stay || l='-'
    printf '  %-10s %-9s %s\n' "$act" "$m" "$l"
  done
}

# 11. _fc_reg_get: reading the registry. Never write ${_FC_REG[$var:field]}:
#     zsh takes the first letter after the ':' as a parameter modifier (:t tail /
#     :h head / :r root / :e ext / :s suffix / :l lower / :u upper) and silently
#     returns empty. Every field name below has hit that trap.
t_case_reg_get() {
  t_sep "fields whose first letter collides with a modifier (all of these once returned empty silently)"
  local f v
  for f in title stay fallback homepage rollback search; do
    v=$(_fc_reg_get npm "$f")
    printf '  %-10s -> [%s]\n' "$f" "$v"
  done
  t_sep "an undefined field must come back empty"
  for f in tap head root ext suffix lower upper; do
    v=$(_fc_reg_get npm "$f")
    printf '  %-10s -> [%s]\n' "$f" "$v"
  done
  t_sep "view-specific fields"
  printf '  manage:title        -> [%s]\n' "$(_fc_reg_get npm manage title)"
  printf '  search:fzf-opts     -> [%s]\n' "$(_fc_reg_get npm search fzf-opts)"
  printf '  mutating:outdated   -> [%s]\n' "$(_fc_reg_get npm mutating outdated)"
  t_sep "for comparison: writing the subscript directly fails silently"
  local -A T
  T=( [npm:title]=Npm [npm:views]="a b" )
  local eco=npm
  # ${T[$eco:title]:-}: the key already has a value, and :- does not change the
  # output outside nounset -- it is here so that this line also runs under
  # nounset. The nounset gate has to be able to run the whole case, and this
  # passage **deliberately** demonstrates a form that fails -- and the way it
  # fails is precisely "silently loses data" rather than an error, so the
  # nounset gate cannot catch it and should not catch it. The :- is there so that
  # the ":t is read as tail" conclusion is still printed under nounset.
  printf '  ${T[$eco:title]}   = [%s]  <- :t read as tail, data lost\n' "${T[$eco:title]:-}"
  printf '  ${T[$eco:views]}   = [%s]  <- :v is not a modifier, works by luck\n' "${T[$eco:views]:-}"
  local key="${eco}:title"
  printf '  with key=%s, T[$key] = [%s]  <- the correct way\n' "$key" "${T[$key]:-}"
}

# 12. Several ecosystems coexisting in the registry. The associated array
#     _FC_REG=(...) is a **whole replacement**, so a collection has to write
#     _FC_REG+=(...), or the one sourced last wipes out the earlier ones.
t_case_coexist() {
  local eco
  t_sep "every migrated ecosystem must still be in the registry"
  for eco in npm pnpm pip; do
    printf '  %-6s title=[%s] views=[%s]\n' \
      "$eco" "$(_fc_reg_get "$eco" title)" "$(_fc_reg_get "$eco" views)"
  done
  t_sep "the control group: _FC_REG=(...) replaces, only _FC_REG+=(...) merges"
  local -A T
  T=([x:1]=X [x:2]=Y)
  T=([y:1]=Z)
  printf '  T=([x:1] [x:2]) then T=([y:1])  -> entries=%s  (1 = replaced)\n' "${#T}"
  T=([x:1]=X [x:2]=Y)
  T+=([y:1]=Z)
  printf '  with T+=([y:1]) instead        -> entries=%s  (3 = merged correctly)\n' "${#T}"
}

# 13. _fc_session has to pipe the list to fzf. Without the pipe fzf reads the
#     terminal and takes the user's input for the candidate list. Replace
#     _fc_fzf_read with a stub and capture what it reads from stdin.
t_case_session_stdin() {
  local line
  t_sep "the candidate list fzf reads from stdin"
  functions[_t_read_orig]=$functions[_fc_fzf_read]

  # The stub: print what it read from stdin, then simulate "the user cancelled".
  # It has to write to stderr: _fc_fzf_read is called inside a $(...) subshell,
  # and writing to stdout is swallowed by the command substitution, so the two
  # cases print the same thing and the test cannot tell them apart. Report an
  # error explicitly when no line arrives.
  _fc_fzf_read() {
    local line
    local n=0
    while IFS= read -r line; do print -r -- "  fzf<- [$line]" >&2; (( n++ )); done
    if (( n == 0 )); then
      print -r -- "  *** error: fzf got no candidate list (_FC_ROWS was not piped to fzf) ***" >&2
    else
      print -r -- "  fzf received $n lines in total" >&2
    fi
    return 130
  }
  _t_list_stub() { printf 'alpha\t1.0\nmy package\t2.0\n' }
  _t_act_stub() { : }
  _FC_REG+=(
    'probe:title'         'Probe'
    'probe:views'         'manage'
    'probe:manage'        '_t_list_stub'
    'probe:manage:title'  'Probe Manage'
    'probe:manage:actions' 'uninstall'
    'probe:mutating'      'uninstall'
    'probe:fallback'        '_t_act_stub'
  )

  _fc_session probe manage
  print "  rows left after the cancel=${#_FC_ROWS}  (2 = nothing dropped wrongly)"

  unfunction _fc_fzf_read _t_list_stub _t_act_stub
  eval "_fc_fzf_read() { $functions[_t_read_orig] }"
  unfunction _t_read_orig
  for k in title views manage manage:title manage:actions mutating fallback; do
    unset "_FC_REG[probe:$k]"
  done
}

# 14. Splitting a multi-selection. It has to be written "${(@f)sel}":
#     ${(f)"$sel"} is invalid syntax, which zsh -n cannot see -- it only throws
#     bad substitution at run time, once something has actually been selected.
t_case_pick_split() {
  local sel p
  local -a picked
  t_sep "multi-select: the first field of each row, a multi-word name stays intact"
  sel="alpha	1.0
my package	2.0
gamma	3.0"
  picked=("${(@f)sel}")
  printf '  n=%d\n' "${#picked[@]}"
  for p in $picked; do
    printf '  [%s] -> name=[%s]\n' "${p//$'\t'/|}" "${p%%$'\t'*}"
  done
  t_sep "single selection"
  sel="only one	9.9"
  picked=("${(@f)sel}")
  printf '  n=%d name=[%s]\n' "${#picked[@]}" "${picked[1]%%$'\t'*}"
}

# 15. The registry is self-consistent: an action name must not collide with an
#     internal data key, and every dispatch target has to exist. A collision
#     means picking one action hits another action's handler, and the symptom
#     only shows up once you really go and install a package, so it is stopped
#     statically.
t_case_registry() {
  local key eco view act fn
  local -a ecos parts views acts k2 reserved providers
  local missing=0

  # The data keys have to be derived from _fc_rollback in base.zsh, not copied
  # in here -- otherwise renaming a key makes this case follow along and it is
  # "consistent" for ever.
  reserved=(${(f)"$(sed -n '/^_fc_rollback()/,/^}/p' base.zsh \
    | grep -o '_fc_reg_get "\$eco" [a-z][a-z-]*' | awk '{print $NF}')"})
  reserved=(${(u)reserved})

  ecos=()
  for key in "${(@k)_FC_REG}"; do
    parts=("${(@s.:.)key}")
    (( ${#parts} == 2 )) || continue
    [[ ${parts[2]} == title ]] || continue
    ecos+=("${parts[1]}")
  done
  ecos=(${(u)ecos})

  t_sep "registry self-consistency (${#ecos} ecosystems)"
  printf '  the data keys _fc_rollback reads: %s\n' "${(j: :)reserved}"

  for eco in $ecos; do
    # The functions these keys point at are the "data provider functions". Once
    # an action resolves to one of them, _fc_act is treating a data provider as
    # an action handler -- whatever that key is called, so what is compared here
    # is the function's identity, not the key's name.
    providers=()
    for key in $reserved; do
      fn=$(_fc_reg_get $eco $key)
      [[ -n $fn ]] && providers+=($fn)
    done

    views=(${(s: :)$(_fc_reg_get $eco views)})
    for view in $views; do
      acts=(${(s: :)$(_fc_reg_get $eco $view actions)})
      for act in $acts; do
        fn=$(_fc_reg_get $eco $act)
        [[ -n $fn ]] || continue                  # it goes to fallback, no collision
        if (( ${providers[(Ie)$fn]} )); then
          missing=1
          printf '  *** error: the action %s of %s/%s resolves to the data provider %s ***\n' $eco $view $act $fn
        fi
        if (( ! ${+functions[$fn]} )); then
          missing=1
          printf '  *** error: the %s of %s/%s points at a function that does not exist: %s ***\n' $eco $view $act $fn
        fi
      done
    done
  done
  (( missing )) || printf '  OK no collisions, every dispatch target exists\n'
  printf '  views that declare title/actions/cols:'
  for eco in $ecos; do
    for view in ${(s: :)$(_fc_reg_get $eco views)}; do
      k2=()
      for key in $view "${view}:title" "${view}:actions" "${view}:cols"; do
        [[ -n $(_fc_reg_get $eco $key) ]] || { missing=1; printf '\n    missing from %s/%s: %s' $eco $view $key }
      done
    done
  done
  (( missing )) || printf 'yes'
  printf '\n'
  printf '  registered ecosystems: %s\n' "${(j: :)ecos}"
}

# 16. The shape of a key: _FC_REG[<eco>:<view>:<field>], and the driver really
#     resolves it. The wrong shape (_FC_REG[<eco>:actions:<view>]) reads no value
#     and **does not error**; the symptom is "pressing enter does nothing", so
#     both the shape is checked and the driver's real resolution path is walked
#     for a non-empty value.
#
# Both checks are needed: the shape check alone passes a key whose segments are
# in the wrong order, and only the driver's own path catches that.
t_case_keyshape() {
  local key eco view
  local -a ecos parts
  local bad=0

  ecos=()
  for key in "${(@k)_FC_REG}"; do
    parts=("${(@s.:.)key}")
    (( ${#parts} == 2 )) || continue
    [[ ${parts[2]} == title ]] || continue
    ecos+=("${parts[1]}")
  done
  ecos=(${(u)ecos})

  t_sep "key shape: the X in the second segment of every three-segment key needs _FC_REG[<eco>:X:title]"
  for eco in $ecos; do
    for key in "${(@k)_FC_REG}"; do
      parts=("${(@s.:.)key}")
      (( ${#parts} == 3 )) || continue
      [[ ${parts[1]} == $eco ]] || continue
      view=${parts[2]}
      # The criterion is "does this X have a title of its own", and the set of
      # X cannot be inferred from the keys that exist: written that way, a key
      # with the segment order reversed counts as a legal view name too, and it
      # always passes.
      if [[ -z $(_fc_reg_view_get $eco $view title) ]]; then
        bad=1
        printf '  *** error: %s has no title, so it is not a legal view (the segments of key %s are reversed) ***\n' $view $key
      fi
    done
  done
  (( bad )) || printf '  OK the three-segment keys agree in all %d ecosystems\n' ${#ecos}

  t_sep "driver resolution: the action list of every view is non-empty (enter must open a submenu)"
  bad=0
  for eco in $ecos; do
    for view in ${(s: :)$(_fc_reg_get $eco views)}; do
      if _fc_reg_view_actions $eco $view 2>/dev/null; then
        printf '  OK   %-15s %2d actions\n' "$eco/$view" ${#_FC_ACTIONS}
      else
        bad=1
        printf '  *** error: the action list of %s/%s is empty ***\n' $eco $view
      fi
    done
  done
  (( bad )) || printf '  OK all non-empty\n'

  t_sep "driver resolution: a view-level mutating override really has to be picked up"
  bad=0
  for eco in $ecos; do
    for view in ${(s: :)$(_fc_reg_get $eco views)}; do
      key=$(_fc_reg_view_get $eco $view mutating)
      [[ -n $key ]] || continue
      _fc_reg_view_mutating $eco $view
      if [[ ${(j: :)${_FC_MUTATING}} == ${(j: :)${(s: :)key}} ]]; then
        printf '  OK   %-15s override [%s]\n' "$eco/$view" "$key"
      else
        bad=1
        printf '  *** error: the override of %s/%s is=[%s] but it actually is=[%s] ***\n' \
          $eco $view "$key" "${(j: :)${_FC_MUTATING}}"
      fi
    done
  done
  (( bad )) || printf '  OK every override took effect'
}

# 17. The full cycle: list -> enter -> submenu -> run.
#     The 2nd fzf call has to receive the action list; the symptom of it not
#     doing so is "pressing enter does nothing".
#
#     The counter has to go to a file: _fc_fzf_read is called inside a $(...)
#     subshell, a variable changed there does not get out, and counting in a
#     variable makes every run think it is the first call, so the session spins
#     until it times out.
t_case_action_menu() {
  local cnt logf line n
  local k
  cnt=$(mktemp)
  logf=$(mktemp)
  print -r -- 0 >"$cnt"

  functions[_t_read_orig]=$functions[_fc_fzf_read]
  _fc_fzf_read() {
    local n
    n=$(<"$cnt")
    n=$(( n + 1 ))
    print -r -- "$n" >"$cnt"
    # Write to stderr: stdout is swallowed by the command substitution.
    # _fc_session must be called bare (with no pipe), or it runs in a subshell
    # and the _FC_ROWS it changed does not come back out, so the last line always
    # reports 0 rows.
    local -a cand
    local c
    cand=("${(@f)$(cat)}")
    local -a brief
    for c in "${(@)cand}"; do
      # Take the first field (the package name) of a list row, and copy an
      # action row whole: that way the baseline can be read to see who the
      # candidates are.
      [[ $c == *$'\t'* ]] && c=${c%%$'\t'*}
      brief+=("$c")
    done
    print -r -- "  fzf#$n ${#cand[@]} candidates: ${(j: , :)brief}" >&2
    (( ${#cand} == 0 )) && print -r -- "  *** error: call $n has no candidates ***" >&2
    # The 2nd call is the submenu, and its candidates must be the action list:
    # when the list does not resolve, fzf still receives the list rows, and the
    # symptom is "pressing enter does nothing".
    if (( n == 2 )) && [[ "${(j: :)cand}" != 'show hide' ]]; then
      print -r -- "  *** error: the submenu candidates should be [show hide], they are [${(j: :)cand}] ***" >&2
    fi
    if (( n == 2 )) && [[ "${(j: :)cand[1]}" != show ]]; then
      print -r -- "  *** error: the action name turned into [$cand[1]], so the action list did not resolve ***" >&2
    fi
    case $n in
      1) print -r -- $'alpha\t1.0\t=>\t2.0' ;;
      2) print -r -- 'show' ;;
      *) return 130 ;;
    esac
  }
  _t_probe_list() { printf 'alpha\t1.0\t=>\t2.0\nbeta\t3.0\t=>\t4.0\n' }
  _t_probe_runner() { print -r -- "  ACTION act=$1 pkg=[$2]" >&2; return 0 }
  _FC_REG+=(
    'probe2:title'   'Probe2'
    'probe2:views'   'manage'
    'probe2:manage'  '_t_probe_list'
    'probe2:manage:title'   'Probe2 Manage'
    'probe2:manage:actions' 'show hide'
    'probe2:manage:cols'    'name have sep want'
    'probe2:mutating' 'hide'
    'probe2:stay'     'show'
    'probe2:fallback'   '_t_probe_runner'
  )

  _fc_session probe2 manage
  print -r -- "  fzf was called $(<"$cnt") times in total (4 = list + submenu + back to the list + cancel)"
  print -r -- "  ${#_FC_ROWS} rows left (show is in stay, so it must not drop a row: 2)"

  unfunction _fc_fzf_read _t_probe_list _t_probe_runner
  eval "_fc_fzf_read() { $functions[_t_read_orig] }"
  unfunction _t_read_orig
  for k in title views manage manage:title manage:actions manage:cols mutating stay fallback; do
    unset "_FC_REG[probe2:$k]"
  done
  rm -f "$cnt" "$logf"
}

# 18. Handling a failed action. A mutating action that fails has to stop at
#     once, and only the ones that took effect come out of the list -- taking a
#     failed one out makes it disappear off the screen while it is still on the
#     system, and it can never be found again. A read-only action does not abort:
#     it changes no state, and its "failure" is usually just "no results".
t_case_failure() {
  local cnt logf line n log
  local k fallback
  local -a rows
  # local on purpose: the stub is called in a $(...) subshell, and zsh's dynamic
  # scoping sees it either way, but it should not outlive this case as a global.
  # The plugin depends on that same property (_FC_HEADER).
  local SEL_ACT
  cnt=$(mktemp)
  logf=$(mktemp)

  _t_p4_list() { printf 'a\t1\nb\t2\nc\t3\nd\t4\n' }
  # The 2nd package fails, the rest succeed
  _t_p4_fail_second() {
    print -r -- "$*" >>"$logf"
    [[ $2 == b ]] && return 1
    return 0
  }
  _t_p4_always_ok()  { print -r -- "$*" >>"$logf"; return 0 }
  _t_p4_always_err() { print -r -- "$*" >>"$logf"; return 1 }
  # 128 + SIGINT: this is the exit code when brew is Ctrl-C'd while downloading
  # a formula
  _t_p4_interrupt()  { print -r -- "$*" >>"$logf"; return 130 }

  functions[_t_read_orig]=$functions[_fc_fzf_read]
  # The counter goes to a file: _fc_fzf_read is called inside a $(...) subshell,
  # a variable does not get out
  _fc_fzf_read() {
    local n
    n=$(<"$cnt")
    n=$(( n + 1 ))
    print -r -- "$n" >"$cnt"
    cat >/dev/null
    case $n in
      1) print -r -- $'a\t1\nb\t2\nc\t3\nd\t4' ;;
      2) print -r -- "$SEL_ACT" ;;
      *) return 130 ;;
    esac
  }

  t_sep "a mutating action fails midway: stop at once, drop only the successes, the failure can be retried"
  fallback=_t_p4_fail_second
  SEL_ACT=go
  _FC_REG+=(
    'p4:title'  'P4'
    'p4:views'  'manage'
    'p4:manage' '_t_p4_list'
    'p4:manage:title'   'P4 Manage'
    'p4:manage:actions' 'go peek'
    'p4:manage:cols'    'name'
    'p4:mutating' 'go'
    'p4:stay'     'peek'
    'p4:fallback'   "$fallback"
  )
  print -r -- 0 >"$cnt"
  : >"$logf"
  _fc_session p4 manage
  log=$(<"$logf")
  print -r -- "  fallback got ${#${(f)log}} calls: ${(j: :)${(f)log}}"
  print -r -- "  DONE=${(j: :)_FC_DONE}  FAILED=${(j: :)_FC_FAILED}  not run=${_FC_PENDING}"
  rows=()
  for line in "${_FC_ROWS[@]}"; do rows+=("${line%%	*}"); done
  print -r -- "  ${#rows} rows left: ${(j: :)rows}"
  for k in title views manage manage:title manage:actions manage:cols mutating stay fallback; do
    unset "_FC_REG[p4:$k]"
  done

  t_sep "every mutating action succeeds: they all come out of the list"
  SEL_ACT=go
  _FC_REG+=(
    'p4:title'  'P4'
    'p4:views'  'manage'
    'p4:manage' '_t_p4_list'
    'p4:manage:title'   'P4 Manage'
    'p4:manage:actions' 'go peek'
    'p4:manage:cols'    'name'
    'p4:mutating' 'go'
    'p4:stay'     'peek'
    'p4:fallback'   '_t_p4_always_ok'
  )
  print -r -- 0 >"$cnt"
  : >"$logf"
  _fc_session p4 manage
  rows=()
  for line in "${_FC_ROWS[@]}"; do rows+=("${line%%	*}"); done
  print -r -- "  ${#rows} rows left: ${(j: :)rows} (should be 0)"
  for k in title views manage manage:title manage:actions manage:cols mutating stay fallback; do
    unset "_FC_REG[p4:$k]"
  done

  t_sep "a read-only action returns non-zero: it neither aborts nor drops rows"
  SEL_ACT=peek
  _FC_REG+=(
    'p4:title'  'P4'
    'p4:views'  'manage'
    'p4:manage' '_t_p4_list'
    'p4:manage:title'   'P4 Manage'
    'p4:manage:actions' 'go peek'
    'p4:manage:cols'    'name'
    'p4:mutating' 'go'
    'p4:stay'     'peek'
    'p4:fallback'   '_t_p4_always_err'
  )
  print -r -- 0 >"$cnt"
  : >"$logf"
  _fc_session p4 manage
  log=$(<"$logf")
  print -r -- "  fallback got ${#${(f)log}} calls in total (4 = it did not abort early)"
  rows=()
  for line in "${_FC_ROWS[@]}"; do rows+=("${line%%	*}"); done
  print -r -- "  ${#rows} rows left: ${(j: :)rows} (should be 4)"
  for k in title views manage manage:title manage:actions manage:cols mutating stay fallback; do
    unset "_FC_REG[p4:$k]"
  done

  t_sep "exit code 130 (Ctrl-C): the wording differs from an ordinary failure"
  SEL_ACT=go
  _FC_REG+=(
    'p4:title'  'P4'
    'p4:views'  'manage'
    'p4:manage' '_t_p4_list'
    'p4:manage:title'   'P4 Manage'
    'p4:manage:actions' 'go peek'
    'p4:manage:cols'    'name'
    'p4:mutating' 'go'
    'p4:stay'     'peek'
    'p4:fallback'   '_t_p4_interrupt'
  )
  print -r -- 0 >"$cnt"
  : >"$logf"
  _fc_session p4 manage
  rows=()
  for line in "${_FC_ROWS[@]}"; do rows+=("${line%%	*}"); done
  print -r -- "  ${#rows} rows left: ${(j: :)rows} (should be 4, nothing changed)"
  for k in title views manage manage:title manage:actions manage:cols mutating stay fallback; do
    unset "_FC_REG[p4:$k]"
  done

  eval "_fc_fzf_read() { $functions[_t_read_orig] }"
  unfunction _t_read_orig _t_p4_list _t_p4_fail_second \
              _t_p4_always_ok _t_p4_always_err _t_p4_interrupt
  rm -f "$cnt" "$logf"
}

# 19. _fc_load_rows: collecting the query output into _FC_ROWS
#
# The implementation was replaced here (the old while-read + arr+=() is O(n^2)),
# and the semantics have to be exactly the same:
#   - blank lines are dropped
#   - a last line without a newline is still collected
#   - the content of a row is not altered (tabs stay as they are, that is the
#     input to _fc_render). A command substitution eats the trailing newline, so
#     splitting on lines leaves one extra empty element at the end, and without
#     clearing it that becomes a blank candidate.
t_case_load_rows() {
  local out
  t_sep "ordinary input: three rows, one of them blank"
  out=$(printf 'alpha\t1.0\n\nbeta\t2.0\n' | _fc_load_rows; print -r -- "n=${#_FC_ROWS} [${(j:,:)${_FC_ROWS}}]")
  print -r -- "  $out"
  t_sep "last row without a newline"
  out=$(printf 'alpha\t1.0\nbeta' | _fc_load_rows; print -r -- "n=${#_FC_ROWS} [${(j:,:)${_FC_ROWS}}]")
  print -r -- "  $out"
  t_sep "blank rows only"
  out=$(printf '\n\n' | _fc_load_rows; print -r -- "n=${#_FC_ROWS} [${(j:,:)${_FC_ROWS}}]")
  print -r -- "  $out"
  t_sep "no input"
  out=$(printf '' | _fc_load_rows; print -r -- "n=${#_FC_ROWS}")
  print -r -- "  $out"
  t_sep "a blank row and leading/trailing whitespace are not the same thing: '  ' stays"
  out=$(printf '  \nx\t\n' | _fc_load_rows; print -r -- "n=${#_FC_ROWS} [${(j:|:)${_FC_ROWS}}]")
  print -r -- "  $out"
  _FC_ROWS=()
}

# 20. A single-column view with no mutating action takes the streaming path
#
# The regression (a user reported it): pnpmf -> search never produces candidates,
# and the longer you wait the worse it gets. _fc_load_rows on the buffered path
# uses while-read plus an array append, which is O(n^2) (80k rows 172s, double
# that 4x), while search's data source all-the-package-names has 4.48 million
# rows -- on the buffered path fzf would not see a candidate for over an hour.
#
# Three things are asserted: the candidates match the buffered path (first field
# taken, blank rows dropped), _FC_ROWS stays empty throughout, and _fc_render is
# never called at all.
t_case_stream() {
  local cnt qcnt logf log
  local k
  local -a cand
  local c
  cnt=$(mktemp)
  qcnt=$(mktemp)
  logf=$(mktemp)
  print -r -- 0 >"$cnt"
  print -r -- 0 >"$qcnt"
  : >"$logf"

  functions[_t_read_orig]=$functions[_fc_fzf_read]
  functions[_t_render_orig]=$functions[_fc_render]
  _fc_render() {
    print -r -- '  *** error: a streaming view must not call _fc_render ***' >&2
    cat
  }
  _fc_fzf_read() {
    local n
    n=$(<"$cnt")
    n=$(( n + 1 ))
    print -r -- "$n" >"$cnt"
    cand=("${(@f)$(cat)}")
    cand=("${(@)cand:#}")
    print -r -- "  fzf#$n received ${#cand[@]} candidates: ${(j:,:)cand}" >&2
    (( ${#cand} == 0 )) && print -r -- '  *** error: call '"$n"' has no candidates ***' >&2
    case $n in
      1) print -r -- 'alpha' ;;
      2) print -r -- 'show' ;;
      *) return 130 ;;
    esac
  }
  # The counter has to go to a file: the query function runs in _fc_feed's pipe
  # and does not get out of the subshell
  _t_s_list() {
    print -r -- $(( $(<"$qcnt") + 1 )) >"$qcnt"
    printf 'alpha\t1.0\nbeta\t2.0\n\n'
  }
  _t_s_runner() { print -r -- "act=$1 pkg=[$2]" >>"$logf"; return 0 }
  _FC_REG+=(
    's1:title'        'S1'
    's1:views'        'search'
    's1:search'       '_t_s_list'
    's1:search:title' 'S1 Search'
    's1:search:actions' 'install'
    's1:search:cols'  'name'
    # The only mutating action declared is uninstall, and it is not among
    # search's actions -- an empty intersection is exactly the criterion for
    # being streamable
    's1:mutating'     'uninstall'
    's1:stay'         'install'
    's1:fallback'       '_t_s_runner'
  )

  _fc_session s1 search
  log=$(<"$logf")
  printf '  the query was called %s times (2 = the list + back to the list after the action)\n' "$(<"$qcnt")"
  printf '  _FC_ROWS length %d (0 = the streaming path does not buffer)\n' "${#_FC_ROWS}"
  printf '  the action received: %s\n' "${(j: :)${(f)log}}"
  printf '  fzf was called %s times in total (3 = list + submenu + cancel)\n' "$(<"$cnt")"

  unfunction _fc_fzf_read _fc_render _t_s_list _t_s_runner
  eval "_fc_fzf_read() { $functions[_t_read_orig] }"
  eval "_fc_render() { $functions[_t_render_orig] }"
  unfunction _t_read_orig _t_render_orig
  for k in title views search search:title search:actions search:cols mutating stay fallback; do
    unset "_FC_REG[s1:$k]"
  done
  rm -f "$cnt" "$qcnt" "$logf"

  t_sep "streaming classification: the 4.48-million-row npm / pnpm search must be judged streamable"
  local key eco view how
  local -a ecos parts
  local bad=0
  ecos=()
  for key in "${(@k)_FC_REG}"; do
    parts=("${(@s.:.)key}")
    (( ${#parts} == 2 )) || continue
    [[ ${parts[2]} == title ]] || continue
    ecos+=("${parts[1]}")
  done
  ecos=(${(u)ecos})
  for eco in $ecos; do
    for view in ${(s: :)$(_fc_reg_get $eco views)}; do
      # %-4s is left as it is: it is code, not text. "streaming" is longer than
      # 4, so the field is simply not padded.
      if _fc_view_streamable "$eco" "$view"; then how=streaming; else how=buffered; fi
      # %-9s rather than %-4s: with the labels in English, "streaming" and
      # "buffered" are 9 and 8 characters, and a 4-column field no longer
      # covers them, so the output comes out ragged.
      printf '  %-9s %s/%s\n' "$how" "$eco" "$view"
    done
  done
  for view in npm/search pnpm/search; do
    eco=${view%%/*}; view=${view#*/}
    _fc_view_streamable "$eco" "$view" || { bad=1; printf '  *** error: %s was judged buffered, so search goes back to being O(n^2) ***\n' "$eco/$view" }
  done
  # A multi-column view has to stay on the buffered path: it needs a width
  # pre-scan, and cut -f1 cannot give it alignment
  for view in npm/manage pnpm/outdated brew/manage gem/manage; do
    eco=${view%%/*}; view=${view#*/}
    _fc_view_streamable "$eco" "$view" && { bad=1; printf '  *** error: %s is a multi-column view, it must not be judged streaming ***\n' "$eco/$view" }
  done
  (( bad )) || printf '  OK search over 4.48 million rows streams, multi-column views still use the buffered path'
}

# 17. pathf / envf value extraction and --ansi
#     Extracting the value has to drop the alignment padding and the colour
#     codes, and it has to take "everything after the first field" rather than
#     the last whitespace-separated field: with "/Applications/VMware
#     Fusion.app/..." in PATH, the latter leaves only "Fusion.app/...".
#     fzf has to get --ansi: without it it reads \e[34m as 5 ordinary
#     characters, so it neither colours them nor stops counting those 9 bytes
#     towards the display width, and long rows get truncated early.
t_case_other_value() {
  # Declare it all at once, do not write another `local line` further down --
  # redeclaring a scalar local (and without an assignment) prints a `line=...`
  # line to stdout, which gets into the baseline.
  # KEY has to be declared: in ${(l:24:: :)KEY} below it is a **placeholder for
  # the positional parameter**, and under nounset an undeclared KEY counts as an
  # unset variable and errors. Its value is never used (only its length, 3).
  # pad is the same case: the value position in ${(l:N:: :)pad} cannot be left
  # out under nounset, a declared empty variable will do (a local without an
  # assignment already counts as "set", and reading it gives the empty string).
  local ESC=$'\e' BLUE RESET PAD r line v KEY=KEY pad
  local bad=0 f n_all n_ansi
  BLUE="${ESC}[34m"
  RESET="${ESC}[0m"
  PAD='                    '

  t_sep "value extraction: the alignment padding and the colour codes are dropped"
  # pad=${(l:N:: :)} is a trick this repo uses over and over: its **value** is the
  # empty string, and what it does is generate N spaces as one independent tab
  # segment. Under nounset the value position cannot be left out (it would count
  # as referencing an undeclared parameter), so pad needs a declared name.
  line="${(l:24:: :)pad}${BLUE}value${RESET}"
  print -r -- "  with colour and padding [$(_other_value "$line")]  (should be value)"
  line="${(l:24:: :)pad}a b c"
  print -r -- "  value has spaces  [$(_other_value "$line")]  (should be a b c, not just c)"

  t_sep "value extraction: a value containing spaces must come out whole"
  # A value the case builds itself, not this machine's environment. This used to
  # read __MISE_ORIG_PATH, which pinned the "896 characters" of this machine into
  # the baseline: on a machine without mise, this cell takes the else branch and
  # is skipped, the line count does not match, and the whole behaviour
  # comparison fails.
  v='alpha beta/gamma delta.app epsilon'
  line="SOME_LONG_KEY${(l:20:: :)pad}${BLUE}${v}${RESET}"
  r="${line%%[[:space:]]*} = $(_other_value "$line")"
  print -r -- "  the value has 4 spaces and 1 dot, the output is ${#r} characters (should differ by 15 = the key name plus ' = ')"
  if [[ $r == "SOME_LONG_KEY = $v" ]]; then
    print -r -- '  OK the value is kept whole, not reduced to the last field'
  else
    print -r -- "  *** error: the value was truncated, it is [$r]"
  fi
  # When the value has runs of spaces to begin with, extraction must not squeeze
  # them out -- what is taken is "everything after the first field"
  v='a  b   c'
  line="K${(l:20:: :)pad}${BLUE}${v}${RESET}"
  r="${line%%[[:space:]]*} = $(_other_value "$line")"
  if [[ $r == "K = a  b   c" ]]; then
    print -r -- '  OK runs of spaces are kept character for character'
  else
    print -r -- "  *** error: runs of spaces were altered, it is [$r]"
  fi

  t_sep "fzf is only called in _fc_fzf_read, and it gets --ansi (regression 2)"
  # Do not count the lines in the source that have `| fzf "`: once pathf and
  # envf went through _fc_fzf_read those two direct calls disappeared, so the
  # count reaches 0 == 0 and passes -- the gate passes because the thing under
  # test is gone, and its output looks exactly like "the check passed".
  #
  # Two things are asserted that cannot come out empty: the one fzf call in
  # base.zsh carries --ansi; and no file under collections calls fzf directly.
  if grep -qE '^\s*fzf .*--ansi' "$root"/base.zsh; then
    print -r -- '  OK   the fzf call in base.zsh has --ansi'
  else
    bad=1
    print -r -- '  *** error: the fzf call in base.zsh has no --ansi ***'
  fi
  local f2 n2
  n2=0
  for f2 in "$root"/base.zsh "$root"/collections/*.zsh; do
    [[ -f $f2 ]] || continue
    if grep -qE '^\s*fzf ' "$f2"; then
      if [[ $f2 == */base.zsh ]]; then
        print -r -- "  OK   base.zsh has 1 fzf call (the only one allowed)"
      else
        n2=$(( n2 + 1 ))
        print -r -- "  *** error: ${f2:t} calls fzf directly, it should go through _fc_fzf_read ***"
      fi
    fi
  done
  (( n2 == 0 )) || bad=1
  (( bad )) || print -r -- '  OK   only _fc_fzf_read calls fzf, in the whole repo'
}

# 18. The display width and value restoration of envf
#     The regression: in a real environment the value of PATH runs to a thousand
#     or two thousand characters (measured at 1994 in one session, 2562 in
#     another), and FPATH / LS_COLORS are just as over-wide. fzf can only
#     truncate them and scroll sideways, so a row shows only its tail and the
#     whole list looks misaligned. A pathf value is "directory + file name" and
#     is never wider than the screen, so it is unaffected -- that is why the two
#     commands behave differently.
#     After the display is truncated, selecting a row must still print the whole
#     value.
#
#     **Every asserted value in this case comes from a variable the case exports
#     itself; the machine's environment is not read.** This used to walk
#     PATH / FPATH / LS_COLORS / LUA_INIT / __MISE_ORIG_PATH …, which pinned
#     local state such as "LS_COLORS 1906 characters" or "__MISE_ORIG_PATH 896
#     characters" into the baseline: on another machine one variable fewer means
#     one line of output fewer, the behaviour comparison fails, and it fails for
#     a reason that has nothing to do with the code. The real environment keeps
#     one property assertion that does not depend on length (no row wider than
#     the screen), and it prints only the boolean, never a number.
t_case_envf_width() {
  # A temporary directory via mktemp -d, not $root -- $root is only defined in
  # tests/run.sh, so it is empty when this file is sourced on its own to call
  # some t_case_xxx.
  local ESC=$'\e'
  local ENVF_TMP
  # pad only fills the value position of ${(l:N:: :)pad}; its value is the empty
  # string (what it does is generate N spaces). Under nounset the value position
  # cannot be left out, so it has to be a declared name.
  local pad
  local valmax=${_ENVF_VALMAX:-$_FC_ENVF_WIDTH}
  ENVF_TMP=$(mktemp -d "${TMPDIR:-/tmp}/fzf-envf.XXXXXX") || return 1

  # ---- the case's own variables, with fixed values and fixed lengths ----
  local long
  # 300 characters, deterministically past the default truncation limit of 80
  long=${(l:300:: :)pad}
  long="${long// /x}"
  export _ENVF_T_SPACES='alpha beta/gamma delta.app'
  export _ENVF_T_LONG="$long"
  export _ENVF_T_NL=$'first\nsecond'
  export _ENVF_T_EQ='has=equals=inside'
  export _ENVF_T_EMPTY=''
  typeset -A want_val
  want_val=(
    _ENVF_T_SPACES 'alpha beta/gamma delta.app'
    _ENVF_T_LONG    "$long"
    _ENVF_T_NL      $'first\nsecond'
    _ENVF_T_EQ      'has=equals=inside'
    _ENVF_T_EMPTY   ''
  )

  t_sep "the value layer: the display is truncated, a selection must still print the whole value"
  # The stub: simulate "the user selected one row", going through envf's real
  # value loop.
  #
  # The stub must not be written `fzf() { while read l; ...; }` -- envf's fzf is
  # in a pipe, and the while inside the stub function reads **the function's
  # own** stdin rather than the candidates coming from the pipe, so it reads
  # nothing (which is why it once reported "actual 0" everywhere). The right way
  # is to write the candidates to a file first and pick from there.
  #
  # want / l / sel must be declared outside the loop -- a scalar local in a loop
  # body pollutes stdout.
  local want got l sel outf pick line
  for want in _ENVF_T_SPACES _ENVF_T_LONG _ENVF_T_NL _ENVF_T_EQ _ENVF_T_EMPTY; do
    outf=$ENVF_TMP/out.$$
    pick=$ENVF_TMP/pick.$$
    fzf() {
      cat > "$pick"
      # Strip the colour, pick that row out by the key name, and simulate what
      # fzf prints once something is selected
      sed "s/$ESC\\[[0-9;]*m//g" "$pick" 2>/dev/null \
        | while IFS= read -r sel; do
            [[ ${sel%%[[:space:]]*} == $want ]] && { print -r -- "$sel"; break }
          done
      rm -f "$pick"
    }
    envf > "$outf" 2>/dev/null
    got=$(<"$outf")
    rm -f "$outf"
    if [[ $got == "$want = ${want_val[$want]}" ]]; then
      # ${(l:24:: :)pad} rather than ${(l:24:: )}: the value position cannot be
      # left out under nounset, leaving it out counts as referencing an
      # undeclared parameter. pad is declared at the top of the function and its
      # value is the empty string, so this generates 24 spaces.
      print -r -- "  OK   ${(l:24:: :)pad}$want matches character for character"
    else
      print -r -- "  *** error $want: the expected length is $(( ${#want} + 3 + ${#want_val[$want]} )), the actual is ${#got}"
      print -r -- "        actual content [${got//[[:cntrl:]]/?}]"
    fi
  done

  t_sep "the display layer: a long value must be truncated (a 300-character value the case builds itself)"
  # Truncation only happens in the **display layer** (before _other_format), and
  # everything envf finally prints is the whole value -- that is exactly the
  # behaviour it should have, so envf's output cannot be used to test truncation.
  # What has to be tested is "what the row fzf receives looks like", which is
  # the row the stub picked.
  #
  # The assertion takes "the first valmax characters + ..." rather than
  # measuring the whole row: the row length also contains the alignment padding,
  # and the padding width depends on the longest key name on screen, which is
  # decided by a different variable.
  local disp
  for want in _ENVF_T_LONG _ENVF_T_SPACES; do
    pick=$ENVF_TMP/pick.$$
    disp=$ENVF_TMP/disp.$$
    fzf() {
      cat > "$pick"
      sed "s/$ESC\\[[0-9;]*m//g" "$pick" 2>/dev/null \
        | while IFS= read -r sel; do
            [[ ${sel%%[[:space:]]*} == $want ]] && { print -r -- "$sel" >"$disp"; break }
          done
      rm -f "$pick"
    }
    envf >/dev/null 2>&1
    got=""
    if [[ -f $disp ]]; then
      got=$(_other_value "$(<"$disp")")
    fi
    if [[ $want == _ENVF_T_LONG ]]; then
      if [[ $got == "${long[1,$valmax]}..." ]]; then
        print -r -- "  OK   a long value is shown as its first $valmax characters + ... (${#got} characters in total)"
      elif [[ $got == "$long" ]]; then
        print -r -- '  *** error: it is not truncated at all, a row wider than the screen makes fzf scroll sideways ***'
      else
        print -r -- "  *** error: the truncation length is wrong, ${#got} characters (should be $(( valmax + 3 )))"
      fi
    else
      if [[ $got == 'alpha beta/gamma delta.app' ]]; then
        print -r -- '  OK   a short value is shown as it is, not truncated'
      else
        print -r -- "  *** error: a short value was altered [$got]"
      fi
    fi
  done

  t_sep "the display layer: no row in the real environment is wider than the screen (property only, no length recorded)"
  # This deliberately prints only the boolean result: the length of the real
  # PATH / FPATH differs per machine, and putting a number into the baseline is
  # the same as pinning local state. The property itself (no row over 200
  # columns) holds everywhere.
  local probe=$ENVF_TMP/probe.$$
  local over
  fzf() { cat > "$probe"; return 0; }
  # envf has to write to the file directly, it must not be captured with
  # $(envf) -- once the stub has written the candidates to the file there is no
  # output left in the pipe, envf returns early, and the command substitution
  # ends up fighting the stub over the same probe file, so neither side can read
  # it.
  envf >/dev/null 2>&1
  if [[ -f $probe ]]; then
    over=$(awk 'length($0) > 200 { c++ } END { print c + 0 }' "$probe")
    if (( over == 0 )); then
      print -r -- '  OK   no row in the real environment is over 200 columns'
    else
      print -r -- "  *** error: $over rows are over 200 columns, the truncation is not taking effect"
    fi
  else
    print -r -- '  *** error: envf produced no candidates (the stub did not work)'
  fi
  rm -f "$probe"

  unset _ENVF_T_SPACES _ENVF_T_LONG _ENVF_T_NL _ENVF_T_EQ _ENVF_T_EMPTY
  rm -rf "$ENVF_TMP"
}

# 19. Parsing uvf's list
#     Neither uv's `tool list` nor `tool list --outdated` accepts --format json,
#     so the rows of both the manage and the outdated view have to be parsed out
#     of text; that makes this the only behaviour of uvf worth pinning: the
#     top-level rows and the `- exe` rows come out of one and the same output,
#     and the bracketed annotations grow with every --show-* (see the comment in
#     _uvf_list_outdated). uv is stubbed rather than really called: this case has
#     to run on a machine without uv too.
#
# On equality the actual value is printed alongside (it goes into the baseline,
# comparable byte for byte); on inequality, actual and expected are both printed.
# A tab is displayed as -> , so that no bare tab gets into the baseline.
t_uvf_expect() {      # $1=actual $2=expected $3=description
  local got=${1//$'\t'/->} want=${2//$'\t'/->}
  if [[ $1 == "$2" ]]; then
    print -r -- "  OK   $3: [$got]"
  else
    print -r -- "  *** error $3: actual [$got], expected [$want]"
  fi
}

t_case_uvf_rows() {
  local got want
  # The stub: every line of $UV_STUB is one line uv printed. When UV_STUB is
  # empty ${(f)UV_STUB} still yields one empty element and the stub prints a
  # blank line; the parser drops it as "fewer than two segments", so the
  # expected value of the "no tools installed" cell is still empty.
  #
  # Saving and restoring the original function has to use ${:-}: `$functions[uv]`
  # only exists on a machine that has uv installed, and the whole premise of this
  # case is "it has to run on a machine without uv" (see the comment above).
  # Under nounset a bare reference to an unset subscript of an associative array
  # ends the script, so on a machine without uv this case would never reach the
  # assertion -- the gate would fail because the condition under test does not
  # exist, not because the code is wrong.
  #
  # The restore at the end uses ${:-} too: without uv installed there is no
  # uv_orig, so restoring means deleting the stub.
  #
  # **Do not casually call the real uv.** The stub replaces a function definition
  # of the same name, and the uv call in _uvf_list_installed resolves to this
  # stub -- on the condition that uv is **not** an external command cached in
  # this process's hash table. So the external uv has to be dropped with hash -r
  # first for the stub to take effect, and put back at the end. Without these
  # two lines, on a machine with uv installed this case really runs
  # `uv tool list`, waits out the 0.7s network round trip for an output that has
  # nothing to do with UV_STUB, and then judges the whole case wrong.
  hash -r 2>/dev/null
  functions[uv_orig]=${functions[uv]:-}
  uv() { print -rl -- ${(f)UV_STUB} }

  t_sep "manage: take the name and version from the top-level rows, drop the executable rows that start with -"
  UV_STUB=$'browser-use v0.13.10\n- browser\n- bu\nwatchdog v6.0.0\n- watchmedo'
  got=$(_uvf_list_installed)
  want=$'browser-use\t0.13.10\nwatchdog\t6.0.0'
  t_uvf_expect "$got" "$want" 'two tools'

  t_sep "manage: no tools installed (uv prints No tools installed, to stderr)"
  UV_STUB=''
  got=$(_uvf_list_installed)
  t_uvf_expect "$got" '' 'no output'

  t_sep "manage: a row with only an executable name is not a tool (no version in the name)"
  UV_STUB=$'- watchmedo'
  got=$(_uvf_list_installed)
  t_uvf_expect "$got" '' 'no output'

  t_sep "outdated: split into the four columns name/current/=>/latest"
  UV_STUB=$'ruff v0.2.0 [latest: 0.16.9]\n- ruff'
  got=$(_uvf_list_outdated)
  want=$'ruff\t0.2.0\t=>\t0.16.9'
  t_uvf_expect "$got" "$want" 'one tool'

  t_sep "outdated: the other bracketed annotations and the path must be cut off first, they must not get into the version"
  # This row carries [required:] [CPython] [latest:] and the env path at the end
  # at the same time -- if the cutting happened before [latest:] was picked out,
  # the version column would become "0.1.0] [required: ==0.1.0]..."
  UV_STUB=$'ruff v0.1.0 [required: ==0.1.0] [CPython 3.14.7] [latest: 0.16.9] (/tmp/t/ruff)'
  got=$(_uvf_list_outdated)
  want=$'ruff\t0.1.0\t=>\t0.16.9'
  t_uvf_expect "$got" "$want" 'the annotations and the path are both cut off'

  t_sep "outdated: when it is already the latest, uv prints nothing at all (the view should be empty)"
  UV_STUB=''
  got=$(_uvf_list_outdated)
  t_uvf_expect "$got" '' 'no output'

  # On a machine without uv there is no uv_orig: the stub is then the only
  # source, and deleting it is the restore.
  if (( ${+functions[uv_orig]} )); then
    functions[uv]=${functions[uv_orig]}
  else
    unfunction uv 2>/dev/null
  fi
  unset 'uv_orig'
  # Put the external uv back into the hash table, or every later call to uv in
  # this process keeps going through the stub.
  hash -r 2>/dev/null
}

# 24. requires: the dependency check declared per ecosystem.
#
#     Two things have to hold, and neither is visible from reading the code:
#       1. every `*-f` entry point actually goes through the check. ghf is the
#          trap: it skips the view menu and calls _fc_session directly, so it
#          never reaches the check _fc_cmd does, and it has to ask for itself.
#       2. a missing command is named. The alternative failure is silence: the
#          view opens and the query returns nothing, which reads as "you have no
#          packages installed".
#
#     How it runs: _fc_have_cmd is stubbed, so this does not depend on what is
#     installed here. The stub answers "everything exists" first, to prove the
#     check does not fire when it should not, and then "nothing exists", to
#     prove it fires and says what.
t_case_requires() {
  local key eco view
  local out
  local -a ecos entries
  local bad=0 c pad
  local -a names

  t_sep "every entry point runs the check"
  # The nine public commands. Each is called with _fc_have_cmd answering "no",
  # so a command that skips the check produces no message at all.
  functions[_t_p8_have_orig]=$functions[_fc_have_cmd]
  functions[_t_p8_read_orig]=$functions[_fc_fzf_read]
  # fzf counts as present throughout: it is checked for every command, and
  # leaving it out of the stub would put it in every message and bury the name
  # this case is actually about.
  _fc_have_cmd() { [[ $1 == fzf ]] }
  _fc_fzf_read() { cat >/dev/null; return 130 }
  names=(brewf npmf pnpmf pipf uvf gemf ghf pathf envf)
  for c in "${names[@]}"; do
    out=$($c 2>&1)
    if [[ $out == *'fzf-collection: missing'* ]]; then
      print -r -- "  OK   $c checks its requirements"
    else
      bad=1
      print -r -- "  *** error: $c does not check its requirements, output [$out]"
    fi
  done

  t_sep "the missing names are spelled out"
  out=$(gemf 2>&1)
  if [[ $out == *'missing gem.'* ]]; then
    print -r -- '  OK   gem is named'
  else
    bad=1
    print -r -- "  *** error: gem is not named, actual [$out]"
  fi
  out=$(npmf 2>&1)
  if [[ $out == *'missing npm, all-the-package-names.'* ]]; then
    print -r -- '  OK   several missing commands are listed in order'
  else
    bad=1
    print -r -- "  *** error: actual [$out]"
  fi
  out=$(pipf 2>&1)
  if [[ $out == *'missing pip3|pip.'* ]]; then
    print -r -- '  OK   the alternatives are named as one item'
  else
    bad=1
    print -r -- "  *** error: actual [$out]"
  fi
  out=$(pathf 2>&1)
  if [[ $out == *'missing find, uniq.'* ]]; then
    print -r -- '  OK   pathf is not an ecosystem and declares its own'
  else
    bad=1
    print -r -- "  *** error: actual [$out]"
  fi

  t_sep "alternatives: one hit is enough"
  _fc_have_cmd() { [[ $1 == fzf || $1 == pip ]] }
  out=$(pipf 2>&1)
  if [[ $out != *'missing'* ]]; then
    print -r -- '  OK   passes with pip present and pip3 absent'
  else
    bad=1
    print -r -- "  *** error: still reports a missing command [$out]"
  fi

  t_sep "nothing is reported when everything is present"
  _fc_have_cmd() { return 0 }
  for c in "${names[@]}"; do
    out=$($c 2>&1)
    if [[ $out == *missing* ]]; then
      bad=1
      print -r -- "  *** error: $c still reports a missing command with all present [$out]"
    fi
  done
  print -r -- '  OK   none of the nine entry points reports anything'

  t_sep "the registry: every ecosystem declares requires"
  ecos=()
  for key in "${(@k)_FC_REG}"; do
    [[ $key == *:requires ]] || continue
    ecos+=("${key%%:*}")
  done
  ecos=(${(u)ecos})
  print -r -- "  declared: ${(j: :)ecos}"
  for eco in $ecos; do
    out=$(_fc_reg_get "$eco" requires)
    if [[ -n $out ]]; then
      print -r -- "  OK   ${(l:6:: :)pad}$eco -> $out"
    else
      bad=1
      print -r -- "  *** error: $eco declares no requires"
    fi
  done
  # fzf must not be in any of them: _fc_require checks it once, for everyone.
  for eco in $ecos; do
    for c in ${(s: :)$(_fc_reg_get "$eco" requires)}; do
      if [[ $c == fzf ]]; then
        bad=1
        print -r -- "  *** error: $eco lists fzf, which _fc_require checks for everyone"
      fi
    done
  done
  print -r -- '  OK   no ecosystem lists fzf itself'

  unfunction _fc_have_cmd _fc_fzf_read
  eval "_fc_have_cmd() { $functions[_t_p8_have_orig] }"
  eval "_fc_fzf_read() { $functions[_t_p8_read_orig] }"
  unfunction _t_p8_have_orig _t_p8_read_orig
  (( bad )) || print -r -- '  OK   requires all good'
  return 0
}

# 23. The entry layer: the commands that can be called with no arguments, and
#     the places that read the user's environment variables.
#
#     These two kinds of place break most easily under nounset, and the syntax /
#     hygiene / baseline gates all miss them -- they are syntactically correct
#     and cleanly written, they just reference a value that may not exist:
#       - a no-argument call into a function whose normal use has arguments
#         (pathf) writing `[[ "$1" == ... ]]`
#       - reading $EDITOR / $VISUAL and other external variables that may not be
#         set
#
#     How it runs: stub out the external commands the function under test
#     depends on, and require only that it "does not terminate on an unset
#     parameter". Note this case must **not** be taken for done because it
#     passed locally -- with EDITOR set, a bare $EDITOR is perfectly fine. It
#     only has discriminating power in the tests/run.sh --nounset round.
t_case_entry_params() {
  local got l
  local bad=0

  # ---- pathf: called with no arguments ----
  # Stub fzf so that it walks the whole pipe without interacting, and let fzf
  # select the first row, so that the while loop downstream of the pipe really
  # runs -- that is where $1 is read. find is stubbed because pathf needs a GNU
  # find with -printf / -executable, while the one macOS ships is a BSD find
  # (which fails outright with "unknown primary or operator"), and the case
  # must not depend on whether the caller has findutils installed.
  functions[_t_p7_fzf_orig]=$functions[_fc_fzf_read]
  # ${:-} as in t_case_uvf_rows: find is normally an external command and has no
  # functions entry, and a bare reference ends the whole script under nounset.
  functions[_t_p7_find_orig]=${functions[find]:-}
  _fc_fzf_read() { while IFS= read -r l; do print -r -- "$l"; break; done; return 0 }
  find() { print -r -- 'mytool /some/dir'; return 0 }
  got=$(pathf 2>&1)
  if print -r -- "$got" | grep -qE 'parameter not set|bad substitution'; then
    bad=1
    print -r -- '  *** error: calling pathf with no arguments errors under nounset ***'
    print -r -- "$got" | head -3 | sed 's/^/        /'
  elif [[ $got != *'/some/dir/mytool' ]]; then
    bad=1
    print -r -- "  *** error: calling pathf with no arguments did not reach the extraction step, it is [$got] (the stub did not work)"
  else
    print -r -- "  OK   calling pathf with no arguments prints [$got]"
  fi
  # With -d it must print directories only
  got=$(pathf -d 2>&1)
  if [[ $got == '/some/dir/' ]]; then
    print -r -- '  OK   pathf -d prints directories only'
  else
    bad=1
    print -r -- "  *** error: pathf -d is [$got]"
  fi

  # ---- brew edit: $EDITOR / $VISUAL ----
  # Stub brew and "the editor". The editor is a function rather than an external
  # command: putting an external command name in VISUAL means the text of a
  # command not found error gets into $got as well.
  functions[_t_p7_brew_orig]=$functions[_brewf]
  _brewf() {
    if [[ $1 == formula ]]; then
      print -r -- /tmp/fake-formula.rb
    fi
    return 0
  }
  _t_p7_editor() { print -r -- "EDITOR-CALLED $*"; }
  # vi has to be stubbed too: with both EDITOR and VISUAL unset, _brewf_edit
  # really does start vi and waits for the user to edit, so the test hangs there
  # (measured: tests/run.sh --record timed out outright). A function takes
  # precedence over the PATH lookup, so a function of the same name stops that
  # fallback.
  vi() { print -r -- "EDITOR-CALLED(vi) $*"; }
  # Only unsetting can verify the fallback: while it is set, a bare $EDITOR of
  # course does not error.
  # The package name has to be passed: _brewf_edit reads $1 itself (to hand it to
  # brew formula), and a call with no arguments blows up there first under
  # nounset, so the EDITOR layer would never be reached.
  unset EDITOR VISUAL
  got=$(_brewf_edit somepkg 2>&1)
  if print -r -- "$got" | grep -qE 'parameter not set|bad substitution'; then
    bad=1
    print -r -- '  *** error: _brewf_edit errors with neither EDITOR nor VISUAL set ***'
    print -r -- "$got" | head -3 | sed 's/^/        /'
  elif [[ $got != 'EDITOR-CALLED(vi) /tmp/fake-formula.rb' ]]; then
    bad=1
    print -r -- "  *** error: the fallback did not land on vi, it is [$got]"
  else
    print -r -- "  OK   _brewf_edit has a fallback, it lands on [$got]"
  fi
  got=$(VISUAL=_t_p7_editor EDITOR=other-editor _brewf_edit somepkg 2>&1)
  if [[ $got == 'EDITOR-CALLED /tmp/fake-formula.rb' ]]; then
    print -r -- '  OK   VISUAL wins over EDITOR'
  else
    bad=1
    print -r -- "  *** error: VISUAL did not win, it is [$got]"
  fi
  unset VISUAL EDITOR

  # ---- _fc_render: callable with no arguments (a single-column render with no cols) ----
  _FC_ROWS=("alpha" "beta")
  got=$(_fc_render 2>&1)
  if [[ $got == *'parameter not set'* ]]; then
    bad=1
    print -r -- '  *** error: calling _fc_render with no arguments errors under nounset ***'
  else
    print -r -- "  OK   calling _fc_render with no arguments is fine, it prints [${got//$'\n'/,}]"
  fi
  _FC_ROWS=()

  unfunction _fc_fzf_read _brewf _t_p7_editor vi find
  eval "_fc_fzf_read() { $functions[_t_p7_fzf_orig] }"
  eval "_brewf() { $functions[_t_p7_brew_orig] }"
  # find may be an external command with no functions entry, in which case the
  # stub was never installed to begin with, and restoring "there is no such
  # function" is right.
  if (( ${+functions[_t_p7_find_orig]} )); then
    eval "find() { $functions[_t_p7_find_orig] }"
  fi
  unfunction _t_p7_fzf_orig _t_p7_brew_orig _t_p7_find_orig
  (( bad )) || print -r -- '  OK   the whole entry layer passes'
  return 0
}

# 21. The colour layer: role name resolution, the colour switch, _fc_sgr_strip
#
# 1. A wrong role name must degrade **and warn**. The lookup cannot go by
#    "is it empty": the value of 'name' is the empty string (meaning explicitly
#    no colour) and a misspelled name finds no value either, so only [[ -v ]]
#    can tell them apart.
# 2. The colour-off output has to be byte-for-byte identical to "colour on, then
#    stripped" -- and that also pins "the colour codes do not go into the
#    alignment calculation": _fc_render pads first and colours after, so a
#    change on either side shows up here.
# 3. _fc_sgr_strip recognises the SGR itself, not the current palette. So it is
#    asserted with a colour that is not in the palette (magenta), with a
#    multi-parameter SGR and with true colour -- using only the colours of the
#    current palette cannot tell anything.
t_case_palette() {
  local out p spec role i escf
  local -a colored plain stripped

  t_sep "role name -> SGR prefix (the empty string is legal too: it means no colour and no warning)"
  for spec in name have sep want msg ''; do
    _fc_sgr_prefix "$spec"
    p=$_FC_SGR_PREFIX
    print -r -- "  ${(qq)spec} -> ${(qq)p}"
  done

  t_sep "a numeric spec now counts as an unknown name: it warns and degrades"
  # 34 / 1;32 used to be legal ways of writing an SGR parameter, and 0 and -
  # meant "no colour". A spec can now only be a role name, so they all take the
  # "unknown name" path. This is asserted because it is the only change in this
  # pass that **deliberately** invalidates the old form.
  escf=$(mktemp)
  _FC_SGR_WARNED=0
  local warned=0
  for spec in 34 33 1\;32 0 -; do
    _fc_sgr_prefix "$spec" 2>"$escf"
    p=$_FC_SGR_PREFIX
    w=$(<"$escf")
    [[ -n $w ]] && warned=1
    print -r -- "  ${(qq)spec} -> [${(qq)p}]${w:+  warning: $w}"
  done
  print -r -- "  only the first one warns: $( (( warned )) && print yes || print no ) (de-duplication is _FC_SGR_WARNED)"
  rm -f "$escf"
  _FC_SGR_WARNED=0

  t_sep "an unknown role name: it degrades to no colour + warns exactly once"
  escf=$(mktemp)
  _FC_SGR_WARNED=0
  _fc_sgr_prefix nope 2>"$escf"
  p=$_FC_SGR_PREFIX
  print -r -- "  prefix=[${(qq)p}] (should be the empty string, i.e. no colour)"
  print -r -- "  warning: $(<"$escf")"
  # The second one has to be silent. _fc_sgr_prefix goes through an output
  # variable rather than print, precisely so that this flag survives in the
  # current shell -- through a command substitution the assignment lands in a
  # subshell and it complains all over again every time.
  _fc_sgr_prefix alsowrong 2>"$escf"
  p=$_FC_SGR_PREFIX
  print -r -- "  wrong once more: [$(<"$escf")] (should be empty, one session complains once)"
  rm -f "$escf"
  _FC_SGR_WARNED=0

  t_sep "the colour switch: with colour off there are zero escapes, byte-for-byte the same as colour on then stripped"
  _FC_REG+=('pal:manage:cols' 'name have sep want')
  _FC_ROWS=("alpha	1.0	=>	2.0"
             "much-longer-name	22	=>	22")
  colored=("${(@f)$(_fc_render pal manage)}")
  _FC_COLOR=0
  plain=("${(@f)$(_fc_render pal manage)}")
  _FC_COLOR=1
  print -r -- "  ${#colored} rows with colour / ${#plain} rows without"
  if [[ ${(j: :)plain} == *$'\e'* ]]; then
    print -r -- '  *** error: there are still escape sequences with colour off ***'
  else
    print -r -- '  OK the colour-off output contains no ESC'
  fi
  stripped=()
  local same=1
  for (( i = 1; i <= ${#colored}; i++ )); do
    stripped[i]=$(_fc_sgr_strip "$colored[i]")
    # Compare row by row rather than joining the array and comparing once: the
    # separator of a join is a literal argument of the flag, the $'\n' in
    # ${(j: :.)arr} is not evaluated (the same family of flag traps as elsewhere
    # in this project), and comparing row by row can also point at which row is
    # the first to differ.
    if [[ ${stripped[i]} != ${plain[i]:-} ]]; then
      same=0
      print -r -- "  *** row $i differs ***"
    fi
  done
  (( ${#colored} == ${#plain} )) || same=0
  if (( same )); then
    print -r -- '  OK the stripped colour-on output == the colour-off output'
  else
    print -r -- '  *** error: the colour affected the row content (most likely the colour codes got into the alignment calculation) ***'
  fi
  unset '_FC_REG[pal:manage:cols]'

  t_sep "_fc_sgr_strip: it recognises the SGR itself, whatever palette is in use"
  # ${(ok)_FC_SGR}: o = sort by key. Without it the iteration order of an
  # associative array is not guaranteed and the baseline drifts at random --
  # output that unstable must never get into the baseline.
  for role in ${(ok)_FC_SGR}; do
    p=$(_fc_sgr_paint "$role" 'X')
    out=$(_fc_sgr_strip "$p")
    if [[ $out == X ]]; then
      print -r -- "  ${(qq)role} ${(qq)p}X -> OK"
    else
      print -r -- "  ${(qq)role} -> *** error: something is left after stripping [${(qq)out}] ***"
    fi
  done
  # A colour that is not in the palette, a multi-parameter SGR, 24-bit true
  # colour: none of them may affect the stripping.
  for spec in $'\e[35m' $'\e[1;32m' $'\e[38;2;255;128;0m'; do
    out=$(_fc_sgr_strip "${spec}X${_FC_SGR_RESET}")
    if [[ $out == X ]]; then
      print -r -- "  ${(qq)spec} -> OK"
    else
      print -r -- "  ${(qq)spec} -> *** error: something is left after stripping [${(qq)out}] ***"
    fi
  done
  out=$(_fc_sgr_strip $'a\tb\e[34mc\e[0md')
  print -r -- "  mixed in the middle: [${(qq)out}] (should contain one real tab)"
}

# 22. View-level fzf-opts must actually reach fzf.
#
#     Regression: base.zsh parsed fzf-opts into a local `fzfopts` and then never
#     used it, passing an undeclared `$opt` to _fc_feed instead. Every
#     `*:fzf-opts` in the registry was therefore dead -- including
#     npm:search's `--tiebreak=begin,length,index`, which is the sort order for
#     a 4.5-million-name list.
#
#     The nounset gate (tests/run.sh) catches the *symptom* -- an unset `$opt`
#     is a "parameter not set" error. It cannot catch "parsed but never passed",
#     because an unset `$opt` expands to nothing and silently vanishes. So this
#     case asserts the argv directly.
#
#     Precedence asserted here, since it is what the fix has to get right:
#     FZF_COLLECTION_OPTS (--no-multi) < the driver's --multi < view fzf-opts.
#     fzf takes the last flag, so a view can opt back out of --multi.
t_case_fzf_opts() {
  local argf cnt
  local k
  local n
  local line
  local bad=0
  local -a calls
  cnt=$(mktemp)
  argf=$(mktemp)
  print -r -- 0 >"$cnt"
  : >"$argf"

  functions[_t_read_orig]=$functions[_fc_fzf_read]
  # argv must land in a file: _fc_fzf_read is called inside $(...) and a
  # variable set in that subshell does not survive.
  _fc_fzf_read() {
    local n
    n=$(<"$cnt")
    n=$(( n + 1 ))
    print -r -- "$n" >"$cnt"
    print -r -- "$*" >>"$argf"
    cat >/dev/null
    case $n in
      1) print -r -- $'alpha\t1.0' ;;
      2) print -r -- 'go' ;;
      *) return 130 ;;
    esac
  }
  _t_p5_list() { printf 'alpha\t1.0\n' }
  _t_p5_act() { : }
  _FC_REG+=(
    'p5:title'   'P5'
    'p5:views'   'manage'
    'p5:manage'  '_t_p5_list'
    'p5:manage:title'   'P5 Manage'
    'p5:manage:actions' 'go'
    'p5:manage:cols'    'name have'
    'p5:manage:fzf-opts' '--tiebreak=index --no-sort'
    'p5:mutating' 'go'
    'p5:fallback'   '_t_p5_act'
  )

  _fc_session p5 manage

  t_sep "the argv the view's fzf-opts reach fzf with"
  calls=("${(@f)$(<"$argf")}")
  n=0
  for line in "${calls[@]}"; do
    (( n++ ))
    print -r -- "  fzf#$n argv: [$line]"
  done
  # Call 1 is the package list, call 2 the action submenu. Only the list call
  # carries the view's fzf-opts; the submenu goes through _fc_actions, which
  # passes nothing and must stay that way.
  if [[ ${calls[1]:-} == *'--tiebreak=index'* ]]; then
    print -r -- '  OK   --tiebreak=index reached fzf'
  else
    bad=1
    print -r -- '  *** error: --tiebreak=index did not reach fzf (fzf-opts was parsed and then unused) ***'
  fi
  if [[ ${calls[1]:-} == *'--no-sort'* ]]; then
    print -r -- '  OK   --no-sort reached fzf'
  else
    bad=1
    print -r -- '  *** error: --no-sort did not reach fzf ***'
  fi
  if [[ ${calls[1]:-} == *'--multi'* ]]; then
    print -r -- '  OK   --multi is still there (the driver default was not squeezed out by fzf-opts)'
  else
    bad=1
    print -r -- '  *** error: --multi is gone ***'
  fi
  if [[ ${calls[2]:-} == *'--no-sort'* ]]; then
    bad=1
    print -r -- '  *** error: the action submenu must not take the view fzf-opts ***'
  else
    print -r -- '  OK   the action submenu does not take fzf-opts'
  fi
  (( bad )) || print -r -- '  OK   every fzf-opts is in place'

  t_sep "every fzf-opts declared in the registry has to be a legal flag"
  # key / tok / toks are declared outside the loop: a scalar local in a loop
  # body prints a NAME=value line to stdout, and this function's stdout is the
  # content compared with the baseline character for character, so that line
  # would become part of the baseline.
  local key tok
  local -a toks
  for key in "${(@k)_FC_REG}"; do
    [[ $key == *:fzf-opts ]] || continue
    toks=(${(s: :)_FC_REG[$key]})
    for tok in "${toks[@]}"; do
      if [[ $tok == --* ]]; then
        print -r -- "  OK   $key -> $tok"
      else
        bad=1
        print -r -- "  *** error: the '$tok' of $key is not a flag ***"
      fi
    done
  done

  unfunction _fc_fzf_read _t_p5_list _t_p5_act
  eval "_fc_fzf_read() { $functions[_t_read_orig] }"
  unfunction _t_read_orig
  for k in title views manage manage:title manage:actions manage:cols \
           manage:fzf-opts mutating fallback; do
    unset "_FC_REG[p5:$k]"
  done
  rm -f "$cnt" "$argf"
}

# 20. The README agrees with the code
#     The README used to list a `uvf` that did not exist and a `registry` view
#     that did not exist, leave out pinned / gemf / envf, and its dependency
#     table mentioned only grep coreutils and gh jq. Documentation drift breaks
#     nothing, so nobody notices -- except whoever goes looking for it on
#     purpose. cargof / ffp are gone and fp has been renamed to pathf, so the
#     lists in this case have to follow, or it takes "the docs mention a command
#     that does not exist" for correct.
#     uvf really was added later: the list here gained it, and with it the
#     assertion about uvf further down, under "names that must not appear", was
#     dropped -- that assertion existed because uvf really did not exist then.
t_case_readme() {
  local R=$root/README.md
  if [[ ! -f $R ]]; then
    print -r -- '  (no README.md, skipped)'
    return 0
  fi

  t_sep "public commands: the README must list every one of them, no more and no fewer"
  local -a want
  want=(brewf npmf pnpmf pipf uvf gemf ghf pathf envf)
  local c
  for c in "${want[@]}"; do
    if grep -qF -- "\`$c\`" "$R"; then
      print -r -- "  OK   $c is listed"
    else
      print -r -- "  *** error: the README does not list $c"
    fi
  done
  # The other direction: a command name the README mentions has to exist.
  # fzf is excluded -- it is the project name and a dependency name, not a
  # command this plugin defines.
  local -a defined
  defined=(${(f)"$(grep -hoE '^[a-z][a-z0-9]*\(\)' "$root"/base.zsh "$root"/collections/*.zsh \
             | tr -d '()' | sort)"})
  for c in ${(f)"$(grep -oE '`[a-z]+f`' "$R" | tr -d '`' | sort -u)"}; do
    [[ $c == fzf ]] && continue
    (( ${defined[(Ie)$c]} )) || print -r -- "  *** error: the README mentions $c, but there is no such function in the code"
  done

  t_sep "the view list: the README must cover every view in the registry, and write nothing extra"
  local eco v line miss extra
  for eco in brew npm pnpm pip uv gem gh; do
    local -a vs
    vs=(${(s: :)${_FC_REG[$eco:views]}})
    (( ${#vs} )) || continue
    line=$(grep -m1 "^\`${eco}f\`:" "$R")
    if [[ -z $line ]]; then
      print -r -- "  *** error: the README has no command line for ${eco}f"
      continue
    fi
    miss=""
    for v in "${vs[@]}"; do
      [[ $line == *"\`$v\`"* ]] || miss+=" $v"
    done
    extra=""
    for v in ${(z)${(s. .)${line#*: }}}; do
      v=${v//\`/}
      [[ -z $v ]] && continue
      (( ${vs[(Ie)$v]} )) || extra+=" $v"
    done
    if [[ -n $miss ]]; then
      print -r -- "  *** error ${eco}f is missing the view:$miss"
    elif [[ -n $extra ]]; then
      print -r -- "  *** error ${eco}f writes a view that does not exist:$extra"
    else
      print -r -- "  OK   ${eco}f: ${(j: :)vs}"
    fi
  done

  t_sep "names that must not appear"
  # This used to assert as well that the README must not mention uvf / fzf-uv --
  # it held back then because uvf really did not exist. Once uvf was added those
  # two premises were gone, and "a command the README mentions must really
  # exist" is already checked one by one in the reverse check above (grep
  # '`[a-z]+f`' against defined), so there is no need to keep a hand-written list
  # of them here as well.
  if grep -qF '`registry`' "$R"; then
    print -r -- '  *** error: the README mentions the registry view, but the registry has none'
  else
    print -r -- '  OK   it does not mention the registry view'
  fi

  t_sep "the default module list"
  # Both sides are normalised into "space separated, no leading or trailing
  # space" before comparing, otherwise trailing spaces disguise themselves as a
  # mismatch (hit once).
  local real_mods readme_mods
  real_mods=$(print -l -- ${FZF_COLLECTION_MODULES} | tr '\n' ' ')
  readme_mods=$(sed -n '/^FZF_COLLECTION_MODULES=($/,/^  )$/p' "$R" \
                | sed '1d;$d' | tr -d ' ' | tr '\n' ' ')
  real_mods=${real_mods%% }
  readme_mods=${readme_mods%% }
  print -r -- "  code:   [${real_mods}]"
  print -r -- "  README: [${readme_mods}]"
  if [[ $real_mods == $readme_mods ]]; then
    print -r -- '  OK   they agree'
  else
    print -r -- '  *** error: the default module lists differ'
  fi

  t_sep "dependencies: what the README mentions must really be called, and what the code uses must be mentioned"
  # The whitelist has to exhaust the external commands. The earlier whitelist
  # left out curl, so the fact that pipf's search fetches the index page with
  # curl was in neither version of the dependency table, and this check would
  # never have caught it. Better to list a few candidates too many (and only
  # then decide whether the call is real) than to leave one out.
  #
  # Take the words themselves with grep -w, not by splitting on a character
  # class -- the latter takes fragments carrying a separator, like "brew:" or
  # "(find", for words, and reports a pile of bogus "the code uses X".
  # head / tail are not listed separately: head is only used together with find;
  # in gem, tail is a variable name. cut is part of the streaming search path
  # (see _fc_view_streamable), and sed is what pipf uses to pick the links out of
  # the index page (870k lines, see _pipf_list_available), so both have to be
  # listed. uv goes last: it is the shortest one in the alternation, and putting
  # it earlier also splits uvtool and the like out (-w blocks most of that, but
  # there is no reason to rely on it).
  local -a used
  used=(${(u)${(s: :)$(grep -hvE '^\s*#' "$root"/base.zsh "$root"/collections/*.zsh \
        | sed 's/[[:space:]]#.*$//' \
        | grep -howE 'all-the-package-names|pip-autoremove|brew|npm|pnpm|pip3?|gem|gh|jq|curl|find|git|grep|cut|sed|sort|uniq|printenv|less|open|dirname|uv' | tr 'A-Z' 'a-z' | sort -u)}})
  for c in "${used[@]}"; do
    # It has to be in the **dependency table**, i.e. on a table row starting with
    # "| `". This used to check only "the README mentions it somewhere", so a
    # passing mention in the prose was enough to get by -- an injection test
    # proved it: delete curl from the table and leave it in the prose, and the
    # check still passes.
    if grep -E '^\| ' "$R" | grep -qF "$c"; then
      :
    else
      print -r -- "  *** error: the code uses $c, and the README dependency table does not have it"
    fi
  done
  print -r -- "  all ${#used[@]} external commands used by the code are in the dependency table"
  # perl / column are gone for good, the README must not claim them
  for c in perl column; do
    n=$(grep -hvE '^\s*#' "$root"/base.zsh "$root"/collections/*.zsh | grep -cE "\b$c\b")
    if (( n == 0 )) && grep -qiE "install.*\b$c\b|\b$c\b.*install" "$R"; then
      print -r -- "  *** error: the README still claims $c is needed, but the code no longer calls it"
    else
      print -r -- "  OK   the code calls $c $n times, the README does not claim it is needed"
    fi
  done

  t_sep "tunables: every overridable variable in the code must be in the README, with the same name"
  # Checked in both directions. This used to check only the _ENVF_VALMAX
  # direction, so _FC_COLUMN_GAP slipped through.
  #
  # Whole-line comments have to be removed first. This gate used to scan the
  # whole file, so writing a lowercase example of the same shape in a comment
  # conjured up an extra "tunable" out of thin air and then demanded that the
  # README document it -- the variable is fake, the gate is real. The dependency
  # gate has always had `grep -hvE '^\s*#'`, this one did not. Only whole-line
  # comments are removed, trailing ones are left alone: removing a trailing
  # comment would treat the # inside a string like `... # ...` as the start of a
  # comment and cut away a real tunable that may follow, and a missed report is
  # harder to notice than a false one.
  local -a tunable
  tunable=(${(u)${(s: :)$(grep -hvE '^\s*#' "$root"/base.zsh "$root"/collections/*.zsh \
          | grep -hoE '\$\{[A-Z_][A-Z0-9_]*:-' \
          | sed 's/\${//;s/:-//')}})
  # General environment variables are not the plugin's own tunables. EDITOR /
  # VISUAL appear in the ${VISUAL:-${EDITOR:-vi}} fallback in _brewf_edit (a bare
  # $EDITOR errors under nounset when it is unset); the user's shell environment
  # provides them, and the README only mentions them in the dependency table.
  tunable=(${tunable:#PAGER})
  tunable=(${tunable:#EDITOR})
  tunable=(${tunable:#VISUAL})
  local vname
  for vname in "${tunable[@]}"; do
    if grep -qF "$vname" "$R"; then
      print -r -- "  OK   $vname is documented"
    else
      print -r -- "  *** error: the code can override $vname, the README does not have it"
    fi
  done
  print -r -- "  ${#tunable[@]} plugin variables the code can override: ${(j: :)tunable}"

  t_sep "the defaults live in base.zsh: the README must name the constants, not copy a literal"
  # The gate above only guarantees that the environment variable name appears
  # somewhere in the README. It does not care whether the default the README
  # quotes is the real one -- someone changes _FC_ENVF_WIDTH and the 80 in the
  # README just sits there. So every tunable has to say in the README which
  # constant it lands in.
  local -a dflt
  dflt=(_FC_ENVF_WIDTH _FC_PYPI_INDEX _FC_PYPI_JSON_BASE)
  local dname
  for dname in "${dflt[@]}"; do
    if grep -qF "$dname" "$R"; then
      print -r -- "  OK   $dname is documented"
    else
      print -r -- "  *** error: the code puts the default in $dname, the README does not mention it ***"
    fi
  done

  t_sep "the clone address must point at this repository, not at upstream"
  # It used to be the address of upstream liuyinz, and copying it verbatim
  # clones the wrong repository.
  local remote
  remote=$(cd "$root" && git remote get-url origin 2>/dev/null)
  if [[ -z $remote ]]; then
    print -r -- '  (no origin remote, skipped)'
  else
    remote=${remote%.git}
    remote=${remote#https://}
    remote=${remote#git@}
    remote=${remote/:/\/}
    print -r -- "  origin = ${remote}"
    if grep -qF "https://${remote}" "$R"; then
      print -r -- '  OK   the clone address in the README agrees with origin'
    else
      print -r -- '  *** error: the clone address in the README differs from origin'
      grep -oE 'https://github.com/[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+' "$R" \
        | sort -u | sed 's/^/        in the README: /'
    fi
  fi

  t_sep "jq: the usage the README claims must agree with the code"
  # The facts: brew does not use jq (only a comment mentions it); gem does not
  # use it at all; gh uses gh api --jq (built in, needs no external binary);
  # outdated and manage for npm / pnpm / pip need an external jq, while search
  # does not.
  local eco2 fn2 f2 v2 row
  for eco2 in brew gem; do
    for v2 in ${(s: :)${_FC_REG[$eco2:views]}}; do
      fn2=${_FC_REG[$eco2:$v2]}
      [[ -z $fn2 ]] && continue
      f2=$(grep -l "^${fn2}()" "$root"/collections/*.zsh 2>/dev/null | head -1)
      [[ -z $f2 ]] && continue
      if sed -n "/^${fn2}()/,/^}/p" "$f2" | grep -vE '^\s*#' | grep -qE '\| jq -r'; then
        print -r -- "  *** error: $eco2/$v2 uses an external jq, the README claims $eco2 does not need one"
      fi
    done
    print -r -- "  OK   the data sources of the $eco2 views really do not use an external jq"
  done
  # The other direction: outdated for npm / pnpm / pip really does use jq, so
  # the README must list jq
  for eco2 in npm pnpm pip; do
    fn2=${_FC_REG[$eco2:outdated]}
    f2=$(grep -l "^${fn2}()" "$root"/collections/*.zsh 2>/dev/null | head -1)
    if [[ -z $f2 ]] || ! sed -n "/^${fn2}()/,/^}/p" "$f2" | grep -vE '^\s*#' | grep -qE '\| jq -r'; then
      print -r -- "  *** error: outdated of $eco2 no longer needs jq, yet the README lists it"
      continue
    fi
    # The $eco2f row of the README's dependency table must contain jq.
    # npmf and pnpmf are merged into one row (`| `npmf`, `pnpmf` | ...`), so the
    # start of the line cannot be the only thing matched.
    row=$(grep -F "\`${eco2}f\`" "$R" | grep '^|' | head -1)
    if [[ -n $row ]] && print -r -- "$row" | grep -q 'jq'; then
      print -r -- "  OK   outdated of $eco2 uses jq, and the README lists it"
    else
      print -r -- "  *** error: outdated of $eco2 uses jq, but the README dependency table does not list it"
      print -r -- "        the row that was found: ${row:-(none)}"
    fi
  done

  t_sep "FZF_COLLECTION_OPTS must agree with _FC_OPTS item for item"
  local inreadme inopts
  inreadme=$(sed -n '/^  FZF_COLLECTION_OPTS="/,/"/p' "$R" | grep -oE '^\s+--[a-z-]+' | tr -d ' ' | sort)
  inopts=$(print -l -- ${_FC_OPTS} | grep -oE '^--[a-z-]+' | sort)
  if [[ $inreadme == $inopts ]]; then
    print -r -- '  OK   they agree'
  else
    print -r -- '  *** error: it differs from _FC_OPTS in the code'
    print -r -- "      README:  ${(j: :)inreadme}"
    print -r -- "      _FC_OPTS: ${(j: :)inopts}"
  fi
}

# ---- case isolation ----
#
# Snapshot the plugin globals before each case and restore them afterwards.
# Without this layer, one case clearing _FC_OPTS makes every case after it run
# with empty opts, and the consistency gate in t_case_readme writes "*** error"
# into the baseline -- and the baseline only records text, it cannot tell
# "correct" from "wrong the same way every time".
#
# More reliable than "remember to clean up in the case": what gets left out is
# not one leaked variable but a false failure several screens away. **When adding
# a plugin global, add a line here.**

typeset -ga _T_OPTS _T_ROWS _T_FIELDS _T_STREAM _T_ACTIONS _T_MUTATING
typeset -ga _T_PICKED _T_DONE _T_FAILED
typeset -gi _T_PENDING _T_RC
typeset -g  _T_COLOR _T_SGR_WARNED _T_SGR_PREFIX _T_HEADER
typeset -gA _T_REG

_t_snapshot() {
  _T_OPTS=("${_FC_OPTS[@]}")
  _T_ROWS=("${_FC_ROWS[@]}")
  _T_FIELDS=("${_FC_FIELDS[@]}")
  _T_STREAM=$_FC_STREAM
  # The right-hand side still carries ${arr[@]:-} everywhere: base.zsh now
  # declares these arrays at the top level, but the :- costs nothing, and it
  # makes this function safe even when the plugin's globals do not exist yet
  # (tests/cases.sh can be sourced on its own, without the plugin). With the
  # :- added, a reference expansion contributes zero elements when the array
  # does not exist, which means the same as "an empty array".
  _T_ACTIONS=("${_FC_ACTIONS[@]:-}")
  _T_MUTATING=("${_FC_MUTATING[@]:-}")
  _T_PICKED=("${_FC_PICKED[@]:-}")
  _T_DONE=("${_FC_DONE[@]:-}")
  _T_FAILED=("${_FC_FAILED[@]:-}")
  _T_PENDING=$_FC_PENDING
  _T_RC=$_FC_RC
  _T_COLOR=$_FC_COLOR
  _T_SGR_WARNED=$_FC_SGR_WARNED
  _T_SGR_PREFIX=$_FC_SGR_PREFIX
  _T_HEADER=$_FC_HEADER
  # The whole registry is stored in one go: registering the fixture keys one by
  # one means leaving one key out is one missed leak. The price is copying
  # several hundred keys per case, which is acceptable.
  _T_REG=("${(@kv)_FC_REG}")
}

_t_restore() {
  _FC_OPTS=("${_T_OPTS[@]}")
  _FC_ROWS=("${_T_ROWS[@]}")
  _FC_FIELDS=("${_T_FIELDS[@]}")
  _FC_STREAM=$_T_STREAM
  _FC_ACTIONS=("${_T_ACTIONS[@]}")
  _FC_MUTATING=("${_T_MUTATING[@]}")
  _FC_PICKED=("${_T_PICKED[@]}")
  _FC_DONE=("${_T_DONE[@]}")
  _FC_FAILED=("${_T_FAILED[@]}")
  _FC_PENDING=$_T_PENDING
  _FC_RC=$_T_RC
  _FC_COLOR=$_T_COLOR
  _FC_SGR_WARNED=$_T_SGR_WARNED
  _FC_SGR_PREFIX=$_T_SGR_PREFIX
  _FC_HEADER=$_T_HEADER
  _FC_REG=("${(@kv)_T_REG}")
}

t_run_all() {
  local c
  # The list of cases is data: adding a case adds one line, and there is no need
  # to remember to wrap it in snapshot/restore. This used to be 25 direct calls,
  # and it was easy for whoever added a case to add only the call and not the
  # harness.
  local -a cases
  cases=(
    t_case_rule
    t_case_format
    t_case_read
    t_case_msg
    t_case_split_row
    t_case_loop
    t_case_render
    t_case_drop_rows
    t_case_membership
    t_case_reg_get
    t_case_coexist
    t_case_session_stdin
    t_case_pick_split
    t_case_registry
    t_case_keyshape
    t_case_action_menu
    t_case_failure
    t_case_load_rows
    t_case_stream
    t_case_other_value
    t_case_envf_width
    t_case_uvf_rows
    t_case_palette
    t_case_entry_params
    t_case_requires
    t_case_fzf_opts
    t_case_readme
  )
  for c in "${cases[@]}"; do
    _t_snapshot
    $c
    _t_restore
  done
  printf '\n### END\n'
}
