#!/usr/bin/env zsh
# 上面这行是文件元数据（供编辑器与格式化工具识别），不是解释器指令。
# 本文件是库文件，由 fzf-collection.plugin.zsh 以 source 方式加载。
# 它仅含函数定义、无顶层入口，即使赋予执行权限直接运行也只会是空操作，
# 且缺少 base.sh 的依赖必然失败。文件模式保持 100644，不要 chmod +x。

# SEE https://gist.github.com/steakknife/8294792

_brewf() {
  # # make brew command don't call curl
  # HOMEBREW_NO_INSTALL_FROM_API=1
  brew "$@"
}

_brewf_list_outdated() {
  brew update &>/dev/null
  brew outdated --verbose \
    | grep -Fv "pinned at" \
    | perl -pe 's/, /|/g; tr/()//d' \
    | perl -lane 'print "$F[0] $F[1] $F[3]"'

  # # NOTE time consuming is as twice as above
  #   brew info --json=v2 --installed \
  #     | jq -r '.[] | values[] | "\(.name | if type=="array" then .[0] else . end) \(.installed | if type=="array" then map(.version) | join("|") else . end)"' \

}

_brewf_list_installed() {
  _brewf list --versions \
    | perl -ane 'printf "%s %s\n", $F[0], join("|", @F[1 .. $#F])'

  # # NOTE time consuming is as twice as above
  #   _brewf info --json=v2 --installed \
  #     | jq -r '.[] | values[] | "\(.name | if type=="array" then .[0] else . end) \(.installed | if type=="array" then map(.version) | join("|") else . end)"'

}

_brewf_list_available() {
  brew formulae
  brew casks
}

_brewf_version_current() {
  _brewf list --versions | perl -slne '/^$f (.+)$/ && print "$1"' -- -f="$pkg"
}

_brewf_version_list() {
  git -C "$dir" log --color=always --pretty='format:%C(magenta)%h%C(reset) %s' -- "$f"
}

_brewf_version_install() {
  brew unpin "$pkg" &>/dev/null
  git -C "$dir" checkout "$new" "$f"
  (HOMEBREW_NO_AUTO_UPDATE=1 && brew reinstall "$pkg")
  git -C "$dir" checkout HEAD "$f"

  # pkg if it's pinned at first
  [ $format = "pinned" ] && brew pin "$pkg" &>/dev/null
}

_brewf_switch() {
  local subcmd

  subcmd=$(_fzf_subcmd)

  if [ -n "$subcmd" ]; then
    for f in $(echo "$inst"); do
      case $subcmd in
        rollback)
          _brewf_rollback "$f"
          ;;
        edit)
          $EDITOR "$(brew formula "$f")"
          ;;
        upgrade)
          _brewf upgrade --yes "$f" && _fzf_tmp_shift "$f"
          ;;
        uninstall | untap | unpin)
          _brewf "$subcmd" "$f" && _fzf_tmp_shift "$f"
          ;;
        uses)
          _brewf uses --installed "$f"
          ;;
        deps)
          _brewf deps "$f" --tree
          ;;
        info)
          _brewf info "$f" | _fzf_pager
          ;;
        *) _brewf "$subcmd" "$f" ;;
      esac
      echo ""
    done

    case $subcmd in
      upgrade | uninstall | untap | rollback) return 0 ;;
    esac

  else
    return 0
  fi

  _brewf_switch

}

_brewf_rollback() {
  local header pkg f dir caller fzf_extra current install versions

  header=$(_fzf_header)
  pkg="$1"
  f="$pkg.rb"
  dir=$(dirname "$(find "$(brew --repository)" -name "$f" | head -n 1)")
  caller=$(_fzf_parent 1)

  fzf_extra="--tiebreak=index --query=$pkg update"
  current="_brewf_version_current"
  install="_brewf_version_install"
  versions="_brewf_version_list"

  if [ -n "$dir" ]; then
    old=$($current)
    _fzf_msg "${old:-Not-installed}" "$pkg"
    new=$($versions | _fzf_read)

    if [ -n "$new" ]; then
      eval " $install"
    else
      _fzf_msg "Rollback cancel." && return 0
    fi
  else
    _fzf_msg "No formulae or cask exists." && return 0
  fi
}

brewf-search() {
  local tmpfile inst opt header available switch

  header=$(_fzf_header)
  tmpfile=$(_fzf_tmp_create)
  available="_brewf_list_available"
  switch="_brewf_switch"
  opt=("install" "rollback" "options" "homepage" "info" "deps" "uses" "edit" "cat"
    "uninstall" "link" "unlink" "pin" "unpin")

  _fzf_search
}

brewf-manage() {
  local inst opt header tmpfile format installed switch

  header=$(_fzf_header)
  tmpfile=$(_fzf_tmp_create)
  format="manage"
  installed="_brewf_list_installed"
  switch="_brewf_switch"
  opt=("uninstall" "rollback" "homepage" "link" "unlink" "pin" "unpin"
    "options" "info" "deps" "uses" "edit" "cat")

  _fzf_manage
}

brewf-outdated() {
  local inst opt header tmpfile format outdated switch

  header=$(_fzf_header)
  tmpfile=$(_fzf_tmp_create)
  format="outdated"
  outdated="_brewf_list_outdated"
  switch="_brewf_switch"
  opt=("upgrade" "uninstall" "rollback" "options" "homepage" "info" "deps" "uses" "edit" "cat")

  _fzf_outdated
}

brewf-tap() {
  local tmpfile inst opt header

  header=$(_fzf_header)
  tmpfile=$(_fzf_tmp_create)
  opt=("untap" "tap-info")

  if [ ! -e "$tmpfile" ]; then
    tap_list=$(brew tap)

    if [ -n "$tap_list" ]; then
      touch "$tmpfile"
      inst=$(echo "$tap_list" | _fzf_tmp_write)
    else
      echo "No tap."
      return 0
    fi

  else

    if [ -s "$tmpfile" ]; then
      inst=$(_fzf_tmp_read)
    else
      echo "No tap."
      rm -f "$tmpfile" && return 0
    fi
  fi

  if [ -n "$inst" ]; then
    _brewf_switch
  else
    echo "Tap cancel."
    rm -f "$tmpfile" && return 0
  fi

  brewf-tap
}

brewf-pinned() {
  local tmpfile inst opt header format switch lst

  header=$(_fzf_header)
  tmpfile=$(_fzf_tmp_create)
  caller=$(_fzf_parent 1)
  switch="_brewf_switch"
  format="pinned"
  opt=("unpin" "rollback" "uninstall" "homepage" "link" "unlink"
    "options" "info" "deps" "uses" "edit" "cat")

  if [ ! -e "$tmpfile" ]; then
    lst=$(brew ls --pinned --versions)
    if [ -n "$lst" ]; then
      touch "$tmpfile"
      inst=$(echo "$lst" | _fzf_format | _fzf_tmp_write)
    else
      _fzf_msg "No pinned." && return 0
    fi

  else

    if [ -s "$tmpfile" ]; then
      inst=$(_fzf_tmp_read)
    else
      rm -f "$tmpfile"
      _fzf_msg "No pinned." && return 0
    fi
  fi

  if [ -n "$inst" ]; then
    eval " $switch"
  else
    rm -f "$tmpfile"
    _fzf_msg "Unpin cancel." && return 0
  fi

  brewf-pinned
}

brewf() {
  local header opt

  header=$(_fzf_header)
  opt=("outdated" "search" "manage" "pinned" "tap")

  _fzf_command

}
