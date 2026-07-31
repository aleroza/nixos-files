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

вся hermes-логика вынесена в `hermes.nix` (импортируется из
`default.nix`). Хост-файл остаётся сфокусирован на собственно
настройке хоста.

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
│   ├─ systemd-run --unit=hermes-switch-* --no-block \            │
│   │       $CLOSURE/bin/switch-to-configuration switch           │
│   ├─ exit 0  ← service done, ничего не держит                   │
│   └─ rm -f /var/lib/hermes/workspace/.switch-request            │
│              .pending-switch                                    │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ hermes-switch-<ts>-<pid>.service  (transient, --collect)        │
│   делает реальный switch в своей cgroup, вне lifecycle         │
│   родительского nixos-activate.service                          │
└──────────────────────────────────────────────────────────────────┘
```

Сборка **не** идёт внутри юнита — она медленная и шумная, в oneshot
только то, что быстро и атомарно. `systemd-run` отделяет шаг
"инициировать switch" от шага "выполнить switch": см. следующую
секцию.

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

#### Как service избегает самопроизвольного убийства

`switch-to-configuration switch` на финальной стадии останавливает
**все активные systemd-юниты** — это нужно, чтобы они не держали
старые версии сокетов/бинарников во время перехода. Если бы
`nixos-activate.service` запускал `switch-to-configuration` прямо
внутри своего `ExecStart`, он сам бы оказался в этой волне:

```
nixos-activate-start: Checking switch inhibitors... done
nixos: switching to system configuration /nix/store/...-nixos-system-...
nixos-activate-start: stopping the following units: nixos-activate.service
nixos-activate.service: Main process exited, code=killed, status=15/TERM
```

Активация при этом всё равно прошла бы (system profile переключён,
bootloader entry записан, `current-system` обновлён) — systemd бы
просто записал service как failed. На ремеди это лишний шум и
ложный сигнал тревоги.

Чтобы этого не было, service делегирует switch в **transient
unit** через `systemd-run --no-block --collect`:

```nix
TRANSIENT="hermes-switch-$(date +%s)-$$"
systemd-run \
  --unit="$TRANSIENT" \
  --description="Hermes-triggered switch-to-configuration for $GEN" \
  --no-block \
  --collect \
  --setenv=GEN="$GEN" \
  "$CLOSURE/bin/switch-to-configuration" switch
```

Сценарий:

1. `nixos-activate.service` ставит transient unit в очередь и
   сразу делает `exit 0`. Status=0/SUCCESS. Trigger-файлы
   удалены.
2. transient unit живёт в своей cgroup, не child нашего service.
3. `switch-to-configuration` бежит в transient unit. Когда он
   доходит до стадии "stop all units", наш `nixos-activate.service`
   уже давно inactive, а transient unit сам себя не убивает —
   он не находится в списке "all units, которые были активны до
   активации нового поколения" (этот список формируется по
   состоянию на момент старта switch, а наш transient unit
   поднялся внутри).
4. switch отрабатывает до конца, `current-system` обновлён,
   systemd-boot entry записан.

**Цена:** exit code самого `switch-to-configuration` больше не
доходит до trigger flag (мы уже удалили файлы). Hermes супервизит
исход через journalctl transient unit-а:

```bash
journalctl -u 'hermes-switch-*' --no-pager -n 100
```

Если что-то пошло не так — там будет видно. В happy-path
`current-system` указывает на новый closure и `systemctl status
nixos-activate.service` показывает `status=0/SUCCESS`.

#### Что активируется через trigger

После введения `systemd-run` транзиентного unit-а ограничение
**снято**: теперь через trigger flag можно активировать **любую**
правку в конфиге хоста — включая сам `systemd.services.nixos-activate`,
`systemd.paths.nixos-activate-trigger`, `users.users.hermes.*`,
`services.hermes-agent.*`. Единственное, что реально нужно от
хост-овнера, это:

- **Первая активация после merge PR** с правкой `default.nix`,
  `hermes.nix`, `flake.nix` или другого host-файла, в котором
  `imports = [ ./hermes.nix ]`. Текущая инкарнация service в
  `/etc/systemd/system/nixos-activate.service` ещё не знает про
  новую структуру, пока ты не сделаешь `sudo nixos-rebuild
  switch` один раз. После этого — любая правка активируется
  через trigger.
- **Любая правка `flake.lock`** (новые версии `nixpkgs`,
  `home-manager`, и т.п.) — это не constraint trigger-а, но
  rebuild closure меняется, что иногда требует ручного
  решения при конфликте package versions. На практике это
  редко мешает.

Всё остальное — packages, модули, `environment.*`, `auto.*`,
`users.users.aleroza.*`, `users.users.openclaw.*`, любые
`systemd.services.*`/`systemd.paths.*` — hermes активирует сам,
без sudo.

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

# последний запуск главного service
journalctl -u nixos-activate.service -n 50 --no-pager

# исход switch-to-configuration (transient unit, имя включает ts + pid)
journalctl -u 'hermes-switch-*' -n 100 --no-pager

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
- Не отключает NNP на `hermes-agent.service`.
