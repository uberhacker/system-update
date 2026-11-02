#!/usr/bin/env bats
# mise: self-update (not for distro/brew installs), plugin updates, and
# `mise upgrade` only with RUNTIMES=1 (never --bump).

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
  SU_CFG[RUNTIMES]=0
  STEP_RESULT=""; STEP_NOTE=""
  LOG="$BATS_TEST_TMPDIR/calls.log"; : > "$LOG"
  echo 2024.11.4 > "$state/version"
  printf 'node\npython\n' > "$state/plugins"
  echo 'node 20.17.0 -> 20.18.1' > "$state/updry"
  make_fake_bin "$bindir" mise "
echo \"mise \$* yes=\${MISE_YES:-unset}\" >> '$LOG'
case \"\$*\" in
  --version) echo \"\$(cat '$state/version') linux-x64 (2024-11-20)\" ;;
  'self-update --yes') [ -e '$state/self_na' ] && { echo 'mise self-update is not available for this installation'; exit 1; }
                       [ -e '$state/self_fail' ] && exit 1; echo 2024.11.5 > '$state/version' ;;
  'plugins ls') cat '$state/plugins' ;;
  'plugins update') [ -e '$state/plugins_fail' ] && exit 1 ;;
  'upgrade --dry-run') cat '$state/updry' ;;
  'upgrade --yes') echo 'mise node@20.18.1 installed' ;;
esac
exit 0"
  tools_discover
}

@test "mise on PATH is detected" {
  assert_equal "$bindir/mise" "${SU_TOOL_BIN[mise]}"
}

@test "self-update and plugins; runtimes off by default" {
  tool_mise_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "mise 2024.11.4 -> 2024.11.5"
  assert_contains "$STEP_NOTE" "2 plugin(s) updated"
  assert_contains "$STEP_NOTE" "runtimes: off; enable with --runtimes or RUNTIMES=1"
  grep -q '^mise self-update --yes yes=1' "$LOG"
  grep -q '^mise plugins update' "$LOG"
  ! grep -q '^mise upgrade' "$LOG"
}

@test "RUNTIMES=1 runs mise upgrade --yes, never --bump" {
  SU_CFG[RUNTIMES]=1
  tool_mise_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "runtimes upgraded within their specs"
  grep -q '^mise upgrade --yes' "$LOG"
  ! grep -q -- '--bump' "$LOG"
}

@test "dry run with runtimes reads only" {
  SU_CFG[RUNTIMES]=1
  SU_DRY_RUN=1
  tool_mise_update
  assert_equal dry-run "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "would run mise self-update --yes"
  assert_contains "$STEP_NOTE" "would run mise plugins update (2 plugin(s))"
  assert_contains "$STEP_NOTE" "runtimes: would upgrade 1 tool version(s)"
  ! grep -qE '^mise (self-update|plugins update|upgrade --yes)' "$LOG"
  assert_equal 2024.11.4 "$(cat "$state/version")"
}

@test "a distro-packaged mise skips its self-update but still updates plugins" {
  make_fake_bin "$bindir" dpkg 'echo "mise: $2"'
  tool_mise_update
  assert_equal ok "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "mise itself comes from apt package 'mise'"
  assert_contains "$STEP_NOTE" "2 plugin(s) updated"
  ! grep -q '^mise self-update' "$LOG"
  grep -q '^mise plugins update' "$LOG"
}

@test "self-update not available for this install is a note, not a failure" {
  touch "$state/self_na"
  tool_mise_update
  assert_equal ok "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "self-update is not available for this install of mise"
}

@test "a failed plugin update is a failure" {
  touch "$state/plugins_fail"
  tool_mise_update
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "mise plugins update failed"
}

@test "something else called mise is skipped" {
  make_fake_bin "$bindir" mise 'echo "mise en place v1"'
  tool_mise_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "does not look like mise"
}
