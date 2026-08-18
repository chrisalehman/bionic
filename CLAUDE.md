# bionic

Standing instructions for every agent working in this repo.

## Build & test

- Install/update: `./claude-bootstrap.sh` (idempotent). Reset: `./claude-reset.sh`.
- Test suite: `bash tests/run.sh` — runs every hermetic suite plus the Docker e2e when
  Docker is present. Must be green before any commit.

## SDLC

Non-trivial engineering goes through the `canonical-sdlc` skill
(`skills/canonical-sdlc/SKILL.md`) — declare `intent · rigor · scale` before starting.
Docs and chores stay out.

## Path-scoped rules

See `.claude/rules/` for guidance scoped by path — hook authoring, bootstrap/install traps,
test-harness traps, doc-path and worktree discipline, and agent/dispatch discipline. Each file
declares its own `paths:` globs and loads only when a matching file is read.

`.claude/rules/` is **committed** (epic-17 W4, 2026-08-18) via a `.gitignore` negation pair —
the rest of `.claude/` (settings, local worktree state) stays gitignored as machine-local. A
fresh clone now carries the path-scoped channel; shipped-plugin-surface absorption (rendering
this discipline into the plugin's own agent files) is in progress this same wave — see
`.claude/rules/` for the current file set until that lands.
