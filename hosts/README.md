# Hosts

Per-host configuration — hardware, GPU, home-manager, lid settings.

## Structure

```
hosts/
├── _common/           # Shared host-agnostic defaults
└── <hostname>/
    ├── default.nix    # Host entry point (imports modules)
    ├── hardware.nix   # Hardware config (disko, kernel modules)
    ├── gpu.nix        # GPU configuration
    ├── home.nix       # User home-manager config
    └── lid.nix        # Laptop lid behavior
```

## Adding a New Host

1. Create the directory: `hosts/my-host/`
2. Copy from `_common/` or an existing host:
   ```bash
   cp hosts/aleroza-pc/default.nix hosts/my-host/
   ```
3. Edit `hosts/my-host/default.nix` — set `imports` and `hostName`
4. Add to `flake.nix`'s `hosts` map:
   ```nix
   my-host = import ./hosts/my-host;
   ```
5. Run `nixos-rebuild switch --flake .#my-host`

## Host Files

| File | Purpose |
|------|---------|
| `default.nix` | Imports + hostName + networking + boot |
| `hardware.nix` | disko config, kernel modules |
| `gpu.nix` | NVIDIA/AMD GPU settings |
| `home.nix` | Home-manager user config |
| `lid.nix` | Lid close behavior |
