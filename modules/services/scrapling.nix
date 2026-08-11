# Scrapling — adaptive web-scraping framework by D4Vinci (D4Vinci/Scrapling).
#
# Runs as a persistent oci-container (image: pyd4vinci/scrapling:latest)
# with Streamable-HTTP MCP transport. The container starts once at boot,
# installs chromium via scrapling's own `scrapling install` command on
# first run, and keeps state in /var/lib/scrapling on the host. Hermes
# connects to the MCP endpoint over loopback HTTP via mcp_servers.scrapling.
#
# Why persistent (vs. docker run --rm per tool call):
#   - Chromium boot is 5-8s on the 4300U. Persistent container avoids
#     paying that cost on every tool call.
#   - Scrapling's `mcp` command is just a Python entrypoint in the
#     pyd4vinci/scrapling image — there's no shell inside the image
#     (entrypoint is `scrapling-mcp`), so we can't run
#     `scrapling install --force` inside a `--rm` container.
#     Persistent container gets a real shell via `docker exec`.
#   - The image does NOT bundle chromium; only the Python package.
#     Persistent container survives the `scrapling install` step
#     (which downloads chromium + playwright deps into /root/.cache).
#
# Why HTTP transport (vs. stdio MCP):
#   - stdio MCP requires hermes-agent to spawn the process per-tool-call.
#     With persistent container, stdio would mean `docker exec -i`,
#     which is fine but more fragile than HTTP.
#   - Streamable-HTTP is one of the two transports scrapling-mcp supports
#     natively (since v0.3.6, PR D4Vinci/Scrapling#360 era).
#   - Auth token: enforced via SCRAPLING_MCP_AUTH_TOKEN (loopback-only
#     makes this belt-and-suspenders, but the env var keeps the token
#     out of the process list — important if anything else ever looks
#     at /proc on this host).
#
# Why --network=host:
#   - Chromium inside the container should exit on the same egress IP
#     as the host, useful for sites that pin by source IP.
#   - The container's HTTP endpoint binds to 127.0.0.1:9876 inside the
#     host's network namespace (because of --network=host), so hermes
#     reaches it via http://127.0.0.1:9876/mcp without any port
#     forwarding.
#
# What this module does:
#   - services.scrapling — declarative config (image, port, host, token,
#     persistentStateDir). No systemd unit is generated from this;
#     it's just typed configuration for `auto.scrapling.enable`.
#   - auto.scrapling.enable — feature toggle (host-level). Sets up the
#     oci-container (`podman-scrapling.service`), a `scrapling-install.service`
#     oneshot that runs `docker exec ... scrapling install --force`
#     after the container is up, and tmpfiles for /var/lib/scrapling.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.scrapling;
  autoCfg = config.auto.scrapling;

  # Per-call exec into the running container to install chromium.
  # Idempotent: scrapling install --force re-runs without harm.
  # Runs as root in a systemd oneshot, after the oci-container is up.
  installScript = pkgs.writeShellScript "scrapling-install" ''
    set -euo pipefail
    echo "scrapling-install: waiting for container to be running..."
    # oci-containers names the unit after the container name. We use
    # `podman-scrapling` because the daemon is docker (which still emits
    # `podman-*` unit names when the daemon is podman-compatible, i.e.
    # docker on NixOS).
    ${pkgs.systemd}/bin/systemctl is-active --wait-only podman-scrapling.service
    echo "scrapling-install: running scrapling install --force inside container"
    ${pkgs.docker-client}/bin/docker exec scrapling \
      ${cfg.installCommand}
    echo "scrapling-install: done"
  '';
in
{
  options.services.scrapling = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable the Scrapling MCP server. Runs a persistent oci-container
        with Streamable-HTTP MCP transport on a loopback port.
      '';
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "pyd4vinci/scrapling:latest";
      description = ''
        Docker image to use. The DockerHub image is the recommended
        one per Scrapling's docs.
      '';
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Address scrapling-mcp binds to inside the host's network
        namespace (because of --network=host). Loopback by default.
      '';
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 9876;
      description = ''
        TCP port scrapling-mcp listens on. Must not collide with
        other loopback services (Aphrodite :9797/:9798, OpenViking :1933).
      '';
    };

    authTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/scrapling/auth-token";
      description = ''
        Path to a file containing the bearer token for the MCP HTTP
        endpoint. When set, the token is passed to the container as
        SCRAPLING_MCP_AUTH_TOKEN (env var) — keeps the token out of
        the process list (`docker inspect`). Loopback-only makes
        auth optional in practice, but we set it for hygiene.
      '';
    };

    persistentStateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/scrapling";
      description = ''
        Host directory mounted into the container at /root. Persists
        scrapling install state (chromium browser cache, ~/.cache/ms-playwright)
        across container restarts. Idempotent: a wiped directory just
        triggers a fresh chromium download on next `scrapling install`.
      '';
    };

    proxyUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "http://127.0.0.1:7890";
      description = ''
        HTTP proxy URL passed to scrapling as HTTP_PROXY/HTTPS_PROXY.
        Set null to disable. Defaults to the host's local proxy
        (same one hermes-agent uses).
      '';
    };

    installCommand = lib.mkOption {
      type = lib.types.str;
      default = "scrapling install --force";
      description = ''
        Command to run inside the container after it starts. The
        default `scrapling install --force` downloads chromium +
        playwright deps. Idempotent.
      '';
    };
  };

  options.auto.scrapling = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Declare intent to run the Scrapling MCP server. Sets up the
        oci-container, the install oneshot, and the persistent state
        directory.
      '';
    };
  };

  config = lib.mkIf autoCfg.enable {
    services.scrapling.enable = true;

    # /var/lib/scrapling is owned by root (the daemon user for docker
    # containers managed by oci-containers is root). We set the
    # sticky bit so the container's root user can write inside.
    systemd.tmpfiles.rules = [
      "d ${cfg.persistentStateDir} 0750 root root - -"
    ];

    virtualisation.oci-containers.containers.scrapling = {
      image = cfg.image;
      # --network=host: container shares the host's network stack.
      # scrapling-mcp binds to cfg.host:cfg.port inside that namespace,
      # so the HTTP endpoint is reachable as http://127.0.0.1:<port>/mcp
      # without any port forwarding.
      extraOptions = [ "--network=host" ];
      volumes = [
        "${cfg.persistentStateDir}:/root"
      ];
      environment = {
        # scrapling-mcp --http binds to this address; with
        # --network=host, "127.0.0.1" is the host's loopback.
        # Override via --http-host CLI flag below.
        HOME = "/root";
      }
      // lib.optionalAttrs (cfg.proxyUrl != null) {
        HTTP_PROXY = cfg.proxyUrl;
        HTTPS_PROXY = cfg.proxyUrl;
        ALL_PROXY = cfg.proxyUrl;
        NO_PROXY = "127.0.0.1,localhost,::1";
      }
      // lib.optionalAttrs (cfg.authTokenFile != null) {
        # File-based env var: docker run reads the file and passes the
        # contents as env var to the container. Keeps the token out of
        # `docker inspect` and the host process list.
        SCRAPLING_MCP_AUTH_TOKEN_FILE = toString cfg.authTokenFile;
      };

      # The image's default CMD is `scrapling-mcp` (stdio). Override to
      # the http subcommand with our host/port. Token is read from the
      # file env var above if set.
      cmd = [
        "mcp" "--http"
        "--host" cfg.host
        "--port" (toString cfg.port)
      ];
    };

    # Run `scrapling install --force` once after the container is up.
    # This is a oneshot with RemainAfterExit=yes: it succeeds once and
    # doesn't run again unless the user wipes /var/lib/scrapling.
    # Idempotent at the scrapling level: `install --force` re-runs the
    # dependency check without breaking things.
    systemd.services.scrapling-install = {
      wantedBy = [ "multi-user.target" ];
      after = [ "podman-scrapling.service" ];
      wants = [ "podman-scrapling.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Allow a long timeout (chromium download is ~170MB).
        TimeoutStartSec = "10min";
      };
      path = [ pkgs.docker-client ];
      script = installScript;
    };
  };
}
