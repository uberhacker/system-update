# Python tools: pipx, pip, AWS CLI (`pip`)

Upgrades Python command line tools installed for the invoking user, without touching the system Python.

| | |
| --- | --- |
| Step name | `pip` |
| Runs as | the invoking user |
| Detected when | `pipx`, `pip`, `pip3` or `aws` is on `PATH` |
| Settings | `TIMEOUT` |

## What it does

1. **pipx**: `pipx upgrade-all`.
2. **pip itself**: only a user-level pip in `~/.local/bin` on a Python that is not "externally managed" (PEP 668) gets `pip install --user -U pip`. A system pip is left to the package manager; on PEP 668 distros (Debian 12+, Ubuntu 23.04+, Arch, ...) pip is never upgraded.
3. **AWS CLI**:
   * v2 is not a pip package and is left to its own installer or your package manager (noted in the summary);
   * v1 installed with pipx is covered by `pipx upgrade-all`;
   * v1 in `~/.local/bin` on a non-PEP-668 Python: `pip install --user -U awscli`.

Nothing is ever `pip install`ed into the system interpreter.

## What will be affected

* The pipx venvs under `~/.local/share/pipx/venvs` (or `$PIPX_HOME`): every package moves to its latest release.
* With a user pip: `~/.local/lib/python3.*/site-packages/pip` and, for AWS CLI v1, `awscli` and its dependencies there.

## Dry run and `--detailed`

`--dry-run` lists what would run (`would run pipx upgrade-all`, ...).

`--detailed` also lists each pipx package with a newer release on PyPI (`installed -> latest`), using `pipx list --short` and PyPI's JSON API (one HTTPS request per package, read-only).

## Warnings

* `pipx upgrade-all` moves every pipx package to its newest release, including new major versions. A version given at install time (`pipx install pkg==X`) is not a pin; use `pipx pin` where your pipx has it, or `--skip pip`.
* For a uv-managed Python tool, see [uv](uv.md).
