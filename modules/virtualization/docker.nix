# Docker module
{ config, lib, ... }:

{
  config.virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
}