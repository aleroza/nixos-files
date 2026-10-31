# FlClash — proxy GUI (mihomo / Clash.Meta front-end).
#
# Why a module: nixpkgs removed `flclash` ("low number of users and lack
# of maintenance"). We pin a specific upstream AppImage from
# chen08209/FlClash releases and use `appimageTools.wrapType2`, which
# extracts the AppImage and wraps the resulting squashfs-root in an
# FHS-env so a `flclash` binary lands in $out/bin. Once in
# `environment.systemPackages`, autostart .desktop entries can call
# `flclash` directly without any path arithmetic.
#
# Bump the version + hash together:
#   1. fetch the new AppImage from
#      https://github.com/chen08209/FlClash/releases
#   2. `nix store prefetch-file --json <url>` to get the new
#      sha256 (and storePath stays out of /home/aleroza/nixos-config).
#   3. update `version` and `src.sha256` below.

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.auto.flclash;

  version = "0.9.2";

  src = pkgs.fetchurl {
    url = "https://github.com/chen08209/FlClash/releases/download/v${version}/FlClash-${version}-linux-amd64.AppImage";
    sha256 = "sha256-/bIUDj83IklL1YAIXR5t3z+LqiHGvg1H3iCmY3xkcvw=";
  };

  # wrapType2 — это правильный entry-point для Type 2 AppImage
  # (`file FlClash-*.AppImage` показывает `AI\x02`). Внутри:
  #   1. extract       — распаковывает AppImage через appimage-exec.sh
  #   2. wrapAppImage  — собирает FHS-env вокруг распакованной
  #                      директории и запускает `appimage-exec.sh -w <dir>`.
  #
  # Если использовать только `wrapAppImage` (без extract), wrapper
  # получает `-w <AppImage-файл>` вместо `-w <распакованная-папка>` и
  # падает с `Usage: appimage-run ...` / пустой realpath.
  flclash = pkgs.appimageTools.wrapType2 {
    inherit src;
    pname = "flclash";
    inherit version;
    # FlClash is GTK/libhandy/Electron-based and depends on libraries
    # not in appimageTools' default FHS list (libepoxy for EGL/GLX
    # dispatch, libsoup3 for GTK4 networking, etc.). extraPkgs adds
    # them to the FHS-env so /squashfs-root/FlClash can dlopen them.
    extraPkgs = pkgs: with pkgs; [
      libepoxy
      gtk3
      at-spi2-atk
      at-spi2-core
      libsoup_3
      librsvg
    ];
  };

  # `appimageTools.wrapType2` ships only the FHS-env wrapper — the
  # .desktop file and the icon that live inside the AppImage are
  # dropped on the floor. Unpack the AppImage a second time to lift
  # the icon into the hicolor theme, so the app-menu entry shows a
  # real icon instead of the generic "missing icon" placeholder.
  unpacked = pkgs.appimageTools.extract {
    pname = "flclash";
    inherit version;
    inherit src;
  };

  icon = pkgs.runCommand "flclash-icon" { } ''
    mkdir -p "$out/share/icons/hicolor/512x512/apps"
    cp ${unpacked}/FlClash.png "$out/share/icons/hicolor/512x512/apps/flclash.png"
  '';

  desktop = pkgs.makeDesktopItem {
    name = "flclash";
    desktopName = "FlClash";
    comment = "Proxy GUI (mihomo / Clash.Meta front-end)";
    exec = "${flclash}/bin/flclash %U";
    icon = "flclash";
    categories = [ "Network" ];
    keywords = [ "FlClash" "Clash" "ClashMeta" "Proxy" ];
  };
in
{
  # `auto.flclash.enable` is declared in modules/auto.nix (single source
  # of truth for `auto.*` options, per the convention in AGENTS.md).
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      flclash
      icon
      desktop
    ];
  };
}
