{
  config,
  lib,
  pkgs,
  ...
}:

# ▸ Открытые порты: SSH (22)

lib.mkIf config.auto.ssh {

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
    };
  };
}
