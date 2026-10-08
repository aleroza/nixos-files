# CCR retrieval (master-prompt block)

Add to the master system prompt alongside the existing `focus` / `foresight`
directives. Replaces any earlier ad-hoc wording on this topic. English.

```markdown
## CCR retrieval

- See `<<<CCR:hash|type|size>>>` → call `aphrodite_retrieve(hash)`. Do not
  write it to `/tmp`. Do not `read_file` it. The marker is the content.
- If `aphrodite_retrieve` returns `found: false`: try once more, then
  `aphrodite_search`/`aphrodite_catalog` for context. If still nothing,
  ask the user — do not fall back to `terminal > /tmp`.
- The only legitimate use of `terminal ... > /tmp/foo && read_file` is for
  content you produced yourself (downloads, generated artifacts) that was
  never a tool output.
- `read_file` reads disk. CCR markers are not on disk. Conflating them is
  the failure mode to avoid.
```

## Why this wording

- **Imperative, not introspective.** Tested prompt patterns: `on a marker,
  do X` outperforms `ask yourself whether to do X` because the latter
  defers the decision and the model falls back to its prior habit (which
  in this codebase was `terminal > /tmp && read_file`).
- **Failure rule is explicit, not open-ended.** A previous draft said
  "if `found: false`, search to clarify" without specifying the search
  key, training a vague reflex. This version names the actual fallback
  chain: `retrieve` → `retrieve` → `search`/`catalog` → ask user.
- **Exception is one, not two.** A previous draft allowed `terminal > /tmp`
  for "fresh downloads not yet in store". This is so rare in practice that
  naming it teaches the wrong default. The single real exception is
  self-produced files (downloads, generated artifacts) — narrowed to that.
- **Last bullet names the failure mode.** Putting `read_file` and CCR
  markers in the same mental category is what causes the model to write
  markers to /tmp. Calling out the conflation directly is cheaper than
  relying on the model to infer the difference.

## Where it lives in the prompt

Slot it directly under the existing `focus` directive block, before
`foresight`. Both directives refer to CCR markers; this block is the
operational counterpart (what to do when the focus/foresight rules
encounter an unfamiliar situation).
