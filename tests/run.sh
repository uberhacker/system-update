#!/usr/bin/env bash
# tests/run.sh - run the unit tests with bats-core.
#
# Uses `bats` from PATH, or $BATS, or clones bats-core into tests/vendor
# (git-ignored) on first use. Extra arguments are passed to bats, e.g.
#   tests/run.sh --filter nvm
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bats_bin="${BATS:-}"
if [ -z "$bats_bin" ]; then
  if command -v bats >/dev/null 2>&1; then
    bats_bin=bats
  else
    vendor="$here/vendor/bats-core"
    if [ ! -x "$vendor/bin/bats" ]; then
      echo "fetching bats-core into $vendor" >&2
      git clone --quiet --depth 1 https://github.com/bats-core/bats-core.git "$vendor"
    fi
    bats_bin="$vendor/bin/bats"
  fi
fi
exec "$bats_bin" "$here/unit" "$@"
