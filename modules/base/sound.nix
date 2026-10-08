{
  config,
  lib,
  pkgs,
  ...
}:

# ▸ Software-amplify ALSA sinks via a NixOS-level WirePlumber config.
#
#   Laptop's built-in speaker amp is usually anemic, and the Master
#   ALSA control is already at 100% — so the only room left for gain
#   is the PipeWire-side software volume on the sink. `wireplumber.
#   settings.device.routes.default-sink-volume` is capped to 1.0, so
#   we need a Lua hook to go above 100%.
#
#   `services.pipewire.wireplumber.extraConfig` / `extraScripts` look
#   like the natural fit, but NixOS serializes `extraConfig` as JSON
#   (`section = { ... }`), and WirePlumber's fragment parser expects
#   TOML-style syntax. So NixOS-generated extraConfig fragments are
#   silently ignored. We bypass that by dropping TOML fragments and
#   the lua script directly into `configPackages`.
#
#   Enable from a host config:
#
#     auto.wireplumber.amplifyAlsaSinks = true;

let
  cfg = config.auto.wireplumber;
  v = toString cfg.amplifyVolume;
  amplifyConf = pkgs.writeText "90-alsa-amplify.conf" ''
    # WirePlumber TOML fragment: registers the lua script as a
    # component and pulls it into the `main` profile.
    wireplumber.components = [
      {
        name = "90-alsa-amplify.lua"
        type = "script/lua"
        provides = "alsa-amplify"
      }
    ]

    wireplumber.profiles.main."alsa-amplify" = "required"
  '';
  amplifyLua = pkgs.writeText "90-alsa-amplify.lua" ''
    -- SPDX-License-Identifier: MIT
    log = Log.open_topic ("s-alsa-amplify")

    SimpleEventHook {
      name = "alsa-amplify",
      interests = {
        EventInterest {
          Constraint { "event.type", "=", "node-added" },
          Constraint { "media.class", "=", "Audio/Sink" },
          Constraint { "node.name", "matches", "alsa_output.*" },
        },
      },
      execute = function (event)
        local node = event:get_subject ()
        local ok, props = pcall (function ()
          return {
            "Spa:Pod:Object:Param:Props", "Props",
            volume = ${v},
          }
        end)
        if not ok then
          log:warning (node, "failed to build Props pod: " .. tostring (props))
          return
        end
        node:set_param ("Props", props)
        log:info (node, "amplified to ${v}")
      end,
    }
  '';
  amplifyPkg = pkgs.runCommandLocal "wireplumber-alsa-amplify" { } ''
    mkdir -p "$out/share/wireplumber/scripts"
    mkdir -p "$out/share/wireplumber/wireplumber.conf.d"
    cp ${amplifyLua} "$out/share/wireplumber/scripts/90-alsa-amplify.lua"
    cp ${amplifyConf} "$out/share/wireplumber/wireplumber.conf.d/90-alsa-amplify.conf"
  '';
in
{
  options.auto.wireplumber = {
    amplifyAlsaSinks = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Boost software volume on every ALSA sink via a WirePlumber
        Lua hook installed by modules/base/sound.nix.
      '';
    };
    amplifyVolume = lib.mkOption {
      type = lib.types.float;
      default = 1.5;
      example = 2.0;
      description = ''
        Target software volume (1.0 = 100%, 1.5 = 150%). Values above
        1.0 introduce software gain and may clip on loud sources.
      '';
    };
  };

  config = lib.mkIf (cfg.amplifyAlsaSinks && config.services.pipewire.wireplumber.enable) {
    services.pipewire.wireplumber.configPackages = [ amplifyPkg ];
  };
}