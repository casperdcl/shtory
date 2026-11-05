#!/usr/bin/env bash
# test: search (run via ./test.bash; standalone: bash test/search.sh)
source ./test/common.sh

echo "# search"
S=$T/searchhome; D=$T/work; mkdir -p "$S" "$D"
cat > "$S/.shtory.hostA.jsonl" <<EOF
{"t":1000,"d":"$D","e":0,"c":"git status"}
{"t":1100,"d":"$D","e":0,"c":"git status"}
{"t":1200,"d":"$D","e":1,"c":"make build"}
{"t":1300,"d":"/var/log","e":0,"c":"tail -f app.log"}
{"t":1400,"d":"$D","e":0,"c":"grep -E 'a|b' conf.yml"}
EOF
cat > "$S/.shtory.hostB.jsonl" <<'EOF'
{"t":900,"d":"/home/u","e":0,"c":"echo fromB"}
{"t":1500,"d":"/root","e":1,"c":"make test"}
EOF
for h in lap-01 lap-top laptop prefix-lap-01 desktop-personal; do
  printf '{"t":1,"d":"/x","e":0,"c":"cmd-on-%s"}\n' "$h" > "$S/.shtory.$h.jsonl"
done
run(){ HOME=$S "$B" search "$@"; }
assert_eq "default host is all" "git status" "$(run git)"
assert_eq "glob lap-* (excl. laptop, desktop-personal)" $'cmd-on-lap-01\ncmd-on-lap-top' "$(run -h 'lap-*')"
assert_eq "glob host*" $'make test\nmake build' "$(run -h 'host*' make)"
assert_eq "-H = -h local host" "git status" "$(SHTORY_HOSTNAME=hostA run -H git)"
assert_eq "--localhost" "git status" "$(SHTORY_HOSTNAME=hostA run --localhost git)"
assert_eq "query, deduped" "git status" "$(run -h hostA git)"
assert_eq "case-insensitive" "git status" "$(run -h hostA GIT)"
assert_eq "-Z all hosts, newest first" $'make test\nmake build' "$(run -h '*' -Z -s newest)"
assert_eq "-z" "echo fromB" "$(run -h hostB -z)"
assert_eq "-c cwd filter" $'grep -E \'a|b\' conf.yml\nmake build\ngit status' \
  "$(cd "$D" && HOME=$S "$B" search -h hostA -c -s newest)"
assert_eq "-s count, top is dup" "git status" "$(run -h hostA -s count | head -1)"
assert_eq "-s frecency (default): frequent beats newer" "git status" "$(run -h hostA | head -1)"
assert_eq "-s newest: newer beats frequent" "grep -E 'a|b' conf.yml" "$(run -h hostA -s newest | head -1)"
assert_eq "-s oldest -n 2" $'git status\nmake build' "$(run -h hostA -s oldest -n 2)"
assert_eq "-n 1 across hosts" "make test" "$(run -h '*' -n 1 -s newest)"
assert_eq "-n 0 = no limit" $'grep -E \'a|b\' conf.yml\ntail -f app.log\nmake build\ngit status' "$(run -h hostA -n 0 -s newest)"
assert_eq "regex query" "make build" "$(run -h hostA 'make .*')"
run -h hostA '([' >/dev/null 2>&1; rc=$?
[[ $rc -ne 0 ]] && ok "bad regex nonzero rc" || bad "bad regex nonzero rc"
run -h nosuch >/dev/null 2>&1; assert_rc "missing host rc 1" 1 $?
out=$(HOME=$S "$B" search -h hostA 'nope' 2>/dev/null); assert_eq "no match empty" "" "$out"
cat > "$S/.shtory.hostT.jsonl" <<EOF
{"t":1,"d":"$S","e":0,"c":"in-home"}
{"t":2,"d":"$S/sub","e":0,"c":"in-sub"}
{"t":3,"d":"$S-x","e":0,"c":"in-sibling"}
EOF
rows(){ HOME=$S shtory_fn "cwd= efilter= order=newest limit=1000 files=(\"$S/.shtory.hostT.jsonl\"); query '$1' rows"; }
assert_eq "path: home itself is ~" $'in-home\t~\t0\t1970-01-01 00:00\thostT' "$(rows in-home)"
assert_eq "path: home prefix is ~/" $'in-sub\t~/sub\t0\t1970-01-01 00:00\thostT' "$(rows in-sub)"
assert_eq "path: sibling prefix untouched" $'in-sibling\t'"$S-x"$'\t0\t1970-01-01 00:00\thostT' "$(rows in-sibling)"
SH=$T/streamhome; mkdir -p "$SH"
printf '{"t":2,"d":"/x","e":0,"c":"own-old"}\n{"t":4,"d":"/x","e":0,"c":"own-new"}\n' > "$SH/.shtory.own.jsonl"
printf '{"t":1,"d":"/x","e":0,"c":"other-old"}\n{"t":3,"d":"/x","e":0,"c":"other-new"}\n' > "$SH/.shtory.other.jsonl"
assert_eq "fzf stream: newest file first, newest first" $'own-new\nown-old\nother-new\nother-old' \
  "$(HOME=$SH shtory_fn 'cwd= efilter= limit=0 files=("'$SH'/.shtory.other.jsonl" "'$SH'/.shtory.own.jsonl"); fzf_rows' | cut -f1)"
assert_eq "fzf stream: single file, newest first" $'other-new\nother-old' \
  "$(HOME=$SH shtory_fn 'cwd= efilter= limit=0 files=("'$SH'/.shtory.other.jsonl"); fzf_rows' | cut -f1)"
