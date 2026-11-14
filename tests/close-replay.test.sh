#!/bin/bash
# Tests for a run rehearsed whole: a fresh project's run at version 15 played through commands alone from the skill's
# invocation and the configuration card to close-out's `delivered:` (tests/lib/rehearsal.sh `rehearse delivered`), its
# last stretch the replay of a failed review's close, in a sandbox whose project declares its real release check.
#
#   §E2E      the whole run: Steps 0 to 3 each on its card, its approval and its advance; every step and approval in
#             the log in order; every command exits 0 but the close the failing review refuses; every tool and poker
#             verb it calls is one the skills' text names
#   §CLOSE    the replay reaches delivered: through the verbs alone, close-out counting no hand-hold
#   §WINDOW   after the close, the hand-holds window ends at the delivery's instant, and a decline after the card counts
#   §SR       a second review naming the fix row's site is written fixed by its landing, no finding-move after it
#   §PR       the integrate row's pull request goes through a stand-in gh, the only gh on its PATH
#   §ENTRY    the release entry names the review the run failed and fixed; the record names each commit after the fix
#   §REAL     the sandbox's own real check ran, every hand write is of a kind a run writes, and the log is UTF-8
#   §LIVE     the plan's live criterion names the close row in its Task column, passes every advance past the Verify
#             gate pending, is owed by the close on the release approval card, and close-out proves it
#   §LOG      the landing record and the asks are events of the one log: no landing-proofs.log, no asks.state
#   §GROWS    the log kept after each command is a prefix of the next, and of the log at the close
#   §SESSION  the Patrol's arming and disarming write no line of the log, a tick only the run's facts, and none a stop
#   §PLANSUM  the plan's checksum is the same on both sides of every command
#   §VERBS    every command the poker lists is called by the rehearsal or a hook, or named in a skill or role file
#   §CANCEL   reopened at Step 8 by its log, close-out reads the release approved, and not once the log cancels it
#   §SINGLE   `rehearse single-verify` stands at step 5, its criterion discharged by the walk under the critic's review
#
# NAMED, NOT COUNTED: CL-8 names each verb the replay runs, so a log that lost one is red however long it is; the
# listing's commands and the texts' are read by one extractor (cr_verbs), never typed.
#
# ONE SANDBOX, READ BY EVERY SECTION BUT §SINGLE: `rehearse delivered` builds it once, under WORLD_ROOT; each command
# it ran is in its rehearsal.log, the replay's own after the `# replay:` line, with the run's log kept after each
# (logs/<n>.log) and the plan's checksum on each side (plan-sums). §SINGLE builds its own, beside it, in a subshell of
# its own, so nothing it sets reaches the replay's readers.
#
# FIXTURE FIDELITY: the sandbox is tests/lib/door.sh's project, a repository carrying the plugin's hooks and scripts
# and the release check's closure, with no plan; every state of the run is a command's. What `rehearse` writes by
# hand is tagged in the log with its kind (rehearsal.sh RH_HAND_KINDS), and §REAL reads those tags.
#
# ANTI-VACUITY: a state that cannot be reached stops its section before any read, asserting the failure. Every empty
# read (no refusal, no changed checksum, no line a tick wrote, no unnamed command) stands beside a non-empty read
# through the same extractor in the same section.
#
# EXPECTED TIME: about eleven minutes when the replay reaches delivered:; §SINGLE about a minute more.
#
# Usage: bash tests/close-replay.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
CR_LOADED=0
# shellcheck source=/dev/null
. "$(dirname "$0")/lib/rehearsal.sh" && CR_LOADED=1
[ -n "${WORLD_ROOT:-}" ] || . "$(dirname "$0")/lib/world.sh"

CR_DIR="$WORLD_ROOT/delivered"; CR_ROOT="$CR_DIR/project"; CR_LOG="$CR_DIR/rehearsal.log"
CR_REC="$CR_ROOT/.bionic/docs/record/wave-x"
CR_RC=0; CR_PLAN=""
if [ "$CR_LOADED" = 1 ]; then
  CR_PLAN="$(DOOR_LIVE_ROW=1 rehearse delivered "$CR_DIR" 2> "$WORLD_ROOT/delivered.err")" || CR_RC=$?
else
  CR_RC=127
fi
# The sandbox's paths as the rehearsal and the check record them: physical.
[ -d "$CR_DIR" ] && CR_DIR="$(cd "$CR_DIR" && pwd -P)" && CR_ROOT="$CR_DIR/project" && CR_LOG="$CR_DIR/rehearsal.log" \
  && CR_REC="$CR_ROOT/.bionic/docs/record/wave-x"

# cr_part -> the replay's part of the log: every line after its `# replay:` line
cr_part() { awk 'f { print } /^# replay:/ { f = 1 }' "$CR_LOG" 2>/dev/null; }
# cr_rc <label> -> the exit of each logged command carrying that label, one per line
cr_rc() { awk -v l="  (${1}, " 'index($0, l) && match($0, /^  rc=[0-9]+/) { print substr($0, 6, RLENGTH - 5) }' "$CR_LOG" 2>/dev/null; }
# cr_rcs -> each logged command's exit and label in the replay's part, as <rc>|<label>
cr_rcs() { cr_part | sed -n 's/^  rc=\([0-9][0-9]*\)  (\(.*\), [0-9][0-9]* s)$/\1|\2/p'; }
# cr_all_rcs -> each logged command of the whole run as <rc>|<label>, in the order run
cr_all_rcs() { sed -n 's/^  rc=\([0-9][0-9]*\)  (\(.*\), [0-9][0-9]* s)$/\1|\2/p' "$CR_LOG" 2>/dev/null; }
# cr_snaps -> the run's log as kept after each command, in the order kept
cr_snaps() { ls "$CR_DIR/logs" 2>/dev/null | LC_ALL=C sort -n | sed "s|^|$CR_DIR/logs/|"; }
# cr_verbs -> each poker verb the text on stdin names: `session-poker.sh <verb>`, or a code span opening with the verb
cr_verbs() { /usr/bin/grep -oE 'session-poker\.sh [a-z][a-z0-9-]*|`[a-z][a-z0-9-]*[ `]' | sed -E 's/^session-poker\.sh //; s/^`//; s/[ `]$//' | LC_ALL=C sort -u; }
# cr_skill_text -> the texts loaded to tell an actor what to do: the plugin's skills and the agents' role files;
# cr_skill_verbs -> the poker verbs they name
cr_skill_text() { cat "$BIONIC_SCRIPTS_DIR"/skills/*/SKILL.md "$BIONIC_SCRIPTS_DIR"/skills/canonical-sdlc/*.md "$BIONIC_SCRIPTS_DIR"/skills/canonical-sdlc/steps/*.md "$BIONIC_SCRIPTS_DIR"/agents/*.md 2>/dev/null; }
cr_skill_verbs() { cr_skill_text | cr_verbs; }
# cr_hook_verbs -> the poker verbs a hook or script a run executes calls: a call quotes the poker's path, `bash
# "…session-poker.sh" <verb>` or `bash "$poker" <verb>`, where a sentence it prints names the path bare
cr_hook_verbs() { /usr/bin/grep -rhoE 'bash "[^"]*(session-poker\.sh|\$\{?poker\}?)" +[a-z][a-z0-9-]*' "$BIONIC_SCRIPTS_DIR/hooks" "$BIONIC_SCRIPTS_DIR/payload/scripts" 2>/dev/null \
  | sed -E 's/^bash "[^"]*" +/session-poker.sh /' | cr_verbs; }
# cr_called -> each poker verb a command of the run calls
cr_called() { cr_names < "$CR_LOG" | cut -d'|' -f2 | sed -n 's/^session-poker\.sh \([a-z][a-z0-9-]*\).*/\1/p' | LC_ALL=C sort -u; }
# cr_marks <tag> -> the text of each `# <tag>: ` line in the replay's part
cr_marks() { cr_part | awk -v t="# ${1}: " 'index($0, t) == 1 { print substr($0, length(t) + 1) }'; }
# The verbs the replay runs (rehearsal.sh `_rh_replay`), each named `<tool> <verb>`: the tool the command runs and
# the first bare word of its arguments. A log missing any of them is a replay that did not run that verb, whatever its
# length. A refusal's follow is not listed: the replay meets one only when a verb refuses.
CR_VERBS='stop-orders.sh stopped|session-poker.sh task-add|spawn-worktree.sh create|execution-recorder.sh|spawn-worktree.sh ready|session-poker.sh release-check|session-poker.sh release-approval|session-poker.sh reply|session-poker.sh reviews-part|gh pr create|gh pr merge|close-out.sh run'
# The kinds of hand write the replay makes: the fix writer's launch, its code and report, the user's typed reply.
CR_HANDS='launch code record typed'
# cr_names -> for each `$ ` command line on stdin, `<rc>|<tool> <words>`: the tool is the first word naming a script
# (`*.sh`) or gh, its words every bare lowercase word after it (a path, a hash, a row id or a flag is none), and
# <rc> the exit on the `  rc=` line that closes the command's block. A command naming no tool prints nothing.
cr_names() {
  awk 'function out() { if (nm != "") print rc "|" nm; nm = ""; rc = "" }
    /^\$ / { out(); t = ""; v = ""
      for (i = 2; i <= NF; i++) {
        if (t == "") { if ($i ~ /\.sh$/ || $i ~ /(^|\/)gh$/) { t = $i; sub(/.*\//, "", t) }; continue }
        if ($i ~ /^[a-z][a-z-]*$/) v = v " " $i
      }
      nm = t v; next }
    /^  rc=[0-9]+  \(/ { if (nm != "") { rc = $1; sub(/^rc=/, "", rc); out() } }
    END { out() }'
}
# cr_held <a|b|...> -> of the names given, `|`-joined in their order, each that a line on stdin is or begins with
# (the name and a blank): the list again when every one is held
cr_held() {
  awk -v w="$1" 'BEGIN { n = split(w, want, "|") } { have[NR] = $0 }
    END { for (i = 1; i <= n; i++) for (j = 1; j <= NR; j++)
            if (have[j] == want[i] || index(have[j], want[i] " ") == 1) { printf "%s%s", s, want[i]; s = "|"; break }
          print "" }'
}
# cr_out <label> -> the output the log holds for the command carrying that label (the last such command)
cr_out() {
  awk -v l="  (${1}, " '
    /^\$ / { n = 0; delete o; next }
    /^  \| / { o[++n] = substr($0, 5); next }
    index($0, l) && /^  rc=/ { k = n; for (i = 1; i <= n; i++) r[i] = o[i] }
    END { for (i = 1; i <= k; i++) print r[i] }' "$CR_LOG" 2>/dev/null
}
# cr_ask <key> -> the newest act on <key> as <state>|<by>, read from the register, then the run's log, where an ask
# event's reply= is the act that closed it
cr_ask() {
  cat "$CR_REC/asks.state" "$CR_REC/run.log" 2>/dev/null | awk -F'|' -v k="key=$1" '
    ($1 == "owed/v1" && $2 == k) || ($1 == "run/v1" && $2 == "ev=ask" && $3 == k) { s = ($1 == "run/v1") ? "open" : ""; b = ""
      for (i = 3; i <= NF; i++) { if ($i ~ /^state=/) s = substr($i, 7); if ($i ~ /^by=/) b = substr($i, 4)
        if ($1 == "run/v1" && $i ~ /^reply=/) { s = "closed"; b = substr($i, 7) } }
      l = s "|" b } END { if (l != "") print l }'
}
cr_closer_is_waiver() {  # <by> -> yes when a waiver or close-out closed the ask, else no
  case "$1" in
    (waive|close-out*) echo yes ;;
    (*) echo no ;;
  esac
}
# cr_field <line> <key> -> the value of <key>= in a `|`-separated landing-record line
cr_field() { printf '%s\n' "$1" | awk -F'|' -v k="$2=" '{ for (i = 1; i <= NF; i++) if (index($i, k) == 1) { print substr($i, length(k) + 1); exit } }'; }
cr_lines() { cat "$CR_REC/landing-proofs.log" "$CR_REC/run.log" 2>/dev/null; }   # the landing record's lines, then the log's
# cr_part_event -> the last line naming a commit of the entry's reviews part, whichever verb wrote it
cr_part_event() { cr_lines | /usr/bin/grep '|part=reviews|' | tail -1; }
# cr_entry_part <changelog text on stdin> <version> -> the `### The reviews` part of that version's entry, heading
# to the next heading
cr_entry_part() {
  awk -v v="## $1 " '
    /^## / { inb = (index($0, v) == 1); inp = 0 }
    /^### / { t = $0; sub(/[[:space:]]+$/, "", t); inp = inb && (t == "### The reviews") }
    inp { print }'
}
# cr_proofs <plan> [<log>] -> the run's proofs through the proof library's readers, each in an older plan's line shape:
# the plan's own, then each proof event of <log>, the record's, which stays in the project when close-out archives the
# plan and so is joined to an archived plan by no reader
cr_proofs() { bash -c '. "$1/payload/scripts/lib/proof.sh" && proof_lines "$2" && { [ -z "$3" ] || awk -F"|" "$(proof_fact_awk)"'"'"'proof_fact() { print proof_fact_line() }'"'"' "$3"; }' \
  _ "$BIONIC_SCRIPTS_DIR" "$1" "${2:-}" 2>/dev/null; }
# cr_review_bullet <plan> <reader> -> the bullet the run's review proof by <reader> is listed as, built here from
# the proof's own fields: `- <question> review, <scope>: <result> at <head8> by <reader>, <at> (`<evidence file>`)`
cr_review_bullet() {
  cr_proofs "$1" "$CR_REC/run.log" | awk -v r="$2" '
    /^proved: kind=review / {
      q = ""; rd = ""; res = ""; sc = ""; h = ""; at = ""; ev = ""
      for (i = 2; i <= NF; i++) {
        if ($i ~ /^question=/) q = substr($i, 10)
        else if ($i ~ /^reader=/) rd = substr($i, 8)
        else if ($i ~ /^result=/) res = substr($i, 8)
        else if ($i ~ /^scope=/) sc = substr($i, 7)
        else if ($i ~ /^head=/) h = substr($i, 6)
        else if ($i ~ /^at=/) at = substr($i, 4)
        else if ($i ~ /^evidence=/) ev = substr($i, 10)
      }
      if (rd == r) { n = split(ev, e, "/"); b = sprintf("- %s review, %s: %s at %s by %s, %s (`%s`)", q, sc, res, substr(h, 1, 8), rd, at, e[n]) }
    }
    END { if (b != "") print b }'
}
# cr_back <cmd> [args] -> <cmd> [args] <plan>, the delivered plan put back where close-out read it for the call, so the
# readers join it to the run's log again; the copy is removed after
cr_back() {
  local p="$CR_ROOT/$DOOR_PLAN_REL" put="" rc
  [ -f "$p" ] || { mkdir -p "${p%/*}" && cp "$CR_PLAN" "$p" && put=yes; }
  "$@" "$p"; rc=$?
  [ -z "$put" ] || rm -f "$p"
  return "$rc"
}
cr_approved_head() { bash -c '. "$1/payload/scripts/lib/proof.sh" && proof_approved_head "$3" "$2"' _ "$BIONIC_SCRIPTS_DIR" "$1" "$2" 2>/dev/null; }
cr_reached() {  # -> 0 when the replay reached delivered:; else the failure asserted, with where it stopped
  [ "$CR_RC" = 0 ] && [ -f "$CR_PLAN" ] && return 0
  expect_eq "$1 the replay reached delivered: (rehearse exit 0), so this section can be read" "0" "$CR_RC"
  return 1
}

# ============================================================
section "§E2E: the whole run, from the configuration card to delivered, through commands alone"
# ============================================================
# fails-when: a gate refuses a step of the rehearsal, a step is entered with no card and approval before it, a step or
# an approval is missing from the run's log or out of its order, or a command the run takes is one the skills' text
# does not name.
expect_eq "E2-1 the run opens on the skill's invocation and the planner's page, then each of Steps 0 to 3 on its card, its approval and its advance, each exit 0" \
  "0|the skill is invoked: the session engages 0|the plan binds the session 0|the Step 0 card 0|approve step0 0|enter Step 1 0|the Step 1 card 0|approve step1 0|enter Step 2 0|the Step 2 card 0|approve step2 0|enter Step 3 0|the Step 3 card 0|approve plan 0|enter Step 4" \
  "$(cr_all_rcs | head -14 | paste -sd' ' -)"
expect_eq "E2-2 the run's log holds each step from 1 to 9 in order, and the approvals of Steps 0 to 2 and the plan's before Step 4" \
  "1 2 3 4 5 6 7 8 9|step0 step1 step2 step3" \
  "$(awk -F'|' '$2 == "ev=step" { n = $3; sub(/^n=/, "", n); if (n != l) printf "%s%s", (c++ ? " " : ""), n; l = n } END { print "" }' "$CR_REC/run.log" 2>/dev/null)|$(awk -F'|' '$2 == "ev=step" && $3 == "n=4" { exit } $2 == "ev=approval" { k = $3; sub(/^key=/, "", k); printf "%s%s", (c++ ? " " : ""), k } END { print "" }' "$CR_REC/run.log" 2>/dev/null)"
expect_eq "E2-3 every command of the run exits 0 but the close-out the failing review refuses (it ran $(cr_all_rcs | wc -l | tr -d ' ') commands)" \
  "close-out, refused on the failing review" "$(cr_all_rcs | awk -F'|' '$1 != 0 { print $2 }')"
E2_TOOLS="$(cr_names < "$CR_LOG" | cut -d'|' -f2 | awk '{ print $1 }' | LC_ALL=C sort -u)"; E2_TEXT="$(cr_skill_text)"; E2_NAMED="$(cr_skill_verbs)"
expect_contains "E2-4 the tools the run's commands name are read: the poker and the cards among them" "card.sh" "$E2_TOOLS"
expect_eq "E2-4b …and the skills' text names each of them and each poker verb the run calls" "" \
  "$(printf '%s\n' "$E2_TOOLS" | while IFS= read -r t; do [ -z "$t" ] || /usr/bin/grep -qF -- "$t" <<< "$E2_TEXT" || printf '%s ' "$t"; done
    cr_called | while IFS= read -r v; do /usr/bin/grep -qx -- "$v" <<< "$E2_NAMED" || printf '%s ' "$v"; done)"

# ============================================================
section "§CLOSE: from the failed-review state, the verbs alone reach delivered:"
# ============================================================
# fails-when: the replay stops before close-out's delivered:, reaches it only past a hand landing, hand merge, plan
# edit, step set back or waiver, or close-out counts a hand-hold.
expect_eq "CL-1 the replay reaches delivered: through the verbs (rehearse exit 0, the run's step 9 delivered and archived)" \
  "0|yes" "$CR_RC|$(/usr/bin/grep '|ev=step|n=9|' "$CR_REC/run.log" 2>/dev/null | tail -1 | /usr/bin/grep -q '|delivered=.*|archived=' && echo yes)"
if [ "$CR_RC" != 0 ]; then
  printf '    the replay stopped; rehearse said:\n'
  sed 's/^/    | /' "$WORLD_ROOT/delivered.err" 2>/dev/null | cut -c1-400 | tail -12
fi
if [ "$CR_RC" = 0 ] && [ -f "$CR_PLAN" ]; then
  CL_MAIN="$(git -C "$CR_ROOT" rev-parse --verify -q refs/heads/main)"
  # Main holds the reviews part's commit, rendered before the pull request on the head the check held and the user
  # approved; that head is the commit's one parent.
  CL_PART="$(cr_field "$(cr_part_event)" commit)"
  CL_REL="$(git -C "$CR_ROOT" rev-parse --verify -q "refs/heads/main^1" 2>/dev/null)"
  expect_eq "CL-2 the fix row born of the finding lands through ready, published by the line (kind=queue)" "0|queue" \
    "$(cr_rc 'the fix row says ready' | tail -1)|$(awk -F'|' '$2 == "ev=published" && $3 == "row=T5" { for (i = 4; i <= NF; i++) if ($i ~ /^kind=/) k = substr($i, 6) } END { print k }' <(cr_lines))"
  CL_W="$(cr_ask waive:structure)"
  expect_eq "CL-3 the structure review's waiver ask is on the register (read beside the next row)" "yes" \
    "$([ -n "$CL_W" ] && echo yes)"
  expect_eq "CL-3b …and closed, by neither a waiver nor close-out" "closed|no" \
    "${CL_W%%|*}|$(cr_closer_is_waiver "${CL_W#*|}")"
  expect_eq "CL-3c …its acts stand in the run's log as ask events, and the record holds no asks.state" "yes|" \
    "$(/usr/bin/grep -q '^run/v1|ev=ask|key=waive:structure|' "$CR_REC/run.log" 2>/dev/null && echo yes)|$(ls "$CR_REC/asks.state" 2>/dev/null)"
  expect_eq "CL-4 the release lands with the fix: its published event carries the line's release numbers commit" "yes" \
    "$(awk -F'|' '$2 == "ev=published" && $3 == "row=T5" && /\|numbers=[0-9a-f]{40}\|/ { f = 1 } END { if (f) print "yes" }' <(cr_lines))"
  expect_eq "CL-4b …and main holds the reviews part's commit, on the head the release check held (a kind=check line there, not result=fail)" "yes|yes|no" \
    "$([ -n "$CL_PART" ] && [ "$CL_PART" = "$CL_MAIN" ] && echo yes)|$([ -n "$CL_REL" ] && cr_proofs "$CR_PLAN" "$CR_REC/run.log" | /usr/bin/grep -q "^proved: kind=check head=$CL_REL " && echo yes)|$(cr_proofs "$CR_PLAN" "$CR_REC/run.log" | /usr/bin/grep "^proved: kind=check head=${CL_REL:-none} " | tail -1 | /usr/bin/grep -q 'result=fail' && echo yes || echo no)"
  expect_eq "CL-5 the user's reply approves that head: reply exit 0, and the run's approvals of release and merge-unproved (the fix landed past the whole run), asked of the proof library, name it" "0|$CL_REL|$CL_REL" \
    "$(cr_rc "the user's reply to the card at the fix's head" | tail -1)|$(for k in release merge-unproved; do cr_back cr_approved_head "$k"; done | paste -sd'|' -)"
  expect_eq "CL-6 close-out runs (exit 0) and lands the integrate row by one published event of the close kind, its row holding no status cell" "0|1|9|0" \
    "$(cr_rc 'close-out, the tail' | tail -1)|$(awk -F'|' '$2 == "ev=published" && $3 == "row=T4" && /\|kind=close\|by=close-out\|/ { n++ } END { print n + 0 }' <(cr_lines))|$(bash "$BIONIC_SCRIPTS_DIR/payload/scripts/reader.sh" "$CR_PLAN" row T4 | /usr/bin/grep -c '=')|$(bash "$BIONIC_SCRIPTS_DIR/payload/scripts/reader.sh" "$CR_PLAN" row T4 | /usr/bin/grep -c '^status=')"
  CL_HH="$(cr_out 'close-out, the tail' | /usr/bin/grep '^hand-holds: ')"
  expect_eq "CL-7 close-out prints its hand-holds line" "yes" "$([ -n "$CL_HH" ] && echo yes)"
  expect_contains "CL-7b …and it counts none" "hand-holds: total=0 " "$CL_HH"
  CL_CMDS="$(cr_part | /usr/bin/grep '^\$ ')"
  expect_eq "CL-8 the replay's part of the log holds a command for each verb the replay runs, named" "$CR_VERBS" \
    "$(cr_part | cr_names | cut -d'|' -f2- | cr_held "$CR_VERBS")"
  expect_eq "CL-8b …none a hand landing, a hand merge, a step set back or a waiver, and no hand write of the plan's prose" "" \
    "$(printf '%s\n' "$CL_CMDS" | /usr/bin/grep -E -- '--by-hand|session-poker\.sh current [0-7]( |$)|session-poker\.sh waive |git .*(fetch|merge|update-ref)'; cr_marks 'by hand' | /usr/bin/grep '^\[prose\]')"
fi

# ============================================================
section "§WINDOW: after the close, the hand-holds window ends at the delivery's instant, and an act after the card counts"
# ============================================================
# The window runs from the last build landing to `delivered:`; the release approval card ends nothing. The report read
# over the delivered plan names that end, and a decline planted a second after the card's replay time is counted.
# fails-when: the end is the card again, so the ends line names the page and the planted decline is outside.
# close-out archived the plan outside the project, where no project root names the record, so the report reads a copy
# put back where the plan stood when close-out read it, and the copy is removed after.
cr_hh() {  # -> landing-report --hand-holds over the delivered plan, as the replay's verbs run it
  cr_back door_run "$CR_ROOT" bash "$CR_ROOT/hooks/session-poker.sh" landing-report --hand-holds
  printf '%s\n' "$DOOR_OUT"
}
if cr_reached "WINDOW-0"; then
  CW_DEL="$(awk -F'|' '/\|ev=step\|n=9\|/ { for (i = 3; i <= NF; i++) if ($i ~ /^at=/) t = substr($i, 4) } END { print t }' "$CR_REC/run.log" 2>/dev/null)"
  CW_CARD="$(cat "$CR_REC"/release-approval-*.md 2>/dev/null | sed -n 's/^release-approval\/v1|plan=.*|at=\([^|]*\)|.*/\1/p' | LC_ALL=C sort | tail -1)"
  expect_eq "WINDOW-0 precondition: the run's log names the delivery's second and the record a release approval card's time" "yes|yes" \
    "$(printf '%s' "$CW_DEL" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' && echo yes)|$([ -n "$CW_CARD" ] && echo yes)"
  CW_OUT="$(cr_hh)"
  expect_contains "WINDOW-1 the ends line names the delivery's instant as the window's end" \
    "until ${CW_DEL/%:00Z/Z} (delivered:)" "$(printf '%s\n' "$CW_OUT" | grep '^hand-holds window: ')"
  CW_D0="$(printf '%s\n' "$CW_OUT" | grep '^hand-holds: ' | sed -n 's/.* declines=\([0-9]*\) .*/\1/p')"
  CW_AFTER="$(date -u -j -v+1S -f '%Y-%m-%dT%H:%M:%SZ' "$CW_CARD" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "$CW_CARD + 1 second" +%Y-%m-%dT%H:%M:%SZ)"
  cp "$CR_REC/fill-ledger.log" "$WORLD_ROOT/fill-ledger.kept" 2>/dev/null || : > "$WORLD_ROOT/fill-ledger.kept"
  printf 'fill-ledger/v1|at=%s|session=replay|turn=|current=9|state=decline|ceiling=6|width=|open=|free=|ready=T9|launched=|declined=no room|missed=0|idle=|room=|named=T9\n' "$CW_AFTER" >> "$CR_REC/fill-ledger.log"
  expect_eq "WINDOW-2 a decline a second after the card is inside the window: the count reads one decline more" \
    "$(( ${CW_D0:-0} + 1 ))" "$(cr_hh | grep '^hand-holds: ' | sed -n 's/.* declines=\([0-9]*\) .*/\1/p')"
  cp "$WORLD_ROOT/fill-ledger.kept" "$CR_REC/fill-ledger.log"
fi

# ============================================================
section "§SR: a second record at the fix row's site is settled by the fix row's landing, with no move after it"
# ============================================================
# fails-when: the second record names another site, the replay's log shows a finding-move after the fix row's landing,
# the second finding is not written fixed by the landing, or the close reads above zero.
if cr_reached "SR-0"; then
  SR_A="$(/usr/bin/grep '^finding: 1 ' "$CR_REC/w-structure-whole-2.md" 2>/dev/null | awk '{ print $5 }')"
  SR_B="$(/usr/bin/grep '^finding: 1 ' "$CR_REC/w-adversarial-whole-2.md" 2>/dev/null | awk '{ print $5 }')"
  expect_eq "SR-1 the replay plants a second review, registered under adversarial, naming the fix row's site" "yes|$SR_A" \
    "$(cr_proofs "$CR_PLAN" "$CR_REC/run.log" | /usr/bin/grep -q '^proved: kind=review .*evidence=record/wave-x/w-adversarial-whole-2.md question=adversarial ' && echo yes)|$SR_B"
  expect_contains "SR-1b …the site is a line of the library the fix answers" "payload/scripts/lib/said.sh:" "$SR_A"
  SR_AFTER="$(cr_part | awk '/^\$ / { c = $0; next } /^  rc=[0-9]+  \(the fix row says ready, / { f = 1; next } f && /^  rc=/ { print c }')"
  expect_contains "SR-2 commands follow the fix row's landing in the replay's log (read beside the moves)" "close-out.sh" "$SR_AFTER"
  expect_eq "SR-2b …and none of them is a finding-move" "" "$(printf '%s\n' "$SR_AFTER" | /usr/bin/grep 'session-poker\.sh finding-move')"
  expect_eq "SR-3 the second finding is written fixed by the fix row's landing" "yes" \
    "$(/usr/bin/grep -qF 'run/v1|ev=finding|ref=record/wave-x/w-adversarial-whole-2.md#1|to=fixed|row=T5|by=landing|' "$CR_REC/run.log" && echo yes)"
  expect_contains "SR-4 the close reads zero with the window at delivered:" "hand-holds: total=0 " \
    "$(cr_out 'close-out, the tail' | /usr/bin/grep '^hand-holds: ')"
fi

# ============================================================
section "§PR: the integrate row's pull request goes through a stand-in gh"
# ============================================================
# fails-when: the replay never reaches the pull request, another gh is on the integrate row's PATH, or the stand-in's
# log does not hold the pull request against main from the working branch.
if [ -n "$(cr_rc 'the integrate row opens the pull request')" ]; then
  expect_eq "PR-1 the integrate row's gh call exits 0 and is answered with the stand-in's address" "0|https://example.invalid/pull/1" \
    "$(cr_rc 'the integrate row opens the pull request' | tail -1)|$(cr_out 'the integrate row opens the pull request' | tail -1)"
  expect_contains "PR-2 the stand-in's log holds the pull request from the working branch into main" \
    "pr create --base main --head $DOOR_BRANCH" "$(cat "$CR_DIR/bin/gh.log" 2>/dev/null)"
  expect_eq "PR-3 the stand-in is the only gh on that PATH" "gh is $CR_DIR/bin/gh" \
    "$(cr_out "the gh on the integrate row's PATH")"
  expect_eq "PR-4 the person's merge through it leaves main holding the reviews part's commit, whose parent is the head the release check held" "0|yes|yes" \
    "$(cr_rc 'the person merges the pull request' | tail -1)|$([ "$(cr_field "$(cr_part_event)" commit)" = "$(git -C "$CR_ROOT" rev-parse --verify -q refs/heads/main)" ] && echo yes)|$(cr_proofs "$CR_PLAN" "$CR_REC/run.log" | /usr/bin/grep -q "^proved: kind=check head=$(git -C "$CR_ROOT" rev-parse --verify -q 'refs/heads/main^1' 2>/dev/null) " && echo yes)"
else
  expect_eq "PR-0 the replay reached the integrate row's pull request, so this section can be read" "reached" "not reached"
fi

# ============================================================
section "§ENTRY: the release entry names the review the run failed and fixed, and the record names every commit after the fix"
# ============================================================
# fails-when: the replay stops before close-out, the working branch's release entry or main's after the merge lacks
# the reviews part as the plan registered the failing review, the part lists a different number of reviews than the
# plan registers, the part was written by another than the integrate row, or the branch holds a commit after the fix's
# landing that no published event and no event writing the part names.
if cr_reached "EN-0"; then
  EN_BR="$(sed -n 's/^working-branch:[[:space:]]*//p' "$CR_PLAN" | head -1)"
  EN_VER="$(sed -n 's/^release:[[:space:]]*//p' "$CR_PLAN" | head -1)"
  EN_PART="$(git -C "$CR_ROOT" show "refs/heads/$EN_BR:CHANGELOG.md" 2>/dev/null | cr_entry_part "$EN_VER")"
  EN_WANT="$(cr_review_bullet "$CR_PLAN" w-structure-whole-2)"
  expect_eq "EN-1 the plan's proof line for the failing review is read: a bullet is built from its fields" "yes" \
    "$([ -n "$EN_WANT" ] && echo yes)"
  expect_contains "EN-1b …and it reads as the failing structure review of the whole" "- structure review, whole: fail at " "$EN_WANT"
  expect_eq "EN-2 the working branch's release entry holds a reviews part at its final head" "### The reviews" \
    "$(printf '%s\n' "$EN_PART" | sed -n 1p)"
  expect_eq "EN-3 …and lists the failed review exactly as the plan registered it" "$EN_WANT" \
    "$([ -n "$EN_WANT" ] && printf '%s\n' "$EN_PART" | /usr/bin/grep -x -F -- "$EN_WANT")"
  EN_PLAN_N="$(cr_proofs "$CR_PLAN" "$CR_REC/run.log" | /usr/bin/grep -c '^proved: kind=review ')"
  EN_PLAN_N=$((EN_PLAN_N + $(cat "$CR_REC/run.log" 2>/dev/null | /usr/bin/grep -c '^run/v1|ev=waiver|')))
  expect_eq "EN-4 the part lists as many reviews and waivers as the run registers, its reviews and its waivers both in its log (it registers some)" "$EN_PLAN_N|yes" \
    "$(printf '%s\n' "$EN_PART" | /usr/bin/grep -c '^- ')|$([ "$EN_PLAN_N" -ge 1 ] && echo yes)"
  EN_MAIN="$(git -C "$CR_ROOT" show "refs/heads/main:CHANGELOG.md" 2>/dev/null | cr_entry_part "$EN_VER")"
  expect_eq "EN-2m main's release entry holds the reviews part after the person's merge" "### The reviews" \
    "$(printf '%s\n' "$EN_MAIN" | sed -n 1p)"
  expect_eq "EN-3m …and lists the failed review exactly as the plan registered it" "$EN_WANT" \
    "$([ -n "$EN_WANT" ] && printf '%s\n' "$EN_MAIN" | /usr/bin/grep -x -F -- "$EN_WANT")"
  EN_WROTE="$(cr_part_event)"
  expect_eq "EN-4m the part was written by the integrate row before its pull request (a published part, by T4, no row)" \
    "ev=published|T4|" "$(printf '%s\n' "$EN_WROTE" | awk -F'|' '{ print $2 }')|$(cr_field "$EN_WROTE" by)|$(cr_field "$EN_WROTE" row)"
  EN_PUB="$(cr_lines | awk -F'|' '$2 == "ev=published" && $3 == "row=T5"' | tail -1)"
  EN_FIX="$(cr_field "$EN_PUB" numbers)"; [ -n "$EN_FIX" ] || EN_FIX="$(cr_field "$EN_PUB" commit)"
  EN_ON="$([ -n "$EN_FIX" ] && git -C "$CR_ROOT" merge-base --is-ancestor "$EN_FIX" "refs/heads/$EN_BR" 2>/dev/null && echo yes)"
  expect_eq "EN-5 the record names where the fix row's landing put the branch, and that commit is on the branch" "yes" "$EN_ON"
  EN_AFTER=""; [ "$EN_ON" != yes ] || EN_AFTER="$(git -C "$CR_ROOT" rev-list "$EN_FIX..refs/heads/$EN_BR" 2>/dev/null)"
  EN_NAMED="$(awk -F'|' '$2 == "ev=published" || /\|part=reviews\|/ {
      for (i = 3; i <= NF; i++) if ($i ~ /^(commit|numbers)=[0-9a-f]+$/) print substr($i, index($i, "=") + 1) }' <(cr_lines))"
  expect_eq "EN-6 commits follow the fix on the branch (read beside the unnamed ones)" "yes" \
    "$([ "$(printf '%s\n' "$EN_AFTER" | /usr/bin/grep -c .)" -ge 1 ] && echo yes)"
  expect_eq "EN-6b …and each is named in the landing record by a published event or the event that wrote the part" "" \
    "$(printf '%s\n' "$EN_AFTER" | while IFS= read -r c; do
        [ -z "$c" ] || printf '%s\n' "$EN_NAMED" | /usr/bin/grep -q -x -F -- "$c" || printf '%s\n' "$c"; done)"
  expect_eq "EN-6c …among them the branch's final head, named by the event that wrote the reviews part" \
    "$(git -C "$CR_ROOT" rev-parse --verify -q "refs/heads/$EN_BR")" "$(cr_field "$EN_WROTE" commit)"
fi

# ============================================================
section "§REAL: the sandbox declares the project's real check, and nothing a verb writes is written by hand"
# ============================================================
# fails-when: the sandbox declares a stand-in check, the check that ran is not the sandbox's own copy, or a hand
# write in the log is of a kind a person does not write or names a file a verb writes, or a line of the log is not
# valid UTF-8.
if [ -f "$CR_ROOT/.bionic/config.yaml" ] && [ -s "$CR_LOG" ]; then
  RE_CMD="$(sed -n 's/^release-check:[[:space:]]*//p' "$CR_ROOT/.bionic/config.yaml")"
  expect_eq "RE-1 the config declares the sandbox's release check, the file its repository commits" \
    "bash tests/lib/release-check.sh|tests/lib/release-check.sh" \
    "${RE_CMD% *}|$(git -C "$CR_ROOT" ls-files tests/lib/release-check.sh)"
  RE_SEEN="$(door_seen | /usr/bin/grep -F "script=$CR_DIR/" | /usr/bin/grep -c '/tests/lib/release-check\.sh$')"
  expect_eq "RE-2 the sandbox's own copy of the check ran (its sentinel holds a run of it)" "yes" \
    "$([ "${RE_SEEN:-0}" -ge 1 ] && echo yes)"
  RE_LOGS="$(cat "$CR_REC"/release-check-*.log 2>/dev/null | /usr/bin/grep '^command: ')"
  expect_eq "RE-3 the release check verb's logs name the command it ran" "yes" "$([ -n "$RE_LOGS" ] && echo yes)"
  expect_eq "RE-3b …and every one ran the declared check" "" \
    "$(printf '%s\n' "$RE_LOGS" | /usr/bin/grep -v -F "command: $RE_CMD")"
  RE_HAND="$(/usr/bin/grep '^# by hand: ' "$CR_LOG")"
  expect_eq "RE-4 the log tags each hand write with its kind: a row's code and an agent's record among them" "yes|yes" \
    "$(printf '%s\n' "$RE_HAND" | /usr/bin/grep -q '^# by hand: \[code\] ' && echo yes)|$(printf '%s\n' "$RE_HAND" | /usr/bin/grep -q '^# by hand: \[record\] ' && echo yes)"
  expect_eq "RE-4b …and every kind is one of $RH_HAND_KINDS" "" \
    "$(printf '%s\n' "$RE_HAND" | while IFS= read -r h; do k="${h#\# by hand: [}"; k="${k%%]*}"
        case " $RH_HAND_KINDS " in (*" $k "*) : ;; (*) printf '%s\n' "$h" ;; esac; done)"
  expect_eq "RE-5 no hand write names a file or a line a verb writes" "" \
    "$(printf '%s\n' "$RE_HAND" | /usr/bin/grep -E 'asks\.state|landing-proofs\.log|proved:|approved: |current:|- Step [0-9]|Dispatch ledger|## Tasks')"
  # A line no UTF-8 reader can decode stops macOS awk partway through the log, so the rows reading the replay's
  # part would read nothing and name the wrong cause; this row names it.
  expect_eq "RE-6 the log is text its readers can decode: valid UTF-8 throughout, the replay's part among them (iconv exit 0)" \
    "0" "$(/usr/bin/iconv -f UTF-8 -t UTF-8 "$CR_LOG" >/dev/null 2>&1; echo $?)"
else
  expect_eq "RE-0 the sandbox and its log were built, so this section can be read" "built" "not built"
fi

# ============================================================
section "§LIVE: the run's live criterion is owed at the close, passes every gate before it pending, and the close writes it"
# ============================================================
# The replay's plan carries the live criterion a planner writes (DOOR_LIVE_ROW): an Eval design row of live type, its
# eval the hand-holds line at the close, its Task cell the close row T9. The gate defers it until that row's step, so
# each advance and the refused close-out pass with it pending; the release approval card lists it owed by the close,
# never a decision its reply could waive; close-out proves it from its last reading after delivered:.
# fails-when: an advance or the card refuses or waives the pending row, or the run's log holds no proof naming it
# with the continuation as its evidence.
if cr_reached "LV-0"; then
  expect_eq "LV-1 the plan's live criterion is the planner's: its Eval design row names the close row in its Task cell, its eval the hand-holds line" "yes|yes" \
    "$(bash "$BIONIC_SCRIPTS_DIR/payload/scripts/reader.sh" "$CR_PLAN" criterion AC-2.1 | /usr/bin/grep -qx 'task=T9' && echo yes)|$(bash "$BIONIC_SCRIPTS_DIR/payload/scripts/reader.sh" "$CR_PLAN" criterion AC-2.1 | /usr/bin/grep -q '^eval=.*landing-report --hand-holds' && echo yes)"
  expect_eq "LV-2 each advance past the Verify gate exits 0 with the row pending" "0|0|0" \
    "$(cr_rc 'enter Step 6' | tail -1)|$(cr_rc 'enter Step 7' | tail -1)|$(cr_rc 'enter Step 8' | tail -1)"
  LV_CARD="$(cat "$CR_REC"/release-approval-*.md 2>/dev/null)"
  expect_eq "LV-3 the release approval card lists it owed by the close, and puts no decision on it" "yes|no" \
    "$(/usr/bin/grep -q 'owed by the close' <<< "$LV_CARD" && echo yes || echo no)|$(/usr/bin/grep -q 'key=row:AC-2\.1|' <<< "$LV_CARD" && echo yes || echo no)"
  expect_eq "LV-4 at delivered: the run's log holds one proof naming it, its evidence the continuation" \
    "1" "$(/usr/bin/grep -c '|ev=proof|ac=AC-2\.1|evidence=record/wave-x/continuation\.md|' "$CR_REC/run.log")"
  expect_contains "LV-5 …written by close-out from its last reading" "matrix: AC-2.1 discharged" "$(cr_out 'close-out, the tail')"
fi

# ============================================================
section "§LOG: the landing record and the asks are events of the one log"
# ============================================================
# fails-when: the record holds a landing-proofs.log or an asks.state, or the run's log lacks a landing's events or the
# asks' opening and closing.
if cr_reached "LG-0"; then
  expect_eq "LG-1 the log holds T5's landing, its ready, candidate, verdict and published events, and of run.log, landing-proofs.log and asks.state the record holds run.log alone" \
    "ready candidate verdict published|run.log" \
    "$(awk -F'|' '$3 == "row=T5" && $2 ~ /^ev=(ready|candidate|verdict|published)$/ { e = substr($2, 4); if (!(e in s)) { s[e] = 1; printf "%s%s", (c++ ? " " : ""), e } } END { print "" }' "$CR_REC/run.log" 2>/dev/null)|$(cd "$CR_REC" 2>/dev/null && ls run.log landing-proofs.log asks.state 2>/dev/null | paste -sd' ' -)"
  expect_eq "LG-2 each card's ask is opened and closed in the log by the approval it asked: approve:step0 to approve:step3" \
    "approve:step0>approve step0 approve:step1>approve step1 approve:step2>approve step2 approve:step3>approve plan" \
    "$(awk -F'|' '$2 == "ev=ask" && $3 ~ /^key=approve:step[0-3]$/ && $4 ~ /^reply=/ { k = substr($3, 5); r = substr($4, 7); printf "%s%s>%s", (c++ ? " " : ""), k, r } END { print "" }' "$CR_REC/run.log" 2>/dev/null)"
fi

# ============================================================
section "§GROWS: the log only grows"
# ============================================================
# fails-when: the log kept after a command is not a prefix of the log kept after the next, or of the log at the close.
CG_N="$(cr_snaps | wc -l | tr -d ' ')"
expect_eq "GR-1 a log is kept after each command of the run (it kept $CG_N), and the log at the close is longer than the first one kept" "yes|yes" \
  "$([ "$CG_N" -ge 1 ] && [ "$CG_N" -eq "$(cr_all_rcs | wc -l | tr -d ' ')" ] && echo yes)|$([ "$(wc -c < "$CR_REC/run.log" 2>/dev/null || echo 0)" -gt "$(cr_snaps | while IFS= read -r f; do [ -s "$f" ] && { wc -c < "$f"; break; }; done)" ] 2>/dev/null && echo yes)"
expect_eq "GR-2 each log kept is a prefix of the next, and the last of the log at the close" "" \
  "$( { cr_snaps; printf '%s\n' "$CR_REC/run.log"; } | { p=""; while IFS= read -r f; do
      [ ! -s "$p" ] || head -c "$(wc -c < "$p")" "$f" 2>/dev/null | cmp -s - "$p" || printf '%s ' "${p##*/}"; p="$f"; done; })"

# ============================================================
section "§SESSION: a session's own bookkeeping stays out of the log"
# ============================================================
# fails-when: the log holds a line for a Patrol tick, the Patrol's arming or a stop order: a stop event, a line the
# arming or the disarming wrote, or a line a tick wrote that is not one of the run's own facts.
CS_ACTS="$(cr_all_rcs | awk -F'|' '$2 ~ /^the skill is invoked|, tick [0-9]+$|^the Patrol is disarmed/ { print NR "|" $2 }')"
# cs_added <n> -> the lines the command numbered <n> added to the run's log, from the logs kept on each side of it
cs_added() { local b="$CR_DIR/logs/$(($1 - 1)).log"; [ "$1" -gt 1 ] || b=/dev/null; diff "$b" "$CR_DIR/logs/$1.log" 2>/dev/null | sed -n 's/^> //p'; }
expect_eq "CS-1 the run engages (which arms the Patrol), ticks and disarms, each a command of the run" "yes|yes|yes" \
  "$(printf '%s\n' "$CS_ACTS" | /usr/bin/grep -q '|the skill is invoked' && echo yes)|$(printf '%s\n' "$CS_ACTS" | /usr/bin/grep -q ', tick [0-9]*$' && echo yes)|$(printf '%s\n' "$CS_ACTS" | /usr/bin/grep -q '|the Patrol is disarmed' && echo yes)"
CS_TICKS="$(printf '%s\n' "$CS_ACTS" | /usr/bin/grep ', tick [0-9]*$' | while IFS='|' read -r n l; do cs_added "$n"; done)"
expect_eq "CS-2 what a tick adds is the run's own facts, the regression row it landed among them, never a stop or a line of its own" "yes|" \
  "$(/usr/bin/grep -q '^run/v1|ev=published|row=T3|' <<< "$CS_TICKS" && echo yes)|$(/usr/bin/grep -E -v '^run/v1\|ev=[a-z]+\|' <<< "$CS_TICKS"; /usr/bin/grep '^run/v1|ev=stop|' <<< "$CS_TICKS")"
expect_eq "CS-2b …and the arming and the disarming add no line" "" \
  "$(printf '%s\n' "$CS_ACTS" | /usr/bin/grep -v ', tick [0-9]*$' | while IFS='|' read -r n l; do [ -z "$n" ] || [ -z "$(cs_added "$n")" ] || printf '%s; ' "$l"; done)"
expect_eq "CS-3 the log's events are read (it holds step events) and none is a stop" "yes|0" \
  "$(/usr/bin/grep -q '^run/v1|ev=step|' "$CR_REC/run.log" 2>/dev/null && echo yes)|$(/usr/bin/grep -c '^run/v1|ev=stop|' "$CR_REC/run.log" 2>/dev/null)"

# ============================================================
section "§PLANSUM: no command changes the plan"
# ============================================================
# fails-when: the plan's checksum differs across any command of the run, close-out's archiving among them.
CP_SUMS="$(cat "$CR_DIR/plan-sums" 2>/dev/null)"
expect_eq "PS-1 the plan's checksum is read on each side of every command, and the page grew between Step 0 and Step 4 by its person's hand" "yes|yes" \
  "$([ "$(printf '%s\n' "$CP_SUMS" | /usr/bin/grep -c .)" -eq "$(cr_all_rcs | wc -l | tr -d ' ')" ] && echo yes)|$([ "$(printf '%s\n' "$CP_SUMS" | awk -F'|' '$1 == "the Step 0 card" { print $3 }')" != "$(printf '%s\n' "$CP_SUMS" | awk -F'|' '$1 == "enter Step 4" { print $3 }')" ] && echo yes)"
expect_eq "PS-2 …and no command changed it" "" "$(printf '%s\n' "$CP_SUMS" | awk -F'|' '$2 != $3 { print $1 }')"

# ============================================================
section "§VERBS: every command the poker lists is one a run needs"
# ============================================================
# fails-when: a command the poker's listing prints is neither called by the rehearsal, nor called by a hook or script a
# run executes, nor named in a text loaded to tell an actor what to do (a skill of the plugin or an agent's role file).
VB_LIST="$(bash "$BIONIC_SCRIPTS_DIR/hooks/session-poker.sh" 2>&1 | cr_verbs)"
VB_OF() { printf '%s\n' "$VB_LIST" | while IFS= read -r v; do printf '%s\n' "$1" | /usr/bin/grep -qx -- "$v" && printf '%s ' "$v"; done; }
VB_RH="$(cr_called)"; VB_HK="$(cr_hook_verbs)"; VB_TX="$(cr_skill_verbs)"
printf '    the listing: %s\n    called by the rehearsal: %s\n    called by a hook or script: %s\n    named in a skill or role file: %s\n' \
  "$(printf '%s\n' "$VB_LIST" | paste -sd' ' -)" "$(VB_OF "$VB_RH")" "$(VB_OF "$VB_HK")" "$(VB_OF "$VB_TX")"
expect_eq "VB-1 the listing and each proof's source are read by the one extractor: approve listed, the rehearsal calls current, a hook calls interval, a text names approve" \
  "yes|yes|yes|yes" "$(printf '%s\n' "$VB_LIST" | /usr/bin/grep -qx approve && echo yes)|$(printf '%s\n' "$VB_RH" | /usr/bin/grep -qx current && echo yes)|$(printf '%s\n' "$VB_HK" | /usr/bin/grep -qx interval && echo yes)|$(printf '%s\n' "$VB_TX" | /usr/bin/grep -qx approve && echo yes)"
expect_eq "VB-2 each command it lists is called by the rehearsal, called by a hook or script a run executes, or named in a skill or role file" "" \
  "$(printf '%s\n' "$VB_LIST" | while IFS= read -r v; do printf '%s\n%s\n%s\n' "$VB_RH" "$VB_HK" "$VB_TX" | /usr/bin/grep -qx -- "$v" || printf '%s ' "$v"; done)"

# ============================================================
section "§CANCEL: a cancel of the release approval appended to the run's log is followed by close-out's facts line"
# ============================================================
# The delivered plan is put back where close-out read it, its log the reader's own translation with step 9 cancelled,
# so close-out's check reads the run at Step 8 and reaches its facts line. Both are removed after.
# fails-when: close-out reads the release as approved after the log cancels that approval.
if cr_reached "CN-0"; then
  CN_P="$CR_ROOT/$DOOR_PLAN_REL"; CN_L="$CR_REC/run.log"; mkdir -p "${CN_P%/*}" && cp "$CR_PLAN" "$CN_P"
  { ( . "$BIONIC_SCRIPTS_DIR/payload/scripts/lib/reader.sh" && reader_events "$CN_P" )
    printf 'run/v1|ev=cancel|of=step|n=9|at=2099-01-01T00:00:00Z\n'; } > "$WORLD_ROOT/cn.log" && mv "$WORLD_ROOT/cn.log" "$CN_L"
  cn_facts() { door_run "$CR_ROOT" env HOME="$CR_DIR/home" BIONIC_CLAUDE_HOME="$CR_DIR/home/.claude" \
    bash "$CR_ROOT/payload/scripts/close-out.sh" "$CN_P" check; printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -m1 '^facts: '; }
  expect_eq "CN-1 reopened at Step 8, close-out reads the release approved: every fact holds at the branch's head" \
    "facts: every fact the run owes holds at $(git -C "$CR_ROOT" rev-parse --verify -q "refs/heads/$DOOR_BRANCH")" "$(cn_facts)"
  printf 'run/v1|ev=cancel|of=approval|key=release|at=2099-01-01T00:00:01Z\n' >> "$CN_L"
  expect_contains "CN-2 …and with that approval cancelled in the log, it reads the release as not approved" \
    "no approved: release line names a head" "$(cn_facts)"
  rm -f "$CN_L" "$CN_P"
fi

# ============================================================
section "§SINGLE: the single-rigor run reaches the Verify gate, its criterion discharged by the walk"
# ============================================================
# fails-when: the rehearsal's single-rigor state does not build, its plan is not at rigor: single, it does not stand at
# current: 5 with the build's criterion discharged by the walk's proof under the critic's verdict at the head, or the
# evidence review is registered on any row but the critic's.
SG_DIR="$WORLD_ROOT/single-verify"; SG_RC=0; SG_PLAN=""
if [ "$CR_LOADED" = 1 ]; then
  # The host is planted busy (load 14 on 8 cores): a rehearsed landing's verdict never turns on the machine's load.
  SG_PLAN="$(BIONIC_PROBE_CORES=8 BIONIC_PROBE_BUSY_CORES=14 BIONIC_PROBE_BUSY_CORES_5M=14 \
    rehearse single-verify "$SG_DIR" 2> "$WORLD_ROOT/single-verify.err")" || SG_RC=$?
else
  SG_RC=127
fi
expect_eq "SG-1 the single-rigor rehearsal reaches its state (rehearse exit 0, its plan printed)" "0|yes" \
  "$SG_RC|$([ -n "$SG_PLAN" ] && [ -f "$SG_PLAN" ] && echo yes)"
if [ "$SG_RC" = 0 ] && [ -f "$SG_PLAN" ]; then
  expect_eq "SG-2 the plan is the single-rigor fixture's: its frontmatter says rigor: single" "single" \
    "$(awk '/^---$/ { n++; next } n == 1 && /^rigor:/ { sub(/^rigor:[[:space:]]*/, ""); print }' "$SG_PLAN")"
  expect_eq "SG-3 the run stands at the Verify gate: step 5 in its log, and its page at 15 holds no state section" "n=5|15|no" \
    "$(bash "$BIONIC_SCRIPTS_DIR/payload/scripts/reader.sh" "$SG_PLAN" step | head -1)|$(sed -n 's/^canonical_sdlc_version: //p' "$SG_PLAN")|$(/usr/bin/grep -q '^## SDLC State' "$SG_PLAN" && echo yes || echo no)"
  SG_CELL="$(bash -c '. "$1/payload/scripts/lib/reader.sh" && reader_cells "$2" "$3"' _ "$BIONIC_SCRIPTS_DIR" "$SG_PLAN" \
    "$(git -C "$SG_DIR/project" rev-parse --verify -q "refs/heads/$DOOR_BRANCH")" | awk -F'\037' '$1 == "AC-1.1" { print $2 "|" $3 "|" $5 "|" $6 }')"
  expect_eq "SG-4 the build's criterion reads discharged by the walk's proof, its verdict the critic's evidence review at the head" \
    "discharged|proof|record/wave-x/walk.md|CONFIRMED" "$SG_CELL"
  SG_NAMES="$(cr_names < "$SG_DIR/rehearsal.log" | cut -d'|' -f2-)"
  SG_WANT='spawn-worktree.sh ready|session-poker.sh proof-add review|session-poker.sh proof-add walk|session-poker.sh proof-add regression|session-poker.sh current'
  expect_eq "SG-5 the log names the verbs that brought it there" "$SG_WANT" "$(printf '%s\n' "$SG_NAMES" | cr_held "$SG_WANT")"
  # The evidence review: one proof line of the question, its reader's roster row the critic's, dealt evidence.
  SG_READER="$(cr_proofs "$SG_PLAN" | sed -n 's/^proved: kind=review .* question=evidence reader=\([^ ]*\) .*/\1/p' | tail -1)"
  expect_eq "SG-7 the evidence question was read by the critic: its proof line names a reader whose roster row is bionic:critic, dealt evidence" \
    "w-evidence-whole|bionic:critic|evidence" \
    "$SG_READER|$(/usr/bin/grep -h "|name=${SG_READER:-none}|" "$SG_DIR"/project/.bionic/tmp/roster-*.state 2>/dev/null | tail -1 | tr '|' '\n' | sed -n 's/^subagent_type=//p;s/^questions=//p' | paste -sd'|' -)"
else
  printf '    the single-rigor rehearsal stopped; rehearse said:\n'
  sed 's/^/    | /' "$WORLD_ROOT/single-verify.err" 2>/dev/null | cut -c1-400 | tail -12
fi

finish
