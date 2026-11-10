reviewed: 68ef6f3350834e887d6cd212c975a114348aabfa..dd9b12e1883354b73b57fe21b859ef74349d55f2
question: structure
result: flag
scope: piece
check: reuse PASS each new site does a job nothing else does: gate_reserve_ok (gate.sh:262) replaces the verb's inline check and gate_reserve's own, and reuses _res_cores and _res_is_uint; _gate_cpu (gate.sh:1276) is the one `times` parse, called by gate_ask and gate_end (the only `split(x, a, "m")` in payload, hooks and tests/run.sh); _GATE_PICK_AWK (gate.sh:488) takes $_GATE_FITS_AWK's shape and is included by both cost readers (gate.sh:498, 524); _gate_cores_for keeps one awk for both arms, so the free room has one site (gate.sh:482, the only `int(l - b - f)`); compared against _gate_share_cores and gate_width (the line floored, another concept), and _R_cpu0 against the other _gate_read fields (one reader, one writer)
check: one-site FLAG the at-least-one-core fallback this piece wrote into gate_reserve_ok (gate.sh:266) is also computed in _gate_share_cores (gate.sh:289), older than the reviewed range (both copies are at 68ef6f335, gate.sh:268 and 280); the reserve rule, the pick, the free room and the processor-seconds parse are now one site each; the shared pairs the piece touches each name a test seen red: verb and reader of a reserve, SS.4 (w49-T17/red-sp2.log at 68ef6f335 and mutant-sp2.log on the shape-arm mutant); cpu0= writer and reader, CO.4 (w49-T17/red-gate.log); the measured promise and admission, CO.5 and CO.6 (same log); the faded sum and an unscanned reader, CO.5b (A-T20.2, w49-T20/red-head.log); the unknown busy at the room and at admission, RM.5 (w49-T20/red-mut.log)
findings: 0
debt: duplicate usable-cores payload/scripts/lib/gate.sh:266, payload/scripts/lib/gate.sh:289

## The burns, confirmed

- **reserve-rule, burned.** `gate_reserve_ok` (gate.sh:262-268) holds the shape, the nine-character cap and the bound. `gate_reserve` falls back to 1 on its refusal (gate.sh:277), and the share verb refuses with exit 2 on it (session-poker.sh:3478). No other reserve check remains in payload or hooks. SS.4 is the pair's test, and it went red on the head and on the mutant.
- **robust-pick, burned.** One text, `_GATE_PICK_AWK` (gate.sh:488-492), defines `sortv`, `median` and `pick`. Both `_gate_cost_cores` and `_gate_seconds` include it. No other copy of the twice-the-median walk exists (`grep -rnE 'function sortv|function median|2 \* m|2 \* med' payload hooks`: gate.sh:489-491 only). The shared text returns a number. `_gate_cost_cores` maps it back to its line's spelling, and `_gate_seconds` prints it as whole seconds.
- These are REQ-7's consolidation force at work: two duplicates raised by the whole read are paid by the row that touched their sites. debt.md marks both `burned T17`. class-vocabulary stays carried, and no site of it is in this piece.

## The debt line

- **usable-cores (older than the reviewed range).** "The cores this process may use, and 1 when that reading is not a whole number of at least 1" is written as one line at gate.sh:266 and again at gate.sh:289. This piece moved the first copy from `gate_reserve` into `gate_reserve_ok` without merging it with the second. A third form reads the same fact differently: `gate_end`'s cap guards `c + 0 >= 1` inside its awk (gate.sh:1332). One reader in resources.sh beside `_res_cores` is the burn. The copies agree today, so this is debt and not a FAIL.

## Against the design's ownership table

"A run's cost" names `gate_end` as its owner. The baseline is now written by `gate_ask` and read by `gate_end`, both through `_gate_cpu`, and CO.4 pins the pair. That is one concept with one parse, so it is not a second owner. The table could add `gate_ask`'s `cpu0=` to the row's reuses.

## What may be raised, and was not

- **substitution.** `_gate_cost_cores` now prints the first line in file order whose value equals the pick, where the copy printed the last in sort order (A-T17.6). Only two spellings of one value can differ, and both callers read it as a number or print it as the promise. `gate_reserve` reads a hand-written value of ten or more characters as 1, where it read the number (A-T17.4). Its callers read a reserve and never its length.
- **over-engineering.** Each new unit has two callers: `gate_reserve_ok`, `_gate_cpu` and `_GATE_PICK_AWK`. `_gate_cpu` sets a global rather than printing, because `times` inside `$( )` reads the subshell. Its comment says so.
- **Comments naming run history.** No added line names a wave, task, criterion, decision, finding or `.bionic` path. The command and its empty output are in critic-adversarial-2.md.
