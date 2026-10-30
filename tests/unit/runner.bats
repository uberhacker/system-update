#!/usr/bin/env bats
# Step runner, result tracking, summary table and exit code.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  export SU_SYSTEM_CONFIG=/nonexistent
  export SU_CONFIG_FILE="$BATS_TEST_TMPDIR/empty.conf"; : > "$SU_CONFIG_FILE"
  SU_ONLY=""; SU_SKIP=""
  SU_STEP_NAMES=(); SU_STEP_RESULTS=(); SU_STEP_NOTES=()
}

s_ok()   { step_ok "fine"; }
s_up()   { step_updated "1.0 -> 1.1"; }
s_fail() { step_fail "boom"; }
s_rc()   { return 3; }
s_skip() { step_skip "nope"; }
s_dry()  { step_dry "would do it"; }
s_warn() { step_warn "reboot required"; }
s_silent() { :; }

@test "results are recorded in order" {
  run_step tools a s_ok
  run_step tools b s_up
  run_step tools c s_skip
  run_step tools d s_dry
  assert_equal "a b c d" "${SU_STEP_NAMES[*]}"
  assert_equal "ok updated skipped dry-run" "${SU_STEP_RESULTS[*]}"
  assert_equal "1.0 -> 1.1" "${SU_STEP_NOTES[1]}"
}

@test "a function that returns non-zero without reporting is failed" {
  run_step tools d s_rc
  assert_equal failed "${SU_STEP_RESULTS[0]}"
  assert_contains "${SU_STEP_NOTES[0]}" "exit code 3"
}

@test "a silent success is ok" {
  run_step tools e s_silent
  assert_equal ok "${SU_STEP_RESULTS[0]}"
}

@test "summary exits 1 when anything failed and shows counts" {
  run_step tools a s_ok
  run_step tools b s_up
  run_step tools c s_fail
  run_step tools d s_skip
  run summary_print
  assert_equal 1 "$status"
  assert_contains "$output" "1 ok, 1 updated, 1 skipped, 1 failed, 0 dry-run"
  assert_contains "$output" "boom"
  assert_contains "$output" "Summary"
}

@test "summary exits 0 when nothing failed" {
  run_step tools a s_ok
  run_step tools b s_dry
  run summary_print
  assert_equal 0 "$status"
  assert_contains "$output" "1 ok, 0 updated, 0 skipped, 0 failed, 1 dry-run"
}

@test "a warning is shown in the summary but does not fail the run" {
  run_step tools a s_ok
  run_step extras reboot-check s_warn
  assert_equal "ok warn" "${SU_STEP_RESULTS[*]}"
  run summary_print
  assert_equal 0 "$status"
  assert_contains "$output" "1 ok, 0 updated, 0 skipped, 0 failed, 0 dry-run, 1 warning(s)"
  assert_contains "$output" "warn     reboot-check reboot required"
}

@test "imported child results accept warn and reject unknown statuses" {
  local f="$BATS_TEST_TMPDIR/results"
  printf 'nvm\tupdated\tv20 -> v22\nx\twarn\tcareful\ny\tbogus\twhat\n' > "$f"
  runner_import_file "$f"
  assert_equal "updated warn failed" "${SU_STEP_RESULTS[*]}"
  assert_contains "${SU_STEP_NOTES[2]}" "unrecognised result"
}

@test "summary with no steps" {
  run summary_print
  assert_equal 0 "$status"
  assert_contains "$output" "no steps were run"
}

@test "--only filters by name and by group" {
  SU_ONLY="b"
  run_step tools a s_ok
  run_step tools b s_ok
  assert_equal "b" "${SU_STEP_NAMES[*]}"
  SU_STEP_NAMES=(); SU_STEP_RESULTS=(); SU_STEP_NOTES=()
  SU_ONLY="system"
  run_step system apt s_ok
  run_step tools kilo s_ok
  assert_equal "apt" "${SU_STEP_NAMES[*]}"
}

@test "--skip filters by name and by group" {
  SU_SKIP="tools,snap"
  run_step system apt s_ok
  run_step extras snap s_ok
  run_step extras flatpak s_ok
  run_step tools kilo s_ok
  assert_equal "apt flatpak" "${SU_STEP_NAMES[*]}"
}

@test "step_enabled understands aliases and spaces in lists" {
  SU_SKIP="pkg, nvm"
  ! step_enabled system apt pkg
  ! step_enabled tools nvm
  step_enabled tools uv
  SU_SKIP=""; SU_ONLY="pkg"
  step_enabled system apt pkg
  ! step_enabled tools uv
}

@test "results can be exported to a file and imported" {
  export SU_RESULTS_OUT="$BATS_TEST_TMPDIR/results"
  run_step tools a s_up
  run_step tools b s_fail
  unset SU_RESULTS_OUT
  SU_STEP_NAMES=(); SU_STEP_RESULTS=(); SU_STEP_NOTES=()
  runner_import_file "$BATS_TEST_TMPDIR/results"
  assert_equal "a b" "${SU_STEP_NAMES[*]}"
  assert_equal "updated failed" "${SU_STEP_RESULTS[*]}"
  assert_equal "boom" "${SU_STEP_NOTES[1]}"
}

@test "imported garbage results count as failed" {
  printf 'x\tweird\tnote\n' > "$BATS_TEST_TMPDIR/results"
  runner_import_file "$BATS_TEST_TMPDIR/results"
  assert_equal failed "${SU_STEP_RESULTS[0]}"
}

@test "entry exits non-zero when a tool step fails" {
  local bindir="$BATS_TEST_TMPDIR/bin"
  make_fake_bin "$bindir" kilo 'case "$1" in --version) echo 1.2.3;; upgrade) echo "network down" >&2; exit 7;; esac'
  PATH="$bindir:$PATH" SU_PKG_FALLBACK=0 SU_OS_RELEASE="$(fixture os-release/arch.txt)" \
    run "$REPO_ROOT/bin/system-update" --only kilo --no-color
  assert_equal 1 "$status"
  assert_contains "$output" "0 ok, 0 updated, 0 skipped, 1 failed"
  assert_contains "$output" "exit code 7"
}

@test "entry exits zero when every step is ok or skipped" {
  local bindir="$BATS_TEST_TMPDIR/bin"
  make_fake_bin "$bindir" kilo 'case "$1" in --version) echo 1.2.3;; upgrade) echo ok;; esac'
  PATH="$bindir:$PATH" SU_PKG_FALLBACK=0 SU_OS_RELEASE="$(fixture os-release/arch.txt)" \
    run "$REPO_ROOT/bin/system-update" --only kilo --no-color
  assert_equal 0 "$status"
  assert_contains "$output" "1 ok, 0 updated, 0 skipped, 0 failed"
}
