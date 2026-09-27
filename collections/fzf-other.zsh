#!/usr/bin/env zsh
# 库文件，由 fzf-collection.plugin.zsh source 加载；无顶层入口，模式 100644。

# 这两个命令（pathf / envf）不是包管理器，没有 view 与 action 的概念，所以不进
# 注册表，各自带一个 _FC_HEADER。

# 候选由 _other_format 上色，所以 fzf 必须知道候选里有 SGR 序列：_fc_fzf_read 无条件
# 带上 --ansi。用户若用 FZF_COLLECTION_OPTS 覆盖掉它，fzf 会把 \e[34m 当 5 个普通
# 字符：既不上色，还把这 5+4 个字节算进显示宽度，长行于是被提前截断。

# 取首个字段之后的全部内容：剥掉对齐填充与颜色码。fzf 带 --ansi 时输出已经
# 剥过颜色，所以 _fc_sgr_strip 这步只是兜底。
_other_value() {             # $1=行
  local t=${1#"${1%%[[:space:]]*}"}
  _fc_ltrim t
  t=$(_fc_sgr_strip "$t")
  print -r -- "$t"
}

# ---- 表格排版：复刻 column -t ----

# 排版要用调色板，所以这两个函数会调 base.zsh 的 _fc_sgr_prefix。
_other_format() {          # 首字段原样，其余合并成一段并染蓝，再按首字段宽度对齐
  local line first rest
  local pre post
  # 首字段与合并段之间的标记。不能与空白同形，否则 _other_align 分不清「按它切」
  # 与「按空白切」。
  local sep='^^'
  local -a lines out
  # 着色在循环外解析一次：色码每行都一样，而逐行 _fc_sgr_paint 是每行一次命令替换。
  # pre / post 分开是为了「不上色时后缀也是空」，否则会留下裸的 \e[0m。
  _fc_sgr_prefix have
  pre=$_FC_SGR_PREFIX
  if [[ -n $pre ]]; then post=$_FC_SGR_RESET; else post=''; fi
  # 末行没有换行时 read 返回非零但仍填了变量，所以要补一次判断。
  while IFS= read -r line || [[ -n $line ]]; do lines+=("$line"); done
  # 输入全是空白行时什么都不输出。
  local any=0
  for line in "${lines[@]}"; do
    [[ -n ${line//[[:space:]]/} ]] && { any=1; break; }
  done
  (( any )) || return 0
  for line in "${lines[@]}"; do
    _fc_ltrim line
    first=${line%%[[:space:]]*}
    rest=${line#"$first"}
    # 首字段之外按空白重拼：制表符与连续空格都压成单个空格。
    rest=${rest//[[:space:]]/ }
    while [[ $rest == *"  "* ]]; do rest=${rest//  / }; done
    while [[ $rest == ' '* ]]; do rest=${rest# }; done
    while [[ $rest == *' ' ]]; do rest=${rest% }; done
    out+=("$first$sep$pre$rest$post")
  done
  print -rl -- "${out[@]}" | _other_align "$sep"
}

# 按分隔符对齐成表格：丢空行 -> 切列 -> 每列补到本列最大宽 -> 列间 2 空格 -> 末列
# 不补。$1 可选分隔符：给了按它切（复刻 `column -s X -t`），没给按空白切
# （复刻 `column -s ' ' -t`）。

# 几个反直觉的细节：连续分隔符当一个，且**空字段整个丢掉**（不占宽度也不占间隔），
# 列号按剩下的字段数；空白模式剥每行前导空白、折叠连续空格，指定分隔符时不剥；
# 制表符在空白模式下**不算**分隔符（`-s ' '` 只认字面空格）。

# 已知限制：column 按显示宽度算，zsh 的 ${#} 按字符数，含宽字符时对齐会偏。当前
# 调用方的字段都是 ASCII。
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
      # 分隔符是变量时 ${(s:$delim)var} 不展开（flag 参数是字面量），所以先替换
      # 成换行再按行切。给 $delim 加引号是为了不让它当 glob。
      keep=("${(@f)${line//"$delim"/$_FC_NL}}")
    else
      keep=("${(@s: :)line}")
    fi
    # column 把空字段整个丢掉：不占宽度也不占间隔，列号按剩下的字段数。
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
# -d 只输出目录，不带文件名。

pathf() {
  local _FC_HEADER line dir
  local i
  _FC_HEADER="Find Path"

  for i in "${(@s.:.)PATH}"; do
    if [ -d "$i" ]; then
      # -H 让 root_path 处的符号链接照常解析：
      # https://www.gnu.org/software/findutils/manual/html_node/find_html/Symbolic-Links.html
      find -H "$i" -maxdepth 1 -executable -type f,l -printf "%f ${i/$HOME/~}\n"
    fi
  done \
    | _other_format \
    | uniq \
    | _fc_fzf_read --tiebreak=index \
    | while IFS= read -r line; do
        # 这个 while 必须接在管道里：写成独立语句的话它读的是函数自己的 stdin，
        # 不是 fzf 的输出。
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
  # key / val 给下面的 while 用，都在这里声明完：循环体内的标量 local 会往 stdout
  # 打一行赋值，混进候选（zsh 5.9）。
  local _FC_HEADER rec line key val
  local valmax=${_ENVF_VALMAX:-$_FC_ENVF_WIDTH}
  _FC_HEADER="Env"

  # 用 NUL 分隔读，值里含换行时才不会被拆成两条记录；zsh 的 read -d 能吃 NUL，
  # 所以不需要 tr。读进来后换行压成空格，key / val 按第一个 = 切开。

  # 显示层把值截到 valmax 个字符。必须截：PATH 的值实测 1994 字符，FPATH /
  # LS_COLORS / __MISE_ZSH_ACTIVATE_PATH 也都超屏宽，fzf 只能横向滚动，一行看着
  # 只剩尾部，整个列表像是错位。截断只影响显示，选中后按 key 从环境取完整值。
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
        # 显示行里的值已被截断，所以按 key 从环境取完整值。存在性用 parameters
        # 判，不能用「${(P)key} 是否为空」：空值环境变量合法，那样会退回截断值。
        key=${line%%[[:space:]]*}
        if (( ${+parameters[$key]} )); then
          print -r -- "$key = ${(P)key}"
        else
          print -r -- "$key = $(_other_value "$line")"
        fi
      done
}
