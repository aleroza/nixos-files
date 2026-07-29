{ config, lib, ... }:

# ▸ Unified firewall port set.
#
#   NixOS merges `networking.firewall.allowedTCPPorts` / `allowedUDPPorts`
#   when multiple modules contribute lists, but doing it here in one place
#   keeps the wiring obvious: every feature module contributes its ports
#   to `auto.firewall.*Ports`, and this module applies the union.
#
#   To add a feature, add an `auto.firewall.<feature>` toggle that appends
#   to the lists below. To open an extra port from a host config, set
#   `auto.firewall.allowedTCPPorts` / `allowedUDPPorts` directly.

let
  gamingTCP = [
    27031 # Steam Remote Play streaming
    27036 # Steam Remote Play (incoming)
    27037 # Steam Remote Play (incoming)
  ];
  gamingUDP = [
    9000  # Pico Park (default)
    27031 # Steam Remote Play streaming
    27036 # Steam Remote Play
    27037 # Steam Remote Play
    4380  # Steam client (LAN discovery / LAN game transfers)
    5353  # mDNS — service discovery used by many games
  ];
in
lib.mkMerge [

  (lib.mkIf config.auto.firewall.gaming {
    auto.firewall.allowedTCPPorts = lib.mkBefore gamingTCP;
    auto.firewall.allowedUDPPorts = lib.mkBefore gamingUDP;
  })

  # Apply the merged port set + trusted interfaces in one place.
  ({
    networking.firewall = {
      allowedTCPPorts = config.auto.firewall.allowedTCPPorts;
      allowedUDPPorts = config.auto.firewall.allowedUDPPorts;
      trustedInterfaces = config.auto.firewall.trustedInterfaces;
    };
  })

]
