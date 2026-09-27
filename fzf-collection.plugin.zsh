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
    uv
    gem
    gh
    other
  )
fi

source "${0:h:A}/base.zsh"

# 颜色开关。加载时算一次，之后整个 session 不再改。
#
# 为什么不能放在显示层判：显示层的 stdout 是通向 fzf 的管道，那里的
# [[ -t 1 ]] 恒为 false，会把颜色全部关掉。真正决定「输出给谁看」的是
# 这个文件的 stdout —— 也就是用户敲命令时那个终端。
#
# 优先级（显式设置最高，其余按 no-color.org 的约定）：
#   FZF_COLLECTION_COLOR=0|1  >  NO_COLOR 非空  >  TERM 为空或 dumb
#   >  [[ -t 1 ]]
#
# 关闭时 _fzf_prefix 什么都不输出，于是行内容与开启时逐字节相同 ——
# 只是没有转义序列。对齐、补齐、取值都不受影响。
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
