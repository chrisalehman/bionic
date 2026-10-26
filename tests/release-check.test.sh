#!/bin/bash
# Tests for tests/lib/release-check.sh — this repo's `release-check:` command (wave-31 T1; spec
# D1, REQ-3 AC-3.5).
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
#   §RATIO          the cap on tests: the tracked shell lines under tests/ against the tracked shell lines everywhere
#                   else, counted in the tree at BIONIC_CHECK_HEAD. A head whose tests exceed its code is refused in
#                   one line naming both counts; a head under passes with `test-ratio: <tests>/<code>`; the counts are
#                   the head's, never the working files'; a directory reached through a symlink counts once; a head
#                   with no shell code outside tests/ is a refusal, never a pass.
#   §RATIO-BASE     a head over the cap is admitted when its test lines are at or under the tree at BIONIC_CHECK_BASE's
#                   and refused when they rose; the line then carries `(base <tests>/<code>)`; a head under the cap
#                   passes as before; a base that names no commit compares nothing, so the head alone is judged.
#   §CORR           the 1.19.0 entry against wave-36's REQ-8 and REQ-9 (AC-8.1, AC-8.3, AC-8.4, AC-9.1,
#                   AC-9.2): the block exists at its own heading, dated; the Corrections
#                   section names the two refusals 1.18.0 introduced, the text-only floor arm, D22's two
#                   deferred sentences and the corrected fix count; Known limits carries every `deferred:`
#                   stated sentence of the bound plan; Migration names every row that added a refusal; every
#                   build row names its record; the 1.18.0 block is as released; help.md and version.md
#                   read the version and `render.sh --check` is green. Each rule has a doctored copy.
#   §REL-1.27.0     the 1.27.0 entry: the version pair reads 1.27.0, the entry is dated, names ADR-071,
#                   and its Migration paragraph names the rows that changed what a script may meet.
#                   The release check is run on a repository holding the real entry and the run's real deferred lines
#                   (this run states none, so the Known limits arms hold at zero): every deferred sentence stands under
#                   Known limits and the check passes; the same entry with its Known limits removed fails one line for
#                   each deferred sentence, and passes when there are none; one planted deferral keeps the omission arm live.
#   §REL-1.28.0     the 1.28.0 entry: its block's own heading reads 1.28.0, the version pair agrees at the newest heading,
#                   the entry is dated, names its two ADRs and every row that changed what a script may meet, each with a
#                   doctored copy, against a pinned 1.28.0 manifest. The release check is run on a repository holding the
#                   real entry and this run's real deferred lines: every deferred sentence stands under Known limits and it
#                   passes; with its Known limits removed it fails one line for each; one planted deferral keeps that arm live.
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

R="$TMP/agree"; fx_repo "$R" 2.3.4 2.3.4
run_check "$R"
expect_status "(i) an agreeing pair, a clean scan: the check passes" 0 "$RC"

R="$TMP/chg"; fx_repo "$R" 2.3.4 2.3.4
fx_changelog 2.3.5 > "$R/CHANGELOG.md"; git -C "$R" commit -q -am "doctor the heading"
run_check "$R"
expect_status "(ii) a doctored CHANGELOG heading: the check fails" 1 "$RC"
expect_contains "(ii) …and the line names the CHANGELOG's version" "2.3.5" "$OUT"
expect_contains "(ii) …and the line names the plugin's version" "2.3.4" "$OUT"
expect_eq "(ii) …in one line" "1" "$(lines_of "$OUT")"

R="$TMP/plg"; fx_repo "$R" 2.3.4 2.3.4
fx_plugin 2.3.9 > "$R/payload/.claude-plugin/plugin.json"; git -C "$R" commit -q -am "doctor the version"
run_check "$R"
expect_status "(iii) a doctored plugin.json version: the check fails" 1 "$RC"
expect_contains "(iii) …and the line names the plugin's version" "2.3.9" "$OUT"
expect_contains "(iii) …and the CHANGELOG's" "2.3.4" "$OUT"
expect_eq "(iii) …in one line" "1" "$(lines_of "$OUT")"

# (iv) the HEAD tree, not the working file: the working CHANGELOG disagrees, nothing is committed.
R="$TMP/dirty"; fx_repo "$R" 2.3.4 2.3.4
run_check "$R"
expect_status "(iv) setup: the clean repository passes" 0 "$RC"
CLEAN_OUT="$OUT"
fx_changelog 7.7.7 > "$R/CHANGELOG.md"
expect_nonempty "(iv) setup: the repository really is dirty" "$(git -C "$R" status --porcelain)"
run_check "$R"
expect_status "(iv) a working CHANGELOG edited and not committed: the check still passes (HEAD is read)" 0 "$RC"
expect_eq "(iv) …and prints what the clean run of the same repository printed" "$CLEAN_OUT" "$OUT"

# BIONIC_CHECK_HEAD picks the tree: the bad commit is HEAD, the good one is HEAD~1.
R="$TMP/pick"; fx_repo "$R" 2.3.4 2.3.4
fx_changelog 2.3.5 > "$R/CHANGELOG.md"; git -C "$R" commit -q -am "doctor the heading"
run_check "$R"
expect_status "(v) the doctored HEAD fails" 1 "$RC"
OUT="$(cd "$R" && env -u BIONIC_CHECK_BASE BIONIC_CHECK_HEAD='HEAD~1' bash "$CHECK" "$LIST" 2>&1)"; RC=$?
expect_status "(v) …and BIONIC_CHECK_HEAD=HEAD~1 reads the agreeing tree and passes" 0 "$RC"

section "§REFUSE — no list path, and a pair that cannot be read, are one-line refusals"

R="$TMP/refuse"; fx_repo "$R" 2.3.4 2.3.4
OUT="$(cd "$R" && env -u BIONIC_CHECK_BASE -u BIONIC_CHECK_HEAD bash "$CHECK" 2>&1)"; RC=$?
expect_ne "(a) no list path: non-zero" "0" "$RC"
expect_eq "(a) …in one line" "1" "$(lines_of "$OUT")"
run_check "$R" "$TMP/lists/does-not-exist.list"
expect_ne "(b) a list path that is not there: non-zero" "0" "$RC"
expect_eq "(b) …in one line" "1" "$(lines_of "$OUT")"

R="$TMP/nohead"; fx_repo "$R" 2.3.4 2.3.4
printf '# Changelog\n\nno release heading here\n' > "$R/CHANGELOG.md"; git -C "$R" commit -q -am "no heading"
run_check "$R"
expect_ne "(c) a CHANGELOG with no release heading: non-zero" "0" "$RC"
expect_eq "(c) …in one line" "1" "$(lines_of "$OUT")"

R="$TMP/nover"; fx_repo "$R" 2.3.4 2.3.4
printf '{ "name": "fixture" }\n' > "$R/payload/.claude-plugin/plugin.json"; git -C "$R" commit -q -am "no version"
run_check "$R"
expect_ne "(d) a plugin.json with no version: non-zero" "0" "$RC"
expect_eq "(d) …in one line" "1" "$(lines_of "$OUT")"

section "§SCAN — the name scan still runs under the release check"

R="$TMP/scan"; fx_repo "$R" 2.3.4 2.3.4
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
# project), in the shapes the writers write: frontmatter `release:` and `fix-policy:`, `deferred:` lines under
# `## SDLC State` with the ` stated="…"` field `finding-stated` appends (a `"` written `\"`, a `\` written `\\`).
# Three deferrals: #1 and #2 stated and deferred by the policy, #4 stated but rated fix (S2 on under S1,S2-on), so
# only #1 and #2 are held. #3, deferred and unstated, is kept apart (LIM_UNSTATED, LIM_DASH): a deferral rated
# defer with no sentence refuses the release, so it joins a plan only where that refusal is the thing proved.
# SYNTHESIZED: the sentences, the versions, the records.
LIM_A='The first limit says "quoted" words and a back\slash.'
LIM_B='The second limit is long enough that a changelog wraps it across two lines.'
lim_plan() {  # <repo> <release> [<deferred lines>] -> the run's plan under the repository's docs root
  local d="$1/.bionic/docs/plans/epic-01"
  mkdir -p "$d"
  { printf -- '---\nfix-policy: S1,S2-on\nrelease: %s\n---\n\n# fixture run\n\n## SDLC State\n\ncurrent: 7\n' "$2"
    printf '%s\n' "${3-}"
    printf '\n## Tasks\n'; } > "$d/wave-01.plan.md"
}
LIM_DEFERRED='deferred: record/w/critic.md#1 S3 on "a first title" stated="The first limit says \"quoted\" words and a back\\slash."
deferred: record/w/critic.md#2 S3 on "a second title" stated="The second limit is long enough that a changelog wraps it across two lines."
deferred: record/w/critic.md#4 S2 on "fixed instead" stated="A sentence the policy fixes is no limit."'
LIM_UNSTATED='deferred: record/w/critic.md#3 S3 on "an unstated one"'
LIM_DASH='deferred: record/w/critic.md#3 S3 on "an unstated one" stated="-"'
LIM_FIXED='deferred: record/w/critic.md#4 S2 on "fixed instead" stated="A sentence the policy fixes is no limit."'
lim_changelog() {  # <repo> <Known limits body of 2.3.4> [<older entry body>] -> commit a CHANGELOG whose newest entry is 2.3.4
  { printf '# Changelog\n\n## 2.3.4 — 2026-01-02\n\n- a change\n\n### Known limits\n\n%s\n\n' "$2"
    printf '## 0.0.1 — 2026-01-01\n\n- first\n%s\n' "${3-}"; } > "$1/CHANGELOG.md"
  git -C "$1" add CHANGELOG.md && git -C "$1" commit -q -m "the changelog"
}
LIM_BOTH="- Known limit: $LIM_A
- Known limit: The second limit is long enough that a changelog
  wraps it across two lines."

R="$TMP/lim-ok"; fx_repo "$R" 2.3.4 2.3.4; lim_plan "$R" 2.3.4 "$LIM_DEFERRED"; lim_changelog "$R" "$LIM_BOTH"
expect_false "(l0) setup: the plan is not committed (it is read from the docs root, as a real project's is)" git -C "$R" cat-file -e "HEAD:.bionic/docs/plans/epic-01/wave-01.plan.md"
run_check "$R"
expect_status "(l1) every stated deferral under the newest entry's Known limits, one of them wrapped: the check passes" 0 "$RC"
expect_eq "(l1) …and no release-check line" "0" "$(lines_of "$OUT")"

R="$TMP/lim-omit"; fx_repo "$R" 2.3.4 2.3.4; lim_plan "$R" 2.3.4 "$LIM_DEFERRED"; lim_changelog "$R" "- Known limit: $LIM_A"
run_check "$R"
expect_status "(l2) §LIMITS AC-11.4 Known limits omitting one stated sentence: the check fails" 1 "$RC"
expect_eq "(l2) …in one line" "1" "$(lines_of "$OUT")"

R="$TMP/lim-elsewhere"; fx_repo "$R" 2.3.4 2.3.4; lim_plan "$R" 2.3.4 "$LIM_DEFERRED"
{ printf '# Changelog\n\n## 2.3.4 — 2026-01-02\n\n- a change: %s\n\n### Known limits\n\n- Known limit: %s\n\n' "$LIM_B" "$LIM_A"
  printf '## 0.0.1 — 2026-01-01\n\n- first\n'; } > "$R/CHANGELOG.md"; git -C "$R" commit -q -am "the sentence outside Known limits"
run_check "$R"
expect_status "(l3) the sentence in the entry but outside its Known limits: the check fails" 1 "$RC"
expect_contains "(l3) …naming it" "omit the deferred sentence of record/w/critic.md#2" "$OUT"

R="$TMP/lim-older"; fx_repo "$R" 2.3.4 2.3.4; lim_plan "$R" 2.3.4 "$LIM_DEFERRED"
lim_changelog "$R" "- Known limit: $LIM_A" "
### Known limits

- Known limit: $LIM_B"
run_check "$R"
expect_status "(l4) the sentence only under an older entry's Known limits: the check fails" 1 "$RC"
expect_contains "(l4) …naming it" "omit the deferred sentence of record/w/critic.md#2" "$OUT"

R="$TMP/lim-none"; fx_repo "$R" 2.3.4 2.3.4
lim_plan "$R" 2.3.4 "$LIM_FIXED"; lim_changelog "$R" "- Known limit: none of note."
run_check "$R"
expect_status "(l5) a plan with no deferral rated defer: the check passes" 0 "$RC"
expect_contains "(l5) …in one line saying so" "known-limits: 2.3.4 — $(cd "$R" && pwd -P)/.bionic/docs/plans/epic-01/wave-01.plan.md states no deferred sentence" "$OUT"
expect_eq "(l5) …one such line" "1" "$(printf '%s\n' "$OUT" | /usr/bin/grep -c '^known-limits:')"

R="$TMP/lim-noplan"; fx_repo "$R" 2.3.4 2.3.4; lim_plan "$R" 2.3.3 "$LIM_DEFERRED"; lim_changelog "$R" "- Known limit: none of note."
run_check "$R"
expect_status "(l6) no plan names the release (the plan names 2.3.3): the check passes" 0 "$RC"
lim_plan "$R" 2.3.4 "$LIM_DEFERRED"
run_check "$R"
expect_status "(l6) …positive, the same repository once the plan names 2.3.4: the omissions fail it" 1 "$RC"
expect_eq "(l6) …one line for each of the two sentences" "2" "$(lines_of "$OUT")"

section "§LIMITS-2 — a deferral rated defer with no stated sentence, or a dash for one, refuses the release"

# The same fixture world as §LIMITS: one deferral, #3, rated defer by the policy. Unstated it is no limit anyone
# can carry, so the check names it and refuses; stated and carried it passes. The mutant is a copy of the check
# beside the real name scan, the real payload and the real hooks, with the arm's `if` made `if false`.
L2_LINE() { printf 'release-check: 2.3.4 defers record/w/critic.md#3 with no stated sentence; state it or fix it'; }
R="$TMP/l2-bare"; fx_repo "$R" 2.3.4 2.3.4; lim_plan "$R" 2.3.4 "$LIM_UNSTATED"; lim_changelog "$R" "- Known limit: none of note."
run_check "$R"
expect_status "(L2-1) §LIMITS-2 a deferral rated defer with no sentence: the check fails" 1 "$RC"
expect_contains "(L2-1) …one line naming the finding" "$(L2_LINE)" "$OUT"
expect_eq "(L2-1) …and it is the only release-check line" "1" "$(lines_of "$OUT")"
expect_eq "(L2-1) …no known-limits: line says the plan holds none" "0" "$(printf '%s\n' "$OUT" | /usr/bin/grep -c '^known-limits:')"

R="$TMP/l2-dash"; fx_repo "$R" 2.3.4 2.3.4; lim_plan "$R" 2.3.4 "$LIM_DASH"; lim_changelog "$R" "- Known limit: none of note."
run_check "$R"
expect_status "(L2-2) a dash for the sentence: the check fails" 1 "$RC"
expect_contains "(L2-2) …the same line, naming the finding" "$(L2_LINE)" "$OUT"
expect_eq "(L2-2) …and it is the only release-check line" "1" "$(lines_of "$OUT")"

R="$TMP/l2-stated"; fx_repo "$R" 2.3.4 2.3.4
lim_plan "$R" 2.3.4 'deferred: record/w/critic.md#3 S3 on "an unstated one" stated="The third limit is stated and carried."'
lim_changelog "$R" "- Known limit: The third limit is stated and carried."
run_check "$R"
expect_status "(L2-3) the same deferral with its sentence stated and carried in Known limits: the check passes" 0 "$RC"
expect_contains "(L2-3) …and the known-limits: line says one sentence carried" "known-limits: 2.3.4 carries the 1 deferred sentences of $(cd "$R" && pwd -P)/.bionic/docs/plans/epic-01/wave-01.plan.md" "$OUT"
expect_eq "(L2-3) …no release-check line" "0" "$(lines_of "$OUT")"

# A stated deferral beside an unstated one: the unstated one alone is named, and the stated one is still held to Known limits.
R="$TMP/l2-both"; fx_repo "$R" 2.3.4 2.3.4; lim_plan "$R" 2.3.4 "$LIM_UNSTATED
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
expect_contains "(L2-4) MUTANT …and it ran: the sentence is carried" "known-limits: 2.3.4 carries the 1 deferred sentences" "$OUT"
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

# FIXTURE FIDELITY: the run's plan names 2.3.4, and its landing record holds, in the line's event shapes, a queue
# landing at L1 and a hand landing at L2. The entry is rendered at L2 for 01:30 and committed as E, which a hand
# landing carries at 02:00; a third row lands L3 on top at 03:00. The poker runs from the fixture as a user runs it.
# SYNTHESIZED: the events.
POKER="${BIONIC_SCRIPTS_DIR}/hooks/session-poker.sh"; RN_PLAN=".bionic/docs/plans/epic-01/wave-01.plan.md"
rn_pub() { printf 'line/v1|ev=published|row=%s|commit=%s|kind=%s|by=t|why=w|at=%s\n' "$@" >> "$RN_REC"; }
rn_commit() {  # <file> -> commit a change to it, print the head
  printf '%s\n' "$1" > "$R/$1"; git -C "$R" add -- "$1"; git -C "$R" commit -q -m "$1"; git -C "$R" rev-parse HEAD
}
rn_entry() {  # <release-note output> -> commit a CHANGELOG whose 2.3.4 entry carries it, print the head
  { printf '# Changelog\n\n## 2.3.4 — 2026-01-02\n\n- a change\n\n%s\n## 0.0.1 — 2026-01-01\n\n- first\n' "${1%rc=0}"
  } > "$R/CHANGELOG.md"; git -C "$R" commit -q -am "the entry" >/dev/null; git -C "$R" rev-parse HEAD
}
rn_note() { (cd "$R" && bash "$POKER" release-note "$@" "$RN_PLAN" 2>&1; echo "rc=$?"); }
rn_check() { OUT="$(cd "$R" && env -u BIONIC_CHECK_BASE BIONIC_CHECK_HEAD="$1" bash "$CHECK" "$LIST" 2>&1)"; RC=$?; }
R="$TMP/rn"; fx_repo "$R" 2.3.4 2.3.4; lim_plan "$R" 2.3.4
RN_REC="$R/.bionic/docs/record/wave-01/landing-proofs.log"; mkdir -p "${RN_REC%/*}"
L1="$(rn_commit l1)"; L2="$(rn_commit l2)"
{ printf 'line/v1|ev=ready|row=T1|commit=%s|at=2026-01-02T00:00:00Z\n' "$L1"
  printf 'line/v1|ev=verdict|row=T1|commit=%s|suite=a.test.sh|result=green|log=-|admitted=1767312060|width=2|promised=60|actual=90|at=2026-01-02T00:05:00Z\n' "$L1"
} > "$RN_REC"; rn_pub T1 "$L1" queue 2026-01-02T00:10:00Z; rn_pub T2 "$L2" hand 2026-01-02T01:00:00Z
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
expect_contains "(f5) …and the rest still agrees" "landing-numbers: 2.3.4 agrees" "$OUT"

section "§LAST — the entry is written after the last landing it describes"

rn_check HEAD
expect_status "(t1) §LAST T3 landed after the entry's head, no rewrite: the check fails" 1 "$RC"
expect_eq "(t1) …in one line" "1" "$(lines_of "$OUT")"
rn_check "$(rn_entry "$(rn_note --on 2026-01-02T03:30:00Z)")"
expect_status "(t2) the entry rendered again at the new head: the check passes" 0 "$RC"
# A real CHANGELOG runs past a pipe's buffer, so the carrier is read whole after its match; here the carrier is a merge.
RNL="$(rn_note --on 2026-01-02T04:30:00Z)"; git -C "$R" checkout -q -b carry
{ printf '# Changelog\n\n## 2.3.4 — 2026-01-02\n\n- a change\n\n%s\n## 0.0.1 — 2026-01-01\n\n' "${RNL%rc=0}"
  awk 'BEGIN { for (i = 0; i < 20000; i++) print "- an older line" }'; } > "$R/CHANGELOG.md"
git -C "$R" commit -q -am "the long entry"; git -C "$R" checkout -q -; git -C "$R" merge -q --no-ff -m "land" carry
M="$(git -C "$R" rev-parse HEAD)"; rn_pub T7 "$M" hand 2026-01-02T05:00:00Z
expect_eq "(t3) setup: the carrier is a merge of two parents" "2" "$(git -C "$R" rev-list --parents -n 1 "$M" | wc -w | awk '{ print $1 - 1 }')"
rn_check "$M"
expect_contains "(t3) §LAST the merge that carried a long entry is the newest landing: the check agrees" "landing-numbers: 2.3.4 agrees" "$OUT"


section "§PROJECT — the check run from a tree with no plan reads the project's plan and record from BIONIC_CHECK_PROJECT"

# FIXTURE FIDELITY: the judge runs in a landing tree, a detached worktree of the project with no `.bionic` beside it,
# so the plan and the landing record are only where the project keeps them. Two projects: §LIMITS's world with one
# unstated deferral of 2.3.4, and §LAST's world at the merge whose numbers agree. Each is judged from a tree of its
# own, once with BIONIC_CHECK_PROJECT naming the project and once without it. SYNTHESIZED: as §LIMITS and §LAST.
pj_tree() {  # <repo> <rev> -> a detached worktree of <repo> at <rev>, under its own ignored tmp, with no .bionic
  local t="$1/.bionic/tmp/landing/1"
  git -C "$1" worktree add -q --detach "$t" "$2" >/dev/null 2>&1 && printf '%s' "$(cd "$t" && pwd -P)"
}
pj_check() {  # <tree> <head> [<project>] -> OUT, RC: the check run in <tree>, the project named only when given
  OUT="$(cd "$1" && env -u BIONIC_CHECK_BASE -u BIONIC_CHECK_PROJECT BIONIC_CHECK_HEAD="$2" \
    ${3:+BIONIC_CHECK_PROJECT="$3"} bash "$CHECK" "$LIST" 2>&1)"; RC=$?
}
R="$TMP/pj-lim"; fx_repo "$R" 2.3.4 2.3.4; lim_plan "$R" 2.3.4 "$LIM_UNSTATED"; lim_changelog "$R" "- Known limit: none of note."
PJ_T="$(pj_tree "$R" HEAD)"
expect_eq "(pj0) setup: the tree is the project's head, and holds no plan" "$(git -C "$R" rev-parse HEAD) no" \
  "$(git -C "${PJ_T:-/nonexistent}" rev-parse HEAD 2>/dev/null) $([ -e "${PJ_T:-/nonexistent}/.bionic" ] && echo yes || echo no)"
pj_check "$PJ_T" HEAD "$(cd "$R" && pwd -P)"
expect_status "(pj1) §PROJECT AC-2.2 with BIONIC_CHECK_PROJECT naming the project, an unstated deferral refuses from the tree" 1 "$RC"
expect_contains "(pj1b) …naming the deferral of the project's plan" "$(L2_LINE)" "$OUT"
pj_check "$PJ_T" HEAD
expect_status "(pj2) CONTROL with the variable unset, the same tree passes" 0 "$RC"
expect_contains "(pj2b) CONTROL …saying no plan under the tree's own docs names the release" \
  "known-limits: 2.3.4 — no plan under $PJ_T/.bionic/docs names release: 2.3.4" "$OUT"

# §LAST's world: its numbers agree at the merge M, the plan and the record read from the project.
R="$TMP/rn"; PJ_T="$(pj_tree "$R" "$M")"
pj_check "$PJ_T" "$M" "$(cd "$R" && pwd -P)"
expect_status "(pj3) the landing numbers judged from a tree, the project named: the check passes" 0 "$RC"
expect_contains "(pj3b) …its numbers rendered from the project's plan and record, and agreeing" \
  "landing-numbers: 2.3.4 agrees with the landing report at" "$OUT"
pj_check "$PJ_T" "$M"
expect_contains "(pj4) CONTROL the variable unset: no plan holds the numbers" \
  "landing-numbers: 2.3.4 — no plan under $PJ_T/.bionic/docs names release: 2.3.4" "$OUT"

section "§RATIO — tests may not outgrow the code: shell lines under tests/ against shell lines elsewhere, at the head"

# fx_ratio <dir> <tests lines> <code lines> — a committed pair whose tracked shell files hold exactly that many lines.
fx_lines() { awk -v n="$1" 'BEGIN { for (i = 0; i < n; i++) print ":" }'; }
fx_ratio() {
  fx_repo "$1" 2.3.4 2.3.4 || return 1
  mkdir -p "$1/tests" &&
  fx_lines "$2" > "$1/tests/big.test.sh" && fx_lines "$3" > "$1/code.sh" &&
  git -C "$1" add -A && git -C "$1" commit -q -m "the shell files"
}

R="$TMP/ratio-over"; fx_ratio "$R" 50 10
run_check "$R"
expect_status "(R-1) a head whose tests/ shell lines exceed the rest: the check fails" 1 "$RC"
expect_contains "(R-1) …and the line names both counts" "test-ratio 50/10" "$OUT"
expect_contains "(R-1) …and says tests exceed code at the head" "tests exceed code at HEAD" "$OUT"
expect_eq "(R-1) …in one line" "1" "$(lines_of "$OUT")"

R="$TMP/ratio-under"; fx_ratio "$R" 10 50
run_check "$R"
expect_status "(R-2) a head under: the check passes" 0 "$RC"
expect_contains "(R-2) …and prints the ratio" "test-ratio: 10/50" "$OUT"
expect_absent "(R-2) …with no refusal beside it" "tests exceed code" "$OUT"
R="$TMP/ratio-equal"; fx_ratio "$R" 40 40
run_check "$R"
expect_status "(R-2b) tests equal to code is not over: the check passes" 0 "$RC"
expect_contains "(R-2b) …printing the ratio" "test-ratio: 40/40" "$OUT"

# (R-3) the head's counts, never the working files': the committed head is under, the working files are far over.
R="$TMP/ratio-head"; fx_ratio "$R" 10 50
fx_lines 900 > "$R/tests/untracked.test.sh"; fx_lines 1 > "$R/code.sh"
expect_nonempty "(R-3) setup: the repository really is dirty" "$(git -C "$R" status --porcelain)"
run_check "$R"
expect_status "(R-3) working files edited and added after the commit: the check still passes" 0 "$RC"
expect_contains "(R-3) …on the head's counts" "test-ratio: 10/50" "$OUT"
git -C "$R" add -A; git -C "$R" commit -q -m "now over"
run_check "$R"
expect_status "(R-3) setup: the same files committed are over, so the dirty pass above was the head" 1 "$RC"
OUT="$(cd "$R" && env -u BIONIC_CHECK_BASE BIONIC_CHECK_HEAD='HEAD~1' bash "$CHECK" "$LIST" 2>&1)"; RC=$?
expect_contains "(R-3) …and BIONIC_CHECK_HEAD=HEAD~1 reads the earlier commit's counts" "test-ratio: 10/50" "$OUT"

# (R-4) a symlinked directory counts once: the blob the link names, never the files seen through it.
R="$TMP/ratio-link"; fx_repo "$R" 2.3.4 2.3.4
mkdir -p "$R/lib" "$R/tests" && fx_lines 20 > "$R/lib/x.sh" && fx_lines 5 > "$R/tests/t.test.sh"
ln -s lib "$R/lib2" && ln -s lib/x.sh "$R/alias.sh" && ln -s ../lib "$R/tests/viaLink"
git -C "$R" rm -q -f code.sh && git -C "$R" add -A && git -C "$R" commit -q -m "links"
expect_eq "(R-4) setup: the links are committed as links" "3" "$(git -C "$R" ls-tree -r HEAD | awk '$1 == "120000"' | wc -l | tr -d ' ')"
run_check "$R"
expect_status "(R-4) the check passes" 0 "$RC"
expect_contains "(R-4) …the code is the 20 lines of the real file, counted once, and the tests are their own 5" "test-ratio: 5/20" "$OUT"

# (R-5) no shell outside tests/ is no code to count against: a refusal, never a pass.
R="$TMP/ratio-nocode"; fx_repo "$R" 2.3.4 2.3.4
git -C "$R" rm -q -f code.sh; mkdir -p "$R/tests"; fx_lines 3 > "$R/tests/t.test.sh"; git -C "$R" add -A; git -C "$R" commit -q -m "tests only"
run_check "$R"
expect_status "(R-5) a head with no shell outside tests/: the check refuses (exit 2)" 2 "$RC"
expect_contains "(R-5) …in a line that says so" "no shell file outside tests/" "$OUT"
expect_eq "(R-5) …one line" "1" "$(lines_of "$OUT")"

section "§RATIO-BASE — a head over the cap is admitted when its test lines are at or under the base's, refused when they rose"

# run_check_base <repo> <base> — the check at HEAD with BIONIC_CHECK_BASE=<base>, the range the release runner passes; sets OUT and RC
run_check_base() {
  OUT="$(cd "$1" && env -u BIONIC_CHECK_HEAD BIONIC_CHECK_BASE="$2" bash "$CHECK" "$LIST" 2>&1)"; RC=$?
}
# fx_retest <dir> <tests lines> — the tests file rewritten to that many lines and committed
fx_retest() {
  fx_lines "$2" > "$1/tests/big.test.sh" && git -C "$1" add -A && git -C "$1" commit -q -m "tests at $2 lines"
}

# (RB-1) over the cap at the base, one test line cut: the landing is admitted and the line carries both sides.
R="$TMP/ratiob-cut"; fx_ratio "$R" 50 10; RB_BASE="$(git -C "$R" rev-parse HEAD)"
fx_retest "$R" 49
run_check_base "$R" "$RB_BASE"
expect_status "(RB-1) over the cap at the base, one test line cut: the check passes" 0 "$RC"
expect_contains "(RB-1) …and prints the head's ratio beside the base's" "test-ratio: 49/10 (base 50/10)" "$OUT"
expect_absent "(RB-1) …with no refusal beside it" "tests exceed code" "$OUT"

# (RB-2) over the cap at the base, one test line added: refused, in one line that names both sides.
R="$TMP/ratiob-rise"; fx_ratio "$R" 50 10; RB_BASE="$(git -C "$R" rev-parse HEAD)"
fx_retest "$R" 51
run_check_base "$R" "$RB_BASE"
expect_status "(RB-2) over the cap at the base, one test line added: the check fails" 1 "$RC"
expect_contains "(RB-2) …the line names both counts and says tests exceed code at the head" "test-ratio 51/10 — tests exceed code at HEAD" "$OUT"
expect_contains "(RB-2) …and the base's counts it rose from" "(base 50/10)" "$OUT"
expect_eq "(RB-2) …in one line" "1" "$(lines_of "$OUT")"

# (RB-3) the same test lines as the base is not a rise.
R="$TMP/ratiob-same"; fx_ratio "$R" 50 10; RB_BASE="$(git -C "$R" rev-parse HEAD)"
printf ':\n' >> "$R/code.sh"; git -C "$R" add -A; git -C "$R" commit -q -m "one code line more"
run_check_base "$R" "$RB_BASE"
expect_status "(RB-3) over the cap at the base, test lines unchanged: the check passes" 0 "$RC"
expect_contains "(RB-3) …printing both ratios" "test-ratio: 50/11 (base 50/10)" "$OUT"

# (RB-4) the control: under the cap at the head, lines added, the base beside the ratio and no refusal.
R="$TMP/ratiob-under"; fx_ratio "$R" 10 50; RB_BASE="$(git -C "$R" rev-parse HEAD)"
fx_retest "$R" 20
run_check_base "$R" "$RB_BASE"
expect_status "(RB-4) under the cap at the head, test lines added: the check passes" 0 "$RC"
expect_contains "(RB-4) …printing both ratios" "test-ratio: 20/50 (base 10/50)" "$OUT"

# (RB-5) a base the repository cannot read compares nothing: the head alone is judged, as with no base.
R="$TMP/ratiob-nobase"; fx_ratio "$R" 50 10
run_check_base "$R" "0000000000000000000000000000000000000000"
expect_status "(RB-5) a base that names no commit, a head over the cap: the check fails" 1 "$RC"
expect_contains "(RB-5) …on the head's counts" "test-ratio 50/10 — tests exceed code at HEAD" "$OUT"
expect_absent "(RB-5) …with no base counts invented" "(base" "$OUT"

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

PLAN_36="${BIONIC_SCRIPTS_DIR}/.bionic/docs/plans/epic-23-bionic-tech-debt/wave-36-zero-machine-errors.plan.md"
PLUGIN_JSON="${BIONIC_SCRIPTS_DIR}/payload/.claude-plugin/plugin.json"
# Every landed build row of the run and the record that proves it; the entry names each record
ROWS_1190="T1:T1-run-on-branch.md T2:T2-restart-truth.md T3:T3-placement.md T4:T4-jurisdiction.md
T5:T5-reads-index.md T6:T6-pinned-text.md T7:T7-cover-judge.md T8:T8-fixed-move.md T9:T9-run-sessions.md
T10:T10-closure-and-markers.md T11:T11-gate-lifecycle.md T12:T12-branch-reads.md T13:T13-debt-grammar.md
T14:T14-close-out-state.md T15:T15-doctrine.md T24:T24-block-heading.md T25:T25-callers.md
T27:T27-consumers.md T28:T28-verbs-ask-the-judge.md T29:T29-launch-arm-and-adopt.md
T30:T30-start-hook-bash5.md T31:T31-fix-seen-by-asker.md T32:T32-one-width-fact.md T33:T33-said-no-pipe.md
T34:T34-taking-lock-stale.md T35:T35-floor-is-a-fact.md T36:T36-stop-wall-pins.md T37:T37-shell-lint-reds.md
T38:T38-one-roster-reader.md T39:T39-sp2-pins.md T40:T40-tick-asks-once.md T41:T41-task-set-files.md
T42:T42-born-floor-backed.md T43:T43-two-cd-chain.md T44:T44-walk-pointer.md T47:T47-adopt-lands-on-whole.md"
# The rows that added a refusal; the Migration paragraph names each (AC-9.2)
MIG_ROWS="T4 T7 T8 T13 T14 T25 T27 T31 T32 T35 T42"
# D22's two deferred sentences, as wave-35's continuation states them and 1.18.0's Known limits omitted them
D22_A='`task-add --born` still admits a finding the person moved to defer when its reader'"'"'s rating is inside the fix policy; the guard reads a move to fix, not a move to defer.'
D22_B='a dead session'"'"'s open row whose files are already sweepable still holds its plan row, and the refusal'"'"'s remedy (`adopt`) lists nothing for that session; `session-poker.sh sweep` clears it.'
# The text-only floor arm's sentence (A-orch-50)
TEXT_ONLY='from Step 7 the commit wall refuses a plan that claims a regression and carries no `proved: kind=floor` line, and it reads text only, so a floor line that owes suites passes it and the judge holds them at `current 7` and `current 8`.'

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
# plan_deferred — the stated sentence of each `deferred:` line of the bound plan, one per line
plan_deferred() { sed -n 's/^deferred: .* stated="\(.*\)"[[:space:]]*$/\1/p' "$1"; }
# plan_deferred_open <plan> — the stated sentences of the deferrals no `moved: <id> to=fixed` line has closed, the ones the
# check holds the entry to; a plan whose later rows fixed a deferred finding states more sentences than the entry owes
plan_deferred_open() {
  awk 'FNR == NR { if ($1 == "moved:" && $3 == "to=fixed") fixed[$2] = 1; next }
       $1 == "deferred:" && !($2 in fixed) { print }' "$1" "$1" | sed -n 's/^deferred: .* stated="\(.*\)"[[:space:]]*$/\1/p'
}

# corr_check <file> <plugin.json> <plan> — one `corr:` line per broken rule; no output when all hold
corr_check() {
  local f="$1" pj="$2" plan="$3" blk cor lim mig lead s n pair row rec cnt stated actual t13 t13hit
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
  if [ -r "$plan" ]; then
    cnt=0
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      cnt=$((cnt + 1))
      has "$lim" "$s" || echo "corr: Known limits lacks the deferred sentence: $s"
    done <<EOT
$(plan_deferred "$plan")
EOT
    [ "$cnt" -gt 0 ] || echo "corr: the plan holds no deferred sentence to pin"
  fi
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
# pair_check <file> <plugin.json> — one `corr:` line when plugin.json does not read the newest heading (the live pair,
# whichever release is newest; the 1.19.0 rules above hold that block at its own heading)
pair_check() {
  local ver pv
  ver="$(grep -m 1 '^## ' "$1" | sed -n 's/^## \([0-9.]*\) .*/\1/p')"
  pv="$(jq -r '.version // empty' "$2" 2>/dev/null)"
  [ -n "$ver" ] && [ "$pv" = "$ver" ] || echo "corr: plugin.json reads ${pv:-nothing}, not the newest heading ${ver:-none}"
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
cor_check() { corr_check "$1" "$PLUGIN_JSON" ""; }
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
if [ -r "$PLAN_36" ]; then
  FIRST_DEFERRED="$(plan_deferred "$PLAN_36" | head -n 1)"
fi
doctor c_klcount sed 's/The count of Known limits in this block is [0-9]*\./The count of Known limits in this block is 99./'
expect_contains "(c2l) a stated count that is not the bullets counted: red" "corr: the count says 99" "$(cor_check "$TMP/doctored.c_klcount")"
doctor c_klnone sed 's/The count of Known limits in this block is/The Known limits here number/'
doctor c_mig awk '/^\*\*Migration\.\*\*/ { m = 1 } m && /^### / { m = 0 } m { gsub(/T35/, "Tnn") } { print }'
expect_contains "(c2n) a Migration paragraph that does not name T35: red" "corr: Migration does not name T35" "$(cor_check "$TMP/doctored.c_mig")"
doctor c_t13 sed 's/`debt adopt` and the Step-1 card now refuse/the card now refuses/'
doctor c_rec sed 's/`T27-consumers\.md`/the record/g'
doctor c_born sed 's/T33, T36, T37, T38, T39 and T40/the six rows/'
doctor c_edit1180 awk '{ print } /^## 1\.18\.0 — /{ print "" }'
printf '{\n  "name": "bionic",\n  "version": "1.18.0"\n}\n' > "$TMP/plugin.old.json"
doctor c_nodate sed 's/^## 1\.19\.0 — .*/## 1.19.0 —/'

# rel_check <file> <plugin.json> <version> <adr> <rows> — one `rel:` line per broken rule; no output when all hold
rel_check() {
  local f="$1" pj="$2" ver="$3" adr="$4" rows="$5" blk mig s vre
  vre="${ver//./\\.}"
  blk="$(cl_block "$f" "$ver")"
  [ -n "$blk" ] || { echo "rel: no $ver block"; return 0; }
  grep -q -E "^## $vre — 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]\$" <<<"$blk" || echo "rel: the $ver heading carries no date"
  mig="$(cl_lead "$f" "$ver" | awk '/^\*\*Migration\.\*\*/ { m = 1 } m')"
  [ -n "$mig" ] || echo "rel: no Migration paragraph"
  for s in $rows; do
    grep -q -w -- "$s" <<<"$mig" || echo "rel: Migration does not name $s"
  done
  has "$blk" "$adr" || echo "rel: the entry does not name $adr"
  [ "$(jq -r '.version // empty' "$pj" 2>/dev/null)" = "$ver" ] || echo "rel: plugin.json does not read $ver"
}
# rel_world <dir> <changelog> <version> <plan> [<extra deferred line>] — a committed repository holding <changelog> as its
# CHANGELOG and the run's real deferred lines as its plan, each with the moved: lines that later changed its state, so the
# declared check judges the entry as the door will
rel_world() {
  fx_repo "$1" 2.3.4 "$3" && lim_plan "$1" "$3" "$(/usr/bin/grep -E '^(deferred|moved): ' "$4")${5:+
$5}" &&
  { cat "$2"; printf '\n## 0.0.1 — 2026-01-01\n\n- first\n'; } > "$1/CHANGELOG.md" &&
  git -C "$1" add CHANGELOG.md && git -C "$1" commit -q -m "the $3 entry"
}

section "§REL-1.27.0 — the 1.27.0 entry names its rows and carries the run's deferred sentences"

REL_PLAN="${BIONIC_SCRIPTS_DIR}/.bionic/docs/plans/epic-23-bionic-tech-debt/wave-44-every-hand.plan.md"
# The rows whose Migration bullets name what a script of yours may meet at 1.27.0
REL_MIG_ROWS="T1 T2 T3 T4 T5 T13 T14"

printf '{\n  "name": "bionic",\n  "version": "1.27.0"\n}\n' > "$TMP/plugin.1270.json"
expect_eq "(n2) the entry keeps every rule" "" "$(rel_check "$CL" "$TMP/plugin.1270.json" 1.27.0 ADR-071 "$REL_MIG_ROWS")"
doctor r27_nomig awk '/^\*\*Migration\.\*\*/ { m = 1 } m && /^### / { m = 0 } m { gsub(/T14/, "Tnn") } { print }'
expect_contains "(n2) a Migration paragraph that does not name T14: red" "rel: Migration does not name T14" "$(rel_check "$TMP/doctored.r27_nomig" "$TMP/plugin.1270.json" 1.27.0 ADR-071 "$REL_MIG_ROWS")"
doctor r27_noadr sed 's/ADR-071/the fourth record/g'
expect_contains "(n2) an entry that does not name ADR-071: red" "rel: the entry does not name ADR-071" "$(rel_check "$TMP/doctored.r27_noadr" "$TMP/plugin.1270.json" 1.27.0 ADR-071 "$REL_MIG_ROWS")"
expect_contains "(n2) a manifest that reads another version: red" "rel: plugin.json does not read 1.27.0" "$(rel_check "$CL" "$TMP/plugin.old.json" 1.27.0 ADR-071 "$REL_MIG_ROWS")"

if [ -r "$REL_PLAN" ]; then
  REL_N="$(plan_deferred "$REL_PLAN" | /usr/bin/grep -c .)"
  # A plan that states no deferral holds the arms below at zero; one that gains a deferral turns them to the
  # strict form (the check fails without the Known limits, one line each) with no edit here.
  if [ "$REL_N" -gt 0 ]; then REL_WANT=1; else REL_WANT=0; fi
  expect_true "(n0) setup: the count of the run's deferred sentences is read" [ "$REL_N" -ge 0 ]
  cl_block "$CL" 1.27.0 | awk '/^### / { skip = ($0 == "### The landing numbers") } !skip' > "$TMP/rel.entry"
  cl_block "$CL" 1.27.0 | awk '/^### / { skip = ($0 == "### The landing numbers" || $0 == "### Known limits") } !skip' > "$TMP/rel.nolimits"
  expect_nonempty "(n0) setup: the entry's Known limits are cut out of a block that exists" "$(cat "$TMP/rel.nolimits")"
  R="$TMP/rel-real"; rel_world "$R" "$TMP/rel.entry" 1.27.0 "$REL_PLAN"
  run_check "$R"
  expect_status "(n3) the real entry, every deferred sentence of the run's plan under Known limits: the check passes" 0 "$RC"
  if [ "$REL_N" -gt 0 ]; then
    expect_contains "(n3) …carrying each deferred sentence" "known-limits: 1.27.0 carries the $REL_N deferred sentences" "$OUT"
  else
    expect_contains "(n3) …saying the plan states none" "known-limits: 1.27.0 — " "$OUT"
    expect_contains "(n3) …in those words" "states no deferred sentence" "$OUT"
  fi
  R="$TMP/rel-nolimits"; rel_world "$R" "$TMP/rel.nolimits" 1.27.0 "$REL_PLAN"
  run_check "$R"
  expect_status "(n4) the same entry with its Known limits removed: the check fails only when a sentence is deferred" "$REL_WANT" "$RC"
  if [ "$REL_N" -gt 0 ]; then
    expect_eq "(n4) …one line for each deferred sentence" "$REL_N" "$(lines_of "$OUT")"
    expect_contains "(n4) …naming a finding" "omit the deferred sentence of record/" "$OUT"
  else
    expect_contains "(n4) …the plan states none, so none is omitted" "states no deferred sentence" "$OUT"
  fi
  # One planted deferral keeps the omission arm live whatever this run states: the same entry, no Known limits.
  R="$TMP/rel-planted"; rel_world "$R" "$TMP/rel.nolimits" 1.27.0 "$REL_PLAN" 'deferred: record/w/planted.md#1 S3 on "a planted title" stated="The planted limit is stated and the entry omits it."'
  run_check "$R"
  expect_status "(n5) one deferred sentence planted in the run's plan, the entry without Known limits: the check fails" 1 "$RC"
  expect_contains "(n5) …naming the planted finding" "omit the deferred sentence of record/w/planted.md#1" "$OUT"
fi

section "§REL-1.28.0 — the 1.28.0 entry names its rows and its ADRs and carries the run's deferred sentences"

REL_PLAN="${BIONIC_SCRIPTS_DIR}/.bionic/docs/plans/epic-23-bionic-tech-debt/wave-45-whole-run.plan.md"
# The rows whose Migration bullets name what a script of yours may meet at 1.28.0
REL_MIG_ROWS="T1 T2 T3 T5 T6 T7 T8 T9 T10 T11 T12 T13 T14 T15 T16 T17 T18 T24 T25 T28 T31 T32 T33"
# The two ADRs this release records
REL_ADR_A="ADR-072"
REL_ADR_B="ADR-073"

expect_eq "(n1) the version pair reads the newest heading" "" "$(pair_check "$CL" "$PLUGIN_JSON")"
expect_eq "(n1) …the 1.28.0 block's own heading reads 1.28.0" "1.28.0" "$(cl_block "$CL" 1.28.0 | head -1 | sed -n 's/^## \([0-9.]*\) .*/\1/p')"
printf '{\n  "name": "bionic",\n  "version": "1.28.0"\n}\n' > "$TMP/plugin.1280.json"
expect_eq "(n2) the entry keeps every rule" "" "$(rel_check "$CL" "$TMP/plugin.1280.json" 1.28.0 "$REL_ADR_A" "$REL_MIG_ROWS")$(rel_check "$CL" "$TMP/plugin.1280.json" 1.28.0 "$REL_ADR_B" "$REL_MIG_ROWS")"
doctor r28_nomig awk '/^\*\*Migration\.\*\*/ { m = 1 } m && /^### / { m = 0 } m { gsub(/T33/, "Tnn") } { print }'
expect_contains "(n2) a Migration paragraph that does not name T33: red" "rel: Migration does not name T33" "$(rel_check "$TMP/doctored.r28_nomig" "$TMP/plugin.1280.json" 1.28.0 "$REL_ADR_A" "$REL_MIG_ROWS")"
doctor r28_noadr sed "s/$REL_ADR_A/the first record/g"
expect_contains "(n2) an entry that does not name $REL_ADR_A: red" "rel: the entry does not name $REL_ADR_A" "$(rel_check "$TMP/doctored.r28_noadr" "$TMP/plugin.1280.json" 1.28.0 "$REL_ADR_A" "$REL_MIG_ROWS")"
doctor r28_noadr2 sed "s/$REL_ADR_B/the second record/g"
expect_contains "(n2) an entry that does not name $REL_ADR_B: red" "rel: the entry does not name $REL_ADR_B" "$(rel_check "$TMP/doctored.r28_noadr2" "$TMP/plugin.1280.json" 1.28.0 "$REL_ADR_B" "$REL_MIG_ROWS")"
expect_contains "(n2) a manifest that reads another version: red" "rel: plugin.json does not read 1.28.0" "$(rel_check "$CL" "$TMP/plugin.1270.json" 1.28.0 "$REL_ADR_A" "$REL_MIG_ROWS")"

if [ -r "$REL_PLAN" ]; then
  REL_N="$(plan_deferred_open "$REL_PLAN" | /usr/bin/grep -c .)"
  # A plan that states no deferral holds the arms below at zero; one that gains a deferral turns them to the
  # strict form (the check fails without the Known limits, one line each) with no edit here.
  if [ "$REL_N" -gt 0 ]; then REL_WANT=1; else REL_WANT=0; fi
  expect_true "(n0) setup: the count of the run's deferred sentences is read" [ "$REL_N" -ge 0 ]
  cl_block "$CL" 1.28.0 | awk '/^### / { skip = ($0 == "### The landing numbers") } !skip' > "$TMP/rel28.entry"
  cl_block "$CL" 1.28.0 | awk '/^### / { skip = ($0 == "### The landing numbers" || $0 == "### Known limits") } !skip' > "$TMP/rel28.nolimits"
  expect_nonempty "(n0) setup: the entry's Known limits are cut out of a block that exists" "$(cat "$TMP/rel28.nolimits")"
  R="$TMP/rel28-real"; rel_world "$R" "$TMP/rel28.entry" 1.28.0 "$REL_PLAN"
  run_check "$R"
  expect_status "(n3) the real entry, every deferred sentence of the run's plan under Known limits: the check passes" 0 "$RC"
  if [ "$REL_N" -gt 0 ]; then
    expect_contains "(n3) …carrying each deferred sentence" "known-limits: 1.28.0 carries the $REL_N deferred sentences" "$OUT"
  else
    expect_contains "(n3) …saying the plan states none" "known-limits: 1.28.0 — " "$OUT"
    expect_contains "(n3) …in those words" "states no deferred sentence" "$OUT"
  fi
  R="$TMP/rel28-nolimits"; rel_world "$R" "$TMP/rel28.nolimits" 1.28.0 "$REL_PLAN"
  run_check "$R"
  expect_status "(n4) the same entry with its Known limits removed: the check fails only when a sentence is deferred" "$REL_WANT" "$RC"
  if [ "$REL_N" -gt 0 ]; then
    expect_eq "(n4) …one line for each deferred sentence" "$REL_N" "$(lines_of "$OUT")"
    expect_contains "(n4) …naming a finding" "omit the deferred sentence of record/" "$OUT"
  else
    expect_contains "(n4) …the plan states none, so none is omitted" "states no deferred sentence" "$OUT"
  fi
  # One planted deferral keeps the omission arm live whatever this run states: the same entry, no Known limits.
  R="$TMP/rel28-planted"; rel_world "$R" "$TMP/rel28.nolimits" 1.28.0 "$REL_PLAN" 'deferred: record/w/planted.md#1 S3 on "a planted title" stated="The planted limit is stated and the entry omits it."'
  run_check "$R"
  expect_status "(n5) one deferred sentence planted in the run's plan, the entry without Known limits: the check fails" 1 "$RC"
  expect_contains "(n5) …naming the planted finding" "omit the deferred sentence of record/w/planted.md#1" "$OUT"
fi

finish
