# Rust toolchains via rustup (`rustup`)

Updates rustup itself and every installed Rust toolchain.

| | |
| --- | --- |
| Step name | `rustup` |
| Runs as | the invoking user |
| Detected when | `rustup` is on the user's `PATH`, or `$CARGO_HOME/bin/rustup` (default `~/.cargo/bin/rustup`) exists |
| Settings | `TIMEOUT`, `PROBE_TIMEOUT`; toolchain commands use the one-hour package-manager limit |

## What it does

1. Probes `rustup --version`; the output must start with `rustup <version>`, otherwise the step is skipped as a different program.
2. **rustup itself**: `rustup self update`, unless rustup is owned by a distro package or comes from Homebrew (the note then says so; that package manager updates it). A failed self-update is noted and the toolchains are still updated.
3. **Toolchains**: `rustup update --no-self-update`, which updates every installed toolchain (stable, beta, nightly, pinned versions) and its components.
4. Counts the `updated` and `unchanged` lines of rustup's output for the summary.

A distro-packaged rustup still manages your toolchains, so the toolchain update runs in every case.

## What will be affected

* Toolchains under `$RUSTUP_HOME` (default `~/.rustup/toolchains`): `rustc`, `cargo`, the standard library and installed components move to the newest release of each channel.
* The rustup binary in `~/.cargo/bin` (unless a package manager owns it).
* Crates installed with `cargo install` are not touched here; see [cargo](cargo.md).

## Dry run and `--detailed`

`--dry-run` runs `rustup check` (it only reads the channel manifests) and reports how many toolchains have an update, plus `would run rustup self update` when that applies. `--detailed` adds nothing beyond that.

## Warnings

* A **nightly** toolchain moves to the latest nightly, which can drop components (clippy, rustfmt, miri) that are missing from that day's build.
* Projects pinned with `rust-toolchain.toml` keep using their pinned version; only the installed channels move.

## Skipped / failed when

* The probe times out or does not print `rustup X.Y`: skipped.
* `rustup update` fails: failed (a self-update failure alone is only noted).
