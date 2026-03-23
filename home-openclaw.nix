# home-openclaw.nix
{
  config,
  pkgs,
  ...
}:
{
  home.username = "openclaw";
  home.homeDirectory = "/home/openclaw";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  # Install OpenClaw package for the user (config managed manually)
  home.packages = [ pkgs.openclaw ];

  # OpenClaw user service - runs the gateway with existing config
  systemd.user.services.openclaw-gateway = {
    Unit = {
      Description = "OpenClaw Gateway";
      After = [ "network.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.openclaw}/bin/openclaw-gateway";
      Restart = "on-failure";
      RestartSec = "10";
      # Use existing config file location
      Environment = [
        "OPENCLAW_CONFIG=/home/openclaw/.openclaw/openclaw.json"
        "OPENCLAW_BUNDLED_PLUGINS_DIR=/nix/store/i01qh39d4cczsrmvid5h18jgzq1n1gn0-openclaw-gateway-unstable-823a09ac/lib/openclaw/extensions"
      ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
