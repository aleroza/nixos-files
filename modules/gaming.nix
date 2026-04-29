{ config, lib, pkgs, ... }:

# ▸ Включится только если auto.gaming = true
#   Набор соответствует конфигурации aleroza-pc

lib.mkIf config.auto.gaming {

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
  };

  environment.systemPackages = with pkgs; [
    protonup-qt
    heroic
  ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
