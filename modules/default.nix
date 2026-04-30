{ config, lib, ... }:

{
  imports = [
    ./base.nix
    ./xserver.nix
    ./display-manager.nix
    ./gnome.nix
    ./kde.nix
    ./hyprland.nix
    ./sound.nix
    ./power.nix
    ./input.nix
    ./programs.nix
    ./development.nix
    ./gaming.nix
    ./docker.nix
    ./hardware.nix
    ./security.nix
    ./flatpak.nix
  ];
}
