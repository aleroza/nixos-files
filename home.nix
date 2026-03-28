{
  config,
  pkgs,
  lib,
  ...
}:

{
  home.username = "aleroza";
  home.homeDirectory = "/home/aleroza";

  # Управление конфигами программ (dotfiles)
  programs.git = {
    enable = true;
    settings = {
      user.name = "aleroza";
      user.email = "aleroza1910@gmail.com";
    };
  };

  # Это важно для совместимости
  home.stateVersion = "25.11";

  # Автоматическое управление установкой через home-manager
  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    google-chrome
    nixfmt

    gnomeExtensions.clipboard-indicator
    gnomeExtensions.brightness-control-using-ddcutil
  ];
  dconf = {
    enable = true;
    settings = {
      "org/gnome/shell" = {
        favorite-apps = [
          "google-chrome.desktop"
          "org.telegram.desktop.desktop"
          "code.desktop"
          "org.gnome.Console.desktop"
          "org.gnome.Nautilus.desktop"
        ];

        # `gnome-extensions list` for a list
        enabled-extensions = [
          "appindicatorsupport@rgcjonas.gmail.com"
          "clipboard-indicator@tudmotu.com"
          "display-brightness-ddcutil@themightydeity.github.com"
        ];
      };
      "org/gnome/desktop/interface".show-battery-percentage = true;

      # Настройки переключения раскладки (Left Shift + Left Alt)
      "org/gnome/desktop/input-sources" = {
        xkb-options = [ "grp:alt_shift_toggle" ];
      };

      # Настройки питания и экрана
      "org/gnome/settings-daemon/plugins/power" = {
        # Отключение действий при бездействии при питании от сети
        sleep-inactive-ac-type = "nothing";
        sleep-inactive-ac-timeout = 0;
        # Время до действия при питании от батареи -- гибернация через 15 минут (900 сек)
        sleep-inactive-battery-type = "hibernate";
        sleep-inactive-battery-timeout = 900;
      };

      # Время бездействия до активации хранителя через 12 минут (720 сек)
      "org/gnome/desktop/session" = {
        idle-delay = lib.hm.gvariant.mkUint32 720;
      };

      # Настройки хранителя экрана и блокировки
      "org/gnome/screensaver" = {
        # Включить блокировку при активации хранителя экрана
        lock-enabled = true;
        # Задержка блокировки после активации хранителя - 0 секунд (сразу)
        lock-delay = 0;
      };

      "org/gnome/shell/extensions/display-brightness-ddcutil" = {
        show-display-name = true;
        button-location = 1;
      };
    };
  };

  xdg.mimeApps.enable = true;
  xdg.configFile."mimeapps.list".force = true;
  xdg.mimeApps.defaultApplications = {
    "text/html" = "google-chrome.desktop";
    "x-scheme-handler/http" = "google-chrome.desktop";
    "x-scheme-handler/https" = "google-chrome.desktop";
    "x-scheme-handler/about" = "google-chrome.desktop";
    "x-scheme-handler/unknown" = "google-chrome.desktop";
  };

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

  xdg.configFile."autostart/flclash.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Exec=${pkgs.flclash}/bin/FlClash
    Hidden=false
    NoDisplay=false
    X-GNOME-Autostart-enabled=true
    Name=FlClash
    Comment=Start FlClash on login
  '';
}
