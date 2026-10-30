# Standalone Bicep CLI (`bicep`)

Updates a standalone `bicep` binary from the official GitHub release. The Bicep that `az` manages in `~/.azure/bin` is handled by [azure-cli](azure-cli.md) instead.

| | |
| --- | --- |
| Step name | `bicep` |
| Runs as | the user when the binary is under the user's home, otherwise root |
| Detected when | `bicep` is on the user's `PATH` and is not inside `${AZURE_CONFIG_DIR:-~/.azure}/bin` |
| Settings | `GITHUB_TOKEN`, `PROBE_TIMEOUT` |
| Needs | `curl`, `sha256sum` (or `shasum`) |

## What it does

1. Identifies the binary: a distro package is skipped (updated with the system packages), Homebrew is skipped (the [brew](brew.md) step), and `bicep --version` must print `Bicep CLI version X.Y`.
2. Picks the release asset `bicep-linux-x64` or `bicep-linux-arm64` (`bicep-linux-musl-<arch>` on Alpine).
3. Compares the installed version with the latest release of `Azure/bicep`.
4. Looks for a published sha256: a checksums file among the release assets (`checksums.txt`, `SHA256SUMS`, ...), an `<asset>.sha256` asset, or a release-notes line naming the asset next to a hash. **Without one nothing is installed.**
5. Downloads the asset, verifies it, and installs it over the binary's real path with `install -m 0755`, as the user when they can write it, otherwise as root.

## What will be affected

* One file: the `bicep` binary, replaced in place with mode 0755.

## Dry run and `--detailed`

Both report `up to date (X)` or `would download bicep-linux-<arch> vNEW, verify its sha256 and install it to <path> (OLD -> NEW)`. The dry run does not check whether a checksum is published, so a real run can still end in "no sha256 published".

## Warnings

* If the release publishes no sha256 for the asset, the real run is skipped with `no sha256 published for <asset>; refusing to install an unverified binary`.
* Only x86_64 and aarch64 are supported.

## Skipped when

* Distro package or Homebrew; probe does not match; unsupported architecture; latest release unknown (offline or rate limited); no published checksum.
