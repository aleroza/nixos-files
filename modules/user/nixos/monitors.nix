{ config, lib, ... }:

{
  # monitors.xml for GNOME dual-display setup
  # Always created; GNOME will use it automatically on login
  home.file.".config/monitors.xml" = {
    force = true;
    text = builtins.readFile ./monitors.xml;
  };
}
