# Home-manager module for Aphrodite integration with Hermes Agent.
#
# What it does:
#   1. Installs the PlayForm/Aphrodite-Hermes plugin at
#      ~/.hermes/plugins/aphrodite (symlink into the Nix store).
#      On first Hermes launch the plugin auto-loads its dylib +
#      proxy binary from the binaries/ subdir we ship here.
#   2. Drops the prebuilt aphrodite proxy binary and the Hermes
#      dylib into ~/.hermes/plugins/aphrodite/binaries/, so the
#      plugin can dlopen them on startup without needing to
#      fetch from GitHub Releases.
#   3. Ships a Hermes profile `aphrodite` that routes through
#      127.0.0.1:9798 → MiniMax.
#
# The systemd proxy unit lives in modules/services/aphrodite.nix
# and starts on the host independently of home-manager. The
# plugin here gives the gateway its tools and context engine;
# the systemd unit supplies the proxy process itself.

{ config, lib, auto, pkgs, ... }:

let
  cfg = auto.aphrodite;

  # Pin to PlayForm/Aphrodite-Hermes v2.0.7 (matches the release
  # tag fetched below). Update both together — the plugin's
  # plugin.yaml declares a min_hermes_version that the gateway
  # checks at load time.
  plugin = pkgs.fetchFromGitHub {
    owner = "PlayForm";
    repo = "Aphrodite-Hermes";
    rev = "v2.0.7";
    sha256 = "sha256-UTDRotOfw13Cvisg6Uerp5nh4fU19VXREU5H6fBANFQ=";
  };

  # The proxy binary used by services.aphrodite (systemd) is the
  # same one the plugin's __init__.py dlopen-equivalent code
  # looks for under binaries/. We fetch from the same upstream
  # release (PlayForm/Aphrodite v1.3.8) with the same SHA256 the
  # NixOS module uses, so there is exactly one binary on disk.
  aphroditeBinary = pkgs.fetchurl {
    url = "https://github.com/PlayForm/Aphrodite/releases/download/Aphrodite/v1.3.8/aphrodite-x86_64-unknown-linux-gnu";
    sha256 = "b2f3d71536c7291263b542bed5ff90b6d9271b4b2552369df5c3707e992caa18";
  };

  # The Hermes plugin dylib (libaphrodite_hermes.so) — a different
  # artifact from the proxy binary, published in the same release
  # under a different asset name.
  aphroditeHermesDylib = pkgs.fetchurl {
    url = "https://github.com/PlayForm/Aphrodite/releases/download/Aphrodite/v1.3.8/libaphrodite_hermes-x86_64-unknown-linux-gnu.so";
    sha256 = "286a9866de0abe95c358037db2a25f6d21a36d52e2d503252879a32fcf99c82b";
  };
in
{
  config = lib.mkIf (cfg.enable or false) {

    home.sessionVariables = {
      APHRODITE_CONFIG_PATH = "$HOME/.hermes/aphrodite/aphrodite.toml";
    };

    # The plugin checkout. home.file with source=pkgs.fetchFromGitHub
    # creates a regular file copy under the path — not a symlink.
    # That works because Hermes's plugin loader imports the
    # __init__.py directly; it does not require a live symlink.
    home.file.".hermes/plugins/aphrodite" = {
      source = plugin;
      recursive = true;
      # Don't clobber user edits to plugin.yaml etc. on re-deploy.
      force = false;
    };

    # The plugin's __init__.py looks for these two files at:
    #   ~/.hermes/plugins/aphrodite/binaries/aphrodite
    #   ~/.hermes/plugins/aphrodite/binaries/libaphrodite_hermes.so
    # We drop them in directly via home.file (single-file copy).
    # The .binaries/ path is created implicitly by the file sources.
    home.file.".hermes/plugins/aphrodite/binaries/aphrodite" = {
      source = aphroditeBinary;
      executable = true;
    };
    home.file.".hermes/plugins/aphrodite/binaries/libaphrodite_hermes.so" = {
      source = aphroditeHermesDylib;
    };

    # Directory for user overrides of the rendered TOML and the
    # CCR store. The proxy unit uses /opt/aphrodite/ as its
    # data dir (HOME=/opt/aphrodite), but the plugin can write
    # ~/.hermes/aphrodite/ for user-side state.
    home.file.".hermes/aphrodite/.keep" = {
      text = "";
    };

    # Hermes profile for running through the Aphrodite proxy.
    # base_url points to the systemd-managed proxy on :9798.
    home.file.".hermes/profiles/aphrodite/config.yaml".force = true;
    home.file.".hermes/profiles/aphrodite/config.yaml".text = ''
      # Hermes profile for working through the Aphrodite CCR proxy.
      # Adapted from PlayForm/Aphrodite/profiles/example/config.yaml
      # for our stack (MiniMax upstream, M3 default + M2.7 delegation).

      agent:
        max_turns: 90
        disabled_toolsets: []
        tool_use_enforcement: auto

      model:
        default: minimax/MiniMax-M3
        provider: aphrodite-token

      providers:
        aphrodite-token:
          provider: openai
          base_url: http://127.0.0.1:9798
          # The systemd-managed proxy reads MINIMAX_API_KEY (its
          # api_key_env). Same env var is sourced into user
          # sessions from ~/.hermes/.env at gateway start.
          api_key_env: MINIMAX_API_KEY
          max_tokens: 65536
        # Direct fallback if the proxy is down — Hermes goes
        # straight to MiniMax with the same key.
        minimax:
          provider: openai
          base_url: https://api.minimax.io/v1
          api_key_env: MINIMAX_API_KEY
          max_tokens: 65536

      compression:
        enabled: false
      context:
        engine: aphrodite

      toolsets:
        - hermes-cli
        - aphrodite

      terminal:
        env_passthrough:
          - MINIMAX_API_KEY
          - PATH
          - HOME

      delegation:
        model: minimax/MiniMax-M2.7
    '';
  };
}