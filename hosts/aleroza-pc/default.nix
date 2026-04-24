# Aleroza-PC Host Configuration
# Modular NixOS configuration
{ inputs ? { }, ... }:

{
  imports = [
    # Hardware
    ../../hardware-configuration.nix

    # New modular modules
    ../../modules/core/base.nix
    ../../modules/networking/base.nix
    ../../modules/networking/ssh.nix
    ../../modules/security/base.nix
    ../../modules/users/groups.nix
    ../../modules/users/base.nix
    ../../modules/audio/base.nix
    ../../modules/audio/bluetooth.nix
    ../../modules/input/libinput.nix
    ../../modules/virtualization/docker.nix
    ../../modules/packages/base.nix
    ../../modules/packages/dev-tools.nix
    ../../modules/packages/apps.nix

    # Legacy configuration (unmigrated sections remain here)
    ../../configuration.nix
  ];

  # Machine-specific configuration
  config = {
    networking.hostName = "aleroza-pc";

    # Boot loader
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
  };
}