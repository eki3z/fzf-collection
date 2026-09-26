#!/usr/bin/env zsh
#
# 行为基线测试驱动
#
# 用法：
#   tests/run.sh              跑测试并与 tests/expected/baseline.txt 比对
#   tests/run.sh --record     用当前行为重新记录基线（仅在行为有意变更时使用）
#   tests/run.sh --syntax     只跑 zsh -n 语法门
#   tests/run.sh --hygiene    只跑变量卫生 lint（见下）
#   tests/run.sh --perms      只检查 body 文件在 git 索引中的模式
#
# 已知：zsh -n 只查语法，查不出下面两类静默错误，--hygiene 那道门就是为它们准备的：
#   - 循环体内的标量 local 会往 stdout 打一行 NAME=值
#   - local x=$(cmd) 会让命令替换的退出码被吞掉
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
  for f in "$root"/base.zsh "$root"/collections/*.zsh "$root"/tests/cases.sh; do
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
  for line in ${(f)"$(git -C "$root" ls-files -s base.zsh collections/ fzf-collection.plugin.zsh)"}; do
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

# 静态 lint：变量卫生。两条都在 zsh 里静默出错，zsh -n 都查不出。
#
# 1) 禁止把标量 local 写在循环体内。
#    zsh 5.9 在循环体内执行标量 local 时，会往 stdout 打一行
#    `NAME=<上一轮的值>`（含 ESC 的值显示成 $'\C-...'）。body 里几乎所有
#    函数的 stdout 都会被 $(...) 或管道捕获，那一行就会变成一条假数据 ——
#    曾经表现为 pnpmf 的候选列表里混入 k=6 / k=''。
#    为什么不可省：在循环里写 local 是很自然、很常见的写法，
#    而症状要等用户在 fzf 列表里看到多出一行才暴露。
#
# 2) 禁止在 local / typeset 的声明里带命令替换。
#    `local x=$(cmd)` 返回的是 local 内建自己的状态，命令替换的退出码被吞掉：
#      local x=$(false)  -> 之后 $? 是 0
#      local x; x=$(false) -> 之后 $? 是 1
#    于是 `local v=$(pkg_install "$1") || return 1` 这种写法里的 || 永远不触发。
hygiene_gate() {
  print -r -- "--- lint: 变量卫生 ---"
  local f rc=0 n
  for f in "$root"/base.zsh "$root"/collections/*.zsh; do
    n=$(awk '
      function report(msg) { printf("  FAIL %s:%d  %s\n", FILENAME, FNR, msg) }
      { line = $0; sub(/\r$/, "", line)
        if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/) next
        work = line; gsub(/\t/, "        ", work)
        ind = match(work, /[^ ]/) - 1
        s = line; sub(/^[ \t]+/, "", s)

        # ---- 2) 声明里带命令替换 ----
        if (s ~ /^(local|typeset|declare)([ \t]|$)/ &&
            s ~ /=[ \t]*["\x27]?\$\(/ && s !~ /^[ \t]*#/) {
          report("声明里带命令替换，退出码会被 local 吞掉 -> " s)
        }

        # ---- 1) 循环体内的标量 local ----
        if (s ~ /^(local|typeset)[ \t]+/) {
          rest = s; sub(/^(local|typeset)[ \t]+/, "", rest)
          isarr = (rest ~ /(^|[ \t])-[aA]([ \t]|$)/)
          hasname = 0
          nt = split(rest, tok, /[ \t]+/)
          for (i = 1; i <= nt; i++) if (tok[i] != "" && tok[i] !~ /^-/) hasname = 1
          inloop = 0
          for (i = top; i >= 1; i--)
            if (kind[i] == "loop" && lind[i] < ind) { inloop = 1; break }
          if (inloop && !isarr && hasname)
            printf("  FAIL %s:%d  %s\n", FILENAME, FNR, s)
        }

        if (s ~ /^done([ \t]*;)?$/) { if (top >= 1 && kind[top] == "loop") top--; next }
        if (s ~ /^\}([ \t]*;)?$/)  { if (top >= 1 && kind[top] == "func") top--; next }
        if (s ~ /^(for|while|until|select|repeat)([ \t]|$)/ || s ~ /^do$/) {
          top++; kind[top] = "loop"; lind[top] = ind; next
        }
        if (s ~ /^[A-Za-z_][A-Za-z0-9_.:-]*[ \t]*\([ \t]*\)[ \t]*\{?$/) {
          top++; kind[top] = "func"; lind[top] = ind; next
        }
      }
    ' "$f")
    if [[ -n $n ]]; then
      print -r -- "$n"
      print -r -- "       ^ 循环体内的 local 会把 NAME=值 打进 stdout；"
      print -r -- "         声明里的 \$(cmd) 会让 || 永远不触发"
      rc=1
    else
      print -r -- "  OK   ${f:t}"
    fi
  done
  return $rc
}

# 与真实加载路径一致：source plugin.zsh（它会加载 base.sh 与各 collection），
# 这样用例能看到完整的注册表。
run_cases() {
  ( cd "$root" && zsh -c '
      source ./fzf-collection.plugin.zsh || exit 1
      source ./tests/cases.sh || exit 1
      t_run_all
    ' 2>&1 )
}

mode=compare
case ${1:-} in
  --record)  mode=record ;;
  --syntax)  mode=syntax ;;
  --perms)   mode=perms ;;
  --hygiene) mode=hygiene ;;
  '')        mode=compare ;;
  -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
  hygiene)
    hygiene_gate
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
hygiene_gate || fail=1
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
