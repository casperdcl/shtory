# shtory

[![CI](https://github.com/casperdcl/shtory/actions/workflows/ci.yml/badge.svg)](https://github.com/casperdcl/shtory/actions/workflows/ci.yml)

Bash history the [UNIX way](https://en.wikipedia.org/wiki/Unix_philosophy): shell scripts using just [coreutils](https://en.wikipedia.org/wiki/GNU_Core_Utilities)/[`jq`](https://github.com/jqlang/jq)/[`fzf`](https://github.com/junegunn/fzf).

- logs every command (including path, time & exit code) to `~/.bash_history.$HOSTNAME.jsonl`
- interactive search
- serverless efficient merge/sync via `rsync`/`ssh`

## Subcommands

### install / update

Place on `$PATH` and install:

```bash
echo 'export SHTORY_HOSTNAME=$HOSTNAME' >> ~/.bashrc; . ~/.bashrc # optional
curl -fsSLO --output-dir ~/.local/bin/ https://raw.githubusercontent.com/casperdcl/shtory/main/{tui-,}shtory
shtory install --import
```

- `--import`: also include existing `~/.bash_history` (with no path/time/exit code info)

A `shtory` block is upserted in `~/.bashrc` (hook, keybinding & tab completion).

> [!TIP]
> To skip logging any commands matching a regex, use `SHTORY_SKIP`; e.g. add to `~/.bashrc`:
>
> ```bash
> export SHTORY_SKIP='(KEY|TOKEN).*=.+'
> ```

### search

Interactively search for past commands.

```bash
shtory search [options] [<query>...]
```

- `-h`, `--hostname <name>`: glob filter by host (default `*`)
- `-H`, `--localhost`: filter to current machine
- `-c`, `--cwd`: filter to current path (`$PWD`)
- `-s`, `--sort <order>`: `frecency` (default; count×recency 30d halflife decay), `newest`, `oldest`, `count` (frequency)
- `-n`, `--limit <n>`: max results, default 0 (unlimited)
- `-z`, `--zero` / `-Z`, `--nonzero`: exit code filter

`query`:

- case-insensitive regex
- on TTY with no query, search is interactive
  + using `fzf` if available

> [!NOTE]
> <kbd>Ctrl</kbd><kbd>r</kbd> is the default interactive trigger (overriding the normal `history` trigger); equivalent config in `~/.bashrc`:
>
> ```bash
> export SHTORY_KEY='\C-r'
> ```

### hostname

Print or override the hostname used by `shtory` locally (`export SHTORY_HOSTNAME` in `~/.bashrc`).

```bash
shtory hostname [<host>]
```

`${SHTORY_HOSTNAME:-$HOSTNAME}` determines which history JSONL file is written and searched.

### sync

Sync histories across multiple systems over `ssh`.

```bash
shtory sync [--compact <n>] [--self] [<remote host>...]
```

Pulls every remote host, merges differences, then pushes.

- `--compact <n>`: after pulling & merging, `compact` each file before pushing (implies `--self`)
- `--self`: don't avoid overwriting a remote host's own history file with any local copy of it

`remote host`:

- when unspecified, auto-detect remote host(s) via `~/.bash_history.*.jsonl` names
- a corresponding hostname should exist in `~/.ssh/config`
  - :warning: this should match the remote host's own `shtory hostname`, otherwise auto-detection won't work correctly

### stats

Per-host command count, timeline, most frequent executed.

```bash
shtory stats [--timeline] [--cmd <n>] [--dir <n>]
```

- `--cmd`, `--dir <n>`: show `n` most frequent commands/directories
- `--timeline`: if `SHTORY_GIST_ID` is set, also pushes the histogram to `SHTORY_GIST_FILE` (default `shtory.stats`) via `gh` for display via e.g. [svgist](https://github.com/casperdcl/svgist.cdcl.ml) embeds: \
![](https://svgist.cdcl.ml/0bfb38f71908213bd251765c066343a2?grid=1)

### compact

Deduplicate & keep newest `n` commands per file.

```bash
shtory compact <n>
```

> [!NOTE]
> To persist compactions when syncing to multiple hosts, use `shtory sync --compact <n>` instead.

## Configuration

env var | effect
-- | --
`SHTORY_TUI=1` | force builtin picker instead of `fzf`
`SHTORY_SAFE=1` | merge via `jq` instead of coreutils (~50x slower but full JSON-compat)
`SHTORY_NOPROGRESS=1` | disable `tqdm` progress
`SHTORY_BASHRC` | (un)install target (default `~/.bashrc`)

## Alternatives

Think your few megabytes of bash history worthy of session IDs, runtime durations, SQL databases, webservers, and 200k+ lines of Rust? Non-POSIX-compliant overkill goodies exist!

tool | storage | sync | search | notes
-- | -- | -- | -- | --
[`shtory`](https://github.com/casperdcl/shtory) | **per-host JSONL** | **serverless** `rsync` over SSH | TUI | **one bash file, no web auth, history never leaves your own machines**
[![atuin](https://img.shields.io/github/stars/atuinsh/atuin?label=atuin)](https://github.com/atuinsh/atuin) | SQLite | E2EE | TUI, FTS, scopes | binary + server
[![McFly](https://img.shields.io/github/stars/cantino/mcfly?label=McFly)](https://github.com/cantino/mcfly) | SQLite | none | neural-ranked | binary
[![hstr](https://img.shields.io/github/stars/dvorka-oss/hstr?label=hstr)](https://github.com/dvorka-oss/hstr) | `.bash_history` | none | TUI | no context (exit code/cwd/time)
[![hishtory](https://img.shields.io/github/stars/ddworken/hishtory?label=hishtory)](https://github.com/ddworken/hishtory) | SQLite | SOPS E2EE | SQL | binary + server
[![bashhub](https://img.shields.io/github/stars/rcaloras/bashhub-client?label=bashhub)](https://github.com/rcaloras/bashhub-client) | unknown ([closed-source](https://github.com/rcaloras/bashhub-client/issues/47)) | built-in | basic, [10k limit](https://github.com/rcaloras/bashhub-client/issues/118) | python client
[![suvadu](https://img.shields.io/github/stars/AppachiTech/suvadu?label=suvadu)](https://github.com/AppachiTech/suvadu) | SQLite | none | TUI, AI/MCP | binary
[![pxh](https://img.shields.io/github/stars/chipturner/pxhist?label=pxh)](https://github.com/chipturner/pxhist) | SQLite | serverless `ssh` | TUI | binary

## Credits

[Things worth writing are worth taking a long time to write.](https://gist.cdcl.ml/the-problem/)
Unit tests & TUI are vibe-coded; but `shtory` itself isn't.

[![git-fame](https://git-fame.cdcl.ml/gh/casperdcl/shtory?auth=share)](https://git-fame.cdcl.ml/gh/casperdcl/shtory?auth=share)

Also thanks to [dylanaraps/writing-a-tui-in-bash](https://github.com/dylanaraps/writing-a-tui-in-bash) & [fff](https://github.com/dylanaraps/fff) for TUI [pointers](https://xkcd.com/138/).
