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
  config = lib.mkIf cfg.python {
    environment.systemPackages = with pkgs; [
      python3
    ];
  };
}