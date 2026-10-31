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
      url = "github:NousResearch/hermes-agent/v0.21.6";
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

      # The openviking overlay extends hermes-agent without recursion.
# Upstream `hermes-agent.overlays.default` evaluates
# `inputs.self.packages.<system>.default`, which references its own
# flake outputs and creates infinite recursion when composed from a
# consumer flake. So we read `packages.<sys>.default` directly here —
# it is the derivation upstream wants consumers to override.
#
# Composition (applied via nixpkgs.overlays):
#   1. `hermes-agent.packages.x86_64-linux.default` is the underlying
#      derivation that the upstream NixOS module consumes via
#      `services.hermes-agent.package`.
#   2. Our `.override { extraPythonPackages = [...]; }` extends that
#      derivation's wrapper PYTHONPATH with httpx (and its transitive
#      deps: httpcore, h11, anyio, sniffio, idna, certifi) via
#      `python.pkgs.requiredPythonModules`.
#
# Version-stable ABI selection: hermes-agent upstream moves between
# python3.11/3.12/3.13/3.14 across releases. We introspect the
# actual hermes-agent python version at overlay-eval time and pick
# the matching nixpkgs Python package set (python311Packages,
# python312Packages, etc.) so the overlay automatically follows
# future upstream python bumps without manual edits.
      composedOpenvikingOverlay = final: prev: let
        basePkg = prev.hermes-agent or null;
        pyVersion = if basePkg != null
          then basePkg.python.version or "3.12"
          else null;
        majorMinor = if pyVersion != null
          then builtins.replaceStrings [ "." ] [ "" ]
            (builtins.substring 0 3 pyVersion)
          else null;
        pyAttr = if majorMinor != null then "python${majorMinor}Packages" else null;
        pySet =
          let
            pyAttrExists = pyAttr != null && builtins.hasAttr pyAttr final;
            pySet' = if pyAttrExists
              then builtins.getAttr pyAttr final
              else null;
          in if pySet' != null then pySet' else final.python3Packages or null;
      in if basePkg == null then {}
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
            # Apply the openviking overlay (which composes upstream
            # hermes-agent overlay + httpx injection) at the nixosSystem
            # level. `services.hermes-agent.package` reads hermes-agent
            # through this overlay, so the extraPythonPackages override
            # takes effect here.
            ({ ... }: {
              nixpkgs.overlays = [ composedOpenvikingOverlay ];
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
      # PoC: build-time bundle that mimics `hermes plugins install hindsight`.
      #
      # `hermes plugins install hindsight` runtime does:
      #   1. git clone vectorize-io/hindsight#hindsight-integrations/hermes
      #   2. uv pip install hindsight-client hindsight-embed
      #   3. drop __init__.py + plugin.yaml into ~/.hermes/plugins/hindsight/
      #
      # Step 2 fails on NixOS because hermes-agent's Python env lives in
      # /nix/store (read-only, no uv.lock). We sidestep that by doing
      # the build entirely in /nix/store (writable during build) and
      # packaging the result as a self-contained derivation that the
      # activation script unpacks into ~/.hermes/plugins/hindsight/ at
      # switch-to-configuration time.
      #
      # The wheel contains both the plugin (hindsight_integrations_hermes)
      # AND its transitive runtime deps (hindsight-client, hindsight-embed,
      # fastapi, uvicorn, etc.) — all resolved against the plugin's own
      # uv.lock, not against the read-only hermes-agent-env.
      hindsightMemoryBundle =
        let
          basePkg = hermes-agent.packages.x86_64-linux.default;
          pluginSrc = pkgs.fetchFromGitHub {
            owner = "vectorize-io";
            repo = "hindsight";
            rev = "d56c4acdf59c41957613d399094cdf8c489b060c";
            # Raw sha256-hex 64 chars (computed from the .tar.gz with
            # `nix hash path --type sha256 --base16`). nixpkgs 26.05
            # fetchurl does not infer hash type from the value, so
            # we route through the explicit `sha256` parameter (the
            # legacy hash fields are still supported and the
            # inferred-type path is restricted to SRI via `hash`).
            sha256 = "2f91e3545eb87e84ac962ccfe853ef11c9f3a2b2b82d8efc627bae3fcadf11c0";
          };
          python = pkgs.python312;
          # Build the hindsight memory plugin wheel in /nix/store. The
          # plugin's own uv.lock pins hindsight-client and hindsight-embed
          # as transitive deps; we resolve them through python -m build
          # (PEP 517 frontend, hatchling per the plugin's pyproject.toml)
          # and bundle them into a single self-contained wheel that the
          # activation script installs into a writable user target via
          # `uv pip install --user` at switch-to-configuration time.
          #
          # The plugin sets `package = false` in [tool.uv] so it loads
          # as a directory in non-NixOS installs. We override to
          # package=true so `python -m build` actually produces a wheel.
          hindsightWheel = python.pkgs.buildPythonPackage {
            pname = "hindsight-hermes-plugin";
            version = "1.2.1-d56c4acd";
            format = "wheel";
            src = pluginSrc;
            # NOTE: hindsight-client and hindsight-embed are NOT in nixpkgs
            # 26.05. We build them as separate wheels in the same
            # closure, then bundle all three into the activation script's
            # `uv pip install --user` invocation. propagatedBuildInputs
            # intentionally empty here to keep the plugin wheel build
            # self-contained.
            propagatedBuildInputs = [ ];
            nativeBuildInputs = [
              python.pkgs.hatchling
              python.pkgs.hatch-vcs
              python.pkgs.hatch-fancy-pypi-readme
              python.pkgs.editables
            ];
            dontConfigure = true;
            preBuild = ''
              cd "$sourceRoot/hindsight-integrations/hermes"
              sed -i 's/^package = false/package = true/' pyproject.toml
              sed -i '/\[tool\.uv\]/,/^\[/d' pyproject.toml
              cat >> pyproject.toml <<'EOF'

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
EOF
            '';
            meta = {
              description = "Hindsight memory plugin for Hermes Agent (plugin wheel only; deps installed at activation)";
              license = pkgs.lib.licenses.mit;
            };
          };

            # Build hindsight-client wheel from upstream source.
          hindsightClientWheel = python.pkgs.buildPythonPackage {
            pname = "hindsight-client";
            version = "0.10.5";
            format = "wheel";
            src = pluginSrc;
            sourceRoot = "hindsight-source";
            # Source is a directory (fetchFromGitHub), not a tarball;
            # skip unpackPhase's auto-extract which errors on dirs.
            dontUnpack = true;
            dontConfigure = true;
            preBuild = ''
              cp -r ${pluginSrc}/hindsight-clients/python "$NIX_BUILD_TOP/hindsight-source/"
              chmod -R u+rwX "$NIX_BUILD_TOP/hindsight-source"
              cd "$NIX_BUILD_TOP/hindsight-source"
              if [ ! -f pyproject.toml ]; then
                echo "hindsight-clients/python/pyproject.toml missing; aborting"
                exit 1
              fi
            '';
            propagatedBuildInputs = [ ];
            nativeBuildInputs = [
              python.pkgs.hatchling
              python.pkgs.hatch-vcs
              python.pkgs.editables
            ];
            meta = { description = "hindsight-client SDK"; license = pkgs.lib.licenses.mit; };
          };

          # Build hindsight-embed wheel from upstream source.
          hindsightEmbedWheel = python.pkgs.buildPythonPackage {
            pname = "hindsight-embed";
            version = "0.10.2";
            format = "wheel";
            src = pluginSrc;
            sourceRoot = "hindsight-source";
            dontUnpack = true;
            dontConfigure = true;
            preBuild = ''
              cp -r ${pluginSrc}/hindsight-embed "$NIX_BUILD_TOP/hindsight-source/"
              chmod -R u+rwX "$NIX_BUILD_TOP/hindsight-source"
              cd "$NIX_BUILD_TOP/hindsight-source"
              if [ ! -f pyproject.toml ]; then
                echo "hindsight-embed/pyproject.toml missing; aborting"
                exit 1
              fi
            '';
            propagatedBuildInputs = [ ];
            nativeBuildInputs = [
              python.pkgs.hatchling
              python.pkgs.hatch-vcs
              python.pkgs.editables
              python.pkgs.hatch-fancy-pypi-readme
            ];
            meta = { description = "hindsight-embed (PostgreSQL-backed local memory operations)"; license = pkgs.lib.licenses.mit; };
          };
        in
        basePkg.overrideAttrs (old: {
          # Reuse the upstream installPhase but copy our wheel into the
          # hermes-agent tree at $out/share/ so the activation script can
          # `uv pip install` it at runtime. hermes-agent's own installPhase
          # runs after buildPhase (per stdenv's phase order), so the wheel
          # is already in $out by the time it executes.
          installPhase = (old.installPhase or "") + ''
            mkdir -p $out/share/hindsight-wheel
            cp ${hindsightWheel}/*.whl $out/share/hindsight-wheel/ || true
            cp ${hindsightClientWheel}/*.whl $out/share/hindsight-wheel/ || true
            cp ${hindsightEmbedWheel}/*.whl $out/share/hindsight-wheel/ || true
            ls -l $out/share/hindsight-wheel/
          '';
        });

      nixosConfigurations = {
        somehost = mkHost "somehost";
        aleroza-pc = mkHost "aleroza-pc";
      };
    };
}