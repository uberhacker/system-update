#!/usr/bin/env bats
# AnythingLLM Desktop: the vendor installer asks y/n questions with `read`
# under `set -e`; we answer them from a file so it neither dies on closed
# stdin nor touches AppArmor or starts the app.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  gh_stub_init
  bindir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bindir"
  export PATH="$bindir:$PATH"
  export SU_PROBE_TIMEOUT=5
  export SU_TIMEOUT=20
  SU_PKG=apt
  SU_DRY_RUN=0
  STEP_RESULT=""; STEP_NOTE=""
  export ALLOW_UNVERIFIED_INSTALLERS=1
  config_load
  export LLM_LOG="$BATS_TEST_TMPDIR/installer.log"
  : > "$LLM_LOG"
  fake_appimage "$bindir/AnythingLLMDesktop.AppImage" 1.18.0
  gh_stub_release Mintplex-Labs/anything-llm v1.19.0 "" 
  serve_installer
  tools_discover
}

# fake_appimage PATH VERSION: answers --appimage-extract like a real AppImage.
fake_appimage() {
  cat > "$1" <<APP
#!/usr/bin/env bash
if [ "\$1" = --appimage-extract ]; then
  mkdir -p squashfs-root
  printf '[Desktop Entry]\nName=AnythingLLM\nX-AppImage-Version=$2\n' > squashfs-root/anythingllm-desktop.desktop
fi
APP
  chmod +x "$1"
}

# serve_installer: an installer with the same questions, in the same order,
# as cdn.anythingllm.com/latest/installer.sh (AppArmor taken as active).
serve_installer() {
  mkdir -p "$CURL_STUB_DIR/latest"
  cat > "$CURL_STUB_DIR/latest/installer.sh.json" <<'INST'
#!/bin/sh
set -eu
INSTALL_DIR="${ANYTHING_LLM_INSTALL_DIR:-$HOME}"
APP="$INSTALL_DIR/AnythingLLMDesktop.AppImage"
echo "Install Directory: $INSTALL_DIR"
if [ -f "$APP" ]; then
  echo "Existing installation found at $APP"
  read -p "Do you want to re-download and overwrite it? (y/n): " overwrite
  if [ "$overwrite" = y ]; then
    sed -i 's/X-AppImage-Version=[0-9.]*/X-AppImage-Version=1.19.0/' "$APP"
    echo downloaded >> "$LLM_LOG"
  fi
fi
read -p "Do you want to auto-create an AppArmor profile for AnythingLLM now? (y/n): " create_apparmor
[ "$create_apparmor" = y ] && echo apparmor >> "$LLM_LOG"
read -p "Do you want to start AnythingLLMDesktop now? (y/n): " start
[ "$start" = y ] && echo started >> "$LLM_LOG"
echo done >> "$LLM_LOG"
INST
}

@test "update answers yes to the overwrite and no to AppArmor and starting the app" {
  tool_anythingllm_update
  assert_equal updated "$STEP_RESULT"
  assert_equal "1.18.0 -> 1.19.0" "$STEP_NOTE"
  assert_equal "$(printf 'downloaded\ndone')" "$(cat "$LLM_LOG")"
}

@test "installer runs with ANYTHING_LLM_INSTALL_DIR set to the AppImage's directory" {
  real="$BATS_TEST_TMPDIR/opt/AnythingLLMDesktop.AppImage"
  mkdir -p "${real%/*}"
  mv "$bindir/AnythingLLMDesktop.AppImage" "$real"
  ln -s "$real" "$bindir/AnythingLLMDesktop.AppImage"
  tools_discover
  tool_anythingllm_update
  assert_equal updated "$STEP_RESULT"
  grep -q 'X-AppImage-Version=1.19.0' "$real"
}

@test "up to date: the installer is not downloaded" {
  fake_appimage "$bindir/AnythingLLMDesktop.AppImage" 1.19.0
  tool_anythingllm_update
  assert_equal ok "$STEP_RESULT"
  ! grep -q installer.sh "$CURL_STUB_LOG"
}

@test "without --allow-unverified-installers it only reports the new version" {
  export ALLOW_UNVERIFIED_INSTALLERS=0
  config_load
  tool_anythingllm_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "--allow-unverified-installers"
  [ ! -s "$LLM_LOG" ]
}

@test "an AppImage the user cannot write is skipped with a hint, not failed" {
  [ "$(id -u)" -ne 0 ] || skip "root can write anything"
  chmod a-w "$bindir/AnythingLLMDesktop.AppImage"
  tool_anythingllm_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "not writable"
  [ ! -s "$LLM_LOG" ]
}

@test "an AppImage under another name is skipped: our answers would not line up" {
  real="$BATS_TEST_TMPDIR/opt/anythingllm-1.18.0.AppImage"
  mkdir -p "${real%/*}"
  mv "$bindir/AnythingLLMDesktop.AppImage" "$real"
  ln -s "$real" "$bindir/AnythingLLMDesktop.AppImage"
  tools_discover
  tool_anythingllm_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "not named AnythingLLMDesktop.AppImage"
  [ ! -s "$LLM_LOG" ]
}

@test "dry run names the directory and runs nothing" {
  SU_DRY_RUN=1
  tool_anythingllm_update
  assert_equal dry-run "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "$bindir"
  [ ! -s "$LLM_LOG" ]
}

@test "an installer that leaves the old version behind is a warning, not an update" {
  sed -i 's/^    sed -i .*$/    :/' "$CURL_STUB_DIR/latest/installer.sh.json"
  tool_anythingllm_update
  assert_equal warn "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "still 1.18.0"
}
