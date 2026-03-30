{ config, lib, pkgs, ... }:

{
  # Base CLI utilities
  environment.systemPackages = with pkgs; [
    home-manager
    vim
    wget
    htop
    parted
    ddcutil
    fastfetch
    fd
    plocate
    fzf
    gh
    flclash
    git
  ];
}
