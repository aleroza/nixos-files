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
  # Try v0.4.7 (stable branch) before v0.4.11.dev* (which had a
  # bug where the server ignored server.host in ov.conf and
  # defaulted back to 0.0.0.0 even on dev mode). Stable branch
  # also has the same auth (root_api_key + Admin API user_key),
  # just without the host-ignore regression.
  openvikingImage = "openviking/openviking@sha256:a25c8eb3759cec0f18d99635174e5475b0aeb712128410502c738e4a2300b01b";
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
    # Substitute api_key in 3 places. server.root_api_key
    # substitution is conditional — when ovConfig declares a
    # literal root_api_key we leave it alone. When ovConfig has
    # the placeholder "__read_from_file__" we substitute the
    # apiKeyFile content.
    JSON=$(${pkgs.jq}/bin/jq \
      --arg key "$KEY" -c '
        .embedding.dense.api_key = $key
        | .vlm.api_key = $key
        | (if (.server.root_api_key == "__read_from_file__")
              then .server.root_api_key = $key
              else . end)
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
    # Debug: also dump rendered JSON to /tmp, world-readable so we
    # can inspect what landed without sudo. Pure diagnostic;
    # contains the api_key — only enable during debugging.
    ${pkgs.coreutils}/bin/install -m 0644 -o root -g root \
      /var/lib/openviking-server/ov.conf.env \
      /tmp/openviking-rendered-ov.json
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
    # The ov.conf JSON. Rendered into OPENVIKING_CONF_CONTENT
    # and passed to the container as an env var at unit
    # start. The api_key placeholders `__read_from_file__`
    # are substituted from `services.openviking.apiKeyFile`.
    ovConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {
        server = {
          host = "127.0.0.1";
          port = 1933;
          # dev mode = unauthenticated root endpoint. dev mode is
          # the right choice for a single-host single-client setup
          # like ours (hermes-agent is the only thing that talks to
          # OpenViking, and we bind podman to 127.0.0.1:1933 on the
          # host firewall so nothing else can reach it).
          #
          # dev mode requires server.host = 127.0.0.1 — the v0.4.11
          # dev branch ignored that field and forced 0.0.0.0; on
          # v0.4.7 the dev-mode host check is satisfied as long as
          # we set it here.
          auth_mode = "dev";
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
      default = /run/secrets/hermes/GOOGLE_API_KEY;
      description = ''
        Path to a file containing the Google AI Studio API key.
        Read at unit start; either a raw key (one line) or an
        env-file with `GOOGLE_API_KEY=...` (or `OPENAI_API_KEY=`)
        lines. Default reuses the dedicated sops secret at
        /run/secrets/hermes/GOOGLE_API_KEY; switch to
        /run/secrets/hermes/env if you want one combined
        secret file for everything Google-shaped.
      '';
    };

    # Optional HTTP/HTTPS proxy for the container. Some embedding
    # / VLM providers reject direct connections from non-public
    # IP ranges, or the user wants outbound traffic going through
    # the same proxy as the rest of the host. Set this and
    # HTTPS_PROXY / HTTP_PROXY / ALL_PROXY / NO_PROXY are
    # propagated into the container; the OpenViking Python
    # client picks them up via the standard library.
    #
    # Default is "no proxy" — OpenViking talks directly to
    # Gemini's public endpoint. Set to e.g.
    #   services.openviking.proxyUrl = "http://127.0.0.1:7890";
    # to route through the host's proxy. NO_PROXY is auto-set
    # to localhost/127.0.0.1 so the loopback bind to OpenViking
    # itself doesn't go through the proxy.
    proxyUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "http://127.0.0.1:7890";
      description = ''
        HTTP/HTTPS proxy URL for outbound traffic from the
        OpenViking container. null means no proxy.
      '';
    };

    noProxy = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1,localhost,::1";
      description = ''
        Comma-separated NO_PROXY list. Excluded hosts bypass the
        proxy regardless of HTTPS_PROXY setting. Default excludes
        loopback so OpenViking's own API endpoint stays direct.
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

    # Forward proxy config from auto → services.
    services.openviking.proxyUrl = autoCfg.proxyUrl;

    # The actual server. We hand-roll a podman systemd unit
    # instead of using NixOS's virtualisation.oci-containers
    # because we need to inject the rendered ov.conf as an env
    # var with the api_key substituted in at unit start. The
    # rendered config contains secrets, so it must not live in
    # the Nix store.
    systemd.services.openviking-server = {
      description = "OpenViking self-hosted context database — config rev ${builtins.substring 0 8 (builtins.hashString "sha256" (builtins.toJSON cfg.ovConfig))}";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "openviking-server-data-dir.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        # Type=notify because podman's --sdnotify=conmon notifies
        # systemd when the container is ready. With Type=simple
        # systemd treats the service as "started" the moment
        # podman returns from exec — which happens almost
        # immediately when the container goes into the
        # background. The notify type waits for the actual
        # sd_notify READY=1 from conmon before considering the
        # unit started. Crucially, we MUST NOT use `podman run -d`
        # because that would background the container and podman
        # would exit before sdnotify can fire — the right
        # invocation is foreground `podman run` which stays
        # running as the unit's PID and forwards sd_notify through
        # conmon.
        Type = "notify";
        NotifyAccess = "main";
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
          # Build optional -e args for proxy env vars. We don't
          # hard-code the proxy in the module — services.openviking.proxyUrl
          # controls this, and podman picks up the env vars
          # automatically from -e. NO_PROXY is always set so
          # the loopback bind (OpenViking's own API) stays direct.
          PROXY_ARGS=()
          ${lib.optionalString (cfg.proxyUrl != null) ''
            PROXY_ARGS+=(
              -e HTTP_PROXY="${cfg.proxyUrl}"
              -e HTTPS_PROXY="${cfg.proxyUrl}"
              -e ALL_PROXY="${cfg.proxyUrl}"
            )
          ''}
          PROXY_ARGS+=(
            -e NO_PROXY="${cfg.noProxy}"
          )
          # Always recreate the container on start so a new
          # closure (image digest, env vars, mounts, anything) is
          # picked up the moment systemd restarts us. Without
          # this, --replace leaves the container running when
          # podman can't gracefully stop it within 10s (e.g. when
          # the container's entrypoint is wedged), and the new
          # unit's args never take effect.
          ${pkgs.podman}/bin/podman rm -f openviking-server 2>/dev/null || true
          exec ${pkgs.podman}/bin/podman run \
            --rm \
            --name=openviking-server \
            --log-driver=journald \
            --cgroups=enabled \
            --sdnotify=conmon \
            --replace \
            # openviking-entrypoint.sh defaults OPENVIKING_SERVER_HOST
            # to 0.0.0.0 (so the vikingbot child process can reach the
            # server). With dev auth_mode this triggers the
            # "host must be localhost" panic at startup. We force
            # the entrypoint's env to 127.0.0.1 so server --host
            # is localhost and the dev-mode check passes. This MUST
            # appear before the positional <image> arg in the same
            # podman run invocation, otherwise the comment line that
            # wraps our env-var would also comment out the env var
            # itself (bash continuation backslash on each line puts
            # everything after <image> into one logical line whose
            # first `#` starts a comment that swallows everything up
            # to the actual newline after the env var).
            -e OPENVIKING_SERVER_HOST=127.0.0.1 \
            -e OPENVIKING_CONF_CONTENT="$DECODED" \
            "''${PROXY_ARGS[@]}" \
            -p 127.0.0.1:${toString cfg.port}:${toString cfg.port} \
            -v ${cfg.dataDir}:/data \
            -w /data \
            ${cfg.image}
        '';
        ExecStop = "-${pkgs.podman}/bin/podman stop openviking-server";
      };
      # Restart whenever any of the files this ExecStart reads
      # changes. Render-ov-conf lives in /nix/store and is
      # regenerated on every commit; openviking-server-run is
      # regenerated whenever the module changes. Together they
      # cover "Nix config changed → restart the container with
      # the new unit args" without needing a separate restart
      # step.
      restartTriggers = [
        renderConf
        pkgs.podman
      ];
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

    # Render client.env with the real api_key substituted in. We
    # can't put a secret in environment.etc.<name>.text because
    # Nix build-time evaluation can't reach runtime files. Same
    # pattern as render-ov-conf: a tiny systemd unit that reads
    # apiKeyFile and writes /var/lib/openviking-server/client.env
    # at unit start. systemd reads the resulting file via
    # EnvironmentFile= in the hermes-agent.service unit.
    systemd.services.openviking-client-env = {
      description = "Render /var/lib/openviking-server/client.env with api_key substituted";
      wantedBy = [ "multi-user.target" ];
      before = [ "hermes-agent.service" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # The bearer auth key is picked in this priority order:
        #   1. ovConfig.server.root_api_key literal, when it is not
        #      the placeholder "__read_from_file__" (which signals
        #      "use apiKeyFile at runtime"). Literal values stay
        #      verbatim across builds and across service restarts.
        #   2. Runtime apiKeyFile (sops-managed Google API key,
        #      OpenAI API key, or a one-line raw token). When
        #      root_api_key is the placeholder, we read this file
        #      and use its content as the bearer.
        #
        # We pre-compute the bearer at eval time so it lands
        # verbatim in the binary script — same string the server
        # got in ov.conf.
        ExecStart = pkgs.writeShellScript "render-client-env" ''
          set -euo pipefail
          mkdir -p /var/lib/openviking-server
          # Bearer chosen by the Nix module at eval time. The chosen
          # literal is either ovConfig.server.root_api_key (when
          # set to a real string) or the apiKeyFile content; the
          # placeholder "__read_from_file__" forces the latter.
          BEARER=${lib.escapeShellArg (
            let
              rak = cfg.ovConfig.server.root_api_key or null;
            in
            if rak == "__read_from_file__" || rak == null || rak == ""
            then "__literal_from_runtime__"  # marker, replaced below
            else rak
          )}
          # Bash below: when BEARER is "__literal_from_runtime__", fall
          # back to apiKeyFile contents.
          SRC=${lib.escapeShellArg (toString cfg.apiKeyFile)}
          if [ "$BEARER" = "__literal_from_runtime__" ]; then
            if [ ! -e "$SRC" ]; then
              echo "apiKeyFile $SRC not found" >&2
              exit 1
            fi
            if grep -qE '^GOOGLE_API_KEY=' "$SRC"; then
              BEARER=$(grep -E '^GOOGLE_API_KEY=' "$SRC" | head -n1 | cut -d= -f2- | tr -d '\n')
            elif grep -qE '^OPENAI_API_KEY=' "$SRC"; then
              BEARER=$(grep -E '^OPENAI_API_KEY=' "$SRC" | head -n1 | cut -d= -f2- | tr -d '\n')
            else
              BEARER=$(cat "$SRC" | tr -d '\n')
            fi
          fi
          if [ -z "$BEARER" ]; then
            echo "Empty bearer — check ovConfig.server.root_api_key and apiKeyFile" >&2
            exit 1
          fi
          cat > /var/lib/openviking-server/client.env <<EOF
          OPENVIKING_ENDPOINT=http://127.0.0.1:${toString cfg.port}
          OPENVIKING_ACCOUNT=default
          OPENVIKING_USER=default
          OPENVIKING_AGENT=hermes
          OPENVIKING_API_KEY=$BEARER
          EOF
          chmod 0644 /var/lib/openviking-server/client.env
          echo "render-client-env: wrote $(stat -c %s /var/lib/openviking-server/client.env) bytes" >&2
        '';
      };
    };

    # Fire a firewall hole if the user explicitly asks for one.
    networking.firewall.allowedTCPPorts =
      lib.mkIf cfg.openFirewall [ cfg.port ];

    # Surface the endpoint as a session env var for ad-hoc CLI use.
    environment.sessionVariables = {
      OPENVIKING_ENDPOINT = "http://127.0.0.1:${toString cfg.port}";
    };
  };
}
