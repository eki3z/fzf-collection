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
    - [uvf](#uvf)
    - [gemf](#gemf)
    - [ghf](#ghf)
    - [pathf](#pathf)
    - [envf](#envf)
  - [Environment](#environment)
    - [FZF_COLLECTION_COLOR](#fzf_collection_color)
    - [FZF_COLLECTION_MODULES](#fzf_collection_modules)
    - [FZF_COLLECTION_OPTS](#fzf_collection_opts)
    - [_ENVF_VALMAX](#_envf_valmax)
    - [_FC_COLUMN_GAP](#_fc_column_gap)
    - [_UVF_INDEX](#_uvf_index)
    - [_UVF_PYPI_JSON](#_uvf_pypi_json)
  - [Colours](#colours)
  - [Registry](#registry)
  - [Adding a package manager](#adding-a-package-manager)
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
| `uvf` | `uv`, `jq`, `curl` plus `grep` and `sed`. `outdated` needs network access to the index |
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

`uvf`'s `search` scrapes the same kind of page from `_UVF_INDEX`. Its
`outdated` view is `uv tool list --outdated`, which compares each tool
against the index; the installed and latest versions come back inside the
text output, so there is no `jq` in the list queries. `jq` is used for the
PyPI JSON that `rollback`, `info`, `deps` and `homepage` need. Two things
`uv` itself does not do: the index is not read from `uv.toml` — see
[_UVF_INDEX](#_uvf_index) — and a tool installed from git is reported
against the same-named package on PyPI, so its `latest` is a version you
cannot install from where the tool actually came from.

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

### uvf

`uvf`: `outdated` `search` `manage`

`uvf` is for the global commands `uv tool install` puts on your `PATH`,
not for the dependencies of a uv project.

`outdated` is `uv tool list --outdated` (uv 0.11.0 and later). Tools that
are already current do not appear, so an empty list means there is
nothing to upgrade. It only compares each tool's own version — the extra
requirements passed to `uv tool install --with` are not checked, even
though `upgrade` will move them.

`search` lists the whole index, so most entries are not tools at all;
picking one fails and the row stays in the list. See
[Requirements](#requirements) and [_UVF_INDEX](#_uvf_index).

`deps` reads the tool's own environment when it is installed, which
includes the `--with` requirements, and falls back to what PyPI declares
when it is not.

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

### FZF_COLLECTION_COLOR

`0` or `1`. Whether the lists are coloured. On unless `NO_COLOR` is set,
`TERM` is empty or `dumb`, or stdout is not a terminal — the rules
[no-color.org](https://no-color.org) asks for. Set it to override them.

With colour off, a row is byte-for-byte the coloured row minus the escape
sequences. Alignment, padding and the value a command prints on stdout are
unchanged.

```sh
export FZF_COLLECTION_COLOR=0
```

### FZF_COLLECTION_MODULES

Setting `FZF_COLLECTION_MODULES` to load modules. By default, all modules are loaded.

```sh
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
in the list. Defaults to `_FC_ENVF_WIDTH` in `base.zsh`, currently `80`.
Lower it if you use a narrow terminal, raise it if yours is wide — `PATH`
alone runs to a couple of thousand characters.

```sh
export _ENVF_VALMAX=60
```

### _FC_COLUMN_GAP

All `*-f` views. Number of spaces between columns. Defaults to `5`.

```sh
export _FC_COLUMN_GAP=3
```

### _UVF_INDEX

`uvf` `search` only. The simple index page it scrapes package names from.
Defaults to `_FC_PYPI_INDEX` in `base.zsh`, currently
`https://pypi.org/simple`, and the trailing `/` is added for you — the page
answers 301 without it.

It is **not** read from `uv.toml` or `UV_DEFAULT_INDEX`: `uv` has no
subcommand that prints the index it resolved, so nothing here would stay
in step with your config. Set it yourself when you install through a
mirror.

```sh
export _UVF_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple
```

### _UVF_PYPI_JSON

`uvf` `rollback` / `info` / `deps` / `homepage` only. Base URL of the
PyPI JSON API. Defaults to `_FC_PYPI_JSON_BASE` in `base.zsh`, currently
`https://pypi.org/pypi`.

Deliberately independent of [_UVF_INDEX](#_uvf_index): a mirror's JSON
snapshot can be far behind (Tuna still reported ruff 0.5.7 while PyPI was
on 0.16.9), and these four need current metadata. A stale snapshot makes
`rollback` offer versions that are not installable.

## Colours

_FC_SGR in `base.zsh` is the whole palette: one associative array, keyed by the
*role* a column plays rather than by its colour:

| Role | Used for | Colour |
| --- | --- | --- |
| `name` | the package name, or the whole of a single-column view | none |
| `have` | the installed version, or the description | blue |
| `sep` | connectors such as `=>` | none |
| `want` | the version a mutating action would install | yellow |
| `msg` | the label a message is printed with | blue |

A view declares its columns in the registry with `<eco>:<view>:cols`, space
separated, one role per column: `outdated` is `name have sep want`, `manage`
is `name have`, `search` is `name`. Re-theme every view at once by editing the
palette. A role name that is not in the table is reported once on stderr and
treated as no colour. Nothing else is accepted — a bare SGR parameter like `34`
is not a role name, and neither is `0`; whether a role is coloured is the
palette's answer, not the spec's spelling.

Escape sequences appear in the data, so fzf has to be told about them — see
[`FZF_COLLECTION_OPTS`](#fzf_collection_opts). Alignment is measured on the
uncoloured text: each column is padded first and coloured afterwards, which is
why the padding never has to account for the sequences.

## Registry

Every `*-f` view is a row in one associative array, `_FC_REG` in `base.zsh`.
A collection file is mostly this array plus the functions it names; the driver
in `base.zsh` contains no package-manager logic at all.

Keys have the shape `_FC_REG[<eco>[:<view>]][:<field>]`. A list function is
registered under a two-segment key, an action handler under a two-segment key
too — the same map holds data and code, which is worth knowing before you
invent a field name (see `install-version` below).

Per ecosystem:

| Field | Meaning |
| --- | --- |
| `title` | the name shown in the view menu |
| `views` | the views, space separated |
| `requires` | commands that must exist before a view opens |
| `stay` | actions that leave you in the action menu after they run |
| `mutating` | actions that change state, so a failure stops the batch |
| `fallback` | function receiving `(action, package)` for actions with no handler |
| `list-versions` | function listing every available version, one per line |
| `current-version` | function printing the installed version |
| `install-version` | function installing `package` at `version` |

Per view, `<eco>:<view>` itself is the function that produces the list:

| Field | Meaning |
| --- | --- |
| `title` | the name in the header; falls back to the ecosystem's |
| `actions` | the action menu, space separated; falls back to the ecosystem's |
| `mutating` | overrides the ecosystem's list |
| `cols` | one [colour role](#colours) per column, space separated |
| `fzf-opts` | extra options for fzf in this view |

A list function prints `name<TAB>field<TAB>...`, one row per line, with no
colour and no padding — the display layer does both. An action handler is
registered as `_FC_REG[<eco>:<action>]` and receives the package name. With no
handler, `fallback` gets `(action, package)`.

Two things to know before adding a field. First, a key is always assembled into
a variable and only then used as a subscript: `_FC_REG[$eco:title]` would have
zsh read `:t` as a parameter modifier — `tail` — and return an empty string
without an error. Second, a data key must not be spelled like an action, or
selecting that action dispatches to it: `install` is a real action in `search`,
which is why the version fields are `list-versions`, `current-version` and
`install-version` and not `versions` / `current` / `install`. `t_case_registry`
asserts both.

### requires

`requires` is checked before the view menu opens, and a missing command is named
rather than left to fail later:

```
$ gemf
fzf-collection: missing gem.
  Install gem and try again.
```

The value is space separated, and an item may offer alternatives with `|`, of
which one has to exist — that is how `pipf` declares `pip3|pip`.

`fzf` itself is **not** in the list. Every command needs it, and repeating it in
seven ecosystems would be seven places to forget, so `_fc_require` checks it
alongside whatever the ecosystem declares. `pathf` and `envf` are not
ecosystems and have no registry key; they call `_fc_need` directly, `fzf`
included.

The check does not change any exit code. Every `*-f` command already returns 0
on every path — a cancelled session included — so there is nothing for a
non-zero code to disagree with, and picking 1 for "missing dependency" alone
would only make "you pressed Ctrl-C" and "this never started" tell apart. Run
`gemf` and read the message instead.

## Adding a package manager

A collection is one file under `collections/`, named `fzf-<name>.zsh`, and it
is loaded by `fzf-collection.plugin.zsh` — never on its own, which is why it
does not have to declare anything the driver already declared.

1. **A `<eco>f` function** that calls `_fc_cmd <eco>`, and the name added to
   `FZF_COLLECTION_MODULES` in the plugin entry file.
2. **The registry block**, with `title`, `views` and
   [`requires`](#requires) at minimum.
3. **One list function per view**, printing `name<TAB>...` rows.
4. **`_FC_REG[<eco>:fallback]`**, unless every action has a handler.
5. **The version trio** (`list-versions`, `current-version`, `install-version`)
   only if the ecosystem can install a specific version — that is what makes
   `rollback` work, and `rollback` should be in `actions` only when all three
   are present.

Then:

- `tests/cases.sh` — the view list, key shape and action-dispatch cases read the
  registry, so a new ecosystem shows up there without edits, and a mistake in
  yours shows up as a failure rather than as silence.
- `README.md` — the command, its views, and its external commands. The
  consistency case checks all three, including that every command the code
  calls appears in the requirements table.

## Development

```sh
tests/run.sh             # all gates, plus the behaviour diff against the baseline
tests/run.sh --syntax    # zsh -n
tests/run.sh --hygiene   # variable-hygiene lint
tests/run.sh --nounset   # the same cases under `setopt nounset`
tests/run.sh --record    # re-record the baseline after an intended change
```

The lint exists because three zsh behaviours fail silently and write to
stdout, which almost every function here captures:

- a scalar `local NAME` inside a loop body
- a scalar `local NAME` with no assignment when `NAME` is already local
- `local x=$(cmd)`, whose exit status is swallowed, so a following `||`
  never fires

`zsh -n` checks none of these.

`--nounset` exists for the one class of bug that is syntactically correct,
hygiene-clean, and still fails silently at run time: a reference to a parameter
that may not be set. `_fc_session` used to pass an undeclared `$opt` to
`_fc_feed`, so on a shell with `setopt nounset` every `*-f` command quit after
its first selection while the other three gates stayed green. Read the gate's
result rather than the exit code — under `nounset` zsh reports the problem on
stderr and still returns 0.

## Todo

- [ ] Switch the two-level view/action menus to a single screen with `--expect`
- [ ] Replace the `info` / `deps` pager step with a `--preview` pane
- [ ] Add zsh completion, so `brewf <TAB>` lists views
