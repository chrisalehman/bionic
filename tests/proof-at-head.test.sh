#!/bin/bash
# tests/proof-at-head.test.sh — THE FULL PASS'S STATE, PRINTED ONCE: payload/scripts/lib/proof.sh `proof_whole_text`.
#
# WHAT IT HOLDS. Green means the full suite ran green at this head. A whole run behind the head, whose reds later
# landings' own suites greened, is what the floor judge reads as covered; it is still red at this head, with the
# landings since it counted. Every surface that states the full pass prints it from the one printer over the judge:
# the release card's `whole suite:` line, the scorecard's correctness line (`landing-report --scorecard`, which the
# continuation also carries under ## Scorecard) and close-out's continuation header. The miss this suite was opened on:
# over one red whole run the card read covered, the scorecard read green and the continuation read holds.
#
# §ONE   over one plan and record, a red whole run at F with four suites owed and two landings past it that green
#        them, the card, the scorecard and the continuation print the same state, `red at <F8>, 2 landings before
#        this head`; a copy of close-out that prints green for that run splits them, and the check says so
#
# FIXTURE FIDELITY. The project is close-out's own (tests/close-out.prelude.sh): a git project at Step 8 with its
# working branch checked out beside it and every fact the run owes planted by the product's line builders. On it,
# `pah_world` lays the run the record shows: the regression proof as `proof-add regression` writes it
# (`proof_floor_line`, `owed=` the runner's red suites), then each landing as the line records it, a `ready` naming
# the row's suites, a green verdict of each at the landed commit and the `published` event, and the readings at the
# head the landings reach. The three surfaces are the real verbs: `release-approval --preview`, `landing-report
# --scorecard` and `close-out.sh run`.
#
# ANTI-VACUITY. Each surface's state is read through its own extractor, and each extractor is shown non-empty on the
# surface it reads before the states are compared. The split arm runs a mutated copy of close-out.sh and proves the
# copy ran, its continuation written and its line read green, before the check is read to split.
#
# Usage: bash tests/proof-at-head.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/regression-fixture.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/close-out.prelude.sh"

PAH_LIB="$REPO_ROOT/payload/scripts/lib"
PAH_POKER="${BIONIC_HOOKS_DIR}/session-poker.sh"

# pah_world <label> <owed suites, comma-joined, or empty> <landings> -> PAH_P (the project), PAH_PLAN, PAH_F (the
# whole run's head) and PAH_H (the working head). The close-out fixture at Step 8, its regression proof replaced by
# a whole run at F that left <owed> red, then <landings> landing commits on the working branch, landing k greening
# the owed suites at the positions k, k + <landings>, …; with landings the integration branch takes the working
# branch, as the merge before close-out does, the readings move to the working head, and the plan carries the
# person's word to merge with no pass at it (`approved: merge-unproved … head=<H>`), which close-out's judge needs.
pah_world() {
  local label="$1" owed="$2" n="${3:-0}" p plan w rec k i s su c
  p="$(mk_fixture "$label")" || return 1
  advance_to "$p" 8
  plan="$p/$PLAN_REL"; w="$p-wave"; rec="$p/.bionic/docs/record/wave-01-fixture/landing-proofs.log"
  PAH_F="$(fixture_git "$p" rev-parse wave/01-fixture)"
  sed '/^proved: kind=regression /d' "$plan" > "$plan.n" && mv "$plan.n" "$plan"
  bash -c '. "$1/proof.sh" || exit 1
    proof_add_line "$2" "$(proof_floor_line "$3" 2026-10-04T12:00:00Z "record/wave-01-fixture/regression-run-$3.log" "$4")"' \
    _ "$PAH_LIB" "$plan" "$PAH_F" "$owed" > "$plan.n" && mv "$plan.n" "$plan"
  mkdir -p "${rec%/*}"
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
      printf 'line/v1|ev=ready|row=T%d|name=w-T%d|commit=%s|branch=wt/01-T%d|tree=%s|suites=%s|debt=-|carrier=1:x|at=2026-10-04T13:%02d:00Z\n' \
        "$((k + 2))" "$((k + 2))" "$c" "$((k + 2))" "$w" "${su:-a.test.sh}" "$((k * 10))"
      for s in ${su//,/ }; do
        printf 'line/v1|ev=verdict|row=T%d|commit=%s|suite=%s|result=green|log=/rec/T%d-%s.log|at=2026-10-04T13:%02d:30Z\n' \
          "$((k + 2))" "$c" "$s" "$((k + 2))" "$s" "$((k * 10))"
      done
      printf 'line/v1|ev=published|row=T%d|commit=%s|kind=queue|by=-|why=-|at=2026-10-04T13:%02d:50Z\n' "$((k + 2))" "$c" "$((k * 10))"
      printf 'landed: row=T%d branch=wt/01-T%d head=%s merge=%s at=2026-10-04T13:%02d:50Z\n' "$((k + 2))" "$((k + 2))" "$c" "$c" "$((k * 10))"
    } >> "$rec"
    k=$((k + 1))
  done
  PAH_H="$(fixture_git "$p" rev-parse wave/01-fixture)"
  if [ "$n" -gt 0 ]; then
    fixture_git "$p" merge -q --no-ff -m "merge wave" wave/01-fixture >/dev/null 2>&1 || return 1
    # The landings cover the head and no pass ran at it, so the merge close-out delivers is the person's word at H.
    awk -v f="$PAH_F" -v h="$PAH_H" '/^proved: kind=review / { sub("head=" f, "head=" h) } { print }
      /^current: / { print "approved: merge-unproved by fixture 2026-10-04T14:00:00Z head=" h " \"merge it\"" }' "$plan" > "$plan.n" \
      && mv "$plan.n" "$plan"
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
# pah_one <card state> <scorecard state> <continuation state> -> `one: <state>` when the three agree, else
# `split: card=<…>; scorecard=<…>; continuation=<…>`.
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


# THE PAST-F ARMS: a green whole run at F, then commits past it on the working branch. Green is content: a head whose
# every commit since F moved no code, by the judge's own cover basis (prose or release), reads green and names F;
# one commit that moved code keeps the red line, F and the landings since counted.
# pah_past <spec>... -> PAH_H: one commit on the working branch past the world `pah_world` built for each <spec>, the
# paths it touches comma-joined, then the integration branch takes the working branch, as the merge before close-out.
pah_past() {
  local spec f
  for spec in "$@"; do
    for f in ${spec//,/ }; do
      mkdir -p "$(dirname "$PAH_P-wave/$f")"; printf 'past F: %s\n' "$spec" >> "$PAH_P-wave/$f"
      fixture_git "$PAH_P-wave" add "$f" || return 1
    done
    fixture_git "$PAH_P-wave" commit -qm "past F: $spec" || return 1
  done
  PAH_H="$(fixture_git "$PAH_P" rev-parse wave/01-fixture)"
  fixture_git "$PAH_P" merge -q --no-ff -m "merge wave" wave/01-fixture >/dev/null 2>&1
}
# pah_whole [<lib dir>] -> the printer's line at the working head, from the real lib or from <lib dir>'s copy.
pah_whole() {
  bash -c '. "$1/roots.sh" && . "$1/proof.sh" && proof_whole_text "$2" "$3"' _ "${1:-$PAH_LIB}" "$PAH_PLAN" "$PAH_P" 2>/dev/null
}
# pah_check <commit> -> the plan carries a passing release check at <commit>, the line `release-check` writes.
pah_check() {
  bash -c '. "$1/proof.sh" || exit 1
    proof_add_line "$2" "$(proof_line check "$3" 2026-10-04T15:00:00Z record/wave-01-fixture/release-check.log)"' \
    _ "$PAH_LIB" "$PAH_PLAN" "$1" > "$PAH_PLAN.n" && mv "$PAH_PLAN.n" "$PAH_PLAN"
}

# fails-when: the printer reads green only at F itself, so a head two docs-only commits past a green whole run reads
# red, the card asks the merge without a pass and close-out refuses for the regression; or one surface words its own.
pah_world past-docs "" 0
P3="$PAH_P"; P3_F="$PAH_F"
expect_eq "ONE-11 precondition: a green whole run at the working head reads green at it" "green at ${P3_F:0:8}" "$(pah_whole)"
pah_past README.md docs/notes.md
P3_PLAN="$PAH_PLAN"; P3_H="$PAH_H"
expect_eq "ONE-12 precondition: the head is two first-parent commits past F, each prose by the judge's walk" \
  "2|cover prose|cover prose" \
  "$(fixture_git "$P3" rev-list --first-parent --count "$P3_F..$P3_H")|$(bash -c '. "$1/roots.sh" && . "$1/proof.sh" && facts_cover "$2" "$3" "$4"' _ "$PAH_LIB" "$P3_PLAN" "$P3_F" "$P3_H" 2>/dev/null | awk '{ printf "%s%s %s", (NR > 1 ? "|" : ""), $1, $3 }')"
P3_WANT="green at ${P3_F:0:8}, 2 landings since moved no code"
expect_eq "ONE-13 (AC-1.1) two docs-only commits past a green whole run: the state reads green at F, the landings since counted" \
  "$P3_WANT" "$(pah_whole)"
( in_fixture "$P3" || exit 1; bound_marker "$P3" pah-past-card "$P3_PLAN" )
pah_poke "$P3" pah-past-card release-approval --preview "$P3_PLAN"
P3_CARD="$PAH_OUT"
pah_poke "$P3" pah-past-card landing-report --scorecard "$P3_PLAN"
P3_SCORE="$PAH_OUT"
run_close_as pah-past-close "$P3" run
expect_eq "ONE-14 …close-out delivers at that head with no word from the person (exit 0, no merge-unproved line)" "0|0" \
  "$CO_RC|$(/usr/bin/grep -c '^approved: merge-unproved ' "$P3_PLAN")"
[ "$CO_RC" = 0 ] || printf '      close-out said: %s\n' "$(printf '%s\n' "$CO_OUT" | tail -3)"
expect_eq "ONE-15 …and the card, the scorecard and the continuation print that one state" "one: $P3_WANT" \
  "$(pah_one "$(pah_card_state "$P3_CARD")" "$(pah_score_state "$P3_SCORE")" "$(pah_cont_state "$P3/$CONT_REL")")"
expect_eq "ONE-16 …the card marks it green" "✅ whole suite: $P3_WANT" \
  "$(printf '%s\n' "$P3_CARD" | /usr/bin/grep -F "whole suite: " | head -1)"
expect_absent "ONE-16b …and asks no merge without a pass, on the card whose whole-suite line was read above" \
  "Merge without a whole run at this head" "$P3_CARD"

# fails-when: a release-set commit past F is read green without its check, or red with a passing check at it.
pah_world past-release "" 0
P4="$PAH_P"; P4_F="$PAH_F"
pah_past CHANGELOG.md,payload/.claude-plugin/plugin.json
P4_H="$PAH_H"
expect_eq "ONE-17 (AC-1.2) one release-set commit past F with no check recorded at it: red, the landing counted" \
  "red at ${P4_F:0:8}, 1 landing before this head" "$(pah_whole)"
pah_check "$P4_H"
expect_eq "ONE-18 (AC-1.2) …the same commit with a passing release check recorded at it: green at F" \
  "green at ${P4_F:0:8}, 1 landing since moved no code" "$(pah_whole)"

# fails-when: a commit that moved code past F is read as prose, so the head reads green with no pass at it.
pah_world past-code "" 0
P5="$PAH_P"; P5_F="$PAH_F"
pah_past payload/scripts/x.sh
expect_eq "ONE-19 (AC-1.3) one code commit past F: red at F, one landing before this head" \
  "red at ${P5_F:0:8}, 1 landing before this head" "$(pah_whole)"
( in_fixture "$P5" || exit 1; bound_marker "$P5" pah-code-card "$PAH_PLAN" )
pah_poke "$P5" pah-code-card release-approval --preview "$PAH_PLAN"
expect_contains "ONE-19a …and its card asks the merge without a pass, the red state on the ask" \
  "Merge without a whole run at this head — red at ${P5_F:0:8}, 1 landing before this head" "$(printf '%s\n' "$PAH_OUT" | tr '\n' ' ' | tr -s ' ')"
pah_past README.md
expect_eq "ONE-19b …and a docs commit after it leaves it red, the two landings counted" \
  "red at ${P5_F:0:8}, 2 landings before this head" "$(pah_whole)"

# THE MUTANT: the docs head of ONE-13 with the judge's basis (`_facts_basis`) made to read every commit `owes`. fails-when: the printer
# turns green past F on anything but the walk's basis (position, or a basis of its own), so the mutant still reads green.
PAH_MUTLIB="$SANDBOX/mut-lib"
cp -R "$PAH_LIB" "$PAH_MUTLIB"
cat >> "$PAH_MUTLIB/proof.sh" <<'PAH_MUT_EOF'
_facts_basis() { printf 'cover %s owes\n' "$1"; return 1; }
PAH_MUT_EOF
PAH_P="$P3"; PAH_PLAN="$P3_PLAN"
expect_eq "ONE-20 precondition: the mutant runs, its walk reading each docs commit owes" "cover owes|cover owes" \
  "$(bash -c '. "$1/roots.sh" && . "$1/proof.sh" && facts_cover "$2" "$3" "$4"' _ "$PAH_MUTLIB" "$P3_PLAN" "$P3_F" "$P3_H" 2>"$SANDBOX/mut.err" | awk '{ printf "%s%s %s", (NR > 1 ? "|" : ""), $1, $3 }')"
[ ! -s "$SANDBOX/mut.err" ] || printf '      the mutant said: %s\n' "$(head -3 "$SANDBOX/mut.err")"
expect_eq "ONE-21 …and under it the docs head reads red, so the walk's basis is what turned it green" \
  "red at ${P3_F:0:8}, 2 landings before this head" "$(pah_whole "$PAH_MUTLIB")"

finish
