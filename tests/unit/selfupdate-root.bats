#!/usr/bin/env bats
# A tool's own updater (copilot update, ...) writes a temp folder next to
# the binary, so a binary in a root-owned /usr/local/bin is updated as root
# (with root's HOME), as the user only when the user can write both the
# binary and its directory, and skipped when neither works. Lando, which
# refuses root, always stays with the user.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  bindir="$BATS_TEST_TMPDIR/usr-local-bin"; mkdir -p "$bindir"
  export PATH="$bindir:$PATH"
  export SU_PROBE_TIMEOUT=5 SU_TIMEOUT=20
  SU_PKG=apt; SU_DRY_RUN=0; STEP_RESULT=""; STEP_NOTE=""
  RAN="$BATS_TEST_TMPDIR/ran"; : > "$RAN"
  ver="$BATS_TEST_TMPDIR/ver"; echo 1.0.105 > "$ver"
  make_fake_bin "$bindir" copilot "case \"\$1\" in
  --version) echo \"GitHub Copilot CLI \$(cat '$ver').\" ;;
  update) echo 1.0.106 > '$ver' ;;
esac"
  make_fake_bin "$bindir" lando "case \"\$1\" in
  version) echo \"v\$(cat '$ver')\" ;;
  update) echo 1.0.106 > '$ver' ;;
esac"
  tools_discover
  NOT_WRITABLE=""
  distro_pkg_owner() { return 1; }
  user_can_write() { case " $NOT_WRITABLE " in *" $1 "*) return 1 ;; esac; return 0; }
  sudo_available() { return 0; }
  do_user() { echo "user $*" >> "$RAN"; "$@"; }
  do_root() { echo "root $*" >> "$RAN"; "$@"; }
}

@test "copilot in a directory the user can write: updated as the user" {
  tool_copilot_update
  assert_equal updated "$STEP_RESULT"
  assert_equal "1.0.105 -> 1.0.106" "$STEP_NOTE"
  assert_equal "user copilot update" "$(cat "$RAN")"
}

@test "copilot in a root-owned /usr/local/bin: updated as root with root's HOME (Ed's EACCES)" {
  NOT_WRITABLE="$bindir"
  tool_copilot_update
  assert_equal updated "$STEP_RESULT"
  assert_equal "1.0.105 -> 1.0.106" "$STEP_NOTE"
  assert_equal "root env HOME=/root copilot update" "$(cat "$RAN")"
}

@test "copilot binary itself not the user's: updated as root" {
  NOT_WRITABLE="$bindir/copilot"
  tool_copilot_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$(cat "$RAN")" "root env HOME=/root copilot update"
}

@test "no sudo and the directory is root's: skipped with the directory named" {
  NOT_WRITABLE="$bindir"
  sudo_available() { return 1; }
  tool_copilot_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "$bindir is not writable by $SU_USER and sudo is unavailable"
  assert_equal "" "$(cat "$RAN")"
  assert_equal 1.0.105 "$(cat "$ver")"
}

@test "lando refuses root: its updater stays with the user even in a root-owned directory" {
  NOT_WRITABLE="$bindir"
  tool_lando_update
  assert_equal "user lando update -y" "$(cat "$RAN")"
}

@test "go toolchain: root when the user can't write its parent directory" {
  SU_GO_ROOT="$BATS_TEST_TMPDIR/usr-local/go"
  NOT_WRITABLE="$BATS_TEST_TMPDIR/usr-local"
  go_priv true
  assert_equal "root true" "$(cat "$RAN")"
  : > "$RAN"; NOT_WRITABLE=""
  go_priv true
  assert_equal "user true" "$(cat "$RAN")"
}
