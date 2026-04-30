{ config, lib, ... }:

let
  cfg = config.auto;
in

lib.mkIf cfg.kde.enable {

  services.displayManager = {
    sddm.enable = true;
    defaultSession = "plasma";
    autoLogin = {
      enable = true;
      user = lib.mkDefault "";
    };
  };

  services.desktopManager.plasma6.enable = true;

}
