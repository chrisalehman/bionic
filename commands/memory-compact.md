---
description: Compact .bionic/memory/ in the current project — consolidate, summarize, age-out. Size + age + sprawl audits.
---

# Memory Compact

On-demand compaction of `.bionic/memory/` in the current project. *Compaction* — consolidation, summarization, age-out — not just sweeping. Use when SessionStart nags about size, or whenever the notebook feels bloated.

The SessionStart hook at `~/.claude/hooks/memory-cleanup.sh` flags stale topical files and oversized `INDEX.md` / `context.md`. This command is the on-demand, broader pass that actually does the compaction.

## INDEX.md style guide (the target shape)

INDEX.md has **two sections** and nothing else:

- **Always Apply** — high-priority rules that always apply. ≤ 15 rules. One line each, ≤ 120 chars. If a rule needs more, it belongs in a topical file.
- **Deep Context** — pointers only, one line each: `- [file.md](file.md) — one-sentence hook`. No bodies, no quotes, no examples.

When a bullet outgrows one line, migrate it to a topical file and the INDEX entry becomes the Deep Context pointer.

## Step 1: Inventory

Confirm `.bionic/memory/` exists at the project root. If not, tell the user and stop — don't create one.

For every `.md` file in `.bionic/memory/`, note:
- Filename
- Byte size, line count
- `updated:` frontmatter date (if present)
- Whether `INDEX.md` links to it

## Step 2: Size audit

Flag any of:
- **INDEX.md** — > 30 Always Apply rules OR > 5 KB
- **context.md** — > 500 lines OR > 50 KB
- **Any topical file** — > 50 KB (split candidate)

## Step 3: Age audit

Topical files only (`INDEX.md` and `context.md` never expire):
- **Stale warning** — `updated:` > 30 days. Spot-check against the current codebase: bump the date if still accurate; rewrite or delete otherwise.
- **Hard-delete candidate** — `updated:` > 60 days. Propose deletion (requires user confirmation).

## Step 4: Sprawl audit (5 axes)

1. **Orphans** — files in the directory that `INDEX.md` does not link to. Either link them or delete them.
2. **Dangling references** — links in `INDEX.md` pointing to files that no longer exist. Remove the broken link.
3. **Duplicates** — the same rule or fact stated in two places. Pick one canonical home and remove the other copy.
4. **Oversized Always Apply** — bullets in `INDEX.md` → Always Apply that have grown into multi-paragraph explanations. These belong in their own topical file with a one-line Deep Context pointer left behind.
5. **Near-duplicates** — two topical files covering overlapping ground, or rules that paraphrase each other. Merge or pick a canonical home.

## Step 5: Compaction actions

Propose the following before executing. Group findings by action type; one line for the finding, one line for the recommended action. **Do not edit anything yet.** Wait for the user to confirm with "do it all", "skip X", or per-item responses.

- **(a) INDEX migration.** If INDEX.md > 30 rules, group bullets by topic. Migrate each group to a topical file (e.g., `testing-rules.md`, `git-rules.md`). Replace the INDEX bullet group with **one** Deep Context pointer line + a 1-sentence summary hook in the same line. Always Apply shrinks to ≤ 15 rules.
- **(b) context.md rotation.** If context.md > 500 lines, keep the last 7 days of sessions verbatim at the top. Archive older sessions into `archive-YYYY-MM.md` (one file per month — append into the existing one if present). Drop fully-completed work sections after archival.
- **(c) Age-out.** Topical files > 60 days untouched → propose deletion. User confirms per file.

## Step 6: Execute

Apply the approved changes. When creating or rewriting a topical file, keep the existing frontmatter shape:

```
---
name: ...
description: ...
updated: YYYY-MM-DD
---
```

Use today's date for any bump. When migrating a bullet group from INDEX.md into a new topical file, set `updated:` to today.

## Step 7: Report

Summarize what changed in 3–5 bullets. Include: rules migrated out of INDEX, files archived from context, files deleted by age-out, new topical files created. Done.

## Discipline

- If content is still accurate, just bump `updated:` — don't rewrite it.
- Don't reorganize the notebook's taxonomy or invent new rules — compaction follows the existing shape.
- If relevance is ambiguous, ask the user rather than guessing.
- Scope is `.bionic/memory/` only — do not touch `~/.claude/CLAUDE.md`, hooks, or other config.
- INDEX.md is the index, not a knowledge base. Bodies live in topical files.
