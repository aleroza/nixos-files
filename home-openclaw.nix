{ config, pkgs, ... }:

{
  home.username = "openclaw";
  home.homeDirectory = "/home/openclaw";

  # Управление конфигами программ (dotfiles)
  programs.git = {
    enable = true;
    settings = {
      user.name = "openclaw";
      user.email = "openclaw@example.com";
    };
  };

  # Это важно для совместимости
  home.stateVersion = "25.11";

  # Автоматическое управление установкой через home-manager
  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    nodejs-slim_24
    pnpm
    nixfmt
    anytype
  ];

  # # Включение openclaw-gateway для запуска при старте системы
  # # не работает
  # systemd.user.services.openclaw-gateway = {
  #   enable = true;
  #   wantedBy = [ "default.target" ];
  # };

  # pnpm setup
  home.sessionVariables = {
    PNPM_HOME = "$HOME/.local/share/pnpm";
    XDG_RUNTIME_DIR = "/run/user/$(id -u)";
    DBUS_SESSION_BUS_ADDRESS = "unix:path=$XDG_RUNTIME_DIR/bus";
  };

  programs.bash.enable = true;
  programs.bash.initExtra = ''
    export PNPM_HOME="$HOME/.local/share/pnpm"
    case ":$PATH:" in
      *":$PNPM_HOME:"*) ;;
      *) export PATH="$PNPM_HOME:$PATH" ;;
    esac
  '';
}
