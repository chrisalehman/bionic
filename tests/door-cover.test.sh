#!/bin/bash
# Tests for the judge's cover of this repository's own release merges: each release the project shipped, read by the
# judge's reader (`facts_cover` in payload/scripts/lib/proof.sh) with a check passing at its merge, reads `release`.
#
#   §REAL    1.23.0, 1.22.0 and 1.21.0 by their merge commits: each merge is the one that brought in its version's
#            CHANGELOG heading, and `facts_cover <plan> <merge>^1 <merge>` prints `cover <merge> release`, rc 0. A
#            merge this repository does not hold (a shallow clone, a rewritten history) is skipped by its version
#            and hash, never faked; one row proves the skip names an absent hash.
#   §MUTANT  the release set with one arm taken out of a copy of proof.sh. Without the check suite's arm every
#            merge owes; without the promoted records' arm the 1.23.0 merge, which promoted four, owes and the
#            other two still read release.
#
# WHY THE REAL MERGES. A cover test over a commit built from the code's own list cannot fail on a path the list
# omits: the input and the code share the omission. The merges the release rows actually produced carry every path
# a release really touched, so a path the set drops turns a real merge's cover to `owes`.
#
# FIXTURE FIDELITY: live tier, read-only. The merges are this repository's own commits, read through a scratch
# repository under the world directory whose object store borrows this repository's (an alternates file); nothing
# is written here. SYNTHESIZED: the plan, a scratch file whose `## SDLC State` holds one passing check line per
# merge present, in the shape the release-check verb writes, its readers' green verdicts in the landing record as
# lib/line.sh writes them, and the one absent hash of the skip row.
#
# ANTI-VACUITY: each mutant row first proves the copy differs from proof.sh by exactly its one arm and that the copy
# still sources and runs; the mutant's own reading is an exact `cover <merge> owes` line, never an absence.
#
# Usage: bash tests/door-cover.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
[ -n "${WORLD_ROOT:-}" ] || . "$(dirname "$0")/lib/world.sh"

SKIPPED=0
skip() { SKIPPED=$((SKIPPED + 1)); echo "SKIP: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

DC_PROOF="$BIONIC_SCRIPTS_DIR/payload/scripts/lib/proof.sh"
# The release merges, pinned by the hashes the rewritten history gave them: version, then merge.
DC_MERGES="1.23.0 f75f8bbc7cd78a963f6b9f922bb2fd1af2933335
1.22.0 1c451183069a6c78a53d57135f36b7bb1a2b2d1e
1.21.0 7d5a0f719fbbf106226a41cf93c17f1d0355ee12"

setup_section "the reader: a scratch repository that borrows this one's objects, and a plan with a check at each merge"

DC_R="$WORLD_ROOT/cover"
# git prints the common directory relative to where it ran, so it is resolved from there.
DC_OBJ="$(cd "$BIONIC_SCRIPTS_DIR" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)/objects"
DC_HEAD="$(git -C "$BIONIC_SCRIPTS_DIR" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)"
git init -q "$DC_R" && printf '%s\n' "$DC_OBJ" > "$DC_R/.git/objects/info/alternates"
# dc_present <merge> -> 0 when the merge and its first parent are commits here: the reader walks <merge>^1..<merge>.
dc_present() { git -C "$DC_R" cat-file -e "$1^{commit}" 2>/dev/null && git -C "$DC_R" cat-file -e "$1^1^{commit}" 2>/dev/null; }
DC_PLAN="$DC_R/plan.md"
{ printf -- '---\ncurrent: 7\n---\n\n## SDLC State\n\n'
  while read -r v m; do
    dc_present "$m" && printf 'proved: kind=check head=%s at=2026-10-20T00:00:00Z evidence=check-%s.log\n' "$m" "$v"
  done <<EOF
$DC_MERGES
EOF
} > "$DC_PLAN"
# A release merge is release with its readers green at it: one green verdict per reader at each merge present.
while read -r v m; do dc_present "$m" || continue; bash -c '. "$1/line.sh" && . "$1/proof.sh" || exit 1; for s in $(_proof_release_readers); do line_event "$2" verdict row=T8 "commit=$3" "suite=$s" result=green log=- admitted=- width=-; done' _ "${DC_PROOF%/*}" "$DC_PLAN" "$m" </dev/null; done <<EOF
$DC_MERGES
EOF
echo "door-cover: reading $DC_OBJ through $DC_R; $(/usr/bin/grep -c '^proved: kind=check' "$DC_PLAN") of 3 merges present"

# dc_cover <proof.sh> <merge> -> the judge's cover of the merge alone, as the judge reads it, then `rc=<n>`.
dc_cover() {
  bash -c '. "$1" >/dev/null 2>&1 || exit 127; facts_cover "$2" "$3^1" "$3"; echo "rc=$?"' _ "$1" "$DC_PLAN" "$2"
}
# dc_real <label> <version> <merge> -> the release rows of one merge, or one SKIP naming the version and the hash.
dc_real() {
  if ! dc_present "$3"; then
    skip "$1 $2 merge ${3:0:12} reads release" "the merge $3 or its first parent is absent from this repository"
    return 0
  fi
  expect_eq "$1 $2 merge ${3:0:12} is the merge that brought in the $2 heading" "1" \
    "$(git -C "$DC_R" diff --no-renames "$3^1" "$3" -- CHANGELOG.md | /usr/bin/grep -c "^+## $2 — ")"
  expect_eq "$1 …and the judge's cover of it, a check passing at it, reads release (rc 0)" \
    "$(printf 'cover %s release\nrc=0' "$3")" "$(dc_cover "$DC_PROOF" "$3")"
}

# ---------------------------------------------------------------------------------------------------------------
section "§REAL: the judge reads each real release merge as release"

# A reader that cannot see this repository would skip every merge as absent; it is a failure, never a skip.
expect_eq "(r) the scratch reader holds this repository's own head, so an absent merge is absent from this history" \
  "commit" "$( [ -n "$DC_HEAD" ] && git -C "$DC_R" cat-file -t "$DC_HEAD" 2>/dev/null)"
DC_I=0
while read -r v m; do
  DC_I=$((DC_I + 1))
  dc_real "(r$DC_I)" "$v" "$m"
done <<EOF
$DC_MERGES
EOF
DC_ABSENT=0000000000000000000000000000000000000001
DC_SAID="$(dc_real "(r0)" 0.0.0 "$DC_ABSENT")"
expect_contains "(r0) a merge absent from this repository is skipped by its version and its hash" \
  "SKIP: (r0) 0.0.0 merge ${DC_ABSENT:0:12} reads release" "$DC_SAID"
expect_contains "(r0b) …the skip printing the whole hash" "the merge $DC_ABSENT or its first parent is absent" "$DC_SAID"

# ---------------------------------------------------------------------------------------------------------------
section "§MUTANT: a release set missing an arm the real merges need turns their cover to owes"

# dc_mutant <name> <sed> -> the path of a copy of proof.sh with the sed applied, beside the libraries it loads; nothing
# when the sed changed nothing.
dc_mutant() {
  local out="$WORLD_ROOT/lib-$1/proof.sh"
  cp -R "${DC_PROOF%/*}" "${out%/*}" && sed "$2" "$DC_PROOF" > "$out" && ! cmp -s "$DC_PROOF" "$out" && printf '%s' "$out"
}
# dc_changed <copy> -> the number of lines the copy adds against proof.sh: one for a one-arm mutant.
# diff exits 1 on a difference, which pipefail would hand on, so the count is the answer and the status is 0.
dc_changed() { diff "$DC_PROOF" "$1" | /usr/bin/grep -c '^>'; return 0; }
# dc_classes <copy> <path> -> `in` or `out`: the copy's release set, asked directly.
dc_classes() { bash -c '. "$1" >/dev/null 2>&1 || exit 127; _proof_release_path "$2" && echo in || echo out' _ "$1" "$2"; }

DC_NOCHECK="$(dc_mutant nocheck 's#|tests/release-check.test.sh) return 0#) return 0#')"
expect_eq "(m0) MUTANT precondition: the copy without the check suite's arm differs from proof.sh by one line" "1" \
  "$( [ -n "$DC_NOCHECK" ] && dc_changed "$DC_NOCHECK" || echo 0)"
expect_eq "(m0b) MUTANT …and it runs: CHANGELOG.md is in its set and tests/release-check.test.sh is not" "in out" \
  "$(dc_classes "$DC_NOCHECK" CHANGELOG.md) $(dc_classes "$DC_NOCHECK" tests/release-check.test.sh)"
DC_NOADR="$(dc_mutant noadr 's#payload/commands/?\*\.md|docs/adrs/?\*\.md) return 0#payload/commands/?*.md) return 0#')"
expect_eq "(m1) MUTANT precondition: the copy without the promoted records' arm differs from proof.sh by one line" "1" \
  "$( [ -n "$DC_NOADR" ] && dc_changed "$DC_NOADR" || echo 0)"
expect_eq "(m1b) MUTANT …and it runs: payload/commands/help.md is in its set and docs/adrs/adr-001-a.md is not" "in out" \
  "$(dc_classes "$DC_NOADR" payload/commands/help.md) $(dc_classes "$DC_NOADR" docs/adrs/adr-001-a.md)"

DC_I=0
while read -r v m; do
  DC_I=$((DC_I + 1))
  if ! dc_present "$m"; then
    skip "(m$((DC_I + 1))) $v merge ${m:0:12} under the two mutants" "the merge $m or its first parent is absent from this repository"
    continue
  fi
  expect_eq "(m$((DC_I + 1))) MUTANT without the check suite's arm, the $v merge owes (rc 1)" \
    "$(printf 'cover %s owes\nrc=1' "$m")" "$(dc_cover "$DC_NOCHECK" "$m")"
  if [ "$v" = 1.23.0 ]; then DC_WANT="cover $m owes"$'\n'"rc=1"; DC_SAYS="owes, it promoted four records"
  else DC_WANT="cover $m release"$'\n'"rc=0"; DC_SAYS="still reads release, it promoted none"
  fi
  expect_eq "(m$((DC_I + 1))b) MUTANT without the promoted records' arm, the $v merge $DC_SAYS" \
    "$DC_WANT" "$(dc_cover "$DC_NOADR" "$m")"
done <<EOF
$DC_MERGES
EOF

[ "$SKIPPED" -eq 0 ] || echo "door-cover: ${SKIPPED} row(s) skipped by name"
finish
