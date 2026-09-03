#!/bin/bash
# Tests for hooks/session-start.sh — THE POST-`/clear` DETECTOR (bionic 1.4.0,
# spec AC-1, AC-4's "the block runs the report", AC-11's symlink listing; plan
# slice SSTART).
#
# THE CONTRACT UNDER TEST. `/clear` re-keys the session id in place (probe
# A-probe-1/2/3: env, payload and `sessions/<pid>.json` all move together, same
# pid, same process) and leaves the PREVIOUS conversation's state on disk beside
# the new session's: a roster with open rows nobody owns any more, a patrol stamp
# under the old sid, and — until the ritual runs — a live predecessor cron
# (A-probe-4, which FIRED into the new conversation 13 minutes late). None of that
# announces itself. This hook is the announcement, and nothing more: it prints one
# block on stdout, which a SessionStart hook's stdout puts into the new
# conversation's context, and it arms, writes and refuses nothing.
#
# WHY EVERY ASSERTION BELOW ALSO CHECKS `writes nothing`. A detector that stamped
# would satisfy the arming wall over a cron table that holds nothing — the exact
# inversion tests/patrol-revive.test.sh was written to prevent one file over. The
# `snap` helper fingerprints the whole `.bionic` subtree (paths and mtimes) before
# and after every drive, so a write of any kind — including a poker subprocess
# that stamped on the way past — fails the group that caused it.
#
# ACCELERATED CLOCK, NEVER A WAIT. Staleness is manufactured by backdating the
# stamp's mtime against a tiny `poker-interval:` in the fixture's own config —
# the `s21_backdate` idiom of tests/dispatch-preflight.test.sh, borrowed through
# tests/patrol-revive.test.sh. Nothing here sleeps.
#
# THE PID FILE IS DRIVEN, NOT ASSUMED. The hook reads `<claude-home>/sessions/
# $PPID.json`, and its parent is whatever launched it, so the fixtures launch it
# through `wrap.sh`, which writes its own `$$` into a fixture claude-home and then
# runs the hook as a CHILD (never `exec`, which would make the hook's parent the
# wrapper's parent instead). BIONIC_CLAUDE_HOME redirects the home, the same knob
# payload/scripts/lib/patrol.sh already reads.
#
# Usage: bash tests/session-start.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

HOOK="${BIONIC_SESSION_START_UNDER_TEST:-${BIONIC_HOOKS_DIR}/session-start.sh}"
PASS=0; FAIL=0; TOTAL=0

ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "  $2"; return 0; }

eq()  { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }
has() { if printf '%s' "$3" | grep -qF -- "$2"; then ok "$1"; else no "$1" "missing '$2' in: $3"; fi; }
hasnt() { if printf '%s' "$3" | grep -qF -- "$2"; then no "$1" "unexpected '$2' in: $3"; else ok "$1"; fi; }

command -v jq >/dev/null 2>&1 || { echo "session-start: jq absent — suite cannot run"; exit 1; }

# THE SUITE IS NOT ALLOWED TO BE VACUOUS. Most assertions below read "rc 0 and no
# stdout", which is exactly what a MISSING hook produces once the shell's 127 is
# discarded. Prove the subject exists and parses before any of it runs.
[ -f "$HOOK" ] || { echo "session-start: no hook at $HOOK — suite refuses to run"; exit 1; }
bash -n "$HOOK" || { echo "session-start: $HOOK does not parse — suite refuses to run"; exit 1; }

CUR_SID="11111111-2222-3333-4444-555555555555"
OLD_SID="99999999-8888-7777-6666-555555555555"
OLD2_SID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
PAY_SID="77777777-6666-5555-4444-333333333333"

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# ---------- fixture builders ----------

# A scratch project carrying `.bionic/tmp` and a TINY poker-interval, so twice the
# interval is two seconds and a backdated stamp is decisively stale with no wait.
# No git repository: project_root's walk answers at the nearest ancestor carrying
# a real `.bionic/`, which is this directory itself.
make_env() {  # [interval] -> project dir on stdout
  local dir; dir=$(mktemp -d "$WORK/proj.XXXXXX")
  mkdir -p "$dir/.bionic/tmp"
  printf 'poker-interval: %s\n' "${1:-1s}" > "$dir/.bionic/config.yaml"
  printf '%s' "$dir"
}

# A roster row per status transition, exactly as hooks/session-poker.sh's wall and
# hooks/execution-recorder.sh append them: `intended`, then `identified`, then
# `confirmed` for one name. Open rows are counted BY NAME, so three rows for one
# agent are one open row — a counter that counted lines would read 3 here.
roster_rows() {  # <file> <sid> <name>
  local f="$1" sid="$2" n="$3" st
  for st in intended identified confirmed; do
    printf 'roster-state/v1|status=%s|session=%s|name=%s|agent_id=a%s-1111111111111111|launched_at=2026-09-02T20:00:00Z|subagent_type=implementor|model=|deliverable=.bionic/docs/record/%s.md|source=declared|duration=|progress=|claims=|cadence=|absent=|waiver=|tool_use_id=toolu_01FIXTURE\n' \
      "$st" "$sid" "$n" "$n" "$n" >> "$f"
  done
}

swept() {  # <file> <name>   the landing gate's closing marker
  printf 'landing-swept/v1|name=%s|state=MET|at=2026-09-02T21:00:00Z\n' "$2" >> "$1"
}

backdate() {  # <file> <seconds ago>
  local ts
  ts="$(date -v-"$2"S +%Y%m%d%H%M.%S 2>/dev/null || date -d "-$2 seconds" +%Y%m%d%H%M.%S)"
  touch -t "$ts" "$1"
}

write_stamp() {  # <project> <sid>
  printf 'patrol-stamp/v1|at=2026-09-02T20:00:00Z|session=%s|verb=arm\n' "$2" \
    > "$1/.bionic/tmp/patrol-$2.state"
}

# Every path under .bionic with its mtime — the "wrote nothing" fingerprint.
snap() {  # <project>
  find "$1/.bionic" 2>/dev/null | sort | while read -r f; do
    printf '%s %s\n' "$f" "$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)"
  done
}

# The wrapper whose $$ becomes the hook's PPID. Written once, used by every drive.
WRAP="$WORK/wrap.sh"
cat > "$WRAP" <<'WRAP_EOF'
#!/bin/bash
# $1 = fixture claude home, $2 = sessionId to record (or "-" for no pid file),
# $3 = hook path. Payload arrives on stdin and is inherited by the child.
# NOT `exec`: the hook must be a CHILD so that its $PPID is this shell's $$,
# which is the pid this file is named for.
if [ "$2" != "-" ]; then
  mkdir -p "$1/sessions"
  printf '{"pid":%s,"sessionId":"%s","cwd":"%s"}\n' "$$" "$2" "$PWD" > "$1/sessions/$$.json"
fi
bash "$3"
WRAP_EOF

# One drive. Prints stdout, and leaves stdout/stderr/rc in three files.
#
# THE THREE FILES ARE NOT A CONVENIENCE. Every call site reads `OUT=$(drive …)`,
# which runs `drive` inside a command substitution — a SUBSHELL, whose variable
# assignments are discarded the moment it exits. An earlier draft of this harness
# kept rc in a shell variable and every "exit 0" assertion below silently compared
# the initial 0 against itself: forty green rows over an unread status. The status
# and the stderr therefore cross the subshell boundary the only way they can, on
# disk, and `rc` / `errtext` read them back afterwards.
OUTF=""; ERRF=""; RCF=""
drive() {  # <project> <source> <env-sid> <payload-sid> <pidfile-sid|-> -> stdout
  local proj="$1" src="$2" esid="$3" psid="$4" fsid="$5" home
  home="$WORK/home.$RANDOM.$RANDOM"; mkdir -p "$home"
  OUTF="$WORK/last.out"; ERRF="$WORK/last.err"; RCF="$WORK/last.rc"
  (
    cd "$proj" || exit 1
    printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"SessionStart","source":"%s"}' \
      "$psid" "$home/t.jsonl" "$proj" "$src" \
    | CLAUDE_CODE_SESSION_ID="$esid" BIONIC_CLAUDE_HOME="$home" \
      bash "$WRAP" "$home" "$fsid" "$HOOK" > "$WORK/last.out" 2>"$WORK/last.err"
  )
  printf '%s' "$?" > "$WORK/last.rc"
  cat "$WORK/last.out"
}
rc()      { cat "$WORK/last.rc" 2>/dev/null; }
errtext() { cat "$WORK/last.err" 2>/dev/null; }

# The harness's own catch-proof: a drive of a script that exits 3 with a known
# stderr line must be READ as 3 with that line. Without this row, every rc and
# stderr assertion below could be passing over a broken reader (the failure this
# helper was rewritten to close).
printf '#!/bin/bash\ncat >/dev/null\necho "harness-probe-stderr" >&2\nexit 3\n' > "$WORK/probe.sh"
P0=$(make_env 1s)
BIONIC_SESSION_START_UNDER_TEST_SAVE="$HOOK"; HOOK="$WORK/probe.sh"
drive "$P0" clear "$CUR_SID" "$CUR_SID" "$CUR_SID" >/dev/null
eq  "0.1 the harness reads a non-zero exit as non-zero" "3" "$(rc)"
has "0.2 …and reads the driven script's stderr" "harness-probe-stderr" "$(errtext)"
HOOK="$BIONIC_SESSION_START_UNDER_TEST_SAVE"

echo "=== 1 — a predecessor roster on a /clear: the block, and the sequence ==="
# The whole point of the hook, driven exactly as the probe left the disk: same
# process, new sid, the old conversation's roster still open beside the new one's.
P1=$(make_env 1s)
roster_rows "$P1/.bionic/tmp/roster-$OLD_SID.state" "$OLD_SID" "W-ALPHA"
roster_rows "$P1/.bionic/tmp/roster-$OLD_SID.state" "$OLD_SID" "W-BETA"
swept "$P1/.bionic/tmp/roster-$OLD_SID.state" "W-BETA"
# THIS session's own roster, also with an open row: it must NOT be listed. Without
# this the "predecessor" filter could be a no-op and every assertion still pass.
roster_rows "$P1/.bionic/tmp/roster-$CUR_SID.state" "$CUR_SID" "W-MINE"
S1_BEFORE=$(snap "$P1")
OUT=$(drive "$P1" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq   "1.1 exit 0" "0" "$(rc)"
has  "1.2 the block names the predecessor roster file" "roster-$OLD_SID.state" "$OUT"
has  "1.3 …with ONE open row (three status rows for W-ALPHA are one agent)" "1 open row" "$OUT"
has  "1.4 …under the predecessor's sid8" "${OLD_SID:0:8}" "$OUT"
hasnt "1.5 …and THIS session's own open roster is not a predecessor" "roster-$CUR_SID.state" "$OUT"
has  "1.6 the re-arm sequence: CronList first" "re-arm: CronList" "$OUT"
has  "1.7 …then the stray delete" "delete bionic-patrol session=" "$OUT"
has  "1.8 …then CronCreate" "CronCreate" "$OUT"
has  "1.9 …then arm, by absolute path" "$(cd "$(dirname "$HOOK")/.." && pwd -P)/hooks/session-poker.sh arm" "$OUT"
has  "1.10 …then adopt" "adopt" "$OUT"
has  "1.11 the session-id triple agrees" "— agree" "$OUT"
eq   "1.12 the hook wrote nothing under .bionic" "$S1_BEFORE" "$(snap "$P1")"

echo ""
echo "=== 2 — startup with nothing to report: silence ==="
P2=$(make_env 1s)
S2_BEFORE=$(snap "$P2")
OUT=$(drive "$P2" startup "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq "2.1 exit 0" "0" "$(rc)"
eq "2.2 nothing on stdout" "" "$OUT"
eq "2.3 wrote nothing" "$S2_BEFORE" "$(snap "$P2")"

echo ""
echo "=== 3 — no .bionic anywhere above the cwd: silence ==="
# A bare temp directory: no git, no `.bionic`. project_root falls back to the cwd
# and there is no real `.bionic` under it, so there is no project to report on.
P3=$(mktemp -d "$WORK/bare.XXXXXX")
OUT=$(drive "$P3" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq "3.1 exit 0" "0" "$(rc)"
eq "3.2 nothing on stdout" "" "$OUT"
eq "3.3 no .bionic was created" "" "$(ls -A "$P3")"

echo ""
echo "=== 4 — a divergent session-id triple: DIVERGE, named channel by channel ==="
P4=$(make_env 1s)
OUT=$(drive "$P4" clear "$CUR_SID" "$PAY_SID" "$OLD_SID")
eq  "4.1 exit 0" "0" "$(rc)"
has "4.2 the verdict is DIVERGE" "DIVERGE" "$OUT"
has "4.3 env is named" "env=$CUR_SID" "$OUT"
has "4.4 payload is named" "payload=$PAY_SID" "$OUT"
has "4.5 pidfile is named" "pidfile=$OLD_SID" "$OUT"
# The L-SESSION contract: one warning line on stderr naming both, and the env wins.
has "4.6 lib/session.sh's divergence warning reached stderr" \
  "session-id: payload $PAY_SID ≠ env $CUR_SID — using env" "$(errtext)"

# …and an absent pid file says so rather than inventing agreement.
P4b=$(make_env 1s)
OUT=$(drive "$P4b" clear "$CUR_SID" "$PAY_SID" "-")
has "4.7 an absent pid file is reported absent" "pidfile=absent" "$OUT"
has "4.8 …and two channels that still disagree still DIVERGE" "DIVERGE" "$OUT"

echo ""
echo "=== 5 — a legacy .bionic symlink under .worktrees (AC-11, ledger C2) ==="
P5=$(make_env 1s)
mkdir -p "$P5/.worktrees/wt-one"
ln -s "$P5/.bionic" "$P5/.worktrees/wt-one/.bionic"
mkdir -p "$P5/.worktrees/wt-two/.bionic"   # a REAL dir there is not a legacy link
S5_BEFORE=$(snap "$P5")
OUT=$(drive "$P5" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq  "5.1 exit 0" "0" "$(rc)"
has "5.2 the legacy link is listed" "legacy .bionic symlinks:" "$OUT"
has "5.3 …by its path" ".worktrees/wt-one/.bionic" "$OUT"
hasnt "5.4 …and a real directory beside it is not" ".worktrees/wt-two/.bionic" "$OUT"
eq  "5.5 wrote nothing" "$S5_BEFORE" "$(snap "$P5")"

echo ""
echo "=== 6 — predecessor stamps: stale past PATROL_STALE_MULTIPLIER x interval ==="
# interval 1s -> limit 2s. One predecessor stamp backdated well past it, one
# predecessor stamp written now, and THIS session's own stamp backdated too — the
# last is the anti-vacuity control: staleness alone must not make a stamp mine.
P6=$(make_env 1s)
write_stamp "$P6" "$OLD_SID";  backdate "$P6/.bionic/tmp/patrol-$OLD_SID.state" 600
write_stamp "$P6" "$OLD2_SID"
write_stamp "$P6" "$CUR_SID";  backdate "$P6/.bionic/tmp/patrol-$CUR_SID.state" 600
S6_BEFORE=$(snap "$P6")
OUT=$(drive "$P6" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq  "6.1 exit 0" "0" "$(rc)"
has "6.2 the stamps section is present" "predecessor stamps:" "$OUT"
eq  "6.3 the backdated predecessor stamp reads stale" "1" \
  "$(printf '%s\n' "$OUT" | grep -c "^  ${OLD_SID:0:8} .*stale$")"
eq  "6.4 the just-written predecessor stamp reads fresh" "1" \
  "$(printf '%s\n' "$OUT" | grep -c "^  ${OLD2_SID:0:8} .*fresh$")"
hasnt "6.5 THIS session's own stale stamp is not a predecessor" "  ${CUR_SID:0:8}" "$OUT"
has "6.6 the age is reported in seconds" "s old" "$OUT"
eq  "6.7 wrote nothing" "$S6_BEFORE" "$(snap "$P6")"

echo ""
echo "=== 7 — the hook never blocks and never refuses ==="
# Every fixture above already asserted rc 0. What is left is the degenerate input
# a real SessionStart can still deliver: no payload at all, and no session key.
P7=$(make_env 1s)
roster_rows "$P7/.bionic/tmp/roster-$OLD_SID.state" "$OLD_SID" "W-GAMMA"
S7_BEFORE=$(snap "$P7")
OUT=$( cd "$P7" && printf '' | CLAUDE_CODE_SESSION_ID="" BIONIC_CLAUDE_HOME="$WORK/nohome" bash "$HOOK" 2>/dev/null )
eq "7.1 empty payload, no session key: exit 0" "0" "$?"
eq "7.2 …and still wrote nothing" "$S7_BEFORE" "$(snap "$P7")"
OUT=$( cd "$P7" && printf 'not json at all' | CLAUDE_CODE_SESSION_ID="$CUR_SID" BIONIC_CLAUDE_HOME="$WORK/nohome" bash "$HOOK" 2>/dev/null )
eq "7.3 unparsable payload: exit 0" "0" "$?"

echo ""
echo "──────────────────────────────────────────────"
echo "session-start: ${PASS} passed, ${FAIL} failed, ${TOTAL} total"
[ "$FAIL" -eq 0 ]
