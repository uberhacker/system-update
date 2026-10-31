# Go toolchain in /usr/local/go (`go`) - opt-in

Replaces the Go toolchain installed from a go.dev tarball in `/usr/local/go` with the latest stable release. **Off by default**: enable it with `--go-toolchain` (or `--go`) or `GO_TOOLCHAIN=1`.

| | |
| --- | --- |
| Step name | `go` |
| Runs as | root, unless the user can write the parent of `/usr/local/go` |
| Detected when | `/usr/local/go/bin/go` exists |
| Settings | `GO_TOOLCHAIN` / `--go-toolchain` (off by default) |
| Needs | `curl`, `sha256sum` (or `shasum`), `tar` |

## What it does

1. Without `--go-toolchain`: skipped (`off by default; enable with --go-toolchain or GO_TOOLCHAIN=1`).
2. A `/usr/local/go` owned by a distro package is skipped.
3. Reads the installed version (`go version`) and fetches `https://go.dev/dl/?mode=json`, which lists the newest stable release with the sha256 of each archive.
4. Downloads `go<version>.linux-<arch>.tar.gz` from go.dev and verifies it against that sha256.
5. Unpacks it next to `/usr/local/go` (`/usr/local/.go-update.<pid>`), then swaps it in with two renames. If the move fails, or the new `go version` does not report the expected version, the old toolchain is restored.

## What will be affected

* `/usr/local/go` is replaced as a whole, which also removes anything you added inside it.
* `GOPATH` (`~/go`), the module cache and binaries installed with `go install` are not touched.
* Distribution packages of Go (`golang`) and toolchains managed by mise/asdf are never touched.

## Dry run and `--detailed`

Both fetch the release list and report `up to date (goX)` or `would download <file>, verify its sha256 and replace /usr/local/go (OLD -> NEW)`.

## Warnings

* The update moves to the **newest** stable Go, which can be a new minor release (1.23 to 1.24). Modules with a `toolchain` directive may then download a different toolchain on their own.
* The swap needs free space for a second copy of the toolchain next to `/usr/local/go`.

## Skipped / failed when

* Not enabled, distro-owned, version unreadable, unsupported architecture: skipped.
* Release list unreachable, checksum mismatch, unpack or swap failure: failed, with `/usr/local/go` left or restored as it was.
