{ config, lib, pkgs, ... }:

# ▸ Включится только если auto.development = true

lib.mkIf config.auto.development {

  environment.systemPackages = with pkgs; [
    git
    vim
    gcc
    python3
    nodejs
  ];
}
