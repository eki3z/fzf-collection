#!/usr/bin/env bash

_pipf() {
  pip --disable-pip-version-check "$@"
}

_pipf_list_installed() {
  # SEE https://unix.stackexchange.com/a/615709
  _pipf list --format=json | jq -r '.[] | "\(.name) \(.version)"'
}

_pipf_list_outdated() {
  _pipf list --format=json --outdated \
    | jq -r '.[] | "\(.name) \(.version) \(.latest_version)"'
}

_pipf_list_available() {
  curl -s "$(pip config get global.index-url)/" \
    | perl -lne '/">(.*?)<\/a>/ && print $1'
}

_pipf_extract() {
  _pipf show "$1" 2>/dev/null | perl -slne '/^\Q$f\E: (.+)$/ && print "$1"' -- -f="$2"
}

_pipf_install() {
  _pipf install --user "$@"
}

_pipf_uninstall() {
  if [ "$1" = "pip" ]; then
    echo "Package [pip] can not be uninstalled !" && return 1
  else
    if _fzf_exist pip-autoremove && [ "$1" != "pip-autoremove" ]; then
      # REQUIRE pip install pip-autoremove
      pip-autoremove "$1" --yes
    else
      _pipf uninstall --yes "$1"
    fi
  fi
}

_pipf_version_current() {
  _pipf_extract "$pkg" Version 2>/dev/null
}

_pipf_version_install() {
  _pipf_install --upgrade --force-reinstall "$pkg==$new" 2>/dev/null
}

_pipf_rollback() {
  local header pkg current install versions

  pkg=$1
  header=$(_fzf_header)
  current="_pipf_version_current"
  install="_pipf_version_install"
  versions=$(
    _pipf index versions --pre "$pkg" 2>/dev/null \
      | perl -lne '/Available versions: (.*)$/m && print $1' \
      | perl -pe 's/, /\n/g'
  )

  _fzf_rollback
}

_pipf_switch() {
  local subcmd

  subcmd=$(_fzf_subcmd)

  if [ -n "$subcmd" ]; then

    for f in $(echo "$inst"); do
      case $subcmd in
        upgrade)
          _pipf_install --upgrade "$f" && _fzf_tmp_shift "$f"
          ;;
        uninstall)
          _pipf_uninstall "$f" && _fzf_tmp_shift "$f"
          ;;
        install)
          _pipf_install "$f"
          ;;
        rollback)
          _pipf_rollback "$f"
          ;;
        homepage)
          _fzf_homepage "$(_pipf_extract "$f" Home-page)"
          ;;
        deps)
          _pipf_extract "$f" Requires
          ;;
        use)
          _pipf_extract "$f" Required-by
          ;;
        info)
          _pipf show "$f"
          ;;
        *)
          _pipf "$subcmd" "$f"
          ;;
      esac
      echo ""
    done

    case $subcmd in
      upgrade | uninstall | rollback) return 0 ;;
    esac

  else
    return 0
  fi

  _pipf_switch
}

pipf-outdated() {
  local inst header opt tmpfile format outdated switch

  header=$(_fzf_header)
  tmpfile=$(_fzf_tmp_create)
  format="outdated"
  outdated="_pipf_list_outdated"
  switch="_pipf_switch"
  opt=("upgrade" "uninstall" "rollback" "deps" "use" "info")

  _fzf_outdated
}

pipf-manage() {
  local tmpfile inst header opt format installed switch

  header=$(_fzf_header)
  tmpfile=$(_fzf_tmp_create)
  format="manage"
  installed="_pipf_list_installed"
  switch="_pipf_switch"
  opt=("uninstall" "rollback" "homepage" "deps" "use" "info")

  _fzf_manage
}

pipf-search() {
  local tmpfile inst opt header available switch

  header=$(_fzf_header)
  tmpfile=$(_fzf_tmp_create)
  opt=("install" "uninstall" "rollback")
  available="_pipf_list_available"
  switch="_pipf_switch"

  _fzf_search
}

pipf() {
  local header opt

  header=$(_fzf_header)
  opt=("outdated" "search" "manage")

  _fzf_command
}
