# nixos-modular

Modular NixOS configuration — shared modules with per-host overrides.

## Structure

```
flake.nix              # Entry point
modules/               # Shared modules (core, networking, security, users, etc.)
  └── <category>/       #   Each category has domain-specific submodules
desktop/               # DE modules (gnome, kde, hyprland, none)
hosts/                 # Host-specific configs
  └── <hostname>/      #   Hardware, GPU, home, lid settings
```

## Quick Start

**Add a new host:**
```bash
mkdir -p hosts/my-host
cp hosts/_common/* hosts/my-host/
# Edit hosts/my-host/default.nix — set imports for this host
# Add to flake.nix's hosts map
```

**Switch DE:**
```nix
# In your host's default.nix, change the desktop import:
imports = [ ../desktop/gnome ];       # primary
imports = [ ../desktop/kde ];        # stub
imports = [ ../desktop/hyprland ];   # stub
imports = [ ../desktop/none ];       # headless
```

## Philosophy

- **Shared modules** in `modules/` — imported by all hosts, DRY
- **Per-host overrides** in `hosts/<hostname>/` — hardware, user, lid config
- **Desktop modules** in `desktop/` — swap DE without touching system modules
- **HM modules** in `modules/user/` — home-manager for user-level config

See `modules/README.md` for module details.
