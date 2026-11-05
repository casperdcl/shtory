#!/usr/bin/env bash
# test: import (install --import) (run via ./test.bash; standalone: bash test/import.sh)
source ./test/common.sh

echo "# import (install --import)"
I=$T/importhome; F=$I/.shtory/imphost.jsonl; mkdir -p "$I/.shtory"
BS=$(command -v bash) # import defaults depend on $SHELL; pin bash for the .bash_history cases
printf 'ls\ncd /tmp\nls\ngit status\n\n' > "$I/.bash_history"
SHELL=$BS HOME=$I SHTORY_HOSTNAME=imphost "$B" install --import >/dev/null
assert_eq "install --import: block written" "1" "$(grep -cF '>>> shtory >>>' "$I/.bashrc")"
assert_eq "install --import: unique, original order, t=0" \
  $'{"t":0,"d":"","e":0,"c":"ls"}\n{"t":0,"d":"","e":0,"c":"cd /tmp"}\n{"t":0,"d":"","e":0,"c":"git status"}' \
  "$(cat "$F")"
[[ $(stat -c %a "$F") == 600 ]] && ok "install --import: file mode 600" || bad "install --import: file mode 600 ($(stat -c %a "$F"))"
assert_eq "imported searchable" "git status" \
  "$(HOME=$I SHTORY_HOSTNAME=imphost "$B" search -h imphost git)"
# idempotent: re-running does not duplicate already-present commands
F_before=$(cat "$F")
SHELL=$BS HOME=$I SHTORY_HOSTNAME=imphost "$B" install --import >/dev/null
assert_eq "install --import: idempotent (no dup on re-run)" "$F_before" "$(cat "$F")"
# dedup against existing commands of any t: a normally-logged (t>0) command
# blocks its import, and the existing t>0 line is untouched
printf '%s\n' '{"t":999,"d":"/a","e":0,"c":"ls"}' > "$F"
printf 'ls\n' > "$I/.bash_history"
SHELL=$BS HOME=$I SHTORY_HOSTNAME=imphost "$B" install --import >/dev/null
assert_eq "dedup: existing (t>0) entry blocks import, kept untouched" \
  $'{"t":999,"d":"/a","e":0,"c":"ls"}' \
  "$(cat "$F")"
# stale import: a t:0 line whose command is now logged (t>0) is removed
printf '%s\n' '{"t":0,"d":"","e":0,"c":"ls"}' '{"t":42,"d":"/b","e":0,"c":"ls"}' > "$F"
printf 'other\n' > "$I/.bash_history"
SHELL=$BS HOME=$I SHTORY_HOSTNAME=imphost "$B" install --import >/dev/null
assert_eq "stale t:0 removed when a t>0 entry exists" \
  $'{"t":0,"d":"","e":0,"c":"other"}\n{"t":42,"d":"/b","e":0,"c":"ls"}' \
  "$(cat "$F")"
printf '%s\n' '{"t":500,"d":"/a","e":0,"c":"existing"}' > "$F"
printf 'echo new\n' > "$I/.bash_history"
SHELL=$BS HOME=$I SHTORY_HOSTNAME=imphost "$B" install --import >/dev/null
assert_eq "install --import: prepends before existing" \
  $'{"t":0,"d":"","e":0,"c":"echo new"}\n{"t":500,"d":"/a","e":0,"c":"existing"}' \
  "$(cat "$F")"
: > "$F"
printf 'echo "a b" && ls -la\n' > "$I/.bash_history"
SHELL=$BS HOME=$I SHTORY_HOSTNAME=imphost "$B" install --import >/dev/null
assert_eq "install --import: quoting escaped" 'echo "a b" && ls -la' "$(jq -r '.c' "$F")"
# comment lines (starting with #) are skipped, incl. HISTTIMEFORMAT #epoch timestamps
: > "$F"
printf 'ls\n#1793199155\ngit status\n#my note\n' > "$I/.bash_history"
SHELL=$BS HOME=$I SHTORY_HOSTNAME=imphost "$B" install --import >/dev/null
assert_eq "comment (#) lines skipped" \
  $'{"t":0,"d":"","e":0,"c":"ls"}\n{"t":0,"d":"","e":0,"c":"git status"}' \
  "$(cat "$F")"
I2=$T/importempty; mkdir -p "$I2"
printf 'should-not-import\n' > "$I2/.bash_history"
HOME=$I2 SHTORY_HOSTNAME=imphost "$B" install >/dev/null
[[ ! -f $I2/.shtory/imphost.jsonl ]] && ok "plain install: no import" || bad "plain install: no import"
I3=$T/importempty3; mkdir -p "$I3"
SHELL=$BS HOME=$I3 SHTORY_HOSTNAME=imphost "$B" install --import >/dev/null 2>&1
assert_rc "install --import: no .bash_history is a no-op (rc 0)" 0 $?
grep -qF '>>> shtory >>>' "$I3/.bashrc" && ok "no-op: block still written" || bad "no-op: block still written"
# import strips control chars, survives binary bytes + mixed case (LC_ALL=C + grep -a)
I4=$T/importbinary; mkdir -p "$I4"
printf 'A cmd\na cmd\n#123\necho \0nul\nz cmd\n' > "$I4/.bash_history"
SHELL=$BS HOME=$I4 SHTORY_HOSTNAME=imphost "$B" install --import >/dev/null 2>&1
assert_rc "import: binary+mixed-case history does not fail" 0 $?
assert_eq "import: binary+mixed-case imports 4 commands" 4 "$(wc -l < "$I4/.shtory/imphost.jsonl")"
assert_eq "import: control chars stripped" "echo nul" "$(jq -r 'select(.c | startswith("echo")) | .c' "$I4/.shtory/imphost.jsonl")"
# zsh: $SHELL=zsh defaults to ~/.zsh_history; extended_history ": <ts>:<s>;" prefixes stripped
I5=$T/importzsh; mkdir -p "$I5"
printf 'echo z\n: 1793199155:0;echo ext\ngit log\n' > "$I5/.zsh_history"
SHELL=/usr/bin/zsh HOME=$I5 SHTORY_HOSTNAME=imphost "$B" install --import >/dev/null 2>&1
assert_eq "zsh: ~/.zsh_history imported, extended_history prefixes stripped" \
  $'{"t":0,"d":"","e":0,"c":"echo z"}\n{"t":0,"d":"","e":0,"c":"echo ext"}\n{"t":0,"d":"","e":0,"c":"git log"}' \
  "$(cat "$I5/.shtory/imphost.jsonl")"
