#!/usr/bin/env bash
# No TTY required. Runs the test sections in test/*.sh in order (sourced,
# so shared state like $T and $S carries between sections).
set -uo pipefail
source ./test/common.sh
source ./test/lint.sh
source ./test/install.sh
source ./test/tui.sh
source ./test/search.sh
source ./test/hostname.sh
source ./test/stats.sh
source ./test/import.sh
source ./test/sync.sh
source ./test/pty.sh

echo "# result"
if [[ $FAILS -eq 0 ]]; then
  echo "all tests passed"
else
  echo "$FAILS test(s) failed"
  exit 1
fi
