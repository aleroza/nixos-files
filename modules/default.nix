{ config, lib, ... }:

{
  imports = [
    ./base
    ./security/fail2ban.nix
    ./security/sops.nix
    ./flatpak.nix
    ./xserver.nix
    ./gnome
    ./kde.nix
    ./hyprland.nix
    ./dev
    ./gaming.nix
    ./firewall/gaming.nix
    ./docker.nix
    ./network-capture.nix
    ./services/openviking.nix
    ./services/openviking-bootstrap.nix
    ./services/hermes-host-privs.nix
  ];
}
