#!/usr/bin/env bash
# lib/pkg/nix.sh - NixOS / Nix (not supported; prints what to run instead).
#
# Nix upgrades are declarative and depend on how the system is configured
# (channels vs flakes, nixos-rebuild vs home-manager), so guessing could do
# the wrong thing. We report and leave it to the user.

pkg_nix_dry_needs_root() { return 1; }

pkg_nix_update() {
  if [ "$SU_OS_ID" = nixos ]; then
    step_skip "NixOS is not supported; run 'sudo nixos-rebuild switch --upgrade' (or your flake update)"
  else
    step_skip "Nix is not supported; run 'nix-channel --update && nix-env -u' (or your flake update)"
  fi
  return 0
}
