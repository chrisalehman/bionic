#!/bin/bash
# tests/release-approval-2.test.sh — THE RELEASE APPROVAL CARD, part 2 of 2: the merge without a whole run at the head.
# Its header, world and helpers are tests/release-approval.prelude.sh's; it starts from that world as built.
#
# Usage: bash tests/release-approval-2.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/release-approval.prelude.sh"

# ============================================================
section "§JUDGE: the Tests line prints the full pass's state at this head, and a merge with no pass at it is the person's own approval"
# ============================================================
# fails-when: the page reads covered or green over a whole run behind the head, names a suite still owed, or leaves
# the landings since the run uncounted; the card puts no merge-unproved decision while the whole suite is not green
# at the head; reply on that decision writes no `approved: merge-unproved` line at the head; or `current 8 --check`
# passes before that line is written, or refuses after it.
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
fc_unproved() { fc_under Decisions | fc_flat | /usr/bin/grep -o "[0-9]*\. Merge without a whole run at this head — [^·]*· recommended: wait for the pass · default: none"; }
fc_judge_plan a.test.sh
fc_page --preview
expect_contains "JUDGE-0 precondition: the Tests section renders the whole-suite line" "whole suite: " "$(fc_under Tests)"
expect_contains "JUDGE-1 a red the whole run left and a later landing greened: the page reads red at the run's head, the two landings since counted" "whole suite: red at ${FC_C:0:8}, 2 landings before this head" "$(fc_under Tests | fc_flat)"
expect_eq "JUDGE-1b …and the word red is on the line, never covered" "1|0" "$(fc_under Tests | fc_flat | /usr/bin/grep -cw 'red')|$(fc_under Tests | fc_flat | /usr/bin/grep -c 'covered')"
expect_contains "JUDGE-1c …and the merge without a pass at this head is a decision, the state on it, waiting recommended" ". Merge without a whole run at this head — red at ${FC_C:0:8}, 2 landings before this head · recommended: wait for the pass · default: none" "$(fc_unproved)"
git -C "$RFC" reset -q --hard "$FC_R"
rm -f "$FC_REC/landing-proofs.log"
fc_plan "$(fc_floor "$FC_C" a.test.sh)
$(fc_reads "$FC_C")"
fc_page --preview
expect_contains "JUDGE-2 the control: no landing greened it, the page reads red at the run's head, one landing since" "whole suite: red at ${FC_C:0:8}, 1 landing before this head" "$(fc_under Tests | fc_flat)"
expect_contains "JUDGE-2b …names the suite the whole run left red, and its exit" "needs: the pass — a fix row for a.test.sh, then the pass" "$(fc_under Tests | fc_flat)"
expect_absent "JUDGE-2c …and does not read covered" "covered" "$(fc_under Tests | fc_flat)"
expect_contains "JUDGE-2d …and the card puts its decisions, the release among them" "Release 1.0.0" "$(fc_under Decisions | fc_flat)"
expect_eq "JUDGE-2e …but no merge without a whole run: the word never waives a suite the whole run left red" "" "$(fc_unproved)"
FC_WD_OWED=no; [ -z "$(fc_unproved)" ] || FC_WD_OWED=yes   # the owed row of §WORD's table
rm -f "$FC_REC"/release-approval-*.md
# JUDGE-4: the whole run at R, one docs commit past it, so the head moved no code since the pass. fails-when: the printer
# reads green only at the pass's own head, so the card asks the merge at a docs head and the defaults leave current 8 refusing.
fc_mu() { bash -c '. "$1/roots.sh"; . "$1/proof.sh"; proof_merge_ask "$2" "$3" "$4"; echo "rc=$?"' _ "$FC_LIB" "$PFC" "$RFC" "$1" 2>/dev/null | paste -sd'|' -; }  # <head> -> its line, then rc=
fc_plan "$FC_GOOD"
FC_J4="$(s57_commit "$RFC" README.md 'prose past the whole run')"
fc_page; FC_J4T="$(/usr/bin/grep '^release-approval/v1|dec=' "$FC_REC/release-approval-${FC_J4:0:8}.md" 2>/dev/null)"
expect_eq "JUDGE-4 precondition: one docs commit past the whole run, the card renders (exit 0) and its table holds the release approval" "0|yes" "$FC_RC|$(fc_has "$FC_J4T" '|key=approve:release|')"
expect_contains "JUDGE-4b the Tests line reads green at the whole run's head, the landing since counted" "whole suite: green at ${FC_R:0:8}, 1 landing since moved no code" "$(fc_under Tests | fc_flat)"
expect_absent "JUDGE-4c …and the table that holds the release approval carries no merge-unproved decision" "key=approve:merge-unproved" "$FC_J4T"
FC_WD_GREEN=no; [ -z "$(fc_has "$FC_J4T" '|key=approve:merge-unproved|')" ] || FC_WD_GREEN=yes   # the green row of §WORD's table
FC_J4M="$(fc_mu "$FC_J4")"; fc_plan "$(fc_floor "$FC_B")
$(fc_reads "$FC_C")"
expect_eq "JUDGE-4d …proof_merge_ask exits 1 at that head, printing nothing; over a whole run at B it asks at the code head C, naming the commit no run proved" "rc=1|red at ${FC_B:0:8}, 1 landing before this head; commit ${FC_C:0:12} (no landing row) is not proved: no run of its row's suites is recorded at it|rc=0" "$FC_J4M|$(fc_mu "$FC_C")"
fc_plan "$FC_GOOD"; fc_page; fc_typed "$FC_WD"
poke "$RFC" reply "$FC_WD"; FC_J4_REPLY="$RC"
poke "$RFC" current 8 --check; FC_WN_GREEN="$RC"
expect_eq "JUDGE-4e …the reply that takes every default replays (exit 0), writing no merge-unproved line, and current 8 --check is admitted (exit 0)" "0||0" "$FC_J4_REPLY|$(/usr/bin/grep '^approved: merge-unproved ' "$PFC")|$RC"
[ "$RC" = 0 ] || printf '      current 8 --check said: %s\n' "$(printf '%s\n' "$OUT" | tail -4)"
git -C "$RFC" reset -q --hard "$FC_R"; fc_typed "$FC_WD" "$FC_WR"; rm -f "$FC_REC"/release-approval-*.md
# JUDGE-3: the whole run at B, T1's code at C landed green on its suite, the release text at R: covered to the judge,
# red at the head. The card renders (not early: the gate's one refusal is the card's own decision), the reply that waits
# leaves current 8 refusing on that decision alone, naming its exit; the reply that merges writes the line at this
# head, and current 8 passes.
fc_published T1 "$FC_C" > "$FC_REC/landing-proofs.log"
fc_plan "$(fc_floor "$FC_B")
$(fc_reads "$FC_C")"
fc_page
FC_J3N="$(fc_table | /usr/bin/grep -F '|key=approve:merge-unproved|' | sed -n 's/^release-approval\/v1|dec=\([0-9]*\)|.*/\1/p')"
poke "$RFC" current 8 --check
FC_J3_PRE="$RC|$OUT"
expect_eq "JUDGE-3 precondition: the head is past the whole run, the card renders (exit 0) and its table holds the decision" "0|yes" "$FC_RC|$([ -n "$FC_J3N" ] && echo yes)"
FC_WD_COV=no; [ -z "$FC_J3N" ] || FC_WD_COV=yes   # the covered row of §WORD's table
expect_contains "JUDGE-3b …current 8 --check refuses before any reply, naming the decision's exit by its number on the page" "needs: the user — reply ${FC_J3N:-<n>} on the release card (merge without a whole run at this head), or wait for the pass" "$FC_J3_PRE"
expect_eq "JUDGE-3c …the replay line waits by default and merges as its other choice" "default=-|other=approve merge-unproved|choices=wait/merge" "$(fc_table | /usr/bin/grep -F '|key=approve:merge-unproved|' | /usr/bin/grep -oE 'default=[^|]*\|other=[^|]*' )|$(fc_table | /usr/bin/grep -F '|key=approve:merge-unproved|' | /usr/bin/grep -oE 'choices=[^|]*')"
FC_J3W="${FC_J3N:-0} wait, rest default"
fc_typed "$FC_J3W"
poke "$RFC" reply "$FC_J3W"
expect_eq "JUDGE-3d a reply that waits on it and takes every other default replays (exit 0), writing no merge-unproved line" "0|" "$RC|$(/usr/bin/grep '^approved: merge-unproved ' "$PFC")"
poke "$RFC" current 8 --check; FC_WN_COV="$RC"
expect_eq "JUDGE-3e …and current 8 --check still refuses (exit 1), on the regression alone" "1|1" "$RC|$(printf '%s\n' "$OUT" | /usr/bin/grep -cE '^regression	unproved	')"
expect_contains "JUDGE-3f …naming the person's exit" "or wait for the pass" "$OUT"
fc_page
FC_J3N="$(/usr/bin/grep -F '|key=approve:merge-unproved|' "$FC_REC/release-approval-$FC_H8-2.md" 2>/dev/null | sed -n 's/^release-approval\/v1|dec=\([0-9]*\)|.*/\1/p')"
FC_J3M="${FC_J3N:-0} merge"
fc_typed "$FC_J3M"
poke "$RFC" reply "$FC_J3M"
expect_eq "JUDGE-3g the card put again holds the one decision, and reply ${FC_J3M} replays it (exit 0)" "1|0" "${FC_J3N:-}|$RC"
expect_regex "JUDGE-3h …writing the approval at the working head with the user's words" "^approved: merge-unproved by Dana Fixture [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z head=$FC_R \"$FC_J3M\"\$" "$(/usr/bin/grep '^approved: merge-unproved ' "$PFC")"
expect_eq "JUDGE-3i …closing its ask on the person's ledger" "" "$(fc_owed | /usr/bin/grep -x 'approve:merge-unproved')"
poke "$RFC" current 8 --check; FC_WY_COV="$RC"
expect_eq "JUDGE-3j …after which current 8 --check passes (exit 0)" "0" "$RC"
[ "$RC" = 0 ] || printf '      current 8 --check said: %s\n' "$(printf '%s\n' "$OUT" | tail -4)"
s57_commit "$RFC" README.md 'prose past the approval' >/dev/null
poke "$RFC" current 8 --check
expect_eq "JUDGE-3k the head moves past it by prose: the release still holds, the merge-unproved line is stale, and current 8 --check refuses on the regression again" "1|1" "$RC|$(printf '%s\n' "$OUT" | /usr/bin/grep -cE '^regression	unproved	')"
git -C "$RFC" reset -q --hard "$FC_R"
fc_typed "$FC_WD" "$FC_WR"
rm -f "$FC_REC"/release-approval-*.md

# ============================================================
section "§WORD: the word accepts absence: the card draws the merge decision on exactly the floors the gate honours the word on, covered or uncovered, never owed"
# ============================================================
# fails-when: the card offers the word where current 8 --check will not honour it, or withholds it where it will; or the
# owed refusal names a reply. The gate HONOURS the word when it refuses without it and admits with it. The covered, green
# and owed card readings are §JUDGE's (JUDGE-3, JUDGE-4, JUDGE-2), carried; uncovered is its world with no landing for C.
fc_judged() { bash -c '. "$1/roots.sh"; . "$1/proof.sh"; _proof_floor_judge "$2" "$3" "$4" | cut -f1' _ "$FC_LIB" "$PFC" "$RFC" "$FC_R" 2>/dev/null; }
fc_regline() { printf '%s\n' "$OUT" | /usr/bin/grep -E '^regression	'; }  # the gate's regression line, as current 8 --check printed it
# (1) An uncovered head, the card's decision, the reply that merges, the gate admitting.
rm -f "$FC_REC/landing-proofs.log"
fc_plan "$(fc_floor "$FC_B")
$(fc_reads "$FC_C")"
expect_eq "WORD-0 precondition: with no run recorded for T1's code commit, the judge reads the head uncovered" "uncovered" "$(fc_judged)"
fc_page
FC_WDN="$(fc_table | /usr/bin/grep -F '|key=approve:merge-unproved|' | sed -n 's/^release-approval\/v1|dec=\([0-9]*\)|.*/\1/p')"; FC_WD_UNC=no; [ -z "$FC_WDN" ] || FC_WD_UNC=yes
expect_eq "WORD-1 at an uncovered head the card renders (exit 0) and its table holds the merge without a whole run" "0|yes" "$FC_RC|$FC_WD_UNC"
expect_eq "WORD-1a …and the number its table gives the decision is the one the judge's exit reads (proof_merge_decision)" "${FC_WDN:-none}" \
  "$(bash -c '. "$1/roots.sh"; . "$1/proof.sh"; proof_merge_decision "$2" "$3" "$4"' _ "$FC_LIB" "$PFC" "$RFC" "$FC_R" 2>/dev/null)"
expect_contains "WORD-1b …drawn on the page with the head's state" ". Merge without a whole run at this head — red at ${FC_B:0:8}, 2 landings before this head" "$(fc_unproved)"
expect_contains "WORD-1b2 …and naming the commit no run proved, as the judge's refusal does" "; commit ${FC_C:0:12} (no landing row) is not proved: " "$(fc_unproved)"
FC_WDM="${FC_WDN:-0} merge, rest default"; fc_typed "$FC_WDM"
poke "$RFC" reply "$FC_WDM"
expect_regex "WORD-1c reply ${FC_WDM} replays (exit 0), writing the word at the head with the user's words" "^0\|approved: merge-unproved by Dana Fixture [0-9T:Z-]+ head=$FC_R \"$FC_WDM\"\$" "$RC|$(/usr/bin/grep '^approved: merge-unproved ' "$PFC")"
poke "$RFC" current 8 --check; FC_WY_UNC="$RC"
expect_eq "WORD-1d …and current 8 --check is admitted (exit 0) over the uncovered floor" "0" "$RC"
/usr/bin/grep -v '^approved: merge-unproved ' "$PFC" > "$PFC.new" && mv "$PFC.new" "$PFC"
poke "$RFC" current 8 --check; FC_WN_UNC="$RC"
expect_eq "WORD-1e …the word taken out, the release approval kept: refused (exit 1) on the regression unproved, so the word is what admits" "1|unproved" "$RC|$(fc_regline | cut -f2)"
fc_typed "$FC_WD" "$FC_WR"; rm -f "$FC_REC"/release-approval-*.md
# (2) An owed head; the card's side is JUDGE-2's (the owed suite and its exit on the Tests line, no decision).
fc_plan "$(fc_floor "$FC_C" a.test.sh)
$(fc_reads "$FC_C")"
expect_eq "WORD-2 precondition: the whole run at C left a.test.sh red and nothing greened it since: the judge reads the head owed" "owed" "$(fc_judged)"
poke "$RFC" approve release 'ship it'
poke "$RFC" current 8 --check; FC_WN_OWED="$RC"
expect_eq "WORD-2e with the release approved at the head, current 8 --check refuses (exit 1) on the regression owed" "1|owed" "$RC|$(fc_regline | cut -f2)"
expect_contains "WORD-2f …the refusal names the pass as the exit" "needs: the pass — a fix row for a.test.sh, then the pass" "$(fc_regline)"
expect_absent "WORD-2g …and names no reply" "reply" "$(fc_regline)"
poke "$RFC" approve merge-unproved 'merge it'
poke "$RFC" current 8 --check; FC_WY_OWED="$RC"
expect_eq "WORD-2h the word recorded at the head over the owed floor: still refused (exit 1) on the regression owed" "1|owed|1" "$RC|$(fc_regline | cut -f2)|$(/usr/bin/grep -c '^approved: merge-unproved ' "$PFC")"
# (3) The states table, each row the card's draw beside the gate's exits without and with the word.
fc_wrow() { local h=no; [ "$3" = 0 ] || [ "$4" != 0 ] || h=yes; printf '%s:draw=%s:honour=%s ' "$1" "$2" "$h"; }  # <state> <draw> <exit without the word> <with it, or -> -> one cell
FC_WT="$(fc_wrow covered "$FC_WD_COV" "$FC_WN_COV" "$FC_WY_COV")$(fc_wrow uncovered "$FC_WD_UNC" "$FC_WN_UNC" "$FC_WY_UNC")$(fc_wrow owed "$FC_WD_OWED" "$FC_WN_OWED" "$FC_WY_OWED")$(fc_wrow green "$FC_WD_GREEN" "$FC_WN_GREEN" -)"
expect_eq "WORD-3 the table: the word drawn and honoured on covered and uncovered, neither on owed, needed on green by neither" \
  "covered:draw=yes:honour=yes uncovered:draw=yes:honour=yes owed:draw=no:honour=no green:draw=no:honour=no " "$FC_WT"
expect_eq "WORD-3b …each row read from its exits: covered and uncovered refused without the word and admitted with it, owed refused with it, green admitted without it" \
  "1/0|1/0|1/1|0" "$FC_WN_COV/$FC_WY_COV|$FC_WN_UNC/$FC_WY_UNC|$FC_WN_OWED/$FC_WY_OWED|$FC_WN_GREEN"
expect_eq "WORD-3c one predicate: the ask defined in lib/proof.sh and called by the card; the old one gone from both" "1|1|0" \
  "$(/usr/bin/grep -c '^proof_merge_ask()' "$FC_LIB/proof.sh")|$(/usr/bin/grep -c 'proof_merge_ask "$PV_PLAN"' "$BIONIC_HOOKS_DIR/poker/plan.sh")|$(cat "$FC_LIB/proof.sh" "$BIONIC_HOOKS_DIR/poker/plan.sh" | /usr/bin/grep -c proof_merge_unproved)"

# ============================================================
section "§OWED-FIRST: the red the whole run left outranks a commit no run proved: the floor reads owed, the word drawn and honoured nowhere"
# ============================================================
# fails-when: past a floor whose owed suite no landing greened, a code commit no run proved turns the judge uncovered, so
# the card draws the word and the gate honours it over a known red; or the same where the floor is not in the head's history.
fc_fj() { bash -c '. "$1/roots.sh"; . "$1/proof.sh"; _proof_floor_judge "$2" "$3" "$4"' _ "$FC_LIB" "$PFC" "$RFC" "$FC_R" 2>/dev/null; }
fc_plan "$(fc_floor "$FC_B" a.test.sh)
$(fc_reads "$FC_C")"
expect_eq "OF-1 a whole run at B left a.test.sh red and T1's code at C has no run: the judge reads the head owed, naming the suite" "owed	a.test.sh" "$(fc_fj)"
expect_eq "OF-1b …proof_merge_ask exits 2 there, printing the owed suite and no merge line" "a.test.sh|rc=2" "$(fc_mu "$FC_R")"
fc_page --preview
expect_eq "OF-2 the card puts the release decision and no merge without a whole run, as JUDGE-2 at an owed head" "yes|" "$(fc_has "$(fc_under Decisions | fc_flat)" 'Release 1.0.0')|$(fc_unproved)"
poke "$RFC" approve release 'ship it'; poke "$RFC" approve merge-unproved 'merge it'
poke "$RFC" current 8 --check
expect_eq "OF-3 the word recorded at the head: current 8 --check refuses (exit 1) on the regression owed, never covered" "1|owed|1" "$RC|$(fc_regline | cut -f2)|$(/usr/bin/grep -c '^approved: merge-unproved ' "$PFC")"
expect_contains "OF-3b …naming the pass or a fix row as the exit" "needs: the pass — a fix row for a.test.sh, then the pass" "$(fc_regline)"
expect_absent "OF-3c …and no reply" "reply" "$(fc_regline)"
FC_OFX="$(git -C "$RFC" commit-tree -p "$FC_B" -m 'a whole run off the head line' "$FC_C^{tree}")"
fc_plan "$(fc_floor "$FC_OFX" a.test.sh)
$(fc_reads "$FC_C")"
expect_eq "OF-4 a floor not in the head's history keeps its red: the judge reads owed, and the ask draws nothing" "owed	a.test.sh|a.test.sh|rc=2" "$(fc_fj)|$(fc_mu "$FC_R")"
rm -f "$FC_REC"/release-approval-*.md

# §JUDGE's world as it was left: T1's landing recorded, the head R.
fc_published T1 "$FC_C" > "$FC_REC/landing-proofs.log"; rm -f "$FC_REC"/release-approval-*.md
fc_typed "$FC_WD" "$FC_WR"

# ============================================================
section "§UNPROVED-ASK: the merge without a pass is an answer where an open integrate row waits on the release"
# ============================================================
# fails-when: approve, or the card's reply, writes no merge-unproved line on a plan whose integrate row reads no approval:merge; or writes one where no open integrate row stands.
fc_ua() {  # [<integrate row's status>] -> PFC: the red world, the integrate row reading no approval but its own release
  fc_plan "$(fc_floor "$FC_B")
$(fc_reads "$FC_C")" "s/| pending | approval:release, approval:merge, head |\$/| ${1:-pending} | head |/"
}
fc_ua; poke "$RFC" approve merge-unproved 'words'
expect_eq "UA-1 approve merge-unproved writes the line (exit 0) where the integrate row is open and no row reads approval:merge" "0|1" "$RC|$(/usr/bin/grep -c '^approved: merge-unproved ' "$PFC")"
fc_ua; fc_page
FC_UAN="$(fc_table | /usr/bin/grep -F '|key=approve:merge-unproved|' | sed -n 's/^release-approval\/v1|dec=\([0-9]*\)|.*/\1/p')"
FC_UAM="${FC_UAN:-0} merge, rest default"; fc_typed "$FC_UAM"
poke "$RFC" reply "$FC_UAM"
expect_eq "UA-2 …and so does reply on the card's decision (exit 0)" "0|1" "$RC|$(/usr/bin/grep -c '^approved: merge-unproved ' "$PFC")"
for FC_UAS in dropped landed; do
  fc_ua "$FC_UAS"
  poke "$RFC" approve merge-unproved 'words'
  expect_eq "UA-3 …refused with the integrate row $FC_UAS, the plan unchanged" "1|0" "$RC|$(/usr/bin/grep -c '^approved: merge-unproved ' "$PFC")"
  expect_contains "UA-3b …naming what the rows read, in the refusal's words ($FC_UAS)" "reads approval:merge-unproved, so recording it would satisfy nothing; the rows read: (no named approval)" "$OUT"
done
fc_typed "$FC_WD" "$FC_WR"
rm -f "$FC_REC"/release-approval-*.md "$FC_REC/landing-proofs.log"

# ============================================================
section "§COVERED: a failed review its fix landing answered reads covered on the card, naming the landing, and the sitrep counts it as the card does"
# ============================================================
# FIXTURE FIDELITY: the adversarial reading at C fails on one S2 finding to fix (its record in the readers' grammar,
# its proof line by the writer), newer than the passing ones; the fix row T4 is born of that finding (the marker
# `task-add --born` writes) and landed green at F, the head (its events as the line writes them). The card is the
# real verb's page and the count is the real sitrep's sheet, over the same plan and head.
# fails-when: the Reviews line still prints failing after the fix landed, does not name the fix's landing, reads
# covered before the fix landed; or the sitrep's failed count differs from the card's failing lines, or a sitrep
# planted back to the raw result agrees with the card.
printf 'question: adversarial\nresult: fail\nscope: piece\nreviewed: %s..%s\nfindings: 1\nfinding: 1 S2 on lib/x.sh:1 the x writer drops its error\nshown: 1 bash tests/a.test.sh\n\nwhat the reader found\n' \
  "${FC_B:0:10}" "${FC_C:0:10}" > "$FC_REC/adversarial-fail.md"
FC_CV_FAIL="$(fc_line review "$FC_C" 2026-10-12T12:30:00Z record/wave-x/adversarial-fail.md adversarial w-read fail piece)"
cv_reviews() { fc_under Reviews | fc_flat; }
cv_adv() {  # -> the adversarial line of the Reviews section, unfolded, up to the next line's icon
  cv_reviews | awk '{ i = index($0, "adversarial — "); if (!i) exit; split(substr($0, i), a, /(✅|✖️|❔|➖)/); sub(/ +$/, "", a[1]); print a[1] }'
}
cv_card_failing() { fc_under Reviews | /usr/bin/grep -c '^ *✖️'; }
cv_sitrep_failed() {  # [<poker>] -> the failed count of the sitrep sheet's reviews line over PFC, as this session
  ( cd "$RFC" && env CLAUDE_CODE_SESSION_ID="$SID" bash "${1:-$POKER}" sitrep "$PFC" 2>/dev/null ) \
    | sed -n 's/^reviews: [0-9]* passed, \([0-9]*\) failed, .*/\1/p'
}
fc_plan "$FC_GOOD
$FC_CV_FAIL"
fc_page --preview
expect_contains "COVERED-0 precondition: the Reviews section renders the adversarial line" "adversarial — " "$(cv_reviews)"
expect_contains "COVERED-0b the control: before any fix lands the adversarial line reads failing" "failing" "$(cv_adv)"
FC_CV0_CARD="$(cv_card_failing)"; FC_CV0_SR="$(cv_sitrep_failed)"
expect_eq "COVERED-0c …and the card's failing lines and the sitrep's failed count agree: one each" "1|1" "$FC_CV0_CARD|$FC_CV0_SR"
FC_CV_F="$(s57_commit "$RFC" lib/x.sh 'T4: the fix the adversarial reading asked for')"
fc_published T4 "$FC_CV_F" > "$FC_REC/landing-proofs.log"
fc_plan "$FC_GOOD
$FC_CV_FAIL
- T4: landed $FC_CV_F 2026-10-12T14:00:00Z born: review S2 on of=record/wave-x/adversarial-fail.md#1"
awk '{ print } /^\| T2 \|/ {
  print "| T4 | 4 | build | fix the x error · born: review | implementor | — | 30 | REQ-1 | lib/x.sh | — | — | landed | approval:plan |" }' \
  "$PFC" > "$PFC.new" && mv "$PFC.new" "$PFC"
fc_page --preview
expect_contains "COVERED-1 AC-13.1 the fix landed at the head: the adversarial line reads covered" "covered" "$(cv_adv)"
expect_absent "COVERED-1b …and no longer failing (COVERED-1 read the same line)" "failing" "$(cv_adv)"
expect_contains "COVERED-1c …naming the covering landing, its row and commit" "T4 at ${FC_CV_F:0:8}" "$(cv_adv)"
FC_CV1_CARD="$(cv_card_failing)"; FC_CV1_SR="$(cv_sitrep_failed)"
expect_eq "COVERED-2 the sitrep's failed count over the same fixture agrees with the card: none failing on either" "0|0" "$FC_CV1_CARD|$FC_CV1_SR"
# THE PLANT: a copy of the tree whose sitrep is put back to counting the recorded result; it then disagrees with the card.
FC_CVM="$TMPROOT/cv-mut"; mkdir -p "$FC_CVM/payload"
cp -R "$BIONIC_HOOKS_DIR" "$FC_CVM/hooks" && cp -R "$BIONIC_HOOKS_DIR/../payload/scripts" "$FC_CVM/payload/scripts"
sed 's/if \[ "\$jrc" -ne 2 \]; then/if false; then/' "$BIONIC_HOOKS_DIR/poker/sitrep.sh" > "$FC_CVM/hooks/poker/sitrep.sh"
expect_eq "COVERED-3 the plant changed the copy's sitrep (it reads the one reader today)" "1" \
  "$(cmp -s "$BIONIC_HOOKS_DIR/poker/sitrep.sh" "$FC_CVM/hooks/poker/sitrep.sh" && echo 0 || echo 1)"
expect_eq "COVERED-3b …and the planted sitrep counts the fixed review failed while the card reads none: the readers diverge" "0|1" \
  "$FC_CV1_CARD|$(cv_sitrep_failed "$FC_CVM/hooks/session-poker.sh")"
git -C "$RFC" reset -q --hard "$FC_R"
rm -f "$FC_REC/landing-proofs.log" "$FC_REC"/release-approval-*.md "$FC_REC/adversarial-fail.md"

finish
