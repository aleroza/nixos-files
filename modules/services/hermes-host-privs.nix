# Hermes-host privileges — unblock end-to-end OpenViking integration.
#
# While we debug OpenViking memory-provider wiring we let hermes
# elevate through sudo to specific commands (restart openviking-*
# units, look at their logs). The upstream hermes-agent NixOS
# module sets `NoNewPrivileges = true` on its own unit, which
# prevents sudo from granting root. We override it just for
# hermes-agent — every other unit keeps its full hardening. sudo
# itself uses an explicit allowlist (services.sudo.extraRules in
# hermes.nix), never `NOPASSWD: ALL`.
#
# Both halves are gated by their own `auto` flag so they can be
# switched off together when proper approval flow (smart_policy +
# issue #5528 path-anchored dangerous patterns) lands.

{ config, lib, pkgs, ... }:

let
  cfg = config.auto.hermes-host-privs;
in
{
  options.auto.hermes-host-privs = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Let the hermes-agent service (and user `hermes`) elevate
        via sudo to a small allowlist of restart/log commands, and
        disable NoNewPrivileges on hermes-agent.service. Dev only.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Override the upstream hermes-agent NixOS module's hardening
    # so sudo actually works for the gateway process. The
    # upstream module sets (all via plain attrs, not mkForce, so
    # we override with mkForce):
    #   NoNewPrivileges = true;
    #   ProtectSystem = "strict";
    #   ...
    #
    # We force-disable just enough to let sudo:
    #   - NoNewPrivileges: lets sudo escalate from inside
    #     hermes-agent.service.
    #   - ProtectSystem: must be off (or "no") so the process can
    #     write to /run/sudo (where sudo persists per-uid
    #     timestamp files). NixOS's stricter values ("strict",
    #     "full", "64") make /run read-only for unprivileged
    #     users, which breaks NOPASSWD sudo under NNP=false
    #     because sudo can't create /run/sudo/ts/<uid>.
    #
    # Anything else (ProtectHome, UMask, etc.) we leave alone —
    # the upstream module's defaults aren't blocking sudo.
    systemd.services.hermes-agent.serviceConfig.NoNewPrivileges = lib.mkForce false;
    systemd.services.hermes-agent.serviceConfig.ProtectSystem = lib.mkForce "no";
  };
}
