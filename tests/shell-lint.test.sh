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
# each with its mutant. §BP keeps its quitting-`grep -q` sweep.
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
#   U<TAB><file><TAB><state>                    the file ended with a frame still open
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
      if (substr(s, i, 4) == "esac" && isb(substr(s, i + 4, 1))) {
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
      nb = (m != "") && isb(substr(s, i + length(m), 1))
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
          i += 7; ws = 0; continue
        }
      }
      if (AT[d]) {
        if (c == "{" && isb(substr(s, i + 1, 1))) { BR[d]++; continue }
        if (c == "}" && isb(substr(s, i + 1, 1))) { BR[d]--; AT[d] = 0; ws = 0; continue }
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
# quotes and parentheses and nothing of heredocs, so a lone ) closes the substitution.
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
# A file that ends with a frame, a case or a heredoc still open is one the lexer lost its
# place in, and every row it printed after that point is suspect: it says so.
function closefile(f,   st, x) {
  if (f == "" || (d == 1 && cn == 0 && !hdon && np == 0)) return
  st = ""; for (x = 1; x <= d; x++) st = st K[x] (x < d ? "/" : "")
  printf "U\t%s\t%s cases=%d heredoc=%s\n", f, st, cn, (hdon ? HD[hc] : "-")
}
FNR == 1 {
  closefile(PREVF); PREVF = FILENAME; PQS = ""
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

finish
