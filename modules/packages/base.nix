# Base system packages
{ config, lib, pkgs, ... }:

{
  config.environment.systemPackages = with pkgs; [
    git
    wget
    vim
    usbutils
    pciutils
    htop
    btop
    fastfetch
    parted
    fd
    plocate
    fzf
    conntrack-tools
    socat
    tcpdump
    wirelesstools
  ];
}