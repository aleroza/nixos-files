{
  config,
  pkgs,
  lib,
  auto,
  ...
}:

# ▸ Home-manager config для пользователя openclaw
#   Портабельный — не зависит от NixOS-специфичных опций

{
  imports = [
    ./modules/npm-global.nix
  ];

  home.username = "openclaw";
  home.homeDirectory = "/home/openclaw";

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  # ── Git ─────────────────────────────────────────────────────────
  programs.git = {
    enable = true;
    settings = {
      user.name = "openclaw";
      user.email = "openclaw@example.com";
    };
  };

  # ── Пакеты ──────────────────────────────────────────────────────
  home.packages = with pkgs; [
    nodejs
    python3
    gh
    nixfmt
  ];

  # ── Активация: npm global packages ─────────────────────────────
  home.activation = {
    ensureOpenclawDepsPackageJson = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # Create writable npm global directory if not exists
      mkdir -p "$HOME/.npm-global/lib"
      # Check if already installed
      if [ -d "$HOME/.npm-global/lib/node_modules/openclaw" ]; then
        echo "openclaw already installed, skipping"
      else
        # Ensure node is in PATH for npm preinstall scripts
        export PATH="${pkgs.nodejs}/bin:$PATH"
        # Run in background to avoid blocking activation
        nohup ${pkgs.nodejs}/bin/npm install -g --prefix "$HOME/.npm-global" openclaw@latest > /tmp/openclaw-install.log 2>&1 &
        echo "openclaw installation started in background, see /tmp/openclaw-install.log"
      fi
    '';
  };

  # ── Сессионные переменные ──────────────────────────────────────
  home.sessionVariables = {
    PNPM_HOME = "$HOME/.local/share/pnpm";
    XDG_RUNTIME_DIR = "/run/user/$(id -u)";
    DBUS_SESSION_BUS_ADDRESS = "unix:path=$XDG_RUNTIME_DIR/bus";
  };

  # ── systemd user dropin: proxy env for openclaw-gateway ────────
  xdg.configFile."systemd/user/openclaw-gateway.service.d/proxy.conf".text = ''
    [Service]
    Environment="http_proxy=http://127.0.0.1:7890"
    Environment="https_proxy=http://127.0.0.1:7890"
    Environment="all_proxy=http://127.0.0.1:7890"
    Environment="HTTP_PROXY=http://127.0.0.1:7890"
    Environment="HTTPS_PROXY=http://127.0.0.1:7890"
    Environment="ALL_PROXY=http://127.0.0.1:7890"
    Environment="NO_PROXY=127.0.0.1,localhost"
    Environment="no_proxy=127.0.0.1,localhost"
  '';

  # ── Bash initExtras (PATH setup) ───────────────────────────────
  programs.bash.enable = true;
  programs.bash.initExtra = ''
    export PNPM_HOME="$HOME/.local/share/pnpm"
    case ":$PATH:" in
      *":$PNPM_HOME:"*) ;;
      *) export PATH="$PNPM_HOME:$PATH" ;;
    esac

    __openclaw_ensure_package_json() {
      local deps_dir="$HOME/.openclaw/plugin-runtime-deps"
      if [ -d "$deps_dir" ]; then
        for dir in "$deps_dir"/openclaw-*/; do
          [ -f "$dir/package.json" ] || echo '{}' > "$dir/package.json" 2>/dev/null || true
        done
      fi
    }
    __openclaw_ensure_package_json
    unset -f __openclaw_ensure_package_json
  '';
}
