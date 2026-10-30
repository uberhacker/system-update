# Claude Code (`claude`)

Anthropic's coding agent CLI, installed with the native installer (`~/.local/bin/claude`) or as the npm package `@anthropic-ai/claude-code`.

| | |
| --- | --- |
| Step name | `claude` (for `--only` / `--skip`) |
| Runs as | the invoking user (`SUDO_USER` under `sudo`) |
| Detected when | `claude` is on the user's `PATH` |
| Expected package | `@anthropic-ai/claude-code` |
| Update command | `claude update` |
| Settings | `TIMEOUT`, `PROBE_TIMEOUT` |

## What it does

1. **Identify the binary.** The real path behind `claude` decides how it was installed:
   * inside an npm, pnpm or bun global `node_modules`, or a `uv tool` / `pipx` venv: the package must be `@anthropic-ai/claude-code`, otherwise the step is skipped;
   * owned by a distro package: skipped, the system package step updates it;
   * under `~/.cargo/bin` or Homebrew: skipped here, because the [cargo](cargo.md) or [brew](brew.md) step updates it.
2. **Probe it.** `claude --version` runs with stdin closed, `TERM=dumb`, and a `PROBE_TIMEOUT` (20 s) limit. The output must contain a version followed by `Claude Code`, e.g. `2.1.314 (Claude Code)`; anything else is skipped as a different program.
3. **Update it** through the package manager that installed it:

   | Installed with | Command run |
   | --- | --- |
   | npm | `npm install -g <package>@latest` |
   | pnpm | `pnpm add -g <package>@latest` |
   | bun | `bun install -g <package>@latest` |
   | uv | `uv tool upgrade <package>` |
   | pipx | `pipx upgrade <package>` |
   | anything else | `claude update` |

4. **Compare.** The probe runs again; the summary shows `old -> new`, or `up to date (X)`.

Every command runs with stdin closed and is killed after `TIMEOUT` seconds (300 by default).

## What will be affected

* The `claude` installation only: the global npm/pnpm/bun package, the `uv`/`pipx` venv, or whatever the tool's own updater replaces (usually the binary under `~/.local/bin` or `~/.local/share`).
* Files belong to the invoking user. Nothing is run as root and no system directory is touched.
* Configuration, credentials and history of the tool are left alone by this script (the tool's own updater may migrate them).

## Dry run and `--detailed`

`--dry-run` identifies and probes the binary, then reports `would update via npm (@pkg)` or `would run 'claude update'` with the installed version. Nothing is installed.

`--detailed` also asks the npm registry for the newest version of `@anthropic-ai/claude-code` (`npm view @anthropic-ai/claude-code version`, read-only), even when the tool was installed with its own installer, and reports `up to date (X)` or `installed -> latest`.

## Warnings

* `claude update` follows the release channel configured in Claude Code; `--detailed` compares against the `latest` tag on npm, which can be ahead of the `stable` channel. The dry run may therefore say an update exists that `claude update` will not install yet.
* Running sessions keep the old version until they are restarted.
* The update replaces the tool in place. Close running sessions of it first if it holds files open.
* To leave it alone: `--skip claude`, or `SKIP=claude` in the config file.

## Skipped when

* `claude` is not on `PATH`.
* The binary belongs to a distro package, Homebrew or cargo (see above).
* The probe times out or its output does not look like Claude Code.
* No update method applies.

See also: [identification guard](../README.md#identification-guard), [configuration](../README.md#configuration).
