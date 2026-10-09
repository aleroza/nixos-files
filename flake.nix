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

      # The openvikingOverlay must be applied through `nixpkgs.overlays`
      # on the nixosSystem level (NOT through specialArgs.pkgs*), because
      # `services.hermes-agent.package` reads `packages.<system>.default`
      # directly from the flake-input and only sees overlays attached
      # to nixpkgs.legacyPackages via nixpkgs.overlays.
      #
      # We also pull in hermes-agent's own `overlays.default` upstream
      # exposes for `extraPythonPackages` overrides (per
      # https://hermes-agent.nousresearch.com/docs/getting-started/
      # nix-setup — "Using the Overlay").
      openvikingOverlay = final: prev:
        let
          basePkg = prev.hermes-agent or null;
          pyVersion = if basePkg != null then basePkg.python.version or "3.12" else null;
          majorMinor =
            if pyVersion != null
            then builtins.replaceStrings [ "." ] [ "" ]
              (builtins.substring 0 3 pyVersion)
            else null;
          pyAttr = if majorMinor != null then "python${majorMinor}Packages" else null;
          pySet = if pyAttr != null then final.${pyAttr} or final.python3Packages or null else null;
        in
        if basePkg == null then {}
        else if pySet == null || !(pySet ? httpx) then
          throw "openviking-overlay: hermes-agent uses python${pyVersion}, "
            + "but nixpkgs has no ${pyAttr}.httpx."
        else {
          hermes-agent = basePkg.override {
            extraPythonPackages = [ pySet.httpx ];
          };
        };
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
            # Nixpkgs overlays — applied to every nixpkgs.legacyPackages
            # in the system closure. `services.hermes-agent.package`
            # reads hermes-agent through this overlay, so the
            # extraPythonPackages override takes effect here.
            #
            # We do NOT include hermes-agent.overlays.default here —
            # it self-applies via `inputs.self.packages.<sys>.default`
            # and creates infinite recursion when read from a
            # consumer flake. Our openvikingOverlay uses
            # `prev.hermes-agent` directly (the flake-input already
            # resolves to packages.default at flake-exports, before
            # any consumer overlay runs), so it doesn't loop.
            ({ ... }: {
              nixpkgs.overlays = [ openvikingOverlay ];
            })
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