{ config, lib, pkgs, ... }:

let
  cfg = config.auto;
in

# ▸ Открытые порты: SSH (22)

{
  services.openssh = lib.mkIf cfg.ssh {
    enable = true;
    settings = {
      PermitRootLogin = "no";
    };
  };

  services.fail2ban = lib.mkIf cfg.fail2ban {
    enable = true;
  };
}
