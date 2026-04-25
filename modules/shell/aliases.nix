# Shell aliases module
{ config, lib, ... }:

{
  config = {
    environment.shellAliases = {
      ll = "ls -lah";
      nix-rebuild = "sudo nixos-rebuild switch --flake .#aleroza-pc";
      nix-gen = ''echo "Path: $(readlink /run/current-system)"; echo "  ID: $(readlink /nix/var/nix/profiles/system)"'';
    };
  };
}