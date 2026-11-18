reviewed: 59350b5e6a5b16a42933825fab8148cee4465c48..68ef6f3350834e887d6cd212c975a114348aabfa
question: structure
result: flag
scope: whole
check: reuse FLAG _gate_cost_cores (gate.sh:476-486) re-implements _gate_seconds's sort, median and twice-the-median pick (gate.sh:510-533) in a second awk rather than sharing one; the share verb re-implements gate_reserve's acceptance rule (session-poker.sh:3479-3481 against gate.sh:266-269); compared also gate_reserve against gate_share (reused: the same file-read shape, one site each), _gate_faded against the two sums it replaced (one function, three readers), tick_hold_stands (one copy now for both stand-down reasons)
check: one-site FLAG the reserve rule is decided at two sites, both this wave, and they already differ on length (the verb refuses a value over nine characters, the reader takes it); the browser-and-compile set is enumerated at six sites, all this wave (booked.sh:309, gate.sh:1204, gate.sh:465, walls.sh:5709, walls.sh:5215, walls.sh:5755), and no test pins the gate's accepted set against the classifier's words for compile; the share's cores (_gate_share_cores, read by admission, the room, the width ask, gate_width, the verb and the tick) and the faded sum (_gate_faded at gate.sh:793, the room and the width ask) are one site each, pinned by §SHARE and §ROOM, both seen red (T1's and T2's red runs in their progress files)
findings: 0
debt: duplicate reserve-rule payload/scripts/lib/gate.sh:266, hooks/session-poker.sh:3479
debt: duplicate class-vocabulary payload/scripts/booked.sh:309, payload/scripts/lib/gate.sh:1204, payload/scripts/lib/gate.sh:465, payload/scripts/lib/walls.sh:5709
debt: unpinned-pair class-vocabulary payload/scripts/lib/cmd-class.sh:1143, payload/scripts/lib/gate.sh:1204
debt: duplicate robust-pick payload/scripts/lib/gate.sh:481, payload/scripts/lib/gate.sh:510

## What each line says

- **reserve-rule (both sites this wave).** What a reserve value may be: a non-negative decimal no larger than the cores, `''|.*|*.|*[!0-9.]*|*.*.*` and `v + 0 <= c`. `gate_reserve` decides it to fall back to 1, and the share verb decides it again to refuse with exit 2. A third shape added to one is missed by the other. They already disagree on length (`${#SH_RES} -le 9` at session-poker.sh:3480 has no twin in the reader), where only a hand-written file meets it, so FLAG and not FAIL. One predicate in gate.sh, which the verb calls, is the burn. This is A-T6.x's candidate, confirmed.
- **class-vocabulary (all sites this wave).** Which classes are heavy and take the free-room prior is decided at once in the shim's usage check, `gate_ask`'s check, `_gate_cores_for`'s prior arm, the wall's `_bsg_booked_class` and its key arm, and `classify_tier1`'s pass. The design's ownership table names cmd-class.sh as the class's one owner and these as rendering surfaces, but each of them decides membership rather than carrying a word. A third heavy tool, say `storybook build`, is six edits. The shim could forward `--class` and let `gate_ask`'s rc 2 refuse it, and the wall's three arms could read one predicate. This is the open-closed shape: one table would take the next case.
- **class-vocabulary as an unpinned pair.** The classifier's `webtool` words (cmd-class.sh:1143-1150) and the gate's accepted set (gate.sh:1204) must agree, or a wrapped command exits 2 at the shim. §B-CLASS (background-suite-guard) and §CLASS (booked) pin `browser` end to end, and T4's and T5's reds show those cases fail. Nothing drives `compile` from the classifier to a request, so a `compile` dropped from `gate_ask`'s case would stay green.
- **robust-pick (second site older than the reviewed range).** `_gate_cost_cores`'s inline insertion sort, median and `v[k] > 2 * m` walk is `_gate_seconds`'s `sortv`, `median` and pick, copied with a parallel text array so it prints the line's spelling. The spec's ownership table says the promise "reuses `_gate_seconds`'s robust rule"; it is reused by copy. No test asserts the two pick alike on one plant. One awk function both programs include, the way `$_GATE_FITS_AWK` is shared, is the burn.

## The consolidation act (REQ-7, D10)

Visible in the diff, both of them. T3 reworded the two `times` comments in tests/run.sh (run.sh:875-877 and 963-966) to name the fourth field, which the code now writes, so they are true again. T15 burned close-criterion-eval: `matrix_close_eval` (walls.sh:1824) is the one test of the close's criterion, and `mr_close_acs` (plan.sh:710) and the matrix render's `isclose` read it, where session-poker.sh's `taskof` had its own regex. debt.md records `burned T15`.

## AC-7.3

The criterion fails when this record raises a `debt:` line whose sites both landed in this wave. The reserve-rule and class-vocabulary lines do. Neither is a FAIL. The criterion is unproved as written, so it is the user's to rule.

## Comments naming run history

No added line of code under payload, hooks, tests/run.sh or tests/lib names a wave, task, criterion, decision or .bionic path. The command and its empty output are in critic-adversarial.md's attempts.
