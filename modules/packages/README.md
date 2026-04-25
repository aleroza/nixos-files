# packages module

System packages organized by category.

## What it configures

- `base/` — core utilities (git, curl, wget, unzip, etc.)
- `apps/` — GUI applications
- `dev-tools/` — compilers, build tools
- `editors/` — editor configs (VS Code stub)

## Key options

- `packages.enableUnfree` — include unfree packages (bool)
- `packages.basePackages` — list of base packages
- `packages.devPackages` — list of dev tool packages
- `packages.appPackages` — list of GUI application packages
