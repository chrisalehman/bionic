#!/bin/bash
# tests/final-card.test.sh — THE FINAL CARD: payload/scripts/card.sh `final <plan>` and `early <plan>`, and
# hooks/session-poker.sh `reply '<text>'` (epic-23 wave-38 T3; REQ-1 AC-1.1, AC-1.2; D19, D20; ADR-059).
#
# WHAT IT HOLDS. The autonomous half of a run waits for its human once, at one card the tool renders from the
# record: the owed ledger's open items (lib/owed.sh), the matrix rows not discharged and the findings disposition
# (`session-poker.sh disposition`), each with its default shown, option 1 accepting every default and options 2..n
# the single overrides. The card refuses to render, `CARD-EARLY — <reason>` on stderr and exit 1, while a reader
# row is open on the session's roster, an owed reading is unregistered at the working head, or `current <N>
# --check` is red for N = 6, 7 or 8 (T1's check-only advance, its exit read, never re-derived). One reply, typed by
# the user, is replayed by `reply` into approve, waive, waive-row and finding-move with the user's words.
#
# §ONE    one render, one reply, every line stamped with the reply's words; the second render reads as settled
# §EARLY  each of the three facts refuses the render in its own words; the tick says the same line as advice
# §AGREE  the card's options are exactly the owed items, the undischarged rows and the carried findings
# §REPLY  an override replays into its own verb; an option not on the card, or words not typed, write nothing
#
# FIXTURE FIDELITY. The world is session-poker-5 §CHECK's (a real repository on `wave/01-fixture`, base B, a code
# commit C, then the release text's commit R touching CHANGELOG.md alone), a double wave plan the real gate admits
# at Steps 6 to 8, bound to this session, every proof line in its production writer's shape (`proof_line`,
# `proof_floor_line`), and five reading records in the readers' grammar, one carrying an S3 finding. The release
# row T2 and the build row T1 are landed; the integrate row T3 reads `approval:release, approval:merge, head`. The
# undischarged row AC-1.2 is `pending` with the auditor's CONFIRMED (the only undischarged shape the Step-6 gate
# admits on a row that carries no waiver, measured: an empty auditor cell makes `current 6 --check` refuse). The
# user's words stand in a transcript where the CLI writes one, under a CLAUDE_CONFIG_DIR of this suite's own, with
# the session's load record beside the root (lib/said.sh's two witnesses). Every move is the real verb.
#
# ANTI-VACUITY. Each refusal row stands beside a render on the same verb and the same fixture with one fact moved
# (EARLY-1 and EARLY-2: one reader, open then acked); the tick's absent CARD-EARLY stands beside its WAIT line on
# the same output; the agreement comparator is shown to go red on a planted and on a dropped option before its
# green is read; every refusal of reply is held to a byte-identical plan (cmp) beside a reply that wrote.
#
# Usage: bash tests/final-card.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/lib/live-answer.sh"

# THE SEAMS. The poker as session-poker.test.sh offers it; the card renderer beside the library it sources.
POKER="${W2_POKER_UNDER_TEST:-${BIONIC_HOOKS_DIR}/session-poker.sh}"
CARD="${BIONIC_CARD_UNDER_TEST:-${BIONIC_HOOKS_DIR}/../payload/scripts/card.sh}"
FC_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib"
S46_LIB="${FC_LIB}/proof.sh"
. "$(dirname "$0")/session-poker.prelude.sh"
POKE_BOUND=180

# ---------- the world ----------
RFC="$(make_repo final)"
git -C "$RFC" config user.email t@example.com; git -C "$RFC" config user.name "Dana Fixture"
printf '.bionic\n' > "$RFC/.gitignore"
mkdir -p "$RFC/tests" "$RFC/lib" "$RFC/.bionic/docs/plans" "$RFC/.bionic/docs/record/wave-x"
printf '#!/bin/bash\nexit 0\n' > "$RFC/tests/a.test.sh"
printf 'one\n' > "$RFC/lib/x.sh"; printf '# Changelog\n' > "$RFC/CHANGELOG.md"
( cd "$RFC" && git add .gitignore tests lib CHANGELOG.md && git commit -qm base && git checkout -q -b wave/01-fixture ) >/dev/null 2>&1
FC_B="$(git -C "$RFC" rev-parse HEAD)"
FC_C="$(s57_commit "$RFC" lib/x.sh 'T1: the code change')"
FC_R="$(s57_commit "$RFC" CHANGELOG.md 'T2: the release text')"
FC_H8="${FC_R:0:8}"
FC_REC="$RFC/.bionic/docs/record/wave-x"
FC_FID="record/wave-x/adversarial.md#1"
printf 'generic fixture proof\n' > "$RFC/.bionic/docs/record/generic-evidence.md"
fc_record() {  # <name> <question> <scope> [<finding line>] -> a reading record in the readers' grammar
  { printf 'question: %s\nresult: pass\nscope: %s\nreviewed: %s..%s\n' "$2" "$3" "${FC_B:0:10}" "${FC_C:0:10}"
    if [ -n "${4:-}" ]; then printf 'findings: 1\n%s\n' "$4"; else printf 'findings: 0\n'; fi
    printf '\nwhat the reader found\n'; } > "$FC_REC/$1.md"
}
fc_record evidence evidence piece
fc_record adversarial adversarial piece 'finding: 1 S3 off lib/x.sh:1 a message could be clearer'
fc_record structure structure piece
fc_record adversarial-whole adversarial whole
fc_record structure-whole structure whole
fc_line() { bash -c '. "$1/proof.sh" && shift && proof_line "$@"' _ "$FC_LIB" "$@"; }
fc_floor() {  # <head> [<owed suites>] -> a regression proof at <head>, as its writer writes it
  bash -c '. "$1/proof.sh" && proof_floor_line "$2" 2026-10-12T11:00:00Z record/wave-x/floor.log "${3:-}"' _ "$FC_LIB" "$1" "${2:-}"
}
fc_reads() {  # <head> -> the five readings a double wave plan is dealt, at <head>
  fc_line review "$1" 2026-10-12T12:00:00Z record/wave-x/evidence.md evidence w-read pass piece
  fc_line review "$1" 2026-10-12T12:00:00Z record/wave-x/adversarial.md adversarial w-read pass piece
  fc_line review "$1" 2026-10-12T12:00:00Z record/wave-x/structure.md structure w-read pass piece
  fc_line review "$1" 2026-10-12T12:00:00Z record/wave-x/adversarial-whole.md adversarial w-read pass whole
  fc_line review "$1" 2026-10-12T12:00:00Z record/wave-x/structure-whole.md structure w-read pass whole
}
PFC="$RFC/.bionic/docs/plans/wave-x.plan.md"
fc_plan() {  # <proof lines> [<sed edit>] -> PFC at current: 8, bound to this session; the record and the ledger cleared
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: double\nscale: wave\n'
    printf 'deploy_target: none\nuse_worktree: false\nhas_ui: false\nwalk: exempt\n---\n# plan\n\n## SDLC State\n\n'
    printf 'current: 8\nworking-branch: wave/01-fixture\napproved-by: fixture 2026-09-22T00:00Z approved\n'
    printf -- '- Step 4: dispatched, record/wave-x/dispatch.md\n  worktree: .\n  base-sha: %s\n  branch: wave/01-fixture\n' "$FC_B"
    printf -- '- T1: landed %s 2026-10-12T10:00:00Z\n- T2: landed %s 2026-10-12T13:00:00Z\n' "$FC_C" "$FC_R"
    printf -- '- Step 5: regression, record/wave-x/floor.log\n  auditor: CONFIRMED, record/wave-x/audit.md\n'
    printf -- '- Step 6: review at record/wave-x/review.md\n'
    printf -- '- Step 7: documented at record/wave-x/docs.md\n  n/a: no decision this run\n'
    printf '%s\n' "$1"
    printf '\n## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T1 | 4 | build | the x writer | implementor | — | 30 | REQ-1 | lib/x.sh | — | — | landed | approval:plan |\n'
    printf '| T2 | 7 | doc | the release 1.0.0 | implementor | — | 30 | REQ-1 | CHANGELOG.md | — | — | landed | approval:plan, head |\n'
    printf '| T3 | 8 | integrate | merge into main | orchestrator | — | 10 | REQ-1 | — | — | — | pending | approval:release, approval:merge, head |\n'
    printf '\n## Verification Matrix\n\nstack-health: n/a: no long-running serve\n\n'
    printf '| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n'
    printf '| AC-1.1 | T1 | discharged | see AC-1.1 | CONFIRMED |\n| AC-1.2 | T1 | pending | see AC-1.2 | CONFIRMED |\n\n'
    printf 'AC-1.1:\n  fails-when: the planted defect this eval must go red on\n  evidence: record/generic-evidence.md\n'
    printf '  tier-run: bash tests/a.test.sh\n  readback: the line it wrote\n'
    printf 'AC-1.2:\n  fails-when: a second planted defect\n  evidence: record/generic-evidence.md\n'
    printf '  tier-run: bash tests/a.test.sh\n  readback: the line it wrote\n'
  } | sed -e "${2:-}" > "$PFC"
  rm -f "$FC_REC"/final-card-*.md "$RFC/.bionic/tmp/owed-$SID.state" "$(roster_of "$RFC")" "$(ack_ledger_of "$RFC")"
  bind_marker "$RFC" "$PFC"
}
FC_GOOD="$(fc_floor "$FC_C")
$(fc_reads "$FC_C")"

# THE USER'S WORDS: every reply this suite replays is typed in this session's transcript, whole.
FC_CFG="$TMPROOT/fc-cfg"
FC_PROJ="$FC_CFG/projects/$(bash -c '. "$1/detect.sh" >/dev/null 2>&1; project_slug "$2"' _ "$FC_LIB" "$RFC")"
mkdir -p "$FC_PROJ" "$FC_CFG/bionic"
printf '80\n' > "$FC_CFG/bionic/share"   # the prelude's pinned share, kept under this suite's own config dir
printf 'root=%s\nstarted=2026-10-14T00:00:00Z\ncwd=%s\n' "${BIONIC_HOOKS_DIR%/*}" "$RFC" > "$RFC/.bionic/tmp/loaded-$SID.state"
export CLAUDE_CONFIG_DIR="$FC_CFG"
FC_TX="$FC_PROJ/$SID.jsonl"
FC_FX="${BIONIC_SCRIPTS_DIR}/tests/fixtures/transcript-move"
fc_typed() {  # <prompt>... -> the transcript holds each as a typed prompt of this session
  local t
  cat "$FC_FX/frame.jsonl" > "$FC_TX"
  for t in "$@"; do jq -c --arg t "$t" '.message.content = $t' "$FC_FX/typed.jsonl" >> "$FC_TX"; done
}
FC_W2='2 hold the release for now'
FC_W5='5 fix it before the merge please'
fc_typed 1 "$FC_W2" "$FC_W5"

fc_card() {  # <verb> [<plan>] -> FC_RC, FC_OUT (stdout), FC_ERR (stderr) of card.sh, run in the repository as this session
  ( cd "$RFC" && exec env CLAUDE_CODE_SESSION_ID="$SID" bash "$CARD" "$1" "${2:-$PFC}" ) > "$TMPROOT/fc.out" 2> "$TMPROOT/fc.err"
  FC_RC=$?; FC_OUT="$(cat "$TMPROOT/fc.out")"; FC_ERR="$(cat "$TMPROOT/fc.err")"
}
fc_cards() { ( cd "$FC_REC" && ls final-card-*.md 2>/dev/null ) | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'; }
fc_table() { /usr/bin/grep '^final-card/v1|opt=' "$FC_REC/final-card-$FC_H8.md" 2>/dev/null; }  # the record's replay table
fc_keys() { fc_table | awk -F'|' '{ for (i = 2; i <= NF; i++) if (index($i, "key=") == 1) print substr($i, 5) }'; }
fc_row() { /usr/bin/grep -E "^\| $1 \|" "$PFC" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $4); print $4 }'; }  # <AC> -> its status cell
fc_owed() { bash -c '. "$1/owed.sh"; OWED_ROOT="$2" OWED_SID="$3" owed_list' _ "$FC_LIB" "$RFC" "$SID" 2>/dev/null | cut -f1; }
fc_owe() { bash -c '. "$1/owed.sh"; OWED_ROOT="$2" OWED_SID="$3" owed_open "$4" "fixture: $4" "poker: fixture item $4"' _ "$FC_LIB" "$RFC" "$SID" "$1"; }

# ============================================================
section "§ONE: one render of card.sh final, one reply, every approval and waiver stamped with the reply's words (AC-1.1; D19)"
# ============================================================
# fails-when: the card does not render on a run whose readers are in and whose advances check green; a second
# render is needed; `reply '1'` leaves an approval or the row's waiver unwritten, or writes another word than the
# reply's; the render after the reply refuses or offers the settled items again.
fc_plan "$FC_GOOD"
for fc_n in 6 7 8; do
  poke "$RFC" current "$fc_n" --check
  expect_eq "ONE-0.$fc_n precondition: current $fc_n --check is green on the fixture (the card's third fact holds)" \
    "0|poker: current $fc_n --check: would advance" "$RC|$(printf '%s\n' "$OUT" | head -1)"
done
fc_card final
expect_eq "ONE-1 card.sh final renders on the settled run (exit 0)" "0" "$FC_RC"
[ "$FC_RC" = 0 ] || printf '      stderr: %s\n' "$FC_ERR"
expect_eq "ONE-1b …and says nothing on stderr" "" "$FC_ERR"
expect_eq "ONE-2 the card opens on its heading, the run and the head it was rendered at" \
  "**Final card · wave-x at $FC_H8**" "$(printf '%s\n' "$FC_OUT" | head -1)"
expect_contains "ONE-2b …in the decision shape: Goal" "**Goal:**" "$FC_OUT"
expect_contains "ONE-2c …Options" "**Options:**" "$FC_OUT"
expect_contains "ONE-2d …a Recommendation opening on option 1" "**Recommendation:** Option 1," "$FC_OUT"
expect_contains "ONE-2e …Significance" "**Significance:**" "$FC_OUT"
expect_eq "ONE-2f …ending on one reply line naming every option" "Reply 1, 2, 3, 4 or 5" "$(printf '%s\n' "$FC_OUT" | tail -1)"
expect_contains "ONE-3 option 1 accepts every default" "1. Accept every default:" "$FC_OUT"
expect_contains "ONE-3b …the release approval, shown" "approve release" "$FC_OUT"
expect_contains "ONE-3c …the merge approval, shown" "approve merge" "$FC_OUT"
expect_contains "ONE-3d …the undischarged row, waived with its reason" "waive AC-1.2 — not run on this release" "$FC_OUT"
expect_contains "ONE-3e …the S3 finding, carried with its changelog sentence" \
  "carry $FC_FID (S3 off) — \"a message could be clearer\"" "$FC_OUT"
expect_contains "ONE-4 option 2 withholds the release" "2. Withhold release:" "$FC_OUT"
expect_contains "ONE-4b option 3 withholds the merge" "3. Withhold merge:" "$FC_OUT"
expect_contains "ONE-4c option 4 runs the row instead of waiving it" "4. Run AC-1.2 instead of waiving:" "$FC_OUT"
expect_contains "ONE-4d option 5 fixes the finding instead of carrying it" "5. Fix $FC_FID instead:" "$FC_OUT"
expect_eq "ONE-5 the card is written to record/<wave>/final-card-<head8>.md, one file" "final-card-$FC_H8.md" "$(fc_cards)"
expect_eq "ONE-5b …and the record opens on the card, byte for byte as printed" \
  "$FC_OUT" "$(head -n "$(printf '%s\n' "$FC_OUT" | wc -l | tr -d ' ')" "$FC_REC/final-card-$FC_H8.md" 2>/dev/null)"
expect_eq "ONE-5c …carrying its replay table, one line per overridable item" "4" "$(fc_table | /usr/bin/grep -c .)"
cp "$PFC" "$TMPROOT/fc-before-reply"
poke "$RFC" reply 1
expect_eq "ONE-6 reply '1' replays the card (exit 0)" "0" "$RC"
[ "$RC" = 0 ] || printf '      reply said: %s\n' "$OUT"
expect_regex "ONE-6b approved: release, by the git user, with the reply's words" \
  '^approved: release by Dana Fixture [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z "1"$' "$(/usr/bin/grep '^approved: release ' "$PFC")"
expect_regex "ONE-6c approved: merge, the same" \
  '^approved: merge by Dana Fixture [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z "1"$' "$(/usr/bin/grep '^approved: merge ' "$PFC")"
expect_eq "ONE-6d the undischarged row's status is waived" "waived" "$(fc_row AC-1.2)"
expect_regex "ONE-6e …its waiver: line quoting the reply, with the card's reason" \
  '^  waiver: Dana Fixture [0-9]{4}-[0-9]{2}-[0-9]{2} "1" — not run on this release$' "$(/usr/bin/grep '^  waiver: ' "$PFC")"
expect_eq "ONE-6f …the discharged row is untouched" "discharged" "$(fc_row AC-1.1)"
expect_eq "ONE-6g the carried finding needs no verb: no moved: line names it" "" "$(/usr/bin/grep -F "moved: $FC_FID " "$PFC")"
expect_contains "ONE-6h …while the record keeps the reply and what it applied" "replied: " "$(cat "$FC_REC/final-card-$FC_H8.md")"
expect_contains "ONE-6i …the carry among them" "applied: finding:$FC_FID carried" "$(cat "$FC_REC/final-card-$FC_H8.md")"
expect_eq "ONE-6j the reply closed the person's two approval items" "" "$(fc_owed | /usr/bin/grep '^approve:')"
fc_card final
expect_eq "ONE-7 a second card.sh final after the reply refuses nothing (exit 0)" "0|" "$FC_RC|$FC_ERR"
expect_contains "ONE-7b …and renders the card as settled" "settled" "$(printf '%s\n' "$FC_OUT" | head -1)"
expect_contains "ONE-7c …naming each recorded approval" "approved: release by Dana Fixture" "$FC_OUT"
expect_absent "ONE-7d …and offers no option" "Reply 1" "$FC_OUT"
expect_eq "ONE-7e …and writes no second card: one render in the record" "final-card-$FC_H8.md" "$(fc_cards)"

# ============================================================
section "§EARLY: card.sh final refuses CARD-EARLY on each of the three facts, and the tick says the same line (AC-1.2; D20)"
# ============================================================
# fails-when: the card renders while a reader row is open, an owed reading is unregistered at the head, or the
# advance to 6, 7 or 8 checks red; the refusal names another reason; a writer row or an acked reader trips it.
fc_plan "$FC_GOOD"
new_roster "$RFC"
add_row "$RFC" name=w38-T13 agent_id=a013 subagent_type=bionic:critic
fc_card final
expect_eq "EARLY-1 an open critic row on the roster: card.sh final exits 1" "1" "$FC_RC"
expect_eq "EARLY-1b …saying CARD-EARLY and the reader, on stderr" "CARD-EARLY — reader w38-T13 open" "$FC_ERR"
expect_eq "EARLY-1c …rendering nothing" "" "$FC_OUT"
expect_eq "EARLY-1d …and writing no card" "" "$(fc_cards)"
fc_card early
expect_eq "EARLY-1e card.sh early answers the same fact, the same words (exit 1)" "1|CARD-EARLY — reader w38-T13 open" "$FC_RC|$FC_ERR"
ack_rows "$RFC" w38-T13
fc_card final
expect_eq "EARLY-2 the same critic acked: the card renders (exit 0, no refusal)" "0|" "$FC_RC|$FC_ERR"
fc_plan "$FC_GOOD"
new_roster "$RFC"
add_row "$RFC" name=w38-T9 agent_id=a009 subagent_type=bionic:implementor
fc_card final
expect_eq "EARLY-2b an open writer row is no reader: the card renders (exit 0)" "0|" "$FC_RC|$FC_ERR"
fc_plan "$FC_GOOD" '/structure-whole/d'
fc_card final
expect_eq "EARLY-3 the whole structure reading unregistered at the head: exit 1" "1" "$FC_RC"
expect_eq "EARLY-3b …CARD-EARLY naming the question and the head" "CARD-EARLY — structure unregistered at $FC_H8" "$FC_ERR"
expect_eq "EARLY-3c …nothing rendered, no card written" "|" "$FC_OUT|$(fc_cards)"
FC_RED7="$(fc_floor "$FC_C" a.test.sh)
$(fc_reads "$FC_C")"
fc_plan "$FC_RED7"
poke "$RFC" current 6 --check; FC_C6="$RC"
poke "$RFC" current 7 --check; FC_C7="$RC|$(printf '%s\n' "$OUT" | head -1)"
expect_eq "EARLY-4 precondition: the regression's run owes a.test.sh, so current 6 --check holds and current 7 --check refuses" \
  "0 1|poker: current 7 --check: would refuse" "$FC_C6 $FC_C7"
fc_card final
expect_eq "EARLY-4b card.sh final exits 1" "1" "$FC_RC"
expect_eq "EARLY-4c …CARD-EARLY with the check's own verdict line as the reason" "CARD-EARLY — current 7 --check: would refuse" "$FC_ERR"
expect_eq "EARLY-4d …nothing rendered, no card written" "|" "$FC_OUT|$(fc_cards)"
new_roster "$RFC"; forget_digest "$RFC"
poke "$RFC" tick
expect_contains "EARLY-5 the tick, an integrate row open, says the same line as advice" \
  "poker: CARD-EARLY — current 7 --check: would refuse" "$OUT"
expect_contains "EARLY-5b …beside its WAIT line for the integrate row" "poker: WAIT T3" "$OUT"
fc_plan "$FC_GOOD"
new_roster "$RFC"; forget_digest "$RFC"
poke "$RFC" tick
expect_contains "EARLY-5c on the settled run the tick still says its WAIT line (the reader is not vacuous)" "poker: WAIT T3" "$OUT"
expect_absent "EARLY-5d …and no CARD-EARLY" "CARD-EARLY" "$OUT"

# ============================================================
section "§AGREE: the card's options are the owed items, the undischarged rows and the carried findings, nothing else (ownership row; D19)"
# ============================================================
# fails-when: the card offers an item the record does not owe, or leaves one out. The expected set is lifted from
# the three sources independently: owed_list's approve: and waive: keys, the matrix rows neither discharged nor
# waived, and the S2-off, S3 and S4 findings `disposition` prints.
fc_plan "$FC_GOOD"
fc_owe approve:release; fc_owe approve:merge; fc_owe waive:structure
fc_expected() {  # -> the item keys the three sources owe, sorted
  { fc_owed | /usr/bin/grep -E '^(approve|waive):'
    awk -F'|' '/^## /{ m = ($0 ~ /^## Verification Matrix/) } m && /^\| AC-/ { s = $4; gsub(/^[ \t]+|[ \t]+$/, "", s); a = $2; gsub(/^[ \t]+|[ \t]+$/, "", a)
      if (s != "discharged" && s != "waived") print "row:" a }' "$PFC"
    poke "$RFC" disposition
    printf '%s\n' "$OUT" | awk '$2 == "finding" { s = $4; r = $5; sub(/^user-facing=/, "", r)
      if (s == "S1" || (s == "S2" && r == "on")) next; print "finding:" $3 }'
  } | LC_ALL=C sort
}
fc_agree() {  # <record> -> same or differs: the record's table keys against the sources'
  if [ "$(awk -F'|' '/^final-card\/v1\|opt=/ { for (i = 2; i <= NF; i++) if (index($i, "key=") == 1) print substr($i, 5) }' "$1" | LC_ALL=C sort)" \
     = "$(fc_expected)" ]; then echo same; else echo differs; fi
}
FC_WANT="$(fc_expected)"
expect_eq "AGREE-0 precondition: the sources owe five items (two approvals, a waiver, the row, the S3)" \
  "approve:merge approve:release finding:$FC_FID row:AC-1.2 waive:structure" "$(printf '%s\n' "$FC_WANT" | tr '\n' ' ' | sed 's/ $//')"
fc_card final
expect_eq "AGREE-1 card.sh final renders (exit 0)" "0" "$FC_RC"
expect_eq "AGREE-2 the card's options are exactly the sources' items" "same" "$(fc_agree "$FC_REC/final-card-$FC_H8.md")"
expect_eq "AGREE-2b …and it prints one option per item, after option 1" "6" "$(printf '%s\n' "$FC_OUT" | /usr/bin/grep -cE '^[0-9]+\. ')"
expect_contains "AGREE-2c …the waiver shown as a default, waived with the user's words" "waive structure" "$FC_OUT"
expect_contains "AGREE-2d …and its override" "Withhold the structure waiver:" "$FC_OUT"
expect_eq "AGREE-2e …in the fixed order: approvals, waivers, rows, findings" \
  "approve:release approve:merge waive:structure row:AC-1.2 finding:$FC_FID" "$(fc_keys | tr '\n' ' ' | sed 's/ $//')"
cp "$FC_REC/final-card-$FC_H8.md" "$TMPROOT/fc-planted.md"
printf 'final-card/v1|opt=7|key=approve:ship|default=approve ship|override=-|why=-\n' >> "$TMPROOT/fc-planted.md"
expect_eq "AGREE-3 a planted extra option goes red" "differs" "$(fc_agree "$TMPROOT/fc-planted.md")"
/usr/bin/grep -v '|key=row:AC-1.2|' "$FC_REC/final-card-$FC_H8.md" > "$TMPROOT/fc-dropped.md"
expect_eq "AGREE-3b …and so does a dropped one" "differs" "$(fc_agree "$TMPROOT/fc-dropped.md")"

# ============================================================
section "§REPLY: reply replays one option into its verbs with the user's words; anything else writes nothing (AC-1.1; D19)"
# ============================================================
# fails-when: an override is replayed into another verb or with other words; an option not on the card, a reply
# with no option, words the user never typed, a stale card or no card at all writes a byte of the plan.
fc_plan "$FC_GOOD"
fc_card final
poke "$RFC" reply "$FC_W2"
expect_eq "REPLY-1 reply '$FC_W2' (option 2, withhold release) exits 0" "0" "$RC"
expect_eq "REPLY-1b …the release is not approved" "" "$(/usr/bin/grep '^approved: release ' "$PFC")"
expect_regex "REPLY-1c …every other default is applied with the user's words: the merge" \
  "^approved: merge by Dana Fixture [0-9T:Z-]+ \"$FC_W2\"\$" "$(/usr/bin/grep '^approved: merge ' "$PFC")"
expect_eq "REPLY-1d …the row" "waived" "$(fc_row AC-1.2)"
expect_contains "REPLY-1e …and the reply says what it held back" "withheld: approve:release" "$OUT"
expect_contains "REPLY-1f …and that the person's approval item stays open" "approve:release" "$(fc_owed)"
fc_plan "$FC_GOOD"
fc_card final
poke "$RFC" reply "$FC_W5"
expect_eq "REPLY-2 reply '$FC_W5' (option 5, fix the finding instead) exits 0" "0" "$RC"
[ "$RC" = 0 ] || printf '      reply said: %s\n' "$OUT"
expect_regex "REPLY-2b …the finding is moved to fix on the user's words" \
  "^moved: record/wave-x/adversarial\\.md#1 to=fix by=Dana Fixture at=[0-9T:Z-]+ words=\"$FC_W5\"( session=[^ ]+)? why=\"" "$(/usr/bin/grep -F "moved: $FC_FID " "$PFC")"
expect_eq "REPLY-2c …and both approvals are stamped with the same words" \
  "2" "$(/usr/bin/grep '^approved: ' "$PFC" | /usr/bin/grep -cF "\"$FC_W5\"")"
fc_plan "$FC_GOOD"
fc_card final
fc_typed 1 "$FC_W2" "$FC_W5" 9 'ship it all now'
cp "$PFC" "$TMPROOT/fc-before"
poke "$RFC" reply 9
expect_eq "REPLY-3 an option the card does not carry (9 of 5): refused, exit 1" "1" "$RC"
expect_contains "REPLY-3b …naming the options there are" "1 to 5" "$OUT"
expect_true "REPLY-3c …and the plan is byte-identical (cmp)" cmp -s "$TMPROOT/fc-before" "$PFC"
poke "$RFC" reply 'ship it all now'
expect_eq "REPLY-4 a reply that names no option: refused, exit 1, the plan unchanged" "1|same" \
  "$RC|$(cmp -s "$TMPROOT/fc-before" "$PFC" && echo same || echo changed)"
poke "$RFC" reply '1 approve everything on the card'
expect_eq "REPLY-5 words the user never typed: refused, exit 1" "1" "$RC"
expect_true "REPLY-5b …before any verb runs: the plan is byte-identical (cmp)" cmp -s "$TMPROOT/fc-before" "$PFC"
s57_commit "$RFC" CHANGELOG.md 'a later release line' >/dev/null
poke "$RFC" reply 1
expect_eq "REPLY-6 the head moved since the card was rendered: refused, exit 1, the plan unchanged" "1|same" \
  "$RC|$(cmp -s "$TMPROOT/fc-before" "$PFC" && echo same || echo changed)"
expect_contains "REPLY-6b …saying the card is stale and to render it again" "card.sh final" "$OUT"
git -C "$RFC" reset -q --hard "$FC_R"
rm -f "$FC_REC"/final-card-*.md
poke "$RFC" reply 1
expect_eq "REPLY-7 no card rendered for the run: refused, exit 1, the plan unchanged" "1|same" \
  "$RC|$(cmp -s "$TMPROOT/fc-before" "$PFC" && echo same || echo changed)"
# THE REPLAY IS TABLE-DRIVEN: a waiver item replays as `waive <q> '<words>'` whatever the question, the verb name a
# string in the card's table. An open `waive:adversarial` item (opened by the judge on a reading since answered)
# replays into the waive verb; `waive:regression`, T2's arm, the same way once the verb admits the question.
fc_plan "$FC_GOOD"
fc_owe waive:adversarial
fc_card final
poke "$RFC" reply 1
expect_eq "REPLY-8 reply '1' over an open waive:adversarial item exits 0" "0" "$RC"
expect_regex "REPLY-8b …writing the waiver at the working head with the reply's words" \
  "^waived: question=adversarial head=$FC_R by Dana Fixture [0-9T:Z-]+ \"1\"\$" "$(/usr/bin/grep '^waived: question=adversarial ' "$PFC")"
FC_REGQ="$(bash -c '. "$1/proof.sh" >/dev/null 2>&1; declare -f proof_question_ok' _ "$FC_LIB" | /usr/bin/grep -c 'regression')"
if [ "$FC_REGQ" -gt 0 ]; then
  fc_plan "$FC_GOOD"
  fc_owe waive:regression
  fc_card final
  expect_contains "REPLY-9 an open waive:regression item is a default on the card" "waive regression" "$FC_OUT"
  poke "$RFC" reply 1
  expect_eq "REPLY-9b …and reply '1' replays it into waive regression (exit 0)" "0" "$RC"
  expect_regex "REPLY-9c …the regression waiver at the working head with the reply's words" \
    "^waived: question=regression head=$FC_R by Dana Fixture [0-9T:Z-]+ \"1\"\$" "$(/usr/bin/grep '^waived: question=regression ' "$PFC")"
else
  printf '  SKIP: REPLY-9 waive regression — proof_question_ok at this head admits no regression question (T2 not landed; A-T3-5)\n'
fi

finish
