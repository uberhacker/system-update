#!/usr/bin/env bats
# Command line parsing.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  export SU_SYSTEM_CONFIG=/nonexistent
  export SU_CONFIG_FILE="$BATS_TEST_TMPDIR/empty.conf"; : > "$SU_CONFIG_FILE"
  export SU_PKG_FALLBACK=0
}

@test "-n sets dry run" { args_parse -n; args_apply; assert_equal 1 "$SU_DRY_RUN"; }
@test "-d is an alias for --dry-run" { args_parse -d; args_apply; assert_equal 1 "$SU_DRY_RUN"; }
@test "--dry-run long form" { args_parse --dry-run; args_apply; assert_equal 1 "$SU_DRY_RUN"; }
@test "default is not a dry run" { args_parse; args_apply; assert_equal 0 "$SU_DRY_RUN"; }
@test "combined short flags -nv" { args_parse -nv; args_apply; assert_equal 1 "$SU_DRY_RUN"; assert_equal 1 "$SU_VERBOSE"; }
@test "-y sets yes" { args_parse -y; args_apply; assert_equal 1 "$SU_YES"; }

@test "--only and --skip (both syntaxes)" {
  args_parse --only=apt,nvm --skip snap
  args_apply
  assert_equal "apt,nvm" "$SU_ONLY"
  assert_equal "snap" "$SU_SKIP"
}

@test "--timeout sets the timeout" { args_parse --timeout 42; args_apply; assert_equal 42 "$SU_TIMEOUT"; }
@test "--timeout with garbage is rejected" {
  args_parse --timeout abc
  run args_apply
  assert_equal 2 "$status"
}
@test "option needing a value without one is rejected" { run args_parse --only; assert_equal 2 "$status"; }
@test "unknown option is rejected" { run args_parse --bogus; assert_equal 2 "$status"; assert_contains "$output" "unknown option"; }
@test "positional arguments are rejected" { run args_parse foo; assert_equal 2 "$status"; }
@test "--no-color" { args_parse --no-color; args_apply; assert_equal never "$SU_COLOR"; }
@test "--color always" { args_parse --color=always; args_apply; assert_equal always "$SU_COLOR"; }
@test "--color garbage rejected" { args_parse --color sometimes; run args_apply; assert_equal 2 "$status"; }
@test "--firmware / --prune-node / --install-jq / --allow-unverified-installers / --aur" {
  args_parse --firmware --prune-node --install-jq --allow-unverified-installers --aur --no-autoremove
  args_apply
  cfg_bool FIRMWARE; cfg_bool PRUNE_NODE; cfg_bool INSTALL_JQ; cfg_bool ALLOW_UNVERIFIED_INSTALLERS; cfg_bool AUR_HELPER
  ! cfg_bool AUTOREMOVE
}
@test "opt-in step flags: --nvim-plugins --runtimes --npm-globals --go-toolchain --containers" {
  args_parse
  args_apply
  ! cfg_bool NVIM_PLUGINS; ! cfg_bool RUNTIMES; ! cfg_bool NPM_GLOBALS; ! cfg_bool GO_TOOLCHAIN; ! cfg_bool CONTAINERS
  args_parse --nvim-plugins --runtimes --npm-globals --go-toolchain --containers
  args_apply
  cfg_bool NVIM_PLUGINS; cfg_bool RUNTIMES; cfg_bool NPM_GLOBALS; cfg_bool GO_TOOLCHAIN; cfg_bool CONTAINERS
  assert_equal flag "${SU_CFG_SOURCE[CONTAINERS]}"
}
@test "--go is an alias for --go-toolchain" { args_parse --go; args_apply; cfg_bool GO_TOOLCHAIN; }
@test "--source and --branch feed self-update settings" {
  args_parse --source https://github.com/uberhacker/system-update --branch main
  args_apply
  assert_equal "https://github.com/uberhacker/system-update" "$(cfg SELF_UPDATE_REPO)"
  assert_equal main "$(cfg SELF_UPDATE_BRANCH)"
}
@test "--source with a non-https URL is rejected" {
  args_parse --source git@github.com:x/y.git
  run args_apply
  assert_equal 2 "$status"
}
@test "--quiet and --verbose together keep verbose" { args_parse -q -v; args_apply; assert_equal 1 "$SU_VERBOSE"; assert_equal 0 "$SU_QUIET"; }
@test "--config FILE is recorded" { args_parse --config /tmp/x.conf; assert_equal /tmp/x.conf "$SU_CONFIG_FILE"; }

# End to end through the entry point.
@test "entry: --help exits 0 and shows usage" {
  run "$REPO_ROOT/bin/system-update" --help
  assert_equal 0 "$status"
  assert_contains "$output" "Usage: system-update"
  assert_contains "$output" "--self-update"
  assert_contains "$output" "Opt-in steps (off by default"
  assert_contains "$output" "--nvim-plugins"
  assert_contains "$output" "--go-toolchain"
  assert_contains "$output" "--containers"
}
@test "entry: --version prints the version" {
  run "$REPO_ROOT/bin/system-update" --version
  assert_equal 0 "$status"
  [[ "$output" =~ ^system-update\ [0-9]+\.[0-9]+\.[0-9]+ ]]
}
@test "entry: unknown option exits 2 with usage" {
  run "$REPO_ROOT/bin/system-update" --nope
  assert_equal 2 "$status"
  assert_contains "$output" "unknown option"
  assert_contains "$output" "Usage:"
}
@test "entry: --list reports the fixture distro and manager" {
  SU_OS_RELEASE="$(fixture os-release/manjaro.txt)" run "$REPO_ROOT/bin/system-update" --list
  assert_equal 0 "$status"
  assert_contains "$output" "Package manager: pacman"
  assert_contains "$output" "ID=manjaro ID_LIKE=arch"
  assert_contains "$output" "Tools found"
}
@test "entry: the top-level wrapper still works" {
  run "$REPO_ROOT/system-update" --version
  assert_equal 0 "$status"
  assert_contains "$output" "system-update"
}
@test "entry: works through a symlink" {
  ln -s "$REPO_ROOT/bin/system-update" "$BATS_TEST_TMPDIR/su-link"
  run "$BATS_TEST_TMPDIR/su-link" --version
  assert_equal 0 "$status"
  assert_contains "$output" "system-update"
}
