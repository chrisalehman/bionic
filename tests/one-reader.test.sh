#!/bin/bash
# tests/one-reader.test.sh — payload/scripts/one-reader-check.sh, the count of what the one-reader rule
# names over a checkout: parsers of a plan or a log outside the reader, plan writers, event types with
# two writers, refusal words in hook files and pasted loader copies. It reports and exits 0.
#
#   §PARSERS      an awk over a plan planted under payload/scripts/lib/ is named and the count rises by one;
#                 the same awk inside the reader's own file is admitted.
#   §PLANWRITERS  a planted append to a plan is named and the count rises by one.
#   §WRITERS      two functions appending one event type are listed as a pair; so is `published` today. A
#                 launch's `dispatch` has one writer, the launch recorder's, and a row's `born` one, the units
#                 library's; each is paired with a planted second, the born one in the shape of a split; so is
#                 a planted second appender of a waiver, a finding or a proof beside the one writer of each.
#   §NAMES        the verbs the dispatch, born and tree events and the landing's event retired, the five that wrote
#                 a matrix cell and the commands with no job are named nowhere in hooks/ or payload/scripts/; nor those
#                 that wrote a step's line, its fields, the regression's setting, its runs' count, a row's
#                 confirmation and the cap, beside the step's and the approval's one writer in §WRITERS.
#   §REFUSALS     refusal words planted in a registered hook file are listed and counted, one site for each name the
#                 check counts; the dispatch wall lists none, and no fact the dispatch library says is in its file.
#   §FOLDS        a caller of the fold through a pipe or an unread $( ) is named, one that reads its exit is not;
#                 the tree holds none.
#   §LOADER       the loader block's mark is found in one file, lib/loader.sh, and the check reads no copy over the
#                 tree; a copy planted in a hook file is listed and counted.
#   §REPORT       the check exits 0 with findings and ends on the six count lines, in their order.
#   §READINGS     readings.sh prints the release's readings at a revision from git objects; reading 1 is the
#                 check's own count over that tree, reading 7 the born events the reader lists for the record.
#
# FIXTURE FIDELITY. Every run reads a scratch copy of this checkout's hooks/ and payload/scripts/;
# the plants are real files in that copy.

set -uo pipefail
. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
CHECK="${BIONIC_SCRIPTS_DIR}/payload/scripts/one-reader-check.sh"
S="$(mktemp -d)"; trap 'rm -rf "$S"' EXIT; mkdir -p "$S/payload"
cp -R "${BIONIC_SCRIPTS_DIR}/hooks" "$S/hooks"; cp -R "${BIONIC_SCRIPTS_DIR}/payload/scripts" "$S/payload/scripts"
run() { bash "$CHECK" "$S"; }
count() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }
BEFORE="$(run)"
L="$S/payload/scripts/lib"
cat > "$L/planted-parse.sh" <<'EOF'
planted_rows() { awk -F'|' '$2 ~ /^ T[0-9]+ $/ { print $2 }' "$plan"; }
EOF
cat > "$L/planted-write.sh" <<'EOF'
planted_line() { printf -- '- %s: landed\n' "$1" >> "$plan"; }
EOF
cat > "$L/planted-writers.sh" <<'EOF'
planted_born_a() { log_append born row=T1; }
planted_born_b() { RUN_LOG="$log" log_append born "row=$child" "reason=split from $parent"; }
planted_waiver() { log_append waiver question=evidence; }
planted_finding() { log_append finding ref=r.md#1; }
planted_proof() { log_append proof kind=walk; }
planted_dispatch() { log_append dispatch row=T1; }
planted_tree() { RUN_LOG="$log" log_append tree row=T1 path=.worktrees/t1; }
EOF
printf '%s\n' "planted_reader_rows() { awk -F'|' '\$2 ~ /T/' \"\$plan\"; }" >> "$L/reader.sh"
# One planted site for each name the check counts, on each wire, so the section's proof rests on no real hook.
printf '%s\n' 'refuse exit2 v "w" "x" ""' 'refuse deny v "w" "x" ""' 'refuse block v "w" "x" ""' 'refuse "$m" v "w" "x" ""' \
  'fold_block "w"' 'dp_finding "w" "x" ""' 'patrol_deny "w" "x" ""' 'dp_not_checked "w"' 'deny "w"' 'block "w"' >> "$S/hooks/engage.sh"
printf '%s\n' 'a() { _proof_ask "$p" reader_q_step "$p" | sed -n s/^n=//p; }' 'b() { f="$(_proof_facts "$p")"; }' 'c() { local f="$(reader_main "$p" step)" || return 2; }' \
  'd() { f="$(_proof_facts "$p")" || return 2; printf "%s" "$f" | awk 1; }' 'reader_facts() { printf "%s" "$f"; }' > "$L/planted-folds.sh"
printf '%s\n' '#!/bin/bash' '# --- bionic-loader/v2 BEGIN' > "$S/hooks/planted-loader.sh"
AFTER="$(run)"; RC=$?

section "PARSERS"
expect_contains "a real parser is named at this head" "$(printf 'parser\tpayload/scripts/card.sh\t')" "$BEFORE"
expect_absent "the goals library reads a criterion's state and a plan's scale through the reader alone" "$(printf 'parser\tpayload/scripts/lib/plan.sh\t')" "$BEFORE"
expect_absent "the fill library takes the run's step and approval from the reader alone" "$(printf 'parser\tpayload/scripts/lib/fill.sh\t')" "$BEFORE"
expect_eq "the parsers stand at or under twenty-one" 1 "$(( $(count "$BEFORE" parsers) <= 21 ))"
expect_contains "the planted awk over a plan is named" "$(printf 'parser\tpayload/scripts/lib/planted-parse.sh\t')" "$AFTER"
expect_eq "the parser count rises by one" "$(( $(count "$BEFORE" parsers) + 1 ))" "$(count "$AFTER" parsers)"
expect_absent "the reader's own file is admitted, its planted awk too" "lib/reader.sh" "$AFTER"

section "PLANWRITERS"
expect_contains "the planted plan write is named" "$(printf 'plan-writer\tpayload/scripts/lib/planted-write.sh\t')" "$AFTER"
expect_absent "a plan write is not a parse" "$(printf 'parser\tpayload/scripts/lib/planted-write.sh')" "$AFTER"
expect_absent "the units library writes no plan" "$(printf 'plan-writer\tpayload/scripts/lib/units.sh\t')" "$AFTER"
expect_eq "the plan-writer count rises by one" "$(( $(count "$BEFORE" plan_writers) + 1 ))" "$(count "$AFTER" plan_writers)"

section "WRITERS"
expect_contains "two functions appending one type are a pair" \
  "$(printf 'shared\tborn\tpayload/scripts/lib/planted-writers.sh:planted_born_a payload/scripts/lib/planted-writers.sh:planted_born_b')" "$AFTER"
PUB="$(printf '%s\n' "$BEFORE" | awk -F'\t' '$1 == "shared" && $2 == "published" { print $3 }')"
expect_contains "published: the queue landing's writer" "payload/scripts/lib/line.sh:line_publish" "$PUB"
expect_contains "published: a record row's landing, the tick's" "hooks/poker/line.sh:record_row_land" "$PUB"
expect_contains "published: close-out's landing of the rows its merge lands" "payload/scripts/close-out.sh:act_lands" "$PUB"
pair() { printf '%s\n' "$AFTER" | awk -F'\t' -v t="$1" '$1 == "shared" && $2 == t { print $3 }'; }
expect_contains "a planted second waiver appender is named beside the one waiver writer" \
  "payload/scripts/lib/planted-writers.sh:planted_waiver payload/scripts/lib/proof.sh:proof_waiver_event" "$(pair waiver)"
expect_contains "a planted second finding appender is named beside the one finding writer" \
  "payload/scripts/lib/planted-writers.sh:planted_finding payload/scripts/lib/proof.sh:proof_finding_event" "$(pair finding)"
expect_contains "a planted second proof appender is named beside the one proof writer" \
  "payload/scripts/lib/planted-writers.sh:planted_proof payload/scripts/lib/proof.sh:proof_event" "$(pair proof)"
DSP="$(printf '%s\n' "$AFTER" | awk -F'\t' '$1 == "shared" && $2 == "dispatch" { print $3 }')"
expect_contains "dispatch: the launch recorder's one writer" "hooks/execution-recorder.sh:dispatch_event" "$DSP"
expect_contains "dispatch: the planted second writer beside it" "payload/scripts/lib/planted-writers.sh:planted_dispatch" "$DSP"
BRN="$(printf '%s\n' "$AFTER" | awk -F'\t' '$1 == "shared" && $2 == "born" { print $3 }')"
expect_contains "born: the units library's one writer" "payload/scripts/lib/units.sh:units_born_event" "$BRN"
expect_contains "born: the planted split beside it" "payload/scripts/lib/planted-writers.sh:planted_born_b" "$BRN"
TRE="$(pair tree)"
expect_contains "tree: the tree verb's one writer" "payload/scripts/lib/worktree.sh:worktree_tree_event" "$TRE"
expect_contains "tree: the planted second writer beside it" "payload/scripts/lib/planted-writers.sh:planted_tree" "$TRE"
SH0="$(printf '%s\n' "$BEFORE" | awk -F'\t' '$1 == "shared" && ($2 == "born" || $2 == "dispatch" || $2 == "waiver" || $2 == "finding" || $2 == "proof" || $2 == "tree")' | grep -c .)"
expect_eq "the shared-type count rises by each of the six planted types not shared before" "$(( $(count "$BEFORE" shared_types) + 6 - SH0 ))" "$(count "$AFTER" shared_types)"
w1() { printf '%s\n' "$AFTER" | awk -F'\t' -v t="$1" '$1 == "writer" && $2 == t { split($3, w, " "); sub(/:[0-9]+$/, "", w[1]); print w[1], w[2] }'; }
for t in step approval; do expect_eq "$t: one writer, the facts library's, and no second" "payload/scripts/lib/proof.sh proof_${t}_event|" "$(w1 $t)|$(pair $t)"; done
expect_eq "decision and debt: one writer each, the facts library's, and no second" "payload/scripts/lib/proof.sh proof_decision_event|payload/scripts/lib/proof.sh proof_debt_event|" \
  "$(w1 decision)|$(w1 debt)|$(pair decision)$(pair debt)"
expect_eq "order, handoff and bind: one writer each, the facts library's, and no second" \
  "payload/scripts/lib/proof.sh proof_order_event|payload/scripts/lib/proof.sh proof_handoff_event|payload/scripts/lib/proof.sh proof_bind_event|" \
  "$(w1 order)|$(w1 handoff)|$(w1 bind)|$(pair order)$(pair handoff)$(pair bind)"
# The two setters of matrix cells go with the matrix; every other hand event is written by the one writer.
expect_eq "hand: one writer, the line library's, beside the matrix setters" "payload/scripts/lib/line.sh line_hand_event" \
  "$(printf '%s\n' "$BEFORE" | awk -F'\t' '$1 == "writer" && $2 == "hand" { split($3, w, " "); sub(/:[0-9]+$/, "", w[1]); print w[1], w[2] }' \
    | /usr/bin/grep -v ' poker_verb_matrix_' | sort -u)"

section "NAMES"
names() { /usr/bin/grep -rnE 'launch-sync|ledger-add|ledger-set|task-set|task-split|tasks-prose|row-landed|row_landed|session-poker\.sh"? deliver|`deliver`|deliver <(row|id)>|^ *deliver\)' "$1/hooks" "$1/payload/scripts"; }
printf '%s\n' '# launch-sync' '# tasks-prose' '# row-landed' '# session-poker.sh deliver T1' > "$L/planted-name.sh"
expect_contains "the extractor reads a planted name" "planted-name.sh" "$(names "$S")"
expect_eq "the retired verbs are named nowhere else" "" "$(names "$S" | grep -v planted-name.sh)"
cells() { /usr/bin/grep -rnE 'matrix-(set|retier|render)|waive-row|poker_verb_discharge|discharge\)|(session-poker\.sh|plan_verb_open|plan_verb_swap|pv_next) discharge' "$1/hooks" "$1/payload/scripts" \
  | grep -v -e '/payload/scripts/lib/translate\.sh:' -e 'w == "'; }   # an older run's hand acts are read by their names
printf '%s\n' '# matrix-retier' '# session-poker.sh discharge AC-1' > "$L/planted-cell.sh"
expect_eq "the extractor reads both planted names of the verbs that wrote a matrix cell" "2" "$(cells "$S" | grep -c planted-cell.sh)"
expect_eq "the five verbs that wrote a matrix cell are named nowhere else" "" "$(cells "$S" | grep -v planted-cell.sh)"
# The commands with no job are read by the shape of a use, never the bare word, for several are English: the poker run
# with one as its verb, a function named for one, and a case arm of the poker's own.
GONE_V='anchors|patrol|wait|cover|epic-row|continuation-fill|interval-default|window|fill-report|disposition'
gone() {
  { /usr/bin/grep -rnE "(session-poker\.sh|\\\$\{?[A-Za-z_]*(poker|POKER)[A-Za-z_]*\}?)[\"']? ($GONE_V)([^a-z_-]|\$)|poker_verb_(${GONE_V//-/_})([^a-z_]|\$)" "$1/hooks" "$1/payload/scripts"
    /usr/bin/grep -rnE --include='*poker*.sh' "^ *([a-z-]+\|)*($GONE_V)(\|[a-z-]+)*\)" "$1/hooks" "$1/payload/scripts"; }
}
printf '%s\n' '# bash "$POKER" wait r1' '  poker_verb_patrol() {' > "$L/planted-gone.sh"
printf '%s\n' '  tick|anchors)' > "$L/planted-poker-arm.sh"
expect_eq "the extractor reads the planted call, function and case arm" "3" "$(gone "$S" | grep -c '/planted-')"
expect_eq "the commands with no job are named nowhere else" "" "$(gone "$S" | grep -v '/planted-')"

# A version-15 header still refuses the runs count's old key.
steps() { /usr/bin/grep -rnE 'step-line|step-field|regression-runs|regression_runs_count|units_set_current|units_step_line|units_step_fields|poker_verb_regression\b|\|budget\||\|regression\|share\||confirm-row|confirm_row|matrix_block_key|poker_verb_budget|budget-override|session-poker\.sh"? budget|^  budget\)$' "$1/hooks" "$1/payload/scripts" \
  | grep -v -e 'PLAN_READ_GONE_KEYS='; }
printf '%s\n' '# step-field 5 walk-artifact=x' '# regression-runs --write' '# confirm-row AC-1' '# session-poker.sh budget writers=2' > "$L/planted-step.sh"
expect_eq "the extractor reads the four planted names of the step's, the confirmation's and the cap's writers" "4" "$(steps "$S" | grep -c planted-step.sh)"
expect_eq "the verbs that wrote a step's line, its fields, the regression's setting, its runs' count, a row's confirmation and the cap are named nowhere else" "" "$(steps "$S" | grep -v planted-step.sh)"
# A design ledger heading and a debt ledger row are read by the translation alone; no verb writes either file.
ledgers() { /usr/bin/grep -rnE '## Δ|/ \\[|] /|" [|] raised-by ' "$1/hooks" "$1/payload/scripts" | grep -v -e '/payload/scripts/lib/translate\.sh:' -e ':[0-9]*: *#'; }
printf '%s\n' '# ## Δ0 in a comment' "led_n() { sed -n 's/^## Δ\\([0-9]*\\).*/\\1/p' \"\$1\"; }" > "$L/planted-ledger.sh"
expect_eq "the extractor reads the planted ledger parser and not the comment" "1" "$(ledgers "$S" | grep -c planted-ledger.sh)"
expect_eq "neither ledger file is written or parsed outside the translation" "" "$(ledgers "$S" | grep -v planted-ledger.sh)"

section "REFUSALS"
own() { printf '%s\n' "${2:-$BEFORE}" | awk -F'\t' -v f="hooks/$1.sh:" 'index($2, f) == 1 { n = $2; sub(/.*:/, "", n); print n, $3 }'; }
expect_eq "every planted site is listed, one for each name the check counts" \
  "refuse refuse refuse refuse fold_block dp_finding patrol_deny dp_not_checked deny block" "$(own engage "$AFTER" | awk '{ print $2 }' | tr '\n' ' ' | sed 's/ $//')"
expect_regex "the extractor reads the planted file's sites by line" "^[0-9]+ refuse$" "$(own engage "$AFTER" | head -1)"
expect_eq "the refusal count rises by ten" "$(( $(count "$BEFORE" hook_refusals) + 10 ))" "$(count "$AFTER" hook_refusals)"
expect_eq "the write hook's file and the permission hook's list no refusal" "0 0" "$(own canonical-sdlc-governing-skill | grep -c .) $(own permission-answer | grep -c .)"
expect_eq "the dispatch wall's file lists no refusal" "0" "$(own dispatch-preflight | grep -c .)"
expect_eq "the Bash wall lists only the two functions the next row deletes: three sites, none outside" "3 0" \
  "$(own bash-walls | grep -c .) $(own bash-walls | awk '{ print $1 }' | grep -vxFf <(awk '/^wall_ruling_(unread|ack)\(\)/ { on = 1 } on { print NR } /^}/ { on = 0 }' "$S/hooks/bash-walls.sh") | grep -c .)"
# Each fact the dispatch library says, its facts given as @, cut at them into pieces of ten columns or more: a
# piece found in the wall's code is a refusal's words left in the hook, whatever function holds them.
DPIECES="$(bash -c '. "$1/refuse.sh" && . "$1/dispatch.sh" || exit 1
  for k in $(dispatch_keys); do dispatch_say "$k" @ @ @ @ @ @ @ @ @ @ && printf "%s\n" "$DISPATCH_FACT"; done' _ "$L" | tr '@' '\n' | awk 'length($0) >= 10')"
pieces_in() { awk '!/^[ \t]*#/' "$1" > "$S/.code"; printf '%s\n' "$DPIECES" | while IFS= read -r p; do /usr/bin/grep -qF -- "$p" "$S/.code" && printf '%s\n' "$p"; done; }
DKEYS="$(bash -c '. "$1/refuse.sh" && . "$1/dispatch.sh" && for k in $(dispatch_keys); do dispatch_say "$k" @ && [ -n "$DISPATCH_FACT" ] && echo "$k"; done' _ "$L" | grep -c .)"
expect_eq "the dispatch library says a fact under a key for each of the wall's 43 refusals" 43 "$DKEYS"
expect_eq "every piece of those facts is found in the library's own text" "$(printf '%s\n' "$DPIECES" | grep -c .)" "$(pieces_in "$L/dispatch.sh" | grep -c .)"
expect_eq "no fact of the dispatch library is found in the wall's file" "" "$(pieces_in "$S/hooks/dispatch-preflight.sh")"
expect_eq "the stop guard's file lists no refusal" "0" "$(own stop-guard | grep -c .)"
# The stop guard's words are its facts and its details, each line cut at its facts and trimmed.
DPIECES="$(bash -c '. "$1/refuse.sh" && . "$1/stop.sh" || exit 1
  for k in $(stop_guard_keys); do stop_guard_say "$k" @ @ @ @ @ @ && printf "%s\n%s\n" "$SG_FACT" "$SG_DETAIL"; done' _ "$L" \
  | tr '@' '\n' | awk '{ gsub(/^[ \t]+|[ \t]+$/, "") } length($0) >= 10' | sort -u)"
expect_eq "the stop library says a fact under a key for each of the guard's nine refusals, its frame the detail of six" 9 \
  "$(bash -c '. "$1/refuse.sh" && . "$1/stop.sh" && for k in $(stop_guard_keys); do stop_guard_say "$k" @ && [ -n "$SG_FACT" ] && echo "$k"; done' _ "$L" | grep -c .)"
expect_regex "the guard's words cut into pieces" "^[1-9][0-9]*$" "$(printf '%s\n' "$DPIECES" | grep -c .)"
expect_eq "every piece of the guard's words is found in the stop library's own text" "$(printf '%s\n' "$DPIECES" | grep -c .)" "$(pieces_in "$L/stop.sh" | grep -c .)"
expect_eq "no piece of the guard's words is found in the guard's file" "" "$(pieces_in "$S/hooks/stop-guard.sh")"

section "FOLDS"
expect_eq "a fold through a pipe, an unread \$( ) and a local's \$( ) are named; one whose exit is read and a stand-in are not" "1 2 3" \
  "$(printf '%s\n' "$AFTER" | sed -n 's|^unheard	payload/scripts/lib/planted-folds\.sh:||p' | tr '\n' ' ' | sed 's/ $//')"
expect_eq "the unheard count rises by three over the tree, which holds none" "0 3" "$(count "$BEFORE" unheard_folds) $(count "$AFTER" unheard_folds)"

section "LOADER"
expect_eq "the loader block's mark is found in one file, the loader's own" "payload/scripts/lib/loader.sh" \
  "$(cd "$BIONIC_SCRIPTS_DIR" && /usr/bin/grep -rl '^# --- bionic-loader/v2 BEGIN' hooks payload/scripts | sort | tr '\n' ' ' | sed 's/ $//')"
expect_eq "the check reads no pasted copy over the tree" 0 "$(count "$BEFORE" loader_copies)"
expect_contains "a copy planted in a hook file is listed" "$(printf 'loader\thooks/planted-loader.sh\t:2')" "$AFTER"
expect_absent "the loader's own file is not a copy" "$(printf 'loader\tpayload/scripts/lib/loader.sh')" "$AFTER"
expect_eq "the planted copy raises the count by one" "$(( $(count "$BEFORE" loader_copies) + 1 ))" "$(count "$AFTER" loader_copies)"

section "REPORT"
expect_status "the check exits 0 with findings" 0 "$RC"
expect_eq "it ends on the six count lines, in order" "parsers plan_writers shared_types hook_refusals loader_copies unheard_folds" \
  "$(printf '%s\n' "$AFTER" | tail -6 | sed -n 's/^\([a-z_]*\)=[0-9][0-9]*$/\1/p' | tr '\n' ' ' | sed 's/ $//')"
bash "$CHECK" "$S/no-such" >/dev/null 2>&1; expect_status "a root that is not a checkout exits 2" 2 "$?"

# §READINGS runs from the checkout; a scratch commit on a shared clone moves a count without touching it.
READ="${BIONIC_SCRIPTS_DIR}/payload/scripts/readings.sh"; F="${BIONIC_SCRIPTS_DIR}/tests/fixtures/replay"
at() { ( cd "$1" && shift && bash "$READ" "$@" 2>&1 ); }
born() { ( . "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/reader.sh"; reader_facts "$1" ) | grep -c '^run/v1|ev=born|'; }
OLD=7a9633486; R30="$(at "$BIONIC_SCRIPTS_DIR" $OLD)"
mkdir "$S/old"; git -C "$BIONIC_SCRIPTS_DIR" archive $OLD hooks payload/scripts | tar -x -C "$S/old"
git clone -q --shared --no-checkout "$BIONIC_SCRIPTS_DIR" "$S/repo"; G="git -C $S/repo"; $G read-tree $OLD
BLOB="$($G show $OLD:hooks/session-poker.sh | awk '{print} /^case "\$VERB" in/ {print "  zzscratch) ;;"}' | $G hash-object -w --stdin)"
$G update-index --cacheinfo "100755,$BLOB,hooks/session-poker.sh"
SCR="$($G -c user.name=t -c user.email=t@t commit-tree "$($G write-tree)" -p $OLD -m scratch)"
RW="$F/wave-46-asks-nothing"; R46="$(at "$BIONIC_SCRIPTS_DIR" $OLD "$RW/record/wave-46-asks-nothing")"
R49="$(at "$BIONIC_SCRIPTS_DIR" $OLD "$F/wave-49-what-a-run-costs/record/wave-49-what-a-run-costs")"
BORN="$(born "$RW/plans/epic-23-bionic-tech-debt/wave-46-asks-nothing.plan.md")"

section "READINGS"
expect_contains "the verbs are 68" "r2_session_poker_verbs=68" "$R30"
expect_contains "11 hook scripts are registered, 9 over 30 percent in-file" "r3_registered_hook_scripts=11 r3_over_30pct_in_file=9" "$R30"
expect_contains "15 loader copies" "r3_loader_copies=15" "$R30"
expect_contains "101513 shell lines outside tests" "r4_shell_outside_tests_lines=101513" "$R30"
expect_contains "102161 test lines" "r5_tests_lines=102161" "$R30"
expect_regex "reading 1 is a count" "^r1_parsers=[1-9][0-9]*$" "$R30"
expect_eq "reading 1 is the check's own count over the same tree" "$(count "$(bash "$CHECK" "$S/old")" parsers)" "$(count "$R30" r1_parsers)"
expect_contains "a scratch commit adding one verb arm moves the verbs to 69" "r2_session_poker_verbs=69" "$(at "$S/repo" "$SCR")"
expect_contains "no record, none read: the output says so" "record=none" "$R30"
expect_absent "no record, no reading 7" "r7_" "$R30"
expect_contains "the output names the record it read" "record=$RW/record/wave-46-asks-nothing" "$R46"
expect_regex "a record's born events are not zero" "^[1-9][0-9]*$" "$BORN"
expect_eq "reading 7 is the born events the reader lists for the run" "$BORN" "$(count "$R46" r7_born_events)"
expect_ne "reading 7 moves with the record passed" "$(count "$R46" r7_born_events)" "$(count "$R49" r7_born_events)"
expect_status "a record that is not a directory exits 2" 2 "$(at "$BIONIC_SCRIPTS_DIR" $OLD "$S/none" >/dev/null; echo $?)"

finish
