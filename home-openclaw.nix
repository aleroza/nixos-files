# home-openclaw.nix
{
  config,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    inputs.nix-openclaw.homeManagerModules.openclaw
  ];

  home.username = "openclaw";
  home.homeDirectory = "/home/openclaw";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  programs.openclaw = {
    enable = true;

    # Keep secrets out of the Nix store; the upstream README says the gateway
    # token and provider keys should come from env/files, not hardcoded values.
    # gateway.auth.token = "...";

    config = {
      gateway = {
        mode = "local";
      };

      # channels.telegram = {
      #   tokenFile = "/run/agenix/telegram-bot-token";
      #   allowFrom = [ 12345678 ];
      # };
    };

    # Use the current upstream option names if you add tools/plugins later:
    # bundledPlugins = { summarize.enable = true; };
    # customPlugins = [ { source = "github:owner/repo"; } ];
  };
}
