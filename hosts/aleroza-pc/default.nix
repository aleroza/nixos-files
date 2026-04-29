{ config, lib, pkgs, ... }:

{
  # ▸ Основная настройка хоста
  system.stateVersion = "25.11";
  networking.hostName = "aleroza-pc";

  # ▸ Boot loader — systemd-boot (EFI)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ▸ Latest kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # ▸ Swap (файл на btrfs subvol)
  swapDevices = [
    { device = "/.swapvol/swapfile"; }
  ];

  # ▸ Часовой пояс
  time.timeZone = "Europe/Moscow";

  # ▸ Импорт auto-detected hardware config
  imports = [
    ./hardware-configuration.nix
  ];

  # ▸ auto — конфигурация этого хоста
  auto = {
    development = true;
    gaming      = true;
    desktop     = true;
    desktopType = "gnome";
    server      = false;

    bluetooth = true;
    flatpak   = true;
    ssh       = true;
    fail2ban  = true;

    docker = {
      enable = true;
      users  = [ "aleroza" "openclaw" ];
    };

    hmUsers = [ "aleroza" "openclaw" ];
  };

  # ▸ Группы
  users.groups = {
    openclaw = { };
    plocate = { };
  };

  # ▸ Пользователь aleroza
  users.users.aleroza = {
    hashedPasswordFile = "/etc/nixos/secrets/aleroza-password";
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "docker"
      "i2c"
      "plocate"
    ];
  };

  # ▸ Пользователь openclaw
  users.users.openclaw = {
    isNormalUser = true;
    home = "/home/openclaw";
    createHome = true;
    group = "openclaw";
    extraGroups = [
      "docker"
    ];
    linger = true;
    description = "OpenClaw service account";
  };

  # ▸ Shell-алиасы
  environment.shellAliases = {
    ll = "ls -lah";
    nix-rebuild = "sudo nixos-rebuild switch --flake .#aleroza-pc";
    nix-gen = ''echo "Path: $(readlink /run/current-system)"; echo "  ID: $(readlink /nix/var/nix/profiles/system)"'';
  };

  # ▸ Системные пакеты (хостовые — не входящие в модули)
  environment.systemPackages = with pkgs; [
    home-manager
    usbutils
    pciutils
    psmisc
    vim
    wget
    htop
    btop
    parted
    ddcutil
    fastfetch

    conntrack-tools
    socat
    tcpdump
    wireshark
    wirelesstools

    fd
    plocate
    fzf

    vscode
    gh
    flclash
    git
    telegram-desktop
  ];
}
