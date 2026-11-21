#!/bin/bash
# Tests for hooks/session-poker.sh — shard 5: §CHECK, §ROUNDS, §EARLY-TICK, §ORDER, §QUIET-LANDING,
# §NOTREADY, §STEP, §TSENTENCE, §CAP, §OWED, §EXEMPT, §REGISTRY, §APPROVED-BY, §PARTS, §START.
#
# THE SUITE IS SHARDS. Its design, hermetic posture and clock discipline are
# in tests/session-poker.test.sh's header; the sandbox and shared fixture builders are tests/session-poker.prelude.sh.
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
. "$(dirname "$0")/lib/plan-fixture.sh"

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
# `current <N> --check` (N in 5..8) runs the advance's own path up to the swap, through the real gate and the same
# `cur7_judge <N>`, prints `would advance` or `would refuse` above the refusal text, and writes nothing.
# FIXTURE FIDELITY: §CUR7's world (session-poker-4): a real repository on `wave/01-fixture` with two
# suites and lib/x.sh, base B and a code commit C; the run at 15 a double wave plan's text stands for, which
# the real gate admits at Steps 5 through 7, bound to this session: plan_fixture's page at double rigor and
# base B, its log the fixture's events, then the text's proofs in the production writer's shape
# (`proof_line`, `proof_floor_line`) appended as their events (`sp_fact`), then its criterion's proof. Every move is
# the real verb; each fixture is rebuilt before the advance runs.
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
PCK="$RCK/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
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
ck_plan() {  # <current> <proof lines> [<row>...] -> PCK, the run at 15 those proofs stand in, bound to this session
  rm -rf "${PCK%/*}" "$RCK/.bionic/docs/record/wave-01-fixture"
  local cur="$1" proofs="$2" l; shift 2
  plan_fixture --current "$cur" "$PCK" wave "$@" > /dev/null
  awk -v b="$CK_B" '/^rigor: /{ $0 = "rigor: double" } /^base-sha: /{ print "base-sha: " b; print "adrs: none — no decision this run"; next } { print }' \
    "$PCK" > "$PCK.t" && mv "$PCK.t" "$PCK"
  printf '%s\n' "$proofs" | while IFS= read -r l; do [ -z "$l" ] || sp_fact "$PCK" "$l"; done
  printf 'run/v1|ev=proof|ac=AC-1.1|evidence=record/generic-evidence.md|at=2026-10-12T13:00:00Z\n' >> "$(plan_fixture_log "$PCK")"
  seal_fixture "$PCK"
  bind_marker "$RCK" "$PCK"
}
ck_tree() {  # -> one cksum line per file in the fixture repository outside .git: what a write would change
  ( cd "$RCK" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do cksum "$f"; done )
}
ck_unpid() {  # [<text>] (else stdin) -> the text with each plan copy's process suffix (.current.<pid>) read as <pid>
  if [ $# -gt 0 ]; then printf '%s\n' "$1" | ck_unpid; return; fi
  sed -E 's/\.current\.[0-9]+/.current.<pid>/g'
}
CK_GOOD="$(ck_floor "$CK_C")
$(ck_reads "$CK_C")"

# ck_case <label> <N> <current> <want rc> <proof lines> -> the check on a fresh fixture,
# then the advance on a fresh fixture of the same bytes; asserts both exit <want>, the check's first line,
# that the check wrote nothing (the plan by cmp, the whole tree by cksum), and that a refusal's text is the
# advance's own. Leaves CK_RC/CK_OUT (the check) and AD_RC/AD_OUT (the advance).
ck_case() {
  local label="$1" n="$2" cur="$3" want="$4" proofs="$5" verdict
  ck_plan "$cur" "$proofs"; cp "$PCK" "$TMPROOT/ck-before"; ck_tree > "$TMPROOT/ck-tree-before"
  poke "$RCK" current "$n" --check; CK_RC="$RC"; CK_OUT="$OUT"
  ck_tree > "$TMPROOT/ck-tree-after"; cp "$PCK" "$TMPROOT/ck-after"
  ck_plan "$cur" "$proofs"
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
    expect_eq "$label — …the advance appended step $n, the plan byte-identical (the fixture is one the advance takes)" "n=$n|same" \
      "$(bash "$BIONIC_SCRIPTS_DIR/payload/scripts/reader.sh" "$PCK" step | head -1)|$(cmp -s "$TMPROOT/ck-before" "$PCK" && echo same)"
  else
    expect_true "$label — …the advance left the plan byte-identical (cmp)" cmp -s "$TMPROOT/ck-before" "$PCK"
    expect_contains "$label — …the advance refused in words (REFUSED)" "REFUSED" "$AD_OUT"
    expect_eq "$label — …and the check's refusal text under its verdict is the advance's, line for line" \
      "$(ck_unpid "$AD_OUT")" "$(printf '%s\n' "$CK_OUT" | tail -n +2 | ck_unpid)"
  fi
}
expect_regex "CK-0 precondition: the working branch's head is C, a 40-hex commit" '^[0-9a-f]{40}$' "$CK_C"

# ---------- N=5: the dry commit at Step 5 admits it, or refuses a run whose log holds no regression proof ----------
ck_case "CK-5g current 5 from 4, every fact the gate asks for held" 5 4 0 "$CK_GOOD"
ck_case "CK-5r current 5 from 4, the run holding no regression proof" 5 4 1 "$(ck_reads "$CK_C")"
expect_contains "CK-5r-b …refused by the dry commit, in the gate's words" "Step 5's regression" "$CK_OUT"

# ---------- N=6: the dry commit at Step 6 admits it, or the gate refuses a question whose newest reading failed ----------
CK_FAILREAD="$(ck_floor "$CK_C")
$(ck_reads "$CK_C" fail)"
ck_case "CK-6g current 6 from 5, every fact the gate asks for held" 6 5 0 "$CK_GOOD"
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
  "waive:adversarial" "$( ( cd "$RCK" && CLAUDE_CODE_SESSION_ID="$SID" bash -c '. "$1/owed.sh" && owed_lines' _ "${BIONIC_HOOKS_DIR}/../payload/scripts/lib" ) 2>/dev/null)"
ck_case "CK-8r2 current 8 from 7, the floor one commit behind the head" 8 7 1 "$(ck_floor "$CK_B")
$(ck_reads "$CK_C")"
expect_contains "CK-8r2-b …refused by the judge, naming the commit no run proves (the floor owes no suite: unproved, never owed)" \
  "$(printf 'regression\tunproved\tred at %.8s, 1 landing before this head; commit %.12s (no landing row) is not proved: ' "$CK_B" "$CK_C")" "$CK_OUT"

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
section "§ROUNDS: decisions put appends a put round to the run's log and decisions rule closes its ask, so the decision is owed from its put to its ruling; each put prints what an hour's wait moves, from the tasks that read it and the longest chain"
# ============================================================
# A put opens a round and the next ruling of the same number closes it; a ruling with no put open is a round of its
# own, the shape of a ledger written before puts. The wait line reads the tasks whose deps cell names the decision
# as an approval and whether any is on the longest open chain. FIXTURE FIDELITY: a real repository, s34_plan's
# plan shape at 15, T1 landed in its log, each ruling given by the verb in the session whose transcript it reads.
# fails-when: a put opens no ask, or the verb's ruling leaves it open; the wait line is absent, or reads the same whether
# its task is on the chain.
RW="$(make_repo rounds)"; PW="$(s34_plan "$RW" 4)"
RW_L="$RW/.bionic/docs/record/wave-01-fixture/design-ledger.md"
/usr/bin/grep -Ev '[|]row=T[25][|]' "${RW_L%/*}/run.log" > "$RW_L.t"; mv "$RW_L.t" "${RW_L%/*}/run.log"   # T1 landed, no other row launched
rw_table() {  # <the side task's size> -> the task table: a side task waits on one decision; the last on another and on the long one
  awk -v s="$1" '/^## Tasks/ { print; print ""; print "| id | step | kind | task | deps | size | serves | Files | artifact |"
    print "|---|---|---|---|---|---|---|---|---|"
    print "| T1 | 4 | build | the first | — | 30 | REQ-1 | a.sh | — |"
    print "| T2 | 4 | build | the side | approval:D7 | " s " | REQ-1 | b.sh | — |"
    print "| T3 | 4 | build | the long | — | 200 | REQ-1 | c.sh | — |"
    print "| T4 | 4 | build | the last | T3, approval:D8 | 100 | REQ-1 | d.sh | — |"
    print ""; skip = 1; next } skip && /^## / { skip = 0 } !skip' "$PW" > "$PW.t" && mv "$PW.t" "$PW"
}
rw_table 30
printf '# design ledger\n\n## Δ0 — D1 ruled "1" (Dana Fixture 2026-10-05): the frame holds\n' > "$RW_L"
RW_T="$CLAUDE_CONFIG_DIR/projects/$(cd "$RW" && pwd -P | sed 's/[^a-zA-Z0-9]/-/g')/$SID.jsonl"; mkdir -p "${RW_T%/*}" "$RW/.bionic/tmp"; : > "$RW/.bionic/tmp/loaded-$SID.state"
jq -nc '{type:"user",isSidechain:false,userType:"external",message:{role:"user",content:"carry on"}}' > "$RW_T"
rw_rule() { poke "$RW" decisions rule D3 "$1"; }
rw_led() { bash "$BIONIC_SCRIPTS_DIR/payload/scripts/reader.sh" "$PW" ledger "$@"; }
rw_asks() { bash "$BIONIC_SCRIPTS_DIR/payload/scripts/reader.sh" "$PW" asks | sed -n 's/.*|key=\(decide:D[0-9]*\)|.*/\1/p' | tr '\n' ' '; }   # open on the register
poke "$RW" decisions put D3 'the third'
expect_eq "RD-1 decisions put exits 0 on the bound run" "0" "$RC"
expect_eq "RD-1b …and appends one put round for it to the run's log, the ledger unchanged" "1|2" "$(rw_led D3 | grep -c '|verb=put|')|$(grep -c . "$RW_L")"
RD_PUT="$(rw_asks)"
rw_rule 1; RD_RULED="$(rw_asks)"
poke "$RW" decisions put D3 'the third, again'; RD_AGAIN="$(rw_asks)"; rw_rule 2
poke "$RW" decisions put D3 'the third, once more'; rw_rule 3; poke "$RW" decisions put D2 'the second'
expect_eq "RD-2 a put opens its ask on the register, the verb's ruling closes it, and a second put opens it again" "decide:D3 ||decide:D3 " \
  "$RD_PUT|$RD_RULED|$RD_AGAIN"
poke "$RW" decisions
expect_contains "RD-4 the register still lists the rulings" 'D3 · "3" · orchestrator' "$OUT"
expect_absent "RD-4b …and no put (RD-4 read the same output)" " put" "$OUT"
poke "$RW" decisions put 7 'no number'
expect_eq "RD-5 a put that names no D<n> is refused, no round written" "1|4" "$RC|$(rw_led | grep -c '|verb=put|')"
poke "$RW" decisions put D8 'on the chain'; RW_ON="$(printf '%s\n' "$OUT" | grep '^wait: ')"
poke "$RW" decisions put D7 'off the chain'; RW_OFF="$(printf '%s\n' "$OUT" | grep '^wait: ')"
poke "$RW" decisions put D9 'read by none'; RW_NONE="$(printf '%s\n' "$OUT" | grep '^wait: ')"
expect_contains "WT-1b …and names that task" "T4" "$RW_ON"
expect_contains "WT-3 no task reads it: nothing moves" "nothing moves" "$RW_NONE"
expect_true "WT-4 the put round carries its wait line (WT-1 read it non-empty)" \
  bash -c '[ -n "$1" ] && grep -qF "|wait=$1|" <<< "$2"' _ "${RW_ON#wait: }" "$(rw_led D8)"
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
# FIXTURE FIDELITY: §CHECK's world and run at 15 at Step 8, its Tasks rows T1 landed and the integrate row T3 waiting
# on the two approvals. The red fact is a header naming no Step-7 document (no adrs: line), a refusal no default of
# the card settles, so `current 7 --check` refuses while `current 6 --check` holds.
# fails-when: the tick stays silent while a fact fails; it says CARD-EARLY on a settled run, or with no open
# integrate row; its line is not the card's own.
ET_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
et_plan() {  # <proof lines> <integrate status> [no-document] -> PCK at current: 8, T1 landed and the integrate row T3, bound
  ck_plan 8 "$1" '| T1 | 4 | build | the x writer | implementor | — | | 30 | REQ-1 | lib/x.sh | — | — | landed |' \
    "| T3 | 8 | integrate | merge into main | orchestrator | approval:release, approval:merge | | 10 | REQ-1 | — | — | — | $2 |"
  [ -z "${3:-}" ] || { /usr/bin/grep -v '^adrs: ' "$PCK" > "$PCK.t" && mv "$PCK.t" "$PCK"; seal_fixture "$PCK"; }
  new_roster "$RCK"
}
ET_CARD="${BIONIC_HOOKS_DIR}/../payload/scripts/card.sh"
et_plan "$CK_GOOD" pending no-document
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
et_plan "$CK_GOOD" landed no-document
forget_digest "$RCK"
poke "$RCK" tick
expect_contains "ET-3 with no open integrate row the tick still answers" "poker:" "$OUT"
expect_absent "ET-3b …and says no CARD-EARLY, the red check notwithstanding" "CARD-EARLY" "$OUT"
POKE_BOUND="$ET_BOUND_WAS"

# ============================================================
section "§ORDER: the tick orders dispatch — FILL offers the longest remaining chain first, the gate line prints the width the gate answers each open landing, and SPLIT is a decision line only while width idles (wave-38 T7; REQ-6 AC-6.5; D22)"
# ============================================================
# The tick offers ready rows longest remaining chain first, and offers a split of a row as its SPLIT decision line with
# its reason when width idles; the gate answers width to the oldest active landing and 0 to the younger ones. A row's
# remaining chain is its size plus the heaviest path of open rows waiting on it, transitively (the `f` of
# lib/units.sh `units_chain`, which the CHAIN line prints for the whole graph); ties go by row id. The ready set's
# membership is unchanged: only its order, and so which rows the writer gap's trim keeps.
# FIXTURE FIDELITY: s47_plan's table at 15, each link a dep: two chains, T1 (10) → T2 (10) = 20 and T3 (30) → T4 (40) → T5 (50)
# = 120, and T6 (20) alone, tying T1 at 20. Table order offers T1 first; chain order offers T3. The leases are
# opened by the gate's own writer (`gate_landing_open`), carried by this test's live process, at planted ages.
# fails-when: FILL names T1 ahead of T3; the writer gap of one keeps T1; the gate line names no widths, names a
# younger landing ahead of an older, or answers a younger landing more than 0; SPLIT? stays on the CHAIN line, or the
# SPLIT line prints while the fill is full.
OR_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib"
ROR="$(make_repo order)"; new_roster "$ROR"
or_plan() {  # <writers> -> the fixture plan at 15, each chain's link a dep on the row before it
  s47_plan "$ROR" "$1" \
    "| T1 | 4 | build | the short chain's head | implementor | — | 10 | REQ-x | payload/a.sh | pending | |" \
    "| T2 | 4 | build | the short chain's tail | implementor | T1 | 10 | REQ-x | payload/a2.sh | pending | |" \
    "| T3 | 4 | build | the long chain's head | implementor | — | 30 | REQ-x | payload/b.sh | pending | |" \
    "| T4 | 4 | build | the long chain's middle | implementor | T3 | 40 | REQ-x | payload/c.sh | pending | |" \
    "| T5 | 4 | build | the long chain's tail | implementor | T4 | 50 | REQ-x | payload/d.sh | pending | |" \
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
expect_eq "OR-7b precondition: the gate answers the oldest, LC, 2 by hand (8 cores at share 80 less the default reserve of 1 is 5.4; a load of 1.0 plus 1.61 a run: 2.61 and 4.22 fit, 5.83 does not) and the younger LB 0" \
  "2|0" "$OR_N|$(or_ask or:w01:LB)"
forget_digest "$ROR"; poke_pressure "$ROR" 8192 1.0 tick
expect_eq "OR-8 AC-6.5 the gate line prints each open landing in age order with the gate's answer: the oldest its width, the others 0" \
  "or:w01:LC=2,or:w01:LB=0,or:w01:LA=0" "$(or_gate)"
expect_regex "OR-8b …on the one gate line, after room=" '^poker: gate share=.* room=(yes|no) widths: or:w01:LC=2,' "$(s47_lines gate)"
# A gate read under a tab IFS (bash runs a here-string's command substitution under a builtin's temporary IFS)
# compares each carrier's start as any other read does, so the three leases stay held and LC keeps its width.
OR_TAB="$( . "$OR_LIB/gate.sh" && IFS='	' read -r w <<< "$(gate_width_ask or:w01:LC)" && printf '%s' "$w" )"
expect_eq "OR-8c a gate read under a tab IFS answers LC its width and keeps all three leases" \
  "2|3" "$OR_TAB|$(ls "$BIONIC_GATE_DIR/leases/" | /usr/bin/grep -c '\.lease$' | tr -d ' ')"
# LC's carrier leaves it WAITING: the lease is kept but orders no one, so LB is the oldest the gate answers.
bash -c '. "$1/gate.sh" && gate_landing_leave "$2" "$3"' _ "$OR_LIB" or:w01:LC "$$"
forget_digest "$ROR"; poke_pressure "$ROR" 8192 1.0 tick
expect_eq "OR-9 a lease left WAITING drops off the line, and the next oldest, LB, is answered its width" \
  "or:w01:LB=2,or:w01:LA=0" "$(or_gate)"
rm -rf "$BIONIC_GATE_DIR/leases"

# ============================================================
section "§QUIET-LANDING: the quiet check reads the row's live landing carrier and the gate's open request for its agent before the mtimes (wave-39 T22; REQ-16 AC-16.1; D21)"
# ============================================================
# A writer blocked in a foreground `ready --within 1790` touches neither its progress file nor its transcript for up to
# 30 minutes, so both NOTIFY arms ask first whether the row's landing carrier lives or the gate holds an open request
# for the row's agent; either makes the row ACTIVE. Only then the mtimes: a dead silent row still NOTIFYs.
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
# A row that should wait is made not ready by a fact of the run the tick judges: a wait on a decision no approval
# rules, a wait on a still-open row, or the user's order in the run's log.
# FIXTURE FIDELITY: s47_plan's run at 15, approved at step 4; T2 is launched, so it is still open; the Stop is the
# shipped hooks/stop.sh on an ordinary turn of this session.
# fails-when: FILL names T1 or T3; either prints no WAIT; the wall refuses a turn on which no row is ready;
# an open order leaves a FILL; the tick prints a decline.
NR_REC=".bionic/docs/record/wave-01-fixture/T2-held.md"
RNR="$(make_repo notready)"; new_roster "$RNR"
NR_P="$(s47_plan "$RNR" 8 \
  "| T1 | 4 | build | reads a ruling | implementor | approval:D3 | 10 | REQ-x | payload/a.sh | pending | |" \
  "| T2 | 4 | build | the open row | implementor | — | 10 | REQ-x | $NR_REC, payload/b.sh | active | |" \
  "| T3 | 4 | build | waits on T2 | implementor | T2 | 10 | REQ-x | payload/c.sh | pending | |" \
  "| T4 | 4 | build | waits on nothing | implementor | — | 10 | REQ-x | payload/d.sh | pending | |")"
NR_LOG="$RNR/.bionic/docs/record/wave-01-fixture/run.log"
nr_led() { /usr/bin/grep '^run/v1|ev=stop|' "$NR_LOG" 2>/dev/null | tail -1; }
nr_fill() { printf '%s\n' "$OUT" | /usr/bin/grep '^poker: FILL T'; }   # -> the FILL line, never its "FILL —" sentence
poke_pressure "$RNR" 8192 1.0 tick
expect_eq "NR-0 the tick over the table exits 0" "0" "$RC"
expect_eq "NR-1 FILL names only the row that waits on nothing" "poker: FILL T4" "$(nr_fill)"
expect_contains "NR-2 the row reading the unruled D3 prints its WAIT, naming the read" "poker: WAIT T1 — approval:D3" "$OUT"
expect_contains "NR-3 the row waiting on the open T2 prints its WAIT, naming it" "poker: WAIT T3 — waits for T2 (active)" "$OUT"
expect_absent "NR-4 …and the tick prints no decline (NR-1 read this same output)" "decline" "$OUT"
s31_stop "$RNR" "$(s31_transcript "$RNR" "carry on")"
expect_eq "NR-5 the control: T4 ready and nothing launched, the wall refuses the turn" "duty" "$(s31_decision)"
expect_contains "NR-5b …naming T4 alone" "ready with room: T4 " "$(s31_reason)"

# T4 launched: every row left waits, the tick offers none, and the wall ends the turn.
printf 'run/v1|ev=dispatch|row=T4|name=implementor|at=2026-10-04T00:30:00Z\n' >> "$NR_LOG"
forget_digest "$RNR"; poke_pressure "$RNR" 8192 1.0 tick
expect_contains "NR-6 precondition: the waits still print" "poker: WAIT T1 — approval:D3" "$OUT"
expect_eq "NR-6b …and no row is offered" "" "$(nr_fill)"
s31_stop "$RNR" "$(s31_transcript "$RNR" "carry on")"
expect_contains "NR-7 meta: the wall read the turn, its stop event is there" "run/v1|ev=stop|" "$(nr_led)"
expect_contains "NR-7b …and no row was ready" "|ready=|" "$(nr_led)"
expect_eq "NR-7c the wall ends the turn" "" "$(s31_decision)"

# The user's order: T4's launch taken back, an open order in the run's log, so nothing is offered; the
# order lifted, T4 is offered again.
printf 'run/v1|ev=%s|at=%s\n' 'cancel|of=dispatch|row=T4|name=implementor' 2026-10-19T23:59:00Z 'order|act=given|said=hold the fleet while I read' 2026-10-20T00:00:00Z >> "$NR_LOG"
forget_digest "$RNR"; poke_pressure "$RNR" 8192 1.0 tick
expect_contains "NR-8 under an open order the tick says so, quoting the words" \
  "no FILL — an order of the user stands: given 2026-10-20T00:00:00Z \"hold the fleet while I read\"" "$OUT"
expect_eq "NR-8b …and offers no row" "" "$(nr_fill)"
s31_stop "$RNR" "$(s31_transcript "$RNR" "carry on")"
expect_eq "NR-8c …and the wall ends the turn" "" "$(s31_decision)"
printf 'run/v1|ev=order|act=lifted|said=hold the fleet while I read|at=2026-10-20T00:30:00Z\n' >> "$NR_LOG"
forget_digest "$RNR"; poke_pressure "$RNR" 8192 1.0 tick
expect_eq "NR-9 the control: the order lifted, T4 is offered again" "poker: FILL T4" "$(nr_fill)"

# ============================================================
section "§STEP: the approval line alone readies nothing: a plan at current: 2 that carries approved-by: offers no FILL and the wall ends the turn; at current: 4 the same table fills"
# ============================================================
# A row's approval:plan read is met only while the plan is at current: 4 or later. A plan approved and still at
# Step 2 has a ratified table nobody has started, and its rows wait for the step, in the tick, the wall and the
# table reader alike.
# FIXTURE FIDELITY: s47_plan's one-row run at 15, its step moved by a step event in its log; the Stop is the shipped
# hooks/stop.sh; the table reader is lib/units.sh `units_ready`, sourced from the shipped tree.
# fails-when: at current: 2 the tick prints FILL, the wall refuses, or units_ready names T1; at current: 4 any of
# the three disagrees.
RST="$(make_repo step)"; new_roster "$RST"
ST_P="$(s47_plan "$RST" 8 "| T1 | 4 | build | ready from step 4 | implementor | — | 10 | REQ-x | payload/a.sh | pending | |")"
st_at() { bash -c '. "$1/proof.sh" && proof_step_event "$2" "$3"' _ "${BIONIC_HOOKS_DIR}/../payload/scripts/lib" "$ST_P" "$1"; }
st_ready() { bash -c '. "$1/units.sh" && units_ready "$2" 4' _ "${BIONIC_HOOKS_DIR}/../payload/scripts/lib" "$ST_P" 2>/dev/null; }
st_at 2
expect_eq "ST-0 precondition: the run is at step 2" "n=2" "$(bash "$BIONIC_SCRIPTS_DIR/payload/scripts/reader.sh" "$ST_P" step | head -1)"
expect_contains "ST-0b precondition: …and its log carries the plan's approval" "|ev=approval|key=step3|" "$(cat "$(plan_fixture_log "$ST_P")")"
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
expect_eq "ST-5 …the wall refuses the turn that left it" "duty" "$(s31_decision)"
expect_eq "ST-6 …and the table reader names T1" "T1" "$(st_ready)"

# ============================================================
# ============================================================
section "§TSENTENCE: task-add refuses a Tasks cell with no sentence after its title, or with a backticked one, in the Step-3 card's words"
# ============================================================
# A Tasks cell opens on its title, then one plain sentence saying what the row makes true; the Step-3 card prints the
# sentence under the row and refuses a cell without one. task-add, the verb that writes the cell, refuses it where it is typed,
# through the card's own check (`card.sh task-cell`), so the words are the card's and the plan is left as it was.
# FIXTURE FIDELITY: s34's plan at current: 5, bound to this session; every write is the real verb.
# fails-when: a verb writes a cell the card would refuse, refuses a cell the card would draw, says other words than the
# card's check, or changes a byte of the plan when it refuses.
TS_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
TS_CARD="${BIONIC_HOOKS_DIR}/../payload/scripts/card.sh"
RTS="$(make_repo tsentence)"; ( cd "$RTS" && git commit -q --allow-empty -m init )
PTS="$(s34_plan "$RTS" 5)"
ts_card_says() {  # <id> <cell> -> what the card's check prints for that cell
  bash "$TS_CARD" task-cell "$1" "$2" 2>&1 >/dev/null
}
ts_row() {  # <id> -> the plan's ## Tasks row for <id>
  /usr/bin/grep "^| $1 |" "$PTS"
}

ta_add "$RTS" T7 7 doc 'Release the fixture. The fixture ships as one release. The entry names `CHANGELOG.md`.' bionic:implementor 'T5' 30 REQ-1 '—'
expect_eq "TSENT-1 task-add writes a cell that opens on its title and a plain sentence (exit 0)" "0" "$RC"
expect_contains "TSENT-1b …the cell as typed, its detail's backtick too" \
  '| T7 | 7 | doc | Release the fixture. The fixture ships as one release. The entry names `CHANGELOG.md`. |' "$(ts_row T7)"

ta_add "$RTS" T8 7 doc 'Release the fixture.' bionic:implementor 'T5' 30 REQ-1 '—'
TS_WORDS="$(ts_card_says T8 'Release the fixture.')"
expect_eq "TSENT-2 precondition: the card's check refuses that cell with its line" \
  "REFUSED — task T8: no sentence after its title" "$TS_WORDS"
expect_eq "TSENT-2a task-add of a cell with no sentence is refused (exit 1)" "1" "$RC"
expect_contains "TSENT-2b …in the card's words" "$TS_WORDS" "$OUT"
expect_eq "TSENT-2c …and the plan is unchanged" "$(cat "$TMPROOT/s42-before")" "$(cat "$PTS")"

ta_add "$RTS" T8 7 doc 'Release the fixture. The fixture ships `v2` as one release.' bionic:implementor 'T5' 30 REQ-1 '—'
TS_WORDS="$(ts_card_says T8 'Release the fixture. The fixture ships `v2` as one release.')"
expect_eq "TSENT-3 precondition: the card's check refuses that cell with its line" \
  'REFUSED — task T8: the sentence carries a backtick: The fixture ships `v2` as one release.' "$TS_WORDS"
expect_eq "TSENT-3a task-add of a cell whose sentence carries a backtick is refused (exit 1)" "1" "$RC"
expect_contains "TSENT-3b …in the card's words" "$TS_WORDS" "$OUT"
expect_eq "TSENT-3c …and the plan is unchanged" "$(cat "$TMPROOT/s42-before")" "$(cat "$PTS")"

POKE_BOUND="$TS_BOUND_WAS"

# ============================================================
section "§CAP: task-add refuses a title over the card's cap where it is typed, in the card's words, the born suffix counted"
# ============================================================
# The Step-3 card refuses a title of more than 30 columns. A row added or reset with one landed in the plan and
# reddened the card at the next draw, a step away from the hand that typed it, so the verb that writes the cell
# measure it first, through the card's own check (`card.sh task-cell`): the words are the card's, every refused cell
# is named in the one refusal, and the plan is left as it was. The whole cell is judged as it will be written, the
# ` · born: …` tag task-add appends included, so no tag can push a title the verb admitted over the cap.
# FIXTURE FIDELITY: s34's plan at current: 5, bound to this session; every write is the real verb.
# fails-when: a verb writes a title the card would refuse, refuses a title the card would draw, says other words than
# the card's check, names only one of two refused cells, or changes a byte of the plan when it refuses.
CP_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
CP_CARD="${BIONIC_HOOKS_DIR}/../payload/scripts/card.sh"
RCP="$(make_repo cap)"; ( cd "$RCP" && git commit -q --allow-empty -m init )
PCP="$(s34_plan "$RCP" 5)"
CP_T30="Thirty columns of title, no more"; CP_T30="${CP_T30:0:30}"
CP_T31="${CP_T30}x"
cp_says() {  # <id> <cell> -> what the card's check prints for that cell
  bash "$CP_CARD" task-cell "$1" "$2" 2>&1 >/dev/null
}
cp_row() { /usr/bin/grep "^| $1 |" "$PCP"; }
expect_eq "CAP-0 precondition: the boundary title is 30 columns and the over-long one 31" "30|31" "${#CP_T30}|${#CP_T31}"

ta_add "$RCP" T7 7 doc "${CP_T30}. The fixture ships as one release." bionic:implementor 'T5' 30 REQ-1 '—'
expect_eq "CAP-1 task-add writes a title of exactly 30 columns (exit 0)" "0" "$RC"
expect_contains "CAP-1b …the cell as typed" "| T7 | 7 | doc | ${CP_T30}. The fixture ships as one release. |" "$(cp_row T7)"

CP_CELL="${CP_T31}. The fixture ships as one release."
CP_WORDS="$(cp_says T8 "$CP_CELL")"
expect_eq "CAP-2 precondition: the card's check refuses that cell with the title's length, the cap and the title" \
  "REFUSED — task T8: title is 31 characters, the cap is 30: ${CP_T31}" "$CP_WORDS"
ta_add "$RCP" T8 7 doc "$CP_CELL" bionic:implementor 'T5' 30 REQ-1 '—'
expect_eq "CAP-2a task-add of a 31-column title is refused (exit 1)" "1" "$RC"
expect_contains "CAP-2b …in the card's words" "$CP_WORDS" "$OUT"
expect_eq "CAP-2c …and the plan is unchanged" "$(cat "$TMPROOT/s42-before")" "$(cat "$PCP")"

# The tag the verb appends is part of the cell it judges: a title that fits is admitted with it, one that does not is refused with it.
ta_add "$RCP" T8 7 doc "$CP_CELL" bionic:implementor 'T5' 30 REQ-1 '—' --born 'review S2 on'
expect_eq "CAP-3 task-add of a 31-column title with a born tag is refused all the same (exit 1)" "1" "$RC"
expect_contains "CAP-3b …in the card's words, the title whole" "$CP_WORDS" "$OUT"
expect_eq "CAP-3c …and the plan is unchanged" "$(cat "$TMPROOT/s42-before")" "$(cat "$PCP")"
ta_add "$RCP" T8 7 doc "${CP_T30}. The fixture ships as one release." bionic:implementor 'T5' 30 REQ-1 '—' --born 'review S2 on'
expect_eq "CAP-3d control: the same cell with a 30-column title and the born tag is admitted (exit 0)" "0" "$RC"
CP_BORN_LAST="$(printf '%s\n' "$OUT" | tail -1)"
expect_contains "CAP-3e …with the tag written after the sentence" "| T8 | 7 | doc | ${CP_T30}. The fixture ships as one release. · born: review" "$(cp_row T8)"


# ============================================================
section "§OWED: task-add ends on one line naming the task-list entry the turn now owes, by the row's title"
# ============================================================
# A row added to the plan is a row the harness's task list lacks, and the entries after it are recreated to keep the
# order. The rule is stated where the act happens: the verb's last line names the entry, as the task list names it
# (`<step>/<id>: <title>`), so no step text carries it.
# fails-when: task-add ends on anything but that line, names the entry by anything but the row's title, or says it
# of a refusal.
ta_add "$RCP" T9 7 doc 'Make the entry. The entry is owed the same turn.' bionic:implementor 'T5' 30 REQ-1 '—'
expect_eq "OWED-1 task-add of a row exits 0 and ends on one line naming the task-list entry by its title" \
  "0|poker: task-add — owed: create the task-list entry 7/T9: Make the entry at the end of the list." "$RC|$(printf '%s\n' "$OUT" | tail -1)"
expect_eq "OWED-1b …the line is said once" "1" "$(printf '%s\n' "$OUT" | /usr/bin/grep -c 'owed: create the task-list entry')"
expect_eq "OWED-2 a born row (CAP-3d's T8) ends on the same line, its title without the tag" \
  "poker: task-add — owed: create the task-list entry 7/T8: ${CP_T30} at the end of the list." "$CP_BORN_LAST"
ta_add "$RCP" T11 7 doc "${CP_T31}. Over the cap." bionic:implementor 'T5' 30 REQ-1 '—'
expect_eq "OWED-3 a refused task-add says nothing is owed" "1|0" "$RC|$(printf '%s\n' "$OUT" | /usr/bin/grep -c 'owed:')"
POKE_BOUND="$CP_BOUND_WAS"
# ============================================================
section "§EXEMPT: a review-born row inside fix-policy: is exempt from fix-cap:, a promoted or carried one counts, and task-add says which count it applied"
# ============================================================
# A defect the wave made, the wave fixes, so the cap counts only the rows a review adds beyond them: a row rated inside
# fix-policy: (default S1,S2-on) lands however many there are; a finding the person moved to fix from outside it, and a
# finding carried in from another plan's record directory, count against fix-cap:.
# FIXTURE FIDELITY: s34's plan at current: 4 with `fix-cap: 2` in its frontmatter, as Step 3 writes the field; two
# readings registered in the shape `proof-add review` writes, their records holding findings in the reader's shape, one
# record this plan's own and one another plan's; the person's moves to fix planted as `finding-move` writes them; every
# row is the real verb's.
# fails-when: a third row inside the policy is refused at fix-cap: 2; a promoted or a carried row lands uncounted; a
# third counted row lands; the refusal names neither the counted and exempt figures nor its exit; the line task-add
# prints names the wrong count, or none.
EX_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
REX="$(make_repo exempt)"; ( cd "$REX" && git commit -q --allow-empty -m init )
PEX="$(s34_plan "$REX" 4)"; EX_H="$(git -C "$REX" rev-parse HEAD)"
EX_OWN="record/wave-01-fixture/rev.md"; EX_CARRIED="record/wave-00-prior/critic.md"
mkdir -p "$REX/.bionic/docs/record/wave-01-fixture" "$REX/.bionic/docs/record/wave-00-prior"
printf 'reviewed: %s..%s\nquestion: structure\nresult: fail\nscope: piece\n\nfindings: 3\nfinding: 1 S3 on lib/p1.sh:1 the first promoted defect\nfinding: 2 S3 on lib/p2.sh:1 the second promoted defect\nfinding: 3 S3 on lib/p3.sh:1 the third promoted defect\nshown: 1 cat lib/p1.sh\nshown: 2 cat lib/p2.sh\nshown: 3 cat lib/p3.sh\n' \
  "$EX_H" "$EX_H" > "$REX/.bionic/docs/$EX_OWN"
printf 'reviewed: %s..%s\nquestion: adversarial\nresult: fail\nscope: piece\n\nfindings: 1\nfinding: 1 S2 on lib/c1.sh:1 the carried defect\nshown: 1 cat lib/c1.sh\n' \
  "$EX_H" "$EX_H" > "$REX/.bionic/docs/$EX_CARRIED"
awk '{ print } /^rigor: / && !fm { fm = 1; print "fix-cap: 2" }' "$PEX" > "$PEX.n" && mv "$PEX.n" "$PEX"
for ex_r in "$EX_OWN structure w-rev" "$EX_CARRIED adversarial w-adv"; do set -- $ex_r
  sp_fact "$PEX" "proved: kind=review head=$EX_H at=2026-10-20T00:00:00Z evidence=$1 question=$2 reader=$3 result=fail scope=piece"; done
for ex_i in 1 2 3; do
  printf 'run/v1|ev=finding|ref=%s#%s|to=fix|by=Dana|words=fix it in this wave|why=the user ruled it|at=2026-10-20T01:00:00Z\n' "$EX_OWN" "$ex_i"
done >> "$(plan_fixture_log "$PEX")"
ex_add() {  # <id> <files> <born> -> OUT, RC: task-add of a step-4 build row born of <born>
  ta_add "$REX" "$1" 4 build "Fix $1. The defect is gone." bionic:implementor '—' 30 REQ-1 "$2" --born "$3"
}
ex_born_line() { printf '%s\n' "$OUT" | /usr/bin/grep 'is review-born' || :; }
ex_mark() { bash -c '. "$1/units.sh" >/dev/null 2>&1; _units_born_facts "$2"' _ "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib" "$PEX" | awk -F'\t' -v r="$1" '$1 == r { print "born: " $2 ($3 != "" ? " of=" $3 : "") ($4 != "" ? " promoted" : "") }'; }
expect_eq "EX-0 precondition: the plan reads fix-cap: 2 and no fix-policy: (the default, S1,S2-on), and both findings are read" \
  "2||3|1" "$(sed -n 's/^fix-cap: //p' "$PEX")|$(sed -n 's/^fix-policy: //p' "$PEX")|$(/usr/bin/grep -c '^finding: ' "$REX/.bionic/docs/$EX_OWN")|$(/usr/bin/grep -c '^finding: ' "$REX/.bionic/docs/$EX_CARRIED")"

# Inside the policy, the review's own defects land however many there are.
ex_add T6 lib/e6.sh 'review S2 on'
expect_eq "EX-1 the first row born review S2 on lands (exit 0)" "0" "$RC"
expect_contains "EX-1b …and says it was exempt under the policy (AC-1.3)" " · exempt under fix-policy: S1,S2-on" "$(ex_born_line)"
ex_add T7 lib/e7.sh 'review S2 on'
expect_eq "EX-2 the second lands (exit 0)" "0" "$RC"
ex_add T8 lib/e8.sh 'review S2 on'
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
expect_eq "EX-3 the third born review S2 on row lands at fix-cap: 2 (exit 0): inside fix-policy: it is exempt (AC-1.1)" "0" "$RC"
EX_LINE="$(ex_born_line)"
expect_contains "EX-3b …its line ends exempt under fix-policy: S1,S2-on (AC-1.3)" " · exempt under fix-policy: S1,S2-on" "$EX_LINE"
expect_absent "EX-3c …and names no count of the cap for an exempt row (AC-1.3)" "of cap" "$EX_LINE"
expect_eq "EX-3d …its born event carries the plain rating" "born: review S2 on" "$(ex_mark T8)"

# A carried finding and a promoted one count; the third counted row is refused.
ex_add T9 lib/c1.sh "$EX_CARRIED#1"
expect_eq "EX-4 a finding carried from another plan's record lands, counted (exit 0)" "0" "$RC"
expect_contains "EX-4b …its line ends counted 1 of 2 (AC-1.3)" " · counted 1 of 2" "$(ex_born_line)"
expect_eq "EX-4c …its born event names the carried record" "born: review S2 on of=$EX_CARRIED#1" "$(ex_mark T9)"
ex_add T10 lib/p1.sh "$EX_OWN#1"
expect_eq "EX-5 a finding rated S3 on that the person moved to fix lands, counted (exit 0)" "0" "$RC"
expect_contains "EX-5b …its line ends counted 2 of 2 (AC-1.3)" " · counted 2 of 2" "$(ex_born_line)"
expect_eq "EX-5c …its born event says it was promoted" "born: review S3 on of=$EX_OWN#1 promoted" "$(ex_mark T10)"
ex_add T11 lib/p2.sh "$EX_OWN#2"
expect_eq "EX-6 a third counted row, promoted from S3 on, is refused at fix-cap: 2 (exit 1) (AC-1.2)" "1" "$RC"
expect_contains "EX-6b …the refusal names the counted and exempt figures and its exit" \
  "task-add refused — review-born rows: 2 of cap 2 are counted (3 exempt under fix-policy: S1,S2-on); T11 stands in the plan unborn, the person's to remove; this finding goes to the review findings disposition, or the person raises the cap: set fix-cap=3 at the card." "$OUT"
expect_eq "EX-6c …and the plan is unchanged across it" "$(cat "$TMPROOT/s42-before")" "$(cat "$PEX")"
ex_add T11 lib/e11.sh 'review S1 off'
expect_eq "EX-7 control: with the cap full, a row born review S1 off still lands (exit 0): S1 is inside the policy at either reach" "0" "$RC"
expect_contains "EX-7b …exempt" " · exempt under fix-policy: S1,S2-on" "$(ex_born_line)"
POKE_BOUND="$EX_BOUND_WAS"

# ============================================================
section "§REGISTRY: the per-file cap does not count a file every test row must touch, and still counts any other"
# ============================================================
# fails-when: a fourth review-born row touching tests/CENSUS.md is refused as a fourth fix on it, or a fourth row on an
# ordinary shared path is admitted, or its refusal names another path.
RG_WAS="$POKE_BOUND"; POKE_BOUND=180
for RG_I in 1 2 3; do ex_add T2$RG_I "tests/CENSUS.md,lib/r$RG_I.sh,lib/shared.sh" 'review S2 on'; done
ex_add T24 "tests/CENSUS.md,lib/r4.sh" 'review S2 on'
expect_eq "RG-1 a fourth born row touching tests/CENSUS.md, three rows already fixing it, is admitted (exit 0)" "0" "$RC"
ex_add T25 "tests/CENSUS.md,lib/shared.sh" 'review S2 on'
expect_eq "RG-2 control: a fourth on lib/shared.sh, three rows already fixing it, is refused (exit 1)" "1" "$RC"
expect_contains "RG-2b …naming lib/shared.sh and the three rows" "a fourth fix on lib/shared.sh: T21, T22, T23 already fix it" "$OUT"
POKE_BOUND="$RG_WAS"

# ============================================================
section "§APPROVED-BY: approve plan '<reply>' appends the plan's approval the walls read, with the user's words, once (REQ-9 AC-9.2)"
# ============================================================
# The plan's approval is one approval event in the run's log, key step3, which the commit gate reads from Step 4; step0,
# step1 and step2 are the ones the gate at 15 asks at Steps 1 to 3, each closing its own ask at its instant. Each holds the
# git user and the reply as given, a placeholder refused, the plan unwritten, and a second call refused as recorded once.
# FIXTURE FIDELITY: s34's run at 15 at step 3 with its approval taken out of its log, and for AS-4 plan_fixture's run at 15
# at Step 3 with its approval taken out, each bound to this session; the gate is the shipped one (s34_gate); every write is the real verb.
# fails-when: an approval's only giver is the orchestrator's editor; it is given twice; the words differ; a step's is refused;
# one is taken on words no prompt the person typed holds, or on a prompt a program sent (said_as sdk).
AB_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RAB="$(make_repo approved-by)"; ( cd "$RAB" && git commit -q --allow-empty -m init ); git -C "$RAB" config user.name "Dana Fixture"
PAB="$(s34_plan "$RAB" 3)"; L5="$(plan_fixture_log "$PAB")"; /usr/bin/grep -v 'ev=approval' "$L5" > "$L5.t" && mv "$L5.t" "$L5"
ab_k() { /usr/bin/grep "^run/v1|ev=$1" "$RAB/.bionic/docs/record/wave-01-fixture/run.log" 2>/dev/null; }
ab_said() { printf '%s' "$1" | /usr/bin/grep -q "$2" && echo yes || echo no; }   # <text> <words> -> yes when the text holds them
ab_at() { bash -c '. "$1/proof.sh" && proof_step_event "$2" "$3"' _ "${S46_LIB%/*}" "$PAB" "$1"; }
ab_at 3; CLAUDE_CONFIG_DIR="$SAID_CFG" poke "$RAB" approve plan 'TBD'; expect_eq "AB-0b approve plan refuses a placeholder for the user's words (exit 1), appending nothing" "1|0" "$RC|$(ab_k 'approval|key=step3|' | grep -c .)"
CLAUDE_CONFIG_DIR="$SAID_CFG" poke "$RAB" approve plan 'approved, go ahead'; AU="$RC|$(ab_k 'approval|key=step3|' | grep -c .)"
said_as sdk "$RAB" 'approved, go ahead'; CLAUDE_CONFIG_DIR="$SAID_CFG" poke "$RAB" approve plan 'approved, go ahead'; AU="$AU|$RC|$(ab_k 'approval|key=step3|' | grep -c .)|$(ab_said "$OUT" 'stand in no prompt the user typed')"
expect_eq "AU-1 approve plan on words no prompt holds, then on words only a program sent: refused (exit 1) each, nothing appended" "1|0|1|0|yes" "$AU"
said_as typed "$RAB" 'approved, go ahead'; AB_BEFORE="$(cat "$PAB")"; CLAUDE_CONFIG_DIR="$SAID_CFG" poke "$RAB" approve plan 'approved, go ahead'
expect_eq "AB-1 approve plan appends one approval (exit 0), the plan unchanged, and says so" "0|1|yes|yes" "$RC|$(ab_k 'approval|key=step3|' | grep -c .)|$([ "$AB_BEFORE" = "$(cat "$PAB")" ] && echo yes || echo no)|$(ab_said "$OUT" 'approved by Dana Fixture')"
expect_regex "AB-1b …the git user, the reply verbatim, an ISO-UTC instant" '^run/v1\|ev=approval\|key=step3\|by=Dana Fixture\|said=approved, go ahead\|at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$(ab_k 'approval|key=step3|')"
ab_at 3; AB_BEFORE="$(cat "$PAB")"; CLAUDE_CONFIG_DIR="$SAID_CFG" poke "$RAB" approve plan 'approved'
expect_eq "AB-3 a second approve plan is refused (exit 1) as recorded once, the plan unchanged and nothing appended" "1|yes|1|yes" "$RC|$([ "$AB_BEFORE" = "$(cat "$PAB")" ] && echo yes || echo no)|$(ab_k 'approval|key=step3|' | grep -c .)|$(ab_said "$OUT" 'recorded once')"
OWED_ROOT="$RAB" OWED_SID="$SID" OWED_PLAN="$PAB" bash -c '. "$1" && owed_open approve:step1 t q' _ "${S46_LIB%/*}/owed.sh"
CLAUDE_CONFIG_DIR="$SAID_CFG" poke "$RAB" approve step2 'TBD'; AS="$RC|$(ab_k 'approval|key=step2|' | grep -c .)"
CLAUDE_CONFIG_DIR="$SAID_CFG" poke "$RAB" approve step1 'yes, step1 as shown'; AS="$AS|$RC|$(ab_k 'approval|key=step1|' | grep -c .)"
for k in step0 step1 step2; do said_as typed "$RAB" "yes, $k as shown"; CLAUDE_CONFIG_DIR="$SAID_CFG" poke "$RAB" approve "$k" "yes, $k as shown"; AS="$AS|$RC"; done
expect_eq "AS-1 approve refuses a placeholder for step2 and step1 on words no prompt holds, appending nothing, then takes step0, step1 and step2 once typed" "1|0|1|0|0|0|0" "$AS"
AS="$(ab_k 'approval|key=step1|')"; expect_eq "AS-2 …each under its own key, the git user and the reply verbatim, step1's ask closed at its instant" \
  "run/v1|ev=approval|key=step1|by=Dana Fixture|said=yes, step1 as shown|1" "${AS%|at=*}|$(ab_k "ask|key=approve:step1|reply=approve step1|${AS##*|}" | grep -c .)"
CLAUDE_CONFIG_DIR="$SAID_CFG" poke "$RAB" approve step1 'yes again'; expect_eq "AS-3 a second approve step1 is refused as recorded once, nothing appended" "1|1|yes" "$RC|$(ab_k 'approval|key=step1|' | grep -c .)|$(ab_said "$OUT" 'recorded once')"
RAB="$(make_repo approved-15)"; ( cd "$RAB" && git commit -q --allow-empty -m init && git checkout -q -b wave/01-fixture ); git -C "$RAB" config user.name "Dana Fixture"
PAB="$(plan_fixture --current 3 "$RAB/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md" wave)"; bound_marker "$RAB" "$SID" "$PAB"
L5="$(plan_fixture_log "$PAB")"; /usr/bin/grep -v 'ev=approval' "$L5" > "$L5.t" && mv "$L5.t" "$L5"; seal_fixture "$PAB" "$L5"
said_as typed "$RAB" approved; CLAUDE_CONFIG_DIR="$SAID_CFG" poke "$RAB" approve plan 'approved'; AS="$RC|$(ab_k approval | grep -c .)"; printf 'run/v1|ev=step|n=4|at=2026-10-04T00:04:00Z\n' >> "$L5"; seal_fixture "$PAB" "$L5"; s34_gate "$RAB"
expect_eq "AS-4 the plan's approval answers the steps before it: at 15 with none of theirs it is taken, the only one, and a commit at Step 4 admitted" "0|1|0" "$AS|$GATE_RC"
POKE_BOUND="$AB_BOUND_WAS"

# ============================================================
section "§PARTS: the release-entry parts render in the checkout they run from: a row's tree commits on its own branch and the working branch stays put, the working branch's checkout moves it, and the part line names the tree (REQ-12 AC-12.1, AC-12.2)"
# ============================================================
# `known-limits-part <row>` and `reviews-part <row>` render the part into the checkout they run from and commit it on that
# checkout's branch; only the checkout holding the working branch moves it, a checkout on main commits on the working
# branch as before, and the part line names the tree that took the commit.
# FIXTURE FIDELITY: s34_plan's plan, bound to this session, with the working branch and the release in its frontmatter
# as Step 0 writes them; the doc and integrate rows are the table's own shape; the deferral is the person's move to
# defer with its sentence on it, and the waiver `proof_waiver_line`'s, each an event in the run's log. The row's tree is a linked worktree on its own branch cut at the working branch, as
# `spawn-worktree.sh create` makes it; the entry is a plain commit on the working branch.
# fails-when: a verb run from the row's tree commits on the working branch or moves it, leaves the tree's branch or its
# working tree without the part, changes the commit message, or writes no tree= on the part line; the working branch's
# checkout no longer moves its branch; a checkout on main commits on main.
PA_V=9.9.9
PA_S1='The one limit the run defers, stated.'
PA_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib"
pa_lib() { bash -c '. "$1/run.sh" && . "$1/proof.sh" || exit 9; shift; "$@"' _ "$PA_LIB" "$@"; }   # <fn> [args…]
pa_tip() { git -C "$RPA" rev-parse --verify -q "refs/heads/$1"; }   # <branch>
pa_ev() { find "$RPA/.bionic" -name run.log -exec cat {} + 2>/dev/null | /usr/bin/grep "|part=$1|" | tail -1; }   # <part>
pa_has() { /usr/bin/grep -c "^$2" "$1/CHANGELOG.md" 2>/dev/null | tr -d ' '; }   # <checkout> <line start> -> the count in its working tree
RPA="$(make_repo parts)"; RPA="$(cd "$RPA" && pwd -P)"
git -C "$RPA" config user.email t@example.com; git -C "$RPA" config user.name "Dana Fixture"
printf '# Changelog\n\n## %s — 2026-10-25\n\n### The work\n\n- one change\n\n### The landing numbers\n\nthe numbers\n' "$PA_V" > "$RPA/CHANGELOG.md"
( cd "$RPA" && git add CHANGELOG.md && git commit -qm "the entry" && git branch -M main && git checkout -qb wave/01-fixture ) >/dev/null 2>&1
PPA="$(s34_plan "$RPA" 4)"; PA_LOG="$(plan_fixture_log "$PPA")"
awk -v v="$PA_V" 'NR == 1 { print; print "release: " v; next }
  { print }
  /^\| T5 \|/ { print "| T3 | 7 | doc | the entry. The release entry is written. | — | 10 | REQ-1 | CHANGELOG.md | — |"
               print "| T4 | 8 | integrate | the pull request. The run reaches main. | — | 10 | REQ-1 | — | — |" }' \
  "$PPA" > "$PPA.n" && mv "$PPA.n" "$PPA"
PA_H="$(pa_tip wave/01-fixture)"
printf 'run/v1|ev=finding|ref=record/wave-01-fixture/critic.md#1|to=defer|by=Dana Fixture|words=defer it|session=%s|why=out of this run|severity=S3|reach=on|title=the one title|stated=%s|at=2026-10-25T09:00:00Z\n' \
  "$SID" "$PA_S1" >> "$PA_LOG"
sp_fact "$PPA" "$(pa_lib proof_waiver_line adversarial "$PA_H" 'Dana Fixture' 2026-10-25T10:00:00Z 'go on')"
git -C "$RPA" worktree add -q -b wt/01-T3 "$TMPROOT/parts-T3" wave/01-fixture >/dev/null 2>&1
PA_WT="$(cd "$TMPROOT/parts-T3" && pwd -P)"
expect_eq "PA-0 precondition: the plan's working branch is wave/01-fixture, the sentence is stated, the waiver is a line of its own, the row's tree is on wt/01-T3 at the working branch's head" \
  "wave/01-fixture|1|1|wt/01-T3|$PA_H" \
  "$(pa_lib plan_working_branch "$PPA")|$(/usr/bin/grep -c '|ev=finding|.*|to=defer|.*|stated=' "$PA_LOG" | tr -d ' ')|$(/usr/bin/grep -c '|ev=waiver|question=adversarial|' "$PA_LOG" | tr -d ' ')|$(git -C "$PA_WT" symbolic-ref --short -q HEAD)|$(git -C "$PA_WT" rev-parse HEAD)"

poke "$PA_WT" known-limits-part T3
PA_T1="$(pa_tip wt/01-T3)"
expect_eq "PA-1 known-limits-part run from the row's tree commits on the tree's branch: exit 0, the line's author, on the tree's head, the message as before" \
  "0|bionic line|$PA_H|line: the $PA_V entry's Known limits, rendered from the plan's deferrals" \
  "$RC|$(git -C "$RPA" log -1 --format='%an|%P|%s' "$PA_T1" 2>/dev/null)"
[ "$RC" = 0 ] || printf '%s\n' "$OUT" | tail -6 | sed 's/^/    | /'
expect_eq "PA-1b …rendered into the tree: its HEAD is the commit, its CHANGELOG.md holds the sentence and is clean" \
  "$PA_T1|1|" "$(git -C "$PA_WT" rev-parse HEAD)|$(pa_has "$PA_WT" "- $PA_S1")|$(git -C "$PA_WT" status --porcelain -- CHANGELOG.md)"
expect_eq "PA-2 …and the working branch is where it was, its checkout without the part" \
  "$PA_H|$PA_H|0" "$(pa_tip wave/01-fixture)|$(git -C "$RPA" rev-parse HEAD)|$(pa_has "$RPA" "- $PA_S1")"
expect_contains "PA-3 the part line names the commit, the tree's branch and the tree" \
  "|ev=published|part=known-limits|commit=$PA_T1|branch=wt/01-T3|tree=$PA_WT|by=T3|at=" "$(pa_ev known-limits)"

poke "$PA_WT" reviews-part T4
PA_T2="$(pa_tip wt/01-T3)"
expect_eq "PA-4 reviews-part run from the row's tree commits on the tree's branch: exit 0, the line's author, on the tree's head, the message as before" \
  "0|bionic line|$PA_T1|line: the $PA_V entry's reviews, rendered from the plan before the pull request" \
  "$RC|$(git -C "$RPA" log -1 --format='%an|%P|%s' "$PA_T2" 2>/dev/null)"
[ "$RC" = 0 ] || printf '%s\n' "$OUT" | tail -6 | sed 's/^/    | /'
expect_eq "PA-4b …rendered into the tree: its HEAD is the commit and its CHANGELOG.md holds the part" \
  "$PA_T2|1" "$(git -C "$PA_WT" rev-parse HEAD)|$(pa_has "$PA_WT" '### The reviews')"
expect_eq "PA-5 …and the working branch is where it was" "$PA_H|0" "$(pa_tip wave/01-fixture)|$(pa_has "$RPA" '### The reviews')"
expect_contains "PA-6 the part line names the commit, the tree's branch and the tree" \
  "|ev=published|part=reviews|commit=$PA_T2|branch=wt/01-T3|tree=$PA_WT|by=T4|at=" "$(pa_ev reviews)"

poke "$RPA" known-limits-part T3
PA_T3="$(pa_tip wave/01-fixture)"
expect_eq "PA-7 run from the checkout holding the working branch, known-limits-part moves that branch: exit 0, a commit on its old head" \
  "0|bionic line|$PA_H" "$RC|$(git -C "$RPA" log -1 --format='%an|%P' "$PA_T3" 2>/dev/null)"
expect_eq "PA-7b …by a fast-forward of that checkout, which holds the sentence; the row's branch is untouched" \
  "$PA_T3|1|$PA_T2" "$(git -C "$RPA" rev-parse HEAD)|$(pa_has "$RPA" "- $PA_S1")|$(pa_tip wt/01-T3)"
expect_contains "PA-8 …and its part line names the working branch and its checkout" \
  "|ev=published|part=known-limits|commit=$PA_T3|branch=wave/01-fixture|tree=$RPA|by=T3|at=" "$(pa_ev known-limits)"

git -C "$RPA" worktree add -q "$TMPROOT/parts-main" main >/dev/null 2>&1
PA_M="$(pa_tip main)"
poke "$TMPROOT/parts-main" reviews-part T4
PA_T4="$(pa_tip wave/01-fixture)"
expect_eq "PA-9 run from a checkout on main, reviews-part commits on the working branch as before, main unmoved" \
  "0|$PA_T3|$PA_M|$PA_T4" "$RC|$(git -C "$RPA" log -1 --format='%P' "$PA_T4" 2>/dev/null)|$(pa_tip main)|$(git -C "$RPA" rev-parse HEAD)"
expect_contains "PA-9b …and its part line names the working branch and the checkout holding it" \
  "|ev=published|part=reviews|commit=$PA_T4|branch=wave/01-fixture|tree=$RPA|by=T4|at=" "$(pa_ev reviews)"

# ============================================================
section "§START: start <id> records the birth, renders the brief and makes the tree of a row the plan holds, then owes one task-list entry, at the end (REQ-14 AC-14.1, REQ-18 AC-18.1)"
# ============================================================
# The row's words are a person's and are in the plan first; start does every act after them: task-add's birth, the
# brief's render and spawn-worktree.sh create --for the row's name, at the working head on wt/<wave n>-<id>. A second
# start, under a re-dispatch's name, finds the birth and the tree standing and marks the kept tree for the new name.
# FIXTURE FIDELITY: plan_fixture's page at Step 4 on a real repository on its working branch; the row is the
# orchestrator's edit (ta_put), sealed again as the write hook seals it; every act is the real verb's.
# fails-when: after start the log lacks the row's birth, or its brief or its tree is missing; the owed line names more
# than one entry, or asks for the entries after it to be made again.
SR_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=120
RSR="$(make_repo start)"; git -C "$RSR" config user.email t@example.com; git -C "$RSR" config user.name "Dana Fixture"
( cd "$RSR" && printf '.bionic\n' > .gitignore && git add .gitignore && git commit -qm base && git checkout -q -b wave/01-fixture ) >/dev/null 2>&1
PSR="$(plan_fixture "$RSR/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md" wave \
  "| T1 | 4 | build | The first build. It lands. | — | — | — | 30 | REQ-1 | lib/a.sh | — | — | pending |")"
ta_put "$PSR" '| T7 | 4 | build | Start the row. One verb starts it. · complexity: complex | — | 30 | REQ-1 | lib/s.sh, tests/s.test.sh | — |'
SR_LOG="$(plan_fixture_log "$PSR")"; seal_fixture "$PSR" "$SR_LOG"; bind_marker "$RSR" "$PSR"
SR_TREE="$RSR/.worktrees/01-T7"; SR_BRIEFS="$RSR/.bionic/docs/record/wave-01-fixture/briefs"
sr_owed() { printf '%s\n' "$OUT" | /usr/bin/grep -c "$1"; }
poke "$RSR" start T7
expect_eq "START-1 start of a row the plan holds exits 0" "0" "$RC"
expect_eq "START-1b AC-14.1 …the run's log holds the row's birth, once" "1" "$(/usr/bin/grep -c '|ev=born|row=T7|' "$SR_LOG")"
expect_true "START-1c AC-14.1 …its brief is rendered under its name" test -s "$SR_BRIEFS/T7.md"
expect_eq "START-1d AC-14.1 …and its tree is made at the working head, on its branch" \
  "wt/01-T7 $(git -C "$RSR" rev-parse wave/01-fixture)" "$(git -C "$SR_TREE" rev-parse --abbrev-ref HEAD 2>&1) $(git -C "$SR_TREE" rev-parse HEAD 2>&1)"
expect_eq "START-2 AC-18.1 its last line owes one task-list entry, added at the end of the list" \
  "poker: start — owed: add the task-list entry 4/T7: Start the row at the end of the list, and mark it in progress." "$(printf '%s\n' "$OUT" | tail -1)"
expect_eq "START-2b …said once, and no entry after it is to be made again" "1|0" "$(sr_owed 'owed:')|$(sr_owed recreate)"
poke "$RSR" start T7 T7-r2
expect_eq "START-3 a second start under a re-dispatch's name exits 0, and the birth stands once" \
  "0|1" "$RC|$(/usr/bin/grep -c '|ev=born|row=T7|' "$SR_LOG")"
expect_eq "START-3b …the brief is rendered for the new name, and the kept tree is marked for it" "1|T7-r2" \
  "$(test -s "$SR_BRIEFS/T7-r2.md" && echo 1)|$(bash -c '. "$1/worktree.sh" >/dev/null 2>&1; worktree_marker "$2"' _ "${BIONIC_HOOKS_DIR}/../payload/scripts/lib" "$SR_TREE")"
expect_eq "START-3c …and it owes no new entry: the one it has goes in progress" \
  "poker: start — owed: mark the task-list entry 4/T7: Start the row in progress." "$(printf '%s\n' "$OUT" | tail -1)"
POKE_BOUND="$SR_BOUND_WAS"

finish
