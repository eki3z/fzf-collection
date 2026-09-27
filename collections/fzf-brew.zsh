#!/usr/bin/env zsh
# 库文件，由 fzf-collection.plugin.zsh source 加载；无顶层入口，模式 100644。

# SEE https://gist.github.com/steakknife/8294792

_brewf() {
  # HOMEBREW_NO_INSTALL_FROM_API=1 关掉 API，brew 全部读本地 tap。
  brew "$@"
}

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
    print -r -- "$name${_FC_TAB}${f[2]}${_FC_TAB}=>${_FC_TAB}${f[4]}"
  done
}

# `brew list --versions` 每行是 `name 1.2 3.4`，多版本用 `|` 连起来。
_brewf_list_installed() {
  local line
  local -a f
  _brewf list --versions | while IFS= read -r line; do
    f=(${(z)line})
    (( ${#f} >= 2 )) || continue
    print -r -- "${f[1]}${_FC_TAB}${(j:|:)f[2,-1]}"
  done
}

# `brew ls --pinned --versions` 与 list --versions 同形。
_brewf_list_pinned() {
  local line
  local -a f
  brew ls --pinned --versions | while IFS= read -r line; do
    f=(${(z)line})
    (( ${#f} >= 2 )) || continue
    print -r -- "${f[1]}${_FC_TAB}${(j:|:)f[2,-1]}"
  done
}

_brewf_list_available() {
  brew formulae
  brew casks
}

_brewf_list_tap() { brew tap }

# ---- 回滚 ----
# 不用通用 _fc_rollback：它要先定位 formula 所在的 tap 目录才能对单个文件做
# git checkout，目录由包名推导，所以这层自带；也因此不注册 versions /
# current / install 三个键。

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
  # 回滚前是 pinned 就重新 pin —— 看实际状态，不看从哪个视图进来。
  _brewf_is_pinned "$1" && brew pin "$1" &>/dev/null
  return 0
}

_brewf_rollback() {          # $1=pkg
  local pkg=$1 dir old new
  # _fc_fzf_read 靠动态作用域读 _FC_HEADER，所以能 local 覆盖而不影响外层。
  local _FC_HEADER="Rollback $pkg"
  dir=$(_brewf_brewdir "$pkg")
  if [[ -z $dir ]]; then
    _fc_msg "No formulae or cask exists." "$pkg" && return 0
  fi
  old=$(_brewf_version_current "$pkg")
  _fc_msg "${old:-Not-installed}" "$pkg"
  # git log 默认按时间倒序，--tiebreak=index 保证 fzf 不打乱它。
  new=$(print -l -- ${(f)"$(_brewf_version_list "$pkg")"} \
    | _fc_fzf_read --tiebreak=index --query="$pkg")
  if [[ -z $new ]]; then
    _fc_msg "Rollback cancel." "$pkg" && return 0
    return 0
  fi
  # _fc_fzf_read 原样返回整行，所以 hash 要在这里自己取。
  _brewf_checkout "$pkg" "${new%% *}" "$old"
}

# ---- 动作适配器 ----

_brewf_info() { _brewf info "$1" | _fc_pager }
_brewf_uses() { _brewf uses --installed "$1" }
_brewf_deps() { _brewf deps "$1" --tree }
_brewf_edit() { $EDITOR "$(_brewf formula "$1")" }

# 其余动作（homepage / options / cat / link / unlink / pin / install /
# tap-info）都落到 `*)` 原样透传。
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

_FC_REG+=(
  'brew:title'  'Brew'
  'brew:views'  'outdated search manage pinned tap'
  'brew:fallback' '_brewf_act'

  'brew:outdated'       '_brewf_list_outdated'
  'brew:outdated:title' 'Brew Outdated'
  'brew:outdated:fzf-opts'   '--tiebreak=index'
  'brew:outdated:actions' 'upgrade uninstall rollback options homepage info deps uses edit cat'
  'brew:outdated:cols'  'name have sep want'

  'brew:search'         '_brewf_list_available'
  'brew:search:title'   'Brew Search'
  # search 列的是**还没装**的 formula/cask，所以 uninstall（对没装的包卸载）和
  # unpin（没装的东西无从 pin）都不能在这里 —— manage 与 pinned 视图里两个都有。
  # 于是本视图没有 mutating 动作，走流式路径（base.zsh 的
  # _fc_view_streamable），每次回列表重跑一次 brew formulae。
  'brew:search:actions' 'install rollback options homepage info deps uses edit cat link unlink pin'
  'brew:search:cols'    'name'

  'brew:manage'         '_brewf_list_installed'
  'brew:manage:title'   'Brew Manage'
  'brew:manage:actions' 'uninstall rollback homepage link unlink pin unpin options info deps uses edit cat'
  'brew:manage:cols'    'name have'

  'brew:pinned'         '_brewf_list_pinned'
  'brew:pinned:title'   'Brew Pinned'
  'brew:pinned:actions' 'unpin rollback uninstall homepage link unlink options info deps uses edit cat'
  'brew:pinned:cols'    'name have'

  'brew:tap'            '_brewf_list_tap'
  'brew:tap:title'      'Brew Tap'
  'brew:tap:actions'    'untap tap-info'
  'brew:tap:cols'       'name'

  # 移出列表的动作。rollback 不删行但会回到列表，所以不在这里。
  'brew:mutating' 'upgrade uninstall untap unpin'

  # 留在动作菜单里的动作。unlink 会改 brew 状态却仍留在这里，先保持现状。
  'brew:stay' 'install options homepage info deps uses edit cat link unlink pin'

  'brew:rollback' '_brewf_rollback'
)

brewf() {
  _fc_cmd brew
}
