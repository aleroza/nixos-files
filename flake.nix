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

    # Хелпер: для каждого хоста собираем конфиг
    mkHost = hostName: nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit self; };
      modules = [
        # Базовая опция auto
        ./modules/auto.nix

        # Конфигурация конкретного хоста (там лежит auto = { ... })
        ./hosts/${hostName}/default.nix

        # Все модули — они сами решают, включаться по auto или нет
        ./modules/default.nix

        # Home-manager (опционально)
        home-manager.nixosModules.home-manager
        ./users/default.nix
      ];
    };
  in {
    nixosConfigurations = {
      somehost = mkHost "somehost";
      # А так — добавить ещё хост:
      # worklaptop = mkHost "worklaptop";
    };
  };
}
