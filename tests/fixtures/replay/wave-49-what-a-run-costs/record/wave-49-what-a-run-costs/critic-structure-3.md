reviewed: dd9b12e1883354b73b57fe21b859ef74349d55f2..f87acbfce4ebc03d798b897e6ea5571948635334
question: structure
result: flag
scope: piece
check: reuse FLAG T22 copied booked_ask's ask-through-a-file (booked.sh:532-541) into _line_runner (line.sh:2583-2588) and _gate_ask_for (run.sh:173-178): three copies of one rule, ask in the holder's shell and read the id back through a file, `$( )` only when no file can be made; the copies already differ in cleanup, since booked.sh removes its id file by a process-wide trap and the two new copies leave it on TERM (A-T22.2, probe-runner.log case A), which no user meets as a wrong result, so this is debt and not a FAIL; compared against gate.sh (no helper does this, and the stop rule held it untouched) and the other gate_ask callers (`grep -rnE 'gate_ask ' payload hooks tests/run.sh`: these three, and close-out.sh's own gate_ask function); T12 adds no function, file, type or key: its edits are prose, the version and rendered pages, and the numbers commit is the line's render
check: one-site PASS no rule, value or decision this piece writes is computed at a second site: the cpu0= baseline is still written by gate_ask alone (gate.sh:1248) and read by gate_end alone in the same shell, and T22 moved only where the callers ask; the consolidation rule is one sentence in steps/9.md.tmpl:9 and its render, read by `debt list`; the version is one value, plugin.json, rendered into help.md and version.md; the two new test oracles parse `times` on their own and not through `_gate_cpu`, by design, since an oracle that called the code under test would prove nothing; the shared pairs the piece touches each name a test seen red: the caller's ask and gate_end's baseline, landing-line-1 §HOLDER (h1) and runner-width GR.3 (w49-T22/red-landing-line-1.log `no: cpu0=0.17 before=0.585`, red-runner-width.log `no: cpu0=0.13 floor=0.548`); the CHANGELOG heading and plugin.json, release-check §VERSION-PAIR (iii), whose arm doctors plugin.json and asserts exit 1; the rendered pages and their templates, `render.sh --check` in render.test.sh, whose Section 3 plants an input and asserts the archive arm red; Known limits and the plan's deferrals, release-check known-limits, seen refusing T12's four-sentence entry (A-orch.39); the landing numbers and the landing report, release-check §FROM-REPORT
findings: 0
debt: duplicate ask-through-file payload/scripts/booked.sh:536, payload/scripts/lib/line.sh:2584, tests/run.sh:174

## The debt line

- **ask-through-file.** "Ask the gate in this shell, the id read back through a temp file, `$( )` when no file can be made" is now written three times. Each copy is four lines, with the same mktemp, redirect, `read -r` and `rm -f`. The brief asks whether a four-line idiom is a site. It is here, because it encodes a rule rather than a shape. gate.sh's own comments say gate_ask and gate_end must never run inside `$( )` (gate.sh:1274, 1282), so every caller has to carry the workaround. The copies have already drifted on cleanup. A next change, such as moving the id file out of TMPDIR (critic-adversarial-3.md #4) or into the gate's store so that the fallback never fires, means three edits. The burn is one gate.sh helper that asks and sets a named variable, for example with `printf -v`, which the three callers then call. It is paid when gate.sh is next touched. This run could not touch it under the stop rule (A-orch.37, A-orch.38).

## The debt table

- No item was burned in this piece, and none was raised besides the line above.
- **usable-cores** stays open, at gate.sh:266 and :289. No site of it is in this piece.
- **release-entry-part** is carried, at hooks/poker/line.sh:1110 and payload/scripts/lib/line.sh:641. T22's edit to line.sh is one function far from line 641 (A-orch.38), and T12's entry used the verb without changing it.
- **class-vocabulary** stays carried. No site of it is in this piece.
- The run's three burns stand: close-criterion-eval by T15, reserve-rule and robust-pick by T17. Shown by `grep -c burned debt.md`: 4, one of them the header.

## What may be raised, and was not

- **over-engineering.** T22 adds no abstraction. Each copy is inline.
- **substitution.** The landing runner's result file, its 75 arm, `at=`, `promised=` and `_GATE_OWN` read as before (critic-adversarial-3.md, probe-runner.log cases B and C). The ask's exit codes reach each caller unchanged.
- **narrow-interface.** Neither caller gains a parameter. nv_drive's `NV_POLL` defaults to the old 0.1.
- **The two test oracles.** §HOLDER's (h1) and GR.3 each carry the same `times` parse, `gsub(",", "."); gsub(/[ms]/, " "); … $1 * 60 + $2 + $3 * 60 + $4`. These are two test oracles, and keeping them apart from `_gate_cpu` is their point. A shared tests/lib helper could hold them, but at two sites it is not worth a line.
