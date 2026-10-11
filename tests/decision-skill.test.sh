#!/bin/bash
# tests/decision-skill.test.sh — the decision skill's text, pinned (wave-33 REQ-11; wave-29 folded).
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
# §SHAPE AC-11.1 · §FORMS AC-11.4 · §REPLY AC-11.5 · §PIN AC-11.6 · §SIZE AC-11.7 · §CORE the core
# rule's static half (AC-11.2's live half is another row's). Static: reads files, runs nothing.
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
expect_true "6: one decision per interview turn" grep -qi 'one decision per interview turn' "$SKILL"
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
anchor -E "$SKILL" '^\*\*Recommendation:\*\*' 1
doctor "$SKILL" "$TMP/renamed.md" 's/^\*\*Recommendation:\*\*/**Rationale:**/'
expect_true "12a: the renamed copy carries the plant" grep -q '^\*\*Rationale:\*\*' "$TMP/renamed.md"
expect_false "12b: a copy renaming Recommendation to Rationale fails the labels pin" labels_ok "$TMP/renamed.md"

anchor -E "$SKILL" '^\*\*Significance:\*\*' 1
doctor "$SKILL" "$TMP/rename2.md" 's/^\*\*Significance:\*\*/**Impact:**/'
expect_true "13a: the second renamed copy carries the plant" grep -q '^\*\*Impact:\*\*' "$TMP/rename2.md"
expect_false "13b: a copy renaming Significance fails the labels pin" labels_ok "$TMP/rename2.md"

anchor "$SKILL" 'first principles' 1
doctor "$SKILL" "$TMP/no-altitude.md" '/first principles/d'
expect_false "14a: the clause-dropped copy lost the clause" grep -q 'first principles' "$TMP/no-altitude.md"
expect_true "14b: …and still carries the others (the copy is not empty)" grep -qi 'plain language' "$TMP/no-altitude.md"
expect_false "14c: a copy dropping one altitude clause fails the altitude pin" altitude_ok "$TMP/no-altitude.md"

anchor "$SKILL" "$REPLY_LINE" 1
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

section "§SIZE — at most 5,000 bytes, listed in the README, no person named (AC-11.7)"

SIZE="$(wc -c < "$SKILL" | tr -d ' ')"
expect_true "19: skills/decision/SKILL.md is at most 5000 bytes (is ${SIZE})" test "$SIZE" -le 5000
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
expect_true "26: …one decision per turn; approvals and reversible calls stay out" \
  grep -qE 'one decision per turn.*Approvals and calls you can reverse stay out' "$CORE"

finish
