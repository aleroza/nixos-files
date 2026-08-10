# Home-manager module for the Aphrodite integration.
#
# What lives here (per-user, not per-host):
#   1. ~/.hermes/profiles/aphrodite/config.yaml — an explicit
#      profile that routes through the Aphrodite proxy on
#      127.0.0.1:9798. Launch with:
#        hermes --profile aphrodite
#      The default profile (in
#      hosts/aleroza-pc/hermes/default.nix) already routes
#      through the same proxy via settings.providers.aphrodite-token,
#      so this profile is mainly a backup / explicit-override
#      entry point.
#   2. ~/.hermes/aphrodite/.keep — empty directory marker.
#      The systemd proxy (services.aphrodite) uses /opt/aphrodite
#      for its data dir (see modules/services/aphrodite.nix,
#      HOME=/opt/aphrodite), so this is only used for user-side
#      overrides.
#
# What does NOT live here anymore (was here before, was wrong):
#   * Plugin installation at ~/.hermes/plugins/aphrodite/ via
#     home.file. That path bypassed the NixOS hermes-agent
#     module's extraPlugins mechanism — the gateway did not
#     auto-enable the plugin because NixOS-managed plugins live
#     in ~/.hermes/plugins/nix-managed-<name>, and home-manager
#     wrote a regular recursive copy (not a symlink, not
#     prefixed with `nix-managed-`).
#
#     The plugin is now correctly registered via
#     services.hermes-agent.extraPlugins in
#     hosts/aleroza-pc/hermes/default.nix. The systemd proxy it
#     talks to is services.aphrodite in modules/services/aphrodite.nix.
#
#     The prebuilt proxy binary and the Hermes dylib are also
#     declared there (same fetchurl derivations, in
#     modules/services/aphrodite.nix's package option and in
#     the host's environmentFiles for the proxy). We do not
#     duplicate them in home-manager.

{ config, lib, auto, ... }:

let
  cfg = auto.aphrodite;
in
{
  config = lib.mkIf (cfg.enable or false) {

    home.sessionVariables = {
      APHRODITE_CONFIG_PATH = "$HOME/.hermes/aphrodite/aphrodite.toml";
    };

    # Empty directory marker. The systemd proxy lives under
    # /opt/aphrodite (services.aphrodite.dataDir), so this is
    # only a place for user-side overrides.
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