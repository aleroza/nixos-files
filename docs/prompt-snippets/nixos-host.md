# NixOS host notes (master-prompt block)

Add to the master system prompt. Pairs with the existing `focus` /
`foresight` directives; complements rather than replaces the
`ccr-retrieval.md` snippet in this directory. English.

```markdown
## NixOS host notes

You run on NixOS as user `hermes` under a NixOS-managed systemd unit whose
PATH is the hermes-agent closure (not the system closure).
`/run/current-system/sw/bin/` and `~/.nix-profile/bin/` are not on PATH
by default — `docker`, `git`, `nix`, etc. are invisible unless invoked by
absolute path or installed into the user profile.

- **Install into your shell** (no sudo, reversible, no `/nix/store` writes):
  `nix-env -iA nixpkgs.<attr>`. Prefer this over `pip install --user`,
  `npm i -g`, `apt`.
- **One-off command needing a missing tool:** `nix-shell -p <pkg> --run '…'`.
- **System binary the unit's PATH can't see:** absolute path
  `/run/current-system/sw/bin/<tool>`. Read-only, always resolvable.

Do not run `nixos-rebuild` (user-triggered via `.switch-request`/`.pending-switch`
pair, requires explicit approval). Do not write to `/nix/store`.
```

## Why this wording

- **Lead with the *why* (PATH is a closure, not a system PATH).** Naming
  the constraint up front lets the model classify tools correctly: "this
  command is missing because the unit's PATH is narrow, not because it
  isn't installed." Without that, the model tends to reach for `sudo` or
  `apt`, both wrong here.
- **Three install primitives, one concrete command each.** `nix-env -iA`
  for permanent, `nix-shell -p --run` for one-off, absolute path for
  system binaries the unit can't see. Parallel structure, no prose
  bridging — the model pattern-matches a need to a recipe.
- **Don'ts are guardrails, not the main story.** Putting `nixos-rebuild`
  and `/nix/store` writes at the end frames them as "things you might
  be tempted to do but shouldn't", not as the operating mode.
- **No explanation of what NixOS or sudo are.** The model is assumed to
  know standard linux + package-manager abstractions. Spending tokens
  on definitions would dilute the operative rules.

## Where it lives in the prompt

Slot next to the `ccr-retrieval.md` snippet in the master prompt — both
are operational notes about the runtime environment (CCR is a
content-routing concern, NixOS is a tool/PATH concern). Either order
works; placing NixOS second means the model encounters CCR retrieval
first when it scans the prompt top-to-bottom.
