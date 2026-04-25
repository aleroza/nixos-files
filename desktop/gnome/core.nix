{ config, lib, pkgs, ... }:

{
  config = {
    services.desktopManager.gnome.enable = true;
    environment.gnome.excludePackages = with pkgs; [ epiphany ];
  };
}