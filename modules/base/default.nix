{ config, lib, ... }:

{
  imports = [
    ./core.nix
    ./input.nix
    ./sound.nix
    ./programs.nix
    ./bluetooth.nix
    ./ssh.nix
    ./laptop.nix
  ];

  config = lib.mkMerge [
    # ▸ Server profile — convenience preset
    #   Sets auto.ssh and auto.fail2ban to true via mkDefault (can be overridden per host)
    (lib.mkIf config.auto.server {
      auto.ssh = lib.mkDefault true;
      auto.fail2ban = lib.mkDefault true;
    })

    # ▸ Desktop profile — convenience preset
    #   Enables common desktop features via mkDefault (all can be overridden per host)
    #   Also implies server profile (ssh + fail2ban)
    (lib.mkIf config.auto.desktop {
      auto.server = lib.mkDefault true;
      auto.input.enable = lib.mkDefault true;
      auto.sound.enable = lib.mkDefault true;
      auto.programs.enable = lib.mkDefault true;
      auto.bluetooth = lib.mkDefault true;
    })
  ];
}
