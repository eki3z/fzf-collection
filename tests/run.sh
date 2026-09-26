#!/usr/bin/env zsh
#
# 行为基线测试驱动
#
# 用法：
#   tests/run.sh              跑测试并与 tests/expected/baseline.txt 比对
#   tests/run.sh --record     用当前行为重新记录基线（仅在行为有意变更时使用）
#   tests/run.sh --syntax     只跑 zsh -n 语法门
#   tests/run.sh --perms      只检查 body 文件在 git 索引中的模式
#
# 为什么基线由 zsh 记录：body 由 plugin.zsh 以 source 加载，解析者是 zsh，
# 当前行为即基线。重构目标是「行为等价」，因此基线必须在改动前录下。

set -u

here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
baseline="$here/expected/baseline.txt"
outdir=$(mktemp -d)
trap 'rm -rf "$outdir"' EXIT

syntax_gate() {
  local f rc=0
  print -r -- "--- zsh -n 语法门 ---"
  for f in "$root"/base.sh "$root"/collections/*.sh "$root"/tests/cases.sh; do
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
  print -r -- "--- git 索引中的文件模式（应全部 100644）---"
  local line rc=0 fmode fpath_
  # 注意：不要用 path / fpath / cdpath / manpath 作变量名 —— 它们是 zsh 的特殊变量
  for line in ${(f)"$(git -C "$root" ls-files -s base.sh collections/ fzf-collection.plugin.zsh)"}; do
    fmode=${line%% *}
    fpath_=${line#*$'\t'}
    if [[ $fmode == 100644 ]]; then
      print -r -- "  OK   $fmode  $fpath_"
    else
      print -r -- "  FAIL $fmode  $fpath_  ← body 是库文件，不应有执行位"
      rc=1
    fi
  done
  return $rc
}

# 与 plugin.zsh 相同的加载方式：source base.sh，再 source 用例
run_cases() {
  ( cd "$root" && zsh -c '
      source ./base.sh || exit 1
      source ./tests/cases.sh || exit 1
      t_run_all
    ' 2>&1 )
}

mode=compare
case ${1:-} in
  --record)  mode=record ;;
  --syntax)  mode=syntax ;;
  --perms)   mode=perms ;;
  '')        mode=compare ;;
  -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *)         print -ru2 "未知参数: $1"; exit 2 ;;
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
  record)
    print -r -- "用 zsh 记录基线 -> $baseline"
    run_cases > "$baseline" || { print -ru2 "记录失败"; exit 1; }
    print -r -- "已记录 $(wc -l < "$baseline" | tr -d ' ') 行"
    exit 0
    ;;
esac

# compare
fail=0

syntax_gate || fail=1
print
perms_gate || fail=1
print

if [[ ! -f $baseline ]]; then
  print -ru2 "缺少基线，请先运行: tests/run.sh --record"
  exit 2
fi

out="$outdir/actual.txt"
run_cases > "$out"

print -r -- "--- 行为比对（$(zsh --version)）---"
if diff -u "$baseline" "$out" > "$outdir/d.txt" 2>&1; then
  print -r -- "  PASS  与基线一致（$(wc -l < "$baseline" | tr -d ' ') 行）"
else
  fail=1
  print -r -- "  FAIL  以下行与基线不同："
  grep '^[-+][^-+]' "$outdir/d.txt" 2>/dev/null | head -30 | sed 's/^/      /'
  print -r -- "      完整差异: $outdir/d.txt"
fi

print
if (( fail == 0 )); then
  print -r -- "全部通过"
else
  print -r -- "存在失败项"
fi
exit $fail
