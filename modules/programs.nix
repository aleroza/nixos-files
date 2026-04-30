{ config, lib, pkgs, ... }:

let
  cfg = config.auto;
in

lib.mkIf cfg.programs.enable {

  programs.firefox.enable = true;

}
