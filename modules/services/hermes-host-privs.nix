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
    # Allow sudo to actually elevate hermes-agent processes —
    # the upstream hermes-agent module sets NoNewPrivileges=true
    # which blocks sudo even when our extraRules would otherwise
    # allow it. We force-disable NNP just for hermes-agent.
    # Other units keep their full hardening.
    #
    # Implementation: hermes-agent isn't its own NixOS module
    # for system unit options (services.hermes-agent is a
    # declarative wrapper, not an option namespace), so we have
    # to override the underlying systemd.services path.
    # NixOS merge of `systemd.services.X.serviceConfig.*` is
    # recursive — this single-key assignment overrides only
    # NoNewPrivileges without disturbing any other field.
    systemd.services.hermes-agent.serviceConfig.NoNewPrivileges = lib.mkForce false;
  };
}
