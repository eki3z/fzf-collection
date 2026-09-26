#!/usr/bin/env zsh
# 上面这行是文件元数据（供编辑器与格式化工具识别），不是解释器指令。
# 本文件是库文件，由 fzf-collection.plugin.zsh 以 source 方式加载。
# 它仅含函数定义、无顶层入口，即使赋予执行权限直接运行也只会是空操作，
# 且缺少 base.zsh 的依赖必然失败。文件模式保持 100644，不要 chmod +x。

_fzf_opts=($(echo "${FZF_COLLECTION_OPTS}"))

_fzf_exist() {
  command -v "$@" &>/dev/null
}

_fzf_msg() {
  printf "\n\x1b[34m%s\x1b[0m: %s\n" ${2:-$caller} $1
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

_fzf_read() {
  fzf "${_fzf_opts[@]}" --header "$(_fzf_underline "$header")" "$@" \
    | perl -lane 'print $F[0]'
  return $pipestatus[1]
}

_fzf_homepage() {
  if [ -n "$1" ]; then
    echo "Open: $1 ..."
    open "$1"
  else
    echo "No homepage."
  fi
}

# SEE https://stackoverflow.com/a/23777065/13194984
_fzf_format() {
  local input rule

  input="$([[ -p /dev/stdin ]] && cat - || return)"

  case $format in
    manage | pinned)
      rule='printf "%s^^\x1b[34m%s\x1b[0m\n", $F[0], join(" ", @F[1 .. $#F])'
      ;;
    outdated)
      rule='printf "%s^^\x1b[34m%.15s\x1b[0m^^=>^^\x1b[33m%.15s\x1b[0m\n", $F[0], $F[1], join(" ", @F[2 .. $#F])'
      ;;
    general)
      rule='printf "%s^^\x1b[34m%s\x1b[0m\n", $F[0], join(" ", @F[1 .. $#F])'
      ;;
    *) echo "Error: No such format: $format" && return 0 ;;
  esac

  [ -n "$input" ] && echo "$input" | perl -ane "$rule" | column -s '^^' -t
}

# =============================================================================
# 驱动层
#
# 7 个包管理器的 collection 全部走这里。相对重构前的写法：
#   - 列表是结构化行 name<TAB>f2<TAB>...，整轮 session 只查询一次，缓存在 _PKG_ROWS
#   - 不写 /tmp 临时文件，不靠 funcstack 递归重入
#   - 显示名由注册表提供，不再从函数名反推
#   - 函数派发用 "$fn" 间接展开（zsh 的 nameref 不能派发函数，见计划 2.3）
#
# 上面保留的 _fzf_* 是三个独立命令 fp / ffp / envf 用的（collections/fzf-other.zsh），
# 它们不是包管理器，没有 view / action 的概念，因此没有并入注册表。
# =============================================================================

# -g 是刻意的：若本文件被从函数里 source，普通 typeset 会把 PKG 变成局部变量，
# 函数返回后下标 ${PKG[eco:view]} 会被当成算术下标求值，
# 报出 "bad math expression: ':' without '?'" 这种完全无法定位的错误。
typeset -gA PKG         # 注册表：PKG[<eco>[:<view>]][:<field>] = value
typeset -ga _PKG_ROWS    # 当前 session 的列表，由 _pkg_session 独占
typeset -ga _PKG_FIELDS # _pkg_split_tabs 的输出

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
  for line in "${_PKG_ROWS[@]}"; do
    _pkg_split_tabs "$line"
    flds=("${_PKG_FIELDS[@]}")
    for (( i = 1; i <= nf; i++ )); do
      cell=${flds[i]:-}
      (( ${#cell} > widths[i] )) && widths[i]=${#cell}
    done
  done

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
_pkg_read_rows() {
  local line
  _PKG_ROWS=()
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    _PKG_ROWS+=("$line")
  done
}

# 整个 session 仅此一次查询
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
    _fzf_msg "Rollback cancel." && return 0
  fi
  [[ $new == "$old" ]] && { print -n $'\nREINSTALL THE SAME VERSION after 2 seconds\n'; sleep 2 }
  # 第 3 个参数是回滚前的版本。多数 ecosystem 用不到（直接装新版本即可），
  # 但 gem 需要先按旧版本定位安装目录并卸载，所以传过去。
  # 已有的 handler 只用 $1 $2，多传一个参数不影响。
  "$(_pkg_get "$eco" version-install)" "$pkg" "$new" "$old"
}

# view 循环：整个 session 只查询一次，动作后从内存删行，不重查、不落盘。
_pkg_session() {           # $1=eco $2=view
  local eco=$1 view=$2 sel act p
  local -a picked mutating loop opt

  header=$(_pkg_view_get "$eco" "$view" title)
  [[ -n $header ]] || header=$(_pkg_get "$eco" title)
  _pkg_view_mutating "$eco" "$view"
  mutating=("${_PKG_MUTATING[@]}")
  loop=(${(s: :)$(_pkg_get "$eco" loop)})
  opt=(${(s: :)$(_pkg_view_get "$eco" "$view" opt)})

  _pkg_query "$eco" "$view" | _pkg_read_rows
  if (( ! ${#_PKG_ROWS} )); then
    _fzf_msg "Nothing to show." "$header" && return 0
  fi

  while :; do
    # 必须把列表管道给 fzf。漏掉这一步 fzf 会去读终端，
    # 把用户输入当成候选列表（表现为列出了完全无关的内容）。
    sel=$(_pkg_display "$eco" "$view" | _pkg_read --multi $opt) || break
    [[ -n $sel ]] || break
    # 必须用 ${(f)sel} 或 "${(@f)sel}"。写成 ${(f)"$sel"}（带引号的展开配 (f) flag）
    # 是非法语法，且只在运行时才报 bad substitution —— zsh -n 检查不出来。
    picked=("${(@f)sel}")
    (( ${#picked} )) || continue

    # 内层：动作菜单。非 mutating 且在 loop 列表中的动作会留在原地，
    # 沿用旧驱动「同一选择可连续执行多个只读动作」的行为。
    while :; do
      act=$(_pkg_actions "$eco" "$view") || break
      [[ -n $act ]] || break
      # ${p%%$'\t'*} 取到的就是干净 name —— _pkg_display 把对齐填充放在
      # 第一个 tab 之后，所以这里不需要额外剥空格
      for p in $picked; do
        _pkg_act "$eco" "$view" "$act" "${p%%$'\t'*}"
        print
      done
      if (( ${mutating[(Ie)$act]} )); then
        for p in $picked; do _pkg_drop "${p%%$'\t'*}"; done
        break
      fi
      (( ${loop[(Ie)$act]} )) || break
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
