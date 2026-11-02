#!/usr/bin/env bats
# npm globals (opt-in): only under a Node that belongs to the user (nvm),
# never a distro or root-owned prefix.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  bindir="$BATS_TEST_TMPDIR/bin"; state="$BATS_TEST_TMPDIR/state"
  mkdir -p "$bindir" "$state"
  export SU_PROBE_TIMEOUT=5
  export SU_TIMEOUT=20
  SU_USER_HOME="$BATS_TEST_TMPDIR/home"
  nodedir="$SU_USER_HOME/.nvm/versions/node/v22.11.0"
  mkdir -p "$nodedir/bin"
  export PATH="$nodedir/bin:$bindir:$PATH"
  SU_PKG=apt
  SU_DRY_RUN=0
  SU_CFG[NPM_GLOBALS]=1
  STEP_RESULT=""; STEP_NOTE=""
  LOG="$BATS_TEST_TMPDIR/calls.log"; : > "$LOG"
  echo "$nodedir" > "$state/prefix"
  printf '%s/lib/node_modules/npm:npm@10.9.0:npm@10.9.2:npm\n%s/lib/node_modules/corepack:corepack@0.29.0:corepack@0.30.0:corepack\n' "$nodedir" "$nodedir" > "$state/outdated"
  npm_body="
echo \"npm \$* notifier=\${NO_UPDATE_NOTIFIER:-unset}\" >> '$LOG'
case \"\$*\" in
  'prefix -g') cat '$state/prefix' ;;
  'outdated -g --parseable') cat '$state/outdated'; [ -s '$state/outdated' ] && exit 1 ;;
  'update -g') [ -e '$state/fail' ] && exit 1 ;;
esac
exit 0"
  make_fake_bin "$nodedir/bin" npm "$npm_body"
  tools_discover
}

@test "an npm under the user's home is detected; a system npm is not" {
  assert_equal "$nodedir/bin/npm" "${SU_TOOL_BIN[npm-globals]}"
  make_fake_bin "$BATS_TEST_TMPDIR/sys/bin" npm "$npm_body"
  PATH="$BATS_TEST_TMPDIR/sys/bin:$PATH" tools_discover
  [ -z "${SU_TOOL_BIN[npm-globals]-}" ]
}

@test "off by default" {
  SU_CFG[NPM_GLOBALS]=0
  tool_npm_globals_update
  assert_equal skipped "$STEP_RESULT"
  assert_equal "off by default; enable with --npm-globals or NPM_GLOBALS=1" "$STEP_NOTE"
  ! grep -q . "$LOG"
}

@test "a global prefix outside the home is never written to" {
  echo /usr/local > "$state/prefix"
  tool_npm_globals_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "global prefix '/usr/local' is not inside $SU_USER_HOME; refusing to write there"
  ! grep -q '^npm update' "$LOG"
}

@test "npm update -g with the notifier off" {
  tool_npm_globals_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "2 global package(s) updated"
  grep -q '^npm update -g notifier=1' "$LOG"
}

@test "nothing outdated is ok" {
  : > "$state/outdated"
  tool_npm_globals_update
  assert_equal ok "$STEP_RESULT"
  ! grep -q '^npm update' "$LOG"
}

@test "dry run counts and changes nothing" {
  SU_DRY_RUN=1
  tool_npm_globals_update
  assert_equal dry-run "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "2 outdated global package(s); would run npm update -g"
  ! grep -q '^npm update' "$LOG"
}

@test "a failed npm update -g is a failure" {
  touch "$state/fail"
  tool_npm_globals_update
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "npm update -g failed"
}
