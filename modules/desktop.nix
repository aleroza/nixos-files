{ config, lib, pkgs, ... }:

# ▸ Включится только если auto.desktop = true
#    И дополнительно — если есть auto.development, включить ещё gui-средства

lib.mkIf config.auto.desktop {

  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Можно комбинировать фичи внутри модуля
  environment.systemPackages = with pkgs; [
    firefox
    alacritty
  ] ++ lib.optionals config.auto.development [
    # Только если desktop + development
    vscode
  ];
}
