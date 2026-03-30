{ config, lib, pkgs, ... }:

{
  # GNOME Desktop
  services.desktopManager.gnome.enable = true;

  # Exclude unwanted GNOME apps
  environment.gnome.excludePackages = with pkgs; [ epiphany ];

  # GNOME-specific packages
  environment.systemPackages = with pkgs; [
    vscode
    telegram-desktop
    gnomeExtensions.appindicator
  ];
}
