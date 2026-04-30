{ config, lib, ... }:

let
  cfg = config.auto;
in

lib.mkIf cfg.kde.enable {

  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

}
