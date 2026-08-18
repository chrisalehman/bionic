---
paths:
  - "claude-bootstrap.sh"
  - "claude-reset.sh"
  - "claude-config.txt"
  - "claude-global.md"
---

# Bootstrap install traps

> **STALENESS NOTICE (self-retiring, ADR-003 pattern — see
> `.bionic/docs/adrs/epic-17-plugin-conversion/adr-003-self-retiring-transitional-tests.md`
> for the precedent this follows).** This whole file describes the bootstrap era:
> `claude-bootstrap.sh`/`claude-reset.sh`-driven install, sync, and mirror mechanics.
> **Retirement trigger: W5's deletion of `claude-bootstrap.sh`.** When that lands, delete
> this file whole rather than editing it down piecemeal — nothing in it has a post-bootstrap
> successor content, and no partial edit is owed. Added epic-17 W4 S4, 2026-08-18.

Source of truth, install types, and blast radius. Migrated from `.bionic/memory/`
(epic-12 wave-01 slice 6) with the correction ledger applied.

## Source of truth — what you edit, and where

- **Edit `claude-global.md` in the bionic repo, run `./claude-bootstrap.sh` to sync.** Never
  edit `~/.claude/CLAUDE.md` directly. Bootstrap installs the global CLAUDE.md from
  `claude-global.md`; direct edits are silently overwritten on the next run.

- **Edit source in `bionic/skills/` and `bionic/hooks/`, not `~/.claude/`.** The user-level
  directories are bootstrap-installed mirrors, overwritten on every `./claude-bootstrap.sh`
  run. Any edit made directly to `~/.claude/skills/<name>/` or `~/.claude/hooks/<name>.sh`
  will be silently clobbered on the next bootstrap. Caught 2026-04-18 during canonical-sdlc
  v2 work, after editing the deployed mirror instead of the project source.

- **Run `./claude-bootstrap.sh` after every change, confirm 0 issues.** The pipeline checks
  idempotency, syntax, and installs cleanly. Don't assume a change deployed correctly; verify
  with a clean bootstrap run. **The repo's hooks are not the installed hooks** (proven live
  2026-07-26): `tests/run.sh` exercises `hooks/*.sh` in the tree, while `~/.claude/hooks/` is
  what actually gates tool calls, and nothing compares the two. A green suite says nothing
  about the machine's real behavior until bootstrap has run — after any hook change, deploy,
  then diff installed against repo before believing a gate is live.

- **Precedence rules in `claude-global.md` that reference specific skill IDs** (e.g.
  `superpowers:test-driven-development`) have no regression guard — if an upstream plugin
  renames a skill, the rule silently points at a phantom. When upgrading a referenced plugin,
  re-check the Skill precedence section against the new skill list.

- **Prose labels in `claude-global.md` that look "wrong" next to the code they describe may be
  intentional reader-facing capitalization, not bugs.** Don't normalize without user
  confirmation. *(Correction 2026-07-27: the cited instance — an `Updated:` prose label on
  line 42 against an `updated:` YAML key on line 44 — no longer exists; `claude-global.md` is
  38 lines and has no such pair. The general caution stands; the example is gone.)*

## Install types (2026-06-27, PR #12)

- **`brew-cask | <binary> | <cask>`** — installs a Homebrew cask via `brew install --cask`.
  Added because `gcloud` is `brew-cask | gcloud | gcloud-cli`: the `google-cloud-sdk` cask was
  **renamed to `gcloud-cli`** (old name 404s) and there is **no `gcloud` formula**, so the
  prior `brew-dep | gcloud` failed on every fresh machine. Casks are macOS-only (don't exist
  on Linux/Docker).
- **`pnpm-store | <pkg>`** — pre-warms the pnpm content-addressable store
  (`pnpm store add <pkg>@latest`) so `pnpm add <pkg>` in a project hard-links
  instantly/offline. Used for `motion`. It does **not** make the lib importable without a
  per-project `pnpm add` — it's a cache warm, not a global install.
- Both are install-only (like `brew-dep`): not undone by `claude-reset.sh`, intentionally
  excluded from the bootstrap/reset symmetry test.

## Install scopes

- **`local-command` install type installs globally to `~/.claude/commands/<name>.md`, not
  project-scoped.** Same applies to `local-skill` (installs to `~/.claude/skills/<name>/`).
  Every Claude Code session on the machine picks them up regardless of project directory.
  Project-scoped commands would need `<project>/.claude/commands/` — bionic's install layer
  doesn't support that path today.

## Bootstrap resilience (2026-06-27, PR #12)

- **The install phase must run to completion — never abort mid-run.** `claude-bootstrap.sh`
  installers record failures (`record_fail` → `INSTALL_FAILURES`) and continue instead of
  `exit 1`; network ops go through `run_retry` (exponential backoff); npm/uv/jq sections
  skip-not-abort when their tool is missing; an end-of-run summary lists failures and sets the
  exit code. Only genuine prereqs (missing `claude`) hard-fail up front.
- **One-command tests: `bash tests/run.sh`** (gating: a `hooks/*.test.sh` glob, plus the
  hand-listed `tests/scripts.test.sh`, `tests/installer-behavior.test.sh`,
  `tests/agent-roles.test.sh` and `lib/platform.test.sh`, plus the Docker mock e2e). Only the
  `hooks/` entry globs — a new top-level suite must be added to `tests/run.sh` by name or it
  silently never runs. No CI by design — manual + fast.
  **tart/macOS-VM was excised** (`bootstrap-e2e-docker.sh` mock run covers whole-script
  completion on a fresh OS; the one macOS-only cask is covered by `installer-behavior.test.sh`
  + the live Homebrew cask API).

## Bootstrap blast radius

- **Blast radius is `~/.claude/` only** *(corrected 2026-07-19; the pre-correction text
  described `~/.claude-other/` and `~/.claude-synthesis/` as live symlinked alternate homes —
  **they no longer exist**)*. `./claude-bootstrap.sh` updates the installed mirror in one
  place; there is no per-home isolation to reason about.
- **Still check for OTHER live `claude` processes before deploying a strict new hook.** Since
  v12 deleted grandfathering (2026-07-26), a deploy no longer spares in-flight plans: anything
  not on the supported version now blocks at both hooks. The only isolation boundary is "don't
  run bootstrap until other sessions are quiesced." Generalizes to every bootstrap that ships
  a strict-new-hook or destructive-skill change.

## Portable shell

- **BSD awk on macOS rejects newlines inside `-v var=value` assignments.**
  `awk -v add="line1\nline2" ...` errors with `newline in string` on Darwin (GNU awk accepts
  it). For multi-line splices in portable bash hooks/scripts, use a
  `{ head -n N; printf '%s' "$additions"; tail -n +M; } > tmp` pipeline instead of
  awk-with-multiline-vars. Caught 2026-05-02 in a portable shell-tool rewrite; tests passed on
  first try. Generalizes to every shell tool bionic ships — it targets both Darwin and Linux.

## Architecture diagram

- **`architecture.excalidraw` is manually authored and needs regeneration for install-layer
  changes** (new hooks, new install types, new managed files). It's not generated from code.
  After such changes, manually re-export the PNG via the `excalidraw-diagram` skill or by hand.
