#!/usr/bin/env bash
# test: tui-shtory filter (run via ./test.bash; standalone: bash test/tui.sh)
source ./test/common.sh

echo "# tui filter"
assert_eq "word-substring filter" "git status" \
  "$(tui_fn "tui_filter 'git s' 'git status' 'git diff' 'ls'")"
assert_eq "empty filter passes all" $'a\nb' \
  "$(tui_fn "tui_filter '' 'a' 'b'")"
assert_eq "case-insensitive" "git status" \
  "$(tui_fn "tui_filter 'GIT S' 'git status'")"
assert_eq "words must be in order" "" \
  "$(tui_fn "tui_filter 'status git' 'git status'")"
