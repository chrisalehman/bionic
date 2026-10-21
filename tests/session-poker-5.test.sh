#!/bin/bash
# Tests for hooks/session-poker.sh — shard 5: §CHECK, §DECISIONS, §ROUNDS, §EARLY-TICK, §ORDER, §QUIET-LANDING,
# §NOTREADY, §STEP.
#
# THE SUITE IS SHARDS (wave-30 T2; design-ledger Δ7, D8). Its governing design, its hermetic
# posture and its clock discipline are written once, in tests/session-poker.test.sh's header;
# the sandbox, the pins and the shared fixture builders are tests/session-poker.prelude.sh,
# sourced below after the framework and the POKER seam. This shard builds every fixture it reads.
#
# Usage: bash tests/session-poker-5.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/regression-fixture.sh"

# THE SEAM, exactly as tests/session-poker.test.sh offers it, for RED evidence against a
# mutated copy without ever touching the shipped file:
#   W2_POKER_UNDER_TEST=/tmp/mutant.sh bash tests/session-poker-5.test.sh
POKER="${W2_POKER_UNDER_TEST:-${BIONIC_HOOKS_DIR}/session-poker.sh}"

# THE FILES THIS SHARD'S HOISTED HELPERS READ, NAMED HERE (tests/lib/impact.sh maps a suite from
# its own lines and never follows it into the prelude).
S46_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/proof.sh"
S31_STOP_HOOK="${BIONIC_HOOKS_DIR}/stop.sh"
. "$(dirname "$0")/session-poker.prelude.sh"

# ============================================================
section "§CHECK: current <N> --check runs what current <N> runs before it writes, writes nothing, and exits as the advance would (wave-38 T1; REQ-1 AC-1.3; D20)"
# ============================================================
# There was no dry form of the step move: close-out's `check` was the only one, so an orchestrator
# learned whether `current 7` would be admitted by running it. `current <N> --check` (N in 5..8) runs
# the advance's own path up to and excluding the swap — the same dry commit through the real gate,
# the same `cur7_judge <N>` — prints `current <N> --check: would advance` or `… would refuse` above
# the refusal text, and writes nothing. The agreement is structural: one function both paths call.
# FIXTURE FIDELITY: §CUR7's world (session-poker-4): a real repository on `wave/01-fixture` with two
# suites and lib/x.sh, base B and a code commit C; a double wave plan the real gate admits at Steps 5
# through 7, bound to this session; every fact in the production writer's shape (`proof_line`,
# `proof_floor_line`). Every move is the real verb; each fixture is rebuilt before the advance runs.
# fails-when: the check and the advance disagree on a fixture; the check writes a byte anywhere in the
# repository; the check path loses the judge (the mutant below).
CK_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
CK_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib"
RCK="$(make_repo check)"
git -C "$RCK" config user.email t@example.com; git -C "$RCK" config user.name "Dana Fixture"
printf '.bionic\n' > "$RCK/.gitignore"
mkdir -p "$RCK/tests" "$RCK/lib" "$RCK/.bionic/docs/plans" "$RCK/.bionic/docs/record/w35"
# a.test.sh READS lib/x.sh (wave-39 T24; D5, AC-18.1): a commit past the floor owes the suites that read what it changed,
# so C, a change to lib/x.sh, is unproved until a.test.sh runs at it; a file no suite reads would owe nothing.
printf '#!/bin/bash\n[ -s "$(dirname "$0")/../lib/x.sh" ]\n' > "$RCK/tests/a.test.sh"; printf '#!/bin/bash\nexit 0\n' > "$RCK/tests/b.test.sh"
printf 'one\n' > "$RCK/lib/x.sh"
( cd "$RCK" && git add .gitignore tests lib && git commit -qm base && git checkout -q -b wave/01-fixture ) >/dev/null 2>&1
printf 'generic fixture proof\n' > "$RCK/.bionic/docs/record/generic-evidence.md"
CK_B="$(git -C "$RCK" rev-parse HEAD)"
CK_C="$(s57_commit "$RCK" lib/x.sh 'C: a code change after the floor')"
PCK="$RCK/.bionic/docs/plans/wave-x.plan.md"
ck_line() { bash -c '. "$1/proof.sh" && shift && proof_line "$@"' _ "$CK_LIB" "$@"; }
ck_floor() {  # <head> [<owed>] -> a floor proof at <head>, as proof-add floor writes it
  bash -c '. "$1/proof.sh" && proof_floor_line "$2" 2026-10-12T11:00:00Z record/w35/floor.log "${3:-}"' _ "$CK_LIB" "$1" "${2:-}"
}
ck_reads() {  # <head> [<adversarial result>] -> the five readings a double wave plan is dealt, at <head>; both adversarial ones take the result
  ck_line review "$1" 2026-10-12T12:00:00Z record/w35/evidence.md evidence w-read pass piece
  ck_line review "$1" 2026-10-12T12:00:00Z record/w35/adversarial.md adversarial w-read "${2:-pass}" piece
  ck_line review "$1" 2026-10-12T12:00:00Z record/w35/structure.md structure w-read pass piece
  ck_line review "$1" 2026-10-12T12:00:00Z record/w35/adversarial-whole.md adversarial w-read "${2:-pass}" whole
  ck_line review "$1" 2026-10-12T12:00:00Z record/w35/structure-whole.md structure w-read pass whole
}
ck_plan() {  # <current> <proof lines> [<sed edit>] -> PCK, bound to this session
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: double\nscale: wave\n'
    printf 'deploy_target: none\nuse_worktree: false\nhas_ui: false\nwalk: exempt\n---\n# plan\n\n## SDLC State\n\n'
    printf 'current: %s\nworking-branch: wave/01-fixture\napproved-by: fixture 2026-09-22T00:00Z approved\n' "$1"
    printf -- '- Step 4: dispatched, record/w35/dispatch.md\n  worktree: .\n  base-sha: %s\n  branch: wave/01-fixture\n' "$CK_B"
    printf -- '- Step 5: floor, record/w35/floor.log\n  auditor: CONFIRMED, record/w35/audit.md\n'
    printf -- '- Step 6: review at record/w35/review.md\n'
    printf -- '- Step 7: documented at record/w35/docs.md\n  n/a: no decision this run\n'
    printf '%s\n' "$2"
    printf '\n## Verification Matrix\n\nstack-health: n/a: no long-running serve\n\n'
    printf '| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |\n\n'
    printf 'AC-1:\n  fails-when: the planted defect this eval must go red on\n  evidence: record/generic-evidence.md\n'
    printf '  tier-run: bash tests/a.test.sh\n  readback: the line it wrote\n'
  } | sed -e "${3:-}" > "$PCK"
  bind_marker "$RCK" "$PCK"
}
ck_tree() {  # -> one cksum line per file in the fixture repository outside .git: what a write would change
  ( cd "$RCK" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do cksum "$f"; done )
}
ck_unpid() {  # [<text>] (else stdin) -> the text with each plan copy's process suffix (.current-dry.<pid>) read as <pid>
  if [ $# -gt 0 ]; then printf '%s\n' "$1" | ck_unpid; return; fi
  sed -E 's/\.(current(-dry)?)\.[0-9]+/.\1.<pid>/g'
}
CK_GOOD="$(ck_floor "$CK_C")
$(ck_reads "$CK_C")"

# ck_case <label> <N> <current> <want rc> <proof lines> [<drop pattern>] -> the check on a fresh fixture,
# then the advance on a fresh fixture of the same bytes; asserts both exit <want>, the check's first line,
# that the check wrote nothing (the plan by cmp, the whole tree by cksum), and that a refusal's text is the
# advance's own. Leaves CK_RC/CK_OUT (the check) and AD_RC/AD_OUT (the advance).
ck_case() {
  local label="$1" n="$2" cur="$3" want="$4" proofs="$5" drop="${6:-}" verdict
  ck_plan "$cur" "$proofs" "$drop"; cp "$PCK" "$TMPROOT/ck-before"; ck_tree > "$TMPROOT/ck-tree-before"
  poke "$RCK" current "$n" --check; CK_RC="$RC"; CK_OUT="$OUT"
  ck_tree > "$TMPROOT/ck-tree-after"; cp "$PCK" "$TMPROOT/ck-after"
  ck_plan "$cur" "$proofs" "$drop"
  expect_true "$label precondition: the advance's fixture is the check's, byte for byte (cmp)" cmp -s "$TMPROOT/ck-before" "$PCK"
  poke "$RCK" current "$n"; AD_RC="$RC"; AD_OUT="$OUT"
  expect_eq "$label — current $n --check and current $n exit alike, $want (check|advance)" "$want|$want" "$CK_RC|$AD_RC"
  [ "$CK_RC|$AD_RC" = "$want|$want" ] || printf '      the check said: %s\n      the advance said: %s\n' "$CK_OUT" "$AD_OUT"
  [ "$want" = 0 ] && verdict="would advance" || verdict="would refuse"
  expect_eq "$label — …the check's first line is its verdict" "poker: current $n --check: $verdict" "$(printf '%s\n' "$CK_OUT" | head -1)"
  expect_true "$label — …the check left the plan byte-identical (cmp)" cmp -s "$TMPROOT/ck-before" "$TMPROOT/ck-after"
  expect_true "$label — …and wrote no file anywhere in the repository (every file's cksum, before and after)" \
    cmp -s "$TMPROOT/ck-tree-before" "$TMPROOT/ck-tree-after"
  if [ "$want" = 0 ]; then
    expect_eq "$label — …the advance wrote current: $n (the fixture is one the advance takes)" "$n" "$(sed -n 's/^current: //p' "$PCK")"
  else
    expect_true "$label — …the advance left the plan byte-identical (cmp)" cmp -s "$TMPROOT/ck-before" "$PCK"
    expect_contains "$label — …the advance refused in words (REFUSED)" "REFUSED" "$AD_OUT"
    expect_eq "$label — …and the check's refusal text under its verdict is the advance's, line for line" \
      "$(ck_unpid "$AD_OUT")" "$(printf '%s\n' "$CK_OUT" | tail -n +2 | ck_unpid)"
  fi
}
expect_regex "CK-0 precondition: the working branch's head is C, a 40-hex commit" '^[0-9a-f]{40}$' "$CK_C"

# ---------- N=5: the dry commit at Step 5 admits it, or refuses a plan with no Step-5 line ----------
ck_case "CK-5g current 5 from 4, every line the gate asks for written" 5 4 0 "$CK_GOOD"
ck_case "CK-5r current 5 from 4, the plan carrying no Step-5 line" 5 4 1 "$CK_GOOD" '/^- Step 5: /d'
expect_contains "CK-5r-b …refused by the dry commit, in the gate's words" "has no 'Step 5:' line" "$CK_OUT"

# ---------- N=6: the dry commit at Step 6 admits it, or the gate refuses a question whose newest reading failed ----------
CK_FAILREAD="$(ck_floor "$CK_C")
$(ck_reads "$CK_C" fail)"
ck_case "CK-6g current 6 from 5, every line the gate asks for written" 6 5 0 "$CK_GOOD"
ck_case "CK-6r current 6 from 5, both adversarial readings failing" 6 5 1 "$CK_FAILREAD"

# ---------- N=7: the dry commit and the judge admit it, or the judge refuses a floor whose whole run left a suite red ----------
ck_case "CK-7g current 7 from 6, the floor and every reading at the head" 7 6 0 "$CK_GOOD"
ck_case "CK-7r current 7 from 6, a.test.sh owed by the floor's whole run" 7 6 1 "$(ck_floor "$CK_C" a.test.sh)
$(ck_reads "$CK_C")"
expect_contains "CK-7r-b …refused by the judge, naming the owed suite" "$(printf 'regression\towed\ta.test.sh')" "$CK_OUT"
CK_7R_PROOFS="$(ck_floor "$CK_C" a.test.sh)
$(ck_reads "$CK_C")"

# ---------- N=8: the judge holds, or it does not: the adversarial readings failing at the head ----------
ck_case "CK-8g current 8 from 7, every fact the run owes holding at the head" 8 7 0 "$CK_GOOD"
CK_8R_PROOFS="$CK_FAILREAD"
ck_case "CK-8r current 8 from 7, both adversarial readings failing at the head" 8 7 1 "$CK_8R_PROOFS"
# The judge's refusal settles the person's ledger (cur8_owed_waivers): the advance opens a waiver item in the
# repository's owed store. The check takes the same judgment and not that write; the tree row above saw no file
# change across the check, and this row proves the store is a file that row reads.
expect_contains "CK-8r-c …the advance opened the waiver item the judge owes, in the store the check's tree row covers" \
  "waive:adversarial" "$( ( cd "$RCK" && CLAUDE_CODE_SESSION_ID="$SID" bash -c '. "$1/owed.sh" && cat "$(owed_file)"' _ "${BIONIC_HOOKS_DIR}/../payload/scripts/lib" ) 2>/dev/null)"
ck_case "CK-8r2 current 8 from 7, the floor one commit behind the head" 8 7 1 "$(ck_floor "$CK_B")
$(ck_reads "$CK_C")"
expect_contains "CK-8r2-b …refused by the judge, naming the range no run proves" "${CK_B}..${CK_C}" "$CK_OUT"

# ---------- the flag's grammar: after the step, for 5..8 only ----------
ck_plan 6 "$CK_GOOD"; cp "$PCK" "$TMPROOT/ck-before"
poke "$RCK" current 4 --check
expect_eq "CK-u1 current 4 --check is a usage error (exit 2): the check is for steps 5 to 8" "2" "$RC"
expect_contains "CK-u1b …saying which steps it takes" "--check" "$OUT"
poke "$RCK" current 9 --check
expect_eq "CK-u2 current 9 --check is a usage error (exit 2)" "2" "$RC"
poke "$RCK" current 7 --chek
expect_eq "CK-u3 current 7 with any other second word is a usage error (exit 2)" "2" "$RC"
poke "$RCK" current --check 7
expect_eq "CK-u4 the flag before the step is a usage error (exit 2)" "2" "$RC"
expect_true "CK-u5 …and none of them touched the plan (cmp)" cmp -s "$TMPROOT/ck-before" "$PCK"
poke "$RCK" current 7 --check
expect_eq "CK-u6 …control: current 7 --check on that plan is admitted (exit 0)" "0" "$RC"

# ---------- the mutant: the judge dropped from the path --check takes ----------
# A doctored copy of the poker (hooks/ beside scripts/lib, the tree's own library linked in, so the copy's
# loader finds this tree's library) with every `cur7_judge <N>` call line replaced by one that only binds the head
# the judge would have set (`PV_HEAD8`, read by the advance's summary under `set -u`), so the judge is gone and
# nothing else is. It runs, and says "would advance" on the judge-refused fixture at Step 7, so the agreement row
# there goes red on it; at Step 8 the dry commit refuses failing readings before the judge is asked.
CK_MUT="$TMPROOT/ck-mutant"; mkdir -p "$CK_MUT/hooks" "$CK_MUT/scripts"
ln -s "$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)" "$CK_MUT/scripts/lib"
for ck_sib in "$(dirname "$POKER")"/*; do
  [ "$(basename "$ck_sib")" = session-poker.sh ] && continue
  [ "$(basename "$ck_sib")" = poker ] && continue
  ln -s "$ck_sib" "$CK_MUT/hooks/$(basename "$ck_sib")"
done
# The two calls are in the judge, the part beside the dispatcher that holds the current verb; the copy carries its own
# poker/ so the doctored judge is the one the copied dispatcher loads.
cp "$POKER" "$CK_MUT/hooks/session-poker.sh"; cp -R "$(dirname "$POKER")/poker" "$CK_MUT/hooks/poker"
CK_JUDGE="$(dirname "$POKER")/poker/judge.sh"
awk '/^[[:space:]]*cur7_judge [0-9]+[[:space:]]*$/ { sub(/cur7_judge [0-9]+/, ": \"${PV_HEAD8:=}\""); n++ } { print } END { print n + 0 > "/dev/stderr" }' \
  "$CK_JUDGE" > "$CK_MUT/hooks/poker/judge.sh" 2> "$TMPROOT/ck-mutant.n"
expect_eq "CK-mut0 the mutant replaces the judge's two call lines, parses, and differs from the judge" "2 0 differs" \
  "$(cat "$TMPROOT/ck-mutant.n") $(bash -n "$CK_MUT/hooks/poker/judge.sh" >/dev/null 2>&1; echo "$?") $(cmp -s "$CK_MUT/hooks/poker/judge.sh" "$CK_JUDGE" && echo same || echo differs)"
CK_REAL_POKER="$POKER"
ck_plan 6 "$CK_GOOD"
POKER="$CK_MUT/hooks/session-poker.sh"; poke "$RCK" current 7 --check; POKER="$CK_REAL_POKER"
[ "$RC" = 0 ] || printf '      the mutant said: %s\n' "$OUT"
expect_eq "CK-mut1 the mutant runs: current 7 --check on the good fixture still says would advance (exit 0)" \
  "0|poker: current 7 --check: would advance" "$RC|$(printf '%s\n' "$OUT" | head -1)"
ck_plan 6 "$CK_7R_PROOFS"
POKER="$CK_MUT/hooks/session-poker.sh"; poke "$RCK" current 7 --check; POKER="$CK_REAL_POKER"
CK_M7="$RC|$(printf '%s\n' "$OUT" | head -1)"
poke "$RCK" current 7; CK_A7="$RC"
expect_eq "CK-mut2 the mutant flips CK-7r: its check says would advance (exit 0) where the real advance refuses (exit 1)" \
  "0|poker: current 7 --check: would advance|1" "$CK_M7|$CK_A7"
POKE_BOUND="$CK_BOUND_WAS"

# ============================================================
section "§DECISIONS: decisions [--all] reads the design ledgers' register entries; the recap prints this run's settled set; doctrine re-puts a settled decision only as reopening D<n> (wave-38 T13; REQ-3 AC-3.4; D24)"
# =====================================================# Every ruling is a `## Δn — Dn ruled "<reply>" (<who> <date>): <title>` heading in record/<wave>/design-ledger.md, or
# a `- Dn ruled …` bullet under a Δ (the Step-1 rulings folded in, as this wave's Δ21 holds them); `re-ruled` and
# `withdrawn` are register entries too. `decisions` lists this run's, `D<n> · "<reply>" · <who> <date> · <title>`, in
# the ledger's order; `--all` lists every record/*/design-ledger.md under the docs root, each line keyed by its wave,
# waves in slug order, a ledger with no entry in the grammar named once, and every ADR keyed by its frontmatter wave.
# The resume recap's settled: lines come from the same parser (handoff-file §RESUME RS6). FIXTURE FIDELITY: a real
# repository, §CHECK's plan shape bound to this session; ledgers in the grammar this wave's own ledger is written in,
# with the lines a register must not read (a heading with no ruling, a body line, a fenced example).
# fails-when: a ruled decision is absent from the list or the recap; a non-entry is listed.
RDC="$(make_repo decisions)"
PDC="$(s34_plan "$RDC" 4)"
DC_DOCS="$RDC/.bionic/docs"
mkdir -p "$DC_DOCS/record/wave-01-fixture" "$DC_DOCS/record/wave-00-earlier" "$DC_DOCS/record/wave-02-old" "$DC_DOCS/adrs/epic-99-fixture"
cat > "$DC_DOCS/record/wave-01-fixture/design-ledger.md" <<'LEDGER'
# design ledger — wave-01-fixture

## Frame — the question, not a ruling

## Δ0 — D1 ruled "1" (Dana Fixture 2026-10-05): the frame holds

A body line that names D9 ruled "9" (Nobody 2026-01-01): not a heading, never an entry.

## Δ1 — D2 ruled "Option 2" (Dana Fixture 2026-10-06, typed "D2: 2"): one door

## Δ2 — D2 re-ruled "Option 3, first" (Dana Fixture 2026-10-07, "ok, let's try it")

## Δ3 — tactical defaults set by Dana Fixture 2026-10-07

## Δ4 — Step-1 rulings folded in (orchestrator, 2026-10-07)

- D3 ruled "1" (Dana Fixture 2026-10-04): three folded in
- D4 withdrawn (Dana Fixture 2026-10-04): the old shape

```text
## Δ9 — D9 ruled "x" (Fake Person 2026-01-01): inside a fence
```
LEDGER
cat > "$DC_DOCS/record/wave-00-earlier/design-ledger.md" <<'LEDGER'
# design ledger — wave-00-earlier

## Δ0 — D1 ruled "2" (Dana Fixture 2026-09-01): the earlier frame
LEDGER
printf '# design ledger — wave-02-old\n\n## D1 — What Step 0 approves (Dana: "Approved!")\n' > "$DC_DOCS/record/wave-02-old/design-ledger.md"
printf -- '---\nwave: wave-01-fixture\nstatus: Accepted (Step 7, 2026-10-08)\n---\n\n# ADR-001 — One door to resume\n' \
  > "$DC_DOCS/adrs/epic-99-fixture/adr-001-one-door.md"
DC_WANT='D1 · "1" · Dana Fixture 2026-10-05 · the frame holds
D2 · "Option 2" · Dana Fixture 2026-10-06 · one door
D2 · re-ruled "Option 3, first" · Dana Fixture 2026-10-07 · (untitled)
D3 · "1" · Dana Fixture 2026-10-04 · three folded in
D4 · withdrawn · Dana Fixture 2026-10-04 · the old shape'
poke "$RDC" decisions
expect_eq "DC-1 decisions exits 0 on the bound run" "0" "$RC"
expect_absent "DC-1c …never a body line, a heading with no ruling, or a fenced example (DC-1b read the same output)" "D9" "$OUT"
poke "$RDC" decisions --all
expect_eq "DC-2 decisions --all exits 0" "0" "$RC"
poke "$RDC" decisions --each
expect_eq "DC-3 an unknown flag is the usage error" "2" "$RC"
mv "$DC_DOCS/record/wave-01-fixture/design-ledger.md" "$TMPROOT/dc-ledger"
poke "$RDC" decisions
expect_eq "DC-4 an absent ledger is exit 1" "1" "$RC"
expect_contains "DC-4b …in one line naming the path" "record/wave-01-fixture/design-ledger.md" "$OUT"
expect_eq "DC-4c …one line" "1" "$(printf '%s\n' "$OUT" | grep -c .)"
mv "$TMPROOT/dc-ledger" "$DC_DOCS/record/wave-01-fixture/design-ledger.md"
# The doctrine: a proposal that re-puts a settled decision opens with its number and the new evidence.
DC_SKILL="${BIONIC_SKILLS_DIR}/decision/SKILL.md"

# ---- wave-39 T11 (REQ-7; D15, D24; AC-7.1, AC-7.2): the decision line grammar, over wave 38's own ledger ----
# D15: `D<n> [qualifier] <verb> ["<reply>"] (<who> <date>)[: <title>]`, the seven verbs ruled, re-ruled, amended,
# amended again, ratified, final and withdrawn, and the heading form `D<n> ruled: <title> (<who> <date>)`. A
# `put (…)` proposal is never an entry. FIXTURE FIDELITY: the ledger below is wave 38's design ledger from the
# heading of its Δ23 to the end of its Δ24, byte for byte (D30's three lines, D31's five and its put line), under
# the slug the bound plan names, so `decisions`, `decisions --all` and the resume recap read it as they read the
# real one. fails-when: a line of D30 or D31 is absent or listed twice, out of the ledger's order, or the put line
# has an entry.
RD6="$(make_repo decisions-w38)"
PD6="$(s34_plan "$RD6" 4)"
D6_DOCS="$RD6/.bionic/docs"
mkdir -p "$D6_DOCS/record/wave-01-fixture"
cat > "$D6_DOCS/record/wave-01-fixture/design-ledger.md" <<'LEDGER'
# design ledger — wave-01-fixture (wave 38's Δ23 and Δ24, verbatim)

## Δ23 — D28, D29 and D30 ruled (Chris Lehman 2026-10-17)

- D28 ruled "option 3" (Chris Lehman 2026-10-17 8:35 AM, recorded from the handoff): gathered landing; fourteen landed-by-hand marks accepted on the scorecard.
- D29 ruled "1" (Chris Lehman 2026-10-17 3:52 PM): the indicator thresholds print once, in one line under the three Assessment lines, never on the lines themselves.
- D30 ruled "No, I think the icon should be left-justified, as with the Situation section. However, make them more nuanced, not so loud. Perhaps a check mark is equivalent to green, some kind of neutral and bad icon..." (Chris Lehman 2026-10-17 3:52 PM): the mark opens the line, as Situation's does; the set is ✅ fine · ➖ watch · ⚫ off, ⚪ unverified unchanged (the orchestrator's choice of glyphs, reversible). The one-line form on the tick and the handoff head carries the same three marks. Fix row T35.
- D30 amended "Maybe not a red X?" (Chris Lehman 2026-10-17 5:40 PM): the off mark is ✖ (U+2716, text style, never the red ❌ emoji); the set is ✅ fine · ➖ watch · ⚫ off, ⚪ unverified unchanged.
- D30 amended again "Green, grey, something else that's more calm, in keeping with that theme." (Chris Lehman 2026-10-17 5:42 PM): the off mark is ⚫ (black circle), pairing with ⚪ unverified; the set is ✅ fine · ➖ watch · ⚫ off. No cross, no red.

## Δ24 — D31 ruled: an Assessment mark encodes deviation from a tolerance (Chris Lehman 2026-10-17)

- D31 put (orchestrator, 5:55 PM): the Assessment marks borrowed Situation's state vocabulary (✅ landed = ✅ within), one glyph with two meanings on one page. The user: "Shouldn't the iconography communicate something more fundamental … Reason from first principles re: the information architecture of /sitrep." Ruled "Neither. I like option 2, except I don't like the icons. Something more noticable, like ✅. But it has to be elegant, and following the conceptual tolerance model": the four states are within the bar, near it, over it, not measurable.
- D31 glyphs ruled "✅ for within the bar" (Chris Lehman 2026-10-17 6:02 PM), the rest from the diamond gauge: ✅ within · 🔸 near · 🔶 over · ◇ not measurable. Noticeability grows with the deviation. The marks of Situation (✅ 🔄 ⬜ ⛔) encode work state; ✅ is shared by the user's choice. D29 stands: the thresholds print once, under the three lines, headed within/near/over. D30's ✅ ➖ ⚫ set is superseded.
- D31 glyphs re-ruled "do the arrow up for over" (Chris Lehman 2026-10-17 6:20 PM), after "✅ ➖ ⚫ is still better, except the circle doesn't work. Horizontal line is 'near it' … question mark for not measurable … more bold, stylized in a cool, calm way" and "not yellow": the final set is ✅ within the bar · ➖ near it · 🔼 over it · ❔ not measurable. One register, grey and white but the check's green; ➖ is the bar and 🔼 the measurement above it. The diamond gauge (🔹 🔸 🔶 ◇), ⚫, 👎 and the arrow triple were considered and dropped.
- D31 glyphs final "Changed my mind. That's too confusing. Let's go back to an X shape. But let's make it grey X like the horizontal bar." (Chris Lehman 2026-10-17 6:24 PM): ✅ within the bar · ➖ near it · ✖️ over it (U+2716 U+FE0F, the heavy grey X; no grey-boxed X exists in the emoji set) · ❔ not measurable. 🔼 dropped.
- D31 ratified "Yes" (Chris Lehman 2026-10-17 6:41 PM) on the presented table: ✅ within the bar · ➖ near it · ✖️ over it · ❔ not measurable; the mark leads the line; the thresholds print once under the block, headed within / near / over. The glyph colours are the emoji font's and cannot be tinted on the page's path; recorded as a known limit of the choice.
LEDGER
# d6_pick: the register's output -> the id, the first 48 bytes of the verb-and-reply field, and the who-and-date field
# of each D30 and D31 line, in the order printed (any `<wave> ` key and any `settled: ` prefix stripped first).
d6_pick() { sed -e 's/^wave-01-fixture //' -e 's/^settled: //' | awk -F' · ' '$1 ~ /^D3[01]$/ { print $1 " | " substr($2, 1, 48) " | " $3 }'; }
D6_WANT='D30 | "No, I think the icon should be left-justified,  | Chris Lehman 2026-10-17
D30 | amended "Maybe not a red X?" | Chris Lehman 2026-10-17
D30 | amended again "Green, grey, something else that'"'"' | Chris Lehman 2026-10-17
D31 | ruled | Chris Lehman 2026-10-17
D31 | glyphs ruled "✅ for within the bar" | Chris Lehman 2026-10-17
D31 | glyphs re-ruled "do the arrow up for over" | Chris Lehman 2026-10-17
D31 | glyphs final "Changed my mind. That'"'"'s too confus | Chris Lehman 2026-10-17
D31 | ratified "Yes" | Chris Lehman 2026-10-17'
poke "$RD6" decisions
expect_eq "DG-1 precondition: decisions exits 0 on the bound run" "0" "$RC"
D6_OUT="$OUT"
expect_nonempty "DG-1b precondition: …and prints something, so the counts below read a real list" "$D6_OUT"
expect_eq "DG-2b …and those are the only entries (D28 and D29 are bullets of the same Δ, the Δ23 heading names three numbers and is none: 3 + 5 + 2)" \
  "10" "$(printf '%s\n' "$D6_OUT" | grep -c .)"
expect_absent "DG-3 AC-7.2 the put line has no entry (DG-2 read the same output): its words are in no line" "5:55 PM" "$D6_OUT"
expect_eq "DG-3b …and no line is the put line's: no entry whose verb is put" "0" "$(printf '%s\n' "$D6_OUT" | grep -c ' put')"
poke "$RD6" decisions --all
expect_eq "DG-4 decisions --all exits 0" "0" "$RC"
# The resume recap's settled: lines are this parser's output too, and handoff-file §RESUME reads them there.

# ============================================================
section "§ROUNDS: decisions put writes a put line to the run's ledger and its ruling closes it, so the sitrep's decisions line counts rounds; each put prints what an hour's wait moves, from the tasks that read it and the longest chain"
# ============================================================
# A put opens a round and the next ruling of the same number closes it; a ruling with no put open is a round of its
# own, the shape of a ledger written before puts. The wait line reads the tasks whose reads cell names the decision
# as an approval and whether any is on the longest open chain. FIXTURE FIDELITY: a real repository, §DECISIONS's
# plan shape with a reads column, the ruling headings in the register's grammar written as the person's word is.
# fails-when: a re-put is uncounted; the wait line is absent, or reads the same whether its task is on the chain.
RW="$(make_repo rounds)"; PW="$(s34_plan "$RW" 4)"
RW_L="$RW/.bionic/docs/record/wave-01-fixture/design-ledger.md"; mkdir -p "${RW_L%/*}"
rw_table() {  # <the side task's size> -> the task table: a side task reads one decision; the last reads another and the long one's file
  awk -v s="$1" '/^## Tasks/ { print; print ""; print "| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |"
    print "|---|---|---|---|---|---|---|---|---|---|---|---|---|"
    print "| T1 | 4 | build | the first | implementor | — | 30 | REQ-1 | a.sh | — | — | landed | approval:plan |"
    print "| T2 | 4 | build | the side | implementor | — | " s " | REQ-1 | b.sh | — | — | pending | approval:plan, approval:D7 |"
    print "| T3 | 4 | build | the long | implementor | — | 200 | REQ-1 | c.sh | — | — | pending | approval:plan |"
    print "| T4 | 4 | build | the last | implementor | — | 100 | REQ-1 | d.sh | — | — | pending | approval:plan, c.sh, approval:D8 |"
    print ""; skip = 1; next } skip && /^## / { skip = 0 } !skip' "$PW" > "$PW.t" && mv "$PW.t" "$PW"
}
rw_table 30
printf '# design ledger\n\n## Δ0 — D1 ruled "1" (Dana Fixture 2026-10-05): the frame holds\n' > "$RW_L"
rw_rule() { printf '\n## Δ%s — D3 %s (Dana Fixture 2026-10-06): the third\n' "$1" "$2" >> "$RW_L"; }  # the person's word, as recorded
rw_line() { poke "$RW" sitrep; printf '%s\n' "$OUT" | grep ' decisions — '; }
poke "$RW" decisions put D3 'the third'
expect_eq "RD-1 decisions put exits 0 on the bound run" "0" "$RC"
expect_eq "RD-1b …and writes one put line for it to the run's ledger" "1" "$(grep -c '^## Δ[0-9]* — D3 put (' "$RW_L")"
rw_rule 50 'ruled "1"'; poke "$RW" decisions put D3 'the third, again'; rw_rule 51 'amended "2"'
RD_TWO="$(rw_line)"
poke "$RW" decisions put D3 'the third, once more'; rw_rule 52 'amended "3"'; poke "$RW" decisions put D2 'the second'
expect_contains "RD-2 two puts, each ruled, read as two rounds" "D3 two" "$RD_TWO"
poke "$RW" decisions
expect_contains "RD-4 the register still lists the rulings" 'D3 · amended "3"' "$OUT"
expect_absent "RD-4b …and no put (RD-4 read the same output)" " put" "$OUT"
poke "$RW" decisions put 7 'no number'
expect_eq "RD-5 a put that names no D<n> is refused, the ledger unchanged" "1|4" "$RC|$(grep -c ' put (' "$RW_L")"
poke "$RW" decisions put D8 'on the chain'; RW_ON="$(printf '%s\n' "$OUT" | grep '^wait: ')"
poke "$RW" decisions put D7 'off the chain'; RW_OFF="$(printf '%s\n' "$OUT" | grep '^wait: ')"
poke "$RW" decisions put D9 'read by none'; RW_NONE="$(printf '%s\n' "$OUT" | grep '^wait: ')"
expect_contains "WT-1b …and names that task" "T4" "$RW_ON"
expect_contains "WT-3 no task reads it: nothing moves" "nothing moves" "$RW_NONE"
expect_true "WT-4 the put line in the ledger carries its wait line (WT-1 read it non-empty)" \
  bash -c '[ -n "$1" ] && grep -qF "$1" "$2"' _ "${RW_ON#wait: }" "$RW_L"
rw_table 500; poke "$RW" decisions put D7 'off the chain, now on it'; RW_FLIP="$(printf '%s\n' "$OUT" | grep '^wait: ')"
rw_close() { case "$1" in *'the predicted close moves'*) echo moves ;; *'the predicted close holds'*) echo holds ;; *) echo none ;; esac; }
expect_eq "WT-2 AC-14.1 the line reads the chain: D8's task on it moves the close, D7's off it holds the close, and D7 once its task is the longest moves it" \
  "moves|holds|moves" "$(rw_close "$RW_ON")|$(rw_close "$RW_OFF")|$(rw_close "$RW_FLIP")"

# ============================================================
section "§EARLY-TICK: the tick says CARD-EARLY as advice beside its WAIT lines while an integrate row is open (wave-38 T3; REQ-1 AC-1.2; D20)"
# ============================================================
# The final card refuses to render while a reader is open, a reading is unregistered at the head, or the advance to
# 6, 7 or 8 checks red (payload/scripts/card.sh `early`, the one owner of the three facts). The tick asks the same
# function whenever the plan carries an open integrate row and prints its line as advice, `poker: CARD-EARLY —
# <reason>`, beside the WAIT lines; it refuses nothing and writes nothing for it.
# FIXTURE FIDELITY: §CHECK's world and plan at current: 8, with a reads table after the matrix: T1 landed, the
# integrate row T3 pending on the two approvals and head. The red fact is the Step-7 line naming no adr, rca or n/a,
# a refusal no default of the card settles, so `current 7 --check` refuses while `current 6 --check` holds.
# fails-when: the tick stays silent while a fact fails; it says CARD-EARLY on a settled run, or with no open
# integrate row; its line is not the card's own.
ET_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
et_plan() {  # <proof lines> <integrate status> [<sed edit>] -> PCK at current: 8 with a reads table, bound to this session
  ck_plan 8 "$1" "${3:-}"; new_roster "$RCK"
  { printf '\n## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T1 | 4 | build | the x writer | implementor | — | 30 | REQ-1 | lib/x.sh | — | — | landed | approval:plan |\n'
    printf '| T3 | 8 | integrate | merge into main | orchestrator | — | 10 | REQ-1 | — | — | — | %s | approval:release, approval:merge, head |\n' "$2"
  } >> "$PCK"
}
ET_CARD="${BIONIC_HOOKS_DIR}/../payload/scripts/card.sh"
et_plan "$CK_GOOD" pending '/n\/a: no decision/d'
ET_EARLY="$( ( cd "$RCK" && env CLAUDE_CODE_SESSION_ID="$SID" bash "$ET_CARD" early "$PCK" ) 2>&1 )"
expect_eq "ET-0 precondition: card.sh early names the red check on this plan" "CARD-EARLY — current 7 --check: would refuse" "$ET_EARLY"
forget_digest "$RCK"
poke "$RCK" tick
expect_contains "ET-1 the tick says the card's line as advice, an integrate row open and current 7 --check red" \
  "poker: CARD-EARLY — current 7 --check: would refuse" "$OUT"
expect_contains "ET-1b …beside the integrate row's WAIT line" "poker: WAIT T3" "$OUT"
expect_eq "ET-1c …once" "1" "$(printf '%s\n' "$OUT" | /usr/bin/grep -c 'CARD-EARLY')"
et_plan "$CK_GOOD" pending
forget_digest "$RCK"
poke "$RCK" tick
expect_contains "ET-2 on a settled run the tick still says the integrate row's WAIT line" "poker: WAIT T3" "$OUT"
expect_absent "ET-2b …and no CARD-EARLY" "CARD-EARLY" "$OUT"
et_plan "$CK_GOOD" landed '/n\/a: no decision/d'
forget_digest "$RCK"
poke "$RCK" tick
expect_contains "ET-3 with no open integrate row the tick still answers" "poker:" "$OUT"
expect_absent "ET-3b …and says no CARD-EARLY, the red check notwithstanding" "CARD-EARLY" "$OUT"
POKE_BOUND="$ET_BOUND_WAS"

# ============================================================
section "§ORDER: the tick orders dispatch — FILL offers the longest remaining chain first, the gate line prints the width the gate answers each open landing, and SPLIT is a decision line only while width idles (wave-38 T7; REQ-6 AC-6.5; D22)"
# ============================================================
# D22: "the tick offers ready rows longest remaining chain first, and offers a `task-split` as a decision with its
# reason when width idles"; the gate answers width to the oldest active landing and 0 to the younger ones. A row's
# remaining chain is its size plus the heaviest path of open rows waiting on it, transitively (the `f` of
# lib/units.sh `units_chain`, which the CHAIN line prints for the whole graph); ties go by row id. The ready set's
# membership is unchanged: only its order, and so which rows the writer gap's trim keeps.
# FIXTURE FIDELITY: §47's reads table (s47_plan): two chains, T1 (10) → T2 (10) = 20 and T3 (30) → T4 (40) → T5 (50)
# = 120, and T6 (20) alone, tying T1 at 20. Table order offers T1 first; chain order offers T3. The leases are
# opened by the gate's own writer (`gate_landing_open`), carried by this test's live process, at planted ages.
# fails-when: FILL names T1 ahead of T3; the writer gap of one keeps T1; the gate line names no widths, names a
# younger landing ahead of an older, or answers a younger landing more than 0; SPLIT? stays on the CHAIN line, or the
# SPLIT line prints while the fill is full.
OR_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib"
ROR="$(make_repo order)"; new_roster "$ROR"
or_plan() {  # <writers> -> the fixture plan, bound by s47_plan's approval line
  s47_plan "$ROR" "$1" \
    "| T1 | 4 | build | the short chain's head | implementor | — | 10 | REQ-x | payload/a.sh | pending | |" \
    "| T2 | 4 | build | the short chain's tail | implementor | — | 10 | REQ-x | payload/a2.sh | pending | payload/a.sh |" \
    "| T3 | 4 | build | the long chain's head | implementor | — | 30 | REQ-x | payload/b.sh | pending | |" \
    "| T4 | 4 | build | the long chain's middle | implementor | — | 40 | REQ-x | payload/c.sh | pending | payload/b.sh |" \
    "| T5 | 4 | build | the long chain's tail | implementor | — | 50 | REQ-x | payload/d.sh | pending | payload/c.sh |" \
    "| T6 | 4 | build | alone, tying T1's chain | implementor | — | 20 | REQ-x | payload/e.sh | pending | |" >/dev/null
}
or_gate() { s47_lines gate | sed -n 's/^.* widths: //p'; }   # -> the gate line's widths field
or_fill() { printf '%s\n' "$OUT" | /usr/bin/grep -m1 '^poker: FILL T'; }   # -> the FILL line, never its "FILL —" sentence
or_lease() {  # <landing key> <first>:<seq> -> a lease the gate's writer opens, carried by this test's process
  bash -c '. "$1/gate.sh" && gate_landing_open "$2" "$3" 3600 "$4"' _ "$OR_LIB" "$1" "$$" "$2" >/dev/null
}
or_ask() { bash -c '. "$1/gate.sh" && gate_width_ask "$2"' _ "$OR_LIB" "$1"; }   # <landing key> -> the gate's answer

# ---------- the FILL order: the longest remaining chain first, ties by id ----------
or_plan 8
poke_pressure "$ROR" 8192 1.0 tick
expect_eq "OR-0 the tick over the two-chain table exits 0" "0" "$RC"
expect_nonempty "OR-0b precondition: the extractor reads the FILL line" "$(or_fill)"
expect_eq "OR-1 AC-6.5 FILL names the longest-chain row first: T3 (120 min), then T1 and T6 (20 each, by id), where table order is T1 T3 T6" \
  "poker: FILL T3 T1 T6" "$(or_fill)"
expect_eq "OR-2 the CHAIN line is the long chain by hand, 30 + 40 + 50, and carries no SPLIT? (it moved to its own decision line)" \
  "poker: CHAIN T3→T4→T5 (120 min)" "$(s47_lines CHAIN)"

# ---------- the trim keeps the longest chain: a gap of one offers T3, and nothing idles ----------
or_plan 1
poke_pressure "$ROR" 8192 1.0 tick
expect_eq "OR-4 AC-6.5 a writer gap of one (cap 1) offers T3, never table-first T1" "poker: FILL T3" "$(or_fill)"
expect_absent "OR-5 …and the fill is full, so no SPLIT decision is printed (OR-4 read this same output)" "poker: SPLIT " "$OUT"
expect_eq "OR-5b …and the CHAIN line is the same chain, no SPLIT? on it" "poker: CHAIN T3→T4→T5 (120 min)" "$(s47_lines CHAIN)"

# ---------- the gate line: the width the gate answers each open landing, oldest first ----------
rm -rf "$BIONIC_GATE_DIR/leases"
or_plan 8
poke_pressure "$ROR" 8192 1.0 tick
expect_nonempty "OR-6 precondition: the gate line is printed" "$(s47_lines gate)"
expect_eq "OR-6b no lease open: the gate line ends widths: none" "none" "$(or_gate)"
# Three leases, opened in name order with their ages reversed, so file order is not age order: LC is the oldest.
or_lease or:w01:LA 1020:3; or_lease or:w01:LB 1010:2; or_lease or:w01:LC 1000:1
# The widths are a gate reading, as the load is: they move no digest, so each tick below forgets it to print in full.
expect_eq "OR-7 precondition: the gate's writer opened three lease files" "3" "$(ls "$BIONIC_GATE_DIR/leases/" | /usr/bin/grep -c '\.lease$' | tr -d ' ')"
OR_N="$(or_ask or:w01:LC)"
expect_eq "OR-7b precondition: the gate answers the oldest, LC, 3 by hand (8 cores at share 80 is 6.4; a load of 1.0 and 1.61 a run: 2.61, 3.22 and 4.83 fit, 6.44 does not) and the younger LB 0" \
  "3|0" "$OR_N|$(or_ask or:w01:LB)"
forget_digest "$ROR"; poke_pressure "$ROR" 8192 1.0 tick
expect_eq "OR-8 AC-6.5 the gate line prints each open landing in age order with the gate's answer: the oldest its width, the others 0" \
  "or:w01:LC=3,or:w01:LB=0,or:w01:LA=0" "$(or_gate)"
expect_regex "OR-8b …on the one gate line, after room=" '^poker: gate share=.* room=(yes|no) widths: or:w01:LC=3,' "$(s47_lines gate)"
# A gate read under a tab IFS (bash runs a here-string's command substitution under a builtin's temporary IFS)
# compares each carrier's start as any other read does, so the three leases stay held and LC keeps its width.
OR_TAB="$( . "$OR_LIB/gate.sh" && IFS='	' read -r w <<< "$(gate_width_ask or:w01:LC)" && printf '%s' "$w" )"
expect_eq "OR-8c a gate read under a tab IFS answers LC its width and keeps all three leases" \
  "3|3" "$OR_TAB|$(ls "$BIONIC_GATE_DIR/leases/" | /usr/bin/grep -c '\.lease$' | tr -d ' ')"
# LC's carrier leaves it WAITING: the lease is kept but orders no one, so LB is the oldest the gate answers.
bash -c '. "$1/gate.sh" && gate_landing_leave "$2" "$3"' _ "$OR_LIB" or:w01:LC "$$"
forget_digest "$ROR"; poke_pressure "$ROR" 8192 1.0 tick
expect_eq "OR-9 a lease left WAITING drops off the line, and the next oldest, LB, is answered its width" \
  "or:w01:LB=3,or:w01:LA=0" "$(or_gate)"
rm -rf "$BIONIC_GATE_DIR/leases"

# ============================================================
section "§QUIET-LANDING: the quiet check reads the row's live landing carrier and the gate's open request for its agent before the mtimes (wave-39 T22; REQ-16 AC-16.1; D21)"
# ============================================================
# A writer blocked in a foreground `ready --within 1790` touches neither its progress file nor its transcript
# for up to 30 minutes, so the tick's two NOTIFY arms (past the declared duration; quieter than the cadence)
# named a working row every tick (three nights of it). Both arms now ask first whether the row's landing carrier
# lives (an entry of lib/line.sh's fold, present while the `carrier=` pid of its `ev=ready` lives, whose name is
# the row's) or whether the gate holds an open request for the row's agent; either makes the row ACTIVE, never
# NOTIFY. Only then the mtimes. A row with no carrier, no request and nothing written past its cadence is quiet,
# and a dead silent row still NOTIFYs.
# FIXTURE FIDELITY: a real repository with a wave plan the tick reads, the roster row in the writer's shape (name,
# progress and cadence), the carrier a sleeping process whose pid and start time the record's `ev=ready` names as
# lib/line.sh writes them (`line_event`, `_line_me`), the request one the gate's own `gate_ask` files and whose
# holder stays alive. The progress file is older than the row's cadence in every case.
# fails-when: a row with a live carrier or an open request NOTIFYs; a dead silent row does not; a carrier or a
# request of ANOTHER agent masks this row.
QL_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib"
QL_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
QL_PIDS=""
RQL="$(make_repo quiet-landing)"; new_roster "$RQL"
QL_PLAN="$(wave_plan_at "$RQL" 'epic-99-fixture/wave-01-fixture.plan.md' "-" \
  "| T1 | 4 | build | the writer's row | implementor | — | 60 | REQ-x | a.sh | active |")"
QL_REC="$(bash -c '. "$1/line.sh" && line_record "$2"' _ "$QL_LIB" "$QL_PLAN")"
QL_PROG="$RQL/progress-w1.md"
printf 'working\n' > "$QL_PROG"; backdate "$QL_PROG" 3000   # 10 cadences old
add_row "$RQL" name=w1 agent_id=aquiet-one-bbbbbbbbbbbbbbbb deliverable="$RQL/absent-w1.md" \
  duration="4 hours" launched_at="$(iso_ago 3600)" progress="$QL_PROG" cadence="5 minutes"
ql_sleeper() {  # -> a live process's carrier, `<pid>:<start>`, in QL_CAR (its pid is kept for the cleanup)
  sleep 600 & local p=$!
  QL_PIDS="$QL_PIDS $p"
  QL_CAR="${p}:$(bash -c '. "$1/slots.sh" && _slots_since "$2"' _ "$QL_LIB" "$p")"
}
ql_ready() {  # <name> <carrier> -> the record's ev=ready of row T1, as `line_ready` writes it
  bash -c '. "$1/line.sh" && line_event "$2" ready row=T1 "name=$3" "commit=$(printf "c%.0s" $(seq 40))" branch=wt/T1 tree=/x/T1 suites=none debt=none "carrier=$4"' \
    _ "$QL_LIB" "$QL_PLAN" "$1" "$2"
}
ql_clear() { rm -f "$QL_REC"; rm -rf "$BIONIC_GATE_DIR/requests"; mkdir -p "$BIONIC_GATE_DIR/requests"; }
ql_tick() { forget_digest "$RQL"; poke_pressure "$RQL" 8192 1.0 tick; }
ql_decision() { printf '%s\n' "$OUT" | sed -n 's/^.*|decision=\([A-Z]*\)|.*$/\1/p' | head -1; }
ql_rows() { printf '%s\n' "$OUT" | sed -n 's/^.*|rows=\([^|]*\).*$/\1/p' | head -1; }

# ---------- a dead silent row still NOTIFYs (the paired positive for every row below) ----------
ql_clear
ql_tick
expect_eq "QL-1 precondition: a row with no carrier, no request and a progress file ten cadences old is NOTIFY, naming w1" \
  "NOTIFY|w1" "$(ql_decision)|$(ql_rows)"
expect_contains "QL-1b …and the quiet line prints the mtime it rests on" "w1: no line for " "$OUT"

# ---------- a live carrier: the row is active ----------
ql_clear; ql_sleeper; ql_ready w1 "$QL_CAR"
ql_tick
expect_eq "QL-2b a live ready carrier of the row's name, files quiet past cadence: the tick prints QUIET and names no row" \
  "QUIET|" "$(ql_decision)|$(ql_rows)"
expect_absent "QL-2c …and no quiet line is printed for it" "w1: no line for " "$OUT"
# the same record, the carrier dead and nothing written
kill "${QL_PID_LAST:-${QL_CAR%%:*}}" 2>/dev/null; wait "${QL_CAR%%:*}" 2>/dev/null
ql_tick
expect_eq "QL-3 the same row with the carrier dead and nothing written: NOTIFY, naming w1" \
  "NOTIFY|w1" "$(ql_decision)|$(ql_rows)"

# ---------- a carrier of ANOTHER name masks nothing ----------
ql_clear; ql_sleeper; ql_ready w2 "$QL_CAR"
ql_tick
expect_eq "QL-4 a live carrier whose name is w2, not w1, leaves w1 NOTIFY" "NOTIFY|w1" "$(ql_decision)|$(ql_rows)"

# ---------- past the declared duration: the overdue arm reads the carrier too ----------
add_row "$RQL" name=w1 agent_id=aquiet-one-bbbbbbbbbbbbbbbb deliverable="$RQL/absent-w1.md" \
  duration="1 minute" launched_at="$(iso_ago 3600)" progress="$QL_PROG" cadence="5 minutes"
ql_clear; ql_tick
expect_eq "QL-5 precondition: a row past its declared duration with no carrier is NOTIFY (the overdue arm)" \
  "NOTIFY|w1" "$(ql_decision)|$(ql_rows)"
expect_contains "QL-5b …by the overdue arm's own detail" "past declared duration" "$OUT"
ql_sleeper; ql_ready w1 "$QL_CAR"
ql_tick
expect_eq "QL-5c the same overdue row with a live carrier: QUIET, no row named" "QUIET|" "$(ql_decision)|$(ql_rows)"
expect_absent "QL-5d …and no overdue detail is printed" "past declared duration" "$OUT"

# ---------- an open gate request for the row's agent, no carrier ----------
ql_clear
ql_ask() {  # <agent> -> a request the gate's own ask files for <agent>, its holder alive until the cleanup
  ( BIONIC_GATE_AGENT="$1" CLAUDE_CODE_SESSION_ID="$SID" bash -c '. "$1/gate.sh" && gate_ask work ql-fixture.test.sh --within 5 >/dev/null 2>&1; sleep 600' _ "$QL_LIB" ) &
  QL_PIDS="$QL_PIDS $!"
  local i=0
  while [ "$i" -lt 100 ] && ! /usr/bin/grep -qs "^who=${SID}:$1\$" "$BIONIC_GATE_DIR"/requests/[0-9]* 2>/dev/null; do sleep 0.1; i=$((i + 1)); done
}
ql_ask w1
expect_nonempty "QL-6 precondition: the gate holds a request whose who is this session's w1" \
  "$(/usr/bin/grep -ls "^who=${SID}:w1\$" "$BIONIC_GATE_DIR"/requests/[0-9]* 2>/dev/null | head -1)"
expect_eq "QL-6b precondition: the record holds no carrier (no file)" "no" "$([ -f "$QL_REC" ] && echo yes || echo no)"
ql_tick
expect_eq "QL-6c an open gate request for w1 and no carrier: the tick prints QUIET and names no row" "QUIET|" "$(ql_decision)|$(ql_rows)"
ql_clear; ql_ask w2
ql_tick
expect_eq "QL-7 an open request for another agent, w2, masks nothing: w1 is NOTIFY" "NOTIFY|w1" "$(ql_decision)|$(ql_rows)"

# the sleepers and the held requests end here, however the cases above went
for QL_P in $QL_PIDS; do kill "$QL_P" 2>/dev/null; wait "$QL_P" 2>/dev/null; done
ql_clear
POKE_BOUND="$QL_BOUND_WAS"

# ============================================================
section "§NOTREADY: a row reading an unruled decision or waiting on an open row is not ready: the tick prints its WAIT and offers FILL only for a row that waits on nothing, an open order offers none, and the wall ends the turn"
# ============================================================
# A row that should wait is made not ready by a fact of the plan the tick judges: a read of a decision no
# approved: line rules, a read of the record a still-open row writes, or the user's order under ## SDLC State.
# FIXTURE FIDELITY: s47_plan's reads table, approved at current: 4; T2 is active, so the record it writes is
# not yet written; the Stop is the shipped hooks/stop.sh on an ordinary turn of this session.
# fails-when: FILL names T1 or T3; either prints no WAIT; the wall refuses a turn on which no row is ready;
# an open order leaves a FILL; the tick prints a decline.
NR_REC=".bionic/docs/record/wave-01-fixture/T2-held.md"
RNR="$(make_repo notready)"; new_roster "$RNR"
NR_P="$(s47_plan "$RNR" 8 \
  "| T1 | 4 | build | reads a ruling | implementor | — | 10 | REQ-x | payload/a.sh | pending | approval:plan, approval:D3 |" \
  "| T2 | 4 | build | the open row | implementor | — | 10 | REQ-x | $NR_REC, payload/b.sh | active | |" \
  "| T3 | 4 | build | waits on T2 | implementor | — | 10 | REQ-x | payload/c.sh | pending | approval:plan, $NR_REC |" \
  "| T4 | 4 | build | waits on nothing | implementor | — | 10 | REQ-x | payload/d.sh | pending | |")"
nr_led() { tail -1 "$RNR/.bionic/docs/record/wave-01-fixture/fill-ledger.log" 2>/dev/null; }
nr_fill() { printf '%s\n' "$OUT" | /usr/bin/grep '^poker: FILL T'; }   # -> the FILL line, never its "FILL —" sentence
poke_pressure "$RNR" 8192 1.0 tick
expect_eq "NR-0 the tick over the table exits 0" "0" "$RC"
expect_eq "NR-1 FILL names only the row that waits on nothing" "poker: FILL T4" "$(nr_fill)"
expect_contains "NR-2 the row reading the unruled D3 prints its WAIT, naming the read" "poker: WAIT T1 — approval:D3" "$OUT"
expect_contains "NR-3 the row reading the record of the open T2 prints its WAIT, naming the writer" \
  "poker: WAIT T3 — reads $NR_REC, written by T2 (active)" "$OUT"
expect_absent "NR-4 …and the tick prints no decline (NR-1 read this same output)" "decline" "$OUT"
s31_stop "$RNR" "$(s31_transcript "$RNR" "carry on")"
expect_eq "NR-5 the control: T4 ready and nothing launched, the wall refuses the turn" "block" "$(s31_decision)"
expect_contains "NR-5b …naming T4 alone" "ready with room: T4 " "$(s31_reason)"

# T4 landed: every row left waits, the tick offers none, and the wall ends the turn.
awk '{ if (index($0, "| T4 |") == 1) sub(/\| pending \|/, "| landed |"); print }' "$NR_P" > "$NR_P.t" && mv "$NR_P.t" "$NR_P"
forget_digest "$RNR"; poke_pressure "$RNR" 8192 1.0 tick
expect_contains "NR-6 precondition: the waits still print" "poker: WAIT T1 — approval:D3" "$OUT"
expect_eq "NR-6b …and no row is offered" "" "$(nr_fill)"
s31_stop "$RNR" "$(s31_transcript "$RNR" "carry on")"
expect_contains "NR-7 meta: the wall read the turn, its ledger line is there" "fill-ledger/v1|" "$(nr_led)"
expect_contains "NR-7b …and no row was ready" "|ready=|" "$(nr_led)"
expect_eq "NR-7c the wall ends the turn" "" "$(s31_decision)"

# The user's order: T4 pending again, an open order under ## SDLC State, so nothing is offered; the
# order lifted, T4 is offered again.
awk '{ if (index($0, "| T4 |") == 1) sub(/\| landed \|/, "| pending |"); print }
     /^approved-by:/ { print "order: given 2026-10-20T00:00:00Z \"hold the fleet while I read\"" }' "$NR_P" > "$NR_P.t" && mv "$NR_P.t" "$NR_P"
forget_digest "$RNR"; poke_pressure "$RNR" 8192 1.0 tick
expect_contains "NR-8 under an open order the tick says so, quoting the words" \
  "no FILL — an order of the user stands: given 2026-10-20T00:00:00Z \"hold the fleet while I read\"" "$OUT"
expect_eq "NR-8b …and offers no row" "" "$(nr_fill)"
s31_stop "$RNR" "$(s31_transcript "$RNR" "carry on")"
expect_eq "NR-8c …and the wall ends the turn" "" "$(s31_decision)"
printf 'order: lifted 2026-10-20T00:30:00Z "hold the fleet while I read"\n' > "$NR_P.o"
awk -v f="$NR_P.o" '{ print } /^order: given/ { while ((getline l < f) > 0) print l }' "$NR_P" > "$NR_P.t" && mv "$NR_P.t" "$NR_P"
forget_digest "$RNR"; poke_pressure "$RNR" 8192 1.0 tick
expect_eq "NR-9 the control: the order lifted, T4 is offered again" "poker: FILL T4" "$(nr_fill)"

# ============================================================
section "§STEP: the approval line alone readies nothing: a plan at current: 2 that carries approved-by: offers no FILL and the wall ends the turn; at current: 4 the same table fills"
# ============================================================
# A row's approval:plan read is met only while the plan is at current: 4 or later. A plan approved and still at
# Step 2 has a ratified table nobody has started, and its rows wait for the step, in the tick, the wall and the
# table reader alike.
# FIXTURE FIDELITY: s47_plan's one-row reads table, its current: line rewritten in place; the Stop is the shipped
# hooks/stop.sh; the table reader is lib/units.sh `units_ready`, sourced from the shipped tree.
# fails-when: at current: 2 the tick prints FILL, the wall refuses, or units_ready names T1; at current: 4 any of
# the three disagrees.
RST="$(make_repo step)"; new_roster "$RST"
ST_P="$(s47_plan "$RST" 8 "| T1 | 4 | build | ready from step 4 | implementor | — | 10 | REQ-x | payload/a.sh | pending | |")"
st_at() { awk -v c="$1" '!d && /^current:/ { print "current: " c; d = 1; next } { print }' "$ST_P" > "$ST_P.t" && mv "$ST_P.t" "$ST_P"; }
st_ready() { bash -c '. "$1/units.sh" && units_ready "$2" 4' _ "${BIONIC_HOOKS_DIR}/../payload/scripts/lib" "$ST_P" 2>/dev/null; }
st_at 2
expect_contains "ST-0 precondition: the plan is at current: 2" "current: 2" "$(cat "$ST_P")"
expect_contains "ST-0b precondition: …and carries its approved-by: line" "$SP_APPROVED_LINE" "$(cat "$ST_P")"
poke_pressure "$RST" 8192 1.0 tick
expect_eq "ST-1 the tick at current: 2 exits 0" "0" "$RC"
expect_contains "ST-1b …says the step holds the fill" "no FILL — plan at current: 2" "$OUT"
expect_eq "ST-1c …and offers no row" "" "$(nr_fill)"
s31_stop "$RST" "$(s31_transcript "$RST" "carry on")"
expect_eq "ST-2 the wall at current: 2 ends the turn" "" "$(s31_decision)"
expect_eq "ST-3 the table reader at current: 2 names no ready row" "" "$(st_ready)"
st_at 4; forget_digest "$RST"
poke_pressure "$RST" 8192 1.0 tick
expect_eq "ST-4 at current: 4 the same table fills" "poker: FILL T1" "$(nr_fill)"
s31_stop "$RST" "$(s31_transcript "$RST" "carry on")"
expect_eq "ST-5 …the wall refuses the turn that left it" "block" "$(s31_decision)"
expect_eq "ST-6 …and the table reader names T1" "T1" "$(st_ready)"

# ============================================================
finish
