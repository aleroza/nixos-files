# SSH server module
{ config, lib, ... }:

{
  config.services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
    };
  };
}