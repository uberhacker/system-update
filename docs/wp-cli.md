# WP-CLI (`wp-cli`)

Updates [WP-CLI](https://wp-cli.org) with `wp cli update`.

| | |
| --- | --- |
| Step name | `wp-cli` |
| Runs as | the invoking user, or root when the phar is not writable by the user |
| Detected when | `wp` is on `PATH` |
| Settings | `TIMEOUT` |

## What it does

`wp cli update --yes --no-color --allow-root`, as the user when the phar is writable by them, as root through `sudo` otherwise (that is what `--allow-root` is for; it is harmless for a normal user). A `wp` owned by a distro package is skipped. The version is read before and after (`wp cli version`).

## What will be affected

* The `wp` phar, replaced in place with the latest stable release.
* WordPress sites, plugins and themes are **not** touched; this only updates the WP-CLI tool.

## Dry run and `--detailed`

`--dry-run` reports `would run wp cli update (installed X)`. `--detailed` also looks up the latest GitHub release of `wp-cli/wp-cli` and reports `up to date` or `installed -> latest`.

## Warnings

* WP-CLI installed with Composer or a package manager is not a phar; `wp cli update` refuses to run and the step fails. Update it the way it was installed.
* WP-CLI packages (`wp package list`) are not updated by this step.
