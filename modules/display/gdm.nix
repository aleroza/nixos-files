{ config, lib, pkgs, ... }:

{
  options.display = {
    autoLoginUser = lib.mkOption {
      type = lib.types.str;
      default = "aleroza";
      description = "User for GDM auto-login";
    };
    autoLoginEnable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable GDM auto-login";
    };
  };

  config = {
    services.displayManager.gdm.enable = true;
    services.displayManager.autoLogin = {
      enable = config.display.autoLoginEnable;
      user = config.display.autoLoginUser;
    };
  };
}