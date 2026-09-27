# 行为基线测试用例
#
# 本文件会被三个 shell 分别 source：bash 3.2 / bash 5.3 / zsh 5.9
# 因此这里的每一行语法都必须同时在三者下成立 —— 任何分歧都说明
# body 尚未满足「纯 bash 语法、实际由 zsh 解析」这个约束。
#
# 用例只覆盖确定性、无副作用的纯函数。
# 不覆盖：_fc_pager(起 less)、_fc_homepage(开浏览器)、
#        _fc_cmd(要真 fzf 与真包管理器)
#
# 已删除的用例：t_case_header。它调用 _fzf_header —— 一个在 P1 换注册表驱动时
# 就删掉的函数。于是它每次打印 "command not found: _fzf_header"，而基线把那
# 两行录成了预期输出。三个门都曾这样"稳定地错"：_fzf_opts 被前一个用例清空、
# $root 没导出、以及这一条调用一个不存在的函数。基线只记录文本，分不出
# 「正确」与「每次都一样地错」。

# 用例之间的分隔标记，便于 diff 定位
t_sep() {
  printf '\n===== %s =====\n' "$1"
}

# 1. _fc_rule：header 下划线，长度应等于字符串长度
#    已知问题：base.sh:43 的 {1..$#1} 在 bash 下只输出 1 个字符
#    （bash 的 brace expansion 先于参数展开，{1..$#1} 被当作字面量）
t_case_rule() {
  local s
  for s in "Header Text" "abc" "Find Path" "Env" "Npm Outdated"; do
    printf -- '--- [%s] (len=%s) ---\n' "$s" "${#s}"
    _fc_rule "$s"
    printf '\n'
  done
}

# 2. _fzf_format：五种取值下的输出
#    已知：manage 与 pinned 共用同一分支，输出完全相同
#    已知：bogus 走 *) 分支，打印错误后 return 0
# 2. _fzf_format：只剩 general
#    原来有 manage / pinned / outdated / general 四个分支，每个一条 perl printf
#    规则（$rule 里用 perl 的 @F 与 %.15s）。迁移后包管理器全部走 _fc_render，
#    format 只有 general 还被 pathf / envf 使用，另外三个分支无法到达，已删除，
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

# 3. _fc_fzf_read：fzf 非交互模式（--filter）与退出码透传
#    这一条原本测的是 _fzf_read（缺陷 B1 / B11）。ffp 移除后 _fzf_read
#    零调用者，已随之删除，但它承载的 B11 知识不能丢：
#      旧 _fzf_read 结尾是 `fzf | perl`，perl 恒返回 0，于是它永远返回 0，
#      调用方无法区分「用户选中」与「用户取消」。
#    _fc_fzf_read 不管道任何东西，直接透传 $?，所以 B11 在这里已修。
#    保留这个用例是为了让「退出码必须透传」不再退化 —— 调用方靠它 break 循环。
t_case_read() {
  _FC_OPTS=()
  header="Test"

  t_sep "退出码：匹配时"
  printf 'alpha\nbeta\n' | _fc_fzf_read --filter=alp >/dev/null
  print -r -- "  _fc_fzf_read 退出码=$?"
  printf 'alpha\nbeta\n' | fzf --filter=alp >/dev/null
  print -r -- "  fzf 裸调用  退出码=$?   ← 两者必须一致"

  t_sep "退出码：无匹配时必须透传 fzf 的 1（缺陷 B11 的回归点）"
  printf 'alpha\nbeta\n' | _fc_fzf_read --filter=zzzz >/dev/null
  print -r -- "  _fc_fzf_read 退出码=$?   ← 必须是 1，不能恒为 0"
  printf 'alpha\nbeta\n' | fzf --filter=zzzz >/dev/null
  print -r -- "  fzf 裸调用  退出码=$?"
}

# 4. _fc_msg：消息输出格式
#    标签必须显式传。原来回退到 $caller —— 那是旧驱动的自由变量，
#    旧驱动删掉后无人赋值，单参调用会打出一个空标签。
t_case_msg() {
  t_sep "有 pkg"
  _fc_msg "some message" "mypkg"
  t_sep "无 pkg：回退到固定标签，不再依赖 \$caller"
  caller="MYFUNC"
  _fc_msg "another message"
}

# 5. 字段拆分：body 需要把「name<TAB>version...」拆开
#    注意：IFS=$'\t' read -r -a arr 是 bash-only（zsh: bad option: -a），
#    不可用于 body。下面两种形式在 bash 3.2 / bash 5 / zsh 下均可用。
t_case_split_row() {
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

# 8. _fc_render：结构化行 -> 对齐且上色的 fzf 显示行
#    行结构：name<TAB><补齐><TAB>rest。补齐在第一个 tab 之后，
#    所以取 name 无需剥空格。对齐只发生在这一层，_FC_ROWS 里是干净数据。
t_case_render() {
  local line out row segs2 c i
  local -a start ref
  # start/segs2 也用于下面的对齐断言
  t_sep "有 display：每列各自对齐，列间是真 tab"
  _FC_ROWS=("lodash	4.17.21" "my package	1.0.0 some desc")
  _fc_render | cat -v
  t_sep "无 display（search view）：原样输出，不补齐"
  _FC_ROWS=("all-the-package-names" "left-pad")
  _fc_render | cat -v
  t_sep "回读 name：多词包名完整，且天然没有尾随空格"
  _FC_ROWS=("my package	1.0.0")
  line=$(_fc_render)
  printf '  显示行=[%s]\n' "$line"
  printf '  name=[%s]\n' "${line%%	*}"
  t_sep "_FC_ROWS 保持干净（未被显示层污染）"
  _FC_ROWS=("alpha	1" "beta	2" "a-very-long-name	3")
  _fc_render >/dev/null
  printf '  [%s]\n' "${(j:,:)${_FC_ROWS}}"

  # 字符级断言：显示行里绝不能出现字面的反斜杠。
  # 回归点：曾用 ${(j:\t:)segs} 拼行，而 flag 参数是字面量、不解释转义，
  # 于是输出全是字面 \t。基线只「记录现状」，抓不到这类 bug，必须显式断言。
  t_sep "字符级断言：不得出现字面反斜杠"
  _FC_ROWS=("a	1" "bb	2")
  out=$(_fc_render)
  if [[ $out == *'\'* ]]; then
    print -r -- '  *** 错误：显示行里出现字面反斜杠，tab 拼接写错了 ***'
  else
    print -r -- '  OK 无字面反斜杠'
  fi
  [[ $out == *$'\t'* ]] && print -r -- '  含真 tab: yes' || print -r -- '  含真 tab: no'

  # 对齐断言：所有行的每一个数据列都必须起始于同一列。
  # 回归点：曾写成 for seg in $segs（未加引号），zsh 会丢弃空元素，
  # 而补齐段在最长的那行恰好为空 —— 那一行就少一个 tab、整行左移。
  # 列间的 tab 数（_FC_COLUMN_GAP，默认 5）不固定，所以只比较数据列本身。
  t_sep "对齐断言：各数据列起始位置必须一致"
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
  unset '_FC_REG[al:manage:cols]'

  # 纯度断言：显示层每行必须以包名开头。
  # 回归点：zsh 5.9 在循环体内执行标量 local 时，会往 stdout 打一行
  # `NAME=<上一轮的值>`。本函数的 stdout 直接喂给 fzf，那一行会变成一条
  # 假候选（曾经表现为 pnpmf 列表里混进 k=6 / k=''）。zsh -n 查不出，
  # tests/run.sh --local 那道静态门负责在写入时拦住，这里负责兜住症状。
  t_sep "纯度断言：每行必须以包名开头（无 NAME= 污染、无前导 tab）"
  _FC_ROWS=("a	1	=>	1"
             "much-longer-name	22	=>	22"
             "mid	333	=>	333")
  _FC_REG+=('al:manage:cols' 'name have sep want')
  local -a names
  names=()
  for row in "${(@f)$(_fc_render al manage)}"; do
    names+=("${row%%	*}")
  done
  print -r -- "  各行首段: ${(j: | :)names}"
  local expect=('a' 'much-longer-name' 'mid')
  if [[ ${(j:|:)names} == "${(j:|:)expect}" ]]; then
    print -r -- '  OK 首段与包名一一对应'
  else
    print -r -- "  *** 错误：首段与包名不符 —— 有非数据行混进了输出 ***"
  fi
  unset '_FC_REG[al:manage:cols]'
}

# 9. _fc_drop_row：从 _FC_ROWS 精确删除匹配的行
#    对照 ${(@)rows:#pat} 的 glob 误伤 —— 这是必须用 while + [[ == ]] 的原因
t_case_drop_row() {
  t_sep "删除存在的行"
  _FC_ROWS=("alpha	1" "beta	2" "gamma	3")
  _fc_drop_row "beta"
  printf '  n=%d  [%s]\n' ${#_FC_ROWS} "${(j:,:)${_FC_ROWS}}"
  t_sep "删除多词包名（精确匹配，不能误伤其它行）"
  _FC_ROWS=("my package	1" "other-pkg	2" "my package extra	3")
  _fc_drop_row "my package"
  printf '  n=%d  [%s]\n' ${#_FC_ROWS} "${(j:,:)${_FC_ROWS}}"
  t_sep "删除不存在的行（不应误删）"
  _FC_ROWS=("a*x	1" "ab	2" "axb	3")
  _fc_drop_row "a*x"
  printf '  n=%d  [%s]\n' ${#_FC_ROWS} "${(j:,:)${_FC_ROWS}}"
  t_sep "对照：glob 写法会误伤（这就是不用它的原因）"
  _FC_ROWS=("a*x	1" "ab	2" "axb	3")
  printf '  ${(@)_FC_ROWS:#*x*} -> n=%d （3 行被全删）\n' ${#${(@)_FC_ROWS:#*x*}}
}

# 10. 动作成员判定：${arr[(Ie)act]} 是驱动判断「删行回列表」还是
#     「留在动作菜单」的唯一依据
t_case_membership() {
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

# 11. _fc_reg_get：注册表读取
#     关键回归点 —— 绝不能写 ${_FC_REG[$var:field]}，zsh 会把 ':' 后的首字母
#     当成参数修饰符（:t tail / :h head / :r root / :e ext / :s suffix
#     / :l lower / :u upper），于是静默返回空。下面的字段名全部踩过这个坑。
t_case_reg_get() {
  t_sep "首字母撞上修饰符的字段（这些曾全部静默返回空）"
  local f v
  for f in title loop runner homepage rollback search; do
    v=$(_fc_reg_get npm "$f")
    printf '  %-10s -> [%s]\n' "$f" "$v"
  done
  t_sep "未定义的字段应为空"
  for f in tap head root ext suffix lower upper; do
    v=$(_fc_reg_get npm "$f")
    printf '  %-10s -> [%s]\n' "$f" "$v"
  done
  t_sep "view 专属字段"
  printf '  manage:title        -> [%s]\n' "$(_fc_reg_get npm manage title)"
  printf '  search:opt          -> [%s]\n' "$(_fc_reg_get npm search opt)"
  printf '  mutating:outdated   -> [%s]\n' "$(_fc_reg_get npm mutating outdated)"
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
#     回归点：zsh 关联数组的 _FC_REG=(...) 是【整体替换】而非合并，
#     后 source 的 collection 会把先前的条目全部擦掉。
#     必须写 _FC_REG+=(...)。此用例随每个 collection 迁移而增长。
t_case_coexist() {
  local eco
  t_sep "已迁移的 ecosystem 都应留在注册表里"
  for eco in npm pnpm pip; do
    printf '  %-6s title=[%s] views=[%s]\n' \
      "$eco" "$(_fc_reg_get "$eco" title)" "$(_fc_reg_get "$eco" views)"
  done
  t_sep "对照组：_FC_REG=(...) 替换，_FC_REG+=(...) 才合并"
  local -A T
  T=([x:1]=X [x:2]=Y)
  T=([y:1]=Z)
  printf '  T=([x:1] [x:2]) 后再 T=([y:1])  -> 条目数=%s  （1 = 被替换）\n' "${#T}"
  T=([x:1]=X [x:2]=Y)
  T+=([y:1]=Z)
  printf '  改用 T+=([y:1])               -> 条目数=%s  （3 = 正确合并）\n' "${#T}"
}

# 13. _fc_session 必须把列表管道给 fzf
#     回归点：曾漏掉 `print -l -- "${_FC_ROWS[@]}" |`，于是 fzf 自己去读终端，
#     把用户输入当成候选列表。这里用桩替换 _fc_fzf_read，捕获它从 stdin 读到的内容。
t_case_session_stdin() {
  local line
  t_sep "fzf 从 stdin 读到的候选列表"
  functions[_t_read_orig]=$functions[_fc_fzf_read]

  # 桩：原样打印从 stdin 读到的内容，然后模拟「用户取消」。
  # 必须写 stderr —— _fc_fzf_read 是在 $(...) 的子 shell 里被调用的，
  # 写 stdout 会被命令替换吞掉，两种情况的输出就完全一样，测不出差别。
  # 收不到任何行时显式报错，这样「漏掉管道」才能被基线比对抓到。
  _fc_fzf_read() {
    local line
    local n=0
    while IFS= read -r line; do print -r -- "  fzf<- [$line]" >&2; (( n++ )); done
    if (( n == 0 )); then
      print -r -- "  *** 错误：fzf 没收到候选列表（_FC_ROWS 未管道给 fzf）***" >&2
    else
      print -r -- "  fzf 共收到 $n 行" >&2
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
    'probe:runner'        '_t_act_stub'
  )

  _fc_session probe manage
  print "  取消后剩余行数=${#_FC_ROWS}  （2 = 未误删）"

  unfunction _fc_fzf_read _t_list_stub _t_act_stub
  eval "_fc_fzf_read() { $functions[_t_read_orig] }"
  unfunction _t_read_orig
  for k in title views manage manage:title manage:actions mutating runner; do
    unset "_FC_REG[probe:$k]"
  done
}

# 14. 多选结果的切分
#     回归点：曾写成 picked=(${(f)"$sel"})，那是非法语法 ——
#     zsh -n 查不出来，只有真正选中之后才在运行时抛 bad substitution。
#     正确写法是 "${(@f)sel}"（flag 不能与带引号的展开组合）。
t_case_pick_split() {
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
# 回归点：回滚用的安装器曾登记为 _FC_REG[<eco>:install]，而 install 正是
# search 视图的合法动作名。_fc_act 用 _FC_REG[<eco>:<动作名>] 查专用处理
# 函数，于是选「install」会命中回滚安装器，而且只收到包名一个参数 ——
# npm / pip / gem 三个 search 视图全中，pnpm 用 add 才躲过去。
# 症状要等真的去装一个包才暴露，所以这里静态拦住。
t_case_registry() {
  local key eco view act fn
  local -a ecos parts views acts k2 reserved providers
  local missing=0

  # 数据键必须从 base.zsh 的 _fc_rollback 里推导，不能在这里抄一份。
  # 抄一份的话把键名改回去，本用例就跟着变，永远「一致」。
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

  t_sep "注册表自洽性（${#ecos} 个 ecosystem）"
  printf '  _fc_rollback 读的数据键：%s\n' "${(j: :)reserved}"

  for eco in $ecos; do
    # 这几个键指向的函数就是「数据提供函数」。动作一旦解析到其中之一，
    # 说明 _fc_act 把数据提供器当成了动作处理函数 —— 无论那个键叫什么，
    # 所以这里比的是函数身份，不是键名。
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
    for view in ${(s: :)$(_fc_reg_get $eco views)}; do
      k2=()
      for key in $view "${view}:title" "${view}:actions" "${view}:cols"; do
        [[ -n $(_fc_reg_get $eco $key) ]] || { missing=1; printf '\n    缺 %s/%s 的 %s' $eco $view $key }
      done
    done
  done
  (( missing )) || printf '是'
  printf '\n'
  printf '  已登记的 ecosystem：%s\n' "${(j: :)ecos}"
}

# 16. 键的形状：_FC_REG[<eco>:<view>:<field>]，且驱动真的解析得到
#
# 回归点（用户实测报出）：brewf outdated 选中后回车没有子菜单。
# 原因是 _fc_actions 把参数拼成了 _FC_REG[<eco>:actions:<view>]，
# 而注册表登记的是 _FC_REG[<eco>:<view>:actions] —— 读不到任何值且**不报错**，
# 只是静默返回空，于是动作清单为空，回车无事可做。
# 同一次迁移里 mutating 用的是另一种顺序，两种顺序并存才让这种错有可能发生。
#
# 这里既查形状（第二段必须是合法 view 名），也走驱动的真实解析路径查非空，
# 两者都必要：形状对但调用点顺序错，只有后者能抓到。
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

  t_sep "键形状：每个三段键的第二段 X 必须有 _FC_REG[<eco>:X:title]"
  for eco in $ecos; do
    for key in "${(@k)_FC_REG}"; do
      parts=("${(@s.:.)key}")
      (( ${#parts} == 3 )) || continue
      [[ ${parts[1]} == $eco ]] || continue
      view=${parts[2]}
      # 判据必须是「这个 X 有没有自己的 title」，不能从现有键里反推 X 集合 ——
      # 那样写等于把顺序写反的键也算进合法 view 名，永远通过。
      # cargo:search 是个有 title 但不在 views 里的 view，本检查照样认可。
      if [[ -z $(_fc_reg_view_get $eco $view title) ]]; then
        bad=1
        printf '  *** 错误：%s 无 title，不是合法 view（键 %s 的分段顺序反了）***\n' $view $key
      fi
    done
  done
  (( bad )) || printf '  OK 全部 %d 个 ecosystem 的三段键顺序一致\n' ${#ecos}

  t_sep "驱动解析：每个 view 的动作清单都非空（回车必须有子菜单）"
  bad=0
  for eco in $ecos; do
    for view in ${(s: :)$(_fc_reg_get $eco views)}; do
      if _fc_reg_view_actions $eco $view 2>/dev/null; then
        printf '  OK   %-15s %2d 个动作\n' "$eco/$view" ${#_FC_ACTIONS}
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
    for view in ${(s: :)$(_fc_reg_get $eco views)}; do
      key=$(_fc_reg_view_get $eco $view mutating)
      [[ -n $key ]] || continue
      _fc_reg_view_mutating $eco $view
      if [[ ${(j: :)${_FC_MUTATING}} == ${(j: :)${(s: :)key}} ]]; then
        printf '  OK   %-15s 覆盖 [%s]\n' "$eco/$view" "$key"
      else
        bad=1
        printf '  *** 错误：%s/%s 覆盖=[%s] 实际=[%s] ***\n' \
          $eco $view "$key" "${(j: :)${_FC_MUTATING}}"
      fi
    done
  done
  (( bad )) || printf '  OK 覆盖全部生效'
}

# 17. 完整循环：列表 -> 回车 -> 子菜单 -> 执行
#
# 回归点（用户实测报出）：brewf outdated 选中后回车没有子菜单。
# 动作清单解析成了 _FC_REG[<eco>:actions:<view>]，而注册表是
# _FC_REG[<eco>:<view>:actions] —— 读不到值且不报错，于是清单为空，
# fzf 第二次被调用时收到 0 个候选，什么都不弹。
#
# 计数器必须落文件。_fc_fzf_read 是在 $(...) 的子 shell 里被调用的，
# 变量改动出不了子 shell —— 之前用变量计数时每次都以为是第一次调用，
# 结果永远返回列表行，session 空转到超时。这个坑项目里已记过档。
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
    # 候选数与内容写 stderr：stdout 会被命令替换吞掉。
    # 裸调用 _fc_session（不接管道），否则它跑在子 shell 里，
    # 改到的 _FC_ROWS 出不来，末尾就永远报 0 行。
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
    'probe2:loop'     'show'
    'probe2:runner'   '_t_probe_runner'
  )

  _fc_session probe2 manage
  print -r -- "  fzf 共被调用 $(<"$cnt") 次（4 = 列表 + 子菜单 + 回子菜单 + 取消）"
  print -r -- "  剩余行数 ${#_FC_ROWS}（show 在 loop 里不该删行，应为 2）"

  unfunction _fc_fzf_read _t_probe_list _t_probe_runner
  eval "_fc_fzf_read() { $functions[_t_read_orig] }"
  unfunction _t_read_orig
  for k in title views manage manage:title manage:actions manage:cols mutating loop runner; do
    unset "_FC_REG[probe2:$k]"
  done
  rm -f "$cnt" "$logf"
}

# 18. 动作失败的处理（B9）
#
# 回归点：旧驱动的循环不看退出码 —— 一个包失败也继续跑完剩下的，
# 而且失败的那个照样被移出列表，于是它从屏幕上消失了但系统里还在。
# 现在 mutating 动作遇到失败立刻停止，只把成功的移出列表，并打印汇总；
# 只读动作不中止，因为它没有改变任何状态，「失败」往往只是「没有结果」。
t_case_failure() {
  local cnt logf line n log
  local k runner
  local -a rows
  # local 而不是 typeset -g：stub _fc_fzf_read 是在 $(...) 子 shell 里被调的，
  # zsh 动态作用域照样看得到调用者的 local，但它不该以全局的形式活过本用例。
  # （插件自己也依赖同一个性质，见 base.zsh 的 _fc_fzf_read 读 header。）
  local SEL_ACT
  cnt=$(mktemp)
  logf=$(mktemp)

  _t_p4_list() { printf 'a\t1\nb\t2\nc\t3\nd\t4\n' }
  # 第 2 个包失败，其余成功
  _t_p4_fail_second() {
    print -r -- "$*" >>"$logf"
    [[ $2 == b ]] && return 1
    return 0
  }
  _t_p4_always_ok()  { print -r -- "$*" >>"$logf"; return 0 }
  _t_p4_always_err() { print -r -- "$*" >>"$logf"; return 1 }
  # 128 + SIGINT：brew 下载 formulae 时被 Ctrl-C 掉就是这个退出码
  _t_p4_interrupt()  { print -r -- "$*" >>"$logf"; return 130 }

  functions[_t_read_orig]=$functions[_fc_fzf_read]
  # 计数器落文件：_fc_fzf_read 在 $(...) 子 shell 里被调用，变量出不去
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

  t_sep "mutating 中途失败：立刻停止、只删成功项、失败项可重试"
  runner=_t_p4_fail_second
  SEL_ACT=go
  _FC_REG+=(
    'p4:title'  'P4'
    'p4:views'  'manage'
    'p4:manage' '_t_p4_list'
    'p4:manage:title'   'P4 Manage'
    'p4:manage:actions' 'go peek'
    'p4:manage:cols'    'name'
    'p4:mutating' 'go'
    'p4:loop'     'peek'
    'p4:runner'   "$runner"
  )
  print -r -- 0 >"$cnt"
  : >"$logf"
  _fc_session p4 manage
  log=$(<"$logf")
  print -r -- "  runner 收到 ${#${(f)log}} 次调用: ${(j: :)${(f)log}}"
  print -r -- "  DONE=${(j: :)_FC_DONE}  FAILED=${(j: :)_FC_FAILED}  未执行=${_FC_PENDING}"
  rows=()
  for line in "${_FC_ROWS[@]}"; do rows+=("${line%%	*}"); done
  print -r -- "  剩余 ${#rows} 行: ${(j: :)rows}"
  for k in title views manage manage:title manage:actions manage:cols mutating loop runner; do
    unset "_FC_REG[p4:$k]"
  done

  t_sep "mutating 全部成功：全部移出列表"
  SEL_ACT=go
  _FC_REG+=(
    'p4:title'  'P4'
    'p4:views'  'manage'
    'p4:manage' '_t_p4_list'
    'p4:manage:title'   'P4 Manage'
    'p4:manage:actions' 'go peek'
    'p4:manage:cols'    'name'
    'p4:mutating' 'go'
    'p4:loop'     'peek'
    'p4:runner'   '_t_p4_always_ok'
  )
  print -r -- 0 >"$cnt"
  : >"$logf"
  _fc_session p4 manage
  rows=()
  for line in "${_FC_ROWS[@]}"; do rows+=("${line%%	*}"); done
  print -r -- "  剩余 ${#rows} 行: ${(j: :)rows}（应为 0）"
  for k in title views manage manage:title manage:actions manage:cols mutating loop runner; do
    unset "_FC_REG[p4:$k]"
  done

  t_sep "只读动作返回非零：不中止、不删行"
  SEL_ACT=peek
  _FC_REG+=(
    'p4:title'  'P4'
    'p4:views'  'manage'
    'p4:manage' '_t_p4_list'
    'p4:manage:title'   'P4 Manage'
    'p4:manage:actions' 'go peek'
    'p4:manage:cols'    'name'
    'p4:mutating' 'go'
    'p4:loop'     'peek'
    'p4:runner'   '_t_p4_always_err'
  )
  print -r -- 0 >"$cnt"
  : >"$logf"
  _fc_session p4 manage
  log=$(<"$logf")
  print -r -- "  runner 收到 ${#${(f)log}} 次调用（4 = 没提前中止）"
  rows=()
  for line in "${_FC_ROWS[@]}"; do rows+=("${line%%	*}"); done
  print -r -- "  剩余 ${#rows} 行: ${(j: :)rows}（应为 4）"
  for k in title views manage manage:title manage:actions manage:cols mutating loop runner; do
    unset "_FC_REG[p4:$k]"
  done

  t_sep "退出码 130（Ctrl-C）：措辞与普通失败不同"
  SEL_ACT=go
  _FC_REG+=(
    'p4:title'  'P4'
    'p4:views'  'manage'
    'p4:manage' '_t_p4_list'
    'p4:manage:title'   'P4 Manage'
    'p4:manage:actions' 'go peek'
    'p4:manage:cols'    'name'
    'p4:mutating' 'go'
    'p4:loop'     'peek'
    'p4:runner'   '_t_p4_interrupt'
  )
  print -r -- 0 >"$cnt"
  : >"$logf"
  _fc_session p4 manage
  rows=()
  for line in "${_FC_ROWS[@]}"; do rows+=("${line%%	*}"); done
  print -r -- "  剩余 ${#rows} 行: ${(j: :)rows}（应为 4，什么都没改成）"
  for k in title views manage manage:title manage:actions manage:cols mutating loop runner; do
    unset "_FC_REG[p4:$k]"
  done

  eval "_fc_fzf_read() { $functions[_t_read_orig] }"
  unfunction _t_read_orig _t_p4_list _t_p4_fail_second \
              _t_p4_always_ok _t_p4_always_err _t_p4_interrupt
  rm -f "$cnt" "$logf"
}

# 19. _fc_load_rows：把查询输出收进 _FC_ROWS
#
# 这里换掉了实现（原 while-read + arr+=()，O(n^2)），语义必须一模一样：
#   - 空行丢掉
#   - 末行没有换行也要收进来
#   - 不改动行内容（tab 原样保留，那是 _fc_render 的输入）
#     回归点：曾经用 $(cat) slurp，命令替换会吃掉尾部换行，
#     按行切完末尾多出一个空元素，不清掉就会变成一条空白候选。
t_case_load_rows() {
  local out
  t_sep "常规输入：三行，含空行"
  out=$(printf 'alpha\t1.0\n\nbeta\t2.0\n' | _fc_load_rows; print -r -- "n=${#_FC_ROWS} [${(j:,:)${_FC_ROWS}}]")
  print -r -- "  $out"
  t_sep "末行无换行"
  out=$(printf 'alpha\t1.0\nbeta' | _fc_load_rows; print -r -- "n=${#_FC_ROWS} [${(j:,:)${_FC_ROWS}}]")
  print -r -- "  $out"
  t_sep "只有空行"
  out=$(printf '\n\n' | _fc_load_rows; print -r -- "n=${#_FC_ROWS} [${(j:,:)${_FC_ROWS}}]")
  print -r -- "  $out"
  t_sep "无输入"
  out=$(printf '' | _fc_load_rows; print -r -- "n=${#_FC_ROWS}")
  print -r -- "  $out"
  t_sep "空行与首尾空白不是一回事：'  ' 要留着"
  out=$(printf '  \nx\t\n' | _fc_load_rows; print -r -- "n=${#_FC_ROWS} [${(j:|:)${_FC_ROWS}}]")
  print -r -- "  $out"
  _FC_ROWS=()
}

# 20. 单列 + 无 mutating 动作的视图走流式路径
#
# 回归点（用户实测报出）：pnpmf -> search 一直不出候选，越等越久。
# 重构后所有视图都先把整份列表读进 _FC_ROWS，而 _fc_load_rows 原来的
# while-read + 数组 append 是 O(n^2)（8 万行 172s，翻一倍 4 倍）。
# search 的数据源是 all-the-package-names，有 448 万行，于是 fzf
# 在一个多小时里一个候选都收不到。重构前的 _fzf_search 是
# `$available | _fzf_tmp_write`，也就是直接流进 fzf，所以是秒开。
#
# 断言三件事：候选内容与缓冲路径一致（取首字段 + 丢空行）、
# _FC_ROWS 全程为空、_fc_render 一次都没被调用。
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
    print -r -- '  *** 错误：流式视图不该调用 _fc_render ***' >&2
    cat
  }
  _fc_fzf_read() {
    local n
    n=$(<"$cnt")
    n=$(( n + 1 ))
    print -r -- "$n" >"$cnt"
    cand=("${(@f)$(cat)}")
    cand=("${(@)cand:#}")
    print -r -- "  fzf#$n 收到 ${#cand[@]} 个候选: ${(j:,:)cand}" >&2
    (( ${#cand} == 0 )) && print -r -- '  *** 错误：第 '"$n"' 次调用没有候选 ***' >&2
    case $n in
      1) print -r -- 'alpha' ;;
      2) print -r -- 'show' ;;
      *) return 130 ;;
    esac
  }
  # 计数器必须落文件：查询函数是在 _fc_feed 的管道里跑的，出不了子 shell
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
    # 唯一声明的 mutating 动作是 uninstall，而 search 的动作里没有它 ——
    # 交集为空正是可流式的判据
    's1:mutating'     'uninstall'
    's1:loop'         'install'
    's1:runner'       '_t_s_runner'
  )

  _fc_session s1 search
  log=$(<"$logf")
  printf '  查询被调用 %s 次（2 = 列表 + 动作后回到列表）\n' "$(<"$qcnt")"
  printf '  _FC_ROWS 长度 %d（0 = 流式路径不缓冲）\n' "${#_FC_ROWS}"
  printf '  动作收到: %s\n' "${(j: :)${(f)log}}"
  printf '  fzf 共被调用 %s 次（3 = 列表 + 子菜单 + 取消）\n' "$(<"$cnt")"

  unfunction _fc_fzf_read _fc_render _t_s_list _t_s_runner
  eval "_fc_fzf_read() { $functions[_t_read_orig] }"
  eval "_fc_render() { $functions[_t_render_orig] }"
  unfunction _t_read_orig _t_render_orig
  for k in title views search search:title search:actions search:cols mutating loop runner; do
    unset "_FC_REG[s1:$k]"
  done
  rm -f "$cnt" "$qcnt" "$logf"

  t_sep "流式分类：448 万行的 npm / pnpm search 必须判成可流式"
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
      if _fc_view_streamable "$eco" "$view"; then how=流式; else how=缓冲; fi
      printf '  %-4s %s/%s\n' "$how" "$eco" "$view"
    done
  done
  for view in npm/search pnpm/search; do
    eco=${view%%/*}; view=${view#*/}
    _fc_view_streamable "$eco" "$view" || { bad=1; printf '  *** 错误：%s 判成缓冲，search 会重新变成 O(n^2) ***\n' "$eco/$view" }
  done
  # 多列视图必须留在缓冲路径：它们要宽度预扫描，cut -f1 给不了对齐
  for view in npm/manage pnpm/outdated brew/manage gem/manage; do
    eco=${view%%/*}; view=${view#*/}
    _fc_view_streamable "$eco" "$view" && { bad=1; printf '  *** 错误：%s 是多列视图，不该判成流式 ***\n' "$eco/$view" }
  done
  (( bad )) || printf '  OK 448 万行的 search 是流式，多列视图仍走缓冲'
}

# 17. pathf / envf 的取值与 --ansi
#     回归点 1：envf 的行含对齐填充与颜色码，取值必须掐掉它们，且要取
#     「首个字段之后的全部内容」而不是最后一个空白字段 —— 旧代码用
#     $F[$#F]，PATH 里有 "/Applications/VMware Fusion.app/..." 时
#     结果只剩 "Fusion.app/..."。
#     回归点 2：fzf 必须收 --ani。不给的话它把 \e[34m 当 5 个普通字符，
#     既不上色也把这 9 个字节算进显示宽度，长行于是被提前截断。
t_case_other_value() {
  # 一次声明完，别在后面再写 local line 之类 —— 变量已是 local 时重复
  # 声明（且不带赋值）会往 stdout 打一行 `line=...`，混进基线。
  local ESC=$'\e' BLUE RESET PAD r line v
  local bad=0 f n_all n_ansi
  BLUE="${ESC}[34m"
  RESET="${ESC}[0m"
  PAD='                    '

  t_sep "取值：掐掉对齐填充与颜色码"
  line="${(l:24:: :)KEY}${BLUE}value${RESET}"
  print -r -- "  带色带填充 [$(_other_value "$line")]  (应为 value)"
  line="${(l:24:: :)KEY}a b c"
  print -r -- "  值含空格   [$(_other_value "$line")]  (应为 a b c，不能只剩 c)"

  t_sep "取值：值含空格时必须完整（回归点 1）"
  v=$(printenv __MISE_ORIG_PATH)
  if [[ -n $v ]]; then
    line="__MISE_ORIG_PATH${(l:20:: :)}${BLUE}${v}${RESET}"
    r="${line%%[[:space:]]*} = $(_other_value "$line")"
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

# 18. envf 的显示宽度与取值还原
#     回归点：PATH 的值实测 1994 字符（另一次会话里 2562），是 200 列终端的
#     10 倍以上，FPATH / LS_COLORS / __MISE_ZSH_ACTIVATE_PATH 同样超宽。
#     fzf 只能截断并横向滚动这些行，一行看着只剩尾部，整个列表像错位。
#     fp 的值是「目录 + 文件名」，从不满屏，所以 pathf 不受影响 ——
#     这就是两个命令表现不同的原因。
#     显示截断后，选中必须仍输出完整值。
t_case_envf_width() {
  # 基准与被测必须同进程同时取：PATH 在子 shell 里会被 zsh/mise 改写，
  # 跨进程比对毫无意义（曾因此把正确的实现误判成不一致）。
  #
  # 临时文件目录用 mktemp -d，不依赖 $root —— $root 只在 tests/run.sh 里定义，
  # 单独 source 本文件调用某个 t_case_xxx 时它是空的。
  local ESC=$'\e'
  local ENVF_TMP
  ENVF_TMP=$(mktemp -d "${TMPDIR:-/tmp}/fzf-envf.XXXXXX") || return 1
  typeset -A base
  local r
  while IFS= read -r -d $'\0' r; do
    [[ $r == *=* ]] || continue
    base[${r%%=*}]=${r#*=}
  done < <(printenv --null)

  t_sep "显示层：候选行不得超屏宽"
  local probe=$ENVF_TMP/probe.$$
  local longest over
  fzf() { cat > "$probe"; return 0; }
  # 必须让 envf 直接写文件，不能用 $(envf) 捕获 ——
  # 桩把候选写进文件后，管道下游没有任何输出，envf 提前返回，
  # 命令替换会与桩争抢同一个 probe 文件，结果两边都读不到。
  envf >/dev/null 2>&1
  if [[ -f $probe ]]; then
    longest=$(awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }' "$probe")
    over=$(awk 'length($0) > 200 { c++ } END { print c + 0 }' "$probe")
    print -r -- "  最长行 ${longest} 字符，超 200 列的行 ${over} 条"
    print -r -- "  （截断上限由 _ENVF_VALMAX 控制，默认 80）"
    if (( longest <= 200 )); then
      print -r -- '  OK'
    else
      print -r -- '  *** 错误：仍有超屏宽的行 ***'
    fi
  else
    print -r -- '  (envf 没有产出候选，跳过)'
  fi
  rm -f "$probe"

  t_sep "取值层：显示被截，选中仍须输出完整值"
  # 桩：模拟「用户只选中了 key 这一行」，走 envf 真实的取值循环。
  #
  # 桩不能写成 `fzf() { while read l; ...; }` —— envf 的 fzf 在管道里，
  # 桩函数的 while 会读到**函数自己的** stdin 而不是管道来的候选，什么都读不到
  # （曾因此全部报「实际 0」）。正确做法是把候选先落到文件再挑。
  #
  # want / l / sel 必须在循环外声明 —— 循环体内的标量 local 会污染 stdout。
  local want got l sel outf pick
  for want in PATH FPATH LS_COLORS FZF_DEFAULT_OPTS LUA_INIT PWD \
             __MISE_ORIG_PATH SHLVL HOME; do
    [[ -n ${base[$want]:-} ]] || continue
    outf=$ENVF_TMP/out.$$
    pick=$ENVF_TMP/pick.$$
    fzf() {
      cat > "$pick"
      # 剥色后按键名挑出那一行，模拟 fzf 选中后输出的内容
      sed "s/$ESC\\[[0-9;]*m//g" "$pick" 2>/dev/null \
        | while IFS= read -r sel; do
            [[ ${sel%%[[:space:]]*} == $want ]] && { print -r -- "$sel"; break }
          done
      rm -f "$pick"
    }
    envf > "$outf" 2>/dev/null
    got=$(<"$outf")
    rm -f "$outf"
    if [[ $got == "$want = ${base[$want]}" ]]; then
      print -r -- "  OK   ${(l:24:: :)}$want ${#base[$want]} 字符逐字一致"
    else
      print -r -- "  *** 错误 $want：期望长度 $(( ${#want} + 3 + ${#base[$want]} ))，实际 ${#got}"
    fi
  done

  t_sep "取值层：值为空的环境变量（不能用「是否为空」判存在性）"
  export _ENVF_EMPTY_TEST_VAR=''
  outf=$ENVF_TMP/out.$$
  pick=$ENVF_TMP/pick.$$
  fzf() {
    cat > "$pick"
    sed "s/$ESC\\[[0-9;]*m//g" "$pick" 2>/dev/null \
      | while IFS= read -r sel; do
          [[ ${sel%%[[:space:]]*} == _ENVF_EMPTY_TEST_VAR ]] && { print -r -- "$sel"; break }
        done
    rm -f "$pick"
  }
  envf > "$outf" 2>/dev/null
  got=$(<"$outf")
  rm -f "$outf"
  if [[ $got == '_ENVF_EMPTY_TEST_VAR = ' ]]; then
    print -r -- "  OK   输出 [${got}]"
  else
    print -r -- "  *** 错误：实际 [${got}]"
  fi
  unset _ENVF_EMPTY_TEST_VAR
  rm -rf "$ENVF_TMP"
}

# 19. uvf 的列表解析
#     uv 的 `tool list` / `tool list --outdated` 都不接受 --format json，
#     manage 与 outdated 两个视图的行全靠解析文本，所以这是 uvf 里唯一值得
#     钉住的行为：顶层行与 `- exe` 行混在同一次输出里，方括号注解还会随
#     --show-* 变多（见 _uvf_list_outdated 的注释）。
#     桩掉 uv 而不是真调：没有 uv 的机器也得能跑这条用例。
#
# 断言相等就把实际值一起打出来（它会进基线，逐字节可比）；不等打实际与期望。
# tab 显示成 -> ，免得基线里混进裸制表符。
t_uvf_expect() {      # $1=实际 $2=期望 $3=说明
  local got=${1//$'\t'/->} want=${2//$'\t'/->}
  if [[ $1 == "$2" ]]; then
    print -r -- "  OK   $3: [$got]"
  else
    print -r -- "  *** 错误 $3: 实际 [$got] 期望 [$want]"
  fi
}

t_case_uvf_rows() {
  local got want
  # 桩：$UV_STUB 的每一行就是 uv 打印的一行。UV_STUB 为空时 ${(f)UV_STUB}
  # 仍给出一个空元素，桩会打一个空行；解析端按「不足两段」丢掉它，
  # 所以「空工具目录」这一格的期望值仍然是空。
  functions[uv_orig]=$functions[uv]
  uv() { print -rl -- ${(f)UV_STUB} }

  t_sep "manage：顶层行取名与版本，- 开头的可执行文件行丢掉"
  UV_STUB=$'browser-use v0.13.10\n- browser\n- bu\nwatchdog v6.0.0\n- watchmedo'
  got=$(_uvf_list_installed)
  want=$'browser-use\t0.13.10\nwatchdog\t6.0.0'
  t_uvf_expect "$got" "$want" '两个工具'

  t_sep "manage：空工具目录（uv 打的是 No tools installed，走 stderr）"
  UV_STUB=''
  got=$(_uvf_list_installed)
  t_uvf_expect "$got" '' '无输出'

  t_sep "manage：只有可执行文件名的行不算工具（名字里没有版本）"
  UV_STUB=$'- watchmedo'
  got=$(_uvf_list_installed)
  t_uvf_expect "$got" '' '无输出'

  t_sep "outdated：拆出 name/当前/=>/最新 四列"
  UV_STUB=$'ruff v0.2.0 [latest: 0.16.9]\n- ruff'
  got=$(_uvf_list_outdated)
  want=$'ruff\t0.2.0\t=>\t0.16.9'
  t_uvf_expect "$got" "$want" '单个工具'

  t_sep "outdated：其余方括号注解与路径必须先截掉，不能混进版本号"
  # 这一行同时带 [required:] [CPython] [latest:] 与结尾的 env 路径 ——
  # 截断若发生在摘 [latest:] 之前，版本列会变成 "0.1.0] [required: ==0.1.0]..."
  UV_STUB=$'ruff v0.1.0 [required: ==0.1.0] [CPython 3.14.7] [latest: 0.16.9] (/tmp/t/ruff)'
  got=$(_uvf_list_outdated)
  want=$'ruff\t0.1.0\t=>\t0.16.9'
  t_uvf_expect "$got" "$want" '注解与路径都被截掉'

  t_sep "outdated：已是最新时 uv 一行都不给（视图应为空）"
  UV_STUB=''
  got=$(_uvf_list_outdated)
  t_uvf_expect "$got" '' '无输出'

  functions[uv]=$functions[uv_orig]
  unset 'uv_orig'
}

# 21. 配色层：角色名解析、颜色开关、_fc_sgr_strip
#
# 回归点 1：角色名写错必须**降级并告警**。查表不能靠判空 —— 'name' 在调色板里
#   的值就是空串（明确不上色），和拼错的名字一样查不到值。所以 _fc_sgr_prefix 用
#   [[ -v _FC_SGR[$s] ]] 查。这里断言拼错的名字仍会被发现，否则它会静默
#   变成不上色，而配色错在哪个 view 上极难看出来。
# 回归点 2：关色输出必须与「开色再剥色」逐字节相同。这条同时钉住了
#   「色码不进对齐计算」—— _fc_render 是先补齐后上色，任何一边动了
#   都会在这里露出来（历史上那三行的起始列就因为剥色正则无效而整体偏 9）。
# 回归点 3：_fc_sgr_strip 认的是 SGR 本身，不是当前配色。fzf-other.zsh 的
#   _other_value 原来掐的是固定的首尾两段（绑定当时的配色），而 fzf --ansi
#   已经先剥过一次，所以配色一换它就失效且不报错。断言里特意用调色板里
#   没有的颜色（品红）做剥离 —— 用「当前用到的颜色」测是测不出来的。
t_case_palette() {
  local out p spec role i escf
  local -a colored plain stripped

  t_sep "角色名 -> SGR 前缀"
  for spec in name have sep want msg 0 - ''; do
    _fc_sgr_prefix "$spec"
    p=$_FC_SGR_PREFIX
    print -r -- "  ${(qq)spec} -> ${(qq)p}"
  done

  t_sep "数字 spec 仍认（旧的 cols 声明走这条兼容路）"
  for spec in 34 33 1\;32; do
    _fc_sgr_prefix "$spec"
    p=$_FC_SGR_PREFIX
    print -r -- "  ${(qq)spec} -> ${(qq)p}"
  done

  t_sep "未知角色名：降级为不上色 + 只告警一次"
  escf=$(mktemp)
  _FC_SGR_WARNED=0
  _fc_sgr_prefix nope 2>"$escf"
  p=$_FC_SGR_PREFIX
  print -r -- "  前缀=[${(qq)p}]（应为空串，即不上色）"
  print -r -- "  告警: $(<"$escf")"
  # 第二次必须安静。_fc_sgr_prefix 走输出变量而不是 print，正是为了这个标志
  # 能在当前 shell 里存活 —— 走命令替换的话赋值落在子 shell，每次都重吵一遍。
  _fc_sgr_prefix alsowrong 2>"$escf"
  p=$_FC_SGR_PREFIX
  print -r -- "  再错一次: [$(<"$escf")]（应为空，一次 session 只吵一次）"
  rm -f "$escf"
  _FC_SGR_WARNED=0

  t_sep "颜色开关：关色时零转义，且与「开色再剥色」逐字节相同"
  _FC_REG+=('pal:manage:cols' 'name have sep want')
  _FC_ROWS=("alpha	1.0	=>	2.0"
             "much-longer-name	22	=>	22")
  colored=("${(@f)$(_fc_render pal manage)}")
  _FC_COLOR=0
  plain=("${(@f)$(_fc_render pal manage)}")
  _FC_COLOR=1
  print -r -- "  开色 ${#colored} 行 / 关色 ${#plain} 行"
  if [[ ${(j: :)plain} == *$'\e'* ]]; then
    print -r -- '  *** 错误：关色后仍有转义序列 ***'
  else
    print -r -- '  OK 关色输出不含 ESC'
  fi
  stripped=()
  local same=1
  for (( i = 1; i <= ${#colored}; i++ )); do
    stripped[i]=$(_fc_sgr_strip "$colored[i]")
    # 逐行比而不是把数组 join 后一次比：join 的分隔符是 flag 的字面量参数，
    # ${(j: :.)arr} 里的 $'\n' 不求值（和本项目里那一串 flag 陷阱同源），
    # 而且逐行比还能指出是哪一行开始不一致。
    if [[ ${stripped[i]} != ${plain[i]:-} ]]; then
      same=0
      print -r -- "  *** 第 $i 行不一致 ***"
    fi
  done
  (( ${#colored} == ${#plain} )) || same=0
  if (( same )); then
    print -r -- '  OK 剥色后的开色输出 == 关色输出'
  else
    print -r -- '  *** 错误：颜色影响了行内容（多半是色码混进了对齐计算） ***'
  fi
  unset '_FC_REG[pal:manage:cols]'

  t_sep "_fc_sgr_strip：认 SGR 本身，与用哪套配色无关"
  # ${(ok)_FC_SGR}：o = 按键排序。不排的话关联数组的遍历顺序不保证，
  # 基线就会随机漂 —— 这类不稳定输出绝不能进基线。
  for role in ${(ok)_FC_SGR}; do
    p=$(_fc_sgr_paint "$role" 'X')
    out=$(_fc_sgr_strip "$p")
    if [[ $out == X ]]; then
      print -r -- "  ${(qq)role} ${(qq)p}X -> OK"
    else
      print -r -- "  ${(qq)role} -> *** 错误：剥完还剩 [${(qq)out}] ***"
    fi
  done
  # 调色板里没有的颜色、多参数 SGR、24 位真彩：都不该影响剥离。
  for spec in $'\e[35m' $'\e[1;32m' $'\e[38;2;255;128;0m'; do
    out=$(_fc_sgr_strip "${spec}X${_FC_SGR_RESET}")
    if [[ $out == X ]]; then
      print -r -- "  ${(qq)spec} -> OK"
    else
      print -r -- "  ${(qq)spec} -> *** 错误：剥完还剩 [${(qq)out}] ***"
    fi
  done
  out=$(_fc_sgr_strip $'a\tb\e[34mc\e[0md')
  print -r -- "  混在中间: [${(qq)out}]（应为含一个真 tab）"
}

# 20. README 与代码一致
#     README 曾经把不存在的 `uvf`、不存在的 `registry` view 写进去，
#     漏掉 pinned / gemf / envf，依赖表也只提了 grep coreutils 和 gh jq。
#     文档漂移不会让任何东西坏掉，所以不会有人发现 —— 除了专门查它的时候。
#     cargof / ffp 已移除、fp 已改名为 pathf，本用例的清单必须跟着变，
#     否则它会把「文档写了不存在的命令」当成正确。
#     uvf 是后来真加上的：清单里加了它，下面「不该出现的名字」那段对 uvf 的
#     断言也随之删除 —— 那条断言的来由是它当时确实不存在。
t_case_readme() {
  local R=$root/README.md
  if [[ ! -f $R ]]; then
    print -r -- '  (没有 README.md，跳过)'
    return 0
  fi

  t_sep "公开命令：README 必须逐个收录，且不多不少"
  local -a want
  want=(brewf npmf pnpmf pipf uvf gemf ghf pathf envf)
  local c
  for c in "${want[@]}"; do
    if grep -qF -- "\`$c\`" "$R"; then
      print -r -- "  OK   收录了 $c"
    else
      print -r -- "  *** 错误：README 没收录 $c"
    fi
  done
  # 反向：README 提到的命令名必须真的存在。
  # 排除 fzf —— 它是项目名也是依赖名，不是本插件定义的命令。
  local -a defined
  defined=(${(f)"$(grep -hoE '^[a-z][a-z0-9]*\(\)' "$root"/base.zsh "$root"/collections/*.zsh \
             | tr -d '()' | sort)"})
  for c in ${(f)"$(grep -oE '`[a-z]+f`' "$R" | tr -d '`' | sort -u)"}; do
    [[ $c == fzf ]] && continue
    (( ${defined[(Ie)$c]} )) || print -r -- "  *** 错误：README 提到 $c，但代码里没有这个函数"
  done

  t_sep "view 列表：README 必须覆盖注册表里的全部 view，且不写多余的"
  local eco v line miss extra
  for eco in brew npm pnpm pip uv gem gh; do
    local -a vs
    vs=(${(s: :)${_FC_REG[$eco:views]}})
    (( ${#vs} )) || continue
    line=$(grep -m1 "^\`${eco}f\`:" "$R")
    if [[ -z $line ]]; then
      print -r -- "  *** 错误：README 缺 ${eco}f 的命令行"
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
      print -r -- "  *** 错误 ${eco}f 漏了 view:$miss"
    elif [[ -n $extra ]]; then
      print -r -- "  *** 错误 ${eco}f 写了不存在的 view:$extra"
    else
      print -r -- "  OK   ${eco}f: ${(j: :)vs}"
    fi
  done

  t_sep "不该出现的名字"
  # 这里原来还断言 README 不得提到 uvf / fzf-uv —— 当初成立是因为 uvf 真的
  # 不存在。uvf 加进来之后那两条前提就没了，而「README 提到的命令必须真的
  # 存在」在上面那段反向检查里已经逐个查过（grep '`[a-z]+f`' 对 defined），
  # 所以这里不必再维护一份手工名单。
  if grep -qF '`registry`' "$R"; then
    print -r -- '  *** 错误：README 提到 registry view，但注册表里没有'
  else
    print -r -- '  OK   不提 registry view'
  fi

  t_sep "默认模块列表"
  # 两边都归一成「空格分隔、无首尾空格」再比，
  # 否则尾随空格会伪装成不一致（踩过一次）。
  local real_mods readme_mods
  real_mods=$(print -l -- ${FZF_COLLECTION_MODULES} | tr '\n' ' ')
  readme_mods=$(sed -n '/^FZF_COLLECTION_MODULES=($/,/^  )$/p' "$R" \
                | sed '1d;$d' | tr -d ' ' | tr '\n' ' ')
  real_mods=${real_mods%% }
  readme_mods=${readme_mods%% }
  print -r -- "  代码:   [${real_mods}]"
  print -r -- "  README: [${readme_mods}]"
  if [[ $real_mods == $readme_mods ]]; then
    print -r -- '  OK   一致'
  else
    print -r -- '  *** 错误：默认模块列表不一致'
  fi

  t_sep "依赖：README 提到的必须真被调用，代码用到的必须被提到"
  # 白名单必须穷举外部命令。之前的白名单漏了 curl，于是 pipf 的 search
  # 靠 curl 抓 index 页面这件事两版依赖表都没写，也永远不会被这个检查抓到。
  # 宁可多列几个候选（命中后再判断是不是真调用），也不能漏。
  #
  # 用 grep -w 取词本身，不要用字符类切分 —— 那样会把 "brew:" 、"(find"
  # 这种带分隔符的碎片当成词，报出一堆假的「代码用了 X」。
  # head / tail 不单列：head 只跟 find 一起用；tail 在 gem 里是变量名。
  # cut 是流式 search 路径的一部分（见 _fc_view_streamable），sed 是 pipf 抠 index 页
  # 链接用的（87 万行，见 _pipf_list_available），两者都必须列进来。
  # uv 放在最后：它是 alternation 里最短的一个，放前面会把 uvtool 之类也切进来
  # （-w 挡得住大部分，但没必要依赖它）。
  local -a used
  used=(${(u)${(s: :)$(grep -hvE '^\s*#' "$root"/base.zsh "$root"/collections/*.zsh \
        | sed 's/[[:space:]]#.*$//' \
        | grep -howE 'all-the-package-names|pip-autoremove|brew|npm|pnpm|pip3?|gem|gh|jq|curl|find|git|grep|cut|sed|sort|uniq|printenv|less|open|dirname|uv' | tr 'A-Z' 'a-z' | sort -u)}})
  for c in "${used[@]}"; do
    # 必须在**依赖表**里，即以 "| `" 开头的表格行。
    # 之前只查「README 任意位置提过」，于是散文里顺口提一句就能蒙混过关 ——
    # 注入测试证明过：把 curl 从表格里删掉、留在散文里，检查照样通过。
    if grep -E '^\| ' "$R" | grep -qF "$c"; then
      :
    else
      print -r -- "  *** 错误：代码用了 $c，README 依赖表里没有"
    fi
  done
  print -r -- "  代码用到的 ${#used[@]} 个外部命令都已在依赖表中"
  # perl / column 已彻底移除，README 不得再声称需要
  for c in perl column; do
    n=$(grep -hvE '^\s*#' "$root"/base.zsh "$root"/collections/*.zsh | grep -cE "\b$c\b")
    if (( n == 0 )) && grep -qiE "install.*\b$c\b|\b$c\b.*install" "$R"; then
      print -r -- "  *** 错误：README 仍声称需要 $c，但代码已不再调用它"
    else
      print -r -- "  OK   $c 在代码中 $n 次调用，README 未声称需要"
    fi
  done

  t_sep "可配置项：代码里每个可覆盖的变量都必须在 README 里有，且名字一致"
  # 双向核对。以前只查 _ENVF_VALMAX 一个方向，_FC_COLUMN_GAP 就漏了。
  local -a tunable
  tunable=(${(u)${(s: :)$(grep -hoE '\$\{[A-Z_][A-Z0-9_]*:-' "$root"/base.zsh "$root"/collections/*.zsh \
          | sed 's/\${//;s/:-//')}})
  # PAGER 是通用环境变量，不算插件自己的可配置项
  tunable=(${tunable:#PAGER})
  local vname
  for vname in "${tunable[@]}"; do
    if grep -qF "$vname" "$R"; then
      print -r -- "  OK   $vname 有文档"
    else
      print -r -- "  *** 错误：代码可覆盖 $vname，README 没有"
    fi
  done
  print -r -- "  代码里可覆盖的插件变量共 ${#tunable[@]} 个：${(j: :)tunable}"

  t_sep "clone 地址必须指向本仓库，不能是上游"
  # 之前一直写的是上游 liuyinz 的地址，照抄会克隆错仓库。
  local remote
  remote=$(cd "$root" && git remote get-url origin 2>/dev/null)
  if [[ -z $remote ]]; then
    print -r -- '  (没有 origin remote，跳过)'
  else
    remote=${remote%.git}
    remote=${remote#https://}
    remote=${remote#git@}
    remote=${remote/:/\/}
    print -r -- "  origin = ${remote}"
    if grep -qF "https://${remote}" "$R"; then
      print -r -- '  OK   README 的 clone 地址与 origin 一致'
    else
      print -r -- '  *** 错误：README 的 clone 地址与 origin 不一致'
      grep -oE 'https://github.com/[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+' "$R" \
        | sort -u | sed 's/^/        README 里的: /'
    fi
  fi

  t_sep "jq：README 声称的用法必须与代码一致"
  # 事实：brew 不用 jq（只有注释里提到）；gem 完全不用；
  # gh 用的是 gh api --jq（内置，不需要外部二进制）；
  # npm / pnpm / pip 的 outdated 与 manage 需要外部 jq，search 反而不用。
  local eco2 fn2 f2 v2 row
  for eco2 in brew gem; do
    for v2 in ${(s: :)${_FC_REG[$eco2:views]}}; do
      fn2=${_FC_REG[$eco2:$v2]}
      [[ -z $fn2 ]] && continue
      f2=$(grep -l "^${fn2}()" "$root"/collections/*.zsh 2>/dev/null | head -1)
      [[ -z $f2 ]] && continue
      if sed -n "/^${fn2}()/,/^}/p" "$f2" | grep -vE '^\s*#' | grep -qE '\| jq -r'; then
        print -r -- "  *** 错误：$eco2/$v2 用了外部 jq，README 声称 $eco2 不需要"
      fi
    done
    print -r -- "  OK   $eco2 的 view 数据源确实不用外部 jq"
  done
  # 反向：npm / pnpm / pip 的 outdated 真的用 jq，README 必须列出 jq
  for eco2 in npm pnpm pip; do
    fn2=${_FC_REG[$eco2:outdated]}
    f2=$(grep -l "^${fn2}()" "$root"/collections/*.zsh 2>/dev/null | head -1)
    if [[ -z $f2 ]] || ! sed -n "/^${fn2}()/,/^}/p" "$f2" | grep -vE '^\s*#' | grep -qE '\| jq -r'; then
      print -r -- "  *** 错误：$eco2 的 outdated 不再需要 jq，README 却列着"
      continue
    fi
    # README 的依赖表里 $eco2f 那一行必须含 jq。
    # npmf 与 pnpmf 合并成一行（`| `npmf`, `pnpmf` | ...`），所以不能只匹配行首。
    row=$(grep -F "\`${eco2}f\`" "$R" | grep '^|' | head -1)
    if [[ -n $row ]] && print -r -- "$row" | grep -q 'jq'; then
      print -r -- "  OK   $eco2 的 outdated 用 jq，README 也列了"
    else
      print -r -- "  *** 错误：$eco2 的 outdated 用 jq，但 README 依赖表没列"
      print -r -- "        找到的行: ${row:-（无）}"
    fi
  done

  t_sep "FZF_COLLECTION_OPTS 必须与 _FC_OPTS 逐项一致"
  local inreadme inopts
  inreadme=$(sed -n '/^  FZF_COLLECTION_OPTS="/,/"/p' "$R" | grep -oE '^\s+--[a-z-]+' | tr -d ' ' | sort)
  inopts=$(print -l -- ${_FC_OPTS} | grep -oE '^--[a-z-]+' | sort)
  if [[ $inreadme == $inopts ]]; then
    print -r -- '  OK   一致'
  else
    print -r -- '  *** 错误：与代码里的 _FC_OPTS 不一致'
    print -r -- "      README:  ${(j: :)inreadme}"
    print -r -- "      _FC_OPTS: ${(j: :)inopts}"
  fi
}

# =============================================================================
# 用例隔离
#
# 为什么需要这一层：t_case_read 里有 `_FC_OPTS=()`（为了让退出码测试不受用户
# opts 干扰）和 `header="Test"`，两处都没有恢复。于是从它之后的所有用例都在
# 空 opts 下运行，t_case_readme 的 FZF_COLLECTION_OPTS 一致性门拿到一个空数组、
# 打出「*** 错误」—— 而 baseline 把那段错误录成了预期输出。那道门从落地起就在
# 报错，而基线「记录现状」的机制不可能发现这一点。
#
# 逐个用例快照再恢复，比「记得在用例里清理」可靠：漏掉的不是一次污染，而是
# 下一个门的假失败，而假失败往往在几屏之外才被看见。
# **新增插件全局时必须在这里加一行。**
# =============================================================================

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
  _T_ACTIONS=("${_FC_ACTIONS[@]}")
  _T_MUTATING=("${_FC_MUTATING[@]}")
  _T_PICKED=("${_FC_PICKED[@]}")
  _T_DONE=("${_FC_DONE[@]}")
  _T_FAILED=("${_FC_FAILED[@]}")
  _T_PENDING=$_FC_PENDING
  _T_RC=$_FC_RC
  _T_COLOR=$_FC_COLOR
  _T_SGR_WARNED=$_FC_SGR_WARNED
  _T_SGR_PREFIX=$_FC_SGR_PREFIX
  _T_HEADER=$header
  # 整个注册表一起存：逐个 fixture 键登记的话，漏掉一个键就是漏掉一次污染。
  # 代价是每个用例复制一次几百个键，可以接受。
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
  header=$_T_HEADER
  _FC_REG=("${(@kv)_T_REG}")
}

t_run_all() {
  local c
  # 用例清单是数据：加一个用例只加一行，不必记得包 snapshot/restore。
  # 以前这里是 25 个直接调用，加用例的人很容易只加调用不加工具。
  local -a cases
  cases=(
    t_case_rule
    t_case_format
    t_case_read
    t_case_msg
    t_case_split_row
    t_case_loop
    t_case_render
    t_case_drop_row
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
    t_case_readme
  )
  for c in "${cases[@]}"; do
    _t_snapshot
    $c
    _t_restore
  done
  printf '\n### END\n'
}
