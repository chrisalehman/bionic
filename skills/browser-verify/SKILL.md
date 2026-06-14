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

### Server lifecycle (local apps)

Never drive a URL that isn't answering yet — a race against server startup is the most common false failure. Start the server, **wait for the port**, drive, then tear it down so you don't leak a process:

```bash
URL="http://localhost:3000"
npm run dev >/tmp/devserver.log 2>&1 &   # background the server
SERVER_PID=$!
# wait up to ~30s for it to answer, then proceed
for i in $(seq 1 30); do curl -sf -o /dev/null "$URL" && break || sleep 1; done
curl -sf -o /dev/null "$URL" || { echo "server never came up:"; tail -20 /tmp/devserver.log; kill "$SERVER_PID"; exit 1; }

# ... run the verify procedure against "$URL" ...

kill "$SERVER_PID" 2>/dev/null   # teardown in all exit paths
```

Prefer the project's own start command (`npm run dev`, `pnpm dev`, `make serve`, etc.). If the server is already running, skip the start/teardown and just confirm it answers with the `curl` line.

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

3. **Capture runtime health — and assert on it.** A page can look right and still be broken. Check the two channels unit tests can't see, and turn each into a pass/fail, not a glance:
   ```bash
   # Console: the log header reports the counts — fail if any errors.
   playwright-cli -s="$S" console error
   #   header line: "Total messages: N (Errors: E, Warnings: W)" — require E == 0.

   # Network: collect any >=400 response on a reload. Empty result = pass.
   playwright-cli -s="$S" run-code "async (page) => { const bad=[]; page.on('response', r => { if (r.status() >= 400) bad.push(r.status() + ' ' + r.url()); }); await page.reload({ waitUntil: 'networkidle' }); return bad; }"
   #   a non-empty array (e.g. ["404 .../api/x", "500 .../y"]) is a failed verification.
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
- **Console + network are non-optional, and must be asserted, not glanced at.** Visual pass ≠ runtime pass. A clean screenshot over a 500 response is a failed verification. Use the step-3 idioms: require `Errors: 0` in the console header and an empty `>=400` array from the network reload. "Looked fine" is not evidence.
- **Always tear down the dev server.** If you started it, `kill` it on every exit path (success, failure, early return). A leaked server poisons the next run's port.
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
