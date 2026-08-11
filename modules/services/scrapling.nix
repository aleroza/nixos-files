# Scrapling — adaptive web-scraping framework by D4Vinci.
#
# This module is intentionally tiny. Scrapling ships as a Docker image
# (`pyd4vinci/scrapling`) that exposes an MCP server over stdio via
# the `mcp` subcommand. Hermes connects to it as a stdio MCP server
# (see hosts/aleroza-pc/hermes/default.nix →
# settings.mcp_servers.scrapling), spawning
# `docker run -i --rm --network host pyd4vinci/scrapling mcp` per
# tool invocation. No long-running container, no open port, no
# systemd service — the image is pulled once and cached by the
# docker daemon.
#
# Why no systemd unit?
#   - Scrapling is invoked lazily, only when a tool call needs it.
#   - stdio MCP transport means lifecycle = tool-call lifecycle.
#   - Cold start is ~1.5-2s on a warm image (vs ~3-5s if the
#     container had to start every time without caching).
#   - No state leaks between sessions; `docker run --rm` tears
#     down the chromium browser on every exit.
#
# Why `--network host` + `HTTP_PROXY` env together?
#   - `--network host` makes the container share the host's
#     network stack. This means the chromium browser inside
#     the container sees the **same IP** as the host on the
#     network — useful for sites that pin by egress IP.
#   - `HTTP_PROXY/HTTPS_PROXY` env vars tell scrapling (and
#     any underlying curl_cffi/Playwright) to route through
#     the host's local proxy (7890). This is the same proxy
#     that hermes-agent already uses (see
#     services.hermes-agent.environment in hermes/default.nix).
#   - Both together: container exits on the same IP as the
#     host, and that egress already goes through the proxy.
#     Substitutes your IP from inside the container, while
#     still using the host's connection.
#
# What this module does provide:
#   - `auto.scrapling.enable` — feature toggle. The actual
#     wiring lives in hosts/aleroza-pc/hermes/default.nix
#     (settings.mcp_servers.scrapling).
#   - `services.scrapling.image` — image reference, defaults
#     to `pyd4vinci/scrapling:latest` (matches the docs
#     recommendation; the ghcr.io/d4vinci/scrapling image is
#     a source-builder that re-resolves dependencies on every
#     start and fails behind a non-HTTP_PROXY-aware proxy).
#   - `services.scrapling.prePull` — when true, runs
#     `docker pull` at activation time so the first MCP
#     call doesn't pay the pull cost.
#
# Future work:
#   - Pin image digest (currently `pyd4vinci/scrapling:latest`,
#     which is mutable — re-pull may break compat with the
#     `mcp` tool schema if upstream changes it).
#   - Optional: pre-bake the image via `dockerTools.buildImage`
#     so scrapling is installed at build time and `mcp` doesn't
#     trigger a uv rebuild on first use.

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
        Enable the Scrapling MCP server. No systemd unit is
        generated; the server runs as a per-call stdio MCP
        process spawned by hermes-agent via
        `settings.mcp_servers.scrapling`.
      '';
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "pyd4vinci/scrapling:latest";
      description = ''
        Docker image to use for the Scrapling MCP server.
        Matches the recommendation in Scrapling's MCP docs.
      '';
    };

    mcpCommand = lib.mkOption {
      type = lib.types.str;
      default = "mcp";
      description = ''
        The command to run inside the container. The Scrapling
        image exposes `scrapling-mcp` (a shortcut added in
        v0.4.13) and `mcp` (a subcommand of the `scrapling`
        CLI). Both are equivalent. Default `mcp` matches the
        upstream Docker example in Scrapling's docs.
      '';
    };

    prePull = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        When true, runs `docker pull` on the configured image
        during NixOS activation. Pays the pull cost up-front
        so the first MCP tool call doesn't.
      '';
    };
  };

  options.auto.scrapling = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Declare intent to use the Scrapling MCP web-fetch
        container. This is the user-facing flag toggled from
        the host's `auto` block; it sets
        `services.scrapling.enable = true` and pre-pulls the
        image.
      '';
    };
  };

  config = lib.mkIf autoCfg.enable {
    services.scrapling.enable = true;
    services.scrapling.prePull = true;

    # Pre-pull the image at activation. Runs as root in the
    # system activation phase, before hermes-agent starts.
    # Idempotent: docker pull is a no-op if the local image
    # is already up to date.
    system.activationScripts."scrapling-pre-pull" = lib.mkIf cfg.prePull {
      text = ''
        echo "scrapling: pulling ${cfg.image}"
        ${pkgs.docker}/bin/docker pull ${lib.escapeShellArg cfg.image}
      '';
      deps = [ ];
    };
  };
}
