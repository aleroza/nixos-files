{ config, lib, pkgs, ... }:

let
  cfg = config.auto.docker;
in

# ▸ Включается если auto.docker.enable = true
#   Помимо демона, добавляет пользователей из auto.docker.users в группу docker

lib.mkIf cfg.enable {

  virtualisation.docker.enable = true;
  virtualisation.docker.autoPrune.enable = true;
  virtualisation.docker.autoPrune.dates = [ "monthly" ];

  users.users = lib.genAttrs cfg.users (name: {
    extraGroups = [ "docker" ];
  });
}
