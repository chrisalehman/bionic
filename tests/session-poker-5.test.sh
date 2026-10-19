#!/bin/bash
# Tests for hooks/session-poker.sh — shard 5: the sections wave-38 adds (§CHECK, §WORD, §EARLY-TICK, §DECISIONS, §ORDER).
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
# a.test.sh READS lib/x.sh (wave-39 T24; D5, AC-18.1): a commit past the floor owes the suites that read what it changed,
# so C, a change to lib/x.sh, is unproved until a.test.sh runs at it; a file no suite reads would owe nothing.
printf '#!/bin/bash\n[ -s "$(dirname "$0")/../lib/x.sh" ]\n' > "$RWD/tests/a.test.sh"; printf '#!/bin/bash\nexit 0\n' > "$RWD/tests/b.test.sh"
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
expect_eq "DC-1b …every register entry of this run's ledger, number · reply · who and date · title, in the ledger's order" "$DC_WANT" "$OUT"
expect_absent "DC-1c …never a body line, a heading with no ruling, or a fenced example (DC-1b read the same output)" "D9" "$OUT"
poke "$RDC" decisions --all
expect_eq "DC-2 decisions --all exits 0" "0" "$RC"
expect_eq "DC-2b …every wave's entries keyed by its slug, waves in slug order, the ADRs keyed by their wave, a pre-register ledger named once" \
  "wave-00-earlier D1 · \"2\" · Dana Fixture 2026-09-01 · the earlier frame
$(printf '%s\n' "$DC_WANT" | sed 's/^/wave-01-fixture /')
wave-01-fixture ADR-001 · Accepted (Step 7, 2026-10-08) · One door to resume
wave-02-old · no register entries (a ledger written before D24)" "$OUT"
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
expect_true "DC-5 precondition: the decision skill reads (its When it applies section is found)" grep -q '^## When it applies' "$DC_SKILL"
expect_true "DC-5b the decision skill requires the reopening form under When it applies" \
  bash -c 'awk "/^## When it applies/ { f = 1; next } f && /^## / { exit } f" "$1" | grep -qF "reopening D<n>: <one sentence of new evidence>"' _ "$DC_SKILL"

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
expect_eq "DG-2 AC-7.1 over wave 38's ledger decisions lists D30 three times and D31 five times, in the ledger's order, with the verb, the qualifier and the who and date each line carries" \
  "$D6_WANT" "$(printf '%s\n' "$D6_OUT" | d6_pick)"
expect_eq "DG-2b …and those are the only entries (D28 and D29 are bullets of the same Δ, the Δ23 heading names three numbers and is none: 3 + 5 + 2)" \
  "10" "$(printf '%s\n' "$D6_OUT" | grep -c .)"
expect_contains "DG-2c …the heading form's title is the words after its colon, its who and date the parenthesis that ends the line" \
  "D31 · ruled · Chris Lehman 2026-10-17 · an Assessment mark encodes deviation from a tolerance" "$D6_OUT"
expect_contains "DG-2d …a tail after the parenthesis that is not ': <title>' is the title (D31 ratified: ' on the presented table: …')" \
  'D31 · ratified "Yes" · Chris Lehman 2026-10-17 · on the presented table: ' "$D6_OUT"
expect_absent "DG-3 AC-7.2 the put line has no entry (DG-2 read the same output): its words are in no line" "5:55 PM" "$D6_OUT"
expect_eq "DG-3b …and no line is the put line's: no entry whose verb is put" "0" "$(printf '%s\n' "$D6_OUT" | grep -c ' put')"
poke "$RD6" decisions --all
expect_eq "DG-4 decisions --all exits 0" "0" "$RC"
expect_eq "DG-4b AC-7.1 …and lists the same eight, keyed by the wave, in the same order" "$D6_WANT" "$(printf '%s\n' "$OUT" | d6_pick)"
# The resume recap reads the same list. The world is handoff-file §RESUME's, reduced: the plan on its branches, the
# handoff written by the real verb while bound, then the session made new (engaged, unbound, unstamped).
git -C "$RD6" config user.name "Dana Fixture"; git -C "$RD6" config user.email t@example.com
( cd "$RD6" && git commit -q --allow-empty -m init && git branch -f trunk HEAD && git commit -q --allow-empty -m work && git branch -f wave/01-fixture HEAD )
awk 'NR == 1 && $0 == "---" { print; print "working-branch: wave/01-fixture"; print "integration-branch: trunk"; next } { print }' "$PD6" > "$PD6.d6" && mv "$PD6.d6" "$PD6"
s42_snap "$RD6" "$PD6"
poke "$RD6" handoff --mid-flight 'T2 is in its ready loop'
expect_eq "DG-5 precondition: the handoff is written by the real verb while bound" "0" "$RC"
D6_DOOR=".bionic/docs/record/wave-01-fixture/handoff.md"
expect_true "DG-5b precondition: …and the file is there" test -s "$RD6/$D6_DOOR"
engage "$RD6"
rm -f "$(stamp_of "$RD6")" "$(armed_of "$RD6")" "$(digest_of "$RD6")"
poke "$RD6" resume "$D6_DOOR"
expect_eq "DG-6 precondition: resume exits 0" "0" "$RC"
expect_eq "DG-6b AC-7.1 the recap's settled: lines are the same eight, in the same order" "$D6_WANT" "$(printf '%s\n' "$OUT" | grep '^settled: ' | d6_pick)"
expect_eq "DG-6c …and the recap lists every entry of the ledger as settled: (3 + 5 + 2)" "10" "$(printf '%s\n' "$OUT" | grep -c '^settled: D')"

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
expect_eq "OR-3 AC-6.5 three ready writers, a cap of 8 and room past them: width idles, and the split candidate of the chain is a decision line with its reason (T4: 1 row waits × 40 min × 1 file outscores T3's 30)" \
  "poker: SPLIT T4 — 40 min, 1 files, 1 rows wait on it; width idles at 3" "$(s47_lines SPLIT)"

# ---------- the trim keeps the longest chain: a gap of one offers T3, and nothing idles ----------
or_plan 1
poke_pressure "$ROR" 8192 1.0 tick
expect_eq "OR-4 AC-6.5 a writer gap of one (cap 1) offers T3, never table-first T1" "poker: FILL T3" "$(or_fill)"
expect_contains "OR-4b …T1 waits for a slot, its reason the gap" "poker: WAIT T1 — ready; no writer slot free (gap 1)" "$OUT"
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
expect_nonempty "QL-2 precondition: the record holds the row's ready event" "$(/usr/bin/grep -c 'ev=ready' "$QL_REC")"
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
section "§BRIEF-UNION: brief always unions the reads index into Suites: and Lands-on:, whether or not the row has a suites cell, and the wall admits the rendered text (wave-39 T23; REQ-17 AC-17.1; D22)"
# ============================================================
# T43's brief rendered Suites: pending and Lands-on: pending from a row with an empty suites cell and the orchestrator
# filled both by hand from the index. A row's own cells used to END the derivation (a suites cell, a lands-on cell, and
# the index was never read), so a row that named some of its suites got a Lands-on the wall refused for omitting the
# rest. Now Suites: is the row's suites cell (else its Files' *.test.sh entries) with the reads index over its Files
# unioned after it, and Lands-on: is the lands-on cell (else the Suites) with the same index unioned after it, once
# each, for a row whose Files write the head. A row that writes no code keeps Lands-on: none <reason>.
# FIXTURE FIDELITY: session-poker-3 §BRIEF's world (three suites read payload/scripts/lib/walls.sh by the three routes
# the index knows, one names it only in a comment, committed on the working branch; the index is the real one, read by
# the real verb) and session-poker-4 §BRIEF's gate (the wall run on the rendered text, as an Agent call's prompt, under
# a scratch HOME, attestation, patrol stamp and engagement).
# fails-when: a row with a suites cell, or a lands-on cell, or neither, prints a Suites: or Lands-on: that omits a suite
# the index names for its Files; the rendered brief is refused by the wall for a Lands-on: outside Suites: or one that
# omits an index suite; a code-free row loses its `none <reason>`.
BU_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RBU="$(make_repo brief-union)"; ( cd "$RBU" && git commit -q --allow-empty -m init )
mkdir -p "$RBU/payload/scripts/lib" "$RBU/hooks" "$RBU/tests"
printf 'the wall line\n' > "$RBU/payload/scripts/lib/walls.sh"
printf '#!/bin/bash\nBIONIC_LIB_WANT="walls.sh"\n' > "$RBU/hooks/h.sh"
printf '#!/bin/bash\ngrep -c wall "$REPO/payload/scripts/lib/walls.sh"\n' > "$RBU/tests/s-grep.test.sh"
printf "#!/bin/bash\nanchor file payload/scripts/lib/walls.sh 'the wall line'\n" > "$RBU/tests/s-anchor.test.sh"
printf '#!/bin/bash\nbash "$REPO/hooks/h.sh"\n' > "$RBU/tests/s-hook.test.sh"
printf '#!/bin/bash\n# payload/scripts/lib/walls.sh is named only in this comment\necho none\n' > "$RBU/tests/s-none.test.sh"
printf '#!/bin/bash\necho extra\n' > "$RBU/tests/s-extra.test.sh"
( cd "$RBU" && git add payload hooks tests && git commit -qm "three suites read walls.sh" )
PBU="$(s42_plan "$RBU" 4)"
BU_REC=".bionic/docs/record/wave-01-fixture"
BU_TABLE="$TMPROOT/bu-table.md"
{
  printf '## Tasks\n\n'
  printf '| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | suites | lands-on |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n'
  printf '| T51 | 4 | build | a row that names some suites and a lands-on | implementor | — | 30 | REQ-1 | payload/scripts/lib/walls.sh, %s/T51-w.md | — | — | pending | s-grep.test.sh, s-extra.test.sh | s-grep.test.sh |\n' "$BU_REC"
  printf '| T52 | 4 | build | a row with an empty suites cell | implementor | — | 30 | REQ-1 | payload/scripts/lib/walls.sh, %s/T52-w.md | — | — | pending | — | — |\n' "$BU_REC"
  printf '| T53 | 4 | build | a row that names suites and no lands-on | implementor | — | 30 | REQ-1 | payload/scripts/lib/walls.sh, %s/T53-w.md | — | — | pending | s-extra.test.sh | — |\n' "$BU_REC"
  printf '| T55 | 4 | build | a row whose task carries an escaped pipe, a case label (a\\|b), as T43'"'"'s did | implementor | — | 30 | REQ-1 | payload/scripts/lib/walls.sh, %s/T55-w.md | — | — | pending | s-extra.test.sh | — |\n' "$BU_REC"
  printf '| T54 | 4 | doc | a record and no code | implementor | — | 30 | REQ-1 | %s/T54-text.md | — | — | pending | — | — |\n' "$BU_REC"
  printf '\n'
} > "$BU_TABLE"
awk -v t="$BU_TABLE" '/^## Tasks/ { while ((getline l < t) > 0) print l; skip = 1; next } skip && /^## / { skip = 0 } !skip { print }' "$PBU" \
  | awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' > "$PBU.new" && mv "$PBU.new" "$PBU"
( cd "$RBU" && git add -f "$PBU" && git commit -qm "brief-union fixture" && git branch -f wave/01-fixture HEAD ) >/dev/null 2>&1
BU_DIR="$RBU/$BU_REC/briefs"
bu_field() {  # <file> <label> -> the value of the first `<label>:` line, trimmed
  awk -v l="$2" 'index($0, l ":") == 1 { v = substr($0, length(l) + 2); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); print v; exit }' "$1"
}
BU_IDX="s-anchor.test.sh, s-grep.test.sh, s-hook.test.sh"
expect_eq "BU-0 precondition: the reads index at the working head names the three reading suites for walls.sh, and not s-none or s-extra" \
  "tests/s-anchor.test.sh,tests/s-grep.test.sh,tests/s-hook.test.sh" \
  "$(bash "${BIONIC_HOOKS_DIR}/../payload/scripts/lib/anchors.sh" reads_index "$RBU" --at wave/01-fixture 2>/dev/null | awk -F'\t' '$1 == "payload/scripts/lib/walls.sh" { print $2 }')"

poke "$RBU" brief T51
expect_eq "BU-1 a row with a suites cell and a lands-on cell: exit 0, Suites is the cell then the index's suites it lacks" \
  "0|s-grep.test.sh, s-extra.test.sh, s-anchor.test.sh, s-hook.test.sh" "$RC|$(bu_field "$BU_DIR/T51.md" Suites)"
expect_eq "BU-1b …and Lands-on is its cell then the index's suites it lacks (the index's union, none omitted)" \
  "s-grep.test.sh, s-anchor.test.sh, s-hook.test.sh" "$(bu_field "$BU_DIR/T51.md" Lands-on)"
poke "$RBU" brief T52
expect_eq "BU-2 a row whose suites cell is empty (T43's row): Suites is the index's union, no slot" \
  "0|$BU_IDX" "$RC|$(bu_field "$BU_DIR/T52.md" Suites)"
expect_eq "BU-2b …and Lands-on is the index's union" "$BU_IDX" "$(bu_field "$BU_DIR/T52.md" Lands-on)"
poke "$RBU" brief T53
expect_eq "BU-3 a row with a suites cell and no lands-on cell: Suites is the cell then the index's suites" \
  "0|s-extra.test.sh, s-anchor.test.sh, s-grep.test.sh, s-hook.test.sh" "$RC|$(bu_field "$BU_DIR/T53.md" Suites)"
expect_eq "BU-3b …and Lands-on is the same set, so it holds every index suite and stays inside Suites" \
  "s-extra.test.sh, s-anchor.test.sh, s-grep.test.sh, s-hook.test.sh" "$(bu_field "$BU_DIR/T53.md" Lands-on)"
expect_absent "BU-3c …a suite naming the file only in a comment is named by none of the three (positive: BU-3 read four)" \
  "s-none.test.sh" "$(bu_field "$BU_DIR/T51.md" Suites)$(bu_field "$BU_DIR/T52.md" Suites)$(bu_field "$BU_DIR/T53.md" Suites)"
poke "$RBU" brief T54
expect_eq "BU-4 a row that writes no code keeps Suites: none (positive: Row reads from the same file)" "T54|none" \
  "$(bu_field "$BU_DIR/T54.md" Row)|$(bu_field "$BU_DIR/T54.md" Suites)"
expect_regex "BU-4b …and Lands-on: none with a reason" '^none [A-Za-z]' "$(bu_field "$BU_DIR/T54.md" Lands-on)"

# T43's row carried a case label `(name\|other)` in its task cell, and the cell reader split on every `|`, so its
# suites cell read as the status cell to its left: `pending`. The units reader honours `\|`; the cell reader now does.
poke "$RBU" brief T55
expect_eq "BU-8 a row whose task cell carries an escaped pipe reads its own suites cell (not the status beside it): the cell, then the index's suites" \
  "0|s-extra.test.sh, s-anchor.test.sh, s-grep.test.sh, s-hook.test.sh" "$RC|$(bu_field "$BU_DIR/T55.md" Suites)"
expect_eq "BU-8b …and its Lands-on is the same set" "s-extra.test.sh, s-anchor.test.sh, s-grep.test.sh, s-hook.test.sh" "$(bu_field "$BU_DIR/T55.md" Lands-on)"
expect_absent "BU-8c …and neither line says pending (positive: BU-8 read a Suites)" "pending" "$(bu_field "$BU_DIR/T55.md" Suites)$(bu_field "$BU_DIR/T55.md" Lands-on)"

# ---------- the wall, run on the rendered text ----------
BU_HOME="$TMPROOT/bu-home"; BU_PROJ="$BU_HOME/.claude/projects/$(bash -c '. "$1/detect.sh" >/dev/null 2>&1; project_slug "$2"' _ "${BIONIC_HOOKS_DIR}/../payload/scripts/lib" "$RBU")"
mkdir -p "$BU_PROJ"; : > "$BU_PROJ/$SID.jsonl"
printf 'patrol-stamp/v1|at=%s|session=%s|verb=arm\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SID" > "$RBU/.bionic/tmp/patrol-$SID.state"
printf '# fixture attestation\nversion=1\nkind=preflight-attestation\nsession_id=%s\nwritten_at=1785790000\nrepo=%s\n' "$SID" "$RBU" > "$RBU/.bionic/tmp/preflight-$SID.state"
bu_gate() {  # <brief text file> <agent name> -> sets BU_OUT, BU_ERR
  local payload
  payload="$(jq -n --arg s "$SID" --arg c "$RBU" --arg n "$2" --rawfile p "$1" \
    '{session_id:$s, transcript_path:"/nonexistent.jsonl", cwd:$c, hook_event_name:"PreToolUse", tool_name:"Agent",
      tool_input:{description:"a rendered brief", subagent_type:"implementor", prompt:$p, run_in_background:true, name:$n},
      tool_use_id:"toolu_brief_union"}')"
  BU_OUT="$( cd "$RBU" && printf '%s' "$payload" | env HOME="$BU_HOME" CLAUDE_CONFIG_DIR="$BU_HOME/.claude" ANTHROPIC_API_KEY=sk-fixture \
    CLAUDE_CODE_SESSION_ID="$SID" BIONIC_WALL_VERBOSE=1 bash "${BIONIC_HOOKS_DIR}/dispatch-preflight.sh" 2>"$TMPROOT/bu-gate.err" )"
  BU_ERR="$(cat "$TMPROOT/bu-gate.err")"
}
bu_row() { /usr/bin/grep -F "|name=$2|" "$(roster_of "$1")" 2>/dev/null | tail -1; }
for BU_T in T51 T52 T53 T55; do
  bu_gate "$BU_DIR/$BU_T.md" "w-$BU_T"
  expect_absent "BU-5-$BU_T the wall does not refuse the rendered $BU_T brief (outside-Suites and omission arms: zero refusals)" '"permissionDecision":"deny"' "$BU_OUT"
  expect_contains "BU-5b-$BU_T …and it journalled the launch row for $BU_T (the positive that the wall read the brief)" "|name=w-$BU_T|" "$(bu_row "$RBU" "w-$BU_T")"
done
# the wall can refuse each arm on this same text: the two negatives above are tests only beside these two positives
sed 's/^Lands-on: .*/Lands-on: s-grep.test.sh, s-anchor.test.sh, s-hook.test.sh, s-none.test.sh/' "$BU_DIR/T52.md" > "$TMPROOT/bu-outside.md"
bu_gate "$TMPROOT/bu-outside.md" w-T52o
expect_contains "BU-6 the rendered T52 with a Lands-on: suite outside Suites: is denied by the wall" '"permissionDecision":"deny"' "$BU_OUT"
expect_contains "BU-6b …by the outside-Suites arm" "is outside Suites" "$BU_OUT$BU_ERR"
sed 's/^Lands-on: .*/Lands-on: s-grep.test.sh/' "$BU_DIR/T52.md" > "$TMPROOT/bu-omits.md"
bu_gate "$TMPROOT/bu-omits.md" w-T52m
expect_contains "BU-7 the rendered T52 with a Lands-on: that omits two index suites is denied by the wall" '"permissionDecision":"deny"' "$BU_OUT"
expect_contains "BU-7b …by the omission arm" "omits" "$BU_OUT$BU_ERR"
POKE_BOUND="$BU_BOUND_WAS"

# ============================================================
section "§OWED-WORDS: the judge's refusal, the tick's wait reason and regression-run's refusal each end waive regression '<reply>' beside the second whole run, and name the owed set (wave-39 T25; REQ-18 AC-18.3; D5)"
# ============================================================
# A run whose head owes suites past the regression's head was told the way out in three places, and none of them named
# the user's word for the regression: `current 8` closed on "waive a question", the tick's wait on `approve regression-2`,
# and regression-run's second-run refusal on the approval. An orchestrator reading them invented `approve regression-2`
# where the record could only say `waive regression`. Now each ends on `waive regression '<reply>'` beside the second
# whole run, and the judge and regression-run name THE OWED SET (lib/proof.sh `proof_owed_suites`, the one reader) in
# one clause (`proof_owed_say`). A head whose owed set is empty owes no run, so no surface offers the waiver for it.
# FIXTURE FIDELITY: §CHECK's world shape, built afresh: a real repository on `wave/01-fixture`, a.test.sh reading
# lib/x.sh and b.test.sh reading nothing, a stub tests/run.sh that only counts its runs; base B, a code commit C that
# a.test.sh reads, and later a glossary commit D in a Markdown file outside the fixed docs list, which no suite reads
# (AC-18.1). A double wave plan bound to this session, its integrate row pending, every fact in the production
# writer's shape (`proof_line`, `proof_floor_line`). Every move is the real verb.
# fails-when: a surface names the run and not the waiver, or ends on anything else; the judge or regression-run names
# another set than proof_owed_suites prints; a surface offers the waiver at a head whose owed set is empty.
OW_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
ROW="$(make_repo owed-words)"
git -C "$ROW" config user.email t@example.com; git -C "$ROW" config user.name "Dana Fixture"
printf '.bionic\n' > "$ROW/.gitignore"
mkdir -p "$ROW/tests" "$ROW/lib" "$ROW/notes" "$ROW/.bionic/docs/plans" "$ROW/.bionic/docs/record/w35"
OW_SEEN="$TMPROOT/ow-seen"; : > "$OW_SEEN"
printf '#!/bin/bash\n[ -s "$(dirname "$0")/../lib/x.sh" ]\n' > "$ROW/tests/a.test.sh"; printf '#!/bin/bash\nexit 0\n' > "$ROW/tests/b.test.sh"
printf '#!/bin/bash\nprintf ran >> "%s"\nexit 0\n' "$OW_SEEN" > "$ROW/tests/run.sh"
printf 'one\n' > "$ROW/lib/x.sh"; printf '# Glossary\n' > "$ROW/notes/glossary.md"
( cd "$ROW" && git add .gitignore tests lib notes && git commit -qm base && git checkout -q -b wave/01-fixture ) >/dev/null 2>&1
printf 'generic fixture proof\n' > "$ROW/.bionic/docs/record/generic-evidence.md"
OW_B="$(git -C "$ROW" rev-parse HEAD)"
OW_C="$(s57_commit "$ROW" lib/x.sh 'C: a code change a.test.sh reads')"
POW="$ROW/.bionic/docs/plans/wave-x.plan.md"
ow_plan() {  # <current> <proof lines> -> POW with a pending integrate row, bound to this session
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: double\nscale: wave\n'
    printf 'deploy_target: none\nuse_worktree: false\nhas_ui: false\nwalk: exempt\n---\n# plan\n\n## SDLC State\n\n'
    printf 'current: %s\nworking-branch: wave/01-fixture\napproved-by: fixture 2026-09-22T00:00Z approved\n' "$1"
    printf -- '- Step 4: dispatched, record/w35/dispatch.md\n  worktree: .\n  base-sha: %s\n  branch: wave/01-fixture\n' "$OW_B"
    printf -- '- Step 5: floor, record/w35/floor.log\n  auditor: CONFIRMED, record/w35/audit.md\n'
    printf -- '- Step 6: review at record/w35/review.md\n'
    printf -- '- Step 7: documented at record/w35/docs.md\n  n/a: no decision this run\n'
    printf '%s\n' "$2"
    printf '\n## Verification Matrix\n\nstack-health: n/a: no long-running serve\n\n'
    printf '| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |\n\n'
    printf 'AC-1:\n  fails-when: the planted defect this eval must go red on\n  evidence: record/generic-evidence.md\n'
    printf '  tier-run: bash tests/a.test.sh\n  readback: the line it wrote\n'
    printf '\n## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T1 | 4 | build | the x writer | implementor | — | 30 | REQ-1 | lib/x.sh | — | — | landed | approval:plan |\n'
    printf '| T3 | 8 | integrate | merge into main | orchestrator | — | 10 | REQ-1 | — | — | — | pending | approval:release, approval:merge, proof:regression, head |\n'
  } > "$POW"
  bind_marker "$ROW" "$POW"; new_roster "$ROW"
}
ow_set() { bash -c '. "$1/run.sh" && . "$1/proof.sh" && proof_owed_suites "$2" "$3"' _ "$CK_LIB" "$POW" "$ROW" 2>/dev/null; }
ow_last() { printf '%s\n' "$1" | awk 'NF { l = $0 } END { print l }'; }   # <text> -> its last non-blank line
ow_wait() { printf '%s\n' "$OUT" | awk 'index($0, "poker: WAIT T3 ") == 1 { print; exit }'; }   # the tick's WAIT line for T3
ow_runs() { wc -c < "$OW_SEEN" | tr -d ' '; }
OW_TAIL="waive regression '<reply>'"

# ---------- a head that owes a.test.sh: the three surfaces ----------
ow_plan 7 "$(ck_floor "$OW_B")
$(ck_reads "$OW_C")"
OW_SET="$(ow_set)"
expect_eq "OW-0 precondition: the owed set at C is a.test.sh, the suite that reads what C changed (proof_owed_suites, the one reader)" \
  "a.test.sh" "$OW_SET"
poke "$ROW" current 8
expect_eq "OW-1 precondition: current 8 is refused at C (exit 1), the plan at current: 7" "1|7" "$RC|$(sed -n 's/^current: //p' "$POW")"
expect_contains "OW-1b …by the judge, on the regression" "regression	uncovered	" "$OUT"
expect_regex "OW-2 AC-18.3 the judge's refusal ends on the user's word for the regression" "waive regression '<reply>'\$" "$(ow_last "$OUT")"
expect_contains "OW-2b …beside the second whole run" "a second whole run, or the user's word: ${OW_TAIL}" "$(ow_last "$OUT")"
expect_contains "OW-2c …and names the owed set proof_owed_suites prints" "the head owes ${OW_SET}:" "$(ow_last "$OUT")"
# The integrate row waits for its step first, so the tick is asked of the run at current: 8, C landed after the advance.
ow_plan 8 "$(ck_floor "$OW_B")
$(ck_reads "$OW_C")"
forget_digest "$ROW"
poke "$ROW" tick
expect_contains "OW-3 precondition: the tick holds the integrate row on the regression (the extractor reads real output)" \
  "proof:regression: the regression is one whole run plus each later commit proved" "$(ow_wait)"
expect_regex "OW-3b AC-18.3 the tick's wait reason ends on the user's word for the regression" "waive regression '<reply>'\$" "$(ow_wait)"
expect_contains "OW-3c …beside the second whole run" "a second run: approve regression-2, or the user's word: ${OW_TAIL}" "$(ow_wait)"
ow_plan 7 "$(ck_floor "$OW_B")
$(ck_reads "$OW_C")"
poke "$ROW" regression-run
expect_eq "OW-4 precondition: regression-run refuses a second whole run at C (exit 1), and nothing ran" "1|0" "$RC|$(ow_runs)"
expect_contains "OW-4b …as a second whole run" "a second whole run on this plan" "$OUT"
expect_regex "OW-4c AC-18.3 regression-run's refusal ends on the user's word for the regression" "waive regression '<reply>'\$" "$(ow_last "$OUT")"
expect_contains "OW-4d …and names the owed set proof_owed_suites prints" "the head owes ${OW_SET}:" "$OUT"

# ---------- the user's word closes it: every surface goes quiet ----------
poke "$ROW" waive regression '1'
expect_eq "OW-5 the user's waive regression '1' is admitted (exit 0)" "0" "$RC"
expect_eq "OW-5b …and the owed set is empty to the waiver's head" "" "$(ow_set)"
poke "$ROW" current 8
expect_eq "OW-5c …so current 8 is admitted (exit 0), the plan at current: 8" "0|8" "$RC|$(sed -n 's/^current: //p' "$POW")"

# ---------- AC-18.1: a glossary commit past the regression's head owes nothing, and no surface offers the waiver ----------
OW_D="$(s57_commit "$ROW" notes/glossary.md 'D: a glossary line, read by no suite')"
ow_plan 7 "$(ck_floor "$OW_C")
$(ck_reads "$OW_D")"
expect_eq "OW-6 precondition: past the regression's head at C, the glossary commit D owes nothing (the extractor read a.test.sh at OW-0)" \
  "" "$(ow_set)"
poke "$ROW" current 8
expect_eq "OW-6b current 8 is admitted at D (exit 0)" "0" "$RC"
expect_absent "OW-6c …and says nothing of the regression's waiver (OW-2 is the positive)" "waive regression" "$OUT"
ow_plan 8 "$(ck_floor "$OW_C")
$(ck_reads "$OW_D")"
forget_digest "$ROW"
poke "$ROW" tick
expect_contains "OW-7 precondition: the tick still holds the integrate row (the extractor reads real output)" "poker: WAIT T3 " "$(ow_wait)"
expect_absent "OW-7b …but not on the regression, and with no waiver (OW-3 is the positive)" "proof:regression" "$(ow_wait)"
poke "$ROW" regression-run
expect_eq "OW-8 regression-run refuses a run at D, which the regression covers (exit 1), and nothing ran" "1|0" "$RC|$(ow_runs)"
expect_contains "OW-8b …saying the head is already proved" "is already proved" "$OUT"
expect_absent "OW-8c …and offering no waiver (OW-4c is the positive)" "waive regression" "$OUT"

# ---------- the waiver alone: the tick's plan reader (lib/units.sh) takes it as the regression's line (AC-18.4) ----------
# A run whose regression was never run and is waived: the judge reads it covered, so the tick must not hold the
# integrate row on a `proof:regression` read only a `proved: kind=regression` line could meet.
ow_plan 7 "$(ck_reads "$OW_D")"
poke "$ROW" waive regression '1'
expect_eq "OW-9 precondition: with no regression proof, the user's waive regression '1' is admitted (exit 0)" "0" "$RC"
poke "$ROW" current 8
expect_eq "OW-9b …and the real current 8 is admitted on it (exit 0), the plan at current: 8" "0|8" "$RC|$(sed -n 's/^current: //p' "$POW")"
forget_digest "$ROW"
poke "$ROW" tick
expect_contains "OW-9c precondition: the tick holds the integrate row on its approvals (the extractor reads real output)" "poker: WAIT T3 " "$(ow_wait)"
expect_absent "OW-9d AC-18.4 …and not on the regression, which the waiver answers (OW-3 is the positive)" "proof:regression" "$(ow_wait)"
POKE_BOUND="$OW_BOUND_WAS"

finish
