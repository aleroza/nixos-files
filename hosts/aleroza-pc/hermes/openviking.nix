# OpenViking memory plugin for Hermes Agent — declarative install via Nix store.
#
# Why this lives here (mirrors hosts/aleroza-pc/hermes/aphrodite.nix):
#
#   The upstream plugin loader `hermes plugins install openviking` shells out
#   to `uv` to fetch and link the plugin's Python dependencies (httpx, etc).
#   Under NixOS, uv's repo_root() resolves into the read-only
#   `/nix/store/<hash>-hermes-agent-*/lib/python3.14/site-packages/` and
#   expects `uv.lock` to live there. It does not — uv.lock is a git-tree
#   artifact, not a Nix-store artifact — so the install aborts with
#   `FileNotFoundError: '.../site-packages/uv.lock'` and the gateway
#   prints:
#
#     ⚠ Memory provider 'openviking' moved out of core and could not be
#       installed automatically: ... Run `hermes plugins install openviking`.
#
#   We sidestep uv entirely by copying the plugin's `__init__.py` and
#   `plugin.yaml` straight from the same NousResearch/hermes-agent flake
#   input the host already pins (rev a871948d, sha256 taken from
#   flake.lock). The Python dependency `httpx` is added to the hermes
#   venv via `package.overrideAttrs { extraPythonPackages = [ pkgs.httpx ]; }`
#   in hosts/aleroza-pc/hermes/default.nix — that keeps the plugin
#   importable without a writable uv-managed venv.
#
# What this module does:
#
#   1. Fetches the pinned NousResearch/hermes-agent source as a Nix-store
#      derivation (sha256 must match flake.lock's hermes-agent entry —
#      `nix flake lock --update-input hermes-agent` will refresh both).
#   2. Activation script lays down `~/.hermes/plugins/openviking/` as a
#      REAL directory (not a symlink to /nix/store), owned by
#      hermes:hermes, mode 0750, with:
#        - plugin.yaml — symlink to the store source
#        - __init__.py — COPY (not symlink). The plugin loader resolves
#          `Path(__file__).resolve().parent` to locate sibling files;
#          if __init__.py is a symlink to /nix/store, .resolve() follows
#          it and `import` / `register_memory_provider` calls run with
#          the wrong `__file__` context. aphrodite.nix documents the
#          same pitfall at length.
#   3. Idempotent: each step gates on current state, safe to re-run on
#      every activation; cheap.
#
# What this module does NOT do:
#
#   - Add httpx to the venv. Done in default.nix via extraPythonPackages.
#   - Touch /opt/openviking/. The OpenViking SERVER container is
#     configured by modules/services/openviking.nix; this module just
#     wires the Hermes CLIENT plugin to that server.
#   - Touch ~/.hermes/config.yaml. `services.hermes-agent.settings.memory
#     .provider = "openviking"` is already set in default.nix; the
#     loader finds the plugin via `find_provider_dir("openviking")`
#     which walks $HERMES_HOME/plugins/.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Pinned NousResearch/hermes-agent source. rev + sha256 are taken
  # verbatim from this repo's flake.lock (hermes-agent input). Any
  # `nix flake update` that bumps hermes-agent must also bump the
  # rev/sha256 pair here, and a `git grep sha256-lLuG+` will surface
  # this file as the only consumer.
  pluginSrc = pkgs.fetchFromGitHub {
    owner = "NousResearch";
    repo = "hermes-agent";
    rev = "a871948d8d4b0f774d4ec40467bab1078a9f28d5";
    sha256 = "sha256-lLuG+syp2+HkW4N4EyxNpUM/lCjBSqSvDak6ujslWzo=";
  };

  hermesHome = "/var/lib/hermes";
in
{
  config = {

    # Activation lays down the plugin tree at a known path.
    #
    #   /var/lib/hermes/.hermes/plugins/openviking/        (real dir, 0750 hermes:hermes)
    #     ├── plugin.yaml                                  -> ${pluginSrc}/.../openviking/plugin.yaml
    #     └── __init__.py                                  =  ${pluginSrc}/.../openviking/__init__.py (copy)
    #
    # Tolerates /var/lib/hermes being absent: services.hermes-agent's
    # own activation creates the user + home before this script runs
    # (deps = [ "hermes-agent-setup" ]).
    system.activationScripts."openviking-plugin" = {
      deps = [ "hermes-agent-setup" ];
      text = ''
        set -euo pipefail

        PLUGIN_SRC='${pluginSrc}'
        PLUGIN_DIR=${hermesHome}/.hermes/plugins/openviking

        # ────────────────────────────────────────────────────────
        # Plugin directory. MUST be a real directory, not a symlink
        # to /nix/store — the Python loader resolves
        # Path(__file__).resolve().parent and looks for sibling files
        # there. A symlink to a read-only store path makes that
        # resolution point at the store, where register_memory_provider
        # is called from a path the gateway considers foreign.
        #
        # If PLUGIN_DIR is a stale symlink to a store path from a
        # previous version of this module, remove it and replace with
        # a real directory.
        # ────────────────────────────────────────────────────────
        if [[ -L "$PLUGIN_DIR" ]]; then
          rm -f "$PLUGIN_DIR"
        fi
        if [[ ! -d "$PLUGIN_DIR" ]]; then
          mkdir -p "$PLUGIN_DIR"
        fi
        chown hermes:hermes "$PLUGIN_DIR"
        chmod 0750 "$PLUGIN_DIR"

        # ────────────────────────────────────────────────────────
        # plugin.yaml. Symlink to the store source (loader just
        # parses it for metadata).
        # ────────────────────────────────────────────────────────
        yaml_link="$PLUGIN_DIR/plugin.yaml"
        yaml_src="$PLUGIN_SRC/plugins/memory/openviking/plugin.yaml"
        if [[ ! -L "$yaml_link" ]] || [[ "$(readlink -f "$yaml_link")" != "$yaml_src" ]]; then
          ln -sfn "$yaml_src" "$yaml_link"
        fi
        chown -h hermes:hermes "$yaml_link"
        chmod -h 0644 "$yaml_link"

        # ────────────────────────────────────────────────────────
        # __init__.py. COPIED (not symlinked) so Path(__file__)
        # .resolve() inside the Python loader sees the real
        # /var/lib/hermes/.hermes/plugins/openviking/ as the plugin
        # directory. Idempotent: copy only if missing, symlinked-to-
        # wrong-target, or stale (size mismatch with source).
        # ────────────────────────────────────────────────────────
        init_dest="$PLUGIN_DIR/__init__.py"
        init_src="$PLUGIN_SRC/plugins/memory/openviking/__init__.py"
        need_copy=0
        if [[ ! -e "$init_dest" ]]; then
          need_copy=1
        elif [[ -L "$init_dest" ]]; then
          # A symlink here breaks Path.resolve() — remove and replace.
          rm -f "$init_dest"
          need_copy=1
        else
          src_size=$(stat -c%s "$init_src" 2>/dev/null || echo 0)
          dst_size=$(stat -c%s "$init_dest" 2>/dev/null || echo 0)
          if [[ "$src_size" != "$dst_size" ]] || [[ "$src_size" -eq 0 ]]; then
            need_copy=1
          fi
        fi
        if [[ "$need_copy" -eq 1 ]]; then
          cp -f "$init_src" "$init_dest"
        fi
        chown hermes:hermes "$init_dest"
        chmod 0644 "$init_dest"

        echo "openviking-plugin: $PLUGIN_DIR/ (real, hermes:hermes 0750)"
        echo "openviking-plugin:   -> $PLUGIN_SRC (plugin.yaml symlinked, __init__.py copied)"
      '';
    };
  };
}