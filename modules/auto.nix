{ config, lib, ... }:
let
  inherit (lib) types mkOption;
in
{
  options.auto = {
    # ▸ Feature toggles
    dev = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable base development tools (git, vim, nix-ld).";
      };
      nodejs = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Node.js.";
      };
      python = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Python.";
      };
      networkCapture = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Enable packet capture tools (wireshark/tcpdump) and grant
            capture rights to users listed in auto.dev.networkCapture.users.
          '';
        };
        users = mkOption {
          type = types.listOf types.str;
          default = lib.lists.optional (config.auto.mainUser != "") config.auto.mainUser;
          description = ''
            Users added to the 'wireshark' group. Members can run
            dumpcap/tcpdump/wireshark without root via CAP_NET_RAW.
          '';
        };
      };
    };

    gaming = mkOption {
      type = types.bool;
      default = false;
      description = "Enable gaming tools (Steam, Lutris, MangoHud).";
    };

    firewall = {
      gaming = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Open firewall ports for LAN/hosted multiplayer games
          (Jackbox, Pico Park, etc.), Steam Remote Play, Steam LAN game
          transfers, and Source Dedicated Server.
        '';
      };
      trustedInterfaces = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "wlan0" "tailscale0" ];
        description = ''
          Interfaces treated as trusted LAN by the firewall. Required for
          LAN game discovery (mDNS, broadcast) to work — open ports alone
          are not enough, as NixOS' default firewall blocks incoming
          traffic on non-trusted interfaces. Find interface names with
          `ip link`.
        '';
      };
      allowedTCPPorts = mkOption {
        type = types.listOf types.port;
        default = [ ];
        example = [ 6881 51413 ];
        description = ''
          Extra TCP ports to open on the firewall, in addition to the
          feature-defined port sets (e.g. gaming). Merged into a single
          `networking.firewall.allowedTCPPorts` list by modules/firewall.
        '';
      };
      allowedUDPPorts = mkOption {
        type = types.listOf types.port;
        default = [ ];
        example = [ 6881 ];
        description = ''
          Extra UDP ports to open on the firewall, in addition to the
          feature-defined port sets (e.g. gaming). Merged into a single
          `networking.firewall.allowedUDPPorts` list by modules/firewall.
        '';
      };
    };

    server = mkOption {
      type = types.bool;
      default = false;
      description = "Enable server profile. Convenience preset that enables ssh + fail2ban via mkDefault.";
    };

    desktop = mkOption {
      type = types.bool;
      default = false;
      description = "Enable desktop profile. Convenience preset that enables server + input + sound + programs + bluetooth via mkDefault.";
    };

    # ▸ Desktop environments (individual toggles, any combination allowed)
    xserver = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable X11 windowing system.";
      };
    };

    gnome = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable GNOME desktop environment.";
      };
    };

    kde = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable KDE Plasma desktop environment.";
      };
    };

    hyprland = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Hyprland compositor.";
      };
    };

    laptop = mkOption {
      type = types.bool;
      default = false;
      description = "Enable laptop lid behavior (suspend/lock on lid close).";
    };

    power = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable power management (logind).";
      };
    };

    sound = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable sound (PipeWire).";
      };
    };

    input = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable touchpad / libinput.";
      };
    };

    programs = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable common desktop programs (Firefox, etc.).";
      };
    };

    # ▸ Docker
    docker = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Docker daemon.";
      };

      users = mkOption {
        type = types.listOf types.str;
        default = lib.lists.optional (config.auto.mainUser != "") config.auto.mainUser;
        description = "Users to add to the docker group.";
      };
    };

    # ▸ OpenViking (local-first context database for Hermes Agent)
    openviking = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable OpenViking self-hosted context database on
          127.0.0.1:1933. Used by services.hermes-agent when
          memory.provider is set to "openviking".
        '';
      };
      openFirewall = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to expose the OpenViking port (1933) on the
          firewall. Off by default — the server binds to
          127.0.0.1 only, so firewall rules are usually
          unnecessary.
        '';
      };
    };

    # ▸ Bluetooth
    bluetooth = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Bluetooth support.";
    };

    # ▸ Flatpak
    flatpak = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Flatpak (flathub) support.";
    };

    # ▸ SSH server
    ssh = mkOption {
      type = types.bool;
      default = false;
      description = "Enable OpenSSH server.";
    };

    # ▸ Fail2ban
    fail2ban = mkOption {
      type = types.bool;
      default = false;
      description = "Enable fail2ban.";
    };

    # ▸ SOPS (age-encrypted secrets)
    sops = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable sops-nix. Activates the sops NixOS module, which decrypts
          secrets declared via `sops.secrets.<name>` (paths placed under
          /run/secrets by default) using age keys provisioned by
          `sops.age.sshKeyPaths` / `sops.age.keyFile`.

          Also creates `~/.config/sops/age/keys.txt` for the users in
          `auto.sops.users` so they can run `sops` interactively.
        '';
      };

      users = mkOption {
        type = types.listOf types.str;
        default = lib.lists.optional (config.auto.mainUser != "") config.auto.mainUser;
        description = ''
          Users for whom `~/.config/sops/age/keys.txt` is provisioned so
          they can encrypt/edit secrets interactively.
        '';
      };
    };

    # ▸ Home-manager users
    hmUsers = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Users configured via home-manager.";
    };

    # ▸ Main system user
    mainUser = mkOption {
      type = types.str;
      default = "";
      description = "Primary system user. Auto-filled into module user-lists like docker.users or display-brightness-ddcutil.users.";
    };
  };
}
