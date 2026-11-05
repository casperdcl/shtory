# working on the code

- `shtory` speed matters (especially for `search` and `sync`)
- CI runs `./test.bash` (so no TTY) & `shellcheck --severity=warning -x shtory tui-shtory test.bash test/*.sh`
  + `test.bash` sources subtests from `test/*.sh`
  + `test/{hostname,stats}.sh` need `test/search.sh`'s `$S`
  + when making local changes, avoid running the full `test.bash` (slow) if subtest(s) can be used instead
  + `test.bash` is TTY-less by design: the pickers (numbered loop, tui-shtory) are covered by `script(1)` pty tests; the keybinding (`bind -x`) and post-insertion editing are not - verify those on a real pty before claiming they work
- `tui-shtory`: drop-in `fzf`
  + rows on stdin, selected row on stdout, rc 0/130/1, keys typed while a slow search query runs can leak (same as `fzf`, accepted - do not "fix")
  + self-contained (no sourcing between `shtory`)
  + picker chain: `fzf` -> `tui-shtory` (`SHTORY_TUI=1` forces) -> numbered loop
  + frame code encodes Termux terminal quirks (no `\e[K`, termux-app#3549); read its comments before changing rendering
- `kill -WINCH 0` in `__shtory_pick` is load-bearing on this bash build (readline desync after `bind -x` + `READLINE_LINE`); do not remove
- never rewrite/amend/rebase git history unasked

# history file format

One JSON object per line in `~/.shtory/HOST.jsonl` (HOST: `$SHTORY_HOSTNAME` > `~/.shtory/shtory.env` > `$HOSTNAME`):

```json
{"t":1792893841,"d":"/path","e":1,"c":"some && command | line"}
```

- `t` unix seconds, `d` working directory, `e` exit code, `c` full commandline as typed, including pipelines
- hostname is in the filename, not a field
- hook appends; `sync` and `compact` rewrite files (deduped union, t-sorted)
- format stays trivially grep-able, diff-able, rsync-friendly

# caveats

- commands are captured from bash's history list (`history 1` at prompt time), so `HISTCONTROL` is respected (ignoredups/ignorespace/ignoreboth/erasedups), and `history -r` re-reads (new sessions, per-prompt re-reads in `.bash_aliases`) do not re-log the last entry
  + use `SHTORY_SKIP` regex to exclude commands
- history JSONL files are as sensitive as `~/.bash_history` & `~/.zsh_history` (could contain secrets) and `sync` transfers via `rsync` as-is, so ensure ssh config/keys are sane, and keep the files out of any untrusted dotfile sync
- `sync` host detection treats a host as configured iff `ssh -G` resolves it to a `HostName` different from the alias itself
