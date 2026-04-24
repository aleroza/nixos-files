{
  description = "Aleroza-PC System Flake";

  inputs = {
    # Указываем версию NixOS
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    # Добавляем Home Manager
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
    let
      base = /home/openclaw/.openclaw/workspace/nixos-files;
    in
    {
      nixosConfigurations."aleroza-pc" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs;
        };
        modules = [
          ./hardware-configuration.nix
          ./configuration.nix

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {
              inherit inputs;
            };
            home-manager.users.aleroza = import ./home.nix;
            home-manager.users.openclaw = import ./home-openclaw.nix;
          }
        ];
      };
    };
}
