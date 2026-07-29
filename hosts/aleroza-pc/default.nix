{
  config,
  lib,
  pkgs,
  nixpkgs-unstable,
  ...
}:

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
    mainUser = "aleroza";
    dev = {
      enable = true;
      nodejs = true;
      python = true;
      networkCapture = {
        enable = true;
        users = [
          "aleroza"
          "openclaw"
        ];
      };
    };
    gaming = true;
    firewall = {
      gaming = true;
      # Interfaces trusted by the firewall (required for LAN game discovery).
      # Run `ip link` to find the correct name; common values:
      #   wlan0, wlp1s0, wlp3s0  (Wi-Fi)
      #   enp0s3, eth0            (Ethernet)
      # `tailscale0` is added for hosting games over the tailnet.
      trustedInterfaces = [
        "wlp1s0"
      ];
      # Deluge default listen port — required so peers can connect back
      # to us; without it the firewall blocks incoming and only seeds
      # that initiate the TCP connection actually transfer data.
      allowedTCPPorts = [
        53
        67
        6881
      ];
      allowedUDPPorts = [
        53
        67
        68
        6881
      ];
    };
    desktop = true;
    laptop = true;

    # xserver.enable = true; @ Wayland in gnome
    gnome = {
      enable = true;
      extensions = {
        display-brightness-ddcutil.enable = true;
        appindicator.enable = true;
        clipboard-indicator.enable = true;
      };
    };

    flatpak = true;

    docker = {
      enable = true;
      users = [ "openclaw" ];
    };

    hmUsers = [
      "aleroza"
      "openclaw"
    ];
  };

  # ▸ Display manager override (DE модули ставят user = "", перебиваем тут)
  services.displayManager.autoLogin.user = lib.mkForce "aleroza";

  # services.deluge.enable = true;
  # services.deluge.openFirewall = true;

  # ▸ Группы
  users.groups = {
    openclaw = { };
    plocate = { };
  };

  # ▸ Пользователь aleroza
  users.users.aleroza = {
    hashedPasswordFile = "/etc/nixos/secrets/aleroza-password";
    isNormalUser = true;
    linger = true;
    extraGroups = [
      "wheel"
      "docker"
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
    fastfetch
    git

    conntrack-tools
    socat
    wirelesstools

    fd
    plocate
    fzf

    vscode
    gh
    nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.flclash
    telegram-desktop
    onlyoffice-desktopeditors
    filezilla

    prismlauncher

    ntfs3g
    exfat
    dosfstools
    darktable
    exiftool
  ];

  # ▸ Монитор (раскладка двух экранов, host-specific) ───────────────
  home-manager.users.aleroza.home.file.".config/monitors.xml" = {
    force = true;
    text = ''
      <monitors version="2">
        <configuration>
          <layoutmode>physical</layoutmode>
          <logicalmonitor>
            <x>320</x>
            <y>1440</y>
            <scale>1</scale>
            <monitor>
              <monitorspec>
                <connector>eDP-1</connector>
                <vendor>LGD</vendor>
                <product>0x05e5</product>
                <serial>0x00000000</serial>
              </monitorspec>
              <mode>
                <width>1920</width>
                <height>1080</height>
                <rate>59.977</rate>
              </mode>
            </monitor>
          </logicalmonitor>
          <logicalmonitor>
            <x>0</x>
            <y>0</y>
            <scale>1</scale>
            <primary>yes</primary>
            <monitor>
              <monitorspec>
                <connector>HDMI-1</connector>
                <vendor>XMI</vendor>
                <product>Mi monitor</product>
                <serial>5392700011291</serial>
              </monitorspec>
              <mode>
                <width>2560</width>
                <height>1440</height>
                <rate>59.951</rate>
              </mode>
            </monitor>
          </logicalmonitor>
        </configuration>
      </monitors>
    '';
  };
}
