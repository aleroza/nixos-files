{ config, lib, ... }:

let
  cfg = config.auto.laptop;
in

lib.mkIf cfg {

  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "lock";
    HandleLidSwitchDocked = "ignore";
  };

}
