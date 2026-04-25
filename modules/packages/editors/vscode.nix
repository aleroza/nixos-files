# VSCode editor module
{ config, lib, pkgs, ... }:

{
  config = {
    environment.systemPackages = with pkgs; [ vscode ];
  };
}