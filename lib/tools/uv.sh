#!/usr/bin/env bash
# lib/tools/uv.sh - uv (self update for standalone installs) and `uv tool upgrade --all`.

tool_uv_detect() { user_bin uv; }

# uv_outdated: "tool|installed|latest" from `uv tool list --outdated`
# ("ruff v0.4.0 [latest: 0.5.0]"); older uv without --outdated prints nothing.
uv_outdated() {
  local line re='^([^[:space:]]+) v([^[:space:]]+) \[latest: v?([^]]+)\]'
  while IFS= read -r line; do
    [[ "$line" =~ $re ]] && printf '%s|%s|%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
  done < <(SU_RUN_TIMEOUT=$SU_TIMEOUT run_user "${SU_TOOL_BIN[uv]}" tool list --outdated 2>/dev/null)
}

tool_uv_update() {
  local bin="${SU_TOOL_BIN[uv]}" before after log rc=0 notes=() failed=0 changed=0 method

  method=$(install_method "$bin")
  before=$(version_from_text "$(tool_probe "$bin" --version)")
  [ -n "$before" ] && log_info "installed version: $before"
  log=$(tmp_file) || return 1

  case "${method%%:*}" in
    distro) notes+=("uv itself comes from $SU_PKG package '${method#*:}'") ;;
    pipx|uv) notes+=("uv itself installed with ${method%%:*}") ;;
    *)
      if [ "$SU_DRY_RUN" = 1 ]; then
        notes+=("would run uv self update")
      elif run_capture "$log" run_user "$bin" self update; then
        grep -qiE 'upgraded|updated uv' "$log" && changed=1
        notes+=("self update ok")
      else
        if grep -qiE 'external package manager|not installed via|self-update is not available' "$log"; then
          notes+=("self update unavailable for this install method")
        else
          notes+=("uv self update failed"); failed=1
        fi
      fi ;;
  esac

  if [ -d "${UV_TOOL_DIR:-$SU_USER_HOME/.local/share/uv/tools}" ]; then
    : > "$log"
    if [ "$SU_DRY_RUN" = 1 ]; then
      detail_show "uv tool(s)" uv_outdated
      notes+=("would run uv tool upgrade --all")
    elif run_capture "$log" run_user "$bin" tool upgrade --all; then
      grep -qE '^ *[-+] ' "$log" && changed=1
      notes+=("tool upgrade --all ok")
    else
      notes+=("uv tool upgrade --all failed"); failed=1
    fi
  fi

  if [ "$SU_DRY_RUN" = 1 ]; then step_dry "$(join_by '; ' "${notes[@]}")"; return 0; fi
  if [ "$failed" = 1 ]; then step_fail "$(join_by '; ' "${notes[@]}")"; return 0; fi
  after=$(version_from_text "$(tool_probe "$bin" --version)")
  if [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ]; then
    step_updated "$before -> $after; $(join_by '; ' "${notes[@]}")"
  elif [ "$changed" = 1 ]; then
    step_updated "$(join_by '; ' "${notes[@]}")"
  else
    step_ok "${after:+$after; }$(join_by '; ' "${notes[@]}")"
  fi
}
