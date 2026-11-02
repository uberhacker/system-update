#!/usr/bin/env bats
# nvm logic with a stubbed nvm.sh: keep the current LTS, migrate packages,
# never remove the previous default before the new one works, prune only on
# request, no iojs / Node 4/6/8.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  export NVM_DIR="$BATS_TEST_TMPDIR/nvm"
  export NVM_STUB_LOG="$BATS_TEST_TMPDIR/nvm.log"
  mkdir -p "$NVM_DIR/state"
  cp "$STUBS/nvm.sh" "$NVM_DIR/nvm.sh"
  echo v20.11.0 > "$NVM_DIR/state/installed"
  echo v20.11.0 > "$NVM_DIR/state/default"
  echo v20.11.0 > "$NVM_DIR/state/current"
  echo v22.11.0 > "$NVM_DIR/state/remote_lts"
  : > "$NVM_STUB_LOG"
  SU_DRY_RUN=0
  SU_CFG[PRUNE_NODE]=0
  STEP_RESULT=""; STEP_NOTE=""
  tools_discover
}

@test "nvm is detected through NVM_DIR" {
  assert_equal "$NVM_DIR/nvm.sh" "${SU_TOOL_BIN[nvm]}"
}

@test "installs the LTS, migrates packages and points default at lts/*" {
  tool_nvm_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "v20.11.0 -> v22.11.0"
  grep -qx 'install v22.11.0 --reinstall-packages-from=v20.11.0' "$NVM_STUB_LOG"
  grep -qx 'alias default lts/\*' "$NVM_STUB_LOG"
  assert_equal 'lts/*' "$(cat "$NVM_DIR/state/default")"
  grep -qx v22.11.0 "$NVM_DIR/state/installed"
}

@test "the previous version is kept without --prune-node" {
  tool_nvm_update
  grep -qx v20.11.0 "$NVM_DIR/state/installed"
  ! grep -q '^uninstall' "$NVM_STUB_LOG"
}

@test "--prune-node removes other versions but never the new default" {
  SU_CFG[PRUNE_NODE]=1
  echo v18.20.0 >> "$NVM_DIR/state/installed"
  tool_nvm_update
  assert_equal updated "$STEP_RESULT"
  grep -qx 'uninstall v20.11.0' "$NVM_STUB_LOG"
  grep -qx 'uninstall v18.20.0' "$NVM_STUB_LOG"
  ! grep -qx 'uninstall v22.11.0' "$NVM_STUB_LOG"
  assert_equal v22.11.0 "$(cat "$NVM_DIR/state/installed")"
  assert_contains "$STEP_NOTE" "removed 2 other version(s)"
}

@test "already on the current LTS is ok and installs nothing" {
  echo v22.11.0 > "$NVM_DIR/state/installed"
  echo v22.11.0 > "$NVM_DIR/state/default"
  echo v22.11.0 > "$NVM_DIR/state/current"
  tool_nvm_update
  assert_equal ok "$STEP_RESULT"
  ! grep -q '^install' "$NVM_STUB_LOG"
}

@test "a failed install leaves the old default untouched" {
  touch "$NVM_DIR/state/fail_install"
  tool_nvm_update
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "previous default left in place"
  assert_equal v20.11.0 "$(cat "$NVM_DIR/state/default")"
  ! grep -q '^alias' "$NVM_STUB_LOG"
  ! grep -q '^uninstall' "$NVM_STUB_LOG"
}

@test "dry run only reads" {
  SU_DRY_RUN=1
  tool_nvm_update
  assert_equal dry-run "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "would install v22.11.0"
  ! grep -qE '^(install|alias|uninstall)' "$NVM_STUB_LOG"
  assert_equal v20.11.0 "$(cat "$NVM_DIR/state/installed")"
}

@test "never installs iojs or Node 4/6/8" {
  tool_nvm_update
  ! grep -qiE 'iojs|argon|boron|carbon|install v[468]\.' "$NVM_STUB_LOG"
}

@test "with no default alias the active version is migrated from" {
  rm -f "$NVM_DIR/state/default"
  tool_nvm_update
  grep -qx 'install v22.11.0 --reinstall-packages-from=v20.11.0' "$NVM_STUB_LOG"
  assert_equal updated "$STEP_RESULT"
}

@test "with nothing installed the LTS is installed without migration" {
  : > "$NVM_DIR/state/installed"
  rm -f "$NVM_DIR/state/default"
  echo none > "$NVM_DIR/state/current"
  tool_nvm_update
  grep -qx 'install v22.11.0' "$NVM_STUB_LOG"
  assert_equal updated "$STEP_RESULT"
}

@test "unreachable node dist is a failure, not an update" {
  : > "$NVM_DIR/state/remote_lts"
  tool_nvm_update
  assert_equal failed "$STEP_RESULT"
  ! grep -qE '^(install|alias|uninstall)' "$NVM_STUB_LOG"
}
