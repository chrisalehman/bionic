#!/bin/bash
# Tests for the close of a run, replayed: the rehearsal's failed-review state (a whole structure review registered
# failing at Step 8, close-out refused on it) carried through the verbs alone to close-out's `delivered:`
# (tests/lib/rehearsal.sh `rehearse delivered`), in a sandbox whose project declares its real release check.
#
#   §CLOSE   the replay reaches delivered:: the fix row born of the finding lands through ready, the waiver ask closes
#            without a waiver, the release lands (its numbers re-rendered on the fix's landing, the check held there),
#            the user's reply approves that head and its merge without a whole run, the integrate row renders the
#            reviews part before its pull request (main holds it on the approved head) and lands, close-out writes
#            delivered: with no hand-hold; the replay's log holds no hand landing or merge, plan edit, step set back or waiver
#   §WINDOW  after the close, the hand-holds window ends at the plan's delivered: time, and a decline planted after
#            the release approval card is counted: the card ends nothing
#   §VERBS   every refusal the replay met names a verb that writes the cell (deliver, amend, task-set or
#            step-field), and that verb's call on the cell, then the refused call again, exit 0
#   §PR      the integrate row's pull request goes through a stand-in gh, the only gh on its PATH, whose log holds
#            `pr create --base main --head wave/x`
#   §ENTRY   after close-out, the release entry's reviews part, at the branch's final head and on main after the merge,
#            names the review the run failed and fixed as registered, and every commit after the fix's landing is one
#            the landing record names: a published event or the integrate row's event that wrote the part
#   §REAL    the sandbox's config declares tests/lib/release-check.sh, the sandbox's own copy is the one that ran,
#            and every hand write in the log is one a person, an agent or the harness writes in a real run, and the log
#            is valid UTF-8 throughout, so every reader reads the whole of it
#   §SR      the replay plants a second review naming the fix row's site under another question; the fix row's landing
#            writes it fixed, no finding-move follows the landing, and the close reads zero
#   §LIVE    the replay's live criterion (door.sh DOOR_LIVE_ROW), owed at the close: every advance and the refused
#            close-out pass with it pending, the release approval card lists it owed by the close, and close-out writes it
#            discharged from its last reading, with no matrix-set
#   §SINGLE  `rehearse single-verify` (door.sh `door_world_single`) stands at current: 5, the build's criterion discharged
#            by its landing, the critic's evidence review on its own roster row carried into the auditor cell and the
#            head's auditor-wave: line; its log names the verbs that brought it there and no discharge
#
# NAMED, NOT COUNTED: the rows reading the replay's part (CL-8, VB-1, VB-2) name each verb the replay runs and each kind
# of hand write it makes, so a log that lost one of them is red however long it is.
#
# ONE SANDBOX, READ BY EVERY SECTION BUT §SINGLE: `rehearse delivered` builds it once, under WORLD_ROOT; each command
# it ran is in its rehearsal.log, the replay's own commands after the `# replay:` line. §SINGLE builds its own, beside
# it, in a subshell of its own, so nothing it sets reaches the replay's readers.
#
# FIXTURE FIDELITY: the sandbox is tests/lib/door.sh's repository carrying the plugin's hooks and scripts and the
# release check's closure; every state past the plan's Step-3 prose is a command's. What `rehearse` writes by hand
# is tagged in the log with its kind (rehearsal.sh RH_HAND_KINDS), and §REAL reads those tags.
#
# ANTI-VACUITY: a state that cannot be reached stops its section before any read, asserting the failure. Every empty
# read (no refusal, no hand-hold command, no foreign kind) stands beside a non-empty read through the same extractor
# in the same section.
#
# EXPECTED TIME: about seven minutes when the replay reaches delivered: (four and a half to failed-review, two more for
# the replay's release check), four and a half when it stops at the fix's landing; §SINGLE about a minute more.
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
# cr_marks <tag> -> the text of each `# <tag>: ` line in the replay's part
cr_marks() { cr_part | awk -v t="# ${1}: " 'index($0, t) == 1 { print substr($0, length(t) + 1) }'; }
# The verbs the replay runs (rehearsal.sh `_rh_replay`), each named `<tool> <verb>`: the tool the command runs and
# the first bare word of its arguments. A log missing any of them is a replay that did not run that verb, whatever its
# length. A refusal's follow is not listed: the replay meets one only when a verb refuses.
CR_VERBS='session-sweeper.sh ack|session-poker.sh task-add|spawn-worktree.sh create|session-poker.sh launch-sync|spawn-worktree.sh ready|session-poker.sh release-check|session-poker.sh release-approval|session-poker.sh reply|session-poker.sh reviews-part|gh pr create|gh pr merge|session-poker.sh deliver|close-out.sh run'
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
# cr_ask <key> -> the register's line for <key> as <state>|<by>
cr_ask() {
  awk -F'|' -v k="key=$1" '$2 == k { s = ""; b = ""
    for (i = 3; i <= NF; i++) { if ($i ~ /^state=/) s = substr($i, 7); if ($i ~ /^by=/) b = substr($i, 4) }
    print s "|" b }' "$CR_REC/asks.state" 2>/dev/null | tail -1
}
cr_closer_is_waiver() {  # <by> -> yes when a waiver or close-out closed the ask, else no
  case "$1" in
    (waive|close-out*) echo yes ;;
    (*) echo no ;;
  esac
}
# cr_field <line> <key> -> the value of <key>= in a `|`-separated landing-record line
cr_field() { printf '%s\n' "$1" | awk -F'|' -v k="$2=" '{ for (i = 1; i <= NF; i++) if (index($i, k) == 1) { print substr($i, length(k) + 1); exit } }'; }
# cr_part_event -> the landing record's last line naming a commit of the entry's reviews part, whichever verb wrote it
cr_part_event() { /usr/bin/grep '|part=reviews|' "$CR_REC/landing-proofs.log" 2>/dev/null | tail -1; }
# cr_entry_part <changelog text on stdin> <version> -> the `### The reviews` part of that version's entry, heading
# to the next heading
cr_entry_part() {
  awk -v v="## $1 " '
    /^## / { inb = (index($0, v) == 1); inp = 0 }
    /^### / { t = $0; sub(/[[:space:]]+$/, "", t); inp = inb && (t == "### The reviews") }
    inp { print }'
}
# cr_review_bullet <plan> <reader> -> the bullet the plan's review line by <reader> is listed as, built here from
# the line's own fields: `- <question> review, <scope>: <result> at <head8> by <reader>, <at> (`<evidence file>`)`
cr_review_bullet() {
  awk -v r="$2" '
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
    END { if (b != "") print b }' "$1" 2>/dev/null
}
cr_reached() {  # -> 0 when the replay reached delivered:; else the failure asserted, with where it stopped
  [ "$CR_RC" = 0 ] && [ -f "$CR_PLAN" ] && return 0
  expect_eq "$1 the replay reached delivered: (rehearse exit 0), so this section can be read" "0" "$CR_RC"
  return 1
}

# ============================================================
section "§CLOSE: from the failed-review state, the verbs alone reach delivered:"
# ============================================================
# fails-when: the replay stops before close-out's delivered:, reaches it only past a hand landing, hand merge, plan
# edit, step set back or waiver, or close-out counts a hand-hold.
expect_eq "CL-1 the replay reaches delivered: through the verbs (rehearse exit 0, the archived plan's Step 9 line delivered:)" \
  "0|yes" "$CR_RC|$(/usr/bin/grep -q '^- Step 9: delivered:' "$CR_PLAN" 2>/dev/null && echo yes)"
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
    "$(cr_rc 'the fix row says ready' | tail -1)|$(awk -F'|' '$2 == "ev=published" && $3 == "row=T5" { for (i = 4; i <= NF; i++) if ($i ~ /^kind=/) k = substr($i, 6) } END { print k }' "$CR_REC/landing-proofs.log" 2>/dev/null)"
  CL_W="$(cr_ask waive:structure)"
  expect_eq "CL-3 the structure review's waiver ask is on the register (read beside the next row)" "yes" \
    "$([ -n "$CL_W" ] && echo yes)"
  expect_eq "CL-3b …and closed, by neither a waiver nor close-out" "closed|no" \
    "${CL_W%%|*}|$(cr_closer_is_waiver "${CL_W#*|}")"
  expect_eq "CL-4 the release lands with the fix: its published event carries the line's release numbers commit" "yes" \
    "$(awk -F'|' '$2 == "ev=published" && $3 == "row=T5" && /\|numbers=[0-9a-f]{40}\|/ { f = 1 } END { if (f) print "yes" }' "$CR_REC/landing-proofs.log" 2>/dev/null)"
  expect_eq "CL-4b …and main holds the reviews part's commit, on the head the release check held (a kind=check line there, not result=fail)" "yes|yes|no" \
    "$([ -n "$CL_PART" ] && [ "$CL_PART" = "$CL_MAIN" ] && echo yes)|$([ -n "$CL_REL" ] && /usr/bin/grep -q "^proved: kind=check head=$CL_REL " "$CR_PLAN" && echo yes)|$(/usr/bin/grep "^proved: kind=check head=${CL_REL:-none} " "$CR_PLAN" | tail -1 | /usr/bin/grep -q 'result=fail' && echo yes || echo no)"
  expect_eq "CL-5 the user's reply approves that head: reply exit 0, the newest approved: release and approved: merge-unproved (the fix landed past the whole run) name it" "0|$CL_REL|$CL_REL" \
    "$(cr_rc "the user's reply to the card at the fix's head" | tail -1)|$(for k in release merge-unproved; do /usr/bin/grep "^approved: $k " "$CR_PLAN" | tail -1 | sed -n 's/.* head=\([0-9a-f]*\) .*/\1/p'; done | paste -sd'|' -)"
  expect_eq "CL-6 the integrate row lands and close-out runs (exit 0)" "landed|0" \
    "$(awk -F'|' '$2 ~ /^ *T4 *$/ { s = $(NF - 1); gsub(/ /, "", s); print s }' "$CR_PLAN")|$(cr_rc 'close-out, the tail' | tail -1)"
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
section "§WINDOW: after the close, the hand-holds window ends at the plan's delivered: time, and an act after the card counts"
# ============================================================
# The window runs from the last build landing to `delivered:`; the release approval card ends nothing. The report read
# over the delivered plan names that end, and a decline planted a second after the card's replay time is counted.
# fails-when: the end is the card again, so the ends line names the page and the planted decline is outside.
# close-out archived the plan outside the project, where no project root names the record, so the report reads a copy
# put back where the plan stood when close-out read it, and the copy is removed after.
cr_hh() {  # -> landing-report --hand-holds over the delivered plan, as the replay's verbs run it
  local p="$CR_ROOT/$DOOR_PLAN_REL" put=""
  [ -f "$p" ] || { mkdir -p "${p%/*}" && cp "$CR_PLAN" "$p" && put=yes; }
  door_run "$CR_ROOT" bash "$CR_ROOT/hooks/session-poker.sh" landing-report --hand-holds "$p"
  [ -z "$put" ] || rm -f "$p"
  printf '%s\n' "$DOOR_OUT"
}
if cr_reached "WINDOW-0"; then
  CW_DEL="$(awk '/^- Step 9: delivered: / { print $5; exit }' "$CR_PLAN")"
  CW_CARD="$(cat "$CR_REC"/release-approval-*.md 2>/dev/null | sed -n 's/^release-approval\/v1|plan=.*|at=\([^|]*\)|.*/\1/p' | LC_ALL=C sort | tail -1)"
  expect_eq "WINDOW-0 precondition: the plan names a delivered: minute and the record a release approval card's time" "yes|yes" \
    "$(printf '%s' "$CW_DEL" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z$' && echo yes)|$([ -n "$CW_CARD" ] && echo yes)"
  CW_OUT="$(cr_hh)"
  expect_contains "WINDOW-1 the ends line names the plan's delivered: time as the window's end" \
    "until $CW_DEL (delivered:)" "$(printf '%s\n' "$CW_OUT" | grep '^hand-holds window: ')"
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
    "$(/usr/bin/grep -q '^proved: kind=review .*evidence=record/wave-x/w-adversarial-whole-2.md question=adversarial ' "$CR_PLAN" && echo yes)|$SR_B"
  expect_contains "SR-1b …the site is a line of the library the fix answers" "payload/scripts/lib/said.sh:" "$SR_A"
  SR_AFTER="$(cr_part | awk '/^\$ / { c = $0; next } /^  rc=[0-9]+  \(the fix row says ready, / { f = 1; next } f && /^  rc=/ { print c }')"
  expect_contains "SR-2 commands follow the fix row's landing in the replay's log (read beside the moves)" "close-out.sh" "$SR_AFTER"
  expect_eq "SR-2b …and none of them is a finding-move" "" "$(printf '%s\n' "$SR_AFTER" | /usr/bin/grep 'session-poker\.sh finding-move')"
  expect_eq "SR-3 the second finding is written fixed by the fix row's landing" "yes" \
    "$(/usr/bin/grep -q '^moved: record/wave-x/w-adversarial-whole-2\.md#1 to=fixed row=T5 by=landing ' "$CR_PLAN" && echo yes)"
  expect_contains "SR-4 the close reads zero with the window at delivered:" "hand-holds: total=0 " \
    "$(cr_out 'close-out, the tail' | /usr/bin/grep '^hand-holds: ')"
fi

# ============================================================
section "§VERBS: every refusal the replay met names the verb that writes the cell, and that verb then writes it"
# ============================================================
# fails-when: a refusal names no verb of deliver, amend, task-set and step-field, a refused call is left unfollowed,
# or the named verb, or the refused call after it, exits non-zero.
if cr_reached "VB-0"; then
  VB_RCS="$(cr_rcs)"
  expect_eq "VB-1 the replay's part logs an exit 0 for each verb the replay runs, named" "$CR_VERBS" \
    "$(cr_part | cr_names | sed -n 's/^0|//p' | cr_held "$CR_VERBS")"
  expect_eq "VB-1b …and every non-zero exit is a refusal the replay followed" "" \
    "$(printf '%s\n' "$VB_RCS" | awk -F'|' '$1 != 0 { print $2 }' | while IFS= read -r l; do
        cr_marks refused | /usr/bin/grep -q -F -- "$l · names: " || printf '%s\n' "$l"; done)"
  expect_eq "VB-2 the replay's marks are read: a hand write of each kind the replay makes, named ($CR_HANDS)" \
    "$(printf '%s' "$CR_HANDS" | tr ' ' '|')" \
    "$(cr_marks 'by hand' | sed -n 's/^\[\([a-z]*\)\] .*/\1/p' | cr_held "$(printf '%s' "$CR_HANDS" | tr ' ' '|')")"
  expect_eq "VB-2b …and every refusal names a verb of $RH_FOLLOW_VERBS" "" \
    "$(cr_marks refused | while IFS= read -r m; do v="${m##* · names: }"
        case " $RH_FOLLOW_VERBS " in (*" $v "*) : ;; (*) printf '%s\n' "$m" ;; esac; done)"
  expect_eq "VB-3 each named verb's call on the cell, then the refused call again, exits 0" "" \
    "$(cr_marks refused | while IFS= read -r m; do l="${m% · names: *}"
        f="$(cr_part | awk -v m="# refused: $m" 'index($0, m) == 1 { f = 1; next } f && /^  rc=[0-9]+  \(follow: / { sub(/^  rc=/, ""); sub(/ .*/, ""); print; exit }')"
        a="$(cr_rc "$l, again" | tail -1)"
        [ "$f|$a" = "0|0" ] || printf '%s: follow=%s again=%s\n' "$l" "${f:-none}" "${a:-none}"; done)"
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
    "pr create --base main --head wave/x" "$(cat "$CR_DIR/bin/gh.log" 2>/dev/null)"
  expect_eq "PR-3 the stand-in is the only gh on that PATH" "gh is $CR_DIR/bin/gh" \
    "$(cr_out "the gh on the integrate row's PATH")"
  expect_eq "PR-4 the person's merge through it leaves main holding the reviews part's commit, whose parent is the head the release check held" "0|yes|yes" \
    "$(cr_rc 'the person merges the pull request' | tail -1)|$([ "$(cr_field "$(cr_part_event)" commit)" = "$(git -C "$CR_ROOT" rev-parse --verify -q refs/heads/main)" ] && echo yes)|$(/usr/bin/grep -q "^proved: kind=check head=$(git -C "$CR_ROOT" rev-parse --verify -q 'refs/heads/main^1' 2>/dev/null) " "$CR_PLAN" 2>/dev/null && echo yes)"
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
  EN_REC="$CR_REC/landing-proofs.log"
  EN_PART="$(git -C "$CR_ROOT" show "refs/heads/$EN_BR:CHANGELOG.md" 2>/dev/null | cr_entry_part "$EN_VER")"
  EN_WANT="$(cr_review_bullet "$CR_PLAN" w-structure-whole-2)"
  expect_eq "EN-1 the plan's proof line for the failing review is read: a bullet is built from its fields" "yes" \
    "$([ -n "$EN_WANT" ] && echo yes)"
  expect_contains "EN-1b …and it reads as the failing structure review of the whole" "- structure review, whole: fail at " "$EN_WANT"
  expect_eq "EN-2 the working branch's release entry holds a reviews part at its final head" "### The reviews" \
    "$(printf '%s\n' "$EN_PART" | sed -n 1p)"
  expect_eq "EN-3 …and lists the failed review exactly as the plan registered it" "$EN_WANT" \
    "$([ -n "$EN_WANT" ] && printf '%s\n' "$EN_PART" | /usr/bin/grep -x -F -- "$EN_WANT")"
  EN_PLAN_N="$(awk '/^[[:space:]]*```/ { fence = !fence; next } fence { next } /^##[[:space:]]/ { s = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    s && (/^proved: kind=review / || /^waived:[[:space:]]/) { n++ } END { print n + 0 }' "$CR_PLAN")"
  expect_eq "EN-4 the part lists as many reviews and waivers as the plan registers (the plan registers some)" "$EN_PLAN_N|yes" \
    "$(printf '%s\n' "$EN_PART" | /usr/bin/grep -c '^- ')|$([ "$EN_PLAN_N" -ge 1 ] && echo yes)"
  EN_MAIN="$(git -C "$CR_ROOT" show "refs/heads/main:CHANGELOG.md" 2>/dev/null | cr_entry_part "$EN_VER")"
  expect_eq "EN-2m main's release entry holds the reviews part after the person's merge" "### The reviews" \
    "$(printf '%s\n' "$EN_MAIN" | sed -n 1p)"
  expect_eq "EN-3m …and lists the failed review exactly as the plan registered it" "$EN_WANT" \
    "$([ -n "$EN_WANT" ] && printf '%s\n' "$EN_MAIN" | /usr/bin/grep -x -F -- "$EN_WANT")"
  EN_WROTE="$(cr_part_event)"
  expect_eq "EN-4m the part was written by the integrate row before its pull request (its event, ev=integrate, names T4)" \
    "ev=integrate|T4" "$(printf '%s\n' "$EN_WROTE" | awk -F'|' '{ print $2 }')|$(cr_field "$EN_WROTE" row)"
  EN_PUB="$(awk -F'|' '$2 == "ev=published" && $3 == "row=T5"' "$EN_REC" 2>/dev/null | tail -1)"
  EN_FIX="$(cr_field "$EN_PUB" numbers)"; [ -n "$EN_FIX" ] || EN_FIX="$(cr_field "$EN_PUB" commit)"
  EN_ON="$([ -n "$EN_FIX" ] && git -C "$CR_ROOT" merge-base --is-ancestor "$EN_FIX" "refs/heads/$EN_BR" 2>/dev/null && echo yes)"
  expect_eq "EN-5 the record names where the fix row's landing put the branch, and that commit is on the branch" "yes" "$EN_ON"
  EN_AFTER=""; [ "$EN_ON" != yes ] || EN_AFTER="$(git -C "$CR_ROOT" rev-list "$EN_FIX..refs/heads/$EN_BR" 2>/dev/null)"
  EN_NAMED="$(awk -F'|' '$2 == "ev=published" || /\|part=reviews\|/ {
      for (i = 3; i <= NF; i++) if ($i ~ /^(commit|numbers)=[0-9a-f]+$/) print substr($i, index($i, "=") + 1) }' "$EN_REC" 2>/dev/null)"
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
# The replay's plan carries the live row a planner writes (door.sh DOOR_LIVE_ROW): a row at tier T3, its eval the
# hand-holds line at the close, its task the close row T9. The gate defers it until its step, so each advance and the
# refused close-out pass with it pending; the release approval card lists it owed by the close, never a decision its
# reply could waive; close-out writes it from its last reading after delivered:, and no matrix-set touches it.
# fails-when: an advance or the card refuses or waives the pending row, the delivered plan reads it anything but
# discharged with the continuation as its evidence, or a matrix-set in the log names it.
if cr_reached "LV-0"; then
  lv_cells() { awk -F'|' '$2 ~ /^ *AC-2\.1 *$/ { s = $4; e = $5; gsub(/^ +| +$/, "", s); gsub(/^ +| +$/, "", e); print s "|" e }' "$1"; }
  lv_key() { awk -v k="$2" '/^AC-2\.1:/ { b = 1; next } b && /^[^ \t]/ { b = 0 } b && $0 ~ "^[ \t]+" k ": " { sub("^[ \t]+" k ": ", ""); print; exit }' "$1"; }
  expect_eq "LV-1 the plan's live row is matrix-render's: its task the close row, its eval the hand-holds line" "T9|yes" \
    "$(lv_key "$CR_PLAN" task)|$(lv_key "$CR_PLAN" eval | /usr/bin/grep -q 'landing-report --hand-holds' && echo yes)"
  expect_eq "LV-2 each advance past the Verify gate exits 0 with the row pending" "0|0|0" \
    "$(cr_rc 'enter Step 6' | tail -1)|$(cr_rc 'enter Step 7' | tail -1)|$(cr_rc 'enter Step 8' | tail -1)"
  LV_CARD="$(cat "$CR_REC"/release-approval-*.md 2>/dev/null)"
  expect_eq "LV-3 the release approval card lists it owed by the close, and puts no decision on it" "yes|no" \
    "$(/usr/bin/grep -q 'owed by the close' <<< "$LV_CARD" && echo yes || echo no)|$(/usr/bin/grep -q 'key=row:AC-2\.1|' <<< "$LV_CARD" && echo yes || echo no)"
  expect_eq "LV-4 at delivered: the plan reads it discharged, its evidence cell and block key the continuation" \
    "discharged|record/wave-x/continuation.md|record/wave-x/continuation.md" \
    "$(lv_cells "$CR_PLAN")|$(lv_key "$CR_PLAN" evidence)"
  expect_contains "LV-5 …written by close-out from its last reading" "matrix: AC-2.1 discharged" "$(cr_out 'close-out, the tail')"
  LV_SETS="$(/usr/bin/grep '^\$ .*session-poker.sh matrix-set ' "$CR_LOG")"
  expect_contains "LV-6 precondition: the log's matrix-set lines are read (the criterion's task on AC-1.1)" "matrix-set AC-1.1" "$LV_SETS"
  expect_absent "LV-6b …and none names AC-2.1" "AC-2.1" "$LV_SETS"
fi

# ============================================================
section "§SINGLE: the single-rigor run reaches the Verify gate with no discharge"
# ============================================================
# fails-when: the rehearsal's single-rigor state does not build, its plan is not at rigor: single, it does not stand at
# current: 5 with the build's criterion discharged, the auditor cell or the head's auditor-wave: line lacks the critic's
# verdict, the evidence review is registered on any row but the critic's, or its log runs discharge.
SG_DIR="$WORLD_ROOT/single-verify"; SG_RC=0; SG_PLAN=""
if [ "$CR_LOADED" = 1 ]; then
  SG_PLAN="$(rehearse single-verify "$SG_DIR" 2> "$WORLD_ROOT/single-verify.err")" || SG_RC=$?
else
  SG_RC=127
fi
expect_eq "SG-1 the single-rigor rehearsal reaches its state (rehearse exit 0, its plan printed)" "0|yes" \
  "$SG_RC|$([ -n "$SG_PLAN" ] && [ -f "$SG_PLAN" ] && echo yes)"
if [ "$SG_RC" = 0 ] && [ -f "$SG_PLAN" ]; then
  expect_eq "SG-2 the plan is the single-rigor fixture's: its frontmatter says rigor: single" "single" \
    "$(awk '/^---$/ { n++; next } n == 1 && /^rigor:/ { sub(/^rigor:[[:space:]]*/, ""); print }' "$SG_PLAN")"
  expect_eq "SG-3 the run stands at the Verify gate: current: 5, the Step 5 line written" "5|yes" \
    "$(sed -n 's/^current:[[:space:]]*//p' "$SG_PLAN" | head -1)|$(/usr/bin/grep -q '^- Step 5: ' "$SG_PLAN" && echo yes)"
  # The matrix row as the table holds it: status and auditor cells, so the auditor cell is read beside a status.
  expect_eq "SG-4 the build's criterion is discharged by status, and its auditor cell holds the critic's verdict, the bare token" "discharged|CONFIRMED" \
    "$(awk -F'|' '$2 ~ /^ *AC-1\.1 *$/ { s = $4; a = $6; gsub(/^ +| +$/, "", s); gsub(/^ +| +$/, "", a); print s "|" a }' "$SG_PLAN")"
  SG_NAMES="$(cr_names < "$SG_DIR/rehearsal.log" | cut -d'|' -f2-)"
  expect_eq "SG-5 the log names the verbs that brought it there" \
    "session-poker.sh matrix-render|spawn-worktree.sh ready|session-poker.sh proof-add review|session-poker.sh step-line|session-poker.sh step-field|session-poker.sh current" \
    "$(printf '%s\n' "$SG_NAMES" | cr_held 'session-poker.sh matrix-render|spawn-worktree.sh ready|session-poker.sh proof-add review|session-poker.sh step-line|session-poker.sh step-field|session-poker.sh current')"
  expect_eq "SG-5b …and discharge is not among them" "" \
    "$(printf '%s\n' "$SG_NAMES" | cr_held 'session-poker.sh discharge')"
  expect_eq "SG-6 the status is the landing's: no matrix-set writes a status (rehearsal.sh holds none), the block's evidence is the landing's log" "0|yes" \
    "$(/usr/bin/grep -c 'matrix-set.*status=' "$BIONIC_SCRIPTS_DIR/tests/lib/rehearsal.sh")|$(awk '/^AC-1\.1:/ { b = 1; next } b && /^[^ \t]/ { b = 0 } b && /^[ \t]+evidence: record\/wave-x\/line\/T1-rehearsal-row-/ { y = 1 } END { if (y) print "yes" }' "$SG_PLAN")"
  # The evidence review: one proof line of the question, its reader's roster row the critic's, dealt evidence.
  SG_READER="$(sed -n 's/^proved: kind=review .* question=evidence reader=\([^ ]*\) .*/\1/p' "$SG_PLAN" | tail -1)"
  expect_eq "SG-7 the evidence question was read by the critic: its proof line names a reader whose roster row is bionic:critic, dealt evidence" \
    "w-evidence-whole|bionic:critic|evidence" \
    "$SG_READER|$(/usr/bin/grep -h "|name=${SG_READER:-none}|" "$SG_DIR"/project/.bionic/tmp/roster-*.state 2>/dev/null | tail -1 | tr '|' '\n' | sed -n 's/^subagent_type=//p;s/^questions=//p' | paste -sd'|' -)"
  expect_eq "SG-7b …and its wave verdict is the head's auditor-wave: line, above the table" "auditor-wave: CONFIRMED — every requirement has a row|yes" \
    "$(awk '/^## Verification Matrix/ { m = 1; next } /^## / { m = 0 } m && /^\|/ { exit } m && /^auditor-wave:/' "$SG_PLAN")|$(awk '/^## Verification Matrix/ { m = 1; next } m && /^stack-health:/ { s = 1 } m && /^\|/ { exit } END { if (s) print "yes" }' "$SG_PLAN")"
else
  printf '    the single-rigor rehearsal stopped; rehearse said:\n'
  sed 's/^/    | /' "$WORLD_ROOT/single-verify.err" 2>/dev/null | cut -c1-400 | tail -12
fi

finish
