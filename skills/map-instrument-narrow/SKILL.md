---
name: map-instrument-narrow
description: Use when debugging requires understanding unfamiliar system internals before instrumentation will be interpretable — especially async execution, third-party library code, state mutations with no obvious code path between cause and effect, prior failed fix attempts, OR any diagnostic friction in a canonical-sdlc run
layer: technique
needs: []
loading: deferred
---

# Map-Instrument-Narrow

Three phases produce a data-confirmed root cause before any fix code is written. Default route for failing tests, bugs, and surprising behavior; `superpowers:systematic-debugging` still owns the scientific-method loop this technique feeds.

## Rigor Mandate

Run under this directive **verbatim**. It is the canonical source: orchestrators (e.g. `canonical-sdlc`) MUST inject it verbatim into every diagnostic-friction subagent prompt — see that skill's `## Dispatch` section. This blockquote is the only copy; there is no second source.

> **Execute map-instrument-narrow with exquisite rigor and discipline. Absolutely no corner-cutting.** Walk every phase gate in order — MAP → INSTRUMENT → NARROW — and write each phase's artifact before advancing past its gate. No fix code, and no "let me just try one thing first." No ad-hoc, trial-and-error theory-hopping: the data names the root cause, not your hunches. NO FIX CODE WITHOUT DATA. NO INSTRUMENTATION WITHOUT ARCHITECTURE.

## When to Use

Any one hard trigger, or two or more soft triggers, invokes this skill. Neither: use `superpowers:systematic-debugging` Phase 1 directly. `canonical-sdlc` loads this skill on the FIRST diagnostic friction event — not after a speculative fix has failed.

**Hard triggers (any one):**
- Prior fix attempt failed without clear understanding of why
- Bug involves async/deferred execution (rAF, setTimeout, Promise chains, event listeners)
- Root cause spans code you don't own (third-party library internals)

**Soft triggers (two or more):**
- State is correct at point A but wrong at point B with no visible code path connecting them
- A "fix" works in isolation but gets overridden by something else
- Multiple interacting subsystems (3+ layers)
- Prior session attempted fixes without measurement data

## Phase 1: MAP

**Goal:** build architectural understanding so instrumentation data will be interpretable. **Dispatch parallel research agents:**

| Agent | Role | Deliverable |
|-------|------|-------------|
| **Architect** | Read source code of the system under investigation — your code AND library internals | Written analysis: call chains, async boundaries, state ownership |
| **Git** | Assess current state — dirty files, recent changes, what's committed vs experimental | Categorized file list: keep vs experimental vs mixed |
| **Env** | Verify infrastructure readiness — services running, build state, test tooling | Readiness report with blockers |
| **State-Audit** | Verify inherited claims (handoff docs, prior agent assertions, checkpoint files, "95% done" claims) against actual repo state | Discrepancy list with evidence — what was claimed vs what is true now |

**The architect agent is the critical one.** It reads the library source for the mechanics that make data readable — deferred execution (`render()` behind `requestAnimationFrame`), hidden state writes (`setCameraCPU()` modifying translation), object replacement (`_updateToDisplayImageCPU()` swapping the viewport). Without this, instrumentation data is numbers without meaning.

**Phase 1 produces:** A written architectural artifact. "I have a mental model" is not evidence. Write it down.

## Phase 2: INSTRUMENT (Broad Capture)

**Goal:** capture the full state picture — "what IS happening?", not "why?" **Add diagnostic logging at key state boundaries:** state BEFORE the operation; state AFTER the operation; confirmation that fix/guard code executes; state at the symptom point (e.g., render time).

```typescript
// Example: broad capture at operation boundaries
console.warn(`[DIAG] PRE operation: state=${JSON.stringify(relevant_state)}`);
await theOperation();
console.warn(`[DIAG] POST operation: state=${JSON.stringify(relevant_state)}`);
```

**Run the test scenario. READ THE NUMBERS. Do not form hypotheses yet.** The broad capture answers: does the system enter the expected code path? Is the state correct before the operation? Does the operation change state as expected? Is the state still correct at the symptom point?

**Phase 2 produces:** Raw diagnostic data showing the state at each boundary. The GAP — where state goes from correct to incorrect — should be visible.

## Phase 3: NARROW (Targeted Per-Call)

**Goal:** find the exact mutation point within the gap identified in Phase 2. **Add per-call logging between the two boundary points:**

```typescript
// Example: narrow within setRenderParams
operationA();
console.warn(`[DIAG] AFTER-A: state=${readState()}`);

operationB();
console.warn(`[DIAG] AFTER-B: state=${readState()}`);

operationC();
console.warn(`[DIAG] AFTER-C: state=${readState()}`);
```

**Run the test scenario. The data identifies the single culprit.** If AFTER-A shows correct state and AFTER-B shows incorrect state, the mutation is inside operationB.

**Phase 3 produces:** A definitive root cause statement with data evidence: "operationB mutates state from X to Y because [mechanism from MAP phase]."

## Constraints

- **No fix code during MAP or INSTRUMENT** (you are observing, not treating), and none during NARROW until the data names a single culprit.
- **Each phase produces a written artifact:** architecture analysis, diagnostic data, root cause statement — written before advancing past that phase's gate.
- **Instrumentation is disposable.** Remove or commit separately from the fix. Never ship diagnostic logging unless explicitly asked.
- **One test run per phase.** Broad capture = one run. Targeted narrowing = one run. If you need more than two test runs to find root cause, your MAP phase was incomplete — go back and research more.

## Phase Gates

### MAP → INSTRUMENT gate

- [ ] Written architecture artifact exists (file, not "in my head")
- [ ] Full call chain from trigger to symptom described, with async boundaries and state owners named explicitly at each step
- [ ] If multi-system (multiple engines / viewports / frames / runtimes): parity matrix exists showing how each system implements the relevant call chain
- [ ] Inherited claims (handoff docs, prior agent assertions, checkpoint files) verified against current repo state — discrepancies recorded

### INSTRUMENT → NARROW gate

- [ ] Probes captured at least one full scenario run
- [ ] Two adjacent boundaries show correct → incorrect transition
- [ ] No fix code has been written
- [ ] If pre-existing log volume exceeds your channel's cap (e.g., test-runner console limits) or drowns probes: existing noise has been silenced first
- [ ] If async/race: probes include monotonic timestamps + per-event sequence numbers + lifecycle events

### NARROW → FIX gate

- [ ] Single function/call identified as the mutation point
- [ ] WHY explained using MAP architecture (not just "X mutates Y" but "X mutates Y *because* the async boundary in `<location>` does Z")
- [ ] Conceptual significance written: one paragraph in plain language stating what this means for the system, whether scope changes, whether prior assumptions were wrong

**FIX → SCOPE-EXPANSION gate.** If you are tempted to apply the same fix pattern to sibling callsites (other engines, other viewports, other frames), that is a **new debugging problem**, not a continuation. Re-run MAP for the sibling scope. Cross-system parity from the MAP→INSTRUMENT gate makes sibling regressions visible before they ship.

## Recursive Root-Cause Detection

One pass finds one root cause; real defects often have **more than one**. After NARROW names a culprit, answer two questions from the MAP architecture:

1. **Is this cause itself caused by something upstream? (depth)** "The guard is missing" is proximate; "the guard was never wired because the initializer returned early" is deeper; "the initializer returned early because config loaded async" is deeper still. Each layer is a *new* root-cause investigation.
2. **Are there sibling causes the same symptom is hiding? (chain)** Fixing cause A can unmask cause B that A was masking. Two independent mutations can produce one symptom.

If the answer to either is yes, the deeper/sibling cause is a **fresh debugging problem** — it earns its own MAP-INSTRUMENT-NARROW pass, not a continuation of this one. Do not reason about it from the current, now-contaminated context (you have read fix code, mutated state, and formed theories).

**The root-cause tree.** Record every cause as a node so the investigation is auditable and an orchestrator can drive the recursion:

```
{ id, statement, evidence, kind: "proximate" | "deeper" | "sibling",
  parent_id, children: [], status: "open" | "confirmed" | "fixed" }
```

- The first NARROW result is the root node (`kind: proximate`, `parent_id: null`); a depth finding adds a child under the current node (`kind: deeper`); a chain finding adds a sibling under the same parent (`kind: sibling`).
- A node is `confirmed` only when its own NARROW gate passed with data evidence.

**Who runs the recursion:**

- **Standalone use** (direct invocation): when a node spawns children, run a fresh MAP-INSTRUMENT-NARROW pass for each, depth-first, and keep the tree in your working notes.
- **Under an orchestrator** (`canonical-sdlc` autonomous mode): do NOT recurse in place. Emit the confirmed node plus its open children as structured candidates and hand them back. The orchestrator owns the tree and dispatches a **fresh subagent per candidate** (clean context, same Rigor Mandate). See that skill's `## Escalation` section.

**Termination.** Stop descending when a node has no upstream cause you can name from data (a **terminal** root cause), OR at depth 4, OR when a deeper cause expands scope beyond the current task — at which point surface the tree to the user rather than auto-recursing further. Apply a fix per confirmed node; the whole tree feeds the RCA as "root cause" + "contributing factors" / "root-cause chain."
