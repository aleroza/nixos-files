{ config, lib, ... }:

# ▸ Opens firewall ports required for LAN/hosted multiplayer games
#   (Jackbox, Pico Park, etc.), Steam Remote Play, Steam LAN game
#   transfers, and Source Dedicated Server.
#   Guarded by `auto.firewall.gaming`.
#   Note: programs.steam.{remotePlay,dedicatedServer,localNetworkGameTransfers}
#   firewall flags are already set by modules/gaming.nix when auto.gaming = true.

lib.mkIf config.auto.firewall.gaming {

  networking.firewall = {
    # Steam Remote Play (host) — https://help.steampowered.com/en/faqs/view/0E2D-1B7A-4D27-80A3
    allowedTCPPorts = [
      27031 # Steam Remote Play streaming
      27036 # Steam Remote Play (incoming)
      27037 # Steam Remote Play (incoming)
    ];
    allowedUDPPorts = [
      27031 # Steam Remote Play streaming
      27036 # Steam Remote Play
      27037 # Steam Remote Play
      4380 # Steam client (LAN discovery / LAN game transfers)
      5353 # mDNS — service discovery used by many games
    ];
  };
}
