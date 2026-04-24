# User groups module
{ config, lib, ... }:

{
  # User groups - NixOS already has users.groups defined
  config.users.groups = {
    i2c = { };
    openclaw = { };
    plocate = { };
  };
}