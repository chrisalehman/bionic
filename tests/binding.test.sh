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
. "$(dirname "$0")/lib/bound-marker.sh"   # unbound_marker — the three "no binding" shapes

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
section "2 — the five refusal causes are told apart (AC-2.2)"
# ============================================================

# The root (a), (d) and (e) refuse on, holding one open plan.
R1="$(make_repo r1)"
P1="$R1/.bionic/docs/plans/epic-01-demo/wave-01.plan.md"

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
section "5 — bind_holders: which OTHER sessions' markers name a plan (wave-23 T13, critic C-3)"
# ============================================================
#
# The reader engagement asks before it guesses a binding (hooks/engage.sh, THE HELD RUN).
# Liveness is the caller's (the sweeper's predicate); this pins only the marker read: the
# other session's binding is found, the caller's own is not, the four "no binding" shapes
# name nothing, a symlinked marker is never followed, and two spellings of one plan agree.
HOLD_ST=0; HOLD_IDS=""
call_holders() {  # <root> <sid> <plan> -> sets HOLD_ST / HOLD_IDS
  local out
  out=$(bash -c '
      set -u
      . "$1" || exit 9
      . "$2" || exit 9
      rc=0
      bind_holders "$3" "$4" "$5" || rc=$?
      printf "%s|%s|" "$rc" "$(printf "%s" "${BIND_HOLDERS:-}" | tr "\n" ",")"
    ' _ "$RUNLIB" "$BINDLIB" "$1" "$2" "$3" 2>/dev/null)
  HOLD_ST="${out%%|*}"
  HOLD_IDS="${out#*|}"; HOLD_IDS="${HOLD_IDS%|}"
}
OSID="0a1b2c3d-1111-4222-8333-444455556666"
TSID="7f6e5d4c-1111-4222-8333-444455556666"
R6="$(make_repo r6)"
P6="$R6/.bionic/docs/plans/epic-01-demo/wave-01.plan.md"
call_holders "$R6" "$SID" "$P6"
expect_eq "no other marker: no holder (exit 1)" "1" "$HOLD_ST"
expect_eq "…and BIND_HOLDERS is empty" "" "$HOLD_IDS"
call_bind "$R6" "$OSID" "$P6"
call_holders "$R6" "$SID" "$P6"
expect_eq "another session bound to the plan holds it (exit 0)" "0" "$HOLD_ST"
expect_eq "…and is named" "$OSID" "$HOLD_IDS"
call_holders "$R6" "$SID" "$R6/.bionic/docs/plans/epic-01-demo/../epic-01-demo/wave-01.plan.md"
expect_eq "…and a second spelling of the same plan finds the same holder" "$OSID" "$HOLD_IDS"
call_holders "$R6" "$OSID" "$P6"
expect_eq "a session never holds a run against itself" "1" "$HOLD_ST"
call_bind "$R6" "$SID" "$P6"
call_holders "$R6" "$OSID" "$P6"
expect_eq "…while the other direction names the other session" "$SID" "$HOLD_IDS"
call_bind "$R6" "$SID" none
for shape in none empty nofield; do
  unbound_marker "$R6" "$OSID" "$shape"
  call_holders "$R6" "$SID" "$P6"
  expect_eq "an other marker of shape '$shape' holds nothing" "1" "$HOLD_ST"
done
printf 'plan=%s\nengaged_at=2026-10-02T00:00:00Z\n' "$P6" > "$SANDBOX/linked.state"
ln -s "$SANDBOX/linked.state" "$R6/.bionic/tmp/engaged-$TSID.state"
call_holders "$R6" "$SID" "$P6"
expect_eq "a SYMLINKED marker naming the plan is never followed" "1" "$HOLD_ST"
rm -f "$R6/.bionic/tmp/engaged-$TSID.state"
call_bind "$R6" "$TSID" "$P6"
call_holders "$R6" "$SID" "$P6"
expect_eq "…paired: the same id as a real marker holds it" "$TSID" "$HOLD_IDS"

# ============================================================
section "7 — the bind verb's act admits a delivered plan: the session reads it bound-closed (wave-36 T14; D13, AC-7.7; ruling r1791955629-34788)"
# ============================================================
#
# `task-set --reason` amends a delivered plan from the session bound to it, and after a close-out the session has no
# marker, so `bind` must be able to reach that state. Only the bind VERB's act (`bind`) admits a delivered plan;
# engagement (`engage`), the governing skill's Write (`write`) and an act-less call keep §2's refusal, so the
# newest-plan fallback and engagement are unchanged. A plan neither open nor delivered (abandoned) is still refused.
call_bind_act() {  # <root> <sid> <plan|none> <act> -> sets BIND_ST / BIND_WHY / BIND_ERR / BIND_RUN (session_run after)
  local out
  out=$(bash -c '
      set -u
      . "$1" || exit 9
      . "$2" || exit 9
      rc=0
      bind_plan "$3" "$4" "$5" "$6" || rc=$?
      printf "%s|%s|%s|" "$rc" "${BIND_REFUSAL:-}" "$(session_run "$3" "$4" 2>/dev/null)"
    ' _ "$RUNLIB" "$BINDLIB" "$1" "$2" "$3" "$4" 2>"$SANDBOX/.err")
  BIND_ST="${out%%|*}"; out="${out#*|}"
  BIND_WHY="${out%%|*}"; out="${out#*|}"
  BIND_RUN="${out%|}"
  BIND_ERR=$(cat "$SANDBOX/.err" 2>/dev/null)
}
R7="$(make_repo r7)"
P7="$R7/.bionic/docs/plans/epic-01-demo/wave-01.plan.md"
D7="$R7/.bionic/docs/plans/epic-01-demo/wave-02-delivered.plan.md"
closed_body > "$D7"
A7="$R7/.bionic/docs/plans/epic-01-demo/wave-03-abandoned.plan.md"
printf -- '---\ncanonical_sdlc_version: 14\nabandoned: 2026-10-01 superseded\n---\n\n## SDLC State\n\ncurrent: 4\n\n- Step 4: in flight\n' > "$A7"
call_bind_act "$R7" "$SID" "$P7" bind
expect_eq "7a paired positive: the root's open plan binds by the verb's act, bound-open" "0||bound-open $P7" "$BIND_ST|$BIND_WHY|$BIND_RUN"
call_bind_act "$R7" "$SID" "$D7" bind
expect_eq "7b the bind verb's act binds a DELIVERED plan of the root (exit 0, no refusal)" "0|" "$BIND_ST|$BIND_WHY"
expect_eq "…the marker names it" "plan=$D7" "$(grep -m1 '^plan=' "$(marker_of "$R7")")"
expect_eq "…and the session reads it bound-closed" "bound-closed $D7" "$BIND_RUN"
call_bind_act "$R7" "$SID" "$A7" bind
expect_eq "7c an ABANDONED plan, neither open nor delivered, is still refused not-an-open-run" "1|not-an-open-run" "$BIND_ST|$BIND_WHY"
expect_eq "…the marker still names the delivered plan" "plan=$D7" "$(grep -m1 '^plan=' "$(marker_of "$R7")")"
for act in engage write; do
  call_bind_act "$R7" "$SID" "$P7" bind
  call_bind_act "$R7" "$SID" "$D7" "$act"
  expect_eq "7d the $act act keeps the refusal on a delivered plan (not-an-open-run), the marker unchanged" "1|not-an-open-run|plan=$P7" \
    "$BIND_ST|$BIND_WHY|$(grep -m1 '^plan=' "$(marker_of "$R7")")"
done
OTHER7="$(make_repo r7-other)"
closed_body > "$OTHER7/.bionic/docs/plans/epic-01-demo/wave-02-delivered.plan.md"
call_bind_act "$R7" "$SID" "$OTHER7/.bionic/docs/plans/epic-01-demo/wave-02-delivered.plan.md" bind
expect_eq "7e a delivered plan of ANOTHER root is refused not-an-open-run" "1|not-an-open-run" "$BIND_ST|$BIND_WHY"

# ============================================================
section "SIZE — a plan carrying 3,000 session lines binds once as present, and a session not on it is recorded exactly once"
# ============================================================
#
# `bind_record_session` asks `bind_sessions` whether the line of this session is already there. A reader that quits at the
# first match leaves the writer a closed pipe, and under `set -o pipefail`, which every caller of the library runs under, a
# writer killed that way fails the pipeline and a session already on the plan reads absent: the call answers `recorded`
# and the plan gains a second line. `bind_sessions` ends in `return 0`, which masks its own writer, so the quitting form
# does not bite through it on this library; the presence read still reads to the end, so that no change to that function
# can make it bite. The rows build a plan whose id stream (over 100 KB) outruns one 64 KB pipe buffer, with the line of
# this session FIRST, where an early quit happens, and SZ-3 shows this plan is one a quitting reader bites on.
# fails-when: the presence read quits early, the call answers recorded and the plan gains a second line (SZ-1).
sz_plan() {  # <path> <with|without> -> a plan of 3,000 distinct session lines, the line of this session first when "with"
  {
    printf -- '---\ncanonical_sdlc_version: 14\n---\n\n## SDLC State\n\ncurrent: 4\n\n- Step 4: in flight\n'
    [ "$2" = with ] && printf -- '- session: %s bound 2026-10-01T00:00:00Z by engage\n' "$SID"
    awk 'BEGIN { for (i = 1; i <= 3000; i++) printf "- session: %08d-0000-4000-8000-000000000000 bound 2026-10-01T00:00:00Z by bind\n", i }'
    printf '\n## Notes\n\nafter the state.\n'
  } > "$1"
}
sz_call() {  # <bindlib> <plan> <act> -> prints "<rc>|<BIND_SESSION>|" from one call, under pipefail as the callers run
  bash -c '
      set -uo pipefail
      . "$1" || exit 9
      . "$2" || exit 9
      rc=0
      bind_record_session "$3" "$4" "$5" || rc=$?
      printf "%s|%s|" "$rc" "${BIND_SESSION:-}"
    ' _ "$RUNLIB" "$1" "$2" "$SID" "$3" 2>/dev/null
}
sz_count() { grep -c -- "^- session: $SID " "$1"; }

SZ="$SANDBOX/size"; mkdir -p "$SZ"
sz_plan "$SZ/with.plan.md" with
expect_eq "SZ-1 the plan is over 64 KB (the writer cannot fit one pipe buffer)" "yes" \
  "$([ "$(wc -c < "$SZ/with.plan.md")" -gt 65536 ] && echo yes || echo no)"
expect_eq "SZ-1 the plan carries the line of this session once, among 3,000 session lines" "1|3001" \
  "$(sz_count "$SZ/with.plan.md")|$(grep -c '^- session: ' "$SZ/with.plan.md")"
cp "$SZ/with.plan.md" "$SZ/with.before"
expect_eq "SZ-1 a session already on a 3,000-line plan binds once as present: exit 1, BIND_SESSION present" "1|present|" \
  "$(sz_call "$BINDLIB" "$SZ/with.plan.md" bind)"
expect_true "SZ-1 …and the plan is byte-identical after" cmp -s "$SZ/with.plan.md" "$SZ/with.before"

sz_plan "$SZ/without.plan.md" without
expect_eq "SZ-2 control: the same plan without a line for this session carries none" "0|3000" \
  "$(sz_count "$SZ/without.plan.md")|$(grep -c '^- session: ' "$SZ/without.plan.md")"
expect_eq "SZ-2 a session not on the plan is recorded: exit 0, BIND_SESSION recorded" "0|recorded|" \
  "$(sz_call "$BINDLIB" "$SZ/without.plan.md" bind)"
expect_eq "SZ-2 …a second call over the same plan answers present" "1|present|" \
  "$(sz_call "$BINDLIB" "$SZ/without.plan.md" bind)"
expect_eq "SZ-2 …so the plan gained exactly one line, that of this session, over the two calls" "1|3001" \
  "$(sz_count "$SZ/without.plan.md")|$(grep -c '^- session: ' "$SZ/without.plan.md")"

# SZ-3: a quitting reader over the raw id stream, put into a copy of the library, turns SZ-1's answer into `recorded`. The
# mutant is proved to differ from the library and to carry that reader before its answer is read, so a sed that matched
# nothing cannot pass for a mutant that was caught; the same plan, read to the end, binds as present in SZ-1.
SZ_MUT="$SZ/binding-mutant.sh"
sed 's/^  case "\$nl\$ids\$nl" in .*$/  if _bind_session_ids "$plan" | grep -qxF -- "$sid"; then BIND_SESSION="present"; return 1; fi/' "$BINDLIB" > "$SZ_MUT"
expect_eq "SZ-3 the mutant carries the quitting reader over the id stream once" "1" \
  "$(grep -c 'if _bind_session_ids "\$plan" | grep -qxF -- "\$sid"; then BIND_SESSION="present"' "$SZ_MUT")"
expect_true "SZ-3 …and the mutant parses" bash -n "$SZ_MUT"
cp "$SZ/with.before" "$SZ/mutant.plan.md"
expect_eq "SZ-3 the quitting reader answers recorded on the plan SZ-1 binds as present" "0|recorded|" \
  "$(sz_call "$SZ_MUT" "$SZ/mutant.plan.md" bind)"
expect_eq "SZ-3 …and the plan gains the second line" "2" "$(sz_count "$SZ/mutant.plan.md")"

finish
