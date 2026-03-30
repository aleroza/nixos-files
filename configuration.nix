# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix

    # Modular configuration
    ./modules/00-boot.nix
    ./modules/01-networking.nix
    ./modules/02-display.nix
    ./modules/03-desktop-gnome.nix
    ./modules/04-audio-bluetooth.nix
    ./modules/05-input.nix
    ./modules/06-security.nix
    ./modules/07-users.nix
    ./modules/08-packages.nix
    ./modules/09-docker.nix
  ];

  # Nix settings (flakes support)
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Firefox
  programs.firefox.enable = true;

  # State version — do NOT change
  system.stateVersion = "25.11";
}
