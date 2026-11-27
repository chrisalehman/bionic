#!/bin/bash
# Tests for tests/lib/release-check.sh — this repo's `release-check:` command.
#
# THE CONTRACT THE DELETED PIN SUITE HELD THAT NO OTHER SUITE HOLDS: the CHANGELOG's newest
# heading equals `.version` in payload/.claude-plugin/plugin.json. The release check runs the
# name scan AND that pair, both read from the tree at BIONIC_CHECK_HEAD (default HEAD) with
# `git show`, so a check run in a dirty working tree judges what a push would publish.
#
#   §VERSION-PAIR   an agreeing pair passes; a doctored CHANGELOG heading and a doctored
#                   plugin.json version each fail with ONE line naming both versions; the check
#                   reads the HEAD tree, never the working files; BIONIC_CHECK_HEAD picks the tree.
#   §REFUSE         no list path, and a pair that cannot be read, are one-line refusals.
#   §SCAN           the name scan still runs under it: a listed entry planted in a committed
#                   file fails the check, beside the clean run on the same repository.
#   §LIMITS         the Known limits of the release being shipped (wave-38 T20; REQ-11 AC-11.4, L8): for the
#                   newest heading, the plan whose `release:` names it is read, and every open deferral's
#                   `stated=` sentence must stand under that entry's `### Known limits`. One omitted sentence
#                   exits 1 in one line naming it; all present is green; a sentence elsewhere in the entry or
#                   only under an older entry is an omission; no stated deferral, and no plan naming the
#                   release, each pass with one `known-limits:` line saying so.
#   §LIMITS-2       a deferral rated `defer` whose `deferred:` line states no sentence, or a dash for one, refuses
#                   the release in one line naming the finding; the same deferral stated and carried passes.
#   §LIMITS-3       the deferral rule bites from a named floor release on: a plan naming 1.23.0 with an unstated or
#                   dashed defer deferral passes, naming 1.24.0 refuses; a stated deferral is held at every release;
#                   the comparison is dotted integers (1.9.9 is below 1.24.0).
#   §FROM-REPORT    `release-note` renders the entry's landing numbers: `landing-report --rows` over the landing
#                   record through the head's last landing. The check renders them again at the head the entry names
#                   and refuses a number that disagrees, naming both; the gate's killed count is not held to it.
#   §LAST           a landing the entry's head does not hold, other than the one that carried the entry, refuses it
#                   until the entry is rendered again.
#   §PROJECT        the check run from a tree that holds no plan reads the project's plan and record from
#                   BIONIC_CHECK_PROJECT, so an unstated deferral refuses from that tree as it does from the project's own.
#   §JOIN           the cap on tests reads the non-whitespace characters of the tracked, non-link shell files under
#                   tests/ against those everywhere else, in the tree at BIONIC_CHECK_HEAD, never the working files:
#                   tests split over lines and the same tests joined onto one read the same; a link counts nothing.
#   §DELETE         the limit is 1.25 times the larger of the head's code and BIONIC_CHECK_BASE's, so a commit that
#                   deletes code is admitted and so is the next one that adds a test line; no base, the head's alone.
#   §OVER           a head past the limit exits 1 in one line naming both counts, unless its tests are at or under
#                   the base's; a head with no shell code outside tests/ is a refusal, never a pass.
#   §LINE           a pass prints `test-ratio: <tests>/<code> chars · limit <n> · room <n>`, a refusal the same after
#                   `release-check: `, the limit rounded down; release-approval.test.sh §RATIO pins its readers.
#   §CORR           the 1.19.0 entry against wave-36's REQ-8 and REQ-9 (AC-8.1, AC-8.3, AC-8.4, AC-9.1,
#                   AC-9.2): the block exists at its own heading, dated; the Corrections
#                   section names the two refusals 1.18.0 introduced, the text-only floor arm, D22's two
#                   deferred sentences and the corrected fix count; Known limits states its own count;
#                   Migration names every row that added a refusal; every
#                   build row names its record; the 1.18.0 block is as released; help.md and version.md
#                   read the version and `render.sh --check` is green. Each rule has a doctored copy.
#   §REL-1.28.0     the release check run on a repository holding the real 1.28.0 entry and its run's own deferred
#                   and moved lines, cut from the closed plan as finding events into tests/fixtures/release-check/: a
#                   deferral the person later moved to fixed is not held, every other deferred sentence stands under
#                   Known limits and the check passes; with its Known limits removed it fails one line for each.
#   §JUDGE          the person's word moves the judge: `check-from` refuses words no prompt holds and a commit the
#                   working head does not hold; on their words a later landing that rewrites the check is run by the
#                   judge's copy, and its line names the judge, the words and who typed them.
#   §RELEASE        two landings through the runner, the first deleting code, the next adding a test line onto it:
#                   both are admitted, for the runner exports the release (BIONIC_CHECK_RELEASE) and the check counts
#                   its code as well as the landing's base.
#   §HOLD           the project's check, run from inside a held command, is started with no hold, so its facts are
#                   folded by the reader at the judge and not by the verb's.
#   §ONE-READER     the copy check runs over the tree at BIONIC_CHECK_HEAD, as the judge's one-reader-check.sh holds it: a
#                   head with a planted second parser, a second writer of the plan or a copied loader is each refused in
#                   one line naming the copy, a clean head passes with its counts, a plant in the working files alone is
#                   not read, and a head with no hooks/ and payload/scripts/ passes saying it holds no copy to count.
#   §DEFER-LANDING  a range whose base holds the release's entry as the head does (a landing of code, or of an older
#                   entry) passes an unstated or omitted deferral with a note per line and one line saying why; the
#                   landing that writes the entry, a range spanning that change and a run with no base refuse it.
#   §NUMBERS-FLOOR  from 2.3.0 an entry with no landing numbers fails, by hand and at the landing that writes it, and
#                   is a note at a landing that leaves it as it was; the 2.2.0 entry with none passes.
#
# FIXTURE FIDELITY: every repository is a real `git init` under a mktemp directory with real
# commits; nothing is a mock of git. The list file lives outside every checkout and holds one
# made-up entry. The real tree is never written; §CORR reads its CHANGELOG.md and writes only
# doctored copies under the scratch directory. SYNTHESIZED: the versions and the entry.
#
# Usage: bash tests/release-check.test.sh
#
# pins: tests/lib/release-check.sh tests/lib/name-scan.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

CHECK="${BIONIC_SCRIPTS_DIR}/tests/lib/release-check.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/release-check-test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
mkdir -p "$TMP/lists"

ENTRY="zq-alpha-7731"
LIST="$TMP/lists/names.list"
printf '%s\n' "$ENTRY" > "$LIST"

setup_section "fixtures"

[ -r "$CHECK" ] || { echo "FAIL: $CHECK is not readable"; exit 1; }
expect_false "setup: the list directory is outside every checkout" git -C "$TMP/lists" rev-parse --show-toplevel

# fx_changelog <version> — a CHANGELOG whose newest heading is <version>, older one below it
fx_changelog() {
  printf '# Changelog\n\n## %s — 2026-01-02\n\n- a change\n\n## 0.0.1 — 2026-01-01\n\n- first\n' "$1"
}
# fx_plugin <version>
fx_plugin() { printf '{\n  "name": "fixture",\n  "version": "%s"\n}\n' "$1"; }
# fx_repo <dir> <changelog version> <plugin version> — a committed pair
fx_repo() {
  mkdir -p "$1/payload/.claude-plugin" &&
  git -C "$1" init -q --template= &&
  git -C "$1" config commit.gpgsign false &&
  fx_changelog "$2" > "$1/CHANGELOG.md" && fx_plugin "$3" > "$1/payload/.claude-plugin/plugin.json" &&
  printf 'base\n' > "$1/a.txt" && printf '#!/bin/bash\n:\n:\n' > "$1/code.sh" &&
  git -C "$1" add -A && git -C "$1" commit -q -m "first"
}
# run_check <repo> [args...] — sets OUT (stdout+stderr) and RC; the list is the default argument
run_check() {
  local repo="$1"; shift
  [ "$#" -gt 0 ] || set -- "$LIST"
  OUT="$(cd "$repo" && env -u BIONIC_CHECK_BASE -u BIONIC_CHECK_HEAD bash "$CHECK" "$@" 2>&1)"; RC=$?
}
# lines_of <text> — the number of lines the check itself printed (its `release-check:` lines);
# the name scan's own output, which rides along on stdout, is not counted
lines_of() { printf '%s\n' "$1" | awk '/^release-check:/ { n++ } END { print n + 0 }'; }

section "§VERSION-PAIR — the newest CHANGELOG heading equals plugin.json's version, read from the HEAD tree"

R="$TMP/agree"; fx_repo "$R" 2.2.4 2.2.4
run_check "$R"
expect_status "(i) an agreeing pair, a clean scan: the check passes" 0 "$RC"

R="$TMP/chg"; fx_repo "$R" 2.2.4 2.2.4
fx_changelog 2.2.5 > "$R/CHANGELOG.md"; git -C "$R" commit -q -am "doctor the heading"
run_check "$R"
expect_status "(ii) a doctored CHANGELOG heading: the check fails" 1 "$RC"
expect_contains "(ii) …and the line names the CHANGELOG's version" "2.2.5" "$OUT"
expect_contains "(ii) …and the line names the plugin's version" "2.2.4" "$OUT"
expect_eq "(ii) …in one line" "1" "$(lines_of "$OUT")"

R="$TMP/plg"; fx_repo "$R" 2.2.4 2.2.4
fx_plugin 2.2.9 > "$R/payload/.claude-plugin/plugin.json"; git -C "$R" commit -q -am "doctor the version"
run_check "$R"
expect_status "(iii) a doctored plugin.json version: the check fails" 1 "$RC"
expect_contains "(iii) …and the line names the plugin's version" "2.2.9" "$OUT"
expect_contains "(iii) …and the CHANGELOG's" "2.2.4" "$OUT"
expect_eq "(iii) …in one line" "1" "$(lines_of "$OUT")"

# (iv) the HEAD tree, not the working file: the working CHANGELOG disagrees, nothing is committed.
R="$TMP/dirty"; fx_repo "$R" 2.2.4 2.2.4
run_check "$R"
expect_status "(iv) setup: the clean repository passes" 0 "$RC"
CLEAN_OUT="$OUT"
fx_changelog 7.7.7 > "$R/CHANGELOG.md"
expect_nonempty "(iv) setup: the repository really is dirty" "$(git -C "$R" status --porcelain)"
run_check "$R"
expect_status "(iv) a working CHANGELOG edited and not committed: the check still passes (HEAD is read)" 0 "$RC"
expect_eq "(iv) …and prints what the clean run of the same repository printed" "$CLEAN_OUT" "$OUT"

# BIONIC_CHECK_HEAD picks the tree: the bad commit is HEAD, the good one is HEAD~1.
R="$TMP/pick"; fx_repo "$R" 2.2.4 2.2.4
fx_changelog 2.2.5 > "$R/CHANGELOG.md"; git -C "$R" commit -q -am "doctor the heading"
run_check "$R"
expect_status "(v) the doctored HEAD fails" 1 "$RC"
OUT="$(cd "$R" && env -u BIONIC_CHECK_BASE BIONIC_CHECK_HEAD='HEAD~1' bash "$CHECK" "$LIST" 2>&1)"; RC=$?
expect_status "(v) …and BIONIC_CHECK_HEAD=HEAD~1 reads the agreeing tree and passes" 0 "$RC"

section "§REFUSE — no list path, and a pair that cannot be read, are one-line refusals"

R="$TMP/refuse"; fx_repo "$R" 2.2.4 2.2.4
OUT="$(cd "$R" && env -u BIONIC_CHECK_BASE -u BIONIC_CHECK_HEAD bash "$CHECK" 2>&1)"; RC=$?
expect_ne "(a) no list path: non-zero" "0" "$RC"
expect_eq "(a) …in one line" "1" "$(lines_of "$OUT")"
run_check "$R" "$TMP/lists/does-not-exist.list"
expect_ne "(b) a list path that is not there: non-zero" "0" "$RC"
expect_eq "(b) …in one line" "1" "$(lines_of "$OUT")"

R="$TMP/nohead"; fx_repo "$R" 2.2.4 2.2.4
printf '# Changelog\n\nno release heading here\n' > "$R/CHANGELOG.md"; git -C "$R" commit -q -am "no heading"
run_check "$R"
expect_ne "(c) a CHANGELOG with no release heading: non-zero" "0" "$RC"
expect_eq "(c) …in one line" "1" "$(lines_of "$OUT")"

R="$TMP/nover"; fx_repo "$R" 2.2.4 2.2.4
printf '{ "name": "fixture" }\n' > "$R/payload/.claude-plugin/plugin.json"; git -C "$R" commit -q -am "no version"
run_check "$R"
expect_ne "(d) a plugin.json with no version: non-zero" "0" "$RC"
expect_eq "(d) …in one line" "1" "$(lines_of "$OUT")"

section "§SCAN — the name scan still runs under the release check"

R="$TMP/scan"; fx_repo "$R" 2.2.4 2.2.4
run_check "$R"
expect_status "(e) setup: the clean repository passes" 0 "$RC"
printf 'a line holding %s in the middle\n' "$ENTRY" > "$R/b.txt"; git -C "$R" add -A; git -C "$R" commit -q -m "plant"
run_check "$R"
expect_status "(e) a listed entry planted in a committed file: the check fails" 1 "$RC"
expect_contains "(e) …and the scan's hit line is in the output" "HIT entry=1" "$OUT"
expect_absent "(e) …and the entry itself is never printed" "$ENTRY" "$OUT"

section "§LIMITS — the shipped release's Known limits carry every deferred sentence of its plan (wave-38 T20; REQ-11 AC-11.4)"

# FIXTURE FIDELITY: a real repository whose committed CHANGELOG's newest entry has a `### Known limits` part, and
# the run's plan on disk under the project's docs root (never committed, as `.bionic/` is ignored in a real
# project): a page at version 15 whose header names `release:` and `fix-policy:`, and beside it the run's log, its step
# and each deferral a `finding` event whose `stated=` sentence is escaped as the move verb writes it.
# Three deferrals: #1 and #2 stated and deferred by the policy, #4 stated but rated fix (S2 on under S1,S2-on), so
# only #1 and #2 are held. #3, deferred and unstated, is kept apart (LIM_UNSTATED, LIM_DASH): a deferral rated
# defer with no sentence refuses the release, so it joins a plan only where that refusal is the thing proved.
# SYNTHESIZED: the sentences, the versions, the records.
LIM_A='The first limit says "quoted" words and a back\slash.'
LIM_B='The second limit is long enough that a changelog wraps it across two lines.'
lim_plan() {  # <repo> <release> [<finding events>] -> the run's page under the repository's docs root, and its log
  local d="$1/.bionic/docs"
  mkdir -p "$d/plans/epic-01" "$d/record/wave-01"
  printf -- '---\ncanonical_sdlc_version: 15\nfix-policy: S1,S2-on\nrelease: %s\n---\n\n# fixture run\n' "$2" > "$d/plans/epic-01/wave-01.plan.md"
  { printf 'run/v1|ev=step|n=7|at=2025-12-31T00:00:00Z\n'; [ -z "${3-}" ] || printf '%s\n' "$3"; } > "$d/record/wave-01/run.log"
}
# The move verb writes a stated sentence through its own escape, and the one reader of it unescapes, so a deferral's
# sentence is escaped here by that function, taken from where it lives, never by a rule restated in this suite.
eval "$(sed -n '/^deferral_escape() {/,/^}/p' "${BIONIC_HOOKS_DIR}/poker/proof.sh")"
lim_def() {  # <ref> <severity> <reach> <title> [<stated>] -> one deferral as the move verb writes it into the run's log
  printf 'run/v1|ev=finding|ref=%s|severity=%s|reach=%s|to=deferred|title=%s%s|at=2026-01-01T00:00:00Z' "$1" "$2" "$3" "$4" \
    "${5+|stated=$(deferral_escape "$5")}"
}
expect_eq "(l0) setup: the move verb's escape is loaded and escapes a quote and a backslash" 'a \"b\" c\\d' "$(deferral_escape 'a "b" c\d')"
LIM_DEFERRED="$(lim_def record/w/critic.md#1 S3 on 'a first title' "$LIM_A")
$(lim_def record/w/critic.md#2 S3 on 'a second title' "$LIM_B")
$(lim_def record/w/critic.md#4 S2 on 'fixed instead' 'A sentence the policy fixes is no limit.')"
LIM_UNSTATED="$(lim_def record/w/critic.md#3 S3 on 'an unstated one')"
LIM_DASH="$(lim_def record/w/critic.md#3 S3 on 'an unstated one' -)"
LIM_FIXED="$(lim_def record/w/critic.md#4 S2 on 'fixed instead' 'A sentence the policy fixes is no limit.')"
lim_changelog() {  # <repo> <Known limits body of 2.2.4> [<older entry body>] -> commit a CHANGELOG whose newest entry is 2.2.4
  { printf '# Changelog\n\n## 2.2.4 — 2026-01-02\n\n- a change\n\n### Known limits\n\n%s\n\n' "$2"
    printf '## 0.0.1 — 2026-01-01\n\n- first\n%s\n' "${3-}"; } > "$1/CHANGELOG.md"
  git -C "$1" add CHANGELOG.md && git -C "$1" commit -q -m "the changelog"
}
LIM_BOTH="- Known limit: $LIM_A
- Known limit: The second limit is long enough that a changelog
  wraps it across two lines."

R="$TMP/lim-ok"; fx_repo "$R" 2.2.4 2.2.4; lim_plan "$R" 2.2.4 "$LIM_DEFERRED"; lim_changelog "$R" "$LIM_BOTH"
expect_false "(l0) setup: the plan is not committed (it is read from the docs root, as a real project's is)" git -C "$R" cat-file -e "HEAD:.bionic/docs/plans/epic-01/wave-01.plan.md"
run_check "$R"
expect_status "(l1) every stated deferral under the newest entry's Known limits, one of them wrapped: the check passes" 0 "$RC"
expect_eq "(l1) …and no release-check line" "0" "$(lines_of "$OUT")"

R="$TMP/lim-omit"; fx_repo "$R" 2.2.4 2.2.4; lim_plan "$R" 2.2.4 "$LIM_DEFERRED"; lim_changelog "$R" "- Known limit: $LIM_A"
run_check "$R"
expect_status "(l2) §LIMITS AC-11.4 Known limits omitting one stated sentence: the check fails" 1 "$RC"
expect_eq "(l2) …in one line" "1" "$(lines_of "$OUT")"

R="$TMP/lim-elsewhere"; fx_repo "$R" 2.2.4 2.2.4; lim_plan "$R" 2.2.4 "$LIM_DEFERRED"
{ printf '# Changelog\n\n## 2.2.4 — 2026-01-02\n\n- a change: %s\n\n### Known limits\n\n- Known limit: %s\n\n' "$LIM_B" "$LIM_A"
  printf '## 0.0.1 — 2026-01-01\n\n- first\n'; } > "$R/CHANGELOG.md"; git -C "$R" commit -q -am "the sentence outside Known limits"
run_check "$R"
expect_status "(l3) the sentence in the entry but outside its Known limits: the check fails" 1 "$RC"
expect_contains "(l3) …naming it" "omit the deferred sentence of record/w/critic.md#2" "$OUT"

R="$TMP/lim-older"; fx_repo "$R" 2.2.4 2.2.4; lim_plan "$R" 2.2.4 "$LIM_DEFERRED"
lim_changelog "$R" "- Known limit: $LIM_A" "
### Known limits

- Known limit: $LIM_B"
run_check "$R"
expect_status "(l4) the sentence only under an older entry's Known limits: the check fails" 1 "$RC"
expect_contains "(l4) …naming it" "omit the deferred sentence of record/w/critic.md#2" "$OUT"

R="$TMP/lim-none"; fx_repo "$R" 2.2.4 2.2.4
lim_plan "$R" 2.2.4 "$LIM_FIXED"; lim_changelog "$R" "- Known limit: none of note."
run_check "$R"
expect_status "(l5) a plan with no deferral rated defer: the check passes" 0 "$RC"
expect_contains "(l5) …in one line saying so" "known-limits: 2.2.4 — $(cd "$R" && pwd -P)/.bionic/docs/plans/epic-01/wave-01.plan.md states no deferred sentence" "$OUT"
expect_eq "(l5) …one such line" "1" "$(printf '%s\n' "$OUT" | /usr/bin/grep -c '^known-limits:')"

R="$TMP/lim-noplan"; fx_repo "$R" 2.2.4 2.2.4; lim_plan "$R" 2.2.3 "$LIM_DEFERRED"; lim_changelog "$R" "- Known limit: none of note."
run_check "$R"
expect_status "(l6) no plan names the release (the plan names 2.2.3): the check passes" 0 "$RC"
lim_plan "$R" 2.2.4 "$LIM_DEFERRED"
run_check "$R"
expect_status "(l6) …positive, the same repository once the plan names 2.2.4: the omissions fail it" 1 "$RC"
expect_eq "(l6) …one line for each of the two sentences" "2" "$(lines_of "$OUT")"

section "§LIMITS-2 — a deferral rated defer with no stated sentence, or a dash for one, refuses the release"

# The same fixture world as §LIMITS: one deferral, #3, rated defer by the policy. Unstated it is no limit anyone
# can carry, so the check names it and refuses; stated and carried it passes. The mutant is a copy of the check
# beside the real name scan, the real payload and the real hooks, with the arm's `if` made `if false`.
L2_LINE() { printf 'release-check: 2.2.4 defers record/w/critic.md#3 with no stated sentence; state it or fix it'; }
R="$TMP/l2-bare"; fx_repo "$R" 2.2.4 2.2.4; lim_plan "$R" 2.2.4 "$LIM_UNSTATED"; lim_changelog "$R" "- Known limit: none of note."
run_check "$R"
expect_status "(L2-1) §LIMITS-2 a deferral rated defer with no sentence: the check fails" 1 "$RC"
expect_contains "(L2-1) …one line naming the finding" "$(L2_LINE)" "$OUT"
expect_eq "(L2-1) …and it is the only release-check line" "1" "$(lines_of "$OUT")"
expect_eq "(L2-1) …no known-limits: line says the plan holds none" "0" "$(printf '%s\n' "$OUT" | /usr/bin/grep -c '^known-limits:')"

R="$TMP/l2-dash"; fx_repo "$R" 2.2.4 2.2.4; lim_plan "$R" 2.2.4 "$LIM_DASH"; lim_changelog "$R" "- Known limit: none of note."
run_check "$R"
expect_status "(L2-2) a dash for the sentence: the check fails" 1 "$RC"
expect_contains "(L2-2) …the same line, naming the finding" "$(L2_LINE)" "$OUT"
expect_eq "(L2-2) …and it is the only release-check line" "1" "$(lines_of "$OUT")"

R="$TMP/l2-stated"; fx_repo "$R" 2.2.4 2.2.4
lim_plan "$R" 2.2.4 "$(lim_def record/w/critic.md#3 S3 on 'an unstated one' 'The third limit is stated and carried.')"
lim_changelog "$R" "- Known limit: The third limit is stated and carried."
run_check "$R"
expect_status "(L2-3) the same deferral with its sentence stated and carried in Known limits: the check passes" 0 "$RC"
expect_contains "(L2-3) …and the known-limits: line says one sentence carried" "known-limits: 2.2.4 carries the 1 deferred sentences of $(cd "$R" && pwd -P)/.bionic/docs/plans/epic-01/wave-01.plan.md" "$OUT"
expect_eq "(L2-3) …no release-check line" "0" "$(lines_of "$OUT")"

# A stated deferral beside an unstated one: the unstated one alone is named, and the stated one is still held to Known limits.
R="$TMP/l2-both"; fx_repo "$R" 2.2.4 2.2.4; lim_plan "$R" 2.2.4 "$LIM_UNSTATED
$(printf '%s\n' "$LIM_DEFERRED" | sed -n '2p')"
lim_changelog "$R" "- Known limit: The second limit is long enough that a changelog wraps it across two lines."
run_check "$R"
expect_status "(L2-3b) one unstated beside one stated and carried: the check fails" 1 "$RC"
expect_eq "(L2-3b) …naming the unstated one alone" "1 1" "$(lines_of "$OUT") $(printf '%s\n' "$OUT" | /usr/bin/grep -cF "$(L2_LINE)")"

# L2-4 MUTATION: the arm disabled turns L2-1 red (the check passes) and L2-3 stays green.
MUT="$TMP/l2-mut"; mkdir -p "$MUT/tests/lib"
cp "$BIONIC_SCRIPTS_DIR/tests/lib/name-scan.sh" "$MUT/tests/lib/name-scan.sh"
ln -s "$BIONIC_SCRIPTS_DIR/payload" "$MUT/payload"; ln -s "$BIONIC_SCRIPTS_DIR/hooks" "$MUT/hooks"
sed 's/^\(  *\)if \[ -z "\$st" \] || \[ "\$st" = - \]; then$/\1if false; then/' "$CHECK" > "$MUT/tests/lib/release-check.sh"
expect_false "(L2-4) setup: the mutant differs from the check" cmp -s "$CHECK" "$MUT/tests/lib/release-check.sh"
expect_eq "(L2-4) setup: the mutant has the arm disabled and nothing else" "1" "$(diff "$CHECK" "$MUT/tests/lib/release-check.sh" | /usr/bin/grep -c '^>')"
mut_check() { OUT="$(cd "$1" && env -u BIONIC_CHECK_BASE -u BIONIC_CHECK_HEAD bash "$MUT/tests/lib/release-check.sh" "$LIST" 2>&1)"; RC=$?; }
mut_check "$TMP/l2-stated"
expect_status "(L2-4) MUTANT on the stated fixture: still passes (L2-3 stays green)" 0 "$RC"
expect_contains "(L2-4) MUTANT …and it ran: the sentence is carried" "known-limits: 2.2.4 carries the 1 deferred sentences" "$OUT"
mut_check "$TMP/l2-bare"
expect_status "(L2-4) MUTANT on the unstated fixture: the check passes, so L2-1 would go red" 0 "$RC"
expect_absent "(L2-4) MUTANT …and the line naming the finding is gone" "with no stated sentence" "$OUT"

section "§LIMITS-3 — the deferral rule bites from its floor release on; an earlier release is passed over"

# The same fixture world as §LIMITS-2, with the release named by the plan varied. Releases before the floor shipped
# under the older rule, so an unstated or dashed deferral of one is neither counted nor refused and its known-limits
# line reads as it did; a stated deferral is held to Known limits at every release. The comparison is dotted
# integers, so 1.9.9 is below 1.24.0 where a string compare would put it above.
L3_PLAN() { printf '%s' "$(cd "$1" && pwd -P)/.bionic/docs/plans/epic-01/wave-01.plan.md"; }
R="$TMP/l3-old"; fx_repo "$R" 1.23.0 1.23.0; lim_plan "$R" 1.23.0 "$LIM_UNSTATED"
run_check "$R"
expect_status "(L3-1) §LIMITS-3 a plan naming 1.23.0 with an unstated defer deferral: the check passes" 0 "$RC"
expect_absent "(L3-1) …no line says it has no stated sentence" "no stated sentence" "$OUT"
expect_contains "(L3-1) …and the known-limits line reads as before: the plan states none" "known-limits: 1.23.0 — $(L3_PLAN "$R") states no deferred sentence" "$OUT"
expect_eq "(L3-1) …no release-check line" "0" "$(lines_of "$OUT")"

R="$TMP/l3-old-dash"; fx_repo "$R" 1.23.0 1.23.0; lim_plan "$R" 1.23.0 "$LIM_DASH"
run_check "$R"
expect_status "(L3-1b) the same release with a dash for the sentence: the check passes" 0 "$RC"
expect_contains "(L3-1b) …and the known-limits line reads as before" "known-limits: 1.23.0 — $(L3_PLAN "$R") states no deferred sentence" "$OUT"
expect_eq "(L3-1b) …no release-check line" "0" "$(lines_of "$OUT")"

R="$TMP/l3-old-stated"; fx_repo "$R" 1.23.0 1.23.0; lim_plan "$R" 1.23.0 "$LIM_DEFERRED"
run_check "$R"
expect_status "(L3-1c) a stated deferral of 1.23.0 whose sentence its Known limits omit: the check still fails" 1 "$RC"
expect_contains "(L3-1c) …naming the omission" "release-check: Known limits of 1.23.0 omit the deferred sentence of record/w/critic.md#1" "$OUT"

R="$TMP/l3-floor"; fx_repo "$R" 1.24.0 1.24.0; lim_plan "$R" 1.24.0 "$LIM_UNSTATED"
run_check "$R"
expect_status "(L3-2) the same plan naming 1.24.0: the check fails" 1 "$RC"
expect_contains "(L3-2) …naming the finding" "release-check: 1.24.0 defers record/w/critic.md#3 with no stated sentence; state it or fix it" "$OUT"
expect_eq "(L3-2) …and it is the only release-check line" "1" "$(lines_of "$OUT")"

R="$TMP/l3-floor-dash"; fx_repo "$R" 1.24.0 1.24.0; lim_plan "$R" 1.24.0 "$LIM_DASH"
run_check "$R"
expect_status "(L3-2b) a dash for the sentence at 1.24.0: the check fails" 1 "$RC"
expect_contains "(L3-2b) …naming the finding" "release-check: 1.24.0 defers record/w/critic.md#3 with no stated sentence; state it or fix it" "$OUT"

R="$TMP/l3-nine"; fx_repo "$R" 1.9.9 1.9.9; lim_plan "$R" 1.9.9 "$LIM_UNSTATED"
run_check "$R"
expect_status "(L3-2c) 1.9.9, below 1.24.0 by digits and above it as a string: the check passes" 0 "$RC"
expect_contains "(L3-2c) …and the known-limits line says the plan states none" "known-limits: 1.9.9 — $(L3_PLAN "$R") states no deferred sentence" "$OUT"

# L3-3 the comparison itself. The check runs its checks when loaded, so the function is cut out of its source and
# defined in a subshell; the cut is proved non-empty before any answer is read.
FN="$(awk '/^lim_version_at_least\(\) \{/ { f = 1 } f { print } f && /^\}/ { exit }' "$CHECK")"
expect_nonempty "(L3-3) setup: lim_version_at_least is defined in the check" "$FN"
vge() { ( eval "$FN"; lim_version_at_least "$1" "$2" ) >/dev/null 2>&1; }
expect_true "(L3-3) 1.24.0 is at or past 1.24.0" vge 1.24.0 1.24.0
expect_true "(L3-3) 1.24.1 is at or past 1.24.0" vge 1.24.1 1.24.0
expect_true "(L3-3) 1.25.0 is at or past 1.24.0" vge 1.25.0 1.24.0
expect_true "(L3-3) 2.0.0 is at or past 1.24.0" vge 2.0.0 1.24.0
expect_false "(L3-3) 1.23.0 is below 1.24.0" vge 1.23.0 1.24.0
expect_false "(L3-3) 1.9.9 is below 1.24.0 (digits, not strings)" vge 1.9.9 1.24.0
expect_false "(L3-3) 0.99.99 is below 1.24.0" vge 0.99.99 1.24.0

# L3-4 MUTATION: the floor raised past every release turns L3-2 red (the unstated deferral is passed over), and the
# comparison made true for every release turns L3-1 red (1.23.0 is refused).
l3_mutant() {  # <name> <sed script> -> $MUT_DIR/tests/lib/release-check.sh with one line changed
  MUT_DIR="$TMP/$1"; mkdir -p "$MUT_DIR/tests/lib"
  cp "$BIONIC_SCRIPTS_DIR/tests/lib/name-scan.sh" "$MUT_DIR/tests/lib/name-scan.sh"
  ln -s "$BIONIC_SCRIPTS_DIR/payload" "$MUT_DIR/payload"; ln -s "$BIONIC_SCRIPTS_DIR/hooks" "$MUT_DIR/hooks"
  sed "$2" "$CHECK" > "$MUT_DIR/tests/lib/release-check.sh"
}
l3_mut_check() { OUT="$(cd "$1" && env -u BIONIC_CHECK_BASE -u BIONIC_CHECK_HEAD bash "$MUT_DIR/tests/lib/release-check.sh" "$LIST" 2>&1)"; RC=$?; }
l3_mutant l3-mut-floor 's/^LIM_RULE_FROM=.*/LIM_RULE_FROM=99.0.0/'
expect_eq "(L3-4) setup: the floor mutant changes one line and nothing else" "1" "$(diff "$CHECK" "$MUT_DIR/tests/lib/release-check.sh" | /usr/bin/grep -c '^>')"
l3_mut_check "$TMP/l3-old"
expect_status "(L3-4) MUTANT floor raised, on the 1.23.0 fixture: still passes (L3-1 stays green)" 0 "$RC"
expect_contains "(L3-4) MUTANT …and it ran: the known-limits line is there" "known-limits: 1.23.0" "$OUT"
l3_mut_check "$TMP/l3-floor"
expect_status "(L3-4) MUTANT floor raised, on the 1.24.0 fixture: the check passes, so L3-2 would go red" 0 "$RC"
expect_absent "(L3-4) MUTANT …and the line naming the finding is gone" "no stated sentence" "$OUT"
l3_mutant l3-mut-cmp 's/^\(  *\)if ! lim_version_at_least \(.*\); then$/\1if false; then/'
expect_eq "(L3-4) setup: the gate mutant changes one line and nothing else" "1" "$(diff "$CHECK" "$MUT_DIR/tests/lib/release-check.sh" | /usr/bin/grep -c '^>')"
l3_mut_check "$TMP/l3-floor"
expect_status "(L3-4) MUTANT gate off, on the 1.24.0 fixture: still refuses (L3-2 stays green)" 1 "$RC"
l3_mut_check "$TMP/l3-old"
expect_status "(L3-4) MUTANT gate off, on the 1.23.0 fixture: refused, so L3-1 would go red" 1 "$RC"
expect_contains "(L3-4) MUTANT …by the line naming the finding" "no stated sentence" "$OUT"

section "§FROM-REPORT — release-note renders the landing numbers at a head; the check holds the entry to them"

# FIXTURE FIDELITY: the run's plan names 2.2.4, and its log holds, in the line's event shapes, a queue
# landing at L1 and a hand landing at L2. The entry is rendered at L2 for 01:30 and committed as E, which a hand
# landing carries at 02:00; a third row lands L3 on top at 03:00. The poker runs from the fixture as a user runs it.
# SYNTHESIZED: the events.
POKER="${BIONIC_SCRIPTS_DIR}/hooks/session-poker.sh"; RN_PLAN=".bionic/docs/plans/epic-01/wave-01.plan.md"
rn_pub() { printf 'run/v1|ev=published|row=%s|commit=%s|kind=%s|by=t|why=w|at=%s\n' "$@" >> "$RN_REC"; }
rn_commit() {  # <file> -> commit a change to it, print the head
  printf '%s\n' "$1" > "$R/$1"; git -C "$R" add -- "$1"; git -C "$R" commit -q -m "$1"; git -C "$R" rev-parse HEAD
}
rn_entry() {  # <release-note output> -> commit a CHANGELOG whose 2.2.4 entry carries it, print the head
  { printf '# Changelog\n\n## 2.2.4 — 2026-01-02\n\n- a change\n\n%s\n## 0.0.1 — 2026-01-01\n\n- first\n' "${1%rc=0}"
  } > "$R/CHANGELOG.md"; git -C "$R" commit -q -am "the entry" >/dev/null; git -C "$R" rev-parse HEAD
}
rn_note() { (cd "$R" && bash "$POKER" release-note "$@" "$RN_PLAN" 2>&1; echo "rc=$?"); }
rn_check() { OUT="$(cd "$R" && env -u BIONIC_CHECK_BASE BIONIC_CHECK_HEAD="$1" bash "$CHECK" "$LIST" 2>&1)"; RC=$?; }
R="$TMP/rn"; fx_repo "$R" 2.2.4 2.2.4; lim_plan "$R" 2.2.4
RN_REC="$R/.bionic/docs/record/wave-01/run.log"
L1="$(rn_commit l1)"; L2="$(rn_commit l2)"
{ printf 'run/v1|ev=ready|row=T1|commit=%s|at=2026-01-02T00:00:00Z\n' "$L1"
  printf 'run/v1|ev=verdict|row=T1|commit=%s|suite=a.test.sh|result=green|log=-|admitted=1767312060|width=2|promised=60|actual=90|at=2026-01-02T00:05:00Z\n' "$L1"
} >> "$RN_REC"; rn_pub T1 "$L1" queue 2026-01-02T00:10:00Z; rn_pub T2 "$L2" hand 2026-01-02T01:00:00Z
LR1="$(cd "$R" && bash "$POKER" landing-report --rows "$RN_PLAN" 2>&1)"
B="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; RN1="$(rn_note)"; A="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ON="$(printf '%s\n' "$RN1" | sed -n 's/^`landing-report --rows` at [0-9a-f]* on \(.*\):$/\1/p')"
expect_contains "(f0) setup: the landing report reads the record's two landings" "queue=1 hand=1" "$LR1"
expect_regex "(f1) release-note names the instant it rendered for" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$ON"
expect_eq "(f1) …an instant between the two read before and after it ran" "$B $A" "$(printf '%s\n%s\n%s\n' "$B" "$ON" "$A" | sort | sed -n '1p;3p' | tr '\n' ' ' | sed 's/ $//')"
RNE="$(rn_note --on 2026-01-02T01:30:00Z)"; E="$(rn_entry "$RNE")"; rn_pub T9 "$E" hand 2026-01-02T02:00:00Z
rn_doctor() { sed "$1" "$R/CHANGELOG.md" > "$TMP/rn.cl" && cp "$TMP/rn.cl" "$R/CHANGELOG.md"; git -C "$R" commit -q -am doctored >/dev/null; git -C "$R" rev-parse HEAD; git -C "$R" reset -q --hard "$E"; }
D="$(rn_doctor 's/ hand=1 / hand=2 /')"; K="$(rn_doctor 's/killed=0/killed=5/')"
L3="$(rn_commit l3)"; rn_pub T3 "$L3" hand 2026-01-02T03:00:00Z
expect_ne "(f2) setup: the later landings move the landing report" "$LR1" "$(cd "$R" && bash "$POKER" landing-report --rows "$RN_PLAN" 2>&1)"
expect_eq "(f2) …and release-note for the entry's head and instant still prints the entry's block" "$RNE" "$(rn_note --at "$L2" --on 2026-01-02T01:30:00Z)"
rn_check "$E"
expect_status "(f3) the entry at its own head, carried by T9's landing: the check passes" 0 "$RC"
rn_check "$D"
expect_status "(f4) §FROM-REPORT a typed number that disagrees with the report at the entry's head: the check fails" 1 "$RC"
rn_check "$K"
expect_status "(f5) the killed count, which the gate holds and prunes, is not held to the report" 0 "$RC"
expect_contains "(f5) …and the rest still agrees" "landing-numbers: 2.2.4 agrees" "$OUT"

section "§LAST — the entry is written after the last landing it describes"

rn_check HEAD
expect_status "(t1) §LAST T3 landed after the entry's head, no rewrite: the check fails" 1 "$RC"
expect_eq "(t1) …in one line" "1" "$(lines_of "$OUT")"
rn_check "$(rn_entry "$(rn_note --on 2026-01-02T03:30:00Z)")"
expect_status "(t2) the entry rendered again at the new head: the check passes" 0 "$RC"
# A real CHANGELOG runs past a pipe's buffer, so the carrier is read whole after its match; here the carrier is a merge.
RNL="$(rn_note --on 2026-01-02T04:30:00Z)"; git -C "$R" checkout -q -b carry
{ printf '# Changelog\n\n## 2.2.4 — 2026-01-02\n\n- a change\n\n%s\n## 0.0.1 — 2026-01-01\n\n' "${RNL%rc=0}"
  awk 'BEGIN { for (i = 0; i < 20000; i++) print "- an older line" }'; } > "$R/CHANGELOG.md"
git -C "$R" commit -q -am "the long entry"; git -C "$R" checkout -q -; git -C "$R" merge -q --no-ff -m "land" carry
M="$(git -C "$R" rev-parse HEAD)"; rn_pub T7 "$M" hand 2026-01-02T05:00:00Z
expect_eq "(t3) setup: the carrier is a merge of two parents" "2" "$(git -C "$R" rev-list --parents -n 1 "$M" | wc -w | awk '{ print $1 - 1 }')"
rn_check "$M"
expect_contains "(t3) §LAST the merge that carried a long entry is the newest landing: the check agrees" "landing-numbers: 2.2.4 agrees" "$OUT"


section "§PROJECT — the check run from a tree with no plan reads the project's plan and record from BIONIC_CHECK_PROJECT"

# FIXTURE FIDELITY: the judge runs in a landing tree, a detached worktree of the project with no `.bionic` beside it,
# so the plan and the landing record are only where the project keeps them. Two projects: §LIMITS's world with one
# unstated deferral of 2.2.4, and §LAST's world at the merge whose numbers agree. Each is judged from a tree of its
# own, once with BIONIC_CHECK_PROJECT naming the project and once without it. SYNTHESIZED: as §LIMITS and §LAST.
pj_tree() {  # <repo> <rev> -> a detached worktree of <repo> at <rev>, under its own ignored tmp, with no .bionic
  local t="$1/.bionic/tmp/landing/1"
  git -C "$1" worktree add -q --detach "$t" "$2" >/dev/null 2>&1 && printf '%s' "$(cd "$t" && pwd -P)"
}
pj_check() {  # <tree> <head> [<project>] -> OUT, RC: the check run in <tree>, the project named only when given
  OUT="$(cd "$1" && env -u BIONIC_CHECK_BASE -u BIONIC_CHECK_PROJECT BIONIC_CHECK_HEAD="$2" \
    ${3:+BIONIC_CHECK_PROJECT="$3"} bash "$CHECK" "$LIST" 2>&1)"; RC=$?
}
R="$TMP/pj-lim"; fx_repo "$R" 2.2.4 2.2.4; lim_plan "$R" 2.2.4 "$LIM_UNSTATED"; lim_changelog "$R" "- Known limit: none of note."
PJ_T="$(pj_tree "$R" HEAD)"
expect_eq "(pj0) setup: the tree is the project's head, and holds no plan" "$(git -C "$R" rev-parse HEAD) no" \
  "$(git -C "${PJ_T:-/nonexistent}" rev-parse HEAD 2>/dev/null) $([ -e "${PJ_T:-/nonexistent}/.bionic" ] && echo yes || echo no)"
pj_check "$PJ_T" HEAD "$(cd "$R" && pwd -P)"
expect_status "(pj1) §PROJECT AC-2.2 with BIONIC_CHECK_PROJECT naming the project, an unstated deferral refuses from the tree" 1 "$RC"
expect_contains "(pj1b) …naming the deferral of the project's plan" "$(L2_LINE)" "$OUT"
pj_check "$PJ_T" HEAD
expect_status "(pj2) CONTROL with the variable unset, the same tree passes" 0 "$RC"
expect_contains "(pj2b) CONTROL …saying no plan under the tree's own docs names the release" \
  "known-limits: 2.2.4 — no plan under $PJ_T/.bionic/docs names release: 2.2.4" "$OUT"

# §LAST's world: its numbers agree at the merge M, the plan and the record read from the project.
R="$TMP/rn"; PJ_T="$(pj_tree "$R" "$M")"
pj_check "$PJ_T" "$M" "$(cd "$R" && pwd -P)"
expect_status "(pj3) the landing numbers judged from a tree, the project named: the check passes" 0 "$RC"
expect_contains "(pj3b) …its numbers rendered from the project's plan and record, and agreeing" \
  "landing-numbers: 2.2.4 agrees with the landing report at" "$OUT"
pj_check "$PJ_T" "$M"
expect_contains "(pj4) CONTROL the variable unset: no plan holds the numbers" \
  "landing-numbers: 2.2.4 — no plan under $PJ_T/.bionic/docs names release: 2.2.4" "$OUT"

section "§JOIN — the cap reads the non-whitespace characters of tracked shell files, so joining lines changes no reading"

# fx_lines <n> — n lines of `:`, so n characters; fx_ratio <dir> <tests> <code> — a committed pair holding that many.
fx_lines() { awk -v n="$1" 'BEGIN { for (i = 0; i < n; i++) print ":" }'; }
fx_ratio() {
  fx_repo "$1" 2.2.4 2.2.4 || return 1
  mkdir -p "$1/tests" &&
  fx_lines "$2" > "$1/tests/big.test.sh" && fx_lines "$3" > "$1/code.sh" &&
  git -C "$1" add -A && git -C "$1" commit -q -m "the shell files"
}
fx_commit() { git -C "$1" add -A && git -C "$1" commit -q -m "$2"; }   # <dir> <message>
ratio_line() { printf '%s\n' "$OUT" | /usr/bin/grep 'test-ratio'; }   # -> OUT's reading, a pass's or a refusal's
# run_check_base <repo> <base> — the check at HEAD with BIONIC_CHECK_BASE=<base>, as the release runner passes it; sets OUT and RC
run_check_base() {
  OUT="$(cd "$1" && env -u BIONIC_CHECK_HEAD BIONIC_CHECK_BASE="$2" bash "$CHECK" "$LIST" 2>&1)"; RC=$?
}

R="$TMP/join-split"; fx_ratio "$R" 0 40
printf 'true &&\n  true &&\n  true\n' > "$R/tests/big.test.sh"; fx_commit "$R" "three lines"
run_check "$R"; J_SPLIT="$(ratio_line)"
expect_eq "(J-1) tests on three lines read as their 16 characters against the code's 40" \
  "test-ratio: 16/40 chars · limit 50 · room 34" "$J_SPLIT"
R="$TMP/join-one"; fx_ratio "$R" 0 40
printf 'true && true && true\n' > "$R/tests/big.test.sh"; fx_commit "$R" "one line"
run_check "$R"
expect_eq "(J-2) the same tests joined onto one line read the same" "$J_SPLIT" "$(ratio_line)"
fx_lines 900 > "$R/tests/untracked.test.sh"; fx_lines 1 > "$R/code.sh"
run_check "$R"
expect_eq "(J-3) the head's tree is read, never the working files: an untracked test file and edited code change nothing" \
  "$J_SPLIT" "$(ratio_line)"

# (J-5) the count mode prints the two numbers the cap reads and stops: no list path, no scan, no pair.
R="$TMP/join-split"
run_check "$R" --count HEAD
expect_eq "(J-5) --count HEAD prints the tests and the code the J-1 line reads, and nothing else" "16 40" "$OUT"
expect_status "(J-5b) …and exits 0" 0 "$RC"
# (J-6) it reads the committed tree, as the cap does: files in the working directory change nothing.
fx_lines 900 > "$R/tests/untracked.test.sh"; fx_lines 1 > "$R/code.sh"
run_check "$R" --count HEAD
expect_eq "(J-6) an untracked test file and edited code change nothing" "16 40" "$OUT"
# (J-7) a name that is no revision exits 1 and prints nothing on stdout.
J7_OUT="$(cd "$R" && bash "$CHECK" --count no-such-rev 2>/dev/null)"; J7_RC=$?
expect_status "(J-7) a name that is not a revision: exit 1" 1 "$J7_RC"
expect_eq "(J-7b) …and nothing on stdout" "" "$J7_OUT"
J7_OUT="$(cd "$R" && bash "$CHECK" --count 2>/dev/null)"; J7_RC=$?
expect_status "(J-7c) no revision named: refused, exit 2" 2 "$J7_RC"

# (J-4) a link is no blob of text, so a directory reached through one counts once, by its real files.
R="$TMP/ratio-link"; fx_repo "$R" 2.2.4 2.2.4
mkdir -p "$R/lib" "$R/tests" && fx_lines 20 > "$R/lib/x.sh" && fx_lines 5 > "$R/tests/t.test.sh"
ln -s lib "$R/lib2" && ln -s lib/x.sh "$R/alias.sh" && ln -s ../lib "$R/tests/viaLink"
git -C "$R" rm -q -f code.sh && fx_commit "$R" "links"
expect_eq "(J-4) setup: the links are committed as links" "3" "$(git -C "$R" ls-tree -r HEAD | awk '$1 == "120000"' | wc -l | tr -d ' ')"
run_check "$R"
expect_eq "(J-4b) …the code is the 20 characters of the real file, counted once, and the tests are their own 5" \
  "test-ratio: 5/20 chars · limit 25 · room 20" "$(ratio_line)"

section "§DELETE — the limit is 1.25 times the larger of the head's code and the base's, so deleting code takes no room"

# One character of room at the base: 49 test characters against 40 of code, a limit of 50.
R="$TMP/delete"; fx_ratio "$R" 49 40; D_BASE="$(git -C "$R" rev-parse HEAD)"
fx_lines 20 > "$R/code.sh"; fx_commit "$R" "half the code deleted"
run_check_base "$R" "$D_BASE"
expect_status "(D-1) a commit that only deletes code is admitted" 0 "$RC"
expect_eq "(D-1b) …its limit set by the base's 40 characters of code, not the head's 20" \
  "test-ratio: 49/20 chars · limit 50 · room 1" "$(ratio_line)"
printf ':\n' >> "$R/tests/big.test.sh"; fx_commit "$R" "one test line"
run_check_base "$R" "$D_BASE"
expect_status "(D-2) the next commit, which adds one test line, is admitted too" 0 "$RC"
expect_eq "(D-2b) …into the room the deletion left standing" "test-ratio: 50/20 chars · limit 50 · room 0" "$(ratio_line)"
run_check "$R"
expect_status "(D-3) CONTROL with no base, the same head is judged on its own 20 characters of code: refused" 1 "$RC"
run_check_base "$R" "0000000000000000000000000000000000000000"
expect_status "(D-4) …and so it is under a base that names no commit, which compares nothing" 1 "$RC"
expect_absent "(D-4b) …with no base counts invented" "limit 50" "$OUT"

section "§OVER — a head whose test characters pass 1.25 times its code is refused, unless they are at or under the base's"

R="$TMP/over"; fx_ratio "$R" 51 40
run_check "$R"
expect_status "(O-1) 51 test characters against 40 of code, past the limit of 50: the check fails" 1 "$RC"
expect_eq "(O-1b) …in one line naming both counts" \
  "release-check: test-ratio: 51/40 chars · limit 50 · room -1 — tests pass 1.25 times the code at HEAD" "$(ratio_line)"
expect_eq "(O-1c) …and no other line of its own" "1" "$(lines_of "$OUT")"
R="$TMP/over-base"; fx_ratio "$R" 60 40; O_BASE="$(git -C "$R" rev-parse HEAD)"
fx_lines 59 > "$R/tests/big.test.sh"; fx_commit "$R" "one test character cut"
run_check_base "$R" "$O_BASE"
expect_status "(O-2) over the limit at the base, one test character cut: admitted" 0 "$RC"
expect_eq "(O-2b) …the line saying the room is still short" "test-ratio: 59/40 chars · limit 50 · room -9" "$(ratio_line)"
fx_lines 61 > "$R/tests/big.test.sh"; fx_commit "$R" "two test characters added"
run_check_base "$R" "$O_BASE"
expect_status "(O-3) …and once the tests rise past the base's 60: refused" 1 "$RC"
expect_contains "(O-3b) …naming both counts" "test-ratio: 61/40 chars" "$OUT"

# (O-4) no shell outside tests/ is no code to count against: a refusal, never a pass.
R="$TMP/ratio-nocode"; fx_repo "$R" 2.2.4 2.2.4
git -C "$R" rm -q -f code.sh; mkdir -p "$R/tests"; fx_lines 3 > "$R/tests/t.test.sh"; fx_commit "$R" "tests only"
run_check "$R"
expect_status "(O-4) a head with no shell outside tests/: the check refuses (exit 2)" 2 "$RC"
expect_contains "(O-4b) …in a line that says so" "no shell file outside tests/" "$OUT"
expect_eq "(O-4c) …one line" "1" "$(lines_of "$OUT")"

section "§LINE — a pass and a refusal each print the reading, the limit and the room; the limit rounds down"

# 41 characters of code allow 51.25, so 51. The readers of this line are pinned in release-approval.test.sh §RATIO.
R="$TMP/line"; fx_ratio "$R" 51 41
run_check "$R"
expect_status "(L-1) tests at the limit: a pass" 0 "$RC"
expect_eq "(L-1b) …printing room 0" "test-ratio: 51/41 chars · limit 51 · room 0" "$(ratio_line)"
printf ':\n' >> "$R/tests/big.test.sh"; fx_commit "$R" "one test character past"
run_check "$R"
expect_status "(L-2) one character past it: a refusal" 1 "$RC"
expect_eq "(L-2b) …printing room -1" \
  "release-check: test-ratio: 52/41 chars · limit 51 · room -1 — tests pass 1.25 times the code at HEAD" "$(ratio_line)"

section "§CORR — the 1.19.0 entry names the run and corrects 1.18.0 (REQ-8 AC-8.1, AC-8.3, AC-8.4; REQ-9 AC-9.1, AC-9.2)"

CL="${BIONIC_SCRIPTS_DIR}/CHANGELOG.md"

# doctor <name> <command…> — the CHANGELOG through <command>, to \$TMP/doctored.<name>, proved different
doctor() {
  local name="$1"; shift
  "$@" < "$CL" > "$TMP/doctored.$name"
  expect_false "(s3) setup: the $name copy differs from the CHANGELOG" cmp -s "$CL" "$TMP/doctored.$name"
}

# cl_block <file> <version> — the block's lines, heading included, up to the next `## ` heading
cl_block() {
  awk -v v="$2" '/^## / { inb = (index($0, "## " v " ") == 1) } inb' "$1"
}
# cl_cksum — the cksum of stdin, trailing blanks trimmed
cl_cksum() { cksum | sed 's/[[:space:]]*$//'; }

# The 1.18.0 block as released: its cksum at 3287c6a7, the commit before wave-36 (AC-8.4: the 1.19.0 entry
# corrects it and the block itself is never edited).
BLOCK_1180_CKSUM="2015167781 19033"

PLUGIN_JSON="${BIONIC_SCRIPTS_DIR}/payload/.claude-plugin/plugin.json"
# a released record's name holds a verb since removed, read from the deletion list so that no line of this suite spells it
RC_TS="$(/usr/bin/grep -o '`task[-]set`' "${BIONIC_SCRIPTS_DIR}/tests/fixtures/deletion-list.txt" | tr -d '`')"
# Every landed build row of the run and the record that proves it; the entry names each record
ROWS_1190="T1:T1-run-on-branch.md T2:T2-restart-truth.md T3:T3-placement.md T4:T4-jurisdiction.md
T5:T5-reads-index.md T6:T6-pinned-text.md T7:T7-cover-judge.md T8:T8-fixed-move.md T9:T9-run-sessions.md
T10:T10-closure-and-markers.md T11:T11-gate-lifecycle.md T12:T12-branch-reads.md T13:T13-debt-grammar.md
T14:T14-close-out-state.md T15:T15-doctrine.md T24:T24-block-heading.md T25:T25-callers.md
T27:T27-consumers.md T28:T28-verbs-ask-the-judge.md T29:T29-launch-arm-and-adopt.md
T30:T30-start-hook-bash5.md T31:T31-fix-seen-by-asker.md T32:T32-one-width-fact.md T33:T33-said-no-pipe.md
T34:T34-taking-lock-stale.md T35:T35-floor-is-a-fact.md T36:T36-stop-wall-pins.md T37:T37-shell-lint-reds.md
T38:T38-one-roster-reader.md T39:T39-sp2-pins.md T40:T40-tick-asks-once.md T41:T41-$RC_TS-files.md
T42:T42-born-floor-backed.md T43:T43-two-cd-chain.md T44:T44-walk-pointer.md T47:T47-adopt-lands-on-whole.md"
# The rows that added a refusal; the Migration paragraph names each (AC-9.2)
MIG_ROWS="T4 T7 T8 T13 T14 T25 T27 T31 T32 T35 T42"

# cl_part <file> <version> <heading> — the lines of the block's `### <heading>` part, up to the next `### ` or `## `
cl_part() {
  awk -v v="$2" -v h="### $3" '
    /^## / { inb = (index($0, "## " v " ") == 1); inp = 0; next }
    !inb { next }
    /^### / { inp = (index($0, h) == 1); next }
    inp' "$1"
}
# cl_lead <file> <version> — the block's lines before its first `### ` part (lead and Migration)
cl_lead() {
  awk -v v="$2" '
    /^## / { inb = (index($0, "## " v " ") == 1); inp = 0; if (inb) print; next }
    !inb { next }
    /^### / { inp = 1 }
    !inp' "$1"
}
# flat — stdin on one line, white space squeezed, so a wrapped sentence compares as written
flat() { tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g'; }
# has <text> <phrase> — 0 when the phrase is in the text, white space squeezed on both sides
has() { local t p; t="$(printf '%s' "$1" | flat)"; p="$(printf '%s' "$2" | flat)"; case "$t" in *"$p"*) return 0 ;; esac; return 1; }
# plan_deferred <events> [open] — the stated sentence of each deferral, one per line; with `open`, only those of the
# deferrals no later finding event moved to fixed, the ones the check holds the entry to
plan_deferred() {
  awk -F'|' -v open="${2:-}" '
    { delete f; for (i = 3; i <= NF; i++) { k = substr($i, 1, index($i, "=") - 1); f[k] = substr($i, length(k) + 2) } }
    $2 != "ev=finding" { next }
    FNR == NR { if (f["to"] == "fixed") fixed[f["ref"]] = 1; next }
    f["to"] == "deferred" && ("stated" in f) && !(open != "" && (f["ref"] in fixed)) { print f["stated"] }' "$1" "$1"
}

# corr_check <file> <plugin.json> — one `corr:` line per broken rule; no output when all hold
corr_check() {
  local f="$1" pj="$2" blk cor lim mig lead s n pair row rec stated actual t13 t13hit
  blk="$(cl_block "$f" 1.19.0)"
  [ -n "$blk" ] || { echo "corr: no 1.19.0 block"; return 0; }
  grep -q -E '^## 1\.19\.0 — 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]$' <<<"$blk" || echo "corr: the 1.19.0 heading carries no date"
  lead="$(cl_lead "$f" 1.19.0)"
  for s in 'zero machine errors' 'D7' 'D14'; do
    has "$lead" "$s" || echo "corr: the lead does not name $s"
  done
  mig="$(printf '%s\n' "$lead" | awk '/^\*\*Migration\.\*\*/ { m = 1 } m')"
  [ -n "$mig" ] || echo "corr: no Migration paragraph"
  for s in $MIG_ROWS; do
    grep -q -w -- "$s" <<<"$mig" || echo "corr: Migration does not name $s"
  done
  # T13's bullet names the refusal of the two verbs that apply the debt grammar to a carried line (D14; AC-9.2)
  t13="$(printf '%s\n' "$mig" | awk '/^- T13:/ { p = 1; print; next } p && /^- / { p = 0 } p')"
  t13hit="$(printf '%s\n' "$t13" | flat | awk '{ n = split($0, a, /\. /); for (i = 1; i <= n; i++) print a[i] }' \
    | grep -F -- 'debt adopt' | grep -F -- 'Step-1 card' | grep -F -- 'refuse' | grep -F -- 'prose site' \
    | grep -F -- 'unlisted kind' | grep -F -- '1.18.0' || true)"
  [ -n "$t13hit" ] || echo "corr: the T13 Migration bullet does not say debt adopt and the Step-1 card refuse a prose site or an unlisted kind"
  cor="$(cl_part "$f" 1.19.0 'Corrections to 1.18.0')"
  [ -n "$cor" ] || echo "corr: no Corrections to 1.18.0 section"
  has "$cor" '`T31-verify-gate.md`' && has "$cor" 'no floor proof line' || echo "corr: Corrections does not name T31's floor-proof refusal"
  has "$cor" '`T32-floor-run-dirty.md`' && has "$cor" 'dirty checkout' || echo "corr: Corrections does not name T32's dirty-checkout refusal"
  has "$cor" 'A-orch-50' && has "$cor" 'text-only' || echo "corr: Corrections does not name the text-only floor arm"
  has "$cor" 'D22' || echo "corr: Corrections does not name D22's two deferred sentences"
  has "$cor" 'three fixes' && has "$cor" 'T34' && has "$cor" 'A-orch-48' || echo "corr: Corrections does not correct the count of fixes the review ordered"
  lim="$(cl_part "$f" 1.19.0 'Known limits')"
  [ -n "$lim" ] || echo "corr: no Known limits section"
  stated="$(printf '%s\n' "$lim" | flat | sed -n 's/.*The count of Known limits in this block is \([0-9][0-9]*\)\..*/\1/p')"
  actual="$(printf '%s\n' "$lim" | grep -c -E '^- Known limit' || true)"
  if [ -z "$stated" ]; then echo "corr: the count of Known limits is not stated"
  elif [ "$stated" != "$actual" ]; then echo "corr: the count says $stated and Known limits holds $actual"; fi
  for pair in $ROWS_1190; do
    row="${pair%%:*}"; rec="${pair#*:}"
    grep -q -F -- '`'"$rec"'`' <<<"$blk" || echo "corr: the entry names no record for $row ($rec)"
  done
  has "$blk" 'T33, T36, T37, T38, T39 and T40' && has "$blk" '`born: floor`' || echo "corr: the entry does not name the six rows born: floor"
  [ "$(cl_block "$f" 1.18.0 | cl_cksum)" = "$BLOCK_1180_CKSUM" ] || echo "corr: the 1.18.0 block is not as released"
  return 0
}
# help_check — the rendered pages read the plugin's version and are the pages render.sh renders
help_check() {
  local ver pg
  ver="$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)"
  for pg in help version; do
    grep -q -F -- "bionic $ver (installed)" "${BIONIC_SCRIPTS_DIR}/payload/commands/$pg.md" || echo "corr: payload/commands/$pg.md does not read bionic $ver (installed)"
  done
  bash "${BIONIC_SCRIPTS_DIR}/agents-src/render.sh" --check >/dev/null 2>&1 || echo "corr: render.sh --check is not green"
}

# --- the extractors are not vacuous
expect_eq "(c0) the table of build rows holds 36 rows" "36" "$(printf '%s\n' $ROWS_1190 | grep -c .)"

# --- the repository's own entry keeps every rule
expect_eq "(c1) …and the rendered pages read plugin.json's version and are the rendered pages" "" "$(help_check)"

# --- doctored copies: each rule has one that goes red, named by its rule
cor_check() { corr_check "$1" "$PLUGIN_JSON"; }
doctor c_no119 sed 's/^## 1\.19\.0 — /## 1.18.9 — /'
expect_contains "(c2a) no 1.19.0 block: red" "corr: no 1.19.0 block" "$(cor_check "$TMP/doctored.c_no119")"
doctor c_nocor sed 's/^### Corrections to 1\.18\.0/### Notes/'
expect_contains "(c2b) a block with no Corrections section: red" "corr: no Corrections to 1.18.0 section" "$(cor_check "$TMP/doctored.c_nocor")"
doctor c_t31 sed 's/T31-verify-gate\.md/the-record/g'
doctor c_t32 perl -0pe 's/dirty\s+checkout/dirty tree/g'
doctor c_textonly sed 's/text-only/wall-only/g'
doctor c_d22 sed 's/D22/D2x/g'
doctor c_count sed 's/three fixes/four fixes/g'
doctor c_d22a sed 's/still admits a finding the person moved to defer/admits a finding/'
doctor c_d22b sed 's/lists nothing for that session/lists nothing/'
doctor c_floorarm sed 's/it reads text only/it reads the tree/'
doctor c_klcount sed 's/The count of Known limits in this block is [0-9]*\./The count of Known limits in this block is 99./'
expect_contains "(c2l) a stated count that is not the bullets counted: red" "corr: the count says 99" "$(cor_check "$TMP/doctored.c_klcount")"
doctor c_klnone sed 's/The count of Known limits in this block is/The Known limits here number/'
doctor c_mig awk '/^\*\*Migration\.\*\*/ { m = 1 } m && /^### / { m = 0 } m { gsub(/T35/, "Tnn") } { print }'
expect_contains "(c2n) a Migration paragraph that does not name T35: red" "corr: Migration does not name T35" "$(cor_check "$TMP/doctored.c_mig")"
doctor c_t13 sed 's/`debt adopt` and the Step-1 card now refuse/the card now refuses/'
doctor c_rec sed 's/`T27-consumers\.md`/the record/g'
doctor c_born sed 's/T33, T36, T37, T38, T39 and T40/the six rows/'
doctor c_edit1180 awk '{ print } /^## 1\.18\.0 — /{ print "" }'
doctor c_nodate sed 's/^## 1\.19\.0 — .*/## 1.19.0 —/'

# rel_world <dir> <changelog> <version> <events> — a committed repository holding <changelog> as its CHANGELOG and, in
# its run's log, the run's finding events from <events>: each deferral and each later move of one, so the declared check
# judges the entry as the door will
rel_world() {
  fx_repo "$1" 2.2.4 "$3" && lim_plan "$1" "$3" "$(/usr/bin/grep '^run/v1|ev=finding|' "$4")" &&
  { cat "$2"; printf '\n## 0.0.1 — 2026-01-01\n\n- first\n'; } > "$1/CHANGELOG.md" &&
  git -C "$1" add CHANGELOG.md && git -C "$1" commit -q -m "the $3 entry"
}

section "§REL-1.28.0 — the real 1.28.0 entry passes over its run's deferrals, a deferral later moved to fixed not held"

# The run's deferrals and their moves, cut from its closed plan as the log holds a finding: each deferral dated before
# the first move, each move at its own instant; a move's words, session and why are kept, since a move to defer or fix
# without them reads as no move, and its author is a stand-in. A deferral the person moved to fixed is owed no Known
# limit, so the real entry passes only when the check reads the move.
REL_PLAN="${BIONIC_SCRIPTS_DIR}/tests/fixtures/release-check/wave-45-findings.txt"
REL_N="$(plan_deferred "$REL_PLAN" open | /usr/bin/grep -c .)"
expect_true "(n0) setup: the run's deferred sentences are read, at least one" [ "$REL_N" -gt 0 ]
expect_true "(n0) setup: …and fewer than its deferrals, so a move to fixed is in the fixture" \
  [ "$REL_N" -lt "$(plan_deferred "$REL_PLAN" | /usr/bin/grep -c .)" ]
cl_block "$CL" 1.28.0 | awk '/^### / { skip = ($0 == "### The landing numbers") } !skip' > "$TMP/rel28.entry"
cl_block "$CL" 1.28.0 | awk '/^### / { skip = ($0 == "### The landing numbers" || $0 == "### Known limits") } !skip' > "$TMP/rel28.nolimits"
expect_nonempty "(n0) setup: the entry's Known limits are cut out of a block that exists" "$(cat "$TMP/rel28.nolimits")"
R="$TMP/rel28-real"; rel_world "$R" "$TMP/rel28.entry" 1.28.0 "$REL_PLAN"
run_check "$R"
expect_status "(n3) the real entry, every deferred sentence of the run's plan under Known limits: the check passes" 0 "$RC"
expect_contains "(n3) …carrying each deferred sentence" "known-limits: 1.28.0 carries the $REL_N deferred sentences" "$OUT"
R="$TMP/rel28-nolimits"; rel_world "$R" "$TMP/rel28.nolimits" 1.28.0 "$REL_PLAN"
run_check "$R"
expect_status "(n4) the same entry with its Known limits removed: the check fails" 1 "$RC"
expect_eq "(n4) …one line for each deferred sentence" "$REL_N" "$(lines_of "$OUT")"
expect_contains "(n4) …naming a finding" "omit the deferred sentence of record/" "$OUT"

section "§JUDGE — the person's typed word moves the judge: a later landing is run by that commit's copy and names the word"

# The release approval card's world: a run bound to this session, typed prompts in its transcript, its base-sha the
# release base. The check is declared as ck.sh, which the base does not hold; the judge J commits a copy that says so
# and fails, and a piece on J rewrites it to pass. The door's run of the check is driven as `line_publish` drives it.
. "$(dirname "$0")/release-approval.prelude.sh"
trap 'cleanup; rm -rf "$TMP"' EXIT
fc_plan "$FC_GOOD"
printf 'release-check: bash ck.sh\n' > "$RFC/.bionic/config.yaml"
JG_J="$(cd "$RFC" && printf 'echo judge-copy; exit 1\n' > ck.sh && git add ck.sh && git commit -qm 'the new check' && git rev-parse HEAD)"
git -C "$RFC" worktree add -q -b piece "$TMPROOT/jg-piece" "$JG_J" && printf 'exit 0\n' > "$TMPROOT/jg-piece/ck.sh"
JG_P="$(cd "$TMPROOT/jg-piece" && git commit -qam 'the piece rewrites the check' && git rev-parse HEAD)"
jg_land() { ( cd "$RFC" && . "$FC_LIB/worktree.sh" && _wt_release_check "$RFC" "$PFC" "$JG_J" "$JG_P" "$TMPROOT/jg-piece" piece wave/01-fixture 2>&1 ); }
jg_events() { /usr/bin/grep -c '^run/v1|ev=approval|key=judge|' "$FC_REC/run.log"; }
JG_W='the new check judges from here'
fc_typed "$JG_W"
JG_OUT="$(jg_land)"
expect_contains "(jg0) with no word the landing is refused as the base-sha's copy holds it" "(base-sha $FC_B)" "$JG_OUT"
expect_absent "(jg0b) …which is not the judge's copy" "judge-copy" "$JG_OUT"
poke "$RFC" check-from 'words nobody typed here'
expect_eq "(jg1) check-from on words no prompt holds is refused, and writes no judge event" "1|0" "$RC|$(jg_events)"
poke "$RFC" check-from "$JG_W" "$JG_P"
expect_eq "(jg2) …and at a commit the working head does not hold" "1|0" "$RC|$(jg_events)"
poke "$RFC" check-from "$JG_W"
expect_eq "(jg3) on the person's words it writes one judge event at the working head, naming who typed them" "0|1" \
  "$RC|$(/usr/bin/grep -c "^run/v1|ev=approval|key=judge|by=Dana Fixture|head=$JG_J|said=$JG_W|session=$SID|" "$FC_REC/run.log")"
JG_OUT="$(jg_land)"
expect_contains "(jg4) a later landing that rewrites the check is run by the judge's copy, not its own" "judge-copy" "$JG_OUT"
expect_contains "(jg5) …and its line names the judge, the word and whose it was" \
  "(the judge ${JG_J:0:12}, set by Dana Fixture's word \"$JG_W\")" "$JG_OUT"

section "§RELEASE — two landings through the runner: code deleted during a release takes no room from the landing after"

# A landing's BIONIC_CHECK_BASE is the target's head before it, so after a landing that deletes code the base is the
# smaller code; the runner's BIONIC_CHECK_RELEASE, the plan's base-sha here, keeps the release's code in the limit. The
# check is declared by its path in this suite's tree, outside the fixture, so the runner runs this copy whatever the
# judge holds; which copy judges is §JUDGE's. One character of room at the release: 49 test characters against 40.
RL="$TMP/release"; fx_ratio "$RL" 49 40; RL_B="$(git -C "$RL" rev-parse HEAD)"
mkdir -p "$RL/.bionic/docs/plans" "$RL/.git/info" && printf '.bionic/\n' >> "$RL/.git/info/exclude"
expect_eq "(rl0) the fixture's exclude file holds the line written into it: init --template= made no .git/info, so the section makes it" \
  ".bionic/" "$(cat "$RL/.git/info/exclude" 2>&1)"
printf 'release-check: bash %s %s\n' "$CHECK" "$LIST" > "$RL/.bionic/config.yaml"
RL_PLAN="$RL/.bionic/docs/plans/x.plan.md"
printf -- '---\nbase-sha: %s\nintegration-branch: main\n---\n# plan\n' "$RL_B" > "$RL_PLAN"
git -C "$RL" worktree add -q -b rl-piece "$TMP/rl-piece" "$RL_B"
fx_lines 20 > "$TMP/rl-piece/code.sh"; fx_commit "$TMP/rl-piece" "half the code deleted"; RL_P1="$(git -C "$RL" rev-parse rl-piece)"
printf ':\n' >> "$TMP/rl-piece/tests/big.test.sh"; fx_commit "$TMP/rl-piece" "one test line"; RL_P2="$(git -C "$RL" rev-parse rl-piece)"
rl_land() { ( cd "$RL" && . "$FC_LIB/worktree.sh" && _wt_release_check "$RL" "$RL_PLAN" "$1" "$2" "$TMP/rl-piece" rl-piece main 2>&1 ); }
RL_OUT="$(rl_land "$RL_B" "$RL_P1")"; RC=$?
expect_status "(rl1) the landing that only deletes code is admitted" 0 "$RC"
RL_OUT="$(rl_land "$RL_P1" "$RL_P2")"; RC=$?
expect_status "(rl2) the next landing, onto the deletion, which adds one test line, is admitted too" 0 "$RC"
[ "$RC" = 0 ] || printf '      the landing said: %s\n' "$RL_OUT" | head -3
OUT="$(cd "$RL" && env BIONIC_CHECK_HEAD="$RL_P2" BIONIC_CHECK_BASE="$RL_P1" BIONIC_CHECK_RELEASE="$RL_B" bash "$CHECK" "$LIST" 2>&1)"
expect_eq "(rl3) the check as the runner calls it there counts the release's 40 characters of code" \
  "test-ratio: 50/20 chars · limit 50 · room 0" "$(ratio_line)"
OUT="$(cd "$RL" && env -u BIONIC_CHECK_RELEASE BIONIC_CHECK_HEAD="$RL_P2" BIONIC_CHECK_BASE="$RL_P1" bash "$CHECK" "$LIST" 2>&1)"
expect_contains "(rl4) CONTROL with no release named, the same range is refused on the base's 20 characters" \
  "release-check: test-ratio: 50/20 chars · limit 25" "$OUT"

section "§HOLD — the project's check is started holding nothing, so its facts are folded by its own reader"

# A held command's reads are bionic's for that one command (lib/proof.sh `_proof_held_dir`); the project's check runs
# at the judge, whose reader may not be the verb's, so it must not be handed the verb's hold. The check here prints
# what it was handed; the run is made from inside an open hold, as the release-check verb makes it.
HL="$TMP/hold"; fx_repo "$HL" 1.0.0 1.0.0
mkdir -p "$HL/.bionic/docs/plans" "$HL/.git/info" && printf '.bionic/\n' >> "$HL/.git/info/exclude"
printf 'release-check: bash ck.sh\n' > "$HL/.bionic/config.yaml"
printf 'echo "check: held=${BIONIC_HELD:-none} judge-head=${BIONIC_CHECK_HEAD:-}"\n' > "$HL/ck.sh"
fx_commit "$HL" "the check"; HL_J="$(git -C "$HL" rev-parse HEAD)"
printf -- '---\nbase-sha: %s\nintegration-branch: main\n---\n# plan\n' "$HL_J" > "$HL/.bionic/docs/plans/x.plan.md"
HL_OUT="$( cd "$HL" && . "$FC_LIB/worktree.sh" && . "$FC_LIB/proof.sh" && proof_hold_begin || exit 3
  printf 'caller: held=%s\n' "${BIONIC_HELD:+yes}"
  worktree_check_run "$HL" "$HL/.bionic/docs/plans/x.plan.md" "$HL_J" "$HL_J" "$HL_J"; printf 'rc=%s\n%s\n' "$?" "$WT_CHECK_OUT"
  proof_hold_end )"
expect_contains "(hl0) the caller held its reads when it ran the check" "caller: held=yes" "$HL_OUT"
expect_contains "(hl1) the check ran at the judge and printed what it was handed" "check: held=" "$HL_OUT"
expect_contains "(hl2) …which is the head it judges, so the line is the check's own" "judge-head=$HL_J" "$HL_OUT"
expect_contains "(hl3) …and no hold: the project's command is started holding nothing" "check: held=none " "$HL_OUT"

section "§ONE-READER — a planted second parser, plan writer or loader at the head is refused by the check a landing runs"

# A repository whose head holds this checkout's hooks/ and payload/scripts/, so the judge's copy check reads a whole
# tree; each plant is one commit on that head of its own, judged through BIONIC_CHECK_HEAD.
OR="$TMP/one-reader"; fx_repo "$OR" 2.2.4 2.2.4
mkdir -p "$OR/payload" && cp -R "$BIONIC_SCRIPTS_DIR/hooks" "$OR/hooks" && cp -R "$BIONIC_SCRIPTS_DIR/payload/scripts" "$OR/payload/scripts" \
  && fx_commit "$OR" "the code"; OR_B="$(git -C "$OR" rev-parse HEAD)"
or_plant() {  # <name> <path> <text> -> the commit holding <text> at <path> on the clean head
  git -C "$OR" checkout -q -B "plant-$1" "$OR_B" && printf '%s\n' "$3" > "$OR/$2" && fx_commit "$OR" "plant $1" && git -C "$OR" rev-parse HEAD
}
or_check() { OUT="$(cd "$OR" && env -u BIONIC_CHECK_BASE BIONIC_CHECK_HEAD="$1" bash "$CHECK" "$LIST" 2>&1)"; RC=$?; }
OR_P="$(or_plant parse payload/scripts/lib/planted-parse.sh "planted_rows() { awk -F'|' '\$2 ~ /^ T[0-9]+ \$/ { print \$2 }' \"\$plan\"; }")"
OR_W="$(or_plant write payload/scripts/lib/planted-write.sh "planted_line() { printf -- '- %s: landed\\n' \"\$1\" >> \"\$plan\"; }")"
OR_L="$(or_plant loader hooks/planted-loader.sh "$(printf '#!/bin/bash\n# --- bionic-loader/v2 BEGIN')")"
git -C "$OR" checkout -q -B main "$OR_B"
or_check "$OR_B"
expect_status "(or0) the clean head passes" 0 "$RC"
expect_regex "(or0) …with one line of its counts, each nought" "^one-reader: parsers=0 ([a-z_]+=0 )+homes=0$" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep '^one-reader: ')"
or_check "$OR_P"
expect_eq "(or1) a second parser at the head fails the release in one line naming it" \
  "1|1|release-check: one-reader-check: refused — parser payload/scripts/lib/planted-parse.sh:1" \
  "$RC|$(lines_of "$OUT")|$(printf '%s\n' "$OUT" | /usr/bin/grep '^release-check: ')"
or_check "$OR_W"
expect_eq "(or2) a second writer of the plan at the head fails it in one line naming it" \
  "1|1|release-check: one-reader-check: refused — plan-writer payload/scripts/lib/planted-write.sh:1" \
  "$RC|$(lines_of "$OUT")|$(printf '%s\n' "$OUT" | /usr/bin/grep '^release-check: ')"
or_check "$OR_L"
expect_eq "(or3) a copied loader at the head fails it in one line naming it" \
  "1|1|release-check: one-reader-check: refused — loader hooks/planted-loader.sh:2" \
  "$RC|$(lines_of "$OUT")|$(printf '%s\n' "$OUT" | /usr/bin/grep '^release-check: ')"
git -C "$OR" show "$OR_P:payload/scripts/lib/planted-parse.sh" > "$OR/payload/scripts/lib/planted-parse.sh"
or_check "$OR_B"
expect_eq "(or4) the parser in the working files alone is not read: the head passes" "0|0" "$RC|$(lines_of "$OUT")"
rm -f "$OR/payload/scripts/lib/planted-parse.sh"
run_check "$TMP/agree"
expect_eq "(or5) a head with no hooks/ and payload/scripts/ passes, saying it holds no copy to count" \
  "0|one-reader: HEAD holds no hooks/ and payload/scripts/, so no copy to count" "$RC|$(printf '%s\n' "$OUT" | /usr/bin/grep '^one-reader: ')"

section "§DEFER-LANDING — a landing that leaves the entry as it was is told of a deferral's missing sentence, and passes"

# §LIMITS-2's world: the plan defers #3 with no sentence and #1 with a sentence the entry omits. Four commits: F, the
# repository with the entry's bare first form; E, the entry with its Known limits; C, a change to code.sh alone; O, an
# edit to the older entry only. Each range is judged as the runner judges a landing, BIONIC_CHECK_BASE its base.
DL_PLAN="$LIM_UNSTATED
$(printf '%s\n' "$LIM_DEFERRED" | sed -n '1p')"
DL_OMIT="release-check: Known limits of 2.2.4 omit the deferred sentence of record/w/critic.md#1: $LIM_A"
R="$TMP/dl"; fx_repo "$R" 2.2.4 2.2.4; DL_F="$(git -C "$R" rev-parse HEAD)"
lim_plan "$R" 2.2.4 "$DL_PLAN"; lim_changelog "$R" "- Known limit: none of note."; DL_E="$(git -C "$R" rev-parse HEAD)"
printf '#!/bin/bash\n:\n:\n:\n' > "$R/code.sh"; fx_commit "$R" "code only"; DL_C="$(git -C "$R" rev-parse HEAD)"
sed 's/^- first$/- first, worded again/' "$R/CHANGELOG.md" > "$TMP/dl.cl" && cp "$TMP/dl.cl" "$R/CHANGELOG.md"
fx_commit "$R" "the older entry only"; DL_O="$(git -C "$R" rev-parse HEAD)"
dl_check() { OUT="$(cd "$R" && env BIONIC_CHECK_BASE="$1" BIONIC_CHECK_HEAD="$2" bash "$CHECK" "$LIST" 2>&1)"; RC=$?; }
dl_notes() { printf '%s\n' "$OUT" | /usr/bin/grep -c '^known-limits: note — '; }
expect_eq "(dl0) setup: the older entry's edit leaves the 2.2.4 entry as E wrote it" "1" \
  "$(git -C "$R" diff "$DL_C" "$DL_O" -- CHANGELOG.md | /usr/bin/grep -c '^+- first, worded again$')"
dl_check "$DL_F" "$DL_E"
expect_status "(dl1) §DEFER-LANDING a landing that writes the entry is refused on the unstated deferral" 1 "$RC"
expect_eq "(dl1) …in its two lines, the unstated one and the omitted one, and no note" "2|1|1|0" \
  "$(lines_of "$OUT")|$(printf '%s\n' "$OUT" | /usr/bin/grep -cxF "$(L2_LINE)")|$(printf '%s\n' "$OUT" | /usr/bin/grep -cxF "$DL_OMIT")|$(dl_notes)"
dl_check "$DL_E" "$DL_C"
expect_status "(dl2) §DEFER-LANDING a landing that changes code only passes" 0 "$RC"
expect_eq "(dl2) …with no release-check line, and each of the two told as a note" "0|2" "$(lines_of "$OUT")|$(dl_notes)"
expect_contains "(dl2) …the unstated one named, with what to do" \
  "known-limits: note — 2.2.4 defers record/w/critic.md#3 with no stated sentence; state it or fix it" "$OUT"
expect_contains "(dl2) …the omitted one named with its sentence" "known-limits: note — Known limits of 2.2.4 omit the deferred sentence of record/w/critic.md#1: $LIM_A" "$OUT"
expect_contains "(dl2) …and one line says why it passes, and what still refuses" \
  "known-limits: 2.2.4 — this range leaves the entry as it was, so these are notes; a range that changes the entry refuses them" "$OUT"
dl_check "$DL_C" "$DL_O"
expect_eq "(dl3) a landing that edits an older entry only leaves this one as it was: it passes with the two notes" "0|0|2" \
  "$RC|$(lines_of "$OUT")|$(dl_notes)"
dl_check "$DL_F" "$DL_C"
expect_eq "(dl4) a range that spans the entry's change, as the release check's does, is refused" "1|2|0" "$RC|$(lines_of "$OUT")|$(dl_notes)"
OUT="$(cd "$R" && env -u BIONIC_CHECK_BASE BIONIC_CHECK_HEAD="$DL_C" bash "$CHECK" "$LIST" 2>&1)"; RC=$?
expect_eq "(dl5) no range named, the check run by hand: the code-only head is refused" "1|2|0" "$RC|$(lines_of "$OUT")|$(dl_notes)"

section "§NUMBERS-FLOOR — from 2.3.0 an entry with no landing numbers fails where the entry is asked; 2.2.0's passes"

# The repository's own entries: 2.2.0 shipped with no landing numbers, and the floor is the release after it. N0 is a
# repository whose newest entry is 2.2.0; N1 adds a 2.3.0 entry with no numbers (the version bumped with it); N2 changes
# code alone on top. No plan names either release.
NF_LINE='release-check: 2.3.0 holds no landing numbers; paste release-note'
R="$TMP/nf"; fx_repo "$R" 2.2.0 2.2.0; NF_0="$(git -C "$R" rev-parse HEAD)"
run_check "$R"
expect_eq "(nf1) §NUMBERS-FLOOR the 2.2.0 entry with no landing numbers passes, and says it names no head" \
  "0|0|landing-numbers: 2.2.0 — the entry names no head its numbers were rendered at, so none is held to the report" \
  "$RC|$(lines_of "$OUT")|$(printf '%s\n' "$OUT" | /usr/bin/grep '^landing-numbers: ')"
fx_changelog 2.3.0 > "$R/CHANGELOG.md"; fx_plugin 2.3.0 > "$R/payload/.claude-plugin/plugin.json"
fx_commit "$R" "the 2.3.0 entry"; NF_1="$(git -C "$R" rev-parse HEAD)"
printf '#!/bin/bash\n:\n' > "$R/code.sh"; fx_commit "$R" "code only"; NF_2="$(git -C "$R" rev-parse HEAD)"
run_check "$R"
expect_eq "(nf2) §NUMBERS-FLOOR a 2.3.0 entry with no landing numbers fails the check run by hand, in one line" \
  "1|1|$NF_LINE" "$RC|$(lines_of "$OUT")|$(printf '%s\n' "$OUT" | /usr/bin/grep '^release-check: ')"
OUT="$(cd "$R" && env BIONIC_CHECK_BASE="$NF_0" BIONIC_CHECK_HEAD="$NF_1" bash "$CHECK" "$LIST" 2>&1)"; RC=$?
expect_eq "(nf3) …and at the landing that writes the entry" "1|1|$NF_LINE" \
  "$RC|$(lines_of "$OUT")|$(printf '%s\n' "$OUT" | /usr/bin/grep '^release-check: ')"
OUT="$(cd "$R" && env BIONIC_CHECK_BASE="$NF_1" BIONIC_CHECK_HEAD="$NF_2" bash "$CHECK" "$LIST" 2>&1)"; RC=$?
expect_eq "(nf4) a landing that leaves the entry as it was passes, told of it as a note" \
  "0|0|landing-numbers: note — 2.3.0 holds no landing numbers; paste release-note" \
  "$RC|$(lines_of "$OUT")|$(printf '%s\n' "$OUT" | /usr/bin/grep '^landing-numbers: note — ')"
NF_FN="$(awk '/^NUMS_RULE_FROM=/' "$CHECK")"
expect_eq "(nf5) the floor is the release after 2.2.0, compared as dotted integers by the Known limits' own comparison" \
  "NUMS_RULE_FROM=2.3.0" "$NF_FN"

finish
