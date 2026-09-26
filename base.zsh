#!/usr/bin/env zsh
# 上面这行是文件元数据（供编辑器与格式化工具识别），不是解释器指令。
# 本文件是库文件，由 fzf-collection.plugin.zsh 以 source 方式加载。
# 它仅含函数定义、无顶层入口，即使赋予执行权限直接运行也只会是空操作，
# 且缺少 base.zsh 的依赖必然失败。文件模式保持 100644，不要 chmod +x。

# FZF_COLLECTION_OPTS 是一个字符串，要按空白切成数组再传给 fzf。
# ${=var} 是 zsh 的强制分词 flag（默认不分词）。
# 原来写的是 _fzf_opts=($(echo "$FZF_COLLECTION_OPTS}")) —— 结果相同，
# 但为了分词而 fork 一次 echo，插件每次加载都白付这个代价。
_fzf_opts=(${=FZF_COLLECTION_OPTS})

_fzf_exist() {
  command -v "$@" &>/dev/null
}

# $1=消息 $2=标签（是谁触发的，通常是包名）
#
# 标签必须显式传。原来这里回退到 $caller —— 那是旧驱动的自由变量，
# 旧驱动删掉之后没有任何地方再给它赋值，于是单参调用会打出一个空标签
# （"Rollback cancel.: "）。
_fzf_msg() {
  printf "\n\x1b[34m%s\x1b[0m: %s\n" "${2:-fzf-collection}" "$1"
}

_fzf_pager() {
  local pager
  pager="${PAGER:-less}"
  if [ "$pager" = "less" ] && _fzf_exist less; then
    less -R
  elif _fzf_exist "$pager"; then
    $pager
  else
    cat
  fi
}

# SEE https://stackoverflow.com/a/68093509/13194984
_fzf_underline() {
  printf -- '%s\n' "$1"
  printf -- '▔%.0s' {1..$#1}
}

_fzf_homepage() {
  if [ -n "$1" ]; then
    echo "Open: $1 ..."
    open "$1"
  else
    echo "No homepage."
  fi
}

# 首字段原样，其余字段合并后染蓝，再按首字段宽度对齐。
#
# 原来这里有 manage / pinned / outdated / general 四个分支，每个分支一条 perl
# printf 规则（$rule 里用 perl 的 @F 与 %.15s）。迁移后包管理器全部走
# _pkg_display，format 只剩 general 还被 pathf / envf 使用，另外三个分支无法到达，
# 所以删掉了。现在没有任何 perl 也没有 column。
#
# general 的语义（对照过 column -t 的输出）：
#   - 按空白切，首字段之外的整段（含中间的空格）合并成一个字段
#   - 首字段补齐到本批最大宽度，间隔 2 个空格
_fzf_format() {          # $format 由调用方设为 general
  local line first rest
  local -a lines out
  if [[ $format != general ]]; then
    print -r -- "Error: No such format: $format"
    return 0
  fi
  # 末行没有换行时 read 返回非零但仍填了变量，所以要补一次判断
  while IFS= read -r line || [[ -n $line ]]; do lines+=("$line"); done
  # 输入里只有空行时什么都不输出。旧实现是 `input="$(cat)"` 再 `[ -n "$input" ]`，
  # 命令替换会剥掉尾部换行，所以纯空行输入的 input 是空串。
  local any=0
  for line in "${lines[@]}"; do
    [[ -n ${line//[[:space:]]/} ]] && { any=1; break; }
  done
  (( any )) || return 0
  for line in "${lines[@]}"; do
    while [[ $line == [[:space:]]* ]]; do line=${line#?}; done
    first=${line%%[[:space:]]*}
    rest=${line#"$first"}
    # 首字段之外的部分要按空白重新拼接：旧规则是 perl 的 join(" ", @F[1 .. $#F])，
    # 它把字段间的制表符、连续空格一律压成单个空格。直接取原 remainder 会把
    # 制表符原样带进显示里。
    rest=${rest//[[:space:]]/ }
    while [[ $rest == *"  "* ]]; do rest=${rest//  / }; done
    while [[ $rest == ' '* ]]; do rest=${rest# }; done
    while [[ $rest == *' ' ]]; do rest=${rest% }; done
    out+=("$first$_FZF_SEP$_FZF_BLUE$rest$_FZF_RESET")
  done
  print -rl -- "${out[@]}" | _fzf_align "$_FZF_SEP"
}

# ${s//, /$'\n'} 里的 $'\n' 不会被求值（替换位和 flag 参数一样是字面量），
# 会原样输出这四个字符，所以换行只能走变量。必须在文件顶层声明 ——
# 循环体内的标量 local 会往 stdout 打一行赋值，混进候选列表。
typeset -g _FZF_NL=$'\n'
# _fzf_format 的字段分隔符。与空白区分开才能传给 _fzf_align ——
# 空白模式下它是「按空白切、剥前导空白」，指定分隔符时不是。
typeset -g _FZF_SEP='^^'
# 颜色转义序列。$'\e[34m' 写在双引号里不会被求值（和 $'\n' 同一个陷阱），
# 只会得到字面的 `$'\e[34m'` 七个字符，所以必须先落到变量里。
typeset -g _FZF_BLUE=$'\e[34m'
typeset -g _FZF_RESET=$'\e[0m'

# 按分隔符对齐成表格，逐字节复刻 `column -t`：
#   丢掉空行 -> 切列 -> 每列补齐到本列最大宽度 -> 列间 2 个空格 -> 末列不补
#
# $1 可选分隔符。给了就按它切（复刻 `column -s X -t`），没给就按空白切
# （复刻 `column -s ' ' -t`）。两种模式的差别都在 _fzf_split 里。
#
# 四个容易漏掉的细节：
#   - column 把连续分隔符当一个，且**空字段整个丢掉**（不占宽度也不占间隔），
#     所以列号是按「剩下的字段」数的
#   - 空白模式下 column 会剥每行前导空白、折叠连续空格；指定分隔符时不会
#   - 制表符在空白模式下**不算**分隔符（因为 -s ' ' 只认字面空格）
#   - 行尾空白会被去掉，所以「a 」输出成「a」
#
# 已知限制：column 按显示宽度算，zsh 的 ${#} 按字符数，含宽字符时对齐会偏。
# 目前的调用方是 crates.io 依赖表与 pathf / envf 的列表，字段都是 ASCII。
_fzf_align() {          # $1=可选分隔符
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
      # 分隔符是变量时 ${(s:$delim)var} 不展开（flag 参数是字面量），
      # 所以先替换成换行再按行切。给 $delim 加引号是为了不让它当 glob。
      keep=("${(@f)${line//"$delim"/$_FZF_NL}}")
    else
      keep=("${(@s: :)line}")
    fi
    # column 把空字段整个丢掉：不占宽度也不占间隔，列号按剩下的字段数
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
      keep=("${(@f)${line//"$delim"/$_FZF_NL}}")
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

# =============================================================================
# 驱动层
#
# 7 个包管理器的 collection 全部走这里。相对重构前的写法：
#   - 列表是结构化行 name<TAB>f2<TAB>...
#   - 列表默认整轮 session 只查询一次，缓存在 _PKG_ROWS，动作后从内存删行
#   - 例外：单列且没有可达 mutating 动作的视图走流式，见 _pkg_streamable
#   - 不写 /tmp 临时文件，不靠 funcstack 递归重入
#   - 显示名由注册表提供，不再从函数名反推
#   - 函数派发用 "$fn" 间接展开（zsh 的 nameref 不能派发函数，见计划 2.3）
#
# 上面保留的 _fzf_* 是两个独立命令 pathf / envf 用的（collections/fzf-other.zsh），
# 它们不是包管理器，没有 view / action 的概念，因此没有并入注册表。
# =============================================================================

# -g 是刻意的：若本文件被从函数里 source，普通 typeset 会把 PKG 变成局部变量，
# 函数返回后下标 ${PKG[eco:view]} 会被当成算术下标求值，
# 报出 "bad math expression: ':' without '?'" 这种完全无法定位的错误。
typeset -gA PKG         # 注册表：PKG[<eco>[:<view>]][:<field>] = value
typeset -ga _PKG_ROWS    # 当前 session 的列表，由 _pkg_session 独占
typeset -ga _PKG_FIELDS # _pkg_split_tabs 的输出
typeset -gi _PKG_STREAM # 1 = 当前 view 走流式路径（_pkg_feed 用），见 _pkg_streamable

# 注册表类型自检。关联数组被误重建为普通数组时给出明确诊断，
# 而不是让下标里的 ':' 被当成三元运算符。
_pkg_ready() {
  if [[ ${(t)PKG} != association ]]; then
    print -ru2 "fzf-collection: 注册表 PKG 类型错误（当前: ${(t)PKG:-未定义}）"
    print -ru2 "  请重新加载插件；若自定义了 .zshrc 请检查是否有同名变量 PKG"
    return 1
  fi
  return 0
}

# 注册表读取。key 必须在变量里拼好再用于下标。
#
# 绝对不要写 ${PKG[$eco:title]} —— zsh 会把 ':' 后的首字母当成参数修饰符：
#   :h head  :t tail  :r root  :e extension  :s suffix  :l lower  :u upper
# 于是 $eco:title 里的 ':t' 被解释成 tail，返回空字符串且没有任何报错。
# 受影响的字段名（本项目全部踩过）：title / loop / runner / homepage /
# rollback / search / tap。views / info / install 只是恰好没撞上。
_pkg_get() {
  local key=$1 part
  shift
  for part in "$@"; do key="${key}:${part}"; done
  [[ -n ${PKG[$key]:-} ]] && print -r -- "${PKG[$key]}"
}

# 读 view 级字段：PKG[<eco>:<view>:<field>]。
#
# 单独拆一个函数，是因为 key 的分段顺序只有一处能写对。注册表约定是
# eco:view:field，而 _pkg_get 是「eco 后面接什么就是什么」，于是
# _pkg_get eco actions view 会拼出 eco:actions:view —— 读不到任何东西，
# 而且**不报错**，只是静默返回空。动作清单一空，回车就没有子菜单可弹，
# 表现为「选中了却什么都没发生」。所以顺序必须封在这个函数的参数里。
_pkg_view_get() {           # $1=eco $2=view $3=field
  local key=$1
  key="${key}:${2}:${3}"
  [[ -n ${PKG[$key]:-} ]] && print -r -- "${PKG[$key]}"
}

# fzf 读取。退出码透传，调用方靠它区分「选中」与「取消」（旧驱动的 B11）。
# --tabstop=1：本驱动的行约定是「tab = 列分隔符，渲染成恰好 1 个空格」，
# 列对齐由 _pkg_display 补空格完成，不交给 tab stop。
_pkg_read() {
  fzf "${_fzf_opts[@]}" --tabstop=1 --header "$(_fzf_underline "$header")" "$@"
}

# 按 tab 切分一行。不能用 ${(ps:\t:)var} —— flag 参数不接受 $'\t'（见计划 2.3）。
_pkg_split_tabs() {        # $1=line -> _PKG_FIELDS
  local rest=$1
  _PKG_FIELDS=()
  while :; do
    case $rest in
      *$'\t'*) _PKG_FIELDS+=("${rest%%$'\t'*}"); rest=${rest#*$'\t'} ;;
      *)       _PKG_FIELDS+=("$rest"); break ;;
    esac
  done
}

# 展示层：把 _PKG_ROWS（干净的 name<TAB>f2<TAB>... ）渲染成对齐且逐列着色的 fzf 行。
#
# 列数与配色由注册表 <eco>:<view>:cols 给出，每列一个 ANSI 颜色码，0 = 不着色：
#   '0,34,0,33'   ->  name | 蓝 | 无 | 黄      即 outdated 的四列双色
#   '0,34'        ->  name | 蓝                即 manage 的两列
#   '0'           ->  单列                     即 search
# 未声明 cols 时按单列处理。
#
# 每列各自补齐到本列最大宽度，末列不补（避免尾随空白）。
# 输出的行结构是  name<TAB><补齐><TAB>f2<TAB>f3...
# 补齐单独占一个 tab 段，因此 ${line%%$'\t'*} 取到的 name 天然干净。
# 配合 --tabstop=1（tab 渲染成 1 个空格）得到旧版 column -t 的对齐效果。
_pkg_display() {           # $1=eco $2=view
  local eco=$1 view=$2
  local line cell seg out k first
  local -a cols widths flds segs
  local i nf n
  # 所有 local 都必须写在函数开头，绝不能写进循环体。
  # 回归点：zsh 5.9 在循环体内执行标量 local 时，会往 stdout 打一行
  # `NAME=<上一轮的值>`（含 ESC 的值显示成 $'\C-...'）。本函数的 stdout
  # 直接喂给 fzf，那一行会变成一条假候选（曾经表现为列表里出现 k=6）。
  # 写对位置的话 _pkg_display 输出的每一行都以包名开头。
  local -i csep=${_PKG_COLSEP:-5}

  n=${#_PKG_ROWS}
  (( n )) || return 0

  cols=(${(s:,:)$(_pkg_view_get "$eco" "$view" cols)})
  nf=$#cols
  (( nf )) || { cols=(0); nf=1 }

  widths=()
  for (( i = 1; i <= nf; i++ )); do widths[i]=0; done
  # 单列时 widths 一次都用不到（补齐只发生在 i < nf 的分支里，而单列没有那种分支），
  # 所以整个预扫描可以跳过：它要再把全表过一遍，4 万行就是 3~4s 白花。
  if (( nf > 1 )); then
    for line in "${_PKG_ROWS[@]}"; do
      _pkg_split_tabs "$line"
      flds=("${_PKG_FIELDS[@]}")
      for (( i = 1; i <= nf; i++ )); do
        cell=${flds[i]:-}
        (( ${#cell} > widths[i] )) && widths[i]=${#cell}
      done
    done
  fi

  for line in "${_PKG_ROWS[@]}"; do
    _pkg_split_tabs "$line"
    flds=("${_PKG_FIELDS[@]}")
    segs=()
    for (( i = 1; i <= nf; i++ )); do
      cell=${flds[i]:-}
      if (( i == 1 )); then
        # name 保持原样，补齐另起一个 tab 段，取名因此无需剥空格。
        # 单列（search 之类）后面没有别的列，补齐段只会给每行留下尾部
        # tab 和空白 —— 既难看，又会让 fzf 的匹配把尾部空白算进去。
        segs+=("$cell")
        (( nf > 1 )) && segs+=("${(l:$(( widths[1] - ${#cell} )):: :)}")
      else
        (( i < nf )) && cell="${(r:$widths[i]:: :)cell}"
        if [[ ${cols[i]} == 0 ]]; then
          segs+=("$cell")
        else
          segs+=($'\e['"${cols[i]}m${cell}"$'\e[0m')
        fi
      fi
    done
    # 字段之间用 COLSEP 个 tab 分隔，配合 --tabstop=1 渲染成同样多个空格。
    # 默认 5：比单个空格宽，列间更易读。设 _PKG_COLSEP 可调整。
    #
    # tab 必须用 $'\t' 手工拼接。${(j:\t:)segs} 不行 —— flag 的参数是字面量，
    # '\t' 不会被解释成转义，会原样输出两个字符；变量也不行，
    # ${(j:$sep:)...} 同样不展开。
    #
    # 必须写 "${segs[@]}"。未加引号的数组展开会丢弃空元素 ——
    # 而补齐段在最长的那行恰好是空的，于是那一行少一个 tab、整行左移。
    #
    # csep/k/first 在函数开头声明，原因见上。first 每行都要重置，
    # 必须是普通赋值而不是 local —— 循环体内的 local 会污染 stdout。
    first=1
    out=""
    for seg in "${segs[@]}"; do
      if (( ! first )); then
        for (( k = 1; k <= csep; k++ )); do out+=$'\t'; done
      fi
      first=0
      out+="$seg"
    done
    # 末尾不加 tab。补齐段可能为空，会留下连续 tab —— 渲染成连续空格，
    # 正是需要的列间隔
    print -r -- "$out"
  done
}

# 收集查询结果。_PKG_ROWS 里是干净的 name<TAB>rest，不含颜色与对齐空格。
#
# 必须一次 slurp 完再按行切，不能用 while-read + arr+=()：
# zsh 的数组 append 每次都要重新分配整个数组，于是这一段是 O(n^2)。
# 实测 8 万行 172s、44 万行（取一半）45s，翻一倍就是 4 倍。
# npm / pnpm 的 search 有 448 万行（all-the-package-names），
# 照 while-read 写要一个多小时才把第一批候选交给 fzf —— 表现就是「一直不出候选」。
#
# ${(@f)$(cat)} 是一次 fork + 一次批量切分，80 万行 0.4s。
# 代价是整份列表会短暂以单个字符串的形式驻留；只有走缓冲路径的视图会到这里，
# 它们的行数都在几百到几千（outdated / manage / pinned / gem、pip 的 search）。
_pkg_read_rows() {
  local -a lines
  lines=("${(@f)$(cat)}")
  # 命令替换会吃掉尾部换行，按行切完末尾可能多出一个空元素。
  # ${(@)arr:#} 用空模式删掉所有空串，等价于原来的 [[ -z $line ]] && continue。
  _PKG_ROWS=("${(@)lines:#}")
}

# 该视图能不能走流式路径（不落 _PKG_ROWS，直接把查询结果管道给 fzf）。
#
# 两个条件都要满足：
#   1. cols 只声明一列。单列视图里 _pkg_display 的净效果就是「取首字段」——
#      首列原样输出、不补齐、不上色，于是整层可以退化成 cut -f1。
#   2. 视图的动作里没有一个是 mutating。没有 mutating 就没有删行，
#      _PKG_ROWS 也就没有存在理由。
#
# 满足时 _pkg_feed 的候选链是
#     _pkg_query | cut -f1 | grep -v '^$' | fzf
# 语义与缓冲路径一致（取首字段 + 丢空行），但 zsh 一行都不碰。
# npm / pnpm 的 search（448 万行）走的正是这条：all-the-package-names 本身 0.7s，
# cut + grep 加起来不到 0.2s，fzf 立刻开始出候选 —— 与重构前 _fzf_search 的
# `$available | fzf` 一样。重构后两个 search 视图都被判成不可流式，
# 于是掉进 O(n^2) 的缓冲路径，这就是「以前秒开、现在一直不出来」的原因。
#
# 代价：每次回到列表都要重查一次（0.7s）。旧驱动用 /tmp 缓存文件避开这一下，
# 那是本驱动刻意去掉的机制，这里不捡回来。
_pkg_streamable() {        # $1=eco $2=view -> 返回 0 表示可流式
  local eco=$1 view=$2 a m
  local -a acts muts cols
  acts=(${(s: :)$(_pkg_view_get "$eco" "$view" actions)})
  (( ${#acts} )) || acts=(${(s: :)$(_pkg_get "$eco" actions)})
  _pkg_view_mutating "$eco" "$view"
  muts=("${_PKG_MUTATING[@]}")
  for a in "${acts[@]}"; do
    for m in "${muts[@]}"; do
      [[ $a == "$m" ]] && return 1
    done
  done
  # cols 没声明时 _pkg_display 按单列处理，这里必须同样按单列算
  cols=(${(s:,:)$(_pkg_view_get "$eco" "$view" cols)})
  (( ${#cols} <= 1 )) || return 1
  return 0
}

# 送候选给 fzf，选中行写到 stdout。$1=eco $2=view，其余参数透传给 _pkg_read。
# 两条路径只在「候选从哪来」上不同，动作与子菜单逻辑完全共用。
_pkg_feed() {
  local eco=$1 view=$2
  shift 2
  if (( _PKG_STREAM )); then
    _pkg_query "$eco" "$view" | cut -f1 | grep -v '^$' | _pkg_read "$@"
  else
    # 列表被清空时（最后一轮 mutating 全删完）不能让 print 打出一个空行 ——
    # 那会变成一条空白候选，让用户能选中它。直接不发任何行，fzf 立刻退出，
    # 与 _pkg_display 在空表时 return 0 的效果一致。
    if (( ${#_PKG_ROWS} )); then
      print -rl -- "${_PKG_ROWS[@]}" | _pkg_display "$eco" "$view" | _pkg_read "$@"
    fi
  fi
}

# 调用注册表里登记的查询函数。缓冲路径整个 session 只调一次；
# 流式路径每次渲染列表都调一次（见 _pkg_streamable 的代价说明）。
_pkg_query() {
  local fn
  fn=$(_pkg_get "$1" "$2") || return 1
  "$fn"
}

# 精确删除匹配的行。不能用 ${(@)rows:#pat}：它按 glob 匹配整个元素，
# 而元素含 tab，且 flag 参数塞不进 $'\t'（计划 2.3）。
_pkg_drop() {
  local name=$1 line
  local -a keep
  for line in "${_PKG_ROWS[@]}"; do
    [[ ${line%%$'\t'*} == "$name" ]] || keep+=("$line")
  done
  _PKG_ROWS=("${keep[@]}")
}

# 动作派发完全由注册表决定，驱动里不出现任何具体动作名：
#   PKG[<eco>:<act>] 存在 -> 专用处理器，收一个包名参数
#                       （rollback / info / deps / homepage / use / ...）
#   否则               -> PKG[<eco>:runner] 原生透传，收 (act, 包名)
_pkg_act() {               # $1=eco $2=view $3=act $4=name
  local act=$3 fn
  fn=$(_pkg_get "$1" "$act")
  if [[ -n $fn ]]; then
    "$fn" "$4"
  else
    fn=$(_pkg_get "$1" runner) || return 1
    "$fn" "$act" "$4"
  fi
}

_pkg_view_actions() {      # $1=eco $2=view -> _PKG_ACTIONS（无动作则返回 1）
  local -a acts
  acts=(${(s: :)$(_pkg_view_get "$1" "$2" actions)})
  (( ! ${#acts} )) && acts=(${(s: :)$(_pkg_get "$1" actions)})
  (( ${#acts} )) || return 1
  _PKG_ACTIONS=("${acts[@]}")
}

_pkg_actions() {           # $1=eco $2=view
  _pkg_view_actions "$1" "$2" || return 1
  print -l -- "${_PKG_ACTIONS[@]}" | _pkg_read
}

# 会把行移出列表的动作。view 级覆盖优先，缺了才回退到 eco 级。
# 同样把解析拆出来，测试才能走真实路径而不是自己拼一遍 key。
_pkg_view_mutating() {     # $1=eco $2=view -> _PKG_MUTATING
  local -a m
  m=(${(s: :)$(_pkg_view_get "$1" "$2" mutating)})
  (( ! ${#m} )) && m=(${(s: :)$(_pkg_get "$1" mutating)})
  _PKG_MUTATING=("${m[@]}")
}

# 回滚到指定版本。versions 列表只在此处取一次，不随 session 缓存。
#
# 三个数据键刻意不叫 versions / current / install：_pkg_act 用 PKG[<eco>:<动作名>]
# 查专用处理函数，而 install 正是 search 视图的合法动作名。叫 install 的话，
# 用户选「install」会命中回滚用的安装器，而且只收到包名一个参数。
# 加 version- 前缀就不会和动作名相撞。
_pkg_rollback() {          # $1=eco $2=pkg
  local eco=$1 pkg=$2 versions old new fn
  fn=$(_pkg_get "$eco" version-list) || return 1
  versions=$("$fn" "$pkg")
  if [[ -z $versions ]]; then
    _fzf_msg "No versions." "$pkg" && return 0
  fi
  old=$("$(_pkg_get "$eco" version-current)" "$pkg")
  _fzf_msg "${old:-Not-installed}" "$pkg"
  new=$(print -l -- ${(f)versions} | _pkg_read)
  if [[ -z $new ]]; then
    _fzf_msg "Rollback cancel." "$pkg" && return 0
  fi
  [[ $new == "$old" ]] && { print -n $'\nREINSTALL THE SAME VERSION after 2 seconds\n'; sleep 2 }
  # 第 3 个参数是回滚前的版本。多数 ecosystem 用不到（直接装新版本即可），
  # 但 gem 需要先按旧版本定位安装目录并卸载，所以传过去。
  # 已有的 handler 只用 $1 $2，多传一个参数不影响。
  "$(_pkg_get "$eco" version-install)" "$pkg" "$new" "$old"
}

# 对选中的一批包执行一个动作。
#
# 回归点（B9）：旧驱动写成 `gem uninstall ... && _fzf_tmp_shift "$f"`，循环里
# 不看退出码 —— 一个包失败也继续跑完剩下的，而且失败的那个照样被移出列表，
# 于是它从屏幕上消失了，但系统里还在，再也找不到。用户只能重查一次才知道。
#
# $4=1 表示这是 mutating 动作，此时遇到失败立刻停止（返回 1）；
# 只读动作传 0 —— 失败不停止，因为只读动作没有改变任何状态，
# 中止没有意义，「失败」也往往只是「没有结果」（例如 brew uses 查不到依赖）。
#
# 结果放进 _PKG_DONE / _PKG_FAILED，由 _pkg_session 决定要不要删行。
_pkg_apply() {           # $1=eco $2=view $3=act $4=mutating?
  local eco=$1 view=$2 act=$3 strict=$4 p name
  _PKG_DONE=()
  _PKG_FAILED=()
  _PKG_RC=0
  for p in "${(@f)_PKG_PICKED}"; do
    # ${p%%$'\t'*} 取到的就是干净 name —— _pkg_display 把对齐填充放在
    # 第一个 tab 之后，所以这里不需要额外剥空格
    name=${p%%$'\t'*}
    if _pkg_act "$eco" "$view" "$act" "$name"; then
      _PKG_DONE+=("$name")
      print
    else
      # 退出码必须第一个取：下面追加数组就会清掉 $?
      _PKG_RC=$?
      _PKG_FAILED+=("$name")
      (( strict )) && return 1
    fi
  done
  return 0
}

# 动作失败后的汇总。写清楚哪一项失败、后面的没做、成功几项，
# 这样用户知道列表里剩下的东西是什么状态。
_pkg_report() {          # $1=act
  print -r -- ""
  # 130 = 128 + SIGINT。下载 formulae 时 Ctrl-C 是很常见的操作，
  # 说成「失败」会让用户以为包坏了，而实际上什么都没变。
  if (( _PKG_RC == 130 )); then
    print -r -- "  ${_PKG_FAILED[1]}: 动作 '$1' 被 Ctrl-C 中断，已停止"
  else
    print -r -- "  ${_PKG_FAILED[1]}: 动作 '$1' 失败（退出码 $_PKG_RC），已停止"
  fi
  (( ${#_PKG_DONE} )) && print -r -- "  已完成 ${#_PKG_DONE} 项并移出列表"
  print -r -- "  其余 ${_PKG_PENDING} 项未执行，仍在列表里"
}

# view 循环：缓冲路径整轮 session 只查询一次，动作后从内存删行，不重查、不落盘；
# 流式路径（_pkg_streamable）每次回到列表重查，但从不把列表读进 zsh。
_pkg_session() {           # $1=eco $2=view
  local eco=$1 view=$2 sel act p
  local -i strict
  local -a picked mutating loop opt
  typeset -ga _PKG_PICKED _PKG_DONE _PKG_FAILED
  typeset -gi _PKG_PENDING _PKG_RC _PKG_STREAM

  header=$(_pkg_view_get "$eco" "$view" title)
  [[ -n $header ]] || header=$(_pkg_get "$eco" title)
  _pkg_view_mutating "$eco" "$view"
  mutating=("${_PKG_MUTATING[@]}")
  loop=(${(s: :)$(_pkg_get "$eco" loop)})
  opt=(${(s: :)$(_pkg_view_get "$eco" "$view" opt)})

  _PKG_STREAM=0
  if _pkg_streamable "$eco" "$view"; then
    _PKG_STREAM=1
    # 清掉上一个 view 可能留下的行。流式路径不读它，但 _PKG_ROWS 是全局的，
    # 留着上一批数据只会让人误以为本视图也缓冲过。
    _PKG_ROWS=()
  else
    _pkg_query "$eco" "$view" | _pkg_read_rows
    if (( ! ${#_PKG_ROWS} )); then
      _fzf_msg "Nothing to show." "$header" && return 0
    fi
  fi

  while :; do
    # 必须把列表管道给 fzf。漏掉这一步 fzf 会去读终端，
    # 把用户输入当成候选列表（表现为列出了完全无关的内容）。
    sel=$(_pkg_feed "$eco" "$view" --multi $opt) || break
    [[ -n $sel ]] || break
    # 必须用 ${(f)sel} 或 "${(@f)sel}"。写成 ${(f)"$sel"}（带引号的展开配 (f) flag）
    # 是非法语法，且只在运行时才报 bad substitution —— zsh -n 检查不出来。
    picked=("${(@f)sel}")
    (( ${#picked} )) || continue
    _PKG_PICKED=("${picked[@]}")

    # 内层：动作菜单。非 mutating 且在 loop 列表中的动作会留在原地，
    # 沿用旧驱动「同一选择可连续执行多个只读动作」的行为。
    while :; do
      act=$(_pkg_actions "$eco" "$view") || break
      [[ -n $act ]] || break

      strict=0
      (( ${mutating[(Ie)$act]} )) && strict=1

      if _pkg_apply "$eco" "$view" "$act" "$strict"; then
        # 全部成功
        if (( strict )); then
          for p in "${_PKG_DONE[@]}"; do _pkg_drop "$p"; done
          break
        fi
        (( ${loop[(Ie)$act]} )) || break
        continue
      fi

      # 只有 mutating 动作会走到这里。成功的那几个已经生效，必须移出列表，
      # 否则用户会以为它们还在；失败项与未执行项保持原样，可直接重试。
      for p in "${_PKG_DONE[@]}"; do _pkg_drop "$p"; done
      _PKG_PENDING=$(( ${#_PKG_PICKED} - ${#_PKG_DONE} - ${#_PKG_FAILED} ))
      _pkg_report "$act"
      break
    done
  done
}

_pkg_cmd() {               # $1=eco
  local eco=$1 v
  local -a views
  _pkg_ready || return 1
  views=(${(s: :)$(_pkg_get "$eco" views)})
  (( ${#views} )) || return 1
  header=$(_pkg_get "$eco" title)
  while :; do
    v=$(print -l -- $views | _pkg_read) || return 0
    [[ -n $v ]] || return 0
    _pkg_session "$eco" "$v" || return 0
  done
}
