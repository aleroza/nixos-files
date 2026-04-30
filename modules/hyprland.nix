{ config, lib, ... }:

let
  cfg = config.auto;
in

lib.mkIf cfg.hyprland.enable {

  services.displayManager = {
    sddm.enable = true;
    defaultSession = "hyprland";
    autoLogin = {
      enable = true;
      user = lib.mkDefault "";
    };
  };

  programs.hyprland.enable = true;

}
