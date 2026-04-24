# Desktop Environments

Swap DE by changing the desktop import in your host's `default.nix`.

## Modules

- `gnome/` — **Primary DE**. Full GNOME stack: gdm, core, apps, extensions
- `kde/` — **Stub**. Plasma configuration (placeholder)
- `hyprland/` — **Stub**. Hyprland configuration (placeholder)
- `none/` — Headless config (no desktop environment)

## Switching DE

```nix
# In hosts/<your-host>/default.nix:
imports = [ ../desktop/gnome ];       # default
imports = [ ../desktop/kde ];
imports = [ ../desktop/hyprland ];
imports = [ ../desktop/none ];        # server/headless
```

GNOME is the primary DE. KDE and Hyprland modules are functional but less configured.
