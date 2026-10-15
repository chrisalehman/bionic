#!/bin/bash
# NOTHING HERE PASSES OR FAILS BY THE CLOCK (wave-35 T11; REQ-2 AC-2.2, D11). §16's cost rows
# count forks over 8 and 400 predecessors and §17.13 counts the bound's polls, where they once
# read seconds and ratios of seconds; see THE COUNT in §16.
#
# Tests for hooks/session-start.sh — THE POST-`/clear` DETECTOR (bionic 1.4.0,
# spec AC-1, AC-4's "the block runs the report", AC-11's symlink listing; plan
# task SSTART).
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
# that stamped on the way past — fails the group that caused it. The one write a
# start makes for itself, the load record (§21, wave-36 T1), needs a CLAUDE_PLUGIN_ROOT,
# and `drive` hands the hook an empty one unless a row names a root.
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
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"

HOOK="${BIONIC_SESSION_START_UNDER_TEST:-${BIONIC_HOOKS_DIR}/session-start.sh}"

eq()  { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }
# has/hasnt READ THE HAYSTACK WITHOUT A PIPE (wave-36 T48; §16.4a/b). They were
# `printf '%s' "$3" | grep -qF`, which under `pipefail` fails a present needle once the report
# outgrows the pipe buffer (grep leaves at its first match, printf takes EPIPE) and, in hasnt,
# reads that same present needle as absent. tests/lib/assert.sh's quoted-`case` helpers are the
# same containment with no pipe; the 400-character message cut is theirs.
has()   { expect_contains "$@"; }
hasnt() { expect_absent "$@"; }

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
    roster_row_fixture status="$st" session="$sid" name="$n" \
      agent_id="a$n-1111111111111111" launched_at=2026-09-02T20:00:00Z model= \
      deliverable=".bionic/docs/record/$n.md" >> "$f"
  done
}

# THROUGH THE ONE WRITER (S17, spec AC-26): `swept_marker_write` is
# hooks/landing-gate.sh's own function, extracted by tests/lib/swept-marker.sh and called
# for real. The printf that used to sit here wrote a marker the originator would not
# recognise — no `session=`, no `agent_id=` — and stayed green because every reader of the
# marker is by key.
#
# The old spelling here also REORDERED the fields (`name=` before `state=` before `at=`),
# which no reader noticed and no writer has ever produced.
swept() {  # <file> <sid> <name>   the landing gate's marker — a landing SEEN
  swept_marker_write "$1" 2026-09-02T21:00:00Z "$2" "$3" "" MET
}

# THE ACK — the one thing that closes a name (epic-23 wave-20 T17, D10). The sweeper's ledger
# line in its writer's shape, beside the roster as `sweeper-<sid>.state`. The hook's open-row
# count asks `roster_open_names`' predicate, which closes a name only on an ack stamped after
# its latest live row's `launched_at=` (roster_rows stamps 2026-09-02T20:00:00Z); a MET marker
# alone closes nothing.
acked() {  # <project> <sid> <name> [at]
  local l="$1/.bionic/tmp/sweeper-$2.state"
  [ -f "$l" ] || printf '# bionic session sweeper ledger — schema sweeper-ledger/v1 — machine-local, safe to delete\n' > "$l"
  printf 'sweeper-ledger/v1|event=ack|at=%s|epoch=0|pid=1|session=%s|name=%s|by=patrol|reason=landed\n' \
    "${4:-2026-09-02T21:30:00Z}" "$2" "$3" >> "$l"
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

# An OPEN RUN, in the shape lib/run.sh's active_plan/active_run read: a
# flush-left `## SDLC State` heading under `.bionic/docs/plans/`, and a
# `current:` step below 9. This is the T4 gate's own precondition (AC-11/
# AC-12) — no earlier section in this suite plants one, so the engagement
# gate is a complete no-op for every fixture above.
write_open_plan() {  # <project> [name] -> plan path on stdout
  local dir="$1/.bionic/docs/plans/fixture" f name="${2:-fixture}"
  mkdir -p "$dir"
  f="$dir/$name.plan.md"
  {
    printf -- '---\n'
    printf 'governing-skill: canonical-sdlc\ncanonical_sdlc_version: 14\n'
    printf 'intent: bugfix\nrigor: single\nscale: task\n'
    printf -- '---\n\n# Fixture plan\n\n## SDLC State\n\ncurrent: 3\n'
  } > "$f"
  printf '%s' "$f"
}

# A CLOSED run (delivered) — same shape, `current: 9` and a Step-9 evidence line
# carrying `delivered:` (lib/run.sh `run_open`'s own close condition). This is the
# negative fixture for §12: a member of `active_plan`'s candidate walk that
# `open_runs` must never include.
write_delivered_plan() {  # <project> [name] -> plan path on stdout
  local dir="$1/.bionic/docs/plans/fixture" f name="${2:-delivered}"
  mkdir -p "$dir"
  f="$dir/$name.plan.md"
  {
    printf -- '---\n'
    printf 'governing-skill: canonical-sdlc\ncanonical_sdlc_version: 14\n'
    printf 'intent: bugfix\nrigor: single\nscale: task\n'
    printf -- '---\n\n# Fixture plan\n\n## SDLC State\n\ncurrent: 9\n\n- Step 9: delivered: 2026-09-02\n'
  } > "$f"
  printf '%s' "$f"
}

# A BOUND marker (lib/binding.sh's shape, S1/S2 contract): `plan=<path>` naming a
# member of the open-run set, plus `engaged_at=`. Distinct from `plant_engaged`,
# which writes an empty (unbound) marker. S11: this now calls the real `bind_plan`
# (tests/lib/bound-marker.sh), which stores the CANONICAL spelling itself — the
# `realplan()` workaround this suite used to need at every call site that asserts
# the plan's exact text is gone; the real writer canonicalises for us.
plant_bound() {  # <project> <sid> <plan-path>
  bound_marker "$1" "$2" "$3"
}

# The engagement marker itself (lib/run.sh `engaged_session`) — a REGULAR file
# at this exact path is the whole contract; content is never read here.
plant_engaged() {  # <project> <sid>
  mkdir -p "$1/.bionic/tmp"
  : > "$1/.bionic/tmp/engaged-$2.state"
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
"${DRIVE_HOOK_BASH:-bash}" "$3"
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
STANDING_MARK='goes through the bionic:decision skill'
drive() {  # <project> <source> <env-sid> <payload-sid> <pidfile-sid|-> -> stdout
  local proj="$1" src="$2" esid="$3" psid="$4" fsid="$5" home
  home="$WORK/home.$RANDOM.$RANDOM"; mkdir -p "$home"
  OUTF="$WORK/last.out"; ERRF="$WORK/last.err"; RCF="$WORK/last.rc"
  # DRIVE_PLUGIN_ROOT=<dir>: the CLAUDE_PLUGIN_ROOT the CLI hands the hook (§21, wave-36 T1). Empty by
  # default, and set empty rather than inherited, so no section reads the root of whatever ran the suite.
  # DRIVE_HOOK_BASH=<path>: the bash that runs the hook (§22); `bash` on the PATH by default.
  # DRIVE_LIVE=<sid>: one more LIVE session in the fixture home (T15), at this suite's own pid,
  # which is alive for the whole run — the CLI's pid-file shape the wrapper writes for the hook.
  if [ -n "${DRIVE_LIVE:-}" ]; then
    mkdir -p "$home/sessions"
    printf '{"pid":%s,"sessionId":"%s","cwd":"%s"}\n' "$$" "$DRIVE_LIVE" "$proj" > "$home/sessions/$$.json"
  fi
  (
    cd "$proj" || exit 1
    printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"SessionStart","source":"%s"}' \
      "$psid" "$home/t.jsonl" "$proj" "$src" \
    | CLAUDE_CODE_SESSION_ID="$esid" BIONIC_CLAUDE_HOME="$home" CLAUDE_PLUGIN_ROOT="${DRIVE_PLUGIN_ROOT:-}" \
      DRIVE_HOOK_BASH="${DRIVE_HOOK_BASH:-bash}" bash "$WRAP" "$home" "$fsid" "$HOOK" > "$WORK/last.out" 2>"$WORK/last.err"
  )
  printf '%s' "$?" > "$WORK/last.rc"
  # The STANDING decision line (T27, AC-11.2) is printed in every session and is not part of the
  # state report every assertion below reads, so it is taken out of what `drive` returns. The raw
  # stdout stays in last.out, and §20 reads it from there. Every report assertion keeps its text.
  grep -vF -- "$STANDING_MARK" "$WORK/last.out" || true
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

section "1 — a predecessor roster on a /clear: the block, and the sequence"
# The whole point of the hook, driven exactly as the probe left the disk: same
# process, new sid, the old conversation's roster still open beside the new one's.
#
# 3600s, NOT THE 1s DEFAULT (R2, ticket-30). session-start.sh now sweeps a DEAD
# predecessor's state whose files are older than one Patrol interval — that is
# the whole feature under test in tests/session-sweep.test.sh §7 — and this
# section is not about that feature at all: OLD_SID's roster here is written
# moments before `drive()` runs it, and under the suite's own 1s default that
# freshness is a coin flip against however long sourcing four libraries and
# parsing the JSON payload actually takes on the machine running this suite. A
# generous interval keeps the file unambiguously YOUNG so "wrote nothing" below
# tests what this section is actually about — the report and the re-arm
# sequence — deterministically, not by how loaded the box happens to be.
P1=$(make_env 3600s)
roster_rows "$P1/.bionic/tmp/roster-$OLD_SID.state" "$OLD_SID" "W-ALPHA"
roster_rows "$P1/.bionic/tmp/roster-$OLD_SID.state" "$OLD_SID" "W-BETA"
swept "$P1/.bionic/tmp/roster-$OLD_SID.state" "$OLD_SID" "W-BETA"
# RE-AUTHORED BY T17 (epic-23 wave-20, D10): W-BETA used to be closed by the MET marker above
# alone. It is now closed by the ack the Patrol takes once it sees the agent gone — the marker
# stays because a landed row carries one — so 1.3's "ONE open row" still counts W-ALPHA only.
# §18 pins the marker-alone case directly.
acked "$P1" "$OLD_SID" "W-BETA"
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
has  "1.7 …then the stray delete" "delete every job whose prompt begins with bionic-patrol session=" "$OUT"
has  "1.8 …then CronCreate" "CronCreate" "$OUT"
# RE-AUTHORED BY wave-21 T2 (REQ-2, D2, ADR-037 decision 1). T19 (A-orch-19.3) dropped
# `session-poker.sh arm` from this line because engage.sh arms the stamp at engagement. That
# holds for the session that engages; it does not hold for the starts this line now serves —
# a `compact` or `resume` of an engaged session runs no engage.sh, so its stamp is whatever the
# last firing left, and the armed instant (R-13) predates the clock the model is about to
# create. The line is now the FINISHED arm command the model runs as written: CronList, delete
# every marked job, CronCreate with the prompt baked in (the poker's own `prompt` verb's output,
# so the prompt text keeps one owner), then `arm`, all by this hook's own root.
S1_POKER="$(cd "$(dirname "$HOOK")/.." && pwd -P)/hooks/session-poker.sh"
S1_PROMPT="$(CLAUDE_CODE_SESSION_ID="$CUR_SID" bash "$S1_POKER" prompt 2>/dev/null)"
has  "1.9 …then the arm hand step, by this hook's own poker" "bash $S1_POKER arm" "$OUT"
has  "1.9b …the re-arm line itself, exactly: CronList, delete, CronCreate with the baked prompt, arm" \
  "re-arm: CronList → delete every job whose prompt begins with bionic-patrol session= → CronCreate, recurring every 3600s, with the prompt \`$S1_PROMPT\` → bash $S1_POKER arm" "$OUT"
has  "1.9c …the baked prompt's first token is THIS session's marker" \
  "with the prompt \`bionic-patrol session=${CUR_SID:0:8} " "$OUT"
has  "1.9e …and its tick is this hook's own poker" "bash $S1_POKER tick" "$OUT"
eq   "1.9d exactly one re-arm line" "1" "$(printf '%s\n' "$OUT" | grep -c '^re-arm: ')"
# The predecessor variant keeps its extra step: adopt, on its own line after the arm line.
has  "1.10 …then adopt, by this hook's own poker" "adopt: bash $S1_POKER adopt" "$OUT"
has  "1.11 the session-id triple agrees" "— agree" "$OUT"
eq   "1.12 the hook wrote nothing under .bionic" "$S1_BEFORE" "$(snap "$P1")"

section "2 — startup with nothing to report: silence"
P2=$(make_env 1s)
S2_BEFORE=$(snap "$P2")
OUT=$(drive "$P2" startup "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq "2.1 exit 0" "0" "$(rc)"
eq "2.2 nothing on stdout" "" "$OUT"
eq "2.3 wrote nothing" "$S2_BEFORE" "$(snap "$P2")"

section "3 — no .bionic anywhere above the cwd: silence"
# A bare temp directory: no git, no `.bionic`. project_root falls back to the cwd
# and there is no real `.bionic` under it, so there is no project to report on.
P3=$(mktemp -d "$WORK/bare.XXXXXX")
OUT=$(drive "$P3" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq "3.1 exit 0" "0" "$(rc)"
eq "3.2 nothing on stdout" "" "$OUT"
eq "3.3 no .bionic was created" "" "$(ls -A "$P3")"

section "4 — a divergent session-id triple: DIVERGE, named channel by channel"
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

section "5 — a legacy .bionic symlink under .worktrees (AC-11/AC-7.1, ledger C2, narrowed A-orch-24)"
# `wt-one` resolves SOMEWHERE ELSE — a mis-pointed link, the genuine legacy shape.
# `wt-two` is a real directory, never a symlink. `wt-three` resolves to THIS
# project's own `.bionic` — the alias `spawn-worktree.sh create` plants on
# purpose (D7) — so it must NOT be reported: `worktree_legacy_links` (lib/
# worktree.sh) is the one predicate this hook and doctor.sh's own report both
# call, rather than each keeping its own copy of the comparison.
P5=$(make_env 1s)
mkdir -p "$P5/.worktrees/wt-one" "$P5/.worktrees/wt-three"
mkdir -p "$P5/elsewhere/.bionic"
ln -s "$P5/elsewhere/.bionic" "$P5/.worktrees/wt-one/.bionic"
mkdir -p "$P5/.worktrees/wt-two/.bionic"   # a REAL dir there is not a legacy link
ln -s "$P5/.bionic" "$P5/.worktrees/wt-three/.bionic"
S5_BEFORE=$(snap "$P5")
OUT=$(drive "$P5" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq  "5.1 exit 0" "0" "$(rc)"
has "5.2 the legacy link is listed" "legacy .bionic symlinks:" "$OUT"
has "5.3 …by its path" ".worktrees/wt-one/.bionic" "$OUT"
hasnt "5.4 …and a real directory beside it is not" ".worktrees/wt-two/.bionic" "$OUT"
hasnt "5.4b …and an alias correctly pointing at the main root's .bionic is not (D7)" \
  ".worktrees/wt-three/.bionic" "$OUT"
eq  "5.5 wrote nothing" "$S5_BEFORE" "$(snap "$P5")"

section "6 — predecessor stamps: graded against ONE FIRE WINDOW, and swept per session"
# RE-AUTHORED AT epic-23 wave-16 (REQ-8 AC-8.1/8.2, REQ-11 AC-11.1/11.2). Both halves this
# section drives changed under it, and they changed in opposite directions:
#
#   THE REPORT no longer grades a stamp at `interval * 2`. That multiplier is deleted —
#   age past a threshold cannot tell a dead cron from a busy orchestrator, because a session
#   cron fires only while the session is IDLE. The threshold is `patrol_fire_window` (the
#   interval plus a tenth for jitter) and, for a stamp of a LIVE session past it, the answer
#   comes from `patrol_verdict` over that session's transcript. Every stamp here belongs to a
#   DEAD predecessor, which is the plainest case: no process is left to fire anything, so
#   past the window it is stale on that fact and needs no transcript.
#
#   THE SWEEP no longer defers the whole directory when one dead file is young. The hook
#   passes `--window` and the verb defers PER SESSION, which is what lets this one fixture
#   hold both answers at once.
#
# SO THE FIXTURE IS A 60s INTERVAL (a 66s window) with three stamps: one dead predecessor
# ten minutes old — past the window, and old enough for the sweep; one dead predecessor five
# seconds old — inside the window, and young enough for the verb to defer; and THIS session's
# own, backdated, as the anti-vacuity control that staleness alone does not make a stamp
# mine. Nothing sleeps and no assertion depends on how long the hook takes: five seconds and
# ten minutes are both decisively on their side of 66s.
P6=$(make_env 60s)
write_stamp "$P6" "$OLD_SID";  backdate "$P6/.bionic/tmp/patrol-$OLD_SID.state" 600
write_stamp "$P6" "$OLD2_SID"; backdate "$P6/.bionic/tmp/patrol-$OLD2_SID.state" 5
write_stamp "$P6" "$CUR_SID";  backdate "$P6/.bionic/tmp/patrol-$CUR_SID.state" 600
OUT=$(drive "$P6" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq  "6.1 exit 0" "0" "$(rc)"
has "6.2 the stamps section is present" "predecessor stamps:" "$OUT"
eq  "6.3 a dead predecessor's stamp past the fire window reads stale" "1" \
  "$(printf '%s\n' "$OUT" | grep -c "^  ${OLD_SID:0:8} .*stale$")"
eq  "6.4 …and one inside the window reads fresh" "1" \
  "$(printf '%s\n' "$OUT" | grep -c "^  ${OLD2_SID:0:8} .*fresh$")"
hasnt "6.5 THIS session's own stale stamp is not a predecessor" "  ${CUR_SID:0:8}" "$OUT"
has "6.6 the age is reported in seconds" "s old" "$OUT"
# THE WINDOW IS THE NUMBER THE LINE NAMES, and it is the library's, not twice the interval:
# 60 + 60/10. A line still quoting 120s would be the deleted multiplier back in the report.
has "6.6b …and the line names the fire window it graded against" "inside 66s" "$OUT"

# THE SWEEP, PER SESSION (REQ-8). The report above is read off the disk BEFORE the sweep
# runs, so 6.3/6.4 stand whatever it does next. Both predecessors are DEAD (no live pid for
# either in this fixture's claude-home); the ten-minute-old one is past the 60s window and
# goes, the five-second-old one is inside it and is deferred — ALONE, which is the whole of
# what REQ-8 changed. Before it, one young file kept the other session's residue too.
# THIS session's own 600s-old stamp survives because it is LIVE, not because of its age —
# the same anti-vacuity point 6.5 makes about the report, made again about the sweep.
expect_false "6.7 the dead, 600s-old predecessor stamp is swept" \
  test -e "$P6/.bionic/tmp/patrol-$OLD_SID.state"
expect_true "6.8 …while the OTHER dead predecessor, younger than the window, is deferred alone" \
  test -f "$P6/.bionic/tmp/patrol-$OLD2_SID.state"
expect_true "6.9 THIS session's own 600s-old stamp survives — it is live, not young" \
  test -f "$P6/.bionic/tmp/patrol-$CUR_SID.state"
expect_false "6.10 …and no sweep-failure marker appeared — nothing failed here" \
  test -e "$P6/.bionic/tmp/sweep-failed.state"

section "7 — the hook never blocks and never refuses"
# Every fixture above already asserted rc 0. What is left is the degenerate input
# a real SessionStart can still deliver: no payload at all, and no session key.
# 3600s: see §1's comment above — this fixture's predecessor roster is fresh and
# unrelated to R2's own age-gate feature, so a generous interval keeps it out of
# the sweep's reach deterministically.
P7=$(make_env 3600s)
roster_rows "$P7/.bionic/tmp/roster-$OLD_SID.state" "$OLD_SID" "W-GAMMA"
S7_BEFORE=$(snap "$P7")
OUT=$( cd "$P7" && printf '' | CLAUDE_CODE_SESSION_ID="" BIONIC_CLAUDE_HOME="$WORK/nohome" bash "$HOOK" 2>/dev/null )
eq "7.1 empty payload, no session key: exit 0" "0" "$?"
eq "7.2 …and still wrote nothing" "$S7_BEFORE" "$(snap "$P7")"
OUT=$( cd "$P7" && printf 'not json at all' | CLAUDE_CODE_SESSION_ID="$CUR_SID" BIONIC_CLAUDE_HOME="$WORK/nohome" bash "$HOOK" 2>/dev/null )
eq "7.3 unparsable payload: exit 0" "0" "$?"

section "8 — an open run, no engagement marker: one line, nothing else (AC-11)"
# A predecessor roster and stamp are seeded too — the positive control that
# proves the gate, not an empty fixture, is what silences the block: under
# today's rules (no open run) this exact disk state would have printed both.
P8=$(make_env 1s)
PLAN8="$(write_open_plan "$P8")"
roster_rows "$P8/.bionic/tmp/roster-$OLD_SID.state" "$OLD_SID" "W-DELTA"
write_stamp "$P8" "$OLD_SID"
S8_BEFORE=$(snap "$P8")
OUT=$(drive "$P8" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq    "8.1 exit 0" "0" "$(rc)"
has   "8.2 the one-line notice names the plan path" "$PLAN8" "$OUT"
has   "8.3 …and names the skill to invoke" "/bionic:canonical-sdlc" "$OUT"
eq    "8.4 exactly one line of output" "1" "$(printf '%s\n' "$OUT" | grep -c .)"
hasnt "8.5 no re-arm instruction" "re-arm" "$OUT"
hasnt "8.6 no adopt instruction" "adopt" "$OUT"
hasnt "8.7 no predecessor roster line" "roster-$OLD_SID.state" "$OUT"
hasnt "8.8 no predecessor stamps section" "predecessor stamps:" "$OUT"
eq    "8.9 the hook wrote nothing under .bionic" "$S8_BEFORE" "$(snap "$P8")"

section "9 — an open run + the engagement marker: today's block, unchanged (AC-12)"
# 3600s: see §1's comment — engaged fixtures reach the predecessor-roster/sweep
# code below the early-exit branches, so this section's fresh OLD_SID roster is
# exactly the R2 age-gate race described there.
P9=$(make_env 3600s)
write_open_plan "$P9" >/dev/null
roster_rows "$P9/.bionic/tmp/roster-$OLD_SID.state" "$OLD_SID" "W-DELTA"
plant_engaged "$P9" "$CUR_SID"
S9_BEFORE=$(snap "$P9")
OUT=$(drive "$P9" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq    "9.1 exit 0" "0" "$(rc)"
has   "9.2 the predecessor roster is listed, exactly as with no run open" \
  "roster-$OLD_SID.state" "$OUT"
has   "9.3 the re-arm sequence still prints: CronList first" "re-arm: CronList" "$OUT"
has   "9.4 …through adopt" "adopt" "$OUT"
hasnt "9.5 the bystander notice does not also print" \
  "invoke /bionic:canonical-sdlc to engage it" "$OUT"
eq    "9.6 the hook wrote nothing under .bionic" "$S9_BEFORE" "$(snap "$P9")"

section "10 — a symlink at the marker path reads as absent, same as no marker (AC-4)"
P10=$(make_env 1s)
PLAN10="$(write_open_plan "$P10")"
mkdir -p "$P10/.bionic/tmp"
: > "$P10/.bionic/tmp/real-engaged-file"
ln -s "$P10/.bionic/tmp/real-engaged-file" "$P10/.bionic/tmp/engaged-$CUR_SID.state"
OUT=$(drive "$P10" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq    "10.1 exit 0" "0" "$(rc)"
has   "10.2 a symlinked marker reads not-engaged: the notice prints" \
  "invoke /bionic:canonical-sdlc to engage it" "$OUT"
has   "10.3 …naming the plan path" "$PLAN10" "$OUT"
hasnt "10.4 …and not the re-arm block" "re-arm" "$OUT"

section "11 — no open run at all: the marker's presence or absence changes nothing (AC-11 pair)"
# The paired control the design calls for: no plan on disk, marker absent —
# today's behaviour, silence over a clean fixture. Marker presence must not
# matter either, since the gate above is conditioned on PLAN being non-empty.
P11=$(make_env 1s)
OUT=$(drive "$P11" startup "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq "11.1 exit 0" "0" "$(rc)"
eq "11.2 nothing on stdout" "" "$OUT"
P11b=$(make_env 1s)
plant_engaged "$P11b" "$CUR_SID"
OUT=$(drive "$P11b" startup "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq "11.3 exit 0 with the marker present too" "0" "$(rc)"
# RE-AUTHORED BY wave-21 T2 (REQ-2, AC-2.1). This row used to read "still nothing on stdout":
# the marker changed nothing when no run was open. It changes one thing now — an ENGAGED start
# prints the arm line whatever else is on disk, because the Patrol carries the session, not the
# run, and the model has no other surface that names the root to arm from (ADR-037 decision 1).
# No run, no notice, no predecessor block: the arm line is the whole output.
eq "11.4 no run, marker present: the arm line and nothing else" "1" \
  "$(printf '%s\n' "$OUT" | grep -c .)"
has "11.5 …and that one line is the arm line" "re-arm: CronList" "$OUT"

section "12 — two or more open runs (AC-5, S7)"

echo "--- 12a: two open plans, not engaged: the listing block, and nothing else ---"
P12=$(make_env 1s)
PLAN12A="$(write_open_plan "$P12" alpha)"
PLAN12B="$(write_open_plan "$P12" beta)"
PLAN12C="$(write_delivered_plan "$P12" gamma)"
roster_rows "$P12/.bionic/tmp/roster-$OLD_SID.state" "$OLD_SID" "W-EPSILON"
write_stamp "$P12" "$OLD_SID"
S12_BEFORE=$(snap "$P12")
OUT=$(drive "$P12" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq    "12a.1 exit 0" "0" "$(rc)"
has   "12a.2 the header names the count" "bionic: 2 open runs exist here" "$OUT"
has   "12a.3 …and the engage instruction" "invoke /bionic:canonical-sdlc" "$OUT"
has   "12a.4 …and the bind instruction" "session-poker.sh bind <plan>" "$OUT"
# DOCS-ROOT-RELATIVE, not absolute (review P3 / security F4, S10b). Every path in the
# listing shares one long prefix, and the instruction beside it already says where the
# paths resolve — `bind` takes either spelling. The absolute row is pinned ABSENT beside
# each relative row, because the relative string is a substring of the absolute one and a
# `has` on it alone would pass over an unchanged hook.
has   "12a.5 the first open plan is listed relative to the docs root" \
  "  ${PLAN12A#$P12/.bionic/docs/}" "$OUT"
hasnt "12a.5b …and not as an absolute path" "$P12/.bionic/docs/" "$OUT"
has   "12a.6 the second open plan is listed relative to the docs root" \
  "  ${PLAN12B#$P12/.bionic/docs/}" "$OUT"
eq    "12a.6b both listed paths are indented two spaces" "2" \
  "$(printf '%s\n' "$OUT" | grep -cE '^  .*\.plan\.md$')"
hasnt "12a.7 the CLOSED plan's path is absent" "$(basename "$PLAN12C")" "$OUT"
hasnt "12a.8 no roster text — the listing is the whole block" "predecessor rosters:" "$OUT"
hasnt "12a.9 …and no re-arm sequence either" "re-arm" "$OUT"
eq    "12a.10 wrote nothing" "$S12_BEFORE" "$(snap "$P12")"

echo ""
echo "--- 12b: one open plan, not engaged: today's singular line, byte-identical to §8 ---"
P12b=$(make_env 1s)
PLAN12b="$(write_open_plan "$P12b")"
S12b_BEFORE=$(snap "$P12b")
OUT=$(drive "$P12b" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq    "12b.1 exit 0" "0" "$(rc)"
has   "12b.2 the one-line notice names the plan path, exactly as §8.2 pins" "$PLAN12b" "$OUT"
has   "12b.3 …and names the skill to invoke, exactly as §8.3 pins" "/bionic:canonical-sdlc" "$OUT"
eq    "12b.4 exactly one line of output, exactly as §8.4 pins" "1" "$(printf '%s\n' "$OUT" | grep -c .)"
hasnt "12b.5 no count-style header" "open runs exist here" "$OUT"
eq    "12b.6 wrote nothing" "$S12b_BEFORE" "$(snap "$P12b")"

echo ""
echo "--- 12c: two open plans, engaged and bound-open to one: today's engaged block, no listing ---"
# 3600s: see §1's comment — a bound session is engaged too, so this also reaches
# the sweep below.
P12c=$(make_env 3600s)
PLAN12cA="$(write_open_plan "$P12c" alpha)"
PLAN12cB="$(write_open_plan "$P12c" beta)"
roster_rows "$P12c/.bionic/tmp/roster-$OLD_SID.state" "$OLD_SID" "W-ZETA"
plant_bound "$P12c" "$CUR_SID" "$PLAN12cA"
S12c_BEFORE=$(snap "$P12c")
OUT=$(drive "$P12c" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq    "12c.1 exit 0" "0" "$(rc)"
has   "12c.2 the predecessor roster is listed, exactly as an engaged session sees it" \
  "roster-$OLD_SID.state" "$OUT"
has   "12c.3 the re-arm sequence still prints" "re-arm: CronList" "$OUT"
hasnt "12c.4 no count-style listing" "open runs exist here" "$OUT"
hasnt "12c.5 the sibling (unbound) plan is not named" "$PLAN12cB" "$OUT"
eq    "12c.6 wrote nothing" "$S12c_BEFORE" "$(snap "$P12c")"

echo ""
echo "--- 12d: two open plans, engaged with an EMPTY (unbound) marker: the listing, then today's engaged block ---"
# 3600s: see §1's comment — engaged and unbound still reaches the sweep below.
P12d=$(make_env 3600s)
PLAN12dA="$(write_open_plan "$P12d" alpha)"
PLAN12dB="$(write_open_plan "$P12d" beta)"
roster_rows "$P12d/.bionic/tmp/roster-$OLD_SID.state" "$OLD_SID" "W-ETA"
plant_engaged "$P12d" "$CUR_SID"   # empty marker: engaged, unbound
S12d_BEFORE=$(snap "$P12d")
OUT=$(drive "$P12d" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq    "12d.1 exit 0" "0" "$(rc)"
has   "12d.2 the not-bound header names the count" \
  "bionic: 2 open runs exist here and this session is not bound to one" "$OUT"
has   "12d.3 …and the bind instruction" "session-poker.sh bind <plan>" "$OUT"
has   "12d.4 the first open plan is listed relative to the docs root" \
  "  ${PLAN12dA#$P12d/.bionic/docs/}" "$OUT"
hasnt "12d.4b …and not as an absolute path" "$P12d/.bionic/docs/" "$OUT"
has   "12d.5 the second open plan is listed relative to the docs root" \
  "  ${PLAN12dB#$P12d/.bionic/docs/}" "$OUT"
has   "12d.6 today's engaged roster block still follows — no early exit" \
  "roster-$OLD_SID.state" "$OUT"
has   "12d.7 …through the re-arm sequence" "re-arm: CronList" "$OUT"
eq    "12d.8 wrote nothing" "$S12d_BEFORE" "$(snap "$P12d")"

echo ""
echo "--- 12e: ten open plans: the listing is CAPPED at 8, with a trailer naming the rest ---"
# WHY A CAP (review P3, security F4 — S10b). A SessionStart hook's stdout is context the
# model pays for on `startup`, `clear`, `resume` AND `compact`. This repository's own tree
# already renders 60 paths (~6.8 KB, ~1,700 tokens) that a reader acts on at most one line
# of. `open_runs` itself stays uncapped — it is a membership predicate with three callers —
# so what is bounded here is the DISPLAY only, and the header still names the true count.
P12e=$(make_env 1s)
_i=1
while [ "$_i" -le 10 ]; do
  write_open_plan "$P12e" "p$_i" >/dev/null
  _i=$((_i + 1))
done
S12e_BEFORE=$(snap "$P12e")
OUT=$(drive "$P12e" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq    "12e.1 exit 0" "0" "$(rc)"
has   "12e.2 the header names the TRUE count, not the capped one" \
  "bionic: 10 open runs exist here" "$OUT"
eq    "12e.3 exactly 8 plan lines are listed" "8" \
  "$(printf '%s\n' "$OUT" | grep -cE '^  .*\.plan\.md$')"
has   "12e.4 …and one trailer line names the remainder" \
  "  … and 2 more — bind names any open plan" "$OUT"
hasnt "12e.5 no absolute path anywhere in the block" "$P12e/.bionic/docs/" "$OUT"
eq    "12e.6 wrote nothing" "$S12e_BEFORE" "$(snap "$P12e")"

echo ""
echo "--- 12f: three open plans: all three listed, and NO trailer ---"
# The paired negative for 12e: below the cap the trailer must not appear at all. Without
# this row a hook that printed "and 0 more" unconditionally would pass 12e.
P12f=$(make_env 1s)
_i=1
while [ "$_i" -le 3 ]; do
  write_open_plan "$P12f" "q$_i" >/dev/null
  _i=$((_i + 1))
done
S12f_BEFORE=$(snap "$P12f")
OUT=$(drive "$P12f" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq    "12f.1 exit 0" "0" "$(rc)"
has   "12f.2 the header names the count" "bionic: 3 open runs exist here" "$OUT"
eq    "12f.3 all three plan lines are listed" "3" \
  "$(printf '%s\n' "$OUT" | grep -cE '^  .*\.plan\.md$')"
hasnt "12f.4 …and no trailer line" "more — bind names any open plan" "$OUT"
eq    "12f.5 wrote nothing" "$S12f_BEFORE" "$(snap "$P12f")"

# Eight days ago: past the default 7d `live-window`, so `live_runs` excludes it while
# `open_runs` still counts it. No BIONIC_NOW_EPOCH pin needed — `backdate` moves the
# file's mtime itself, so the wall clock's real "now" already sees it as stale.
QUIET_AGO=$((8 * 86400))

section "13 — live vs open: the quiet-count line replaces the quiet listing (AC-3, S3)"

echo "--- 13a: 3 open, 1 live, not engaged: only the live plan is listed, plus a quiet-count line ---"
P13=$(make_env 1s)
PLAN13A="$(write_open_plan "$P13" alpha)"
PLAN13B="$(write_open_plan "$P13" beta)"
PLAN13C="$(write_open_plan "$P13" gamma)"
backdate "$PLAN13B" "$QUIET_AGO"
backdate "$PLAN13C" "$QUIET_AGO"
S13_BEFORE=$(snap "$P13")
OUT=$(drive "$P13" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq    "13a.1 exit 0" "0" "$(rc)"
has   "13a.2 the header still names the true OPEN count" "bionic: 3 open runs exist here" "$OUT"
has   "13a.3 the live plan is listed relative to the docs root" \
  "  ${PLAN13A#$P13/.bionic/docs/}" "$OUT"
hasnt "13a.4 the first quiet plan is NOT listed" "$(basename "$PLAN13B")" "$OUT"
hasnt "13a.5 the second quiet plan is NOT listed" "$(basename "$PLAN13C")" "$OUT"
has   "13a.6 one quiet-count line names the two quiet runs" \
  "bionic: 2 quiet open run(s) — bind names any of them" "$OUT"
eq    "13a.7 wrote nothing" "$S13_BEFORE" "$(snap "$P13")"

echo ""
echo "--- 13b: same shape, engaged and NOT bound: the quiet-count line still appears ---"
P13b=$(make_env 1s)
PLAN13bA="$(write_open_plan "$P13b" alpha)"
PLAN13bB="$(write_open_plan "$P13b" beta)"
backdate "$PLAN13bB" "$QUIET_AGO"
plant_engaged "$P13b" "$CUR_SID"
OUT=$(drive "$P13b" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq  "13b.1 exit 0" "0" "$(rc)"
has "13b.2 the not-bound header still fires" \
  "bionic: 2 open runs exist here and this session is not bound to one" "$OUT"
has "13b.3 the live plan is listed" "  ${PLAN13bA#$P13b/.bionic/docs/}" "$OUT"
hasnt "13b.4 the quiet plan is not listed" "$(basename "$PLAN13bB")" "$OUT"
has "13b.5 one quiet-count line" "bionic: 1 quiet open run(s) — bind names any of them" "$OUT"

echo ""
echo "--- 13c: all open runs live: no quiet-count line at all (anti-vacuity) ---"
P13c=$(make_env 1s)
write_open_plan "$P13c" alpha >/dev/null
write_open_plan "$P13c" beta >/dev/null
OUT=$(drive "$P13c" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
hasnt "13c.1 no quiet-count line when nothing is quiet" "quiet open run(s)" "$OUT"

section "14 — engaged and bound: the bound-run line names the plan and its step (AC-21, S3)"

echo "--- 14a: exactly one open run, engaged and bound to it: one line, nothing else ---"
P14=$(make_env 1s)
PLAN14="$(write_open_plan "$P14")"
plant_bound "$P14" "$CUR_SID" "$PLAN14"
S14_BEFORE=$(snap "$P14")
OUT=$(drive "$P14" startup "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq  "14a.1 exit 0" "0" "$(rc)"
has "14a.2 the bound line names the docs-root-relative plan and its current step" \
  "bionic: bound to ${PLAN14#$P14/.bionic/docs/} — current: 3" "$OUT"
# TWO LINES SINCE WAVE-11 ROW 1b, and the second one is the point of the split. The bound
# line names the run and its step; the line under it names the step FILE the governing skill
# tells the model to read at that step. The count is still pinned exactly, not loosened to
# "at least one" — a third line here would be predecessor state this fixture has none of,
# which is what 14a.3 has always been guarding.
# THREE SINCE wave-21 T2 (REQ-2, AC-2.1): the third is the arm line every engaged start now
# prints. Still pinned exactly — a fourth line would be predecessor state this fixture has none
# of, which is what this row has always guarded.
eq  "14a.3 exactly three lines — the bound line, its step-file pointer, the arm line; no predecessor state" \
  "3" "$(printf '%s\n' "$OUT" | grep -c .)"
has "14a.3c …the third is the arm line" "re-arm: CronList" "$OUT"
has "14a.3b the second line points at the step file for the plan's own current step" \
  "skills/canonical-sdlc/steps/3.md" "$OUT"
eq  "14a.4 wrote nothing" "$S14_BEFORE" "$(snap "$P14")"

echo ""
echo "--- 14b: the same fixture on resume and on compact: the bound line fires on every source ---"
for BSRC in resume compact; do
  OUT=$(drive "$P14" "$BSRC" "$CUR_SID" "$CUR_SID" "$CUR_SID")
  has "14b.$BSRC the bound line fires on source=$BSRC" \
    "bionic: bound to ${PLAN14#$P14/.bionic/docs/} — current: 3" "$OUT"
done

echo ""
echo "--- 14c: two open runs, engaged and bound to one: the bound line, no listing, roster unaffected ---"
P14c=$(make_env 1s)
PLAN14cA="$(write_open_plan "$P14c" alpha)"
PLAN14cB="$(write_open_plan "$P14c" beta)"
roster_rows "$P14c/.bionic/tmp/roster-$OLD_SID.state" "$OLD_SID" "W-THETA"
plant_bound "$P14c" "$CUR_SID" "$PLAN14cA"
OUT=$(drive "$P14c" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq    "14c.1 exit 0" "0" "$(rc)"
has   "14c.2 the bound line names the bound plan" \
  "bionic: bound to ${PLAN14cA#$P14c/.bionic/docs/} — current: 3" "$OUT"
hasnt "14c.3 the sibling (unbound) plan is not named" "$(basename "$PLAN14cB")" "$OUT"
hasnt "14c.4 no count-style listing" "open runs exist here" "$OUT"
has   "14c.5 the predecessor roster still prints alongside it" "roster-$OLD_SID.state" "$OUT"

section "15 — engaged, one live run, unbound: the bind line, and otherwise unchanged (S3 scope (c); wave-23 T13, critic C-4)"
# 3600s: see §1's comment — engaged, N==1, unbound also reaches the sweep below.
#
# C-4 (record/wave-23-fixit-1810/critic-43e45387.md). This branch printed NOTHING about the
# binding for an engaged session with `plan=none` and one open run, while the N>=2 branch
# listed the runs and the bind verb. Since D1 an unbound session's gates are inert and T13's
# engagement leaves a session unbound beside another live session's run, so the one-run root
# is exactly where an engaged session most needs to be told it is unbound. The line rides
# STDOUT, which is SessionStart's model-facing channel (this hook's own header), one header
# line plus one line per run, the shape §12 pins for two runs.
P15=$(make_env 3600s)
PLAN15="$(write_open_plan "$P15")"
roster_rows "$P15/.bionic/tmp/roster-$OLD_SID.state" "$OLD_SID" "W-IOTA"
plant_engaged "$P15" "$CUR_SID"
S15_BEFORE=$(snap "$P15")
OUT=$(drive "$P15" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq    "15.1 exit 0" "0" "$(rc)"
hasnt "15.2 no bound line — this session never bound" "bionic: bound to" "$OUT"
hasnt "15.3 no quiet-count line — nothing is quiet" "quiet open run(s)" "$OUT"
has   "15.4 the predecessor roster still prints, exactly as today" "roster-$OLD_SID.state" "$OUT"
eq    "15.5 wrote nothing" "$S15_BEFORE" "$(snap "$P15")"
has   "15.6 the bind line prints for the engaged unbound session (C-4)" \
  "bionic: 1 open run exists here and this session is not bound to it — bind with: bash" "$OUT"
has   "15.7 …naming the poker's bind verb" "/hooks/session-poker.sh bind <plan>" "$OUT"
has   "15.8 …and then the one run, docs-root-relative, on its own line" \
  "  ${PLAN15#$P15/.bionic/docs/}" "$OUT"
eq    "15.9 …on stdout, the model's channel: nothing of it on stderr" "0" \
  "$(errtext | grep -c 'not bound to it')"
eq    "15.10 …exactly one header line and one run line" "2" \
  "$(printf '%s\n' "$OUT" | grep -c -e 'not bound to it' -e "^  ${PLAN15#$P15/.bionic/docs/}\$")"
# the pair, one field apart: the SAME root with the session BOUND prints the bound line and
# no bind line (§14a's shape), so 15.6 measured the binding and not the root.
plant_bound "$P15" "$CUR_SID" "$PLAN15"
OUT=$(drive "$P15" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
has   "15.11 paired: bound on the same root, the bound line prints" "bionic: bound to" "$OUT"
hasnt "15.12 …and no bind line" "not bound to it" "$OUT"

section "15h — engaged, unbound, the one run HELD by a live session: the line names the holder (wave-23 T15, critic N-2)"
# N-2 (record/wave-23-fixit-1810/critic-d067c07d.md, the `held.sh` drive). §15's line offers the
# bare bind verb to every engaged unbound session — including the one engage.sh left unbound
# BECAUSE another live session holds the run (A-T13.4). On a resume or compaction that bare verb
# is the reflex bind A-T13.4 exists to prevent. So when the sole run is held by a LIVE session
# (the sweeper's predicate, as engage.sh asks it), the header names that holder's id prefix and
# says to bind only when resuming that run. Unheld, it is §15's line, unchanged.
HOLD_SID="40ld0000-aaaa-4bbb-8ccc-dddddddddddd"
P15h=$(make_env 3600s)
PLAN15h="$(write_open_plan "$P15h")"
plant_engaged "$P15h" "$CUR_SID"
plant_bound "$P15h" "$HOLD_SID" "$PLAN15h"
OUT=$(DRIVE_LIVE="$HOLD_SID" drive "$P15h" compact "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq    "15h.1 exit 0" "0" "$(rc)"
has   "15h.2 held: the header names the live holder by its id prefix" \
  "bionic: 1 open run exists here and live session ${HOLD_SID:0:8} holds it; this session is not bound to it" "$OUT"
has   "15h.3 …and says to bind only when resuming that run" \
  "/hooks/session-poker.sh bind <plan> only if this session is resuming that run" "$OUT"
hasnt "15h.4 …and the bare bind line (§15's) is not printed" \
  "bionic: 1 open run exists here and this session is not bound to it — bind with: bash" "$OUT"
has   "15h.5 …the run still listed on its own line" "  ${PLAN15h#$P15h/.bionic/docs/}" "$OUT"
eq    "15h.6 …exactly one header line and one run line, on stdout" "2" \
  "$(printf '%s\n' "$OUT" | grep -c -e 'not bound to it' -e "^  ${PLAN15h#$P15h/.bionic/docs/}\$")"
eq    "15h.7 …nothing of it on stderr" "0" "$(errtext | grep -c 'not bound to it')"
# the pair, one fact apart: the SAME root with the holder's pid file gone (dead) prints §15's
# line exactly, and no holder.
OUT=$(drive "$P15h" compact "$CUR_SID" "$CUR_SID" "$CUR_SID")
has   "15h.8 unheld (the holder is dead): §15's line, unchanged" \
  "bionic: 1 open run exists here and this session is not bound to it — bind with: bash" "$OUT"
hasnt "15h.9 …and no holder named" "holds it" "$OUT"
has   "15h.10 …and the run on its own line" "  ${PLAN15h#$P15h/.bionic/docs/}" "$OUT"

section "16 — 400 aged predecessor files: bounded, not a linear scan (AC-6.1, AC-6.2)"
# THE FIELD DEFECT (carry-over P9, REQ-6): both the roster loop (:427) and the
# patrol-stamp loop (:504) spawn a subprocess PER FILE (an `awk` for open_rows,
# a `stat` for the stamp's age) with no upper bound on how many predecessor
# files can accumulate under .bionic/tmp — measured ~10.4s at 400 dead sessions
# against the CLI's 10s hook timeout. This section plants exactly that shape
# and counts what the drives over it do (THE COUNT, below).
#
# WHAT MUST STILL WORK (AC-6.2): a predecessor this run has no reason to treat
# as settled — a FRESH roster/stamp pair under its own sid, never backdated —
# is read and listed exactly as it would be with zero aged files beside it, and
# THIS session's own files are still excluded exactly as every section above
# already proves. The 400 aged files are the ones REQ-6 allows the loops to
# skip; they are backdated 7 days (604800s), an age no interval/multiplier
# combination anywhere in this file's own constants could mistake for "still
# worth an individual read".
#
# 3600s, NOT a tiny interval: see §1's comment and §9/§12's own use of the same
# value — a generous interval keeps FRESH_SID's just-written files out of the
# auto-sweep's reach deterministically (the verb's `--window` defers a dead session
# whose own newest file is younger than one interval). A tiny interval here would
# race this section's own timing against whether that deferral applies, which is
# REQ-8's feature and not this section's subject — §16 is timing the two REPORT
# loops this task bounds.
P16=$(make_env 3600s)
DEAD_I=1
while [ "$DEAD_I" -le 400 ]; do
  DEAD_SID=$(printf 'dead0000-dead-dead-dead-%012d' "$DEAD_I")
  roster_rows "$P16/.bionic/tmp/roster-$DEAD_SID.state" "$DEAD_SID" "W-DEAD$DEAD_I"
  backdate "$P16/.bionic/tmp/roster-$DEAD_SID.state" 604800
  write_stamp "$P16" "$DEAD_SID"
  backdate "$P16/.bionic/tmp/patrol-$DEAD_SID.state" 604800
  DEAD_I=$((DEAD_I + 1))
done
FRESH_SID="fedcba98-7654-3210-fedc-ba9876543210"
roster_rows "$P16/.bionic/tmp/roster-$FRESH_SID.state" "$FRESH_SID" "W-FRESH"
write_stamp "$P16" "$FRESH_SID"
roster_rows "$P16/.bionic/tmp/roster-$CUR_SID.state" "$CUR_SID" "W-MINE"
write_stamp "$P16" "$CUR_SID"

# THE COUNT, NEVER THE CLOCK (wave-35 T11; REQ-2 AC-2.2, D11). This section used to time its
# drives and gate a ratio of two of them; it now counts what each drive does, with
# tests/hook-timeout.test.sh's tracer: every bash a drive starts sources a prelude through
# BASH_ENV that points xtrace at fd 87 (the hook uses 9 itself) with a marker in PS4, and the
# markers are counted as bytes. What REQ-6 bounded is the FORKS — an `awk` and a `stat` per
# predecessor file, then a `$( )` per predecessor — while the filtering loop that stays is pure
# builtins and runs once per file by design. So a fork is what is counted: an external command
# on the trace (the roster below), and a command run inside a subshell (`BASH_SUBSHELL` > 0,
# which PS4 carries). Both must come out the same at 8 predecessors and at 400.
# SS_TRACE_ROLE scopes the trace: `all` is every bash the drive starts; `sweep` is the sweep
# (`session-poker.sh`, which the hook starts) and what it starts, and nothing of the hook.
SS_PRELUDE="$WORK/ss-xtrace-prelude.sh"
cat > "$SS_PRELUDE" <<'PRELUDE'
# bash 3.2 sets `$0` to the shell, not the script, while BASH_ENV runs, so the sweep is known by
# its command line (one `ps` before tracing starts, never counted).
if [ "${SS_TRACING:-}" != 1 ]; then
  case "${SS_TRACE_ROLE:-}" in
    all) SS_TRACING=1; export SS_TRACING ;;
    sweep) case "$(ps -o args= -p $$ 2>/dev/null)" in
             *session-poker.sh\ sweep*) SS_TRACING=1; export SS_TRACING ;;
           esac ;;
  esac
fi
if [ "${SS_TRACING:-}" = 1 ]; then
  exec 87>>"$SS_TRACE_OUT"
  PS4='+|SSCOUNT|${BASH_SUBSHELL}|${BASH_SOURCE##*/}:${LINENO}| '
  if [ "${BASH_VERSINFO[0]}" -ge 5 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 1 ]; }; then
    BASH_XTRACEFD=87
  else
    exec 2>&87
    set -T
    trap 'exec 2>&87' DEBUG
  fi
  set -x
fi
PRELUDE
SS_TRACE="$WORK/ss-trace"
SS_EXTERNAL="jq grep awk sed cut tr git date stat find sort uniq head tail wc python3 basename dirname readlink realpath rm mkdir cat ls ps mv cp touch mktemp sleep env perl xargs"
ss_counts() {  # -> "<commands> <external> <in-subshell>" read off $SS_TRACE
  local all ext sub cmd c
  all="$(LC_ALL=C grep -o '|SSCOUNT|' "$SS_TRACE" 2>/dev/null | wc -l | tr -d ' ')"
  sub="$(LC_ALL=C grep -oE '\|SSCOUNT\|[1-9][0-9]*\|' "$SS_TRACE" 2>/dev/null | wc -l | tr -d ' ')"
  ext=0
  for cmd in $SS_EXTERNAL; do
    c="$(LC_ALL=C grep -oE "\|SSCOUNT\|[0-9]+\|[^| ]*\| ${cmd}( |\$)" "$SS_TRACE" 2>/dev/null | wc -l | tr -d ' ')"
    ext=$((ext + ${c:-0}))
  done
  printf '%s %s %s' "$all" "$ext" "$sub"
}
ss_count_drive() {  # <role> <hook> <project> -> stdout of the drive; counts in $WORK/ss-counts
  local keep="$HOOK"
  : > "$SS_TRACE"
  HOOK="$2"
  BASH_ENV="$SS_PRELUDE" SS_TRACE_OUT="$SS_TRACE" SS_TRACE_ROLE="$1" \
    drive "$3" clear "$CUR_SID" "$CUR_SID" "$CUR_SID"
  HOOK="$keep"
  ss_counts > "$WORK/ss-counts"
}

# THE REPORT, ALONE, FROM A COPY OF THE HOOK WITH NO POKER BESIDE IT. The hook sweeps only when
# `session-poker.sh` sits next to it (`[ -f "$SS_POKER" ]`), so a copy in a `hooks/` directory
# of its own, beside the real payload, runs every line of the report and starts no sweep at all
# — and nothing deletes the predecessors these drives read. (This used to be a drive with the
# sweep's bound set to 0, killed on its first poll: a race between the kill and the sweep's
# first deletions, and a trace whose length was the race's.)
SS_REPORT_ONLY="$WORK/report-only"
mkdir -p "$SS_REPORT_ONLY/hooks"
_ss_root="$(cd "$(dirname "$HOOK")/.." && pwd -P)"
[ -d "$_ss_root/payload" ] && ln -s "$_ss_root/payload" "$SS_REPORT_ONLY/payload"
[ -d "$_ss_root/scripts" ] && ln -s "$_ss_root/scripts" "$SS_REPORT_ONLY/scripts"
cp "$HOOK" "$SS_REPORT_ONLY/hooks/session-start.sh"
expect_false "16.0 the report-only copy has no poker beside it, so it starts no sweep" \
  test -e "$SS_REPORT_ONLY/hooks/session-poker.sh"

# A CONTROL AT SMALL n, the same drive over EIGHT aged predecessors instead of four hundred —
# eight being the real field pile-up this section's own comment below cites.
P16C=$(make_env 3600s)
CTL_I=1
while [ "$CTL_I" -le 8 ]; do
  CTL_SID=$(printf 'ctl00000-ctl0-ctl0-ctl0-%012d' "$CTL_I")
  roster_rows "$P16C/.bionic/tmp/roster-$CTL_SID.state" "$CTL_SID" "W-CTL$CTL_I"
  backdate "$P16C/.bionic/tmp/roster-$CTL_SID.state" 604800
  write_stamp "$P16C" "$CTL_SID"
  backdate "$P16C/.bionic/tmp/patrol-$CTL_SID.state" 604800
  CTL_I=$((CTL_I + 1))
done
roster_rows "$P16C/.bionic/tmp/roster-$CUR_SID.state" "$CUR_SID" "W-MINE"
write_stamp "$P16C" "$CUR_SID"

OUT16C=$(ss_count_drive all "$SS_REPORT_ONLY/hooks/session-start.sh" "$P16C")
read -r SS_C8 SS_X8 SS_S8 < "$WORK/ss-counts"
eq    "16.1c the control drive exits 0" "0" "$(rc)"
has   "16.1d …and it is the same report, listing the control predecessors" \
  "predecessor stamps:" "$OUT16C"
OUT=$(ss_count_drive all "$SS_REPORT_ONLY/hooks/session-start.sh" "$P16")
read -r SS_C400 SS_X400 SS_S400 < "$WORK/ss-counts"
echo "      (16.2 counts — 8 predecessors: $SS_C8 commands, $SS_X8 external, $SS_S8 in subshells; 400: $SS_C400, $SS_X400, $SS_S400)"

eq    "16.1 exit 0" "0" "$(rc)"
# 16.2 IS AC-6.1'S CRITERION, IN THE UNITS THAT CAUSED IT. The report loops cost ~10.4s at 400
# dead sessions because each file forked an `awk` and a `stat`; T16 then took a `$( )` per file
# out of both loops. A fork per predecessor is a count that grows from 8 to 400 on any machine.
expect_true "16.2a the tracer counted both report drives forking (${SS_X8} external commands at 8)" \
  test "${SS_X8:-0}" -gt 0 -a "${SS_C400:-0}" -gt "${SS_C8:-0}"
eq    "16.2 the report runs as many external commands over 400 aged predecessors as over 8: no fork per file (AC-6.1)" \
  "$SS_X8" "$SS_X400"
eq    "16.2b …and as many commands inside subshells: no \$( ) per file either" \
  "$SS_S8" "$SS_S400"
has   "16.3 the fresh predecessor roster is still listed" "roster-$FRESH_SID.state" "$OUT"
has   "16.4 the predecessor stamps section still appears" "predecessor stamps:" "$OUT"
has   "16.5 …naming the fresh predecessor by its short id" "${FRESH_SID:0:8}" "$OUT"
hasnt "16.6 THIS session's own roster is never listed as a predecessor" \
  "roster-$CUR_SID.state" "$OUT"
hasnt "16.7 THIS session's own stamp is never listed as a predecessor" \
  "  ${CUR_SID:0:8} " "$OUT"

# 16.4 WAS RED AT THE FLOOR FOR A REASON THAT IS NOT THE HOOK'S (wave-36 T48; D10; AC-4.1, AC-6.1).
# The hook printed `predecessor stamps:` — the floor's own quoted block carries it — and `has`
# said it was missing, because `has` piped the 61 KB report into `grep -qF` under `pipefail`:
# grep leaves at its first match, the printf still writing takes EPIPE, and the pipeline fails
# on a needle that is present (`printf: write error: Broken pipe`, session-start.test.sh:54,
# in the floor log). That race needs load to lose, so it is forced here: a haystack past any
# pipe buffer with the needle on its first line and SIGPIPE ignored, which makes the write error
# certain. `hasnt` had the same pipeline and failed the other way — a present needle read as
# absent, so the row PASSED. Each helper's verdict is captured from a subshell so the forced
# case is judged by these rows and not counted twice.
SS_BIG="$(printf 'needle-first-line\n'; head -c 300000 /dev/zero | tr '\0' 'x')"
SS_HAS_V="$(trap '' PIPE; has "probe" "needle-first-line" "$SS_BIG" 2>&1 | head -1)"
SS_HASNT_V="$(trap '' PIPE; hasnt "probe" "needle-first-line" "$SS_BIG" 2>&1 | head -1)"
eq    "16.4a has finds a needle on the first line of a haystack past the pipe buffer, with SIGPIPE ignored" \
  "PASS: probe" "$SS_HAS_V"
eq    "16.4b hasnt reports that same present needle as present: a broken pipe cannot read it as absent" \
  "FAIL: probe" "$SS_HASNT_V"
has   "16.4c …and a needle truly absent from the same haystack still passes hasnt" \
  "PASS: probe" "$(trap '' PIPE; hasnt "probe" "needle-not-there" "$SS_BIG" 2>&1 | head -1)"

# AND THE SECOND DRIVE IS THE WHOLE HOOK, sweep included. The sweep is bounded
# (`BIONIC_SWEEP_BOUND_SECONDS`, default 10, hooks/session-start.sh), and the bound is the one
# clock this section cannot remove: it is the hook's, and §17 proves what it does when it fires.
# Here it is set past any sweep's reach, so the drive's outcome is the sweep's own and not the
# machine's — whether a loaded runner let four hundred deletions finish inside ten seconds was
# the question rows 16.9 and 16.11 used to branch on. The trace covers the sweep alone
# (SS_TRACE_ROLE=sweep): the hook's poll loop counts its own ticks, which is the bound's pace.
SS_FAR=86400
OUT16BC=$(BIONIC_SWEEP_BOUND_SECONDS=$SS_FAR ss_count_drive sweep "$HOOK" "$P16C")
read -r SS_W8 SS_WX8 SS_WS8 < "$WORK/ss-counts"
OUT16B=$(BIONIC_SWEEP_BOUND_SECONDS=$SS_FAR ss_count_drive sweep "$HOOK" "$P16")
read -r SS_W400 SS_WX400 SS_WS400 < "$WORK/ss-counts"
echo "      (16.8 sweep counts — 8 dead sessions: $SS_W8 commands, $SS_WX8 external, $SS_WS8 in subshells; 400: $SS_W400, $SS_WX400, $SS_WS400)"

SS_TIMEOUT="$(jq -r '.hooks.SessionStart[]?.hooks[]?
  | select(.command | test("session-start\\.sh$")) | .timeout' \
  "${BIONIC_HOOKS_DIR}/hooks.json" 2>/dev/null | head -1)"
case "$SS_TIMEOUT" in ''|*[!0-9]*) SS_TIMEOUT="" ;; esac
expect_eq "16.8a hooks.json declares this hook's CLI timeout, and it is readable" "yes" \
  "$([ -n "$SS_TIMEOUT" ] && echo yes || echo no)"
expect_true "16.8 the tracer counted both sweeps, and the larger one did more (${SS_W8:-0} commands over 8 dead sessions, ${SS_W400:-0} over 400)" \
  test "${SS_W8:-0}" -gt 0 -a "${SS_W400:-0}" -gt "${SS_W8:-0}"
# 16.8b IS THE SAME DESIGN BUDGET, IN COMMANDS. Deleting four hundred dead sessions is work done
# per session, so the sweep's count grows with them, as its seconds did; what T22 bounded was
# its share beside the report it is bundled with — under eight times — and a ratio of two counts
# of the same fixture is one no machine can move (it read 5.8-6.0 in seconds).
expect_true "16.8b …and the sweep of 400 dead sessions runs under eight times the commands of the report over them (${SS_W400:-?} against ${SS_C400:-?})" \
  test "${SS_C400:-0}" -gt 0 -a "${SS_W400:-0}" -lt "$((8 * ${SS_C400:-0}))"
SS_MARKER="$P16/.bionic/tmp/sweep-failed.state"
SS_RESIDUE="$P16/.bionic/tmp/patrol-dead0000-dead-dead-dead-000000000001.state"
# THE POSITIVE CONTROL FOR THE NEGATIVES BELOW: a drive that printed nothing at all would
# satisfy any `hasnt` over its output. This row proves $OUT16B is a real render.
has   "16.8c the whole-hook drive printed its block, so a row reading that output is reading something" \
  "predecessor stamps:" "$OUT16B"
# THE SWEEP'S OUTCOME, NO LONGER AN INPUT. 16.9 and 16.11 used to read the sweep-failed marker
# and branch: a sweep the bound cut off (on a loaded floor, 17.6 s for the whole drive) took
# the other arm. With the bound out of reach the sweep returns, so the arm is fixed and both
# rows assert it on every machine. The cut-off arm has its own drive below, with the bound at 0.
expect_false "16.9 the sweep returned, so the aged residue is gone at four hundred sessions' scale (REQ-8)" \
  test -e "$SS_RESIDUE"
expect_true "16.10 …while the fresh predecessor, inside one interval, is deferred" \
  test -f "$P16/.bionic/tmp/patrol-$FRESH_SID.state"
expect_false "16.11 …and nothing failed on the way: no sweep-failed marker" test -e "$SS_MARKER"
hasnt "16.11b …and the hook told the reader nothing about a sweep failure" \
  "the automatic dead-session sweep failed" "$OUT16B"
# THE CUT-OFF ARM, ON PURPOSE: the bound at 0 is spent before the first poll, so the sweep is
# stopped wherever it got to. What survives being cut off is the EXPLANATION — the marker with
# rc=124 (a bound, not a refusal) and the same rc in the hook's one line — and that is what is
# asserted; which predecessors the sweep reached first is not.
P16K=$(make_env 3600s)
KIL_I=1
while [ "$KIL_I" -le 8 ]; do
  KIL_SID=$(printf 'kil00000-kil0-kil0-kil0-%012d' "$KIL_I")
  roster_rows "$P16K/.bionic/tmp/roster-$KIL_SID.state" "$KIL_SID" "W-KIL$KIL_I"
  backdate "$P16K/.bionic/tmp/roster-$KIL_SID.state" 604800
  write_stamp "$P16K" "$KIL_SID"
  backdate "$P16K/.bionic/tmp/patrol-$KIL_SID.state" 604800
  KIL_I=$((KIL_I + 1))
done
OUT16K=$(BIONIC_SWEEP_BOUND_SECONDS=0 drive "$P16K" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
expect_regex "16.12 a sweep cut off by its bound leaves a marker naming the bound, rc=124" \
  'sweep-failed/v1\|at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z\|rc=124' \
  "$(cat "$P16K/.bionic/tmp/sweep-failed.state" 2>/dev/null)"
has   "16.13 …and the hook tells the READER so, in its one line, carrying the same rc (AC-R2.4)" \
  "bionic: the automatic dead-session sweep failed (rc=124)" "$OUT16K"


section "17 — the sweep's own bound: the fork's noise, and the bound without a group (T23)"
#
# THE SAME DEFECT AS T22, ONE LAYER UP. `ss_bounded_sweep` in the hook is a deliberate
# local copy of `detect_bounded` (payload/scripts/lib/detect.sh) — this hook's loader wants
# four libraries, not five — and it carried both of the faults T22 fixed in the original:
#
#   (1) the FORKING SHELL's stderr was this hook's own, so bash's
#       `child setpgid (N to N): Operation not permitted` — which bash prints from inside
#       the fork wherever the kernel refuses the new process group — would land on a
#       SessionStart hook's stderr, i.e. in front of the user at the top of a session;
#   (2) the timeout arm signalled `-$pid`, a process group the job leads only where that
#       same setpgid SUCCEEDED. Where it is refused the group kill fails, the old
#       `|| kill -TERM $pid` fallback TERMs the direct child alone, and the sweep's
#       grandchildren survive the bound — and `sweep` is `bash session-poker.sh`, which
#       forks, so the grandchild is not hypothetical.
#
# WHAT CAN AND CANNOT BE PINNED HERE, SAID PLAINLY. NO FIXTURE CAN REFUSE setpgid ON THIS
# MACHINE: T22 measured 960 forks and eight parallel doctor-suite runs under this harness
# and produced zero warnings. So the noise half is pinned STRUCTURALLY — the fork must run
# inside a compound carrying its own stderr — beside a behavioural trio proving that
# isolation is SURGICAL (scoped to the compound) rather than a blanket discard laid over
# the hook, which is the fix a later reader is most likely to reach for and the one that
# would silence lib/session.sh's divergence warning in §4.6 along with it.
#
# THE KILL HALF NEEDS NO SEAM. A background job started WITHOUT `set -m` is in its caller's
# process group, which is exactly where a refusal leaves it; the arm reaches that state by
# not asking for a group rather than by substituting anything the code under test reads,
# and it asserts the precondition (`leader=no`) before asserting the reap.
#
# THE SUBJECT IS THE REAL FUNCTION. The hook is a script, not a library, so its bound
# helpers are extracted out of it with `awk` and `eval`ed into each driver — the
# tests/lib/swept-marker.sh idiom, for the same reason: a second spelling of the code under
# test can only ever pass. The extraction is CHECKED; reformat the hook and the check fails
# loudly rather than this section passing over nothing.

S17_LIB="$WORK/s17-bound.sh"
{
  grep -m1 '^SS_POLL_TICKS_PER_SEC=' "$HOOK"
  awk '/^ss_bound_kill_tree\(\)/,/^\}/' "$HOOK"
  awk '/^ss_bound_kill\(\)/,/^\}/'      "$HOOK"
  awk '/^ss_bounded_sweep\(\)/,/^\}/'   "$HOOK"
} > "$S17_LIB"
# Only the two that exist BEFORE this task are hard preconditions. The kill helper's
# absence is the RED this section was written against, and it is reported by the drivers
# below as a failing arm — never as a suite that refused to run.
grep -q '^SS_POLL_TICKS_PER_SEC=' "$S17_LIB" || {
  echo "session-start §17: no '^SS_POLL_TICKS_PER_SEC=' line in $HOOK — the tick constant could not be extracted (the file was reformatted, or the name moved)." >&2; exit 1; }
grep -q '^ss_bounded_sweep()' "$S17_LIB" || {
  echo "session-start §17: no '^ss_bounded_sweep()' definition in $HOOK — the bounded runner could not be extracted (the file was reformatted, or the name moved)." >&2; exit 1; }

# ---- the structural half: the fork's own stderr -------------------------------------
# These are the pins that fail if the shell's job-control warning can reach this hook's
# stderr again. Remove either and every behavioural arm below goes on passing on a machine
# where setpgid succeeds — which is exactly how this defect reached a floor in detect.sh.
expect_true "17.1 the sweep's fork runs inside a compound with its OWN stderr, so a shell job-control warning cannot reach the hook" \
  /usr/bin/grep -q '} 9>&2 2>/dev/null' "$HOOK"
expect_true "17.2 …and the hook's real stderr is carried on fd 9 and CLOSED in the child, never inherited by the sweep" \
  /usr/bin/grep -q '2>/dev/null 9>&- &' "$HOOK"

# ---- the behavioural trio: pass-through, and isolation that is surgical --------------
cat > "$WORK/s17-poker.sh" <<'S17POKER'
#!/bin/bash
# `ss_bounded_sweep` invokes `bash <poker> sweep`; the verb is ignored here.
echo SWEEP_STDOUT_OK
echo SWEEP_SAID_THIS >&2
exit "${S17_POKER_RC:-0}"
S17POKER

cat > "$WORK/s17-passthru.sh" <<'S17PT'
#!/bin/bash
# $1 = the extracted bound helpers, $2 = the poker stub, $3 = a root to cd into.
. "$1" || { echo "source-failed"; exit 2; }
BIONIC_ROOT="$3"
echo CALLER_STDERR_BEFORE >&2
S17_OUT="$(ss_bounded_sweep "$2" 5)"; S17_RC=$?
echo CALLER_STDERR_AFTER >&2
# Is the carrier still open in the CALLER? It must not be: `} 9>&2` scopes it to the
# compound, where an `exec 9>&2` (or an `exec 2>/dev/null`) would leak it over the hook.
fd9=no; { : >&9; } 2>/dev/null && fd9=yes
echo "out=$S17_OUT rc=$S17_RC fd9_open=$fd9"
S17PT

S17_E1="$WORK/s17-passthru.err"
S17_R1="$(bash "$WORK/s17-passthru.sh" "$S17_LIB" "$WORK/s17-poker.sh" "$WORK" 2>"$S17_E1")"
has "17.3 the sweep's stdout is passed through unchanged" "out=SWEEP_STDOUT_OK" "$S17_R1"
has "17.4 …and its exit status is mirrored" "rc=0" "$S17_R1"
hasnt "17.5 …while the sweep's OWN stderr never reaches this hook's stderr, as it never has: a subprocess's noise is not the user's business at a session start" \
  "SWEEP_SAID_THIS" "$(cat "$S17_E1")"
has "17.6 the hook's own stderr is still live BEFORE the bounded fork — the discard is the fork's, not the hook's" \
  "CALLER_STDERR_BEFORE" "$(cat "$S17_E1")"
has "17.7 …and still live AFTER it: nothing here is an \`exec 2>/dev/null\` over the whole hook" \
  "CALLER_STDERR_AFTER" "$(cat "$S17_E1")"
has "17.8 …and the fd-9 carrier is scoped to the compound, not left open on the hook" \
  "fd9_open=no" "$S17_R1"

S17_R1B="$(S17_POKER_RC=7 bash "$WORK/s17-passthru.sh" "$S17_LIB" "$WORK/s17-poker.sh" "$WORK" 2>/dev/null)"
has "17.9 a failing sweep's own exit status still reaches the caller, which is what the sweep-failed marker is written from" \
  "rc=7" "$S17_R1B"

# ---- the kill half, behavioural, on a stand-in with no seam -------------------------
cat > "$WORK/s17-kid.sh" <<'S17KID'
#!/bin/sh
# A job with a grandchild — the shape `sweep` really has (it is `bash session-poker.sh`,
# which forks), and the shape a bound that signals only the direct child fails to stop.
sleep 40 &
echo $! > "$1"
wait
S17KID

cat > "$WORK/s17-nogroup.sh" <<'S17NG'
#!/bin/bash
# The refused-setpgid stand-in: a background job started WITHOUT `set -m`, which leaves it
# in its caller's process group — the same place a refusal leaves it.
. "$1" || { echo "source-failed"; exit 2; }
# NAMED BEFORE IT IS CALLED. An absent helper is a missing command, which bash reports on a
# stderr this driver discards and then walks straight past — the arm would then measure a
# 40-second `wait` and read as a pass. Say so instead, and let both arms fail. (T22 found
# exactly this vacuity in its own first driver; it is not hypothetical either.)
command -v ss_bound_kill >/dev/null 2>&1 || { echo "kill_helper=missing"; exit 3; }
gcfile="$2"; kidscript="$3"; rm -f "$gcfile"
sh "$kidscript" "$gcfile" </dev/null >/dev/null 2>&1 &
kid=$!
sleep 1
kid_pgid="$(ps -o pgid= -p "$kid" 2>/dev/null | tr -d ' ')"
gc="$(cat "$gcfile" 2>/dev/null)"
leader=no; [ "$kid_pgid" = "$kid" ] && leader=yes
ss_bound_kill "$kid"
wait "$kid" 2>/dev/null
sleep 1
alive=no
if [ -n "$gc" ] && kill -0 "$gc" 2>/dev/null; then alive=yes; kill -TERM "$gc" 2>/dev/null; fi
echo "kid=$kid kid_pgid=$kid_pgid leader=$leader grandchild=$gc grandchild_alive=$alive"
S17NG

S17_NG="$(bash "$WORK/s17-nogroup.sh" "$S17_LIB" "$WORK/s17-gc" "$WORK/s17-kid.sh" 2>/dev/null)"
has "17.10 the stand-in really is the no-group state: the job does not lead a group of its own" \
  "leader=no" "$S17_NG"
has "17.11 …and the bound reaps its grandchild there anyway, where the group signal alone reached nothing" \
  "grandchild_alive=no" "$S17_NG"
echo "      (no-group arm: $S17_NG)"

# ---- end to end: a sweep that outruns its bound ------------------------------------
cat > "$WORK/s17-poker-hang.sh" <<'S17PH'
#!/bin/bash
# A sweep that never returns, with a grandchild of its own.
sleep 40 &
echo $! > "$S17_GCFILE"
wait
S17PH

cat > "$WORK/s17-timeout.sh" <<'S17TO'
#!/bin/bash
# $1 = helpers, $2 = grandchild-pid file, $3 = the hanging poker, $4 = root to cd into.
. "$1" || { echo "source-failed"; exit 2; }
BIONIC_ROOT="$4"
gcfile="$2"; rm -f "$gcfile"
export S17_GCFILE="$gcfile"
ss_bounded_sweep "$3" 2 >/dev/null 2>/dev/null
rc=$?
gc="$(cat "$gcfile" 2>/dev/null)"
sleep 1
alive=no
if [ -n "$gc" ] && kill -0 "$gc" 2>/dev/null; then alive=yes; kill -TERM "$gc" 2>/dev/null; fi
echo "rc=$rc grandchild=$gc grandchild_alive=$alive"
S17TO

S17_TO="$(bash "$WORK/s17-timeout.sh" "$S17_LIB" "$WORK/s17-gc2" "$WORK/s17-poker-hang.sh" "$WORK" 2>/dev/null)"
has "17.12 a sweep that outruns its bound is cut off, and says so with 124" "rc=124" "$S17_TO"
# 17.13 COUNTS THE POLLS, NOT THE SECONDS. The bound is a number of ticks
# (`max_ticks = limit * SS_POLL_TICKS_PER_SEC`), so a wrapper that stops at its bound polls
# exactly that many times and then cuts the sweep off, while one that waited at the sweep's own
# pace would poll until the sweep's forty seconds ran out. The same drive, traced, says which:
# every `sleep` the poll loop ran is a line of the trace.
S17_TPS="$(sed -n 's/^SS_POLL_TICKS_PER_SEC=\([0-9][0-9]*\).*/\1/p' "$S17_LIB")"
: > "$SS_TRACE"
BASH_ENV="$SS_PRELUDE" SS_TRACE_OUT="$SS_TRACE" SS_TRACE_ROLE=all \
  bash "$WORK/s17-timeout.sh" "$S17_LIB" "$WORK/s17-gc3" "$WORK/s17-poker-hang.sh" "$WORK" >/dev/null 2>&1
S17_POLLS="$(LC_ALL=C grep -oE '\|SSCOUNT\|[0-9]+\|s17-bound\.sh:[0-9]+\| sleep 0\.1' "$SS_TRACE" | wc -l | tr -d ' ')"
expect_true "17.13a the tick constant was read from the hook ($S17_TPS a second)" \
  test -n "$S17_TPS"
expect_eq "17.13 …inside the bound rather than at the sweep's own pace: it polled exactly its 2 s of ticks, then cut the sweep off" \
  "$((2 * ${S17_TPS:-0}))" "$S17_POLLS"
has "17.14 …and its grandchild is not left running on the machine afterwards" \
  "grandchild_alive=no" "$S17_TO"
echo "      (timeout arm: $S17_TO, bound=2s, sweep sleeps 40s, polls=$S17_POLLS)"

section "18 — a predecessor's open rows are the one close predicate's (epic-23 wave-20 T17, REQ-10; D10)"
# THE DEFECT (T2's carry-over). This hook's open-row count closed a name on a
# `landing-swept/v1|…|state=MET` marker OR on any ack of the name, ever, while the dispatch
# wall, the sweeper, the stop wall and the tick's adopt fold close it only on an ack stamped
# after its latest launch (`roster_open_names`). So after a /clear the block could tell the
# operator a predecessor held nothing open while every wall held its name open — or the
# reverse, for a name acked and dispatched again. One predecessor roster per history, and one
# block reads all four:
#   MET-ONLY  dispatched, a MET marker, never acked        -> open  (was closed)
#   AGAIN     dispatched, acked, dispatched again          -> open  (was closed)
#   DONE      dispatched, acked after the launch           -> closed
#   SAMESEC   an ack in the launch's own second            -> open  (cannot be ordered)
# DONE is the paired positive: without a history that closes, "open" everywhere would pass
# on a hook that had stopped closing anything.
P18=$(make_env 3600s)
S18_MET="18181818-0000-4000-8000-00000000000a"
S18_AGAIN="18181818-0000-4000-8000-00000000000b"
S18_DONE="18181818-0000-4000-8000-00000000000c"
S18_SAME="18181818-0000-4000-8000-00000000000d"
roster_rows "$P18/.bionic/tmp/roster-$S18_MET.state" "$S18_MET" "W-METONLY"
swept "$P18/.bionic/tmp/roster-$S18_MET.state" "$S18_MET" "W-METONLY"
roster_rows "$P18/.bionic/tmp/roster-$S18_AGAIN.state" "$S18_AGAIN" "W-AGAIN"
acked "$P18" "$S18_AGAIN" "W-AGAIN"
roster_row_fixture status=intended session="$S18_AGAIN" name=W-AGAIN agent_id= \
  launched_at=2026-09-02T22:00:00Z model= deliverable= >> "$P18/.bionic/tmp/roster-$S18_AGAIN.state"
roster_rows "$P18/.bionic/tmp/roster-$S18_DONE.state" "$S18_DONE" "W-DONE"
swept "$P18/.bionic/tmp/roster-$S18_DONE.state" "$S18_DONE" "W-DONE"
acked "$P18" "$S18_DONE" "W-DONE"
roster_rows "$P18/.bionic/tmp/roster-$S18_SAME.state" "$S18_SAME" "W-SAMESEC"
acked "$P18" "$S18_SAME" "W-SAMESEC" 2026-09-02T20:00:00Z
S18_BEFORE=$(snap "$P18")
OUT=$(drive "$P18" clear "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq    "18.1 exit 0" "0" "$(rc)"
has   "18.2 a MET marker with no ack closes nothing: the predecessor is listed, 1 open row" \
  "${S18_MET:0:8} — 1 open row(s) — roster-$S18_MET.state" "$OUT"
has   "18.3 acked and dispatched again: the name is open again" \
  "${S18_AGAIN:0:8} — 1 open row(s) — roster-$S18_AGAIN.state" "$OUT"
hasnt "18.4 acked after its launch: closed, so the roster is not listed" \
  "roster-$S18_DONE.state" "$OUT"
has   "18.5 an ack in the launch's own second closes nothing" \
  "${S18_SAME:0:8} — 1 open row(s) — roster-$S18_SAME.state" "$OUT"
eq    "18.6 the hook wrote nothing under .bionic" "$S18_BEFORE" "$(snap "$P18")"

# ONE PREDICATE, NOT A THIRD SPELLING. The behaviour above is the proof; this names where it
# lives, so a private ack or MET set regrown in the hook fails here as well as in the field.
eq    "18.7 the hook's open-row count is the roster library's (roster_open_counts)" "yes" \
  "$(grep -q '| roster_open_counts' "$HOOK" && echo yes || echo no)"
eq    "18.8 …and the hook keeps no MET close of its own" "0" \
  "$(grep -c 'state") == "MET"' "$HOOK" | tr -d ' ')"

section "19 — every engaged start prints the arm line, from this hook's root (wave-21 T2, REQ-2, AC-2.1; D2)"
# THE DEFECT (triage-C §R2; seed 2 "related defect 2"). The arm line printed only inside the
# predecessor block, so an engaged start on a clean project — a `compact` of a run with no
# /clear residue — printed nothing, and the model resolved the plugin root from the CLI's
# registry instead. On a directory-source install the registry can name an older build than
# the tree the hooks run from (measured: 1.8.6 cache vs the 1.8.7 tree, the two pokers
# differing), so the Patrol ticked an old poker against new walls. The fix: the hook prints the
# finished arm command on EVERY engaged start, its path baked from its own directory.
#
# PAIRED CONTROLS. 19a is the clean engaged start; §2/§11.2 are the clean NOT-engaged start,
# still silent. 19c plants a registry naming another root WITH a poker in it, so a hook that
# read the registry would have a real path to print — and pins the arm line present beside the
# absence, so the absence cannot pass over a hook that printed nothing.
S19_PROMPT="$(CLAUDE_CODE_SESSION_ID="$CUR_SID" bash "$S1_POKER" prompt 2>/dev/null)"

echo "--- 19a: engaged, no run, no predecessor state, on compact: exactly one arm line ---"
P19=$(make_env 1s)
plant_engaged "$P19" "$CUR_SID"
S19_BEFORE=$(snap "$P19")
OUT=$(drive "$P19" compact "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq    "19a.1 exit 0" "0" "$(rc)"
eq    "19a.2 exactly one arm line" "1" "$(printf '%s\n' "$OUT" | grep -c '^re-arm: ')"
has   "19a.3 the arm line, exactly, baking \$S1_POKER" \
  "re-arm: CronList → delete every job whose prompt begins with bionic-patrol session= → CronCreate, recurring every 1s, with the prompt \`$S19_PROMPT\` → bash $S1_POKER arm" "$OUT"
hasnt "19a.4 no predecessor block title — nothing was left here" "bionic session-start (source:" "$OUT"
hasnt "19a.5 no adopt line — there is nothing to adopt" "adopt:" "$OUT"
eq    "19a.6 wrote nothing" "$S19_BEFORE" "$(snap "$P19")"

echo "--- 19b: the same clean engaged project on every source ---"
for S19SRC in startup clear resume; do
  OUT=$(drive "$P19" "$S19SRC" "$CUR_SID" "$CUR_SID" "$CUR_SID")
  has "19b.$S19SRC the arm line prints on source=$S19SRC" "bash $S1_POKER arm" "$OUT"
done

echo "--- 19c: a registry naming another root: the line still names this hook's own root ---"
P19c=$(make_env 1s)
plant_engaged "$P19c" "$CUR_SID"
S19_REG="$WORK/registry-home"
S19_OTHER="$S19_REG/plugins/cache/bionic/bionic/1.8.6"
mkdir -p "$S19_OTHER/hooks" "$S19_OTHER/scripts/lib"
cp "$S1_POKER" "$S19_OTHER/hooks/session-poker.sh"
printf '{"version":2,"plugins":{"bionic@bionic":[{"scope":"user","installPath":"%s","version":"1.8.6"}]}}\n' \
  "$S19_OTHER" > "$S19_REG/plugins/installed_plugins.json"
OUT=$(
  export CLAUDE_CONFIG_DIR="$S19_REG" BIONIC_PLUGINS_DIR="$S19_REG/plugins"
  drive "$P19c" compact "$CUR_SID" "$CUR_SID" "$CUR_SID"
)
eq    "19c.1 exit 0" "0" "$(rc)"
has   "19c.2 the arm line names this hook's own poker" "bash $S1_POKER arm" "$OUT"
hasnt "19c.3 …and the registry's root appears nowhere in the output" "$S19_OTHER" "$OUT"

echo "--- 19d: the interval is the poker's: 20m reads as 1200s and its cron expression ---"
P19d=$(make_env 20m)
plant_engaged "$P19d" "$CUR_SID"
OUT=$(drive "$P19d" compact "$CUR_SID" "$CUR_SID" "$CUR_SID")
has   "19d.1 CronCreate names the configured interval and its cron spelling" \
  "CronCreate, recurring every 1200s (cron */20 * * * *), with the prompt" "$OUT"

echo "--- 19e: not engaged, no run, no predecessor state: still silent (the paired control) ---"
P19e=$(make_env 1s)
OUT=$(drive "$P19e" compact "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq    "19e.1 nothing on stdout" "" "$OUT"

section "20 — the standing decision line: in every session, run or no run (T27, AC-11.2)"
# The always-loaded rule sits in canonical-sdlc, which loads only inside a run, so a session with
# no run open answered a choice between approaches in prose (T19). The hook says it in every
# session it runs in. `drive` strips the line from what it returns; the raw stdout is last.out.
raw() { cat "$WORK/last.out"; }
P20a=$(make_env 1s)
drive "$P20a" startup "$CUR_SID" "$CUR_SID" "$CUR_SID" >/dev/null
has   "20.1 a project with no run: the line is on stdout" "$STANDING_MARK" "$(raw)"
has   "20.2 …and tells the session to invoke the skill" "bionic:decision skill — invoke it" "$(raw)"
eq    "20.3 …as exactly one line" "1" "$(raw | grep -cF -- "$STANDING_MARK")"
eq    "20.4 …and it is the only line (nothing else to report)" "1" "$(raw | grep -c .)"
P20b=$(make_env 1s)
write_open_plan "$P20b" >/dev/null
drive "$P20b" startup "$CUR_SID" "$CUR_SID" "$CUR_SID" >/dev/null
has   "20.5 an open run, session not engaged: the line is there" "$STANDING_MARK" "$(raw)"
has   "20.6 …beside the run notice (positive control: the notice is still printed)" "/bionic:canonical-sdlc" "$(raw)"
P20c=$(make_env 3600s)
write_open_plan "$P20c" >/dev/null
plant_engaged "$P20c" "$CUR_SID"
drive "$P20c" startup "$CUR_SID" "$CUR_SID" "$CUR_SID" >/dev/null
has   "20.7 an open run, session engaged: the line is there" "$STANDING_MARK" "$(raw)"
eq    "20.8 …once" "1" "$(raw | grep -cF -- "$STANDING_MARK")"
P20d=$(mktemp -d "$WORK/bare.XXXXXX")
drive "$P20d" startup "$CUR_SID" "$CUR_SID" "$CUR_SID" >/dev/null
has   "20.9 no .bionic anywhere above the cwd: the line is there" "$STANDING_MARK" "$(raw)"
eq    "20.10 …and the hook still created nothing" "" "$(ls -A "$P20d")"
eq    "20.11 …and drive's returned report is empty (the line is not part of it)" "" "$(drive "$P20d" startup "$CUR_SID" "$CUR_SID" "$CUR_SID")"

section "21 — the load record: what this session loaded, keyed by its id (wave-36 T1, D7; AC-1.1)"
# THE RECORD (spec D7, ADR-055). A session started with `--plugin-dir <checkout>/payload` runs the
# checkout; the start hook is the one bionic code that runs at load, so it writes what was loaded:
# `.bionic/tmp/loaded-<sid>.state` holding `root=` (CLAUDE_PLUGIN_ROOT), `commit=` when that root is a
# checkout, `started=`, and one `<sha256> <path>` line per file of hooks/hooks.json, skills/**/*.md,
# agents/**/*.md and commands/*.md. The fixture is shaped like this repository: payload/hooks and
# payload/agents are links to the repo's own directories, so a reader that does not follow links
# misses them. The expected set is spelled here file by file, never by the hook's own glob.
L_REPO=$(mktemp -d "$WORK/plugin.XXXXXX")
mkdir -p "$L_REPO/hooks" "$L_REPO/agents/sub" "$L_REPO/payload/.claude-plugin" \
  "$L_REPO/payload/skills/x/steps" "$L_REPO/payload/commands/sub"
printf '{"name":"bionic","version":"9.9.9"}\n' > "$L_REPO/payload/.claude-plugin/plugin.json"
printf '{"hooks":{}}\n'   > "$L_REPO/hooks/hooks.json"
printf 'echo\n'           > "$L_REPO/hooks/other.sh"
printf 'agent a\n'        > "$L_REPO/agents/a.md"
printf 'agent deep\n'     > "$L_REPO/agents/sub/b.md"
printf 'skill\n'          > "$L_REPO/payload/skills/x/SKILL.md"
printf 'step one\n'       > "$L_REPO/payload/skills/x/steps/1.md"
printf 'echo\n'           > "$L_REPO/payload/skills/x/run.sh"
printf 'command\n'        > "$L_REPO/payload/commands/c.md"
printf 'nested command\n' > "$L_REPO/payload/commands/sub/deep.md"
ln -s ../hooks  "$L_REPO/payload/hooks"
ln -s ../agents "$L_REPO/payload/agents"
git -C "$L_REPO" init -q && git -C "$L_REPO" add -A \
  && git -C "$L_REPO" -c user.email=t@t -c user.name=t commit -qm fixture
L_HEAD=$(git -C "$L_REPO" rev-parse HEAD)
L_ROOT=$(cd "$L_REPO/payload" && pwd -P)
l_sha() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }
L_WANT=$(for f in agents/a.md agents/sub/b.md commands/c.md hooks/hooks.json skills/x/SKILL.md skills/x/steps/1.md; do
  printf '%s %s\n' "$(l_sha "$L_ROOT/$f")" "$f"; done)
l_hashes() { grep -E '^[0-9a-f]{64} ' "$1" 2>/dev/null | LC_ALL=C sort -k2; }

P21=$(make_env 3600s)
L_REC="$P21/.bionic/tmp/loaded-$CUR_SID.state"
OUT=$(DRIVE_PLUGIN_ROOT="$L_ROOT" drive "$P21" startup "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq   "21.1 exit 0" "0" "$(rc)"
eq   "21.2 the record is a regular file under the session's id" "file" "$([ -f "$L_REC" ] && [ ! -L "$L_REC" ] && echo file)"
eq   "21.3 root= is CLAUDE_PLUGIN_ROOT" "root=$L_ROOT" "$(grep '^root=' "$L_REC" 2>/dev/null)"
eq   "21.4 commit= is the checkout's HEAD" "commit=$L_HEAD" "$(grep '^commit=' "$L_REC" 2>/dev/null)"
eq   "21.5 started= is an ISO-8601 UTC instant" "1" "$(grep -cE '^started=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$L_REC" 2>/dev/null)"
eq   "21.6 one sha256 line per loaded file: hooks.json, skills/**, agents/** through the links, commands/*" \
  "$L_WANT" "$(l_hashes "$L_REC")"
hasnt "21.7 …a script beside a skill is not a loaded file" "skills/x/run.sh" "$(cat "$L_REC" 2>/dev/null)"
hasnt "21.8 …nor a command one directory down (commands/*.md only)" "commands/sub/deep.md" "$(cat "$L_REC" 2>/dev/null)"
hasnt "21.9 …nor a hook script (hooks.json names them; they are read per call)" "hooks/other.sh" "$(cat "$L_REC" 2>/dev/null)"
eq   "21.10 the record adds nothing to what the hook prints" "" "$OUT"

# Each start writes its own: a /clear re-keys the session, and a resume or a compaction of the same
# id rewrites the one record with what is on disk now.
OUT=$(DRIVE_PLUGIN_ROOT="$L_ROOT" drive "$P21" clear "$OLD_SID" "$OLD_SID" "$OLD_SID")
eq   "21.11 a /clear's new id gets its own record" "root=$L_ROOT" "$(grep '^root=' "$P21/.bionic/tmp/loaded-$OLD_SID.state" 2>/dev/null)"
eq   "21.12 …and the first id's record stays" "root=$L_ROOT" "$(grep '^root=' "$L_REC" 2>/dev/null)"
printf 'command, edited\n' > "$L_REPO/payload/commands/c.md"
for L_SRC in resume compact; do
  DRIVE_PLUGIN_ROOT="$L_ROOT" drive "$P21" "$L_SRC" "$CUR_SID" "$CUR_SID" "$CUR_SID" >/dev/null
  eq "21.13 $L_SRC rewrites the record with the file as it is now" \
    "$(l_sha "$L_ROOT/commands/c.md") commands/c.md" "$(grep ' commands/c.md$' "$L_REC" 2>/dev/null)"
done

# A root that is no checkout (the plugin cache) has no commit, and says so by the key's absence.
L_CACHE=$(mktemp -d "$WORK/cache.XXXXXX")
mkdir -p "$L_CACHE/skills/y" && printf 'skill\n' > "$L_CACHE/skills/y/SKILL.md"
L_CACHE=$(cd "$L_CACHE" && pwd -P)
P21b=$(make_env 3600s)
DRIVE_PLUGIN_ROOT="$L_CACHE" drive "$P21b" startup "$CUR_SID" "$CUR_SID" "$CUR_SID" >/dev/null
eq   "21.14 a cache root: root= names it" "root=$L_CACHE" "$(grep '^root=' "$P21b/.bionic/tmp/loaded-$CUR_SID.state" 2>/dev/null)"
eq   "21.15 …and carries no commit=" "0" "$(grep -c '^commit=' "$P21b/.bionic/tmp/loaded-$CUR_SID.state" 2>/dev/null)"
# A directory inside some other repository is not a checkout of the plugin: ~/.claude kept in git
# must not lend the cache its commit.
L_OUTER=$(mktemp -d "$WORK/outer.XXXXXX")
mkdir -p "$L_OUTER/plugins/cache/v/skills/z" && printf 'skill\n' > "$L_OUTER/plugins/cache/v/skills/z/SKILL.md"
git -C "$L_OUTER" init -q && git -C "$L_OUTER" add -A && git -C "$L_OUTER" -c user.email=t@t -c user.name=t commit -qm outer
P21c=$(make_env 3600s)
DRIVE_PLUGIN_ROOT="$(cd "$L_OUTER/plugins/cache/v" && pwd -P)" drive "$P21c" startup "$CUR_SID" "$CUR_SID" "$CUR_SID" >/dev/null
eq   "21.16 a root inside another repository: the record is written" "1" "$(grep -c '^root=' "$P21c/.bionic/tmp/loaded-$CUR_SID.state" 2>/dev/null)"
eq   "21.17 …and carries no commit=" "0" "$(grep -c '^commit=' "$P21c/.bionic/tmp/loaded-$CUR_SID.state" 2>/dev/null)"

# No CLAUDE_PLUGIN_ROOT: the CLI did not launch this hook, there is no load to record (positive: 21.2).
P21d=$(make_env 3600s)
S21D_BEFORE=$(snap "$P21d")
drive "$P21d" startup "$CUR_SID" "$CUR_SID" "$CUR_SID" >/dev/null
eq   "21.18 no CLAUDE_PLUGIN_ROOT: no record, nothing written" "$S21D_BEFORE" "$(snap "$P21d")"
# A link planted at the record's path is replaced, never written through.
P21e=$(make_env 3600s)
printf 'victim\n' > "$WORK/victim"
ln -s "$WORK/victim" "$P21e/.bionic/tmp/loaded-$CUR_SID.state"
DRIVE_PLUGIN_ROOT="$L_ROOT" drive "$P21e" startup "$CUR_SID" "$CUR_SID" "$CUR_SID" >/dev/null
eq   "21.19 a link at the record path: its target is untouched" "victim" "$(cat "$WORK/victim")"
eq   "21.20 …and the record is a regular file in its place" "root=$L_ROOT" "$([ -L "$P21e/.bionic/tmp/loaded-$CUR_SID.state" ] || grep '^root=' "$P21e/.bionic/tmp/loaded-$CUR_SID.state")"

section "22 — the start hook under bash 4 and 5 (wave-36 T30, D7; AC-1.1)"
# `ss_load_record` once declared `local -a files` and indexed `files[${#files[@]}]` on the unset array,
# which `set -u` refuses under bash 4.0+ ("files: unbound variable"): no load record was written and the
# rest of the hook never ran. /bin/bash 3.2, the shebang, was the only bash it worked under. The hook runs
# here under a bash of major version 4 or more found on this machine, with the §21 fixture: the record is
# written, and a line from the far end of the hook (the standing decision line, printed in every session)
# is on stdout. With no such bash the rows are recorded `ok` with the reason in the label (no skip idiom
# in this harness, as canonical-sdlc-governing-skill 8.1h).
B5_BASH=""
for b5_c in /opt/homebrew/bin/bash /usr/local/bin/bash "$(command -v bash 2>/dev/null)"; do
  [ -n "$b5_c" ] && [ -x "$b5_c" ] || continue
  b5_v="$("$b5_c" -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null)"
  case "$b5_v" in ''|*[!0-9]*) continue ;; esac
  if [ "$b5_v" -ge 4 ]; then B5_BASH="$b5_c"; break; fi
done
if [ -n "$B5_BASH" ]; then
  P22=$(make_env 3600s)
  B5_REC="$P22/.bionic/tmp/loaded-$CUR_SID.state"
  DRIVE_HOOK_BASH="$B5_BASH" DRIVE_PLUGIN_ROOT="$L_ROOT" drive "$P22" startup "$CUR_SID" "$CUR_SID" "$CUR_SID" >/dev/null
  eq    "22.1 the hook under $B5_BASH exits 0" "0" "$(rc)"
  hasnt "22.2 …with no unbound variable on stderr" "unbound variable" "$(errtext)"
  eq    "22.3 …the load record is written" "root=$L_ROOT" "$(grep '^root=' "$B5_REC" 2>/dev/null)"
  eq    "22.4 …with one sha256 line per loaded file, as under bash 3.2" \
    "$(printf '%s\n' "$L_WANT" | wc -l | tr -d ' ')" "$(l_hashes "$B5_REC" | wc -l | tr -d ' ')"
  has   "22.5 …and the hook's later lines ran: the standing decision line is on stdout" \
    "$STANDING_MARK" "$(cat "$WORK/last.out" 2>/dev/null)"
else
  ok "22.1-22.5: skip: no bash >= 4 on this machine (looked for /opt/homebrew/bin/bash, /usr/local/bin/bash, bash on PATH)"
fi

# THE START CWD (wave-37 T5; D9, ADR-058). The record carries `cwd=`, the physical directory the session started
# in: the CLI files a session's transcript under that directory's name, and a session started in a subdirectory
# or a worktree files it under a name other than the root's, so the words reader (lib/said.sh) looks there too.
# The record still lives under the project root, and `cwd=` follows `started=`, so the header readers that stop
# at a key they do not know (close-out.sh co_governed_rows) still read root=, commit= and started=.
P23=$(make_env 3600s); mkdir -p "$P23/sub"
L23_REC="$P23/.bionic/tmp/loaded-$CUR_SID.state"
OUT=$(DRIVE_PLUGIN_ROOT="$L_ROOT" drive "$P23/sub" startup "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq   "23.1 a session started in a subdirectory: exit 0" "0" "$(rc)"
eq   "23.2 the record under the project root carries cwd=, the start directory, physical" \
  "cwd=$(cd "$P23/sub" && pwd -P)" "$(grep '^cwd=' "$L23_REC" 2>/dev/null)"
eq   "23.3 …and root= is still CLAUDE_PLUGIN_ROOT" "root=$L_ROOT" "$(grep '^root=' "$L23_REC" 2>/dev/null)"
eq   "23.4 …the header keys in order, cwd= after started=" "root commit started cwd" \
  "$(sed -n 's/^\([a-z]*\)=.*/\1/p' "$L23_REC" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
eq   "23.5 …and one sha256 line per loaded file, as before" \
  "$(printf '%s\n' "$L_WANT" | wc -l | tr -d ' ')" "$(l_hashes "$L23_REC" | wc -l | tr -d ' ')"
P23b=$(make_env 3600s)
OUT=$(DRIVE_PLUGIN_ROOT="$L_ROOT" drive "$P23b" startup "$CUR_SID" "$CUR_SID" "$CUR_SID")
eq   "23.6 a session started at the root records the root as its cwd" \
  "cwd=$(cd "$P23b" && pwd -P)" "$(grep '^cwd=' "$P23b/.bionic/tmp/loaded-$CUR_SID.state" 2>/dev/null)"

finish
