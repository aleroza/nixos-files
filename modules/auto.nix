{ config, lib, ... }: let
  inherit (lib) types mkOption;
in {
  # ▸ auto — единая точка конфигурации хоста
  #
  #   auto = {
  #     # Feature toggles (бывшие tags)
  #     development = true;
  #     desktop     = true;
  #     gaming      = false;
  #
  #     # Модули со своей структурой
  #     docker.enable = true;
  #     docker.users  = [ "aleroza" "openclaw" ];
  #
  #     # Home-manager users
  #     hmUsers = [ "alex" ];
  #   };
  #
  # Модули проверяют config.auto.<feature> и сами гейтятся.
  # Всё в одном пространстве — никакой магии.

  options.auto = {
    # ▸ Feature toggles (плоские булевы, как были tags)

    development = mkOption {
      type = types.bool;
      default = false;
      description = "Enable development tools (git, compilers, IDEs).";
    };

    gaming = mkOption {
      type = types.bool;
      default = false;
      description = "Enable gaming tools (Steam, Lutris, MangoHud).";
    };

    desktop = mkOption {
      type = types.bool;
      default = false;
      description = "Enable desktop environment (KDE Plasma).";
    };

    server = mkOption {
      type = types.bool;
      default = false;
      description = "Enable server configuration.";
    };

    # ▸ Docker
    docker = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Docker daemon.";

      };

      users = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Users to add to the docker group.";
      };
    };

    # ▸ Home-manager users
    hmUsers = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Users configured via home-manager.";
    };
  };
}
