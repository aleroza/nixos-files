# TypeSafe Jev plugin for Hermes Agent — declarative install via the native
# `hermes plugins install` path.
#
# Jev is TypeSafe's "System One" model: it answers typed decision questions
# (yes/no, choice, score) with calibrated probabilities instead of generating
# text. It is NOT a chat model — it cannot write replies or code. Hermes
# exposes it through plugins, not through the core (there is no
# `providers.typesafe` in hermes_cli/models.py).
#
# The Hermes plugin catalog carries several Jev plugins:
#
#   jev-typesafe            (installed as "jev")        typed decision tools
#   jev-approvals           smart-approval reviewer, probabilities only
#   jev-cron-gate           skip pointless cron runs, fail-open
#   hermes-jev-routing      per-turn model routing (needs Hermes >= 0.22.3)
#   typesafe-skill-router   pick one fitting skill per request
#
# We install the three that run on Hermes 0.21.x. hermes-jev-routing is left
# out on purpose: its `requires_hermes` floor is above the version we run.
#
# All three need TYPESAFE_API_KEY. Until that key exists the plugins are
# installed but disabled (see plugins.disabled in default.nix) — the key is
# a runtime secret, not a Nix input, so enablement is a separate step.
#
# The install follows the same shape as hindsight.nix: run as root, drop to
# the hermes user with `runuser` (sudo is unusable — NoNewPrivileges strips
# the setuid bit), check a filesystem marker first, retry transient network
# failures, and never fail the switch.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  hermesHome = "/var/lib/hermes";
  # Why? See AGENTS.md "Activation Scripts" — Antipattern 1:
  hermesBin = "${config.system.path}/bin/hermes";
  # Catalog entry -> directory name under ~/.hermes/plugins/.
  #
  #   jev-typesafe  -> "jev"           (the catalog renames the plugin)
  #   jev-approvals -> "jev-approvals"
  #   jev-cron-gate -> "jev-cron-gate"
  jevPlugins = [
    {
      catalog = "jev-typesafe";
      dir = "jev";
    }
    {
      catalog = "jev-approvals";
      dir = "jev-approvals";
    }
    {
      catalog = "jev-cron-gate";
      dir = "jev-cron-gate";
    }
  ];
in
{
  config = {

    # Activation: install each Jev plugin if missing, no-op otherwise.
    #
    #   /var/lib/hermes/.hermes/plugins/jev/            (real dir, populated by hermes)
    #   /var/lib/hermes/.hermes/plugins/jev-approvals/
    #   /var/lib/hermes/.hermes/plugins/jev-cron-gate/
    #
    # Tolerates /var/lib/hermes being absent: services.hermes-agent's own
    # activation creates the user + home before this script runs (deps
    # = [ "hermes-agent-setup" ]).
    system.activationScripts."jev-plugins" = {
      deps = [ "hermes-agent-setup" ];
      text = ''
        # Why? See AGENTS.md "Activation Scripts" — Antipatterns 2 & 3:
        set -euo pipefail

        main() {
          local HERMES_USER=hermes
          local HERMES_HOME='${hermesHome}'
          local HERMES_BIN='${hermesBin}'

          install_one() {
            local catalog="$1"
            local dir="$2"
            local plugin_dir="$HERMES_HOME/.hermes/plugins/$dir"
            local marker="$plugin_dir/__init__.py"

            # Filesystem marker first: if the plugin's __init__.py is on disk
            # it is installed, regardless of what `hermes plugins list` says
            # (the loader can report stale state after a hermes-agent
            # upgrade). Never treat a loader/marker mismatch as "not
            # installed" — that caused a false negative → reinstall →
            # "already exists" → switch failure in the hindsight plugin.
            if [[ -f "$marker" ]]; then
              echo "jev-plugin[$catalog]: marker present — already installed"
              return 0
            fi

            echo "jev-plugin[$catalog]: not installed, running: hermes plugins install $catalog --yes-deps --no-enable"

            # --yes-deps: auto-consent to Python dependency installation.
            # --no-enable: install inert. Enabling needs TYPESAFE_API_KEY,
            # which is not available at activation time; the operator
            # enables them once the key lands.
            local install_ok=1
            local attempt
            for attempt in 1 2 3; do
              if runuser -u "$HERMES_USER" -- env HOME="$HERMES_HOME" \
                   "$HERMES_BIN" plugins install "$catalog" --yes-deps --no-enable; then
                install_ok=0
                break
              fi
              rc=$?
              echo "jev-plugin[$catalog]: install attempt $attempt failed (exit $rc), retrying in 10s" >&2
              sleep 10
            done

            if [[ "$install_ok" -ne 0 ]]; then
              echo "jev-plugin[$catalog]: WARNING — install failed after 3 attempts (likely network/TLS)" >&2
              echo "jev-plugin[$catalog]: activation continues; rerun manually with:" >&2
              echo "jev-plugin[$catalog]:   runuser -u hermes -- env HOME=/var/lib/hermes /run/current-system/sw/bin/hermes plugins install $catalog --yes-deps --no-enable" >&2
              # Return 0 (not exit 0) so the surrounding activation script
              # continues — the final `ln -sfn ... /run/current-system` line
              # must run, or the next boot fails to chase
              # /run/current-system/systemd/lib/systemd/systemd.
              return 0
            fi
          }

          ${lib.concatMapStrings (p: ''
            install_one "${p.catalog}" "${p.dir}"
          '') jevPlugins}
        }

        main "$@"
      '';
    };
  };
}
