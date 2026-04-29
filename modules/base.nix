{ config, lib, pkgs, ... }:

# ▸ Core system settings — always enabled
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  networking.networkmanager.enable = true;

  nixpkgs.config.allowUnfree = true;
}
