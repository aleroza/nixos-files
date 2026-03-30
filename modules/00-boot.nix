{ config, lib, pkgs, ... }:

{
  # Boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelModules = [ "i2c-dev" ];

  # Swap
  swapDevices = [
    { device = "/.swapvol/swapfile"; }
  ];
}
