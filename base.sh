#!/usr/bin/env zsh
# 上面这行是文件元数据（供编辑器与格式化工具识别），不是解释器指令。
# 本文件是库文件，由 fzf-collection.plugin.zsh 以 source 方式加载。
# 它仅含函数定义、无顶层入口，即使赋予执行权限直接运行也只会是空操作，
# 且缺少 base.sh 的依赖必然失败。文件模式保持 100644，不要 chmod +x。

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

# A -> B -> _fzf_parent, return function name of A by default
# SEE https://stackoverflow.com/a/56305385/13194984
# use ${array:index:length} in zsh for compatibility, index start at 0, don't bothered by option: ksharrays
_fzf_parent() {
  local level
  level=${1:-2}

  echo "${funcstack[@]:$level:1}"
}

## generate fzf header according to command name
_fzf_header() {
  _fzf_parent | perl -pe 's/[_-]/ /g; s/(\w+)/\u\L$1/g; s/^\s+|\s+$//g'
}

# SEE https://stackoverflow.com/a/68093509/13194984
_fzf_underline() {
  printf -- '%s\n' "$1"
  printf -- '▔%.0s' {1..$#1}
}

_fzf_read() {
  fzf "${_fzf_opts[@]}" --header "$(_fzf_underline "$header")" "$@" \
    | perl -lane 'print $F[0]'
}

## generate fzf tmpfile according to command name
_fzf_tmp_create() {
  echo "/tmp/$(_fzf_parent).lock"
}

_fzf_tmp_read() {
  cat <"$tmpfile" | _fzf_read --multi $fzf_extra "$@"
}

_fzf_tmp_write() {
  tee "$tmpfile" | _fzf_read --multi $fzf_extra "$@"
}

# SEE https://stackoverflow.com/a/24493085/13194984
## remove related line in tmpfile
_fzf_tmp_shift() {
  perl -i -slne '/^$f(\s+.+)$/||print' -- -f="$1" "$tmpfile"

  # BUG cann't delete \n newline
  # perl -i -lspe 's/^$f(\s+.+)$//' -- -f="$1" "$tmpfile"
}

# TODO update pkg version info when using rollback
# SEE https://stackoverflow.com/questions/12131134/replace-specific-capture-group-instead-of-entire-regex-in-perl
# _fzf_tmp_update() {
#
# }

_fzf_subcmd() {
  echo "${opt[@]}" | perl -pe 's/ /\n/g' | _fzf_read
}

_fzf_version_check() {
  if [ "$new" = "$old" ]; then
    printf "\nREINSTALL THE SAME VERSION after 2 seconds\n" && sleep 2
  fi
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

_fzf_outdated() {
  local lst caller
  caller=$(_fzf_parent)

  if [ ! -e "$tmpfile" ]; then
    lst=$($outdated)
    if [ -n "$lst" ]; then
      touch "$tmpfile"
      inst=$(echo "$lst" | _fzf_format | _fzf_tmp_write)
    else
      _fzf_msg "No updates." && return 0
    fi
  else
    if [ -s "$tmpfile" ]; then
      inst=$(_fzf_tmp_read)
    else
      rm -f "$tmpfile"
      _fzf_msg "Upgrade finished." && return 0
    fi
  fi
  if [ -n "$inst" ]; then
    eval " $switch"
  else
    rm -f "$tmpfile"
    _fzf_msg "Upgrade cancel." && return 0
  fi

  eval "$caller"
}

_fzf_manage() {
  if [ ! -e "$tmpfile" ]; then
    touch "$tmpfile"
    inst=$($installed | _fzf_format | _fzf_tmp_write)
  else
    inst=$(_fzf_tmp_read)
  fi

  if [ -n "$inst" ]; then
    eval " $switch"
  else
    rm -f "$tmpfile" && return 0
  fi

  eval "$(_fzf_parent)"
}

_fzf_search() {
  if [ ! -e "$tmpfile" ]; then
    touch "$tmpfile"
    inst=$($available | _fzf_tmp_write)
  else
    inst=$(_fzf_tmp_read)
  fi

  if [ -n "$inst" ]; then
    eval " $switch"
  else
    rm -f "$tmpfile" && return 0
  fi

  eval "$(_fzf_parent)"
}

_fzf_rollback() {
  local old new caller
  caller=$(_fzf_parent)

  if [ -n "$versions" ]; then
    old=$($current)
    _fzf_msg "${old:-Not-installed}" "$pkg"
    new=$(echo "$versions" | _fzf_read)

    if [ -n "$new" ]; then
      _fzf_version_check
      eval " $install"
    else
      _fzf_msg "Rollback cancel." && return 0
    fi
  else
    _fzf_msg "No versions." && return 0
  fi
}

## generate fzf interface according to command name
_fzf_command() {
  local cmd

  cmd=$(_fzf_subcmd)
  [ -n "$cmd" ] && eval "$(_fzf_parent)-$cmd"
}
