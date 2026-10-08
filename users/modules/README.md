# User Modules

Декларативные home-manager модули для пользователей. Каждый файл в
этом каталоге объявляет `options.<namespace>.*` и подкладывает
конфигурацию (файлы через `xdg.configFile` / `home.file`, пакеты,
сервисы, переменные) только когда пользователь явно запросил
соответствующие опции в `users/<name>.nix`.

## Стили активации

### `auto.*`-gated (хост-обязательные фичи)

Модуль активен для всех HM-пользователей на хостах, где хост выставил
соответствующий флаг. Пример: `npm-global.nix` подкладывает `PATH`
для глобальных npm-пакетов, если у хоста стоит `auto.dev.nodejs = true`.

```nix
# users/modules/<name>.nix
{ config, lib, auto, ... }:

{
  config = lib.mkIf auto.<feature> {
    # ...класть файлы / менять конфиг...
  };
}
```

Чтобы добавить такой модуль:

1. `users/modules/<name>.nix` — `lib.mkIf auto.<feature>` в теле.
2. `modules/auto.nix` — `options.auto.<feature> = mkOption ...`.
3. `hosts/<host>/default.nix` — `auto.<feature> = true;`.
4. `users/<user>.nix` — `imports = [ ./modules/<name>.nix ];`.

### Per-user options (opt-in пользовательские фичи)

Модуль активен только если пользователь сам импортировал его и
задал опции в `users/<name>.nix`. Самый гибкий стиль: пользователь
сам решает, нужна ли ему фича, и на каких хостах.

```nix
# users/modules/<name>.nix
{ config, lib, pkgs, hostName, ... }:

{
  options.<namespace>.<feature> = {
    enable = lib.mkEnableOption "..." // { default = true; };
    hosts  = lib.mkOption { type = lib.types.listOf lib.types.str;
                             default = [];
                             example = [ "aleroza-pc" ];
                             description = "..."; };
    # ...другие параметры фичи...
  };

  config = lib.mkIf (config.<namespace>.<feature>.enable
    && (config.<namespace>.<feature>.hosts == []
        || builtins.elem hostName config.<namespace>.<feature>.hosts)) {
    # ...класть файлы / менять конфиг...
  };
}
```

Чтобы добавить такой модуль:

1. `users/modules/<name>.nix` — `options` + `lib.mkIf`-гейт по
   `enable` и `hosts`.
2. `users/<user>.nix` — `imports = [ ./modules/<name>.nix ];` +
   `<namespace>.<feature> = { ... };`.

Пример: `users/modules/wireplumber-amplify.nix` — усилитель звука
для ALSA-выходов, активируется у пользователя aleroza на хосте
`aleroza-pc` через `volume = 1.5`.

## Правила проектирования

- **Один стиль активации на модуль.** Либо `auto.*`-gated (читает
  `auto` из `extraSpecialArgs`), либо per-user-options (читает
  `config.<namespace>.*`). Если нужны оба — разнесите на два файла.

- **Пространство иммён опций = то, что пользователь пишет в файле.**
  `options.wireplumber.amplify.*` ↔ `wireplumber.amplify = { ... }`
  в `users/<name>.nix`. Это контракт: переименование пространства
  имён — breaking change для пользовательских файлов.

- **Документация — в шапке модуля** (комментарий `# ▸ ...`),
  не в пользовательском файле. Пользовательский файл должен
  содержать только компактную декларацию опций (3–6 строк).

- **`enable` с дефолтом `true`** — opt-out, а не opt-in. Пользователь,
  импортировавший модуль, получает его работу по умолчанию; чтобы
  выключить — пишет `enable = false`.

- **`hosts = []` = «все хосты».** Не `null`, не опциональный список —
  пустой список это явное «без фильтра». Идиоматично и легко читается:
  `hosts == [] || builtins.elem hostName hosts`.

- **`hostName` пробрасывается через `extraSpecialArgs`.** В
  home-manager-модуле нет `config.networking.hostName` — это
  NixOS-опция, в HM она не определена. Берётся из
  `extraSpecialArgs.hostName` (см. `users/default.nix`).

- **Файлы через `xdg.configFile` / `home.file` не должны существовать
  у пользователя вручную.** Иначе HM откажется (без `force = true`).
  Если модуль кладёт `~/.config/wireplumber/main.lua.d/...` — это
  теперь территория модуля.

## Шаблон: «положить готовый файл»

```nix
{ config, lib, pkgs, hostName, ... }:

{
  options.mytool.things = {
    enable = lib.mkEnableOption "..." // { default = true; };
    hosts  = lib.mkOption { type = lib.types.listOf lib.types.str;
                             default = []; example = [ "aleroza-pc" ]; };
  };

  config = lib.mkIf (config.mytool.things.enable
    && (config.mytool.things.hosts == []
        || builtins.elem hostName config.mytool.things.hosts)) {
    xdg.configFile."mytool/config.toml".source = pkgs.writeText "config.toml" ''
      # generated from users/modules/mytool.nix
      key = "value";
    '';
  };
}
```

## Шаблон: «установить пакет»

```nix
config = lib.mkIf (...) {
  home.packages = [ pkgs.ripgrep ];
};
```

## Шаблон: «per-user systemd unit»

```nix
systemd.user.services.mything = {
  Unit = { Description = "..."; After = [ "network.target" ]; };
  Service = {
    ExecStart = "${pkgs.mypkg}/bin/mything --serve";
    Restart = "on-failure";
  };
  Install = { WantedBy = [ "default.target" ]; };
};
```

Требует `users.users.<name>.linger = true;` в NixOS-конфиге, чтобы
юнит жил после закрытия графической сессии.
