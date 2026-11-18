reviewed: dd9b12e1883354b73b57fe21b859ef74349d55f2..f87acbfce4ebc03d798b897e6ea5571948635334
question: adversarial
result: flag
scope: piece
findings: 5
finding: 1 S4 on CHANGELOG.md:30 the entry describes T12's head, not the release head: its test-line headroom, its one whole run and its debt count are stale, and T21's read and T22's fix are absent
finding: 2 S4 on docs/adrs/adr-077-the-gate-steers-by-the-load.md:39 ADR-077 and the entry say a measured promise is never less than one core, but a key measured at 0.4 cores is promised 0.4
finding: 3 S4 on CHANGELOG.md:184 the landing numbers leave out T22, the row whose publish rendered them, while counting its four runs
finding: 4 S4 off payload/scripts/lib/line.sh:2583 a runner stopped by TERM while its ask waits leaves its empty id file in TMPDIR, and tests/run.sh:173 does the same
finding: 5 S4 off tests/landing-line-1.test.sh:630 §HOLDER's case (h1) reuses the label of five §ALONE cases at lines 216 to 224

Nothing at S3 or above remains in the piece. Every finding is S4, so the table notes them all and none goes to fix. T22's file form holds under TERM, under a short `--within` and when mktemp fails. The runner's locals and `_GATE_OWN` read as before, and the 75 arm still writes its result file. The version pair holds, and the release-numbers commit is one render by the line.

## 1 — the entry is T12's, not the release head's (S4 on, note)

T12 wrote the entry at 1c3ada20e. T22 and the release-numbers render landed after it, and three of its statements no longer hold at f87acbfce:

- **The headroom.** Line 30 reads "102091 test lines against 102206 of code at the head, 115 to spare". The release check at the head prints `test-ratio: 102145/102214`, so 69 lines are left. A-T22.5 records the same 69. Source: release-check-f87acbfce4ebc03d798b897e6ea5571948635334.log.
- **The regression.** Lines 144 to 148 call the run at 68ef6f335 "the one whole run". They say T17 to T20 "are covered by their rows' own suites" and that "a second whole run at the release head is the orchestrator's". In fact two more whole runs went green, 128 of 128 each: one at dd9b12e18 (A-orch.40) and one at f87acbfce (A-orch.46, regression-run-f87acbfce….log).
- **The ledger.** Line 112 reads "14 items adopted and 4 raised by the structure read, 3 burned, 15 open". debt.md now holds 19 items: usable-cores was raised by critic-structure-2.md. That makes 5 raised, 3 burned and 16 open. Shown by `wc -l < debt.md` (20, one of them the header) and `grep -c burned debt.md` (4, one of them the header).
- **T21 and T22.** No sentence names the fix read or T22's change to the landing runner and the test runner. Without T22, T17's line 60 claim, "the gate's own polls are not charged to the run", was false for both of them. T13's reviews-part renders review and waiver lines under `### The reviews` (hooks/poker/line.sh:1048 to 1157). It does not rewrite the prose under "The walk, the regression, the critic", so these statements ship as written unless a row edits them.

## 2 — "never less than one core" (S4 on, note)

ADR-077's Decision, item 1, and the entry's Migration line for T17 (CHANGELOG.md:60) both say "a measured promise is bounded by the same free room and is never less than one core". The plan's T17 row rules min(measured, max(1, floor(lim − busy − faded))), and the code matches it (gate.sh:482). Only the bound is at least one core. A measured value under it prints as written. probe-sub-one.sh plants three kept lines of 0.3, 0.4 and 0.3 cores on an idle machine:

```
_gate_cost_cores: 0.4
_gate_cores_for work - light.test.sh: 0.4
gate_promise light.test.sh: 0:0.4:10
```

The code is right and the sentence is wrong. The fix is wording only, for example "bounded by the same free room, itself never less than one core".

## 3 — the publishing row is missing from its own numbers (S4 on, note; older than the reviewed range)

The numbers are rendered during T22's publish (landing-proofs.log: `ev=published|row=T22|…|numbers=f87acbfce`). The report reads the record before T22's published line exists. So the rows list 15 queue landings without T22. The summary still counts T22's four green verdicts: `runs: green=42`, against the rows' own runs, which sum to 38 (T12's four plus T22's four took it from 34 at dd9b12e18). The release check agrees because it reads the same report (`landing-numbers: 1.30.0 agrees with the landing report at f86f965faea9`). The 1.29.2 entry has the same gap: its numbers at 01eecc091 list no T18, the row whose publish rendered them. The renderer dates from 2a8e26557 (2026-10-20). The run did not change that code, so it is a next-wave item.

## 4 — the id file left on TERM (S4 off, note)

probe-runner.sh drives the real `_line_runner` at the head behind a held whole request, at poll 0.3. probe-runner.log:

```
case A (TERM while waiting): runner exit 143, result file (none), request 2 holder=- left=…, "handed back on TERM", id files left: 1 line-id.evKqlP
case B (--within 1): runner exit 0, result file gate=75, request 2 holder=-, id files left: 0
case C (TMPDIR=/nonexistent, the $( ) fallback): runner exit 0, admitted=2 at= promised= unstarted=1 actual= rc=1, cpu0=0.37, id files left: 0
```

Case A is A-T22.2's choice, reproduced. The file is empty and harmless. tests/run.sh's `--one` worker sets no EXIT trap, and the whole run's trap removes `$TMP` but not TMPDIR. A path beside the result file, or under `$TMP`, would be swept by what already exists. Case C shows the fallback works. It brings back the subshell baseline only on a host whose TMPDIR cannot be written, which is the shape before T22 and not a regression.

## 5 — a reused case label (S4 off, note)

`grep -n '"(h1' tests/landing-line-1.test.sh` lists `(h1)` at lines 216, 220, 221, 223 and 224 for §ALONE's hand landing, and again at line 630 for §HOLDER's cpu0 claim. A red log line `FAIL: (h1) …` then names two sections. The CENSUS keys by section, so no verdict is lost.

## Falsification attempts that held

- **Errexit inside the ask.** Bash clears `-e` inside `$( )`, so moving gate_ask into the caller's shell would let `_gate_decide`'s non-zero return end a caller running under `set -e`. No caller sets it: `grep -nE 'set -[a-z]*e|errexit' tests/run.sh payload/scripts/lib/line.sh payload/scripts/booked.sh payload/scripts/lib/gate.sh` prints nothing. The runner is spawned by a plain `bash -c` (line.sh:2273).
- **The ask's state leaking into the caller.** probe-leak.sh runs gate_ask through a wait and an admission inside a function holding the runner's locals `id rc p c f`, then diffs the shell's variables. The locals come back untouched: `rc=0 p=SENT c=SENT f=idfile id-file=2`. Every name the ask leaves is gate.sh's own (`_G_*`, `_R_*`, `_GATE_*`, `_SLOTS_SINCE*`). The one that tests/run.sh also assigns is `_GATE_ID`, which `read -r _GATE_ID < "$_f"` overwrites on every path. On a 75 or a failure it is then reset to empty (run.sh:180, 185). The cached `_G_*` tallies do not mislead a later read: gate_state and gate_end each scan again under the lock (gate.sh:1339, 1353).
- **The holder and `_GATE_OWN`.** The holder is written as `$$:<start>` (gate.sh:833). `$$` is the same in a subshell and in its parent, so `_GATE_OWN`'s `"$$:"*` test reads as it did. In probe-runner.log case C, holder=14576 is the runner's pid, and gate_end ended that request in the runner's shell (`ended=… rc=1`).
- **The TERM disposition.** In the caller's shell, `_gate_term_arm` now finds `me == $$` and keeps the caller's own TERM trap, which `_gate_term_disarm` puts back before `_gate_term_end` signals the shell (gate.sh:1162-1186). run.sh traps only EXIT (run.sh:642), and the runner traps nothing, so each still dies of TERM, as case A shows (exit 143, no result line). The drain's TERM reaches `sleep` too (`_line_kill_tree`, line.sh:2226), so the trap runs at once and not a poll later. This is the same as before.
- **Callers still asking in `$( )`.** `grep -rnE '\$\([^)]*gate_ask ' payload hooks tests/run.sh` prints only the three fallbacks (booked.sh:540, line.sh:2587, run.sh:177). close-out.sh's `gate_ask` is a function of its own (close-out.sh:2078).
- **GR.3's floor is measured in another process.** probe-gr3-spread.sh repeats the floor eight times: 0.581 to 0.619 s, about 3 percent either side. The red run read cpu0 0.13 against 0.548, so the margin is wide on both sides. The (h1) case measures in the same shell and is exact.
- **The version pair.** plugin.json, help.md, version.md and the CHANGELOG heading all read 1.30.0. `grep -rn '1\.29\.2' --include='*.json' --include='*.md' payload .claude-plugin`, excluding CHANGELOG, prints nothing. The three refreshed checksums equal `shasum -a 256` of payload/commands/help.md, payload/commands/version.md and payload/skills/canonical-sdlc/steps/9.md. The steps/9 sentence changes doctrine and no verb, so `canonical_sdlc_version` 14 stands by the entry's own policy (CHANGELOG.md:7).
- **The release-numbers commit.** `git show --stat f87acbfce` names one file, authored by "bionic line". Its eleven changed lines are the report header, the summary and the rows for T21, T12 and T23 (`git show f87acbfce | grep -cE '^[-+][^-+]'`: 11). No other prose moved.
- **Known limits.** The plan's five deferred findings are the whole read's #3 to #6 and the fix read's #2. The entry carries five sentences, and the release check prints `known-limits: 1.30.0 carries the 5 deferred sentences`. ADR-077's four "Deferred." bullets are the four that concern the decision. The fifth is a test fixture, so its absence there is right. The fade's "up to 37 percent" in the entry and the ADR's "63 to 87 percent" agree. No limit is reopened in this piece: T22 changes no key, fade or dial-down.
- **ADR-077 against D13.** Item 1 promises a whole run, and a browser or compile run with no measurement, the room free at admission, max(1, floor(lim − busy − faded)), with the runner sizing its jobs from it. That is D13's option "2" as ruled (design-ledger Δ25). The code never reads a whole run's measurement (gate.sh:475), and the ADR claims none. Finding 2 is the one mismatch in this item.
- **The consolidation rule.** It is doctrine at one site, steps/9.md.tmpl:9 and its render, as D1 ruled. Its one named reader, `session-poker.sh debt list`, exists (session-poker.sh:1556).
