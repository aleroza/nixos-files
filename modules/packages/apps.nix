# Application packages
{ config, lib, pkgs, ... }:

{
  config = {
    environment.systemPackages = with pkgs; [
      # Desktop apps
      telegram-desktop
      gnome-tweaks

      # Gaming
      protonup-qt
      heroic

      # Tools
      flclash
    ];
  };
}