#!/usr/bin/env bash
# lib/tools/gh-extensions.sh - GitHub CLI extensions (`gh extension upgrade --all`).
#
# gh itself comes from a package manager; only its extensions are updated
# here, as the invoking user. Skips cleanly when none are installed or when
# gh is not authenticated. The dry run uses `gh extension upgrade --dry-run`.

GH_EXT_ENV=(env GH_NO_UPDATE_NOTIFIER=1 GH_PROMPT_DISABLED=1 GH_PAGER=cat NO_COLOR=1)

gh_extensions_dir() {
  if [ -n "${GH_DATA_DIR:-}" ]; then
    printf '%s/extensions\n' "$GH_DATA_DIR"
  else
    printf '%s/gh/extensions\n' "${XDG_DATA_HOME:-$SU_USER_HOME/.local/share}"
  fi
}

tool_gh_extensions_detect() {
  local bin
  bin=$(user_bin gh) || return 1
  [ -d "$(gh_extensions_dir)" ] || return 1
  printf '%s\n' "$bin"
}

tool_gh_extensions_update() {
  local bin="${SU_TOOL_BIN[gh-extensions]}" log rc=0 count upgraded
  log=$(tmp_file) || return 1

  run_capture "$log" run_user "${GH_EXT_ENV[@]}" "$bin" extension list || rc=$?
  if grep -qiE 'gh auth login|not logged in|authentication' "$log"; then
    step_skip "gh is not authenticated (run gh auth login)"
    return 0
  fi
  count=$(count_matching '^gh ' "$log")
  if [ "$count" -eq 0 ]; then
    step_skip "no extensions installed"
    return 0
  fi
  log_info "$count extension(s) installed"
  : > "$log"

  if [ "$SU_DRY_RUN" = 1 ]; then
    rc=0
    run_capture "$log" run_user "${GH_EXT_ENV[@]}" "$bin" extension upgrade --all --dry-run || rc=$?
    if grep -qiE 'gh auth login|authentication required|not logged in' "$log"; then
      step_skip "gh is not authenticated (run gh auth login)"
    elif [ "$rc" -eq 0 ]; then
      upgraded=$(count_matching 'would have upgraded' "$log")
      step_dry "$count extension(s); $upgraded would be upgraded"
    else
      step_dry "$count extension(s); would run gh extension upgrade --all"
    fi
    return 0
  fi

  rc=0
  run_capture "$log" run_user "${GH_EXT_ENV[@]}" "$bin" extension upgrade --all || rc=$?
  if grep -qiE 'gh auth login|authentication required|not logged in' "$log"; then
    step_skip "gh is not authenticated (run gh auth login)"
    return 0
  fi
  if [ "$rc" -ne 0 ]; then
    if grep -qi 'no extensions installed' "$log"; then
      step_skip "no extensions installed"
    else
      step_fail "gh extension upgrade --all failed ($(rc_note "$rc"))"
    fi
    return 0
  fi
  upgraded=$(count_matching 'upgraded from' "$log")
  if [ "$upgraded" -gt 0 ]; then
    step_updated "$upgraded of $count extension(s) upgraded"
  else
    step_ok "$count extension(s) up to date"
  fi
}
