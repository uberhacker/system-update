# Homebrew on Linux (`brew`)

Runs `brew update` and `brew upgrade` for a Homebrew (Linuxbrew) installation, as the user who owns it.

| | |
| --- | --- |
| Step name | `brew` |
| Runs as | the invoking user; never root |
| Detected when | `brew` is on the user's `PATH`, or `/home/linuxbrew/.linuxbrew/bin/brew` or `~/.linuxbrew/bin/brew` exists |
| Settings | `AUTOREMOVE` / `--no-autoremove`; brew commands use the one-hour package-manager limit |

## What it does

1. Refuses to run when the invoking user is root (Homebrew does not allow it, and it would break the prefix's ownership), and when the `brew` binary belongs to a different user.
2. `brew update` (refreshes the formula index).
3. `brew outdated --quiet`; nothing outdated ends the step.
4. `brew upgrade`.
5. `brew autoremove` unless `--no-autoremove`.

Every brew call runs with `HOMEBREW_NO_AUTO_UPDATE`, `HOMEBREW_NO_ENV_HINTS`, `HOMEBREW_NO_ANALYTICS`, `HOMEBREW_NO_EMOJI` and `HOMEBREW_NO_COLOR`; with `--no-autoremove` also `HOMEBREW_NO_INSTALL_CLEANUP`.

## What will be affected

* Every outdated formula and cask in the Homebrew prefix, including new major versions.
* With autoremove (the default): formulae that were only installed as dependencies and are no longer needed are removed, and Homebrew cleans old versions after upgrading.
* Tools that other steps find inside the Homebrew prefix (rustup, mise, asdf, cloudflared, bicep, az, ...) are left to this step.

## Dry run and `--detailed`

`--dry-run` still runs `brew update` (it only refreshes Homebrew's metadata), then lists the outdated formulae by name: `N outdated: a b c; would run brew upgrade`. `--detailed` adds nothing beyond that (`brew outdated` with versions is not used).

## Warnings

* `brew update` runs even in a dry run; it updates Homebrew's own git checkout and formula index, not installed software.
* Run `system-update` as yourself. Under `sudo` the user-level tools run as `SUDO_USER`, so Homebrew is still updated as you; as plain root it is skipped.

## Skipped / failed when

* Invoking user is root, or the brew binary is owned by someone else: skipped.
* `brew update` or `brew upgrade` fails: failed (a failed autoremove is a warning).
