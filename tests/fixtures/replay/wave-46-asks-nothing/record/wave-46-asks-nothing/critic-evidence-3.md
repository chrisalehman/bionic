reviewed: 5a08f601b5aca8cdf332c0ca1581bcbcdf3ab851..6b7563afb608fccbdcf93beaff95655b086f2d77
question: evidence
result: flag
scope: piece
findings: 1
finding: 1 S4 off .bionic/docs/plans/epic-23-bionic-tech-debt/wave-46-asks-nothing.plan.md:244 AC-4.1 is the live close row, owed at Step 9, and cannot be judged at this head

# critic-evidence-3 — wave-46-asks-nothing, the fix row T31

Reader: w46-T33, at head 6b7563afb608fccbdcf93beaff95655b086f2d77, in the main checkout. I did not write any of this code. Scope is the piece: T31's change to matrix-render's task rule and what it reaches, the one criterion it serves, and the wave's coverage verdict at this head.

The range opens at T30's head, 5a08f601. `git log --oneline --first-parent 5a08f601..31da41f7` prints one commit, 31da41f71 `merge wt/46-T19 (land)`, T19's release-set landing. Its branch carries four commits: d2e50621 (ADR-074), 1bb46ccd (the 1.29.0 entry, plugin.json 1.29.0, help and version rendered, the manifest refreshed), 69c0ce45 (the two §REL-1.28.0 arms retargeted to the 1.28.0 block and a pinned 1.28.0 manifest), and 91808ea8 (the entry's Known limits, committed by the line verb). `git diff --stat 5a08f601..31da41f7` names CHANGELOG.md, the ADR copy, plugin.json, help.md, version.md, rendered.sha256 and tests/release-check.test.sh. e38e7518, the reviews part the verb committed, comes after 31da41f7 and was already in my reading. I read the version, manifest and release-check diffs and the entry. They touch no hook, no matrix criterion and no file T31 changed. release-check went green at 31da41f7 (landing-proofs.log:777), and the whole run at 6b7563af covers them. The entry they wrote is the one adversarial finding 1 rests on, so they support that finding and change no verdict.

## Coverage

- T31 serves REQ-4 alone (plan line 124, serves cell `REQ-4`). The chain is REQ-4 to D11 (wave-46-asks-nothing.spec.md line 88, which tags D11 with `REQ-2, REQ-4`) and to the ruling D19 (design-ledger Δ16 and Δ17, A-orch.42), to AC-4.1, to its evidence: the live `landing-report --hand-holds` reading at delivered (Eval design, plan line 66). No requirement in the chain is left without a decision or a criterion.
- The whole read at 837ddc39 inverted the spec's tags and the blocks' provenance lines and found no requirement with zero inbound citations (critic-evidence.md, Coverage). This piece adds no requirement and no criterion: `git diff 31da41f7..wave/46-asks-nothing --stat` touches no plan, spec or requirements file. The inversion stands.
- One other criterion names the rule T31 sits beside. AC-10.1 (plan line 352) pins the owing-step rule, which reads a block's `task:`. T31 changes what matrix-render writes into that key on a new plan, not how the gate reads it, so AC-10.1's evidence does not move.
- On this plan T31 changes nothing. AC-4.1's block already reads `task: T21` (`awk '/^AC-4.1:/{p=1} p{print; if(++n>10) exit}'` on the plan), written by the matrix-set at 04:58:30Z (A-orch.30, A-orch.37). matrix-render never rewrites a present key. The change serves the next run's Step 3, which is the substance D19 asked for: the cause fixed, not the key.

## Power

- **AC-4.1.** Its observation, `hand-holds: total=0 … needs-you=0` at delivered, would show a count above zero had the AC-4.1 task write still fallen in the window. A-orch.44 records the line at `total=0 · status-writes=0 (window since T31's landing)`, after `total=1 · status-writes=1` at A-orch.37. I did not re-run `landing-report --hand-holds` (outside my brief's runs), so the current reading is unverified by me. The zero now comes from the window moving past the write, which any build landing after it would also have done, whatever it changed. So the close's reading cannot tell a fixed cause from a moved window. The person ruled this route (D19 "2"), and the rule is the 1.28.0 entry's listed limit. The adversarial record carries the entry's silence on it as its finding 1. The row stays live and UNVERIFIABLE here.
- **T31's own rows.** CT-1 is the change detector. Absent T31, CT-1 reads `0|pending` where it wants `0|T3`, and the red log shows exactly that (below). CT-2 fails if the arm ignores the eval, CT-3 if the one-row rule breaks, and CT-4 if a second close row is resolved instead of left pending. Two changed conditions have no row of their own: the step-9 fallback (`hooks/session-poker.sh:3197`, A-T31.3), and the kind arm as distinct from it, since every close row in §CLOSE-TASK sits at step 9 (adversarial finding 2). These rows prove T31's render, not a matrix criterion, so the gap takes no power from AC-4.1.

## Authenticity

1. **Re-executed, session-poker-4 at this head.** The brief's logged command:

   ```
   cd /fixture/project || exit 1; LOG=.bionic/docs/record/wave-46-asks-nothing/T33-session-poker-4.log; set -o pipefail; tests/run.sh --only session-poker-4.test.sh 2>&1 | tee "$LOG"; rc=$?; echo "rc=$rc" >> "$LOG"; exit $rc
   ```

   The log, .bionic/docs/record/wave-46-asks-nothing/T33-session-poker-4.log, opens `head=6b7563afb608fccbdcf93beaff95655b086f2d77 dirty=0` and ends `Gating: 1 passed, 0 failed`, `All gating suites green ✓`, `rc=0`. It agrees with the landing verdict log line/T31-session-poker-4-1df303f2f7aa.log, which reads `PASS: CT-4 …` and `session-poker-4.test.sh: 501/501 passed, 0 failed`. The code is the same at both heads: 6b7563af changes only CHANGELOG.md (`git show --stat --format= 6b7563afb` prints `CHANGELOG.md | 6 ++++--`).
2. **The red, read.** T31-session-poker-4-red.log opens `head=e38e7518e2f7f93a749071ea40e17eee009468ff dirty=1` with roots in the T31 tree, so the hook was at base and only the test was new. Its one failure is `FAIL: CT-1 … expected '0|T3', got '0|pending'` (line 536), then `500/501 passed, 1 failed` and `rc=1`. It is a red of the new row against the pre-change file, not a suite-wide failure.
3. **The reach, read.** landing-line-1 and landing-line-2 ran green on the landing candidate 1df303f2: landing-proofs.log:917-918 `result=green`, and their logs read `328/328 passed` and `215/215 passed`. The whole run at this head is green: regression-run-6b7563afb608fccbdcf93beaff95655b086f2d77.log ends `Gating: 127 passed, 0 failed` and `rc=0`, and plan line 130 reads `stack-health: green head=6b7563af… pass=127 total=127`.

The tier AC-4.1 uses, T3 live, has no command to re-execute before delivered.

## Row verdicts

| AC | verdict | why |
|---|---|---|
| AC-4.1 | UNVERIFIABLE | live at delivered (finding 1); T31 leaves its present `task: T21` as written, and the zero the close will read now rests on the window starting at T31's landing, the 1.28.0 listed limit the person's ruling D19 accepted |

verdict: CONFIRMED — the piece adds no requirement or criterion, REQ-4 runs from D11 and the ruling D19 to AC-4.1 and its live reading at delivered, T31's render change is proved red then green on its own row (CT-1 red at base, session-poker-4 green at 6b7563af in the landing's log and in my re-run), the rows it reaches through serves_load are green at the landing, and the whole run at this head is 127 of 127; AC-4.1 stays owed at Step 9, and its zero cannot tell a fixed cause from the window moving past the write
