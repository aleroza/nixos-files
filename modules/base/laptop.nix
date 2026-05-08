{ config, lib, ... }:

let
  cfg = config.auto.laptop;
in

lib.mkIf cfg.enable {

  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "lock";
    HandleLidSwitchDocked = "ignore";
  };

}
