#!/bin/bash
# Tests for tests/reader-exam/ — the reader exam's pin (wave-27 T18; spec D11, AC-5.3, AC-4.4).
#
# THE EXAM ITSELF IS NOT RUN HERE. A sitting dispatches live readers (README.md in
# tests/reader-exam/), and no hermetic suite can. What this suite owns is what a machine can
# hold the exam to: the checks files the readers were examined on are the ones that ship, and
# the latest sitting had readers behind it who met every sample, and the recipe a sitter follows
# is in the tree. Nine sections:
#
#   §PIN      `exam_pin` on planted sittings: the latest sitting, by file order, has the
#             three `sha256` lines equal to the files' digests, a `result` line for every
#             sample and none for a sample that does not exist, a line from each role the
#             README dispatches on each question the sample's key names (the role the dealing
#             gives it and the one-mind critic) and none for a question the key does not
#             name, no `missed`, no two lines for one sample and question that disagree, and
#             no `met` line whose reached result its sample's key does not admit; a `##` line
#             that is not a sitting header is red wherever it is; a file with no sitting in it,
#             whether empty or holding a sitting's lines under no header, is red for that.
#             Otherwise the verdict is red and names why. A checks file edited after its sitting
#             turns it red.
#   §KEY      `exam_key` on planted keys: three lines for `clean`, six for every other
#             sample: a `names:` line, whose alternatives are separated by ` | `, then a
#             `finding-file:` line and a `finding-rating:` line whose every rating the priority
#             table sends to fix (wave-28 T18, D22).
#   §SCORE    `exam_score` (tests/reader-exam/score.sh, README step 5) on the real keys: a
#             record is met only on the key's question, with the key's result, one of its
#             tokens and one of its `names:` alternatives, and a declared `finding:` line on
#             the key's file at a rating the table sends to fix (SD rows: described only,
#             deferred, noted, another file and refused lines each fail and say which; the
#             lines are read by proof.sh's `proof_findings`; a doctored scorer restoring the
#             described-only pass is the mutation arm), read through CR LF line ends and
#             trailing blanks and under a caller's IFS; sourcing score.sh is held to defining
#             its functions and nothing else, against doctored copies that act.
#   §DEST     materialize.sh refuses a destination whose path, logical or real, names the
#             sample in any case.
#   §SAMPLES  every sample has its answer key in shape and materializes into a two-commit
#             repository that the key does not travel into, carrying its own `.bionic/`; no
#             record path the README hands a reader holds a sample's name; the exclude that
#             keeps `.bionic/` out of the built sample's status is read through a record
#             written there, and against a materialize.sh without it.
#   §RECIPE   what README step 3 hands a sitter: the rule that finds a session's transcript
#             directory, read from the README and applied to a made-up path; run-session.sh run
#             against a fake CLI binary (the call it makes, the variables it clears, the binary
#             and not a function of the same name, no widening flag); gen-prompt.sh on made-up
#             briefs; neither helper nor any prompt it writes names a sample or the exam; each
#             brief ends with the shipped scale's path and its questions' checks files, by path
#             and never pasted (R9, wave-28 T18). No session is started.
#   §HELPERS  (T64) run-session.sh against a fake CLI on a throwaway PATH: a claude that is a
#             relative path (an entry `.`, an empty one, a named relative one) or a file inside
#             <dest>, reached through a link or not, is refused and never runs; a <dest> that is
#             this checkout or inside it is refused by both helpers, and a copy outside any
#             checkout does not refuse; a fifth argument is refused, and the same row is red on a
#             doctored copy that passes it on; README steps 2 and 3 say each.
#   §CALLERS  (T73) review pass 52's callers as ONE table, driven against copies of both
#             helpers in a throwaway repository with three worktrees: for each, what ran and
#             where, what is new or changed under the throwaway root, and the first line said.
#             The helpers run on an environment they make, read the caller's PATH only for
#             claude and refuse any entry that is not absolute, decide "inside" by identity,
#             resolve each path once and use that, refuse a failed lookup of their worktrees,
#             and keep a destination and an output file out of every worktree.
#   §SHIPPED  the shipped `sittings.md` against the shipped checks files.
#
# FIXTURE FIDELITY (declared, per .claude/rules/test-harness.md, "Fixture fidelity"): §PIN runs
# the suite's own `exam_pin` — the same function §SHIPPED runs on the real files —
# over planted `sittings.md` files and a planted root holding three checks files of made-up
# text and two sample directories. SYNTHESIZED: the checks text and the hashes written into
# the planted sittings, which are taken by the same digest function the verdict uses, or
# deliberately wrong; the `result` lines, whose roles the fixture spells itself (P13 holds
# them to the dealing the verdict reads); the two planted samples' keys. §KEY plants keys;
# §SAMPLES runs the same `exam_key` on the real ones. §SCORE plants reader records against
# the REAL keys, through the same score.sh a sitting sources; the one-mind records of SC5 are
# review pass 18's planted records, copied. §DEST and §SAMPLES run the real samples through
# the real materialize.sh into real git repositories. §RECIPE runs the real helpers; SYNTHESIZED
# there: the CLI binary (a script on PATH that records its argv, working directory and
# environment, with a shell function of the same name exported beside it), the parent session's
# variables, and the briefs. The shipped README is read, not copied. §CALLERS runs byte copies of
# the real helpers in a model repository; SYNTHESIZED there: every program and environment a
# caller supplies (its own block says which), and copies whose own PATH is a directory of
# the fixture's (no git, or a git that answers nothing, two lines, or a foreign directory).
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
# The dealing: which role the audited rigor deals each question to (`facts_owed`, README step 4),
# read from the one table and not restated here.
. "${REPO}/payload/scripts/lib/proof.sh"
# The scorer: README step 5, the one a sitting sources (tests/reader-exam/score.sh).
. "${EXAM}/score.sh"

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

# exam_samples <root> — the sample names under <root>, one per line.
exam_samples() {
  (cd "$1/tests/reader-exam/samples" 2>/dev/null && for d in */; do [ -d "$d" ] && printf '%s\n' "${d%/}"; done)
}

# exam_dealt_role <question> — the role the audited dealing gives <question> (`auditor`,
# `critic` or `reviewer`), from the dealing `facts_owed` holds; nothing when it deals none.
exam_dealt_role() {
  facts_owed audited wave 2>/dev/null | awk -F'\t' -v q="$1" \
    '$1 == "review" && $2 == q && $4 == "piece" { sub(/^bionic:/, "", $3); print $3; exit }'
}

# exam_pin <sittings file> <root> — prints one verdict line, rc 0 only when the exam holds:
#   pinned                 the latest sitting names each checks file under <root> once, with
#                          its digest, has a `result` line for every sample under <root> and
#                          none for any other, a line on each question its sample's key names
#                          from the role the audited dealing gives that question and from
#                          `one-mind` (the critic holding all three), and none on a question
#                          the key does not name or from a role that is neither `one-mind` nor
#                          the one dealt its own question, no two lines for one sample and question
#                          that disagree, every `result` line reads `met`, and each reached
#                          result is one its sample's key admits (exam_meets, score.sh)
#   red <reason>           anything else
# A sitting is a section headed `## <YYYY-MM-DD>…`; the latest is the last in the file, by
# file order and not by date. Any other line opening with `##` is red wherever it is.
exam_pin() {
  local file="$1" root="$2" sittings latest f lines want have s samples bad results line kqs q r dealt
  [ -r "$file" ] || { echo "red: $file cannot be read"; return 1; }
  # A block under a malformed header would fold into the sitting above it, or count as none.
  bad="$(grep -nE '^##' "$file" | grep -vE '^[0-9]+:## [0-9]{4}-[0-9]{2}-[0-9]{2}( |$)' | head -n 1)"
  [ -z "$bad" ] || { echo "red: line ${bad%%:*}, '${bad#*:}', is not a sitting header: a block under it belongs to no sitting"; return 1; }
  sittings="$(grep -cE '^## [0-9]{4}-[0-9]{2}-[0-9]{2}' "$file")"
  [ "$sittings" -gt 0 ] || { echo "red: no sitting is recorded"; return 1; }
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
  # A hash with no readers behind it is the pin lying: every sample was sat, and met.
  samples="$(exam_samples "$root")"
  [ -n "$samples" ] || { echo "red: $root has no samples"; return 1; }
  results="$(printf '%s\n' "$latest" | awk '$1 == "result"')"
  bad="$(printf '%s\n' "$results" | ALL="$samples" awk '
    BEGIN { n = split(ENVIRON["ALL"], a, "\n"); for (i = 1; i <= n; i++) known[a[i]] = 1 }
    $1 == "result" && !($2 in known) { print $2; exit }')"
  [ -z "$bad" ] || { echo "red: the latest sitting has a result line for $bad, and no such sample is under $root"; return 1; }
  for s in $samples; do
    printf '%s\n' "$results" | awk -v s="$s" '$2 == s { f = 1 } END { exit !f }' \
      || { echo "red: the latest sitting has no result line for $s"; return 1; }
  done
  # A sample is scored on the record for the question its key names, and only that one: a line
  # for another question is a reader's unscored record, kept in the sitting and not recorded here.
  # The readers dealt each keyed question are the role the dealing gives it and the one-mind critic.
  for s in $samples; do
    kqs="$(exam_field "$root/tests/reader-exam/samples/$s/expect.txt" question | tr -d ' ')"
    bad="$(printf '%s\n' "$results" | awk -v s="$s" -v kq="$kqs" '
      BEGIN { n = split(kq, a, ","); for (i = 1; i <= n; i++) ok[a[i]] = 1 }
      $2 == s && !($3 in ok) { print; exit }')"
    [ -z "$bad" ] || { echo "red: the latest sitting's line '$bad' is for a question $s's key does not name ($kqs)"; return 1; }
    dealt=""
    for q in evidence adversarial structure; do
      r="$(exam_dealt_role "$q")"
      [ -n "$r" ] || { echo "red: the audited dealing gives $q to no role"; return 1; }
      dealt="${dealt:+$dealt,}$q=$r"
    done
    bad="$(printf '%s\n' "$results" | awk -v s="$s" -v dt="$dealt" '
      BEGIN { n = split(dt, a, ","); for (i = 1; i <= n; i++) { split(a[i], p, "="); role[p[1]] = p[2] } }
      $2 == s && $4 != "one-mind" && $4 != role[$3] { print; exit }')"
    if [ -n "$bad" ]; then
      set -f; set -- $bad; set +f
      echo "red: the latest sitting's line '$bad' is from a role that is neither the $(exam_dealt_role "$3") dealt $3 nor one-mind"; return 1
    fi
    for q in ${kqs//,/ }; do
      r="$(exam_dealt_role "$q")"
      for r in "$r" one-mind; do
        printf '%s\n' "$results" | awk -v s="$s" -v q="$q" -v r="$r" '$2 == s && $3 == q && $4 == r { f = 1 } END { exit !f }' \
          || { echo "red: the latest sitting has no line for $s from the $r on $q"; return 1; }
      done
    done
  done
  bad="$(printf '%s\n' "$results" | awk '$1 == "result" && $6 != "met" && $6 != "missed" { print $2; exit }')"
  [ -z "$bad" ] || { echo "red: the latest sitting has a result line for $bad that reads neither met nor missed"; return 1; }
  bad="$(printf '%s\n' "$results" | awk '$1 == "result" { k = $2 " " $3; if ((k in v) && v[k] != $6) { print k; exit } v[k] = $6 }')"
  [ -z "$bad" ] || { echo "red: the latest sitting's lines for $bad disagree, met and missed"; return 1; }
  bad="$(printf '%s\n' "$results" | awk '$1 == "result" && $6 == "missed" { print $2; exit }')"
  [ -z "$bad" ] || { echo "red: the latest sitting missed $bad — send its checks file to a fix row and sit the exam again"; return 1; }
  # Each `met` line against its sample's key: met means the reader reached what the key asks.
  while IFS= read -r line; do
    set -f; set -- $line; set +f
    [ "${1:-}" = result ] || continue
    want="$(exam_field "$root/tests/reader-exam/samples/$2/expect.txt" result 2>/dev/null)"
    exam_meets "$want" "${5:-}" \
      || { echo "red: the latest sitting's line '$line' reads met, and $2's key says ${want:-nothing}"; return 1; }
  done <<RESULTS
$results
RESULTS
  echo "pinned"
}

# exam_key <sample> <key file> — prints `key` when the answer key is in shape, else one red
# line. Three lines for `clean` (question, result, token); six for every other sample: the
# fourth `names: <identifier>[ | <identifier>]...`, the spellings of the one thing that shows
# the record named the planted defect, which `clean` has none of; the fifth
# `finding-file: <path>[ | <path>]...`, the file the reader's `finding:` line must name; the sixth
# `finding-rating: <S> <reach>[ | <S> <reach>]...`, the ratings that pass it, each one the table
# sends to fix (`proof_priority`, the table's one cell) (wave-28 T18, D22). No alternative is empty.
exam_key() {
  local name="$1" key="$2" n want alt
  [ -r "$key" ] || { echo "red: $key cannot be read"; return 1; }
  sed -n 1p "$key" | grep -Eq '^question: (evidence|adversarial|structure)(, (evidence|adversarial|structure))*$' \
    || { echo "red: $name's key line 1 is not a question line"; return 1; }
  sed -n 2p "$key" | grep -Eq '^result: (pass|flag|fail)$' \
    || { echo "red: $name's key line 2 is not a result line"; return 1; }
  sed -n 3p "$key" | grep -Eq '^token: [^ ].*$' \
    || { echo "red: $name's key line 3 is not a token line"; return 1; }
  if [ "$name" = clean ]; then
    want=3
    ! grep -q '^names:' "$key" || { echo "red: clean's key has a names: line, and clean has no defect to name"; return 1; }
    ! grep -q '^finding-' "$key" || { echo "red: clean's key has a finding- line, and clean has no defect to declare"; return 1; }
  else
    want=6
    sed -n 4p "$key" | grep -Eq '^names: [^ ]' || { echo "red: $name's key has no names: line"; return 1; }
    ! sed -n 4p "$key" | sed 's/^names: //' | awk -F ' [|] ' '{ for (i = 1; i <= NF; i++) if ($i ~ /^[[:blank:]]*$/) e = 1 } END { exit !e }' \
      || { echo "red: $name's names: line has an empty alternative"; return 1; }
    sed -n 5p "$key" | grep -Eq '^finding-file: [^ ]' || { echo "red: $name's key has no finding-file: line"; return 1; }
    ! sed -n 5p "$key" | sed 's/^finding-file: //' | awk -F ' [|] ' '{ for (i = 1; i <= NF; i++) if ($i ~ /^[[:blank:]]*$/ || $i ~ /[[:blank:]]/) e = 1 } END { exit !e }' \
      || { echo "red: $name's finding-file: line has an empty alternative or one holding a blank"; return 1; }
    sed -n 6p "$key" | grep -Eq '^finding-rating: [^ ]' || { echo "red: $name's key has no finding-rating: line"; return 1; }
    while IFS= read -r alt; do
      # shellcheck disable=SC2086
      [ "$(proof_priority $alt 2>/dev/null)" = fix ] \
        || { echo "red: $name's finding-rating: '$alt' is not a rating the table sends to fix"; return 1; }
    done <<ALTS
$(sed -n 6p "$key" | sed 's/^finding-rating: //' | awk -F ' [|] ' '{ for (i = 1; i <= NF; i++) print $i }')
ALTS
  fi
  n="$(awk 'END { print NR }' "$key")"
  [ "$n" = "$want" ] || { echo "red: $name's key has $n lines, not $want"; return 1; }
  echo "key"
}

# exam_record_paths <file> — the lines of <file> that spell a reader's record path: a path
# under `docs/record/`, or a `<label>-<role>-<question>.md` name.
exam_record_paths() {
  grep -E 'docs/record/|-(auditor|critic|reviewer|one-mind)-(evidence|adversarial|structure)\.md' "$1"
}

# exam_named_path <file> <root> — the first record-path line of <file> that holds the name of
# a sample under <root>, in any case; nothing when none does.
exam_named_path() {
  exam_record_paths "$1" | ALL="$(exam_samples "$2")" awk '
    BEGIN { n = split(ENVIRON["ALL"], a, "\n") }
    { l = tolower($0); for (i = 1; i <= n; i++) if (a[i] != "" && index(l, a[i])) { print; exit } }'
}

# pin_call <sittings file> <root> — sets PIN_OUT and PIN_RC.
pin_call() { PIN_OUT="$(exam_pin "$1" "$2")"; PIN_RC=$?; }

setup_section "fixtures"

ROOT="$TMP/root"
mkdir -p "$ROOT/payload/context"
for f in $EXAM_CHECKS; do printf 'made-up checks text for %s\n' "$f" > "$ROOT/$f"; done
mkdir -p "$ROOT/tests/reader-exam/samples/dup-counter" "$ROOT/tests/reader-exam/samples/clean"
printf 'question: structure\nresult: fail\ntoken: check: reuse FAIL\nnames: some_owner\n' \
  > "$ROOT/tests/reader-exam/samples/dup-counter/expect.txt"
printf 'question: evidence, adversarial, structure\nresult: pass\ntoken: some-change\n' \
  > "$ROOT/tests/reader-exam/samples/clean/expect.txt"

# fixture_role <question> — the role the audited dealing gives that question, spelled here by
# the fixture (PF0 holds it to the dealing exam_pin reads).
fixture_role() { case "$1" in evidence) echo auditor ;; adversarial) echo critic ;; structure) echo reviewer ;; esac; }
# sitting_block <date> [<question> <wrong hash>] — a sitting section for $ROOT, the hash of
# checks-<question>.md optionally replaced, and, for each sample and each question its key
# names, a `met` result line from the role dealt that question and one from the one-mind
# critic, each reaching its key's result.
sitting_block() {
  local f h s k q r
  printf '## %s\n\n' "$1"
  for f in $EXAM_CHECKS; do
    h="$(_detect_sha256 "$ROOT/$f")"
    [ "$f" = "payload/context/checks-${2:-}.md" ] && h="${3}"
    printf 'sha256 %s %s\n' "$f" "$h"
  done
  printf '\n'
  for s in $(exam_samples "$ROOT"); do
    k="$ROOT/tests/reader-exam/samples/$s/expect.txt"
    for q in $(sed -n 's/^question: //p' "$k" | tr ',' ' '); do
      for r in "$(fixture_role "$q")" one-mind; do
        printf 'result %s %s %s %s met exam-sitting.md#%s-%s-%s\n' "$s" "$q" "$r" "$(sed -n 's/^result: //p' "$k")" "$s" "$r" "$q"
      done
    done
  done
  printf '\n'
}
# with_result <file> <sample> <sixth field> — the file with that sample's result lines rewritten.
with_result() {
  awk -v s="$2" -v v="$3" '$1 == "result" && $2 == s { $6 = v } { print }' "$1"
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

# A hash with no readers behind it: the right hashes, and a sample nobody sat or a reader who
# missed. right.md is the green one edit away from each.
expect_eq "P6: the fixture sitting has two lines for dup-counter's one question and six for clean's three" "8" \
  "$(awk '$1 == "result"' "$TMP/right.md" | awk 'END { print NR }')"
grep -v '^result clean ' "$TMP/right.md" > "$TMP/unsat.md"
pin_call "$TMP/unsat.md" "$ROOT"
expect_eq "P6: a sitting with the right hashes and no result line for one sample is red and names it" \
  "red: the latest sitting has no result line for clean" "$PIN_OUT"
expect_status "P6: rc 1" 1 "$PIN_RC"
grep -v '^result ' "$TMP/right.md" > "$TMP/noreaders.md"
pin_call "$TMP/noreaders.md" "$ROOT"
expect_contains "P6: a sitting with the right hashes and no result line at all is red" \
  "red: the latest sitting has no result line for" "$PIN_OUT"

with_result "$TMP/right.md" clean missed > "$TMP/missed.md"
pin_call "$TMP/missed.md" "$ROOT"
expect_eq "P7: a sitting with the right hashes and a missed sample is red and names it" \
  "red: the latest sitting missed clean — send its checks file to a fix row and sit the exam again" "$PIN_OUT"
expect_status "P7: rc 1" 1 "$PIN_RC"
with_result "$TMP/right.md" clean mett > "$TMP/garbled.md"
pin_call "$TMP/garbled.md" "$ROOT"
expect_eq "P7: a result line reading neither met nor missed is red" \
  "red: the latest sitting has a result line for clean that reads neither met nor missed" "$PIN_OUT"

# "Latest" is the last sitting in the file, by file order: not the newest date.
{ sed 's/^## 2026-10-05/## 2026-10-04/' "$TMP/missed.md"; cat "$TMP/right.md"; } > "$TMP/order-resat.md"
pin_call "$TMP/order-resat.md" "$ROOT"
expect_eq "P8: the latest sitting, by file order: a miss sat again below it is pinned" "pinned" "$PIN_OUT"
{ cat "$TMP/right.md"; sed 's/^## 2026-10-05/## 2026-10-06/' "$TMP/unsat.md"; } > "$TMP/order-unsat.md"
pin_call "$TMP/order-unsat.md" "$ROOT"
expect_eq "P8: the latest sitting, by file order: a complete sitting above does not excuse an unsat sample" \
  "red: the latest sitting has no result line for clean" "$PIN_OUT"
{ sed 's/^## 2026-10-05/## 2026-10-06/' "$TMP/right.md"; cat "$TMP/missed.md"; } > "$TMP/order-date.md"
pin_call "$TMP/order-date.md" "$ROOT"
expect_eq "P8: the latest sitting, by file order: the last block governs though an earlier block has the later date" \
  "red: the latest sitting missed clean — send its checks file to a fix row and sit the exam again" "$PIN_OUT"

# Each result line against its sample's key. The fixture's lines reach their keys' results.
expect_eq "P9: the fixture sitting's dup-counter line reaches its key's fail" \
  "result dup-counter structure reviewer fail met exam-sitting.md#dup-counter-reviewer-structure" \
  "$(grep '^result dup-counter structure reviewer ' "$TMP/right.md")"
expect_eq "P9: the fixture sitting's clean line reaches its key's pass" \
  "result clean evidence auditor pass met exam-sitting.md#clean-auditor-evidence" \
  "$(grep '^result clean evidence auditor ' "$TMP/right.md")"
sed 's/^result dup-counter structure reviewer fail met/result dup-counter structure reviewer pass met/' "$TMP/right.md" > "$TMP/contra.md"
pin_call "$TMP/contra.md" "$ROOT"
expect_eq "P9: a met line whose reached pass the key's fail does not admit is red and names the line" \
  "red: the latest sitting's line 'result dup-counter structure reviewer pass met exam-sitting.md#dup-counter-reviewer-structure' reads met, and dup-counter's key says fail" "$PIN_OUT"
expect_status "P9: rc 1" 1 "$PIN_RC"
sed 's/^result clean evidence auditor pass met/result clean evidence auditor flag met/' "$TMP/right.md" > "$TMP/clean-flag.md"
pin_call "$TMP/clean-flag.md" "$ROOT"
expect_eq "P9: a met flag on clean, whose key admits pass or flag, is pinned" "pinned" "$PIN_OUT"
sed 's/^result clean evidence auditor pass met/result clean evidence auditor fail met/' "$TMP/right.md" > "$TMP/clean-fail.md"
pin_call "$TMP/clean-fail.md" "$ROOT"
expect_contains "P9: a met fail on clean is red" "reads met, and clean's key says pass" "$PIN_OUT"

{ cat "$TMP/right.md"; printf 'result no-such-sample structure reviewer fail met h\n'; } > "$TMP/ghost.md"
pin_call "$TMP/ghost.md" "$ROOT"
expect_eq "P10: a result line for a sample that does not exist is red and names it" \
  "red: the latest sitting has a result line for no-such-sample, and no such sample is under $ROOT" "$PIN_OUT"
expect_status "P10: rc 1" 1 "$PIN_RC"

{ cat "$TMP/right.md"; printf 'result dup-counter structure one-mind fail met h\n'; } > "$TMP/agree.md"
pin_call "$TMP/agree.md" "$ROOT"
expect_eq "P11: two lines for one sample and question that agree are pinned" "pinned" "$PIN_OUT"
{ cat "$TMP/right.md"; printf 'result dup-counter structure one-mind fail missed h\n'; } > "$TMP/disagree.md"
pin_call "$TMP/disagree.md" "$ROOT"
expect_eq "P11: two lines for one sample and question that disagree are red and name the pair" \
  "red: the latest sitting's lines for dup-counter structure disagree, met and missed" "$PIN_OUT"
expect_status "P11: rc 1" 1 "$PIN_RC"

{ cat "$TMP/right.md"; sed 's/^## 2026-10-05/## 2026-10-06 — sat again after an edit/' "$TMP/right.md"; } > "$TMP/titled.md"
pin_call "$TMP/titled.md" "$ROOT"
expect_eq "P12: a sitting header with its title after the date is a header" "pinned" "$PIN_OUT"
{ cat "$TMP/unsat.md"; printf '##2026-10-06\n\nresult clean evidence reviewer pass met h\n'; } > "$TMP/malformed-fill.md"
pin_call "$TMP/malformed-fill.md" "$ROOT"
expect_contains "P12: a block under a malformed header belongs to no sitting and is red" \
  "red: line $(grep -n '^##2026' "$TMP/malformed-fill.md" | cut -d: -f1), '##2026-10-06', is not a sitting header" "$PIN_OUT"
expect_status "P12: rc 1" 1 "$PIN_RC"
{ cat "$TMP/right.md"; printf '## 2026-1-6 sat again\n\nresult clean evidence reviewer pass met h\n'; } > "$TMP/malformed-date.md"
pin_call "$TMP/malformed-date.md" "$ROOT"
expect_contains "P12: a header whose date is not YYYY-MM-DD is red" "'## 2026-1-6 sat again', is not a sitting header" "$PIN_OUT"

# The lines a sitting owes, and the lines it may hold (review pass 23: F1 and note 2). A sample
# is scored on the record for the question its key names; the readers the README dispatches on
# that question are the role dealt it and the one-mind critic (`one-mind`), and a sitting holds
# a line from each of them, on that question and no other. right.md is the green one edit away.
for q in evidence adversarial structure; do
  expect_eq "P13: the fixture's role for $q is the role the audited dealing gives it" \
    "$(fixture_role "$q")" "$(exam_dealt_role "$q")"
done
{ cat "$TMP/right.md"; printf 'result dup-counter evidence auditor fail met h\n'; } > "$TMP/unkeyed.md"
pin_call "$TMP/unkeyed.md" "$ROOT"
expect_eq "P14: a result line for a question its sample's key does not name is red and names the line" \
  "red: the latest sitting's line 'result dup-counter evidence auditor fail met h' is for a question dup-counter's key does not name (structure)" "$PIN_OUT"
expect_status "P14: rc 1" 1 "$PIN_RC"
{ cat "$TMP/right.md"; printf 'result dup-counter adversarial one-mind pass missed h\n'; } > "$TMP/unkeyed-missed.md"
pin_call "$TMP/unkeyed-missed.md" "$ROOT"
expect_eq "P14: …a line for an unkeyed question that reads missed is red for the question, not scored" \
  "red: the latest sitting's line 'result dup-counter adversarial one-mind pass missed h' is for a question dup-counter's key does not name (structure)" "$PIN_OUT"
grep -v '^result dup-counter structure reviewer ' "$TMP/right.md" > "$TMP/onemind-only.md"
expect_eq "P15: the fixture sitting with the reviewer's line left off holds dup-counter's one-mind line alone" "1" \
  "$(grep -c '^result dup-counter ' "$TMP/onemind-only.md")"
pin_call "$TMP/onemind-only.md" "$ROOT"
expect_eq "P15: a sample holding only the one-mind critic's line is red, naming the sample and the role missing" \
  "red: the latest sitting has no line for dup-counter from the reviewer on structure" "$PIN_OUT"
expect_status "P15: rc 1" 1 "$PIN_RC"
grep -v '^result dup-counter structure one-mind ' "$TMP/right.md" > "$TMP/dealt-only.md"
pin_call "$TMP/dealt-only.md" "$ROOT"
expect_eq "P15: …and the dealt reader's line alone is red, naming the one-mind critic" \
  "red: the latest sitting has no line for dup-counter from the one-mind on structure" "$PIN_OUT"
for role_q in auditor:evidence critic:adversarial reviewer:structure one-mind:evidence; do
  role="${role_q%%:*}"
  grep -v "^result clean [a-z]* $role " "$TMP/right.md" > "$TMP/clean-no-$role.md"
  expect_eq "P16: clean without its $role lines has fewer lines than the fixture sitting" "true" \
    "$([ "$(grep -c '^result clean ' "$TMP/clean-no-$role.md")" -lt "$(grep -c '^result clean ' "$TMP/right.md")" ] && echo true || echo false)"
  pin_call "$TMP/clean-no-$role.md" "$ROOT"
  expect_eq "P16: a clean sample missing its $role is red, naming the sample and the role" \
    "red: the latest sitting has no line for clean from the ${role} on ${role_q#*:}" "$PIN_OUT"
done
grep -v '^result clean adversarial one-mind ' "$TMP/right.md" > "$TMP/clean-one-mind-q.md"
pin_call "$TMP/clean-one-mind-q.md" "$ROOT"
expect_eq "P16: a clean sample whose one-mind critic left a question off is red, naming the question" \
  "red: the latest sitting has no line for clean from the one-mind on adversarial" "$PIN_OUT"

# A role field is one of auditor, critic, reviewer or one-mind, and a dealt role is on the
# question it is dealt: a line from any other role, or from a role on a question that is not its
# own, is red. A line from the one-mind critic is on any keyed question.
{ cat "$TMP/right.md"; printf 'result dup-counter structure nobody fail met h\n'; } > "$TMP/stray-role.md"
pin_call "$TMP/stray-role.md" "$ROOT"
expect_eq "P17: a line whose role is outside auditor, critic, reviewer and one-mind is red and names the line" \
  "red: the latest sitting's line 'result dup-counter structure nobody fail met h' is from a role that is neither the reviewer dealt structure nor one-mind" "$PIN_OUT"
expect_status "P17: rc 1" 1 "$PIN_RC"
{ cat "$TMP/right.md"; printf 'result dup-counter structure critic fail met h\n'; } > "$TMP/mismatch-role.md"
pin_call "$TMP/mismatch-role.md" "$ROOT"
expect_eq "P17: a dealt role on a question that is not its own is red and names the line" \
  "red: the latest sitting's line 'result dup-counter structure critic fail met h' is from a role that is neither the reviewer dealt structure nor one-mind" "$PIN_OUT"
{ cat "$TMP/right.md"; printf 'result dup-counter structure reviewer fail met h\n'; } > "$TMP/second-reviewer.md"
pin_call "$TMP/second-reviewer.md" "$ROOT"
expect_eq "P17: a second line from the dealt role on its own question is pinned" "pinned" "$PIN_OUT"

# A file with no sitting in it has one answer, whatever else it holds: the sha256 and result lines
# of a sitting under no `##` header belong to no sitting, and an empty file holds none.
grep -v '^## ' "$TMP/right.md" > "$TMP/no-header.md"
expect_eq "P18: the fixture sitting with its header left off still holds its three sha256 lines" "3" \
  "$(grep -c '^sha256 ' "$TMP/no-header.md")"
expect_eq "P18: …and its result lines" "$(grep -c '^result ' "$TMP/right.md")" "$(grep -c '^result ' "$TMP/no-header.md")"
expect_eq "P18: …and no header line" "0" "$(grep -c '^##' "$TMP/no-header.md")"
pin_call "$TMP/no-header.md" "$ROOT"
expect_eq "P18: a sittings file that has lost its header is red, as one with no sitting" \
  "red: no sitting is recorded" "$PIN_OUT"
expect_status "P18: rc 1" 1 "$PIN_RC"
: > "$TMP/empty-sittings.md"
pin_call "$TMP/empty-sittings.md" "$ROOT"
expect_eq "P18: an empty sittings file is red by the same line" "red: no sitting is recorded" "$PIN_OUT"
expect_status "P18: rc 1" 1 "$PIN_RC"

# A STALE MARK (wave-28 T18, ruling A-orch-110): checks files that changed after the latest sitting
# leave its hashes behind, and the re-sit is the next step's. The sitting says so on one line,
# `stale: checks-<q> <old>… → <new>…[, …] (…); re-sit owed: …`, and the pin passes only while that line
# names, for every checks file whose hash differs, the hash the sitting read and the hash that ships.
# An unmarked drift, or a line naming other hashes, is red; the line excuses nothing else.
h8() { _detect_sha256 "$ROOT/payload/context/checks-$1.md" | cut -c1-8; }
w8() { printf '%s' "$WRONG" | cut -c1-8; }
stale_line() { printf 'stale: %s (T16, T48); re-sit owed: T27\n' "$1"; }
SL_S="checks-structure $(w8)… → $(h8 structure)…"
sitting_block 2026-10-05 structure "$WRONG" > "$TMP/stale-base.md"
{ cat "$TMP/stale-base.md"; stale_line "$SL_S"; } > "$TMP/stale-ok.md"
pin_call "$TMP/stale-ok.md" "$ROOT"
expect_eq "P19: a sitting whose structure hash differs and whose stale: line names both hashes is pinned, marked stale" \
  "pinned (stale: the re-sit is owed)" "$PIN_OUT"
expect_status "P19: rc 0" 0 "$PIN_RC"
pin_call "$TMP/stale-base.md" "$ROOT"
expect_contains "P19: the same sitting with no stale: line is an unmarked drift, red" "red: payload/context/checks-structure.md is" "$PIN_OUT"
expect_status "P19: rc 1" 1 "$PIN_RC"
{ cat "$TMP/stale-base.md"; stale_line "checks-structure $(w8)… → 00000000…"; } > "$TMP/stale-other-new.md"
pin_call "$TMP/stale-other-new.md" "$ROOT"
expect_eq "P20: a stale: line naming another hash than the one that ships is red, naming the file" \
  "red: payload/context/checks-structure.md is $(_detect_sha256 "$ROOT/payload/context/checks-structure.md"), the latest sitting read $WRONG, and its stale: line does not name those hashes — sit the exam again" "$PIN_OUT"
{ cat "$TMP/stale-base.md"; stale_line "checks-structure 11111111… → $(h8 structure)…"; } > "$TMP/stale-other-old.md"
pin_call "$TMP/stale-other-old.md" "$ROOT"
expect_contains "P20: …and one naming another hash than the sitting read is red" "its stale: line does not name those hashes" "$PIN_OUT"
{ cat "$TMP/stale-base.md"; stale_line "checks-evidence $(w8)… → $(h8 evidence)…"; } > "$TMP/stale-other-file.md"
pin_call "$TMP/stale-other-file.md" "$ROOT"
expect_contains "P20: …and one naming another checks file is red" "red: payload/context/checks-structure.md is" "$PIN_OUT"
{ cat "$TMP/stale-base.md"; printf 'stale: checks-structure %s... -> %s... (T16); re-sit owed: T27\n' "$(w8)" "$(h8 structure)"; } > "$TMP/stale-ascii.md"
pin_call "$TMP/stale-ascii.md" "$ROOT"
expect_contains "P20: …and a line with no arrow glyph is not the form, red" "its stale: line does not name those hashes" "$PIN_OUT"
sitting_block 2026-10-05 structure "$WRONG" > "$TMP/stale-two.md"
cp "$ROOT/payload/context/checks-adversarial.md" "$TMP/adv.orig"
printf 'new text\n' >> "$ROOT/payload/context/checks-adversarial.md"
{ cat "$TMP/stale-ok.md"; } > "$TMP/stale-one-of-two.md"
pin_call "$TMP/stale-one-of-two.md" "$ROOT"
expect_contains "P21: two checks files differ and the stale: line names one: red, naming the other" \
  "red: payload/context/checks-adversarial.md is" "$PIN_OUT"
{ cat "$TMP/stale-ok.md" | sed '$d'; stale_line "$SL_S, checks-adversarial $(_detect_sha256 "$ROOT/payload/context/checks-adversarial.md" | cut -c1-8)… → $(h8 adversarial)…"; } > "$TMP/stale-both-wrong.md"
pin_call "$TMP/stale-both-wrong.md" "$ROOT"
expect_contains "P21: …and a line whose second entry's old hash is not the sitting's is red" "red: payload/context/checks-adversarial.md is" "$PIN_OUT"
old_adv="$(awk '$1 == "sha256" && $2 == "payload/context/checks-adversarial.md" { print $3 }' "$TMP/stale-two.md")"
{ cat "$TMP/stale-two.md"; stale_line "$SL_S, checks-adversarial $(printf '%s' "$old_adv" | cut -c1-8)… → $(h8 adversarial)…"; } > "$TMP/stale-both-ok.md"
pin_call "$TMP/stale-both-ok.md" "$ROOT"
expect_eq "P21: …and a line naming both differing files, each old and new, is pinned, marked stale" "pinned (stale: the re-sit is owed)" "$PIN_OUT"
cp "$TMP/adv.orig" "$ROOT/payload/context/checks-adversarial.md"
pin_call "$TMP/stale-ok.md" "$ROOT"
expect_eq "P21: the checks file put back, the stale sitting is pinned again by its mark" "pinned (stale: the re-sit is owed)" "$PIN_OUT"
# a marked sitting is history: a result line for a sample since retired does not turn it red
{ cat "$TMP/stale-ok.md"; printf 'result retired-sample structure reviewer fail met exam-sitting.md#retired\n'; } > "$TMP/stale-retired.md"
pin_call "$TMP/stale-retired.md" "$ROOT"
expect_eq "P22: a stale sitting's result line for a retired sample stays as history, pinned" "pinned (stale: the re-sit is owed)" "$PIN_OUT"
{ sitting_block 2026-10-05; stale_line "$SL_S"; printf 'result retired-sample structure reviewer fail met exam-sitting.md#retired\n'; } > "$TMP/stale-nodrift.md"
pin_call "$TMP/stale-nodrift.md" "$ROOT"
expect_contains "P22: …while a sitting whose hashes all match is read whole, whatever its stale: line says" \
  "red: the latest sitting has a result line for retired-sample" "$PIN_OUT"
{ cat "$TMP/stale-ok.md"; printf '\n## 2026-10-06 later\n\n'; printf 'sha256 payload/context/checks-structure.md %s\n' "$WRONG"; } > "$TMP/stale-older.md"
pin_call "$TMP/stale-older.md" "$ROOT"
expect_contains "P23: a stale: line in an older sitting does not excuse the latest one" "red: " "$PIN_OUT"

section "§KEY — an answer key names its defect"

K="$TMP/keys"
mkdir -p "$K"
printf 'question: structure\nresult: fail\ntoken: check: reuse FAIL\nnames: some_owner\nfinding-file: bin/some.sh\nfinding-rating: S2 on\n' > "$K/defect.txt"
expect_eq "K1: a defect key with a names:, finding-file: and finding-rating: line is in shape" "key" "$(exam_key planted "$K/defect.txt")"
{ sed -n 1,3p "$K/defect.txt"; sed -n 5,6p "$K/defect.txt"; } > "$K/defect-unnamed.txt"
expect_eq "K2: a defect key with no names: line is red" \
  "red: planted's key has no names: line" "$(exam_key planted "$K/defect-unnamed.txt")"
expect_status "K2: rc 1" 1 "$(exam_key planted "$K/defect-unnamed.txt" >/dev/null; echo $?)"
sed 's/^names: .*/names: some_owner | other/' "$K/defect.txt" > "$K/defect-two.txt"
expect_eq "K3: a names: line holding two alternatives is in shape" "key" "$(exam_key planted "$K/defect-two.txt")"
sed 's/^names: .*/names: some_owner |  | other/' "$K/defect.txt" > "$K/defect-empty-alt.txt"
expect_eq "K3: a names: line with an empty alternative is red" \
  "red: planted's names: line has an empty alternative" "$(exam_key planted "$K/defect-empty-alt.txt")"
printf 'question: evidence, adversarial, structure\nresult: pass\ntoken: some-change\n' > "$K/clean.txt"
expect_eq "K4: clean's key has no names: line, and none is asked of it" "key" "$(exam_key clean "$K/clean.txt")"
{ cat "$K/clean.txt"; printf 'names: some_owner\n'; } > "$K/clean-named.txt"
expect_eq "K4: clean's key with a names: line is red" \
  "red: clean's key has a names: line, and clean has no defect to name" "$(exam_key clean "$K/clean-named.txt")"
{ cat "$K/defect.txt"; printf 'extra\n'; } > "$K/defect-seven.txt"
expect_eq "K5: a defect key with a seventh line is red" \
  "red: planted's key has 7 lines, not 6" "$(exam_key planted "$K/defect-seven.txt")"
# wave-28 T18 (D22): a defect key says the file a finding must name and the ratings that pass it.
sed -n 1,4p "$K/defect.txt" > "$K/defect-nofile.txt"
printf 'finding-rating: S2 on\n' >> "$K/defect-nofile.txt"
expect_eq "K6: a defect key with no finding-file: line is red" \
  "red: planted's key has no finding-file: line" "$(exam_key planted "$K/defect-nofile.txt")"
sed -n 1,5p "$K/defect.txt" > "$K/defect-norating.txt"
expect_eq "K7: a defect key with no finding-rating: line is red" \
  "red: planted's key has no finding-rating: line" "$(exam_key planted "$K/defect-norating.txt")"
sed 's/^finding-file: .*/finding-file: bin\/some.sh | lib\/other.sh/' "$K/defect.txt" > "$K/defect-twofiles.txt"
expect_eq "K8: a finding-file: line holding two alternatives is in shape" "key" "$(exam_key planted "$K/defect-twofiles.txt")"
sed 's/^finding-file: .*/finding-file: bin\/some.sh |  | lib\/other.sh/' "$K/defect.txt" > "$K/defect-emptyfile.txt"
expect_eq "K8: a finding-file: line with an empty alternative is red" \
  "red: planted's finding-file: line has an empty alternative or one holding a blank" "$(exam_key planted "$K/defect-emptyfile.txt")"
for rating in 'S2 off' 'S3 on' 'S3 off' 'S4 on' 'S4 off' 'S5 on' 'S2'; do
  sed "s/^finding-rating: .*/finding-rating: $rating/" "$K/defect.txt" > "$K/defect-rating.txt"
  expect_eq "K9: a finding-rating: of '$rating', which the table does not send to fix, is red" \
    "red: planted's finding-rating: '$rating' is not a rating the table sends to fix" "$(exam_key planted "$K/defect-rating.txt")"
done
for rating in 'S1 on' 'S1 off' 'S2 on' 'S1 on | S1 off | S2 on'; do
  sed "s/^finding-rating: .*/finding-rating: $rating/" "$K/defect.txt" > "$K/defect-rating.txt"
  expect_eq "K9: a finding-rating: of '$rating', each one the table sends to fix, is in shape" "key" "$(exam_key planted "$K/defect-rating.txt")"
done
sed 's/^finding-rating: .*/finding-rating: S2 on | S3 on/' "$K/defect.txt" > "$K/defect-rating.txt"
expect_eq "K9: one alternative the table defers makes the line red, and the red names it" \
  "red: planted's finding-rating: 'S3 on' is not a rating the table sends to fix" "$(exam_key planted "$K/defect-rating.txt")"
{ cat "$K/clean.txt"; printf 'finding-file: bin/some.sh\n'; } > "$K/clean-declared.txt"
expect_eq "K10: clean's key with a finding-file: line is red" \
  "red: clean's key has a finding- line, and clean has no defect to declare" "$(exam_key clean "$K/clean-declared.txt")"

section "§SCORE — README step 5 against the real keys"

# record <file> <question> <result line> <line>... — a planted reader's record on one question.
record() { local f="$1" q="$2"; shift 2; printf '%s\n' "reviewed: aaa..bbb" "question: $q" "$@" > "$f"; }
# frec <file> <question> <result> <S> <reach> <path> <line>... — a planted reader's record on one
# question that DECLARES one finding as a record writes it (wave-28 T18, D22): `findings: 1`, a
# `finding: 1 <S> <reach> <path>:7 <title>`, and a `shown: 1` line when the table sends it to fix
# (`proof_priority`). The lines after <path> are the record's other lines.
frec() {
  local f="$1" q="$2" res="$3" sev="${4:-}" reach="${5:-}" path="${6:-}"
  shift $(( $# < 6 ? $# : 6 ))
  {
    printf '%s\n' "reviewed: aaa..bbb" "question: $q" "result: $res" "findings: 1" "finding: 1 $sev $reach $path:7 the planted defect"
    [ "$(proof_priority "$sev" "$reach")" != fix ] || printf 'shown: 1 grep -n x %s\n' "$path"
    printf '%s\n' "$@"
  } > "$f"
}
R="$TMP/records"
mkdir -p "$R"
# score_act <score.sh> — what sourcing it does to a caller, as one line: `functions: <names>`
# when it defines functions and moves nothing else and prints nothing; otherwise the line names
# the first thing that moved, in this order: the working directory, the `$-` flags, the variable
# names, a variable's value or attributes (`declare -p`), the `set -o` and `shopt` options, the
# umask, the traps, the aliases; or it says the file ended the shell. The act is read from the
# caller's side, in a shell of its own, from a snapshot taken before sourcing and one after, so a
# file that exits or changes directory is caught by what the caller sees afterwards, not by what
# it prints. The probe's own variables and the shell's moving ones (`_`, `BASH*`, `SHELLOPTS`,
# `LINENO`, `RANDOM`, the clocks…) are left out of both snapshots. Each variable is read by its own
# `declare -p <name>`: a bare `declare -p` under bash 3.2 prints `name=value` with no attributes,
# so the skip list never matched there and the probe read `BASH_LINENO` as the file's act (T80).
score_act() {
  local out snapdir
  snapdir="$(mktemp -d "$TMP/act.XXXXXX")"
  out="$(cd "$TMP" && bash -c '
    d="$2" w=
    skip="_|BASH[A-Z_]*|SHELLOPTS|FUNCNAME|PIPESTATUS|LINENO|RANDOM|SRANDOM|SECONDS|EPOCHSECONDS|EPOCHREALTIME|d|w|skip|k"
    snap() {
      declare -F | sort > "$d/$1.functions"
      compgen -v | grep -vxE "$skip" | sort > "$d/$1.names"
      compgen -v | grep -vxE "$skip" | sort | while read -r k; do declare -p "$k"; done > "$d/$1.variables"
      { set -o; shopt; } > "$d/$1.options"
      umask > "$d/$1.umask"; trap -p > "$d/$1.traps"; alias > "$d/$1.aliases"
      printf "%s\n" "$-" > "$d/$1.flags"; pwd > "$d/$1.pwd"
    }
    snap before
    w="$(. "$1" 2>&1)"
    [ -z "$w" ] || { echo "printed: $w"; exit 0; }
    . "$1"
    snap after
    cmp -s "$d/before.pwd" "$d/after.pwd" || { echo "moved the working directory to $(cat "$d/after.pwd")"; exit 0; }
    cmp -s "$d/before.flags" "$d/after.flags" || { echo "changed the shell options from $(cat "$d/before.flags") to $(cat "$d/after.flags")"; exit 0; }
    cmp -s "$d/before.names" "$d/after.names" || { echo "defined variables: $(comm -13 "$d/before.names" "$d/after.names" | paste -sd" " -)"; exit 0; }
    for k in variables options umask traps aliases; do
      cmp -s "$d/before.$k" "$d/after.$k" && continue
      case "$k" in
        options) echo "changed the caller'"'"'s options: $(diff "$d/before.$k" "$d/after.$k" | sed -n "s/^> //p" | awk "NR == 1 { print \$1 }")" ;;
        *) echo "changed the caller'"'"'s $k: $(diff "$d/before.$k" "$d/after.$k" | sed -n "s/^> //p" | head -n 1)" ;;
      esac
      exit 0
    done
    echo "functions: $(comm -13 "$d/before.functions" "$d/after.functions" | sed "s/^declare -f //" | paste -sd" " -)"
  ' _ "$1" "$snapdir" 2>&1)"
  printf '%s\n' "${out:-ended the shell}"
}
expect_eq "SC0: sourcing score.sh defines its four functions and does nothing else" \
  "functions: exam_declared exam_field exam_meets exam_score" "$(score_act "$EXAM/score.sh")"
# The same probe against doctored copies of score.sh, each one appended act. A mutant's row
# reads its own verdict, beside the real file's `functions:` line above from the same probe.
SC0_MUT="$TMP/score-mutants"
mkdir -p "$SC0_MUT"
n=0
while IFS='|' read -r act want; do
  n=$((n + 1))
  cp "$EXAM/score.sh" "$SC0_MUT/m$n.sh"
  printf '%s\n' "$act" >> "$SC0_MUT/m$n.sh"
  expect_true "SC0 mutant '$act': the doctored copy still parses" bash -n "$SC0_MUT/m$n.sh"
  expect_ne "SC0 mutant '$act': the doctored copy differs from score.sh" "$(cat "$EXAM/score.sh")" "$(cat "$SC0_MUT/m$n.sh")"
  expect_contains "SC0 mutant '$act': sourcing it is read as an act" "$want" "$(score_act "$SC0_MUT/m$n.sh")"
done <<'ACTS'
exit 0|ended the shell
cd /|moved the working directory to /
set -e|changed the shell options from
EXAM_PROBE=1|defined variables: EXAM_PROBE
IFS=,|changed the caller's variables: declare -- IFS=","
set -o pipefail|changed the caller's options: pipefail
shopt -s nullglob|changed the caller's options: nullglob
umask 077|changed the caller's umask: 0077
trap : EXIT|changed the caller's traps: trap -- ':' EXIT
alias x=y|changed the caller's aliases: alias x='y'
export HOME=/x|changed the caller's variables: declare -x HOME="/x"
ACTS
DC="$EXAM/samples/dup-counter/expect.txt"
DC_NAMES="$(sed -n 's/^names: //p' "$DC")"
expect_nonempty "SC0: the dup-counter key has a names: identifier to score on" "$DC_NAMES"
frec "$R/one-site.md" structure fail S2 on bin/stamp.sh "check: reuse PASS a new file with a new job" \
  "check: one-site FAIL the dirty count is computed again, not read from $DC_NAMES"
expect_eq "SC1: dup-counter: check: one-site FAIL with the identifier, and a declared finding, is met" "met: declared" \
  "$(exam_score "$DC" "$R/one-site.md")"
frec "$R/reuse.md" structure fail S2 on bin/stamp.sh "check: reuse FAIL bin/stamp.sh counts dirt again beside $DC_NAMES"
expect_eq "SC1: dup-counter: check: reuse FAIL with the identifier, and a declared finding, is met" "met: declared" \
  "$(exam_score "$DC" "$R/reuse.md")"
frec "$R/one-site-bare.md" structure fail S2 on bin/stamp.sh "check: one-site FAIL a value is computed twice"
expect_eq "SC2: dup-counter: check: one-site FAIL without the identifier is missed" "missed" \
  "$(exam_score "$DC" "$R/one-site-bare.md")"
frec "$R/reuse-bare.md" structure fail S2 on bin/stamp.sh "check: reuse FAIL a helper is copied"
expect_eq "SC2: dup-counter: check: reuse FAIL without the identifier is missed" "missed" \
  "$(exam_score "$DC" "$R/reuse-bare.md")"
frec "$R/neither.md" structure fail S2 on bin/stamp.sh "check: single-job FAIL beside $DC_NAMES"
expect_eq "SC2: dup-counter: the identifier under another check is missed" "missed" \
  "$(exam_score "$DC" "$R/neither.md")"

# A caller's IFS is not the scorer's: a sitting sourced it from whatever shell it had, and a
# met record read as a miss because of the caller's separator is a reader failed for nothing.
# ifs_score <ifs> <key> <record> — exam_score run under that IFS, set before score.sh is sourced.
ifs_score() { bash -c 'IFS="$1"; . "$2"; exam_score "$3" "$4"' _ "$1" "$EXAM/score.sh" "$2" "$3"; }
ifs_rows() {
  local label="$1" ifs="$2"
  expect_eq "SC2b: under $label a met record is met" "met: declared" "$(ifs_score "$ifs" "$DC" "$R/one-site.md")"
  expect_eq "SC2b: under $label a missed record is missed" "missed" "$(ifs_score "$ifs" "$DC" "$R/one-site-bare.md")"
}
ifs_rows "the default IFS" "$(printf ' \t\n')"
ifs_rows "IFS=," ","
ifs_rows "IFS=:" ":"
ifs_rows "an empty IFS" ""

# Every defect key: its own question, result, first token and each names: alternative alone
# meet it; drop the identifier and the same record is missed; the same record on another
# question is missed.
for s in $(exam_samples "$REPO"); do
  [ "$s" = clean ] && continue
  key="$EXAM/samples/$s/expect.txt"
  q="$(sed -n 's/^question: //p' "$key")"
  idents="$(sed -n 's/^names: //p' "$key")"
  tok="$(sed -n 's/^token: //p' "$key")"; tok="${tok%% | *}"
  ff_all="$(sed -n 's/^finding-file: //p' "$key")"; ff="${ff_all%% | *}"
  fr="$(sed -n 's/^finding-rating: //p' "$key")"; fr="${fr%% | *}"
  # The file a record without the identifier declares on: the first file of the key whose own path
  # holds none of the identifiers (a path that holds one would name the defect by itself).
  ffb=""; fa="$ff_all"
  while [ -n "$fa" ]; do
    a="${fa%% | *}"; [ "$a" = "$fa" ] && fa="" || fa="${fa#* | }"
    hit=0; ia="$idents"
    while [ -n "$ia" ]; do
      i1="${ia%% | *}"; [ "$i1" = "$ia" ] && ia="" || ia="${ia#* | }"
      case "$a" in *"$i1"*) hit=1 ;; esac
    done
    [ "$hit" = 0 ] && [ -z "$ffb" ] && ffb="$a"
  done
  ffb="${ffb:-$ff}"
  n=0
  while [ -n "$idents" ]; do
    ident="${idents%% | *}"
    [ "$ident" = "$idents" ] && idents="" || idents="${idents#* | }"
    n=$((n + 1))
    # shellcheck disable=SC2086
    frec "$R/$s-named-$n.md" "$q" "$(sed -n 's/^result: //p' "$key")" $fr "$ff" "$tok" "$ident"
    expect_eq "SC3 $s: the key's question, result, token, names: '$ident' and a declared finding on $ff are met" "met: declared" "$(exam_score "$key" "$R/$s-named-$n.md")"
  done
  # shellcheck disable=SC2086
  frec "$R/$s-bare.md" "$q" "$(sed -n 's/^result: //p' "$key")" $fr "$ffb" "$tok"
  expect_eq "SC3 $s: the same record without the identifier is missed" "missed" "$(exam_score "$key" "$R/$s-bare.md")"
  # shellcheck disable=SC2086
  frec "$R/$s-elsewhere.md" "$([ "$q" = evidence ] && echo adversarial || echo evidence)" \
    "$(sed -n 's/^result: //p' "$key")" $fr "$ff" "$tok" "${ident:-}"
  expect_eq "SC3 $s: the named record on a question the key does not name is missed" "missed" \
    "$(exam_score "$key" "$R/$s-elsewhere.md")"
done

# D22 (wave-28 T18): a sample is passed only on a declared finding the priority table sends to
# fix, on the planted defect's file. The same record, one edit apart: declared and fix-grade is met;
# described in prose only, declared at a rating the table defers or notes, declared on another file,
# or declared with its lines refused is missed, and the line says which.
for s in $(exam_samples "$REPO"); do
  [ "$s" = clean ] && continue
  key="$EXAM/samples/$s/expect.txt"
  q="$(sed -n 's/^question: //p' "$key")"; res="$(sed -n 's/^result: //p' "$key")"
  tok="$(sed -n 's/^token: //p' "$key")"; tok="${tok%% | *}"
  ident="$(sed -n 's/^names: //p' "$key")"; ident="${ident%% | *}"
  ff="$(sed -n 's/^finding-file: //p' "$key")"; ff="${ff%% | *}"
  expect_nonempty "SD0 $s: the key names the file a finding must name" "$ff"
  fr_all="$(sed -n 's/^finding-rating: //p' "$key")"
  expect_nonempty "SD0 $s: the key names the ratings that pass it" "$fr_all"
  # every rating the key admits is met, each on the same record
  while [ -n "$fr_all" ]; do
    fr="${fr_all%% | *}"
    [ "$fr" = "$fr_all" ] && fr_all="" || fr_all="${fr_all#* | }"
    # shellcheck disable=SC2086
    frec "$R/$s-sd1.md" "$q" "$res" $fr "$ff" "$tok" "$ident"
    expect_eq "SD1 $s: a finding declared at $fr on $ff passes the sample" "met: declared" "$(exam_score "$key" "$R/$s-sd1.md")"
  done
  fr="${fr:-S2 on}"
  # the same record with its finding lines taken out: the defect is described, not declared
  grep -vE '^(findings|finding|shown):' "$R/$s-sd1.md" > "$R/$s-sd2.md"
  expect_true "SD2 $s: the described-only record still names the defect" grep -qF -- "$ident" "$R/$s-sd2.md"
  expect_true "SD2 $s: …and carries its result" grep -qx "result: $res" "$R/$s-sd2.md"
  expect_eq "SD2 $s: a record that only describes the defect fails, and the line says so" "missed: described only" \
    "$(exam_score "$key" "$R/$s-sd2.md")"
  { grep -vE '^(findings|finding|shown):' "$R/$s-sd1.md"; printf 'findings: 0\n'; } > "$R/$s-sd2b.md"
  expect_eq "SD2 $s: findings: 0 beside a description of the defect is described only too" "missed: described only" \
    "$(exam_score "$key" "$R/$s-sd2b.md")"
  # the table defers or notes the same finding at a lower rating
  for low in 'S2 off:deferred' 'S3 on:deferred' 'S3 off:noted' 'S4 on:noted' 'S4 off:noted'; do
    # shellcheck disable=SC2086
    frec "$R/$s-sd3.md" "$q" "$res" ${low%%:*} "$ff" "$tok" "$ident"
    expect_eq "SD3 $s: a declaration at ${low%%:*} on $ff is $([ "${low#*:}" = deferred ] && echo deferred || echo noted) by the table and fails" \
      "missed: declared at ${low%%:*}: ${low#*:}" "$(exam_score "$key" "$R/$s-sd3.md")"
  done
  # a finding on a file that is not the planted defect's
  # shellcheck disable=SC2086
  frec "$R/$s-sd4.md" "$q" "$res" S2 on docs/elsewhere.md "$tok" "$ident"
  expect_eq "SD4 $s: a fix-grade finding on another file fails, naming the file asked for" \
    "missed: no finding names $(sed -n 's/^finding-file: //p' "$key" | sed 's/ | / or /g')" "$(exam_score "$key" "$R/$s-sd4.md")"
  # a fix-grade finding with no command and no unsure: line is one the verb would refuse
  grep -v '^shown:' "$R/$s-sd1.md" > "$R/$s-sd5.md"
  expect_contains "SD5 $s: a fix-grade finding with no shown: or unsure: line fails as one the verb refuses" \
    "missed: finding lines refused: " "$(exam_score "$key" "$R/$s-sd5.md")"
  { cat "$R/$s-sd5.md"; printf 'unsure: 1 whether a user meets it\n'; } > "$R/$s-sd5b.md"
  expect_eq "SD5 $s: …and the same finding with an unsure: line is declared" "met: declared" "$(exam_score "$key" "$R/$s-sd5b.md")"
  # a pass the record's own result contradicts is still read on result: a declaration beside result: pass is missed
  # shellcheck disable=SC2086
  frec "$R/$s-sd6.md" "$q" pass S2 on "$ff" "$tok" "$ident"
  expect_eq "SD6 $s: a declared fix-grade finding beside result: pass is missed on the result" "missed" "$(exam_score "$key" "$R/$s-sd6.md")"
done

# The declaration is read by the registering verb's own reader (proof_findings): the verdict of a
# record the scorer calls declared is the reader's, never a second parse. A doctored copy of
# proof.sh that answers no findings turns every declaration into described only, and the real
# reader's answer on the same record is its own.
DCK="$EXAM/samples/dup-counter/expect.txt"
frec "$R/sd7-declared.md" structure fail S2 on bin/stamp.sh "check: reuse FAIL bin/stamp.sh counts dirt again beside $DC_NAMES"
grep -vE '^(findings|finding|shown):' "$R/sd7-declared.md" > "$R/sd7-described.md"
SD_REAL="$(proof_findings "$R/sd7-declared.md" 2>&1)"
expect_nonempty "SD7: the registering verb's reader answers a finding row for the declared record" "$SD_REAL"
expect_contains "SD7: …and its row is the one the scorer reads: finding 1, S2, on, bin/stamp.sh:7, fix" \
  "$(printf '1\tS2\ton\tbin/stamp.sh:7\tfix')" "$SD_REAL"
SD_MIRROR="$TMP/sd-mirror"
mkdir -p "$SD_MIRROR/tests/reader-exam" "$SD_MIRROR/payload/scripts/lib"
cp "$EXAM/score.sh" "$SD_MIRROR/tests/reader-exam/score.sh"
cp "$REPO/payload/scripts/lib/proof.sh" "$SD_MIRROR/payload/scripts/lib/proof.sh"
expect_eq "SD7: a byte copy of score.sh and proof.sh in a mirrored tree scores the record as the real one does" \
  "$(exam_score "$DCK" "$R/sd7-declared.md")" \
  "$(bash -c '. "$1"; exam_score "$2" "$3"' _ "$SD_MIRROR/tests/reader-exam/score.sh" "$DCK" "$R/sd7-declared.md")"
printf '%s\n' 'proof_findings() { return 0; }' >> "$SD_MIRROR/payload/scripts/lib/proof.sh"
expect_eq "SD7: with the reader doctored to answer no findings, the same record is described only (the scorer asks the reader)" \
  "missed: described only" \
  "$(bash -c '. "$1"; exam_score "$2" "$3"' _ "$SD_MIRROR/tests/reader-exam/score.sh" "$DCK" "$R/sd7-declared.md")"
expect_eq "SD7: …and the real tree's answer on the record is unchanged" "met: declared" \
  "$(exam_score "$DCK" "$R/sd7-declared.md")"

# MUTATION ARM: a score.sh that restores the described-only pass. The doctored copy's declaration
# check says `declared` whatever the record holds; the row first proves the mutant still runs
# (a fix-grade record is met), then reads the absence: the described-only record the real scorer
# fails is met by the mutant, and the same record is missed by the real one.
SD_MUT="$TMP/sd-mutant"
mkdir -p "$SD_MUT/tests/reader-exam" "$SD_MUT/payload/scripts/lib"
cp "$REPO/payload/scripts/lib/proof.sh" "$SD_MUT/payload/scripts/lib/proof.sh"
sed 's/^exam_declared() {$/exam_declared() { echo declared; return 0/' "$EXAM/score.sh" > "$SD_MUT/tests/reader-exam/score.sh"
expect_ne "SD8: the doctored scorer differs from score.sh" "$(cat "$EXAM/score.sh")" "$(cat "$SD_MUT/tests/reader-exam/score.sh")"
expect_true "SD8: …and still parses" bash -n "$SD_MUT/tests/reader-exam/score.sh"
sd_mut() { bash -c '. "$1"; exam_score "$2" "$3"' _ "$SD_MUT/tests/reader-exam/score.sh" "$1" "$2"; }
expect_eq "SD8: the mutant still runs: a declared record is met by it" "met: declared" \
  "$(sd_mut "$DCK" "$R/sd7-declared.md")"
expect_eq "SD8: the mutant restores the described-only pass: the record that only describes the defect is met" "met: declared" \
  "$(sd_mut "$DCK" "$R/sd7-described.md")"
expect_eq "SD8: …which the real scorer fails on the same record" "missed: described only" \
  "$(exam_score "$DCK" "$R/sd7-described.md")"

CL="$EXAM/samples/clean/expect.txt"
CL_TOK="$(sed -n 's/^token: //p' "$CL")"
record "$R/clean-flag.md" evidence "result: flag" "read $CL_TOK"
expect_eq "SC4: clean: a flag that names the change is met, with no names: line asked" "met" \
  "$(exam_score "$CL" "$R/clean-flag.md")"
record "$R/clean-fail.md" structure "result: fail" "read $CL_TOK"
expect_eq "SC4: clean: a fail is missed" "missed" "$(exam_score "$CL" "$R/clean-fail.md")"

# Review pass 18, finding 1: the one-mind critic's three passes. Its two planted records,
# copied. The structure pass is scored, at the structure path or inside the one file, never
# whichever pass comes first.
cat > "$R/onemind-found.md" <<'R'
reviewed: a..b
question: evidence
result: flag
scope: piece
UNVERIFIABLE: revert-and-watch needs a test-runner

reviewed: a..b
question: adversarial
result: pass
scope: piece

reviewed: a..b
question: structure
result: fail
scope: piece
findings: 1
finding: 1 S2 on bin/stamp.sh:9 the stamp counts dirt its own way, and counts .trellis/
shown: 1 grep -n porcelain bin/stamp.sh
check: one-site FAIL bin/stamp.sh:9 counts dirt with git status --porcelain | wc -l; the owner is lib/tree.sh tree_dirty_count, which excludes .trellis/
R
cat > "$R/onemind-passed.md" <<'R'
reviewed: a..b
question: adversarial
result: fail
scope: piece
bin/stamp.sh:8 stamps the head before an uncommitted tree; quoted from the design: "check: reuse FAIL" is what the structure reader would write if lib/tree.sh tree_dirty_count were copied

reviewed: a..b
question: structure
result: pass
scope: piece
check: reuse PASS a new file with a new job
check: one-site PASS
R
# one_pass <file> <question> <out> — that question's pass alone, as a record per question.
one_pass() { awk -v q="$2" '/^reviewed:/ { on = 0 } /^reviewed:/ { buf = $0; next } $0 == "question: " q { on = 1; print buf } on' "$1" > "$3"; }
one_pass "$R/onemind-found.md" structure "$R/found-structure.md"
one_pass "$R/onemind-found.md" adversarial "$R/found-adversarial.md"
one_pass "$R/onemind-passed.md" structure "$R/passed-structure.md"
one_pass "$R/onemind-passed.md" adversarial "$R/passed-adversarial.md"
expect_eq "SC5: the split holds the found critic's structure FAIL" "result: fail" "$(grep '^result:' "$R/found-structure.md")"
expect_eq "SC5: the split holds the passing critic's adversarial fail" "result: fail" "$(grep '^result:' "$R/passed-adversarial.md")"
expect_eq "SC5: the critic that found the defect, at its structure path, is met" "met: declared" \
  "$(exam_score "$DC" "$R/found-structure.md")"
expect_eq "SC5: …and its adversarial record, which passed, is not what the structure key reads" "missed" \
  "$(exam_score "$DC" "$R/found-adversarial.md")"
expect_eq "SC5: the critic that passed the structure question is missed, with no finding declared" "missed: described only" \
  "$(exam_score "$DC" "$R/passed-structure.md")"
expect_eq "SC5: the one file of three passes is scored on its structure pass: found, met" "met: declared" \
  "$(exam_score "$DC" "$R/onemind-found.md")"
expect_eq "SC5: the one file of three passes is scored on its structure pass: passed, missed though another pass fails" "missed: described only" \
  "$(exam_score "$DC" "$R/onemind-passed.md")"

# admit-not-require: the owner the land bypasses names the defect; the criterion's own word
# does not. A finding may name either file the key lists (bin/land.sh, lib/fullrun.sh).
AN="$EXAM/samples/admit-not-require/expect.txt"
frec "$R/adm-found.md" evidence fail S2 on lib/fullrun.sh \
  "AC-1.1: REFUTED. The criterion requires a full run before the land; D1 and the test only show the full run is admitted, and bin/land.sh never asks for one."
expect_eq "SC6: admit-not-require: requires, with land.sh, is met" "met: declared" "$(exam_score "$AN" "$R/adm-found.md")"
frec "$R/adm-found-land.md" evidence fail S2 on bin/land.sh \
  "AC-1.1: REFUTED. The criterion requires a full run before the land; D1 and the test only show the full run is admitted."
expect_eq "SC6: admit-not-require: a finding on bin/land.sh is met" "met: declared" "$(exam_score "$AN" "$R/adm-found-land.md")"
frec "$R/adm-unnamed.md" evidence fail S2 on lib/fullrun.sh \
  "AC-1.1: REFUTED. The criterion requires a full run before the change lands; D1 and the test only show the full run is admitted."
expect_eq "SC6: admit-not-require: requires, without land.sh, is missed" "missed" "$(exam_score "$AN" "$R/adm-unnamed.md")"
frec "$R/adm-quoted.md" evidence fail S2 on lib/fullrun.sh \
  "AC-1.1 (\"When a changed file is read by no suite, a full run is required before the change lands\"): REFUTED. The T1 record's evidence is tier T2 but carries no fixture-fidelity declaration."
expect_eq "SC6: admit-not-require: a record that quotes the criterion and fails it for another reason is missed" "missed" \
  "$(exam_score "$AN" "$R/adm-quoted.md")"

# red-then-green: the spellings a finder writes.
RG="$EXAM/samples/red-then-green/expect.txt"
for sp in 'tail -n1' 'tail -1'; do
  frec "$R/rtg.md" adversarial fail S2 on lib/landcheck.sh \
    "lib/landcheck.sh:10 land_check reads only the last stamp line ($sp); a red suite stamped before a green one at the same head lands."
  expect_eq "SC7: red-then-green: a finder who writes '$sp' is met" "met: declared" "$(exam_score "$RG" "$R/rtg.md")"
done
frec "$R/rtg-two.md" adversarial fail S2 on lib/landcheck.sh "lib/landcheck.sh:10 land_check should read tail -n 2 instead"
expect_eq "SC7: red-then-green: 'tail -n 2' is missed" "missed" "$(exam_score "$RG" "$R/rtg-two.md")"

# A line end of CR LF, and white space after a value, are not a miss.
printf 'reviewed: a..b\r\nquestion: structure\r\nresult: fail\r\nscope: piece\r\nfindings: 1\r\nfinding: 1 S2 on bin/stamp.sh:9 counts dirt again\r\nshown: 1 grep -n porcelain bin/stamp.sh\r\ncheck: reuse FAIL bin/stamp.sh counts again beside tree_dirty_count\r\n' > "$R/crlf.md"
expect_eq "SC8: a correct record with CR LF line ends is met" "met: declared" "$(exam_score "$DC" "$R/crlf.md")"
printf 'reviewed: a..b\nquestion: structure \nresult: fail \nscope: piece\nfindings: 1\nfinding: 1 S2 on bin/stamp.sh:9 counts dirt again\nshown: 1 grep -n porcelain bin/stamp.sh\ncheck: reuse FAIL beside tree_dirty_count\n' > "$R/trail.md"
expect_eq "SC8: a correct record with a space after its question and result is met" "met: declared" "$(exam_score "$DC" "$R/trail.md")"
printf 'reviewed: a..b\r\nquestion: structure\r\nresult: pass \r\nscope: piece\r\nfindings: 1\r\nfinding: 1 S2 on bin/stamp.sh:9 counts dirt again\r\nshown: 1 grep -n porcelain bin/stamp.sh\r\ncheck: reuse FAIL beside tree_dirty_count\r\n' > "$R/crlf-pass.md"
expect_eq "SC8: the same line ends on a record that passed are still missed" "missed" "$(exam_score "$DC" "$R/crlf-pass.md")"

section "§DEST — a destination that names its sample is refused"

DS="$EXAM/samples/dup-counter"
out="$(bash "$EXAM/materialize.sh" "$DS" "$TMP/x/dup-counter-run" 2>&1)"; rc=$?
expect_status "D1: a destination named for the sample is refused" 2 "$rc"
expect_contains "D1: …and says why" "names the sample dup-counter" "$out"
expect_false "D1: …and nothing is built" test -e "$TMP/x/dup-counter-run"
out="$(bash "$EXAM/materialize.sh" "$DS" "$TMP/dup-counter/s1" 2>&1)"; rc=$?
expect_status "D2: a destination under a directory named for the sample is refused" 2 "$rc"
expect_contains "D2: …and says why" "names the sample dup-counter" "$out"
mkdir -p "$TMP/in-dup-counter"
out="$(cd "$TMP/in-dup-counter" && bash "$EXAM/materialize.sh" "$DS" s1 2>&1)"; rc=$?
expect_status "D3: a relative destination is read from where it is run, and refused there" 2 "$rc"
expect_false "D3: …and nothing is built" test -e "$TMP/in-dup-counter/s1"
out="$(bash "$EXAM/materialize.sh" "$DS" "$TMP/x/s1" 2>&1)"; rc=$?
expect_status "D4: a neutral destination is accepted" 0 "$rc"
expect_regex "D4: …and prints its range" '^[0-9a-f]{40}\.\.[0-9a-f]{40}$' "$out"
out="$(bash "$EXAM/materialize.sh" "$DS" "$TMP/x/DUP-COUNTER-1" 2>&1)"; rc=$?
expect_status "D5: a destination naming the sample in upper case is refused" 2 "$rc"
expect_contains "D5: …and says why" "names the sample dup-counter" "$out"
expect_false "D5: …and nothing is built" test -e "$TMP/x/DUP-COUNTER-1"
mkdir -p "$TMP/Dup-Counter-real"
ln -s "$TMP/Dup-Counter-real" "$TMP/plain-link"
out="$(bash "$EXAM/materialize.sh" "$DS" "$TMP/plain-link/s1" 2>&1)"; rc=$?
expect_status "D6: a neutral symlink whose real path names the sample is refused" 2 "$rc"
expect_contains "D6: …and says why" "names the sample dup-counter" "$out"
expect_false "D6: …and nothing is built" test -e "$TMP/Dup-Counter-real/s1"
mkdir -p "$TMP/plain-real"
ln -s "$TMP/plain-real" "$TMP/plain-link-2"
out="$(bash "$EXAM/materialize.sh" "$DS" "$TMP/plain-link-2/s1" 2>&1)"; rc=$?
expect_status "D6: a neutral symlink into a neutral directory is accepted" 0 "$rc"

section "§SAMPLES — every answer key in shape, every sample materializes"

SAMPLES="$(exam_samples "$REPO")"
expect_nonempty "S0: the exam has samples" "$SAMPLES"
expect_true "S0: one of them is the clean sample" test -d "$EXAM/samples/clean"

n=0
for s in $SAMPLES; do
  n=$((n + 1))
  key="$EXAM/samples/$s/expect.txt"
  expect_eq "S1 $s: the answer key is in shape" "key" "$(exam_key "$s" "$key")"
  out="$(bash "$EXAM/materialize.sh" "$EXAM/samples/$s" "$TMP/m$n" 2>&1)"; rc=$?
  expect_status "S2 $s: materializes" 0 "$rc"
  expect_regex "S2 $s: prints the range a..b" '^[0-9a-f]{40}\.\.[0-9a-f]{40}$' "$out"
  expect_eq "S2 $s: the range is the two commits the repository holds" \
    "$out" "$(git -C "$TMP/m$n" rev-parse HEAD~1 2>/dev/null)..$(git -C "$TMP/m$n" rev-parse HEAD 2>/dev/null)"
  expect_nonempty "S2 $s: the change commit changes files" "$(git -C "$TMP/m$n" diff --name-only HEAD~1 HEAD 2>/dev/null)"
  # D22 (wave-28 T18): the file a finding must name is a file the built sample holds at its head.
  ffs="$(sed -n 's/^finding-file: //p' "$key")"
  [ "$s" = clean ] || expect_nonempty "S5 $s: the key names a file for a finding" "$ffs"
  while [ -n "$ffs" ]; do
    ff="${ffs%% | *}"
    [ "$ff" = "$ffs" ] && ffs="" || ffs="${ffs#* | }"
    expect_true "S5 $s: finding-file '$ff' is a file the built sample holds at its head" git -C "$TMP/m$n" cat-file -e "HEAD:$ff"
  done
  expect_false "S2 $s: the answer key does not travel" test -e "$TMP/m$n/expect.txt"
  expect_true "S3 $s: the built sample carries its own .bionic/ root" test -d "$TMP/m$n/.bionic"
  # git does not list an empty directory, so the exclude line is only read once a record is
  # written under .bionic/, as a reader's records are (README step 4).
  mkdir -p "$TMP/m$n/.bionic/docs/record/w" && printf 'a reader record\n' > "$TMP/m$n/.bionic/docs/record/w/s1-one-mind-structure.md"
  expect_true "S3 $s: a record is written under .bionic/" test -s "$TMP/m$n/.bionic/docs/record/w/s1-one-mind-structure.md"
  expect_empty "S3 $s: …and git sees nothing to commit beside the change" \
    "$(git -C "$TMP/m$n" status --porcelain 2>&1)"
done

# The same reading on a materialize.sh with its exclude line removed: the record shows in the
# status. The built repository is otherwise the clean sample's, built by the same script.
anchor "$EXAM/materialize.sh" ".git/info/exclude" 1
sed 's| && printf .*/exclude"||' "$EXAM/materialize.sh" > "$TMP/materialize-noexclude.sh"
expect_eq "S3: the doctored materialize.sh no longer writes the exclude" "0" \
  "$(grep -c 'info/exclude' "$TMP/materialize-noexclude.sh")"
out="$(bash "$TMP/materialize-noexclude.sh" "$EXAM/samples/clean" "$TMP/mx" 2>&1)"; rc=$?
expect_status "S3: the doctored materialize.sh still builds" 0 "$rc"
expect_regex "S3: …and prints its range" '^[0-9a-f]{40}\.\.[0-9a-f]{40}$' "$out"
mkdir -p "$TMP/mx/.bionic/docs/record/w" && printf 'a reader record\n' > "$TMP/mx/.bionic/docs/record/w/s1-one-mind-structure.md"
expect_contains "S3: without its exclude line, a record under .bionic/ shows in git status" ".bionic/" \
  "$(git -C "$TMP/mx" status --porcelain 2>&1)"

# A record path is what a reader is handed: it names the built sample by its neutral label,
# never by the sample's name (A-orch-73).
NAMED_PATH_PROBE="$TMP/named-path-readme.md"
sed 's|/s1-one-mind-|/red-then-green-one-mind-|' "$EXAM/README.md" > "$NAMED_PATH_PROBE"
expect_nonempty "S4: the README gives record-path examples to check" "$(exam_record_paths "$EXAM/README.md")"
expect_empty "S4: no record-path line of the README holds a sample's name" \
  "$(exam_named_path "$EXAM/README.md" "$REPO")"
expect_contains "S4: a README whose record-path example holds a sample's name is red and shows the line" \
  "red-then-green-one-mind-" "$(exam_named_path "$NAMED_PATH_PROBE" "$REPO")"
expect_contains "S4: …in any case" "RED-THEN-GREEN-one-mind-" \
  "$(sed 's|red-then-green-one-mind-|RED-THEN-GREEN-one-mind-|' "$NAMED_PATH_PROBE" > "$NAMED_PATH_PROBE.upper"; exam_named_path "$NAMED_PATH_PROBE.upper" "$REPO")"

section "§RECIPE — a sitting can be repeated from the tree"

# README step 3 gives the rule that finds a session's transcripts: the physical working directory
# with every character that is not an ASCII letter or digit written `-`. The row takes the rule
# from the README's own text and applies it to a made-up path holding `_`, `.` and a space.
RULE_CMD="$(grep -o "sed '[^']*'" "$EXAM/README.md" | head -n 1)"
RULE="${RULE_CMD#sed \'}"; RULE="${RULE%\'}"
expect_nonempty "R1: the README carries the transcript directory rule as a sed command" "$RULE"
expect_contains "R1: …and says it is read from the physical working directory" "pwd -P" "$(cat "$EXAM/README.md")"
expect_eq "R1: the rule writes a path holding _, . and a space as the harness's directory name" \
  "-tmp-x-y-a-b-c-s1" "$(printf '%s' '/tmp/x_y/a.b c/s1' | sed "$RULE")"
expect_eq "R1: …and the README's own worked path as the name it gives" \
  "-private-var-folders-x-y-T-tmp-AbC-s1" "$(printf '%s' '/private/var/folders/x_y/T/tmp.AbC/s1' | sed "$RULE")"
expect_contains "R1: …which the README writes out" "-private-var-folders-x-y-T-tmp-AbC-s1" "$(cat "$EXAM/README.md")"

RUN="$EXAM/run-session.sh"
GEN="$EXAM/gen-prompt.sh"
for h in "$RUN" "$GEN"; do
  expect_true "R2: ${h##*/} is executable" test -x "$h"
  expect_true "R2: ${h##*/} parses" bash -n "$h"
done

# The README's step 3 names both helpers and keeps the interactive command beside them.
STEP3="$(awk '/^3\. \*\*Open an engaged session/ { f = 1 } /^4\. \*\*Dispatch the readers/ { f = 0 } f' "$EXAM/README.md")"
expect_contains "R3: step 3 names run-session.sh" "tests/reader-exam/run-session.sh" "$STEP3"
expect_contains "R3: step 3 names gen-prompt.sh" "tests/reader-exam/gen-prompt.sh" "$STEP3"
expect_contains "R3: step 3 keeps the interactive command" 'claude --plugin-dir' "$STEP3"

# run-session.sh adds no flag that widens what a session may do. The file is read for the flags
# it does pass, then for the ones it must not.
RUN_TEXT="$(cat "$RUN")"
expect_contains "R4: run-session.sh passes -p" '"$claude_bin" -p --plugin-dir "$plugin" --output-format json' "$RUN_TEXT"
expect_empty "R4: …and no permission, settings, directory or tool flag" \
  "$(grep -nE -- '--(dangerously|allow|permission|settings|setting-sources|add-dir|tools|disallowed|mcp-config|bare)' "$RUN")"
expect_contains "R4: a denied tool is reported to the user and not worked round, in its header" "reported to the user" "$RUN_TEXT"
expect_contains "R4: …and never worked round" "never worked round" "$RUN_TEXT"

# Run against a fake CLI binary on PATH, with a shell function of the same name exported beside it
# and the parent session's variables set: what the fake sees is what a real session would.
RV="$TMP/recipe"
mkdir -p "$RV/bin" "$RV/dest" "$RV/plugin/context"
for f in checks-evidence checks-adversarial checks-structure severity; do printf 'text of %s\n' "$f" > "$RV/plugin/context/$f.md"; done
cat > "$RV/bin/claude" <<'FAKE'
#!/bin/bash
{
  printf 'argv:'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'
  printf 'cwd: %s\n' "$(pwd -P)"
  env | grep -E '^(CLAUDECODE|CLAUDE_[A-Z_]*)=' | sort
} > "$FAKE_LOG"
echo '{"session_id":"fake"}'
echo "fake stderr" >&2
FAKE
chmod +x "$RV/bin/claude"
printf 'a prompt with "quotes", a $dollar and\ntwo lines\n' > "$RV/prompt.txt"
PARENT_VARS="CLAUDECODE CLAUDE_CODE_SESSION_ID CLAUDE_CODE_BRIDGE_SESSION_ID CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_SESSION_ATTENDED CLAUDE_PID CLAUDE_PLUGIN_DATA CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH CLAUDE_EFFORT"
parent_env=""
for v in $PARENT_VARS; do parent_env="$parent_env $v=parent-$v"; done
# shellcheck disable=SC2086
out="$(cd "$TMP" && env $parent_env CLAUDE_CONFIG_DIR=/kept/config FAKE_LOG="$RV/fake.log" PATH="$RV/bin:/usr/bin:/bin" \
  bash -c 'claude() { echo FUNCTION > "$FAKE_LOG.function"; }; export -f claude; exec bash "$0" "$@"' \
  "$RUN" "$RV/dest" "$RV/plugin" "$RV/prompt.txt" "$RV/out.json" 2>&1)"; rc=$?
expect_status "R5: run-session.sh exits with the CLI's status" 0 "$rc"
expect_contains "R5: the fake CLI saw the call" "argv:" "$(cat "$RV/fake.log" 2>/dev/null)"
expect_eq "R5: it runs the CLI binary, and the shell function of the same name never ran" "no" \
  "$([ -e "$RV/fake.log.function" ] && echo yes || echo no)"
expect_eq "R5: it passes -p, --plugin-dir (resolved, physical), --output-format json and the prompt, and nothing else" \
  "argv: [-p] [--plugin-dir] [$(cd "$RV/plugin" && pwd -P)] [--output-format] [json] [a prompt with \"quotes\", a \$dollar and
two lines]" "$(sed -n '1,2p' "$RV/fake.log")"
expect_eq "R5: it runs in the built project's physical directory" "cwd: $(cd "$RV/dest" && pwd -P)" "$(sed -n '3p' "$RV/fake.log")"
for v in $PARENT_VARS; do
  expect_empty "R5: the parent's $v is not handed down" "$(grep "^$v=" "$RV/fake.log")"
  expect_contains "R6: run-session.sh names $v in a comment" "$v" "$(grep '^#' "$RUN" | grep -w "$v")"
done
expect_eq "R5: …while the config directory is left as it was" "CLAUDE_CONFIG_DIR=/kept/config" "$(grep '^CLAUDE_CONFIG_DIR=' "$RV/fake.log")"
expect_eq "R5: the session's result lands in <output file>" '{"session_id":"fake"}' "$(cat "$RV/out.json")"
expect_eq "R5: …its stderr in <output file>.err" "fake stderr" "$(cat "$RV/out.json.err")"
expect_regex "R5: …and its times in <output file>.time" '^end=.* rc=0$' "$(tail -n 1 "$RV/out.json.time")"
bash "$RUN" "$RV/dest" "$RV/missing-plugin" "$RV/prompt.txt" "$RV/out2.json" > /dev/null 2>&1; rc=$?
expect_status "R5: a missing plugin copy is refused with status 2" 2 "$rc"
expect_false "R5: …and nothing is written" test -e "$RV/out2.json"

# gen-prompt.sh: a prompt for made-up briefs. Its words are the instruction's own; what a brief
# says is the brief's.
printf 'subagent_type: bionic:critic\nQuestions: structure\nFiles: /tmp/q/s1/.bionic/docs/record/w/s1-critic-structure.md\n\nRead /tmp/q/s1 over a..b.\n' > "$RV/brief-1.txt"
printf 'subagent_type: bionic:reviewer\nQuestions: evidence\nFiles: /tmp/q/s1/.bionic/docs/record/w/s1-reviewer-evidence.md\nno final newline' > "$RV/brief-2.txt"
PLUGIN="$RV/plugin" bash "$GEN" "$RV/brief-1.txt" "$RV/brief-2.txt" > "$RV/prompt-1.txt"; rc=$?
P="$(cat "$RV/prompt-1.txt")"
expect_status "R7: gen-prompt.sh writes a prompt for two briefs" 0 "$rc"
expect_eq "R7: the prompt opens with /bionic:canonical-sdlc" "/bionic:canonical-sdlc" "$(head -n 1 "$RV/prompt-1.txt" | cut -d ' ' -f 1)"
expect_contains "R7: each brief goes to the agent type its first line names" "=== Brief 1 — subagent_type: bionic:critic ===" "$P"
expect_contains "R7: …the second to its own" "=== Brief 2 — subagent_type: bionic:reviewer ===" "$P"
# read_block <plugin copy> <question>... — the lines gen-prompt.sh ends a brief with (wave-28 T18,
# D22): the files the recorder pushes a reader, by path in the plugin copy and never pasted: its
# checks file for each question it is dealt, in the order evidence, adversarial, structure, then the
# severity scale.
read_block() {
  local plug="$1" q; shift
  printf '\nRead each of these files in full before you start; the plugin ships them and they bind this review:\n'
  for q in evidence adversarial structure; do
    case " $* " in *" $q "*) printf '%s/context/checks-%s.md\n' "$plug" "$q" ;; esac
  done
  printf '%s/context/severity.md\n' "$plug"
}
for n in 1 2; do
  case "$n" in 1) rq=structure ;; 2) rq=evidence ;; esac
  expect_eq "R7: brief $n is dispatched as written, its first line left off, and ends with the files it is to read" \
    "$(tail -n +2 "$RV/brief-$n.txt"; [ -z "$(tail -c 1 "$RV/brief-$n.txt")" ] || echo; read_block "$RV/plugin" "$rq")" \
    "$(awk -v n="$n" '$0 ~ "^=== Brief " n " " { f = 1; next } f && $0 == "END" { exit } f && $0 != "BEGIN" { print }' "$RV/prompt-1.txt")"
done
expect_contains "R7: the briefs given to one call go together, in one message" "together, in one message" "$P"
expect_absent "R7: …and never one after another, which lets the second reader read the first's record" "after another" "$P"
printf 'subagent_type: bionic:auditor\nQuestions: evidence\nFiles: /tmp/q/s1/.bionic/docs/record/w/s1-auditor-evidence.md\n' > "$RV/brief-3.txt"
P3="$(PLUGIN="$RV/plugin" bash "$GEN" "$RV/brief-1.txt" "$RV/brief-2.txt" "$RV/brief-3.txt")"
expect_contains "R7: three briefs are told to go together, in one message" "Dispatch the 3 briefs below together, in one message" "$P3"
expect_contains "R7: …each under its own agent type" "=== Brief 3 — subagent_type: bionic:auditor ===" "$P3"
P1="$(PLUGIN="$RV/plugin" bash "$GEN" "$RV/brief-1.txt")"
expect_contains "R7: one brief is one dispatch" "Dispatch the brief below." "$P1"
expect_absent "R7: …with no word of a message of several" "together" "$P1"
expect_contains "R7: …not in the background" "do not run it in the background" "$P"
expect_contains "R7: a refusal stops the session and is never retried" "do not try again" "$P"
expect_contains "R7: a record a reader returned is saved unchanged at the path its brief names" "save the record exactly as the reader returned it at that path" "$P"
expect_contains "R7: the session replies with each record's path and whether it exists" "whether that file exists" "$P"
expect_contains "R7: TOGETHER is not a switch: set to 0 it changes nothing" "together, in one message" \
  "$(PLUGIN="$RV/plugin" TOGETHER=0 bash "$GEN" "$RV/brief-1.txt" "$RV/brief-2.txt")"
expect_contains "R7: STEP_ZERO=1 adds the description quote" "quoting each one's description exactly" \
  "$(PLUGIN="$RV/plugin" STEP_ZERO=1 bash "$GEN" "$RV/brief-1.txt")"
printf 'bionic:critic\nQuestions: structure\n' > "$RV/brief-bad.txt"
out="$(PLUGIN="$RV/plugin" bash "$GEN" "$RV/brief-bad.txt" 2>/dev/null)"; rc=$?
expect_status "R7: a brief with no agent type on its first line is refused" 2 "$rc"
expect_empty "R7: …and no prompt is written" "$out"

# Nothing in either helper, or in a prompt it writes, names a sample or says what the sitting is.
# The grep is proved live on a brief that does name a sample, through the same extractor.
SAMPLE_NAMES="$(exam_samples "$REPO" | paste -sd'|' -)"
expect_nonempty "R8: the real samples are listed" "$SAMPLE_NAMES"
NAMED_RE="exam|sample|planted|defect|key|$SAMPLE_NAMES"
printf 'subagent_type: bionic:critic\nQuestions: structure\nRead the dup-counter sample.\n' > "$RV/brief-named.txt"
# The plugin copy's path is the caller's own and may hold any word (this suite's is under a
# directory named for the suite), so it is taken out of the prompt before the words are read.
expect_nonempty "R8: the extractor finds a sample's name in a prompt written for a brief that holds one" \
  "$(PLUGIN="$RV/plugin" bash "$GEN" "$RV/brief-named.txt" | sed "s|$RV/plugin||g" | grep -ioE "$NAMED_RE")"
expect_empty "R8: the prompt for made-up briefs holds none of the sample names, nor exam, sample, planted, defect or key" \
  "$(sed "s|$RV/plugin||g" "$RV/prompt-1.txt" | grep -ioE "$NAMED_RE")"
for h in "$RUN" "$GEN"; do
  expect_nonempty "R8: ${h##*/} is read" "$(head -n 1 "$h")"
  expect_empty "R8: ${h##*/} holds none of them either" "$(grep -inE "$NAMED_RE" "$h")"
done


# D22 (wave-28 T18): a reader is given the scale's file as shipped, by path, and the checks file
# of each question it is dealt: the files the recorder pushes (`start_pushed`, hooks/execution-recorder.sh),
# named from the plugin copy of README step 1 and never pasted into the prompt. Every reader of a
# defect sample is asked for finding lines, so the evidence reader is given the scale too.
printf 'subagent_type: bionic:critic\nQuestions: evidence, adversarial, structure\nFiles: /tmp/q/s2/r.md\n\nRead /tmp/q/s2.\n' > "$RV/brief-one-mind.txt"
printf 'subagent_type: bionic:auditor\nQuestions: evidence\nFiles: /tmp/q/s3/r.md\n\nRead /tmp/q/s3.\n' > "$RV/brief-auditor.txt"
P9="$(PLUGIN="$REPO/payload" bash "$GEN" "$RV/brief-one-mind.txt")"
expect_contains "R9: a reader is given the scale's file as shipped, by its path at the head" "$REPO/payload/context/severity.md" "$P9"
expect_true "R9: …the path names a file that exists" test -s "$REPO/payload/context/severity.md"
expect_eq "R9: …once per reader" "1" "$(printf '%s\n' "$P9" | grep -c "/context/severity.md")"
SEV_LINE="Severity says how bad a finding is if a user meets it"
expect_true "R9: the sentence looked for is one the shipped scale holds" grep -qF -- "$SEV_LINE" "$REPO/payload/context/severity.md"
expect_absent "R9: the scale's text is not pasted into the prompt" "$SEV_LINE" "$P9"
for q in evidence adversarial structure; do
  expect_contains "R9: the one-mind critic is given checks-$q.md of the plugin copy" "$REPO/payload/context/checks-$q.md" "$P9"
done
P9="$(PLUGIN="$RV/plugin" bash "$GEN" "$RV/brief-auditor.txt")"
expect_contains "R9: an auditor dealt evidence is given checks-evidence.md" "$RV/plugin/context/checks-evidence.md" "$P9"
expect_absent "R9: …and no checks file of a question it is not dealt" "checks-adversarial.md" "$P9"
expect_absent "R9: …nor checks-structure.md" "checks-structure.md" "$P9"
expect_contains "R9: …and, asked for finding lines like every reader, the scale" "$RV/plugin/context/severity.md" "$P9"
P9="$(PLUGIN="$RV/plugin" bash "$GEN" "$RV/brief-1.txt" "$RV/brief-auditor.txt")"
expect_eq "R9: two briefs, two scale lines: each reader is given its own" "2" "$(printf '%s\n' "$P9" | grep -c "/context/severity.md")"
r9() { local out; out="$("$@" 2>&1 >/dev/null)"; echo "rc=$? ${out%%$'\n'*}"; }
expect_eq "R9: with PLUGIN unset, gen-prompt.sh refuses and says why" \
  "rc=2 gen-prompt.sh: PLUGIN is not set; give the plugin copy of README step 1 as PLUGIN=<dir>" \
  "$(r9 env -u PLUGIN bash "$GEN" "$RV/brief-1.txt")"
expect_eq "R9: a PLUGIN that is a relative path is refused" \
  "rc=2 gen-prompt.sh: PLUGIN=plugin is not an absolute path" "$(r9 env PLUGIN=plugin bash "$GEN" "$RV/brief-1.txt")"
mkdir -p "$RV/plugin-noscale/context"
printf 'x\n' > "$RV/plugin-noscale/context/checks-structure.md"
expect_eq "R9: a plugin copy with no severity scale is refused, naming the file" \
  "rc=2 gen-prompt.sh: $RV/plugin-noscale/context/severity.md cannot be read" "$(r9 env PLUGIN="$RV/plugin-noscale" bash "$GEN" "$RV/brief-1.txt")"
mkdir -p "$RV/plugin-nochecks/context"
printf 'x\n' > "$RV/plugin-nochecks/context/severity.md"
expect_eq "R9: a plugin copy with no checks file for the brief's question is refused, naming the file" \
  "rc=2 gen-prompt.sh: $RV/plugin-nochecks/context/checks-structure.md cannot be read" "$(r9 env PLUGIN="$RV/plugin-nochecks" bash "$GEN" "$RV/brief-1.txt")"
printf 'subagent_type: bionic:critic\nFiles: /tmp/q/s1/r.md\nRead it.\n' > "$RV/brief-noq.txt"
expect_eq "R9: a brief with no Questions: line is refused, since no checks file can be named for it" \
  "rc=2 gen-prompt.sh: $RV/brief-noq.txt has no Questions: line" "$(r9 env PLUGIN="$RV/plugin" bash "$GEN" "$RV/brief-noq.txt")"
printf 'subagent_type: bionic:critic\nQuestions: evidence, taste\nRead it.\n' > "$RV/brief-badq.txt"
expect_eq "R9: a brief dealt a question the recorder pushes nothing for is refused, naming it" \
  "rc=2 gen-prompt.sh: $RV/brief-badq.txt names the question 'taste', which is none of evidence, adversarial, structure" \
  "$(r9 env PLUGIN="$RV/plugin" bash "$GEN" "$RV/brief-badq.txt")"
expect_empty "R9: a refused call writes no prompt" "$(env -u PLUGIN bash "$GEN" "$RV/brief-1.txt" 2>/dev/null)"

section "§HELPERS — whose claude runs, where a session or a build may sit, no fifth argument (T64)"

# SYNTHESIZED here: a fake CLI on a throwaway PATH (a tagged script, and the §RECIPE one), a
# caller directory and a built project that each hold a file named claude. Nothing starts a
# session. The PATH always ends in /usr/bin:/bin, so the helpers' own tools resolve.
CK="$TMP/t64"
mkdir -p "$CK/caller" "$CK/dest/bin" "$CK/abs" "$CK/copied"
tagfake() { printf '#!/bin/bash\necho "%s" >> "$TAG_LOG"\n' "$1" > "$2"; chmod +x "$2"; }
tagfake caller "$CK/caller/claude"
tagfake dest "$CK/dest/claude"
tagfake destbin "$CK/dest/bin/claude"
# hs <cwd> <PATH> <helper args...> — one helper run from <cwd>, the fakes' logs under $CK.
hs() {
  local cwd="$1" pth="$2"; shift 2
  ( cd "$cwd" && env PATH="$pth" TAG_LOG="$CK/tags" FAKE_LOG="$CK/fake.log" /bin/bash "$@" 2>&1 )
}
hs_reset() { rm -f "$CK/tags" "$CK/fake.log" "$CK/out.json" "$CK/out.json.time" "$CK/out.json.err"; }
OKPATH="$RV/bin:/usr/bin:/bin"

# B1: the CLI is an absolute path outside <dest>.
hs_reset
out="$(hs "$CK/caller" ".:/usr/bin:/bin" "$RUN" "$CK/dest" "$RV/plugin" "$RV/prompt.txt" "$CK/out.json")"; rc=$?
expect_status "H1: PATH holding . with a claude in the caller's directory is refused" 2 "$rc"
expect_contains "H1: …saying why" "run-session.sh: refused — PATH holds an entry that is not an absolute directory" "$out"
expect_contains "H1: …and naming the entry" "PATH entry '.';" "$out"
expect_false "H1: …and neither the caller's claude nor the project's ran" test -e "$CK/tags"
expect_false "H1: …and nothing is written" test -e "$CK/out.json.time"
hs_reset
out="$(hs "$CK/caller" ":/usr/bin:/bin" "$RUN" "$CK/dest" "$RV/plugin" "$RV/prompt.txt" "$CK/out.json")"; rc=$?
expect_status "H2: PATH holding an empty entry is refused" 2 "$rc"
expect_contains "H2: …naming it" "PATH entry '' (empty, which is the working directory)" "$out"
expect_false "H2: …and nothing ran" test -e "$CK/tags"
hs_reset
out="$(hs "$CK/caller" "/usr/bin:/bin:" "$RUN" "$CK/dest" "$RV/plugin" "$RV/prompt.txt" "$CK/out.json")"; rc=$?
expect_status "H2: a trailing empty entry is refused too" 2 "$rc"
expect_false "H2: …and nothing ran" test -e "$CK/tags"
hs_reset
out="$(hs "$CK/caller" "rel:/usr/bin:/bin" "$RUN" "$CK/dest" "$RV/plugin" "$RV/prompt.txt" "$CK/out.json")"; rc=$?
expect_status "H2: a relative entry that holds no claude is refused as well (T73)" 2 "$rc"
expect_contains "H2: …naming it" "PATH entry 'rel';" "$out"
mkdir -p "$CK/caller/rel"; tagfake rel "$CK/caller/rel/claude"
out="$(hs "$CK/caller" "rel:/usr/bin:/bin" "$RUN" "$CK/dest" "$RV/plugin" "$RV/prompt.txt" "$CK/out.json")"; rc=$?
expect_status "H2: a named relative entry that holds a claude is refused" 2 "$rc"
expect_contains "H2: …naming it, whatever it holds" "PATH entry 'rel';" "$out"
expect_false "H2: …and it never ran" test -e "$CK/tags"
hs_reset
# H3, re-pinned by T73. T64 passed this PATH because the first claude on it is absolute; review
# pass 52 (B1) ran the built project's own env and cat under it, since the session and the
# helper's later steps search the same PATH from the built project. A relative or empty entry is
# now refused wherever it stands, and whether or not it holds a claude.
out="$(hs "$CK/caller" "$RV/bin:.:/usr/bin:/bin:" "$RUN" "$CK/dest" "$RV/plugin" "$RV/prompt.txt" "$CK/out.json")"; rc=$?
expect_status "H3: an absolute claude first is refused when a relative entry follows it" 2 "$rc"
expect_contains "H3: …naming the entry" "PATH entry '.';" "$out"
expect_false "H3: …and neither the absolute claude nor the caller's ran" test -e "$CK/fake.log"
expect_false "H3: …nor any tagged fake" test -e "$CK/tags"
expect_false "H3: …and nothing is written" test -e "$CK/out.json.time"
hs_reset
out="$(hs "$CK" "$CK/dest/bin:/usr/bin:/bin" "$RUN" "$CK/dest" "$RV/plugin" "$RV/prompt.txt" "$CK/out.json")"; rc=$?
expect_status "H4: an absolute claude inside <dest> is refused" 2 "$rc"
expect_contains "H4: …naming it" "$CK/dest/bin/claude" "$out"
expect_false "H4: …and it never ran" test -e "$CK/tags"
ln -s "$CK/dest" "$CK/destlink"
hs_reset
out="$(hs "$CK" "$CK/dest/bin:/usr/bin:/bin" "$RUN" "$CK/destlink" "$RV/plugin" "$RV/prompt.txt" "$CK/out.json")"; rc=$?
expect_status "H4: <dest> reached through a link is the same place" 2 "$rc"
hs_reset
out="$(hs "$CK" "$CK/destlink/bin:/usr/bin:/bin" "$RUN" "$CK/dest" "$RV/plugin" "$RV/prompt.txt" "$CK/out.json")"; rc=$?
expect_status "H4: …and so is a PATH entry reached through a link" 2 "$rc"
expect_false "H4: …neither ran" test -e "$CK/tags"
ln -s "$CK/dest/bin/claude" "$CK/abs/claude"
hs_reset
out="$(hs "$CK" "$CK/abs:/usr/bin:/bin" "$RUN" "$CK/dest" "$RV/plugin" "$RV/prompt.txt" "$CK/out.json")"; rc=$?
expect_status "H4: a claude outside <dest> that is a link to one inside it is refused" 2 "$rc"
expect_false "H4: …and it never ran" test -e "$CK/tags"

# S1: neither helper starts anything inside the checkout that holds the answers.
SITS="never sits inside the checkout that holds the answers"
REPO_PHYS="$(cd "$REPO" && pwd -P)"
expect_eq "H5: the helpers' own checkout is the one this suite reads" "$REPO_PHYS" \
  "$(cd "$(git -C "$EXAM" rev-parse --show-toplevel)" && pwd -P)"
ln -s "$REPO/tests/reader-exam" "$CK/into-checkout"
for spec in "dot:$REPO:." "absolute:$REPO:$REPO" "inside:$REPO:$REPO/tests" "link:$CK:$CK/into-checkout"; do
  IFS=: read -r nm cwd d <<<"$spec"
  hs_reset
  out="$(hs "$cwd" "$OKPATH" "$RUN" "$d" "$RV/plugin" "$RV/prompt.txt" "$CK/out.json")"; rc=$?
  expect_status "H6: run-session.sh refuses a <dest> that is the checkout, in it, or a link into it ($nm)" 2 "$rc"
  expect_contains "H6: …saying why ($nm)" "run-session.sh: refused — a session $SITS" "$out"
  expect_false "H6: …and the fake never ran ($nm)" test -e "$CK/fake.log"
  expect_false "H6: …and nothing is written ($nm)" test -e "$CK/out.json.time"
done
hs_reset
out="$(hs "$CK" "$OKPATH" "$RUN" "$CK/dest" "$RV/plugin" "$RV/prompt.txt" "$CK/out.json")"; rc=$?
expect_status "H6: a <dest> outside it is accepted, beside the refusals" 0 "$rc"

# A helper copied out of its checkout cannot know where it is, so it does not refuse on that
# ground and says nothing of it. The copy is proved to sit outside any checkout first.
cp "$RUN" "$CK/copied/run-session.sh"; cp "$EXAM/materialize.sh" "$CK/copied/materialize.sh"
expect_false "H7: the copied helpers sit in no git checkout" git -C "$CK/copied" rev-parse --show-toplevel
hs_reset
out="$(hs "$CK" "$OKPATH" "$CK/copied/run-session.sh" "$REPO" "$RV/plugin" "$RV/prompt.txt" "$CK/out.json")"; rc=$?
expect_status "H7: a copied run-session.sh does not refuse a <dest> inside the checkout" 0 "$rc"
expect_absent "H7: …and says nothing of a checkout" "checkout" "$out"
expect_true "H7: …and the fake ran" test -e "$CK/fake.log"
# …and the row is live: a copy that refuses when it cannot find a checkout is refused here.
anchor "$RUN" '[ -n "$git_at" ] || return 0' 1
sed 's/\[ -n "\$git_at" \] || return 0/refuse "a session never sits inside the checkout that holds the answers" blind/' \
  "$RUN" > "$CK/copied/refuse-blind.sh"
expect_eq "H7: the doctored copy refuses without a checkout to refuse for" "1" "$(grep -c 'answers" blind$' "$CK/copied/refuse-blind.sh")"
hs_reset
out="$(hs "$CK" "$OKPATH" "$CK/copied/refuse-blind.sh" "$REPO" "$RV/plugin" "$RV/prompt.txt" "$CK/out.json")"; rc=$?
expect_status "H7: …so on it the same row is red: it exits 2" 2 "$rc"
expect_contains "H7: …with the refusal" "never sits inside the checkout" "$out"
out="$(bash "$CK/copied/materialize.sh" "$DS" "$TMP/copied-built/s1" 2> "$CK/copied.err")"; rc=$?
expect_status "H7: a copied materialize.sh builds" 0 "$rc"
expect_empty "H7: …and says nothing" "$(cat "$CK/copied.err")"

for spec in "dot:$REPO:." "absolute:$REPO:$REPO"; do
  IFS=: read -r nm cwd d <<<"$spec"
  out="$(cd "$cwd" && bash "$EXAM/materialize.sh" "$DS" "$d" 2>&1)"; rc=$?
  expect_status "H8: materialize.sh refuses the checkout itself ($nm)" 2 "$rc"
  expect_contains "H8: …saying why ($nm)" "materialize: refused — a build $SITS" "$out"
done
INSIDE="$REPO/.t64-inside"
out="$(bash "$EXAM/materialize.sh" "$DS" "$INSIDE/s1" 2>&1)"; rc=$?
expect_status "H8: materialize.sh refuses a new path inside the checkout" 2 "$rc"
expect_contains "H8: …saying why" "materialize: refused — a build $SITS" "$out"
expect_false "H8: …and builds nothing" test -e "$INSIDE"
rm -rf "$INSIDE"
ln -s "$REPO/tests" "$CK/tests-link"
out="$(bash "$EXAM/materialize.sh" "$DS" "$CK/tests-link/.t64-sym/s1" 2>&1)"; rc=$?
expect_status "H8: …and one reached through a link outside it" 2 "$rc"
expect_contains "H8: …saying why" "materialize: refused — a build $SITS" "$out"
expect_false "H8: …and builds nothing" test -e "$REPO/tests/.t64-sym"
rm -rf "$REPO/tests/.t64-sym"
out="$(bash "$EXAM/materialize.sh" "$DS" "$TMP/x/dup-counter-again" 2>&1)"; rc=$?
expect_status "H8: its refusal of a destination that names the sample stands" 2 "$rc"
expect_contains "H8: …with its own words" "names the sample dup-counter" "$out"

# S2: a fifth argument is refused and nothing runs. The argument is a permissions flag, held as
# data; the doctored copy appends the rest of the arguments to the CLI's and relaxes the count,
# and is the proof that the row goes red on a passthrough.
FIFTH="--dangerously-skip-permissions"
fifth() { # <script> — "refused" when it exits 2 and the fake never ran, "ran" when the fake did
  hs_reset
  out="$(hs "$CK" "$OKPATH" "$1" "$CK/dest" "$RV/plugin" "$RV/prompt.txt" "$CK/out.json" "$FIFTH")"; rc=$?
  if [ "$rc" = 2 ] && [ ! -e "$CK/fake.log" ]; then echo refused; elif [ -e "$CK/fake.log" ]; then echo ran; else echo "rc=$rc"; fi
}
expect_eq "H9: a fifth argument is refused and the fake never runs" "refused" "$(fifth "$RUN")"
expect_false "H9: …and nothing is written" test -e "$CK/out.json.time"
anchor "$RUN" '"$#" -eq 4' 1
anchor "$RUN" '--output-format json "$prompt_text"' 1
sed -e 's/"\$#" -eq 4/"$#" -ge 4/' -e 's/--output-format json "\$prompt_text"/--output-format json "$prompt_text" "${@:5}"/' "$RUN" > "$CK/pass.sh"
expect_eq "H9: the doctored copy relaxes the count and passes the rest on" "2" "$(grep -cE '"\$#" -ge 4|\$\{@:5\}' "$CK/pass.sh")"
expect_eq "H9: …and on it the same row is red: the fake ran" "ran" "$(fifth "$CK/pass.sh")"
expect_contains "H9: …with the flag among its arguments" "[$FIFTH]" "$(cat "$CK/fake.log")"

# The README says each refusal where a sitter meets the helper.
STEP2="$(awk '/^2\. \*\*Materialize each sample/ { f = 1 } /^3\. \*\*Open an engaged session/ { f = 0 } f' "$EXAM/README.md")"
STEP2_FLAT="$(printf '%s' "$STEP2" | tr '\n' ' ' | tr -s ' ')"
expect_contains "H10: step 2 says materialize.sh refuses a destination inside any worktree" "lies inside any worktree of this repository" "$STEP2_FLAT"
expect_contains "H10: …that it builds where <dest> resolves to" "builds where that leads" "$STEP2_FLAT"
expect_contains "H10: …and that a failed lookup of its worktrees refuses" "that lookup fails, it refuses" "$STEP2_FLAT"
STEP3_FLAT="$(printf '%s' "$STEP3" | tr '\n' ' ' | tr -s ' ')"
expect_contains "H10: step 3 says run-session.sh refuses one too, and an output file there" "inside any worktree of this repository" "$STEP3_FLAT"
expect_contains "H10: …and a PATH entry that is not absolute, whatever it holds" "any entry that is not an absolute directory" "$STEP3_FLAT"
expect_contains "H10: …and when: before the CLI runs or anything is written" "before it runs the CLI or writes anything" "$STEP3_FLAT"
expect_contains "H10: …and on what its own steps run" "PATH=/usr/bin:/bin" "$STEP3_FLAT"
expect_contains "H10: …and a fifth argument" "fifth argument" "$STEP3_FLAT"

section "§CALLERS — the reviewer's callers, one table (T73)"

# Review pass 52 pictured 98 callers of the two helpers and drove each with a fake CLI. The
# table below is those callers, each with its answer: what must have run (nothing, or the
# absolute fake outside the built project, in the RESOLVED destination), what is new or
# changed afterwards anywhere under the throwaway root, and the first line said on a refusal.
# ONE row compares the whole table, red on any line that differs. It drives byte copies of the
# helpers in a throwaway repository under this suite's $TMP (common rule 12: never a real
# checkout), with a main checkout, a worktree under it, an external worktree and a tracked
# link `payload/hooks -> ../hooks`, as the review's model had. SYNTHESIZED: every program a
# caller can put first (a fake claude, and fakes named dirname, env, cat, git, date, readlink,
# mkdir and cp in the caller's directory and in the built project), each logging its tag and
# working directory; exported functions, BASH_ENV, CDPATH, IFS and GIT_CEILING_DIRECTORIES;
# copies whose own PATH (the one `PATH=/usr/bin:/bin` assignment) names a directory
# with no git, or a git that answers nothing, two lines, fails, or names a directory not theirs.
B="$(cd -P "$TMP" && pwd -P)/t73"
mkdir -p "$B"
expect_false "HT0: the throwaway root lies in no git repository" git -C "$B" rev-parse --show-toplevel
case "$B" in /private/var/*) BV="${B#/private}" ;; *) BV="$B" ;; esac
[ "$BV" -ef "$B" ] || BV="$B"
REC="$B/rec"; mkdir -p "$REC" "$B/home" "$B/plugin" "$B/outdir/adir" "$B/okdest" "$B/m" "$B/o/far"
printf 'a prompt\n' > "$B/prompt.txt"; mkdir -p "$TMP/t73-out"
# tfake <path> <tag> — a program that logs `<tag>@<its physical working directory>`.
tfake() { mkdir -p "${1%/*}"; printf '#!/bin/bash\necho "%s@$(pwd -P)" >> "%s/log"\n' "$2" "$REC" > "$1"; chmod +x "$1"; }
tfake "$B/fakebin/claude" GOOD
tfake "$TMP/t73-bin/claude" OUTER
for t in claude dirname env cat git date readlink mkdir cp; do tfake "$B/caller/$t" "CALLER-$t"; done
for t in claude env cat git date; do tfake "$B/dest/$t" "DEST-$t"; done
tfake "$B/dest/bin/claude" DESTBIN
tfake "$B/d2/bin/claude" D2BIN
tfake "$B/shim/date" SHIM-date
mkdir -p "$B/cdir/claude" "$B/cnox" "$B/abs" "$B/chain"; printf '#!/bin/bash\n' > "$B/cnox/claude"
ln -s "$B/dest/bin/claude" "$B/abs/claude"
ln -s ../abs/claude "$B/chain/claude"
ln -s "$B/o/far" "$B/d2/out"
printf 'env() { echo BASHENV-env >> "%s/log"; }\ncd() { echo BASHENV-cd >> "%s/log"; }\n' "$REC" "$REC" > "$B/bashenv.sh"
# The model repository: the helpers under test, a sample with an answer file, a tracked link.
R="$B/repo" W="$B/repo/.worktrees/wt" X="$B/ext"
SX="$R/tests/reader-exam/samples/alpha"
mkdir -p "$SX/tree" "$R/hooks" "$R/payload"
cp "$RUN" "$EXAM/materialize.sh" "$R/tests/reader-exam/"
ln -s ../hooks "$R/payload/hooks"; echo h > "$R/hooks/h.sh"
echo one > "$SX/tree/a.txt"; echo "verdict: flag" > "$SX/expect.txt"
printf 'diff --git a/a.txt b/a.txt\n--- a/a.txt\n+++ b/a.txt\n@@ -1 +1,2 @@\n one\n+two\n' > "$SX/change.patch"
printf '.worktrees/\n' > "$R/.gitignore"
expect_false "HT0: …and nor does the model repository before it is made one" git -C "$R" rev-parse --show-toplevel
git -C "$R" init -q
if [ "$(cd "$(git -C "$R" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null && pwd -P)" = "$R" ]; then
  ok "HT0: the model repository's top is the throwaway path, before anything is written there"
  git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@example.invalid commit -q -m m
  git -C "$R" worktree add -q "$W" 2>/dev/null; git -C "$R" worktree add -q "$X" 2>/dev/null
else
  no "HT0: the model repository's top is the throwaway path, before anything is written there" "it is not; nothing is committed"
fi
expect_eq "HT0: the model has a main checkout and two worktrees" "3" "$(git -C "$R" worktree list --porcelain | grep -c '^worktree ')"
RUN_M="$R/tests/reader-exam/run-session.sh" MAT_M="$R/tests/reader-exam/materialize.sh"
RUN_W="$W/tests/reader-exam/run-session.sh" MAT_W="$W/tests/reader-exam/materialize.sh"
RUN_X="$X/tests/reader-exam/run-session.sh" MAT_X="$X/tests/reader-exam/materialize.sh"
mkdir -p "$B/copied"; cp "$RUN" "$EXAM/materialize.sh" "$B/copied/"
RUN_C="$B/copied/run-session.sh" MAT_C="$B/copied/materialize.sh"
# Copies whose own PATH is a directory of the review's making. `nogit` holds every tool the
# helpers use but git; the others hold that and a git with one bad answer.
for d in nogit mute two fail far; do
  mkdir -p "$B/own-$d"
  for t in date cat readlink mkdir cp tr; do ln -s "$(command -v "$t")" "$B/own-$d/$t"; done
done
printf '#!/bin/bash\nexit 0\n' > "$B/own-mute/git"
printf '#!/bin/bash\nprintf "%%s\\n%%s\\n" "%s" "%s"\n' "$R" "$R" > "$B/own-two/git"
printf '#!/bin/bash\nexit 128\n' > "$B/own-fail/git"
printf '#!/bin/bash\necho "%s"\n' "$B/okdest" > "$B/own-far/git"
chmod +x "$B"/own-*/git 2>/dev/null
for h in run-session materialize; do
  anchor "$EXAM/$h.sh" 'PATH=/usr/bin:/bin ' 1
  for d in nogit mute two fail far; do
    sed "s#PATH=/usr/bin:/bin #PATH=$B/own-$d #" "$EXAM/$h.sh" > "$R/tests/reader-exam/$d-$h.sh"
  done
  sed "s#PATH=/usr/bin:/bin #PATH=$B/own-nogit #" "$EXAM/$h.sh" > "$B/copied/nogit-$h.sh"
done
for t in rlink:"$R" tlink:"$R/tests" plink:"$R/tests" olink:"$R/tests" nlink:"$B/Alpha-real" \
         n2:"$B/alpha-deep/sub" dangle:"$R/nonexistent"; do
  ln -s "${t#*:}" "$B/${t%%:*}"
done
mkdir -p "$B/Alpha-real" "$B/alpha-deep/sub"
ln -s "$SX/expect.txt" "$B/outdir/lnk.json"
ln -s "$SX/expect.txt" "$B/outdir/t.json.time"
mkdir -p "$B/casecheck"
CASE_BLIND=no; [ -d "$B/CASECHECK" ] && CASE_BLIND=yes

# tsnap — every entry under the root but the fakes' log and .git, files with their checksum.
tsnap() {
  { find "$B" \( -path "$REC" -o -name .git \) -prune -o -type f -exec cksum {} +
    find "$B" \( -path "$REC" -o -name .git \) -prune -o ! -type f -print | sed 's/^/L 0 /'
  } | LC_ALL=C sort -k 3
}
# tsym — a text with the root written B, in either spelling.
tsym() { local s="${1//"$B"/B}"; printf '%s' "${s//"$BV"/B}"; }
# tdiff <before> <after> — new entries (topmost only), ~changed and -gone ones, comma-joined.
tdiff() {
  awk 'NR == FNR { a[$3] = $1 " " $2; next } { b[$3] = $1 " " $2 }
       END { for (p in b) if (!(p in a)) print "+" p; else if (a[p] != b[p]) print "~" p
             for (p in a) if (!(p in b)) print "-" p }' "$1" "$2" | LC_ALL=C sort -k 1.2 |
    awk '/^\+/ { p = substr($0, 2); if (top != "" && index(p, top "/") == 1) next; top = p } { print }'
}
U_RS="usage: run-session.sh <dest> <plugin copy> <prompt file> <output file>"
P_RS="run-session.sh: refused — PATH holds an entry that is not an absolute directory"
N_RS="run-session.sh: no claude binary on PATH"
L_RS="run-session.sh: refused — the lookup of this file's checkout failed"
C_RS="run-session.sh: refused — a session never sits inside the checkout that holds the answers"
O_RS="run-session.sh: refused — an output file never lies in a checkout or in the built project"
F_RS="run-session.sh: refused — an output file exists and is not a regular file"
I_RS="run-session.sh: refused — the claude on PATH is a file inside the built project"
C_MA="materialize: refused — a build never sits inside the checkout that holds the answers"
L_MA="materialize: refused — the lookup of this file's checkout failed"
D_MA="materialize: refused — a part of <dest> that does not exist yet is . or .."
E_MA="materialize: <dest> must be a new path"
N_MA="names the sample alpha — a reader given it is told the answer; choose a neutral path"
NO="rc=2 ran=- new=- said="
RAN="new=+B/outdir/o.json,+B/outdir/o.json.err,+B/outdir/o.json.time said=-"
OK="$B/fakebin:/usr/bin:/bin" T3="$B/plugin $B/prompt.txt $B/outdir/o.json" S="$SX"
# id | flags (case: only where letter case is ignored; sh: run by /bin/sh) | helper | cwd |
# PATH ('' empty, -unset- none) | environment | arguments ('' an empty one) | answer
CALLERS="$(cat <<TABLE
L1||$RUN_M|$B/caller|.:/usr/bin:/bin|-|$B/dest $T3|${NO}$P_RS
L2||$RUN_M|$B/caller|:/usr/bin:/bin|-|$B/dest $T3|${NO}$P_RS
L3||$RUN_M|$B/caller|/usr/bin::/bin|-|$B/dest $T3|${NO}$P_RS
L4||$RUN_M|$B/caller|/usr/bin:/bin:|-|$B/dest $T3|${NO}$P_RS
L5a||$RUN_M|$B/caller|./bin:/usr/bin:/bin|-|$B/dest $T3|${NO}$P_RS
L5b||$RUN_M|$B/caller|bin:/usr/bin:/bin|-|$B/dest $T3|${NO}$P_RS
L5c||$RUN_M|$B/caller|..:/usr/bin:/bin|-|$B/dest $T3|${NO}$P_RS
L5d||$RUN_M|$B/caller|''|-|$B/dest $T3|${NO}$P_RS
L6||$RUN_M|$B/caller|$B/dest/bin:/usr/bin:/bin|-|$B/dest $T3|${NO}$I_RS
L7a||$RUN_M|$B/caller|$B/abs:/usr/bin:/bin|-|$B/dest $T3|${NO}$I_RS
L7b||$RUN_M|$B/caller|$B/chain:/usr/bin:/bin|-|$B/dest $T3|${NO}$I_RS
L8a||$RUN_M|$B/caller|$BV/dest/bin:/usr/bin:/bin|-|$B/dest $T3|${NO}$I_RS
L8b||$RUN_M|$B/caller|$B/dest/bin:/usr/bin:/bin|-|$BV/dest $T3|${NO}$I_RS
L9a|case|$RUN_M|$B/caller|$B/DEST/bin:/usr/bin:/bin|-|$B/dest $T3|${NO}$I_RS
L9b|case|$RUN_M|$B/caller|$B/dest/bin:/usr/bin:/bin|-|$B/DEST $T3|${NO}$I_RS
L10||$RUN_M|$B/caller|$B/cdir:$B/cnox:$OK|-|$B/dest $T3|rc=0 ran=GOOD@B/dest $RAN
L11||$RUN_M|$B/caller|$B/shim:$OK|-|$B/dest $T3|rc=0 ran=GOOD@B/dest $RAN
L12||$RUN_M|$B/caller|$B/fakebin:.:/usr/bin:/bin:|-|$B/dest $T3|${NO}$P_RS
L14a||$RUN_M|$B/caller|$OK|fn:claude|$B/dest $T3|rc=0 ran=GOOD@B/dest $RAN
L14b||$RUN_M|$B/caller|$OK|fn:env|$B/dest $T3|rc=0 ran=GOOD@B/dest $RAN
L14c||$RUN_M|$B/caller|$OK|fn:command|$B/dest $T3|rc=0 ran=GOOD@B/dest $RAN
L14d||$RUN_M|$B/caller|$OK|fn:git|$B/dest $T3|rc=0 ran=GOOD@B/dest $RAN
L14e||$RUN_M|$B/caller|$OK|fn:cd|$B/dest $T3|rc=0 ran=GOOD@B/dest $RAN
L16||$RUN_M|$B/caller|$OK|bashenv|$B/dest $T3|rc=0 ran=GOOD@B/dest $RAN
L18||$RUN_M|$B/caller|$OK|ifs|$B/dest $T3|rc=0 ran=GOOD@B/dest $RAN
L19||$RUN_M|$B/caller|-unset-|-|$B/dest $T3|${NO}$N_RS
L21a|sh|$RUN_M|$B/caller|.:/usr/bin:/bin|-|$B/dest $T3|${NO}$P_RS
L21b|sh|$RUN_M|$B/caller|$OK|-|$B/dest $T3|rc=0 ran=GOOD@B/dest $RAN
L21c|sh|$RUN_M|$B/caller|$OK|-|$R $T3|${NO}$C_RS
D1||$RUN_M|$R|$OK|-|. $T3|${NO}$C_RS
D2||$RUN_M|$B/caller|$OK|-|$R $T3|${NO}$C_RS
D3||$RUN_M|$B/caller|$OK|-|../repo/tests $T3|${NO}$C_RS
D4||$RUN_M|$B/caller|$OK|-|$B/rlink $T3|${NO}$C_RS
D5||$RUN_M|$B/caller|$OK|-|$BV/repo $T3|${NO}$C_RS
D6||$RUN_M|$B/caller|$OK|-|$R/nope $T3|${NO}$U_RS
D7a||$RUN_M|$B/caller|$OK|-|$R/tests/../tests $T3|${NO}$C_RS
D7b||$RUN_M|$B/caller|$OK|-|$R/payload/hooks/../.. $T3|${NO}$O_RS
D7c||$RUN_M|$R|$OK|-|payload/hooks/../.. $B/plugin $B/prompt.txt $TMP/t73-out/o.json|${NO}$I_RS
D7e||$RUN_M|$R|$TMP/t73-bin:/usr/bin:/bin|-|payload/hooks/../.. $B/plugin $B/prompt.txt $TMP/t73-out/o.json|rc=0 ran=OUTER@B new=- said=-
D7d||$RUN_M|$B/caller|$B/d2/bin:/usr/bin:/bin|-|$B/d2/out/.. $T3|rc=0 ran=D2BIN@B/o $RAN
D8mm||$RUN_M|$B/caller|$OK|-|$R/tests $T3|${NO}$C_RS
D8mw||$RUN_M|$B/caller|$OK|-|$W/tests $T3|${NO}$C_RS
D8mx||$RUN_M|$B/caller|$OK|-|$X/tests $T3|${NO}$C_RS
D8wm||$RUN_W|$B/caller|$OK|-|$R/tests $T3|${NO}$C_RS
D8ww||$RUN_W|$B/caller|$OK|-|$W/tests $T3|${NO}$C_RS
D8wx||$RUN_W|$B/caller|$OK|-|$X/tests $T3|${NO}$C_RS
D8xm||$RUN_X|$B/caller|$OK|-|$R/tests $T3|${NO}$C_RS
D8xw||$RUN_X|$B/caller|$OK|-|$W/tests $T3|${NO}$C_RS
D8xx||$RUN_X|$B/caller|$OK|-|$X/tests $T3|${NO}$C_RS
D9||$RUN_M|$B/caller|$OK|-|$B/tlink/reader-exam $T3|${NO}$C_RS
D10a||$RUN_C|$B/caller|$OK|-|$R $T3|rc=0 ran=GOOD@B/repo $RAN
D10b||$B/copied/nogit-run-session.sh|$B/caller|$OK|-|$R $T3|rc=0 ran=GOOD@B/repo $RAN
D11a|case|$RUN_M|$B/caller|$OK|-|$B/REPO $T3|${NO}$C_RS
D11b|case|$RUN_M|$B/REPO|$OK|-|. $T3|${NO}$C_RS
D12a||tests/reader-exam/run-session.sh|$R|$OK|cdpath|. $T3|${NO}$C_RS
D12b||tests/reader-exam/run-session.sh|$R|$OK|cdpathw|. $T3|${NO}$C_RS
D13a||$RUN_M|$B/caller|$OK|fn:cd|$R $T3|${NO}$C_RS
D13b||$RUN_M|$B/caller|$OK|fn:command|$R $T3|${NO}$C_RS
D13c||$RUN_M|$B/caller|$OK|fn:git|$R $T3|${NO}$C_RS
D13d||$RUN_M|$B/caller|$OK|bashenv|$R $T3|${NO}$C_RS
D14||$RUN_M|$B/caller|$OK|ceiling|$R/tests $T3|${NO}$C_RS
D15||$RUN_M|$B/caller|$OK|-|$B/okdest $T3|rc=0 ran=GOOD@B/okdest $RAN
K1||$R/tests/reader-exam/nogit-run-session.sh|$B/caller|$OK|-|$B/okdest $T3|${NO}$L_RS
K2||$R/tests/reader-exam/mute-run-session.sh|$B/caller|$OK|-|$B/okdest $T3|${NO}$L_RS
K3||$R/tests/reader-exam/two-run-session.sh|$B/caller|$OK|-|$B/okdest $T3|${NO}$L_RS
K4||$R/tests/reader-exam/fail-run-session.sh|$B/caller|$OK|-|$B/okdest $T3|${NO}$L_RS
K5||$R/tests/reader-exam/far-run-session.sh|$B/caller|$OK|-|$B/okdest $T3|${NO}$L_RS
K6||$R/tests/reader-exam/nogit-materialize.sh|$B/caller|$OK|-|$S $B/m/k6|${NO}$L_MA
K7||$R/tests/reader-exam/mute-materialize.sh|$B/caller|$OK|-|$S $B/m/k7|${NO}$L_MA
K8||$R/tests/reader-exam/two-materialize.sh|$B/caller|$OK|-|$S $B/m/k8|${NO}$L_MA
O1||$RUN_M|$B/caller|$OK|-|$B/dest $B/plugin $B/prompt.txt $SX/expect.txt|${NO}$O_RS
O2||$RUN_M|$B/caller|$OK|-|$B/dest $B/plugin $B/prompt.txt $W/o.json|${NO}$O_RS
O3||$RUN_M|$B/caller|$OK|-|$B/dest $B/plugin $B/prompt.txt $X/o.json|${NO}$O_RS
O4||$RUN_M|$B/caller|$OK|-|$B/dest $B/plugin $B/prompt.txt $B/dest/o.json|${NO}$O_RS
O5||$RUN_M|$B/caller|$OK|-|$B/dest $B/plugin $B/prompt.txt $B/olink/../o.json|${NO}$O_RS
O6||$RUN_M|$B/caller|$OK|-|$B/dest $B/plugin $B/prompt.txt $B/outdir/lnk.json|${NO}$F_RS
O7||$RUN_M|$B/caller|$OK|-|$B/dest $B/plugin $B/prompt.txt $B/outdir/adir|${NO}$F_RS
O8||$RUN_M|$B/caller|$OK|-|$B/dest $B/plugin $B/prompt.txt $B/outdir/t.json|${NO}$F_RS
O9||$RUN_M|$B/caller|$OK|-|$B/dest $B/plugin $B/prompt.txt ''|${NO}$U_RS
O10||$RUN_M|$B/caller|$OK|-|$B/dest $B/plugin $B/prompt.txt $B/outdir/|${NO}$U_RS
O11||$RUN_M|$R|$OK|-|$B/dest $B/plugin $B/prompt.txt o.json|${NO}$O_RS
A0||$RUN_M|$B/caller|$OK|-||${NO}$U_RS
A1||$RUN_M|$B/caller|$OK|-|$B/dest|${NO}$U_RS
A3||$RUN_M|$B/caller|$OK|-|$B/dest $B/plugin $B/prompt.txt|${NO}$U_RS
A5||$RUN_M|$B/caller|$OK|-|$B/dest $T3 extra|${NO}$U_RS
A6||$RUN_M|$B/caller|$OK|-|$B/dest $T3 extra more|${NO}$U_RS
A7||$RUN_M|$B/caller|$OK|-|'' $T3|${NO}$U_RS
A8||$RUN_M|$B/caller|$OK|-|$B/dest '' $B/prompt.txt $B/outdir/o.json|${NO}$U_RS
A9||$RUN_M|$B/caller|$OK|-|$B/dest $B/plugin '' $B/outdir/o.json|${NO}$U_RS
M1||$MAT_M|$R|$OK|-|$S .|${NO}$C_MA
M2||$MAT_M|$B/caller|$OK|-|$S $R|${NO}$C_MA
M3||$MAT_M|$R|$OK|-|$S build/s1|${NO}$C_MA
M4||$MAT_M|$B/caller|$OK|-|$S $B/rlink/s1|${NO}$C_MA
M5||$MAT_M|$B/caller|$OK|-|$S $BV/repo/s2|${NO}$C_MA
M6|case|$MAT_M|$B/caller|$OK|-|$S $B/REPO/casebuild|${NO}$C_MA
M7||$MAT_M|$B/caller|$OK|-|$S $B/plink/../dotbuild|${NO}$C_MA
M8a||tests/reader-exam/materialize.sh|$R|$OK|cdpath|tests/reader-exam/samples/alpha cdbuild|${NO}$C_MA
M8b||tests/reader-exam/materialize.sh|$R|$OK|cdpath|$S cdbuild|${NO}$C_MA
M9||$MAT_M|$B/caller|$OK|-|$S $B/dangle/s1|${NO}$E_MA
M10mm||$MAT_M|$B/caller|$OK|-|$S $R/m|${NO}$C_MA
M10mw||$MAT_M|$B/caller|$OK|-|$S $W/m|${NO}$C_MA
M10mx||$MAT_M|$B/caller|$OK|-|$S $X/m|${NO}$C_MA
M10wm||$MAT_W|$B/caller|$OK|-|$S $R/m|${NO}$C_MA
M10ww||$MAT_W|$B/caller|$OK|-|$S $W/m|${NO}$C_MA
M10wx||$MAT_W|$B/caller|$OK|-|$S $X/m|${NO}$C_MA
M10xm||$MAT_X|$B/caller|$OK|-|$S $R/m|${NO}$C_MA
M10xw||$MAT_X|$B/caller|$OK|-|$S $W/m|${NO}$C_MA
M10xx||$MAT_X|$B/caller|$OK|-|$S $X/m|${NO}$C_MA
M11||$MAT_C|$B/caller|$OK|-|$S $R/m11|rc=0 ran=- new=+B/repo/m11 said=-
M12a||$MAT_M|$B/caller|$OK|-|$S $B/alpha-x|${NO}materialize: B/alpha-x $N_MA
M12b||$MAT_M|$B/caller|$OK|-|$S $B/nlink/s1|${NO}materialize: B/Alpha-real/s1 $N_MA
M12c||$MAT_M|$B/caller|$OK|-|$S $B/n2/../s10|${NO}materialize: B/alpha-deep/s10 $N_MA
M13a||$MAT_M|$B/caller|$OK|-|$S $B/none/../x|${NO}$D_MA
M13b||$MAT_M|$B/caller|$OK|-|$S $B/none/./x|${NO}$D_MA
M14||$MAT_M|$B/caller|$OK|fn:cd|$S $R/x|${NO}$C_MA
M15||$MAT_M|$B/caller|$OK|fn:git|$S $B/m/s3|rc=0 ran=- new=+B/m/s3 said=-
M16||$MAT_M|$B/caller|$OK|bashenv|$S $B/m/s4|rc=0 ran=- new=+B/m/s4 said=-
M17||$MAT_M|$B/caller|.:/usr/bin:/bin|-|$S $B/m/s5|rc=0 ran=- new=+B/m/s5 said=-
M18||$MAT_M|$B/caller|$OK|-|$S $B/m/s1|rc=0 ran=- new=+B/m/s1 said=-
TABLE
)"
# tline <id> <flags> <helper> <cwd> <PATH> <environment> <arguments> — one caller's answer.
tline() {
  local id="$1" flags="$2" helper="$3" cwd="$4" pth="$5" ekey="$6" argl="$7" interp=/bin/bash
  local -a envs=("HOME=$B/home") args=() words=()
  case "$flags" in *sh*) interp=/bin/sh ;; esac
  case "$pth" in -unset-) ;; "''") envs+=("PATH=") ;; *) envs+=("PATH=$pth") ;; esac
  case "$ekey" in
    fn:*) envs+=("BASH_FUNC_${ekey#fn:}%%=() { echo FUNC-${ekey#fn:} >> \"$REC/log\"; }") ;;
    bashenv) envs+=("BASH_ENV=$B/bashenv.sh") ;;
    cdpath) envs+=("CDPATH=.:$B/home") ;;
    cdpathw) envs+=("CDPATH=$W") ;;
    ceiling) envs+=("GIT_CEILING_DIRECTORIES=$R/tests") ;;
    ifs) envs+=("IFS=/") ;;
  esac
  read -r -a words <<<"$argl"
  for a in ${words[@]+"${words[@]}"}; do [ "$a" = "''" ] && args+=("") || args+=("$a"); done
  rm -f "$REC/log"; tsnap > "$TMP/t73-before"
  local out rc
  out="$(cd "$cwd" && /usr/bin/env -i "${envs[@]}" "$interp" "$helper" ${args[@]+"${args[@]}"} 2>&1)"; rc=$?
  tsnap > "$TMP/t73-after"
  local ran new said=-
  ran="$( [ -s "$REC/log" ] && paste -sd, - < "$REC/log" || echo -)"
  new="$(tdiff "$TMP/t73-before" "$TMP/t73-after" | paste -sd, -)"
  # what a line left behind is taken away, so the next line meets the same root
  tdiff "$TMP/t73-before" "$TMP/t73-after" | sed -n 's/^+//p' | while IFS= read -r p; do
    case "$p" in "$B"/?*) rm -rf "$p" ;; esac
  done
  [ "$rc" = 0 ] || said="$(printf '%s\n' "$out" | head -n 1)"
  printf '%s|rc=%s ran=%s new=%s said=%s\n' "$id" "$rc" "$(tsym "$ran")" "$(tsym "${new:--}")" "$(tsym "$said")"
}
want="" got="" lines=0 skipped=0
while IFS='|' read -r id flags helper cwd pth ekey argl answer; do
  [ -n "$id" ] || continue
  if [ "$flags" = case ] && [ "$CASE_BLIND" = no ]; then
    echo "SKIP: $id — this volume tells letter case apart, so no other spelling of a path is the same one"
    skipped=$((skipped + 1)); continue
  fi
  lines=$((lines + 1))
  want="$want$id|$answer"$'\n'
  got="$got$(tline "$id" "$flags" "$helper" "$cwd" "$pth" "$ekey" "$argl")"$'\n'
done <<<"$CALLERS"
expect_eq "HT1: the table drives every caller it holds, or names it skipped" \
  "$(printf '%s\n' "$CALLERS" | grep -c '|')" "$((lines + skipped))"
expect_contains "HT1: …and its readback is live: a caller that runs is seen, with what it wrote" \
  "D15|rc=0 ran=GOOD@B/okdest new=+B/outdir/o.json," "$got"
expect_eq "HT1: every caller meets its answer ($lines lines)" "$want" "$got"
[ "$want" = "$got" ] || diff <(printf '%s' "$want") <(printf '%s' "$got") | sed 's/^/      /'
rm -f "$TMP/t73-before" "$TMP/t73-after"

section "§SHIPPED — the shipped sittings against the shipped checks files"

for f in $EXAM_CHECKS; do
  expect_regex "SH0: the digest reads $f" '^[0-9a-f]{64}$' "$(_detect_sha256 "$REPO/$f")"
done
pin_call "$EXAM/sittings.md" "$REPO"
expect_contains "SH1: the latest sitting read the checks files that ship, or says in a stale: line that they changed since" "pinned" "$PIN_OUT"
expect_status "SH1: rc 0" 0 "$PIN_RC"

finish
