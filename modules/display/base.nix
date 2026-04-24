{ config, lib, pkgs, ... }:
{
  options.desktop.environment = lib.mkOption {
    type = lib.types.enum [ "gnome" "kde" "hyprland" "none" ];
    default = "gnome";
    description = "Desktop environment to use";
  };

  config = {
    
  };
}