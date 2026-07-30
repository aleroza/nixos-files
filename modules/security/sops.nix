{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.auto.sops;
  sopsUsers = cfg.users;
in
lib.mkIf cfg.enable {

  # ▸ Активирует sops-nix. Хост-ключ лежит в /etc/sops/age/key.age
  #   (генерируется вручную через `nix-shell -p age --run age-keygen -o ...`,
  #   затем импортируется в .sops.yaml).
  #
  # ▸ Секреты объявляются в hosts/<host>/default.nix:
  #
  #     sops.secrets.aleroza-password = {
  #       sopsFile = ./secrets/aleroza-password.yaml;
  #       owner   = "aleroza";
  #       group   = "users";
  #       mode    = "0400";
  #     };
  #
  #   users.users.aleroza.hashedPasswordFile = "/run/secrets/aleroza-password";
  #
  # ▸ Ключи пользователей раскладываются в
  #   ~/.config/sops/age/keys.txt для тех, кто указан в auto.sops.users.
  sops = {
    age = {
      generateKey = false;
      sshKeyPaths = [ ];
      keyFile = "/etc/sops/age/key.age";
    };

    secrets = { };
  };

  environment.systemPackages = [ pkgs.sops pkgs.age ];

  # Создаём только директории с правильными правами.
  # Сам файл keys.txt НЕ создаём намеренно: age-keygen отказывается
  # перезаписывать существующий файл, и пользователь должен сгенерировать
  # ключ сам через `age-keygen -o ~/.config/sops/age/keys.txt`.
  systemd.tmpfiles.rules =
    lib.concatMap
      (u: [
        "d /home/${u}/.config/sops 0755 ${u} users - -"
        "d /home/${u}/.config/sops/age 0700 ${u} users - -"
      ])
      sopsUsers;

}