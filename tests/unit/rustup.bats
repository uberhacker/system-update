#!/usr/bin/env bats
# rustup: self update + toolchain update, dry run via rustup check,
# distro-packaged rustup keeps updating toolchains but not itself.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  bindir="$BATS_TEST_TMPDIR/bin"; state="$BATS_TEST_TMPDIR/state"
  mkdir -p "$bindir" "$state"
  export PATH="$bindir:$PATH"
  export SU_PROBE_TIMEOUT=5
  export SU_TIMEOUT=20
  SU_USER_HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$SU_USER_HOME"
  SU_PKG=apt
  SU_DRY_RUN=0
  STEP_RESULT=""; STEP_NOTE=""
  LOG="$BATS_TEST_TMPDIR/calls.log"; : > "$LOG"
  echo 1.27.1 > "$state/version"
  printf 'stable-x86_64-unknown-linux-gnu - Update available : 1.81.0 (eeb90cda1 2024-09-04) -> 1.82.0 (f6e511eec 2024-10-15)\nnightly-x86_64-unknown-linux-gnu - Up to date : 1.84.0-nightly (a0d98ff0e 2024-10-20)\n' > "$state/check"
  printf '  stable-x86_64-unknown-linux-gnu updated - rustc 1.82.0 (f6e511eec 2024-10-15) (from rustc 1.81.0 (eeb90cda1 2024-09-04))\n  nightly-x86_64-unknown-linux-gnu unchanged - rustc 1.84.0-nightly (a0d98ff0e 2024-10-20)\n\ninfo: cleaning up downloads & tmp directories\n' > "$state/update"
  make_fake_bin "$bindir" rustup "
echo \"rustup \$*\" >> '$LOG'
case \"\$1\" in
  --version) echo \"rustup \$(cat '$state/version') (2024-10-01)\" ;;
  check) cat '$state/check' ;;
  self) [ -e '$state/self_fail' ] && { echo 'error: download failed'; exit 1; }
        if [ -e '$state/self_current' ]; then echo '  rustup unchanged - 1.27.1'; else echo '  rustup updated - 1.27.2 (from 1.27.1)'; echo 1.27.2 > '$state/version'; fi ;;
  update) [ -e '$state/update_fail' ] && { echo 'error: could not download nightly manifest'; exit 1; }
          cat '$state/update' ;;
esac"
  tools_discover
}

@test "rustup on PATH is detected" {
  assert_equal "$bindir/rustup" "${SU_TOOL_BIN[rustup]}"
}

@test "update: self update, then rustup update --no-self-update; counts toolchains" {
  tool_rustup_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "1 toolchain(s) updated, 1 unchanged"
  assert_contains "$STEP_NOTE" "rustup self-updated"
  assert_contains "$STEP_NOTE" "rustup 1.27.1 -> 1.27.2"
  grep -qx 'rustup self update' "$LOG"
  grep -qx 'rustup update --no-self-update' "$LOG"
}

@test "everything current is ok" {
  touch "$state/self_current"
  printf '  stable-x86_64-unknown-linux-gnu unchanged - rustc 1.82.0\n  nightly-x86_64-unknown-linux-gnu unchanged - rustc 1.84.0-nightly\n' > "$state/update"
  tool_rustup_update
  assert_equal ok "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "2 toolchain(s) up to date"
}

@test "dry run uses rustup check and changes nothing" {
  SU_DRY_RUN=1
  tool_rustup_update
  assert_equal dry-run "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "1 update(s) available; would run rustup update"
  assert_contains "$STEP_NOTE" "would run rustup self update"
  grep -qx 'rustup check' "$LOG"
  ! grep -qE '^rustup (self|update)' "$LOG"
  assert_equal 1.27.1 "$(cat "$state/version")"
}

@test "a distro-packaged rustup still updates toolchains but never itself" {
  make_fake_bin "$bindir" dpkg 'echo "rustup: $2"'
  tool_rustup_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "rustup itself comes from apt package 'rustup'"
  assert_contains "$STEP_NOTE" "1 toolchain(s) updated"
  ! grep -q '^rustup self' "$LOG"
  grep -qx 'rustup update --no-self-update' "$LOG"
}

@test "a distro-packaged rustup in a dry run does not offer a self update" {
  make_fake_bin "$bindir" dpkg 'echo "rustup: $2"'
  SU_DRY_RUN=1
  tool_rustup_update
  assert_equal dry-run "$STEP_RESULT"
  assert_not_contains "$STEP_NOTE" "would run rustup self update"
}

@test "a failed toolchain update is a failure" {
  touch "$state/update_fail"
  tool_rustup_update
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "rustup update failed"
}

@test "a failed self update is noted; toolchains are still updated" {
  touch "$state/self_fail"
  tool_rustup_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "rustup self update failed"
  grep -qx 'rustup update --no-self-update' "$LOG"
}

@test "something else called rustup is skipped" {
  make_fake_bin "$bindir" rustup 'echo "usage: rustup-thing"; exit 1'
  tool_rustup_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "does not look like rustup"
}
