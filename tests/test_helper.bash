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

# gh_stub_init: route GitHub lookups and downloads through tests/stubs/curl.
gh_stub_init() {
  export CURL_STUB_DIR="$BATS_TEST_TMPDIR/api"
  export CURL_STUB_LOG="$BATS_TEST_TMPDIR/curl.log"
  export PATH="$STUBS:$PATH"
  export SU_GITHUB_API="https://api.github.test"
  mkdir -p "$CURL_STUB_DIR"
  : > "$CURL_STUB_LOG"
  gh_init
}

# gh_stub_release REPO TAG BODY ASSET...: the latest release of REPO as the
# stub serves it. BODY is a JSON string body (\n escapes allowed).
gh_stub_release() {
  local repo="$1" tag="$2" body="$3"; shift 3
  local assets="" a
  for a in "$@"; do
    assets+="${assets:+,}{\"name\":\"$a\",\"browser_download_url\":\"https://github.com/$repo/releases/download/$tag/$a\"}"
  done
  mkdir -p "$CURL_STUB_DIR/repos/$repo/releases"
  printf '{"tag_name":"%s","name":"%s","body":"%s","assets":[%s]}\n' "$tag" "$tag" "$body" "$assets" \
    > "$CURL_STUB_DIR/repos/$repo/releases/latest.json"
}

# gh_stub_asset REPO TAG NAME SRC: serve SRC as a release asset download.
gh_stub_asset() {
  mkdir -p "$CURL_STUB_DIR/$1/releases/download/$2"
  cp "$4" "$CURL_STUB_DIR/$1/releases/download/$2/$3.json"
}

# make_git_pair DIR: a checkout at DIR whose origin is the bare repo DIR.git,
# with a working source clone at DIR.src to push new commits from
# (git_advance DIR). Used for the frameworks that update themselves with
# git (oh-my-zsh, oh-my-bash, TPM plugins, asdf plugins).
make_git_pair() {
  local dir="$1" o
  o="$BATS_TEST_TMPDIR/origins/$(basename "$1")"
  mkdir -p "$o"
  git init -q "$o/src"
  git -C "$o/src" symbolic-ref HEAD refs/heads/master
  git -C "$o/src" -c user.email=t@test -c user.name=t commit -q --allow-empty -m one
  git clone -q --bare "$o/src" "$o/bare"
  git clone -q "$o/bare" "$dir" 2>/dev/null
}

# git_advance DIR: one more commit on DIR's origin.
git_advance() {
  local o
  o="$BATS_TEST_TMPDIR/origins/$(basename "$1")"
  git -C "$o/src" -c user.email=t@test -c user.name=t commit -q --allow-empty -m more
  git -C "$o/src" push -q "$o/bare" master
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
