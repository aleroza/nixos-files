# security module

System hardening and intrusion detection.

## What it configures

- Base hardening (sudo, sysctl, entropy)
- fail2ban

## Key options

- `security.enableFail2ban` — enable fail2ban (bool)
- `security.sudoRequirePassword` — require password for sudo (bool)
