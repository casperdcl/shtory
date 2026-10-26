# shtory

Supercharge bash history.

- logs every command (including path, time & exit code) to `~/.bash_history.$HOSTNAME.jsonl`
- interactive search
- serverless sync via `ssh`

All in under 500 lines in single bash script.

## Subcommands

### install / update

Drop inside `$PATH` and install:

```bash
curl -fsSLo ~/.local/bin/shtory https://raw.githubusercontent.com/casperdcl/shtory/main/shtory
shtory install
```

This appends a `shtory` block to `~/.bashrc`.

> [!TIP]
> To skip logging any commamds matching a regex, add to `~/.bashrc`:
> ```bash
> export SHTORY_SKIP='passw|secret'
> ```

### search

Interactively search for past commands.

```bash
shtory search [options] [<query>...]
```

- `-h`, `--hostname <HOST>`: glob filter by host (default `*`)
- `-c`, `--cwd`: filter to current path (`$PWD`)
- `-s`, `--sort <ORDER>`: `newest` (default), `oldest`, `count` (most common)
- `-n`, `--limit <N>`: max results (default 100 interactive, 1000 non-interactive)
- `-z`, `--zero` / `-Z`, `--nonzero`: exit code filter

`query`:

- case-insensitive PCRE
- on TTY with no query, search is interactive
  + using `fzf` if available

### hostname

Print or override the hostname used by `shtory` locally (`export SHTORY_HOSTNAME` in `~/.bashrc`).

```bash
shtory hostname [<host>]
```

`${SHTORY_HOSTNAME:-$HOSTNAME}` determines which history JSONL file is written and searched.

### sync

Sync histories across multiple systems over `ssh`.

```bash
shtory sync [<host>...]
```

Pulls every host, merges differences (`jq` union), then pushes.

Any discrepancies between local & remote host files are merged with `jq`.

## stats

Per-host command count, time ranges, nonzero exit count.

```bash
shtory stats
```

## compact

Deduplicate & keep newest `n` commands per file.

```bash
shtory compact <n>
```

## Alternatives

| tool | storage | sync | search | notes |
|---|---|---|---|---|
| bashhub | cloud DB (server) | built-in | web + `bh` CLI | the inspiration; needs an account, history leaves your machine |
| atuin | SQLite | E2EE (server or key) | TUI, FTS, scopes | most featureful; binary + server, heaviest footprint |
| hstr | plain `.bash_history` | none | TUI, frequency/recency ranking | great suggest-box, but records no context (no exit code, cwd or time) |
| hishtory | SQLite | E2EE via sops | SQL queries | context-rich, but Rust binary + sops/sops-server setup |
| McFly | SQLite | built-in (encrypted) | neural-ranked ctrl-r | polished, but binary + sync server |
| **shtory** | **per-host JSONL** | **rsync over ssh** | **interactive, jq/regex** | **one bash file, no binaries, no server, no keys to exchange; history never leaves your own machines** |
