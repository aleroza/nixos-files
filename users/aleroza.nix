{
  config,
  pkgs,
  lib,
  nix-flatpak,
  nixpkgs-unstable,
  ...
}:

# ▸ Home-manager config для пользователя aleroza
#   Портабельный — не зависит от NixOS-специфичных опций,
#   может использоваться на других дистрибутивах через standalone HM

{
  imports = [
    nix-flatpak.homeManagerModules.nix-flatpak
    ./modules/npm-global.nix
  ];

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

  # ── Пакеты (только для aleroza) ─────────────────────────────────
  home.packages = with pkgs; [
    google-chrome
    nixfmt
  ];

  # Uses nix-flatpak for declarative flatpak management
  # https://github.com/gmodena/nix-flatpak
  services.flatpak = {
    enable = true;
    packages = [
      "com.usebottles.bottles"
    ];
    overrides = {
      "com.usebottles.bottles".Context = {
        filesystem = [ "xdg-data/Steam" ];
        share = [ "network" ];
      };
    };
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

  # ── FlClash autostart ───────────────────────────────────────────
  xdg.configFile."autostart/FlClash.desktop" = {
    force = true;
    text = ''
      [Desktop Entry]
      Type=Application
      Name=FlClash
      Comment=FlClash startup script
      Exec=${nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.flclash}/app/flclash/FlClash
      StartupNotify=false
      Terminal=false
    '';
  };

  # ── Deluge daemon (per-user systemd unit) ────────────────────────
  # Runs as a background daemon the user owns. deluge-gtk / deluge-console
  # connect to 127.0.0.1:58846 with the `localclient` account defined in
  # ~/.config/deluge/auth. Requires `linger = true` on the user so the
  # unit keeps running after the last graphical session ends.
  systemd.user.services.deluged = {
    Unit = {
      Description = "Deluge BitTorrent Daemon";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = "${pkgs.deluge}/bin/deluged -d";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install = { WantedBy = [ "default.target" ]; };
  };
}
