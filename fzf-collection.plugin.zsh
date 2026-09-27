#!/usr/bin/env zsh
# 唯一入口，由 oh-my-zsh（或手动 source）加载。${0:h:A} 定位本文件并 source
# 下面的 body，body 全是 zsh 代码。

# set options if not defined
if [[ -z ${FZF_COLLECTION_OPTS:-} ]]; then
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

if [[ -z ${FZF_COLLECTION_MODULES:-} ]]; then
  FZF_COLLECTION_MODULES=(
    brew
    npm
    pnpm
    pip
    uv
    gem
    gh
    other
  )
fi

source "${0:h:A}/base.zsh"

# ---- 颜色开关 ----
#
# 加载时算一次。不能在显示层判：显示层的 stdout 是通向 fzf 的管道，那里的
# [[ -t 1 ]] 恒为 false，会把颜色全关掉。
#
# 优先级：FZF_COLLECTION_COLOR=0|1 > NO_COLOR 非空 > TERM 为空或 dumb > [[ -t 1 ]]。
# 关闭时 _fc_sgr_prefix 不输出任何东西，行内容与开启时逐字节相同，只是没有转义。
typeset -gi _FC_COLOR=1
if [[ -z ${FZF_COLLECTION_COLOR:-} ]]; then
  if [[ -n ${NO_COLOR:-} ]] || [[ ${TERM:-dumb} == dumb ]] || [[ ! -t 1 ]]; then
    _FC_COLOR=0
  fi
else
  [[ ${FZF_COLLECTION_COLOR} == 0 ]] && _FC_COLOR=0 || _FC_COLOR=1
fi

for f in "${FZF_COLLECTION_MODULES[@]}"; do
  source "${0:h:A}/collections/fzf-${f}.zsh"
done
