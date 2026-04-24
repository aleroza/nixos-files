{ config, lib, pkgs, ... }:

{
  home.sessionVariables = {
    EDITOR = "code";
    VISUAL = "code";
  };
  programs.bash.initExtra = ''
    export HISTCONTROL=ignoredups:erasedups
    export HISTIGNORE=" *"
    export HISTSIZE=10000
    export HISTFILESIZE=20000
  '';
}
