# AGENTS.md

## Build & Validate

```bash
# From any directory with flake.nix:
sudo nixos-rebuild switch --flake .#<hostname>

# Validate without building
nixos-rebuild dry-run --flake .#<hostname>

# Validate flake
nix flake check
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
