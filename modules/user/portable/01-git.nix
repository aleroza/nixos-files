{ config, lib, pkgs, ... }:

{
  programs.git = {
    enable = true;
    settings = {
      user.name = "aleroza";
      user.email = "aleroza1910@gmail.com";
    };
  };
}
