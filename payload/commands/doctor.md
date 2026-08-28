---
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh:*)
description: Read-only diagnosis of the bionic install on this machine — plugin integrity, tier state, dependencies, environment, and what to do about anything broken. Changes nothing.
---
<!-- GENERATED FILE — DO NOT EDIT.
     Rendered from agents-src/templates/commands/doctor.md.tmpl and the shared blocks in
     agents-src/blocks/. Edit those, then re-render; the render check goes red whenever
     this file and its sources disagree. -->

<!-- VOICE-CONTRACT-BEGIN -->
Presentation contract — what the user sees from this command:
- Relay the script's questions exactly as asked; pass the user's answer as given.
  Never answer for the user, never editorialize.
- Show the script's output exactly as it came back, inside a single fenced code
  block, unchanged — never retype, trim, reorder or summarize it, and never let it
  render as plain markdown prose: the script pads and indents its own columns, and
  only a fenced block keeps that whitespace intact. Add NO closing line of your own:
  the script's last line is the conclusion, and restating it is the repetition the
  user reads as noise. Say nothing about shells, stdin, pipes, re-runs, hooks, tool
  calls, or what you did.
- On a real error show the error verbatim and the fix, inside a fenced code block.
  Never paraphrase an error away or bury it under a summary.
- At most one caveat line, only if it changes what the user should do next
  (e.g. "Takes effect after /reload-plugins or a new session.").
- Product words only. Never print internal names: lanes, letter-number codes,
  hook or function names, step identifiers.
<!-- VOICE-CONTRACT-END -->

The closing SUMMARY is a list of things the user could do, not a list of things to do:
act on an item only if the user asks for it.

Run:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh
```

Show the report as printed. Ask nothing afterwards.
