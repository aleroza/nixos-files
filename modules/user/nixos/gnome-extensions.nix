{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    gnomeExtensions.clipboard-indicator
    gnomeExtensions.brightness-control-using-ddcutil
  ];
}
