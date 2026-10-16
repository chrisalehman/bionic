#!/bin/bash
# Tests for hooks/session-poker.sh — shard 5: the sections wave-38 adds (§CHECK).
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
. "$(dirname "$0")/lib/floor-fixture.sh"

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
expect_contains "CK-7r-b …refused by the judge, naming the owed suite" "$(printf 'floor\towed\ta.test.sh')" "$CK_OUT"
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

finish
