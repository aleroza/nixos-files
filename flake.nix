{
  description = "Auto-config NixOS — feature toggles + module presets";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-flatpak.url = "github:gmodena/nix-flatpak?ref=v0.7.0";
    sops-nix.url = "github:Mic92/sops-nix";

    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
        pyproject-build-systems.follows = "pyproject-build-systems";
        npm-lockfile-fix.follows = "npm-lockfile-fix";
      };
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    pyproject-nix.url = "github:pyproject-nix/pyproject.nix";
    uv2nix.url = "github:pyproject-nix/uv2nix";
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs = {
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
      };
    };
    npm-lockfile-fix.url = "github:jeslie0/npm-lockfile-fix";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      nix-flatpak,
      sops-nix,
      hermes-agent,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # See modules/revision.nix for the env vars these fields come from.
      gitMeta = let
        envRev = builtins.getEnv "NIXOS_GIT_REVISION";
      in {
        rev = envRev;
        shortRev =
          if builtins.stringLength envRev >= 7
          then builtins.substring 0 7 envRev
          else "";
        branch = builtins.getEnv "NIXOS_GIT_BRANCH";
        dirty = (builtins.getEnv "NIXOS_GIT_DIRTY") == "1";
        url = builtins.getEnv "NIXOS_GIT_URL";
      };

      mkHost =
        hostName:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit self gitMeta nix-flatpak nixpkgs-unstable hermes-agent;
          };
          modules = [
            ./modules/auto.nix
            ./hosts/${hostName}/default.nix
            ./modules/default.nix
            home-manager.nixosModules.home-manager
            nix-flatpak.nixosModules.nix-flatpak
            sops-nix.nixosModules.sops
            hermes-agent.nixosModules.default
            ./users/default.nix
          ];
        };
    in
    {
      nixosConfigurations = {
        somehost = mkHost "somehost";
        aleroza-pc = mkHost "aleroza-pc";
      };
    };
}