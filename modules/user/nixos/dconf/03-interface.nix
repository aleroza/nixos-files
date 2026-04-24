{ config, lib, pkgs, ... }:

{
  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/interface".show-battery-percentage = true;
    };
  };
}
