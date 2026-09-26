#!/usr/bin/env zsh
# 上面这行是文件元数据（供编辑器与格式化工具识别），不是解释器指令。
# 本文件是库文件，由 fzf-collection.plugin.zsh 以 source 方式加载。
# 它仅含函数定义、无顶层入口，即使赋予执行权限直接运行也只会是空操作，
# 且缺少 base.zsh 的依赖必然失败。文件模式保持 100644，不要 chmod +x。

# 从 `gem info <name>` 的缩进输出里取一个字段。输出形如
#   bigdecimal (1.4.1)
#       Authors: Kenta Murata, ...
#       Homepage: https://...
# 整行含 "<字段>: " 才命中，取冒号后的内容；冒号后若还有多余空格要剥掉
# （旧版靠 perl 的 -s 顺手做了这件事）。
_gemf_extract() {
  local line
  gem info "$1" --exact --prerelease 2>/dev/null | while IFS= read -r line; do
    [[ $line == *"$2: "* ]] || continue
    line=${line#*"$2: "}
    while [[ $line == [[:space:]]* ]]; do line=${line#?}; done
    print -r -- "$line"
    break
  done
}

# ---- 列表查询：输出 name<TAB>rest ----

# `gem info --prerelease` 每行是 `name (1.0.0, 2.0.0.pre)`，多个已装版本
# 用 `, ` 分隔。旧版把它换成 `|`，与 brew 展示多版本的方式一致。
_gemf_list_installed() {
  local line name vers
  gem info --prerelease | while IFS= read -r line; do
    [[ $line == *' ('*')' ]] || continue
    name=${line%%' ('*}
    vers=${line#*' ('}
    vers=${vers%')'}
    print -r -- "$name${_G_TAB}${vers//, /|}"
  done
}

# `gem outdated` 每行是 `name (1.0.0) < 2.0.0, 3.0.0`。去掉括号后按空白切，
# 末段保留旧版的 `< 2.0.0` 写法（`=>` 由显示层给出，`<` 是 gem 自己的记法）。
_gemf_list_outdated() {
  local line name rest cur tail
  gem outdated | while IFS= read -r line; do
    line=${line//[()]/}
    name=${line%% *}
    rest=${line#* }
    cur=${rest%% *}
    tail=${rest#* }
    print -r -- "$name${_G_TAB}$cur${_G_TAB}=>${_G_TAB}$tail"
  done
}

_gemf_list_available() {
  gem search --remote --no-versions
}

# ---- 版本相关：显式收参 ----

# 所有版本（含未安装的），每行一个。
# `gem search X --all --remote --exact` 每行是
#   json (3.0.2 ruby java, 3.0.1 ruby java, ...)，取括号里那段再按 `, ` 拆行。
_gemf_version_list() {
  local line s
  gem search "$1" --all --remote --exact 2>/dev/null | while IFS= read -r line; do
    [[ $line == *'('*')' ]] || continue
    s=${line##*\(}
    s=${s%\)}
    # 换行走变量：${s//, /$'\n'} 里的 $'\n' 不会被求值
    print -r -- "${s//, /$_G_NL}"
  done
}

# 已安装的最新版本：取 `name (v1, v2)` 括号里逗号（或右括号）之前的部分
_gemf_version_current() {
  local line s
  gem info "$1" --exact --prerelease 2>/dev/null | while IFS= read -r line; do
    [[ $line == *'('*')' ]] || continue
    s=${line##*\(}
    print -r -- "${s%%[,)]*}"
    break
  done
}

# $1=pkg $2=目标版本 $3=回滚前的版本。
# gem 允许多版本共存，升级靠装新版本，但回滚必须先卸掉当前那个，
# 否则 gem 会认为目标版本已安装而跳过。
_gemf_version_install() {
  local dir
  print -r -- "Install $1@$2"
  if [[ -n $3 ]]; then
    dir=$(_gemf_extract "$1" "$3")
    gem uninstall "$1" --version "$3" --executables --install-dir $dir
  fi
  gem install "$1" --version "$2" 2>/dev/null
}

# ---- 动作适配器 ----
# 参数一律显式声明，不再读调用者作用域（旧版靠 $pkg / $current / $new
# 跨函数取值，_fzf_rollback 用 eval 注入，来源不可追踪）。

_gemf_rollback() { _pkg_rollback gem "$1" }

_gemf_info() { gem info "$1" | _fzf_pager }
_gemf_deps() { gem dependency "^$1\$" --prerelease }
_gemf_homepage() { _fzf_homepage "$(_gemf_extract "$1" Homepage)" }

# 改动类动作直接透传给 gem，只读与未知动作也透传（与旧 _gemf_switch 一致）
_gemf_act() {
  case $1 in
    # update 没有对应动作，旧版靠 `*)` 落到 gem update，保持不变
    upgrade)    gem update "$2" --prerelease --minimal-deps ;;
    uninstall)  gem uninstall "$2" --all --executables ;;
    install)    gem install "$2" --prerelease ;;
    *)          gem "$1" "$2" ;;
  esac
}

# ---- 注册表 ----

# base.zsh 已用 typeset -gA 声明过；这里再确认一次，使本文件即使被单独 source
# 也不会把 PKG 变成普通数组（下标里的 ':' 会被当成算术求值）。
[[ ${(t)PKG} == association ]] || typeset -gA PKG

# 换行符。${s//, /$'\n'} 里的 $'\n' 不会被求值（替换位和 flag 参数一样是字面量），
# 会原样输出这四个字符，所以只能走变量。必须在文件顶层声明 ——
# 循环体内的标量 local 会往 stdout 打一行赋值，混进候选列表。
typeset -g _G_TAB=$'\t'
typeset -g _G_NL=$'\n'

PKG+=(
  'gem:title'   'Gem'
  'gem:views'   'outdated search manage'
  'gem:runner'  '_gemf_act'

  'gem:outdated'       '_gemf_list_outdated'
  'gem:outdated:title' 'Gem Outdated'
  'gem:outdated:opt'   '--tiebreak=index'
  'gem:outdated:actions' 'upgrade uninstall rollback deps info'
  'gem:outdated:cols'  '0,34,0,33'

  'gem:search'         '_gemf_list_available'
  'gem:search:title'   'Gem Search'
  'gem:search:actions' 'install uninstall rollback'
  'gem:search:cols'    '0'

  'gem:manage'         '_gemf_list_installed'
  'gem:manage:title'   'Gem Manage'
  'gem:manage:actions' 'uninstall rollback homepage deps info'
  'gem:manage:cols'    '0,34'

  # 移出列表的动作。旧 _gemf_switch 里只有 upgrade / uninstall 调了
  # _fzf_tmp_shift，rollback 不删行但会回到列表，所以它不在这里。
  'gem:mutating'           'uninstall'
  'gem:outdated:mutating'  'upgrade uninstall'
  # 留在动作菜单里的动作：装完可以接着对同一批包做别的事
  'gem:loop'          'install homepage deps info'

  'gem:rollback'  '_gemf_rollback'
  'gem:info'      '_gemf_info'
  'gem:deps'      '_gemf_deps'
  'gem:homepage'  '_gemf_homepage'
  'gem:version-list'     '_gemf_version_list'
  'gem:version-current'  '_gemf_version_current'
  'gem:version-install'  '_gemf_version_install'
)

gemf() {
  _pkg_cmd gem
  gem cleanup &>/dev/null
}
