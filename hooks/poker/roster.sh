# shellcheck shell=bash
# hooks/poker/roster.sh — the roster: the runs, adoption, the launch sync and the sweep (adopt, sweep, bind,
# extend, hold, rule, ruling-ack, rulings, launch-sync, wait, stop-run, regression-runs).
#
# A part of hooks/session-poker.sh, which sets every global and loads this file before any verb runs. A part
# defines functions only, and is never run by itself.

# ---------------------------------------------------------------- the agent name
#
# THE NAME A DISPATCH USES IS DERIVED, NEVER CHOSEN (T22, A-orch-33; Chris, first
# principles: the roster is the identity register).
#
# `fill_name` AND ITS REASONING MOVED TO payload/scripts/lib/fill.sh (wave-18 REQ-3, D2).
# It went where the ready set went: `payload/scripts/lib/stop.sh`'s fill duty names rows this
# tick may also have printed, and a second idea of which name is free would let the two
# disagree about what "dispatch T5" means. The body is unchanged, and the tick and `adopt`
# call it exactly as they did.

# ---------------------------------------------------------------- adoption
#
# WHAT A `/clear`+RESUME ACTUALLY LOSES, and what it does not. Lost: the completion message
# (the CLI delivers it to the conversation that dispatched, and that conversation is gone)
# and the orchestrator's in-memory dispatch ledger. NOT lost: the agent itself — same
# process, still working — its artifacts, its transcript under
# `<config>/projects/<slug>/<old-sid>/subagents/agent-<id>.jsonl`, and its roster row, which
# lives in the PROJECT's `.bionic/tmp` rather than in any session.
#
# So the successor session can read every one of those files and still be unable to ACT on
# the agent, because the one thing it cannot re-derive is the AGENT ID — the identity the
# CLI handed back at launch and only the dead conversation held. `SendMessage` and
# `TaskStop` both take it, and hooks/stop-guard.sh refuses a stop by NAME for exactly this
# reason ("a NAME is not an identity — it is reused across waves"), naming the full agent id
# as the deliberate way through. The id is on disk the whole time: hooks/execution-recorder.sh
# writes it onto the row as `status=identified|agent_id=`.
#
# `adopt` is the verb that reads it back. For every roster in this project's `.bionic/tmp`
# that belongs to some OTHER session, it prints each row that is still open, its id, and the
# three addresses derived from that id — observe, message, stop — plus a verdict taken from
# disk rather than from memory.
#
# IT WRITES EXACTLY ONE THING, AND IT IS THIS SESSION'S OWN ROSTER. Everything else this
# verb touches is read: no PREDECESSOR roster is ever written (that session may still be
# appending to it), no Patrol stamp is taken (this is not a tick and must not age the
# arming wall's clock), and nothing is stopped or messaged.
#
# The one write is the adoption itself, and it exists because printing an id was only half
# a cure (epic-20 W1 B-1). Every wall downstream of the id asks THIS session's roster
# whether the agent is ours — hooks/stop-guard.sh establishes ownership from a
# `confirmed`/`identified` row carrying the resolved id, hooks/stop-check.sh classifies
# from the same accepted set — so with no row of ours the predecessor's agent classifies
# FOREIGN and every stop of it is refused. `adopt_write_row` below is the successor saying
# on disk what this verb has just said on the terminal: this contract is mine now.
#
# THIS SESSION'S OWN ROWS ARE NEVER ADOPTED. They are not lost — the running session still
# holds them — and printing them would invite the successor to re-ledger work it is already
# tracking, which is the double-counting the roster exists to prevent.

# ---------------------------------------------------------------- the runs (wave-30 T12; D6, D7d)
#
# A RUN IS AN OBJECT, MADE AT THE SHIM (payload/scripts/booked.sh --detach, wave-30 T8). Its files
# sit side by side under `<project>/.bionic/tmp/runs`: `<id>.log` (its output, last line `rc=<n>`),
# `<id>.log.pid` (the detached shim's pid, the session leader of everything the run started),
# `<id>.log.rc` (its code, written last, by the detached side alone) and `<id>.log.progress.tsv`
# (a line per suite and per section as it opens). With --agent naming a row, the row carries the
# record too: `run_pid= run_log= run_head= run_cmd= run_started_at=` at the start, `run_rc=
# run_ended_at=` at the end (lib/roster.sh `roster_mark_run`). These readers serve `wait`,
# `stop-run`, `adopt`, the tick's RUNNING lines and `regression-runs`, one reading for all five.
#
# THREE STATES, AND NO FOURTH. FINISHED: the row carries `run_rc`, or `<log>.rc` holds a code.
# RUNNING: neither, and the pid is alive AND is still that run's detached shim (`ps` names
# booked.sh with `--run-log <log>`; a pid the system gave to someone else is not the run). LOST:
# neither, and the pid is dead or is no longer the run's — reported with the time its log was
# last written. A LOST run is never called a timeout: nothing here knows a limit was reached.
# Set in hooks/session-poker.sh, before any part loads: RUN_LOG, RUN_PID, RUN_NAME, RUN_ROSTER, RUN_ROW_RC,
# RUN_STARTED, RUN_STATE, RUN_RC, RUN_ID, RUN_LAST_WRITTEN, RUN_PROGRESS, RUN_ELAPSED.

# run_find <project root> <name | run id | log path> -> RUN_* for the run that operand names; 1 when
# none. A NAME is looked up on every roster of the project (this session's and a predecessor's: a
# run outlives the session that started it), and the newest start wins. A RUN ID (the `run=` the
# shim printed, `<agent>-<suites>[-<n>]`) or a log path is read off the runs directory, for a run no
# row records (the main thread's).
run_find() {
  local repo="$1" arg="$2" rf row best="" bestrf="" s bs=""
  RUN_LOG=""; RUN_PID=""; RUN_NAME=""; RUN_ROSTER=""; RUN_ROW_RC=""; RUN_STARTED=""
  [ -n "$arg" ] || return 1
  case "$arg" in
    /*.log)
      [ -f "$arg" ] || return 1
      RUN_LOG="$arg"; RUN_NAME="$(basename "$arg" .log)" ;;
    *)
      for rf in "$repo/.bionic/tmp"/roster-*.state; do
        row="$(run_row_of "$rf" "$arg")" || continue
        [ -n "$row" ] || continue
        s="$(line_field "$row" run_started_at)"
        if [ -z "$best" ] || [ "$s" \> "$bs" ]; then best="$row"; bestrf="$rf"; bs="$s"; fi
      done
      if [ -n "$best" ]; then
        run_load_row "$best" "$bestrf" || return 1
      else
        case "$arg" in */*|.*) return 1 ;; esac
        [ -f "$repo/.bionic/tmp/runs/$arg.log" ] || return 1
        RUN_LOG="$repo/.bionic/tmp/runs/$arg.log"; RUN_NAME="$arg"
      fi ;;
  esac
  [ -n "$RUN_PID" ] || { read -r RUN_PID < "$RUN_LOG.pid"; } 2>/dev/null
  return 0
}

# run_groups <pid> -> the process groups of <pid> and every process below it, one per line. The
# detached shim leads its own session and group, and runs its command in a group of its own (set -m),
# so stopping the run's group alone could leave the command running.
run_groups() {
  ps -ax -o pid= -o ppid= -o pgid= 2>/dev/null | awk -v root="$1" '
    { pp[$1] = $2; pg[$1] = $3; n[NR] = $1 }
    END {
      keep[root] = 1; changed = 1
      while (changed) { changed = 0
        for (i in n) { p = n[i]; if (!(p in keep) && (pp[p] in keep)) { keep[p] = 1; changed = 1 } } }
      for (p in keep) if (p in pg) g[pg[p]] = 1
      for (x in g) print x
    }'
}

# THE GATE'S HALF OF stop-run (wave-36 T11; D8, REQ-2 AC-2.2). A shim parked in `gate_ask` is no detached run:
# no `.bionic/tmp/runs/` log names it, and before D8 `gate_end` refused its never-admitted request. The verb
# reads the gate's store through lib/gate.sh's own reader and rule (`_gate_read`, `_gate_open`), never a copy.
#
# stop_run_request <operand> -> SR_REQ and rc 0 when the operand names a gate request: a whole number names
# that request's file (run ids are never bare numbers: `<agent>-<suites>[-<n>]`); a name names the one OPEN
# request whose who's agent half it is. rc 1 when it names none; rc 2 with the ids, lowest first, in
# SR_REQS when a name holds more than one open request — nothing is guessed.
stop_run_request() {
  local arg="$1" gd f
  SR_REQ=""; SR_REQS=""
  declare -F _gate_read >/dev/null 2>&1 && declare -F gate_dir >/dev/null 2>&1 || return 1
  gd="$(gate_dir)"
  case "$arg" in
    ''|*[!0-9]*) : ;;
    *) [ -f "$gd/requests/$arg" ] || return 1; SR_REQ="$arg"; return 0 ;;
  esac
  for f in "$gd"/requests/[0-9]*; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    _gate_read "$f" 2>/dev/null || continue
    [ "${_R_who#*:}" = "$arg" ] || continue
    _gate_open || continue
    SR_REQS="$SR_REQS ${f##*/}"
  done
  SR_REQS="$(printf '%s\n' $SR_REQS | sort -n | tr '\n' ' ')"; SR_REQS="${SR_REQS% }"
  case "$SR_REQS" in '') return 1 ;; *' '*) return 2 ;; esac
  SR_REQ="$SR_REQS"
  return 0
}

# stop_run_record <key=value>... -> appends `line/v1|ev=stop-run|…` (lib/line.sh `line_event`) to the landing
# record of the run this session is bound to; rc 1, nothing written, with no bound run. The hand-hold fold
# (`hand_holds_report`) counts it under its own kind: a stop is a verb act, never a by-hand one.
stop_run_record() {
  local sid
  sid="$(session_id 2>/dev/null)" || sid=""
  [ -n "$sid" ] || return 1
  resolve_run "$REPO_REAL" "$sid" 2>/dev/null
  [ -n "$POKER_RUN_PLAN" ] && [ -f "$POKER_RUN_PLAN" ] || return 1
  declare -F line_event >/dev/null 2>&1 || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1
  declare -F line_event >/dev/null 2>&1 || return 1
  line_event "$POKER_RUN_PLAN" stop-run "$@"
}

# stop_run_gate <id> -> stops gate request <id> and says what it did; rc 0, or 2 when the end could not be
# written. THE ORDER: the end is written first, `gate_end <id> 143 --by <sid> --why <reason>` (accepted on a
# never-admitted id from this call alone), so the parked or running shim, TERMed next, finds its request
# ended and its own trap's end changes nothing; then its holder's process group is TERMed (never this call's
# own group: then the holder alone), KILLed after 5 s if it lives on; then the record line.
stop_run_gate() {
  local id="$1" gd f sid who kind key state hp hs pg self what i rec=""
  gd="$(gate_dir)"; f="$gd/requests/$id"
  _gate_read "$f" 2>/dev/null || { die "stop-run — gate request $id cannot be read"; return 2; }
  who="${_R_who#*:}"; kind="$_R_kind"; key="${_R_key//|/ }"
  if [ -n "$_R_ended" ]; then
    say "stop-run request $id ${who:--} $kind $key — ended rc=${_R_rc:--}; nothing to stop"
    return 0
  fi
  _R_state=""; _gate_open 2>/dev/null || :
  state="$_R_state"
  hp=""; hs=""
  if _gate_alive; then hp="${_R_holder%%:*}"; hs="${_R_holder#*:}"; fi
  if [ "$SR_REPORT_ONLY" = yes ]; then
    if [ -n "$hp" ]; then what="would end it and TERM its holder's process group (pid $hp)"; else what="would end it; its holder is gone"; fi
    say "stop-run request $id ${who:--} $kind $key — $state; $what (report-only: nothing was sent)"
    return 0
  fi
  sid="$(session_id 2>/dev/null)" || sid=""; sid="${sid:-none}"
  if ! gate_end "$id" 143 --by "$sid" --why "${SR_WHY:--}" 2>/dev/null; then
    die "stop-run — gate request $id could not be ended (the gate's store or lock); nothing was sent"
    return 2
  fi
  what="its holder is gone, so nothing was sent"
  if [ -n "$hp" ]; then
    self="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')"
    pg="$(ps -o pgid= -p "$hp" 2>/dev/null | tr -d ' ')"
    case "$pg" in ''|0|1|*[!0-9]*) pg="" ;; esac
    [ "$pg" != "$self" ] || pg=""
    if [ -n "$pg" ]; then kill -TERM -- "-$pg" 2>/dev/null || kill -TERM "$hp" 2>/dev/null
    else kill -TERM "$hp" 2>/dev/null; fi
    what="TERM"
    i=0
    while [ "$i" -lt 50 ] && _slots_live "$hp" "$hs"; do sleep 0.1; i=$((i + 1)); done
    if _slots_live "$hp" "$hs"; then
      if [ -n "$pg" ]; then kill -KILL -- "-$pg" 2>/dev/null; fi
      kill -KILL "$hp" 2>/dev/null
      what="TERM, then KILL"
    fi
    what="its holder's process group stopped ($what)"
  fi
  stop_run_record "request=$id" "who=${_R_who//|/ }" "kind=$kind" "key=$key" "by=$sid" "why=${SR_WHY:--}" \
    || rec="; no bound run, so no ev=stop-run line was written"
  say "stop-run request $id ${who:--} $kind $key — $state; ended by=$sid why=${SR_WHY:--}, $what$rec"
  return 0
}

# THE REPORT, RECOVERED FROM THE TRANSCRIPT — the recovery skills/canonical-sdlc/SKILL.md
# §Dispatch already prescribes by hand ("the report is the last long `assistant` text block
# in that agent's file"), done by machine. Each assistant entry's text blocks are joined and
# re-emitted as ONE JSON string per entry, because a text block spans lines and a
# line-oriented pass would cut a report in half. The LAST block over the floor wins; if
# nothing clears it, the last block of any size does, so a short-report agent is quoted
# rather than dropped.
#
# It is a QUOTE, not an artifact. SKILL.md's own rule stands: persist it under
# `<docs-root>/record/` before acting on it — a transcript is one cleanup away from gone.
#
# AND IT IS UNTRUSTED TEXT. What is quoted here is whatever the agent typed, printed into
# the operator's terminal by a verb they ran to find out what a predecessor left behind —
# an escape sequence in it would repaint or rewrite that terminal rather than be read. The
# control characters are stripped for that reason, tab and newline excepted because the
# report's own line structure is what the caller indents.
agent_report_tail() {  # <transcript> -> the tail on stdout, nonzero if nothing to quote
  local raw
  [ -f "$1" ] || return 1
  command -v jq >/dev/null 2>&1 || {
    printf '(report tail unavailable: jq is not on PATH)'
    return 0
  }
  raw="$(jq -r 'select(.type == "assistant")
                | ((.message.content // []) | map(select(.type == "text") | .text) | join("\n"))
                | select(length > 0)
                | @json' "$1" 2>/dev/null \
    | awk -v min="$ADOPT_TAIL_MIN" '
        { any = $0 }
        length($0) - 2 >= min { last = $0 }
        END { if (last != "") print last; else if (any != "") print any }')"
  [ -n "$raw" ] || return 1
  # THE C1 BLOCK GOES TOO (Step-6 security review S-6). `tr -d '\000-\010\013-\037\177'`
  # removes ESC and DEL and leaves `U+0080`–`U+009F` — of which `U+009B` is CSI, a control
  # sequence introducer that needs no ESC in front of it on a terminal that honours C1. Those
  # arrive as the two UTF-8 bytes `0xC2 0x80`–`0xC2 0x9F`, which a byte-oriented `tr` cannot
  # name, so the pair is deleted by `sed` before the byte-wise strip runs. Ordered first
  # because the byte strip would otherwise leave a bare `0xC2` behind.
  printf '%s' "$raw" | jq -r '.' 2>/dev/null \
    | LC_ALL=C sed 's/'"$(printf '\302')"'['"$(printf '\200')"'-'"$(printf '\237')"']//g' \
    | tr -d '\000-\010\013-\037\177' | head -c "$ADOPT_TAIL_CAP"
}

# ONE FOLD PER PREDECESSOR ROSTER, and the same rule the fleet's other three folds keep: the
# file is append-only, a contract advances along it (`intended` -> `confirmed` ->
# `identified`), every writer copies the contract fields forward, so the LAST row carrying a
# name is the authoritative one (tests/cross-gate-agreement.test.sh §P). Two departures,
# both because this fold answers a question the others do not:
#
#   THE ID IS TAKEN OFF `identified`/`confirmed` ONLY, never off `intended` — the same
#   accepted set hooks/stop-guard.sh and hooks/stop-check.sh use for ownership, and for the
#   same reason: `intended` carries `agent_id=` empty by design, and a row that never
#   advanced past it has no identity to offer. That row is the UNADDRESSABLE case, reported
#   with its cure rather than skipped, because a silent skip is how a predecessor's agent
#   becomes invisible twice.
#
#   A ROW IS CLOSED BY AN ACK TAKEN AFTER ITS LATEST LAUNCH, and by nothing else — the one
#   close predicate, `roster_open_names` (payload/scripts/lib/roster.sh; epic-23 wave-20 T2,
#   D10; ADR-034 d1), which dispatch preflight, the sweeper's `acked=` and the stop wall's
#   occupancy ask too. The ack ledger binds across sessions ("an ack taken in a session that
#   has since died is still in force in its successor"). A `landing-swept/v1` marker closes
#   NOTHING here, MET or not: until wave-20 a MET marker did, so an agent swept MET and never
#   acked — still alive on the panel — came out of a `/clear` with no row on the new roster,
#   and no stop could reach it (the code in `roster_open_names` is the rule). An ack older than a
#   relaunch closes nothing either: the relaunched agent is the one to adopt.
#
# THE ORIGIN IS CARRIED OUT WITH THE ROW, and it is what the stop address is built from
# (T3 FINDING 1). `adopted_from=` wins over `session=` when the row has one: a row that was
# itself adopted is filed under the session that TOOK it, while the harness's teammate table
# keeps naming the session that made the `Agent` call, and `adopted_from` is the only field
# on the row that still points there. Absent both, the caller falls back to the roster
# file's own session — the invariant every roster writer keeps.
#
# Output is one `|`-delimited record per open row. `|` rather than a tab because every value
# on a roster row is cleaned of `|` at write time, while the shell collapses runs of tabs
# and would silently merge two empty fields into one.
adopt_fold() {  # <roster file> <ack ledger> -> name|id|type|deliverable|progress|cadence|launched_at|origin|plan|waiver|suites_source|done|lands_red|red_evidence|row|<source row: the merged list fields, row-shaped>
  # THE OPEN SET IS ASKED ONCE, of the one predicate, over the predecessor's roster as it
  # stands — no session filter, because every row on it carries the predecessor's own id.
  # Handed to awk through the environment rather than `-v`, which would read a backslash in
  # a name as an escape.
  AF_OPEN="$(roster_open_names "$1" "$2")" AF_LISTS="$ROSTER_LIST_FIELDS" AF_SCHEMA="roster-state/${ROSTER_SCHEMA_VERSION}" awk '
    function kv(line, key,   n, a, i, eq, k) {
      n = split(line, a, "|")
      for (i = 1; i <= n; i++) {
        eq = index(a[i], "=")
        if (eq == 0) continue
        k = substr(a[i], 1, eq - 1)
        if (k == key) return substr(a[i], eq + 1)
      }
      return ""
    }
    BEGIN {
      no = split(ENVIRON["AF_OPEN"], ol, "\n")
      for (i = 1; i <= no; i++) if (ol[i] != "") isopen[ol[i]] = 1
      nl = split(ENVIRON["AF_LISTS"], lf, " ")
    }
    /^roster-state\/v1\|/ {
      n = kv($0, "name"); if (n == "") next
      if (!(n in seen)) { seen[n] = 1; order[++cnt] = n }
      v = kv($0, "subagent_type"); if (v != "") stype[n] = v
      v = kv($0, "deliverable");   if (v != "") deliv[n] = v
      v = kv($0, "progress");      if (v != "") prog[n]  = v
      v = kv($0, "cadence");       if (v != "") cad[n]   = v
      v = kv($0, "launched_at");   if (v != "") launch[n] = v
      v = kv($0, "session");       if (v != "") sess[n]   = v
      v = kv($0, "adopted_from");  if (v != "") afrom[n]  = v
      # THE WAIVER, carried forward the same way the contract fields are (S17, AC-12 attempt
      # 2). Before this fix it was the one field this fold read off the source row and then
      # dropped: `adopt_write_row` hard-coded `waiver=` empty on every adopted row, so a
      # dispatch this session waived at launch came out the far side of a clear looking like
      # one that never was — the `verdict_row` function in hooks/session-sweeper.sh reads
      # `waiver=` straight off the row (no marker involved) and calls a non-empty one WAIVED
      # before it ever asks about a deliverable, so an empty copy verdicted as an unmet
      # SILENT row instead.
      v = kv($0, "waiver");        if (v != "") waiv[n]   = v
      # THE LIST FIELDS (wave-37 T7, D11; was the three instrument fields wave-01 S13 named, then the
      # declared runs and the landing set one at a time), carried forward as the contract fields above
      # are: the merged value of each field of the set the roster library names once, in
      # `ROSTER_LIST_FIELDS`, handed in through the environment so this program holds no copy of it.
      # They are what the writer-side budget guard reads: a resumed agent whose adopted row lost
      # `suites_allowed=` would come out of a /clear with no budget on it, and the wall that refuses
      # an off-budget suite would go quiet for exactly the agents a clear leaves running longest;
      # one that lost `questions=` is no longer a reader of anything. `suites_source` is the one
      # scalar that travels beside them.
      for (li = 1; li <= nl; li++) { v = kv($0, lf[li]); if (v != "") lv[n, lf[li]] = v }
      v = kv($0, "suites_source");  if (v != "") ssrc[n]   = v
      # THE DONE MARKER (wave-24 T9, D3): the same contract, so its completion signal too.
      v = kv($0, "done");           if (v != "") dmark[n]  = v
      # THE LANDING KEYS (wave-28 T68; A-orch-216): `lands_on=` (a list field, above), `lands_red=`, `red_evidence=` and `row=` are what the
      # dispatch wall wrote from the brief, and what `ready` reads the suites and the declared debt from. Carried
      # forward as the instrument fields are, or an adopted row would be proved on its budget with its debt dropped.
      v = kv($0, "lands_red");      if (v != "") lred[n]   = v
      v = kv($0, "red_evidence");   if (v != "") revid[n]  = v
      v = kv($0, "row");            if (v != "") lrow[n]   = v
      # THE ATTRIBUTION, carried forward exactly as the contract fields are. It is the bound
      # plan of the session that dispatched the row, stamped at the instant the row was
      # written (hooks/dispatch-preflight.sh). Rows written before this wave carry no such
      # field at all — a THIRD state, not an empty plan, and the caller partitions on the
      # difference (spec AC-2, A2). An apostrophe cannot appear in this comment: the awk
      # program is one single-quoted argument.
      if (index($0, "|plan=") > 0) { plan[n] = kv($0, "plan"); hasplan[n] = 1 }
      st = kv($0, "status")
      if (st == "identified" || st == "confirmed") {
        v = kv($0, "agent_id"); if (v != "") id[n] = v
      }
      next
    }
    END {
      for (i = 1; i <= cnt; i++) {
        n = order[i]
        if (!(n in isopen)) continue
        # THE SOURCE ROW, LAST: row-shaped, so the caller reads a list field off it by key and the
        # tail of its `read` takes the whole of it, `|` and all. A key is there only where the
        # predecessor stated a value.
        src = ENVIRON["AF_SCHEMA"]
        for (li = 1; li <= nl; li++) if ((n, lf[li]) in lv) src = src "|" lf[li] "=" lv[n, lf[li]]
        printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n", n, id[n], stype[n], deliv[n], prog[n], cad[n], \
               launch[n], ((n in afrom) ? afrom[n] : sess[n]), \
               ((n in hasplan) ? (plan[n] == "" ? "none" : plan[n]) : ""), waiv[n], \
               ssrc[n], dmark[n], lred[n], revid[n], lrow[n], src
      }
    }
  ' "$1" 2>/dev/null
}

# AN ACK TAKEN IN ANOTHER SESSION: `adopt_cross_acks` and `adopt_acked_elsewhere` live in lib/fill.sh beside
# the roster walk (wave-35 T28; AC-5.5), because the fill and the dispatch wall read the same acks `adopt` does.

# TWO READS A CADENCE APART (wave-34 T6; REQ-14 AC-14.1, D23). A transcript's mtime says when the agent
# last wrote, which is as true of an agent SIGKILLed a minute ago as of one at work; growth between two
# reads is the evidence. `adopt` keeps each read it takes — `adopt-read/v1|id=|size=|epoch=` in
# `.bionic/tmp/adopt-reads.state`, one file for the root because a read is about the agent, not the
# session that took it — and the next adopt compares against the newest read at least one cadence old.
# `--report-only` reads the file and never writes it. Kept small: a week of reads, eight per agent.
# Set in hooks/session-poker.sh, before any part loads: ADOPT_READS_SCHEMA.
adopt_read_baseline() {  # <reads> <id> <oldest epoch allowed> -> "<size> <epoch>" of the newest read at or before it
  [ -n "$1" ] || return 0
  printf '%s\n' "$1" | awk -v id="$2" -v lim="$3" '
    function kv(line, key,   i, n, p) {
      n = split(line, p, "|")
      for (i = 1; i <= n; i++) if (index(p[i], key "=") == 1) return substr(p[i], length(key) + 2)
      return ""
    }
    index($0, "adopt-read/v1|") == 1 && kv($0, "id") == id {
      e = kv($0, "epoch"); z = kv($0, "size")
      if (e ~ /^[0-9]+$/ && z ~ /^[0-9]+$/ && e + 0 <= lim + 0 && e + 0 >= best + 0) { best = e; bz = z; got = 1 }
    }
    END { if (got) print bz " " best }'
}

adopt_reads_write() {  # <file> <new lines> <now epoch> -> 0 written, 1 not
  local f="$1" tmp
  [ -n "$2" ] || return 0
  tmp_dir_ok "${f%/*}" || return 1
  [ -L "$f" ] && return 1
  tmp="$f.$$"
  { [ -f "$f" ] && cat "$f"; printf '%s\n' "$2"; } 2>/dev/null | awk -v now="$3" '
    function kv(line, key,   i, n, p) {
      n = split(line, p, "|")
      for (i = 1; i <= n; i++) if (index(p[i], key "=") == 1) return substr(p[i], length(key) + 2)
      return ""
    }
    index($0, "adopt-read/v1|") == 1 {
      id = kv($0, "id"); e = kv($0, "epoch")
      if (id == "" || e !~ /^[0-9]+$/ || e + 0 < now - 604800) next
      k = ++c[id]; r[id, k] = $0; if (!(id in seen)) { seen[id] = 1; ids[++n] = id }
    }
    END { for (i = 1; i <= n; i++) { id = ids[i]; for (k = (c[id] > 8 ? c[id] - 7 : 1); k <= c[id]; k++) print r[id, k] } }' \
    > "$tmp" 2>/dev/null && mv -f "$tmp" "$f" 2>/dev/null && return 0
  rm -f "$tmp" 2>/dev/null
  return 1
}

# THE HANDOFF, READ BACK (wave-34 T6; REQ-14 AC-14.2, D23). `handoff` writes `## Handoff` with its
# `written:` instant, and a dispatch after it starts an agent that handoff never saw — so the first verb a
# resumed session runs says whether the bound plan's handoff still stands: STALE, naming every dispatch
# stamped with that plan (the dispatch wall's `intended` row, `plan=` and `launched_at=`) later than it.
# Silent when the session is unbound or its plan carries no handoff. The handoff itself is marked by the
# plan writer that runs at dispatch (`handoff_mark_stale`, T29), from the same two readers.
#
# THE FILE IS THE STORE (wave-38 T12; D23). `handoff` writes record/<wave>/handoff.md and the plan's section is
# one pointer line, `handoff: <path> written <local time>`, the path project-root-relative. Every reader below
# resolves the pointer and reads the FILE's own `written:` instant; a section still in the in-place form a wave-37
# plan carries (its own `written:` line) reads as it always did.
#
# ONE READER OF THE SECTION (burns debt handoff-section-reader): `_HANDOFF_SEC_AWK`'s `ho_track(line)` is 1 for
# a line inside `## Handoff` (the heading, fences and fenced lines excluded), and every awk here that looks in the
# section calls it, the in-place rewrite of the safety lines included. It and the pointer's reader live in
# lib/handoff.sh since wave-39 T16 (D18; burns debt handoff-pointer-reader): `handoff_pointer_of` is the absolute
# path the pointer names, project-root relative, empty when the plan has none, and close-out.sh reads it there too.
# Set in hooks/session-poker.sh, before any part loads: _HANDOFF_ISO_RE.
handoff_written_at() {  # <plan file> -> the handoff's `written:` instant (the file's, through the pointer), empty when none
  local f
  f="$(handoff_pointer_of "$1")"
  if [ -n "$f" ]; then
    [ -f "$f" ] && [ ! -L "$f" ] || return 0
    awk -v re="$_HANDOFF_ISO_RE" '$0 ~ re { print substr($0, 10); exit }' "$f" 2>/dev/null
    return 0
  fi
  awk -v re="$_HANDOFF_ISO_RE" "$_HANDOFF_SEC_AWK"'ho_track($0) && $0 ~ re { print substr($0, 10); exit }' "$1" 2>/dev/null
}

adopt_handoff_note() {  # <bound plan, raw> <repo root> <state dir>
  local plan at names="" n=0 nm la
  [ -n "$1" ] || return 0
  plan="$(adopt_abs "$1" "$2")"
  [ -f "$plan" ] && [ -r "$plan" ] || return 0
  at="$(handoff_written_at "$plan")"
  [ -n "$at" ] || return 0
  while IFS="$(printf '\t')" read -r nm la; do
    [ -n "$nm" ] || continue
    names="${names:+$names, }$nm"; n=$((n + 1))
  done <<EOF
$(handoff_dispatches_since "$1" "$3" "$at")
EOF
  if [ "$n" -eq 0 ]; then
    say "handoff written $at — current: no dispatch of this plan since"
  else
    say "handoff written $at — STALE: $n dispatch(es) of this plan since ($(clean "$names")); rewrite it: bash ${HOOK_DIR}/session-poker.sh handoff"
  fi
}

# handoff_stale_list <bound plan, raw> <instant> <state dir> -> `<name> at <local> (<ISO>), …` for every dispatch of
# the plan after <instant>, empty when there is none: the one sentence both markings print.
handoff_stale_list() {
  local list="" nm la loc
  while IFS="$(printf '\t')" read -r nm la; do
    [ -n "$nm" ] || continue
    loc="$(handoff_local_time "$la")"
    list="${list:+$list, }$(clean "$nm") at ${loc:+$loc }($la)"
  done <<EOF
$(handoff_dispatches_since "$1" "$3" "$2")
EOF
  printf '%s' "$list"
}
handoff_mark_stale() {  # <bound plan, raw> <plan file in> <state dir> <out> -> 0 when <out> is <in> marked and differs from it
  local at list
  # A plan whose section is the pointer has no safety line of its own: its file is marked (handoff_file_mark_stale).
  [ -z "$(handoff_pointer_of "$2")" ] || return 1
  at="$(handoff_written_at "$2")"
  [ -n "$at" ] || return 1
  list="$(handoff_stale_list "$1" "$at" "$3")"
  [ -n "$list" ] || return 1
  HM_EXIT="no — STALE: dispatched after this handoff was written: $list; rewrite it: session-poker.sh handoff" \
  HM_CLEAR="no — STALE, for the same reason" awk "$_HANDOFF_SEC_AWK"'
    { h = ho_track($0) }
    h && index($0, "- safe to exit:") == 1 { print "- safe to exit: " ENVIRON["HM_EXIT"]; next }
    h && index($0, "- safe to /clear:") == 1 { print "- safe to /clear: " ENVIRON["HM_CLEAR"]; next }
    { print }' "$2" > "$4" 2>/dev/null || return 1
  ! cmp -s "$2" "$4"
}
# THE FILE MARKED (wave-38 T12; D23). The handoff file's safe line, the line before its door, is rewritten whole to
# STALE naming each later dispatch, and nothing else in the file; recomputed each time, so a second call with no new
# dispatch writes nothing. The file is written in place (a private copy, then one rename); the plan is not touched.
handoff_file_mark_stale() {  # <bound plan, raw> <handoff file> <state dir> -> 0 when the file was rewritten
  local at list f="$2" tmp
  [ -f "$f" ] && [ ! -L "$f" ] || return 1
  at="$(handoff_written_at "$1")"
  [ -n "$at" ] || return 1
  list="$(handoff_stale_list "$1" "$at" "$3")"
  [ -n "$list" ] || return 1
  tmp="$f.stale.$$"
  HM_LINE="STALE — dispatched after this handoff was written: $list; rewrite it: session-poker.sh handoff" awk '
    { l[NR] = $0 }
    END { for (i = 1; i <= NR; i++) {
            if (i == NR - 1 && index(l[NR], "/bionic:canonical-sdlc ") == 1 \
                && (l[i] == "safe to clear" || l[i] ~ /^wait [0-9]+ minutes/ || index(l[i], "STALE — ") == 1)) print ENVIRON["HM_LINE"]
            else print l[i] } }' "$f" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  if cmp -s "$f" "$tmp"; then rm -f "$tmp"; return 1; fi
  mv -f "$tmp" "$f" 2>/dev/null || { rm -f "$tmp"; return 1; }
}

# ONE SHORT FORM OF A ROW'S TASK (wave-38 T13; D13). The sitrep's Situation lines and the resume verb's task-list:
# lines both name a row by its task cell cut before the first "(", ". " or " · ", trimmed, a final period dropped.
# Set in hooks/session-poker.sh, before any part loads: _ROW_SHORT_AWK.

# THE ADOPTED ROW — the verb's one write, and the second half of the B-1 cure. What it
# records is an ownership fact, and each field is there because a named reader asks for it:
#
#   status=identified   the accepted set hooks/stop-guard.sh and hooks/stop-check.sh
#                       establish ownership BY ID from. `confirmed` would do as well and
#                       says less: the id is known, which is exactly what `identified` means.
#   agent_id=           the TRANSCRIPT form, the only form either gate resolves a target to.
#   teammate_id=        the ADDRESSING form `<name>@session-<id8>`, the only spelling the
#                       platform's stop primitive takes for a teammate — built from the
#                       session that LAUNCHED the agent, never from ours (T3 FINDING 1). The
#                       teammate table keys on the session that made the `Agent` call and a
#                       `/clear` does not move it; hooks/stop-guard.sh reads this recorded
#                       address before it constructs one, so a row carrying our own eight
#                       would put the string the harness rejects into every refusal it
#                       prints. The caller hands it in already built, for the same reason
#                       the address is printed from there: one construction, one origin.
#   adopted_from=       provenance. The agent is still filed under the predecessor's own
#                       subagents directory, and that directory is what hooks/stop-guard.sh
#                       must widen its resolution to; without this field it cannot know
#                       which session to widen to, and a blind project-wide walk is exactly
#                       the name-oracle the 4/9 ownership rule removed.
#   the contract        deliverable/progress/cadence, copied forward unchanged — the same
#                       forward-copy every roster writer in the fleet performs, so the
#                       successor's readers see the contract the predecessor declared.
#   waiver=             S17 (AC-12 attempt 2). Copied forward for the same reason: it is a
#                       contract field, and `hooks/session-sweeper.sh verdict_row` reads it
#                       directly off THIS row (no marker involved) to decide WAIVED before it
#                       ever looks at a deliverable. A row with a real waiver and an empty
#                       copy of it verdicts as if the waiver had never been declared.
#
# THE APPEND IDIOM IS hooks/dispatch-preflight.sh's (:1339-1347), copied deliberately:
# header-if-absent, `chmod 600`, ONE `printf` of one line, NO LOCK. A single O_APPEND write
# of well under a pipe buffer is not interleaved by the kernel; a read-modify-write here
# would drop rows another writer appended in between (hooks/execution-recorder.sh:399-419).
#
# IDEMPOTENT BY READ-BEFORE-APPEND. `adopt` is the first verb a resumed session runs and it
# is run again at the next resume, so a row already carrying this agent's id AND a
# provenance is left alone — otherwise the roster would grow one row per run without
# carrying one new fact. The read is ADVISORY, never a lock: a lost race duplicates a row,
# which every reader in the fleet already tolerates (the last row carrying a name wins).
#
# A ROW WITH NO ID IS NEVER WRITTEN. That is the UNADDRESSABLE verdict's whole content —
# there is no identity to file — and a row carrying `agent_id=` empty would be inert at
# every by-id reader while looking like an adoption on disk.
#
# THE ROW CARRIES THE ADOPTING SESSION'S BINDING, in the same trailing `plan=` field
# hooks/dispatch-preflight.sh:1703 writes on the rows it creates — one field name, one
# position, two writers (spec §Ownership table, "roster attribution"; cross-gate §RA).
# Without it an adopted row was the one row on any roster with no attribution at all, so a
# THIRD session bound to the same plan re-read this session's own adoption as
# `unattributed` and declined to take it: the partition would quietly stop working exactly
# where two sessions hand a run back and forth. The value is the ADOPTER's binding, because
# the adopter is now the session that owns the row — the launching session is already
# recorded, separately, in `adopted_from=`.
adopt_write_row() {  # <roster file> <sid> <name> <id> <type> <deliverable> <progress> <cadence> <launched> <from-sid> <teammate address> <plan|none> <waiver> [<source row> [<suites_source> [<done> [<lands_red> <red_evidence> <row>]]]] -> 0 written/already there, 1 not
  local f="$1" sid="$2" name="$3" id="$4" typ="$5" deliv="$6" prog="$7" cad="$8"
  local launch="$9" osid="${10}" addr="${11}" plan="${12:-none}" waiver="${13:-}" d
  local src="${14:-}" ssrc="${15:-}" dmark="${16:-}"
  local lred="${17:-}" revid="${18:-}" lrow="${19:-}"
  local -a RR_ARGS
  local ROW=""
  local -a LIST_FIELDS_ARGS
  local lf
  [ -n "$id" ] || return 1
  [ -n "$sid" ] || return 1
  d="${f%/*}"
  tmp_dir_ok "$d" || return 1
  [ -L "$f" ] && return 1
  if [ -f "$f" ] && awk -v k="|agent_id=${id}|" '
        index($0, k) > 0 && index($0, "|adopted_from=") > 0 { found = 1 }
        END { exit !found }' "$f" 2>/dev/null; then
    return 0
  fi
  # A LIVE NAME NEVER GETS A SECOND LIVE ROW (T6, AC-6.1; research R1 §5). The idempotence
  # check above is by agent_id — a SECOND agent, under a DIFFERENT id, adopted under the SAME
  # name is not caught by it, and two live rows of one name is exactly the ambiguity
  # `hooks/stop-guard.sh`'s own stop refusal exists to police (T29 §7). `live_ids_of_name` is
  # that refusal's own predicate, moved to the one library both files source
  # (`payload/scripts/lib/roster.sh`): a non-empty answer means this name is already live
  # here, so this adopt takes the `-r<n>` search (`fill_name`, the fleet's one convention for a
  # spent id, payload/scripts/lib/fill.sh) instead of the name it was asked for, and says so once
  # on stderr — this call site is otherwise silent.
  local ROSTER_FILE="$f"
  if [ -n "$(live_ids_of_name "$name")" ]; then
    local renamed
    renamed="$(fill_name "$f" "$name")"
    if [ -n "$renamed" ] && [ "$renamed" != "$name" ]; then
      echo "adopt: '${name}' is already live on this session's roster — writing this row as '${renamed}'" >&2
      name="$renamed"
    fi
  fi
  mkdir -p "$d" 2>/dev/null || return 1
  if [ ! -e "$f" ]; then
    roster_header >> "$f" 2>/dev/null && chmod 600 "$f" 2>/dev/null
  fi
  # EVERY FIELD THROUGH `clean()`, `session=` INCLUDED (Step-6 security review S-4). It was
  # the one interpolation of the thirteen that took its value raw, which is character for
  # character the defect this wave fixed on the other row writer one task earlier
  # (hooks/dispatch-preflight.sh: "a value carrying a `|` or a newline forges a segment …
  # the asymmetry between the two writers was itself the defect"). Every by-key reader in
  # the fleet takes the FIRST match, so a forged `name=` ahead of the real one wins outright.
  # Unreachable today — `engaged_marker_path` refuses a session id outside `[A-Za-z0-9_-]`
  # before any verb decides anything — and that is a guard in another file for another
  # reason, not this writer's own.
  #
  # THE LIST FIELDS ARE READ OFF THE SOURCE ROW BY KEY, EVERY ONE OF THE SET (wave-37 T7, REQ-8,
  # D11). `ROSTER_LIST_FIELDS` (payload/scripts/lib/roster.sh) names them once, and `<source row>`
  # is the row-shaped string `adopt_fold` built from the predecessor's roster: the merged value of
  # each list field the name ever carried, a key present only where the predecessor stated one.
  # Each field present is passed whole, so `questions=` and `claims=` travel as `files=` does,
  # byte for byte, where they used to be dropped and written empty. The field name goes to
  # `clean` so the cut is skipped for the set and `re_executes=` is decoded (see `clean`): the
  # value reaches `roster_row` as the brief spelled it and is encoded there, once.
  #
  # THREE OF THEM TRAVEL AS A GROUP BESIDE `suites_source=`, AND ONLY WHEN THE SOURCE ROW HAD THE
  # GROUP (wave-01 S13, spec AC-20). `roster_row` emits `files=`, `suites_allowed=` and
  # `suites_source=` present-if-PASSED, and the distinction is load-bearing at the writer-side
  # guard: a row with `suites_allowed=` empty stated a budget that came out empty, while a row
  # with no such key at all was written before the wall existed. Adopting the second kind must
  # not manufacture the first. All three go or none do — an empty member of a stated group is
  # itself a statement, and splitting them would let a resumed row claim a source for a set it
  # does not carry. The group rule is unchanged by the set above: it adds the empty member a
  # stated group is missing, and nothing else.
  LIST_FIELDS_ARGS=()
  for lf in $ROSTER_LIST_FIELDS; do
    if row_has_key "$src" "$lf"; then
      LIST_FIELDS_ARGS+=("$lf=$(clean "$(line_field "$src" "$lf")" "$lf")")
    fi
  done
  if [ -n "$ssrc" ] || row_has_key "$src" files || row_has_key "$src" suites_allowed; then
    row_has_key "$src" files || LIST_FIELDS_ARGS+=("files=")
    row_has_key "$src" suites_allowed || LIST_FIELDS_ARGS+=("suites_allowed=")
    LIST_FIELDS_ARGS+=("suites_source=$(clean "$ssrc")")
  fi
  # THE ROW IS BUILT BY `roster_row` (payload/scripts/lib/roster.sh), not by a format string
  # here (spec AC-25, ledger D3). The fields this writer leaves EMPTY are still named
  # — `model=`, `duration=`, `absent=` and the rest; `claims=` is the library's own empty unless
  # the source row stated one — because an omitted key and
  # an empty one are different rows to a by-key reader, and this writer has always emitted
  # both of the fields no other writer does (`teammate_id=`, `adopted_from=`), empty address
  # included. `clean()` stays here: it is this file's cap on a value, while the row's SHAPE
  # is the library's.
  RR_ARGS=(
    status=identified
    "session=$(clean "$sid")"
    "name=$(clean "$name")"
    "agent_id=$(clean "$id")"
    "launched_at=$(clean "$launch")"
    "subagent_type=$(clean "$typ")"
    model=
    "deliverable=$(clean "$deliv")"
    source=adopted
    duration=
    "progress=$(clean "$prog")"
    "cadence=$(clean "$cad")"
    absent=
    "waiver=$(clean "$waiver")"
    ${LIST_FIELDS_ARGS[@]+"${LIST_FIELDS_ARGS[@]}"}
    ${dmark:+"done=$(clean "$dmark")"}
    "teammate_id=$(clean "$addr")"
    "adopted_from=$(clean "$osid")"
    tool_use_id=
    "plan=$(clean "$plan")"
    ${lred:+"lands_red=$(clean "$lred")"}
    ${revid:+"red_evidence=$(clean "$revid")"}
    ${lrow:+"row=$(clean "$lrow")"}
  )
  # THE DECLARED RUNS RIDE THE SAME LOOP (REQ-1 AC-1.1's adopt half; wave-37 T7, D11).
  # `re_executes=` is one of the list fields, so the loop above passes it with its name and
  # `clean` decodes the stored form: the value reaches `roster_row` as the brief spelled it,
  # and `roster_row` encodes it again on the way out, so the row this writer appends holds the
  # predecessor's bytes. There is one call to the builder and no fallback append: a key the
  # builder did not know would refuse the whole row here, and `roster_row` has taken every key
  # of the set (tests/session-poker-4.test.sh §LIST pins it).
  ROW="$(roster_row "${RR_ARGS[@]}")" || return 1
  [ -n "$ROW" ] || return 1
  printf '%s\n' "$ROW" >> "$f" 2>/dev/null || return 1
  return 0
}

# THE MARKER COPY (S17, AC-12 attempt 2) — the other half of the contract-verdict fix beside
# the waiver above. `adopt_write_row` puts the row on this session's roster; this puts the
# SOURCE roster's own landing verdict for that name beside it, verbatim, so a reader that
# trusts the marker rather than re-deriving from disk (`hooks/session-start.sh`'s
# `open_rows`, which scans the roster it was handed for a `landing-swept/v1|…|name=<X>|`
# line) sees the same answer on the successor that stood on the predecessor.
#
# payload/scripts/lib/stop.sh (`stop_landing_gate`, reached from hooks/stop.sh) is this
# schema's one ORIGINATING writer. This call site is the second writer, made deliberately
# narrow: it never COMPUTES a verdict, it only APPENDS a line that
# writer already produced, byte for byte, off the source roster this verb is only ever
# permitted to read (never write — the row above is still the one file this verb writes to).
#
# THE LATEST LINE, because the marker stream is append-only the same way the roster is: a
# name can be superseded (UNMET -> MET) and the last line wins. `adopt_fold` excludes a
# closed name through the same `roster_open_names` predicate (an ack later than the row's
# launch), not a `met[]` filter, so a name that reaches this call was never offered one to
# adopt in the first place, and the only history left to find is whatever the source
# roster's own ack state has not yet closed.
#
# IDEMPOTENT BY EXACT-LINE PRESENCE, the same posture `adopt_write_row` takes: the source
# session is the one and only writer of ITS OWN marker lines, so a line copied once from it
# never changes shape on a later read, and comparing the verbatim text is enough to know this
# adopt already carried it.
adopt_copy_marker() {  # <source roster> <own roster> <name> -> 0 copied/already there, 1 nothing to copy
  local src="$1" own="$2" name="$3" line
  [ -n "$name" ] && [ -f "$src" ] && [ ! -L "$src" ] || return 1
  # THE SHARED CONSTANT (declared above), NOT A SECOND SPELLING (S15, AC-26). This used to
  # grep the bare literal 'landing-swept/v1' — see the constant's own comment for why a
  # literal here was the exact hazard research-code-map §2.c named.
  line="$(grep "^${SWEPT_SCHEMA}|" "$src" 2>/dev/null | grep -F "|name=${name}|" | tail -1)"
  [ -n "$line" ] || return 1
  grep -qF "$line" "$own" 2>/dev/null && return 0
  [ -f "$own" ] && [ ! -L "$own" ] || return 1
  printf '%s\n' "$line" >> "$own" 2>/dev/null || return 1
  return 0
}

# ---------------------------------------------------------------- is this session's residue gone?
#
# THE SWEEP'S OWN QUESTION, ASKED OF ONE SESSION (REQ-9 AC-9.1; D10), lives in lib/fill.sh as the first
# arm of `roster_row_open` (wave-36 T10; AC-4.4): dead (not among the live ids) AND every state file older
# than the window `sweep --window` defers inside. Both halves, never one: a `/clear` leaves the
# predecessor dead within seconds while its roster is the freshest file here. The dispatch wall's hold
# asks the same function, so a row this verb counts closed is a row the wall admits over.

# ---------------------------------------------------------------- the launch sync
#
# ONE TRANSACTION FOR EVERY LAUNCH THE PLAN LACKS (wave-26 T32; D4, review-3 F1, F2, F6). Through
# T12 the launch recorder ran `task-set` and then `ledger-add` inside its own hook, about a second
# each, under a 10 s limit: a batch of launches outran it and the later ones printed the busy
# refusal. `launch-sync` reads this session's roster and the bound plan and writes, in ONE
# validated, dry-committed write (the shared transaction above), every open launch whose row is
# not yet active under it or whose ledger line is missing. The recorder starts it without
# waiting; the Patrol tick and the turn-end wall run it too. Whichever runs first does the work,
# and the others find nothing to do and say nothing.
#
# WHICH LAUNCHES: the OPEN names of this session's roster (`roster_open_names`, the predicate the
# ready set reads), each by its latest `confirmed` or `identified` row. A finished agent's launch
# is never applied again, so a row returned to `pending` (a review row after its proof) is not
# re-activated under an old name. A name maps to a `## Tasks` row by `fill_row_launched`; a row
# that is `landed` or `dropped` is left alone.
#
# WHAT IS WRITTEN, PER LAUNCH, AND ALL OF IT OR NONE OF IT: the row's `status=active` and agent,
# its empty `worktree` and `base` filled from the tree spawn-worktree.sh recorded for the name;
# and one `## Dispatch ledger` line, `<role> (<name>)`, the launch minute, the brief duration, the
# deliverable, and `<tree> @ <base>` in the notes. A row's agent cell is its LATEST open launch,
# so a `-r<n>` re-dispatch moves the cell and gets its own line, keyed `<id>r<n>` (F1). A launch
# with no tree of its own (a reviewer or a test-runner whose row's Files name nothing outside the
# docs root, `units_writes_head`) goes active with an empty worktree cell, which units_validate
# admits for exactly such a row, and takes the Step-4 block's `worktree:` and `base-sha:` for its
# ledger line only: the wave's tree in the row would read to the commit gate as the row's own. A
# row that writes the head with no tree recorded cannot go active at all and is printed. A plan with no
# `## Dispatch ledger` heading keeps no ledger, and its launches get the row alone.
#
# NEVER HALF A LAUNCH (F2, F6). The row and its line are projected together on a scratch copy and
# kept only when both project; the batch is validated and dry-committed once, and the plan is
# replaced by one rename. A run killed before the rename leaves the plan byte-identical and the
# next caller applies the launch whole; the copy it left is removed by the next run once its pid
# is gone. The T12 case of a ledger-add refusing after task-set succeeded cannot arise.
#
# ONE WRITER: a lock under `.bionic/tmp`, mkdir and pid. `--wait` (the recorder's detached call)
# waits up to LAUNCH_SYNC_WAIT seconds; the tick and the turn-end wall leave a held lock to its
# holder. A holder whose pid is gone, or a lock older than LAUNCH_SYNC_STALE seconds, is taken
# over.
#
# WHAT IT PRINTS: `poker: LAUNCHED <id> <name> — <what was written>` once, by whichever caller
# wrote it; `poker: NOT-RECORDED <id> <name> — <why>` and the commands to run by hand, by every
# caller, until it is fixed (exit 1). Nothing at all when there is nothing to do.
# Set in hooks/session-poker.sh, before any part loads: LAUNCH_SYNC_WAIT, LAUNCH_SYNC_STALE, LAUNCH_SYNC_LOCK.

# The tree and base spawn-worktree.sh recorded for <name> in this session, `path<TAB>base`, or
# nothing. worktree.sh owns the read (`workspace_record_for_name`, wave-26 T40): a path counts
# only where git lists it as a linked worktree (wave-25 T18), so a line any script appended
# naming the main checkout never fills a row; the last line that counts wins.
launch_sync_workspace() {  # <root> <sid> <name>
  declare -F workspace_record_for_name >/dev/null 2>&1 || return 0
  workspace_record_for_name "$1" "$2" "$3" 2>/dev/null || return 0
}

# A recorded tree as the plan writes it: relative to the project root when it sits under it.
launch_sync_rel() {  # <root> <absolute tree>
  local root="$1" p="$2" root_p
  [ -d "$p" ] && p="$(cd "$p" 2>/dev/null && pwd -P)"
  root_p="$(cd "$root" 2>/dev/null && pwd -P)"
  case "$p" in
    "$root"/*)   p="${p#"$root"/}" ;;
    "$root_p"/*) p="${p#"$root_p"/}" ;;
  esac
  printf '%s' "$p"
}

# The brief duration as the ledger writes it: `60 minutes`, `~45 minutes.` -> `60 min`, `45 min`;
# anything else verbatim.
launch_sync_minutes() {  # <duration>
  local d="$1" n
  d="${d#\~}"; d="${d%.}"
  n="${d%%[!0-9]*}"
  case "${d#"$n"}" in
    ' min'|' mins'|' minute'|' minutes'|min|mins|m) [ -n "$n" ] && { printf '%s min' "$n"; return 0; } ;;
  esac
  printf '%s' "$1"
}

# The Step-4 block's `worktree:` and `base-sha:`, `tree<TAB>base`, or nothing.
launch_sync_step4() {  # <plan>
  awk '
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^##[ \t]/ { sdlc = ($0 ~ /^##[ \t]+SDLC State/); inb = 0; next }
    !sdlc { next }
    /^[ \t]*-?[ \t]*Step[ \t]+4[ \t]*:/ { inb = 1; next }
    inb && /^[ \t]*- / { inb = 0 }
    inb && /^[ \t]+worktree[ \t]*:/ { v = $0; sub(/^[ \t]+worktree[ \t]*:[ \t]*/, "", v); sub(/[ \t].*$/, "", v); wt = v }
    inb && /^[ \t]+base-sha[ \t]*:/ { v = $0; sub(/^[ \t]+base-sha[ \t]*:[ \t]*/, "", v); sub(/[ \t].*$/, "", v); bs = v }
    END { if (wt != "") print wt "\t" bs }' "$1" 2>/dev/null
}

# IS THIS LAUNCH ALREADY LEDGERED (wave-26 T32, A-T32.14; T54, review 17 S1). A ledger line names
# its launch `<role> (<name>)`, and a name an ack freed can be dispatched again: a line of the same
# name counts for this launch only when its `dispatched=` minute is not older than this launch's
# first minute (`launch_sync_launches`). A line whose cell is not an ISO minute, or a launch with no
# minute, keeps the name alone as the key, as before. Reads the projection's LGAG and LGDT.
launch_sync_ledgered() {  # <name> <launched_at> -> 0 when a ledger line records this launch
  local name="$1" m="" k=0 d
  case "$2" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]*) m="${2:0:16}Z" ;; esac
  while [ "$k" -lt "${#LGAG[@]}" ]; do
    case "${LGAG[k]}" in
      *"($name)")
        d="${LGDT[k]}"
        case "$d" in
          [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]*) [ -n "$m" ] && [ "${d:0:16}Z" \< "$m" ] || return 0 ;;
          *) return 0 ;;
        esac ;;
    esac
    k=$((k + 1))
  done
  return 1
}

# The open launches, `name launched_at duration deliverable subagent_type` joined by the unit
# separator (\037: a field may be empty, and `read` folds runs of a whitespace separator), each by
# its latest confirmed or identified row, in the roster order of that row. The launch minute is the
# FIRST of the name's latest launch (wave-26 T51; review 13 F4): `extend` appends a row launched now
# for a reviewer it re-opens, and that is the same launch, which a proof of its row may already have
# read. ONE LAUNCH, NOT ONE NAME (wave-26 T54; review 17 S1): a name an ack freed can be dispatched
# again, and that is a new pass, which the old pass's first minute would date before the proof that
# read the old pass. So the minute is the earliest among the rows of the latest row's lineage: those
# that share its agent id or its tool_use_id. `extend`, `amend` and `hold` copy both, and the
# recorder's rows of one dispatch share the tool_use_id (a teammate's confirmed row carries no agent
# id until its identified row), while a new dispatch has neither. A latest row with neither falls
# back to every row of the name.
launch_sync_launches() {  # <roster> <sid> <open names, one per line>
  LS_OPEN="$3" LS_SID="$2" awk -F'|' '
    BEGIN { n = split(ENVIRON["LS_OPEN"], o, "\n"); for (i = 1; i <= n; i++) if (o[i] != "") open[o[i]] = 1
            sid = ENVIRON["LS_SID"] }
    $1 != "roster-state/v1" { next }
    {
      split("", kv)
      for (i = 2; i <= NF; i++) {
        e = index($i, "="); if (e < 2) continue
        k = substr($i, 1, e - 1); if (!(k in kv)) kv[k] = substr($i, e + 1)
      }
      if (kv["status"] != "confirmed" && kv["status"] != "identified") next
      nm = kv["name"]; if (nm == "" || !(nm in open)) next
      if (kv["session"] != "" && kv["session"] != sid) next
      at[nm] = NR; r++; last[nm] = r
      rn[r] = nm; ri[r] = kv["agent_id"]; rt[r] = kv["tool_use_id"]; rl[r] = kv["launched_at"]
      rec[nm] = kv["duration"] "\037" kv["deliverable"] "\037" kv["subagent_type"] "\037" kv["row"]
    }
    END {
      for (q = 1; q <= r; q++) {
        nm = rn[q]; l = last[nm]
        if (ri[l] != "" || rt[l] != "")
          if (!((ri[l] != "" && ri[q] == ri[l]) || (rt[l] != "" && rt[q] == rt[l]))) continue
        if (rl[q] != "" && (!(nm in la) || rl[q] < la[nm])) la[nm] = rl[q]
      }
      for (k in at) print at[k] "\t" k "\037" la[k] "\037" rec[k] }' "$1" 2>/dev/null | sort -n | cut -f2-
}

# Removes what a run killed before its rename left beside the plan: the copies and the dry
# commit's engagement marker of a pid that is gone.
launch_sync_sweep() {  # <plan> <root>
  local f pid m
  for f in "$1".launch-sync.* "$1".launch-sync-dry.*; do
    [ -e "$f" ] || continue
    pid="${f#"$1".launch-sync}"; pid="${pid#-dry}"; pid="${pid#.}"; pid="${pid%%.*}"
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    kill -0 "$pid" 2>/dev/null && continue
    rm -f "$f" 2>/dev/null
    m="$(engaged_marker_path "$2" "planverb-$pid" 2>/dev/null)" && [ -n "$m" ] && rm -f "$m" 2>/dev/null
  done
  return 0
}

# IS THIS LAUNCH A PASS ITS ROW'S OWN PROOF ALREADY READ (wave-26 T51; review 13 F2, F4). A review
# row returns to `pending` on its proof while its reviewer may still be open, and a launch older
# than that proof is the pass the proof read: it is not applied again (T32, A-T32.17). Since T46 a
# proof returns only the row whose Files hold its evidence (`units_live_rows`, both spellings, as
# proof-add hands them), so a launch is judged against the proofs of ITS row alone: the proof of
# another review, the final one among them, says nothing about it, and a live launch the sync had
# not yet applied when such a proof landed is applied. Newest proof first; the first one not newer
# than the launch ends the search. The proofs are read once per transaction, and only when a pending
# row has a launch to judge.
# Set in hooks/session-poker.sh, before any part loads: LS_PROOFS, LS_PROOFS_READ.
launch_sync_read() {  # <plan> <root> <row id> <launched_at> -> 0 when a review proof of that row is newer than the launch
  local plan="$1" root="$2" id="$3" la="$4" at ev q doc
  [ -n "$la" ] || return 1
  if [ "$LS_PROOFS_READ" = no ]; then
    LS_PROOFS="$(awk '
      /^[ \t]*```/ { f = !f; next }
      f { next }
      /^##[ \t]/ { insdlc = ($0 ~ /^##[ \t]+SDLC State/); next }
      insdlc && /^proved:[ \t]/ && / kind=review( |$)/ && match($0, / at=[^ ]+/) {
        a = substr($0, RSTART + 4, RLENGTH - 4); q = ""
        if (match($0, / question=[^ ]+/)) q = substr($0, RSTART + 10, RLENGTH - 10)
        if (match($0, / evidence=[^ ]+/)) print a "\t" substr($0, RSTART + 10, RLENGTH - 10) "\t" q
      }' "$plan" 2>/dev/null | sort -r)"
    LS_PROOFS_READ=yes
  fi
  [ -n "$LS_PROOFS" ] || return 1
  doc="$(docs_root "$root" 2>/dev/null)"
  case "$doc" in "$root"/*) doc="${doc#"$root"/}" ;; *) doc="" ;; esac
  # A READING IS ITS QUESTION'S ROW'S PROOF (wave-27 T10; D4): a proof carrying question= is
  # matched to the read row carrying that question, as proof-add returned it, not by its Files.
  while IFS="$(printf '\t')" read -r at ev q; do
    [ -n "$at" ] && [ -n "$ev" ] || continue
    [ "$la" \< "$at" ] || return 1
    units_live_rows "$plan" ${q:+--question "$q"} "$ev" ${doc:+"$doc/$ev"} 2>/dev/null \
      | awk -F'\t' -v id="$id" '$1 == id && $2 == "review" { f = 1 } END { exit !f }' && return 0
  done <<EOF
$LS_PROOFS
EOF
  return 1
}

# launch_sync_project <plan> <root> <sid> <roster> <ack ledger> <out>
#   -> writes the projected plan to <out>; sets LS_SAID (lines for what it applies), LS_FAILS
#   (lines for what it cannot) and LS_HANDS (every applied launch's commands, for a batch the
#   gate refuses). 0 when something was projected, 1 when nothing was.
launch_sync_project() {
  local plan="$1" root="$2" sid="$3" roster="$4" acks="$5" out="$6"
  local open rec i j n=0 nl=0 hits h hasl=0 haswt=0 hasbs=0 s4 s4wt s4bs
  local name la du dl ty st ag wt bs fil ws wsbs wtnew bsnew treeless noroom what lid sfx k role rc hand
  local us=$'\037'
  local -a RID RFIL RAG RST RWT RBS LN LLA LDU LDL LTY LBR LROW FINAL LGID LGAG LGDT pairs lpairs
  # THE LEDGER'S ARRAYS ARE SET BEFORE ANY ROW IS READ (wave-35 T29). They are assigned only per existing
  # ledger row, and a header-only `## Dispatch ledger` has none: `${#LGAG[@]}` in launch_sync_ledgered and
  # `${#LGID[@]}` in the id search then read a declared-but-unset array, which bash 5.x under `set -u`
  # aborts ("LGAG: unbound variable"), the first dispatch of every fresh plan. `=()` makes them empty.
  LGID=(); LGAG=(); LGDT=()
  LS_SAID=""; LS_FAILS=""; LS_HANDS=""; LS_PROOFS=""; LS_PROOFS_READ=no
  open="$(roster_open_names "$roster" "$acks" "$sid" 2>/dev/null)"
  [ -n "$open" ] || return 1
  while IFS="$us" read -r name la du dl ty rw; do
    [ -n "$name" ] || continue
    LN[nl]="$name"; LLA[nl]="$la"; LDU[nl]="$du"; LDL[nl]="$dl"; LTY[nl]="$ty"; LBR[nl]="$rw"; nl=$((nl + 1))
  done <<EOF
$(launch_sync_launches "$roster" "$sid" "$open")
EOF
  [ "$nl" -gt 0 ] || return 1
  while IFS="$us" read -r rec _ _ _ ag _ _ _ fil st wt bs _; do
    [ -n "$rec" ] || continue
    RID[n]="$rec"; RFIL[n]="$fil"; RAG[n]="$ag"; RST[n]="$st"; RWT[n]="$wt"; RBS[n]="$bs"; FINAL[n]=-1
    n=$((n + 1))
  done <<EOF
$(units_rows "$plan" 2>/dev/null | tr '\t' '\037')
EOF
  [ "$n" -gt 0 ] || return 1
  j=0
  while [ "$j" -lt "$nl" ]; do
    hits=0; h=-1; i=0
    # THE ROW LABEL FIRST (wave-28 T7; D17): a launch whose row carries `row=` is that row's, by the
    # id itself; only a launch with none is matched by its name.
    while [ "$i" -lt "$n" ]; do
      if [ -n "${LBR[j]}" ]; then
        [ "${RID[i]}" = "${LBR[j]}" ] && { hits=$((hits + 1)); h="$i"; }
      elif fill_row_launched "${RID[i]}" "${LN[j]}"; then hits=$((hits + 1)); h="$i"; fi
      i=$((i + 1))
    done
    LROW[j]=-1
    if [ "$hits" -gt 1 ]; then
      LS_FAILS="${LS_FAILS}NOT-RECORDED ? ${LN[j]} — the name maps to more than one ## Tasks row; set the row it runs by hand: $(launch_sync_hand task-set '<id>' status=active "agent=${LN[j]}")"$'\n'
    elif [ "$hits" -eq 1 ]; then
      case "${RST[h]}" in pending|active) LROW[j]="$h"; FINAL[h]="$j" ;; esac
    fi
    j=$((j + 1))
  done
  units_has_column "$plan" worktree && haswt=1
  units_has_column "$plan" base && hasbs=1
  if launch_sync_ledger "$plan" > "$out.ledger"; then hasl=1; fi
  i=0
  while IFS="$us" read -r lid ag la; do
    [ -n "$lid" ] || continue
    LGID[i]="$lid"; LGAG[i]="$ag"; LGDT[i]="$la"; i=$((i + 1))
  done < "$out.ledger"
  rm -f "$out.ledger"
  s4="$(launch_sync_step4 "$plan")"; s4wt="${s4%%$'\t'*}"; s4bs="${s4#*$'\t'}"; [ -n "$s4" ] || s4bs=""
  cp "$plan" "$out" || return 1
  j=0
  while [ "$j" -lt "$nl" ]; do
    i="${LROW[j]}"
    if [ "$i" -lt 0 ]; then j=$((j + 1)); continue; fi
    name="${LN[j]}"; st="${RST[i]}"; ag="${RAG[i]}"; wt="${RWT[i]}"; bs="${RBS[i]}"; fil="${RFIL[i]}"
    pairs=(); lpairs=(); what=""; treeless=0; wtnew=""; bsnew=""
    ws="$(launch_sync_workspace "$root" "$sid" "$name")"
    if [ -n "$ws" ]; then
      case "$wt" in *[A-Za-z0-9]*) : ;; *) [ "$haswt" = 1 ] && wtnew="$(launch_sync_rel "$root" "${ws%%$'\t'*}")" ;; esac
      case "$bs" in *[A-Za-z0-9]*) : ;; *)
        case "${ws#*$'\t'}" in *[A-Za-z0-9]*) [ "$hasbs" = 1 ] && bsnew="$(printf '%s' "${ws#*$'\t'}" | cut -c1-8)" ;; esac ;;
      esac
    fi
    # A LAUNCH WITH NO TREE OF ITS OWN: no record for the name, an empty cell, and a Files cell
    # that names nothing outside the docs root (units.sh `units_writes_head`, the predicate the
    # validator asks before it owes the row a tree).
    case "$wt" in *[A-Za-z0-9]*) : ;; *)
      if [ -z "$wtnew" ] && [ "$haswt" = 1 ]; then
        units_writes_head "$fil" || treeless=1
      fi ;;
    esac
    noroom=0
    # A PENDING ROW WHOSE LAUNCH IS ALREADY LEDGERED WAS PUT BACK ON PURPOSE (wave-26 T14: a review
    # row returns to `pending` on its proof while its reviewer may still be open). The launch was
    # recorded once; it is not re-applied to the row, and the next pass is its own launch, under
    # a name of its own or under this one again once an ack freed it (`launch_sync_ledgered`).
    lid=""
    if [ "$st" = pending ] && [ "$hasl" = 1 ] && launch_sync_ledgered "$name" "${LLA[j]}"; then
      lid=have
    fi
    if [ -z "$lid" ] && [ "$st" = pending ] && launch_sync_read "$plan" "$root" "${RID[i]}" "${LLA[j]}"; then
      lid=read
    fi
    if [ -n "$lid" ]; then j=$((j + 1)); continue; fi
    if [ "${FINAL[i]}" = "$j" ]; then
      if [ "$st" = pending ] && [ "$treeless" = 1 ]; then
        pairs=(status=active "agent=$name")
        what="row active with no tree of its own (its Files write nothing the head carries)"
      elif [ "$st" = pending ] && [ "$haswt" = 1 ] && [ -z "$wtnew" ] && { case "$wt" in *[A-Za-z0-9]*) false ;; *) true ;; esac; }; then
        noroom=1
        pairs=(status=active "agent=$name" 'worktree=<tree>' 'base=<sha>')
      elif [ "$st" = pending ]; then
        pairs=(status=active "agent=$name")
        [ -n "$wtnew" ] && pairs+=("worktree=$wtnew")
        [ -n "$bsnew" ] && pairs+=("base=$bsnew")
        what="row active${wtnew:+ in $wtnew}"
      elif [ "$ag" != "$name" ]; then
        pairs=("agent=$name")
        [ -n "$bsnew" ] && pairs+=("base=$bsnew")
        what="the agent cell was ${ag:-empty}"
      fi
    fi
    lid=""
    if [ "$hasl" = 1 ]; then
      launch_sync_ledgered "$name" "${LLA[j]}" && lid=have
      if [ -z "$lid" ]; then
        lid="${RID[i]}"
        sfx="${name##*-r}"; case "$name" in *-r[0-9]*) case "$sfx" in *[!0-9]*) sfx=1 ;; esac ;; *) sfx=1 ;; esac
        while :; do
          k=0
          while [ "$k" -lt "${#LGID[@]}" ] && [ "${LGID[k]}" != "$lid" ]; do k=$((k + 1)); done
          [ "$k" -lt "${#LGID[@]}" ] || break
          lid="${RID[i]}r$sfx"; sfx=$((sfx + 1))
        done
        role="${LTY[j]##*:}"; [ -n "$role" ] || role=agent
        la="${LLA[j]}"
        case "$la" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]*Z) la="${la:0:16}Z" ;; esac
        du="$(launch_sync_minutes "${LDU[j]}")"
        lpairs=("agent=$role ($name)")
        [ -n "$la" ] && lpairs+=("dispatched=$la")
        [ -n "$du" ] && lpairs+=("expected=$du")
        [ -n "${LDL[j]}" ] && lpairs+=("artifact=${LDL[j]}")
        if [ -n "$ws" ]; then
          wsbs=""; case "${ws#*$'\t'}" in *[A-Za-z0-9]*) wsbs="$(printf '%s' "${ws#*$'\t'}" | cut -c1-8)" ;; esac
          lpairs+=("notes=$(launch_sync_rel "$root" "${ws%%$'\t'*}")${wsbs:+ @ $wsbs}")
        elif [ "$treeless" = 1 ] && [ -n "$s4wt" ]; then
          lpairs+=("notes=$s4wt${s4bs:+ @ $s4bs}")
        else
          case "$wt" in *[A-Za-z0-9]*)
            case "$bs" in *[A-Za-z0-9]*) lpairs+=("notes=$wt @ $bs") ;; *) lpairs+=("notes=$wt") ;; esac ;;
          esac
        fi
      else
        lid=""
      fi
    fi
    # A ROW THAT CANNOT GO ACTIVE: nothing of the launch is written, and both commands print.
    if [ "$noroom" = 1 ]; then
      LS_FAILS="${LS_FAILS}NOT-RECORDED ${RID[i]} $name — no tree is recorded for $name and row ${RID[i]} names none, so it cannot go active (spawn its tree with spawn-worktree.sh create --for $name, or fill the cells by hand). Nothing of this launch was written; run:
  $(launch_sync_hand task-set "${RID[i]}" "${pairs[@]}")${lid:+
  $(launch_sync_hand ledger-add "$lid" "${lpairs[@]}")}"$'\n'
      j=$((j + 1)); continue
    fi
    if [ "${#pairs[@]}" -eq 0 ] && [ -z "$lid" ]; then j=$((j + 1)); continue; fi
    # THE LAUNCH WHOLE OR NOT AT ALL: both halves on a scratch copy, kept only together.
    rc=0
    cp "$out" "$out.l" || return 1
    if [ "${#pairs[@]}" -gt 0 ]; then
      units_table_cells "$out.l" set tasks "${RID[i]}" "${pairs[@]}" > "$out.r" 2>/dev/null || rc=$?
      if [ "$rc" -ne 0 ]; then
        LS_FAILS="${LS_FAILS}NOT-RECORDED ${RID[i]} $name — row ${RID[i]} of ## Tasks could not take ${pairs[*]} (units_table_cells exit $rc). Nothing of this launch was written; run:
  $(launch_sync_hand task-set "${RID[i]}" "${pairs[@]}")${lid:+
  $(launch_sync_hand ledger-add "$lid" "${lpairs[@]}")}"$'\n'
        rm -f "$out.l" "$out.r"; j=$((j + 1)); continue
      fi
      mv -f "$out.r" "$out.l"
    fi
    if [ -n "$lid" ]; then
      units_table_cells "$out.l" add ledger "$lid" "${lpairs[@]}" > "$out.r" 2>/dev/null || rc=$?
      if [ "$rc" -ne 0 ]; then
        hand=""
        [ "${#pairs[@]}" -gt 0 ] && hand="  $(launch_sync_hand task-set "${RID[i]}" "${pairs[@]}")"$'\n'
        LS_FAILS="${LS_FAILS}NOT-RECORDED ${RID[i]} $name — the ## Dispatch ledger could not take its line (units_table_cells exit $rc: a header without one of agent, dispatched, expected, artifact or notes, or the id $lid taken). Nothing of this launch was written; run:
${hand}  $(launch_sync_hand ledger-add "$lid" "${lpairs[@]}")"$'\n'
        rm -f "$out.l" "$out.r"; j=$((j + 1)); continue
      fi
      mv -f "$out.r" "$out.l"
      LGID[${#LGID[@]}]="$lid"; LGAG[${#LGAG[@]}]="$role ($name)"; LGDT[${#LGDT[@]}]="$la"
      what="${what:+$what, }ledger line $lid"
    fi
    mv -f "$out.l" "$out"
    [ "${#pairs[@]}" -gt 0 ] && RAG[i]="$name"
    LS_SAID="${LS_SAID}LAUNCHED ${RID[i]} $name — $what"$'\n'
    [ "${#pairs[@]}" -gt 0 ] && LS_HANDS="${LS_HANDS}  $(launch_sync_hand task-set "${RID[i]}" "${pairs[@]}")"$'\n'
    [ -n "$lid" ] && LS_HANDS="${LS_HANDS}  $(launch_sync_hand ledger-add "$lid" "${lpairs[@]}")"$'\n'
    j=$((j + 1))
  done
  [ -n "$LS_SAID" ] || { rm -f "$out"; return 1; }
  return 0
}

# ---------------------------------------------------------------- the sweep
#
# THE OTHER HALF OF `adopt` (fixit 1.5.1 T5; ideas/fixit-1.5.2-dead-session-sweep.md).
# `adopt` reads a predecessor's residue back so a resumed session can act on it. Nothing has
# ever removed that residue once NO session can act on it — so a project's `.bionic/tmp`
# grows one set of files per `/clear`, forever, while every one of those files declares
# itself machine-local and safe to delete in its own first line, and doctor proves the
# sessions dead and then names no way to clear them.
#
# THE HARNESS COMPUTES DEADNESS, A HUMAN RUNS THE VERB (D-5). Deadness is
# `patrol_live_sessions` and nothing else: `kill -0` against the pid the CLI itself wrote
# into its own session file — never `ps`, never an mtime heuristic, and never a judgment of
# the rows inside the file. A dead session's agents are dead by construction, so MET, UNMET,
# acked and open are all the same fact once nobody can act on any of them. Auto-sweeping was
# rejected on the record (D-5): the residue is exactly what `adopt` reads, so a hook that
# cleared it at engagement would delete the evidence of the thing it was helping with.
#
# THE SESSION-KEYED CLASSES, and no others — scripts/lib/patrol.sh's PATROL_STATE_CLASSES.
# Each is `<class>-<session id>.state` under `<root>/.bionic/tmp`, plus the Patrol stamp's
# `.armed` sibling:
#
#   roster-<sid>.state         hooks/dispatch-preflight.sh   the dispatch ledger
#   preflight-<sid>.state      hooks/preflight-probe.sh      the budget attestation
#   engaged-<sid>.state        scripts/lib/binding.sh        the engagement marker
#   sweeper-<sid>.state        hooks/session-sweeper.sh      the ack ledger
#   patrol-<sid>.state[.armed] this file                     the Patrol stamp and its marker
#   stop-orders-<sid>.state    hooks/stop-orders.sh          the order queue
#   tick-digest-<sid>.state    this file                     the tick's digest and duty
#   workspaces-<sid>.state     scripts/lib/worktree.sh       the run's workspace record
#   gate-<sid>.state           hooks/permission-answer.sh    the reserved requests to escalate
#
# THE FILES THAT ARE NOT SESSION-KEYED ARE THEREFORE UNREACHABLE FROM HERE, and that
# is a property of the enumeration rather than a list to maintain: `context-spend.state` and
# `farm-out.state` carry no session id in their names, so no id this walk derives can ever
# address one. A future non-session file is safe on arrival for the same reason.
# (`stop-check.state` was the third of these until epic-23 wave-15 deleted the observation
# record itself — ADR-028.)
# Set in hooks/session-poker.sh, before any part loads: SWEEP_SCHEMA.

# THE ENUMERATION IS THE LIBRARY'S, NOT A COPY (T5 phase 2). Which files belong
# to a session, and which sessions are dead, are read through
# `patrol_state_session_ids`, `patrol_session_state_files` and
# `patrol_dead_sessions` in scripts/lib/patrol.sh — the same three functions
# scripts/lib/checks.sh's dead-session detector calls. They have to agree: a
# class this verb did not delete but the detector counted would put a row on
# doctor's page whose named cure clears nothing, and a second copy of the class
# list here is exactly how that drift arrives. The library's own header carries
# the class table and the reason the unkeyed files are unreachable.

# NO LONGER A FUNCTION (REQ-9/D5's prune half). This used to be `sweep_unlink`, called once
# per candidate file — one `rm -f` subprocess per call, the dominant cost once
# hooks/session-start.sh's own report loops were bounded (T6/T16). The `sweep` verb below
# now queues every non-symlink candidate from every session it decides is old enough (never
# a symlink; never rewritten here) and deletes them all in ONE `xargs -0 rm -f` pass, then
# confirms each with a plain `[ -e ]` — no second `rm`, no per-file function call. See the
# verb's own comments for the full shape, including the per-session age gate that decides
# which sessions reach the delete list at all.

  poker_verb_adopt() {
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "adopt answers 'what did the OTHER sessions launch here', and without this session's"
      die "own key it cannot tell their rows from ours."
      exit 3
    fi

    # ---------- THE ENGAGEMENT GUARD (AC-10): is this session bionic's at all? ----------
    #
    # BEFORE ANYTHING IS READ, DECIDED OR WRITTEN — above the stamp, above the roster,
    # above the sweeper. Chris, 2026-09-03: "all guardrails imposed by bionic should only
    # apply when exercising bionic. Nothing should apply until bionic is triggered" — and
    # the trigger is the canonical-sdlc skill, which writes
    # `.bionic/tmp/engaged-<sid>.state` at the instant it is invoked. The Patrol prompt
    # runs this verb, and a Patrol inherited by a session that never invoked the skill
    # must decide nothing about it rather than deciding wrongly.
    #
    # ONE LINE, EXIT 0, and not a refusal: the tick fired correctly and found nothing it
    # is entitled to judge. `arm` is deliberately not guarded (writing a stamp for a
    # session that asked for one is harmless) and neither is `disarm`, which removes the
    # stamp and leaves this marker exactly where it is — a session that invoked the skill
    # is bionic's for its whole life, so every hook still binds after a disarm (AC-15).
    # [WALL: tests/session-poker.test.sh]
    if ! engaged_session "$(project_root "$PWD")" "$SESSION_ID"; then
      say "NOT-ENGAGED — this session has not invoked /bionic:canonical-sdlc; nothing decided"
      exit 0
    fi

    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    ADOPT_DIR="$REPO_REAL/.bionic/tmp"
    # The ONE file this verb writes: this session's own roster. Named here, once, so the
    # loop below cannot be read as writing anything it iterates over.
    ADOPT_OWN_ROSTER="$ADOPT_DIR/roster-${SESSION_ID}.state"
    ADOPT_ROWS=0
    ADOPT_SESSIONS=0
    ADOPT_NOW="$(now_epoch)"

    # ---------- THE PARTITION (spec AC-2; design ledger T2) ----------
    #
    # THE BUG THIS CLOSES is symptom 2 of the report: this loop walked every roster in the
    # project and offered every open row on every one of them, filtered by nothing but the
    # filename. Two runs sharing a root meant each session was handed the other run's agents
    # to ledger, message and stop.
    #
    # ATTRIBUTION, NOT A SECOND SCAN. hooks/dispatch-preflight.sh stamps the dispatching
    # session's bound plan onto every row it writes, and a BOUND caller compares that field
    # against its own binding: same plan is its own work, a different plan is another run in
    # this root, no field at all is a roster written before this wave (A2). Only the first is
    # written to this session's roster; the other two are LISTED, because a predecessor's
    # agent that is invisible is exactly the failure `adopt` exists to prevent — the operator
    # still needs to see that something is running here, even when taking it is not theirs.
    #
    # AN UNBOUND CALLER HAS NOTHING TO COMPARE AGAINST and gets today's behaviour verbatim:
    # every row, adopted, `partition=all` (AC-3). `session_plan` is the RAW binding rather
    # than `session_run`'s resolution, deliberately — a session bound to a plan that has
    # since closed still owns the rows it dispatched under it, and the fallback plan of an
    # unbound session was never anyone's attribution.
    ADOPT_OWN_PLAN="$(session_plan "$REPO_REAL" "$SESSION_ID")" || ADOPT_OWN_PLAN=""
    ADOPT_OWN_KEY=""
    [ -n "$ADOPT_OWN_PLAN" ] && ADOPT_OWN_KEY="$(adopt_plan_key "$ADOPT_OWN_PLAN")"
    ADOPT_ADOPTED=0
    ADOPT_LISTED=0
    ADOPT_CLOSED=0
    ADOPT_UNREADABLE=0
    ADOPT_DUPES=0
    ADOPT_LAST_PART=""
    # THE IDS THIS RUN HAS ALREADY OFFERED (REQ-9 AC-9.2; D10). Adoption files a copy of the
    # row on the ADOPTER's roster, so an agent resumed N times leaves N rows for one agent id
    # across N rosters — and this walk read all of them, offering one running agent as N
    # things to ledger, message and stop. The id is the identity; the name is not (a rename
    # under `-r<n>` is this verb's own convention). First row carrying an id wins, in roster
    # order, which is the same "the last row of a name wins / the first sighting of an id
    # counts" direction every other reader in the fleet takes.
    ADOPT_SEEN_IDS="|"
    # CLOSURE'S TWO INPUTS, RESOLVED ONCE PER RUN. The live session set is one file per
    # running process out of the claude home, and the window is this project's own poker
    # interval — the same knob the `sweep` verb reads for `--window`, with the same fallback
    # to this script's built-in default so a malformed override cannot disable the read.
    ADOPT_LIVE_IDS="$(patrol_live_session_ids)"
    ADOPT_LIVE_IDS="${ADOPT_LIVE_IDS}${ADOPT_LIVE_IDS:+
}${SESSION_ID}"
    ADOPT_WINDOW="$(poker_interval_seconds 2>/dev/null)"
    case "$ADOPT_WINDOW" in ''|*[!0-9]*) ADOPT_WINDOW="$(parse_seconds "$POKER_INTERVAL_DEFAULT" 2>/dev/null)" ;; esac
    case "$ADOPT_WINDOW" in ''|*[!0-9]*) ADOPT_WINDOW=1200 ;; esac

    # THE EVIDENCE, READ ONCE (wave-34 T6; REQ-14 AC-14.1/14.3, D23). Liveness used to be an mtime and
    # LANDED the deliverable's presence, so a SIGKILLed probe read LANDED and a just-killed one RUNNING
    # (field report 2026-10-11, item 1). Three inputs replace them: this session's newest ListAgents answer
    # (lib/agents.sh, less every agent a TaskStop after it ended) — an agent it lists is reachable by name;
    # the kept transcript reads (`adopt_read_baseline`) — growth across a cadence; and the sweeper's
    # completion signal — an agent's report, the only thing LANDED is read from. Acks are read from every
    # ledger in the root (`adopt_cross_acks`).
    ADOPT_SWEEPER="$HOOK_DIR/session-sweeper.sh"
    ADOPT_PANEL_RC=4; ADOPT_PANEL=""
    ADOPT_TR="$(session_transcript "$SESSION_ID")" || ADOPT_TR=""
    if [ -n "$ADOPT_TR" ]; then
      _la_ensure "$ADOPT_TR" 2>/dev/null; ADOPT_PANEL_RC=$?
      if [ "$ADOPT_PANEL_RC" -eq 0 ]; then
        ADOPT_PANEL="$(printf '%s\n' "$_LA_CACHE_OUT" | ADOPT_GONE="$(live_agents_since_answer "$ADOPT_TR" 2>/dev/null \
          | awk -F'\t' '$1 == "stopped" { print $2 }')" awk -F'|' '
            BEGIN { n = split(ENVIRON["ADOPT_GONE"], g, "\n"); for (i = 1; i <= n; i++) if (g[i] != "") gone[g[i]] = 1 }
            $1 != "" && !($1 in gone) { print $1 "|" $3 }')"
      fi
    fi
    ADOPT_READS_FILE="$ADOPT_DIR/adopt-reads.state"
    ADOPT_READS_OLD=""
    [ -f "$ADOPT_READS_FILE" ] && [ ! -L "$ADOPT_READS_FILE" ] && ADOPT_READS_OLD="$(cat "$ADOPT_READS_FILE" 2>/dev/null)"
    ADOPT_READS_NEW=""
    # THE ONE CLOSURE RULE (wave-36 T10; AC-4.4, D10): lib/fill.sh `roster_row_open`, which the dispatch
    # wall's hold asks too, handed the inputs this run already resolved. It reads every ledger's acks.
    roster_closure_begin "$ADOPT_DIR" "$ADOPT_LIVE_IDS" "$ADOPT_WINDOW" "$ADOPT_NOW"
    adopt_handoff_note "$ADOPT_OWN_PLAN" "$REPO_REAL" "$ADOPT_DIR"
    # THE ACTIVE READERS (wave-36 T29; REQ-4 AC-4.1; D10). A reader (auditor, critic) is swept MET when
    # its record lands and is acked on its own session's ledger, while its plan row stays `active` until
    # the orchestrator registers the reading. A `/clear` in between left it closed here, so it came out
    # on no roster and the launch arm refused its row (wave-35 A-orch-46). So a read-only role's row
    # (`role_is_readonly`) whose name is the agent cell of an `active` row of this session's bound plan
    # is carried as an open writer row is, its own ledger's ack notwithstanding; it is then listed,
    # adopted and closed by `roster_row_open` exactly as every row is. A writer stays closed by its ack:
    # a writer's tree and takeover are not a reader's. The agent cells are read once per run.
    ADOPT_ACTIVE=""
    [ -z "$ADOPT_OWN_PLAN" ] || ADOPT_ACTIVE="$(units_rows "$(adopt_abs "$ADOPT_OWN_PLAN" "$REPO_REAL")" 2>/dev/null \
      | awk -F'\t' '$10 == "active" && $5 ~ /[A-Za-z0-9]/ { print $5 }')"

    # THE WALK IS lib/fill.sh's `fill_roster_walk` (wave-35 T28; AC-5.5, D14): every regular, unlinked
    # `roster-<sid>.state` but this session's, each with its own ledger, an unreadable one said and left
    # out. The fill and the dispatch wall take the same walk, so a row this verb lists open is a row the
    # tick never offers. Read on fd 3: nothing in the body may eat the walk.
    while IFS=$'\t' read -r OSID ADOPT_RF ADOPT_LEDGER <&3; do
      [ -n "$OSID" ] || continue
      ADOPT_OUT="$(adopt_fold "$ADOPT_RF" "$ADOPT_LEDGER")"
      if [ -n "$ADOPT_ACTIVE" ]; then
        # THE SAME FOLD WITH NO ACKS, kept to the active readers of this run the open fold left out.
        while IFS= read -r ADOPT_AR; do
          ADOPT_AR_N="${ADOPT_AR%%|*}"; ADOPT_AR_T="${ADOPT_AR#*|*|}"; ADOPT_AR_T="${ADOPT_AR_T%%|*}"
          [ -n "$ADOPT_AR_N" ] && role_is_readonly "$ADOPT_AR_T" || continue
          case "
$ADOPT_ACTIVE
" in *"
$ADOPT_AR_N
"*) ;; *) continue ;; esac
          case "
$ADOPT_OUT" in *"
$ADOPT_AR_N|"*) continue ;; esac
          ADOPT_AR_P="$(printf '%s' "$ADOPT_AR" | cut -d'|' -f9)"
          [ -n "$ADOPT_OWN_KEY" ] && [ "$(adopt_plan_key "$ADOPT_AR_P")" = "$ADOPT_OWN_KEY" ] || continue
          ADOPT_OUT="${ADOPT_OUT}${ADOPT_OUT:+
}${ADOPT_AR}"
        done <<ADOPT_READERS
$(adopt_fold "$ADOPT_RF" "")
ADOPT_READERS
      fi
      [ -n "$ADOPT_OUT" ] || continue
      # COUNTED WHEN IT CONTRIBUTES, not when it is merely read. A predecessor whose every
      # row is closed is residue, and "N open row(s) from M predecessor session(s)" would be
      # a sentence naming sessions the reader was shown nothing from.
      ADOPT_SESSION_COUNTED=no

      # Resolved ONCE per predecessor session, not once per row: the walk is the same for
      # every agent that session launched.
      OSUB="$(session_subagent_dir "$OSID")" || OSUB=""
      ADOPT_VERDICTS=""; ADOPT_VERDICTS_READ=no

      while IFS='|' read -r RNAME RID RTYPE RDELIV RPROG RCAD RLAUNCH RORIG RPLAN RWAIVER \
                            RSSRC RDONE RLRED RREVID RLROW RSRC; do
        [ -n "$RNAME" ] || continue
        # THE LIST FIELDS ARE READ OFF THE SOURCE ROW, the last column, by key (wave-37 T7, D11).
        RSALLOW="$(line_field "$RSRC" suites_allowed)"
        RREX="$(line_field "$RSRC" re_executes)"

        # ---- IS THIS ROW STILL SOMEBODY'S WORK? (REQ-9 AC-9.1/9.2; D10)
        #
        # CLOSURE IS DERIVED, NEVER STORED (spec §1). Two independent facts close a row for
        # this verb, and neither is a new field: the run its own `plan=` names is closed
        # (`run_open`, the same predicate `bind` and the tick's run-state read use), or the
        # session that launched it is dead and its files are already sweepable. Either way
        # there is nothing to take over, and a row offered anyway costs the operator a ledger
        # entry, a message address and a stop for work that no longer exists.
        #
        # CHECKED BEFORE THE PARTITION, AND ABOVE `own` INCLUDED. The plan partition answers
        # "whose run is this row"; closure answers "is there a run at all". A row of OUR OWN
        # closed binding is residue exactly as a neighbour's is, and adopting it would take
        # ownership of an agent whose contract nothing is left to discharge.
        #
        # A GONE PLAN IS NOT A CLOSED ONE. `run_open` says nothing about a path that is not
        # a file here — another root's plan, a plan since deleted — so the row keeps today's
        # partition and is listed. A verb that cannot read a fact does not guess it.
        #
        # AND AN UNREADABLE PLAN IS NEITHER (wave-20 T18, REQ-2, D2; T1's carry-over). A plan
        # that is THERE and cannot be read — mode 000, or inside a folder that cannot be
        # opened (`plan_unreadable`, lib/run.sh) — was read two wrong ways here: at mode 000
        # `-f` held and `run_open` failed, so its rows were counted closed and printed
        # nowhere; in an unopenable folder `-f` failed, so the row fell through to the
        # partition and an unbound caller ADOPTED it. Its run may be mid-flight and nothing
        # about it can be read, so the row is listed as UNREADABLE with the path, never
        # adopted and never counted closed — `session_run`'s `bound-unreadable`, asked of the
        # row's plan instead of the session's (cross-gate §S.4g).
        #
        # THE RULE IS lib/fill.sh's `roster_row_open` (wave-36 T10; AC-4.4, D10), the one the dispatch
        # wall's hold asks, in this order: a dead, sweepable session closes (asked once per session);
        # an unreadable plan answers 2, listed UNREADABLE below; a closed run closes; an ack taken in
        # another session after the launch closes. A row the wall admits over is a row this verb skips.
        ADOPT_ROW_CLOSED=no
        ADOPT_ROW_UNREADABLE=""
        roster_row_open "$OSID" "$RNAME" "$RID" "$RLAUNCH" "$RPLAN"
        case $? in
          1) ADOPT_ROW_CLOSED=yes ;;
          2) ADOPT_ROW_UNREADABLE="$ROSTER_ROW_WHY" ;;
        esac
        if [ "$ADOPT_ROW_CLOSED" = yes ]; then
          ADOPT_CLOSED=$((ADOPT_CLOSED + 1))
          continue
        fi

        # ---- ONE AGENT ID, ONE OFFER (AC-9.2). An empty id is never deduped: an
        # UNADDRESSABLE row has no identity to be the same as another's, and folding two of
        # them together would hide a row the operator has to fix at its source.
        if [ -n "$RID" ]; then
          case "$ADOPT_SEEN_IDS" in
            *"|${RID}|"*) ADOPT_DUPES=$((ADOPT_DUPES + 1)); continue ;;
          esac
          ADOPT_SEEN_IDS="${ADOPT_SEEN_IDS}${RID}|"
        fi

        if [ "$ADOPT_SESSION_COUNTED" = no ]; then
          ADOPT_SESSIONS=$((ADOPT_SESSIONS + 1))
          ADOPT_SESSION_COUNTED=yes
        fi
        ADOPT_ROWS=$((ADOPT_ROWS + 1))

        # ---- THE STOP ADDRESS, BUILT FROM THE SESSION THAT LAUNCHED THE AGENT
        #
        # T3 FINDING 1, live 2026-09-03. This was the ADOPTING session's eight until a real
        # `/clear` was driven against a real harness: `TaskStop PROBE-AGENT@session-<adopting
        # 8>` came back `No task found with ID: … Running teammates:
        # PROBE-AGENT@session-<launching 8>`. The probe that argued for the adopting session
        # was right about the env — `CLAUDE_CODE_SESSION_ID` does re-key — and wrong about
        # the teammate table, which keys on the session that made the `Agent` call and does
        # not re-key with it. So the suffix comes off the ROW (its `adopted_from=`, else its
        # own `session=`, else the roster file's session), never off ours.
        #
        # EMPTY WITHOUT AN ID, because the address is only ever offered beside one: a row
        # with no identity has no stop line to carry it, and a machine field that named an
        # address the UNADDRESSABLE branch refuses to print would contradict its own row.
        ADOPT_ADDR_SID="${RORIG:-$OSID}"
        ADOPT_ADDR=""
        [ -n "$RID" ] \
          && ADOPT_ADDR="$(clean "$RNAME")@session-$(printf '%s' "$ADOPT_ADDR_SID" | cut -c1-8)"

        # ---- the deliverable, on disk or not
        RDELIV_ABS="$(adopt_abs "$RDELIV" "$REPO_REAL")"
        DELIV_PRESENT=no
        [ -n "$RDELIV_ABS" ] && [ -e "$RDELIV_ABS" ] && DELIV_PRESENT=yes

        # ---- the progress file's age against the cadence its own row declared
        RPROG_ABS="$(adopt_abs "$RPROG" "$REPO_REAL")"
        PROG_AGE=""
        PROG_MTIME=0
        if [ -n "$RPROG_ABS" ] && [ -f "$RPROG_ABS" ]; then
          PROG_MTIME="$(file_mtime "$RPROG_ABS")"
          PROG_AGE=$(( ADOPT_NOW - PROG_MTIME ))
        fi
        CAD_S="$(parse_seconds "$RCAD")" || CAD_S=""

        # ---- the three addresses, all of them derived from the one id
        #
        # RESOLVED THROUGH THE SAME NEWEST-COPY PREFERENCE `row_quiet` USES (D8, REQ-8;
        # supersedes T1d, walk W-3). This report used to quote ONLY the launching session's
        # copy, unconditionally — so a re-run of `adopt --report-only` after this session
        # had already exchanged a turn with the agent (the file now sitting under THIS
        # session's subagents dir) still named the launcher's stale path and age, while the
        # next tick's `row_quiet` read the fresh one: one row, two disagreeing readers. A
        # chain of "this session, else the launcher" also missed an INTERMEDIATE adopter
        # between two `/clear`s — `agent_log_newest` is the one function both readers ask
        # now, and it globs every session directory rather than walking a chain.
        TX=""
        TX_PRESENT=no
        TX_AGE=""
        TX_MTIME=0
        if [ -n "$RID" ]; then
          # THIS SESSION'S PROJECT DIRECTORY FIRST, falling back to the PREDECESSOR's — the
          # two are ordinarily the same physical directory, but this session may never have
          # spoken to any agent yet (no transcript, no subagents dir of its own), while the
          # predecessor's directory is exactly what this walk is iterating over.
          TX_PROJ="$(agent_project_dir_for "$SESSION_ID")" || TX_PROJ=""
          [ -n "$TX_PROJ" ] || TX_PROJ="$(agent_project_dir_for "$OSID")" || TX_PROJ=""
          TX=""
          [ -n "$TX_PROJ" ] && { TX="$(agent_log_newest "$RID" "$TX_PROJ")" || TX=""; }
          if [ -n "$TX" ]; then
            TX_PRESENT=yes
            # THE SECOND LIVENESS INPUT. The harness appends to this file on every turn
            # the agent takes, so its mtime is a fact about the agent rather than a
            # promise the agent has to remember to keep.
            TX_MTIME="$(file_mtime "$TX")"
            TX_AGE=$(( ADOPT_NOW - TX_MTIME ))
          elif [ -n "$OSUB" ]; then
            # NEITHER SESSION HAS SPOKEN TO THE AGENT YET — still name the launcher's path
            # (where the file will land once it does) rather than nothing.
            TX="$OSUB/agent-${RID}.jsonl"
          else
            # The slug could not be resolved — say where to look rather than inventing a
            # path that would read as a fact.
            TX="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/*/${OSID}/subagents/agent-${RID}.jsonl"
          fi
        fi

        # ---- the verdict
        #
        # UNADDRESSABLE OUTRANKS THE REST, because it is the only one of the four that is
        # about this verb's own subject — the id. A row without one cannot be messaged or
        # stopped whatever its artifacts say, and the cure is prospective (it fixes the NEXT
        # dispatch, not this row). The deliverable's state is still printed underneath, so
        # nothing is hidden by the ordering.
        #
        # WAIVED IS NEXT (S17, AC-12 attempt 2), ahead of LANDED/RUNNING/SILENT, and for the
        # same reason `session-sweeper.sh verdict_row` puts it first: a carried `waiver=` is
        # an explicit designation that this row's contract is not held, so its deliverable's
        # absence is not "quiet for now" — it was never open. Printing SILENT for such a row,
        # which is what happened before the field was carried at all, read as an unmet
        # contract for one that was closed at dispatch (the live T4 walk this fixes).
        # LIVE ON EITHER MTIME, STALE ONLY ON BOTH (1.6, AC-6). The progress file is a
        # promise the agent keeps by hand — the first thing to lapse when the work gets
        # absorbing, and impossible for a role with no Write tool — so reading it alone
        # called working agents SILENT. The transcript is the harness's own record of the
        # agent taking a turn, at the very path this verb already prints as the observe
        # address, so it costs one stat and answers the question the progress file was
        # standing in for. SILENT now means neither a written line nor a turn taken inside
        # the window, which is a state worth waking someone for.
        #
        # THE WINDOW IS ONE CADENCE, AND THE CLASSIFICATION IS THE LIBRARY'S (REQ-10 D9).
        # This arm used to compute twice the cadence here, from a constant of its own, on the
        # reasoning
        # that a row promising a line every ten minutes is up to ten minutes stale at any
        # random instant while perfectly healthy. The reasoning is sound and the consequence
        # was not: `observe_class` (payload/scripts/lib/observe.sh) answers the SAME question
        # at ONE cadence for the stop gates, so one row was alive to one reader and silent to
        # another, and the fleet carried four staleness arithmetics for three questions. Both
        # readers ask the function now; an author who wants slack declares it in the cadence,
        # which is the liveness contract's own rule ("too quiet" means quieter than the
        # AUTHOR'S OWN declaration).
        #
        # THE SIX INPUTS ARE FILLED BY HAND because this caller already holds the row and the
        # two stats — `observe_agent` would re-resolve a target against THIS session's roster,
        # which is not where these rows live. Delivery is left `none`: the verdict order below
        # asks about the deliverable itself one branch later, and `observe_class` outranking it
        # here would answer the same question twice.
        LIVE=no
        OBS_DELIV_STATE=none
        OBS_PROGRESS_STATE=unnamed; OBS_PROGRESS_AGE=0
        OBS_LOG_MTIME=0; OBS_LOG_AGE=0
        OBS_CADENCE_S="${CAD_S:-$OBSERVE_CADENCE_DEFAULT_S}"
        if [ -n "$PROG_AGE" ]; then
          OBS_PROGRESS_STATE=present; OBS_PROGRESS_AGE="$PROG_AGE"
        fi
        if [ -n "$TX_AGE" ]; then
          OBS_LOG_MTIME="$TX_MTIME"; OBS_LOG_AGE="$TX_AGE"
        fi
        [ "$(observe_class)" = alive ] && LIVE=yes

        # ---- the evidence (wave-34 T6; REQ-14 AC-14.1, D23)
        #
        # THE REPORT: the sweeper's verdict on the launching session's roster, MET with a completion
        # signal it actually read (`said=`). Asked once per roster, and only of a roster with a row
        # whose deliverable is on disk.
        REPORTED=no
        if [ -n "$RID" ] && [ "$DELIV_PRESENT" = yes ]; then
          if [ "$ADOPT_VERDICTS_READ" = no ]; then
            ADOPT_VERDICTS_READ=yes
            [ -f "$ADOPT_SWEEPER" ] && ADOPT_VERDICTS="$( cd "$REPO_REAL" 2>/dev/null \
              && CLAUDE_CODE_SESSION_ID="$OSID" bash "$ADOPT_SWEEPER" verdict 2>/dev/null )"
          fi
          printf '%s\n' "$ADOPT_VERDICTS" | awk -v k="|name=$(clean "$RNAME")|" \
            'index($0, "landing-verdict/v1|") == 1 && index($0, k) && index($0, "|state=MET|") && index($0, "said=") { f = 1 } END { exit !f }' \
            && REPORTED=yes
        fi
        # REACHABLE BY NAME: this session's fresh answer lists it, and with what status.
        PANEL_ST=""
        [ -n "$RID" ] && [ "$ADOPT_PANEL_RC" -eq 0 ] \
          && PANEL_ST="$(printf '%s\n' "$ADOPT_PANEL" | awk -F'|' -v n="$(clean "$RNAME")" '$1 == n { s = $2 } END { print s }')"
        # GROWTH: the newest kept read at least one cadence old, against this one.
        GREW=""; TX_SIZE=""; BASE_LINE=""
        if [ "$TX_PRESENT" = yes ]; then
          TX_SIZE="$(stat -f %z "$TX" 2>/dev/null || stat -c %s "$TX" 2>/dev/null)"
          case "$TX_SIZE" in ''|*[!0-9]*) TX_SIZE="" ;; esac
        fi
        if [ -n "$TX_SIZE" ]; then
          BASE_LINE="$(adopt_read_baseline "$ADOPT_READS_OLD" "$RID" $(( ADOPT_NOW - OBS_CADENCE_S )))"
          if [ -n "$BASE_LINE" ]; then
            GREW=no; [ "$TX_SIZE" -gt "${BASE_LINE%% *}" ] && GREW=yes
          fi
          ADOPT_READS_NEW="${ADOPT_READS_NEW}${ADOPT_READS_NEW:+
}${ADOPT_READS_SCHEMA}|id=${RID}|size=${TX_SIZE}|epoch=${ADOPT_NOW}"
        fi

        if [ -z "$RID" ]; then
          VERDICT=UNADDRESSABLE
        elif [ -n "$RWAIVER" ]; then
          VERDICT=WAIVED
        elif [ "$DELIV_PRESENT" = yes ] && [ "$REPORTED" = yes ]; then
          VERDICT=LANDED
        elif [ -n "$PANEL_ST" ] && [ "$PANEL_ST" != "$_LA_ROW_CLOSED_STATUS" ]; then
          VERDICT=RUNNING
        elif [ "$GREW" = yes ]; then
          VERDICT=RUNNING
        elif [ -n "$PANEL_ST" ]; then
          VERDICT=IDLE
        elif [ "$GREW" = no ]; then
          VERDICT=SILENT
        elif [ "$LIVE" = yes ]; then
          VERDICT=UNCONFIRMED
        else
          VERDICT=SILENT
        fi
        # THE SENTENCE BEHIND THE WORD, printed under the row: which evidence decided it.
        case "$ADOPT_PANEL_RC" in
          0) PANEL_WORDS="not on this session's fresh ListAgents answer" ;;
          *) PANEL_WORDS="this session has no fresh ListAgents answer to find it on" ;;
        esac
        case "$VERDICT" in
          LANDED)  EVIDENCE="its report is on record, beside the deliverable" ;;
          RUNNING) if [ -n "$PANEL_ST" ]; then EVIDENCE="on this session's fresh ListAgents answer, $PANEL_ST"
                   else EVIDENCE="its transcript grew from ${BASE_LINE%% *} to $TX_SIZE bytes since a read $(( ADOPT_NOW - ${BASE_LINE##* } ))s ago"; fi ;;
          IDLE)    EVIDENCE="on this session's fresh ListAgents answer, idle: it finished its turn with no report on record — message it" ;;
          UNCONFIRMED) EVIDENCE="written within its cadence, but $PANEL_WORDS and no read a cadence old to compare — run ListAgents, or adopt again after ${OBS_CADENCE_S}s" ;;
          SILENT)  if [ "$GREW" = no ]; then EVIDENCE="no growth since a read $(( ADOPT_NOW - ${BASE_LINE##* } ))s ago, and $PANEL_WORDS"
                   else EVIDENCE="nothing written within its cadence, and $PANEL_WORDS"; fi ;;
          *)       EVIDENCE="" ;;
        esac

        # ---- WHOSE RUN IS THIS ROW? (AC-2)
        #
        # `plan=none` READS AS UNATTRIBUTED, not as another run. `none` is the marker's own
        # word for "this session had no binding" (payload/scripts/lib/run.sh:378), so a row
        # carrying it names no run at all — and calling it "another run in this root" would
        # assert a run that does not exist. Both answers are un-adoptable, so the choice
        # only decides which heading the operator reads it under.
        #
        # UNREADABLE OUTRANKS ALL FOUR, `own` and `all` included: ownership is taken against a
        # run, and this row's run cannot be read.
        if [ -n "$ADOPT_ROW_UNREADABLE" ]; then
          PARTITION=unreadable
        elif [ -z "$ADOPT_OWN_KEY" ]; then
          PARTITION=all
        elif [ -z "$RPLAN" ] || [ "$RPLAN" = none ]; then
          PARTITION=unattributed
        elif [ "$(adopt_plan_key "$RPLAN")" = "$ADOPT_OWN_KEY" ]; then
          PARTITION=own
        else
          PARTITION=other
        fi
        case "$PARTITION" in
          own|all)    ADOPT_ADOPTED=$((ADOPT_ADOPTED + 1)) ;;
          unreadable) ADOPT_UNREADABLE=$((ADOPT_UNREADABLE + 1)) ;;
          *)          ADOPT_LISTED=$((ADOPT_LISTED + 1)) ;;
        esac

        # THE HEADING IS A GROUP SEPARATOR, printed when the partition CHANGES rather than
        # once for the whole report. Rows arrive in roster order and a predecessor session
        # dispatched under one binding, so in practice each kind is one contiguous run and
        # gets exactly one heading; a session that rebound mid-flight interleaves them and
        # gets the heading again, which is right — a heading standing over rows of another
        # kind would be worse than a repeated one. An unbound caller sees neither line.
        if [ "$PARTITION" != "$ADOPT_LAST_PART" ]; then
          case "$PARTITION" in
            other)        say "other runs in this root — listed, never adopted" ;;
            unattributed) say "unattributed rows (pre-wave rosters) — listed, never adopted" ;;
            unreadable)   say "UNREADABLE — rows whose plan is there and cannot be read — listed, never adopted, never counted closed" ;;
          esac
        fi
        ADOPT_LAST_PART="$PARTITION"

        # THE TWO NEW FIELDS ARE TRAILING, so every existing field keeps its position for a
        # reader that counts rather than looks up by key. `plan=` is the row's own
        # attribution (`none` when it carried none) and `partition=` is what this caller
        # decided about it.
        printf '%s|at=%s|session=%s|from=%s|name=%s|verdict=%s|agent_id=%s|address=%s|subagent_type=%s|deliverable=%s|deliverable_present=%s|progress=%s|progress_age=%s|cadence=%s|transcript=%s|transcript_present=%s|transcript_age=%s|plan=%s|partition=%s\n' \
          "$ADOPT_SCHEMA" "$(iso_now)" "$SESSION_ID" "$OSID" "$(clean "$RNAME")" "$VERDICT" \
          "$RID" "$ADOPT_ADDR" "$(clean "$RTYPE")" "$(clean "$RDELIV_ABS")" "$DELIV_PRESENT" \
          "$(clean "$RPROG_ABS")" "${PROG_AGE:-unknown}" "${CAD_S:-unknown}" \
          "$(clean "$TX")" "$TX_PRESENT" "${TX_AGE:-unknown}" \
          "$(clean "${RPLAN:-none}")" "$PARTITION"

        # ---- the adoption itself, written before it is printed
        #
        # The row is what makes the address below TRUE: hooks/stop-guard.sh accepts
        # `<name>@session-<this session>` as an identity because THIS session's roster
        # records it, and resolves the agent at all because the row names the session it is
        # filed under. Printing the address without writing the row would hand the operator
        # a second line they cannot use.
        # THE WRITE'S ANSWER IS READ, because `die()` prints and RETURNS — it does not exit
        # (:156, and every other caller depends on that). A warning followed by the address
        # block below would hand the operator a `TaskStop` line that both stop gates refuse
        # as FOREIGN, since ownership is taken from the row that was just NOT written
        # (review-a C-3). So the row's own state decides which rendering it gets.
        #
        # `--report-only` TAKES THE SAME ROW AND DOES NOT FILE IT. The rendering below is
        # unchanged — same verdict, same addresses, same tail — because the whole point of
        # the flag is that the operator reads exactly what `adopt` would then write. The
        # stop address it prints is the address the write MAKES true, so it is printed as
        # the instruction it is: run `adopt`, and this line works. AC-4's "identical rows"
        # is pinned in tests/session-poker.test.sh §8i by comparing the two renderings.
        #
        # AND THE PARTITION DECIDES WHETHER IT IS FILED AT ALL (AC-2). A row belonging to
        # another run in this root is never written to this session's roster: the write is
        # what makes the stop address true, so writing it would take ownership of an agent
        # this session did not launch and is not steering — the exact harm the partition
        # exists to prevent. It is still printed, one arm down.
        ROW_JOURNALLED=no
        ROW_LISTED_ONLY=no
        case "$PARTITION" in
          own|all)
            if [ -n "$RID" ] && [ "$ADOPT_REPORT_ONLY" = yes ]; then
              ROW_JOURNALLED=yes
            elif [ -n "$RID" ]; then
              if adopt_write_row "$ADOPT_OWN_ROSTER" "$SESSION_ID" "$RNAME" "$RID" "$RTYPE" \
                   "$RDELIV" "$RPROG" "$RCAD" "$RLAUNCH" "$OSID" "$ADOPT_ADDR" \
                   "${ADOPT_OWN_PLAN:-none}" "$RWAIVER" \
                   "$RSRC" "$RSSRC" "$RDONE" "$RLRED" "$RREVID" "$RLROW"; then
                ROW_JOURNALLED=yes
                # THE MARKER COPY (S17, AC-12 attempt 2). `payload/scripts/lib/stop.sh`
                # (`stop_landing_gate`, reached from hooks/stop.sh) is this schema's one
                # ORIGINATING writer. This is a second writer, deliberately: adopt never
                # ORIGINATES a `landing-swept/v1` verdict, it only COPIES a line that writer
                # already produced onto the roster this session is now the owner of, so
                # `hooks/session-start.sh`'s `open_rows` — which still reads a marker
                # straight off the SAME roster file as ground truth, with no re-derivation —
                # sees the same history on the successor that stood on the predecessor. A
                # closed name can never reach here: `adopt_fold` excludes it through the
                # `roster_open_names` predicate (an ack later than the row's launch), not a
                # `met[]` filter, so only a still-open history is ever offered to copy.
                adopt_copy_marker "$ADOPT_RF" "$ADOPT_OWN_ROSTER" "$(clean "$RNAME")"
              else
                die "WARN — this row could not be journalled to $ADOPT_OWN_ROSTER; the stop gate will not treat $RNAME as ours."
              fi
            fi ;;
          *) ROW_LISTED_ONLY=yes ;;
        esac

        # A READER SAYS SO on its verdict line (wave-36 T29): it holds no tree and no writer slot.
        ADOPT_ROLE_WORD=""
        role_is_readonly "$RTYPE" && ADOPT_ROLE_WORD=" · read-only"
        say "$(clean "$RNAME") ($(clean "$RTYPE")) from session $OSID — ${VERDICT}${ADOPT_ROLE_WORD}"
        # THE PATH, ON EVERY UNREADABLE ROW WHATEVER ITS ID, because the cure is on the plan.
        [ "$PARTITION" = unreadable ] \
          && printf '  plan        : UNREADABLE — %s is there and cannot be read\n' "$(clean "$ADOPT_ROW_UNREADABLE")"
        if [ -n "$RID" ] && [ "$ROW_JOURNALLED" = yes ]; then
          printf '  agent id    : %s\n' "$RID"
          printf '  observe     : %s (%s)\n' "$TX" \
            "$([ "$TX_PRESENT" = yes ] && echo 'on disk' || echo 'not on disk')"
          # THE MESSAGE ADDRESS IS THE NAME (T22, A-orch-33), and the id keeps the two lines
          # it is genuinely the key for — the observe path above and the stop below. It was
          # the transcript-form id here until 2026-09-14, when a SendMessage to an id a
          # `/clear` had re-keyed made the harness RESUME A COPY of the agent while the
          # original was still running: two processes, one contract, one roster row. The
          # agent table does not survive a `/clear`; the TEAMMATE table, keyed on the name,
          # does — so the name is the address that keeps meaning the same agent.
          printf '  message     : SendMessage to:%s\n' "$(clean "$RNAME")"
          # THE ADDRESS THE PLATFORM ACCEPTS, not the one this verb happens to hold. The id
          # on the roster is the TRANSCRIPT form; the stop primitive takes
          # `<name>@session-<id8>` for a teammate and rejects the transcript form (capture
          # record/session-20260814-wave-detector-terminal-state/min/logs/A-p3.jsonl:9), so
          # printing the id cost the operator a refusal they could not clear.
          #
          # ONE SUFFIXED SPELLING, AND IT IS THE LAUNCHING SESSION'S (T3 FINDING 1). The
          # alternate — this session's eight — was printed here until a live `/clear` drive
          # refused it by name and the harness named the launching session's in its place.
          # See the construction above for what the row is read for.
          #
          # AND THE BARE NAME BENEATH IT, because it is the one address that survived every
          # step of that drive: it reached the stop wall before the `/clear` and after it,
          # and it is what finally stopped the adopted agent when the suffixed form did not
          # resolve. Neither stop gate keys on the suffix — each resolves on the base name
          # and takes ownership from the id on this session's roster
          # (tests/stop-guard.test.sh §14, tests/stop-check.test.sh §10(d)) — so offering
          # both costs the operator nothing and covers the case where the suffix is stale.
          printf '  stop        : TaskStop %s\n' "$ADOPT_ADDR"
          printf '                TaskStop %s — the bare name, the address that always survives\n' \
            "$(clean "$RNAME")"
        elif [ "$ROW_LISTED_ONLY" = yes ] && [ -n "$RID" ]; then
          # LISTED, NOT ADOPTED. Everything that does not depend on this session's roster is
          # still printed — the id, the observe address, the message address all belong to
          # the agent rather than to us — and the one line that would be a lie is replaced by
          # the reason it is missing. The operator can still SEE and MESSAGE an agent of the
          # other run; taking ownership of it is what they may not do, and the cure is the
          # other session, not a retry here.
          printf '  agent id    : %s\n' "$RID"
          printf '  observe     : %s (%s)\n' "$TX" \
            "$([ "$TX_PRESENT" = yes ] && echo 'on disk' || echo 'not on disk')"
          printf '  message     : SendMessage to:%s\n' "$(clean "$RNAME")"
          if [ "$PARTITION" = unreadable ]; then
            printf '  stop        : not adopted — this row'"'"'s plan cannot be read, so there is no\n'
            printf '                run to take ownership against. Restore read access and re-run adopt.\n'
          elif [ "$PARTITION" = other ]; then
            printf '  stop        : not adopted — this row belongs to another run in this root\n'
            printf '                (%s), and ownership stays with the session working it.\n' "${RPLAN:-none}"
          else
            printf '  stop        : not adopted — this row carries no plan= attribution\n'
            printf '                (a roster written before session-bound runs existed), so it\n'
            printf '                cannot be told from another run in this root.\n'
          fi
        elif [ -n "$RID" ]; then
          # ADDRESSABLE FOR EVERYTHING BUT THE STOP. The id is real and the transcript and
          # the message address do not depend on this session's roster — only ownership
          # does, and that is precisely what the failed write cost. So the two true lines
          # are still printed and the one that would be false is replaced by its cause,
          # which is the UNADDRESSABLE shape below applied to the half that is missing.
          printf '  agent id    : %s\n' "$RID"
          printf '  observe     : %s (%s)\n' "$TX" \
            "$([ "$TX_PRESENT" = yes ] && echo 'on disk' || echo 'not on disk')"
          printf '  message     : SendMessage to:%s\n' "$(clean "$RNAME")"
          printf '  stop        : unavailable — this adoption was NOT journalled to\n'
          printf '                %s\n' "$ADOPT_OWN_ROSTER"
          printf '  cure        : both stop gates take ownership from THIS session'"'"'s roster, so\n'
          printf '                until that write lands every stop of %s is refused as\n' "$(clean "$RNAME")"
          printf '                FOREIGN. Clear that path — a symlink where the roster goes, or\n'
          printf '                a .bionic/tmp that is not a writable real directory — and re-run adopt.\n'
        else
          printf '  agent id    : (none — no identified row on that roster)\n'
          printf '  observe     : unavailable without an id\n'
          printf '  message     : unavailable without an id\n'
          printf '  stop        : unavailable without an id\n'
          printf '  cure        : the predecessor'"'"'s dispatch wall or execution recorder was dead when\n'
          printf '                this row was written — re-invoke /bionic:canonical-sdlc before\n'
          printf '                dispatching, or the same thing happens again.\n'
        fi
        printf '  launched    : %s\n' "${RLAUNCH:-unknown}"
        [ -z "$EVIDENCE" ] || printf '  evidence    : %s\n' "$EVIDENCE"
        # THE ROW'S RUN (wave-30 T12; REQ-3 AC-3.5). A row whose agent started a detached suite run
        # (booked.sh --detach) carries its record; the run outlives the session that started it, so
        # the successor is told what it is doing: RUNNING with its pid and age, FINISHED with its
        # code, or LOST with the time its log was last written. `wait <name>` waits on it, and
        # `stop-run <name>` stops it. A row with no run record prints no line.
        if run_load_row "$(run_row_of "$ADOPT_RF" "$RNAME")" "$ADOPT_RF"; then
          run_read
          printf '  run         : %s\n' "$(run_state_words)"
        fi
        # THE BUDGET, BESIDE THE LAUNCH (T6, REQ-5, AC-5.1). A resumed orchestrator needs the
        # row's allowance to widen it, and a row can carry only declared RUNS: its suites cell
        # is then empty, so the line names both cells rather than reading as no budget.
        _AD_RUNS="$(clean "$RREX" re_executes)"
        if [ -z "$RSALLOW" ] && [ -z "$_AD_RUNS" ]; then
          printf '  budget      : none\n'
        else
          printf '  budget      : suites=%s runs=%s\n' "${RSALLOW:-none}" "${_AD_RUNS:-none}"
        fi
        printf '  deliverable : %s (%s)\n' "${RDELIV_ABS:-none declared}" \
          "$([ "$DELIV_PRESENT" = yes ] && echo 'on disk' || echo 'not on disk')"
        printf '  progress    : %s (%s)\n' "${RPROG_ABS:-none declared}" \
          "$([ -n "$PROG_AGE" ] && printf '%ss old, cadence %ss' "$PROG_AGE" "${CAD_S:-unknown}" || echo 'not on disk')"
        if [ "$TX_PRESENT" = yes ]; then
          TAIL_TEXT="$(agent_report_tail "$TX")" || TAIL_TEXT=""
          if [ -n "$TAIL_TEXT" ]; then
            printf '  report tail (last long assistant block, capped at %s chars — quote it into\n' "$ADOPT_TAIL_CAP"
            printf '  the record before acting on it; a transcript is not an artifact):\n'
            printf '%s\n' "$TAIL_TEXT" | sed 's/^/    | /'
          fi
        fi
        printf '\n'
      done <<EOF
$ADOPT_OUT
EOF
    done 3<<ADOPT_WALK
$(fill_roster_walk "$ADOPT_DIR" "$SESSION_ID")
ADOPT_WALK

    # THE READS ARE KEPT BY THE WRITING VERB ONLY; `--report-only` writes nothing.
    if [ "$ADOPT_REPORT_ONLY" != yes ] && ! adopt_reads_write "$ADOPT_READS_FILE" "$ADOPT_READS_NEW" "$ADOPT_NOW"; then
      die "WARN — the transcript reads could not be kept in $ADOPT_READS_FILE; the next adopt has no read to judge growth against."
    fi

    # THE TWO NEW COUNTERS ARE TRAILING AND ADDITIVE (REQ-9 AC-9.1/9.2). A row this verb
    # dropped is invisible by design — that is the fix — so the COUNT of what was dropped is
    # on the line that answers for the run, or the drop could not be told from a walk that
    # found nothing.
    # `unreadable=` TRAILS THEM, the same way (wave-20 T18): a row neither adopted, listed as
    # another run's, nor closed is counted where the operator reads the other three.
    printf '%s|at=%s|session=%s|scanned=%s|open=%s|adopted=%s|listed=%s|closed=%s|dupes=%s|unreadable=%s\n' \
      "$ADOPT_SCHEMA" "$(iso_now)" "$SESSION_ID" "$ADOPT_SESSIONS" "$ADOPT_ROWS" \
      "$ADOPT_ADOPTED" "$ADOPT_LISTED" "$ADOPT_CLOSED" "$ADOPT_DUPES" "$ADOPT_UNREADABLE"
    # SAID ONCE, AND ONLY WHEN THERE IS SOMETHING TO SAY. An operator who expected a
    # predecessor's rows and was shown none is owed the reason.
    [ "$ADOPT_CLOSED" -gt 0 ] \
      && say "$ADOPT_CLOSED row(s) skipped: their run is closed, their session is dead and its state files are already sweepable, or an ack taken in another session closed them — there is nothing left to take over."
    [ "$ADOPT_UNREADABLE" -gt 0 ] \
      && say "$ADOPT_UNREADABLE row(s) UNREADABLE: their plan is there and cannot be read, so they are neither adopted nor counted closed — restore read access and re-run adopt."
    [ "$ADOPT_DUPES" -gt 0 ] \
      && say "$ADOPT_DUPES duplicate row(s) folded: one agent id is one agent, however many rosters carry a row for it."
    if [ "$ADOPT_ROWS" -eq 0 ]; then
      say "nothing to adopt — no other session has an open row on this project's rosters."
      exit 0
    fi
    say "$ADOPT_ROWS open row(s) from $ADOPT_SESSIONS predecessor session(s) — ledger every one BY AGENT ID before dispatching anything new."
    # THE SECOND LINE EXISTS ONLY WHEN IT SAYS SOMETHING. A caller that adopted everything it
    # found is the case this verb has always described, and a count of zero listed rows would
    # be a line the operator has to read to learn nothing.
    [ "$ADOPT_LISTED" -gt 0 ] \
      && say "$ADOPT_ADOPTED adopted onto this session's roster, $ADOPT_LISTED listed only — a row belonging to another run in this root is never adopted."
    # ONE EXTRA LINE, and the rows above untouched: the mode is stated where it changes what
    # the reader should do next, not woven through a rendering that has to stay comparable.
    [ "$ADOPT_REPORT_ONLY" = yes ] \
      && say "report-only: nothing was written — run 'adopt' to take these rows onto this session's roster."
    exit 1
  }

  # ---------------------------------------------------------------- sweep
  #
  # NOT ENGAGEMENT-GATED, AND DELIBERATELY (D-4). The engagement marker is itself one of the
  # files this verb removes: a session that never invoked the skill still leaves preflight
  # and roster state behind when it dies, and a cleanup that refused to run without
  # engagement would refuse hardest on the machines carrying the most residue. The guard the
  # other verbs take exists so bionic decides nothing about a session that never asked it to;
  # this verb decides nothing about any session at all — it removes files whose owners the
  # kernel says are gone AND whose newest file is old enough that nobody dispatching it a
  # moment ago could still be looking at it (below).
  #
  # IT TAKES NO SESSION ID, and that is the surface staying closed rather than an omission.
  # The question is "what here can nobody act on any more", which is a question about the
  # directory; an id operand would be a second way to ask it, and the one thing a caller
  # could do with it that the walk does not already do is name a session the walk skipped —
  # which is exactly the live one this verb refuses.
  #
  # PER-SESSION AGE IS OPT-IN, VIA `--window` (REQ-6/D5's prune half, moved here from T6).
  # Without the flag this verb is exactly what `tests/session-sweep.test.sh` has always
  # pinned it as (sections 1-6, none of which ever pass it): PID-liveness alone decides
  # dead-or-live, and every dead session's files go in one pass, aged or not — a question
  # about the directory, not about time. `hooks/session-start.sh`'s own auto-sweep gate
  # asks a cruder, SEPARATE question before it ever calls this verb at all: is ANY file
  # anywhere under `.bionic/tmp` younger than a poker interval, and if so, skip calling
  # `sweep` for the WHOLE run — every dead session's files, ancient or brand new, wait
  # together for the next session start (that gate is unchanged by this task; it is not in
  # this file). A batch dying by the hour meant `.bionic/tmp` only grew: the newest corpse
  # always blocked the oldest one's cleanup. `--window` is this verb's own, finer answer to
  # the SAME question, FOR A CALLER THAT ASKS FOR IT: each dead session's own newest file
  # must itself be older than the poker interval, or that one session — and only that one
  # — is deferred and named in the report, instead of the whole directory waiting on it.
  #
  # THE EXIT CODE SAYS WHETHER ANYTHING IS LEFT THAT THIS VERB MAY NOT TOUCH:
  #   0  the sweep completed — dead state removed (or listed), or there was none to begin with
  #      (with `--window`, a dead session deferred for being too young is not a fault either)
  #   1  nothing swept: every session with state here is LIVE, so there was nothing to remove
  #   2  usage, or a `.bionic/tmp` this verb will not delete inside
  # A live session's state is not a fault and the 1 is not a scolding — it is the one answer
  # a caller cannot read off "0 files removed", which is also what a live-only run and an
  # empty directory would otherwise share. A dead-but-deferred session (`--window` only) is
  # reported by name (never silently folded into either bucket) and does not turn a real
  # sweep into a 1: the 1 means "everything here is LIVE", not "nothing was old enough yet".
  poker_verb_sweep() {
    # The current session's own key, when it has one. It is not required — this verb answers
    # for the DIRECTORY, not for a session — but when it is present the session is live by
    # construction, and adding it by hand means a claude-home this process cannot read (an
    # unreadable `~/.claude/sessions`, a missing `jq`) can never let a session sweep its own
    # state out from under itself.
    SESSION_ID="$(session_id)" || SESSION_ID=""

    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    SWEEP_DIR="$REPO_REAL/.bionic/tmp"

    # THE SAME GUARD THE WRITERS TAKE, because a delete is a write. `tmp_dir_ok` is this
    # file's one copy of the rule (a `.bionic` symlinked outside the repo, a `tmp` that is
    # itself a link), and taking it here means the walk below cannot enumerate a single path
    # inside a directory the stamp writer would have refused.
    if ! tmp_dir_ok "$SWEEP_DIR"; then
      die "REFUSED — $SWEEP_DIR is not a directory this verb will delete inside."
      die "A .bionic or a tmp that is a symlink out of this repo is refused, never followed."
      exit 2
    fi
    if [ ! -d "$SWEEP_DIR" ]; then
      say "nothing to sweep — this project has no .bionic/tmp."
      exit 0
    fi

    # LIVE, NOT DEAD — one walk, not two (T6, 63405b0, reused: ownership moved here at
    # T6-fixup/971afdb). `patrol_dead_sessions` would answer this by calling
    # `patrol_state_session_ids` a second time internally and subtracting the live set; this
    # verb already walks that same id set once below, so asking the LIVE side once here and
    # comparing inline reaches the identical verdict without the second walk.
    # `patrol_live_session_ids` costs nothing proportional to residue under `.bionic/tmp` (it
    # reads `${CLAUDE_CONFIG_DIR}/sessions/*.json`, one file per running process, a
    # different and much smaller set). This session's own key is added by hand, live by
    # construction, so an unreadable claude-home can never let a session sweep itself.
    SWEEP_LIVE_IDS="$(patrol_live_session_ids)"
    [ -z "$SESSION_ID" ] || SWEEP_LIVE_IDS="${SWEEP_LIVE_IDS}${SWEEP_LIVE_IDS:+
}${SESSION_ID}"

    # THE WINDOW — read only when `--window` asked for it, so a plain `sweep` call costs
    # nothing extra and touches no new fact. This session's own poker interval, the exact
    # knob hooks/session-start.sh's own auto-sweep gate reads through a subprocess call to
    # this same verb. A malformed `.bionic/config.yaml` REFUSES the `interval` verb
    # elsewhere in this file, which is right for a caller that needs an exact answer; here
    # it must not disable pruning altogether, so a bad override falls back to this script's
    # own built-in default instead (a dead session's files still eventually clear rather
    # than accumulating forever behind a typo).
    SWEEP_WINDOW=0
    SWEEP_NOW=0
    SWEEP_STAT_GNU=no
    if [ "$SWEEP_WINDOWED" = yes ]; then
      SWEEP_WINDOW="$(poker_interval_seconds 2>/dev/null)"
      case "$SWEEP_WINDOW" in ''|*[!0-9]*) SWEEP_WINDOW="$(parse_seconds "$POKER_INTERVAL_DEFAULT" 2>/dev/null)" ;; esac
      case "$SWEEP_WINDOW" in ''|*[!0-9]*) SWEEP_WINDOW=1200 ;; esac
      SWEEP_NOW="$(now_epoch)"

      # THE STAT FLAVOUR, PROBED ONCE — the identical GNU/BSD discrimination
      # hooks/session-start.sh's own age gate uses (its own comment there has the full
      # rationale: GNU's `-f` is a different flag, `--file-system`, so trying the BSD form
      # first and treating any non-empty capture as success reads a filesystem report as a
      # timestamp). Duplicated rather than sourced: the two hooks share no process to read
      # one answer from.
      case "$(stat -c %Y /dev/null 2>/dev/null)" in
        ''|*[!0-9]*) SWEEP_STAT_GNU=no ;;
        *) SWEEP_STAT_GNU=yes ;;
      esac
    fi

    SWEEP_SCANNED=0
    SWEEP_DEAD=0
    SWEEP_KEPT=0
    SWEEP_YOUNG=0
    SWEEP_FILES=0
    SWEEP_REMOVED=0
    SWEEP_REFUSED=0

    # ONE PASS OVER THE DISK TO DECIDE AND DESCRIBE, ONE MORE TO DELETE — never a second
    # walk to RE-DERIVE the report (T6, A-T6.3: a two-walk shape that deletes first and then
    # re-lists a now-emptied directory undercounts every dead session to zero files, and at
    # "everything just got swept" can misreport "nothing swept: all sessions are LIVE").
    # `SWEEP_OUT` accumulates the WHOLE report as this loop goes, with a `?`-prefixed
    # placeholder standing in for any file this pass QUEUES (into `SWEEP_BULK`) rather than
    # deletes immediately. Every other line — live-kept, deferred, a symlink refused — is
    # final the moment it is written. Only after the loop does ONE `xargs -0 rm -f` pass run,
    # and only then are the placeholders resolved, by checking each path once more against
    # disk (never a second `rm`).
    SWEEP_OUT=""
    SWEEP_BULK=""
    # THE PER-START FILES, READ ONCE FOR THE WHOLE WALK (T83): handed to every
    # `patrol_session_state_files` call below, which then picks a session's own from this
    # list instead of globbing the directory once per class per session.
    SWEEP_PER_START="$(patrol_per_start_files "$REPO_REAL")"
    while IFS= read -r SWEEP_SID; do
      [ -n "$SWEEP_SID" ] || continue
      SWEEP_SCANNED=$((SWEEP_SCANNED + 1))

      # Newline-delimited containment against the LIVE set: an id counts as live
      # only as a whole line, so a dead session whose id is a prefix of a live
      # one is not mistaken for it.
      case "
$SWEEP_LIVE_IDS
" in
        *"
$SWEEP_SID
"*)
          SWEEP_KEPT=$((SWEEP_KEPT + 1))
          SWEEP_OUT="${SWEEP_OUT}$SWEEP_SID — live, kept
"
          continue
          ;;
        *) ;;
      esac

      SWEEP_DEAD=$((SWEEP_DEAD + 1))
      SWEEP_SESSION_FILES="$(patrol_session_state_files "$REPO_REAL" "$SWEEP_SID" "$SWEEP_PER_START")"

      # THIS SESSION'S OWN NEWEST FILE, and nobody else's — the whole of the "per-session,
      # not all-or-nothing" fix, and gated on `--window` so a plain `sweep` never pays for
      # or exhibits it (see the verb's own header comment). A session dies once and its own
      # files age together, so one newest mtime among ITS files (never compared across
      # sessions) is the one fact this decision needs. Batched per session (one
      # flavour-probed `xargs stat` call for however many of the five classes this one
      # session actually left) rather than one `stat` fork per file — the exact shape that
      # made 400 dead sessions' worth of per-file forking the dominant cost T6/T16 spent
      # this wave cutting down elsewhere in this same call chain.
      if [ "$SWEEP_WINDOWED" = yes ]; then
        SWEEP_NEWEST=0
        if [ -n "$SWEEP_SESSION_FILES" ]; then
          if [ "$SWEEP_STAT_GNU" = yes ]; then
            SWEEP_SESSION_MTS="$(printf '%s\n' "$SWEEP_SESSION_FILES" | tr '\n' '\0' | xargs -0 stat -c %Y 2>/dev/null)"
          else
            SWEEP_SESSION_MTS="$(printf '%s\n' "$SWEEP_SESSION_FILES" | tr '\n' '\0' | xargs -0 stat -f %m 2>/dev/null)"
          fi
          while IFS= read -r SWEEP_MT; do
            case "$SWEEP_MT" in ''|*[!0-9]*) continue ;; esac
            [ "$SWEEP_MT" -gt "$SWEEP_NEWEST" ] && SWEEP_NEWEST="$SWEEP_MT"
          done <<EOF
$SWEEP_SESSION_MTS
EOF
        fi

        # YOUNGER THAN THE WINDOW: DEFER THIS SESSION, INDIVIDUALLY. Nothing about any
        # OTHER dead session is touched by this — the property the all-or-nothing shape did
        # not have. A session whose files could not be stat'd at all (`SWEEP_NEWEST` still
        # 0, the empty-file-list or every-stat-failed case) is treated as old enough rather
        # than perpetually deferred: an age gate exists to protect a session that JUST
        # died, not to withhold state this verb can no longer even measure.
        if [ "$SWEEP_NEWEST" -gt 0 ] && [ $(( SWEEP_NOW - SWEEP_NEWEST )) -lt "$SWEEP_WINDOW" ]; then
          SWEEP_YOUNG=$((SWEEP_YOUNG + 1))
          SWEEP_N=0
          while IFS= read -r SWEEP_F; do
            [ -n "$SWEEP_F" ] || continue
            SWEEP_N=$((SWEEP_N + 1))
          done <<EOF
$SWEEP_SESSION_FILES
EOF
          SWEEP_OUT="${SWEEP_OUT}$SWEEP_SID — dead, deferred ($SWEEP_N file(s) younger than the ${SWEEP_WINDOW}s window)
"
          continue
        fi
      fi

      SWEEP_N=0
      SWEEP_LINES=""
      while IFS= read -r SWEEP_F; do
        [ -n "$SWEEP_F" ] || continue
        SWEEP_FILES=$((SWEEP_FILES + 1))
        SWEEP_N=$((SWEEP_N + 1))
        if [ "$SWEEP_REPORT_ONLY" = yes ]; then
          # A LINK IS NAMED AS A LINK EVEN HERE, so the report of what would happen matches
          # what happens: a run that listed a symlink as a file to delete and then left it
          # would have lied about its own next invocation.
          if [ -L "$SWEEP_F" ]; then
            SWEEP_REFUSED=$((SWEEP_REFUSED + 1))
            SWEEP_LINES="${SWEEP_LINES}  refused (symlink, left alone): $SWEEP_F
"
          else
            SWEEP_LINES="${SWEEP_LINES}  $SWEEP_F
"
          fi
          continue
        fi
        # A SYMLINK IS NOT A FILE THIS SCRIPT WROTE, so it is refused rather than followed
        # and left in place rather than unlinked — the identical posture `remove_patrol_stamp`
        # takes, and for the identical reason: every reader in the fleet already treats a
        # symlinked state file as absent, so there is nothing to clear, and a hostile repo
        # must not gain a delete through a path it aimed. Everything else is queued for the
        # ONE bulk delete below, never removed here one fork at a time.
        if [ -L "$SWEEP_F" ]; then
          SWEEP_REFUSED=$((SWEEP_REFUSED + 1))
          SWEEP_LINES="${SWEEP_LINES}  refused (symlink or not a file, left alone): $SWEEP_F
"
        else
          SWEEP_BULK="${SWEEP_BULK}${SWEEP_F}
"
          SWEEP_LINES="${SWEEP_LINES}?${SWEEP_F}
"
        fi
      done <<EOF
$SWEEP_SESSION_FILES
EOF

      SWEEP_OUT="${SWEEP_OUT}$SWEEP_SID — dead, $SWEEP_N file(s)
${SWEEP_LINES}"
    done <<EOF
$(patrol_state_session_ids "$REPO_REAL")
EOF

    # THE ONE DELETE. Nothing above ever appends to `SWEEP_BULK` when `SWEEP_REPORT_ONLY=yes`
    # or when a session was deferred (both `continue` before reaching it), so report-only and
    # an all-deferred run both reach here with an empty list and this is a no-op for them.
    if [ -n "$SWEEP_BULK" ]; then
      printf '%s' "$SWEEP_BULK" | tr '\n' '\0' | xargs -0 rm -f -- 2>/dev/null
    fi

    # RESOLVE THE PLACEHOLDERS. Every `?`-prefixed line named a file that was NOT a symlink
    # at enumeration time and was just queued in the one `rm` pass above; the only question
    # left is whether that `rm` actually removed it (the ordinary case) or left it behind
    # (permissions, a concurrent writer) — decided with a plain existence check, never a
    # second `rm`. Every other line already carries its final wording and passes through as-is.
    if [ -n "$SWEEP_OUT" ]; then
      SWEEP_RESOLVED=""
      while IFS= read -r SWEEP_L; do
        case "$SWEEP_L" in
          '?'*)
            SWEEP_RF="${SWEEP_L#?}"
            if [ ! -e "$SWEEP_RF" ]; then
              SWEEP_REMOVED=$((SWEEP_REMOVED + 1))
              SWEEP_RESOLVED="${SWEEP_RESOLVED}  $SWEEP_RF
"
            else
              SWEEP_REFUSED=$((SWEEP_REFUSED + 1))
              SWEEP_RESOLVED="${SWEEP_RESOLVED}  refused (symlink or not a file, left alone): $SWEEP_RF
"
            fi
            ;;
          *)
            SWEEP_RESOLVED="${SWEEP_RESOLVED}${SWEEP_L}
"
            ;;
        esac
      done <<EOF
$SWEEP_OUT
EOF
      SWEEP_OUT="$SWEEP_RESOLVED"
    fi

    printf '%s' "$SWEEP_OUT" | while IFS= read -r SWEEP_L; do
      [ -n "$SWEEP_L" ] && say "$SWEEP_L"
    done

    # `deferred=` IS APPENDED AFTER `refused=`, never inserted between the six original
    # fields (AC-9.2's spirit extended to this line): `tests/session-sweep.test.sh` pins
    # several of them as ADJACENT substrings (`|dead=2|live=1|`, and so on), and a plain
    # `sweep` call — which never sets `SWEEP_YOUNG` above 0 — must keep emitting a byte-
    # identical line up through `refused=` for those pins to hold.
    printf '%s|at=%s|session=%s|mode=%s|scanned=%s|dead=%s|live=%s|files=%s|removed=%s|refused=%s|deferred=%s\n' \
      "$SWEEP_SCHEMA" "$(iso_now)" "${SESSION_ID:-none}" \
      "$([ "$SWEEP_REPORT_ONLY" = yes ] && printf 'report-only' || printf 'sweep')" \
      "$SWEEP_SCANNED" "$SWEEP_DEAD" "$SWEEP_KEPT" "$SWEEP_FILES" "$SWEEP_REMOVED" "$SWEEP_REFUSED" "$SWEEP_YOUNG"

    if [ "$SWEEP_SCANNED" -eq 0 ]; then
      say "nothing to sweep — no session-keyed state under $SWEEP_DIR."
      exit 0
    fi

    if [ "$SWEEP_DEAD" -eq 0 ]; then
      die "REFUSED — nothing swept: all $SWEEP_KEPT session(s) with state under $SWEEP_DIR are LIVE."
      die "A live session's state is its own to keep; this verb removes only what nobody can act on."
      exit 1
    fi

    # BOTH SUMMARY LINES NAME THE DEFERRED COUNT SEPARATELY FROM THE DEAD ONE. `SWEEP_DEAD`
    # counts every session the liveness check ruled dead, deferred ones included — the exit-1
    # refusal above depends on that (a batch that is ALL deferred is not "everything here is
    # live" and must not read as one). The dead-session count in these two prose lines is
    # `SWEEP_DEAD - SWEEP_YOUNG`, on purpose: it is the count of sessions this run actually
    # acted on (swept, or listed to be), so it still says "0" rather than a number that
    # includes sessions nothing happened to.
    if [ "$SWEEP_REPORT_ONLY" = yes ]; then
      say "report-only: $SWEEP_FILES file(s) across $((SWEEP_DEAD - SWEEP_YOUNG)) dead session(s) would be deleted — nothing was written."
      [ "$SWEEP_YOUNG" -gt 0 ] \
        && say "$SWEEP_YOUNG dead session(s) deferred — their files are younger than the ${SWEEP_WINDOW}s window."
      say "run 'sweep' to delete them."
      exit 0
    fi

    say "swept $SWEEP_REMOVED file(s) across $((SWEEP_DEAD - SWEEP_YOUNG)) dead session(s); $SWEEP_KEPT live session(s) kept."
    [ "$SWEEP_YOUNG" -gt 0 ] \
      && say "$SWEEP_YOUNG dead session(s) deferred — their files are younger than the ${SWEEP_WINDOW}s window."
    [ "$SWEEP_REFUSED" -gt 0 ] \
      && say "$SWEEP_REFUSED path(s) refused and left alone — a symlink under .bionic/tmp is never followed."
    exit 0
  }

  # ---------------------------------------------------------------- bind
  #
  # THE ACT THAT NAMES THIS SESSION'S RUN (spec AC-8; design ledger D1). Identity is
  # DECLARED, never inferred by a scan: engagement binds a session when the root holds
  # exactly one open run and writes `plan=none` when it holds several (AC-7), so a session
  # resumed into a two-run root is deliberately left unbound until it says which run is its
  # own. This verb is how it says so.
  #
  # AND IT IS THE ONLY WAY A BINDING CHANGES AFTER ENGAGEMENT, besides the governing skill's
  # bind-on-first-write (hooks/canonical-sdlc-governing-skill.sh, AC-9). D1 rejected both
  # alternatives on the record: an argument on the engage hook turns a hook into a command,
  # and a hand-edited marker abandons the one-writer invariants that make the file readable
  # at all. Nothing else in this file writes the marker.
  #
  # THE INVARIANTS ARE THE LIBRARY'S, NOT A SECOND COPY. `bind_plan`
  # (payload/scripts/lib/binding.sh) owns the two-line shape, mode 600, the symlink refusal
  # and — the one that matters here — MEMBERSHIP in `open_runs`, the same set `session_run`
  # will later rule on. This verb's own work is to say WHICH refusal happened, because
  # `bind_plan` answers 0/1/2 and an operator handed a bare "refused" cannot tell a typo
  # from a closed run.
  poker_verb_bind() {
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "A binding answers for ONE session, so without the key there is nothing to write."
      exit 3
    fi

    # THE ENGAGEMENT GUARD, above everything, for `adopt`'s reason verbatim (AC-10): nothing
    # bionic does applies until the session invoked the skill. Note that this guard also
    # answers the planted-symlink case — `engaged_session` refuses a symlink at the marker
    # path before it is followed (payload/scripts/lib/run.sh:351) — so the link's target is
    # never written through, one line before `bind_plan` would have refused it too.
    if ! engaged_session "$(project_root "$PWD")" "$SESSION_ID"; then
      say "NOT-ENGAGED — this session has not invoked /bionic:canonical-sdlc; nothing decided"
      exit 0
    fi

    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi

    # ABSOLUTE, BECAUSE THE MARKER IS READ FROM EVERY CWD IN THE FLEET. A relative operand is
    # taken against the PROJECT ROOT rather than `$PWD`: the plan path an operator has to
    # hand is the one their editor shows, which is project-relative, and a worktree cwd would
    # otherwise resolve it against a tree that does not hold the run.
    #
    # AND AGAINST THE DOCS ROOT WHEN THAT MISSES (S10b phase 2). hooks/session-start.sh
    # prints the open-run listing DOCS-root-relative — `plans/<epic>/<wave>.md` — because
    # every absolute path in that listing shares one long prefix. An operator who copies a
    # listed line straight into this verb was handing over a project-relative path that does
    # not exist, and getting a refusal that reads as if the PLAN were wrong rather than the
    # spelling. Both spellings now bind.
    #
    # THE PROJECT ROOT IS TRIED FIRST AND WINS TIES, so every operand that resolved before
    # resolves to exactly the same file now: the docs root is reached only when the
    # project-relative spelling is not a regular file, which is the case that used to refuse.
    # A miss under both leaves `BIND_PATH` at the project-root spelling, so the refusal names
    # the path an operator typing a repo path would expect to see.
    # A TRAILING SLASH IS NOT A DIFFERENT PLAN (S8). Shell completion on a path an operator
    # is still typing leaves one behind, and `[ -f "<file>/" ]` is FALSE — so the docs-root
    # fallback below used to miss on the one spelling and hit on the other, and the two
    # operands that name one file bound to two different things. The canonicalizer strips it
    # anyway (`dirname`/`basename`); stripping it here is what lets both spellings reach the
    # same probe. `/` keeps its slash: it is the path, not a decoration on one.
    BIND_ARG_P="$BIND_ARG"
    while [ ${#BIND_ARG_P} -gt 1 ]; do
      case "$BIND_ARG_P" in */) BIND_ARG_P="${BIND_ARG_P%/}" ;; *) break ;; esac
    done
    case "$BIND_ARG_P" in
      /*) BIND_PATH="$BIND_ARG_P" ;;
      *)
        BIND_PATH="$REPO/$BIND_ARG_P"
        if [ ! -f "$BIND_PATH" ]; then
          BIND_DOCS_TRY="$(docs_root "$REPO")/$BIND_ARG_P"
          [ -f "$BIND_DOCS_TRY" ] && BIND_PATH="$BIND_DOCS_TRY"
        fi ;;
    esac

    BIND_RC=0
    bind_plan "$REPO_REAL" "$SESSION_ID" "$BIND_PATH" bind || BIND_RC=$?
    if [ "$BIND_RC" -eq 0 ]; then
      say "bound $BIND_PATH"
      # A DELIVERED RUN (wave-36 T14; ruling r1791955629-34788): bound, and read bound-closed, so every verb keeps
      # its closed-run refusal but task-set --reason.
      [ "${BIND_DELIVERED:-}" != yes ] \
        || say "$BIND_PATH is delivered: this session reads it bound-closed, and only task-set … --reason '<why>' writes it"
      # THE RUN'S SESSIONS (wave-36 T9; D10): `bind_plan` writes this session's `- session:` line
      # into the plan beside the marker, `by bind`; a plan that could not take it is said, not hidden.
      case "${BIND_SESSION:-}" in
        recorded) say "session $SESSION_ID recorded under ## SDLC State of $BIND_PATH" ;;
        failed) die "the session line could not be written into $BIND_PATH (the plan changed, or is not a regular file); bind again to write it" ;;
      esac
      exit 0
    else
      if [ "$BIND_RC" -ge 2 ]; then
        die "REFUSED — marker write failed"
        die "The binding was valid; the marker could not be written. Check that"
        die "$REPO_REAL/.bionic/tmp is a writable real directory."
        exit 2
      fi
      # WHICH REFUSAL, decided POSITIONALLY. `bind_plan` returns one code for every invalid
      # binding, so the reason is re-derived here from where the path is: a regular file in a
      # plan directory of this root is a plan that is not OPEN (delivered, abandoned, or
      # carrying no readable `## SDLC State`), and anything else is not a plan of this root
      # at all. The marker-symlink case is listed for completeness — the guard above answers
      # it first — so that every 1 from the library leaves this verb with something to say.
      BIND_MARKER="$(engaged_marker_path "$REPO_REAL" "$SESSION_ID")" || BIND_MARKER=""
      BIND_DOCS="$(docs_root "$REPO_REAL")"
      # THE SAME CANONICALIZER `bind_plan` JUST USED (AC-23). This arm carried its own copy
      # of the resolve-the-directory rule and degraded to an EMPTY `BIND_REAL` when the
      # directory would not resolve — which then fell through the location `case` below and
      # was reported as "not a plan under this root", a sentence about the wrong thing: the
      # path may well be under this root, it is the directory above it that is missing.
      # `BIND_PATH` is absolute by construction above, which is what `_bind_resolve` requires.
      BIND_REAL=""
      BIND_RESOLVED=yes
      BIND_REAL="$(_bind_resolve "$BIND_PATH")" || { BIND_REAL=""; BIND_RESOLVED=no; }
      if [ -n "$BIND_MARKER" ] && [ -L "$BIND_MARKER" ]; then
        BIND_WHY="marker is a symlink"
      elif [ "$BIND_RESOLVED" = no ]; then
        BIND_WHY="its directory does not resolve"
      else
        # THE SAME DEPTH BOUND THE SET IS BUILT WITH (review D8c, S10b). `open_runs` walks
        # `find <plans|incidents> -maxdepth 2`, so `plans/<a>/<b>/x.md` is not a candidate
        # at all. A `case` glob matches across `/`, so the location test used to call that
        # file a plan of this root and blame its CONTENT ("not an open run") for a miss the
        # walk decided before ever opening it. `BIND_TAIL` is the path below `plans/` or
        # `incidents/`: no slash is depth 1, one slash is depth 2, two or more is outside.
        BIND_TAIL=""
        case "$BIND_REAL" in
          "$BIND_DOCS"/plans/*|"$BIND_DOCS"/incidents/*)
            BIND_TAIL="${BIND_REAL#"$BIND_DOCS"/}"
            BIND_TAIL="${BIND_TAIL#*/}" ;;
        esac
        case "$BIND_TAIL" in
          ''|*/*/*)
            # Outside the walk: not under a plan directory of this root, or nested deeper
            # than the walk reaches.
            BIND_WHY="not a plan under this root" ;;
          *)
            if [ -f "$BIND_PATH" ]; then
              BIND_WHY="not an open run"
            else
              BIND_WHY="not a plan under this root"
            fi ;;
        esac
      fi
      die "REFUSED — $BIND_WHY: $BIND_PATH"
      die "A binding names a member of this root's OPEN-RUN SET — a plan under"
      die "$BIND_DOCS/{plans,incidents} whose run is still open. This session's binding is unchanged."
      exit 1
    fi
  }

  # THE RE-OPEN (T-h; D11; REQ-10). `verdict_row` (hooks/session-sweeper.sh) reads a name's
  # LAST roster row alone, and nothing else — `waiver=`, `deliverable=`, `launched_at=`, the
  # `claims=`/`progress=`/`cadence=` triple. `standdown-declined:` is written as a `hold`
  # (wave-26 T15), which keeps the launch; `ack` closes a row rather than opening one. Neither
  # re-opens a MET
  # lineage, so this verb is a plain append: a fresh row for the same name, launched NOW,
  # with the operator's reason recorded as `extended=<iso> <reason>`. It used to ride
  # `claims=`, the process pattern the sweeper hands to `pgrep -f`, so a reason carrying
  # `.*` held the row STILL-LIVE on any process at all (wave-20 T9, AC-4.4); `claims=` is
  # now copied from the row, like every field but the launch. The already-written deliverable then
  # dates before the new launch instant — `landing_conjunct` returns its `stale=` conjunct —
  # the verdict leaves MET for STILL-LIVE or UNMET, and the name drops off
  # `STANDDOWN_NAMES` and rejoins `OPEN`: the truthful accounting, the agent is still
  # working. The roster is APPEND-ONLY (same invariant `adopt_write_row` keeps at :1799,
  # above) — this never rewrites the row it found, only adds one after it — and `adopt_fold`
  # folds by KEY, last non-empty value per field per name, so the bumped `launched_at=` (and
  # the unmoved `deliverable=`) are exactly what a later `adopt` rebuilds from (AC-10.2).
  poker_verb_extend() {
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "An extension answers for ONE session's roster, so without the key there is nothing to write."
      exit 3
    fi

    # THE ENGAGEMENT GUARD (AC-10), same reason and the same shape `bind` and `adopt` take
    # above: nothing bionic does applies until the session invoked the skill.
    if ! engaged_session "$(project_root "$PWD")" "$SESSION_ID"; then
      say "NOT-ENGAGED — this session has not invoked /bionic:canonical-sdlc; nothing decided"
      exit 0
    fi

    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    ROSTER_FILE="$REPO_REAL/.bionic/tmp/roster-${SESSION_ID}.state"
    if [ ! -f "$ROSTER_FILE" ] || [ -L "$ROSTER_FILE" ]; then
      die "REFUSED — no row named $EXTEND_NAME: this session has no roster at $ROSTER_FILE."
      exit 1
    fi

    # THE LAST ROW CARRYING THIS NAME IS ITS LATEST CONTRACT — the same by-name reading
    # every other reader in this file takes (e.g. the duration arm inside `tick`, below).
    # Any `roster-state/` row, the prefix `identity_args` reads, so the copy and the id stamp
    # come from one row under a schema bump (wave-22 T13; critic-3598752 I4).
    EXTEND_ROW="$(grep '^roster-state/' "$ROSTER_FILE" 2>/dev/null \
      | grep -F "|name=${EXTEND_NAME}|" | tail -1)"
    if [ -z "$EXTEND_ROW" ]; then
      die "REFUSED — no row named $EXTEND_NAME on this session's roster ($ROSTER_FILE)."
      exit 1
    fi

    EXTEND_NOW="$(iso_now)"
    # THE COPY IS `row_copy_args`'s, shared with `amend`; this verb overrides two fields: the
    # launch, bumped to now (the whole point — the old deliverable then predates it), and
    # its reason, as data. `claims=` travels with the copy, untouched.
    row_copy_args "$EXTEND_ROW" "$SESSION_ID" drop-done
    identity_args "$ROSTER_FILE" "$EXTEND_NAME" "$EXTEND_ROW"
    EXTEND_RR_ARGS=("${ROW_COPY_ARGS[@]}")
    EXTEND_RR_ARGS+=(${POKER_ID_ARGS[@]+"${POKER_ID_ARGS[@]}"})
    EXTEND_RR_ARGS+=("launched_at=$EXTEND_NOW" "extended=$EXTEND_NOW $(clean "$EXTEND_REASON")")

    EXTEND_NEW_ROW="$(roster_row "${EXTEND_RR_ARGS[@]}")" || EXTEND_NEW_ROW=""
    if [ -z "$EXTEND_NEW_ROW" ]; then
      die "REFUSED — could not build the extended row for $EXTEND_NAME."
      exit 2
    fi
    printf '%s\n' "$EXTEND_NEW_ROW" >> "$ROSTER_FILE" 2>/dev/null || {
      die "REFUSED — could not write to $ROSTER_FILE."
      exit 2
    }
    say "extended — $EXTEND_NAME is open again: $ROSTER_FILE"
    exit 0
  }

  # THE STANDING ANSWER TO A STAND-DOWN (wave-24 T7; REQ-4, AC-4.3; spec D1, ADR-041 d1). A
  # finished agent kept up on purpose — an auditor held for a second pass — was ordered down
  # on every tick, because the only answer the stop wall read was a `standdown-declined:` line
  # in that one turn's text. `hold` writes the answer where the tick reads its facts: a
  # successor row of the name, copied as `extend` and `amend` copy it, carrying `held=<at>
  # <reason> fp=<fingerprint>`. While the fingerprint is unchanged the tick prints `held <name>`
  # and writes no stop order, so the stop wall's stand-down set — computed from orders — has
  # nothing to ask. Any change voids it without a write: a new launch, a rewritten deliverable,
  # a new completion message. The row's launch is the copy's, so the row stays MET; unlike
  # `extend`, nothing re-opens.
  #
  # REFUSED: no session key (3), an unengaged session (decides nothing, 0), no row of the name,
  # a row that is not MET or is already closed (1). A subagent cannot reach this verb: the Bash
  # wall refuses it with `amend`, `extend` and `task-add` (payload/scripts/lib/walls.sh).
  poker_verb_hold() {
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "A hold answers for ONE session's roster, so without the key there is nothing to write."
      exit 3
    fi
    if ! engaged_session "$(project_root "$PWD")" "$SESSION_ID"; then
      say "NOT-ENGAGED — this session has not invoked /bionic:canonical-sdlc; nothing decided"
      exit 0
    fi
    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    ROSTER_FILE="$REPO_REAL/.bionic/tmp/roster-${SESSION_ID}.state"
    if [ ! -f "$ROSTER_FILE" ] || [ -L "$ROSTER_FILE" ]; then
      die "REFUSED — no row named $HOLD_NAME: this session has no roster at $ROSTER_FILE."
      exit 1
    fi
    HOLD_ROW="$(grep '^roster-state/' "$ROSTER_FILE" 2>/dev/null \
      | grep -F "|name=${HOLD_NAME}|" | tail -1)"
    if [ -z "$HOLD_ROW" ]; then
      die "REFUSED — no row named $HOLD_NAME on this session's roster ($ROSTER_FILE)."
      exit 1
    fi
    # THE VERDICT IS THE SWEEPER'S, read as the tick reads it. A hold answers a stand-down, and
    # only a MET, unacked row is ever stood down.
    SWEEPER="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/session-sweeper.sh"
    HOLD_VERDICT="$( cd "$REPO_REAL" 2>/dev/null && CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
      bash "$SWEEPER" verdict "$HOLD_NAME" 2>/dev/null | grep -F "landing-verdict/v1|" | tail -1 )"
    HOLD_STATE="$(line_field "$HOLD_VERDICT" state)"
    if [ "$HOLD_STATE" != MET ] || [ "$(line_field "$HOLD_VERDICT" acked)" = yes ]; then
      die "REFUSED — $HOLD_NAME reads ${HOLD_STATE:-no verdict}$( [ "$(line_field "$HOLD_VERDICT" acked)" = yes ] && printf ', closed'); a hold answers a stand-down, and only a MET, open row is stood down."
      exit 1
    fi
    HOLD_TR="$(session_transcript "$SESSION_ID")" || HOLD_TR=""
    HOLD_FP="$(hold_fingerprint "$HOLD_ROW" "$REPO_REAL" "$HOLD_TR")"
    HOLD_NOW="$(iso_now)"
    row_copy_args "$HOLD_ROW" "$SESSION_ID"
    identity_args "$ROSTER_FILE" "$HOLD_NAME" "$HOLD_ROW"
    HOLD_RR_ARGS=("${ROW_COPY_ARGS[@]}")
    HOLD_RR_ARGS+=(${POKER_ID_ARGS[@]+"${POKER_ID_ARGS[@]}"})
    HOLD_RR_ARGS+=("held=$HOLD_NOW $(clean "$HOLD_REASON") fp=$HOLD_FP")
    HOLD_NEW_ROW="$(roster_row "${HOLD_RR_ARGS[@]}")" || HOLD_NEW_ROW=""
    if [ -z "$HOLD_NEW_ROW" ]; then
      die "REFUSED — could not build the held row for $HOLD_NAME."
      exit 2
    fi
    printf '%s\n' "$HOLD_NEW_ROW" >> "$ROSTER_FILE" 2>/dev/null || {
      die "REFUSED — could not write to $ROSTER_FILE."
      exit 2
    }
    say "held — $HOLD_NAME stays up while its launch, deliverable and messages are unchanged (fp=$HOLD_FP); the tick prints it held and orders no stop: $ROSTER_FILE"
    exit 0
  }

  # A RULING FOR A LIVE WRITER (wave-33 T10; REQ-1 AC-1.1 to AC-1.4, D1). The orchestrator's binding
  # instruction to one writer while it works: a `ruling/v1` line on this session's roster (lib/roster.sh
  # `ruling_record`, which owns the state and its one reader). hooks/ruling-push.sh carries it on the
  # writer's next tool result; the writer's commit and `ready` refuse while it is unread. `rulings` reads
  # the state; `ruling-ack` is the writer's own acknowledgement, from its tree (the session key is the
  # orchestrator's in a teammate's shell, so it finds the same roster).
  #
  # REFUSED, exit 2, with the reason (AC-1.3): a name no row of this roster carries, or a row that is
  # closed (`roster_open_names`, the one reader of "is this name closed": ended, or acked after its
  # launch). A ruling for either would never be shown, so it is never written. No session key is 3,
  # as everywhere in this file.
  poker_verb_rule() {
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "A ruling lives on ONE session's roster, so without the key there is nothing to read or write."
      exit 3
    fi
    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    ROSTER_FILE="$REPO_REAL/.bionic/tmp/roster-${SESSION_ID}.state"
    if [ ! -f "$ROSTER_FILE" ] || [ -L "$ROSTER_FILE" ]; then
      die "REFUSED — this session has no roster at $ROSTER_FILE, so it has no writer to rule for."
      exit 2
    fi
    case "$VERB" in
      rule)
        if ! grep '^roster-state/' "$ROSTER_FILE" 2>/dev/null | grep -qF "|name=${RULE_WRITER}|"; then
          die "REFUSED — no row named $RULE_WRITER on this session's roster ($ROSTER_FILE); a ruling names one live writer."
          exit 2
        fi
        if ! roster_open_names "$ROSTER_FILE" "$(roster_ack_ledger "$ROSTER_FILE")" | grep -qxF "$RULE_WRITER"; then
          die "REFUSED — $RULE_WRITER's row is closed (ended, or acked after its launch): a ruling for it would never be shown. Nothing written."
          exit 2
        fi
        if [ -n "$RULE_WORDS" ]; then
          # THE USER'S WORDS, AS finding-move HOLDS THEM (wave-36 T9; D10): looked for in every session the
          # bound plan records, then this one; refused in said_refuse's voice, exit 2 as this arm refuses.
          if ! declare -F user_said >/dev/null 2>&1 && [ -f "$BIONIC_LIB/said.sh" ]; then
            . "$BIONIC_LIB/said.sh"
          fi
          if ! declare -F user_said >/dev/null 2>&1; then
            die "REFUSED — what the user typed is read by lib/said.sh, which cannot be loaded from $BIONIC_LIB; nothing written."
            exit 2
          fi
          RULE_PLAN="$(session_plan "$REPO_REAL" "$SESSION_ID" 2>/dev/null)" || RULE_PLAN=""
          user_said "$RULE_WORDS" "$RULE_PLAN"; RULE_SAID=$?
          if [ "$RULE_SAID" -ne 0 ]; then
            said_refuse "$RULE_SAID" "$(said_fold "$RULE_WORDS")" "a ruling's quote"
            exit 2
          fi
          RULE_TEXT="$RULE_TEXT words=\"$(said_fold "$RULE_WORDS" | tr '"' "'")\" session=$SAID_SESSION"
        fi
        RULE_ID="$(ruling_record "$ROSTER_FILE" "$RULE_WRITER" "$RULE_TEXT")" || RULE_ID=""
        if [ -z "$RULE_ID" ]; then
          die "REFUSED — could not write the ruling to $ROSTER_FILE."
          exit 2
        fi
        say "ruling $RULE_ID recorded for $RULE_WRITER — its next tool result carries it, and its commit and ready are refused until it is shown; read it with: rulings $RULE_WRITER"
        exit 0 ;;
      ruling-ack)
        RA_LINE="$(ruling_fold "$ROSTER_FILE" | awk -F"$RULING_US" -v id="$RULING_ID" '$1 == id { print; exit }')"
        if [ -z "$RA_LINE" ]; then
          die "REFUSED — no ruling $RULING_ID on this session's roster ($ROSTER_FILE)."
          exit 2
        fi
        IFS="$RULING_US" read -r RA_ID RA_W RA_REC RA_P RA_C RA_S RA_B RA_T <<< "$RA_LINE"
        if [ -n "$RA_S" ]; then
          say "ruling $RA_ID was already shown to $RA_W (shown=$RA_S by=${RA_B:-?}); nothing to do"
          exit 0
        fi
        RA_NOW="$(date +%s)"
        ruling_stamp "$ROSTER_FILE" "$RA_ID" "$RA_W" "shown=$RA_NOW" "by=ack" || {
          die "REFUSED — could not write to $ROSTER_FILE."
          exit 2
        }
        say "ruling $RA_ID acknowledged — shown=$RA_NOW; your commit and ready no longer wait on it"
        exit 0 ;;
      rulings)
        RS_ANY=no
        while IFS="$RULING_US" read -r RS_ID RS_W RS_REC RS_P RS_C RS_S RS_B RS_T; do
          [ -n "$RS_ID" ] || continue
          RS_ANY=yes
          RS_STATE="unread"
          [ -z "$RS_S" ] || RS_STATE="shown=$RS_S by=${RS_B:-?}"
          say "ruling $RS_ID $RS_W recorded=$RS_REC${RS_P:+ pushed=$RS_P} $RS_STATE — $RS_T"
        done <<< "$(ruling_fold "$ROSTER_FILE" "$RULE_WRITER")"
        [ "$RS_ANY" = yes ] || say "no ruling for $RULE_WRITER on this session's roster"
        exit 0 ;;
    esac
  }

  # THE LAUNCH SYNC (wave-26 T32; D4). Its reasoning is above the verbs, beside the functions it
  # runs. Silent, exit 0, wherever there is nothing it may write: no engagement, no bound open run,
  # a plan before Step 4 (`current:` a step below 4, or none), no roster, or a lock another writer
  # holds when the caller does not wait. What it cannot write prints, and the exit says whether a
  # retry repairs it (wave-26 T51; review 13 F6): 75 when another writer replaced the plan while
  # this one judged its copy, which the next caller repairs by running again, and when the lock's
  # mkdir keeps failing with no lock there (T54; review 17 N1), said in one line; 1 for every refusal
  # no retry repairs (a launch the plan cannot take, the validator or the commit gate refusing the
  # batch, a lock that cannot be made); 2 when the dry commit cannot run at all.
  poker_verb_launch_sync() {
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "launch-sync applies ONE session's launches, so without the key there is nothing to read."
      exit 3
    fi
    LS_ROOT="$(cd "$(project_root "$PWD")" 2>/dev/null && pwd -P)" || LS_ROOT=""
    [ -n "$LS_ROOT" ] || exit 0
    engaged_session "$LS_ROOT" "$SESSION_ID" || exit 0
    LS_RUN="$(session_run "$LS_ROOT" "$SESSION_ID" 2>/dev/null)" || LS_RUN=""
    case "$LS_RUN" in 'bound-open '*) LS_PLAN="${LS_RUN#bound-open }" ;; *) exit 0 ;; esac
    # ONE LEDGER SHAPE (wave-31 T5; REQ-1 AC-1.2, D2): `current:` is a step number at every scale.
    # A value that is not one — the retired task-scale `T<n>` above all — is refused aloud, exit 1,
    # never skipped: the turn-end wall passes 0 and 75 only, so the plan's author is told. It is read
    # BEFORE the roster (wave-31 T43; A-orch-76), so a session with no confirmed launch is told too.
    LS_RAW="$(_fill_current_field "$LS_PLAN")"; LS_CUR="${LS_RAW%[ab]}"
    case "$LS_CUR" in
      '') exit 0 ;;
      *[!0-9]*)
        printf 'NOT-RECORDED — current: %s is not numeric; a plan in the retired task-scale shape is refused, not skipped\n' \
          "$(printf '%s' "$LS_RAW" | tr -d '[:cntrl:]')" >&2
        exit 1 ;;
    esac
    # A session that has confirmed no launch, or a plan before Step 4, has no launch to apply; a handoff
    # a later dispatch outdates is marked all the same, at any step (`handoff_mark_stale`, T29).
    LS_ROSTER="$LS_ROOT/.bionic/tmp/roster-${SESSION_ID}.state"
    LS_LAUNCH=yes
    [ "$LS_CUR" -ge 4 ] || LS_LAUNCH=no
    { [ -f "$LS_ROSTER" ] && [ ! -L "$LS_ROSTER" ] \
        && grep -qE '\|status=(confirmed|identified)\|' "$LS_ROSTER" 2>/dev/null; } || LS_LAUNCH=no
    if [ "$LS_LAUNCH" = no ]; then
      LS_AT="$(handoff_written_at "$LS_PLAN")"
      [ -n "$LS_AT" ] && [ -n "$(handoff_dispatches_since "$LS_PLAN" "$LS_ROOT/.bionic/tmp" "$LS_AT")" ] || exit 0
    fi
    tmp_dir_ok "$LS_ROOT/.bionic/tmp" || exit 0
    # A LOCK THAT CANNOT BE MADE IS NOT A LOCK ANOTHER WRITER HOLDS (wave-26 T51; review 13 F1):
    # held, the holder writes the launches and this call says nothing; not makeable, no caller
    # can write them until the directory can be written, so it is said, exit 1, as a refusal.
    LS_LOCK_RC=0
    launch_sync_lock "$LS_ROOT/.bionic/tmp/launch-sync.lock" "$LS_WAIT" || LS_LOCK_RC=$?
    case "$LS_LOCK_RC" in
      0) : ;;
      2)
        die "REFUSED — the launch-sync lock $LS_ROOT/.bionic/tmp/launch-sync.lock cannot be made: its directory is missing or not writable. Nothing was written; no launch of this session is recorded in the plan until it can be."
        exit 1 ;;
      3)
        die "launch-sync — the lock $LS_ROOT/.bionic/tmp/launch-sync.lock could not be made although its directory can be written (a full disk or a quota?). No launch was applied by this call; the next tick applies them once it can be."
        exit 75 ;;
      *) exit 0 ;;
    esac
    trap 'launch_sync_unlock' EXIT
    plan_verb_open launch-sync
    # THE CHECKSUM AGAIN, NOW THE LOCK IS HELD: plan_verb_open took it before this run owned the
    # plan, and a writer that finished in between is not a change this transaction has to refuse.
    PV_SUM="$(cksum < "$PV_PLAN" 2>/dev/null)"
    LS_SWAPPED=no
    launch_sync_exit() {
      local rc=$?
      rm -f "$PV_NEW" "$PV_NEW.2" "$PV_NEW.l" "$PV_NEW.r" "$PV_NEW.ledger" "$PV_DRY" ${PV_MARK:+"$PV_MARK"} 2>/dev/null
      if [ "$rc" -ne 0 ] && [ "$LS_SWAPPED" = no ] && [ -n "${LS_HANDS:-}" ]; then
        die "launch-sync: nothing was written. Fix what refused it, then run these by hand (or let the next tick retry):"
        printf '%s' "$LS_HANDS" >&2
      fi
      launch_sync_unlock
    }
    trap launch_sync_exit EXIT
    launch_sync_sweep "$PV_PLAN" "$PV_REPO"
    LS_RC=0
    LS_PROJECTED=no; LS_SAID=""; LS_FAILS=""; LS_HANDS=""
    if [ "$LS_LAUNCH" = yes ] && launch_sync_project "$PV_PLAN" "$PV_REPO" "$SESSION_ID" "$LS_ROSTER" \
      "$PV_REPO/.bionic/tmp/sweeper-${SESSION_ID}.state" "$PV_NEW"; then
      LS_PROJECTED=yes
    fi
    # WHAT CANNOT BE RECORDED PRINTS FIRST, so a refusal of the rest below cannot hide it.
    if [ -n "$LS_FAILS" ]; then
      printf '%s' "$LS_FAILS" | sed 's/^NOT-RECORDED /poker: NOT-RECORDED /'
      LS_RC=1
    fi
    # THE HANDOFF A LATER DISPATCH OUTDATES (T29), marked in the same write as the launches, or alone.
    LS_MARKED=no; LS_SRC="$PV_PLAN"; [ "$LS_PROJECTED" = yes ] && LS_SRC="$PV_NEW"
    if handoff_mark_stale "$PV_PLAN" "$LS_SRC" "$PV_REPO/.bionic/tmp" "$PV_NEW.2"; then
      mv -f "$PV_NEW.2" "$PV_NEW" && LS_MARKED=yes
    fi
    rm -f "$PV_NEW.2"
    # A plan whose ## Handoff is the pointer (wave-38 T12; D23): its FILE's safe line is marked, the plan untouched.
    LS_HF="$(handoff_pointer_of "$PV_PLAN")"; LS_FMARKED=no
    if [ -n "$LS_HF" ] && handoff_file_mark_stale "$PV_PLAN" "$LS_HF" "$PV_REPO/.bionic/tmp"; then
      LS_FMARKED=yes
      say "HANDOFF-STALE — ${LS_HF#"$PV_REPO"/} now reads stale: a dispatch of this plan postdates it; rewrite it: bash ${HOOK_DIR}/session-poker.sh handoff"
    fi
    if [ "$LS_PROJECTED" = yes ]; then
      LS_VIOL="$(units_validate "$PV_NEW" 2>&1)"
      if [ -n "$LS_VIOL" ]; then
        die "REFUSED — with these launches recorded, the ## Tasks table breaks the Task invariants; the plan is unchanged:"
        printf '%s\n' "$LS_VIOL" >&2
        exit 1
      fi
    fi
    if [ "$LS_PROJECTED" = yes ] || [ "$LS_MARKED" = yes ]; then
      [ "$LS_RC" = 0 ] && PV_RACE_RC=75   # a launch it could not record keeps exit 1
      LS_WHAT="$(printf '%s' "$LS_SAID" | awk '{ printf "%s%s", (NR > 1 ? ", " : ""), $2 }')"
      LS_WHAT="${LS_WHAT:+$LS_WHAT recorded}"
      [ "$LS_MARKED" = no ] || LS_WHAT="${LS_WHAT:+$LS_WHAT, }the handoff marked stale"
      plan_verb_swap launch-sync "$LS_WHAT" writer
      LS_SWAPPED=yes
      printf '%s' "$LS_SAID" | sed 's/^/poker: /'
      [ "$LS_MARKED" = no ] || say "HANDOFF-STALE — ## Handoff now reads stale: a dispatch of this plan postdates it; rewrite it: bash ${HOOK_DIR}/session-poker.sh handoff"
    fi
    exit "$LS_RC"
  }

  # ---------- wait: THE RE-ENTRANT WAIT ON A DETACHED RUN (wave-30 T12; D6; AC-3.2, AC-3.3, AC-3.8) ----------
  #
  # The attach half of `booked.sh --detach`, by name, for a caller that is gone (a /clear, a stopped
  # agent, a call the harness moved to the background). It reads the run's record and never starts
  # anything, so two waits on one run are one run. It polls every BIONIC_RUN_POLL seconds (1 unless
  # set), never one long call, and prints a RUNNING line with the run's last progress line on the
  # first poll, whenever that line changes, and at least every 30 seconds. It exits with the run's
  # code once the run has one; 70 when the run is LOST (its pid gone, no end written: a kill, never a
  # timeout); 75 when `--for` ran out first, the run untouched. No session key is needed. A run that
  # ended 75 (the gate did not admit it inside its bound) is reported with the shim's one line first.
  poker_verb_wait() {
    REPO_REAL="$(cd "$(project_root "$PWD")" 2>/dev/null && pwd -P)"
    [ -n "$REPO_REAL" ] || { die "REFUSED — cannot resolve the working directory."; exit 2; }
    if ! run_find "$REPO_REAL" "$WT_ARG"; then
      die "wait — no run named $WT_ARG: no roster row of this project carries a run for it, and there is no $REPO_REAL/.bionic/tmp/runs/$WT_ARG.log"
      exit 2
    fi
    WT_POLL="${BIONIC_RUN_POLL:-1}"
    case "$WT_POLL" in ''|*[!0-9.]*|.|*.*.*) WT_POLL=1 ;; esac
    WT_T0="$(now_epoch)"; WT_SAID=""; WT_SAID_AT=0
    while :; do
      run_read
      case "$RUN_STATE" in
        FINISHED)
          # A run the gate did not admit inside its bound ends 75 with the shim's one line in its log
          # (booked.sh, the detached side's ceiling; wave-31 T12, D10): the wait says what it waited
          # for and the command to run again, before the FINISHED line, whose text is unchanged.
          if [ "$RUN_RC" = 75 ]; then
            WT_NOTE="$(grep '^booked: the gate did not admit' "$RUN_LOG" 2>/dev/null | tail -n 1)"
            [ -z "$WT_NOTE" ] || say "$WT_NOTE"
          fi
          say "FINISHED $RUN_NAME run=$RUN_ID rc=$RUN_RC log=$RUN_LOG"; exit "$RUN_RC" ;;
        LOST)     say "LOST $RUN_NAME run=$RUN_ID last-written=$RUN_LAST_WRITTEN — its pid is gone and it wrote no end; log $RUN_LOG"; exit 70 ;;
      esac
      WT_NOW="$(now_epoch)"
      if [ "$WT_SAID_AT" = 0 ] || [ "$RUN_PROGRESS" != "$WT_SAID" ] || [ $((WT_NOW - WT_SAID_AT)) -ge 30 ]; then
        say "RUNNING $RUN_NAME run=$RUN_ID pid=$RUN_PID elapsed=${RUN_ELAPSED:-?}s progress: ${RUN_PROGRESS:-none yet}"
        WT_SAID="$RUN_PROGRESS"; WT_SAID_AT="$WT_NOW"
      fi
      if [ -n "$WT_FOR" ] && [ $((WT_NOW - WT_T0)) -ge "$WT_FOR" ]; then
        say "still RUNNING after ${WT_FOR}s — the run goes on; wait again: bash ${POKER_WORD} wait $RUN_NAME"
        exit 75
      fi
      sleep "$WT_POLL"
    done
  }

  # ---------- stop-run: STOPPING A DETACHED RUN ON PURPOSE (wave-30 T12; D6) ----------
  #
  # A detached run is in nobody's process group, so TaskStop and a killed caller cannot reach it; this
  # verb can. It sends TERM to the run's group (the shim's own traps then stop its command, end its
  # place at the gate, stamp and write its end), waits up to five seconds, and KILLs every process
  # group at or below the run's pid that is still there. When the run wrote no end (a KILL runs no
  # trap) it records one: `rc=137` on the log, `<log>.rc`, and the roster row's `run_rc=` through
  # `roster_mark_run`, so the run reads FINISHED rc=137, a stop, and not LOST. A run already ended or
  # LOST is reported and left alone. `--report-only` sends nothing.
  poker_verb_stop_run() {
    REPO_REAL="$(cd "$(project_root "$PWD")" 2>/dev/null && pwd -P)"
    [ -n "$REPO_REAL" ] || { die "REFUSED — cannot resolve the working directory."; exit 2; }
    SR_FOUND=no
    if run_find "$REPO_REAL" "$SR_ARG"; then run_read; SR_FOUND=yes; fi
    # A GATE REQUEST, when the operand names no detached run that still runs (wave-36 T11; D8): a request id,
    # or the name of a holder parked in `gate_ask` or running under an admission.
    if [ "$SR_FOUND" = no ] || [ "$RUN_STATE" != RUNNING ]; then
      stop_run_request "$SR_ARG"; _sr_rc=$?
      if [ "$_sr_rc" -eq 2 ]; then
        die "stop-run — $SR_ARG holds more than one open gate request ($SR_REQS); name the one to stop by its id"
        exit 2
      fi
      if [ "$_sr_rc" -eq 0 ]; then stop_run_gate "$SR_REQ"; exit $?; fi
    fi
    if [ "$SR_FOUND" = no ]; then
      die "stop-run — no run named $SR_ARG: no roster row of this project carries a run for it, there is no $REPO_REAL/.bionic/tmp/runs/$SR_ARG.log, and no gate request is $SR_ARG or held by it"
      exit 2
    fi
    case "$RUN_STATE" in
      FINISHED) say "stop-run $RUN_NAME run=$RUN_ID — FINISHED rc=$RUN_RC; nothing to stop"; exit 0 ;;
      LOST)     say "stop-run $RUN_NAME run=$RUN_ID — LOST last-written=$RUN_LAST_WRITTEN; no process of it is left to stop"; exit 0 ;;
    esac
    if [ "$SR_REPORT_ONLY" = yes ]; then
      say "stop-run $RUN_NAME run=$RUN_ID pid=$RUN_PID — RUNNING; would TERM its process group, then KILL every group below it still alive after 5 s (report-only: nothing was sent)"
      exit 0
    fi
    # NEVER THIS CALL'S OWN GROUP: whoever runs the verb (a test, close-out, the operator's shell) is
    # not the run, whatever a pid table says about who started whom.
    SR_SELF="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')"
    SR_GROUPS="$(run_groups "$RUN_PID")"
    kill -TERM -- "-$RUN_PID" 2>/dev/null || kill -TERM "$RUN_PID" 2>/dev/null
    _sr_i=0
    while [ "$_sr_i" -lt 50 ] && run_live "$RUN_PID" "$RUN_LOG"; do sleep 0.1; _sr_i=$((_sr_i + 1)); done
    SR_HOW="TERM"
    if run_live "$RUN_PID" "$RUN_LOG"; then
      SR_GROUPS="$SR_GROUPS
$(run_groups "$RUN_PID")"
      for _sr_g in $(printf '%s\n' "$SR_GROUPS" | sort -u); do
        case "$_sr_g" in ''|0|1|*[!0-9]*) continue ;; esac
        [ "$_sr_g" != "$SR_SELF" ] || continue
        kill -KILL -- "-$_sr_g" 2>/dev/null
      done
      kill -KILL "$RUN_PID" 2>/dev/null
      SR_HOW="TERM, then KILL"
    fi
    _sr_i=0
    while [ "$_sr_i" -lt 30 ] && [ ! -s "$RUN_LOG.rc" ]; do sleep 0.1; _sr_i=$((_sr_i + 1)); done
    SR_RC=""; { read -r SR_RC < "$RUN_LOG.rc"; } 2>/dev/null
    case "$SR_RC" in
      ''|*[!0-9]*)
        [ -z "$(tail -c 1 "$RUN_LOG" 2>/dev/null)" ] || printf '\n' >> "$RUN_LOG"
        printf 'rc=137\n' >> "$RUN_LOG"
        printf '137\n' > "$RUN_LOG.rc"
        if [ -n "$RUN_ROSTER" ] && [ -z "$RUN_ROW_RC" ]; then
          roster_mark_run "$RUN_ROSTER" "$RUN_NAME" "$RUN_LOG" run_rc=137 "run_ended_at=$(iso_now)" 2>/dev/null || :
        fi
        say "stop-run $RUN_NAME run=$RUN_ID pid=$RUN_PID — stopped ($SR_HOW); it wrote no end, so rc=137 was recorded for it" ;;
      *)
        say "stop-run $RUN_NAME run=$RUN_ID pid=$RUN_PID — stopped ($SR_HOW); the run wrote its own end, rc=$SR_RC" ;;
    esac
    # THE ACT IS RECORDED (wave-36 T11; D8): one ev=stop-run in the bound run's landing record, as for a request.
    _sr_sid="$(session_id 2>/dev/null)" || _sr_sid=""
    stop_run_record "run=$RUN_ID" "name=$RUN_NAME" "by=${_sr_sid:-none}" "why=${SR_WHY:--}" || :
    exit 0
  }

  # ---------- regression-runs: THE FULL RUNS, COUNTED FROM THE RECORDS (wave-30 T12; D7d, Δ6d; AC-4.6) ----------
  #
  # The count is `regression_runs_count`'s: every ended run on this project's rosters whose command
  # is the full runner. Bare, it prints `poker: regression-runs=<n>` and needs no session. `--write`
  # puts the count in the bound plan's `regression-runs:` header through the plan-verb transaction,
  # and only when the plan carries the field and holds another value: a hand-typed number does not
  # survive it. The tick runs `--write` when its own reading of the header differs from the count,
  # so the value is the landing's, never a hand's. The one change is a number in one header line, so
  # the copy is judged here and needs no dry commit.
  poker_verb_regression_runs() {
    REPO_REAL="$(cd "$(project_root "$PWD")" 2>/dev/null && pwd -P)"
    [ -n "$REPO_REAL" ] || { die "REFUSED — cannot resolve the working directory."; exit 2; }
    RR_N="$(regression_runs_count "$REPO_REAL")"
    if [ "$RR_WRITE" = no ]; then say "regression-runs=$RR_N"; exit 0; fi
    plan_verb_open regression-runs
    RR_HAVE="$(plan_frontmatter_get "$PV_PLAN" regression-runs)"
    [ -n "$RR_HAVE" ] && [ "$RR_HAVE" != "$RR_N" ] || exit 0
    if ! RR_N="$RR_N" awk '
      NR == 1 && $0 == "---" { f = 1; print; next }
      f && $0 == "---" { f = 0; print; next }
      f && !done && /^[[:space:]]*regression-runs[[:space:]]*:/ { print "regression-runs: " ENVIRON["RR_N"]; done = 1; next }
      { print }
      END { if (!done) exit 1 }' "$PV_PLAN" > "$PV_NEW" 2>/dev/null; then
      die "REFUSED — $PV_PLAN has no regression-runs: line in its leading frontmatter; the plan is unchanged."
      exit 1
    fi
    plan_verb_swap regression-runs "regression-runs: $RR_N" judged
    say "regression-runs — the plan header read $RR_HAVE and the run records count $RR_N: $RR_N written to $PV_PLAN"
    exit 0
  }
