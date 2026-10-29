#!/usr/bin/env bash
# No TTY required
set -uo pipefail
B=$PWD/shtory
TUI=$PWD/tui-shtory
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
for f in "$B" "$TUI"; do
  if bash -n "$f"; then ok "bash -n ${f##*/}"; else bad "bash -n ${f##*/}"; fi
done
if command -v shellcheck >/dev/null 2>&1; then
  for f in "$B" "$TUI"; do
    if shellcheck -x "$f"; then ok "shellcheck ${f##*/}"; else bad "shellcheck ${f##*/}"; fi
  done
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
F=$H/.bash_history.testhost.jsonl
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
F2=$H2/.bash_history.testhost2.jsonl
[[ -f $F2 && $(wc -l < "$F2") == 1 ]] && ok "re-read entry not re-logged" || bad "re-read entry not re-logged ($(jq -r .c "$F2" 2>/dev/null | tr '\n' '|'))"
assert_eq "re-read entry: fresh cmd logged" "fresh cmd" "$(jq -r .c "$F2" 2>/dev/null)"

echo "# tui filter"
shtory_fn() { bash -c "source \"$B\" >/dev/null 2>&1; $*"; }
tui_fn() { bash -c "source \"$TUI\" >/dev/null 2>&1; $*"; }
assert_eq "word-substring filter" "git status" \
  "$(tui_fn "tui_filter 'git s' 'git status' 'git diff' 'ls'")"
assert_eq "empty filter passes all" $'a\nb' \
  "$(tui_fn "tui_filter '' 'a' 'b'")"
assert_eq "case-insensitive" "git status" \
  "$(tui_fn "tui_filter 'GIT S' 'git status'")"
assert_eq "words must be in order" "" \
  "$(tui_fn "tui_filter 'status git' 'git status'")"

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
assert_eq "-H = -h local host" "git status" "$(SHTORY_HOSTNAME=hostA run -H git)"
assert_eq "--localhost" "git status" "$(SHTORY_HOSTNAME=hostA run --localhost git)"
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
SH=$T/streamhome; mkdir -p "$SH"
printf '{"t":2,"d":"/x","e":0,"c":"own-old"}\n{"t":4,"d":"/x","e":0,"c":"own-new"}\n' > "$SH/.bash_history.own.jsonl"
printf '{"t":1,"d":"/x","e":0,"c":"other-old"}\n{"t":3,"d":"/x","e":0,"c":"other-new"}\n' > "$SH/.bash_history.other.jsonl"
assert_eq "fzf stream: newest file first, newest first" $'own-new\nown-old\nother-new\nother-old' \
  "$(HOME=$SH shtory_fn 'cwd= efilter= limit=0 files=("'$SH'/.bash_history.other.jsonl" "'$SH'/.bash_history.own.jsonl"); fzf_rows' | cut -f1)"
assert_eq "fzf stream: single file, newest first" $'other-new\nother-old' \
  "$(HOME=$SH shtory_fn 'cwd= efilter= limit=0 files=("'$SH'/.bash_history.other.jsonl"); fzf_rows' | cut -f1)"

echo "# hostname"
assert_eq "prints effective host" "${SHTORY_HOSTNAME:-$HOSTNAME}" "$(HOME=$S "$B" hostname)"
HOME=$S SHTORY_BASHRC=$T/h "$B" hostname 'bad name!' >/dev/null 2>&1
assert_rc "invalid name rc 2" 2 $?

echo "# stats / compact"
assert_eq "stats hostA" '{"host":"hostA","commands":5,"first":"1970-01-01T00:16:40Z","last":"1970-01-01T00:23:20Z","failed":1}' \
  "$(HOME=$S "$B" stats | grep hostA)"
printf '%s\n' \
  '{"t":1,"d":"/uniquedir1","e":0,"c":"zzztop"}' '{"t":2,"d":"/uniquedir1","e":0,"c":"zzztop"}' \
  '{"t":3,"d":"/uniquedir1","e":0,"c":"zzztop"}' '{"t":4,"d":"/uniquedir1","e":1,"c":"qqq"}' \
  '{"t":5,"d":"/uniquedir2","e":0,"c":"qqq"}' > "$S/.bash_history.hostS.jsonl"
assert_eq "stats --cmd 2" $'3\tzzztop\n2\tgit status' "$(HOME=$S "$B" stats --cmd 2)"
assert_eq "stats --dir 1" $'5\t/x' "$(HOME=$S "$B" stats --dir 1)"
HOME=$S "$B" stats --cmd x >/dev/null 2>&1; assert_rc "stats bad --cmd rc 2" 2 $?
for i in $(seq 1 15); do
  printf '{"t":%s,"d":"/z","e":0,"c":"filler %s"}\n' "$((60 + i))" "$i" >> "$S/.bash_history.hostB.jsonl"
done
HOME=$S "$B" compact 3
assert_eq "compact keeps newest 3" "3" "$(wc -l < "$S/.bash_history.hostB.jsonl")"
assert_eq "compact sorted by t" "75 900 1500" "$(jq -r .t "$S/.bash_history.hostB.jsonl" | tr '\n' ' ' | sed 's/ $//')"
HOME=$S "$B" compact abc >/dev/null 2>&1; assert_rc "compact bad cap rc 2" 2 $?
HOME=$S "$B" compact >/dev/null 2>&1; assert_rc "compact requires <N>" 2 $?
# compact edge: n>length keeps all (deduped, ascending); n=0 empties
CE=$T/compactedge; mkdir -p "$CE"
printf '%s\n' '{"t":1,"d":"/z","e":0,"c":"a"}' '{"t":5,"d":"/z","e":0,"c":"b"}' '{"t":3,"d":"/z","e":0,"c":"c"}' '{"t":3,"d":"/z","e":0,"c":"c"}' > "$CE/.bash_history.e.jsonl"
HOME=$CE "$B" compact 10
assert_eq "compact n>length: keep all, deduped, ascending" "1 3 5" "$(jq -r .t "$CE/.bash_history.e.jsonl" | tr '\n' ' ' | sed 's/ $//')"
HOME=$CE "$B" compact 0
assert_eq "compact n=0: empties" "0" "$(wc -l < "$CE/.bash_history.e.jsonl")"
printf '%s\n' '{"t":1,"d":"/z","e":0,"c":"a"}' '{"t":2,"d":"/z","e":0,"c":"b"}' > "$CE/.bash_history.m.jsonl"
chmod 600 "$CE/.bash_history.m.jsonl"
HOME=$CE "$B" compact 5
[[ $(stat -c %a "$CE/.bash_history.m.jsonl") == 600 ]] && ok "compact preserves mode 600" || bad "compact preserves mode 600 ($(stat -c %a "$CE/.bash_history.m.jsonl"))"

echo "# import (install --import)"
I=$T/importhome; F=$I/.bash_history.imphost.jsonl; mkdir -p "$I"
printf 'ls\ncd /tmp\nls\ngit status\n\n' > "$I/.bash_history"
HOME=$I SHTORY_HOSTNAME=imphost "$B" install --import >/dev/null
assert_eq "install --import: block written" "1" "$(grep -cF '>>> shtory >>>' "$I/.bashrc")"
assert_eq "install --import: unique, original order, t=0" \
  $'{"t":0,"d":"","e":0,"c":"ls"}\n{"t":0,"d":"","e":0,"c":"cd /tmp"}\n{"t":0,"d":"","e":0,"c":"git status"}' \
  "$(cat "$F")"
[[ $(stat -c %a "$F") == 600 ]] && ok "install --import: file mode 600" || bad "install --import: file mode 600 ($(stat -c %a "$F"))"
assert_eq "imported searchable" "git status" \
  "$(HOME=$I SHTORY_HOSTNAME=imphost "$B" search -h imphost git)"
# idempotent: re-running does not duplicate already-present commands
F_before=$(cat "$F")
HOME=$I SHTORY_HOSTNAME=imphost "$B" install --import >/dev/null
assert_eq "install --import: idempotent (no dup on re-run)" "$F_before" "$(cat "$F")"
# dedup keys on (c, t:0): a normally-logged command (t>0) is still imported as a t:0 line
printf '%s\n' '{"t":999,"d":"/a","e":0,"c":"ls"}' > "$F"
printf 'ls\n' > "$I/.bash_history"
HOME=$I SHTORY_HOSTNAME=imphost "$B" install --import >/dev/null
assert_eq "dedup is (c,t:0): real (t>0) entry does not block import" \
  $'{"t":0,"d":"","e":0,"c":"ls"}\n{"t":999,"d":"/a","e":0,"c":"ls"}' \
  "$(cat "$F")"
printf '%s\n' '{"t":500,"d":"/a","e":0,"c":"existing"}' > "$F"
printf 'echo new\n' > "$I/.bash_history"
HOME=$I SHTORY_HOSTNAME=imphost "$B" install --import >/dev/null
assert_eq "install --import: prepends before existing" \
  $'{"t":0,"d":"","e":0,"c":"echo new"}\n{"t":500,"d":"/a","e":0,"c":"existing"}' \
  "$(cat "$F")"
: > "$F"
printf 'echo "a b" && ls -la\n' > "$I/.bash_history"
HOME=$I SHTORY_HOSTNAME=imphost "$B" install --import >/dev/null
assert_eq "install --import: quoting escaped" 'echo "a b" && ls -la' "$(jq -r '.c' "$F")"
# comment lines (starting with #) are skipped, incl. HISTTIMEFORMAT #epoch timestamps
: > "$F"
printf 'ls\n#1793199155\ngit status\n#my note\n' > "$I/.bash_history"
HOME=$I SHTORY_HOSTNAME=imphost "$B" install --import >/dev/null
assert_eq "comment (#) lines skipped" \
  $'{"t":0,"d":"","e":0,"c":"ls"}\n{"t":0,"d":"","e":0,"c":"git status"}' \
  "$(cat "$F")"
I2=$T/importempty; mkdir -p "$I2"
printf 'should-not-import\n' > "$I2/.bash_history"
HOME=$I2 SHTORY_HOSTNAME=imphost "$B" install >/dev/null
[[ ! -f $I2/.bash_history.imphost.jsonl ]] && ok "plain install: no import" || bad "plain install: no import"
I3=$T/importempty3; mkdir -p "$I3"
HOME=$I3 SHTORY_HOSTNAME=imphost "$B" install --import >/dev/null 2>&1
assert_rc "install --import: no .bash_history is a no-op (rc 0)" 0 $?
grep -qF '>>> shtory >>>' "$I3/.bashrc" && ok "no-op: block still written" || bad "no-op: block still written"
# import strips control chars, survives binary bytes + mixed case (LC_ALL=C + grep -a)
I4=$T/importbinary; mkdir -p "$I4"
printf 'A cmd\na cmd\n#123\necho \0nul\nz cmd\n' > "$I4/.bash_history"
HOME=$I4 SHTORY_HOSTNAME=imphost "$B" install --import >/dev/null 2>&1
assert_rc "import: binary+mixed-case history does not fail" 0 $?
assert_eq "import: binary+mixed-case imports 4 commands" 4 "$(wc -l < "$I4/.bash_history.imphost.jsonl")"
assert_eq "import: control chars stripped" "echo nul" "$(jq -r 'select(.c | startswith("echo")) | .c' "$I4/.bash_history.imphost.jsonl")"

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
h=$1
a=(); a+=("$@")
for (( i = 0; i < ${#a[@]}; i++ )); do
  case ${a[i]} in
    -o) (( i++ )); continue ;; # skip -o and its value
    -*) continue ;;
    *) h=${a[i]}; break ;;
  esac
done
if [[ -n ${FAKE_DOWN:-} ]] && grep -qx "$h" "$FAKE_DOWN"; then
  exit 255
fi
if [[ -n ${FAKE_HOSTNAMES:-} ]] && grep -q "^$h " "$FAKE_HOSTNAMES"; then
  awk -v h="$h" '$1 == h {print $2}' "$FAKE_HOSTNAMES"
  exit 0
fi
printf '%s\n' "$h"
exit 0
EOF
cat > "$SHIM/rsync" <<'EOF'
#!/usr/bin/env bash
args=("$@")
src_arg=''; has_dd=0
for a in "${args[@]}"; do
  [[ $a == -- ]] && has_dd=1
  [[ $a == -* ]] && continue
  [[ -z $src_arg && $a == *:* ]] && src_arg=$a
done
# pull: no '--', host:src present; push: files after '--'
if [[ $has_dd -eq 0 && -n $src_arg ]]; then
  h=${src_arg%%:*}; dest=${args[-1]}; n=0
  src="$FAKE_REMOTE/$h"; [[ -d $src ]] || src=$FAKE_REMOTE
  for f in "$src"/.bash_history.*.jsonl; do
    [[ -e $f ]] || continue
    cp "$f" "$dest/" && n=$((n + 1))
  done
  if [[ -n ${FAKE_RSYNC_PARTIAL:-} ]] && grep -qx "$h" "$FAKE_RSYNC_PARTIAL"; then
    exit 23
  fi
  exit $((n == 0))
fi
i=0
while [[ ${args[i]-} != -- && $i -lt ${#args[@]} ]]; do i=$((i + 1)); done
[[ ${args[i]-} == -- ]] || exit 1
h=${args[-1]%%:*}
dest=$FAKE_REMOTE
[[ -d $dest/$h ]] && dest=$dest/$h
files=("${args[@]:i + 1: ${#args[@]} - i - 2}")
for f in "${files[@]}"; do cp "$f" "$dest/"; done
exit 0
EOF
chmod +x "$SHIM/ssh" "$SHIM/rsync"
printf '%s\n' '{"t":100,"d":"/a","e":0,"c":"local-only"}' '{"t":300,"d":"/a","e":0,"c":"shared"}' > "$L/.bash_history.localhost.jsonl"
printf '%s\n' '{"t":200,"d":"/x","e":0,"c":"onA"}' '{"t":300,"d":"/a","e":0,"c":"shared"}' > "$L/.bash_history.fakeA.jsonl"
chmod 600 "$L/.bash_history.fakeA.jsonl"   # must survive the merge
printf '%s\n' '{"t":200,"d":"/x","e":0,"c":"onA"}' '{"t":300,"d":"/a","e":0,"c":"shared"}' '{"t":400,"d":"/y","e":1,"c":"remote-only"}' > "$R/.bash_history.fakeA.jsonl"
printf '%s\n' '{"t":50,"d":"/z","e":0,"c":"fromB"}' > "$R/.bash_history.fakeB.jsonl"
printf 'fakeA\nfakeB\n' > "$T/ssh_hosts"
(
  HOME=$L FAKE_REMOTE=$R FAKE_SSH_HOSTS=$T/ssh_hosts SHTORY_HOSTNAME=me \
    PATH="$SHIM:$PATH" "$B" sync
)
assert_eq "merged union, t-sorted" $'{"t":200,"d":"/x","e":0,"c":"onA"}\n{"t":300,"d":"/a","e":0,"c":"shared"}\n{"t":400,"d":"/y","e":1,"c":"remote-only"}' \
  "$(cat "$L/.bash_history.fakeA.jsonl")"
[[ $(stat -c %a "$L/.bash_history.fakeA.jsonl") == 600 ]] && ok "sync merge preserves mode 600" || bad "sync merge preserves mode 600 ($(stat -c %a "$L/.bash_history.fakeA.jsonl"))"
assert_eq "missing file pulled" '{"t":50,"d":"/z","e":0,"c":"fromB"}' "$(cat "$L/.bash_history.fakeB.jsonl")"
[[ -f $R/.bash_history.localhost.jsonl ]] && ok "local-only pushed to remote" || bad "local-only pushed to remote"
md5sum "$L"/.bash_history.*.jsonl > "$T/m1"
(
  HOME=$L FAKE_REMOTE=$R FAKE_SSH_HOSTS=$T/ssh_hosts SHTORY_HOSTNAME=me \
    PATH="$SHIM:$PATH" "$B" sync
) >/dev/null 2>&1
md5sum "$L"/.bash_history.*.jsonl > "$T/m2"
if diff -q "$T/m1" "$T/m2" >/dev/null; then ok "idempotent"; else bad "idempotent"; fi
out=$(
  HOME=$L FAKE_REMOTE=$R FAKE_SSH_HOSTS=$T/ssh_hosts PATH="$SHIM:$PATH" \
    "$B" sync fakeA 2>&1
)
if [[ $out == *fakeA:*synced* && $out != *fakeB* ]]; then ok "explicit <host>: no auto-detect"; else bad "explicit <host>: no auto-detect ($out)"; fi

# auto-detect must skip the local host's own file (it is local, not a remote)
L4=$T/ad_home; R4=$T/ad_remote
mkdir -p "$L4" "$R4"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"on-me"}' > "$L4/.bash_history.me.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"stale"}' > "$L4/.bash_history.dev1.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"stale"}' '{"t":2,"d":"/x","e":0,"c":"on-remote"}' > "$R4/.bash_history.dev1.jsonl"
printf 'dev1\n' > "$T/ssh_hosts5"
out=$(
  HOME=$L4 FAKE_REMOTE=$R4 FAKE_SSH_HOSTS=$T/ssh_hosts5 SHTORY_HOSTNAME=me \
  PATH="$SHIM:$PATH" "$B" sync 2>&1
)
if [[ $out == *dev1:*synced* && $out != *me* ]]; then ok "auto-detect skips local host"; else bad "auto-detect skips local host ($out)"; fi
[[ -f $R4/.bash_history.me.jsonl ]] && ok "local file still pushed to remote" || bad "local file still pushed to remote"
assert_eq "auto-detect: remote file merged locally" $'{"t":1,"d":"/x","e":0,"c":"stale"}\n{"t":2,"d":"/x","e":0,"c":"on-remote"}' \
  "$(cat "$L4/.bash_history.dev1.jsonl")"

# unreachable host (ssh rc 255) is skipped, not hung on
out=$(
  HOME=$L4 FAKE_REMOTE=$R4 FAKE_SSH_HOSTS=$T/ssh_hosts5 FAKE_DOWN=$T/ssh_hosts5 SHTORY_HOSTNAME=me \
  PATH="$SHIM:$PATH" "$B" sync dev1 2>&1
)
if [[ $out == *dev1:*unreachable* ]]; then ok "unreachable host skipped"; else bad "unreachable host skipped ($out)"; fi

# multi-host: every host must receive the full merge (per-host loop left later hosts stale)
M=$T/mh_remote
for h in mA mB mC; do mkdir -p "$M/$h"; done
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"a1"}' '{"t":2,"d":"/x","e":0,"c":"a2"}' > "$M/mA/.bash_history.mA.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"b1"}' > "$M/mA/.bash_history.mB.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"c1"}' > "$M/mA/.bash_history.mC.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"a1"}' > "$M/mB/.bash_history.mA.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"b1"}' '{"t":2,"d":"/x","e":0,"c":"b2"}' > "$M/mB/.bash_history.mB.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"c1"}' > "$M/mB/.bash_history.mC.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"a1"}' > "$M/mC/.bash_history.mA.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"b1"}' > "$M/mC/.bash_history.mB.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"c1"}' '{"t":2,"d":"/x","e":0,"c":"c2"}' > "$M/mC/.bash_history.mC.jsonl"
MH=$T/mh_home; mkdir -p "$MH"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"a1"}' > "$MH/.bash_history.mA.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"b1"}' > "$MH/.bash_history.mB.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"c1"}' > "$MH/.bash_history.mC.jsonl"
printf 'mA\nmB\nmC\n' > "$T/ssh_hosts4"
(
  HOME=$MH FAKE_REMOTE=$M FAKE_SSH_HOSTS=$T/ssh_hosts4 PATH="$SHIM:$PATH" \
  "$B" sync mA mB mC
) >/dev/null 2>&1
assert_eq "multi-host: mA got mC's new line" $'{"t":1,"d":"/x","e":0,"c":"c1"}\n{"t":2,"d":"/x","e":0,"c":"c2"}' \
  "$(cat "$M/mA/.bash_history.mC.jsonl")"
assert_eq "multi-host: mC got mB's new line" $'{"t":1,"d":"/x","e":0,"c":"b1"}\n{"t":2,"d":"/x","e":0,"c":"b2"}' \
  "$(cat "$M/mC/.bash_history.mB.jsonl")"
assert_eq "multi-host: local merged everything" $'{"t":1,"d":"/x","e":0,"c":"a1"}\n{"t":2,"d":"/x","e":0,"c":"a2"}' \
  "$(cat "$MH/.bash_history.mA.jsonl")"

# sync --compact
L3=$T/cp_home; R3=$T/cp_remote
mkdir -p "$L3" "$R3"
printf '%s\n' '{"t":100,"d":"/a","e":0,"c":"old1"}' '{"t":300,"d":"/a","e":0,"c":"shared"}' '{"t":400,"d":"/a","e":0,"c":"new"}' > "$L3/.bash_history.hostX.jsonl"
printf '%s\n' '{"t":300,"d":"/a","e":0,"c":"shared"}' '{"t":400,"d":"/a","e":0,"c":"new"}' '{"t":500,"d":"/a","e":0,"c":"remote-new"}' > "$R3/.bash_history.hostX.jsonl"
printf '%s\n' '{"t":50,"d":"/z","e":0,"c":"local-only"}' > "$L3/.bash_history.other.jsonl"
printf 'hostX\n' > "$T/ssh_hosts3"
(
  HOME=$L3 FAKE_REMOTE=$R3 FAKE_SSH_HOSTS=$T/ssh_hosts3 PATH="$SHIM:$PATH" \
  "$B" sync --compact 2 hostX
) >/dev/null 2>&1
assert_eq "sync --compact: merged then capped to newest N" $'{"t":400,"d":"/a","e":0,"c":"new"}\n{"t":500,"d":"/a","e":0,"c":"remote-new"}' \
  "$(cat "$L3/.bash_history.hostX.jsonl")"
assert_eq "sync --compact: push carries compacted files" '{"t":50,"d":"/z","e":0,"c":"local-only"}' \
  "$(cat "$R3/.bash_history.other.jsonl")"
assert_eq "sync --compact implies --self: own file pushed compacted" $'{"t":400,"d":"/a","e":0,"c":"new"}\n{"t":500,"d":"/a","e":0,"c":"remote-new"}' \
  "$(cat "$R3/.bash_history.hostX.jsonl")"
HOME=$L3 "$B" sync --compact abc hostX >/dev/null 2>&1; assert_rc "sync --compact bad N rc 2" 2 $?
HOME=$L3 "$B" sync --compact >/dev/null 2>&1; assert_rc "sync --compact requires N" 1 $?

# sync --self
L4=$T/self_home; R4=$T/self_remote
mkdir -p "$L4" "$R4"
printf '%s\n' '{"t":10,"d":"/x","e":0,"c":"shared"}' '{"t":30,"d":"/x","e":0,"c":"local-only"}' > "$L4/.bash_history.hostY.jsonl"
printf '%s\n' '{"t":10,"d":"/x","e":0,"c":"shared"}' '{"t":20,"d":"/x","e":0,"c":"remote-only"}' > "$R4/.bash_history.hostY.jsonl"
printf '%s\n' '{"t":5,"d":"/z","e":0,"c":"other2"}' > "$L4/.bash_history.other2.jsonl"
printf 'hostY\n' > "$T/ssh_hosts5"
(
  HOME=$L4 FAKE_REMOTE=$R4 FAKE_SSH_HOSTS=$T/ssh_hosts5 PATH="$SHIM:$PATH" \
  "$B" sync hostY
) >/dev/null 2>&1
assert_eq "sync: own file not pushed by default" $'{"t":10,"d":"/x","e":0,"c":"shared"}\n{"t":20,"d":"/x","e":0,"c":"remote-only"}' \
  "$(cat "$R4/.bash_history.hostY.jsonl")"
(
  HOME=$L4 FAKE_REMOTE=$R4 FAKE_SSH_HOSTS=$T/ssh_hosts5 PATH="$SHIM:$PATH" \
  "$B" sync --self hostY
) >/dev/null 2>&1
assert_eq "sync --self: own file pushed" $'{"t":10,"d":"/x","e":0,"c":"shared"}\n{"t":20,"d":"/x","e":0,"c":"remote-only"}\n{"t":30,"d":"/x","e":0,"c":"local-only"}' \
  "$(cat "$R4/.bash_history.hostY.jsonl")"

# sync: host's reported name differs from the ssh alias
L5=$T/name_home; R5=$T/name_remote
mkdir -p "$L5" "$R5/alx"
printf '%s\n' '{"t":10,"d":"/x","e":0,"c":"shared"}' '{"t":30,"d":"/x","e":0,"c":"local-only"}' > "$L5/.bash_history.realhost.jsonl"
printf '%s\n' '{"t":10,"d":"/x","e":0,"c":"shared"}' '{"t":20,"d":"/x","e":0,"c":"remote-only"}' > "$R5/alx/.bash_history.realhost.jsonl"
printf '%s\n' '{"t":5,"d":"/z","e":0,"c":"other2"}' > "$L5/.bash_history.other2.jsonl"
printf 'alx\n' > "$T/ssh_hosts6"
printf 'alx realhost\n' > "$T/hostnames"
(
  HOME=$L5 FAKE_REMOTE=$R5 FAKE_SSH_HOSTS=$T/ssh_hosts6 FAKE_HOSTNAMES=$T/hostnames PATH="$SHIM:$PATH" \
  "$B" sync alx
) >/dev/null 2>&1
assert_eq "name mismatch: own file (by reported name) not pushed" $'{"t":10,"d":"/x","e":0,"c":"shared"}\n{"t":20,"d":"/x","e":0,"c":"remote-only"}' \
  "$(cat "$R5/alx/.bash_history.realhost.jsonl")"
assert_eq "name mismatch: local merged" $'{"t":10,"d":"/x","e":0,"c":"shared"}\n{"t":20,"d":"/x","e":0,"c":"remote-only"}\n{"t":30,"d":"/x","e":0,"c":"local-only"}' \
  "$(cat "$L5/.bash_history.realhost.jsonl")"
[[ -f $R5/alx/.bash_history.other2.jsonl ]] && ok "name mismatch: other files still pushed" || bad "name mismatch: other files still pushed"

# sync: partial pull (rsync 23) merges what arrived, with a warning
L6=$T/partial_home; R6=$T/partial_remote
mkdir -p "$L6" "$R6/part"
printf '%s\n' '{"t":10,"d":"/x","e":0,"c":"shared"}' '{"t":30,"d":"/x","e":0,"c":"local-extra"}' > "$L6/.bash_history.part.jsonl"
printf '%s\n' '{"t":10,"d":"/x","e":0,"c":"shared"}' '{"t":20,"d":"/x","e":0,"c":"remote-extra"}' > "$R6/part/.bash_history.part.jsonl"
printf 'part\n' > "$T/ssh_hosts7"
printf 'part\n' > "$T/partial_hosts"
out=$(
  HOME=$L6 FAKE_REMOTE=$R6 FAKE_SSH_HOSTS=$T/ssh_hosts7 FAKE_RSYNC_PARTIAL=$T/partial_hosts PATH="$SHIM:$PATH" \
  "$B" sync part 2>&1
)
assert_eq "partial pull: merged what arrived" $'{"t":10,"d":"/x","e":0,"c":"shared"}\n{"t":20,"d":"/x","e":0,"c":"remote-extra"}\n{"t":30,"d":"/x","e":0,"c":"local-extra"}' \
  "$(cat "$L6/.bash_history.part.jsonl")"
[[ $out == *"pull incomplete (rsync 23)"* ]] && ok "partial pull: warned" || bad "partial pull: warned ($out)"

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

echo "# result"
if [[ $FAILS -eq 0 ]]; then
  echo "all tests passed"
else
  echo "$FAILS test(s) failed"
  exit 1
fi
