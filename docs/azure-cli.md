# Azure CLI and its Bicep (`azure-cli`)

Updates the Azure CLI (`az`) when it is not managed by a package manager, and the Bicep CLI that `az` installs for itself.

| | |
| --- | --- |
| Step name | `azure-cli` |
| Runs as | the invoking user |
| Detected when | `az` is on the user's `PATH` |
| Settings | `TIMEOUT`, `PROBE_TIMEOUT`; `az upgrade` uses the one-hour package-manager limit |

## What it does

1. Reads the installed version from `az version --output json` (the `azure-cli` field). No version: skipped as a different program.
2. **az itself**:
   * owned by a distro package, which includes Microsoft's own apt/rpm repository: left to the system step (noted);
   * from Homebrew: left to the [brew](brew.md) step (noted);
   * otherwise (pip, the user's own install): `az upgrade --yes --all false`.
3. **Bicep managed by az**: when `${AZURE_CONFIG_DIR:-~/.azure}/bin/bicep` exists, `az bicep upgrade`.

All `az` commands run with colour, the progress bar and telemetry turned off (`AZURE_CORE_NO_COLOR`, `AZURE_CORE_DISABLE_PROGRESS_BAR`, `AZURE_CORE_COLLECT_TELEMETRY=false`).

## What will be affected

* The Azure CLI installation (when this step updates it), not its extensions: `--all false` leaves extensions alone.
* `~/.azure/bin/bicep`, replaced by `az bicep upgrade`.
* Your login, subscriptions and configuration in `~/.azure` are not touched.

A standalone `bicep` binary elsewhere on `PATH` is handled by the [bicep](bicep.md) step.

## Dry run and `--detailed`

`--dry-run` reports `would run az upgrade --yes --all false` (when it applies) and `would run az bicep upgrade (installed X)`. `--detailed` adds nothing beyond that.

## Warnings

* Extensions (`az extension list`) are not updated; run `az extension update --name <ext>` yourself.

## Skipped / failed when

* `az version` gives no version: skipped.
* `az` is a distro package and there is no az-managed Bicep: skipped (the system step updates it).
* `az upgrade` or `az bicep upgrade` fails: failed.
