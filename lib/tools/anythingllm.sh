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
#
# The installer asks up to three y/n questions with `read` under `set -e`,
# so with stdin closed it stopped at the first one ("re-download and
# overwrite it?") and exited 1. We answer them from a file:
#   1. overwrite the existing AppImage?          y  (that is the update)
#   2./3. create / overwrite the AppArmor profile? n  (needs sudo; left alone)
#   4. start AnythingLLM now?                     n
# Question 1 is only asked when $INSTALL_DIR/AnythingLLMDesktop.AppImage
# exists, so we only run it when that is the file we found; otherwise our
# "y" would answer the AppArmor question.
ANYTHINGLLM_ANSWERS='y\nn\nn\nn\n'

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
  local app="${SU_TOOL_BIN[anythingllm]}" installed latest tmp real dir rc=0 after

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
  real=$(readlink -f -- "$app")
  dir=$(dirname "$real")
  if [ "$(basename "$real")" != AnythingLLMDesktop.AppImage ]; then
    step_skip "$installed -> $latest available; $real is not named AnythingLLMDesktop.AppImage, so the installer would not replace it"
    return 0
  fi
  # The installer runs as the user and overwrites the file in place.
  if ! run_user test -w "$real"; then
    step_skip "$installed -> $latest available; $real is not writable by $SU_USER (install it in a directory they own, such as ~/.local/bin)"
    return 0
  fi
  if [ "$SU_DRY_RUN" = 1 ]; then
    step_dry "would run the AnythingLLM installer into $dir ($installed -> $latest)"
    return 0
  fi
  tmp=$(tmp_dir) || return 1
  download "$ANYTHINGLLM_INSTALLER" "$tmp/installer.sh" || { step_fail "download failed"; return 0; }
  bash -n "$tmp/installer.sh" || { step_fail "installer did not parse as a shell script"; return 0; }
  printf '%b' "$ANYTHINGLLM_ANSWERS" > "$tmp/answers"
  # Under sudo the installer runs as the user, who must be able to read it.
  if ! user_is_current; then
    chmod a+rx "$tmp" && chmod a+r "$tmp/installer.sh" "$tmp/answers"
  fi
  # It downloads a large AppImage: give it the package-manager time limit.
  # shellcheck disable=SC2016  # $1/$2 belong to the inner shell
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT do_user env ANYTHING_LLM_INSTALL_DIR="$dir" \
    bash -c 'exec bash "$1" < "$2"' anythingllm-installer "$tmp/installer.sh" "$tmp/answers" || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "installer failed ($(SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT rc_note "$rc"); close AnythingLLM if it is running)"
    return 0
  fi
  after=$(anythingllm_version "$app" 2>/dev/null) || after=""
  if [ -n "$after" ] && ! version_lt "$installed" "$after"; then
    step_warn "the installer finished but $real is still $after"
    return 0
  fi
  step_updated "$installed -> ${after:-$latest}"
}
