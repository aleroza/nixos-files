# AGENTS.md

## Build & Validate

**Primary path: the systemd trigger.** `nixos-activate-trigger.path` watches
`/var/lib/hermes/workspace/.switch-request` and runs `switch-to-configuration`
against the closure already built into `/nix/store`. This is how every regular
edit lands — Hermes builds (unprivileged), writes the closure path to
`.pending-switch`, then touches `.switch-request`. Root picks it up and
activates.

The trigger works because **the build has already happened**, so
`NIXOS_GIT_*` env vars (set by the wrapper, see below) have already been
baked into the closure at evaluation time. The trigger service itself
just activates — no rebuild, no rebuild-time metadata injection needed.

**Manual path: `scripts/nixos-rebuild-meta`.** Use only when:

- the change touches `hermes.nix` / `nixos-activate.service` / `nixos-activate-trigger.path` itself — the trigger can't restart a service it depends on,
- the user explicitly asks for a manual switch,
- dry-run / dry-activate for fast validation without affecting the running system.

```bash
# Manual switch (uncommon — only for self-referential changes)
./scripts/nixos-rebuild-meta switch --flake .#<hostname>

# Validate without building or activating
./scripts/nixos-rebuild-meta dry-activate --flake .#<hostname>

# Static syntax + type checks
nix flake check
```

**Never run raw `sudo nixos-rebuild`**, `nixos-rebuild switch`, or
`nixos-rebuild dry-activate` — they bypass `NIXOS_GIT_REVISION` /
`BRANCH` / `DIRTY` / `URL` and the metadata lands empty in
`/etc/os-release` and `nixos-version --configuration-revision`.

After a successful switch (trigger or manual), verify metadata landed:

```bash
nixos-version --configuration-revision      # HEAD sha (or "dd36133bad...-dirty")
grep -E '^GIT_' /etc/os-release              # GIT_REVISION / GIT_BRANCH / GIT_DIRTY / GIT_URL
```

## Secrets

Secrets are referenced via `hashedPasswordFile` in `users.users.*` and live **outside the repo** — **never commit them**. The default location used by `aleroza-pc` is `/etc/nixos/secrets/`.

## `auto` Module System

All modules are **always imported** via `modules/default.nix`. Features are enabled/disabled with `lib.mkIf config.auto.<feature>`. See [`preAGENTS.md`](preAGENTS.md) for the full module creation pattern.

To add a feature:
1. `modules/<name>.nix` — wrap body in `lib.mkIf config.auto.<name>`
2. `modules/default.nix` — add `./<name>.nix`
3. `modules/auto.nix` — declare `options.auto.<name> = mkOption { type = types.bool; default = false; }`
4. Host config — set `auto.<name> = true/false`

## User Modules

Home-manager модули живут в `users/modules/`. Они активируются через `auto.*` флаги (передаются через `extraSpecialArgs`).

To add a user module:
1. `users/modules/<name>.nix` — create module, use `lib.mkIf auto.<feature>`
2. `users/<user>.nix` — add `imports = [ ./modules/<name>.nix ]`

## Architecture

- `flake.nix` — single source of truth for nixpkgs/home-manager inputs; two hosts via `mkHost`
- `modules/` — shared NixOS modules; `auto.nix` declares all feature toggles
- `hosts/<name>/` — per-host configs; import hardware-config and set `auto.*` flags
- `users/default.nix` — home-manager user configuration
