#!/usr/bin/env zsh
# 上面这行是文件元数据（供编辑器与格式化工具识别），不是解释器指令。
# 本文件是库文件，由 fzf-collection.plugin.zsh 以 source 方式加载。
# 它仅含函数定义、无顶层入口，即使赋予执行权限直接运行也只会是空操作，
# 且缺少 base.zsh 的依赖必然失败。文件模式保持 100644，不要 chmod +x。

# ---- 列表查询：输出 name<TAB>rest ----

# 登录用户名在整个 session 里只查一次：动作菜单可能被反复打开，
# 每次都发一次 `gh api user` 没有意义。
typeset -g _GHF_USER

_ghf_user() {
  [[ -n $_GHF_USER ]] || _GHF_USER=$(gh api user --jq '.login')
  print -r -- "$_GHF_USER"
}

_ghf_list_repos() {
  gh api "users/$(_ghf_user)/repos" --paginate --jq '.[].name'
}

# ---- 动作适配器 ----

# gh 不是包管理器，没有 rollback / info / deps 那一套；
# 仓库的完整信息由 `gh repo view` 自己取，所以只注册这两个动作。
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

  # 旧 ghf 没有任何 `return 0` 分支，两个动作做完都回到列表，
  # 所以 loop 是空的：browse 不会把动作菜单留在原地。
  'gh:mutating' 'delete-repo'
)

ghf() {
  # 旧 ghf 没有 view 菜单，直接就是仓库列表，所以绕过 _fc_cmd
  # 的选单步骤，只登记一个 view 并直接进入。
  _fc_session gh repos
}
