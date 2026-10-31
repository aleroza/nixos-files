# OpenChamber — desktop GUI for OpenCode sessions (Electron app).
#
# Why a module: OpenChamber ships no nixpkgs package — only an
# upstream AppImage per release. We pin a specific release asset from
# openchamber/openchamber and wrap it with `appimageTools.wrapType2`,
# exactly like FlClash (see modules/flclash.nix): the AppImage is
# extracted, the resulting squashfs-root is wrapped in an FHS-env and
# a plain `openchamber` binary lands in $out/bin. Once in
# `environment.systemPackages`, .desktop entries can call
# `openchamber` directly without any path arithmetic.
#
# Bump the version + hash together:
#   1. fetch the new AppImage from
#      https://github.com/openchamber/openchamber/releases
#   2. `nix store prefetch-file --json <url>` to get the new
#      sha256 (and storePath stays out of /home/aleroza/nixos-config).
#   3. update `version` and `src.sha256` below.
#
# Note on `--no-sandbox`: upstream's own .desktop file launches the
# app with `--no-sandbox` (Electron's setuid sandbox helper is not
# usable inside the FHS-env), so the desktop entry below does the same.

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.auto.openchamber;

  version = "2.5.3";

  src = pkgs.fetchurl {
    url = "https://github.com/openchamber/openchamber/releases/download/v${version}/OpenChamber-${version}-linux-x86_64.AppImage";
    sha256 = "sha256-wDSorfUq9bxQ+Z3OmU1wFZdBB00MQmb0VrcPWbyB3jI=";
  };

  # wrapType2 — the correct entry-point for Type 2 AppImages
  # (`xxd -l 16 <AppImage>` shows `AI\x02` at offset 8). It extracts
  # the AppImage and wraps the unpacked directory in an FHS-env.
  openchamber = pkgs.appimageTools.wrapType2 {
    inherit src;
    pname = "openchamber";
    inherit version;
    # The AppImage ships its own Electron runtime; the FHS-env only
    # needs the shared libraries Electron dlopen()s at runtime
    # (gtk3 for the dialogs, nss/nspr for the network stack, ...).
    extraPkgs = pkgs: with pkgs; [
      gtk3
      nss
      nspr
      alsa-lib
      at-spi2-atk
      at-spi2-core
      libdrm
      libgbm
      libxkbcommon
    ];
  };

  # The AppImage's .desktop file and icon are dropped by the FHS-env
  # wrapper — unpack the AppImage a second time to lift the icon into
  # the hicolor theme, so the app-menu entry shows a real icon.
  unpacked = pkgs.appimageTools.extract {
    pname = "openchamber";
    inherit version;
    inherit src;
  };

  icon = pkgs.runCommand "openchamber-icon" { } ''
    mkdir -p "$out/share/icons/hicolor/512x512/apps"
    cp ${unpacked}/openchamber.png "$out/share/icons/hicolor/512x512/apps/openchamber.png"
  '';

  desktop = pkgs.makeDesktopItem {
    name = "openchamber";
    desktopName = "OpenChamber";
    comment = "Desktop GUI for OpenCode sessions";
    exec = "${openchamber}/bin/openchamber --no-sandbox %U";
    icon = "openchamber";
    categories = [ "Development" ];
    keywords = [ "OpenChamber" "OpenCode" "AI" "Agent" ];
    startupWMClass = "openchamber";
  };
in
{
  # `auto.openchamber.enable` is declared in modules/auto.nix (single
  # source of truth for `auto.*` options, per the convention in
  # AGENTS.md).
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      openchamber
      icon
      desktop
    ];
  };
}
