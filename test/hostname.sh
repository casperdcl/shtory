#!/usr/bin/env bash
# test: hostname (run via ./test.bash; uses $S from test/search.sh)
source ./test/common.sh

echo "# hostname"
assert_eq "prints effective host" "${SHTORY_HOSTNAME:-$HOSTNAME}" "$(HOME=${S:-$T} "$B" hostname)"
HOME=${S:-$T} SHTORY_BASHRC=$T/h "$B" hostname 'bad name!' >/dev/null 2>&1
assert_rc "invalid name rc 2" 2 $?
