#!/usr/bin/env bash
#
# tests/marker-verify.sh — class-marker verifier (epic-11 W2; spec R1/R2/R3).
#
# Reads the class marker embedded next to each rule in the governed instruction
# surfaces and fails when the surface and the code disagree. Four classes:
#
#   [WALL: <test>]   the action does not happen — `exit 2`, or a
#                    hookSpecificOutput.permissionDecision "deny" payload
#   [FORM: <test>]   a required artifact shape; a malformed field is caught
#   [INSTRUMENT]     observes and records; never blocks, never instructs
#   [UNENFORCED]     prose only; nothing downstream depends on it
#
# UNENFORCED is legitimate and non-pejorative. The defect this verifier exists
# to catch is a rule that READS as binding while nothing enforces it — and its
# mirror image, enforcement that exists while no rule claims it.
#
# Marker syntax, in full:
#
#   [CLASS]                     INSTRUMENT | UNENFORCED — never a pointer
#   [CLASS: path[, path...]]    WALL | FORM — at least one `*.test.sh`
#
# The ENFORCING file is the test pointer with `.test` removed
# (hooks/protect-main.test.sh -> hooks/protect-main.sh), the convention every
# hook in this repo already follows. Where that derivation does not apply, list
# the enforcer as an extra path. One grep-able token, read by the same
# fence-aware awk the hooks already use: no new parser, no new dependency.
#
# Checks (spec R3) — each has its own violation code:
#
#   E-UNMARKED            a normative statement in a unit carrying no marker
#   E-MISSING-POINTER     WALL/FORM with no pointer
#   E-UNEXPECTED-POINTER  INSTRUMENT/UNENFORCED carrying a pointer
#   E-POINTER-MISSING     a pointer path that does not exist
#   E-POINTER-NOTEST      a pointer naming no `*.test.sh`
#   E-ENFORCER-UNRESOLVED no enforcer listed and none derivable
#   E-NO-BLOCKING         the named enforcer contains no blocking path
#   E-UNCLAIMED-BLOCK     a blocking path no marker claims — the two-way check
#
# Definitions this verifier commits to (all are judgment calls; see the plan's
# ## Assumptions):
#
#   normative statement — a LINE containing an obligation keyword (never / must
#     / always / mandatory / required / shall / do not / don't) or a BINDING VERB
#     (cannot / can't / forbid(s) / forbidden / refuse(s) / prevents / no way to
#     / will not / is barred), case-insensitive, whole word. Line, not sentence:
#     sentence splitting is a parser. Keyword-based detection is a floor, not a
#     ceiling — a rule phrased without a keyword is invisible here, which is why
#     markers are ALLOWED on any line and why the two-way check exists. The
#     binding verbs were added in slice 4/9 after a sweep found overclaims that
#     said the system *refuses* something rather than that you *must not* do it.
#   unit — the span a marker covers. In prose: a run of non-blank lines, split
#     at every list item, heading and TABLE ROW, so siblings need their own
#     markers (the `## Boundaries` case: two of four entries bind, two do not;
#     the rationalization table: one marked row was covering twenty-eight). In
#     shell: a run of comment lines, split at empty comment lines.
#   blocking path — `exit 2` or a permissionDecision "deny" payload, on a
#     NON-COMMENT line. Comment lines are excluded deliberately: a grep that
#     counted `exit 2` inside a comment disclaiming it already produced one
#     false finding in this epic.
#
# Usage:
#   bash tests/marker-verify.sh                 # the three governed surfaces
#   bash tests/marker-verify.sh <path>...       # named surfaces (fixtures, etc)
#
# Exit 0 when clean, 1 when any violation is found. Read-only: it never edits a
# surface. Its own behaviour gate is tests/marker-verify.test.sh.
#
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

# How far below a marker its claim reaches, in lines. Generous on purpose: the
# job is to catch enforcement no rule claims, not to police layout.
CLAIM_WINDOW="${MARKER_CLAIM_WINDOW:-30}"

# The two known blocking mechanisms, in one place so the in-file scan and the
# enforcer corroboration can never drift apart. A third mechanism would be
# invisible to both — the wave found two and does not assume there is no third.
RE_EXIT='(^|[^[:alnum:]_])exit[[:space:]]+2([^0-9]|$)'
RE_DENY='permissionDecision.*deny'

if [ "$#" -gt 0 ]; then
  SURFACES=("$@")
else
  SURFACES=(claude-global.md skills/canonical-sdlc/SKILL.md)
  for _h in hooks/*.sh; do
    [ -f "$_h" ] || continue
    case "$_h" in *.test.sh) continue ;; esac   # a test asserting a block is not enforcement
    SURFACES+=("$_h")
  done
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REC="$TMP/records"; VIO="$TMP/violations"
: >"$REC"; : >"$VIO"

# violation <file> <line> <code> <detail>
violation() { printf '%s\t%s\t%s %s:%s %s\n' "$1" "$2" "$3" "$1" "$2" "$4" >>"$VIO"; }

# ---------- scan: one awk pass per surface, emitting flat records ----------
#
# NORM  <file> <line> <covered> <text>    a normative statement
# MARK  <file> <line> <class> <args>      a class marker
# BLOCK <file> <line> <mech> <claimed>    a blocking path

scan() {  # scan <mode:prose|shell> <file>
  awk -v MODE="$1" -v FILEN="$2" -v WINDOW="$CLAIM_WINDOW" \
      -v RE_EXIT="$RE_EXIT" -v RE_DENY="$RE_DENY" '
    function flush_unit(   i) {
      for (i = 1; i <= un; i++)
        if (unorm[i]) printf "NORM\t%s\t%d\t%d\t%s\n", FILEN, uln[i], umark, utxt[i]
      un = 0; umark = 0
    }
    # Non-letters collapse to spaces, then whole words are matched between
    # spaces. This makes the match apostrophe-agnostic ("don'\''t", "don\342\200\231t")
    # without putting a quote inside this awk program.
    function normative(s,   t) {
      t = tolower(s); gsub(/[^a-z]/, " ", t); gsub(/  +/, " ", t); t = " " t " "
      if (t ~ / (never|must|always|mandatory|required|shall) /) return 1
      if (t ~ / do not /) return 1
      if (t ~ / (dont|don t) /) return 1
      # Binding verbs: a rule that says the system REFUSES something is as
      # binding as one that says you must not do it, and the first keyword set
      # could not see any of them. "The flag floor forbids it — you cannot shop
      # rigor below a derivable floor" is the case that found this gap.
      if (t ~ / (cannot|cant|forbid|forbids|forbidden|refuse|refuses|prevents) /) return 1
      if (t ~ / (can t|no way to|will not|is barred) /) return 1
      return 0
    }
    function scan_markers(s, ln,   rest, tok, inner, cls, args, p) {
      rest = s
      while (match(rest, /\[(WALL|FORM|INSTRUMENT|UNENFORCED)(:[^]]*)?\]/)) {
        tok  = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        inner = substr(tok, 2, length(tok) - 2)
        p = index(inner, ":")
        if (p > 0) { cls = substr(inner, 1, p - 1); args = substr(inner, p + 1) }
        else       { cls = inner; args = "" }
        sub(/^[ \t]+/, "", args); sub(/[ \t]+$/, "", args)
        printf "MARK\t%s\t%d\t%s\t%s\n", FILEN, ln, cls, args
        umark = 1
        if (cls == "WALL" || cls == "FORM") last_wf = ln
      }
    }
    function collect(s, ln,   t) {
      un++
      uln[un] = ln
      t = s; sub(/^[[:space:]]+/, "", t)
      utxt[un] = (length(t) > 100) ? substr(t, 1, 97) "..." : t
      unorm[un] = normative(s)
      scan_markers(s, ln)
    }
    { sub(/\r$/, "") }

    MODE == "prose" && FNR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
    MODE == "prose" && fm { if ($0 ~ /^---[[:space:]]*$/) fm = 0; next }
    MODE == "prose" && /^[[:space:]]*(```|~~~)/ { flush_unit(); fence = !fence; next }
    MODE == "prose" && fence { next }
    MODE == "prose" && /^[[:space:]]*$/ { flush_unit(); next }
    MODE == "prose" {
      if ($0 ~ /^[[:space:]]*([-*+]|[0-9]+[.)])[[:space:]]/ || $0 ~ /^#{1,6}[[:space:]]/ || $0 ~ /^[[:space:]]*\|/) flush_unit()
      collect($0, FNR)
      next
    }

    # shell: markers and normative statements live in comments, blocking paths
    # never do.
    /^[[:space:]]*#/ {
      ctext = $0; sub(/^[[:space:]]*#+[[:space:]]*/, "", ctext)
      if (ctext == "") { flush_unit(); next }
      collect($0, FNR)
      next
    }
    {
      flush_unit()
      mech = ""
      if ($0 ~ RE_EXIT)      mech = "exit2"
      else if ($0 ~ RE_DENY) mech = "deny"
      if (mech != "") {
        claimed = (last_wf > 0 && FNR - last_wf <= WINDOW) ? 1 : 0
        printf "BLOCK\t%s\t%d\t%s\t%d\n", FILEN, FNR, mech, claimed
      }
      next
    }
    END { flush_unit() }
  ' "$2"
}

# has_blocking <file> — a blocking path on a non-comment line
has_blocking() {
  [ -f "$1" ] || return 1
  awk -v RE_EXIT="$RE_EXIT" -v RE_DENY="$RE_DENY" '
    /^[[:space:]]*#/ { next }
    ($0 ~ RE_EXIT) || ($0 ~ RE_DENY) { found = 1 }
    END { exit (found ? 0 : 1) }
  ' "$1"
}

missing_surface=0
for f in "${SURFACES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "marker-verify: no such surface: $f" >&2
    missing_surface=1
    continue
  fi
  case "$f" in
    *.sh) scan shell "$f" >>"$REC" ;;
    *)    scan prose "$f" >>"$REC" ;;
  esac
done
[ "$missing_surface" -eq 0 ] || exit 1

# ---------- pointer resolution (needs the filesystem, so: bash, not awk) ----------

while IFS=$'\t' read -r kind file line cls args; do
  [ "$kind" = "MARK" ] || continue
  case "$cls" in
    INSTRUMENT|UNENFORCED)
      [ -z "$args" ] || violation "$file" "$line" E-UNEXPECTED-POINTER \
        "$cls carries a test pointer ($args); only WALL/FORM do"
      continue
      ;;
  esac

  if [ -z "$args" ]; then
    violation "$file" "$line" E-MISSING-POINTER "$cls claims to bind but names no test"
    continue
  fi

  tests=""; enforcers=""
  IFS=',' read -r -a parts <<<"$args"
  for p in "${parts[@]}"; do
    p="${p#"${p%%[![:space:]]*}"}"; p="${p%"${p##*[![:space:]]}"}"
    [ -n "$p" ] || continue
    [ -e "$p" ] || violation "$file" "$line" E-POINTER-MISSING "pointer does not resolve: $p"
    case "$p" in
      *.test.sh) tests="$tests $p" ;;
      *)         enforcers="$enforcers $p" ;;
    esac
  done

  if [ -z "$tests" ]; then
    violation "$file" "$line" E-POINTER-NOTEST "$cls names no *.test.sh: $args"
  fi

  if [ -z "$enforcers" ]; then
    for t in $tests; do
      d="${t%.test.sh}.sh"
      if [ "$d" = "$t" ]; then
        violation "$file" "$line" E-ENFORCER-UNRESOLVED "cannot derive an enforcer from $t"
      else
        enforcers="$enforcers $d"
      fi
    done
  fi

  for e in $enforcers; do
    if [ ! -f "$e" ]; then
      violation "$file" "$line" E-POINTER-MISSING "enforcer does not resolve: $e"
    elif ! has_blocking "$e"; then
      violation "$file" "$line" E-NO-BLOCKING \
        "$cls claims enforcement but $e contains no blocking path (exit 2 / permissionDecision deny)"
    fi
  done
done <"$REC"

# ---------- record-derived violations + summary ----------

awk -F'\t' '
  $1 == "NORM"  && $4 == 0 { printf "%s\t%s\tE-UNMARKED %s:%s normative statement carries no class marker: %s\n", $2, $3, $2, $3, $5 }
  $1 == "BLOCK" && $5 == 0 { printf "%s\t%s\tE-UNCLAIMED-BLOCK %s:%s blocking path (mechanism=%s) is claimed by no marker\n", $2, $3, $2, $3, $4 }
' "$REC" >>"$VIO"

echo "== marker-verify =="
awk -F'\t' -v surfaces="$(printf '%s ' "${SURFACES[@]}")" '
  $1 == "NORM"  { norm[$2]++; if ($4 == 0) unmark[$2]++ }
  $1 == "MARK"  { marks[$2]++; cls[$4]++ }
  $1 == "BLOCK" { sites[$2]++; if ($5 == 0) unclaimed[$2]++; shell[$2] = 1 }
  END {
    n = split(surfaces, S, " ")
    tn = tu = ts = tc = 0
    for (i = 1; i <= n; i++) {
      f = S[i]; if (f == "") continue
      printf "surface  %s  normative=%d unmarked=%d markers=%d\n", f, norm[f] + 0, unmark[f] + 0, marks[f] + 0
      if (f ~ /\.sh$/)
        printf "blocking %s  sites=%d unclaimed=%d\n", f, sites[f] + 0, unclaimed[f] + 0
      tn += norm[f]; tu += unmark[f]; ts += sites[f]; tc += unclaimed[f]
    }
    printf "class    WALL=%d FORM=%d INSTRUMENT=%d UNENFORCED=%d\n", cls["WALL"] + 0, cls["FORM"] + 0, cls["INSTRUMENT"] + 0, cls["UNENFORCED"] + 0
    printf "total    normative=%d unmarked=%d sites=%d unclaimed=%d\n", tn, tu, ts, tc
  }
' "$REC"

nvio=$(wc -l <"$VIO" | tr -d ' ')
if [ "$nvio" -gt 0 ]; then
  echo "--"
  sort -t$'\t' -k1,1 -k2,2n "$VIO" | cut -f3-
fi
echo "violations=$nvio"
[ "$nvio" -eq 0 ]
