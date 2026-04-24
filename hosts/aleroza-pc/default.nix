# Aleroza-PC Host Configuration
# Modular NixOS configuration
{ inputs ? { }, ... }:

{
  imports = [
    # Hardware
    ../../hardware-configuration.nix

    # Host-specific hardware
    ./lid.nix

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
    ../../modules/display/x11.nix
    ../../modules/display/gdm.nix
    ../../modules/packages/base.nix
    ../../modules/packages/dev-tools.nix
    ../../modules/packages/apps.nix
    ../../modules/packages/editors/vscode.nix
    ../../modules/shell/aliases.nix

    # Desktop environments
    ../../desktop/gnome/default.nix

    # Legacy configuration (unmigrated sections remain here)
    # NOTE: configuration.nix removed to avoid circular import
  ];

  # Machine-specific configuration
  config = {
    networking.hostName = "aleroza-pc";

    # Boot loader
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # Allow unfree packages (google-chrome, steam, etc.)
    nixpkgs.config.allowUnfree = true;

    # Required: state version
    system.stateVersion = "25.11";
  };
}