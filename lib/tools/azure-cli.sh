#!/usr/bin/env bash
# lib/tools/azure-cli.sh - Azure CLI (az) and the Bicep CLI that az manages.
#
#  * az from the distro or Microsoft's apt/rpm repository is a distro package:
#    left to the system step. az from pip or the user's own install gets
#    `az upgrade --yes --all false` (the CLI itself; extensions are the
#    user's business).
#  * Bicep installed through az lives in ~/.azure/bin and is upgraded with
#    `az bicep upgrade`. A standalone bicep binary is handled by bicep.sh.

AZ_ENV=(env AZURE_CORE_NO_COLOR=true AZURE_CORE_DISABLE_PROGRESS_BAR=true AZURE_CORE_COLLECT_TELEMETRY=false)

tool_azure_cli_detect() { user_bin az; }

# az_cli_version BIN: the azure-cli version from `az version` (JSON).
az_cli_version() {
  tool_probe "$1" version --output json 2>/dev/null \
    | grep -o -E '"azure-cli"[[:space:]]*:[[:space:]]*"[0-9][0-9.]*"' | head -n1 | grep -o -E '[0-9][0-9.]*' | head -n1
}

tool_azure_cli_update() {
  local bin="${SU_TOOL_BIN[azure-cli]}" method before after log rc=0 notes=() failed=0 changed=0
  local azbicep="${AZURE_CONFIG_DIR:-$SU_USER_HOME/.azure}/bin/bicep" bver

  method=$(install_method "$bin")
  before=$(az_cli_version "$bin")
  [ -n "$before" ] || { step_skip "$bin does not look like the Azure CLI (no version from 'az version')"; return 0; }
  log_info "installed version: $before"
  log=$(tmp_file) || return 1

  case "${method%%:*}" in
    distro)
      notes+=("az belongs to $SU_PKG package '${method#*:}' (updated with the system packages)") ;;
    brew)
      notes+=("az comes from Homebrew (see the brew step)") ;;
    *)
      if [ "$SU_DRY_RUN" = 1 ]; then
        notes+=("would run az upgrade --yes --all false")
      elif SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_user "${AZ_ENV[@]}" "$bin" upgrade --yes --all false; then
        after=$(az_cli_version "$bin")
        if [ -n "$after" ] && [ "$after" != "$before" ]; then
          notes+=("az $before -> $after"); changed=1
        else
          notes+=("az up to date ($before)")
        fi
      else
        notes+=("az upgrade failed"); failed=1
      fi ;;
  esac

  if [ -x "$azbicep" ]; then
    bver=$(version_from_text "$(tool_probe "$azbicep" --version)")
    if [ "$SU_DRY_RUN" = 1 ]; then
      notes+=("would run az bicep upgrade${bver:+ (installed $bver)}")
    else
      : > "$log"
      if run_capture "$log" run_user "${AZ_ENV[@]}" "$bin" bicep upgrade; then
        after=$(version_from_text "$(tool_probe "$azbicep" --version)")
        if [ -n "$after" ] && [ "$after" != "$bver" ]; then
          notes+=("bicep ${bver:-?} -> $after"); changed=1
        else
          notes+=("bicep up to date${bver:+ ($bver)}")
        fi
      else
        notes+=("az bicep upgrade failed"); failed=1
      fi
    fi
  fi

  if [ "$SU_DRY_RUN" = 1 ]; then step_dry "$(join_by '; ' "${notes[@]}")"; return 0; fi
  if [ "$failed" = 1 ]; then step_fail "$(join_by '; ' "${notes[@]}")"; return 0; fi
  if [ "${method%%:*}" = distro ] && [ ! -x "$azbicep" ]; then
    step_skip "$(join_by '; ' "${notes[@]}")"
  elif [ "$changed" = 1 ]; then
    step_updated "$(join_by '; ' "${notes[@]}")"
  else
    step_ok "$(join_by '; ' "${notes[@]}")"
  fi
}
