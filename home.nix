{
  config,
  pkgs,
  lib,
  ...
}:

{
  home.username = "aleroza";
  home.homeDirectory = "/home/aleroza";

  # Похоже не требуется
  # home.sessionVariables = {
  #   XDG_DATA_DIRS = "@{XDG_DATA_DIRS}:/var/lib/flatpak/exports/share:$HOME/.local/share/flatpak/exports/share";
  # };

  # Bash history settings
  programs.bash.initExtra = ''
    # History settings
    export HISTCONTROL=ignoredups:erasedups
    export HISTIGNORE=" *"
    export HISTSIZE=10000
    export HISTFILESIZE=20000
  '';

  # Управление конфигами программ (dotfiles)
  programs.git = {
    enable = true;
    settings = {
      user.name = "aleroza";
      user.email = "aleroza1910@gmail.com";
    };
  };

  # Git aliases через shellAliases
  programs.bash.shellAliases = {
    gs = "git status";
    ga = "git add";
    gc = "git commit";
    gp = "git push";
    gl = "git log --oneline -10";
    gd = "git diff";
    gco = "git checkout";
    gb = "git branch";
    gst = "git status";
  };

  # Это важно для совместимости
  home.stateVersion = "25.11";

  # Автоматическое управление установкой через home-manager
  programs.home-manager.enable = true;

  home.activation = {
    setupFlatpak = ''
      ${pkgs.flatpak}/bin/flatpak --user remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    '';
    installBottles = lib.hm.dag.entryAfter [ "setupFlatpak" ] ''
      ${pkgs.flatpak}/bin/flatpak --user install --noninteractive flathub com.usebottles.bottles
      ${pkgs.flatpak}/bin/flatpak override --user com.usebottles.bottles --filesystem=xdg-data/Steam --share=network
    '';
  };

  home.packages = with pkgs; [
    google-chrome
    nixfmt

    gnomeExtensions.clipboard-indicator
    gnomeExtensions.brightness-control-using-ddcutil
  ];

  dconf = {
    enable = true;
    settings = {
      # Custom shortcuts
      "org/gnome/settings-daemon/plugins/media-keys" = {
        custom-keybindings = [
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/open-console/"
          # "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
        ];
      };
      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/open-console" = {
        name = "Open Console";
        command = "kgx";
        binding = "<Control><Alt>t";
      };
      # "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1" = {
      #   name = "111";
      #   command = "echo \"1\"";
      #   binding = "<Control><Alt>1";
      # };

      # Apps pinned to Dash-panel
      "org/gnome/shell" = {
        favorite-apps = [
          "google-chrome.desktop"
          "org.telegram.desktop.desktop"
          "code.desktop"
          "org.gnome.Console.desktop"
          "org.gnome.Nautilus.desktop"
        ];

        # Enabled extensions (user `gnome-extensions list` for full extension name)
        enabled-extensions = [
          "appindicatorsupport@rgcjonas.gmail.com"
          "clipboard-indicator@tudmotu.com"
          "display-brightness-ddcutil@themightydeity.github.com"
        ];
      };

      # Show battery percentage in the top bar
      "org/gnome/desktop/interface".show-battery-percentage = true;

      # Keyboard layout switching command
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

      # Monitor brightness control extension
      "org/gnome/shell/extensions/display-brightness-ddcutil" = {
        show-display-name = true; # Show name of monitor
        button-location = 1; # Show brightness control in the main menu
      };
      # Clipboard history extension
      "org/gnome/shell/extensions/clipboard-indicator" = {
        display-mode = 2; # Show clipboard content and icon
        topbar-preview-size = 15; # Preview size
      };

      "org/gnome/desktop/wm/preferences" = {
        button-layout = "appmenu:minimize,maximize,close";
        action-middle-click-titlebar = "minimize";
      };
    };
  };

  # App/links associations
  xdg.mimeApps.enable = true;
  xdg.configFile."mimeapps.list".force = true;
  xdg.mimeApps.defaultApplications = {
    "text/html" = "google-chrome.desktop";
    "x-scheme-handler/http" = "google-chrome.desktop";
    "x-scheme-handler/https" = "google-chrome.desktop";
    "x-scheme-handler/about" = "google-chrome.desktop";
    "x-scheme-handler/unknown" = "google-chrome.desktop";
  };

  # Default monitor layout
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
