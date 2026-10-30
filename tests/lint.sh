#!/usr/bin/env bash
# tests/lint.sh - bash -n on every script and shellcheck -x.
#
# The entry point is checked with -x so the whole program (core and package
# manager modules are sourced statically) is analysed as one unit. Tool
# modules are discovered at runtime, so they are checked on their own with
# the two cross-file warnings (unused/unassigned variable) silenced.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

rc=0
for f in bin/system-update system-update install.sh tests/*.sh tests/test_helper.bash tests/stubs/curl tests/stubs/nvm.sh lib/core/*.sh lib/pkg/*.sh lib/tools/*.sh; do
  bash -n "$f" || { echo "bash -n failed: $f"; rc=1; }
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x bin/system-update system-update install.sh tests/*.sh tests/test_helper.bash tests/stubs/curl tests/stubs/nvm.sh || rc=1
  shellcheck -x -e SC2034,SC2154 lib/tools/*.sh || rc=1
else
  echo "shellcheck not installed; skipped" >&2
fi

[ "$rc" -eq 0 ] && echo "lint ok"
exit "$rc"
