{ inputs ? { }, lib ? null, pkgs ? null, ... }:

{
  home.username = "aleroza";
  home.homeDirectory = "/home/aleroza";

  imports = [
    ../../modules/user/portable/01-git.nix
    ../../modules/user/portable/02-shell-env.nix
    ../../modules/user/portable/03-shell-aliases.nix
    ../../modules/user/portable/04-defaults.nix
    ../../modules/user/portable/05-cli-apps.nix
    ../../modules/user/portable/06-xdg-mimeapps.nix
    ../../modules/user/nixos/dconf/01-shortcuts.nix
    ../../modules/user/nixos/dconf/02-favorites.nix
    ../../modules/user/nixos/dconf/03-interface.nix
    ../../modules/user/nixos/dconf/04-power.nix
    ../../modules/user/nixos/dconf/05-screensaver.nix
    ../../modules/user/nixos/dconf/06-wm.nix
    ../../modules/user/nixos/dconf/07-extensions.nix
    ../../modules/user/nixos/dconf/08-input.nix
    ../../modules/user/nixos/gnome-extensions.nix
    ../../modules/user/nixos/monitors.nix
    ../../modules/user/nixos/autostart.nix
  ];

  # Flatpak activation
  home.activation = {
    setupFlatpak = ''
      ${pkgs.flatpak}/bin/flatpak --user remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    '';
    installBottles = lib.hm.dag.entryAfter [ "setupFlatpak" ] ''
      ${pkgs.flatpak}/bin/flatpak --user install --noninteractive flathub com.usebottles.bottles
      ${pkgs.flatpak}/bin/flatpak override --user com.usebottles.bottles --filesystem=xdg-data/Steam --share=network
    '';
  };
}
