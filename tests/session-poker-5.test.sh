#!/bin/bash
# Tests for hooks/session-poker.sh — shard 5: the sections wave-38 adds (§CHECK, §WORD).
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
printf '#!/bin/bash\nexit 0\n' > "$RCK/tests/a.test.sh"; printf '#!/bin/bash\nexit 0\n' > "$RCK/tests/b.test.sh"
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
expect_contains "CK-6r-b …refused by the dry commit, in the gate's words" "the commit gate refused the plan with current: 6" "$CK_OUT"

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
expect_contains "CK-8r-b …refused by the judge" "current: 8 is admitted only when every fact the run owes holds" "$CK_OUT"
# The judge's refusal settles the person's ledger (cur8_owed_waivers): the advance opens a waiver item in the
# repository's owed store. The check takes the same judgment and not that write; the tree row above saw no file
# change across the check, and this row proves the store is a file that row reads.
expect_contains "CK-8r-c …the advance opened the waiver item the judge owes, in the store the check's tree row covers" \
  "waive:adversarial" "$(cat "$RCK/.bionic/tmp/owed-$SID.state" 2>/dev/null)"
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
# nothing else is. It runs, and says "would advance" on the two judge-refused fixtures, so the agreement rows
# CK-7r and CK-8r go red on it.
CK_MUT="$TMPROOT/ck-mutant"; mkdir -p "$CK_MUT/hooks" "$CK_MUT/scripts"
ln -s "$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)" "$CK_MUT/scripts/lib"
for ck_sib in "$(dirname "$POKER")"/*; do
  [ "$(basename "$ck_sib")" = session-poker.sh ] && continue
  ln -s "$ck_sib" "$CK_MUT/hooks/$(basename "$ck_sib")"
done
awk '/^[[:space:]]*cur7_judge [0-9]+[[:space:]]*$/ { sub(/cur7_judge [0-9]+/, ": \"${PV_HEAD8:=}\""); n++ } { print } END { print n + 0 > "/dev/stderr" }' \
  "$POKER" > "$CK_MUT/hooks/session-poker.sh" 2> "$TMPROOT/ck-mutant.n"
expect_eq "CK-mut0 the mutant replaces the judge's two call lines, parses, and differs from the poker" "2 0 differs" \
  "$(cat "$TMPROOT/ck-mutant.n") $(bash -n "$CK_MUT/hooks/session-poker.sh" >/dev/null 2>&1; echo "$?") $(cmp -s "$CK_MUT/hooks/session-poker.sh" "$POKER" && echo same || echo differs)"
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
ck_plan 7 "$CK_8R_PROOFS"
POKER="$CK_MUT/hooks/session-poker.sh"; poke "$RCK" current 8 --check; POKER="$CK_REAL_POKER"
CK_M8="$RC|$(printf '%s\n' "$OUT" | head -1)"
poke "$RCK" current 8; CK_A8="$RC"
expect_eq "CK-mut3 the mutant flips CK-8r: its check says would advance (exit 0) where the real advance refuses (exit 1)" \
  "0|poker: current 8 --check: would advance|1" "$CK_M8|$CK_A8"
POKE_BOUND="$CK_BOUND_WAS"

# ============================================================
section "§WORD: the user's word for the regression — waive regression '<reply>' writes one waived: line the regression judge and the Step-7 wall honour, and waive all '<reply>' writes four in one call (wave-38 T2; REQ-4 AC-4.2)"
# ============================================================
# A question's waiver covers it up to its head; the regression had no such line, so a head the regression could
# not prove waited on a run or on `approve regression-2`. `waive regression '<reply>'` writes
#
#   waived: question=regression head=<working head> by <git user.name> <ISO-UTC> "<reply>"
#
# in the grammar the three questions use (lib/proof.sh `proof_waiver_line`), and `waive all '<reply>'` writes four such
# lines, evidence, adversarial, structure and regression, in one transaction. The judge (lib/proof.sh
# `_proof_floor_judge`, asked by facts_state for `current 7` and `current 8`) reads a regression waiver newer than the
# plan's last regression proof as the regression's newest link, covered to its head; the Step-7 text wall
# (`_eg_refuse_floor_absent`) reads it through `proof_floor_absent`, the one reader of "is there a regression line".
# FIXTURE FIDELITY: §CUR7's shape (session-poker-4): a real repository on `wave/01-fixture` with two suites and
# lib/x.sh, base B and one code commit C; a double wave plan the real gate admits at Steps 6 and 7, bound to this
# session; every fact in the production writer's shape (`proof_line`, `proof_floor_line`). Every move is the real verb.
# fails-when: a gate still refuses at the waived head; the line is not the three questions' grammar; `waive all` writes
# other than four lines.
WD_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
WD_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib"
RWD="$(make_repo word)"
git -C "$RWD" config user.email t@example.com; git -C "$RWD" config user.name "Dana Fixture"
printf '.bionic\n' > "$RWD/.gitignore"
mkdir -p "$RWD/tests" "$RWD/lib" "$RWD/.bionic/docs/plans" "$RWD/.bionic/docs/record/w38"
printf '#!/bin/bash\nexit 0\n' > "$RWD/tests/a.test.sh"; printf '#!/bin/bash\nexit 0\n' > "$RWD/tests/b.test.sh"
printf 'one\n' > "$RWD/lib/x.sh"
( cd "$RWD" && git add .gitignore tests lib && git commit -qm base && git checkout -q -b wave/01-fixture ) >/dev/null 2>&1
printf 'generic fixture proof\n' > "$RWD/.bionic/docs/record/generic-evidence.md"
WD_B="$(git -C "$RWD" rev-parse HEAD)"
WD_C="$(s57_commit "$RWD" lib/x.sh 'C: a code change after the regression proof')"
PWD8="$RWD/.bionic/docs/plans/wave-x.plan.md"
wd_line() { bash -c '. "$1/proof.sh" && shift && proof_line "$@"' _ "$WD_LIB" "$@"; }
wd_floor() {  # <head> -> a regression proof at <head>, as proof-add floor writes it
  bash -c '. "$1/proof.sh" && proof_floor_line "$2" 2026-10-12T11:00:00Z record/w38/floor.log ""' _ "$WD_LIB" "$1"
}
wd_reads() {  # <head> -> the five readings a double wave plan is dealt, each passing, at <head>
  wd_line review "$1" 2026-10-12T12:00:00Z record/w38/evidence.md evidence w-read pass piece
  wd_line review "$1" 2026-10-12T12:00:00Z record/w38/adversarial.md adversarial w-read pass piece
  wd_line review "$1" 2026-10-12T12:00:00Z record/w38/structure.md structure w-read pass piece
  wd_line review "$1" 2026-10-12T12:00:00Z record/w38/adversarial-whole.md adversarial w-read pass whole
  wd_line review "$1" 2026-10-12T12:00:00Z record/w38/structure-whole.md structure w-read pass whole
}
wd_plan() {  # <current> <proof lines> -> PWD8, bound to this session (step lines through 7)
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: double\nscale: wave\n'
    printf 'deploy_target: none\nuse_worktree: false\nhas_ui: false\nwalk: exempt\n---\n# plan\n\n## SDLC State\n\n'
    printf 'current: %s\nworking-branch: wave/01-fixture\napproved-by: fixture 2026-09-22T00:00Z approved\n' "$1"
    printf -- '- Step 4: dispatched, record/w38/dispatch.md\n  worktree: .\n  base-sha: %s\n  branch: wave/01-fixture\n' "$WD_B"
    printf -- '- Step 5: floor, record/w38/floor.log\n'
    printf -- '- Step 6: review at record/w38/review.md\n'
    printf -- '- Step 7: documented at record/w38/docs.md\n  n/a: no decision this run\n'
    printf '%s\n' "$2"
    printf '\n## Verification Matrix\n\nstack-health: n/a: no long-running serve\n\n'
    printf '| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |\n\n'
    printf 'AC-1:\n  fails-when: the planted defect this eval must go red on\n  evidence: record/generic-evidence.md\n'
    printf '  tier-run: bash tests/a.test.sh\n  readback: the line it wrote\n'
  } > "$PWD8"
  bind_marker "$RWD" "$PWD8"
}
wd_judge() {  # -> facts_state's lines for PWD8 at the working branch's ref, `regression <state>` or `<question>-<scope> <state>` (the regression fact under either name, wave-38 T8 renames it)
  bash -c '. "$1/run.sh" && . "$1/proof.sh" && facts_state "$2" "$3"' _ "$WD_LIB" "$PWD8" "$(git -C "$RWD" rev-parse --verify -q wave/01-fixture)" 2>/dev/null \
    | awk -F'\t' '$1 == "floor" || $1 == "regression" { print "regression " $2; next } $1 == "review" { print $2 "-" $4 " " $5 }'
}
wd_current() { sed -n 's/^current: //p' "$PWD8"; }
WD_ISO='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'

# ---------- waive regression: the one line, and current 7 passes at a head the regression refuses without it ----------
wd_plan 6 "$(wd_floor "$WD_B")
$(wd_reads "$WD_C")"
expect_eq "WD-0 precondition: the regression proof at B, the head at C: the judge reads it uncovered, the readings covered" \
  "regression uncovered|evidence-piece covered" "$(wd_judge | awk 'NR <= 2' | paste -sd'|' -)"
poke "$RWD" current 7
expect_eq "WD-0b precondition: …so current 7 is refused at C (exit 1), the plan at current: 6" "1|6" "$RC|$(wd_current)"
expect_contains "WD-0c …in the judge's words" "uncovered" "$OUT"
poke "$RWD" waive regression '1'
expect_eq "WD-1 AC-4.2 waive regression '1' is admitted (exit 0)" "0" "$RC"
expect_regex "WD-1b …and writes one line in the three questions' grammar: the question, the working head, who, when, the reply" \
  "^waived: question=regression head=${WD_C} by Dana Fixture ${WD_ISO} \"1\"$" "$(/usr/bin/grep -E '^waived: ' "$PWD8")"
expect_contains "WD-1c …and the success line names it" "question=regression head=${WD_C}" "$OUT"
expect_eq "WD-2 AC-4.2 …which the judge reads: the regression covered at C" "regression covered" "$(wd_judge | awk 'NR == 1')"
poke "$RWD" current 7
expect_eq "WD-3 AC-4.2 current 7 passes at the waived head (exit 0), the plan at current: 7" "0|7" "$RC|$(wd_current)"

# ---------- waive all: four lines in one call, and current 8 passes ----------
wd_plan 7 "$(wd_floor "$WD_B")
$(wd_reads "$WD_B")"
expect_eq "WD-4 precondition: every reading and the regression at B, the head at C: the judge reads all six uncovered" \
  "6|0" "$(wd_judge | awk '$2 == "uncovered"' | awk 'END { print NR }')|$(wd_judge | awk '$2 == "covered"' | awk 'END { print NR }')"
poke "$RWD" current 8
expect_eq "WD-4b precondition: …so current 8 is refused at C (exit 1), the plan at current: 7" "1|7" "$RC|$(wd_current)"
poke "$RWD" waive all '1'
expect_eq "WD-5 AC-4.2 waive all '1' is admitted (exit 0)" "0" "$RC"
expect_eq "WD-5b …and writes four lines, evidence, adversarial, structure and regression, each at C with the reply" \
  "evidence ${WD_C} \"1\"|adversarial ${WD_C} \"1\"|structure ${WD_C} \"1\"|regression ${WD_C} \"1\"" \
  "$(/usr/bin/grep -E '^waived: ' "$PWD8" | awk '{ q = $2; h = $3; sub(/^question=/, "", q); sub(/^head=/, "", h); print q " " h " " $NF }' | paste -sd'|' -)"
expect_eq "WD-5c …each in the one grammar" "4" \
  "$(/usr/bin/grep -cE "^waived: question=(evidence|adversarial|structure|regression) head=${WD_C} by Dana Fixture ${WD_ISO} \"1\"$" "$PWD8" | tr -d ' ')"
expect_eq "WD-6 AC-4.2 …which the judge reads: all six covered at C" "6" "$(wd_judge | awk '$2 == "covered"' | awk 'END { print NR }')"
poke "$RWD" current 8
expect_eq "WD-7 AC-4.2 current 8 passes at the waived head (exit 0), the plan at current: 8" "0|8" "$RC|$(wd_current)"

# ---------- what the verb refuses ----------
wd_plan 6 "$(wd_floor "$WD_B")"
cp "$PWD8" "$TMPROOT/wd-before"
poke "$RWD" waive verdict '1'
expect_eq "WD-8 a word outside the five is refused (exit 1), the plan byte-identical" "1|same" \
  "$RC|$(cmp -s "$TMPROOT/wd-before" "$PWD8" && echo same || echo changed)"
expect_contains "WD-8b …naming the five" "evidence, adversarial, structure, regression or all" "$OUT"
POKE_BOUND="$WD_BOUND_WAS"

finish
