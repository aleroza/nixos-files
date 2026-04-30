{ config, lib, pkgs, ... }:

let
  cfg = config.auto;
in

lib.mkIf cfg.gnome.enable {

  services.displayManager = {
    gdm.enable = true;
    defaultSession = "gnome";
    autoLogin = {
      enable = true;
      user = lib.mkDefault "";
    };
  };

  services.desktopManager.gnome.enable = true;

  environment.gnome.excludePackages = with pkgs; [
    epiphany
  ];

  environment.systemPackages = with pkgs; [
    gnome-tweaks
    gnomeExtensions.appindicator
  ];

}
