#!/usr/bin/env bats
# Tool identification guard: kilo editor vs Kilo Code, npm/uv/pipx layouts,
# distro-owned binaries, dry run.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  bindir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bindir"
  export PATH="$bindir:$PATH"
  export SU_PROBE_TIMEOUT=2
  export SU_TIMEOUT=10
  SU_PKG=apt
  SU_DRY_RUN=0
  STEP_RESULT=""; STEP_NOTE=""
}

@test "a hanging kilo (antirez editor) is skipped, not run" {
  make_fake_bin "$bindir" kilo 'while :; do sleep 1; done'
  tools_discover
  assert_equal "$bindir/kilo" "${SU_TOOL_BIN[kilo]}"
  local start end
  start=$(date +%s)
  tool_kilo_update
  end=$(date +%s)
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "did not answer"
  [ $((end - start)) -lt 10 ]
}

@test "a kilo that prints an editor usage line is skipped" {
  make_fake_bin "$bindir" kilo 'echo "Usage: kilo <filename>" >&2; exit 1'
  tools_discover
  tool_kilo_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "does not look like kilo"
}

@test "Kilo Code is identified by its version output and upgraded" {
  local verfile="$BATS_TEST_TMPDIR/version"
  echo 4.2.1 > "$verfile"
  make_fake_bin "$bindir" kilo "case \"\$1\" in --version) cat '$verfile';; upgrade) echo 4.3.0 > '$verfile'; touch '$BATS_TEST_TMPDIR/upgraded';; esac"
  tools_discover
  tool_kilo_update
  assert_equal updated "$STEP_RESULT"
  assert_equal "4.2.1 -> 4.3.0" "$STEP_NOTE"
  [ -e "$BATS_TEST_TMPDIR/upgraded" ]
}

@test "already current Kilo Code is ok" {
  make_fake_bin "$bindir" kilo 'case "$1" in --version) echo 4.3.0;; upgrade) echo "already up to date";; esac'
  tools_discover
  tool_kilo_update
  assert_equal ok "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "4.3.0"
}

@test "dry run probes but never runs the upgrade" {
  make_fake_bin "$bindir" kilo "case \"\$1\" in --version) echo 4.2.1;; upgrade) touch '$BATS_TEST_TMPDIR/upgraded';; esac"
  tools_discover
  SU_DRY_RUN=1
  tool_kilo_update
  assert_equal dry-run "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "kilo upgrade"
  [ ! -e "$BATS_TEST_TMPDIR/upgraded" ]
}

@test "the upgrade runs with stdin from /dev/null and a timeout" {
  make_fake_bin "$bindir" kilo 'case "$1" in --version) echo 4.2.1;; upgrade) read -r line && echo "got input" >&2; sleep 30;; esac'
  tools_discover
  SU_TIMEOUT=2
  local start end
  start=$(date +%s)
  tool_kilo_update
  end=$(date +%s)
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "timed out"
  [ $((end - start)) -lt 20 ]
}

@test "npm-installed Kilo Code is updated through npm without probing" {
  local prefix="$BATS_TEST_TMPDIR/prefix"
  mkdir -p "$prefix/lib/node_modules/@kilocode/cli/bin"
  printf '#!/usr/bin/env bash\nwhile :; do sleep 1; done\n' > "$prefix/lib/node_modules/@kilocode/cli/bin/kilo"
  chmod +x "$prefix/lib/node_modules/@kilocode/cli/bin/kilo"
  ln -s "$prefix/lib/node_modules/@kilocode/cli/bin/kilo" "$bindir/kilo"
  make_fake_bin "$bindir" npm "echo \"\$@\" >> '$BATS_TEST_TMPDIR/npm.log'"
  tools_discover
  assert_equal "npm:@kilocode/cli" "$(install_method "$bindir/kilo")"
  tool_kilo_update
  assert_equal ok "$STEP_RESULT"
  grep -q 'install -g @kilocode/cli@latest' "$BATS_TEST_TMPDIR/npm.log"
}

@test "an npm package with another name is not touched" {
  local prefix="$BATS_TEST_TMPDIR/prefix"
  mkdir -p "$prefix/lib/node_modules/kilo-editor/bin"
  printf '#!/usr/bin/env bash\necho 1.0.0\n' > "$prefix/lib/node_modules/kilo-editor/bin/kilo"
  chmod +x "$prefix/lib/node_modules/kilo-editor/bin/kilo"
  ln -s "$prefix/lib/node_modules/kilo-editor/bin/kilo" "$bindir/kilo"
  make_fake_bin "$bindir" npm "touch '$BATS_TEST_TMPDIR/npm-ran'"
  tools_discover
  tool_kilo_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "kilo-editor"
  [ ! -e "$BATS_TEST_TMPDIR/npm-ran" ]
}

@test "a binary owned by a distro package is left to the package manager" {
  make_fake_bin "$bindir" kilo 'echo 4.2.1'
  make_fake_bin "$bindir" dpkg 'if [ "$1" = -S ]; then echo "kilo: $2"; fi'
  tools_discover
  assert_equal "distro:kilo" "$(install_method "$bindir/kilo")"
  tool_kilo_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "apt package 'kilo'"
}

@test "install_method recognises uv, pipx, bun, pnpm and cargo layouts" {
  local h="$BATS_TEST_TMPDIR/home"
  mkdir -p "$h/.local/share/uv/tools/hermes-agent/bin" "$h/.local/pipx/venvs/zcmds/bin" \
           "$h/.bun/install/global/node_modules/@scope/pkg/bin" "$h/.local/share/pnpm/global/5/node_modules/qwen/bin" "$h/.cargo/bin"
  touch "$h/.local/share/uv/tools/hermes-agent/bin/hermes" "$h/.local/pipx/venvs/zcmds/bin/zcmds" \
        "$h/.bun/install/global/node_modules/@scope/pkg/bin/x" "$h/.local/share/pnpm/global/5/node_modules/qwen/bin/qwen" "$h/.cargo/bin/rg"
  assert_equal "uv:hermes-agent" "$(install_method "$h/.local/share/uv/tools/hermes-agent/bin/hermes")"
  assert_equal "pipx:zcmds" "$(install_method "$h/.local/pipx/venvs/zcmds/bin/zcmds")"
  assert_equal "bun:@scope/pkg" "$(install_method "$h/.bun/install/global/node_modules/@scope/pkg/bin/x")"
  assert_equal "pnpm:qwen" "$(install_method "$h/.local/share/pnpm/global/5/node_modules/qwen/bin/qwen")"
  assert_equal "cargo" "$(install_method "$h/.cargo/bin/rg")"
}

@test "Debian's pi (digits of pi) is not mistaken for the pi agent" {
  make_fake_bin "$bindir" pi 'echo 3.14159265358979323846'
  tools_discover
  tool_pi_update
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "does not look like pi"
}

@test "grok pattern tool is not mistaken for the grok agent" {
  make_fake_bin "$bindir" grok 'echo "grok: unknown option --version"; exit 2'
  tools_discover
  tool_grok_update
  assert_equal skipped "$STEP_RESULT"
}

@test "claude is identified by the Claude Code banner" {
  make_fake_bin "$bindir" claude 'case "$1" in --version) echo "2.0.5 (Claude Code)";; update) echo "already current";; esac'
  tools_discover
  tool_claude_update
  assert_equal ok "$STEP_RESULT"
}

@test "version_from_text picks the first version" {
  assert_equal 2.0.5 "$(version_from_text "2.0.5 (Claude Code)")"
  assert_equal 0.3.12 "$(version_from_text $'Warning: could not connect\nollama version is 0.3.12')"
  assert_equal 1.95.3.24321 "$(version_from_text "1.95.3.24321")"
  assert_equal "" "$(version_from_text "no numbers here")"
}

@test "version_lt" {
  version_lt 1.2.3 1.10.0
  version_lt v2.29.1 v2.30.0
  ! version_lt 2.30.0 2.29.1
  ! version_lt 1.0.0 1.0.0
  version_lt 1.95.3.24321 1.96.0.25001
}
