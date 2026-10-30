#!/usr/bin/env bash
# Shared helpers for the bats unit tests.
# shellcheck disable=SC2034  # variables here are used by the .bats files

REPO_ROOT=$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)
FIXTURES="$REPO_ROOT/tests/fixtures"
STUBS="$REPO_ROOT/tests/stubs"

# load_su: source every module into the test shell without running main.
# bats owns the EXIT trap, so util.sh must not install its own; temp files
# are removed in teardown instead.
load_su() {
  export SU_ROOT="$REPO_ROOT"
  export SU_COLOR="${SU_COLOR:-never}"
  export SU_SKIP_EXIT_TRAP=1
  set +u
  local f
  for f in log util config args os json github runner pkg tools selfupdate; do
    # shellcheck disable=SC1090
    source "$REPO_ROOT/lib/core/$f.sh"
  done
  for f in "$REPO_ROOT"/lib/pkg/*.sh; do
    # shellcheck disable=SC1090
    source "$f"
  done
  tools_load
  user_init
  config_load
  SU_TIMEOUT=$(cfg TIMEOUT)
  SU_PROBE_TIMEOUT=$(cfg PROBE_TIMEOUT)
  log_init
}

# Remove temp files created through tmp_dir/tmp_file during a test.
teardown() {
  declare -F tmp_cleanup >/dev/null && tmp_cleanup
  return 0
}

# fixture NAME: path to tests/fixtures/NAME
fixture() { printf '%s/%s\n' "$FIXTURES" "$1"; }

# make_fake_bin DIR NAME SCRIPT_BODY: executable script on a private PATH dir.
make_fake_bin() {
  local dir="$1" name="$2" body="$3"
  mkdir -p "$dir"
  printf '#!/usr/bin/env bash\n%s\n' "$body" > "$dir/$name"
  chmod +x "$dir/$name"
}

# assert_contains HAYSTACK NEEDLE
assert_contains() {
  if [[ "$1" != *"$2"* ]]; then
    echo "expected to find: $2"
    echo "in: $1"
    return 1
  fi
}

# assert_not_contains HAYSTACK NEEDLE
assert_not_contains() {
  if [[ "$1" == *"$2"* ]]; then
    echo "did not expect to find: $2"
    echo "in: $1"
    return 1
  fi
}

# assert_equal EXPECTED ACTUAL
assert_equal() {
  if [ "$1" != "$2" ]; then
    echo "expected: $1"
    echo "actual:   $2"
    return 1
  fi
}
