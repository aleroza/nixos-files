# user/ is deprecated

The `user/` directory is no longer used.

## Active Tree

User-level configuration is now in `modules/user/`:

- `modules/user/portable/` — Home-manager portable modules (git, shell, CLI apps, XDG)
- `modules/user/nixos/` — NixOS-specific HM config (dconf)

## Migration

Old `user/` imports → `modules/user/portable/` or `modules/user/nixos/` in the host's home.nix.
