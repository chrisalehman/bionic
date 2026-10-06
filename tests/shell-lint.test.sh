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
# the lexer is not written yet: it reads nothing and names nothing
{ }
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

finish
