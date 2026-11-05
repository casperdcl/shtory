#!/usr/bin/env bash
# test: usage, (un)install, hook logging (run via ./test.bash; standalone: bash test/install.sh)
source ./test/common.sh

echo "# usage"
assert_eq "usage text" "shtory <subcommand> [options]" "$("$B" | head -1)"
"$B" nope >/dev/null 2>&1
assert_rc "unknown subcommand rc 2" 2 $?

echo "# (un)install"
RC=$T/.bashrc
BS=$(command -v bash)
echo 'echo kept' > "$RC"
SHELL=$BS SHTORY_BASHRC=$RC "$B" install >/dev/null
SHELL=$BS SHTORY_BASHRC=$RC "$B" install >/dev/null
SHELL=$BS SHTORY_BASHRC=$RC "$B" install foo >/dev/null 2>&1
assert_rc "install: unknown arg rc 2 (no hang)" 2 $?
assert_eq "idempotent install" "1" "$(grep -cF '>>> shtory >>>' "$RC")"
assert_eq "re-install doesn't stack blank lines" "1" "$(sed -n '1,/>>> shtory >>>/p' "$RC" | grep -c '^$')"
assert_eq "preserves first line" "echo kept" "$(head -1 "$RC")"
grep -qF 'complete -F _shtory shtory' "$RC" && ok "completion registered" || bad "completion registered"
grep -qF '__shtory_log' "$RC" && ok "hook present" || bad "hook present"
SHELL=$BS SHTORY_BASHRC=$RC "$B" hostname my.host >/dev/null
grep -qF 'export SHTORY_HOSTNAME=my.host' "$RC" && ok "hostname written" || bad "hostname written"
SHELL=$BS SHTORY_BASHRC=$RC "$B" uninstall >/dev/null
assert_eq "uninstall removes block" "0" "$(grep -cF 'shtory' "$RC" || true)"
assert_eq "uninstall preserves rest" "echo kept" "$(head -1 "$RC")"

echo "# (un)install --zsh"
TZ=$T/.zshrc
echo 'echo kept' > "$TZ"
SHELL=/usr/bin/zsh SHTORY_ZSHRC=$TZ "$B" install >/dev/null
SHELL=/usr/bin/zsh SHTORY_ZSHRC=$TZ "$B" install >/dev/null
assert_eq "zsh: idempotent install" "1" "$(grep -cF '>>> shtory >>>' "$TZ")"
assert_eq "zsh: preserves first line" "echo kept" "$(head -1 "$TZ")"
grep -qF 'add-zsh-hook zshaddhistory __shtory_zshaddhistory' "$TZ" && ok "zsh: hook registered" || bad "zsh: hook registered"
grep -qF 'bindkey' "$TZ" && ok "zsh: keybinding present" || bad "zsh: keybinding present"
TZ2=$T/.zshrc2
echo 'echo kept' > "$TZ2"
SHELL=/usr/bin/zsh SHTORY_ZSHRC=$TZ2 "$B" install >/dev/null
grep -qF 'add-zsh-hook zshaddhistory' "$TZ2" && ok "install auto-detects zsh from \$SHELL" || bad "install auto-detects zsh from \$SHELL"
SHELL=/usr/bin/zsh SHTORY_ZSHRC=$TZ "$B" uninstall >/dev/null
assert_eq "zsh: uninstall removes block" "0" "$(grep -cF 'shtory' "$TZ" || true)"
SHELL=/usr/bin/zsh SHTORY_ZSHRC=$TZ "$B" hostname zsh.host >/dev/null
grep -qF 'export SHTORY_HOSTNAME=zsh.host' "$TZ" && ok "zsh: hostname written to zshrc" || bad "zsh: hostname written to zshrc"

if command -v zsh >/dev/null 2>&1; then
echo "# zsh hook logging"
HZ=$T/zhome; mkdir -p "$HZ"
SHELL=/usr/bin/zsh SHTORY_ZSHRC=$HZ/.zshrc "$B" install >/dev/null
cat > "$T/zcmds" <<'EOF'
echo hi
false
echo a | grep a
echo a
echo a
 echo spaced
secret_cmd here
printf 'q"uote and \back\slash'
EOF
printf 'SHTORY_SKIP=secret_cmd\nsetopt hist_ignore_dups\nsetopt hist_ignore_space\n' >> "$HZ/.zshrc"
(
  cd /tmp || exit 1
  umask 022 # so the 0600 assertion is not vacuous
  HOME=$HZ SHTORY_HOSTNAME=zhost TERM=dumb \
    zsh -i < "$T/zcmds" > "$T/zhook_out" 2>/dev/null
)
F=$HZ/.shtory.zhost.jsonl
[[ -f $F ]] && ok "zsh: history file created" || bad "zsh: history file created"
[[ $(stat -c %a "$F") == 600 ]] && ok "zsh: history file mode 600" || bad "zsh: history file mode 600 ($(stat -c %a "$F"))"
assert_eq "zsh: 5 commands logged (dup/space/secret skipped)" "5" "$(wc -l < "$F")"
jq -e 'has("t") and has("d") and has("e") and has("c")' "$F" >/dev/null 2>&1 && ok "zsh: all lines valid JSON" || bad "zsh: all lines valid JSON"
assert_eq "zsh: exit code captured" "1" "$(jq -r 'select(.c == "false") | .e' "$F")"
assert_eq "zsh: pipeline captured whole" "echo a | grep a" "$(jq -r 'select(.c == "echo a | grep a") | .c' "$F")"
assert_eq "zsh: cwd captured" "/tmp" "$(jq -r 'select(.c == "echo hi") | .d' "$F")"
assert_eq "zsh: dup skipped (hist_ignore_dups)" "1" "$(jq -r 'select(.c == "echo a") | .c' "$F" | wc -l)"
assert_eq "zsh: quoted cmd escaped" 'printf '\''q"uote and \back\slash'\''' "$(jq -r 'select(.c | contains("q\"uote")) | .c' "$F")"
else
  echo "SKIP - zsh not installed"
fi

echo "# hook logging"
H=$T/home; mkdir -p "$H"
printf 'PROMPT_COMMAND=(foo bar)\n' > "$H/.bashrc" # shtory must keep these entries (bash 5.1+ array)
SHTORY_BASHRC=$H/.bashrc "$B" install >/dev/null
cat > "$T/hook.sh" <<'EOF'
echo hi
false
echo a | grep a
printf 'q"uote and \back\slash'
secret_cmd here
printf '\nPC:%s\n' "${PROMPT_COMMAND[*]}"
EOF
(
  cd /tmp || exit 1
  umask 022 # so the 0600 assertion is not vacuous
  HOME=$H SHTORY_HOSTNAME=testhost SHTORY_SKIP='secret_cmd|PC' TERM=dumb \
    bash -i < "$T/hook.sh" > "$T/hook_out" 2>/dev/null
)
F=$H/.shtory.testhost.jsonl
[[ -f $F ]] && ok "history file created" || bad "history file created"
[[ $(stat -c %a "$F") == 600 ]] && ok "history file mode 600" || bad "history file mode 600 ($(stat -c %a "$F"))"
assert_eq "PROMPT_COMMAND array entries kept" "PC:__shtory_log foo bar" "$(grep '^PC:' "$T/hook_out")"
assert_eq "4 commands logged (secret skipped)" "4" "$(wc -l < "$F")"
jq -e 'has("t") and has("d") and has("e") and has("c")' "$F" >/dev/null 2>&1 && ok "all lines valid JSON" || bad "all lines valid JSON"
assert_eq "exit code captured" "1" "$(jq -r 'select(.c == "false") | .e' "$F")"
assert_eq "pipeline captured whole" "echo a | grep a" "$(jq -r 'select(.c == "echo a | grep a") | .c' "$F")"
assert_eq "cwd captured" "/tmp" "$(jq -r 'select(.c == "echo hi") | .d' "$F")"
assert_eq "quoting/backslash escaped" 'printf '\''q"uote and \back\slash'\''' "$(jq -r 'select(.c | contains("q\"uote")) | .c' "$F")"
# a new session must not re-log the last command of the re-read history file
H2=$T/hook_home2; mkdir -p "$H2"
SHTORY_BASHRC=$H2/.bashrc "$B" install >/dev/null
printf 'old cmd one\nold cmd two\n' > "$H2/.bash_history"
printf 'fresh cmd\n' > "$T/hook2.sh"
( HOME=$H2 SHTORY_HOSTNAME=testhost2 TERM=dumb bash -i < "$T/hook2.sh" >/dev/null 2>&1 )
F2=$H2/.shtory.testhost2.jsonl
[[ -f $F2 && $(wc -l < "$F2") == 1 ]] && ok "re-read entry not re-logged" || bad "re-read entry not re-logged ($(jq -r .c "$F2" 2>/dev/null | tr '\n' '|'))"
assert_eq "re-read entry: fresh cmd logged" "fresh cmd" "$(jq -r .c "$F2" 2>/dev/null)"
