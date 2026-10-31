#!/usr/bin/env bats
# Config file parsing (never sourced), precedence and hostile values.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  export SU_SYSTEM_CONFIG="$BATS_TEST_TMPDIR/system.conf"
  export SU_CONFIG_FILE="$BATS_TEST_TMPDIR/user.conf"
  unset TIMEOUT SKIP ONLY SELF_UPDATE_REPO SELF_UPDATE_BRANCH FIRMWARE GITHUB_TOKEN GH_TOKEN COLOR INSTALL_JQ NVIM_PLUGINS RUNTIMES NPM_GLOBALS GO_TOOLCHAIN CONTAINERS 2>/dev/null || true
}

@test "defaults" {
  config_load
  assert_equal "https://github.com/uberhacker/system-update" "$(cfg SELF_UPDATE_REPO)"
  assert_equal "" "$(cfg SELF_UPDATE_BRANCH)"
  assert_equal 300 "$(cfg TIMEOUT)"
  assert_equal 0 "$(cfg FIRMWARE)"
  assert_equal 1 "$(cfg AUTOREMOVE)"
  assert_equal default "${SU_CFG_SOURCE[TIMEOUT]}"
  # Opt-in steps are off.
  assert_equal 0 "$(cfg NVIM_PLUGINS)"
  assert_equal 0 "$(cfg RUNTIMES)"
  assert_equal 0 "$(cfg NPM_GLOBALS)"
  assert_equal 0 "$(cfg GO_TOOLCHAIN)"
  assert_equal 0 "$(cfg CONTAINERS)"
}

@test "opt-in steps can be turned on in the config file or the environment" {
  printf 'RUNTIMES=yes\nCONTAINERS=true\n' > "$SU_CONFIG_FILE"
  config_load
  cfg_bool RUNTIMES; cfg_bool CONTAINERS; ! cfg_bool GO_TOOLCHAIN
  GO_TOOLCHAIN=1 NPM_GLOBALS=on config_load
  cfg_bool GO_TOOLCHAIN; cfg_bool NPM_GLOBALS
}

@test "user config file is parsed" {
  cat > "$SU_CONFIG_FILE" <<'EOF'
# a comment
TIMEOUT=120

SKIP = "snap, composer"
FIRMWARE=yes
SELF_UPDATE_BRANCH='release/1.x'
EOF
  config_load
  assert_equal 120 "$(cfg TIMEOUT)"
  assert_equal "snap, composer" "$(cfg SKIP)"
  assert_equal 1 "$(cfg FIRMWARE)"
  assert_equal "release/1.x" "$(cfg SELF_UPDATE_BRANCH)"
  assert_contains "${SU_CFG_SOURCE[TIMEOUT]}" "user.conf:2"
}

@test "system file is overridden by the user file" {
  echo 'TIMEOUT=50' > "$SU_SYSTEM_CONFIG"
  echo 'TIMEOUT=70' > "$SU_CONFIG_FILE"
  config_load
  assert_equal 70 "$(cfg TIMEOUT)"
}

@test "environment overrides files, flags override environment" {
  echo 'TIMEOUT=120' > "$SU_CONFIG_FILE"
  TIMEOUT=60 config_load
  assert_equal 60 "$(cfg TIMEOUT)"
  assert_equal env "${SU_CFG_SOURCE[TIMEOUT]}"
  SU_ARG_TIMEOUT=30
  args_apply
  assert_equal 30 "$(cfg TIMEOUT)"
  assert_equal 30 "$SU_TIMEOUT"
}

@test "hostile values are rejected and never executed" {
  rm -f "$BATS_TEST_TMPDIR/pwned"
  cat > "$SU_CONFIG_FILE" <<EOF
TIMEOUT=\$(touch $BATS_TEST_TMPDIR/pwned)
SKIP=snap; touch $BATS_TEST_TMPDIR/pwned
SELF_UPDATE_REPO=http://example.com/evil
SELF_UPDATE_REPO=\`touch $BATS_TEST_TMPDIR/pwned\`
SELF_UPDATE_BRANCH=../../etc
GITHUB_TOKEN=abc def
UNKNOWN_KEY=1
COLOR=rainbow
this is not a key=value line
EOF
  run config_load
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
  assert_contains "$output" "invalid value for TIMEOUT"
  assert_contains "$output" "invalid value for SKIP"
  assert_contains "$output" "invalid value for SELF_UPDATE_REPO"
  assert_contains "$output" "invalid value for SELF_UPDATE_BRANCH"
  assert_contains "$output" "invalid value for GITHUB_TOKEN"
  assert_contains "$output" "unknown key 'UNKNOWN_KEY'"
  assert_contains "$output" "invalid value for COLOR"
  assert_contains "$output" "not a KEY=value line"
  # Values stay at their defaults.
  config_load >/dev/null
  assert_equal 300 "$(cfg TIMEOUT)"
  assert_equal "" "$(cfg SKIP)"
  assert_equal "https://github.com/uberhacker/system-update" "$(cfg SELF_UPDATE_REPO)"
  assert_equal "" "$(cfg SELF_UPDATE_BRANCH)"
  assert_equal auto "$(cfg COLOR)"
}

@test "control characters are rejected" {
  printf 'SKIP=snap\033[31m\n' > "$SU_CONFIG_FILE"
  run config_load
  assert_contains "$output" "invalid value for SKIP"
}

@test "https source is accepted, ssh and http are not" {
  SELF_UPDATE_REPO="https://github.com/uberhacker/system-update.git" config_load
  assert_equal "https://github.com/uberhacker/system-update.git" "$(cfg SELF_UPDATE_REPO)"
  run env SELF_UPDATE_REPO="git@github.com:uberhacker/system-update.git" bash -c 'true'
  SELF_UPDATE_REPO="git@github.com:uberhacker/system-update.git" run config_load
  assert_contains "$output" "invalid value for SELF_UPDATE_REPO"
}

@test "file:// source only with the test toggle" {
  SELF_UPDATE_REPO="file:///tmp/repo.git" run config_load
  assert_contains "$output" "invalid value for SELF_UPDATE_REPO"
  SYSTEM_UPDATE_ALLOW_FILE_SOURCE=1 SELF_UPDATE_REPO="file:///tmp/repo.git" config_load
  assert_equal "file:///tmp/repo.git" "$(cfg SELF_UPDATE_REPO)"
}

@test "GH_TOKEN is accepted as an alias for GITHUB_TOKEN" {
  GH_TOKEN=ghp_abc123 config_load
  assert_equal ghp_abc123 "$(cfg GITHUB_TOKEN)"
}

@test "booleans are normalised" {
  printf 'FIRMWARE=TRUE\nPRUNE_NODE=off\nINSTALL_JQ=1\n' > "$SU_CONFIG_FILE"
  config_load
  assert_equal 1 "$(cfg FIRMWARE)"
  assert_equal 0 "$(cfg PRUNE_NODE)"
  cfg_bool INSTALL_JQ
  ! cfg_bool PRUNE_NODE
}

@test "unreadable --config file warns" {
  SU_CONFIG_FILE=/nonexistent/config run config_load
  assert_contains "$output" "config file not readable"
}
