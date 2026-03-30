{ config, lib, pkgs, ... }:

{
  # Docker
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
}
