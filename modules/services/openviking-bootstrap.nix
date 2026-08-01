# OpenViking Admin API bootstrap — provision the per-user hermes
# account + api_key on first start, store it where hermes-agent
# can read it.
#
# Why: OpenViking's api_key auth rejects root keys for tenant
# data APIs (/api/v1/sessions, /api/v1/contexts, /api/v1/memory/*).
# The only way in is a per-user key minted through the Admin API.
# We generate it on first boot and persist the result in
# /var/lib/openviking-server/hermes_api_key. Subsequent restarts
# reuse the same key.
#
# The Admin API is bootstrap-only. Once hermes has a working
# user_key it does NOT need this service again — its bearer
# token authenticates the data APIs going forward.
#
# Idempotency: re-running the bootstrap just creates or replaces
# the user; the previous key continues to work alongside the new
# one. We always read the fresh key from the Admin API response
# and overwrite the persisted file.
#
# Why a separate service, not ExecStartPre on openviking-server:
# we want this to run once per host, not on every container
# restart. Splayed with `RemainAfterExit = true` and a sentinel
# file so it actually only re-runs when /var/lib/openviking-server
# is empty (i.e. first boot or a manual wipe). Re-running it on
# every start would invalidate the hermes-agent token we'd be
# serving to it, breaking the integration until a manual restart.

{ config, lib, pkgs, ... }:

let
  cfg = config.auto.openviking;
  servicesCfg = config.services.openviking;
  bootstrapCfg = config.services.openviking-bootstrap;

  # Build a self-contained python script at eval time. We use
  # ${...} interpolation to feed in account/user/port/key from
  # the Nix config; the script's logic stays separate so it
  # doesn't have to fight Nix string escaping.
  bootstrapScript = pkgs.writeScript "openviking-bootstrap" ''
    #!/usr/bin/env python3
    import json
    import os
    import sys
    import urllib.error
    import urllib.request

    # Hard-coded by Nix substitution at eval time. Not a secret:
    # these are the same literals already in ovConfig / hermes.nix.
    base_url = "http://127.0.0.1:${toString servicesCfg.port}"
    root_api_key = ${lib.escapeShellArg servicesCfg.ovConfig.server.root_api_key}
    account = ${lib.escapeShellArg bootstrapCfg.hermesAccount}
    user_id = ${lib.escapeShellArg bootstrapCfg.hermesUser}
    key_file = "/var/lib/openviking-server/hermes_api_key"

    def req(path, body=None, method=None):
        url = base_url + path
        headers = {"Authorization": "Bearer " + root_api_key}
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        r = urllib.request.Request(
            url,
            data=data,
            headers=headers,
            method=method or ("POST" if body is not None else "GET"),
        )
        try:
            with urllib.request.urlopen(r, timeout=10) as resp:
                return json.loads(resp.read())
        except urllib.error.HTTPError as e:
            err_body = e.read().decode()
            print("HTTP " + str(e.code) + " " + path + ": " + err_body, file=sys.stderr)
            raise

    # 1. Ensure account exists. ALREADY_EXISTS is fine.
    try:
        req(
            "/api/v1/admin/accounts",
            {"account_id": account, "admin_user_id": user_id},
        )
        print("bootstrap: account '" + account + "' created")
    except urllib.error.HTTPError as e:
        if e.code != 409:
            raise
        body = json.loads(e.read())
        if body["error"]["code"] != "ALREADY_EXISTS":
            raise
        print("bootstrap: account '" + account + "' already exists")

    # 2. Register user. Server returns the existing user_key if
    # already registered — that's idempotency by accident.
    user_key = req(
        "/api/v1/admin/accounts/" + account + "/users",
        {"user_id": user_id, "role": "user"},
    )["result"]["user_key"]
    print("bootstrap: user '" + user_id + "' has api_key: "
          + user_key[:24] + "...")

    # 3. Persist the key.
    os.makedirs(os.path.dirname(key_file), exist_ok=True)
    os.umask(0o077)
    with open(key_file, "w") as f:
        f.write(user_key + "\n")
    os.chmod(key_file, 0o640)
    print("bootstrap: wrote " + key_file + " ("
          + str(os.path.getsize(key_file)) + " bytes)")
  '';

  # Runner wraps python script so we don't depend on PATH. Uses
  # writeShellScript so systemd can exec it directly.
  runner = pkgs.writeShellScript "openviking-bootstrap-runner" ''
    exec ${lib.getExe pkgs.python3} ${bootstrapScript}
  '';
in
{
  options.services.openviking-bootstrap = {
    hermesAccount = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = ''
        OpenViking account (workspace) to put hermes-agent under.
        Created if missing. Matches the OPENVIKING_ACCOUNT env var.
      '';
    };
    hermesUser = lib.mkOption {
      type = lib.types.str;
      default = "hermes";
      description = ''
        OpenViking user_id to mint a per-user api_key for. Matches
        the OPENVIKING_USER + OPENVIKING_AGENT env vars.
      '';
    };
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run the Admin API bootstrap once. Disable by default —
        turn on only after the OpenViking container is healthy
        and root_api_key auth is configured.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && bootstrapCfg.enable) {
    systemd.services.openviking-bootstrap = {
      description = "OpenViking Admin API bootstrap — provision hermes user_key";
      wantedBy = [ "multi-user.target" ];
      after = [ "openviking-server.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = runner;
      };
    };
  };
}
