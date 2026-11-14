# tests/session-poker.prelude.sh — THE HALF OF THE SESSION-POKER SUITE EVERY SHARD SHARES
#
# Sourced by tests/session-poker.test.sh, -2, -3 and -4, after tests/lib/assert.sh, the four
# fixture libraries and the POKER seam. It is not a suite: the runner launches `*.test.sh`
# only. It sits beside the shards rather than under tests/lib/ so that tests/lib/impact.sh
# answers an edit to it with these four suites, through their `source` lines, and not with
# the full run every tests/lib file owes.
#
# WHAT IT HOLDS. The sandbox and the machine pins, the fixture builders every section uses,
# and each helper or constant a section defined that a section in a LATER shard calls. A
# hoisted block is marked with the section it came from, and that section keeps a one-line
# pointer where it stood.
#
# WHAT IT NEVER HOLDS. A fixture: a repository one section builds and a later one reads is
# not a helper, so those sections share a shard instead. And a path the impact map must see:
# the map reads a suite's own lines and does not follow this file, so POKER, S46_LIB and
# S31_STOP_HOOK are assigned by each shard that needs them, before this file is sourced.

TMPROOT="$(mktemp -d)"

# THE LOADER'S REGISTRY LANE, POINTED AT NOTHING (bionic 1.4.0). The poker now finds its
# library through the shared loader idiom, whose candidates (2) and (3) read the CLI's
# plugin registry under `$BIONIC_PLUGINS_DIR` (default `$HOME/.claude/plugins`). Every
# invocation in this suite runs the shipped file, whose sibling `scripts/lib` answers at
# candidate (1) — so a run that ever reached the registry would be a run that failed to
# find the library beside the script, and pointing the knob at an empty directory turns
# that into a visible failure instead of a silent read of this machine's real install.
export BIONIC_PLUGINS_DIR="$TMPROOT/no-plugins"
mkdir -p "$BIONIC_PLUGINS_DIR"

# THE MACHINE IS FIXTURE DATA HERE, WITHOUT EXCEPTION (S8). The tick now samples the
# pressure ring and takes its fill width from `pressure_level`, so two readings that used
# to reach only the advisory HOLD line now decide how many tasks a FILL names. Left
# unpinned, this suite would read THIS machine — and a suite that happens to run while the
# fleet is busy would see a critical band, a quartered rung and a FILL of one where the case
# asked for two. Every one of these is a seam lib/resources.sh already owns
# (`BIONIC_PROBE_*`, resources.sh:154 and :242/:279) plus the ring path S7 added; pinning
# them here is the same discipline §11's preamble already declares for free_mb and load.
#
# THE RING GOES UNDER $TMPROOT, so nothing in this file can read or write the machine-scoped
# ring at ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/pressure.ring. Cases that need a
# particular BAND override the two percentages and take a ring of their own (`poke_rung`).
export BIONIC_PRESSURE_RING="$TMPROOT/pressure.ring"
export BIONIC_PROBE_FREE_MB=8192
export BIONIC_PROBE_LOAD_1M=1.0
export BIONIC_PROBE_FREE_PCT=60
export BIONIC_PROBE_SWAP_PCT=0
# THE GATE IS FIXTURE DATA TOO (wave-28 T13; D14). The tick sizes its fill at the gate, which
# reads the machine through the readers' pins and its store at BIONIC_GATE_DIR: 8 cores, 30%
# used, a load of 1.0 over the last minute and the last five, and one run on record that takes
# 0.1 core — room for every row a fixture here offers. §11 plants its own per case.
export BIONIC_PROBE_CORES=8 BIONIC_PROBE_USED_PCT=30 BIONIC_PROBE_BUSY_CORES=1.0 BIONIC_PROBE_BUSY_CORES_5M=1.0
SP_GATE_DIR="$TMPROOT/gate"
export BIONIC_GATE_DIR="$SP_GATE_DIR"
mkdir -p "$SP_GATE_DIR/requests" "$SP_GATE_DIR/cost"
printf '5:0.1:30:1000\n' > "$SP_GATE_DIR/cost/fixture.test.sh"
# THE SHARE IS FIXTURE DATA TOO (wave-31 T13; A-orch-38). The gate reads the share from
# ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/share and the default is 92, so a suite that left the dir
# unset read this machine's file or the default. 80 is the value §11 is written against ("the five-minute
# load over 6.4 cores" is 8 cores x 0.80) and the one §40 pins for itself. Sections that name their own
# dir through `fake_config_dir` override this one per call and keep working.
#
# THE PIN HAS A NAME, BECAUSE SECTIONS LEAVE IT. A section that points CLAUDE_CONFIG_DIR at its own
# `fake_config_dir` ends by putting it back with `CLAUDE_CONFIG_DIR="$SP_CONFIG_DIR"`, never `unset`: an
# unset hands the read to `$HOME/.claude`, this machine's own share (92). HOME is not pinned.
SP_CONFIG_DIR="$TMPROOT/config"
mkdir -p "$SP_CONFIG_DIR/bionic"
printf '80\n' > "$SP_CONFIG_DIR/bionic/share"
export CLAUDE_CONFIG_DIR="$SP_CONFIG_DIR"

cleanup() { chmod -R u+rwX "$TMPROOT" 2>/dev/null; rm -rf "$TMPROOT"; }
trap cleanup EXIT

SID="8a41c2e0-9b71-4f3a-8d6e-2c19f7b0e5aa"

# ---------- sandbox + fixture builders (mirrors tests/session-sweeper.test.sh) ----------

make_repo() {  # <label> -> repo path, in a session that has ENGAGED bionic
  local r="$TMPROOT/$1"
  mkdir -p "$r/.bionic/tmp"
  ( cd "$r" && git init -q . 2>/dev/null )
  engage "$r"
  printf '%s' "$r"
}

# ---------- engagement (task-engaged-session, AC-10, AC-15) ----------
#
# Since 2026-09-03 `tick` and `adopt` decide nothing in a session that never invoked the
# canonical-sdlc skill (Chris: "Nothing should apply until bionic is triggered"). The
# record of the invocation is `.bionic/tmp/engaged-<sid>.state` under the repo root, and
# every fixture in this file carries one because every assertion in it is about what the
# Patrol does inside a run somebody started. Section 11 is the unengaged world.
#
# `arm` and `disarm` are deliberately NOT guarded: writing or removing a stamp for a
# session that asked for one is harmless, and disarm must leave this marker in place —
# a session that invoked the skill is bionic's for its whole life (AC-15).
engage()   { mkdir -p "$1/.bionic/tmp" && : > "$1/.bionic/tmp/engaged-$SID.state"; }
unengage() { rm -f "$1/.bionic/tmp/engaged-$SID.state"; }

roster_of() { printf '%s/.bionic/tmp/roster-%s.state' "$1" "${2:-$SID}"; }

iso_ago() {  # <seconds ago> -> UTC ISO-8601, the launched_at shape
  date -u -v-"$1"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "-$1 seconds" +%Y-%m-%dT%H:%M:%SZ
}

backdate() {  # <file> <seconds ago> — sets mtime, the progress-staleness input
  local ts
  ts="$(date -v-"$2"S +%Y%m%d%H%M.%S 2>/dev/null || date -d "-$2 seconds" +%Y%m%d%H%M.%S)"
  touch -t "$ts" "$1"
}

new_roster() {  # <repo>
  roster_header > "$(roster_of "$1")"
}

# Subset of tests/session-sweeper.test.sh's mkrow — the fields the poker actually reads
# (name, launched_at, deliverable, duration, progress, claims, cadence, waiver), same
# schema shape and field order as the roster writer in hooks/dispatch-preflight.sh.
mkrow() {  # <key=value>...
  local status=confirmed session="$SID" name=agent agent_id=a000 launched_at=""
  local deliverable="" duration="" progress="" claims="" cadence="" waiver=""
  local subagent_type=implementor
  local tool_use_id=toolu_x source=declared kv
  # THE ATTRIBUTION FIELD IS OPT-IN HERE, and that is the point (wave-session-bound-run,
  # A2). hooks/dispatch-preflight.sh appends `plan=` to every row it writes from this wave
  # on, but every roster written BEFORE it carries none — and `adopt`'s partition has to
  # answer for those too. A fixture that always emitted the field could not describe a
  # pre-wave roster, so `plan=` is written only when a case asks for it, and every existing
  # row in this file stays exactly the shape it was.
  local plan="" plan_set=no
  # THE THREE INSTRUMENT FIELDS ARE OPT-IN for the same reason `plan=` is (S13, spec
  # AC-20): every roster written before the suite-allowance wall carries none of them, and
  # `adopt` has to answer for those files too. A fixture that always emitted them could not
  # describe a pre-wall roster, and the third state — key absent, as opposed to key present
  # and empty — is the one the writer-side budget guard partitions on.
  local files="" sallow="" ssrc="" instrument_set=no
  local rexec="" rexec_set=no
  # THE DONE MARKER IS OPT-IN too (wave-24 T9, D3): a row that names none carries no key.
  local dmark="" dmark_set=no
  # THE LANDING KEYS ARE OPT-IN too (wave-28 T68): a row the dispatch wall wrote under 1.13.0 carries them, one
  # that names none does not, and `adopt` has to carry exactly the ones present.
  local -a landing=()
  for kv in "$@"; do
    case "$kv" in
      lands_on=*|lands_red=*|red_evidence=*|row=*) landing+=("$kv") ;;
      re_executes=*) rexec="${kv#*=}"; rexec_set=yes ;;
      done=*)        dmark="${kv#*=}"; dmark_set=yes ;;
      plan=*)        plan="${kv#*=}"; plan_set=yes ;;
      status=*)      status="${kv#*=}" ;;
      session=*)     session="${kv#*=}" ;;
      agent_id=*)    agent_id="${kv#*=}" ;;
      subagent_type=*) subagent_type="${kv#*=}" ;;
      name=*)        name="${kv#*=}" ;;
      launched_at=*) launched_at="${kv#*=}" ;;
      deliverable=*) deliverable="${kv#*=}" ;;
      duration=*)    duration="${kv#*=}" ;;
      progress=*)    progress="${kv#*=}" ;;
      claims=*)      claims="${kv#*=}" ;;
      cadence=*)     cadence="${kv#*=}" ;;
      waiver=*)      waiver="${kv#*=}" ;;
      files=*)          files="${kv#*=}";  instrument_set=yes ;;
      suites_allowed=*) sallow="${kv#*=}"; instrument_set=yes ;;
      suites_source=*)  ssrc="${kv#*=}";   instrument_set=yes ;;
      *) printf 'mkrow: unknown key %s\n' "$kv" >&2; return 1 ;;
    esac
  done
  [ -n "$launched_at" ] || launched_at="$(iso_ago 60)"
  # THE ROW ITSELF COMES FROM `roster_row`, through tests/lib/roster-row.sh (S14, AC-25).
  # What stays here is this file's own house defaults — `model=opus`, `tool_use_id=toolu_x`,
  # a launch time sixty seconds ago — and the `plan=` opt-in above, which is the one thing
  # the production writer cannot express: no writer emits a row without that field any more,
  # and a pre-wave roster is exactly what these cases are about.
  local emit=roster_row_fixture
  [ "$plan_set" = yes ] || emit=roster_row_no_plan
  local -a instrument
  if [ "$instrument_set" = yes ]; then
    instrument=("files=$files" "suites_allowed=$sallow" "suites_source=$ssrc")
  fi
  [ "$rexec_set" = yes ] && instrument+=("re_executes=$rexec")
  [ "$dmark_set" = yes ] && instrument+=("done=$dmark")
  "$emit" \
    "status=$status" "session=$session" "name=$name" "agent_id=$agent_id" \
    "launched_at=$launched_at" "subagent_type=$subagent_type" model=opus \
    "deliverable=$deliverable" "source=$source" "duration=$duration" \
    "progress=$progress" "claims=$claims" "cadence=$cadence" absent= \
    "waiver=$waiver" ${instrument[@]+"${instrument[@]}"} \
    "tool_use_id=$tool_use_id" "plan=$plan" ${landing[@]+"${landing[@]}"}
}

add_row() {  # <repo> <key=value>...
  local repo="$1"; shift
  mkrow "$@" >> "$(roster_of "$repo")"
}

# THE AGENT SAID SO (wave-24 T9, REQ-4 AC-4.8; D3). MET is a landed deliverable AND a completion
# signal after the launch, and a fixture whose session transcript holds a panel but no report
# from the agent reads UNMET without one. A row meant to read MET gets its Done marker, written
# now, beside the deliverable: the row says nothing else, and nothing in the transcript moves.
said() {  # <dir> <name> -> the `done=<path>` argument, the marker written
  : > "$1/$2.done"
  printf 'done=%s/%s.done' "$1" "$2"
}

# THE ACK IS PLANTED THROUGH THE REAL VERB, never by hand-writing a ledger line. `acked=`
# reaches the poker on the verdict line (hooks/session-sweeper.sh:715), and the only writer
# of the ledger that line is computed from is `ack` itself — a fabricated ledger would pin
# this suite to a private idea of the ledger's shape rather than to the one the sweeper
# actually keeps. The sweeper is resolved exactly as the poker resolves it, as a sibling of
# the script under test, so a mutated poker copy still acks through the shipped sweeper.
SWEEPER_FOR_ACK="$(cd "$(dirname "$POKER")" && pwd)/session-sweeper.sh"
ack_rows() {  # <repo> <name>...
  local repo="$1"; shift
  ( cd "$repo" && env CLAUDE_CODE_SESSION_ID="$SID" bash "$SWEEPER_FOR_ACK" ack "$@" ) \
    >/dev/null 2>&1
}

# ---------- plan fixtures: the run-state read the tick takes (B-4, AC-13/AC-14) ----------
#
# WHY EVERY DISARM FIXTURE BELOW GREW A PLAN. `open == 0` used to be the whole DISARM
# predicate, and it is also what a live wave looks like between two batches — so the tick
# ended the Patrol of runs with days of work left (epic-20 W1 dogfood, idea §B-4). DISARM
# now needs the RUN to say it is delivered: `current: 9` with `delivered:` on the `Step 9:`
# line, read out of the newest plan carrying an unfenced `## SDLC State`. A fixture that
# writes no plan is therefore a fixture that cannot DISARM, which is AC-13's second half.
#
# CLOCK DISCIPLINE HOLDS: nothing here sleeps. `touch` after the write is what makes a
# fixture the newest candidate, exactly as `backdate` drives staleness above.
plan_body() {  # <current> [evidence text for the Step-<current> line] -> a whole plan file
  printf '# fixture plan\n\n## SDLC State\n\nintegration-branch: main\ncurrent: %s\n' "$1"
  # Past Step 3 the plan carries its approval, the fact the fill keys on (wave-26 T13; D3).
  case "${1%[ab]}" in [4-9]) printf '%s\n' 'approved-by: fixture 2026-10-04T00:00Z "approved"' ;; esac
  printf '\n- Step %s: %s\n' "$1" "${2:-evidence for this step}"
}

write_plan() {  # <repo> <body> [path relative to <docs-root>/plans]
  local repo="$1" body="$2" rel="${3:-epic-99-fixture/wave-01-fixture.plan.md}"
  local f="$repo/.bionic/docs/plans/$rel"
  mkdir -p "$(dirname "$f")"
  printf '%s' "$body" > "$f"
  touch "$f"
}

# The shorthand every DISARM fixture uses: a run that reached Step 9 and recorded a
# delivery. `delivered:` is the token the close-out step writes and the only one run_state
# accepts.
delivered_plan() {  # <repo>
  write_plan "$1" "$(plan_body 9 'delivered: bionic 9.9.9; report: record/fixture/close-out.md')"
}

# ---------- the session binding (wave-session-bound-run, AC-2/AC-3/AC-6/AC-8) ----------
marker_of() { printf '%s/.bionic/tmp/engaged-%s.state' "$1" "${2:-$SID}"; }

# THE BOUND FIXTURE, in hooks/engage.sh's exact two-line shape — the same posture
# tests/canonical-sdlc-evidence-gate.test.sh §35 takes. Written directly rather than through
# `poker bind` so that §17 and §18 describe a session that arrived already bound (the
# ordinary case: engagement bound it, or the governing skill did) and do not depend on the
# verb §16 is testing.
bind_marker() {  # <repo> <plan path|none> [sid]
  bound_marker "$1" "${3:-$SID}" "$2"
}

stamp_of() { printf '%s/.bionic/tmp/patrol-%s.state' "$1" "${2:-$SID}"; }

# THE TICK DIGEST (wave-24 T7, REQ-4; D4). A tick over the same facts as the last one prints one
# `unchanged` line, so a case that ticks the SAME world twice to read the second tick's full
# output — a doctored copy, a second cwd, a third reading of one pressure — forgets the digest
# first. Forgetting it is what an `arm` does to the next tick.
digest_of() { printf '%s/.bionic/tmp/tick-digest-%s.state' "$1" "${2:-$SID}"; }
forget_digest() { rm -f "$(digest_of "$1")"; }

# THE ARMING RECORD — the sibling of the stamp whose mtime `arm` sets and the tick compares a
# delivery against (R-13). Spelled out here the way stamp_of spells the stamp: one place in
# this suite knows the layout, and a rename on the writer's side shows up as a failure rather
# than as a fixture that quietly stops describing anything.
armed_of() { printf '%s%s' "$(stamp_of "$@")" ".armed"; }

# A DISARM FIXTURE DESCRIBES A PATROL THAT ARMED BEFORE THE RUN DELIVERED, and from 1.3.2
# that ordering is what the tick reads — so it is fixture DATA, set by arming through the
# real verb and dating the record back, exactly as `backdate` sets staleness and as
# tests/cross-gate-agreement.test.sh §S.3 sets "newest". Nothing here sleeps, and nothing is
# left to a same-second tie.
armed_ago() {  # <repo> [seconds ago, default 3600]
  poke "$1" arm
  backdate "$(armed_of "$1")" "${2:-3600}"
}

# ---------- running the poker (same watchdog shape as tests/session-sweeper.test.sh) ----------

POKE_BOUND=20
# A TICK RUNS ON A SESSION'S OWN RUN (wave-23-fixit-1810, REQ-1, D1; T11). An UNBOUND session
# gets the advisory and no run, so a fixture that engages with an empty marker and then asks
# the tick about the plan beside it would be asking an unbound session about someone else's
# run. `poke_bind` binds the empty marker to the library's open run for the drive, as
# cross-gate-agreement's `cg_eg_bind` does for the gate; a case that WANTS the unbound
# session sets POKE_UNBOUND=1 (§18c).
poke_bind() {  # <repo> -> binds an empty engaged marker to the root's open run, if there is one
  local m p; m="$(marker_of "$1")"
  [ -f "$m" ] && [ ! -L "$m" ] && [ ! -s "$m" ] || return 0
  p="$(bash -c '. "$1/run.sh" 2>/dev/null && active_run "$2"' _ "$BIONIC_SCRIPTS_DIR/payload/scripts/lib" "$1" 2>/dev/null)" || p=""
  [ -n "$p" ] && bound_marker "$1" "$SID" "$p"
  return 0
}
poke() {  # <repo> <args...> -> sets OUT, RC; POKE_BASH names the interpreter (default: PATH's bash)
  local repo="$1"; shift
  case "${1:-}" in tick) [ "${POKE_UNBOUND:-0}" = 1 ] || poke_bind "$repo" ;; esac
  ( cd "$repo" && exec env CLAUDE_CODE_SESSION_ID="$SID" "${POKE_BASH:-bash}" "$POKER" "$@" ) \
    > "$TMPROOT/poke.out" 2>&1 &
  local p=$! i=0
  while kill -0 "$p" 2>/dev/null && [ "$i" -lt $(( POKE_BOUND * 10 )) ]; do
    sleep 0.1; i=$((i+1))
  done
  if kill -0 "$p" 2>/dev/null; then
    kill -9 "$p" 2>/dev/null; wait "$p" 2>/dev/null
    RC=124
  else
    wait "$p" 2>/dev/null; RC=$?
  fi
  OUT="$(cat "$TMPROOT/poke.out")"
}

# ta_add <repo> <id> <step> <kind> <task> <agent> <deps> <size> <serves> <Files> [<reads>] [--born <b>] [--questions <q>]
#   -> OUT, RC: the orchestrator's edit of the row, by the header, then the plan kept for s42_unchanged, then task-add of it;
#   TA_PASTE=1 pastes the lines a short row's refusal prints, as the orchestrator does, and runs the verb again.
ta_add() {
  local repo="$1" b="" q="" p t; shift
  while [ $# -ge 2 ]; do case "${*: -2:1}" in --born) b="${*: -1}" ;; --questions) q="${*: -1}" ;; *) break ;; esac; set -- "${@:1:$(($# - 2))}"; done
  p="$(sed -n 's/^plan=//p' "$(marker_of "$repo")" 2>/dev/null)"; [ -f "$p" ] || { poke_bind "$repo"; p="$(sed -n 's/^plan=//p' "$(marker_of "$repo")")"; }
  t="$4"; case "$b" in '') ;; regression:*) t="$t · born: regression" ;; *) t="$t · born: review" ;; esac; [ -z "$q" ] || t="$t · questions: $q"
  ta_put "$p" "$(TA_V="$(printf '%s\t' "$1" "$2" "$3" "$t" "$5" "$6" "$7" "$8" "$9" "${10:-}")" awk '
    BEGIN { split("id step kind task agent deps size serves files reads", k, " "); split(ENVIRON["TA_V"], v, "\t"); for (i in k) val[k[i]] = v[i]; val["status"] = "pending" }
    /^## / { t = ($0 ~ /^## [Tt]asks/) } t && /^\| *id *\|/ { n = split($0, h, "|"); r = "|"
      for (c = 2; c < n; c++) { x = tolower(h[c]); gsub(/^ +| +$/, "", x); r = r " " (val[x] == "" ? "—" : val[x]) " |" }; print r; exit }' "$p")"
  cp "$p" "$TMPROOT/s42-before"; poke "$repo" task-add "$1" ${b:+--born "$b"}
  [ "${TA_PASTE:-}$RC" = 11 ] && [ "${OUT/ is short /}" != "$OUT" ] && { ta_put "$p" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^| T')"; poke "$repo" task-add "$1" ${b:+--born "$b"}; }; :
}
ta_put() {  # <plan> <Tasks lines> -> each line written over the row of its id, or after the table's last row
  TA_V="$2" awk 'BEGIN { n = split(ENVIRON["TA_V"], v, "\n"); for (i = 1; i <= n; i++) { split(v[i], c, "|"); k = c[2]; gsub(/ /, "", k); if (k != "") { row[k] = v[i]; o[++m] = k } } }
    /^## / { t = ($0 ~ /^## [Tt]asks/) } { L[NR] = $0 } t && /^\|/ { last = NR; split($0, c, "|"); k = c[2]; gsub(/ /, "", k); if (k in row) { L[NR] = row[k]; put[k] = 1 } }
    END { for (i = 1; i <= NR; i++) { print L[i]; if (i == last) for (j = 1; j <= m; j++) if (!(o[j] in put)) print row[o[j]] } }' "$1" > "$1.ta" && mv "$1.ta" "$1"
}

# ── hoisted from Section 6: fake_config_dir — Sections 41 and 43–45 build config dirs with it. ──
# ============================================================
# THE BLIND-WALL DETECTOR, RETIRED (bionic 1.4.0, task ADOPT, spec AC-7)
# ============================================================
#
# It compared main-thread `Agent` tool_uses in the transcript against rows on the roster
# and raised a NOTIFY when dispatches outnumbered them. The condition it looked for was
# real: the dispatch wall lived in the governing skill's frontmatter, and a skill's
# registrations do not survive a session continue, a `/clear` + resume or a
# `/reload-plugins` — so the wall went silently absent and dispatches launched unrostered.
#
# Every wall is registered in hooks/hooks.json now and survives all three, so that
# condition cannot arise the way it did. What could still arise was the detector's own
# false positive: it had no "no active run" branch, so a session that had simply not
# engaged a run — no roster, because nothing was dispatched — read as a session whose wall
# had died. That fired for real on 2026-09-02 at 20:07Z, against this wave's own
# orchestrator, which is how it came to be in scope.
#
# The registration is pinned instead, in tests/hook-adoption.test.sh and
# tests/cross-gate-agreement.test.sh §L: every hook named once in hooks.json, none in the
# frontmatter. That is a claim about a file on disk rather than an inference from a
# transcript, and it goes red when the wiring changes rather than when a session is idle.
#
# ONE HELPER SURVIVES THE RETIREMENT: `fake_config_dir`. Section 8 builds a predecessor's
# subagent transcript under it, and `adopt` resolves the observe address through
# CLAUDE_CONFIG_DIR — so without it that section would read the real ~/.claude.
fake_config_dir() {  # <label> -> a CLAUDE_CONFIG_DIR with a projects/ tree
  local c="$TMPROOT/$1-config"
  mkdir -p "$c/projects/-fixture-project"
  printf '%s' "$c"
}

# ── hoisted from Section 11: wave_plan_at, SP_TASKS_HEADER, SP_APPROVED_LINE, plant_answer, poke_pressure, RUNG_N, poke_rung — every later shard plants plans and answers and ticks under a pinned pressure with them. ──
# A plan carrying BOTH halves the scheduler reads: the frontmatter `parallel-budget:` line
# and the machine-readable task table. Written as one builder because a fixture that
# carried only one of them would be testing a plan shape the wave never produces.
#
# The budget line's shape is byte-identical to what Step 0 writes and to what
# hooks/dispatch-preflight.sh's budget arm reads (L-RESOURCES/2): one string, four fields.
#
# AT A PATH THE CALLER NAMES, and echoing that path back. Section 18 needs
# TWO budgeted plans in one root — one bound, one not — which a fixed filename cannot
# describe.
# THE ONE `## Tasks` HEADER EVERY FIXTURE PLAN IN THIS SUITE CARRIES (REQ-1e). The tick
# reads the table through payload/scripts/lib/units.sh now, which keys every column off
# this header row by NAME — so a fixture that named fewer columns would be testing a
# schema no plan ships. The `step` cell is the one that matters to FILL: `units_ready`
# answers for ONE step, and these fixtures sit at `current: 4`.
SP_TASKS_HEADER='| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
'
# THE APPROVAL A LIVE FIXTURE CARRIES (wave-26 T13; D3, AC-6.2). The ready set keys on the plan's
# `approved-by:` line, not on `current: >= 4`, so a fixture that means "past Step 3" writes it.
SP_APPROVED_LINE='approved-by: fixture 2026-10-04T00:00Z "approved"'

wave_plan_at() {  # <repo> <path under <docs-root>/plans> <budget or "-"> <table row>... -> the path
  local repo="$1" rel="$2" budget="$3"; shift 3
  local f="$repo/.bionic/docs/plans/$rel"
  mkdir -p "$(dirname "$f")"
  {
    printf -- '---\n'
    printf 'governing-skill: superpowers:writing-plans\n'
    [ "$budget" = "-" ] || printf 'parallel-budget: %s\n' "$budget"
    printf -- '---\n\n'
    printf '# fixture plan\n\n## SDLC State\n\ncurrent: 4\n%s\n\n- Step 4: in progress\n\n' "$SP_APPROVED_LINE"
    printf '## Tasks\n\n'
    printf '%s' "$SP_TASKS_HEADER"
    local row
    for row in "$@"; do printf '%s\n' "$row"; done
  } > "$f"
  [ "${SP_PLAN_AT:-15}" != 15 ] || sp_at15 "$f"
  touch "$f"
  printf '%s' "$f"
}

# The poker under an injected pressure reading. The two knobs are exported for exactly one
# invocation and unset afterwards, so no case can leak a reading into the next.
# ---------- the live answer, planted where `session_transcript` looks for it ----------
#
# Any project directory of CLAUDE_CONFIG_DIR, file `<session-id>.jsonl`. Section 19 owns the
# NARRATIVE (it is the section that made the tick read one) and used to own the code too;
# Section 12's stand-down cases need the same primitive, and a second copy of it there would
# be two ideas of what a ListAgents answer looks like. The BODY is always composed by
# tests/lib/live-answer.sh out of the committed corpus, never hand-typed, so separators and
# ref suffixes are the harness's rather than this suite's guess about them.
plant_answer() {  # <transcript file> <state: fresh|stale|none> <name[:status]>...
  local tr="$1" state="$2"; shift 2
  local body
  mkdir -p "$(dirname "$tr")"
  if [ "$state" = "none" ]; then
    printf '{"type":"user","timestamp":"2026-09-05T00:50:00.000Z","message":{"role":"user","content":"go"}}\n' \
      > "$tr"
    return 0
  fi
  body="$(live_answer_body "$@")"
  {
    jq -nc --arg ts "2026-09-05T00:50:00.000Z" \
      '{type:"user",timestamp:$ts,message:{role:"user",content:"go"}}'
    jq -nc --arg ts "2026-09-05T00:51:00.000Z" \
      '{type:"assistant",timestamp:$ts,message:{role:"assistant",content:[{type:"tool_use",id:"toolu_01S19LISTAGENTS",name:"ListAgents",input:{}}]}}'
    jq -nc --arg ts "2026-09-05T00:52:23.349Z" --arg b "$body" \
      '{type:"user",timestamp:$ts,message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_01S19LISTAGENTS",content:$b}]}}'
    [ "$state" = "stale" ] && jq -nc --arg ts "2026-09-05T00:55:00.000Z" \
      '{type:"user",timestamp:$ts,message:{role:"user",content:"anything else?"}}'
  } > "$tr"
  return 0
}

poke_pressure() {  # <repo> <free_mb> <load_1m> <args...>
  local repo="$1" free="$2" load="$3"; shift 3
  BIONIC_PROBE_FREE_MB="$free" BIONIC_PROBE_LOAD_1M="$load" poke "$repo" "$@"
}

# sp_at15 <plan> -> the page a builder here wrote at 14, rewritten as a run at 15 holds it, and that run's log written
#   whole beside it (<docs>/record/<stem>/run.log). The header gains the version and the branches the state section named;
#   the state section, the dispatch ledger and the matrix go; each Tasks row keeps its nine authored cells, read by the
#   table's own header names; and the log holds a step event for each step to current:, the plan's approval when the
#   section carried approved-by:, then per row its dispatch (an agent cell on a row not pending), its tree (a worktree
#   cell) and its landing (status landed). The matrix's criterion is an Eval design row. Instants are fixed and
#   increasing, so the fold reads the lines in the order written.
sp_at15() {
  local p="$1" d n
  d="${p%/*}"; case "$d" in */plans/*) d="${d%/plans/*}" ;; *) d="${d%/plans}" ;; esac
  n="$(basename "$p" .plan.md)"; mkdir -p "$d/record/$n" || return 1
  awk -v lf="$d/record/$n/run.log" '
    function none(s) { gsub(/—|-/, "", s); return s == "" }
    function ev(s) { printf "run/v1|ev=%s|at=2026-10-04T00:%02d:00Z\n", s, ++t > lf }
    function cell(r, k) { return (k in col) ? r[col[k]] : "—" }
    NR == FNR { if (/^current: /) cur = $2; if (/^approved-by: /) ok = 1
      if (/^  base-sha: /) base = $2; if (/^  branch: /) br = $2; if (/^working-branch: /) br = $2
      if (/^integration-branch: /) ib = $2; next }
    FNR == 1 && /^---$/ { fm = 1; print; next }
    fm && /^canonical_sdlc_version:/ { next }
    fm && /^---$/ { fm = 0; print "canonical_sdlc_version: 15"; if (br != "") print "working-branch: " br
      if (base != "") print "base-sha: " base; if (ib != "") print "integration-branch: " ib; print
      for (i = 1; i <= cur; i++) ev("step|n=" i); if (ok) ev("approval|key=step3|by=fixture|said=approved"); next }
    /^## / { skip = ($0 ~ /^## (SDLC State|Dispatch ledger|Verification Matrix)/); tab = ($0 ~ /^## Tasks/); hd = 0
      if ($0 ~ /^## Verification Matrix/) eval = 1 }
    skip { next }
    tab && /^\| *id *\|/ { m = split($0, h, "|"); for (i = 2; i < m; i++) { k = tolower(h[i]); gsub(/^ +| +$/, "", k); col[k] = i }
      print "| id | step | kind | task | deps | size | serves | Files | artifact |"; print "|---|---|---|---|---|---|---|---|---|"; hd = 1; next }
    tab && hd && /^\|---/ { next }
    tab && hd && /^\|/ { split($0, r, "|"); for (i in r) gsub(/^[ \t]+|[ \t]+$/, "", r[i])
      printf "| %s | %s | %s | %s | %s | %s | %s | %s | — |\n", cell(r, "id"), cell(r, "step"), cell(r, "kind"), cell(r, "task"), cell(r, "deps"), cell(r, "size"), cell(r, "serves"), cell(r, "files")
      if (!none(cell(r, "agent")) && cell(r, "status") != "pending") ev("dispatch|row=" cell(r, "id") "|name=" cell(r, "agent"))
      if (!none(cell(r, "worktree"))) ev("tree|row=" cell(r, "id") "|path=.worktrees/" cell(r, "worktree"))
      if (cell(r, "status") == "landed") ev("published|row=" cell(r, "id")); next }
    { print }
    END { if (eval) { print "\n## Eval design\n\n| Requirement | Approach | Criterion | Eval type | Eval | Fails when |\n|---|---|---|---|---|---|"
      print "| REQ-1 | fixture | AC-1.1 | hermetic | `tests/a.test.sh` | the fixture is wrong |" } }' "$p" "$p" > "$p.15" && mv "$p.15" "$p"
}

# ── hoisted from Section 12: sp_plan_at_step — Sections 37–40, 50, 55 and 67 write plans with it. ──
# SP_PLAN_AT=14 asks for the page at 14; unasked, sp_at15 rewrites it as a run at 15 holds it.
sp_plan_at_step() {  # <repo> <current> <row>... -> the plan path
  local repo="$1" current="$2"; shift 2
  local f="$repo/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md" row
  mkdir -p "$(dirname "$f")"
  {
    printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
    printf 'parallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=user\n'
    printf -- '---\n\n# fixture plan\n\n## SDLC State\n\ncurrent: %s\n%s\n\n' "$current" "$SP_APPROVED_LINE"
    printf -- '- Step %s: in progress\n\n' "$current"
    printf '## Tasks\n\n'
    printf '%s' "$SP_TASKS_HEADER"
    for row in "$@"; do printf '%s\n' "$row"; done
  } > "$f"
  [ "${SP_PLAN_AT:-15}" != 15 ] || sp_at15 "$f"
  touch "$f"
  printf '%s' "$f"
}

# ── hoisted from Section 19: s20_ack — session-poker-4 plants acks with it. ──
s20_ack() {  # <repo> <name> <at> — the sweeper ledger's ack line, in its writer's shape
  local le; le="$1/.bionic/tmp/sweeper-${SID}.state"
  [ -f "$le" ] || printf '# bionic session sweeper ledger — schema sweeper-ledger/v1 — machine-local, safe to delete\n' > "$le"
  printf 'sweeper-ledger/v1|event=ack|at=%s|epoch=0|pid=1|session=%s|name=%s|by=patrol|reason=landed\n' \
    "$3" "$SID" "$2" >> "$le"
}

# ── hoisted from Section 26: ack_ledger_of — the release approval prelude reads the ack ledger with it. ──
ack_ledger_of() { printf '%s/.bionic/tmp/sweeper-%s.state' "$1" "${2:-$SID}"; }

# ── hoisted from Section 30: s30_row, s30_last, s30_field — Section 43, AMEND-ROOT, Section 66, Section 67, §SEV and §REPORT-INCL write and read rows with them. ──
s30_row() {  # <repo> <key=value>... — one live row through the one writer
  local repo="$1"; shift
  roster_row_fixture status=identified "session=$SID" name=w1 agent_id=aw1-3000000000000001 \
    "launched_at=$(iso_ago 600)" subagent_type=bionic:implementor source=declared \
    "deliverable=$repo/never-yet.md" duration="2 hours" \
    files=hooks/a.sh suites_allowed=a.test.sh suites_source=declared \
    teammate_id=w1@session-8a41c2e0 tool_use_id=toolu_w1 "$@" >> "$(roster_of "$repo")"
}
s30_last() { grep -F "|name=${2:-w1}|" "$(roster_of "$1")" | tail -1; }
s30_field() { printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

# ── hoisted from Section 31: s31_transcript, s31_stop, s31_reason, s31_decision — Sections 65 and 67 drive the Stop hook with them (each shard that calls s31_stop names S31_STOP_HOOK itself). ──
s31_transcript() {  # <repo> <text>... -> the transcript path
  local repo="$1"; shift
  local tr="$repo/transcript.jsonl"
  : > "$tr"
  local t
  for t in "$@"; do
    jq -nc --arg x "$t" '{type:"user",isSidechain:false,userType:"external",
                          message:{role:"user",content:$x}}' >> "$tr"
  done
  printf '%s' "$tr"
}
s31_stop() {  # <repo> <transcript> -> sets S31_OUT, S31_RC
  S31_OUT="$(env CLAUDE_CODE_SESSION_ID="$SID" bash "$S31_STOP_HOOK" <<EOF 2>/dev/null
$(jq -nc --arg t "$2" --arg c "$1" --arg s "$SID" \
   '{session_id:$s,transcript_path:$t,cwd:$c,hook_event_name:"Stop",stop_hook_active:false}')
EOF
)"
  S31_RC=$?
}
s31_reason() { printf '%s' "$S31_OUT" | jq -r '.reason // ""' 2>/dev/null; }
s31_decision() { printf '%s' "$S31_OUT" | jq -r '.decision // ""' 2>/dev/null; }

# ── hoisted from Section 34: s34_plan — Sections 37, 42, 49, 51 and §ROW-LABEL build the gate-admitted plan with it. ──
s34_plan() {  # <repo> <current> [step-4 block body] -> the plan path; the session is bound to it
  local repo="$1" cur="$2" block="${3:-}" f
  f="$repo/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
  mkdir -p "$(dirname "$f")" "$repo/.bionic/docs/specs/epic-99-fixture"
  printf '# requirements\n' > "$repo/.bionic/docs/specs/epic-99-fixture/wave-01-fixture.requirements.md"
  printf '# spec\n' > "$repo/.bionic/docs/specs/epic-99-fixture/wave-01-fixture.spec.md"
  [ -n "$block" ] || block='  worktree: .worktrees/01-fixture
  base-sha: abc1234
  branch: wave/01-fixture'
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: bugfix\n'
    printf 'rigor: double\nscale: wave\nmulti_agent: true\nuse_worktree: true\nhas_ui: false\n'
    printf 'walk: exempt\ndeploy_target: n/a\n'
    printf 'parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=user\n---\n\n'
    printf '# fixture wave\n\n## SDLC State\n\ncurrent: %s\n' "$cur"
    printf 'approved-by: fixture 2026-09-23T00:00Z "approved"\n\n'
    printf -- '- Step 1: requirements: specs/epic-99-fixture/wave-01-fixture.requirements.md\n'
    printf -- '- Step 2: spec: specs/epic-99-fixture/wave-01-fixture.spec.md\n'
    printf -- '- Step 3: plan: plans/epic-99-fixture/wave-01-fixture.plan.md\n'
    printf -- '- Step 4: opened\n%s\n' "$block"
    [ "$cur" = 5 ] && printf -- '- Step 5: (pending)\n'
    printf -- '- T1: landed at record/T1.md\n- T2: dispatched to w-T2\n- T5: pending dispatch — .worktrees/01-T5\n\n'
    printf '## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T1 | 4 | build | the first build | implementor | — | 30 | REQ-1 | a.sh | — | — | landed |\n'
    printf '| T2 | 4 | build | the second build | implementor | — | 30 | REQ-1 | b.sh | 01-T2 | abc1234 | active |\n'
    printf '| T5 | 5 | verify | the floor | test-runner | T1, T2 | 30 | REQ-1 | — | — | — | pending |\n\n'
    printf '## Verification Matrix\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n'
    printf '| AC-1.1 | T2 | pending | — | — |\n\nAC-1.1:\n  provenance: fixture\n  fails-when: the fixture is wrong\n'
  } > "$f"
  [ "${SP_PLAN_AT:-15}" != 15 ] || sp_at15 "$f"
  bound_marker "$repo" "$SID" "$f" >/dev/null 2>&1
  printf '%s' "$f"
}

# ── hoisted from Section 34: s34_gate — every later shard drives the real commit gate with it. ──
# S34_GATE <repo> -> rc of the REAL commit gate on a main-root `git commit` in this session.
s34_gate() {
  local repo="$1" input
  input="$(jq -n --arg s "$SID" --arg cwd "$repo" '{session_id: $s, cwd: $cwd,
    hook_event_name: "PreToolUse", tool_name: "Bash",
    tool_input: {command: "git commit -m x"}, tool_use_id: "toolu_s34"}')"
  GATE_ERR="$( cd "$repo" && CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$SID" BIONIC_WALL_VERBOSE=1 \
    bash "${BIONIC_HOOKS_DIR}/bash-walls.sh" <<< "$input" 2>&1 >/dev/null )"
  GATE_RC=$?
}

# s34_gate15 <repo> <plan> -> GATE_RC, GATE_ERR of a main-checkout commit judged against the run at 15 the plan's run at 14
#   stands for: a twin of the plan rewritten by sp_at15 (the header naming its branch, base, epic and wave; the log its
#   steps, approval and rows), the run's own log after them, bound for that commit alone, then taken away and the plan
#   bound again. The commit gate refuses an open run at 14, so a world built at 14 for what the translation reads asks
#   the gate of its run as this release carries it.
s34_gate15() {
  local p="$2" t r n e
  n="$(basename "$p" .plan.md)"; e="$(basename "${p%/*}")"; t="${p%/*}/$n-at15.plan.md"; r="${p%/plans/*}/record"
  rm -rf "$t" "$r/$n-at15"; cp "$p" "$t"; sp_at15 "$t"
  awk -v e="$e" -v w="$n" 'NR == 1 { print; next } !d && /^---$/ { if (!ep) print "epic: " e; if (!wv) print "wave: " w; d = 1 }
    !d && /^epic: / { ep = 1 } !d && /^wave: / { wv = 1 } { print }' "$t" > "$t.x" && mv "$t.x" "$t"
  [ ! -f "$r/$n/run.log" ] || cat "$r/$n/run.log" >> "$r/$n-at15/run.log"
  bind_marker "$1" "$t"; s34_gate "$1"; bind_marker "$1" "$p"
  rm -rf "$t" "$r/$n-at15"
}

# ── hoisted from Section 42: s42_plan, s42_snap, s42_unchanged, s42_builds_landed — every later shard builds, snapshots and compares plans with them. ──
s42_plan() {  # <repo> <current> [step-4 block body] -> the plan path; bound, committed
  local p; p="$(s34_plan "$1" "$2" "${3:-}")"
  [ "${SP_PLAN_AT:-15}" = 15 ] || printf '\n## Dispatch ledger\n\n| id | agent | dispatched | expected | artifact | landed | notes |\n' >> "$p"
  [ "${SP_PLAN_AT:-15}" = 15 ] || printf '|---|---|---|---|---|---|---|\n| T1 | implementor (w-T1) | 2026-10-03T00:00Z | 30 min | record/T1.md | landed | batch 1 |\n' >> "$p"
  ( cd "$1" && git add -f "$p" && git commit -qm plan ) >/dev/null 2>&1
  printf '%s' "$p"
}
s42_snap() {  # <repo> <plan> -> commit the plan and keep a byte copy for the cmp rows
  ( cd "$1" && git add -f "$2" && git commit -qm snap ) >/dev/null 2>&1
  cp "$2" "$TMPROOT/s42-before"
}
s42_unchanged() {  # <label> <want rc> <plan>
  expect_eq "$1 — refused (exit $2)" "$2" "$RC"
  expect_true "$1 — …and the plan is byte-identical (cmp)" cmp -s "$TMPROOT/s42-before" "$3"
}
# s42_builds_landed <plan> -> the fixture's active build row T2 written landed, as T1 is: a whole
# read is registered only once no build row is pending or active (wave-27 T45; D10).
s42_builds_landed() {
  awk '/^\| T2 \| 4 \| build \|/ { $0 = "| T2 | 4 | build | the second build | implementor | — | 30 | REQ-1 | b.sh | — | — | landed |" } { print }' \
    "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# ── hoisted from Section 47 §WAIT: s47_plan, s47_lines — Section 59, §SEV, §RC-DEFER and §MOVE-PASTED write reads tables and read tick lines with them. ──
s47_plan() {  # <repo> <writers> <row>... -> the path; a reads table, approved, current: 4
  local repo="$1" writers="$2"; shift 2
  local f="$repo/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md" row
  mkdir -p "$(dirname "$f")"
  {
    printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
    printf 'parallel-budget: writers=%s suites=2 worktrees=8 test_jobs=8 source=user\n' "$writers"
    printf -- '---\n\n# fixture plan\n\n## SDLC State\n\ncurrent: 4\n%s\n\n- Step 4: in progress\n\n' "$SP_APPROVED_LINE"
    printf '## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | status | reads |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
    for row in "$@"; do printf '%s\n' "$row"; done
  } > "$f"
  [ "${SP_PLAN_AT:-15}" != 15 ] || sp_at15 "$f"
  touch "$f"
  printf '%s' "$f"
}
s47_lines() { printf '%s\n' "$OUT" | /usr/bin/grep "^poker: $1 " ; }  # <WAIT|FILL|CHAIN>

# ── hoisted from Section 46 §PROOF-ADD: s46_last, s46_proved — shards 3 and 4 read proof lines with them (each names S46_LIB itself). ──
s46_last() {  # <plan> <kind> -> proof_last's answer, from the library itself
  bash -c '. "$1" && proof_last "$2" "$3"' _ "$S46_LIB" "$1" "$2" 2>/dev/null
}
s46_proved() { bash -c '. "$1" && proof_lines "$2"' _ "$S46_LIB" "$1" 2>/dev/null; }  # <plan> -> the run's proofs through the proof library's reader, each in an older plan's line shape

# ── hoisted from Section 48 §READY-EARLY (review half): s48_row, s48_fill_has — Section 59 reads rows and FILL lines with them. ──
s48_row() {  # <plan> <id> -> the row's cells, `|`-joined and trimmed: id|…|status|reads
  awk -F'|' -v id="$2" '{ c = $2; gsub(/^[ \t]+|[ \t]+$/, "", c) } c == id {
    o = ""; for (i = 2; i < NF; i++) { v = $i; gsub(/^[ \t]+|[ \t]+$/, "", v); o = o (i > 2 ? "|" : "") v }
    print o; exit }' "$1"
}
s48_fill_has() {  # <id> -> yes when the tick's FILL line names it
  case " $(s47_lines FILL | sed 's/^poker: FILL //') " in *" $1 "*) printf yes ;; *) printf no ;; esac
}

# ── hoisted from Section 55 §RECON-PLAN: SRP_ROW1, SRP_ROW2 — Section 67 plants the same two rows. ──
SRP_ROW1="| T1 | 4 | build | waits on CI | implementor | ext:ci-rp | 15m | REQ-x | a.sh | pending |"
SRP_ROW2="| T2 | 4 | build | waits on CI too | implementor | ext:ci-rp | 15m | REQ-x | b.sh | pending |"

# ── hoisted from Section 57 §JUDGE §WHOLE §WAIVE: s57_commit — Section 64, Sections 66–68, §SEV, §RC-DEFER and §PASS-KEY commit with it. ──
s57_commit() {  # <checkout> <path> <message> -> the head after one commit touching <path>
  mkdir -p "$1/$(dirname "$2")"; printf '%s\n' "$3" >> "$1/$2"
  ( cd "$1" && git add -f "$2" && git commit -qm "$3" ) >/dev/null 2>&1
  git -C "$1" rev-parse HEAD
}

# ── hoisted from Section 59 §RANGE-Q: S59_REL — the hoisted s59w_q names the record directory with it. ──
S59_REL=".bionic/docs/record/wave-01-fixture"

# ── hoisted from Section 59 §RANGE-Q: s59_world — §60's world, which §LINE-TELL and §REPORT-RTL build, is built on it. ──
# s59_world <label> <state lines, @A @B @C for the three commits> <rows...> -> R59W, P59W and
# S59W_A/B/C: §59's repository shape, one plan, the rows given in a reads table.
s59_world() {
  local lab="$1" st="$2"; shift 2
  R59W="$(make_repo "$lab")"; new_roster "$R59W"; ( cd "$R59W" && git commit -q --allow-empty -m init )
  # A BASE THE JUDGE CAN HOLD (wave-36 T28; D9): live:head asks facts_state, which judges only a plan whose base-sha:
  # is a commit, so the Step-4 block names the init commit, not s42_plan's placeholder.
  P59W="$(SP_PLAN_AT=14 s42_plan "$R59W" 4 "  worktree: .worktrees/01-fixture
  base-sha: $(git -C "$R59W" rev-parse --short=8 HEAD)
  branch: wave/01-fixture")"
  # EACH LANDING TOUCHES CODE (wave-36 T28; D9): the judge reads a commit that touches nothing as prose, and a
  # review row is ready again only past a commit that owes, so A, B and C each change a.sh.
  ( cd "$R59W" && git worktree add -q -b wave/01-fixture "$R59W/.worktrees/01-fixture" \
    && for c in A B C; do printf '%s\n' "$c" >> "$R59W/.worktrees/01-fixture/a.sh" \
         && git -C "$R59W/.worktrees/01-fixture" add a.sh && git -C "$R59W/.worktrees/01-fixture" commit -q -m "landing $c"; done ) >/dev/null 2>&1
  S59W_A="$(git -C "$R59W/.worktrees/01-fixture" rev-parse HEAD~2 2>/dev/null)"
  S59W_B="$(git -C "$R59W/.worktrees/01-fixture" rev-parse HEAD~1 2>/dev/null)"
  S59W_C="$(git -C "$R59W/.worktrees/01-fixture" rev-parse HEAD 2>/dev/null)"
  st="${st//@A/$S59W_A}"; st="${st//@B/$S59W_B}"; st="${st//@C/$S59W_C}"
  printf '%s\n' "$@" > "$R59W.rows"; printf '%s\n' "$st" > "$R59W.st"
  awk -v sf="$R59W.st" -v rf="$R59W.rows" '
    /^current: / && !wb { print; print "working-branch: wave/01-fixture"; while ((getline l < sf) > 0) if (l != "") print l; wb = 1; next }
    /^\| id \| step \|/ { intab = 1
      print "| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |"
      print "|---|---|---|---|---|---|---|---|---|---|---|---|---|"
      while ((getline l < rf) > 0) print l
      next }
    intab && /^\|/ { next }
    { intab = 0; print }' "$P59W" > "$P59W.tmp" && mv "$P59W.tmp" "$P59W"
  ( cd "$R59W" && git add -f "$P59W" && git commit -qm rows ) >/dev/null 2>&1
  rm -f "$R59W/.bionic/tmp/tick-digest-$SID.state"
}

# ── hoisted from Section 59 §RANGE-Q: S59W_T5 — the hoisted s60_world plants the floor row with it. ──
S59W_T5="| T5 | 5 | verify | the floor | test-runner | — | 30 | REQ-1 | — | — | — | pending |  |"

# ── hoisted from Section 59 §RANGE-Q: s59w_q — the hoisted s60_world plants a read row with it. ──
s59w_q() {  # <id> <questions> -> a read row
  printf '| %s | 6 | review | the read row | critic | — | 30 | REQ-1 | %s/%s.md | — | — | pending | approval:plan, live:head:%s |' "$1" "$S59_REL" "$1" "$2"
}

# ── hoisted from Section 60 §MOVED: S60_T1, S60_T7, S60_T8, s60_whole, s60_world — §LINE-TELL and §REPORT-RTL build §60's world with them. ──
S60_T1="| T1 | 4 | build | landed before the whole read | implementor | — | 30 | REQ-1 | a.sh | — | — | landed |  |"
S60_T7="| T7 | 4 | build | a fix | implementor | — | 30 | REQ-2 | b.sh | — | — | landed |  |"
S60_T8="| T8 | 4 | build | another fix | implementor | — | 30 | REQ-4, REQ-5 | c.sh | — | — | landed |  |"
s60_whole() {  # <head> <scope> -> a structure reading's proof line
  printf 'proved: kind=review head=%s at=2026-10-04T10:01:00Z evidence=record/wave-01-fixture/st-whole.md question=structure reader=w-rev result=pass scope=%s' "$1" "$2"
}
s60_world() {  # <label> <whole head @A|@C> <scope> -> R59W, P59W: §59's shape plus a matrix
  s59_world "$1" "$(s60_whole "$2" "$3")" "$S60_T1" "$S60_T7" "$S60_T8" "$(s59w_q T3 structure)" "$S59W_T5"
  printf '\n## Verification Matrix\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n' >> "$P59W"
  printf '| AC-%s | T2 | pending | record/wave-01-fixture/x.md | |\n' 1.1 2.1 2.2 4.1 5.1 >> "$P59W"
  ( cd "$R59W" && git add -f "$P59W" && git commit -qm matrix ) >/dev/null 2>&1
  S60_INIT="$(git -C "$R59W" rev-parse "$S59W_A~1" 2>/dev/null)"
  S60_REC="$R59W/.bionic/docs/record/wave-01-fixture/landing-proofs.log"; mkdir -p "${S60_REC%/*}"; : > "$S60_REC"
}

# ── hoisted from Section 60 §MOVED: s60_tick — §LINE-TELL ticks §60's world with it. ──
s60_tick() { rm -f "$R59W/.bionic/tmp/tick-digest-$SID.state"; poke_pressure "$R59W" 8192 1.0 tick; }
