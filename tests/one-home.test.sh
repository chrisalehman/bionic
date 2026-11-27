#!/bin/bash
# tests/one-home.test.sh — six facts that cannot be one place, held equal by reading both sides.
#
#   §PAIRS  the full pass's two prints; the task roles against their page; the working-branch refusal against its
#           page; the version rule against its page; the pages that teach starting a row; the triple's kinds
#           against the method's page. Each pair is read from the files themselves, never from a copy typed here,
#           and a change to either side in a scratch copy turns its row red.
#
# ANTI-VACUITY. A side that reads empty fails the agreeing row, and a mutant row needs both sides non-empty and
# unequal, so a mutant that broke a reader does not read as a pass. Each mutation is anchored to the one line it
# changes before it is made.
#
# Usage: bash tests/one-home.test.sh

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
. "$(dirname "$0")/lib/proof-at-head-world.sh" || { echo "one-home.test.sh: cannot load lib/proof-at-head-world.sh"; exit 1; }

S=skills/canonical-sdlc; L=payload/scripts/lib
FILES="$S/steps/3.md $S/steps/4.md $S/operational-rules.md $S/SKILL.md $S/dispatch.md"
MT="$SANDBOX/mt"

# Each side function prints `<one side><TAB><the other>`, both read from the tree it is handed.
sideprints() {  # <lib> <plan> <project> -> the whole print's colour and head, then the health line's
  local w h f g
  w="$(bash -c '. "$1/roots.sh" && . "$1/proof.sh" && proof_whole_text "$2" "$3"' _ "$1" "$2" "$3" 2>/dev/null)"
  h="$(bash -c '. "$1/roots.sh" && . "$1/proof.sh" && proof_health_line "$2" "$3"' _ "$1" "$2" "$3" 2>/dev/null)"
  f="${w#* at }"; g="${h#*head=}"
  printf '%s %s\t%s %s' "${w%% *}" "${f:0:8}" "${h%% *}" "${g:0:8}"
}
sideroles() {
  printf '%s\t%s' "$(sed -n 's/.*On a \([a-z]*\) or \([a-z]*\) row the card.s agent column reads it: `complex` is \([a-z-]*\), `standard` \([a-z-]*\);.*/\1 \2|complex=\3 standard=\4/p' "$1/$S/steps/3.md")" \
    "$(bash -c '. "$1/'$L'/units.sh" || exit; k="$(units_kinds role tag)"; d=""
      for x in $(units_kinds); do [ -z "$(units_kind_role "$x" "complexity: complex")" ] || d="$d${d:+ }$x"; done
      [ "$d" = "$k" ] || k="$k != $d"
      printf "%s|complex=%s standard=%s" "$k" "$(units_kind_role build "complexity: complex")" "$(units_kind_role build "complexity: standard")"' _ "$1")"
}
sidebranch() {
  local p; p="$(sed -n 's/.*`REFUSED reason=\([^`]*\)`.*/\1/p' "$1/$S/operational-rules.md" | head -1)"
  printf '%s\t%s' "${p//<plan>/P1}" "$(bash -c '. "$1/'$L'/run.sh" || exit; run_no_branch_why P1' _ "$1" 2>/dev/null)"
}
sideversion() {
  printf '%s %s\t%s %s' "$(sed -n 's/^\*\*\([0-9]*\) is the version a plan is written at\..*/\1/p' "$1/$S/SKILL.md")" \
    "$(sed -n 's/.* a page that does not declare \([0-9]*\) is refused.*/\1/p' "$1/$S/SKILL.md")" \
    "$(sed -n 's/^\[ "\$SDLC_VERSION" = \([0-9]*\) \] || _eg_refuse_lowered.*/\1/p' "$1/$L/walls.sh")" \
    "$(sed -n 's/.*a new plan is written at \([0-9]*\)\..*/\1/p' "$1/$L/write-gate.sh")"
}
startverb() { sed -n 's/.*`session-poker\.sh \([a-z]*\) <id>`.*/\1/p' "$1" | head -1; }
sidestart() {  # the three pages that name the verb, the third read twice so both sides hold two words
  printf '%s %s\t%s %s' "$(startverb "$1/$S/dispatch.md")" "$(startverb "$1/$S/operational-rules.md")" \
    "$(startverb "$1/$S/steps/4.md")" "$(startverb "$1/$S/steps/4.md")"
}
sidetriple() {
  printf '%s\t%s' "$(awk '/^\| (Intent|Scale) \|/ { t = ($2 == "Intent") ? "i" : "s"; next }
      /^\| \| `/ { gsub(/[`|]/, ""); $1 = $1; r = $0; next }
      !/^\|/ { t = "" }
      t && /^\| `/ { sub(/^\| `/, ""); sub(/`.*/, ""); w[t] = w[t] " " $0 }
      END { print w["i"] w["s"] "|" r }' "$1/$S/SKILL.md" | sed 's/^ //')" \
    "$(bash -c '. "$1/'$L'/write-gate.sh" || exit; printf "%s %s|%s" "$WRITE_GATE_INTENTS" "$WRITE_GATE_SCALES" "$WRITE_GATE_RIGORS"' _ "$1")"
}

# chk <label> <side function> <tree> <agree|differ> [<args for the side function>]
chk() {
  local o a b; o="$("$2" "$3" "${@:5}")"; a="${o%%$'\t'*}"; b="${o#*$'\t'}"
  if [ "$4" = agree ]; then [ -n "$a" ] && [ "$a" = "$b" ] && { ok "$1"; return; }
  else [ -n "$a" ] && [ -n "$b" ] && [ "$a" != "$b" ] && { ok "$1"; return; }; fi
  no "$1" "one side [$a], the other [$b]"
}
# mut <file> <fixed pattern> <sed> -> $MT, a scratch copy of the pages and the libraries the pairs read, one line changed
mut() {
  local f; rm -rf "$MT"
  for f in $FILES; do mkdir -p "$MT/${f%/*}"; cp "$REPO_ROOT/$f" "$MT/$f"; done
  mkdir -p "$MT/$L"; cp -R "$REPO_ROOT/$L/." "$MT/$L"
  anchor "$MT/$1" "$2" 1
  sed "$3" "$MT/$1" > "$MT/n" && mv "$MT/n" "$MT/$1"
}
# both <label> <side function>, then `<file> <pattern> <sed>` for the page and for the other side
both() {
  chk "$1: the sides agree on the tree" "$2" "$REPO_ROOT" agree
  mut "$3" "$4" "$5"; chk "$1: the page changed, the sides differ" "$2" "$MT" differ
  mut "$6" "$7" "$8"; chk "$1: the other side changed, the sides differ" "$2" "$MT" differ
}

setup_section "§WORLD — a green whole run and a red one, each with no landing past it"
pah_world green "" 0; PG="$PAH_P"; PG_PLAN="$PAH_PLAN"
pah_world red "a.test.sh,b.test.sh" 0; PR="$PAH_P"; PR_PLAN="$PAH_PLAN"

section "§PAIRS — each pair reads both sides, and a changed side turns it red"
chk "PR.1 the full pass's two prints agree over a green run" sideprints "$PAH_LIB" agree "$PG_PLAN" "$PG"
chk "PR.1 …and over a red one" sideprints "$PAH_LIB" agree "$PR_PLAN" "$PR"
rm -rf "$SANDBOX/ml"; cp -R "$PAH_LIB" "$SANDBOX/ml"
anchor "$SANDBOX/ml/proof.sh" "covered*) printf 'green at " 1
sed "s/covered\*) printf 'green at /covered*) printf 'passed at /" "$SANDBOX/ml/proof.sh" > "$SANDBOX/ml/n" && mv "$SANDBOX/ml/n" "$SANDBOX/ml/proof.sh"
chk "PR.1 the full-pass print changed, the prints differ" sideprints "$SANDBOX/ml" differ "$PG_PLAN" "$PG"
cp "$PAH_LIB/proof.sh" "$SANDBOX/ml/proof.sh"
anchor "$SANDBOX/ml/proof.sh" "printf 'green head=%s%s evidence=" 1
sed "s/printf 'green head=%s%s evidence=/printf 'passed head=%s%s evidence=/" "$SANDBOX/ml/proof.sh" > "$SANDBOX/ml/n" && mv "$SANDBOX/ml/n" "$SANDBOX/ml/proof.sh"
chk "PR.1 the health line changed, the prints differ" sideprints "$SANDBOX/ml" differ "$PG_PLAN" "$PG"
both "PR.2 the task roles" sideroles $S/steps/3.md "build or test row" 's/build or test row/build or doc row/' \
  $L/units.sh "complex) printf 'senior-implementor'" "s/complex) printf 'senior-implementor'/complex) printf 'implementor'/"
both "PR.3 the working-branch refusal" sidebranch $S/operational-rules.md "reason=no-working-branch plan=<plan>" 's/reason=no-working-branch/reason=no-branch/' \
  $L/run.sh "'no-working-branch plan=%s'" "s/'no-working-branch plan=%s'/'no-branch plan=%s'/"
both "PR.4 the version rule" sideversion $S/SKILL.md "**15 is the version a plan is written at" 's/^\*\*15 is/**16 is/' \
  $L/walls.sh '"$SDLC_VERSION" = 15 ] || _eg_refuse_lowered' 's/= 15 \] || _eg_refuse_lowered/= 16 ] || _eg_refuse_lowered/'
mut $L/write-gate.sh "a new plan is written at 15." 's/a new plan is written at 15\./a new plan is written at 16./'
chk "PR.4 the write gate's version changed, the sides differ" sideversion "$MT" differ
both "PR.5 the pages that teach starting a row" sidestart $S/dispatch.md '`session-poker.sh start <id>`' 's/session-poker\.sh start/session-poker.sh begin/' \
  $S/steps/4.md '`session-poker.sh start <id>`' 's/session-poker\.sh start/session-poker.sh begin/'
mut $S/operational-rules.md '`session-poker.sh start <id>`' 's/session-poker\.sh start/session-poker.sh begin/'
chk "PR.5 the rules page changed, the pages differ" sidestart "$MT" differ
both "PR.6 the triple's kinds" sidetriple $S/SKILL.md '| `tune` |' 's/^| `tune` |/| `tweak` |/' \
  $L/write-gate.sh 'WRITE_GATE_SCALES="task wave epic"' 's/"task wave epic"/"task wave epic pr"/'

finish
