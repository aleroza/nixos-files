{ config, pkgs, lib, ... }:

# ▸ Home-manager config для пользователя openclaw
#   Портабельный — не зависит от NixOS-специфичных опций

{
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
    nodejs_24
    python3
    gh
    nixfmt
  ];

  # ── Активация: npm global packages ─────────────────────────────
  home.activation = {
    ensureOpenclawDepsPackageJson = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      npm install -g openclaw@latest @tobilu/qmd
    '';
  };

  # ── Сессионные переменные ──────────────────────────────────────
  home.sessionVariables = {
    PNPM_HOME = "$HOME/.local/share/pnpm";
    NPM_PACKAGES = "$HOME/.npm-global";
    XDG_RUNTIME_DIR = "/run/user/$(id -u)";
    DBUS_SESSION_BUS_ADDRESS = "unix:path=$XDG_RUNTIME_DIR/bus";
  };

  # ── Bash initExtras (PATH setup) ───────────────────────────────
  programs.bash.enable = true;
  programs.bash.initExtra = ''
    export PNPM_HOME="$HOME/.local/share/pnpm"
    case ":$PATH:" in
      *":$PNPM_HOME:"*) ;;
      *) export PATH="$PNPM_HOME:$PATH" ;;
    esac

    export NPM_CONFIG_PREFIX="$HOME/.npm-global"
    export NPM_PACKAGES="$HOME/.npm-global"
    mkdir -p "$NPM_PACKAGES/bin" "$NPM_PACKAGES/lib" 2>/dev/null || true
    case ":$PATH:" in
      *":$NPM_PACKAGES/bin:"*) ;;
      *) export PATH="$NPM_PACKAGES/bin:$PATH" ;;
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
