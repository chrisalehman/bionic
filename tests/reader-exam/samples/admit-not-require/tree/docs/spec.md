# Spec — full runs

## Requirements

**REQ-1.** A change that no suite can bound gets a full run before it lands.

- **AC-1.1.** When a changed file is read by no suite, a full run is required before the
  change lands. Fails when: a new file under a directory no suite names lands with no full
  run at all.

## Design

- **D1.** `lib/fullrun.sh` `fullrun_decision <file>...` reads `lib/reach.sh`. It admits a
  full run only when the change is unbounded: when some changed file reaches no suite it
  prints `unbounded` and `admit`; otherwise it prints the suites the change reaches and
  `refuse`. (REQ-1)
