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

Home-manager modules live in `users/modules/`. These are **declarative option + configuration modules** — not "config snippets imported as-is". They declare `options.<namespace>.*` and lay down files / packages only when the user has explicitly requested the corresponding options in their `users/<name>.nix`.

Two activation styles:

1. **Per-user import, gated by per-user options.** Each user in `users/<name>.nix` imports the module themselves and sets the relevant options (`hosts`, `volume`, `enable`, ...). The module disables itself via `lib.mkIf` if `enable = false` or if the current host isn't in the allowlist. This style fits **opt-in features** specific to a user (audio amplifier, custom toolchain, dotfiles).
2. **`auto.*`-gated.** The module activates based on `auto.<feature>` (host flag). This is for **host-mandatory features** needed by all users at once (e.g. `npm-global.nix` enables via `auto.dev.nodejs`).

**Don't mix both styles within one module:** either it's `auto.*`-gated (reads `auto` from `extraSpecialArgs`), or per-user-options-gated (reads `config.<namespace>.*`). If you need both — split into two modules.

### Per-user module design

Example: `users/modules/wireplumber-amplify.nix`.

```nix
{ config, lib, pkgs, hostName, ... }:

# ▸ Header doc-comment: what the module does, why, usage syntax.
#   Documentation lives with the module, not the user's file —
#   it survives rename/refactor and is available to anyone reading
#   the module itself.

{
  options.<namespace>.<feature> = {
    enable  = lib.mkEnableOption "..." // { default = true; };
    hosts   = lib.mkOption { type = lib.types.listOf lib.types.str;
                             default = []; example = [ "aleroza-pc" ];
                             description = "..."; };
    volume  = lib.mkOption { type = lib.types.float; default = 1.5;
                             description = "..."; };
  };

  config = lib.mkIf (
    config.<namespace>.<feature>.enable
    && (config.<namespace>.<feature>.hosts == []
        || builtins.elem hostName config.<namespace>.<feature>.hosts)
  ) {
    xdg.configFile."...".source = pkgs.writeText "..." ''
      -- lua / template, interpolation via ${...}
    '';
  };
}
```

What matters:

- **The option namespace must match what the user writes in their file.** `options.wireplumber.amplify.*` → `wireplumber.amplify = { ... };` in `users/<name>.nix`. This is the module's contract.
- **`extraSpecialArgs.hostName` is forwarded via `users/default.nix`.** If a module needs data from the NixOS host config (hostName, username, ...), it must be explicitly passed through `extraSpecialArgs`. Don't try to read `config.networking.hostName` from home-manager — that section isn't defined in HM modules.
- **`enable` defaulting to `true` + `hosts = []` as "all hosts"** is the most idiomatic gate for per-user modules. It means "the module works if the user imported it, and doesn't work on hosts not listed in `hosts`".
- **Documentation lives in the module header**, not the user's file. The user's file contains only a compact option declaration (3–6 lines).
- **Files a module lays down via `xdg.configFile` / `home.file` must not exist manually in the user's `~/.config`** — otherwise HM either refuses (without `force = true`) or overwrites.

### Adding a per-user module

1. `users/modules/<name>.nix` — declare options + gated config.
2. `users/<user>.nix` — `imports = [ ./modules/<name>.nix ];` +
   `<namespace>.<feature> = { ... };` (or your namespace).

### Adding an `auto.*`-gated user module

1. `users/modules/<name>.nix` — wrap body in `lib.mkIf auto.<feature>`.
2. `modules/auto.nix` — declare `options.auto.<feature> = mkOption ...`.
3. `hosts/<name>/default.nix` — set `auto.<feature> = true`.
4. `users/<user>.nix` — `imports = [ ./modules/<name>.nix ];`.

See the full reference in `users/modules/README.md`.

## Activation Scripts

`system.activationScripts.<name>` are **code blocks** in one large bash script `$systemConfig/activate`, not functions. Snippets run in chroot `/sysroot` **before** the final `ln -sfn "$(readlink -f "$systemConfig")" /run/current-system`. If a snippet breaks activate earlier, the next boot fails with `Switch root target contains no usable init`.

### Antipatterns (all three break boot silently)

1. **Calling a binary via `/run/current-system/sw/bin/<tool>`.** The symlink doesn't exist yet — it's created by the final activate line, after all snippets. `execve` fails with `ENOENT`, activate aborts. **Fix:** `''${config.system.path}/bin/<tool>`.
2. **`exit 0` (any `exit`) at snippet top level.** Terminates the whole activate before the final `ln -sfn /run/current-system`. **Fix:** wrap the body in `main() { ... }; main "$@"` and use `return 0`.
3. **`set -euo pipefail` at top level.** Any failure (even a false-y `[[ ... ]]`) drops activate. **Fix:** `set -euo pipefail` may live at the top of the snippet — the snippet is the only thing being executed in that subshell, so its strict mode is scoped to the snippet, not the whole activate script. The function-wrapper form (`main() { ... }`) is the **structural** guarantee that `return 0` is the only way to leave the script early and that the snippet body is not inlined as a top-level statement when the file is sourced; the strict-mode line itself is harmless at the snippet's top level.

### Correct template

```nix
system.activationScripts."my-plugin" = {
  text = ''
    # WHY THIS IS WRAPPED: see AGENTS.md "Activation Scripts" — antipatterns 1-3.
    set -euo pipefail

    main() {
      # Use Nix-store path, not /run/current-system.
      local tool="''${config.system.path}/bin/my-tool"

      if [[ -f "$marker" ]]; then
        echo "my-plugin: already installed, no-op"
        return 0
      fi

      "$tool" install || {
        echo "my-plugin: install failed, continuing" >&2
        return 0
      }
    }

    main "$@"
  '';
};
```

Canonical examples: `hosts/aleroza-pc/hermes/hindsight.nix` (fixes antipattern 1), `hosts/aleroza-pc/hermes/aphrodite.nix` and `openviking.nix` (fix antipattern 3).

## Architecture

- `flake.nix` — single source of truth for nixpkgs/home-manager inputs; two hosts via `mkHost`
- `modules/` — shared NixOS modules; `auto.nix` declares all feature toggles
- `hosts/<name>/` — per-host configs; import hardware-config and set `auto.*` flags
- `users/default.nix` — home-manager user configuration; `extraSpecialArgs` forwards `auto`, `hostName`, `nix-flatpak`, `nixpkgs-unstable`
- `users/modules/` — per-user and `auto.*`-gated home-manager modules
