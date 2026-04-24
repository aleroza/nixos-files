{ lib, ... }:

{
  # Allow unfree packages (google-chrome, steam, etc.)
  nixpkgs.config.allowUnfree = true;
}
