# bionic domain dictionary

The ubiquitous language for bionic. When a ticket, spec, hypothesis, or test names a
concept, use the term as defined here. Adding a term is a `/domain-modeling` act; note the
date and the effort that adopted it.

## Terms

- **proven ledger** — the per-requirement record of proven / refuted / untested / in-flight,
  each with its primary surface; the raw material the admission rule filters.
  *(adopted 2026-09-04, v1 wayfinder)*
- **admission rule** — a requirement enters the spec only with its proving surface and its
  falsifying measurement; otherwise it is fog. *(adopted 2026-09-04, v1 wayfinder)*
- **ladder (certification ladder)** — capabilities in dependency order; a rung is fundamental
  iff the rung above cannot be certified without it; climbed once per vendor.
  *(adopted 2026-09-04, v1 wayfinder)*
- **adapter (harness adapter)** — the per-harness piece of bionic (Claude plugin, omnigent
  bundle + bindings); the only legitimate home for harness-specific behaviour.
  *(adopted 2026-09-04, v1 wayfinder)*
- **primary surface** — a place a claim can be read without trusting self-report: a file on
  disk, a tracker record, a transcript line, a hook's stdout. *(standing rule A-W5-175/178)*
- **fog** — an in-scope question not yet sharp enough to ticket. *(wayfinder vocabulary)*
- **canon** — the method itself as a set of statements: what a seat is, what it may never do,
  how work moves through gates. bionic's identity lives here, not in any artifact.
  *(adopted 2026-09-03, rung zero #23)*
- **interpreter** — one way of running the canon on a harness (the Claude plugin, the omnigent
  piece). Complete in itself, obtained as one thing, never depending on another interpreter
  being installed. Certified by conformance. Refines *adapter*. *(adopted 2026-09-03, #23)*
- **conformance** — the proof shape for an interpreter: for each statement, does this
  interpreter honour it. *(adopted 2026-09-03, #23)*
- **provenance (of a session)** — the fact that governs a session: it belongs to whatever
  brought it into being. A hand-opened session originates with the person, who hands it to
  the Claude interpreter by invoking the method. *(adopted 2026-09-03, #23)*
- **door wall / room wall** — a door wall stands between seats (dispatch, routing) and is
  enforced where hand-offs pass; a room wall stands inside a seat (never commit to main) and is
  placed by the seat's owner at its birth. *(adopted 2026-09-03, #23)*
- **reach** — how far into a session a governor's authority extends: the door, the room, or
  constitution only. Bounded by the runtime; placed by the owner. *(adopted 2026-09-03, #23)*
- **guard** — a hermetic check that runs on every change, anywhere, unconditionally, and says
  "this change broke nothing." Never a certificate. *(adopted 2026-09-03, #23)*
- **certificate** — a dated live run of a real session under a real interpreter at a stated
  runtime version, read from primary surfaces, script beside the numbers. Goes stale on a
  runtime bump by design. *(adopted 2026-09-03, #23)*
- **climb** — the act that fills one interpreter's certificate column for a rung.
  *(adopted 2026-09-03, #23)*
- **statement index** — proof indexed by statement: one row per canon statement, per
  interpreter a guard cell and a certificate cell; an empty cell is a visible hole.
  *(adopted 2026-09-03, #23)*
- **reproduction** — rung zero's certifying measurement: each interpreter rebuilt from the
  repository alone matches what ships exactly; the build has no other input.
  *(adopted 2026-09-03, #23)*
- **spec / kit / certificate** — three things, kept apart: the spec is the contract (canon + the
  admission rule); the kit is the spec-controlled battery (statement index + climb runners); a
  certificate is one *result* about one interpreter at one build against one runtime version. The
  spec is complete without a single certificate. *(adopted 2026-09-03, #26)*
- **certificate** *(refined)* — a self-contained result: names the spec and kit versions it was
  earned against, the interpreter build, the runtime version and date, and carries its own
  evidence. An **efficacy** claim: with bionic the seat refused, without bionic the same model did
  not. Registry lives in the repository beside the builds. *(refined 2026-09-03, #26)*
- **compliant twin** — the control that tests the instrument: the same act performed in a way the
  statement permits, which the wall must allow. Runs per cell, per interpreter.
  *(adopted 2026-09-03, #26)*
- **baseline** — the control that tests attribution: the same model, same task, bionic absent.
  A fact about the model and the statement, measured once per model per statement and shared
  across interpreters; stale on model change. *(adopted 2026-09-03, #26)*
- **vacuous cell** — a certificate cell whose baseline shows the bare model already complies;
  nothing was tested, so it reads untested. *(adopted 2026-09-03, #26)*
- **held under prior verification** — the status of a pass observed before the kit existed or
  under a builder's verification: version and pointers kept, no certification standing.
  Failures, by contrast, cross as refuted. *(adopted 2026-09-03, #26)*
- **verification vs certification** — the builder verifies a change (SDLC tiers, consumed at the
  wave gate); the kit certifies a statement about the product (outlives any wave). One may feed
  the other; neither is the other. *(adopted 2026-09-03, #26)*
