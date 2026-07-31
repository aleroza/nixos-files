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
  configFile = pkgs.writeText "ov.conf" (''
    [server]
    host = "127.0.0.1"
    port = ${toString cfg.port}
    data_dir = "${cfg.dataDir}"

    [storage]
    backend = "local"

    [logging]
    level = "info"
  '');
  openvikingImage = "openviking/openviking:v0.4.11.dev23";
  # OpenViking reads its config from ~/.openviking/ov.conf (the
  # home dir of whatever user the container runs as — root by
  # default for our oci-containers setup, but OpenViking may
  # have a non-root entrypoint; in either case it ends up under
  # /root/.openviking/ov.conf or /.openviking/ov.conf). The data
  # dir gets bind-mounted at /data; we want the config to live
  # alongside the data so it survives container restarts and
  # can be inspected from the host. The /data volume is mounted
  # rw, so writing /data/.openviking/ov.conf inside the
  # container persists.
  #
  # We pre-create the JSON config from a Nix attrset rather than
  # running `openviking-server init` interactively. The init
  # wizard requires a TTY and asks for API keys in plaintext —
  # not workable from a systemd unit. We render the JSON
  # straight from the option values, with api_key sourced from
  # the sops-managed secret at /run/secrets/openviking/api_key
  # (same pattern as hermes/env).
  ovConfigFile = cfg.ovConfig;
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
        The ~/.openviking/ov.conf JSON config. Must include
        `embedding.dense.provider` (gemini | openai | ollama | …)
        and `vlm.provider`. api_key placeholders
        `__read_from_file__` are substituted at runtime from
        `services.openviking.apiKeyFile`.
      '';
    };

    apiKeyFile = lib.mkOption {
      type = lib.types.path;
      default = /run/secrets/hermes/env;
      description = ''
        Path to a file containing the Google AI Studio API key.
        The file is read at unit start; the first non-empty
        line is used as the api_key. Default points at the
        existing hermes/env sops secret which contains
        GOOGLE_API_KEY on its own line — reuse that rather than
        provisioning a second secret.
      '';
    };
  };

  # Render the JSON config with the api_key filled in at
  # activation time (so changing apiKeyFile doesn't require a
  # rebuild — just an activation). We DON'T add a Nix assertion
  # for apiKeyFile existing at build time — that would prevent
  # building the configuration before the secret is provisioned.
  # Instead, the systemd unit that renders the config (below)
  # fails fast at start time if the file is missing.
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
    # NixOS's virtualisation.oci-containers — this is the
    # declarative Nix way to run a container (no hand-written
    # `docker run` ExecStart, no image pull at unit-start time,
    # image version is pinned in the Nix config).
    virtualisation.oci-containers.containers.openviking-server = {
      image = cfg.image;
      autoStart = true;
      ports = [ "127.0.0.1:${toString cfg.port}:${toString cfg.port}" ];
      volumes = [
        "${cfg.dataDir}:/data"
        "/etc/openviking/ov.conf:/data/.openviking/ov.conf:ro"
      ];
      environment = {
        # The container's openviking-server reads its config
        # from $HOME/.openviking/ov.conf, which under our
        # mount layout is /data/.openviking/ov.conf.
        HOME = "/data";
      };
      # The container expects to write its DB to /data; map
      # that to the host's dataDir.
      workdir = "/data";
    };

    # Make sure the data dir exists before podman tries to
    # mount it. StateDirectory= creates /var/lib/openviking
    # owned by root with mode 0755 at unit-start; podman then
    # can bind-mount it into the container. (Without this,
    # podman errors out with "statfs: no such file or directory"
    # because it stats the source path before mounting.)
    systemd.services.openviking-server-data-dir = {
      description = "Ensure OpenViking data directory exists";
      wantedBy = [ "multi-user.target" ];
      before = [ "podman-openviking-server.service" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "openviking";
        StateDirectoryMode = "0755";
        # Render ~/.openviking/ov.conf with the api_key from
        # apiKeyFile substituted into the placeholder fields.
        # OpenViking refuses to start without this file, and the
        # init wizard is interactive (no good way to drive it
        # from a systemd unit). Render on each start so key
        # rotation works without a rebuild.
        #
        # If apiKeyFile is missing the unit exits with a clear
        # error message — never silently produces a broken
        # config. Once the user provisions the sops secret (or
        # points apiKeyFile elsewhere) and re-runs nixos-rebuild,
        # the next container start succeeds.
        ExecStartPre = pkgs.writeShellScript "check-api-key" ''
          if [ ! -s ${lib.escapeShellArg (toString cfg.apiKeyFile)} ]; then
            echo "services.openviking.apiKeyFile = ${toString cfg.apiKeyFile}" >&2
            echo "is missing or empty. Provision a sops secret at" >&2
            echo "aleroza.yaml:\$openviking/api_key, or change" >&2
            echo "services.openviking.apiKeyFile to point at a file you own." >&2
            exit 1
          fi
        '';
        ExecStart = pkgs.writeShellScript "render-ov-conf" ''
          set -euo pipefail
          mkdir -p /var/lib/openviking/.openviking
          # apiKeyFile may be either a raw key (one line, no
          # prefix) or an env-file with `KEY=VALUE` lines. Handle
          # both: first try to grep for GOOGLE_API_KEY=, fall back
          # to reading the whole file as the key.
          KEY=""
          if grep -qE '^GOOGLE_API_KEY=' ${lib.escapeShellArg (toString cfg.apiKeyFile)}; then
            KEY=$(grep -E '^GOOGLE_API_KEY=' ${lib.escapeShellArg (toString cfg.apiKeyFile)} | head -n1 | cut -d= -f2-)
          else
            KEY=$(cat ${lib.escapeShellArg (toString cfg.apiKeyFile)})
          fi
          if [ -z "$KEY" ]; then
            echo "No API key found in ${lib.escapeShellArg (toString cfg.apiKeyFile)}" >&2
            exit 1
          fi
          ${pkgs.jq}/bin/jq \
            --arg key "$KEY" '
              .embedding.dense.api_key = $key
              | .vlm.api_key = $key
            ' ${pkgs.writeText "ov-config-template.json" (builtins.toJSON cfg.ovConfig)} \
            > /var/lib/openviking/.openviking/ov.conf
          chmod 0600 /var/lib/openviking/.openviking/ov.conf
        '';
      };
    };

    # Server config — pinned and readable
    environment.etc."openviking/ov.conf".source = configFile;
    environment.etc."openviking/ov.conf".mode = "0644";

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
