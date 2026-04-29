{ config, lib, pkgs, ... }:

# ▸ Включится если auto.flatpak = true
#   Устанавливает Flatpak + Flathub + Flatseal

lib.mkIf config.auto.flatpak {

  services.flatpak.enable = true;

  system.activationScripts = {
    flatpak-setup = ''
      ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
      ${pkgs.flatpak}/bin/flatpak install --noninteractive flathub com.github.tchx84.Flatseal
    '';
  };
}
