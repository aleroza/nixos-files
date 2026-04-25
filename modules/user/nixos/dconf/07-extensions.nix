{ config, lib, pkgs, ... }:

{
  dconf = {
    enable = true;
    settings = {
      "org/gnome/shell/extensions/display-brightness-ddcutil" = {
        show-display-name = true;
        button-location = 1;
      };
      "org/gnome/shell/extensions/clipboard-indicator" = {
        display-mode = 2;
        topbar-preview-size = 15;
      };
    };
  };
}
