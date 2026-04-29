{ config, lib, ... }:

{
  imports = [
    ./development.nix
    ./gaming.nix
    ./desktop.nix
    ./docker.nix
  ];
}
