#!/bin/bash
# tests/decision-skill.test.sh — the decision skill's text, pinned (wave-33 REQ-11; wave-29 folded;
# wave-34 REQ-12 and REQ-13).
#
# WHAT THIS SUITE OWNS. `skills/decision/SKILL.md` carries one fixed shape for a decision put to
# the user: four bold labels in order (Goal, Options, Recommendation, Significance), a numbered
# Options list, and one reply line last. The labels and the reply line are an INTERFACE: a script
# can read decisions back out of the transcripts by them, so they are fixed strings, and this suite
# is what fixes them (AC-11.6). Nothing runs at decision time; the shape is held here, in the text.
#
# EVERY CHECK IS A PREDICATE OVER A FILE. The shipped skill must pass each one, and §PIN hands the
# same predicates doctored copies — a renamed label, a dropped altitude clause, text after the reply
# line, a forbidden word — each of which must fail. A predicate that a doctored copy passes is not
# pinning anything, so the doctored half is what proves the shipped half means something.
#
# §SHAPE AC-11.1 (its rows 1-2 with §PIN 12-13 are AC-12.4's §LABELS) · §FORMS AC-11.4 · §REPLY
# AC-11.5 · §PIN AC-11.6 · §SIZE AC-11.7, AC-12.4 · §CORE the core rule's static half (AC-11.2's live
# half is another row's) · §NUMBER AC-12.1 · §GOAL AC-12.2 · §BATCH AC-12.3 · §ALTITUDE AC-13.1 ·
# §EXAMPLES AC-13.2 (AC-13.3's live half is another row's) · §CLIMB wave-35 AC-10.1 (AC-10.2's live
# half is the T24 record's headless session). Static: reads files, runs nothing.
#
# WHY A TEXT PIN HERE, against the house rule that pinning text is a bad test. The labels and the
# reply line are not prose: they are the strings a transcript reader keys on (ADR-048 item 3), so
# their exact spelling IS the behaviour. Everything else is pinned as a relation over spans (a
# label set in order, a list shape, a phrase per clause), never as a byte image of the file.
#
# FIXTURE FIDELITY (see .claude/rules/test-harness.md, "Fixture fidelity"). The subject is the
# shipped skill file itself, read in place; no fixture stands in for it. The doctored copies in
# §PIN are SYNTHESIZED from it by one sed or awk edit each, and each proves its plant landed.
#
# ANTI-VACUITY (same file, "Anti-vacuity"). The layout extractor is proved non-empty on the real
# file (0b) before any predicate reads it. Each negative sits beside a positive on the same file:
# the never-form check beside 8b, the forbidden-word check inside words_ok beside its `forms` hit,
# the no-person check beside 22a, and each doctored failure beside its plant-landed row and an
# `anchor` that proves the edited line existed exactly once.
#
# Usage: bash tests/decision-skill.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
SKILL="${REPO}/skills/decision/SKILL.md"
CORE="${REPO}/skills/canonical-sdlc/SKILL.md"
STEP2="${REPO}/skills/canonical-sdlc/steps/2.md"
CORE_TMPL="${REPO}/agents-src/templates/skills/canonical-sdlc/SKILL.md.tmpl"
STEP2_TMPL="${REPO}/agents-src/templates/skills/canonical-sdlc/steps/2.md.tmpl"
HEADING='**D<n> · Step <s>**'
KINDS='How a rule is enforced|How a shared resource is shared|What a wave builds'
# The skill's size cap (AC-12.4): raised from 5,000 bytes to carry the three worked pairs.
SIZE_CAP=10000
REPLY_LINE='Reply 1, 2 or 3 · or matrix, diagram, page'
LABELS='Goal Options Recommendation Significance'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── extractors and predicates ────────────────────────────────────────────────

# layout <file> -> the body of the file's first ```text fence: the shape, as the skill shows it.
layout() {
  awk '/^```text$/ { f = 1; next } f && /^```$/ { exit } f { print }' "$1"
}

# layout_labels <file> -> the bold, colon-terminated labels that open the layout's lines, in order.
layout_labels() {
  layout "$1" | sed -nE 's/^\*\*([A-Za-z ]+):\*\*.*/\1/p' | tr '\n' ' ' | sed 's/ $//'
}

# labels_ok <file> — exactly the four labels, in order, and no separate rationale part anywhere.
labels_ok() {
  [ "$(layout_labels "$1")" = "$LABELS" ] || return 1
  ! grep -qiE '\*\*Rationale' "$1"
}

# options_ok <file> — Options is a numbered list of two or more, and exactly one blank line
# separates the last option from Recommendation.
options_ok() {
  layout "$1" | awk '
    /^\*\*Options:\*\*/ { inopt = 1; next }
    inopt && /^\*\*Recommendation:\*\*/ { done = 1; exit }
    inopt && /^[0-9]+\. / { n++; blanks = 0; last = "opt"; next }
    inopt && /^$/ { blanks++; next }
    inopt { bad = 1 }
    END { exit !(done && !bad && n >= 2 && last == "opt" && blanks == 1) }'
}

# recommendation_ok <file> — Recommendation opens on an option number, and the shape answers the
# other options; Significance names downstream, compounding and reversal.
recommendation_ok() {
  local l
  l="$(layout "$1")"
  grep -qE '^\*\*Recommendation:\*\* Option [0-9]' <<<"$l" || return 1
  grep -E '^\*\*Recommendation:\*\*' <<<"$l" | grep -qE 'Not [0-9]' || return 1
  grep -E '^\*\*Significance:\*\*' <<<"$l" | grep -q 'downstream' || return 1
  grep -E '^\*\*Significance:\*\*' <<<"$l" | grep -q 'compounds' || return 1
  grep -E '^\*\*Significance:\*\*' <<<"$l" | grep -q 'reverse'
}

# altitude_ok <file> — the five altitude clauses in the latest wording, and not the older one.
altitude_ok() {
  grep -qi 'plain language' "$1" || return 1
  grep -qi 'level of abstraction that makes the options differ most' "$1" || return 1
  grep -qi 'goal says what and why' "$1" || return 1
  grep -qi 'most architecturally elegant choice' "$1" || return 1
  grep -qi 'first principles' "$1" || return 1
  grep -qi 'concise' "$1" || return 1
  ! grep -qi 'delineate the choices' "$1"
}

# reply_last_ok <file> — the layout's last non-blank line is the reply line, byte for byte.
# Bash string equality, never awk `==`: the line carries a multibyte middle dot.
reply_last_ok() {
  local last
  last="$(layout "$1" | sed '/^[[:space:]]*$/d' | tail -1)"
  [ "$last" = "$REPLY_LINE" ]
}

# reply_rules_ok <file> — the line is last with nothing after it, lists only forms not yet shown
# and allowed, carries the options alone when none is left, and a named form comes directly.
reply_rules_ok() {
  grep -qi 'last line' "$1" || return 1
  grep -qi 'nothing follows it' "$1" || return 1
  grep -qi 'only the forms not yet shown' "$1" || return 1
  grep -qi 'options alone' "$1" || return 1
  grep -qi 'names a form gets that form directly' "$1"
}

# words_ok <file> — speaks of forms, never of climbing a ladder of rungs.
words_ok() {
  grep -qiw 'forms' "$1" || return 1
  ! grep -qiwE 'climb|climbs|climbing|ladder|rung|rungs' "$1"
}

# forms_ok <file> — four parts first in the terminal; the matrix threshold; the diagram and page
# conditions; video and raster named only as never-forms.
forms_ok() {
  local vr
  grep -qi 'first as the four parts' "$1" || return 1
  grep -qi 'never replaces' "$1" || return 1
  grep -i 'matrix' "$1" | grep -i 'three or more options' | grep -qi 'three or more criteria' || return 1
  grep -i 'diagram' "$1" | grep -i 'medium significance' | grep -qi 'structure' || return 1
  grep -i 'page' "$1" | grep -i 'hard to reverse' | grep -qi 'crosses waves' || return 1
  vr="$(grep -iE 'video|raster' "$1")"
  [ -n "$vr" ] || return 1
  ! grep -viq 'never' <<<"$vr"
}

# desc_of <file> -> the front-matter description line's text (the line the model reads to decide to invoke).
desc_of() { sed -n 's/^description: *//p' "$1" | head -1; }

# reach_ok <file> — the description names the case T19's live check exposed: the user asking which
# of several options to use is a decision to put in the shape.
reach_ok() {
  local d
  d="$(desc_of "$1")"
  grep -qi 'asks which of several options to use' <<<"$d" || return 1
  grep -qi 'is a decision too: put it in the shape' <<<"$d"
}

# number_ok <file> — the layout opens on the numbered heading, and the skill says the numbers run in
# the order asked. Bash string equality: the heading carries a multibyte middle dot.
number_ok() {
  local first
  first="$(layout "$1" | sed '/^[[:space:]]*$/d' | head -1)"
  [ "$first" = "$HEADING" ] || return 1
  grep -qi 'in one sequence, in the order asked' "$1"
}

# goal_ok <file> — the Goal is one sentence; a short paragraph may follow it, and is optional.
goal_ok() {
  grep -qi 'the goal is one sentence' "$1" || return 1
  grep -i 'short plain paragraph after the goal' "$1" | grep -qi 'optional'
}

# batch_ok <file> — small decisions may share a turn, a momentous one always goes alone, and no
# line still says one decision per turn. The negative reads the same file the positives just read.
batch_ok() {
  grep -qi 'small decisions may share a turn' "$1" || return 1
  grep -qiE 'momentous (one|decision) (always )?goes alone' "$1" || return 1
  ! grep -qiE 'one decision per (interview )?turn|one question per turn' "$1"
}

# ALT_CLAUSES — AC-13.1's five clauses, one phrase each, exactly as the skill states them.
ALT_CLAUSES=(
  'concepts, not mechanisms: its Goal and Options carry no file, function, row, task or version identifiers'
  'short plain paragraph after the Goal explains the problem before any option'
  'option is named as an idea and says what it means for the user'
  'names the principle that decides it'
  'Significance names the rule the choice sets for later work'
)

# altitude2_ok <file> — every one of the five design-altitude clauses is present.
altitude2_ok() {
  local c
  for c in "${ALT_CLAUSES[@]}"; do grep -qF -- "$c" "$1" || return 1; done
}

# pairs <file> -> one line per complete worked pair, its kind: a `### ` heading under
# `## Worked pairs` with exactly one `Mechanism level:` and one `Design altitude:` half.
pairs() {
  awk '
    function flush() { if (kind != "" && m == 1 && a == 1) print kind; kind = ""; m = 0; a = 0 }
    /^## / { flush(); inp = ($0 == "## Worked pairs"); next }
    inp && /^### / { flush(); kind = substr($0, 5); next }
    inp && kind != "" && $0 == "Mechanism level:" { m++ }
    inp && kind != "" && $0 == "Design altitude:" { a++ }
    END { flush() }' "$1"
}

# pairs_ok <file> — at least three pairs, of the three named kinds, none repeated.
pairs_ok() {
  local got
  got="$(pairs "$1" | sort)"
  [ "$(printf '%s\n' "$got" | grep -c .)" -ge 3 ] || return 1
  [ -z "$(printf '%s\n' "$got" | uniq -d)" ] || return 1
  [ "$(printf '%s\n' "$got" | sort -u | tr '\n' '|' | sed 's/|$//')" = "$KINDS" ]
}

# half <file> <n> <Mechanism level|Design altitude> -> the Goal-to-Options lines of pair n's half:
# what the altitude rule governs (the Recommendation and Significance lines are not read).
half() {
  awk -v n="$2" -v h="$3:" '
    /^## / { inp = ($0 == "## Worked pairs"); next }
    inp && /^### / { k++; on = 0; next }
    inp && k == n && $0 == h { on = 1; next }
    on && /^(Mechanism level|Design altitude):$/ { on = 0 }
    on && /^> \*\*(Recommendation|Significance):\*\*/ { on = 0 }
    on && /^> / { print }' "$1"
}

# IDENT — what a design-altitude Goal or Options never carries: a backticked name, a task,
# requirement or criterion number, a file name, a version string.
IDENT='`|(^|[^A-Za-z0-9])(T[0-9]+|REQ-[0-9]+|AC-[0-9]+)|[A-Za-z0-9_-]+\.(sh|md|tsv|yaml|json|py)([^A-Za-z]|$)|[0-9]+\.[0-9]+\.[0-9]+'

# altitude_halves_ok <file> — in every pair the mechanism half carries an identifier (it is the
# failure it shows) and the design-altitude half carries none.
altitude_halves_ok() {
  local n mech alt
  for n in 1 2 3; do
    mech="$(half "$1" "$n" 'Mechanism level')"; alt="$(half "$1" "$n" 'Design altitude')"
    [ -n "$mech" ] && [ -n "$alt" ] || return 1
    grep -qE "$IDENT" <<<"$mech" || return 1
    ! grep -qE "$IDENT" <<<"$alt" || return 1
  done
}

# doctor <src> <dst> <sed-expr> — a doctored copy of the skill.
doctor() { sed -E "$3" "$1" > "$2"; }

expect_true "0: skills/decision/SKILL.md exists" test -f "$SKILL"
[ -f "$SKILL" ] || finish

# The extractor has to find something, or every predicate below reads an empty layout.
LAYOUT="$(layout "$SKILL")"
expect_nonempty "0b: the skill carries a \`\`\`text layout fence" "$LAYOUT"

section "§SHAPE — four labels in order, numbered options, the altitude (AC-11.1)"

expect_eq "1: the layout's labels are Goal, Options, Recommendation, Significance, in that order" \
  "$LABELS" "$(layout_labels "$SKILL")"
expect_true "2: no separate rationale part, and no other label" labels_ok "$SKILL"
expect_true "3: Options is a numbered list, one blank line before Recommendation" options_ok "$SKILL"
expect_true "4: Recommendation opens on the option number and answers the others; Significance names downstream, compounding, reversal" \
  recommendation_ok "$SKILL"
expect_true "5: the five altitude clauses, in the latest wording" altitude_ok "$SKILL"
expect_true "6: small decisions may share a turn, a momentous one alone; none says one per turn (AC-12.3)" \
  batch_ok "$SKILL"
expect_true "7: approvals and reversible calls stay out" \
  grep -qiE 'approvals? .*reversible|reversible .*approvals?' "$SKILL"

section "§FORMS — prose first, the matrix threshold, the diagram and page conditions (AC-11.4)"

expect_true "8: forms are stated with their thresholds; video and raster only as never-forms" \
  forms_ok "$SKILL"
expect_true "8b: video and raster are named (so the never-check above read something)" \
  grep -qiE 'video|raster' "$SKILL"

section "§REPLY — the reply line, last, forms below the cap only (AC-11.5)"

expect_true "9: the layout ends on the reply line, byte for byte" reply_last_ok "$SKILL"
expect_true "10: the reply rules — last, nothing after, only forms not yet shown, options alone, a named form directly" \
  reply_rules_ok "$SKILL"
expect_true "11: the skill speaks of forms, never climb, ladder or rung" words_ok "$SKILL"

section "§PIN — a doctored copy fails the pin; nothing runs per decision (AC-11.6)"

# Each doctored copy is proved to differ from the shipped file, and to carry the plant, before its
# failure is read: a sed that matched nothing would leave a copy that fails for no reason at all.
anchor insert skills/decision/SKILL.md '**Recommendation:**'
doctor "$SKILL" "$TMP/renamed.md" 's/^\*\*Recommendation:\*\*/**Rationale:**/'
expect_true "12a: the renamed copy carries the plant" grep -q '^\*\*Rationale:\*\*' "$TMP/renamed.md"
expect_false "12b: a copy renaming Recommendation to Rationale fails the labels pin" labels_ok "$TMP/renamed.md"

anchor insert skills/decision/SKILL.md '**Significance:**'
doctor "$SKILL" "$TMP/rename2.md" 's/^\*\*Significance:\*\*/**Impact:**/'
expect_true "13a: the second renamed copy carries the plant" grep -q '^\*\*Impact:\*\*' "$TMP/rename2.md"
expect_false "13b: a copy renaming Significance fails the labels pin" labels_ok "$TMP/rename2.md"

anchor file skills/decision/SKILL.md 'first principles'
doctor "$SKILL" "$TMP/no-altitude.md" '/first principles/d'
expect_false "14a: the clause-dropped copy lost the clause" grep -q 'first principles' "$TMP/no-altitude.md"
expect_true "14b: …and still carries the others (the copy is not empty)" grep -qi 'plain language' "$TMP/no-altitude.md"
expect_false "14c: a copy dropping one altitude clause fails the altitude pin" altitude_ok "$TMP/no-altitude.md"

anchor insert skills/decision/SKILL.md 'Reply 1, 2 or 3 · or matrix, diagram, page'
awk -v r="$REPLY_LINE" '{ print } index($0, r) == 1 && length($0) == length(r) { print "Anything else?" }' \
  "$SKILL" > "$TMP/after-reply.md"
expect_true "15a: the text-after copy carries the plant" grep -q '^Anything else?$' "$TMP/after-reply.md"
expect_false "15b: a copy with text after the reply line fails the reply pin" reply_last_ok "$TMP/after-reply.md"

doctor "$SKILL" "$TMP/climb.md" 's/^(\*\*Goal:\*\*)/\1 climb/'
expect_true "16a: the forbidden-word copy carries the plant" grep -qw 'climb' "$TMP/climb.md"
expect_false "16b: a copy naming climb fails the words pin" words_ok "$TMP/climb.md"

# Nothing is run or written per decision: the skill is text only, and says so. A relation, not a
# count — markdown may join SKILL.md later; a script, a hook or a store may not.
expect_true "17a: the skill directory holds SKILL.md" test -f "${REPO}/skills/decision/SKILL.md"
expect_empty "17b: …and nothing that is not markdown (no script, hook or store runs per decision)" \
  "$(find "${REPO}/skills/decision" -type f ! -name '*.md')"
expect_true "18: the skill states nothing is run or written per decision" \
  grep -qi 'nothing is run or written' "$SKILL"

section "§SIZE — at most ${SIZE_CAP} bytes, listed in the README, no person named (AC-11.7, AC-12.4)"

SIZE="$(wc -c < "$SKILL" | tr -d ' ')"
expect_true "19: skills/decision/SKILL.md is at most ${SIZE_CAP} bytes (is ${SIZE})" test "$SIZE" -le "$SIZE_CAP"
expect_true "20: the README lists the skill" grep -q '^### `decision`' "${REPO}/README.md"
expect_true "21: the help page's skill list lists it" grep -q '`/bionic:decision`' "${REPO}/payload/commands/help.md"
expect_true "22a: the skill names its own audience-neutral subject (the user)" grep -qiw 'user' "$SKILL"
expect_false "22b: …and names no person or project from its sources" \
  grep -qiE 'chris|lehman|bionic2|wave-[0-9]|epic-[0-9]|jev' "$SKILL"

section "§CORE — the always-loaded core sends every decision through the skill"

expect_true "23: the core names the decision skill and says to invoke it" \
  grep -qE '`decision` skill: invoke it' "$CORE"
expect_true "24: …at any step and with no run open" grep -q 'at any step and with no run open' "$CORE"
expect_true "25: …naming the Step-1 and Step-2 interviews as its heaviest users" \
  grep -qE 'Step-1 .*Step-2 .*heaviest users' "$CORE"
expect_true "26: …small decisions may share a turn; approvals and reversible calls stay out" \
  grep -qE 'small decisions may share a turn.*Approvals and calls you can reverse stay out' "$CORE"

section "§REACH — the description names the case the live check exposed (T27, AC-11.2)"

expect_nonempty "27a: the description line is extractable" "$(desc_of "$SKILL")"
expect_true "27b: it names the user asking which of several options to use as a decision" reach_ok "$SKILL"
doctor "$SKILL" "$TMP/no-reach.md" 's/asks which of several options to use/asks something/'
expect_true "27c: the doctored copy's plant landed" grep -q 'asks something' "$TMP/no-reach.md"
expect_false "27d: …and the doctored copy (case removed) fails the pin" reach_ok "$TMP/no-reach.md"

section "§NUMBER — every decision is numbered on a heading above the Goal (AC-12.1)"

expect_true "28a: the layout opens on the heading, and the numbers run in the order asked" number_ok "$SKILL"
anchor file skills/decision/SKILL.md '**D<n> · Step <s>**'
grep -vF "$HEADING" "$SKILL" > "$TMP/no-number.md"
expect_false "28b: the number-dropped copy lost the heading" grep -qF "$HEADING" "$TMP/no-number.md"
expect_true "28c: …and still carries the Goal (the copy is not empty)" grep -q '^\*\*Goal:\*\*' "$TMP/no-number.md"
expect_false "28d: a copy dropping the numbered heading fails the number pin" number_ok "$TMP/no-number.md"

section "§GOAL — the Goal is one sentence, an optional short paragraph after it (AC-12.2)"

expect_true "29a: the altitude says the Goal is one sentence, and the paragraph after it is optional" goal_ok "$SKILL"
anchor file skills/decision/SKILL.md 'The Goal is one sentence'
doctor "$SKILL" "$TMP/long-goal.md" 's/The Goal is one sentence/The Goal may run to several sentences/'
expect_true "29b: the long-goal copy carries the plant" grep -q 'may run to several sentences' "$TMP/long-goal.md"
expect_false "29c: a copy letting the Goal run to several sentences fails the goal pin" goal_ok "$TMP/long-goal.md"

section "§BATCH — the batching rule on the skill, the core and Step 2, in the templates too (AC-12.3)"

for f in "$CORE" "$STEP2" "$CORE_TMPL" "$STEP2_TMPL"; do
  expect_true "30: ${f#"$REPO"/} lets small decisions share a turn, a momentous one alone, and never says one per turn" \
    batch_ok "$f"
done
anchor file skills/decision/SKILL.md 'momentous decision always goes alone'
doctor "$SKILL" "$TMP/no-alone.md" 's/[Mm]omentous (one|decision) always goes alone/momentous one may join them/'
expect_true "31a: the momentous-dropped copy carries the plant" grep -q 'momentous one may join them' "$TMP/no-alone.md"
expect_false "31b: a copy without momentous-alone fails the batch pin" batch_ok "$TMP/no-alone.md"
anchor file skills/canonical-sdlc/SKILL.md 'small decisions may share a turn'
doctor "$CORE" "$TMP/core-old.md" 's/small decisions may share a turn/one decision per turn, small decisions may share a turn/'
expect_true "32a: the core copy carries the old sentence" grep -q 'one decision per turn' "$TMP/core-old.md"
expect_false "32b: a core that still says one per turn fails the batch pin" batch_ok "$TMP/core-old.md"
expect_true "33: each decision of a batch keeps its own number and reply line" \
  grep -qi 'own number and reply line' "$SKILL"

section "§ALTITUDE — concepts not mechanisms, and the four clauses that make it so (AC-13.1)"

expect_true "34a: the five design-altitude clauses are present" altitude2_ok "$SKILL"
# One block per clause, each with its own shaped anchor (wave-35 T23; D16): an anchor in a loop
# runs once per pass but is declared once, so the checker would read one call for five runs.
alt_drop() {  # <i> <clause> — the copy without clause <i>, and the two rows that read it
  awk -v c="$2" '{ p = index($0, c); if (p) $0 = substr($0, 1, p - 1) "DROPPED" substr($0, p + length(c)); print }' \
    "$SKILL" > "$TMP/alt-$1.md"
  expect_true "34b.$1: the copy without clause $1 carries the plant" grep -q 'DROPPED' "$TMP/alt-$1.md"
  expect_false "34c.$1: a copy without clause $1 fails the altitude pin" altitude2_ok "$TMP/alt-$1.md"
}
anchor file skills/decision/SKILL.md 'concepts, not mechanisms: its Goal and Options carry no file, function, row, task or version identifiers'
alt_drop 1 "${ALT_CLAUSES[0]}"
anchor file skills/decision/SKILL.md 'short plain paragraph after the Goal explains the problem before any option'
alt_drop 2 "${ALT_CLAUSES[1]}"
anchor file skills/decision/SKILL.md 'option is named as an idea and says what it means for the user'
alt_drop 3 "${ALT_CLAUSES[2]}"
anchor file skills/decision/SKILL.md 'names the principle that decides it'
alt_drop 4 "${ALT_CLAUSES[3]}"
anchor file skills/decision/SKILL.md 'Significance names the rule the choice sets for later work'
alt_drop 5 "${ALT_CLAUSES[4]}"

section "§EXAMPLES — three worked pairs, three kinds, in the skill file (AC-13.2)"

PAIRS="$(pairs "$SKILL")"
expect_nonempty "35a: the pairs extractor reads pairs from the skill" "$PAIRS"
expect_true "35b: three pairs, one of each kind: enforced, built, shared" pairs_ok "$SKILL"
expect_true "35c: each pair's mechanism half carries identifiers, its design-altitude half none" \
  altitude_halves_ok "$SKILL"

anchor file skills/decision/SKILL.md '### What a wave builds'
awk '/^### What a wave builds$/ { skip = 1; next } skip && /^#/ { skip = 0 } !skip' "$SKILL" > "$TMP/two-pairs.md"
expect_eq "36a: the two-pair copy carries two pairs" "2" "$(pairs "$TMP/two-pairs.md" | grep -c .)"
expect_false "36b: a copy with two pairs fails the examples pin" pairs_ok "$TMP/two-pairs.md"

anchor file skills/decision/SKILL.md '### How a shared resource is shared'
doctor "$SKILL" "$TMP/same-kind.md" 's/^### How a shared resource is shared$/### How a rule is enforced/'
expect_eq "37a: the same-kind copy carries the enforced kind twice" "2" "$(pairs "$TMP/same-kind.md" | grep -c 'enforced')"
expect_false "37b: a copy with two pairs of one kind fails the examples pin" pairs_ok "$TMP/same-kind.md"

anchor file skills/decision/SKILL.md '## Worked pairs'
awk '/^## Worked pairs$/ { print "## Worked pairs"; print ""; print "See examples.md beside this file."; skip = 1; next }
     skip && /^## / { skip = 0 } !skip' "$SKILL" > "$TMP/moved.md"
expect_true "38a: the moved-out copy points elsewhere" grep -q 'See examples.md' "$TMP/moved.md"
expect_false "38b: a copy whose pairs live in another file fails the examples pin" pairs_ok "$TMP/moved.md"

awk '/^Design altitude:$/ { a = 1 } a == 1 && /^> \*\*Goal:\*\*/ { $0 = $0 " in `walls.sh`"; a = 2 } { print }' \
  "$SKILL" > "$TMP/ident.md"
expect_true "39a: the identifier copy carries the plant" grep -q 'in `walls.sh`' "$TMP/ident.md"
expect_false "39b: a design-altitude half naming a file fails the halves pin" altitude_halves_ok "$TMP/ident.md"

section "§CLIMB — the Altitude section opens on the act, the labels after it (wave-35 AC-10.1)"

# altitude_span <file> -> the lines of the `## Altitude` section, heading excluded.
altitude_span() { awk '/^## / { on = ($0 == "## Altitude"); next } on' "$1"; }

# first_at <span> <phrase> -> the span's line number of the phrase's first case-blind match, or 0.
first_at() { grep -inF -- "$2" <<<"$1" | head -1 | cut -d: -f1 | grep . || echo 0; }

# climb_ok <file> — the section opens on the reframe (its first line asks for a conceptual level),
# then, in order: the one difference named before any structure; detail cut before sentences;
# plain words over the record's house style; the four labels. The failure, if stated, comes after.
climb_ok() {
  local s first a b c d e f
  s="$(altitude_span "$1")"
  first="$(sed '/^[[:space:]]*$/d' <<<"$s" | head -1)"
  grep -qi 'conceptual level' <<<"$first" || return 1
  a="$(first_at "$s" 'conceptual level')"
  b="$(first_at "$s" 'one thing the options differ on')"
  c="$(grep -in 'detail before' <<<"$s" | grep -i 'sentences' | head -1 | cut -d: -f1)"
  d="$(first_at "$s" 'house style')"
  e="$(first_at "$s" 'four labels')"
  f="$(first_at "$s" 'failure to avoid')"
  [ "$a" -gt 0 ] && [ "$b" -gt "$a" ] && [ "${c:-0}" -gt "$b" ] && [ "$d" -gt "$c" ] && [ "$e" -gt "$d" ] || return 1
  # The difference is named as a contrast: without it the live check's Goals asked "how", not
  # "whether this, or that" (T24-altitude-live.md, round 1).
  sed -n "${b}p" <<<"$s" | grep -qi 'contrast' || return 1
  [ "$f" -eq 0 ] || [ "$f" -gt "$e" ]
}

SPAN="$(altitude_span "$SKILL")"
expect_nonempty "40a: the Altitude span extractor reads the section" "$SPAN"
expect_true "40b: the section opens on the reframe and keeps the act's order" climb_ok "$SKILL"

# The climb-first sentence deleted: the section no longer opens on the reframe.
anchor file skills/decision/SKILL.md 'conceptual level'
grep -viF 'conceptual level' "$SKILL" > "$TMP/no-climb.md"
expect_false "41a: the no-reframe copy lost the climb-first sentence" grep -qiF 'conceptual level' "$TMP/no-climb.md"
expect_true "41b: …and still carries the one-difference rule (the copy is not empty)" \
  grep -qiF 'one thing the options differ on' "$TMP/no-climb.md"
expect_false "41c: a copy without the climb-first sentence fails the climb pin" climb_ok "$TMP/no-climb.md"

# The failure moved to open the section: it opens on what to avoid, not on the act.
anchor file skills/decision/SKILL.md 'failure to avoid'
awk '/failure to avoid/ { next } { print } $0 == "## Altitude" { print ""; print "The failure to avoid is a brief written at the level of mechanisms." }' \
  "$SKILL" > "$TMP/failure-first.md"
expect_true "42a: the failure-first copy opens its Altitude section on the failure" \
  grep -qi 'failure to avoid' <<<"$(altitude_span "$TMP/failure-first.md" | sed '/^[[:space:]]*$/d' | head -1)"
expect_false "42b: a copy opening on the failure fails the climb pin" climb_ok "$TMP/failure-first.md"

# The one-difference rule removed.
anchor file skills/decision/SKILL.md 'one thing the options differ on'
doctor "$SKILL" "$TMP/no-difference.md" 's/one thing the options differ on/options/'
expect_true "43a: the no-difference copy still opens on the reframe" grep -qiF 'conceptual level' "$TMP/no-difference.md"
expect_false "43b: a copy without the one-difference rule fails the climb pin" climb_ok "$TMP/no-difference.md"

# Concise pulled the wrong way: sentences cut before detail.
anchor file skills/decision/SKILL.md 'detail before cutting sentences'
doctor "$SKILL" "$TMP/sentences-first.md" 's/detail before cutting sentences/sentences before cutting detail/'
expect_true "44a: the sentences-first copy carries the plant" grep -qF 'sentences before cutting detail' "$TMP/sentences-first.md"
expect_false "44b: a copy cutting sentences before detail fails the climb pin" climb_ok "$TMP/sentences-first.md"

# The difference named, but not as a contrast.
anchor file skills/decision/SKILL.md ', as a contrast: whether this, or that'
doctor "$SKILL" "$TMP/no-contrast.md" 's/, as a contrast: whether this, or that//'
expect_true "45a: the no-contrast copy still names the one difference" \
  grep -qiF 'one thing the options differ on' "$TMP/no-contrast.md"
expect_false "45b: …and has lost the contrast" grep -qF 'as a contrast' "$TMP/no-contrast.md"
expect_false "45c: a copy naming the difference without the contrast fails the climb pin" climb_ok "$TMP/no-contrast.md"

finish
