#!/usr/bin/env bats
# The per-run log file (lib/core/runlog.sh, _log_file, _run_logged).

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  export SU_SYSTEM_CONFIG=/nonexistent
  export SU_CONFIG_FILE="$BATS_TEST_TMPDIR/empty.conf"; : > "$SU_CONFIG_FILE"
  export SU_PKG_FALLBACK=0
  SU_BIN=system-update
  LOGS="$BATS_TEST_TMPDIR/logs"
  os_detect >/dev/null 2>&1 || true
}

teardown() {
  [ -n "${SU_LOG_FD:-}" ] && exec {SU_LOG_FD}>&-
  SU_LOG_FD=""
  declare -F tmp_cleanup >/dev/null && tmp_cleanup
  return 0
}

open_log() {
  config_set LOGGING 1 test
  config_set LOG_DIR "$LOGS" test
  args_apply
  runlog_open --dry-run
}

@test "a log is opened by default, 0600, with a header and a latest.log link" {
  open_log
  [ -f "$SU_LOG_FILE" ]
  assert_equal "$(basename "$SU_LOG_FILE")" "$(readlink "$LOGS/latest.log")"
  assert_equal 600 "$(stat -c %a "$SU_LOG_FILE")"
  grep -q '^# command  system-update --dry-run' "$SU_LOG_FILE"
  grep -q '^# mode ' "$SU_LOG_FILE"
}

@test "LOGGING=0 / --no-log opens nothing" {
  args_parse --no-log
  config_set LOG_DIR "$LOGS" test
  args_apply
  runlog_open
  assert_equal "" "$SU_LOG_FD"
  [ ! -e "$LOGS" ]
}

@test "--log FILE writes exactly there" {
  args_parse --log "$BATS_TEST_TMPDIR/mine.log"
  args_apply
  runlog_open
  assert_equal "$BATS_TEST_TMPDIR/mine.log" "$SU_LOG_FILE"
  [ ! -e "$LOGS" ]
}

@test "messages are timestamped and colour-free; quiet and verbose-only lines are logged" {
  SU_COLOR=always; log_init
  open_log
  SU_QUIET=1 SU_VERBOSE=0
  log_ok "hidden on the console"
  log_detail "verbose only"
  log_warn "a warning"
  run cat "$SU_LOG_FILE"
  assert_contains "$output" "hidden on the console"
  assert_contains "$output" "verbose only"
  assert_contains "$output" "a warning"
  assert_not_contains "$output" $'\033'
  grep -qE '^[0-9]{2}:[0-9]{2}:[0-9]{2} .*a warning' "$SU_LOG_FILE"
}

@test "a command's output and exit status are logged and still returned to the caller" {
  open_log
  out=$(run_user bash -c 'echo to-stdout; echo to-stderr >&2; exit 3' 2>/dev/null) && rc=0 || rc=$?
  assert_equal 3 "$rc"
  assert_equal to-stdout "$out"
  sleep 0.2   # stderr is copied asynchronously
  run cat "$SU_LOG_FILE"
  assert_contains "$output" '$ bash -c'
  assert_contains "$output" "to-stdout"
  assert_contains "$output" "to-stderr"
  assert_contains "$output" "-> exit 3 after"
}

@test "without a log the runners behave exactly as before" {
  out=$(run_user bash -c 'echo hi; exit 4') && rc=0 || rc=$?
  assert_equal 4 "$rc"
  assert_equal hi "$out"
}

@test "only the newest LOG_KEEP logs are kept" {
  mkdir -p "$LOGS"
  for i in 1 2 3 4 5; do : > "$LOGS/system-update-2026010${i}-000000-1.log"; done
  config_set LOG_KEEP 3 test
  open_log
  run ls "$LOGS"
  assert_not_contains "$output" "20260101"
  assert_not_contains "$output" "20260102"
  assert_not_contains "$output" "20260103"
  assert_contains "$output" "20260105"
  assert_contains "$output" "$(basename "$SU_LOG_FILE")"
}

@test "the GitHub token is never written to the header" {
  config_set GITHUB_TOKEN ghp_secretvalue test
  open_log
  run cat "$SU_LOG_FILE"
  assert_not_contains "$output" ghp_secretvalue
  assert_contains "$output" "GITHUB_TOKEN=<set>"
}

@test "LOG_DIR must be an absolute path" {
  run config_set LOG_DIR relative/dir test
  assert_equal 1 "$status"
  run config_set LOG_DIR /var/../etc test
  assert_equal 1 "$status"
}

@test "runlog_close records the exit status" {
  open_log
  f="$SU_LOG_FILE"
  runlog_close 1
  grep -q '^# finished .*exit status 1' "$f"
}
