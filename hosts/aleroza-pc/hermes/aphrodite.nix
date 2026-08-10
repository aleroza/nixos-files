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
#      (Python wrapper + plugin.yaml + __init__.py + download.sh)
#      as a Nix store derivation. Pin: v2.0.7.
#   2. Fetches the two prebuilt release binaries from the Aphrodite
#      monorepo (companion release Aphrodite/v1.3.8):
#        - aphrodite-x86_64-unknown-linux-gnu          (proxy binary)
#        - libaphrodite_hermes-x86_64-unknown-linux-gnu.so (cdylib)
#      Both sha256 verified against
#      https://github.com/PlayForm/Aphrodite/releases/download/Aphrodite%2Fv1.3.8/SHA256SUMS-x86_64-unknown-linux-gnu.txt
#   3. Activation script lays down the plugin files (symlinks to
#      store paths) and the binaries (symlinks to store paths) under
#      ~/.hermes/plugins/aphrodite/ as a real directory owned by
#      hermes:hermes, mode 0750 (dirs) / 0755 (binaries).
#
#      The directory is real, NOT a symlink to a store path. The
#      plugin's __init__.py resolves _PLUGIN_DIR via
#      Path(__file__).resolve().parent and then looks for
#      binaries/ as a subdirectory of that. If _PLUGIN_DIR itself
#      is a symlink to a read-only store path, the dlopen() of
#      binaries/libaphrodite_hermes.so fails with ENOENT — the
#      store has no binaries/ subdirectory. So the real directory
#      is mandatory, and only the files inside it are symlinks.
#
#      /var/lib/hermes/Aphrodite-Hermes is a clone-mirror symlink
#      to the store source (humans + download.sh's monorepo probe
#      use this path).
#
# What this module does NOT do:
#   - Start the proxy. The plugin's __init__.py spawns the binary
#     on first tool call. We rely on that.
#   - Touch ~/.hermes/config.yaml. Plugin discovery is automatic
#     from ~/.hermes/plugins/* — no settings.plugins.* wiring needed.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Plugin source — PlayForm/Aphrodite-Hermes, pinned to v2.0.7.
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

  # Files from the plugin source we want to symlink into
  # ~/.hermes/plugins/aphrodite/. We don't want everything in the
  # store path (.git/ is ~5MB of git metadata) — just what the
  # plugin needs to load + a couple of supporting files.
  pluginFiles = [
    "plugin.yaml"
    "__init__.py"
    "BINARY_VERSION"
    "download.sh"
    "download.ps1"
    "README.md"
  ];

  hermesHome = "/var/lib/hermes";
in
{
  config = {

    # ▸ Activation: lay down plugin tree + binaries at known paths.
    #
    #    /var/lib/hermes/Aphrodite-Hermes                       -> ${pluginSrc}
    #    /var/lib/hermes/.hermes/plugins/aphrodite/             (real dir, 0750 hermes:hermes)
    #      ├── plugin.yaml, __init__.py, BINARY_VERSION, ...    -> ${pluginSrc}/<file>
    #      └── binaries/                                         (real subdir, 0750 hermes:hermes)
    #          ├── aphrodite                                    -> ${proxyBin}
    #          └── libaphrodite_hermes.so                       -> ${proxyDylib}
    #
    #    ~/.hermes/plugins/aphrodite/ MUST be a real directory,
    #    not a symlink. The plugin's __init__.py uses
    #    Path(__file__).resolve().parent as _PLUGIN_DIR and then
    #    opens binaries/libaphrodite_hermes.so relative to it.
    #    If _PLUGIN_DIR is a symlink to a read-only store path,
    #    the dlopen() fails with ENOENT (the store has no
    #    binaries/ subdirectory).
    #
    # Idempotent: each step checks the target's current state and
    # only writes when it differs. Safe to re-run on every
    # activation; cheap.
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

        # ────────────────────────────────────────────────────────
        # Clone mirror. Symlink (not copy). Used by humans + the
        # plugin's download.sh which auto-probes Cargo.toml
        # versions from the surrounding monorepo if present.
        #
        # If CLONE_PATH is a real directory from a previous
        # dev-mode checkout, back it up so we don't silently
        # nuke human edits. (Recurring switch from dev → Nix
        # flow tends to leave old checkouts.)
        # ────────────────────────────────────────────────────────
        if [[ -L "$CLONE_PATH" ]]; then
          if [[ "$(readlink -f "$CLONE_PATH")" != "$PLUGIN_SRC" ]]; then
            ln -sfn "$PLUGIN_SRC" "$CLONE_PATH"
          fi
        elif [[ -e "$CLONE_PATH" ]]; then
          mv "$CLONE_PATH" "''${CLONE_PATH}.bak.$(date +%s)"
          ln -sfn "$PLUGIN_SRC" "$CLONE_PATH"
        else
          mkdir -p "$(dirname "$CLONE_PATH")"
          ln -sfn "$PLUGIN_SRC" "$CLONE_PATH"
        fi
        chown -h hermes:hermes "$CLONE_PATH"
        chmod 0755 "$CLONE_PATH"

        # ────────────────────────────────────────────────────────
        # Plugin directory. MUST be a real directory (the plugin
        # resolves _PLUGIN_DIR = Path(__file__).resolve().parent
        # and then opens binaries/ relative to it — a symlink to
        # the read-only store path makes that impossible).
        #
        # If PLUGIN_DIR is a symlink to a store path from a
        # previous version of this module, remove it and replace
        # with a real directory.
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
        # Plugin files. Symlinks to the store source. The list is
        # explicit (not a glob) so we don't pull .git/ (~5MB) or
        # stale __pycache__/ (.pyc blobs) into the loader path.
        # ────────────────────────────────────────────────────────
        ${lib.concatMapStrings (f: ''
          if [[ ! -L "$PLUGIN_DIR/${f}" ]] || [[ "$(readlink -f "$PLUGIN_DIR/${f}")" != "$PLUGIN_SRC/${f}" ]]; then
            ln -sfn "$PLUGIN_SRC/${f}" "$PLUGIN_DIR/${f}"
          fi
          chown -h hermes:hermes "$PLUGIN_DIR/${f}"
          chmod 0644 "$PLUGIN_DIR/${f}"
        '') pluginFiles}

        # ────────────────────────────────────────────────────────
        # Binaries subdirectory + two binary symlinks. Mode 0755
        # on the binaries themselves (the .so is dlopen'd as
        # code, the proxy is exec'd).
        # ────────────────────────────────────────────────────────
        if [[ ! -d "$BIN_DIR" ]]; then
          mkdir -p "$BIN_DIR"
        fi
        chown hermes:hermes "$BIN_DIR"
        chmod 0750 "$BIN_DIR"

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

        echo "aphrodite-plugin: $PLUGIN_DIR/ (real, hermes:hermes 0750)"
        echo "aphrodite-plugin:   -> $PLUGIN_SRC (plugin files)"
        echo "aphrodite-plugin: $BIN_DIR/aphrodite -> $PROXY_BIN"
        echo "aphrodite-plugin: $BIN_DIR/libaphrodite_hermes.so -> $PROXY_DYLIB"
      '';
    };

  };
}