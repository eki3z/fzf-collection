#!/usr/bin/env zsh
# 上面这行是文件元数据（供编辑器与格式化工具识别），不是解释器指令。
# 本文件是库文件，由 fzf-collection.plugin.zsh 以 source 方式加载。
# 它仅含函数定义、无顶层入口，即使赋予执行权限直接运行也只会是空操作，
# 且缺少 base.zsh 的依赖必然失败。文件模式保持 100644，不要 chmod +x。

# [F]ind [P]ath
# option -d return executable path

fp() {
  local header format rule
  header="Find Path"
  format="general"

  if [[ "$1" == "-d" ]]; then
    rule='printf "%s/", glob($F[$#F])'
  else
    rule='printf "%s/%s", glob($F[$#F]), $F[0]'
  fi

  for i in $(echo ${PATH//:/ }); do
    if [ -d "$i" ]; then
      # option -H to allow symbolic root_path to parse normally
      # SEE https://www.gnu.org/software/findutils/manual/html_node/find_html/Symbolic-Links.html
      find -H "$i" -maxdepth 1 -executable -type f,l -printf "%f ${i/$HOME/~}\n"
    fi
  done \
    | _fzf_format \
    | uniq \
    | fzf "${_fzf_opts[@]}" --header "$(_fzf_underline "$header")" --tiebreak=index \
    | perl -lane "$rule"
}

# [F]ind [FP]ath

ffp() {
  local loc header
  header="Find Fpath"
  loc=$(
    echo "$FPATH" \
      | perl -pe 's/:/\n/g' \
      | _fzf_read
  )

  if [ -d "$loc" ]; then
    header="Find Fpath => ${loc}"
    rg --files "$loc" \
      | rev \
      | cut -d"/" -f1 \
      | rev \
      | _fzf_read >/dev/null
    ffp
  fi
}

# [E]nv
envf() {
  local header format rule
  header="Env"
  format="general"
  # NOTE use null as separator then replace \n and first = to space to avoid conflicts.
  printenv --null \
    | perl -pe 's/\n+/ /g;s/\x00/\n/g' \
    | perl -pe 's/^(\S+?)=/$1 /' \
    | sort -u \
    | _fzf_format \
    | fzf "${_fzf_opts[@]}" --header "$(_fzf_underline "$header")" \
    | perl -lane 'printf "%s = %s", $F[0], $F[$#F]'
}
