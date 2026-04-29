{ config, lib, pkgs, ... }:

# ▸ Аппаратные модули — bluetooth, i2c, udev, kernel

let
  cfg = config.auto;
in

{
  # ── Bluetooth ────────────────────────────────────────────────────
  # Включается если auto.bluetooth = true

  hardware.bluetooth = lib.mkIf cfg.bluetooth {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
        Experimental = true;
      };
    };
  };

  # ── i2c-dev (управление яркостью внешних мониторов) ─────────────
  boot.kernelModules = [ "i2c-dev" ];

  services.udev.extraRules = ''
    KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"
  '';

  users.groups.i2c = { };
}
