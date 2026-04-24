{ config, lib, pkgs, ... }:

{
  dconf = {
    enable = true;
    settings = {
      "org/gnome/settings-daemon/plugins/media-keys" = {
        custom-keybindings = [
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/open-console/"
        ];
      };
      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/open-console" = {
        name = "Open Console";
        command = "kgx";
        binding = "<Control><Alt>t";
      };
    };
  };
}
