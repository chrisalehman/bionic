#!/bin/bash
# tests/binding.test.sh — payload/scripts/lib/binding.sh: WHICH refusal, not just that
# there was one (epic-23 wave-18-fixit-185, REQ-2 AC-2.2; spec §2 D5).
#
# WHAT IT OWNS. `bind_plan` has five refusal causes and one exit status for all of them,
# so every caller that wanted to say why had to re-derive the reason from the filesystem
# afterwards — hooks/session-poker.sh:3203 does exactly that, in a comment that calls the
# re-derivation "POSITIONAL". The PostToolUse bind arm cannot re-derive anything: by the
# time it is running the tool has already written the file, and the reason it declined is
# the only thing the operator wants. So the library names the refusal in `BIND_REFUSAL`,
# and this suite is what keeps the five names distinct and attached to the right cause.
#
# WHY A VARIABLE AND NOT FIVE EXIT CODES (A-T3.1, and the reason it is written down here
# rather than only in the wave record). Two files outside this task's scope read the
# status numerically and would invert on a widened set:
#   - tests/engage.test.sh §E8 (f)(g)(g2)(h) pins `exit 1` for four of the five causes;
#   - hooks/session-poker.sh:3199 reads `BIND_RC -ge 2` as "the marker write failed",
#     so any code above 2 would report a valid refusal as a broken tree.
# The status contract is therefore unchanged — 0 written · 1 refused · 2 write failed —
# and the distinction rides beside it. AC-2.2's eval reads "four distinct codes/messages".
#
# HERMETIC. Every root is a fixture under one mktemp sandbox; HOME is redirected into it
# and the library is sourced in a CHILD shell per row, so no row can be answered by state
# an earlier row left in this one.
#
# Usage: bash tests/binding.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
LIB_DIR="$REPO_ROOT/payload/scripts/lib"
RUNLIB="$LIB_DIR/run.sh"
BINDLIB="$LIB_DIR/binding.sh"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/binding-test.XXXXXX")" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

export HOME="$SANDBOX/home"
mkdir -p "$HOME"
unset CLAUDE_CODE_SESSION_ID

SID="5e4d3c2b-1a09-4876-9b5c-4d3e2f1a0b9c"

# ---------- the driver ----------
#
# `set -u` inside the child on purpose: every caller of bind_plan is a hook that runs
# under it, and an unbound `BIND_REFUSAL` there would take the hook down at the line that
# reads the reason. The child prints the status and the reason on one line so a row reads
# both from one call and cannot pair a status with another call's reason.
BIND_ST=0; BIND_WHY=""; BIND_ERR=""
call_bind() {  # <root> <sid> <plan|none> -> sets BIND_ST / BIND_WHY / BIND_ERR
  local out
  out=$(bash -c '
      set -u
      . "$1" || exit 9
      . "$2" || exit 9
      rc=0
      bind_plan "$3" "$4" "$5" || rc=$?
      printf "%s|%s|" "$rc" "${BIND_REFUSAL:-}"
    ' _ "$RUNLIB" "$BINDLIB" "$1" "$2" "$3" 2>"$SANDBOX/.err")
  # ONE LINE, TWO FIELDS, AND A TRAILING DELIMITER. Command substitution eats trailing
  # newlines, so a two-LINE answer whose second field is empty collapses into one line and
  # both fields read as the status — the shape that makes a RED row look green.
  BIND_ST="${out%%|*}"
  BIND_WHY="${out#*|}"; BIND_WHY="${BIND_WHY%|}"
  BIND_ERR=$(cat "$SANDBOX/.err" 2>/dev/null)
}

open_body()   { printf -- '---\ncanonical_sdlc_version: 14\n---\n\n## SDLC State\n\ncurrent: 4\n\n- Step 4: in flight\n'; }
closed_body() { printf -- '---\ncanonical_sdlc_version: 14\n---\n\n## SDLC State\n\ncurrent: 9\n\n- Step 9: close-out delivered: yes\n'; }

make_repo() {  # <name> -> an engaged-looking root holding one OPEN plan
  local d="$SANDBOX/$1"
  mkdir -p "$d/.bionic/docs/plans/epic-01-demo" "$d/.bionic/tmp"
  git -C "$d" init -q . 2>/dev/null
  open_body > "$d/.bionic/docs/plans/epic-01-demo/wave-01.plan.md"
  printf '%s' "$d"
}

marker_of() { printf '%s' "$1/.bionic/tmp/engaged-$SID.state"; }

# ============================================================
section "1 — the accepted bindings still answer 0 and name no refusal"
# ============================================================
#
# EVERY REFUSAL ROW BELOW SITS BESIDE A POSITIVE ON THE SAME ROOT, one argument apart
# (tests/engage.test.sh §E8's rule, kept): a suite whose fixtures cannot bind at all
# would pass every refusal row for the wrong reason.

R1="$(make_repo r1)"
P1="$R1/.bionic/docs/plans/epic-01-demo/wave-01.plan.md"
call_bind "$R1" "$SID" "$P1"
expect_eq "an open plan of the root binds (exit 0)" "0" "$BIND_ST"
expect_eq "…and names no refusal" "" "$BIND_WHY"
expect_eq "…and prints nothing on stderr" "" "$BIND_ERR"
expect_eq "…and the marker names the plan" "plan=$P1" "$(grep -m1 '^plan=' "$(marker_of "$R1")")"

call_bind "$R1" "$SID" "none"
expect_eq "the literal none binds (exit 0)" "0" "$BIND_ST"
expect_eq "…and names no refusal" "" "$BIND_WHY"

# ============================================================
section "2 — the five refusal causes are told apart (AC-2.2)"
# ============================================================

# (a) :78 — the sid the reader refuses is the sid the writer refuses.
call_bind "$R1" "a b" "$P1"
expect_eq "a misshapen sid refuses (exit 1)" "1" "$BIND_ST"
expect_eq "…and names the sid" "sid" "$BIND_WHY"
WHY_SID="$BIND_WHY"

# (b) :89 — `.bionic` or `.bionic/tmp` on the marker's own path is a symlink.
R2="$(make_repo r2)"
P2="$R2/.bionic/docs/plans/epic-01-demo/wave-01.plan.md"
mv "$R2/.bionic/tmp" "$SANDBOX/elsewhere-tmp"
ln -s "$SANDBOX/elsewhere-tmp" "$R2/.bionic/tmp"
call_bind "$R2" "$SID" "$P2"
expect_eq "a symlinked .bionic/tmp refuses (exit 1)" "1" "$BIND_ST"
expect_eq "…and names the marker's directory" "marker-dir-symlink" "$BIND_WHY"
WHY_DIR="$BIND_WHY"
expect_eq "…and wrote nothing through the link" "0" \
  "$(find "$SANDBOX/elsewhere-tmp" -name 'engaged-*.state' 2>/dev/null | wc -l | tr -d ' ')"
rm -f "$R2/.bionic/tmp"; mv "$SANDBOX/elsewhere-tmp" "$R2/.bionic/tmp"
call_bind "$R2" "$SID" "$P2"
expect_eq "…paired: with the link undone the same call writes (exit 0)" "0" "$BIND_ST"

# (c) :95 — the marker file itself is a symlink.
R3="$(make_repo r3)"
P3="$R3/.bionic/docs/plans/epic-01-demo/wave-01.plan.md"
printf 'plan=none\nengaged_at=2016-01-01T00:00:00Z\n' > "$SANDBOX/decoy.state"
ln -s "$SANDBOX/decoy.state" "$(marker_of "$R3")"
call_bind "$R3" "$SID" "$P3"
expect_eq "a symlinked marker path refuses (exit 1)" "1" "$BIND_ST"
expect_eq "…and names the marker" "marker-symlink" "$BIND_WHY"
WHY_LINK="$BIND_WHY"
expect_eq "…and did not write through it" "plan=none" "$(grep -m1 '^plan=' "$SANDBOX/decoy.state")"
rm -f "$(marker_of "$R3")"
call_bind "$R3" "$SID" "$P3"
expect_eq "…paired: with the link removed the same call writes (exit 0)" "0" "$BIND_ST"

# (d) :110 — the plan path does not resolve at all (relative, or a directory that is gone).
call_bind "$R1" "$SID" ".bionic/docs/plans/epic-01-demo/wave-01.plan.md"
expect_eq "a relative plan path refuses (exit 1)" "1" "$BIND_ST"
expect_eq "…and names the resolution" "unresolvable" "$BIND_WHY"
WHY_RES="$BIND_WHY"
call_bind "$R1" "$SID" "$R1/.bionic/docs/plans/no-such-epic/wave-01.plan.md"
expect_eq "…and so does a path whose directory does not exist" "unresolvable" "$BIND_WHY"

# (e) :117 — the path resolves, and is simply not a member of the open-run set.
CLOSED="$R1/.bionic/docs/plans/epic-01-demo/wave-09-closed.plan.md"
closed_body > "$CLOSED"
call_bind "$R1" "$SID" "$CLOSED"
expect_eq "a CLOSED plan of this root refuses (exit 1)" "1" "$BIND_ST"
expect_eq "…and names the open-run set" "not-an-open-run" "$BIND_WHY"
WHY_SET="$BIND_WHY"
OTHER="$(make_repo r4)"
call_bind "$R1" "$SID" "$OTHER/.bionic/docs/plans/epic-01-demo/wave-01.plan.md"
expect_eq "…and so does an open plan of ANOTHER root" "not-an-open-run" "$BIND_WHY"
NOTPLAN="$R1/.bionic/docs/plans/epic-01-demo/notes.md"
printf '# just notes\n' > "$NOTPLAN"
call_bind "$R1" "$SID" "$NOTPLAN"
expect_eq "…and so does a file under plans/ carrying no ## SDLC State" "not-an-open-run" "$BIND_WHY"
call_bind "$R1" "$SID" "$P1"
expect_eq "…paired: the root's open plan on the same fixture is accepted (exit 0)" "0" "$BIND_ST"

# (f) THE POINT OF THE WHOLE SECTION: no two causes answer the same word. A set built
# from the five and counted is the assertion — a pair that collided would shrink it.
DISTINCT=$(printf '%s\n' "$WHY_SID" "$WHY_DIR" "$WHY_LINK" "$WHY_RES" "$WHY_SET" | sort -u | wc -l | tr -d ' ')
expect_eq "the five refusal causes answer five distinct names" "5" "$DISTINCT"
expect_eq "…and none of them is empty" "0" \
  "$(printf '%s\n' "$WHY_SID" "$WHY_DIR" "$WHY_LINK" "$WHY_RES" "$WHY_SET" | grep -c '^$' | tr -d ' ')"

# ============================================================
section "3 — a broken tree is still a different answer from a refusal"
# ============================================================
#
# Exit 2 is the write failing, not the caller being wrong, and hooks/session-poker.sh
# reads `-ge 2` as exactly that. The reason still gets a name so an operator is not left
# guessing which of the two happened.

R5="$(make_repo r5)"
P5="$R5/.bionic/docs/plans/epic-01-demo/wave-01.plan.md"
rm -rf "$R5/.bionic/tmp"
mkdir -p "$(marker_of "$R5")"          # a DIRECTORY where the marker file belongs
call_bind "$R5" "$SID" "$P5"
expect_eq "a marker path that cannot be written is exit 2" "2" "$BIND_ST"
expect_eq "…and names the write" "write-failed" "$BIND_WHY"
rmdir "$(marker_of "$R5")"
call_bind "$R5" "$SID" "$P5"
expect_eq "…paired: with the obstruction gone the same call writes (exit 0)" "0" "$BIND_ST"

# ============================================================
section "4 — the reason never survives a later call (AC-2.2 fails-when)"
# ============================================================
#
# A stale reason is worse than none: the arm that reads it would name the PREVIOUS
# decline as the reason for this one. `bind_plan` clears it on entry.

call_bind "$R1" "$SID" "$P1"
expect_eq "a success after a refusal leaves no reason behind" "" "$BIND_WHY"

finish
