reviewed: 837ddc39161b522a7071b996cf9d0d9121f1c61b..5a08f601b5aca8cdf332c0ca1581bcbcdf3ab851
question: structure
result: flag
scope: piece
check: reuse FLAG walk_registered spells its own sed reader of a proof line's kind and evidence= over $SECTION, where lib/proof.sh proof_awk is the declared one reading of a proof line and walls.sh _eg_reading_gaps already reads $SECTION through it
check: one-site FLAG the walk proof line has two surfaces, proof_line's writer and walk_registered's reader, and no test drives the writer's output through the gate; 26b feeds a hand-spelled line
findings: 0
debt: duplicate proof-line-reader payload/scripts/lib/walls.sh:4399, payload/scripts/lib/proof.sh:1433
debt: unpinned-pair walk-proof-line payload/scripts/lib/walls.sh:4399, payload/scripts/lib/proof.sh:95

# critic-structure-2 — wave-46-asks-nothing, the fix piece T29

Reader: w46-T30, at head 5a08f601b5aca8cdf332c0ca1581bcbcdf3ab851. The design for this wave has no ownership table naming a proof-line reader, so I searched the code.

## reuse

The change adds one function, `walk_registered` (`payload/scripts/lib/walls.sh:4394`). Its job is to read the plan section's proof lines, keep those of kind `walk`, and take each one's `evidence=` value.

- `payload/scripts/lib/proof.sh:1411-1418` declares `proof_awk` "THE ONE READING OF A PROOF LINE", and calls its `PROOF_EVIDENCE` "the one `evidence=` reader, where five programs each spelled their own".
- The same file T29 edited already reads `$SECTION` through it: `_eg_reading_gaps` runs `printf '%s\n' "$SECTION" | awk "$(proof_awk)" … proof_fields($0) && PROOF_KIND == "review"` and takes `PROOF_EVIDENCE` (`walls.sh:2558-2562`). That reuse needs no new read, so the wall freeze is no bar to it.
- T29's reuse line (A-T29.2, assumptions.md line 158) searched `'proved: '` and `'\^proved'` in walls.sh and found "No existing walls.sh reader parses proved lines out of $SECTION". `_eg_reading_gaps` is such a reader; it carries no `proved:` literal, because `proof_awk` holds it. The search missed it.
- The two readings differ today in what they accept: `proof_fields` demands a 7-to-40-hex `head=`, accepts fields in any order and tab separators, and maps old kind names; the sed expression demands `proved: kind=walk ` first, takes any head, and maps nothing. The one writer, `proof_line`, writes the shape both accept, so no user meets the difference. FLAG, debt of kind duplicate.

## one-site

The concept "this artifact is a registered walk" is decided in one place, `walk_registered`. The proof line it reads is a shared pair: `walk_register` writes it through `proof_line` (`hooks/poker/proof.sh:216`, `payload/scripts/lib/proof.sh:95`), and the gate parses it with its own expression (`walls.sh:4399`).

- 26b is the only row on the reading side, and its line is spelled by hand in the suite (`wg_line="proved: kind=walk head=$EG_HEAD at=… evidence=record/w"`, `tests/canonical-sdlc-evidence-gate.test.sh:255`). A change to `proof_line`'s field order or separator would leave 26b green while the real pairing breaks.
- T29's own census line says so: session-poker-4's WK rows "pin the line proof-add walk writes, not the gate's reading of it" (tests/CENSUS.md, the Section 26 line).
- No test has been seen to fail on a disagreement between the two surfaces. The real-plan run in this review (.bionic/tmp/scratch/00000000-0000-4000-8000-000000000003/w46-T30/realplan.log, `registered(as-is)=rc0`) observes them agreeing once, which is not a pin. FLAG, debt of kind unpinned-pair.
- The doctrine sentence and its render agree: `bash agents-src/render.sh --check` rc=0, and the steps/5.md hash matches the manifest.

Both debts are paid together if `walk_registered` reads through `proof_fields` and one row registers a walk with the line `proof_line` prints.
