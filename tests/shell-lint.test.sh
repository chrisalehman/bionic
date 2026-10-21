#!/bin/bash
# SHELL LINT — what `bash -n` cannot see (epic-23 wave-28 T37; REQ-11, D28).
#
# WHAT THIS SUITE OWNS. Every hook and payload script names `#!/bin/bash`, which on macOS is
# bash 3.2, and a hook runs by its shebang. Three shapes parse clean under `/bin/bash -n`
# and then misread at run time, because 3.2 finds the end of a `$( … )` by counting
# parentheses and quotes, knowing nothing of `case` or heredocs:
#
#   CASE           a `case` arm with no opening paren inside `$( … )`, on one line or many,
#                  quoted or not. In a double-quoted `"$( … )"` it parses, and the function
#                  fails only when it runs (wave-27 T80: hooks/session-poker.sh's release-check).
#   HEREDOC-CASE   the same arm inside a `$( … )` in the body of a heredoc whose delimiter is
#                  unquoted: the body is expanded at run time, and the arm fails then.
#   HEREDOC-PAREN  a heredoc inside `$( … )` whose body holds a lone `)`: 3.2 ends the
#                  substitution there, silently, and the rest leaks as text.
#
# (The last two are review pass 73's P3-1.) The instrument is the lexer below, written for
# this suite: it reads quotes, `$'…'`, `${…}`, `$(( ))`, `$( )`, `<( )`, `( )`, backquotes,
# comments, heredocs and case states, and names each hazard by file and line. It is the one
# home of what bash 3.2 rejects, so it also holds what tests/cross-gate-agreement.test.sh §BP
# held before it: the `/bin/bash -n` sweep (§PARSE) and the one-line `$(case` grep (§CASE),
# each with its mutant.
#
# §BP is a fourth shape that neither `-n` nor a run at test size can see: a writer piped into a
# reader that quits early (`grep -q`, `grep -l`, `grep -m`, `head`, an awk that exits) in a file
# that runs under pipefail, with the pipeline's status read. Past the 64 KB pipe buffer the writer
# takes SIGPIPE, the pipeline reports 141, and a present line reads as absent. The sweep reads the
# hooks, payload/scripts and the declared check's two files; tests/lib/quitting-readers.allow lists
# each bounded site with its reason. §BP-PIN proves the fixed form of observe.sh's process scan
# returns 0 on a listing larger than the buffer, and the quitting form returns 141.
#
# §CENSUS-COMPLETE-1 to -3 hold the tests tree to tests/CENSUS.md: every suite has a heading, every
# `section` call a record line under its key, every verdict is one of the five words, and a `rule:`
# line is a keep. The calls are found by the section-list command in tests/RUBRIC.md, run from here.
#
# §LOAD sources every library under payload/scripts/lib in a bare `/bin/bash` and requires
# every function the lexer finds it defining at load to be defined after, with nothing on
# stderr. A hook or a payload command is parsed (§PARSE), never run.
#
# FIXTURE FIDELITY (the rule of that name, .claude/rules/test-harness.md). The shipped tree is
# read where it lies, never copied. Every mutant is SYNTHESIZED here, and each one is first
# proven to be the hazard it stands for: it parses under `/bin/bash -n`, and run under
# `/bin/bash` it fails or leaks. The shapes were measured under bash 3.2.57 on 2026-10-06.
#
# ANTI-VACUITY (the rule of that name). Each sweep first proves it found files, and the
# lexer proves it read every shipped file to its end with every frame closed (§LEXER), so a
# lexer that lost its place says so instead of going quiet. Every clean row stands beside a
# planted row read by the same instrument in the same call, and every control (a paren-led
# arm, a quoted heredoc, a balanced body) beside the mutant it differs from.
#
# HERMETIC. It reads the tree and writes only under a mktemp directory. A library is loaded
# with `env -i`, a throwaway HOME and cwd, and GIT_CEILING_DIRECTORIES at that directory.
#
# Usage: bash tests/shell-lint.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
HOOKS_DIR="${BIONIC_HOOKS_DIR}"
SCRIPTS_DIR="${REPO}/payload/scripts"
LIB_DIR="${REPO}/payload/scripts/lib"
TESTS_DIR="${REPO}/tests"
RENDER_SH="${REPO}/agents-src/render.sh"
WSL_SH="${REPO}/wsl-setup.sh"

[ -x /bin/bash ] || { echo "shell-lint.test.sh: /bin/bash is required"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── the lexer ────────────────────────────────────────────────────────────────
LINT_AWK="$TMP/lint.awk"
cat > "$LINT_AWK" <<'LINT_AWK_EOF'
# A shell lexer for the three shapes bash 3.2 reads differently from a modern bash.
# Prints, per file it reads:
#   H<TAB><file>:<line><TAB><shape><TAB><what>   one row per hazard
#   D<TAB><file><TAB><name>                     one row per function a load defines
#   U<TAB><file><TAB><state>                    the file ended with a frame still open, or
#                                               its brace depth went below zero or ended
#                                               above it
# Frames: top, cs ($( ) and <( )), sub (( )), bt (` `), dq, sq, dsq ($' '), par (${ }),
# ar ($(( )) and (( ))), hd (an unquoted heredoc body). A case lives in the
# command frame that opened it: subj, pat, patx (inside a pattern), body.
function push(k,   p) {
  p = d; d++; K[d] = k; AT[d] = 1; BR[d] = 0; AD[d] = 0
  Z[d] = (k == "cs") ? 1 : ((k == "bt") ? 0 : Z[p])
  HB_[d] = (k == "hd") ? 1 : HB_[p]
  Q[d] = (k == "dq" || k == "hd") ? 1 : ((k == "top" || k == "cs" || k == "sub" || k == "bt") ? 0 : Q[p])
}
function pop() {
  while (cn > 0 && CF[cn] >= d) cn--
  if (d > 1) d--
}
function cmdish(k) { return k == "top" || k == "cs" || k == "sub" || k == "bt" }
function isb(c) {
  return c == "" || c == " " || c == "\t" || c == ";" || c == "&" || c == "|" \
    || c == "(" || c == ")" || c == "<" || c == ">"
}
# the end of a reserved word: a blank or metacharacter, or the backquote that closes the
# backquoted text it sits in (`… esac` + backquote)
function kend(c) { return isb(c) || (c == "`" && K[d] == "bt") }
function hit(shape, what,   key) {
  key = FILENAME SUBSEP FNR SUBSEP shape
  if (key in SEEN) return
  SEEN[key] = 1
  printf "H\t%s:%d\t%s\t%s\n", FILENAME, FNR, shape, what
}
function owns() { return cn > 0 && CF[cn] == d }
function dollar(s, i,   c2) {
  c2 = substr(s, i + 1, 1)
  if (c2 == "(") {
    if (substr(s, i + 2, 1) == "(") { push("ar"); return i + 2 }
    push("cs"); ws = 1; return i + 1
  }
  if (c2 == "{") { push("par"); return i + 1 }
  if (c2 == "'" && !Q[d]) { push("dsq"); return i + 1 }
  if (c2 != "" && index("#?$!@*-0123456789", c2)) return i + 1
  return i
}
function pattern(s, i,   n, c, j) {
  n = length(s)
  for (; i <= n; i++) {
    c = substr(s, i, 1)
    if (PQS == "'") { if (c == "'") PQS = ""; continue }
    if (PQS == "\"") { if (c == "\\") i++; else if (c == "\"") PQS = ""; continue }
    if (c == "\\") { i++; continue }
    if (c == "'" || c == "\"") { PQS = c; continue }
    if (c == "$" && substr(s, i + 1, 1) == "{") {
      j = index(substr(s, i), "}"); if (j == 0) return n; i += j - 1; continue
    }
    if (c == ")") { CS[cn] = "body"; AT[d] = 1; ws = 1; return i }
  }
  return n
}
function heredoc(s, i,   j, n, c, w, q, e, strip) {
  j = i + 2; n = length(s); strip = 0; w = ""; q = 0
  if (substr(s, j, 1) == "-") { strip = 1; j++ }
  while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
  for (; j <= n; j++) {
    c = substr(s, j, 1)
    if (c == "'" || c == "\"") {
      q = 1; e = index(substr(s, j + 1), c)
      if (e == 0) { w = w substr(s, j + 1); j = n + 1; break }
      w = w substr(s, j + 1, e - 1); j += e; continue
    }
    if (c == "\\") { q = 1; w = w substr(s, j + 1, 1); j++; continue }
    if (isb(c)) break
    w = w c
  }
  if (!hdon && w != "") { np++; HD[np] = w; HQ[np] = q; HS[np] = strip; HZ[np] = Z[d] }
  return j - 1
}
function scan(s,   i, n, c, k, w, m, nb, nm) {
  n = length(s); ws = 1
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1); k = K[d]
    if (k == "sq") {
      m = index(substr(s, i), "'"); if (m == 0) return
      i += m - 1; pop(); ws = 0; continue
    }
    if (k == "dsq") { if (c == "\\") i++; else if (c == "'") { pop(); ws = 0 } continue }
    if (k == "dq" || k == "hd") {
      if (c == "\\") { i++; continue }
      if (c == "\"" && k == "dq") { pop(); ws = 0; continue }
      if (c == "`") { push("bt"); ws = 1; continue }
      if (c == "$") i = dollar(s, i)
      continue
    }
    if (k == "par") {
      if (c == "\\") { i++; continue }
      if (c == "}") { pop(); ws = 0; continue }
      if (c == "$") { i = dollar(s, i); continue }
      if (c == "\"") { push("dq"); continue }
      if (c == "'" && !Q[d]) { push("sq"); continue }
      if (c == "`") push("bt")
      continue
    }
    if (k == "ar") {
      if (c == "(") { AD[d]++; continue }
      if (c == ")") {
        if (AD[d] > 0) AD[d]--
        else { if (substr(s, i + 1, 1) == ")") i++; pop(); ws = 0 }
        continue
      }
      if (c == "$") i = dollar(s, i)
      continue
    }
    # a command frame: top, cs, sub, bt
    if (owns() && CS[cn] == "patx") { i = pattern(s, i); continue }
    if (c == " " || c == "\t") { ws = 1; continue }
    if (ws && c == "#") return
    if (owns() && CS[cn] == "pat") {
      if (substr(s, i, 4) == "esac" && kend(substr(s, i + 4, 1))) {
        cn--; AT[d] = 0; i += 3; ws = 0; continue
      }
      CS[cn] = "patx"
      if (c == "(") continue
      if (Z[d]) {
        if (HB_[d]) hit("HEREDOC-CASE", "a case arm with no opening paren inside $( ) in an unquoted heredoc body")
        else hit("CASE", "a case arm with no opening paren inside $( )")
      }
      i = pattern(s, i); continue
    }
    if (ws) {
      w = substr(s, i)
      m = match(w, /^[a-z]+/) ? substr(w, 1, RLENGTH) : ""
      nb = (m != "") && kend(substr(s, i + length(m), 1))
      if (owns() && CS[cn] == "subj") {
        if (nb && m == "in" && CSW[cn]) { CS[cn] = "pat"; i += 1; ws = 0; continue }
        CSW[cn] = 1
      } else if (AT[d] && nb) {
        if (m == "case") { cn++; CF[cn] = d; CS[cn] = "subj"; CSW[cn] = 0; AT[d] = 0; i += 3; ws = 0; continue }
        if (m == "esac" && owns()) { cn--; AT[d] = 0; i += 3; ws = 0; continue }
        if (m ~ /^(if|then|else|elif|do|while|until|time)$/) { i += length(m) - 1; ws = 0; continue }
        if (m == "function") {
          nm = substr(s, i + 8); sub(/^[ \t]+/, "", nm); sub(/[^A-Za-z0-9_:.-].*$/, "", nm)
          if (d == 1 && BR[1] == 0 && !hdon && nm != "") printf "D\t%s\t%s\n", FILENAME, nm
          # the name is no command word: step over it and stay in command position, so the
          # `{` of `function name {` counts as the one of `name() {` does
          match(substr(s, i + 8), /^[ \t]*[A-Za-z0-9_:.-]*/); i += 7 + RLENGTH; ws = 0; continue
        }
      }
      if (AT[d]) {
        if (c == "{" && isb(substr(s, i + 1, 1))) { BR[d]++; continue }
        if (c == "}" && kend(substr(s, i + 1, 1))) {
          if (--BR[d] < 0 && !BNEG) BNEG = FNR
          AT[d] = 0; ws = 0; continue
        }
        if (c == "!" && isb(substr(s, i + 1, 1))) continue
        if (d == 1 && BR[1] == 0 && !hdon && match(w, /^[A-Za-z_][A-Za-z0-9_:.-]*[ \t]*\(\)/)) {
          nm = w; sub(/[ \t]*\(.*$/, "", nm); printf "D\t%s\t%s\n", FILENAME, nm
        }
        if (!match(w, /^[A-Za-z_][A-Za-z0-9_]*\+?=/)) AT[d] = 0
      }
    }
    if (c == "\\") { i++; ws = 0; continue }
    if (c == "'") { push("sq"); ws = 0; continue }
    if (c == "\"") { push("dq"); ws = 0; continue }
    if (c == "`") { if (k == "bt") { pop(); ws = 0 } else { push("bt"); ws = 1 } continue }
    if (c == "$") { i = dollar(s, i); if (K[d] != "cs") ws = 0; continue }
    if (c == "(") {
      if (substr(s, i + 1, 1) == ")") { i++; AT[d] = 1; ws = 1; continue }
      if (AT[d] && substr(s, i + 1, 1) == "(") { i++; push("ar"); continue }
      push("sub"); ws = 1; continue
    }
    if (c == ")") { if (k == "cs" || k == "sub") pop(); ws = (k == "sub"); continue }
    if (c == "<") {
      if (substr(s, i, 3) == "<<<") { i += 2; ws = 1; continue }
      if (substr(s, i, 2) == "<<") { i = heredoc(s, i); ws = 1; continue }
      if (substr(s, i + 1, 1) == "(") { i++; push("cs") }
      ws = 1; continue
    }
    if (c == ">") { if (substr(s, i + 1, 1) == "(") { i++; push("cs") } ws = 1; continue }
    if (c == ";") {
      if (owns() && CS[cn] == "body" && (substr(s, i + 1, 1) == ";" || substr(s, i + 1, 1) == "&")) {
        CS[cn] = "pat"; i++; if (substr(s, i + 1, 1) == "&") i++
        ws = 1; continue
      }
      AT[d] = 1; ws = 1; continue
    }
    if (c == "&" || c == "|") { AT[d] = 1; ws = 1; continue }
    ws = 0
  }
}
# The raw text of a heredoc body inside $( ), read the way bash 3.2 reads it: it knows
# quotes, parentheses and comments and nothing of heredocs, so a lone ) closes the
# substitution. A comment opens at a `#` that starts the line or follows a blank, and to
# the line's end no paren and no quote counts (measured under 3.2.57, wave-28 T46).
function rawparen(s,   i, n, c) {
  n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (RQ != "") {
      if (c == "\\" && RQ != "'") { i++; continue }
      if (c == RQ) RQ = ""
      continue
    }
    if (c == "\\") { i++; continue }
    if (c == "#" && (i == 1 || substr(s, i - 1, 1) == " " || substr(s, i - 1, 1) == "\t")) return
    if (c == "'" || c == "\"" || c == "`") { RQ = c; continue }
    if (c == "(") RDEP++
    else if (c == ")") {
      if (RDEP > 0) RDEP--
      else if (!RHIT) { RHIT = 1; hit("HEREDOC-PAREN", "a lone ) in a heredoc body inside $( ) ends the substitution early") }
    }
  }
}
function startbody() {
  HBASE = d
  if (!HQ[hc]) push("hd")
  RQ = ""; RDEP = 0; RHIT = 0
}
# A file that ends with a frame, a case or a heredoc still open, or whose brace depth went
# below zero or ends above it, is one the lexer lost its place in (a form it does not
# know), and every row it printed after that point is suspect: it says so.
function closefile(f,   st, x) {
  if (f == "" || (d == 1 && cn == 0 && !hdon && np == 0 && BR[1] == 0 && !BNEG)) return
  st = ""; for (x = 1; x <= d; x++) st = st K[x] (x < d ? "/" : "")
  printf "U\t%s\t%s cases=%d heredoc=%s braces=%d%s\n", f, st, cn, (hdon ? HD[hc] : "-"), \
    BR[1], (BNEG ? " below-zero-at=" BNEG : "")
}
FNR == 1 {
  closefile(PREVF); PREVF = FILENAME; PQS = ""; BNEG = 0
  d = 1; K[1] = "top"; AT[1] = 1; BR[1] = 0; Z[1] = 0; HB_[1] = 0; Q[1] = 0
  cn = 0; np = 0; hdon = 0; hc = 0
}
{
  line = $0
  if (hdon) {
    t = line
    if (HS[hc]) sub(/^\t+/, "", t)
    if (t == HD[hc]) {
      while (d > HBASE) pop()
      hc++
      if (hc > np) { hdon = 0; np = 0 } else startbody()
      next
    }
    if (HZ[hc]) rawparen(line)
    if (!HQ[hc]) { scan(line); if (cmdish(K[d])) AT[d] = 1 }
    next
  }
  scan(line)
  if (cmdish(K[d]) && line !~ /\\$/) AT[d] = 1
  if (np > 0 && cmdish(K[d])) { hdon = 1; hc = 1; startbody() }
}
END { closefile(PREVF) }
LINT_AWK_EOF

# lint_raw <file>... -> the lexer's rows (H, D, U), each file named as it was given
lint_raw() {
  LC_ALL=C awk -f "$LINT_AWK" "$@"
}
# lint_hits <file>... -> one `<file>:<line>: <shape> — <what>` per hazard
lint_hits() {
  lint_raw "$@" | LC_ALL=C awk -F'\t' '$1 == "H" { printf "%s: %s — %s\n", $2, $3, $4 }'
}
# shape_of <shape> <hits> -> the hits of that one shape
shape_of() {
  printf '%s\n' "$2" | LC_ALL=C awk -v s="$1" 'index($0, ": " s " — ") > 0'
}
# rel <absolute path>... -> each path relative to the repository, one per line
rel() {
  local f
  for f in "$@"; do printf '%s\n' "${f#"$REPO"/}"; done
}
# mark_line <file> <marker> -> the number of the one line that carries <marker>
mark_line() {
  LC_ALL=C grep -n -- "$2" "$1" | head -1 | cut -d: -f1
}
# plant <file> — stdin to <file>, with @DOL@ spelled `$`. The one-line shapes are written
# this way so this file's own source never holds the text §CASE's grep forbids.
plant() {
  sed 's/@DOL@/$/g' > "$1"
}

# The shipped files the lexer reads: every hook, and everything under payload/scripts.
# hooks/ is the real path; payload/hooks is a symlink to it and is not read twice.
LINT_ABS="$(find "$HOOKS_DIR" "$SCRIPTS_DIR" -name '*.sh' -type f 2>/dev/null | LC_ALL=C sort)"
# shellcheck disable=SC2086  # one path per line, none with blanks
LINT_REL="$(rel $LINT_ABS)"
# shellcheck disable=SC2086
LINT_RAW="$(cd "$REPO" && lint_raw $LINT_REL)"
LINT_HITS="$(printf '%s\n' "$LINT_RAW" | LC_ALL=C awk -F'\t' '$1 == "H" { printf "%s: %s — %s\n", $2, $3, $4 }')"

# ============================================================
section "LEXER — the instrument reads every shipped file to its end"
# ============================================================
expect_eq "the lexer's roster holds hooks and payload scripts" "yes" \
  "$(LC_ALL=C grep -q '^hooks/.*\.sh$' <<< "$LINT_REL" \
     && LC_ALL=C grep -q '^payload/scripts/lib/.*\.sh$' <<< "$LINT_REL" \
     && LC_ALL=C grep -q '^payload/scripts/[^/]*\.sh$' <<< "$LINT_REL" && echo yes || echo no)"
expect_eq "…and it found function definitions in them, so it read their text" "yes" \
  "$(LC_ALL=C grep -q '^D	' <<< "$LINT_RAW" && echo yes || echo no)"
expect_eq "…and every shipped file ended with every frame, case and heredoc closed" "" \
  "$(printf '%s\n' "$LINT_RAW" | LC_ALL=C awk -F'\t' '$1 == "U"')"
# The row above is a negative; this is its positive, on the same extractor: a file that ends
# inside an open double-quoted substitution is named, with the frames it was left in.
plant "$TMP/unclosed.sh" <<'EOF'
#!/bin/bash
x="@DOL@(printf '%s' "a"
EOF
expect_contains "…while a planted file left open is named with the frames it ended in" \
  "$TMP/unclosed.sh	top/dq/cs" "$(lint_raw "$TMP/unclosed.sh")"

# A lost brace depth is a lost place too (wave-28 T46). A form the lexer does not know leaves
# its count of `{` and `}` wrong, and from there it owes §LOAD no function, so a library
# 3.2 leaves half loaded would pass. Two valid forms it does not know, one each way: an
# arithmetic `for` with a brace body (depth below zero at its `}`), and a `}` straight after
# `fi` (depth above zero at the end). Each is named; the control beside them, an `esac`
# directly before the backquote that closes it, is a valid file the lexer reads whole.
plant "$TMP/brace-below.sh" <<'EOF'
#!/bin/bash
for ((i = 0; i < 1; i++)) { :; }  # MARK-below
early_fn() { :; }
[ "@DOL@{BASH_VERSINFO[0]}" -ge 4 ] || return 0
late_fn() { :; }
EOF
plant "$TMP/brace-above.sh" <<'EOF'
#!/bin/bash
early_fn() { if :; then :; fi }
[ "@DOL@{BASH_VERSINFO[0]}" -ge 4 ] || return 0
late_fn() { :; }
EOF
plant "$TMP/esac-bt.sh" <<'EOF'
#!/bin/bash
X="@DOL@(echo `case "@DOL@1" in a) echo A ;; *) echo B ;; esac`)"
printf 'X=[%s]\n' "@DOL@X"
EOF
expect_eq "the two lost-brace files and the esac control parse under /bin/bash -n" "0 0 0" \
  "$(/bin/bash -n "$TMP/brace-below.sh" 2>/dev/null; printf '%s ' $?
     /bin/bash -n "$TMP/brace-above.sh" 2>/dev/null; printf '%s ' $?
     /bin/bash -n "$TMP/esac-bt.sh" 2>/dev/null; printf '%s' $?)"
expect_eq "…each lost-brace file, loaded under /bin/bash, defines early_fn and not late_fn" \
  "early_fn | early_fn |" \
  "$(for f in brace-below brace-above; do (cd "$TMP" && env -i PATH=/usr/bin:/bin /bin/bash -c \
       '. "$1" >/dev/null 2>&1; declare -F' _ "$TMP/$f.sh") | LC_ALL=C awk '{ printf "%s ", $3 }'
     printf '| '; done | sed 's/ $//')"
expect_eq "…and the control runs under /bin/bash and answers" "X=[A]" \
  "$(/bin/bash "$TMP/esac-bt.sh" a 2>&1)"
BRACE_RAW="$(cd "$TMP" && lint_raw brace-below.sh brace-above.sh esac-bt.sh)"
expect_contains "the lexer names a file whose brace depth goes below zero, with the line" \
  "below-zero-at=$(mark_line "$TMP/brace-below.sh" MARK-below)" \
  "$(printf '%s\n' "$BRACE_RAW" | LC_ALL=C awk -F'\t' '$1 == "U" && $2 == "brace-below.sh"')"
expect_contains "…and a file whose brace depth ends above zero" "braces=1" \
  "$(printf '%s\n' "$BRACE_RAW" | LC_ALL=C awk -F'\t' '$1 == "U" && $2 == "brace-above.sh"')"
expect_absent "…while the esac control, read in the same call, is not named" "esac-bt.sh" \
  "$BRACE_RAW"

# ============================================================
section "PARSE — every shell file in the tree parses under the SYSTEM interpreter"
# ============================================================
#
# MOVED HERE from tests/cross-gate-agreement.test.sh §BP (wave-28 T37), rows and mutant
# unchanged. WHY IT EXISTS: cross-gate-agreement.test.sh once shipped a `case` inside a
# `$( … )`. Its own shebang says `#!/bin/bash`, which on macOS is bash 3.2, and 3.2's parser
# cannot read that construct, so the file was unparseable by the interpreter it names. It ran
# green for days because PATH resolved `bash` to a Homebrew 5.x build (Step-6 review C-2).
#
# IT IS A PARSE CHECK, NOT A RUN. `-n` reads and parses and executes nothing.
#
# THE ROSTER (critic K-6). Three directories, plus two shipped scripts that sit outside them:
# `agents-src/render.sh` (it writes the version half of AC-26 into payload/commands/help.md)
# and the root `wsl-setup.sh`. Both are named directly, so a stray future `*.sh` at the repo
# root still falls outside the sweep on purpose.
PARSE_SH="$(find "$HOOKS_DIR" "$SCRIPTS_DIR" "$TESTS_DIR" "$RENDER_SH" "$WSL_SH" \
  -name '*.sh' -type f 2>/dev/null | LC_ALL=C sort)"
expect_eq "the sweep found shell files to check" "yes" \
  "$([ -n "$PARSE_SH" ] && echo yes || echo no)"
# shellcheck disable=SC2086
PARSE_REL="$(rel $PARSE_SH)"
expect_eq "…and its roster reaches every root it names" "yes" \
  "$(LC_ALL=C grep -q '^hooks/' <<< "$PARSE_REL" \
     && LC_ALL=C grep -q '^payload/scripts/' <<< "$PARSE_REL" \
     && LC_ALL=C grep -q '^tests/' <<< "$PARSE_REL" \
     && LC_ALL=C grep -qx 'agents-src/render.sh' <<< "$PARSE_REL" \
     && LC_ALL=C grep -qx 'wsl-setup.sh' <<< "$PARSE_REL" && echo yes || echo no)"

parse_sweep() {  # <root> <newline-separated relative paths> -> one `FAIL <path>: <msg>` per
                 # file that does not parse
  local root="$1" list="$2" f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    /bin/bash -n "$root/$f" 2>&1 | sed "s|^|FAIL $f: |"
  done <<EOF
$list
EOF
  return 0
}

PARSE_OUT="$(parse_sweep "$REPO" "$PARSE_REL")"
expect_eq "every *.sh under hooks, payload/scripts and tests, and render.sh and wsl-setup.sh, parses under /bin/bash" \
  "" "$PARSE_OUT"
expect_eq "…and the system interpreter this asserts against is the one the shebangs name" \
  "yes" "$([ -x /bin/bash ] && echo yes || echo no)"

# THE MUTATION ARM. Plant the exact construct C-2 found — a `case` inside a command
# substitution — and require the sweep to name that file.
PARSE_MUT="$TMP/parse-mutant"
mkdir -p "$PARSE_MUT/tests"
cat > "$PARSE_MUT/tests/bp-planted.test.sh" <<'BPEOF'
#!/bin/bash
# A copy carrying the bash-3.2 defect C-2 found, for the mutation arm of §PARSE.
planted() {
  local n="$1"
  body=$(
    for x in $n; do
      case "$x" in
        *:*) echo "${x%%:*}" ;;
        *)   echo "$x" ;;
      esac
    done
  )
  printf '%s\n' "$body"
}
BPEOF
PARSE_MUT_OUT="$(/bin/bash -n "$PARSE_MUT/tests/bp-planted.test.sh" 2>&1)"
expect_eq "the mutation arm: the planted construct does NOT parse under /bin/bash" "yes" \
  "$([ -n "$PARSE_MUT_OUT" ] && echo yes || echo no)"
expect_contains "…and the failure names the case pattern that closes it" ";;" "$PARSE_MUT_OUT"
PARSE_SWEPT="$(parse_sweep "$PARSE_MUT" "tests/bp-planted.test.sh")"
expect_contains "…and the sweep reports it as a FAIL row naming the file" \
  "FAIL tests/bp-planted.test.sh" "$PARSE_SWEPT"

# ============================================================
section "LOAD — every library loads under /bin/bash with its functions defined"
# ============================================================
#
# `-n` parses; it does not run what a library runs as it loads. A top-level `declare -A`
# parses under 3.2 and fails when sourced, and a top-level test that returns early under 3.2
# leaves every function after it undefined. So each library is sourced in a bare /bin/bash,
# and every function the lexer finds it defining at load (column-0 command position, outside
# any function body and heredoc) must be defined afterwards, with nothing on stderr. No
# function is called.
LOAD_HOME="$TMP/load"
mkdir -p "$LOAD_HOME"
lint_load() {  # <file>... -> one `FAIL <file>: <why>` per library bash 3.2 does not load whole
  local f missing err
  for f in "$@"; do
    lint_raw "$f" | LC_ALL=C awk -F'\t' '$1 == "D" { print $3 }' | LC_ALL=C sort -u > "$LOAD_HOME/want"
    (cd "$LOAD_HOME" && env -i HOME="$LOAD_HOME" PATH=/usr/bin:/bin TMPDIR="$LOAD_HOME" \
      GIT_CEILING_DIRECTORIES="$LOAD_HOME" /bin/bash -c \
      '. "$1" </dev/null >/dev/null 2>"$2"; declare -F' _ "$f" "$LOAD_HOME/err" 2>/dev/null) \
      | LC_ALL=C awk '{ print $3 }' | LC_ALL=C sort -u > "$LOAD_HOME/got"
    err="$(head -1 "$LOAD_HOME/err" 2>/dev/null)"
    [ -z "$err" ] || printf 'FAIL %s: %s\n' "$f" "$err"
    missing="$(LC_ALL=C comm -23 "$LOAD_HOME/want" "$LOAD_HOME/got" | tr '\n' ' ')"
    [ -z "$missing" ] || printf 'FAIL %s: not defined after loading: %s\n' "$f" "$missing"
  done
  return 0
}

LOAD_LIBS="$(find "$LIB_DIR" -name '*.sh' -type f 2>/dev/null | LC_ALL=C sort)"
expect_eq "the load sweep found libraries" "yes" "$([ -n "$LOAD_LIBS" ] && echo yes || echo no)"
# shellcheck disable=SC2086
LOAD_WANT="$(lint_raw $LOAD_LIBS | LC_ALL=C awk -F'\t' '$1 == "D"')"
expect_eq "…and the lexer names functions they define at load" "yes" \
  "$([ -n "$LOAD_WANT" ] && echo yes || echo no)"
# shellcheck disable=SC2086
LOAD_OUT="$(lint_load $LOAD_LIBS)"
expect_eq "every library under payload/scripts/lib loads under /bin/bash with every function it defines" \
  "" "$LOAD_OUT"

# THE MUTATION ARM: three planted libraries in one sweep. Two parse under -n and still do not
# load whole under 3.2; the third is the control and loads.
cat > "$TMP/lib-assoc.sh" <<'EOF'
#!/bin/bash
declare -A LOAD_TABLE=()
assoc_fn() { :; }
EOF
cat > "$TMP/lib-early.sh" <<'EOF'
#!/bin/bash
early_fn() { :; }
[ "${BASH_VERSINFO[0]}" -ge 4 ] || return 0
late_fn() { :; }
EOF
cat > "$TMP/lib-clean.sh" <<'EOF'
#!/bin/bash
clean_fn() { :; }
helper() {
  inner_fn() { :; }
}
EOF
expect_eq "the planted libraries all parse under /bin/bash -n" "0 0 0" \
  "$(/bin/bash -n "$TMP/lib-assoc.sh" 2>/dev/null; printf '%s ' $?
     /bin/bash -n "$TMP/lib-early.sh" 2>/dev/null; printf '%s ' $?
     /bin/bash -n "$TMP/lib-clean.sh" 2>/dev/null; printf '%s' $?)"
LOAD_MUT="$(lint_load "$TMP/lib-assoc.sh" "$TMP/lib-early.sh" "$TMP/lib-clean.sh")"
expect_contains "…a top-level declare -A fails the load, named with its error" \
  "FAIL $TMP/lib-assoc.sh: " "$LOAD_MUT"
expect_contains "…a 3.2-only early return is named by the function it left undefined" \
  "FAIL $TMP/lib-early.sh: not defined after loading: late_fn" "$LOAD_MUT"
expect_absent "…while the clean library, read in the same sweep, is not named" \
  "lib-clean.sh" "$LOAD_MUT"
expect_eq "…and a function defined inside another is not owed at load" \
  "clean_fn helper " \
  "$(lint_raw "$TMP/lib-clean.sh" | LC_ALL=C awk -F'\t' '$1 == "D" { printf "%s ", $3 }')"

# The keyword forms (wave-28 T46): `function name {` and `function name() {` open a body as
# `name() {` does. A lexer that skips the keyword form's `{` reads its `}` as below zero and
# owes nothing after it, so the early return above went green behind a keyword definition.
cat > "$TMP/lib-kw.sh" <<'EOF'
#!/bin/bash
function kw_first { :; }
function kw_second() { :; }
[ "${BASH_VERSINFO[0]}" -ge 4 ] || return 0
function kw_third { :; }
kw_fourth() { :; }
EOF
expect_eq "the keyword-form library parses under /bin/bash -n" "0" \
  "$(/bin/bash -n "$TMP/lib-kw.sh" >/dev/null 2>&1; echo $?)"
expect_eq "…and loaded under /bin/bash it defines only the two before its early return" \
  "kw_first kw_second " \
  "$( (cd "$LOAD_HOME" && env -i PATH=/usr/bin:/bin /bin/bash -c \
     '. "$1" >/dev/null 2>&1; declare -F' _ "$TMP/lib-kw.sh") | LC_ALL=C awk '{ printf "%s ", $3 }')"
expect_eq "the lexer owes every function the keyword-form library defines at load" \
  "kw_first kw_second kw_third kw_fourth " \
  "$(lint_raw "$TMP/lib-kw.sh" | LC_ALL=C awk -F'\t' '$1 == "D" { printf "%s ", $3 }')"
expect_contains "…so the load sweep names the two the early return left undefined" \
  "FAIL $TMP/lib-kw.sh: not defined after loading: kw_fourth kw_third" \
  "$(lint_load "$TMP/lib-kw.sh" "$TMP/lib-clean.sh")"

# ============================================================
section "CASE — no case arm without its opening paren inside \$( )"
# ============================================================
#
# 3.2 reads `y)` inside `$( … )` as the substitution's end. Unquoted, `-n` catches it; inside
# double quotes it parses and fails only when the function runs — the T80 defect.
expect_eq "every shipped hook and payload script is clean of the CASE shape" "" \
  "$(shape_of CASE "$LINT_HITS")"

plant "$TMP/case-dq.sh" <<'EOF'
#!/bin/bash
t80() {
  X="@DOL@(for w in a b; do
    case "@DOL@w" in
      a) echo A ;;  # MARK-dq
      *) echo B ;;
    esac
  done)"
  printf '%s\n' "@DOL@X"
}
t80
EOF
plant "$TMP/case-unq.sh" <<'EOF'
#!/bin/bash
f() {
  X=@DOL@(case "@DOL@1" in
    a) echo A ;;  # MARK-unq
    *) echo B ;;
  esac)
}
EOF
plant "$TMP/case-inline.sh" <<'EOF'
#!/bin/bash
x="@DOL@(case "@DOL@1" in *a*) echo yes ;; *) echo no ;; esac)"  # MARK-inline
printf '%s' "@DOL@x"
EOF
# The controls: the paren-led arm T80's fix wrote, an arm at top level, an arm inside
# backquotes (3.2 parses backquoted text when it runs it, as a command), and an arm whose
# `$( )` sits in its subject, not around it.
plant "$TMP/case-ok.sh" <<'EOF'
#!/bin/bash
X="@DOL@(for w in a b; do
  case "@DOL@w" in
    (a) echo A ;;  # MARK-led
    (*) echo B ;;
  esac
done)"
case "@DOL@X" in
  a) echo top ;;  # MARK-top
esac
Y="`case a in a) echo bq ;; esac`"  # MARK-bq
case "@DOL@(printf a)" in
  a) echo subj ;;  # MARK-subj
esac
EOF
expect_eq "the T80 shape parses under /bin/bash -n" "0" \
  "$(/bin/bash -n "$TMP/case-dq.sh" >/dev/null 2>&1; echo $?)"
expect_contains "…and fails when its function runs under /bin/bash" "syntax error" \
  "$(/bin/bash "$TMP/case-dq.sh" 2>&1)"
expect_eq "…and the controls parse and run under /bin/bash" "0" \
  "$(/bin/bash "$TMP/case-ok.sh" >/dev/null 2>&1; echo $?)"
CASE_HITS="$(cd "$TMP" && lint_hits case-dq.sh case-unq.sh case-inline.sh case-ok.sh)"
expect_contains "the lint names the T80 shape in \"\$( )\" by file and line" \
  "case-dq.sh:$(mark_line "$TMP/case-dq.sh" MARK-dq): CASE" "$CASE_HITS"
expect_contains "…and the same arm in an unquoted \$( )" \
  "case-unq.sh:$(mark_line "$TMP/case-unq.sh" MARK-unq): CASE" "$CASE_HITS"
expect_contains "…and the one-line shape" \
  "case-inline.sh:$(mark_line "$TMP/case-inline.sh" MARK-inline): CASE" "$CASE_HITS"
expect_absent "…while no control, read in the same call, is named" "case-ok.sh" "$CASE_HITS"

# The keyword form inside "$( )" (wave-28 T46): the arm after `function g { case … in` is in a
# body the lexer must see open. The control is the same function with paren-led arms.
plant "$TMP/case-fn.sh" <<'EOF'
#!/bin/bash
X="@DOL@(function g { case "@DOL@1" in
    a) echo A ;;  # MARK-fn
  esac; }; g a)"
printf 'X=[%s]\n' "@DOL@X"
EOF
plant "$TMP/case-fn-ok.sh" <<'EOF'
#!/bin/bash
X="@DOL@(function g { case "@DOL@1" in
    (a) echo A ;;
  esac; }; g a)"
printf 'X=[%s]\n' "@DOL@X"
EOF
expect_eq "the keyword-form arm and its control parse under /bin/bash -n" "0 0" \
  "$(/bin/bash -n "$TMP/case-fn.sh" 2>/dev/null; printf '%s ' $?
     /bin/bash -n "$TMP/case-fn-ok.sh" 2>/dev/null; printf '%s' $?)"
expect_contains "…the arm fails when it runs under /bin/bash" "syntax error" \
  "$(/bin/bash "$TMP/case-fn.sh" 2>&1)"
expect_eq "…while the control answers" "X=[A]" "$(/bin/bash "$TMP/case-fn-ok.sh" 2>&1)"
CASE_FN_HITS="$(cd "$TMP" && lint_hits case-fn.sh case-fn-ok.sh)"
expect_contains "the lint names the arm after \`function g {\` by file and line" \
  "case-fn.sh:$(mark_line "$TMP/case-fn.sh" MARK-fn): CASE" "$CASE_FN_HITS"
expect_absent "…while the control, read in the same call, is not named" "case-fn-ok.sh" \
  "$CASE_FN_HITS"

# MOVED HERE from tests/cross-gate-agreement.test.sh §BP (wave-28 T37): the one-line grep, over
# §PARSE's roster, which reaches tests/ where the lexer does not. A one-line `case` inside a
# command substitution PARSES under 3.2 and then evaluates to the tail of its own source text —
# two rows of cross-gate §S2 once read `expected 'no', got ' echo yes ;; *) echo no ;; esac)'`
# under /bin/bash while `-n` said the file was fine. The pattern is written in bracket classes
# so that this file's own source does not match the rule it enforces.
BP_RE='[$][(]case '
# shellcheck disable=SC2086
BP_INLINE="$(cd "$REPO" && LC_ALL=C grep -nE "$BP_RE" $PARSE_REL 2>/dev/null)"
expect_eq "no file opens a \`case\` inside a command substitution on one line" "" "$BP_INLINE"

# The mutation arm, and it is the QUOTED shape on purpose: unquoted, 3.2 refuses to parse
# and `-n` catches it; inside double quotes it parses clean and then truncates the
# substitution at the first `)` at RUN time, leaking the rest as literal text.
BP_INLINE_PLANT="$TMP/bp-inline.sh"
BP_DOL='$'
printf '#!/bin/bash\nx="%s(case "%s1" in *a*) echo yes ;; *) echo no ;; esac)"\nprintf "%%s" "%sx"\n' \
  "$BP_DOL" "$BP_DOL" "$BP_DOL" > "$BP_INLINE_PLANT"
expect_eq "the mutation arm: the quoted one-line shape PARSES, so -n cannot catch it" "0" \
  "$(/bin/bash -n "$BP_INLINE_PLANT" >/dev/null 2>&1; echo $?)"
expect_contains "…and at run time it leaks its own source text instead of answering" \
  "esac)" "$(/bin/bash "$BP_INLINE_PLANT" abc 2>/dev/null)"
expect_eq "…but the grep catches it" "yes" \
  "$([ -n "$(LC_ALL=C grep -nE "$BP_RE" "$BP_INLINE_PLANT")" ] && echo yes || echo no)"

# ============================================================
section "HEREDOC — review pass 73's two heredoc shapes"
# ============================================================
#
# (i) A heredoc whose delimiter is unquoted is expanded when it runs, and a `$( )` in its
# body is read then, by the same 3.2 reader: a paren-less arm there fails at run time.
# (ii) A heredoc inside `$( … )` is raw text to 3.2's reader, which knows nothing of
# heredocs: a lone `)` in its body ends the substitution, silently.
expect_eq "every shipped hook and payload script is clean of HEREDOC-CASE" "" \
  "$(shape_of HEREDOC-CASE "$LINT_HITS")"
expect_eq "…and of HEREDOC-PAREN" "" "$(shape_of HEREDOC-PAREN "$LINT_HITS")"

plant "$TMP/hd-case.sh" <<'EOF'
#!/bin/bash
f() {
  cat <<EOT
@DOL@(case z in
 y) echo yes ;;  MARK-hdc
 *) echo no ;;
esac)
EOT
}
f
EOF
plant "$TMP/hd-case-inline.sh" <<'EOF'
#!/bin/bash
cat <<EOT
@DOL@(case z in y) echo yes ;; *) echo no ;; esac) MARK-hdi
EOT
EOF
plant "$TMP/hd-paren.sh" <<'EOF'
#!/bin/bash
f() {
  x="@DOL@(cat <<'EOT'
a lone ) paren MARK-hdp
EOT
)"
  printf '%s\n' "@DOL@x"
}
f
EOF
# The controls: the same body under a quoted delimiter (never expanded), and a heredoc inside
# "$( )" whose body balances its parentheses, as payload/scripts/lib/deps.sh's table does.
plant "$TMP/hd-ok.sh" <<'EOF'
#!/bin/bash
cat <<'EOT'
@DOL@(case z in
 y) echo yes ;;  MARK-hdq
esac)
EOT
x="@DOL@(cat <<'EOT'
a (balanced) paren MARK-hdb
EOT
)"
printf '%s\n' "@DOL@x"
EOF
expect_eq "the planted heredoc shapes all parse under /bin/bash -n" "0 0 0" \
  "$(/bin/bash -n "$TMP/hd-case.sh" 2>/dev/null; printf '%s ' $?
     /bin/bash -n "$TMP/hd-case-inline.sh" 2>/dev/null; printf '%s ' $?
     /bin/bash -n "$TMP/hd-paren.sh" 2>/dev/null; printf '%s' $?)"
expect_contains "…shape (i) fails when it runs under /bin/bash" "syntax error" \
  "$(/bin/bash "$TMP/hd-case.sh" 2>&1)"
expect_contains "…shape (ii) leaks its own heredoc text instead of the body" "EOT" \
  "$(/bin/bash "$TMP/hd-paren.sh" 2>/dev/null)"
expect_eq "…while the balanced control prints its body whole" "a (balanced) paren MARK-hdb" \
  "$(/bin/bash "$TMP/hd-ok.sh" 2>/dev/null | tail -1)"
HD_HITS="$(cd "$TMP" && lint_hits hd-case.sh hd-case-inline.sh hd-paren.sh hd-ok.sh)"
expect_contains "the lint names shape (i) by file and line" \
  "hd-case.sh:$(mark_line "$TMP/hd-case.sh" MARK-hdc): HEREDOC-CASE" "$HD_HITS"
expect_contains "…and its one-line form" \
  "hd-case-inline.sh:$(mark_line "$TMP/hd-case-inline.sh" MARK-hdi): HEREDOC-CASE" "$HD_HITS"
expect_contains "…and shape (ii) by file and line" \
  "hd-paren.sh:$(mark_line "$TMP/hd-paren.sh" MARK-hdp): HEREDOC-PAREN" "$HD_HITS"
expect_absent "…while neither control, read in the same call, is named" "hd-ok.sh" "$HD_HITS"

# The comment 3.2's reader honours (wave-28 T46). A `#` at a word start (the line's start, or
# after a blank) comments out the rest of its line: no paren after it counts. So a `(` there
# hides nothing and a `)` there closes nothing: the first body below leaks, the second prints
# whole. (Measured under 3.2.57: a mid-word `#`, or one after `;`, `|`, `(`, is no comment.)
plant "$TMP/hd-hash.sh" <<'EOF'
#!/bin/bash
x="@DOL@(cat <<'EOT'
# open ( here
close ) there MARK-hho
EOT
)"
printf '[%s]\n' "@DOL@x"
EOF
plant "$TMP/hd-hash-ok.sh" <<'EOF'
#!/bin/bash
x="@DOL@(cat <<'EOT'
# note ) here MARK-hhn
EOT
)"
printf '[%s]\n' "@DOL@x"
EOF
expect_eq "the two commented bodies parse under /bin/bash -n" "0 0" \
  "$(/bin/bash -n "$TMP/hd-hash.sh" 2>/dev/null; printf '%s ' $?
     /bin/bash -n "$TMP/hd-hash-ok.sh" 2>/dev/null; printf '%s' $?)"
expect_contains "…a ( after the # hides nothing: the ) on the next line leaks the heredoc" "EOT" \
  "$(/bin/bash "$TMP/hd-hash.sh" 2>/dev/null)"
expect_eq "…while a ) after the # closes nothing: the body prints whole" \
  "[# note ) here MARK-hhn]" "$(/bin/bash "$TMP/hd-hash-ok.sh" 2>/dev/null)"
HD_HASH_HITS="$(cd "$TMP" && lint_hits hd-hash.sh hd-hash-ok.sh)"
expect_contains "the lint names the ) that leaks, by file and line" \
  "hd-hash.sh:$(mark_line "$TMP/hd-hash.sh" MARK-hho): HEREDOC-PAREN" "$HD_HASH_HITS"
expect_absent "…and not the ) behind the #, read in the same call" "hd-hash-ok.sh" "$HD_HASH_HITS"

# What 3.2 does when the body RUNS (the plan's T46 ruling, A-orch-23): after the comment's `#`
# no quote pairs either, so a lone quote there leaves the next line's `)` lone; and a `#` is a
# comment only at a line's start or after a blank, as each boundary below was measured.
# hd_plant <file> <body> -> a script that captures a quoted heredoc holding <body> in "$( )"
# and prints what it captured
hd_plant() {
  printf '#!/bin/bash\nx="$(cat <<'"'"'EOT'"'"'\n%s\nEOT\n)"\nprintf '"'"'[%%s]\\n'"'"' "$x"\n' \
    "$2" > "$1"
}
HD_B_DIR="$TMP/hd-bound"
mkdir -p "$HD_B_DIR"
HD_B_CASES=""
hd_case() {  # <name> <leaks|whole> <body>
  hd_plant "$HD_B_DIR/$1.sh" "$3"; HD_B_CASES="$HD_B_CASES $1:$2"
}
hd_case comment-squote leaks "# it's
x ) y
' z"
hd_case comment-dquote leaks '# say "hi
x ) y
" z'
hd_case semicolon leaks 'a;# ) y'
hd_case pipe leaks 'a|# ) y'
hd_case open-paren leaks 'a(# ) y ) z'
hd_case close-paren leaks '(a)# ) y'
hd_case equals leaks 'a=# ) y'
hd_case brace leaks 'a{# ) y'
hd_case backquote leaks '`a`# ) y'
hd_case squote leaks "'a'# ) y"
hd_case dquote leaks '"a"# ) y'
hd_case space whole 'see #1 ) here'
hd_case tab whole "$(printf '\t# x ) y')"
expect_eq "every planted boundary body parses under /bin/bash -n" "13 of 13" \
  "$(n=0; ok=0; for c in $HD_B_CASES; do n=$((n + 1))
       /bin/bash -n "$HD_B_DIR/${c%%:*}.sh" >/dev/null 2>&1 && ok=$((ok + 1)); done
     echo "$ok of $n")"
HD_B_HITS="$(cd "$HD_B_DIR" && lint_hits ./*.sh)"
for c in $HD_B_CASES; do
  f="$HD_B_DIR/${c%%:*}.sh"
  if [ "${c#*:}" = leaks ]; then
    expect_contains "${c%%:*}: run under /bin/bash, the ) leaks the heredoc" "EOT" \
      "$(/bin/bash "$f" 2>/dev/null)"
    expect_contains "${c%%:*}: …and the lint names it by file and line" \
      "${c%%:*}.sh:$(mark_line "$f" ' ) '): HEREDOC-PAREN" "$HD_B_HITS"
  else
    expect_eq "${c%%:*}: run under /bin/bash, the body prints whole" \
      "[$(sed -n 3p "$f")]" "$(/bin/bash "$f" 2>/dev/null)"
    expect_absent "${c%%:*}: …and the lint, in the same call, does not name it" "/${c%%:*}.sh:" "$HD_B_HITS"
  fi
done

# ============================================================
section "BP — no writer is piped into a reader that quits early where the status is read"
# ============================================================
#
# fails-when: a hook or payload script pipes a writer into `grep -q`, `grep -l`, `grep -m`, `head` or an
# awk that exits, under pipefail with the status read, and neither fixes it nor lists it with a reason; or
# the process scan in observe.sh is the quitting form again.
#
# WHY IT EXISTS. `w | grep -q x` parses and answers right while w's output fits the 64 KB pipe buffer.
# Past it, grep exits at the first match while w is still writing, w takes SIGPIPE, and under pipefail the
# pipeline reports w's 141: `if w | grep -q x` reads a present line as absent, and a wall built on it
# inverts. The sites are found by reading the shell, because no run at test size can see them.
#
# THE ROSTER: hooks/, payload/scripts/ and the two files of the declared release check's closure
# (tests/lib/release-check.sh and tests/lib/name-scan.sh). Other suites build fixtures and are not walls.
#
# WHAT IS A SITE. A pipe whose far side is a quitting reader: grep with -q, -l or -m (also --quiet,
# --silent, --files-with-matches, --max-count), head, or an awk program with an `exit` outside its END.
# The file must run under pipefail: it sets it, or it is a library (a path with /lib/ or under
# hooks/poker/), which runs inside whichever process sourced it. The status must be read:
#   grep -q or -l      always, since a pipeline that only reports a status is read for it
#   the others         an `&&` or `||` after them, `; then` or `; do`, a `$?` on the line or the next
#                      line, or a `then` on the next line; inside `$( )` only when the substitution is
#                      the value of an assignment and one of those follows it
# WHAT IS EXCUSED, each with a control below: a whole-line or trailing comment; a heredoc body; a pipe that
# is `||` or `|&` or sits inside quotes; an awk whose only `exit` is in END (it has read every line); a
# limiter whose status nobody reads (`v=$(w | head -n 1)` keeps the whole value); `|| true` or `|| :`;
# a file that is an entry point and sets no pipefail. NOT READ: sed with a q command, `read` fed by a
# pipe, and errexit (no file of the roster sets it).
#
# THE ALLOW FILE, tests/lib/quitting-readers.allow: `<path>:<pattern> # <reason>`. The pattern is a
# fixed substring of the logical line; the reason says why the writer cannot outrun the buffer. A line
# without a reason, without a colon, or naming a path outside the roster is refused.
QUIT_AWK="$TMP/quit.awk"
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
QUIT_ALLOW="$TESTS_DIR/lib/quitting-readers.allow"

# quit_sweep <root> <allow file> <relative path>... -> the Q and A rows the awk prints
quit_sweep() {
  local root="$1" allow="$2" roster f
  shift 2
  roster="$(mktemp "$TMP/quit-roster.XXXXXX")"
  printf '%s\n' "$@" > "$roster"
  ( cd "$root" || exit 1
    LC_ALL=C awk -v REPORT=1 -v ALLOW="$allow" -v ROSTER="$roster" -f "$QUIT_AWK" /dev/null
    for f in "$@"; do
      LC_ALL=C awk -v ALLOW="$allow" -v ROSTER="$roster" -f "$QUIT_AWK" "$f"
    done )
}
# quit_sites <sweep output> -> the sorted path:line of each site
quit_sites() { printf '%s\n' "$1" | LC_ALL=C awk -F'\t' '$1 == "Q" { print $2 }' | LC_ALL=C sort; }

BP_ROSTER="$(cd "$REPO" && { find hooks payload/scripts -name '*.sh' -type f; \
  printf '%s\n' tests/lib/release-check.sh tests/lib/name-scan.sh; } 2>/dev/null | LC_ALL=C sort)"
expect_eq "the sweep found shell files to read" "yes" "$([ -n "$BP_ROSTER" ] && echo yes || echo no)"
expect_eq "…and its roster reaches hooks, payload/scripts and both files of the check closure" "yes" \
  "$(LC_ALL=C grep -q '^hooks/poker/' <<< "$BP_ROSTER" \
     && LC_ALL=C grep -q '^payload/scripts/lib/' <<< "$BP_ROSTER" \
     && LC_ALL=C grep -qx 'tests/lib/release-check.sh' <<< "$BP_ROSTER" \
     && LC_ALL=C grep -qx 'tests/lib/name-scan.sh' <<< "$BP_ROSTER" && echo yes || echo no)"
expect_eq "the allow file exists" "yes" "$([ -f "$QUIT_ALLOW" ] && echo yes || echo no)"

# BP-1: the real tree. Every site is fixed or listed with a reason.
# shellcheck disable=SC2086
BP_REAL="$(quit_sweep "$REPO" "$QUIT_ALLOW" $BP_ROSTER)"
expect_eq "BP-1 no hook or payload script pipes a writer into a quitting reader unlisted" "" "$BP_REAL"
# shellcheck disable=SC2086
BP_NONE="$(quit_sweep "$REPO" /dev/null $BP_ROSTER)"
expect_contains "…and with no allow file the same sweep names the carrier site in the tick, so the file is what silences it" \
  "hooks/poker/tick.sh:" "$(quit_sites "$BP_NONE")"

# BP-2: planted sites, read by the same instrument in the same call as their controls.
BP2="$TMP/bp2"
mkdir -p "$BP2/hooks/poker" "$BP2/payload/scripts/lib"
plant "$BP2/hooks/plant.sh" <<'EOF'
#!/bin/bash
set -uo pipefail
gen() { seq 1 5; }
if git show HEAD:x | grep -q y; then :; fi  # MARK-S1
gen | grep -m1 needle && echo y  # MARK-S2
gen | grep -l needle && echo y  # MARK-S3
v=$(gen | head -n 1) || v=none  # MARK-S4
gen | awk '/needle/ { exit }' && echo y  # MARK-S5
if ! gen | head -1 | grep -c y >/dev/null; then :; fi  # MARK-S6
# MARK-S7 the next two lines are one pipeline
if gen \
  | grep -qF needle; then :; fi
if gen | awk '
    /needle/ { print; exit }
  ' | grep -c . >/dev/null; then :; fi  # MARK-S8
v=$(gen | head -n 1)  # MARK-C1 the value is whole and nobody reads the status
# if gen | grep -q needle; then :; fi  # MARK-C2 a comment
gen | awk '{ n++ } END { exit n > 3 }' && echo y  # MARK-C3 an exit in END has read every line
grep -qF needle <<< "$v" && echo y  # MARK-C4 a here-string has no writer
gen | grep -q needle || true  # MARK-C5 the status is thrown away
if gen | grep needle >/dev/null; then :; fi  # MARK-C6 reads to the end
if gen | grep -c needle; then :; fi  # MARK-C7 reads to the end
x="gen | grep -q y" && echo "$x"  # MARK-C8 the pipe is quoted
gen | head -n 3  # MARK-C9 a limiter whose status nobody reads
cat <<'DOC'
if gen | grep -q needle; then :; fi  # MARK-C10 heredoc text
DOC
if printf '%s\n' "$bounded" | grep -qx needle; then :; fi  # MARK-A1 allowed with a reason
EOF
plant "$BP2/hooks/plain.sh" <<'EOF'
#!/bin/bash
gen() { seq 1 5; }
if gen | grep -q needle; then :; fi  # MARK-P1 an entry point that sets no pipefail
EOF
plant "$BP2/payload/scripts/lib/plant-lib.sh" <<'EOF'
gen() { seq 1 5; }
if gen | grep -q needle; then :; fi  # MARK-L1 a library runs inside its caller
EOF
plant "$BP2/hooks/poker/plant-tick.sh" <<'EOF'
landing_carrier_names "$plan" | /usr/bin/grep -qxF -- "$name" && return 0  # MARK-CARRIER the carrier exemption as a quitting grep
EOF
printf '%s\n' '# a comment' '' 'hooks/plant.sh:printf '"'"'%s\n'"'"' "$bounded" # the writer is one short variable' > "$BP2/allow"
BP2_ROSTER="hooks/plant.sh
hooks/plain.sh
payload/scripts/lib/plant-lib.sh
hooks/poker/plant-tick.sh"
# shellcheck disable=SC2086
BP2_OUT="$(quit_sweep "$BP2" "$BP2/allow" $BP2_ROSTER)"
BP2_SITES="$(quit_sites "$BP2_OUT")"
bp2_at() { printf '%s:%s\n' "$1" "$(mark_line "$BP2/$1" "$2")"; }
# bp_fline <file> <fixed text> -> the number of the first line that holds the text
bp_fline() { LC_ALL=C grep -nF -- "$2" "$1" | head -1 | cut -d: -f1; }
expect_contains "BP-2 a pipe from git show into grep -q is named by file and line" "$(bp2_at hooks/plant.sh MARK-S1)" "$BP2_SITES"
expect_contains "…grep -m1 with an && after it" "$(bp2_at hooks/plant.sh MARK-S2)" "$BP2_SITES"
expect_contains "…grep -l with an && after it" "$(bp2_at hooks/plant.sh MARK-S3)" "$BP2_SITES"
expect_contains "…head -n inside an assignment with a || after it" "$(bp2_at hooks/plant.sh MARK-S4)" "$BP2_SITES"
expect_contains "…an awk that exits, with an && after it" "$(bp2_at hooks/plant.sh MARK-S5)" "$BP2_SITES"
expect_contains "…head -1 in an if condition" "$(bp2_at hooks/plant.sh MARK-S6)" "$BP2_SITES"
expect_contains "…a pipeline split across lines, named at its first line" \
  "hooks/plant.sh:$(( $(mark_line "$BP2/hooks/plant.sh" MARK-S7) + 1 ))" "$BP2_SITES"
expect_contains "…an awk program open across lines" "hooks/plant.sh:$(( $(mark_line "$BP2/hooks/plant.sh" MARK-S8) - 2 ))" "$BP2_SITES"
expect_contains "…a library with no pipefail of its own" "$(bp2_at payload/scripts/lib/plant-lib.sh MARK-L1)" "$BP2_SITES"
expect_contains "…the carrier exemption as a quitting grep, in a file the allow file does not name" \
  "$(bp2_at hooks/poker/plant-tick.sh MARK-CARRIER)" "$BP2_SITES"
expect_eq "…and the sites named are those and no others, so every control in the same call passes" \
  "$(printf '%s\n' "$(bp2_at hooks/plant.sh MARK-S1)" "$(bp2_at hooks/plant.sh MARK-S2)" "$(bp2_at hooks/plant.sh MARK-S3)" \
       "$(bp2_at hooks/plant.sh MARK-S4)" "$(bp2_at hooks/plant.sh MARK-S5)" "$(bp2_at hooks/plant.sh MARK-S6)" \
       "hooks/plant.sh:$(( $(mark_line "$BP2/hooks/plant.sh" MARK-S7) + 1 ))" \
       "hooks/plant.sh:$(( $(mark_line "$BP2/hooks/plant.sh" MARK-S8) - 2 ))" \
       "$(bp2_at payload/scripts/lib/plant-lib.sh MARK-L1)" "$(bp2_at hooks/poker/plant-tick.sh MARK-CARRIER)" | LC_ALL=C sort)" \
  "$BP2_SITES"
expect_eq "…the listed line is silenced by its allow entry" "no" \
  "$(quit_sites "$BP2_OUT" | LC_ALL=C grep -qx "$(bp2_at hooks/plant.sh MARK-A1)" && echo yes || echo no)"
expect_eq "…and was a site before it was listed" "yes" \
  "$(quit_sites "$(quit_sweep "$BP2" /dev/null $BP2_ROSTER)" | grep -qx "$(bp2_at hooks/plant.sh MARK-A1)" && echo yes || echo no)"

# BP-3: observe.sh with the quitting form restored, in a scratch copy of the real file.
BP3="$TMP/bp3"
mkdir -p "$BP3/payload/scripts/lib"
LC_ALL=C awk '
  /procs="\$\(ps -eo command/ { print "  ps -eo command 2>/dev/null | grep -qF -- \"$pat\""; skip = 1; next }
  skip && /<<< "\$procs"/ { skip = 0; next }
  { print }' "$LIB_DIR/observe.sh" > "$BP3/payload/scripts/lib/observe.sh"
expect_eq "BP-3 the scratch copy has the quitting scan and parses" "1 0" \
  "$(/usr/bin/grep -cF 'ps -eo command 2>/dev/null | grep -qF' "$BP3/payload/scripts/lib/observe.sh") $(/bin/bash -n "$BP3/payload/scripts/lib/observe.sh" >/dev/null 2>&1; echo $?)"
BP3_OUT="$(quit_sweep "$BP3" "$QUIT_ALLOW" payload/scripts/lib/observe.sh)"
expect_contains "…and the sweep names it, unlisted, by file and line" \
  "payload/scripts/lib/observe.sh:$(bp_fline "$BP3/payload/scripts/lib/observe.sh" 'ps -eo command 2>/dev/null | grep -qF')" \
  "$(quit_sites "$BP3_OUT")"
expect_eq "…while the shipped observe.sh, read in the same call, is not named" "" \
  "$(quit_sites "$(quit_sweep "$REPO" "$QUIT_ALLOW" payload/scripts/lib/observe.sh)")"

# BP-4: an allow line must carry its reason.
BP4="$TMP/bp4.allow"
{ printf '%s\n' '# a comment' ''
  printf '%s\n' 'hooks/plant.sh:printf '"'"'%s\n'"'"' "$bounded"'
  printf '%s\n' 'hooks/plant.sh:printf '"'"'%s\n'"'"' "$bounded" # '
  printf '%s\n' 'no colon here # a reason'
  printf '%s\n' 'hooks/nowhere.sh:x # a reason'; } > "$BP4"
# shellcheck disable=SC2086
BP4_OUT="$(quit_sweep "$BP2" "$BP4" $BP2_ROSTER)"
expect_eq "BP-4 an allow line with no reason, an empty one, one with no colon and one with a path outside the roster are each refused by line" \
  "3 4 5 6" "$(printf '%s\n' "$BP4_OUT" | LC_ALL=C awk -F'\t' '$1 == "A" { print $2 }' | LC_ALL=C sort -n | tr '\n' ' ' | sed 's/ $//')"
expect_contains "…and a refused entry silences nothing: the line it named is still a site" \
  "$(bp2_at hooks/plant.sh MARK-A1)" "$(quit_sites "$BP4_OUT")"
expect_eq "…while the comment, the blank line and the entry with its reason, read in the same call, are not refused" "" \
  "$(quit_sweep "$BP2" "$BP2/allow" $BP2_ROSTER | LC_ALL=C awk -F'\t' '$1 == "A"')"
expect_eq "the real allow file has no refused line" "" \
  "$(printf '%s\n' "$BP_REAL" | LC_ALL=C awk -F'\t' '$1 == "A"')"

# ============================================================
section "BP-PIN — a writer of more than 64 KB into the fixed form returns 0 under pipefail"
# ============================================================
#
# fails-when: the process scan in observe_claims_live is `ps | grep -qF` again, so a process listing larger than
# the pipe buffer with the match near its top returns 141 under pipefail and the claim reads as dead.
#
# The writer is `seq 1 20000` (108894 bytes). The match must come BEFORE the bulk: a reader whose match is
# on the last line has read everything and quits no earlier than a reader that reads to the end, so only a
# match-first listing can show the defect. The real function is driven with a stub `ps` and a PATH that
# holds no `pgrep`, so it takes its `ps` fallback, with pipefail set the way a hook sets it.
pin_writer() { printf 'needle\n'; seq 1 20000; }
expect_true "the writer is larger than the 64 KB pipe buffer" [ "$(pin_writer | wc -c | tr -d ' ')" -gt 65536 ]
expect_eq "…the quitting form on it returns 141 under pipefail: the defect is real on this machine" "141" \
  "$(set -o pipefail; pin_writer | /usr/bin/grep -q needle; echo $?)"
expect_eq "…the quitting form returns 0 without pipefail, so only the pipeline status is lost" "0" \
  "$(set +o pipefail; pin_writer | /usr/bin/grep -q needle; echo $?)"
expect_eq "…a here-string of the same writer returns 0 under pipefail" "0" \
  "$(set -o pipefail; v="$(pin_writer)"; /usr/bin/grep -qF needle <<< "$v"; echo $?)"
expect_eq "…and so does a match on the last line" "0" \
  "$(set -o pipefail; v="$({ seq 1 20000; printf 'needle\n'; })"; /usr/bin/grep -qF needle <<< "$v"; echo $?)"

PIN_BIN="$TMP/pin-bin"
mkdir -p "$PIN_BIN"
printf '%s\n' '#!/bin/bash' 'printf "needle-proc --flag\n"' 'PATH=/usr/bin:/bin' 'seq 1 20000' > "$PIN_BIN/ps"
chmod +x "$PIN_BIN/ps"
ln -s /usr/bin/grep "$PIN_BIN/grep"
pin_scan() {  # <observe.sh> -> observe_claims_live's status for a process that is listed, under pipefail
  env -i PATH="$PIN_BIN" /bin/bash -c 'set -o pipefail; . "$1"; observe_claims_live needle-proc; echo $?' _ "$1" 2>/dev/null
}
expect_true "the stub listing is larger than the pipe buffer" [ "$("$PIN_BIN/ps" | wc -c | tr -d ' ')" -gt 65536 ]
expect_eq "the PATH holds no pgrep, so the ps fallback is the branch that runs" "no" \
  "$(env -i PATH="$PIN_BIN" /bin/bash -c 'command -v pgrep >/dev/null 2>&1 && echo yes || echo no')"
expect_eq "observe_claims_live finds a listed process in a listing larger than the pipe buffer" "0" \
  "$(pin_scan "$LIB_DIR/observe.sh")"
expect_eq "…and with the quitting scan restored in a scratch copy the same call returns 141" "141" \
  "$(pin_scan "$BP3/payload/scripts/lib/observe.sh")"

# ── the census ───────────────────────────────────────────────────────────────
# tests/CENSUS.md holds one record line per section of every suite under tests/, under a heading per
# suite, in the shape tests/RUBRIC.md §4 sets. This sweep refuses a tests tree the census does not
# cover. A `section` call is found by the rubric's own section-list command, extracted from the
# rubric and run here, so there is one key rule and no second copy of it. A call inside a heredoc
# body is fixture text, written into a scratch suite, and is not a section.
CENSUS_MD="$TESTS_DIR/CENSUS.md"
CENSUS_RUBRIC="$TESTS_DIR/RUBRIC.md"
CENSUS_PROG="$TMP/census-prog.awk"
cat > "$TMP/census-extract.awk" <<'CENSUS_EXTRACT_EOF'
index($0, "awk '/^[[:space:]]*(setup_)?section") == 1 { on = 1; sub(/^awk '/, "") }
on && (i = index($0, "' tests/<suite>.test.sh")) { print substr($0, 1, i - 1); exit }
on { print }
CENSUS_EXTRACT_EOF
awk -f "$TMP/census-extract.awk" "$CENSUS_RUBRIC" > "$CENSUS_PROG" 2>/dev/null
# The file with every heredoc body blanked, line numbers kept. A `<<` opens a body only outside
# quotes (a nested `$( )` has quotes of its own) and not as a here-string, and a body ends at its
# delimiter line.
cat > "$TMP/census-blank.awk" <<'CENSUS_BLANK_EOF'
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
  d="$(mktemp -d "$TMP/census-blank.XXXXXX")"
  for f in "$1"/*.test.sh; do
    [ -f "$f" ] || continue
    awk -f "$TMP/census-blank.awk" "$f" > "$d/${f##*/}"
  done
  ( cd "$d" && LC_ALL=C awk -f "$CENSUS_PROG" ./*.test.sh 2>/dev/null ) \
    | awk '{ loc = $1; kind = $2; key = $0; sub(/^[^ ]+ [^ ]+ §/, "", key); sub(/^\.\//, "", loc); sub(/:[0-9]+$/, "", loc)
             printf "%s\t%s\t%s\n", loc, kind, key }'
}
# census_records <census file> -> `R TAB <suite> TAB <key> TAB <verdict> TAB <defect>` per record line.
census_records() {
  awk -F' [|] ' '/^[A-Za-z0-9._-]+\.test\.sh [|] / { k = $2; sub(/^§/, "", k); printf "R\t%s\t%s\t%s\t%s\n", $1, k, $3, $4 }' "$1" 2>/dev/null
}
# census_refusals <tests dir> <census file> -> one line per refusal, none when the census covers the tree:
#   no heading: a suite with no `## <suite>` heading
#   no line: a suite with no section call and no `no section` line
#   no verdict: a section call with fewer record lines under its key than the suite has calls of it
#   bad verdict: a record line whose verdict is not one of the five words
#   rule mark on a cull: a `rule:` defect on a line whose verdict is not keep
#   no section line on a suite with sections: the `no section` line beside a suite that has calls
census_refusals() {
  local f
  {
    for f in "$1"/*.test.sh; do [ -f "$f" ] && printf 'S\t%s\n' "${f##*/}"; done
    sed -n 's/^## \(.*\.test\.sh\)$/H\t\1/p' "$2" 2>/dev/null
    census_records "$2"
    census_calls "$1" | sed 's/^/C\t/'
  } | LC_ALL=C awk -F'\t' '
    $1 == "S" { suite[$2] = 1 }
    $1 == "H" { head[$2] = 1 }
    $1 == "C" { ncall[$2]++; if ($3 == "section") need[$2 SUBSEP $4]++ }
    $1 == "R" {
      s = $2; k = $3; v = $4; d = $5
      if (k == "—" && v == "—" && d == "no section") { nosec[s] = 1; next }
      have[s SUBSEP k]++
      if (v != "keep" && v != "duplicate" && v != "prose pin" && v != "tally" && v != "vacuous") print "bad verdict: " s " §" k " " v
      else if (d ~ /^rule: / && v != "keep") print "rule mark on a cull: " s " §" k " " v
    }
    END {
      for (s in suite) {
        if (!(s in head)) print "no heading: " s
        if (ncall[s] == 0 && !(s in nosec)) print "no line: " s
        if (ncall[s] > 0 && (s in nosec)) print "no section line on a suite with sections: " s
      }
      for (key in need) { split(key, p, SUBSEP); if (have[key] < need[key]) print "no verdict: " p[1] " §" p[2] }
    }' | LC_ALL=C sort
}
# census_scratch <dir> -> a tests tree of three suites: x with two sections, y with none, z holding a
# section call only inside a heredoc body that writes a scratch suite.
census_scratch() {
  mkdir -p "$1/tests"
  printf '%s\n' 'section "ONE: the first"' 'expect_eq a 1 1' 'section "TWO: the second"' 'expect_eq b 1 1' > "$1/tests/x.test.sh"
  printf '%s\n' 'echo no sections here' > "$1/tests/y.test.sh"
  printf '%s\n' "cat > scratch.sh <<'PLANT'" 'section "HIDDEN: inside a heredoc"' 'PLANT' 'echo done' > "$1/tests/z.test.sh"
}
# census_file <file> <x lines...> -> a census with headings for x, y and z, y and z with a `no section` line, and
# the given record lines under x.
census_file() {
  local out="$1"; shift
  { printf '# census\n\n## x.test.sh\n'; [ "$#" -eq 0 ] || printf '%s\n' "$@"
    printf '\n## y.test.sh\nynosec\n\n## z.test.sh\nznosec\n'; } \
    | sed -e 's/^ynosec$/y.test.sh | — | — | no section | —/' -e 's/^znosec$/z.test.sh | — | — | no section | —/' > "$out"
}
CS_ONE='x.test.sh | §ONE | keep | lib/x.sh: the first arm deleted | none (searched x in tests/)'
CS_TWO='x.test.sh | §TWO | prose pin | "the second" | carried by exit 1'

# ============================================================
section "CENSUS-COMPLETE-1: a section with no census line, a suite with no heading and a suite with no line are refused by name"
# ============================================================
# fails-when: a census missing a section's line, a suite's heading or a section-less suite's line passes.
CC1="$TMP/cc1"; census_scratch "$CC1"
expect_eq "the sweep reads the scratch tree: two sections of x, and nothing of the heredoc body in z" \
  "x.test.sh	section	ONE|x.test.sh	section	TWO" \
  "$(census_calls "$CC1/tests" | awk -F'\t' '$1 == "x.test.sh"' | paste -sd'|' -)"
expect_eq "…and z, whose only section call sits in a heredoc body, has no call at all" "0" \
  "$(census_calls "$CC1/tests" | awk -F'\t' '$1 == "z.test.sh"' | wc -l | tr -d ' ')"
census_file "$CC1/full.md" "$CS_ONE" "$CS_TWO"
expect_eq "control: a census with both lines and the section-less suites' lines is refused for nothing" "" \
  "$(census_refusals "$CC1/tests" "$CC1/full.md")"
census_file "$CC1/one.md" "$CS_ONE"
expect_eq "the census missing x's second section is refused naming the suite and the key" \
  "no verdict: x.test.sh §TWO" "$(census_refusals "$CC1/tests" "$CC1/one.md")"
census_file "$CC1/none.md"
expect_eq "…missing both, it names both" "no verdict: x.test.sh §ONE|no verdict: x.test.sh §TWO" \
  "$(census_refusals "$CC1/tests" "$CC1/none.md" | paste -sd'|' -)"
sed -e '/^## x.test.sh$/d' "$CC1/full.md" > "$CC1/nohead.md"
expect_eq "a suite with lines and no heading is refused naming the suite" "no heading: x.test.sh" \
  "$(census_refusals "$CC1/tests" "$CC1/nohead.md")"
sed -e '/^y.test.sh | /d' "$CC1/full.md" > "$CC1/noline.md"
expect_eq "a suite with no section and no \`no section\` line is refused naming the suite" "no line: y.test.sh" \
  "$(census_refusals "$CC1/tests" "$CC1/noline.md")"
{ cat "$CC1/full.md"; printf 'x.test.sh | — | — | no section | —\n'; } > "$CC1/wrongnosec.md"
expect_eq "a \`no section\` line beside a suite that has sections is refused" \
  "no section line on a suite with sections: x.test.sh" "$(census_refusals "$CC1/tests" "$CC1/wrongnosec.md")"

# ============================================================
section "CENSUS-COMPLETE-2: a verdict outside the five words, and a rule line marked as a cull, are refused"
# ============================================================
# fails-when: a record line with a word of its own for a verdict, or a rule: line that is not keep, passes.
CC2="$TMP/cc2"; census_scratch "$CC2"
census_file "$CC2/odd.md" "$CS_ONE" 'x.test.sh | §TWO | maybe | lib/x.sh: a line changed | none (searched x in tests/)'
expect_eq "a verdict that is not one of the five words is refused naming the suite, the key and the word" \
  "bad verdict: x.test.sh §TWO maybe" "$(census_refusals "$CC2/tests" "$CC2/odd.md")"
census_file "$CC2/rule.md" 'x.test.sh | §ONE | duplicate | rule: lint — a shape planted | x.test.sh §TWO' "$CS_TWO"
expect_eq "a rule: line whose verdict is duplicate is refused naming the suite, the key and the verdict" \
  "rule mark on a cull: x.test.sh §ONE duplicate" "$(census_refusals "$CC2/tests" "$CC2/rule.md")"
census_file "$CC2/rulekeep.md" 'x.test.sh | §ONE | keep | rule: lint — a shape planted | none (searched x in tests/)' "$CS_TWO"
expect_eq "control: the same rule: line as keep, and a two-word verdict, are refused for nothing" "" \
  "$(census_refusals "$CC2/tests" "$CC2/rulekeep.md")"

# ============================================================
section "CENSUS-COMPLETE-3: the census covers every suite and every section of the tests tree"
# ============================================================
# fails-when: a suite under tests/ has no heading, a section call has no record line under its key, a verdict is
# not one of the five words, or a rule: line is not keep.
CC3_CALLS="$(census_calls "$TESTS_DIR")"
expect_contains "the sweep reads the real tree: it finds this suite's own section" \
  "shell-lint.test.sh	section	CENSUS-COMPLETE-3" "$CC3_CALLS"
expect_eq "the census file is there, with a heading for this suite" "yes" \
  "$(/usr/bin/grep -q '^## shell-lint.test.sh$' "$CENSUS_MD" 2>/dev/null && echo yes)"
expect_eq "the real tests tree is covered by tests/CENSUS.md: no refusal" "" "$(census_refusals "$TESTS_DIR" "$CENSUS_MD")"


# ── the cut ──────────────────────────────────────────────────────────────────
# The census is also the cut: a section whose verdict is a cull is deleted from its suite, and a section the census
# keeps stays. A key's calls in its suite must number its keep lines, so a culled section still called and a kept
# one gone are both refused, by suite and key. `## Culled` lists the cull as `<suite> §<key> — <verdict>`, the
# verdict after the last ` — ` because a key may hold one. A line there whose verdict is keep, or whose key carries a
# `rule:` record (a door refusal, a lint or a check pin), culls what the rubric never lets go.
# census_cull_refusals <tests dir> <census file> -> one line per refusal, none when the tree is cut as the census says:
#   culled section present: a key with a cull line still called more often than it has keep lines
#   kept section absent: a key with more keep lines than calls in its suite
#   keep in the culled list: a `## Culled` line whose verdict is keep
#   rule pin culled: a `## Culled` line whose key has a record line with a `rule:` defect
census_cull_refusals() {
  {
    census_records "$2"
    sed -n '/^## Culled$/,$p' "$2" 2>/dev/null | LC_ALL=C awk '/^[A-Za-z0-9._-]+\.test\.sh §/ {
      sep = " — "; s = $0; sub(/ .*/, "", s); r = substr($0, length(s) + length(" §") + 1); v = r
      while ((i = index(v, sep)) > 0) v = substr(v, i + length(sep))
      printf "U\t%s\t%s\t%s\n", s, substr(r, 1, length(r) - length(v) - length(sep)), v }'
    census_calls "$1" | sed 's/^/C\t/'
  } | LC_ALL=C awk -F'\t' '
    $1 == "R" { if ($3 == "—") next; key = $2 SUBSEP $3; seen[key] = 1
                if ($4 == "keep") nkeep[key]++; else ncull[key]++
                if ($5 ~ /^rule: /) rule[key] = 1 }
    $1 == "U" { key = $2 SUBSEP $3
                if ($4 == "keep") print "keep in the culled list: " $2 " §" $3
                U[key] = 1 }
    $1 == "C" { called[$2 SUBSEP $4]++ }
    END {
      for (key in U) if (key in rule) { split(key, p, SUBSEP); print "rule pin culled: " p[1] " §" p[2] }
      for (key in seen) {
        split(key, p, SUBSEP)
        if (ncull[key] > 0 && called[key] > nkeep[key]) print "culled section present: " p[1] " §" p[2]
        if (nkeep[key] > called[key]) print "kept section absent: " p[1] " §" p[2]
      }
    }' | LC_ALL=C sort
}
CS_THREE='x.test.sh | §THREE | duplicate | lib/x.sh: the third arm deleted | x.test.sh §ONE'

# ============================================================
section "CENSUS-1: a section the census culls that is still in its suite is refused by suite and key"
# ============================================================
# fails-when: a suite still calls a section whose only census line is a cull, and the sweep passes.
CN1="$TMP/cn1"; census_scratch "$CN1"
printf '%s\n' 'section "THREE: the third"' 'expect_eq c 1 1' >> "$CN1/tests/x.test.sh"
census_file "$CN1/cut.md" "$CS_ONE" "$CS_TWO" "$CS_THREE"
printf '\n## Culled\n\nx.test.sh §TWO — prose pin\nx.test.sh §THREE — duplicate\n' >> "$CN1/cut.md"
expect_eq "the sweep reads the scratch tree: three sections of x" "ONE|TWO|THREE" \
  "$(census_calls "$CN1/tests" | awk -F'\t' '$1 == "x.test.sh" { print $3 }' | paste -sd'|' -)"
expect_eq "both culled sections still called are refused, each by suite and key" \
  "culled section present: x.test.sh §THREE|culled section present: x.test.sh §TWO" \
  "$(census_cull_refusals "$CN1/tests" "$CN1/cut.md" | paste -sd'|' -)"
sed -e '/^section "THREE/,$d' "$CN1/tests/x.test.sh" > "$CN1/x.one" && mv "$CN1/x.one" "$CN1/tests/x.test.sh"
expect_eq "…with the third cut, the second alone is refused" "culled section present: x.test.sh §TWO" \
  "$(census_cull_refusals "$CN1/tests" "$CN1/cut.md")"
printf '%s\n' 'section "ONE: the first"' 'expect_eq a 1 1' > "$CN1/tests/x.test.sh"
expect_eq "control: with both culled sections cut and the kept one called, nothing is refused" "" \
  "$(census_cull_refusals "$CN1/tests" "$CN1/cut.md")"
printf '%s\n' 'section "ONE: the first"' 'section "TWO: twice"' 'section "TWO: again"' > "$CN1/tests/x.test.sh"
census_file "$CN1/twice.md" "$CS_ONE" 'x.test.sh | §TWO: twice | vacuous | the branch is never taken | none (searched x in tests/)' \
  'x.test.sh | §TWO: again | keep | lib/x.sh: the second arm deleted | none (searched x in tests/)'
printf '\n## Culled\n\nx.test.sh §TWO: twice — vacuous\n' >> "$CN1/twice.md"
expect_eq "a shared key is read by whole title, and the culled one of the two is refused alone" \
  "culled section present: x.test.sh §TWO: twice" "$(census_cull_refusals "$CN1/tests" "$CN1/twice.md")"

# ============================================================
section "CENSUS-2: a section the census keeps that is gone from its suite is refused by suite and key"
# ============================================================
# fails-when: a section whose census line is a keep is deleted from its suite, and the sweep passes.
CN2="$TMP/cn2"; census_scratch "$CN2"
census_file "$CN2/keep.md" "$CS_ONE" "$CS_TWO"
printf '\n## Culled\n\nx.test.sh §TWO — prose pin\n' >> "$CN2/keep.md"
printf '%s\n' 'section "ONE: the first"' 'expect_eq a 1 1' > "$CN2/tests/x.test.sh"
expect_eq "control: the kept section called and the culled one cut are refused for nothing" "" \
  "$(census_cull_refusals "$CN2/tests" "$CN2/keep.md")"
printf '%s\n' 'echo the first section went' > "$CN2/tests/x.test.sh"
expect_eq "the kept section deleted is refused naming the suite and the key" "kept section absent: x.test.sh §ONE" \
  "$(census_cull_refusals "$CN2/tests" "$CN2/keep.md")"
rm -f "$CN2/tests/x.test.sh"
expect_eq "…and so is a kept section whose whole suite is gone" "kept section absent: x.test.sh §ONE" \
  "$(census_cull_refusals "$CN2/tests" "$CN2/keep.md")"

# ============================================================
section "CENSUS-3: a culled-list line that culls a keep or a rule pin is refused"
# ============================================================
# fails-when: `## Culled` names a section whose verdict is keep, or whose record carries a door refusal, lint or
# check pin, and the sweep passes.
CN3="$TMP/cn3"; census_scratch "$CN3"
printf '%s\n' 'section "ONE: the first"' 'expect_eq a 1 1' > "$CN3/tests/x.test.sh"
CS_RULE='x.test.sh | §ONE | keep | rule: lint — a shape planted | none (searched x in tests/)'
census_file "$CN3/ok.md" "$CS_RULE" "$CS_TWO"
printf '\n## Culled\n\nx.test.sh §TWO — prose pin\n' >> "$CN3/ok.md"
expect_eq "control: a rule: keep left out of the culled list is refused for nothing" "" \
  "$(census_cull_refusals "$CN3/tests" "$CN3/ok.md")"
{ cat "$CN3/ok.md"; printf 'x.test.sh §ONE — duplicate\n'; } > "$CN3/rule.md"
expect_contains "a culled-list line for the rule: record is refused naming the suite and the key" \
  "rule pin culled: x.test.sh §ONE" "$(census_cull_refusals "$CN3/tests" "$CN3/rule.md")"
{ cat "$CN3/ok.md"; printf 'x.test.sh §ONE — keep\n'; } > "$CN3/keep.md"
expect_contains "a culled-list line whose verdict is keep is refused naming the suite and the key" \
  "keep in the culled list: x.test.sh §ONE" "$(census_cull_refusals "$CN3/tests" "$CN3/keep.md")"

# ============================================================
section "CENSUS-4: the tests tree is cut as tests/CENSUS.md says"
# ============================================================
# fails-when: a suite under tests/ still calls a section the census culls, a kept section is gone, or the culled
# list holds a keep or a rule pin.
CN4_CULLED="$(sed -n '/^## Culled$/,$p' "$CENSUS_MD" 2>/dev/null | /usr/bin/grep -c '\.test\.sh §')"
expect_true "the census carries a culled list to read (${CN4_CULLED} lines)" [ "${CN4_CULLED:-0}" -gt 0 ]
expect_eq "the real tests tree: no culled section called, no kept section gone, no keep or rule pin culled" "" \
  "$(census_cull_refusals "$TESTS_DIR" "$CENSUS_MD")"

finish
