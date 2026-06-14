---
name: browser-verify
description: Use when verifying UI/frontend behavior in a real browser — golden-path and edge-case flows, console/network checks, visual evidence. Drives the browser via the token-efficient `playwright-cli`; escalates to chrome-devtools MCP only for deep inspection (Lighthouse, performance-trace analysis, heap/CPU profiling, network throttling) that no CLI exposes. Routed by canonical-sdlc Step 5.
layer: technique
needs: []
loading: deferred
---

# Browser Verify

## Overview

Runtime verification of browser behavior using **`playwright-cli`** — bionic's token-efficient browser driver. The CLI keeps browser state on disk and returns compact snapshots and file paths, so the full DOM and image binaries never enter context unless you explicitly read them. Driving a real browser this way costs a fraction of the same flow run through an MCP server (~27K vs ~114K tokens per task).

**Core principle:** Drive with the CLI; reserve the MCP for inspection the CLI can't do. An MCP server is an always-on context tax (its tool schemas load every session); a CLI is pay-per-call. For routine verification — navigate, interact, screenshot, read console/network — the CLI wins every turn. Deep inspection fires once per investigation, so the MCP's richer interface earns its cost only there.

**Violating the letter of this process is violating the spirit of this process.**

**Layer:** Technique (verification capability). Invoked by `canonical-sdlc` Step 5, or standalone whenever you need real-browser evidence rather than unit-test inference. Unit tests don't catch visual regressions, focus traps, contrast failures, or runtime console/network errors — this does.

## When to use vs escalate

| Need | Tool |
|---|---|
| Navigate, click, fill, type, select, drag, hover | `playwright-cli` (this skill) |
| Snapshot the DOM / accessibility tree for element refs | `playwright-cli snapshot` |
| Read console messages / errors | `playwright-cli console` |
| List network requests | `playwright-cli network` |
| Screenshot / PDF evidence | `playwright-cli screenshot` / `pdf` |
| Arbitrary assertions / waits via the Playwright API | `playwright-cli run-code` / `eval` |
| **Lighthouse audit, performance-trace *analysis*, heap/CPU profiling, CrUX field data, network throttling emulation** | **escalate → `agent-skills:browser-testing-with-devtools` (chrome-devtools MCP)** |

The bottom row is the **only** sanctioned MCP use in this skill. If a `playwright-cli` command covers the need, the MCP is not justified.

## Setup (once per environment)

```bash
playwright-cli install            # initialize the workspace
playwright-cli install-browser    # install the browser binary (chromium)
```

If the target is a local app, start the dev server first (or run it in the background) and verify it answers before driving.

## Procedure

Work in a **named session** so a multi-step flow shares one browser:

```bash
S="verify-<wave-slug>"
playwright-cli -s="$S" open http://localhost:3000
```

1. **Reconnaissance before action.** After navigating, settle the page, then snapshot to get element refs — never guess selectors.
   ```bash
   playwright-cli -s="$S" run-code "async (page) => { await page.waitForLoadState('networkidle'); }"
   playwright-cli -s="$S" snapshot
   ```
   The snapshot returns stable `ref`s (accessibility-tree handles). Use those refs for every interaction.

2. **Drive the golden path.** One action at a time; re-`snapshot` after any action that changes the DOM.
   ```bash
   playwright-cli -s="$S" fill <ref> "user@example.com"
   playwright-cli -s="$S" click <ref>
   playwright-cli -s="$S" run-code "async (page) => { await page.waitForLoadState('networkidle'); }"
   playwright-cli -s="$S" snapshot
   ```

3. **Capture runtime health.** A page can look right and still be broken — check the two channels unit tests can't see:
   ```bash
   playwright-cli -s="$S" console error     # console errors/warnings
   playwright-cli -s="$S" network            # requests — look for 4xx/5xx, failed loads
   ```

4. **Capture visual evidence** straight to the ephemeral workspace (`--filename`; add `--full-page` for the whole scroll height):
   ```bash
   playwright-cli -s="$S" screenshot --filename .bionic/tmp/evidence-<slug>-golden.png
   ```

5. **At least one edge case.** Drive a failure or boundary path (invalid input, empty state, error response) and confirm the UI handles it — capture its evidence too.

6. **Close the session** when done:
   ```bash
   playwright-cli -s="$S" close
   ```

## Robustness rules

- **Always settle before inspecting.** On dynamic apps, `run-code "async (page) => { await page.waitForLoadState('networkidle'); }"` (or `waitForSelector(...)`) before `snapshot` — otherwise you read a half-rendered DOM and chase phantom failures. `run-code` takes a `(page) => {...}` function; `eval` takes `() => expr`.
- **Refs, not guesses.** Drive off `snapshot` refs. If a ref goes stale after a DOM change, re-`snapshot`.
- **Console + network are non-optional.** Visual pass ≠ runtime pass. A clean screenshot over a 500 response is a failed verification.
- **One assertion channel must be objective.** A screenshot is evidence a human reads; pair it with a `console`/`network` check or an `eval` that returns a boolean you assert on (e.g. `eval "() => document.querySelector('.success') !== null"`) — don't rely on the pixels alone.
- **Reuse auth instead of re-logging-in.** `state-save <file>` once, then `state-load <file>` in later sessions.

## Evidence

Write interim artifacts to `.bionic/tmp/` (gitignored) and record the path in the plan's Step 5 block under the **`devtools-trace:`** key (the key name is historical — the artifact is a `playwright-cli` capture, which is fine):

```
Step 5:
  devtools-trace: .bionic/tmp/evidence-<slug>-golden.png
```

For non-UI waves, the Step 5 block is `n/a: <reason>` instead. **End-to-end closure floor:** for any wave whose value is user-visible behavior change, the evidence must trace user input → new code (file:line per hop); `n/a: substrate-only` is a red flag requiring explicit justification.

## Deep-debug escalation

When — and only when — you need Lighthouse scores, interpreted performance traces, heap/CPU profiles, CrUX field data, or network-throttling emulation, escalate to `agent-skills:browser-testing-with-devtools`, which drives the **chrome-devtools MCP** (≈33 tools, CDP-level introspection). State in the plan *why* the CLI was insufficient. Return to `playwright-cli` for any further driving.

## Red flags (stop and correct)

| Thought | Reality |
|---|---|
| "Unit tests cover it, I can skip browser verify." | Unit tests miss visual regressions, focus traps, contrast, and runtime console/network errors. |
| "The screenshot looks right, done." | Check `console error` and `network` — a clean pixel over a failed request is not a pass. |
| "I'll just use the chrome-devtools MCP to click around." | Driving is the CLI's job. The MCP is for inspection the CLI can't do (Lighthouse, perf analysis, profiling). |
| "I'll guess the selector." | Snapshot first; drive off refs. Guessed selectors cause flaky, token-wasting retries. |
