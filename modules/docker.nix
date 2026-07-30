{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.auto.docker;
  loginCfg = cfg.login;
in
{
  options.auto.docker.login = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        user = lib.mkOption {
          type = lib.types.str;
          description = "System user to log in as. Also becomes the owner of ~/.docker/config.json.";
        };
        registry = lib.mkOption {
          type = lib.types.str;
          default = "docker.io";
          description = "Registry to authenticate against.";
        };
        username = lib.mkOption {
          type = lib.types.str;
          description = "Docker registry username.";
        };
        passwordFile = lib.mkOption {
          type = lib.types.path;
          description = "Path to a file containing the Docker registry password/access-token.";
        };
      };
    });
    default = [ ];
    description = ''
      Per-user Docker registry logins. Each entry produces a systemd-user
      service that runs `docker login` on user session start (after the
      docker socket is up) and writes ~/.docker/config.json for that user,
      so `docker pull/push` works without an interactive login.
    '';
  };

  config = lib.mkMerge [

    (lib.mkIf cfg.enable {
      virtualisation.docker.enable = true;
      virtualisation.docker.autoPrune.enable = true;
      virtualisation.docker.autoPrune.dates = "monthly";

      users.users = lib.genAttrs cfg.users (name: {
        extraGroups = [ "docker" ];
      });
    })

    (lib.mkIf (cfg.enable && loginCfg != [ ]) {
      systemd.user.services = lib.listToAttrs (map (entry: {
        name = "docker-login-${entry.user}";
        value = {
          description = "Login ${entry.user} to ${entry.registry}";
          wantedBy = [ "default.target" ];
          after = [ "docker.socket" ];
          wants = [ "docker.socket" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            # Запускаем от имени пользователя, чтобы ~/.docker/config.json
            # принадлежал ему (systemd-user unit по умолчанию запускается
            # под владельцем юнита — поэтому блок ниже задаёт User=).
            User = entry.user;
            ExecStart = ''
              mkdir -p %h/.docker
              ${pkgs.docker-client}/bin/docker login \
                --username '${lib.escapeShellArg entry.username}' \
                --password-stdin \
                ${lib.escapeShellArg entry.registry} \
                < ${lib.escapeShellArg (toString entry.passwordFile)}
            '';
          };
        };
      }) loginCfg);
    })
  ];
}
