#!/usr/bin/env zsh
#
# Behaviour baseline test driver
# Usage:
#   tests/run.sh              run every gate and compare with the baseline
#                             (tests/expected/baseline.txt)
#   tests/run.sh --record     re-record the baseline from current behaviour
#                             (only on an intentional behaviour change)
#   tests/run.sh --syntax     only run the zsh -n syntax gate
#   tests/run.sh --hygiene    only run the variable hygiene lint (see below)
#   tests/run.sh --nounset    only run the setopt nounset gate (see below)
#   tests/run.sh --perms      only check body file modes in the git index
#
# This file only runs under zsh, and so does the body (README: Requirements).
#
# zsh -n only checks syntax; it cannot see the silent errors that write to
# stdout, which is what the --hygiene gate is there for. The --nounset gate is
# for "referencing an unset parameter" -- the one class of error in zsh that is
# syntactically correct, hygiene-clean, and still fails silently at run time.
#
# The baseline is recorded by zsh: the body is loaded by plugin.zsh with
# source, the parser is zsh, so the current behaviour IS the baseline. The
# goal of the refactor is behavioural equivalence, so the baseline has to be
# recorded before the change.

set -u

here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
baseline="$here/expected/baseline.txt"
outdir=$(mktemp -d)
trap 'rm -rf "$outdir"' EXIT

syntax_gate() {
  local f rc=0
  print -r -- "--- zsh -n syntax gate ---"
  # run.sh itself has to pass too. This list used to leave it out, so a syntax
  # error in run.sh only surfaced when that line was really executed -- and the
  # gate is the first thing that gets executed.
  # fzf-collection.plugin.zsh has to pass for the same reason: it is the only
  # entry point, a syntax error there makes the whole plugin fail to load, and
  # it was not in the list either -- the only zsh file in the entry layer went
  # unchecked.
  for f in "$root"/base.zsh "$root"/collections/*.zsh \
           "$root"/fzf-collection.plugin.zsh \
           "$root"/tests/cases.sh "$root"/tests/run.sh; do
    if zsh -n "$f" 2>&1; then
      print -r -- "  OK   ${f:t}"
    else
      print -r -- "  FAIL ${f:t}"
      rc=1
    fi
  done
  return $rc
}

perms_gate() {
  print -r -- "--- file modes in the git index (all should be 100644) ---"
  local line rc=0 fmode fpath_
  # Note: do not use path / fpath / cdpath / manpath as variable names -- they
  # are zsh special variables.
  # Only the body files are checked, not tests/run.sh -- the latter is
  # executable (CI runs ./tests/run.sh directly).
  for line in ${(f)"$(git -C "$root" ls-files -s base.zsh collections/ fzf-collection.plugin.zsh)"}; do
    fmode=${line%% *}
    fpath_=${line#*$'\t'}
    if [[ $fmode == 100644 ]]; then
      print -r -- "  OK   $fmode  $fpath_"
    else
      print -r -- "  FAIL $fmode  $fpath_  <- body is a library file, it must not be executable"
      rc=1
    fi
  done
  return $rc
}

# A static lint: variable hygiene. All three fail silently in zsh, zsh -n cannot
# see them, and all three print into stdout -- almost every function in the
# body has its stdout captured by $(...) or by a pipe.
#
# 1) A scalar local inside a loop body. zsh 5.9 prints a `NAME=<value>` line to
#    stdout (a value containing ESC shows up as $'\C-...'). Writing a local
#    inside a loop is perfectly natural, and the symptom only shows up once the
#    user sees an extra line in the fzf list, so it has to be caught at write
#    time.
# 2) A command substitution in a local / typeset declaration. `local x=$(cmd)`
#    returns the local builtin's own status and swallows the command
#    substitution's exit code: after `local x=$(false)` $? is 0, and only
#    `local x; x=$(false)` gives 1. So the || in `local v=$(f) || return 1` can
#    never fire.
# 3) Declaring the same scalar local twice (without an assignment), which also
#    prints a `NAME=<value>` line to stdout. With an assignment (local x=v), an
#    array (local -a x) or an integer (local -i x) it does not fire.
hygiene_gate() {
  print -r -- "--- lint: variable hygiene ---"
  local f rc=0 n
  # cases.sh has to be scanned too: its stdout is the content compared verbatim
  # against the baseline, and one stray `line='...'` becomes part of the
  # baseline and can never be found again.
  # The same list as syntax_gate, including run.sh and plugin.zsh themselves:
  # they are zsh code that writes to stdout as well (hygiene_gate lives in
  # run.sh, plugin.zsh is the entry point).
  for f in "$root"/base.zsh "$root"/collections/*.zsh \
           "$root"/fzf-collection.plugin.zsh \
           "$root"/tests/cases.sh "$root"/tests/run.sh; do
    n=$(awk '
      function report(msg) { printf("  FAIL %s:%d  %s\n", FILENAME, FNR, msg) }
      # One list of local names per function, cleared at the opening brace --
      # not at the closing one, or common names like line / f / n would report
      # each other across functions.
      function forget() { delete seen }
      { line = $0; sub(/\r$/, "", line)
        if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/) next
        work = line; gsub(/\t/, "        ", work)
        ind = match(work, /[^ ]/) - 1
        s = line; sub(/^[ \t]+/, "", s)

        # ---- 2) command substitution in a declaration ----
        if (s ~ /^(local|typeset|declare)([ \t]|$)/ &&
            s ~ /=[ \t]*["\x27]?\$\(/) {
          report("a command substitution in a declaration, the exit code is swallowed by local -> " s)
        }

        # ---- 1) scalar local in a loop body / 3) repeated scalar local ----
        if (s ~ /^(local|typeset)[ \t]+/) {
          rest = s; sub(/^(local|typeset)[ \t]+/, "", rest)
          # Cut the trailing comment off before tokenising. English words in a
          # comment get taken for variable names: once the comments are in
          # English, the the / current / by in
          # `typeset -gi _FC_STREAM # 1 = the current view...` all collide with
          # local names in other functions and the comment itself makes the
          # file FAIL. The criterion is "whitespace in front", so the quoted #
          # in local x='#foo' is not cut; a declaration cannot contain
          # "whitespace + #", so the cut is safe.
          sub(/[ \t]+#.*$/, "", rest)
          isarr = (rest ~ /(^|[ \t])-[aA]([ \t]|$)/)
          isint = (rest ~ /(^|[ \t])-[iI]([ \t]|$)/)
          inloop = 0
          for (i = top; i >= 1; i--)
            if (kind[i] == "loop" && lind[i] < ind) { inloop = 1; break }
          nt = split(rest, tok, /[ \t]+/)
          for (i = 1; i <= nt; i++) {
            if (tok[i] == "" || tok[i] ~ /^-/) continue
            nm = tok[i]
            hasval = (nm ~ /=/)
            sub(/=.*/, "", nm)
            if (nm !~ /^[A-Za-z_][A-Za-z0-9_]*$/) continue
            if (inloop && !isarr && !isint)
              report("a scalar local inside a loop body prints NAME=value to stdout -> " s)
            if (!isarr && !isint && !hasval && (nm in seen))
              report("redeclaring an already-local scalar (no value) prints NAME=value to stdout -> " s)
            if (!(nm in seen)) seen[nm] = 1
          }
        }

        # An unmatched done / } has to be passed through as it is, without a
        # convenient top--: once the stack is misaligned, every more deeply
        # indented local afterwards is falsely reported as a scalar local in a
        # loop body. The real source of the misalignment is the
        # `| while IFS= read -r x; do` on a continuation line -- with the
        # leading whitespace stripped s starts with `|`, so it is not read as a
        # loop head and its done finds no matching loop. All that is guaranteed
        # here is that it does not get worse; the stack is fully reset by the
        # top=0 at a function start.
        if (s ~ /^done([ \t]*;)?$/) { if (top >= 1 && kind[top] == "loop") top--; next }
        if (s ~ /^\}([ \t]*;)?$/)  { if (top >= 1 && kind[top] == "func") top--; next }
        if (s ~ /^(for|while|until|select|repeat)([ \t]|$)/ || s ~ /^do$/) {
          # A one-line loop (`for k in a b; do unset ...; done`) closes within
          # the same line. This used to push the stack just by looking at the
          # head, so such a for left behind a loop frame that could never be
          # popped: every local indented more deeply than it was afterwards was
          # falsely reported as a scalar local in a loop body. The symptom is
          # that writing a local in a nested stub function FAILs, which has
          # nothing to do with the real intent of that rule.
          rest = s
          sub(/^(for|while|until|select|repeat)[ \t]+/, "", rest)
          if (rest ~ /;[ \t]*done([ \t;]|$)/) next
          top++; kind[top] = "loop"; lind[top] = ind; next
        }
        # A function start. A { followed by a trailing comment has to be
        # allowed -- nearly every function in this repo is written that way
        # (`_fc_rollback() {        # $1=eco $2=pkg`). Not recognising it lets
        # the local list accumulate across functions, so common names like
        # line / f / n report each other.
        if (s ~ /^[A-Za-z_][A-Za-z0-9_.:-]*[ \t]*\([ \t]*\)[ \t]*\{([ \t]*#.*)?$/) {
          # top=0 is necessary: the done and } above that cannot be recognised,
          # or cannot be matched, make the stack misalign, and forget() only
          # clears the local list, it does not touch the stack. A loop frame
          # left over by the misalignment has a very small lind, so every local
          # in this function is misjudged as being inside a loop. A function
          # start is the only reliable boundary -- what the previous function
          # left behind is of no concern to this one.
          top = 0
          top++; kind[top] = "func"; lind[top] = ind; forget(); next
        }
      }
    ' "$f")
    if [[ -n $n ]]; then
      print -r -- "$n"
      print -r -- "       ^ all three of these silently print a NAME=value line to stdout:"
      print -r -- "         a scalar local in a loop body / a repeated value-less scalar local / a \$(cmd) in a declaration"
      rc=1
    else
      print -r -- "  OK   ${f:t}"
    fi
  done
  return $rc
}

# The nounset gate: the same set of cases run again under setopt nounset.
#
# What this gate catches is "referencing an unset parameter". Its symptoms under
# nounset have two properties, and they decide how the criterion has to be
# written:
#
#   1. The exit code is 0. zsh complaining about an unset parameter does not
#      fail the script, and a function like _fc_session still returns 0. So the
#      criterion cannot be the exit code; it has to be text on stderr.
#   2. When the report happens deep inside a pipe or a $(...), the location
#      information is only `function: line: parameter not set`, and stderr is
#      mixed into stdout by 2>&1, together with the baseline.
#
# So it is done in two steps: first look for those three texts on stderr (that
# is this gate's criterion), then check that the normal output is byte-for-byte
# identical to the baseline (nounset does not change the normal path, so both
# runs must produce the same output -- this also catches "the behaviour was
# changed to make nounset pass").
#
# The real war story: _fc_session once passed a never-declared $opt to _fc_feed,
# so a user who had nounset set returned on the first round of any *-f command
# and every interactive feature was effectively gone. The syntax gate, the
# hygiene gate and the baseline comparison were all green -- none of them
# covered this.
nounset_gate() {
  print -r -- "--- lint: referencing unset parameters under setopt nounset ---"
  local rc=0
  # What is passed is the full 'setopt nounset', not 'nounset': run_cases
  # interpolates $1 verbatim as the body of the script, so passing the bare
  # word makes zsh go looking for a command called nounset and the criterion
  # silently stops working.
  #
  # The output goes to a file rather than into $(...): a command substitution
  # eats the trailing newline, and comparing against the baseline then shows a
  # whole block of deletion lines out of thin air, which looks like the
  # behaviour changed when really only a few blank lines are gone.
  local out="$outdir/nounset.txt"
  run_cases 'setopt nounset' >"$out"

  # stderr has already been mixed into stdout by the 2>&1 in run_cases, so look
  # in that same output.
  if grep -qE 'parameter not set|bad substitution|unbound variable|not a valid identifier' "$out"; then
    print -r -- "  FAIL  references to unset parameters under nounset:"
    grep -nE 'parameter not set|bad substitution|unbound variable|not a valid identifier' "$out" \
      | head -10 | sed 's/^/        /'
    rc=1
  else
    print -r -- '  OK   no references to unset parameters'
  fi
  if [[ -f $baseline ]] && ! diff -u "$baseline" "$out" >"$outdir/nounset-diff.txt" 2>&1; then
    print -r -- '  FAIL  output under nounset differs from the baseline -- behaviour changed to get past nounset:'
    grep '^[-+][^-+]' "$outdir/nounset-diff.txt" 2>/dev/null | head -10 | sed 's/^/        /'
    print -r -- "        full diff: $outdir/nounset-diff.txt"
    rc=1
  else
    print -r -- '  OK   output under nounset matches the baseline'
  fi
  return $rc
}

# Same as the real load path: source plugin.zsh (which loads base.zsh and every
# collection), so the cases see the complete registry.
# $1 is optional: with 'nounset', setopt nounset is turned on in the subshell.
run_cases() {
  # opts is a line of shell to be **executed** ('setopt nounset'), interpolated
  # in double quotes into the body of the zsh -c script. This used to miss the
  # braces ($opts rather than ${opts}), so the \n right after it was swallowed
  # and `setopt` became a command name -- the gate then printed "OK" while
  # nounset was never actually turned on, and the criterion was inert. Anywhere
  # a switch is written as a variable and interpolated, confirm that it ran.
  local opts=${1:-}
  ( cd "$root" && zsh -c "
      ${opts}
      # \$root has to be re-exported here: the cases use \"\$root\"/base.zsh in
      # several places, as well as local R=\$root/README.md, and the \$root in
      # run.sh does not follow into this subshell. Without this line those
      # checks quietly do nothing: the README consistency gate and the
      # fzf --ansi gate both ran empty because of it, and the baseline was
      # left with a single \"OK\".
      root=\$PWD
      export root
      # The colour has to be pinned on explicitly. The plugin tests [[ -t 1 ]]
      # when it loads, and this is a non-interactive zsh inside a subshell, so
      # that is always false -- without pinning, colour is entirely off and the
      # lines carrying ESC in the baseline (the output of _other_format and
      # _fc_msg) lose their escapes wholesale. The colour-off path is tested on
      # its own by t_case_palette.
      FZF_COLLECTION_COLOR=1
      export FZF_COLLECTION_COLOR
      source ./fzf-collection.plugin.zsh || exit 1
      source ./tests/cases.sh || exit 1
      t_run_all
    " 2>&1 )
}

mode=compare
case ${1:-} in
  --record)  mode=record ;;
  --syntax)  mode=syntax ;;
  --perms)   mode=perms ;;
  --hygiene) mode=hygiene ;;
  --nounset) mode=nounset ;;
  '')        mode=compare ;;
  -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *)         print -ru2 "unknown argument: $1"; exit 2 ;;
esac

case $mode in
  syntax)
    syntax_gate
    exit $?
    ;;
  perms)
    perms_gate
    exit $?
    ;;
  hygiene)
    hygiene_gate
    exit $?
    ;;
  nounset)
    nounset_gate
    exit $?
    ;;
  record)
    print -r -- "recording the baseline with zsh -> $baseline"
    run_cases > "$baseline" || { print -ru2 "recording failed"; exit 1; }
    print -r -- "recorded $(wc -l < "$baseline" | tr -d ' ') lines"
    exit 0
    ;;
esac

# compare
fail=0

syntax_gate || fail=1
print
hygiene_gate || fail=1
print
nounset_gate || fail=1
print
perms_gate || fail=1
print

if [[ ! -f $baseline ]]; then
  print -ru2 "baseline missing, run this first: tests/run.sh --record"
  exit 2
fi

out="$outdir/actual.txt"
run_cases > "$out"

print -r -- "--- behaviour comparison ($(zsh --version)) ---"
if diff -u "$baseline" "$out" > "$outdir/d.txt" 2>&1; then
  print -r -- "  PASS  matches the baseline ($(wc -l < "$baseline" | tr -d ' ') lines)"
else
  fail=1
  print -r -- "  FAIL  these lines differ from the baseline:"
  grep '^[-+][^-+]' "$outdir/d.txt" 2>/dev/null | head -30 | sed 's/^/      /'
  print -r -- "      full diff: $outdir/d.txt"
fi

print
if (( fail == 0 )); then
  print -r -- "all passed"
else
  print -r -- "there are failures"
fi
exit $fail
