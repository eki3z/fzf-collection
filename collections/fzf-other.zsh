#!/usr/bin/env zsh
# 上面这行是文件元数据（供编辑器与格式化工具识别），不是解释器指令。
# 本文件是库文件，由 fzf-collection.plugin.zsh 以 source 方式加载。
# 它仅含函数定义、无顶层入口，即使赋予执行权限直接运行也只会是空操作，
# 且缺少 base.zsh 的依赖必然失败。文件模式保持 100644，不要 chmod +x。

# 这两个命令（pathf / envf）不是包管理器，没有 view 与 action 的概念，
# 所以不进注册表，各自带一个 _FC_HEADER。

# 两个命令的候选由 _other_format 上色，于是 fzf 必须知道候选里有 SGR 序列。
# 以前这里是各自直接调 fzf 并显式带一份 --ansi，因为 _FC_OPTS 是用户可覆盖的
# 变量 —— 一旦有人设 FZF_COLLECTION_OPTS 时漏掉 --ansi，fzf 会把 \e[34m 当
# 5 个普通字符：既不上色，还把这 5+4 个字节算进显示宽度，于是长行被提前截断。
# 现在两个命令都走 _fc_fzf_read，--ansi 由它无条件带上，这条依赖只有一处实现。
#
# 注意：这与 fzf 在 Kitty 键盘协议下把按键序列当文本插入查询框是两回事，
# 那个问题 fzf 至今未修（junegunn/fzf#3208），与本插件无关。

# 取首个字段之后的全部内容：剥掉对齐填充与颜色码。
#
# 原来是 `perl -lane 'printf "%s = %s", $F[0], $F[$#F]'`，$F[$#F] 是最后一个
# 空白分隔字段，所以值里带空格时会截断 —— 例如 PATH 里有
# "/Applications/VMware Fusion.app/Contents/Public"，结果只剩 "Fusion.app/..."。
# 这里改成「首个字段之后全都要」，把值完整带出来。
#
# 颜色码：fzf 带 --ansi 时输出已经剥掉了颜色，所以这步只是兜底。
# 原来这里是掐固定的首尾两段（'$_FZF_BLUE' 前缀、'$_FC_SGR_RESET' 后缀），
# 也就是把剥色和**当前配色**绑死了：换成别的颜色后它会静默失效，而且因为
# 上面那条 --ansi 已经剥过一次，失效也不报错。现在统一走 _fc_sgr_strip，
# 认的是 SGR 序列本身，与用哪套配色无关。
_other_value() {             # $1=行
  local t=${1#"${1%%[[:space:]]*}"}
  _fc_ltrim t
  t=$(_fc_sgr_strip "$t")
  print -r -- "$t"
}

# =============================================================================
# 表格排版：这两个命令的列表要对齐，也就是逐字节复刻 column -t
#
# 这段以前在 base.zsh 里，也就是「驱动 + 注册表」那个文件里，而它的调用方
# 只有 pathf 和 envf。一个只服务单个模块的通用排版器放在驱动文件里，层次是
# 反的：读 base.zsh 的人会以为驱动依赖它，其实依赖方向相反。现在它跟着模块
# 走，模块私有代码一律 _other_ 前缀。
#
# 排版要用调色板，所以这两个函数会调 base.zsh 的 _fc_sgr_prefix —— 跨模块
# 调用，方向是对的：模块依赖驱动，不反过来。
# =============================================================================

_other_format() {          # 首字段原样，其余合并成一段并染蓝，再按首字段宽度对齐
  local line first rest
  local pre post
  # 首字段与合并段之间的标记。不能与空白同形，否则无法传给 _other_align
  # 区分「按它切」和「按空白切」两种模式。
  local sep='^^'
  local -a lines out
  # 着色在循环外解析一次：色码每行都一样，而逐行 _fc_sgr_paint 是每行一次命令替换。
  # 两个变量而不是一个，正是为了「不上色时后缀也是空」——否则会留下裸的
  # \e[0m，而 _fc_sgr_strip 之外的消费者未必认得它。
  _fc_sgr_prefix have
  pre=$_FC_SGR_PREFIX
  if [[ -n $pre ]]; then post=$_FC_SGR_RESET; else post=''; fi
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
    _fc_ltrim line
    first=${line%%[[:space:]]*}
    rest=${line#"$first"}
    # 首字段之外的部分要按空白重新拼接：旧规则是 perl 的 join(" ", @F[1 .. $#F])，
    # 它把字段间的制表符、连续空格一律压成单个空格。直接取原 remainder 会把
    # 制表符原样带进显示里。
    rest=${rest//[[:space:]]/ }
    while [[ $rest == *"  "* ]]; do rest=${rest//  / }; done
    while [[ $rest == ' '* ]]; do rest=${rest# }; done
    while [[ $rest == *' ' ]]; do rest=${rest% }; done
    out+=("$first$sep$pre$rest$post")
  done
  print -rl -- "${out[@]}" | _other_align "$sep"
}

# 按分隔符对齐成表格，逐字节复刻 `column -t`：
#   丢掉空行 -> 切列 -> 每列补齐到本列最大宽度 -> 列间 2 个空格 -> 末列不补
#
# $1 可选分隔符。给了就按它切（复刻 `column -s X -t`），没给就按空白切
# （复刻 `column -s ' ' -t`）。两种模式的差别都在下面的切分处：给了分隔符时
# 空行保留且不剥前导空白，没给时反过来。
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
_other_align() {          # $1=可选分隔符
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
      keep=("${(@f)${line//"$delim"/$_FC_NL}}")
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
      keep=("${(@f)${line//"$delim"/$_FC_NL}}")
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

# [P]ath [F]ind
# option -d return executable path

pathf() {
  local _FC_HEADER line dir
  local i
  _FC_HEADER="Find Path"

  # 原来写的是 for i in $(echo ${PATH//:/ }) —— 一次 echo fork，
  # 而且靠命令替换的空白分词，路径里有空格就断了。${(s.:.)PATH} 直接切。
  for i in "${(@s.:.)PATH}"; do
    if [ -d "$i" ]; then
      # option -H to allow symbolic root_path to parse normally
      # SEE https://www.gnu.org/software/findutils/manual/html_node/find_html/Symbolic-Links.html
      find -H "$i" -maxdepth 1 -executable -type f,l -printf "%f ${i/$HOME/~}\n"
    fi
  done \
    | _other_format \
    | uniq \
    | _fc_fzf_read --tiebreak=index \
    | while IFS= read -r line; do
        # 原来这里是 `| perl -lane "$rule"`，$rule 为
        #   printf "%s/%s", glob($F[$#F]), $F[0]   （或 -d 时 printf "%s/", glob(...)）
        # glob() 对普通路径是恒等，但会把开头的 ~ 展开成 $HOME ——
        # find 那步把 $HOME 换成了 ~，所以 PATH 里含 ~/bin 时这是真实场景，要保留。
        #
        # 这个 while 必须接在管道里。写成独立语句的话它读的是函数自己的
        # stdin，不是 fzf 的输出。
        dir=$(_other_value "$line")
        [[ $dir == '~'* ]] && dir=$HOME${dir#\~}
        if [[ "$1" == "-d" ]]; then
          print -r -- "$dir/"
        else
          print -r -- "$dir/${line%%[[:space:]]*}"
        fi
      done
}

# [E]nv

envf() {
  # key / val 在下面的 while 循环里用；都在函数开头声明，
  # 循环体内的标量 local 会污染 stdout（zsh 5.9）。
  local _FC_HEADER rec line key val
  # local 一次性声明完，别在后面重复 local（zsh 5.9 会往 stdout 打 NAME=值）。
  local valmax=${_ENVF_VALMAX:-$_FC_ENVF_WIDTH}
  _FC_HEADER="Env"

  # 用 NUL 分隔读，值里含换行时才不会被拆成两条记录。
  # zsh 的 read -d 能吃 NUL（read -r -d $'\0'），所以不需要 tr 或 perl。
  # 读进来后：换行压成空格（与旧实现一致），第一个 = 换成空格。
  #
  # 显示层把值截到 valmax 个字符。必须截 —— PATH 的值实测 1994 字符，
  # 是 200 列终端的 10 倍，FPATH / LS_COLORS / __MISE_ZSH_ACTIVATE_PATH
  # 也都超屏宽。fzf 只能截断并横向滚动这些行，于是一行看着只剩尾部，
  # 整个列表像是错位。pathf 的值是「目录 + 文件名」，从没超宽，所以它不受影响 ——
  # 这就是两个命令表现不同的原因。
  #
  # 截断只影响显示：选中后按 key 从环境重新取完整值（见管道末尾）。
  while IFS= read -r -d $'\0' rec; do
    rec=${rec//$'\n'/ }
    [[ $rec == *=* ]] || continue
    key=${rec%%=*}
    val=${rec#*=}
    if (( ${#val} > valmax )); then
      val="${val[1,$valmax]}..."
    fi
    print -r -- "$key $val"
  done < <(printenv --null) \
    | sort -u \
    | _other_format \
    | _fc_fzf_read \
    | while IFS= read -r line; do
        # 显示行里的值已被截断，所以按 key 从环境重新取完整值。
        key=${line%%[[:space:]]*}
        # 用 parameters 判存在性，不能用「${(P)key} 是否为空」——
        # 值为空的环境变量是合法的，那样判会错误地回退到已截断的显示值。
        if (( ${+parameters[$key]} )); then
          print -r -- "$key = ${(P)key}"
        else
          print -r -- "$key = $(_other_value "$line")"
        fi
      done
}
