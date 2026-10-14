#!/bin/bash
# tests/placement.test.sh — payload/scripts/lib/placement.sh, THE ONE READER OF WHERE A COMMAND RUNS
# (wave-36 T3; spec D11, ruled at D6; REQ-5 AC-5.1, AC-5.5).
#
# THE DEFECT THIS SUITE EXISTS FOR. Four readers answered "where does this command run" with four
# grammars (research-landing-and-walls.md §Q2 cause A): the shim's stamp walk, the gate's tree, the
# commit's cwd and its separator test. The stamp walk asked the RAW TEXT ahead of the suite for a
# parenthesis, a pipe or a backquote, and asked that the suite's segment occur verbatim in the
# command, so a note in quotes, a heredoc, a `$(date)` in an echo or a `> "$LOG"` redirect unplaced
# a run that plainly ran in the tree it cd'd to. Eighteen of wave-35's runs were not counted for it
# (§Q5, probe P1b). `cmd_place` reads cmd-class's parsed segments instead: quoted text and heredoc
# bodies are invisible to it by construction, and a cd it cannot read is `moving`, never a guess.
#
# THE CONTRACT these rows pin is stated in full in
# .bionic/docs/record/wave-36-zero-machine-errors/T3-placement.md, which T25 (the four callers) and
# T4 (the jurisdiction arm) read.
#
# §FORMS is the row's red-first pin: wave-35's six refused shapes, each placed at the tree.
#
# FIXTURE FIDELITY (per .claude/rules/test-harness.md, "Fixture fidelity"). Every command is a
# string handed to the function, the way a hook hands it the payload's tool_input.command. The
# §FORMS commands are the shapes research §Q5 extracted from wave-35's not-counted transcripts
# (probe P1b: T34's quoted note, T38's printf, T33's heredoc, T31/T38's `> "$LOG"`, T20's
# `$(date)`), re-typed around a sandbox tree; the rest are SYNTHESIZED, one per contract clause.
# HERMETIC. Pure text in, text out: the reader touches no filesystem, so the trees named here need
# not exist; HOME is a sandbox directory so `~` reads the same on any machine.
#
# ANTI-VACUITY (per .claude/rules/test-harness.md, "Anti-vacuity"). P0 refuses to go on when the
# library is missing or defines no cmd_place. Every empty-output row (G6, G7, A1) sits beside a
# positive on the same call in the same fixture (G6-positive, A3).
#
# Usage: tests/run.sh --only placement.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

PLACEMENT_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/placement.sh"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/placement-test.XXXXXX")" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT
HOME="$SANDBOX/home"; export HOME
mkdir -p "$HOME"

CWD="$SANDBOX/main"            # where the tool call stands (the payload cwd)
T="$SANDBOX/trees/t1"          # the tree a cd names
U="$SANDBOX/trees/u2"          # a second tree
SUITE='tests/run.sh --only a.test.sh'

P_OUT=""; P_RC=0
place() {  # <command> <cwd> [<target>] -> P_OUT, P_RC
  P_OUT="$(cmd_place "$@")"; P_RC=$?
  return 0
}
placed() {  # <label> <command> <expected tree> [<target>; default suite]
  place "$2" "$CWD" "${4:-suite}"
  expect_eq "$1 [$2] is placed at $3" "$3" "$P_OUT"
  expect_status "$1 …exit 0" 0 "$P_RC"
}
moving() {  # <label> <command> <expected segment> [<target>; default suite]
  place "$2" "$CWD" "${4:-suite}"
  expect_eq "$1 [$2] is moving, naming the segment" "moving $3" "$P_OUT"
  expect_status "$1 …exit 1" 1 "$P_RC"
}
require_helpers place placed moving

section "P0 — the library exists, parses and defines cmd_place"
expect_true "P0a: placement.sh exists" test -r "$PLACEMENT_LIB"
expect_true "P0b: placement.sh parses" bash -n "$PLACEMENT_LIB"
# shellcheck disable=SC1090
. "$PLACEMENT_LIB" 2>/dev/null
expect_eq "P0c: sourcing it defines cmd_place" "function" "$(type -t cmd_place 2>/dev/null)"
if [ "$(type -t cmd_place 2>/dev/null)" != function ]; then
  echo "placement: cmd_place is not defined — the rest of the suite would read nothing"
  finish
fi

section "FORMS — wave-35's six refused shapes are placed at the tree (AC-5.1; research §Q5)"
# Each opens with the literal guard every brief prescribes, then trips one clause of the raw-text
# walk that refused it: a quoted parenthesis, a heredoc, a `$(…)` in a segment that moves nothing,
# a suite redirected to a pinned variable, a redirection on the cd itself, a pipe in a note.
placed "F1 a quoted parenthesis" \
  "cd $T || exit 1; echo \"red run done (7 BM FAIL, rest pass); next\" >> p.md; $SUITE" "$T"
placed "F2 a heredoc" \
  "cd $T || exit 1; cat >> assumptions.md <<'EOF'
- A-T33-1 (T33, 2026-10-12): a (b) | c \`d\` cd /elsewhere
EOF
$SUITE" "$T"
placed "F3 a command substitution in a segment that moves nothing" \
  "cd $T || exit 1; echo \"\$(date +%H:%M) go\" >> p.md; $SUITE" "$T"
placed "F4 the suite redirected to a pinned variable" \
  "cd $T || exit 1; LOG=/tmp/x.log; set -o pipefail; $SUITE > \"\$LOG\" 2>&1; rc=\$?; echo \"rc=\$rc\" >> \"\$LOG\"; exit \$rc" "$T"
placed "F5 a redirection after the cd" \
  "cd $T 2>/dev/null || exit 1; $SUITE" "$T"
placed "F6 a pipe in a note" \
  "cd $T || exit 1; printf -- '- %s red gate (T38-red.log 376/378 | 2 FAIL)\n' x >> p.md; $SUITE" "$T"
# The same six again in the forms the transcripts carried beside them (research §Q5 table).
placed "F7 a real pipe in a segment that moves nothing" \
  "cd $T || exit 1; git status --short | head -3; $SUITE" "$T"
placed "F8 a substitution feeding mkdir" \
  "cd $T || exit 1; mkdir -p \"\$(dirname /tmp/l)\"; $SUITE" "$T"
placed "F9 a python heredoc" \
  "cd $T || exit 1; python3 - <<'EOF'
print(open('p').read().count('(') | 1)
EOF
$SUITE" "$T"
placed "F10 a quoted grep alternation" \
  "cd $T || exit 1; grep -h -A1 \"FAIL: (cause3)\\|FAIL: (x)\" log; $SUITE" "$T"

section "CHAIN — the literal cd chain is followed (bare, quoted, ~, a pinned variable)"
placed "C1 bare absolute, ||" "cd $T || exit 1; $SUITE" "$T"
placed "C2 bare absolute, &&" "cd $T && $SUITE" "$T"
placed "C3 bare absolute, ;" "cd $T; $SUITE" "$T"
placed "C4 bare absolute, newline" "cd $T || exit 1
$SUITE" "$T"
placed "C5 relative, joined to the cwd" "cd ../trees/t1 && $SUITE" "$T"
placed "C6 two cds, the second relative" "cd $SANDBOX/trees; cd t1 || exit 1; $SUITE" "$T"
placed "C7 single-quoted, holding a space" "cd '$SANDBOX/a tree' || exit 1; $SUITE" "$SANDBOX/a tree"
placed "C8 double-quoted with nothing to expand" "cd \"$T\" || exit 1; $SUITE" "$T"
placed "C9 ~/ from HOME" "cd ~/w || exit 1; $SUITE" "$HOME/w"
placed "C10 bare ~" "cd ~ && $SUITE" "$HOME"
placed "C11 bare cd is HOME" "cd && $SUITE" "$HOME"
placed "C12 a variable one literal assignment pins" "D=$T; cd \$D || exit 1; $SUITE" "$T"
placed "C13 …double-quoted" "D=$T; cd \"\$D\" || exit 1; $SUITE" "$T"
placed "C14 a brace group" "{ cd $T || exit 1; $SUITE; }" "$T"
placed "C15 a subshell the cd and the suite share" "(cd $T && $SUITE)" "$T"
placed "C16 a cd behind && runs whenever the suite does" "true && cd $T && $SUITE" "$T"
placed "C17 an unreadable cd, then an absolute one re-anchors" "cd \"\$X\"; cd $T && $SUITE" "$T"
placed "C18 the end-of-options marker" "cd -- $T && $SUITE" "$T"
placed "C19 no move: the cwd" "$SUITE" "$CWD"
placed "C20 only the cds ahead of the target count" "$SUITE; cd $T; $SUITE" "$CWD"
placed "C21 a cd before a subshell the suite runs in" "cd $T || exit 1; ( $SUITE )" "$T"
placed "C22 .. folds" "cd $T/../u2/./ && $SUITE" "$U"
placed "C23 an assignment and a grep ahead of a pinned cd (T38 #297)" \
  "S=$SANDBOX/trees; R=x; grep -c y z; cd \$S/t1 || exit 1; $SUITE" "$T"
placed "C24 the cd's failure branch exits, then a later statement" "cd $T || { echo no; exit 1; }; $SUITE" "$T"

section "MOVING — a move the reader cannot be sure of names its segment, never a guess"
moving "M1 an unpinned variable" "cd \"\$T\" || exit 1; $SUITE" "cd \"\$T\""
moving "M2 a cd in a subshell that closed" "(cd $T; true); $SUITE" "cd $T"
moving "M3 a cd in a pipeline stage" "true | cd $T; $SUITE" "cd $T"
moving "M4 a cd behind ||" "true || cd $T; $SUITE" "cd $T"
moving "M5 pushd" "pushd $T && $SUITE" "pushd $T"
moving "M6 popd" "cd $T; popd; $SUITE" "popd"
moving "M7 a cd as an if condition" "if cd $T; then $SUITE; fi" "if cd $T"
moving "M8 a cd to a substitution" "cd \$(git rev-parse --show-toplevel) && $SUITE" "cd \$(git rev-parse --show-toplevel)"
moving "M9 a cd with an option" "cd -P $T && $SUITE" "cd -P $T"
moving "M10 relative after an unreadable cd" "cd \"\$X\"; cd t1 && $SUITE" "cd \"\$X\""
moving "M11 a cd a failing step may skip" "false && cd $T; $SUITE" "cd $T"
moving "M12 a cd the shell backgrounds" "cd $T & $SUITE" "cd $T"
moving "M13 a cd piped into a command" "cd $T | cat; $SUITE" "cd $T"
moving "M14 a cd behind a branch keyword names its segment as typed" "if true; then cd $T; fi; $SUITE" "then cd $T"
moving "M14b a bare cd inside a branch the suite is not in" "if true; then
cd $T
fi; $SUITE" "cd $T"
moving "M15 a cd behind an assignment prefix" "X=1 cd $T; $SUITE" "X=1 cd $T"
moving "M16 eval cd" "eval cd $T; $SUITE" "eval cd $T"
moving "M17 a loop variable with two values" "for d in $T $U; do cd \$d; $SUITE; done" "do cd \$d"
moving "M17b …a bare cd reading it" "for d in $T $U; do
cd \$d && $SUITE
done" "cd \$d"
moving "M18 cd -" "cd -; $SUITE" "cd -"
moving "M19 a glob" "cd $SANDBOX/trees/t*; $SUITE" "cd $SANDBOX/trees/t*"
moving "M20 two operands" "cd $T $U; $SUITE" "cd $T $U"
moving "M21 the target moves inside its own shell string" "bash -c 'cd $T && $SUITE'" "bash -c 'cd $T && $SUITE'"
moving "M22 ~user" "cd ~nobody; $SUITE" "cd ~nobody"
moving "M23 the target behind the cd's own failure branch" "cd $T || $SUITE" "cd $T"
moving "M24 a negated cd" "! cd $T; $SUITE" "! cd $T"

section "INVISIBLE — quoted text and heredoc bodies move nothing"
placed "I1 a cd inside an echo's quotes" "echo \"cd $U\"; $SUITE" "$CWD"
placed "I2 a cd inside a heredoc body" "cat > n.md <<EOF
cd $U
pushd $U
EOF
$SUITE" "$CWD"
placed "I3 a cd in a commit message" "cd $T && git commit -m \"cd $U; (pushd) | popd\"" "$T" git
placed "I4 a cd inside a substitution moves no shell" "cd $T || exit 1; X=\$(cd $U && pwd); $SUITE" "$T"
placed "I5 the 2 KB quoted body of a python3 -c ahead of the suite" \
  "cd $T || exit 1; python3 -c \"$(printf 'x = (1 | 2); cd %.0s' $(seq 1 120))\"; $SUITE" "$T"

section "TARGET — the segment asked about: suite, a command word, or the end of the command"
placed "G1 a git target" "cd $T && git add x && git commit -m wip" "$T" git
placed "G2 …the command word folds as the machine resolves it" "cd $T && GIT commit -m wip" "$T" git
placed "G3 …through cmd-class's unwrap" "cd $T && env GIT_X=1 git commit -m wip" "$T" git
placed "G4 the first git, not a later one" "git status; cd $T; git commit -m wip" "$CWD" git
place "cd $T; cd $U" "$CWD"
expect_eq "G5 no target: where the shell stands at the end of the command" "$U" "$P_OUT"
expect_status "G5 …exit 0" 0 "$P_RC"
place "cd $T; ls" "$CWD" git
expect_eq "G6 a named target no segment carries prints nothing" "" "$P_OUT"
expect_status "G6 …exit 3" 3 "$P_RC"
place "cd $T; git log" "$CWD" git
expect_eq "G6-positive: the same fixture with the target present is placed" "$T" "$P_OUT"
place "cd $T; ls" "$CWD" suite
expect_status "G7 no suite segment: exit 3" 3 "$P_RC"
expect_eq "G7 …prints nothing" "" "$P_OUT"

section "ARGS — the cwd is required and absolute"
place "$SUITE" ""
expect_status "A1 no cwd: exit 2" 2 "$P_RC"
expect_eq "A1 …prints nothing on stdout" "" "$P_OUT"
place "$SUITE" "rel/dir"
expect_status "A2 a relative cwd: exit 2" 2 "$P_RC"
place "$SUITE" "$CWD/"
expect_eq "A3 the cwd is printed folded (A1/A2's positive)" "$CWD" "$P_OUT"
expect_status "A3 …exit 0" 0 "$P_RC"
place "" "$CWD"
expect_eq "A4 an empty command stands at the cwd" "$CWD" "$P_OUT"

finish
