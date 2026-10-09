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

      # Overlay: bump hermes-agent with the OpenViking plugin's Python
      # deps. extraPythonPackages is a derivation-FUNCTION parameter
      # (upstream nix/hermes-agent.nix:208), so .override here must
      # happen BEFORE host code reads pkgs.hermes-agent. Applying it
      # via nixpkgs.overlays guarantees every consumer in the closure
      # (services.hermes-agent.package, addToSystemPackages, etc.) sees
      # the same .override()'d derivation.
      #
      # Version-stable ABI selection: hermes-agent upstream moves
      # between python3.11/3.12/3.13/3.14 across releases. The
      # `python.pkgs.requiredPythonModules` walker inside upstream
      # (nix/hermes-agent.nix:208) needs ABI-matched wheels, so the
      # overlay introspects the actual python version of the
      # hermes-agent build and picks the matching nixpkgs Python
      # package set (`python311Packages`, `python312Packages`, etc.).
      # On a release where upstream bumps python, this overlay
      # automatically follows — no manual edit required.
      #
      # httpx propagates httpcore + h11 + anyio + sniffio + idna +
      # certifi through requiredPythonModules.
      openvikingOverlay = final: prev:
        let
          basePkg = prev.hermes-agent or null;
          pyVersion = basePkg.python.version or "3.12";
          # nixpkgs names its Python sets `python311Packages`,
          # `python312Packages`, ... keyed by major.minor. Resolve
          # the right attribute and fall back to `python3Packages`
          # (which always tracks the latest Python) only when the
          # explicit version is missing in this nixpkgs — better to
          # log loudly than silently ABI-mismatch.
          majorMinor = builtins.replaceStrings [ "." ] [ "" ]
            (builtins.substring 0 3 pyVersion);
          pyAttr = "python${majorMinor}Packages";
          pySet = final.${pyAttr} or final.python3Packages or null;
        in
        if basePkg == null then null
        else if pySet == null || !(pySet ? httpx) then
          # Hard failure is better than silent ABI mismatch.
          throw "openviking-overlay: hermes-agent uses python${pyVersion}, "
            + "but nixpkgs has no ${pyAttr}.httpx. "
            + "Either bump nixpkgs, or set EXTRA_PYTHON_OVERRIDE_HTTPX_PATH "
            + "in flake.nix to a python-matched httpx derivation."
        else basePkg.override {
          extraPythonPackages = [ pySet.httpx ];
        };
      pkgsWithOverlay = pkgs.appendOverlays [ openvikingOverlay ];

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
            inherit self gitMeta nix-flatpak nixpkgs-unstable hermes-agent pkgsWithOverlay;
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