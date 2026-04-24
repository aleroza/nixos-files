# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page,
# on https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

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

  # === MIGRATED TO modules/display/x11.nix ===
  # services.xserver.enable = true;
  # services.xserver.xkb.layout = "us,ru";

  # === MIGRATED TO modules/display/gdm.nix ===
  # services.displayManager.gdm.enable = true;
  # services.displayManager.autoLogin.enable = true;
  # services.displayManager.autoLogin.user = "aleroza";

  # === MIGRATED TO desktop/gnome/core.nix ===
  # services.desktopManager.gnome.enable = true;
  # environment.gnome.excludePackages = with pkgs; [ epiphany ];

  # === MIGRATED TO hosts/aleroza-pc/lid.nix ===
  # services.logind.settings.Login = {
  #   HandleLidSwitch = "suspend-then-hibernate";
  #   HandleLidSwitchExternalPower = "lock";
  #   HandleLidSwitchDocked = "ignore";
  # };

  # === MIGRATED TO modules/users/base.nix ===
  # users.users.aleroza = {
  #   hashedPasswordFile = "./secrets/aleroza-password";
  #   isNormalUser = true;
  #   extraGroups = [ "wheel" "docker" "i2c" "plocate" ];
  # };
  # users.users.openclaw = {
  #   isNormalUser = true;
  #   home = "/home/openclaw";
  #   createHome = true;
  #   group = "openclaw";
  #   extraGroups = [ "docker" ];
  #   linger = true;
  #   description = "OpenClaw service account";
  # };

  # === MIGRATED TO modules/shell/aliases.nix ===
  # environment.shellAliases = {
  #   ll = "ls -lah";
  #   nix-rebuild = "sudo nixos-rebuild switch --flake .#aleroza-pc";
  #   nix-gen = ''echo "Path: $(readlink /run/current-system)"; echo "  ID: $(readlink /nix/var/nix/profiles/system)"'';
  # };

  # === MIGRATED TO modules/packages/apps.nix ===
  # programs.steam = { enable = true; remotePlay.openFirewall = true; ... };
  # programs.firefox.enable = true;
  # services.flatpak.enable = true;
  # system.activationScripts.flatpak-setup = ...

  nixpkgs.config.allowUnfree = true;

  # === REMAINING IN CONFIGURATION (not yet migrated) ===

  # Base system packages - only non-migrated packages remain here
  environment.systemPackages = with pkgs; [
    home-manager
    usbutils
    pciutils
    vim
    wget
    htop
    btop
    parted
    fastfetch

    conntrack-tools
    socat
    tcpdump
    wirelesstools

    fd
    plocate
    fzf

    gh
    nixfmt

    telegram-desktop
    flclash
    git
  ];

  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.11"; # Did you read the comment?

}