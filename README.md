# nixos-files · template

**Feature-toggle NixOS config через единую `auto` опцию.**

Фичи включаются одной переменной в конфиге хоста — модули сами решают, подхватываться или нет. Никакой ручной возни с `imports`.

## Быстрый старт

```bash
# 1. Форкни репозиторий
# 2. Клонируй
git clone <твой-форк>
cd nixos-files

# 3. Создай secrets (опционально)
mkdir -p secrets/
mkpasswd -m sha-512 > ./secrets/<имя-пользователя>-password

# 4. Создай свой хост
cp -r hosts/somehost hosts/my-laptop
#    поправь networking.hostName в hosts/my-laptop/default.nix

# 5. Собери
sudo nixos-rebuild switch --flake .#my-laptop
```

## Структура

```
flake.nix              # входная точка, собирает хост из модулей
├── modules/
│   ├── auto.nix       # объявляет options.auto — единая конфигурация
│   ├── default.nix    # импортирует все модули
│   ├── development.nix
│   ├── desktop.nix
│   ├── gaming.nix
│   └── docker.nix     # модули сами гейтятся через lib.mkIf
├── hosts/
│   └── somehost/
│       └── default.nix  # конфиг конкретного хоста (задаёт auto)
└── users/
    ├── default.nix     # подключает home-manager для auto.hmUsers
    └── testuser.nix    # home-manager конфиг пользователя
```

## Как работает `auto`

В `modules/auto.nix` объявлена опция `auto` — единое пространство для всей конфигурации хоста:

```nix
auto = {
  development = true;   # включить dev-инструменты
  gaming      = false;  # выключить игры
  desktop     = true;   # включить KDE
  docker = {
    enable = true;
    users  = [ "testuser" ];  # кто в docker group
  };
  hmUsers = [ "testuser" ];   # у кого home-manager
};
```

Каждый модуль сам проверяет свою опцию:

```nix
# modules/development.nix
{ config, lib, pkgs, ... }:

lib.mkIf config.auto.development {
  environment.systemPackages = with pkgs; [ git vim gcc python3 nodejs ];
};
```

Всё остальное — обычный NixOS. Никакой магии, просто удобная группировка.

## Как добавить модуль

1. Создай `modules/myfeature.nix`
2. Оберни в `lib.mkIf config.auto.myfeature`
3. Добавь `myfeature` в `options.auto` в `modules/auto.nix` (со своим типом)
4. Импортни в `modules/default.nix`

```nix
# modules/media.nix
{ config, lib, pkgs, ... }:

lib.mkIf config.auto.media {
  services.jellyfin.enable = true;
};
```

## Как добавить хост

```bash
cp -r hosts/somehost hosts/newhost
```

Правишь `networking.hostName`, выставляешь `auto` под себя — готово. Добавляешь вызов `mkHost "newhost"` в `flake.nix`.

## Requirements

- NixOS 25.11
- Home-manager release-25.11

## Лицензия

MIT — делай что хочешь.
