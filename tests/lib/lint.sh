#!/bin/bash
# tests/lib/lint.sh — the project's static checks, over a whole tree or over the files a row changed.
#
#   bash tests/lib/lint.sh <root> [<path>...]   each path relative to <root>; with none, read from stdin, one a line
#
# Prints one `<CHECK> <file>[:<line>] <what>` line per hit and exits 1; 0 when there is none; 2, with the reason on
# stderr, when a check cannot be run. Each check is a property of the files it reads, so a run over the files a row
# changed answers as a run over the whole tree would for those files, in seconds. The landing line runs the
# candidate's own copy of this file at every landing, whatever the row's landing set names (payload/scripts/lib/line.sh
# `_line_lints`); tests/shell-lint.test.sh sources it and proves its programs over the whole tree, and
# tests/one-reader.test.sh runs its REFUSALS over a planted hook.
#
#   EXIT      a hook or payload script whose refusals with no exit are over its line in tests/lib/refusal-exits.ceiling,
#             or under it with the line not lowered; a ceiling line it cannot read, when the row changed that file
#   BP        a writer piped into a reader that quits early where the status is read, not in tests/lib/quitting-readers.allow;
#             an allow line it cannot read, when the row changed that file
#   HEADER    a suite header that lists a section its body lacks, or omits one its body has
#   REFUSALS  a refusal call, as payload/scripts/one-reader-check.sh finds one, in a registered hook's own file
#
# What a row changed decides what is read: a changed ceiling widens EXIT to every file it names, a changed allow file
# is read for its own faults, and a changed hooks/hooks.json widens REFUSALS to every hook.
# Sourced, it defines its programs under $LINT_TMP (a directory the caller owns) and runs nothing. bash 3.2.

set -uo pipefail

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  LINT_TMP="$(mktemp -d "${TMPDIR:-/tmp}/lint.XXXXXX")" || { echo "lint.sh: no temporary directory" >&2; exit 2; }
  trap 'rm -rf "$LINT_TMP"' EXIT
fi
if [ -z "${LINT_TMP:-}" ] || [ ! -d "${LINT_TMP:-}" ]; then
  echo "lint.sh: LINT_TMP names no directory" >&2
  return 2 2>/dev/null || exit 2
fi

# exit_roster <root> -> the files EXIT reads: every *.sh under hooks/ and payload/scripts/, sorted
exit_roster() { ( cd "$1" 2>/dev/null && find hooks payload/scripts -name '*.sh' -type f 2>/dev/null | LC_ALL=C sort ); }
# quit_roster <root> -> the files BP reads: the same, and the files of the declared check's closure and this one
quit_roster() {
  ( cd "$1" 2>/dev/null && { find hooks payload/scripts -name '*.sh' -type f
    printf '%s\n' tests/lib/release-check.sh tests/lib/name-scan.sh tests/lib/lint.sh; } 2>/dev/null | LC_ALL=C sort )
}

QUIT_AWK="$LINT_TMP/quit.awk"
cat > "$QUIT_AWK" <<'QUIT_AWK_EOF'
# QUITTING READERS. A writer piped into a reader that quits early (grep -q, -l or -m, head, an awk that
# exits) is sent SIGPIPE once its output outruns the 64 KB pipe buffer; under pipefail the pipeline then
# reports the writer's 141, and a test of its status reads a present line as absent.
#
# Run once per file with -v ALLOW=<allow file> -v ROSTER=<file listing every path swept>, the file's path
# relative to the root as its one argument. -v REPORT=1 on a run over /dev/null prints the allow file's
# own faults. Prints
#   Q<TAB><path>:<line><TAB><the logical line>      a site neither allowed nor excused
#   A<TAB><allow line number><TAB><what is wrong>   an allow line that is refused
function blank(s,   n, i, c, q, o) {  # quoted text becomes underscores, so a quoted ; | && is not read
  n = length(s); q = ""; o = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q == "") {
      if (c == "\\") { o = o c substr(s, i + 1, 1); i++; continue }
      if (c == "'" || c == "\"") { q = c; o = o c; continue }
      o = o c
    } else if (c == q) { q = ""; o = o c }
    else if (q == "\"" && c == "\\") { o = o "__"; i++ }
    else o = o "_"
  }
  return o
}
function strip_comment(s,   b, n, i, c, prev) {
  b = blank(s); n = length(b); prev = " "
  for (i = 1; i <= n; i++) {
    c = substr(b, i, 1)
    if (c == "#" && (prev == " " || prev == "\t" || prev == ";" || prev == "") && i > 1) return substr(s, 1, i - 1)
    prev = c
  }
  return s
}
function open_sq(s,   n, i, c, q) {  # does s end inside a single-quoted string
  n = length(s); q = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q == "'") { if (c == "'") q = ""; continue }
    if (q == "\"") { if (c == "\\") i++; else if (c == "\"") q = ""; continue }
    if (c == "\\") { i++; continue }
    if (c == "'" || c == "\"") q = c
  }
  return q == "'"
}
# s starts right after a pipe: 0 not a quitting reader, 1 a predicate (grep -q, -l), 2 a limiter
function reader(s,   rest, n, i, t, prog) {
  sub(/^[ \t]+/, "", s)
  while (match(s, /^(env|LC_ALL=[A-Za-z0-9_.]+|LANG=[A-Za-z0-9_.]+)[ \t]+/)) s = substr(s, RLENGTH + 1)
  sub(/^(\/usr\/bin\/|\/bin\/)/, "", s)
  if (match(s, /^(grep|egrep|fgrep)[ \t]/)) {
    n = split(substr(s, RLENGTH + 1), T, /[ \t]+/)
    for (i = 1; i <= n; i++) {
      t = T[i]
      if (t == "") continue
      if (t == "--") break
      if (t == "--quiet" || t == "--silent" || t == "--files-with-matches") return 1
      if (t ~ /^--max-count/) return 2
      if (t ~ /^--/) continue
      if (t ~ /^-[A-Za-z0-9]/) {
        if (t ~ /^-[A-Za-z]*[ql]/) return 1
        if (t ~ /^-[A-Za-z]*m/) return 2
        if (t == "-e" || t == "-f") i++
        continue
      }
      break
    }
    return 0
  }
  if (s ~ /^head([ \t]|$)/) return 2
  if (match(s, /^(awk|gawk|mawk)[ \t]/)) {
    prog = s
    gsub(/END[ \t]*\{[^}]*\}/, "", prog)
    return (prog ~ /(^|[^A-Za-z0-9_])exit([^A-Za-z0-9_]|$)/) ? 2 : 0
  }
  return 0
}
# Is the status of the pipeline whose reader starts at `rest` (the text from the reader on) consumed?
# before is the text ahead of the pipe. Inside a command substitution the status is the assignment's,
# so it counts only when the substitution is the value of an assignment and && or || follows it.
function consumed(before, rest, nxt,   b, n, i, c, d, tail, cut, inside, pre) {
  b = blank(rest); n = length(b); d = 0; inside = 0; cut = n + 1
  for (i = 1; i <= n; i++) {
    c = substr(b, i, 1)
    if (c == "(") d++
    else if (c == ")") { if (d == 0) { inside = 1; cut = i; break } d-- }
  }
  if (inside) {
    pre = before
    if (!(pre ~ /[A-Za-z_][A-Za-z0-9_]*\+?=\"?[$][(][^$]*$/ || pre ~ /[A-Za-z_][A-Za-z0-9_]*\+?=\"?`[^`]*$/)) return 0
    tail = substr(b, cut + 1)
  } else tail = b
  sub(/;[ \t]*(then|do)([ \t;]|$).*/, " THEN ", tail)
  sub(/;.*/, "", tail)
  if (tail ~ /THEN/) return 1
  if (tail ~ /&&/) return 1
  if (tail ~ /[|][|]/ && tail !~ /[|][|][ \t]*(true|:)([ \t)]|$)/) return 1
  if (tail ~ /[$][?]/) return 1
  if (tail ~ /^[ \t]*$/ && nxt ~ /^[ \t]*(then|do)([ \t;]|$)/) return 1
  if (nxt ~ /^[ \t]*[A-Za-z_][A-Za-z0-9_]*=[$][?]/ || nxt ~ /^[ \t]*(if|\[\[?)[^#]*[$][?]/) return 1
  return 0
}
BEGIN {
  nallow = 0
  while ((getline al < ALLOW) > 0) {
    alno++
    if (al ~ /^[ \t]*(#|$)/) continue
    reason = ""; entry = al
    k = index(al, " # ")
    if (k > 0) { entry = substr(al, 1, k - 1); reason = substr(al, k + 3) }
    gsub(/^[ \t]+|[ \t]+$/, "", reason)
    c = index(entry, ":")
    if (c == 0) { if (REPORT) printf "A\t%d\tno <path>:<pattern>\n", alno; continue }
    if (reason == "") { if (REPORT) printf "A\t%d\tno reason after a space, a hash and a space\n", alno; continue }
    nallow++; ALNO[nallow] = alno; APATH[nallow] = substr(entry, 1, c - 1); APAT[nallow] = substr(entry, c + 1)
    gsub(/[ \t]+$/, "", APAT[nallow])
  }
  while ((getline r < ROSTER) > 0) IN[r] = 1
  for (a = 1; a <= nallow; a++)
    if (!(APATH[a] in IN)) { if (REPORT) printf "A\t%d\tthe path %s is not in the roster\n", ALNO[a], APATH[a]; APATH[a] = "" }
}
{ P[++nl] = $0 }
END {
  pf = (FILENAME ~ /\/lib\// || FILENAME ~ /^hooks\/poker\//) ? 1 : 0
  for (ln = 1; ln <= nl; ln++)
    if (P[ln] ~ /^[ \t]*set[ \t]/ && P[ln] ~ /pipefail/) pf = 1
  if (!pf) exit
  hd = ""
  for (ln = 1; ln <= nl; ln++) {
    s = P[ln]
    if (hd != "") { t = s; sub(/^\t+/, "", t); if (t == hd) hd = ""; continue }
    if (s ~ /^[ \t]*#/) continue
    start = ln; end = ln
    while (end < nl && end - start < 40 && (s ~ /\\$/ || strip_comment(s) ~ /[|][ \t]*$/ || (s ~ /(awk|gawk|mawk)[ \t]/ && open_sq(s)))) {
      if (s ~ /\\$/) s = substr(s, 1, length(s) - 1)
      end++; s = s " " P[end]
    }
    if (open_sq(s) && end - start >= 40) end = start   # a quote that never closes: read the one line
    if (end == start) s = P[start]
    ln = end
    if (match(s, /<<-?[ \t]*['"]?[A-Za-z_][A-Za-z0-9_]*/) && substr(s, RSTART - 1, 1) != "<" && substr(s, RSTART + 2, 1) != "<") {
      d = substr(s, RSTART, RLENGTH); sub(/^<<-?[ \t]*['"]?/, "", d); hd = d
    }
    s = strip_comment(s)
    if (s !~ /[|]/) continue
    nxt = ""
    for (k = ln + 1; k <= nl; k++) if (P[k] !~ /^[ \t]*$/) { nxt = P[k]; break }
    b = blank(s); n = length(b); site = 0
    for (i = 1; i <= n; i++) {
      if (substr(b, i, 1) != "|") continue
      if (substr(b, i + 1, 1) == "|") { i++; continue }
      if (substr(b, i + 1, 1) == "&") continue
      if (i > 1 && substr(b, i - 1, 1) == "|") continue
      cls = reader(substr(s, i + 1))
      if (cls == 1 && substr(s, i + 1) !~ /[|][|][ \t]*(true|:)([ \t)]|$)/) site = 1
      else if (cls == 2 && consumed(substr(s, 1, i - 1), substr(s, i + 1), nxt)) site = 1
      if (site) break
    }
    if (!site) continue
    ok = 0
    for (a = 1; a <= nallow; a++) if (APATH[a] != "" && APATH[a] == FILENAME && index(s, APAT[a]) > 0) { ok = 1; break }
    if (ok) continue
    printf "Q\t%s:%d\t%s\n", FILENAME, start, s
  }
}
QUIT_AWK_EOF


# quit_sweep <root> <allow file> <relative path>... -> the Q and A rows the awk prints
quit_sweep() {
  local root="$1" allow="$2" roster f
  shift 2
  roster="$(mktemp "$LINT_TMP/quit-roster.XXXXXX")"
  printf '%s\n' "$@" > "$roster"
  ( cd "$root" || exit 1
    LC_ALL=C awk -v REPORT=1 -v ALLOW="$allow" -v ROSTER="$roster" -f "$QUIT_AWK" /dev/null
    for f in "$@"; do
      LC_ALL=C awk -v ALLOW="$allow" -v ROSTER="$roster" -f "$QUIT_AWK" "$f"
    done )
}

EXIT_VERBS="finding-move known-limits-part landing-report proof-add regression-run release-approval
  release-check release-note reviews-part ruling-ack stop-run task-add"
EXIT_WORDS="adopt amend approve bind extend reply ready resume waive"
EXIT_AWK="$LINT_TMP/exit.awk"
cat > "$EXIT_AWK" <<'EXIT_AWK_EOF'
# REFUSALS AND THEIR EXITS. Run once per file with -v VERBS=<hyphenated verbs> -v WORDS=<one-word verbs>, the
# file's path relative to the root as its one argument. Prints
#   X<TAB><path>:<line><TAB><the site's first 80 columns>   a site that names no exit
#   E<TAB><path>:<line>                                      a site that names one
function dq_open(s,   n, i, c, q) {  # does s end inside a double-quoted string
  n = length(s); q = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q == "'") { if (c == "'") q = ""; continue }
    if (q == "\"") { if (c == "\\") i++; else if (c == "\"") q = ""; continue }
    if (c == "\\") { i++; continue }
    if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t;]/)) break
    if (c == "'" || c == "\"") q = c
  }
  return q == "\""
}
function names_exit(s,   t, n, i) {
  t = s
  gsub(/[A-Za-z0-9_.-]+ refused (—|--)/, "", t)
  gsub(/REFUSED (—|--) [a-z][a-z-]*( --[a-z-]+)*:/, "REFUSED —", t)
  if (t ~ /session-poker\.sh [a-z]/ || t ~ /card\.sh [a-z]/ || index(t, "spawn-worktree.sh") || index(t, "close-out.sh")) return 1
  if (index(t, "Fix:") || index(t, "next call:") || index(t, "run again:") || index(t, "needs: ")) return 1
  if (index(t, "set fix-cap") || index(t, "decisions rule")) return 1
  n = split(VERBS, V, /[ \t\n]+/)
  for (i = 1; i <= n; i++) if (V[i] != "" && match(t, "(^|[^A-Za-z0-9_-])" V[i] "([^A-Za-z0-9_-]|$)")) return 1
  n = split(WORDS, W, /[ \t\n]+/)
  for (i = 1; i <= n; i++) if (W[i] != "" && match(t, "(^|[^A-Za-z0-9_-])" W[i] " [-<'$`0-9]")) return 1
  return 0
}
{ P[++nl] = $0 }
END {
  hd = ""
  for (ln = 1; ln <= nl; ln++) {
    s = P[ln]
    if (hd != "") { t = s; sub(/^\t+/, "", t); if (t == hd) hd = ""; continue }
    if (s ~ /^[ \t]*#/) continue
    start = ln; end = ln
    while (end < nl && end - start < 40 && (s ~ /\\$/ || dq_open(s))) {
      if (s ~ /\\$/) s = substr(s, 1, length(s) - 1)
      end++; s = s " " P[end]
    }
    if (dq_open(s) && end - start >= 40) { end = start; s = P[start] }   # a quote that never closes: the one line
    ln = end
    if (match(s, /<<-?[ \t]*['"]?[A-Za-z_][A-Za-z0-9_]*/) && substr(s, RSTART - 1, 1) != "<" && substr(s, RSTART + 2, 1) != "<") {
      d = substr(s, RSTART, RLENGTH); sub(/^<<-?[ \t]*['"]?/, "", d); hd = d
    }
    if (s !~ /REFUSED/ && s !~ /refused (—|--)/) continue
    if (match(s, /(^|[;&|({ \t])refuse[ \t]+[a-z"$]/)) { print "E\t" FILENAME ":" start; continue }
    if (!match(s, /(^|[;&|({ \t])(die|block)[ \t]+"/)) continue
    site = substr(s, RSTART); sub(/^[;&|({ \t]/, "", site)
    if (site ~ /^die[ \t]+"( +bash|Usage)/) continue
    nxt = ""
    for (k = end + 1; k <= nl; k++) if (P[k] !~ /^[ \t]*$/) { nxt = P[k]; break }
    if (names_exit(site) || nxt ~ /^[ \t]*pv_next[ \t]/) { print "E\t" FILENAME ":" start; continue }
    site = substr(site, 1, 80); sub(/[\200-\377]+$/, "", site)   # never end on half a character
    printf "X\t%s:%d\t%s\n", FILENAME, start, site
  }
}
EXIT_AWK_EOF
# THE JUDGE. The sweep's rows on stdin, -v CEIL=<ceiling file> -v NAME=<the name the lower line says>. Prints
#   F<TAB><ceiling line number><TAB><what is wrong>     a ceiling line refused
#   O<TAB><path><TAB><count> over ceiling <n>          a file above its ceiling, then each of its sites:
#   S<TAB><path>:<line><TAB><text>
#   L<TAB>lower <NAME>: <path> <count>                 a file below its ceiling, with the number to write
EXIT_JUDGE_AWK="$LINT_TMP/exit-judge.awk"
cat > "$EXIT_JUDGE_AWK" <<'EXIT_JUDGE_EOF'
BEGIN {
  FS = "\t"
  while ((getline l < CEIL) > 0) {
    no++
    if (l ~ /^[ \t]*(#|$)/) continue
    k = index(l, " # "); reason = ""; entry = l
    if (k > 0) { entry = substr(l, 1, k - 1); reason = substr(l, k + 3) }
    gsub(/^[ \t]+|[ \t]+$/, "", reason)
    n = split(entry, f, /[ \t]+/)
    if (n != 2 || f[2] !~ /^[0-9]+$/) { printf "F\t%d\tnot <path> <count>\n", no; continue }
    if (reason == "") { printf "F\t%d\tno reason after a space, a hash and a space\n", no; continue }
    if (f[1] in C) { printf "F\t%d\t%s is named twice\n", no, f[1]; continue }
    C[f[1]] = f[2] + 0
  }
}
$1 == "X" { p = $2; sub(/:[0-9]+$/, "", p); N[p]++; SITES[p] = SITES[p] "S\t" $2 "\t" $3 "\n" }
END {
  for (p in N) {
    c = (p in C) ? C[p] : 0
    if (N[p] > c) { printf "O\t%s\t%d over ceiling %d: give the new site its exit (a verb, needs: <person> — <why>, or a pv_next line)\n", p, N[p], c; printf "%s", SITES[p] }
  }
  for (p in C) if ((p in N ? N[p] : 0) < C[p]) printf "L\tlower %s: %s %d\n", NAME, p, (p in N ? N[p] : 0)
}
EXIT_JUDGE_EOF

# exit_sweep <root> <relative path>... -> the X and E rows of each file
exit_sweep() {
  local root="$1" f
  shift
  ( cd "$root" || exit 1
    for f in "$@"; do LC_ALL=C awk -v VERBS="$(tr '\n' ' ' <<< "$EXIT_VERBS")" -v WORDS="$EXIT_WORDS" -f "$EXIT_AWK" "$f"; done )
}
# exit_judge <sweep rows> <ceiling file> -> the F, O, S and L rows, sorted
exit_judge() {
  printf '%s\n' "$1" | LC_ALL=C awk -v CEIL="$2" -v NAME="tests/lib/refusal-exits.ceiling" -f "$EXIT_JUDGE_AWK" | LC_ALL=C sort
}

CENSUS_PROG="$LINT_TMP/census-prog.awk"
cat > "$LINT_TMP/census-extract.awk" <<'CENSUS_EXTRACT_EOF'
index($0, "awk '/^[[:space:]]*(setup_)?section") == 1 { on = 1; sub(/^awk '/, "") }
on && (i = index($0, "' tests/<suite>.test.sh")) { print substr($0, 1, i - 1); exit }
on { print }
CENSUS_EXTRACT_EOF
# The file with every heredoc body blanked, line numbers kept. A `<<` opens a body only outside
# quotes (a nested `$( )` has quotes of its own) and not as a here-string, and a body ends at its
# delimiter line.
cat > "$LINT_TMP/census-blank.awk" <<'CENSUS_BLANK_EOF'
function opener(line,   i, n, c, top, rest, d, st) {
  n = length(line); st = "c"
  for (i = 1; i <= n; i++) {
    c = substr(line, i, 1); top = substr(st, length(st), 1)
    if (top == "s") { if (c == "'") st = substr(st, 1, length(st) - 1); continue }
    if (c == "\\") { i++; continue }
    if (top == "d") {
      if (c == "\"") st = substr(st, 1, length(st) - 1)
      else if (c == "$" && substr(line, i + 1, 1) == "(") { st = st "c"; i++ }
      continue
    }
    if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t]/)) return ""
    if (c == "'") { st = st "s"; continue }
    if (c == "\"") { st = st "d"; continue }
    if (c == "$" && substr(line, i + 1, 1) == "(") { st = st "c"; i++; continue }
    if (c == ")" && length(st) > 1) { st = substr(st, 1, length(st) - 1); continue }
    if (c == "<" && substr(line, i, 2) == "<<") {
      if (substr(line, i, 3) == "<<<") { i += 2; continue }
      rest = substr(line, i + 2); hdash = 0
      if (substr(rest, 1, 1) == "-") { hdash = 1; rest = substr(rest, 2) }
      sub(/^[ \t]+/, "", rest)
      if (match(rest, /^(\\?'[A-Za-z_0-9]+'|"[A-Za-z_0-9]+"|\\?[A-Za-z_0-9]+)/)) {
        d = substr(rest, 1, RLENGTH); gsub(/['"\\]/, "", d); return d
      }
      i += 1
    }
  }
  return ""
}
{
  if (hd != "") {
    ln = $0
    if (hdash) sub(/^\t+/, "", ln)
    if (ln == hd) hd = ""
    print ""
    next
  }
  hd = opener($0)
  print
}
CENSUS_BLANK_EOF
# census_calls <tests dir> -> `<suite> TAB <section|setup> TAB <key>` per call outside a heredoc body.
census_calls() {
  local d f
  d="$(mktemp -d "$LINT_TMP/census-blank.XXXXXX")"
  for f in "$1"/*.test.sh; do
    [ -f "$f" ] || continue
    awk -f "$LINT_TMP/census-blank.awk" "$f" > "$d/${f##*/}"
  done
  ( cd "$d" && LC_ALL=C awk -f "$CENSUS_PROG" ./*.test.sh 2>/dev/null ) \
    | awk '{ loc = $1; kind = $2; key = $0; sub(/^[^ ]+ [^ ]+ §/, "", key); sub(/^\.\//, "", loc); sub(/:[0-9]+$/, "", loc)
             printf "%s\t%s\t%s\n", loc, kind, key }'
}

# header_entries <suite file> -> the keys the suite header lists, one per line: a line of the leading comment block
# that opens `#`, two or more spaces and `§KEY`. A `§` inside a sentence refers to something else and is not a claim.
header_entries() {
  awk 'NR == 1 && /^#!/ { next } /^#/ { print; next } { exit }' "$1" \
    | LC_ALL=C sed -n 's/^#[ ][ ][ ]*§\([A-Za-z0-9][A-Za-z0-9._-]*\).*$/\1/p' \
    | sed 's/[._-]*$//' | LC_ALL=C sort -u
}
# body_keys <census_calls output> <suite file name> -> the keys of the suite's `section` calls, one per line: the
# census key cut again at its first space. A title with no ` — ` or `: ` and more than one word is a sentence, not a
# key, and is left out.
body_keys() {
  printf '%s\n' "$1" | LC_ALL=C awk -F'\t' -v S="$2" '$1 == S && $2 == "section" {
    k = $3; i = index(k, " — "); j = index(k, ": ")
    if (i && (!j || i < j)) k = substr(k, 1, i - 1); else if (j) k = substr(k, 1, j - 1); else if (k ~ /[ \t]/) next
    sub(/[ \t].*$/, "", k); sub(/[.,;:-]*$/, "", k); print k }' | LC_ALL=C sort -u
}
# header_refusals <tests dir> -> one line per suite whose header lists a section its body lacks, or whose body has a
# section its header does not list, naming the suite and both differences. A header that lists none makes no claim.
header_refusals() {
  local f s calls only_h only_b out
  calls="$(census_calls "$1")"
  for f in "$1"/*.test.sh; do
    [ -f "$f" ] || continue
    s="${f##*/}"
    header_entries "$f" > "$LINT_TMP/hdr.keys"
    [ -s "$LINT_TMP/hdr.keys" ] || continue
    body_keys "$calls" "$s" > "$LINT_TMP/bdy.keys"
    only_h="$(LC_ALL=C comm -23 "$LINT_TMP/hdr.keys" "$LINT_TMP/bdy.keys" | sed 's/^/§/' | paste -sd' ' -)"
    only_b="$(LC_ALL=C comm -13 "$LINT_TMP/hdr.keys" "$LINT_TMP/bdy.keys" | sed 's/^/§/' | paste -sd' ' -)"
    out=""
    [ -z "$only_h" ] || out="header lists ${only_h} with no section"
    [ -z "$only_b" ] || out="${out:+$out; }body has ${only_b} with no header entry"
    [ -z "$out" ] || printf '%s: %s\n' "$s" "$out"
  done
}

# census_prog <rubric> -> 0 once $CENSUS_PROG holds the rubric's section-list command; 1 when the rubric yields none
census_prog() { awk -f "$LINT_TMP/census-extract.awk" "$1" > "$CENSUS_PROG" 2>/dev/null; [ -s "$CENSUS_PROG" ]; }

# Each check below reads <root> and the sorted file of the paths to judge, and prints its hits; 2 when it cannot run.
lint_changed() { /usr/bin/grep -qxF "$1" "$2"; }   # <path> <paths file> -> 0 when the row changed that path

lint_exit() {  # <root> <paths file>
  local root="$1" ceil="$1/tests/lib/refusal-exits.ceiling" widen="" rows
  [ -f "$ceil" ] || ceil=/dev/null
  ! lint_changed tests/lib/refusal-exits.ceiling "$2" || widen=1
  { cat "$2"; [ -z "$widen" ] || awk '!/^[ \t]*(#|$)/ { print $1 }' "$ceil"; } | LC_ALL=C sort -u > "$LINT_TMP/exit.want"
  exit_roster "$root" | LC_ALL=C comm -12 - "$LINT_TMP/exit.want" > "$LINT_TMP/exit.swept"
  [ -s "$LINT_TMP/exit.swept" ] || [ -n "$widen" ] || return 0
  # shellcheck disable=SC2046  # one rostered path per line, none with blanks
  rows="$(exit_sweep "$root" $(cat "$LINT_TMP/exit.swept"))"
  # A ceiling the row changed is judged at its own line too: a ceiling set under a file's count names that line, so
  # a reader of the lines a row wrote finds the row's red there and not only at the older sites.
  exit_judge "$rows" "$ceil" | LC_ALL=C awk -F'\t' -v W="$widen" -v SW="$LINT_TMP/exit.swept" -v CF="$ceil" '
    BEGIN { while ((getline l < SW) > 0) S[l] = 1
            while ((getline l < CF) > 0) { no++; if (l !~ /^[ \t]*(#|$)/) { split(l, c, /[ \t]+/); if (!(c[1] in CL)) CL[c[1]] = no } } }
    $1 == "O" { over[$2] = $3; if (W && ($2 in CL)) print "EXIT tests/lib/refusal-exits.ceiling:" CL[$2] " " $2 " " $3; next }
    $1 == "S" { p = $2; sub(/:[0-9]+$/, "", p); print "EXIT " $2 " " $3 " — " over[p] }
    $1 == "L" { p = $2; sub(/ [0-9]+$/, "", p); sub(/.* /, "", p); if (p in S) print "EXIT " p " " $2 }
    $1 == "F" && W { print "EXIT tests/lib/refusal-exits.ceiling:" $2 " " $3 }'
}

lint_quit() {  # <root> <paths file>
  local root="$1" allow="$1/tests/lib/quitting-readers.allow" f
  [ -f "$allow" ] || allow=/dev/null
  quit_roster "$root" > "$LINT_TMP/quit.roster"
  LC_ALL=C comm -12 "$LINT_TMP/quit.roster" "$2" > "$LINT_TMP/quit.swept"
  ( cd "$root" || exit 2
    ! lint_changed tests/lib/quitting-readers.allow "$2" \
      || LC_ALL=C awk -v REPORT=1 -v ALLOW="$allow" -v ROSTER="$LINT_TMP/quit.roster" -f "$QUIT_AWK" /dev/null
    while IFS= read -r f; do
      [ ! -f "$f" ] || LC_ALL=C awk -v ALLOW="$allow" -v ROSTER="$LINT_TMP/quit.roster" -f "$QUIT_AWK" "$f"
    done < "$LINT_TMP/quit.swept" ) | LC_ALL=C awk -F'\t' '
    $1 == "Q" { print "BP " $2 " " $3 }
    $1 == "A" { print "BP tests/lib/quitting-readers.allow:" $2 " " $3 }'
}

lint_header() {  # <root> <paths file>
  local d="$LINT_TMP/hd/tests" p n=0
  rm -rf "$d"; mkdir -p "$d" || return 2
  while IFS= read -r p; do
    case "$p" in (tests/*/*) continue ;; (tests/*.test.sh) ;; (*) continue ;; esac
    [ ! -f "$1/$p" ] || { cp "$1/$p" "$d/" && n=$((n + 1)); }
  done < "$2"
  [ "$n" -gt 0 ] || return 0
  census_prog "$1/tests/RUBRIC.md" || { echo "lint.sh: HEADER reads sections by tests/RUBRIC.md's command, which $1 does not hold" >&2; return 2; }
  header_refusals "$d" | sed 's|^|HEADER tests/|'
}

# A registered hook's own file holds no refusal: its words live in the library the hook calls. The check reads which
# hooks are registered from hooks/hooks.json, so a copy holding that file and the changed top-level hooks is judged as
# the tree would be for them; a changed hooks.json may register any hook, so then every one is read. A tree with no
# hooks.json registers no hook, and there is nothing to read.
lint_refusals() {  # <root> <paths file>
  local o="$LINT_TMP/orc" f n=0 out rc all=""
  [ -f "$1/hooks/hooks.json" ] || return 0
  rm -rf "$o"; mkdir -p "$o/hooks" "$o/payload/scripts" || return 2
  ! lint_changed hooks/hooks.json "$2" || all=1
  for f in "$1"/hooks/*.sh; do
    [ -f "$f" ] || continue
    [ -n "$all" ] || lint_changed "hooks/${f##*/}" "$2" || continue
    cp "$f" "$o/hooks/" && n=$((n + 1))
  done
  [ "$n" -gt 0 ] || return 0
  cp "$1/hooks/hooks.json" "$o/hooks/hooks.json" || { echo "lint.sh: REFUSALS cannot copy $1/hooks/hooks.json" >&2; return 2; }
  # The check refuses its own four kinds with exit 1; only a run that could not read the tree is past it.
  out="$(bash "$1/payload/scripts/one-reader-check.sh" "$o" 2>/dev/null)"; rc=$?
  [ "$rc" -le 1 ] || { echo "lint.sh: REFUSALS: $1/payload/scripts/one-reader-check.sh exited $rc" >&2; return 2; }
  printf '%s\n' "$out" | LC_ALL=C awk -F'\t' '$1 == "refusal" { print "REFUSALS " $2 " " $3 " — a registered hook file holds no refusal: say it in the library the hook calls" }'
}

lint_main() {  # <root> [<path>...] -> the hits; 0 none · 1 hits · 2 a check could not run
  local root c out hits="" rc=0
  root="$(cd "${1:-}" 2>/dev/null && pwd -P)" || { echo "lint.sh: no root ${1:-<none>}" >&2; return 2; }
  shift
  if [ "$#" -gt 0 ]; then printf '%s\n' "$@"; else cat; fi | awk 'NF' | LC_ALL=C sort -u > "$LINT_TMP/paths"
  for c in exit quit header refusals; do
    out="$("lint_$c" "$root" "$LINT_TMP/paths")" || rc=2
    [ -z "$out" ] || hits="${hits}${out}
"
  done
  [ -z "$hits" ] || printf '%s' "$hits"
  [ "$rc" = 2 ] && return 2
  [ -z "$hits" ]
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  lint_main "$@"
  exit $?
fi
