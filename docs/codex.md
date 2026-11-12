# OpenAI Codex CLI (`codex`)

OpenAI's coding agent CLI, normally the npm package `@openai/codex`.

| | |
| --- | --- |
| Step name | `codex` (for `--only` / `--skip`) |
| Runs as | the invoking user (`SUDO_USER` under `sudo`); its own updater as root when the binary's directory is not the user's to write |
| Detected when | `codex` is on the user's `PATH` |
| Expected package | `@openai/codex` |
| Update command | `codex update` |
| Settings | `TIMEOUT`, `TOOL_TIMEOUT`, `PROBE_TIMEOUT` |

## What it does

1. **Identify the binary.** The real path behind `codex` decides how it was installed:
   * inside an npm, pnpm or bun global `node_modules`, or a `uv tool` / `pipx` venv: the package must be `@openai/codex`, otherwise the step is skipped;
   * owned by a distro package: skipped, the system package step updates it;
   * under `~/.cargo/bin` or Homebrew: skipped here, because the [cargo](cargo.md) or [brew](brew.md) step updates it.
2. **Probe it.** `codex --version` runs with stdin closed, `TERM=dumb`, and a `PROBE_TIMEOUT` (20 s) limit. The output must contain `codex <version>` or `codex-cli <version>`; anything else is skipped as a different program.
3. **Update it** through the package manager that installed it:

   | Installed with | Command run |
   | --- | --- |
   | npm | `npm install -g <package>@latest` |
   | pnpm | `pnpm add -g <package>@latest` |
   | bun | `bun install -g <package>@latest` |
   | uv | `uv tool upgrade <package>` |
   | pipx | `pipx upgrade <package>` |
   | anything else | `codex update` |

4. **Compare.** The probe runs again; the summary shows `old -> new`, or `up to date (X)`.

Every command runs with stdin closed. The tool's own updater is killed after `TOOL_TIMEOUT` seconds (120 by default); a package manager update after `TIMEOUT` seconds (300 by default).

## What will be affected

* The `codex` installation only: the global npm/pnpm/bun package, the `uv`/`pipx` venv, or whatever the tool's own updater replaces (usually the binary under `~/.local/bin` or `~/.local/share`).
* Files belong to the invoking user. The one exception: when the tool updates itself and its binary sits in a directory the user can't write (for example a root-owned `/usr/local/bin`, where its installer puts it under `sudo`), the updater has to create files next to the binary, so it runs as root through `sudo`, with `HOME=/root` so nothing root-owned lands in the user's home. The directory's ownership is never changed.
* Configuration, credentials and history of the tool are left alone by this script (the tool's own updater may migrate them).

## Dry run and `--detailed`

`--dry-run` identifies and probes the binary, then reports `would update via npm (@pkg)` or `would run 'codex update'` with the installed version. Nothing is installed.

`--detailed` also asks the npm registry for the newest version of `@openai/codex` (`npm view @openai/codex version`, read-only), even when the tool was installed with its own installer, and reports `up to date (X)` or `installed -> latest`.

## Warnings

* `codex` is a generic name. A binary that is not the npm package and does not print `codex[-cli] X.Y` is skipped, never run with `update`.
* The update replaces the tool in place. Close running sessions of it first if it holds files open.
* To leave it alone: `--skip codex`, or `SKIP=codex` in the config file.

## Skipped when

* `codex` is not on `PATH`.
* The binary belongs to a distro package, Homebrew or cargo (see above).
* The probe times out or its output does not look like OpenAI Codex CLI.
* No update method applies.

See also: [identification guard](../README.md#identification-guard), [configuration](../README.md#configuration).
