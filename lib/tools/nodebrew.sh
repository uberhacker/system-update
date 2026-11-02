#!/usr/bin/env bash
# lib/tools/nodebrew.sh - Node.js via nodebrew: newest release of the current major.
# Global packages are migrated with `nodebrew migrate-package`; the previous
# version is only removed with PRUNE_NODE=1 (--prune-node).

tool_nodebrew_detect() { user_bin nodebrew; }

tool_nodebrew_update() {
  local bin="${SU_TOOL_BIN[nodebrew]}" current major latest rc=0 note

  current=$(tool_probe "$bin" ls | sed -n 's/^current:[[:space:]]*//p' | head -n1)
  if ! [[ "$current" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    step_skip "no node version is active in nodebrew (current: ${current:-none})"
    return 0
  fi
  major="${current%%.*}"
  latest=$(SU_RUN_TIMEOUT=$SU_TIMEOUT run_user "$bin" ls-remote 2>/dev/null | tr ' ' '\n' | grep -E "^${major}\.[0-9]+\.[0-9]+$" | sort -V | tail -n1)
  if [ -z "$latest" ]; then
    step_fail "could not list remote versions for $major"
    return 0
  fi
  log_info "current: $current, newest $major release: $latest"
  if [ "$current" = "$latest" ]; then
    step_ok "up to date ($current)"
    return 0
  fi
  if [ "$SU_DRY_RUN" = 1 ]; then
    note="would install $latest, migrate global packages from $current and switch to it"
    cfg_bool PRUNE_NODE && note="$note; would remove $current"
    step_dry "$note"
    return 0
  fi
  run_user "$bin" install-binary "$latest" || run_user "$bin" install "$latest" || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "nodebrew install $latest failed ($(rc_note "$rc")); $current left in place"
    return 0
  fi
  run_user "$bin" migrate-package "$current" || log_warn "migrate-package failed; global packages were not copied"
  run_user "$bin" use "$latest" || { step_fail "nodebrew use $latest failed"; return 0; }
  note="$current -> $latest"
  if cfg_bool PRUNE_NODE; then
    if run_user "$bin" uninstall "$current"; then note="$note; removed $current"; fi
  fi
  step_updated "$note"
}
