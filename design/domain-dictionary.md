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
