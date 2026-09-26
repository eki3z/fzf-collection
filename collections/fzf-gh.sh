#!/usr/bin/env zsh
# 上面这行是文件元数据（供编辑器与格式化工具识别），不是解释器指令。
# 本文件是库文件，由 fzf-collection.plugin.zsh 以 source 方式加载。
# 它仅含函数定义、无顶层入口，即使赋予执行权限直接运行也只会是空操作，
# 且缺少 base.sh 的依赖必然失败。文件模式保持 100644，不要 chmod +x。

ghf() {
  local tmpfile user header

  header=$(_fzf_header)
  tmpfile=$(_fzf_tmp_create)
  user=$(gh api user --jq '.login')

  if [ ! -e "$tmpfile" ]; then
    touch "$tmpfile"
    inst=$(
      gh api users/"$user"/repos --paginate --jq '.[].name' \
        | _fzf_tmp_write
    )
  else
    inst=$(_fzf_tmp_read)
  fi

  if [ -n "$inst" ]; then
    subcmd=$(echo "delete-repo\nbrowse" | _fzf_read)
    if [ -n "$subcmd" ]; then
      for f in $(echo "$inst"); do
        case $subcmd in
          delete-repo)
            gh "$subcmd" "$user/$f" && _fzf_tmp_shift "$f"
            ;;
          browse)
            gh browse --repo "$user/$f"
            ;;
          *) return 0 ;;
        esac
      done
    fi
  else
    rm -f "$tmpfile" && return 0
  fi

  ghf

}
