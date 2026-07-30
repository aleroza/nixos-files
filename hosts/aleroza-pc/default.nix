{
  config,
  lib,
  pkgs,
  nixpkgs-unstable,
  hermes-agent,
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
      login = [
        {
          user = "aleroza";
          username = "aleroza";
          passwordFile = "/run/secrets/aleroza/dockerhub/password";
        }
      ];
    };

    sops = {
      enable = true;
      users = [
        "aleroza"
      ];
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

  # ▸ sops-nix: расшифрованные секреты.
  sops.secrets =
    let
      alerozaSecret =
        attrs:
        {
          sopsFile = ./secrets/users/aleroza.yaml;
          owner = "aleroza";
          group = "users";
          mode = "0400";
        }
        // attrs;
    in
    {
      "aleroza/password" = alerozaSecret { };
      "aleroza/dockerhub/password" = alerozaSecret { };
      "hermes/env" = alerozaSecret {
        owner = "hermes";
        group = "hermes";
        mode = "0400";
      };
    };

  # ▸ Подсказываем интерактивному `sops`, какие правила шифрования применять.
  environment.sessionVariables.SOPS_CONFIG = toString ./.sops.yaml;

  # ▸ Пользователь aleroza
  users.users.aleroza = {
    hashedPasswordFile = "/run/secrets/aleroza/password";
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

  # ▸ Hermes (system user, created by hermes-agent NixOS module).
  # See hosts/aleroza-pc/README.md for full rationale.
  users.users.hermes.extraGroups = [
    "systemd-journal"
  ];

  # ▸ Hermes Agent (managed by hermes-agent NixOS module)
  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;
    environmentFiles = [ "/run/secrets/hermes/env" ];
    environment = {
      HTTP_PROXY = "http://127.0.0.1:7890";
      HTTPS_PROXY = "http://127.0.0.1:7890";
      ALL_PROXY = "http://127.0.0.1:7890";
      http_proxy = "http://127.0.0.1:7890";
      https_proxy = "http://127.0.0.1:7890";
      all_proxy = "http://127.0.0.1:7890";
      NO_PROXY = "127.0.0.1,localhost,::1";
      no_proxy = "127.0.0.1,localhost,::1";
    };
    settings.model = "minimax/MiniMax-M3";
    settings.toolsets = [ "all" ];

    # Fix "ModuleNotFoundError: No module named 'hermes_state_common'"
    package =
      let
        basePkg = hermes-agent.packages.x86_64-linux.default;
        pythonSrc = basePkg.hermesNpmLib.pythonSrc;
        venv = basePkg.hermesVenv;
      in
      basePkg.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          mkdir -p $out/lib/python3.12/site-packages
          for mod in hermes_state_common hermes_state_portability hermes_state_schema hermes_state_search; do
            if [ -f "${pythonSrc}/$mod.py" ]; then
              cp -f "${pythonSrc}/$mod.py" "$out/lib/python3.12/site-packages/$mod.py"
            fi
          done
          # Re-wrap each hermes entry-point to inject the patched site-packages
          # on PYTHONPATH, so Python finds our copies before the wheel's.
          for bin in hermes hermes-agent hermes-acp; do
            if [ -x "$out/bin/$bin" ]; then
              wrapProgram "$out/bin/$bin" \
                --prefix PYTHONPATH : "$out/lib/python3.12/site-packages"
            fi
          done
        '';
      });
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
    parted
    fastfetch
    git
    inotify-tools
    bpftrace

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
          <layoutmode>logical</layoutmode>
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

  # ▸ Hermes-triggered system activation (NNP-safe).
  # Root systemd unit + path trigger so hermes can switch generations
  # without sudo / without disabling NNP on hermes-agent.service.
  #
  # Workflow:
  #   1. Hermes edits the flake and commits.
  #   2. Hermes runs `nix build` itself (as hermes, nixbld group) to
  #      produce the system closure in /nix/store.
  #   3. Hermes writes the closure path to
  #      /var/lib/hermes/workspace/.pending-switch.
  #   4. Hermes touches /var/lib/hermes/workspace/.switch-request.
  #   5. systemd.paths triggers nixos-activate.service.
  #   6. The service (as root, NNP=false) reads .pending-switch and
  #      runs switch-to-configuration against that closure.
  #
  # The service does NOT build — the closure must already exist in
  # /nix/store. If the build fails, hermes catches it before
  # touching the request flag. See hosts/aleroza-pc/README.md.
  systemd.services.nixos-activate = {
    description = "Hermes-triggered nixos-rebuild activate (allowlisted)";
    wantedBy = [ ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      NoNewPrivileges = false;
      ProtectSystem = "full";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [
        "/var/lib/hermes/workspace/nixos-files"
        "/nix/store"
        "/var/run"
      ];
      RuntimeDirectory = "nixos-activate";
    };
    script = ''
      export PATH=/run/current-system/sw/bin
      export HOME=/var/root
      set -euo pipefail

      WORKSPACE=/var/lib/hermes/workspace
      REQUEST="$WORKSPACE/.switch-request"
      PENDING="$WORKSPACE/.pending-switch"

      # Tooling check.
      command -v flock >/dev/null || { echo "flock not in PATH" >&2; rm -f "$REQUEST"; exit 4; }

      # Lock against concurrent activations.
      LOCK=/run/nixos-activate/lock
      exec 9>"$LOCK"
      if ! flock -n 9; then
        echo "another activation in progress" >&2
        rm -f "$REQUEST"
        exit 3
      fi

      # Read the closure path that hermes built and stamped into
      # .pending-switch. Refuse if missing or doesn't look like a
      # /nix/store path.
      [ -f "$PENDING" ] || { echo "no pending switch at $PENDING" >&2; rm -f "$REQUEST"; exit 7; }
      CLOSURE=$(cat "$PENDING")
      case "$CLOSURE" in
        /nix/store/*-nixos-system-aleroza-pc-*) ;;
        *) echo "pending switch points to unexpected path: $CLOSURE" >&2; rm -f "$REQUEST" "$PENDING"; exit 8 ;;
      esac
      [ -x "$CLOSURE/bin/switch-to-configuration" ] || { echo "no switch-to-configuration in $CLOSURE" >&2; rm -f "$REQUEST" "$PENDING"; exit 9; }

      GEN="hermes-$(date +%Y%m%d-%H%M%S)"
      echo "activating generation $GEN from $CLOSURE"

      "$CLOSURE/bin/switch-to-configuration" switch

      rc=$?
      rm -f "$REQUEST" "$PENDING"
      exit $rc
    '';
  };

  systemd.paths.nixos-activate-trigger = {
    pathConfig = {
      PathExists = "/var/lib/hermes/workspace/.switch-request";
      Unit = "nixos-activate.service";
    };
    wantedBy = [ "paths.target" ];
  };
}
