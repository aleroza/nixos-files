{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.auto.gnome.extensions.clipboard-indicator;
in

{
  options.auto.gnome.extensions.clipboard-indicator = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Clipboard Indicator GNOME extension.";
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = lib.lists.optional (config.auto.mainUser != "") config.auto.mainUser;
      description = "Users to configure the Clipboard Indicator extension for.";
    };
  };

  config = lib.mkIf (cfg.enable && config.auto.gnome.enable) {
    environment.systemPackages = with pkgs; [ gnomeExtensions.clipboard-indicator ];

    home-manager.users = lib.genAttrs cfg.users (name: {
      dconf.settings = {
        "org/gnome/shell" = {
          enabled-extensions = lib.mkBefore [
            "clipboard-indicator@tudmotu.com"
          ];
        };
        "org/gnome/shell/extensions/clipboard-indicator" = {
          display-mode = 2;
          topbar-preview-size = 15;
        };
      };
    });
  };
}
