# nixos-files · my-config

**Персональная конфигурация NixOS для aleroza-pc.**

Форк от [nixos-files template](https://github.com/aleroza/nixos-files) с реальной конфигурацией Алексея.

## Сборка/переключение

```bash
sudo nixos-rebuild switch --flake .#aleroza-pc
```

Либо через алиас:
```bash
nix-rebuild
```

## Хосты

- **aleroza-pc** — основной ПК (AMD Ryzen, NVIDIA, btrfs + LUKS)
- **somehost** — шаблон для новых хостов (чистый, без секретов)

## Модульная система

Все фичи — через единый неймспейс `auto`. Каждый модуль — отдельный файл с собственным флагом включения. Никакой ручной возни с `imports`.

```nix
auto = {
  # ── DE инфраструктура ──────────────────────────────────
  xserver.enable            = true;
  gnome.enable              = true;
  displayManager.autoLogin.enable = true;
  # kde.enable               = true;  # можно несколько сразу
  # hyprland.enable          = true;  # WIP

  # ── Подсистемы ─────────────────────────────────────────
  sound.enable              = true;   # PipeWire
  power.enable              = true;   # logind / lid switch
  input.enable              = true;   # libinput (тачпад)
  programs.enable           = true;   # Firefox и пр.

  # ── Остальное ──────────────────────────────────────────
  development = true;
  gaming      = true;
  server      = false;
  bluetooth   = true;
  flatpak     = true;
  ssh         = true;
  fail2ban    = true;

  docker = {
    enable = true;
    users  = [ "aleroza" "openclaw" ];
  };

  hmUsers = [ "aleroza" "openclaw" ];
};
```

## Структура модулей

```
modules/
├── auto.nix              # опции (все флаги auto.*)
├── default.nix           # импорт всех модулей
├── base.nix              # базовая система
├── xserver.nix           # X11 + раскладка
├── gnome.nix             # GNOME + GDM
├── kde.nix               # KDE Plasma + SDDM
├── hyprland.nix          # Hyprland (заготовка)
├── display-manager.nix   # auto-login
├── sound.nix             # PipeWire
├── power.nix             # logind (управление питанием)
├── input.nix             # libinput (тачпад)
├── programs.nix          # Firefox и общие программы
├── development.nix       # dev tools
├── gaming.nix            # Steam / Lutris / MangoHud
├── docker.nix            # Docker daemon
├── hardware.nix          # bluetooth, CUPS и пр.
├── security.nix          # fail2ban, ssh
└── flatpak.nix           # Flatpak / flathub
```

## Secrets

Пароли и чувствительные данные — во внешней директории `/etc/nixos/secrets/`, в репозиторий не попадают.
