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
  # Render ov.conf with the api_key substituted. Two output paths
  # produced in a single run:
  #   - /run/openviking-server/ov.conf.json (for the file:// URL
  #     path — kept around for debugging)
  #   - stdout (captured and passed inline to OPENVIKING_CONF_CONTENT
  #     when systemd starts the container)
  #
  # We use the inline-stdout path because intermediate-file paths
  # are fragile under systemd's runtime-dir cleanup, and because
  # the inline form avoids any TOCTOU between render and
  # container-start.
  # Render the ov.conf JSON with the api_key substituted, then
  # write it as a systemd EnvironmentFile at
  # /var/lib/openviking-server/ov.conf.env. systemd's
  # EnvironmentFile= format is "KEY=VALUE" per line, where VALUE
  # may be shell-double-quoted to include spaces/specials. We
  # use jq -r to print one JSON line then double-quote it
  # for systemd. systemd then re-exports OPENVIKING_CONF_CONTENT
  # into the process environment of openviking-server.service.
  renderConf = pkgs.writeShellScript "render-ov-conf" ''
    set -euo pipefail
    mkdir -p /var/lib/openviking-server
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
    JSON=$(${pkgs.jq}/bin/jq \
      --arg key "$KEY" -c '
        .embedding.dense.api_key = $key
        | .vlm.api_key = $key
      ' ${pkgs.writeText "ov-config-template.json" (builtins.toJSON cfg.ovConfig)})
    # systemd's EnvironmentFile parser splits values on
    # whitespace. JSON contains spaces between fields, so an
    # unquoted EnvironmentFile entry would be truncated. We
    # base64-encode the JSON, write that as the env var, and
    # decode on the podman side with `base64 -d`. systemd
    # treats the base64 string as opaque — no splitting, no
    # quoting drama.
    B64=$(printf '%s' "$JSON" | ${pkgs.coreutils}/bin/base64 -w0)
    printf 'OPENVIKING_CONF_CONTENT_B64=%s\n' "$B64" > /var/lib/openviking-server/ov.conf.env
    chmod 0600 /var/lib/openviking-server/ov.conf.env
    # Diagnostic so the journal shows we got here.
    echo "render-ov-conf: wrote $(stat -c %s /var/lib/openviking-server/ov.conf.env) bytes of OPENVIKING_CONF_CONTENT" >&2
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
        server = {
          host = "0.0.0.0";
          port = 1933;
          # api_key mode = bearer token auth on the root endpoint.
          # Without this, dev mode refuses to start when bound to
          # 0.0.0.0 — but we want it reachable from the host's
          # 127.0.0.1 mapping, and the only thing that talks to
          # OpenViking is hermes-agent.service on this same host
          # (so 127.0.0.1 is fine). Pick any random root_api_key
          # here; hermes-agent will be configured with the same
          # value via OPENVIKING_API_KEY env var so it can talk
          # to the server.
          #
          # Note: OpenViking's auth model is currently being
          # redesigned (the upstream Discord had complaints
          # about api_key vs dev mode confusion). If switching
          # to api_key fails at runtime with "unknown field",
          # fall back to dev mode and override server.host to
          # 127.0.0.1 here.
          auth_mode = "api_key";
          root_api_key = "__placeholder_set_via_secret__";
        };
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

    # The actual server. We hand-roll a podman systemd unit
    # instead of using NixOS's virtualisation.oci-containers
    # because we need to inject the rendered ov.conf as an env
    # var with the api_key substituted in at unit start. The
    # rendered config contains secrets, so it must not live in
    # the Nix store.
    systemd.services.openviking-server = {
      description = "OpenViking self-hosted context database";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "openviking-server-data-dir.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 5;
        # Read the base64-encoded JSON config from
        # /var/lib/openviking-server/ov.conf.env (the openviking-
        # server-data-dir unit writes it before we start) and
        # forward it to the container as the env var
        # OPENVIKING_CONF_CONTENT that the upstream entrypoint
        # reads. We use base64 because systemd's EnvironmentFile
        # parser splits values on whitespace, and JSON has
        # whitespace inside it.
        EnvironmentFile = /var/lib/openviking-server/ov.conf.env;
        ExecStart = pkgs.writeShellScript "openviking-server-run" ''
          set -e
          # Decode the JSON config from the base64 env var the
          # EnvironmentFile exported.
          DECODED=$(printf '%s' "$OPENVIKING_CONF_CONTENT_B64" | ${pkgs.coreutils}/bin/base64 -d)
          exec ${pkgs.podman}/bin/podman run \
            --rm \
            --name=openviking-server \
            --log-driver=journald \
            --cgroups=enabled \
            --sdnotify=conmon \
            -d \
            --replace \
            -e OPENVIKING_CONF_CONTENT="$DECODED" \
            -p 127.0.0.1:${toString cfg.port}:${toString cfg.port} \
            -v ${cfg.dataDir}:/data \
            -w /data \
            ${cfg.image}
        '';
        ExecStop = "-${pkgs.podman}/bin/podman stop openviking-server";
      };
    };

    # Render ov.conf with the real api_key substituted in. State
    # goes to /var/lib/openviking-server/ov.conf.json, which
    # is bind-mounted into the container at /ov.conf/ov.conf.json.
    systemd.services.openviking-server-data-dir = {
      description = "Ensure OpenViking data directory exists and config is rendered";
      wantedBy = [ "multi-user.target" ];
      before = [ "podman-openviking-server.service" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Render ov.conf.json with the api_key substituted from
        # apiKeyFile. OpenViking refuses to start without this
        # file; we can't drive the init wizard interactively
        # from a systemd unit, so render it ourselves.
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
