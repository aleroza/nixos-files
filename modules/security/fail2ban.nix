{
  config,
  lib,
  pkgs,
  ...
}:

lib.mkIf config.auto.fail2ban {

  services.fail2ban.enable = true;

}
