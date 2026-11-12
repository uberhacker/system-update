#!/usr/bin/env bats
# MOVE_TO_HOME / --move-to-home (Ed's issue 3): a self-updating tool in a
# root-owned /usr/local/bin is moved to ~/.local/bin once, so its own
# updater runs as the user from then on, with no sudo.

load ../test_helper

setup() {
  SU_OUT=1
  export SU_SYSTEM_CONFIG=/nonexistent
  export SU_CONFIG_FILE="$BATS_TEST_TMPDIR/empty.conf"; : > "$SU_CONFIG_FILE"
  load_su
  SU_USER_HOME="$BATS_TEST_TMPDIR/home"
  homebin="$SU_USER_HOME/.local/bin"
  sysbin="$BATS_TEST_TMPDIR/usr-local-bin"
  mkdir -p "$sysbin" "$SU_USER_HOME"
  export PATH="$homebin:$sysbin:$PATH"
  export SU_PROBE_TIMEOUT=5 SU_TIMEOUT=20
  SU_PKG=apt; SU_DRY_RUN=0; STEP_RESULT=""; STEP_NOTE=""
  RAN="$BATS_TEST_TMPDIR/ran"; : > "$RAN"
  ver="$BATS_TEST_TMPDIR/ver"; echo 1.0.105 > "$ver"
  make_fake_bin "$sysbin" copilot "case \"\$1\" in
  --version) echo \"GitHub Copilot CLI \$(cat '$ver').\" ;;
  update) echo \"\$0\" > '$BATS_TEST_TMPDIR/updated-from'; echo 1.0.106 > '$ver' ;;
esac"
  tools_discover
  # Only the fake tool: nothing else installed on the test machine may run.
  SU_TOOLS=(copilot)
  distro_pkg_owner() { return 1; }
  # The test runs as one user: the "root-owned" directory is simulated.
  user_can_write() { case "$1" in "$sysbin"|"$sysbin"/*|"$BATS_TEST_TMPDIR/opt"|"$BATS_TEST_TMPDIR/opt"/*) return 1 ;; esac; return 0; }
  sudo_available() { return 0; }
  do_user() { echo "user $*" >> "$RAN"; "$@"; }
  do_root() { echo "root $*" >> "$RAN"; "$@"; }
  config_set MOVE_TO_HOME copilot test
}

@test "copilot in a root-owned directory is moved to ~/.local/bin and updated as the user" {
  tools_run_all user
  [ -x "$homebin/copilot" ]
  [ ! -e "$sysbin/copilot" ]
  assert_equal "$homebin/copilot" "${SU_TOOL_BIN[copilot]}"
  assert_equal "$homebin/copilot" "$(cat "$BATS_TEST_TMPDIR/updated-from")"
  grep -q "^root rm -f -- $sysbin/copilot$" "$RAN"
  grep -q "^user copilot update$" "$RAN"
  ! grep -q "^root env" "$RAN"
  grep -q "copilot|updated|1.0.105 -> 1.0.106" <<< "$(printf '%s|%s|%s\n' "${SU_STEP_NAMES[0]}" "${SU_STEP_RESULTS[0]}" "${SU_STEP_NOTES[0]}")"
}

@test "not in MOVE_TO_HOME: left where it is and updated as root" {
  config_set MOVE_TO_HOME wp-cli test
  tools_run_all user
  [ -e "$sysbin/copilot" ]
  [ ! -e "$homebin/copilot" ]
  grep -q "^root env HOME=/root copilot update$" "$RAN"
}

@test "MOVE_TO_HOME=all covers it" {
  config_set MOVE_TO_HOME all test
  tools_run_all user
  [ -x "$homebin/copilot" ]
  [ ! -e "$sysbin/copilot" ]
}

@test "~/.local/bin not on PATH ahead of the old place: not moved, and says how to fix PATH" {
  PATH="$sysbin:$homebin:${PATH#"$homebin:$sysbin:"}"
  run tool_move_home copilot
  assert_equal 1 "$status"
  assert_contains "$output" "not on your PATH ahead of $sysbin"
  assert_contains "$output" 'export PATH="$HOME/.local/bin:$PATH"'
  [ -e "$sysbin/copilot" ]
  [ ! -e "$homebin/copilot" ]
}

@test "a link, a distro package's file, or a different file already in ~/.local/bin: not moved" {
  mkdir -p "$BATS_TEST_TMPDIR/opt"
  mv "$sysbin/copilot" "$BATS_TEST_TMPDIR/opt/copilot"
  ln -s "$BATS_TEST_TMPDIR/opt/copilot" "$sysbin/copilot"
  run tool_move_home copilot
  assert_equal 1 "$status"
  assert_contains "$output" "is a link to"
  rm "$sysbin/copilot"; mv "$BATS_TEST_TMPDIR/opt/copilot" "$sysbin/copilot"

  distro_pkg_owner() { echo copilot-cli; }
  run tool_move_home copilot
  assert_equal 1 "$status"
  assert_contains "$output" "belongs to apt package 'copilot-cli'"
  distro_pkg_owner() { return 1; }

  mkdir -p "$homebin"; echo other > "$homebin/copilot"
  run tool_move_home copilot
  assert_equal 1 "$status"
  assert_contains "$output" "already exists and differs"
  [ -e "$sysbin/copilot" ]
}

@test "no sudo: not moved" {
  sudo_available() { return 1; }
  run tool_move_home copilot
  assert_equal 1 "$status"
  assert_contains "$output" "needs sudo"
  [ -e "$sysbin/copilot" ]
}

@test "dry run: says what it would move and moves nothing" {
  SU_DRY_RUN=1
  run tool_move_home copilot
  assert_contains "$output" "would move $sysbin/copilot to $homebin/copilot"
  [ -e "$sysbin/copilot" ]
  [ ! -e "$homebin/copilot" ]
}

@test "already in a directory the user can write: nothing to move" {
  user_can_write() { return 0; }
  run tool_move_home copilot
  assert_equal 1 "$status"
  [ -e "$sysbin/copilot" ]
  [ ! -e "$homebin/copilot" ]
}

@test "the flag sets MOVE_TO_HOME" {
  args_parse --move-to-home wp-cli,terminus
  args_apply
  assert_equal wp-cli,terminus "$(cfg MOVE_TO_HOME)"
}
