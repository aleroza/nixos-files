{ config, lib, pkgs, ... }:

{
  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/wm/preferences" = {
        button-layout = "appmenu:minimize,maximize,close";
        action-middle-click-titlebar = "minimize";
      };
    };
  };
}
