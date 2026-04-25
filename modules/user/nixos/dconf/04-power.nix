{ config, lib, pkgs, ... }:

{
  dconf = {
    enable = true;
    settings = {
      "org/gnome/settings-daemon/plugins/power" = {
        sleep-inactive-ac-type = "nothing";
        sleep-inactive-ac-timeout = 0;
        sleep-inactive-battery-type = "hibernate";
        sleep-inactive-battery-timeout = 900;
      };
    };
  };
}
