#!/usr/bin/env bats
# Self-update: git checkout against a local bare repository, dirty tree
# refusal, non-https refusal, remote default branch, tarball mode.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  export SYSTEM_UPDATE_ALLOW_FILE_SOURCE=1
  export SU_SYSTEM_CONFIG=/nonexistent
  export SU_CONFIG_FILE="$BATS_TEST_TMPDIR/empty.conf"; : > "$SU_CONFIG_FILE"
  export SU_PKG_FALLBACK=0
  export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
  export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  T="$BATS_TEST_TMPDIR"
  REMOTE="$T/remote.git"
  SRC="file://$REMOTE"

  # A bare "GitHub" with one commit at version 2.0.0, default branch master.
  git init --quiet --bare --initial-branch=master "$REMOTE"
  mkdir -p "$T/work"
  cp -a "$REPO_ROOT/bin" "$REPO_ROOT/lib" "$REPO_ROOT/VERSION" "$T/work/"
  git -C "$T/work" init --quiet --initial-branch=master
  git -C "$T/work" add -A
  git -C "$T/work" commit --quiet -m "v2.0.0"
  git -C "$T/work" remote add origin "$SRC"
  git -C "$T/work" push --quiet origin master
  # The installation under test: a clone of the remote.
  git clone --quiet "$SRC" "$T/install"
  INSTALL="$T/install/bin/system-update"
  # A newer commit upstream.
  echo 9.9.9 > "$T/work/VERSION"
  git -C "$T/work" commit --quiet -am "v9.9.9"
  git -C "$T/work" push --quiet origin master
}

@test "git checkout fast-forwards to the new version" {
  run "$INSTALL" --self-update --source "$SRC"
  assert_equal 0 "$status"
  assert_contains "$output" "updated 2.0.0"
  assert_contains "$output" "9.9.9"
  assert_equal 9.9.9 "$(cat "$T/install/VERSION")"
}

@test "already up to date" {
  "$INSTALL" --self-update --source "$SRC" >/dev/null
  run "$INSTALL" --self-update --source "$SRC"
  assert_equal 0 "$status"
  assert_contains "$output" "already up to date"
}

@test "dry run fetches but changes nothing" {
  run "$INSTALL" --self-update --dry-run --source "$SRC"
  assert_equal 0 "$status"
  assert_contains "$output" "would fast-forward"
  assert_equal 2.0.0 "$(cat "$T/install/VERSION")"
}

@test "a dirty tree is refused" {
  echo "# local change" >> "$T/install/lib/core/log.sh"
  run "$INSTALL" --self-update --source "$SRC"
  assert_equal 1 "$status"
  assert_contains "$output" "local changes"
  assert_equal 2.0.0 "$(cat "$T/install/VERSION")"
  grep -q "local change" "$T/install/lib/core/log.sh"
}

@test "non-https sources are refused" {
  run "$INSTALL" --self-update --source "http://example.com/system-update"
  assert_equal 2 "$status"
  assert_contains "$output" "invalid value for SELF_UPDATE_REPO"
  run "$INSTALL" --self-update --source "git@github.com:bradvrudney/system-update.git"
  assert_equal 2 "$status"
  SYSTEM_UPDATE_ALLOW_FILE_SOURCE=0 run "$INSTALL" --self-update --source "$SRC"
  assert_equal 2 "$status"
  assert_equal 2.0.0 "$(cat "$T/install/VERSION")"
}

@test "the default source is the bradvrudney fork over https" {
  assert_equal "https://github.com/bradvrudney/system-update" "$SU_DEFAULT_REPO"
}

@test "origin mismatch is refused unless --source re-points it" {
  git init --quiet --bare --initial-branch=master "$T/other.git"
  SELF_UPDATE_REPO="file://$T/other.git" run "$INSTALL" --self-update
  assert_equal 1 "$status"
  assert_contains "$output" "does not match"
  assert_equal 2.0.0 "$(cat "$T/install/VERSION")"
  # With --source the remote is re-pointed and the update proceeds.
  git -C "$T/install" remote set-url origin "file://$T/other.git"
  run "$INSTALL" --self-update --source "$SRC"
  assert_equal 0 "$status"
  assert_equal "$SRC" "$(git -C "$T/install" remote get-url origin)"
  assert_equal 9.9.9 "$(cat "$T/install/VERSION")"
}

@test "remote default branch is read with ls-remote --symref, falling back to master" {
  assert_equal master "$(selfupdate_remote_default_branch "$SRC")"
  git -C "$T/work" branch --quiet trunk
  git -C "$T/work" push --quiet origin trunk
  git -C "$REMOTE" symbolic-ref HEAD refs/heads/trunk
  assert_equal trunk "$(selfupdate_remote_default_branch "$SRC")"
  run selfupdate_remote_default_branch "file://$T/does-not-exist.git"
  assert_equal 1 "$status"
  assert_equal master "$SU_SELF_UPDATE_FALLBACK_BRANCH"
}

@test "a detached checkout follows the remote default branch" {
  git -C "$T/work" checkout --quiet -b trunk
  echo 7.7.7 > "$T/work/VERSION"
  git -C "$T/work" commit --quiet -am "v7.7.7 on trunk"
  git -C "$T/work" push --quiet origin trunk
  git -C "$REMOTE" symbolic-ref HEAD refs/heads/trunk
  git -C "$T/install" checkout --quiet --detach
  run "$INSTALL" --self-update --source "$SRC"
  assert_equal 0 "$status"
  assert_contains "$output" "branch trunk"
  assert_equal 7.7.7 "$(cat "$T/install/VERSION")"
  assert_equal trunk "$(git -C "$T/install" symbolic-ref --short HEAD)"
}

@test "a checkout on a branch the remote has stays on it" {
  git -C "$REMOTE" symbolic-ref HEAD refs/heads/trunk
  run "$INSTALL" --self-update --source "$SRC"
  assert_equal 0 "$status"
  assert_contains "$output" "branch master"
  assert_equal 9.9.9 "$(cat "$T/install/VERSION")"
}

@test "--branch selects an explicit branch" {
  git -C "$T/work" checkout --quiet -b feature
  echo 5.5.5 > "$T/work/VERSION"
  git -C "$T/work" commit --quiet -am "v5.5.5"
  git -C "$T/work" push --quiet origin feature
  run "$INSTALL" --self-update --source "$SRC" --branch feature
  assert_equal 0 "$status"
  assert_equal 5.5.5 "$(cat "$T/install/VERSION")"
  assert_equal feature "$(git -C "$T/install" symbolic-ref --short HEAD)"
}

@test "SELF_UPDATE_BRANCH with path tricks is refused" {
  run "$INSTALL" --self-update --source "$SRC" --branch "../../evil"
  assert_equal 2 "$status"
}

make_tarball_remote() {
  # $1 = dir to serve, $2 = version inside the tarball, $3 = optional "broken"
  local serve="$1" ver="$2" tree="$BATS_TEST_TMPDIR/tree/system-update-master"
  rm -rf "$BATS_TEST_TMPDIR/tree"
  mkdir -p "$tree" "$serve/archive/refs/heads"
  cp -a "$REPO_ROOT/bin" "$REPO_ROOT/lib" "$tree/"
  echo "$ver" > "$tree/VERSION"
  if [ "${3:-}" = broken ]; then
    printf 'if then fi (((\n' >> "$tree/lib/core/log.sh"
  fi
  tar -czf "$serve/archive/refs/heads/master.tar.gz" -C "$BATS_TEST_TMPDIR/tree" system-update-master
}

@test "tarball mode replaces a plain (non-git) installation atomically" {
  rm -rf "$T/install/.git"
  make_tarball_remote "$T/tb" 9.9.9
  run "$INSTALL" --self-update --source "file://$T/tb" --branch master
  assert_equal 0 "$status"
  assert_contains "$output" "updated 2.0.0 -> 9.9.9"
  assert_equal 9.9.9 "$(cat "$T/install/VERSION")"
  [ -x "$T/install/bin/system-update" ]
  [ -f "$T/install/lib/core/log.sh" ]
  [ ! -e "$T/install.old" ]
  run "$INSTALL" --version
  assert_contains "$output" "system-update 9.9.9"
}

@test "tarball mode without a branch falls back to master when the remote has no git" {
  rm -rf "$T/install/.git"
  make_tarball_remote "$T/tb" 9.9.9
  run "$INSTALL" --self-update --source "file://$T/tb"
  assert_equal 0 "$status"
  assert_equal 9.9.9 "$(cat "$T/install/VERSION")"
}

@test "tarball mode refuses a tree that does not parse" {
  rm -rf "$T/install/.git"
  make_tarball_remote "$T/tb" 9.9.9 broken
  run "$INSTALL" --self-update --source "file://$T/tb" --branch master
  assert_equal 1 "$status"
  assert_contains "$output" "does not parse"
  assert_equal 2.0.0 "$(cat "$T/install/VERSION")"
}

@test "tarball dry run downloads and checks but does not swap" {
  rm -rf "$T/install/.git"
  make_tarball_remote "$T/tb" 9.9.9
  run "$INSTALL" --self-update --dry-run --source "file://$T/tb" --branch master
  assert_equal 0 "$status"
  assert_contains "$output" "would replace"
  assert_equal 2.0.0 "$(cat "$T/install/VERSION")"
}
