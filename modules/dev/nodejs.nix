{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.auto.dev;
in

{
  config = lib.mkIf cfg.nodejs {
    environment.systemPackages = with pkgs; [
      nodejs
    ];
  };
}