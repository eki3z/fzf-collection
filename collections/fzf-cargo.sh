#!/usr/bin/env zsh
# 上面这行是文件元数据（供编辑器与格式化工具识别），不是解释器指令。
# 本文件是库文件，由 fzf-collection.plugin.zsh 以 source 方式加载。
# 它仅含函数定义、无顶层入口，即使赋予执行权限直接运行也只会是空操作，
# 且缺少 base.sh 的依赖必然失败。文件模式保持 100644，不要 chmod +x。

_cargof_list_installed() {
  cargo install --list \
    | perl -lne '/^(.+)\sv(.+):$/ && print "$1 $2"'
}

_cargof_list_outdated() {
  cargo install-update --list \
    | perl -lne '/^(.+)\s+v(.+)\s+v(.+)\s+Yes$/ && print "$1 $2 $3"'
}

_cargof_list_available() {
  all-the-crate-names
}

# SEE https://github.com/hcpl/crates.io-http-api-reference#user-content-get-versions
_cargof_extract() {
  local pkg field query

  pkg="$1"
  case $2 in
    homepage)
      field="$pkg"
      query='.crate | .homepage // .repositorys // empty'
      ;;
    versions)
      field="$pkg"
      query='.versions[] | .num'
      ;;
    dependencies)
      field="$pkg/$(_cargof_version_current)/dependencies"
      query='.dependencies[] | "\(.crate_id) \(.req)"'
      ;;
    info)
      field="$pkg"
      query='.crate |"id: \(.id)\nmax_version: \(.max_version)\nrepository: \(.repository)\ndownloads: \(.downloads)\ncreated: \(.created_at)\nupdated: \(.updated_at)\ndescription: \(.description)"'
      ;;
    *)
      echo "Error: No such option: $pkg" && return 0
      ;;
  esac

  curl --silent "https://crates.io/api/v1/crates/$field" | jq -r "$query"
}

_cargof_version_current() {
  cargo install --list 2>/dev/null \
    | perl -slne '/^\Q$f\E\s+v(.+):$/ && print "$1"' -- -f="$pkg"
}

_cargof_version_install() {
  echo "install $pkg: version $new"
  cargo install --force --version "$new" -- "$pkg"
}

_cargof_rollback() {
  local header pkg current install versions

  pkg=$1
  header=$(_fzf_header)
  current="_cargof_version_current"
  install="_cargof_version_install"
  versions=$(_cargof_extract "$pkg" versions)

  _fzf_rollback
}

_cargof_switch() {
  local subcmd

  subcmd=$(_fzf_subcmd)

  if [ -n "$subcmd" ]; then

    for f in $(echo "$inst"); do
      case $subcmd in
        update)
          cargo install-update -- "$f" && _fzf_tmp_shift "$f"
          ;;
        uninstall)
          cargo uninstall -- "$f" && _fzf_tmp_shift "$f"
          ;;
        install)
          cargo install -- "$f" && _fzf_tmp_shift "$f"
          ;;
        rollback)
          _cargof_rollback "$f"
          ;;
        homepage)
          _fzf_homepage "$(_cargof_extract "$f" homepage)"
          ;;
        deps)
          _cargof_extract "$f" dependencies | column -s ' ' -t
          ;;
        info)
          _cargof_extract "$f" info | _fzf_pager
          ;;
        *)
          cargo "$subcmd" "$f"
          ;;
      esac
      echo ""
    done

    case $subcmd in
      update | uninstall | rollback) return 0 ;;
    esac

  else
    return 0
  fi

  _cargof_switch
}

cargof-outdated() {
  local inst header opt tmpfile format outdated switch

  header=$(_fzf_header)
  tmpfile=$(_fzf_tmp_create)
  format="outdated"
  outdated="_cargof_list_outdated"
  switch="_cargof_switch"
  opt=("update" "uninstall" "rollback" "deps" "info")

  _fzf_outdated
}

cargof-manage() {
  local tmpfile inst header opt format installed switch

  header=$(_fzf_header)
  tmpfile=$(_fzf_tmp_create)
  format="manage"
  installed="_cargof_list_installed"
  switch="_cargof_switch"
  opt=("uninstall" "rollback" "homepage" "deps" "info")

  _fzf_manage
}

cargof-search() {
  local tmpfile inst opt header available switch

  # REQUIRE cargo install all-the-crate-names
  # BUG not available yet
  if ! _fzf_exist all-the-crate-names; then
    echo 'Error! please run "cargo install all-the-crate-names" first!' && return 0
  fi

  header=$(_fzf_header)
  tmpfile=$(_fzf_tmp_create)
  opt=("install" "uninstall" "rollback" "homepage" "deps" "info")
  available="_cargof_list_available"
  switch="_cargof_switch"

  _fzf_search
}

cargof() {
  local header opt

  header=$(_fzf_header)
  # opt=("outdated" "search" "manage")
  opt=("outdated" "manage")

  _fzf_command
}
