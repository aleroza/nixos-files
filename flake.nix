{
  description = "Auto-config NixOS — feature toggles + module presets";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, ... }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    mkHost = hostName: nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit self; };
      modules = [
        ./modules/auto.nix
        ./hosts/${hostName}/default.nix
        ./modules/default.nix
        home-manager.nixosModules.home-manager
        ./users/default.nix
      ];
    };
  in {
    nixosConfigurations = {
      somehost = mkHost "somehost";
      aleroza-pc = mkHost "aleroza-pc";
    };
  };
}
