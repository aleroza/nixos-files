# Aphrodite plugin for Hermes Agent — declarative install via Nix store.
#
# Why this lives here (not in modules/services/aphrodite.nix):
#   The previous design ran the proxy as a standalone systemd unit
#   (aphrodite-proxy.service). That required its own sops secret
#   (aphrodite/MINIMAX_API_KEY), its own TOML renderer, and its own
#   lifecycle plumbing. Hermes is already the orchestrator of the
#   proxy via the PlayForm/Aphrodite-Hermes plugin — the plugin
#   spawns the proxy binary as a subprocess on first tool call and
#   reuses the same secret the gateway already has.
#
#   Standalone systemd added operational weight without saving any
#   complexity: gateway restart still has to coordinate with the
#   proxy's lifecycle, the sops secret was only read by preStart, and
#   the rendered TOML was identical to what the plugin generates.
#   The systemd unit is removed; this file replaces it.
#
# What this module does:
#   1. Fetches the PlayForm/Aphrodite-Hermes plugin source tree
#      (Python wrapper + plugin.yaml + __init__.py) as a Nix store
#      derivation. Pin: v2.0.7 (sha256 verified against upstream).
#   2. Fetches the two prebuilt release binaries from the Aphrodite
#      monorepo (companion release Aphrodite/v1.3.8):
#        - aphrodite-x86_64-unknown-linux-gnu          (proxy binary)
#        - libaphrodite_hermes-x86_64-unknown-linux-gnu.so (cdylib)
#      Both sha256 verified against
#      https://github.com/PlayForm/Aphrodite/releases/download/Aphrodite%2Fv1.3.8/SHA256SUMS-x86_64-unknown-linux-gnu.txt
#   3. Activation script symlinks the store path into
#        /var/lib/hermes/Aphrodite-Hermes        (plugin source)
#        /var/lib/hermes/.hermes/plugins/aphrodite/binaries/aphrodite
#        /var/lib/hermes/.hermes/plugins/aphrodite/binaries/libaphrodite_hermes.so
#      …so the Python loader in the gateway can find everything by
#      the conventional names. Ownership: hermes:hermes, mode 0750
#      on directories, 0755 on binaries (the .so is dlopen'd as
#      code, not just read).
#
# What this module does NOT do:
#   - Start the proxy. The plugin's __init__.py spawns the binary
#     on first tool call (see aphrodite-launch in
#     PlayForm/Aphrodite-Hermes/__init__.py). We rely on that.
#   - Touch ~/.hermes/config.yaml. Plugin activation is driven by
#     the existing services.hermes-agent.extraPlugins wiring in
#     hosts/aleroza-pc/hermes/default.nix, which symlinks the
#     plugin source into ~/.hermes/plugins/nix-managed-aphrodite.
#     We additionally drop a *bare* name symlink
#     ~/.hermes/plugins/aphrodite -> the same store path so
#     interactive `bash download.sh` (from the plugin's own dir)
#     works without changing directory, and so the plugin's
#     BINARY_VERSION path resolution finds the binaries even if
#     the gateway loader's path differs.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Plugin source — PlayForm/Aphrodite-Hermes, pinned to v2.0.7.
  # sha256 from `nix-prefetch-github --rev v2.0.7 PlayForm Aphrodite-Hermes`.
  pluginSrc = pkgs.fetchFromGitHub {
    owner = "PlayForm";
    repo = "Aphrodite-Hermes";
    rev = "v2.0.7";
    sha256 = "sha256-UTDRotOfw13Cvisg6Uerp5nh4fU19VXREU5H6fBANFQ=";
  };

  # Companion proxy + dylib from PlayForm/Aphrodite (monorepo).
  # Pinned to Aphrodite/v1.3.8 (latest). The plugin's BINARY_VERSION
  # file says 1.3.5, but the plugin's Python wrapper is forward-
  # compatible across all v1.3.x dylibs (pure FFI surface, no
  # version-gated ABI), and v1.3.8 ships both Linux + Windows +
  # macOS + SHA256SUMS in one release (older tags are partial).
  # shas verified against
  #   https://github.com/PlayForm/Aphrodite/releases/download/Aphrodite%2Fv1.3.8/SHA256SUMS-x86_64-unknown-linux-gnu.txt
  proxyBin = pkgs.fetchurl {
    url = "https://github.com/PlayForm/Aphrodite/releases/download/Aphrodite%2Fv1.3.8/aphrodite-x86_64-unknown-linux-gnu";
    sha256 = "b2f3d71536c7291263b542bed5ff90b6d9271b4b2552369df5c3707e992caa18";
  };
  proxyDylib = pkgs.fetchurl {
    url = "https://github.com/PlayForm/Aphrodite/releases/download/Aphrodite%2Fv1.3.8/libaphrodite_hermes-x86_64-unknown-linux-gnu.so";
    sha256 = "286a9866de0abe95c358037db2a25f6d21a36d52e2d503252879a32fcf99c82b";
  };

  # Hermes user owns the plugin tree. The activation script runs as
  # root and chowns to hermes:hermes so the gateway (running as
  # User=hermes) can dlopen the .so and execute the proxy binary
  # without permission errors.
  hermesHome = "/var/lib/hermes";
in
{
  # No options declared — this is a leaf module that activates
  # unconditionally when imported. Kept that way because the plugin
  # is part of the hermes-agent stack on this host; if a future
  # host doesn't want it, don't import this file.

  config = {

    # ▸ Activation: lay down plugin tree + binaries at known paths.
    #
    #    /var/lib/hermes/Aphrodite-Hermes        -> ${pluginSrc}
    #      (clone-mirror path — git-style; used by humans + the
    #       plugin's own download.sh for re-resolving binaries)
    #
    #    /var/lib/hermes/.hermes/plugins/aphrodite -> ${pluginSrc}
    #      (loader path; bare name "aphrodite" so `bash download.sh`
    #       in $SCRIPT_DIR/.. finds binaries/ next to itself)
    #
    #    /var/lib/hermes/.hermes/plugins/aphrodite/binaries/aphrodite
    #      -> ${proxyBin}
    #    /var/lib/hermes/.hermes/plugins/aphrodite/binaries/libaphrodite_hermes.so
    #      -> ${proxyDylib}
    #
    #    All four owned by hermes:hermes, mode 0750 (dirs) / 0755
    #    (binaries + dylib). The .so is dlopen'd as code; the proxy
    #    binary is exec'd; both need the execute bit.
    #
    # Idempotent: each step checks for the target symlink's
    # existence and skips if it already points at the right store
    # path. Cheap to re-run on every activation.
    #
    # Also tolerates /var/lib/hermes being absent: services.hermes-
    # agent's own activation creates the user + home before this
    # script runs (deps = [ "hermes-agent-setup" ]).
    system.activationScripts."aphrodite-plugin" = {
      deps = [ "hermes-agent-setup" ];
      text = ''
        set -euo pipefail

        PLUGIN_SRC='${pluginSrc}'
        PROXY_BIN='${proxyBin}'
        PROXY_DYLIB='${proxyDylib}'

        CLONE_PATH=${hermesHome}/Aphrodite-Hermes
        PLUGIN_DIR=${hermesHome}/.hermes/plugins/aphrodite
        BIN_DIR="$PLUGIN_DIR/binaries"

        # Top-level clone mirror. Used by humans and by the plugin's
        # own download.sh (which auto-detects Cargo.toml versions
        # from the surrounding monorepo if present). Symlink, not
        # copy — keeps the closure lean and avoids drift.
        if [[ ! -L "$CLONE_PATH" ]] || [[ "$(readlink -f "$CLONE_PATH")" != "$PLUGIN_SRC" ]]; then
          mkdir -p "$(dirname "$CLONE_PATH")"
          ln -sfn "$PLUGIN_SRC" "$CLONE_PATH"
        fi
        chown -h hermes:hermes "$CLONE_PATH"
        chmod 0755 "$CLONE_PATH"

        # Plugin directory the gateway's loader looks at. Bare name
        # "aphrodite" so `bash $PLUGIN_DIR/download.sh` (run from
        # the plugin's own dir) drops binaries into $PLUGIN_DIR/
        # binaries/ correctly. The NixOS hermes-agent module also
        # symlinks this same source into ~/.hermes/plugins/nix-
        # managed-aphrodite — both paths point at the same store
        # path, so no duplication.
        mkdir -p "$BIN_DIR"
        # Symlink the plugin directory itself to the source tree so
        # plugin.yaml / __init__.py / download.sh live next to
        # binaries/. The store source already has plugin.yaml +
        # __init__.py at its root; we only need to add binaries/.
        if [[ ! -L "$PLUGIN_DIR" ]] || [[ "$(readlink -f "$PLUGIN_DIR")" != "$PLUGIN_SRC" ]]; then
          # If $PLUGIN_DIR is a real dir from a previous install
          # (e.g. dev-mode plugin checkout), back it up so we don't
          # silently nuke human edits. Idempotent: only swaps on a
          # mismatch between current symlink target and $PLUGIN_SRC.
          if [[ -e "$PLUGIN_DIR" ]] && [[ ! -L "$PLUGIN_DIR" ]]; then
            mv "$PLUGIN_DIR" "''${PLUGIN_DIR}.bak.$(date +%s)"
          fi
          ln -sfn "$PLUGIN_SRC" "$PLUGIN_DIR"
        fi

        # Binaries. Symlinks (not copies) so updates from the Nix
        # store propagate on next activation without per-file sync.
        for pair in \
          "aphrodite::$PROXY_BIN" \
          "libaphrodite_hermes.so::$PROXY_DYLIB" \
        ; do
          name="''${pair%%::*}"
          src="''${pair##*::}"
          dest="$BIN_DIR/$name"
          if [[ ! -L "$dest" ]] || [[ "$(readlink -f "$dest")" != "$src" ]]; then
            ln -sfn "$src" "$dest"
          fi
          chown -h hermes:hermes "$dest"
          chmod 0755 "$dest"
        done

        # Belt-and-suspenders ownership on the whole plugin tree.
        # Covers the case where a previous install left real
        # directories behind (the .bak.<ts> above gets chown'd too
        # so the user can inspect it without sudo).
        chown -R hermes:hermes "$PLUGIN_DIR" || true
        chmod -R u+rwX,g+rX,o-rwx "$PLUGIN_DIR" || true

        echo "aphrodite-plugin: $PLUGIN_DIR -> $PLUGIN_SRC"
        echo "aphrodite-plugin: $BIN_DIR/aphrodite -> $PROXY_BIN"
        echo "aphrodite-plugin: $BIN_DIR/libaphrodite_hermes.so -> $PROXY_DYLIB"
      '';
    };

  };
}