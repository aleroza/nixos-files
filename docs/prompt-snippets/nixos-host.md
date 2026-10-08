# NixOS host notes (master-prompt block)

Add to the master system prompt. Pairs with the existing `focus` /
`foresight` directives; complements rather than replaces the
`ccr-retrieval.md` snippet in this directory. English.

```markdown
## NixOS host notes

You run on NixOS as `hermes`; the systemd unit's PATH is the hermes-agent
closure, not the system. To use a tool: `nix-env -iA nixpkgs.<attr>` (writes
to `~/.nix-profile`, no sudo), or `nix-shell -p <pkg> --run '…'` for one-off,
or absolute path `/run/current-system/sw/bin/<tool>`. Don't `nixos-rebuild`,
don't touch `/nix/store`.
```

## Why this wording

Three primitives, one line each, in order of frequency. The lead sentence
explains *why* PATH is narrow (so the model doesn't reach for `sudo` or
`apt`). Don'ts are last and merged into one sentence — they're guardrails,
not the main story.

## Where it lives in the prompt

Slot next to the `ccr-retrieval.md` snippet — both are operational notes
about the runtime environment.
