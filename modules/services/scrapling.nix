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
#     Persistent container gets a real shell via `podman exec`.
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
      default = "install --force";
      description = ''
        Command to run inside the container after it starts. The
        default `install --force` invokes scrapling's `install`
        subcommand via the uv-tool wrapper (entrypoint = `uv run
        scrapling`, console scripts pass through as args). This
        downloads chromium + playwright deps. Idempotent.
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
        # Point scrapling at the chromium symlink created by the
        # activation script (scrapling-pre-install). The symlink
        # resolves to whichever chromium-NNNN exists in the
        # persistent state dir, regardless of Playwright revision.
        # Without this, scrapling looks for chromium-1228 (the
        # version baked into the image at build time) and errors
        # with "Executable doesn't exist" because `scrapling install`
        # always fetches the latest Playwright chromium revision,
        # which drifts over time (1228 -> 1234 -> ...).
        SCRAPLING_EXECUTABLE_PATH = "/root/.cache/ms-playwright/chromium/chrome-linux64/chrome";
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
        "mcp"
        "--http"
        "--host"
        cfg.host
        "--port"
        (toString cfg.port)
      ];
    };

    # Run `scrapling install -f` once at activation time, as root,
    # so chromium is downloaded into the persistent state dir
    # BEFORE the container's MCP HTTP endpoint becomes available
    # to hermes.
    #
    # Why this is in activation, not a systemd oneshot:
    #   systemd oneshots run as the systemd user manager's user.
    #   On NixOS, podman exec requires root for rootful containers
    #   (oci-containers-managed), but rootless podman (the users
    #   default) cannot see them.
    #   Activation scripts always run as root, which is the user
    #   oci-containers uses to launch the container.
    #
    # Why we run a transient podman run --rm here:
    #   The persistent container scrapling does not exist yet on
    #   first activation. We use a separate ephemeral container
    #   with the same image and the same persistent volume mount
    #   to install chromium into the state dir. Once installed,
    #   the persistent container (launched later in the same
    #   activation cycle by oci-containers) finds chromium
    #   already in the persistent .cache/ms-playwright.
    #
    # Idempotency: skip if chromium is already installed (the
    # playwright cache directory has INSTALLATION_COMPLETE marker).
    # Also create a /root/.cache/ms-playwright/chromium symlink
    # pointing at whichever chromium-NNNN exists, so scrapling
    # can find the binary via SCRAPLING_EXECUTABLE_PATH=/root/.cache/ms-playwright/chromium/chrome
    # regardless of which Playwright revision `scrapling install`
    # fetched (1228, 1234, 1244, ...). The image was built with
    # playwright pinned to chromium-1228, but `scrapling install`
    # always fetches the latest version, and these versions drift.
    system.activationScripts.scrapling-pre-install = {
      text = ''
        if [ ! -f "${cfg.persistentStateDir}/.cache/ms-playwright/INSTALLATION_COMPLETE" ]; then
          echo "scrapling-pre-install: downloading chromium via ephemeral container"
          ${pkgs.podman}/bin/podman run --rm \
            --network=host \
            -v ${cfg.persistentStateDir}:/root \
            -e HOME=/root \
            ${cfg.image} \
            install -f
        else
          echo "scrapling-pre-install: chromium already installed, skipping download"
        fi
        # Always (re)create the chromium -> chromium-NNNN symlink, in
        # case the latest playwright revision bumped since last install.
        # Use /root/.cache/ms-playwright/chromium-1234 as the target
        # (a path INSIDE the container), not the host-side
        # /var/lib/scrapling/.cache/ms-playwright/chromium-1234.
        # Even though they're the same directory (host dir is
        # bind-mounted into the container at /root), symlinks resolve
        # to whatever path they were created with; an absolute path
        # to a host-only directory will be invalid inside the
        # container, while a relative or /root-anchored path works.
        rm -f ${cfg.persistentStateDir}/.cache/ms-playwright/chromium
        chromium_dir=$(ls -d ${cfg.persistentStateDir}/.cache/ms-playwright/chromium-* 2>/dev/null | head -n1)
        if [ -n "$chromium_dir" ]; then
          # Strip the host prefix, leaving a /root-anchored path.
          # pointer1
          ln -s "$rel_path" ${cfg.persistentStateDir}/.cache/ms-playwright/chromium
          echo "scrapling-pre-install: chromium symlink -> $rel_path"
        fi
      '';
      deps = [ "specialfs" ];
    };
  };
}

# in pointer1 was this line
#          rel_path="/root${chromium_dir#${cfg.persistentStateDir}}"
