{ config, lib, ... }:

let
  cfg = config.auto;
in

lib.mkIf cfg.input.enable {

  services.libinput.enable = true;

}
