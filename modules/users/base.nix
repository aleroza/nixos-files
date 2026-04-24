# Users base module
{ config, lib, ... }:

{
  options = { };

  config = {
    users.users = {
      aleroza = {
        # hashedPasswordFile = ./secrets/aleroza-password; # requires secrets dir
        isNormalUser = true;
        extraGroups = [
          "wheel"
          "docker"
          "i2c"
          "plocate"
        ];
      };
      openclaw = {
        isNormalUser = true;
        home = "/home/openclaw";
        createHome = true;
        group = "openclaw";
        extraGroups = [ "docker" ];
        linger = true;
        description = "OpenClaw service account";
      };
    };
  };
}