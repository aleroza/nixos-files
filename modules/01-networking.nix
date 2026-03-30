{ config, lib, pkgs, ... }:

{
  # Hostname
  networking.hostName = "aleroza-pc";

  # NetworkManager
  networking.networkmanager.enable = true;

  # Timezone
  time.timeZone = "Europe/Moscow";

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
    };
  };
}
