{ config, pkgs, lib, ... }:

# ▸ Home-manager config для пользователя aleroza
#   Портабельный — не зависит от NixOS-специфичных опций,
#   может использоваться на других дистрибутивах через standalone HM

{
  home.username = "aleroza";
  home.homeDirectory = "/home/aleroza";

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  # ── Bash / история ──────────────────────────────────────────────
  programs.bash.enable = true;
  programs.bash.initExtra = ''
    export HISTCONTROL=ignoredups:erasedups
    export HISTIGNORE=" *"
    export HISTSIZE=10000
    export HISTFILESIZE=20000
  '';

  # ── Git ─────────────────────────────────────────────────────────
  programs.git = {
    enable = true;
    settings = {
      user.name = "aleroza";
      user.email = "aleroza1910@gmail.com";
    };
  };

  programs.bash.shellAliases = {
    gs  = "git status";
    ga  = "git add";
    gc  = "git commit";
    gp  = "git push";
    gl  = "git log --oneline -10";
    gd  = "git diff";
    gco = "git checkout";
    gb  = "git branch";
    gst = "git status";
  };

  # ── Пакеты (только для aleroza) ─────────────────────────────────
  home.packages = with pkgs; [
    google-chrome
    nixfmt

    gnomeExtensions.clipboard-indicator
    gnomeExtensions.brightness-control-using-ddcutil
  ];

  # ── Flatpak (настройка, не требующая system-wide flatpak) ───────
  home.activation = {
    setupFlatpak = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.flatpak}/bin/flatpak --user remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    '';
    installBottles = lib.hm.dag.entryAfter [ "setupFlatpak" ] ''
      ${pkgs.flatpak}/bin/flatpak --user install --noninteractive flathub com.usebottles.bottles
      ${pkgs.flatpak}/bin/flatpak override --user com.usebottles.bottles --filesystem=xdg-data/Steam --share=network
    '';
  };

  # ── GNOME dconf настройки ───────────────────────────────────────
  dconf = {
    enable = true;
    settings = {
      "org/gnome/settings-daemon/plugins/media-keys" = {
        custom-keybindings = [
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/open-console/"
        ];
      };
      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/open-console" = {
        name = "Open Console";
        command = "kgx";
        binding = "<Control><Alt>t";
      };

      "org/gnome/shell" = {
        favorite-apps = [
          "google-chrome.desktop"
          "org.telegram.desktop.desktop"
          "code.desktop"
          "org.gnome.Console.desktop"
          "org.gnome.Nautilus.desktop"
        ];
        enabled-extensions = [
          "appindicatorsupport@rgcjonas.gmail.com"
          "clipboard-indicator@tudmotu.com"
          "display-brightness-ddcutil@themightydeity.github.com"
        ];
      };

      "org/gnome/desktop/interface".show-battery-percentage = true;

      "org/gnome/desktop/input-sources" = {
        xkb-options = [ "grp:alt_shift_toggle" ];
      };

      "org/gnome/settings-daemon/plugins/power" = {
        sleep-inactive-ac-type = "nothing";
        sleep-inactive-ac-timeout = 0;
        sleep-inactive-battery-type = "hibernate";
        sleep-inactive-battery-timeout = 900;
      };

      "org/gnome/desktop/session" = {
        idle-delay = lib.hm.gvariant.mkUint32 720;
      };

      "org/gnome/screensaver" = {
        lock-enabled = true;
        lock-delay = 0;
      };

      "org/gnome/shell/extensions/display-brightness-ddcutil" = {
        show-display-name = true;
        button-location = 1;
      };
      "org/gnome/shell/extensions/clipboard-indicator" = {
        display-mode = 2;
        topbar-preview-size = 15;
      };

      "org/gnome/desktop/wm/preferences" = {
        button-layout = "appmenu:minimize,maximize,close";
        action-middle-click-titlebar = "minimize";
      };
    };
  };

  # ── MIME-ассоциации ────────────────────────────────────────────
  xdg.mimeApps.enable = true;
  xdg.configFile."mimeapps.list".force = true;
  xdg.mimeApps.defaultApplications = {
    "text/html" = "google-chrome.desktop";
    "x-scheme-handler/http" = "google-chrome.desktop";
    "x-scheme-handler/https" = "google-chrome.desktop";
    "x-scheme-handler/about" = "google-chrome.desktop";
    "x-scheme-handler/unknown" = "google-chrome.desktop";
  };

  # ── Монитор (раскладка двух экранов) ────────────────────────────
  home.file.".config/monitors.xml" = {
    force = true;
    text = ''
      <monitors version="2">
        <configuration>
          <layoutmode>physical</layoutmode>
          <logicalmonitor>
            <x>320</x>
            <y>1440</y>
            <scale>1</scale>
            <monitor>
              <monitorspec>
                <connector>eDP-1</connector>
                <vendor>LGD</vendor>
                <product>0x05e5</product>
                <serial>0x00000000</serial>
              </monitorspec>
              <mode>
                <width>1920</width>
                <height>1080</height>
                <rate>59.977</rate>
              </mode>
            </monitor>
          </logicalmonitor>
          <logicalmonitor>
            <x>0</x>
            <y>0</y>
            <scale>1</scale>
            <primary>yes</primary>
            <monitor>
              <monitorspec>
                <connector>HDMI-1</connector>
                <vendor>XMI</vendor>
                <product>Mi monitor</product>
                <serial>5392700011291</serial>
              </monitorspec>
              <mode>
                <width>2560</width>
                <height>1440</height>
                <rate>59.951</rate>
              </mode>
            </monitor>
          </logicalmonitor>
        </configuration>
      </monitors>
    '';
  };

  # ── FlClash autostart ───────────────────────────────────────────
  xdg.configFile."autostart/FlClash.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=FlClash
    Comment=FlClash startup script
    Exec=${pkgs.flclash}/app/flclash/FlClash
    StartupNotify=false
    Terminal=false
  '';
}
