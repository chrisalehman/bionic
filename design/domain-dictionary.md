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
