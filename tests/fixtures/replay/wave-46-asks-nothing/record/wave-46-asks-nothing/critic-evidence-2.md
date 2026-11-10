reviewed: 837ddc39161b522a7071b996cf9d0d9121f1c61b..5a08f601b5aca8cdf332c0ca1581bcbcdf3ab851
question: evidence
result: pass
scope: piece
findings: 0

# critic-evidence-2 — wave-46-asks-nothing, the fix piece T29

Reader: w46-T30, at head 5a08f601b5aca8cdf332c0ca1581bcbcdf3ab851. I did not write any of this code. Scope is the piece: T29's change to the Step-5 walk gate and what it reaches, the criteria AC-8.1, AC-8.2 and AC-8.3, and the wave's coverage verdict at this head.

## Coverage

- The chain is REQ-8 to D13 to AC-8.1, AC-8.2 and AC-8.3 to evidence. The whole read at 837ddc39 found it covered in letter and missed in substance: the walk record D13 and AC-8.1 require carries a verdict table full of AC identifiers, and the walk gate refused any artifact holding one (critic-evidence.md finding 4, moved to fixed by T29 at plan line 460).
- At this head the gate yields to a registered walk. `payload/scripts/lib/walls.sh:4477` refuses only when the grep matches and `walk_registered` finds no `proved: kind=walk` line whose `evidence=` names the artifact.
- The real plan was driven through the landed code. `bash .bionic/tmp/scratch/00000000-0000-4000-8000-000000000003/w46-T30/realplan.sh` extracts `resolve_walk_path` and `walk_registered` verbatim from `git show HEAD:payload/scripts/lib/walls.sh` and runs them over the plan's fence-stripped `## SDLC State`. Log: .bionic/tmp/scratch/00000000-0000-4000-8000-000000000003/w46-T30/realplan.log. Output:
  - `raw=record/wave-46-asks-nothing/walk.md abs=/fixture/project/.bionic/docs/record/wave-46-asks-nothing/walk.md`
  - `AC-ids-in-walk=27`
  - `registered(as-is)=rc0`, and `registered(absolute spelling of walk-artifact)=rc0`
  - `registered(proved walk line removed)=rc1`
  So the line proof-add walk wrote at T17's landing (plan line 449, `proved: kind=walk head=837ddc39… evidence=record/wave-46-asks-nothing/walk.md`) registers the artifact the Step-5 `walk-artifact:` names (plan line 446), and without that line the arm still fires on 27 identifiers.
- The full-process dry run the brief asked for could not be run. `bash hooks/session-poker.sh current 5 --check` was refused by the commit-wall process before it ran: `bionic: current refused — a subagent may not change a contract or the plan (ask main)`. The function-level run above is the substitute, and it is not the whole gate process. Label for the whole-process claim on the real plan: unverified.
- No requirement this piece reaches is left without a decision or a criterion. AC-4.1 stays the close's, owed at Step 9 (whole read finding 3); this piece does not reach it.

## Power

- AC-8.1: the T11 log rows WK-1 and WK-2 refuse a record with no table or no `verdict:` line and leave the plan byte-identical; WK-3 registers one with both. Absent the parser's table rule, WK-1 would register. T29 adds the other half: absent T29, the record AC-8.1 demands is refused at the gate, which the red log shows (below).
- AC-8.2: WK-4 to WK-10 read the discharged cells, the REFUTED row left pending, both pointers, one `proved: kind=walk` line, one `ev=walk` line and no `ev=matrix-set`. WK-7 fails if the pointer write is split out and skipped, which is the row's fails-when.
- AC-8.3: WK-15 is a doctored control. With the walk test removed from the poker, deliver lands the row and settles nothing (`PASS: WK-15 control: with the walk test removed, deliver lands the row (exit 0) and settles nothing`), and WK-16 lands it with the cells settled. That is the fails-when observed both ways.
- T29's own pin: 26b is the change detector. The red log `.bionic/docs/record/wave-46-asks-nothing/T29-canonical-sdlc-evidence-gate-red.log` opens `head=837ddc39161b522a7071b996cf9d0d9121f1c61b dirty=1` (the test file only, the library at base), ends `rc=1`, and reads `33/34 passed, 1 failed` with only `FAIL: 26b` and the walk arm's refusal text. 26a and 26c pass there, as guards should. It is a red of the pin against the pre-change library, not a suite-wide failure.
- 26a fails if the identifier arm is deleted or `walk_registered` answers yes on every input. 26c fails if the yield is read by kind alone. The `refusal` substring `AC-<n>` occurs only in the walk arm's text (`/usr/bin/grep -rn "AC-<n>" payload/scripts/lib/ hooks/*.sh` names walls.sh:4479 alone among refusals).
- One branch has no row: deleting the resolved-spelling compare in `walk_registered` leaves Section 26 green. The verb writes `walk-artifact:` and `evidence=` from one value, so the as-written compare carries every registered walk, and a deleted branch fails closed. The adversarial record carries it as a note; it does not take power from any AC row.

## Authenticity (re-executed, three)

1. T2, the piece's suite: `tests/run.sh --only canonical-sdlc-evidence-gate.test.sh`, the brief's logged form. Log: .bionic/docs/record/wave-46-asks-nothing/T30-canonical-sdlc-evidence-gate.log, opening `head=5a08f601b5aca8cdf332c0ca1581bcbcdf3ab851 dirty=0`, ending `All gating suites green ✓` and `rc=0`. It matches the landing verdict log line/T29-canonical-sdlc-evidence-gate-5a08f601b5ac.log, which reads `34/34 passed, 0 failed` with `PASS: 26a`, `PASS: 26b`, `PASS: 26c`.
2. T2, AC-8.1: `proof_verdicts` extracted from `git show HEAD:hooks/poker/proof.sh` and run over walk.md. Log: .bionic/tmp/scratch/00000000-0000-4000-8000-000000000003/w46-T30/proof-verdicts-walk.log: `wave	UNVERIFIABLE`, `AC-8.1	CONFIRMED`, `AC-8.2	UNVERIFIABLE`, `AC-8.3	UNVERIFIABLE`, `rc=0`. The record parses in the critic's shape. It holds 21 rows (`/usr/bin/grep -cE '^AC-'` on that log printed 21), where walk.md's own AC-8.1 cell says 20; that sentence is T17's, outside this range.
3. The real-plan run of the landed gate functions, quoted under Coverage.

Also read, not re-executed:
- The live landing: landing-proofs.log line 497, `line/v1|ev=walk|record=record/wave-46-asks-nothing/walk.md|discharged=3|at=2026-10-26T04:01:19Z`, one second after the plan's walk proof line `at=2026-10-26T04:01:18Z`.
- After it, the one `ev=matrix-set` on a walk row is line 500, `ac=AC-8.3|cells=evidence`, the repointing. The hand-holds fold counts only `status` or `task` cells (`hooks/poker/line.sh:739`), so no status write followed the walk on its rows. Line 641, `ac=AC-4.1|cells=task` at 04:58:30, is a task write on a row the walk does not settle.
- The regression at this head: the whole run at 837ddc39 (regression-run-837ddc39161b522a7071b996cf9d0d9121f1c61b.log opens `head=837ddc39… dirty=0`, ends `rc=0`; plan line 461 `proved: kind=regression head=837ddc39…`), and T29's commit proved by its three suites green at 5a08f601 (landing-proofs.log lines 636 to 638). Nothing else in tests/ asserts the walk arm's refusal (`/usr/bin/grep -nE "names acceptance criteria|AC-<n>|drop the criteria" tests/*.sh` prints only 26a and 26c), and the change only widens what the arm allows. So no other suite's verdict can move with it.
- Rendering: `bash agents-src/render.sh --check` printed `render.sh --check: every rendered final matches a fresh render, and so does the manifest` with rc=0 (log .bionic/tmp/scratch/00000000-0000-4000-8000-000000000003/w46-T30/render-check.log). `shasum -a 256 skills/canonical-sdlc/steps/5.md` printed `286cbbbf…c1b89e`, the value payload/integrity/rendered.sha256 holds.
- Compaction: the diff to the gate suite removes comment lines only, and the count of `expect_` calls went from 23 at 837ddc39 to 26 at 5a08f601, the three Section 26 rows. No pin was removed.

## Row verdicts

| AC | verdict | why |
|---|---|---|
| AC-8.1 | CONFIRMED | WK-1/WK-2 refuse a record without the table or the verdict: line and WK-3 registers one with both (T11 log); proof_verdicts re-run over walk.md exits 0 with 21 rows; T29 makes the gate accept that record when proof-add walk registered it (26b red at base, green at 5a08f601; real plan rc0, rc1 without the proof line) |
| AC-8.2 | CONFIRMED | WK-4 to WK-10 show discharged cells, the REFUTED row pending, both pointers, one proved: kind=walk line, one ev=walk and no ev=matrix-set; the live plan carries walk-artifact: at line 446 and the walk proof at line 449, and the gate now reads that pair (26b; real-plan run of the landed walk_registered rc0) |
| AC-8.3 | CONFIRMED | the pointer line/T11-session-poker-4-623257f87bb7.log holds WK-14 to WK-16: deliver refuses a walk record without its verdict: line, a doctored poker without the walk test lands and settles nothing (WK-15), and the real one lands with the cells settled (WK-16); live, ev=walk discharged=3 at T17's landing and no status or task write on a walk row after it (landing-proofs.log 497 to 641) |

verdict: CONFIRMED — REQ-8 is now covered in substance as well as letter: the walk record D13 requires is registered by proof-add walk and accepted by the Step-5 walk gate (26b red before T29, green at 5a08f601; the real plan's walk proof registers walk.md), the unregistered case still refuses (26a, 26c), and the regression at this head is the whole run at 837ddc39 plus T29's three greens; AC-4.1 remains owed at Step 9 and outside this piece
