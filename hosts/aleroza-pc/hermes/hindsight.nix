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
  # Why? See AGENTS.md "Activation Scripts" — Antipattern 1:
  hermesBin = "${config.system.path}/bin/hermes";
  # Why? Antipattern 1 again — uv is in /run/current-system/sw/bin/uv, not
  # anywhere we can rely on at activation time as a bare name.
  uvBin = "${config.system.path}/bin/uv";
  # Where to drop the hindsight-client / hindsight-embed wheels so the
  # plugin's `import hindsight_embed.daemon_embed_manager` resolves at
  # runtime. /nix/store/<hash>-hermes-agent-*/lib/python3.14/site-packages
  # is read-only; /var/lib/hermes is RW. Plugin code (embedded.py) reads
  # PYTHONPATH-extra via the manager's child-env handling.
  pythonDeps = "${hermesHome}/.hermes/python-deps";
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
    # Runs as root (activation scripts always do) and uses `runuser` to
    # drop privileges to the hermes user for the install. `sudo` is not
    # viable here — in this container /run/current-system/sw/bin/sudo is
    # a symlink to a /nix/store path whose setuid bit has been stripped
    # by the systemd hardening (NoNewPrivileges on the parent unit),
    # so `sudo -u hermes ...` aborts with "must be owned by uid 0 and
    # have the setuid bit set" before the target command runs. `runuser`
    # (util-linux) does not require setuid; it relies on the caller
    # already being root and PAM-allowed, which activation scripts are.
    system.activationScripts."hindsight-plugin" = {
      deps = [ "hermes-agent-setup" ];
      text = ''
        # Why? See AGENTS.md "Activation Scripts" — Antipatterns 2 & 3:
        set -euo pipefail

        main() {
          HERMES_BIN='${hermesBin}'
          HERMES_USER=hermes
          HERMES_HOME='${hermesHome}'
          PLUGIN_DIR="$HERMES_HOME/.hermes/plugins/hindsight"
          MARKER="$PLUGIN_DIR/__init__.py"

          # ────────────────────────────────────────────────────────
          # Idempotency check.
          #
          # Two signals, in order of trust:
          #
          #   1. filesystem marker — if the plugin's __init__.py is on
          #      disk under the hermes user's plugin dir, it's installed
          #      regardless of what `hermes plugins list` reports (which
          #      can lie if invoked under a degraded hermes-agent state).
          #      root can read the file directly; no runuser needed.
          #
          #   2. `hermes plugins list hindsight` via runuser — defensive
          #      cross-check. If the marker exists but the loader doesn't
          #      know about the plugin (e.g. fresh hermes-agent upgrade
          #      lost the catalog cache), log a warning so we know to
          #      re-run `hermes plugins adopt` or similar manually. We
          #      do NOT treat that mismatch as "not installed" — that
          #      was the bug in the previous version (false negative →
          #      install → "Plugin already exists" → switch failed).
          #
          # If the marker is missing AND the loader confirms absence,
          # we install.
          # ────────────────────────────────────────────────────────
          if [[ -f "$MARKER" ]]; then
            echo "hindsight-plugin: marker present at $MARKER — already installed"
            # Cross-check (best-effort, never fails activation).
            if runuser -u "$HERMES_USER" -- env HOME="$HERMES_HOME" \
                 "$HERMES_BIN" plugins list 2>/dev/null \
                 | grep -qE '(^|\s)hindsight(\s|$)'; then
              echo "hindsight-plugin: hermes plugins list confirms install, no-op"
            else
              echo "hindsight-plugin: WARNING — plugin files present but loader does not see hindsight" >&2
              echo "hindsight-plugin:   possible cause: catalog cache stale, or hermes-agent upgrade" >&2
              echo "hindsight-plugin:   no-op (not overwriting on disk); investigate manually if memory breaks" >&2
            fi
            return 0
          fi

          # Secondary check via the loader — only runs if the marker is
          # missing. If the loader says installed but the marker is gone,
          # something deleted the plugin files out from under us; reinstall
          # to restore. If the loader also says absent, install fresh.
          loader_says_installed=0
          if runuser -u "$HERMES_USER" -- env HOME="$HERMES_HOME" \
               "$HERMES_BIN" plugins list 2>/dev/null \
               | grep -qE '(^|\s)hindsight(\s|$)'; then
            loader_says_installed=1
          fi

          if [[ "$loader_says_installed" -eq 1 ]]; then
            echo "hindsight-plugin: loader reports installed but marker is missing — reinstalling"
          else
            echo "hindsight-plugin: not installed, running: hermes plugins install hindsight --yes-deps --no-enable"
          fi

          # --yes-deps: auto-consent to Python dependency installation (the
          # plugin depends on hindsight-client + hindsight-embed which uv
          # fetches into ~/.local/share/uv/...).
          # --no-enable: install inert. Activation (settings.memory.provider
          # = "hindsight" + hermes-agent restart) happens via default.nix.
          #
          # Failure handling: a transient network error during install
          # (e.g. github.com TLS EOF during git clone) MUST NOT fail the
          # whole nixos-rebuild switch — that leaves the host on a stale
          # generation. Retry up to 3 times with 10s backoff. If install
          # ultimately fails, log a loud WARNING and return 0 anyway so
          # the switch commits; the operator can rerun manually.
          install_ok=1
          install_args=(--yes-deps --no-enable)
          if [[ "$loader_says_installed" -eq 1 ]]; then
            install_args=(--force --yes-deps --no-enable)
          fi
          for attempt in 1 2 3; do
            if runuser -u "$HERMES_USER" -- env HOME="$HERMES_HOME" \
                 "$HERMES_BIN" plugins install hindsight "''${install_args[@]}"; then
              install_ok=0
              break
            fi
            rc=$?
            echo "hindsight-plugin: install attempt $attempt failed (exit $rc), retrying in 10s" >&2
            sleep 10
          done
          if [[ "$install_ok" -ne 0 ]]; then
            echo "hindsight-plugin: WARNING — install failed after 3 attempts (likely network/TLS)" >&2
            echo "hindsight-plugin: activation continues; rerun manually with:" >&2
            echo "hindsight-plugin:   runuser -u hermes -- env HOME=/var/lib/hermes /run/current-system/sw/bin/hermes plugins install hindsight --yes-deps --no-enable" >&2
            # Return 0 (not exit 0) so the surrounding activation script
            # continues — the final `ln -sfn ... /run/current-system` line
            # must run, or the next boot fails to chase
            # /run/current-system/systemd/lib/systemd/systemd.
            return 0
          fi
        }

        main "$@"
      '';
    };

    # Activation: pin hindsight-client / hindsight-embed into
    # ~/.hermes/python-deps/ (RW) so the plugin's embedded daemon
    # manager can import them. Hermes's own `hermes memory setup` is
    # supposed to do this via `pm.sync_venv`, but on NixOS that path
    # walks into /nix/store/<hash>-hermes-agent-*/lib/python3.14/site-packages
    # looking for uv.lock and aborts with FileNotFoundError — uv.lock
    # is a git-tree artifact, not a Nix-store one. We sidestep by
    # running `uv pip install --target` directly into a hermes-owned
    # RW directory, then making the plugin's hermes-agent service see
    # it via PYTHONPATH (added in default.nix alongside the plugin
    # enablement).
    #
    # Idempotency: presence of hindsight_embed/__init__.py under the
    # target dir is the marker. If present, skip.
    #
    # Failure handling: same as the install snippet — transient network
    # errors must not fail the switch. Warn and continue.
    system.activationScripts."hindsight-pip-deps" = {
      deps = [ "hindsight-plugin" ];
      text = ''
        # Why? See AGENTS.md "Activation Scripts" — Antipatterns 2 & 3.
        set -euo pipefail

        main() {
          local HERMES_USER=hermes
          local HERMES_HOME='${hermesHome}'
          local UV_BIN='${uvBin}'
          local DEPS_DIR='${pythonDeps}'
          local MARKER="$DEPS_DIR/hindsight_embed/__init__.py"

          mkdir -p "$DEPS_DIR"
          chown "$HERMES_USER:$HERMES_USER" "$DEPS_DIR"
          chmod 0750 "$DEPS_DIR"

          if [[ -f "$MARKER" ]]; then
            echo "hindsight-pip-deps: marker present at $MARKER — already installed"
            return 0
          fi

          echo "hindsight-pip-deps: installing hindsight-client + hindsight-embed into $DEPS_DIR"
          if ! runuser -u "$HERMES_USER" -- env HOME="$HERMES_HOME" \
               "$UV_BIN" pip install --target "$DEPS_DIR" \
                 hindsight-client hindsight-embed; then
            echo "hindsight-pip-deps: WARNING — uv pip install failed; activation continues" >&2
            echo "hindsight-pip-deps: rerun manually with:" >&2
            echo "hindsight-pip-deps:   runuser -u hermes -- env HOME=/var/lib/hermes ${uvBin} pip install --target ${pythonDeps} hindsight-client hindsight-embed" >&2
            # Return 0 (not exit 0) — see AGENTS.md Antipattern 2.
            return 0
          fi

          # Fix ownership: uv pip install --target creates files as the
          # runuser (hermes) which is what we want, but be explicit so
          # the next activation doesn't trip on a permission mismatch.
          chown -R "$HERMES_USER:$HERMES_USER" "$DEPS_DIR"
          echo "hindsight-pip-deps: ok"
        }

        main "$@"
      '';
    };

    # Activation: lay down ~/.hindsight/profiles/default.env for the
    # embedded daemon. The plugin's daemon_embed_manager reads this
    # file when starting `uvx hindsight-api` and exports its contents
    # into the daemon child's environment — this is how the daemon
    # learns its LLM provider credentials. Without it, the daemon
    # boots with no LLM API key and every embed/retain call fails.
    #
    # Idempotent: only writes if the file is missing. Operator can
    # edit the file by hand later (e.g. to switch LLM provider); this
    # snippet will not overwrite a non-empty file.
    #
    # Source of the API key: /run/secrets/hermes/env (sops secret, same
    # one that feeds MINIMAX_API_KEY into hermes-agent). We re-use
    # MINIMAX_API_KEY as HINDSIGHT_LLM_API_KEY — Hindsight's LLM client
    # is OpenAI-compatible and the same bearer works against
    # api.minimax.io. To switch providers, edit the file by hand; the
    # activation script will leave existing content alone.
    system.activationScripts."hindsight-profile-env" = {
      deps = [ "hindsight-pip-deps" ];
      text = ''
        # Why? See AGENTS.md "Activation Scripts" — Antipatterns 2 & 3.
        set -euo pipefail

        main() {
          local HERMES_USER=hermes
          local HERMES_HOME='${hermesHome}'
          local PROFILE_DIR="$HERMES_HOME/.hindsight/profiles"
          local PROFILE_FILE="$PROFILE_DIR/default.env"
          local SECRETS=/run/secrets/hermes/env

          mkdir -p "$PROFILE_DIR"
          chown -R "$HERMES_USER:$HERMES_USER" "$HERMES_HOME/.hindsight"
          chmod 0750 "$PROFILE_DIR"

          if [[ -s "$PROFILE_FILE" ]]; then
            echo "hindsight-profile-env: $PROFILE_FILE already populated, not overwriting"
            return 0
          fi

          if [[ ! -f "$SECRETS" ]]; then
            echo "hindsight-profile-env: WARNING — $SECRETS not found; cannot seed LLM key" >&2
            echo "hindsight-profile-env: write $PROFILE_FILE by hand with HINDSIGHT_LLM_API_KEY=..." >&2
            return 0
          fi

          local KEY
          KEY=$(grep '^MINIMAX_API_KEY=' "$SECRETS" | head -1 | cut -d= -f2- || true)
          if [[ -z "$KEY" ]]; then
            echo "hindsight-profile-env: WARNING — MINIMAX_API_KEY empty in $SECRETS" >&2
            return 0
          fi

          cat > "$PROFILE_FILE" <<PROFILE_EOF
        # Generated by hosts/aleroza-pc/hermes/hindsight.nix — do not edit
        # unless you want to switch LLM providers. Re-running nixos-rebuild
        # does not overwrite this file (it only seeds a missing/empty one).
        # Sourced by the embedded daemon manager into uvx hindsight-api.
        HINDSIGHT_LLM_API_KEY=$KEY
        HINDSIGHT_LLM_BASE_URL=https://api.minimax.io/v1
        HINDSIGHT_LLM_MODEL=MiniMax-M3
        HINDSIGHT_EMBED_BASE_URL=https://api.minimax.io/v1
        HINDSIGHT_EMBED_MODEL=text-embedding-3-small
        PROFILE_EOF
          chown "$HERMES_USER:$HERMES_USER" "$PROFILE_FILE"
          chmod 0640 "$PROFILE_FILE"
          echo "hindsight-profile-env: seeded $PROFILE_FILE from MINIMAX_API_KEY"
        }

        main "$@"
      '';
    };
  };
}