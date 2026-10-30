# RVM (`rvm`)

Updates [RVM](https://rvm.io) itself with `rvm get stable`. Installed Rubies and gems are not changed.

| | |
| --- | --- |
| Step name | `rvm` |
| Runs as | the invoking user |
| Detected when | `~/.rvm/bin/rvm` exists, or `rvm` is on `PATH` |
| Settings | `GITHUB_TOKEN`, `TIMEOUT` |

## What it does

1. Reads the installed version (`rvm -v`) and the latest release of `rvm/rvm` on GitHub. If the installed version is current, nothing runs. If the latest release is unknown, `rvm get stable` decides.
2. `rvm get stable`.

## What will be affected

* The RVM scripts under `~/.rvm` (or the system-wide RVM directory for a multi-user install). Rubies, gemsets and gems are left as they are.

## Dry run and `--detailed`

Both report `up to date (X)` or `would run 'rvm get stable' (OLD -> NEW)`.

## Warnings

* `rvm get stable` downloads and runs RVM's own installer from the network (RVM verifies it with its GPG key when the key is imported).
* A multi-user RVM in `/usr/local/rvm` is not writable by a normal user; the update then fails rather than escalating.
