{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  cfg = config.auto.nixRebuildMeta;

  nixRebuildMeta = pkgs.runCommand "nixos-rebuild-meta-wrapper" { } ''
    mkdir -p $out/bin
    cp ${self + "/scripts/nixos-rebuild-meta"} $out/bin/nixos-rebuild-meta
    chmod +x $out/bin/nixos-rebuild-meta
  '';
in
lib.mkIf cfg.enable {
  environment.shellAliases.nix-rebuild =
    "sudo -E ${nixRebuildMeta}/bin/nixos-rebuild-meta switch --flake .#${config.networking.hostName}";
}
