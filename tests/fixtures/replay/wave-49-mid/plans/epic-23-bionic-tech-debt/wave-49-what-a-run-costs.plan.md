---
governing-skill: canonical-sdlc
sdlc-step: 0
epic: epic-23-bionic-tech-debt
wave: wave-49-what-a-run-costs
intent: build
rigor: double
review-cadence: once
fix-policy: S1,S2-on
fix-cap: 10%
scale: wave
scale-recommendation: "Issue #51 is not a repair inside the gate's design but a change to its control law: what the wall books (browser runs and app compiles, today unbooked), what a run is charged (its measured cores, today a flat 1.61), how a lone request is admitted under load (today always), what running work counts for (today twice), and what the person keeps (today nothing). That is a governing design with three or four rulings and a spec, about ten rows and a day or two, so wave scale with a spec and double rigor, where the evidence question gets its own reader on the control law that overloaded a machine; the user may set scale=task and rigor=single as 1.28.0 to 1.29.2 ran."
canonical_sdlc_version: 14
surface_type: cli-plugin
language: bash
has_ui: false
multi_agent: true
deploy_target: n/a
cleanup_on_finish: true
use_worktree: false
walk: required
design-interview: true
model_plan: orchestrator=claude-fable-5-1; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=haiku-high; auditor=opus-high; critic=opus-high
archive-root: /fixture/home/bionic-archive
working-branch: wave/49-what-a-run-costs
integration-branch: main
base-sha: 59350b5e6
seed: ideas/bionic-1.30.0-gate-cost-report-20261106.md
release: 1.30.0
regression: yes
created: 2026-11-06
adrs: docs/adrs/adr-077-the-gate-steers-by-the-load.md
---

# wave-49-what-a-run-costs — bionic 1.30.0: the gate charges each run what it costs

## Goal

Ship bionic 1.30.0: the gate controls the machine's capacity by what each run costs, and never by how many agents are running. GitHub issue #51 (2026-11-06) reports a user project's wave of eight to eleven writers driving an 8-core machine to a 1-minute load of 17 to 34 until its owner killed the terminal: three writers typed browser test runs straight into Bash, each starting a cold app compile on every core plus a browser, and none left a gate request. Three defects in the gate's control law let it happen, and the issue's comment adds three more readings. The wall does not book the commands that compile the app or drive a browser, so the gate never sees them. The gate cannot charge a run as the whole machine: every request is promised the flat cost of one suite, 1.61 cores, and the whole-machine booking was removed in wave 35 on a reasoning about a suite's correctness that does not hold for its cost. A lone request is admitted whatever the load, since the processor rule passes when nothing admitted is unfinished, so load from work the gate does not see never stops it. Running work is counted twice, its measured load plus its promise, so ready rows waited on a machine that was 63 percent idle. And the 92 percent share leaves the person about 0.6 of a core on the machine they are using. Accepted when a browser or compile command typed into Bash is booked and admitted alone, when a request is charged the cores its own runs measured, when a lone request waits while the measured load is over the share and the oldest waiter is taken once it falls, when a running run counts once, and when the person's reserve is honoured; each on its own red test, the whole suite green at the release head.

## Problem

The gate admits a request on a promise, and the promise is a constant. Every work request is promised `_res_suite_cores`, 1.61 cores, whatever the command; a whole run is promised the width. A command the wall does not know is not booked at all, so a browser run with a cold compile, the most expensive thing a writer can start, is invisible to the gate, and when it is the only thing asking, nothing holds it. The issue's principle is the one the gate's charter already states, control capacity by what each run costs, and the five defects are the five places the gate reads a constant or nothing where it should read a measurement.

## Eval design

| Requirement | Approach | Criterion | Eval type | Eval | Fails when |
|---|---|---|---|---|---|
| REQ-1 | the real classifier and wall over fixture commands | AC-1.1 | hermetic | `tests/cmd-class.test.sh` §C1 → `playwright test`, `npx playwright test e2e/x.spec.ts`, `pnpm playwright test` read `browser` | the classifier answers `none` |
| REQ-1 | the real classifier and wall over fixture commands | AC-1.2 | hermetic | `tests/cmd-class.test.sh` §C1 → `next dev`, `npx next build`, `next start`, `npx lighthouse http://x` read `compile` or `browser` | any reads `none` |
| REQ-1 | the real classifier and wall over fixture commands | AC-1.3 | hermetic | `tests/background-suite-guard.test.sh` §B-CLASS → the wall's wrap text for `npx playwright test x` names booked.sh with `--class browser`; in a planted store the shim leaves a request `class=browser` | the command is not wrapped, or the request lacks `class=` |
| REQ-1 | the real classifier and wall over fixture commands | AC-1.4 | hermetic | `tests/background-suite-guard.test.sh` → a backgrounded `npx playwright test x &` is refused as a backgrounded suite is today | the new class skips the backgrounded refusal |
| REQ-2 | the gate over a planted store | AC-2.1 | hermetic | `tests/gate.test.sh` §CLASS → `gate_ask work k --class browser` on a fresh key at busy 2.0, lim 6.36, nothing admitted is promised `0:4:0` (the free room); at busy 0 the width | the promise reads 1.61 |
| REQ-2 | the gate over a planted store | AC-2.2 | hermetic | `tests/gate.test.sh` §CLASS → at busy 0 on 8 cores at share 92 and reserve 1 a browser ask on a fresh key is promised the width, 6, and a work ask beside it waits (CL.2); a `whole` ask waits while a work request is unfinished (WH rows kept; numbers aligned with the fixture, A-orch.30) | a second request is admitted beside the width-promised run |
| REQ-2 | the gate over a planted store | AC-2.3 | static | `/usr/bin/grep -n 'owed its measured cost' payload/scripts/lib/walls.sh payload/scripts/booked.sh .bionic/docs/adrs/epic-23-bionic-tech-debt/adr-051-*.md` → three hits (the ADR path corrected at A-orch.32: ADR-051 has no tracked copy under docs/adrs) | a site stands unamended |
| REQ-3 | the gate over a planted store | AC-3.1 | hermetic | `tests/gate.test.sh` §COST → booked.sh over `bash -c 'i=0; while [ $i -lt 400000 ]; do i=$((i+1)); done'` in a planted store writes a cost line whose fourth field is at least 0.5 | the line has three fields, or the fourth reads 0 |
| REQ-3 | the gate over a planted store | AC-3.2 | hermetic | `tests/gate.test.sh` §COST → three planted lines with cores 5.8, 6.0, 13.0 promise `0:6.0:<s>` (the robust rule's pick, the largest at or under twice the median; plant corrected at T3, A-T3.1) | the promise reads 1.61, 13.0 or the mean 8.27 |
| REQ-3 | the gate over a planted store | AC-3.3 | hermetic | `tests/gate.test.sh` WA.1 kept → a key with no lines is promised `_res_suite_cores`; `whole` at busy 2.0 the free room 4, and the runner's JOBS after the grant reads 4 | an unknown key reads 0 or the width |
| REQ-3 | the gate over a planted store | AC-3.4 | hermetic | `tests/gate.test.sh` §COST → three 1.29.2 lines `<s>:<e>:<load>` read their seconds and load as before and promise the prior | `_gate_seconds` reads 0, or a line is rewritten |
| REQ-3 | the gate over a planted store | AC-3.5 | unit | `tests/gate.test.sh` §COST → a planted `times` of 400 s over 10 s on 8 cores writes 8; 0.01 s over 10 s writes 0.1 | a line records more than the machine, or 0 |
| REQ-4 | the gate over a planted store and clock | AC-4.1 | hermetic | `tests/gate.test.sh` §ROOM → three requests admitted 120 s ago at 1.61, busy 2.95 of 6.4 (8 cores at share 80, reserve 0): `gate_room` reads `promised=0 room=yes` (RM.1; numbers aligned with the fixture, A-orch.30) | `promised=4.83 room=no` |
| REQ-4 | the gate over a planted store and clock | AC-4.2 | hermetic | `tests/gate.test.sh` §ROOM → the same three admitted 10 s ago read `promised=4.0` (±0.1) and `room=no` | `promised=0` |
| REQ-4 | the gate over a planted store and clock | AC-4.3 | hermetic | `tests/gate.test.sh` §ROOM → at one store and reading, a newcomer at the room's margin is admitted exactly when `gate_room --owed 1` reads yes | the two sites disagree |
| REQ-5 | the gate over a planted store | AC-5.1 | hermetic | `tests/gate.test.sh` H.4 inverted → `world_machine 8 8192 30 16`, nothing admitted: `gate_ask work x --within 1` returns 75 | admitted (rc 0) |
| REQ-5 | the gate over a planted store | AC-5.2 | hermetic | `tests/gate.test.sh` §LONE → two waiters, busy falls to 1.0: the lower `asked=` is admitted first | the newer is admitted first |
| REQ-5 | the gate over a planted store | AC-5.3 | hermetic | `tests/gate.test.sh` H.8 and H.9 kept → unknown memory with nothing admitted admits, beside unfinished work waits; an unknown busy reading counts the promises whole | admitted beside unfinished work on an unknown memory reading, or a promise faded on an unknown busy reading |
| REQ-5 | the gate over a planted store | AC-5.4 | hermetic | `tests/gate.test.sh` §LONE → a landing and a work request waiting on load: when it falls the landing is admitted first | the work request passes it |
| REQ-6 | the gate over a planted config dir | AC-6.1 | hermetic | `tests/gate.test.sh` §SHARE → share 92, reserve 1, 8 cores: `_gate_share_cores` reads 6.36; reserve absent reads 6.36 (default 1); reserve 0 reads 7.36 | 7.36 with reserve 1 |
| REQ-6 | the gate over a planted config dir | AC-6.2 | hermetic | `tests/session-poker-2.test.sh` §SHARE → `share` prints `share=92 reserve=1 cores=8 room=6.36`; `share reserve=2` writes 2; `share reserve=9` exits 2 on 8 cores | no reserve printed, or 9 accepted |
| REQ-6 | the gate over a planted config dir | AC-6.3 | hermetic | `tests/gate.test.sh` §WIDTH → `gate_width` reads 6 at share 92 reserve 1 on 8 cores | 7 |
| REQ-7 | static reads of the ledger, step text and structure record | AC-7.1 | static | `session-poker.sh debt list` → one line `burned T<n>` by a row of this wave, or `grep -c '^consolidation: none found' record/wave-49-what-a-run-costs/continuation.md` → 1 | neither |
| REQ-7 | static reads of the ledger, step text and structure record | AC-7.2 | static | `/usr/bin/grep -c 'one act of consolidation' payload/skills/canonical-sdlc/steps/9.md` → 1 | 0 |
| REQ-7 | static reads of the ledger, step text and structure record | AC-7.3 | static | `/usr/bin/grep -c '^debt:' record/wave-49-what-a-run-costs/critic-structure.md` over lines whose two sites are both files this wave landed → 0 | one such line |
| REQ-8 | the verb with no plan bound | AC-8.1 | hermetic | `tests/sitrep.test.sh` §UNBOUND → `sitrep --line` in a fixture with no bound plan: stderr empty, rc 0 | stderr carries `unbound variable` |
| REQ-9 | the tick over a planted gate reading and roster | AC-9.1 | hermetic | `tests/stop.test.sh` §LOAD → `world_machine 8 8192 30 14 14`, room closed, two live writers: the tick prints `STANDDOWN <newest> — load 14.0 over 6.36` | QUIET |
| REQ-9 | the tick over a planted gate reading and roster | AC-9.2 | hermetic | `tests/stop.test.sh` §LOAD → after the stand-down the row's status reads `pending`; at `world_machine 8 8192 30 1 1` the tick prints FILL naming it | `dropped`, or no FILL |
| REQ-9 | the tick over a planted gate reading and roster | AC-9.3 | hermetic | `tests/stop.test.sh` §LOAD → three live writers over the line: one STANDDOWN per tick | two names on one tick |
| REQ-9 | the tick over a planted gate reading and roster | AC-9.4 | hermetic | `tests/stop.test.sh` §LOAD → the admitted request in the planted store has no `ended=` after the tick | `ended=` with `why=load` |

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads | suites | lands-on | artifact |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | The person keeps a reserve. The reader gate_reserve reads bionic/reserve beside the share, a non-negative decimal under the machine's cores, default 1; _gate_share_cores becomes max(1, share × cores ÷ 100 − reserve), the one site, so admission, the room, the width ask and gate_width all leave it; gate_state prints reserve=; red first in gate.test.sh §SHARE (reserve 1 reads 6.36 on 8 cores at share 92, absent reads the same, 0 reads 7.36) and §WIDTH (gate_width 6), WD.4 kept; the shell-lint green; net test growth at or under the code growth (D6; AC-6.1, AC-6.3). complexity: standard | w49-T1 | — | 40 | REQ-6 | payload/scripts/lib/gate.sh!, tests/gate.test.sh, tests/CENSUS.md | .worktrees/49-T1 | 59350b5e6 | landed | — | gate.test.sh, shell-lint.test.sh | gate.test.sh, shell-lint.test.sh | — |
| T2 | 4 | build | A promise fades into the load. One function, _gate_faded <now>, sums each admitted unfinished request's promised cores by max(0, 1 − (now − admitted)/60), weight 1 while the busy reading is unknown; _gate_decide reads busy + faded + newcomer against lim with the unf > 0 guard and the max gone; _gate_room_line reads b1 and b5 each + faded + owed × most; the width ask loses its floor of 1; red first by inverting H.4 (16 busy of 8, nothing admitted: waits, rc 75 under --within 1) and WA.3 (load 6.0, the oldest landing answered 0), H.8 kept for unknown memory, and new §ROOM (three admitted 120 s ago at busy 2.95 read promised=0 room=yes; 10 s ago read promised about 4.0 room=no; a newcomer at the margin is admitted exactly when gate_room --owed 1 reads yes) and §LONE (two waiters, busy falls to 1.0: the lower asked= first; a waiting landing is admitted before a waiting work request); the header's processor and room rules rewritten to what the code does; net test growth at or under the code growth (D5, D12; AC-4.1 to AC-4.3, AC-5.1 to AC-5.4). complexity: complex | w49-T2 | — | 60 | REQ-4, REQ-5 | payload/scripts/lib/gate.sh!, tests/gate.test.sh, tests/CENSUS.md | .worktrees/49-T2 | 11f6c32d | landed | — | gate.test.sh, landing-line-2.test.sh, shell-lint.test.sh | gate.test.sh, landing-line-2.test.sh, shell-lint.test.sh | — |
| T3 | 4 | build | The gate remembers cost. The ask gate_ask takes --class browser or compile and writes class= on the request; _gate_cores_for <kind> [<class>] [<key> <project>] answers the key's measured cores by _gate_cost_cores (the fourth field of the kept cost lines, by _gate_seconds's robust rule), else the width for whole, browser and compile, else _res_suite_cores; gate_end reads times in its own shell, never in a subshell, sums the children's user and system seconds and writes <secs>:<now>:<load>:<cores>, the load field empty when unknown, cores = min(machine cores, max(0.1, cpu/secs)) to two decimals; _gate_seconds unchanged; the tests/run.sh comments at :874 and :956 reworded to name the fourth field (D10's first candidate); red first in gate.test.sh §COST (booked.sh over a CPU-burning loop in a planted store writes a fourth field of at least 0.5; three planted lines 6.0, 5.8, 6.2 promise 0:6.0:<s>; three 1.29.2 three-field lines read their seconds and promise the prior; a planted times of 400 s over 10 s on 8 cores writes 8, 0.01 s writes 0.1) and §CLASS (gate_ask work k --class browser on a fresh key is promised the width; a work ask waits beside an admitted width-promised run), WA.1 kept; a world_cost_cores helper in tests/lib/world.sh; net test growth at or under the code growth (D3, D4, D9; AC-2.1, AC-2.2, AC-3.1 to AC-3.5). complexity: complex | w49-T3 | — | 60 | REQ-2, REQ-3 | payload/scripts/lib/gate.sh!, tests/gate.test.sh, tests/lib/world.sh, tests/run.sh, tests/CENSUS.md | .worktrees/49-T3 | e22c6aee4 | pending | approval:plan | gate.test.sh, runner-width.test.sh, shell-lint.test.sh | gate.test.sh, runner-width.test.sh, shell-lint.test.sh | — |
| T4 | 4 | build | The wall books browser runs. The classifier cmd_class answers browser for playwright test, cypress run and lighthouse and compile for next dev, next build and next start, bare or behind npx, pnpm, yarn or bunx, and suite for vitest; _bsg_wrap_text wraps suite, browser and compile, handing the shim --class <c> for the two new classes with the command's key as --suites; a backgrounded command of the new classes meets the backgrounded refusal as a suite does; the wave-35 sentence at walls.sh:5507-5509 gains the clause that a browser or compile run is owed its measured cost; red first in cmd-class.test.sh §C1 (nine commands read browser, compile or suite where they read none; the build class unchanged and pinned so) and background-suite-guard.test.sh §B-CLASS (the wrap text names booked.sh with --class browser; the backgrounded form is refused); net test growth at or under the code growth (D8; AC-1.1, AC-1.2, AC-1.4, AC-1.3's wrap half). complexity: standard | w49-T4 | — | 45 | REQ-1 | payload/scripts/lib/cmd-class.sh, payload/scripts/lib/walls.sh, tests/cmd-class.test.sh, tests/background-suite-guard.test.sh, tests/CENSUS.md | .worktrees/49-T4 | 59350b5e6 | landed | — | cmd-class.test.sh, background-suite-guard.test.sh, shell-lint.test.sh | cmd-class.test.sh, background-suite-guard.test.sh, shell-lint.test.sh | — |
| T5 | 4 | build | The shim carries the class. The shim booked.sh reads --class browser or compile and booked_ask passes it to gate_ask as --class, so a wrapped browser run leaves a request with class=browser in the store; the wave-35 sentence at booked.sh:132-135 gains the owed-its-measured-cost clause; red first in booked.test.sh §CLASS (booked.sh --class browser over a short command in a planted store leaves a request reading class=browser and a promise of the width; without --class no class line and the suite prior); net test growth at or under the code growth (D4, D8; AC-1.3's request half, AC-2.1). complexity: standard | w49-T5 | — | 40 | REQ-1, REQ-2 | payload/scripts/booked.sh, tests/booked.test.sh, tests/CENSUS.md | .worktrees/49-T5 | 7a92d2337 | pending | approval:plan, tests/lib/world.sh | booked.test.sh, shell-lint.test.sh | booked.test.sh, shell-lint.test.sh | — |
| T6 | 4 | build | The verb shows the reserve. The verb session-poker.sh share [<pct>] [reserve=<cores>] prints share=<n> reserve=<c> cores=<n> room=<share cores>; reserve=<c> writes bionic/reserve through the same temp-and-rename as the share and refuses a value that is not a non-negative number under the machine's cores with exit 2; red first in session-poker-2.test.sh §SHARE (the print, reserve=2 written, reserve=9 refused on 8 cores), 40f kept; the shell-lint green; net test growth at or under the code growth (D6; AC-6.2). complexity: standard | w49-T6 | — | 30 | REQ-6 | hooks/session-poker.sh, tests/session-poker-2.test.sh, tests/CENSUS.md | .worktrees/49-T6 | 11f6c32d | landed | approval:plan, payload/scripts/lib/gate.sh | session-poker-2.test.sh, shell-lint.test.sh | session-poker-2.test.sh, shell-lint.test.sh | — |
| T7 | 4 | build | The run stands a writer down. After the gate line, when the 5-minute busy cores exceed _gate_share_cores and SCHED_GATE_ROOM is no, the tick names the newest live writer whose row is not landed and orders STANDDOWN with why=load <5m> over <lim> through the stop-orders path, at most one per tick; the stood-down row stays ready and FILL offers it when the room opens; an admitted request is never ended by it; red first in stop.test.sh §LOAD beside GAP4 (world_machine 8 8192 30 14 14 with two live writers prints STANDDOWN <newest> — load 14.0 over 6.36; the row then reads pending and FILL names it at load 1 1; three writers over the line get one STANDDOWN; the planted admitted request has no ended= after the tick); the tick's header names the rule; net test growth at or under the code growth (D7; AC-9.1 to AC-9.4). complexity: complex | w49-T7 | — | 60 | REQ-9 | hooks/poker/tick.sh, tests/stop.test.sh, tests/CENSUS.md | .worktrees/49-T7 | a4a4a4803 | landed | approval:plan, payload/scripts/lib/gate.sh | stop.test.sh, shell-lint.test.sh | stop.test.sh, shell-lint.test.sh | — |
| T8 | 4 | build | The status line reads unbound. The variable lq is initialised beside its siblings in hooks/poker/sitrep.sh before the branch that sets it, so sitrep --line with no plan bound prints its line and nothing on stderr; red first in sitrep.test.sh §UNBOUND; net test growth at or under the code growth (D11; AC-8.1). complexity: standard | w49-T8 | — | 15 | REQ-8 | hooks/poker/sitrep.sh, tests/sitrep.test.sh, tests/CENSUS.md | .worktrees/49-T8 | 59350b5e6 | landed | — | sitrep.test.sh, shell-lint.test.sh | sitrep.test.sh, shell-lint.test.sh | — |
| T15 | 4 | build | The close reads one eval. The criterion the close proves, an eval naming landing-report --hand-holds, is decided once: walls.sh matrix_close_rows is the one predicate and MR_AWK taskof in hooks/session-poker.sh reads its answer instead of matching the eval itself, so the two cannot disagree; red first with an agreement case in the suite that pins matrix_close_rows (a planted plan where the old match and the new predicate differ reads one answer); debt burn close-criterion-eval T15 (D10's second candidate); net test growth at or under the code growth (D10; AC-7.1). complexity: complex | w49-T15 | — | 45 | REQ-7 | hooks/session-poker.sh, payload/scripts/lib/walls.sh, tests/close-out-4.test.sh, tests/CENSUS.md | .worktrees/49-T15 | a4a4a4803 | landed | approval:plan, payload/scripts/lib/walls.sh, hooks/session-poker.sh | close-out-4.test.sh, session-poker-4.test.sh, shell-lint.test.sh | close-out-4.test.sh, session-poker-4.test.sh, shell-lint.test.sh | — |
| T9 | 5 | verify | The walk reads the loop. The walk drives the issue's scenes over fixtures and planted stores: three browser commands typed into Bash are wrapped, booked and admitted one at a time; a lone request waits at a planted load of 16 and the oldest waiter goes first when it falls; three running runs read once at the room; a reserve of 1 shows at every site; a tick over a 5-minute load of 14 stands one writer down and re-offers the row; a booked run leaves a four-field cost line and its next ask is promised the measured cores. Twenty-six hermetic and unit criteria discharged at tier, the four static ones left to their steps; the record at record/wave-49-what-a-run-costs/walk.md, registered by proof-add walk. | w49-T9 | — | 60 | REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-8, REQ-9 | record/wave-49-what-a-run-costs/walk.md | .worktrees/49-T9 | 68ef6f33 | pending | approval:plan, head | — | — | record/wave-49-what-a-run-costs/walk.md |
| T10 | 6 | review | The auditor reads the evidence. The auditor holds evidence over the settled head: is each discharged criterion's proof honest, at its tier, with the planted failure its eval names actually red before the change. One record under record/wave-49-what-a-run-costs, registered by proof-add review. · questions: evidence | w49-T10 | — | 60 | REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9 | record/wave-49-what-a-run-costs/auditor-evidence.md | .worktrees/49-T10 | 68ef6f33 | pending | approval:plan, head | — | — | record/wave-49-what-a-run-costs/auditor-evidence.md |
| T11 | 6 | review | The critic reads the whole. One critic holds adversarial and structure over the settled head: what is wrong that nobody asked about in the loop, and whether it is built from what exists; the structure read is REQ-7's measure of AC-7.3. Two records under record/wave-49-what-a-run-costs, one per question, registered by proof-add review. · questions: adversarial,structure | w49-T11 | — | 60 | REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9 | record/wave-49-what-a-run-costs/critic-adversarial.md, record/wave-49-what-a-run-costs/critic-structure.md | .worktrees/49-T11 | 68ef6f33 | pending | approval:plan, head | — | — | record/wave-49-what-a-run-costs/critic-adversarial.md |
| T12 | 7 | doc | ADR-077 and the entry. ADR-077, the gate steers by the load, promoted to docs/adrs as Proposed from this row's tree, with ADR-051's and ADR-060's Status lines naming the amendment; steps/9.md gains the sentence that every run owes one act of consolidation or a stated none, through its template and render.sh; the 1.30.0 entry in CHANGELOG.md rendered from the plan with known-limits-part and reviews-part; plugin.json 1.30.0 and the help and version pages through render.sh, rendered.sha256 refreshed (AC-2.3, AC-7.2). | w49-T12 | — | 45 | REQ-2, REQ-7 | .bionic/docs/adrs/epic-23-bionic-tech-debt/adr-077-the-gate-steers-by-the-load.md, docs/adrs/adr-077-the-gate-steers-by-the-load.md, .bionic/docs/adrs/epic-23-bionic-tech-debt/adr-051-a-whole-run-holds-the-machine-once-and-cost-is-cut-where-it-lives.md, .bionic/docs/adrs/epic-23-bionic-tech-debt/adr-060-the-gate-owns-capacity.md, CHANGELOG.md, payload/.claude-plugin/plugin.json, payload/commands/help.md, payload/commands/version.md, payload/integrity/rendered.sha256, tests/release-check.test.sh, agents-src/templates/skills/canonical-sdlc/steps/9.md.tmpl, skills/canonical-sdlc/steps/9.md, .bionic/docs/record/wave-49-what-a-run-costs/T12.md | .worktrees/49-T12 | dd9b12e18 | pending | approval:plan, head, proof:review | release-check.test.sh, render.test.sh, commands.test.sh, shell-lint.test.sh | release-check.test.sh, render.test.sh, commands.test.sh, shell-lint.test.sh | — |
| T13 | 8 | integrate | The merge. The wave branch is merged into main locally once the state at the head reads green; the push is the person's; reviews-part before the merge. | — | — | 30 | REQ-7 | CHANGELOG.md | — | — | pending | — | — | — | — |
| T14 | 9 | close | The close consolidates. The close-out reads the state at its head green and the debt ledger with close-criterion-eval burned by T15, or writes consolidation: none found with the reason; release card, delivered:, continuation.md with the deferrals and the debt lines (AC-7.1). | — | — | 30 | REQ-7 | record/wave-49-what-a-run-costs/continuation.md | — | — | pending | — | — | — | record/wave-49-what-a-run-costs/continuation.md |
| T16 | 4 | build | Runner width reads the reserve. The runner's width suite assumed the share's cores with no reserve: at a4a4a48 runner-width.test.sh reads 38 of 48, ten cases red (1b, 1c, 2a, 3b, 5 ×4, 6a, 6f), each a JOBS or width number one lower under T1's default reserve of 1; the suite plants the reserve it assumes (reserve 0 where a case pins the pre-reserve arithmetic) and gains one case pinning that JOBS follows the reserve (reserve 1 on 8 cores at share 92 reads 6), so the runner's width is proved to read the gate's one cores site; no code change; net test growth at or under the code growth (D6; AC-6.3). complexity: standard | w49-T16 | — | 20 | REQ-6 | tests/runner-width.test.sh, tests/CENSUS.md | .worktrees/49-T16 | bfebd5fa6 | landed | approval:plan, payload/scripts/lib/gate.sh | runner-width.test.sh, shell-lint.test.sh | runner-width.test.sh, shell-lint.test.sh | — |

## Verification Matrix


| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1.1 | T2 | pending | — | — |
| AC-1.2 | T2 | pending | — | — |
| AC-1.3 | T2 | pending | — | — |
| AC-1.4 | T2 | pending | — | — |
| AC-2.1 | T2 | pending | — | — |
| AC-2.2 | T2 | pending | — | — |
| AC-2.3 | T0 | pending | — | — |
| AC-3.1 | T2 | pending | — | — |
| AC-3.2 | T2 | pending | — | — |
| AC-3.3 | T2 | pending | — | — |
| AC-3.4 | T2 | pending | — | — |
| AC-3.5 | T1 | pending | — | — |
| AC-4.1 | T2 | pending | — | — |
| AC-4.2 | T2 | pending | — | — |
| AC-4.3 | T2 | pending | — | — |
| AC-5.1 | T2 | pending | — | — |
| AC-5.2 | T2 | pending | — | — |
| AC-5.3 | T2 | pending | — | — |
| AC-5.4 | T2 | pending | — | — |
| AC-6.1 | T2 | pending | — | — |
| AC-6.2 | T2 | pending | — | — |
| AC-6.3 | T2 | pending | — | — |
| AC-7.1 | T0 | pending | — | — |
| AC-7.2 | T0 | pending | — | — |
| AC-7.3 | T0 | pending | — | — |
| AC-8.1 | T2 | pending | — | — |
| AC-9.1 | T2 | pending | — | — |
| AC-9.2 | T2 | pending | — | — |
| AC-9.3 | T2 | pending | — | — |
| AC-9.4 | T2 | pending | — | — |

AC-1.1: `playwright test`, bare or behind a package runner (`npx`, `pnpm`, `yarn`, `bunx`), classifies as a heavy command the wall books.
  provenance: issue #51 defect 1 and proposed fix; three `npx playwright test` runs with no gate request; cmd-class.sh's `suite` class
  serves: REQ-1
  fails-when: the classifier answers `none`
  eval: T2 — `tests/cmd-class.test.sh` §C1 → `playwright test`, `npx playwright test e2e/x.spec.ts`, `pnpm playwright test` read `browser`
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T4-cmd-class-11d89fdd1b3f.log
AC-1.2: `next dev`, `next build`, `next start` and `lighthouse` (bare or behind a package runner) classify as heavy commands the wall books.
  provenance: issue #51 defect 1 and proposed fix; three `npx playwright test` runs with no gate request; cmd-class.sh's `suite` class
  serves: REQ-1
  fails-when: any reads `none`
  eval: T2 — `tests/cmd-class.test.sh` §C1 → `next dev`, `npx next build`, `next start`, `npx lighthouse http://x` read `compile` or `browser`
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T4-cmd-class-11d89fdd1b3f.log
AC-1.3: A Bash call carrying a command of AC-1.1 or AC-1.2 is rewritten into booked.sh by the wall, so its run leaves a request in the gate store.
  provenance: issue #51 defect 1 and proposed fix; three `npx playwright test` runs with no gate request; cmd-class.sh's `suite` class
  serves: REQ-1
  fails-when: the command is not wrapped, or the request lacks `class=`
  eval: T2 — `tests/background-suite-guard.test.sh` §B-CLASS → the wall's wrap text for `npx playwright test x` names booked.sh with `--class browser`; in a planted store the shim leaves a request `class=browser`
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T25-background-suite-guard-67508196c4f9.log
AC-1.4: A command of these classes that the wall already refuses or wraps for another reason keeps that reading; the new class adds a booking, never removes a refusal.
  provenance: issue #51 defect 1 and proposed fix; three `npx playwright test` runs with no gate request; cmd-class.sh's `suite` class
  serves: REQ-1
  fails-when: the new class skips the backgrounded refusal
  eval: T2 — `tests/background-suite-guard.test.sh` → a backgrounded `npx playwright test x &` is refused as a backgrounded suite is today
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T25-background-suite-guard-67508196c4f9.log
AC-2.1: A request the wall books for a command of REQ-1 is filed `kind=work` with `class=browser` or `class=compile` on the request, and before its key has a measurement it is promised its class prior: the room free at admission, at least one core (statement aligned with the requirements as amended under D4 and D13, A-orch.30).
  provenance: issue #51 defect 2 and proposed fix; comment finding 1 (a warm lone run is mild, a cold one in a fresh worktree beside ten suites is not); wave-35 D11, ADR-051
  serves: REQ-2
  fails-when: the promise reads 1.61, or the full width on a busy machine
  eval: T2 — `tests/gate.test.sh` §CLASS → `gate_ask work k --class browser` on a fresh key at busy 2.0, lim 6.36, nothing admitted is promised `0:4:0` (the free room); at busy 0 the width
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T3-gate-7a92d2337cd1.log
AC-2.2: A `whole` request is admitted only when nothing admitted is unfinished, and while it is unfinished no other request is admitted.
  provenance: issue #51 defect 2 and proposed fix; comment finding 1 (a warm lone run is mild, a cold one in a fresh worktree beside ten suites is not); wave-35 D11, ADR-051
  serves: REQ-2
  fails-when: a second request is admitted beside the width-promised run
  eval: T2 — `tests/gate.test.sh` §CLASS → at busy 0 on 8 cores at share 92 and reserve 1 a browser ask on a fresh key is promised the width, 6, and a work ask beside it waits (CL.2); a `whole` ask waits while a work request is unfinished (WH rows kept; numbers aligned with the fixture, A-orch.30)
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T3-gate-7a92d2337cd1.log
AC-2.3: The reasoning that removed the solo arms in wave 35 is amended where it is written: a whole booking is about a run's cost, not its correctness, and nothing passes or fails by the clock still holds.
  provenance: issue #51 defect 2 and proposed fix; comment finding 1 (a warm lone run is mild, a cold one in a fresh worktree beside ten suites is not); wave-35 D11, ADR-051
  serves: REQ-2
  fails-when: a site stands unamended
  eval: T0 — `/usr/bin/grep -n 'owed its measured cost' payload/scripts/lib/walls.sh payload/scripts/booked.sh .bionic/docs/adrs/epic-23-bionic-tech-debt/adr-051-*.md` → three hits (the ADR path corrected at A-orch.32: ADR-051 has no tracked copy under docs/adrs)
  task: T12
  evidence: record/wave-49-what-a-run-costs/T12.md
AC-3.1: `gate_end` writes the run's measured cores as a field of the key's cost line, read from the child's CPU time over its wall time.
  provenance: issue #51 defect 2 and proposed fix ("charge a request its measured cores, already within reach of gate_end"); comment finding 1 (cost depends on a cold or warm cache, which a measurement captures and a flat number cannot); ADR-060 (1.61)
  serves: REQ-3
  fails-when: the line has three fields, or the fourth reads 0
  eval: T2 — `tests/gate.test.sh` §COST → booked.sh over `bash -c 'i=0; while [ $i -lt 400000 ]; do i=$((i+1)); done'` in a planted store writes a cost line whose fourth field is at least 0.5
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T20-gate-dd9b12e18833.log
AC-3.2: The promise for a key whose cost lines carry cores is read from them by the same robust rule as the seconds (with three or more kept, the largest at or under twice their median; with fewer, the largest), never the flat `_res_suite_cores`.
  provenance: issue #51 defect 2 and proposed fix ("charge a request its measured cores, already within reach of gate_end"); comment finding 1 (cost depends on a cold or warm cache, which a measurement captures and a flat number cannot); ADR-060 (1.61)
  serves: REQ-3
  fails-when: the promise reads 1.61 or the mean, or the largest
  eval: T2 — `tests/gate.test.sh` §COST → three planted lines with cores 5.8, 6.0, 13.0 promise `0:6.0:<s>` (the robust rule's pick, the largest at or under twice the median; plant corrected at T3, A-T3.1)
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T20-gate-dd9b12e18833.log
AC-3.3: A key with no cores on file is promised its kind's default: a work request `_res_suite_cores`, a whole request the width.
  provenance: issue #51 defect 2 and proposed fix ("charge a request its measured cores, already within reach of gate_end"); comment finding 1 (cost depends on a cold or warm cache, which a measurement captures and a flat number cannot); ADR-060 (1.61)
  serves: REQ-3
  fails-when: an unknown key reads 0 or the width; a whole run on a busy machine is promised the width
  eval: T2 — `tests/gate.test.sh` WA.1 kept → a key with no lines is promised `_res_suite_cores`; `whole` at busy 2.0 the free room 4, and the runner's JOBS after the grant reads 4
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T20-gate-dd9b12e18833.log
AC-3.4: A cost line written by 1.29.2 or before, `<seconds>:<epoch>[:<load>]`, is read for its seconds and load as today, and never rewritten or refused.
  provenance: issue #51 defect 2 and proposed fix ("charge a request its measured cores, already within reach of gate_end"); comment finding 1 (cost depends on a cold or warm cache, which a measurement captures and a flat number cannot); ADR-060 (1.61)
  serves: REQ-3
  fails-when: `_gate_seconds` reads 0, or a line is rewritten
  eval: T2 — `tests/gate.test.sh` §COST → three 1.29.2 lines `<s>:<e>:<load>` read their seconds and load as before and promise the prior
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T20-gate-dd9b12e18833.log
AC-3.5: The measured cores are capped at the machine's cores and floored at a small positive value, so a reading from a stalled or forked run cannot promise more than the machine or nothing.
  provenance: issue #51 defect 2 and proposed fix ("charge a request its measured cores, already within reach of gate_end"); comment finding 1 (cost depends on a cold or warm cache, which a measurement captures and a flat number cannot); ADR-060 (1.61)
  serves: REQ-3
  fails-when: a line records more than the machine, or 0
  eval: T1 — `tests/gate.test.sh` §COST → a planted `times` of 400 s over 10 s on 8 cores writes 8; 0.01 s over 10 s writes 0.1
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T20-gate-dd9b12e18833.log
AC-4.1: With three admitted runs older than the load window each measured in the busy cores, the room line's `promised=` carries no term for them.
  provenance: issue #51 comment finding 2 (`promised=4.83` closed the room at load 2.95 on a machine 63 percent idle); gate.sh `_gate_room_line`, the processor rule
  serves: REQ-4
  fails-when: `promised=4.83 room=no`
  eval: T2 — `tests/gate.test.sh` §ROOM → three requests admitted 120 s ago at 1.61, busy 2.95 of 6.4 (8 cores at share 80, reserve 0): `gate_room` reads `promised=0 room=yes` (RM.1; numbers aligned with the fixture, A-orch.30)
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T2-gate-e22c6aee47d1.log
AC-4.2: A run admitted inside the load window is still counted by its promise, so a burst of fresh admissions is not read as free.
  provenance: issue #51 comment finding 2 (`promised=4.83` closed the room at load 2.95 on a machine 63 percent idle); gate.sh `_gate_room_line`, the processor rule
  serves: REQ-4
  fails-when: `promised=0`
  eval: T2 — `tests/gate.test.sh` §ROOM → the same three admitted 10 s ago read `promised=4.0` (±0.1) and `room=no`
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T2-gate-e22c6aee47d1.log
AC-4.3: The admission rule's processor term and the room reading use one rule for when a run's promise yields to the measurement, written once.
  provenance: issue #51 comment finding 2 (`promised=4.83` closed the room at load 2.95 on a machine 63 percent idle); gate.sh `_gate_room_line`, the processor rule
  serves: REQ-4
  fails-when: the two sites disagree
  eval: T2 — `tests/gate.test.sh` §ROOM → at one store and reading, a newcomer at the room's margin is admitted exactly when `gate_room --owed 1` reads yes
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T2-gate-e22c6aee47d1.log
AC-5.1: With nothing admitted and the measured busy cores over the share's cores, a work request is not admitted.
  provenance: issue #51 defect 3 and proposed fix; the processor rule's "or nothing admitted is unfinished" arm
  serves: REQ-5
  fails-when: admitted (rc 0)
  eval: T2 — `tests/gate.test.sh` H.4 inverted → `world_machine 8 8192 30 16`, nothing admitted: `gate_ask work x --within 1` returns 75
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T20-gate-dd9b12e18833.log
AC-5.2: Once the measured load falls under the share's cores, the waiting request with the lowest `asked=` is admitted before any newer one.
  provenance: issue #51 defect 3 and proposed fix; the processor rule's "or nothing admitted is unfinished" arm
  serves: REQ-5
  fails-when: the newer is admitted first
  eval: T2 — `tests/gate.test.sh` §LONE → two waiters, busy falls to 1.0: the lower `asked=` is admitted first
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T20-gate-dd9b12e18833.log
AC-5.3: An unknown load reading keeps today's rule: a request is admitted only when nothing admitted is unfinished.
  provenance: issue #51 defect 3 and proposed fix; the processor rule's "or nothing admitted is unfinished" arm
  serves: REQ-5
  fails-when: admitted beside unfinished work on an unknown memory reading, or a promise faded on an unknown busy reading
  eval: T2 — `tests/gate.test.sh` H.8 and H.9 kept → unknown memory with nothing admitted admits, beside unfinished work waits; an unknown busy reading counts the promises whole
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T20-gate-dd9b12e18833.log
AC-5.4: The landing queue's order among waiters (whole, then landing, then work, by asked) is unchanged by the load wait: the load decides whether the head is admitted, never which request is the head.
  provenance: issue #51 defect 3 and proposed fix; the processor rule's "or nothing admitted is unfinished" arm
  serves: REQ-5
  fails-when: the work request passes it
  eval: T2 — `tests/gate.test.sh` §LONE → a landing and a work request waiting on load: when it falls the landing is admitted first
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T20-gate-dd9b12e18833.log
AC-6.1: A reserve, in cores, is read from the same store as the share (`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/`), with a default the design names, and `_gate_share_cores` is the share's cores less the reserve, at least one.
  provenance: issue #51 comment finding 3 (the 92 percent share leaves the person about 0.6 of a core on an 8-core machine they use interactively)
  serves: REQ-6
  fails-when: 7.36 with reserve 1
  eval: T2 — `tests/gate.test.sh` §SHARE → share 92, reserve 1, 8 cores: `_gate_share_cores` reads 6.36; reserve absent reads 6.36 (default 1); reserve 0 reads 7.36
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T1-gate-11f6c32d55be.log
AC-6.2: The `share` verb prints the reserve beside the share and sets it on request, refusing a value that is not a non-negative number under the machine's cores.
  provenance: issue #51 comment finding 3 (the 92 percent share leaves the person about 0.6 of a core on an 8-core machine they use interactively)
  serves: REQ-6
  fails-when: no reserve printed, or 9 accepted
  eval: T2 — `tests/session-poker-2.test.sh` §SHARE → `share` prints `share=92 reserve=1 cores=8 room=6.36`; `share reserve=2` writes 2; `share reserve=9` exits 2 on 8 cores
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T6-session-poker-2-a4a4a4803b80.log
AC-6.3: The whole run's width (`gate_width`) is sized from the reduced cores, so a whole run also leaves the reserve.
  provenance: issue #51 comment finding 3 (the 92 percent share leaves the person about 0.6 of a core on an 8-core machine they use interactively)
  serves: REQ-6
  fails-when: 7
  eval: T2 — `tests/gate.test.sh` §WIDTH → `gate_width` reads 6 at share 92 reserve 1 on 8 cores
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T1-gate-11f6c32d55be.log
AC-7.1: This run burns at least one carried debt item by a row already on its sites (`debt burn <concept> <row>`), or its continuation carries one line under `## Deferrals` reading `consolidation: none found — <reason>`.
  provenance: D1 ruled "1" (Person A 2026-11-06); ideas/consolidation-force.md; wave-48 D14
  serves: REQ-7
  fails-when: neither
  eval: T0 — `session-poker.sh debt list` → one line `burned T<n>` by a row of this wave, or `grep -c '^consolidation: none found' record/wave-49-what-a-run-costs/continuation.md` → 1
  task: T15, T17
  evidence: record/wave-49-what-a-run-costs/debt.md
AC-7.2: The close-out step text names the standing obligation: one act of consolidation per run, or a stated none, read from the debt ledger and the continuation.
  provenance: D1 ruled "1" (Person A 2026-11-06); ideas/consolidation-force.md; wave-48 D14
  serves: REQ-7
  fails-when: 0
  eval: T0 — `/usr/bin/grep -c 'one act of consolidation' payload/skills/canonical-sdlc/steps/9.md` → 1
  task: T12
  evidence: record/wave-49-what-a-run-costs/T12.md
AC-7.3: The gate's new readings (the booked classes, the measured cores, the once-counted promise, the load wait, the reserve) each have one reader; the structure read raises no duplicate whose both sites this wave landed.
  provenance: D1 ruled "1" (Person A 2026-11-06); ideas/consolidation-force.md; wave-48 D14
  serves: REQ-7
  fails-when: one such line
  eval: T0 — `/usr/bin/grep -c '^debt:' record/wave-49-what-a-run-costs/critic-structure.md` over lines whose two sites are both files this wave landed → 0
  task: T23
  evidence: record/wave-49-what-a-run-costs/auditor-evidence-3.md
  waiver: Person B 2026-11-07T17:34:52Z "all recommended" — not run on this release
AC-8.1: `session-poker.sh sitrep --line` with no plan bound prints its line and nothing on stderr.
  provenance: A-orch.1, met 2026-11-06: `session-poker.sh sitrep --line` printed `hooks/poker/sitrep.sh: line 1400: lq: unbound variable` before its line
  serves: REQ-8
  fails-when: stderr carries `unbound variable`
  eval: T2 — `tests/sitrep.test.sh` §UNBOUND → `sitrep --line` in a fixture with no bound plan: stderr empty, rc 0
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T8-sitrep-bfebd5fa69d5.log
AC-9.1: With the 5-minute busy cores over the share's cores and the room closed, the Patrol's tick decides a dial-down naming the load and the writer it stands down, never QUIET.
  provenance: user 2026-11-06 "the system needs to be able to detect when resources are getting over-taxed, and self-regulate"; "even if constants are used to define resource ceilings, the system should still be able to auto-correct and dial down subagents dynamically, if necessary, in case it's overcommitted the run"
  serves: REQ-9
  fails-when: QUIET
  eval: T2 — `tests/stop.test.sh` §LOAD → `world_machine 8 8192 30 14 14`, room closed, two live writers: the tick prints `STANDDOWN <newest> — load 14.0 over 6.36`
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T7-stop-5d58e7676aad.log
AC-9.2: A writer stood down by the load rule leaves its row ready, not dropped, and the row is offered again once the room reads yes.
  provenance: user 2026-11-06 "the system needs to be able to detect when resources are getting over-taxed, and self-regulate"; "even if constants are used to define resource ceilings, the system should still be able to auto-correct and dial down subagents dynamically, if necessary, in case it's overcommitted the run"
  serves: REQ-9
  fails-when: `dropped`, or no FILL
  eval: T2 — `tests/stop.test.sh` §LOAD → after the stand-down the row's status reads `pending`; at `world_machine 8 8192 30 1 1` the tick prints FILL naming it
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T7-stop-5d58e7676aad.log
AC-9.3: The load rule stands down at most one writer per tick, so the run does not empty itself on one spike.
  provenance: user 2026-11-06 "the system needs to be able to detect when resources are getting over-taxed, and self-regulate"; "even if constants are used to define resource ceilings, the system should still be able to auto-correct and dial down subagents dynamically, if necessary, in case it's overcommitted the run"
  serves: REQ-9
  fails-when: two names on one tick
  eval: T2 — `tests/stop.test.sh` §LOAD → three live writers over the line: one STANDDOWN per tick
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T7-stop-5d58e7676aad.log
AC-9.4: An admitted run is never ended by the load rule; its cost is sunk and its measurement is the next promise.
  provenance: user 2026-11-06 "the system needs to be able to detect when resources are getting over-taxed, and self-regulate"; "even if constants are used to define resource ceilings, the system should still be able to auto-correct and dial down subagents dynamically, if necessary, in case it's overcommitted the run"
  serves: REQ-9
  fails-when: `ended=` with `why=load`
  eval: T2 — `tests/stop.test.sh` §LOAD → the admitted request in the planted store has no `ended=` after the tick
  task: pending
  evidence: record/wave-49-what-a-run-costs/line/T7-stop-5d58e7676aad.log

## Assumptions

Logged to record/wave-49-what-a-run-costs/assumptions.md as A-orch.n and A-T<row>.n.

## Handoff

handoff: .bionic/docs/record/handoffs/2026-11-07-wave-49-what-a-run-costs.md written 2026-11-07 09:37 PST
## SDLC State

integration-branch: main
working-branch: wave/49-what-a-run-costs
base: main @ 59350b5e6 (1.29.2, PR #50)
intent: build
rigor: double
scale: wave
current: 4
approved-by: Person A 2026-11-07T02:25:48Z "Approved"
- Step 0: configured at 2026-11-07T01:10Z via Person A "approved, D1: 1" at the Step-0 card (card.sh step0, record/wave-49-what-a-run-costs/step0-card.txt); prereqs: ok; D1 "1" (the consolidation force rides as a standing requirement, ideas/consolidation-force.md); model_plan=orchestrator=claude-fable-5-1; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=haiku-high; auditor=opus-high; critic=opus-high; probe cores=8 mem_gb=8 disk_free_gb=23 load_1m=1.36; share 92; branch wave/49-what-a-run-costs off main @ 59350b5e6 (1.29.2, PR #50); no wave was open (wave 48 delivered 2026-11-05T20:56Z); the seed is GitHub issue #51 and its comment, copied to ideas/bionic-1.30.0-gate-cost-report-20261106.md with the reporting project named generically
- Step 1: requirements: specs/epic-23-bionic-tech-debt/wave-49-what-a-run-costs.requirements.md; approved at 2026-11-07T01:21Z by Person A "approved" at the Step-1 card (record/wave-49-what-a-run-costs/step1-card.txt); 8 requirements in 4 themes, 25 criteria, 0 deferrals adopted, 41 carried, 14 debt items adopted (record/wave-49-what-a-run-costs/debt.md); D1 "1" (the consolidation force is REQ-7); the approve verb refused `approval:step1` since no row names it, so the approval is recorded here, as at wave 48
- Step 2: spec: specs/epic-23-bionic-tech-debt/wave-49-what-a-run-costs.spec.md; approved at 2026-11-07T02:12Z by Person A "approved" at the Step-2 card (record/wave-49-what-a-run-costs/step2-card.txt); the design interview held: D2 "1" (the frame, its principle restated in Person A's words, A-orch.4), D3 "1" (rider: simple and elegant), D4 "2", D5 "1", D6 "1", D7 "2" at the walk, D8 to D12 the tactical defaults ruled "approved" at the card; REQ-9 added at Step 2 with attribution and AC-9.1, AC-9.3 corrected under D7; ADR-077 drafted at adrs/epic-23-bionic-tech-debt/adr-077-the-gate-steers-by-the-load.md; eval design 30 rows (4 static, 1 unit, 25 hermetic); research at record/wave-49-what-a-run-costs/research-gate-control-law.md (w49-R1)
- Step 3: plan: plans/epic-23-bionic-tech-debt/wave-49-what-a-run-costs.plan.md; approved at 2026-11-07T02:25:48Z by Person A "Approved" at the Step-3 card (record/wave-49-what-a-run-costs/step3-card.txt); 15 rows (9 build, 1 verify, 2 review, 1 doc, 1 integrate, 1 close), matrix 30 rows rendered by matrix-render; chain T1 → T2 → T3 → T5 → T9 → T10 → T12 → T13 → T14, 425 min, peak width 3
- Step 4: rows dispatched from the working branch; worktree: spawned per row by spawn-worktree.sh under .worktrees/; base-sha: 59350b5e6; branch: wave/49-what-a-run-costs; dispatch ledger below
  worktree: .
  base-sha: 59350b5e6
  branch: wave/49-what-a-run-costs
  share: 92
- session: 00000000-0000-4000-8000-000000000001 bound 2026-11-07T01:06:35Z by write
- T1: landed 11f6c32d55bee4421acecfce9c1abd7734c6afbf 2026-11-07T02:37:51Z — .worktrees/49-T1
- T2: landed e22c6aee47d17249e5c791384475464d579f3775 2026-11-07T03:26:26Z — .worktrees/49-T2
- T4: landed 11d89fdd1b3f0937bab1beb5adc9241eeb62613d 2026-11-07T02:38:38Z — .worktrees/49-T4
- T6: landed a4a4a4803b80288c115684d96e1cb5ba78f48d4b 2026-11-07T02:52:53Z — .worktrees/49-T6
- T7: landed 5d58e7676aadc3c110b158cd7534474959793105 2026-11-07T03:11:33Z — .worktrees/49-T7
- T8: landed bfebd5fa69d550bcd767f3dfab22168211324a90 2026-11-07T02:57:36Z — .worktrees/49-T8
- T15: landed 2059d7286bae121523e35d9cee33a954c269d706 2026-11-07T03:25:39Z — .worktrees/49-T15
- T16: landed 43c8a129bccb6547aa718f9f7e6fb0edf52c84a2 2026-11-07T03:05:04Z — added by task-add at 2026-11-07T02:59:59Z
