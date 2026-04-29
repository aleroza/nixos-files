{ config, pkgs, ... }:

{
  home = {
    stateVersion = "25.11";

    packages = with pkgs; [
      htop
      ripgrep
      fd
    ];

    sessionVariables = {
      EDITOR = "vim";
    };
  };

  programs = {
    bash.enable = true;
    git.enable = true;
  };
}
