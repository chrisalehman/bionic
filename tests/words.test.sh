#!/bin/bash
# tests/words.test.sh — one vocabulary on what the user reads: a review is a "review", whoever does
# it is never a "reader", and a goal nobody measures is "not measured".
#
# WHAT THIS SUITE OWNS. The lint `words_hits` and the surfaces it reads: the skill texts
# (skills/canonical-sdlc, skills/handoff, skills/sitrep), the command pages (payload/commands), the
# agent role texts and the texts pushed to an agent at start (agents/, payload/context), the strings
# the poker and its verbs, the card renderer, the dispatch wall and the plan, proof, walls, units and dispatch
# libraries print (hooks/session-poker.sh, hooks/poker/*.sh, payload/scripts/card.sh,
# hooks/dispatch-preflight.sh, payload/scripts/lib/{plan,proof,walls,units,dispatch}.sh), the sources under
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
# A CHECK IS A TEST. The Step 2 and Step 3 cards, the Step 2 views and their refusals are drawn over a SYNTHESIZED
# spec and plan, and every line of the hooks and scripts is read, for the old word "eval" naming a check; the shell
# builtin of the same spelling and the old heading a page written before the rename still carries pass (§TEST-WORD).
# The loaded pages define test and eval once each, teach the Test design and the reply words the cards print, and call
# no check an eval (§TEST-WORD-PAGES).
#
# EXITS ON THE PAGES. No rendered page or role file names a non-zero exit code beside an answer that now exits 0
# (the landing's WAITING, a gate that did not admit a run, a checked advance or the judge that would refuse, the
# tick's NOTIFY, an early card, a close held before the merge); the record's codes stay. The suite line carries the
# meant-to-fail word as an assignment leading the suite segment (§EXIT-PAGES). The dispatch page and each of the six
# role files hold the rule that a check expecting no match ends with `|| true` (§NONE-EXITS-0).
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
# pins: agents-src/blocks/implementor-mechanics.md agents/implementor.md agents/senior-implementor.md skills/canonical-sdlc/steps/0.md agents-src/templates/skills/canonical-sdlc/steps/0.md.tmpl skills/canonical-sdlc/steps/5.md agents-src/templates/skills/canonical-sdlc/steps/5.md.tmpl skills/canonical-sdlc/steps/7.md agents-src/templates/skills/canonical-sdlc/steps/7.md.tmpl skills/canonical-sdlc/operational-rules.md payload/context/working-principles.md agents-src/templates/context/working-principles.md.tmpl hooks/dispatch-preflight.sh hooks/poker/tick.sh skills/sitrep/SKILL.md payload/scripts/card.sh payload/scripts/lib/cmd-class.sh payload/scripts/lib/git-argv.sh payload/scripts/lib/grant.sh payload/scripts/lib/plan-read.sh skills/canonical-sdlc/SKILL.md agents-src/templates/skills/canonical-sdlc/SKILL.md.tmpl skills/canonical-sdlc/steps/2.md agents-src/templates/skills/canonical-sdlc/steps/2.md.tmpl skills/canonical-sdlc/steps/3.md agents-src/templates/skills/canonical-sdlc/steps/3.md.tmpl

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
payload/context/working-principles.md agents-src/templates/context/working-principles.md.tmpl|Write for a reader with no context|whoever reads a message, not a review
payload/context/working-principles.md agents-src/templates/context/working-principles.md.tmpl|The reader has not seen your tool calls|whoever reads a message, not a review
hooks/poker/tick.sh|the panel reading is|a reading of the agent panel, a measurement, not a review
hooks/session-poker.sh|Lands-red from the reader;|the program that answers from the run's log, not a review
hooks/session-poker.sh|printed from the reader and never typed|the program that answers from the run's log, not a review
hooks/poker/line.sh|the reader (lib/reader.sh) cannot be loaded|the program that answers from the run's log, named by its file, not a review
hooks/poker/line.sh|or the reader (lib/reader.sh) that reads them|the program that answers from the run's log, named by its file, not a review
hooks/poker/line.sh|line_kv("reader")|the proof line's reader= field, read by its name
payload/scripts/lib/proof.sh|p["reader"]|the proof line's reader= field, read by its name
skills/sitrep/SKILL.md|never "reading" or "reader"|names the refused words, to refuse them
payload/scripts/card.sh|(readers?|readings?|unmeasured)|the judgment check's pattern of the refused words
WORDS_ALLOW_EOF

# ── the surfaces ─────────────────────────────────────────────────────────────
# words_surfaces <root> — every file the lint reads, one path from <root> per line.
words_surfaces() {
  (
    cd "$1" || exit 1
    ls skills/canonical-sdlc/*.md skills/canonical-sdlc/steps/*.md skills/handoff/*.md skills/sitrep/*.md payload/commands/*.md agents/*.md agents-src/blocks/*.md \
      agents-src/templates/*.tmpl agents-src/templates/commands/*.tmpl agents-src/templates/skills/canonical-sdlc/*.tmpl \
      agents-src/templates/skills/canonical-sdlc/steps/*.tmpl agents-src/templates/context/*.tmpl payload/context/*.md \
      payload/scripts/lib/plan.sh payload/scripts/lib/proof.sh payload/scripts/lib/walls.sh payload/scripts/lib/units.sh \
      payload/scripts/lib/dispatch.sh hooks/dispatch-preflight.sh hooks/session-poker.sh hooks/poker/*.sh payload/scripts/card.sh 2>/dev/null
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
# cannot be the word; nor can a program's file name (`reader.sh`), bare or as a path component.
words_refused() {
  awk '{
    c = index($0, "\t"); tag = substr($0, 1, c - 1); t = substr($0, c + 1)
    l = t; gsub(/\$\{[A-Za-z_][A-Za-z0-9_]*\}/, "$V", l); gsub(/\$\{[A-Za-z_][A-Za-z0-9_]*[:#%\/+=?-]+/, "$V ", l)
    gsub(/\$[A-Za-z_][A-Za-z0-9_]*/, "$V", l); l = tolower(l); gsub(/readers?\.sh/, "$V", l)
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
  'hooks/session-poker.sh' 'payload/scripts/card.sh' 'hooks/dispatch-preflight.sh' 'payload/scripts/lib/plan.sh' 'payload/scripts/lib/proof.sh' 'payload/scripts/lib/walls.sh' 'payload/scripts/lib/units.sh' 'payload/scripts/lib/dispatch.sh'; do
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
expect_eq "a program's file name is no word: a line naming reader.sh passes, the bare word beside it is refused" "t2 the reader said so" \
  "$(printf 't1\t. "$lib/reader.sh" && x=lib/reader.sh\nt2\tthe reader said so\n' | words_refused)"

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
wr_row() { printf '| %s | %s | build | %s · complexity: standard | %s | 30 | REQ-1 | lib/%s.sh | — |\n' "$1" "$2" "$3" "$4" "$1"; }   # <id> <step> <task> <deps>, its state the log's
{
  printf -- '---\nwave: wave-02-fx\ncanonical_sdlc_version: 15\nrelease: 9.9.0\nworking-branch: wave/02-fx\nintegration-branch: main\nforecast: 8h\n'
  printf 'goals: owed · the user says what they owe (record/owed-test.md)\n---\n# fixture plan\n'
  printf '\n## Tasks\n\n| id | step | kind | task | deps | size | serves | Files | artifact |\n|---|---|---|---|---|---|---|---|---|\n'
  wr_row T1 4 "The first row" —; wr_row T2 4 "The second row" —
  wr_row T3 8 "Merge it" "approval:release"
  printf '\n## Not Doing\n\n- nothing\n'
} > "$WR_P"
{ printf 'run/v1|ev=approval|key=step3|by=fixture|said=approved|at=2026-10-06T16:00:00Z\nrun/v1|ev=step|n=4|at=2026-10-06T16:00:00Z\n'   # the run's log: its approval and step, T1's landing, T2's launch and the open ask
  printf 'run/v1|ev=published|row=T1|commit=%s|kind=queue|by=-|why=-|at=2026-10-06T18:00:00Z\n' "$(printf 'c%.0s' $(seq 40))"
  printf 'run/v1|ev=dispatch|row=T2|name=w-T2|at=2026-10-06T18:30:00Z\n'
  printf 'run/v1|ev=ask|key=approve:release|sent=-|title=approval: release|at=2026-10-06T20:00:00Z\n'; } > "$WR_R/.bionic/docs/record/wave-02-fx/run.log"
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
expect_eq "RD1 the sitrep card is drawn (exit 0) and holds the open approval under Blocked on you" "0|1" "$WR_RC|$(/usr/bin/grep -c '^    • The release approval, which holds 8/3' "$TMP/rendered/card.txt")"
wr_poke sitrep --line "$WR_P" > "$TMP/rendered/line.txt"
expect_eq "RD2 the Patrol line is drawn (exit 0): one line, the approval owed" "0|1|1" "$WR_RC|$(/usr/bin/grep -c . "$TMP/rendered/line.txt")|$(/usr/bin/grep -c ' tasks · owed: 1 on you · 0 on events · close ' "$TMP/rendered/line.txt")"
wr_poke handoff > /dev/null <<'WR_HANDOFF_EOF'
Summary
- Doing: the fixture run.
- Learned: nothing new.
- Open: none.
- First: land T2.
WR_HANDOFF_EOF
WR_HF="$(ls "$WR_R/.bionic/docs/record/handoffs/"*.md 2>/dev/null | head -1)"
awk 'NR > 1 && $0 == "" { exit } NR > 1 { print }' "$WR_HF" > "$TMP/rendered/head.txt" 2>/dev/null
expect_eq "RD3 the handoff head is drawn (exit 0): the title, the run line, Blocked on you: yes and the approval's line" "0|1|1|1" "$WR_RC|$(/usr/bin/grep -c ' tasks · owed: 1 on you · 0 on events · close ' "$TMP/rendered/head.txt")|$(/usr/bin/grep -cx 'Blocked on you: yes' "$TMP/rendered/head.txt")|$(/usr/bin/grep -c '^- approval: release — holds ' "$TMP/rendered/head.txt")"
for wr_s in card line head; do
  expect_nonempty "$wr_s: the lint reads the rendered text (the extractor reads the real output)" "$(words_text "$TMP/rendered/$wr_s.txt")"
  expect_empty "$wr_s: no refused word on it" "$(words_hits "$TMP/rendered/$wr_s.txt" "rendered/$wr_s.txt")"
  cp "$TMP/rendered/$wr_s.txt" "$TMP/rendered/$wr_s.plant.txt"
  printf '%s\n' '    • PLANT no reader for the goal' >> "$TMP/rendered/$wr_s.plant.txt"
  expect_contains "$wr_s: a planted \"no reader for\" on it is refused" "PLANT no reader for" "$(words_hits "$TMP/rendered/$wr_s.plant.txt" "rendered/$wr_s.txt")"
done


# ── §BIND ────────────────────────────────────────────────────────────────────
section "§BIND: over the same fixture run, a judgment that sets 1 green and 3 red over a sheet of 3 green and 1 red is refused, not drawn"

# The rendered texts above are read for refused words; a card the judgment filled with the wrong number beside a word
# the sheet places is a wrong card with no refused word in it, so the same run is given a suite line of its own and the
# card verb is asked the swap. The run's log holds four suites by their last verdict, three green and one red.
# fails-when: the swap draws, the control in the sheet's order is refused, or the refusal leaves the card on stdout.
WR_REC="$WR_R/.bionic/docs/record/wave-02-fx/run.log"
mkdir -p "${WR_REC%/*}"
for wr_k in "a green" "b green" "c green" "d red"; do
  printf 'run/v1|ev=verdict|row=T1|commit=%s|suite=%s.test.sh|result=%s|log=/rec/%s.log|at=2026-10-06T18:00:00Z\n' "$(printf 'c%.0s' $(seq 40))" "${wr_k%% *}" "${wr_k##* }" "${wr_k%% *}" >> "$WR_REC"
done
wr_poke sitrep "$WR_P" > "$TMP/wr-sheet"
expect_eq "BN0 precondition: the sheet holds 3 green and 1 red on one line" "1" "$(/usr/bin/grep -c '^tests.suites-run: 4: 3 green, 1 red ' "$TMP/wr-sheet")"
wr_bind() {  # <the point> -> the card verb's stdout over the sheet; WR_RC, and stderr in $TMP/wr.err
  wr_poke sitrep card "$WR_P" <<< "$(printf '%s\n' 'purpose: the first row lands and the release goes out; on course.' 'call: Approve the release once 4/2 lands.' 'grade: C' "point: $1" 'ask approve:release: The release approval, which holds 8/3 — recommend approve once 4/2 lands' 'close: if 4/2 lands first time.')"
}
wr_bind "3 suites green and 1 red." > "$TMP/rendered/bind-ok.txt"
expect_eq "BN1 control: the point in the sheet's order draws (exit 0) with its numbers on the card" "0|1" "$WR_RC|$(/usr/bin/grep -c '3 suites green and 1 red' "$TMP/rendered/bind-ok.txt")"
wr_bind "1 suite green and 3 red." > "$TMP/rendered/bind-swap.txt"
expect_eq "BN2 the swap is refused (exit 1) and nothing is drawn" "1|0" "$WR_RC|$(/usr/bin/grep -c . "$TMP/rendered/bind-swap.txt")"
expect_contains "BN2b …naming each number beside the word it does not stand by" 'says 1 beside "green"' "$(cat "$TMP/wr.err")"
expect_contains "BN2c …and the other" 'says 3 beside "red"' "$(cat "$TMP/wr.err")"

# ── §GONE ────────────────────────────────────────────────────────────────────
section "§GONE: no file of the loaded set names a deleted plan section as a part of a plan; a plant on a copy goes red"

# The set is payload/scripts/lib/walls.sh `loaded_set`, the net-zero wall's list, read by sourcing it, never retyped.
# fails-when: a file of the set says "verification matrix" in any case, "ledger rows in the plan" or "Step-5 block",
# or the search reads none of the set, so the planted copy passes.
gone_hits() { ( cd "$1" && . "$REPO/payload/scripts/lib/walls.sh" >/dev/null 2>&1 && /usr/bin/grep -n -i -E "${2:-verification matrix|ledger rows in the plan}" $(loaded_set) /dev/null ); }
GONE_SET="$(cd "$REPO" && . payload/scripts/lib/walls.sh >/dev/null 2>&1 && printf '%s\n' $(loaded_set))"
while IFS= read -r f; do mkdir -p "$TMP/gone/${f%/*}" && cp "$REPO/$f" "$TMP/gone/$f"; done <<< "$GONE_SET"
printf '\nPLANT-1 the Verification Matrix.\n' >> "$TMP/gone/skills/canonical-sdlc/SKILL.md"; printf '\nPLANT-2 ledger rows in the plan.\n' >> "$TMP/gone/agents/implementor.md"; printf '\nPLANT-3 in the Step-5 block.\n' >> "$TMP/gone/skills/canonical-sdlc/steps/5.md"
expect_eq "GN1 the set is read: more than 20 members, each a file" "yes|0" "$([ "$(printf '%s\n' "$GONE_SET" | /usr/bin/grep -c .)" -gt 20 ] && echo yes)|$(while IFS= read -r f; do [ -f "$REPO/$f" ] || echo "$f"; done <<< "$GONE_SET" | /usr/bin/grep -c .)"
expect_eq "GN2 the planted copy of the set is refused at both plants" "2" "$(gone_hits "$TMP/gone" | /usr/bin/grep -c 'PLANT-[12]')"
expect_empty "GN3 the shipped set names neither (the same search over the files the copy was made from)" "$(gone_hits "$REPO")"
expect_eq "GN4 the planted Step-5 block is found, and the shipped set names none" "1|" "$(gone_hits "$TMP/gone" 'step-5 block' | /usr/bin/grep -c PLANT-3)|$(gone_hits "$REPO" 'step-5 block')"

# ── §PAGES ───────────────────────────────────────────────────────────────────
section "§PAGES: the rendered pages teach the verbs a run uses today"

# Each row reads a page as shipped. A page that names a verb only on a page nothing loads, or in a retired form, is a
# page a run cannot learn the verb from, so the sentence is read where the run loads it. An absence is read beside the
# presence of the line it is read from, so a renamed line cannot pass it.
# fails-when: the dispatch page or the Step 4 page does not name `session-poker.sh start`; the dispatch page does not
# name `check-from`, or does not say the rule verb grants files and suites; none of the Step 6, 7 and 8 pages says a
# carried finding's sentence is stated before the release card; the rules page does not name steps/9.md, or still sends
# the reader to SKILL.md for the terminal-disposition rule; the scaffold's Row: comment names a push; the opening line
# spells the rigor as required.
PG_DIR="$REPO/skills/canonical-sdlc"
pg_has() { /usr/bin/grep -c -F -- "$2" "$PG_DIR/$1" || true; }
expect_nonempty "PG0 the pages are read: dispatch.md, steps/4.md, steps/6.md, steps/7.md, steps/8.md, SKILL.md and operational-rules.md exist" "$(for f in dispatch.md steps/4.md steps/6.md steps/7.md steps/8.md SKILL.md operational-rules.md; do [ -s "$PG_DIR/$f" ] && printf y; done | /usr/bin/grep -x yyyyyyy)"
expect_ne "PG1 the dispatch page names session-poker.sh start" "0" "$(pg_has dispatch.md 'session-poker.sh start')"
expect_ne "PG1b the Step 4 page names session-poker.sh start" "0" "$(pg_has steps/4.md 'session-poker.sh start')"
expect_ne "PG2 the dispatch page names check-from" "0" "$(pg_has dispatch.md 'check-from')"
expect_ne "PG2b the dispatch page says the rule verb grants files and suites (session-poker.sh rule … --files+ … --suites+ on one line)" "0" "$(/usr/bin/grep -c -E 'session-poker\.sh rule .*--files\+.*--suites\+' "$PG_DIR/dispatch.md" || true)"
expect_ne "PG3 one of the Step 6, 7 and 8 pages says a carried finding's sentence is stated before the release card (finding-move … stated)" "0" "$(/usr/bin/grep -c -E 'finding-move <record>#<n> stated' "$PG_DIR/steps/6.md" "$PG_DIR/steps/7.md" "$PG_DIR/steps/8.md" | awk -F: '{s+=$2} END{print s+0}')"
expect_ne "PG4 the rules page names steps/9.md" "0" "$(pg_has operational-rules.md 'steps/9.md')"
expect_eq "PG4b …and the page it names holds the terminal-disposition rule (the control for the absence below)" "1" "$(/usr/bin/grep -c -F 'TERMINAL-DISPOSITION-BEGIN' "$REPO/skills/canonical-sdlc/steps/9.md" | awk '{print ($1>0)}')"
expect_eq "PG4c …and the rules page no longer says SKILL.md §Step 9 carries it" "0" "$(pg_has operational-rules.md 'SKILL.md §Step 9 carries')"
PG_ROW="$(/usr/bin/grep -E -- '^Row: <id>' "$PG_DIR/dispatch.md" | head -1)"
expect_nonempty "PG5 the scaffold's Row: line is read from the dispatch page" "$PG_ROW"
expect_eq "PG5b …and it names no push or pull request" "0" "$(printf '%s\n' "$PG_ROW" | /usr/bin/grep -c -E 'push|gh pr create' || true)"
PG_OPEN="$(/usr/bin/grep -F -- 'card.sh opening' "$PG_DIR/SKILL.md" | head -1)"
expect_nonempty "PG6 the opening line is read from SKILL.md" "$PG_OPEN"
expect_eq "PG6b …and it spells the rigor as optional, never as required" "1|0" "$(printf '%s\n' "$PG_OPEN" | /usr/bin/grep -c -F 'card.sh opening [<rigor>' || true)|$(printf '%s\n' "$PG_OPEN" | /usr/bin/grep -c -F 'card.sh opening <rigor>' || true)"

# ── §TEST-WORD ───────────────────────────────────────────────────────────────
section "§TEST-WORD: the cards, their views and refusals, and every line the hooks and scripts print call a check a test"

# A check is a test: deterministic, it passes or it fails. "Eval" names a test of a model, which bionic does not write,
# so no surface the tool prints may call a criterion's check one. The cards are drawn through the real verb over a
# SYNTHESIZED spec and plan, each in the shipped shape, the spec written once in the new words and once in the old,
# since a page written before the rename must draw the same card. The printed lines are read in place.
# fails-when: the card, a reply word, a refusal or a report prints the old word for a check.
tw_word() { awk '{ l = tolower($0); if (l ~ /(^|[^a-z0-9_$-])evals?([^a-z0-9_=-]|$)/) print }'; }   # lines naming the old word
tw_new() { awk '{ l = tolower($0); if (l ~ /(^|[^a-z0-9_$-])tests?([^a-z0-9_=.-]|$)/) print }'; }   # lines naming the new word
expect_eq "TW0 the two extractors tell the words apart: each finds its own line and not the other's" "show evals <req>|show tests <req>" \
  "$(printf 'show evals <req>\nshow tests <req>\nevaluate it\n' | tw_word)|$(printf 'show evals <req>\nshow tests <req>\ntests.sh\n' | tw_new)"
TW="$TMP/tw"; mkdir -p "$TW"
tw_spec() {  # <file> <heading> <type column> <check column>
  {
    printf -- '---\nsdlc-step: 2\nworking-branch: wave/99-tw\nintegration-branch: main\nbase-sha: abc1234\n---\n\n# fixture wave 99 · spec\n\n'
    printf '## Goal\n\nAnswer one requirement with a design small enough to read whole.\n\n## Design\n\n'
    printf '### 2. Component boundaries and interfaces\n\n- **`lib/first.sh`** The first file owns the first thing. (D1; REQ-1)\n\n'
    printf '### 3. Ownership table\n\n| concept | owning module (SSoT) | rendering surfaces | agreement test |\n|---|---|---|---|\n'
    printf '| first thing | `lib/first.sh` | `card.sh` rows | `tests/first.test.sh` |\n\n'
    printf '## %s\n\n| Requirement | Approach | Criterion | %s | %s | Fails when |\n|---|---|---|---|---|---|\n' "$2" "$3" "$4"
    printf '| REQ-1 | a fixture run | AC-1.1 the first criterion | hermetic | `bash tests/first.test.sh` | it reds |\n'
    printf '| REQ-1 | a fixture run | AC-1.2 the second criterion | unit | `bash tests/second.test.sh` | it reds |\n'
  } > "$1"
}
tw_card() {  # <args to card.sh…> -> TW_OUT, TW_ERR, TW_RC
  TW_RC=0
  bash "$REPO/payload/scripts/card.sh" "$@" > "$TW/out" 2> "$TW/err" 0<&- || TW_RC=$?
  TW_OUT="$(cat "$TW/out")"; TW_ERR="$(cat "$TW/err")"
}
tw_spec "$TW/new.spec.md" 'Test design' 'Test type' Test; tw_spec "$TW/old.spec.md" 'Eval design' 'Eval type' Eval
for tw_w in new old; do
  tw_card step2 "$TW/$tw_w.spec.md"
  expect_eq "TW1 $tw_w words: the Step 2 card draws (exit 0), headed Test design over the type labels" "0|1" \
    "$TW_RC|$(printf '%s\n' "$TW_OUT" | /usr/bin/grep -c '^  Test design  *static  *unit  *hermetic  *live  *human$' || true)"
  expect_eq "TW1b $tw_w words: …and its last line offers show tests <req>" "show tests <req> · explain <decision> · show ownership" "$(printf '%s\n' "$TW_OUT" | tail -1)"
  expect_nonempty "TW1c $tw_w words: …the new word is on the card (the control for the absence below)" "$(printf '%s\n' "$TW_OUT" | tw_new)"
  expect_empty "TW1d $tw_w words: …and the old word is not" "$(printf '%s\n' "$TW_OUT" | tw_word)"
  tw_card step2 "$TW/$tw_w.spec.md" tests REQ-1
  expect_eq "TW2 $tw_w words: the tests view of a requirement draws (exit 0), titled Test design · REQ-1" "0|  Test design · REQ-1" "$TW_RC|$(printf '%s\n' "$TW_OUT" | head -1)"
  expect_eq "TW2b $tw_w words: …each criterion's check under the label test" "2" \
    "$(printf '%s\n' "$TW_OUT" | /usr/bin/grep -c '^      test  *bash tests/[a-z]*\.test\.sh$' || true)"
  expect_empty "TW2c $tw_w words: …and the old word is not on the view" "$(printf '%s\n' "$TW_OUT" | tw_word)"
done
tw_card step2 "$TW/new.spec.md" bogus
expect_eq "TW3 an unknown view is refused (exit 2), naming the tests form among the valid ones" "2|1" "$TW_RC|$(printf '%s\n' "$TW_ERR" | /usr/bin/grep -c -F 'step2 <spec> tests <REQ-id> (REQ-id: REQ-1)' || true)"
TW_REF="$TW_ERR"
tw_card step2 "$TW/new.spec.md" tests
expect_eq "TW3b the tests view with no id is refused (exit 2) in the new word" "2|1" "$TW_RC|$(printf '%s\n' "$TW_ERR" | /usr/bin/grep -c 'tests takes one requirement id' || true)"
TW_REF="$TW_REF"$'\n'"$TW_ERR"
tw_card step2 "$TW/new.spec.md" tests REQ-9
expect_eq "TW3c a requirement the table lacks is refused (exit 2), naming the Test design" "2|1" "$TW_RC|$(printf '%s\n' "$TW_ERR" | /usr/bin/grep -c "no requirement 'REQ-9' in the Test design" || true)"
TW_REF="$TW_REF"$'\n'"$TW_ERR"
sed -e '/^## Test design$/,$d' "$TW/new.spec.md" > "$TW/none.spec.md"
tw_card step2 "$TW/none.spec.md"
expect_eq "TW3d a wave spec with no table is refused (exit 64), naming the new heading" "64|1" "$TW_RC|$(printf '%s\n' "$TW_ERR" | /usr/bin/grep -c -F 'the spec has no ## Test design table' || true)"
TW_REF="$TW_REF"$'\n'"$TW_ERR"
sed -e 's/| REQ-1 | a fixture run | AC-1.2/| REQ-1 | a second run | AC-1.2/' "$TW/new.spec.md" > "$TW/two.spec.md"
tw_card step2 "$TW/two.spec.md"
expect_eq "TW3e a second approach is refused (exit 64), naming the row as a Test design row" "64|1" "$TW_RC|$(printf '%s\n' "$TW_ERR" | /usr/bin/grep -c -F 'Test design row REQ-1 AC-1.2: a second approach for REQ-1' || true)"
TW_REF="$TW_REF"$'\n'"$TW_ERR"
expect_empty "TW3f …and none of those refusals names the old word" "$(printf '%s\n' "$TW_REF" | tw_word)"
tw_card step2 "$TW/new.spec.md" evals REQ-1
expect_eq "TW3g the old view word is no view: refused (exit 2), with the tests form named" "2|1" "$TW_RC|$(printf "%s\n" "$TW_ERR" | /usr/bin/grep -F "unknown sub-view 'evals'" | /usr/bin/grep -c -F "step2 <spec> tests <REQ-id>" || true)"
{
  printf -- '---\nsdlc-step: 3\nwalk: required\nrigor: double\ncanonical_sdlc_version: 15\nworking-branch: wave/99-tw\nintegration-branch: main\nbase-sha: abc1234\n---\n\n# fixture wave 99 · plan\n\n'
  printf '## Goal\n\nLand the one requirement.\n\n## Tasks\n\n| id | step | kind | task | deps | size | serves | Files | artifact |\n|---|---|---|---|---|---|---|---|---|\n'
  printf '| T1 | 4 | build | REQ-1: the first task. It has its own sentence. complexity: standard | — | 30 | REQ-1 | lib/first.sh | — |\n\n'
  printf '## Test design\n\n| Requirement | Approach | Criterion | Test type | Test | Fails when |\n|---|---|---|---|---|---|\n'
  printf '| REQ-1 | fixture | AC-1.1 | hermetic | `tests/a.test.sh` | it is wrong |\n'
} > "$TW/tw.plan.md"
tw_card step3 "$TW/tw.plan.md"
expect_eq "TW4 the Step 3 card draws (exit 0) and its last line offers only the views it takes" "0|show task <n> · explain <decision>" "$TW_RC|$(printf '%s\n' "$TW_OUT" | tail -1)"
expect_empty "TW4b …and offers no view of the checks, by either word" "$(printf '%s\n' "$TW_OUT" | tail -1 | tw_word)"

# THE PRINTED LINES. Every shell file of the hooks and the scripts, read as §TEXTS reads one: a comment is cut, every
# printed string and every line of code is read. The shell builtin is the same four letters, so `eval` as a command, the
# word followed by a quoted or expanded argument, passes; a line naming it any other way, or reading the old heading of
# a page written before the rename, is answered by an allow entry, which must still match its line (TW6).
TW_ALLOW="$TMP/tw-allow"
cat > "$TW_ALLOW" <<'TW_ALLOW_EOF'
payload/scripts/lib/cmd-class.sh|exec|eval|source|if|the builtin, named among the words that move or replace the shell
payload/scripts/lib/cmd-class.sh|match(h, /^eval[ \t]+/)|the builtin, matched at the head of a command
payload/scripts/lib/cmd-class.sh|A[1] == "eval"|the builtin, matched as a command's first word
payload/scripts/lib/cmd-class.sh|if (b == "eval") { fx_unk("eval runs text|the builtin, named in the class of a command it cannot read
payload/scripts/lib/git-argv.sh|exec|eval|source)|the builtin, named among the words that move or replace the shell
payload/scripts/lib/git-argv.sh|    eval)|the builtin, matched as a command's first word
payload/scripts/lib/grant.sh|ash|eval|env)|the builtin, named among the runners of a text
payload/scripts/card.sh|h == "Eval design"|the old heading, read so a page written before the rename still draws
payload/scripts/lib/plan-read.sh|PLAN_READ_CRITERIA='Test design|Eval design'|the old heading, read so a page written before the rename still reads
payload/scripts/lib/plan-read.sh|(k == "eval") ?|the old column, mapped to its key so a page written before the rename still reads
TW_ALLOW_EOF
tw_hits() {  # <file> <path from the repo root> -> "<path>:<line>: <text>" for each line naming the old word, its allow entries cut
  words_text "$1" | awk -F'\t' -v rel="$2" -v allow="$TW_ALLOW" '
    BEGIN {
      while ((getline e < allow) > 0) {
        p = index(e, "|"); if (!p) continue
        rest = substr(e, p + 1); q = 0
        for (j = length(rest); j > 0; j--) if (substr(rest, j, 1) == "|") { q = j; break }
        if (q < 2 || substr(e, 1, p - 1) != rel) continue
        n++; A[n] = substr(rest, 1, q - 1)
      }
    }
    {
      t = $0; sub(/^[0-9]+\t/, "", t)
      for (i = 1; i <= n; i++) while ((c = index(t, A[i])) > 0) t = substr(t, 1, c - 1) substr(t, c + length(A[i]))
      gsub(/(^|[^a-zA-Z0-9_$-])eval[ \t]+["\047$]/, " ", t)
      l = tolower(t)
      if (l ~ /(^|[^a-z0-9_$-])evals?([^a-z0-9_=-]|$)/) printf "%s:%s:\t%s\n", rel, $1, t
    }'
}
TW_SH="$(cd "$REPO" && ls hooks/*.sh hooks/poker/*.sh payload/scripts/*.sh payload/scripts/lib/*.sh 2>/dev/null)"
expect_eq "TW5 precondition: the printed lines are read from the hooks, the poker, the scripts and their libraries" "yes|yes|yes|yes" \
  "$(for d in 'hooks/[a-z-]*\.sh' 'hooks/poker/' 'payload/scripts/[a-z-]*\.sh' 'payload/scripts/lib/'; do printf '%s\n' "$TW_SH" | /usr/bin/grep -q "^$d" && printf yes; printf '|'; done | sed 's/|$//')"
TW_HITS=""
while IFS= read -r f; do TW_HITS="$TW_HITS$(tw_hits "$REPO/$f" "$f")"$'\n'; done <<< "$TW_SH"
expect_empty "TW5b no line the hooks and scripts print calls a check an eval" "$(printf '%s' "$TW_HITS" | /usr/bin/grep -v '^$' || true)"
mkdir -p "$TW/plant/payload/scripts/lib"; cp "$REPO/payload/scripts/lib/walls.sh" "$TW/plant/payload/scripts/lib/walls.sh"
printf '%s\n' 'die "PLANT the eval of this criterion cannot fire"' 'eval "$PLANT_BUILTIN"' >> "$TW/plant/payload/scripts/lib/walls.sh"
TW_PL="$(tw_hits "$TW/plant/payload/scripts/lib/walls.sh" payload/scripts/lib/walls.sh)"
expect_eq "TW5c a planted printed eval on a copy of walls.sh is refused, and the builtin planted beside it passes" "1|0" \
  "$(printf '%s\n' "$TW_PL" | /usr/bin/grep -c 'PLANT the eval' || true)|$(printf '%s\n' "$TW_PL" | /usr/bin/grep -c 'PLANT_BUILTIN' || true)"
while IFS= read -r e; do
  tw_p="${e%%|*}"; tw_s="${e#*|}"; tw_s="${tw_s%|*}"
  expect_true "TW6 allow entry '$tw_s': $tw_p still holds it" /usr/bin/grep -qF -- "$tw_s" "$REPO/$tw_p"
done < "$TW_ALLOW"

# ── §TEST-WORD-PAGES ─────────────────────────────────────────────────────────
section "§TEST-WORD-PAGES: the loaded pages define test and eval once each, teach the Test design and the card's reply words, and call no check an eval"

# The pages are the loaded set §GONE reads, as shipped. A page line is read whole but for its HTML comments, code spans
# included, because a reply word sits in one and a page that teaches `show evals` teaches a word the card refuses. Two
# sentences must name the old word: the definition, and the note that a page under the old words still reads. Each is
# cut from its line before the line is read, and each is counted over the whole set, so it is said exactly once. The
# reply lines the pages draw are compared with the lines the real card prints over §TEST-WORD's fixture spec and plan.
# fails-when: a page keeps the old word for a check, or a definition is missing.
TP_DEF='A test is deterministic: unit, integration, hermetic or end to end; an eval tests a model, which is not, so it passes by reaching a stated threshold a stated share of the time.'
TP_OLD='A page under the old words, `Eval design` with `Eval type` and `Eval`, still reads.'
tp_hits() {  # <root> -> "<path>:<line>:<text>" for each line of the set naming the old word, the two sentences cut
  local f
  while IFS= read -r f; do
    awk -v rel="$f" -v d="$TP_DEF" -v o="$TP_OLD" '{
      t = $0; gsub(/<!--([^-]|-[^-])*-->/, "", t)
      while ((c = index(t, d)) > 0) t = substr(t, 1, c - 1) substr(t, c + length(d))
      while ((c = index(t, o)) > 0) t = substr(t, 1, c - 1) substr(t, c + length(o))
      printf "%s:%d:%s\n", rel, NR, t }' "$1/$f" | tw_word
  done <<< "$GONE_SET"
}
tp_count() { ( cd "$1" && while IFS= read -r f; do cat "$f"; done <<< "$GONE_SET" ) | /usr/bin/grep -c -F -- "$2" || true; }   # <root> <sentence>
TP="$TMP/tp"
while IFS= read -r f; do mkdir -p "$TP/${f%/*}" && cp "$REPO/$f" "$TP/$f"; done <<< "$GONE_SET"
printf '\nPLANT-1 the eval of this criterion.\n' >> "$TP/skills/canonical-sdlc/steps/2.md"; printf '\nPLANT-2 reply `show evals <req>`.\n' >> "$TP/payload/context/checks-evidence.md"
expect_eq "TP0 the planted copy of the set is refused at both plants, the one in a code span too (the control for TP1)" "2" "$(tp_hits "$TP" | /usr/bin/grep -c 'PLANT-[12]' || true)"
expect_empty "TP1 no loaded page calls a check an eval (the same read over the shipped files)" "$(tp_hits "$REPO")"
expect_eq "TP2 the definition of test and eval is said once over the set, on the skill's main page" "1|1" "$(tp_count "$REPO" "$TP_DEF")|$(/usr/bin/grep -c -F -- "$TP_DEF" "$PG_DIR/SKILL.md" || true)"
expect_eq "TP2b the note that a page under the old words still reads is said once over the set" "1" "$(tp_count "$REPO" "$TP_OLD")"
expect_eq "TP3 the Step 2 page teaches the heading and its six columns" "1|1" \
  "$(pg_has steps/2.md 'flush-left `## Test design` table')|$(pg_has steps/2.md '| Requirement | Approach | Criterion | Test type | Test | Fails when |')"
expect_eq "TP3b the rules page heads its guidance The Test design table" "1" "$(pg_has operational-rules.md '### The Test design table')"
tw_card step2 "$TW/new.spec.md"; TP_C2="$(printf '%s\n' "$TW_OUT" | tail -1)"; TP_S2="$(printf '%s\n' "$TW_OUT" | /usr/bin/grep '^  Test design ' || true)"
TP_P2="$(/usr/bin/grep -E '^show [^`]* · explain <decision> · show ownership$' "$PG_DIR/steps/2.md" | head -1)"
expect_nonempty "TP4 the Step 2 page's card mock ends on a reply line" "$TP_P2"
expect_eq "TP4b …the line the Step 2 card prints" "$TP_C2" "$TP_P2"
expect_eq "TP4c …and the mock's section line is the card's, headed Test design over the type labels" "1" "$(pg_has steps/2.md "$TP_S2")"
expect_ne "TP4d the Step 2 page names the view's command form, … tests <REQ>" "0" "$(pg_has steps/2.md '`… tests <REQ>`')"
tw_card step3 "$TW/tw.plan.md"; TP_C3="$(printf '%s\n' "$TW_OUT" | tail -1)"
TP_P3="$(/usr/bin/grep -E '^show [^`]*explain <decision>$' "$PG_DIR/steps/3.md" | head -1)"
expect_nonempty "TP5 the Step 3 page's card mock ends on a reply line" "$TP_P3"
expect_eq "TP5b …the line the Step 3 card prints" "$TP_C3" "$TP_P3"

# ── §EXIT-PAGES ──────────────────────────────────────────────────────────────
section "§EXIT-PAGES: no page or role file names a non-zero exit for an answer that exits 0; the suite line carries the meant-to-fail word"

# A clause (cut at ; and at a full stop) that names an ordinary answer and a non-zero exit code is refused, and so is
# "exits as the advance would". The record's codes (a stamp's 75, the landing's STALLED 70, a red landing's 1) sit in
# clauses that name no ordinary answer, so they pass; the controls below prove that. The plants are put on copies.
# fails-when: a page or role file says a WAITING, a run the gate did not admit, a checked advance or the judge, a
# NOTIFY tick, an early card or a held close exits with a code other than 0; or the suite line loses the leading word.
EX_ANS='WAITING|BUSY|NOTIFY|CARD-EARLY|admit|--check|judge|close-out refused|not merged'
ex_hits() {  # <root> -> "<path>: <clause>" for each refused clause of the rendered pages and role files
  local f
  while IFS= read -r f; do
    awk -v rel="$f" -v ans="$EX_ANS" '/^[ ]*(- |#|$)/ { t = t ";" } { t = t " " $0 }
      END { n = split(t, c, /;|\. /)
        for (i = 1; i <= n; i++) if ((c[i] ~ ans && c[i] ~ /exit(s|ed)?( code| status)? [1-9]/) || c[i] ~ /exits? as the advance/) printf "%s: %s\n", rel, c[i] }' "$1/$f"
  done < <(words_surfaces "$1" | /usr/bin/grep -E '^(skills|agents|payload)/.*[.]md$')
}
EXP="$TMP/exp"
for f in skills/canonical-sdlc/dispatch.md payload/context/survival.md; do mkdir -p "$EXP/${f%/*}" && cp "$REPO/$f" "$EXP/$f"; done
printf '\nPLANT-1 `WAITING <row>` (exit 75, its place kept).\n' >> "$EXP/skills/canonical-sdlc/dispatch.md"
printf '\nPLANT-2 a command the gate does not admit exits 75 with the line to run again.\n' >> "$EXP/payload/context/survival.md"
expect_eq "EX0 the planted copies are refused at both plants (the control for EX1)" "2" "$(ex_hits "$EXP" | /usr/bin/grep -c 'PLANT-[12]' || true)"
expect_empty "EX1 no shipped page or role file names a refused exit" "$(ex_hits "$REPO")"
expect_nonempty "EX2 the pages are read: the dispatch page, every role file and the survival text are in the set" "$(words_surfaces "$REPO" | /usr/bin/grep -c -E '^(skills/canonical-sdlc/dispatch|payload/context/survival|agents/[a-z-]+)[.]md$' | /usr/bin/grep -x 8 || true)"
expect_eq "EX3 the codes that are still true stay on the dispatch page: a red landing's 1 and a stall's 70" "1|1" \
  "$(/usr/bin/grep -c -F '(exit 1, the row back' "$PG_DIR/dispatch.md" || true)|$(/usr/bin/grep -c -F '(exit 70)' "$PG_DIR/dispatch.md" || true)"
EX_WORD='BIONIC_EXPECT=red tests/run.sh --only'
for f in skills/canonical-sdlc/dispatch.md payload/context/survival.md agents/implementor.md agents/senior-implementor.md; do
  expect_eq "EX4 $f teaches the word on the suite segment itself, never on the cd" "1|0" \
    "$(/usr/bin/grep -c -F -- "$EX_WORD" "$REPO/$f" | awk '{print ($1>0)}')|$(/usr/bin/grep -c -E 'BIONIC_EXPECT=red +cd ' "$REPO/$f" || true)"
done

# ── §NONE-EXITS-0 ────────────────────────────────────────────────────────────
section "§NONE-EXITS-0: the dispatch page and each of the six role files hold the rule that a check expecting no match ends with || true"

# The rule is one line carrying both its words. The plant is a copy of each file with that line cut, so the count falls
# from one to none, which proves the count reads the rule and not some other line.
# fails-when: the dispatch page or a role file lacks the line.
NE_FILES="skills/canonical-sdlc/dispatch.md agents/auditor.md agents/critic.md agents/implementor.md agents/researcher.md agents/senior-implementor.md agents/test-runner.md"
ne_count() { /usr/bin/grep -c -E 'expects no match.*[|][|] true' "$1" || true; }   # <file>
NEP="$TMP/nep"
for f in $NE_FILES; do
  mkdir -p "$NEP/${f%/*}"; /usr/bin/grep -v -E 'expects no match.*[|][|] true' "$REPO/$f" > "$NEP/$f"
  expect_eq "NE $f holds the rule, and the copy with its line cut holds none" "1|0" "$(ne_count "$REPO/$f")|$(ne_count "$NEP/$f")"
done

finish
