#!/usr/bin/env bash
# test: stats / compact (run via ./test.bash; needs $S from test/search.sh)
source ./test/common.sh

echo "# stats / compact"
assert_eq "stats hostA" '{"host":"hostA","commands":5,"first":"1970-01-01T00:16:40Z","last":"1970-01-01T00:23:20Z","failed":1}' \
  "$(HOME=$S "$B" stats | grep hostA)"
# t:0 (imported, untimestamped) entries don't count as the first command
T0=$T/t0_home; mkdir -p "$T0"
printf '%s\n' '{"t":0,"d":"","e":0,"c":"imported"}' '{"t":500,"d":"/a","e":0,"c":"live1"}' '{"t":300,"d":"/a","e":0,"c":"live2"}' > "$T0/.bash_history.hostZ.jsonl"
assert_eq "stats skips t:0 for first" '{"host":"hostZ","commands":3,"first":"1970-01-01T00:05:00Z","last":"1970-01-01T00:08:20Z","failed":0}' \
  "$(HOME=$T0 "$B" stats | grep hostZ)"
printf '%s\n' '{"t":0,"d":"","e":0,"c":"imported"}' > "$T0/.bash_history.hostY.jsonl"
assert_eq "stats all-t:0: first null" '{"host":"hostY","commands":1,"first":null,"last":"1970-01-01T00:00:00Z","failed":0}' \
  "$(HOME=$T0 "$B" stats | grep hostY)"
printf '%s\n' \
  '{"t":1,"d":"/uniquedir1","e":0,"c":"zzztop"}' '{"t":2,"d":"/uniquedir1","e":0,"c":"zzztop"}' \
  '{"t":3,"d":"/uniquedir1","e":0,"c":"zzztop"}' '{"t":4,"d":"/uniquedir1","e":0,"c":"qqq"}' \
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
