{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.auto.gnome.extensions.display-brightness-ddcutil;
in

{
  options.auto.gnome.extensions.display-brightness-ddcutil = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable display-brightness-ddcutil GNOME extension and i2c support.";
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = lib.lists.optional (config.auto.mainUser != "") config.auto.mainUser;
      description = "Users to configure with the ddcutil extension (i2c group, home-manager).";
    };
  };

  config = lib.mkIf (cfg.enable && config.auto.gnome.enable) {

    # ── i2c-dev (управление яркостью внешних мониторов) ─────────────
    boot.kernelModules = [ "i2c-dev" ];

    services.udev.extraRules = ''
      KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"
    '';

    users.groups.i2c = { };

    # ── Добавление пользователей в группу i2c ─────────────────────
    users.users = lib.genAttrs cfg.users (name: {
      extraGroups = [ "i2c" ];
    });

    # ── ddcutil system package ──────────────────────────────────────
    environment.systemPackages = with pkgs; [ ddcutil ];

    # ── Home-manager: настройка GNOME расширения для каждого юзера ──
    home-manager.users = lib.genAttrs cfg.users (name: {
      home.packages = with pkgs; [ gnomeExtensions.brightness-control-using-ddcutil ];

      dconf.settings = {
        "org/gnome/shell" = {
          enabled-extensions = lib.mkBefore [
            "display-brightness-ddcutil@themightydeity.github.com"
          ];
        };
        "org/gnome/shell/extensions/display-brightness-ddcutil" = {
          show-display-name = true;
          button-location = 1;
        };
      };
    });
  };
}
