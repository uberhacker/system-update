# Hermes Agent (`hermes`)

Nous Research's Hermes agent (`hermes-agent`), installed with its own installer (updated with `hermes update`) or with `uv tool` / `pipx` (updated through them).

| | |
| --- | --- |
| Step name | `hermes` (for `--only` / `--skip`) |
| Runs as | the invoking user (`SUDO_USER` under `sudo`) |
| Detected when | `hermes` is on the user's `PATH` |
| Expected package | `hermes-agent` |
| Update command | `hermes update` |
| Settings | `TIMEOUT`, `PROBE_TIMEOUT` |

## What it does

1. **Identify the binary.** The real path behind `hermes` decides how it was installed:
   * inside an npm, pnpm or bun global `node_modules`, or a `uv tool` / `pipx` venv: the package must be `hermes-agent`, otherwise the step is skipped;
   * owned by a distro package: skipped, the system package step updates it;
   * under `~/.cargo/bin` or Homebrew: skipped here, because the [cargo](cargo.md) or [brew](brew.md) step updates it.
2. **Probe it.** `hermes -V` runs with stdin closed, `TERM=dumb`, and a `PROBE_TIMEOUT` (20 s) limit. The output must contain `Hermes` and a version, or a three-part version number; anything else is skipped as a different program.
3. **Update it** through the package manager that installed it:

   | Installed with | Command run |
   | --- | --- |
   | npm | `npm install -g <package>@latest` |
   | pnpm | `pnpm add -g <package>@latest` |
   | bun | `bun install -g <package>@latest` |
   | uv | `uv tool upgrade <package>` |
   | pipx | `pipx upgrade <package>` |
   | anything else | `hermes update` |

4. **Compare.** The probe runs again; the summary shows `old -> new`, or `up to date (X)`.

Every command runs with stdin closed and is killed after `TIMEOUT` seconds (300 by default).

## What will be affected

* The `hermes` installation only: the global npm/pnpm/bun package, the `uv`/`pipx` venv, or whatever the tool's own updater replaces (usually the binary under `~/.local/bin` or `~/.local/share`).
* Files belong to the invoking user. Nothing is run as root and no system directory is touched.
* Configuration, credentials and history of the tool are left alone by this script (the tool's own updater may migrate them).

## Dry run and `--detailed`

`--dry-run` identifies and probes the binary, then reports `would update via npm (@pkg)` or `would run 'hermes update'` with the installed version. Nothing is installed.

`--detailed` also asks PyPI for the newest version of `hermes-agent` when it was installed with `pipx` or `uv tool`, and reports `up to date (X)` or `installed -> latest`. For other install methods the latest version is unknown and only the installed one is shown.

## Warnings

* The update replaces the tool in place. Close running sessions of it first if it holds files open.
* To leave it alone: `--skip hermes`, or `SKIP=hermes` in the config file.

## Skipped when

* `hermes` is not on `PATH`.
* The binary belongs to a distro package, Homebrew or cargo (see above).
* The probe times out or its output does not look like Hermes Agent.
* No update method applies.

See also: [identification guard](../README.md#identification-guard), [configuration](../README.md#configuration).
