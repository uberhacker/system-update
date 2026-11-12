# WP-CLI (`wp-cli`)

Updates [WP-CLI](https://wp-cli.org) with `wp cli update`.

| | |
| --- | --- |
| Step name | `wp-cli` |
| Runs as | the invoking user, or root when the phar or its directory is not writable by the user |
| Detected when | `wp` is on `PATH` |
| Settings | `TIMEOUT` |

## What it does

`wp cli update --yes --no-color --allow-root`, as the user when both the phar and its directory are writable by them, as root through `sudo` otherwise (that is what `--allow-root` is for; it is harmless for a normal user). A `wp` owned by a distro package is skipped. The version is read before and after (`wp cli version`).

## What will be affected

* The `wp` phar, replaced in place with the latest stable release.
* WordPress sites, plugins and themes are **not** touched; this only updates the WP-CLI tool.

## Moving it out of /usr/local/bin

With `--move-to-home wp-cli` (or `MOVE_TO_HOME=wp-cli`), a copy in a root-owned directory is moved to `~/.local/bin` once (when that directory is on your `PATH` ahead of the old one), so later updates run as you without sudo. See [Third-party tools](../README.md#third-party-tools).

## Dry run and `--detailed`

`--dry-run` reports `would run wp cli update (installed X)`. `--detailed` also looks up the latest GitHub release of `wp-cli/wp-cli` and reports `up to date` or `installed -> latest`.

## Warnings

* WP-CLI replaces itself by writing a new file next to the phar, so a user-owned `wp` in a root-owned `/usr/local/bin` fails with "`/usr/local/bin` is not writable by current user" when run as the user. The step therefore runs the update as root in that case. It never changes the ownership of `/usr/local/bin`.
* WP-CLI installed with Composer or a package manager is not a phar; `wp cli update` refuses to run and the step fails. Update it the way it was installed.
* WP-CLI packages (`wp package list`) are not updated by this step.
