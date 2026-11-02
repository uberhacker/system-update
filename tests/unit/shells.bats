#!/usr/bin/env bats
# Oh My Zsh, Oh My Bash and TPM: each updates itself with git through its
# own script; the commits before and after tell whether anything moved.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  bindir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bindir"
  export PATH="$bindir:$PATH"
  export SU_PROBE_TIMEOUT=5
  export SU_TIMEOUT=20
  SU_USER_HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$SU_USER_HOME"
  SU_PKG=apt
  SU_DRY_RUN=0
  STEP_RESULT=""; STEP_NOTE=""
  LOG="$BATS_TEST_TMPDIR/calls.log"; : > "$LOG"
  export ZSH="$BATS_TEST_TMPDIR/omz"
  export OSH="$BATS_TEST_TMPDIR/omb"
  export TMUX_PLUGIN_MANAGER_PATH="$BATS_TEST_TMPDIR/tmux/plugins"
  make_fake_bin "$bindir" zsh 'exec bash "$@"'
  make_fake_bin "$bindir" tmux 'echo tmux'
  # The frameworks' own upgrade scripts, reduced to what matters here: a
  # fast-forward from origin/master, exit 80 when already current (omz).
  make_git_pair "$ZSH"
  mkdir -p "$ZSH/tools"
  printf 'echo "omz upgrade ZSH=$ZSH prompt=$DISABLE_UPDATE_PROMPT" >> %q\n[ -e %q ] && exit 1\ncd "$ZSH" || exit 1\ngit fetch -q origin master\n[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/master)" ] && exit 80\ngit merge -q --ff-only origin/master\n' \
    "$LOG" "$BATS_TEST_TMPDIR/omz_fail" > "$ZSH/tools/upgrade.sh"
  make_git_pair "$OSH"
  mkdir -p "$OSH/tools"
  printf 'echo "omb upgrade OSH=$OSH" >> %q\ncd "$OSH" || exit 1\ngit pull -q --ff-only origin master\n' "$LOG" > "$OSH/tools/upgrade.sh"
  make_git_pair "$TMUX_PLUGIN_MANAGER_PATH/tpm"
  make_git_pair "$TMUX_PLUGIN_MANAGER_PATH/tmux-sensible"
  mkdir -p "$TMUX_PLUGIN_MANAGER_PATH/tpm/bin"
  printf '#!/usr/bin/env bash\necho "update_plugins $* path=$TMUX_PLUGIN_MANAGER_PATH" >> %q\n[ -e %q ] && exit 1\nfor d in "$TMUX_PLUGIN_MANAGER_PATH"/*/; do [ -d "$d/.git" ] && git -C "$d" pull -q --ff-only origin master; done\nexit 0\n' \
    "$LOG" "$BATS_TEST_TMPDIR/tpm_fail" > "$TMUX_PLUGIN_MANAGER_PATH/tpm/bin/update_plugins"
  chmod +x "$TMUX_PLUGIN_MANAGER_PATH/tpm/bin/update_plugins"
  tools_discover
}

head_of() { git -C "$1" rev-parse --short HEAD; }

# --- Oh My Zsh ---------------------------------------------------------------

@test "oh-my-zsh is detected through ZSH" {
  assert_equal "$ZSH" "${SU_TOOL_BIN[oh-my-zsh]}"
}

@test "oh-my-zsh: upgrade script runs non-interactively and moves HEAD" {
  local before; before=$(head_of "$ZSH")
  git_advance "$ZSH"
  tool_oh_my_zsh_update
  assert_equal updated "$STEP_RESULT"
  assert_equal "$before -> $(head_of "$ZSH")" "$STEP_NOTE"
  grep -q "^omz upgrade ZSH=$ZSH prompt=true" "$LOG"
}

@test "oh-my-zsh: exit 80 (already current) is ok" {
  tool_oh_my_zsh_update
  assert_equal ok "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "already at the latest version"
}

@test "oh-my-zsh: dry run fetches and counts, runs no script" {
  git_advance "$ZSH"
  SU_DRY_RUN=1
  tool_oh_my_zsh_update
  assert_equal dry-run "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "1 commit(s) behind origin/master; would run Oh My Zsh's upgrade script"
  ! grep -q '^omz upgrade' "$LOG"
}

@test "oh-my-zsh: dry run when current" {
  SU_DRY_RUN=1
  tool_oh_my_zsh_update
  assert_equal dry-run "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "already at the latest version"
}

@test "oh-my-zsh: a failing upgrade script is a failure" {
  touch "$BATS_TEST_TMPDIR/omz_fail"
  tool_oh_my_zsh_update
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "Oh My Zsh upgrade script failed"
}

@test "oh-my-zsh: not a git checkout is skipped" {
  rm -rf "$ZSH/.git"
  tool_oh_my_zsh_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "not a git checkout"
}

# --- Oh My Bash --------------------------------------------------------------

@test "oh-my-bash: detected through OSH and updated with its script" {
  assert_equal "$OSH" "${SU_TOOL_BIN[oh-my-bash]}"
  git_advance "$OSH"
  tool_oh_my_bash_update
  assert_equal updated "$STEP_RESULT"
  grep -q "^omb upgrade OSH=$OSH" "$LOG"
}

@test "oh-my-bash: current is ok" {
  tool_oh_my_bash_update
  assert_equal ok "$STEP_RESULT"
}

# --- TPM ----------------------------------------------------------------------

@test "tpm: detected through TMUX_PLUGIN_MANAGER_PATH" {
  assert_equal "$TMUX_PLUGIN_MANAGER_PATH/tpm/bin/update_plugins" "${SU_TOOL_BIN[tpm]}"
}

@test "tpm: update_plugins all; counts plugins that moved" {
  git_advance "$TMUX_PLUGIN_MANAGER_PATH/tmux-sensible"
  tool_tpm_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "1 of 2 plugin(s) updated"
  grep -q "^update_plugins all path=$TMUX_PLUGIN_MANAGER_PATH" "$LOG"
}

@test "tpm: nothing moved is ok" {
  tool_tpm_update
  assert_equal ok "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "2 plugin(s) up to date"
}

@test "tpm: dry run runs nothing" {
  git_advance "$TMUX_PLUGIN_MANAGER_PATH/tmux-sensible"
  SU_DRY_RUN=1
  tool_tpm_update
  assert_equal dry-run "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "would run tpm/bin/update_plugins all for 2 plugin(s)"
  ! grep -q '^update_plugins' "$LOG"
}

@test "tpm: a failing update_plugins is a failure" {
  touch "$BATS_TEST_TMPDIR/tpm_fail"
  tool_tpm_update
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "update_plugins all failed"
}
