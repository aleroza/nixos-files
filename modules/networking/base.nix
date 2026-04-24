# Networking base module
{ config, lib, ... }:

{
  config = {
    networking.hostName = "aleroza-pc";
    networking.networkmanager.enable = true;
    time.timeZone = "Europe/Moscow";
  };
}