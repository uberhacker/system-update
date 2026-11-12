#!/usr/bin/env bats
# After a run: a newer system-update release is announced, and applied with
# SELF_UPDATE_AUTO=1 (Ed's issue: "self updatable executable").

load ../test_helper

setup() {
  SU_OUT=1
  export SU_SYSTEM_CONFIG=/nonexistent
  export SU_CONFIG_FILE="$BATS_TEST_TMPDIR/empty.conf"; : > "$SU_CONFIG_FILE"
  load_su
  gh_stub_init
  SU_DRY_RUN=0
  SU_BUNDLED=0
  calls="$BATS_TEST_TMPDIR/selfupdate.calls"
  : > "$calls"
  # The real self-update is tested elsewhere; here only whether it is called.
  selfupdate_main() { echo called >> "$calls"; }
}

have() { echo "$1" > "$BATS_TEST_TMPDIR/VERSION"; SU_ROOT="$BATS_TEST_TMPDIR"; }

@test "a newer release is announced with the command to get it" {
  have 2.0.1
  gh_stub_release uberhacker/system-update v2.1.0 ""
  run selfupdate_release_check
  assert_equal 0 "$status"
  assert_contains "$output" "system-update 2.1.0 is available (this is 2.0.1): run system-update --self-update"
  [ ! -s "$calls" ]
}

@test "the same or an older release says nothing" {
  have 2.1.0
  gh_stub_release uberhacker/system-update v2.1.0 ""
  run selfupdate_release_check
  assert_equal "" "$output"
  have 2.2.0
  run selfupdate_release_check
  assert_equal "" "$output"
}

@test "no release published (or offline): nothing, and the run is not failed" {
  have 2.0.1
  run selfupdate_release_check
  assert_equal 0 "$status"
  assert_equal "" "$output"
}

@test "SELF_UPDATE_AUTO=1 applies the newer release" {
  have 2.0.1
  gh_stub_release uberhacker/system-update v2.1.0 ""
  config_set SELF_UPDATE_AUTO 1 test
  selfupdate_release_check
  assert_equal called "$(cat "$calls")"
}

@test "SELF_UPDATE_AUTO=1 does nothing in a dry run beyond the notice" {
  have 2.0.1
  gh_stub_release uberhacker/system-update v2.1.0 ""
  config_set SELF_UPDATE_AUTO 1 test
  SU_DRY_RUN=1
  run selfupdate_release_check
  assert_contains "$output" "2.1.0 is available"
  [ ! -s "$calls" ]
}

@test "SELF_UPDATE_CHECK=0 asks nothing" {
  have 2.0.1
  gh_stub_release uberhacker/system-update v2.1.0 ""
  config_set SELF_UPDATE_CHECK 0 test
  run selfupdate_release_check
  assert_equal "" "$output"
  [ ! -s "$CURL_STUB_LOG" ]
}

@test "a fork's releases are followed when SELF_UPDATE_REPO names it" {
  have 2.0.1
  gh_stub_release someone/system-update v3.0.0 ""
  config_set SELF_UPDATE_REPO https://github.com/someone/system-update.git test
  run selfupdate_release_check
  assert_contains "$output" "3.0.0 is available"
}

@test "a single-file build compares its own built-in version" {
  SU_BUNDLED=1 SU_BUNDLE_VERSION=2.0.1
  gh_stub_release uberhacker/system-update v2.1.0 ""
  run selfupdate_release_check
  assert_contains "$output" "2.1.0 is available (this is 2.0.1)"
}
