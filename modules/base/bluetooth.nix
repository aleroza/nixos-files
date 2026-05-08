{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.auto;
in

# ▸ Включается если auto.bluetooth = true

lib.mkIf cfg.bluetooth {

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
        Experimental = true;
      };
    };
  };
}
