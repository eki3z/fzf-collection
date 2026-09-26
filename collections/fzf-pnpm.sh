#!/usr/bin/env zsh
# 上面这行是文件元数据（供编辑器与格式化工具识别），不是解释器指令。
# 本文件是库文件，由 fzf-collection.plugin.zsh 以 source 方式加载。
# 它仅含函数定义、无顶层入口，即使赋予执行权限直接运行也只会是空操作，
# 且缺少 base.sh 的依赖必然失败。文件模式保持 100644，不要 chmod +x。

_pnpmf() {
  pnpm "$1" --global "${@:2}"
}

_pnpmf_list_outdated() {
  _pnpmf outdated --json \
    | jq -r 'to_entries[] | "\(.key) \(.value | .current) \(.value | .latest)"'
}

_pnpmf_list_installed() {
  _pnpmf list --json \
    | jq -r '.[].dependencies | values[] | "\(.from) \(.version)"'
}

_pnpmf_list_available() {
  all-the-package-names
}

_pnpmf_version_current() {
  _pnpmf list --json "$pkg" 2>/dev/null \
    | jq -r '.[].dependencies | values[].version'
}

_pnpmf_version_install() {
  echo "Install $pkg@$new"
  _pnpmf add "$pkg@$new" 2>/dev/null
}

_pnpmf_switch() {
  local subcmd

  subcmd=$(_fzf_subcmd)

  if [ -n "$subcmd" ]; then
    for f in $(echo "$inst"); do
      case $subcmd in
        update)
          echo "update $f"
          # SEE https://github.com/pnpm/pnpm/issues/5365#issuecomment-1252398786
          _pnpmf update --latest "$f" && _fzf_tmp_shift "$f"
          ;;
        remove)
          _pnpmf remove "$f" && _fzf_tmp_shift "$f"
          ;;
        add)
          _pnpmf add "$f"
          ;;
        rollback)
          _pnpmf_rollback "$f"
          ;;
        homepage)
          _fzf_homepage "$(pnpm view "$f" homepage)"
          ;;
        deps)
          pnpm view "$f" dependencies
          ;;
        info)
          pnpm view "$f" | _fzf_pager
          ;;
        *) pnpm "$subcmd" "$f" ;;
      esac
      echo ""
    done

    case $subcmd in
      update | remove | rollback) return 0 ;;
    esac

  else
    return 0
  fi

  _pnpmf_switch
}

_pnpmf_rollback() {
  local header pkg current install versions

  pkg=$1
  header=$(_fzf_header)
  current="_pnpmf_version_current"
  install="_pnpmf_version_install"
  versions=$(
    pnpm info "$pkg" versions --json 2>/dev/null \
      | jq -r 'reverse | .[]' 2>/dev/null
  )

  _fzf_rollback
}

pnpmf-manage() {
  local tmpfile inst header opt format installed switch

  header=$(_fzf_header)
  tmpfile=$(_fzf_tmp_create)
  format="manage"
  installed="_pnpmf_list_installed"
  switch="_pnpmf_switch"
  opt=("remove" "rollback" "homepage" "deps" "info")

  _fzf_manage
}

pnpmf-outdated() {
  local inst header opt tmpfile format outdated switch

  header=$(_fzf_header)
  tmpfile=$(_fzf_tmp_create)
  format="outdated"
  outdated="_pnpmf_list_outdated"
  switch="_pnpmf_switch"
  opt=("update" "remove" "rollback" "homepage" "deps" "info")

  _fzf_outdated
}

pnpmf-search() {
  local tmpfile inst opt header available switch fzf_extra

  # REQUIRE npm install -g all-the-package-names
  if ! _fzf_exist all-the-package-names; then
    echo 'Error! please run "pnpm add -g all-the-package-names" first!' && return 0
  fi

  header=$(_fzf_header)
  tmpfile=$(_fzf_tmp_create)
  available="_pnpmf_list_available"
  switch="_pnpmf_switch"
  opt=("add" "rollback" "homepage" "deps" "info")
  fzf_extra="--tiebreak=begin,length,index"

  _fzf_search
}

pnpmf() {
  local header opt

  header=$(_fzf_header)
  opt=("outdated" "search" "manage")

  _fzf_command
}
