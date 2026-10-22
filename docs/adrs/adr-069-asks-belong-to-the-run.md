---
governing-skill: agent-skills:documentation-and-adrs
sdlc-step: 7
epic: epic-23-bionic-tech-debt
wave: wave-42-sitrep-owes
intent: build
rigor: single
scale: task
canonical_sdlc_version: 14
surface_type: cli-plugin
language: bash
has_ui: false
multi_agent: true
deploy_target: n/a
cleanup_on_finish: true
use_worktree: false
model_plan: orchestrator=claude-opus-5-5; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=haiku-high; auditor=opus-high; critic=opus-high
status: Accepted (release 1.25.0, 2026-10-21; D3 ruled 2026-10-21)
created: 2026-10-21
---
# ADR-069 — Every ask belongs to the run, in one register that every session of the run writes and reads

## Status

**Accepted** (release 1.25.0, 2026-10-21; D3 ruled 2026-10-21). On Chris Lehman's ruling D3, option 1 (wave-42 design-ledger Δ10).

## Context

At 8:14 AM on 2026-10-21 the sitrep printed "Blocked on you: Nothing" while the merge was held on a failed review. The ask existed. Three close-out preflights had each opened `waive:adversarial` in the store of a stand-in session, `closeout-preflight-<pid>`, and the sitrep read only the stores of the sessions the plan binds. A stand-in is never one of them, and its marker is deleted after the preflight (research-sitrep-map §3). The release card had the same flaw one step earlier: it built its waiver decisions from the calling session's store, so the 6:38 AM card offered no waiver for the failing review and "all recommended" approved a release the merge then refused.

The map of every ask that holds a run (research-sitrep-map §2) found more that no page read: the unruled matrix row, the unread ruling, the held merge, a failed review before any advance, the stop-rule call, and a gap carried by the orchestrator's choice. The cause was one: an ask lived in the session that raised it, and the run has many sessions.

## Decision

An ask belongs to the run. Every ask, approval, waiver, decision and held merge lives in one register under the run, `record/<run>/asks.state`, where `<run>` is the plan's file name less `.plan.md`. Every session acting for the run writes it, the close-out's stand-in sessions included, and every card, page and wall that looks for an ask looks there. Answering an ask once closes it for the whole run, so a card drawn by any session shows every ask the run owes. An ask raised with no run open stays with its session, in the store it had.

The register keeps the line format and the lock of the session store (`owed/v1`); only its location moved. A plan names a run only while it is a regular file named `*.plan.md`: a preflight's scratch copy, an archived plan and a missing one name none, and the ask falls back to the session store. Close-out acts for the plan it was given and says so to the commit wall, which passes that plan through as it came. Asks raised before the register are not migrated.

The register is the only place an ask counts. Every ask that holds the run is therefore written to it by a verb: the held merge when close-out refuses, a failed review from the moment its result is recorded, the stop-rule call, and a carried gap (T2). The canonical-sdlc and sitrep skills tell the model to record an ask before it puts the ask to the user in chat. The sitrep's fact sheet lists the register, and its card check refuses a page that drops an ask the register holds.

## Alternatives considered

- **Keep the ask with its session, labelled with its run (rejected).** The sitrep would then have to find every session that ever acted for the run, and the stand-ins are the sessions it cannot find: they are not in the plan and their markers are gone. A label puts the burden on every place that looks, and the 8:14 AM page shows what one missed store costs.
- **Make the stand-in sessions join the run (rejected).** A stand-in lives for one command. Binding it to the plan would add a session line and a marker per preflight and still leave the stores to be listed and read; it fixes the one failure and keeps the shape that caused it.

## Consequences

- A card drawn by any session shows every ask of the run, and a waiver offered on the release card is offered whichever session raised it (T1; research-sitrep-map §2 gap 1, §3).
- An ask answered in one session is closed in all of them; there is no second copy to go stale.
- The ask lines of a run stay beside its other records under `record/<run>/`, and the register is archived with them.
- A script that read `owed-<sid>.state` by path to find a bound session's ask now reads nothing there. It reads through `owed_file`, which resolves the register. The suites that seeded the session file by path were moved to it.
- Asks raised before 1.25.0 stay in their session stores and do not reach a run's register.
- The sitrep's completeness check is possible because the register is one file: "every recorded ask appears under Blocked on you" can be tested against it.
