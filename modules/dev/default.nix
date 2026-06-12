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
  imports = [
    ./nodejs.nix
    ./python.nix
  ];

  config = lib.mkIf cfg.enable {
    programs.nix-ld.enable = true;
    environment.systemPackages = with pkgs; [
      git
      vim
      bind

      tldr
      p7zip
    ];
  };
}
