#!/bin/bash
# Tests for tests/reader-exam/ — the reader exam's pin (wave-27 T18; spec D11, AC-5.3, AC-4.4).
#
# THE EXAM ITSELF IS NOT RUN HERE. A sitting dispatches live readers (README.md in
# tests/reader-exam/), and no hermetic suite can. What this suite owns is the one thing a
# machine can hold the exam to: the checks files the readers were examined on are the ones
# that ship. Three sections:
#
#   §PIN      `exam_pin` on planted sittings: the latest sitting's three `sha256` lines equal
#             the files' digests, or the verdict is red and names the file. A checks file
#             edited after its sitting turns it red.
#   §OWED     until the first sitting, `sittings.md` carries the owed line; that line alone
#             passes, neither it nor a sitting is red, and both together are red.
#   §SAMPLES  every sample has its answer key in shape and materializes into a two-commit
#             repository that the key does not travel into.
#   §SHIPPED  the shipped `sittings.md` against the shipped checks files.
#
# FIXTURE FIDELITY (declared, per .claude/rules/test-harness.md, "Fixture fidelity"): §PIN and
# §OWED run the suite's own `exam_pin` — the same function §SHIPPED runs on the real files —
# over planted `sittings.md` files and a planted root holding three checks files of made-up
# text. SYNTHESIZED: the checks text and the hashes written into the planted sittings, which
# are taken by the same digest function the verdict uses, or deliberately wrong. §SAMPLES runs
# the real samples through the real materialize.sh into real git repositories.
#
# ANTI-VACUITY (declared, per the same file, "Anti-vacuity"): every red verdict sits beside a
# green one from the same function on a fixture one edit away; the digest function is proved
# to return a 64-hex digest on every shipped checks file before any comparison reads it.
#
# Usage: bash tests/reader-exam.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
EXAM="${REPO}/tests/reader-exam"
# The digest: the one sha256 reader the payload already carries (reuse, not a fourth copy).
. "${REPO}/payload/scripts/lib/detect.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/reader-exam-test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null

# The checks files, root-relative. Spelled out from the root, not built from the question
# names: tests/lib/impact.sh finds a suite's reach by the paths it names, and an edited checks
# file must reach this suite.
EXAM_CHECKS=""
for f in "${REPO}/payload/context/checks-evidence.md" "${REPO}/payload/context/checks-adversarial.md" \
         "${REPO}/payload/context/checks-structure.md"; do
  EXAM_CHECKS="${EXAM_CHECKS:+$EXAM_CHECKS }${f#"$REPO"/}"
done
EXAM_OWED_LINE="first-sitting: owed by wave-27 T22"

# exam_pin <sittings file> <root> — prints one verdict line, rc 0 only when the exam holds:
#   pinned                 the latest sitting names each checks file under <root> once, with
#                          its digest
#   owed                   no sitting and the owed line (RE-AUTHORED BY T22: this arm goes
#                          when the first sitting is recorded)
#   red <reason>           anything else
# A sitting is a section headed `## <YYYY-MM-DD>…`; the latest is the last in the file.
exam_pin() {
  local file="$1" root="$2" sittings owed latest f lines want have
  [ -r "$file" ] || { echo "red: $file cannot be read"; return 1; }
  sittings="$(grep -cE '^## [0-9]{4}-[0-9]{2}-[0-9]{2}' "$file")"
  owed="$(grep -cxF -- "$EXAM_OWED_LINE" "$file")"
  if [ "$sittings" -eq 0 ]; then
    [ "$owed" -gt 0 ] && { echo "owed"; return 0; }
    echo "red: no sitting is recorded and no line says the first is owed"; return 1
  fi
  [ "$owed" -eq 0 ] || { echo "red: a sitting is recorded and the owed line still says none is"; return 1; }
  latest="$(awk '/^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$file")"
  for f in $EXAM_CHECKS; do
    lines="$(printf '%s' "$latest" | awk -v f="$f" '$1 == "sha256" && $2 == f { print $3 }')"
    case "$(printf '%s' "$lines" | awk 'END { print NR }')" in
      1) want="$lines" ;;
      0) echo "red: the latest sitting has no sha256 line for $f"; return 1 ;;
      *) echo "red: the latest sitting has more than one sha256 line for $f"; return 1 ;;
    esac
    have="$(_detect_sha256 "$root/$f")" || { echo "red: $f cannot be digested"; return 1; }
    [ "$want" = "$have" ] || { echo "red: $f is $have, the latest sitting read $want — sit the exam again"; return 1; }
  done
  echo "pinned"
}

# pin_call <sittings file> <root> — sets PIN_OUT and PIN_RC.
pin_call() { PIN_OUT="$(exam_pin "$1" "$2")"; PIN_RC=$?; }

setup_section "fixtures"

ROOT="$TMP/root"
mkdir -p "$ROOT/payload/context"
for f in $EXAM_CHECKS; do printf 'made-up checks text for %s\n' "$f" > "$ROOT/$f"; done

# sitting_block <date> [<question> <wrong hash>] — a sitting section for $ROOT, the hash of
# checks-<question>.md optionally replaced.
sitting_block() {
  local f h
  printf '## %s\n\n' "$1"
  for f in $EXAM_CHECKS; do
    h="$(_detect_sha256 "$ROOT/$f")"
    [ "$f" = "payload/context/checks-${2:-}.md" ] && h="${3}"
    printf 'sha256 %s %s\n' "$f" "$h"
  done
  printf '\nresult dup-counter structure reviewer fail met\n\n'
}
WRONG="0000000000000000000000000000000000000000000000000000000000000000"

section "§PIN — the latest sitting's hashes against the checks files"

sitting_block 2026-10-05 > "$TMP/right.md"
pin_call "$TMP/right.md" "$ROOT"
expect_eq "P1: a sitting with the three right hashes is pinned" "pinned" "$PIN_OUT"
expect_status "P1: rc 0" 0 "$PIN_RC"

sitting_block 2026-10-05 structure "$WRONG" > "$TMP/wrong.md"
pin_call "$TMP/wrong.md" "$ROOT"
expect_contains "P2: one wrong hash is red and names its file" "red: payload/context/checks-structure.md is" "$PIN_OUT"
expect_status "P2: rc 1" 1 "$PIN_RC"

{ sitting_block 2026-10-05 evidence "$WRONG"; sitting_block 2026-10-06; } > "$TMP/old-wrong.md"
pin_call "$TMP/old-wrong.md" "$ROOT"
expect_eq "P3: an older wrong sitting under a right latest one is pinned" "pinned" "$PIN_OUT"
{ sitting_block 2026-10-05; sitting_block 2026-10-06 evidence "$WRONG"; } > "$TMP/new-wrong.md"
pin_call "$TMP/new-wrong.md" "$ROOT"
expect_contains "P3: a right older sitting does not excuse a wrong latest one" "red: payload/context/checks-evidence.md is" "$PIN_OUT"

grep -v 'checks-adversarial' "$TMP/right.md" > "$TMP/missing.md"
pin_call "$TMP/missing.md" "$ROOT"
expect_eq "P4: a sitting with no line for a checks file is red" \
  "red: the latest sitting has no sha256 line for payload/context/checks-adversarial.md" "$PIN_OUT"
{ cat "$TMP/right.md"; grep 'checks-evidence' "$TMP/right.md"; } > "$TMP/twice.md"
pin_call "$TMP/twice.md" "$ROOT"
expect_eq "P4: a sitting naming a checks file twice is red" \
  "red: the latest sitting has more than one sha256 line for payload/context/checks-evidence.md" "$PIN_OUT"

# The failure the pin exists for: a checks file changes and no one sits the exam again.
cp -R "$ROOT" "$TMP/edited"
printf 'one sharpened sentence\n' >> "$TMP/edited/payload/context/checks-adversarial.md"
pin_call "$TMP/right.md" "$TMP/edited"
expect_contains "P5: a checks file edited after its sitting turns the pin red" "red: payload/context/checks-adversarial.md is" "$PIN_OUT"
expect_status "P5: rc 1" 1 "$PIN_RC"
pin_call "$TMP/right.md" "$ROOT"
expect_eq "P5: the same sitting over the unedited files stays pinned" "pinned" "$PIN_OUT"

section "§OWED — before the first sitting"

printf '%s\n' "$EXAM_OWED_LINE" > "$TMP/owed.md"
pin_call "$TMP/owed.md" "$ROOT"
expect_eq "O1: the owed line and no sitting is owed" "owed" "$PIN_OUT"
expect_status "O1: rc 0" 0 "$PIN_RC"

: > "$TMP/neither.md"
pin_call "$TMP/neither.md" "$ROOT"
expect_eq "O2: neither the owed line nor a sitting is red" \
  "red: no sitting is recorded and no line says the first is owed" "$PIN_OUT"
expect_status "O2: rc 1" 1 "$PIN_RC"

{ printf '%s\n\n' "$EXAM_OWED_LINE"; cat "$TMP/right.md"; } > "$TMP/both.md"
pin_call "$TMP/both.md" "$ROOT"
expect_eq "O3: a sitting beside the owed line is red" \
  "red: a sitting is recorded and the owed line still says none is" "$PIN_OUT"

section "§SAMPLES — every answer key in shape, every sample materializes"

SAMPLES="$(cd "$EXAM/samples" 2>/dev/null && for d in */; do printf '%s\n' "${d%/}"; done)"
expect_nonempty "S0: the exam has samples" "$SAMPLES"
expect_true "S0: one of them is the clean sample" test -d "$EXAM/samples/clean"

n=0
for s in $SAMPLES; do
  n=$((n + 1))
  key="$EXAM/samples/$s/expect.txt"
  expect_eq "S1 $s: expect.txt is three lines" "3" "$(awk 'END { print NR }' "$key" 2>/dev/null)"
  expect_regex "S1 $s: question line names questions from the set" \
    '^question: (evidence|adversarial|structure)(, (evidence|adversarial|structure))*$' "$(sed -n 1p "$key")"
  expect_regex "S1 $s: result line is pass, flag or fail" '^result: (pass|flag|fail)$' "$(sed -n 2p "$key")"
  expect_regex "S1 $s: token line carries a token" '^token: [^ ].*$' "$(sed -n 3p "$key")"
  out="$(bash "$EXAM/materialize.sh" "$EXAM/samples/$s" "$TMP/m$n" 2>&1)"; rc=$?
  expect_status "S2 $s: materializes" 0 "$rc"
  expect_regex "S2 $s: prints the range a..b" '^[0-9a-f]{40}\.\.[0-9a-f]{40}$' "$out"
  expect_eq "S2 $s: the range is the two commits the repository holds" \
    "$out" "$(git -C "$TMP/m$n" rev-parse HEAD~1 2>/dev/null)..$(git -C "$TMP/m$n" rev-parse HEAD 2>/dev/null)"
  expect_nonempty "S2 $s: the change commit changes files" "$(git -C "$TMP/m$n" diff --name-only HEAD~1 HEAD 2>/dev/null)"
  expect_false "S2 $s: the answer key does not travel" test -e "$TMP/m$n/expect.txt"
done

section "§SHIPPED — the shipped sittings against the shipped checks files"

for f in $EXAM_CHECKS; do
  expect_regex "SH0: the digest reads $f" '^[0-9a-f]{64}$' "$(_detect_sha256 "$REPO/$f")"
done
pin_call "$EXAM/sittings.md" "$REPO"
if [ "$PIN_OUT" = "owed" ]; then
  ok "RE-AUTHORED BY T22: the first sitting is owed by wave-27 T22 (sittings.md carries the owed line and no sitting)"
else
  expect_eq "SH1: the latest sitting read the checks files that ship" "pinned" "$PIN_OUT"
fi

finish
