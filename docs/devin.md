# Devin CLI (`devin`)

The Devin CLI, updated with its own `devin update` command.

| | |
| --- | --- |
| Step name | `devin` (for `--only` / `--skip`) |
| Runs as | the invoking user (`SUDO_USER` under `sudo`) |
| Detected when | `devin` is on the user's `PATH` |
| Expected package | none (probe only) |
| Update command | `devin update` |
| Settings | `TIMEOUT`, `PROBE_TIMEOUT` |

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

4. **Compare.** The probe runs again; the summary shows `old -> new`, or `up to date (X)`.

Every command runs with stdin closed and is killed after `TIMEOUT` seconds (300 by default).

## What will be affected

* The `devin` installation only: the global npm/pnpm/bun package, the `uv`/`pipx` venv, or whatever the tool's own updater replaces (usually the binary under `~/.local/bin` or `~/.local/share`).
* Files belong to the invoking user. Nothing is run as root and no system directory is touched.
* Configuration, credentials and history of the tool are left alone by this script (the tool's own updater may migrate them).

## Dry run and `--detailed`

`--dry-run` identifies and probes the binary, then reports `would update via npm (@pkg)` or `would run 'devin update'` with the installed version. Nothing is installed.

`--detailed` looks up the latest version on npm or PyPI when the tool was installed with one of those package managers. With its own installer the latest version is not published anywhere this script can ask, so only the installed version is shown.

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
