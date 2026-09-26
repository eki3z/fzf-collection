# fzf-collection

[![GitHub license](https://img.shields.io/github/license/eki3z/fzf-collection)](https://github.com/eki3z/fzf-collection/blob/master/LICENSE)

A collection of commands to enhance commandline with [FZF](https://github.com/junegunn/fzf)

<!-- markdown-toc start -->

## Contents

- [fzf-collection](#fzf-collection)
  - [Install](#install)
    - [Manual](#manual)
    - [Oh-My-Zsh](#oh-my-zsh)
  - [Requirements](#requirements)
  - [Commands](#commands)
    - [brewf](#brewf)
    - [npmf](#npmf)
    - [pnpmf](#pnpmf)
    - [pipf](#pipf)
    - [gemf](#gemf)
    - [ghf](#ghf)
    - [pathf](#pathf)
    - [envf](#envf)
  - [Environment](#environment)
    - [FZF_COLLECTION_MODULES](#fzf_collection_modules)
    - [FZF_COLLECTION_OPTS](#fzf_collection_opts)
    - [_ENVF_VALMAX](#_envf_valmax)
    - [_PKG_COLSEP](#_pkg_colsep)
  - [Development](#development)
  - [Todo](#todo)

<!-- markdown-toc end -->

## Install

### Manual

First, clone this repository.

```sh
git clone https://github.com/eki3z/fzf-collection.git
```

Then add the following line to your `~/.zshrc` .

```sh
source /path/to/fzf-collection.plugin.zsh
```

### Oh-My-Zsh

Clone this repository to custom plugin directory

```sh
git clone https://github.com/eki3z/fzf-collection.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-collection
```

To start using it, add the fzf-collection plugin to your plugins array in `~/.zshrc`:

```diff
- plugins=(...)
+ plugins=(... fzf-collection)
```

## Requirements

The shell code is zsh-only. It needs no perl and no `column`, and nothing
beyond `fzf` at load time.

| Command | Requires |
| --- | --- |
| all commands | `fzf` |
| `brewf` | `brew`, `grep`. `git` only for `rollback`; `find` and `dirname` only for the `unpin` action |
| `npmf`, `pnpmf` | `npm` / `pnpm`, `jq`, and `all-the-package-names` plus `cut` for `search` |
| `pipf` | `pip` or `pip3`, `jq`, `curl` plus `grep` and `sed` for `search`. `pip-autoremove` is offered as an extra action when installed |
| `gemf` | `gem` |
| `ghf` | `gh`, authenticated. No external `jq` — `gh api --jq` is built in |
| `pathf` | `find` with `-printf`, so GNU or Homebrew findutils, not BSD, plus `uniq` |
| `envf` | nothing beyond `printenv` and `sort` |
| `info` / `deps` output | `less`, if present — otherwise the output is printed as-is |
| `homepage` action | `open`, if present — otherwise the URL is printed |

`jq` parses the `--json` output of `outdated`, `manage`, `deps` and
`rollback` for npm, pnpm and pip. Their `search` view does not use it.

`pipf`'s `search` scrapes the index page that `pip config get
global.index-url` points at, so it needs `curl` and network access. The
page holds 871,000 lines; the links are pulled out with `grep -o` and
`sed` so that no shell loop ever walks them.

Without `all-the-package-names`, `npmf` and `pnpmf` stop immediately with
a message rather than running with a broken view. Everything else degrades
quietly: a missing `jq` leaves the affected views empty, and a missing
`pip-autoremove` just drops that one action.

## Commands

Each `*-f` command picks a view, then picks an action, and loops: after
an action runs, the finished rows are dropped from the in-memory list and
the rest stays. Nothing is ever written to disk.

Most views hold the list in memory, query it once, and drop rows from it as
actions finish. A view that lists every package name cannot: npm's and
pnpm's `search` see 4.5 million names, and a shell loop over that many
lines is quadratic, so the list would take hours to reach fzf. Those views
have no action that removes rows, so they need no memory at all — the query
streams into fzf through `cut` and `grep`, and it is re-run each time the
view comes back. Either way nothing is written to disk.

### brewf

`brewf`: `outdated` `search` `manage` `pinned` `tap`

`pinned` lists pinned formulae; `rollback` re-pins afterwards based on
the actual pinned state, so rolling back from any view leaves pinning as
it was.

### npmf

`npmf`: `outdated` `search` `manage`

`search` needs the package list; see [Requirements](#requirements).

### pnpmf

`pnpmf`: `outdated` `search` `manage`

`search` needs the package list; see [Requirements](#requirements).

### pipf

`pipf`: `outdated` `search` `manage`

### gemf

`gemf`: `outdated` `search` `manage`

### ghf

`ghf`: `repos`

### pathf

`pathf`: find an executable in `$PATH`. `pathf -d` prints its directory
instead of the full path.

### envf

`envf`: pick an environment variable and print `NAME = value`.

The displayed value is truncated so that no row exceeds the screen —
`PATH` alone is often several times wider than the terminal, and fzf can
only truncate and scroll a line that wide, which makes the list look
misaligned. The value you get on stdout is always the complete one.

## Environment

### FZF_COLLECTION_MODULES

Setting `FZF_COLLECTION_MODULES` to load modules. By default, all modules are loaded.

```sh
FZF_COLLECTION_MODULES=(
  brew
  npm
  pnpm
  pip
  gem
  gh
  other
  )
```

### FZF_COLLECTION_OPTS

Setting `FZF_COLLECTION_OPTS` to customize fzf options.

```sh
# set options if needed, default value is as below :
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
```

`--ansi` is required by the views that colour their rows. `pathf` and
`envf` pass it themselves rather than relying on this list, so overriding
`FZF_COLLECTION_OPTS` cannot silently break their colours.

### _ENVF_VALMAX

`envf` only. Number of characters of an environment variable's value shown
in the list. Defaults to `80`. Lower it if you use a narrow terminal.

```sh
export _ENVF_VALMAX=60
```

### _PKG_COLSEP

All `*-f` views. Number of spaces between columns. Defaults to `5`.

```sh
export _PKG_COLSEP=3
```

## Development

```sh
tests/run.sh             # behaviour diff against tests/expected/baseline.txt
tests/run.sh --hygiene   # variable-hygiene lint
tests/run.sh --record    # re-record the baseline after an intended change
```

The lint exists because three zsh behaviours fail silently and write to
stdout, which almost every function here captures:

- a scalar `local NAME` inside a loop body
- a scalar `local NAME` with no assignment when `NAME` is already local
- `local x=$(cmd)`, whose exit status is swallowed, so a following `||`
  never fires

`zsh -n` checks none of these.

## Todo

- [ ] Switch the two-level view/action menus to a single screen with `--expect`
- [ ] Replace the `info` / `deps` pager step with a `--preview` pane
- [ ] Add zsh completion, so `brewf <TAB>` lists views
