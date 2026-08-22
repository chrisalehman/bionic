# bionic

Standing instructions for every agent working in this repo.

## Build & test

- Install/update: the plugin comes from this repo's own marketplace —
  `claude plugin marketplace add <path-or-repo>` once, then `claude plugin install
  bionic@bionic`. That is tier 1 and it is fully live on its own. `/bionic:setup` is
  tier 2 (dependencies, shell environment, permission profile), idempotent and consented
  per item; `/bionic:doctor` diagnoses without changing anything and `/bionic:remove`
  tears the footprint back down. The bootstrap installer and its reset script were
  deleted at epic-17 W5 — a change to a hook or a skill is not live for a session until
  the plugin the CLI resolved carries it.
- Test suite: `bash tests/run.sh` — runs every hermetic suite. Must be green before any
  commit.

## SDLC

Non-trivial engineering goes through the `canonical-sdlc` skill
(`skills/canonical-sdlc/SKILL.md`) — declare `intent · rigor · scale` before starting.
Docs and chores stay out.

## Path-scoped rules

See `.claude/rules/` for guidance scoped by path — hook authoring, test-harness traps,
doc-path and worktree discipline, and agent/dispatch discipline. Each file declares its own
`paths:` globs and loads only when a matching file is read.

`.claude/rules/` is **committed** (epic-17 W4, 2026-08-18) via a `.gitignore` negation pair —
the rest of `.claude/` (settings, local worktree state) stays gitignored as machine-local, so
a fresh clone carries the path-scoped channel and nothing else. Rules addressed to a
*dispatched agent* belong in `agents-src/blocks/` instead, which renders into the six role
files under `agents/` and ships with the plugin; the two channels differ in when an edit
lands (a rules file on the next read, a role file on the next session), not in reach.
`tests/scripts.test.sh` pins the roster of files here, so adding one is a deliberate act.
