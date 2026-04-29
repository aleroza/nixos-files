{ config, lib, pkgs, ... }:

{
  # ▸ Основная настройка хоста
  system.stateVersion = "25.11";
  networking.hostName = "somehost";

  # ▸ auto — конфигурация этого хоста
  auto = {
    development = true;
    gaming      = true;
    desktop     = true;
    server      = false;

    docker = {
      enable = true;
      users  = [ "testuser" ];
    };

    hmUsers = [ "testuser" ];
  };

  # ▸ Пользователи (для docker.users + hmUsers)
  users.users = lib.genAttrs [ "testuser" ] (name: {
    isNormalUser = true;
    description = "Template user ${name}";
    group = name;
  });

  users.groups = lib.genAttrs [ "testuser" ] (name: {});

  # А вот так — просто добавить новую фичу:
  # auto.office = true;
  # auto.media  = false;

  # Можно переопределить что угодно поверх модулей
  environment.systemPackages = with pkgs; [
    htop
    curl
  ];

  # ▸ Unfree пакеты (vscode и т.д.)
  nixpkgs.config.allowUnfree = true;

  # ▸ Минимальное, чтобы собралось
  boot.loader.grub.devices = [ "/dev/sda" ];
  fileSystems."/" = {
    device = "/dev/sda1";
    fsType = "ext4";
  };
}
