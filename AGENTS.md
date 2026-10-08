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

Home-manager модули живут в `users/modules/`. Это **декларативные модули
опций и конфигурации** — не «куски конфига, которые импортируются
as-is». Они объявляют `options.<namespace>.*` и подкладывают файлы /
пакеты только когда пользователь явно запросил соответствующие опции
в своём `users/<name>.nix`.

Два стиля активации:

1. **Per-user import, gated by per-user options.** Каждый пользователь
   в `users/<name>.nix` сам импортирует модуль и задаёт нужные опции
   (`hosts`, `volume`, `enable`, ...). Модуль сам себя гасит через
   `lib.mkIf`, если опция `enable = false` или текущий хост не входит
   в белый список. Этот стиль подходит для **opt-in фич**, специфичных
   для пользователя (усилитель звука, кастомный тулчейн, dotfiles).
2. **`auto.*`-gated.** Модуль активируется по `auto.<feature>` (флаг
   хоста). Это для **обязательных для хоста фич**, которые нужны
   всем пользователям одновременно (например, `npm-global.nix`
   включается через `auto.dev.nodejs`).

В пределах одного модуля **не смешивайте оба стиля**: либо он
`auto.*`-gated (читает `auto` из `extraSpecialArgs`), либо
per-user-options-gated (читает `config.<namespace>.*`). Если нужны
оба — разнесите на два модуля.

### Per-user module design

Пример: `users/modules/wireplumber-amplify.nix`.

```nix
{ config, lib, pkgs, hostName, ... }:

# ▸ Doc-комментарий шапки: что делает, зачем, синтаксис использования.
#   Документация принадлежит модулю, а не пользовательскому файлу —
#   так она переживает rename / refactor и доступна тем, кто читает
#   сам модуль.

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
      -- lua / template, интерполяция через ${...}
    '';
  };
}
```

Что важно:

- **Пространство имён опций должно совпадать с тем, что пользователь
  пишет в своём файле.** `options.wireplumber.amplify.*` →
  `wireplumber.amplify = { ... }` в `users/<name>.nix`. Это контракт
  модуля.
- **`extraSpecialArgs.hostName`** пробрасывается в `users/default.nix`.
  Если модулю нужны данные из NixOS-конфига хоста (hostName, имя
  пользователя, ...), их надо явно передать через `extraSpecialArgs`.
  Не пытайтесь читать `config.networking.hostName` из home-manager —
  эта секция в HM-модуле не определена.
- **`enable` с дефолтом `true` + `hosts = []` как «все хосты»** —
  самый идиоматичный гейт для per-user модулей. Это значит «модуль
  работает, если пользователь его импортировал, и не работает на
  хостах, которых нет в `hosts`».
- **Документация — в шапке модуля**, не в пользовательском файле.
  Пользовательский файл содержит только компактную декларацию
  опций (3–6 строк).
- **Файлы, которые модуль кладёт через `xdg.configFile` / `home.file`,
  не должны существовать у пользователя в `~/.config` вручную** —
  иначе HM либо откажется (без `force = true`), либо перезапишет.

### Adding a per-user module

1. `users/modules/<name>.nix` — declare options + gated config.
2. `users/<user>.nix` — `imports = [ ./modules/<name>.nix ];` +
   `wireplumber.amplify = { ... };` (или ваше пространство имён).

### Adding an `auto.*`-gated user module

1. `users/modules/<name>.nix` — wrap body in `lib.mkIf auto.<feature>`.
2. `modules/auto.nix` — declare `options.auto.<feature> = mkOption ...`.
3. `hosts/<name>/default.nix` — set `auto.<feature> = true`.
4. `users/<user>.nix` — `imports = [ ./modules/<name>.nix ];`.

Подробный референс см. в `users/modules/README.md`.

## Architecture

- `flake.nix` — single source of truth for nixpkgs/home-manager inputs; two hosts via `mkHost`
- `modules/` — shared NixOS modules; `auto.nix` declares all feature toggles
- `hosts/<name>/` — per-host configs; import hardware-config and set `auto.*` flags
- `users/default.nix` — home-manager user configuration; `extraSpecialArgs` пробрасывает `auto`, `hostName`, `nix-flatpak`, `nixpkgs-unstable`
- `users/modules/` — per-user и `auto.*`-gated home-manager модули
