#!/usr/bin/env bats
# ollama: `ollama -v` reports the running server first and the binary on
# disk as "client version"; without systemd the installer cannot restart an
# old server. The step must read the client, not call an unchanged version
# "updated", and restart or report a stale server.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  bindir="$BATS_TEST_TMPDIR/bin"; mkdir -p "$bindir"
  state="$BATS_TEST_TMPDIR/state"; mkdir -p "$state"
  # The fake ollama prints what a real one does for the server and client
  # versions held in $state/server and $state/client.
  make_fake_bin "$bindir" ollama "s=\$(cat '$state/server' 2>/dev/null); c=\$(cat '$state/client')
if [ -z \"\$s\" ]; then echo 'Warning: could not connect to a running Ollama instance'; echo \"Warning: client version is \$c\"
elif [ \"\$s\" = \"\$c\" ]; then echo \"ollama version is \$s\"
else echo \"ollama version is \$s\"; echo \"Warning: client version is \$c\"; fi"
  SU_TOOL_BIN[ollama]="$bindir/ollama"
  SU_PKG=apt; SU_DRY_RUN=0; STEP_RESULT=""; STEP_NOTE=""
  cfg_bool() { [ "$1" = ALLOW_UNVERIFIED_INSTALLERS ]; }
  RAN="$BATS_TEST_TMPDIR/ran"; : > "$RAN"
  distro_pkg_owner() { return 1; }
  sudo_available() { return 0; }
  gh_latest_version() { echo 0.40.14; }
  download() { echo 'true' > "$2"; }
  systemd_running() { return 1; }
  OLLAMA_INITD="$BATS_TEST_TMPDIR/no-initd"
  # The installer replaces the binary on disk (client) only; INSTALL_NOOP
  # makes it change nothing.
  do_root() {
    echo "root $*" >> "$RAN"
    case "$1" in
      sh) [ -n "${INSTALL_NOOP:-}" ] || echo 0.40.14 > "$state/client" ;;
      "$OLLAMA_INITD") cat "$state/client" > "$state/server" ;;
    esac
  }
}

@test "versions: client and server read apart" {
  ollama_versions "$(printf 'ollama version is 0.40.13\nWarning: client version is 0.40.14\n')"
  assert_equal 0.40.14 "$OLLAMA_CLIENT"
  assert_equal 0.40.13 "$OLLAMA_SERVER"
  ollama_versions "$(printf 'Warning: could not connect to a running Ollama instance\nWarning: client version is 0.40.14\n')"
  assert_equal 0.40.14 "$OLLAMA_CLIENT"
  assert_equal "" "$OLLAMA_SERVER"
  ollama_versions "ollama version is 0.40.14"
  assert_equal 0.40.14 "$OLLAMA_CLIENT"
  assert_equal 0.40.14 "$OLLAMA_SERVER"
}

@test "no systemd, old server keeps running: warns instead of a silent 'updated'" {
  echo 0.40.13 > "$state/server"; echo 0.40.13 > "$state/client"
  tool_ollama_update
  assert_equal warn "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "0.40.13 -> 0.40.14"
  assert_contains "$STEP_NOTE" "the running ollama server is still 0.40.13; restart it"
}

@test "second run with the new binary on disk: up to date, installer not rerun (Ed's repeat run)" {
  echo 0.40.13 > "$state/server"; echo 0.40.14 > "$state/client"
  tool_ollama_update
  assert_equal warn "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "up to date (0.40.14), but the running ollama server is still 0.40.13"
  assert_not_contains "$(cat "$RAN")" "root sh"
}

@test "installer that changes nothing: failed, not 'updated X -> X'" {
  echo 0.40.13 > "$state/server"; echo 0.40.13 > "$state/client"
  INSTALL_NOOP=1
  tool_ollama_update
  assert_equal failed "$STEP_RESULT"
  assert_equal "the installer finished but ollama is still 0.40.13" "$STEP_NOTE"
}

@test "no systemd but an init script: the server is restarted through it" {
  make_fake_bin "$BATS_TEST_TMPDIR" initd 'exit 0'
  OLLAMA_INITD="$BATS_TEST_TMPDIR/initd"
  echo 0.40.13 > "$state/server"; echo 0.40.13 > "$state/client"
  tool_ollama_update
  assert_equal updated "$STEP_RESULT"
  assert_equal "0.40.13 -> 0.40.14" "$STEP_NOTE"
  assert_contains "$(cat "$RAN")" "root $OLLAMA_INITD restart"
}

@test "no server running: updated" {
  echo 0.40.13 > "$state/client"
  tool_ollama_update
  assert_equal updated "$STEP_RESULT"
  assert_equal "0.40.13 -> 0.40.14" "$STEP_NOTE"
}

@test "with systemd the installer restarts the server: updated" {
  systemd_running() { return 0; }
  echo 0.40.13 > "$state/server"; echo 0.40.13 > "$state/client"
  do_root() { echo "root $*" >> "$RAN"; echo 0.40.14 > "$state/client"; echo 0.40.14 > "$state/server"; }
  tool_ollama_update
  assert_equal updated "$STEP_RESULT"
  assert_equal "0.40.13 -> 0.40.14" "$STEP_NOTE"
}

@test "up to date with matching server: ok" {
  echo 0.40.14 > "$state/server"; echo 0.40.14 > "$state/client"
  tool_ollama_update
  assert_equal ok "$STEP_RESULT"
  assert_equal "up to date (0.40.14)" "$STEP_NOTE"
}
