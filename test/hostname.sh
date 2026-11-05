#!/usr/bin/env bash
# test: hostname (run via ./test.bash; uses $S from test/search.sh)
source ./test/common.sh

echo "# hostname"
assert_eq "prints effective host" "${SHTORY_HOSTNAME:-$HOSTNAME}" "$(HOME=${S:-$T} "$B" hostname)"
HOME=${S:-$T} "$B" hostname 'bad name!' >/dev/null 2>&1
assert_rc "invalid name rc 2" 2 $?
HN=$T/hn_home; mkdir -p "$HN"
HOME=$HN "$B" hostname my.host >/dev/null
assert_eq "env file written" "SHTORY_HOSTNAME=my.host" "$(cat "$HN/.shtory/shtory.env")"
assert_eq "hostname prints env file value" "my.host" "$(HOME=$HN "$B" hostname)"
assert_eq "env var beats env file" "envhost" "$(HOME=$HN SHTORY_HOSTNAME=envhost "$B" hostname)"
