#!/bin/bash
# tests/proof-at-head.test.sh — THE FULL PASS'S STATE, PRINTED ONCE: payload/scripts/lib/proof.sh `proof_whole_text`.
#
# WHAT IT HOLDS. Green is content: the full pass at F proves a head whose commits since F moved no code by the judge's
# cover basis (prose, or release with its check passing). A head past F that moved code is red there, with the landings
# since counted, even where the landings' own suites cover it to the judge. Every surface that states the full pass
# prints it from the one printer: the release card's `whole suite:` line, the scorecard's correctness line (which the
# continuation carries under ## Scorecard) and close-out's continuation header.
#
# §ONE   a red run at F, two landings greening its reds: the three surfaces print `red at <F8>, 2 landings before this
#        head`, a close-out copy printing green splits them; then a green run at F with docs, release and code past it
# §LOG   a review reading, a regression proof and an approval the run's log alone holds are read by the judge and the
#        proof readers, which ask the reader; a proof written between two reads in one process is read by the second;
#        an inherited suite is read from the log alone, two at one head as two; the base is the header's
# §KEEP  the kept fold is served from the user's own mode-700 directory, never from one others can write or a link; a fold that failed is kept nowhere
# §IFS   under a tab as the caller's only separator the fold's key still covers the log, and a rating and a verdict read
#        as they do under the default
#
# FIXTURE FIDELITY. The project is close-out's own (tests/close-out.prelude.sh) at Step 8, its working branch checked
# out beside it. `pah_world` lays the regression proof as `proof-add regression` writes it and each landing as the line
# logs it (ready, a green verdict per suite at the landed commit, published); the surfaces are the real verbs.
#
# ANTI-VACUITY. Each surface's state is read through its own extractor, shown non-empty before the states are
# compared; the split arm and the mutant each prove their copy ran before their absence is read.
#
# Usage: bash tests/proof-at-head.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/regression-fixture.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"
. "$(dirname "$0")/close-out.prelude.sh"

PAH_LIB="$REPO_ROOT/payload/scripts/lib"
PAH_POKER="${BIONIC_HOOKS_DIR}/session-poker.sh"
CO_PLAN_AT=15   # the worlds here are at 15

# pah_world <label> <owed suites, comma-joined, or empty> <landings> -> PAH_P, PAH_PLAN, PAH_F (the whole run's head)
# and PAH_H (the working head): the close-out fixture at Step 8 with a whole run at F that left <owed> red, then
# <landings> code landings, landing k greening the owed suites at positions k, k + <landings>, …; with landings the
# integration branch takes the working branch, the readings move to H and the run carries the word to merge at H.
# The page is at 15, where the proof, the readings' head and the word are the run's log's events, each by its writer.
pah_world() {
  local label="$1" owed="$2" n="${3:-0}" p plan w k i s su c log
  p="$(CO_PLAN_AT=15 mk_fixture "$label")" || return 1
  advance_to "$p" 8
  plan="$p/$PLAN_REL"; w="$p-wave"
  PAH_F="$(fixture_git "$p" rev-parse wave/01-fixture)"
  log="$p/$LOG_REL"
  sed '/|ev=proof|kind=regression|/d' "$log" > "$log.n" && mv "$log.n" "$log"
  bash -c '. "$1/run.sh" && . "$1/proof.sh" || exit 1
    LOG_AT=2026-10-04T12:00:00Z proof_event "$2" kind=regression "head=$3" "evidence=record/wave-01-fixture/regression-run-$3.log" ${4:+"owed=$4"}' \
    _ "$PAH_LIB" "$plan" "$PAH_F" "$owed" || return 1
  k=1
  while [ "$k" -le "$n" ]; do
    su=""; i=0
    for s in ${owed//,/ }; do
      [ $(( i % n + 1 )) -ne "$k" ] || su="$su${su:+,}$s"
      i=$((i + 1))
    done
    printf 'T%d\n' "$((k + 2))" >> "$w/land-$k.txt"
    fixture_git "$w" add "land-$k.txt" && fixture_git "$w" commit -qm "T$((k + 2)): a fix" || return 1
    c="$(fixture_git "$w" rev-parse HEAD)"
    {
      printf 'run/v1|ev=ready|row=T%d|name=w-T%d|commit=%s|branch=wt/01-T%d|tree=%s|suites=%s|debt=-|carrier=1:x|at=2026-10-04T13:%02d:00Z\n' \
        "$((k + 2))" "$((k + 2))" "$c" "$((k + 2))" "$w" "${su:-a.test.sh}" "$((k * 10))"
      for s in ${su//,/ }; do
        printf 'run/v1|ev=verdict|row=T%d|commit=%s|suite=%s|result=green|log=/rec/T%d-%s.log|at=2026-10-04T13:%02d:30Z\n' \
          "$((k + 2))" "$c" "$s" "$((k + 2))" "$s" "$((k * 10))"
      done
      printf 'run/v1|ev=published|row=T%d|commit=%s|kind=queue|by=-|why=-|at=2026-10-04T13:%02d:50Z\n' "$((k + 2))" "$c" "$((k * 10))"
    } >> "$log"
    k=$((k + 1))
  done
  PAH_H="$(fixture_git "$p" rev-parse wave/01-fixture)"
  if [ "$n" -gt 0 ]; then
    fixture_git "$p" merge -q --no-ff -m "merge wave" wave/01-fixture >/dev/null 2>&1 || return 1
    # The landings cover the head and no pass ran at it, so the merge close-out delivers is the person's word at H.
    sed "s/|ev=proof|kind=review|head=$PAH_F|/|ev=proof|kind=review|head=$PAH_H|/" "$log" > "$log.n" && mv "$log.n" "$log"
    bash -c '. "$1/run.sh" && . "$1/proof.sh" || exit 1
      LOG_AT=2026-10-04T14:00:00Z proof_approval_event "$2" merge-unproved by=fixture "head=$3" "said=merge it"' \
      _ "$PAH_LIB" "$plan" "$PAH_H" || return 1
  fi
  PAH_P="$p"; PAH_PLAN="$plan"
}

# pah_poke <project> <sid> <verb> [<arg>...] -> PAH_OUT, PAH_RC: the real poker verb in the project, as that session.
pah_poke() {
  local p="$1" sid="$2"; shift 2
  ( in_fixture "$p" || exit 9
    HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" CLAUDE_CODE_SESSION_ID="$sid" \
      bash "$PAH_POKER" "$@" ) > "$SANDBOX/pah-poker" 2>&1
  PAH_RC=$?; PAH_OUT="$(cat "$SANDBOX/pah-poker")"
}

# THE THREE EXTRACTORS, one per surface, each printing the state the surface states and nothing else.
# pah_card_state <card> -> the state after `whole suite: ` on the Tests line, its folded lines joined.
pah_card_state() {
  printf '%s\n' "$1" | awk '
    on && /^   [^ ]/ { s = s " " substr($0, 4); next }
    on { exit }
    { i = index($0, "whole suite: ") }
    i { s = substr($0, i + 13); on = 1 }
    END { print s }'
}
# pah_score_state <scorecard> -> the state after `whole run ` on the correctness line, to its `; `.
pah_score_state() {
  printf '%s\n' "$1" | awk 'index($0, "correctness: ") == 1 { i = index($0, "; whole run "); if (!i) exit
    s = substr($0, i + 12); j = index(s, "; "); print (j ? substr(s, 1, j - 1) : s); exit }'
}
# pah_cont_state <continuation file> -> the state after `the regression: whole suite ` in its header, to ` (proved`.
pah_cont_state() {
  awk '{ i = index($0, "the regression: whole suite "); if (!i) next
    s = substr($0, i + 28); j = index(s, " (proved"); print (j ? substr(s, 1, j - 1) : s); exit }' "$1" 2>/dev/null
}
# pah_one <card> <scorecard> <continuation states> -> `one: <state>` when the three agree, else `split: card=<…>; …`.
pah_one() {
  if [ -n "$1" ] && [ "$1" = "$2" ] && [ "$2" = "$3" ]; then printf 'one: %s\n' "$1"
  else printf 'split: card=%s; scorecard=%s; continuation=%s\n' "$1" "$2" "$3"; fi
}

PAH_OWED="notify.test.sh,rehearsal-failed-review.test.sh,shell-lint.test.sh,sitrep.test.sh"

# ============================================================
section "§ONE: the card, the scorecard and the continuation print one state of the full pass over one run"
# ============================================================
# fails-when: one surface computes its own answer, so over a red whole run whose reds two later landings greened the
# card reads covered, the scorecard green or the continuation holds; or the landings since the run go uncounted.
pah_world one "$PAH_OWED" 2
P1="$PAH_P"; P1_PLAN="$PAH_PLAN"; P1_F="$PAH_F"; P1_H="$PAH_H"
expect_eq "ONE-0 precondition: the working head is two first-parent commits past the whole run's head, and the judge reads it covered" \
  "2|covered	$P1_H" \
  "$(fixture_git "$P1" rev-list --first-parent --count "$P1_F..$P1_H")|$(bash -c '. "$1/roots.sh" && . "$1/proof.sh" && proof_state "$2" "$3"' _ "$PAH_LIB" "$P1_PLAN" "$P1" 2>/dev/null)"
( in_fixture "$P1" || exit 1; bound_marker "$P1" pah-one-card "$P1_PLAN" )
pah_poke "$P1" pah-one-card release-approval --preview "$P1_PLAN"
P1_CARD="$PAH_OUT"; P1_CARD_RC="$PAH_RC"
pah_poke "$P1" pah-one-card landing-report --scorecard "$P1_PLAN"
P1_SCORE="$PAH_OUT"; P1_SCORE_RC="$PAH_RC"
run_close_as pah-one-close "$P1" run
P1_CLOSE_RC="$CO_RC"
expect_eq "ONE-1 precondition: the card renders, the scorecard prints and close-out delivers (exit 0 each)" "0|0|0" \
  "$P1_CARD_RC|$P1_SCORE_RC|$P1_CLOSE_RC"
[ "$P1_CLOSE_RC" = 0 ] || printf '      close-out said: %s\n' "$(printf '%s\n' "$CO_OUT" | tail -3)"
expect_nonempty "ONE-2 precondition: the card's state is read off its whole-suite line" "$(pah_card_state "$P1_CARD")"
expect_nonempty "ONE-3 precondition: the scorecard's state is read off its correctness line" "$(pah_score_state "$P1_SCORE")"
expect_nonempty "ONE-4 precondition: the continuation's state is read off its regression line" "$(pah_cont_state "$P1/$CONT_REL")"
P1_WANT="red at ${P1_F:0:8}, 2 landings before this head"
expect_eq "ONE-5 the three surfaces print one state: red at the whole run's head, the two landings since counted" \
  "one: $P1_WANT" \
  "$(pah_one "$(pah_card_state "$P1_CARD")" "$(pah_score_state "$P1_SCORE")" "$(pah_cont_state "$P1/$CONT_REL")")"
expect_eq "ONE-6 …and the card marks it not green" "✖️ whole suite: $P1_WANT" \
  "$(printf '%s\n' "$P1_CARD" | /usr/bin/grep -F "whole suite: " | head -1)"
expect_eq "ONE-7 …and the continuation's own scorecard carries the same correctness state" "$P1_WANT" \
  "$(pah_score_state "$(sed -n '/^## Scorecard$/,/^## /p' "$P1/$CONT_REL")")"

# THE SPLIT ARM: a copy of close-out.sh whose continuation prints green for the run, the shape the old text took.
pah_world one-split "$PAH_OWED" 2
P2="$PAH_P"; P2_F="$PAH_F"
PAH_MUT="$SANDBOX/mut-scripts"
cp -R "$REPO_ROOT/payload/scripts" "$PAH_MUT"
sed 's/whole_text="$(proof_whole_text "$PLAN" "$ROOT")"/whole_text="green at $(proof_last "$PLAN" regression | cut -c1-8)"/' "$REPO_ROOT/payload/scripts/close-out.sh" \
  > "$PAH_MUT/close-out.sh"
expect_eq "ONE-8 precondition: the copy differs from close-out.sh at the printer's call alone" "1" \
  "$(diff "$REPO_ROOT/payload/scripts/close-out.sh" "$PAH_MUT/close-out.sh" | /usr/bin/grep -c '^>')"
PAH_SCRIPT_KEEP="$SCRIPT"; SCRIPT="$PAH_MUT/close-out.sh"
run_close_as pah-split-close "$P2" run
SCRIPT="$PAH_SCRIPT_KEEP"
expect_eq "ONE-9 the copy ran: close-out delivers (exit 0) and its continuation's line reads green at the whole run's head" \
  "0|green at ${P2_F:0:8}" "$CO_RC|$(pah_cont_state "$P2/$CONT_REL")"
expect_regex "ONE-10 …and the check over the card, the scorecard and that continuation reads split" '^split: ' \
  "$(pah_one "$(pah_card_state "$P1_CARD")" "$(pah_score_state "$P1_SCORE")" "$(pah_cont_state "$P2/$CONT_REL")")"


# pah_past <spec>... -> PAH_H: a commit on the working branch per <spec> (its paths, comma-joined), then the merge.
pah_past() {
  local spec f
  for spec in "$@"; do
    for f in ${spec//,/ }; do mkdir -p "$(dirname "$PAH_P-wave/$f")"; printf '%s\n' "$spec" >> "$PAH_P-wave/$f"; fixture_git "$PAH_P-wave" add "$f" || return 1; done
    fixture_git "$PAH_P-wave" commit -qm "past F: $spec" || return 1
  done
  PAH_H="$(fixture_git "$PAH_P" rev-parse wave/01-fixture)"; fixture_git "$PAH_P" merge -q --no-ff -m "merge wave" wave/01-fixture >/dev/null 2>&1
}
pah_whole() { bash -c '. "$1/roots.sh" && . "$1/proof.sh" && proof_whole_text "$2" "$3"' _ "${1:-$PAH_LIB}" "$PAH_PLAN" "$PAH_P" 2>/dev/null; }  # [<lib>] -> the printer's line
pah_cover() { bash -c '. "$1/roots.sh" && . "$1/proof.sh" && facts_cover "$2" "$3" "$4"' _ "$1" "$P3_PLAN" "$P3_F" "$P3_H" 2>/dev/null | awk '{ printf "%s%s %s", (NR > 1 ? "|" : ""), $1, $3 }'; }  # <lib> -> each basis F..H
# fails-when: green only at F itself, so two docs commits past it read red, the card asks the merge, close-out refuses.
pah_world past-docs "" 0
P3="$PAH_P"; P3_F="$PAH_F"
expect_eq "ONE-11 precondition: a green whole run at the working head reads green at it" "green at ${P3_F:0:8}" "$(pah_whole)"
pah_past README.md docs/notes.md
P3_PLAN="$PAH_PLAN"; P3_H="$PAH_H"; P3_WANT="green at ${P3_F:0:8}, 2 landings since moved no code"
expect_eq "ONE-12 precondition: the head is two first-parent commits past F, each prose by the judge's walk" "2|cover prose|cover prose" "$(fixture_git "$P3" rev-list --first-parent --count "$P3_F..$P3_H")|$(pah_cover "$PAH_LIB")"
expect_eq "ONE-13 (AC-1.1) two docs-only commits past a green whole run: the state reads green at F, the landings since counted" "$P3_WANT" "$(pah_whole)"
( in_fixture "$P3" || exit 1; bound_marker "$P3" pah-past-card "$P3_PLAN" )
pah_poke "$P3" pah-past-card release-approval --preview "$P3_PLAN"; P3_CARD="$PAH_OUT"
pah_poke "$P3" pah-past-card landing-report --scorecard "$P3_PLAN"; P3_SCORE="$PAH_OUT"
run_close_as pah-past-close "$P3" run
expect_eq "ONE-14 …close-out delivers at that head with no word from the person (exit 0, no merge-unproved approval)" "0|0" "$CO_RC|$(/usr/bin/grep -c '|ev=approval|key=merge-unproved|' "$P3/$LOG_REL")"
[ "$CO_RC" = 0 ] || printf '      close-out said: %s\n' "$(printf '%s\n' "$CO_OUT" | tail -3)"
expect_eq "ONE-15 …and the card, the scorecard and the continuation print that one state" "one: $P3_WANT" \
  "$(pah_one "$(pah_card_state "$P3_CARD")" "$(pah_score_state "$P3_SCORE")" "$(pah_cont_state "$P3/$CONT_REL")")"
expect_eq "ONE-16 …the card marks it green" "✅ whole suite: $P3_WANT" "$(printf '%s\n' "$P3_CARD" | /usr/bin/grep -F "whole suite: " | head -1)"
expect_absent "ONE-16b …and asks no merge without a pass, on the card whose whole-suite line was read above" "Merge without a whole run at this head" "$P3_CARD"
# fails-when: a release-set commit past F is read green without its check, or red with a passing check at it.
pah_world past-release "" 0
P4_F="$PAH_F"; pah_past CHANGELOG.md,payload/.claude-plugin/plugin.json
expect_eq "ONE-17 (AC-1.2) one release-set commit past F with no check recorded at it: red, the landing counted" "red at ${P4_F:0:8}, 1 landing before this head" "$(pah_whole)"
bash -c '. "$1/run.sh" && . "$1/proof.sh" && LOG_AT=2026-10-04T15:00:00Z proof_event "$2" kind=check "head=$3" evidence=record/wave-01-fixture/release-check.log' _ "$PAH_LIB" "$PAH_PLAN" "$PAH_H"
expect_eq "ONE-17a precondition: the release set's readers are the five suites that read it" "release-check.test.sh shell-lint.test.sh render.test.sh commands.test.sh words.test.sh" "$(bash -c '. "$1/proof.sh" && _proof_release_readers' _ "$PAH_LIB" 2>/dev/null | paste -sd' ' -)"
pah_read() { bash -c '. "$1/line.sh" || exit 1; p="$2" c="$3"; shift 3; for s; do line_event "$p" verdict row=T8 "commit=$c" "suite=$s" result=green log=- admitted=- width=-; done' _ "$PAH_LIB" "$PAH_PLAN" "$PAH_H" "$@"; }  # <suite>... -> a green verdict each at PAH_H
pah_read release-check.test.sh shell-lint.test.sh render.test.sh commands.test.sh
# fails-when: a reader is not asked, so the release commit with its check and one reader unproved reads green.
expect_eq "ONE-17b (AC-1.2) …with its check passing and four of its readers green, words.test.sh unproved: still red" "red at ${P4_F:0:8}, 1 landing before this head" "$(pah_whole)"
pah_read words.test.sh
expect_eq "ONE-18 (AC-1.2) …the same commit with its release check passing and its five readers green at it: green at F" "green at ${P4_F:0:8}, 1 landing since moved no code" "$(pah_whole)"
# fails-when: a commit that moved code past F is read as prose, so the head reads green with no pass at it.
pah_world past-code "" 0
P5="$PAH_P"; P5_F="$PAH_F"; pah_past payload/scripts/x.sh
expect_eq "ONE-19 (AC-1.3) one code commit past F: red at F, one landing before this head" "red at ${P5_F:0:8}, 1 landing before this head" "$(pah_whole)"
( in_fixture "$P5" || exit 1; bound_marker "$P5" pah-code-card "$PAH_PLAN" )
pah_poke "$P5" pah-code-card release-approval --preview "$PAH_PLAN"
expect_contains "ONE-19a …and its card asks the merge without a pass, the red state on the ask" "Merge without a whole run at this head — red at ${P5_F:0:8}, 1 landing before this head" "$(printf '%s\n' "$PAH_OUT" | tr '\n' ' ' | tr -s ' ')"
pah_past README.md
expect_eq "ONE-19b …and a docs commit after it leaves it red, the two landings counted" "red at ${P5_F:0:8}, 2 landings before this head" "$(pah_whole)"
# fails-when: the judge's cover at F is not asked, so a red whole run with one docs commit past it reads green.
pah_world past-red "$PAH_OWED" 0; P6_F="$PAH_F"; pah_past README.md
expect_eq "ONE-19c (REQ-1) a red whole run at F and one docs-only commit past it: red, the landing counted" "red at ${P6_F:0:8}, 1 landing before this head" "$(pah_whole)"
# THE MUTANT: `_facts_basis` reads every commit `owes`. fails-when: the printer greens past F on any other basis.
PAH_MUTLIB="$SANDBOX/mut-lib"; cp -R "$PAH_LIB" "$PAH_MUTLIB"
printf '%s\n' "_facts_basis() { printf 'cover %s owes\\n' \"\$1\"; return 1; }" >> "$PAH_MUTLIB/proof.sh"
PAH_P="$P3"; PAH_PLAN="$P3_PLAN"
expect_eq "ONE-20 precondition: the mutant runs, its walk reading each docs commit owes" "cover owes|cover owes" "$(pah_cover "$PAH_MUTLIB")"
expect_eq "ONE-21 …and under it the docs head reads red, so the walk's basis is what turned it green" "red at ${P3_F:0:8}, 2 landings before this head" "$(pah_whole "$PAH_MUTLIB")"

# ============================================================
section "§LOG: the proof readers answer from the reader's facts, so a proof the run's log alone holds stands"
# ============================================================
# fails-when: facts_state, proof_last or proof_approved_head read the plan's text themselves, so a review
# reading, a regression proof or an approval written only as a run/v1 event reads absent; or a fact read once is
# served after the plan changed under the same process.
PL="$(mk_fixture log)"; advance_to "$PL" 8
PL_PLAN="$PL/$PLAN_REL"; PL_H="$(fixture_git "$PL" rev-parse wave/01-fixture)"; PL_REC="$PL/.bionic/docs/record/wave-01-fixture"
for q in evidence adversarial structure; do
  printf '# %s\n\nNo findings.\n' "$q" > "$PL_REC/critic-$q.md"
  printf 'run/v1|ev=proof|kind=review|head=%s|evidence=record/wave-01-fixture/critic-%s.md|question=%s|reader=w-critic|result=pass|scope=piece|at=2026-10-04T12:00:00Z\n' \
    "$PL_H" "$q" "$q" >> "$PL_REC/run.log"
done
pl_state() { bash -c '. "$1/roots.sh" && . "$1/proof.sh" && facts_state "$2" "$3"' _ "$PAH_LIB" "$PL_PLAN" "$PL_H" 2>/dev/null | awk -F'\t' '$1 == "review" && $4 == "piece" { printf "%s%s=%s", (n++ ? " " : ""), $2, $5 }'; }
expect_eq "LOG-1 precondition: the three readings in the run's log are each covered at the head" \
  "evidence=covered adversarial=covered structure=covered" "$(pl_state)"
printf 'run/v1|ev=proof|kind=regression|head=%s|evidence=record/wave-01-fixture/regression-run.log|at=2026-10-04T12:30:00Z\n' "$PL_H" >> "$PL_REC/run.log"
printf 'run/v1|ev=approval|key=merge-unproved|by=fixture|head=%s|said=merge it|at=2026-10-04T12:40:00Z\n' "$PL_H" >> "$PL_REC/run.log"
expect_eq "LOG-2 precondition: the plan holds no adversarial reading and the log holds it as an event" "0|yes" \
  "$(/usr/bin/grep -c 'question=adversarial' "$PL_PLAN")|$(awk 'index($0, "|ev=proof|") && index($0, "|question=adversarial|") { f = 1 } END { print (f ? "yes" : "no") }' "$PL_REC/run.log")"
expect_eq "LOG-3 a review reading the log alone holds is covered, as the other two are" \
  "evidence=covered adversarial=covered structure=covered" "$(pl_state)"
expect_eq "LOG-4 …the regression proof and the person's word the log alone holds are read at their head" "$PL_H|$PL_H" \
  "$(bash -c '. "$1/proof.sh" && printf "%s|%s" "$(proof_last "$2" regression)" "$(proof_approved_head "$2" merge-unproved)"' _ "$PAH_LIB" "$PL_PLAN")"
# fails-when: the facts are kept for the process past a change, so a proof written between two reads is not seen.
expect_eq "LOG-5 a proof written between two reads in one process is read by the second" "$PL_H|0000000000000000000000000000000000000001" \
  "$(bash -c '. "$1/proof.sh" || exit 1; a="$(proof_last "$2" task)"; a="$(proof_last "$2" regression)"
    printf "run/v1|ev=proof|kind=regression|head=%s|evidence=x|at=2026-10-04T13:00:00Z\n" 0000000000000000000000000000000000000001 >> "$3"
    printf "%s|%s" "$a" "$(proof_last "$2" regression)"' _ "$PAH_LIB" "$PL_PLAN" "$PL_REC/run.log")"

# fails-when: a suite proof-add inherited writes to the log is owed again; or two suites inherited at one head read as one.
for s in b c; do printf 'run/v1|ev=proof|kind=inherited|head=%s|evidence=record/wave-01-fixture/i-%s.log|suite=%s.test.sh|base=%s|at=2026-10-04T13:2%s:00Z\n' "$PL_H" "$s" "$s" "$PL_H" "${#s}" >> "$PL_REC/run.log"; done
expect_eq "LOG-6 two suites the log inherits at one head are two debts, each read once" \
  "b.test.sh,c.test.sh|2" \
  "$(bash -c '. "$1/proof.sh" && printf "%s|%s" "$(proof_inherited "$2")" "$(proof_inherited_lines "$2" | grep -c "^inherited: ")"' _ "$PAH_LIB" "$PL_PLAN")"
# fails-when: the base is read from a base-sha: line in the page's body, and not from the header.
PL_B="$(sed -n 's/^base-sha: //p' "$PL_PLAN")"; printf '\n## Notes\n\n  base-sha: %s\n' "$PL_H" >> "$PL_PLAN"
expect_eq "LOG-7 the base is the header's, a commit other than the one a line of the body names" "$PL_B|$PL_H|yes" \
  "$(bash -c '. "$1/proof.sh" && proof_plan_base "$2" "$3"' _ "$PAH_LIB" "$PL_PLAN" "$PL")|$(sed -n 's/^  base-sha: //p' "$PL_PLAN")|$([ -n "$PL_B" ] && [ "$PL_B" != "$PL_H" ] && echo yes)"

section "§KEEP: the kept fold is served only from a directory this user alone can write, and its files are bounded"
# fails-when: a fold planted under the right key is served from a directory others can write or through a link, the user's own fold is not served to a second process, or a file per plan is kept for ever, or a failed fold, or a kept file pruned between two reads, is kept as the run's facts; or a fold that failed reaches the judge or a reader of it as no proof, or a lookup that died as a whole run.
pk() { TMPDIR="$PK/$1" bash -c '. "$1/proof.sh" && proof_approved_head "$2" release' _ "$PAH_LIB" "$PL_PLAN"; }  # <dir> -> a fresh process's `release` approval head, TMPDIR $PK/<dir>
PK="$SANDBOX/keep"; PK_D="bionic-facts-$(id -u)"; mkdir -p "$PK/ok" "$PK/open/$PK_D" "$PK/away" "$PK/link" "$PK/full/$PK_D"; pk ok; PK_F="$(ls "$PK/ok/$PK_D")"; awk -v l="$(printf 'run/v1|ev=approval|key=release|by=intruder|head=%s|said=x|at=2026-10-04T14:00:00Z' "$PL_H")" '$0 == "\036" && !d { print l; d = 1 } { print }' "$PK/ok/$PK_D/$PK_F" > "$PK/ok.f" && cat "$PK/ok.f" > "$PK/ok/$PK_D/$PK_F"
cp "$PK/ok/$PK_D/$PK_F" "$PK/open/$PK_D/"; chmod 777 "$PK/open/$PK_D"; cp -R "$PK/ok/$PK_D" "$PK/away/"; ln -s "$PK/away/$PK_D" "$PK/link/$PK_D"; for i in $(seq 40); do : > "$PK/full/$PK_D/$i"; done; touch -t 202601010000 "$PK/full/$PK_D"/*; chmod 700 "$PK/full/$PK_D"; pk full
expect_eq "KEEP-1 the user's own kept fold (mode 700) is served to a second process, the approval planted in it read" "drwx------|$PL_H" "$(ls -ld "$PK/ok/$PK_D" | cut -c1-10)|$(pk ok)"
expect_eq "KEEP-2 the same file is served neither from a directory others can write nor through a link to the user's own, each left as planted" "||1|1" "$(pk open)|$(pk link)|$(grep -c intruder "$PK/open/$PK_D/$PK_F")|$(grep -c intruder "$PK/away/$PK_D/$PK_F")"
expect_eq "KEEP-3 a fold written beside forty older files leaves the sixteen newest, its own the newest" "16|$PK_F" "$(ls "$PK/full/$PK_D" | wc -l | tr -d ' ')|$(ls -t "$PK/full/$PK_D" | head -1)"
pf() { rm -rf "$PK/f"; mkdir -p "$PK/f"; TMPDIR="$PK/f" bash -c '. "$1/proof.sh" && _proof_reader_load || exit 1; fn="$5" pp="$3" px="$4"; eval "$(declare -f $fn | sed 1s/$fn/pf_real/)"; eval "$fn() { printf \"\$pp\"; return \$px; }"; _proof_facts "$2" > "$TMPDIR/o" 2> "$TMPDIR/e"; rc=$?; eval "$fn() { pf_real \"\$@\"; }"
  printf "%s|%s|%s|%s|%s|%s" $rc "$(wc -l < "$TMPDIR/o")" "${_PROOF_FACTS_KEY:+key}" "$(ls "$TMPDIR"/bionic-facts-* | wc -l)" "$(grep -cF "$2" "$TMPDIR/e")" "$(proof_last "$2" regression)" | tr -d " "' _ "$PAH_LIB" "${PF_PLAN:-$PL_PLAN}" "$2" "$3" "$1"; }  # <reader function stood in> <what it prints> <its exit> -> exit|lines served|key|files kept|stderr lines naming the plan|the next ask's newest regression head
PL_R=0000000000000000000000000000000000000001; expect_eq "KEEP-4 a fold that fails, short or empty or with a stage of its pipeline killed, is an error naming the plan, is kept nowhere, and the next ask folds the whole" "2|0||0|1|$PL_R~2|0||0|1|$PL_R~2|0||0|1|$PL_R" "$(pf reader_facts 'run/v1|ev=x\n' 1)~$(pf reader_facts '' 1)~$(pf reader_events 'run/v1|ev=x\n' 128)"
expect_eq "KEEP-5 an empty fold that succeeds is a run with no fact, and is kept" "0|0|key|1|0|" "$(pf reader_facts '' 0)"
pk race; expect_eq "KEEP-6 a kept file pruned after its first read is served whole, never as an empty fold" "$PL_R" "$(TMPDIR="$PK/race" bash -c '. "$1/proof.sh" || exit 1; for c in head sed cat; do eval "$c() { command $c \"\$@\"; rm -f \"\$TMPDIR\"/bionic-facts-*/*; }"; done; proof_last "$2" regression' _ "$PAH_LIB" "$PL_PLAN")"
pg() { rm -rf "$PK/g"; mkdir -p "$PK/g"; TMPDIR="$PK/g" bash -c '. "$1/roots.sh" && . "$1/proof.sh" && _proof_reader_load || exit 1; [ "$4" = whole ] || reader_facts() { return 1; }; p="$2" h="$3"; eval "$5"' _ "$PAH_LIB" "$PL_PLAN" "$PL_H" "$@" 2>/dev/null; }  # <whole|failing> <script over $p and $h> -> its output in a fresh process and TMPDIR, the reader whole or failing
PG_J='o="$(facts_state "$p" "$h")"; printf "%s|%s" $? "$(printf "%s" "$o" | grep -c "^review")"'; expect_eq "KEEP-7 with the reader failing the judge exits 2 and prints no chain, where whole it prints every chain" "2|0~0|5" "$(pg failing "$PG_J")~$(pg whole "$PG_J")"
PG_5='{ proof_approved_head "$p" merge-unproved; a=$?; _proof_floor_match "$p" "$p" "" "$h" 0; b=$?; proof_chain_head "$p" structure; c=$?; proof_last "$p" regression; d=$?; _facts_check_at "$p" "$h" "$h"; } >/dev/null; printf "%s|%s|%s|%s|%s" $a $b $c $d $?'; expect_eq "KEEP-8 …and each of the other five readers of the fold hands the failure back, exit 2, where whole it answers" "2|2|2|2|2~0|1|0|0|0" "$(pg failing "$PG_5")~$(pg whole "$PG_5")"
expect_eq "KEEP-9 a lookup of the run log that dies is a failed fold, never a run with no log" "2|0||0|1|$PL_R" "$(pf reader_record '' 128)"

section "§FOLD: a caller of the fold hears it fail: what writes from the facts writes nothing and exits 2, what shows them says they could not be read"
# fails-when: a reader question asked in-process, close-out's continuation, the release card, a waiver, the bound line,
# the tick's words, the hand-holds count or a checked ask reads a fold that failed as a run with no fact.
# The stand-in is a copy of hooks/ and payload/scripts/ whose reader_facts exits 128, a refused fork's exit, inside any
# function PAH_IN names, and folds whole elsewhere; each row reads the failing call beside the whole one.
PF_ST="$SANDBOX/stand"; mkdir -p "$PF_ST/payload"; cp -R "$BIONIC_HOOKS_DIR" "$PF_ST/hooks"; cp -R "$REPO_ROOT/payload/scripts" "$PF_ST/payload/scripts"; ln -s ../hooks "$PF_ST/payload/hooks"
printf '%s\n' 'eval "pf_whole_$(declare -f reader_facts)"; reader_facts() { case " ${FUNCNAME[*]} " in *" ${PAH_IN:-} "*) return 128 ;; esac; pf_whole_reader_facts "$@"; }' >> "$PF_ST/payload/scripts/lib/reader.sh"
pfu() { printf '%s|%s' "$1" "$(printf '%s\n' "$2" | grep -c "$3")|$(printf '%s\n' "$2" | grep -c 'could not be read')"; }  # <exit> <output> <its fact's pattern> -> exit|fact lines|could-not-read lines
PF_RS='. "$1/run.sh"; o="$(run_step "$2")"; printf "%s|%s" $? "$o" | tr "\n" " "'
expect_eq "FOLD-1 a reader question run in-process (run_step) hands back the fold's failure; whole, its step and 0" "128|n=0 state=open~0|n=8 state=open" \
  "$(PAH_IN=reader_facts bash -c "$PF_RS" _ "$PF_ST/payload/scripts/lib" "$PL_PLAN")~$(bash -c "$PF_RS" _ "$PF_ST/payload/scripts/lib" "$PL_PLAN")"
pf_tmp() { mkdir -p "$SANDBOX/t-$1/bionic-facts-$(id -u)"; chmod 777 "$SANDBOX/t-$1/bionic-facts-$(id -u)"; printf '%s' "$SANDBOX/t-$1"; }  # <label> -> a TMPDIR where no fold is kept, so each read folds
pf_close() { local p; p="$(mk_fixture "fold-$1")"; advance_to "$p" 8; debt_plant "$p"
  SCRIPT="$PF_ST/payload/scripts/close-out.sh" TMPDIR="$(pf_tmp "$1")" PAH_IN="$2" run_close_as "pf-$1" "$p" run; pfu "$CO_RC" "$CO_OUT$(cat "$p/$CONT_REL" 2>/dev/null)" '^debt: tree_count '; }  # <label> <function the fold fails in> -> close-out's exit|debt lines|could-not-read lines
expect_eq "FOLD-2 a fold that fails as close-out writes the continuation writes none and refuses, exit 2; whole, the debt carried" "2|0|1~0|1|0" "$(pf_close c act_continuation)~$(pf_close w none)"
pah_world fold "" 0; ( in_fixture "$PAH_P" || exit 1; bound_marker "$PAH_P" pah-fold "$PAH_PLAN" ); fixture_git "$PAH_P" config user.name fixture
PF_POKE() { TMPDIR="$(pf_tmp "p$RANDOM")" PAH_POKER="$PF_ST/hooks/session-poker.sh" PAH_IN="$1" pah_poke "$PAH_P" pah-fold "${@:2}"; pfu "$PAH_RC" "$PAH_OUT" "$PF_PAT"; }  # <function the fold fails in> <verb…> -> exit|lines of PF_PAT|could-not-read lines
PF_PAT='whole suite: '; expect_eq "FOLD-3 the release card over a fold that fails is not drawn, exit 2; whole, drawn" "2|0|1~0|1|0" "$(PF_POKE poker_verb_release_approval release-approval --preview "$PAH_PLAN")~$(PF_POKE none release-approval --preview "$PAH_PLAN")"
PF_PAT='^hand-holds: total='; expect_eq "FOLD-4 the hand-holds count over a fold that fails says it could not be read; whole, its total" "0|0|1~0|1|0" "$(PF_POKE reader_facts landing-report --hand-holds "$PAH_PLAN")~$(PF_POKE none landing-report --hand-holds "$PAH_PLAN")"
# The person typed the waiver's words in this session: its transcript under a config of this check's own, at the fixture's
# project name, and its load record there, the two witnesses the waive verb holds a waiver's words to (lib/said.sh).
PF_TX="$SANDBOX/pf-cfg/projects/$(bash -c '. "$1/detect.sh" >/dev/null 2>&1; project_slug "$2"' _ "$REPO_ROOT/payload/scripts/lib" "$(cd "$PAH_P" && pwd -P)")"; mkdir -p "$PF_TX" "$PAH_P/.bionic/tmp"
jq -c '.message.content = "waive it, the person said"' "$REPO_ROOT/tests/fixtures/transcript-move/typed.jsonl" > "$PF_TX/pah-fold.jsonl"; : > "$PAH_P/.bionic/tmp/loaded-pah-fold.state"
PF_PAT='question=structure head='; expect_eq "FOLD-5 a waiver over a fold that fails is refused, nothing written; whole, its event is written to the run's log" "2|0|1~0|1|0" "$(CLAUDE_CONFIG_DIR="$SANDBOX/pf-cfg" PF_POKE reader_facts waive structure 'waive it, the person said')~$(CLAUDE_CONFIG_DIR="$SANDBOX/pf-cfg" PF_POKE none waive structure 'waive it, the person said')"
PF_SS="$(sed -n '/^SS_FACTS_PLAN=/p;/^ss_ask() {/,/^}/p;/^print_bound_line() {/,/^}/p' "$BIONIC_HOOKS_DIR/session-start.sh")"
PF_B='BIONIC_LIB="$1"; DOCS=""; HOOK_ROOT=x; eval "$2"; print_bound_line "bound-open $3"'
PF_PAT='current: 8$'; expect_eq "FOLD-6 the bound line over a fold that fails says the facts could not be read where the step stands; whole, the step" "0|0|1~0|1|0" \
  "$(pfu 0 "$(PAH_IN=reader_facts bash -c "$PF_B" _ "$PF_ST/payload/scripts/lib" "$PF_SS" "$PL_PLAN")" "$PF_PAT")~$(pfu 0 "$(bash -c "$PF_B" _ "$PF_ST/payload/scripts/lib" "$PF_SS" "$PL_PLAN")" "$PF_PAT")"
PG_U='. "$1/units.sh"; _units_readings_state "$p"'; expect_eq "FOLD-7 the tick's words for the reviews over a fold that fails say it did not fold, not rigor and scale" \
  "the run's facts could not be read: its facts did not fold; ask again~covered" "$(pg failing "$PG_U")~$(pg whole "$PG_U")"

section "§IFS: the library splits its own lists, whatever separators its caller set"
# fails-when: the fold's key splits its lists of libraries and homes on the caller's IFS, so under a tab it covers the
# plan alone and a fold kept before the run's log gained a proof is served after it.
expect_eq "IFS-1 under a tab as the caller's only separator, the second ask reads the proof the log gained after the first" \
  "0000000000000000000000000000000000000001|0000000000000000000000000000000000000002" \
  "$(bash -c '. "$1/proof.sh" || exit 1; IFS=$'"'"'\t'"'"'; a="$(proof_last "$2" regression)"
    printf "run/v1|ev=proof|kind=regression|head=%s|evidence=x|at=2026-10-04T13:10:00Z\n" 0000000000000000000000000000000000000002 >> "$3"
    printf "%s|%s" "$a" "$(proof_last "$2" regression)"' _ "$PAH_LIB" "$PL_PLAN" "$PL_REC/run.log")"
# fails-when: a rating or a run's verdict is split on the caller's IFS, so under a tab the finding drops out unrated and
# a green run's verdict is refused as cut off.
printf '## SDLC State\n\ndeferred: record/r.md#1 S2 off "a title"\n' > "$SANDBOX/ifs-plan.md"
printf 'head=%s dirty=0\nGating: 3 passed, 0 failed\n' "$PL_H" > "$SANDBOX/ifs-run.log"
ifs_read() { bash -c '. "$1/proof.sh" || exit 1; IFS="$2"; printf "%s|%s" "$(proof_findings_owed "$3")" "$(proof_attested task "$4" "$5" "" "" "" "$6")"' \
  _ "$PAH_LIB" "$1" "$SANDBOX/ifs-plan.md" "$SANDBOX/ifs-run.log" "$PL" "$PL_H"; }  # <IFS> -> the finding's rated line|the head the run attests
expect_eq "IFS-2 precondition: under the default separators the deferred finding reads rated and the green run attests the head" \
  "record/r.md#1 S2 off defer \"a title\"|$PL_H" "$(ifs_read $' \t\n')"
expect_eq "IFS-3 under a tab as the only separator the rating and the verdict read as they do under the default" "$(ifs_read $' \t\n')" "$(ifs_read $'\t')"

finish
