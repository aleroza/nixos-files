{ config, lib, pkgs, ... }:

# ▸ Включится только если auto.gaming = true

lib.mkIf config.auto.gaming {

  environment.systemPackages = with pkgs; [
    steam
    lutris
    mangohud
    gamemode
  ];

  programs.gamemode.enable = true;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
