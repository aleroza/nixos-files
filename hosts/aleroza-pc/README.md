# aleroza-pc

Основной хост — AMD Ryzen, NVIDIA, btrfs + LUKS. См. общий
[`README.md`](../../README.md) для устройства модульной системы и
флагов `auto.*`.

## Hermes-интеграция

`aleroza-pc` запускает [Hermes Agent](https://github.com/NousResearch/hermes-agent)
как системный сервис (`services.hermes-agent`). Hermes живёт в контейнере
от пользователя `hermes` (uid 988) с включённым `NoNewPrivileges=yes`
на `hermes-agent.service` — то есть стандартный `sudo`/`pkexec` для
него заблокированы.

Чтобы Hermes мог:

1. **собирать** системные derivations через `nix-daemon` (запись в `/nix/store`),
2. **активировать** новые поколения NixOS,

в `default.nix` сделано две согласованные правки.

### 1. `nixbld` для hermes

```nix
users.users.hermes.extraGroups = [ "nixbld" ];
```

Мерджится с декларацией пользователя из `hermes-agent.nixosModules`.
`nixbld` — стандартная NixOS-группа, которая даёт право создавать
директории в `/nix/store`. Никакого root'а и никакого shell — только
право на запись в store от имени демона.

После этого от hermes работают:

```bash
nix build .#nixosConfigurations.aleroza-pc.config.system.build.toplevel
nixos-rebuild build --flake .#aleroza-pc --profile /var/lib/hermes/.nix-profile/system
nix flake check
nix flake update --commit
```

### 2. `nixos-activate` — root-юнит для активации

```nix
systemd.services.nixos-activate
systemd.paths.nixos-activate-trigger
```

Это **единственное место**, где пересекается граница привилегий.
Юнит работает от root, NNP на нём отключён (всё равно уже root),
но триггерится только явным flag-файлом — `/var/lib/hermes/workspace/.switch-request`.

#### Workflow

```
┌──────────────────────────────────────────────────────────────────┐
│ hermes (unprivileged, NNP=yes, no sudo)                         │
│                                                                 │
│   1. пишет/правит файлы в /var/lib/hermes/workspace/nixos-files  │
│   2. git commit / git push (PAT в /var/lib/hermes/.hermes/.env)  │
│   3. nix flake check --no-build                                 │
│   4. touch /var/lib/hermes/workspace/.switch-request            │
└──────────────────────────────────────────────────────────────────┘
                              │ flag-файл
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ systemd.paths.nixos-activate-trigger                            │
│   заметил файл → запускает systemd.services.nixos-activate       │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ systemd.services.nixos-activate (User=root, NNP=false)          │
│                                                                 │
│   ├─ [ ! -d $FLAKE_DIR ] → exit 1                               │
│   ├─ cd /var/lib/hermes/workspace/nixos-files                   │
│   ├─ git diff --quiet HEAD -- . → exit 2 (если dirty)           │
│   ├─ flock /var/run/nixos-activate.lock                         │
│   ├─ GEN="hermes-$(date +%Y%m%d-%H%M%S)"                       │
│   ├─ nixos-rebuild switch \                                     │
│   │     --flake .#aleroza-pc \                                  │
│   │     --install-bootloader \                                  │
│   │     --profile-name "$GEN"                                   │
│   └─ rm -f /var/lib/hermes/workspace/.switch-request            │
└──────────────────────────────────────────────────────────────────┘
```

#### Защитные свойства

- **Dirty tree refuse.** Неактивируется из незакоммиченного состояния —
  активная конфигурация всегда совпадает с историей в git.
- **Lock.** Одновременно может идти только один switch. Параллельный
  триггер получает `exit 3` без запуска rebuild.
- **Уникальный `--profile-name`.** Каждое поколение помечено
  `hermes-YYYYmmdd-HHMMSS` — легко опознать и откатить через boot
  loader (`nixos-rebuild switch --rollback` или выбор поколения в
  systemd-boot меню).
- **Allowlisted source.** Юнит жёстко смотрит только на
  `/var/lib/hermes/workspace/nixos-files#aleroza-pc`. Никакой
  произвольный путь от имени hermes не пройдёт.
- **NNP на hermes-agent.service не трогается.** Граница привилегий
  пересекается только в одном root-юните, только по явному триггеру,
  и только против разрешённого пути.

#### Отладка

```bash
# состояние юнитов
systemctl status nixos-activate.service
systemctl status nixos-activate-trigger.path

# последний запуск
journalctl -u nixos-activate.service -n 50 --no-pager

# ручной тест (от root, в обход flag-файла)
sudo systemctl start nixos-activate.service
```

#### Что НЕ делает этот механизм

- Не даёт hermes shell или sudo на хосте.
- Не позволяет hermes собирать от имени других пользователей.
- Не даёт произвольного исполнения — только `nixos-rebuild switch`
  из конкретного флейка.
- Не отключает NNP на `hermes-agent.service`.