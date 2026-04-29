{ config, lib, pkgs, ... }:

let
  hmUsers = config.auto.hmUsers;
in
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users = lib.genAttrs hmUsers (name: import ./${name}.nix);
  };
}
