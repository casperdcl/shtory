#!/usr/bin/env bash
# test: stats / compact (run via ./test.bash; needs $S from test/search.sh)
source ./test/common.sh
unset SHTORY_GIST_ID SHTORY_GIST_FILE # never touch a real gist in tests

echo "# stats / compact"
assert_eq "stats hostA" '{"host":"hostA","commands":5,"first":"1970-01-01T00:16:40Z","last":"1970-01-01T00:23:20Z","failed":1}' \
  "$(HOME=$S "$B" stats | grep hostA)"
# t:0 (imported, untimestamped) entries don't count as the first command
T0=$T/t0_home; mkdir -p "$T0"
printf '%s\n' '{"t":0,"d":"","e":0,"c":"imported"}' '{"t":500,"d":"/a","e":0,"c":"live1"}' '{"t":300,"d":"/a","e":0,"c":"live2"}' > "$T0/.shtory.hostZ.jsonl"
assert_eq "stats skips t:0 for first" '{"host":"hostZ","commands":3,"first":"1970-01-01T00:05:00Z","last":"1970-01-01T00:08:20Z","failed":0}' \
  "$(HOME=$T0 "$B" stats | grep hostZ)"
printf '%s\n' '{"t":0,"d":"","e":0,"c":"imported"}' > "$T0/.shtory.hostY.jsonl"
assert_eq "stats all-t:0: first null" '{"host":"hostY","commands":1,"first":null,"last":"1970-01-01T00:00:00Z","failed":0}' \
  "$(HOME=$T0 "$B" stats | grep hostY)"
# stats --timeline: per-host activity histogram on a shared time axis
# setsid: drop the controlling tty so the bar width stays 40 regardless of the dev's terminal size
G=$T/g_home; mkdir -p "$G"
printf '%s\n' '{"t":10,"d":"/a","e":0,"c":"a0"}' '{"t":11,"d":"/a","e":0,"c":"a1"}' '{"t":12,"d":"/a","e":0,"c":"a2"}' '{"t":110,"d":"/a","e":0,"c":"a3"}' '{"t":114,"d":"/a","e":0,"c":"a4"}' '{"t":210,"d":"/a","e":0,"c":"a5"}' > "$G/.shtory.aa.jsonl"
printf '%s\n' '{"t":10,"d":"/a","e":0,"c":"b0"}' '{"t":20,"d":"/a","e":0,"c":"b1"}' '{"t":30,"d":"/a","e":0,"c":"b2"}' '{"t":40,"d":"/a","e":0,"c":"b3"}' > "$G/.shtory.bb.jsonl"
printf '%s\n' '{"t":0,"d":"","e":0,"c":"imported"}' > "$G/.shtory.hostZ0.jsonl"   # t:0-only host skipped
assert_eq "stats --timeline" "$(cat <<'EOF'
       1970-01-01                    1970-01-01  cmds days
TOTAL  █ ▂ ▂ ▂             ▄                  ▂    10    0
   aa  █                   ▅                  ▂     6    0
   bb  █ █ █ █                                      4    0
EOF
)" "$(HOME=$G setsid "$B" stats --timeline)"
G1=$T/g1_home; mkdir -p "$G1"
printf '{"t":1000,"d":"/a","e":0,"c":"solo"}\n' > "$G1/.shtory.solo.jsonl"
assert_eq "stats --timeline single point" $'       1970-01-01                    1970-01-01  cmds days\nTOTAL  █                                            1    0\n solo  █                                            1    0' \
  "$(HOME=$G1 setsid "$B" stats --timeline)"
# alignment: 2-digit counts/days right-align with 1-digit ones
GA=$T/ga_home; mkdir -p "$GA"
printf '%s\n' '{"t":10,"d":"/a","e":0,"c":"x0"}' '{"t":11,"d":"/a","e":0,"c":"x1"}' '{"t":12,"d":"/a","e":0,"c":"x2"}' '{"t":13,"d":"/a","e":0,"c":"x3"}' '{"t":14,"d":"/a","e":0,"c":"x4"}' '{"t":15,"d":"/a","e":0,"c":"x5"}' '{"t":16,"d":"/a","e":0,"c":"x6"}' '{"t":17,"d":"/a","e":0,"c":"x7"}' '{"t":18,"d":"/a","e":0,"c":"x8"}' '{"t":19,"d":"/a","e":0,"c":"x9"}' '{"t":1041810,"d":"/a","e":0,"c":"x10"}' '{"t":1041814,"d":"/a","e":0,"c":"x11"}' > "$GA/.shtory.h1.jsonl"
printf '%s\n' '{"t":5,"d":"/a","e":0,"c":"y0"}' '{"t":6,"d":"/a","e":0,"c":"y1"}' '{"t":7,"d":"/a","e":0,"c":"y2"}' > "$GA/.shtory.h2.jsonl"
assert_eq "stats --timeline right-aligns counts/days" "$(cat <<'EOF'
       1970-01-01                    1970-01-13  cmds days
TOTAL  █                                      ▁    15   12
   h1  █                                      ▁    12   12
   h2  █                                            3    0
EOF
)" "$(HOME=$GA setsid "$B" stats --timeline)"
HOME=$G "$B" stats --timeline --cmd 2 >/dev/null 2>&1; assert_rc "stats --timeline exclusive rc 2" 2 $?
GN=$T/gn_home; mkdir -p "$GN"
printf '{"t":0,"d":"","e":0,"c":"i"}\n' > "$GN/.shtory.h.jsonl"
out=$(HOME=$GN "$B" stats --timeline 2>&1); rc=$?
assert_rc "stats --timeline t:0-only rc 1" 1 $rc
[[ $out == *"no history with timestamps"* ]] && ok "stats --timeline t:0-only warns" || bad "stats --timeline t:0-only warns ($out)"
# gist: SHTORY_GIST_ID makes --timeline push the histogram text via `gh gist edit`
GB=$T/ghbin; mkdir -p "$GB"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$@" > "$0.args"' 'cp -- "${!#}" "$0.file"' > "$GB/gh"
chmod +x "$GB/gh"
out=$(PATH="$GB:$PATH" SHTORY_GIST_ID=g1 HOME=$G setsid "$B" stats --timeline 2>&1); rc=$?
assert_rc "gist gh rc 0" 0 $rc
[[ $out == *"shtory: gist g1 updated"* ]] && ok "gist success message" || bad "gist success message ($out)"
[[ $(cat "$GB/gh.args") == $'gist\nedit\ng1\n-f\nshtory.stats\n/'*'/shtory.stats' ]] && ok "gist gh args + default file" || bad "gist gh args + default file ($(cat "$GB/gh.args" | tr '\n' ' '))"
grep -q 'aa' "$GB/gh.file" && [[ $(head -1 "$GB/gh.file") == *" cmds days" ]] && ok "gist text content" || bad "gist text content ($(head -1 "$GB/gh.file"))"
LC_ALL=C.UTF-8 bash -c '
  rc=0
  while IFS= read -r l; do (( ${#l} <= 50 )) || rc=1; done < "$1"
  exit $rc' _ "$GB/gh.file"
[[ $? -eq 0 ]] && ok "gist lines <= 50 chars" || bad "gist lines <= 50 chars"
rm -f "$GB/gh.args"
PATH="$GB:$PATH" SHTORY_GIST_ID=g1 SHTORY_GIST_FILE=hist.txt HOME=$G setsid "$B" stats --timeline >/dev/null
[[ $(sed -n 5p "$GB/gh.args") == hist.txt && $(tail -1 "$GB/gh.args") == /*/hist.txt ]] && ok "gist SHTORY_GIST_FILE override" || bad "gist SHTORY_GIST_FILE override ($(tr '\n' ' ' < "$GB/gh.args"))"
rm -f "$GB/gh.args"
HOME=$G setsid "$B" stats --timeline >/dev/null
[[ ! -e $GB/gh.args ]] && ok "gist not called without SHTORY_GIST_ID" || bad "gist not called without SHTORY_GIST_ID"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$GB/gh"
PATH="$GB:$PATH" SHTORY_GIST_ID=g1 HOME=$G setsid "$B" stats --timeline >/dev/null 2>&1
assert_rc "gist gh failure propagates" 1 $?
# empty gist: -f fails with "no file" -> retry with -a
cat > "$GB/gh" <<'EOF'
#!/usr/bin/env bash
if [[ $4 == -f ]]; then
  echo 'gist has no file "x"' >&2
  exit 1
fi
printf '%s\n' "$@" > "$0.args"
EOF
chmod +x "$GB/gh"
rm -f "$GB/gh.args"
PATH="$GB:$PATH" SHTORY_GIST_ID=g1 HOME=$G setsid "$B" stats --timeline >/dev/null 2>&1
assert_rc "gist -a fallback rc 0" 0 $?
[[ $(sed -n 4p "$GB/gh.args") == -a && $(sed -n 5p "$GB/gh.args") == shtory.stats ]] && ok "gist -a fallback args" || bad "gist -a fallback args ($(tr '\n' ' ' < "$GB/gh.args"))"
printf '%s\n' \
  '{"t":1,"d":"/uniquedir1","e":0,"c":"zzztop"}' '{"t":2,"d":"/uniquedir1","e":0,"c":"zzztop"}' \
  '{"t":3,"d":"/uniquedir1","e":0,"c":"zzztop"}' '{"t":4,"d":"/uniquedir1","e":0,"c":"qqq"}' \
  '{"t":5,"d":"/uniquedir2","e":0,"c":"qqq"}' > "$S/.shtory.hostS.jsonl"
assert_eq "stats --cmd 2" $'3\tzzztop\n2\tgit status' "$(HOME=$S "$B" stats --cmd 2)"
assert_eq "stats --dir 1" $'5\t/x' "$(HOME=$S "$B" stats --dir 1)"
HOME=$S "$B" stats --cmd x >/dev/null 2>&1; assert_rc "stats bad --cmd rc 2" 2 $?
for i in $(seq 1 15); do
  printf '{"t":%s,"d":"/z","e":0,"c":"filler %s"}\n' "$((60 + i))" "$i" >> "$S/.shtory.hostB.jsonl"
done
HOME=$S "$B" compact 3
assert_eq "compact keeps newest 3" "3" "$(wc -l < "$S/.shtory.hostB.jsonl")"
assert_eq "compact sorted by t" "75 900 1500" "$(jq -r .t "$S/.shtory.hostB.jsonl" | tr '\n' ' ' | sed 's/ $//')"
HOME=$S "$B" compact abc >/dev/null 2>&1; assert_rc "compact bad cap rc 2" 2 $?
HOME=$S "$B" compact >/dev/null 2>&1; assert_rc "compact requires <N>" 2 $?
# compact edge: n>length keeps all (deduped, ascending); n=0 empties
CE=$T/compactedge; mkdir -p "$CE"
printf '%s\n' '{"t":1,"d":"/z","e":0,"c":"a"}' '{"t":5,"d":"/z","e":0,"c":"b"}' '{"t":3,"d":"/z","e":0,"c":"c"}' '{"t":3,"d":"/z","e":0,"c":"c"}' > "$CE/.shtory.e.jsonl"
HOME=$CE "$B" compact 10
assert_eq "compact n>length: keep all, deduped, ascending" "1 3 5" "$(jq -r .t "$CE/.shtory.e.jsonl" | tr '\n' ' ' | sed 's/ $//')"
HOME=$CE "$B" compact 0
assert_eq "compact n=0: empties" "0" "$(wc -l < "$CE/.shtory.e.jsonl")"
printf '%s\n' '{"t":1,"d":"/z","e":0,"c":"a"}' '{"t":2,"d":"/z","e":0,"c":"b"}' > "$CE/.shtory.m.jsonl"
chmod 600 "$CE/.shtory.m.jsonl"
HOME=$CE "$B" compact 5
[[ $(stat -c %a "$CE/.shtory.m.jsonl") == 600 ]] && ok "compact preserves mode 600" || bad "compact preserves mode 600 ($(stat -c %a "$CE/.shtory.m.jsonl"))"
