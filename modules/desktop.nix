{ config, lib, pkgs, ... }:

let
  cfg = config.auto;
in

# ▸ Включится только если auto.desktop = true
#   Выбор DE управляется через auto.desktopType

lib.mkIf cfg.desktop {

  # X11 windowing system
  services.xserver.enable = true;

  # ── Desktop environment ──────────────────────────────────────────
  # Выбор через одну опцию auto.desktopType
  # Поддерживаются: gnome, kde, hyprland — легко добавить новый DE

  services.displayManager.gdm.enable = cfg.desktopType == "gnome";
  services.desktopManager.gnome.enable = cfg.desktopType == "gnome";
  environment.gnome.excludePackages = lib.mkIf (cfg.desktopType == "gnome") (with pkgs; [
    epiphany
  ]);

  # Заготовки для переключения на другие DE (раскомментировать при добавлении):
  # services.displayManager.sddm.enable = cfg.desktopType == "kde";
  # services.desktopManager.plasma6.enable = cfg.desktopType == "kde";

  # ── Auto-login (при LUKS-шифровании диска пропускаем экран входа) ─
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "aleroza";

  # ── Управление питанием ──────────────────────────────────────────
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "lock";
    HandleLidSwitchDocked = "ignore";
  };

  # ── Раскладка клавиатуры ────────────────────────────────────────
  services.xserver.xkb.layout = "us,ru";
  # GNOME управляет переключением через dconf (xkb-options), поэтому
  # на уровне X сервера layout не настраиваем

  # ── Pipewire (звук) ─────────────────────────────────────────────
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # ── Тачпад ──────────────────────────────────────────────────────
  services.libinput.enable = true;

  # ── Firefox (NixOS модуль, а не просто пакет) ──────────────────
  programs.firefox.enable = true;

  # ── Базовая DE-пакеты ──────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    gnome-tweaks
    gnomeExtensions.appindicator
  ];
}
