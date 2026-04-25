# Minimal configuration — wraps host template
# All actual config is in hosts/aleroza-pc/default.nix
#
# NOTE: This file only works with flakes.
# For non-flake rebuilds, use: nixos-rebuild switch --flake .#aleroza-pc
{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./hosts/aleroza-pc/default.nix
  ];
}
