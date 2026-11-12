# Pantheon Terminus (`terminus`)

Updates [Terminus](https://github.com/pantheon-systems/terminus), Pantheon's command line tool, with `terminus self:update`.

| | |
| --- | --- |
| Step name | `terminus` |
| Runs as | the invoking user, or root when the phar or its directory is not writable by the user |
| Detected when | `terminus` is on `PATH` |
| Settings | `TIMEOUT` |

## What it does

`terminus self:update --no-interaction --no-ansi`, as the user when the phar is writable by them, as root through `sudo` otherwise. A Terminus owned by a distro package is skipped. The version is read before and after (`terminus --version`).

## What will be affected

* The Terminus phar, replaced in place.
* Terminus plugins in `~/.terminus/plugins` are not updated; check them after a major Terminus update.

## Moving it out of /usr/local/bin

With `--move-to-home terminus` (or `MOVE_TO_HOME=terminus`), a copy in a root-owned directory is moved to `~/.local/bin` once (when that directory is on your `PATH` ahead of the old one), so later updates run as you without sudo. See [Third-party tools](../README.md#third-party-tools).

## Dry run and `--detailed`

`--dry-run` reports `would run terminus self:update (installed X)`. `--detailed` also looks up the latest GitHub release of `pantheon-systems/terminus` and reports `up to date` or `installed -> latest`.

## Warnings

* Terminus installed with Composer (`composer global require pantheon-systems/terminus`) is updated by the [composer](composer.md) step; `self:update` is meant for the phar and may fail on such installs. Use `--skip terminus` then.
* A new major Terminus version can drop plugin compatibility.
