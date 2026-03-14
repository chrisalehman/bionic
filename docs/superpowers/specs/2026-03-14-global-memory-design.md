# Global Memory Management — Design Spec

## Context

Claude Code reads `~/.claude/CLAUDE.md` as global instructions applied to every session across all projects. The claude-setup project currently manages plugins, marketplaces, and custom skills but has no mechanism for managing global behavioral rules. Engineers accumulate useful feedback as per-project auto-memories, but universal rules (like "always run code review before push") stay siloed in individual projects.

This feature adds global memory management to the bootstrap system: a curated set of behavioral rules shipped as opinionated defaults, installed to `~/.claude/CLAUDE.md`, config-driven so engineers can opt in or out.

## Design

### Config entry

New type in `claude-config.txt`:

```
global-memory | claude-global.md
```

Single field: filename relative to repo root. Follows the same single-value pattern as `marketplace` entries. The callback receives the filename as its first argument (second argument is empty, same as `do_install_marketplace`). Header comment updated:

```
#   global-memory |  filename
```

If the line is commented out or removed, bootstrap skips global memory entirely.

### Source file — `claude-global.md`

Markdown file in repo root with curated behavioral rules:

1. **Code Review Before Push** — Always invoke code review before `git push`
2. **Don't Start Duplicate Dev Servers** — Check if a server is already running before starting one
3. **Don't Delete Generated Outputs** — Never delete PDFs, diagrams, images without explicit confirmation
4. **Clean Working Directory** — Scripts/tools must not leave intermediary files
5. **Reviews Must Check Conventions** — Code reviews must check file placement, naming, structure — not just correctness

Engineers edit this file to add/remove rules. Changes take effect on next bootstrap run.

### Bootstrap behavior (`claude-bootstrap.sh`)

New function `do_install_global_memory(file, _)`:

1. Validate source file exists: `${SCRIPT_DIR}/${file}`. If missing, print error and exit (consistent with `set -euo pipefail` behavior).
2. Ensure target directory exists: `mkdir -p ~/.claude`
3. Read source file content
4. Build marked section: `<!-- claude-setup:start -->\n` + content + `\n<!-- claude-setup:end -->`
5. If `~/.claude/CLAUDE.md` doesn't exist: create it with the marked section
6. If markers already exist: replace everything between them (inclusive) with the new marked section. Use `awk` for safe literal string replacement (no regex interpretation of source content).
7. If file exists but no markers: append a blank line followed by the marked section (prevents running into existing content)

Idempotent: re-running replaces only the managed section, preserving any personal content outside markers.

New script section between Plugins and Custom Skills:

```
Global memory:
  claude-global.md → ~/.claude/CLAUDE.md... ✓
```

### Reset behavior (`claude-reset.sh`)

New function `do_remove_global_memory(file, _)`:

1. If `~/.claude/CLAUDE.md` doesn't exist: print `✓ (already removed)`
2. Remove everything from `<!-- claude-setup:start -->` through `<!-- claude-setup:end -->` (inclusive). Use `awk` for safe removal (matching `do_install_global_memory`).
3. If file contains nothing but whitespace after removal: delete it entirely. Otherwise leave personal content intact.

New script section between Custom Skills and Plugins (reverse of bootstrap order: bootstrap is Marketplaces → Plugins → Global Memory → Custom Skills, reset is Custom Skills → Global Memory → Plugins → Marketplaces):

```
Global memory:
  ~/.claude/CLAUDE.md... ✓
```

### Files changed

| File | Change |
|---|---|
| `claude-global.md` | **New.** Source file with 5 curated behavioral rules |
| `claude-config.txt` | Add `global-memory \| claude-global.md` entry + update header comment |
| `claude-bootstrap.sh` | Add `do_install_global_memory` function + `read_config "global-memory"` section between Plugins and Custom Skills |
| `claude-reset.sh` | Add `do_remove_global_memory` function + `read_config "global-memory"` section between Custom Skills and Plugins |
| `README.md` | Add Global Memory section between Subagent Plugins and Custom Skills, documenting: what global memory is, how to customize it, how markers work |

### Verification

1. Run `./claude-reset.sh --all` to clean slate
2. Run `./claude-bootstrap.sh` to install everything
3. Verify `~/.claude/CLAUDE.md` exists with content between markers
4. Re-run `./claude-bootstrap.sh` — verify idempotency (no duplication)
5. Add personal content above/below markers, re-run bootstrap — verify personal content preserved
6. Run `./claude-reset.sh` — verify only managed section removed, personal content preserved
7. Create `~/.claude/CLAUDE.md` containing only the managed section (no personal content), run reset — verify file is deleted entirely
8. Comment out `global-memory` line in config, run bootstrap — verify global memory skipped
