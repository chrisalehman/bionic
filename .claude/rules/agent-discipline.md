---
paths:
  - "**/*.sh"
  - "**/*.md"
---

# Agent-behavior discipline

How Claude should operate in this codebase — authoring instruction files, dispatching
subagents, and choosing between overlapping skills. Its text was migrated from bionic's retired
memory tier (ADR-002) at epic-12 wave-01 slice 6, with the correction ledger applied.

**Routing note (slice 6 judgment call).** This is the weakest path-glob *fit* of the rules
files — most of it fires regardless of which file is being touched — and it is here because
`.claude/rules/` is the only channel measured to reach a dispatched subagent. *(Corrected
2026-08-18, epic-17 W4 S3: no longer the only one. A role file under `~/.claude/agents/`
reaches a dispatched agent too — measured by live readback — but it is snapshotted at CLI
start, so an edit lands on the NEXT session while this file lands on the next read. That
timing difference, not reach, is now what decides which channel a rule belongs in.)* Project
`CLAUDE.md` was measured **absent** from a fresh subagent this session despite being committed
before dispatch. Auto-memory is off by bionic's setup (`CLAUDE_CODE_DISABLE_AUTO_MEMORY`): a
correction becomes a rule in the file that owns it, and a dispatched subagent never receives
MEMORY.md (forks do), so nothing here is justified by it.

The globs are deliberately broad. Bionic is a shell-and-markdown repo, so `**/*.sh` +
`**/*.md` is close to "any work in this tree" — an imperfect glob on a proven channel beats a
clean glob on an unproven one. This is pay-per-read, not pay-per-session: nothing here loads
at session start, so AC-2 is unaffected. The cost is ~8 KB whenever a matching file is read.

## Discourse and judgment

- **Instruction files for Claude** (skills, agent prompts, path-scoped rules like this one):
  sentences naming Claude's default failure modes are TRIGGERS, not elaboration. "Obvious to a senior
  engineer" is the wrong rubric — the audience is the model, which needs the guardrail.
  Example: "Hypotheses without data produce circular debugging" earns its place because Claude
  defaults to hypothesis-patching without measuring, even though a human reader would already
  know that.

## Subagent dispatch

> **Moved (epic-17 W4, 2026-08-18).** Foreground-first and poll-don't-watch now live in
> `agents-src/blocks/survival.md`, rendered into all six `agents/*.md` role files, so a
> dispatched agent carries them in its own role definition instead of reading them here.
> Live readback and the propagation measurement: `.bionic/docs/record/epic-17-w4/s3-report.md`.
> **Updated (epic-23 wave-12 T3, 2026-09-13).** The brief scaffold itself now also lives in the
> role files and in `skills/canonical-sdlc/dispatch.md` (`agents-src/blocks/brief-scaffold.md`,
> rendered into all seven surfaces). What stays below is the guidance those seven surfaces
> cannot carry — brief-authoring judgment addressed to whoever writes the dispatch, not the
> scaffold's own shape.

## Search, edit and session facts

- **Absence claims use `/usr/bin/grep`.** An absence claim needs `/usr/bin/grep`. The shell
  `grep` is ugrep and skips gitignored trees like `.bionic`. `grep -r payload/` never enters
  `hooks/` or `agents/` because they are symlinks, so search the real paths.
- **Deletion cost is in the references.** Removing a file is the easy half. Grep every
  manifest, fixture, README and cross-reference that names it, including `.txt` and config
  files.
- **CLAUDE.md resolves at session start.** The CLAUDE.md hierarchy is snapshotted once at
  session start and inherited by subagents. No agent can verify a CLAUDE.md edit inside the
  session that made it.
- **Permission rules prefix-match the literal command.** Bash permission rules prefix-match the
  literal command string, so a quoted path never matches an unquoted rule.
  `${CLAUDE_PLUGIN_ROOT}` does substitute in command-file `allowed-tools`.
- **Routing means invocation, not citation.** A skill is routed only when something loads it.
  A table that cites it is not a route. The mechanism is a doer at the step boundary, never a
  wall on the normal path.
- **Attended steps need attended test beds.** Steps 0-3 need a human present. Never judge a
  skill for an attended slot inside an unattended subagent, and never count 'needs a user'
  against it.
- **Amend safety.** Run `git log -1` before every `git commit --amend`. Parallel work can land
  a commit between two tool calls.

## Skill-creator pitfalls

- **`example-skills:skill-creator`'s `improve_description.py` is NOT a standalone tool** —
  it's a function inside `run_loop.py` that requires eval results as input. "Run just the
  description optimizer without the eval loop" is not a thing; the optimizer IS the loop.
  `run_loop.py` also creates UUID-suffixed test command files in `.claude/commands/` that need
  manual cleanup (`rm canonical-sdlc-skill-*.md` pattern) if aborted mid-run.
