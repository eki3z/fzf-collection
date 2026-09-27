#!/usr/bin/env zsh
# 上面这行是文件元数据（供编辑器与格式化工具识别），不是解释器指令。
# 本文件是库文件，由 fzf-collection.plugin.zsh 以 source 方式加载。
# 它仅含函数定义、无顶层入口，即使赋予执行权限直接运行也只会是空操作，
# 且缺少 base.zsh 的依赖必然失败。文件模式保持 100644，不要 chmod +x。

# FZF_COLLECTION_OPTS 是一个字符串，要按空白切成数组再传给 fzf。
# ${=var} 是 zsh 的强制分词 flag（默认不分词）。
# 原来写的是 _FC_OPTS=($(echo "$FZF_COLLECTION_OPTS}")) —— 结果相同，
# 但为了分词而 fork 一次 echo，插件每次加载都白付这个代价。
# -ga 是显式的：以前靠一句没有声明的赋值碰巧建出数组，数组性是隐式的。
typeset -ga _FC_OPTS=(${=FZF_COLLECTION_OPTS})

_fc_have_cmd() {
  command -v "$@" &>/dev/null
}

# $1=消息 $2=标签（是谁触发的，通常是包名）
#
# 标签必须显式传。原来这里回退到 $caller —— 那是旧驱动的自由变量，
# 旧驱动删掉之后没有任何地方再给它赋值，于是单参调用会打出一个空标签
# （"Rollback cancel.: "）。
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

# =============================================================================
# 配色与 SGR
#
# CSI 序列只在这一段里出现。着色一律走 _fc_sgr_prefix，剥色走 _fc_sgr_strip ——
# 换配色时只改 _FC_SGR 一处。
# =============================================================================

# 分隔符。TAB 与换行都必须先落到变量：
#   - ${s//, /$'\n'} 里的 $'\n' 不会被求值（替换位和 flag 参数一样是字面量），
#     会原样输出这四个字符
#   - ${(ps:\t:)x} 的 flag 参数同样不接受 $'\t'
# 而且必须在文件顶层声明：循环体内的标量 local 会让 zsh 5.9 往 stdout 打一行
# 赋值，那一行会变成一条假候选（曾经表现为 pnpmf 列表里混进 k=6）。
#
# 这里原来只有 _FC_NL，而 _B_TAB / _G_TAB / _G_NL / _PIP_NL / _UVF_TAB 分散在
# 四个 collection 里各声明一份 —— 同一个常量四种前缀，同一段说明复制四遍，
# 而读者永远不会同时打开四个文件。现在 collection 里一个全局都不剩。
typeset -g _FC_TAB=$'\t'
typeset -g _FC_NL=$'\n'
# 这里原来还有 _FC_SEP，是 _fzf_format 与 _fzf_align 之间的通道：格式层用
# 它把「首字段」和「合并后的其余字段」隔开，再交给对齐层按它切列。现在这两个
# 函数都搬进了 collections/fzf-other.zsh，通道变成同文件内的一次函数调用，
# 于是分隔符退回成 _other_format 的 local，全局少一个。

# 调色板：角色名 -> SGR 前缀。
#
# 用角色名而不是颜色名，是为了让注册表里的 cols 自解释：'name have sep want'
# 一眼看出四列各是什么，而 '0,34,0,33' 只能靠 base.zsh 里的注释解释。
# 反过来，换主题只改这张表，14 处 cols 声明一个字都不用动。
#
# 值为空串 = **明确不着色**，不是「没配」。所以解析器必须用 [[ -v ]] 查表，
# 靠取值判空的话，拼错的名字会和 name 一样静默降级 —— 查表是唯一的分界。
typeset -gA _FC_SGR=(
  name ''          # 包名 / 首字段
  have $'\e[34m'   # 已装版本、说明文字
  sep  ''          # '=>' 之类的连接符
  want $'\e[33m'   # 目标版本
  msg  $'\e[34m'   # _fc_msg 的标签
)
# 角色名写错只告警一次，且告警排在颜色开关之前 —— 配置错了即便当前不上色
# 也该说出来。告警去重靠这个标志**在当前 shell 里被赋值**，所以下面的
# _fc_sgr_prefix 必须走输出变量而不是命令替换：命令替换跑在子 shell 里，
# 赋的值出不来，于是每次渲染都会重吵一遍。
typeset -gi _FC_SGR_WARNED=0
# _fc_sgr_prefix 的输出。同 _fc_split_row -> _FC_FIELDS、_fc_reg_view_mutating ->
# _FC_MUTATING 的约定：结果落在全局变量里，函数不 print，也不 fork。
typeset -g _FC_SGR_PREFIX=''

# 颜色转义序列。$'\e[34m' 写在双引号里不会被求值（和 $'\n' 同一个陷阱），
# 只会得到字面的 `$'\e[34m'` 七个字符，所以必须先落到变量里。
# 这里只有 RESET：原先还有个 _FZF_BLUE，着色改走调色板后它已无人引用，
# 留着还会在换色后变成一个撒谎的名字（角色 have 改成青色，它就跟着变青）。
typeset -g _FC_SGR_RESET=$'\e[0m'

# 解析一个配色 spec，结果写进 _FC_SGR_PREFIX（空串 = 不着色）。
#
# 用输出变量而不是 print + $(...)：命令替换在子 shell 里跑，_FC_SGR_WARNED
# 的赋值出不来，去重就失效了；而这里每个 view 每次渲染都要问一次颜色，
# 走命令替换还白白 fork 一次。约定与 _FC_FIELDS / _FC_MUTATING 一致。
#
# spec 有三种写法：
#   空 / 0 / -            不着色
#   数字与分号（34、1;32）  原样当 SGR 参数
#   其余                  查 _FC_SGR 的角色名
#
# 数字那条是为兼容旧的 cols 声明（'0,34,0,33'）留的，两种写法都认。
_fc_sgr_prefix() {            # $1=spec
  local s=$1
  _FC_SGR_PREFIX=''
  if [[ -z $s || $s == 0 || $s == - ]]; then
    return 0
  elif [[ $s == *[!0-9\;]* ]]; then
    # 查表前先挡掉含 ']' 的输入：[[ -v _FC_SGR[$s] ]] 里 zsh 会把括号里的内容
    # 当下标表达式求值，而 spec 是注册表字符串里的数据，不能假定它老实。
    if [[ $s == *[^a-z0-9_-]* ]] || [[ ! -v _FC_SGR[$s] ]]; then
      if (( ! _FC_SGR_WARNED )); then
        _FC_SGR_WARNED=1
        print -ru2 -- "fzf-collection: 未知配色角色 '${s}'，按不上色处理"
      fi
      return 0
    fi
    s=${_FC_SGR[$s]}
    [[ -n $s ]] || return 0
  else
    # $'\e[' 与参数之间不能加引号以外的任何东西，也不能写成 "$'\e['" ——
    # 和上面同一个陷阱：双引号里 $'…' 不求值。
    s=$'\e['${s}'m'
  fi
  # 角色合法性先判、开关后判：配置写错时即便颜色关着也要报。
  (( _FC_COLOR )) || return 0
  _FC_SGR_PREFIX=$s
}

# 上色后原样输出文本。
#
# 只在入口层用（_fc_msg 这类一整个命令调一次的地方）。**不要**拿它逐格调用：
# 命令替换每格一次 fork，2 万行 × 4 列实测 51s，而直接拼接是 0.3s。
# 逐行或逐列的场景用「循环外解析一次前缀，循环内纯拼接」，见 _other_format
# 与 _fc_render。
_fc_sgr_paint() {             # $1=spec $2=text
  local p
  _fc_sgr_prefix "$1"
  p=$_FC_SGR_PREFIX
  [[ -n $p ]] || { print -r -- "$2"; return 0 }
  print -r -- "$p$2$_FC_SGR_RESET"
}

# 剥掉一行里全部的 SGR 序列。
#
# 必须开 extendedglob。${1//$'\e'\[[0-9;]#m/} 在 zsh 5.9 下**不匹配** ——
# flag 位置上的 [ 被当成 bracket expression（fzf-other.zsh 的旧注释记过这件事）。
# 而 ${1//$'\e'\[[0-9;]*m/} 过度匹配：* 贪婪，会把整行吃到最后一个 m。
# 两种都实测过，别改回去。
_fc_sgr_strip() {           # $1=行
  setopt localoptions extendedglob
  print -r -- "${1//$'\e'\[[0-9;]#m/}"
}

# =============================================================================
# 驱动层
#
# 7 个包管理器的 collection 全部走这里。相对重构前的写法：
#   - 列表是结构化行 name<TAB>f2<TAB>...
#   - 列表默认整轮 session 只查询一次，缓存在 _FC_ROWS，动作后从内存删行
#   - 例外：单列且没有可达 mutating 动作的视图走流式，见 _fc_view_streamable
#   - 不写 /tmp 临时文件，不靠 funcstack 递归重入
#   - 显示名由注册表提供，不再从函数名反推
#   - 函数派发用 "$fn" 间接展开（zsh 的 nameref 不能派发函数，见计划 2.3）
#
# 上面保留的 _fzf_* 是两个独立命令 pathf / envf 用的（collections/fzf-other.zsh），
# 它们不是包管理器，没有 view / action 的概念，因此没有并入注册表。
# =============================================================================

# -g 是刻意的：若本文件被从函数里 source，普通 typeset 会把 _FC_REG 变成局部变量，
# 函数返回后下标 ${_FC_REG[eco:view]} 会被当成算术下标求值，
# 报出 "bad math expression: ':' without '?'" 这种完全无法定位的错误。
#
# 全仓库**只有这一处**声明 _FC_REG。原先每个 collection 里还有一行
# `[[ ${(t)PKG} == association ]] || typeset -gA PKG`，七份同样的守卫，
# 理由是「万一用户 .zshrc 里有个同名的 PKG」。改名成 _FC_REG 之后这个理由
# 不成立了，而「单独 source 一个 collection」本来就不是支持的用法 ——
# 每个文件的头部都写着它由 fzf-collection.plugin.zsh 加载。
# 同理删除的还有 _pkg_ready()：它的唯一职责就是诊断上面那个抢名字的情况。
typeset -gA _FC_REG         # 注册表：_FC_REG[<eco>[:<view>]][:<field>] = value
typeset -ga _FC_ROWS    # 当前 session 的列表，由 _fc_session 独占
typeset -ga _FC_FIELDS # _fc_split_row 的输出
typeset -gi _FC_STREAM # 1 = 当前 view 走流式路径（_fc_feed 用），见 _fc_view_streamable

# 当前画面的标题，由 _fc_cmd / _fc_session 设，_fc_fzf_read 读。
#
# 它是全局而不是参数，而且**请不要再把它改成参数**：这一层之下要读标题的
# 有三处 —— 动作子菜单、rollback 的版本选择器、view 菜单 —— 它们各自距
# _fc_session 两三层调用，而中间还夹着动作派发：_fc_apply -> _fc_act ->
# handler。把标题穿过去意味着 5 个签名各自多一个参数、并且多数 handler 并不
# 关心它。它是货真价实的 session 状态，_FC_ROWS 也是。
#
# 它以前叫 `header`，不带前缀，于是覆盖了用户 .zshrc 里的同名变量，跑完还
# 留一个脏值在全局。现在这个名字属于插件，撞不掉了。
typeset -g _FC_HEADER=''

# 注册表读取。key 必须在变量里拼好再用于下标。
#
# 绝对不要写 ${_FC_REG[$eco:title]} —— zsh 会把 ':' 后的首字母当成参数修饰符：
#   :h head  :t tail  :r root  :e extension  :s suffix  :l lower  :u upper
# 于是 $eco:title 里的 ':t' 被解释成 tail，返回空字符串且没有任何报错。
# 受影响的字段名（本项目全部踩过）：title / loop / runner / homepage /
# rollback / search / tap。views / info / install 只是恰好没撞上。
_fc_reg_get() {
  local key=$1 part
  shift
  for part in "$@"; do key="${key}:${part}"; done
  [[ -n ${_FC_REG[$key]:-} ]] && print -r -- "${_FC_REG[$key]}"
}

# 读 view 级字段：_FC_REG[<eco>:<view>:<field>]。
#
# 单独拆一个函数，是因为 key 的分段顺序只有一处能写对。注册表约定是
# eco:view:field，而 _fc_reg_get 是「eco 后面接什么就是什么」，于是
# _fc_reg_get eco actions view 会拼出 eco:actions:view —— 读不到任何东西，
# 而且**不报错**，只是静默返回空。动作清单一空，回车就没有子菜单可弹，
# 表现为「选中了却什么都没发生」。所以顺序必须封在这个函数的参数里。
_fc_reg_view_get() {           # $1=eco $2=view $3=field
  local key=$1
  key="${key}:${2}:${3}"
  [[ -n ${_FC_REG[$key]:-} ]] && print -r -- "${_FC_REG[$key]}"
}

# fzf 读取。全仓库唯一调用 fzf 的地方。退出码透传，调用方靠它区分
# 「选中」与「取消」（旧驱动的 B11）。
#
# 三个选项在这里、且只能在这里给：
#   --tabstop=1  本驱动的行约定是「tab = 列分隔符，渲染成恰好 1 个空格」，
#                列对齐由 _fc_render 补空格完成，不交给 tab stop
#   --ansi       候选行里带 SGR 序列（调色板着色的那一层）。不给的话 fzf
#                把 \e[34m 当 5 个普通字符：既不上色，还把这 5+4 个字节算进
#                显示宽度，于是长行被提前截断
#   --header     从 _FC_HEADER 取，见那里为什么是全局
#
# 以前 pathf / envf 绕过这个函数直接调 fzf，自己带一份 --ansi 和 --header。
# 那意味着「必须带 --ansi」这条约束有两处实现，而 tests 里那道检查是
# grep 源码里 `| fzf "` 的行数 —— 删掉那两处直接调用，grep 数到 0，0 == 0，
# 门就通过了。现在统一到这里。
_fc_fzf_read() {
  fzf "${_FC_OPTS[@]}" --tabstop=1 --ansi \
    --header "$(_fc_rule "$_FC_HEADER")" "$@"
}

# 按 tab 切分一行。不能用 ${(ps:\t:)var} —— flag 参数不接受 $'\t'（见计划 2.3）。
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

# 展示层：把 _FC_ROWS（干净的 name<TAB>f2<TAB>... ）渲染成对齐且逐列着色的 fzf 行。
#
# 列数与配色由注册表 <eco>:<view>:cols 给出，**空格分隔**，每列一个 spec。
# spec 是调色板里的角色名（见 _FC_SGR），值写错了由 _fc_sgr_prefix 降级并告警：
#   'name have sep want'  name | 蓝 | 无 | 黄   即 outdated 的四列双色
#   'name have'           name | 蓝             即 manage 的两列
#   'name'                单列                   即 search
# 未声明 cols 时按单列处理。
# 数字写法（'0,34,0,33'）仍然认，那是旧声明的兼容路径，见 _fc_sgr_prefix。
#
# 每列各自补齐到本列最大宽度，末列不补（避免尾随空白）。
# 输出的行结构是  name<TAB><补齐><TAB>f2<TAB>f3...
# 补齐单独占一个 tab 段，因此 ${line%%$'\t'*} 取到的 name 天然干净。
# 配合 --tabstop=1（tab 渲染成 1 个空格）得到旧版 column -t 的对齐效果。
_fc_render() {           # $1=eco $2=view
  local eco=$1 view=$2
  local line cell seg out k first
  local -a cols widths flds segs
  local -a pre post
  local i nf n
  # 所有 local 都必须写在函数开头，绝不能写进循环体。
  # 回归点：zsh 5.9 在循环体内执行标量 local 时，会往 stdout 打一行
  # `NAME=<上一轮的值>`（含 ESC 的值显示成 $'\C-...'）。本函数的 stdout
  # 直接喂给 fzf，那一行会变成一条假候选（曾经表现为列表里出现 k=6）。
  # 写对位置的话 _fc_render 输出的每一行都以包名开头。
  local -i csep=${_FC_COLUMN_GAP:-5}

  n=${#_FC_ROWS}
  (( n )) || return 0

  cols=(${(s: :)$(_fc_reg_view_get "$eco" "$view" cols)})
  nf=$#cols
  (( nf )) || { cols=(0); nf=1 }

  # 逐列的着色前后缀在这里一次解析好，循环内只做字符串拼接。
  #
  # 不能在循环里调 _fc_sgr_paint：命令替换每格一次 fork，2 万行 × 4 列实测 51s，
  # 而直接拼 $'\e['… 是 0.33s，预解析是 0.28s。这也是 _fc_sgr_paint 只许在入口层
  # 用的原因。
  #
  # 宽度的预扫描仍然在补齐之后、着色之前 —— 色码不进 ${#cell}，
  # 所以对齐与配色互不干扰。
  for (( i = 1; i <= nf; i++ )); do
    _fc_sgr_prefix "${cols[i]}"
    pre[i]=$_FC_SGR_PREFIX
    if [[ -n ${pre[i]} ]]; then post[i]=$_FC_SGR_RESET; else post[i]=''; fi
  done

  widths=()
  for (( i = 1; i <= nf; i++ )); do widths[i]=0; done
  # 单列时 widths 一次都用不到（补齐只发生在 i < nf 的分支里，而单列没有那种分支），
  # 所以整个预扫描可以跳过：它要再把全表过一遍，4 万行就是 3~4s 白花。
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
        # name 保持原样，补齐另起一个 tab 段，取名因此无需剥空格。
        # 单列（search 之类）后面没有别的列，补齐段只会给每行留下尾部
        # tab 和空白 —— 既难看，又会让 fzf 的匹配把尾部空白算进去。
        segs+=("$cell")
        (( nf > 1 )) && segs+=("${(l:$(( widths[1] - ${#cell} )):: :)}")
      else
        (( i < nf )) && cell="${(r:$widths[i]:: :)cell}"
        segs+=("$pre[i]$cell$post[i]")
      fi
    done
    # 字段之间用 COLSEP 个 tab 分隔，配合 --tabstop=1 渲染成同样多个空格。
    # 默认 5：比单个空格宽，列间更易读。设 _FC_COLUMN_GAP 可调整。
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

# 收集查询结果。_FC_ROWS 里是干净的 name<TAB>rest，不含颜色与对齐空格。
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
_fc_load_rows() {
  local -a lines
  lines=("${(@f)$(cat)}")
  # 命令替换会吃掉尾部换行，按行切完末尾可能多出一个空元素。
  # ${(@)arr:#} 用空模式删掉所有空串，等价于原来的 [[ -z $line ]] && continue。
  _FC_ROWS=("${(@)lines:#}")
}

# 该视图能不能走流式路径（不落 _FC_ROWS，直接把查询结果管道给 fzf）。
#
# 两个条件都要满足：
#   1. cols 只声明一列。单列视图里 _fc_render 的净效果就是「取首字段」——
#      首列原样输出、不补齐、不上色，于是整层可以退化成 cut -f1。
#   2. 视图的动作里没有一个是 mutating。没有 mutating 就没有删行，
#      _FC_ROWS 也就没有存在理由。
#
# 满足时 _fc_feed 的候选链是
#     _fc_reg_query | cut -f1 | grep -v '^$' | fzf
# 语义与缓冲路径一致（取首字段 + 丢空行），但 zsh 一行都不碰。
# npm / pnpm 的 search（448 万行）走的正是这条：all-the-package-names 本身 0.7s，
# cut + grep 加起来不到 0.2s，fzf 立刻开始出候选 —— 与重构前 _fzf_search 的
# `$available | fzf` 一样。重构后两个 search 视图都被判成不可流式，
# 于是掉进 O(n^2) 的缓冲路径，这就是「以前秒开、现在一直不出来」的原因。
#
# 代价：每次回到列表都要重查一次（0.7s）。旧驱动用 /tmp 缓存文件避开这一下，
# 那是本驱动刻意去掉的机制，这里不捡回来。
_fc_view_streamable() {        # $1=eco $2=view -> 返回 0 表示可流式
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
  # cols 没声明时 _fc_render 按单列处理，这里必须同样按单列算
  cols=(${(s: :)$(_fc_reg_view_get "$eco" "$view" cols)})
  (( ${#cols} <= 1 )) || return 1
  return 0
}

# 送候选给 fzf，选中行写到 stdout。$1=eco $2=view，其余参数透传给 _fc_fzf_read。
# 两条路径只在「候选从哪来」上不同，动作与子菜单逻辑完全共用。
_fc_feed() {
  local eco=$1 view=$2
  shift 2
  if (( _FC_STREAM )); then
    _fc_reg_query "$eco" "$view" | cut -f1 | grep -v '^$' | _fc_fzf_read "$@"
  else
    # 列表被清空时（最后一轮 mutating 全删完）不能让 print 打出一个空行 ——
    # 那会变成一条空白候选，让用户能选中它。直接不发任何行，fzf 立刻退出，
    # 与 _fc_render 在空表时 return 0 的效果一致。
    if (( ${#_FC_ROWS} )); then
      print -rl -- "${_FC_ROWS[@]}" | _fc_render "$eco" "$view" | _fc_fzf_read "$@"
    fi
  fi
}

# 调用注册表里登记的查询函数。缓冲路径整个 session 只调一次；
# 流式路径每次渲染列表都调一次（见 _fc_view_streamable 的代价说明）。
_fc_reg_query() {
  local fn
  fn=$(_fc_reg_get "$1" "$2") || return 1
  "$fn"
}

# 精确删除匹配的行。不能用 ${(@)rows:#pat}：它按 glob 匹配整个元素，
# 而元素含 tab，且 flag 参数塞不进 $'\t'（计划 2.3）。
_fc_drop_row() {
  local name=$1 line
  local -a keep
  for line in "${_FC_ROWS[@]}"; do
    [[ ${line%%$'\t'*} == "$name" ]] || keep+=("$line")
  done
  _FC_ROWS=("${keep[@]}")
}

# 动作派发完全由注册表决定，驱动里不出现任何具体动作名：
#   _FC_REG[<eco>:<act>] 存在 -> 专用处理器，收一个包名参数
#                       （rollback / info / deps / homepage / use / ...）
#   否则               -> _FC_REG[<eco>:runner] 原生透传，收 (act, 包名)
_fc_act() {               # $1=eco $2=view $3=act $4=name
  local act=$3 fn
  fn=$(_fc_reg_get "$1" "$act")
  if [[ -n $fn ]]; then
    "$fn" "$4"
  else
    fn=$(_fc_reg_get "$1" runner) || return 1
    "$fn" "$act" "$4"
  fi
}

_fc_reg_view_actions() {      # $1=eco $2=view -> _FC_ACTIONS（无动作则返回 1）
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

# 会把行移出列表的动作。view 级覆盖优先，缺了才回退到 eco 级。
# 同样把解析拆出来，测试才能走真实路径而不是自己拼一遍 key。
_fc_reg_view_mutating() {     # $1=eco $2=view -> _FC_MUTATING
  local -a m
  m=(${(s: :)$(_fc_reg_view_get "$1" "$2" mutating)})
  (( ! ${#m} )) && m=(${(s: :)$(_fc_reg_get "$1" mutating)})
  _FC_MUTATING=("${m[@]}")
}

# 回滚到指定版本。versions 列表只在此处取一次，不随 session 缓存。
#
# 三个数据键刻意不叫 versions / current / install：_fc_act 用 _FC_REG[<eco>:<动作名>]
# 查专用处理函数，而 install 正是 search 视图的合法动作名。叫 install 的话，
# 用户选「install」会命中回滚用的安装器，而且只收到包名一个参数。
# 加 version- 前缀就不会和动作名相撞。
_fc_rollback() {          # $1=eco $2=pkg
  local eco=$1 pkg=$2 versions old new fn
  fn=$(_fc_reg_get "$eco" version-list) || return 1
  versions=$("$fn" "$pkg")
  if [[ -z $versions ]]; then
    _fc_msg "No versions." "$pkg" && return 0
  fi
  old=$("$(_fc_reg_get "$eco" version-current)" "$pkg")
  _fc_msg "${old:-Not-installed}" "$pkg"
  new=$(print -l -- ${(f)versions} | _fc_fzf_read)
  if [[ -z $new ]]; then
    _fc_msg "Rollback cancel." "$pkg" && return 0
  fi
  [[ $new == "$old" ]] && { print -n $'\nREINSTALL THE SAME VERSION after 2 seconds\n'; sleep 2 }
  # 第 3 个参数是回滚前的版本。多数 ecosystem 用不到（直接装新版本即可），
  # 但 gem 需要先按旧版本定位安装目录并卸载，所以传过去。
  # 已有的 handler 只用 $1 $2，多传一个参数不影响。
  "$(_fc_reg_get "$eco" version-install)" "$pkg" "$new" "$old"
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
# 结果放进 _FC_DONE / _FC_FAILED，由 _fc_session 决定要不要删行。
_fc_apply() {           # $1=eco $2=view $3=act $4=mutating?
  local eco=$1 view=$2 act=$3 strict=$4 p name
  _FC_DONE=()
  _FC_FAILED=()
  _FC_RC=0
  for p in "${(@f)_FC_PICKED}"; do
    # ${p%%$'\t'*} 取到的就是干净 name —— _fc_render 把对齐填充放在
    # 第一个 tab 之后，所以这里不需要额外剥空格
    name=${p%%$'\t'*}
    if _fc_act "$eco" "$view" "$act" "$name"; then
      _FC_DONE+=("$name")
      print
    else
      # 退出码必须第一个取：下面追加数组就会清掉 $?
      _FC_RC=$?
      _FC_FAILED+=("$name")
      (( strict )) && return 1
    fi
  done
  return 0
}

# 动作失败后的汇总。写清楚哪一项失败、后面的没做、成功几项，
# 这样用户知道列表里剩下的东西是什么状态。
_fc_report() {          # $1=act
  print -r -- ""
  # 130 = 128 + SIGINT。下载 formulae 时 Ctrl-C 是很常见的操作，
  # 说成「失败」会让用户以为包坏了，而实际上什么都没变。
  if (( _FC_RC == 130 )); then
    print -r -- "  ${_FC_FAILED[1]}: 动作 '$1' 被 Ctrl-C 中断，已停止"
  else
    print -r -- "  ${_FC_FAILED[1]}: 动作 '$1' 失败（退出码 $_FC_RC），已停止"
  fi
  (( ${#_FC_DONE} )) && print -r -- "  已完成 ${#_FC_DONE} 项并移出列表"
  print -r -- "  其余 ${_FC_PENDING} 项未执行，仍在列表里"
}

# view 循环：缓冲路径整轮 session 只查询一次，动作后从内存删行，不重查、不落盘；
# 流式路径（_fc_view_streamable）每次回到列表重查，但从不把列表读进 zsh。
_fc_session() {           # $1=eco $2=view
  local eco=$1 view=$2 sel act p
  local -i strict
  local -a picked mutating loop opt
  typeset -ga _FC_PICKED _FC_DONE _FC_FAILED
  typeset -gi _FC_PENDING _FC_RC _FC_STREAM

  _FC_HEADER=$(_fc_reg_view_get "$eco" "$view" title)
  [[ -n $_FC_HEADER ]] || _FC_HEADER=$(_fc_reg_get "$eco" title)
  _fc_reg_view_mutating "$eco" "$view"
  mutating=("${_FC_MUTATING[@]}")
  loop=(${(s: :)$(_fc_reg_get "$eco" loop)})
  opt=(${(s: :)$(_fc_reg_view_get "$eco" "$view" opt)})

  _FC_STREAM=0
  if _fc_view_streamable "$eco" "$view"; then
    _FC_STREAM=1
    # 清掉上一个 view 可能留下的行。流式路径不读它，但 _FC_ROWS 是全局的，
    # 留着上一批数据只会让人误以为本视图也缓冲过。
    _FC_ROWS=()
  else
    _fc_reg_query "$eco" "$view" | _fc_load_rows
    if (( ! ${#_FC_ROWS} )); then
      _fc_msg "Nothing to show." "$_FC_HEADER" && return 0
    fi
  fi

  while :; do
    # 必须把列表管道给 fzf。漏掉这一步 fzf 会去读终端，
    # 把用户输入当成候选列表（表现为列出了完全无关的内容）。
    sel=$(_fc_feed "$eco" "$view" --multi $opt) || break
    [[ -n $sel ]] || break
    # 必须用 ${(f)sel} 或 "${(@f)sel}"。写成 ${(f)"$sel"}（带引号的展开配 (f) flag）
    # 是非法语法，且只在运行时才报 bad substitution —— zsh -n 检查不出来。
    picked=("${(@f)sel}")
    (( ${#picked} )) || continue
    _FC_PICKED=("${picked[@]}")

    # 内层：动作菜单。非 mutating 且在 loop 列表中的动作会留在原地，
    # 沿用旧驱动「同一选择可连续执行多个只读动作」的行为。
    while :; do
      act=$(_fc_actions "$eco" "$view") || break
      [[ -n $act ]] || break

      strict=0
      (( ${mutating[(Ie)$act]} )) && strict=1

      if _fc_apply "$eco" "$view" "$act" "$strict"; then
        # 全部成功
        if (( strict )); then
          for p in "${_FC_DONE[@]}"; do _fc_drop_row "$p"; done
          break
        fi
        (( ${loop[(Ie)$act]} )) || break
        continue
      fi

      # 只有 mutating 动作会走到这里。成功的那几个已经生效，必须移出列表，
      # 否则用户会以为它们还在；失败项与未执行项保持原样，可直接重试。
      for p in "${_FC_DONE[@]}"; do _fc_drop_row "$p"; done
      _FC_PENDING=$(( ${#_FC_PICKED} - ${#_FC_DONE} - ${#_FC_FAILED} ))
      _fc_report "$act"
      break
    done
  done
}

_fc_cmd() {               # $1=eco
  local eco=$1 v
  local -a views
  views=(${(s: :)$(_fc_reg_get "$eco" views)})
  (( ${#views} )) || return 1
  _FC_HEADER=$(_fc_reg_get "$eco" title)
  while :; do
    v=$(print -l -- $views | _fc_fzf_read) || return 0
    [[ -n $v ]] || return 0
    _fc_session "$eco" "$v" || return 0
  done
}
