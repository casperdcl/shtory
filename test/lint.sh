#!/usr/bin/env bash
# test: syntax & lint (run via ./test.bash; standalone: bash test/lint.sh)
source ./test/common.sh

echo "# syntax & lint"
for f in "$B" "$TUI"; do
  if bash -n "$f"; then ok "bash -n ${f##*/}"; else bad "bash -n ${f##*/}"; fi
done
if command -v shellcheck >/dev/null 2>&1; then
  for f in "$B" "$TUI"; do
    if shellcheck -x "$f"; then ok "shellcheck ${f##*/}"; else bad "shellcheck ${f##*/}"; fi
  done
else
  echo "SKIP - shellcheck not installed"
fi
