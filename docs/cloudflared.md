# cloudflared (`cloudflared`)

Updates a standalone `cloudflared` (Cloudflare Tunnel client) binary from the official GitHub release.

| | |
| --- | --- |
| Step name | `cloudflared` |
| Runs as | root, unless the binary is writable by the user running the step |
| Detected when | `cloudflared` is on `PATH` |
| Settings | `GITHUB_TOKEN`, `PROBE_TIMEOUT` |
| Needs | `curl`, `sha256sum` (or `shasum`) |

## What it does

1. Identifies the binary: owned by a distro package (including Cloudflare's own apt/rpm repository) it is skipped and updated with the system packages; from Homebrew it is left to the [brew](brew.md) step. `cloudflared --version` must print `cloudflared version X.Y`.
2. Compares the installed version with the latest release of `cloudflare/cloudflared` (asset `cloudflared-linux-amd64`, `-arm64`, `-arm` or `-386`).
3. Looks for a published sha256 (a checksums asset, an `<asset>.sha256` asset, or the hash next to the asset name in the release notes). **Without one nothing is installed.**
4. Downloads, verifies, and installs over the binary's real path with `install -m 0755` (as root when the user cannot write it).

## What will be affected

* One file: the `cloudflared` binary (usually `/usr/local/bin/cloudflared`).
* A running `cloudflared` service keeps the old binary until it is restarted; this step does not restart it.

## Dry run and `--detailed`

Both report `up to date (X)` or `would download cloudflared-linux-<arch> NEW, verify its sha256 and install it to <path> (OLD -> NEW)`. The dry run does not check whether a checksum is published.

## Warnings

* Restart the tunnel service (`systemctl restart cloudflared`) after an update to run the new version.
* A release without a published sha256 is not installed.

## Skipped when

* Distro package or Homebrew; probe does not match; unsupported architecture; latest release unknown; no published checksum.
