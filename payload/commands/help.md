---
description: bionic overview — what it is, the command roster, and where to start.
---
<!-- GENERATED FILE — DO NOT EDIT.
     Rendered from agents-src/templates/commands/help.md.tmpl and the shared blocks in
     agents-src/blocks/. Edit those, then re-render; the render check goes red whenever
     this file and its sources disagree. -->

<!-- VOICE-CONTRACT-BEGIN -->
Presentation contract — what the user sees from this command:
- Relay the script's questions exactly as asked; pass the user's answer as given.
  Never answer for the user, never editorialize.
- Show the script's output exactly as it came back, in one block, unchanged — never
  retype, trim, reorder or summarize it. Your own words are the one closing line. Say
  nothing about shells, stdin, pipes, re-runs, hooks, tool calls, or what you did.
- On a real error show the error verbatim and the fix, in one block. Never
  paraphrase an error away or bury it under a summary.
- At most one caveat line, only if it changes what the user should do next
  (e.g. "Takes effect after /reload-plugins or a new session.").
- Product words only. Never print internal names: lanes, letter-number codes,
  hook or function names, step identifiers.
<!-- VOICE-CONTRACT-END -->

Render the page below in full, verbatim, every time this command runs — even if it was
shown earlier in this session; never summarize it or refer back to an earlier rendering.

bionic 0.1.0 (installed)

# bionic

Bionic is a Claude Code plugin that carries canonical-sdlc guardrails, hooks, and
agent-orchestration discipline into any project you work on with Claude Code. It travels
with you rather than with a repository: install it once and every project you open gets
the same working discipline.

## Commands

- `/bionic:help` — this page: what bionic is, the command roster, and where to start.
- `/bionic:setup` — idempotent machine setup, one consented item at a time.
- `/bionic:doctor` — read-only diagnosis of this machine; it changes nothing.
- `/bionic:remove` — consented teardown, finishing with the plugin uninstall.

## It arrives in two steps

- **Tier 1 — the plugin install.** Installing bionic gives you the whole core: the skill,
  the hooks, the agent roster. Nothing further is required to start using it.
- **Tier 2 — `/bionic:setup`.** Adds what installing a plugin cannot: the tools bionic's
  workflows reach for, your shell environment, and a permission profile. It asks before
  every change and can be run again any time.

## Where to start

- Run `/bionic:doctor` first. It reports what this machine already has and what is
  missing, and it never changes anything.
- Run `/bionic:setup` for anything doctor says is missing.
- If something looks wrong later, `/bionic:doctor` again is the place to look.
