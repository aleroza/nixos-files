{ config, lib, pkgs, ... }:

{
  # Libinput (touchpad/keyboard input)
  services.libinput.enable = true;

  # i2c-dev udev rules
  services.udev.extraRules = ''
    KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"
  '';
}
