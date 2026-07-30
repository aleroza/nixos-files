# aleroza-pc

Основной хост — AMD Ryzen, NVIDIA, btrfs + LUKS. См. общий
[`README.md`](../../README.md) для устройства модульной системы и
флагов `auto.*`.

## Hermes-интеграция

`aleroza-pc` запускает [Hermes Agent](https://github.com/NousResearch/hermes-agent)
как системный сервис (`services.hermes-agent`). Hermes живёт от
пользователя `hermes` (uid 988) с включённым `NoNewPrivileges=yes` на
`hermes-agent.service` — стандартные `sudo`/`pkexec` для него
заблокированы. Чтобы Hermes мог:

1. **собирать** системные derivations через `nix-daemon` (запись в
   `/nix/store`),
2. **активировать** новые поколения NixOS,

в `default.nix` сделаны согласованные правки.

### 1. Сборка без `nixbld`

Hermes собирает системные derivations **от имени своего пользователя**,
без группы `nixbld`. `nixbld` сознательно **не** выдаётся — он даёт
слишком много (произвольная запись в `/nix/store`, что эквивалентно
произвольному исполнению кода под build users).

Вместо этого hermes пишет в `/nix/store` через **обычный unprivileged
nix** (multi-user mode): `nix-daemon` слушает на сокете, проверяет
peer credentials через SO_PEERCRED, и для каждого build запускает
worker от отдельного uid из `/etc/.../nixbld-*`. Сам hermes при этом
остаётся обычным пользователем — пишет только в уже созданные
`nixbld-N` derivation-output пути, которые система сама разрешает ему
через ACL/`/nix/store/.trusted`/прочее.

Рабочие команды от hermes:

```bash
# собрать системный closure (без активации)
nix build .#nixosConfigurations.aleroza-pc.config.system.build.toplevel

# проверить flake без сборки
nix flake check --no-build

# обновить input'ы и закоммитить flake.lock
nix flake update --commit
```

Все они работают **без sudo** и **без `nixbld`-группы**.

### 2. `nixos-activate` — root-юнит для активации

```nix
systemd.services.nixos-activate
systemd.paths.nixos-activate-trigger
```

Единственное место, где пересекается граница привилегий. Юнит
работает от root, `NoNewPrivileges` на нём отключён (всё равно уже
root), триггерится только явным flag-файлом —
`/var/lib/hermes/workspace/.switch-request`. **Юнит не собирает** —
только активирует уже готовый closure.

#### Workflow

```
┌──────────────────────────────────────────────────────────────────┐
│ hermes (unprivileged, NNP=yes, no sudo, no nixbld)              │
│                                                                 │
│   1. правит файлы в /var/lib/hermes/workspace/nixos-files       │
│   2. git commit / git push (PAT в /var/lib/hermes/.hermes/.env) │
│   3. nix build ...toplevel  →  /nix/store/...-nixos-system-...  │
│   4. echo $closure > /var/lib/hermes/workspace/.pending-switch  │
│   5. touch /var/lib/hermes/workspace/.switch-request            │
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
│   ├─ flock /run/nixos-activate/lock                            │
│   ├─ читает .pending-switch → CLOSURE=/nix/store/...            │
│   ├─ [CLOSURE валидный /nix/store/-nixos-system-aleroza-pc-*]   │
│   ├─ [ -x $CLOSURE/bin/switch-to-configuration ]                │
│   ├─ $CLOSURE/bin/switch-to-configuration switch                │
│   └─ rm -f /var/lib/hermes/workspace/.switch-request            │
│              .pending-switch                                    │
└──────────────────────────────────────────────────────────────────┘
```

Сборка **не** идёт внутри юнита — она медленная и шумная, в oneshot
только то, что быстро и атомарно.

#### Защитные свойства

- **Без `nixbld`.** У hermes нет прав на произвольную запись в
  `/nix/store` от своего имени; сборка идёт через `nix-daemon` под
  build-юзерами.
- **Trigger flag, не автозапуск.** Юнит стартует только при наличии
  `/var/lib/hermes/workspace/.switch-request`. Случайный рестарт
  системы не запускает switch.
- **Allowlisted closure path.** Скрипт отвергает closure, если он не
  начинается с `/nix/store/*-nixos-system-aleroza-pc-` (exit 8) или не
  содержит `bin/switch-to-configuration` (exit 9). Произвольный
  path в `.pending-switch` не пройдёт.
- **Lock.** Одновременно может идти только один switch. Параллельный
  триггер получает `exit 3` без запуска rebuild.
- **Self-cleanup.** После успешного switch скрипт удаляет оба
  flag-файла; на повторный trigger нужно класть заново.
- **NNP на `hermes-agent.service` не трогается.** Граница привилегий
  пересекается только в одном root-юните, только по явному триггеру,
  и только против уже валидного closure.

#### Что может пойти не так: самопроизвольное убийство service

`nixos-rebuild switch` (точнее, его финальная стадия
`switch-to-configuration switch`) **останавливает все активные
systemd-юниты** при активации нового поколения. Это включает наш
собственный `nixos-activate.service`, если он ещё работает.

В логе это выглядит так:

```
nixos-activate-start: Checking switch inhibitors... done
nixos: switching to system configuration /nix/store/...-nixos-system-...
nixos-activate-start: stopping the following units: nixos-activate.service
nixos-activate.service: Main process exited, code=killed, status=15/TERM
```

Статус `15/TERM` — это не баг нашего скрипта, это поведение самого
`nixpkgs/nixos/modules/system/activation/switch-to-configuration.nix`.
На реальный результат не влияет: `system` profile уже переключён,
bootloader запись создана, `current-system` обновился. Просто systemd
считает, что service упал.

Из этого следует **важное ограничение**:

> Любой rebuild, который меняет сам `systemd.services.nixos-activate`,
> `systemd.paths.nixos-activate-trigger`, `users.users.hermes.*` или
> `services.hermes-agent.*`, **не может быть активирован через тот же
> триггер-юнит** — он убьёт себя до того, как дочитает новые unit-файлы
> из closure.

Для таких изменений нужен ручной `sudo nixos-rebuild switch --flake
.#[hostname]` от тебя. Hermes это понимает: после ребилда, который
трогает эти unit-файлы, скрипт не будет класть новый closure в
`.pending-switch` — изменения остаются только в git и в `/nix/store`.

Изменения, которые **можно** активировать через trigger:

- любые `modules/*` правки, не затрагивающие `systemd.services.*`
- `hosts/aleroza-pc` правки в разделах `auto.*`, `environment.*`,
  `users.users.aleroza.*`, `users.users.openclaw.*`, packages, и т.п.

Изменения, которые нужно активировать вручную:

- `systemd.services.nixos-activate`, `systemd.paths.nixos-activate-trigger`
- `services.hermes-agent.*`
- `users.users.hermes.*`
- любые `systemd.services.*` или `systemd.paths.*`

#### Rate limits

На **path-юните** (`nixos-activate-trigger.path`) выключен лимит
на триггеры:

```nix
unitConfig.TriggerLimitIntervalSec = 0;
```

Это нужно потому, что при итерации на сломанном конфиге path-unit
триггерит service, тот падает, path триггерит снова — и через 5
провалов за 10 секунд systemd кладёт path-юнит в
`unit-start-limit-hit`. Сбросить можно только
`sudo systemctl reset-failed ...`, что мешает автономной работе.

На самом **service** (`nixos-activate.service`) rate limits не нужны:
`Type = "oneshot"` без `Restart=` — systemd per `man systemd.service`
применяет `StartLimitIntervalSec`/`StartLimitBurst` **только** к
юнитам с `Restart != "no"`. Для oneshot они no-op, а неизвестный
`StartLimitIntervalSec` в `[Service]` у systemd 260 вызывает
`Unknown key ... in section [Service], ignoring` — то есть ключ не
валиден там, и попытка его поставить создаёт шум в логе без
пользы.

Hermes супервизит активации через journalctl + свежесть
`.pending-switch`, поэтому rate limits на path-юните достаточно.

Предупреждение `Unknown key 'StartLimitIntervalSec' in section
[Service]` от systemd — артефакт попытки положить service-level
rate-limit в `[Service]`. Если встретишь его после этого коммита —
это значит в системе ещё крутится старый closure, который был
собран до отката этой правки. После активации свежего closure
(ручной `sudo nixos-rebuild switch --flake .#aleroza-pc`) сообщение
пропадёт.

#### Отладка

```bash
# состояние юнитов
systemctl status nixos-activate.service
systemctl status nixos-activate-trigger.path

# последний запуск
journalctl -u nixos-activate.service -n 50 --no-pager

# если юниты застряли в start-limit-hit
sudo systemctl reset-failed nixos-activate.service nixos-activate-trigger.path
sudo systemctl start nixos-activate-trigger.path

# ручной запуск активации (от root, в обход flag-файла)
sudo /nix/store/*-nixos-system-*/bin/switch-to-configuration switch
```

#### Что НЕ делает этот механизм

- Не даёт hermes shell или sudo на хосте.
- Не даёт hermes группу `nixbld` или любой другой прямой write-доступ
  в `/nix/store` от своего имени.
- Не активирует изменения, которые трогают сами эти юниты (см.
  «Что может пойти не так»).
- Не отключает NNP на `hermes-agent.service`.
