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

## Restoring a mutated file under `payload/`

- **`git checkout -- <path under payload/hooks or payload/skills/canonical-sdlc>` restores
  NOTHING.** Both are symlinks — `payload/hooks -> ../hooks` and
  `payload/skills/canonical-sdlc -> ../../skills/canonical-sdlc` (verified with `ls -ld`, and
  recorded in `.bionic/docs/record/wave-verification-cannot-lie/research-code-map.md:13-14`). A
  checkout of a path *beneath* a symlink does not restore the real file, and the tree is left
  dirty.

- **What it cost.** Wave-01 slice S19b's planted-move proof restored a doctored `SKILL.md` with
  `git checkout -- payload/skills/canonical-sdlc/SKILL.md`; it restored nothing, and the NEXT plant
  then ran against a dirty tree, which would have voided the evidence had it not been caught
  (`.bionic/docs/record/wave-verification-cannot-lie/s19-report.md:304-309`). S19c re-confirmed the
  same fact with `ls -ld` and wrote every plant against the real path instead
  (`.bionic/docs/record/wave-verification-cannot-lie/s19c-report.md:269-273`). Routed here as a
  close-out item by plan A-33.

- **The rule.** Mutate and restore by the REAL path (`hooks/…`, `skills/canonical-sdlc/…`), restore
  with `git checkout -- .`, and prove the tree clean with `git status --porcelain` on **both sides
  of every plant** — before as well as after. This is the `checkout -- wipes uncommitted` lesson
  from the other direction: commit before mutating, and verify the restore rather than assuming it.

- **Why "both sides".** A restore that silently did nothing is invisible at the moment it happens
  and only shows up as a contaminated result one plant later. The check before the plant is what
  catches the previous plant's failed restore.
