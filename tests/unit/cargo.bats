#!/usr/bin/env bats
# cargo: `cargo install-update -a` only when cargo-update is installed;
# otherwise a skip that names the crate. Tools installed with cargo route
# to this step from tool_standard.

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
  export CARGO_HOME="$BATS_TEST_TMPDIR/cargo"
  mkdir -p "$CARGO_HOME/bin"
  SU_PKG=apt
  SU_DRY_RUN=0
  STEP_RESULT=""; STEP_NOTE=""
  LOG="$BATS_TEST_TMPDIR/calls.log"; : > "$LOG"
  printf '[v1]\n"cargo-update 13.0.0 (registry+https://github.com/rust-lang/crates.io-index)" = ["cargo-install-update", "cargo-install-update-config"]\n"ripgrep 14.1.0 (registry+https://github.com/rust-lang/crates.io-index)" = ["rg"]\n' > "$CARGO_HOME/.crates.toml"
  printf 'Updating registry...\n\nPackage  Installed  Latest   Needs update\nripgrep  v14.1.0    v14.1.1  Yes\n\nUpdating ripgrep\n    Finished release\nUpdated 1 package.\n' > "$state/out"
  make_fake_bin "$bindir" cargo "
echo \"cargo \$*\" >> '$LOG'
case \"\$*\" in
  'install-update --list -a') printf 'Package       Installed  Latest   Needs update\\ncargo-update  v13.0.0    v13.0.0  No\\nripgrep       v14.1.0    v14.1.1  Yes\\n' ;;
  'install-update -a') [ -e '$state/fail' ] && { echo 'error: failed to compile ripgrep' >&2; exit 101; }; cat '$state/out' ;;
esac"
  tools_discover
}

with_cargo_update() { make_fake_bin "$CARGO_HOME/bin" cargo-install-update 'exit 0'; }

@test "detected only when crates were installed with cargo install" {
  assert_equal "$bindir/cargo" "${SU_TOOL_BIN[cargo]}"
  rm "$CARGO_HOME/.crates.toml"
  tools_discover
  [ -z "${SU_TOOL_BIN[cargo]-}" ]
}

@test "without cargo-update: skip that names the crate to install" {
  tool_cargo_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "2 crate(s) installed with cargo; install cargo-update (cargo install cargo-update) to update them here"
  ! grep -q . "$LOG"
}

@test "with cargo-update: install-update -a and the count of updated crates" {
  with_cargo_update
  tool_cargo_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "1 of 2 crate(s) updated"
  grep -qx 'cargo install-update -a' "$LOG"
}

@test "nothing updated is ok" {
  with_cargo_update
  printf 'Updating registry...\nPackage  Installed  Latest  Needs update\nUpdated 0 packages.\n' > "$state/out"
  tool_cargo_update
  assert_equal ok "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "2 crate(s) up to date"
}

@test "dry run lists with --list and builds nothing" {
  with_cargo_update
  SU_DRY_RUN=1
  tool_cargo_update
  assert_equal dry-run "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "1 of 2 crate(s) have updates; would run cargo install-update -a"
  grep -qx 'cargo install-update --list -a' "$LOG"
  ! grep -qx 'cargo install-update -a' "$LOG"
}

@test "a failed build is a failure" {
  with_cargo_update
  touch "$state/fail"
  tool_cargo_update
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "cargo install-update -a failed"
}

@test "a tool installed with cargo is routed to the cargo step" {
  make_fake_bin "$SU_USER_HOME/.cargo/bin" kilo 'echo 4.2.1'
  PATH="$SU_USER_HOME/.cargo/bin:$PATH" tools_discover
  assert_equal "$SU_USER_HOME/.cargo/bin/kilo" "${SU_TOOL_BIN[kilo]}"
  tool_kilo_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "installed with cargo; install cargo-update so the cargo step can update it"
  with_cargo_update
  STEP_RESULT=""; STEP_NOTE=""
  tool_kilo_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "installed with cargo; updated by the cargo step (cargo install-update -a)"
}
