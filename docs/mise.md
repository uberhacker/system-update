# mise (`mise`)

Updates [mise](https://mise.jdx.dev) itself and its plugins and, only with `--runtimes`, the tool versions it manages.

| | |
| --- | --- |
| Step name | `mise` |
| Runs as | the invoking user |
| Detected when | `mise` is on the user's `PATH`, or `~/.local/bin/mise` exists |
| Settings | `RUNTIMES` / `--runtimes` (off by default), `TIMEOUT`, `PROBE_TIMEOUT` |

## What it does

1. Probes `mise --version` (must print a calendar version such as `2025.1.0`).
2. **mise itself**: `mise self-update --yes`, unless mise is a distro or Homebrew package (noted). An install that reports self-update as unavailable is noted, not failed.
3. **Plugins**: `mise plugins update` when `mise plugins ls` lists any.
4. **Runtimes**, only with `--runtimes` or `RUNTIMES=1`: `mise upgrade --yes`. This moves each tool only within the version spec configured for it (`node = "20"` stays on 20.x); `--bump` is never used, so configured versions are not rewritten.

All mise calls run with `MISE_YES=1`, `MISE_QUIET=1` and `NO_COLOR=1`.

## What will be affected

* The mise binary (standalone installs).
* Plugin checkouts in mise's data directory.
* With `--runtimes`: new tool versions are installed in mise's installs directory. Your `mise.toml` / `.tool-versions` files are not edited.

## Dry run and `--detailed`

`--dry-run` reports `would run mise self-update --yes` and `would run mise plugins update (N plugin(s))`; with `--runtimes` it runs `mise upgrade --dry-run` and reports how many tool versions would be upgraded. `--detailed` adds nothing beyond that.

## Warnings

* With `--runtimes`, a spec such as `latest` or `lts` lets a tool move to a new major version.
* Old tool versions are not uninstalled (`mise prune` does that).

## Skipped / failed when

* The probe does not match: skipped.
* Self-update, plugin update or `mise upgrade` fails: failed.
