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
# §DIGIN and §REFERENT plant whole briefs and read them through the same extractor: a reply line
# carries its dig-in command and nothing follows it; the context names the thing it is about.
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
HEADING='**D<n> · <what is decided, in a few words>**'
KINDS='How a rule is enforced|How a shared resource is shared|What a wave builds'
# The skill's size cap: raised to carry the worked pairs and the put command.
SIZE_CAP=11000
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

# reply_tail <file> -> the layout's last non-blank line: where a brief ends.
reply_tail() { layout "$1" | sed '/^[[:space:]]*$/d' | tail -1; }

# reply_last_ok <file> — the layout's last non-blank line is the reply line, byte for byte.
# Bash string equality, never awk `==`: the line carries a multibyte middle dot.
reply_last_ok() {
  local last
  last="$(reply_tail "$1")"
  [ "$last" = "$REPLY_LINE" ]
}

# DIGIN_ERE — a reply line that carries its dig-in: the option numbers and any forms, then one
# command in backticks after "to see <the thing>:", and the line ends on it.
DIGIN_ERE='^Reply [0-9][^`]* · to see [^:`]+: `(git show [0-9a-f]{7,40}|show task [0-9]+|show finding [^ `#]+#[0-9]+)`$'

# digin_ok <file> — a brief about a specific thing ends on a reply line carrying its dig-in
# command, so a line after the reply line, or a reply line without the command, fails. The brief
# is read the way the shipped shape is: its first text fence, through reply_tail.
digin_ok() {
  grep -qE "$DIGIN_ERE" <<<"$(reply_tail "$1")"
}

# digin_kind <file> -> what the reply line's command shows: commit, task or finding.
digin_kind() {
  case "$(reply_tail "$1" | sed -E 's/.*`([^`]+)`$/\1/')" in
    'git show '*)     echo commit ;;
    'show task '*)    echo task ;;
    'show finding '*) echo finding ;;
  esac
}

# context_of <file> -> the context paragraph: the non-blank lines between the Goal line and the
# first option (the Options label, or the first numbered option when the label is elided).
context_of() {
  layout "$1" | awk '/^\*\*Goal:\*\*/ { g = 1; next } g && (/^\*\*Options:\*\*/ || /^[0-9]+\. /) { exit } g && NF { print }'
}

# referent_ok <file> — the context is present and names the kind of thing the dig-in command
# shows (the commit, the task, the finding): a context that only says "a change you ordered"
# leaves the reader asking which one.
referent_ok() {
  local ctx kind
  ctx="$(context_of "$1")"; kind="$(digin_kind "$1")"
  [ -n "$ctx" ] && [ -n "$kind" ] || return 1
  grep -qiw "$kind" <<<"$ctx"
}

# context_rule_ok <file> — the skill rules the paragraph between Goal and Options: owed whenever
# the decision is about a specific thing, never pastes the artifact, and the dig-in is named in
# its three forms.
context_rule_ok() {
  grep -qi 'owed whenever the decision is about a specific thing' "$1" || return 1
  grep -qi 'never pastes the artifact' "$1" || return 1
  grep -qF 'git show <sha>' "$1" || return 1
  grep -qF 'show task <n>' "$1" || return 1
  grep -qF 'show finding <record>#<n>' "$1"
}

# altitude_scoped_ok <file> — every line that bars identifiers or research-style detail names the
# Goal as what it governs, so no line reads as barring them from the whole brief.
altitude_scoped_ok() {
  local bad
  bad="$(grep -iE 'identifiers|files, functions, tables and versions' "$1" | grep -vc 'Goal')"
  [ "$bad" = 0 ] && grep -qiE 'identifiers|files, functions, tables and versions' "$1"
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

# put_ok <file> — the put command is named, and the layout's Significance ends on the line it prints.
put_ok() {
  grep -qF "decisions put D<n> '" "$1" || return 1
  layout "$1" | grep -E '^\*\*Significance:\*\*' | grep -qi 'wait line'
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

# number_ok <file> — the layout opens on the numbered, named heading; the skill says the numbers run
# in the order asked and the name says what is decided. Bash string equality: the heading carries a
# multibyte middle dot. The step the decision is asked at is not on the heading: it told the reader
# nothing a name does not, and the name is what a transcript is scanned for.
number_ok() {
  local first
  first="$(layout "$1" | sed '/^[[:space:]]*$/d' | head -1)"
  [ "$first" = "$HEADING" ] || return 1
  grep -qi 'in one sequence, in the order asked' "$1" || return 1
  grep -qi 'a few plain words saying what is decided' "$1" || return 1
  ! grep -qF 'Step <s>' "$1"
}

# goal_ok <file> — the Goal is as long as clarity needs and no longer: one sentence when one carries
# it, a short paragraph after it when the problem must be stated first. A fixed length either way
# is the failure: a one-sentence cap buried the problem, and no cap invites the research back in.
goal_ok() {
  grep -qi 'as long as clarity needs and no longer' "$1" || return 1
  grep -qi 'one sentence when one carries it' "$1" || return 1
  grep -qi 'short plain paragraph after the goal explains the problem' "$1" || return 1
  ! grep -qi 'the goal is one sentence' "$1"
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


# ── a decision brief is read through the same extractor as the shape ─────────

# ACCEPTED_BRIEF — the brief the user accepted, as the ideas file writes it (its third version), the
# block-quote marks removed. Copied here so the suite owns its fixture; the drift row below reads
# the ideas file when it is present.
read -r -d '' ACCEPTED_BRIEF <<'BRIEF'
**Goal:** Decide whether the last change ships on your word or waits for a review.

The commit that removed the plan argument from the sitrep skill, landed on your ruling this morning, came after the critic's last review. Evidence provenance now requires every commit past a review to carry a review or your waiver, and this one has neither.

1. Waive on your word: the release moves now.
2. The critic reads it: about ten minutes, nothing of yours; the release waits.

**Recommendation:** Option 1, because a review earns its place only when it can fail in a way nothing already run can, and the suite that pins that text is green. Not 2: it spends a review to confirm a change you dictated.

**Significance:** None beyond this landing. Reversible in minutes.

Reply 1 or 2 · to see the change: `git show 3225216af`
BRIEF

# plant <name> <text> -> $TMP/<name>.md holding the text in a text fence, the form `layout` reads.
plant() { printf '```text\n%s\n```\n' "$2" > "$TMP/$1.md"; }

section "§DIGIN — the reply line carries the dig-in command, and nothing follows it"

IDEAS="${REPO}/.bionic/docs/ideas/decision-context.md"
if [ -f "$IDEAS" ]; then
  written="$(awk '/^> \*\*Goal:\*\* Decide whether the last change ships/ { on = 1 } on { print } on && /^> Reply 1 or 2/ { exit }' "$IDEAS" | sed -E 's/^> ?//')"
  expect_eq "DR-0: the embedded accepted text is the ideas file's third version, as written" "$written" "$ACCEPTED_BRIEF"
fi

plant accepted "$ACCEPTED_BRIEF"
expect_nonempty "DR-1: the extractor finds the accepted brief's layout" "$(layout "$TMP/accepted.md")"
expect_nonempty "DR-1b: …and its context paragraph" "$(context_of "$TMP/accepted.md")"

expect_true "DG-1: the accepted brief ends on a reply line carrying its command" digin_ok "$TMP/accepted.md"
expect_eq "DG-1b: …and the command shows a commit" "commit" "$(digin_kind "$TMP/accepted.md")"

plant bare "${ACCEPTED_BRIEF/ · to see the change: \`git show 3225216af\`/}"
expect_eq "DG-2a: the command-less copy ends on a bare reply line" "Reply 1 or 2" "$(reply_tail "$TMP/bare.md")"
expect_false "DG-2b: a brief about a commit whose reply line carries no command is refused" digin_ok "$TMP/bare.md"

plant trailing "$ACCEPTED_BRIEF"$'\n\n''To dig in: `git show 3225216af`'
expect_eq "DG-3a: the trailing-line copy carries a line after the reply line" 'To dig in: `git show 3225216af`' "$(reply_tail "$TMP/trailing.md")"
expect_false "DG-3b: a brief with a line after the reply line is refused" digin_ok "$TMP/trailing.md"

plant badcmd "${ACCEPTED_BRIEF/git show 3225216af/see the commit}"
expect_false "DG-4: a reply line whose tail is no command is refused" digin_ok "$TMP/badcmd.md"

expect_true "DG-5: the skill's own reply line is the shape with the dig-in on it" reply_last_ok "$SKILL"
expect_true "DG-5b: …and the skill names the dig-in in its three forms" context_rule_ok "$SKILL"

section "§REFERENT — the context names the thing; Altitude governs Goal and Options only"

expect_true "RF-1: the accepted brief's context names its referent, the commit" referent_ok "$TMP/accepted.md"

blind='A change you ordered landed after the critic'"'"'s last review, and the diff you asked for is all there is. The release gate asks every change past a review to carry a review or your waiver. This one has neither.'
anchor -E "$TMP/accepted.md" '^The commit that removed' 1
plant blind "$(awk -v b="$blind" '/^The commit that removed/ { print b; next } { print }' <<<"$ACCEPTED_BRIEF")"
expect_eq "RF-2a: the referent-less copy carries the plant" "$blind" "$(context_of "$TMP/blind.md")"
expect_true "RF-2b: …and still ends on its dig-in (only the context differs)" digin_ok "$TMP/blind.md"
expect_false "RF-2c: a brief about a specific diff whose context names no referent is refused" referent_ok "$TMP/blind.md"

expect_true "RF-3: the skill rules the context paragraph" context_rule_ok "$SKILL"
doctor "$SKILL" "$TMP/no-context-rule.md" '/never pastes the artifact/d'
expect_false "RF-3a: the rule-dropped copy lost the clause" grep -qi 'never pastes the artifact' "$TMP/no-context-rule.md"
expect_false "RF-3b: …and fails the context-rule pin" context_rule_ok "$TMP/no-context-rule.md"

expect_true "RF-4: every line barring identifiers names the Goal as what it governs" altitude_scoped_ok "$SKILL"
{ cat "$SKILL"; echo 'A brief carries no file, function, row, task or version identifiers.'; } > "$TMP/whole-brief.md"
expect_true "RF-4a: the widened copy carries a line barring identifiers from the whole brief" \
  grep -q '^A brief carries no file' "$TMP/whole-brief.md"
expect_false "RF-4b: …and fails the scope pin" altitude_scoped_ok "$TMP/whole-brief.md"

finish
