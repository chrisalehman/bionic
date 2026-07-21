# Map-Instrument-Narrow

Bionic's debugging technique: three observation phases that produce a data-confirmed root cause *before* any fix code is written.

This is the human-facing reference. The skill prose Claude reads at runtime is in [`SKILL.md`](SKILL.md) — same directory.

> **TL;DR.** An observation constraint for debugging complex systems. Three phases — **MAP** (build architectural understanding so data is interpretable) → **INSTRUMENT** (broad state capture at boundaries, "what IS happening?") → **NARROW** (per-call logging to name the single culprit) — each with an explicit gate that must be answered before advancing. The Iron Law: **NO FIX CODE WITHOUT DATA. NO INSTRUMENTATION WITHOUT ARCHITECTURE.** A verbatim **Rigor Mandate** is what makes the technique work under pressure; orchestrators inject it unchanged into every diagnostic-friction subagent. One pass finds one root cause — **Recursive Root-Cause Detection** models defects as a root-cause tree (proximate / deeper / sibling, `max_depth: 4`) and gives each layer its own fresh pass. `canonical-sdlc`'s Autonomous Friction Protocol loads this skill on the first diagnostic-friction event, and its three-fail rule only fires *after* one full pass.

---

## Contents

- [Why this exists](#why-this-exists)
- [The three phases](#the-three-phases)
- [The Rigor Mandate](#the-rigor-mandate)
- [Phase gates](#phase-gates)
- [Recursive Root-Cause Detection](#recursive-root-cause-detection)
- [Integration with canonical-sdlc](#integration-with-canonical-sdlc)
- [When to use / when not to](#when-to-use--when-not-to)
- [Common rationalizations](#common-rationalizations)
- [Quick reference](#quick-reference)

---

## Why this exists

bionic bridges traditional engineering discipline with agentic engineering. Map-instrument-narrow is that bridge applied to debugging. The traditional half is root-cause discipline: understand the architecture first, instrument the state boundaries, and name the culprit with data — never a speculative fix. The agentic half is how it executes: parallel MAP research agents build the model, a fresh subagent runs each open root-cause candidate, and the orchestrator owns the root-cause tree. The discipline is old; the parallelism is new.

The failure mode it kills is the dominant one in agentic debugging, and it is not ignorance of the method — it is *abandoning the method under pressure*. Spinning through hypotheses, patching the first plausible theory, declaring victory before the data names a single culprit. Three names for the same anti-pattern:

- **Speculative fix before instrumentation.** Writing fix code before the architecture is mapped and the state is measured. This regresses pass rates more often than it improves them.
- **Ad-hoc theory-hopping.** Trial-and-error whack-a-mole where hunches, not data, drive each attempt.
- **"Let me just try one thing first."** The single most expensive move: that "one thing" mutates state, so any instrumentation added afterward captures *post-attempt* state, not the original bug. MAP before any state change.

The core principle: research makes data interpretable; data makes fixes obvious. Without the research you can't read the numbers; without the numbers you're guessing. The Iron Law states the ordering as a hard constraint:

```
NO FIX CODE WITHOUT DATA. NO INSTRUMENTATION WITHOUT ARCHITECTURE.
```

---

## The three phases

Each phase has a **goal**, an **action**, and a **completion gate**. No phase begins before the prior phase's gate is answered, and each phase produces a *written* artifact — "I have a mental model" is never evidence.

### MAP

- **Goal.** Build architectural understanding so instrumentation data will be interpretable.
- **Action.** Dispatch parallel research agents — an **Architect** (reads source of both your code and library internals: call chains, async boundaries, state ownership), a **Git** agent (keep vs. experimental vs. mixed file triage), an **Env** agent (services, build, test tooling readiness), and a **State-Audit** agent (verify inherited claims — handoff docs, "95% done" assertions, checkpoint files — against actual repo state). The architect is the critical one: it surfaces things like `render()` deferring through `requestAnimationFrame`, without which the numbers are meaningless.
- **Complete when.** You can describe the full call chain from trigger to symptom, including async boundaries and state ownership at each step. The artifact is a written architecture analysis.

### INSTRUMENT (broad capture)

- **Goal.** Capture the full state picture. Answer "what IS happening?" — not "why?"
- **Action.** Add diagnostic logging at key state boundaries: state before the operation, state after, confirmation that guard/fix code executes, and state at the symptom point. Run the scenario once and **read the numbers — do not form hypotheses yet.**
- **Complete when.** You can point to two adjacent diagnostic points where state is correct at one and incorrect at the other. The artifact is the raw diagnostic data with the gap visible.

### NARROW (targeted per-call)

- **Goal.** Find the exact mutation point *within* the gap the broad capture exposed.
- **Action.** Add per-call logging between the two boundary points, then run the scenario once. If `AFTER-A` is correct and `AFTER-B` is wrong, the mutation lives inside operation B — the fix is now informed by data, not guesswork.
- **Complete when.** You can name the single function/call that causes the mutation *and* explain why, using the architectural understanding from MAP. The artifact is a definitive root-cause statement with data evidence.

Two hard budget constraints span the phases: **no fix code during MAP, INSTRUMENT, or NARROW** until the data names a single culprit; and **one test run per phase** — broad capture is one run, targeted narrowing is one run. Needing more than two runs means MAP was incomplete: go back and research more. Instrumentation is disposable — remove it or commit it separately; never ship diagnostic logging unless asked.

---

## The Rigor Mandate

This is the directive that makes the technique work. When the skill is invoked — especially by an orchestrator dispatching a subagent — it runs under the following, **verbatim**:

> **Execute map-instrument-narrow with exquisite rigor and discipline. Absolutely no corner-cutting.** Walk every phase gate in order — MAP → INSTRUMENT → NARROW — and write each phase's artifact before advancing past its gate. No fix code, and no "let me just try one thing first." No ad-hoc, trial-and-error theory-hopping: the data names the root cause, not your hunches. NO FIX CODE WITHOUT DATA. NO INSTRUMENTATION WITHOUT ARCHITECTURE.

Why it is non-negotiable: the dominant failure mode is abandoning the method under pressure, and this directive is the thing that holds the line. Held to it, the technique reliably finds the true root cause — the rigor **is** the value, not an overhead on it.

The `SKILL.md` copy is the canonical source. By convention, orchestrators such as `canonical-sdlc` **MUST inject this string verbatim** into every diagnostic-friction subagent prompt — paraphrase is forbidden. The same text is mirrored in the project-local `.bionic/sdlc-dispatch-rules.json` (`diagnostic_friction.directive`; seeded per project, not part of this repo's tree) and referenced by canonical-sdlc's Subagent Dispatch Convention (point 8); orchestrators inject that exact string. Omitting it is the single most common cause of debugging that spins through ad-hoc theories instead of converging.

---

## Phase gates

Each phase has an explicit checklist that MUST be answered before advancing. Walking past a gate is the documented dominant failure mode.

**MAP → INSTRUMENT.** Written architecture artifact exists (a file, not "in my head"); async boundaries and state owners named explicitly; if multi-system (multiple engines / viewports / frames / runtimes), a parity matrix shows how each system implements the call chain; inherited claims verified against current repo state, discrepancies recorded.

**INSTRUMENT → NARROW.** Probes captured at least one full scenario run; two adjacent boundaries show a correct → incorrect transition; no fix code written; if pre-existing log volume exceeds the channel's cap or drowns the probes, the noise was silenced first; if async/race, probes include monotonic timestamps + per-event sequence numbers + lifecycle events.

**NARROW → FIX.** Single function/call identified as the mutation point; the *why* explained using MAP architecture (not "X mutates Y" but "X mutates Y *because* the async boundary in `<location>` does Z"); a one-paragraph conceptual-significance note in plain language — what this means for the system, whether scope changes, whether prior assumptions were wrong.

**FIX → SCOPE-EXPANSION.** Applying the same fix pattern to sibling callsites (other engines, viewports, frames) is a **new debugging problem**, not a continuation — re-run MAP for the sibling scope. The cross-system parity matrix from the MAP→INSTRUMENT gate makes sibling regressions visible before they ship.

---

## Recursive Root-Cause Detection

One pass finds one root cause. Real defects often have more than one, so after NARROW names a culprit you are not done until you have asked — and answered from the MAP architecture — two questions:

1. **Is this cause itself caused by something upstream? (depth)** "The guard is missing" is proximate; "the guard was never wired because the initializer returned early" is deeper; "the initializer returned early because config loaded async" is deeper still.
2. **Are there sibling causes the same symptom is hiding? (chain)** Fixing cause A can unmask cause B that A was masking; two independent mutations can produce one symptom.

If either answer is yes, that deeper/sibling cause is a **fresh debugging problem** — it earns its own MAP-INSTRUMENT-NARROW pass, not a continuation. Do not reason about it from the current, now-contaminated context (you have read fix code, mutated state, formed theories); a fresh pass with a clean head is what keeps each layer rigorous.

### The root-cause tree

Every cause is recorded as a node so the investigation is auditable and an orchestrator can drive the recursion:

```
{ id, statement, evidence, kind: "proximate" | "deeper" | "sibling",
  parent_id, children: [], status: "open" | "confirmed" | "fixed" }
```

- The first NARROW result is the root node (`kind: proximate`, `parent_id: null`).
- A depth finding adds a child under the current node (`kind: deeper`).
- A chain finding adds a sibling under the same parent (`kind: sibling`).
- A node is `confirmed` only when its own NARROW gate passed with data evidence.

**Who runs the recursion.** In standalone use (`ralph-loop`, direct invocation), run a fresh pass per child depth-first and keep the tree in your working notes. Under an orchestrator (an unattended `canonical-sdlc` wave) do **not** recurse in place: emit the confirmed node plus its open children as structured candidates and hand them back — the orchestrator owns the tree and dispatches a fresh subagent per candidate (clean context, same Rigor Mandate).

**Termination.** Stop descending when a node has no upstream cause you can name from data (a terminal root cause), OR at `max_depth` (default 4), OR when a deeper cause expands scope beyond the current task — at which point surface the tree to the user rather than auto-recursing. Apply a fix per confirmed node; the whole tree feeds the RCA as "root cause" plus "contributing factors" / "root-cause chain."

---

## Integration with canonical-sdlc

Map-instrument-narrow is the debugging engine of `canonical-sdlc`'s **Autonomous Friction Protocol**. When an unattended wave (Steps 4–9) hits friction, the orchestrator first classifies it:

- **Diagnostic friction** — direction is clear but the code misbehaves (test fails, behavior diverges from spec, surprise output). → MAP first.
- **Decision friction** — the direction itself is in question (which approach, abstraction, or scope). → surfaced via the User Decision Protocol, *not* this skill.

For diagnostic friction, the protocol loads this skill **immediately** and dispatches it to a fresh subagent carrying the verbatim Rigor Mandate — no speculative fix code first, no fix code until NARROW yields a named root cause with data evidence. The recursion on layered causes is orchestrator-owned: it records the root-cause tree in the plan's `## Assumptions` / RCA section and dispatches a fresh subagent per open candidate, bounded at `max_depth: 4`.

The **three-fail rule** interlocks with this. It fires only **AFTER** one full MAP-INSTRUMENT-NARROW pass, never before — if a complete pass does not yield a clean root cause, the orchestrator loops back to MAP (the architectural model was incomplete) rather than throwing speculative fixes. The three-fail counter **resets after a completed pass yields a root cause**; it does *not* reset on additional speculative fixes.

---

## When to use / when not to

Invoked **proactively, not reactively**. Two canonical entry paths: the **autonomous-mode bridge** (canonical-sdlc loads it on the *first* diagnostic-friction event, before any speculative fix), and a **hard-trigger match** (any single hard trigger invokes it directly, in any mode).

**Use it when any one hard trigger holds:**
- A prior fix attempt failed without a clear understanding of why.
- The bug involves async/deferred execution (rAF, `setTimeout`, Promise chains, event listeners).
- The root cause spans code you don't own (third-party library internals).

**Or when two or more soft triggers hold:** state correct at point A but wrong at point B with no visible code path between them; a "fix" that works in isolation but gets overridden; three or more interacting subsystems; a prior session that attempted fixes without measurement data.

**Skip it** (use `systematic-debugging` Phase 1 directly) when a bug has no hard trigger and fewer than two soft triggers. The skill is a technique layer inside `systematic-debugging`'s "Gather Evidence" phase or `ralph-loop`'s DIAGNOSE phase — it supplies the observation capability that feeds the scientific method; it does not replace it.

---

## Common rationalizations

Every one of these is the sound of the method being abandoned. `SKILL.md` carries the full table; the sharp ones:

| Excuse | Reality |
|--------|---------|
| "I can see the bug, let me just fix it" | Speculative fixes that "saw" the bug repeatedly all failed. MAP first. |
| "I'll instrument after I try one thing" | That "one thing" changes state. Now your instrumentation captures post-fix state, not the original bug. |
| "I don't need to read the library source" | The bug was IN the library's internal call chain. You can't instrument what you don't understand. |
| "I have a good mental model" | Mental models die with context. The architect agent's *written* analysis survives and makes data readable. |
| "The broad capture is enough" | Broad capture shows WHERE the gap is. NARROW shows WHAT fills it. Both are needed. |

---

## Quick reference

| Phase | Input | Action | Output |
|-------|-------|--------|--------|
| **MAP** | Bug report + codebase | Parallel research agents | Written architecture artifact |
| **INSTRUMENT** | Architecture understanding | Broad state logging at boundaries | Diagnostic data showing the gap |
| **NARROW** | The gap (correct → incorrect) | Per-call logging within the gap | Single culprit with evidence |
| **→ Fix** | Root cause + evidence | One atomic code change | Verified via test run |
