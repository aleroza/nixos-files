{ config, lib, ... }:

let
  cfg = config.auto;
in

# ▸ Hyprland — заготовка (WIP)
lib.mkIf cfg.hyprland.enable {

  # services.displayManager.sddm.enable = true;
  # programs.hyprland.enable = true;

}
