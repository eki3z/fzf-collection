#!/usr/bin/env zsh
# 上面这行是文件元数据（供编辑器与格式化工具识别），不是解释器指令。
# 本文件是库文件，由 fzf-collection.plugin.zsh 以 source 方式加载。
# 它仅含函数定义、无顶层入口，即使赋予执行权限直接运行也只会是空操作，
# 且缺少 base.zsh 的依赖必然失败。文件模式保持 100644，不要 chmod +x。

# 这两个命令（pathf / envf）不是包管理器，没有 view 与 action 的概念，
# 所以不进注册表，各自带一个 header 变量。

# pathf 与 envf 的 fzf 调用显式带 --ansi。_FC_OPTS 里默认也有（见
# fzf-collection.plugin.zsh 的 FZF_COLLECTION_OPTS 默认值），但那是用户可覆盖的
# 变量 —— 一旦有人设 FZF_COLLECTION_OPTS 时漏掉 --ansi，_fzf_format 加的颜色
# 就会被 fzf 当普通文本：不上色，还把 \e[34m 的 5+4 个字节算进显示宽度，
# 于是长行被提前截断。候选由本文件上色的调用点自己声明这个依赖。
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
# 上面那条 --ansi 已经剥过一次，失效也不报错。现在统一走 _fzf_unpaint，
# 认的是 SGR 序列本身，与用哪套配色无关。
_fzf_tail() {             # $1=行
  local t=${1#"${1%%[[:space:]]*}"}
  while [[ $t == [[:space:]]* ]]; do t=${t#?}; done
  t=$(_fzf_unpaint "$t")
  print -r -- "$t"
}

# [P]ath [F]ind
# option -d return executable path

pathf() {
  local header format line dir
  local i
  header="Find Path"
  format="general"

  # 原来写的是 for i in $(echo ${PATH//:/ }) —— 一次 echo fork，
  # 而且靠命令替换的空白分词，路径里有空格就断了。${(s.:.)PATH} 直接切。
  for i in "${(@s.:.)PATH}"; do
    if [ -d "$i" ]; then
      # option -H to allow symbolic root_path to parse normally
      # SEE https://www.gnu.org/software/findutils/manual/html_node/find_html/Symbolic-Links.html
      find -H "$i" -maxdepth 1 -executable -type f,l -printf "%f ${i/$HOME/~}\n"
    fi
  done \
    | _fzf_format \
    | uniq \
    | fzf "${_FC_OPTS[@]}" --ansi --header "$(_fzf_underline "$header")" --tiebreak=index \
    | while IFS= read -r line; do
        # 原来这里是 `| perl -lane "$rule"`，$rule 为
        #   printf "%s/%s", glob($F[$#F]), $F[0]   （或 -d 时 printf "%s/", glob(...)）
        # glob() 对普通路径是恒等，但会把开头的 ~ 展开成 $HOME ——
        # find 那步把 $HOME 换成了 ~，所以 PATH 里含 ~/bin 时这是真实场景，要保留。
        #
        # 这个 while 必须接在管道里。写成独立语句的话它读的是函数自己的
        # stdin，不是 fzf 的输出。
        dir=$(_fzf_tail "$line")
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
  local header format rec line key val
  # local 一次性声明完，别在后面重复 local（zsh 5.9 会往 stdout 打 NAME=值）。
  local valmax=${_ENVF_VALMAX:-80}
  header="Env"
  format="general"
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
    | _fzf_format \
    | fzf "${_FC_OPTS[@]}" --ansi --header "$(_fzf_underline "$header")" \
    | while IFS= read -r line; do
        # 显示行里的值已被截断，所以按 key 从环境重新取完整值。
        key=${line%%[[:space:]]*}
        # 用 parameters 判存在性，不能用「${(P)key} 是否为空」——
        # 值为空的环境变量是合法的，那样判会错误地回退到已截断的显示值。
        if (( ${+parameters[$key]} )); then
          print -r -- "$key = ${(P)key}"
        else
          print -r -- "$key = $(_fzf_tail "$line")"
        fi
      done
}
