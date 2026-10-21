#!/bin/bash
# tests/words.test.sh — one vocabulary on what the user reads: a review is a "review", whoever does
# it is never a "reader", and a goal nobody measures is "not measured".
#
# WHAT THIS SUITE OWNS. The lint `words_hits` and the surfaces it reads: the skill texts
# (skills/canonical-sdlc, skills/handoff), the command pages (payload/commands), the agent role
# texts and the texts pushed to an agent at start (agents/, payload/context), the strings the poker
# verbs, the dispatch wall and the plan, proof, walls and units libraries print (hooks/poker/*.sh,
# hooks/dispatch-preflight.sh, payload/scripts/lib/{plan,proof,walls,units}.sh), and the sources
# under agents-src/ the generated texts are rendered from. It refuses "reader", "readers" and
# "readings" anywhere in that text, and "reading" as a noun: after a determiner ("a reading", "the
# reading", "the $q reading", "its whole reading"). The verb ("reading the file") and the
# participle ("every key reading `pending`") pass.
#
# WHAT THE LINT READS. A markdown line minus its HTML comments and its inline code spans, because a
# directive (`<!-- INJECT: brief-scaffold-reader -->`), a block marker, a verb's flag (`--reader`)
# and a record key (`reader=`) are identifiers, not words; a fenced block is read, since a brief
# template's lines are copied into a brief. A shell line minus its comment, full-line or trailing,
# so a code comment is never read and a printed string always is. A word joined to an identifier
# by `_`, `-` or `=` (`PF_READER`, `--reader`, `reader=`) is not the word, and `${VAR}` is read
# as a placeholder, so `the ${q} reading` is still the noun.
#
# THE ALLOW LIST holds the senses the lint cannot tell apart, one entry per line of text it
# answers, each with its reason. An entry that matches no line of its file is refused (§ALLOW), so
# the list cannot outlive the line it was written for.
#
# NOT READ HERE: hooks/poker/sitrep.sh, hooks/session-poker.sh and payload/scripts/card.sh, the
# cards they print, the handoff head and the Patrol line. Those are linted where they are rendered,
# not as source.
#
# FIXTURE FIDELITY (see .claude/rules/test-harness.md, "Fixture fidelity"). §TEXTS reads the
# shipped files in place. §PLANT and §SENSE are SYNTHESIZED: each copies a shipped surface into
# scratch and appends one line, so the lint reads the real file plus the plant; each copy proves
# its plant landed.
#
# ANTI-VACUITY (same file, "Anti-vacuity"). The surface list is proved non-empty in each class
# and the extractor non-empty on every file before any absence is read (§TEXTS); the clean
# readback of each file in §TEXTS has the red readback of its planted copy beside it in §PLANT,
# and §SENSE pairs each passing sense with a refused one in the same copies.
#
# Usage: bash tests/run.sh --only words.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── the allow list ───────────────────────────────────────────────────────────
# <paths from the repo root, space-separated>|<a fixed string of the line, the word inside it>|<why it
# is not the review sense>. The string is cut from the line before the line is read, so a refused
# word elsewhere on the same line is still found. A generated file and its source each carry the
# line, so an entry names both.
WORDS_ALLOW="$TMP/allow"
cat > "$WORDS_ALLOW" <<'WORDS_ALLOW_EOF'
agents-src/blocks/implementor-mechanics.md agents/implementor.md agents/senior-implementor.md|so a reader can re-run the search|whoever reads the report, not a review
skills/canonical-sdlc/steps/0.md agents-src/templates/skills/canonical-sdlc/steps/0.md.tmpl|a later reader meets a decision|whoever reads the plan later, not a review
skills/canonical-sdlc/steps/0.md agents-src/templates/skills/canonical-sdlc/steps/0.md.tmpl|so every later reader sees a decision|whoever reads the plan later, not a review
skills/canonical-sdlc/steps/5.md agents-src/templates/skills/canonical-sdlc/steps/5.md.tmpl|written for the next reader|whoever reads the spec next, not a review
skills/canonical-sdlc/steps/7.md agents-src/templates/skills/canonical-sdlc/steps/7.md.tmpl|it reaches a reader only if|whoever reads the document, not a review
skills/canonical-sdlc/operational-rules.md|with readers who will never open the spec|the people who read a design document, not a review
skills/canonical-sdlc/operational-rules.md|tells a reader nothing to push back on|whoever reads the Step-2 card, not a review
skills/canonical-sdlc/operational-rules.md|what the reader should look at closely|whoever reads the close-out report, not a review
skills/canonical-sdlc/operational-rules.md|the calls a later reader would want|whoever reads the close-out report later, not a review
skills/canonical-sdlc/operational-rules.md|no jargon a plain reader would look up|whoever reads the close-out report, not a review
payload/context/working-principles.md agents-src/templates/context/working-principles.md.tmpl|Lead with what the reader needs to decide|whoever reads the answer, not a review
payload/context/working-principles.md agents-src/templates/context/working-principles.md.tmpl|the reader may act on it|whoever reads the answer, not a review
hooks/dispatch-preflight.sh|a reason the reader can check|whoever reads the plan row, not a review
hooks/poker/tick.sh|the panel reading is|a reading of the agent panel, a measurement, not a review
WORDS_ALLOW_EOF

# ── the surfaces ─────────────────────────────────────────────────────────────
# words_surfaces <root> — every file the lint reads, one path from <root> per line.
words_surfaces() {
  (
    cd "$1" || exit 1
    ls skills/canonical-sdlc/*.md skills/canonical-sdlc/steps/*.md skills/handoff/*.md \
      payload/commands/*.md agents/*.md agents-src/blocks/*.md \
      agents-src/templates/*.tmpl agents-src/templates/commands/*.tmpl \
      agents-src/templates/skills/canonical-sdlc/*.tmpl agents-src/templates/skills/canonical-sdlc/steps/*.tmpl \
      agents-src/templates/context/*.tmpl payload/context/*.md \
      payload/scripts/lib/plan.sh payload/scripts/lib/proof.sh payload/scripts/lib/walls.sh payload/scripts/lib/units.sh \
      hooks/dispatch-preflight.sh 2>/dev/null
    ls hooks/poker/*.sh 2>/dev/null | /usr/bin/grep -v '^hooks/poker/sitrep\.sh$'
  )
}

# words_text <file> — "<line number><TAB><text>" for every line the lint reads.
words_text() {
  case "$1" in
    *.sh) awk '
      # the line with its comment cut, quotes and $( ) tracked so a # inside a string is kept
      function code(s,   n, i, c, st, top) {
        n = length(s); st = "c"
        for (i = 1; i <= n; i++) {
          c = substr(s, i, 1); top = substr(st, length(st), 1)
          if (top == "s") { if (c == "\047") st = substr(st, 1, length(st) - 1); continue }
          if (c == "\\") { i++; continue }
          if (top == "d") {
            if (c == "\"") st = substr(st, 1, length(st) - 1)
            else if (c == "$" && substr(s, i + 1, 1) == "(") { st = st "c"; i++ }
            continue
          }
          if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t;]/)) return substr(s, 1, i - 1)
          if (c == "\047") { st = st "s"; continue }
          if (c == "\"") { st = st "d"; continue }
          if (c == "$" && substr(s, i + 1, 1) == "(") { st = st "c"; i++; continue }
          if (c == ")" && length(st) > 1) { st = substr(st, 1, length(st) - 1); continue }
        }
        return s
      }
      NR == 1 && /^#!/ { next }
      { t = code($0); if (t ~ /[^ \t]/) printf "%d\t%s\n", NR, t }' "$1" ;;
    *) awk '{ t = $0; gsub(/<!--([^-]|-[^-])*-->/, "", t); gsub(/`[^`]*`/, "", t); if (t ~ /[^ \t]/) printf "%d\t%s\n", NR, t }' "$1" ;;
  esac
}

# words_refused — reads "<tag><TAB><text>" lines and prints "<tag> <text>" for each text carrying a
# refused word. A placeholder is read as one: `${q:-a reading}` keeps its default, and `$NAME`
# cannot be the word.
words_refused() {
  awk '{
    c = index($0, "\t"); tag = substr($0, 1, c - 1); t = substr($0, c + 1)
    l = t; gsub(/\$\{[A-Za-z_][A-Za-z0-9_]*\}/, "$V", l); gsub(/\$\{[A-Za-z_][A-Za-z0-9_]*[:#%\/+=?-]+/, "$V ", l)
    gsub(/\$[A-Za-z_][A-Za-z0-9_]*/, "$V", l); l = tolower(l)
    if (l ~ /(^|[^a-z0-9_-])readers?([^a-z0-9_=-]|$)/ || l ~ /(^|[^a-z0-9_-])readings([^a-z0-9_=-]|$)/ \
      || l ~ /(^|[^a-z0-9_])(a|an|the|its|their|each|every|this|that|one|no|any|your|whose)( [a-z$-]+)? reading([^a-z0-9_-]|$)/) print tag " " t
  }'
}

# words_hits <file> [<path from the repo root>] — "<path>:<line>: <text>" for every line carrying a
# refused word once the allow entries naming <path> are cut from it. Prints nothing for a clean file.
words_hits() {
  local rel="${2:-${1#"$REPO"/}}"
  words_text "$1" | awk -F'\t' -v rel="$rel" -v allow="$WORDS_ALLOW" '
    BEGIN {
      while ((getline e < allow) > 0) {
        p = index(e, "|"); if (!p) continue
        rest = substr(e, p + 1); q = index(rest, "|"); if (q < 2) continue
        k = split(substr(e, 1, p - 1), P, " ")
        for (j = 1; j <= k; j++) if (P[j] == rel) { n++; A[n] = substr(rest, 1, q - 1) }
      }
    }
    {
      t = $0; sub(/^[0-9]+\t/, "", t)
      for (i = 1; i <= n; i++) while ((c = index(t, A[i])) > 0) t = substr(t, 1, c - 1) substr(t, c + length(A[i]))
      printf "%s:%s:\t%s\n", rel, $1, t
    }' | words_refused
}

# ── §TEXTS ───────────────────────────────────────────────────────────────────
section "§TEXTS: no review-sense reading or reader, and no \"no reader for\", on the texts the user reads"

SURF="$(words_surfaces "$REPO")"
for cls in 'skills/canonical-sdlc/' 'skills/handoff/' 'payload/commands/' 'agents/' 'agents-src/blocks/' \
  'agents-src/templates/' 'agents-src/templates/context/' 'payload/context/' 'hooks/poker/' 'hooks/dispatch-preflight.sh' \
  'payload/scripts/lib/plan.sh' 'payload/scripts/lib/proof.sh' 'payload/scripts/lib/walls.sh' 'payload/scripts/lib/units.sh'; do
  expect_nonempty "the surfaces include $cls" "$(printf '%s\n' "$SURF" | /usr/bin/grep -F "$cls" | head -1)"
done
EMPTY=""
while IFS= read -r f; do
  [ -n "$(words_text "$REPO/$f")" ] || EMPTY="$EMPTY $f"
done <<WORDS_SURF_EOF
$SURF
WORDS_SURF_EOF
expect_empty "the lint reads text from every surface (a file it reads nothing from is listed)" "$EMPTY"
HITS=""
while IFS= read -r f; do
  HITS="$HITS$(words_hits "$REPO/$f")"$'\n'
done <<WORDS_SURF_EOF
$SURF
WORDS_SURF_EOF
HITS="$(printf '%s' "$HITS" | /usr/bin/grep -v '^$')"
expect_empty "no surface carries a refused word" "$HITS"

# ── §PLANT ───────────────────────────────────────────────────────────────────
section "§PLANT: a planted \"reader\" on every surface and every agents-src source goes red"

# plant_copy <path from the repo root> <dir> — a copy of the surface with one printed line (a shell
# file) or one sentence (markdown) carrying the word appended.
plant_copy() {
  mkdir -p "$2/${1%/*}" && cp "$REPO/$1" "$2/$1" || return 1
  case "$1" in
    *.sh) printf '%s\n' 'say "PLANT the reader of this line"' >> "$2/$1" ;;
    *) printf '\n%s\n' 'PLANT the reader of this line.' >> "$2/$1" ;;
  esac
}
while IFS= read -r f; do
  plant_copy "$f" "$TMP/plant" || { no "$f: the planted copy is made" "cannot copy $REPO/$f"; continue; }
  expect_eq "$f: the copy carries the plant once" "1" "$(/usr/bin/grep -c '^\(say "\)\{0,1\}PLANT the reader' "$TMP/plant/$f")"
  expect_contains "$f: the lint refuses the planted reader" "PLANT the reader" "$(words_hits "$TMP/plant/$f" "$f")"
done <<WORDS_SURF_EOF
$SURF
WORDS_SURF_EOF

# ── §SENSE ───────────────────────────────────────────────────────────────────
section "§SENSE: the noun and the role are refused in every form; the verb, a comment and an identifier pass"

SH_REL="hooks/poker/judge.sh"; MD_REL="skills/canonical-sdlc/steps/6.md"
mkdir -p "$TMP/sense/${SH_REL%/*}" "$TMP/sense/${MD_REL%/*}"
cp "$REPO/$SH_REL" "$TMP/sense/$SH_REL"; cp "$REPO/$MD_REL" "$TMP/sense/$MD_REL"
cat >> "$TMP/sense/$SH_REL" <<'WORDS_SH_EOF'
die "REFUSED-1 the evidence readings are in"
say "REFUSED-2 no reader for the three suites"
echo "REFUSED-3 the $q reading failed"
printf '%s\n' "REFUSED-4 ${q:-a reading} #3"
say "REFUSED-5 Readers rate it"
# PASSED-1 a reader in a comment, the reading
x=1  # PASSED-2 a trailing comment names the reader
say "PASSED-3 register it: proof-add review <record> --reader <name>"
echo "PASSED-4 reader=$PF_READER for $x"
say "PASSED-5 reading the file, line by line"
WORDS_SH_EOF
cat >> "$TMP/sense/$MD_REL" <<'WORDS_MD_EOF'

REFUSED-6 **The Readers.** They answer the questions.
REFUSED-7 a whole reading reads from the base.
PASSED-6 register it with `proof-add review <record> --reader <name>`.
<!-- INJECT: brief-scaffold-reader --> PASSED-7
PASSED-8 every key its tier owes reading `pending`, and reading the snapshot is judgment.
WORDS_MD_EOF
SENSE="$(words_hits "$TMP/sense/$SH_REL" "$SH_REL")"$'\n'"$(words_hits "$TMP/sense/$MD_REL" "$MD_REL")"
for n in 1 2 3 4 5 6 7; do
  expect_contains "REFUSED-$n is found" "REFUSED-$n " "$SENSE"
done
expect_eq "the shell copy still parses (the plants are code, not a broken file)" "0" "$(bash -n "$TMP/sense/$SH_REL" >/dev/null 2>&1; echo $?)"
expect_eq "the copies carry every passing plant" "8" "$(cat "$TMP/sense/$SH_REL" "$TMP/sense/$MD_REL" | /usr/bin/grep -c 'PASSED-[0-9]')"
for n in 1 2 3 4 5 6 7 8; do
  expect_absent "PASSED-$n is not found (the lint read the same copies that refused the others)" "PASSED-$n " "$SENSE"
done

# ── §ALLOW ───────────────────────────────────────────────────────────────────
section "§ALLOW: every allow entry gives a reason, answers a refused word, and still matches a line of each file it names"

expect_nonempty "the allow list has entries" "$(head -1 "$WORDS_ALLOW")"
while IFS='|' read -r paths str why; do
  [ -n "$paths" ] || continue
  expect_nonempty "'$str': it gives a reason" "$why"
  expect_nonempty "'$str': it carries a refused word" "$(printf 'x\t%s\n' "$str" | words_refused)"
  for f in $paths; do
    expect_true "'$str': $f still holds it" /usr/bin/grep -qF -- "$str" "$REPO/$f"
  done
done < "$WORDS_ALLOW"

finish
