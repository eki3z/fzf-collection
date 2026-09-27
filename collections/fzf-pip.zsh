#!/usr/bin/env zsh
# 库文件，由 fzf-collection.plugin.zsh source 加载；无顶层入口，模式 100644。

_pipf() {
  pip3 --disable-pip-version-check "$@"
}

# ---- 列表查询：输出 name<TAB>rest ----

# `pip list --format=json` 每项是 {"name": ..., "version": ...}。
_pipf_list_installed() {
  _pipf list --format=json | jq -r '.[] | "\(.name)\t\(.version)"'
}

_pipf_list_outdated() {
  _pipf list --format=json --outdated \
    | jq -r '.[] | "\(.name)\t\(.version)\t=>\t\(.latest_version)"'
}

# 从 pip index 页面抠包名。
_pipf_list_available() {
  # 整条链必须留在 C 程序里：index 页有 87 万行，grep -o + sed 约 0.9s。
  # grep -o 把一行里的每个锚点分别打出来，等价于「一次吐一个」；贪婪匹配的
  # sed 一行只能吐最后一个，所以必须先靠 grep -o 把每个锚点切开。
  curl -s "$(pip config get global.index-url)/" \
    | grep -o '>[^<]*</a>' \
    | sed -e 's/^>//' -e 's|</a>$||'
}

# ---- pip show 字段提取（显式收参） ----

# 从 `pip show` 的输出里取字段，每行一个 `Key: value`，例如
#   Home-page: https://requests.readthedocs.io
#   Requires: certifi, idna, urllib3
# 整行含 "<key>: " 才命中，取冒号后的内容并剥掉残留空白。
_pipf_extract() {
  local line
  _pipf show "$1" 2>/dev/null | while IFS= read -r line; do
    [[ $line == *"$2: "* ]] || continue
    line=${line#*"$2: "}
    _fc_ltrim line
    print -r -- "$line"
    break
  done
}

# ---- 版本相关：显式收参 ----

_pipf_version_list() {
  local line s
  _pipf index versions --pre "$1" 2>/dev/null | while IFS= read -r line; do
    [[ $line == *'Available versions: '* ]] || continue
    s=${line#*'Available versions: '}
    # 换行走 _FC_NL 变量：替换位里的 $'\n' 不求值，会原样输出这四个字符。
    print -r -- "${s//, /$_FC_NL}"
    break
  done
}

_pipf_version_current() {
  _pipf_extract "$1" Version 2>/dev/null
}

_pipf_version_install() {
  _pipf install --user --upgrade --force-reinstall "$1==$2" 2>/dev/null
}

# ---- 动作适配器 ----

_pipf_install() {
  _pipf install --user "$@"
}

_pipf_uninstall() {
  if [[ $1 == pip ]]; then
    print -r -- "Package [pip] can not be uninstalled !"
    return 1
  fi
  # 需要 pip install pip-autoremove。
  if _fc_have_cmd pip-autoremove && [[ $1 != pip-autoremove ]]; then
    pip-autoremove "$1" --yes
  else
    _pipf uninstall --yes "$1"
  fi
}

_pipf_act() {
  case $1 in
    upgrade)   _pipf_install --upgrade "$2" ;;
    uninstall) _pipf_uninstall "$2" ;;
    install)   _pipf_install "$2" ;;
    *)         _pipf "$1" "$2" ;;
  esac
}

_pipf_info() { _pipf show "$1" | _fc_pager }
_pipf_deps() { _pipf_extract "$1" Requires }
_pipf_use() { _pipf_extract "$1" Required-by }
_pipf_homepage() { _fc_homepage "$(_pipf_extract "$1" Home-page)" }
_pipf_rollback() { _fc_rollback pip "$1" }

# ---- 注册表 ----

# 换行用 base.zsh 的 _FC_NL，collection 里不声明全局。

_FC_REG+=(
  'pip:title'          'Pip'
  'pip:views'          'outdated search manage'
  'pip:fallback'         '_pipf_act'

  'pip:outdated'       '_pipf_list_outdated'
  'pip:outdated:title' 'Pip Outdated'
  'pip:outdated:fzf-opts'   '--tiebreak=index'
  'pip:outdated:actions' 'upgrade uninstall rollback deps use info'
  'pip:outdated:cols'  'name have sep want'

  'pip:search'         '_pipf_list_available'
  'pip:search:title'   'Pip Search'
  # search 列的是**还没装**的包，uninstall 在这里没有意义，入口只留在 manage。
  # 因此本视图没有可达的 mutating 动作，走流式路径（见 base.zsh 的 _fc_view_streamable）。
  'pip:search:actions' 'install rollback'
  'pip:search:cols'    'name'

  'pip:manage'         '_pipf_list_installed'
  'pip:manage:title'   'Pip Manage'
  'pip:manage:actions' 'uninstall rollback homepage deps use info'
  'pip:manage:cols'    'name have'

  'pip:mutating'           'uninstall'
  'pip:outdated:mutating'  'upgrade uninstall'
  'pip:stay'           'homepage deps use info'

  'pip:rollback'       '_pipf_rollback'
  'pip:info'           '_pipf_info'
  'pip:deps'           '_pipf_deps'
  'pip:use'            '_pipf_use'
  'pip:homepage'       '_pipf_homepage'
  'pip:list-versions'     '_pipf_version_list'
  'pip:current-version'  '_pipf_version_current'
  'pip:install-version'  '_pipf_version_install'
)

pipf() { _fc_cmd pip }
