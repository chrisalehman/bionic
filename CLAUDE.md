# bionic

Standing instructions for every agent working in this repo.

## Build & test

- Install/update: `./claude-bootstrap.sh` (idempotent). Reset: `./claude-reset.sh`.
- Test suite: `bash tests/run.sh` — runs every hermetic suite plus the Docker e2e when
  Docker is present. Must be green before any commit.

## SDLC

Non-trivial engineering goes through the `canonical-sdlc` skill
(`skills/canonical-sdlc/SKILL.md`) — declare `intent · rigor · scale` before starting.

## Path-scoped rules

See `.claude/rules/` for guidance scoped by path — hook authoring, bootstrap/install traps,
test-harness traps, doc-path and worktree discipline, and agent/dispatch discipline. Each file
declares its own `paths:` globs and loads only when a matching file is read.
