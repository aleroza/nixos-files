# Hermes Agent startup checklist

This file is read by the boot-md hook on every gateway start. The
hook runs a quick health probe of the OpenViking memory provider and
notifies the first user in `TELEGRAM_ALLOWED_USERS` if anything is
degraded.

The hook only sends a message on degradation; healthy starts are
silent. This file is documentation for the operator — the hook
itself trusts the system to know what to do.

## What the hook does

1. Read `OPENVIKING_ENDPOINT` from the gateway environment.
2. Read the bearer from `OPENVIKING_API_KEY` (provided by
   `/opt/openviking/keys/user_key`).
3. Hit `/health` and `/ready` with a 3 s / 10 s timeout.
4. Hit a real-embedding endpoint (the OpenViking Admin API path
   that triggers a fresh Gemini embedding call) with a 15 s
   timeout.
5. If any of the above fails, send a Telegram message to the first
   user in `TELEGRAM_ALLOWED_USERS`. The message is non-noisy
   (`disable_notification=true`).
6. Else log `[boot-md] openviking probe ok` and stay silent.

The hook is fire-and-forget — it runs in a background thread and
the gateway startup does not block on it.

## Customising

Edit `~/.hermes/hooks/boot-md/handler.sh` (or `hosts/aleroza-pc/
hermes/hooks/boot-md/handler.sh` in the Nix source tree). The
template lives in `modules/services/hermes-openviking-probe/` and
is symlinked into `~/.hermes/hooks/` at activation time.

To disable the hook entirely, delete `~/.hermes/hooks/boot-md/`
and restart the gateway. The hook loader silently skips missing
hooks.
