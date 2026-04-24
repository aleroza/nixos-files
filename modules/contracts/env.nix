{ lib, ... }:
{
  # Env vars used by both NixOS system and home-manager
  environment.sessionVariables = {
    EDITOR = "code";
  };
}