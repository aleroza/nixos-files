{ config, lib, pkgs, nix-flatpak, nixpkgs-unstable, ... }:

let
  hmUsers = config.auto.hmUsers;
in
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      nix-flatpak = nix-flatpak;
      auto = config.auto;
      nixpkgs-unstable = nixpkgs-unstable;
    };
    users = lib.genAttrs hmUsers (name: import ./${name}.nix);
  };
}
