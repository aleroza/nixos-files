{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.auto.gnome.extensions.appindicator;
in

{
  options.auto.gnome.extensions.appindicator = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable AppIndicator GNOME extension support.";
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = lib.lists.optional (config.auto.mainUser != "") config.auto.mainUser;
      description = "Users to enable the AppIndicator extension for.";
    };
  };

  config = lib.mkIf (cfg.enable && config.auto.gnome.enable) {
    # Package (gnomeExtensions.appindicator) is already installed
    # system-wide in modules/gnome/default.nix

    home-manager.users = lib.genAttrs cfg.users (name: {
      dconf.settings = {
        "org/gnome/shell" = {
          enabled-extensions = lib.mkBefore [
            "appindicatorsupport@rgcjonas.gmail.com"
          ];
        };
      };
    });
  };
}
