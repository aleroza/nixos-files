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

  # Files from the plugin source we want to install into
  # ~/.hermes/plugins/aphrodite/. The Python loader resolves
  # `Path(__file__).resolve().parent` to find binaries/ — and
  # `.resolve()` follows symlinks. So __init__.py MUST be a real
  # file (or hardlink) in the plugin directory, otherwise the
  # loader thinks _PLUGIN_DIR lives in /nix/store/... and tries
  # to open /nix/store/.../binaries/libaphrodite_hermes.so (which
  # doesn't exist there), giving up with 'Dylib not found'.
  #
  # Everything else can stay as a symlink — plugin.yaml is just
  # parsed, download.sh / README.md / BINARY_VERSION are never
  # read by the loader. .git/ stays in the store only (we don't
  # ship it to the plugin dir; humans use the /var/lib/hermes/
  # Aphrodite-Hermes clone-mirror for that).
  pluginFiles = [
    "plugin.yaml"
    "BINARY_VERSION"
    "download.sh"
    "download.ps1"
    "README.md"
  ];

  # Python source files: copied (not symlinked) so Path(__file__)
  # resolves to the real plugin directory.
  pythonFiles = [
    "__init__.py"
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
        # -h: target the symlink itself, not its read-only store
        # target. Without -h, chmod on a symlink-to-store-path
        # fails with "Read-only file system" and the whole
        # activate script aborts (set -e).
        chmod -h 0755 "$CLONE_PATH"

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
          # -h: chmod the symlink, not the read-only store target.
          chmod -h 0644 "$PLUGIN_DIR/${f}"
        '') pluginFiles}

        # ────────────────────────────────────────────────────────
        # Python source files. COPIED (not symlinked) so
        # Path(__file__).resolve() inside the Python loader sees
        # the real /var/lib/hermes/.hermes/plugins/aphrodite/ as
        # the plugin directory — otherwise it follows the
        # symlink into /nix/store/.../source and tries to find
        # binaries/ relative to a path that has no binaries/
        # subdirectory, giving up with 'Dylib not found'.
        #
        # Idempotent: copy only if the existing file is a
        # symlink-to-wrong-target, missing, or stale (different
        # size from the source). Plain `cp` overwrites
        # unconditionally; we use the size-mismatch gate to
        # avoid clobbering user edits inside __init__.py.
        # ────────────────────────────────────────────────────────
        ${lib.concatMapStrings (f: ''
          dest="$PLUGIN_DIR/${f}"
          src="$PLUGIN_SRC/${f}"
          need_copy=0
          if [[ ! -e "$dest" ]]; then
            need_copy=1
          elif [[ -L "$dest" ]]; then
            # A symlink here is wrong (would break Path.resolve()).
            # Remove and replace with a real file.
            rm -f "$dest"
            need_copy=1
          else
            src_size=$(stat -c%s "$src" 2>/dev/null || echo 0)
            dst_size=$(stat -c%s "$dest" 2>/dev/null || echo 0)
            if [[ "$src_size" != "$dst_size" ]] || [[ "$src_size" -eq 0 ]]; then
              need_copy=1
            fi
          fi
          if [[ "$need_copy" -eq 1 ]]; then
            cp -f "$src" "$dest"
          fi
          chown hermes:hermes "$dest"
          chmod 0644 "$dest"
        '') pythonFiles}

        # ────────────────────────────────────────────────────────
        # Binaries subdirectory + two binaries. Copied (not
        # symlinked) because the plugin's _start_proxy() does
        # `os.chmod(binary, 0o755)` when os.access(binary, X_OK)
        # fails — and chmod follows symlinks, so a symlinked
        # binary pointing at /nix/store/<hash>-bin would fail
        # with [Errno 30] Read-only file system against the
        # immutable store target.
        #
        # The .so stays small enough (74 MB total for both) that
        # duplicating it on disk instead of in the store is fine.
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
          # Decide whether we need to (re-)copy. Real file of
          # matching size == up to date. Symlink, missing file,
          # or size mismatch == needs copy.
          need_copy=0
          if [[ ! -e "$dest" ]]; then
            need_copy=1
          elif [[ -L "$dest" ]]; then
            rm -f "$dest"
            need_copy=1
          else
            src_size=$(stat -c%s "$src" 2>/dev/null || echo 0)
            dst_size=$(stat -c%s "$dest" 2>/dev/null || echo 0)
            if [[ "$src_size" != "$dst_size" ]] || [[ "$src_size" -eq 0 ]]; then
              need_copy=1
            fi
          fi
          if [[ "$need_copy" -eq 1 ]]; then
            cp -f "$src" "$dest"
          fi
          chown hermes:hermes "$dest"
          # Plain chmod (no -h): dest is a real file now, not a
          # symlink, so chmod mutates the file itself.
          chmod 0755 "$dest"
        done

        echo "aphrodite-plugin: $PLUGIN_DIR/ (real, hermes:hermes 0750)"
        echo "aphrodite-plugin:   -> $PLUGIN_SRC (plugin files)"
        echo "aphrodite-plugin: $BIN_DIR/aphrodite -> $PROXY_BIN"
        echo "aphrodite-plugin: $BIN_DIR/libaphrodite_hermes.so -> $PROXY_DYLIB"

        # ────────────────────────────────────────────────────────
        # Aphrodite proxy config (aphrodite.toml).
        #
        # The proxy binary reads this from:
        #   $APHRODITE_CONFIG_PATH (if set), else
        #   ./aphrodite.toml, else ~/.hermes/aphrodite/aphrodite.toml
        # Priority: env var > TOML > hardcoded default.
        #
        # We write to the second default path. The plugin's
        # _start_proxy() does `subprocess.Popen([binary],
        # env=os.environ.copy())` — the proxy inherits hermes-agent's
        # env. We don't bake APHRODITE_API_KEY into the systemd unit
        # env (avoid leaking it via /proc/<pid>/environ), but the
        # TOML is on disk anyway with mode 0640 owner hermes — the
        # API key is in /run/secrets/hermes/env (mode 0400 hermes)
        # to start with, so on-disk TOML is no worse.
        #
        # The proxy resolves ~ via its own getpwuid()->pw_dir. The
        # systemd unit sets HOME=/var/lib/hermes for hermes-agent,
        # so the on-disk path the proxy opens is
        # /var/lib/hermes/.hermes/aphrodite/aphrodite.toml.
        #
        # api_url is the upstream MiniMax endpoint (NOT
        # api.minimaxi.com — that's a parking page).
        #
        # Two proxies per the Aphrodite README: `cache` on :9797
        # (in-memory CCR, ephemeral) and `token` on :9798 (SQLite,
        # persistent). Hermes routes via :9798.
        # ────────────────────────────────────────────────────────
        APHRODITE_CONFIG_DIR=/var/lib/hermes/.hermes/aphrodite
        APHRODITE_CONFIG=$APHRODITE_CONFIG_DIR/aphrodite.toml

        if [[ ! -d "$APHRODITE_CONFIG_DIR" ]]; then
          mkdir -p "$APHRODITE_CONFIG_DIR"
        fi
        chown hermes:hermes "$APHRODITE_CONFIG_DIR"
        chmod 0750 "$APHRODITE_CONFIG_DIR"

        # Read MINIMAX_API_KEY from the sops-rendered secret.
        # The activation script runs as root (NixOS's bash wrapper
        # around ExecStartPre/activationScripts), so the file at
        # /run/secrets/hermes/env (mode 0400 owner hermes) is
        # readable thanks to root bypass. After rendering, the
        # resulting TOML is mode 0640 owner hermes:hermes — only
        # hermes can read it, which is fine because the proxy
        # runs as hermes.
        KEY_FILE=/run/secrets/hermes/env
        if [[ ! -f "$KEY_FILE" ]]; then
          echo "aphrodite-plugin: WARNING: $KEY_FILE not found, " >&2
          echo "aphrodite-plugin: proxy will fail with 'no API key configured'" >&2
        else
          API_KEY=$(grep '^MINIMAX_API_KEY=' "$KEY_FILE" | head -1 | cut -d= -f2-)
          if [[ -z "$API_KEY" ]]; then
            echo "aphrodite-plugin: WARNING: MINIMAX_API_KEY empty in $KEY_FILE" >&2
          else
            cat > "$APHRODITE_CONFIG" <<TOML_EOF
        # Generated by hosts/aleroza-pc/hermes/aphrodite.nix — do not edit.
        # Re-run switch to regenerate after sops secret rotation.

        [[proxies]]
        name = "cache"
        listen = "127.0.0.1:9797"
        mode = "cache"
        tool_relay = true
        timeout = 120

        [[proxies]]
        name = "token"
        listen = "127.0.0.1:9798"
        mode = "token"
        tool_relay = true
        timeout = 300

        [defaults]
        api_url = "https://api.minimax.io"
        model = "MiniMax-M3"
        api_key = "$API_KEY"
        ccr_ttl_seconds = 3600

        [compression]
        engine_threshold_pct = 55
        engine_protect_first = 2
        engine_protect_last = 5
        engine_min_msgs = 16
        tool_threshold_token = 512
        tool_threshold_cache = 4096
        terminal_threshold = 1024
        inline_threshold = 2048
        auto_expand = false
        auto_expand_limit = 0
        catalog_mode = "tool"
        classifier_poll = true
        code_multiplier = 3.0
        context_engine = true
        prefetch = true

        [previews]
        model_family = "code_first"
        code_structure_map = true
        preview_max_chars = 120

        [prompts]
        retrieve_guidance = "verbose"
        ccr_marker_hint = true
        catalog_intent_hints = true
        TOML_EOF
            chown hermes:hermes "$APHRODITE_CONFIG"
            chmod 0640 "$APHRODITE_CONFIG"
            echo "aphrodite-plugin: $APHRODITE_CONFIG (mode 0640 hermes:hermes)"
          fi
        fi
      '';
    };

  };
}