# tests/release-approval.prelude.sh — the world and the helpers both parts of the release approval card's suite share.
# Sourced by tests/release-approval.test.sh and tests/release-approval-2.test.sh after resolve-roots.sh and assert.sh; not
# a suite. One file promised more than the suite bar (lib/line.sh LINE_SUITE_BAR), so it is cut at a section boundary.
# It holds the world and every helper above the old file's first section, plus `fc_published`, never a fixture one
# section builds for a later one; tests/asks.test.sh reads six of these helpers by name.
#
# THE SUITE (the old file's own header, whole):
# tests/release-approval.test.sh — THE RELEASE APPROVAL CARD: hooks/session-poker.sh `release-approval` and `reply`, and
# payload/scripts/card.sh `early`.
#
# WHAT IT HOLDS. The autonomous half of a run waits for its human once, at one page the tool renders from the
# record: Bottom line, Goals, Tests, Reviews, Findings and Decisions, in that order, padded plain text. A finding
# reaches Decisions only when it names a criterion that is not proved or when the orchestrator recommends against
# the policy's default (`--against <key>`); every other finding is one sentence under Findings, its severity code
# first, grouped fixed / awaiting your decision / carried. The regression is never waived: a head with no green
# whole run is early. A whole run behind the head is green only when nothing since moved code; otherwise merging
# without a pass at this head is the person's own decision (`approve:merge-unproved`). The page refuses to render,
# `CARD-EARLY — <reason>` on stderr and exit 1, while a reader row is open, an owed reading is unregistered at the head,
# or `current <N> --check` is red for N = 6, 7 or 8 (`card.sh early`); `--preview` renders it anyway and records
# nothing. The verb gathers the facts and `card.sh release` draws the page at the shared width. One
# reply, typed by the user, `all default`, `all recommended` or the decisions by number, is replayed by `reply` into
# approve, waive, waive-row, confirm-row and finding-move with the user's words.
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
  rm -f "$FC_REC"/release-approval-*.md "$FC_REC/${RN_W:-review}-results"-*.md "$RFC/.bionic/tmp/owed-$SID.state" "$FC_REC/asks.state" \
    "$(roster_of "$RFC")" "$(ack_ledger_of "$RFC")"
  bind_marker "$RFC" "$PFC"
}
# THE SETTLED RUN: the whole suite ran green at R, the head, so nothing about the merge is the person's to decide;
# the readings at C reach R by the release text's cover.
FC_GOOD="$(fc_floor "$FC_R")
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

fc_page() {  # [<arg>...] -> FC_RC, FC_OUT (stdout), FC_ERR (stderr) of `release-approval <arg>... <plan>`, as this session
  ( cd "$RFC" && exec env CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" release-approval "$@" "$PFC" ) > "$TMPROOT/fc.out" 2> "$TMPROOT/fc.err"
  FC_RC=$?; FC_OUT="$(cat "$TMPROOT/fc.out")"; FC_ERR="$(cat "$TMPROOT/fc.err")"
}
fc_card() {  # <verb> -> FC_RC, FC_OUT, FC_ERR of card.sh <verb> <plan>, run in the repository as this session
  ( cd "$RFC" && exec env CLAUDE_CODE_SESSION_ID="$SID" bash "$CARD" "$1" "$PFC" ) > "$TMPROOT/fc.out" 2> "$TMPROOT/fc.err"
  FC_RC=$?; FC_OUT="$(cat "$TMPROOT/fc.out")"; FC_ERR="$(cat "$TMPROOT/fc.err")"
}
fc_pages() { ( cd "$FC_REC" && ls release-approval-*.md 2>/dev/null ) | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'; }
fc_table() { /usr/bin/grep '^release-approval/v1|dec=' "$FC_REC/release-approval-$FC_H8.md" 2>/dev/null; }  # the record's replay table
fc_keys() { fc_table | awk -F'|' '{ for (i = 2; i <= NF; i++) if (index($i, "key=") == 1) print substr($i, 5) }'; }
fc_row() { /usr/bin/grep -E "^\| $1 \|" "$PFC" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $4); print $4 }'; }  # <AC> -> its status cell
fc_owed() { bash -c '. "$1/owed.sh"; OWED_ROOT="$2" OWED_SID="$3" owed_list' _ "$FC_LIB" "$RFC" "$SID" 2>/dev/null | cut -f1; }
fc_owe() { bash -c '. "$1/owed.sh"; OWED_ROOT="$2" OWED_SID="$3" owed_open "$4" "fixture: $4" "poker: fixture item $4"' _ "$FC_LIB" "$RFC" "$SID" "$1"; }
fc_heads() { printf '%s\n' "$FC_OUT" | sed -n -E 's/^(Bottom line|Goals|Tests|Reviews|Findings|Decisions)( — .*)?$/\1/p' | paste -sd'|' -; }
fc_flat() { tr '\n' ' ' | tr -s ' ' | sed 's/ $//'; }  # folded lines read as one, for a phrase the fold may break
fc_has() { case "$1" in *"$2"*) echo yes ;; esac; }  # <haystack> <needle> -> yes when it holds it
fc_under() {  # <section> -> the page's lines under that section head, to the next blank line
  printf '%s\n' "$FC_OUT" | awk -v h="$1" 'f && $0 == "" { exit } f { print } $0 == h || index($0, h " — ") == 1 { f = 1 }'
}

# THE LANDING'S EVENTS, as the line writes them (hoisted from part 1's §BORN; part 2's sections call it too).
fc_published() {  # <row> <commit> -> a landing's events: its suites ready, its green verdict at the commit, published
  printf 'line/v1|ev=ready|row=%s|suites=tests/a.test.sh|at=2026-10-12T13:50:00Z\n' "$1"
  printf 'line/v1|ev=verdict|row=%s|commit=%s|suite=a.test.sh|result=green|log=/fixture/%s.log|at=2026-10-12T13:55:00Z\n' "$1" "$2" "$1"
  printf 'line/v1|ev=published|row=%s|commit=%s|kind=land|by=w-%s|why=landed|at=2026-10-12T14:00:00Z\n' "$1" "$2" "$1"
}
