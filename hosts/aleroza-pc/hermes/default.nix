# Hermes integration for aleroza-pc.
#
# Consolidates everything hermes-related into one file so the host's
# default.nix stays focused on the host itself. This module lives in
# hosts/aleroza-pc/hermes/ alongside BOOT.md and any gateway hooks we
# drop in. See hosts/aleroza-pc/README.md for the full rationale.
#
# Sections:
#   0. ./aphrodite.nix import — declares the PlayForm/Aphrodite-Hermes
#      plugin + companion binaries (proxy + cdylib) as Nix store
#      derivations; activation script symlinks them into
#      ~/.hermes/plugins/aphrodite/ with hermes:hermes ownership.
#      Plugin source lives in the store, not in /var/lib/hermes —
#      only symlinks (clone mirror + plugin dir + binaries/) live
#      on disk so upgrades from the store propagate on activation.
#   1. Hermes system user (extraGroups).
#   2. Hermes sops secret — environment variables the gateway needs
#      (API keys, etc.). Owned by hermes:hermes so the gateway can
#      read it.
#   3. services.hermes-agent — gateway service itself: model, proxy,
#      memory provider, runtime hooks for missing-python-modules
#      workaround.
#   4. nixos-activate systemd unit + path trigger — root unit that
#      promotes a hermes-built closure into the active system on
#      /var/lib/hermes/workspace/.switch-request.

{
  config,
  lib,
  pkgs,
  hermes-agent,
  ...
}:

{
  imports = [
    ./aphrodite.nix
  ];

  # ▸ 1. Hermes system user (created by hermes-agent NixOS module).
  #    systemd-journal so the gateway can read its own logs without
  #    sudo. openviking so the gateway can read the user_key env-file
  #    at /opt/openviking/keys/user_key (mode 0640 openviking:openviking).
  users.users.hermes.extraGroups = [
    "systemd-journal"
    "openviking"
  ];

  # ▸ 2. Hermes environment secret.
  #    Decrypted from aleroza.yaml (same sops file as the rest of
  #    aleroza's secrets — the key is shared with aleroza). Owned
  #    by hermes:hermes so the gateway can read it directly.
  sops.secrets."hermes/env" = {
    sopsFile = ../secrets/users/aleroza.yaml;
    owner = "hermes";
    group = "hermes";
    mode = "0400";
  };

  # ▸ 3. Hermes Agent gateway (managed by hermes-agent NixOS module).
  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;

    # Register the PlayForm/Aphrodite-Hermes plugin via the bare-
    # name symlink in ~/.hermes/plugins/aphrodite. The activation
    # script in ./aphrodite.nix materialises the plugin source
    # tree (fetched via fetchFromGitHub) and the two companion
    # binaries (aphrodite + libaphrodite_hermes.so, fetched via
    # fetchurl from PlayForm/Aphrodite/releases) as Nix-store
    # backed symlinks. The plugin's own __init__.py spawns the
    # proxy binary as a subprocess on first tool call, so we do
    # NOT need a separate systemd unit (services.aphrodite was
    # removed). The proxy listens on 127.0.0.1:9798 by default.
    #
    # We intentionally do NOT use services.hermes-agent.extraPlugins
    # here — that NixOS module creates a nix-managed-aphrodite
    # symlink, not the bare-name aphrodite the plugin's
    # download.sh expects, and we'd lose control of the
    # binaries/ directory layout.

    # EnvironmentFiles are loaded in order. Later entries overwrite
    # earlier ones on duplicate KEYs. The first one is the
    # user-managed sops env (TELEGRAM_BOT_TOKEN, etc.). The second
    # is the OpenViking user_key written by services.openviking-
    # bootstrap (mode 0640 openviking:openviking, hermes user is
    # in group openviking for read access).
    environmentFiles = [
      "/run/secrets/hermes/env"
      "/opt/openviking/keys/user_key"
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
      # OpenViking client connection. Endpoint is the container
      # bound to 127.0.0.1:1933 (host network mode + server bind
      # override). OPENVIKING_API_KEY is provided by the second
      # EnvironmentFile above. ACCOUNT / USER are local-mode
      # identifiers the server uses to scope data.
      OPENVIKING_ENDPOINT = "http://127.0.0.1:1933";
      OPENVIKING_ACCOUNT = "default";
      OPENVIKING_USER = "default";

      # Opt-in flag for the Aphrodite plugin's context-engine
      # registration. The plugin's on_session_start hook only
      # calls ctx.register_context_engine(...) if this is set,
      # otherwise it stays silent and Hermes falls back to its
      # built-in compressor with a 'Context engine aphrodite
      # not found' warning. The AphroditeContextEngine class
      # itself is a noop (should_compress returns False,
      # compress returns messages unchanged) — it's just a
      # presence signal so Hermes treats the plugin as the
      # configured context engine. Real compression still
      # flows through the proxy's transform_tool_result hook.
      APHRODITE_CONTEXT_ENGINE = "1";
    };
    # Default to routing through the local Aphrodite CCR proxy
    # (127.0.0.1:9798, see services.aphrodite). The model name
    # uses the "provider/model" form so the gateway resolves it
    # against the providers.* map below. Switching the upstream
    # model name in one place (services.aphrodite.defaultModel)
    # propagates here.
    settings.model = "minimax/MiniMax-M3";

    # Sub-agents inherit delegation.model from settings; primary
    # session keeps settings.model above. Aphrodite proxies the
    # M2.7 model through the same upstream (api_url+api_key), so
    # it routes via the same provider.
    settings.delegation.model = "minimax/MiniMax-M2.7";
    settings.toolsets = [ "all" ];

    # Plugin enablement is handled by the activation script in
    # ./aphrodite.nix, which materialises ~/.hermes/plugins/
    # aphrodite as a Nix-store-backed symlink with hermes:hermes
    # ownership. The gateway picks up plugins from ~/.hermes/
    # plugins/ at startup automatically; no settings.plugins.*
    # wiring needed here (that's the path for non-NixOS installs).
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

    # Memory provider: OpenViking. The plugin in upstream
    # hermes-agent reads OPENVIKING_* env from environmentFiles +
    # settings. Built-in MEMORY.md / USER.md stay active alongside
    # — OpenViking is additive.
    #
    # If the OpenViking server is unreachable at gateway startup,
    # the plugin logs a WARNING and the gateway continues with
    # degraded memory (built-in only). The boot-md hook drops a
    # Telegram notification so the user knows the upstream is
    # broken. Restart hermes-agent once the server is healthy and
    # the plugin reconnects.

    settings.providers = {
      minimax = {
        api_key_env = "MINIMAX_API_KEY";
        base_url = "https://api.minimax.io/anthropic";
        provider = "anthropic";
      };
    };
    settings.memory.provider = "openviking";
    settings.context.engine = "aphrodite";
    settings.context.engine_threshold_pct = 55;

    settings.memory.userProfileEnabled = true;

    # ▸ STT (speech-to-text) for voice messages on Telegram.
    #    Groq's whisper-large-v3 gives excellent Russian
    #    recognition, free tier, and offloads work from the CPU
    #    (important on the 4300U / 7GB host). The GROQ_API_KEY
    #    is provisioned by /run/secrets/hermes/env (sops secret,
    #    see sops.secrets."hermes/env" above). The gateway reads
    #    api_key_env, fetches the key from the gateway's
    #    environment, and forwards it to Groq.
    settings.stt = {
      enabled = true;
      provider = "groq";
      groq.api_key_env = "GROQ_API_KEY";
      # Pin the transcription language to Russian. Without this hint,
      # Groq's whisper-large-v3 sometimes "drifts" to English on short
      # voice notes (a known whisper behaviour) and the user sees an
      # English transcript of Russian speech. Resolution order in
      # hermes-cli: stt.<provider>.language → stt.language → env.
      language = "ru";
    };

    # ▸ MCP servers (HTTP transport for persistent oci-containers).
    #    Hermes connects to running services over loopback HTTP. No
    #    stdio spawn — the services manage their own lifecycle.
    #
    #    Scrapling (D4Vinci/Scrapling) — adaptive web-fetch with
    #    built-in anti-bot bypass (Cloudflare Turnstile, fingerprint
    #    spoofing). Runs as a persistent oci-container with
    #    Streamable-HTTP MCP transport on 127.0.0.1:9876
    #    (managed by modules/services/scrapling.nix). 10 MCP tools:
    #    get, bulk_get, fetch, bulk_fetch, stealthy_fetch,
    #    bulk_stealthy_fetch, screenshot, open_session, close_session,
    #    list_sessions.
    #
    #    Loopback-only because:
    #    - Chromium inside the container exits on the host's egress
    #      IP via --network=host (useful for sites that pin by source IP).
    #    - The container's HTTP endpoint binds to 127.0.0.1:9876 in
    #      the host's network namespace, so no port forwarding needed.
    #    - The auth token is set on the container via
    #      SCRAPLING_MCP_AUTH_TOKEN_FILE (see modules/services/scrapling.nix).
    settings.mcp_servers.scrapling = {
      command = "docker";
      args = [
        "run"
        "-i"
        "--rm"
        "--network"
        "host"
        "-e"
        "HTTP_PROXY"
        "-e"
        "HTTPS_PROXY"
        "-e"
        "NO_PROXY"
        "pyd4vinci/scrapling:latest"
        "mcp"
      ];
      env = {
        HTTP_PROXY = "http://127.0.0.1:7890";
        HTTPS_PROXY = "http://127.0.0.1:7890";
        NO_PROXY = "127.0.0.1,localhost,::1";
      };
      # MCP servers default to a short connect timeout. Scrapling
      # cold-starts a chromium browser on first tool call, which
      # can take 5-8s on the 4300U. Give it room.
      connect_timeout = 30;
      timeout = 60;
    };

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
  # security.sudo.extraRules gates which exact commands run.
  # The sudo escalation itself is enabled by force-disabling
  # NoNewPrivileges + ProtectSystem on hermes-agent.service
  # below — see the comment block further down.
  security.sudo.extraRules = [
    {
      users = [ "hermes" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # Force-disable NoNewPrivileges + ProtectSystem on hermes-agent so
  # the sudo allowlist above actually escalates. The upstream
  # hermes-agent NixOS module sets NNP=true (no privilege gain after
  # exec) and ProtectSystem=strict (read-only /run). Both block sudo
  # from doing anything useful: NNP halts the setuid binary, and a
  # read-only /run breaks sudo per-uid timestamp files.
  # Units that hermes-agent itself spawns keep their full hardening.
  systemd.services.hermes-agent.serviceConfig.NoNewPrivileges = lib.mkForce false;
  systemd.services.hermes-agent.serviceConfig.ProtectSystem = lib.mkForce "no";

  # Needed for linking Aphrodite library
  systemd.services.hermes-agent.serviceConfig.Environment = [
    "LD_LIBRARY_PATH=${lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ]}"
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

  # ▸ 5. Hermes Agent gateway hooks.
  #    Drop-in directory under ~/.hermes/hooks/. Each subdir with
  #    HOOK.yaml + handler.<ext> is loaded by the gateway on
  #    startup. The boot-md hook probes OpenViking at gateway
  #    startup and notifies the first user in TELEGRAM_ALLOWED_USERS
  #    if the upstream is degraded.
  #
  #    Rendered from this source tree at activation time. The hooks
  #    land at /var/lib/hermes/.hermes/hooks/ (system user's
  #    HERMES_HOME).
  system.activationScripts."hermes-boot-md" = {
    text = ''
      # Source tree is ${./hooks}, target is /var/lib/hermes/.hermes/hooks.
      # The .hermes tree is owned by hermes:hermes (set up by
      # services.hermes-agent's own activation script). We just
      # need to copy the boot-md subdir.
      mkdir -p /var/lib/hermes/.hermes/hooks
      cp -r ${./hooks}/boot-md /var/lib/hermes/.hermes/hooks/boot-md
      chmod 0750 /var/lib/hermes/.hermes/hooks/boot-md
      chmod 0640 /var/lib/hermes/.hermes/hooks/boot-md/HOOK.yaml
      chmod 0750 /var/lib/hermes/.hermes/hooks/boot-md/handler.sh
      chown -R hermes:hermes /var/lib/hermes/.hermes/hooks

      # Drop BOOT.md next to the hook so humans can read it.
      cp ${./BOOT.md} /var/lib/hermes/.hermes/BOOT.md
      chmod 0640 /var/lib/hermes/.hermes/BOOT.md
      chown hermes:hermes /var/lib/hermes/.hermes/BOOT.md
    '';
    deps = [ "hermes-agent-setup" ];
  };
}
