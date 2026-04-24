{ lib, config, pkgs, ... }:

{
  imports = [
    ./core.nix
    ./apps.nix
    ./extensions.nix
    ./exclude.nix
  ];
}