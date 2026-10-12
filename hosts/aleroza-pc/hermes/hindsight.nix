# Hindsight memory plugin for Hermes Agent — declarative install via Hermes's
# own `hermes plugins install` subcommand.
#
# Why this design (vs hosts/aleroza-pc/hermes/{aphrodite,openviking}.nix):
#
#   Aphrodite and OpenViking both predate `hermes plugins install`'s ability
#   to land plugins into $HERMES_HOME/plugins/ on NixOS without uv falling
#   over a read-only /nix/store site-packages. They sidestep that by hand-
#   rolling a Nix-store fetchFromGitHub + activation script that copies
#   __init__.py into a real (RW) directory in ~/.hermes/plugins/<name>/.
#   That works, but it duplicates the loader's own install logic — every
#   future plugin would mean another bespoke .nix file.
#
#   Hindsight ships in the upstream Hermes plugin catalog as a community
#   entry (vectorize-io, pinned @ eb6df499). `hermes plugins install
#   hindsight --yes-deps --no-enable` clones vectorize-io/hindsight into
#   ~/.hermes/plugins/hindsight/, runs uv to resolve its transitive
#   dependencies against the user's writable Python environment, and lays
#   the plugin tree down itself — the same path non-NixOS users take.
#
#   On NixOS the underlying concern (uv walking into a RO site-packages)
#   is moot because Hermes-agent ships with the plugin-runtime deps
#   already pinned in its /nix/store closure (see flake.nix's hermes-agent
#   overrideAttrs for httpx). The plugin's own Python deps land under
#   ~/.local/share/uv/... which is RW. Verified 2026-10-12 by running the
#   command on the live host (see feat/hindsight-memory, commit logs).
#
# What this module does:
#
#   1. Defines an activation script that checks whether the hindsight
#      plugin is already installed via `hermes plugins list hindsight`.
#   2. If not present, runs `hermes plugins install hindsight --yes-deps
#      --no-enable` as the hermes user. --yes-deps auto-consents to
#      Python dependency installation (required for non-interactive use),
#      --no-enable keeps the plugin inert until `settings.memory.provider`
#      is set to "hindsight" and the gateway restarts (we toggle that in
#      default.nix in the same commit).
#   3. Idempotent: the check-then-install pattern never produces journal
#      noise on subsequent activations.
#
# What this module does NOT do:
#
#   - Touch ~/.hermes/config.yaml. Plugin enablement is handled in
#     default.nix via settings.memory.provider = "hindsight" + a Hermes
#     restart. Setting it here would race with the activation script and
#     is cleaner at the services.hermes-agent.settings layer.
#   - Start a Hindsight daemon. Hindsight has three modes (cloud / local
#     external / local embedded); local embedded starts its own daemon on
#     first use via uvx. A dedicated modules/services/hindsight.nix
#     for the local-external / cloud-bridge modes is a follow-up.
#   - Disable or remove the openviking plugin. The catalog ships both;
#     `settings.memory.provider` chooses the active one. Removing
#     openviking on this commit would risk losing existing memories;
#     do that in a follow-up after we verify hindsight is healthy.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  hermesHome = "/var/lib/hermes";
  hermesBin = "/run/current-system/sw/bin/hermes";
in
{
  config = {

    # Activation: install hindsight if missing, no-op otherwise.
    #
    #   /var/lib/hermes/.hermes/plugins/hindsight/    (real dir, populated by hermes)
    #     ├── __init__.py, plugin.yaml, pyproject.toml, uv.lock, ...    (cloned from upstream)
    #
    # Tolerates /var/lib/hermes being absent: services.hermes-agent's own
    # activation creates the user + home before this script runs (deps
    # = [ "hermes-agent-setup" ]).
    #
    # Runs as the hermes user (not root) because `hermes plugins install`
    # materialises files into ~hermes/.hermes/ and must run with that
    # $HOME for path resolution. The hermes-agent-setup activation
    # creates the home first; by the time this script runs, the user
    # exists and the directory is RW.
    system.activationScripts."hindsight-plugin" = {
      deps = [ "hermes-agent-setup" ];
      text = ''
        set -euo pipefail

        # Activation scripts run with a minimal env (no /run/current-system/sw/bin
        # on PATH by default). Resolve absolute paths so we don't depend on
        # whatever's currently exported. Pattern mirrors nixos-activate.service
        # in default.nix, which exports PATH=/run/current-system/sw/bin
        # before invoking the activation script.
        export PATH=/run/current-system/sw/bin

        HERMES_BIN='${hermesBin}'
        HERMES_USER=hermes
        HERMES_HOME='${hermesHome}'
        SUDO_BIN=$(command -v sudo)

        if [[ -z "$SUDO_BIN" ]]; then
          echo "hindsight-plugin: sudo not found in /run/current-system/sw/bin" >&2
          exit 1
        fi

        # Idempotency check: if hindsight is already in the plugin list,
        # nothing to do. `hermes plugins list` returns 0 with the plugin
        # table on stdout when the plugin is installed; absent plugins
        # are simply not in the table. We grep for "hindsight" in the
        # first column rather than parsing the table.
        if "$SUDO_BIN" -u "$HERMES_USER" HOME="$HERMES_HOME" \
             "$HERMES_BIN" plugins list 2>/dev/null \
             | grep -qE '(^|\s)hindsight(\s|$)'; then
          echo "hindsight-plugin: already installed, no-op"
          exit 0
        fi

        echo "hindsight-plugin: not installed, running: hermes plugins install hindsight --yes-deps --no-enable"
        # --yes-deps: auto-consent to Python dependency installation (the
        # plugin depends on hindsight-client + hindsight-embed which uv
        # fetches into ~/.local/share/uv/...).
        # --no-enable: install inert. Activation (settings.memory.provider
        # = "hindsight" + hermes-agent restart) happens via default.nix.
        #
        # Failure handling: we MUST NOT fail the nixos-rebuild switch on a
        # transient network error during install. The earlier version did
        # (set -e + raw install) and a single TLS EOF on the GitHub clone
        # poisoned the whole activation, leaving the host on a stale
        # generation. Wrap with retry + always-succeed so the switch commits
        # regardless. We log loudly on failure so it's visible in the
        # activation output.
        install_ok=1
        for attempt in 1 2 3; do
          if "$SUDO_BIN" -u "$HERMES_USER" HOME="$HERMES_HOME" \
               "$HERMES_BIN" plugins install hindsight \
                 --yes-deps \
                 --no-enable; then
            install_ok=0
            break
          fi
          rc=$?
          echo "hindsight-plugin: install attempt $attempt failed (exit $rc), retrying in 10s" >&2
          sleep 10
        done
        if [[ "$install_ok" -ne 0 ]]; then
          echo "hindsight-plugin: WARNING — install failed after 3 attempts (likely network/TLS); activation continues." >&2
          echo "hindsight-plugin: fix by running: sudo -u hermes HOME=/var/lib/hermes hermes plugins install hindsight --yes-deps --no-enable" >&2
        fi
      '';
    };
  };
}