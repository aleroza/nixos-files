# Dev tools packages
{ config, lib, pkgs, ... }:

{
  config = {
    environment.systemPackages = with pkgs; [
      nixfmt
    ];
  };
}