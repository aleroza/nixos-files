# OpenViking — local-first context database for Hermes Agent.
#
# Runs openviking/openviking from Docker Hub as a long-lived
# container, exposed on 127.0.0.1:1933 (default port). Hermes
# Agent talks to it via memory.provider = "openviking".
#
# Requires auto.docker.enable = true on the host — there's no
# point pulling a Docker image if the daemon isn't there.
#
# Storage layout:
#   /var/lib/openviking/         — server data dir (volume)
#   /etc/openviking/client.env   — endpoint + creds for clients
#   /etc/openviking/ov.conf      — server config
#
# The server is intentionally bound to 127.0.0.1 — it has no
# authentication and assumes it sits behind a trusted client. If
# you ever expose it across the network, put it behind a reverse
# proxy with TLS + auth.
#
# Quick start after `auto.openviking = true` and `nixos-rebuild switch`:
#
#   1. `sudo systemctl start openviking-server`
#   2. `sudo docker logs -f openviking-server`   — wait for "listening on ..."
#   3. `curl http://127.0.0.1:1933/health`      — confirm it's up
#   4. Set hermes-agent memory.provider to "openviking"
#      and restart hermes-agent.service.

{ config, lib, pkgs, ... }:

let
  cfg = config.services.openviking;
  autoCfg = config.auto.openviking;
  openvikingImage = "openviking/openviking:v0.4.11.dev23";
  # Render ov.conf with the api_key substituted at activation
  # time (so changing apiKeyFile doesn't require a rebuild —
  # just an activation). We embed it as `OPENVIKING_CONF_CONTENT`
  # because the upstream Docker image's entrypoint refuses to
  # start without either /app/.openviking/ov.conf in the
  # container or that env var set. Passing the JSON inline
  # means we don't need to bind-mount a config file at all
  # — the data dir volume just carries the persisted DB, the
  # config travels in the systemd environment.
  #
  # apiKeyFile may be either a raw key (one line) or an env-file
  # with `KEY=VALUE` lines. We grep for the known names first,
  # then fall back to reading the whole file as the key. We
  # strip newlines so multi-line .env files don't poison the
  # JSON.
  renderConf = pkgs.writeShellScript "render-ov-conf" ''
    set -euo pipefail
    # systemd's StateDirectory= creates /run/<unitname>/ where
    # unitname = the service's "name" field. For unit
    # openviking-server-data-dir.service, that's
    # /run/openviking-server-data-dir/. We want /run/openviking-server/
    # because that's the path baked into OPENVIKING_CONF_CONTENT.
    # So just mkdir it manually.
    mkdir -p /run/openviking-server
    KEY=""
    SRC=${lib.escapeShellArg (toString cfg.apiKeyFile)}
    if grep -qE '^GOOGLE_API_KEY=' "$SRC"; then
      KEY=$(grep -E '^GOOGLE_API_KEY=' "$SRC" | head -n1 | cut -d= -f2- | tr -d '\n')
    elif grep -qE '^OPENAI_API_KEY=' "$SRC"; then
      KEY=$(grep -E '^OPENAI_API_KEY=' "$SRC" | head -n1 | cut -d= -f2- | tr -d '\n')
    else
      KEY=$(cat "$SRC" | tr -d '\n')
    fi
    if [ -z "$KEY" ]; then
      echo "No API key found in $SRC" >&2
      exit 1
    fi
    ${pkgs.jq}/bin/jq \
      --arg key "$KEY" '
        .embedding.dense.api_key = $key
        | .vlm.api_key = $key
      ' ${pkgs.writeText "ov-config-template.json" (builtins.toJSON cfg.ovConfig)} \
      > /run/openviking-server/ov.conf.json
    chmod 0600 /run/openviking-server/ov.conf.json
  '';
in
{
  options.services.openviking = {
    enable = lib.mkEnableOption "OpenViking self-hosted context database (Docker)";

    image = lib.mkOption {
      type = lib.types.str;
      default = openvikingImage;
      description = ''
        Container image to run. Pin to a specific tag (the
        upstream `:main` and `:latest` tags change on every CI
        push and will break reproducibility).
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 1933;
      description = ''
        Port for openviking-server to listen on. Bound to
        127.0.0.1 only — never expose this port publicly without
        a reverse proxy providing TLS + auth.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/openviking";
      description = "Host directory mounted into the container for server data.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to open the OpenViking port on the firewall.
        Off by default — the server only binds to 127.0.0.1 so
        firewall rules are normally unnecessary.
      '';
    };

    # Provider configuration. Defaults assume the Gemini family
    # (free tier) — embedding via the dedicated Gemini Embedding
    # endpoint, VLM via Google AI Studio's OpenAI-compatible
    # surface (works because Google exposes `/v1beta/openai/` on
    # the same host). The apiKeyFile points to a sops-managed
    # secret so the key never lands in the Nix store.
    ovConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {
        storage = {
          workspace = "/data";
          vectordb = {
            name = "context";
            backend = "local";
          };
          agfs = {
            backend = "local";
          };
        };
        embedding = {
          dense = {
            provider = "gemini";
            api_key = "__read_from_file__";
            model = "gemini-embedding-2-preview";
            dimension = 3072;
          };
        };
        vlm = {
          api_key = "__read_from_file__";
          api_base = "https://generativelanguage.googleapis.com/v1beta/openai/";
          provider = "openai";
          model = "gemini-2.0-flash";
        };
      };
      description = ''
        The ov.conf JSON. Rendered into OPENVIKING_CONF_CONTENT
        and passed to the container as an env var at unit
        start. The api_key placeholders `__read_from_file__`
        are substituted from `services.openviking.apiKeyFile`.
      '';
    };

    apiKeyFile = lib.mkOption {
      type = lib.types.path;
      default = /run/secrets/hermes/env;
      description = ''
        Path to a file containing the Google AI Studio API key.
        Read at unit start; either a raw key (one line) or an
        env-file with `GOOGLE_API_KEY=...` (or `OPENAI_API_KEY=`)
        lines. Default reuses the existing hermes sops secret.
      '';
    };
  };

  config = lib.mkIf autoCfg.enable {

    assertions = [
      {
        assertion = config.auto.docker.enable;
        message = ''
          auto.openviking.enable = true requires auto.docker.enable = true.
          OpenViking runs as an OCI container; the daemon must
          be enabled for the systemd unit to start.
        '';
      }
    ];

    # The actual server: a long-lived container managed by
    # NixOS's virtualisation.oci-containers. The Docker image
    # needs /data for its SQLite/vector files; we mount the host
    # dataDir there. The runtime config travels in
    # OPENVIKING_CONF_CONTENT (rendered at unit start from
    # apiKeyFile) — no need to bind-mount ov.conf anymore.
    virtualisation.oci-containers.containers.openviking-server = {
      image = cfg.image;
      autoStart = true;
      ports = [ "127.0.0.1:${toString cfg.port}:${toString cfg.port}" ];
      volumes = [
        "${cfg.dataDir}:/data"
      ];
      environment = {
        # The container's openviking-server entrypoint checks
        # OPENVIKING_CONF_CONTENT for the full ov.conf JSON.
        # Render-ov-conf writes to this path on each start.
        OPENVIKING_CONF_CONTENT = ''file:///run/openviking-server/ov.conf.json'';
      };
      # The container expects to write its DB to /data.
      workdir = "/data";
    };

    # Render ov.conf with the real api_key substituted in, then
    # start the container. Order matters: render-ov-conf must
    # finish before podman-openviking-server starts. systemd
    # honours `Before=` for one-shot ordering.
    systemd.services.openviking-server-data-dir = {
      description = "Ensure OpenViking data directory exists and config is rendered";
      wantedBy = [ "multi-user.target" ];
      before = [ "podman-openviking-server.service" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # We need /run/openviking-server/ — the StateDirectory=
        # machinery would create /run/<unit-name>/ which for this
        # unit is /run/openviking-server-data-dir/ and not what
        # OPENVIKING_CONF_CONTENT expects. So do mkdir manually
        # in render-ov-conf (above) and skip StateDirectory= here.
        # We don't need a persistent /var/lib/ directory — the
        # container owns /data via its bind mount and that's
        # where the actual state lives.
        ExecStartPre = pkgs.writeShellScript "check-api-key" ''
          if [ ! -s ${lib.escapeShellArg (toString cfg.apiKeyFile)} ]; then
            echo "services.openviking.apiKeyFile = ${toString cfg.apiKeyFile}" >&2
            echo "is missing or empty. Provision a sops secret at" >&2
            echo "aleroza.yaml hermes.GOOGLE_API_KEY (or" >&2
            echo "aleroza.yaml hermes.OPENAI_API_KEY), or change" >&2
            echo "services.openviking.apiKeyFile to point at a file you own." >&2
            exit 1
          fi
        '';
        ExecStart = renderConf;
      };
    };

    # Env file for clients (e.g. hermes-agent). The openviking
    # client reads OPENVIKING_ENDPOINT / *_ACCOUNT / *_USER /
    # *_AGENT from the process environment.
    environment.etc."openviking/client.env".text = ''
      OPENVIKING_ENDPOINT=http://127.0.0.1:${toString cfg.port}
      OPENVIKING_ACCOUNT=default
      OPENVIKING_USER=default
      OPENVIKING_AGENT=hermes
    '';
    environment.etc."openviking/client.env".mode = "0644";

    # Fire a firewall hole if the user explicitly asks for one.
    networking.firewall.allowedTCPPorts =
      lib.mkIf cfg.openFirewall [ cfg.port ];

    # Surface the endpoint as a session env var for ad-hoc CLI use.
    environment.sessionVariables = {
      OPENVIKING_ENDPOINT = "http://127.0.0.1:${toString cfg.port}";
    };
  };
}
