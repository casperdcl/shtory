#!/usr/bin/env bash
# No TTY required
set -uo pipefail
B=$PWD/shtory
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAILS=0
ok(){ echo " OK  - $1"; }
bad(){ echo "FAIL - $1"; FAILS=$((FAILS + 1)); }
assert_eq(){ # desc expected actual
  if [[ $2 == "$3" ]]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi
}
assert_rc(){ # desc expected_rc actual_rc
  if [[ $2 -eq $3 ]]; then ok "$1"; else bad "$1 (expected rc $2, got rc $3)"; fi
}

echo "# syntax & lint"
if bash -n "$B"; then ok "bash -n"; else bad "bash -n"; fi
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -x "$B"; then ok "shellcheck"; else bad "shellcheck"; fi
else
  echo "SKIP - shellcheck not installed"
fi

echo "# usage"
assert_eq "usage text" "shtory <subcommand> [options]" "$("$B" | head -1)"
"$B" nope >/dev/null 2>&1
assert_rc "unknown subcommand rc 2" 2 $?

echo "# (un)install"
RC=$T/.bashrc
echo 'echo kept' > "$RC"
SHTORY_BASHRC=$RC "$B" install >/dev/null
SHTORY_BASHRC=$RC "$B" install >/dev/null
assert_eq "idempotent install" "1" "$(grep -cF '>>> shtory >>>' "$RC")"
assert_eq "preserves first line" "echo kept" "$(head -1 "$RC")"
grep -qF 'complete -F _shtory shtory' "$RC" && ok "completion registered" || bad "completion registered"
grep -qF '__shtory_log' "$RC" && ok "hook present" || bad "hook present"
SHTORY_BASHRC=$RC "$B" hostname my.host >/dev/null
grep -qF 'export SHTORY_HOSTNAME=my.host' "$RC" && ok "hostname written" || bad "hostname written"
SHTORY_BASHRC=$RC "$B" uninstall >/dev/null
assert_eq "uninstall removes block" "0" "$(grep -cF 'shtory' "$RC" || true)"
assert_eq "uninstall preserves rest" "echo kept" "$(head -1 "$RC")"

echo "# hook logging"
H=$T/home; mkdir -p "$H"
SHTORY_BASHRC=$H/.bashrc "$B" install >/dev/null
cat > "$T/hook.sh" <<'EOF'
echo hi
false
echo a | grep a
printf 'q"uote and \back\slash'
secret_cmd here
EOF
(
  cd /tmp
  HOME=$H SHTORY_HOSTNAME=testhost SHTORY_SKIP='secret_cmd' TERM=dumb \
    bash -i < "$T/hook.sh" >/dev/null 2>&1
)
F=$H/.bash_history.testhost.jsonl
[[ -f $F ]] && ok "history file created" || bad "history file created"
assert_eq "4 commands logged (secret skipped)" "4" "$(wc -l < "$F")"
jq -e 'has("t") and has("d") and has("e") and has("c")' "$F" >/dev/null 2>&1 && ok "all lines valid JSON" || bad "all lines valid JSON"
assert_eq "exit code captured" "1" "$(jq -r 'select(.c == "false") | .e' "$F")"
assert_eq "pipeline captured whole" "echo a | grep a" "$(jq -r 'select(.c == "echo a | grep a") | .c' "$F")"
assert_eq "cwd captured" "/tmp" "$(jq -r 'select(.c == "echo hi") | .d' "$F")"
assert_eq "quoting/backslash escaped" 'printf '\''q"uote and \back\slash'\''' "$(jq -r 'select(.c | contains("q\"uote")) | .c' "$F")"

echo "# tui filter"
shtory_fn() { bash -c "source \"$B\" >/dev/null 2>&1; $*"; }
assert_eq "word-substring filter" "git status" \
  "$(shtory_fn "search_tui_filter 'git s' 'git status' 'git diff' 'ls'")"
assert_eq "empty filter passes all" $'a\nb' \
  "$(shtory_fn "search_tui_filter '' 'a' 'b'")"
assert_eq "case-insensitive" "git status" \
  "$(shtory_fn "search_tui_filter 'GIT S' 'git status'")"
assert_eq "words must be in order" "" \
  "$(shtory_fn "search_tui_filter 'status git' 'git status'")"

echo "# search"
S=$T/searchhome; D=$T/work; mkdir -p "$S" "$D"
cat > "$S/.bash_history.hostA.jsonl" <<EOF
{"t":1000,"d":"$D","e":0,"c":"git status"}
{"t":1100,"d":"$D","e":0,"c":"git status"}
{"t":1200,"d":"$D","e":1,"c":"make build"}
{"t":1300,"d":"/var/log","e":0,"c":"tail -f app.log"}
{"t":1400,"d":"$D","e":0,"c":"grep -E 'a|b' conf.yml"}
EOF
cat > "$S/.bash_history.hostB.jsonl" <<'EOF'
{"t":900,"d":"/home/u","e":0,"c":"echo fromB"}
{"t":1500,"d":"/root","e":1,"c":"make test"}
EOF
for h in lap-01 lap-top laptop prefix-lap-01 desktop-personal; do
  printf '{"t":1,"d":"/x","e":0,"c":"cmd-on-%s"}\n' "$h" > "$S/.bash_history.$h.jsonl"
done
run(){ HOME=$S "$B" search "$@"; }
assert_eq "default host is all" "git status" "$(run git)"
assert_eq "glob lap-* (excl. laptop, desktop-personal)" $'cmd-on-lap-01\ncmd-on-lap-top' "$(run -h 'lap-*')"
assert_eq "glob host*" $'make test\nmake build' "$(run -h 'host*' make)"
assert_eq "query, deduped" "git status" "$(run -h hostA git)"
assert_eq "case-insensitive" "git status" "$(run -h hostA GIT)"
assert_eq "-Z all hosts, newest first" $'make test\nmake build' "$(run -h '*' -Z)"
assert_eq "-z" "echo fromB" "$(run -h hostB -z)"
assert_eq "-c cwd filter" $'grep -E \'a|b\' conf.yml\nmake build\ngit status' \
  "$(cd "$D" && HOME=$S "$B" search -h hostA -c)"
assert_eq "-s count, top is dup" "git status" "$(run -h hostA -s count | head -1)"
assert_eq "-s oldest -n 2" $'git status\nmake build' "$(run -h hostA -s oldest -n 2)"
assert_eq "-n 1 across hosts" "make test" "$(run -h '*' -n 1)"
assert_eq "-n 0 = no limit" $'grep -E \'a|b\' conf.yml\ntail -f app.log\nmake build\ngit status' "$(run -h hostA -n 0)"
assert_eq "regex query" "make build" "$(run -h hostA 'make .*')"
run -h hostA '([' >/dev/null 2>&1; rc=$?
[[ $rc -ne 0 ]] && ok "bad regex nonzero rc" || bad "bad regex nonzero rc"
run -h nosuch >/dev/null 2>&1; assert_rc "missing host rc 1" 1 $?
out=$(HOME=$S "$B" search -h hostA 'nope' 2>/dev/null); assert_eq "no match empty" "" "$out"
cat > "$S/.bash_history.hostT.jsonl" <<EOF
{"t":1,"d":"$S","e":0,"c":"in-home"}
{"t":2,"d":"$S/sub","e":0,"c":"in-sub"}
{"t":3,"d":"$S-x","e":0,"c":"in-sibling"}
EOF
rows(){ HOME=$S shtory_fn "cwd= efilter= order=newest limit=1000 files=(\"$S/.bash_history.hostT.jsonl\"); query '$1' rows"; }
assert_eq "path: home itself is ~" $'in-home\t~\t0\t1970-01-01 00:00\thostT' "$(rows in-home)"
assert_eq "path: home prefix is ~/" $'in-sub\t~/sub\t0\t1970-01-01 00:00\thostT' "$(rows in-sub)"
assert_eq "path: sibling prefix untouched" $'in-sibling\t'"$S-x"$'\t0\t1970-01-01 00:00\thostT' "$(rows in-sibling)"

echo "# hostname"
assert_eq "prints effective host" "${SHTORY_HOSTNAME:-$HOSTNAME}" "$(HOME=$S "$B" hostname)"
HOME=$S SHTORY_BASHRC=$T/h "$B" hostname 'bad name!' >/dev/null 2>&1
assert_rc "invalid name rc 2" 2 $?

echo "# stats / compact"
assert_eq "stats hostA" '{"host":"hostA","commands":5,"first":"1970-01-01T00:16:40Z","last":"1970-01-01T00:23:20Z","failed":1}' \
  "$(HOME=$S "$B" stats | grep hostA)"
for i in $(seq 1 15); do
  printf '{"t":%s,"d":"/z","e":0,"c":"filler %s"}\n' "$((60 + i))" "$i" >> "$S/.bash_history.hostB.jsonl"
done
HOME=$S "$B" compact 3
assert_eq "compact keeps newest 3" "3" "$(wc -l < "$S/.bash_history.hostB.jsonl")"
assert_eq "compact sorted by t" "75 900 1500" "$(jq -r .t "$S/.bash_history.hostB.jsonl" | tr '\n' ' ' | sed 's/ $//')"
HOME=$S "$B" compact abc >/dev/null 2>&1; assert_rc "compact bad cap rc 2" 2 $?
HOME=$S "$B" compact >/dev/null 2>&1; assert_rc "compact requires <N>" 2 $?

echo "# sync (shimmed ssh/rsync)"
SHIM=$T/shim; R=$T/remote; L=$T/rsync_home
mkdir -p "$SHIM" "$R" "$L"
cat > "$SHIM/ssh" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == -G ]]; then
  h=$2
  if grep -qx "$h" "${FAKE_SSH_HOSTS}"; then
    printf 'user root\nhostname %s.resolved\n' "$h"
  else
    printf 'user root\nhostname %s\n' "$h"
  fi
  exit 0
fi
exit 0
EOF
cat > "$SHIM/rsync" <<'EOF'
#!/usr/bin/env bash
args=("$@")
if [[ ${#args[@]} -eq 3 && ${args[1]} == *:* ]]; then
  dest=${args[2]}; n=0
  for f in "$FAKE_REMOTE"/.bash_history.*.jsonl; do
    [[ -e $f ]] || continue
    cp "$f" "$dest/" && n=$((n + 1))
  done
  exit $((n == 0))
fi
i=0
while [[ ${args[i]} != -- ]]; do i=$((i + 1)); done
files=("${args[@]:i + 1: ${#args[@]} - i - 2}")
for f in "${files[@]}"; do cp "$f" "$FAKE_REMOTE/"; done
exit 0
EOF
chmod +x "$SHIM/ssh" "$SHIM/rsync"
printf '%s\n' '{"t":100,"d":"/a","e":0,"c":"local-only"}' '{"t":300,"d":"/a","e":0,"c":"shared"}' > "$L/.bash_history.localhost.jsonl"
printf '%s\n' '{"t":200,"d":"/x","e":0,"c":"onA"}' '{"t":300,"d":"/a","e":0,"c":"shared"}' > "$L/.bash_history.fakeA.jsonl"
printf '%s\n' '{"t":200,"d":"/x","e":0,"c":"onA"}' '{"t":300,"d":"/a","e":0,"c":"shared"}' '{"t":400,"d":"/y","e":1,"c":"remote-only"}' > "$R/.bash_history.fakeA.jsonl"
printf '%s\n' '{"t":50,"d":"/z","e":0,"c":"fromB"}' > "$R/.bash_history.fakeB.jsonl"
printf 'fakeA\nfakeB\n' > "$T/ssh_hosts"
(
  HOME=$L FAKE_REMOTE=$R FAKE_SSH_HOSTS=$T/ssh_hosts PATH="$SHIM:$PATH" \
    "$B" sync
)
assert_eq "merged union, t-sorted" $'{"t":200,"d":"/x","e":0,"c":"onA"}\n{"t":300,"d":"/a","e":0,"c":"shared"}\n{"t":400,"d":"/y","e":1,"c":"remote-only"}' \
  "$(cat "$L/.bash_history.fakeA.jsonl")"
assert_eq "missing file pulled" '{"t":50,"d":"/z","e":0,"c":"fromB"}' "$(cat "$L/.bash_history.fakeB.jsonl")"
[[ -f $R/.bash_history.localhost.jsonl ]] && ok "local-only pushed to remote" || bad "local-only pushed to remote"
md5sum "$L"/.bash_history.*.jsonl > "$T/m1"
(
  HOME=$L FAKE_REMOTE=$R FAKE_SSH_HOSTS=$T/ssh_hosts PATH="$SHIM:$PATH" \
    "$B" sync
) >/dev/null 2>&1
md5sum "$L"/.bash_history.*.jsonl > "$T/m2"
if diff -q "$T/m1" "$T/m2" >/dev/null; then ok "idempotent"; else bad "idempotent"; fi
out=$(
  HOME=$L FAKE_REMOTE=$R FAKE_SSH_HOSTS=$T/ssh_hosts PATH="$SHIM:$PATH" \
    "$B" sync fakeA 2>&1
)
if [[ $out == *fakeA:*synced* && $out != *fakeB* ]]; then ok "explicit <host>: no auto-detect"; else bad "explicit <host>: no auto-detect ($out)"; fi

echo "# result"
if [[ $FAILS -eq 0 ]]; then
  echo "all tests passed"
else
  echo "$FAILS test(s) failed"
  exit 1
fi
