---
description: bionic overview — what it is, the command roster, and where to start.
---

# bionic

Bionic is a Claude Code plugin that carries canonical-sdlc guardrails, hooks,
and agent-orchestration discipline into any project you work on with Claude
Code.

## Commands

- `/bionic:help` — this page: what bionic is, the command roster, and where
  to start.
- `/bionic:setup` — idempotent machine setup; wraps the native plugin install.
- `/bionic:doctor` — read-only diagnosis of the current install and machine
  state; never treats.
- `/bionic:remove` — consented teardown of bionic's machine footprint,
  finishing with the native plugin uninstall.

## Tiers

Bionic installs in two tiers:

- **Tier 1 — plugin install.** `claude plugin install bionic` alone yields a
  fully live core: skill, hooks, agents.
- **Tier 2 — environment setup.** `/bionic:setup` wraps tier 1 — it invokes
  the plugin install first, then does the environment work (dependencies,
  permissions, machine configuration) tier 1 alone doesn't cover. Tier 1 is
  contained in tier 2.

## Where to start

- Fresh machine → run `/bionic:setup`.
- Something looks wrong → run `/bionic:doctor`.
