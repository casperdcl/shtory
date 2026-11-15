#!/usr/bin/env bash
# test: interactive pickers via pty (run via ./test.bash; standalone: bash test/pty.sh)
# skipped if script(1) is unavailable
source ./test/common.sh

echo "# interactive (pty via script(1); skipped if unavailable)"
if ! command -v script >/dev/null 2>&1 || ! script --version >/dev/null 2>&1; then
  echo "SKIP - GNU script missing (-e returns child rc, output copied to stdout, stdin EOF forwarded)"
else
  SC=$(command -v script)
  pty_run() { "$SC" -qec "$1" /dev/null 2>/dev/null; }
  # last content line of a pty capture: drop CR/ESC bytes and CSI parameter text
  lastline() {
    printf '%s\n' "$1" | tr -d '\r\033' | sed 's/\[[0-9;?]*[a-zA-Z]//g' \
      | grep -v '^[[:space:]]*$' | tail -1
  }
  NP=$T/nopath; mkdir -p "$NP" # pty PATH: no fzf/tui-shtory -> numbered loop
  for b in bash sh jq cat stty mkdir; do
    p=$(command -v "$b") && ln -sf "$p" "$NP/$b"
  done
  PTH=$T/pty_home; mkdir -p "$PTH/.shtory"
  printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"git status"}' '{"t":2,"d":"/x","e":0,"c":"git push"}' \
    > "$PTH/.shtory/pty.jsonl"

  # numbered loop: type a pattern, select row 1 (newest match)
  out=$(printf 'git\n1\n' | SHELL=$NP/bash PATH=$NP HOME=$PTH \
    pty_run "$B search" 2>/dev/null | tr -d '\r')
  [[ $(lastline "$out") == *"git push"* ]] && ok "pty: numbered loop selects" || bad "pty: numbered loop selects ($(lastline "$out"))"

  # fzf exits 0 with no output on Enter over an empty list (its contract):
  # cmd_search must treat that as cancel, not as an empty selection
  # (an empty selection wipes the caller's current line via READLINE_LINE='')
  FZH=$T/fz_home; FNP=$T/fzpath; mkdir -p "$FZH/.shtory" "$FNP"
  for b in bash sh jq cat stty awk sleep grep tail cut sort head; do
    p=$(command -v "$b") && ln -sf "$p" "$FNP/$b"
  done
  printf '%s\n' '#!/usr/bin/env bash' 'sleep 1; exit 0' > "$FNP/fzf" # fzf: enter on empty list
  chmod +x "$FNP/fzf"
  : > "$FZH/.shtory/fz.jsonl"
  { sleep 0.5; printf '\r'; sleep 2; } \
    | SHELL=$FNP/bash PATH="$FNP" HOME=$FZH \
    pty_run "$B search" > "$T/fz_out" 2>/dev/null
  assert_rc "fzf: enter on empty list cancels (rc 1, no wipe)" 1 "$?"

  # fzf picker rows: the picker always streams newest-first, regardless of -s
  # (a full pass for cross-file sort is too slow for big histories)
  printf '%s\n' '#!/usr/bin/env bash' \
    'if [[ ${1-} == --version ]]; then echo 0.61.0; exit 0; fi' \
    "cat > $T/fzf_in; exit 130" > "$FNP/fzf"
  chmod +x "$FNP/fzf"
  : > "$T/fzf_in"
  sleep 2 | SHELL=$FNP/bash PATH="$FNP" HOME=$PTH pty_run "$B search" >/dev/null 2>&1
  assert_eq "fzf picker: rows stream newest-first" \
    $'git push\t/x\t0\t1970-01-01 00:00\tpty\ngit status\t/x\t0\t1970-01-01 00:00\tpty' \
    "$(cat "$T/fzf_in")"
  : > "$T/fzf_in"
  sleep 2 | SHELL=$FNP/bash PATH="$FNP" HOME=$PTH pty_run "$B search -s oldest" >/dev/null 2>&1
  assert_eq "fzf picker: -s does not force a full pass (no hang)" \
    $'git push\t/x\t0\t1970-01-01 00:00\tpty\ngit status\t/x\t0\t1970-01-01 00:00\tpty' \
    "$(cat "$T/fzf_in")"

  # tui-shtory: rows from a file (EOF), keys via the pty
  printf 'alpha cmd\nbeta cmd\n' > "$T/tui_rows"
  out=$(printf 'a\n' | SHELL=$NP/bash PATH="$NP:$PATH" HOME=$PTH \
    pty_run "stty rows 20 cols 60 2>/dev/null; $TUI < $T/tui_rows" 2>/dev/null | tr -d '\r')
  [[ $(lastline "$out") == *"alpha cmd"* ]] && ok "pty: tui-shtory filters & selects" || bad "pty: tui-shtory filters & selects ($(lastline "$out"))"

  # tui-shtory streaming: the TUI is interactive before stdin delivers rows
  # (Enter before the row arrives selects nothing; a buffered picker would
  # wait for EOF and select the row)
  cat > "$T/tui_slow.sh" <<'EOF'
#!/usr/bin/env bash
{ sleep 0.5; printf 'gamma cmd\n'; sleep 0.3; } | "$1"
EOF
  out=$( { sleep 0.2; printf '\r'; sleep 1.5; } | \
    SHELL=$NP/bash PATH="$NP:$PATH" HOME=$PTH \
    pty_run "stty rows 20 cols 60 2>/dev/null; bash $T/tui_slow.sh $TUI" 2>/dev/null | tr -d '\r')
  [[ $out == *$'\e[?1049h'* && $out != *"gamma cmd"* ]] && ok "pty: tui-shtory interactive before rows arrive" || bad "pty: tui-shtory interactive before rows arrive"

  # tui-shtory: arrow keys re-render (the inverted row follows sel)
  printf 'alpha x\nbeta x\n' > "$T/tui_rows2"
  out=$( { sleep 0.7; printf '\x1b[A'; sleep 0.3; printf '\r'; } | \
    SHELL=$NP/bash PATH="$NP:$PATH" HOME=$PTH \
    pty_run "stty rows 20 cols 60 2>/dev/null; $TUI < $T/tui_rows2" 2>/dev/null | tr -d '\r')
  [[ $out == *$'\e[7m beta'* ]] && ok "pty: tui-shtory arrow re-renders" || bad "pty: tui-shtory arrow re-renders"

  # tui-shtory --freeze-left: a frozen field wider than the window must clip,
  # not die (a fatal substring error once left the tty raw, alt screen on)
  printf 'averyveryveryverylongcommandword\tx\n' > "$T/tui_rows3"
  out=$( { sleep 0.7; printf 'x'; sleep 0.5; printf '\x1b'; sleep 0.5; } | \
    SHELL=$NP/bash PATH="$NP:$PATH" HOME=$PTH \
    pty_run "stty rows 8 cols 24 2>/dev/null; $TUI --freeze-left=1 < $T/tui_rows3" 2>/dev/null | tr -d '\r')
  [[ $out != *substring* && $out != *unbound* && $out == *"averyveryveryverylongc"* ]] \
    && ok "pty: tui-shtory freeze overflow clips" || bad "pty: tui-shtory freeze overflow clips ($(lastline "$out"))"

  # zsh: ctrl-r zle widget opens the numbered loop (keys via /dev/tty)
  # and inserts the selection; TERM=linux because Termux has no xterm terminfo
  if command -v zsh >/dev/null 2>&1; then
    ZP=$T/zpty_home; mkdir -p "$ZP/bin" "$ZP/.shtory"
    for b in bash sh jq cat stty mkdir; do
      p=$(command -v "$b") && ln -sf "$p" "$ZP/bin/$b"
    done
    ln -sf "$PWD/shtory" "$ZP/bin/shtory"
    printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"echo zsel one"}' '{"t":2,"d":"/x","e":0,"c":"echo zsel two"}' \
      > "$ZP/.shtory/zpty.jsonl"
    SHELL=/usr/bin/zsh SHTORY_ZSHRC=$ZP/.zshrc "$B" install >/dev/null
    out=$( { sleep 0.5; printf '\x12'; sleep 1.5; printf 'echo\n'; sleep 1.5; printf '1\n'; sleep 1.5; printf '\r'; sleep 1.5; printf 'exit\n'; sleep 0.5; } \
      | HOME=$ZP PATH="$ZP/bin" TERM=linux \
      pty_run "$(command -v zsh) -i" 2>/dev/null | tr -d '\r' )
    [[ $out == *"zsel two"* ]] && ok "pty: zsh ctrl-r widget inserts & runs" || bad "pty: zsh ctrl-r widget inserts & runs ($(lastline "$out"))"

    # zsh exit flush: a pending command (precmd didn't run) is flushed by the zshexit hook
    ZF=$T/zf_home; mkdir -p "$ZF/bin" "$ZF/.shtory"
    for b in bash sh jq cat stty mkdir; do
      p=$(command -v "$b") && ln -sf "$p" "$ZF/bin/$b"
    done
    SHELL=/usr/bin/zsh SHTORY_ZSHRC=$ZF/.zshrc HOME=$ZF "$B" install >/dev/null
    rm -f "$ZF"/.shtory/*.jsonl
    { sleep 0.3; printf 'echo a\n'; sleep 0.3; printf 'true && exit\n'; sleep 0.5; } \
      | HOME=$ZF PATH="$ZF/bin" TERM=linux \
      pty_run "$(command -v zsh) -i" >/dev/null 2>&1
    assert_eq "zsh exit flush: compound ending in exit is logged once" \
      $'echo a 0\ntrue && exit 0' "$(jq -r '"\(.c) \(.e)"' "$ZF"/.shtory/*.jsonl 2>/dev/null)"
  fi

  # shell-exit flush: a command whose next action exits the shell is never logged
  # (no prompt follows); the EXIT trap flushes it with the shell's final status
  FX=$T/fx_home; mkdir -p "$FX"
  SHTORY_BASHRC=$FX/.bashrc HOME=$FX "$B" install >/dev/null
  fx_run() { # rest = commands (last one exits the shell); prints saved "c e" pairs
    local line
    rm -f "$FX"/.bash_history "$FX"/.shtory/*.jsonl
    { for line in "$@"; do sleep 0.25; printf '%s\n' "$line"; done
      sleep 0.25; } \
      | SHELL=$NP/bash PATH=$NP HOME=$FX pty_run "bash -i" >/dev/null 2>&1
    jq -r '"\(.c) \(.e)"' "$FX"/.shtory/*.jsonl 2>/dev/null
  }
  assert_eq "exit flush: compound ending in exit is logged once" \
    $'echo a 0\ntrue && exit 0' "$(fx_run 'echo a' 'true && exit')"
  assert_eq "exit flush: bare exit not logged, no double log" \
    $'echo b 0' "$(fx_run 'echo b' 'exit')"

  # HISTCONTROL: the hook mirrors bash's history list, so ignoredups/ignorespace/
  # ignoreboth/erasedups are respected; input lines are spaced out (all-at-once
  # pty input is read ahead before the first prompt)
  HC=$T/hc_home; mkdir -p "$HC"
  SHTORY_BASHRC=$HC/.bashrc HOME=$HC "$B" install >/dev/null
  hc_run() { # $1 = HISTCONTROL value, rest = commands; prints saved commands
    local hc=$1 line; shift
    rm -f "$HC/.bash_history" "$HC"/.shtory/*.jsonl
    printf 'HISTCONTROL=%s\n' "$hc" >> "$HC/.bashrc"
    { for line in "$@"; do sleep 0.25; printf '%s\n' "$line"; done
      sleep 0.25; printf 'exit\n'; sleep 0.5; } \
      | SHELL=$NP/bash PATH=$NP HOME=$HC pty_run "bash -i" >/dev/null 2>&1
    jq -r .c "$HC"/.shtory/*.jsonl 2>/dev/null
  }
  assert_eq "HISTCONTROL unset saves all" $'echo a\necho a\necho b' "$(hc_run '' 'echo a' 'echo a' 'echo b')"
  assert_eq "HISTCONTROL=ignoredups" $'echo a\necho b' "$(hc_run ignoredups 'echo a' 'echo a' 'echo b')"
  assert_eq "HISTCONTROL=ignorespace" $'echo a\necho c' "$(hc_run ignorespace 'echo a' ' echo b' 'echo c')"
  assert_eq "HISTCONTROL=ignoreboth" $'echo a\necho c' "$(hc_run ignoreboth 'echo a' ' echo b' 'echo a' 'echo c')"

  # history -c restarts numbering: logging must continue, not skip until the
  # list grows past the old maximum
  HC2=$T/hc2_home; mkdir -p "$HC2"
  SHTORY_BASHRC=$HC2/.bashrc HOME=$HC2 "$B" install >/dev/null
  { for line in 'echo a' 'echo b' 'history -c' 'echo c' 'echo d'; do sleep 0.25; printf '%s\n' "$line"; done
    sleep 0.25; printf 'exit\n'; sleep 0.5; } \
    | SHELL=$NP/bash PATH=$NP HOME=$HC2 pty_run "bash -i" >/dev/null 2>&1
  assert_eq "history -c: logging continues after clear" $'echo a\necho b\necho c\necho d' \
    "$(jq -r .c "$HC2"/.shtory/*.jsonl 2>/dev/null)"
fi
