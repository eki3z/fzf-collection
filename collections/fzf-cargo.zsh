#!/usr/bin/env zsh
# 上面这行是文件元数据（供编辑器与格式化工具识别），不是解释器指令。
# 本文件是库文件，由 fzf-collection.plugin.zsh 以 source 方式加载。
# 它仅含函数定义、无顶层入口，即使赋予执行权限直接运行也只会是空操作，
# 且缺少 base.zsh 的依赖必然失败。文件模式保持 100644，不要 chmod +x。

# ---- 列表查询：输出 name<TAB>rest ----

# `cargo install --list` 每行是 `name v1.0.0:`
_cargof_list_installed() {
  local line name ver
  cargo install --list | while IFS= read -r line; do
    [[ $line == *' v'*':' ]] || continue
    name=${line%% v*}
    ver=${line#* v}
    ver=${ver%:*}
    print -r -- "$name${_C_TAB}${ver#v}"
  done
}

# `cargo install-update --list` 每行是 `name v1.0.0 v2.0.0 Yes`，
# 只有 Yes（确实有新版）的行要留在这里。
# 部分版本的 cargo-install-update 在两个版本号之间还会插一个 `->`，
# 旧版正则要求没有它才匹配得上。这里先去掉，两种格式都能吃。
_cargof_list_outdated() {
  local line name cur new
  local -a f
  cargo install-update --list | while IFS= read -r line; do
    line=${line//->/}
    f=(${(z)line})
    (( ${#f} >= 4 )) || continue
    [[ ${f[4]} == Yes ]] || continue
    name=${f[1]}
    cur=${f[2]#v}
    new=${f[3]#v}
    print -r -- "$name${_C_TAB}$cur${_C_TAB}=>${_C_TAB}$new"
  done
}

_cargof_list_available() {
  all-the-crate-names
}

# ---- crates.io 查询 ----
# $1=crate $2=field [$3=当前版本，仅 dependencies 需要]
# 版本号从显式参数来，不再靠调用者作用域里的 $pkg。
# SEE https://github.com/hcpl/crates.io-http-api-reference#user-content-get-versions
_cargof_extract() {
  local field query

  case $2 in
    homepage)
      field="$1"
      query='.crate | .homepage // .repositorys // empty'
      ;;
    versions)
      field="$1"
      query='.versions[] | .num'
      ;;
    dependencies)
      field="$1/$3/dependencies"
      query='.dependencies[] | "\(.crate_id) \(.req)"'
      ;;
    info)
      field="$1"
      query='.crate |"id: \(.id)\nmax_version: \(.max_version)\nrepository: \(.repository)\ndownloads: \(.downloads)\ncreated: \(.created_at)\nupdated: \(.updated_at)\ndescription: \(.description)"'
      ;;
    *)
      print -r -- "Error: No such option: $2" && return 0
      ;;
  esac

  curl --silent "https://crates.io/api/v1/crates/$field" | jq -r "$query"
}

# ---- 版本相关：显式收参 ----

# 通用 _pkg_rollback 只传包名一个参数，而 _cargof_extract 需要 (crate, field)，
# 所以这里给 versions 包一层，不能直接把 _cargof_extract 填进注册表。
_cargof_version_list() { _cargof_extract "$1" versions }

_cargof_version_current() {
  local line ver
  local -a f
  cargo install --list 2>/dev/null | while IFS= read -r line; do
    f=(${(z)line})
    (( ${#f} >= 2 )) || continue
    [[ ${f[1]} == "$1" ]] || continue
    # 行尾的冒号要剥掉 —— 旧版靠 perl 正则里的 `:$` 顺手做了这件事
    ver=${f[2]#v}
    print -r -- "${ver%:}"
    break
  done
}

# $1=crate $2=目标版本（--force 让 cargo 允许降级）
_cargof_version_install() {
  print -r -- "install $1: version $2"
  cargo install --force --version "$2" -- "$1"
}

# ---- 动作适配器 ----

_cargof_rollback() { _pkg_rollback cargo "$1" }
_cargof_info() { _cargof_extract "$1" info | _fzf_pager }
_cargof_deps() { _cargof_extract "$1" dependencies "$(_cargof_version_current "$1")" | column -s ' ' -t }
_cargof_homepage() { _fzf_homepage "$(_cargof_extract "$1" homepage)" }

_cargof_act() {
  case $1 in
    # 旧版用 `cargo <subcmd> -- <name>`，cargo 会把 -- 后当位置参数
    update | uninstall | install) cargo "$1" -- "$2" ;;
    *)                              cargo "$1" "$2" ;;
  esac
}

# ---- 注册表 ----

# base.zsh 已用 typeset -gA 声明过；这里再确认一次，使本文件即使被单独 source
# 也不会把 PKG 变成普通数组（下标里的 ':' 会被当成算术求值）。
[[ ${(t)PKG} == association ]] || typeset -gA PKG

# 列表函数在 while 循环里用到的分隔符。必须先声明：循环体内的 local 会让
# zsh 5.9 往 stdout 打一行变量赋值，混进喂给 fzf 的候选列表。
typeset -g _C_TAB=$'\t'

PKG+=(
  'cargo:title'   'Cargo'
  # search 已注册但没进 views：all-the-crate-names 至今不可用，
  # 旧版因此把 search 从菜单里注释掉了。补上 views 即可启用。
  'cargo:views'   'outdated manage'
  'cargo:runner'  '_cargof_act'

  'cargo:outdated'       '_cargof_list_outdated'
  'cargo:outdated:title' 'Cargo Outdated'
  'cargo:outdated:opt'   '--tiebreak=index'
  'cargo:outdated:actions' 'update uninstall rollback deps info'
  'cargo:outdated:cols'  '0,34,0,33'

  'cargo:manage'         '_cargof_list_installed'
  'cargo:manage:title'   'Cargo Manage'
  'cargo:manage:actions' 'uninstall rollback homepage deps info'
  'cargo:manage:cols'    '0,34'

  'cargo:search'         '_cargof_list_available'
  'cargo:search:title'   'Cargo Search'
  'cargo:search:actions' 'install uninstall rollback homepage deps info'
  'cargo:search:cols'    '0'

  # 旧 _cargof_switch 里 update / uninstall / install 都调了 _fzf_tmp_shift，
  # rollback 不删行但会回到列表，所以它不在这里。
  'cargo:mutating' 'install uninstall update'
  'cargo:loop'     'homepage deps info'

  'cargo:rollback'  '_cargof_rollback'
  'cargo:info'      '_cargof_info'
  'cargo:deps'      '_cargof_deps'
  'cargo:homepage'  '_cargof_homepage'
  'cargo:version-list'     '_cargof_version_list'
  'cargo:version-current'  '_cargof_version_current'
  'cargo:version-install'  '_cargof_version_install'
)

cargof() {
  _pkg_cmd cargo
}
