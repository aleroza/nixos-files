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

    server = mkOption {
      type = types.bool;
      default = false;
      description = "Enable server configuration.";
    };

    # ▸ Desktop environments (individual toggles, any combination allowed)
    xserver = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable X11 windowing system.";
      };
    };

    gnome = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable GNOME desktop environment.";
      };
    };

    kde = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable KDE Plasma desktop environment.";
      };
    };

    hyprland = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Hyprland compositor.";
      };
    };

    displayManager = {
      autoLogin = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable auto-login on display manager.";
        };

        user = mkOption {
          type = types.str;
          default = "aleroza";
          description = "User to auto-login as.";
        };
      };
    };

    power = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable power management (logind).";
      };
    };

    sound = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable sound (PipeWire).";
      };
    };

    input = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable touchpad / libinput.";
      };
    };

    programs = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable common desktop programs (Firefox, etc.).";
      };
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
