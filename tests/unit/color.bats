#!/usr/bin/env bats
# Colour and icon behaviour: NO_COLOR, --no-color, non-TTY output, locale.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  export SU_SYSTEM_CONFIG=/nonexistent
  export SU_CONFIG_FILE="$BATS_TEST_TMPDIR/empty.conf"; : > "$SU_CONFIG_FILE"
  unset NO_COLOR
}

@test "auto: no escape codes when stdout is not a TTY" {
  SU_COLOR=auto log_init
  assert_equal "" "$C_RED"
  assert_equal 0 "$SU_USE_COLOR"
}

@test "always forces colours even without a TTY" {
  SU_COLOR=always log_init
  [ -n "$C_RED" ]
  assert_equal $'\033[31m' "$C_RED"
}

@test "never disables colours" {
  SU_COLOR=never log_init
  assert_equal "" "$C_GREEN"
}

@test "NO_COLOR wins over auto" {
  if ! command -v script >/dev/null 2>&1; then skip "util-linux script not available"; fi
  # Under a pseudo-terminal auto would normally colour; NO_COLOR must stop it.
  run script -qec "env NO_COLOR=1 TERM=xterm SU_OS_RELEASE='$(fixture os-release/arch.txt)' SU_PKG_FALLBACK=0 '$REPO_ROOT/bin/system-update' --only nothing --dry-run" /dev/null
  assert_not_contains "$output" $'\033['
}

@test "auto colours on a pseudo-terminal" {
  if ! command -v script >/dev/null 2>&1; then skip "util-linux script not available"; fi
  run script -qec "env -u NO_COLOR TERM=xterm SU_OS_RELEASE='$(fixture os-release/arch.txt)' SU_PKG_FALLBACK=0 '$REPO_ROOT/bin/system-update' --only nothing --dry-run" /dev/null
  assert_contains "$output" $'\033['
}

@test "--no-color flag" {
  args_parse --no-color
  args_apply
  assert_equal never "$SU_COLOR"
  assert_equal "" "$C_RED"
}

@test "piped entry output carries no escape codes" {
  SU_OS_RELEASE="$(fixture os-release/arch.txt)" SU_PKG_FALLBACK=0 run "$REPO_ROOT/bin/system-update" --list
  assert_not_contains "$output" $'\033['
}

@test "COLOR=always from the environment colours piped output" {
  SU_OS_RELEASE="$(fixture os-release/arch.txt)" SU_PKG_FALLBACK=0 COLOR=always run "$REPO_ROOT/bin/system-update" --only nothing --dry-run
  assert_contains "$output" $'\033['
}

@test "ASCII icons when the locale is not UTF-8" {
  LC_ALL=C LANG=C log_init
  assert_equal OK "$I_OK"
  assert_equal XX "$I_FAILED"
  assert_equal ">" "$I_STEP"
}

@test "Unicode icons under a UTF-8 locale" {
  LC_ALL=C.UTF-8 log_init
  assert_equal "✔" "$I_OK"
  assert_equal "▶" "$I_STEP"
  assert_equal "✖" "$I_FAILED"
}

@test "quiet hides info but keeps warnings" {
  SU_QUIET=1
  run log_info "hidden"
  assert_equal "" "$output"
  run log_warn "shown"
  assert_contains "$output" "shown"
}

@test "verbose shows commands" {
  SU_VERBOSE=0
  run log_cmd "ls -l"
  assert_equal "" "$output"
  SU_VERBOSE=1
  run log_cmd "ls -l"
  assert_contains "$output" "ls -l"
}
