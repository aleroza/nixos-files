{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.auto.dev.networkCapture;
in

# ▸ Включается если auto.dev.networkCapture.enable = true
#   Ставит wireshark-cli (с setcap'нутым dumpcap), wireshark (GUI),
#   tcpdump (с setcap'нутым wrapper), и добавляет пользователей
#   из auto.dev.networkCapture.users в группу wireshark
#
#   dumpcap — захватывает пакеты (вызывается из tshark/wireshark)
#   tcpdump — отдельный бинарник; setcap'нутый wrapper позволяет
#             членам группы wireshark запускать его напрямую
#             без sudo для дампа всего трафика на интерфейсах

lib.mkIf cfg.enable {
  programs.wireshark.enable = true;

  environment.systemPackages = with pkgs; [
    tcpdump
    wireshark
  ];

  security.wrappers.tcpdump = {
    source = "${pkgs.tcpdump}/bin/tcpdump";
    owner = "root";
    group = "wireshark";
    capabilities = "cap_net_raw,cap_net_admin+eip";
    permissions = "u+rx,g+x";
  };

  users.users = lib.genAttrs cfg.users (name: {
    extraGroups = [ "wireshark" ];
  });
}
