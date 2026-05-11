{
  config,
  lib,
  pkgs,
  ...
}:

# Uses nix-flatpak for declarative flatpak management
# https://github.com/gmodena/nix-flatpak

lib.mkIf config.auto.flatpak {

  services.flatpak = {
    enable = true;

    restartOnFailure = {
      enable = true;
      restartDelay = "60s";
      exponentialBackoff = {
        enable = true;
        steps = 10;
        maxDelay = "1h";
      };
    };
  };

  # System-level flatpak apps
  services.flatpak.packages = [
    "com.github.tchx84.Flatseal"
  ];
}
