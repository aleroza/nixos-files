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
    ./uv.nix
  ];

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      git
      vim
      gnumake
      bind

      tldr
      p7zip
    ];

    programs.nix-ld.enable = true;
    programs.nix-ld.libraries = with pkgs; [
      gtk3
      glib
      libX11
    ];
  };
}
