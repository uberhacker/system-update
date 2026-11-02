#!/usr/bin/env bats
# asdf, both generations: the bash checkout (asdf update) and the Go binary
# (no self-update; a note). Plugin updates for both; with RUNTIMES=1 the
# home ~/.tool-versions pins move to the newest version of the same major.

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
  export ASDF_DIR="$BATS_TEST_TMPDIR/asdf"
  export ASDF_DATA_DIR="$ASDF_DIR"
  mkdir -p "$ASDF_DIR/bin" "$ASDF_DIR/plugins"
  SU_PKG=apt
  SU_DRY_RUN=0
  SU_CFG[RUNTIMES]=0
  STEP_RESULT=""; STEP_NOTE=""
  LOG="$BATS_TEST_TMPDIR/calls.log"; : > "$LOG"
  echo 0.14.1 > "$state/version"
  make_git_pair "$ASDF_DIR/plugins/nodejs"
  # The same fake serves as the bash asdf (with a shebang) and as the Go
  # asdf (no shebang: the kernel says ENOEXEC and execvp runs it with sh).
  asdf_body="
echo \"asdf \$*\" >> '$LOG'
case \"\$*\" in
  version) echo \"v\$(cat '$state/version')\" ;;
  update) [ -e '$state/update_fail' ] && exit 1; echo 0.15.0 > '$state/version' ;;
  'plugin update --all') [ -e '$state/plugins_fail' ] && exit 1
      for d in \"$ASDF_DIR\"/plugins/*/; do git -C \"\$d\" pull -q --ff-only origin master; done ;;
  'latest nodejs 20') echo 20.18.1 ;;
  'latest ruby 3') echo 3.3.0 ;;
esac
exit 0"
  printf '#!/usr/bin/env bash\n%s\n' "$asdf_body" > "$ASDF_DIR/bin/asdf"
  chmod +x "$ASDF_DIR/bin/asdf"
  printf 'nodejs 20.17.0\nruby 3.3.0\npython system\nerlang ref:master\n' > "$SU_USER_HOME/.tool-versions"
  mkdir -p "$BATS_TEST_TMPDIR/project"
  printf 'nodejs 18.20.4\n' > "$BATS_TEST_TMPDIR/project/.tool-versions"
  tools_discover
}

go_asdf() {
  echo 0.16.2 > "$state/version"
  printf ': the Go asdf\n%s\n' "$asdf_body" > "$ASDF_DIR/bin/asdf"
}

@test "asdf is detected through ASDF_DIR" {
  assert_equal "$ASDF_DIR/bin/asdf" "${SU_TOOL_BIN[asdf]}"
}

@test "bash asdf: asdf update, plugin update --all, runtimes off by default" {
  git_advance "$ASDF_DIR/plugins/nodejs"
  tool_asdf_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "asdf 0.14.1 -> 0.15.0"
  assert_contains "$STEP_NOTE" "1 of 1 plugin(s) updated"
  assert_contains "$STEP_NOTE" "runtimes: off; enable with --runtimes or RUNTIMES=1"
  grep -qx 'asdf update' "$LOG"
  grep -qx 'asdf plugin update --all' "$LOG"
  ! grep -q '^asdf install' "$LOG"
}

@test "bash asdf from a package (asdf_updates_disabled) is not self-updated" {
  touch "$ASDF_DIR/asdf_updates_disabled"
  tool_asdf_update
  assert_equal ok "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "self-update disabled by its package"
  ! grep -qx 'asdf update' "$LOG"
}

@test "Go asdf: no self-update, says how to update it; plugins still updated" {
  go_asdf
  git_advance "$ASDF_DIR/plugins/nodejs"
  tool_asdf_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "asdf 0.16.2 is a binary release; update it with your package manager or from github.com/asdf-vm/asdf/releases (no sha256 published)"
  assert_contains "$STEP_NOTE" "1 of 1 plugin(s) updated"
  ! grep -qx 'asdf update' "$LOG"
}

@test "RUNTIMES=1 (bash asdf): home pins move within their major; project pins untouched" {
  SU_CFG[RUNTIMES]=1
  tool_asdf_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "nodejs 20.17.0 -> 20.18.1"
  grep -qx 'asdf latest nodejs 20' "$LOG"
  grep -qx 'asdf install nodejs 20.18.1' "$LOG"
  grep -qx 'asdf global nodejs 20.18.1' "$LOG"
  ! grep -q '^asdf install ruby' "$LOG"        # already the latest 3.x
  ! grep -q 'python' "$LOG"                    # "system" is left alone
  ! grep -q 'erlang' "$LOG"                    # ref: pins are left alone
  ! grep -q '18\.' "$LOG"                      # the project's pin was never read
  assert_equal 'nodejs 18.20.4' "$(cat "$BATS_TEST_TMPDIR/project/.tool-versions")"
}

@test "RUNTIMES=1 (Go asdf): the home default is set with asdf set -u" {
  go_asdf
  SU_CFG[RUNTIMES]=1
  tool_asdf_update
  assert_equal updated "$STEP_RESULT"
  grep -qx 'asdf set -u nodejs 20.18.1' "$LOG"
  ! grep -q '^asdf global' "$LOG"
}

@test "RUNTIMES=1 with everything current" {
  printf 'nodejs 20.18.1\nruby 3.3.0\n' > "$SU_USER_HOME/.tool-versions"
  SU_CFG[RUNTIMES]=1
  tool_asdf_update
  assert_contains "$STEP_NOTE" "runtimes: all current within their majors"
  ! grep -q '^asdf install' "$LOG"
}

@test "dry run with runtimes installs nothing" {
  SU_CFG[RUNTIMES]=1
  SU_DRY_RUN=1
  git_advance "$ASDF_DIR/plugins/nodejs"
  tool_asdf_update
  assert_equal dry-run "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "would run asdf update"
  assert_contains "$STEP_NOTE" "would run asdf plugin update --all (1 plugin(s))"
  assert_contains "$STEP_NOTE" "would upgrade nodejs 20.17.0 -> 20.18.1"
  ! grep -qE '^asdf (update|plugin update|install|global|set)' "$LOG"
  assert_equal 0.14.1 "$(cat "$state/version")"
}

@test "a failed plugin update is a failure" {
  touch "$state/plugins_fail"
  tool_asdf_update
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "asdf plugin update --all failed"
}

@test "no plugins installed" {
  rm -rf "$ASDF_DIR/plugins/nodejs"
  tool_asdf_update
  assert_contains "$STEP_NOTE" "no plugins installed"
}

@test "something else called asdf is skipped" {
  printf '#!/usr/bin/env bash\necho "asdf: command not found"\n' > "$ASDF_DIR/bin/asdf"
  tool_asdf_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "looks like a different program"
}
