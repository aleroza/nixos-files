{ config, lib, ... }:

{
  imports = [
    ./base.nix
    ./desktop.nix
    ./development.nix
    ./gaming.nix
    ./docker.nix
    ./hardware.nix
    ./security.nix
    ./flatpak.nix
  ];
}
