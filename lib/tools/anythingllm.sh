#!/usr/bin/env bash
# lib/tools/anythingllm.sh - AnythingLLM Desktop AppImage.
#
# The original script compared the AppImage *runtime* commit (what
# --appimage-version prints) with the project's release commit, so it never
# matched and re-ran the vendor installer every time. We read the real app
# version from the .desktop entry embedded in the AppImage
# (X-AppImage-Version) and compare it with the latest GitHub release. The
# vendor installer is an unverified "curl | bash" script, so it only runs
# with ALLOW_UNVERIFIED_INSTALLERS=1 (--allow-unverified-installers).

ANYTHINGLLM_REPO="Mintplex-Labs/anything-llm"
ANYTHINGLLM_INSTALLER="https://cdn.anythingllm.com/latest/installer.sh"

tool_anythingllm_detect() { user_bin AnythingLLMDesktop.AppImage; }

# anythingllm_version APPIMAGE: installed version from the embedded .desktop file.
anythingllm_version() {
  local app="$1" tmp ver
  tmp=$(tmp_dir) || return 1
  (cd "$tmp" && timeout -k 2 "$SU_PROBE_TIMEOUT" "$app" --appimage-extract '*.desktop' >/dev/null 2>&1 </dev/null) || true
  ver=$(grep -rh -m1 '^X-AppImage-Version=' "$tmp/squashfs-root" 2>/dev/null | head -n1 | cut -d= -f2)
  rm -rf -- "$tmp/squashfs-root"
  [ -n "$ver" ] || return 1
  version_norm "$ver"
}

tool_anythingllm_update() {
  local app="${SU_TOOL_BIN[anythingllm]}" installed latest tmp dir rc=0 after

  installed=$(anythingllm_version "$app") || {
    step_skip "could not determine the installed version (AppImage extraction failed)"
    return 0
  }
  log_info "installed version: $installed"
  latest=$(gh_latest_version "$ANYTHINGLLM_REPO") || { step_skip "latest release unknown (GitHub API unavailable)"; return 0; }
  log_info "latest release: $latest"
  if ! version_lt "$installed" "$latest"; then
    step_ok "up to date ($installed)"
    return 0
  fi
  if ! cfg_bool ALLOW_UNVERIFIED_INSTALLERS; then
    step_skip "$installed -> $latest available; the vendor installer is unverified, rerun with --allow-unverified-installers"
    return 0
  fi
  dir=$(dirname "$(readlink -f -- "$app")")
  if [ "$SU_DRY_RUN" = 1 ]; then
    step_dry "would run the AnythingLLM installer into $dir ($installed -> $latest)"
    return 0
  fi
  tmp=$(tmp_dir) || return 1
  download "$ANYTHINGLLM_INSTALLER" "$tmp/installer.sh" || { step_fail "download failed"; return 0; }
  bash -n "$tmp/installer.sh" || { step_fail "installer did not parse as a shell script"; return 0; }
  do_user env ANYTHING_LLM_INSTALL_DIR="$dir" bash "$tmp/installer.sh" || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "installer failed ($(rc_note "$rc"))"
    return 0
  fi
  after=$(anythingllm_version "$app" 2>/dev/null || echo "$latest")
  step_updated "$installed -> $after"
}
