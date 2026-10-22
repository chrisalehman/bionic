#!/bin/bash
# Tests for the close of a run, replayed: the rehearsal's failed-review state (a whole structure review registered
# failing at Step 8, close-out refused on it) carried through the verbs alone to close-out's `delivered:`
# (tests/lib/rehearsal.sh `rehearse delivered`), in a sandbox whose project declares its real release check.
#
#   §CLOSE   the replay reaches delivered:: the fix row born of the review's finding lands through ready, the
#            review's waiver ask closes without a waiver, the release lands (the line re-renders the release
#            numbers on the fix's landing and the release check holds at that head), the user's reply approves the
#            head, the integrate row lands, close-out writes delivered: and counts no hand-hold; the replay's part
#            of the log holds no hand landing, hand merge, plan edit, step set back or waiver
#   §VERBS   every refusal the replay met names a verb that writes the cell (deliver, amend, task-set or
#            step-field), and that verb's call on the cell, then the refused call again, exit 0
#   §PR      the integrate row's pull request goes through a stand-in gh, the only gh on its PATH, whose log holds
#            `pr create --base main --head wave/x`
#   §ENTRY   after close-out, the release entry's reviews part, at the working branch's final head, names the review
#            the run failed and fixed as the plan registered it, and every commit on the branch after the fix's landing
#            is one the landing record names, as a published or a close-out event
#   §REAL    the sandbox's config declares tests/lib/release-check.sh, the sandbox's own copy is the one that ran,
#            and every hand write in the log is one a person, an agent or the harness writes in a real run, and the log
#            is valid UTF-8 throughout, so every reader reads the whole of it
#
# ONE SANDBOX, READ BY EVERY SECTION: `rehearse delivered` builds it once, under WORLD_ROOT; each command it ran is
# in its rehearsal.log, the replay's own commands after the `# replay:` line.
#
# FIXTURE FIDELITY: the sandbox is tests/lib/door.sh's repository carrying the plugin's hooks and scripts and the
# release check's closure; every state past the plan's Step-3 prose is a command's. What `rehearse` writes by hand
# is tagged in the log with its kind (rehearsal.sh RH_HAND_KINDS), and §REAL reads those tags.
#
# ANTI-VACUITY: a state that cannot be reached stops its section before any read, asserting the failure. Every empty
# read (no refusal, no hand-hold command, no foreign kind) stands beside a non-empty read through the same extractor
# in the same section.
#
# EXPECTED TIME: about seven minutes when the replay reaches delivered: (the rehearsal to failed-review, two release
# check verb calls among them, is four and a half; the replay's own release check call is two more), about four and a
# half when it stops at the fix row's landing.
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
  CR_PLAN="$(rehearse delivered "$CR_DIR" 2> "$WORLD_ROOT/delivered.err")" || CR_RC=$?
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
  expect_eq "CL-2 the fix row born of the finding lands through ready, published by the line (kind=queue)" "0|queue" \
    "$(cr_rc 'the fix row says ready' | tail -1)|$(awk -F'|' '$2 == "ev=published" && $3 == "row=T5" { for (i = 4; i <= NF; i++) if ($i ~ /^kind=/) k = substr($i, 6) } END { print k }' "$CR_REC/landing-proofs.log" 2>/dev/null)"
  CL_W="$(cr_ask waive:structure)"
  expect_eq "CL-3 the structure review's waiver ask is on the register (read beside the next row)" "yes" \
    "$([ -n "$CL_W" ] && echo yes)"
  expect_eq "CL-3b …and closed, by neither a waiver nor close-out" "closed|no" \
    "${CL_W%%|*}|$(cr_closer_is_waiver "${CL_W#*|}")"
  expect_eq "CL-4 the release lands with the fix: its published event carries the line's release numbers commit" "yes" \
    "$(awk -F'|' '$2 == "ev=published" && $3 == "row=T5" && /\|numbers=[0-9a-f]{40}\|/ { f = 1 } END { if (f) print "yes" }' "$CR_REC/landing-proofs.log" 2>/dev/null)"
  expect_eq "CL-4b …and the release check holds at the head main holds (a kind=check line there, not result=fail)" "yes|no" \
    "$(/usr/bin/grep -q "^proved: kind=check head=$CL_MAIN " "$CR_PLAN" && echo yes)|$(/usr/bin/grep "^proved: kind=check head=$CL_MAIN " "$CR_PLAN" | tail -1 | /usr/bin/grep -q 'result=fail' && echo yes || echo no)"
  expect_eq "CL-5 the user's reply approves that head: reply exit 0, the newest approved: release names it" "0|$CL_MAIN" \
    "$(cr_rc "the user's reply to the card at the fix's head" | tail -1)|$(/usr/bin/grep '^approved: release ' "$CR_PLAN" | tail -1 | sed -n 's/.* head=\([0-9a-f]*\) .*/\1/p')"
  expect_eq "CL-6 the integrate row lands and close-out runs (exit 0)" "landed|0" \
    "$(awk -F'|' '$2 ~ /^ *T4 *$/ { s = $(NF - 1); gsub(/ /, "", s); print s }' "$CR_PLAN")|$(cr_rc 'close-out, the tail' | tail -1)"
  CL_HH="$(cr_out 'close-out, the tail' | /usr/bin/grep '^hand-holds: ')"
  expect_eq "CL-7 close-out prints its hand-holds line" "yes" "$([ -n "$CL_HH" ] && echo yes)"
  expect_contains "CL-7b …and it counts none" "hand-holds: total=0 " "$CL_HH"
  CL_CMDS="$(cr_part | /usr/bin/grep '^\$ ')"
  expect_eq "CL-8 the replay's part of the log holds the commands it ran" "yes" \
    "$([ "$(printf '%s\n' "$CL_CMDS" | /usr/bin/grep -c .)" -ge 10 ] && echo yes)"
  expect_eq "CL-8b …none a hand landing, a hand merge, a step set back or a waiver, and no hand write of the plan's prose" "" \
    "$(printf '%s\n' "$CL_CMDS" | /usr/bin/grep -E -- '--by-hand|session-poker\.sh current [0-7]( |$)|session-poker\.sh waive |git .*(fetch|merge|update-ref)'; cr_marks 'by hand' | /usr/bin/grep '^\[prose\]')"
fi

# ============================================================
section "§VERBS: every refusal the replay met names the verb that writes the cell, and that verb then writes it"
# ============================================================
# fails-when: a refusal names no verb of deliver, amend, task-set and step-field, a refused call is left unfollowed,
# or the named verb, or the refused call after it, exits non-zero.
if cr_reached "VB-0"; then
  VB_RCS="$(cr_rcs)"
  expect_eq "VB-1 the replay's part logs each command's exit" "yes" \
    "$([ "$(printf '%s\n' "$VB_RCS" | /usr/bin/grep -c '^0|')" -ge 10 ] && echo yes)"
  expect_eq "VB-1b …and every non-zero exit is a refusal the replay followed" "" \
    "$(printf '%s\n' "$VB_RCS" | awk -F'|' '$1 != 0 { print $2 }' | while IFS= read -r l; do
        cr_marks refused | /usr/bin/grep -q -F -- "$l · names: " || printf '%s\n' "$l"; done)"
  expect_eq "VB-2 the replay's marks are read: its hand writes are there" "yes" "$([ -n "$(cr_marks 'by hand')" ] && echo yes)"
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
  expect_eq "PR-4 the person's merge through it leaves main holding the head the release check held" "0|yes" \
    "$(cr_rc 'the person merges the pull request' | tail -1)|$(/usr/bin/grep -q "^proved: kind=check head=$(git -C "$CR_ROOT" rev-parse --verify -q refs/heads/main) " "$CR_PLAN" 2>/dev/null && echo yes)"
else
  expect_eq "PR-0 the replay reached the integrate row's pull request, so this section can be read" "reached" "not reached"
fi

# ============================================================
section "§ENTRY: the release entry names the review the run failed and fixed, and the record names every commit after the fix"
# ============================================================
# fails-when: the replay stops before close-out, close-out leaves the working branch's release entry without the
# reviews part as the plan registered the failing review, lists a different number of reviews than the plan
# registers, or the branch holds a commit after the fix's landing that no published or close-out event names.
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
  EN_PUB="$(awk -F'|' '$2 == "ev=published" && $3 == "row=T5"' "$EN_REC" 2>/dev/null | tail -1)"
  EN_FIX="$(cr_field "$EN_PUB" numbers)"; [ -n "$EN_FIX" ] || EN_FIX="$(cr_field "$EN_PUB" commit)"
  EN_ON="$([ -n "$EN_FIX" ] && git -C "$CR_ROOT" merge-base --is-ancestor "$EN_FIX" "refs/heads/$EN_BR" 2>/dev/null && echo yes)"
  expect_eq "EN-5 the record names where the fix row's landing put the branch, and that commit is on the branch" "yes" "$EN_ON"
  EN_AFTER=""; [ "$EN_ON" != yes ] || EN_AFTER="$(git -C "$CR_ROOT" rev-list "$EN_FIX..refs/heads/$EN_BR" 2>/dev/null)"
  EN_NAMED="$(awk -F'|' '$2 == "ev=published" || $2 == "ev=close-out" {
      for (i = 3; i <= NF; i++) if ($i ~ /^(commit|numbers)=[0-9a-f]+$/) print substr($i, index($i, "=") + 1) }' "$EN_REC" 2>/dev/null)"
  expect_eq "EN-6 commits follow the fix on the branch (read beside the unnamed ones)" "yes" \
    "$([ "$(printf '%s\n' "$EN_AFTER" | /usr/bin/grep -c .)" -ge 1 ] && echo yes)"
  expect_eq "EN-6b …and each is named by a published or close-out event in the landing record" "" \
    "$(printf '%s\n' "$EN_AFTER" | while IFS= read -r c; do
        [ -z "$c" ] || printf '%s\n' "$EN_NAMED" | /usr/bin/grep -q -x -F -- "$c" || printf '%s\n' "$c"; done)"
  expect_eq "EN-6c …among them the branch's final head, named by the close-out event for the reviews part" \
    "$(git -C "$CR_ROOT" rev-parse --verify -q "refs/heads/$EN_BR")" \
    "$(awk -F'|' '$2 == "ev=close-out" && $3 == "part=reviews"' "$EN_REC" 2>/dev/null | tail -1 | awk -F'|' '{ for (i = 4; i <= NF; i++) if ($i ~ /^commit=/) print substr($i, 8) }')"
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

finish
