---
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/remove.sh:*)
description: Consented teardown of the bionic machine footprint, finishing with the native plugin uninstall.
---
<!-- GENERATED FILE — DO NOT EDIT.
     Rendered from agents-src/templates/commands/remove.md.tmpl and the shared blocks in
     agents-src/blocks/. Edit those, then re-render; the render check goes red whenever
     this file and its sources disagree. -->

<!-- VOICE-CONTRACT-BEGIN -->
Presentation contract — what the user sees from this command:
- Relay the script's questions exactly as asked; pass the user's answer as given.
  Never answer for the user, never editorialize.
- Show the script's output exactly as it came back, in one block, unchanged — never
  retype, trim, reorder or summarize it. Add NO closing line of your own: the script's
  last line is the conclusion, and restating it is the repetition the user reads as
  noise. Say nothing about shells, stdin, pipes, re-runs, hooks, tool calls, or what
  you did.
- On a real error show the error verbatim and the fix, in one block. Never
  paraphrase an error away or bury it under a summary.
- At most one caveat line, only if it changes what the user should do next
  (e.g. "Takes effect after /reload-plugins or a new session.").
- Product words only. Never print internal names: lanes, letter-number codes,
  hook or function names, step identifiers.
<!-- VOICE-CONTRACT-END -->

Run this once, with no flags:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/remove.sh
```

It asks about one item at a time and treats every question it cannot put to a person as a
no, so a first run removes nothing and reports what it would have asked. Show the user each
question it printed, word for word, one at a time, and wait for their answer. Never answer
one for them and never guess which one they meant.

When the user says yes to a question, do that one item and nothing else. Every question
names its own item, and each declined line repeats the name beside the command that runs it:

```bash
printf 'y\n' | bash ${CLAUDE_PLUGIN_ROOT}/scripts/remove.sh --only <item>
```

`bash ${CLAUDE_PLUGIN_ROOT}/scripts/remove.sh --list` prints the item names on their own.

When the user asks for the whole teardown rather than one item, one run can carry it:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/remove.sh --all
```

It prints everything it would do and asks one question over that list.
Use --all only when the user asks for everything; relay its one question verbatim.

A declined item is finished, not deferred: never work around a no, never re-ask it, and
never remove something the user did not accept.
