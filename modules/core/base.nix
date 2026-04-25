# Core base module: boot, kernel, swap, udev
{ config, lib, pkgs, ... }:

{
  options.core = {
    kernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "i2c-dev" ];
      description = "List of kernel modules to load.";
    };
    i2cUdevGroup = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Create i2c udev rules and group.";
    };
  };

  config = {
    # Kernel packages - use latest
    boot.kernelPackages = pkgs.linuxPackages_latest;

    # Kernel modules
    boot.kernelModules = config.core.kernelModules;

    # Swap devices
    swapDevices = [
      { device = "/.swapvol/swapfile"; }
    ];

    # Udev rules for i2c
    services.udev.extraRules = lib.mkIf config.core.i2cUdevGroup ''
      KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"
    '';
  };
}