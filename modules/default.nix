{ config, lib, ... }:

{
  imports = [
    # Always-on modules (no auto.* gate). Imported first so they run before
    # hosts/aleroza-pc/default.nix and provide defaults later modules can
    # override.
    ./revision.nix

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
    ./nix-rebuild-meta.nix
  ];
}
