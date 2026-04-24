{ config, lib, pkgs, ... }:

{
  config = {
    services.xserver.enable = true;
    services.xserver.xkb.layout = "us,ru";
  };
}