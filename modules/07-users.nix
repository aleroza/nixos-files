{ config, lib, pkgs, ... }:

{
  # Groups
  users.groups = {
    i2c = { };
    openclaw = { };
    plocate = { };
  };

  # User: aleroza
  users.users.aleroza = {
    hashedPasswordFile = "./secrets/aleroza-password";
    isNormalUser = true;
    extraGroups = [
      "wheel"    # sudo
      "docker"   # Docker access
      "i2c"      # brightness control
      "plocate"
    ];
  };

  # Shell aliases
  environment.shellAliases = {
    ll = "ls -l";
    nix-rebuild = "sudo nixos-rebuild switch --flake .#aleroza-pc";
    nix-gen = ''echo "Path: $(readlink /run/current-system)"; echo "  ID: $(readlink /nix/var/nix/profiles/system)"'';
  };

  # User: openclaw (service account)
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
}
