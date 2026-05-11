{ config, lib, pkgs, nix-flatpak, ... }:

let
  hmUsers = config.auto.hmUsers;
in
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { nix-flatpak = nix-flatpak; };
    users = lib.genAttrs hmUsers (name: import ./${name}.nix);
  };
}
