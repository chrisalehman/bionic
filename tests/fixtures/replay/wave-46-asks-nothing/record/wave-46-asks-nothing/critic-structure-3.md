reviewed: 5a08f601b5aca8cdf332c0ca1581bcbcdf3ab851..6b7563afb608fccbdcf93beaff95655b086f2d77
question: structure
result: flag
scope: piece
check: reuse FLAG the new test reader ct_task (tests/session-poker-4.test.sh:1894) is wk_key (:1754) with the plan path and key fixed; the product side reuses units_rows for step and kind and walls.sh's regex text, compared against serves_tasks' other callers and lib/units.sh's field order
check: one-site FLAG "the criterion the close proves" (an eval naming landing-report --hand-holds) is now decided twice, MR_AWK taskof (hooks/session-poker.sh:3200) and walls.sh matrix_close_rows (payload/scripts/lib/walls.sh:1815), and no test fails when the two matches disagree
findings: 0
debt: duplicate close-criterion-eval hooks/session-poker.sh:3200, payload/scripts/lib/walls.sh:1815
debt: duplicate ac-block-key-reader tests/session-poker-4.test.sh:1894, tests/session-poker-4.test.sh:1754

# critic-structure-3 — wave-46-asks-nothing, the fix row T31

Reader: w46-T33, at head 6b7563afb608fccbdcf93beaff95655b086f2d77, in the main checkout. I wrote none of this code. The wave's design has no ownership table naming a task-key rule or a close-criterion predicate, so I searched the code for each new site.

The range opens at T30's head, 5a08f601. `git log --oneline --first-parent 5a08f601..31da41f7` prints one commit, 31da41f71 `merge wt/46-T19 (land)`, T19's release-set landing. Its branch carries four commits: d2e50621 (ADR-074), 1bb46ccd (the 1.29.0 entry, plugin.json 1.29.0, help and version rendered, the manifest refreshed), 69c0ce45 (the two §REL-1.28.0 arms retargeted to the 1.28.0 block and a pinned 1.28.0 manifest), and 91808ea8 (the entry's Known limits, committed by the line verb). `git diff --stat 5a08f601..31da41f7` names CHANGELOG.md, the ADR copy, plugin.json, help.md, version.md, rendered.sha256 and tests/release-check.test.sh. e38e7518, the reviews part the verb committed, comes after 31da41f7 and was already in my reading. I read the version, manifest and release-check diffs and the entry. They touch no hook, no matrix criterion and no file T31 changed. release-check went green at 31da41f7 (landing-proofs.log:777), and the whole run at 6b7563af covers them. The entry they wrote is the one adversarial finding 1 rests on, so they support that finding and change no verdict.

## What the piece adds

`git diff 31da41f7171d816640e31a715e1b791304f5483a..wave/46-asks-nothing --stat` names four files: CHANGELOG.md, hooks/session-poker.sh, tests/CENSUS.md, tests/session-poker-4.test.sh.

- `serves_tasks` prints two more fields, step and kind, read through lib/units.sh `units_rows`, the table's one reader. The field order there is id, step, kind, task, agent, deps, size, serves (`payload/scripts/lib/units.sh:175-176`, `disp[1]`..`disp[8]`), so `$2` and `$3` are step and kind. Correct reuse.
- `serves_load` keeps `tstep[]` and `tkind[]`. `grep -n 'tstep\|tkind' hooks/session-poker.sh hooks/poker/*.sh payload/scripts/lib/*.sh` prints only lines 3132, 3196 and 3197 of hooks/session-poker.sh: no collision with LE_AWK or MR_AWK names.
- `taskof` gains the close arm. Nothing else in the codebase chooses a criterion's `task:` row; matrix-render is its one writer.
- The test section adds `ct_row` and `ct_task`.

## reuse

- `ct_task` (`tests/session-poker-4.test.sh:1894-1897`) reads an AC block's `task:` value out of the matrix section. `wk_key` (`:1754-1758`) reads any key of an AC block out of the matrix section; it differs only in reading `$PWK` by name and taking the key as an argument. The writer's reuse line says so ("wk_key reads `$PWK` by name and no shared block-key reader exists in the suite"). Passing the plan path was a one-word change. The product also has the gate's own reader, walls.sh `matrix_block` with `matrix_block_task` (`payload/scripts/lib/walls.sh:1689`, `:1739`), which would have read the key the way the gate does. FLAG, debt of kind duplicate, test-side.
- The hand-holds match reuses walls.sh's regex text (A-T31.2), which is a copy, not a reuse: see one-site.

## one-site

- **The close's criterion is decided in two places.** `matrix_close_rows` picks a row when its block's `eval:` matches `landing-report[[:space:]]+--hand-holds` (`payload/scripts/lib/walls.sh:1815`). `taskof` now picks the close row when the Eval cell matches `landing-report[ \t]+--hand-holds` (`hooks/session-poker.sh:3200`). The two spellings accept the same text today, and matrix-render writes the block's `eval:` from that cell, so no user meets a difference. A change to one, such as a renamed measure, would leave the other reading the old text. FLAG, debt of kind duplicate.
- **The predicate pair has no agreement test.** CT-1 to CT-4 drive only taskof's match. close-replay LV-1 (`tests/close-replay.test.sh:398`) reads a rendered live row whose task is the close row and whose eval is the hand-holds line, and §LIVE then has close-out write it, so the task key's two surfaces, matrix-render's writer and the gate's `matrix_owing_step` reader, are pinned end to end. That rehearsal's live criterion is served by the close row alone, so it reaches the one-row rule, not the new arm, and never asks taskof's regex. `grep -ln 'matrix_close_rows\|matrix_owing_step' tests/*.sh` prints tests/canonical-sdlc-evidence-gate.test.sh and tests/landing-line-1.test.sh. `grep -c 'matrix-render'` on them prints 0 and 10; the landing-line-1 rows were not read one by one, so whether any of them crosses the new arm is unverified, and its census line (tests/CENSUS.md) was not changed by T31. That the LV-1 live criterion has one serving row is unverified; I read the section's comment ("its task the close row T9"), not the replay's plan. No row turns red when one regex is changed and the other is not. That is the duplicate above, written once as debt. The step-9 constant also lives on both sides: `tstep[t] + 0 == 9` in taskof, `= 9` in matrix_close_rows (`walls.sh:1814`) and the literal `9` in `matrix_owing_step` (`:1754`).

## Also seen, not checks

- `over-engineering` was considered for the step-9 fallback, an arm for a plan whose step-9 row is not of kind close, which no fixture builds and the live plan does not have (its T21 is `| T21 | 9 | close |`, plan line 114). It is one branch, not an abstraction or parameter, so it is not raised here; its missing test row is in the adversarial record.
- The interface comment for SERVES_AWK (`hooks/poker/plan.sh:617-626`) lists the globals the concatenated awk programs own and the `serves_load` spec. It now omits `tstep[]` and `tkind[]` and states a two-field spec. That file is outside the reviewed range; it is in the adversarial record as a note.
