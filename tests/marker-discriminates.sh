#!/usr/bin/env bash
#
# tests/marker-discriminates.sh — mutation-and-restore proof that a WALL/FORM
# test pointer discriminates (epic-11 W2 slice 4/2; spec R2, matrix AC-2).
#
# marker-verify.sh proves a pointer RESOLVES. This proves it DISCRIMINATES. For
# every rule marked [WALL: <test>] or [FORM: <test>], it removes the enforcement
# the marker claims and requires the named test to notice:
#
#   1. baseline  the test passes as things stand
#   2. mutate    every blocking path in the named enforcer is neutered
#   3. RED       the test must now fail — if it still passes, the pointer proves
#                nothing and is reported E-NONDISCRIMINATING
#   4. restore   the enforcer is put back and byte-identity is ASSERTED
#   5. GREEN     the test passes again
#
# A green suite records that a test passes, never that it discriminates. That
# gap is the whole reason this file exists: three prior attempts in this epic
# shipped artifacts that passed their own checks and failed in use.
#
# THE REAL TREE IS NEVER WRITTEN. The repo is mirrored into a temp working copy
# and every mutation is refused unless its path is inside that copy. An
# interrupted run therefore cannot leave a mutated enforcement path on disk —
# the mutation never existed outside the temp dir, and the temp dir goes away on
# EXIT, INT and TERM.
#
# Mutation operators — the same two mechanisms marker-verify.sh recognises as
# blocking, kept in the same shape here so detection and mutation cannot drift:
#
#   exit 2                       ->  exit 0
#   permissionDecision ... deny  ->  permissionDecision ... allow
#
# on NON-COMMENT lines only. Neutering the blocking path (rather than stubbing
# the whole enforcer) is deliberate: it changes exactly one thing, so a test
# that still passes has demonstrably never asserted the block, and a test that
# goes red cannot have gone red for an unrelated reason.
#
# Violation codes:
#
#   E-NO-POINTERS        the surfaces contain no WALL/FORM pointer at all; a
#                        vacuous green is the failure mode this wave exists for
#   E-POINTER-MISSING    the named test, or its enforcer, does not exist
#   E-BASELINE-RED       the test already fails before any mutation
#   E-NO-MUTATION        the enforcer has no blocking path to remove
#   E-NONDISCRIMINATING  the test still passes with the enforcement removed
#   E-RESTORE-RED        the test fails after restore
#   E-RESTORE-FAILED     the enforcer is not byte-identical after restore
#
# Usage:
#   bash tests/marker-discriminates.sh              # the three governed surfaces
#   bash tests/marker-discriminates.sh <path>...    # named surfaces (fixtures)
#
#   MARKER_MUTATE_ONLY=1 bash tests/marker-discriminates.sh <file>...
#       Apply the mutation operator to the named files and stop. Exists so the
#       operator itself can be tested; refuses any path inside the repo.
#
# Exit 0 when every pointer discriminates, 1 otherwise. Its own behaviour gate
# is tests/marker-discriminates.test.sh.
#
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

# Verbatim from marker-verify.sh: what counts as a blocking path is one
# definition, and mutation must remove exactly what detection recognises.
RE_EXIT='(^|[^[:alnum:]_])exit[[:space:]]+2([^0-9]|$)'
RE_DENY='permissionDecision.*deny'

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# ---------- the mutation operator ----------

# neuter <file> — rewrites the file in place, echoes how many lines it changed.
# Mode and inode are preserved: the content is written back through the existing
# file rather than moved over it.
neuter() {
  awk -v RE_EXIT="$RE_EXIT" -v RE_DENY="$RE_DENY" -v COUNT="$TMP/count" '
    function neuter_exit(s,   out, m) {
      out = ""
      while (match(s, RE_EXIT)) {
        m = substr(s, RSTART, RLENGTH)
        sub(/2/, "0", m)     # the first digit in the match is the exit code
        out = out substr(s, 1, RSTART - 1) m
        s = substr(s, RSTART + RLENGTH)
      }
      return out s
    }
    # Flips the decision value only — the first "deny" after the field name —
    # so a permissionDecisionReason mentioning the word is left alone.
    function neuter_deny(s,   p, head, tail) {
      p = index(s, "permissionDecision")
      if (p == 0) return s
      head = substr(s, 1, p + 17)
      tail = substr(s, p + 18)
      sub(/deny/, "allow", tail)
      return head tail
    }
    /^[[:space:]]*#/ { print; next }
    {
      if ($0 ~ RE_EXIT)      { $0 = neuter_exit($0); n++ }
      else if ($0 ~ RE_DENY) { $0 = neuter_deny($0);  n++ }
      print
    }
    END { print n + 0 > COUNT }
  ' "$1" >"$TMP/neutered" && cat "$TMP/neutered" >"$1"
  cat "$TMP/count"
}

abspath() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }

if [ "${MARKER_MUTATE_ONLY:-0}" != "0" ]; then
  [ "$#" -gt 0 ] || { echo "MARKER_MUTATE_ONLY: name at least one file" >&2; exit 1; }
  for f in "$@"; do
    [ -f "$f" ] || { echo "no such file: $f" >&2; exit 1; }
    a="$(abspath "$f")"
    case "$a" in
      "$REPO"/*|"$REPO")
        echo "refusing to neuter a path inside the repo: $a" >&2; exit 1 ;;
    esac
    echo "neutered $(neuter "$a") blocking path(s) in $a"
  done
  exit 0
fi

# ---------- surfaces ----------

if [ "$#" -gt 0 ]; then
  SURFACES=("$@")
else
  SURFACES=(claude-global.md skills/canonical-sdlc/SKILL.md)
  for _h in hooks/*.sh; do
    [ -f "$_h" ] || continue
    case "$_h" in *.test.sh) continue ;; esac
    SURFACES+=("$_h")
  done
fi

# ---------- marker extraction ----------
#
# Only WALL/FORM carry pointers; the other two classes claim nothing to prove.
# Fenced blocks and non-comment shell lines are skipped for the same reasons
# marker-verify.sh skips them: an example in a code fence is not a claim.

markers() {  # markers <mode:prose|shell> <file>
  awk -v MODE="$1" -v FILEN="$2" '
    function emit(s, ln,   rest, tok, inner, cls, args, p) {
      rest = s
      while (match(rest, /\[(WALL|FORM)(:[^]]*)?\]/)) {
        tok  = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        inner = substr(tok, 2, length(tok) - 2)
        p = index(inner, ":")
        if (p > 0) { cls = substr(inner, 1, p - 1); args = substr(inner, p + 1) }
        else       { cls = inner; args = "" }
        sub(/^[ \t]+/, "", args); sub(/[ \t]+$/, "", args)
        if (args != "") printf "%s\t%d\t%s\t%s\n", FILEN, ln, cls, args
      }
    }
    { sub(/\r$/, "") }
    MODE == "prose" && /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    MODE == "prose" && fence { next }
    MODE == "shell" && $0 !~ /^[[:space:]]*#/ { next }
    { emit($0, FNR) }
  ' "$2"
}

MARKS="$TMP/marks"; : >"$MARKS"
missing_surface=0
for f in "${SURFACES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "marker-discriminates: no such surface: $f" >&2
    missing_surface=1
    continue
  fi
  case "$f" in
    *.sh) markers shell "$f" >>"$MARKS" ;;
    *)    markers prose "$f" >>"$MARKS" ;;
  esac
done
[ "$missing_surface" -eq 0 ] || exit 1

# ---------- pointer -> (test, enforcers) pairs ----------
#
# Enforcer derivation is marker-verify.sh's: the test pointer with `.test`
# stripped, overridden by any non-test path listed alongside it. One pair is
# checked once however many rules claim it — the hooks are marked rule by rule
# and mutating a hook eight times proves nothing extra.

PAIRS="$TMP/pairs"; : >"$PAIRS"
while IFS=$'\t' read -r file line cls args; do
  tests=""; enforcers=""
  IFS=',' read -r -a parts <<<"$args"
  for p in "${parts[@]}"; do
    p="${p#"${p%%[![:space:]]*}"}"; p="${p%"${p##*[![:space:]]}"}"
    [ -n "$p" ] || continue
    case "$p" in
      *.test.sh) tests="$tests $p" ;;
      *)         enforcers="$enforcers $p" ;;
    esac
  done
  [ -n "$tests" ] || continue
  if [ -z "$enforcers" ]; then
    for t in $tests; do
      d="${t%.test.sh}.sh"
      [ "$d" != "$t" ] && enforcers="$enforcers $d"
    done
  fi
  [ -n "$enforcers" ] || continue
  for t in $tests; do
    printf '%s\t%s\t%s\t%s\n' "$t" "${enforcers# }" "$file:$line" "$cls" >>"$PAIRS"
  done
done <"$MARKS"

VIO="$TMP/violations"; : >"$VIO"
violation() { printf '%s %s\n' "$1" "$2" >>"$VIO"; }

echo "== marker-discriminates =="

npairs=$(sort -t$'\t' -k1,2 -u "$PAIRS" | wc -l | tr -d ' ')
if [ "$npairs" -eq 0 ]; then
  echo "surfaces  ${SURFACES[*]}"
  violation E-NO-POINTERS "no WALL/FORM test pointer found in the named surfaces — nothing was proven"
  echo "--"
  cat "$VIO"
  echo "total     pointers=0 discriminating=0"
  echo "violations=1"
  exit 1
fi

# ---------- working copy ----------
#
# Mirrored once and reused. cp -c clones on APFS (near-instant, copy-on-write);
# anywhere else the plain recursive copy is the fallback. .git comes along
# because hooks read the branch out of it.

WORK="$TMP/work"
if ! cp -Rc "$REPO/." "$WORK" 2>/dev/null; then
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp -R "$REPO/." "$WORK" || { echo "could not mirror the repo" >&2; exit 1; }
fi
echo "working copy  $WORK  (the real tree is never written)"
echo

# guard <abs path> — the wall that makes an interrupted run harmless.
guard() {
  case "$1" in
    "$WORK"/*) return 0 ;;
  esac
  echo "marker-discriminates: refusing to mutate outside the working copy: $1" >&2
  exit 1
}

run_test() {  # run_test <repo-relative test> — 0 green, non-zero red
  ( cd "$WORK" && bash "$1" >"$TMP/testout" 2>&1 )
}

checked=0; discriminating=0

while IFS=$'\t' read -r test enf claim cls; do
  checked=$((checked + 1))
  echo "pointer   $test"
  echo "  claim   $claim $cls"

  # -- resolution --
  gone=""
  [ -f "$WORK/$test" ] || gone="$test"
  for e in $enf; do [ -f "$WORK/$e" ] || gone="$gone $e"; done
  if [ -n "$gone" ]; then
    echo "  enforce  $enf"
    echo "  verdict UNPROVEN"
    violation E-POINTER-MISSING "$claim does not resolve:${gone# }"
    echo
    continue
  fi

  # -- baseline --
  if ! run_test "$test"; then
    echo "  enforce $enf"
    echo "  run     baseline=RED"
    echo "  verdict UNPROVEN"
    violation E-BASELINE-RED \
      "$claim $test already fails before any mutation, so it cannot be shown to discriminate: $(tail -n 1 "$TMP/testout")"
    echo
    continue
  fi

  # -- mutate --
  mkdir -p "$TMP/pristine"
  i=0; total=0
  for e in $enf; do
    i=$((i + 1))
    guard "$WORK/$e"
    cp "$WORK/$e" "$TMP/pristine/$i"
    total=$((total + $(neuter "$WORK/$e")))
  done
  word="blocking paths"; [ "$total" -eq 1 ] && word="blocking path"
  echo "  enforce $enf ($total $word neutered)"

  if [ "$total" -eq 0 ]; then
    echo "  run     baseline=GREEN mutated=n/a"
    echo "  verdict UNPROVEN"
    violation E-NO-MUTATION \
      "$claim $enf contains no blocking path to remove, so $test cannot be shown to discriminate"
    echo
    continue
  fi

  if run_test "$test"; then mutated=GREEN; else mutated=RED; fi

  # -- restore, asserted --
  i=0; bytes=identical
  for e in $enf; do
    i=$((i + 1))
    guard "$WORK/$e"
    cat "$TMP/pristine/$i" >"$WORK/$e"
    cmp -s "$TMP/pristine/$i" "$WORK/$e" || bytes="DIFFERENT($e)"
  done
  if run_test "$test"; then restored=GREEN; else restored=RED; fi

  echo "  run     baseline=GREEN mutated=$mutated restored=$restored bytes=$bytes"

  if [ "$mutated" = "RED" ]; then
    discriminating=$((discriminating + 1))
    echo "  verdict DISCRIMINATES"
  else
    echo "  verdict NON-DISCRIMINATING"
    violation E-NONDISCRIMINATING \
      "$claim $test still passes with the blocking paths removed from $enf — the pointer proves nothing"
  fi

  [ "$bytes" = "identical" ] || violation E-RESTORE-FAILED \
    "$claim $enf is not byte-identical after restore ($bytes) — the working copy is compromised"
  [ "$restored" = "GREEN" ] || violation E-RESTORE-RED \
    "$claim $test does not pass again after $enf was restored"
  echo
done < <(sort -t$'\t' -k1,2 -u "$PAIRS")

nvio=$(wc -l <"$VIO" | tr -d ' ')
if [ "$nvio" -gt 0 ]; then
  echo "--"
  cat "$VIO"
fi
echo "total     pointers=$checked discriminating=$discriminating"
echo "violations=$nvio"
[ "$nvio" -eq 0 ]
