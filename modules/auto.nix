{ config, lib, ... }: let
  inherit (lib) types mkOption;
in {
  options.auto = {
    # ▸ Feature toggles
    development = mkOption {
      type = types.bool;
      default = false;
      description = "Enable development tools (git, compilers, IDEs).";
    };

    gaming = mkOption {
      type = types.bool;
      default = false;
      description = "Enable gaming tools (Steam, Lutris, MangoHud).";
    };

    desktop = mkOption {
      type = types.bool;
      default = false;
      description = "Enable desktop environment.";
    };

    server = mkOption {
      type = types.bool;
      default = false;
      description = "Enable server configuration.";
    };

    # ▸ Desktop environment selection
    desktopType = mkOption {
      type = types.enum [ "gnome" "kde" "hyprland" "none" ];
      default = "none";
      description = "Which desktop environment to use (only applies when auto.desktop = true).";
    };

    # ▸ Docker
    docker = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Docker daemon.";
      };

      users = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Users to add to the docker group.";
      };
    };

    # ▸ Bluetooth
    bluetooth = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Bluetooth support.";
    };

    # ▸ Flatpak
    flatpak = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Flatpak (flathub) support.";
    };

    # ▸ SSH server
    ssh = mkOption {
      type = types.bool;
      default = false;
      description = "Enable OpenSSH server.";
    };

    # ▸ Fail2ban
    fail2ban = mkOption {
      type = types.bool;
      default = false;
      description = "Enable fail2ban.";
    };

    # ▸ Home-manager users
    hmUsers = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Users configured via home-manager.";
    };
  };
}
