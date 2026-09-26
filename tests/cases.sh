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
# 2. _fzf_format：只剩 general
#    原来有 manage / pinned / outdated / general 四个分支，每个一条 perl printf
#    规则（$rule 里用 perl 的 @F 与 %.15s）。迁移后包管理器全部走 _pkg_display，
#    format 只有 general 还被 fp / envf 使用，另外三个分支无法到达，已删除，
#    所以这里改为断言「不支持的 format 报错」而不是那三种渲染结果。
t_case_format() {
  local fmt
  local format
  for fmt in manage pinned outdated; do
    t_sep "format=$fmt（已删除的分支，应报错）"
    format=$fmt
    printf 'lodash\t4.17.21\tsome description here\nreact\t18.2.0\tdesc\n' \
      | _fzf_format
  done
  t_sep "format=general"
  format=general
  printf 'lodash\t4.17.21\tsome description here\nreact\t18.2.0\tdesc\n' \
    | _fzf_format
  t_sep "format=bogus"
  format=bogus
  printf 'lodash\t4.17.21\tsome description here\n' | _fzf_format
  t_sep "general：制表符与连续空格都要压成单空格（对齐 perl join 的行为）"
  format=general
  printf 'a\tb  c\ndd\tee\tff\n' | _fzf_format
  t_sep "general：空输入无输出"
  format=general
  printf '' | _fzf_format
  print -r -- "  (以上应为空)"
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
#    标签必须显式传。原来回退到 $caller —— 那是旧驱动的自由变量，
#    旧驱动删掉后无人赋值，单参调用会打出一个空标签。
t_case_msg() {
  t_sep "有 pkg"
  _fzf_msg "some message" "mypkg"
  t_sep "无 pkg：回退到固定标签，不再依赖 \$caller"
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

# 8. _pkg_display：结构化行 -> 对齐且上色的 fzf 显示行
#    行结构：name<TAB><补齐><TAB>rest。补齐在第一个 tab 之后，
#    所以取 name 无需剥空格。对齐只发生在这一层，_PKG_ROWS 里是干净数据。
t_case_pkg_display() {
  local line out row segs2 c i
  local -a start ref
  # start/segs2 也用于下面的对齐断言
  t_sep "有 display：每列各自对齐，列间是真 tab"
  _PKG_ROWS=("lodash	4.17.21" "my package	1.0.0 some desc")
  _pkg_display | cat -v
  t_sep "无 display（search view）：原样输出，不补齐"
  _PKG_ROWS=("all-the-package-names" "left-pad")
  _pkg_display | cat -v
  t_sep "回读 name：多词包名完整，且天然没有尾随空格"
  _PKG_ROWS=("my package	1.0.0")
  line=$(_pkg_display)
  printf '  显示行=[%s]\n' "$line"
  printf '  name=[%s]\n' "${line%%	*}"
  t_sep "_PKG_ROWS 保持干净（未被显示层污染）"
  _PKG_ROWS=("alpha	1" "beta	2" "a-very-long-name	3")
  _pkg_display >/dev/null
  printf '  [%s]\n' "${(j:,:)${_PKG_ROWS}}"

  # 字符级断言：显示行里绝不能出现字面的反斜杠。
  # 回归点：曾用 ${(j:\t:)segs} 拼行，而 flag 参数是字面量、不解释转义，
  # 于是输出全是字面 \t。基线只「记录现状」，抓不到这类 bug，必须显式断言。
  t_sep "字符级断言：不得出现字面反斜杠"
  _PKG_ROWS=("a	1" "bb	2")
  out=$(_pkg_display)
  if [[ $out == *'\'* ]]; then
    print -r -- '  *** 错误：显示行里出现字面反斜杠，tab 拼接写错了 ***'
  else
    print -r -- '  OK 无字面反斜杠'
  fi
  [[ $out == *$'\t'* ]] && print -r -- '  含真 tab: yes' || print -r -- '  含真 tab: no'

  # 对齐断言：所有行的每一个数据列都必须起始于同一列。
  # 回归点：曾写成 for seg in $segs（未加引号），zsh 会丢弃空元素，
  # 而补齐段在最长的那行恰好为空 —— 那一行就少一个 tab、整行左移。
  # 列间的 tab 数（_PKG_COLSEP，默认 5）不固定，所以只比较数据列本身。
  t_sep "对齐断言：各数据列起始位置必须一致"
  PKG+=('al:manage:cols' '0,34,0,33')
  _PKG_ROWS=("a	1	=>	1"
             "much-longer-name	22	=>	22"
             "mid	333	=>	333")
  for row in "${(@f)$(_pkg_display al manage)}"; do
    row=${row//$'\e['\[[0-9]m/}
    _pkg_split_tabs "$row"
    segs2=("${_PKG_FIELDS[@]}")
    c=0; start=()
    for (( i = 2; i <= ${#segs2}; i++ )); do
      c=$(( c + 1 + ${#segs2[i-1]} ))
      [[ -n ${segs2[i]} ]] && start+=($c)      # 跳过空的补齐段
    done
    # 最后 3 个非空段就是 f2 / => / f4，补齐段在它们之前，不影响
    start=("${(@)start[-3,-1]}")
    print -r -- "  [${segs2[1]}] f2/=>/f4 起始列: ${(j:,:)start}"
    if (( ${#ref} == 0 )); then
      ref=("${start[@]}")
    elif [[ ${(j:,:)start} != "${(j:,:)ref}" ]]; then
      print -r -- "  *** 错位：应为 ${(j:,:)ref} ***"
    fi
  done
  (( ${#ref} == 3 )) && print -r -- '  OK 各行数据列起始一致'
  unset 'PKG[al:manage:cols]'

  # 纯度断言：显示层每行必须以包名开头。
  # 回归点：zsh 5.9 在循环体内执行标量 local 时，会往 stdout 打一行
  # `NAME=<上一轮的值>`。本函数的 stdout 直接喂给 fzf，那一行会变成一条
  # 假候选（曾经表现为 pnpmf 列表里混进 k=6 / k=''）。zsh -n 查不出，
  # tests/run.sh --local 那道静态门负责在写入时拦住，这里负责兜住症状。
  t_sep "纯度断言：每行必须以包名开头（无 NAME= 污染、无前导 tab）"
  _PKG_ROWS=("a	1	=>	1"
             "much-longer-name	22	=>	22"
             "mid	333	=>	333")
  PKG+=('al:manage:cols' '0,34,0,33')
  local -a names
  names=()
  for row in "${(@f)$(_pkg_display al manage)}"; do
    names+=("${row%%	*}")
  done
  print -r -- "  各行首段: ${(j: | :)names}"
  local expect=('a' 'much-longer-name' 'mid')
  if [[ ${(j:|:)names} == "${(j:|:)expect}" ]]; then
    print -r -- '  OK 首段与包名一一对应'
  else
    print -r -- "  *** 错误：首段与包名不符 —— 有非数据行混进了输出 ***"
  fi
  unset 'PKG[al:manage:cols]'
}

# 9. _pkg_drop：从 _PKG_ROWS 精确删除匹配的行
#    对照 ${(@)rows:#pat} 的 glob 误伤 —— 这是必须用 while + [[ == ]] 的原因
t_case_pkg_drop() {
  t_sep "删除存在的行"
  _PKG_ROWS=("alpha	1" "beta	2" "gamma	3")
  _pkg_drop "beta"
  printf '  n=%d  [%s]\n' ${#_PKG_ROWS} "${(j:,:)${_PKG_ROWS}}"
  t_sep "删除多词包名（精确匹配，不能误伤其它行）"
  _PKG_ROWS=("my package	1" "other-pkg	2" "my package extra	3")
  _pkg_drop "my package"
  printf '  n=%d  [%s]\n' ${#_PKG_ROWS} "${(j:,:)${_PKG_ROWS}}"
  t_sep "删除不存在的行（不应误删）"
  _PKG_ROWS=("a*x	1" "ab	2" "axb	3")
  _pkg_drop "a*x"
  printf '  n=%d  [%s]\n' ${#_PKG_ROWS} "${(j:,:)${_PKG_ROWS}}"
  t_sep "对照：glob 写法会误伤（这就是不用它的原因）"
  _PKG_ROWS=("a*x	1" "ab	2" "axb	3")
  printf '  ${(@)_PKG_ROWS:#*x*} -> n=%d （3 行被全删）\n' ${#${(@)_PKG_ROWS:#*x*}}
}

# 10. 动作成员判定：${arr[(Ie)act]} 是驱动判断「删行回列表」还是
#     「留在动作菜单」的唯一依据
t_case_pkg_membership() {
  local -a mutating loop
  local act m l
  mutating=(uninstall)
  loop=(homepage deps info)
  t_sep "act / mutating / loop"
  for act in update uninstall rollback install homepage deps info; do
    (( ${mutating[(Ie)$act]} )) && m=mutating || m='-'
    (( ${loop[(Ie)$act]} )) && l=loop || l='-'
    printf '  %-10s %-9s %s\n' "$act" "$m" "$l"
  done
}

# 11. _pkg_get：注册表读取
#     关键回归点 —— 绝不能写 ${PKG[$var:field]}，zsh 会把 ':' 后的首字母
#     当成参数修饰符（:t tail / :h head / :r root / :e ext / :s suffix
#     / :l lower / :u upper），于是静默返回空。下面的字段名全部踩过这个坑。
t_case_pkg_get() {
  t_sep "首字母撞上修饰符的字段（这些曾全部静默返回空）"
  local f v
  for f in title loop runner homepage rollback search; do
    v=$(_pkg_get npm "$f")
    printf '  %-10s -> [%s]\n' "$f" "$v"
  done
  t_sep "未定义的字段应为空"
  for f in tap head root ext suffix lower upper; do
    v=$(_pkg_get npm "$f")
    printf '  %-10s -> [%s]\n' "$f" "$v"
  done
  t_sep "view 专属字段"
  printf '  manage:title        -> [%s]\n' "$(_pkg_get npm manage title)"
  printf '  search:opt          -> [%s]\n' "$(_pkg_get npm search opt)"
  printf '  mutating:outdated   -> [%s]\n' "$(_pkg_get npm mutating outdated)"
  t_sep "对照：直接写变量下标会静默失败"
  local -A T
  T=( [npm:title]=Npm [npm:views]="a b" )
  local eco=npm
  printf '  ${T[$eco:title]}   = [%s]  ← :t 被当成 tail，丢数据\n' "${T[$eco:title]}"
  printf '  ${T[$eco:views]}   = [%s]  ← :v 不是修饰符，侥幸正常\n' "${T[$eco:views]}"
  local key="${eco}:title"
  printf '  key=%s 后 T[$key] = [%s]  ← 正确做法\n' "$key" "${T[$key]}"
}

# 12. 多 ecosystem 注册表共存
#     回归点：zsh 关联数组的 PKG=(...) 是【整体替换】而非合并，
#     后 source 的 collection 会把先前的条目全部擦掉。
#     必须写 PKG+=(...)。此用例随每个 collection 迁移而增长。
t_case_pkg_coexist() {
  local eco
  t_sep "已迁移的 ecosystem 都应留在注册表里"
  for eco in npm pnpm pip; do
    printf '  %-6s title=[%s] views=[%s]\n' \
      "$eco" "$(_pkg_get "$eco" title)" "$(_pkg_get "$eco" views)"
  done
  t_sep "对照组：PKG=(...) 替换，PKG+=(...) 才合并"
  local -A T
  T=([x:1]=X [x:2]=Y)
  T=([y:1]=Z)
  printf '  T=([x:1] [x:2]) 后再 T=([y:1])  -> 条目数=%s  （1 = 被替换）\n' "${#T}"
  T=([x:1]=X [x:2]=Y)
  T+=([y:1]=Z)
  printf '  改用 T+=([y:1])               -> 条目数=%s  （3 = 正确合并）\n' "${#T}"
}

# 13. _pkg_session 必须把列表管道给 fzf
#     回归点：曾漏掉 `print -l -- "${_PKG_ROWS[@]}" |`，于是 fzf 自己去读终端，
#     把用户输入当成候选列表。这里用桩替换 _pkg_read，捕获它从 stdin 读到的内容。
t_case_pkg_session_stdin() {
  local line
  t_sep "fzf 从 stdin 读到的候选列表"
  functions[_pkg_read_orig]=$functions[_pkg_read]

  # 桩：原样打印从 stdin 读到的内容，然后模拟「用户取消」。
  # 必须写 stderr —— _pkg_read 是在 $(...) 的子 shell 里被调用的，
  # 写 stdout 会被命令替换吞掉，两种情况的输出就完全一样，测不出差别。
  # 收不到任何行时显式报错，这样「漏掉管道」才能被基线比对抓到。
  _pkg_read() {
    local line
    local n=0
    while IFS= read -r line; do print -r -- "  fzf<- [$line]" >&2; (( n++ )); done
    if (( n == 0 )); then
      print -r -- "  *** 错误：fzf 没收到候选列表（_PKG_ROWS 未管道给 fzf）***" >&2
    else
      print -r -- "  fzf 共收到 $n 行" >&2
    fi
    return 130
  }
  _pkg_list_stub() { printf 'alpha\t1.0\nmy package\t2.0\n' }
  _pkg_act_stub() { : }
  PKG+=(
    'probe:title'         'Probe'
    'probe:views'         'manage'
    'probe:manage'        '_pkg_list_stub'
    'probe:manage:title'  'Probe Manage'
    'probe:manage:actions' 'uninstall'
    'probe:mutating'      'uninstall'
    'probe:runner'        '_pkg_act_stub'
  )

  _pkg_session probe manage
  print "  取消后剩余行数=${#_PKG_ROWS}  （2 = 未误删）"

  unfunction _pkg_read _pkg_list_stub _pkg_act_stub
  eval "_pkg_read() { $functions[_pkg_read_orig] }"
  unfunction _pkg_read_orig
  for k in title views manage manage:title manage:actions mutating runner; do
    unset "PKG[probe:$k]"
  done
}

# 14. 多选结果的切分
#     回归点：曾写成 picked=(${(f)"$sel"})，那是非法语法 ——
#     zsh -n 查不出来，只有真正选中之后才在运行时抛 bad substitution。
#     正确写法是 "${(@f)sel}"（flag 不能与带引号的展开组合）。
t_case_pkg_pick_split() {
  local sel p
  local -a picked
  t_sep "多选：每行取首字段，多词包名要完整"
  sel="alpha	1.0
my package	2.0
gamma	3.0"
  picked=("${(@f)sel}")
  printf '  n=%d\n' "${#picked[@]}"
  for p in $picked; do
    printf '  [%s] -> name=[%s]\n' "${p//$'\t'/|}" "${p%%$'\t'*}"
  done
  t_sep "单选"
  sel="only one	9.9"
  picked=("${(@f)sel}")
  printf '  n=%d name=[%s]\n' "${#picked[@]}" "${picked[1]%%$'\t'*}"
}

# 15. 注册表自洽：动作名不得与内部数据键相撞，派发结果必须存在
#
# 回归点：回滚用的安装器曾登记为 PKG[<eco>:install]，而 install 正是
# search 视图的合法动作名。_pkg_act 用 PKG[<eco>:<动作名>] 查专用处理
# 函数，于是选「install」会命中回滚安装器，而且只收到包名一个参数 ——
# npm / pip / gem 三个 search 视图全中，pnpm 用 add 才躲过去。
# 症状要等真的去装一个包才暴露，所以这里静态拦住。
t_case_pkg_registry() {
  local key eco view act fn
  local -a ecos parts views acts k2 reserved providers
  local missing=0

  # 数据键必须从 base.zsh 的 _pkg_rollback 里推导，不能在这里抄一份。
  # 抄一份的话把键名改回去，本用例就跟着变，永远「一致」。
  reserved=(${(f)"$(sed -n '/^_pkg_rollback()/,/^}/p' base.zsh \
    | grep -o '_pkg_get "\$eco" [a-z][a-z-]*' | awk '{print $NF}')"})
  reserved=(${(u)reserved})

  ecos=()
  for key in "${(@k)PKG}"; do
    parts=("${(@s.:.)key}")
    (( ${#parts} == 2 )) || continue
    [[ ${parts[2]} == title ]] || continue
    ecos+=("${parts[1]}")
  done
  ecos=(${(u)ecos})

  t_sep "注册表自洽性（${#ecos} 个 ecosystem）"
  printf '  _pkg_rollback 读的数据键：%s\n' "${(j: :)reserved}"

  for eco in $ecos; do
    # 这几个键指向的函数就是「数据提供函数」。动作一旦解析到其中之一，
    # 说明 _pkg_act 把数据提供器当成了动作处理函数 —— 无论那个键叫什么，
    # 所以这里比的是函数身份，不是键名。
    providers=()
    for key in $reserved; do
      fn=$(_pkg_get $eco $key)
      [[ -n $fn ]] && providers+=($fn)
    done

    views=(${(s: :)$(_pkg_get $eco views)})
    for view in $views; do
      acts=(${(s: :)$(_pkg_get $eco $view actions)})
      for act in $acts; do
        fn=$(_pkg_get $eco $act)
        [[ -n $fn ]] || continue                  # 走 runner，不构成冲突
        if (( ${providers[(Ie)$fn]} )); then
          missing=1
          printf '  *** 错误：%s/%s 的动作 %s 解析到数据提供函数 %s ***\n' $eco $view $act $fn
        fi
        if (( ! ${+functions[$fn]} )); then
          missing=1
          printf '  *** 错误：%s/%s 的 %s 指向不存在的函数 %s ***\n' $eco $view $act $fn
        fi
      done
    done
  done
  (( missing )) || printf '  OK 无碰撞，派发目标全部存在\n'
  printf '  每个 view 都声明了 title/actions/cols 的：'
  for eco in $ecos; do
    for view in ${(s: :)$(_pkg_get $eco views)}; do
      k2=()
      for key in $view "${view}:title" "${view}:actions" "${view}:cols"; do
        [[ -n $(_pkg_get $eco $key) ]] || { missing=1; printf '\n    缺 %s/%s 的 %s' $eco $view $key }
      done
    done
  done
  (( missing )) || printf '是'
  printf '\n'
  printf '  已登记的 ecosystem：%s\n' "${(j: :)ecos}"
}

# 16. 键的形状：PKG[<eco>:<view>:<field>]，且驱动真的解析得到
#
# 回归点（用户实测报出）：brewf outdated 选中后回车没有子菜单。
# 原因是 _pkg_actions 把参数拼成了 PKG[<eco>:actions:<view>]，
# 而注册表登记的是 PKG[<eco>:<view>:actions] —— 读不到任何值且**不报错**，
# 只是静默返回空，于是动作清单为空，回车无事可做。
# 同一次迁移里 mutating 用的是另一种顺序，两种顺序并存才让这种错有可能发生。
#
# 这里既查形状（第二段必须是合法 view 名），也走驱动的真实解析路径查非空，
# 两者都必要：形状对但调用点顺序错，只有后者能抓到。
t_case_pkg_keyshape() {
  local key eco view
  local -a ecos parts
  local bad=0

  ecos=()
  for key in "${(@k)PKG}"; do
    parts=("${(@s.:.)key}")
    (( ${#parts} == 2 )) || continue
    [[ ${parts[2]} == title ]] || continue
    ecos+=("${parts[1]}")
  done
  ecos=(${(u)ecos})

  t_sep "键形状：每个三段键的第二段 X 必须有 PKG[<eco>:X:title]"
  for eco in $ecos; do
    for key in "${(@k)PKG}"; do
      parts=("${(@s.:.)key}")
      (( ${#parts} == 3 )) || continue
      [[ ${parts[1]} == $eco ]] || continue
      view=${parts[2]}
      # 判据必须是「这个 X 有没有自己的 title」，不能从现有键里反推 X 集合 ——
      # 那样写等于把顺序写反的键也算进合法 view 名，永远通过。
      # cargo:search 是个有 title 但不在 views 里的 view，本检查照样认可。
      if [[ -z $(_pkg_view_get $eco $view title) ]]; then
        bad=1
        printf '  *** 错误：%s 无 title，不是合法 view（键 %s 的分段顺序反了）***\n' $view $key
      fi
    done
  done
  (( bad )) || printf '  OK 全部 %d 个 ecosystem 的三段键顺序一致\n' ${#ecos}

  t_sep "驱动解析：每个 view 的动作清单都非空（回车必须有子菜单）"
  bad=0
  for eco in $ecos; do
    for view in ${(s: :)$(_pkg_get $eco views)}; do
      if _pkg_view_actions $eco $view 2>/dev/null; then
        printf '  OK   %-15s %2d 个动作\n' "$eco/$view" ${#_PKG_ACTIONS}
      else
        bad=1
        printf '  *** 错误：%s/%s 动作清单为空 ***\n' $eco $view
      fi
    done
  done
  (( bad )) || printf '  OK 全部非空\n'

  t_sep "驱动解析：view 级 mutating 覆盖必须真的被取到"
  bad=0
  for eco in $ecos; do
    for view in ${(s: :)$(_pkg_get $eco views)}; do
      key=$(_pkg_view_get $eco $view mutating)
      [[ -n $key ]] || continue
      _pkg_view_mutating $eco $view
      if [[ ${(j: :)${_PKG_MUTATING}} == ${(j: :)${(s: :)key}} ]]; then
        printf '  OK   %-15s 覆盖 [%s]\n' "$eco/$view" "$key"
      else
        bad=1
        printf '  *** 错误：%s/%s 覆盖=[%s] 实际=[%s] ***\n' \
          $eco $view "$key" "${(j: :)${_PKG_MUTATING}}"
      fi
    done
  done
  (( bad )) || printf '  OK 覆盖全部生效'
}

# 17. 完整循环：列表 -> 回车 -> 子菜单 -> 执行
#
# 回归点（用户实测报出）：brewf outdated 选中后回车没有子菜单。
# 动作清单解析成了 PKG[<eco>:actions:<view>]，而注册表是
# PKG[<eco>:<view>:actions] —— 读不到值且不报错，于是清单为空，
# fzf 第二次被调用时收到 0 个候选，什么都不弹。
#
# 计数器必须落文件。_pkg_read 是在 $(...) 的子 shell 里被调用的，
# 变量改动出不了子 shell —— 之前用变量计数时每次都以为是第一次调用，
# 结果永远返回列表行，session 空转到超时。这个坑项目里已记过档。
t_case_pkg_action_menu() {
  local cnt logf line n
  local k
  cnt=$(mktemp)
  logf=$(mktemp)
  print -r -- 0 >"$cnt"

  functions[_pkg_read_orig]=$functions[_pkg_read]
  _pkg_read() {
    local n
    n=$(<"$cnt")
    n=$(( n + 1 ))
    print -r -- "$n" >"$cnt"
    # 候选数与内容写 stderr：stdout 会被命令替换吞掉。
    # 裸调用 _pkg_session（不接管道），否则它跑在子 shell 里，
    # 改到的 _PKG_ROWS 出不来，末尾就永远报 0 行。
    local -a cand
    local c
    cand=("${(@f)$(cat)}")
    local -a brief
    for c in "${(@)cand}"; do
      # 列表行带 tab，取首字段（就是包名）；动作行没有 tab，整行照抄。
      # 目的是让基线里能读出候选是谁，不是还原 fzf 的渲染。
      [[ $c == *$'\t'* ]] && c=${c%%$'\t'*}
      brief+=("$c")
    done
    print -r -- "  fzf#$n 候选 ${#cand[@]} 个: ${(j: , :)brief}" >&2
    (( ${#cand} == 0 )) && print -r -- "  *** 错误：第 $n 次调用没有候选 ***" >&2
    # 第 2 次调用就是子菜单，候选必须是动作清单本身。
    # 这条断言直接对应「回车没反应」：清单解析不出来时，
    # fzf 收到的还是列表行，动作名变成了整行包名。
    if (( n == 2 )) && [[ "${(j: :)cand}" != 'show hide' ]]; then
      print -r -- "  *** 错误：子菜单候选应为 [show hide]，实为 [${(j: :)cand}] ***" >&2
    fi
    if (( n == 2 )) && [[ "${(j: :)cand[1]}" != show ]]; then
      print -r -- "  *** 错误：动作名变成了 [$cand[1]]，说明动作清单没解析出来 ***" >&2
    fi
    case $n in
      1) print -r -- $'alpha\t1.0\t=>\t2.0' ;;
      2) print -r -- 'show' ;;
      *) return 130 ;;
    esac
  }
  _pkg_probe_list() { printf 'alpha\t1.0\t=>\t2.0\nbeta\t3.0\t=>\t4.0\n' }
  _pkg_probe_runner() { print -r -- "  ACTION act=$1 pkg=[$2]" >&2; return 0 }
  PKG+=(
    'probe2:title'   'Probe2'
    'probe2:views'   'manage'
    'probe2:manage'  '_pkg_probe_list'
    'probe2:manage:title'   'Probe2 Manage'
    'probe2:manage:actions' 'show hide'
    'probe2:manage:cols'    '0,34,0,33'
    'probe2:mutating' 'hide'
    'probe2:loop'     'show'
    'probe2:runner'   '_pkg_probe_runner'
  )

  _pkg_session probe2 manage
  print -r -- "  fzf 共被调用 $(<"$cnt") 次（4 = 列表 + 子菜单 + 回子菜单 + 取消）"
  print -r -- "  剩余行数 ${#_PKG_ROWS}（show 在 loop 里不该删行，应为 2）"

  unfunction _pkg_read _pkg_probe_list _pkg_probe_runner
  eval "_pkg_read() { $functions[_pkg_read_orig] }"
  unfunction _pkg_read_orig
  for k in title views manage manage:title manage:actions manage:cols mutating loop runner; do
    unset "PKG[probe2:$k]"
  done
  rm -f "$cnt" "$logf"
}

# 18. 动作失败的处理（B9）
#
# 回归点：旧驱动的循环不看退出码 —— 一个包失败也继续跑完剩下的，
# 而且失败的那个照样被移出列表，于是它从屏幕上消失了但系统里还在。
# 现在 mutating 动作遇到失败立刻停止，只把成功的移出列表，并打印汇总；
# 只读动作不中止，因为它没有改变任何状态，「失败」往往只是「没有结果」。
t_case_pkg_failure() {
  local cnt logf line n log
  local k runner
  local -a rows
  typeset -g SEL_ACT
  cnt=$(mktemp)
  logf=$(mktemp)

  _pkg_p4_list() { printf 'a\t1\nb\t2\nc\t3\nd\t4\n' }
  # 第 2 个包失败，其余成功
  _pkg_p4_fail_second() {
    print -r -- "$*" >>"$logf"
    [[ $2 == b ]] && return 1
    return 0
  }
  _pkg_p4_always_ok()  { print -r -- "$*" >>"$logf"; return 0 }
  _pkg_p4_always_err() { print -r -- "$*" >>"$logf"; return 1 }
  # 128 + SIGINT：brew 下载 formulae 时被 Ctrl-C 掉就是这个退出码
  _pkg_p4_interrupt()  { print -r -- "$*" >>"$logf"; return 130 }

  functions[_pkg_read_orig]=$functions[_pkg_read]
  # 计数器落文件：_pkg_read 在 $(...) 子 shell 里被调用，变量出不去
  _pkg_read() {
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

  t_sep "mutating 中途失败：立刻停止、只删成功项、失败项可重试"
  runner=_pkg_p4_fail_second
  SEL_ACT=go
  PKG+=(
    'p4:title'  'P4'
    'p4:views'  'manage'
    'p4:manage' '_pkg_p4_list'
    'p4:manage:title'   'P4 Manage'
    'p4:manage:actions' 'go peek'
    'p4:manage:cols'    '0'
    'p4:mutating' 'go'
    'p4:loop'     'peek'
    'p4:runner'   "$runner"
  )
  print -r -- 0 >"$cnt"
  : >"$logf"
  _pkg_session p4 manage
  log=$(<"$logf")
  print -r -- "  runner 收到 ${#${(f)log}} 次调用: ${(j: :)${(f)log}}"
  print -r -- "  DONE=${(j: :)_PKG_DONE}  FAILED=${(j: :)_PKG_FAILED}  未执行=${_PKG_PENDING}"
  rows=()
  for line in "${_PKG_ROWS[@]}"; do rows+=("${line%%	*}"); done
  print -r -- "  剩余 ${#rows} 行: ${(j: :)rows}"
  for k in title views manage manage:title manage:actions manage:cols mutating loop runner; do
    unset "PKG[p4:$k]"
  done

  t_sep "mutating 全部成功：全部移出列表"
  SEL_ACT=go
  PKG+=(
    'p4:title'  'P4'
    'p4:views'  'manage'
    'p4:manage' '_pkg_p4_list'
    'p4:manage:title'   'P4 Manage'
    'p4:manage:actions' 'go peek'
    'p4:manage:cols'    '0'
    'p4:mutating' 'go'
    'p4:loop'     'peek'
    'p4:runner'   '_pkg_p4_always_ok'
  )
  print -r -- 0 >"$cnt"
  : >"$logf"
  _pkg_session p4 manage
  rows=()
  for line in "${_PKG_ROWS[@]}"; do rows+=("${line%%	*}"); done
  print -r -- "  剩余 ${#rows} 行: ${(j: :)rows}（应为 0）"
  for k in title views manage manage:title manage:actions manage:cols mutating loop runner; do
    unset "PKG[p4:$k]"
  done

  t_sep "只读动作返回非零：不中止、不删行"
  SEL_ACT=peek
  PKG+=(
    'p4:title'  'P4'
    'p4:views'  'manage'
    'p4:manage' '_pkg_p4_list'
    'p4:manage:title'   'P4 Manage'
    'p4:manage:actions' 'go peek'
    'p4:manage:cols'    '0'
    'p4:mutating' 'go'
    'p4:loop'     'peek'
    'p4:runner'   '_pkg_p4_always_err'
  )
  print -r -- 0 >"$cnt"
  : >"$logf"
  _pkg_session p4 manage
  log=$(<"$logf")
  print -r -- "  runner 收到 ${#${(f)log}} 次调用（4 = 没提前中止）"
  rows=()
  for line in "${_PKG_ROWS[@]}"; do rows+=("${line%%	*}"); done
  print -r -- "  剩余 ${#rows} 行: ${(j: :)rows}（应为 4）"
  for k in title views manage manage:title manage:actions manage:cols mutating loop runner; do
    unset "PKG[p4:$k]"
  done

  t_sep "退出码 130（Ctrl-C）：措辞与普通失败不同"
  SEL_ACT=go
  PKG+=(
    'p4:title'  'P4'
    'p4:views'  'manage'
    'p4:manage' '_pkg_p4_list'
    'p4:manage:title'   'P4 Manage'
    'p4:manage:actions' 'go peek'
    'p4:manage:cols'    '0'
    'p4:mutating' 'go'
    'p4:loop'     'peek'
    'p4:runner'   '_pkg_p4_interrupt'
  )
  print -r -- 0 >"$cnt"
  : >"$logf"
  _pkg_session p4 manage
  rows=()
  for line in "${_PKG_ROWS[@]}"; do rows+=("${line%%	*}"); done
  print -r -- "  剩余 ${#rows} 行: ${(j: :)rows}（应为 4，什么都没改成）"
  for k in title views manage manage:title manage:actions manage:cols mutating loop runner; do
    unset "PKG[p4:$k]"
  done

  eval "_pkg_read() { $functions[_pkg_read_orig] }"
  unfunction _pkg_read_orig _pkg_p4_list _pkg_p4_fail_second \
              _pkg_p4_always_ok _pkg_p4_always_err _pkg_p4_interrupt
  rm -f "$cnt" "$logf"
}

# 17. fp / envf 的取值与 --ansi
#     回归点 1：envf 的行含对齐填充与颜色码，取值必须掐掉它们，且要取
#     「首个字段之后的全部内容」而不是最后一个空白字段 —— 旧代码用
#     $F[$#F]，PATH 里有 "/Applications/VMware Fusion.app/..." 时
#     结果只剩 "Fusion.app/..."。
#     回归点 2：fzf 必须收 --ani。不给的话它把 \e[34m 当 5 个普通字符，
#     既不上色也把这 9 个字节算进显示宽度，长行于是被提前截断。
t_case_other_tail() {
  # 一次声明完，别在后面再写 local line 之类 —— 变量已是 local 时重复
  # 声明（且不带赋值）会往 stdout 打一行 `line=...`，混进基线。
  local ESC=$'\e' BLUE RESET PAD r line v
  local bad=0 f n_all n_ansi
  BLUE="${ESC}[34m"
  RESET="${ESC}[0m"
  PAD='                    '

  t_sep "取值：掐掉对齐填充与颜色码"
  line="${(l:24:: :)KEY}${BLUE}value${RESET}"
  print -r -- "  带色带填充 [$(_fzf_tail "$line")]  (应为 value)"
  line="${(l:24:: :)KEY}a b c"
  print -r -- "  值含空格   [$(_fzf_tail "$line")]  (应为 a b c，不能只剩 c)"

  t_sep "取值：值含空格时必须完整（回归点 1）"
  v=$(printenv __MISE_ORIG_PATH)
  if [[ -n $v ]]; then
    line="__MISE_ORIG_PATH${(l:20:: :)}${BLUE}${v}${RESET}"
    r="${line%%[[:space:]]*} = $(_fzf_tail "$line")"
    print -r -- "  真实值 ${#v} 字符，输出 ${#r} 字符（应差 19 = 键名加 ' = '）"
    if [[ $r == "__MISE_ORIG_PATH = $v" ]]; then
      print -r -- '  OK 值完整保留'
    else
      print -r -- '  *** 错误：值被截断 ***'
    fi
  else
    print -r -- '  (本机没有 __MISE_ORIG_PATH，跳过)'
  fi

  t_sep "fzf 调用必须带 --ansi（回归点 2）"
  for f in "$root"/collections/fzf-other.zsh; do
    [[ -f $f ]] || continue
    n_all=$(grep -c '| fzf "' "$f")
    n_ansi=$(grep -c '| fzf "[^"]*" --ansi' "$f")
    print -r -- "  fzf 调用 $n_all 处，其中带 --ansi 的 $n_ansi 处"
    (( n_all == n_ansi )) || { bad=1; print -r -- '  *** 有 fzf 调用缺 --ansi ***'; }
  done
  (( bad )) || print -r -- '  OK'
}

t_run_all() {
  t_case_underline
  t_case_format
  t_case_read
  t_case_msg
  t_case_header
  t_case_split
  t_case_loop
  t_case_pkg_display
  t_case_pkg_drop
  t_case_pkg_membership
  t_case_pkg_get
  t_case_pkg_coexist
  t_case_pkg_session_stdin
  t_case_pkg_pick_split
  t_case_pkg_registry
  t_case_pkg_keyshape
  t_case_pkg_action_menu
  t_case_pkg_failure
  t_case_other_tail
  printf '\n### END\n'
}
