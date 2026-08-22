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

bionic 1.0.0 (installed)

# bionic

A Claude Code plugin that carries canonical-sdlc guardrails, hooks, and agent
orchestration into any project you open. It travels with you, not with a repository:
install it once and every project gets the same working discipline.

## Commands

| command | what it does |
| --- | --- |
| `/bionic:help` | this page — the roster, and where to start |
| `/bionic:setup` | idempotent machine setup, one consented item at a time |
| `/bionic:doctor` | read-only diagnosis of this machine; it changes nothing |
| `/bionic:remove` | consented teardown, finishing with the plugin uninstall |
| `/bionic:canonical-sdlc` | engage the engineering lifecycle on a task |

## Skills — ship with the plugin

| skill | what it does |
| --- | --- |
| `/bionic:canonical-sdlc` | the governed lifecycle for non-trivial work — declares `intent · rigor · scale`, walks Steps 0–9, gates every commit on that step's evidence (`help` prints the axis tables) |
| `/bionic:map-instrument-narrow` | diagnostic discipline when the cause is not obvious — map the system, instrument it, narrow to a root cause before writing a fix |
| `/bionic:browser-verify` | verifies UI behavior in a real browser with semantic readback |

## Agents — ship with the plugin

Six roles canonical-sdlc dispatches by step. The model and effort each one runs at:

| role | runs at | what it is for |
| --- | --- | --- |
| `auditor` | opus · high | Independent Step-5 verification auditor — falsifies evidence at its declared tier, never reviews code |
| `critic` | opus · high | Independent Step-6 adversarial critic — falsifies the code and the claim it is ready to merge |
| `implementor` | sonnet · high | MECHANICAL slice execution under TDD discipline — the plan is literal, tests define done, ambiguity means stop and surface |
| `researcher` | sonnet · medium | Read-only codebase/docs exploration returning structured summaries with file:line citations |
| `senior-implementor` | opus · high | DISCRETIONARY slice execution under TDD discipline — judgment and taste licensed within slice scope, every resolution logged to the plan's Assumptions before commit |
| `test-runner` | sonnet · low | Mechanical test-suite execution and full result reporting |

## Installed by setup (third party)

`/bionic:setup` adds what a plugin install cannot: the tools these workflows reach for,
your shell environment, and a permission profile.

- **Plugins** — superpowers, agent-skills, impeccable.
- **Command-line tools** — git, node, pnpm, gh, jq, rg, uv, docker, aws.
- **On demand** — @playwright/cli, chrome-devtools, playwright-chromium, motion. These
  install themselves the first time a route needs one.
- **Optional** — ccstatusline, notebooklm, context7, @pencil.dev/cli.

Run `/bionic:doctor` for what this machine actually has, at which version, and from
which source.

## Start here

  fresh machine →  /bionic:setup           then restart the session
  something off →  /bionic:doctor          read-only, tells you the fix
  big task      →  /bionic:canonical-sdlc  declare intent · rigor · scale — the skill takes it from there
