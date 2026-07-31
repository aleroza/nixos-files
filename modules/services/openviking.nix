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
  };

  config = lib.mkIf autoCfg.enable {

    # Hard dependency on Docker (or podman) — there's no point
    # running a container without a daemon. virtualisation.oci-containers
    # itself enables podman by default, but we anchor on the
    # auto.docker flag because that's what the host owner
    # already configures.
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
        "/etc/openviking/ov.conf:/etc/openviking/ov.conf:ro"
      ];
      environment = {
        # The container's openviking-server reads its config from
        # /etc/openviking/ov.conf by default.
        OPENVIKING_CONFIG_FILE = "/etc/openviking/ov.conf";
      };
      # The container expects to write its DB to /data; map that
      # to the host's dataDir.
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
        ExecStart = "/bin/true";
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
