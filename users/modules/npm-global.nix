{ config, lib, auto, ... }:

{
  config = lib.mkIf auto.dev.nodejs {
    home.sessionVariables = {
      NPM_CACHE = "$HOME/.cache/npm";
    };

    programs.bash.initExtra = ''
      export NPM_GLOBAL_BIN="$HOME/.npm-global/bin"
      case ":$PATH:" in
        *":$NPM_GLOBAL_BIN:"*) ;;
        *) export PATH="$NPM_GLOBAL_BIN:$PATH" ;;
      esac
    '';
  };
}
