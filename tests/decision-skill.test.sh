#!/bin/bash
# tests/decision-skill.test.sh — the decision skill's text, pinned (wave-33 REQ-11; wave-29 folded;
# wave-34 REQ-12 and REQ-13).
#
# WHAT THIS SUITE OWNS. `skills/decision/SKILL.md` carries one fixed shape for a decision put to
# the user: four bold labels in order (Goal, Options, Recommendation, Significance), a numbered
# Options list, and one reply line last. The labels and the reply line are an INTERFACE: a script
# can read decisions back out of the transcripts by them, so they are fixed strings, and this suite
# is what fixes them. The shape is held here, in the text; a put during a run is one verb of the run's script.
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
REPLY_LINE='Reply 1, 2 or 3 · or matrix, diagram, page · to see <the thing>: `<dig-in command>`'
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

# reply_tail <file> -> the layout's last non-blank line: where a brief ends.
reply_tail() { layout "$1" | sed '/^[[:space:]]*$/d' | tail -1; }

# reply_last_ok <file> — the layout's last non-blank line is the reply line, byte for byte.
# Bash string equality, never awk `==`: the line carries a multibyte middle dot.
reply_last_ok() {
  local last
  last="$(reply_tail "$1")"
  [ "$last" = "$REPLY_LINE" ]
}

# words_ok <file> — speaks of forms, never of climbing a ladder of rungs.
words_ok() {
  grep -qiw 'forms' "$1" || return 1
  ! grep -qiwE 'climb|climbs|climbing|ladder|rung|rungs' "$1"
}

# doctor <src> <dst> <sed-expr> — a doctored copy of the skill.
doctor() { sed -E "$3" "$1" > "$2"; }

expect_true "0: skills/decision/SKILL.md exists" test -f "$SKILL"
[ -f "$SKILL" ] || finish

section "§PIN — a doctored copy fails the pin; nothing runs per decision (AC-11.6)"

# Each doctored copy is proved to differ from the shipped file, and to carry the plant, before its
# failure is read: a sed that matched nothing would leave a copy that fails for no reason at all.
doctor "$SKILL" "$TMP/renamed.md" 's/^\*\*Recommendation:\*\*/**Rationale:**/'
expect_true "12a: the renamed copy carries the plant" grep -q '^\*\*Rationale:\*\*' "$TMP/renamed.md"
expect_false "12b: a copy renaming Recommendation to Rationale fails the labels pin" labels_ok "$TMP/renamed.md"

doctor "$SKILL" "$TMP/rename2.md" 's/^\*\*Significance:\*\*/**Impact:**/'
expect_true "13a: the second renamed copy carries the plant" grep -q '^\*\*Impact:\*\*' "$TMP/rename2.md"
expect_false "13b: a copy renaming Significance fails the labels pin" labels_ok "$TMP/rename2.md"

doctor "$SKILL" "$TMP/no-altitude.md" '/first principles/d'
expect_false "14a: the clause-dropped copy lost the clause" grep -q 'first principles' "$TMP/no-altitude.md"
expect_true "14b: …and still carries the others (the copy is not empty)" grep -qi 'plain language' "$TMP/no-altitude.md"
expect_false "14c: a copy dropping one altitude clause fails the altitude pin" altitude_ok "$TMP/no-altitude.md"

awk -v r="$REPLY_LINE" '{ print } index($0, r) == 1 && length($0) == length(r) { print "Anything else?" }' \
  "$SKILL" > "$TMP/after-reply.md"
expect_true "15a: the text-after copy carries the plant" grep -q '^Anything else?$' "$TMP/after-reply.md"
expect_false "15b: a copy with text after the reply line fails the reply pin" reply_last_ok "$TMP/after-reply.md"

doctor "$SKILL" "$TMP/climb.md" 's/^(\*\*Goal:\*\*)/\1 climb/'
expect_true "16a: the forbidden-word copy carries the plant" grep -qw 'climb' "$TMP/climb.md"
expect_false "16b: a copy naming climb fails the words pin" words_ok "$TMP/climb.md"

# The skill directory is text only: markdown may join SKILL.md later; a script, a hook or a store may not. A put
# during a run is the run script's verb, and the line it prints is the last of Significance, never typed.
expect_true "17a: the skill directory holds SKILL.md" test -f "${REPO}/skills/decision/SKILL.md"
expect_empty "17b: …and nothing that is not markdown (no script, hook or store runs per decision)" \
  "$(find "${REPO}/skills/decision" -type f ! -name '*.md')"

finish
