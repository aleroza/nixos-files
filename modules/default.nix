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
    ./development.nix
    ./gaming.nix
    ./docker.nix
  ];
}
