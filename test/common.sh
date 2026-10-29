#!/usr/bin/env bash
# shared test harness for test/*.sh (sourced by test.bash and each test file)
# run from the repo root (B/TUI resolve via $PWD)
# section order matters: hostname/stats use $S created by test/search.sh
if [[ -n ${SHTORY_TEST_COMMON-} ]]; then
  return 0
fi
SHTORY_TEST_COMMON=1
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
shtory_fn() { bash -c "source \"$B\" >/dev/null 2>&1; $*"; }
tui_fn() { bash -c "source \"$TUI\" >/dev/null 2>&1; $*"; }
