# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # === MIGRATED TO modules/core/base.nix ===
  # boot.loader.systemd-boot.enable = true;
  # boot.loader.efi.canTouchEfiVariables = true;
  # boot.kernelPackages = pkgs.linuxPackages_latest;
  # boot.kernelModules = [ "i2c-dev" ];
  # services.udev.extraRules = ''KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"'';
  # swapDevices = [ { device = "/.swapvol/swapfile"; } ];

  # === MIGRATED TO modules/networking/base.nix ===
  # networking.hostName = "aleroza-pc";
  # networking.networkmanager.enable = true;
  # time.timeZone = "Europe/Moscow";

  # === MIGRATED TO modules/audio/base.nix ===
  # services.pipewire = { enable = true; alsa.enable = true; alsa.support32Bit = true; pulse.enable = true; wireplumber.enable = true; };

  # === MIGRATED TO modules/audio/bluetooth.nix ===
  # hardware.bluetooth = { enable = true; powerOnBoot = true; settings = { General = { Enable = "Source,Sink,Media,Socket"; Experimental = true; }; }; };

  # === MIGRATED TO modules/input/libinput.nix ===
  # services.libinput.enable = true;

  # === MIGRATED TO modules/networking/ssh.nix ===
  # services.openssh = { enable = true; settings = { PermitRootLogin = "no"; }; };
  # services.fail2ban.enable = true; # in modules/security/base.nix

  # === MIGRATED TO modules/users/groups.nix ===
  # users.groups = { i2c = { }; openclaw = { }; plocate = { }; };

  # === MIGRATED TO modules/virtualization/docker.nix ===
  # virtualisation.docker = { enable = true; autoPrune.enable = true; };

  # === MIGRATED TO modules/packages/ ===
  # environment.systemPackages with base, dev-tools, apps - see modules/packages/

  # === REMAINING (NOT MIGRATED YET) ===

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  environment.gnome.excludePackages = with pkgs; [ epiphany ];

  # We are using disk encryption so skipping DM login
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "aleroza";

  # Disable lid switch sleep/hibernate - only turn off screen and lock
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "lock";
    HandleLidSwitchDocked = "ignore";
  };

  # Configure keymap in X11
  services.xserver.xkb.layout = "us,ru";

  # Enable sound.
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # Enable Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
        Experimental = true;
      };
    };
  };

  # Enable touchpad support
  services.libinput.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
    };
  };
  services.fail2ban.enable = true;

  # === REMAINING IN CONFIGURATION (not yet migrated) ===

  users.groups = {
    i2c = { };
    openclaw = { };
    plocate = { };
  };

  # User accounts (not migrated)
  users.users.aleroza = {
    hashedPasswordFile = "./secrets/aleroza-password";
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "docker"
      "i2c"
      "plocate"
    ];
  };

  environment.shellAliases = {
    ll = "ls -lah";
    nix-rebuild = "sudo nixos-rebuild switch --flake .#aleroza-pc";
    nix-gen = ''echo "Path: $(readlink /run/current-system)"; echo "  ID: $(readlink /nix/var/nix/profiles/system)"'';
  };

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

  nixpkgs.config.allowUnfree = true;

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
  };

  programs.firefox.enable = true;

  services.flatpak.enable = true;

  system.activationScripts = {
    flatpak-setup = ''
      ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
      ${pkgs.flatpak}/bin/flatpak install --noninteractive flathub com.github.tchx84.Flatseal
    '';
  };

  virtualisation.docker.enable = true;
  virtualisation.docker.autoPrune.enable = true;

  # Base system packages
  environment.systemPackages = with pkgs; [
    home-manager
    usbutils
    pciutils
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

    gh
    nixfmt

    gnome-tweaks
    gnomeExtensions.appindicator
    vscode
    telegram-desktop
    flclash
    git

    protonup-qt
    heroic
  ];

  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.11"; # Did you read the comment?

}