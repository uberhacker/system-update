# Standalone Docker Compose (`docker-compose`)

Updates a standalone `docker-compose` binary from the official GitHub release. The Compose v2 **plugin** (`docker compose`) is not handled here; it comes from your distro or Docker's repository and is updated with the system packages.

| | |
| --- | --- |
| Step name | `docker-compose` |
| Runs as | the user when the binary and its directory are writable by them, otherwise root through `sudo` |
| Detected when | `docker-compose` is on `PATH` |
| Settings | `GITHUB_TOKEN`, `TIMEOUT` |
| Needs | `curl` and `sha256sum` (or `shasum`) |

## What it does

1. Skips the binary when it is part of Docker Desktop, a symlink into a `cli-plugins` directory (the v2 plugin), owned by a distro package, or not a regular file.
2. Reads the installed version (`docker-compose version --short`). Compose v1 (`1.x`) is end-of-life and is skipped with a hint to install the plugin instead.
3. Looks up the latest release of `docker/compose` on GitHub. Nothing happens if the installed version is current.
4. Downloads `docker-compose-linux-<arch>` and the release's `checksums.txt`, and verifies the sha256. A missing or mismatching checksum stops the step; the binary is untouched.
5. Installs the verified file over the binary's real path with `install -m 0755`.

## What will be affected

* One file: the binary's real path (for example `/usr/local/bin/docker-compose`), replaced with mode 0755. Ownership of the directory is never changed.
* Running containers and Compose projects are not touched.

## Dry run and `--detailed`

Both report `up to date (X)` or `would download docker-compose-linux-<arch> vNEW, verify its sha256 and install it to <path> (OLD -> NEW)`. Nothing is downloaded in a dry run.

## Warnings

* The update goes to the **latest** release, which can be a new major version (2.x to 5.x, for example). Check the Compose release notes if scripts depend on specific behaviour.
* When the binary lives in a root-owned directory the install runs as root via `sudo`.
* Supported architectures: x86_64, aarch64, armv6/armv7, ppc64le, riscv64, s390x.
* Without `GITHUB_TOKEN`, GitHub allows 60 API requests an hour; when the limit is hit the step is skipped, never guessed.

## Skipped when

See step 1 and 2 above, plus: latest release unknown (offline or rate limited), unsupported architecture.
