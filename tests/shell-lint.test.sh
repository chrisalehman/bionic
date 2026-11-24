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
# §ADR and §HEADER hold a document to the fact it restates. An ADR says its state twice, in its front
# matter's `status:` and under its `## Status` heading, and the first word of each must be the same word
# (`Accepted`, `Proposed`, `Superseded`); every ADR under docs/adrs/, and under .bionic/docs/adrs/ where
# that directory exists, is read, and a disagreement is refused naming the file and both words. A suite
# header lists the sections it holds as `#   §KEY` lines, and the keys must be exactly the keys of the
# body's `section` calls; a suite is refused naming the key it lists that the body lacks and the key the
# body has that it omits. A `§` inside a sentence is a reference and a header with no list makes no claim,
# but this suite's own list is pinned to its body, so a sweep named here that the body never runs is refused.
#
# THE SECTIONS, in the order the body runs them:
#
#   §LEXER               the lexer reads every shipped file to its end with every frame closed.
#   §PARSE               every shell file in the tree parses under the system interpreter.
#   §LOAD                every library loads in a bare /bin/bash with its functions defined.
#   §CASE                no `case` arm without its opening paren inside `$( … )`.
#   §HEREDOC             the two heredoc shapes: a paren-less arm in an unquoted body, a lone `)` in a body.
#   §BP                  no writer is piped into a reader that quits early where the status is read.
#   §BP-PIN              a writer of more than 64 KB into the fixed form returns 0 under pipefail.
#   §EXIT                every refusal names its exit, and those that do not burn down from a ceiling per file.
#   §CENSUS-COMPLETE-1   a section with no census line, a suite with no heading and a suite with no line are refused.
#   §CENSUS-COMPLETE-2   a verdict outside the five words, and a rule line marked as a cull, are refused.
#   §CENSUS-COMPLETE-3   the census covers every suite and every section of the real tests tree.
#   §CENSUS-ROWS         a row id the census cites that its suite does not hold is refused naming the suite, the section and the id.
#   §CENSUS-1            a section the census culls that is still in its suite is refused.
#   §CENSUS-2            a kept section gone from its suite, or a baseline one gone with no culled line, is refused.
#   §CENSUS-3            a culled-list line that culls a keep or a rule pin is refused.
#   §CENSUS-4            the real tests tree is cut as tests/CENSUS.md says.
#   §CENSUS-GONE         a cull gone with its code needs a listed name; a culled duplicate's catchers are shown and stand.
#   §ADR                 an ADR whose `status:` word differs from its `## Status` word is refused by file.
#   §HEADER              a suite header that lists a section its body lacks, or omits one its body has, is refused.
#   §INTEGRATION-REF     no product line merges into the integration branch or moves its ref; a fetch fills a
#                        remote-tracking ref alone.
#   §LINT                tests/lib/lint.sh, the landing's run of §EXIT's, §BP's and §HEADER's programs over the files a
#                        row changed, names each hit there by file and line, and a lowered ceiling at its own line.
#   §SETUP               a shared setup that loads a helper on a line with no stop is refused by file and line.
#   §STOP                a maker that fails stops the suite that asked, its processes and nothing beside it, with one
#                        line; a setup or a tests/lib file that calls maker_stop with no load of it is refused by line.
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
#
# pins: tests/CENSUS.md tests/*.test.sh

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
# The programs of §EXIT, §BP and §HEADER, and the census's section reader, are tests/lib/lint.sh's: the landing line
# runs that file over the files a row changed, and these sections prove the same programs over the whole tree.
LINT_TMP="$TMP"
# shellcheck source=/dev/null
. "$TESTS_DIR/lib/lint.sh" || { echo "shell-lint.test.sh: tests/lib/lint.sh does not load"; exit 1; }

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
QUIT_ALLOW="$TESTS_DIR/lib/quitting-readers.allow"
# quit_sites <sweep output> -> the sorted path:line of each site
quit_sites() { printf '%s\n' "$1" | LC_ALL=C awk -F'\t' '$1 == "Q" { print $2 }' | LC_ALL=C sort; }

BP_ROSTER="$(quit_roster "$REPO")"
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

# ============================================================
section "EXIT — every refusal names its exit, and the ones that do not burn down from a ceiling per file"
# ============================================================
#
# fails-when: a hook or payload script gains a refusal that names neither a verb nor a person and the file's
# count rises past its line in tests/lib/refusal-exits.ceiling; a file's count falls and its ceiling line is
# not lowered to match; or one of the three walls named below loses the exit it names.
#
# WHY IT EXISTS. A refusal whose only way out is a person's word stops the run on them, and one that says what
# is wrong without saying what to run costs a guess per retry. Rewriting every old text at once is days of
# work, most of it on refusals that never fire, so the old ones are counted, per file, and the count only
# falls: a new refusal ships with its exit, and a file whose count drops writes its new number.
#
# THE ROSTER: every *.sh under hooks/ and payload/scripts/.
#
# WHAT IS A SITE. A `die "`, `block "` or `refuse ` call whose logical line (continuation lines and an open
# double-quoted string joined) carries `REFUSED`, `refused —` or `refused --`. Whole-line comments and heredoc
# bodies are not read, and a usage line (`die "  bash …"`, `die "Usage…"`) is not a site.
# WHAT EXCUSES ONE:
#   a refuse call   by its shape: its fix argument is the exit, and lib/refuse.sh refuses an empty one
#   a die or block  its text, or the next non-blank line when that line calls pv_next (which prints the
#                   call as `next call:`), names an exit: `session-poker.sh <verb>`, `card.sh <verb>`,
#                   `spawn-worktree.sh`, `close-out.sh`, `Fix:`, `next call:`, `run again:`, `needs: `,
#                   `set fix-cap`, `decisions rule`, a hyphenated verb of EXIT_VERBS as a whole word, or a
#                   one-word verb of EXIT_WORDS followed by its argument (`<`, `'`, `$`, a backquote, a
#                   digit or a flag). The refusing verb's own name in `<verb> refused —` or in a
#                   `REFUSED — <verb>:` lead is the refusal's subject, not its exit, and is not read.
# EXIT_VERBS: finding-move known-limits-part landing-report proof-add regression-run release-approval
#   release-check release-note reviews-part ruling-ack stop-run task-add
# EXIT_WORDS: adopt amend approve bind extend reply ready resume waive
# Each is a verb the poker dispatches, but `ready`, spawn-worktree.sh's.
# Every other site is UNEXCUSED and counted against its file's ceiling.
#
# THE CEILING FILE, tests/lib/refusal-exits.ceiling: `<path> <count> # <reason or date>`, one line per file
# with unexcused sites. A file it does not name has ceiling 0. A line with no count, no reason after a space,
# a hash and a space, or a path named twice is refused by line.
EXIT_CEIL="$TESTS_DIR/lib/refusal-exits.ceiling"

# exit_sites <sweep rows> -> the sorted path:line of each unexcused site
exit_sites() { printf '%s\n' "$1" | LC_ALL=C awk -F'\t' '$1 == "X" { print $2 }' | LC_ALL=C sort; }
# exit_count <sweep rows> <path> -> how many unexcused sites the file holds
exit_count() { printf '%s\n' "$1" | LC_ALL=C awk -F'\t' -v p="$2" '$1 == "X" && index($2, p ":") == 1 { n++ } END { print n + 0 }'; }

EXIT_ROSTER="$(exit_roster "$REPO")"
expect_eq "the sweep found shell files to read, under hooks/poker and payload/scripts/lib" "yes" \
  "$(LC_ALL=C grep -q '^hooks/poker/' <<< "$EXIT_ROSTER" && LC_ALL=C grep -q '^payload/scripts/lib/' <<< "$EXIT_ROSTER" && echo yes || echo no)"
# shellcheck disable=SC2086  # one path per line, none with blanks
EXIT_REAL="$(exit_sweep "$REPO" $EXIT_ROSTER)"
expect_eq "…and found refusals in them, both excused and not, so it read their text" "yes yes" \
  "$(printf '%s\n' "$EXIT_REAL" | LC_ALL=C awk -F'\t' '$1 == "E" { e = 1 } $1 == "X" { x = 1 } END { print (e ? "yes" : "no"), (x ? "yes" : "no") }')"
expect_eq "the ceiling file exists" "yes" "$([ -f "$EXIT_CEIL" ] && echo yes || echo no)"

# EXIT-1: the real tree against its ceiling. No file is above it, none below, and no line of it is refused.
expect_eq "EXIT-1 every rostered file's unexcused refusals are at its ceiling: none above, none below" "" \
  "$(exit_judge "$EXIT_REAL" "$EXIT_CEIL")"
EXIT_NONE="$(exit_judge "$EXIT_REAL" /dev/null)"
expect_contains "…and against an empty ceiling the same sweep names a file over and its site, so the ceiling is what holds it" \
  "S	hooks/poker/plan.sh:" "$EXIT_NONE"
EXIT_PCOUNT="$(exit_count "$EXIT_REAL" hooks/poker/plan.sh)"
expect_contains "…naming its count over ceiling 0" "O	hooks/poker/plan.sh	$EXIT_PCOUNT over ceiling 0" "$EXIT_NONE"
LC_ALL=C awk '$1 == "hooks/poker/plan.sh" { $2 = $2 + 1 } { print }' "$EXIT_CEIL" > "$TMP/exit-raised.ceiling"
expect_eq "…and a ceiling raised by one for a file is refused, naming the number to write" \
  "L	lower tests/lib/refusal-exits.ceiling: hooks/poker/plan.sh $EXIT_PCOUNT" \
  "$(exit_judge "$EXIT_REAL" "$TMP/exit-raised.ceiling")"

# EXIT-2: planted sites, read by the same instrument in the same call as their controls.
EX2="$TMP/exit2"
mkdir -p "$EX2/hooks" "$EX2/payload/scripts/lib"
cat > "$EX2/hooks/plant.sh" <<'EOF'
#!/bin/bash
die "REFUSED — x"  # MARK-N1 no exit
die "task-add refused — the cap is full; the plan is unchanged."  # MARK-N2 the verb's own name is no exit
block "REFUSED — the fact" "fix" "the detail"  # MARK-N3 a block has no fix by shape
die "REFUSED — a text
  that runs on to a second line with no exit"  # MARK-N4 named at its first line
die "REFUSED — y; the plan is unchanged."  # MARK-C1 its next line prints the call
pv_next task-add T1 'a title'
die "REFUSED — z; needs: Chris — why"  # MARK-C2 a person's exit
refuse exit2 commit "REFUSED — w" "fix it" "the detail"  # MARK-C3 a refuse call's fix is the exit
die "REFUSED — run it as: session-poker.sh plant-verb AC-1 status=discharged"  # MARK-C4 a script verb
die "REFUSED — a text that runs on
  to its exit: release-note writes it."  # MARK-C5 the exit on the joined line
# die "REFUSED — in a comment"  MARK-C6
cat <<'DOC'
die "REFUSED — heredoc text"  MARK-C7
DOC
die "  bash x.sh REFUSED usage"  # MARK-C8 a usage line
die "REFUSED — the reply is the user's: reply <n> waive"  # MARK-C9 a one-word verb with its argument
die "REFUSED — the reply's item is not a number"  # MARK-N5 the same word as a noun is no exit
EOF
printf '%s\n' '#!/bin/bash' 'die "REFUSED — nothing to run"  # MARK-L1' > "$EX2/payload/scripts/lib/plant-lib.sh"
EX2_ROSTER="hooks/plant.sh
payload/scripts/lib/plant-lib.sh"
# shellcheck disable=SC2086
EX2_OUT="$(exit_sweep "$EX2" $EX2_ROSTER)"
ex2_at() { printf '%s:%s\n' "$1" "$(mark_line "$EX2/$1" "$2")"; }
expect_eq "EXIT-2 the sites named are the planted ones with no exit and no others, so every control in the same call passes" \
  "$(printf '%s\n' "$(ex2_at hooks/plant.sh MARK-N1)" "$(ex2_at hooks/plant.sh MARK-N2)" "$(ex2_at hooks/plant.sh MARK-N3)" \
       "hooks/plant.sh:$(( $(mark_line "$EX2/hooks/plant.sh" MARK-N4) - 1 ))" "$(ex2_at hooks/plant.sh MARK-N5)" \
       "$(ex2_at payload/scripts/lib/plant-lib.sh MARK-L1)" | LC_ALL=C sort)" \
  "$(exit_sites "$EX2_OUT")"
expect_eq "…the controls with an exit are read as sites that name one: the pv_next line, needs:, the refuse call, the script verb, the joined line, the verb word" \
  "$(printf '%s\n' "$(ex2_at hooks/plant.sh MARK-C1)" "$(ex2_at hooks/plant.sh MARK-C2)" "$(ex2_at hooks/plant.sh MARK-C3)" \
       "$(ex2_at hooks/plant.sh MARK-C4)" "hooks/plant.sh:$(( $(mark_line "$EX2/hooks/plant.sh" MARK-C5) - 1 ))" \
       "$(ex2_at hooks/plant.sh MARK-C9)" | LC_ALL=C sort)" \
  "$(printf '%s\n' "$EX2_OUT" | LC_ALL=C awk -F'\t' '$1 == "E" { print $2 }' | LC_ALL=C sort)"
expect_contains "…a site is named with its text" "$(ex2_at hooks/plant.sh MARK-N1)	die \"REFUSED — x\"" "$EX2_OUT"
printf '%s\n' '# a comment' '' 'hooks/plant.sh 5 # the planted ones' 'payload/scripts/lib/plant-lib.sh 1 # 2026-10-25' > "$EX2/at.ceiling"
expect_eq "…at the ceiling the judge prints nothing" "" "$(exit_judge "$EX2_OUT" "$EX2/at.ceiling")"
printf '%s\n' 'hooks/plant.sh 4 # one fewer' 'payload/scripts/lib/plant-lib.sh 1 # 2026-10-25' > "$EX2/under.ceiling"
expect_contains "…one site over the ceiling names the file, its count and the ceiling" "O	hooks/plant.sh	5 over ceiling 4" \
  "$(exit_judge "$EX2_OUT" "$EX2/under.ceiling")"
expect_contains "…and each of its sites by path, line and text" "S	$(ex2_at hooks/plant.sh MARK-N2)	die \"task-add refused" \
  "$(exit_judge "$EX2_OUT" "$EX2/under.ceiling")"
printf '%s\n' 'hooks/plant.sh 6 # one more' 'payload/scripts/lib/plant-lib.sh 1 # 2026-10-25' 'hooks/gone.sh 2 # a file since deleted' > "$EX2/over.ceiling"
expect_eq "…a ceiling above the count names each file to lower and the number to write, a file with none at 0" \
  "L	lower tests/lib/refusal-exits.ceiling: hooks/gone.sh 0
L	lower tests/lib/refusal-exits.ceiling: hooks/plant.sh 5" "$(exit_judge "$EX2_OUT" "$EX2/over.ceiling")"
expect_contains "…a file the ceiling does not name has ceiling 0" "O	payload/scripts/lib/plant-lib.sh	1 over ceiling 0" \
  "$(exit_judge "$EX2_OUT" /dev/null)"
printf '%s\n' 'hooks/plant.sh 5' 'hooks/plant.sh many # a reason' 'hooks/plant.sh 5 # once' 'hooks/plant.sh 5 # twice' \
  'payload/scripts/lib/plant-lib.sh 1 # 2026-10-25' > "$EX2/bad.ceiling"
expect_eq "…a ceiling line with no reason, no count, or a path named twice is refused by line, and the rest still judged" \
  "F	1	no reason after a space, a hash and a space
F	2	not <path> <count>
F	4	hooks/plant.sh is named twice" "$(exit_judge "$EX2_OUT" "$EX2/bad.ceiling")"

# EXIT-3: the three walls that stopped a run on its person's word each name their exit, and none is in the sweep.
EXIT_CAP_LN="$(LC_ALL=C grep -nF 'die "task-add refused — review-born rows:' "$REPO/hooks/poker/plan.sh" | head -1 | cut -d: -f1)"
expect_eq "EXIT-3a the cap refusal in hooks/poker/plan.sh is found, and names the cap's own exit" "yes" \
  "$([ -n "$EXIT_CAP_LN" ] && sed -n "${EXIT_CAP_LN}p" "$REPO/hooks/poker/plan.sh" | LC_ALL=C grep -qF 'set fix-cap=' && echo yes || echo no)"
expect_absent "…and the sweep does not count it" "hooks/poker/plan.sh:${EXIT_CAP_LN:-none}	" "$EXIT_REAL"
expect_contains "…while the same line read with its exit cut out is named" "hooks/poker/plan.sh:1" \
  "$(mkdir -p "$TMP/exit3/hooks/poker"; sed -n "${EXIT_CAP_LN:-1}p" "$REPO/hooks/poker/plan.sh" | sed 's/set fix-cap=[^ ]*//' > "$TMP/exit3/hooks/poker/plan.sh"
     exit_sites "$(exit_sweep "$TMP/exit3" hooks/poker/plan.sh)")"
EXIT_WALLS="$REPO/payload/scripts/lib/walls.sh"
EXIT_LIVE="$(LC_ALL=C awk '/^matrix_live_row_exit\(\)/ { on = 1 } on { print } on && /^}/ { exit }' "$EXIT_WALLS")"
expect_contains "EXIT-3b the Verify gate's live-row exit in payload/scripts/lib/walls.sh names the walk's registration for a row the walk proved" \
  'session-poker.sh proof-add walk <its record>' "$EXIT_LIVE"
expect_contains "…the person's change of the Eval design row for a row whose eval cannot fire" 'its ## Eval design row changed' "$EXIT_LIVE"
expect_contains "…and the user's waiver otherwise" 'needs: the user — a waiver' "$EXIT_LIVE"
expect_eq "…and the live row's three evidence refusals each carry it" "3" \
  "$(LC_ALL=C grep -cF '"${live_exit:-' "$EXIT_WALLS")"
# The release card's row decision is the reply surface for a waiver, so its exit is named by the wall that sends
# the run there: both auditor refusals' detail, three lines from the call, names the user and the card's reply.
EXIT_AUD="$(LC_ALL=C awk -v want='needs: the user — a waiver at the release card: reply <n> waive' '
  index($0, "block_matrix \"the auditor has not confirmed ${ac}\"") { n++; at[n] = NR }
  { L[NR] = $0 }
  END { for (i = 1; i <= n; i++) { f = 0; for (k = at[i]; k <= at[i] + 2; k++) if (index(L[k], want)) f = 1; h += f }
        print n + 0, h + 0 }' "$EXIT_WALLS")"
expect_eq "EXIT-3c the gate's two auditor refusals the release card settles each name the user's waiver and the card's reply" \
  "2 2" "$EXIT_AUD"

# ── the census ───────────────────────────────────────────────────────────────
# The census file holds one record line per section of every suite under tests/, under a heading per suite, in the
# shape tests/RUBRIC.md §4 sets; this sweep refuses a tree it does not cover. A `section` call is found by the rubric's
# own section-list command, extracted from the rubric and run here. A call inside a heredoc body is fixture text.
census_registry() { sed -n 's/^REGISTRY_FILES="\([^" ]*\).*$/\1/p' "$1" | head -1; }   # <units.sh> -> the first registry file
CENSUS_MD="$REPO/$(census_registry "$REPO/payload/scripts/lib/units.sh")"
CENSUS_RUBRIC="$TESTS_DIR/RUBRIC.md"
census_prog "$CENSUS_RUBRIC"
# census_records <census file> -> `R TAB <suite> TAB <key> TAB <verdict> TAB <defect> TAB <catcher> TAB <line>` per record line.
census_records() {
  awk -F' [|] ' '/^[A-Za-z0-9._-]+\.test\.sh [|] / { k = $2; sub(/^§/, "", k); printf "R\t%s\t%s\t%s\t%s\t%s\t%s\n", $1, k, $3, $4, $5, $0 }' "$1" 2>/dev/null
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
# census_row_refusals <tests dir> <census file> -> `unheld row: <suite> §<key> <id>` per labelled row id a record
# line cites in its defect cell, inside a parenthesis, that its suite does not hold. A labelled id is NAME-n, an
# upper-case stem of two letters or more, a hyphen, then a digit (`RV-3`, `AW-5-0`); the plain `7a` of a suite that
# numbers its rows by position has nothing to be held against, and `AC-n` names a criterion, not a row. A suite holds
# an id as a whole token in its own file or in a tests/lib file its text names.
census_row_refusals() {
  local s f lib libs pairs="$(mktemp "${TMPDIR:-/tmp}/cr.XXXXXX")"
  census_records "$2" | awk -F'\t' '{
    t = $5
    while (match(t, /\([^()]*\)/)) {
      g = substr(t, RSTART + 1, RLENGTH - 2); t = substr(t, RSTART + RLENGTH)
      n = split(g, a, ", ")
      for (i = 1; i <= n; i++)
        if (a[i] ~ /^[A-Z][A-Z]+-[0-9][A-Za-z0-9]*(-[0-9A-Za-z]+)*$/ && a[i] !~ /^AC-/) print $2 "\t" $3 "\t" a[i]
    }
  }' | LC_ALL=C sort -u > "$pairs"
  for s in $(cut -f1 "$pairs" | LC_ALL=C sort -u); do
    f="$1/$s"; [ -f "$f" ] || continue
    libs=("$f")
    for lib in "$1"/lib/*.sh; do [ -f "$lib" ] && /usr/bin/grep -q -F "${lib##*/}" "$f" && libs+=("$lib"); done
    # the suite's tokens, a token being a run of letters, digits and hyphens; an id is held when it is one of them
    awk -F'\t' -v s="$s" '$1 == s { print $3 "\t" $2 }' "$pairs" | LC_ALL=C sort > "$pairs.s"
    /usr/bin/grep -h -o -E '[A-Za-z0-9-]+' "${libs[@]}" | LC_ALL=C sort -u > "$pairs.t"
    LC_ALL=C join -t "$(printf '\t')" -v 1 "$pairs.s" "$pairs.t" | awk -F'\t' -v s="$s" '{ printf "unheld row: %s §%s %s\n", s, $2, $1 }'
  done | LC_ALL=C sort -u
  rm -f "$pairs" "$pairs.s" "$pairs.t"
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
expect_eq "the census path comes from the registry constant: the product's names tests/CENSUS.md, a scratch copy's another file" \
  "$TESTS_DIR/CENSUS.md|tests/OTHER.md" "$CENSUS_MD|$(census_registry <(echo 'REGISTRY_FILES="tests/OTHER.md"'))"
expect_eq "the real tests tree is covered by tests/CENSUS.md: no refusal" "" "$(census_refusals "$TESTS_DIR" "$CENSUS_MD")"

# ============================================================
section "CENSUS-ROWS: a row id the census cites that its suite does not hold is refused by suite, section and id"
# ============================================================
# fails-when: a record line cites a labelled row (NAME-n) that neither its suite nor a tests/lib file the suite names
# holds, and the sweep over the real census prints nothing for it.
CR="$TMP/cr"; census_scratch "$CR"
printf '%s\n' 'expect_eq "RV-1: the first row" 1 1' 'expect_eq "RV-1b: its second" 1 1' > "$CR/tests/x.test.sh.rows"
cat "$CR/tests/x.test.sh.rows" >> "$CR/tests/x.test.sh"; rm -f "$CR/tests/x.test.sh.rows"
mkdir -p "$CR/tests/lib"; printf '%s\n' 'expect_eq "LB-2: a row a library holds" 1 1' > "$CR/tests/lib/rows.sh"
printf '%s\n' '. "$TESTS_DIR/lib/rows.sh"' >> "$CR/tests/x.test.sh"
census_file "$CR/held.md" 'x.test.sh | §ONE | keep | lib/x.sh: an arm deleted (RV-1, RV-1b, LB-2, AC-9, 7a) | none (searched x in tests/)' "$CS_TWO"
expect_eq "control: ids the suite holds, one in a library it names, a criterion id and a positional id are refused for nothing" "" \
  "$(census_row_refusals "$CR/tests" "$CR/held.md")"
census_file "$CR/lack.md" 'x.test.sh | §ONE | keep | lib/x.sh: an arm deleted (RV-1, RV-3, RV-3b, RV-1bb) | none (searched x in tests/)' "$CS_TWO"
expect_eq "a cited id the suite lacks is refused by suite, section and id; a longer id does not stand in for a shorter one" \
  "unheld row: x.test.sh §ONE RV-1bb|unheld row: x.test.sh §ONE RV-3|unheld row: x.test.sh §ONE RV-3b" \
  "$(census_row_refusals "$CR/tests" "$CR/lack.md" | paste -sd'|' -)"
census_file "$CR/other.md" 'x.test.sh | §ONE | keep | lib/x.sh: an arm deleted | none (searched x in tests/; y.test.sh §Q (RV-9))' "$CS_TWO"
expect_eq "an id cited only in the catcher cell names another suite's row and is not read" "" \
  "$(census_row_refusals "$CR/tests" "$CR/other.md")"
CR_REAL="$(census_row_refusals "$TESTS_DIR" "$CENSUS_MD")"
expect_eq "the real census cites only rows its suites hold" "" "$CR_REAL"


# ── the cut ──────────────────────────────────────────────────────────────────
# The census is also the cut: a section whose verdict is a cull is deleted from its suite, a section it keeps stays, and
# a key's calls in its suite must number its keep lines, so a culled section still called and a kept one gone are both
# refused. `## Culled` lists the cull as `<suite> §<key> — <verdict>`, the verdict after the last ` — `. A line there
# whose verdict is keep, or whose key carries a `rule:` record, culls what the rubric never lets go.
# census_cull_refusals <tests dir> <census file> -> one line per refusal, none when the tree is cut as the census says:
#   culled section present: a key with a cull line still called more often than it has keep lines
#   kept section absent: a key with more keep lines than calls in its suite
#   keep in the culled list: a `## Culled` line whose verdict is keep
#   rule pin culled: a `## Culled` line whose key has a record line with a `rule:` defect, unless it is gone with its code
#   gone with an unlisted name: a `— gone with <name>` line whose name is not on the deletion list
#   unverified catcher culled: a culled duplicate whose record line marks a catcher `(unverified)` or `(unverified; …)`
#   culled catcher named: a culled duplicate naming a catcher that is on the culled list itself
#   catcher stands in no suite: a culled duplicate naming a catcher no suite calls; a catcher is `<suite> §<key>`, read
#     up to the next `<suite> §`, and a trailing ` (…)` note is dropped until the rest is a key
#   gone with no culled line: a key of the baseline census (the optional third file) with a ` §` part neither called
#     in its suite nor on its suite's culled list, unless its suite stands and the whole key is called in a suite the
#     baseline lacks (a split)
# A section `gone with <name>` is a cull whose reason is that the code it pinned was deleted, so its record line, a keep
# or a rule: keep, stands without the section being called. The optional fourth file is the deletion list.
deletion_names() { /usr/bin/grep -o '`[a-z_.-]*`' "$1" 2>/dev/null | tr -d '`'; }
census_cull_refusals() {
  {
    sed 's/^/B\t/' "${3:-/dev/null}"
    deletion_names "${4:-/dev/null}" | sed 's/^/L\t/'
    census_records "$2"
    sed -n '/^## Culled$/,$p' "$2" 2>/dev/null | LC_ALL=C awk '/^[A-Za-z0-9._-]+\.test\.sh §/ {
      sep = " — "; s = $0; sub(/ .*/, "", s); r = substr($0, length(s) + length(" §") + 1); v = r
      while ((i = index(v, sep)) > 0) v = substr(v, i + length(sep))
      printf "U\t%s\t%s\t%s\n", s, substr(r, 1, length(r) - length(v) - length(sep)), v }'
    census_calls "$1" | sed 's/^/C\t/'
  } | LC_ALL=C awk -F'\t' '
    $1 == "R" { if ($3 == "—") next; key = $2 SUBSEP $3; seen[key] = 1
                if ($4 == "keep") nkeep[key]++; else ncull[key]++
                if ($5 ~ /^rule: /) rule[key] = 1
                if ($4 == "duplicate") { names[key] = names[key] "\n" $6; if ($6 ~ /[(]unverified[);]/) unv[key] = 1 } }
    $1 == "B" { if (sub(/^## /, "", $2)) bsuite[$2] = 1
                else if (split($2, f, " [|] ") > 2 && sub(/^§/, "", f[2])) was[f[1] SUBSEP f[2]] = 1 }
    $1 == "L" { listed[$2] = 1 }
    $1 == "U" { key = $2 SUBSEP $3; nm = $4; n = split($3, t, " §"); for (i = 1; i <= n; i++) part[$2 SUBSEP t[i]] = 1
                if ($4 == "keep") print "keep in the culled list: " $2 " §" $3
                if (sub(/^gone with /, "", nm)) { gone[key] = 1; if (!(nm in listed)) print "gone with an unlisted name: " nm }
                if ($4 == "duplicate") dup[key] = 1
                U[key] = 1 }
    $1 == "C" { called[$2 SUBSEP $4]++; stands[$2] = 1; if (!($2 in bsuite)) born[$4] = 1
                n = split($4, t, " §"); for (i = 1; i <= n; i++) part[$2 SUBSEP t[i]] = 1 }
    function standing(r,   s, c, i, j) {
      s = r; sub(/ §.*/, "", s); c = substr(r, length(s) + length(" §") + 1)
      while (1) {
        if ((s SUBSEP c) in U) return "culled"
        if ((s SUBSEP c) in called) return ""
        for (i = 0; (j = index(substr(c, i + 1), " (")) > 0; ) i += j
        if (i == 0) return "absent"
        c = substr(c, 1, i - 1)
      }
    }
    END {
      for (key in dup) { split(key, p, SUBSEP); if (key in unv) print "unverified catcher culled: " p[1] " §" p[2]
        m = split(names[key], f, "\n")
        for (j = 2; j <= m; j++) { gsub(/[A-Za-z0-9._-]+\.test\.sh §/, "\001&", f[j]); n = split(f[j], ref, "\001")
          for (i = 2; i <= n; i++) { sub(/[, ]+$/, "", ref[i]); w = standing(ref[i])
            if (w == "culled") print "culled catcher named: " p[1] " §" p[2] " names " ref[i]
            if (w == "absent") print "catcher stands in no suite: " p[1] " §" p[2] " names " ref[i] } } }
      for (key in was) { split(key, p, SUBSEP); if ((p[1] in stands) && (p[2] in born)) continue
        n = split(p[2], t, " §"); for (i = 1; i <= n; i++) if (!((p[1] SUBSEP t[i]) in part)) { print "gone with no culled line: " p[1] " §" p[2]; break } }
      for (key in U) if ((key in rule) && !(key in gone)) { split(key, p, SUBSEP); print "rule pin culled: " p[1] " §" p[2] }
      for (key in seen) {
        split(key, p, SUBSEP)
        if (ncull[key] > 0 && called[key] > nkeep[key]) print "culled section present: " p[1] " §" p[2]
        if (nkeep[key] > called[key] && !(key in gone)) print "kept section absent: " p[1] " §" p[2]
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
# fails-when: a section whose census line is a keep is deleted from its suite, or a baseline section is gone with no
# culled line (its suite and census lines with it, or the half of a narrowed key), and the sweep passes.
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
census_file "$CN2/left.md"
expect_eq "a baseline section gone with its whole suite and its census lines, and no culled line, is refused by suite and key" \
  "gone with no culled line: x.test.sh §ONE|gone with no culled line: x.test.sh §TWO" \
  "$(census_cull_refusals "$CN2/tests" "$CN2/left.md" "$CN2/keep.md" | paste -sd'|' -)"
printf '%s\n' 'section "ONE: split out"' > "$CN2/tests/w.test.sh"
expect_eq "…a key split into a suite born since the baseline stands only while its own suite stands" \
  "gone with no culled line: x.test.sh §ONE|gone with no culled line: x.test.sh §TWO" \
  "$(census_cull_refusals "$CN2/tests" "$CN2/left.md" "$CN2/keep.md" | paste -sd'|' -)"
printf '%s\n' 'section "THREE: stays"' 'section "§FOUR §FIVE: narrowed"' > "$CN2/tests/x.test.sh"
census_file "$CN2/narrow.md" "$CS_ONE" 'x.test.sh | §FOUR §FIVE §SIX | keep | lib/x.sh: three arms | none (searched x in tests/)'
expect_eq "…so it stands with its suite, and a narrowed key is refused while the half that went has no line" \
  "gone with no culled line: x.test.sh §FOUR §FIVE §SIX" "$(census_cull_refusals "$CN2/tests" "$CN2/left.md" "$CN2/narrow.md")"
printf '\n## Culled\n\nx.test.sh §SIX — prose pin\n' >> "$CN2/left.md"
expect_eq "…and with that half listed nothing is refused" "" "$(census_cull_refusals "$CN2/tests" "$CN2/left.md" "$CN2/narrow.md")"

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
section "CENSUS-GONE: a cull gone with its code needs a listed name, and a culled duplicate rests only on standing, shown catchers"
# ============================================================
# fails-when: a section removed with its code cannot be culled by a name on the deletion list, a name off the list is
# admitted, or a culled duplicate naming an (unverified) catcher, a culled one or one no suite calls passes, the
# baseline census holding its line or not.
CG="$TMP/cg"; census_scratch "$CG"; CG_LIST="$TESTS_DIR/fixtures/deletion-list.txt"
printf '%s\n' 'section "ONE: the first"' 'expect_eq a 1 1' > "$CG/tests/x.test.sh"
CG_NAME="$(deletion_names "$CG_LIST" | sed -n 1p)"
expect_true "the deletion list yields names to cull by" [ -n "$CG_NAME" ]
census_file "$CG/gone.md" "$CS_ONE" 'x.test.sh | §TWO | keep | rule: lint — a shape planted | none (searched x in tests/)'
printf '\n## Culled\n\nx.test.sh §TWO — gone with %s\n' "$CG_NAME" >> "$CG/gone.md"
expect_eq "a rule: keep gone with a listed name is admitted" "" "$(census_cull_refusals "$CG/tests" "$CG/gone.md" /dev/null "$CG_LIST")"
sed -e 's/gone with .*/gone with no_such_name/' "$CG/gone.md" > "$CG/off.md"
expect_eq "…a name off the list is refused, named" "gone with an unlisted name: no_such_name" \
  "$(census_cull_refusals "$CG/tests" "$CG/off.md" /dev/null "$CG_LIST")"
CG_DUP='| duplicate | lib/x.sh: a line changed |'
census_file "$CG/unv.md" "$CS_ONE" "x.test.sh | §TWO $CG_DUP x.test.sh §ONE (unverified)" \
  "x.test.sh | §THREE $CG_DUP x.test.sh §ONE (unverified; a reason)" "x.test.sh | §FOUR $CG_DUP x.test.sh §TWO" \
  "x.test.sh | §FIVE $CG_DUP y.test.sh §ONE, x.test.sh §ONE" "x.test.sh | §SIX $CG_DUP x.test.sh §ONE (a note, a comma), x.test.sh §ONE"
{ printf '\n## Culled\n\n'; printf 'x.test.sh §%s — duplicate\n' TWO THREE FOUR FIVE SIX; } >> "$CG/unv.md"
expect_eq "culled duplicates on a marked, a culled or an uncalled catcher are refused though the baseline holds them; one on standing catchers is not" \
  "catcher stands in no suite: x.test.sh §FIVE names y.test.sh §ONE|culled catcher named: x.test.sh §FOUR names x.test.sh §TWO|unverified catcher culled: x.test.sh §THREE|unverified catcher culled: x.test.sh §TWO" \
  "$(census_cull_refusals "$CG/tests" "$CG/unv.md" "$CG/unv.md" "$CG_LIST" | paste -sd'|' -)"

# ============================================================
section "CENSUS-4: the tests tree is cut as tests/CENSUS.md says"
# ============================================================
# fails-when: a suite under tests/ still calls a section the census culls, a kept section or a baseline section is
# gone with no culled line, the culled list holds a keep or a rule pin, or a culled duplicate names a catcher that is
# marked unverified, culled or called by no suite.
CN4_CULLED="$(sed -n '/^## Culled$/,$p' "$CENSUS_MD" 2>/dev/null | /usr/bin/grep -c '\.test\.sh §')"
expect_true "the census carries a culled list to read (${CN4_CULLED} lines)" [ "${CN4_CULLED:-0}" -gt 0 ]
CN4_BASE="$TMP/census-base.md"; git -C "$REPO" show 7a9633486:tests/CENSUS.md > "$CN4_BASE" 2>/dev/null
expect_true "the baseline census is readable from history" [ -s "$CN4_BASE" ]
expect_eq "the real tests tree: no culled section called, no kept section gone, no keep or rule pin culled, no cull on an unshown catcher" "" \
  "$(census_cull_refusals "$TESTS_DIR" "$CENSUS_MD" "$CN4_BASE" "$TESTS_DIR/fixtures/deletion-list.txt")"

# ── the agreement checks ─────────────────────────────────────────────────────
# A document states a fact twice, once in a front matter or a header and once in the body that carries it, and
# nothing reads the two against each other. Two sweeps do: an ADR's `status:` against its `## Status` section, and a
# suite's header list of sections against the `section` calls of its body. The body is the fact and the header
# follows it.
# adr_refusals <dir...> -> one line per ADR under the directories (every *.md, recursively) whose front-matter
# `status:` and `## Status` section open with different words, naming the file and both. The word is the first run
# of letters, folded to lower case, so `accepted` and `**Accepted** (Step 7)` agree. A file with only one of the two
# is not compared, and a directory that is not there is skipped.
adr_refusals() {
  local d f
  for d in "$@"; do
    [ -d "$d" ] || continue
    find -H "$d" -name '*.md' -type f | LC_ALL=C sort | while IFS= read -r f; do
      LC_ALL=C awk -v F="$f" '
        function word(s,   w) { sub(/^[^A-Za-z]*/, "", s); w = s; sub(/[^A-Za-z].*$/, "", w); return tolower(w) }
        NR == 1 { fm = ($0 == "---"); next }
        fm == 1 { if ($0 == "---") fm = 2; else if (sw == "" && $0 ~ /^status:/) { v = $0; sub(/^status:[ \t]*/, "", v); sw = word(v) }; next }
        /^## Status[ \t]*$/ { ins = 1; next }
        /^## / { ins = 0 }
        ins && bw == "" && NF { bw = word($0) }
        END { if (sw != "" && bw != "" && sw != bw) print F ": status: " sw " but ## Status " bw }' "$f"
    done
  done
}


# ============================================================
section "ADR: an ADR whose status: word differs from its ## Status word is refused by file, naming both words"
# ============================================================
# fails-when: an ADR's front matter says Accepted while its ## Status section still says Proposed, and the sweep passes.
AD="$TMP/adr"; mkdir -p "$AD/hermetic" "$AD/own/epic/deep"
adr_file() { # <path> <status: value or -> <body line or ->
  { printf -- '---\nname: x\n'; [ "$2" = "-" ] || printf 'status: %s\n' "$2"; printf -- '---\n# ADR\n\n## Status\n\n'
    [ "$3" = "-" ] || printf '%s\n' "$3"; printf '\n## Context\n\nProposed in the prose below Context is not a status.\n'; } > "$1"
}
adr_file "$AD/hermetic/agree.md"  "Accepted (Step 7, 2026-10-01)" "**Accepted** (Step 7, 2026-10-01). Ruled."
adr_file "$AD/hermetic/case.md"   "accepted" "Accepted, 2026-09-05."
adr_file "$AD/hermetic/nobody.md" "Accepted" "-"
adr_file "$AD/hermetic/nostatus.md" "-" "Proposed"
printf '# no front matter\n\n## Status\n\nProposed\n' > "$AD/hermetic/bare.md"
adr_file "$AD/hermetic/drift.md"  "Accepted (close-out, 2026-10-19; Proposed at Step 2)" "**Proposed** (Step 2, 2026-10-18)."
adr_file "$AD/own/epic/deep/drift2.md" "Superseded (Step 7) by adr-065" "Proposed (Step 2)."
expect_eq "the sweep reads every file of both halves, nested ones too: seven files" "7" \
  "$(find -H "$AD" -name '*.md' | wc -l | tr -d ' ')"
expect_eq "control: an agreeing pair, a case and emphasis difference, a file with no body status, no status: and no front matter are refused for nothing" "" \
  "$(adr_refusals "$AD/hermetic" | /usr/bin/grep -v 'drift' )"
expect_eq "a status: Accepted over a ## Status Proposed is refused naming the file and both words" \
  "$AD/hermetic/drift.md: status: accepted but ## Status proposed" "$(adr_refusals "$AD/hermetic")"
expect_eq "a second directory is read too, recursively, and a directory that is not there is skipped" \
  "$AD/hermetic/drift.md: status: accepted but ## Status proposed|$AD/own/epic/deep/drift2.md: status: superseded but ## Status proposed" \
  "$(adr_refusals "$AD/hermetic" "$AD/none" "$AD/own" | paste -sd'|' -)"
sed -e 's/Proposed\*\*/Accepted**/' "$AD/hermetic/drift.md" > "$AD/fixed.md" && mv "$AD/fixed.md" "$AD/hermetic/drift.md"
expect_eq "the body word brought to the front matter's clears the refusal for that file alone" \
  "$AD/own/epic/deep/drift2.md: status: superseded but ## Status proposed" \
  "$(adr_refusals "$AD/hermetic" "$AD/own")"
ADR_HERMETIC="$(find -H "$REPO/docs/adrs" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
ADR_OWN="$(find -H "$REPO/.bionic/docs/adrs" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
expect_true "the real tree is read: docs/adrs holds ${ADR_HERMETIC} ADRs (the run's own .bionic/docs/adrs holds ${ADR_OWN}, read when present)" \
  [ "${ADR_HERMETIC:-0}" -gt 0 ]
expect_contains "the real sweep reads ADR-062 and finds its own ## Status word beside its status: word" \
  "adr-062" "$(find -H "$REPO/docs/adrs" -name 'adr-062*.md')"
expect_eq "every ADR of the real tree has the same state word in its status: and in its ## Status: no refusal" "" \
  "$(adr_refusals "$REPO/docs/adrs" "$REPO/.bionic/docs/adrs")"

# ============================================================
section "HEADER: a suite header that lists a section its body lacks, or misses one its body has, is refused by suite"
# ============================================================
# fails-when: a header lists a section no longer called in its body, or a body section is missing from the header's list,
# and the sweep passes.
HD="$TMP/hd"; mkdir -p "$HD/tests"
hdr_suite() { # <name> <header entry keys, space-separated, - for none> <body section titles, | separated>
  local out="$HD/tests/$1.test.sh" k t
  { printf '#!/bin/bash\n# A suite header.\n#\n'
    for k in $2; do [ "$k" = "-" ] || printf '#   §%s   what the section holds\n' "$k"; done
    printf '# See §ZZ of the plan, a sentence naming a section of something else.\n\n. lib.sh\n'
    printf '%s\n' "$3" | tr '|' '\n' | while IFS= read -r t; do printf 'section "%s"\nexpect_eq a 1 1\n' "$t"; done
    printf 'finish\n'; } > "$out"
}
hdr_suite equal   "ONE TWO THREE" "ONE — the first|§TWO: the second|THREE|a sentence that names no key"
hdr_suite ghost   "ONE TWO GHOST" "ONE: the first|TWO: the second"
hdr_suite short   "ONE" "ONE: the first|TWO: the second"
hdr_suite both    "ONE GHOST" "ONE: the first|TWO: the second"
hdr_suite bare    "-" "ONE: the first|TWO: the second"
hdr_suite shared  "TWO" "TWO: the first|TWO: the second"
printf '%s\n' "cat > scratch.sh <<'PLANT'" 'section "HIDDEN: inside a heredoc"' 'PLANT' 'section "ONE: real"' > "$HD/tests/hidden.sh"
{ printf '#!/bin/bash\n#\n#   §ONE   real\n\n'; cat "$HD/tests/hidden.sh"; } > "$HD/tests/hidden.test.sh"; rm -f "$HD/tests/hidden.sh"
expect_eq "the sweep reads the scratch header: three entries for equal, in order" "ONE|THREE|TWO" \
  "$(header_entries "$HD/tests/equal.test.sh" | paste -sd'|' -)"
expect_eq "…and the entry in a sentence (§ZZ) is not one, and a bare header lists none" "" \
  "$(header_entries "$HD/tests/bare.test.sh")"
expect_eq "…the body keys of equal are the census keys cut at the first space, § dropped, and a title that is a sentence has none" "ONE|THREE|TWO" \
  "$(body_keys "$(census_calls "$HD/tests")" equal.test.sh | paste -sd'|' -)"
expect_eq "control: a header whose entries equal its body's keys, a header with no entry, a shared key, and a section call inside a heredoc body are refused for nothing" "" \
  "$(header_refusals "$HD/tests" | /usr/bin/grep -v '^ghost\|^short\|^both')"
expect_eq "a header entry with no section is refused naming the suite and the entry" \
  "ghost.test.sh: header lists §GHOST with no section" "$(header_refusals "$HD/tests" | /usr/bin/grep '^ghost')"
expect_eq "a body section the header does not list is refused naming the suite and the key" \
  "short.test.sh: body has §TWO with no header entry" "$(header_refusals "$HD/tests" | /usr/bin/grep '^short')"
expect_eq "both differences on one suite are named on one line" \
  "both.test.sh: header lists §GHOST with no section; body has §TWO with no header entry" \
  "$(header_refusals "$HD/tests" | /usr/bin/grep '^both')"
SL_COPY="$TMP/hd-self"; mkdir -p "$SL_COPY"; cp "$TESTS_DIR/shell-lint.test.sh" "$SL_COPY/shell-lint.test.sh"
SL_CALLS="$(census_calls "$SL_COPY")"
expect_eq "shell-lint's own header lists exactly the sections its body calls" \
  "$(body_keys "$SL_CALLS" shell-lint.test.sh | paste -sd' ' -)" "$(header_entries "$SL_COPY/shell-lint.test.sh" | paste -sd' ' -)"
awk 'NR == 2 { print "#   §GHOST   a sweep the body never runs" } { print }' "$TESTS_DIR/shell-lint.test.sh" > "$SL_COPY/shell-lint.test.sh"
expect_eq "mutant: a sweep named in shell-lint's header that its body lacks is refused naming the suite" \
  "shell-lint.test.sh: header lists §GHOST with no section" "$(header_refusals "$SL_COPY")"
expect_eq "control: the unmutated copy beside it is refused for nothing" "" \
  "$(cp "$TESTS_DIR/shell-lint.test.sh" "$SL_COPY/shell-lint.test.sh"; header_refusals "$SL_COPY")"
HD_LISTED=0
for f in "$TESTS_DIR"/*.test.sh; do [ -z "$(header_entries "$f")" ] || HD_LISTED=$((HD_LISTED + 1)); done
expect_true "the real sweep judges suites: ${HD_LISTED} headers list their sections" [ "$HD_LISTED" -gt 0 ]
expect_eq "every suite header of the real tests tree lists only sections its body calls, and every body section it lists: no refusal" "" \
  "$(header_refusals "$TESTS_DIR")"


# ============================================================
section "INTEGRATION-REF: no product line merges into the integration branch or moves its ref"
# ============================================================
# The merge is the person's, made on the host, and read remotely: no product line may merge into the local integration
# branch, move its ref, or fetch into a local branch. A line that merges or moves a ref is read for a name the
# integration branch is held under (the reader `plan_integration_branch`, and the names its callers bind it to); a fetch
# is read for each refspec, whose destination must be under refs/remotes/. Comment lines are prose.
# fails-when: a product line merges into the integration branch, moves its ref, or fetches into a local branch, and the
# sweep passes.
IR_MOVE='(^|[^A-Za-z0-9_-])git([[:space:]].*)?[[:space:]](merge|update-ref|reset|rebase|pull|cherry-pick|(branch[[:space:]]+(-f|--force|-M|-C))|((checkout|switch)[[:space:]]+-[BC]))([[:space:]]|"|$)'
IR_FETCH='(^|[^A-Za-z0-9_-])git([[:space:]].*)?[[:space:]]fetch([[:space:]]|$)'
IR_NAMES='INTEGRATION|integration_branch|[$][{]?ib([^A-Za-z0-9_]|$)'
ir_lines() {  # <pattern> <dir>... -> <file>:<line>:<text> of each code line in the dirs' *.sh files matching the pattern
  local pat="$1"; shift
  /usr/bin/grep -rnE --include='*.sh' "$pat" "$@" 2>/dev/null | /usr/bin/grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'
}
ir_refusals() {  # <dir>... -> each line that moves the integration branch or fetches into a local ref, named
  ir_lines "$IR_MOVE" "$@" | /usr/bin/grep -E "$IR_NAMES" | sed 's/^/moves the integration branch: /'
  ir_lines "$IR_FETCH" "$@" | while IFS= read -r l; do
    printf '%s\n' "${l#*:*:}" | tr ' \t' '\n\n' | tr -d "\"'" | /usr/bin/grep ':' | /usr/bin/grep -v '^[0-9]*>&' \
      | sed 's/^+//; s/.*://' | /usr/bin/grep -qv '^refs/remotes/' && printf 'fetches into a local ref: %s\n' "$l"
  done
}
IR="$TMP/ir"; mkdir -p "$IR/ok" "$IR/bad"
printf '%s\n' '#!/bin/bash' 'git -C "$root" fetch --quiet origin "+refs/heads/$ib:refs/remotes/origin/$ib"' \
  'git -C "$co" merge --ff-only -q "$tip"' '# git -C "$ROOT" merge "$INTEGRATION" is prose here' \
  'git -C "$ROOT" merge-base --is-ancestor "$WORKING" "$INTEGRATION"' > "$IR/ok/ok.sh"
printf '%s\n' '#!/bin/bash' 'git -C "$ROOT" fetch --quiet origin "$INTEGRATION:$INTEGRATION"' > "$IR/bad/fetch.sh"
printf '%s\n' '#!/bin/bash' 'git -C "$ROOT" checkout -q "$INTEGRATION" && git -C "$ROOT" merge --no-ff "$WORKING"' > "$IR/bad/merge.sh"
printf '%s\n' '#!/bin/bash' '  git -C "$root" update-ref "refs/heads/$ib" "$tip"' > "$IR/bad/ref.sh"
for f in "$IR"/ok/*.sh "$IR"/bad/*.sh; do expect_true "the planted ${f#"$IR"/} parses under /bin/bash -n" /bin/bash -n "$f"; done
expect_eq "control: a fetch into origin's tracking ref, a fast-forward of a branch the line names, a comment, a merge-base: refused for nothing" "" \
  "$(ir_refusals "$IR/ok")"
expect_eq "a fetch into the local integration branch, a merge into it and a move of its ref are each refused by file and line" \
  "fetches into a local ref: $IR/bad/fetch.sh:2:|moves the integration branch: $IR/bad/merge.sh:2:|moves the integration branch: $IR/bad/ref.sh:2:" \
  "$(ir_refusals "$IR/bad" | sed -E 's/^(.*\.sh:[0-9]+:).*/\1/' | LC_ALL=C sort | paste -sd'|' -)"
IR_MOVES="$(ir_lines "$IR_MOVE" "$REPO/hooks" "$REPO/payload/scripts" | wc -l | tr -d ' ')"
IR_FETCHES="$(ir_lines "$IR_FETCH" "$REPO/hooks" "$REPO/payload/scripts" | wc -l | tr -d ' ')"
expect_true "the real sweep reads lines to judge: ${IR_MOVES} merge or move ref lines, ${IR_FETCHES} fetch lines in hooks/ and payload/scripts" \
  test "${IR_MOVES:-0}" -gt 0 -a "${IR_FETCHES:-0}" -gt 0
expect_contains "…among them the merge's one reader's fetch, into origin's tracking ref" "refs/remotes/origin/" \
  "$(ir_lines "$IR_FETCH" "$REPO/payload/scripts/lib/line.sh")"
expect_eq "no product line in hooks/ or payload/scripts merges into the integration branch, moves its ref, or fetches into a local ref" "" \
  "$(ir_refusals "$REPO/hooks" "$REPO/payload/scripts")"


# ============================================================
section "LINT — tests/lib/lint.sh, told the files a row changed, names each check's hit there by file and line"
# ============================================================
# The landing runs tests/lib/lint.sh over the paths a row changed. A planted tree holds one hit for each of EXIT, BP
# and HEADER, each in a file of its own, and a clean file; told one path, the run names that file's hit and no other.
LT="$TMP/lint-tree"; mkdir -p "$LT/hooks" "$LT/payload/scripts/lib" "$LT/tests/lib"
cp "$TESTS_DIR/RUBRIC.md" "$LT/tests/RUBRIC.md"
printf '%s\n' '#!/bin/bash' 'die "REFUSED — no exit"' > "$LT/hooks/e.sh"
printf '%s\n' '#!/bin/bash' 'set -o pipefail' 'git show HEAD:x | grep -q y && echo found' > "$LT/payload/scripts/lib/q.sh"
printf '%s\n' '#!/bin/bash' 'echo clean' > "$LT/payload/scripts/lib/c.sh"
printf '%s\n' '#!/bin/bash' '# t.test.sh' '#' '#   §ONE   the first' '#   §TWO   the second' '' 'section "ONE — the first"' > "$LT/tests/t.test.sh"
lint_at() { printf '%s\n' "${@:2}" | bash "$TESTS_DIR/lib/lint.sh" "$1" 2>&1 | cut -d' ' -f1-2 | paste -sd'|' -; }   # <root> <path>... -> CHECK and site of each hit
expect_eq "LINT-1 told the refusal's file, the run names its EXIT hit by line and nothing else" "EXIT hooks/e.sh:2" "$(lint_at "$LT" hooks/e.sh)"
expect_eq "…told the pipe's file, its BP hit by line" "BP payload/scripts/lib/q.sh:3" "$(lint_at "$LT" payload/scripts/lib/q.sh)"
expect_eq "…told the suite, its HEADER hit, naming the listed key the body lacks" "HEADER tests/t.test.sh: header lists §TWO with no section" \
  "$(printf '%s\n' tests/t.test.sh | bash "$TESTS_DIR/lib/lint.sh" "$LT" 2>&1)"
expect_eq "…told all four, the three hits; told the clean file alone, none, and it exits 0" "BP payload/scripts/lib/q.sh:3|EXIT hooks/e.sh:2|HEADER tests/t.test.sh:|0" \
  "$(lint_at "$LT" hooks/e.sh payload/scripts/lib/q.sh tests/t.test.sh payload/scripts/lib/c.sh | tr '|' '\n' | LC_ALL=C sort | paste -sd'|' -)|$(printf '%s\n' payload/scripts/lib/c.sh | bash "$TESTS_DIR/lib/lint.sh" "$LT" >/dev/null 2>&1; echo $?)"
# The ceiling file: the refusal at its file's ceiling is no hit; a row that lowers the ceiling under the count, told
# only the ceiling changed, is named at the ceiling's own line as well as at the site.
printf '%s\n' '# the ceiling' 'hooks/e.sh 1 # one left' > "$LT/tests/lib/refusal-exits.ceiling"
expect_eq "LINT-2 a refusal within its file's ceiling is no hit" "" "$(lint_at "$LT" hooks/e.sh)"
printf '%s\n' '# the ceiling' 'hooks/e.sh 0 # none left' > "$LT/tests/lib/refusal-exits.ceiling"
expect_eq "…a ceiling lowered under the count, told the ceiling alone changed, is named at its line and at the site" \
  "EXIT hooks/e.sh:2|EXIT tests/lib/refusal-exits.ceiling:2" "$(lint_at "$LT" tests/lib/refusal-exits.ceiling | tr '|' '\n' | LC_ALL=C sort | paste -sd'|' -)"
rm -f "$LT/tests/RUBRIC.md"
expect_eq "LINT-3 a check that cannot run exits 2 naming what it lacks" "2|lint.sh: HEADER reads sections by tests/RUBRIC.md's command" \
  "$(printf '%s\n' tests/t.test.sh | bash "$TESTS_DIR/lib/lint.sh" "$LT" 2>"$TMP/lint3.err" >/dev/null; echo "$?|$(sed 's/, which.*//' "$TMP/lint3.err")")"


# ============================================================
section "SETUP — a shared setup that loads a helper on a line with no stop is refused by file and line"
# ============================================================
# A shared setup (tests/*.prelude.sh) that cannot load a helper goes on without its functions: a maker that is not
# there leaves a fixture's path empty, and the next `git -C ""` acts on the repository the suite stands in. So every
# load in a setup reads its own status: a `||` that exits or returns, a chain whose next command needs it, or an `if`
# that tests it. A heredoc body is fixture text, and a load inside a quoted child script is that child's.
# fails-when: a setup loads a helper on a line with no stop, and the sweep passes.
SU="$TMP/setup"; mkdir -p "$SU"
printf '%s\n' '#!/bin/bash' \
  '. "$(dirname "${BASH_SOURCE[0]}")/lib/a.sh"' \
  'declare -F f >/dev/null 2>&1 || . "$(dirname "$0")/lib/b.sh"' \
  'mk() { ( cd "$1" || exit 1; . "$R/lib/c.sh"; c_make "$1" ); }' \
  'source lib/d.sh 2>&1; echo after' > "$SU/bad.prelude.sh"
printf '%s\n' '#!/bin/bash' \
  '[ -r "$H/lib/a.sh" ] && . "$H/lib/a.sh" || { echo "x: cannot load $H/lib/a.sh" >&2; exit 1; }' \
  'declare -F f >/dev/null 2>&1 || { [ -r "$H/lib/b.sh" ] && . "$H/lib/b.sh"; } || { echo "x: no b" >&2; exit 1; }' \
  'chk() { . "$1/run.sh" && . "$1/proof.sh" || exit 99; }' \
  'ask() { ( . "$R/lib/gate.sh" 2>/dev/null && gate_ask "$1" ); }' \
  'if [ -r "$LINE" ] && . "$LINE" 2>/dev/null; then L=1; fi' \
  'type -t g >/dev/null 2>&1 || . "$R/lib/g.sh" || return 1 2>/dev/null || exit 1' \
  "kid() { bash -c '. \"\$1/run.sh\"; run_it' _ \"\$R\"; }" \
  'find . -name x >/dev/null; git -C "$r" init -q .' \
  '# . lib/commented.sh' \
  "cat > \"\$p/s.sh\" <<'EOF'" '. lib/fixture-text.sh' 'EOF' > "$SU/good.prelude.sh"
for f in "$SU"/*.prelude.sh; do expect_true "the planted ${f##*/} parses under /bin/bash -n" /bin/bash -n "$f"; done
# The hazard, measured: a bare load of a missing helper goes on to the next line; the stopped form ends there, in one line.
printf '%s\n' '. "$(dirname "${BASH_SOURCE[0]}")/lib/a.sh"' 'echo went-on' > "$SU/run-bare.sh"
printf '%s\n' '[ -r "$(dirname "${BASH_SOURCE[0]}")/lib/a.sh" ] && . "$(dirname "${BASH_SOURCE[0]}")/lib/a.sh" || { echo "x: cannot load lib/a.sh" >&2; exit 1; }' \
  'echo went-on' > "$SU/run-stopped.sh"
SU_OUT="$(/bin/bash "$SU/run-bare.sh" 2>/dev/null)"; SU_RC=$?
expect_eq "mutant: a bare load of a missing helper, run under /bin/bash, goes on past it" "went-on|0" "$SU_OUT|$SU_RC"
SU_OUT="$(/bin/bash "$SU/run-stopped.sh" 2>"$SU/stopped.err")"; SU_RC=$?
expect_eq "control: the stopped load exits 1 before the next line, with one line naming the helper" "|1|x: cannot load lib/a.sh" \
  "$SU_OUT|$SU_RC|$(paste -sd'#' "$SU/stopped.err")"
expect_eq "SETUP-1 each load with no stop is refused by file and line: a bare load, the fallback of a test, a subshell that goes on, a load a ; drops" \
  "$SU/bad.prelude.sh:2|$SU/bad.prelude.sh:3|$SU/bad.prelude.sh:4|$SU/bad.prelude.sh:5" \
  "$(setup_refusals "$SU/bad.prelude.sh" | cut -f1 | paste -sd'|' -)"
expect_eq "…and the same reader finds every load of the stopped setup, the tested and chained ones too: seven, none in the heredoc, the quoted child or the comment" "7" \
  "$(setup_loads "$SU/good.prelude.sh" | wc -l | tr -d ' ')"
expect_eq "control: stopped, chained and tested loads, a quoted child's load, a heredoc body and a comment are refused for nothing" "" \
  "$(setup_refusals "$SU/good.prelude.sh")"
SU_REAL="$(setup_loads "$TESTS_DIR"/*.prelude.sh | wc -l | tr -d ' ')"
expect_true "the real sweep reads loads: ${SU_REAL} in the shared setups under tests/" [ "${SU_REAL:-0}" -gt 0 ]
expect_eq "SETUP-2 every load in the real shared setups reads its own status: no refusal" "" "$(setup_refusals "$TESTS_DIR"/*.prelude.sh)"
mkdir -p "$LT/tests" && cp "$SU/bad.prelude.sh" "$LT/tests/bad.prelude.sh" && cp "$SU/good.prelude.sh" "$LT/tests/good.prelude.sh"
expect_eq "SETUP-3 the landing's run, told the bad setup, names its four loads as SETUP hits by line" \
  "SETUP tests/bad.prelude.sh:2|SETUP tests/bad.prelude.sh:3|SETUP tests/bad.prelude.sh:4|SETUP tests/bad.prelude.sh:5" \
  "$(lint_at "$LT" tests/bad.prelude.sh)"
expect_eq "…told the stopped setup alone, none, and it exits 0" "|0" \
  "$(printf '%s\n' tests/good.prelude.sh | bash "$TESTS_DIR/lib/lint.sh" "$LT" 2>&1; echo "|$?")"

# ============================================================
section "STOP — a maker that fails stops the suite that asked, and a file that stops through maker_stop loads it"
# ============================================================
# A suite takes a maker's path as `R="$(make_repo x)"`, in a command substitution, so a maker's own exit ends only
# that child: tests/lib/maker-stop.sh ends the shell that loaded it, and every process under that shell, from
# wherever the maker runs. Each take below runs in a child bash that loads the real file, the way a row that tests a
# refusal must; the child is then the suite that stops. The maker is handed a folder it cannot make, and the line
# after the take would write a mark.
# fails-when: maker_stop only exits its own process, or signals a process group, or leaves its notice twice, and
# the take's next line runs; or a file calls maker_stop with no load of maker-stop.sh, and the sweep passes.
ST="$TMP/stop"; mkdir -p "$ST/ro"; chmod 500 "$ST/ro"
st_child() {  # <maker body> <take shape> -> rc|stderr lines|marks, of a child bash that takes through the shape
  rm -f "$ST/went-on" "$ST/cleaned"
  { printf '%s\n' ". \"$TESTS_DIR/lib/maker-stop.sh\" || exit 9" "trap ': > \"$ST/cleaned\"' EXIT" \
      "mk() { mkdir -p \"\$1\" 2>/dev/null && git -C \"\$1\" init -q 2>/dev/null || $1; printf '%s' \"\$1\"; }"
    printf '%s\n' "$2" ": > \"$ST/went-on\""; } > "$ST/child.sh"
  /bin/bash "$ST/child.sh" 2>"$ST/child.err"; printf '%s|%s|%s%s' "$?" "$(awk 'END { print NR }' "$ST/child.err")" \
    "$([ -e "$ST/cleaned" ] && echo cleaned)" "$([ -e "$ST/went-on" ] && echo ' went-on')"
}
ST_STOP='maker_stop mk "no repository of its own at $1"'
expect_true "tests/lib/maker-stop.sh parses under /bin/bash -n" /bin/bash -n "$TESTS_DIR/lib/maker-stop.sh"
expect_eq "mutant: a maker that only returns 1 hands the take an empty path, and the next line runs" "0|0|cleaned went-on" \
  "$(st_child 'return 1' "R=\"\$(mk \"$ST/ro/r\")\"; [ -z \"\$R\" ] || exit 7")"
expect_eq "STOP-1 a take in the suite's own shell: exit 1, one line, the EXIT trap run, no next line" "1|1|cleaned" \
  "$(st_child "$ST_STOP" "R=\"\$(mk \"$ST/ro/r\")\"")"
expect_eq "…the one line names the maker and says the suite stops" "mk: no repository of its own at $ST/ro/r; the suite stops" \
  "$(cat "$ST/child.err")"
expect_eq "…a take inside ( … ): the subshell's next line and the suite's do not run" "1|1|cleaned" \
  "$(st_child "$ST_STOP" "( R=\"\$(mk \"$ST/ro/r\")\"; : > \"$ST/went-on\" )")"
expect_eq "…a take two command substitutions deep" "1|1|cleaned" \
  "$(st_child "$ST_STOP" "f() { local x; x=\"\$(mk \"$ST/ro/r\")\"; printf '%s' \"\$x\"; }; R=\"\$(f)\"")"
expect_eq "…a take beside a background row: the row is ended too, and leaves no notice" "1|1|cleaned" \
  "$(st_child "$ST_STOP" "( sleep 2; : > \"$ST/went-on\" ) & R=\"\$(mk \"$ST/ro/r\")\"")"
sleep 3
expect_eq "…and the background row never ran its line" "no" "$([ -e "$ST/went-on" ] && echo yes || echo no)"
# The stop reaches the loading shell and what runs under it, by process id: a process beside the child, started
# from this suite, is alive after the child stopped.
sleep 30 & ST_SIB=$!
expect_eq "STOP-2 a process beside the stopped child, under this suite, is not reached by the stop" "1|1|cleaned|alive" \
  "$(st_child "$ST_STOP" "R=\"\$(mk \"$ST/ro/r\")\"")|$(kill -0 "$ST_SIB" 2>/dev/null && echo alive || echo gone)"
kill "$ST_SIB" 2>/dev/null; wait "$ST_SIB" 2>/dev/null
chmod 700 "$ST/ro"
# The lint: a file that calls maker_stop loads it itself, since without the function the call answers 127 and the
# maker goes on to write through the path it refused.
printf '%s\n' '#!/bin/bash' 'mk() {' '  # maker_stop in a comment is no call' \
  '  git -C "$1" init -q || maker_stop mk "no repository at $1"' '}' > "$ST/bad.prelude.sh"
printf '%s\n' '#!/bin/bash' '[ -r "$H/lib/maker-stop.sh" ] && . "$H/lib/maker-stop.sh" || { echo "x: cannot load" >&2; exit 1; }' \
  'mk() { git -C "$1" init -q || maker_stop mk "no repository at $1"; }' > "$ST/good.prelude.sh"
printf '%s\n' '#!/bin/bash' "cat > \"\$p/s.sh\" <<'EOF'" 'maker_stop mk "fixture text"' 'EOF' > "$ST/text.prelude.sh"
for f in "$ST"/*.prelude.sh; do expect_true "the planted ${f##*/} parses under /bin/bash -n" /bin/bash -n "$f"; done
expect_eq "STOP-3 a call of maker_stop in a file with no load of it is refused at the call's line" "$ST/bad.prelude.sh:4" \
  "$(stop_refusals "$ST/bad.prelude.sh" | cut -f1)"
expect_eq "control: the file that loads it, and a heredoc body that names it, are refused for nothing" "" \
  "$(stop_refusals "$ST/good.prelude.sh" "$ST/text.prelude.sh")"
ST_REAL="$(for f in "$TESTS_DIR"/*.prelude.sh "$TESTS_DIR"/lib/*.sh; do /usr/bin/grep -l 'maker_stop [a-z"]' "$f"; done | wc -l | tr -d ' ')"
expect_true "the real sweep has callers to read: ${ST_REAL} files of tests/ call maker_stop" [ "${ST_REAL:-0}" -gt 1 ]
expect_eq "STOP-4 every real setup and library that calls maker_stop loads it" "" \
  "$(stop_refusals "$TESTS_DIR"/*.prelude.sh "$TESTS_DIR"/lib/*.sh)"
cp "$ST/bad.prelude.sh" "$LT/tests/stopbad.prelude.sh" && mkdir -p "$LT/tests/lib" && cp "$ST/bad.prelude.sh" "$LT/tests/lib/stopbad.sh"
expect_eq "STOP-5 the landing's run, told a setup and a library that call it unloaded, names each as a STOP hit" \
  "STOP tests/lib/stopbad.sh:4|STOP tests/stopbad.prelude.sh:4" "$(lint_at "$LT" tests/stopbad.prelude.sh tests/lib/stopbad.sh | tr '|' '\n' | LC_ALL=C sort | paste -sd'|' -)"

finish
