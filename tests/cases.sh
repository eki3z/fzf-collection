# 行为基线测试用例
#
# 本文件会被三个 shell 分别 source：bash 3.2 / bash 5.3 / zsh 5.9
# 因此这里的每一行语法都必须同时在三者下成立 —— 任何分歧都说明
# body 尚未满足「纯 bash 语法、实际由 zsh 解析」这个约束。
#
# 用例只覆盖确定性、无副作用的纯函数。
# 不覆盖：_fzf_pager(起 less)、_fzf_homepage(开浏览器)、
#        _fzf_version_check(有 sleep)、_fzf_tmp_*(P2 将删除)

# 用例之间的分隔标记，便于 diff 定位
t_sep() {
  printf '\n===== %s =====\n' "$1"
}

# 1. _fzf_underline：header 下划线，长度应等于字符串长度
#    已知问题：base.sh:43 的 {1..$#1} 在 bash 下只输出 1 个字符
#    （bash 的 brace expansion 先于参数展开，{1..$#1} 被当作字面量）
t_case_underline() {
  local s
  for s in "Header Text" "abc" "Find Path" "Env" "Npm Outdated"; do
    printf -- '--- [%s] (len=%s) ---\n' "$s" "${#s}"
    _fzf_underline "$s"
    printf '\n'
  done
}

# 2. _fzf_format：五种取值下的输出
#    已知：manage 与 pinned 共用同一分支，输出完全相同
#    已知：bogus 走 *) 分支，打印错误后 return 0
t_case_format() {
  local fmt
  local format
  for fmt in manage pinned outdated general bogus; do
    t_sep "format=$fmt"
    format=$fmt
    printf 'lodash\t4.17.21\tsome description here\nreact\t18.2.0\tdesc\n' \
      | _fzf_format
  done
}

# 3. _fzf_read：fzf 非交互模式（--filter）
#    已知缺陷 B1：base.sh:48 的 perl -lane 'print $F[0]' 按空白切分，
#    多词条目只剩第一个词。此处固化该行为，重构后应变为返回完整行。
#    已知缺陷 B11：_fzf_read 结尾是 `fzf | perl`，perl 恒返回 0，
#    因此 _fzf_read 永远返回 0，调用方无法据此检测「用户取消」。
t_case_read() {
  local input
  _fzf_opts=()
  header="Test"

  t_sep "单条"
  input="alpha one
beta two
gamma three"
  printf '%s\n' "$input" | _fzf_read --filter=bet

  t_sep "多词条目被截断（缺陷 B1 的证据）"
  input="my package 1.0.0
other-pkg 2.0.0"
  printf '%s\n' "$input" | _fzf_read --filter=my

  t_sep "退出码：匹配时"
  printf 'alpha\nbeta\n' | _fzf_read --filter=alp >/dev/null
  printf '  退出码=%s\n' "$?"

  t_sep "退出码：无匹配（缺陷 B11 —— fzf 的 1 被 perl 吞掉）"
  printf 'alpha\nbeta\n' | _fzf_read --filter=zzzz >/dev/null
  printf '  _fzf_read 退出码=%s   ← 恒为 0，调用方无法检测取消\n' "$?"
  printf 'alpha\nbeta\n' | fzf --filter=zzzz >/dev/null
  printf '  对照 fzf 裸调用退出码=%s\n' "$?"
}

# 4. _fzf_msg：消息输出格式
t_case_msg() {
  t_sep "有 pkg"
  _fzf_msg "some message" "mypkg"
  t_sep "无 pkg（回退到 caller）"
  caller="MYFUNC"
  _fzf_msg "another message"
}

# 5. _fzf_header：依赖 funcstack（base.sh:32），bash 下为空数组
#    这是「约束 3 未达成」的直接证据，P1 将删除该机制
t_case_header() {
  t_sep "在 zpf_manage 上下文中"
  zpf_manage() {
    printf '  [%s]\n' "$(_fzf_header)"
  }
  zpf_manage
  t_sep "在 zpf_outdated 上下文中"
  zpf_outdated() {
    printf '  [%s]\n' "$(_fzf_header)"
  }
  zpf_outdated
}

# 6. 字段拆分：body 需要把「name<TAB>version...」拆开
#    注意：IFS=$'\t' read -r -a arr 是 bash-only（zsh: bad option: -a），
#    不可用于 body。下面两种形式在 bash 3.2 / bash 5 / zsh 下均可用。
t_case_split() {
  local row x y z
  row="lodash	4.17.21	1.2M"
  t_sep "取首字段（参数展开，可移植）"
  printf '  first=[%s]\n' "${row%%	*}"
  t_sep "定长变量切分（可移植，字段数固定时用）"
  IFS=$'\t' read -r x y z <<< "$row"
  printf '  x=[%s] y=[%s] z=[%s]\n' "$x" "$y" "$z"
  t_sep "while + 参数展开切分（可移植，字段数不定时用）"
  local rest="$row" field
  while [ -n "$rest" ]; do
    case $rest in
      *'	'*) field=${rest%%	*}; rest=${rest#*	} ;;
      *)      field=$rest; rest="" ;;
    esac
    printf '  field=[%s]\n' "$field"
  done
}

# 7. 多行结果循环：body 中 7 处 `for f in $(echo "$inst")` 的行为
#    （zsh 会对命令替换结果分词，此处确认与 bash 一致）
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

t_run_all() {
  t_case_underline
  t_case_format
  t_case_read
  t_case_msg
  t_case_header
  t_case_split
  t_case_loop
  printf '\n### END\n'
}
