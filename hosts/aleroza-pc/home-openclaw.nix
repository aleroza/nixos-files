{ inputs ? { }, lib ? null, pkgs ? null, config ? null, ... }:

{
  home.username = "openclaw";
  home.homeDirectory = "/home/openclaw";
  home.stateVersion = "25.11";

  imports = [
    ../../modules/user/portable/04-defaults.nix
  ];

  programs.git = {
    enable = true;
    settings = {
      user.name = "openclaw";
      user.email = "openclaw@example.com";
    };
  };

  home.packages = with pkgs; [
    nodejs-slim_24
    pnpm
    gh
    nixfmt
  ];

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
