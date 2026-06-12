{ config, lib, ... }:

{
  imports = [
    ./base
    ./security/fail2ban.nix
    ./flatpak.nix
    ./xserver.nix
    ./gnome
    ./kde.nix
    ./hyprland.nix
    ./dev
    ./gaming.nix
    ./docker.nix
    ./network-capture.nix
  ];
}
