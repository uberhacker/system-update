#!/usr/bin/env bats
# Download and checksum helpers: https only, sha256 verification, checksums.txt
# parsing, and a clear failure when curl is missing.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  export SU_SYSTEM_CONFIG=/nonexistent
  export SU_CONFIG_FILE="$BATS_TEST_TMPDIR/empty.conf"; : > "$SU_CONFIG_FILE"
  SU_TIMEOUT=30
  printf 'hello\n' > "$BATS_TEST_TMPDIR/hello"
  HELLO_SHA=5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03
}

@test "checksum_for reads sha256sum-style files, with * and ./ prefixes" {
  cat > "$BATS_TEST_TMPDIR/checksums.txt" <<EOF
0000000000000000000000000000000000000000000000000000000000000001  other-file
$HELLO_SHA  docker-compose-linux-x86_64
0000000000000000000000000000000000000000000000000000000000000002 *docker-compose-linux-aarch64
0000000000000000000000000000000000000000000000000000000000000003  ./codium.deb
EOF
  assert_equal "$HELLO_SHA" "$(checksum_for "$BATS_TEST_TMPDIR/checksums.txt" docker-compose-linux-x86_64)"
  assert_equal 0000000000000000000000000000000000000000000000000000000000000002 "$(checksum_for "$BATS_TEST_TMPDIR/checksums.txt" docker-compose-linux-aarch64)"
  assert_equal 0000000000000000000000000000000000000000000000000000000000000003 "$(checksum_for "$BATS_TEST_TMPDIR/checksums.txt" codium.deb)"
  assert_equal "" "$(checksum_for "$BATS_TEST_TMPDIR/checksums.txt" missing)"
}

@test "verify_sha256 accepts a matching digest, bare or with a file name" {
  verify_sha256 "$BATS_TEST_TMPDIR/hello" "$HELLO_SHA"
  verify_sha256 "$BATS_TEST_TMPDIR/hello" "${HELLO_SHA^^}"
  verify_sha256 "$BATS_TEST_TMPDIR/hello" "$HELLO_SHA  hello"
}

@test "verify_sha256 rejects a mismatch and an invalid expected value" {
  run verify_sha256 "$BATS_TEST_TMPDIR/hello" "0000000000000000000000000000000000000000000000000000000000000000"
  assert_equal 1 "$status"
  assert_contains "$output" "checksum mismatch"
  run verify_sha256 "$BATS_TEST_TMPDIR/hello" ""
  assert_equal 1 "$status"
  assert_contains "$output" "no valid sha256 checksum"
  run verify_sha256 "$BATS_TEST_TMPDIR/hello" "not-a-hash"
  assert_equal 1 "$status"
}

@test "download refuses anything that is not https" {
  run download "http://example.invalid/x" "$BATS_TEST_TMPDIR/out"
  assert_equal 1 "$status"
  assert_contains "$output" "refusing non-https download"
  run download "ftp://example.invalid/x" "$BATS_TEST_TMPDIR/out"
  assert_equal 1 "$status"
  run download "file://$BATS_TEST_TMPDIR/hello" "$BATS_TEST_TMPDIR/out"
  assert_equal 1 "$status"
  assert_contains "$output" "refusing non-https download"
  [ ! -e "$BATS_TEST_TMPDIR/out" ]
}

@test "download fetches a file:// source only with the test toggle, and the result verifies" {
  command -v curl >/dev/null || skip "curl not installed"
  SYSTEM_UPDATE_ALLOW_FILE_SOURCE=1 download "file://$BATS_TEST_TMPDIR/hello" "$BATS_TEST_TMPDIR/out"
  verify_sha256 "$BATS_TEST_TMPDIR/out" "$HELLO_SHA"
}

@test "download and the GitHub helper fail clearly when curl is missing" {
  local bin="$BATS_TEST_TMPDIR/bin" f
  mkdir -p "$bin"
  # A PATH with everything the system has except curl.
  for f in /usr/bin/* /bin/* /usr/local/bin/*; do
    [ -e "$f" ] || continue
    [ "${f##*/}" = curl ] && continue
    ln -sf "$f" "$bin/${f##*/}" 2>/dev/null || true
  done
  run env PATH="$bin" "$bin/bash" -c '
    source "'"$REPO_ROOT"'/lib/core/log.sh"; source "'"$REPO_ROOT"'/lib/core/util.sh"
    source "'"$REPO_ROOT"'/lib/core/config.sh"; source "'"$REPO_ROOT"'/lib/core/json.sh"
    source "'"$REPO_ROOT"'/lib/core/github.sh"
    SU_OUT=1; SU_COLOR=never; SU_VERBOSE=1; SU_QUIET=0; SU_TIMEOUT=30; log_init
    download https://example.invalid/x "'"$BATS_TEST_TMPDIR"'/out"; echo "download rc=$?"
    gh_init; gh_latest_tag docker/compose; echo "gh rc=$?"'
  assert_contains "$output" "curl is not installed; cannot download"
  assert_contains "$output" "download rc=1"
  assert_contains "$output" "curl is not installed; skipping"
  assert_contains "$output" "gh rc=1"
  [ ! -e "$BATS_TEST_TMPDIR/out" ]
}

@test "checksum_for finds the asset on a last line without a trailing newline" {
  local f="$BATS_TEST_TMPDIR/sums"
  printf '%s  other\n%s  wanted' "$(printf 'a%.0s' {1..64})" "$(printf 'b%.0s' {1..64})" > "$f"
  run checksum_for "$f" wanted
  assert_equal 0 "$status"
  assert_equal "$(printf 'b%.0s' {1..64})" "$output"
}
