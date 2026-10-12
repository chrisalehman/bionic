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

anchors_index() {  # <root> <at>
  anchors_extract "${1:-}" "${2:--}" \
    | awk -F'\t' '$7 == "literal" { print $4 "\t" $1 }' | LC_ALL=C sort -u \
    | awk -F'\t' '$1 != f { if (f != "") print f "\t" s; f = $1; s = $2; next } { s = s "," $2 }
                  END { if (f != "") print f "\t" s }'
}
