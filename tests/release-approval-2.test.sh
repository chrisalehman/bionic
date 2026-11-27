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
# at the head; reply on that decision appends no merge-unproved approval at the head; or `current 8 --check`
# passes before that line is written, or refuses after it.
FC_F6="$(s57_commit "$RFC" lib/x.sh 'T6: the fix that greens a')"
fc_published T6 "$FC_F6" > "$FC_SEED"
fc_t6_row() {  # <page> -> the page with T6's Tasks row after T2's, dispatched
  awk '{ print } /^\| T2 \|/ { print "| T6 | 4 | build | fix the x message · born: review | — | 30 | REQ-1 | lib/x.sh | — |" }' "$1" > "$1.new" && mv "$1.new" "$1"
  printf 'run/v1|ev=dispatch|row=T6|name=implementor|at=\n' >> "$FC_EV"
}
fc_judge_plan() {  # <floor's owed suites> -> PFC: the whole run at C left <suites> red, T6 landed after it, born of the adversarial finding
  fc_plan "$(fc_floor "$FC_C" "$1")
$(fc_reads "$FC_C")
run/v1|ev=born|row=T6|reason=review S3 off|finding=record/wave-x/adversarial.md#1|at=2026-10-12T12:45:00Z" "" fc_t6_row
}
fc_unproved() { fc_under Decisions | fc_flat | /usr/bin/grep -o "[0-9]*\. Merge without a whole run at this head — [^·]*· recommended: wait for the pass · default: none"; }
fc_judge_plan a.test.sh
expect_eq "JUDGE-00 precondition: the page stands at 15 with no State, and T6's row and landing are the run's" \
  "15|0|state=landed|commit=$FC_F6" "$(sed -n 's/^canonical_sdlc_version: //p' "$PFC")|$(/usr/bin/grep -c '^## SDLC State' "$PFC")|$(bash "${BIONIC_SCRIPTS_DIR}/payload/scripts/reader.sh" "$PFC" status T6 | /usr/bin/grep -E '^(state|commit)=' | paste -sd'|' -)"
fc_page --preview
expect_contains "JUDGE-0 precondition: the Tests section renders the whole-suite line" "whole suite: " "$(fc_under Tests)"
expect_contains "JUDGE-1 a red the whole run left and a later landing greened: the page reads red at the run's head, the two landings since counted" "whole suite: red at ${FC_C:0:8}, 2 landings before this head" "$(fc_under Tests | fc_flat)"
expect_eq "JUDGE-1b …and the word red is on the line, never covered" "1|0" "$(fc_under Tests | fc_flat | /usr/bin/grep -cw 'red')|$(fc_under Tests | fc_flat | /usr/bin/grep -c 'covered')"
expect_contains "JUDGE-1c …and the merge without a pass at this head is a decision, the state on it, waiting recommended" ". Merge without a whole run at this head — red at ${FC_C:0:8}, 2 landings before this head · recommended: wait for the pass · default: none" "$(fc_unproved)"
git -C "$RFC" reset -q --hard "$FC_R"
rm -f "$FC_SEED"
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
# ck_ans -> the checked advance's answer as its code, from RC and OUT as poke left them: 0 would advance, 1 would refuse.
# The check exits 0 on either answer, so the answer is read from its words; a check that exited non-zero is x<its exit>.
ck_ans() {
  case "$RC:$(printf '%s\n' "$OUT" | awk 'index($0, "--check: would advance") { print "advance"; exit }
      index($0, "--check: would refuse") { print "refuse"; exit }')" in
    0:advance) printf 0 ;; 0:refuse) printf 1 ;; *) printf 'x%s' "$RC" ;;
  esac
}
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
expect_eq "JUDGE-4d …proof_merge_ask exits 1 at that head, printing nothing; over a whole run at B it asks at the code head C, naming the commit no run proved and T1, whose landing the log holds" "rc=1|red at ${FC_B:0:8}, 1 landing before this head; commit ${FC_C:0:12} (row T1) is not proved: no run of its row's suites is recorded at it|rc=0" "$FC_J4M|$(fc_mu "$FC_C")"
fc_plan "$FC_GOOD"; fc_page; fc_typed "$FC_WD"
poke "$RFC" reply "$FC_WD"; FC_J4_REPLY="$RC"
poke "$RFC" current 8 --check; FC_WN_GREEN="$(ck_ans)"
expect_eq "JUDGE-4e …the reply that takes every default replays (exit 0), writing no merge-unproved line, and current 8 --check is admitted (exit 0)" "0||0" "$FC_J4_REPLY|$(fc_appr merge-unproved)|$(ck_ans)"
[ "$(ck_ans)" = 0 ] || printf '      current 8 --check said: %s\n' "$(printf '%s\n' "$OUT" | tail -4)"
git -C "$RFC" reset -q --hard "$FC_R"; fc_typed "$FC_WD" "$FC_WR"; rm -f "$FC_REC"/release-approval-*.md
# JUDGE-3: the whole run at B, T1's code at C landed green on its suite, the release text at R: covered to the judge,
# red at the head. The card renders (not early: the gate's one refusal is the card's own decision), the reply that waits
# leaves current 8 refusing on that decision alone, naming its exit; the reply that merges writes the line at this
# head, and current 8 passes.
fc_published T1 "$FC_C" > "$FC_SEED"
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
expect_eq "JUDGE-3d a reply that waits on it and takes every other default replays (exit 0), writing no merge-unproved line" "0|" "$RC|$(fc_appr merge-unproved)"
poke "$RFC" current 8 --check; FC_WN_COV="$(ck_ans)"
expect_eq "JUDGE-3e …and current 8 --check still refuses (exit 0: would refuse), on the regression alone" "1|1" "$(ck_ans)|$(printf '%s\n' "$OUT" | /usr/bin/grep -cE '^regression	unproved	')"
expect_contains "JUDGE-3f …naming the person's exit" "or wait for the pass" "$OUT"
fc_page
FC_J3N="$(/usr/bin/grep -F '|key=approve:merge-unproved|' "$FC_REC/release-approval-$FC_H8-2.md" 2>/dev/null | sed -n 's/^release-approval\/v1|dec=\([0-9]*\)|.*/\1/p')"
FC_J3M="${FC_J3N:-0} merge"
fc_typed "$FC_J3M"
poke "$RFC" reply "$FC_J3M"
expect_eq "JUDGE-3g the card put again holds the one decision, and reply ${FC_J3M} replays it (exit 0)" "1|0" "${FC_J3N:-}|$RC"
expect_regex "JUDGE-3h …writing the approval at the working head with the user's words" "^run/v1\\|ev=approval\\|key=merge-unproved\\|by=Dana Fixture\\|head=$FC_R\\|said=$FC_J3M\\|at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z\$" "$(fc_appr merge-unproved)"
expect_eq "JUDGE-3i …closing its ask on the person's ledger" "" "$(fc_owed | /usr/bin/grep -x 'approve:merge-unproved')"
poke "$RFC" current 8 --check; FC_WY_COV="$(ck_ans)"
expect_eq "JUDGE-3j …after which current 8 --check passes (exit 0)" "0" "$(ck_ans)"
[ "$(ck_ans)" = 0 ] || printf '      current 8 --check said: %s\n' "$(printf '%s\n' "$OUT" | tail -4)"
s57_commit "$RFC" README.md 'prose past the approval' >/dev/null
poke "$RFC" current 8 --check
expect_eq "JUDGE-3k the head moves past it by prose: the release still holds, the merge-unproved line is stale, and current 8 --check refuses on the regression again" "1|1" "$(ck_ans)|$(printf '%s\n' "$OUT" | /usr/bin/grep -cE '^regression	unproved	')"
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
rm -f "$FC_SEED"
fc_plan "$(fc_floor "$FC_B")
$(fc_reads "$FC_C")"
expect_eq "WORD-0 precondition: with no run recorded for T1's code commit, the judge reads the head uncovered" "uncovered" "$(fc_judged)"
fc_page
FC_WDN="$(fc_table | /usr/bin/grep -F '|key=approve:merge-unproved|' | sed -n 's/^release-approval\/v1|dec=\([0-9]*\)|.*/\1/p')"; FC_WD_UNC=no; [ -z "$FC_WDN" ] || FC_WD_UNC=yes
expect_eq "WORD-1 at an uncovered head the card renders (exit 0) and its table holds the merge without a whole run" "0|yes" "$FC_RC|$FC_WD_UNC"
expect_eq "WORD-1a …and the number its table gives the decision is the one the judge's exit reads (proof_merge_decision)" "${FC_WDN:-none}" \
  "$(bash -c '. "$1/roots.sh"; . "$1/proof.sh"; proof_merge_decision "$2" "$3" "$4"' _ "$FC_LIB" "$PFC" "$RFC" "$FC_R" 2>/dev/null)"
expect_contains "WORD-1b …drawn on the page with the head's state" ". Merge without a whole run at this head — red at ${FC_B:0:8}, 2 landings before this head" "$(fc_unproved)"
expect_contains "WORD-1b2 …and naming the commit no run proved and its landing's row, as the judge's refusal does" "; commit ${FC_C:0:12} (row T1) is not proved: " "$(fc_unproved)"
FC_WDM="${FC_WDN:-0} merge, rest default"; fc_typed "$FC_WDM"
poke "$RFC" reply "$FC_WDM"
expect_regex "WORD-1c reply ${FC_WDM} replays (exit 0), writing the word at the head with the user's words" "^0\\|run/v1\\|ev=approval\\|key=merge-unproved\\|by=Dana Fixture\\|head=$FC_R\\|said=$FC_WDM\\|at=[0-9T:Z-]+\$" "$RC|$(fc_appr merge-unproved)"
poke "$RFC" current 8 --check; FC_WY_UNC="$(ck_ans)"
expect_eq "WORD-1d …and current 8 --check is admitted (exit 0) over the uncovered floor" "0" "$(ck_ans)"
/usr/bin/grep -v '|ev=approval|key=merge-unproved|' "$FC_REC/run.log" > "$FC_REC/run.log.new"; mv "$FC_REC/run.log.new" "$FC_REC/run.log"
poke "$RFC" current 8 --check; FC_WN_UNC="$(ck_ans)"
expect_eq "WORD-1e …the word taken out, the release approval kept: refused (exit 0: would refuse) on the regression unproved, so the word is what admits" "1|unproved" "$(ck_ans)|$(fc_regline | cut -f2)"
fc_typed "$FC_WD" "$FC_WR"; rm -f "$FC_REC"/release-approval-*.md
# (2) An owed head; the card's side is JUDGE-2's (the owed suite and its exit on the Tests line, no decision).
fc_plan "$(fc_floor "$FC_C" a.test.sh)
$(fc_reads "$FC_C")"
expect_eq "WORD-2 precondition: the whole run at C left a.test.sh red and nothing greened it since: the judge reads the head owed" "owed" "$(fc_judged)"
poke "$RFC" approve release 'ship it'; FC_AU="$RC|$(fc_appr release | grep -c .)"; said_as sdk "$RFC" 'ship it'; poke "$RFC" approve release 'ship it'
expect_eq "WORD-2a approve release on words no prompt holds, then on words only a program sent: refused (exit 1) each, nothing appended" "1|0|1|0" "$FC_AU|$RC|$(fc_appr release | grep -c .)"
said_as typed "$RFC" 'ship it' 'merge it'; poke "$RFC" approve release 'ship it'
poke "$RFC" current 8 --check; FC_WN_OWED="$(ck_ans)"
expect_eq "WORD-2e with the release approved at the head, current 8 --check refuses (exit 0: would refuse) on the regression owed" "1|owed" "$(ck_ans)|$(fc_regline | cut -f2)"
expect_contains "WORD-2f …the refusal names the pass as the exit" "needs: the pass — a fix row for a.test.sh, then the pass" "$(fc_regline)"
expect_absent "WORD-2g …and names no reply" "reply" "$(fc_regline)"
poke "$RFC" approve merge-unproved 'merge it'
poke "$RFC" current 8 --check; FC_WY_OWED="$(ck_ans)"
expect_eq "WORD-2h the word recorded at the head over the owed floor: still refused (exit 0: would refuse) on the regression owed" "1|owed|1" "$(ck_ans)|$(fc_regline | cut -f2)|$(fc_appr merge-unproved | grep -c .)"
# (3) The states table, each row the card's draw beside the gate's exits without and with the word.
fc_wrow() { local h=no; [ "$3" = 0 ] || [ "$4" != 0 ] || h=yes; printf '%s:draw=%s:honour=%s ' "$1" "$2" "$h"; }  # <state> <draw> <exit without the word> <with it, or -> -> one cell
FC_WT="$(fc_wrow covered "$FC_WD_COV" "$FC_WN_COV" "$FC_WY_COV")$(fc_wrow uncovered "$FC_WD_UNC" "$FC_WN_UNC" "$FC_WY_UNC")$(fc_wrow owed "$FC_WD_OWED" "$FC_WN_OWED" "$FC_WY_OWED")$(fc_wrow green "$FC_WD_GREEN" "$FC_WN_GREEN" -)"
expect_eq "WORD-3 the table: the word drawn and honoured on covered and uncovered, neither on owed, needed on green by neither" \
  "covered:draw=yes:honour=yes uncovered:draw=yes:honour=yes owed:draw=no:honour=no green:draw=no:honour=no " "$FC_WT"
expect_eq "WORD-3b …each row read from the check's answers (1 would refuse, 0 would advance): covered and uncovered refused without the word and admitted with it, owed refused with it, green admitted without it" \
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
expect_eq "OF-3 the word recorded at the head: current 8 --check refuses (exit 0: would refuse) on the regression owed, never covered" "1|owed|1" "$(ck_ans)|$(fc_regline | cut -f2)|$(fc_appr merge-unproved | grep -c .)"
expect_contains "OF-3b …naming the pass or a fix row as the exit" "needs: the pass — a fix row for a.test.sh, then the pass" "$(fc_regline)"
expect_absent "OF-3c …and no reply" "reply" "$(fc_regline)"
FC_OFX="$(git -C "$RFC" commit-tree -p "$FC_B" -m 'a whole run off the head line' "$FC_C^{tree}")"
fc_plan "$(fc_floor "$FC_OFX" a.test.sh)
$(fc_reads "$FC_C")"
expect_eq "OF-4 a floor not in the head's history keeps its red: the judge reads owed, and the ask draws nothing" "owed	a.test.sh|a.test.sh|rc=2" "$(fc_fj)|$(fc_mu "$FC_R")"
rm -f "$FC_REC"/release-approval-*.md

# §JUDGE's world as it was left: T1's landing recorded, the head R.
fc_published T1 "$FC_C" > "$FC_SEED"; rm -f "$FC_REC"/release-approval-*.md
fc_typed "$FC_WD" "$FC_WR" words

# ============================================================
section "§UNPROVED-ASK: the merge without a pass is an answer where an open integrate row waits on the release"
# ============================================================
# fails-when: approve, or the card's reply, writes no merge-unproved line on a plan whose integrate row reads no approval:merge; or writes one where no open integrate row stands.
fc_ua_row() {  # <page> -> the integrate row reading no approval, landed or dropped as FC_UA_ST says
  sed 's/^\(| T3 | 8 | integrate | merge into main | \)approval:merge |/\1— |/' "$1" > "$1.new" && mv "$1.new" "$1"
  case "$FC_UA_ST" in landed) printf 'run/v1|ev=published|row=T3|at=\n' ;; dropped) printf 'run/v1|ev=drop|row=T3|why=dropped|at=\n' ;; esac >> "$FC_EV"
}
fc_ua() {  # [<integrate row's status>] -> PFC: the red world, the integrate row reading no approval but its own release
  FC_UA_ST="${1:-pending}"; fc_plan "$(fc_floor "$FC_B")
$(fc_reads "$FC_C")" "" fc_ua_row
}
fc_ua; FC_S0="$(cksum < "$PFC")"; poke "$RFC" approve merge-unproved 'words'
expect_eq "UA-1 approve merge-unproved appends it (exit 0) where the integrate row is open and no row reads approval:merge, the plan's sum the same" "0|1|$FC_S0" "$RC|$(fc_appr merge-unproved | grep -c .)|$(cksum < "$PFC")"
FC_AT='|by=me|at=2026-10-12T14:00:00Z'; fc_ua; printf 'run/v1|ev=approval|key=merge-unproved|head=%s%s\n' "$FC_R" "$FC_AT" >> "$FC_REC/run.log"; FC_S0="$(cksum < "$PFC")"; poke "$RFC" approve merge-unproved 'again'; FC_UA1="$RC|$(cksum < "$PFC")"
fc_plan "$(fc_floor "$FC_B")" '/|ev=approval|key=step3|/d'; printf 'run/v1|ev=approval|key=step3%s\n' "$FC_AT" >> "$FC_REC/run.log"; FC_S1="$(cksum < "$PFC")"; poke "$RFC" approve plan 'approved'
expect_eq "UA-1b an approval the log holds at the working head, and the plan's, is not given again (exit 1), the plan unchanged" "1|$FC_S0|1|$FC_S1" "$FC_UA1|$RC|$(cksum < "$PFC")"
fc_ua; fc_page
FC_UAN="$(fc_table | /usr/bin/grep -F '|key=approve:merge-unproved|' | sed -n 's/^release-approval\/v1|dec=\([0-9]*\)|.*/\1/p')"
FC_UAM="${FC_UAN:-0} merge, rest default"; fc_typed "$FC_UAM"
poke "$RFC" reply "$FC_UAM"
expect_eq "UA-2 …and so does reply on the card's decision (exit 0)" "0|1" "$RC|$(fc_appr merge-unproved | grep -c .)"
for FC_UAS in dropped landed; do
  fc_ua "$FC_UAS"
  poke "$RFC" approve merge-unproved 'words'
  expect_eq "UA-3 …refused with the integrate row $FC_UAS, the plan unchanged" "1|0" "$RC|$(fc_appr merge-unproved | grep -c .)"
  expect_contains "UA-3b …naming what the rows read, in the refusal's words ($FC_UAS)" "reads approval:merge-unproved, so recording it would satisfy nothing; the rows read: (no named approval)" "$OUT"
done
fc_typed "$FC_WD" "$FC_WR"
rm -f "$FC_REC"/release-approval-*.md "$FC_SEED"

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
cv_mark() { fc_under Reviews | awk -v q="$1 — " 'index($0, q) { print $1; exit }'; }  # <question> -> the mark its Reviews line opens on
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
fc_published T4 "$FC_CV_F" > "$FC_SEED"
cv_t4_row() {  # <page> -> the page with T4's Tasks row after T2's, dispatched
  awk '{ print } /^\| T2 \|/ { print "| T4 | 4 | build | fix the x error · born: review | — | 30 | REQ-1 | lib/x.sh | — |" }' "$1" > "$1.new" && mv "$1.new" "$1"
  printf 'run/v1|ev=dispatch|row=T4|name=implementor|at=\n' >> "$FC_EV"
}
fc_plan "$FC_GOOD
$FC_CV_FAIL
run/v1|ev=born|row=T4|reason=review S2 on|finding=record/wave-x/adversarial-fail.md#1|at=2026-10-12T12:45:00Z" "" cv_t4_row
fc_page --preview
expect_contains "COVERED-1 AC-13.1 the fix landed at the head: the adversarial line reads covered" "covered" "$(cv_adv)"
expect_absent "COVERED-1b …and no longer failing (COVERED-1 read the same line)" "failing" "$(cv_adv)"
expect_contains "COVERED-1c …naming the covering landing, its row and commit" "T4 at ${FC_CV_F:0:8}" "$(cv_adv)"
# fails-when: a covered reading that failed or flagged draws the pass mark, or its line does not say the result.
expect_eq "COVERED-1d …the covered fail draws no pass mark and says its result; the evidence pass beside it keeps ✅" \
  "➖|result fail|✅" "$(cv_mark adversarial)|$(cv_adv | /usr/bin/grep -o 'result fail')|$(cv_mark evidence)"
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
rm -f "$FC_SEED" "$FC_REC"/release-approval-*.md "$FC_REC/adversarial-fail.md"
# A newer reading that flags, its range held by the release text's cover, its record and proof line as written.
printf 'question: adversarial\nresult: flag\nscope: piece\nreviewed: %s..%s\nfindings: 1\nfinding: 1 S3 off lib/x.sh:1 a name could be plainer\n\nwhat the reader found\n' \
  "${FC_B:0:10}" "${FC_C:0:10}" > "$FC_REC/adversarial-flag.md"
fc_plan "$FC_GOOD
$(fc_line review "$FC_C" 2026-10-12T12:30:00Z record/wave-x/adversarial-flag.md adversarial w-read flag piece)"
fc_page --preview; FC_CV_NEW="$(bash "${BIONIC_SCRIPTS_DIR}/payload/scripts/reader.sh" "$PFC" reviews | /usr/bin/grep 'question=adversarial' | tail -1)"
expect_eq "COVERED-4 the reader's newest adversarial reading a flag, the card renders, says its result and draws no pass mark; evidence keeps ✅" \
  "0|result=flag|result flag|➖|✅" "$FC_RC|$(printf '%s' "$FC_CV_NEW" | /usr/bin/grep -o 'result=[a-z]*')|$(cv_adv | /usr/bin/grep -o 'result flag')|$(cv_mark adversarial)|$(cv_mark evidence)"
rm -f "$FC_REC"/release-approval-*.md "$FC_REC/adversarial-flag.md"

# ============================================================
section "§TASK: a run with no release row is asked the release approval at the advance to 8 and at the close, and its card asks what the gate owes"
# ============================================================
# FIXTURE FIDELITY: the prelude's run as a task-scale run holds it (regression no; a build, a verify, a review and an
# integrate row; no documents or test row), each criterion discharged by a proof with no auditor's word, so its
# auditor cell is the evidence review's, which flagged; the first criterion is the person's own check (T4),
# unconfirmed, and at double the auditor's CONFIRMED is its word. The gate's two asks at 8 are walls.sh `matrix_unruled` and each row
# `matrix_row_awaits` holds.
# fails-when: current 8 or the close admits the run with its card unanswered, or refuses after the typed reply; or the
#   card's owed rows are not the gate's: at single rigor a waiver nothing owes, or the person's confirmation left off; or,
#   a fix landed past the approved head, the card drawn there puts no renewal or the close admits the stale approval.
fc_task() {  # <page> -> the page as a task-scale run at rigor FC_RIGOR
  sed -e "s/^rigor: double$/rigor: $FC_RIGOR/" -e 's/^scale: wave$/scale: task\nregression: no/' -e '/^release: /d' \
    -e 's/^| T2 | 7 | doc .*$/| T2 | 5 | verify | the walk | T1 | 10 | REQ-1 | .bionic\/docs\/record\/wave-x\/walk.md | — |\n| T4 | 6 | review | the critic · questions: evidence,adversarial,structure | T1 | 15 | REQ-1 | .bionic\/docs\/record\/wave-x\/critic.md | — |/' \
    -e 's/^\(| T3 | 8 | integrate | merge into main | \)approval:merge |/\1T2, T4 |/' -e 's/^| — | AC-1\.1 | T1 |/| — | AC-1.1 | T4 |/' \
    "$1" > "$1.n" && mv "$1.n" "$1" && fc_owed_now "$1"
  [ "$FC_RIGOR" = double ] || { sed 's/|auditor=CONFIRMED|/|/' "$FC_EV" > "$FC_EV.n" && mv "$FC_EV.n" "$FC_EV"; }
  printf 'run/v1|ev=%s|at=\n' 'dispatch|row=T4|name=critic' 'proof|ac=AC-1.2|evidence=record/generic-evidence.md' >> "$FC_EV"
}
fc_task_plan() {  # <rigor> -> PFC: the task-scale run at <rigor>, its whole reading at C, the evidence review flagged
  local q; FC_RIGOR="$1"
  fc_plan "$(for q in evidence adversarial structure; do fc_line review "$FC_C" 2026-10-12T12:00:00Z "record/wave-x/$q.md" "$q" w-read "$([ "$q" = evidence ] && echo flag || echo pass)" whole; done)" "" fc_task
}
fc_owes() {  # -> the card's owed rows|the rows the gate's two asks at 8 name
  printf '%s|' "$(fc_keys | sed -n 's/^row://p' | sort | paste -sd' ' -)"
  bash -c '. "$1/run.sh" && . "$1/units.sh" && . "$1/proof.sh" && . "$1/walls.sh" && PLAN="$2" && { matrix_unruled "$2" 8 "$3"; matrix_load "$2" "$3" &&
    matrix_table_rows | while IFS=$'"'"'\037'"'"' read -r a t s e u c w; do ! matrix_row_awaits "$t" "$s" "$u" "$c" "$w" || echo "$a"; done; } | sort -u | paste -sd" " -' _ "$FC_LIB" "$PFC" "$FC_R" 2>/dev/null
}
fc_close() { ( cd "$RFC" && env CLAUDE_CODE_SESSION_ID="$SID" bash "$BIONIC_SCRIPTS_DIR/payload/scripts/close-out.sh" "$PFC" check ) 2>/dev/null | /usr/bin/grep -m1 '^facts: '; }
fc_task_plan double; fc_page; FC_TD="$(fc_owes)"
fc_task_plan single
expect_eq "TASK-0 precondition: the page has an integrate row, no documents or test row, and is at single rigor" "1|0|single" \
  "$(/usr/bin/grep -c '| integrate |' "$PFC")|$(/usr/bin/grep -cE '\| (doc|test) \|' "$PFC")|$(sed -n 's/^rigor: //p' "$PFC")"
fc_page
expect_eq "TASK-1 the card is drawn (exit 0) and puts the release approval" "0|yes" "$FC_RC|$(fc_keys | grep -qx approve:release && echo yes)"
expect_eq "TASK-2 its owed rows are the gate's: at single the person's check alone, at double the auditor's row too" "AC-1.1|AC-1.1|AC-1.1 AC-1.2|AC-1.1 AC-1.2" "$(fc_owes)|$FC_TD"
expect_contains "TASK-2b …and at single the row the evidence review did not confirm reads proved" "acceptance — 1 of 2 criteria proved; 1 awaiting your confirmation" "$(fc_under Tests)"
poke "$RFC" current 8 --check
expect_eq "TASK-3 with the card unanswered, current 8 --check refuses (exit 0: would refuse), naming the approval" "1|yes" "$(ck_ans)|$(fc_has "$OUT" 'carries no approved: release line')"
expect_contains "TASK-4 …and the close refuses on it" "facts: WOULD REFUSE — no approved: release line names a head" "$(fc_close)"
fc_typed "$FC_WD"; poke "$RFC" reply "$FC_WD"; FC_TR="$RC|$(fc_appr release | grep -c "|head=$FC_R|")"
poke "$RFC" current 8 --check
expect_eq "TASK-5 the person's typed reply approves the release at the head (exit 0), and current 8 --check is admitted" "0|1|0" "$FC_TR|$(ck_ans)"
expect_eq "TASK-6 …and the close reads every fact holding" "facts: every fact the run owes holds at $FC_R" "$(fc_close)"
# A FIX PAST THE APPROVAL whose adversarial review fails: the advance refuses on that review, the card's to waive, before
# the stale approval, and the card puts the release again all the same.
FC_TF="$(s57_commit "$RFC" lib/x.sh 'T5: a fix past the approval')"
printf 'question: adversarial\nresult: fail\nscope: whole\nreviewed: %s..%s\nfindings: 1\nfinding: 1 S2 on lib/x.sh:1 the value is lost\n\nwhat the reader found\n' \
  "${FC_B:0:10}" "${FC_TF:0:10}" > "$FC_REC/adversarial-fail.md"
fc_plan "run/v1|ev=approval|key=release|by=Dana Fixture|head=$FC_R|said=$FC_WD|at=2026-10-12T14:00:00Z
$(for q in evidence adversarial structure; do fc_line review "$FC_TF" 2026-10-12T15:00:00Z "record/wave-x/$q$([ "$q" != adversarial ] || echo -fail).md" "$q" w-read "$([ "$q" = adversarial ] && echo fail || echo pass)" whole; done)" "" fc_task
fc_page; FC_TK="$FC_RC|$(/usr/bin/grep -c '|key=approve:release|' "$FC_REC/release-approval-${FC_TF:0:8}.md" 2>/dev/null)"
poke "$RFC" current 8 --check
expect_eq "TASK-7 a fix past the approved head, its review failing: current 8 refuses on the review alone (exit 0: would refuse), and the card drawn there puts the release again (exit 0)" \
  "1|1|0|0|1" "$(ck_ans)|$(printf '%s\n' "$OUT" | /usr/bin/grep -c '^review	adversarial	.*failing')|$(printf '%s\n' "$OUT" | /usr/bin/grep -c 'approved for release')|$FC_TK"
expect_contains "TASK-8 …with no reply the close refuses, naming both heads" "the working head ${FC_TF:0:12} is not the head the user approved for release, ${FC_R:0:12}" "$(fc_close)"
fc_typed "$FC_WD"; poke "$RFC" reply "$FC_WD"; FC_TR="$RC|$(fc_appr release | grep -c "|head=$FC_TF|")"; poke "$RFC" current 8 --check
expect_eq "TASK-9 the typed reply renews the approval at the fix's head (exit 0); current 8 --check and the close pass" \
  "0|1|0|facts: every fact the run owes holds at $FC_TF" "$FC_TR|$(ck_ans)|$(fc_close)"
git -C "$RFC" reset -q --hard "$FC_R"
fc_typed "$FC_WD" "$FC_WR"; rm -f "$FC_REC"/release-approval-*.md "$FC_REC/adversarial-fail.md"

# ============================================================
section "§SENTENCE: a carry holds its sentence: stated before the card, drawn on it, carried by the reply's move, refused at the card when missing"
# ============================================================
# FIXTURE FIDELITY: two S3 findings the registration deferred (lib/proof.sh's deferral line) and one open S2, the
# person's to rule, its carry a decision; each sentence stated by the verb, the release entry rendered by its verb.
# fails-when: the card renders over a carry with no sentence, or puts its approval first; the reply carries a decision
# with no sentence or drops it from the move; or the Known limits refuse after the one reply, a move left to run by hand.
FC_SA=record/wave-x/structure.md#1; FC_SB=record/wave-x/structure-whole.md#1; FC_SC=record/wave-x/adversarial-whole.md#1
fc_record structure structure piece 'finding: 1 S3 on lib/x.sh:1 a name could be clearer'
fc_record structure-whole structure whole 'finding: 1 S3 on lib/x.sh:1 a word could be plainer'
fc_record adversarial-whole adversarial whole $'finding: 1 S2 on lib/x.sh:1 a path could break\nshown: 1 cat lib/x.sh'
fc_plan "$FC_GOOD
$(for f in "$FC_SA" "$FC_SB"; do printf 'run/v1|ev=finding|ref=%s|severity=S3|reach=on|to=deferred|title=t|at=2026-10-12T12:10:00Z\n' "$f"; done)"
fc_said() { poke "$RFC" finding-move "$1" stated "The sentence of ${1##*/}."; printf '%s' "$RC"; }
fc_snum() { fc_table | /usr/bin/grep -F "|key=finding:$FC_SC|" | sed -n 's/^release-approval\/v1|dec=\([0-9]*\)|.*/\1/p'; }
fc_page
expect_eq "SENT-1 a carry with no sentence: the card refuses (exit 1), naming the finding and the verb that states it" "1|yes|yes" \
  "$FC_RC|$(fc_has "$FC_ERR" "REFUSED — $FC_SA is carried with no Known-limits sentence")|$(fc_has "$FC_ERR" "run: bash $BIONIC_HOOKS_DIR/session-poker.sh finding-move $FC_SA stated")"
expect_eq "SENT-1b …before the approval: no page is recorded and the release approval is not opened" "|" "$(fc_pages)|$(fc_owed | /usr/bin/grep -x approve:release)"
FC_SN="$(fc_said "$FC_SA")$(fc_said "$FC_SB")"
fc_page; FC_SNN="$(fc_snum)"; FC_SNR="${FC_SNN:-0} carry, rest default"; fc_typed "$FC_SNR"
expect_eq "SENT-2 each deferral states its sentence (exit 0), standing deferred still; the card renders (exit 0), records its page and opens the approval" \
  "00|2|0|release-approval-$FC_H8.md|approve:release" "$FC_SN|$(bash "${BIONIC_SCRIPTS_DIR}/payload/scripts/reader.sh" "$PFC" findings | /usr/bin/grep -c 'to=deferred')|$FC_RC|$(fc_pages)|$(fc_owed | /usr/bin/grep -x approve:release)"
expect_eq "SENT-2b …drawing each carried finding's sentence under Findings" "yes|yes" \
  "$(fc_has "$(fc_under Findings | fc_flat)" "The sentence of structure.md#1")|$(fc_has "$(fc_under Findings | fc_flat)" "The sentence of structure-whole.md#1")"
poke "$RFC" reply "$FC_SNR"
expect_eq "SENT-3 the reply that carries the open S2, which states none, refuses (exit 1) naming it, and writes no approval" "1|yes|" \
  "$RC|$(fc_has "$OUT" "the reply carries $FC_SC (decision $FC_SNN), which states no Known-limits sentence")|$(fc_appr release)"
FC_SN="$(fc_said "$FC_SC")"; fc_page
expect_eq "SENT-4 stated, the decision draws the sentence its carry takes, and its replay line holds it" "0|yes|yes" \
  "$FC_SN|$(fc_has "$(fc_under Decisions | fc_flat)" "carried, it reads: The sentence of adversarial-whole.md#1.")|$(fc_has "$(fc_table)" "|key=finding:$FC_SC|default=finding-move $FC_SC fix|other=finding-move $FC_SC defer|pick=default|choices=fix/carry|why=the release approval card: fixed|stated=The sentence of adversarial-whole.md#1.")"
poke "$RFC" reply "$FC_SNR"
expect_eq "SENT-5 the one reply replays (exit 0): the approval written, the carry's move stating its sentence" "0|1|1" \
  "$RC|$(fc_appr release | grep -c .)|$(/usr/bin/grep -c "^run/v1|ev=finding|ref=$FC_SC|to=defer|.*|words=$FC_SNR|.*|stated=The sentence of adversarial-whole.md#1.|" "$FC_REC/run.log")"
s57_commit "$RFC" CHANGELOG.md '## 1.0.0 — the fixture release' >/dev/null
poke "$RFC" known-limits-part T3
expect_eq "SENT-6 with no move after the reply, the Known limits render (exit 0), the three sentences in the order deferred" "0|- The sentence of structure.md#1.|- The sentence of structure-whole.md#1.|- The sentence of adversarial-whole.md#1." \
  "$RC|$(git -C "$RFC" show HEAD:CHANGELOG.md | /usr/bin/grep '^- The sentence' | paste -sd'|' -)"
git -C "$RFC" reset -q --hard "$FC_R"
fc_record structure structure piece; fc_record structure-whole structure whole; fc_record adversarial-whole adversarial whole
fc_typed "$FC_WD" "$FC_WR"; rm -f "$FC_REC"/release-approval-*.md

finish
