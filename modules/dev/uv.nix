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
  config = lib.mkIf cfg.uv {
    environment.systemPackages = with pkgs; [
      uv
    ];
  };
}
