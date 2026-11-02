#!/usr/bin/env bats
# Neovim plugin sync (opt-in): lazy.nvim / packer / vim-plug detection,
# headless run with a timeout, the lockfile tells whether anything moved.

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
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/data"
  mkdir -p "$XDG_CONFIG_HOME/nvim" "$XDG_DATA_HOME/nvim"
  lock="$XDG_CONFIG_HOME/nvim/lazy-lock.json"
  echo '{"plenary.nvim":{"commit":"aaaa"}}' > "$lock"
  SU_PKG=apt
  SU_DRY_RUN=0
  SU_CFG[NVIM_PLUGINS]=1
  STEP_RESULT=""; STEP_NOTE=""
  LOG="$BATS_TEST_TMPDIR/calls.log"; : > "$LOG"
  make_fake_bin "$bindir" nvim "
echo \"nvim \$* term=\$TERM\" >> '$LOG'
[ -e '$state/hang' ] && sleep 30
[ -e '$state/fail' ] && exit 1
[ -e '$state/change' ] && echo '{\"plenary.nvim\":{\"commit\":\"bbbb\"}}' > '$lock'
exit 0"
  tools_discover
}

@test "off by default: skipped with the flag and key named, nvim never runs" {
  SU_CFG[NVIM_PLUGINS]=0
  tool_nvim_plugins_update
  assert_equal skipped "$STEP_RESULT"
  assert_equal "off by default; enable with --nvim-plugins or NVIM_PLUGINS=1" "$STEP_NOTE"
  ! grep -q . "$LOG"
}

@test "lazy.nvim is detected from the lockfile" {
  assert_equal lazy.nvim "${SU_TOOL_BIN[nvim-plugins]}"
}

@test "packer and vim-plug are detected from their files" {
  rm "$lock"
  mkdir -p "$XDG_DATA_HOME/nvim/site/pack/packer/start/packer.nvim"
  tools_discover
  assert_equal packer.nvim "${SU_TOOL_BIN[nvim-plugins]}"
  rm -rf "$XDG_DATA_HOME/nvim/site/pack"
  mkdir -p "$XDG_DATA_HOME/nvim/site/autoload"; : > "$XDG_DATA_HOME/nvim/site/autoload/plug.vim"
  tools_discover
  assert_equal vim-plug "${SU_TOOL_BIN[nvim-plugins]}"
  rm -rf "$XDG_DATA_HOME/nvim/site"
  tools_discover
  [ -z "${SU_TOOL_BIN[nvim-plugins]-}" ]
}

@test "dry run prints the command and does not start nvim" {
  SU_DRY_RUN=1
  tool_nvim_plugins_update
  assert_equal dry-run "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "would run: $bindir/nvim --headless +Lazy! sync +qa"
  ! grep -q . "$LOG"
}

@test "lazy sync that changes the lockfile is an update" {
  touch "$state/change"
  tool_nvim_plugins_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "lazy-lock.json changed"
  grep -q '^nvim --headless +Lazy! sync +qa term=dumb' "$LOG"
}

@test "lazy sync with an unchanged lockfile is ok" {
  tool_nvim_plugins_update
  assert_equal ok "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "plugins up to date (lazy.nvim)"
}

@test "packer runs PackerSync headless and quits on PackerComplete" {
  rm "$lock"
  mkdir -p "$XDG_DATA_HOME/nvim/site/pack/packer/start/packer.nvim"
  tools_discover
  tool_nvim_plugins_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "plugins synced (packer.nvim)"
  grep -q '^nvim --headless -c autocmd User PackerComplete quitall -c PackerSync' "$LOG"
}

@test "a failing sync is a failure" {
  touch "$state/fail"
  tool_nvim_plugins_update
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "lazy.nvim sync failed"
}

@test "a hanging nvim is killed by the timeout" {
  touch "$state/hang"
  SU_TIMEOUT=2
  local start end
  start=$(date +%s)
  tool_nvim_plugins_update
  end=$(date +%s)
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "timed out"
  [ $((end - start)) -lt 20 ]
}
