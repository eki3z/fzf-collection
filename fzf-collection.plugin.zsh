#!/usr/bin/env zsh
# fzf-collection 的唯一入口，由 oh-my-zsh（或手动 source）加载。
# 下面用 ${0:h:A} 定位本文件并 source body —— 这是 zsh 专有语法。
# body 全部是 zsh 代码，可自由使用 zsh 特性。

# set options if not defined
if [ -z "$FZF_COLLECTION_OPTS" ]; then
  FZF_COLLECTION_OPTS="
  --header-first
  --ansi
  --reverse
  --cycle
  --no-multi
  --sort
  --exact
  --info=inline
  --tiebreak=begin,index
  --bind=change:first,btab:up+toggle,ctrl-n:down,ctrl-p:up
  --bind=ctrl-u:cancel,ctrl-l:jump,ctrl-t:toggle-all,ctrl-v:clear-selection"
fi

if [ -z "$FZF_COLLECTION_MODULES" ]; then
  FZF_COLLECTION_MODULES=(
    brew
    npm
    pnpm
    pip
    gem
    cargo
    gh
    other
  )
fi

source "${0:h:A}/base.zsh"

for f in "${FZF_COLLECTION_MODULES[@]}"; do
  source "${0:h:A}/collections/fzf-${f}.zsh"
done
