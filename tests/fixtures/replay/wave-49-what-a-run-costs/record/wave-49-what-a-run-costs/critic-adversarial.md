reviewed: 59350b5e6a5b16a42933825fab8148cee4465c48..68ef6f3350834e887d6cd212c975a114348aabfa
question: adversarial
result: fail
scope: whole
findings: 7
finding: 1 S2 on payload/scripts/lib/gate.sh:462 a key whose measured cores exceed the share's line is never admitted again, and as the head of the order it holds every other request
shown: 1 bash /fixture/project/.bionic/tmp/scratch/00000000-0000-4000-8000-000000000002/w49-T11/probe-overlim.sh; bash /fixture/project/.bionic/tmp/scratch/00000000-0000-4000-8000-000000000002/w49-T11/probe-headblock.sh
finding: 2 S2 on payload/scripts/lib/gate.sh:1311 the measured cores are every child the holder's shell ever reaped over the run's wall seconds, so the gate's own polls while it waited are charged to the run
shown: 2 bash /fixture/project/.bionic/tmp/scratch/00000000-0000-4000-8000-000000000002/w49-T11/probe-pollcpu.sh
finding: 3 S3 on payload/scripts/lib/walls.sh:5757 a browser or compile key is the whole command's first 60 characters, which a `cd <tree> || exit 1;` prefix fills, so every heavy command of one tree shares one cost line and no tree's measurement reaches another
finding: 4 S3 on payload/scripts/lib/gate.sh:763 the linear 60-second fade under-counts a fresh run by up to 37 percent of its promise, because the 1-minute load average is exponential
finding: 5 S3 on hooks/poker/tick.sh:2559 the dial-down stops a writer whose detached runs and waiting asks live on, so the load does not fall on the stop and the next tick still over the line stops another
finding: 6 S3 on payload/scripts/lib/walls.sh:5215 a browser or compile run typed on the orchestrator's thread is booked and followed in the foreground, where a suite of the same length is refused and farmed out
finding: 7 S4 off hooks/session-poker.sh:3452 the share verb's header says both files are as they were on a refused write, but a reserve write that fails after the share write leaves the share changed

## 1 — a measured key over the line halts the gate (S2 on, fix)

`gate_end` caps a measured value at the machine's cores (gate.sh:1314, `k > c` with `c = _res_cores`), and `_gate_cores_for` hands any measured value back as the promise with no bound (gate.sh:462-463). The line it is admitted against, `_gate_share_cores`, is at most cores × share ÷ 100 − reserve, so with the default reserve of 1 it is always below the cap: 6.36 on 8 cores. A measured value in (6.36, 8] makes `busy + faded + promise > lim` true on any reading, the empty store and the idle machine included (gate.sh:793). The order rule admits only the head and lets nothing pass it (gate.sh:147-149, 775), so while that request's holder is alive no other request in the store, on any project of this user, is admitted. The detached shim waits up to BIONIC_SETTLE_MAX_WAIT (1200 s), ends 75, and the writer's next ask takes the head again with the lowest `asked=`.

The value is reachable by the class this wave books: the issue measured a cold Turbopack compile "on every core", and a parallel `jest` (workers = cores − 1) or any run that waited long (finding 2) measures there too. On a 4-core machine the line is 2.68, so a three-worker suite is enough.

Probe output (logs beside the scripts in the same scratch folder, probe-overlim.log and probe-headblock.log):

```
share_cores=6.36 width=6 reserve=1
key=k6.0 measured=6.0 idle machine, empty store: gate_ask rc=0 id=1
key=k7.5 promise=0:7.5:30
gate: request 2 not admitted within 4s; it keeps its turn, ask again
key=k7.5 measured=7.5 idle machine, empty store: gate_ask rc=75 id=

light: no history, promise 0:1.61:0, idle machine at busy 0.5: gate_ask rc=75
1 waiting kind=work asked=1794028172 admitted=- ended=- rc=- key=heavy
2 gone kind=work asked=1794028174 admitted=- ended=- rc=- key=light
```

No suite pins it: §COST plants 5.8, 6.0 and 13.0 and asserts the promise string 0:6.0, never an admission of a key measured past the line. The fix belongs in `_gate_cores_for`'s measured arm. Two shapes differ in what they admit: bound the measured promise by the free room, max(1, floor(lim − busy − faded)), as D13 bounds the prior (admits it whenever a core is free, under-counting the run); or bound it by floor(lim) (admits it only near idle, the wait A-T2.6 named and D13 ruled against). Which bound is a D13-adjacent choice; the defect is not.

## 2 — the gate's own polls are charged to the run (S2 on, fix)

`times` (gate.sh:1311) reports every child the shell has reaped since it started. In booked.sh the ask, its polls, the shim's setup and the run share one shell (booked.sh:536 asks in it, :470 ends in it), and the divisor is only the seconds since admission. A probe of one waiting ask in a planted store, poll 2 s:

```
before:  0m0.002s 0m0.003s   (children user, system)
gate_ask rc=75 waited=29s
after:   0m0.385s 0m0.619s
```

That is about 1.0 s of child processor time per 29 s of waiting, 0.035 cores. A detached ask may wait 1200 s (booked.sh:862), about 41 s of processor time. A 20-second one-core suite that waited 10 minutes measures (20 + 21) ÷ 20 = 2.05 cores; a 10-second one after 20 minutes measures over 5, past the line of finding 1. The robust pick keeps a value at or under twice the median, so one inflated line among three near 1.0 is the promise. The overcount is largest exactly when the machine is loaded, which is when the promise matters. A-T3.5 logged the effect and kept "one builtin and no baseline" by D3's rider; one more `times` read at admission, subtracted at the end, keeps the builtin. The fix row's choice is where that baseline is taken: in `gate_ask` after its admission line, which covers every holder, or in each caller.

## 3 — the heavy key is the tree's path (S3 on, defer)

`_bsg_wrap_text` builds the browser and compile key from `_c`, the whole command (walls.sh:5726, 5757), and truncates it at 60 characters. A writer is told to type `cd <TREE> || exit 1; <cmd>`. The expression, applied to such commands (probe-key.sh, log beside it):

```
cd /fixture/home/workspace/personal/app/.worktrees/12-T8 || exit 1; npx playwright test e2e/built-safe.spec.ts
  -> cd__Users_admin_workspace_personal_app_.worktrees_12-T8____e
cd /fixture/home/workspace/personal/app/.worktrees/12-T8 || exit 1; npx next build
  -> cd__Users_admin_workspace_personal_app_.worktrees_12-T8____e
```

So `next build` and `playwright test` from one tree share one cost line: a warm browser run's low measurement is the next cold build's promise, which lifts it past D13's free-room prior. And the issue's scene, cold runs in fresh worktrees, is a new key in every tree, so the measurement never reaches it. The spec's assumption, "two spec files are two keys", holds only for a command typed without a `cd`, and it is not in assumptions.md. §B-CLASS plants only the bare form. The load reading bounds the harm to about a load window per admission, which is why this is S3.

## 4 — the fade is linear, the load average is not (S3 on, defer; against D5, the user's)

`_res_busy_cores` is the 1-minute load average (resources.sh:492), an exponential average: after t seconds of a steady run it holds 1 − e^(−t/60) of it. `_gate_faded` weights the promise 1 − t/60. The sum the gate counts (fade-vs-ema.log):

```
age_s  load_sees  linear_fade  gate_counts
   30      0.393        0.500        0.893
   60      0.632        0.000        0.632
   90      0.777        0.000        0.777
  120      0.865        0.000        0.865
```

Through the second minute a fresh admission is counted at 63 to 87 percent. For a browser run promised a 5-core free room, about 1.8 cores read free at 60 s, one more suite admitted beside it. That is the issue's comment finding 2 inverted: the double count is gone, and an under-count stands in its place. Weighting by e^(−age/60), the exact complement of the average, removes it in the same function at no added cost. The spec's assumption that "a linear fade over 60 s is a fair stand-in" is written there, but the research does not measure it. It recommends against D5's ruled shape, so it is the user's.

## 5 — the dial-down stops writers, not load (S3 on, defer; against D7, the user's)

`tick_load_standdown` picks the newest live unlanded writer by `launched_at` alone (tick.sh:2559) and never reads the gate store. A dispatched writer's booked run is detached (walls.sh: `--detach` whenever no short kill is set, and only the orchestrator's farm-out short pass sets one), so TaskStop leaves both its admitted run and any waiting ask alive: the run keeps its cores, and the waiting ask keeps its turn and runs later in a tree whose row was handed back to pending. A writer between runs costs, by the issue's principle, a fraction of a core. So the stop frees almost nothing within the five-minute window the rule reads, and every tick until that average falls stands down one more (A-T7.9). AC-9.4's test asserts no `ended=` in the store after the tick, which the tick cannot write in any case, so it would pass under any rule. A rule that skips a writer holding an admitted or waiting request, or that waits for a stand-down's five-minute window before the next, would act on the load it reads. Either departs from D7 as ruled, so it is the user's.

## 6 — a heavy run on the orchestrator's thread (S3 on, defer)

`classify_tier1` answers browser and compile as it answers none (walls.sh:5215, A-T4.3), so the farm-out wall never refuses them. The wrap books them `--detach`, and without `--no-wait` the caller follows the log to its end (booked.sh:773, and :714 when it attaches). So a cold `next build` typed by the orchestrator holds its thread for the build, where a suite over the short limit is refused and dispatched. It is no regression (both ran unrefused at 1.29.2, AC-1.4 holds), but it is the heaviest class the wall now knows, and the only heavy one that stays on the thread.

## 7 — the share verb's header (S4 off, note)

hooks/session-poker.sh:3452 says "whichever it is, both files are as they were". The loop at :3488-3498 writes the share and then the reserve, so a reserve write that fails after a share write exits 1 with the share changed. Also: AC-6.2 says "under the machine's cores", and both the verb (:3481, `v <= c`) and `gate_reserve` (gate.sh:269) accept a reserve equal to them.

## Across the pieces, beside the findings

- AC-7.3 reads failed as written: the structure record raises two `debt:` lines whose sites all landed in this wave (the reserve rule, the class vocabulary). The criterion is unproved, so it is the user's.
- The walk (T9) and the auditor (T10) records were not read, by the brief, so this record says nothing on whether the walk reached the code.
- The whole run at 68ef6f335 had not landed under record/ when this record was written: `ls .bionic/docs/record/wave-49-what-a-run-costs/regression-run-68ef6f33*` matched nothing.

## Falsification attempts that held

- **The width ask and the lone guard (A-T3.8).** Only tests/run.sh asks `whole` (`/usr/bin/grep` over payload, hooks and tests/run.sh), and its promise is now the free room, which is admitted whenever a core is free: the promise is floor(lim − busy − faded), and admission needs busy + faded + promise ≤ lim, which holds whenever that floor is 1 or more. The width ask with its floor gone answers 0 on load, and the runner asks again; no other `whole` caller can hang the A-T3.8 way. The hang survives only through the measured arm, finding 1.
- **A-T3.6 and old cost lines.** `_gate_cost_cores` reads only the keyed file (`_gate_cost_file`), never the unkeyed 1.15.0 one whose fourth field is an epoch. It skips three-field 1.29.2 lines (`NF >= 4`). `_gate_seconds` reads `secs:epoch::cores` with an empty load as unloaded (`num($3)` fails), as before. No old line is misread.
- **A-T5.1, the detached argv.** booked_detach forwards agent, kill-after, shell, stamp-dir, suites, class, runner and unplaced (booked.sh:724-732). It drops only --max-wait, by design (its header), and the parent's --detach and --no-wait. Attach matches on tree and full command (booked.sh:625-626), so two heavy commands sharing a key (finding 3) never attach to each other's run.
- **The cost blast's green (cost-blast.log at 7a92d2337).** Six of seven green and booked.test.sh red on DC.0 alone, which T5 re-pinned. A fixture that ends a request writes a fourth field the suites do not assert. A planted line from `world_cost` carries no cores, so those cases read the prior. A green that hid a floor of 0.1 would have to be a case that expects a wait and gets an admission, and that case would read red, not green.
- **Comments naming run history.** Added code lines under payload, hooks, tests/run.sh and tests/lib carry no wave, task, criterion, decision or .bionic path (`git diff -U0 … | grep -E '^\+' | grep -E 'wave-[0-9]|\bT[0-9]+\b|\bAC-[0-9]|\bD[0-9]+\b|\bREQ-[0-9]|\.bionic/|A-T[0-9]|A-orch'`: no output). Test section headers name criteria, as the suites did before this range.
