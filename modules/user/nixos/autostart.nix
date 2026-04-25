{ config, lib, pkgs, ... }:

{
  xdg.configFile."autostart/flclash.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Exec=${pkgs.flclash}/bin/FlClash
    Hidden=false
    NoDisplay=false
    X-GNOME-Autostart-enabled=true
    Name=FlClash
    Comment=Start FlClash on login
  '';
}
