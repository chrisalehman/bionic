---
paths:
  - ".bionic/docs/**"
  - ".worktrees/**"
---

# Doc paths and worktree discipline

Migrated from `.bionic/memory/git-rules.md` (epic-12 wave-01 slice 6) with the correction
ledger applied.

## Gitignored doc paths

- **The root `docs/` directory was deleted 2026-07-16** (user-directed): `docs/bionic/`
  migrated to `.bionic/docs/`, stale April-era `docs/superpowers/` removed. If a superpowers
  skill wants to write specs/plans under `docs/superpowers/`, redirect to `.bionic/docs/`
  (canonical-sdlc layout) — do not recreate the root docs tree, and never git-commit plan/spec
  artifacts.

- **Canonical-sdlc artifacts live in `.bionic/docs/{specs,plans,adrs,incidents}/epic-NN-<slug>/`**
  (default docs-root since 2026-07-16; the `docs/bionic/` override is retired). Directory-per-epic
  layout: `epic.plan.md` + `wave-NN-<slug>.plan.md` + `continuation.md` at the epic-dir root;
  parallel `specs/` and `adrs/` trees. Zero-padded epic numbers, kebab-case slugs. The
  evidence-gate hook descends 2 levels to find nested plans; the governing-skill hook enforces
  frontmatter on artifact-named files under these paths. Both dirs are gitignored.
  (Supersedes the 2026-04-16 rule about the hook only scanning `~/.claude/plans/`.)

- **The operational record lives under `.bionic/docs/` too, path-addressed only.**
  `.bionic/docs/record/` holds the running session log, rotated archives, the inert
  `sdlc-v11-audit.md`, and closed-wave handoffs; `.bionic/docs/ideas/` holds deferred-work
  briefs. Nothing loads any of it unprompted — cite the path explicitly or it is not read.
  *(New 2026-07-27, epic-12 wave-01: this replaced the always-loaded `.bionic/memory/`
  notebook tier.)*

## Worktree path resolution

- **`git worktree add` resolves relative paths against pwd, not against the repo root.**
  Running `git worktree add .worktrees/<new> main` from inside `.worktrees/<current>/` creates
  a NESTED worktree at `.worktrees/<current>/.worktrees/<new>/` instead of a sibling. When
  chaining waves in a single session, `cd` to the repo root (or use an absolute path to
  `.worktrees/<name>`) before each `git worktree add`. Caught and recovered 2026-05-03 by
  `git worktree remove` + `git branch -D` + re-create. *(Correction 2026-07-27: the original
  text hardcoded a `/Users/<name>/workspace/personal/bionic` path that does not exist on this
  machine. Resolve the root with `git rev-parse --show-toplevel`; don't paste a literal.)*
