#!/bin/bash
# tests/one-reader.test.sh — payload/scripts/one-reader-check.sh, the count of what the one-reader rule
# names over a checkout: parsers of a plan or a log outside the reader, plan writers, event types with
# two writers, refusal words in hook files, pasted loader copies and retired verbs. It refuses a parser, a plan
# writer, a shared type and a name, each planted alone in a root of its own, by file and line; the tree it passes.
#
#   §PARSERS      an awk over a plan planted under payload/scripts/lib/ is named and counted; the same awk inside
#                 the reader's own file or its field reader's is admitted, and the landing library parses none. For each kind of line that reads
#                 nothing (a heading's or a shape's words, an operand of another command) a planted file holds
#                 lines of it and, last, the real reading of that kind: only the last is counted.
#   §PLANWRITERS  a planted append to a plan is named and counted; a log's, words' or copy
#                 source's line is no write beside a planted copy onto a plan. No function's write is admitted.
#   §WRITERS      two functions appending one event type are listed as a pair; the six a landing writes have one
#                 writer each, the landing library's, and every place that lands a row or a part calls it. A
#                 launch's `dispatch` has one writer, the launch recorder's, and a row's `born` one, the units
#                 library's; each is paired with a planted second, the born one in the shape of a split; so is
#                 a planted second appender of a waiver, a finding or a proof beside the one writer of each, and one
#                 through a pass-through whose call names the type. A printed search pattern is no writer, nor is the
#                 loader's call that names the appender as its marker.
#   §NAMES        the check names a planted retired verb by its line in each shape it reads (the verbs the events
#                 retired, the five that wrote a matrix cell, the commands with no job, the writers of a step's line,
#                 its fields, the regression's setting, its runs' count, a row's confirmation and the cap) and the old
#                 records' and the deleted hooks' file names; the tree names none, an older run's names in the reader's
#                 lists and files admitted. A suite's line is refused whatever entry is written beside it, and the
#                 loaded set names no deleted plan section; the checkout's suites and loaded set name none. No
#                 verb writes a ledger file.
#   §REFUSALS     refusal words planted in a registered hook file are listed and counted, one site for each name the
#                 check counts; the dispatch wall lists none, and no fact the dispatch library says is in its file.
#                 tests/lib/lint.sh, told the planted hook changed, names the same sites by line.
#   §FOLDS        a caller of the fold through a pipe or an unread $( ) is named, one that reads its exit is not;
#                 the tree holds none. The tree event is folded in the reader alone: a second fold planted in a
#                 script is found beside it, and the checkout holds the reader's one.
#   §DEAD         a planted name of a removed landing function is found by its line; the checkout names neither.
#   §LOGPATH      the run log's path is joined in the reader alone: a planted second join is found by its line.
#   §GITHOME      a second resolution of the common git directory planted in a hook is found by its file; the checkout holds
#                 none beside the root library's `git_common_dir`.
#   §DOCSPATH     adopt and the review proof read a record spelled from the project root or the docs root through lib/root.sh
#                 `docs_path`; a join of the docs root to an operand planted in a script is found by its file.
#   §LOADER      the loader block's mark is found in one file, lib/loader.sh, and the check reads no copy over the
#                 tree; a copy planted in a hook file is listed and counted.
#   §COPIES       a load-once guard, a self-dir, a common-directory lookup and a field-by-key reader, of a handed key
#                 or of a literal one at a walked field, planted under payload/scripts/ are each listed by line with its
#                 home and counted, and refused by none; the one bootstrap line, each idiom in its home's own file, a key
#                 at a fixed place, a key that only filters and a suite's line are not counted. The tree's lookups are
#                 the carried list's. tests/lib/lint.sh over a changed file names a copy and its home only once the
#                 check's list of refusing counts holds that idiom's count.
#   §KEPT         each copy kept by name admits its line in the tree; an entry whose copy is gone is a finding and a
#                 refusal, while a root that holds no file of an entry does not judge it.
#   §REPORT       with the plants the check exits 1, refusing each finding of the five refusing kinds once; a loader
#                 copy alone is refused by its file and line; it ends on the ten count lines, in their order.
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
run() { bash "$CHECK" "$S" 2>"$S/.err"; }
count() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }
# One plant in a root that holds nothing else: the check's refusal lines, then its exit.
lone() { local r="$S/lone-$1"; mkdir -p "$r/hooks" "$r/payload/scripts/lib" "$(dirname "$r/$2")"; cat > "$r/$2"; bash "$CHECK" "$r" 2>&1 >/dev/null; echo "rc=$?"; }
BEFORE="$(run)"; BRC=$?
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
printf '%s\n' "planted_reader_rows() { awk -F'|' '\$2 ~ /T/' \"\$plan\"; }" | tee -a "$L/fields.sh" >> "$L/reader.sh"
# In the reader's file a call of the appender and a printed line appended with >> write an event; a printed line alone is its answer.
printf '%s\n' 'planted_ask_call() { log_append ask key=k; }' 'planted_ask_put() { printf "run/v1|ev=ask|key=k|at=now\n" >> "$RUN_LOG"; }' \
  'planted_ask_say() { printf "run/v1|ev=ask|key=k|at=now\n"; }' >> "$L/reader.sh"
# One planted site for each name the check counts, on each wire, so the section's proof rests on no real hook.
printf '%s\n' 'refuse exit2 v "w" "x" ""' 'refuse deny v "w" "x" ""' 'refuse block v "w" "x" ""' 'refuse "$m" v "w" "x" ""' \
  'fold_block "w"' 'dp_finding "w" "x" ""' 'patrol_deny "w" "x" ""' 'dp_not_checked "w"' 'deny "w"' 'block "w"' >> "$S/hooks/engage.sh"
printf '%s\n' 'a() { _proof_ask "$p" reader_q_step "$p" | sed -n s/^n=//p; }' 'b() { f="$(_proof_facts "$p")"; }' 'c() { local f="$(reader_main "$p" step)" || return 2; }' \
  'd() { f="$(_proof_facts "$p")" || return 2; printf "%s" "$f" | awk 1; }' 'reader_facts() { printf "%s" "$f"; }' > "$L/planted-folds.sh"
printf '%s\n' '#!/bin/bash' '# --- bionic-loader/v2 BEGIN' > "$S/hooks/planted-loader.sh"
# One file for each kind of line that reads nothing, its last line the real reading or write of that kind.
awk -v d="$L" '/^@/ { f = d "/planted-k" substr($0, 2) ".sh"; next } { print > f }' <<'EOF'
@1
  die "REFUSED — the ## Tasks table of $p carries no row $id; the plan is unchanged."
  subject="1 active '## Tasks' row has"
  print "## SDLC State"
  /## SDLC State/ { s = 1 }
@2
  printf 'landings: unmeasured — the landing record holds no line/v1 events\n'
planted_facts() {  # <plan> -> the reader's facts, one run/v1 line each
  index($0, "owed/v1|") == 1 { n++ }
@3
  out="$(printf '%s\n' "$x" | awk -v n="$(count_rows "$plan")" '{ print }')"
  r="$(owed_rounds 'a|b' "$plan" | awk '{ print }')"
  { cat "$w/plan" > "$t"; } || fail "the plan $plan could not be written"
  n="$(cut -d'|' -f2 "$plan")"
@3b
    { c = $2; if (c == id) { print v; exit } }' "$plan" 2>/dev/null)"
@4
  printf 'rc=137\n' >> "$RUN_LOG"
  mv $(refuse_shell_word "$PLAN") $(refuse_shell_word "$to")
  cp -p "$plan" "$st/$wave"
  cp -p "$tmp" "$plan"
@5
planted_k5_count() { echo "n=$(/usr/bin/grep -c '^run/v1|ev=zzplant|' "$f")"; }
planted_k5_put() { echo "run/v1|ev=zzplant|at=now" >> "$f"; }
EOF
# A retired verb in each shape the check reads: by its own word, the poker run with it, a function and a case arm. Each
# name is read from the deletion list by a pattern no search of the check matches, so no line of this suite spells one.
LN="$(/usr/bin/grep -o '`[a-z_.-]*`' "${BIONIC_SCRIPTS_DIR}/tests/fixtures/deletion-list.txt" | tr -d '`')"
dl() { printf '%s\n' "$LN" | /usr/bin/grep -x -m1 -e "$1"; }   # <pattern> -> the one name of the list it matches whole
printf '%s\n' "# $(dl 'launch.sync')" "# $(dl 'tasks.prose')" "# $(dl 'row.landed')" "# session-poker.sh $(dl 'deli.er') T1" > "$L/planted-name.sh"
printf '%s\n' "# $(dl 'matrix.retier')" "# session-poker.sh $(dl 'discharg.') AC-1" > "$L/planted-cell.sh"
printf '%s\n' "# bash \"\$POKER\" $(dl 'wai.') r1" "  poker_verb_$(dl 'patro.')() {" > "$L/planted-gone.sh"; printf '%s\n' "  tick|$(dl 'anchor.'))" > "$L/planted-poker-arm.sh"
printf '%s\n' "# $(dl 'step.field') 5 walk-artifact=x" "# $(dl 'regression.runs') --write" "# $(dl 'confirm.row') AC-1" "# session-poker.sh $(dl 'budge.') writers=2" > "$L/planted-step.sh"
AFTER="$(run)"; RC=$?
site() { printf '%s\n' "$AFTER" | awk -F'\t' -v f="payload/scripts/lib/planted-k$1.sh" '$2 == f { print $1, $3 }'; }

section "PARSERS"
expect_absent "the goals library reads a criterion's state and a plan's scale through the reader alone" "$(printf 'parser\tpayload/scripts/lib/plan.sh\t')" "$BEFORE"
expect_absent "the fill library takes the run's step and approval from the reader alone" "$(printf 'parser\tpayload/scripts/lib/fill.sh\t')" "$BEFORE"
expect_eq "parsers, plan writers and shared types stand at 0 on the tree, and the check exits 0 there" "0 0 0 rc=0" \
  "$(count "$BEFORE" parsers) $(count "$BEFORE" plan_writers) $(count "$BEFORE" shared_types) rc=$BRC"
expect_eq "an awk over a plan, planted alone, is refused by its file and line" "one-reader-check: refused — parser payload/scripts/lib/p.sh:1 rc=1" \
  "$(lone parse payload/scripts/lib/p.sh < "$L/planted-parse.sh" | tr '\n' ' ' | sed 's/ $//')"
expect_eq "headings: a message's, a constant's and a print's words are no parse; an unanchored match is" "parser sites=1 first=4" "$(site 1)"
expect_eq "shapes: a printed one and a function line's comment are no parse; a log line's test is" "parser sites=1 first=3" "$(site 2)"
expect_eq "operands: a function's argument, in a \$( ) or in words, is no read; a reader's own is, and a program's end" \
  "parser sites=1 first=4 parser sites=1 first=1" "$(site 3) $(site 3b)"
expect_contains "the planted awk over a plan is named" "$(printf 'parser\tpayload/scripts/lib/planted-parse.sh\t')" "$AFTER"
expect_eq "the parser count rises by the five planted parsers" "$(( $(count "$BEFORE" parsers) + 5 ))" "$(count "$AFTER" parsers)"
expect_absent "the reader's own file is admitted, its planted awk too" "$(printf 'parser\tpayload/scripts/lib/reader.sh')" "$AFTER"
expect_absent "the field reader's file is the reader's, its planted awk too" "$(printf 'parser\tpayload/scripts/lib/fields.sh')" "$AFTER"
expect_absent "the landing library parses no record shape: its field reader is the reader's" "$(printf 'parser\tpayload/scripts/lib/line.sh\t')" "$AFTER"

section "PLANWRITERS"
expect_contains "the planted plan write is named" "$(printf 'plan-writer\tpayload/scripts/lib/planted-write.sh\t')" "$AFTER"
expect_eq "a plan write planted alone is refused by its file and line" "one-reader-check: refused — plan-writer payload/scripts/lib/p.sh:1 rc=1" \
  "$(lone write payload/scripts/lib/p.sh < "$L/planted-write.sh" | tr '\n' ' ' | sed 's/ $//')"
expect_absent "a plan write is not a parse" "$(printf 'parser\tpayload/scripts/lib/planted-write.sh')" "$AFTER"
expect_absent "the units library writes no plan" "$(printf 'plan-writer\tpayload/scripts/lib/units.sh\t')" "$AFTER"
expect_eq "the plan-writer count rises by the two planted writers" "$(( $(count "$BEFORE" plan_writers) + 2 ))" "$(count "$AFTER" plan_writers)"
expect_eq "writes: a log, a plan in refusal words and a copy's source are no plan write; a copy onto a plan is" "plan-writer sites=1 first=4" "$(site 4)"

section "WRITERS"
expect_contains "two functions appending one type are a pair" \
  "$(printf 'shared\tborn\tpayload/scripts/lib/planted-writers.sh:planted_born_a payload/scripts/lib/planted-writers.sh:planted_born_b')" "$AFTER"
expect_eq "a second appender planted alone is refused, each writer by its file, line and function" \
  "one-reader-check: refused — shared born payload/scripts/lib/p.sh:1 planted_born_a, payload/scripts/lib/p.sh:2 planted_born_b rc=1" \
  "$(head -2 "$L/planted-writers.sh" | lone writers payload/scripts/lib/p.sh | tr '\n' ' ' | sed 's/ $//')"
expect_eq "a second writer through a pass-through, defined after its call, is refused by the type its call names" \
  "one-reader-check: refused — shared waiver payload/scripts/lib/p.sh:1 planted_waiver, payload/scripts/lib/p.sh:2 planted_waiver_put rc=1" \
  "$(printf '%s\n' 'planted_waiver() { log_append waiver question=evidence; }' 'planted_waiver_put() { planted_pass "$log" waiver question=evidence; }' \
    'planted_pass() { local log="$1"; shift; RUN_LOG="$log" log_append "$@"; }' | lone pass payload/scripts/lib/p.sh | tr '\n' ' ' | sed 's/ $//')"
# The loader's call names the appender as the marker it waits for: no event is written there, and one written after it
# on the same line still is.
NEED="$(printf '%s\n' 'planted_need_a() { bionic_need line.sh line_event || return 0; }' 'planted_need_b() { bionic_need line.sh line_event || return 0; }' \
  'planted_need_c() { bionic_need log.sh log_append && log_append born row=T1; }' | lone need payload/scripts/lib/p.sh | tr '\n' ' ' | sed 's/ $//')"
expect_eq "two functions loading the appender by its marker are no pair of writers" "rc=0" "$NEED"
expect_eq "…and a writer after the loader's call on its line is still read, the call itself none" "born payload/scripts/lib/p.sh:3 planted_need_c" \
  "$(bash "$CHECK" "$S/lone-need" 2>/dev/null | awk -F'\t' '$1 == "writer" { print $2, $3 }')"
pair() { printf '%s\n' "$AFTER" | awk -F'\t' -v t="$1" '$1 == "shared" && $2 == t { print $3 }'; }
expect_eq "events: a printed search pattern writes none; a printed line does" "payload/scripts/lib/planted-k5.sh:2 planted_k5_put" \
  "$(printf '%s\n' "$AFTER" | awk -F'\t' '$1 == "writer" && $2 == "zzplant" { print $3 }')"
ASK="$(printf '%s\n' "$AFTER" | awk -F'\t' '$1 == "writer" && $2 == "ask" { print $3 }')"
expect_eq "ask: in the reader's file a log_append call and a printed line appended with >> are writers, a printed line alone is none" "1/1/0" \
  "$(printf '%s\n' "$ASK" | /usr/bin/grep -c ' planted_ask_call$')/$(printf '%s\n' "$ASK" | /usr/bin/grep -c ' planted_ask_put$')/$(printf '%s\n' "$ASK" | /usr/bin/grep -c ' planted_ask_say$')"
expect_absent "ask is shared at this head by no pair, the reader's printed answer being no writer" "$(printf 'shared\task\t')" "$BEFORE"
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
SH0="$(printf '%s\n' "$BEFORE" | awk -F'\t' '$1 == "shared" && ($2 == "born" || $2 == "dispatch" || $2 == "waiver" || $2 == "finding" || $2 == "proof" || $2 == "tree" || $2 == "ask")' | grep -c .)"
expect_eq "the shared-type count rises by each of the seven planted types not shared before" "$(( $(count "$BEFORE" shared_types) + 7 - SH0 ))" "$(count "$AFTER" shared_types)"
w1() { printf '%s\n' "$AFTER" | awk -F'\t' -v t="$1" '$1 == "writer" && $2 == t { split($3, w, " "); sub(/:[0-9]+$/, "", w[1]); print w[1], w[2] }'; }
for t in step approval; do expect_eq "$t: one writer, the facts library's, and no second" "payload/scripts/lib/proof.sh proof_${t}_event|" "$(w1 $t)|$(pair $t)"; done
for t in published run returned ready candidate verdict; do expect_eq "$t: one writer, the landing library's, and no second" "payload/scripts/lib/line.sh line_${t}_event|" "$(w1 $t)|$(pair $t)"; done
# The functions that call a type's one writer, each `<file>:<function>`, read over the scratch copy.
calls() { awk -v t="line_$1_event" -v s="$S/" 'FNR == 1 { f = "-" } match($0, /^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)/) { f = substr($0, RSTART, RLENGTH); gsub(/[ \t()]/, "", f) }
  f != t && $0 !~ /^[ \t]*#/ && index($0, t " ") { p = FILENAME; sub(s, "", p); print p ":" f }' $(find "$S/hooks" "$S/payload/scripts" -name '*.sh') | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//'; }
expect_eq "published: the queue's landing, a counted merge, a record row's, a part's, the tick's landing of a point, the publish verb's, the close's two and the card's projection each call the one writer" \
  "hooks/poker/line.sh:part_land hooks/poker/line.sh:poker_verb_publish hooks/poker/line.sh:record_row_land hooks/poker/tick.sh:tick_point_land payload/scripts/card.sh:_card_project payload/scripts/close-out.sh:act_lands payload/scripts/close-out.sh:co_reviews_publish payload/scripts/lib/line.sh:_line_count_git payload/scripts/lib/line.sh:line_publish" "$(calls published)"
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
nm() { printf '%s\n' "$AFTER" | awk -F'\t' -v f="payload/scripts/lib/planted-$1.sh:" '$1 == "name" && index($2, f) == 1 { sub(/.*:/, "", $2); print $2 }' | tr '\n' ' ' | sed 's/ $//'; }
expect_eq "each planted line is named by its line: the verbs, the matrix cells', the commands with no job (a call, a function, a case arm), the step's and the cap's" \
  "1 2 3 4|1 2|1 2|1|1 2 3 4" "$(nm name)|$(nm cell)|$(nm gone)|$(nm poker-arm)|$(nm step)"
expect_eq "the tree names none, the plants thirteen" "0 13" "$(count "$BEFORE" names) $(count "$AFTER" names)"
PV="bash \"\$POKER\" $(dl 'launch.sync')"; nl1() { tr '\n' ' ' | sed 's/ $//'; }
expect_eq "a retired verb planted alone in a hook is refused by its file and line" "one-reader-check: refused — name hooks/p.sh:1 rc=1" \
  "$(echo "$PV T1" | lone name hooks/p.sh | nl1)"
# Under tests/ a line stands by nothing: no list admits it, so an entry written for it changes nothing.
mkdir -p "$S/lone-suite/tests/fixtures" "$S/lone-listed/tests/fixtures"; echo "$PV T1" > "$S/lone-suite/tests/fixtures/f.sh"
expect_eq "a suite line calling a retired verb or naming a removed function is refused by its file and line; a fixture's is not read" \
  "one-reader-check: refused — name tests/p.test.sh:1 one-reader-check: refused — name tests/p.test.sh:2 rc=1" \
  "$(printf '%s\n' "$PV T1" "$(dl 'units.step.field') \"\$p\" 5" | lone suite tests/p.test.sh | nl1)"
printf 'plant\ttests/p.test.sh\t%s\n' "$PV T1" > "$S/lone-listed/tests/fixtures/admitted-lines.txt"
expect_eq "a suite line stands by no entry written for it: both lines are refused, the first with its entry beside it" \
  "one-reader-check: refused — name tests/p.test.sh:1 one-reader-check: refused — name tests/p.test.sh:2 rc=1" \
  "$(printf '%s\n' "$PV T1" "$PV T2" | lone listed tests/p.test.sh | nl1)"
expect_eq "in the loaded set a deleted plan section, by its heading or the list's words, and a retired verb are refused; what tells of one gone is not" \
  "one-reader-check: refused — name skills/canonical-sdlc/SKILL.md:2 one-reader-check: refused — name skills/canonical-sdlc/SKILL.md:3 one-reader-check: refused — name skills/canonical-sdlc/SKILL.md:4 rc=1" \
  "$(printf '%s\n' 'It holds no state, matrix or handoff section.' '| 3 Plan | the plan, with the Verification Matrix |' '## Dispatch Ledger' "$PV T1" \
    | lone skill skills/canonical-sdlc/SKILL.md | nl1)"
TREE="$(bash "$CHECK" "$BIONIC_SCRIPTS_DIR" 2>&1)"; TRC=$?
expect_eq "the checkout's suites and loaded set name none, with nothing admitted" "names=0 rc=0" "$(printf '%s\n' "$TREE" | /usr/bin/grep '^names=') rc=$TRC"
n=0; for p in "f=\"\$1/$(dl 'landing.proofs.log')\"" "# the $(dl 'asks.stat.') register" "# hooks/$(dl 'stop.guard.sh')" "bash \"\$H/$(dl 'agent.context.guard.sh')\" \"\$@\""; do n=$((n + 1))
  expect_eq "an old record's or a deleted hook's name planted alone is refused by its file and line: $p" "one-reader-check: refused — name payload/scripts/lib/p.sh:1 rc=1" \
    "$(echo "$p" | lone "file$n" payload/scripts/lib/p.sh | tr '\n' ' ' | sed 's/ $//')"; done
expect_eq "in a reader's file the old records' names are admitted, a deleted hook's is not" "one-reader-check: refused — name payload/scripts/lib/reader.sh:3 rc=1" \
  "$(printf '%s\n' "f=\"\$1/$(dl 'landing.proofs.log')\"" "# $(dl 'asks.stat.')" "# hooks/$(dl 'stop.guard.sh')" | lone reader payload/scripts/lib/reader.sh | tr '\n' ' ' | sed 's/ $//')"
expect_eq "the deletion list yields names, and the check's own text holds none of them whole" "y 0" "${LN:+y} $(/usr/bin/grep -cwF -f <(printf '%s\n' "$LN") "$CHECK")"
# The deleted act's file and function, read from the list so that no line of this suite spells either.
n=0; for a in $(printf '%s\n' "$LN" | sed -n '/^bring-/p; /^bf_/p'); do n=$((n + 1))
  expect_eq "the deleted act's name planted alone is refused by its file and line: $a" "one-reader-check: refused — name payload/scripts/p.sh:1 rc=1" \
    "$(printf 'bash "$R/%s" "$plan"\n' "$a" | lone "act$n" payload/scripts/p.sh | tr '\n' ' ' | sed 's/ $//')"; done
expect_eq "…the list naming both, the file and the function" 2 "$n"
# A design ledger heading and a debt ledger row: no code writes or parses either file.
ledgers() { /usr/bin/grep -rnE '## Δ|/ \\[|] /|" [|] raised-by ' "$1/hooks" "$1/payload/scripts" | grep -v -e ':[0-9]*: *#'; }
printf '%s\n' '# ## Δ0 in a comment' "led_n() { sed -n 's/^## Δ\\([0-9]*\\).*/\\1/p' \"\$1\"; }" > "$L/planted-ledger.sh"
expect_eq "the extractor reads the planted ledger parser and not the comment" "1" "$(ledgers "$S" | grep -c planted-ledger.sh)"
expect_eq "neither ledger file is written or parsed" "" "$(ledgers "$S" | grep -v planted-ledger.sh)"

section "REFUSALS"
own() { printf '%s\n' "${2:-$BEFORE}" | awk -F'\t' -v f="hooks/$1.sh:" '$1 == "refusal" && index($2, f) == 1 { n = $2; sub(/.*:/, "", n); print n, $3 }'; }
expect_eq "every planted site is listed, one for each name the check counts" \
  "refuse refuse refuse refuse fold_block dp_finding patrol_deny dp_not_checked deny block" "$(own engage "$AFTER" | awk '{ print $2 }' | tr '\n' ' ' | sed 's/ $//')"
expect_regex "the extractor reads the planted file's sites by line" "^[0-9]+ refuse$" "$(own engage "$AFTER" | head -1)"
expect_eq "the refusal count rises by ten" "$(( $(count "$BEFORE" hook_refusals) + 10 ))" "$(count "$AFTER" hook_refusals)"
expect_eq "the write hook's file and the permission hook's list no refusal" "0 0" "$(own canonical-sdlc-governing-skill | grep -c .) $(own permission-answer | grep -c .)"
expect_eq "the dispatch wall's file lists no refusal" "0" "$(own dispatch-preflight | grep -c .)"
expect_eq "the Bash wall's file lists no refusal" "0" "$(own bash-walls | grep -c .)"
# Each fact the dispatch library says, its facts given as @, cut at them into pieces of ten columns or more: a
# piece found in the wall's code is a refusal's words left in the hook, whatever function holds them.
DPIECES="$(bash -c '. "$1/refuse.sh" && . "$1/dispatch.sh" || exit 1
  for k in $(dispatch_keys); do dispatch_say "$k" @ @ @ @ @ @ @ @ @ @ && printf "%s\n" "$DISPATCH_FACT"; done' _ "$L" | tr '@' '\n' | awk 'length($0) >= 10')"
pieces_in() { awk '!/^[ \t]*#/' "$1" > "$S/.code"; printf '%s\n' "$DPIECES" | while IFS= read -r p; do /usr/bin/grep -qF -- "$p" "$S/.code" && printf '%s\n' "$p"; done; }
DKEYS="$(bash -c '. "$1/refuse.sh" && . "$1/dispatch.sh" && for k in $(dispatch_keys); do dispatch_say "$k" @ && [ -n "$DISPATCH_FACT" ] && echo "$k"; done' _ "$L" | grep -c .)"
expect_eq "the dispatch library says a fact under a key for each of the wall's 43 refusals" 43 "$DKEYS"
expect_eq "every piece of those facts is found in the library's own text" "$(printf '%s\n' "$DPIECES" | grep -c .)" "$(pieces_in "$L/dispatch.sh" | grep -c .)"
expect_eq "no fact of the dispatch library is found in the wall's file" "" "$(pieces_in "$S/hooks/dispatch-preflight.sh")"
expect_eq "the stop hook's file, which answers the stop of an agent, lists no refusal" "0" "$(own stop | grep -c .)"
# The landing runs tests/lib/lint.sh over the files a row changed: told the planted hook alone changed, its REFUSALS
# names every site the whole check lists there, by line; told only an unregistered file changed, it names none.
LINT_LIB="${BIONIC_SCRIPTS_DIR}/tests/lib/lint.sh"
lint_refusal_lines() { printf '%s\n' "$1" | bash "$LINT_LIB" "$S" 2>&1 | awk '$1 == "REFUSALS" { sub(/^hooks\/engage\.sh:/, "", $2); print $2, $3 }'; }
expect_eq "lint.sh's REFUSALS over the changed hook names the ten planted sites" 10 "$(lint_refusal_lines hooks/engage.sh | grep -c .)"
expect_eq "…each one a site the check lists in it, by line" \
  "$(own engage "$AFTER" | tr '\n' ' ')" "$(lint_refusal_lines hooks/engage.sh | tr '\n' ' ')"
expect_eq "…and over a changed file that is no registered hook it names none" "" "$(lint_refusal_lines payload/scripts/lib/planted-folds.sh)"
# The stop guard's words are its facts and its details, each line cut at its facts and trimmed.
DPIECES="$(bash -c '. "$1/refuse.sh" && . "$1/stop.sh" || exit 1
  for k in $(stop_guard_keys); do stop_guard_say "$k" @ @ @ @ @ @ && printf "%s\n%s\n" "$SG_FACT" "$SG_DETAIL"; done' _ "$L" \
  | tr '@' '\n' | awk '{ gsub(/^[ \t]+|[ \t]+$/, "") } length($0) >= 10' | sort -u)"
expect_eq "the stop library says a fact under a key for each of the guard's nine refusals, its frame the detail of six" 9 \
  "$(bash -c '. "$1/refuse.sh" && . "$1/stop.sh" && for k in $(stop_guard_keys); do stop_guard_say "$k" @ && [ -n "$SG_FACT" ] && echo "$k"; done' _ "$L" | grep -c .)"
expect_regex "the guard's words cut into pieces" "^[1-9][0-9]*$" "$(printf '%s\n' "$DPIECES" | grep -c .)"
expect_eq "every piece of the guard's words is found in the stop library's own text" "$(printf '%s\n' "$DPIECES" | grep -c .)" "$(pieces_in "$L/stop.sh" | grep -c .)"
expect_eq "no piece of the guard's words is found in the stop hook's file" "" "$(pieces_in "$S/hooks/stop.sh")"

section "FOLDS"
expect_eq "a fold through a pipe, an unread \$( ) and a local's \$( ) are named; one whose exit is read and a stand-in are not" "1 2 3" \
  "$(printf '%s\n' "$AFTER" | sed -n 's|^unheard	payload/scripts/lib/planted-folds\.sh:||p' | tr '\n' ' ' | sed 's/ $//')"
expect_eq "the unheard count rises by three over the tree, which holds none" "0 3" "$(count "$BEFORE" unheard_folds) $(count "$AFTER" unheard_folds)"
# A row's tree is folded from its events by the reader alone; every other site asks the reader for it.
tree_folds() { ( cd "$1" && /usr/bin/grep -n 'ev() *== *"tree"\|_e *== *"tree"' payload/scripts/lib/*.sh payload/scripts/*.sh | cut -d: -f1 | tr '\n' ' ' | sed 's/ $//' ); }
TF="$S/tree-fold/payload/scripts"; mkdir -p "$TF/lib"; cp "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/reader.sh" "$TF/lib/reader.sh"
printf '%s\n' "planted_trees() { awk -F'|' 'ev() == \"tree\" { t[line_kv(\"row\")] = \$0 }'; }" > "$TF/planted-tree.sh"
expect_eq "a fold of the tree event planted in a script is found beside the reader's" "payload/scripts/lib/reader.sh payload/scripts/planted-tree.sh" "$(tree_folds "$S/tree-fold")"
expect_eq "the checkout folds the tree event once, in the reader" "payload/scripts/lib/reader.sh" "$(tree_folds "$BIONIC_SCRIPTS_DIR")"

section "LOGPATH"
# The run log's path is joined in the reader alone: a line that puts the file's name after a directory is a second builder.
# A comment and a case arm or a `%` strip that only reads a given path's name are no join.
joins() { ( cd "$1" && /usr/bin/grep -rnE '[^%#/]/run\.log' hooks payload/scripts \
  | /usr/bin/grep -vE '^payload/scripts/lib/reader\.sh:|^[^:]*:[0-9]+:[[:space:]]*#|\*[^ ()"]*/run\.log\)' | cut -d: -f1,2 | tr '\n' ' ' | sed 's/ $//' ); }
mkdir -p "$S/logpath/hooks" "$S/logpath/payload/scripts/lib"
printf '%s\n' '# the log is DIR/run.log' 'case "$1" in */record/*/run.log) ;; esac' 'rec="${log%/run.log}"' \
  'planted_log() { RUN_LOG="${x%/*}/run.log" log_append t; }' > "$S/logpath/payload/scripts/p.sh"
printf '%s\n' 'log="$d"/run.log' > "$S/logpath/hooks/h.sh"
printf '%s\n' 'printf "%s/run.log\n" "$rec"' > "$S/logpath/payload/scripts/lib/reader.sh"
expect_eq "a join planted in a script and a hook is found by its line; a comment, a case arm, a strip and the reader's own are not" \
  "hooks/h.sh:1 payload/scripts/p.sh:4" "$(joins "$S/logpath")"
expect_eq "the checkout joins the log's name to a path in the reader alone" "" "$(joins "$BIONIC_SCRIPTS_DIR")"
expect_eq "the reader joins it once" 1 "$(/usr/bin/grep -vE '^[[:space:]]*#' "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/reader.sh" | /usr/bin/grep -cE '[^%#/]/run\.log')"

section "DEAD"
dead() { ( cd "$1" && /usr/bin/grep -rnwE 'worktree_land|worktree_land_for_session' payload hooks skills agents-src agents 2>/dev/null | cut -d: -f1,2 | tr '\n' ' ' | sed 's/ $//' ); }
mkdir -p "$S/dead/payload/scripts"; printf '%s\n' 'f() { :; }' '# worktree_land_for_session lands a tree' > "$S/dead/payload/scripts/p.sh"
expect_eq "a planted comment naming a removed landing function is found by its file and line" "payload/scripts/p.sh:2" "$(dead "$S/dead")"
expect_eq "the checkout's code, hooks, skills and agents name neither removed landing function" "" "$(dead "$BIONIC_SCRIPTS_DIR")"

section "GITHOME"
# The common git directory is resolved by lib/root.sh's `git_common_dir` and by no other code. A line that is not a
# comment and names `git-common-dir` is a resolution of its own, counted by file so that a line moving is no change.
# The root library is the resolver's own file, and no other file resolves it: a lookup that also wants a second
# answer asks the root library's paired lookup, and a lease of a tree asks its lease lookup.
git_homes() { ( cd "$1" && /usr/bin/grep -rnE -- 'git-common-dir' payload/scripts hooks 2>/dev/null \
  | awk -F: '{ t = $0; sub(/^[^:]*:[^:]*:/, "", t); if (t !~ /^[ \t]*#/) print $1 }' | /usr/bin/grep -vx 'payload/scripts/lib/root\.sh' \
  | LC_ALL=C sort | uniq -c | awk '{ printf "%s:%s ", $2, $1 }' | sed 's/ $//' ); }
CARRIED=""
expect_eq "the checkout resolves the common git directory for itself in no file but the root library" "$CARRIED" "$(git_homes "$S")"
printf '%s\n' '# asks --git-common-dir in a comment' 'f() { git_common_dir "$1"; }' > "$L/planted-home.sh"
expect_eq "a comment naming the flag and a caller of the function are no resolution of their own" "$CARRIED" "$(git_homes "$S")"
printf '%s\n' 'g() { git -C "$1" rev-parse --git-common-dir; }' >> "$L/planted-home.sh"
expect_eq "a second resolution planted beyond them is found by its file" "$(printf '%s\n' $CARRIED payload/scripts/lib/planted-home.sh:1 | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')" "$(git_homes "$S")"
rm -f "$L/planted-home.sh"

section "LOADER"
expect_eq "the loader block's mark is found in one file, the loader's own" "payload/scripts/lib/loader.sh" \
  "$(cd "$BIONIC_SCRIPTS_DIR" && /usr/bin/grep -rl '^# --- bionic-loader/v2 BEGIN' hooks payload/scripts | sort | tr '\n' ' ' | sed 's/ $//')"
expect_eq "the check reads no pasted copy over the tree" 0 "$(count "$BEFORE" loader_copies)"
expect_contains "a copy planted in a hook file is listed" "$(printf 'loader\thooks/planted-loader.sh\t:2')" "$AFTER"
expect_absent "the loader's own file is not a copy" "$(printf 'loader\tpayload/scripts/lib/loader.sh')" "$AFTER"
expect_eq "the planted copy raises the count by one" "$(( $(count "$BEFORE" loader_copies) + 1 ))" "$(count "$AFTER" loader_copies)"

section "COPIES"
# Each line of the plant is named in the comment beside the heredoc by what it is: the check must list exactly the
# copies, by line, and nothing the plant holds that is no copy.
CR="$S/lone-copies"; mkdir -p "$CR/hooks" "$CR/payload/scripts/lib" "$CR/tests"
# 1 guard on its line · 2-5 an if above · 6 an unguarded load · 7-8 the line before · 9 the bootstrap line · 10 another
# spelling of it · 11-14 a self-dir · 15 a directory function that reads no BASH_SOURCE · 16 a one-line self-dir · 17 a
# lookup · 18 a comment naming the flag · 19 an awk reader · 20 a literal key at a fixed place · 21 a shell reader · 22 a
# word read by blank · 23-24 a literal key at a walked field whose value the line takes · 25 a literal key that only filters
cat > "$CR/payload/scripts/lib/c.sh" <<'EOF'
declare -F foo_x >/dev/null 2>&1 || . "$d/foo.sh"
if ! declare -F bar_x >/dev/null 2>&1; then
  x=1
  . "$d/bar.sh"
fi
. "$d/plain.sh"
[ -n "${_BAZ_LOADED:-}" ] ||
  . "$d/baz.sh"
declare -F bionic_need >/dev/null 2>&1 || case "${BASH_SOURCE[0]}" in */*) . "${BASH_SOURCE[0]%/*}/loader.sh" ;; *) . ./loader.sh ;; esac
declare -F bionic_need >/dev/null 2>&1 || . "${BASH_SOURCE[0]%/*}/loader.sh"
_c_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}
_c_lock_dir() { printf '%s/lock' "$1"; }
_c_one_dir() { dirname "${BASH_SOURCE[0]}"; }
g() { git -C "$1" rev-parse --git-common-dir; }
# asks --git-common-dir in a comment
v() { awk -F'|' -v k="$2" '{ for (i = 2; i <= NF; i++) if (index($i, k "=") == 1) print substr($i, length(k) + 2) }'; }
r() { awk -F'|' 'index($2, "row=") == 1 { print }'; }
_c_field() { local IFS='|' f; for f in $1; do case "$f" in "$2="*) printf '%s\n' "${f#"$2="}"; return 0 ;; esac; done; }
w() { case " $1 " in *" $2="*) : ;; esac; }
n() { awk -F'|' '{ for (i = 2; i <= NF; i++) if (index($i, "name=") == 1) { print substr($i, 6); exit } }'; }
m() { awk '{ c = split($0, f, "|"); for (j = 2; j <= c; j++) if (index(f[j], "fails-when=") == 1) print substr(f[j], 12) }'; }
d() { awk -F'|' '{ o = $1; for (i = 2; i <= NF; i++) { if (index($i, "reason=") == 1) continue; o = o "|" $i } print o }'; }
EOF
# Each idiom in its home's own file, and a suite's guard, which the counts do not read.
printf '%s\n' 'declare -F foo_x >/dev/null 2>&1 || . "$d/foo.sh"' > "$CR/payload/scripts/lib/loader.sh"
printf '%s\n' 'git_common_dir() { git -C "$1" rev-parse --git-common-dir; }' > "$CR/payload/scripts/lib/root.sh"
printf '%s\n' "function line_kv(k,   i) { for (i = 2; i <= NF; i++) if (index(\$i, k \"=\") == 1) return substr(\$i, length(k) + 2); return \"\" }" \
  > "$CR/payload/scripts/lib/fields.sh"
printf '%s\n' 'declare -F foo_x >/dev/null 2>&1 || . "$d/foo.sh"' > "$CR/tests/t.sh"
CO="$(bash "$CHECK" "$CR" 2>"$S/.cerr")"; CRC=$?
copies() { printf '%s\n' "$CO" | awk -F'\t' -v k="$1" '$1 == k { print $2 }' | tr '\n' ' ' | sed 's/ $//'; }
L1="payload/scripts/lib/c.sh"
expect_eq "guards on their line, under an if and after the line before, a second spelling of the bootstrap line and the two self-dirs are listed by line" \
  "$L1:1 $L1:4 $L1:8 $L1:10 $L1:11 $L1:16" "$(copies load-guard)"
expect_eq "the lookup is listed by its line, the comment naming the flag is not" "$L1:17" "$(copies git-home)"
expect_eq "the awk readers, by a handed key or a literal one at a walked field, and the shell reader are listed by line; a key at a fixed place, a key that only filters and a word read by blank are not" \
  "$L1:19 $L1:21 $L1:23 $L1:24" "$(copies field-reader)"
expect_eq "each is counted, and none is refused: the check exits 0 and says nothing on stderr" "6 1 4 rc=0 ''" \
  "$(count "$CO" load_guards) $(count "$CO" git_homes) $(count "$CO" field_readers) rc=$CRC '$(cat "$S/.cerr")'"
home() { printf '%s\n' "$CO" | awk -F'\t' -v w="$1" '$2 == w { print $3 }'; }
expect_eq "a guard names its home" "guard: use bionic_need (payload/scripts/lib/loader.sh)" "$(home "$L1:1")"
expect_eq "a self-dir names itself and its home" "self-dir _c_self_dir: use bionic_need (payload/scripts/lib/loader.sh)" "$(home "$L1:11")"
expect_eq "a lookup names its home" "lookup: use git_common_dir (payload/scripts/lib/root.sh)" "$(home "$L1:17")"
expect_eq "an awk reader, a shell reader and a literal key's reader name their homes" \
  "awk reader: use line_kv (payload/scripts/lib/fields.sh)|shell reader: use line_value (payload/scripts/lib/fields.sh)|awk reader: use line_kv (payload/scripts/lib/fields.sh)" \
  "$(home "$L1:19")|$(home "$L1:21")|$(home "$L1:23")"
expect_eq "the tree's lookups, counted by the check, are as many as the carried list's" \
  "$(printf '%s\n' $CARRIED | awk -F: '{ n += $2 } END { print n + 0 }')" "$(count "$BEFORE" git_homes)"
expect_regex "the tree's guards and readers are counted" "^[0-9]+ [0-9]+$" "$(count "$BEFORE" load_guards) $(count "$BEFORE" field_readers)"
# The lint names a copy in a changed file with its home only once the check's list of refusing counts holds the idiom's
# count; the same plant read by the check as it is, and by a copy whose list holds the three counts.
OH="$S/onehome"; mkdir -p "$OH/payload"; cp -R "${BIONIC_SCRIPTS_DIR}/hooks" "$OH/hooks"; cp -R "${BIONIC_SCRIPTS_DIR}/payload/scripts" "$OH/payload/scripts"
cp "$CR/payload/scripts/lib/c.sh" "$OH/payload/scripts/lib/planted-copies.sh"
onehome() { printf '%s\n' payload/scripts/lib/planted-copies.sh | bash "$LINT_LIB" "$OH" 2>/dev/null | awk '$1 == "ONEHOME"'; }
OH_OFF="$(onehome)"
sed 's/^REFUSING="\(.*\)"$/REFUSING="\1 load_guards git_homes field_readers"/' "$CHECK" > "$OH/payload/scripts/one-reader-check.sh"
expect_eq "setup: the copy's list of refusing counts is the only line changed" 1 "$(diff "$CHECK" "$OH/payload/scripts/one-reader-check.sh" | grep -c '^>')"
OH_ON="$(onehome)"
expect_eq "with the three counts refusing, the lint names each copy in the changed file by line" \
  "planted-copies.sh:1 planted-copies.sh:4 planted-copies.sh:8 planted-copies.sh:10 planted-copies.sh:11 planted-copies.sh:16 planted-copies.sh:17 planted-copies.sh:19 planted-copies.sh:21 planted-copies.sh:23 planted-copies.sh:24" \
  "$(printf '%s\n' "$OH_ON" | awk '{ sub(/.*\//, "", $2); print $2 }' | tr '\n' ' ' | sed 's/ $//')"
expect_contains "…naming the home beside the line" "ONEHOME payload/scripts/lib/planted-copies.sh:17 — lookup: use git_common_dir (payload/scripts/lib/root.sh)" "$OH_ON"
expect_eq "with the list as the check holds it, the same changed file is named by none" "" "$OH_OFF"

section "KEPT"
KEPT="$(sed -n 's/^KEPT_COPIES="\(.*\)"$/\1/p' "$CHECK")"
expect_nonempty "the check keeps copies by name" "$KEPT"
for e in $KEPT; do
  f="${e%%:*}"; fnn="${e#*:}"
  expect_eq "$e: the kept copy stands in its file and admits its line" "1|" \
    "$(/usr/bin/grep -cE "^[[:space:]]*$fnn[[:space:]]*\(\)" "$S/$f")|$(printf '%s\n' "$BEFORE" | awk -F'\t' -v f="$f:" -v n="$fnn" '$1 == "load-guard" && index($2, f) == 1 && index($3, n ":")')"
done
expect_absent "no entry of the list stands unheld in the tree" "$(printf 'kept\t')" "$BEFORE"
# The doctor's self-dir in a root of its own: kept as it is, and named twice once its name moves off the entry.
KR="$S/lone-kept"; mkdir -p "$KR/hooks" "$KR/payload/scripts"; cp "${BIONIC_SCRIPTS_DIR}/payload/scripts/doctor.sh" "$KR/payload/scripts/doctor.sh"
expect_eq "the doctor's self-dir is kept: nothing is listed for it" "rc=0" "$(bash "$CHECK" "$KR" 2>&1 | awk -F'\t' '$1 == "kept" || $3 ~ /^self-dir/ { print }'; echo "rc=$?")"
sed 's/_doctor_self_dir/_doctor_own_dir/g' "${BIONIC_SCRIPTS_DIR}/payload/scripts/doctor.sh" > "$KR/payload/scripts/doctor.sh"
KO="$(bash "$CHECK" "$KR" 2>&1)"; KRC=$?
expect_contains "renamed, the self-dir is listed" "$(printf 'load-guard\tpayload/scripts/doctor.sh:')" "$KO"
expect_contains "…and the entry that admits no line is a finding" "$(printf 'kept\tpayload/scripts/doctor.sh:_doctor_self_dir\tadmits no line')" "$KO"
expect_eq "…refused, by its entry, and counted with the names" "one-reader-check: refused — kept payload/scripts/doctor.sh:_doctor_self_dir|names=1|rc=1" \
  "$(printf '%s\n' "$KO" | grep '^one-reader-check: refused — ')|$(printf '%s\n' "$KO" | grep '^names=')|rc=$KRC"
expect_absent "a root holding none of the kept files judges no entry" "$(printf 'kept\t')" "$CO"

section "REPORT"
expect_status "with the plants the check exits 1" 1 "$RC"
expect_eq "it refuses each planted parser, plan writer, shared type, loader copy and name once, on stderr" \
  "$(( $(count "$AFTER" parsers) + $(count "$AFTER" plan_writers) + $(count "$AFTER" shared_types) + $(count "$AFTER" loader_copies) + $(count "$AFTER" names) ))" "$(grep -c '^one-reader-check: refused — ' "$S/.err")"
expect_eq "a loader copy planted alone is refused by its file and line" "one-reader-check: refused — loader hooks/p.sh:1 rc=1" \
  "$(echo '# --- bionic-loader/v2 BEGIN' | lone loader hooks/p.sh | tr '\n' ' ' | sed 's/ $//')"
expect_eq "it ends on the ten count lines, in order" \
  "parsers plan_writers shared_types hook_refusals loader_copies unheard_folds names load_guards git_homes field_readers" \
  "$(printf '%s\n' "$AFTER" | tail -10 | sed -n 's/^\([a-z_]*\)=[0-9][0-9]*$/\1/p' | tr '\n' ' ' | sed 's/ $//')"
bash "$CHECK" "$S/no-such" >/dev/null 2>&1; expect_status "a root that is not a checkout exits 2" 2 "$?"

# §READINGS runs from the checkout; a scratch commit on a shared clone moves a count without touching it. The records
# it reads are the bed's runs at 15, each its page and its log.
READ="${BIONIC_SCRIPTS_DIR}/payload/scripts/readings.sh"; F="$(cd "${BIONIC_SCRIPTS_DIR}/tests/fixtures/replay" && pwd -P)"
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
BORN="$(born "${BIONIC_SCRIPTS_DIR}/tests/fixtures/replay/wave-46-asks-nothing/plans/epic-23-bionic-tech-debt/wave-46-asks-nothing.plan.md")"

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

section "DOCSPATH"
# A path spelled from the project root or the docs root is read by lib/root.sh `docs_path`, and by adopt and the review proof through it.
. "$(dirname "$0")/lib/bound-marker.sh"; . "$(dirname "$0")/lib/roster-row.sh"; . "$(dirname "$0")/lib/plan-fixture.sh"
POKER="${BIONIC_HOOKS_DIR}/session-poker.sh"; S46_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/proof.sh"
. "$(dirname "$0")/session-poker.prelude.sh"; trap 'cleanup; rm -rf "$S"' EXIT
R="$(make_repo dp)"; D="$R/.bionic/docs"; W="$D/record/wave-01-fixture"; mkdir -p "$W"; : > "$W/a.md"
dp() { bash -c '. "$1/root.sh"; docs_path "$2" "$3"' _ "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib" "$R" "$1"; }
for sp in .bionic/docs/record/wave-01-fixture/a.md record/wave-01-fixture/a.md; do
  expect_eq "docs_path reads $sp as the file" "$W/a.md" "$(dp "$sp")"
done
expect_eq "a record not yet written, spelled from the docs root, is under it" "$W/y.md" "$(dp record/wave-01-fixture/y.md)"
joins() { ( cd "$1" && /usr/bin/grep -rnE 'docs_root[^|;]*\)/\$\{?[A-Za-z_]*(ARG|arg)' hooks payload/scripts | /usr/bin/grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' | cut -d: -f1 | tr '\n' ' ' | sed 's/ $//' ); }
expect_eq "no code but root.sh's resolver joins the docs root to an operand for itself" "" "$(joins "$S")"
printf '%s\n' 'p="$(docs_root "$r")/$arg"' > "$L/planted-join.sh"
expect_eq "a join planted beside it is found by its file" "payload/scripts/lib/planted-join.sh" "$(joins "$S")"; rm -f "$L/planted-join.sh"
B="$(git -C "$R" commit -q --allow-empty -m init && git -C "$R" rev-parse HEAD)"
P="$(s42_plan "$R" 4 "  worktree: .worktrees/01-fixture
  base-sha: ${B:0:8}
  branch: wave/01-fixture")"; s42_builds_landed "$P"
git -C "$R" worktree add -q -b wave/01-fixture "$R/.worktrees/01-fixture" "$B" >/dev/null 2>&1
git -C "$R/.worktrees/01-fixture" commit -q --allow-empty -m C1; C="$(git -C "$R/.worktrees/01-fixture" rev-parse HEAD)"
printf 'reviewed: %s..%s\nquestion: evidence\nresult: pass\nscope: piece\n' "${B:0:10}" "$C" > "$W/x.md"
for sp in .bionic/docs/record/wave-01-fixture/x.md record/wave-01-fixture/x.md; do
  new_roster "$R"; roster_row_fixture session="$SID" name=implementor agent_id=a1 subagent_type=implementor >> "$(roster_of "$R")"
  printf '%s|questions=evidence\n' "$(roster_row_fixture session="$SID" name=aud agent_id=a2 subagent_type=bionic:auditor files="$sp")" >> "$(roster_of "$R")"
  OS=5f5f5f5f-0000-4000-8000-000000000055; roster_header > "$(roster_of "$R" "$OS")"
  mkrow session="$OS" name=w plan="$P" deliverable="${sp%x.md}a.md" >> "$(roster_of "$R" "$OS")"; poke "$R" adopt
  expect_contains "adopt finds a deliverable spelled $sp" "|deliverable_present=yes|" "$OUT"
  poke "$R" proof-add review record/wave-01-fixture/x.md --question evidence --reader aud
  expect_eq "the review proof finds a record its reader's row spells $sp (exit 0)" 0 "$RC"
  [ "$RC" = 0 ] || printf '%s\n' "$OUT" | head -3
  git -C "$R" checkout -q -- . 2>/dev/null
done

finish
