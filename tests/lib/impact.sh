#!/bin/bash
# tests/lib/impact.sh — the ONE impacted-suite derivation.
# wave-01-verification-cannot-lie slice S12, spec AC-18. Design ledger D2:
# "the tree owns impact".
#
#     bash tests/lib/impact.sh <file>...   →   suite<TAB>reason   (one per suite)
#
# WHAT IT ANSWERS. Given the files a change touches, which gating suites read
# them. It is the single owner of that question: the dispatch wall records its
# answer on the roster row, the writer-side budget guard refuses suites outside
# it, and the landing reconcile re-asks it of the actual diff. One derivation,
# three consumers — so a suite this program cannot see is invisible to all three
# at once, which is why the completeness criterion (AC-19) is a planted edit
# against real suites and not a reading of this file.
#
# WHAT IT IS NOT. Not a gate. The Step-5 tests floor still runs every suite on
# every change, unconditionally (AC-23). This governs DISPATCH — how wide a
# writer's instrument may be — and an over-broad answer costs compute while an
# under-broad one costs a missed regression. It is therefore built to be SOUND
# rather than tight: every rule below over-approximates on purpose.
#
# ── THE EDGE KINDS ───────────────────────────────────────────────────────────
#
#   self               the file IS the suite
#   source             the suite sources the file
#   anchor             the suite doctors it (`grep -v` / `sed`) — a moved anchor
#                      fails SILENTLY, so it is called out by name
#   pin                the suite pins its text (`grep -q` / `has_pin`)
#   path-ref           the suite names the path
#   payload-copy       the suite names the payload ROOT and so reads every file
#                      under it (the ten whole-payload copiers)
#   dir-ref            the suite names some other directory; same expansion
#   transitive-lib     a tests/lib helper the suite sources reads the file
#   transitive-doctor  payload/scripts/doctor.sh sources the file and the suite
#                      reads doctor.sh
#   transitive-script  the same, for the other payload/scripts/*.sh
#   transitive-hook    a hook the suite runs sources the file
#
# The reason column reports the STRONGEST kind found, in the order listed above.
# It is diagnosis, not gating: a consumer that only needs the set does `cut -f1`.
#
# ── WHY EACH RULE EXISTS (research-code-map.md §3.4–§3.5, all measured) ───────
#
# FOUR ROOT ALIASES.  `payload/hooks` is a symlink to `../hooks` and the three
# payload skills are symlinks to `../../skills/*`, so `hooks/X`,
# `payload/hooks/X`, `$BIONIC_HOOKS_DIR/X` and `$BIONIC_HOOKS_DIR/../payload/
# hooks/X` are four spellings of ONE file. Every path is canonicalised to the
# non-symlinked spelling before anything is compared. The alias map is READ FROM
# THE TREE at each run, never hardcoded, so a new symlink is handled the day it
# lands rather than the day someone remembers this file.
#
# DIRECTORIES EXPAND.  Ten suites name `${REPO}/payload` and copy it whole; three
# cross-gate trees glob `"$BIONIC_HOOKS_DIR"/*.sh`. Code map §3.4: these "name a
# DIRECTORY — the derivation must expand it to every file under it, or these ten
# suites read nothing". A directory reference therefore covers every path beneath
# it, INCLUDING what its symlinks reach: `payload` covers `hooks/…`, because
# `payload/hooks` is `hooks`.
#
# TRANSITIVE READS.  Code map §3.5 names two hops a per-suite grep cannot see.
# `tests/lib/bound-marker.sh` sources `payload/scripts/lib/run.sh` and
# `binding.sh`, so its six consumers read both without naming either. And ten
# suites execute `payload/scripts/doctor.sh`, which sources eight libraries —
# the reason the FIX_LINES_OTHER defect surfaced in four suites that never
# mention doctor.sh's printer. Both hops are followed.
#
# WHY THE REPO ROOT IS NOT AN EDGE.  `REPO="${BIONIC_SCRIPTS_DIR}"` resolves to
# the root itself. Treating that as a directory reference would make every suite
# read every file and the answer would be the roster, always. A path expression
# must name something BELOW a root to count.
#
# bash 3.2 (ADR-001), awk, grep, sed. No associative arrays, no `mapfile`, no
# process substitution, no GNU-only flags.
#
# Environment:
#   BIONIC_IMPACT_ROOT   the tree to derive over (default: this file's repo)

set -uo pipefail

_impact_usage() {
  cat >&2 <<'EOF'
usage: bash tests/lib/impact.sh <file>...

Prints the gating suites that read the given files, one line per suite:

    <suite.test.sh><TAB><reason>:<file>

Paths may be repo-relative or absolute, and may be spelled through any of the
root aliases (hooks/X, payload/hooks/X). Exit 0 with no output means no suite
in the roster reads any of them.
EOF
  exit 2
}

[ "$#" -gt 0 ] || _impact_usage

if [ -n "${BIONIC_IMPACT_ROOT:-}" ]; then
  ROOT="$(cd "$BIONIC_IMPACT_ROOT" 2>/dev/null && pwd -P)" || {
    echo "impact.sh: BIONIC_IMPACT_ROOT is not a directory: $BIONIC_IMPACT_ROOT" >&2
    exit 3
  }
else
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd -P)" || {
    echo "impact.sh: cannot resolve the repo root from ${BASH_SOURCE[0]:-$0}" >&2
    exit 3
  }
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── path normalisation ───────────────────────────────────────────────────────
# `.` and `..` collapsed lexically, because a path that names a file the change
# DELETES still has to canonicalise.
_norm() {
  local p="$1" out="" seg oldifs
  case "$p" in /*) p="${p#/}" ;; esac
  oldifs="$IFS"; IFS='/'
  # shellcheck disable=SC2086  # deliberate split on /
  set -- $p
  IFS="$oldifs"
  for seg in "$@"; do
    case "$seg" in
      ''|.) : ;;
      ..) case "$out" in */*) out="${out%/*}" ;; *) out='' ;; esac ;;
      *) out="${out:+$out/}$seg" ;;
    esac
  done
  printf '%s\n' "$out"
}

# ── the symlink alias map, read from the tree ────────────────────────────────
# One `link<TAB>target` line per symlink under the checkout. Both sides are
# repo-relative and normalised, so applying the map is a prefix substitution.
find "$ROOT" -type l \
  -not -path "$ROOT/.git/*" -not -path "$ROOT/.worktrees/*" 2>/dev/null \
| while IFS= read -r lnk; do
    rel="${lnk#$ROOT/}"
    tgt="$(readlink "$lnk")" || continue
    case "$tgt" in
      /*) tgt="${tgt#$ROOT/}" ;;
      *)  tgt="$(dirname "$rel")/$tgt" ;;
    esac
    printf '%s\t%s\n' "$(_norm "$rel")" "$(_norm "$tgt")"
  done | sort -u >"$WORK/aliases"

# _dealias <path> — rewrite through the alias map until it stops changing.
# Longest link first, so payload/skills/canonical-sdlc beats payload/skills.
_dealias() {
  local p="$1" i=0 prev lnk tgt
  while [ "$i" -lt 5 ]; do
    prev="$p"
    while IFS="$(printf '\t')" read -r lnk tgt; do
      [ -n "$lnk" ] || continue
      case "$p" in
        "$lnk") p="$tgt"; break ;;
        "$lnk"/*) p="$tgt/${p#$lnk/}"; break ;;
      esac
    done <"$WORK/aliases_bylen"
    [ "$p" = "$prev" ] && break
    i=$((i + 1))
  done
  printf '%s\n' "$p"
}
awk -F'\t' '{print length($1) "\t" $0}' "$WORK/aliases" \
  | sort -rn | cut -f2- >"$WORK/aliases_bylen"

# _canon <path> — any spelling in, the one canonical repo-relative spelling out.
# An absolute path is stripped of the root prefix. A textual strip is not enough:
# the caller's spelling of the root can differ from `pwd -P`'s through a
# symlinked ancestor (/tmp is /private/tmp on this platform), so a path that does
# not match textually is resolved physically through its own directory before the
# strip is retried.
_canon() {
  local p="$1" d b
  case "$p" in
    "$ROOT") p='' ;;
    "$ROOT"/*) p="${p#$ROOT/}" ;;
    /*)
      d="$(dirname "$p")"; b="$(basename "$p")"
      d="$(cd "$d" 2>/dev/null && pwd -P)" || d=""
      if [ -n "$d" ]; then
        case "$d" in
          "$ROOT") p="$b" ;;
          "$ROOT"/*) p="${d#$ROOT/}/$b" ;;
        esac
      fi
      ;;
  esac
  _dealias "$(_norm "$p")"
}

# ── the raw extraction ───────────────────────────────────────────────────────
# One awk pass over every suite, every tests/lib helper and every payload script.
# It emits `owner<TAB>kind<TAB>rawpath`, where rawpath is still repo-relative but
# not yet de-aliased. Three things happen per line, in this order: an assignment
# extends the variable table; a source line contributes a `<ownerdir>/lib/<x>.sh`
# candidate; every root-rooted path expression on the line becomes an edge whose
# kind is read off the line's own shape.
cat >"$WORK/extract.awk" <<'AWK'
function rootrel(f,   s) { s = f; sub("^" ROOTRE "/", "", s); return s }

function resolve(tok,   v, rest, p) {
  if (!match(tok, /^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/)) return ""
  v = substr(tok, 1, RLENGTH)
  rest = substr(tok, RLENGTH + 1)
  gsub(/[$}{]/, "", v)
  if (!(v in VAR)) return ""
  p = VAR[v] rest
  sub(/^\//, "", p)
  return p
}

FNR == 1 {
  split("", VAR)
  VAR["REPO"] = ""; VAR["REPO_ROOT"] = ""; VAR["BIONIC_SCRIPTS_DIR"] = ""
  VAR["BIONIC_HOOKS_DIR"] = "hooks"; VAR["BIONIC_SKILLS_DIR"] = "skills"
  OWNER = rootrel(FILENAME)
  OWNERDIR = OWNER; sub(/\/[^\/]*$/, "", OWNERDIR)
}

# a whole-line comment names paths it does not read
/^[[:space:]]*#/ { next }

{
  line = $0

  # (1) the variable table. `PAYLOAD="${REPO}/payload"` is how the ten
  #     whole-payload copiers are found, so assignments have to be followed.
  if (match(line, /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=/)) {
    nm = substr(line, RSTART, RLENGTH - 1)
    gsub(/[[:space:]]/, "", nm)
    val = substr(line, RSTART + RLENGTH)
    gsub(/^["'\'']/, "", val)
    sub(/["'\''][[:space:]]*$/, "", val)
    # THE OVERRIDE-SEAM IDIOM. Half the suites write
    # `X="${X_UNDER_TEST:-${REPO}/hooks/y.sh}"` (session-poker.test.sh:32) so a
    # caller can point one file somewhere else. The override name is never a
    # path; the DEFAULT is, and it is what the suite reads on an ordinary run.
    if (match(val, /^\$\{[A-Za-z_][A-Za-z0-9_]*:-/)) {
      val = substr(val, RLENGTH + 1)
      sub(/\}[[:space:]]*$/, "", val)
    }
    rp = resolve(val)
    if (rp != "") VAR[nm] = rp
  }

  # (2) the line's shape decides the kind. An anchor is a doctoring — it fails
  #     silently when the text moves — and a pin fails loudly, so they are
  #     distinguished even though both are reads.
  issrc = (line ~ /^[[:space:]]*(\.|source)[[:space:]]/)
  if (line ~ /grep[[:space:]]+-[a-zA-Z]*v|[^A-Za-z_]sed[[:space:]]/) kind = "anchor"
  else if (line ~ /grep[[:space:]]+-[a-zA-Z]*q|has_pin/) kind = "pin"
  else kind = "path-ref"
  if (issrc) kind = "source"

  # (3) the sourcing candidate. Both `. "$(dirname "$0")/lib/x.sh"` in a suite
  #     and `. "${DOCTOR_LIB}/x.sh"` in doctor.sh source a sibling library, but
  #     they spell the directory differently and doctor.sh's spelling contains no
  #     literal `lib/` at all — DOCTOR_LIB is assigned from `_doctor_self_dir`
  #     eleven lines earlier. So the BASENAME is what is read off the line, and
  #     the owner's own directory supplies the rest. Two candidates are offered,
  #     `<ownerdir>/lib/<base>` and `<ownerdir>/<base>`; the caller keeps only the
  #     one that names a real file, so a guess that matches nothing costs nothing.
  if (issrc) {
    t = line; base = ""
    while (match(t, /[A-Za-z0-9_.-]+\.sh/)) {
      base = substr(t, RSTART, RLENGTH)
      t = substr(t, RSTART + RLENGTH)
    }
    if (base != "") {
      print OWNER "\t" "source?" "\t" OWNERDIR "/lib/" base
      print OWNER "\t" "source?" "\t" OWNERDIR "/" base
      # A hook spells its library directory `$BIONIC_LIB`, assigned from a
      # FUNCTION ARGUMENT at run time (hooks/stop-check.sh:261) — no static
      # reading resolves it. So every library directory in the tree is offered
      # as a candidate and the existence filter picks the real one.
      nld = split(LIBDIRS, LD, " ")
      for (li = 1; li <= nld; li++)
        if (LD[li] != "") print OWNER "\t" "source?" "\t" LD[li] "/" base
    }
  }

  # (3b) a SIBLING of a resolved path. `bash "$(dirname "$POKER")/protect-main.sh"`
  #      (session-poker.test.sh:2491) names a second hook without naming its
  #      directory, and the planted-edit proof caught the miss: mutating
  #      protect-main.sh turned session-poker.test.sh red while the derivation
  #      said it could not.
  t = line
  while (match(t, /\$\(dirname[[:space:]]+"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"\)\/[A-Za-z0-9_.@\/-]*/)) {
    tok = substr(t, RSTART, RLENGTH)
    t = substr(t, RSTART + RLENGTH)
    if (match(tok, /\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"\)/)) {
      vn = substr(tok, RSTART, RLENGTH)
      gsub(/[$}{"\)]/, "", vn)
      if (vn in VAR) {
        base = tok; sub(/^.*\)\//, "", base)
        pp = VAR[vn]
        if (pp ~ /\//) sub(/\/[^\/]*$/, "", pp); else pp = ""
        if (base != "") print OWNER "\t" kind "\t" (pp == "" ? base : pp "/" base)
      }
    }
  }

  # (4) every root-rooted path expression on the line, INCLUDING a bare `$VAR`
  #     that an earlier assignment resolved to a path. docs-pins.test.sh:768
  #     doctors `"$POKER_SH"`, assigned 238 lines earlier — a scan that insisted
  #     on a literal `/` after the variable would read that anchor as no edge at
  #     all. Variables holding the bare repo root resolve to "" and are dropped,
  #     which is what keeps `REPO="${BIONIC_SCRIPTS_DIR}"` from meaning "every
  #     file in the tree".
  s = line
  while (match(s, /\$\{?[A-Za-z_][A-Za-z0-9_]*\}?(\/[A-Za-z0-9_.@\/-]*)?/)) {
    tok = substr(s, RSTART, RLENGTH)
    s = substr(s, RSTART + RLENGTH)
    p = resolve(tok)
    if (p == "" || p == "/") continue
    print OWNER "\t" kind "\t" p
    # $BIONIC_HOOKS_DIR's parent is the repo root in the checkout and the plugin
    # root inside a fixture, so `$BIONIC_HOOKS_DIR/../x` has two readings. Emit
    # both; the one that names no file is never queried.
    if (p ~ /^hooks\/\.\./) {
      q = p; sub(/^hooks\/\.\./, "payload", q)
      print OWNER "\t" kind "\t" q
    }
  }
}
AWK

# Every library directory in the tree, repo-relative — the candidate roots for a
# source line whose directory cannot be read statically.
LIBDIRS="$(find "$ROOT" -type d -name lib \
  -not -path "$ROOT/.git/*" -not -path "$ROOT/.worktrees/*" 2>/dev/null \
  | sed "s|^$ROOT/||" | sort -u | tr '\n' ' ')"

# HOOKS ARE OWNERS TOO. A suite that runs `hooks/session-start.sh` reads every
# library that hook sources, and the planted-edit proof measured the cost of
# leaving them out: wiping payload/scripts/lib/patrol.sh turned four suites red
# that the derivation could not see, all of them reading it through a hook.
EXTRACT_FILES=""
for f in "$ROOT"/tests/*.test.sh "$ROOT"/tests/lib/*.sh \
         "$ROOT"/payload/scripts/*.sh "$ROOT"/hooks/*.sh; do
  [ -f "$f" ] && EXTRACT_FILES="$EXTRACT_FILES $f"
done
# shellcheck disable=SC2086  # deliberate split of the file list
awk -v ROOTRE="$ROOT" -v LIBDIRS="$LIBDIRS" -f "$WORK/extract.awk" \
  $EXTRACT_FILES 2>/dev/null >"$WORK/raw" || :

# ── canonicalise, and settle the sourcing candidates ─────────────────────────
# `source?` is a guess built from the owner's own directory; it becomes a real
# `source` edge only if that file exists. Everything else is de-aliased.
# Done in awk rather than a shell loop: there are a few thousand raw edges and a
# per-edge shell function call turns a sub-second derivation into a four-second
# one, which the dispatch wall pays on every brief.
cat >"$WORK/canon.awk" <<'AWK'
function norm(p,   n, i, seg, out) {
  sub(/^\//, "", p)
  n = split(p, S, "/")
  out = ""
  for (i = 1; i <= n; i++) {
    seg = S[i]
    if (seg == "" || seg == ".") continue
    if (seg == "..") { if (out ~ /\//) sub(/\/[^\/]*$/, "", out); else out = "" }
    else out = (out == "" ? seg : out "/" seg)
  }
  return out
}
function dealias(p,   i, j, changed) {
  for (j = 0; j < 5; j++) {
    changed = 0
    for (i = 1; i <= NL; i++) {
      if (p == LNK[i]) { p = TGT[i]; changed = 1; break }
      if (index(p, LNK[i] "/") == 1) { p = TGT[i] substr(p, length(LNK[i]) + 1); changed = 1; break }
    }
    if (!changed) break
  }
  return p
}
# FILENAME, not NR==FNR: the alias file is legitimately empty in a tree with no
# symlinks, and `NR == FNR` then swallows the SECOND file as if it were the first.
FILENAME == AF { NL++; LNK[NL] = $1; TGT[NL] = $2; next }
{
  p = norm($3)
  if (p == "") next
  if ($2 == "source?") { print $1 "\t" "source" "\t" p "\t" "?"; next }
  print $1 "\t" $2 "\t" dealias(p)
}
AWK
awk -F'\t' -v OFS='\t' -v AF="$WORK/aliases_bylen" -f "$WORK/canon.awk" \
  "$WORK/aliases_bylen" "$WORK/raw" \
  | sort -u >"$WORK/canon"

# A `source?` candidate is a guess built from the owner's own directory; it
# becomes a real edge only if that file exists.
: >"$WORK/edges"
awk -F'\t' '$4 == "?"' "$WORK/canon" | while IFS="$(printf '\t')" read -r owner kind path _q; do
  [ -f "$ROOT/$path" ] && printf '%s\t%s\t%s\n' "$owner" "$kind" "$(_dealias "$path")"
done >>"$WORK/edges"
awk -F'\t' 'NF == 3' "$WORK/canon" >>"$WORK/edges"
sort -u "$WORK/edges" -o "$WORK/edges"

# ── directory edges expand ───────────────────────────────────────────────────
# A reference to a directory is a reference to everything under it. What "under
# it" means is the directory PLUS every path its symlinks reach, so `payload`
# covers `hooks/…` and `skills/canonical-sdlc/…`. The repo root itself is
# excluded: it would cover the whole tree and make every answer the roster.
: >"$WORK/dircov"
cut -f3 "$WORK/edges" | sort -u | while IFS= read -r p; do
  [ -n "$p" ] || continue
  [ -d "$ROOT/$p" ] || continue
  printf '%s\t%s\n' "$p" "$p"
  while IFS="$(printf '\t')" read -r lnk tgt; do
    case "$lnk" in
      "$p"|"$p"/*) printf '%s\t%s\n' "$p" "$tgt" ;;
    esac
  done <"$WORK/aliases"
done | sort -u >"$WORK/dircov"

# ── the suite roster, and who sources what ───────────────────────────────────
ls "$ROOT"/tests/*.test.sh 2>/dev/null | sed "s|^$ROOT/tests/||" | sort >"$WORK/suites"

# ── assemble every edge, direct and transitive ───────────────────────────────
# Written as `suite<TAB>kind<TAB>path`, with directory edges flagged so the
# matcher knows to compare by prefix rather than by equality.
: >"$WORK/all"

# self — a change to a suite reaches that suite. Without it a writer could edit
# a suite and be refused permission to run it.
while IFS= read -r s; do
  printf '%s\tself\tF:tests/%s\n' "$s" "$s"
done <"$WORK/suites" >>"$WORK/all"

# _emit_for <suite> <kind> <owner-of-the-edges>
_emit_for() {
  local suite="$1" kind="$2" owner="$3"
  awk -F'\t' -v o="$owner" -v s="$suite" -v k="$kind" '
    $1 == o { print s "\t" (k == "" ? $2 : k) "\t" $3 }' "$WORK/edges"
}

# direct edges — the suite's own lines.
awk -F'\t' '$1 ~ /^tests\/[^\/]*\.test\.sh$/ {
  sub(/^tests\//, "", $1); print $1 "\t" $2 "\t" $3 }' "$WORK/edges" >>"$WORK/all"

# transitive through tests/lib — a helper the suite sources reads files the
# suite never names (code map §3.5: bound-marker's six consumers). Iterated, so
# a helper that sources a helper is followed too.
awk -F'\t' '$2 == "source" && $3 ~ /^tests\/lib\// { print }' "$WORK/all" | sort -u >"$WORK/suite_libs"
# one hop, then a second for a helper that sources a helper
for hop in 1 2; do
  while IFS="$(printf '\t')" read -r suite _k lib; do
    [ -n "$suite" ] || continue
    _emit_for "$suite" "transitive-lib" "$lib"
  done <"$WORK/suite_libs" >>"$WORK/all"
  awk -F'\t' '$2 == "transitive-lib" && $3 ~ /^tests\/lib\// { print }' "$WORK/all" \
    | sort -u >"$WORK/suite_libs.next"
  if cmp -s "$WORK/suite_libs" "$WORK/suite_libs.next"; then break; fi
  mv "$WORK/suite_libs.next" "$WORK/suite_libs"
done
rm -f "$WORK/suite_libs.next" "$WORK/all.prev"

# transitive through a payload script — ten suites execute doctor.sh, which
# sources eight libraries none of them names (code map §3.5).
awk -F'\t' '$3 ~ /^payload\/scripts\/[^\/]*\.sh$/ || $3 ~ /^hooks\/[^\/]*\.sh$/ {
  print $1 "\t" $3 }' "$WORK/all" | sort -u >"$WORK/suite_scripts"
while IFS="$(printf '\t')" read -r suite script; do
  [ -n "$suite" ] || continue
  case "$script" in
    payload/scripts/doctor.sh) k="transitive-doctor" ;;
    hooks/*) k="transitive-hook" ;;
    *) k="transitive-script" ;;
  esac
  awk -F'\t' -v o="$script" -v s="$suite" -v k="$k" '
    $1 == o && $2 == "source" { print s "\t" k "\t" $3 }' "$WORK/edges"
done <"$WORK/suite_scripts" >>"$WORK/all"

# flag directory edges, and label the payload root as what it is. A directory
# edge becomes one line per prefix it covers — the directory itself plus every
# path its symlinks reach — so `payload` reaches `hooks/session-poker.sh`.
awk -F'\t' -v OFS='\t' '
  FILENAME == CF { COV[$1] = ($1 in COV ? COV[$1] "\n" : "") $2; next }
  {
    if ($3 ~ /^F:/) { print; next }
    if ($3 in COV) {
      n = split(COV[$3], C, "\n")
      for (i = 1; i <= n; i++)
        print $1, ($3 == "payload" ? "payload-copy" : "dir-ref"), "D:" C[i]
    } else print $1, $2, "F:" $3
  }
' CF="$WORK/dircov" "$WORK/dircov" "$WORK/all" | sort -u >"$WORK/all.flagged"
mv "$WORK/all.flagged" "$WORK/all"

# ── answer the query ─────────────────────────────────────────────────────────
: >"$WORK/query"
for a in "$@"; do
  c="$(_canon "$a")"
  [ -n "$c" ] && printf '%s\n' "$c" >>"$WORK/query"
done
sort -u "$WORK/query" -o "$WORK/query"

awk -F'\t' '
  function rank(k) {
    if (k == "self") return 1
    if (k == "source") return 2
    if (k == "anchor") return 3
    if (k == "pin") return 4
    if (k == "path-ref") return 5
    if (k == "transitive-lib") return 6
    if (k == "transitive-doctor") return 7
    if (k == "transitive-script") return 8
    if (k == "transitive-hook") return 9
    if (k == "payload-copy") return 10
    return 11
  }
  function better(suite, k, q,   r) {
    r = rank(k)
    if (!(suite in BEST) || r < BEST[suite] || (r == BEST[suite] && q < BESTQ[suite])) {
      BEST[suite] = r; BESTK[suite] = k; BESTQ[suite] = q
    }
  }
  FILENAME == QF { Q[++nq] = $0; next }
  {
    suite = $1; kind = $2; path = $3
    if (path ~ /^F:/) {
      p = substr(path, 3)
      for (i = 1; i <= nq; i++) if (Q[i] == p) better(suite, kind, Q[i])
    } else {
      d = substr(path, 3)
      for (i = 1; i <= nq; i++)
        if (Q[i] == d || index(Q[i], d "/") == 1) better(suite, kind, Q[i])
    }
  }
  END { for (s in BEST) print s "\t" BESTK[s] ":" BESTQ[s] }
' QF="$WORK/query" "$WORK/query" "$WORK/all" | sort
