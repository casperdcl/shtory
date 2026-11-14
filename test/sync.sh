#!/usr/bin/env bash
# test: sync (shimmed ssh/rsync) (run via ./test.bash; standalone: bash test/sync.sh)
source ./test/common.sh

echo "# sync (shimmed ssh/rsync)"
SHIM=$T/shim; R=$T/remote; L=$T/rsync_home
mkdir -p "$SHIM" "$R/.shtory" "$L/.shtory"
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
cmd=''
for (( i = 0; i < ${#a[@]}; i++ )); do
  case ${a[i]} in
    -o) (( i++ )); continue ;; # skip -o and its value
    -*) continue ;;
    *) h=${a[i]}; cmd=${a[i+1]}; break ;;
  esac
done
if [[ -n ${FAKE_DOWN:-} ]] && grep -qx "$h" "$FAKE_DOWN"; then
  exit 255
fi
# run the remote command in the fake remote's $HOME (its .shtory/shtory.env is visible)
[[ -d $FAKE_REMOTE/$h ]] && home=$FAKE_REMOTE/$h || home=$FAKE_REMOTE
env -i PATH="$PATH" HOME="$home" HOSTNAME="$h" bash -c "$cmd"
EOF
cat > "$SHIM/rsync" <<'EOF'
#!/usr/bin/env bash
# portable stat (GNU -c / BSD -f)
sz() { stat -c %s -- "$1" 2>/dev/null || stat -f %z -- "$1"; }
mt() { stat -c %Y -- "$1" 2>/dev/null || stat -f %m -- "$1"; }
args=("$@")
src_arg=''; has_dd=0
for a in "${args[@]}"; do
  [[ $a == -- ]] && has_dd=1
  [[ $a == -* ]] && continue
  [[ -z $src_arg && $a == *:* ]] && src_arg=$a
done
# pull: no '--', host:src present; push: files after '--'
if [[ $has_dd -eq 0 && -n $src_arg ]]; then
  h=${src_arg%%:*}; dest=${args[$((${#args[@]} - 1))]}; n=0; m=0
  src="$FAKE_REMOTE/$h"; [[ -d $src ]] || src=$FAKE_REMOTE
  for f in "$src"/.shtory/*.jsonl; do
    [[ -e $f ]] || continue
    m=$((m + 1))
    b=${f##*/}; d="$dest/$b"
    # model rsync quick check: skip when size + mtime match
    if [[ -f $d && $(sz "$f") -eq $(sz "$d") \
      && $(mt "$f") -eq $(mt "$d") ]]; then
      continue
    fi
    cp -p "$f" "$dest/" && n=$((n + 1))
    [[ -n ${PULL_LOG:-} ]] && echo "pull $h $b" >> "$PULL_LOG"
  done
  if [[ -n ${FAKE_RSYNC_PARTIAL:-} ]] && grep -qx "$h" "$FAKE_RSYNC_PARTIAL"; then
    exit 23
  fi
  exit $((m == 0))
fi
i=0
while [[ ${args[i]-} != -- && $i -lt ${#args[@]} ]]; do i=$((i + 1)); done
[[ ${args[i]-} == -- ]] || exit 1
h=${args[$((${#args[@]} - 1))]%%:*}
dest=$FAKE_REMOTE
[[ -d $dest/$h ]] && dest=$dest/$h
mkdir -p "$dest/.shtory"
files=("${args[@]:i + 1: ${#args[@]} - i - 2}")
for f in "${files[@]}"; do
  b=${f##*/}; d="$dest/.shtory/$b"
  if [[ -f $d && $(sz "$f") -eq $(sz "$d") \
    && $(mt "$f") -eq $(mt "$d") ]]; then
    continue
  fi
  cp -p "$f" "$dest/.shtory/"
  [[ -n ${PUSH_LOG:-} ]] && echo "push $h $b" >> "$PUSH_LOG"
done
exit 0
EOF
chmod +x "$SHIM/ssh" "$SHIM/rsync"
printf '%s\n' '{"t":100,"d":"/a","e":0,"c":"local-only"}' '{"t":300,"d":"/a","e":0,"c":"shared"}' > "$L/.shtory/localhost.jsonl"
printf '%s\n' '{"t":200,"d":"/x","e":0,"c":"onA"}' '{"t":300,"d":"/a","e":0,"c":"shared"}' > "$L/.shtory/fakeA.jsonl"
chmod 600 "$L/.shtory/fakeA.jsonl"   # must survive the merge
printf '%s\n' '{"t":200,"d":"/x","e":0,"c":"onA"}' '{"t":300,"d":"/a","e":0,"c":"shared"}' '{"t":400,"d":"/y","e":1,"c":"remote-only"}' > "$R/.shtory/fakeA.jsonl"
printf '%s\n' '{"t":50,"d":"/z","e":0,"c":"fromB"}' > "$R/.shtory/fakeB.jsonl"
printf 'fakeA\nfakeB\n' > "$T/ssh_hosts"
(
  HOME=$L FAKE_REMOTE=$R FAKE_SSH_HOSTS=$T/ssh_hosts SHTORY_HOSTNAME=me \
    PATH="$SHIM:$PATH" "$B" sync
)
assert_eq "merged union, t-sorted" $'{"t":200,"d":"/x","e":0,"c":"onA"}\n{"t":300,"d":"/a","e":0,"c":"shared"}\n{"t":400,"d":"/y","e":1,"c":"remote-only"}' \
  "$(cat "$L/.shtory/fakeA.jsonl")"
[[ $(fmode "$L/.shtory/fakeA.jsonl") == 600 ]] && ok "sync merge preserves mode 600" || bad "sync merge preserves mode 600 ($(fmode "$L/.shtory/fakeA.jsonl"))"
assert_eq "missing file pulled" '{"t":50,"d":"/z","e":0,"c":"fromB"}' "$(cat "$L/.shtory/fakeB.jsonl")"
[[ -f $R/.shtory/localhost.jsonl ]] && ok "local-only pushed to remote" || bad "local-only pushed to remote"
cksum "$L"/.shtory/*.jsonl > "$T/m1"
(
  HOME=$L FAKE_REMOTE=$R FAKE_SSH_HOSTS=$T/ssh_hosts SHTORY_HOSTNAME=me \
    PATH="$SHIM:$PATH" "$B" sync
) >/dev/null 2>&1
cksum "$L"/.shtory/*.jsonl > "$T/m2"
if diff -q "$T/m1" "$T/m2" >/dev/null; then ok "idempotent"; else bad "idempotent"; fi
out=$(
  HOME=$L FAKE_REMOTE=$R FAKE_SSH_HOSTS=$T/ssh_hosts PATH="$SHIM:$PATH" \
    "$B" sync fakeA 2>&1
)
if [[ $out == *fakeA:*synced* && $out != *fakeB* ]]; then ok "explicit <host>: no auto-detect"; else bad "explicit <host>: no auto-detect ($out)"; fi

# auto-detect must skip the local host's own file (it is local, not a remote)
L4=$T/ad_home; R4=$T/ad_remote
mkdir -p "$L4/.shtory" "$R4/.shtory"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"on-me"}' > "$L4/.shtory/me.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"stale"}' > "$L4/.shtory/dev1.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"stale"}' '{"t":2,"d":"/x","e":0,"c":"on-remote"}' > "$R4/.shtory/dev1.jsonl"
printf 'dev1\n' > "$T/ssh_hosts5"
out=$(
  HOME=$L4 FAKE_REMOTE=$R4 FAKE_SSH_HOSTS=$T/ssh_hosts5 SHTORY_HOSTNAME=me \
  PATH="$SHIM:$PATH" "$B" sync 2>&1
)
if [[ $out == *dev1:*synced* && $out != *me* ]]; then ok "auto-detect skips local host"; else bad "auto-detect skips local host ($out)"; fi
[[ -f $R4/.shtory/me.jsonl ]] && ok "local file still pushed to remote" || bad "local file still pushed to remote"
assert_eq "auto-detect: remote file merged locally" $'{"t":1,"d":"/x","e":0,"c":"stale"}\n{"t":2,"d":"/x","e":0,"c":"on-remote"}' \
  "$(cat "$L4/.shtory/dev1.jsonl")"

# unreachable host (ssh rc 255) is skipped, not hung on
out=$(
  HOME=$L4 FAKE_REMOTE=$R4 FAKE_SSH_HOSTS=$T/ssh_hosts5 FAKE_DOWN=$T/ssh_hosts5 SHTORY_HOSTNAME=me \
  PATH="$SHIM:$PATH" "$B" sync dev1 2>&1
)
if [[ $out == *dev1:*unreachable* ]]; then ok "unreachable host skipped"; else bad "unreachable host skipped ($out)"; fi

# multi-host: every host must receive the full merge (per-host loop left later hosts stale)
M=$T/mh_remote
for h in mA mB mC; do mkdir -p "$M/$h/.shtory"; done
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"a1"}' '{"t":2,"d":"/x","e":0,"c":"a2"}' > "$M/mA/.shtory/mA.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"b1"}' > "$M/mA/.shtory/mB.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"c1"}' > "$M/mA/.shtory/mC.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"a1"}' > "$M/mB/.shtory/mA.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"b1"}' '{"t":2,"d":"/x","e":0,"c":"b2"}' > "$M/mB/.shtory/mB.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"c1"}' > "$M/mB/.shtory/mC.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"a1"}' > "$M/mC/.shtory/mA.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"b1"}' > "$M/mC/.shtory/mB.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"c1"}' '{"t":2,"d":"/x","e":0,"c":"c2"}' > "$M/mC/.shtory/mC.jsonl"
MH=$T/mh_home; mkdir -p "$MH/.shtory"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"a1"}' > "$MH/.shtory/mA.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"b1"}' > "$MH/.shtory/mB.jsonl"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"c1"}' > "$MH/.shtory/mC.jsonl"
printf 'mA\nmB\nmC\n' > "$T/ssh_hosts4"
(
  HOME=$MH FAKE_REMOTE=$M FAKE_SSH_HOSTS=$T/ssh_hosts4 PATH="$SHIM:$PATH" \
  "$B" sync mA mB mC
) >/dev/null 2>&1
assert_eq "multi-host: mA got mC's new line" $'{"t":1,"d":"/x","e":0,"c":"c1"}\n{"t":2,"d":"/x","e":0,"c":"c2"}' \
  "$(cat "$M/mA/.shtory/mC.jsonl")"
assert_eq "multi-host: mC got mB's new line" $'{"t":1,"d":"/x","e":0,"c":"b1"}\n{"t":2,"d":"/x","e":0,"c":"b2"}' \
  "$(cat "$M/mC/.shtory/mB.jsonl")"
assert_eq "multi-host: local merged everything" $'{"t":1,"d":"/x","e":0,"c":"a1"}\n{"t":2,"d":"/x","e":0,"c":"a2"}' \
  "$(cat "$MH/.shtory/mA.jsonl")"

# sync --compact
L3=$T/cp_home; R3=$T/cp_remote
mkdir -p "$L3/.shtory" "$R3/.shtory"
printf '%s\n' '{"t":100,"d":"/a","e":0,"c":"old1"}' '{"t":300,"d":"/a","e":0,"c":"shared"}' '{"t":400,"d":"/a","e":0,"c":"new"}' > "$L3/.shtory/hostX.jsonl"
printf '%s\n' '{"t":300,"d":"/a","e":0,"c":"shared"}' '{"t":400,"d":"/a","e":0,"c":"new"}' '{"t":500,"d":"/a","e":0,"c":"remote-new"}' > "$R3/.shtory/hostX.jsonl"
printf '%s\n' '{"t":50,"d":"/z","e":0,"c":"local-only"}' > "$L3/.shtory/other.jsonl"
printf 'hostX\n' > "$T/ssh_hosts3"
(
  HOME=$L3 FAKE_REMOTE=$R3 FAKE_SSH_HOSTS=$T/ssh_hosts3 PATH="$SHIM:$PATH" \
  "$B" sync --compact 2 hostX
) >/dev/null 2>&1
assert_eq "sync --compact: merged then capped to newest N" $'{"t":400,"d":"/a","e":0,"c":"new"}\n{"t":500,"d":"/a","e":0,"c":"remote-new"}' \
  "$(cat "$L3/.shtory/hostX.jsonl")"
assert_eq "sync --compact: push carries compacted files" '{"t":50,"d":"/z","e":0,"c":"local-only"}' \
  "$(cat "$R3/.shtory/other.jsonl")"
assert_eq "sync --compact implies --self: own file pushed compacted" $'{"t":400,"d":"/a","e":0,"c":"new"}\n{"t":500,"d":"/a","e":0,"c":"remote-new"}' \
  "$(cat "$R3/.shtory/hostX.jsonl")"
HOME=$L3 "$B" sync --compact abc hostX >/dev/null 2>&1; assert_rc "sync --compact bad N rc 2" 2 $?
HOME=$L3 "$B" sync --compact >/dev/null 2>&1; assert_rc "sync --compact requires N" 1 $?

# sync --self
L4=$T/self_home; R4=$T/self_remote
mkdir -p "$L4/.shtory" "$R4/.shtory"
printf '%s\n' '{"t":10,"d":"/x","e":0,"c":"shared"}' '{"t":30,"d":"/x","e":0,"c":"local-only"}' > "$L4/.shtory/hostY.jsonl"
printf '%s\n' '{"t":10,"d":"/x","e":0,"c":"shared"}' '{"t":20,"d":"/x","e":0,"c":"remote-only"}' > "$R4/.shtory/hostY.jsonl"
printf '%s\n' '{"t":5,"d":"/z","e":0,"c":"other2"}' > "$L4/.shtory/other2.jsonl"
printf 'hostY\n' > "$T/ssh_hosts5"
(
  HOME=$L4 FAKE_REMOTE=$R4 FAKE_SSH_HOSTS=$T/ssh_hosts5 PATH="$SHIM:$PATH" \
  "$B" sync hostY
) >/dev/null 2>&1
assert_eq "sync: own file not pushed by default" $'{"t":10,"d":"/x","e":0,"c":"shared"}\n{"t":20,"d":"/x","e":0,"c":"remote-only"}' \
  "$(cat "$R4/.shtory/hostY.jsonl")"
(
  HOME=$L4 FAKE_REMOTE=$R4 FAKE_SSH_HOSTS=$T/ssh_hosts5 PATH="$SHIM:$PATH" \
  "$B" sync --self hostY
) >/dev/null 2>&1
assert_eq "sync --self: own file pushed" $'{"t":10,"d":"/x","e":0,"c":"shared"}\n{"t":20,"d":"/x","e":0,"c":"remote-only"}\n{"t":30,"d":"/x","e":0,"c":"local-only"}' \
  "$(cat "$R4/.shtory/hostY.jsonl")"

# sync: host's reported name differs from the ssh alias
L5=$T/name_home; R5=$T/name_remote
mkdir -p "$L5/.shtory" "$R5/alx/.shtory"
printf '%s\n' '{"t":10,"d":"/x","e":0,"c":"shared"}' '{"t":30,"d":"/x","e":0,"c":"local-only"}' > "$L5/.shtory/realhost.jsonl"
printf '%s\n' '{"t":10,"d":"/x","e":0,"c":"shared"}' '{"t":20,"d":"/x","e":0,"c":"remote-only"}' > "$R5/alx/.shtory/realhost.jsonl"
touch -d '2020-01-01'  2>/dev/null || touch -t 202001010000 "$R5/alx/.shtory/realhost.jsonl"   # same size, different content: force mtime mismatch
printf '%s\n' '{"t":5,"d":"/z","e":0,"c":"other2"}' > "$L5/.shtory/other2.jsonl"
printf 'alx\n' > "$T/ssh_hosts6"
printf 'SHTORY_HOSTNAME=realhost\n' > "$R5/alx/.shtory/shtory.env"
(
  HOME=$L5 FAKE_REMOTE=$R5 FAKE_SSH_HOSTS=$T/ssh_hosts6 PATH="$SHIM:$PATH" \
  "$B" sync alx
) >/dev/null 2>&1
assert_eq "name mismatch: own file (by reported name) not pushed" $'{"t":10,"d":"/x","e":0,"c":"shared"}\n{"t":20,"d":"/x","e":0,"c":"remote-only"}' \
  "$(cat "$R5/alx/.shtory/realhost.jsonl")"
assert_eq "name mismatch: local merged" $'{"t":10,"d":"/x","e":0,"c":"shared"}\n{"t":20,"d":"/x","e":0,"c":"remote-only"}\n{"t":30,"d":"/x","e":0,"c":"local-only"}' \
  "$(cat "$L5/.shtory/realhost.jsonl")"
[[ -f $R5/alx/.shtory/other2.jsonl ]] && ok "name mismatch: other files still pushed" || bad "name mismatch: other files still pushed"

# plain sync trims stale t:0 imports (import_history's dedup, re-run on the merged union)
L7=$T/stale_home; R7=$T/stale_remote
mkdir -p "$L7/.shtory" "$R7/h7/.shtory"
printf '%s\n' '{"t":0,"d":"","e":0,"c":"stale"}' '{"t":0,"d":"","e":0,"c":"kept"}' > "$L7/.shtory/me.jsonl"
printf '%s\n' '{"t":0,"d":"","e":0,"c":"stale"}' '{"t":0,"d":"","e":0,"c":"kept"}' '{"t":1,"d":"/x","e":0,"c":"stale"}' > "$R7/h7/.shtory/me.jsonl"
printf 'h7\n' > "$T/ssh_hosts8"
(
  HOME=$L7 FAKE_REMOTE=$R7 FAKE_SSH_HOSTS=$T/ssh_hosts8 SHTORY_HOSTNAME=me \
  PATH="$SHIM:$PATH" "$B" sync h7
) >/dev/null 2>&1
assert_eq "sync trims stale t:0 (live counterpart in same file)" $'{"t":0,"d":"","e":0,"c":"kept"}\n{"t":1,"d":"/x","e":0,"c":"stale"}' \
  "$(cat "$L7/.shtory/me.jsonl")"
assert_eq "trimmed t:0 not re-pushed to remote" $'{"t":0,"d":"","e":0,"c":"kept"}\n{"t":1,"d":"/x","e":0,"c":"stale"}' \
  "$(cat "$R7/h7/.shtory/me.jsonl")"

# SHTORY_SAFE=1: jq merge fallback (union, t-sort, dedupe, stale t:0 trim)
L9=$T/safe_home; R9=$T/safe_remote
mkdir -p "$L9/.shtory" "$R9/h9/.shtory"
printf '%s\n' '{"t":0,"d":"","e":0,"c":"stale"}' '{"t":0,"d":"","e":0,"c":"kept"}' '{"t":300,"d":"/a","e":0,"c":"shared"}' '{"t":100,"d":"/b","e":0,"c":"local-only"}' > "$L9/.shtory/h9.jsonl"
printf '%s\n' '{"t":0,"d":"","e":0,"c":"stale"}' '{"t":0,"d":"","e":0,"c":"kept"}' '{"t":1,"d":"/x","e":0,"c":"stale"}' '{"t":200,"d":"/c","e":0,"c":"remote-only"}' '{"t":300,"d":"/a","e":0,"c":"shared"}' > "$R9/h9/.shtory/h9.jsonl"
printf 'h9\n' > "$T/ssh_hosts10"
(
  HOME=$L9 FAKE_REMOTE=$R9 FAKE_SSH_HOSTS=$T/ssh_hosts10 SHTORY_SAFE=1 SHTORY_HOSTNAME=me \
  PATH="$SHIM:$PATH" "$B" sync h9
) >/dev/null 2>&1
assert_eq "SHTORY_SAFE=1: jq merge union, t-sorted, stale t:0 trimmed" \
  $'{"t":0,"d":"","e":0,"c":"kept"}\n{"t":1,"d":"/x","e":0,"c":"stale"}\n{"t":100,"d":"/b","e":0,"c":"local-only"}\n{"t":200,"d":"/c","e":0,"c":"remote-only"}\n{"t":300,"d":"/a","e":0,"c":"shared"}' \
  "$(cat "$L9/.shtory/h9.jsonl")"

# sync: partial pull (rsync 23) merges what arrived, with a warning
L6=$T/partial_home; R6=$T/partial_remote
mkdir -p "$L6/.shtory" "$R6/part/.shtory"
printf '%s\n' '{"t":10,"d":"/x","e":0,"c":"shared"}' '{"t":30,"d":"/x","e":0,"c":"local-extra"}' > "$L6/.shtory/part.jsonl"
printf '%s\n' '{"t":10,"d":"/x","e":0,"c":"shared"}' '{"t":20,"d":"/x","e":0,"c":"remote-extra"}' > "$R6/part/.shtory/part.jsonl"
touch -d '2020-01-01'  2>/dev/null || touch -t 202001010000 "$R6/part/.shtory/part.jsonl"   # same size, different content: force mtime mismatch
printf 'part\n' > "$T/ssh_hosts7"
printf 'part\n' > "$T/partial_hosts"
out=$(
  HOME=$L6 FAKE_REMOTE=$R6 FAKE_SSH_HOSTS=$T/ssh_hosts7 FAKE_RSYNC_PARTIAL=$T/partial_hosts PATH="$SHIM:$PATH" \
  "$B" sync part 2>&1
)
assert_eq "partial pull: merged what arrived" $'{"t":10,"d":"/x","e":0,"c":"shared"}\n{"t":20,"d":"/x","e":0,"c":"remote-extra"}\n{"t":30,"d":"/x","e":0,"c":"local-extra"}' \
  "$(cat "$L6/.shtory/part.jsonl")"
[[ $out == *"pull incomplete (rsync 23)"* ]] && ok "partial pull: warned" || bad "partial pull: warned ($out)"

# sync: unchanged files are not re-transferred (rsync quick check, pull & push)
L8=$T/nt_home; R8=$T/nt_remote
mkdir -p "$L8/.shtory" "$R8/nt/.shtory"
printf '%s\n' '{"t":1,"d":"/x","e":0,"c":"same"}' > "$L8/.shtory/nt.jsonl"
printf '%s\n' '{"t":2,"d":"/x","e":0,"c":"other"}' > "$L8/.shtory/other.jsonl"
cp -p "$L8"/.shtory/*.jsonl "$R8/nt/.shtory/"   # remote identical, same size + mtime
printf 'nt\n' > "$T/ssh_hosts9"
: > "$T/nt_log"
(
  HOME=$L8 FAKE_REMOTE=$R8 FAKE_SSH_HOSTS=$T/ssh_hosts9 PULL_LOG="$T/nt_log" PUSH_LOG="$T/nt_log" SHTORY_HOSTNAME=me \
  PATH="$SHIM:$PATH" "$B" sync nt
) >/dev/null 2>&1
if [[ -s $T/nt_log ]]; then bad "unchanged files not re-transferred ($(tr '\n' ' ' < "$T/nt_log"))"; else ok "unchanged files not re-transferred"; fi
