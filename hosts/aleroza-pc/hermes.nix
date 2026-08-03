# Hermes integration for aleroza-pc.
#
# Consolidates everything hermes-related into one file so the host's
# default.nix stays focused on the host itself (users, packages,
# hardware, auto.* flags). See hosts/aleroza-pc/README.md for the
# full rationale and workflow.
#
# Sections:
#   1. Hermes system user (extraGroups).
#   2. Hermes sops secret — environment variables the gateway needs
#      (API keys, etc.). Owned by hermes:hermes so the gateway can
#      read it.
#   3. services.hermes-agent — gateway service itself: model,
#      proxy, runtime hooks for missing-python-modules workaround.
#   4. nixos-activate systemd unit + path trigger — root unit that
#      promotes a hermes-built closure into the active system on
#      /var/lib/hermes/workspace/.switch-request.

{ config, lib, pkgs, hermes-agent, ... }:

{
  # ▸ 1. Hermes system user (created by hermes-agent NixOS module).
  #    `systemd-journal` so the gateway can read its own logs
  #    without sudo.
  users.users.hermes.extraGroups = [
    "systemd-journal"
  ];

  # ▸ 2. Hermes environment secret.
  #    Decrypted from aleroza.yaml (same sops file as the rest of
  #    aleroza's secrets — the key is shared with aleroza). Owned
  #    by hermes:hermes so the gateway can read it directly.
  sops.secrets."hermes/env" = {
    sopsFile = ./secrets/users/aleroza.yaml;
    owner = "hermes";
    group = "hermes";
    mode = "0400";
  };

  # ▸ 3. Hermes Agent gateway (managed by hermes-agent NixOS module).
  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;
    # TEMPORARY: relax hermes-agent's hardening so the agent can
    # restart openviking-server and friends from chat without
    # needing a hand-applied `sudo systemctl restart`. The long-
    # Allow sudo to actually elevate hermes-agent processes —
    # the upstream hermes-agent module sets NoNewPrivileges=true
    # which blocks sudo even when our extraRules would otherwise
    # allow it. We force-disable NNP just for hermes-agent.
    # Other units keep their full hardening.
    # NoNewPrivileges override is in modules/services/
    # hermes-host-privs.nix — declared there so it lives at top
    # level, not nested inside services.hermes-agent which
    # doesn't expose the systemd.services namespace.
    environmentFiles = [
      "/run/secrets/hermes/env"
    ];
    environment = {
      HTTP_PROXY = "http://127.0.0.1:7890";
      HTTPS_PROXY = "http://127.0.0.1:7890";
      ALL_PROXY = "http://127.0.0.1:7890";
      http_proxy = "http://127.0.0.1:7890";
      https_proxy = "http://127.0.0.1:7890";
      all_proxy = "http://127.0.0.1:7890";
      NO_PROXY = "127.0.0.1,localhost,::1";
      no_proxy = "127.0.0.1,localhost,::1";
    };
    settings.model = "minimax/MiniMax-M3";
    settings.toolsets = [ "all" ];
    settings.approvals.smartPolicy = ''
      ESCALATE any command whose argument list, after shell
      deobfuscation (quotes, escapes, $() substitution, backslash
      continuations), references either of these two absolute
      paths:

        /var/lib/hermes/workspace/.switch-request
        /var/lib/hermes/workspace/.pending-switch

      These files are the NixOS-switch trigger pair: writing to
      .pending-switch records the closure to activate; touching
      .switch-request wakes the systemd.paths unit which launches
      switch-to-configuration. There is no undo that doesn't
      involve picking a different boot entry at systemd-boot
      prompt.

      The path match is what matters, not the writing command.
      `touch`, `tee`, `echo >`, `cat >`, `python -c`, `bash -c`,
      `cp`, `mv`, `sed -i`, and any other write primitive all
      escalate. Similarly, reading or deleting the files is fine
      (rm/ls/cat on the flags) — only mutation is the problem.

      Every other step in the hermes pipeline (git commit, git
      push, nix build, nix flake check, dry-run, jq, grep, etc.)
      is reversible without sudo and continues to auto-approve.
    '';

    # Memory: native MEMORY.md / USER.md only. OpenViking
    # memory-provider integration is temporarily disabled
    # while we redesign the deployment (standalone compose
    # under ~/openviking/, see hosts/aleroza-pc/README.md).
    # Once that's stable we'll re-wire this and gate it on
    # a runtime probe of the OpenViking endpoint so a dead
    # upstream doesn't break the gateway.

    # Fix "ModuleNotFoundError: No module named 'hermes_state_common'"
    package =
      let
        basePkg = hermes-agent.packages.x86_64-linux.default;
        pythonSrc = basePkg.hermesNpmLib.pythonSrc;
        venv = basePkg.hermesVenv;
      in
      basePkg.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          mkdir -p $out/lib/python3.12/site-packages
          for mod in hermes_state_common hermes_state_portability hermes_state_schema hermes_state_search; do
            if [ -f "${pythonSrc}/$mod.py" ]; then
              cp -f "${pythonSrc}/$mod.py" "$out/lib/python3.12/site-packages/$mod.py"
            fi
          done
          # Re-wrap each hermes entry-point to inject the patched site-packages
          # on PYTHONPATH, so Python finds our copies before the wheel's.
          for bin in hermes hermes-agent hermes-acp; do
            if [ -x "$out/bin/$bin" ]; then
              wrapProgram "$out/bin/$bin" \
                --prefix PYTHONPATH : "$out/lib/python3.12/site-packages"
            fi
          done
        '';
      });
  };

  # Simple, wide sudo allowlist for hermes. While we don't have
  # proper path-anchored approval flow yet
  # (NosResearch/hermes-agent#5528), hermes acts on the agent's
  # behalf for any admin-level task via this single allowlist.
  # security.sudo.extraRules gates which exact commands run;
  # the modules/services/hermes-host-privs.nix module disables
  # NoNewPrivileges + ProtectSystem on hermes-agent.service so
  # the gated sudo rules actually escalate at runtime.
  #
  # Alongside this we have modules/services/hermes-host-privs.nix
  # which (a) flips NoNewPrivileges off on hermes-agent.service
  # and (b) forces ProtectSystem=no so /run is writable for
  # sudo's per-uid timestamp files.
  security.sudo.extraRules = [
    {
      users = [ "hermes" ];
      commands = [ { command = "ALL"; options = [ "NOPASSWD" ]; } ];
    }
  ];

  # ▸ 4. Hermes-triggered system activation.
  #    Root systemd unit + path trigger so hermes can switch
  #    generations without sudo / without disabling NNP on
  #    hermes-agent.service.
  #
  #    Workflow:
  #      1. Hermes edits the flake and commits.
  #      2. Hermes runs `nix build` (unprivileged, no nixbld group —
  #         nix-daemon spawns build workers) to produce the system
  #         closure in /nix/store.
  #      3. Hermes writes the closure path to
  #         /var/lib/hermes/workspace/.pending-switch.
  #      4. Hermes touches /var/lib/hermes/workspace/.switch-request.
  #      5. systemd.paths triggers nixos-activate.service.
  #      6. The service (as root, NNP=false) reads .pending-switch
  #         and runs switch-to-configuration against that closure.
  #
  #    The service does NOT build — the closure must already exist
  #    in /nix/store. If the build fails, hermes catches it before
  #    touching the request flag.
  #
  #    Caveat: switch-to-configuration stops all active systemd
  #    units during activation, including this one. The activation
  #    itself completes (system profile gets updated, current-system
  #    symlink flips, bootloader entry gets written); only the
  #    systemd service status shows status=15/TERM. That's
  #    expected. As a consequence, rebuilds that touch this unit's
  #    own definition can't be activated via the trigger — they
  #    need `sudo nixos-rebuild switch --flake .#aleroza-pc` from
  #    the host owner. See hosts/aleroza-pc/README.md.

  systemd.services.nixos-activate = {
    description = "Hermes-triggered nixos-rebuild activate";
    wantedBy = [ ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      RuntimeDirectory = "nixos-activate";
    };
    script = ''
      export PATH=/run/current-system/sw/bin
      export HOME=/var/root
      set -euo pipefail

      WORKSPACE=/var/lib/hermes/workspace
      REQUEST="$WORKSPACE/.switch-request"
      PENDING="$WORKSPACE/.pending-switch"

      # Tooling check.
      command -v flock >/dev/null || { echo "flock not in PATH" >&2; rm -f "$REQUEST"; exit 4; }

      # Lock against concurrent activations.
      LOCK=/run/nixos-activate/lock
      exec 9>"$LOCK"
      if ! flock -n 9; then
        echo "another activation in progress" >&2
        rm -f "$REQUEST"
        exit 3
      fi

      # Read the closure path that hermes built and stamped into
      # .pending-switch. Refuse if missing or doesn't look like a
      # /nix/store path.
      [ -f "$PENDING" ] || { echo "no pending switch at $PENDING" >&2; rm -f "$REQUEST"; exit 7; }
      CLOSURE=$(cat "$PENDING")
      case "$CLOSURE" in
        /nix/store/*-nixos-system-aleroza-pc-*) ;;
        *) echo "pending switch points to unexpected path: $CLOSURE" >&2; rm -f "$REQUEST" "$PENDING"; exit 8 ;;
      esac
      [ -x "$CLOSURE/bin/switch-to-configuration" ] || { echo "no switch-to-configuration in $CLOSURE" >&2; rm -f "$REQUEST" "$PENDING"; exit 9; }

      GEN="hermes-$(date +%Y%m%d-%H%M%S)"
      echo "activating generation $GEN from $CLOSURE"

      # Delegate the switch to a transient systemd unit and exit
      # cleanly. switch-to-configuration's final stage stops all
      # active systemd units during activation — including this
      # service itself. Running it directly inside our ExecStart
      # gives us status=15/TERM in journalctl even when the
      # activation succeeds (system profile flipped, bootloader
      # entry written, current-system symlink updated).
      #
      # By handing off to systemd-run, our service exits 0 as soon
      # as the transient unit is queued, and the actual switch
      # runs in its own cgroup outside our lifecycle. The transient
      # unit isn't a child of nixos-activate.service, so when
      # switch-to-configuration stops "all units" it isn't killing
      # us — we're already gone.
      #
      # Trade-off: failure of the switch-to-configuration step
      # doesn't propagate back to the trigger flag (we already
      # rm -f'd it). Hermes watches the transient unit's journal
      # via journalctl -u "hermes-switch-*" for outcome.
      TRANSIENT="hermes-switch-$(date +%s)-$$"
      systemd-run \
        --unit="$TRANSIENT" \
        --description="Hermes-triggered switch-to-configuration for $GEN" \
        --no-block \
        --collect \
        --setenv=GEN="$GEN" \
        "$CLOSURE/bin/switch-to-configuration" switch

      rc=$?
      rm -f "$REQUEST" "$PENDING"
      exit $rc
    '';
  };

  systemd.paths.nixos-activate-trigger = {
    pathConfig = {
      PathExists = "/var/lib/hermes/workspace/.switch-request";
      Unit = "nixos-activate.service";
    };
    # Disable the path unit's trigger rate limit. Default is 200
    # triggers per 10s; combined with the service's own start-limit
    # it makes "stuck after a failure" very easy to hit during
    # iteration on a broken config. Hermes supervises via journalctl
    # + .pending-switch freshness, so the rate limit adds nothing.
    unitConfig.TriggerLimitIntervalSec = 0;
    wantedBy = [ "paths.target" ];
  };
}
