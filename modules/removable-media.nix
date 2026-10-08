{
  config,
  lib,
  pkgs,
  ...
}:

# ▸ Включается если auto.removableMedia = true
#   Ставит gvfs (gvfsd + MTP/GPhoto2/SMB/AFC-бэкенды), libmtp и
#   libgphoto2, чтобы файловые менеджеры (Nautilus, Dolphin, Thunar,
#   PCManFM) видели подключённые камеры/телефоны как MTP/PTP-устройства.
#
#   gvfs-бэкенды активируются по D-Bus в пользовательской сессии
#   (autostart .desktop-файлы из пакета gvfs), когда устройство
#   появляется в udev.
#   - libmtp — низкоуровневая библиотека MTP; даёт CLI mtp-detect
#              и mtp-files для диагностики и ручного доступа.
#   - libgphoto2 — низкоуровневая библиотека PTP; даёт CLI gphoto2
#                  для tethered capture. darktable/rawtherapee тоже
#                  ходят через неё.
#
#   services.udev.packages копирует <pkg>/lib/udev/rules.d/*.rules
#   в /etc/udev/rules.d/ на активации системы. Без этого 40-libgphoto2.rules
#   с матчем ID_USB_INTERFACES=*:060101:* лежит в /run/current-system/sw
#   нетронутым — udev его не загружает, ID_GPHOTO2=1 на камеру не
#   выставляется, gvfs-gphoto2-volume-monitor её не видит. libmtp-rules
#   попадают в /etc/udev/rules.d/ отдельным NixOS-модулем, поэтому
#   для него services.udev.packages не нужен.

lib.mkIf config.auto.removableMedia {
  environment.systemPackages = with pkgs; [
    gvfs
    libmtp
    libgphoto2
    gphoto2
  ];

  services.udev.packages = [ pkgs.libgphoto2 ];
}