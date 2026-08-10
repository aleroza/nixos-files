# Home-manager модуль для Aphrodite-интеграции Hermes Agent.
#
# Что делает:
#   1. Кладёт готовый Hermes-профиль `aphrodite` в
#      ~/.hermes/profiles/aphrodite/config.yaml. Запуск:
#        hermes --profile aphrodite
#      идёт через прокси 127.0.0.1:9798 → MiniMax.
#   2. Создаёт ~/.hermes/aphrodite/ с правами aleroza:users
#      (для override конфига и CCR store при желании).
#   3. Задаёт `APHRODITE_CONFIG_PATH` для пользовательских сессий
#      hermes — на тот случай, если пользователь захочет запустить
#      собственный экземпляр прокси руками.
#
# Сам systemd-юнит лежит в modules/services/aphrodite.nix и
# стартует на хосте независимо от home-manager. Здесь только
# пользовательские артефакты.

{ config, lib, auto, ... }:

let
  cfg = auto.aphrodite;
in
{
  config = lib.mkIf (cfg.enable or false) {

    home.sessionVariables = {
      APHRODITE_CONFIG_PATH = "$HOME/.hermes/aphrodite/aphrodite.toml";
    };

    # Директория для пользовательских override-конфигов и CCR store.
    home.file.".hermes/aphrodite/.keep" = {
      text = "";
    };

    # Hermes-профиль для запуска через Aphrodite-прокси.
    # Базовый провайдер `aphrodite-token` смотрит на :9798 (default
    # `services.aphrodite.listen` в NixOS-модуле). Если прокси
    # выключен — профиль всё равно загружается, но отвечает 502
    # от nginx (или connection refused от curl). Лучше запускать
    # профиль только когда auto.aphrodite.enable = true.
    home.file.".hermes/profiles/aphrodite/config.yaml".force = true;
    home.file.".hermes/profiles/aphrodite/config.yaml".text = ''
      # Hermes-профиль для работы через Aphrodite CCR-прокси.
      # Скопировано из PlayForm/Aphrodite/profiles/example/config.yaml
      # и адаптировано под наш стек (MiniMax как upstream, M3 +
      # M2.7 для sub-агентов).

      agent:
        max_turns: 90
        disabled_toolsets: []
        tool_use_enforcement: auto

      model:
        default: minimax/MiniMax-M3
        provider: aphrodite-token

      providers:
        aphrodite-token:
          provider: openai
          base_url: http://127.0.0.1:9798
          api_key_env: APHRODITE_API_KEY
          max_tokens: 65536
        # Direct fallback если прокси выключен — Hermes пойдёт
        # на прямую с тем же ключом.
        minimax:
          provider: openai
          base_url: https://api.minimax.io/v1
          api_key_env: APHRODITE_API_KEY
          max_tokens: 65536

      compression:
        enabled: false
      context:
        engine: aphrodite

      toolsets:
        - hermes-cli
        - aphrodite

      terminal:
        env_passthrough:
          - APHRODITE_API_KEY
          - PATH
          - HOME

      delegation:
        model: minimax/MiniMax-M2.7
    '';
  };
}