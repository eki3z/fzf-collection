#!/usr/bin/env zsh
# 上面这行是文件元数据（供编辑器与格式化工具识别），不是解释器指令。
# 本文件是库文件，由 fzf-collection.plugin.zsh 以 source 方式加载。
# 它仅含函数定义、无顶层入口，即使赋予执行权限直接运行也只会是空操作，
# 且缺少 base.sh 的依赖必然失败。文件模式保持 100644，不要 chmod +x。

_gemf_extract() {
  gem info "$1" --exact --prerelease 2>/dev/null | perl -slne '/\Q$f\E: (.+)$/ && print "$1"' -- -f="$2"
}

_gemf_list_installed() {
  gem info --prerelease \
    | perl -lne '/^(.+) \((.+)\)$/ && print "$1 $2"' \
    | perl -pe 's/, /|/g'
  # | perl -F'[,\s]+' -le 'print "$F[0] ", join("|", @F[1 .. $#F])'
}

_gemf_list_outdated() {
  gem outdated | perl -pe 'tr/()<//d'
}

_gemf_list_available() {
  gem search --remote --no-versions
}

_gemf_version_current() {
  # return the first version(newest version)
  gem info "$pkg" --exact --prerelease \
    | perl -lne '/^.+ \(([^,]+).*\)$/ && print "$1"'
}

_gemf_version_install() {
  local dir
  dir=$(_gemf_extract "$pkg" "$($current))")
  gem uninstall "$pkg" --version "$($current)" --executables --install-dir $dir
  gem install "$pkg" --version "$new" 2>/dev/null
}

_gemf_rollback() {
  local header pkg current install versions

  pkg=$1
  header=$(_fzf_header)
  current="_gemf_version_current"
  install="_gemf_version_install"
  versions=$(
    gem search "$pkg" --all --remote --exact 2>/dev/null \
      | perl -lne '/\((.*)\)$/m && print $1' \
      | perl -pe 's/, /\n/g'
  )

  _fzf_rollback
}

_gemf_switch() {
  local subcmd

  subcmd=$(_fzf_subcmd)

  if [ -n "$subcmd" ]; then
    for f in $(echo "$inst"); do
      case $subcmd in
        upgrade)
          gem update "$f" --prerelease --minimal-deps && _fzf_tmp_shift "$f"
          ;;
        uninstall)
          gem uninstall "$f" --all --executables && _fzf_tmp_shift "$f"
          ;;
        install)
          gem install "$f" --prerelease
          ;;
        rollback)
          _gemf_rollback "$f"
          ;;
        homepage)
          _fzf_homepage "$(_gemf_extract "$f" Homepage)"
          ;;
        deps)
          gem dependency "^$f$" --prerelease
          ;;
        info)
          gem info "$f" | _fzf_pager
          ;;
        *)
          gem "$subcmd" "$f"
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

  _gemf_switch
}

gemf-outdated() {
  local inst header opt tmpfile format outdated switch

  header=$(_fzf_header)
  tmpfile=$(_fzf_tmp_create)
  format="outdated"
  outdated="_gemf_list_outdated"
  switch="_gemf_switch"
  opt=("upgrade" "uninstall" "rollback" "deps" "info")

  _fzf_outdated
}

gemf-manage() {
  local tmpfile inst header opt format installed switch

  header=$(_fzf_header)
  tmpfile=$(_fzf_tmp_create)
  format="manage"
  installed="_gemf_list_installed"
  switch="_gemf_switch"
  opt=("uninstall" "rollback" "homepage" "deps" "info")

  _fzf_manage
}

gemf-search() {
  local tmpfile inst opt header available switch

  header=$(_fzf_header)
  tmpfile=$(_fzf_tmp_create)
  opt=("install" "uninstall" "rollback")
  available="_gemf_list_available"
  switch="_gemf_switch"

  _fzf_search
}

gemf() {
  local header opt

  header=$(_fzf_header)
  opt=("outdated" "search" "manage")

  _fzf_command
  gem cleanup &>/dev/null
}
