{ config, lib, pkgs, ... }:

let
  cfg = config.auto;
in

lib.mkIf cfg.sound.enable {

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

}
