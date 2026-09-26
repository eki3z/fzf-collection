#!/usr/bin/env zsh
# 上面这行是文件元数据（供编辑器与格式化工具识别），不是解释器指令。
# 本文件是库文件，由 fzf-collection.plugin.zsh 以 source 方式加载。
# 它仅含函数定义、无顶层入口，即使赋予执行权限直接运行也只会是空操作，
# 且缺少 base.zsh 的依赖必然失败。文件模式保持 100644，不要 chmod +x。

# SEE https://gist.github.com/steakknife/8294792

_brewf() {
  # # make brew command don't call curl
  # HOMEBREW_NO_INSTALL_FROM_API=1
  brew "$@"
}

# 列表函数在 while 循环里用到的分隔符。必须先声明：循环体内的 local 会让
# zsh 5.9 往 stdout 打一行变量赋值，混进喂给 fzf 的候选列表。
typeset -g _B_TAB=$'\t'

# ---- 列表查询：输出 name<TAB>rest ----

# `brew outdated --verbose` 每行形如
#   git (2.30.1) < 2.35.1, 2.36.0 [pinned at 2.30.1]
# 去掉括号、`, ` 换成 `|` 之后按空白切，第 4 段是全部可升级版本。
_brewf_list_outdated() {
  local line name
  local -a f
  brew update &>/dev/null
  brew outdated --verbose | grep -Fv 'pinned at' | while IFS= read -r line; do
    line=${line//[()]/}
    line=${line//, /|}
    f=(${(z)line})
    (( ${#f} >= 4 )) || continue
    name=${f[1]}
    print -r -- "$name${_B_TAB}${f[2]}${_B_TAB}=>${_B_TAB}${f[4]}"
  done

  # # NOTE time consuming is as twice as above
  #   brew info --json=v2 --installed \
  #     | jq -r '.[] | values[] | "\(.name | if type=="array" then .[0] else . end) \(.installed | if type=="array" then map(.version) | join("|") else . end)"'
}

# `brew list --versions` 每行是 `name 1.2 3.4`，多版本用 `|` 连起来
_brewf_list_installed() {
  local line
  local -a f
  _brewf list --versions | while IFS= read -r line; do
    f=(${(z)line})
    (( ${#f} >= 2 )) || continue
    print -r -- "${f[1]}${_B_TAB}${(j:|:)f[2,-1]}"
  done

  # # NOTE time consuming is as twice as above
  #   _brewf info --json=v2 --installed \
  #     | jq -r '.[] | values[] | "\(.name | if type=="array" then .[0] else . end) \(.installed | if type=="array" then map(.version) | join("|") else . end)"'
}

# `brew ls --pinned --versions` 与 list --versions 同形
_brewf_list_pinned() {
  local line
  local -a f
  brew ls --pinned --versions | while IFS= read -r line; do
    f=(${(z)line})
    (( ${#f} >= 2 )) || continue
    print -r -- "${f[1]}${_B_TAB}${(j:|:)f[2,-1]}"
  done
}

_brewf_list_available() {
  brew formulae
  brew casks
}

_brewf_list_tap() { brew tap }

# ---- 回滚 ----
# brew 不能用通用的 _pkg_rollback：它要先定位 formula 所在的 tap 目录，
# 才能对那一个文件做 git checkout。目录由包名推导，所以这层是自带的。
# 也就没有 versions / current / install 三个注册表键 —— 它们只服务于
# 通用 _pkg_rollback，填在这里反而会让人误以为 brew 走通用路径。

_brewf_brewdir() {           # $1=pkg -> formula 所在目录
  local f=$1.rb
  dirname "$(find "$(brew --repository)" -name "$f" | head -n 1)"
}

_brewf_version_current() {   # $1=pkg
  local line
  local -a f
  local -a rows
  rows=(${(f)"$(_brewf list --versions)"})
  for line in $rows; do
    f=(${(z)line})
    [[ ${f[1]:-} == "$1" ]] || continue
    print -r -- "${(j: :)f[2,-1]}"
    return 0
  done
  return 0
}

_brewf_version_list() {      # $1=pkg -> git log，每行 `hash subject`
  local dir
  dir=$(_brewf_brewdir "$1")
  [[ -n $dir ]] || return 0
  git -C "$dir" log --color=always --pretty='format:%C(magenta)%h%C(reset) %s' -- "$1.rb"
}

_brewf_is_pinned() {         # $1=pkg
  local line
  local -a f pins
  pins=(${(f)"$(brew ls --pinned --versions 2>/dev/null)"})
  for line in $pins; do
    f=(${(z)line})
    [[ ${f[1]:-} == "$1" ]] && return 0
  done
  return 1
}

# $1=pkg $2=目标 commit $3=回滚前的版本
_brewf_checkout() {
  local dir
  dir=$(_brewf_brewdir "$1")
  brew unpin "$1" &>/dev/null
  git -C "$dir" checkout "$2" "$1.rb"
  (HOMEBREW_NO_AUTO_UPDATE=1 && brew reinstall "$1")
  git -C "$dir" checkout HEAD "$1.rb"
  # 旧版看 $format，只在从 pinned 视图回滚时才重新 pin；于是从 manage /
  # outdated 视图回滚一个 pinned formula 会被顺手 unpin 掉。
  # 这里改成看实际状态：回滚前是 pinned 就一定重新 pin。
  _brewf_is_pinned "$1" && brew pin "$1" &>/dev/null
  return 0
}

_brewf_rollback() {          # $1=pkg
  local pkg=$1 dir old new
  # _pkg_read 靠动态作用域读 header，所以这里可以 local 覆盖而不影响外层
  local header="Rollback $pkg"
  dir=$(_brewf_brewdir "$pkg")
  if [[ -z $dir ]]; then
    _fzf_msg "No formulae or cask exists." "$pkg" && return 0
  fi
  old=$(_brewf_version_current "$pkg")
  _fzf_msg "${old:-Not-installed}" "$pkg"
  # --query 预填包名，与旧 _brewf_rollback 的 fzf_extra 一致。
  # git log 默认按时间倒序，--tiebreak=index 保证 fzf 不打乱它。
  new=$(print -l -- ${(f)"$(_brewf_version_list "$pkg")"} \
    | _pkg_read --tiebreak=index --query="$pkg")
  if [[ -z $new ]]; then
    _fzf_msg "Rollback cancel." && return 0
    return 0
  fi
  # 旧 _fzf_read 末尾有 `perl -lane 'print $F[0]'`，把整行压成第一个词。
  # 新 _pkg_read 原样返回整行，所以 hash 要在这里自己取。
  _brewf_checkout "$pkg" "${new%% *}" "$old"
}

# ---- 动作适配器 ----

_brewf_info() { _brewf info "$1" | _fzf_pager }
_brewf_uses() { _brewf uses --installed "$1" }
_brewf_deps() { _brewf deps "$1" --tree }
_brewf_edit() { $EDITOR "$(_brewf formula "$1")" }

# 旧 _brewf_switch 的显式分支只有下面几个，其余（含 homepage / options /
# cat / link / unlink / pin / install / tap-info）都落到 `*)` 原样透传。
_brewf_act() {
  case $1 in
    upgrade) _brewf upgrade --yes "$2" ;;
    edit)    _brewf_edit "$2" ;;
    uses)    _brewf_uses "$2" ;;
    deps)    _brewf_deps "$2" ;;
    info)    _brewf_info "$2" ;;
    *)       _brewf "$1" "$2" ;;
  esac
}

# ---- 注册表 ----

# base.zsh 已用 typeset -gA 声明过；这里再确认一次，使本文件即使被单独 source
# 也不会把 PKG 变成普通数组（下标里的 ':' 会被当成算术求值）。
[[ ${(t)PKG} == association ]] || typeset -gA PKG

PKG+=(
  'brew:title'  'Brew'
  'brew:views'  'outdated search manage pinned tap'
  'brew:runner' '_brewf_act'

  'brew:outdated'       '_brewf_list_outdated'
  'brew:outdated:title' 'Brew Outdated'
  'brew:outdated:opt'   '--tiebreak=index'
  'brew:outdated:actions' 'upgrade uninstall rollback options homepage info deps uses edit cat'
  'brew:outdated:cols'  '0,34,0,33'

  'brew:search'         '_brewf_list_available'
  'brew:search:title'   'Brew Search'
  'brew:search:actions' 'install rollback options homepage info deps uses edit cat uninstall link unlink pin unpin'
  'brew:search:cols'    '0'

  'brew:manage'         '_brewf_list_installed'
  'brew:manage:title'   'Brew Manage'
  'brew:manage:actions' 'uninstall rollback homepage link unlink pin unpin options info deps uses edit cat'
  'brew:manage:cols'    '0,34'

  'brew:pinned'         '_brewf_list_pinned'
  'brew:pinned:title'   'Brew Pinned'
  'brew:pinned:actions' 'unpin rollback uninstall homepage link unlink options info deps uses edit cat'
  'brew:pinned:cols'    '0,34'

  'brew:tap'            '_brewf_list_tap'
  'brew:tap:title'      'Brew Tap'
  'brew:tap:actions'    'untap tap-info'
  'brew:tap:cols'       '0'

  # 移出列表的动作。旧 _brewf_switch 里调 _fzf_tmp_shift 的是
  # upgrade 和 uninstall|untap|unpin 四个。rollback 不删行但会回到列表，
  # 所以不在这里 —— 与 gem / cargo 保持一致。
  'brew:mutating' 'upgrade uninstall untap unpin'

  # 留在动作菜单里的动作。
  # link / unlink / pin 在旧版同样不删行、不回列表，就一直停在动作菜单上；
  # unlink 其实会改变 brew 状态却仍留在这里看着别扭，但这是旧行为，先照搬。
  'brew:loop' 'install options homepage info deps uses edit cat link unlink pin'

  'brew:rollback' '_brewf_rollback'
)

brewf() {
  _pkg_cmd brew
}
