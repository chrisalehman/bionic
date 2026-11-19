#!/bin/bash
# tests/binding.test.sh — payload/scripts/lib/binding.sh: WHICH refusal, not just that there was one.
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

# page15 <plan> <step> [line end] -> a plan page at 15 under plans/ or incidents/ and its run's log,
# <docs>/record/<stem>/run.log, at <step>: open below 9, delivered at 9. A plan at 15 holds no state section; its
# header says 15 and its log where it stands.
page15() {
  local l="${1%/plans/*}"; l="${l%/incidents/*}/record/$(basename "$1" .plan.md)/run.log"
  mkdir -p "${1%/*}" "${l%/*}"
  printf -- "---${3:-\n}canonical_sdlc_version: 15${3:-\n}---${3:-\n}" > "$1"
  printf 'run/v1|ev=step|n=%s|at=2026-10-04T00:00:00Z\n' "$2" > "$l"
}

make_repo() {  # <name> -> an engaged-looking root holding one OPEN plan
  local d="$SANDBOX/$1"
  mkdir -p "$d/.bionic/tmp"
  git -C "$d" init -q . 2>/dev/null
  page15 "$d/.bionic/docs/plans/epic-01-demo/wave-01.plan.md" 4
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
page15 "$CLOSED" 9
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
expect_eq "…and so does a file under plans/ carrying neither a state section nor a header at 15" "not-an-open-run" "$BIND_WHY"
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
# A session reads a delivered plan bound-closed once it binds it, and after a close-out the session has no
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
page15 "$D7" 9
A7="$R7/.bionic/docs/plans/epic-01-demo/wave-03-abandoned.plan.md"
page15 "$A7" 4; printf 'run/v1|ev=abandon|why=superseded|at=2026-10-04T00:01:00Z\n' >> "$R7/.bionic/docs/record/wave-03-abandoned/run.log"
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
page15 "$OTHER7/.bionic/docs/plans/epic-01-demo/wave-02-delivered.plan.md" 9
call_bind_act "$R7" "$SID" "$OTHER7/.bionic/docs/plans/epic-01-demo/wave-02-delivered.plan.md" bind
expect_eq "7e a delivered plan of ANOTHER root is refused not-an-open-run" "1|not-an-open-run" "$BIND_ST|$BIND_WHY"

# ============================================================
section "8 — the run's sessions are events: a first engagement is one bind event, a session the run holds adds none, the plan is never written"
# ============================================================
#
# `bind_record_session` asks the reader which sessions the run holds and appends a bind event, through the one writer,
# for a session it lacks. FIXTURE FIDELITY: a fresh root's open plan bound by engagement's act twice; then a run whose
# log carries 3,000 bind events (over 100 KB, past one 64 KB pipe buffer), this session's event first, where a reader
# that quit early would read it absent. fails-when: an engagement writes the plan, a held session is appended again, or
# a session missing from 3,000 is not appended once.
rlog() { cat "$1" 2>/dev/null | awk -v s="|session=$SID|" -v b="|by=$2|" 'index($0, "run/v1|ev=bind|") == 1 && index($0, s) && index($0, b) { n++ } END { print n + 0 }'; }  # <log> <act> -> this session's bind events by that act
R8="$(make_repo r8)"; P8="$R8/.bionic/docs/plans/epic-01-demo/wave-01.plan.md"; S8="$(cksum < "$P8")"
call_bind_act "$R8" "$SID" "$P8" engage; A8="$BIND_ST"; call_bind_act "$R8" "$SID" "$P8" engage
expect_eq "8a a first engagement binds (exit 0) and is one bind event by engage; a second adds none; the plan's sum is unchanged" \
  "0|0|1|$S8" "$A8|$BIND_ST|$(rlog "$R8/.bionic/docs/record/wave-01/run.log" engage)|$(cksum < "$P8")"
sz_plan() {  # <name> <with|without> -> a page at 15 whose run's log holds 3,000 distinct bind events, the event of this session first when "with"
  local p="$SZ/.bionic/docs/plans/epic-01-demo/$1.plan.md"
  page15 "$p" 4
  { [ "$2" = with ] && printf 'run/v1|ev=bind|session=%s|by=engage|at=2026-10-01T00:00:00Z\n' "$SID"
    awk 'BEGIN { for (i = 1; i <= 3000; i++) printf "run/v1|ev=bind|session=%08d-0000-4000-8000-000000000000|by=bind|at=2026-10-01T00:00:00Z\n", i }'; } >> "$SZ/.bionic/docs/record/$1/run.log"
  printf '%s' "$p"
}
sz_call() {  # <plan> -> "<rc>|<BIND_SESSION>" from one call, under pipefail and set -u as the callers run, the reader loaded and its translation not
  bash -c 'set -uo pipefail; . "$1" || exit 9; . "$2" || exit 9; . "${1%/*}/reader.sh" || exit 9; rc=0; bind_record_session "$3" "$4" bind || rc=$?; printf "%s|%s" "$rc" "${BIND_SESSION:-}"' \
    _ "$RUNLIB" "$BINDLIB" "$1" "$SID" 2>/dev/null
}
SZ="$SANDBOX/size"; SZW="$(sz_plan with with)"; SZO="$(sz_plan without without)"; SZS="$(cksum < "$SZW")|$(cksum < "$SZO")"
expect_eq "8b the run's log is over 64 KB and carries the bind event of this session once, among 3,001 bind events" "yes|1|3001" \
  "$([ "$(wc -c < "$SZ/.bionic/docs/record/with/run.log")" -gt 65536 ] && echo yes)|$(grep -c -- "^run/v1|ev=bind|session=$SID|" "$SZ/.bionic/docs/record/with/run.log")|$(grep -c '^run/v1|ev=bind|' "$SZ/.bionic/docs/record/with/run.log")"
expect_eq "8c a session the run holds is present (exit 1) and appends nothing; one it lacks is recorded (exit 0), then present" \
  "1|present 0|recorded 1|present" "$(sz_call "$SZW") $(sz_call "$SZO") $(sz_call "$SZO")"
expect_eq "8d …one bind event of this session for the run that lacked it, none for the other; neither plan written" "0|1|$SZS" \
  "$(rlog "$SZ/.bionic/docs/record/with/run.log" bind)|$(rlog "$SZ/.bionic/docs/record/without/run.log" bind)|$(cksum < "$SZW")|$(cksum < "$SZO")"

# ============================================================
section "9 — a page at 15 is a run: the walk finds it, engagement binds it, an unbound session falls back to it"
# ============================================================
#
# A plan at 15 holds no state section: its header says 15 and its run's log says where it stands. The walk keeps its
# two protections at 15: a header inside a fenced block is prose, and a page whose lines end in a bare CR still has
# lines. A page whose header does not say 15 is judged by its state section, as before.
# fails-when: an open page at 15 is missing from the open-run set, refused by engagement or not the unbound fallback;
# or a fenced header, or a page at 14 with no state section, is listed.
R9="$(make_repo r9)"; D9="$R9/.bionic/docs/plans/epic-01-demo"
page15 "$D9/wave-02-cr.plan.md" 4 '\r'; page15 "$D9/wave-03-fenced.plan.md" 4; page15 "$D9/wave-04.plan.md" 4
printf '# notes\n```\n---\ncanonical_sdlc_version: 15\n---\n```\n' > "$D9/wave-03-fenced.plan.md"
printf -- '---\ncanonical_sdlc_version: 14\n---\n' > "$D9/wave-04.plan.md"
expect_eq "9a the walk lists the open page at 15 and the CR-only one; not the fenced header, nor the page at 14 with no state section" \
  "wave-01.plan.md wave-02-cr.plan.md" "$(bash -c '. "$1"; open_runs "$2"' _ "$RUNLIB" "$R9" 2>/dev/null | sed 's#.*/##' | sort | paste -sd' ' -)"
call_bind_act "$R9" "$SID" "$D9/wave-01.plan.md" engage
expect_eq "9b engagement binds the page at 15 (exit 0, no refusal) and the session reads it bound-open" "0||bound-open $D9/wave-01.plan.md" "$BIND_ST|$BIND_WHY|$BIND_RUN"
R9U="$(make_repo r9u)"
unbound_marker "$R9U" "$SID"
expect_eq "9c an unbound session reads the root's one page at 15 as its fallback" "fallback $R9U/.bionic/docs/plans/epic-01-demo/wave-01.plan.md" \
  "$(bash -c '. "$1"; session_run "$2" "$3"' _ "$RUNLIB" "$R9U" "$SID" 2>/dev/null)"

# An incident lays its run out in a directory of its own, its plan named for the directory; at 15 the walk finds it
# as it finds a wave's, so engagement binds it and the commit gate judges a commit under it on what its step owes.
# A plan named plain at 15 joins no record of its own and is no run. fails-when: the walk admits a page at 15 under
# plans/ alone, so the incident is missing from the open-run set, its engagement is refused, and a commit under it is
# judged on another run's plan or on none.
R9I="$(make_repo r9i)"; I9="$R9I/.bionic/docs/incidents/0002-db-outage"
page15 "$I9/0002-db-outage.plan.md" 4; page15 "$R9I/.bionic/docs/incidents/0003-plain/plan.md" 4
expect_eq "9d the walk lists an incident's page at 15 named for its directory beside the wave's; not one named plain" \
  "0002-db-outage.plan.md wave-01.plan.md" "$(bash -c '. "$1"; open_runs "$2"' _ "$RUNLIB" "$R9I" 2>/dev/null | sed 's#.*/##' | sort | paste -sd' ' -)"
call_bind_act "$R9I" "$SID" "$I9/0002-db-outage.plan.md" engage
expect_eq "9e engagement binds the incident's page at 15 (exit 0, no refusal) and the session reads it bound-open" \
  "0||bound-open $I9/0002-db-outage.plan.md" "$BIND_ST|$BIND_WHY|$BIND_RUN"
git -C "$R9I" -c user.name=f -c user.email=f@x.invalid -c commit.gpgsign=false commit -q --allow-empty -m seed
G9="$(cd "$R9I" && jq -n --arg c "git commit -m x" --arg cwd "$R9I" --arg s "$SID" '{session_id:$s, tool_input:{command:$c}, cwd:$cwd}' \
  | HOME="$R9I" CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$SID" BIONIC_WALL_VERBOSE=1 bash "$REPO_ROOT/hooks/bash-walls.sh" 2>&1; printf '|rc=%s' "$?")"
expect_contains "9f a commit under the bound incident is refused (exit 2)" "|rc=2" "$G9"
expect_contains "…judged on the incident's own plan" "incidents/0002-db-outage/0002-db-outage.plan.md" "$G9"
expect_contains "…for a fact its step truly owes: the Step-3 approval that admits Step 4" "the log holds no Step-3 approval" "$G9"


# ============================================================
section "10 — the binding record beside the seal: written by bind_plan on every binding, to none too"
# ============================================================
#
# Which plan a session is bound to is recorded in the seal's home — `<common git dir>/bionic-seal/`,
# where the project's own tools do not reach — and `session_plan` believes it over the engaged file.
# One file a session and state folder: `<sid>.<cksum of the resolved .bionic>.binding`, four lines.
# FIXTURE FIDELITY: git roots built here; the record is read off disk, never through the reader under
# test, except where the row is the reader's. fails-when: a binding leaves no record, a refused one
# moves it, a root with no repository grows a home, two state folders of one repository share a
# record, a worktree reads another, or a record that cannot be written is reported as written.
rec_of() {  # <root> -> the one binding record of $SID under the root's seal home, or nothing
  local f n=0 got=""
  for f in "$1/.git/bionic-seal/$SID".*.binding; do [ -f "$f" ] && { n=$((n + 1)); got="$f"; }; done
  [ "$n" -eq 1 ] && printf '%s' "$got"
}
plan_read() {  # <root> <sid> -> "<rc>|<session_plan's answer>"
  bash -c '. "$1" || exit 9; v=$(session_plan "$2" "$3"); printf "%s|%s" "$?" "$v"' _ "$RUNLIB" "$1" "$2" 2>/dev/null
}

R10="$(make_repo r10)"; P10="$R10/.bionic/docs/plans/epic-01-demo/wave-01.plan.md"
page15 "$R10/.bionic/docs/plans/epic-02-demo/wave-02.plan.md" 4; Q10="$R10/.bionic/docs/plans/epic-02-demo/wave-02.plan.md"
call_bind "$R10" "$SID" "$P10"
expect_eq "10a bind_plan to an open plan exits 0" "0|" "$BIND_ST|$BIND_WHY"
REC10="$(rec_of "$R10")"
expect_true "…and leaves one record for the session in the seal's home" test -n "$REC10"
expect_eq "…in the four-line layout, naming the session, its state folder and the plan" \
  "$(printf 'binding/v1\nsession=%s\nstate=%s/.bionic\nplan=%s' "$SID" "$R10" "$P10")" "$(cat "$REC10" 2>/dev/null)"

call_bind "$R10" "$SID" none
expect_eq "10b a binding to none exits 0" "0|" "$BIND_ST|$BIND_WHY"
expect_eq "…and rewrites the same record to plan=none" "$REC10|plan=none" "$(rec_of "$R10")|$(sed -n 4p "$REC10" 2>/dev/null)"

call_bind "$R10" "$SID" "$R10/.bionic/docs/plans/no-such.plan.md"
expect_eq "10c a refused binding exits 1" "1|not-an-open-run" "$BIND_ST|$BIND_WHY"
expect_eq "…and leaves the record as it was" "plan=none" "$(sed -n 4p "$REC10" 2>/dev/null)"

call_bind "$R10" "$SID" "$Q10"
expect_eq "10d a change of binding moves the record" "0|plan=$Q10" "$BIND_ST|$(sed -n 4p "$REC10" 2>/dev/null)"
printf 'plan=%s\nengaged_at=2026-10-04T00:00:00Z\n' "$P10" > "$(marker_of "$R10")"
expect_eq "…and session_plan believes it over an engaged file naming the other plan" "0|$Q10" "$(plan_read "$R10" "$SID")"

R10N="$SANDBOX/r10-nogit"; mkdir -p "$R10N/.bionic/tmp"; page15 "$R10N/.bionic/docs/plans/epic-01-demo/wave-01.plan.md" 4
call_bind "$R10N" "$SID" "$R10N/.bionic/docs/plans/epic-01-demo/wave-01.plan.md"
expect_eq "10e in a root with no repository the binding is written (exit 0)" \
  "0|plan=$R10N/.bionic/docs/plans/epic-01-demo/wave-01.plan.md" "$BIND_ST|$(sed -n 1p "$(marker_of "$R10N")")"
expect_eq "…and no seal home is made for it" "" "$(find "$R10N" -name bionic-seal 2>/dev/null)"

# TWO STATE FOLDERS IN ONE REPOSITORY: one session id, two roots, two records.
R10S="$R10/sub"; mkdir -p "$R10S/.bionic/tmp"; page15 "$R10S/.bionic/docs/plans/epic-01-demo/wave-01.plan.md" 4
call_bind "$R10S" "$SID" "$R10S/.bionic/docs/plans/epic-01-demo/wave-01.plan.md"
printf 'plan=none\n' > "$(marker_of "$R10S")"; printf 'plan=none\n' > "$(marker_of "$R10")"
expect_eq "10f one session in two roots of one repository: each root reads its own record" \
  "0|$R10S/.bionic/docs/plans/epic-01-demo/wave-01.plan.md 0|$Q10" "$(plan_read "$R10S" "$SID") $(plan_read "$R10" "$SID")"

# A LINKED WORKTREE whose state folder is the main checkout's (a writer's tree) reads the main
# checkout's record: a dispatched agent carries its parent's session id.
git -C "$R10" -c user.name=f -c user.email=f@x.invalid -c commit.gpgsign=false commit -q --allow-empty -m seed
W10="$SANDBOX/r10-wt"; git -C "$R10" worktree add -q "$W10" -b wt/r10 2>/dev/null; ln -s "$R10/.bionic" "$W10/.bionic"
expect_true "10g the worktree is a linked tree of the repository (non-vacuity)" test -f "$W10/.git"
expect_eq "…and from it the session reads the record the main checkout's binding wrote" "0|$Q10" "$(plan_read "$W10" "$SID")"

# A RECORD THAT CANNOT BE WRITTEN IS A WRITE FAILURE, not a binding.
R10F="$(make_repo r10f)"; P10F="$R10F/.bionic/docs/plans/epic-01-demo/wave-01.plan.md"
: > "$R10F/.git/bionic-seal"
call_bind "$R10F" "$SID" "$P10F"
expect_eq "10h a seal home that cannot hold the record: exit 2, record-failed" "2|record-failed" "$BIND_ST|$BIND_WHY"
rm -f "$R10F/.git/bionic-seal"
call_bind "$R10F" "$SID" "$P10F"
expect_eq "…paired: with the obstruction gone the same call writes the record (exit 0)" "0|plan=$P10F" "$BIND_ST|$(sed -n 4p "$(rec_of "$R10F")" 2>/dev/null)"

# ENGAGEMENT GUESSES ONCE. A session the record answers `none` for keeps `none` when its marker is
# removed: the removal is no first engagement, and the count rule (hooks/engage.sh) is not asked again.
R10E="$(make_repo r10e)"; P10E="$R10E/.bionic/docs/plans/epic-01-demo/wave-01.plan.md"
engage_root() { ( cd "$1" && CLAUDE_CODE_SESSION_ID="$2" bash "$REPO_ROOT/hooks/engage.sh" --root "$1" ) >/dev/null 2>&1; }
engage_root "$R10E" "s10e-first"
expect_eq "10i a first engagement in a root with one live run binds it (the count rule, the positive)" \
  "plan=$P10E" "$(sed -n 1p "$R10E/.bionic/tmp/engaged-s10e-first.state" 2>/dev/null)"
call_bind "$R10E" "s10e-none" none
rm -f "$R10E/.bionic/tmp/engaged-s10e-none.state"
engage_root "$R10E" "s10e-none"
expect_eq "…a session recorded bound to none, its marker removed, engages again at none" \
  "plan=none" "$(sed -n 1p "$R10E/.bionic/tmp/engaged-s10e-none.state" 2>/dev/null)"

finish
