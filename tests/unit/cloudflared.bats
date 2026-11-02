#!/usr/bin/env bats
# cloudflared as a standalone binary: replaced from the GitHub release only
# with the sha256 the release publishes; repo-installed copies are skipped.

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
  SU_USER_HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$SU_USER_HOME"
  SU_PKG=apt
  SU_DRY_RUN=0
  STEP_RESULT=""; STEP_NOTE=""
  make_fake_bin "$bindir" cloudflared 'echo "cloudflared version 2024.10.0 (built 2024-10-01-1234 UTC)"'
  asset="cloudflared-linux-$(arch_name cloudflared)"
  printf '#!/usr/bin/env bash\necho "cloudflared version 2024.11.1 (built 2024-11-05-1234 UTC)"\n' > "$BATS_TEST_TMPDIR/newbin"
  sum=$(sha256_of "$BATS_TEST_TMPDIR/newbin")
  zeros=$(printf '0%.0s' $(seq 64))
  gh_stub_asset cloudflare/cloudflared 2024.11.1 "$asset" "$BATS_TEST_TMPDIR/newbin"
  tools_discover
}

installed_version() { "$bindir/cloudflared" --version | grep -o -E '[0-9]{4}\.[0-9]+\.[0-9]+'; }

@test "updated when the release notes carry the sha256" {
  gh_stub_release cloudflare/cloudflared 2024.11.1 \
    "## Checksums\\n$asset: $sum\\n$asset.deb: $zeros\\n" "$asset" "$asset.deb"
  tool_cloudflared_update
  assert_equal updated "$STEP_RESULT"
  assert_equal "2024.10.0 -> 2024.11.1" "$STEP_NOTE"
  assert_equal 2024.11.1 "$(installed_version)"
  grep -q "releases/download/2024.11.1/$asset\$" "$CURL_STUB_LOG"
}

@test "a checksums.txt asset is used too" {
  printf '%s  %s\n%s  %s.deb\n' "$zeros" "$asset.deb" "$sum" "$asset" | sed "s/  $asset.deb\$/  $asset/" > "$BATS_TEST_TMPDIR/sums"
  printf '%s  %s\n%s  %s\n' "$zeros" "$asset.deb" "$sum" "$asset" > "$BATS_TEST_TMPDIR/sums"
  gh_stub_asset cloudflare/cloudflared 2024.11.1 checksums.txt "$BATS_TEST_TMPDIR/sums"
  gh_stub_release cloudflare/cloudflared 2024.11.1 "notes" "$asset" "$asset.deb" checksums.txt
  tool_cloudflared_update
  assert_equal updated "$STEP_RESULT"
  assert_equal 2024.11.1 "$(installed_version)"
}

@test "no published sha256: skipped, nothing downloaded or installed" {
  gh_stub_release cloudflare/cloudflared 2024.11.1 "Bug fixes." "$asset" "$asset.deb"
  tool_cloudflared_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "no sha256 published for $asset 2024.11.1; refusing to install an unverified binary"
  assert_equal 2024.10.0 "$(installed_version)"
  ! grep -q "releases/download/2024.11.1/$asset\$" "$CURL_STUB_LOG"
}

@test "a sha256 that does not match: failed, binary untouched" {
  gh_stub_release cloudflare/cloudflared 2024.11.1 "$asset: $zeros\\n" "$asset"
  tool_cloudflared_update
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "checksum verification failed"
  assert_contains "$STEP_NOTE" "left untouched"
  assert_equal 2024.10.0 "$(installed_version)"
}

@test "already current is ok" {
  gh_stub_release cloudflare/cloudflared 2024.10.0 "$asset: $sum\\n" "$asset"
  tool_cloudflared_update
  assert_equal ok "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "up to date (2024.10.0)"
}

@test "dry run asks the API and downloads nothing" {
  gh_stub_release cloudflare/cloudflared 2024.11.1 "$asset: $sum\\n" "$asset"
  SU_DRY_RUN=1
  tool_cloudflared_update
  assert_equal dry-run "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "would download $asset 2024.11.1"
  assert_contains "$STEP_NOTE" "2024.10.0 -> 2024.11.1"
  assert_equal 1 "$(grep -c . "$CURL_STUB_LOG")"
  grep -q 'api.github.test/repos/cloudflare/cloudflared/releases/latest' "$CURL_STUB_LOG"
}

@test "latest release unknown (API unavailable) is a skip" {
  tool_cloudflared_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "latest release unknown"
  assert_equal 2024.10.0 "$(installed_version)"
}

@test "a cloudflared from a package repository is left to the system packages" {
  make_fake_bin "$bindir" dpkg 'echo "cloudflared: $2"'
  gh_stub_release cloudflare/cloudflared 2024.11.1 "$asset: $sum\\n" "$asset"
  tool_cloudflared_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "apt package 'cloudflared' (updated with the system packages)"
  ! grep -q . "$CURL_STUB_LOG"
}

@test "a Homebrew cloudflared is left to the brew step" {
  mkdir -p "$BATS_TEST_TMPDIR/linuxbrew/bin"
  mv "$bindir/cloudflared" "$BATS_TEST_TMPDIR/linuxbrew/bin/cloudflared"
  ln -s "$BATS_TEST_TMPDIR/linuxbrew/bin/cloudflared" "$bindir/cloudflared"
  tool_cloudflared_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "Homebrew"
}

@test "something else called cloudflared is skipped" {
  make_fake_bin "$bindir" cloudflared 'echo "usage: cloudflared-wrapper"'
  tool_cloudflared_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "does not look like cloudflared"
}

@test "works without jq" {
  export SU_FORCE_NO_JQ=1
  gh_stub_release cloudflare/cloudflared 2024.11.1 "## Checksums\\n$asset: $sum\\n" "$asset"
  tool_cloudflared_update
  assert_equal updated "$STEP_RESULT"
  assert_equal 2024.11.1 "$(installed_version)"
}
