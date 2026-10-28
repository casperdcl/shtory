# shtory

[![CI](https://github.com/casperdcl/shtory/actions/workflows/ci.yml/badge.svg)](https://github.com/casperdcl/shtory/actions/workflows/ci.yml)

Supercharge bash history.

- logs every command (including path, time & exit code) to `~/.bash_history.$HOSTNAME.jsonl`
- interactive search
- serverless sync via `ssh`

All in a pure bash script.

## Subcommands

### install / update

Place on `$PATH` and install:

```bash
echo 'export SHTORY_HOSTNAME=$HOSTNAME' >> ~/.bashrc; . ~/.bashrc # optional
curl -fsSLO --output-dir ~/.local/bin/ https://raw.githubusercontent.com/casperdcl/shtory/main/{tui-,}shtory
shtory install --import
```

- `--import`: also include existing `~/.bash_history` (with no path/time/exit code info)

This appends a `shtory` block to `~/.bashrc`.

> [!TIP]
> To skip logging any commands matching a regex, use `SHTORY_SKIP`; e.g. add to `~/.bashrc`:
>
> ```bash
> export SHTORY_SKIP='export .*(KEY|TOKEN).*=.+'
> ```

### search

Interactively search for past commands.

```bash
shtory search [options] [<query>...]
```

- `-h`, `--hostname <name>`: glob filter by host (default `*`)
- `-H`, `--localhost`: filter to current machine
- `-c`, `--cwd`: filter to current path (`$PWD`)
- `-s`, `--sort <order>`: `newest` (default), `oldest`, `count` (most common)
- `-n`, `--limit <n>`: max results default: 9999 in `tui-shtory`, 0 (unlimited) otherwise
- `-z`, `--zero` / `-Z`, `--nonzero`: exit code filter

`query`:

- case-insensitive PCRE
- on TTY with no query, search is interactive
  + using `fzf` if available; bundled `tui-shtory` otherwise

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

Pulls every remote host, merges differences (`jq` union), then pushes.

- `--self`: don't avoid overwriting a remote host's own history file with any local copy of it
- `--compact <n>`: after pulling & merging, `compact` each file before pushing (implies `--self`)

`remote host`:

- when unspecified, auto-detect remote host(s) via `~/.bash_history.*.jsonl` names
- a corresponding hostname should exist in `~/.ssh/config`
  - :warning: this should match the remote host's own `shtory hostname`, otherwise auto-detection won't work correctly

## stats

Per-host command count, time ranges, nonzero exit count; or the most frequent commands/dirs.

```bash
shtory stats [--cmd <n>] [--dir <n>]
```

## compact

Deduplicate & keep newest `n` commands per file.

```bash
shtory compact <n>
```

> [!NOTE]
> To persist compactions when syncing to multiple hosts, use `shtory sync --compact <n>` instead.

## Alternatives

tool | storage | sync | search | notes
-- | -- | -- | -- | --
[![shtory](https://img.shields.io/github/stars/casperdcl/shtory?label=shtory)](https://github.com/casperdcl/shtory) | **per-host JSONL** | **serverless** `rsync` over **ssh** | TUI | **one bash file, no web auth, history never leaves your own machines**
[![bashhub](https://img.shields.io/github/stars/rcaloras/bashhub-client?label=bashhub)](https://github.com/rcaloras/bashhub-client) | unknown ([closed-source](https://github.com/rcaloras/bashhub-client/issues/47)) | built-in | basic, [10k limit](https://github.com/rcaloras/bashhub-client/issues/118) | python client
[![atuin](https://img.shields.io/github/stars/atuinsh/atuin?label=atuin)](https://github.com/atuinsh/atuin) | SQLite | E2EE | TUI, FTS, scopes | binary + server
[![hstr](https://img.shields.io/github/stars/dvorka-oss/hstr?label=hstr)](https://github.com/dvorka-oss/hstr) | `.bash_history` | none | TUI | no context (exit code/cwd/time)
[![hishtory](https://img.shields.io/github/stars/ddworken/hishtory?label=hishtory)](https://github.com/ddworken/hishtory) | SQLite | SOPS E2EE | SQL | binary + server
[![McFly](https://img.shields.io/github/stars/cantino/mcfly?label=McFly)](https://github.com/cantino/mcfly) | SQLite | none | neural-ranked | binary

## Credits

[![git-fame](https://git-fame.cdcl.ml/gh/casperdcl/shtory?auth=share)](https://git-fame.cdcl.ml/gh/casperdcl/shtory?auth=share)

Also thanks to [dylanaraps/writing-a-tui-in-bash](https://github.com/dylanaraps/writing-a-tui-in-bash) & [fff](https://github.com/dylanaraps/fff) for TUI [pointers](https://xkcd.com/138/).
