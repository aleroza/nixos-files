# Application packages
{ config, lib, pkgs, ... }:

{
  config = {
    environment.systemPackages = with pkgs; [
      # Desktop apps
      telegram-desktop
      gnome-tweaks
      gnomeExtensions.appindicator

      # Gaming
      protonup-qt
      heroic

      # Tools
      flclash
      wireshark
      ddcutil
    ];

    # Flatpak setup
    services.flatpak.enable = true;

    # Steam
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
    };

    # Firefox
    programs.firefox.enable = true;

    # Flatpak system activation
    system.activationScripts = {
      flatpak-setup = ''
        ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
      '';
    };
  };
}