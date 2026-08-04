# OpenViking — self-hosted context database for Hermes Agent.
#
# One NixOS module, three pieces of state:
#   1. oci-container `openviking` running the server on
#      127.0.0.1:1933 with auth_mode=api_key.
#   2. /opt/openviking/data/ov.conf — server config (api_key read
#      from a host file at activation time, root_api_key generated
#      by Nix).
#   3. systemd `openviking-bootstrap.service` — Type=oneshot that
#      mints a user_key via Admin API and writes it to
#      /opt/openviking/keys/user_key. Hermes-agent reads it from
#      there via EnvironmentFile.
#
# File layout on disk:
#   /opt/openviking/data/         — server data dir (vikingdir)
#   /opt/openviking/data/ov.conf   — server config (api_key)
#   /opt/openviking/keys/user_key  — user_key for hermes-agent (0640)
#
# Both data and keys are owned by `openviking:openviking`. Hermes
# user is in group `openviking` (read-only) so it can read user_key.

{ config, lib, pkgs, ... }:

let
  cfg = config.services.openviking;
  autoCfg = config.auto.openviking;

  # Root API key for OpenViking server. Generated at build time
  # by hashing the path to the api-key file. Anything equivalent
  # (sops, age, etc.) is more work for ~no benefit on a single-host
  # single-user box.
  rootApiKey = "ovk_" + pkgs.lib.substring 0 32
    (builtins.hashString "sha256" (toString cfg.embedding.apiKeyFile));

  # Render ov.conf into /opt/openviking/data/ov.conf.env. The api
  # key is read from a host file at activation time (the file is
  # mounted by sops at /run/secrets/hermes/GOOGLE_API_KEY, or it
  # could be a hand-rolled file under /etc/openviking/). The
  # rendered JSON is base64-encoded because systemd's
  # EnvironmentFile parser splits on whitespace, which JSON
  # contains. The plaintext JSON also lands at
  # /opt/openviking/data/ov.conf.json for inspection. Both files
  # are mode 0640 openviking:openviking.
  renderConfScript = pkgs.writeShellScript "openviking-render-conf" ''
    set -euo pipefail
    KEY_FILE=/opt/openviking/data/ov.conf.env
    KEY_SRC=${lib.escapeShellArg (toString cfg.embedding.apiKeyFile)}

    # Read the api key from the configured file. May be a raw
    # key (one line) or an env-file (KEY=VALUE). Strip newlines
    # so multi-line files don't poison the JSON.
    if grep -qE '^GOOGLE_API_KEY=' "$KEY_SRC"; then
      API_KEY=$(grep -E '^GOOGLE_API_KEY=' "$KEY_SRC" | head -n1 | cut -d= -f2- | tr -d '\n')
    elif grep -qE '^OPENAI_API_KEY=' "$KEY_SRC"; then
      API_KEY=$(grep -E '^OPENAI_API_KEY=' "$KEY_SRC" | head -n1 | cut -d= -f2- | tr -d '\n')
    else
      API_KEY=$(cat "$KEY_SRC" | tr -d '\n')
    fi
    if [[ -z "$API_KEY" ]]; then
      echo "openviking: empty api_key in $KEY_SRC" >&2
      exit 1
    fi

    JSON=$(${pkgs.jq}/bin/jq -n \
      --arg root_key "${rootApiKey}" \
      --arg embed_key "$API_KEY" \
      --arg embed_model "${cfg.embedding.model}" \
      --argjson embed_dim ${toString cfg.embedding.dimension} \
      --arg vlm_base "${cfg.vlm.apiBase}" \
      --arg vlm_model "${cfg.vlm.model}" \
      '{
        server: {
          host: "127.0.0.1",
          port: ${toString cfg.port},
          auth_mode: "api_key",
          root_api_key: $root_key
        },
        storage: {
          workspace: "/data",
          vectordb: { name: "context", backend: "local" },
          agfs: { backend: "local" }
        },
        embedding: {
          dense: {
            provider: "gemini",
            api_key: $embed_key,
            model: $embed_model,
            dimension: $embed_dim
          }
        },
        vlm: {
          api_key: $embed_key,
          api_base: $vlm_base,
          provider: "openai",
          model: $vlm_model
        }
      }')
    printf '%s' "$JSON" > /opt/openviking/data/ov.conf.json
    chmod 0640 /opt/openviking/data/ov.conf.json
    chown openviking:openviking /opt/openviking/data/ov.conf.json
    B64=$(printf '%s' "$JSON" | ${pkgs.coreutils}/bin/base64 -w0)
    printf 'OPENVIKING_CONF_CONTENT_B64=%s\n' "$B64" > "$KEY_FILE"
    chmod 0640 "$KEY_FILE"
    chown openviking:openviking "$KEY_FILE"
  '';

  runScript = pkgs.writeShellScript "openviking-server-run" ''
    set -euo pipefail
    DECODED=$(printf '%s' "$OPENVIKING_CONF_CONTENT_B64" | ${pkgs.coreutils}/bin/base64 -d)
    PROXY_ARGS=()
    ${lib.optionalString (cfg.proxyUrl != null) ''
      PROXY_ARGS+=(
        -e HTTP_PROXY="${cfg.proxyUrl}"
        -e HTTPS_PROXY="${cfg.proxyUrl}"
        -e ALL_PROXY="${cfg.proxyUrl}"
      )
    ''}
    PROXY_ARGS+=(
      -e NO_PROXY="127.0.0.1,localhost,::1"
    )
    exec ${pkgs.podman}/bin/podman run \
      --rm \
      --name=openviking-server \
      --network=host \
      --log-driver=journald \
      --cgroups=enabled \
      --sdnotify=conmon \
      --replace \
      -e OPENVIKING_SERVER_HOST=127.0.0.1 \
      -e OPENVIKING_SERVER_PORT=${toString cfg.port} \
      -e OPENVIKING_WITH_BOT=0 \
      -e OPENVIKING_CONF_CONTENT="$DECODED" \
      "''${PROXY_ARGS[@]}" \
      -v ${cfg.dataDir}:/data \
      ${cfg.image}
  '';
in
{
  options.services.openviking = {
    enable = lib.mkEnableOption "OpenViking self-hosted context database for Hermes Agent";

    image = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/openviking/openviking:v0.4.7.dev6";
      description = "Container image to run.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 1933;
      description = "Port for openviking-server to listen on.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/opt/openviking/data";
      description = "Server data dir (bind-mounted into the container at /data).";
    };

    keysDir = lib.mkOption {
      type = lib.types.path;
      default = "/opt/openviking/keys";
      description = "Directory for the user_key file (mode 0750 openviking:openviking).";
    };

    # LLM provider config. openviking calls out to Gemini for
    # embedding + VLM through the host's HTTP proxy at
    # 127.0.0.1:7890. Google's generic endpoint rejects some
    # egress ranges, so the proxy is mandatory.
    embedding = {
      provider = lib.mkOption {
        type = lib.types.str;
        default = "gemini";
      };
      model = lib.mkOption {
        type = lib.types.str;
        default = "gemini-embedding-2-preview";
      };
      dimension = lib.mkOption {
        type = lib.types.int;
        default = 3072;
      };
      apiKeyFile = lib.mkOption {
        type = lib.types.path;
        default = "/run/secrets/hermes/GOOGLE_API_KEY";
        description = ''
          Path to the Google AI Studio API key. Read at activation
          time. May be a raw key (one line) or an env-file with
          `GOOGLE_API_KEY=` (or `OPENAI_API_KEY=`) lines. Default
          reuses the sops-decrypted secret at
          /run/secrets/hermes/GOOGLE_API_KEY.
        '';
      };
    };

    vlm = {
      apiBase = lib.mkOption {
        type = lib.types.str;
        default = "https://generativelanguage.googleapis.com/v1beta/openai/";
      };
      model = lib.mkOption {
        type = lib.types.str;
        default = "gemini-2.0-flash";
      };
    };

    proxyUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "http://127.0.0.1:7890";
      description = "HTTP proxy for Google's embedding + VLM endpoints. Set null to disable.";
    };
  };

  config = lib.mkIf autoCfg.enable {

    # OpenViking system user + group. Same perms as the bin
    # drops in /opt/openviking. Hermes user gets read-only group
    # access so it can read /opt/openviking/keys/user_key.
    users.groups.openviking = { };
    users.users.openviking = {
      isSystemUser = true;
      group = "openviking";
      uid = 989;
    };
    users.users.hermes.extraGroups = [ "openviking" ];

    # Persistent dirs under /opt/openviking. The container
    # bind-mounts /opt/openviking/data -> /data so the server
    # sees a populated workspace + ov.conf on first start.
    systemd.tmpfiles.rules = [
      "d /opt/openviking 0750 openviking openviking - -"
      "d /opt/openviking/data 0750 openviking openviking - -"
      "d /opt/openviking/keys 0750 openviking openviking - -"
    ];

    # Server container. Run as root so podman doesn't need
    # rootless setup (subuid/subgid for the openviking user).
    # The container bind-mounts /opt/openviking/data and
    # /opt/openviking/keys which are owned by
    # openviking:openviking — podman honours the host ownership
    # on the bind mount. Running as root also lets us read the
    # api-key file at /run/secrets/hermes/GOOGLE_API_KEY
    # (owner=aleroza:hermes, 0400).
    systemd.services.openviking-server = {
      description = "OpenViking self-hosted context database";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "notify";
        NotifyAccess = "main";
        Restart = "always";
        RestartSec = 5;
        User = "root";
        WorkingDirectory = "/opt/openviking/data";
        EnvironmentFile = "-/opt/openviking/data/ov.conf.env";
        ExecStartPre = renderConfScript;
        ExecStart = runScript;
        ExecStop = "-${pkgs.podman}/bin/podman stop openviking-server";
      };
    };

    # One-shot Admin API bootstrap. Runs after openviking-server
    # is healthy. Mints a user_key (or reuses the existing one)
    # and writes it to /opt/openviking/keys/user_key. Hermes-agent
    # picks it up via EnvironmentFile=/opt/openviking/keys/user_key.
    #
    # Race: hermes-agent may start before this finishes — that's
    # acceptable. The boot-md hook notifies via Telegram, and on
    # any subsequent hermes-agent restart (e.g. memory pressure
    # / OOM) the new ENV will include the user_key.
    systemd.services.openviking-bootstrap = {
      description = "OpenViking Admin API bootstrap — mint user_key for hermes-agent";
      wantedBy = [ "multi-user.target" ];
      after = [ "openviking-server.service" ];
      wants = [ "openviking-server.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "openviking";
        Group = "openviking";
        WorkingDirectory = cfg.keysDir;
      };
      script = ''
        set -euo pipefail

        ENDPOINT=http://127.0.0.1:${toString cfg.port}
        KEY_FILE=${cfg.keysDir}/user_key

        # Wait for the server to come up.
        for _ in $(seq 1 60); do
          if ${pkgs.curl}/bin/curl -fsS --max-time 2 "$ENDPOINT/health" >/dev/null 2>&1; then
            break
          fi
          sleep 1
        done

        # Read root_api_key from the rendered ov.conf.json
        # (chmod 0640 openviking:openviking, we own the file).
        ROOT_KEY=$(${pkgs.jq}/bin/jq -r '.server.root_api_key' /opt/openviking/data/ov.conf.json)

        # 1. Ensure account exists. 409 ALREADY_EXISTS is fine.
        code=$(${pkgs.curl}/bin/curl -s -o /dev/null -w '%{http_code}' -X POST \
          -H "Authorization: Bearer ***" \
          -H "Content-Type: application/json" \
          -d '{"account_id":"default","admin_user_id":"default"}' \
          "$ENDPOINT/api/v1/admin/accounts")
        if [[ "$code" != "200" && "$code" != "409" ]]; then
          echo "openviking-bootstrap: account create failed: $code" >&2
          exit 1
        fi

        # 2. Mint user_key. Server returns the existing key if
        # the user is already registered, so this is idempotent
        # without invalidating prior keys.
        USER_KEY=$(${pkgs.curl}/bin/curl -fsS -X POST \
          -H "Authorization: Bearer ***" \
          -H "Content-Type: application/json" \
          -d '{"user_id":"default","role":"user"}' \
          "$ENDPOINT/api/v1/admin/accounts/default/users" \
          | ${pkgs.jq}/bin/jq -r '.result.user_key')

        if [[ -z "$USER_KEY" || "$USER_KEY" == "null" ]]; then
          echo "openviking-bootstrap: empty user_key in response" >&2
          exit 1
        fi

        # 3. Write as an env-file so systemd EnvironmentFile=
        # can consume it directly. KEY=VALUE per line, no shell
        # expansion. OPENVIKING_API_KEY is the upstream plugin's
        # env var.
        printf 'OPENVIKING_API_KEY=%s\n' "$USER_KEY" > "$KEY_FILE"
        chmod 0640 "$KEY_FILE"
      '';
    };
  };
}
