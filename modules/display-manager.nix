{ config, lib, ... }:

let
  cfg = config.auto;
in

lib.mkIf cfg.displayManager.autoLogin.enable {

  services.displayManager = {
    autoLogin.enable = true;
    autoLogin.user = cfg.displayManager.autoLogin.user;
  };

}
