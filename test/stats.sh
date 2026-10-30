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
# stats --timeline: per-host activity histogram on a shared time axis
G=$T/g_home; mkdir -p "$G"
printf '%s\n' '{"t":10,"d":"/a","e":0,"c":"a0"}' '{"t":11,"d":"/a","e":0,"c":"a1"}' '{"t":12,"d":"/a","e":0,"c":"a2"}' '{"t":110,"d":"/a","e":0,"c":"a3"}' '{"t":114,"d":"/a","e":0,"c":"a4"}' '{"t":210,"d":"/a","e":0,"c":"a5"}' > "$G/.bash_history.aa.jsonl"
printf '%s\n' '{"t":10,"d":"/a","e":0,"c":"b0"}' '{"t":20,"d":"/a","e":0,"c":"b1"}' '{"t":30,"d":"/a","e":0,"c":"b2"}' '{"t":40,"d":"/a","e":0,"c":"b3"}' > "$G/.bash_history.bb.jsonl"
printf '%s\n' '{"t":0,"d":"","e":0,"c":"imported"}' > "$G/.bash_history.hostZ0.jsonl"   # t:0-only host skipped
assert_eq "stats --timeline" "$(cat <<'EOF'
    1970-01-01                    1970-01-01  cmds days
aa  █                   ▅                  ▂     6    0
bb  █ █ █ █                                      4    0
EOF
)" "$(HOME=$G setsid "$B" stats --timeline)"
G1=$T/g1_home; mkdir -p "$G1"
printf '{"t":1000,"d":"/a","e":0,"c":"solo"}\n' > "$G1/.bash_history.solo.jsonl"
assert_eq "stats --timeline single point" $'      1970-01-01                    1970-01-01  cmds days\nsolo  █                                            1    0' \
  "$(HOME=$G1 setsid "$B" stats --timeline)"
# alignment: 2-digit counts/days right-align with 1-digit ones
GA=$T/ga_home; mkdir -p "$GA"
printf '%s\n' '{"t":10,"d":"/a","e":0,"c":"x0"}' '{"t":11,"d":"/a","e":0,"c":"x1"}' '{"t":12,"d":"/a","e":0,"c":"x2"}' '{"t":13,"d":"/a","e":0,"c":"x3"}' '{"t":14,"d":"/a","e":0,"c":"x4"}' '{"t":15,"d":"/a","e":0,"c":"x5"}' '{"t":16,"d":"/a","e":0,"c":"x6"}' '{"t":17,"d":"/a","e":0,"c":"x7"}' '{"t":18,"d":"/a","e":0,"c":"x8"}' '{"t":19,"d":"/a","e":0,"c":"x9"}' '{"t":1041810,"d":"/a","e":0,"c":"x10"}' '{"t":1041814,"d":"/a","e":0,"c":"x11"}' > "$GA/.bash_history.h1.jsonl"
printf '%s\n' '{"t":5,"d":"/a","e":0,"c":"y0"}' '{"t":6,"d":"/a","e":0,"c":"y1"}' '{"t":7,"d":"/a","e":0,"c":"y2"}' > "$GA/.bash_history.h2.jsonl"
assert_eq "stats --timeline right-aligns counts/days" "$(cat <<'EOF'
    1970-01-01                    1970-01-13  cmds days
h2  █                                            3    0
h1  █                                      ▁    12   12
EOF
)" "$(HOME=$GA setsid "$B" stats --timeline)"
HOME=$G "$B" stats --timeline --cmd 2 >/dev/null 2>&1; assert_rc "stats --timeline exclusive rc 2" 2 $?
GN=$T/gn_home; mkdir -p "$GN"
printf '{"t":0,"d":"","e":0,"c":"i"}\n' > "$GN/.bash_history.h.jsonl"
out=$(HOME=$GN "$B" stats --timeline 2>&1); rc=$?
assert_rc "stats --timeline t:0-only rc 1" 1 $rc
[[ $out == *"no history with timestamps"* ]] && ok "stats --timeline t:0-only warns" || bad "stats --timeline t:0-only warns ($out)"
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
