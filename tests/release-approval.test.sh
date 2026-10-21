#!/bin/bash
# tests/review-results.test.sh — THE REVIEW RESULTS PAGE: hooks/session-poker.sh `review-results` and `reply`, and
# payload/scripts/card.sh `early`.
#
# WHAT IT HOLDS. The autonomous half of a run waits for its human once, at one page the tool renders from the
# record: Bottom line, Goals, Tests, Reviews, Findings and Decisions, in that order, padded plain text. A finding
# reaches Decisions only when it names a criterion that is not proved or when the orchestrator recommends against
# the policy's default (`--against <key>`); every other finding is one sentence under Findings, its severity code
# first, grouped fixed / awaiting your decision / carried. The regression is never a decision: a head with no green
# whole run is early, not waived. The page refuses to render, `CARD-EARLY — <reason>` on stderr and exit 1, while
# a reader row is open, an owed reading is unregistered at the head, or `current <N> --check` is red for N = 6, 7
# or 8 (`card.sh early`, the one owner of the three facts); `--preview` renders it anyway and records nothing. One
# reply, typed by the user, `all default`, `all recommended` or the decisions by number, is replayed by `reply` into
# approve, waive, waive-row and finding-move with the user's words.
#
# §SHAPE     the prototype's sections in order, plain text, no record path, no quotation, the title, the record
# §TRIGGERS  a carried S3 stays under Findings; a criterion miss and a recommendation against the default decide
# §NO-WAIVER no surface offers waiving the regression: an absent or red whole run is early
# §EARLY     each of the three facts refuses the render in its own words; the tick says the same line as advice
# §PREVIEW   --preview renders an early run's page and writes nothing
# §AGREE     the decisions are exactly the owed items, the unproved rows and the findings recommended against
# §REPLY     all default and all recommended replay into their verbs; anything else writes nothing
# §BORN      two fix rows born of different questions render the page with no re-read
# §JUDGE     the Tests line names the floor judge's answer: covered after a later green, the owed suite while none
# §STEP0     card.sh step0 renders the configuration card and owes its reply
#
# FIXTURE FIDELITY. A real repository on `wave/01-fixture`, base B, a code commit C, then the release text's commit
# R touching CHANGELOG.md alone; a double wave plan the real gate admits at Steps 6 to 8, bound to this session,
# every proof line in its production writer's shape (`proof_line`, `proof_floor_line`), and five reading records in
# the readers' grammar, one carrying an S3 finding. The release row T2 and the build row T1 are landed; the
# integrate row T3 reads `approval:release, approval:merge, head`. The second matrix row, unproved, is `pending` with the
# auditor's CONFIRMED. The user's words stand in a transcript where the CLI writes one, under a CLAUDE_CONFIG_DIR
# of this suite's own, with the session's load record beside the root (lib/said.sh's two witnesses).
#
# ANTI-VACUITY. Each refusal stands beside a render on the same verb and fixture with one fact moved; every absence
# is read from a page whose presence was read first; every refusal of reply is held to a byte-identical plan (cmp)
# beside a reply that wrote.
#
# Usage: bash tests/review-results.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/lib/live-answer.sh"

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
FC_S3='finding: 1 S3 off lib/x.sh:1 a message could be clearer'
fc_record evidence evidence piece
fc_record adversarial adversarial piece "$FC_S3"
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
    printf 'deploy_target: none\nuse_worktree: false\nhas_ui: false\nwalk: exempt\nrelease: 1.0.0\n---\n# plan\n\n## SDLC State\n\n'
    printf 'integration-branch: main\ncurrent: 8\nworking-branch: wave/01-fixture\napproved-by: fixture 2026-09-22T00:00Z approved\n'
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
  rm -f "$FC_REC"/review-results-*.md "$RFC/.bionic/tmp/owed-$SID.state" "$(roster_of "$RFC")" "$(ack_ledger_of "$RFC")"
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
FC_WD='all default'
FC_WR='all recommended'
fc_typed "$FC_WD" "$FC_WR"

fc_page() {  # [<arg>...] -> FC_RC, FC_OUT (stdout), FC_ERR (stderr) of `review-results <arg>... <plan>`, as this session
  ( cd "$RFC" && exec env CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" review-results "$@" "$PFC" ) > "$TMPROOT/fc.out" 2> "$TMPROOT/fc.err"
  FC_RC=$?; FC_OUT="$(cat "$TMPROOT/fc.out")"; FC_ERR="$(cat "$TMPROOT/fc.err")"
}
fc_card() {  # <verb> -> FC_RC, FC_OUT, FC_ERR of card.sh <verb> <plan>, run in the repository as this session
  ( cd "$RFC" && exec env CLAUDE_CODE_SESSION_ID="$SID" bash "$CARD" "$1" "$PFC" ) > "$TMPROOT/fc.out" 2> "$TMPROOT/fc.err"
  FC_RC=$?; FC_OUT="$(cat "$TMPROOT/fc.out")"; FC_ERR="$(cat "$TMPROOT/fc.err")"
}
fc_pages() { ( cd "$FC_REC" && ls review-results-*.md 2>/dev/null ) | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'; }
fc_table() { /usr/bin/grep '^review-results/v1|dec=' "$FC_REC/review-results-$FC_H8.md" 2>/dev/null; }  # the record's replay table
fc_keys() { fc_table | awk -F'|' '{ for (i = 2; i <= NF; i++) if (index($i, "key=") == 1) print substr($i, 5) }'; }
fc_row() { /usr/bin/grep -E "^\| $1 \|" "$PFC" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $4); print $4 }'; }  # <AC> -> its status cell
fc_owed() { bash -c '. "$1/owed.sh"; OWED_ROOT="$2" OWED_SID="$3" owed_list' _ "$FC_LIB" "$RFC" "$SID" 2>/dev/null | cut -f1; }
fc_owe() { bash -c '. "$1/owed.sh"; OWED_ROOT="$2" OWED_SID="$3" owed_open "$4" "fixture: $4" "poker: fixture item $4"' _ "$FC_LIB" "$RFC" "$SID" "$1"; }
fc_heads() { printf '%s\n' "$FC_OUT" | sed -n -E 's/^(Bottom line|Goals|Tests|Reviews|Findings|Decisions)( — .*)?$/\1/p' | paste -sd'|' -; }
fc_flat() { tr '\n' ' ' | tr -s ' ' | sed 's/ $//'; }  # folded lines read as one, for a phrase the fold may break
fc_under() {  # <section> -> the page's lines under that section head, to the next blank line
  printf '%s\n' "$FC_OUT" | awk -v h="$1" 'f && $0 == "" { exit } f { print } $0 == h || index($0, h " — ") == 1 { f = 1 }'
}

# ============================================================
section "§NAME: the card is the release approval card; the old name is read only as an alias and as the stem of pages already written"
# ============================================================
# The old spelling is built from parts so this file, which the sweep reads too, never spells it.
RN_W="review"
RN_ROOT="$(cd "${BIONIC_HOOKS_DIR}/.." && pwd)"
rn_sweep() {  # <root> -> file:line:text for every line under the shipped trees that spells the old name, either way
  ( cd "$1" && /usr/bin/grep -rniE "${RN_W}[ -]results" payload hooks tests skills agents-src 2>/dev/null )
}
# The sweep finds each spelling it is asked to find, in a tree that plants them (so an empty answer below means something).
mkdir -p "$TMPROOT/rn-plant/skills" "$TMPROOT/rn-plant/hooks"
printf 'the %s-results page\nthe %s results card\nThe %s Results page\n' "$RN_W" "$RN_W" "$RN_W" > "$TMPROOT/rn-plant/skills/x.md"
expect_eq "NAME-1 the sweep finds the hyphenated, the spaced and the capitalised spelling in a planted tree" "3" \
  "$(rn_sweep "$TMPROOT/rn-plant" | wc -l | tr -d ' ')"
RN_ALL="$(rn_sweep "$RN_ROOT")"
RN_KEPT='^hooks/session-poker\.sh:[0-9]+:RR_OLD_VERB="'"${RN_W}"'-results"'
expect_eq "NAME-2 the old name is spelled once in the shipped trees: the alias constant in session-poker.sh" "1" \
  "$(printf '%s\n' "$RN_ALL" | /usr/bin/grep -cE "$RN_KEPT")"
expect_empty "NAME-3 …and nowhere else under payload, hooks, tests, skills and agents-src" \
  "$(printf '%s\n' "$RN_ALL" | /usr/bin/grep -vE "$RN_KEPT")"
rn_run() {  # <verb> [<arg>...] -> RN_RC, RN_OUT, RN_ERR of the verb with no session, run in the fixture
  ( cd "$RFC" && exec env -u CLAUDE_CODE_SESSION_ID bash "$POKER" "$@" ) > "$TMPROOT/rn.out" 2> "$TMPROOT/rn.err"
  RN_RC=$?; RN_OUT="$(cat "$TMPROOT/rn.out")"; RN_ERR="$(cat "$TMPROOT/rn.err")"
}
rn_run release-approval --help
expect_eq "NAME-4 release-approval --help exits 0 and names itself on stdout" "0|yes" \
  "$RN_RC|$(printf '%s\n' "$RN_OUT" | /usr/bin/grep -q 'release-approval' && echo yes)"
RN_HELP="$RN_OUT"
rn_run "${RN_W}-results" --help
expect_eq "NAME-5 the old verb is an alias: it exits 0, prints the same help, and says the new name once on stderr" \
  "0|yes|poker: ${RN_W}-results is now release-approval|1" \
  "$RN_RC|$([ "$RN_OUT" = "$RN_HELP" ] && echo yes)|$RN_ERR|$(printf '%s\n' "$RN_ERR" | wc -l | tr -d ' ')"

# ============================================================
section "§SHAPE: the page is the prototype's, in plain text, recorded with its replay table (AC-13.1, AC-13.4; D8)"
# ============================================================
# fails-when: a section is missing or out of order; a markdown label, a record path or a quotation is printed; the
# old name prints; a finding line does not open on its severity code and three spaces; a decision does not say the
# recommendation before the default; the record is not written or does not open on the page.
fc_plan "$FC_GOOD"
for fc_n in 6 7 8; do
  poke "$RFC" current "$fc_n" --check
  expect_eq "SHAPE-0.$fc_n precondition: current $fc_n --check is green on the fixture" \
    "0|poker: current $fc_n --check: would advance" "$RC|$(printf '%s\n' "$OUT" | head -1)"
done
fc_page
expect_eq "SHAPE-1 review-results renders on the settled run (exit 0, nothing on stderr)" "0|" "$FC_RC|$FC_ERR"
expect_regex "SHAPE-2 the title names the page, the release, the head and the tasks landed" \
  "^Review results · [^ ]+ 1\\.0\\.0 · [A-Z][a-z]+day [0-9]{1,2}:[0-9]{2} [AP]M · head $FC_H8 · 2 of 3 tasks landed\$" \
  "$(printf '%s\n' "$FC_OUT" | head -1)"
expect_eq "SHAPE-3 the sections in the prototype's order" "Bottom line|Goals|Tests|Reviews|Findings|Decisions" "$(fc_heads)"
expect_eq "SHAPE-5 Goals with none declared says so" "Goals — none declared" "$(printf '%s\n' "$FC_OUT" | /usr/bin/grep '^Goals')"
expect_nonempty "SHAPE-11 precondition: the page has a body to read" "$(printf '%s\n' "$FC_OUT" | sed '$d')"
expect_eq "SHAPE-11b AC-13.4 …in plain text: no markdown label" "0" "$(printf '%s\n' "$FC_OUT" | /usr/bin/grep -c '\*\*')"
expect_eq "SHAPE-11c …no record path" "0" "$(printf '%s\n' "$FC_OUT" | /usr/bin/grep -c 'record/')"
expect_eq "SHAPE-11d …no quotation above the reply line" "0" "$(printf '%s\n' "$FC_OUT" | sed '$d' | /usr/bin/grep -c '"')"
expect_eq "SHAPE-11e …and never the old name" "0" "$(printf '%s\n' "$FC_OUT" | /usr/bin/grep -ci 'final card')"
expect_eq "SHAPE-11f …every line within 92 columns" "0" "$(printf '%s\n' "$FC_OUT" | LC_ALL=en_US.UTF-8 awk 'length($0) > 92' | /usr/bin/grep -c .)"
expect_eq "SHAPE-12 the page is written to the run's record, one file at the head" "review-results-$FC_H8.md" "$(fc_pages)"
expect_eq "SHAPE-12b …opening on the page, byte for byte as printed" \
  "$FC_OUT" "$(head -n "$(printf '%s\n' "$FC_OUT" | wc -l | tr -d ' ')" "$FC_REC/review-results-$FC_H8.md" 2>/dev/null)"
expect_eq "SHAPE-12c …its replay table one line per decision, in the page's order" \
  "row:AC-1.2 approve:release approve:merge" "$(fc_keys | tr '\n' ' ' | sed 's/ $//')"
expect_contains "SHAPE-12d …each with its default, its other choice and the recommendation" \
  "review-results/v1|dec=1|key=row:AC-1.2|default=waive-row AC-1.2|other=-|pick=default|choices=waive/run|why=not run on this release" "$(fc_table)"
fc_card final
expect_eq "SHAPE-13 card.sh final is gone: a usage error, nothing rendered" "64|" "$FC_RC|$FC_OUT"
expect_contains "SHAPE-13b …naming final as no row kind" "unknown row kind 'final'" "$FC_ERR"
FC_GRP="$(cd "${BIONIC_HOOKS_DIR}/.." && /usr/bin/grep -rn 'card.sh final' hooks payload skills 2>/dev/null)"
FC_GRP2="$(cd "${BIONIC_HOOKS_DIR}/.." && /usr/bin/grep -rln 'card.sh early' hooks payload 2>/dev/null)"
expect_nonempty "SHAPE-14 precondition: the grep reads the tree (card.sh early is found)" "$FC_GRP2"
expect_eq "SHAPE-14b …and no shipped file names card.sh final" "" "$FC_GRP"
FC_SK="${BIONIC_SKILLS_DIR}/canonical-sdlc"

# ---------- goals declared: each read by the one goals reader the sitrep reads ----------
fc_plan "$FC_GOOD" '/^release: 1.0.0$/a\
goals: fast landings · one-file median under 15m (landing-report --rows) ; pages · a fresh agent answers four questions (record/reader-test.md)'
fc_page --preview
printf '# reader test\n\nverdict: pass\n' > "$FC_REC/reader-test.md"
fc_page --preview
expect_eq "SHAPE-16b a reader-test record that passes flips its goal: 1 of 2 reached, the other still ❔, both in the plan's order" \
  "Goals — 1 of 2 reached|❔ fast landings|✅ pages" \
  "$(printf '%s\n' "$FC_OUT" | /usr/bin/grep '^Goals')|$(fc_under Goals | awk -F' — ' '{ print $1 }' | tr '\n' '|' | sed 's/|$//')"
rm -f "$FC_REC/reader-test.md"

# ============================================================
section "§TRIGGERS: a finding is a decision only on a criterion miss or a recommendation against the default (AC-13.2; D7)"
# ============================================================
# fails-when: the carried S3 is a decision; the criterion miss is not; a finding naming the missed criterion is not
# shown awaiting that decision; a recommendation against the default does not make the finding a decision.
fc_plan "$FC_GOOD"
fc_page
expect_contains "TRIG-1 the criterion miss is a decision" "1. AC-1.2, not run on this release" "$(fc_under Decisions)"
expect_contains "TRIG-1b precondition: the S3 is on the page, under Findings" "  S3   a message could be clearer" "$(fc_under Findings)"
expect_absent "TRIG-2 …and the carried S3 is no decision" "a message could be clearer" "$(fc_under Decisions)"
expect_absent "TRIG-2b …and no key for it in the replay table" "finding:" "$(fc_table)"
fc_plan "$FC_GOOD"
fc_page --against "finding:$FC_FID"
expect_eq "TRIG-3 the orchestrator recommends fixing the S3: rendered (exit 0)" "0|" "$FC_RC|$FC_ERR"
expect_eq "TRIG-3d …the count says so" "Findings — 1: 1 for your decision" "$(printf '%s\n' "$FC_OUT" | /usr/bin/grep '^Findings')"
expect_contains "TRIG-3f …and the table picks the other choice" "key=finding:$FC_FID|default=-|other=finding-move $FC_FID fix|pick=other" "$(fc_table)"
fc_plan "$FC_GOOD"
fc_page --against row:AC-9.9
expect_eq "TRIG-4 a recommendation naming nothing on the page is refused (exit 1), nothing written" "1|" "$FC_RC|$(fc_pages)"
expect_contains "TRIG-4b …naming the key" "row:AC-9.9" "$FC_ERR"
fc_record adversarial adversarial piece 'finding: 1 S3 off lib/x.sh:1 AC-1.2 is measured and missed'
fc_plan "$FC_GOOD"
fc_page
expect_absent "TRIG-5b …and is not a decision of its own" "measured and missed" "$(fc_under Decisions)"
fc_record adversarial adversarial piece "$FC_S3"

# ============================================================
section "§NO-WAIVER: no surface offers waiving the regression (AC-7.3; D16)"
# ============================================================
# fails-when: a regression waiver is a decision, a default, a table line or a phrase of the page; a head with no
# green whole run renders.
fc_plan "$FC_GOOD"
fc_owe waive:regression
fc_page
expect_eq "NW-1 an open waive:regression item on the ledger: the page renders (exit 0)" "0|" "$FC_RC|$FC_ERR"
expect_contains "NW-1b precondition: the page offers a waiver, of the row" "waive AC-1.2" "$FC_OUT"
expect_absent "NW-2 …and never the regression's" "waive regression" "$FC_OUT"
expect_absent "NW-2b …no decision names the regression" "egression" "$(fc_under Decisions)"
expect_absent "NW-2c …and no table line" "regression" "$(fc_table)"
fc_plan "$(fc_reads "$FC_C")"
poke "$RFC" current 7 --check
fc_page
expect_eq "NW-3b …and the page is early, not a waiver (exit 1, nothing rendered or written)" "1||" "$FC_RC|$FC_OUT|$(fc_pages)"
expect_contains "NW-3c …saying CARD-EARLY" "CARD-EARLY — " "$FC_ERR"
fc_plan "$(fc_floor "$FC_C" a.test.sh)
$(fc_reads "$FC_C")"
fc_page
expect_eq "NW-4 a whole run that left a suite red: early too (exit 1, nothing written)" "1|" "$FC_RC|$(fc_pages)"
expect_absent "NW-4b …offering no waiver" "waive regression" "$FC_OUT$FC_ERR"

# ============================================================
section "§EARLY: the page refuses CARD-EARLY on each of the three facts, and the tick says the same line (AC-1.2; D20)"
# ============================================================
# fails-when: the page renders while a reader row is open, an owed reading is unregistered at the head, or the
# advance to 6, 7 or 8 checks red; the refusal names another reason; a writer row or an acked reader trips it.
fc_plan "$FC_GOOD"
new_roster "$RFC"
add_row "$RFC" name=w38-T13 agent_id=a013 subagent_type=bionic:critic
fc_page
expect_eq "EARLY-1 an open critic row on the roster: review-results exits 1" "1" "$FC_RC"
expect_eq "EARLY-1b …saying CARD-EARLY and the reader, on stderr" "CARD-EARLY — reader w38-T13 open" "$FC_ERR"
expect_eq "EARLY-1c …rendering nothing and writing no page" "|" "$FC_OUT|$(fc_pages)"
fc_card early
expect_eq "EARLY-1e card.sh early answers the same fact, the same words (exit 1)" "1|CARD-EARLY — reader w38-T13 open" "$FC_RC|$FC_ERR"
ack_rows "$RFC" w38-T13
fc_page
expect_eq "EARLY-2 the same critic acked: the page renders (exit 0, no refusal)" "0|" "$FC_RC|$FC_ERR"
fc_plan "$FC_GOOD"
new_roster "$RFC"
add_row "$RFC" name=w38-T9 agent_id=a009 subagent_type=bionic:implementor
fc_page
expect_eq "EARLY-2b an open writer row is no reader: the page renders (exit 0)" "0|" "$FC_RC|$FC_ERR"
fc_plan "$FC_GOOD" '/structure-whole/d'
fc_page
expect_eq "EARLY-3 the whole structure reading unregistered at the head: exit 1" "1" "$FC_RC"
expect_eq "EARLY-3b …CARD-EARLY naming the question and the head" "CARD-EARLY — structure unregistered at $FC_H8" "$FC_ERR"
expect_eq "EARLY-3c …nothing rendered, no page written" "|" "$FC_OUT|$(fc_pages)"
FC_NODOC='/n\/a: no decision/d'
fc_plan "$FC_GOOD" "$FC_NODOC"
poke "$RFC" current 7 --check
expect_eq "EARLY-4 precondition: the Step-7 line names no adr, rca or n/a, so current 7 --check refuses on it" \
  "1|poker: current 7 --check: would refuse" "$RC|$(printf '%s\n' "$OUT" | head -1)"
fc_page
expect_eq "EARLY-4b review-results exits 1, CARD-EARLY with the check's own verdict line, nothing written" \
  "1|CARD-EARLY — current 7 --check: would refuse|" "$FC_RC|$FC_ERR|$(fc_pages)"
new_roster "$RFC"; forget_digest "$RFC"
poke "$RFC" tick
expect_contains "EARLY-5 the tick, an integrate row open, says the same line as advice" \
  "poker: CARD-EARLY — current 7 --check: would refuse" "$OUT"
expect_contains "EARLY-5b …beside its WAIT line for the integrate row" "poker: WAIT T3" "$OUT"
fc_plan "$FC_GOOD"
new_roster "$RFC"; forget_digest "$RFC"
poke "$RFC" tick
expect_contains "EARLY-5c on the settled run the tick still says its WAIT line" "poker: WAIT T3" "$OUT"
expect_absent "EARLY-5d …and no CARD-EARLY" "CARD-EARLY" "$OUT"
# A RED CHECK THE PAGE'S OWN DEFAULTS SETTLE IS NOT EARLY: a question whose newest reading fails is waived with the
# user's words, and the page offers it as a decision.
{ printf 'question: adversarial\nresult: fail\nscope: whole\nreviewed: %s..%s\nfindings: 1\n' "${FC_B:0:10}" "${FC_C:0:10}"
  printf 'finding: 1 S2 on lib/x.sh:1 the value is lost on a second run\nshown: 1 bash lib/x.sh; bash lib/x.sh\n\nwhat the reader found\n'
} > "$FC_REC/adversarial-fail.md"
FC_FAILR="$(fc_floor "$FC_C")
$(fc_reads "$FC_C" | sed '/adversarial-whole\.md/{s/adversarial-whole\.md/adversarial-fail.md/;s/result=pass/result=fail/;}')"
fc_plan "$FC_FAILR"
poke "$RFC" current 8 --check
expect_eq "EARLY-6 precondition: the failing adversarial reading makes current 8 --check refuse" \
  "1|yes" "$RC|$(printf '%s\n' "$OUT" | /usr/bin/grep -q '^review	adversarial	.*failing' && echo yes || echo no)"
fc_page
expect_eq "EARLY-6b …and yet the page renders: the waiver settles it (exit 0, no refusal)" "0|" "$FC_RC|$FC_ERR"
expect_contains "EARLY-6e …the person's waiver item opened on the ledger" "waive:adversarial" "$(fc_owed)"
poke "$RFC" reply "$FC_WD"
expect_regex "EARLY-6f reply all default writes the waiver with the reply's words" \
  "^waived: question=adversarial head=$FC_R by Dana Fixture [0-9T:Z-]+ \"$FC_WD\"\$" "$(/usr/bin/grep '^waived: question=adversarial ' "$PFC")"
poke "$RFC" current 8 --check
expect_eq "EARLY-6g …after which current 8 --check is green" "0" "$RC"
fc_plan "$FC_FAILR"
printf 'release-check: bash tests/a.test.sh\n' > "$RFC/.bionic/config.yaml"
fc_page
expect_eq "EARLY-7 the failing reading beside an unheld release check no default settles: CARD-EARLY (exit 1)" \
  "1|CARD-EARLY — current 8 --check: would refuse|" "$FC_RC|$FC_ERR|$FC_OUT"
rm -f "$RFC/.bionic/config.yaml"
# THREE ROWS WITH NO AUDITOR CELL: the Step-6 gate refuses the first; the page offers all three as decisions.
fc_plan "$FC_GOOD"
awk '/^\| AC-1\.1 \|/ { print "| AC-1.1 | T1 | discharged | see AC-1.1 | |"; print "| AC-1.3 | T1 | discharged | see AC-1.3 | |"; print "| AC-1.4 | T1 | discharged | see AC-1.4 | |"; next }
  /^\| AC-1\.2 \|/ { print "| AC-1.2 | T1 | discharged | see AC-1.2 | CONFIRMED |"; next }
  { print }
  END { for (i = 3; i <= 4; i++) printf "AC-1.%d:\n  fails-when: planted defect %d\n  evidence: record/generic-evidence.md\n  tier-run: bash tests/a.test.sh\n  readback: the line it wrote\n", i, i }' \
  "$PFC" > "$PFC.new" && mv "$PFC.new" "$PFC"
poke "$RFC" current 6 --check
expect_contains "EARLY-8 precondition: current 6 --check refuses on a row the auditor has not confirmed" \
  "the auditor has not confirmed AC-1.1" "$OUT"
fc_page
expect_eq "EARLY-8b …and the page renders (exit 0, no refusal)" "0|" "$FC_RC|$FC_ERR"
expect_absent "EARLY-8d …and not the confirmed, discharged AC-1.2" "AC-1.2" "$(fc_under Decisions)"
poke "$RFC" reply "$FC_WD"
expect_eq "EARLY-8f reply all default waives the three rows" "waived waived waived" "$(fc_row AC-1.1) $(fc_row AC-1.3) $(fc_row AC-1.4)"
FC_CK=""; for fc_n in 6 7 8; do poke "$RFC" current "$fc_n" --check; FC_CK="$FC_CK$RC"; done
expect_eq "EARLY-8g …and current 6, 7 and 8 --check are then green" "000" "$FC_CK"
# THE STEP-8 APPROVAL REFUSAL IS THE PAGE'S OWN: in the release order the advance to 8 refuses first on the missing
# `approved: release` line, which is decision 7 of the page, so a run whose every other fact holds renders and puts both
# approvals. (The order is a test row at Step 5 and the release's doc row; the fixture's matrix is fully confirmed.)
fc_plan "$FC_GOOD" 's/^\(| AC-1\.2 | T1 \)| pending |/\1| discharged |/
/^| T1 | 4 | build/a\
| T4 | 5 | test | the regression | implementor | — | 30 | REQ-1 | — | — | — | landed | approval:plan |'
poke "$RFC" current 8 --check
FC_CK=""; for fc_n in 6 7; do poke "$RFC" current "$fc_n" --check; FC_CK="$FC_CK$RC"; done
poke "$RFC" current 8 --check
expect_eq "EARLY-9 precondition: current 6 and 7 --check are green, and current 8 --check refuses (exit 1) on the missing approval alone" \
  "001|1" "$FC_CK$RC|$(printf '%s\n' "$OUT" | /usr/bin/grep -c '^poker: REFUSED')"
expect_contains "EARLY-9a …naming the missing approved: release line" "carries no approved: release line" "$OUT"
fc_page
expect_eq "EARLY-9b …and the page renders (exit 0, no refusal, a page written)" "0||review-results-$FC_H8.md" "$FC_RC|$FC_ERR|$(fc_pages)"
expect_eq "EARLY-9c …putting the release approval and the merge approval" "approve:release approve:merge" \
  "$(fc_keys | /usr/bin/grep '^approve:' | tr '\n' ' ' | sed 's/ $//')"

# ============================================================
section "§PREVIEW: --preview renders an early run's page and records nothing"
# ============================================================
# fails-when: the preview refuses, records a page or opens an approval item, or does not say why the run is early.
fc_plan "$FC_GOOD" '/structure-whole/d'
fc_page --preview
expect_eq "PREV-1 the early run previews (exit 0, nothing on stderr)" "0|" "$FC_RC|$FC_ERR"
expect_eq "PREV-3 …every section printed" "Bottom line|Goals|Tests|Reviews|Findings|Decisions" "$(fc_heads)"
expect_eq "PREV-5 …no page written, no approval opened" "|" "$(fc_pages)|$(fc_owed | /usr/bin/grep '^approve:')"
fc_page
expect_eq "PREV-6 the same run without --preview is early (exit 1)" "1" "$FC_RC"
fc_plan "$FC_FAILR"
fc_page --preview
expect_eq "PREV-7b …and opens no item on the person's ledger, the finding's nor the waiver's" "" "$(fc_owed)"
fc_page
expect_contains "PREV-7c the acting render of the same run opens the finding's item (the reader is not vacuous)" \
  "finding:" "$(fc_owed)"

# ============================================================
section "§AGREE: the decisions are the owed items, the unproved rows and the findings recommended against (D7, D19)"
# ============================================================
# fails-when: the page offers an item the record does not owe, or leaves one out.
fc_plan "$FC_GOOD"
fc_owe approve:release; fc_owe approve:merge; fc_owe waive:structure
fc_expected() {  # -> the keys the sources owe, sorted: owed approvals and waivers but the regression, unproved rows, against
  { fc_owed | /usr/bin/grep -E '^(approve|waive):' | /usr/bin/grep -v '^waive:regression$'
    awk -F'|' '/^## /{ m = ($0 ~ /^## Verification Matrix/) } m && /^\| AC-/ { s = $4; gsub(/^[ \t]+|[ \t]+$/, "", s); a = $2; gsub(/^[ \t]+|[ \t]+$/, "", a)
      u = $6; gsub(/^[ \t]+|[ \t]+$/, "", u)
      if (s != "waived" && !(s == "discharged" && u == "CONFIRMED")) print "row:" a }' "$PFC"
    printf '%s\n' "$@"
  } | awk 'NF' | LC_ALL=C sort
}
fc_agree() {  # <record> <against key>... -> same or differs: the record's table keys against the sources'
  local r="$1"; shift
  if [ "$(awk -F'|' '/^review-results\/v1\|dec=/ { for (i = 2; i <= NF; i++) if (index($i, "key=") == 1) print substr($i, 5) }' "$r" | LC_ALL=C sort)" \
     = "$(fc_expected "$@")" ]; then echo same; else echo differs; fi
}
expect_eq "AGREE-0 precondition: the sources owe four items (two approvals, a waiver, the row)" \
  "approve:merge approve:release row:AC-1.2 waive:structure" "$(fc_expected | tr '\n' ' ' | sed 's/ $//')"
fc_page
expect_eq "AGREE-1 review-results renders (exit 0)" "0" "$FC_RC"
expect_eq "AGREE-2 the decisions are exactly the sources' items" "same" "$(fc_agree "$FC_REC/review-results-$FC_H8.md")"
expect_eq "AGREE-2b …one numbered line each" "4" "$(fc_under Decisions | /usr/bin/grep -cE '^[0-9]+\. ')"
expect_eq "AGREE-2c …in the order: waivers, rows, findings, approvals" \
  "waive:structure row:AC-1.2 approve:release approve:merge" "$(fc_keys | tr '\n' ' ' | sed 's/ $//')"
cp "$FC_REC/review-results-$FC_H8.md" "$TMPROOT/fc-planted.md"
printf 'review-results/v1|dec=5|key=approve:ship|default=approve ship|other=-|pick=default|why=-\n' >> "$TMPROOT/fc-planted.md"
expect_eq "AGREE-3 a planted extra decision goes red" "differs" "$(fc_agree "$TMPROOT/fc-planted.md")"
/usr/bin/grep -v '|key=row:AC-1.2|' "$FC_REC/review-results-$FC_H8.md" > "$TMPROOT/fc-dropped.md"
expect_eq "AGREE-3b …and so does a dropped one" "differs" "$(fc_agree "$TMPROOT/fc-dropped.md")"
fc_plan "$FC_GOOD"
fc_page --against "finding:$FC_FID"
expect_eq "AGREE-4 a finding recommended against joins the set" "same" "$(fc_agree "$FC_REC/review-results-$FC_H8.md" "finding:$FC_FID")"

# ============================================================
section "§REPLY: all default and all recommended replay into their verbs with the user's words; anything else writes nothing"
# ============================================================
# fails-when: a default or a recommendation is replayed into another verb or with other words; a reply that is not
# one of the two, words the user never typed, a stale page or no page at all writes a byte of the plan.
fc_plan "$FC_GOOD"
fc_page
cp "$PFC" "$TMPROOT/fc-before-reply"
poke "$RFC" reply "$FC_WD"
expect_eq "REPLY-1 reply all default replays the page (exit 0)" "0" "$RC"
[ "$RC" = 0 ] || printf '      reply said: %s\n' "$OUT"
expect_regex "REPLY-1b approved: release, by the git user, with the reply's words" \
  "^approved: release by Dana Fixture [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z( head=$FC_R)? \"$FC_WD\"\$" "$(/usr/bin/grep '^approved: release ' "$PFC")"
expect_regex "REPLY-1c approved: merge, the same" \
  "^approved: merge by Dana Fixture [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z( head=$FC_R)? \"$FC_WD\"\$" "$(/usr/bin/grep '^approved: merge ' "$PFC")"
expect_eq "REPLY-1d the unproved row's status is waived" "waived" "$(fc_row AC-1.2)"
expect_eq "REPLY-1f …the discharged row is untouched" "discharged" "$(fc_row AC-1.1)"
expect_contains "REPLY-1g the record keeps the reply" "replied: " "$(cat "$FC_REC/review-results-$FC_H8.md")"
expect_eq "REPLY-1h the reply closed the person's two approval items" "" "$(fc_owed | /usr/bin/grep '^approve:')"
fc_page
expect_eq "REPLY-2 a second render after the reply refuses nothing (exit 0)" "0|" "$FC_RC|$FC_ERR"
expect_contains "REPLY-2c …the Decisions say so" "None wait on you." "$(fc_under Decisions)"
expect_absent "REPLY-2d …offering no reply line" "Reply " "$FC_OUT"
expect_eq "REPLY-2e …and writes no second page" "review-results-$FC_H8.md" "$(fc_pages)"
fc_plan "$FC_GOOD"
fc_page --against approve:release
poke "$RFC" reply "$FC_WR"
expect_eq "REPLY-3 the orchestrator recommends holding the release; reply all recommended (exit 0)" "0" "$RC"
expect_eq "REPLY-3b …the release is not approved" "" "$(/usr/bin/grep '^approved: release ' "$PFC")"
expect_regex "REPLY-3c …every other recommendation applied with the user's words: the merge" \
  "^approved: merge by Dana Fixture [0-9T:Z-]+( head=$FC_R)? \"$FC_WR\"\$" "$(/usr/bin/grep '^approved: merge ' "$PFC")"
expect_eq "REPLY-3d …the row" "waived" "$(fc_row AC-1.2)"
expect_contains "REPLY-3e …and the reply says what it held back" "withheld: approve:release" "$OUT"
expect_contains "REPLY-3f …the person's approval item stays open" "approve:release" "$(fc_owed)"
fc_plan "$FC_GOOD"
fc_page --against "finding:$FC_FID"
poke "$RFC" reply "$FC_WR"
expect_eq "REPLY-4 the orchestrator recommends fixing the S3; reply all recommended (exit 0)" "0" "$RC"
[ "$RC" = 0 ] || printf '      reply said: %s\n' "$OUT"
expect_regex "REPLY-4b …the finding is moved to fix on the user's words" \
  "^moved: record/wave-x/adversarial\\.md#1 to=fix by=Dana Fixture at=[0-9T:Z-]+ words=\"$FC_WR\"( session=[^ ]+)? why=\"" "$(/usr/bin/grep -F "moved: $FC_FID " "$PFC")"
expect_eq "REPLY-4c …and both approvals are stamped with the same words" \
  "2" "$(/usr/bin/grep '^approved: ' "$PFC" | /usr/bin/grep -cF "\"$FC_WR\"")"
fc_plan "$FC_GOOD"
fc_page --against "finding:$FC_FID"
poke "$RFC" reply "$FC_WD"
expect_eq "REPLY-5 the same page, reply all default: the finding is carried, not moved" "0|" \
  "$RC|$(/usr/bin/grep -F "moved: $FC_FID " "$PFC")"
expect_contains "REPLY-5b …the carry recorded" "applied: finding:$FC_FID carried" "$(cat "$FC_REC/review-results-$FC_H8.md")"
fc_page --against "finding:$FC_FID"
expect_absent "REPLY-5c …and a carried finding is not put again" "a message could be clearer" "$(fc_under Decisions)"
expect_contains "REPLY-5d …it stays a line under Findings" "  S3   a message could be clearer" "$(fc_under Findings)"
fc_plan "$FC_GOOD"
fc_page
fc_typed "$FC_WD" "$FC_WR" 2 'ship it all now'
cp "$PFC" "$TMPROOT/fc-before"
poke "$RFC" reply 2
expect_eq "REPLY-6 a bare number: refused, exit 1, the plan byte-identical" "1|same" \
  "$RC|$(cmp -s "$TMPROOT/fc-before" "$PFC" && echo same || echo changed)"
expect_contains "REPLY-6b …naming the two replies there are" "all recommended" "$OUT"
poke "$RFC" reply 'ship it all now'
expect_eq "REPLY-7 a reply that is neither: refused, exit 1, the plan unchanged" "1|same" \
  "$RC|$(cmp -s "$TMPROOT/fc-before" "$PFC" && echo same || echo changed)"
fc_typed 'frame only'
poke "$RFC" reply "$FC_WD"
expect_eq "REPLY-8 words the user never typed: refused, exit 1, before any verb runs" "1|same" \
  "$RC|$(cmp -s "$TMPROOT/fc-before" "$PFC" && echo same || echo changed)"
fc_typed "$FC_WD" "$FC_WR"
s57_commit "$RFC" CHANGELOG.md 'a later release line' >/dev/null
poke "$RFC" reply "$FC_WD"
expect_eq "REPLY-9 the head moved since the page was rendered: refused, exit 1, the plan unchanged" "1|same" \
  "$RC|$(cmp -s "$TMPROOT/fc-before" "$PFC" && echo same || echo changed)"
expect_contains "REPLY-9b …saying to render it again" "review-results" "$OUT"
git -C "$RFC" reset -q --hard "$FC_R"
rm -f "$FC_REC"/review-results-*.md
poke "$RFC" reply "$FC_WD"
expect_eq "REPLY-10 no page rendered for the run: refused, exit 1, the plan unchanged" "1|same" \
  "$RC|$(cmp -s "$TMPROOT/fc-before" "$PFC" && echo same || echo changed)"
fc_plan "$FC_GOOD"
fc_owe waive:adversarial
fc_page
poke "$RFC" reply "$FC_WD"
expect_eq "REPLY-11 reply all default over an open waive:adversarial item exits 0" "0" "$RC"
expect_regex "REPLY-11b …writing the waiver at the working head with the reply's words" \
  "^waived: question=adversarial head=$FC_R by Dana Fixture [0-9T:Z-]+ \"$FC_WD\"\$" "$(/usr/bin/grep '^waived: question=adversarial ' "$PFC")"

# ============================================================
section "§BORN: two fix rows born of different questions' findings render the page with no re-read (AC-11.1)"
# ============================================================
# fails-when: the page prints `CARD-EARLY — <q> unregistered` after born rows alone; the fixed findings are not
# shown fixed by their rows.
fc_record structure structure piece 'finding: 1 S3 off lib/x.sh:1 the x writer repeats the y writer'
FC_F1="$(s57_commit "$RFC" lib/x.sh 'T4: the fix the adversarial reading asked for')"
FC_F2="$(s57_commit "$RFC" lib/x.sh 'T5: the fix the structure reading asked for')"
fc_published() {  # <row> <commit> -> a landing's events: its suites ready, its green verdict at the commit, published
  printf 'line/v1|ev=ready|row=%s|suites=tests/a.test.sh|at=2026-10-12T13:50:00Z\n' "$1"
  printf 'line/v1|ev=verdict|row=%s|commit=%s|suite=a.test.sh|result=green|log=/fixture/%s.log|at=2026-10-12T13:55:00Z\n' "$1" "$2" "$1"
  printf 'line/v1|ev=published|row=%s|commit=%s|kind=land|by=w-%s|why=landed|at=2026-10-12T14:00:00Z\n' "$1" "$2" "$1"
}
{ fc_published T4 "$FC_F1"; fc_published T5 "$FC_F2"; } > "$FC_REC/landing-proofs.log"
fc_born_plan() {  # -> PFC: FC_GOOD with T4 and T5 landed, born of the adversarial and the structure finding
  fc_plan "$FC_GOOD
- T4: landed $FC_F1 2026-10-12T14:00:00Z born: review S3 off of=record/wave-x/adversarial.md#1
- T5: landed $FC_F2 2026-10-12T14:00:00Z born: review S3 off of=record/wave-x/structure.md#1"
  awk '{ print } /^\| T2 \|/ {
    print "| T4 | 4 | build | fix the x message · born: review | implementor | — | 30 | REQ-1 | lib/x.sh | — | — | landed | approval:plan |"
    print "| T5 | 4 | build | fix the x writer · born: review | implementor | — | 30 | REQ-1 | lib/x.sh | — | — | landed | approval:plan |" }' \
    "$PFC" > "$PFC.new" && mv "$PFC.new" "$PFC"
}
fc_born_plan
expect_eq "BORN-0 precondition: the working head is T5's landing, two code commits past every reading" \
  "$FC_F2|lib/x.sh|lib/x.sh" \
  "$(git -C "$RFC" rev-parse wave/01-fixture)|$(git -C "$RFC" show --name-only --format= "$FC_F1")|$(git -C "$RFC" show --name-only --format= "$FC_F2")"
fc_page
expect_eq "BORN-1 review-results renders past the two born rows with no re-read: exit 0, nothing on stderr" "0|" "$FC_RC|$FC_ERR"
expect_eq "BORN-1b …and writes the page at T5's landing" "review-results-${FC_F2:0:8}.md" "$(fc_pages)"
expect_contains "BORN-1c …the two findings fixed by their rows" "Fixed by T4 and T5" "$(fc_under Findings)"
new_roster "$RFC"; forget_digest "$RFC"
poke "$RFC" tick
expect_contains "BORN-2 the tick, an integrate row open, says its WAIT line" "poker: WAIT T3" "$OUT"
expect_absent "BORN-2b …and no CARD-EARLY" "CARD-EARLY" "$OUT"
FC_F3="$(s57_commit "$RFC" lib/x.sh 'a code change no review bore')"
fc_born_plan
fc_page
expect_regex "BORN-3 the control: one code commit past the fixes that no row was born for is CARD-EARLY" \
  "^CARD-EARLY — (evidence|adversarial|structure) unregistered at ${FC_F3:0:8}\$" "$FC_ERR"
expect_eq "BORN-3b …exit 1, nothing rendered, no page written" "1||" "$FC_RC|$FC_OUT|$(fc_pages)"
git -C "$RFC" reset -q --hard "$FC_R"
rm -f "$FC_REC/landing-proofs.log" "$FC_REC"/review-results-*.md
fc_record structure structure piece

# ============================================================
section "§JUDGE: the Tests line names the floor judge's answer, not the whole run's red list"
# ============================================================
# fails-when: the page counts the suites a whole run left red after a later landing greened them, or says nothing
# of a suite still owed; the page's line and the judge disagree at the head the user approves from.
FC_F6="$(s57_commit "$RFC" lib/x.sh 'T6: the fix that greens a')"
fc_published T6 "$FC_F6" > "$FC_REC/landing-proofs.log"
fc_judge_plan() {  # <floor's owed suites> -> PFC: the whole run at C left <suites> red, T6 landed after it, born of the adversarial finding
  fc_plan "$(fc_floor "$FC_C" "$1")
$(fc_reads "$FC_C")
- T6: landed $FC_F6 2026-10-12T14:00:00Z born: review S3 off of=record/wave-x/adversarial.md#1"
  awk '{ print } /^\| T2 \|/ {
    print "| T6 | 4 | build | fix the x message · born: review | implementor | — | 30 | REQ-1 | lib/x.sh | — | — | landed | approval:plan |" }' \
    "$PFC" > "$PFC.new" && mv "$PFC.new" "$PFC"
}
fc_judge_plan a.test.sh
fc_page --preview
expect_contains "JUDGE-0 precondition: the Tests section renders a regression line" "regression — " "$(fc_under Tests)"
expect_contains "JUDGE-1 a red the whole run left and a later landing greened: the page reads covered" "covered" \
  "$(fc_under Tests | fc_flat)"
expect_eq "JUDGE-1b …and the word red is not on the line" "0" "$(fc_under Tests | fc_flat | /usr/bin/grep -cw 'red')"
git -C "$RFC" reset -q --hard "$FC_R"
rm -f "$FC_REC/landing-proofs.log"
fc_plan "$(fc_floor "$FC_C" a.test.sh)
$(fc_reads "$FC_C")"
fc_page --preview
expect_contains "JUDGE-2 the control: no landing greened it, the page names a.test.sh as still owed" "a.test.sh" \
  "$(fc_under Tests | fc_flat)"
expect_absent "JUDGE-2b …and does not read covered" "covered" "$(fc_under Tests | fc_flat)"
git -C "$RFC" reset -q --hard "$FC_R"
rm -f "$FC_REC/landing-proofs.log" "$FC_REC"/review-results-*.md

# ============================================================
section "§STEP0: card.sh step0 renders the configuration card in the 1.20.0 shape, ending on its question, and owes its reply (AC-20.1, AC-20.2; D3, D23)"
# ============================================================
{
  printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: double\nscale: wave\n'
  printf 'scale-recommendation: "Several rows in one session. The ask names five files."\nregression: yes\n'
  printf 'surface_type: cli-plugin\nmulti_agent: true\ndeploy_target: n/a\ncleanup_on_finish: true\nuse_worktree: false\n'
  printf 'walk: exempt\ndesign-interview: true\nmodel_plan: orchestrator=claude-fable-5-1\nseed: ideas/seed.md\n---\n'
  printf '# plan\n\n## Goal\n\nConfigure the fixture run, and nothing else.\n\n## SDLC State\n\ncurrent: 0\nworking-branch: wave/01-fixture\n'
} > "$PFC"
rm -f "$RFC/.bionic/tmp/owed-$SID.state"
bind_marker "$RFC" "$PFC"
fc_card step0
expect_eq "STEP0-1 AC-20.1 card.sh step0 <plan> exits 0, nothing on stderr, under the card's title" \
  "0||Step 0 · Plan Configuration" "$FC_RC|$FC_ERR|$(printf '%s\n' "$FC_OUT" | head -1)"
expect_eq "STEP0-2 …its sections in the 1.20.0 order" "Purpose|Seed|Run|Branches|Paths|Shape|Gates|Models" \
  "$(printf '%s\n' "$FC_OUT" | sed -n 's/^  \([A-Z][A-Za-z]*\)$/\1/p' | paste -sd'|' -)"
expect_eq "STEP0-6 rendered for the session's own run, it opens the person's approve:step0 item" "approve:step0" "$(fc_owed)"

finish
