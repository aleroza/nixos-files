# Modules

Shared NixOS modules imported by all hosts. Each subdirectory is a domain.

## Subdirectories

- `audio/` — PulseAudio/PipeWire, Bluetooth audio
- `contracts/` — Environment variables (NIX_PATH, etc.)
- `core/` — Base system config, nix settings, allowlists
- `display/` — X11, GDM, GPU configuration
- `input/` — Keyboard/mouse/touchpad via libinput
- `networking/` — Base networking, SSH
- `packages/` — System packages (base, apps, dev-tools, editors)
- `security/` — Base hardening, fail2ban
- `shell/` — Shell aliases and environment
- `user/` — Home-manager modules (portable + nixos/dconf)
- `users/` — System users, groups
- `virtualization/` — Docker

## Adding a New Module

1. Create `modules/<category>/my-feature.nix`:
```nix
{ config, lib, pkgs, ... }:

{
  options = {
    myFeature = lib.mkOption { ... };
  };

  config = {
    # ... apply myFeature
  };
}
```

2. Reference it in the host or in a parent module via `imports` or `modules`.

See individual category READMEs for details.
