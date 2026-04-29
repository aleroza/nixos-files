# ▸ Хелпер для проверки включённых фич из config.auto
#
#   auto = {
#     development = true;
#     gaming      = true;
#   };
#
#   lib.mkIfAuto "development" {
#     ...
#   };

{ lib, config, ... }:

let
  hasFeature = feature: lib.attrByPath (lib.splitString "." feature) false config.auto;
in {
  inherit hasFeature;
}
