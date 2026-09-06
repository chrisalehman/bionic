#!/bin/bash
# tests/patrol-marker.test.sh — pins the Patrol tick marker across its three
# spellings: payload/scripts/lib/patrol.sh (the SSoT, where the classifier
# regex lives and the header prose names the literal in plain text at :28/:34),
# payload/hooks/patrol-duties-gate.sh (the literal substring its awk index()
# search reads at :177), and payload/skills/canonical-sdlc/SKILL.md (the
# literal command the patrol prompt actually issues at its "Tick the poker"
# bullet, which is what ends up in the transcript the other two read back).
# Bionic 1.3.2, wave-01-dogfood-fixes slice 4/6, spec AC-21.
#
# WHY THIS EXISTS. Nothing joins these three copies together today
# (.bionic/docs/record/wave-bionic-1.3.2-dogfood-fixes/
# research-b2-b4-b6-b8-gate-tick-revive.md §3: "no marker constant, three
# spellings, no agreement test") — a rename of the marker in any one file,
# alone, is invisible to every other suite. This is the N-way agreement test
# the cross-gate-agreement doctrine calls for (tests/cross-gate-agreement.test.sh),
# scoped to this one duplicated concept.
#
# WHAT COUNTS AS "THE SAME LITERAL". The marker is READ out of patrol.sh — the
# SSoT — rather than hardcoded here: patrol.sh's own header comments spell it
# in plain text (`session-poker.sh tick`), distinct from the classifier's
# escaped, whitespace-tolerant regex a few lines below
# (`session-poker\.sh[[:space:]]+tick`, which exists to tolerate a prompt
# whose whitespace varies, not to change the marker itself). Extracting rather
# than hardcoding means a rename of the marker inside patrol.sh's own prose is
# what this suite reads first — hardcoding the string here would make the test
# agree with itself, not with the SSoT.
#
# ANTI-VACUITY (memory/no-vacuous-tests-at-authoring; styled after
# tests/patrol-revive.test.sh :50-56's "prove the subject exists and parses
# before any of it runs", and the Diagrams section of SKILL.md: "every pin
# re-proves itself against a doctored copy on each run"). A positive
# assertion alone cannot tell a real agreement from a coincidence, so §B below
# builds a scratch copy of all three files, mutates exactly one spelling at a
# time, and proves the SAME check function goes red — independently, for each
# of the three files, and with an unmutated control that stays green — before
# §A's assertions against the real files are trusted.
#
# Usage: bash tests/patrol-marker.test.sh
#   BIONIC_PATROL_LIB_UNDER_TEST=/tmp/mutant/patrol.sh \
#   BIONIC_PATROL_GATE_UNDER_TEST=/tmp/mutant/patrol-duties-gate.sh \
#   BIONIC_PATROL_SKILL_UNDER_TEST=/tmp/mutant/SKILL.md \
#     bash tests/patrol-marker.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PAYLOAD="${REPO}/payload"

PATROL_LIB="${BIONIC_PATROL_LIB_UNDER_TEST:-${PAYLOAD}/scripts/lib/patrol.sh}"
GATE_HOOK="${BIONIC_PATROL_GATE_UNDER_TEST:-${PAYLOAD}/hooks/patrol-duties-gate.sh}"
SKILL_DOC="${BIONIC_PATROL_SKILL_UNDER_TEST:-${PAYLOAD}/skills/canonical-sdlc/SKILL.md}"

# pass/fail were pure-rename shadows of the framework's ok/no; the suite's own
# explicit `TOTAL=$((TOTAL + 1))` lines beside each call are dropped too, since
# ok/no already increment it (S7, AC-12).

# THE SUITE IS NOT ALLOWED TO BE VACUOUS over a missing subject: three absent
# files would make every "does not carry the marker" assertion below pass
# over nothing (memory/no-vacuous-tests-at-authoring).
for f in "$PATROL_LIB" "$GATE_HOOK" "$SKILL_DOC"; do
  [ -f "$f" ] || { echo "patrol-marker: no file at $f — suite refuses to run"; exit 1; }
done

# ---------- the check under test ----------

# marker_of <patrol.sh path> -> the literal marker on stdout (whitespace
# squeezed to one space), or empty + nothing on stdout if the SSoT no longer
# spells it in plain text anywhere. Deliberately NOT the classifier's own
# regex a few lines below the header comments — reading that back would let
# the pin agree with a regex that could itself have drifted from the prose
# describing it.
marker_of() {
  # awk's $1=$1 reassembly (default OFS is a single space) both collapses any
  # run of matched whitespace to one space AND drops the trailing newline
  # cleanly — a plain `tr -s '[:space:]' ' '` turns grep's own line-ending
  # newline into a trailing space that command substitution does not strip.
  grep -m1 -oE 'session-poker\.sh[[:space:]]+tick' "$1" 2>/dev/null | awk '{ $1 = $1; print }'
}

# spelling_ok <marker> <gate-hook> <skill-doc> -> rc 0 iff BOTH carry the
# literal marker somewhere in their text.
spelling_ok() {
  local marker="$1" gate="$2" skill="$3"
  grep -qF -- "$marker" "$gate" && grep -qF -- "$marker" "$skill"
}

# ---------- §A: the real files agree ----------

MARKER="$(marker_of "$PATROL_LIB")"

if [ -n "$MARKER" ]; then
  ok "1: the tick marker literal reads out of $PATROL_LIB (the SSoT): '$MARKER'"
else
  no "1: no plain-text tick marker literal found in $PATROL_LIB" \
    "the SSoT's own prose no longer spells the marker in plain text"
fi

if [ -n "$MARKER" ] && grep -qF -- "$MARKER" "$GATE_HOOK"; then
  ok "2: patrol-duties-gate.sh still carries the marker '$MARKER'"
else
  no "2: patrol-duties-gate.sh no longer carries the marker read from patrol.sh"
fi

if [ -n "$MARKER" ] && grep -qF -- "$MARKER" "$SKILL_DOC"; then
  ok "3: SKILL.md still carries the marker '$MARKER'"
else
  no "3: SKILL.md no longer carries the marker read from patrol.sh"
fi

if [ -n "$MARKER" ] && spelling_ok "$MARKER" "$GATE_HOOK" "$SKILL_DOC"; then
  ok "4: the three-way agreement holds — patrol.sh, patrol-duties-gate.sh and SKILL.md all spell the tick marker the same way"
else
  no "4: the three-way agreement is broken — see #1-3 above for which side moved"
fi

# ---------- §A2: the classifier regex is the spelling that DECIDES ----------
#
# Review-b (bionic 1.3.2 wave-01, B-4b): the prose marker is what §1-4 pin, but
# what actually classifies a cron job as the Patrol is the jq `test("…")` regex
# a few lines below the header. If that regex drifted the prose pin would stay
# green while every tick misclassified. So the regex is read back too and must
# MATCH the prose marker — not "agree with a regex that could itself have
# drifted", which is why it is compared against the literal, never trusted alone.

# classifier_regex_of <patrol.sh path> -> the ERE inside jq's test("…") that
# names the poker tick, jq-unescaped (\\. -> \.), or empty if absent.
classifier_regex_of() {
  grep -m1 -oE 'test\("session-poker\\\\\.sh[^"]*"\)' "$1" 2>/dev/null \
    | sed -e 's/^test("//' -e 's/")$//' -e 's/\\\\/\\/g'
}

CLASSIFIER_RE="$(classifier_regex_of "$PATROL_LIB")"
if [ -n "$MARKER" ] && [ -n "$CLASSIFIER_RE" ] && printf '%s\n' "$MARKER" | grep -qE -- "$CLASSIFIER_RE"; then
  ok "4b: patrol.sh's classifier regex ($CLASSIFIER_RE) matches the prose marker '$MARKER' — the deciding spelling agrees"
else
  no "4b: patrol.sh's classifier regex does not match the prose marker" \
    "regex='$CLASSIFIER_RE' marker='$MARKER'"
fi

# ---------- §B: anti-vacuity — mutating exactly one spelling goes red ----------

WORK="$(mktemp -d)" || { echo "patrol-marker: cannot create a scratch dir"; exit 1; }
trap 'rm -rf "$WORK"' EXIT

cp "$PATROL_LIB" "$WORK/patrol.sh"
cp "$GATE_HOOK" "$WORK/patrol-duties-gate.sh"
cp "$SKILL_DOC" "$WORK/SKILL.md"

# doctor_and_check <label> <which: lib|gate|skill>
#
# Copies the WORK trio into its own fresh scratch dir, mutates ONLY the named
# file's marker occurrences to a broken spelling, then re-runs the exact same
# check §A just trusted against the real files. Expects red.
doctor_and_check() {
  local label="$1" which="$2" scratch lib gate skill got_marker
  scratch="$(mktemp -d)" || { no "$label" "cannot create a scratch dir"; return; }
  cp "$WORK/patrol.sh" "$scratch/patrol.sh"
  cp "$WORK/patrol-duties-gate.sh" "$scratch/patrol-duties-gate.sh"
  cp "$WORK/SKILL.md" "$scratch/SKILL.md"

  case "$which" in
    lib)   sed -i.bak 's/session-poker\.sh tick/session-poker.sh tock/g' "$scratch/patrol.sh" ;;
    gate)  sed -i.bak 's/session-poker\.sh tick/session-poker.sh tock/g' "$scratch/patrol-duties-gate.sh" ;;
    skill) sed -i.bak 's/session-poker\.sh tick/session-poker.sh tock/g' "$scratch/SKILL.md" ;;
    *) no "$label" "unknown mutation target '$which'"; rm -rf "$scratch"; return ;;
  esac

  lib="$scratch/patrol.sh"; gate="$scratch/patrol-duties-gate.sh"; skill="$scratch/SKILL.md"
  got_marker="$(marker_of "$lib")"

  if [ "$which" = lib ]; then
    # the SSoT itself moved: the extractor should now find nothing to read
    if [ -z "$got_marker" ]; then
      ok "$label"
    else
      no "$label" "doctoring patrol.sh's own spelling did not blind the extractor — got '$got_marker'"
    fi
  else
    # the SSoT is intact, but one of the two spellings it is compared against
    # moved alone — the agreement check must go red
    if [ -n "$got_marker" ] && ! spelling_ok "$got_marker" "$gate" "$skill"; then
      ok "$label"
    else
      no "$label" "mutating $which alone did not turn the agreement check red"
    fi
  fi
  rm -rf "$scratch"
}

doctor_and_check "5: mutating patrol.sh's own spelling alone goes red" lib
doctor_and_check "6: mutating patrol-duties-gate.sh's spelling alone goes red" gate
doctor_and_check "7: mutating SKILL.md's spelling alone goes red" skill

# 7b: mutating ONLY the classifier regex (prose intact) must go red at §4b —
# proves 4b reads the regex, not the prose it sits beside
scratch_re="$(mktemp -d)"
cp "$WORK/patrol.sh" "$scratch_re/patrol.sh"
sed -i.bak 's/test("session-poker\\\\\.sh\[\[:space:\]\]+tick")/test("session-poker\\\\.sh[[:space:]]+tock")/' "$scratch_re/patrol.sh"
mut_re="$(classifier_regex_of "$scratch_re/patrol.sh")"
mut_marker="$(marker_of "$scratch_re/patrol.sh")"
if [ -n "$mut_marker" ] && [ -n "$mut_re" ] && [ "$mut_re" != "$CLASSIFIER_RE" ] && ! printf '%s\n' "$mut_marker" | grep -qE -- "$mut_re"; then
  ok "7b: mutating patrol.sh's classifier regex alone (prose intact) goes red at 4b"
else
  no "7b: mutating the classifier regex alone did not go red" "mutated regex='$mut_re' marker='$mut_marker'"
fi
rm -rf "$scratch_re"

# the control: an UNMUTATED trio must still agree — proves §5-7's red comes
# from the mutation, not from a broken harness that would be red regardless
control_marker="$(marker_of "$WORK/patrol.sh")"
if [ -n "$control_marker" ] && spelling_ok "$control_marker" "$WORK/patrol-duties-gate.sh" "$WORK/SKILL.md"; then
  ok "8: the unmutated scratch trio still agrees (the mutation harness itself is not the source of §5-7's red)"
else
  no "8: the unmutated scratch trio disagrees — the mutation harness is broken, not the marker"
fi

finish
