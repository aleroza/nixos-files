# Security base module
{ config, lib, ... }:

{
  config.services.fail2ban.enable = true;
}