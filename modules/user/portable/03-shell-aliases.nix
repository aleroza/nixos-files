{ config, lib, pkgs, ... }:

{
  programs.bash.shellAliases = {
    gs = "git status";
    ga = "git add";
    gc = "git commit";
    gp = "git push";
    gl = "git log --oneline -10";
    gd = "git diff";
    gco = "git checkout";
    gb = "git branch";
    gst = "git status";
  };
}
