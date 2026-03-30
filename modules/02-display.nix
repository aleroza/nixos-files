{ config, lib, pkgs, ... }:

{
  # X11
  services.xserver.enable = true;

  # GDM
  services.displayManager.gdm.enable = true;

  # Auto-login
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "aleroza";

  # Keyboard layout
  services.xserver.xkb.layout = "us,ru";

  # Logind (lid switch behaviour)
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "lock";
    HandleLidSwitchDocked = "ignore";
  };
}
