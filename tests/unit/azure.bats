#!/usr/bin/env bats
# Azure CLI: `az upgrade` only when az is not a distro package, `az bicep
# upgrade` for the Bicep az manages; a standalone bicep binary is updated
# from the GitHub release only when a sha256 is published for it.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  gh_stub_init
  bindir="$BATS_TEST_TMPDIR/bin"; state="$BATS_TEST_TMPDIR/state"
  mkdir -p "$bindir" "$state"
  export PATH="$bindir:$PATH"
  export SU_PROBE_TIMEOUT=5
  export SU_TIMEOUT=20
  SU_USER_HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$SU_USER_HOME"
  export AZURE_CONFIG_DIR="$BATS_TEST_TMPDIR/azure"
  SU_PKG=apt
  SU_DRY_RUN=0
  STEP_RESULT=""; STEP_NOTE=""
  LOG="$BATS_TEST_TMPDIR/calls.log"; : > "$LOG"
  echo 2.65.0 > "$state/az"
  echo 0.30.23 > "$state/azbicep"
  make_fake_bin "$bindir" az "
echo \"az \$*\" >> '$LOG'
case \"\$1\" in
  version) printf '{\\n  \"azure-cli\": \"%s\",\\n  \"azure-cli-core\": \"%s\"\\n}\\n' \"\$(cat '$state/az')\" \"\$(cat '$state/az')\" ;;
  upgrade) [ -e '$state/upgrade_fail' ] && exit 1; echo 2.66.0 > '$state/az' ;;
  bicep) echo 0.31.1 > '$state/azbicep' ;;
esac"
  asset="bicep-linux-$(arch_name bicep)"
}

# The Bicep that `az bicep install` puts under ~/.azure/bin.
az_bicep() {
  make_fake_bin "$AZURE_CONFIG_DIR/bin" bicep "echo \"Bicep CLI version \$(cat '$state/azbicep') (abcdef0123)\""
}

standalone_bicep() {
  make_fake_bin "$bindir" bicep 'echo "Bicep CLI version 0.30.23 (abcdef0123)"'
  printf '#!/usr/bin/env bash\necho "Bicep CLI version 0.31.1 (0123456789)"\n' > "$BATS_TEST_TMPDIR/newbicep"
  sum=$(sha256_of "$BATS_TEST_TMPDIR/newbicep")
  gh_stub_asset Azure/bicep v0.31.1 "$asset" "$BATS_TEST_TMPDIR/newbicep"
}

@test "a user-installed az gets az upgrade --yes --all false" {
  tools_discover
  assert_equal "$bindir/az" "${SU_TOOL_BIN[azure-cli]}"
  tool_azure_cli_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "az 2.65.0 -> 2.66.0"
  grep -qx 'az upgrade --yes --all false' "$LOG"
}

@test "a distro-packaged az is left to the system packages" {
  make_fake_bin "$bindir" dpkg 'echo "azure-cli: $2"'
  tools_discover
  tool_azure_cli_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "apt package 'azure-cli' (updated with the system packages)"
  ! grep -q '^az upgrade' "$LOG"
}

@test "a distro-packaged az still upgrades the Bicep it manages" {
  make_fake_bin "$bindir" dpkg 'echo "azure-cli: $2"'
  az_bicep
  tools_discover
  tool_azure_cli_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "bicep 0.30.23 -> 0.31.1"
  grep -qx 'az bicep upgrade' "$LOG"
  ! grep -q '^az upgrade' "$LOG"
}

@test "current az and Bicep are ok" {
  echo 2.66.0 > "$state/az"
  echo 0.31.1 > "$state/azbicep"
  az_bicep
  tools_discover
  tool_azure_cli_update
  assert_equal ok "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "az up to date (2.66.0)"
  assert_contains "$STEP_NOTE" "bicep up to date (0.31.1)"
}

@test "dry run only reads versions" {
  az_bicep
  SU_DRY_RUN=1
  tools_discover
  tool_azure_cli_update
  assert_equal dry-run "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "would run az upgrade --yes --all false"
  assert_contains "$STEP_NOTE" "would run az bicep upgrade (installed 0.30.23)"
  ! grep -qE '^az (upgrade|bicep)' "$LOG"
  assert_equal 2.65.0 "$(cat "$state/az")"
}

@test "a failed az upgrade is a failure" {
  touch "$state/upgrade_fail"
  tools_discover
  tool_azure_cli_update
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "az upgrade failed"
}

@test "something else called az is skipped" {
  make_fake_bin "$bindir" az 'echo "az: unknown command"; exit 1'
  tools_discover
  tool_azure_cli_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "does not look like the Azure CLI"
}

@test "the Bicep under ~/.azure/bin is not a standalone bicep" {
  az_bicep
  ln -s "$AZURE_CONFIG_DIR/bin/bicep" "$bindir/bicep"
  tools_discover
  [ -z "${SU_TOOL_BIN[bicep]-}" ]
}

@test "a standalone bicep is updated when the release publishes its sha256" {
  standalone_bicep
  gh_stub_release Azure/bicep v0.31.1 "notes" "$asset" "$asset.sha256"
  printf '%s  %s\n' "$sum" "$asset" > "$BATS_TEST_TMPDIR/sumfile"
  gh_stub_asset Azure/bicep v0.31.1 "$asset.sha256" "$BATS_TEST_TMPDIR/sumfile"
  tools_discover
  assert_equal "$bindir/bicep" "${SU_TOOL_BIN[bicep]}"
  tool_bicep_update
  assert_equal updated "$STEP_RESULT"
  assert_equal "0.30.23 -> 0.31.1" "$STEP_NOTE"
  assert_contains "$("$bindir/bicep" --version)" "0.31.1"
}

@test "without a published sha256 the standalone bicep is left alone" {
  standalone_bicep
  gh_stub_release Azure/bicep v0.31.1 "Bicep 0.31.1: new features" "$asset" "bicep-win-x64.exe"
  tools_discover
  tool_bicep_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "no sha256 published for $asset v0.31.1; refusing to install an unverified binary"
  assert_contains "$("$bindir/bicep" --version)" "0.30.23"
  ! grep -q "releases/download/v0.31.1/$asset\$" "$CURL_STUB_LOG"
}

@test "standalone bicep dry run downloads nothing" {
  standalone_bicep
  gh_stub_release Azure/bicep v0.31.1 "notes" "$asset" "$asset.sha256"
  SU_DRY_RUN=1
  tools_discover
  tool_bicep_update
  assert_equal dry-run "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "would download $asset v0.31.1"
  assert_contains "$STEP_NOTE" "0.30.23 -> 0.31.1"
  ! grep -q 'releases/download' "$CURL_STUB_LOG"
}

@test "a current standalone bicep is ok" {
  standalone_bicep
  gh_stub_release Azure/bicep v0.30.23 "notes" "$asset"
  tools_discover
  tool_bicep_update
  assert_equal ok "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "up to date (0.30.23)"
}

@test "a bicep in the user's home is a user-level step; elsewhere system" {
  standalone_bicep
  tools_discover
  assert_equal system "$(tool_scope bicep)"
  rm "$bindir/bicep"
  make_fake_bin "$SU_USER_HOME/.local/bin" bicep 'echo "Bicep CLI version 0.30.23 (abcdef0123)"'
  PATH="$SU_USER_HOME/.local/bin:$PATH" tools_discover
  assert_equal user "$(tool_scope bicep)"
}
