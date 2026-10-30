#!/usr/bin/env bats
# gh extensions: `gh extension upgrade --all` as the user, clean skips when
# none are installed or gh is not authenticated, dry run via --dry-run.

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
  export GH_DATA_DIR="$BATS_TEST_TMPDIR/ghdata"
  mkdir -p "$GH_DATA_DIR/extensions/gh-copilot" "$GH_DATA_DIR/extensions/gh-dash"
  SU_PKG=apt
  SU_DRY_RUN=0
  STEP_RESULT=""; STEP_NOTE=""
  LOG="$BATS_TEST_TMPDIR/calls.log"; : > "$LOG"
  printf 'gh copilot\tgithub/gh-copilot\tv1.0.5\ngh dash\tdlvhdr/gh-dash\tv4.7.0\n' > "$state/list"
  printf '[copilot]: would have upgraded from v1.0.5 to v1.0.6\n[dash]: already up to date\n' > "$state/dry"
  printf '[copilot]: upgraded from v1.0.5 to v1.0.6\n[dash]: already up to date\nSuccessfully upgraded extensions\n' > "$state/upgrade"
  make_fake_bin "$bindir" gh "
echo \"gh \$* prompt=\${GH_PROMPT_DISABLED:-unset}\" >> '$LOG'
if [ -e '$state/noauth' ]; then echo 'To get started with GitHub CLI, please run:  gh auth login' >&2; exit 4; fi
case \"\$*\" in
  'extension list') cat '$state/list' ;;
  'extension upgrade --all --dry-run') cat '$state/dry' ;;
  'extension upgrade --all') [ -e '$state/fail' ] && { echo 'X Failed upgrading extension dash: exit status 1' >&2; exit 1; }; cat '$state/upgrade' ;;
esac"
  tools_discover
}

@test "detected only when gh has an extensions directory" {
  assert_equal "$bindir/gh" "${SU_TOOL_BIN[gh-extensions]}"
  rm -rf "$GH_DATA_DIR"
  tools_discover
  [ -z "${SU_TOOL_BIN[gh-extensions]-}" ]
}

@test "upgrade --all runs with prompts disabled and counts upgrades" {
  tool_gh_extensions_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "1 of 2 extension(s) upgraded"
  grep -qx 'gh extension upgrade --all prompt=1' "$LOG"
}

@test "everything current is ok" {
  printf '[copilot]: already up to date\n[dash]: already up to date\n' > "$state/upgrade"
  tool_gh_extensions_update
  assert_equal ok "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "2 extension(s) up to date"
}

@test "dry run uses gh's own --dry-run and upgrades nothing" {
  SU_DRY_RUN=1
  tool_gh_extensions_update
  assert_equal dry-run "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "2 extension(s); 1 would be upgraded"
  ! grep -q '^gh extension upgrade --all prompt' "$LOG"
}

@test "no extensions installed is a clean skip" {
  : > "$state/list"
  tool_gh_extensions_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "no extensions installed"
  ! grep -q 'upgrade' "$LOG"
}

@test "not authenticated is a clean skip" {
  touch "$state/noauth"
  tool_gh_extensions_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "not authenticated"
}

@test "a failed upgrade is a failure" {
  touch "$state/fail"
  tool_gh_extensions_update
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "gh extension upgrade --all failed"
}
