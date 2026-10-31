#!/usr/bin/env bats
# Go toolchain in /usr/local/go (opt-in): latest stable from go.dev's JSON,
# sha256-verified tarball, atomic swap, old toolchain restored on failure.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  gh_stub_init           # the curl stub serves go.dev too
  bindir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bindir"
  export PATH="$bindir:$PATH"
  export SU_PROBE_TIMEOUT=5
  export SU_TIMEOUT=20
  SU_USER_HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$SU_USER_HOME"
  SU_PKG=apt
  SU_DRY_RUN=0
  SU_CFG[GO_TOOLCHAIN]=1
  STEP_RESULT=""; STEP_NOTE=""
  arch=$(arch_name go)
  SU_GO_ROOT="$BATS_TEST_TMPDIR/usr/local/go"
  SU_GO_DL_JSON="https://go.dev.test/dl?mode=json"
  SU_GO_DL_BASE="https://go.dev.test/dl"
  make_fake_bin "$SU_GO_ROOT/bin" go "echo 'go version go1.22.5 linux/$arch'"
  tarball="go1.23.4.linux-$arch.tar.gz"
  make_tarball "go1.23.4"
  write_dl_json "$(sha256_of "$BATS_TEST_TMPDIR/$tarball")"
  tools_discover
}

# make_tarball VERSION: a go/ tree whose go prints VERSION, as the archive.
make_tarball() {
  rm -rf "$BATS_TEST_TMPDIR/new"
  make_fake_bin "$BATS_TEST_TMPDIR/new/go/bin" go "echo 'go version $1 linux/$arch'"
  echo "$1" > "$BATS_TEST_TMPDIR/new/go/VERSION"
  tar -C "$BATS_TEST_TMPDIR/new" -czf "$BATS_TEST_TMPDIR/$tarball" go
  mkdir -p "$CURL_STUB_DIR/dl"
  cp "$BATS_TEST_TMPDIR/$tarball" "$CURL_STUB_DIR/dl/$tarball.json"
}

# write_dl_json SHA256: go.dev/dl/?mode=json with two stable releases.
write_dl_json() {
  printf '[{"version":"go1.23.4","stable":true,"files":[{"filename":"go1.23.4.src.tar.gz","os":"","arch":"","version":"go1.23.4","sha256":"%s","size":1,"kind":"source"},{"filename":"%s","os":"linux","arch":"%s","version":"go1.23.4","sha256":"%s","size":1,"kind":"archive"},{"filename":"go1.23.4.windows-amd64.zip","os":"windows","arch":"amd64","version":"go1.23.4","sha256":"%s","size":1,"kind":"archive"}]},{"version":"go1.22.10","stable":true,"files":[{"filename":"go1.22.10.linux-%s.tar.gz","os":"linux","arch":"%s","version":"go1.22.10","sha256":"%s","size":1,"kind":"archive"}]}]\n' \
    "$(printf '1%.0s' $(seq 64))" "$tarball" "$arch" "$1" "$(printf '2%.0s' $(seq 64))" "$arch" "$arch" "$(printf '3%.0s' $(seq 64))" \
    > "$CURL_STUB_DIR/dl.json"
}

installed_go() { "$SU_GO_ROOT/bin/go" version | grep -o -E 'go[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1; }
leftovers() { find "$(dirname "$SU_GO_ROOT")" -maxdepth 1 -name '.go-*' | grep -c . || true; }

@test "detected only when SU_GO_ROOT/bin/go exists" {
  assert_equal "$SU_GO_ROOT/bin/go" "${SU_TOOL_BIN[go]}"
  assert_equal system "$(tool_scope go)"
  rm -rf "$SU_GO_ROOT"
  tools_discover
  [ -z "${SU_TOOL_BIN[go]-}" ]
}

@test "off by default: nothing is fetched" {
  SU_CFG[GO_TOOLCHAIN]=0
  tool_go_update
  assert_equal skipped "$STEP_RESULT"
  assert_equal "off by default; enable with --go-toolchain or GO_TOOLCHAIN=1" "$STEP_NOTE"
  ! grep -q . "$CURL_STUB_LOG"
}

@test "a distro-owned Go is left to the system packages" {
  make_fake_bin "$bindir" dpkg 'echo "golang-go: $2"'
  tool_go_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "apt package 'golang-go' (updated with the system packages)"
  ! grep -q . "$CURL_STUB_LOG"
}

@test "latest stable is read from the JSON; verified; swapped in atomically" {
  tool_go_update
  assert_equal updated "$STEP_RESULT"
  assert_equal "go1.22.5 -> go1.23.4" "$STEP_NOTE"
  assert_equal go1.23.4 "$(installed_go)"
  assert_equal go1.23.4 "$(cat "$SU_GO_ROOT/VERSION")"
  assert_equal 0 "$(leftovers)"
  grep -q "go.dev.test/dl/$tarball\$" "$CURL_STUB_LOG"
}

@test "already on the latest stable is ok" {
  make_fake_bin "$SU_GO_ROOT/bin" go "echo 'go version go1.23.4 linux/$arch'"
  tool_go_update
  assert_equal ok "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "up to date (go1.23.4)"
  ! grep -q "$tarball" "$CURL_STUB_LOG"
}

@test "dry run reads the release list only" {
  SU_DRY_RUN=1
  tool_go_update
  assert_equal dry-run "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "would download $tarball, verify its sha256 and replace $SU_GO_ROOT (go1.22.5 -> go1.23.4)"
  assert_equal 1 "$(grep -c . "$CURL_STUB_LOG")"
  assert_equal go1.22.5 "$(installed_go)"
}

@test "a sha256 that does not match leaves the old toolchain untouched" {
  write_dl_json "$(printf 'f%.0s' $(seq 64))"
  tool_go_update
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "checksum verification failed; $SU_GO_ROOT left untouched"
  assert_equal go1.22.5 "$(installed_go)"
  assert_equal 0 "$(leftovers)"
}

@test "an archive whose go does not report the new version is rolled back" {
  make_tarball go1.21.0
  write_dl_json "$(sha256_of "$BATS_TEST_TMPDIR/$tarball")"
  tool_go_update
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "does not report go1.23.4; old one restored"
  assert_equal go1.22.5 "$(installed_go)"
  assert_equal 0 "$(leftovers)"
}

@test "an unreachable release list is a failure, not an update" {
  rm "$CURL_STUB_DIR/dl.json"
  tool_go_update
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "could not fetch the Go release list"
  assert_equal go1.22.5 "$(installed_go)"
}

@test "works without jq (fallback parser)" {
  export SU_FORCE_NO_JQ=1
  assert_equal "go1.23.4 $(sha256_of "$BATS_TEST_TMPDIR/$tarball") $tarball" "$(go_latest_info "$CURL_STUB_DIR/dl.json" "$arch")"
  tool_go_update
  assert_equal updated "$STEP_RESULT"
  assert_equal go1.23.4 "$(installed_go)"
}
