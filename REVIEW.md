# NixOS Modular Review — feature/nixos-modular

## Summary

The modular structure is **functional and eval-clean** (`nix flake check` passes), but it carries significant technical debt: duplicate HM module trees, empty placeholder files, an empty `users2/` directory, and several `modules/` that are pure placeholders. The migration is ~80% complete — core infrastructure (boot, networking, users, audio, docker, shell aliases) is solid, but desktop, input, and many home-manager dconf modules are stubs or missing. The `user/` vs `modules/user/` split is a major issue — two parallel HM module trees exist with divergent content.

---

## ✅ What's Working

| Component | Status | Notes |
|---|---|---|
| `flake.nix` | ✅ | Correctly structured with HM integration |
| `hosts/aleroza-pc/default.nix` | ✅ | Imports all modular components cleanly |
| `modules/core/base.nix` | ✅ | Boot loader, kernel, swap, udev rules all present |
| `modules/networking/base.nix` | ✅ | hostName, NetworkManager, timezone |
| `modules/networking/ssh.nix` | ✅ | openssh with PermitRootLogin=no |
| `modules/security/base.nix` | ✅ | fail2ban enabled |
| `modules/security/fail2ban.nix` | ✅ | (module exists, referenced in base) |
| `modules/users/groups.nix` | ✅ | i2c, openclaw, plocate groups |
| `modules/users/base.nix` | ✅ | aleroza + openclaw users fully defined |
| `modules/audio/base.nix` | ✅ | pipewire with alsa+pulse+wireplumber |
| `modules/audio/bluetooth.nix` | ✅ | bluetooth with Experimental=true |
| `modules/virtualization/docker.nix` | ✅ | docker + autoPrune |
| `modules/shell/aliases.nix` | ✅ | ll, nix-rebuild, nix-gen |
| `modules/display/x11.nix` | ✅ | xserver + xkb layout us,ru |
| `modules/display/gdm.nix` | ✅ | gdm + autoLogin |
| `hosts/aleroza-pc/lid.nix` | ✅ | lid switch config (suspend-then-hibernate) |
| `hosts/aleroza-pc/home.nix` | ✅ | HM imports all portable + dconf modules |
| `hosts/aleroza-pc/home-openclaw.nix` | ✅ | openclaw user HM config |
| `modules/contracts/env.nix` | ✅ | EDITOR session variable |
| `desktop/gnome/core.nix` | ✅ | gnome enabled, epiphany excluded |
| Home Manager portable modules | ✅ | 01-06 (git, shell-env, aliases, defaults, cli-apps, xdg-mimeapps) |
| `nix flake check` | ✅ | Passes with no errors |

---

## 🔴 Critical Issues

### 1. **Duplicate HM module trees — `user/` vs `modules/user/`**

Two parallel home-manager module directories exist with **different content**:

```
modules/user/     (used by home.nix)
user/            (NOT imported anywhere — dead code)
```

Key differences:
- `modules/user/portable/06-xdg-mimeapps.nix` exists; `user/portable/` ends at 05
- `user/portable/10-openclaw-user.nix` exists; `modules/user/portable/` has no such file
- `modules/user/nixos/dconf/02-favorites.nix` vs `user/nixos/dconf/02-theme.nix` — completely different
- `modules/user/nixos/gnome-extensions.nix`, `monitors.nix`, `autostart.nix` exist; `user/` versions are different
- `user/nixos/dconf/flatpak-hooks.nix`, `.gitkeep`, `monitors.nix` exist only in `user/`

**Action: Delete `user/` directory entirely** — `hosts/aleroza-pc/home.nix` only imports from `modules/user/`.

### 2. **Empty `users2/` directory**

`modules/users2/` is an empty directory with no files. Dead code — **remove it**.

### 3. **Empty placeholder modules**

The following modules exist but contain only comments (no actual config):

| File | Issue |
|---|---|
| `modules/core/nix.nix` | Empty placeholder |
| `modules/input/base.nix` | Only has `options = {}` |
| `modules/packages/editors/placeholder.nix` | Explicitly "placeholder" |
| `modules/packages/editors/vscode.nix` | Actually works, but vscode is also in `apps.nix` — **double import risk** |
| `modules/users/openclaw-system-user.nix` | Empty placeholder |
| `modules/virtualization/` | Only has `docker.nix` — correct |

**Action:** Either implement or remove empty placeholders. `modules/input/base.nix` could be merged into `libinput.nix`.

### 4. **`modules/packages/editors/vscode.nix` double-inclusion**

vscode is installed in **both** `modules/packages/apps.nix` (via `environment.systemPackages`) and in `modules/packages/editors/vscode.nix` (via `programs.vscode.enable = true`). The host imports **both** modules.

If `editors/vscode.nix` is imported separately, vscode gets added twice — once via systemPackages, once via programs.vscode. This is not an eval error (Nix deduplicates) but it's redundant.

**Action:** Remove vscode from `apps.nix` systemPackages and rely only on `programs.vscode` in `editors/vscode.nix`.

---

## 🟡 Issues to Fix

### 5. **`desktop/gnome/apps.nix`, `extensions.nix`, `exclude.nix` are all empty stubs**

These are imported by `desktop/gnome/default.nix` but contain only comments. The actual gnome config in `core.nix` is minimal — it only enables gnome and excludes epiphany.

Missing from `desktop/gnome/`:
- No GNOME extensions defined (only a placeholder `gnome-extensions.nix`)
- No gnome-tweaks configuration
- No dconf settings for GNOME behavior (power, screensaver, etc.)
- Some of this is handled in home-manager dconf modules, but the split is inconsistent

### 6. **`hosts/aleroza-pc/hardware.nix` and `gpu.nix` are empty stubs**

`gpu.nix` and `hardware.nix` are imported by the host but contain only comments. GPU config is missing (no NVIDIA/catalyst config). This may be intentional if the default nouveau driver works, but it should be documented.

### 7. **`modules/display/base.nix` has dead code**

`modules/display/base.nix` sets `services.displayManager.gdm.enable = true` but GDM is also configured in `modules/display/gdm.nix`. This is a duplicate — GDM ends up enabled twice. `display/base.nix` should not set this if `gdm.nix` handles it, or they should be merged.

### 8. **No `system.activationScripts` for flatpak in host**

The original `configuration.nix` had flatpak setup as `system.activationScripts`. The `modules/packages/apps.nix` still has this, but it's **inside `environment.systemPackages`** which is incorrect — activationScripts should be at top level. However, `hosts/aleroza-pc/home.nix` uses `home.activation` for flatpak setup, which is the proper HM location.

Two flatpak setup locations exist: `modules/packages/apps.nix` (broken — inside systemPackages) and `home.nix` activation. The `apps.nix` one is broken and should be removed.

### 9. **Missing `modules/packages/dev-tools.nix` content**

Only has `nixfmt`. The original had more dev tools. See Missing Functionality below.

### 10. **`modules/user/nixos/dconf/` numbering mismatch**

- `01-shortcuts.nix` — exists, works
- `02-favorites.nix` — exists in `modules/user/`, but `user/` has `02-theme.nix` (different content)
- `03-interface.nix` vs `user/` has `03-fonts.nix`
- `04-power.nix` vs `user/` has `04-keyboard.nix`
- `05-screensaver.nix` vs `user/` has `05-touchpad.nix`
- `06-wm.nix` vs `user/` has `06-applications.nix`
- `07-extensions.nix` vs `user/` has `07-background.nix`
- `08-input.nix` — both have it, content differs

The `modules/user/nixos/dconf/` numbering was likely reassigned during migration but `user/` was not updated. Since `user/` is dead code, this doesn't matter — but the naming is confusing.

### 11. **`configuration.nix` is now just a wrapper**

The current `configuration.nix` just imports `hardware-configuration.nix` and `hosts/aleroza-pc/default.nix`. This is fine, but the comment says "NOTE: This file only works with flakes." — the original had non-flake support. Since flakes are standard now, this is acceptable but the comment is misleading.

---

## 🔲 Missing Functionality

### Original `configuration.nix` → modular migration status:

| Feature | Original | Modular | Status |
|---|---|---|---|
| boot.loader (systemd-boot + EFI) | ✅ | ✅ (`hosts/aleroza-pc/default.nix`) | ✅ |
| kernel (linuxPackages_latest) | ✅ | ✅ (`modules/core/base.nix`) | ✅ |
| swap | ✅ | ✅ (`modules/core/base.nix`) | ✅ |
| udev rules (i2c) | ✅ | ✅ (`modules/core/base.nix`) | ✅ |
| networking.hostName | ✅ | ✅ (`modules/networking/base.nix`) | ✅ |
| networkmanager | ✅ | ✅ (`modules/networking/base.nix`) | ✅ |
| time.timeZone | ✅ | ✅ (`modules/networking/base.nix`) | ✅ |
| xserver | ✅ | ✅ (`modules/display/x11.nix`) | ✅ |
| gdm | ✅ | ✅ (`modules/display/gdm.nix`) | ✅ |
| gnome | ✅ | ✅ (`desktop/gnome/core.nix`) | ✅ partial |
| gdm autoLogin | ✅ | ✅ (`modules/display/gdm.nix`) | ✅ |
| lid switch | ✅ | ✅ (`hosts/aleroza-pc/lid.nix`) | ✅ |
| pipewire | ✅ | ✅ (`modules/audio/base.nix`) | ✅ |
| bluetooth | ✅ | ✅ (`modules/audio/bluetooth.nix`) | ✅ |
| libinput | ✅ | ✅ (`modules/input/libinput.nix`) | ✅ |
| openssh | ✅ | ✅ (`modules/networking/ssh.nix`) | ✅ |
| fail2ban | ✅ | ✅ (`modules/security/base.nix`) | ✅ |
| user groups | ✅ | ✅ (`modules/users/groups.nix`) | ✅ |
| user aleroza | ✅ | ✅ (`modules/users/base.nix`) | ✅ |
| user openclaw | ✅ | ✅ (`modules/users/base.nix`) | ✅ |
| shellAliases | ✅ | ✅ (`modules/shell/aliases.nix`) | ✅ |
| flatpak | ✅ | ⚠️ split (home.activation works; system.activationScripts broken) | ⚠️ |
| steam | ✅ | ✅ (`modules/packages/apps.nix`) | ✅ |
| firefox | ✅ | ✅ (`modules/packages/apps.nix`) | ✅ |
| docker | ✅ | ✅ (`modules/virtualization/docker.nix`) | ✅ |
| systemPackages | ✅ (many) | ⚠️ (reduced set) | ⚠️ partial |
| xkb layout | ✅ (us,ru) | ✅ (`modules/display/x11.nix`) | ✅ |
| ddcutil | ✅ | ✅ (`modules/packages/apps.nix`) | ✅ |
| wireshark | ✅ | ✅ (`modules/packages/apps.nix`) | ✅ |
| **gnome extensions** | N/A | ⚠️ (stub) | ❌ |
| **gnome-tweaks config** | N/A | ⚠️ (stub) | ❌ |
| **flatpak bottles override** | N/A | ✅ (`hosts/aleroza-pc/home.nix`) | ✅ |
| **monitors.xml** | N/A | ✅ (`modules/user/nixos/monitors.nix`) | ✅ |
| **nix.settings** | ✅ (experimental-features) | ❌ (missing) | ❌ |

### Items **not migrated** or **incomplete**:

1. **`nix.settings.experimental-features = ["nix-command" "flakes"]`** — This was in the original `configuration.nix` and is NOT in any modular file. Should be in `modules/core/nix.nix` (currently empty) or in a dedicated `modules/core/nix.nix`.

2. **`programs.steam` firewall options** — In `modules/packages/apps.nix` but steam port openings are `openFirewall = true` which requires `networking.firewall.enable = true`. The firewall module is not explicitly enabled anywhere. This may work if the default firewall is permissive, but it's risky.

3. **`users.users.aleroza.hashedPasswordFile`** — The original used a `secrets/aleroza-password` file. The migrated version has it commented out with "# requires secrets dir". The aleroza user has no password set in the modular version.

4. **GNOME dconf settings** — The home-manager dconf modules cover shortcuts, favorites, interface, power, screensaver, wm, extensions, input — but some are stubs. The `modules/user/nixos/dconf/` modules have different content than the `user/` versions (which are dead).

5. **`home-manager` duplicate detection** — The flake shows `homeManagerConfigurations: unknown` warning. The correct output name for home-manager 25.11 is `homeConfigurations` (not `homeManagerConfigurations`). This means `nix flake show` doesn't properly display the HM configs. However, `nix flake check` passes, so the configs do build.

---

## 🗑️ Dead Code

| Path | Issue |
|---|---|
| `user/` directory | Entire directory is dead — imported from nowhere. Has different HM modules than `modules/user/`. **Delete entire `user/` directory.** |
| `modules/users2/` | Empty directory. **Remove it.** |
| `modules/input/base.nix` | Empty placeholder (`options = {}`). **Remove or merge into `libinput.nix`.** |
| `modules/core/nix.nix` | Empty placeholder. **Implement nix settings here or remove.** |
| `modules/packages/editors/placeholder.nix` | Explicit placeholder. **Remove.** |
| `modules/users/openclaw-system-user.nix` | Empty placeholder. **Remove (user is already in `base.nix`).** |
| `hosts/aleroza-pc/hardware.nix` | Empty placeholder. **Implement or remove from host imports.** |
| `hosts/aleroza-pc/gpu.nix` | Empty placeholder. **Implement GPU config or remove from host imports.** |
| `modules/user/nixos/gnome-extensions.nix` | Stub. **Implement or remove.** |
| `modules/user/nixos/autostart.nix` | Actually has content (flclash autostart) — ✅ this one is fine |
| `modules/user/nixos/monitors.nix` | Actually has content (monitors.xml) — ✅ this one is fine |
| `modules/user/portable/06-xdg-mimeapps.nix` | Exists in `modules/` but not in `user/`. **Keep — good.** |
| `user/portable/10-openclaw-user.nix` | Only exists in `user/` (dead). **Delete with `user/` directory.** |
| `user/nixos/dconf/` | Entire directory is dead with different content than `modules/user/nixos/dconf/`. **Delete with `user/` directory.** |

---

## 📊 Module Health Check

| Module | Status | Issues |
|---|---|---|
| `modules/core/base.nix` | ✅ Good | None |
| `modules/core/allowlist.nix` | ✅ Good | None |
| `modules/core/nix.nix` | 🔴 Empty | **Must implement** nix.settings or remove |
| `modules/networking/base.nix` | ✅ Good | None |
| `modules/networking/ssh.nix` | ✅ Good | None |
| `modules/security/base.nix` | ✅ Good | None |
| `modules/security/fail2ban.nix` | ✅ Good | None |
| `modules/users/groups.nix` | ✅ Good | None |
| `modules/users/base.nix` | ✅ Good | None |
| `modules/users/openclaw-system-user.nix` | 🔴 Empty | **Must remove** (duplicate) |
| `modules/audio/base.nix` | ✅ Good | None |
| `modules/audio/bluetooth.nix` | ✅ Good | None |
| `modules/input/base.nix` | 🔴 Empty | **Must remove or merge** |
| `modules/input/libinput.nix` | ✅ Good | None |
| `modules/display/base.nix` | 🟡 Dead code | Duplicates gdm.enable from gdm.nix — **merge or remove** |
| `modules/display/gdm.nix` | ✅ Good | None |
| `modules/display/x11.nix` | ✅ Good | None |
| `modules/packages/base.nix` | ✅ Good | None |
| `modules/packages/dev-tools.nix` | 🟡 Thin | Only nixfmt — missing wireshark, ddcutil etc. (those are in apps.nix) |
| `modules/packages/apps.nix` | ✅ Good | Has flatpak activation inside systemPackages (broken) |
| `modules/packages/editors/placeholder.nix` | 🗑️ Delete | Placeholder — **remove** |
| `modules/packages/editors/vscode.nix` | ✅ Good | But vscode also in apps.nix — **deduplicate** |
| `modules/shell/aliases.nix` | ✅ Good | None |
| `modules/virtualization/docker.nix` | ✅ Good | None |
| `modules/contracts/env.nix` | ✅ Good | None |
| `desktop/gnome/default.nix` | ✅ Good | Imports stubs |
| `desktop/gnome/core.nix` | ✅ Good | None |
| `desktop/gnome/apps.nix` | 🟡 Stub | Empty placeholder |
| `desktop/gnome/extensions.nix` | 🟡 Stub | Empty placeholder |
| `desktop/gnome/exclude.nix` | 🟡 Stub | Empty placeholder |
| `desktop/kde/default.nix` | 🟡 Stub | KDE not implemented |
| `desktop/hyprland/default.nix` | 🟡 Stub | Hyprland not implemented |
| `desktop/none/default.nix` | 🟡 Stub | "none" desktop not implemented |
| `hosts/aleroza-pc/default.nix` | ✅ Good | None |
| `hosts/aleroza-pc/lid.nix` | ✅ Good | None |
| `hosts/aleroza-pc/hardware.nix` | 🟡 Empty | Stub |
| `hosts/aleroza-pc/gpu.nix` | 🟡 Empty | Stub |
| `hosts/aleroza-pc/home.nix` | ✅ Good | None |
| `hosts/aleroza-pc/home-openclaw.nix` | ✅ Good | None |
| `modules/user/portable/01-05` | ✅ Good | None |
| `modules/user/portable/06-xdg-mimeapps` | ✅ Good | None |
| `modules/user/nixos/dconf/01-08` | ✅ Good | Content differs from `user/` (dead) version |
| `modules/user/nixos/monitors.nix` | ✅ Good | None |
| `modules/user/nixos/autostart.nix` | ✅ Good | None |
| `modules/user/nixos/gnome-extensions.nix` | 🟡 Stub | Empty placeholder |

---

## Recommendations

### Immediate (must do before merge)

1. **Delete `user/` directory** — it's a parallel dead tree causing confusion
2. **Delete `modules/users2/`** — empty directory
3. **Implement `modules/core/nix.nix`** — add `nix.settings.experimental-features = ["nix-command" "flakes"]`
4. **Remove duplicate vscode** — keep only `programs.vscode` in `editors/vscode.nix`, remove from `apps.nix` systemPackages
5. **Fix `modules/packages/apps.nix`** — move the flatpak `system.activationScripts` out of `environment.systemPackages` (or just rely on the home.activation in `home.nix` which is correct)
6. **Remove empty stubs from host imports** — `hardware.nix` and `gpu.nix` are imported but empty. Either implement them or remove from imports

### Short-term (post-migration cleanup)

7. **Implement desktop stubs** — `desktop/gnome/apps.nix`, `extensions.nix`, `exclude.nix` should either have real content or be removed from `desktop/gnome/default.nix` imports
8. **Fix `display/base.nix`** — remove duplicate gdm.enable, or merge `display/base.nix` logic into `gdm.nix`
9. **Document GPU config** — if nouveau is fine, add a comment; if NVIDIA is needed, add config
10. **Clean up `modules/user/nixos/dconf/` naming** — the 01-08 numbering with inconsistent topics is confusing; consider renaming to match content (e.g., `03-interface.nix` → `03-fonts.nix` to match the original `user/` naming, or document the current mapping)

### Nice-to-have

11. **Add password for aleroza user** — either set `hashedPasswordFile` or use `hashedPassword`
12. **Fix `homeManagerConfigurations` warning** — use `homeConfigurations` for proper flake output display
13. **Consider desktop selector** — `modules/display/base.nix` has a `desktop.environment` option that's not used; could drive which desktop module to import
14. **Add KDE/Hyprland implementations** — stubs exist but no real config
