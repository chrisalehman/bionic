#!/bin/bash
# tests/words.test.sh — one vocabulary on what the user reads: a review is a "review", whoever does
# it is never a "reader", and a goal nobody measures is "not measured".
#
# WHAT THIS SUITE OWNS. The lint `words_hits` and the surfaces it reads: the skill texts
# (skills/canonical-sdlc, skills/handoff, skills/sitrep), the command pages (payload/commands), the
# agent role texts and the texts pushed to an agent at start (agents/, payload/context), the strings
# the poker and its verbs, the card renderer, the dispatch wall and the plan, proof, walls and units
# libraries print (hooks/session-poker.sh, hooks/poker/*.sh, payload/scripts/card.sh,
# hooks/dispatch-preflight.sh, payload/scripts/lib/{plan,proof,walls,units}.sh), the sources under
# agents-src/ the generated texts are rendered from, and what the user reads rendered: the sitrep
# card, the handoff head and the Patrol line. It refuses "reader", "readers" and
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
# RENDERED SURFACES. A card prints facts the source does not spell (a task's name, an ask's title),
# so the sitrep card, the handoff head and the Patrol line are also read as printed, over one
# fixture run, every line whole (§RENDERED).
#
# FIXTURE FIDELITY (see .claude/rules/test-harness.md, "Fixture fidelity"). §TEXTS reads the
# shipped files in place. §PLANT and §SENSE are SYNTHESIZED: each copies a shipped surface into
# scratch and appends one line, so the lint reads the real file plus the plant; each copy proves
# its plant landed. §RENDERED draws its three surfaces through the real verbs over a SYNTHESIZED
# run: a plan in the shipped `## Tasks` shape, an ask opened on its register in lib/owed.sh's
# line shape, and a session bound to it by lib/binding.sh `bind_plan`.
#
# ANTI-VACUITY (same file, "Anti-vacuity"). The surface list is proved non-empty in each class
# and the extractor non-empty on every file before any absence is read (§TEXTS); the clean
# readback of each file in §TEXTS has the red readback of its planted copy beside it in §PLANT,
# and §SENSE pairs each passing sense with a refused one in the same copies.
#
# Usage: bash tests/run.sh --only words.test.sh
#
# pins: agents-src/blocks/implementor-mechanics.md agents/implementor.md agents/senior-implementor.md skills/canonical-sdlc/steps/0.md agents-src/templates/skills/canonical-sdlc/steps/0.md.tmpl skills/canonical-sdlc/steps/5.md agents-src/templates/skills/canonical-sdlc/steps/5.md.tmpl skills/canonical-sdlc/steps/7.md agents-src/templates/skills/canonical-sdlc/steps/7.md.tmpl skills/canonical-sdlc/operational-rules.md payload/context/working-principles.md agents-src/templates/context/working-principles.md.tmpl hooks/dispatch-preflight.sh hooks/poker/tick.sh skills/sitrep/SKILL.md payload/scripts/card.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── the allow list ───────────────────────────────────────────────────────────
# <paths from the repo root, space-separated>|<a fixed string of the line, the word inside it>|<why it
# is not the review sense>. The paths end at the first `|` and the reason starts after the last, so
# the string may hold a `|` and the reason may not. The string is cut from the line before the line
# is read, so a refused word elsewhere on the same line is still found. A generated file and its source each carry the
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
skills/sitrep/SKILL.md|never "reading" or "reader"|names the refused words, to refuse them
payload/scripts/card.sh|(readers?|readings?|unmeasured)|the judgment check's pattern of the refused words
WORDS_ALLOW_EOF

# ── the surfaces ─────────────────────────────────────────────────────────────
# words_surfaces <root> — every file the lint reads, one path from <root> per line.
words_surfaces() {
  (
    cd "$1" || exit 1
    ls skills/canonical-sdlc/*.md skills/canonical-sdlc/steps/*.md skills/handoff/*.md skills/sitrep/*.md \
      payload/commands/*.md agents/*.md agents-src/blocks/*.md \
      agents-src/templates/*.tmpl agents-src/templates/commands/*.tmpl \
      agents-src/templates/skills/canonical-sdlc/*.tmpl agents-src/templates/skills/canonical-sdlc/steps/*.tmpl \
      agents-src/templates/context/*.tmpl payload/context/*.md \
      payload/scripts/lib/plan.sh payload/scripts/lib/proof.sh payload/scripts/lib/walls.sh payload/scripts/lib/units.sh \
      hooks/dispatch-preflight.sh hooks/session-poker.sh hooks/poker/*.sh payload/scripts/card.sh 2>/dev/null
  )
}

# words_text <file> — "<line number><TAB><text>" for every line the lint reads; a rendered surface
# (.txt) is read whole, since nothing on it is code.
words_text() {
  case "$1" in
    *.txt) awk '$0 ~ /[^ \t]/ { printf "%d\t%s\n", NR, $0 }' "$1" ;;
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
        rest = substr(e, p + 1); q = 0
        for (j = length(rest); j > 0; j--) if (substr(rest, j, 1) == "|") { q = j; break }
        if (q < 2) continue
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
for cls in 'skills/canonical-sdlc/' 'skills/handoff/' 'skills/sitrep/' 'payload/commands/' 'agents/' 'agents-src/blocks/' \
  'agents-src/templates/' 'agents-src/templates/context/' 'payload/context/' 'hooks/poker/' 'hooks/poker/sitrep.sh' \
  'hooks/session-poker.sh' 'payload/scripts/card.sh' 'hooks/dispatch-preflight.sh' \
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
while IFS= read -r e; do
  paths="${e%%|*}"; str="${e#*|}"; why=""
  case "$str" in *'|'*) why="${str##*|}"; str="${str%|*}" ;; esac
  [ -n "$paths" ] || continue
  expect_nonempty "'$str': it gives a reason" "$why"
  expect_nonempty "'$str': it carries a refused word" "$(printf 'x\t%s\n' "$str" | words_refused)"
  for f in $paths; do
    expect_true "'$str': $f still holds it" /usr/bin/grep -qF -- "$str" "$REPO/$f"
  done
done < "$WORDS_ALLOW"

# ── §RENDERED ────────────────────────────────────────────────────────────────
section "§RENDERED: the sitrep card, the handoff head and the Patrol line, drawn over a fixture run, carry no refused word; a plant on each goes red"

# One run in a temp repository: a three-row plan at Step 4, an approval open on its register, the session bound to it,
# the clock, the zone, the machine's probes, the gate store and the share pinned as tests/sitrep-card.test.sh pins them.
. "$(dirname "$0")/lib/bound-marker.sh"
export BIONIC_PLUGINS_DIR="$TMP/no-plugins" BIONIC_PRESSURE_RING="$TMP/pressure.ring" CLAUDE_CONFIG_DIR="$TMP/config"
export BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_LOAD_1M=1.0 BIONIC_PROBE_FREE_PCT=60 BIONIC_PROBE_SWAP_PCT=0
export BIONIC_PROBE_CORES=8 BIONIC_PROBE_USED_PCT=30 BIONIC_PROBE_BUSY_CORES=1.0 BIONIC_PROBE_BUSY_CORES_5M=1.0
export BIONIC_GATE_DIR="$TMP/gate" BIONIC_NOW_EPOCH=1791324000 TZ=America/Los_Angeles   # 2026-10-06 3:00 PM PDT
mkdir -p "$BIONIC_PLUGINS_DIR" "$CLAUDE_CONFIG_DIR/bionic" "$BIONIC_GATE_DIR/requests" "$BIONIC_GATE_DIR/cost"
printf '80\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
WR_SID="5c1e7a2b-3d4f-4e8a-9b6c-1f2e3d4c5b6a"
WR_R="$TMP/run"; WR_P="$WR_R/.bionic/docs/plans/epic-01-fx/wave-02-fx.plan.md"
mkdir -p "${WR_P%/*}" "$WR_R/.bionic/docs/record/wave-02-fx" "$WR_R/.bionic/tmp"
( cd "$WR_R" && git init -q . && printf '.bionic/\n' >> .git/info/exclude && git -c user.name=fx -c user.email=fx@example.invalid commit -q --allow-empty -m init )
wr_row() { printf '| %s | %s | build | %s · complexity: standard | — | — | %s | 30 | REQ-1 | lib/%s.sh | — | — | %s | — | — | — |\n' "$1" "$2" "$3" "$4" "$1" "$5"; }
{
  printf -- '---\nwave: wave-02-fx\nrelease: 9.9.0\nworking-branch: wave/02-fx\nintegration-branch: main\nforecast: 8h\n'
  printf 'goals: owed · the user says what they owe (record/owed-test.md)\n---\n# fixture plan\n\n## SDLC State\n\n'
  printf 'approved-by: fixture 2026-10-06T16:00:00Z "approved"\ncurrent: 4\n\n- Step 4: implementation opened\n'
  printf -- '- T1: landed %s 2026-10-06T18:00:00Z — .worktrees/02-T1\n' "$(printf 'c%.0s' $(seq 40))"
  printf '\n## Tasks\n\n| id | step | kind | task | agent | deps | reads | size | serves | Files | worktree | base | status | suites | lands-on | artifact |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n'
  wr_row T1 4 "The first row" — landed
  wr_row T2 4 "The second row" — active
  wr_row T3 8 "Merge it" "approval:release" pending
  printf '\n## Not Doing\n\n- nothing\n'
} > "$WR_P"
WR_REG="$(bash -c '. "$1" && owed_register "$2" "$3"' _ "$REPO/payload/scripts/lib/owed.sh" "$WR_R" "$WR_P")"
mkdir -p "${WR_REG%/*}"
printf 'owed/v1|key=approve:release|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: release|reply=poker: WAIT T3 — approval:release\n' > "$WR_REG"
bound_marker "$WR_R" "$WR_SID" "$WR_P"
wr_poke() {  # <args after the poker…> [stdin from the caller] -> the verb's stdout; its exit code in WR_RC
  WR_RC=0
  ( cd "$WR_R" && exec env CLAUDE_CODE_SESSION_ID="$WR_SID" bash "$REPO/hooks/session-poker.sh" "$@" ) 2> "$TMP/wr.err" || WR_RC=$?
}
mkdir -p "$TMP/rendered"
# The judgment is the seven lines the card verb takes; code draws every fact row from the sheet.
wr_poke sitrep "$WR_P" > "$TMP/wr-sheet"
wr_fact() { sed -n "s/^$1: //p" "$TMP/wr-sheet"; }   # <key> -> the run's sheet's value for it
expect_nonempty "RD0 precondition: the run's sheet predicts a close the card draws" "$(wr_fact close.predicted)"
wr_poke sitrep card "$WR_P" > "$TMP/rendered/card.txt" <<WR_JUDGMENT_EOF
purpose: the first row lands and the release goes out; on course.
call: Approve the release once 4/2 lands.
grade: C
point: One task is in flight and nothing is red.
ask approve:release: The release approval, which holds 8/3 — recommend approve once 4/2 lands
close: if 4/2 lands first time.
WR_JUDGMENT_EOF
expect_eq "RD1 the sitrep card is drawn (exit 0) and holds the open approval under Blocked on you" "0|1" \
  "$WR_RC|$(/usr/bin/grep -c '^    • The release approval, which holds 8/3' "$TMP/rendered/card.txt")"
wr_poke sitrep --line "$WR_P" > "$TMP/rendered/line.txt"
expect_eq "RD2 the Patrol line is drawn (exit 0): one line, the approval owed" "0|1|1" \
  "$WR_RC|$(/usr/bin/grep -c . "$TMP/rendered/line.txt")|$(/usr/bin/grep -c ' tasks · owed: 1 on you · 0 on events · close ' "$TMP/rendered/line.txt")"
wr_poke handoff > /dev/null <<'WR_HANDOFF_EOF'
Summary
- Doing: the fixture run.
- Learned: nothing new.
- Open: none.
- First: land T2.
WR_HANDOFF_EOF
WR_HF="$(ls "$WR_R/.bionic/docs/record/handoffs/"*.md 2>/dev/null | head -1)"
awk 'NR > 1 && $0 == "" { exit } NR > 1 { print }' "$WR_HF" > "$TMP/rendered/head.txt" 2>/dev/null
expect_eq "RD3 the handoff head is drawn (exit 0): the title, the run line, Blocked on you: yes and the approval's line" "0|1|1|1" \
  "$WR_RC|$(/usr/bin/grep -c ' tasks · owed: 1 on you · 0 on events · close ' "$TMP/rendered/head.txt")|$(/usr/bin/grep -cx 'Blocked on you: yes' "$TMP/rendered/head.txt")|$(/usr/bin/grep -c '^- approval: release — holds ' "$TMP/rendered/head.txt")"
for wr_s in card line head; do
  expect_nonempty "$wr_s: the lint reads the rendered text (the extractor reads the real output)" "$(words_text "$TMP/rendered/$wr_s.txt")"
  expect_empty "$wr_s: no refused word on it" "$(words_hits "$TMP/rendered/$wr_s.txt" "rendered/$wr_s.txt")"
  cp "$TMP/rendered/$wr_s.txt" "$TMP/rendered/$wr_s.plant.txt"
  printf '%s\n' '    • PLANT no reader for the goal' >> "$TMP/rendered/$wr_s.plant.txt"
  expect_contains "$wr_s: a planted \"no reader for\" on it is refused" "PLANT no reader for" \
    "$(words_hits "$TMP/rendered/$wr_s.plant.txt" "rendered/$wr_s.txt")"
done


# ── §BIND ────────────────────────────────────────────────────────────────────
section "§BIND: over the same fixture run, a judgment that sets 1 green and 3 red over a sheet of 3 green and 1 red is refused, not drawn"

# The rendered texts above are read for refused words; a card the judgment filled with the wrong number beside a word
# the sheet places is a wrong card with no refused word in it, so the same run is given a suite line of its own and the
# card verb is asked the swap. The landing record holds four suites by their last verdict, three green and one red.
# fails-when: the swap draws, the control in the sheet's order is refused, or the refusal leaves the card on stdout.
WR_REC="$WR_R/.bionic/docs/record/wave-02-fx/landing-proofs.log"
mkdir -p "${WR_REC%/*}"
for wr_k in "a green" "b green" "c green" "d red"; do
  printf 'line/v1|ev=verdict|row=T1|commit=%s|suite=%s.test.sh|result=%s|log=/rec/%s.log|at=2026-10-06T18:00:00Z\n' \
    "$(printf 'c%.0s' $(seq 40))" "${wr_k%% *}" "${wr_k##* }" "${wr_k%% *}" >> "$WR_REC"
done
wr_poke sitrep "$WR_P" > "$TMP/wr-sheet"
expect_eq "BN0 precondition: the sheet holds 3 green and 1 red on one line" "1" "$(/usr/bin/grep -c '^tests.suites-run: 4: 3 green, 1 red ' "$TMP/wr-sheet")"
wr_bind() {  # <the point> -> the card verb's stdout over the sheet; WR_RC, and stderr in $TMP/wr.err
  wr_poke sitrep card "$WR_P" <<WR_BIND_EOF
purpose: the first row lands and the release goes out; on course.
call: Approve the release once 4/2 lands.
grade: C
point: $1
ask approve:release: The release approval, which holds 8/3 — recommend approve once 4/2 lands
close: if 4/2 lands first time.
WR_BIND_EOF
}
wr_bind "3 suites green and 1 red." > "$TMP/rendered/bind-ok.txt"
expect_eq "BN1 control: the point in the sheet's order draws (exit 0) with its numbers on the card" "0|1" \
  "$WR_RC|$(/usr/bin/grep -c '3 suites green and 1 red' "$TMP/rendered/bind-ok.txt")"
wr_bind "1 suite green and 3 red." > "$TMP/rendered/bind-swap.txt"
expect_eq "BN2 the swap is refused (exit 1) and nothing is drawn" "1|0" "$WR_RC|$(/usr/bin/grep -c . "$TMP/rendered/bind-swap.txt")"
expect_contains "BN2b …naming each number beside the word it does not stand by" 'says 1 beside "green"' "$(cat "$TMP/wr.err")"
expect_contains "BN2c …and the other" 'says 3 beside "red"' "$(cat "$TMP/wr.err")"

finish
