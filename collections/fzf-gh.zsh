#!/usr/bin/env zsh
# 库文件，由 fzf-collection.plugin.zsh source 加载；无顶层入口，模式 100644。

# ---- 列表查询：输出 name<TAB>rest ----

# 整个 session 只查一次：动作菜单会被反复打开。
typeset -g _GHF_USER

_ghf_user() {
  [[ -n $_GHF_USER ]] || _GHF_USER=$(gh api user --jq '.login')
  print -r -- "$_GHF_USER"
}

_ghf_list_repos() {
  gh api "users/$(_ghf_user)/repos" --paginate --jq '.[].name'
}

# ---- 动作适配器 ----

# gh 不是包管理器，没有 rollback / info / deps；仓库详情由 `gh repo view` 自取。
_ghf_act() {
  case $1 in
    delete-repo) gh delete-repo "$(_ghf_user)/$2" ;;
    browse)      gh browse --repo "$(_ghf_user)/$2" ;;
    *)           gh "$1" "$(_ghf_user)/$2" ;;
  esac
}

# ---- 注册表 ----

_FC_REG+=(
  'gh:title'  'Gh'
  'gh:views'  'repos'
  'gh:fallback' '_ghf_act'

  'gh:repos'         '_ghf_list_repos'
  'gh:repos:title'   'Gh Repos'
  'gh:repos:actions' 'delete-repo browse'
  'gh:repos:cols'    'name'

  # 不声明 stay：browse 之后要回列表，不该留在动作菜单里。
  'gh:mutating' 'delete-repo'
)

# 没有 view 菜单，直接进列表。
ghf() {
  _fc_session gh repos
}
