{ config, lib, ... }:

let
  cfg = config.auto;
in

lib.mkIf cfg.xserver.enable {

  services.xserver = {
    enable = true;
    xkb.layout = "us,ru";
  };

}
