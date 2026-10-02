---
paths:
  - ".bionic/docs/**"
---

# Plan authoring

How to write the run's own documents under `.bionic/docs/`: requirements, spec, plan, and the
record they cite. Landed in epic-23 wave-23 from the triage of the retired auto-memory store;
each line changes an act no hook can check.

## Requirements and spec

- **Provenance is one clause.** State each Step-1 requirement concisely in the source.
  Provenance is one short clause, and citations live in the record. The card prints what it is
  fed.
- **The card parses one shape.** The Step-2 card parses decisions only as
  `- **D<n> — title** (D<n>; REQ…)` list items, and ADR links only as `(D<n>; …)` after a
  backticked `adr-` path. Write the spec in that shape, or the card leaves the decision out.
- **Verify a source of truth first.** Before you propose something as a design's source of
  truth, check what it actually carries.

## Plan and step advance

- **Dry-run the commit gate before a step advance.** Before advancing `current:` to 5 or 6,
  pipe a synthetic commit payload through `bash-walls.sh`. The evidence cell must be one path
  under `record/`, and the auditor cell must read exactly CONFIRMED.
- **A tune target never blocks a wave.** A tune row's numeric target is a round number, not a
  gate. A miss lands with its numbers recorded and a carry-over.
- **Prune means bytes.** On a prune wave the named size reduction is the acceptance criterion.
  Report it first and let it set where effort goes.
