reviewed: b69ac4a3c8909bbc00415684ec9eb5204f2f1bf1..837ddc39161b522a7071b996cf9d0d9121f1c61b
question: evidence
result: fail
scope: whole
findings: 4
finding: 1 S4 off .bionic/docs/plans/epic-23-bionic-tech-debt/wave-46-asks-nothing.plan.md:326 AC-8.3's evidence names a spawn-worktree log that holds no walk section
finding: 2 S3 off .bionic/docs/plans/epic-23-bionic-tech-debt/wave-46-asks-nothing.plan.md:442 the reviewed head is covered by the floor but no whole run ran at it, so the wave's regression proof is unverifiable at 837ddc39 until the in-flight pass lands
finding: 3 S4 off .bionic/docs/plans/epic-23-bionic-tech-debt/wave-46-asks-nothing.plan.md:242 AC-4.1 is the live close row, owed at Step 9, and cannot be judged at this head
finding: 4 S2 on hooks/poker/proof.sh:212 REQ-8 is covered in letter and missed in substance: the walk record its criteria require is refused by the Step-5 walk gate, and no criterion or test drives a step over it
shown: 4 /usr/bin/grep -cE 'AC-[0-9]' .bionic/docs/record/wave-46-asks-nothing/walk.md; sed -n 4458,4466p payload/scripts/lib/walls.sh

# critic-evidence — wave-46-asks-nothing, the whole run

## What was read
- spec D1 to D18 and its Eval design; the plan's Tasks, Verification Matrix, AC blocks and SDLC State; assumptions.md (A-T*, A-orch.1 to .29); landing-proofs.log; regression-run-402980ec…log; every row's settled evidence log under record/wave-46-asks-nothing/line/.
- the judge at the reviewed head, read-only, plan checksum unchanged before and after:
  `bash -c ". payload/scripts/lib/proof.sh && proof_state P . ; proof_whole_text P . ; proof_health_line P . ; proof_merge_unproved P . <head>"`
  output (saved: .bionic/tmp/scratch/00000000-0000-4000-8000-000000000003/w46-T18/judge-at-head.log):
  `covered 837ddc39…` · `red at 402980ec, 4 landings before this head` · `red head=402980ec… owed= closed=<the six>` · merge-unproved rc=0.

## Re-execution (one tier used, T2; two suites, through the door, at 837ddc39, dirty=0)
- `tests/run.sh --only release-approval.test.sh` → PASS, rc=0. Log: .bionic/docs/record/wave-46-asks-nothing/T18-release-approval.log. Holds §JUDGE, §UNPROVED-ASK (UA-1 to UA-3b: reply writes `approved: merge-unproved`), the reply half of AC-7.2. Agrees with T23's settled logs (green).
- `tests/run.sh --only close-out-3.test.sh` → PASS, rc=0. Log: .bionic/docs/record/wave-46-asks-nothing/T18-close-out-3.log. Holds §REG (AC-7.4's second half). It holds no §SCORE: `/usr/bin/grep -c SCORE tests/close-out-3.test.sh` → 0, as A-T12.11 and A-orch.11 say.
- T3 (AC-4.1) is live at delivery; nothing to re-execute at this head.

## Coverage (requirement → design decision → criterion)
Inverted from the spec's `(D<n>; REQ…)` tags and the AC blocks' provenance lines: REQ-1 D1 D8 D9 → AC-1.1..1.5; REQ-2 D2 D10 D11 → AC-2.1..2.4; REQ-3 D12 → AC-3.1..3.3; REQ-4 D11 → AC-4.1; REQ-5 D4 D6 D16 → AC-5.1..5.3; REQ-6 D5 D16 → AC-6.1..6.4; REQ-7 D4 D14 → AC-7.1..7.4; REQ-8 D13 → AC-8.1..8.3; REQ-9 D7 D15 → AC-9.1..9.3; REQ-10 D3 D18 → AC-10.1, 10.2; REQ-11 D3 D18 → AC-11.1; REQ-12 D3 D17 → AC-12.1, 12.2. No requirement has zero inbound citations from either side. No hole.

## The regression's close, judged (the brief's lead)
- The whole run at 402980ec left six suites red (`proved: kind=regression head=402980ec… rc=1 owed=<six>`, plan line 442). Each fix row T25 to T28 ran its owed suites green at its landing (landing-proofs.log ev=run lines, rc=0 at 402980ec for T25/T26/T27 and at 5be5879d for T28). The health line now reads `owed=` empty and `closed=` the six.
- That closes the floor: the judge answers `covered` at 837ddc39 (judge-at-head.log). It does not make the head green under D4, which this wave shipped: `proof_whole_text` prints `red at 402980ec, 4 landings before this head` and `proof_merge_unproved` answers that a merge here needs the person's word. The brief's "the whole run proved at that head" is not what the record says, and steps/6.md:21 ("the reviewers read the head the regression left green") was not met when this review was dispatched.
- Since then the tick started the pass at this head: roster row `regression@837ddc39`, launched_at 2026-10-26T04:05:11Z (.bionic/tmp/roster-a9d1c095-….state lines 16-17), booked pid 21284 still running at 21:18 PDT (`ps -p 21284`). Finding 2 resolves when its proof lands green; red, the reviewed head changes.
- The floor's cover is the row's own suites. T25 changed tests/lib/rehearsal.sh, which rehearsal.test.sh and rehearsal-stop-rule.test.sh also source, and neither ran past 402980ec. Read, not run: the two states they drive (`clean`, `stop-rule`, tests/lib/rehearsal.sh:455-460) never reach the new `_rh_reply` or the changed `failed-review|delivered` arm, so the gap is real in rule and empty in effect.
- The test-line cap: no assertion id present at the base is missing at the head in any of the 23 changed suites (script over `git show <rev>:<suite>` extracting `expect_* "<id>`; output .bionic/tmp/scratch/00000000-0000-4000-8000-000000000003/w46-T18/ids-gone.txt, every `gone:` empty). The deletions the compaction made are comments and section indexes, with one exception the record owns: close-out-3 §SCORE, added and dropped inside the range (A-T12.11). regression-rename's unscanned mutant (A-T28.1, AS-2b/AS-3b) was deleted at 26e66800f, older than the reviewed range.
- SC-2 (AC-9.3's evidence) is clock-dependent: it failed in both of T15's settled logs on the pace percentage alone (`302955%` against `302960%`; line/T15-close-out-4-b5f2a7b729a4.log:100, line/T15-close-out-4-402980ecbdf9.log:100) and passed in the whole run. It is what left T15 standing red and AC-11.1 pending. Older than the reviewed range (the equality is at the base, tests/close-out-4.test.sh:625).

## Row verdicts (auditor column)
| AC | verdict | why |
|---|---|---|
| AC-1.1 | CONFIRMED | §EXEMPT in line/T2-session-poker-5-011d42e2fb7b.log, 272/272; red log T1/T2; the policy test removed would land S3 too |
| AC-1.2 | CONFIRMED | same log; the pin reads `review-born rows: 2 of cap 2 are counted`, not the eval's `counted 2 of 2` (A-T1.5), same rule |
| AC-1.3 | CONFIRMED | same log, the suffix pinned both ways |
| AC-1.4 | CONFIRMED | §REGISTRY in the same log; the constant read by both sites (A-T2.1) |
| AC-1.5 | CONFIRMED | §DEBT in line/T1-units-eb9a83ddeacf.log, three planted removals, 154/154 |
| AC-2.1 | CONFIRMED | §EXIT-2 in line/T4-shell-lint-98eb8b58ae98.log |
| AC-2.2 | CONFIRMED | §EXIT-1 same log; ceiling kept at 148 for plan.sh after T22 (A-T22.2); shell-lint green in the whole run |
| AC-2.3 | CONFIRMED | §NEEDS in line/T3-refuse-9893ed5beeb2.log; writer and reader shapes agree (A-orch.21) |
| AC-2.4 | CONFIRMED | §NEEDS-YOU in line/T5-landing-line-2-a5bf5eb50ab6.log, mutants ny2/ny3 (A-T5.2) |
| AC-3.1 | CONFIRMED | §RETIER in line/T6-session-poker-5-668547a52e63.log |
| AC-3.2 | CONFIRMED | same log, the downward tier refused and the plan unchanged |
| AC-3.3 | CONFIRMED | §RETIER in line/T6-landing-line-2-668547a52e63.log, a waiver counted beside it |
| AC-4.1 | UNVERIFIABLE | live at delivery (finding 3); the record so far holds no ev=refusal, and its one ev=matrix-set is evidence-only, which the fold skips (hooks/poker/line.sh:739) |
| AC-5.1 | CONFIRMED | §WHOLE-RUN in line/T8-canonical-sdlc-evidence-gate-2-6e4604b8607e.log; the same-head refusal is the only one left (hooks/poker/proof.sh:1791) and `proof_whole_run_behind` has no reference left (`/usr/bin/grep -rn proof_whole_run_behind hooks payload/scripts tests` → nothing) |
| AC-5.2 | CONFIRMED | §STACK VT-15 to VT-17b in line/T7-session-poker-4-c684231a82dd.log; note: the line names F and reads green for a green F at any later head (payload/scripts/lib/proof.sh:1972), which D6 allows and the eval's "red past it" does not say |
| AC-5.3 | CONFIRMED | §HEALTH in line/T7-landing-line-1-c684231a82dd.log; live: the plan's line went to `owed=` empty, `closed=` the six, after T25-T28 |
| AC-6.1 | CONFIRMED | §STARTER in line/T13-session-poker-4-3038b1f93477.log; live: the tick started `regression@837ddc39` at 04:05:11Z once nothing was ready |
| AC-6.2 | CONFIRMED | same log |
| AC-6.3 | CONFIRMED | same log; the live run's proof not yet landed |
| AC-6.4 | CONFIRMED | §STARTER in line/T8-landing-line-2-6e4604b8607e.log |
| AC-7.1 | CONFIRMED | §UNPROVED UP-1/UP-2 in line/T23-card-b5f2a7b729a4.log, red and green paired; live the judge prints the eval's shape (judge-at-head.log) |
| AC-7.2 | CONFIRMED | UP-3 to UP-3f (the word planted by hand, A-T10.9) plus the reply path: UA-2 (re-executed, T18-release-approval.log) and close-replay CL-5 / rehearsal FR-1b at T25 |
| AC-7.3 | CONFIRMED | §ONE in line/T9-proof-at-head-f44b9b4389a7.log holds card, scorecard and continuation with a split arm (ONE-8 to ONE-10); `current 8 --check` over the same fixture is UP-3b/UP-3f, not §ONE, so the eval's letter is spread over two sections |
| AC-7.4 | CONFIRMED | §WHOLE in line/T9-sitrep-f44b9b4389a7.log; §REG re-executed green at the head (T18-close-out-3.log) |
| AC-8.1 | CONFIRMED | §WALK in line/T11-session-poker-4-623257f87bb7.log |
| AC-8.2 | CONFIRMED | same log |
| AC-8.3 | REFUTED | as recorded: the evidence is line/T11-spawn-worktree-623257f87bb7.log, which holds no walk row (`/usr/bin/grep -c WALK` → 0); the proof is WK-14 to WK-16 in the session-poker-4 log and, live, `ev=walk … discharged=3` at T17's landing with no ev=matrix-set after it. The claim holds; the pointer proves nothing (finding 1) |
| AC-9.1 | CONFIRMED | §ROUNDS in line/T12-sitrep-d69c413259e6.log |
| AC-9.2 | CONFIRMED | same log |
| AC-9.3 | CONFIRMED | SC-2/SC-5/SC-5b in line/T22-close-out-4-de0039e9bf84.log; the eval's close-out-3 §SCORE does not exist (A-orch.11, re-checked); SC-2 is clock-flaky, older than the range |
| AC-10.1 | CONFIRMED | `/usr/bin/grep -c "T0-only" tests/canonical-sdlc-evidence-gate-2.test.sh` → 0; Section 33 in line/T24-canonical-sdlc-evidence-gate-2-d646c4373e9f.log |
| AC-10.2 | CONFIRMED | 33b and 33b-rev (meta row proves the mutant landed) in the same log |
| AC-11.1 | CONFIRMED | OC-1c0, OC-1c, OC-1d in line/T15-close-out-4-402980ecbdf9.log; red in T15-close-out-4-red.log |
| AC-12.1 | CONFIRMED | §PARTS in line/T16-session-poker-5-284b93cc85e5.log |
| AC-12.2 | CONFIRMED | same log; k6/BP-5 carry tree= (T22) |

## The wave-level hole (added on the orchestrator's lead, checked)
REQ-8 (D13; AC-8.1 to AC-8.3) asks the walk to settle its cells, so that no status write follows it. Each criterion holds as written: the parser, the settlement and the landing all run. None of them asks whether the record they require can stand at the Step-5 gate. The record needs a `| AC | verdict | why |` table (hooks/poker/proof.sh:212). The walk gate refuses any walk artifact matching `AC-[0-9]` (payload/scripts/lib/walls.sh:4462-4466). This run's record has 27 matches (.bionic/tmp/scratch/00000000-0000-4000-8000-000000000003/w46-T18/walk-gate.log). No suite drives `current 5` over a record of D13's shape, and the arm's named pin suite no longer holds it. The settlement is therefore proven, and the step it exists to free is blocked. Missing the person's word at that step is the charter's objective, so this is a hole in substance, not in letter. The adversarial record carries the defect as its finding 8. The `current 5` refusal itself is the orchestrator's observation and unverified here.

auditor-wave: REFUTED — coverage is whole in letter, but REQ-8's walk record is refused by the Step-5 walk gate, so the requirement is missed in substance (finding 4). Apart from that, the regression at the reviewed head is the floor's covered, not a whole run there; the tick's pass at 837ddc39 decides that part (finding 2).
verdict: REFUTED — coverage is whole in letter, but REQ-8's walk record is refused by the Step-5 walk gate, so the requirement is missed in substance (finding 4); apart from that, the regression at the reviewed head is the floor's covered, not a whole run there, and the tick's pass at 837ddc39 decides that part (finding 2).
