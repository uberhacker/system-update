# Devin CLI (`devin`)

The Devin CLI, updated with its own `devin update` command.

| | |
| --- | --- |
| Step name | `devin` (for `--only` / `--skip`) |
| Runs as | the invoking user (`SUDO_USER` under `sudo`); its own updater as root when the binary's directory is not the user's to write |
| Detected when | `devin` is on the user's `PATH` |
| Expected package | none (probe only) |
| Update command | `devin update`, only when the release manifest has a newer version |
| Settings | `TIMEOUT`, `TOOL_TIMEOUT`, `PROBE_TIMEOUT` |

## What it does

1. **Identify the binary.** The real path behind `devin` decides how it was installed:
   * inside an npm, pnpm or bun global `node_modules`, or a `uv tool` / `pipx` venv: that package manager is used;
   * owned by a distro package: skipped, the system package step updates it;
   * under `~/.cargo/bin` or Homebrew: skipped here, because the [cargo](cargo.md) or [brew](brew.md) step updates it.
2. **Probe it.** `devin --version` runs with stdin closed, `TERM=dumb`, and a `PROBE_TIMEOUT` (20 s) limit. The output must contain anything containing a version number (`X.Y`); anything else is skipped as a different program.
3. **Update it** through the package manager that installed it:

   | Installed with | Command run |
   | --- | --- |
   | npm | `npm install -g <package>@latest` |
   | pnpm | `pnpm add -g <package>@latest` |
   | bun | `bun install -g <package>@latest` |
   | uv | `uv tool upgrade <package>` |
   | pipx | `pipx upgrade <package>` |
   | anything else | `devin update` |

   Before `devin update`, the installed version is compared with the public release manifest the official installer uses (`https://static.devin.ai/cli/current/manifest.json`). When they match, the step reports `up to date` and `devin update` is not run at all: without a terminal it can sit until the timeout even when there is nothing to do. When the manifest can't be read, `devin update` runs as before.
4. **Compare.** The probe runs again; the summary shows `old -> new`, or `up to date (X)`.

Every command runs with stdin closed. The tool's own updater is killed after `TOOL_TIMEOUT` seconds (120 by default); a package manager update after `TIMEOUT` seconds (300 by default). When `devin update` is stopped by the timeout, the version is read again: if the new version is already in place the step reports it as updated (the updater only failed to exit); otherwise it fails and says to run `devin update` in a terminal to see what it is waiting for.

## What will be affected

* The `devin` installation only: the global npm/pnpm/bun package, the `uv`/`pipx` venv, or whatever the tool's own updater replaces (usually the binary under `~/.local/bin` or `~/.local/share`).
* Files belong to the invoking user. The one exception: when the tool updates itself and its binary sits in a directory the user can't write (for example a root-owned `/usr/local/bin`, where its installer puts it under `sudo`), the updater has to create files next to the binary, so it runs as root through `sudo`, with `HOME=/root` so nothing root-owned lands in the user's home. The directory's ownership is never changed.
* Configuration, credentials and history of the tool are left alone by this script (the tool's own updater may migrate them).

## Dry run and `--detailed`

`--dry-run` identifies and probes the binary, then reports `would update via npm (@pkg)` or `would run 'devin update'` with the installed version. Nothing is installed.

`--dry-run` and `--detailed` also read the release manifest, so they report `up to date (X)` or `would run 'devin update' (OLD -> NEW)`. For an npm or PyPI install, `--detailed` asks that registry instead.

## Warnings

* Identification rests on the `--version` probe alone (no package name to check). Use `--skip devin` if a different program owns that name on your system.
* The update replaces the tool in place. Close running sessions of it first if it holds files open.
* To leave it alone: `--skip devin`, or `SKIP=devin` in the config file.

## Skipped when

* `devin` is not on `PATH`.
* The binary belongs to a distro package, Homebrew or cargo (see above).
* The probe times out or its output does not look like Devin CLI.
* No update method applies.

See also: [identification guard](../README.md#identification-guard), [configuration](../README.md#configuration).
