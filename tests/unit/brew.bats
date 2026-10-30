#!/usr/bin/env bats
# Homebrew on Linux: brew update + brew upgrade as the user, never as root.

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
  printf 'git\nnode\n' > "$state/outdated"
  brew_body="
echo \"brew \$* auto=\${HOMEBREW_NO_AUTO_UPDATE:-unset} cleanup=\${HOMEBREW_NO_INSTALL_CLEANUP:-unset} user=\$(id -un)\" >> '$LOG'
case \"\$1\" in
  update) [ -e '$state/update_fail' ] && { echo 'Error: Fetching /home/linuxbrew/.linuxbrew/Homebrew failed!' >&2; exit 1; }; echo 'Already up-to-date.' ;;
  outdated) cat '$state/outdated' ;;
  upgrade) [ -e '$state/upgrade_fail' ] && exit 1; : > '$state/outdated' ;;
  autoremove) ;;
esac"
  make_fake_bin "$bindir" brew "$brew_body"
  # The suite may run as root; the step is about the invoking user.
  SU_USER=brewer; SU_CUR_USER=brewer
  make_fake_bin "$bindir" stat 'echo brewer'
  tools_discover
}

@test "brew on PATH is detected; so is ~/.linuxbrew without PATH" {
  assert_equal "$bindir/brew" "${SU_TOOL_BIN[brew]}"
  rm "$bindir/brew"
  make_fake_bin "$SU_USER_HOME/.linuxbrew/bin" brew "$brew_body"
  tools_discover
  assert_equal "$SU_USER_HOME/.linuxbrew/bin/brew" "${SU_TOOL_BIN[brew]}"
}

@test "update, outdated, upgrade, autoremove; auto-update off" {
  tool_brew_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "2 package(s) upgraded: git node"
  grep -q '^brew update auto=1' "$LOG"
  grep -q '^brew outdated --quiet' "$LOG"
  grep -q "^brew upgrade auto=1 cleanup=unset user=$(id -un)" "$LOG"   # runs directly: we are the user
  grep -q '^brew autoremove' "$LOG"
}

@test "AUTOREMOVE=0 skips brew autoremove and keeps brew's own cleanup off" {
  SU_CFG[AUTOREMOVE]=0
  tool_brew_update
  assert_equal updated "$STEP_RESULT"
  grep -q '^brew upgrade auto=1 cleanup=1' "$LOG"
  ! grep -q '^brew autoremove' "$LOG"
}

@test "nothing outdated is ok" {
  : > "$state/outdated"
  tool_brew_update
  assert_equal ok "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "nothing outdated"
  ! grep -q '^brew upgrade' "$LOG"
}

@test "dry run refreshes the index and lists; upgrades nothing" {
  SU_DRY_RUN=1
  tool_brew_update
  assert_equal dry-run "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "2 outdated: git node; would run brew upgrade"
  grep -q '^brew update' "$LOG"
  ! grep -qE '^brew (upgrade|autoremove)' "$LOG"
}

@test "never runs as root" {
  SU_USER=root
  tool_brew_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "must not run as root"
  ! grep -q . "$LOG"
}

@test "another user's Homebrew is not touched" {
  make_fake_bin "$bindir" stat 'echo nobody'
  tool_brew_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "owned by nobody, not $SU_USER"
  ! grep -q '^brew' "$LOG"
}

@test "a failed brew update is a failure" {
  touch "$state/update_fail"
  tool_brew_update
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "brew update failed"
  ! grep -q '^brew upgrade' "$LOG"
}

@test "a failed brew upgrade is a failure" {
  touch "$state/upgrade_fail"
  tool_brew_update
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "brew upgrade failed"
}
