{
  config,
  lib,
  auto,
  ...
}:

{
  config = lib.mkIf auto.dev.nodejs {
    home.sessionVariables = {
      NPM_CACHE = "$HOME/.cache/npm";
    };

    programs.bash.initExtra = ''
      case ":$PATH:" in
        *":$NPM_CACHE:"*) ;;
        *) export PATH="$NPM_CACHE/global/bin:$PATH" ;;
      esac
    '';
  };
}
