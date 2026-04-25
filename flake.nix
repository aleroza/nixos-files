{
  description = "Aleroza-PC System Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    {
      homeManagerConfigurations = {
        "aleroza" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          modules = [ ./hosts/aleroza-pc/home.nix ];
        };
        "openclaw" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          modules = [ ./hosts/aleroza-pc/home-openclaw.nix ];
        };
      };

      nixosConfigurations."aleroza-pc" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/aleroza-pc/default.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users = {
              aleroza = import ./hosts/aleroza-pc/home.nix;
              openclaw = import ./hosts/aleroza-pc/home-openclaw.nix;
            };
          }
        ];
      };
    };
}
