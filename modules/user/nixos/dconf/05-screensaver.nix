{ config, lib, pkgs, ... }:

{
  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/session" = {
        idle-delay = lib.hm.gvariant.mkUint32 720;
      };
      "org/gnome/screensaver" = {
        lock-enabled = true;
        lock-delay = 0;
      };
    };
  };
}
