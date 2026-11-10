#!/usr/bin/env bats
# The single-file build (build.sh): it must behave like the multi-file
# program and update itself from a release asset.

load ../test_helper

setup_file() {
  export BUNDLE="$BATS_FILE_TMPDIR/system-update"
  "$REPO_ROOT/build.sh" "$BUNDLE" >/dev/null
}

setup() {
  export SU_OS_RELEASE="$FIXTURES/os-release/arch.txt" SU_PKG_FALLBACK=0
  export SU_SYSTEM_CONFIG=/nonexistent SU_CONFIG_FILE="$BATS_TEST_TMPDIR/empty.conf"
  : > "$SU_CONFIG_FILE"
}

@test "the bundle is one executable file that parses" {
  [ -x "$BUNDLE" ]
  bash -n "$BUNDLE"
  ! grep -q 'source "\$SU_ROOT' "$BUNDLE"
  grep -q '^SU_BUNDLED=1$' "$BUNDLE"
}

@test "it runs from anywhere, with nothing else next to it" {
  mkdir -p "$BATS_TEST_TMPDIR/alone"
  cp "$BUNDLE" "$BATS_TEST_TMPDIR/alone/su"
  run "$BATS_TEST_TMPDIR/alone/su" --version
  assert_equal 0 "$status"
  assert_contains "$output" "single file"
  assert_contains "$output" "$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"
}

@test "SU_BUNDLED in the environment does not switch the multi-file program into bundle mode" {
  SU_BUNDLED=1 run "$REPO_ROOT/bin/system-update" --_steps
  assert_equal 0 "$status"
  grep -qx nvm <<< "$output"
}

@test "--help is the same as the multi-file program's" {
  assert_equal "$("$REPO_ROOT/bin/system-update" --help)" "$("$BUNDLE" --help)"
}

@test "--list finds the same things as the multi-file program" {
  local a b
  a=$("$REPO_ROOT/bin/system-update" --list --no-color | tail -n +2)
  b=$("$BUNDLE" --list --no-color | tail -n +2)
  assert_equal "$a" "$b"
}

@test "every tool module is in the bundle (--_steps)" {
  local f out
  out=$("$BUNDLE" --_steps)
  for f in "$REPO_ROOT"/lib/tools/*.sh; do
    grep -qx "$(basename "$f" .sh)" <<< "$out" || { echo "missing: $f"; return 1; }
  done
}

@test "--completion bash prints the completion script" {
  assert_equal "$(cat "$REPO_ROOT/completions/system-update.bash")" "$("$BUNDLE" --completion bash)"
  run "$BUNDLE" --completion fish
  assert_equal 2 "$status"
}

@test "completion asks a single-file build for its step names" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cp "$BUNDLE" "$BATS_TEST_TMPDIR/bin/system-update"
  run bash -c 'source <("$1" --completion bash); COMP_WORDS=("$2" --only do); COMP_CWORD=2; _system_update; echo "${COMPREPLY[*]}"' \
    _ "$BUNDLE" "$BATS_TEST_TMPDIR/bin/system-update"
  assert_equal docker-compose "$output"
}

@test "a failing step fails the bundle's run too" {
  local bindir="$BATS_TEST_TMPDIR/fake"
  make_fake_bin "$bindir" kilo 'case "$1" in --version) echo 1.2.3;; upgrade) echo "network down" >&2; exit 7;; esac'
  PATH="$bindir:$PATH" run "$BUNDLE" --only kilo --no-color
  assert_equal 1 "$status"
  assert_contains "$output" "exit code 7"
}

# release DIR COMMIT: a fake GitHub "latest release" under DIR holding a
# bundle stamped with COMMIT and its .sha256.
release() {
  local d="$1/releases/latest/download"
  mkdir -p "$d"
  sed "s/^SU_BUNDLE_COMMIT=.*/SU_BUNDLE_COMMIT='$2'/" "$BUNDLE" > "$d/system-update"
  (cd "$d" && sha256sum system-update > system-update.sha256)
}

@test "--self-update replaces the file with the newer release" {
  local repo="$BATS_TEST_TMPDIR/repo" inst="$BATS_TEST_TMPDIR/inst/system-update"
  mkdir -p "$(dirname "$inst")"
  cp "$BUNDLE" "$inst"
  release "$repo" abc1234
  SYSTEM_UPDATE_ALLOW_FILE_SOURCE=1 run "$inst" --self-update --source "file://$repo" --no-color
  assert_equal 0 "$status"
  assert_contains "$output" "-> "
  grep -q "^SU_BUNDLE_COMMIT='abc1234'$" "$inst"
  [ -x "$inst" ]
  # Now current: a second run has nothing to do.
  SYSTEM_UPDATE_ALLOW_FILE_SOURCE=1 run "$inst" --self-update --source "file://$repo" --no-color
  assert_equal 0 "$status"
  assert_contains "$output" "already up to date"
}

@test "--self-update compares the published checksum first and downloads nothing when it matches" {
  local repo="$BATS_TEST_TMPDIR/repo" inst="$BATS_TEST_TMPDIR/inst/system-update" d
  d="$repo/releases/latest/download"
  mkdir -p "$(dirname "$inst")" "$d"
  cp "$BUNDLE" "$inst"
  # Only the checksum of the installed file is published; the asset is absent.
  (cd "$(dirname "$inst")" && sha256sum system-update > "$d/system-update.sha256")
  SYSTEM_UPDATE_ALLOW_FILE_SOURCE=1 run "$inst" --self-update --source "file://$repo" --no-color
  assert_equal 0 "$status"
  assert_contains "$output" "already up to date"
  assert_not_contains "$output" "download failed"
}

@test "--self-update accepts a .sha256 without a trailing newline and a source ending in .git" {
  local repo="$BATS_TEST_TMPDIR/repo" inst="$BATS_TEST_TMPDIR/inst/system-update" d
  d="$repo/releases/latest/download"
  mkdir -p "$(dirname "$inst")"
  cp "$BUNDLE" "$inst"
  release "$repo" abc1234
  printf '%s  system-update' "$(sha256sum < "$d/system-update" | cut -d' ' -f1)" > "$d/system-update.sha256"
  SYSTEM_UPDATE_ALLOW_FILE_SOURCE=1 run "$inst" --self-update --source "file://$repo.git" --no-color
  assert_equal 0 "$status"
  grep -q "^SU_BUNDLE_COMMIT='abc1234'$" "$inst"
}

@test "--self-update --dry-run leaves the file alone" {
  local repo="$BATS_TEST_TMPDIR/repo" inst="$BATS_TEST_TMPDIR/inst/system-update" before
  mkdir -p "$(dirname "$inst")"
  cp "$BUNDLE" "$inst"
  before=$(sha256sum < "$inst")
  release "$repo" abc1234
  SYSTEM_UPDATE_ALLOW_FILE_SOURCE=1 run "$inst" --self-update --dry-run --source "file://$repo" --no-color
  assert_equal 0 "$status"
  assert_contains "$output" "would replace"
  assert_equal "$before" "$(sha256sum < "$inst")"
}

@test "--self-update refuses a bad checksum, a missing checksum and a non-bundle" {
  local repo="$BATS_TEST_TMPDIR/repo" inst="$BATS_TEST_TMPDIR/inst/system-update" before d
  d="$repo/releases/latest/download"
  mkdir -p "$(dirname "$inst")"
  cp "$BUNDLE" "$inst"
  before=$(sha256sum < "$inst")

  release "$repo" abc1234
  echo "# tampered" >> "$d/system-update"
  SYSTEM_UPDATE_ALLOW_FILE_SOURCE=1 run "$inst" --self-update --source "file://$repo" --no-color
  assert_equal 1 "$status"
  assert_contains "$output" "checksum"

  release "$repo" abc1234
  rm "$d/system-update.sha256"
  SYSTEM_UPDATE_ALLOW_FILE_SOURCE=1 run "$inst" --self-update --source "file://$repo" --no-color
  assert_equal 1 "$status"
  assert_contains "$output" "refusing an unverified update"

  printf '#!/usr/bin/env bash\necho hi\n' > "$d/system-update"
  (cd "$d" && sha256sum system-update > system-update.sha256)
  SYSTEM_UPDATE_ALLOW_FILE_SOURCE=1 run "$inst" --self-update --source "file://$repo" --no-color
  assert_equal 1 "$status"
  assert_contains "$output" "not a single-file build"

  assert_equal "$before" "$(sha256sum < "$inst")"
}

@test "--install-user copies the single file to ~/.local/bin with its completion" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home"
  HOME="$home" XDG_DATA_HOME= PATH="/usr/bin:/bin" run "$BUNDLE" --install-user --no-color --no-log
  assert_equal 0 "$status"
  [ -x "$home/.local/bin/system-update" ]
  cmp -s "$BUNDLE" "$home/.local/bin/system-update"
  grep -q '_system_update' "$home/.local/share/bash-completion/completions/system-update"
  assert_contains "$output" "is not on your PATH"
  # The installed copy knows it is installed.
  HOME="$home" PATH="$home/.local/bin:/usr/bin:/bin" run "$home/.local/bin/system-update" --install-user --no-color --no-log
  assert_equal 0 "$status"
  assert_contains "$output" "already installed"
  assert_not_contains "$output" "not on your PATH"
}

@test "--install puts it under the system prefix and replaces an older single file" {
  local prefix="$BATS_TEST_TMPDIR/usr-local"
  mkdir -p "$prefix/bin"
  sed "s/^SU_BUNDLE_COMMIT=.*/SU_BUNDLE_COMMIT='old1234'/" "$BUNDLE" > "$prefix/bin/system-update"
  SU_INSTALL_ROOT="$prefix" run "$BUNDLE" --install --no-color --no-log
  assert_equal 0 "$status"
  cmp -s "$BUNDLE" "$prefix/bin/system-update"
  [ -f "$prefix/share/bash-completion/completions/system-update" ]
  [ -z "$(find "$prefix/bin" -name '*.new.*')" ]
}

@test "--install refuses to overwrite something that is not system-update, and a checkout's link" {
  local prefix="$BATS_TEST_TMPDIR/usr-local"
  mkdir -p "$prefix/bin"
  echo '#!/bin/sh' > "$prefix/bin/system-update"
  SU_INSTALL_ROOT="$prefix" run "$BUNDLE" --install --no-color --no-log
  assert_equal 1 "$status"
  assert_contains "$output" "not a single-file build"
  assert_equal '#!/bin/sh' "$(cat "$prefix/bin/system-update")"
  rm "$prefix/bin/system-update"
  ln -s "$REPO_ROOT/bin/system-update" "$prefix/bin/system-update"
  SU_INSTALL_ROOT="$prefix" run "$BUNDLE" --install --no-color --no-log
  assert_equal 1 "$status"
  assert_contains "$output" "installation from a checkout"
  [ -L "$prefix/bin/system-update" ]
}

@test "--install --dry-run changes nothing" {
  local prefix="$BATS_TEST_TMPDIR/usr-local"
  SU_INSTALL_ROOT="$prefix" run "$BUNDLE" --install --dry-run --no-color --no-log
  assert_equal 0 "$status"
  assert_contains "$output" "would install"
  [ ! -e "$prefix" ]
}

@test "from a checkout, --install-user hands over to install.sh --user" {
  run "$REPO_ROOT/system-update" --install-user --dry-run --no-color --no-log
  assert_equal 0 "$status"
  assert_contains "$output" "would run: $REPO_ROOT/install.sh --user"
}
