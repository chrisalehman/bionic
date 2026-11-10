reviewed: 68ef6f3350834e887d6cd212c975a114348aabfa..dd9b12e1883354b73b57fe21b859ef74349d55f2
question: adversarial
result: fail
scope: piece
findings: 2
finding: 1 S2 on payload/scripts/lib/gate.sh:1248 the baseline leaves out an asking subshell's own seconds, and the landing runner asks inside `$( )`, so a landing that waited is still charged for its polls
shown: 1 bash /fixture/project/.bionic/tmp/scratch/00000000-0000-4000-8000-000000000002/w49-T21/probe-subshell-cpu0.sh subshell 125; bash /fixture/project/.bionic/tmp/scratch/00000000-0000-4000-8000-000000000002/w49-T21/probe-subshell-self.sh
finding: 2 S3 on tests/slots.test.sh:223 B2's re-pin reads the host's share and reserve, so on a host at share 82 or below, or reserve 1.76 or above, its first shim is never admitted and the suite hangs the whole run again

## 1 — the baseline misses the asking subshell (S2 on, fix)

Finding 1 of the whole read is fixed for one of the gate's two asking forms, not both. `gate_ask` writes `cpu0=` from the second line of `times` in the shell that runs it (gate.sh:1248). booked.sh asks in its own shell through a file (booked.sh:536), so that shell's count and the end's count agree. The landing runner asks inside a command substitution (line.sh:2580) and ends in the parent (line.sh:2605). tests/run.sh asks the same way (run.sh:170). In that form `cpu0=` holds only the subshell's children. When the parent reaps the subshell it gains the subshell's children and also the subshell's own seconds, the first line of `times`. The bash work of every poll's scan is in that first line, and it grows with the store. A-T17.2 named this gap and left its size unverified. This probe measures it.

The probe runs an ask that waits about 20 s at poll 2 over a planted store of ended requests, then a 5 s run of `sleep`, and ends it. The live store holds 125 requests now (`ls ~/.claude/bionic/gate/requests | wc -l`). Output, probe-subshell-cpu0.log in the scratch folder:

```
form=direct   planted=125  cpu0=0.81  holder children after the ask returned: 0m0.313s 0m0.506s  cores 0.1
form=subshell planted=125  cpu0=0.80  holder children after the ask returned: 0m0.617s 0m0.653s  cores 0.1
form=direct   planted=400  cpu0=0.80  holder children after the ask returned: 0m0.319s 0m0.492s  cores 0.1
form=subshell planted=400  cpu0=0.75  holder children after the ask returned: 0m1.099s 0m0.780s  cores 0.23
```

The direct form subtracts the wait exactly: 0.81 against 0.82. The subshell form leaves 0.47 s at 125 requests and 1.13 s at 400, per 20 s waited. That is about 0.024 s of processor time per second waited at today's store size. The first critic measured 0.035 s per second for the polls this row was meant to remove. So the landing runner keeps about two thirds of finding 1's overcharge at today's store, and more as the store grows.

Real landing runs are short. The live cost file d70b46fe%runner-width.test.sh keeps three 10 s runs at 0.82 to 0.89 cores. A landing that waits 300 s behind a whole run, as T12's waits now, then runs that 10 s suite, writes about (8.5 + 7) / 10 = 1.55 cores. The robust pick keeps a line at or under twice the median, so that one line is the key's next promise: nearly twice its cost. A wait of 900 s, a common `ready --within`, writes about 2.95. The bound now caps any promise at the free room, so the order cannot halt. The landing's promise is still wrong, and it holds the room's other landings out for the promise's first minute.

The fix shape is proven exact. probe-subshell-self.log shows a subshell's first line plus its second equal what its parent gains: 0.761 + 0.446 = 1.207, against 1.208. Either of two fixes works. The landing runner and run.sh could ask through a file, as booked.sh does, which fixes the callers. Or the ask could record its own first line as well, but only when it runs in a subshell its holder will reap. A `BASH_SUBSHELL` test alone would over-subtract for a holder that is itself a subshell. Note for the orchestrator: a gate.sh fix would be this component's third fix row, after T17 and T20.

## 2 — slots B2 depends on the host (S3 on, defer)

T18 moved B2 to 4.0 busy cores. Its comment states the line, 6.36, as if the suite planted it. The suite plants only the cores (slots.test.sh:125-126). `bk` does not set `CLAUDE_CONFIG_DIR`, and tests/run.sh does not either (`grep -n CLAUDE_CONFIG_DIR tests/run.sh tests/slots.test.sh`: no output). So `gate_share` and `gate_reserve` read the host's files. Before the lone guard went, B2's first ask was admitted on any host. Now it needs 4.0 + 1.61 to fit the host's line. The B2 shim asks with no ceiling, and A-orch.25 records 28 minutes of exactly that wait. probe-b2-host.log, the first ask at B2's planted machine under host files:

```
share=-  reserve=-: lim=6.36 rc=0
share=83 reserve=-: lim=5.64 rc=0
share=82 reserve=-: lim=5.56 rc=75
share=80 reserve=-: lim=5.4  rc=75
share=92 reserve=2: lim=5.36 rc=75
share=92 reserve=1.4: lim=5.96 rc=0
```

A person who sets `share reserve=2`, the example SS.2 itself uses, or a share of 82 or lower, hangs the whole run at slots.test.sh. A-T18.3 gives the threshold as "about 70". With the default reserve of 1 it is 83. The workaround is A-T18.3's own candidate: plant `CLAUDE_CONFIG_DIR` in GE, as session-poker.prelude.sh:69-70 does for its suites.

## Falsification attempts that held

- **The bound against admission.** `_gate_cores_for` computes the free room once (gate.sh:482, the only `int(l - b - f)` in payload and hooks). `_gate_decide` passes it the busy and faded figures its own test reads (gate.sh:790-802). So a promise of floor(free) always fits, and a measured value under it prints as written. When the free room is under 1, x is 1 and the test refuses until a core is free. That is the prior's behaviour, and a measured value under 1 core is still printed as itself. The under-count is the ruled shape (A-orch.24, D13): a 7.5-core key at busy 5.0 is promised 1 and runs about 6 cores over the line, until the load reading holds it. That is finding 4 of the whole read, not a new defect.
- **gate_promise outside the lock.** It reads a faded sum of 0, or the last scan's list in a shell that scanned. So its cores can differ from admission's. Its only callers outside the tests are line.sh's five `_gate_promise` reads (line.sh:1509, 1530, 1551, 2202, 2288), and each takes the seconds alone (`${p##*:}`). The seconds read is unchanged in this piece. CO.5b and CO.5c pin the set -u reader, which went red at 9b03489c5 (A-T20.2).
- **Nested, believed and ended-elsewhere admissions.** The believed path returns before the loop (gate.sh:1218-1222). The lineage path returns before `_gate_decide` (gate.sh:1243). So neither writes `cpu0=`, as T17's brief asked. Every `gate_end` caller runs it in the asking shell or its parent: booked.sh:470, line.sh:2605, run.sh:197, and `_gate_term_end`. stop-run's end (roster.sh:192) writes no cost line. No caller ends a run inside `$( )` (`grep -rnE 'gate_end '` over payload, hooks and tests/run.sh).
- **The in-run sampling.** Both holders call gate_state while their run goes on. One call leaves 0.023 s of children in the holder's `times` at store sizes 0 and 125 (probe-sample-cpu.log). That is about 0.023 cores of bias for the landing runner, under the 0.1 floor's scale. It is not a finding.
- **The shared pick.** `_gate_cost_cores` sorts `v` in place and leaves `t` in file order. It then prints the first `t[i]` whose value equals the pick, which is the line's own spelling (A-T17.6). `_gate_seconds` prints `%d` of the same pick. The new while-walk equals the old for-walk on non-negative values. The pick's locals `k` and `m` shadow `_gate_seconds`'s own `m` and `c`.
- **The reserve predicate.** The verb and the reader call one predicate (session-poker.sh:3478, gate.sh:277). SS.4 went red at 68ef6f335 (w49-T17/red-sp2.log) and on the shape-arm mutant (mutant-sp2.log). A ten-character hand-written file now reads 1 where it read its number (A-T17.4). The verb already refused that value, so only a hand edit meets it.
- **§ORDER's 2.** The suite plants share 80 in its own config directory, with no reserve file (session-poker.prelude.sh:69-70), so the line is 5.4. Under the old max-of count the answer is 3, and with reserve 0 under either count it is 3. So the 2 goes red if either change is undone (A-T19.1's arithmetic, checked).
- **RM.5 and the reader's seam.** `room()` redefines `_res_busy_cores` from `BUSY_FILE` after sourcing, inside the reader's own subshell (gate.test.sh:580). So RM.5 reads the unknown busy reading at the room and not only at an ask. On the mutant it read 2.415 (w49-T20/red-mut.log).
- **Comments naming run history.** No added line names one (`git diff -U0 68ef6f335..dd9b12e18 -- payload hooks tests | grep -E '^\+' | grep -E 'wave-[0-9]|\bT[0-9]+\b|\bAC-[0-9]|\bD[0-9]+\b|\bREQ-[0-9]|\.bionic/|A-T[0-9]|A-orch|finding'`: no output).
