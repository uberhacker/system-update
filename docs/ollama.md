# Ollama (`ollama`)

Updates [Ollama](https://ollama.com). A distro-packaged Ollama is left to the system packages; otherwise the vendor installer is the only update path.

| | |
| --- | --- |
| Step name | `ollama` |
| Runs as | root (the vendor installer needs it) |
| Detected when | `ollama` is on `PATH` |
| Settings | `ALLOW_UNVERIFIED_INSTALLERS` / `--allow-unverified-installers`, `GITHUB_TOKEN`, `TIMEOUT` |

## What it does

1. A binary owned by a distro package: skipped (updated with the system packages).
2. Reads the installed version (`ollama -v`) and the latest GitHub release of `ollama/ollama`. Nothing happens if it is current.
3. Runs the vendor installer only when Ollama was evidently installed by it (`/etc/systemd/system/ollama.service` exists and the binary is under `/usr/local` or `/usr/bin` without a package owner) **or** with `--allow-unverified-installers`.
4. Downloads `https://ollama.com/install.sh`, checks it parses as shell, and runs it as root.

## What will be affected

The installer is Ollama's own script, not this program's. It typically:

* replaces the `ollama` binary and its libraries under `/usr/local` (or `/usr`);
* creates or updates the `ollama` system user and the `ollama.service` systemd unit, and restarts the service, interrupting running models;
* on machines with an NVIDIA or AMD GPU, may install or update GPU runtime libraries.

Downloaded models (in `/usr/share/ollama/.ollama` or `~/.ollama`) are not removed. Nothing is `chown`ed by this program afterwards.

## Dry run and `--detailed`

Both report `would run the ollama installer as root (OLD -> NEW)`, or `OLD -> NEW available; ... rerun with --allow-unverified-installers` when the installer is not allowed.

## Warnings

* **The installer is downloaded over HTTPS but cannot be verified** (Ollama publishes no checksum or signature for it). Running it means trusting ollama.com at that moment.
* The service restart stops in-flight requests.

## Skipped when

* Owned by a distro package; installed some other way without `--allow-unverified-installers`; no `sudo`; version unreadable; latest release unknown.
