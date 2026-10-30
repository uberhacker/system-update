# tmux plugins via TPM (`tpm`)

Updates tmux plugins managed by the [Tmux Plugin Manager](https://github.com/tmux-plugins/tpm).

| | |
| --- | --- |
| Step name | `tpm` |
| Runs as | the invoking user |
| Detected when | `$TMUX_PLUGIN_MANAGER_PATH/tpm/bin/update_plugins` exists (default `~/.tmux/plugins`) |
| Needs | `tmux`, `git` |
| Settings | `TIMEOUT` |

## What it does

1. Skipped when `tmux` is missing or no plugin checkouts exist under the plugins directory.
2. `bash tpm/bin/update_plugins all`, with `TMUX_PLUGIN_MANAGER_PATH` set.
3. The commit of each plugin checkout before and after says how many moved.

## What will be affected

* Every plugin checkout under `~/.tmux/plugins` (TPM included), moved to its latest commit.
* Running tmux sessions keep the old plugin code until you reload the configuration (`prefix + r` or `tmux source ~/.tmux.conf`).

## Dry run and `--detailed`

`--dry-run` reports `would run tpm/bin/update_plugins all for N plugin(s)`; nothing is fetched. `--detailed` adds nothing beyond that.

## Warnings

* Plugins move to their latest commit, not a release.

## Skipped / failed when

* tmux missing or no plugins installed: skipped.
* `update_plugins all` fails: failed.
