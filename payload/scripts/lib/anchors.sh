#!/bin/bash
# payload/scripts/lib/anchors.sh — the mutation anchors a project's suites declare, read out of their
# source without running them (wave-35 T3; D16, D9; REQ-7 AC-7.1 to AC-7.3).
#
# THE DECLARING SIDE is the project's tests/lib/assert.sh `anchor`, in one of three shapes:
#
#   anchor file   <file> <text> [<replacement> <dest>]      the text on exactly one line of <file>
#   anchor fn     <file> <text> <function> [<replacement>]  …on exactly one line of <function>'s body
#   anchor insert <file> <text> [<line> <dest>]             exactly one line of <file> BEGINS with <text>
#
# <file> is relative to the root. <file>, <text> and fn's <function> are LITERALS in the source (quoted
# or bare words with nothing to expand), so this file reads every call without running the suite; the
# agreement row `finish` prints (tests/lib/assert.sh) catches a call it cannot read.
#
# THIS FILE IS THE READING SIDE, and the one counting rule both sides use:
#
#   anchors_extract <root> <at> [<suite>]  one line per shaped call, in every suite or the one named:
#       <suite> TAB <line> TAB <shape> TAB <file> TAB <text> TAB <function or -> TAB literal|nonliteral
#       (a nonliteral call prints `-` for file and text)
#   anchors_found <root> <at> <shape> <file> <text> <function or ->
#       how many lines the anchor matches where it is anchored; `nofile`, or `nofn` for a function the
#       file does not define
#   anchors_check <root> <at>   `MOVED <suite>:<line> <shape> <file> found=<n>` for each anchor not on
#       exactly one line, `NONLITERAL <suite>:<line>` for each call it cannot read; rc 1 when it printed
#   anchors_index <root> <at>   `<file> TAB <suite>[,<suite>]`, one line per anchored file, files
#       sorted, each file's suites sorted and unique: the interface `brief` and the floor judge read (D9)
#
# <at> is `-` for the files under <root> as they stand, or a commit read out of git's objects (the
# landing's candidate, which no checkout holds). Exposed as `session-poker.sh anchors check|index`.
#
# A SUITE IS THE FILE THAT DECLARES (D3 "1", design-ledger Δ2): any *.sh under <root> that git tracks,
# or holds untracked and unignored, and that carries a shaped call, keyed on its path from the root —
# never on a `.test.sh` suffix, so a suite outside tests/ is indexed by its own path. A call inside a
# heredoc body is a fixture's text, not a declaration (the heredoc reading is `_tf_scan`'s, below).
#
# THE INDEX IS DERIVED ON DEMAND, never stored (spec, rejected alternatives): a stored copy is a second
# truth that drifts the way the anchors did.
#
# bash 3.2 (ADR-001): no associative arrays; the reading is awk.

ANCHORS_CALL_ERE='^[[:space:]]*anchor[[:space:]]+(file|fn|insert)[[:space:]]'

# The root-relative path of each *.sh under <root> carrying a shaped call, sorted.
_anc_files() {  # <root> <at>
  local root="$1" at="$2" p
  if [ "$at" != - ]; then
    git -C "$root" grep -l -E -e "$ANCHORS_CALL_ERE" "$at" -- '*.sh' 2>/dev/null \
      | while IFS= read -r p; do printf '%s\n' "${p#"$at":}"; done
  elif git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$root" grep -l -E --untracked -e "$ANCHORS_CALL_ERE" -- '*.sh' 2>/dev/null
  else
    ( cd "$root" 2>/dev/null && find . -type f -name '*.sh' -exec grep -lE -e "$ANCHORS_CALL_ERE" {} + 2>/dev/null ) \
      | sed 's|^\./||'
  fi | LC_ALL=C sort -u
}

_anc_cat() {  # <root> <at> <path> -> the file's bytes, from the tree or from the commit
  if [ "$2" = - ]; then cat -- "$1/$3" 2>/dev/null; else git -C "$1" show "$2:./$3" 2>/dev/null; fi
}
_anc_has() {  # <root> <at> <path> -> 0 when the file is there
  if [ "$2" = - ]; then [ -f "$1/$3" ]; else git -C "$1" cat-file -e "$2:./$3" 2>/dev/null; fi
}

# THE EXTRACTOR, one awk over one suite's text. `hdtag` is tests/lib/assert.sh `_tf_scan`'s heredoc
# reading, copied whole (quote-, arithmetic- and $( )-aware; a herestring opens nothing), because a
# plugin library cannot source the project's test lib and the two must skip the same bodies.
# `tok` splits a call into shell words: \047…\047 and "…" quoting, backslash escapes; a word holding an
# unescaped $ or backquote, or a bare glob or brace character, is not a literal.
# NOTE FOR EDITORS: the program is a shell single-quoted string; spell an apostrophe \047.
_ANC_AWK='
function hdtag(s,   i, c, L, j, t, ch, q, dep, qs, ar, pc) {
  L = length(s); q = ""; dep = 0; ar = 0; pc = ""
  for (i = 1; i <= L; i++) {
    c = substr(s, i, 1)
    if (ar > 0) {
      if (c == "(") ar++
      else if (c == ")") ar--
      continue
    }
    if (q == "\047") {
      if (c == "\047") q = ""
      continue
    }
    if (q == "\"") {
      if (c == "\\") { i++; continue }
      if (c == "\"") { q = ""; continue }
      if (c == "$" && substr(s, i + 1, 1) == "(") {
        if (substr(s, i + 2, 1) == "(") { ar = 2; i += 2; continue }
        dep++; qs[dep] = q; q = ""; i++; pc = ""; continue
      }
      continue
    }
    if (c == "\047" || c == "\"") { q = c; pc = c; continue }
    if (c == "\\") { i++; pc = ""; continue }
    if (c == "$" && substr(s, i + 1, 1) == "(") {
      if (substr(s, i + 2, 1) == "(") { ar = 2; i += 2; continue }
      dep++; qs[dep] = q; q = ""; i++; pc = ""; continue
    }
    if (c == ")" && dep > 0) { q = qs[dep]; dep--; pc = ")"; continue }
    if (c == "(" && substr(s, i + 1, 1) == "(" \
        && (pc == "" || pc == ";" || pc == "&" || pc == "|" || pc == "(" || pc == "{")) {
      ar = 2; i++; continue
    }
    if (c == "<" && substr(s, i + 1, 1) == "<") {
      if (substr(s, i + 2, 1) == "<") { i += 2; pc = "<"; continue }
      j = i + 2
      if (substr(s, j, 1) == "-") j++
      while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
      ch = substr(s, j, 1)
      if (ch == "\047" || ch == "\"") j++
      t = ""
      while (j <= L) {
        c = substr(s, j, 1)
        if (c ~ /[A-Za-z0-9_]/) { t = t c; j++ } else break
      }
      if (t != "") return t
      i = j - 1; pc = "<"; continue
    }
    if (c != " " && c != "\t") pc = c
  }
  return ""
}
function tok(s,   i, c, d, j, L, w, inw, lit) {
  NT = 0; L = length(s); inw = 0; w = ""; lit = 1
  i = 1
  while (i <= L) {
    c = substr(s, i, 1)
    if (c == " " || c == "\t") { if (inw) { NT++; TW[NT] = w; TL[NT] = lit; inw = 0 } i++; continue }
    if (c == ";" || c == "&" || c == "|" || c == ")" || c == "<" || c == ">" || (c == "#" && !inw)) break
    if (!inw) { inw = 1; w = ""; lit = 1 }
    if (c == "\047") {
      j = index(substr(s, i + 1), "\047")
      if (j == 0) { lit = 0; w = w substr(s, i + 1); i = L + 1; continue }
      w = w substr(s, i + 1, j - 1); i += j + 1; continue
    }
    if (c == "\"") {
      i++
      while (i <= L) {
        c = substr(s, i, 1)
        if (c == "\"") break
        if (c == "\\") {
          d = substr(s, i + 1, 1)
          if (d == "\"" || d == "\\" || d == "$" || d == "`") { w = w d; i += 2; continue }
        }
        if (c == "$" || c == "`") lit = 0
        w = w c; i++
      }
      if (i > L) lit = 0
      i++; continue
    }
    if (c == "\\") { w = w substr(s, i + 1, 1); i += 2; continue }
    if (c == "$" || c == "`" || c == "*" || c == "?" || c == "[" || c == "{" || c == "~") lit = 0
    w = w c; i++
  }
  if (inw) { NT++; TW[NT] = w; TL[NT] = lit }
  return NT
}
hd != "" {
  if ($0 ~ ("^[ \t]*" hd "[ \t]*$")) hd = ""
  next
}
{
  line = $0; ln = NR
  if (line ~ /^[ \t]*#/) next
  if (line ~ /^[ \t]*anchor[ \t]+(file|fn|insert)[ \t]/) {
    while (line ~ /\\$/ && (getline nx) > 0) line = substr(line, 1, length(line) - 1) nx
    n = tok(line)
    shape = TW[2]; f = TW[3]; t = TW[4]; fn = (shape == "fn" ? TW[5] : "-")
    ok = (n >= 4 && TL[3] && TL[4] && f != "" && t != "" && substr(f, 1, 1) != "/" \
          && index(t, "\t") == 0 && index(f, "\t") == 0)
    if (shape == "fn") ok = ok && n >= 5 && TL[5] && fn != "" && fn !~ /[^A-Za-z0-9_:.-]/
    if (ok) print suite "\t" ln "\t" shape "\t" f "\t" t "\t" fn "\tliteral"
    else print suite "\t" ln "\t" shape "\t-\t-\t-\tnonliteral"
  }
  pending = hdtag(line)
  if (pending != "") hd = pending
}'

anchors_extract() {  # <root> <at> [<suite>]
  local root="${1:-}" at="${2:--}" s
  { if [ -n "${3:-}" ]; then printf '%s\n' "$3"; else _anc_files "$root" "$at"; fi; } | while IFS= read -r s; do
    [ -n "$s" ] || continue
    _anc_cat "$root" "$at" "$s" | awk -v suite="$s" "$_ANC_AWK"
  done
}

# THE ONE COUNTING RULE, run by `anchor` at run time and by the check at a landing. The text comes in
# through the environment, never `awk -v`, which would read its backslashes as escapes.
#   file    lines holding <text>
#   insert  lines beginning with <text>
#   fn      lines of <function>'s body holding <text>: from its `name()` head (the head line itself not
#           counted unless the whole definition is on it) to the `}` at the head's own indentation
anchors_found() {  # <root> <at> <shape> <file> <text> <function or ->
  _anc_has "$1" "$2" "$4" || { echo nofile; return 0; }
  _anc_cat "$1" "$2" "$4" | ANC_SHAPE="$3" ANC_TEXT="$5" ANC_FN="${6:--}" awk '
    BEGIN { s = ENVIRON["ANC_SHAPE"]; t = ENVIRON["ANC_TEXT"]; fn = ENVIRON["ANC_FN"]; n = 0; seen = 0; inb = 0 }
    s == "file"   { if (index($0, t)) n++; next }
    s == "insert" { if (index($0, t) == 1) n++; next }
    s == "fn" && inb {
      if (substr($0, 1, length(ind) + 1) == ind "}") { inb = 0; next }
      if (index($0, t)) n++
      next
    }
    s == "fn" {
      h = $0; ind = h; sub(/[^ \t].*$/, "", ind); sub(/^[ \t]+/, "", h); sub(/^function[ \t]+/, "", h)
      if (index(h, fn) != 1) next
      r = substr(h, length(fn) + 1); sub(/^[ \t]+/, "", r)
      if (substr(r, 1, 2) != "()") next
      seen = 1; r = substr(r, 3)
      if (r ~ /\{/ && r ~ /\}[ \t;]*$/) { if (index(r, t)) n++; next }
      inb = 1
    }
    END { if (s == "fn" && !seen) print "nofn"; else print n }'
}

anchors_check() {  # <root> <at>
  local root="${1:-}" at="${2:--}" s l shape f t fn st n bad=0
  while IFS="$(printf '\t')" read -r s l shape f t fn st; do
    [ -n "$s" ] || continue
    if [ "$st" != literal ]; then printf 'NONLITERAL %s:%s\n' "$s" "$l"; bad=1; continue; fi
    n="$(anchors_found "$root" "$at" "$shape" "$f" "$t" "$fn")"
    case "$n" in 1) continue ;; nofile|nofn) n=0 ;; esac
    printf 'MOVED %s:%s %s %s found=%s\n' "$s" "$l" "$shape" "$f" "$n"; bad=1
  done <<ANCHORS_EXTRACTED
$(anchors_extract "$root" "$at")
ANCHORS_EXTRACTED
  return "$bad"
}

# <file> TAB <suite> pairs in -> one line per file, `<file> TAB <suite>[,<suite>]`, files sorted, each
# file's suites sorted and unique (LC_ALL=C byte order). The one grouping both indexes print through.
_anc_group() {
  LC_ALL=C sort -u \
    | awk -F'\t' '$1 != f { if (f != "") print f "\t" s; f = $1; s = $2; next } { s = s "," $2 }
                  END { if (f != "") print f "\t" s }'
}

anchors_index() {  # <root> <at>
  anchors_extract "${1:-}" "${2:--}" \
    | awk -F'\t' '$7 == "literal" { print $4 "\t" $1 }' | _anc_group
}

# ---------------------------------------------------------------------------------------------------
# THE READS INDEX (wave-36 T5; D12, REQ-6 AC-6.1; ADR-056 "a suite covers what it reads"). The one
# file-to-suite fact `brief`, the dispatch wall's Lands-on arm, the landing and the cover rule read.
#
#   reads_index <root> <at>   `<file> TAB <suite>[,<suite>]`, the same grammar and order as anchors_index,
#       one line for every file some suite reads. The contract its readers rely on is stated whole in
#       .bionic/docs/record/wave-36-zero-machine-errors/T5-reads-index.md; in short, a suite
#       (tests/*.test.sh, the runner's roster, top level only) reads a file when
#     1. its text names the file outside a comment: a path-shaped word whose last part is the file's
#        basename. A word holding a `/` names the files whose path is it or ends in `/<it>` (so
#        tests/run.sh is not payload/scripts/lib/run.sh); a bare word, or a qualified one no path
#        ends in, names every file of that basename, and a bare word with no `.` names nothing.
#        A comment is a line whose first non-blank is `#`, or the tail from a `#` that begins a word
#        outside quotes. Heredoc bodies are text like any other: a fixture's text names what it reads.
#     2. it reads a file carrying a `BIONIC_LIB_WANT=` line (every hook): then it reads each library
#        named there, at payload/scripts/lib/<name> (the file's first such line; a name that is not a
#        literal word, `${2:-}` or a glob, names nothing).
#     3. it is the file.
#     4. the anchor index names it for the file (folded in whole, so a declaring suite outside tests/
#        is named by its anchors alone).
#     5. THE PRELUDE HOP (wave-37 T3; D4, AC-3.1): a tests/*.prelude.sh or tests/lib/*.sh the suite names
#        (rule 1) is scanned as the suite's own text, one hop: what that file names, walks or sets, the
#        suite reads, and rule 2 follows from there. What a second such file names is not followed.
#     6. THE DIRECTORY RULE (wave-37 T3; D4, AC-3.1): a line outside a comment holding `find <dir>...` or
#        `<dir>/*glob` reads every file under each directory it names, the glob (`-name`/`-iname`, or what
#        follows the `/`) filtering by basename. A leading `$VAR`/`${VAR}` is resolved once against the
#        VAR= lines of the same text (the suite and the preludes it names); what the value or word still
#        spells after its last expansion is the directory, matched as rule 1 matches a path (it or a path
#        ending in `/<it>`). A word that is all expansion (`"$REPO"`, `.`) names no directory: the root
#        is never one.
#   MISSED, the floor's whole run stays the catch-all (spec assumption 3): a path built from variables
#   past the first (`"$d/$f"`), a copy of a whole directory not walked by find or a glob, a library
#   sourced by a library or by a script without a BIONIC_LIB_WANT line, and anything a run opens that
#   its text does not name.
# `bash anchors.sh reads_index [<root>] [--at <commit>]` prints it from a shell.

# Every file under <root>, root-relative, one per line: the commit's tree; git's tracked and untracked,
# unignored files that stand; or, outside git, every file under the root.
_rd_files() {  # <root> <at>
  local root="$1" at="$2" p
  if [ "$at" != - ]; then
    git -C "$root" -c core.quotepath=off ls-tree -r --name-only "$at" 2>/dev/null
  elif git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$root" -c core.quotepath=off ls-files -co --exclude-standard 2>/dev/null \
      | while IFS= read -r p; do { [ -e "$root/$p" ] || [ -L "$root/$p" ]; } && printf '%s\n' "$p"; done
  else
    ( cd "$root" 2>/dev/null && find . -type f ! -path './.git/*' ) | sed 's|^\./||'
  fi
}

# Every line of every file under <root> matching <pathspec> and <ERE>, as `<tag> TAB <path> TAB <line>`,
# in one process: git grep over the commit or the tree (git's ignore rules), or outside git, find from
# <dir> (to <depth> when one is named) + awk.
_rd_grep() {  # <root> <at> <tag> <ERE> <pathspec> <dir> <find -name glob> [<depth>]
  local root="$1" at="$2" tag="$3" ere="$4" spec="$5" dir="$6" glob="$7" depth="${8:-}"
  if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || [ "$at" != - ]; then
    if [ "$at" != - ]; then
      git -C "$root" -c core.quotepath=off -c grep.lineNumber=false -c grep.fullName=false \
        grep --no-color -I -E -e "$ere" "$at" -- "$spec" 2>/dev/null
    else
      git -C "$root" -c core.quotepath=off -c grep.lineNumber=false -c grep.fullName=false \
        grep --no-color -I --untracked -E -e "$ere" -- "$spec" 2>/dev/null
    fi | awk -v pre="$( [ "$at" = - ] || printf '%s:' "$at" )" -v tag="$tag" '
      substr($0, 1, length(pre)) == pre {
        r = substr($0, length(pre) + 1); i = index(r, ":")
        if (i > 1) print tag "\t" substr(r, 1, i - 1) "\t" substr(r, i + 1)
      }'
  else
    ( cd "$root" 2>/dev/null || exit 0
      [ -d "$dir" ] || exit 0
      find "$dir" ${depth:+-maxdepth "$depth"} -type f -name "$glob" ! -path './.git/*' \
        -exec awk -v tag="$tag" -v ere="$ere" '$0 ~ ere { f = FILENAME; sub(/^\.\//, "", f); print tag "\t" f "\t" $0 }' {} + )
  fi
}

# THE SCAN, one awk over the stream: F <file> (every file), W <file> <BIONIC_LIB_WANT line>, P <file>
# <suite> (the anchor index's pairs), S <suite> <line> (every line of every suite). Prints the pairs.
# NOTE FOR EDITORS: the program is a shell single-quoted string; spell an apostrophe \047.
_RD_AWK='
function uncomment(s,   i, c, L, q, pc) {
  L = length(s); q = ""; pc = " "
  for (i = 1; i <= L; i++) {
    c = substr(s, i, 1)
    if (q == "\047") { if (c == "\047") q = ""; pc = c; continue }
    if (q == "\"") { if (c == "\\") { i++; continue } if (c == "\"") q = ""; pc = c; continue }
    if (c == "\\") { i++; pc = "x"; continue }
    if (c == "\047" || c == "\"") { q = c; pc = c; continue }
    if (c == "#" && (pc == " " || pc == "\t" || pc == ";" || pc == "&" || pc == "|" || pc == "(")) return substr(s, 1, i - 1)
    pc = c
  }
  return s
}
function scan(line, s, arr,   t, n, w, i, x, b, j, p, hit) {
  t = line; gsub(/[^A-Za-z0-9_.\/-]+/, " ", t)
  n = split(t, w, " ")
  for (i = 1; i <= n; i++) {
    x = w[i]
    if (index(x, ".") == 0 && index(x, "/") == 0) continue
    while (substr(x, 1, 2) == "./" || substr(x, 1, 3) == "../") x = substr(x, index(x, "/") + 1)
    sub(/^\/+/, "", x); sub(/[.\/]+$/, "", x)
    b = x; sub(/.*\//, "", b)
    if (b == "" || !(b in nb)) continue
    if (index(x, "/")) {
      hit = 0
      for (j = 1; j <= nb[b]; j++) {
        p = byb[b, j]
        if (p == x || (length(p) > length(x) && substr(p, length(p) - length(x)) == "/" x)) { arr[p "\t" s] = 1; hit = 1 }
      }
      if (hit) continue
    }
    if (index(b, ".") == 0) continue
    for (j = 1; j <= nb[b]; j++) arr[byb[b, j] "\t" s] = 1
  }
}
# text(line, o, arr): one line of owner o (a suite, or a prelude/helper the hop reads), outside comments:
# the name scan into arr, each VAR= value kept for the directory rule, and each line that may walk kept
# (quotes dropped) for END, where the VAR= lines of every text the suite reads are known.
function text(line, o, arr,   lq) {
  if (line ~ /^[ \t]*#/) return
  if (index(line, "#")) line = uncomment(line)
  scan(line, o, arr)
  if (index(line, "=")) assigns(line, o)
  if (index(line, "find") || index(line, "*")) {
    lq = line; gsub(/["\047]/, "", lq)
    if (lq ~ /(^|[^A-Za-z0-9_.\/-])find[ \t]/ || index(lq, "/*")) dl[o, ++nd[o]] = lq
  }
}
function assigns(line, o,   r, nm, v, c, e, L) {
  r = line
  while (match(r, /(^|[ \t;&|(])[A-Za-z_][A-Za-z0-9_]*=/)) {
    nm = substr(r, RSTART, RLENGTH - 1); sub(/^[ \t;&|(]/, "", nm)
    r = substr(r, RSTART + RLENGTH); c = substr(r, 1, 1); L = length(r)
    if (c == "\"" || c == "\047") {
      for (e = 2; e <= L && substr(r, e, 1) != c; e++) if (c == "\"" && substr(r, e, 1) == "\\") e++
      v = substr(r, 2, e - 2); r = substr(r, e + 1)
    } else { v = r; sub(/[ \t;|&)].*$/, "", v); r = substr(r, length(v) + 1) }
    if (dtail(v) != "") asg[o, nm] = asg[o, nm] "\034" v
  }
}
# dtail(w): what a word still spells after its last expansion, from the root: `${R}/a/b` and `$1/a/b` are
# a/b; `$R`, `.` and `/` are nothing.
function dtail(w,   t, pre, i) {
  gsub(/["\047]/, "", w)
  if (!match(w, /[A-Za-z0-9_.\/-]*$/)) return ""
  t = substr(w, RSTART); pre = substr(w, 1, RSTART - 1)
  if (pre ~ /\$\{?$/) { i = index(t, "/"); t = i ? substr(t, i) : "" }
  while (substr(t, 1, 1) == "/" || substr(t, 1, 2) == "./" || substr(t, 1, 3) == "../") t = substr(t, index(t, "/") + 1)
  sub(/\/+$/, "", t)
  return (t == "." || t == "..") ? "" : t
}
# walk(word, g, s, ctx): the files under the directories <word> names, filtered by the globs in g (a list
# led by \034, or empty for every file), as pairs for suite s; ctx is the texts whose VAR= lines resolve
# a leading $VAR (\034-led).
function walk(word, g, s, ctx,   nm, rest, nc, cc, k, nv, vv, m, cand, ncand, x, t, b, j, d, q, f, fb, ng, gg, ok) {
  ncand = 0
  if (match(word, /^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/)) {
    nm = substr(word, RSTART, RLENGTH); rest = substr(word, RSTART + RLENGTH); gsub(/[${}]/, "", nm)
    nc = split(ctx, cc, "\034")
    for (k = 2; k <= nc; k++) if ((cc[k], nm) in asg) {
      nv = split(asg[cc[k], nm], vv, "\034")
      for (m = 2; m <= nv; m++) cand[++ncand] = vv[m] rest
    }
  }
  if (ncand == 0) cand[++ncand] = word
  ng = split(g, gg, "\034")
  for (x = 1; x <= ncand; x++) {
    t = dtail(cand[x]); if (t == "") continue
    b = t; sub(/.*\//, "", b)
    for (j = 1; j <= ndb[b]; j++) {
      d = dbyb[b, j]
      if (!(d == t || (length(d) > length(t) && substr(d, length(d) - length(t)) == "/" t))) continue
      for (q = 1; q <= nf[d]; q++) {
        f = df[d, q]; fb = f; sub(/.*\//, "", fb); ok = (ng < 2)
        for (k = 2; k <= ng && !ok; k++) if (fb ~ globre(gg[k])) ok = 1
        if (ok) out[f "\t" s] = 1
      }
    }
  }
}
function globre(g,   o) {
  if (g in gre) return gre[g]
  o = g
  gsub(/[.+^$(){}|\\]/, "\\\\&", g); gsub(/\[/, "\\\\&", g); gsub(/\*/, ".*", g); gsub(/\?/, ".", g)
  gre[o] = "^" g "$"; return gre[o]
}
# walks(lq, s, ctx): every `find <dir>...` and `<dir>/*glob` on a kept line, walked for suite s.
function walks(lq, s, ctx,   r, a, cut, n, tk, i, w, g, gr, L, j, k, pos, base) {
  r = lq
  while (match(r, /(^|[^A-Za-z0-9_.\/-])find[ \t]+/)) {
    a = substr(r, RSTART + RLENGTH); r = a
    cut = match(a, /[|;)]/) ? substr(a, 1, RSTART - 1) : a
    g = ""; gr = cut
    while (match(gr, /-i?name[ \t]+[^ \t]+/)) { w = substr(gr, RSTART, RLENGTH); sub(/^-i?name[ \t]+/, "", w); g = g "\034" w; gr = substr(gr, RSTART + RLENGTH) }
    n = split(cut, tk, /[ \t]+/)
    for (i = 1; i <= n; i++) {
      if (tk[i] == "") continue
      if (tk[i] ~ /^[-!(\\]/ || tk[i] ~ /^(&&|\|\||>|<|2>)/) break
      walk(tk[i], g, s, ctx)
    }
  }
  base = 0; L = length(lq)
  while ((pos = index(substr(lq, base + 1), "/*")) > 0) {
    pos += base; base = pos + 1
    for (j = pos - 1; j >= 1 && index(" \t;|&(<>=`", substr(lq, j, 1)) == 0; j--) ;
    for (k = pos + 1; k <= L && index(" \t;|&)<>`", substr(lq, k, 1)) == 0; k++) ;
    w = substr(lq, j + 1, pos - j - 1); g = substr(lq, pos + 1, k - pos - 1); sub(/.*\//, "", g)
    if (w != "") walk(w, "\034" g, s, ctx)
  }
}
BEGIN { FS = "\t" }
$1 == "F" {
  p = $2; if (p in files) next; files[p] = 1; b = p; sub(/.*\//, "", b); nb[b]++; byb[b, nb[b]] = p
  d = p
  while (sub(/\/[^\/]*$/, "", d)) {
    if (!(d in nf)) { b = d; sub(/.*\//, "", b); ndb[b]++; dbyb[b, ndb[b]] = d }
    df[d, ++nf[d]] = p
  }
  next
}
$1 == "W" {
  if ($2 in want) next
  v = substr($0, length($2) + 4); sub(/^[ \t]*BIONIC_LIB_WANT=/, "", v)
  q = substr(v, 1, 1)
  if (q == "\"" || q == "\047") { v = substr(v, 2); v = substr(v, 1, index(v, q) - 1) } else sub(/[ \t;].*$/, "", v)
  want[$2] = v; next
}
$1 == "P" { pair[$2 "\t" $3] = 1; next }
$1 == "S" {
  s = $2
  if (s !~ /^tests\/[^\/]*\.test\.sh$/) next
  pair[s "\t" s] = 1; suite[s] = 1
  text(substr($0, length(s) + 4), s, pair); next
}
$1 == "H" {
  h = $2
  if (h !~ /^tests\/[^\/]*\.prelude\.sh$/ && h !~ /^tests\/lib\/[^\/]*\.sh$/) next
  hfile[h] = 1
  text(substr($0, length(h) + 4), h, hp); next
}
END {
  for (k in pair) {
    out[k] = 1; split(k, kk, "\t")
    if ((kk[1] in hfile) && (kk[2] in suite)) hn[kk[2]] = hn[kk[2]] "\034" kk[1]
  }
  for (k in hp) { split(k, kk, "\t"); hr[kk[2]] = hr[kk[2]] "\034" kk[1] }
  for (s in suite) {
    ctx = "\034" s hn[s]; nc = split(ctx, cc, "\034")
    for (c = 2; c <= nc; c++) {
      o = cc[c]
      if (c > 2) { n = split(hr[o], L, "\034"); for (i = 2; i <= n; i++) out[L[i] "\t" s] = 1 }
      for (i = 1; i <= nd[o]; i++) walks(dl[o, i], s, ctx)
    }
  }
  for (k in out) {
    split(k, kk, "\t")
    if (kk[1] in want) {
      n = split(want[kk[1]], L, /[ \t]+/)
      for (i = 1; i <= n; i++) if (L[i] ~ /^[A-Za-z0-9_.-]+$/) fan["payload/scripts/lib/" L[i] "\t" kk[2]] = 1
    }
  }
  for (k in fan) out[k] = 1
  for (k in out) print k
}'

# The command form's usage refusal: one line to stderr, exit 2. Defined at file scope so sourcing defines it too.
_rd_usage() { echo "usage: bash anchors.sh reads_index [<root>] [--at <commit>]${1:+ — $1}" >&2; exit 2; }

reads_index() {  # <root> <at>
  local root="${1:-}" at="${2:--}"
  { _rd_files "$root" "$at" | sed 's/^/F	/'
    _rd_grep "$root" "$at" W '^[[:space:]]*BIONIC_LIB_WANT=' '*.sh' . '*.sh'
    anchors_extract "$root" "$at" | awk -F'\t' '$7 == "literal" { print "P\t" $4 "\t" $1 }'
    _rd_grep "$root" "$at" S '' 'tests/*.test.sh' tests '*.test.sh' 1
    _rd_grep "$root" "$at" H '' 'tests/*.prelude.sh' tests '*.prelude.sh' 1
    _rd_grep "$root" "$at" H '' 'tests/lib/*.sh' tests/lib '*.sh' 1
  } | awk "$_RD_AWK" | _anc_group
}

# reads_suites <root> <at> <cell> -> the suites reads_index names, at <at>, for any file an entry of the Files cell
# covers (lib/units.sh `cell_covers`, the scheduler's matcher; an entry spelled from <root>/ is read from the
# root): by file name, sorted, once each, one per line. Nothing when no suite reads such a file, or units.sh
# cannot be loaded. THE ONE READER of the index by Files (wave-37 T3; D4; burns index-to-suites and
# reads-index-consumers): session-poker.sh `poker_brief_index_suites` (the brief's Lands-on) and
# dispatch-preflight.sh `dp_lands_index_suites` (the wall) are thin calls to it; proof.sh `_proof_walk`
# reads `reads_index` itself, file to suites, joined with the commit's changed code files.
reads_suites() {  # <root> <at> <cell>
  declare -F _units_files_awk >/dev/null 2>&1 \
    || . "$(dirname "${BASH_SOURCE[0]}")/units.sh" 2>/dev/null
  declare -F _units_files_awk >/dev/null 2>&1 || return 0
  reads_index "${1:-}" "${2:--}" 2>/dev/null | awk -F'\t' -v cell="${3:-}" -v root="${1:-}" "$(_units_files_awk)"'
    BEGIN { m = split(cell, e, ","); cell = ""; for (k = 1; k <= m; k++) { t = e[k]; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t); if (root != "" && index(t, root "/") == 1) t = substr(t, length(root) + 2); cell = cell (k > 1 ? "," : "") t } }
    $1 != "" && cell_covers(cell, $1) { m = split($2, s, ","); for (k = 1; k <= m; k++) { b = s[k]; sub(/^.*\//, "", b); print b } }' \
    | LC_ALL=C sort -u
}

# Run as a command: `bash anchors.sh reads_index [<root>] [--at <commit>]`. Sourced, it defines and does
# nothing.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  [ "${1:-}" = reads_index ] || _rd_usage "the one verb is reads_index"
  shift; RD_ROOT=""; RD_AT=-
  while [ $# -gt 0 ]; do
    case "$1" in
      --at) [ -n "${2:-}" ] || _rd_usage "--at takes a commit"; RD_AT="$2"; shift 2 ;;
      -*) _rd_usage "unknown flag $1" ;;
      *) [ -z "$RD_ROOT" ] || _rd_usage "at most one root"; RD_ROOT="$1"; shift ;;
    esac
  done
  [ -n "$RD_ROOT" ] || RD_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || RD_ROOT=""
  [ -n "$RD_ROOT" ] || RD_ROOT="$PWD"
  [ -d "$RD_ROOT" ] || { echo "anchors: reads_index: no directory $RD_ROOT" >&2; exit 2; }
  if [ "$RD_AT" != - ]; then
    git -C "$RD_ROOT" rev-parse --verify -q "${RD_AT}^{commit}" >/dev/null 2>&1 \
      || { echo "anchors: reads_index: no commit $RD_AT in $RD_ROOT" >&2; exit 2; }
  fi
  reads_index "$RD_ROOT" "$RD_AT"
fi
