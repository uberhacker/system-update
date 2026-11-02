# Contributing to system-update

Thanks for helping. Most contributions add support for one more tool, so
most of this page is about that. Other fixes are welcome too: open an issue
or a pull request and describe what you saw on which distro.

## Before you start

You need bash 4.4 or later, coreutils, `shellcheck` and `git`. Docker is
optional; you need it only for the container tests.

```
tests/lint.sh          # bash -n and shellcheck -x on every script
tests/run.sh           # bats unit tests (bats-core is fetched into tests/vendor)
tests/containers.sh    # real runs inside stock distro containers (needs docker)
./build.sh             # the single-file build, dist/system-update
```

CI runs all four on every push and pull request. Please run at least
`tests/lint.sh` and `tests/run.sh` before you open a pull request.

## Adding a tool

A tool is one module in `lib/tools/`, one page in `docs/` and one test file
in `tests/unit/`. Nothing else has to change. The module is found by its
file name, and tab completion, `--list`, `--only` and `--skip` pick the new
name up by themselves.

### 1. The module: `lib/tools/<name>.sh`

The file name is the step name. A dash in it becomes an underscore in the
function names, so `foo-cli.sh` defines `tool_foo_cli_detect`.

```bash
#!/usr/bin/env bash
# lib/tools/foo.sh - Foo CLI (self-update: foo upgrade).

tool_foo_detect() { user_bin foo; }

tool_foo_update() {
  tool_standard foo "${SU_TOOL_BIN[foo]}" '^foo [0-9]+\.[0-9]+' '@foo/cli' \
    --version -- foo upgrade
}
```

| Function | Required | What it does |
| --- | --- | --- |
| `tool_<name>_detect` | yes | Returns 0 and prints the binary's path when the tool is installed. It runs for every tool on every run, so it must be cheap and change nothing: look for a file, never run the tool. |
| `tool_<name>_update` | yes | The step itself. It reports exactly one result through `step_ok`, `step_updated`, `step_skip`, `step_dry`, `step_warn` or `step_fail`, then returns 0. |
| `tool_<name>_scope` | no | Prints `system` when the tool lives in a system directory such as `/usr/local/bin` and is updated as root. The default is `user`. |

Pick the helper that matches how the tool updates. They are all in
`lib/core/tools.sh`.

- `tool_standard NAME BIN REGEX EXPECT_PKGS PROBE_ARGS... -- UPDATE_CMD...`
  covers the usual case: a CLI that has its own update command, or that was
  installed with npm, pnpm, bun, uv or pipx. It identifies the binary (see
  the next section), updates it through the package manager that installed
  it, or else runs `UPDATE_CMD`, and compares versions before and after.
  `EXPECT_PKGS` is a comma separated list of package names the tool is
  published under (empty if none). See `lib/tools/kilo.sh`.
- `tool_github_binary_update NAME REPO ASSET DEST INSTALLED` covers a single
  binary published as a GitHub release asset. It installs the new version
  only when the release publishes a sha256 that matches. See
  `lib/tools/cloudflared.sh`.
- `tool_opt_in KEY FLAG` covers a step that should be off by default. Call
  it first and return when it fails. Add the key to `SU_CFG_DEFAULT` and
  `SU_CFG_TYPE` in `lib/core/config.sh`, and the flag to `lib/core/args.sh`.
- Anything else is written by hand. `lib/tools/devin.sh` checks a release
  manifest before it runs the tool's updater, and `lib/tools/anythingllm.sh`
  drives a vendor installer.

### 2. Identify before you run anything

Tool names collide. `kilo` is also antirez's text editor, which never exits
when you call it with `-v`. `pi` and `grok` are other programs on some
systems. So a module never trusts the name alone:

- `tool_identify` (which `tool_standard` calls) first looks at where the
  binary came from: an npm, bun, pnpm, uv or pipx layout, or a distro
  package. A distro-owned copy is skipped, because the system package step
  updates it.
- Only then does it run the `--version` probe, through `tool_probe`. That
  runs with stdin closed, `TERM=dumb`, `NO_COLOR=1`, `CI=1` and a
  `PROBE_TIMEOUT` limit (20 s). The output must match `REGEX`, or the step
  is skipped as a different program.

Make `REGEX` specific. A tool that prints `foo 1.2.3` deserves `'^foo [0-9]'`
rather than a bare version pattern.

### 3. Rules every module follows

- **Nothing is interactive.** Every command runs with stdin from `/dev/null`.
  A command that prompts gets end-of-file, and under `set -e` that usually
  means exit 1. Pass the tool's own non-interactive flag (`--yes`,
  `--non-interactive`, `-y`). If it has none, answer its questions from a
  file, as `anythingllm.sh` does, and say in a comment which question gets
  which answer.
- **Run commands through the runners** in `lib/core/util.sh`, never directly:
  - `do_user` / `do_root` for anything that changes something. In a dry run
    they only print what they would do.
  - `run_user` / `run_root` for read-only queries, which should also run in
    a dry run.

  User tools run as the invoking user (`SUDO_USER` under `sudo`), never as
  root, so files in their home keep the right owner.
- **Timeouts.** Every runner applies `TIMEOUT` (300 s). `tool_standard` gives
  a tool's own updater `TOOL_TIMEOUT` (120 s). Set `SU_RUN_TIMEOUT` for one
  call when a command legitimately needs longer, such as `SU_PKG_TIMEOUT`
  for a large download, or less, such as `SU_PROBE_TIMEOUT` for a lookup.
- **Dry run.** With `SU_DRY_RUN=1` the step changes nothing and reports
  `step_dry "would ..."`. If you can find the latest version cheaply, say
  `OLD -> NEW`. For `--detailed`, see `detail_show` in
  `lib/core/runner.sh`.
- **Downloads** go through `download`, which allows https only, and are
  checked with `verify_sha256` against a checksum the project publishes. An
  installer that can't be verified (`curl | bash`) runs only when the user
  passes `--allow-unverified-installers`; check
  `cfg_bool ALLOW_UNVERIFIED_INSTALLERS`.
- **Skip, don't fail,** when the tool is fine but this run can't help: it is
  owned by another package manager, the file isn't writable, the latest
  version is unknown. Use `step_fail` only when an update was attempted and
  went wrong. The note should tell the user what to do next.
- **Style.** Two-space indent, `local` for every variable, quote everything,
  and `shellcheck` clean (`tests/lint.sh`). Begin the file with a comment
  that says what the tool is and anything surprising about it.

### 4. The documentation page: `docs/<name>.md`

Copy a page for a tool that updates the same way (`docs/kilo.md` for a CLI
with a self-update command, `docs/cloudflared.md` for a release binary) and
keep its sections: the summary table, What it does, What will be affected,
Dry run and `--detailed`, Warnings and Skipped when. Then add the tool to
the table under "Third-party tools" in `README.md`.

### 5. The tests: `tests/unit/<name>.bats`

The unit tests source the modules and call the update function against a
fake binary on a private `PATH`. Nothing real is installed and the network
is never used.

```bash
#!/usr/bin/env bats
load ../test_helper

setup() {
  SU_OUT=1
  load_su
  bindir="$BATS_TEST_TMPDIR/bin"
  export PATH="$bindir:$PATH"
  SU_DRY_RUN=0
  STEP_RESULT=""; STEP_NOTE=""
}

@test "foo is updated with foo upgrade" {
  make_fake_bin "$bindir" foo 'case "$1" in
    --version) cat "$BATS_TEST_TMPDIR/v" 2>/dev/null || echo "foo 1.0.0" ;;
    upgrade) echo "foo 1.1.0" > "$BATS_TEST_TMPDIR/v" ;;
  esac'
  tools_discover
  tool_foo_update
  assert_equal updated "$STEP_RESULT"
  assert_equal "1.0.0 -> 1.1.0" "$STEP_NOTE"
}
```

Cover at least these cases: an update, already up to date, a dry run that
changes nothing, a failing update command, and a binary with the same name
that is a different program. For downloads, `gh_stub_init` routes `curl`
through `tests/stubs/curl`, which serves files from a directory in the test.
`tests/unit/cloudflared.bats` and `tests/unit/anythingllm.bats` show how.

## Pull requests

- One tool or one fix per pull request is easiest to review.
- Say which distros you ran it on, and paste the output of
  `system-update --only <name> --dry-run` and of a real run.
- Don't bump `VERSION`; that happens when a release is tagged.
