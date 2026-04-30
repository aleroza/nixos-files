{ config, lib, ... }:

let
  cfg = config.auto;
in

lib.mkIf cfg.power.enable {

  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "lock";
    HandleLidSwitchDocked = "ignore";
  };

}
