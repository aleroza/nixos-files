# core module

Base system configuration — timezone, locale, boot, networking base, nix settings.

## What it configures

- Timezone and locale
- Network configuration (hostName, default gateway)
- Boot (loader, kernel params)
- System packages (utilities, FUSE, sandbox)
- Allowlist for unfree packages

## Key options

- `core.hostName` — system hostname
- `core.allowUnfree` — enable unfree packages (bool)
- `core.timezone` / `core.locale`
- `core.kernelParams` — boot kernel parameters
