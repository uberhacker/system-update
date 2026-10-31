# NixOS / Nix (`nix`, `system`) - not updated

NixOS and Nix are detected but **not updated**: how a Nix system is upgraded depends on channels vs. flakes, `nixos-rebuild` vs. home-manager, and guessing could do the wrong thing.

| | |
| --- | --- |
| Step name | `nix` or `system` |
| Result | always `skipped`, with the command to run |

The step prints the usual command instead:

* NixOS: `sudo nixos-rebuild switch --upgrade` (or your flake update);
* Nix on another distribution: `nix-channel --update && nix-env -u` (or your flake update).

Flatpak, firmware and the third-party tools are still handled on NixOS.
