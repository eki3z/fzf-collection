#!/usr/bin/env bash

# SEE https://www.linuxquestions.org/questions/programming-9/passing-a-shell-variable-into-awk-syntax-for-correct-interpretation-562973/#post2793088
# SEE https://stackoverflow.com/a/56762028/13194984

_brewf_list_format() {
  local input
  input="$([[ -p /dev/stdin ]] && cat - || return)"

  if [[ -n "$input" ]]; then
    case $1 in
      --formulae | --formula)
        echo "$input" | awk '{print "\x1b[33mf  \x1b[0m" $0}'
        ;;
      --cask | --casks)
        echo "$input" | awk '{print "\x1b[36mc  \x1b[0m" $0}'
        ;;
      *) return 0 ;;
    esac
  fi
}

# SEE https://gist.github.com/steakknife/8294792

_brewf_switch() {

  subcmd=$(echo "${@:2}" | tr ' ' '\n' | _fzf_single_header)

  if [ -n "$subcmd" ]; then
    for f in $(echo "$1"); do
      case $subcmd in
        rollback)
          brewf-rollback "$f"
          ;;
        edit)
          $EDITOR "$(brew formula "$f")"
          ;;
        upgrade | uninstall | untap)
          if brew "$subcmd" "$f"; then
            # SEE https://stackoverflow.com/questions/5410757/how-to-delete-from-a-text-file-all-lines-that-contain-a-specific-string
            # SEE https://stackoverflow.com/a/17273270 , escape '/' in path
            # SEE https://unix.stackexchange.com/a/33005
            # FIXME whether delete succeed?
            sed -i "/$(sed 's/\//\\&/g' <<<"$f")/d" "$tmpfile"
          fi
          ;;
        *) brew "$subcmd" "$f" ;;
      esac
      echo ""
    done

    case $subcmd in
      # SEE https://stackoverflow.com/a/4827707
      upgrade | uninstall | untap) return 0 ;;
    esac

  else
    return 0
  fi

  _brewf_switch "$@"

}

brewf-rollback() {
  local f dir sha header

  header="Brew Rollback"
  f="$1.rb"
  dir=$(dirname "$(find "$(brew --repository)" -name "$f")")

  if [ -n "$dir" ]; then
    sha=$(
      git -C "$dir" log --color=always -- "$f" \
        | _fzf_single_header --tiebreak=index --query="update $1" \
        | awk '{ print $1 }'
    )

    if [ -n "$sha" ]; then
      brew unpin "$1" &>/dev/null

      git -C "$dir" checkout "$sha" "$f"
      (HOMEBREW_NO_AUTO_UPDATE=1 && brew reinstall "$1")
      git -C "$dir" checkout HEAD "$f"

      if ! brew outdated "$1" &>/dev/null; then
        brew pin "$1" &>/dev/null
      fi

    else
      return 0
    fi
  else
    return 0
  fi

}

brewf-search() {
  local inst opt header

  header="Brew Search"
  inst=$(
    {
      brew formulae | _brewf_list_format --formulae
      brew casks | _brewf_list_format --cask
    } \
      | _fzf_multi_header \
      | awk '{print $2}'
  )

  opt=("install" "rollback" "options" "info" "deps" "edit" "cat"
    "home" "uninstall" "link" "unlink" "pin" "unpin")

  if [ -n "$inst" ]; then
    _brewf_switch "$inst" "${opt[@]}"
  else
    return 0
  fi

  brewf-search

}

brewf-manage() {
  local tmpfile inst opt header

  header="Brew Manage"
  tmpfile=/tmp/brewf-manage

  opt=("uninstall" "rollback" "link" "unlink" "pin" "unpin"
    "options" "info" "deps" "edit" "cat" "home")

  if [ ! -e $tmpfile ]; then
    touch $tmpfile

    inst=$(
      {
        brew list --formulae --versions | _brewf_list_format --formulae
        brew list --cask --versions | _brewf_list_format --cask
      } \
        | tee $tmpfile \
        | _fzf_multi_header \
        | awk '{print $2}'
    )

  else
    inst=$(cat <$tmpfile | _fzf_multi_header | awk '{print $2}')
  fi

  if [ -n "$inst" ]; then
    _brewf_switch "$inst" "${opt[@]}"
  else
    rm -f $tmpfile && return 0
  fi

  brewf-manage

}

brewf-outdated() {
  local tmpfile outdate_list inst opt header

  header="Brew Outdated"
  tmpfile=/tmp/brewf-outdated
  opt=("upgrade" "uninstall" "options" "info" "deps" "edit" "cat" "home")

  if [ ! -e $tmpfile ]; then
    brew update

    outdate_list=$(
      {
        brew outdated --formula --verbose | _brewf_list_format --formula
        brew outdated --cask --greedy --verbose | _brewf_list_format --cask
      } \
        | grep -Fv "pinned at"
    )

    if [[ -n $outdate_list ]]; then
      touch $tmpfile
      inst=$(
        echo "$outdate_list" \
          | tee $tmpfile \
          | _fzf_multi_header \
          | awk '{print $2}'
      )
    else
      echo "No updates within installed formulae or cask."
      return 0
    fi

  else

    if [ -s $tmpfile ]; then
      inst=$(cat <$tmpfile | _fzf_multi_header | awk '{print $2}')
    else
      echo "Upgrade finished."
      rm -f $tmpfile && return 0
    fi

  fi

  if [[ -n "$inst" ]]; then
    _brewf_switch "$inst" "${opt[@]}"
  else
    echo "Upgrade cancel."
    rm -f $tmpfile && return 0
  fi

  brewf-outdated
}

brewf-tap() {
  local tmpfile inst opt header

  header="Brew Tap"
  tmpfile=/tmp/brewf-tap
  opt=("untap" "tap-info")

  if [ ! -e $tmpfile ]; then
    tap_list=$(brew tap)

    if [[ -n $tap_list ]]; then
      touch $tmpfile
      inst=$(echo "$tap_list" | tee $tmpfile | _fzf_multi_header)
    else
      echo "No taps used."
      return 0
    fi

  else

    if [ -s $tmpfile ]; then
      inst=$(cat <$tmpfile | _fzf_multi_header)
    else
      echo "Tap finished."
      rm -f $tmpfile && return 0
    fi
  fi

  if [[ -n "$inst" ]]; then
    _brewf_switch "$inst" "${opt[@]}"
  else
    echo "Tap cancel."
    rm -f $tmpfile && return 0
  fi

  brewf-tap

}

brewf() {
  local opt select header

  header="Brew Fzf"
  opt=("outdated" "search" "manage" "tap")
  select=$(
    echo "${opt[@]}" \
      | tr ' ' '\n' \
      | _fzf_single_header
  )

  if [ -n "$select" ]; then
    case $select in
      outdated) brewf-outdated ;;
      search) brewf-search ;;
      manage) brewf-manage ;;
      tap) brewf-tap ;;
    esac
  fi

}
