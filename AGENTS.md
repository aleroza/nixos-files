# `auto` Module System: Documentation for Agents and Developers

## 1. Overview

This project uses a centralized **`auto`-toggle** system for enabling/disabling functional NixOS modules. Instead of conditionally importing modules, **all modules are always imported**, and each configuration inside a module guards itself with a [`lib.mkIf`](https://noogle.dev/f/lib/mkIf) call.

All management boils down to setting `auto.X = true/false` attributes in the host configuration (e.g., [`hosts/aleroza-pc/default.nix:29`](hosts/aleroza-pc/default.nix:29)). This provides:

- clean declarative enable/disable of features;
- the ability to combine any modules (including multiple DEs);
- safety — no need to worry about circular `imports`.

---

## 2. Module Enabling Patterns

The project uses two patterns for importing modules from [`modules/default.nix`](modules/default.nix):

### Pattern A: Simple toggle (single file)

Used for modules without submodules. Examples: [`development.nix`](modules/development.nix), [`gaming.nix`](modules/gaming.nix), [`flatpak.nix`](modules/flatpak.nix), [`docker.nix`](modules/docker.nix).

**Module structure** — the entire file is wrapped in `lib.mkIf`:

```nix
# modules/myfeature.nix
{ config, lib, pkgs, ... }:

lib.mkIf config.auto.myfeature {
  # NixOS configuration
  environment.systemPackages = with pkgs; [ my-package ];
};
```

**Import** — a simple file reference in [`modules/default.nix`](modules/default.nix:14):

```nix
imports = [
  ./myfeature.nix   # ← file
];
```

**Option declaration** — in [`modules/auto.nix`](modules/auto.nix):

```nix
options.auto = {
  myfeature = mkOption {
    type = types.bool;
    default = false;
    description = "...";
  };
};
```

### Pattern B: Complex module with submodules (directory)

Used when a module has sub-options with their own enabling logic. The only current example is [`modules/gnome/`](modules/gnome/).

**Directory structure:**

```
modules/gnome/
├── default.nix                      # entry point
└── extensions/
    ├── appindicator.nix
    ├── clipboard-indicator.nix
    └── display-brightness-ddcutil.nix
```

**`default.nix`** ([`modules/gnome/default.nix`](modules/gnome/default.nix)) — uses unconditional `imports` to load submodules (so their options are declared) and conditional `config` via `lib.mkIf`:

```nix
{ config, lib, pkgs, ... }:
let cfg = config.auto; in {
  imports = [
    ./extensions/appindicator.nix              # unconditionally
    ./extensions/clipboard-indicator.nix
    ./extensions/display-brightness-ddcutil.nix
  ];

  config = lib.mkIf cfg.gnome.enable {          # conditionally
    services.desktopManager.gnome.enable = true;
  };
};
```

**Submodule (extension)** ([`modules/gnome/extensions/clipboard-indicator.nix`](modules/gnome/extensions/clipboard-indicator.nix:12)) — declares options unconditionally, but only applies configuration when both the parent and the submodule itself are enabled:

```nix
{ config, lib, pkgs, ... }:
let cfg = config.auto.gnome.extensions.clipboard-indicator; in {
  # options are declared unconditionally — otherwise they cannot be read
  options.auto.gnome.extensions.clipboard-indicator = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  # configuration is applied only when both toggles are enabled
  config = lib.mkIf (cfg.enable && config.auto.gnome.enable) {
    environment.systemPackages = with pkgs; [ gnomeExtensions.clipboard-indicator ];
  };
};
```

**Import** — a directory reference in [`modules/default.nix`](modules/default.nix:7):

```nix
imports = [
  ./gnome        # ← directory (NixOS picks up default.nix)
];
```

---

## 4. Rules for Creating New Modules

### Simple module (without submodules)

1. Create the file [`modules/myfeature.nix`](modules/):

```nix
{ config, lib, pkgs, ... }:
lib.mkIf config.auto.myfeature {
  # configuration
};
```

2. Add the line `./myfeature.nix` to [`modules/default.nix`](modules/default.nix).

3. Add the option to [`modules/auto.nix`](modules/auto.nix):

```nix
options.auto = {
  myfeature = mkOption {
    type = types.bool;
    default = false;
    description = "Enable my feature.";
  };
};
```

### Complex module (with submodules)

1. Create the directory [`modules/myfeature/`](modules/) with a `default.nix`:

```nix
{ config, lib, pkgs, ... }:
let cfg = config.auto.myfeature; in {
  imports = [
    ./sub-module.nix       # unconditionally, so options are visible
  ];
  config = lib.mkIf cfg.enable {
    # main module configuration
  };
};
```

2. Create the submodule [`modules/myfeature/sub-module.nix`](modules/):

```nix
{ config, lib, ... }:
let cfg = config.auto.myfeature.sub; in {
  # options are declared unconditionally
  options.auto.myfeature.sub.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
  };

  # configuration with double guard (parent + own toggle)
  config = lib.mkIf (cfg.enable && config.auto.myfeature.enable) {
    # ...
  };
};
```

3. Add the line `./myfeature` to [`modules/default.nix`](modules/default.nix).

4. Add the parent option to [`modules/auto.nix`](modules/auto.nix):

```nix
options.auto = {
  myfeature = {
    enable = mkOption {
      type = types.bool;
      default = false;
    };
  };
};
```

---

## 5. Where to Declare Options

| Option type | Where to declare | Example |
|---|---|---|
| Simple boolean toggles (`auto.development`, `auto.gaming`, `auto.flatpak`, `auto.bluetooth`, `auto.server`, `auto.ssh`, `auto.fail2ban`) | [`modules/auto.nix`](modules/auto.nix) | `auto.flatpak = mkOption { ... }` |
| Toggles with `.enable` for modules with sub-options (`auto.docker.enable`, `auto.gnome.enable`) | [`modules/auto.nix`](modules/auto.nix) | `auto.gnome.enable = mkOption { ... }` |
| Nested options (GNOME extensions — `auto.gnome.extensions.X`) | In the submodule that uses them | [`modules/gnome/extensions/clipboard-indicator.nix:13`](modules/gnome/extensions/clipboard-indicator.nix:13) |
| Additional module fields (`auto.docker.users`, `auto.gnome.extensions.X.users`) | Same place as the `enable` for that module | [`modules/gnome/extensions/appindicator.nix:13`](modules/gnome/extensions/appindicator.nix:13) |

**Principle:** options are declared as close as possible to the configuration they control. Simple toggles go in the central [`auto.nix`](modules/auto.nix), while submodule-specific options go in the submodules themselves (colocation).

---

## Appendix: How It Looks in a Host Configuration

Example from [`hosts/aleroza-pc/default.nix:29`](hosts/aleroza-pc/default.nix:29):

```nix
auto = {
  mainUser  = "aleroza";
  development = true;
  gaming      = true;

  gnome = {
    enable = true;
    extensions = {
      display-brightness-ddcutil.enable = true;
      appindicator.enable = true;
      clipboard-indicator.enable = true;
    };
  };

  docker = {
    enable = true;
    users  = [ "openclaw" ];
  };

  bluetooth = true;
  flatpak   = true;
  # ...
};
```

This structure is the single place where a host declares which features it needs. The modules themselves take care of enabling the corresponding NixOS services.
