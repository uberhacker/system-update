# Crates installed with cargo (`cargo`)

Updates the binaries you installed with `cargo install`, using the [cargo-update](https://crates.io/crates/cargo-update) crate.

| | |
| --- | --- |
| Step name | `cargo` |
| Runs as | the invoking user |
| Detected when | `cargo` is on `PATH` (or `$CARGO_HOME/bin/cargo`) **and** `$CARGO_HOME/.crates.toml` (default `~/.cargo/.crates.toml`) is not empty |
| Needs | `cargo install-update` (`cargo install cargo-update`) |
| Settings | the one-hour package-manager limit applies (crates are compiled) |

## What it does

1. Reads the installed crate names from `~/.cargo/.crates.toml`.
2. Without `cargo-install-update` (on `PATH` or in `~/.cargo/bin`): skipped, with the number of crates and how to enable it. cargo itself has no "update everything" command.
3. With it: `cargo install-update -a`, which rebuilds and reinstalls every crate that has a newer version on crates.io.

## What will be affected

* The binaries in `~/.cargo/bin` installed with `cargo install`, rebuilt from source.
* The Rust toolchain itself is not changed; see [rustup](rustup.md).

## Dry run and `--detailed`

`--dry-run` runs `cargo install-update --list -a` (a read-only listing) and reports `N of M crate(s) have updates`. `--detailed` adds nothing beyond that.

## Warnings

* Every update **compiles from source**: it can take a long time and needs a working C toolchain for crates with native dependencies. The one-hour limit applies to the whole `install-update -a` run.
* Crates move to their newest version, including new major versions.
* Tools found under `~/.cargo/bin` are routed here by the other tool steps, which skip them with a pointer to `cargo install`.

## Skipped / failed when

* No crates in `.crates.toml`; `cargo-update` not installed: skipped.
* `cargo install-update -a` fails: failed.
