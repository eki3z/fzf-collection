#!/usr/bin/env zsh
# 库文件，由 fzf-collection.plugin.zsh source 加载；无顶层入口，模式 100644。

# FZF_COLLECTION_OPTS 是字符串，按空白切成数组；${=var} 是 zsh 的强制分词 flag。
typeset -ga _FC_OPTS=(${=FZF_COLLECTION_OPTS})

_fc_have_cmd() {
  command -v "$@" &>/dev/null
}

# 剥掉前导空白，就地改写。$1 是变量名，不是值。
#
# 就地是因为 _other_format 逐行调用它，而返回值得用命令替换（pathf 有 4900 行）。
# eval 是因为 zsh 5.9 没有 nameref。
# localoptions 是因为 ${s##[[:space:]]#} 需要 extendedglob，没开时不报错、
# 只是静默地什么都不剥。
_fc_ltrim() {              # $1=变量名
  setopt localoptions extendedglob
  eval "$1=\${$1##[[:space:]]#}"
}

# $1=消息 $2=标签（是谁触发的，通常是包名）。标签必须显式传。
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

# 在标题下面画一条等长的 ▔ 线。SEE https://stackoverflow.com/a/68093509/13194984
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

# ---- 可覆盖项的默认值 ----
#
# 这三个是有文档的环境变量的默认值，调用点一律写 ${_ENV_VAR:-$_FC_...}。
# 环境变量是覆盖，不是必填。
#
#   _FC_ENVF_WIDTH      envf 的值显示多宽。80 给窄终端；PATH 一类动辄上千字符，
#                       宽终端要调大。
#   _FC_PYPI_INDEX      uvf search 抓名字的 index 页。走镜像的用户必须换，而它
#                       无法自动取：uv 没有子命令能打印它解析到的 index。
#   _FC_PYPI_JSON_BASE  PyPI JSON API 的根，给 list-versions / info / deps /
#                       homepage。**刻意不跟 _FC_PYPI_INDEX 走**：镜像的 JSON
#                       快照可能很旧（tuna 的 ruff 还停在 0.5.7，PyPI 已 0.16.9），
#                       而这四处要新元数据，否则 rollback 给出装不上的版本。
typeset -g _FC_ENVF_WIDTH=80
typeset -g _FC_PYPI_INDEX='https://pypi.org/simple'
typeset -g _FC_PYPI_JSON_BASE='https://pypi.org/pypi'

# ---- 配色与 SGR ----
#
# CSI 序列只出现在这一段。着色走 _fc_sgr_prefix，剥色走 _fc_sgr_strip，
# 换配色只改 _FC_SGR 一处。

# 分隔符。TAB 与换行都必须先落到变量：$'\n' 在替换位与 flag 参数里都是字面量，
# 不落变量就会原样输出那几个字符。必须在文件顶层声明：循环体内的标量 local 会让
# zsh 5.9 往 stdout 打一行赋值，变成一条假候选。
typeset -g _FC_TAB=$'\t'
typeset -g _FC_NL=$'\n'

# 调色板：角色名 -> SGR 前缀。用角色名而不是颜色名，cols 才是自解释的
# （'name have sep want'），换主题也只改这张表。
#
# 值为空串 = 明确不上色，不是「没配」。所以解析器必须用 [[ -v ]] 查表：
# 靠取值判空的话，拼错的名字会和 name 一样静默降级。
typeset -gA _FC_SGR=(
  name ''          # 包名 / 首字段
  have $'\e[34m'   # 已装版本、说明文字
  sep  ''          # '=>' 之类的连接符
  want $'\e[33m'   # 目标版本
  msg  $'\e[34m'   # _fc_msg 的标签
)
# 角色名写错只告警一次，告警排在颜色开关之前：配置错了即便不上色也该说。
# 去重靠这个标志在当前 shell 里被赋值，所以 _fc_sgr_prefix 必须走输出变量。
typeset -gi _FC_SGR_WARNED=0
# _fc_sgr_prefix 的输出。结果落在全局变量里，函数不 print，也不 fork。
typeset -g _FC_SGR_PREFIX=''

# $'\e[34m' 写在双引号里不求值（同 $'\n'），必须先落到变量里。
typeset -g _FC_SGR_RESET=$'\e[0m'

# 解析一个配色 spec（_FC_SGR 的键），结果写进 _FC_SGR_PREFIX，空串 = 不着色。
# 走输出变量而不是 print + $(...)：命令替换在子 shell 里跑，_FC_SGR_WARNED
# 的赋值出不来，去重就失效。
#
# spec 只接受角色名。上不上色是调色板的值，不是 spec 的写法。
_fc_sgr_prefix() {            # $1=spec
  local s=$1
  _FC_SGR_PREFIX=''
  [[ -n $s ]] || return 0
  # 先挡掉 ']'：[[ -v _FC_SGR[$s] ]] 里 zsh 会把括号里的内容当下标表达式求值，
  # 而 spec 是注册表里的数据。
  if [[ $s == *[^a-z0-9_-]* ]] || [[ ! -v _FC_SGR[$s] ]]; then
    if (( ! _FC_SGR_WARNED )); then
      _FC_SGR_WARNED=1
      print -ru2 -- "fzf-collection: 未知配色角色 '${s}'，按不上色处理"
    fi
    return 0
  fi
  s=${_FC_SGR[$s]}
  # 合法性先判、开关后判：配置写错时即便不上色也要报。
  (( _FC_COLOR )) || return 0
  _FC_SGR_PREFIX=$s
}

# 上色后原样输出文本。只在入口层用，**不要**逐格调用：命令替换每格一次 fork，
# 2 万行 × 4 列实测 51s，而直接拼接是 0.3s。逐行或逐列的场景用「循环外解析
# 一次前缀，循环内纯拼接」，见 _other_format 与 _fc_render。
_fc_sgr_paint() {             # $1=spec $2=text
  local p
  _fc_sgr_prefix "$1"
  p=$_FC_SGR_PREFIX
  [[ -n $p ]] || { print -r -- "$2"; return 0 }
  print -r -- "$p$2$_FC_SGR_RESET"
}

# 剥掉一行里全部的 SGR 序列。必须开 extendedglob：${1//$'\e'\[[0-9;]#m/} 在
# zsh 5.9 下不匹配（flag 位置上的 [ 被当成 bracket expression），而
# ${1//$'\e'\[[0-9;]*m/} 过度匹配，贪婪到把整行吃到最后一个 m。
_fc_sgr_strip() {           # $1=行
  setopt localoptions extendedglob
  print -r -- "${1//$'\e'\[[0-9;]#m/}"
}

# ---- 驱动层 ----
#
# 7 个包管理器的 collection 全部走这里：
#   - 列表是结构化行 name<TAB>f2<TAB>...
#   - 整轮 session 只查询一次，缓存在 _FC_ROWS，动作后从内存删行
#   - 例外：单列且没有 mutating 动作的视图走流式，见 _fc_view_streamable
#   - 不写 /tmp 临时文件
#   - 函数派发用 "$fn" 间接展开（zsh 的 nameref 不能派发函数）
#
# pathf 与 envf 不走这里：它们不是包管理器，没有 view / action 的概念。

# -g 是刻意的：本文件被从函数里 source 时，普通 typeset 会把 _FC_REG 变成局部
# 变量，函数返回后下标里的 ':' 会被当成算术求值，报 "bad math expression"。
#
# 全仓库只有这一处声明 _FC_REG：collection 假定由本文件的加载路径先声明过。
typeset -gA _FC_REG         # 注册表：_FC_REG[<eco>[:<view>]][:<field>] = value
typeset -ga _FC_ROWS    # 当前 session 的列表，由 _fc_session 独占
typeset -ga _FC_FIELDS # _fc_split_row 的输出
typeset -gi _FC_STREAM # 1 = 当前 view 走流式路径（_fc_feed 用），见 _fc_view_streamable

# 当前画面的标题，由 _fc_cmd / _fc_session 设，_fc_fzf_read 读。
#
# 全局而不是参数，**请不要再改成参数**：读标题的有三处（动作子菜单、rollback
# 的版本选择器、view 菜单），都隔着动作派发 _fc_apply -> _fc_act -> handler，
# 穿过去要让 5 个签名都多个参数，而多数 handler 并不关心它。
typeset -g _FC_HEADER=''

# 注册表读取。key 必须在变量里拼好再当下标：${_FC_REG[$eco:title]} 会让 zsh
# 把 ':t' 当成 tail 修饰符，静默返回空。踩过的是 title / stay / fallback /
# homepage / rollback / search / tap。
_fc_reg_get() {
  local key=$1 part
  shift
  for part in "$@"; do key="${key}:${part}"; done
  [[ -n ${_FC_REG[$key]:-} ]] && print -r -- "${_FC_REG[$key]}"
}

# 读 view 级字段 _FC_REG[<eco>:<view>:<field>]。单独拆一个函数是为了把分段
# 顺序封在一处：_fc_reg_get 是「eco 后面接什么就是什么」，用它读 view 字段会
# 拼出 eco:actions:view，静默返回空，回车就没有子菜单可弹。
_fc_reg_view_get() {           # $1=eco $2=view $3=field
  local key=$1
  key="${key}:${2}:${3}"
  [[ -n ${_FC_REG[$key]:-} ]] && print -r -- "${_FC_REG[$key]}"
}

# fzf 读取。全仓库唯一调用 fzf 的地方。退出码透传，调用方靠它区分选中与取消。
#
# 三个选项只能在这里给：
#   --tabstop=1  行约定是「tab = 列分隔符，渲染成恰好 1 个空格」，列对齐由
#                _fc_render 补空格完成，不交给 tab stop
#   --ansi       候选行带 SGR 序列。不给的话 fzf 把 \e[34m 当 5 个普通字符，
#                既不上色，还把这 5+4 个字节算进显示宽度，长行于是被提前截断
#   --header     取自 _FC_HEADER
_fc_fzf_read() {
  fzf "${_FC_OPTS[@]}" --tabstop=1 --ansi \
    --header "$(_fc_rule "$_FC_HEADER")" "$@"
}

# 按 tab 切分一行。不能用 ${(ps:\t:)var}：flag 参数不接受 $'\t'。
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

# 展示层：把 _FC_ROWS（干净的 name<TAB>f2<TAB>...）渲染成对齐且逐列着色的行。
#
# 列数与配色取自 <eco>:<view>:cols，空格分隔，每列一个角色名：
#   'name have sep want'   outdated 的四列
#   'name have'            manage 的两列
#   'name'                 单列，即 search
# 未声明 cols 时按单列处理。
#
# 每列补齐到本列最大宽度，末列不补（避免尾随空白）。补齐单独占一个 tab 段，
# 所以 ${line%%$'\t'*} 取到的 name 天然干净；配合 --tabstop=1 得到 column -t
# 的对齐效果。
_fc_render() {           # $1=eco $2=view
  local eco=$1 view=$2
  local line cell seg out k first w
  local -a cols widths flds segs
  local -a pre post
  local i nf n
  # 所有 local 都写在函数开头，绝不能写进循环体：zsh 5.9 在循环体内执行标量
  # local 会往 stdout 打一行 `NAME=<值>`，而本函数的 stdout 直接喂给 fzf，
  # 那一行会变成一条假候选。
  local -i csep=${_FC_COLUMN_GAP:-5}

  n=${#_FC_ROWS}
  (( n )) || return 0

  cols=(${(s: :)$(_fc_reg_view_get "$eco" "$view" cols)})
  nf=$#cols
  (( nf )) || { cols=(name); nf=1 }

  # 逐列的着色前后缀在这里一次解析好，循环内只做字符串拼接：每格调一次
  # _fc_sgr_paint 是每格一次 fork，实测 51s 对 0.28s。
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
        #
        # ${(l:N:: :)} 的值是空串，所以它不是「把某个值左对齐到 N」，
        # 而是**生成 N 个空格**，作为一个独立的 tab 段。两个地方在 nounset 下
        # 会失败，都是静默把整个列表变空：
        #   1. 算式不能直接写在 flag 参数里（${(l:$(( ... )):: :)}）
        #   2. 值不能省略 —— ${(l:$w:: :)} 后面什么都不给，zsh 当成引用了一个
        #      未定义的参数，报 "parameter not set"。要给 ${:-}。
        segs+=("$cell")
        if (( nf > 1 )); then
          w=$(( widths[1] - ${#cell} ))
          segs+=("${(l:$w:: :)${:-}}")
        fi
      else
        # 同理：宽度先落到变量，flag 参数里不写 $widths[i]
        if (( i < nf )); then
          w=$widths[i]
          cell="${(r:$w:: :)cell}"
        fi
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
    # 末尾不加 tab。补齐段为空时会留下连续 tab，渲染成连续空格，正是列间隔。
    print -r -- "$out"
  done
}

# 收集查询结果到 _FC_ROWS（干净的 name<TAB>rest，不含颜色与对齐空格）。
#
# 必须一次 slurp 再按行切：zsh 的 arr+=() 每次都重新分配整个数组，while-read
# 写就是 O(n^2)（实测 8 万行 172s）。${(@f)$(cat)} 是 80 万行 0.4s。代价是整份
# 列表短暂以单个字符串驻留，只有走缓冲路径的视图会到这里，行数都在几千量级。
_fc_load_rows() {
  local -a lines
  lines=("${(@f)$(cat)}")
  # 命令替换吃掉尾部换行，切完末尾可能多出一个空元素；${(@)arr:#} 删掉所有空串。
  _FC_ROWS=("${(@)lines:#}")
}

# 该视图能否走流式路径（不落 _FC_ROWS，直接把查询结果管道给 fzf）。两个条件：
#   1. cols 只声明一列。单列时 _fc_render 的净效果就是「取首字段」，整层可退化成
#      cut -f1。
#   2. 没有 mutating 动作 —— 没有删行，_FC_ROWS 就无存在理由。
#
# 满足时候选链是 _fc_reg_query | cut -f1 | grep -v '^$' | fzf，语义与缓冲路径
# 一致但 zsh 一行都不碰。代价是每次回到列表都要重查一次（0.7s）。
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
    # 列表被清空时不能打出一个空行：那会变成一条能选中的空白候选。
    if (( ${#_FC_ROWS} )); then
      print -rl -- "${_FC_ROWS[@]}" | _fc_render "$eco" "$view" | _fc_fzf_read "$@"
    fi
  fi
}

# 调用注册表登记的查询函数。缓冲路径整个 session 一次，流式路径每次渲染一次。
_fc_reg_query() {
  local fn
  fn=$(_fc_reg_get "$1" "$2") || return 1
  "$fn"
}

# 精确删除匹配的行。不能用 ${(@)rows:#pat}：它按 glob 匹配整个元素，而元素含
# tab，且 flag 参数塞不进 $'\t'。
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
#   否则                    -> _FC_REG[<eco>:fallback] 原生透传，收 (act, 包名)
_fc_act() {               # $1=eco $2=view $3=act $4=name
  local act=$3 fn
  fn=$(_fc_reg_get "$1" "$act")
  if [[ -n $fn ]]; then
    "$fn" "$4"
  else
    fn=$(_fc_reg_get "$1" fallback) || return 1
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
_fc_reg_view_mutating() {     # $1=eco $2=view -> _FC_MUTATING
  local -a m
  m=(${(s: :)$(_fc_reg_view_get "$1" "$2" mutating)})
  (( ! ${#m} )) && m=(${(s: :)$(_fc_reg_get "$1" mutating)})
  _FC_MUTATING=("${m[@]}")
}

# 回滚到指定版本。versions 列表只在此处取一次，不随 session 缓存。
#
# 三个数据键刻意不叫 versions / current / install：install 是 search 视图的
# 合法动作名，而 _fc_act 用 _FC_REG[<eco>:<动作名>] 查专用处理函数，叫 install
# 的话用户选「install」会命中回滚用的安装器。写成动词-名词就不撞。
_fc_rollback() {          # $1=eco $2=pkg
  local eco=$1 pkg=$2 versions old new fn
  fn=$(_fc_reg_get "$eco" list-versions) || return 1
  versions=$("$fn" "$pkg")
  if [[ -z $versions ]]; then
    _fc_msg "No versions." "$pkg" && return 0
  fi
  old=$("$(_fc_reg_get "$eco" current-version)" "$pkg")
  _fc_msg "${old:-Not-installed}" "$pkg"
  new=$(print -l -- ${(f)versions} | _fc_fzf_read)
  if [[ -z $new ]]; then
    _fc_msg "Rollback cancel." "$pkg" && return 0
  fi
  [[ $new == "$old" ]] && { print -n $'\nREINSTALL THE SAME VERSION after 2 seconds\n'; sleep 2 }
  # 第 3 个参数是回滚前的版本：多数 ecosystem 用不到，gem 要靠它先卸载。
  # 已有的 handler 只用 $1 $2，多传不影响。
  "$(_fc_reg_get "$eco" install-version)" "$pkg" "$new" "$old"
}

# 对选中的一批包执行一个动作。
#
# $4=1 表示 mutating 动作，遇到失败立刻停止（返回 1）。只读动作传 0：它没有改变
# 任何状态，中止没有意义，「失败」往往只是「没有结果」（例如 brew uses 查不到依赖）。
# 结果放进 _FC_DONE / _FC_FAILED，由 _fc_session 决定要不要删行。
_fc_apply() {           # $1=eco $2=view $3=act $4=mutating?
  local eco=$1 view=$2 act=$3 strict=$4 p name
  _FC_DONE=()
  _FC_FAILED=()
  _FC_RC=0
  for p in "${(@f)_FC_PICKED}"; do
    # _fc_render 把对齐填充放在第一个 tab 之后，所以这里取到的 name 天然干净
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

# 动作失败后的汇总：哪一项失败、后面的没做、成功几项。
_fc_report() {          # $1=act
  print -r -- ""
  # 130 = 128 + SIGINT：下载 formulae 时 Ctrl-C 很常见，说成「失败」会让用户
  # 以为包坏了，而实际上什么都没变。
  if (( _FC_RC == 130 )); then
    print -r -- "  ${_FC_FAILED[1]}: 动作 '$1' 被 Ctrl-C 中断，已停止"
  else
    print -r -- "  ${_FC_FAILED[1]}: 动作 '$1' 失败（退出码 $_FC_RC），已停止"
  fi
  (( ${#_FC_DONE} )) && print -r -- "  已完成 ${#_FC_DONE} 项并移出列表"
  print -r -- "  其余 ${_FC_PENDING} 项未执行，仍在列表里"
}

# view 循环：缓冲路径整轮 session 只查询一次，动作后从内存删行，不重查不落盘；
# 流式路径每次回到列表重查，但从不把列表读进 zsh。
_fc_session() {           # $1=eco $2=view
  local eco=$1 view=$2 sel act p
  local -i strict
  local -a picked mutating stay fzfopts
  typeset -ga _FC_PICKED _FC_DONE _FC_FAILED
  typeset -gi _FC_PENDING _FC_RC _FC_STREAM

  _FC_HEADER=$(_fc_reg_view_get "$eco" "$view" title)
  [[ -n $_FC_HEADER ]] || _FC_HEADER=$(_fc_reg_get "$eco" title)
  _fc_reg_view_mutating "$eco" "$view"
  mutating=("${_FC_MUTATING[@]}")
  stay=(${(s: :)$(_fc_reg_get "$eco" stay)})
  fzfopts=(${(s: :)$(_fc_reg_view_get "$eco" "$view" fzf-opts)})

  _FC_STREAM=0
  if _fc_view_streamable "$eco" "$view"; then
    _FC_STREAM=1
    # 清掉上一批数据：_FC_ROWS 是全局的，留着会让人误以为本视图也缓冲过。
    _FC_ROWS=()
  else
    _fc_reg_query "$eco" "$view" | _fc_load_rows
    if (( ! ${#_FC_ROWS} )); then
      _fc_msg "Nothing to show." "$_FC_HEADER" && return 0
    fi
  fi

  while :; do
    # 必须把列表管道给 fzf，否则 fzf 会去读终端，把用户输入当成候选列表。
    sel=$(_fc_feed "$eco" "$view" --multi $opt) || break
    [[ -n $sel ]] || break
    # 必须用 ${(f)sel} 或 "${(@f)sel}"：${(f)"$sel"} 是非法语法，且只在运行时
    # 才报 bad substitution，zsh -n 检查不出来。
    picked=("${(@f)sel}")
    (( ${#picked} )) || continue
    _FC_PICKED=("${picked[@]}")

    # 内层：动作菜单。stay 里的动作执行完留在原地，可连续执行多个只读动作。
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
        (( ${stay[(Ie)$act]} )) || break
        continue
      fi

      # 只有 mutating 动作会走到这里。已生效的必须移出列表，否则用户会以为还在；
      # 失败项与未执行项保持原样，可直接重试。
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
