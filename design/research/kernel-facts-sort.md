---
ticket: chrisalehman/bionic#45 (map #37)
kind: research
subject: the 142 facts the machine holds, sorted into event, authored, ephemeral and dropped under D1
written: 2026-10-26
base: main @ 050fa567e
sources: the spike writeup `.bionic/docs/spikes/spike-kernel-map-20261026.md` (cited `spike:<line>`); its reports under `.bionic/docs/record/spike-kernel-map-20261026/` — `r1-plan-facts.md` (`r1:<line>`), `r2-record-facts.md` (`r2:<line>`), `r4-reconcilers.md` (`r4:<line>` or `r4:R<nn>` for an inventory row); code at file:line in this tree, read where a claim turns on it
method: one row per report row; readers and writers are the reports' columns, condensed; counts were re-run by awk over the report files, not taken from the writeup
---

# The 142 facts, sorted

## Summary

**Totals: 45 event, 34 authored, 21 ephemeral, 42 dropped — 142.** Of the 42 dropped, 13 are write-only today and 29 are derivable from an event the kernel keeps. Of the 45 events, 20 already have the event shape (the landing record's `line/v1` lines and the asks register; r2:5, spike:17-19) and 25 are plan lines or record files that fold into one of nineteen kinds (the catalogue in §0). The plan keeps 32 authored facts: 27 frontmatter keys, the `## Eval design` table, the `## Tasks` row's authored cells, `## Goal`, the spec's decision bullets, and one new key, `state:`, that names the run log (spike:317). Everything per-session (21 rows) stays under `.bionic/tmp` or the user's config dir with exactly one reader each.

**The counts, verified against the reports, not the writeup.** r1 holds 80 fact rows after its `approved-by` pointer row is excluded: 35 frontmatter, 27 `## SDLC State`, 12 matrix/AC/Eval design, 6 Tasks and ledgers (r1:163; re-counted by awk over the file). r2 holds 62: 15 + 6 + 7 + 6 + 18 + 10 (r2:198, 203; re-counted). 80 + 62 = 142. **The spike's §1 table splits the plan's 80 as 26 / 24 / 10 / 20 (spike:54-57); that split is not the report's.** Both sum to 80, so the total and every per-record count stand; only the plan's per-section numbers in the writeup are off. The "≥2 readers" total of 93 is 50 + 43 (r1:164, r2:199) and "≥2 parsers" 59 is 37 + 22 (r1:165, r2:200; the 37 re-counted by awk, the 22 taken from r2's own enumeration at r2:203).

**Two corrections to the write-only list.** `language` and `has_ui` are not read by nothing: `hooks/canonical-sdlc-governing-skill.sh:1315` lists them as required discriminators and presence-checks them at :1319 — in a hook whose 28 arms never fired on 171 writes (spike:198). `attested-by:` and Step 9 `archived:` have no consumer, but close-out reads back its own write of each (`payload/scripts/close-out.sh:2033`, `:2345`). The bin for all four stays `dropped`; the reason is "no consumer", not "no reader".

**The four judgment calls a grilling session must rule on** (each row that turns on one is marked `J1`..`J4` in the tables, with its alternative in §11):

- **J1 — Is a session's act an act of the run?** This sort keeps the Patrol stamp, the armed marker, the tick digest, the roster row's status transitions and the stop orders as ephemeral, and makes the fill ledger an event. The spike's own appender list names `tick`, `arm` and `dispatch` as events (spike:316). The rule used here: an act is an event if a *later session* must know it happened; liveness and this-session housekeeping are not. The alternative puts every tick and arm in the log (152 ticks a wave, spike:238; the fold already reads 1,065 lines in 13 ms, spike:314).
- **J2 — The tree-to-row binding's one home.** Five homes today (r2:123). This sort gives the spawn its own event, `tree`, and derives the other four. The alternative is a `tree=` field on the `dispatch` event and no spawn event; it loses the 62 `spawn-worktree create` calls that precede a dispatch (spike:250).
- **J3 — Does the machine record that it asked?** This sort keeps `ask` as an event (the register is one of the two facts that never disagreed, spike:17-19) and derives "closed" from the answering event. The alternative derives "open" too (a put with no rule yet; a step reached with no approval yet) and drops the register entirely, losing `sent=` — when the person was shown the ask.
- **J4 — Hand-typed keys that a verb also writes.** `base-sha`, `regression`/`regression-override`, `parallel-budget`, `abandoned`, the Step 1 `requirements:` line. The rule used here: if a verb writes it with a timestamp and a name, it is an event; if the person types it at Step 0 and nothing stamps it, it is authored. The alternative treats every frontmatter key as authored and deletes the verbs (`budget` and `regression` were typed 0 and 0 times in waves 44-46; spike:230 lists `budget` among the never-typed).

**Facts held in several homes, and the one that survives:**

| fact | homes today | survives as |
|---|---|---|
| which tree belongs to which row | 5: Tasks `worktree` cell, `workspace/v1`, `tree/v1`, the ready line's `tree=`, roster `row=` (r2:123) | the `tree` event (J2) |
| a run's exit code | 6: roster `run_rc=`, log tail `rc=`, `.rc` file, gate `rc=`, `stamp/v1 rc=`, `ev=run rc=` (r2:148) | the `run` event's `rc=` |
| a landing | 5: `ev=published`, `landed:` header, Tasks `status` cell, the `- T<n>: landed` line, the ledger cell (r2:47, r4:R15) | `landing` `ev=published`, with the header's `branch=` and `head=` moved onto it |
| the walk artifact | 2: Step-5 `walk-artifact:` and the matrix head (r1:91, r4:R12) | the `walk` event (already `ev=walk`, `hooks/poker/proof.sh:233-238`) |
| the AC tier | 3: matrix cell, AC `eval:`, Eval design row (r4:R04) | the `## Eval design` row (authored) |
| `intent`, `rigor`, `scale`, `integration-branch`, `working-branch` | 2 each: frontmatter and an `## SDLC State` copy; `working-branch` and `base-sha` a third time in the Step 4 block (r1:44-46, 63-66) | frontmatter (authored); `base-sha` goes to the Step 4 event (J4) |
| the binding | 2: the plan's `- session:` line and `engaged-<sid>.state` (r1:107, r2:134) | the `bind` event; the marker stays ephemeral as the session's pointer to its log |
| a decision's state | 2: asks `decide:D<n>` and the design ledger heading (r2:97) | the `rule` event |
| delivered | 3: Step 9 `delivered:`, asks `delivered:<wave>`, `ev=close-out` (r1:84, r2:82, r2:42) | the `step` event, `n=9` |
| the ADRs | 3: frontmatter `adrs:`, Step 7 `adr:`, the spec's ADR links (r1:71, `hooks/poker/judge.sh:245-262`) | the `step` event, `n=7`, with the spec's link as the authored pointer |
| a waiver | 2: `waived:` line and the AC block's `waiver:` (r1:105, 125) | the `waive` event |
| the writer cap | 2: preflight `budget=` line and `parallel-budget:` (r2:139, r1:65) | both — measured and chosen are different facts; the cap is their minimum |

## 0. The event catalogue

One append-only `record/<wave>/run.log`, lines `<kind>/v1|k=v|…`, read by one field reader generalised from `_LINE_FIELDS_AWK` (`payload/scripts/lib/line.sh:157-160`). Every field is `at=` ISO seconds UTC (T1, the one shape with a shared reader, r2:176). Kinds in the ticket's list are kept by name; new ones are marked.

| kind | fields | folds in (today's homes) |
|---|---|---|
| `step` | `n=`, `at=`, `by=`, then the step's pointers: `n=0 via=`; `n=1 requirements=`; `n=2 spec=`; `n=4 worktree= base=`; `n=7 adr= rca= na=`; `n=8 closed merge= pr= cleanup= worktree-removed= tmp-wiped= tasks-completed=`; `n=9 delivered= wave= release= deployed= verified= monitored=` | every `- Step N:` line and its indented block (r1:83-98); `ev=close-out` (r2:66); frontmatter `adrs:` (r1:71) |
| `approval` | `key=step0..step3\|release\|merge-unproved\|AC-n.m`, `by=`, `at=`, `head=`, `said=` | `approved-by:` (r1:99), `approved: <name>` (r1:100), AC `user-confirmed:` (r1:125), the asks register's `approve:*` close and the release-approval page's `replied:` (r2:94, 163) |
| `proof` | `kind=regression\|floor\|check\|review\|task`, `head=`, `at=`, `evidence=`, `question=`, `reader=`, `result=`, `scope=`, `owed=`, `inherited=<base>` | `proved:` (r1:102), `inherited:` (r1:106), Step 5 `auditor:` (r1:92) |
| `finding` | `ref=<record>#<n>`, `severity=`, `to=deferred\|fixed\|carried`, `row=`, `by=`, `at=`, `stated=` | `moved:`, `deferred:` (r1:103-104), the asks `finding:*` answer (r2:95), the release page's `applied:` (r2:163) |
| `waive` | `question=` or `ac=`, `by=`, `at=`, `why=` | `waived:` (r1:105), AC `waiver:` (r1:125), asks `waive:*` (r2:81) |
| `rule` | `d=D<n>`, `verb=put\|ruled`, `said=`, `by=`, `at=`; or `key=regression derived= chosen=` | the design ledger heading (r1:135, r2:162), asks `decide:D<n>` (r2:93), `regression-override` (r1:58) |
| `order` | `state=given\|lifted`, `said=`, `at=` | `order:` (r1:101) |
| `bind` | `session=`, `by=write\|read`, `at=` | `- session:` (r1:107) |
| `handoff` | `path=`, `at=` | the `## Handoff` pointer (r1:109, r2:167) |
| `landing` | the `line/v1` line as it is: `ev=ready\|candidate\|verdict\|published\|returned\|stalled\|standing\|admitted\|void` with today's fields (r2:54-63); `published` gains `branch=` and `head=` from the `landed:` header; `debt:`/`void:` become `ev=admitted`/`ev=void` with `\|` separators | `landing-proofs.log` (r2:21-67), the `landed:` header (r2:61), `ev=integrate` as `published kind=part` (r2:66) |
| `run` | `kind=`, `log=`, `head=`, `tree=`, `dirty=`, `rc=`, `sha256=`, `at=` | `ev=run` (r2:57); the five other exit-code homes (r2:148); `stamp/v1` (r2:125) |
| `walk` | `row=`, `record=`, `discharged=`, `at=` | `ev=walk` (`hooks/poker/proof.sh:233-238`), Step-5 and matrix-head `walk-artifact:` (r1:91, 118) |
| `dispatch` | `row=`, `name=`, `agent=<subagent_type>`, `session=`, `files=`, `suites=`, `lands-on=`, `tool_use_id=`, `at=`; `amend=1` on an amend | the roster row's `intended` write (r2:107), the Tasks `agent` cell, the dispatch ledger (r1:108, r4:R17-R18), `amend` (r4:R44) |
| `tree` (new) | `row=`, `path=`, `branch=`, `base=`, `by=<session>`, `at=` | `workspace/v1`, `tree/v1`, Tasks `worktree`/`base` cells (r2:121-123) — J2 |
| `born` (new) | `row=`, `at=`, `reason=`, `finding=` | the `added by task-add at … reason:` stamp (r1:108, spike:135, r4:R49) |
| `ask` (new) | `key=`, `sent=`, `title=`, `reply=`, `at=` | `owed/v1 state=open` (r2:93) — J3 |
| `fill` (new) | `at=`, `session=`, `turn=`, `state=`, `ceiling=`, `room=` | `fill-ledger/v1` (r2:159) — J1 |
| `debt` (new) | `concept=`, `kind=`, `sites=`, `raised-by=`, `touches=`, `from=` | `record/<wave>/debt.md` rows (r2:160); the landing record's `debt:` is renamed `ev=admitted` so the prefix carries one grammar (r2:214) |
| `abandon` (new) | `at=`, `by=`, `why=` | frontmatter `abandoned:` (r1:75) — J4 |

## 1. Plan frontmatter — 35 rows (r1:42-77)

Writers are "hand" (typed at Step 0) unless named. Readers are the report's count and lead site. `authored` rows stay in the frontmatter; `canonical_sdlc_version: 15` means the frontmatter carries `state: record/<wave>/run.log` and the plan holds no machine lines (spike:317).

| # | fact | writers | readers (parsers) | bin | detail |
|---|---|---|---|---|---|
| F1 | `governing-skill` (r1:42) | hand | 2, governing-skill.sh:928, :986 (2) | authored | frontmatter |
| F2 | `sdlc-step` (r1:43) | hand, never updated: W46 reads `0` at `current: 9` (r1:43, 83) | 2, governing-skill.sh:1357, :1659 (1) | dropped | derivable: the current step is a fold over `step`/`approval` events; its only readers scope hook arms that never fired (spike:198). Alt: authored, as "the step the plan was configured at", always 0 |
| F3 | `intent` (r1:44) | hand | 3 (3: FM, FMw, YG) | authored | frontmatter; the `## SDLC State` copy (W46:403) has no reader (r1:44) → dropped |
| F4 | `rigor` (r1:45) | hand | 12 (3) | authored | frontmatter; the SDLC-State copy → dropped |
| F5 | `scale` (r1:46) | hand | 16 (4; only `plan_scale` falls back to the copy, `payload/scripts/lib/plan.sh:96-105`) | authored | frontmatter; the SDLC-State copy → dropped |
| F6 | `canonical_sdlc_version` (r1:47) | hand | 4 (3) | authored | frontmatter; 15 = "carries `state:`" (spike:317) |
| F7 | `surface_type` (r1:48) | hand | 1, card.sh:1823 | authored | frontmatter |
| F8 | `language` / `has_ui` (r1:49) | hand | presence only, governing-skill.sh:1315-1319, an arm that never fired | dropped | write-only in effect (correction to r1:49 and spike:83, which say none) |
| F9 | `multi_agent` (r1:50) | hand | 3 (2) | authored | frontmatter |
| F10 | `deploy_target` (r1:51) | hand | 2 (1) | authored | frontmatter |
| F11 | `cleanup_on_finish` (r1:52) | hand | 1 | authored | frontmatter |
| F12 | `use_worktree` (r1:53) | hand | 2 (1) | authored | frontmatter |
| F13 | `walk` (r1:54) | hand | 5 (2) | authored | frontmatter |
| F14 | `design-interview` (r1:55) | hand | 1 | authored | frontmatter |
| F15 | `model_plan` (r1:56) | hand | 2 (2) | authored | frontmatter |
| F16 | `regression` (r1:57) | the `regression` verb, poker/proof.sh:283-298 | 9 via `plan_regression` (1) | authored | frontmatter: the person's Step-0 choice; the verb that rewrites it goes. J4 — alt: a `rule key=regression` event with the frontmatter line a rendering |
| F17 | `regression-override` (r1:58) | poker/proof.sh:283 | 1, card.sh:1322 (presence) | event | `rule key=regression derived= chosen= by= at=`. J4 — alt: dropped (one presence reader) |
| F18 | `rigor-override` (r1:59) | hand | 2 (2) | authored | frontmatter |
| F19 | `review-cadence` (r1:60) | hand | 2 (2) | authored | frontmatter |
| F20 | `fix-policy` (r1:61) | hand | 3 (2) | authored | frontmatter |
| F21 | `fix-cap` (r1:62) | hand | 4 (2) | authored | frontmatter |
| F22 | `integration-branch` (r1:63) | hand | 11 via `plan_integration_branch` (1, SDLC-first) | authored | frontmatter; the SDLC-State copy (W46:399) → dropped, the reader stops looking there |
| F23 | `working-branch` (r1:64) | hand; the Step 4 block repeats it | 27 (2) | authored | frontmatter; the SDLC copy (W46:400) and the Step 4 `branch:` → dropped |
| F24 | `parallel-budget` (r1:65) | the `budget` verb, poker/plan.sh:811-836 (never typed in waves 44-46, spike:230) | 5 via `plan_budget_line` → `budget_line_of` (`payload/scripts/lib/run.sh:242`) | authored | frontmatter, an optional hand override of the preflight's measured budget (r2:139). J4 — alt: dropped with the verb |
| F25 | `base-sha` (r1:66) | hand; also SDLC `base:` and Step 4 `base-sha:` by step-line | 2 (2), neither reads the other's copy | event | `step n=4 base=`; the frontmatter and SDLC copies → dropped. J4 — alt: authored frontmatter, the other two copies dropped |
| F26 | `epic` (r1:67) | hand | 2 (2) | authored | frontmatter |
| F27 | `wave` (r1:68) | hand | 1 (RAW) | authored | frontmatter |
| F28 | `release` (r1:69) | hand | 6 (1) | authored | frontmatter |
| F29 | `seed` (r1:70) | hand | 1 | authored | frontmatter |
| F30 | `adrs` (r1:71) | judge.sh:258 at `current 7`, copied from the Step 7 `adr:` (`hooks/poker/judge.sh:245-262`); hand when no verb wrote it (spike:259) | 3 (2); close-out reads the spec first (r1:71) | dropped | derivable: the `step n=7 adr=` event, and the spec's ADR link as the authored pointer |
| F31 | `archive-root` (r1:72) | hand | 2 (1) | authored | frontmatter |
| F32 | `scale-recommendation` (r1:73) | hand | 1 | authored | frontmatter |
| F33 | `regression-runs` (r1:74) | `regression-runs --write`, poker/roster.sh:2945 | 3 (1) | dropped | derivable: a count of `run kind=regression` events (r4:R21 "computed on read") |
| F34 | `abandoned` (r1:75) | hand (r1 unverified; `payload/scripts/lib/run.sh:555` reads a flush-left key) | 2 (1) | event | `abandon at= by= why=`: it closes the run, and `run_open` needs its instant. J4 — alt: authored frontmatter flag |
| F35 | `created` (r1:76) | hand | none (r1:76; re-grepped, 0 non-comment hits) | dropped | write-only |

Section tally: 27 authored, 3 event, 5 dropped.

## 2. `## SDLC State` — 27 rows (r1:83-109)

The section disappears from the plan: every line here is an event or a copy of one (spike:313, 317).

| # | fact | writers | readers (parsers) | bin | detail |
|---|---|---|---|---|---|
| S1 | `current:` (r1:83) | 3: `units_set_current`, close-out.sh:2015, card.sh:1424 | 13 sites + 9 `_fill_current_load` calls (10 grammars) | dropped | derivable: the last `step`/`approval` event (spike:317 "`current:` … derived") |
| S2 | Step 9 `delivered:` (r1:84) | close-out `write_plan_blocks` | 8 (6 ERE copies + 2) | event | `step n=9 delivered= wave= release=`; the asks `delivered:<wave>` key and `ev=close-out` fold into it |
| S3 | Step 8 `CLOSED` head line (r1:85) | close-out | 2 (2) | event | `step n=8 at=` |
| S4 | Step 8 block `merge`/`worktree-removed`/`cleanup`/`tmp-wiped`/`tasks-completed` (r1:86) | close-out | 1, walls.sh:3872 | event | fields of `step n=8` |
| S5 | `attested-by:` (r1:87) | close-out | none but close-out's readback of its own write (close-out.sh:2033) | dropped | write-only |
| S6 | Step 9 `archived:` (r1:88) | close-out.sh:2338 | none but its readback (close-out.sh:2345) | dropped | write-only |
| S7 | Step 9 `deployed`/`verified`/`monitored` (r1:89) | close-out / hand | 1, walls.sh:3921 | event | fields of `step n=9` |
| S8 | Step 7 `adr`/`rca`/`n/a` (r1:90) | step-field / step-line | 1, walls.sh:3859 | event | `step n=7 adr= rca= na=` — the one home for the ADR list (F30) |
| S9 | Step 5 `walk-artifact:` (r1:91) | `walk_pointer_put` (both places), close-out `ensure_walk_pointer`, matrix-render stub | 3 (3), 2 storage places | event | `walk row= record= discharged= at=` — exists today as `ev=walk` (`hooks/poker/proof.sh:233-238`, r2:66); both plan copies → dropped (r4:R12) |
| S10 | Step 5 `auditor:` (r1:92) | step-field | 1, walls.sh:4659 | dropped | derivable: the auditor's record is the `evidence=` of a `proof kind=review` event (r4:R13 "auditor = the auditor record"). Alt: a field of `step n=5` |
| S11 | Step 5 floor keys `head`/`cmd`/`pass`/`total`/`output` (r1:93) | floor-run, proof-add floor, step-field | none ("no gate reads them", walls.sh:3837) | dropped | write-only; the `run` event is the fact |
| S12 | Step 5 `regression: no (Step 0, <user>) — <where>` (r1:94) | hand / step-field | 1, walls.sh:3845 | dropped | derivable: a copy of F16/F17 |
| S13 | Step 4 block `worktree`/`base-sha`/`branch` (r1:95) | step-line | 2 (2) | event | `step n=4 worktree= base=`; `branch` is read from F23 |
| S14 | Step 1 `requirements:` + "approved by" (r1:96) | hand / step-line | 3 (3; plan.sh:112 needs a bullet) | event | `step n=1 requirements=` and `approval key=step1`. J4 — alt: authored, the one Step line a person types |
| S15 | Step 0 `configured at … via …` (r1:97) | hand | 1, sitrep.sh:1429 | event | `step n=0 at= via=` |
| S16 | Step N block, generic shape (r1:98) | step-line / step-field / close-out | 2 (awk) | event | the `step` kind itself; `extract_continuation` becomes a fold query |
| S17 | `approved-by:` (r1:99) | `approve step3`, poker/proof.sh:499 | 7 sites + 8 `fill_plan_approved` calls (4 grammars) | event | `approval key=step3 by= at= said=` |
| S18 | `approved: <name>` (r1:100) | `approve`, poker/proof.sh:552 | 9 (3 grammars) | event | `approval key=release\|merge-unproved head= by= at= said=`; closes the asks `approve:*` key (r2:94) |
| S19 | `order:` (r1:101) | `order`, poker/plan.sh:3451 | 1, gate.sh:1038 | event | `order state=given\|lifted said= at=` |
| S20 | `proved:` (r1:102) | `proof_add_line`, 10 callers | 30 `proof_awk` + 15 `proof_last*` + 8 private (7 grammars) | event | `proof kind= head= at= evidence= question= reader= result= scope= owed=` — the fields `proof_fields` already names (`payload/scripts/lib/proof.sh:1420`, r1:33) |
| S21 | `deferred:` (r1:103) | `finding-move defer`, poker/proof.sh:1343; also written at registration (r4:R23) | 5 (2) | event | `finding ref= to=deferred severity= stated= by= at=` for the person's ruling; the registration copy → dropped, findings are read from the review record (r4:R23) |
| S22 | `moved:` (r1:104) | poker/proof.sh:1351; line.sh:915 writes `by=landing` | 8 (3) | event | `finding ref= to=fixed\|carried row= by= at=`; the `by=landing` moves → dropped, derivable from `published` + `born` (r4:R09, R24) |
| S23 | `waived:` (r1:105) | `waive`, proof.sh:199 | 5 (≥2) | event | `waive question= by= at= why=` |
| S24 | `inherited:` (r1:106) | `proof-add inherited`, `hooks/poker/proof.sh:672` (`suite base= head= at= evidence=`) | 1 verified, proof.sh:146 | event | `proof kind=<suite kind> inherited=<base>`. Judgment — alt: dropped, derivable from the base wave's own `run` events |
| S25 | `- session:` (r1:107) | binding.sh:326 | 2 (1) | event | `bind session= by= at=`; the session-side pointer stays ephemeral (row K1) |
| S26 | dispatch-ledger `- T<n>: landed …` / `added by task-add at …` (r1:108) | row-landed; task-add / task-split | 3, all sitrep.sh (3 grammars) | dropped | derivable: the `landed` form is `ev=published` (r4:R15, spike:317); the born stamp becomes the `born` event (r4:R49 keeps it as a door) |
| S27 | `## Handoff` pointer (r1:109) | sitrep.sh:2190, close-out.sh:1804 (W46 carries two sections) | 3 (3) | event | `handoff path= at=` |

Section tally: 20 event, 7 dropped.

## 3. `## Verification Matrix`, AC blocks, `## Eval design` — 12 rows (r1:115-126)

The matrix becomes a view (r4:R03-R10, spike:169). The W46 Eval design columns are `Requirement | Approach | Criterion | Eval type | Eval | Fails when` (W46:52).

| # | fact | writers | readers (parsers) | bin | detail |
|---|---|---|---|---|---|
| M1 | matrix table row: AC, tier, status, evidence, auditor (r1:115) | matrix-render + `matrix_row_cells` from 7 verbs; the status cell has 6 writers (r4:29) | 8 sites + 8 `matrix_row_cell` calls (5 grammars) | dropped | derivable: status from `landing`/`walk`/`proof`/`waive` events, evidence from `verdict log=`, auditor from the `proof kind=review` record (r4:R03, R06-R08); the tier stays authored in the Eval design row (r4:R04) |
| M2 | matrix head `stack-health:` (r1:116) | `proof_health_put` | 1, walls.sh:4038 | dropped | derivable: the last `run kind=regression` event (r4:R11, `proof_health_line` stays as the reader) |
| M3 | matrix head `auditor-wave:` (r1:117) | poker/proof.sh:1055 | none (re-grepped: writer sites only) | dropped | write-only |
| M4 | matrix head `walk-artifact:` (r1:118) | see S9 | 1, close-out.sh:1942 | dropped | derivable: the `walk` event |
| M5 | AC block heading `AC-n.m: <text>` (r1:119) | matrix-render from the requirements file or REQ line | 3 (1, shared) | dropped | derivable: a rendering of the requirements doc and the Eval design row's Criterion cell |
| M6 | AC `provenance:` (r1:120) | matrix-render from the requirements file | 1, walls.sh:4128 | dropped | derivable: the requirements doc holds it |
| M7 | AC `fails-when:` (r1:121) | matrix-render from the Eval design `Fails when` column | 2 (2) | dropped | derivable: the Eval design cell is the authored home |
| M8 | AC `task:` (r1:122) | matrix-render `taskof` from the Tasks `serves` column | 2 (1, copied) | dropped | derivable: the Tasks row's `serves` cell |
| M9 | AC `eval:` (r1:123) | matrix-render from the Eval design cell | 3 (2; debt `close-criterion-eval`) | dropped | derivable: the Eval design `Eval` cell, read by one reader |
| M10 | AC `evidence:` (r1:124) | `matrix_block_key`, the landing | 1, walls.sh:4212 | dropped | derivable: `verdict log=` / `published` for the row that serves the AC |
| M11 | AC `waiver:` / `user-confirmed:` (r1:125) | waive-row / confirm-row (r4:R39, R45 — both doors) | 2 (grep) | event | `waive ac= by= at= why=` and `approval key=AC-n.m by= at= said=`; status is derived from them (r4:R39) |
| M12 | `## Eval design` row (r1:126) | hand at Step 2/3 | 3 (3; card by position) | authored | `## Eval design`, the one home of the AC id, tier, eval and fails-when |

Section tally: 1 authored, 1 event, 10 dropped.

## 4. `## Tasks` and the ledgers — 6 rows (r1:132-137)

| # | fact | writers | readers (parsers) | bin | detail |
|---|---|---|---|---|---|
| T1 | `## Tasks` row: id, step, kind, task, agent, deps, size, serves, Files, worktree, base, status, suites, lands-on, artifact (r1:132, W46:92) | units.sh task-add/task-set; poker/plan.sh verbs | 79 `units_rows` + 3 private (4 grammars) | authored | `## Tasks` for id, step, kind, task, deps, size, serves, Files, suites, lands-on; the `agent`, `worktree`, `base`, `status`, `artifact` cells → dropped, derivable from `dispatch`, `tree`, `published` (r4:R17, R19; `task-set` and `launch-sync` "write what the roster already knows", spike:252) |
| T2 | task title, the task cell's first sentence (r1:133) | — | 2 (2; debt `title-sentence-end`) | dropped | derivable from T1's task cell by one function |
| T3 | `suites` / `lands-on` cells (r1:134) | task-set / amend | 1 (`poker_brief_cell`) | authored | `## Tasks`, the contract before dispatch; at dispatch the `dispatch` event snapshots `files= suites= lands-on=` and `amend` appends (r4:R44 "the one writer of the contract"). Judgment — alt: drop the cells and author the contract only in the brief |
| T4 | design-ledger heading `## Δk — D<n> put\|ruled "…" (name, local time): title` (r1:135) | `decisions_append`, sitrep.sh:2298; matrix-retier | 2 (2) | event | `rule d=D<n> verb= said= by= at=`; the ledger file becomes a rendering; the title is the spec's (T5) |
| T5 | spec decision bullet `- **D<n> — title** (D<n>; REQ…)` (r1:136) | hand | 1, card.sh:758-823 | authored | the spec, not the plan (the card's one shape, `.claude/rules/plan-authoring.md`) |
| T6 | `## Goal` paragraph (r1:137) | hand | 1 (1) | authored | `## Goal` |

Section tally: 4 authored, 1 event, 1 dropped. **Plan total: 32 authored, 25 event, 23 dropped = 80.**

## 5. The landing record — 15 rows (r2:53-67)

Already event-shaped; the rows that stay keep their fields. "fold" = `_line_fold` and the other `line_kv` readers (r2:54-60).

| # | fact | writers | readers (parsers) | bin | detail |
|---|---|---|---|---|---|
| 1.1 | the record's path (r2:53) | — | 4 derivations, 2 naming the root differently | authored | frontmatter `state: record/<wave>/run.log` (spike:317). Judgment — alt: dropped, derived from the plan's slug by one function |
| 1.2 | `ev=ready` (r2:54) | `line_ready` ×2; row-landed by hand | 4 (1) | event | `landing ev=ready row= name= commit= branch= tree= suites= debt= carrier= age= at=`; `carrier=` is a liveness claim judged by K14's one reader, not a fact |
| 1.3 | `ev=candidate` (r2:55) | line.sh:1219, :1678 | 2 (1) | event | `landing ev=candidate row= base= commit= tree= at=` |
| 1.4 | `ev=verdict` (r2:56) | line.sh:2418; proof.sh:1186 | 8 (1 + the substring read at poker/proof.sh:1494) | event | `landing ev=verdict row= commit= suite= result= log= admitted= width= promised= actual= at=`; the substring reader goes |
| 1.5 | `ev=run` (r2:57) | booked.sh:823; poker/proof.sh:1863 | 2 (1) | event | `run kind= log= head= tree= dirty= rc= sha256= at=` — the one home of the exit code (K15); `kind=` replaces the log-name substring rule at poker/line.sh:734 |
| 1.6 | `ev=standing` (r2:58) | line.sh:2101 | 3 (1; fold and proof disagree on `cause=`) | event | `landing ev=standing head= suite= lines= log= cause= against= at=`; one predicate for which causes count |
| 1.7 | `ev=returned` / `ev=stalled` (r2:59) | line.sh, 9 sites | 2 (1) | event | `landing ev=returned\|stalled row= why= detail= at=` |
| 1.8 | `ev=published` (r2:60) | `line_publish`; poker/line.sh:1034 (`kind=hand`); the fold's `kind=git` | 8 (1) | event | `landing ev=published row= commit= kind= by= why= branch= head= at=` — **the** landing; the four copies (1.9, T1 `status`, S26, the ledger cell) go |
| 1.9 | `landed:` header (r2:61) | `_wt_proofs_append`, worktree.sh:1527 | 5 (4 grammars) | dropped | derivable: a second write of 1.8 (r2:47); its `branch=` and `head=` move onto `published`. The migration must settle wave 43's 29 `published` against 28 `landed:` (r2:47) |
| 1.10 | `debt:` in the landing record (r2:62) | `_wt_debt_write`, worktree.sh:1571 | 2 (2, different required fields) | event | `landing ev=admitted id= row= branch= head= suite= token= at=`, renamed so the `debt:` prefix carries one grammar (r2:214) |
| 1.11 | `void:` (r2:63) | `_wt_debt_void`, worktree.sh:1574 | 2 (2) | event | `landing ev=void id= branch= why= at=` |
| 1.12 | `ev=settled` (r2:64) | line.sh:948 (`line_settle`) | 2 (1) | dropped | derivable: which findings and cells a landing settles is a fold over `published`, `born` and the Eval design (r4:R09 "the landing's `published` event is the fact") |
| 1.13 | `ev=matrix-set` / `ev=stop-run` (r2:65) | poker/plan.sh:2063; `hooks/poker/roster.sh:163-167` | 1 (hand-holds count) | dropped | `matrix-set` goes with the field verbs (r4:R38); `stop-run` was never typed in three runs (spike:230). Alt for `stop-run`: `order state=stop run=` |
| 1.14 | `ev=integrate` / `ev=close-out` / `ev=doc` / `ev=walk` (r2:66) | close-out.sh:842; poker/proof.sh:235; poker/line.sh:1103; no `ev=doc` writer found (re-grepped) | none ("acts, read by no fold") | event | `walk` stays as the `walk` kind (S9); `integrate` becomes `published kind=part`; `close-out` becomes `step n=8`; `doc` has no writer in the tree → dropped |
| 1.15 | `stamp/v1` lines copied after a `landed:` header (r2:67) | worktree.sh:1527 | 1 (proof.sh:1109) | dropped | write-only in practice (none occur in waves 43-46); the `run` event is the fact |

Section tally: 1 authored, 10 event, 4 dropped.

## 6. The asks register — 6 rows (r2:92-97)

| # | fact | writers | readers (parsers) | bin | detail |
|---|---|---|---|---|---|
| 2.1 | store path: `record/<run>/asks.state`, else `.bionic/tmp/owed-<sid>.state` (r2:92) | — | 3, one module | dropped | derivable: the run log's path (1.1); the no-run fallback stays ephemeral (K12) |
| 2.2 | open ask `owed/v1 key= state=open sent= at= title= reply=` (r2:93) | `owed_open`, 13 callers | 7 (2: `fld` and sitrep.sh:1200's raw split) | event | `ask key= sent= title= reply= at=`. J3 — alt: derivable (a `rule verb=put` with no `verb=ruled`; a step reached with no `approval`), losing `sent=` |
| 2.3 | closed ask `state=closed by= at= opened=` (r2:94) | `owed_close`, 20 callers | 2 (1) | dropped | derivable: the answering event (`approval`, `rule`, `finding`, `step n=9`) closes the key. J3 — alt: keep `ask state=closed` so the fold is a key match |
| 2.4 | answer on an open ask `answer= answered= event=` (r2:95) | `owed_answer`, 2 callers | 4 (1) | event | it *is* the answering event: `rule` for `decide:`, `approval` for `approve:`, `finding to=carried` for `finding:` |
| 2.5 | the open-ask list, derived TSV (r2:96) | `owed_list` | 11 (1) | dropped | derivable: a fold output, not a stored fact |
| 2.6 | a decision's state, two homes (r2:97) | owed.sh; `decisions_append` | 2 (2) | dropped | derivable: the `rule` event is the one home; `decisions_settle` (the reconciler between the two) goes |

Section tally: 2 event, 4 dropped.

## 7. Roster rows — 7 rows (r2:107-113)

Ephemeral rows name the file and the one reader that survives.

| # | fact | writers | readers (parsers) | bin | detail |
|---|---|---|---|---|---|
| 3.1 | `roster-state/v1` row: status, session, name, agent_id, launched_at, subagent_type, suites_allowed, tool_use_id, plan, teammate_id (r2:107) | `roster_row`, one builder, 9 callers | 31 files (3 families) | ephemeral | `roster-<sid>.state`, one reader: a `roster_field` fold in `roster.sh`. The `intended` write is also the durable `dispatch` event (row, name, agent, contract, at); `confirmed`/`identified` (the `agent_id` arrival) and `run_rc`/landed marks are this session's. J1 — alt: the whole row an event, the roster a fold over this session's dispatches |
| 3.2 | an agent row is open or live, derived (r2:108) | — | 6 rules | dropped | derivable: one liveness predicate over 3.1 and the pid (ADR-005 "one owner per liveness truth", spike:292) |
| 3.3 | `start-unchecked/v1`, `start-claim/v1` (r2:109) | execution-recorder.sh:1156, :1119; tick.sh:1919 | 1, poker/plan.sh:364 | ephemeral | the roster file; one reader poker/plan.sh:364 |
| 3.4 | `ruling/v1` (r2:110) | `ruling_record`, `ruling_stamp` | 2 (1) | dropped | the ruling path was never approached in three runs and `ruling-push` goes with it (spike:212, 315; `rule`/`ruling-ack` never typed, spike:230). Alt: `rule key=writer:<name> said= by= at=` (r4:R46 keeps both acts as doors) |
| 3.5 | `landing-swept/v1` (r2:111) | stop.sh | 1, poker/roster.sh:751 | ephemeral | the roster file; one reader; the schema constant declared once, not twice (r2:111) |
| 3.6 | `sweeper-ledger/v1` acks (r2:112) | session-sweeper.sh | 5 (copies) | ephemeral | `sweeper-<sid>.state`; one reader, `roster_open_names` roster.sh:681 |
| 3.7 | `adopt-read/v1` (r2:113) | session-poker.sh adopt | 1, poker/roster.sh:399 | ephemeral | `adopt-reads.state`; one reader |

Section tally: 5 ephemeral, 2 dropped.

## 8. The tree record — 6 rows (r2:121-126)

| # | fact | writers | readers (parsers) | bin | detail |
|---|---|---|---|---|---|
| 4.1 | a session's workspace, `workspace/v1` in `workspaces-<sid>.state` (r2:121) | `worktree_record_workspace` | 2 (1) | dropped | derivable: `tree` events with `by=<session>`; the per-session file is why a tree was left standing when its record sat in the predecessor's file (wave 43 A-orch.23, spike:292) |
| 4.2 | a tree's owner, `tree/v1` in `<git-dir>/bionic-tree` (r2:122) | `worktree_record_tree` | 1 (line.sh:1075) | dropped | derivable: the reverse index of `tree` events |
| 4.3 | which tree belongs to which row — five homes (r2:123) | spawn-worktree.sh; line.sh:1153; dispatch-preflight.sh | 4 parsers over 5 copies | event | `tree row= path= branch= base= by= at=` at `spawn-worktree create`; the Tasks cells, 4.1, 4.2 and roster `row=` derive from it; the ready line's `tree=` names the landing's source and stays. J2 |
| 4.4 | landing trees `.bionic/tmp/landing/<n>`, held by `<pid>:<lstart>` (r2:124) | `landing_tree_take` | 1 (slots rule) | ephemeral | the hold under the landing tree; one reader `_wt_hold_alive` worktree.sh:1665 |
| 4.5 | test stamps `stamp/v1` in `<git-dir>/bionic-stamps` (r2:125) | booked.sh:354 — the same runner that writes `ev=run` at booked.sh:823 | 2 (2 acceptance rules) | dropped | derivable: a second write of the `run` event, keyed by tree; "was head H proved in tree T" is a fold with `tree=`. Alt: ephemeral, a per-tree cache with `_wt_stale_proof` as its one reader |
| 4.6 | `bionic-pass/`, `bionic-reads/` (r2:126) | none | none (re-grepped: 0 hits) | dropped | orphaned data |

Section tally: 1 event, 1 ephemeral, 4 dropped.

## 9. Stamps and keyed state under `.bionic/tmp` and the user store — 18 rows (r2:134-151)

| # | fact | writers | readers (parsers) | bin | detail |
|---|---|---|---|---|---|
| K1 (5.1) | binding marker `engaged-<sid>.state`: `plan=`, `engaged_at=`, `dry_of=` (r2:134) | 3 (binding.sh:241 and two more, against "one writer" at run.sh:836) | 5 (2) | ephemeral | the session's pointer to its plan and so to its log; one reader `session_plan` run.sh:864; one writer. The run-side fact is the `bind` event (S25) |
| K2 (5.2) | load record `loaded-<sid>.state` (r2:135) | `ss_load_record` | 4 (2; close-out's stops at the first unknown key, `payload/scripts/close-out.sh:875-892`) | ephemeral | one reader `detect_loaded_field` detect.sh:1219 |
| K3 (5.3) | Patrol stamp `patrol-<sid>.state`, judged by mtime (r2:136) | tick.sh:153 | 6 (mtime / prefix) | ephemeral | liveness; one reader `patrol_verdict` patrol.sh:769. J1 — alt: `tick`/`arm` events (spike:316) |
| K4 (5.4) | Patrol armed `patrol-<sid>.state.armed` (r2:137) | tick.sh:32 | presence (reader unverified) | ephemeral | one reader, the same `patrol_verdict`. J1 |
| K5 (5.5) | tick digest `tick-digest-<sid>.state` (r2:138) | `write_tick_digest` | 1 parser, many callers | ephemeral | one reader `tick_digest_field` patrol.sh:961. J1 |
| K6 (5.6) | preflight attestation `preflight-<sid>.state` incl. `budget=` (r2:139) | preflight-probe.sh | 3 (unverified) | ephemeral | one reader, dispatch-preflight.sh:440's loader; the measured writer cap (F24 is the chosen one) |
| K7 (5.7) | context spend `context-spend.state`, not keyed by session (r2:140) | stop.sh:527-560 | 1 (positional) | ephemeral | key it by session; one reader stop.sh:533 |
| K8 (5.8) | gate act requests `gate-<sid>.state` (r2:141) | permission-answer.sh:584 | 1 (unverified) | ephemeral | one reader `gate_requests` tick.sh:1333 |
| K9 (5.9) | stop orders `stop-orders-<sid>.state` (r2:142) | stop-orders.sh, stop-guard.sh (schema declared twice) | 1 | ephemeral | one reader stop.sh:2417; `stop-guard` folds into `stop-orders` (spike:315). Alt: `order state=stop to=` events |
| K10 (5.10) | detached run `runs/<name>.log`, `.pid`, `.rc`, `.progress.tsv` (r2:143) | booked.sh:570 | 4 (presence / tail) | ephemeral | `.pid` and `.progress.tsv` are liveness, one reader `run_live` session-poker.sh:2205; the `.rc` file and the log's `rc=` tail → dropped, copies of the `run` event |
| K11 (5.11) | launch-sync result `launch-sync-<sid>.log` (r2:144) | execution-recorder.sh:613 | 1 | dropped | its writer goes (r4:R17) |
| K12 (5.12) | single-owner stamps `line-told-`, `ruling-pending-`, `farm-out.state`, `sweep-failed.state`, `owed-<sid>.state` (r2:145) | their owners | the same owners | ephemeral | each with its owner as the one reader; `ruling-pending-<sid>` → dropped with 3.4 |
| K13 (5.13) | session liveness: `sessions/<pid>.json`, the transcript, the stamp mtime — three rules (r2:146) | the CLI | 3 rules | ephemeral | the CLI's session file; one reader `patrol_live_sessions` patrol.sh:142 (`kill -0`); the transcript-exists rule at dispatch-preflight.sh:1696 → dropped |
| K14 (5.14) | process liveness `<pid>:<lstart>` in `carrier=`, `holder=`, the landing hold (r2:147) | `_slots_since` | 4 copies | ephemeral | one reader `_slots_live` slots.sh:73; the three copies go |
| K15 (5.15) | a run's exit code — six homes (r2:148) | 6 writers | 5 parsers | event | the `run` event's `rc=` (1.5); roster `run_rc=`, the log tail, `.rc`, gate `rc=`, `stamp/v1 rc=` → dropped |
| K16 (5.16) | gate request `~/.claude/bionic/gate/requests/<id>` (r2:149) | gate.sh:401, :817, :782 | 3 (first-wins vs last-wins; "open" stated 3 times) | ephemeral | one reader `_gate_read` gate.sh:328; `admitted=`/`width=` are already on the `verdict` event |
| K17 (5.17) | test-width share `~/.claude/bionic/share` (r2:150) | session-poker.sh:3403 | 2 (copies) | authored | a user setting, outside the run and the plan; one reader `gate_share` gate.sh:241 |
| K18 (5.18) | pressure ring `~/.claude/bionic/pressure.ring` (r2:151) | resources.sh (unverified) | resources.sh | ephemeral | one module |

Section tally: 1 authored, 1 event, 15 ephemeral, 1 dropped.

## 10. Other record files read by field — 10 rows (r2:159-168)

| # | fact | writers | readers (parsers) | bin | detail |
|---|---|---|---|---|---|
| 6.1 | fill ledger `fill-ledger/v1` (r2:159; 448 lines over four waves) | stop.sh:2387 | 4 (copies) | event | `fill at= session= turn= state= ceiling= room=`; `current=` dropped as derivable. J1 — alt: ephemeral, since no later session reads it except sitrep's history |
| 6.2 | debt ledger `debt.md` rows (r2:160) | the `debt` verb | 5 (2 restatements) | event | `debt concept= kind= sites= raised-by= touches= from=` |
| 6.3 | carried debts in `continuation.md` `## Deferrals` (r2:161) | close-out `co_debts` | 2 (2) | dropped | derivable: a rendering of 6.2 and `finding to=carried` (r4:R26) |
| 6.4 | design ledger `design-ledger.md` headings (r2:162) | `decisions_append` | 4 (3; the local clock read back without its zone) | event | the same `rule` event as T4 — one fact, two report rows; the file becomes a rendering, so its local-time clock stops being parsed |
| 6.5 | release-approval page `release-approval-<h8>.md` (r2:163) | poker/plan.sh:2876-2886 | 4 (4; the page chosen two ways) | dropped | derivable: a rendering of `ask` (the card's keys), `approval` (`replied:` → `said=`) and `finding` (`applied:`) events |
| 6.6 | regression and release-check logs (r2:164) | poker/proof.sh:1847, :1635 | 2 (hash / substring) | event | the `run` event's `log=`, `sha256=`, `kind=`; the file is evidence the event cites, not state |
| 6.7 | per-landing logs `line/<row>-<suite>-<sha12>.log` (r2:165) | line.sh:2184 | 2 | event | the `verdict` event's `log=`; the file is evidence |
| 6.8 | briefs `briefs/<row>.md` (r2:166) | poker/plan.sh:2476 | 1 (existence) | dropped | derivable: a rendering of T1 and the contract; still written, as the file the dispatch wall reads (spike:315) |
| 6.9 | handoff document and pointer (r2:167) | handoff.sh:61; close-out.sh:1813 | 1 | event | `handoff path= at=` (S27); the document is what it names |
| 6.10 | release entry blocks in CHANGELOG (r2:168) | `_line_numbers`, `line_reviews_state`, close-out | 4 (2) | dropped | derivable: written once by one writer after the last review and landing (r4:R28, R32); nothing reads it back |

Section tally: 6 event, 4 dropped. **Record total: 2 authored, 20 event, 21 ephemeral, 19 dropped = 62.**

## 11. The judgment calls, with their alternatives

| id | rows | this sort | the alternative | what decides it |
|---|---|---|---|---|
| J1 | 3.1, K3, K4, K5, K9, 6.1 | a session's liveness and housekeeping are ephemeral; the fill verdict is an event because sitrep reads the run's stop history across sessions (r2:159) | `tick`, `arm`, the roster transitions and stop orders as events (spike:316 names `tick`, `arm`, `dispatch` as appenders) | whether the fold must answer "when was the last tick" for a stop rule (spike:202 "marker-turn-no-tick") from the durable log or from the session's stamp; and whether 152 ticks a wave belong in a log a person's card is a reading of |
| J2 | 4.3, 4.1, 4.2, T1's `worktree`/`base` cells | a `tree` event at spawn | `tree=` on the `dispatch` event, no spawn event | whether a tree can exist with no dispatch (today: 62 `create` calls against 92 `Agent` calls, spike:197, 250; a landing tree is one) |
| J3 | 2.2, 2.3, 6.5 | `ask` is an event; "closed" is derived | both derived; the register goes | whether `sent=` (when the person was shown the ask) is a fact the kernel owes the card and the handoff ("Blocked on you", spike:125) |
| J4 | F16, F17, F24, F25, F34, S14 | a verb-stamped line is an event; a Step-0 hand line is authored | every frontmatter key authored; `budget`, `regression`, the step-line for Step 1 deleted | whether the plan may carry a value a verb once wrote (`regression: yes` by `regression`, poker/proof.sh:283) or the kernel's lint "no writer of the plan but a person" admits no exception |

Three smaller calls are marked inline: S24 (`inherited:` as a proof field or dropped), T3 (the contract cells authored or brief-only), 4.5 (the stamps dropped or a per-tree cache).

## 12. Not verified

- Readers marked (unverified) in r2 were not re-read here: K6's parser, K8's, K4's reader, K18 (r2:228). Their bins rest on the file's name and writer.
- The `ev=doc` kind has no writer in the tree (`/usr/bin/grep` over `payload/scripts hooks`); r2:66 left it unverified. It is counted inside row 1.14, not as its own row.
- Wave 43's one `published` with no `landed:` header (r2:47) was not located; the migration's fold must choose which count is the landing.
- Nothing was run. The event catalogue is a sort of today's fields, not a tested grammar; the replay bed (spike:275) is what pins it.
