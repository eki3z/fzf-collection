#!/usr/bin/env zsh
# Library file, sourced by fzf-collection.plugin.zsh. No top-level entry point;
# mode 100644.

# Manages the global commands that `uv tool` installs, not a uv project's
# dependencies. Its tool install/list/uninstall/upgrade take no --format json,
# so all three views parse their rows out of the text output with the functions
# below; the moment upstream changes the format, this goes blind.

_uvf() {
  uv "$@"
}

# ---- List queries: emit name<TAB>rest ----

# A `uv tool list` top-level line is `name v1.2.3`; the `- exe` lines right
# after it are the tool's executables (one per line, possibly several, possibly
# none). The top-level line grows bracketed annotations with --show-*:
#   v0.1.0 [required: ==0.1.0] [CPython 3.14.7] [latest: 0.16.9] (/path/to/env)
# So truncate at the first ` [`: the annotations stay out of the columns,
# otherwise version would come out as `1.0.0]`.

# The `[` in the truncation pattern has to be escaped as \[ : in a parameter
# expansion pattern `[` opens a bracket expression, so ${line%% [*} is read as
# an unterminated one -- every line reports "bad pattern" and the whole list
# ends up empty.

# When no tool is installed, uv prints "No tools installed" on **stderr**, so
# 2>/dev/null leaves this naturally empty, and the driver prints
# "Nothing to show." instead.
_uvf_list_installed() {
  local line
  local -a f
  uv tool list 2>/dev/null | while IFS= read -r line; do
    [[ $line == '- '* ]] && continue
    line=${line%% \[*}
    f=(${(z)line})
    (( ${#f} >= 2 )) || continue
    # The top-level line is `name v1.2.3`: uv prefixes the version with a v, and
    # dropping it lines up with pipf / npmf.
    print -r -- "${f[1]}${_FC_TAB}${f[2]#v}"
  done
}

# `uv tool list --outdated` lists only what has an update; anything already
# current never appears (since uv 0.11.0). The line shape is the same as above,
# with only a `[latest: X]` added at the end, so X has to be taken off before
# the annotations are truncated.

# One known false positive: a tool installed from git. uv compares its version
# against the same-named PyPI package and answers with a version number that has
# nothing to do with that checkout, and upgrade then only says "Nothing to
# upgrade". Deliberately not detected: detecting it would mean reading each
# tool's uv-receipt.toml, and a tool installed from the index never takes that
# branch.
_uvf_list_outdated() {
  local line latest
  local -a f
  uv tool list --outdated 2>/dev/null | while IFS= read -r line; do
    [[ $line == '- '* ]] && continue
    latest=''
    if [[ $line == *'[latest: '* ]]; then
      latest=${line##*'[latest: '}
      latest=${latest%%']'*}
    fi
    line=${line%% \[*}
    f=(${(z)line})
    (( ${#f} >= 2 )) || continue
    # The same four columns as pipf / npmf: name | current | => | latest.
    print -r -- "${f[1]}${_FC_TAB}${f[2]#v}${_FC_TAB}=>${_FC_TAB}${latest}"
  done
}

# uv has no search subcommand, so the only source is the simple index. The whole
# chain has to stay inside C programs: the index page is 870k lines (about 45MB
# on pypi.org). `grep -o` prints each anchor in a line on its own, which is
# exactly the "emit one at a time" semantics of a per-line while digging out
# `>…</a>`, while a greedy `sed` can only emit the last match per line.

# The index is ${_UVF_INDEX:-$_FC_PYPI_INDEX}, pypi.org by default, with the
# environment variable as an override. The trailing slash has to be appended by
# hand after `}`: a URL without one 301s to the copy with one, and curl without
# -L does not follow, so what comes back is a 169-byte redirect page with not
# one package name in it.
_uvf_list_available() {
  curl -s "${_UVF_INDEX:-$_FC_PYPI_INDEX}/" \
    | grep -o '>[^<]*</a>' \
    | sed -e 's/^>//' -e 's|</a>$||'
}

# **What comes back cannot be guaranteed to be a tool**: the vast majority of
# packages on the index ship no entry point, uv fails to install them and
# returns 2, and the driver reports that as it stands. install is not a mutating
# action, so a failed row stays in the list and can be swapped for another.

# The PyPI JSON API, for list-versions / info / deps / homepage. The root is
# ${_UVF_PYPI_JSON:-$_FC_PYPI_JSON_BASE}, with the environment variable as an
# override.

# Deliberately **not** following _UVF_INDEX: a mirror's JSON snapshot can be
# very stale (measured: tuna's /pypi/ruff/json was still 0.5.7 while PyPI was
# at 0.16.9), and listing versions off a stale snapshot makes rollback offer a
# pile of options that cannot be installed. search only scrapes names and does
# not care how fresh they are, so that one does use the mirror.
_uvf_pypi() {         # $1=pkg $2=jq filter
  curl -fsS "${_UVF_PYPI_JSON:-$_FC_PYPI_JSON_BASE}/$1/json" 2>/dev/null | jq -r "$2"
}

# uv has no per-tool show (`uv tool list` can only dump the whole table), so
# that one block is cut out of the table by name: the top-level line plus its
# executable lines, for info to use.
_uvf_show_entry() {   # $1=pkg -> the tool's raw block in uv tool list
  local pkg=$1 line take=0
  while IFS= read -r line; do
    if [[ $line == '- '* ]]; then
      (( take )) && print -r -- "$line"
      continue
    fi
    take=0
    [[ ${line%% *} == "$pkg" ]] || continue
    take=1
    print -r -- "$line"
  done
}

# ---- Versions: explicit parameters ----

# The available versions can only come from the PyPI JSON releases -- uv has no
# equivalent of `index versions`. Two traps: the **key order of releases is not
# the upload order** (ruff's 0.16.9 sits at position 361 of 425 keys, with
# 0.9.x at the end), so it has to be sorted by upload_time; and a version whose
# array is empty has been yanked.
_uvf_version_list() {
  _uvf_pypi "$1" '[.releases | to_entries[] | select(.value | length > 0)
                   | {v: .key, t: (.value | map(.upload_time) | max)}]
                 | sort_by(.t) | reverse | .[].v'
}

# Whether it is installed is looked up in uv's own table, the same data the
# manage list uses.
_uvf_version_current() {
  local line
  while IFS= read -r line; do
    [[ ${line%%$'\t'*} == "$1" ]] || continue
    print -r -- "${line#*$'\t'}"
    return 0
  done < <(_uvf_list_installed)
}

# Measured: `uv tool install pkg==ver` works both ways. Installing a lower
# version is a downgrade and needs no --force; installing a higher one is an
# upgrade. It is also the only one of the three mutating actions that can
# change the version.
_uvf_version_install() {
  _uvf tool install "$1==$2"
}

# ---- Action adapters ----

# All three mutating actions are `uv tool <action> <package name>`, the same
# shape, so passing them through natively is enough. info / deps / homepage /
# rollback have their own keys in the registry and never land here.
_uvf_act() { _uvf tool "$1" "$2" }

# uv's own section: if the tool is installed it gives the path, the version
# specifier and the Python version, and if not it says so plainly. The summary
# and requires-python can only be asked of PyPI, so the two halves are glued
# together.
_uvf_info() {
  local block
  block=$(uv tool list --show-paths --show-version-specifiers --show-python 2>/dev/null \
    | _uvf_show_entry "$1")
  if [[ -n $block ]]; then
    print -r -- "$block"
  else
    print -r -- "Not installed: $1"
  fi
  print -r -- ''
  # grep -v ': $' drops the fields it cannot fetch (ruff has no requires_dist
  # and the like), otherwise every info comes with four empty labels.
  _uvf_pypi "$1" '.info
                 | "version: \(.version // "")",
                   "summary: \(.summary // "")",
                   "requires-python: \(.requires_python // "")",
                   "home-page: \(.project_urls.Homepage // .home_page // .project_url // "")"' \
    | grep -v ': $'
}

# For an installed tool, read its own venv -- that is the set of dependencies
# the tool actually got (including the extras installed with --with, which is
# exactly the part `uv tool list --outdated` does not check). For a tool that is
# not installed, fall back to requires_dist.
_uvf_deps() {
  local pkg=$1 py
  # Deliberately not `local x=$(...)`: that swallows the exit code, so the `||`
  # after it never fires when uv is missing.
  py="$(_uvf tool dir)/$pkg/bin/python"
  if [[ -x $py ]]; then
    _uvf pip freeze --python "$py"
  else
    _uvf_pypi "$pkg" '.info.requires_dist // [] | .[]'
  fi
}

_uvf_homepage() {
  _fc_homepage "$(_uvf_pypi "$1" '.info | .project_urls.Homepage // .home_page // .project_url // ""')"
}

_uvf_rollback() { _fc_rollback uv "$1" }

# ---- Registry ----

_FC_REG+=(
  'uv:title'          'Uv'
  'uv:requires'       'uv'
  'uv:views'          'outdated search manage'
  'uv:fallback'         '_uvf_act'

  'uv:outdated'       '_uvf_list_outdated'
  'uv:outdated:title' 'Uv Tool Outdated'
  'uv:outdated:fzf-opts'   '--tiebreak=index'
  'uv:outdated:actions' 'upgrade uninstall rollback homepage deps info'
  'uv:outdated:cols'  'name have sep want'

  'uv:search'         '_uvf_list_available'
  'uv:search:title'   'Uv Tool Search'
  # search lists **every** package on the index and the vast majority are not
  # tools, so uninstall is meaningless for them. With no reachable mutating
  # action this view takes the streaming path (see _fc_view_streamable in
  # base.zsh): 870k lines never land in zsh memory, and every return to the list
  # re-scrapes them.
  'uv:search:actions' 'install rollback homepage deps info'
  'uv:search:cols'    'name'

  'uv:manage'         '_uvf_list_installed'
  'uv:manage:title'   'Uv Tool Manage'
  'uv:manage:actions' 'uninstall rollback homepage deps info'
  'uv:manage:cols'    'name have'

  # upgrade only appears in outdated and uninstall only in manage, so the two
  # views never overlap; declaring it once at the eco level is enough and no
  # view-level override is needed.
  'uv:mutating' 'upgrade uninstall'
  'uv:stay'     'homepage deps info'

  'uv:rollback'         '_uvf_rollback'
  'uv:info'             '_uvf_info'
  'uv:deps'             '_uvf_deps'
  'uv:homepage'         '_uvf_homepage'
  'uv:list-versions'     '_uvf_version_list'
  'uv:current-version'  '_uvf_version_current'
  'uv:install-version'  '_uvf_version_install'
)

uvf() {
  _fc_cmd uv
}
