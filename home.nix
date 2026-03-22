{ config, pkgs, ... }:

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
        # `gnome-extensions list` for a list
        enabled-extensions = [
          "clipboard-indicator@tudmotu.com"
          "display-brightness-ddcutil@themightydeity.github.com"
        ];
      };
      "org/gnome/desktop/interface".show-battery-percentage = true;
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
