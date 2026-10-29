#!/usr/bin/env bash
# test: interactive pickers via pty (run via ./test.bash; standalone: bash test/pty.sh)
# skipped if script(1) is unavailable
source ./test/common.sh

echo "# interactive (pty via script(1); skipped if unavailable)"
if ! command -v script >/dev/null 2>&1; then
  echo "SKIP - script (util-linux) not installed"
else
  SC=$(command -v script)
  # last content line of a pty capture: drop CR/ESC bytes and CSI parameter text
  lastline() {
    printf '%s\n' "$1" | tr -d '\r\033' | sed 's/\[[0-9;?]*[a-zA-Z]//g' \
      | grep -v '^[[:space:]]*$' | tail -1
  }
  NP=$T/nopath; mkdir -p "$NP" # pty PATH: no fzf/tui-shtory -> numbered loop
  for b in bash sh jq cat stty; do
    p=$(command -v "$b") && ln -sf "$p" "$NP/$b"
  done
  PTH=$T/pty_home; mkdir -p "$PTH"
  printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"git status"}' '{"t":2,"d":"/x","e":0,"c":"git push"}' \
    > "$PTH/.bash_history.pty.jsonl"

  # numbered loop: type a pattern, select row 1 (newest match)
  out=$(printf 'git\n1\n' | SHELL=$NP/bash PATH=$NP HOME=$PTH \
    "$SC" -qec "$B search" /dev/null 2>/dev/null | tr -d '\r')
  [[ $(lastline "$out") == *"git push"* ]] && ok "pty: numbered loop selects" || bad "pty: numbered loop selects ($(lastline "$out"))"

  # tui-shtory: rows from a file (EOF), keys via the pty
  printf 'alpha cmd\nbeta cmd\n' > "$T/tui_rows"
  out=$(printf 'a\n' | SHELL=$NP/bash PATH="$NP:$PATH" HOME=$PTH \
    "$SC" -qec "stty rows 20 cols 60 2>/dev/null; $TUI < $T/tui_rows" /dev/null 2>/dev/null | tr -d '\r')
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
    "$SC" -qec "stty rows 20 cols 60 2>/dev/null; bash $T/tui_slow.sh $TUI" /dev/null 2>/dev/null | tr -d '\r')
  [[ $out == *$'\e[?1049h'* && $out != *"gamma cmd"* ]] && ok "pty: tui-shtory interactive before rows arrive" || bad "pty: tui-shtory interactive before rows arrive"

  # tui-shtory: arrow keys re-render (the inverted row follows sel)
  printf 'alpha x\nbeta x\n' > "$T/tui_rows2"
  out=$( { sleep 0.7; printf '\x1b[B'; sleep 0.3; printf '\r'; } | \
    SHELL=$NP/bash PATH="$NP:$PATH" HOME=$PTH \
    "$SC" -qec "stty rows 20 cols 60 2>/dev/null; $TUI < $T/tui_rows2" /dev/null 2>/dev/null | tr -d '\r')
  [[ $out == *$'\e[7m beta'* ]] && ok "pty: tui-shtory arrow re-renders" || bad "pty: tui-shtory arrow re-renders"

  # HISTCONTROL: the hook mirrors bash's history list, so ignoredups/ignorespace/
  # ignoreboth/erasedups are respected; input lines are spaced out (all-at-once
  # pty input is read ahead before the first prompt)
  HC=$T/hc_home; mkdir -p "$HC"
  SHTORY_BASHRC=$HC/.bashrc HOME=$HC "$B" install >/dev/null
  hc_run() { # $1 = HISTCONTROL value, rest = commands; prints saved commands
    local hc=$1 line; shift
    rm -f "$HC/.bash_history" "$HC"/.bash_history.*.jsonl
    printf 'export HISTCONTROL=%s\n' "$hc" >> "$HC/.bashrc"
    { for line in "$@"; do sleep 0.25; printf '%s\n' "$line"; done
      sleep 0.25; printf 'exit\n'; sleep 0.5; } \
      | SHELL=$NP/bash PATH=$NP HOME=$HC "$SC" -qec "bash -i" /dev/null >/dev/null 2>&1
    jq -r .c "$HC"/.bash_history.*.jsonl 2>/dev/null
  }
  assert_eq "HISTCONTROL unset saves all" $'echo a\necho a\necho b' "$(hc_run '' 'echo a' 'echo a' 'echo b')"
  assert_eq "HISTCONTROL=ignoredups" $'echo a\necho b' "$(hc_run ignoredups 'echo a' 'echo a' 'echo b')"
  assert_eq "HISTCONTROL=ignorespace" $'echo a\necho c' "$(hc_run ignorespace 'echo a' ' echo b' 'echo c')"
  assert_eq "HISTCONTROL=ignoreboth" $'echo a\necho c' "$(hc_run ignoreboth 'echo a' ' echo b' 'echo a' 'echo c')"
fi
