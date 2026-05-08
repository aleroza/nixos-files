{ config, lib, ... }:
let
  inherit (lib) types mkOption;
in
{
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
      description = "Enable server profile. Convenience preset that enables ssh + fail2ban via mkDefault.";
    };

    desktop = mkOption {
      type = types.bool;
      default = false;
      description = "Enable desktop profile. Convenience preset that enables server + input + sound + programs + bluetooth via mkDefault.";
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

    laptop = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable laptop lid behavior (suspend/lock on lid close).";
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
        default = lib.lists.optional (config.auto.mainUser != "") config.auto.mainUser;
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
      default = [ ];
      description = "Users configured via home-manager.";
    };

    # ▸ Main system user
    mainUser = mkOption {
      type = types.str;
      default = "";
      description = "Primary system user. Auto-filled into module user-lists like docker.users or display-brightness-ddcutil.users.";
    };
  };
}
