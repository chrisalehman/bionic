# shellcheck shell=bash
# hooks/poker/tick.sh — the tick: the Patrol stamp, the scheduler, why each row waits, whether a row is too
# quiet, and the decision line (arm, disarm, tick).
#
# A part of hooks/session-poker.sh, which sets every global and loads this file before any verb runs. A part
# defines functions only, and is never run by itself.

# ---------------------------------------------------------------- the Patrol stamp

# The arming record's path — the stamp's, plus one suffix, so the two can never resolve to
# different directories and a mis-resolved root loses both together rather than half.
patrol_armed_file() {  # <session-id> -> absolute path, or empty
  local f
  f="$(patrol_stamp_file "$1")" || return 1
  [ -n "$f" ] || return 1
  printf '%s%s' "$f" "$PATROL_ARMED_SUFFIX"
}

# WRITTEN BY `arm` AND BY NOTHING ELSE. Its content is for a human reading .bionic/tmp; the
# fact the tick reads is its mtime. A failure here is NOT fatal to arming: the stamp is what
# the arming wall reads, and a session armed without a marker simply never auto-DISARMs —
# which is the safe direction (ADR-002 §3), where refusing to arm would take the dispatch
# wall down over a bookkeeping file.
write_patrol_armed_marker() {  # <session-id> -> 0 written, 1 not
  local sid="$1" f d
  f="$(patrol_armed_file "$sid")" || return 1
  [ -n "$f" ] || return 1
  d="${f%/*}"
  tmp_dir_ok "$d" || return 1
  mkdir -p "$d" 2>/dev/null || return 1
  [ -L "$f" ] && return 1
  printf '%s|at=%s|session=%s\n' "$PATROL_ARMED_SCHEMA" "$(iso_now)" "$sid" \
    > "$f" 2>/dev/null || return 1
  chmod 600 "$f" 2>/dev/null
  return 0
}

# THE DIGEST FILE'S PATH, beside the stamp under the same resolved root. The path and its
# reader, `tick_digest_field`, are lib/patrol.sh's (`tick_digest_path`), which the stop
# collector calls too (wave-24 T27; critic I3).
tick_digest_file() {  # <session-id> -> absolute path, or empty
  local f
  f="$(patrol_stamp_file "$1")" || return 1
  [ -n "$f" ] || return 1
  tick_digest_path "${f%/.bionic/tmp/*}" "$1"
}

# The digest file is rewritten whole, under the stamp's write guard. `arm` writes only the
# version, so the first tick after an arm prints in full. A tick's digest carries `at=`, the
# instant it was written: `since=` is the instant the facts last changed and an unchanged tick
# keeps it, so only `at=` tells the stop collector the digest is this turn's (critic I3).
# `gate_raised=` is the set of gate requests already raised (below), and `arm` carries it over,
# so a re-arm does not raise them a second time. `change=` is the fingerprint of the plan's
# `## Tasks` statuses and its ready set (wave-26 T15; D16): the task-list duty is owed only when
# it moved, so `arm` does not carry it and the first tick after an arm compares against nothing.
write_tick_digest() {  # <session-id> <version> [<digest> <since> <decision> <duty> [<gate keys> [<change> [<live head> [<plan current> <plan rows> [<facts state> [<reconcile cause>]]]]]]] -> 0 written, 1 not
  local f d
  f="$(tick_digest_file "$1")" || return 1
  [ -n "$f" ] || return 1
  d="${f%/*}"
  tmp_dir_ok "$d" || return 1
  mkdir -p "$d" 2>/dev/null || return 1
  [ -L "$f" ] && return 1
  {
    printf '%s\n' "$PATROL_DIGEST_SCHEMA"
    [ -n "$2" ] && printf 'prompt_version=%s\n' "$2"
    if [ -n "${3:-}" ]; then
      printf 'digest=%s\nsince=%s\ndecision=%s\nduty=%s\nat=%s\n' "$3" "$4" "$5" "$6" "$(iso_now)"
    fi
    if [ -n "${7:-}" ]; then
      printf 'gate_raised=%s\n' "$7"
    fi
    if [ -n "${8:-}" ]; then
      printf 'change=%s\n' "$8"
    fi
    # THE HEAD THIS TICK JUDGED `live:head` AGAINST (wave-26 T32; A-T14.2), so the turn-end wall,
    # which reads no git, hands the same head to the same ready set on this tick's turn.
    if [ -n "${9:-}" ]; then
      printf 'head=%s\n' "$9"
    fi
    # THE PLAN'S `current:` AND ITS `## Tasks` ROW COUNT, as this tick read them (wave-27 T13; D20):
    # the next tick asks for a task-list reconcile when current: went 3 to 4 or the count grew.
    # `arm` carries neither, so the first tick after an arm compares against nothing.
    if [ -n "${10:-}" ]; then
      printf 'plan_current=%s\n' "${10}"
    fi
    if [ -n "${11:-}" ]; then
      printf 'plan_rows=%s\n' "${11}"
    fi
    # THE FACTS STATE THIS TICK JUDGED (wave-27 T43; A-orch-82), `sched_facts_state`'s answer, so
    # the turn-end wall, which runs no judge and reads no git, hands the integrate row's
    # `proof:review` the same answer on this tick's turn, as it hands the head above. One line.
    if [ -n "${12:-}" ]; then
      printf 'facts_state=%s\n' "$(printf '%s' "${12}" | tr '\n' ' ')"
    fi
    # WHY THE RECONCILE IS OWED, when the plan moved (wave-27 T37): `step4` or `grew`, read by the
    # turn-end wall (lib/stop.sh `stop_turn_facts`) so its refusal gives the tick's own cause.
    if [ -n "${13:-}" ]; then
      printf 'reconcile=%s\n' "${13}"
    fi
  } > "$f" 2>/dev/null || return 1
  chmod 600 "$f" 2>/dev/null
  return 0
}

# THE GATE REQUESTS (wave-25 T5, REQ-4 AC-4.3; D7). hooks/permission-answer.sh denies a reserved
# action and appends one line per distinct request to `.bionic/tmp/gate-<lead sid>.state`:
#   gate/v1|at=<ISO-UTC>|session=<lead sid>|asker=<name or lead>|category=<category>|head=<command head>
# The tick reads that file and the lead raises each request with the human once. The file is the
# record and nothing here rewrites it; "raised" lives in the digest file as `gate_raised=`, the
# keys of the requests the last tick saw. A request is PENDING while its key is not in that set.
#
# THE KEY IS THE HOOK'S DEDUPE KEY (asker, category, head; the session is the file's), hashed so
# the digest file holds a short token per request rather than a command. The hash is computed in
# awk under the C locale, over bytes: `cksum` per line would cost a process per request per tick.
# A line that is not `gate/v1`, names another session, or lacks an asker, a category of the
# reserved table's shape or a head is skipped: a malformed line raises nothing and stops nothing.
gate_requests() {  # <gate file> <session id> <raised keys, comma-separated>
                   # -> one line per distinct request: <key> TAB <new|raised> TAB <asker> TAB <category> TAB <head>
  LC_ALL=C awk -v sid="$2" -v raised=",$3," '
    BEGIN { for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i }
    function key(s,   h, i, n) {
      h = 0; n = length(s)
      for (i = 1; i <= n; i++) h = (h * 31 + ord[substr(s, i, 1)]) % 2147483647
      return h "-" n
    }
    index($0, "gate/v1|") != 1 { next }
    {
      se = ""; a = ""; c = ""; hd = ""; has_head = 0
      nf = split($0, f, "|")
      for (i = 2; i <= nf; i++) {
        if (index(f[i], "session=") == 1) se = substr(f[i], 9)
        else if (index(f[i], "asker=") == 1) a = substr(f[i], 7)
        else if (index(f[i], "category=") == 1) c = substr(f[i], 10)
        else if (index(f[i], "head=") == 1) { hd = substr(f[i], 6); has_head = 1 }
      }
      if (se != sid || a == "" || c !~ /^[a-z][a-z-]*$/ || !has_head) next
      k = key(a "|" c "|" hd)
      if (k in seen) next
      seen[k] = 1
      print k "\t" (index(raised, "," k ",") ? "raised" : "new") "\t" a "\t" c "\t" hd
    }' "$1" 2>/dev/null
}

write_patrol_stamp() {  # <session-id> <verb> -> 0 written, 1 not
  local sid="$1" verb="$2" f d
  f="$(patrol_stamp_file "$sid")" || return 1
  [ -n "$f" ] || return 1
  d="${f%/*}"
  tmp_dir_ok "$d" || return 1
  mkdir -p "$d" 2>/dev/null || return 1
  [ -L "$f" ] && return 1
  printf '%s|at=%s|session=%s|verb=%s\n' "$PATROL_STAMP_SCHEMA" "$(iso_now)" "$sid" "$verb" \
    > "$f" 2>/dev/null || return 1
  chmod 600 "$f" 2>/dev/null
  return 0
}

# THE OTHER END OF THE SAME RECORD, and the only writer in production that ever removes a
# stamp. Until it existed, an aging stamp had exactly one reading available to every
# consumer — "the Patrol died" — and the two deliberate stops this system takes routinely
# (the run-close `CronDelete`, and the DISARM decision below) produced that reading on a
# run that had simply finished. hooks/patrol-revive.sh then blocked the stop of EVERY
# remaining turn of the session, since one block per turn is not a block that stops
# repeating. Removing the stamp is the readable fact that closes it: the revive hook's
# ABSENT state is silent by design, so a stamp that is gone ends the notice rather than
# restarting it, and the arming wall's never-armed refusal is exactly the right thing to
# say to the next dispatch on a run whose clock was deliberately stopped.
#
# A SYMLINK IS NOT A STAMP, here as everywhere else under .bionic/tmp. It is left alone
# rather than unlinked: every reader in the fleet already treats it as absent, so there is
# nothing to close, and a script that deletes files it never wrote is a worse trade than a
# no-op. The directory shape is checked exactly as the writer checks it, so a resolution
# that landed somewhere else removes nothing.
remove_patrol_stamp() {  # <session-id> -> 0 gone (removed, or never there), 1 could not
  local sid="$1" f d a
  f="$(patrol_stamp_file "$sid")" || return 1
  [ -n "$f" ] || return 1
  d="${f%/*}"
  case "$d" in */.bionic/tmp) : ;; *) return 1 ;; esac
  # THE ARMING RECORD GOES WITH THE STAMP, best-effort. Both halves say "this session's
  # Patrol is live", so leaving one behind leaves the disk saying half of a thing that
  # ended. It is best-effort because no reader consults the marker without a stamp beside
  # it, so a survivor claims nothing — where a surviving STAMP claims a live clock, which
  # is why that one decides the return code.
  a="$(patrol_armed_file "$sid")" || a=""
  if [ -n "$a" ] && [ ! -L "$a" ] && [ -e "$a" ]; then rm -f "$a" 2>/dev/null; fi
  [ -L "$f" ] && return 0
  [ -e "$f" ] || return 0
  rm -f "$f" 2>/dev/null
  [ -e "$f" ] && return 1
  return 0
}

# ---------------------------------------------------------------- the scheduler
#
# FILL, sized at the gate (spec AC-17, AC-29, AC-31; design-ledger D3; wave-28 T13, D14).
#
# THE PROBLEM. A wave's width was a number in a brief, and a ceiling nobody reaches is a
# wave running one writer at a time by accident: this repo's own 1.4.0 wave dispatched six
# trees against a budget of twenty-two and then went quiet for a batch at a time. Nothing
# on the machine was watching for the gap, because the only thing that fires on its own is
# the Patrol tick — and the tick had no opinion about width.
#
# THE WIDTH IS THE GATE'S (wave-28 T13; D14, AC-2.5, AC-2.8; the owner's "Option 2"). The
# tick fills by asking `gate_room` once per ready row, the writers not yet showing counted as
# owed, and stops at the first no (`fill_gate_width`, lib/fill.sh); a person's cap (`fill_cap`,
# the stop wall's reader too) still caps. It prints ONE gate line on every tick, in place of the
# rung, the HOLD and the EMERGENCY that came before it:
#
#   gate share=<n> used=<n>% load=<1m>/<5m> of <cores> promised=<n> admitted=<n> waiting=<n> room=<yes|no> widths: <key>=<n>[,<key>=<n>…]|none
#
# THE WIDTH EACH LANDING IS ANSWERED (wave-38 T7; D22, REQ-6 AC-6.5). `widths:` names every landing whose lease
# is held (lib/gate.sh THE LEASE: from its first ask until it publishes, is returned or stalls), oldest first,
# with what `gate_width_ask` answers it now: the oldest its width, every younger one 0 until it finishes. A
# lease its carrier left WAITING orders no one and is not named; with none held the field is `none`.
#
# and, while memory is over the share, `over share — used=<n>% admitted: <keys>`. The gate
# admits no run past memory's share, so nothing is left for a tick to stop: the line names what
# holds the memory and leaves the act to the orchestrator.
#
# EVERY DECISION IS ADVISORY. The tick prints; the orchestrator dispatches, stops and edits
# the plan. hooks/patrol-duties-gate.sh is what makes a printed FILL binding — the tick's
# turn may not end while a named row is still ready and undispatched — and that is a
# wall on the ORCHESTRATOR, not an action taken here. A hook that dispatched agents or
# stopped them would be a hook taking irreversible action off a reading it cannot confirm.

# One field out of a space-separated `key=value` record (resources_probe's shape, and the
# plan header's `parallel-budget:` value), BY KEY and never by position.
space_field() {  # <record> <key> -> value on stdout, empty if absent
  printf '%s' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -1
}

# THE PLAN HEADER'S BUDGET IS READ BY run.sh (epic-23 wave-20 T2, D10). `plan_budget_line`
# (the strict `parallel-budget:` line of the leading frontmatter) and `budget_field` (one
# whole field, as a decimal integer) moved there from this file, so the tick, the stop wall,
# dispatch preflight and the governing-skill hook size a run from one reading. NOT AN INTEGER
# IS ABSENT: an arm this cannot measure goes unmeasured and says so.

# THE TASK TABLE IS NOT READ HERE ANY MORE (REQ-1e, spec §2 D3). `slice_table` and
# `slice_ready` — a header-keyed `id`/`deps`/`status` parse and the readiness pass over it
# — lived at this point in the file and are now `units_rows` and `units_ready` in
# payload/scripts/lib/units.sh, sourced above. The idiom is theirs, unchanged: column
# indices from the header row by NAME, fence-aware, table order preserved, and the cautious
# fill direction (an id the table does not carry is NOT ready, because a task held back
# costs a batch and a task dispatched onto an unlanded dependency costs the writer's whole
# run). What the move buys is the STEP: the widened table carries one, so a tick at
# `current: 5` fills Step-5 rows and not the Step-6 rows sitting ready behind them.

# ---------------------------------------------------------------- the gate report

# ── THE APPROVAL GATE (epic-21 T4, AC-5). A printed FILL is a dispatch instruction — the
# duties gate (hooks/patrol-duties-gate.sh) refuses the turn until every named task is
# either dispatched or made not ready — and dispatching into a plan that has not
# reached Step 4 sends a writer against a task table nobody has ratified: Steps 0-3 are
# research/spec/plan/REVIEW, and `current:` only reaches 4 once Step 3's approval is given
# (SKILL.md §Steps). Observed 2026-09-05T17:54Z: the tick printed `FILL S1 S2 S3 S4 S12 S14
# S15 S16` against the wave-01 plan sitting at `current: 3`.
#
# THE SAME FENCE-AWARE READ `run_state` USES ABOVE, deliberately duplicated rather than
# shared. `run_state` answers a different question (has THIS run delivered) off a plan
# resolved through its own `resolve_run` call, and folding this into it would couple the
# DISARM decision to the FILL decision — two arms this wave's scope keeps apart. Sharing the
# awk/grep/sed pipeline, not the caller, keeps the two readings from ever disagreeing about
# what one `current:` line says.
#
# AND THE PARSER IS THE LIBRARY'S (wave-19 REQ-6, D7; AC-6.1). The fence-aware read described
# above lives once, in `payload/scripts/lib/fill.sh`'s `_fill_current_field` (sourced above
# with units.sh), which the stop wall's fill duty reads through as well. This name stays as a
# one-line wrapper rather than disappearing: §CG of tests/cross-gate-agreement.test.sh
# extracts it as text and drives it beside `run_open` with fill.sh sourced, and §32 of
# tests/session-poker.test.sh drives it beside the library — a poker that called the library
# directly would leave §32 comparing one function with itself.
_sched_plan_current_field() {  # <plan path> -> the RAW current: value (trimmed), or ""
  _fill_current_field "$@"
}

# THE ONE GRAMMAR THIS REPO ALREADY HAS (Step-6 review-a C-5, review-b finding (c)/N-2).
# payload/scripts/lib/run.sh's run_open strips a trailing a/b sub-step letter before it
# ever looks at digits (`local step="${current%[ab]}"`) — `current: 3b` and `current: 4b`
# are recognized, in-repo forms, not malformed ones. This mirrors exactly that: strip the
# same optional letter, then require what remains to be all-digits.
sched_plan_current() {  # <plan path> -> the current: value (digits only, sub-step letter
                        # stripped), or "" if the raw value is unreadable
  local plan="$1" current step
  current="$(_sched_plan_current_field "$plan")"
  step="${current%[ab]}"
  case "$step" in ''|*[!0-9]*) printf '' ;; *) printf '%s' "$step" ;; esac
}

# ── THE GATE LINE, ON EVERY TICK (wave-28 T13; D14, AC-2.8). One `gate_state` and one
# `gate_room` with the writers not yet showing as owed, printed as one line from every exit
# path, as the rung line was (AC-17: the first tick of a run takes the armed arm, and the DISARM
# arm exits above the scheduler). `gate_state` takes the gate's lock, so the tick is also one of
# the gate's samplers: each line raises the peak of every admitted run.
#
# NO GATE IS NO ROOM. A gate.sh that did not load is a width this tick does not have, and the
# line says so; a fill sized on nothing would be the guess the gate exists to replace.
gate_report() {  # <project root> <session id> -> sets SCHED_GATE_ROOM/SCHED_OWED, says one line
  local st rm used share keys
  sched_budget_read "$1" "${2:-}"
  SCHED_GATE_ROOM=no; SCHED_OVER=no
  SCHED_OWED="$(sched_owed)"
  if ! declare -F gate_room >/dev/null 2>&1 || ! declare -F fill_gate_width >/dev/null 2>&1; then
    say "gate unreadable — lib/gate.sh did not load, so no row is offered"
    return 0
  fi
  st="$(gate_state 2>/dev/null)"
  rm="$(gate_room --owed "$SCHED_OWED" 2>/dev/null)"
  share="$(space_field "$st" share)"; used="$(space_field "$st" used)"
  SCHED_GATE_ROOM="$(space_field "$rm" room)"
  say "gate share=${share:--} used=${used:--}% load=$(space_field "$rm" load) of $(space_field "$rm" cores) promised=$(space_field "$rm" promised) admitted=$(space_field "$st" admitted) waiting=$(space_field "$st" waiting) room=${SCHED_GATE_ROOM:-no} widths: $(gate_widths)"
  case "$used$share" in *[!0-9]*|'') return 0 ;; esac
  [ "$used" -gt "$share" ] || return 0
  SCHED_OVER=yes
  keys="$(gate_list 2>/dev/null | awk '$2 == "admitted" && match($0, / key=/) { printf "%s%s", (n++ ? ", " : ""), substr($0, RSTART + 5) }')"
  say "over share — used=${used}% admitted: ${keys:-none}"
}

# gate_widths -> `<key>=<n>[,<key>=<n>…]` for the held landing leases, oldest first, or `none` (the gate line's
# `widths:` field, above). The leases are read lock-free with the gate's own reader and rule (`_gate_lease_read`,
# `_gate_lease_state`: held, away or spent), ordered as `gate_width_ask` orders them (the first-ask instant, then
# the seq), and each is answered by `gate_width_ask` itself, so the line prints the gate's answer and never its own.
gate_widths() {
  local d f k n out="" held
  declare -F gate_width_ask >/dev/null 2>&1 && declare -F _gate_lease_read >/dev/null 2>&1 \
    && declare -F _gate_lease_state >/dev/null 2>&1 || { printf 'none'; return 0; }
  d="$(gate_dir 2>/dev/null)"
  [ -n "$d" ] && [ -d "$d/leases" ] || { printf 'none'; return 0; }
  held="$(for f in "$d"/leases/*.lease; do
      _gate_lease_read "$f" || continue
      _gate_lease_state
      [ "$_L_state" = held ] && printf '%s\t%s\t%s\n' "$_L_first" "$_L_seq" "$_L_landing"
    done | sort -t "$(printf '\t')" -k1,1n -k2,2n | cut -f3)"
  [ -n "$held" ] || { printf 'none'; return 0; }
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    n="$(gate_width_ask "$k" 2>/dev/null)" || n='-'
    out="${out}${out:+,}$(clean "$k")=${n:--}"
  done <<GATE_WIDTHS
$held
GATE_WIDTHS
  printf '%s' "${out:-none}"
}

# THE WRITERS NOT YET SHOWING (D14): the open writer rows of this tick whose agent has not asked
# the gate for a run, read by `fill_gate_owed` (lib/fill.sh) — the count the stop wall takes too.
sched_owed() {
  if ! declare -F fill_gate_owed >/dev/null 2>&1; then printf '0'; return 0; fi
  printf '%s' "${TICK_OCC_NAMES:-}" | fill_gate_owed "${ROSTER_FILE:-}" "${SESSION_ID:-}"
}

# ---------------------------------------------------------------- the plan report
#
# THE HOLDS AND THE LEDGER, ON EVERY TICK THAT DECIDES (wave-21 T13; REQ-3 AC-3.3, REQ-4
# AC-4.1/AC-4.2; the audit's refutation at 3b45d05). Through T5 both reports lived inside the
# FILL branch, and three reachable states never reached it: the first tick of a run (no roster
# yet: rung, QUIET, exit), HOLD or EMERGENCY under machine pressure, and a plan with no
# `parallel-budget`. The commit gate reads the ledger in every state, so a plan the gate
# refused ticked clean — AC-4.1's fails-when, word for word. Neither report has anything to do
# with the machine or the budget, so neither waits on them: every arm that decides calls this
# once, after its gate line and before its own sentence, and no arm prints them a second time.
#
#   HELD (T4; D3, ADR-037 decision 2). `units_held` names two kinds of row the ready set leaves
#     out: one held FOR ITS STEP (a gate act ahead of `current:`) and one held BY THE WORLD
#     (`ext:<slug>` left in its deps cell). Each ext-held row prints as
#     `poker: HELD <id> ext:<slug>`: the one report of a wait nothing mechanical lifts,
#     addressed to the only actor who can lift it (remove the token from the cell). The
#     step-held lines are left in `SCHED_HOLDS` for the no-FILL line, where they have always
#     been printed.
#   LEDGER (T5; D4, ADR-037 decision 3). `units_findings` is the reader the commit gate refuses
#     on — a status off the enum, a row at its terminal word with no `- T<n>:` line, an
#     `active` row whose agent cell names no row on the run's rosters nor its Dispatch ledger —
#     and each finding prints as `poker: LEDGER <id> <kind> [<value>]`. The rosters are
#     `units_run_rosters`' list, this tick's own first, the list the gate reads (wave-36 T29;
#     D10); with none to read (the first tick) it is the reader's no-roster rule, the gate's too.
#
# AN UNREADABLE BOUND PLAN, OR NO PLAN, REPORTS NOTHING: there is no table to read, and the
# arms that decide say why themselves. A `current:` that will not parse still lints the
# ledger — the findings ask no step — and only the holds, which are a readiness question,
# need the step token.
#
# CALLED UNDER `tick_plan_memoised`, so the holds, the findings and — on the arm that fills —
# the ready set are answered from ONE parse of the table (review-bed/perf/report.md measured
# four parses per tick before this).
# Set in hooks/session-poker.sh, before any part loads: SCHED_HOLDS.
tick_plan_report() {  # -> says the HELD and LEDGER lines; sets SCHED_HOLDS
  local step hold finding kind rest val
  SCHED_HOLDS=""
  [ -n "${SCHED_PLAN:-}" ] && [ "$POKER_RUN_OPEN" != unreadable ] || return 0
  _fill_current_load "$SCHED_PLAN"
  step="$(fill_step_token "$SCHED_PLAN")"
  [ -z "$step" ] || SCHED_HOLDS="$(units_held "$SCHED_PLAN" "$step" 2>/dev/null)"
  while IFS= read -r hold; do
    case "$hold" in
      *": held by ext:"*) say "HELD ${hold%%: held by *} ${hold#*: held by }" ;;
    esac
  done <<EOF
$SCHED_HOLDS
EOF
  while IFS= read -r finding; do
    [ -n "$finding" ] || continue
    kind="${finding%% *}"
    rest="${finding#* }"
    val=""
    case "$rest" in *" "*) val="${rest#* }" ;; esac
    say "LEDGER ${rest%% *} ${kind}${val:+ $(clean "$val")}"
  done <<EOF
$(units_findings "$SCHED_PLAN" "$(units_run_rosters "${ROSTER_FILE%/*}" "$SCHED_PLAN" "$ROSTER_FILE")" 2>/dev/null)
EOF
  return 0
}

# ---------------------------------------------------------------- why each row waits

# A ROW WAITING ON THE USER'S APPROVAL ALONE IS THE PERSON'S BLOCK (wave-33 T35; AC-2.2, D2). A WAIT
# whose every clause is `approval:<name>` (or its live read) opens `approve:<name>` on the person's
# ledger (lib/owed.sh), the key the approve verb closes, carrying the WAIT line printed. A row that
# also waits on other work is not yet blocked on the person and opens nothing; `approval:plan` is the
# Step-3 card's. Opening is idempotent per key, so every later tick on the same wait is one item.
tick_owed_approval() {  # <reason> <printed line> -> always 0, prints nothing
  local c names=""
  declare -F owed_open >/dev/null 2>&1 || return 0
  while IFS= read -r c; do
    c="${c# }"; c="${c% }"; c="${c#live:}"
    case "$c" in
      approval:plan) return 0 ;;
      approval:[A-Za-z0-9]*) case "${c#approval:}" in *[!A-Za-z0-9._-]*) return 0 ;; esac ;;
      *) return 0 ;;
    esac
    names="$names ${c#approval:}"
  done <<TOA
$(printf '%s\n' "$1" | awk '{ n = split($0, a, /; /); for (i = 1; i <= n; i++) print a[i] }')
TOA
  for c in $names; do
    OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_open "approve:$c" "approval: $c" "$2" >/dev/null 2>&1
  done
  return 0
}

# A GOAL'S FIRST MISS IS A DECISION THE PERSON OWES, NEVER A NOTE. Every goal the plan declares is read through
# lib/plan.sh `plan_goals_read`; one read missed opens `decide:goal:<theme>` on the person's ledger (lib/owed.sh),
# carrying the reading, and the tick says it once. A key the ledger already holds, open or closed, opens nothing: the
# person's ruling on a miss stands, so a later tick on the same miss puts no second decision. A goal that reads
# reached closes its item if one is open, so a miss the run recovered from stops asking.
tick_owed_goals() {  # <plan> <landing record> -> always 0; one line said per goal it opens
  local f st t m rd k
  declare -F owed_open >/dev/null 2>&1 && declare -F plan_goals_read >/dev/null 2>&1 || return 0
  f="$(OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_file 2>/dev/null)" || return 0
  while IFS='	' read -r st t m rd; do
    k="decide:goal:$(plan_goal_slug "$t")"
    if [ "$st" = reached ]; then
      declare -F owed_close >/dev/null 2>&1 && OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_close "$k" "goal reached" >/dev/null 2>&1
      continue
    fi
    [ "$st" = missed ] || continue
    [ -f "$f" ] && /usr/bin/grep -qF "|key=$k|" "$f" 2>/dev/null && continue
    OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_open "$k" "Goal missed: $t" "poker: GOAL $t missed — $m: $rd; keep the target or change course" >/dev/null 2>&1 \
      && say "GOAL $t missed — $m: $rd; owed: $k"
  done <<TOG
$(plan_goals_read "$1" "$2" "$(landing_report "$2" "$REPO_REAL" yes 2>/dev/null)")
TOG
  return 0
}

# THE FINAL CARD'S EARLY FACTS, AS ADVICE (wave-38 T3; D20, AC-1.2). While the plan carries an open integrate row,
# the tick asks payload/scripts/card.sh `early`, the one owner of the three facts the final card is refused on (an
# open reader, a reading unregistered at the head, a red check of the advance to 6, 7 or 8), and says its line,
# `CARD-EARLY — <reason>`, beside the WAIT lines. Advice only: the tick refuses nothing and writes nothing for it.
# THE READINGS ARE THE TICK'S, ASKED ONCE (wave-36 T40; D9, AC-3.6): `sched_live_head` has already asked the judge
# for this plan at the working head, so the card is handed that answer and the head it was asked at
# (UNITS_READINGS_STATE, UNITS_LIVE_HEAD) and reads it rather than walking the commits a second time.
tick_card_early() {  # <units_rows output> -> always 0; says the card's CARD-EARLY line when one fact fails
  local card why
  printf '%s\n' "$1" | awk -F'\t' '$3 == "integrate" && ($10 == "pending" || $10 == "active") { f = 1 } END { exit !f }' || return 0
  card="$(cd "$BIONIC_LIB" 2>/dev/null && pwd -P)/../card.sh"
  [ -f "$card" ] || return 0
  why="$( cd "$REPO_REAL" 2>/dev/null && env CLAUDE_CODE_SESSION_ID="$SESSION_ID" UNITS_LIVE_HEAD="${UNITS_LIVE_HEAD:-}" \
    UNITS_READINGS_STATE="${UNITS_READINGS_STATE:-}" "${BASH:-bash}" "$card" early "$SCHED_PLAN" 2>&1 >/dev/null )" && return 0
  why="$(printf '%s\n' "$why" | head -1)"
  case "$why" in "CARD-EARLY — "*) say "$why" ;; esac
  return 0
}

tick_wait_report() {  # -> says the WAIT lines and the CHAIN line; reads SCHED_* the FILL arm set; sets SCHED_BEHIND (the ready rows parked for width)
  local rows waiting all offered held line chain ids mins susp base sfx edges split sp_id sp_sz sp_nf sp_k wl
  [ -n "${SCHED_PLAN:-}" ] && [ -n "${SCHED_STEP:-}" ] || return 0
  rows="$(units_rows "$SCHED_PLAN" 2>/dev/null)" || return 0
  [ -n "$rows" ] || return 0
  waiting="$(units_waiting "$SCHED_PLAN" "$SCHED_STEP" 2>/dev/null)"
  susp="$(suspect_lines "$SCHED_PLAN")"
  all="${SCHED_READY_ALL:-}"
  offered="$(printf '%s' "${SCHED_READY:-}" | tr '\n' ' ')"
  # THE ROWS A ROSTER HOLDS (wave-35 T28; AC-5.5, D14): a pending row open on any roster, this
  # session's or another's, is left out of the ready set (`fill_held_ids`, lib/fill.sh), and its WAIT
  # names the writer and the roster's session: `WAIT <id> — <name> open on roster <sid, first 8>`.
  held="$(fill_held_ids "$SCHED_PLAN" "$(printf '%s\n' "$rows" | awk -F'\t' '$10 == "pending" { print $1 }')" 2>/dev/null)"
  SCHED_BEHIND=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    base="${line%%$'\037'*}"; sfx=""
    [ "$base" = "$line" ] || sfx="${line#*$'\037'}"
    case "$base" in *" — ready; no writer slot free (gap "*) SCHED_BEHIND="${SCHED_BEHIND}${SCHED_BEHIND:+ }${base%% *}" ;; esac
    wl="WAIT $(clean "$base")${sfx:+ · $(clean_whole "$sfx")}"
    say "$wl"
    tick_owed_approval "${base#* — }" "poker: $wl"
  done <<TICK_WAIT
$(printf '\034rows\n%s\n\034wait\n%s\n\034susp\n%s\n\034held\n%s\n' "$rows" "$waiting" "$susp" "$held" | awk -F'\t' \
    -v offered=" $offered " -v all=" $all " -v gap="${SCHED_GAP:-0}" '
  $0 == SUBSEP "rows" { part = 1; next }
  $0 == SUBSEP "wait" { part = 2; next }
  $0 == SUBSEP "susp" { part = 3; next }
  $0 == SUBSEP "held" { part = 4; next }
  part == 3 && $1 != "" { sus[$1, $2] = $3; next }
  part == 4 && $1 != "" { hold[$1] = $2 " open on roster " substr($3, 1, 8); next }
  part == 1 && $1 != "" { n++; id[n] = $1; knd[$1] = $3; st[$1] = $10; next }
  part == 2 && $1 != "" {
    key = $1 SUBSEP $2
    if (!(key in seen)) { seen[key] = 1; nr[$1]++; rd[$1, nr[$1]] = $2 }
    if ($3 != "-") { nw[key]++; wid[key, nw[key]] = $3; wst[key, nw[key]] = $4 }
    next
  }
  END {
    for (k = 1; k <= n; k++) {
      i = id[k]
      if (st[i] != "pending" || index(offered, " " i " ")) continue
      reason = ""
      if (nr[i] > 0) {
        for (m = 1; m <= nr[i]; m++) {
          r = rd[i, m]; key = i SUBSEP r
          if (substr(r, 1, 5) == "step:") {
            p = substr(r, 6); t = "step " p " " knd[i] " row waits for current: " p
          } else if (nw[key] == 0) {
            t = r
          } else if (nw[key] == 1 && wid[key, 1] == r) {
            t = "waits for " r " (" wst[key, 1] ")"
          } else {
            t = "reads " r ", written by "
            for (w = 1; w <= nw[key]; w++) t = t (w > 1 ? ", " : "") wid[key, w] " (" wst[key, w] ")"
          }
          reason = reason (reason == "" ? "" : "; ") t
        }
        sfx = ""; split("", said)
        for (m = 1; m <= nr[i]; m++) {
          key = i SUBSEP rd[i, m]
          for (w = 1; w <= nw[key]; w++) {
            h = wid[key, w]
            if (((i, h) in sus) && !(h in said)) { said[h] = 1; sfx = sfx (sfx == "" ? "" : " · ") sus[i, h] }
          }
        }
        if (sfx != "") reason = reason "\037" sfx
      } else if (index(all, " " i " ")) {
        reason = "ready; no writer slot free (gap " gap ")"
      } else if (i in hold) {
        reason = hold[i]
      } else continue
      printf "%s — %s\n", i, reason
    }
  }')
TICK_WAIT
  tick_card_early "$rows"
  edges="$(units_edges "$SCHED_PLAN" 2>/dev/null)"
  chain="$( { printf '%s\n' "$rows" | awk -F'\t' '$10 == "pending" || $10 == "active" {
                m = 0; if (match($7, /^[0-9]+/)) m = substr($7, RSTART, RLENGTH)
                printf "N\t%s\t%d\n", $1, m }'
              printf '%s\n' "$edges" | awk -F'\t' 'NF >= 2 { printf "E\t%s\t%s\n", $1, $2 }'
            } | units_chain "${SCHED_WRITERS:-$(printf '%s\n' "$rows" | grep -c .)}" 2>&1 )" || {
    say "CHAIN unknown — $(clean "$chain")"
    return 0
  }
  line="$(printf '%s\n' "$chain" | awk -F'\t' '$1 == "chain" { print $2 "\t" $3; exit }')"
  ids="${line%%$'\t'*}"; mins="${line##*$'\t'}"
  [ -n "$ids" ] || return 0
  say "CHAIN ${ids//,/→} (${mins} min)"
  case "${SCHED_IDLE_AT:-}" in ''|*[!0-9]*) return 0 ;; esac
  split="$(units_split_candidate "$SCHED_PLAN" "$ids" "$edges" 2>/dev/null)"
  [ -n "$split" ] || return 0
  IFS=$'\t' read -r sp_id sp_sz sp_nf sp_k <<< "$split"
  gate_room --owed "$SCHED_IDLE_OWED" >/dev/null 2>&1 || return 0
  say "SPLIT $(clean "$sp_id") — ${sp_sz} min, ${sp_nf} files, ${sp_k} rows wait on it; width idles at ${SCHED_IDLE_AT}"
}

# THE PRIORITY A RECORD NEVER STATES (wave-28 T15; D19, AC-8.3). A rated reading writes the plan's
# `deferred:` lines at registration; the tick prints each such finding once, with the
# priority the table gives its rating (lib/proof.sh `proof_findings_owed`, which `release-check`
# prints too):
#
#   poker: FINDING <record>#<n> <S> <reach> <fix|defer|note> "<title>"
#
# Silent on a plan that carries none. Called beside the WAIT lines, on the scheduler's one parse.
tick_finding_report() {  # -> says one FINDING line per finding the plan defers or owes a check for
  local line
  [ -n "${SCHED_PLAN:-}" ] && [ -f "$SCHED_PLAN" ] || return 0
  /usr/bin/grep -qE '^(deferred|check):[[:space:]]' "$SCHED_PLAN" 2>/dev/null || return 0
  declare -F proof_findings_owed >/dev/null 2>&1 \
    || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh" 2>/dev/null; }
  declare -F proof_findings_owed >/dev/null 2>&1 || return 0
  while IFS= read -r line; do
    [ -n "$line" ] && say "FINDING $(clean "$line")"
  done <<TICK_FINDINGS
$(proof_findings_owed "$SCHED_PLAN" 2>/dev/null)
TICK_FINDINGS
}

# THE DETACHED LAUNCH-SYNC'S FAILURE, TOLD ONCE (wave-36 T12; D13, AC-7.1; C13). The launch recorder
# (hooks/execution-recorder.sh `launch_sync_start`) writes the call's output and then `rc=<n>` to
# `.bionic/tmp/launch-sync-<sid>.log`, rewriting it at each launch. A log whose last status is not 0
# and that carries no `told=` line prints
#
#   poker: launch-sync failed — <log>
#
# and gets a `told=<ISO>` line, so the line prints once per failure, never per tick: the next launch
# rewrites the log and a new failure is told again. A log with no `rc=` line is a call still running,
# or one killed before it ended, and says nothing; so does a symbolic link.
tick_launch_sync_failed() {  # <root> <session-id> -> says the line when the log holds an untold failure
  local log="$1/.bionic/tmp/launch-sync-$2.log" rc
  [ -f "$log" ] && [ ! -L "$log" ] || return 0
  rc="$(awk '/^rc=/ { r = substr($0, 4) } /^told=/ { t = 1 } END { if (!t) print r }' "$log" 2>/dev/null)"
  case "$rc" in ''|0) return 0 ;; esac
  printf 'told=%s\n' "$(iso_now)" >> "$log" 2>/dev/null || return 0
  say "launch-sync failed — $log"
}

# tick_plan_memoised <command> [args…] -> runs the command with the bound plan's table parsed
# once for everything it asks (`units_memoised`, payload/scripts/lib/units.sh); a tick with no
# readable plan runs it bare, since there is no table to hold.
tick_plan_memoised() {
  if [ -n "${SCHED_PLAN:-}" ] && [ "$POKER_RUN_OPEN" != unreadable ]; then
    units_memoised "$SCHED_PLAN" "$@"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------- is this row too quiet?

# THE SHARED NEWEST-LOG PREFERENCE (D8; REQ-8; epic-23 wave-20 T5; supersedes the T1d
# this-session/adopted_from chain, walk W-3). An ADOPTED row's transcript lives under
# whichever session last spoke to the agent — and after a SECOND `/clear` that can be an
# INTERMEDIATE adopter this row names nowhere, because `adopted_from=` always names the
# ORIGINAL launcher. `agent_log_newest` globs every session directory of the project for
# the exact agent id and returns the newest by mtime, so no chain of sessions has to be
# walked and no intermediate adopter can be missed. Both readers of the working log —
# `row_quiet` (the tick's own liveness read) and `adopt`'s report (the ADOPT_SCHEMA block
# below) — call it through this project-directory resolution.

# A LIVE RUN IS NOT A QUIET ONE (wave-39 T22; REQ-16 AC-16.1; D21). A writer blocked in a foreground `ready --within`
# touches neither its progress file nor its transcript for up to thirty minutes, so the two mtimes alone named every
# such row on every tick. Before either NOTIFY arm reads an mtime the tick asks `row_live_run` whether the row has a
# run that lives, by the two facts that say so and that no mtime can:
#   - its LANDING CARRIER: an open entry of lib/line.sh's fold (an `ev=ready` of the plan's landing record with no later
#     `published` or `returned`) whose name is the row's and whose `carrier=` process lives, by `_line_entries`'s
#     presence rule (the pid-and-start rule of lib/slots.sh). `landing_carrier_names` is the one read of it;
#   - the GATE's open request for the row's agent: a request of lib/gate.sh waiting or admitted whose `who=` is
#     `<session>:<agent>` (`gate_asked`), the session being the one that launched the agent, the one that adopted it
#     and this one. A suite or a landing's run in flight is a live run too.
# Either one, and the row is ACTIVE: neither arm names it. Neither one, and the mtimes decide as they did, so a dead
# silent row still NOTIFYs.
# Set in hooks/session-poker.sh, before any part loads: TICK_CARRIERS, TICK_CARRIERS_READ.
landing_carrier_names() {  # <plan> -> the names of the entries whose landing carrier lives, one a line (read once a tick)
  local rec
  [ "$TICK_CARRIERS_READ" = yes ] && { printf '%s' "$TICK_CARRIERS"; return 0; }
  TICK_CARRIERS_READ=yes
  declare -F _line_entries >/dev/null 2>&1 || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1
  declare -F _line_entries >/dev/null 2>&1 || return 0
  rec="$(_wt_proofs_path "$REPO_REAL" "$1" 2>/dev/null)" || rec=""
  [ -n "$rec" ] && [ -f "$rec" ] && [ ! -L "$rec" ] || return 0
  TICK_CARRIERS="$(_line_entries "$rec" "" 2>/dev/null | awk -F'\t' '$4 == "yes" && $2 != "" { print $2 }')"
  printf '%s' "$TICK_CARRIERS"
}
row_live_run() {  # <roster-state row> -> 0 when the row's agent has a live landing carrier or an open gate request
  local row="$1" name who s names=""
  name="$(line_field "$row" name)"
  [ -n "$name" ] || return 1
  if [ -n "${POKER_RUN_PLAN:-}" ] && [ -f "$POKER_RUN_PLAN" ]; then
    landing_carrier_names "$POKER_RUN_PLAN" | /usr/bin/grep -qxF -- "$name" && return 0
  fi
  declare -F gate_asked >/dev/null 2>&1 || return 1
  # The gate spells the agent as booked.sh does (lib/gate.sh `_gate_marker`).
  who="${name//[!A-Za-z0-9._+-]/_}"
  for s in "$SESSION_ID" "$(line_field "$row" session)" "$(line_field "$row" adopted_from)"; do
    [ -n "$s" ] && names="${names}${s}:${who}
"
  done
  [ -n "$names" ] && printf '%s' "$names" | gate_asked >/dev/null 2>&1
}

# Set in hooks/session-poker.sh, before any part loads: TICK_QUIET_MTIME, TICK_QUIET_CHANNEL, TICK_QUIET_AGE,
# TICK_QUIET_CAD.
row_quiet() {  # <roster-state row> <now epoch> -> 0 quiet, 1 alive, 2 nothing to observe
  local row="$1" now="$2" cad cad_s prog pm=0 id proj tx lm=0

  TICK_QUIET_MTIME=""; TICK_QUIET_CHANNEL=""; TICK_QUIET_AGE=""; TICK_QUIET_CAD=""
  OBS_DELIV_STATE=none
  OBS_LOG_MTIME=0; OBS_LOG_AGE=0
  OBS_PROGRESS_STATE=unnamed; OBS_PROGRESS_AGE=0
  OBS_CADENCE_S="$OBSERVE_CADENCE_DEFAULT_S"

  # THE DECLARED CADENCE, and the library's own fallback when the row declared none or
  # declared it unreadably — the same default `observe_agent` applies, for the same reason:
  # a guess about the number is worse than the rule the liveness contract widened.
  cad="$(line_field "$row" cadence)"
  if [ -n "$cad" ]; then
    cad_s="$(parse_seconds "$cad")" && [ -n "$cad_s" ] && OBS_CADENCE_S="$cad_s"
  fi
  TICK_QUIET_CAD="$OBS_CADENCE_S"

  # CHANNEL 1 — the contracted progress artifact, as the row spells it.
  prog="$(adopt_abs "$(line_field "$row" progress)" "$REPO_REAL")"
  if [ -n "$prog" ] && [ -f "$prog" ]; then
    OBS_PROGRESS_STATE=present
    pm="$(file_mtime "$prog")"
    OBS_PROGRESS_AGE=$(( now - pm ))
    [ "$OBS_PROGRESS_AGE" -lt 0 ] && OBS_PROGRESS_AGE=0
  fi

  # CHANNEL 2 — the agent's own transcript, which the harness appends to on every turn it
  # takes. It is the channel a role with no Write tool has, and the one a working agent
  # cannot forget to keep. An ADOPTED row's `adopted_from=` records the session that
  # LAUNCHED it, which is where its file lives until this session speaks to the agent.
  tx=""
  id="$(line_field "$row" agent_id)"
  if [ -n "$id" ]; then
    # THE NEWEST COPY, ANYWHERE IN THE PROJECT (D8, REQ-8) — never a this-session/
    # adopted_from CHAIN. The harness files an agent's transcript under whichever session
    # is talking to it NOW, and after a SECOND `/clear` that can be an intermediate adopter
    # `adopted_from=` never names (it always names the ORIGINAL launcher) — reading only
    # the launcher's copy, or only this session's, reported a working agent quiet (R1 Q4,
    # bed3; triage-A). `adopted_from=` itself is still provenance and is never rewritten:
    # adopt's idempotence keys on it.
    proj="$(agent_project_dir_for "$SESSION_ID")" || proj=""
    tx=""
    [ -n "$proj" ] && { tx="$(agent_log_newest "$id" "$proj")" || tx=""; }
    if [ -n "$tx" ]; then
      OBS_LOG_MTIME="$(file_mtime "$tx")"
      lm="$OBS_LOG_MTIME"
      OBS_LOG_AGE=$(( now - OBS_LOG_MTIME ))
      [ "$OBS_LOG_AGE" -lt 0 ] && OBS_LOG_AGE=0
    fi
  fi

  [ "$OBS_PROGRESS_STATE" = present ] || [ "$lm" -gt 0 ] || return 2

  # THE MTIME THE READER IS SHOWN is the NEWEST of the two, because that is the one the
  # verdict rests on: the row is quiet only if BOTH channels are, so the later of them is
  # what "last heard from" means. Printed as an instant and not only as an age — an age is
  # relative to a tick nobody kept.
  if [ "$lm" -gt "$pm" ]; then
    TICK_QUIET_CHANNEL="transcript $tx"
    TICK_QUIET_MTIME="$(epoch_iso "$lm")"
    TICK_QUIET_AGE="$OBS_LOG_AGE"
  else
    TICK_QUIET_CHANNEL="progress $prog"
    TICK_QUIET_MTIME="$(epoch_iso "$pm")"
    TICK_QUIET_AGE="$OBS_PROGRESS_AGE"
  fi

  [ "$(observe_class)" = idle ] && return 0
  return 1
}

# ---------------------------------------------------------------- the decision line
#
# THE TICK'S LAST LINE, AND THE ONLY PLACE THIS SCHEMA IS PRINTED (REQ-10 AC-10.2/10.4; D5).
# Four arms used to print it inline and three of them followed it with the sentence that
# explained it, so the last thing an operator read was never reliably the answer. One printer
# means one field order, one place a field is added, and a caller that cannot print its
# sentence afterwards by accident.
#
# `decision=` IS THE RANKED MAXIMUM DISARM > NOTIFY > FILL > QUIET. Each band is raised by a
# fact this tick computed; the highest wins the field and every lower one keeps its own, so a
# tick that ordered work and found an overdue row reports both rather than whichever arm ran
# first. DISARM is terminal and exits above the fold, so the fold there is over three.
#
# THE SCHEMA NAME IS UNCHANGED AND THE NEW FIELDS ARE TRAILING (A2). `fill=` and `trees=`
# print only when they carry something: a reader that does not know them is inert to them,
# and the existing `decision=|total=|open=` run stays byte-adjacent for the readers that
# match on it (tests/cross-gate-agreement.test.sh's `la6_open_tick`). `rows=`/`detail=` keep
# their positions, which is why they are passed through this printer rather than appended by
# the NOTIFY arm. `gate=` (wave-25 T5; D7) is the last of them: how many reserved requests this
# tick raises and their categories, `gate=1:leaves-the-machine`.
tick_decision_line() {  # <decision> <total> <open> [rows] [detail] [fill ids] [tree paths] [gate]
  local line
  line="$(printf '%s|at=%s|session=%s|decision=%s|total=%s|open=%s' \
    "$POKER_DECISION_SCHEMA" "$(iso_now)" "$SESSION_ID" "$1" "$2" "$3")"
  [ -n "${4:-}" ] && line="${line}|rows=${4}"
  [ -n "${5:-}" ] && line="${line}|detail=${5}"
  [ -n "${6:-}" ] && line="${line}|fill=${6}"
  [ -n "${7:-}" ] && line="${line}|trees=${7}"
  [ -n "${8:-}" ] && line="${line}|gate=${8}"
  printf '%s\n' "$line"
}

  poker_verb_arm() {
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "A Patrol stamp answers for ONE session, so without the key there is nothing to write."
      exit 3
    fi
    if ! write_patrol_stamp "$SESSION_ID" arm; then
      die "REFUSED — the Patrol stamp could not be written; this session is NOT armed."
      die "Check that .bionic/tmp is a writable real directory under the project root."
      exit 2
    fi
    # THE SECOND HALF OF ARMING: the instant, recorded so a later tick can tell THIS run's
    # delivery from the previous one's (R-13). Advisory — a session armed without it keeps
    # ticking and never auto-DISARMs, which is the safe direction — so it warns and the arm
    # still stands.
    write_patrol_armed_marker "$SESSION_ID" \
      || die "WARN — the arming instant could not be recorded; this Patrol will not auto-DISARM (run \`disarm\` to stop it)."
    # THE PROMPT VERSION THIS ARM PAIRS WITH (wave-24 T7; D5). An arm follows the CronCreate of
    # `prompt`'s output, so the version this poker prints is the one the job now carries. The
    # digest it replaces is dropped with it: the first tick after an arm prints in full. The gate
    # requests already raised are kept (wave-25 T5): a re-arm is not a reason to raise them again.
    write_tick_digest "$SESSION_ID" "$PATROL_PROMPT_VERSION" "" "" "" "" \
      "$(tick_digest_field "$(tick_digest_file "$SESSION_ID")" gate_raised)" \
      || die "WARN — the prompt version could not be recorded; the tick will ask for a re-arm."
    say "armed — the Patrol stamp is fresh for this session: $(patrol_stamp_file "$SESSION_ID")"
    exit 0
  }

  # THE DELIBERATE STOP. Paired with `CronDelete` at run close (the ritual is stated in
  # skills/canonical-sdlc/SKILL.md §Dispatch, and both halves belong to it): `CronDelete`
  # stops the firing, this stops the CLAIM that something is still firing. Either half
  # alone leaves a Patrol that is half-stopped in the direction that lies.
  #
  # IDEMPOTENT, AND SILENT ABOUT NOTHING. A ritual is a thing a model runs from a list, so
  # running it twice, or on a session that never armed, answers 0 and says which of the two
  # it was — a no-op reported as a failure is a line the operator has to stop and interpret
  # at exactly the moment the run is trying to end.
  poker_verb_disarm() {
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "A Patrol stamp answers for ONE session, so without the key there is nothing to remove."
      exit 3
    fi
    DISARM_STAMP="$(patrol_stamp_file "$SESSION_ID")" || DISARM_STAMP=""
    if [ -n "$DISARM_STAMP" ] && [ -f "$DISARM_STAMP" ] && [ ! -L "$DISARM_STAMP" ]; then
      if remove_patrol_stamp "$SESSION_ID"; then
        say "disarmed — the Patrol stamp for this session is removed: $DISARM_STAMP"
        say "CronDelete the Patrol job too if it is still in the table; this half only stops the claim that it fires."
        exit 0
      fi
      die "REFUSED — the Patrol stamp could not be removed, so this session still reads as armed."
      die "Remove it by hand or the death notice keeps firing every turn: $DISARM_STAMP"
      exit 2
    fi
    say "already disarmed — no Patrol stamp for this session${DISARM_STAMP:+: $DISARM_STAMP}"
    exit 0
  }

  poker_verb_tick() {
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "A tick answers for ONE session's roster, so without the key there is nothing to read."
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

    # THE WALK, TAKEN BEFORE THE STAMP IS WRITTEN, and that ordering is load-bearing.
    # `write_patrol_stamp` mkdir -p's `<resolved root>/.bionic/tmp`, so a tick that resolved
    # the WRONG root creates a `.bionic` there as its first act — and every walk taken after
    # that point reports the root it just manufactured as `chosen`. Read here, the walk still
    # describes the filesystem the tick actually arrived in, which is the only version of it
    # an operator can act on and the one AC-38's two arms are told apart by.
    TICK_ROOT_WALK="$(project_root_candidates "$PWD")"
    TICK_ROOT_TAG="$(printf '%s\n' "$TICK_ROOT_WALK" | tail -1 | awk -F'\t' '{ print $2 }')"

    # STAMP FIRST, BEFORE ANYTHING IS READ OR DECIDED. Every line below this one can end in
    # a refusal, and each of those refusals is a HEALTHY Patrol firing into a state it has
    # nothing to say about. What the stamp attests is the firing, so it is taken here — the
    # first thing after the session key exists to name the file with.
    write_patrol_stamp "$SESSION_ID" tick \
      || die "WARN — the Patrol stamp could not be written; the tick itself is unaffected."

    # ---------- THE TICK SAYS WHAT CHANGED, OR "unchanged" (wave-24 T7, REQ-4; D4, D5) ----------
    #
    # THE DEFECT (research-R1). Every tick printed its whole reading — the rung, the holds, the
    # stand-downs, the fill — whether or not anything had moved since the last one, and the
    # Patrol prompt asked the model to answer each of them every time. A tick over the same
    # facts now prints one line: `poker: unchanged since <at> — decision=<band>`.
    #
    # THE OUTPUT IS HELD UNTIL THE DECISION. Every line the tick prints below goes to a buffer;
    # `tick_conclude` hashes what was decided (the band, the sorted per-row verdicts, the named
    # lines, the fill, `current:`, the pressure band — never an instant) and compares it with the
    # hash `tick_digest_file` kept from the last tick. The exit trap then prints the buffer, or
    # the one line, and writes the file. A tick that exits on a refusal prints its buffer as it
    # always did and writes no digest. stderr is not held: a warning is a warning on every tick.
    #
    # THE PROMPT VERSION rides the same file: `arm` records the version its prompt carried, and a
    # tick that finds none, or an older one, prints one re-arm line above everything else.
    TICK_BUF="$(mktemp "${TMPDIR:-/tmp}/bionic-poker-tick.XXXXXX" 2>/dev/null)" || TICK_BUF=""
    # ONE REGRESSION STATE PER TICK (wave-26 T64). The schedule and the change fingerprint below each
    # parse the table under their own `units_memoised`; this names the one file both keep the
    # regression state in (lib/units.sh `_units_floor_state`), so a tick runs `proof_state` once.
    [ -z "$TICK_BUF" ] || _UNITS_MEMO_FLOOR="$TICK_BUF.floor"
    TICK_DIGEST=""; TICK_UNCHANGED=no; TICK_SINCE=""; TICK_DECIDED=""; TICK_DUTY=owed; TICK_CHANGE=""; TICK_CHANGE_STORE=""
    TICK_PLAN_CUR=""; TICK_PLAN_ROWS=""
    TICK_GATE_KEYS=""; TICK_GATE_NEW=""; TICK_GATE_FIELD=""; TICK_LANDINGS=""; TICK_RUNS_LINES=""; TICK_RUNS_KEY=""
    TICK_DIGEST_FILE="$(tick_digest_file "$SESSION_ID")" || TICK_DIGEST_FILE=""
    TICK_PVER="$(tick_digest_field "$TICK_DIGEST_FILE" prompt_version)"
    TICK_REARM=""
    # ONE RESTART LINE, FROM DOCTOR'S READER (wave-35 T5; REQ-4 AC-4.5; D13). The CLI holds hooks.json,
    # the skills, the role files and the commands as they were at its start; doctor.sh `--restart-lines`
    # is the one comparison, and the tick prints its own session's line, if any, above everything else
    # on every tick, changed or unchanged. From wave-36 T2 (D7, AC-1.3) the comparison is content: the
    # session's load record against the tree a restart loads, one line naming the classes that moved
    # (`<pid> <sid> <started> <classes> <reloaded-since|->`), and `or reloaded since <ISO>` when the
    # registry installed after the record was written.
    TICK_RESTART=""
    TICK_RESTART_ROW="$(bash "$BIONIC_LIB/../doctor.sh" --restart-lines 2>/dev/null \
      | awk -F'\t' -v s="$SESSION_ID" 'NF >= 5 && $2 == s { print; exit }')"
    if [ -n "$TICK_RESTART_ROW" ]; then
      IFS=$'\t' read -r _tr_pid _ _ _tr_classes _tr_reload <<< "$TICK_RESTART_ROW"
      if [ "${_tr_reload:--}" != - ]; then
        TICK_RESTART="restart needed — ${_tr_classes} changed after this session loaded them, or reloaded since ${_tr_reload} (pid ${_tr_pid}): exit claude and start it again"
      else
        TICK_RESTART="restart needed — ${_tr_classes} changed after this session loaded them (pid ${_tr_pid}): exit claude and start it again"
      fi
    fi
    case "$TICK_PVER" in ''|*[!0-9]*) TICK_PVER_N=0 ;; *) TICK_PVER_N="$TICK_PVER" ;; esac
    if [ "$TICK_PVER_N" -lt "$PATROL_PROMPT_VERSION" ]; then
      TICK_REARM="poker: note: re-arm the Patrol — its prompt is v=${TICK_PVER:-unrecorded} and this poker prints v=${PATROL_PROMPT_VERSION}: replace the bionic-patrol job with one carrying the output of \`bash ${POKER_WORD} prompt\`, then run \`bash ${POKER_WORD} arm\`"
    fi
    tick_emit() {
      local rc=$?
      [ -n "$TICK_BUF" ] || exit "$rc"
      exec 1>&3 3>&-
      [ -z "${TICK_RESTART:-}" ] || say "$TICK_RESTART"
      if [ -n "$TICK_DIGEST" ] && [ -n "$TICK_REARM" ]; then
        printf '%s\n' "$TICK_REARM"
      fi
      [ -z "${TICK_DECIDED:-}" ] || sitrep_tick_line "${SCHED_PLAN:-}"  # THE TICK'S ONE-LINE SITREP, EVERY TICK (wave-38 T11; D13)
      if [ "$TICK_UNCHANGED" = yes ]; then
        # EVERY STANDING HOLD RIDES THE UNCHANGED TICK (wave-35 T5; REQ-4 AC-4.4; D13). The backstop runs
        # on every tick and says its NOT-LANDED lines into the buffer; an equal digest means the world
        # did not move, not that the duty is paid, so the holds it re-found print above the one line.
        /usr/bin/grep '^poker: NOT-LANDED ' "$TICK_BUF" 2>/dev/null
        say "unchanged since ${TICK_SINCE} — decision=${TICK_DECIDED}"
      else
        # THE RUN'S LANDING LINE PRINTS IN THE RE-ARM SLOT, ABOVE THE BUFFER (wave-28 T14, T62, T68; D18, AC-10.4):
        # the buffer ends with the decision line, which is the tick's last line, so this line is printed before it
        # and never after. A landing moves no decision (RP4), so it never makes a tick changed: the line shows on the
        # ticks that print in full for another reason, and an `unchanged` tick stays the one line the Patrol ends on.
        [ -z "$TICK_LANDINGS" ] || say "$TICK_LANDINGS"
        [ -z "${TICK_RUNS_LINES:-}" ] || printf '%s\n' "$TICK_RUNS_LINES"
        cat "$TICK_BUF" 2>/dev/null
        # A START IS TOLD BY THE TICK THAT PRINTED ITS LINE (wave-27 T37; review pass 36 S1).
        [ -z "${US_TOLD_PENDING:-}" ] || printf '%s' "$US_TOLD_PENDING" >> "$ROSTER_FILE" 2>/dev/null
      fi
      rm -f "$TICK_BUF" "$TICK_BUF.floor" 2>/dev/null
      if [ -n "$TICK_DIGEST" ]; then
        write_tick_digest "$SESSION_ID" "$TICK_PVER" "$TICK_DIGEST" "$TICK_SINCE" "$TICK_DECIDED" "$TICK_DUTY" "$TICK_GATE_KEYS" "$TICK_CHANGE_STORE" "${UNITS_LIVE_HEAD:-}" "$TICK_PLAN_CUR" "$TICK_PLAN_ROWS" "${UNITS_FACTS_STATE:-}" "${TICK_RECONCILE:-}" \
          || die "WARN — the tick digest could not be written; the next tick prints in full."
      fi
      exit "$rc"
    }
    if [ -n "$TICK_BUF" ]; then
      exec 3>&1 1>"$TICK_BUF"
      trap tick_emit EXIT
    fi

    # THE DECISION, HASHED (D4). Called once, by whichever arm decides, BEFORE that arm prints
    # its sentence and its decision line — so the buffer holds exactly the lines the decision
    # was reached on. What enters the hash: the band, the decision line's counts and lists, the
    # pressure band (its state and rung), `current:`, every row's verdict as `name|state|acked`
    # sorted, and the named lines the tick printed reduced to their kind and subject (a
    # STANDDOWN, a held row, a GONE report, a duplicate tell, an ext: hold, a ledger finding, a
    # note). Never an instant, an age or a measurement: those move on every tick by themselves.
    # DISARM is terminal and a tick over the share names what holds the memory, so both always
    # print in full.
    #
    # THE GATE (wave-25 T5; D7). A pending gate request raises the band to NOTIFY unless it is
    # DISARM, which outranks it; the caller passes the band it reached without the gate and reads
    # the answer back from TICK_DECIDED. The hash takes that band and the keys of every request in
    # the gate file, raised or not, so the tick after the one that raised a request hashes the
    # same and prints the unchanged line; a new request is a new key and prints in full. No file,
    # or one with no request in it, adds nothing to the hash.
    #
    # THE DUTY (wave-26 T15, REQ-4 AC-4.5; D16, research-R2 §3 P4). The task-list refresh is
    # owed only when a `## Tasks` row's status or the ready set moved since the last tick: that
    # is what the ledger can fall behind on. A tick whose news is a progress file's age, a load
    # band or a roster row's liveness prints in full and owes nothing. `TICK_CHANGE` is that
    # fingerprint, kept in the digest as `change=` beside the whole-decision hash and entered
    # into it too, so a tick that says `unchanged` has, by construction, nothing to reconcile.
    # A QUIET tick owes no reconcile for a status move: with a row open it prints WAITING, which
    # asks for nothing, and with none open there is nothing running to reconcile against
    # (A-orch-4). It does owe one when the plan MOVED (`tick_plan_moved`, below). The stop wall's
    # collector reads this line, so a turn is not refused for a chore with nothing behind it.
    tick_change_rows() {  # -> the plan's id|status lines in table order, then its ready set
      units_rows "$SCHED_PLAN" 2>/dev/null | awk -F'\t' 'NF { print $1 "|" $10 }'
      printf 'ready=%s\n' "$(fill_ready_set "$SCHED_PLAN" 99999 0 2>/dev/null | tr '\n' ' ')"
    }
    # THE TASK LIST IS REBUILT AT PLAN APPROVAL (wave-27 T13; D20; steps/3.md). No hook reads a
    # task list, so this line is all the rule has (advice: no wall reads it since wave-31 T32): it is also owed when the
    # plan's `current:` was 3 at the last digest and is 4 now, or its row count has grown, and
    # it is owed on a QUIET tick too (a plan at approval has nothing open yet).
    # WHICH MOVE IT WAS (wave-27 T37; review pass 8 F2) is TICK_RECONCILE, `step4` or `grew`: the
    # RECONCILE line says it and names the rebuild, and the digest keeps it as `reconcile=` (read by
    # no wall since wave-31 T32; D6: the line is advice). A move into Step 4 is named first when
    # the table also grew: the rebuild it asks for covers the new rows.
    TICK_RECONCILE=""
    tick_plan_moved() {  # -> 0 when the digest's last reading of the plan is behind this one
      local pc pr
      TICK_RECONCILE=""
      pc="$(tick_digest_field "$TICK_DIGEST_FILE" plan_current)"
      pr="$(tick_digest_field "$TICK_DIGEST_FILE" plan_rows)"
      if [ "$pc" = 3 ] && [ "$TICK_PLAN_CUR" = 4 ]; then TICK_RECONCILE=step4; return 0; fi
      case "$pr" in ''|*[!0-9]*) return 1 ;; esac
      [ -n "$TICK_PLAN_ROWS" ] && [ "$TICK_PLAN_ROWS" -gt "$pr" ] || return 1
      TICK_RECONCILE=grew
    }
    tick_conclude() {  # <decision before the gate>
      local cur="" prev=""
      TICK_DECIDED="$1"
      if [ -n "$TICK_GATE_NEW" ] && [ "$1" != DISARM ]; then
        TICK_DECIDED=NOTIFY
      fi
      if [ -n "${SCHED_PLAN:-}" ] && [ -f "${SCHED_PLAN:-}" ]; then
        cur="$(_sched_plan_current_field "$SCHED_PLAN")"
      fi
      TICK_CHANGE="none"
      if [ -n "${SCHED_PLAN:-}" ] && [ -f "${SCHED_PLAN:-}" ] && [ "$POKER_RUN_OPEN" != unreadable ]; then
        TICK_CHANGE="$(tick_plan_memoised tick_change_rows | cksum | awk '{ print $1 "-" $2 }')"
        TICK_PLAN_CUR="$(sched_plan_current "$SCHED_PLAN")"
        TICK_PLAN_ROWS="$(tick_plan_memoised tick_change_rows | grep -vc '^ready=')"
      fi
      if [ -n "$TICK_BUF" ]; then
        TICK_DIGEST="$( {
          printf 'change=%s\n' "$TICK_CHANGE"
          printf 'decision=%s|total=%s|open=%s|notify=%s|fill=%s|trees=%s\n' "$1" "$TOTAL" "$OPEN" \
            "${NOTIFY_ROWS:-}" "${SCHED_FILL:-}" "${LEASE_TREES:-}"
          printf 'room=%s|current=%s\n' "${SCHED_GATE_ROOM:-}" "$cur"
          [ -z "$TICK_GATE_KEYS" ] || printf 'gate=%s\n' "$TICK_GATE_KEYS"
          # THE RUNS (wave-30 T12): the full-run count and each live run of this roster, by name and id.
          [ -z "${TICK_RUNS_KEY:-}" ] || printf '%s\n' "$TICK_RUNS_KEY"
          printf '%s\n' "$VERDICT_OUT" | awk -F'|' '
            $1 == "landing-verdict/v1" {
              n = ""; st = ""; ak = ""
              for (i = 2; i <= NF; i++) {
                if (index($i, "name=") == 1) n = substr($i, 6)
                else if (index($i, "state=") == 1) st = substr($i, 7)
                else if (index($i, "acked=") == 1) ak = substr($i, 7)
              }
              print n "|" st "|" ak
            }' | LC_ALL=C sort
          # A reader started without its checks: the whole line, and the ids beside it (T37; S1).
          [ -z "${US_NOTIFY_IDS:-}" ] || printf 'unchecked=%s\n' "$US_NOTIFY_IDS"
          awk '
            $1 != "poker:" { next }
            $2 == "note:" { print $3, $4, $5; next }
            $2 == "NOTIFY" && index($0, " started without its checks: ") > 0 { print; next }
            $2 ~ /^(STANDDOWN|held|GONE|GONE\?|DUPLICATE-SESSION|DUPLICATE-START|HELD|LEDGER|LAUNCHED|NOT-RECORDED|RANGE|NOTIFY|SPLIT)$/ { print $2, $3, $4 }
            # An open check is told once (wave-28 T41; D33): a new one, or one settled, moves the hash.
            $2 == "FINDING" && $6 == "check" { print $2, $3, $6 }
          ' "$TICK_BUF" | LC_ALL=C sort
        } | cksum | awk '{ print $1 "-" $2 }' )"
      fi
      # THE STORED FINGERPRINT IS THE LAST ONE A DUTY WAS JUDGED AGAINST (wave-26 T32; review-6
      # F1). A QUIET tick owes nothing, so it writes back the value it read: a status move it saw
      # first is still owed by the next tick that can owe it. Through T15 every tick wrote its own,
      # and a move first seen while the run WAITED was used up. The whole-decision hash above still
      # takes this tick's own fingerprint, so a QUIET tick over a move prints in full. With no
      # value stored yet (the first tick after an arm), the QUIET tick's own is the baseline.
      TICK_CHANGE_STORE="$TICK_CHANGE"
      if [ "$TICK_DECIDED" = QUIET ]; then
        prev="$(tick_digest_field "$TICK_DIGEST_FILE" change)"
        [ -n "$prev" ] && TICK_CHANGE_STORE="$prev"
      fi
      prev="$(tick_digest_field "$TICK_DIGEST_FILE" digest)"
      if [ -n "$TICK_DIGEST" ] && [ "$1" != DISARM ] && [ "${SCHED_OVER:-}" != yes ] \
         && [ -z "$TICK_GATE_NEW" ] && [ "$TICK_DIGEST" = "$prev" ]; then
        TICK_UNCHANGED=yes
        TICK_SINCE="$(tick_digest_field "$TICK_DIGEST_FILE" since)"
        [ -n "$TICK_SINCE" ] || TICK_SINCE="$(iso_now)"
        TICK_DUTY=none
        return 0
      fi
      TICK_SINCE="$(iso_now)"
      TICK_DUTY=none
      # THE DUTY IS PRINTED (wave-26 T32; review-6 F2). It used to live only in the digest
      # file, so the Patrol prompt asked for the refresh on a change the model could not see.
      # The prompt and the stop wall's refusal both name this line. A plan move is asked first,
      # in its own words (wave-27 T37): a status change beside it is covered by the rebuild.
      if tick_plan_moved; then
        TICK_DUTY=owed
        case "$TICK_RECONCILE" in
          step4) say "RECONCILE — the plan moved from approval into Step 4 since the last tick: TaskList, and rebuild the task list in execution order (delete every pending entry and recreate them)" ;;
          *)     say "RECONCILE — the ## Tasks table grew since the last tick: TaskList, and rebuild the task list in execution order (delete the pending entries after the new row and recreate them)" ;;
        esac
      elif [ "$TICK_DECIDED" != QUIET ] && [ "$TICK_CHANGE" != "$(tick_digest_field "$TICK_DIGEST_FILE" change)" ]; then
        TICK_DUTY=owed
        say "RECONCILE — a ## Tasks status or the ready set changed since the last tick: TaskList, and bring the task list in line with the plan"
      fi
      tick_write_orders
      return 0
    }

    # THE RANKED BAND, ONE COPY FOR BOTH ARMS THAT DECIDE (REQ-10 AC-10.2, D5; wave-26 T59). The
    # roster arm and the armed first tick both rank this tick's contributors here, so the
    # decision line agrees with what the tick printed whichever arm printed it: a first tick
    # that named a FILL decides FILL, with the same `fill=` field. The ranking and its reasons
    # are documented where the roster arm calls it.
    tick_band() {  # -> TICK_DECISION, the band left standing once tick_conclude has run
      TICK_DECISION=QUIET
      [ -n "$SD_ORDER_NAMES" ] && TICK_DECISION=STANDDOWN
      [ -n "${SCHED_FILL:-}" ] && TICK_DECISION=FILL
      [ -n "$NOTIFY_ROWS" ] && TICK_DECISION=NOTIFY
      # A PENDING GATE REQUEST IS THE THIRD CONTRIBUTOR (wave-25 T5; D7): tick_conclude raises the
      # band to NOTIFY for it, so the band is read back from there.
      tick_conclude "$TICK_DECISION"
      TICK_DECISION="$TICK_DECIDED"
    }
    # THE FILL BAND'S OWN SENTENCE. The `poker: FILL <ids>` line the duty wall reads was printed
    # by the scheduler where it was decided; this says what the decision line then says, so the
    # two channels agree on one tick (D5).
    #
    # AND THE READY ROWS BEHIND THE GAP (wave-28 T74; A-orch-226). The rows the width parked (`WAIT <id> — ready; no
    # writer slot free`) are named too, because a FILL row made to wait frees its slot and the stop wall then asks
    # for them, in the same turn. The `poker: FILL <ids>` line keeps its own ids.
    tick_fill_sentence() {
      say "FILL — ${SCHED_FILL} named for dispatch; the decision line carries them${SCHED_BEHIND:+ · behind the gap: ${SCHED_BEHIND} — a FILL row made to wait frees its slot for them; dispatch them, or make each wait, in the same turn}."
    }

    # THE STOP ORDERS THIS TICK OWES, written once the decision is known (wave-24 T7; D1, D4). An
    # unchanged tick writes none: the stop wall reads its stand-down set off this tick's orders,
    # and a turn told only "unchanged" must not be refused for a STANDDOWN it was never shown.
    # The answer the last turn gave stands until a fact moves.
    SD_ORDER_NAMES=""
    tick_write_orders() {
      local n out
      for n in $SD_ORDER_NAMES; do
        if [ -f "$ORDERS" ]; then
          out=$( cd "$REPO_REAL" 2>/dev/null || exit 9
                 CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
                 bash "$ORDERS" order "$n" --by patrol 2>&1 ) \
            || say "STANDDOWN ${n} — the order could NOT be written, so the stop gate will still ask: $(clean "$(printf '%s' "$out" | head -1)")"
        else
          say "STANDDOWN ${n} — sibling hooks/stop-orders.sh not found, so no order was written; order it yourself before stopping."
        fi
      done
      return 0
    }

    # The sweeper is this script's sibling — same resolution as hooks/landing-gate.sh's.
    SWEEPER="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/session-sweeper.sh"
    if [ ! -f "$SWEEPER" ]; then
      die "REFUSED — sibling hooks/session-sweeper.sh not found; nothing was read."
      exit 2
    fi
    # THE ORDER WRITER, resolved the same way and NOT required to exist. The tick's whole
    # value is the reading it does from the roster; a missing sibling costs the stand-down
    # its order (and says so, once, on the row it was for) rather than costing the session
    # its tick. The sweeper above is required because nothing can be decided without it.
    ORDERS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/stop-orders.sh"

    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    ROSTER_FILE="$REPO_REAL/.bionic/tmp/roster-${SESSION_ID}.state"

    # ---------- THE LAUNCHES THE PLAN LACKS, WRITTEN BEFORE THE PLAN IS READ (wave-26 T32; D4) ----
    #
    # The launch recorder starts `launch-sync` and does not wait for it, so the tick runs the same
    # transaction before anything below reads the plan: a launch the detached call did not record
    # is recorded here (its LAUNCHED line enters this tick's output and its status this tick's
    # change fingerprint), and one that cannot be recorded prints its NOT-RECORDED line and the
    # commands to run by hand. A child process, as the recorder runs it: its refusals exit, and a
    # tick must not. It leaves a lock another writer holds to that writer.
    if [ -f "$ROSTER_FILE" ]; then
      ( cd "$REPO_REAL" && CLAUDE_CODE_SESSION_ID="$SESSION_ID" "${BASH:-bash}" "$HOOK_DIR/session-poker.sh" launch-sync 2>&1 ) || :
    fi
    # The recorder's detached call has a log of its own; its failure is told once, outside the held output, so an
    # unchanged tick still says it (wave-36 T12; D13, AC-7.1).
    if [ -n "$TICK_BUF" ]; then tick_launch_sync_failed "$REPO_REAL" "$SESSION_ID" >&3
    else tick_launch_sync_failed "$REPO_REAL" "$SESSION_ID"; fi

    # ---------- THE LINE'S STANDING REDS AND STALLED ENTRIES, EACH TOLD ONCE (wave-28 T5; D8) ----------
    #
    # `ready` (lib/line.sh) appends `standing` when a red fails at the accepted head too, so the
    # branch's and not a row's, and `stalled` when an entry's suite twice gave no verdict and `ready`
    # exited 70. The first tick that reads one off the bound plan's landing record prints it as a note,
    # with its logs; the event line then goes into `.bionic/tmp/line-told-<sid>.state` and is never
    # printed again. A note enters the decision's hash, so the tick that tells one prints in full.
    resolve_run "$REPO_REAL" "$SESSION_ID"

    # ---------- THE RUNS: regression-runs AND EVERY LIVE RUN OF THIS ROSTER (wave-30 T12; D6, D7d) ----------
    #
    # `poker: regression-runs=<n>` is the count of full-runner runs the project's rosters record
    # (REQ-4 AC-4.6, `regression_runs_count`), and a `poker: RUNNING <name> run=<id> pid=<pid>
    # elapsed=<s>s progress: <line>` line names each row of this roster whose detached run is alive,
    # with the run's last progress line (AC-3.8). Both print above the buffer on every tick that
    # prints in full, as the landing line does, and both enter the decision's hash (TICK_RUNS_KEY): a
    # new full run, or a run starting or ending, is news, so the tick after it prints in full, and an
    # unchanged tick stays the one line it is (AC-4.9 of wave-24). THE HEADER: when the bound plan's
    # `regression-runs:` holds another number, the tick runs `regression-runs --write`, the
    # transaction, in a child as it runs launch-sync: a hand-typed value does not outlive the tick.
    TICK_RR="$(regression_runs_count "$REPO_REAL")"
    TICK_RUNS_LINES="poker: regression-runs=$TICK_RR"
    TICK_RUNS_KEY="regression-runs=$TICK_RR"
    if [ -f "$ROSTER_FILE" ] && [ ! -L "$ROSTER_FILE" ]; then
      for TR_NAME in $(awk -F'|' '/[|]run_log=/ { for (i = 1; i <= NF; i++) if (index($i, "name=") == 1) print substr($i, 6) }' "$ROSTER_FILE" | LC_ALL=C sort -u); do
        run_load_row "$(run_row_of "$ROSTER_FILE" "$TR_NAME")" "$ROSTER_FILE" || continue
        run_read
        [ "$RUN_STATE" = RUNNING ] || continue
        TICK_RUNS_LINES="$TICK_RUNS_LINES
poker: RUNNING $TR_NAME run=$RUN_ID pid=$RUN_PID elapsed=${RUN_ELAPSED:-?}s progress: ${RUN_PROGRESS:-none yet}"
        TICK_RUNS_KEY="$TICK_RUNS_KEY
RUNNING $TR_NAME $RUN_ID"
      done
    fi
    if [ "$POKER_RUN_OPEN" = yes ] && [ -f "$POKER_RUN_PLAN" ]; then
      TICK_RR_HAVE="$(plan_frontmatter_get "$POKER_RUN_PLAN" regression-runs)"
      if [ -n "$TICK_RR_HAVE" ] && [ "$TICK_RR_HAVE" != "$TICK_RR" ]; then
        ( cd "$REPO_REAL" && CLAUDE_CODE_SESSION_ID="$SESSION_ID" "${BASH:-bash}" "$HOOK_DIR/session-poker.sh" regression-runs --write 2>&1 ) || :
      fi
    fi
    LT_TOLD="$REPO_REAL/.bionic/tmp/line-told-${SESSION_ID}.state"
    LT_REC=""
    [ -z "$POKER_RUN_PLAN" ] \
      || LT_REC="$(docs_root "$REPO_REAL" 2>/dev/null)/record/$(proof_plan_slug "$POKER_RUN_PLAN")/landing-proofs.log"
    [ -z "$LT_REC" ] || [ ! -f "$LT_REC" ] || declare -F line_value >/dev/null 2>&1 \
      || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1
    if [ -n "$LT_REC" ] && [ -f "$LT_REC" ] && [ ! -L "$LT_TOLD" ] && tmp_dir_ok "${LT_TOLD%/*}" && declare -F line_value >/dev/null 2>&1; then
      lt_f() { line_value "$LT_EV" "$1"; }   # <key> -> its value in the event
      while IFS= read -r LT_EV; do
        [ -n "$LT_EV" ] || continue
        [ -f "$LT_TOLD" ] && /usr/bin/grep -qxF -- "$LT_EV" "$LT_TOLD" && continue
        case "$(lt_f ev)" in
          standing) LT_H="$(lt_f head)"
            note "standing $(lt_f suite) at ${LT_H:0:12} — $(lt_f lines) failing line(s) fail at the accepted head too: a red the branch carries, not one a row added; log $(lt_f log)" ;;
          *) note "stalled $(lt_f row) — two runs ended with no verdict and no third starts; logs $(lt_f logs)" ;;
        esac
        printf '%s\n' "$LT_EV" >> "$LT_TOLD"
      done <<EOF
$(awk -F'|' "${_LINE_FIELDS_AWK:-}"'{ e = line_ev() } e == "standing" || e == "stalled"' "$LT_REC" 2>/dev/null)
EOF
    fi
    # THE RUN'S LANDING LINE (wave-28 T14; D18): the report's first line, once the record holds a landing.
    # It is printed by the exit trap above the buffer, in the re-arm slot, so the decision stays the last line, and it enters no hash.
    if [ -n "$LT_REC" ] && { awk -F'|' "${_LINE_FIELDS_AWK:-}"'line_ev() == "published" { f = 1; exit } END { exit !f }' "$LT_REC" 2>/dev/null \
      || landing_unmeasured "$LT_REC"; }; then
      TICK_LANDINGS="$(landing_report "$LT_REC" "$REPO_REAL" no 2>/dev/null | head -1)"
    fi
    [ -z "$LT_REC" ] || tick_owed_goals "$POKER_RUN_PLAN" "$LT_REC"

    # ---------- THE GATE REQUESTS, READ ONCE (wave-25 T5, REQ-4 AC-4.3; D7) ----------
    #
    # Read here, above every arm that decides, so the armed tick before any dispatch and the
    # DISARM tick see the same requests as the full one. `gate_requests` (above) says which are
    # pending; the keys of all of them become the digest's `gate_raised=` when this tick writes
    # it, which is what makes the next tick read them as raised. No file is nothing pending.
    # A symlinked file, or one under a symlinked `.bionic/tmp`, is refused as the roster files
    # are and says so in a note; the set already raised is kept, so replacing the link with the
    # real file later does not raise them all a second time.
    TICK_GATE_FILE="$REPO_REAL/.bionic/tmp/gate-${SESSION_ID}.state"
    if [ -L "$TICK_GATE_FILE" ] || ! tmp_dir_ok "${TICK_GATE_FILE%/*}"; then
      TICK_GATE_KEYS="$(tick_digest_field "$TICK_DIGEST_FILE" gate_raised)"
      note "gate file ${TICK_GATE_FILE} is a symlink or sits under one — not read, so no reserved request is raised from it"
    elif [ -f "$TICK_GATE_FILE" ]; then
      TICK_GATE_ROWS="$(gate_requests "$TICK_GATE_FILE" "$SESSION_ID" "$(tick_digest_field "$TICK_DIGEST_FILE" gate_raised)")"
      TICK_GATE_KEYS="$(printf '%s\n' "$TICK_GATE_ROWS" | awk -F'\t' 'NF { printf "%s%s", (n++ ? "," : ""), $1 }')"
      TICK_GATE_NEW="$(printf '%s\n' "$TICK_GATE_ROWS" | awk -F'\t' '$2 == "new"')"
    fi
    # THE GATE ITEM'S CLOSER (wave-33 T12; REQ-2 AC-2.3, D2): a `gate:<key>` item on the person's
    # ledger is closed when the gate is no longer raised, which is when its key is not in the keys
    # just read (`gate_raised=` for the next digest). A request that left the gate file, or a gate
    # file that is gone, closes its item; a request still in the file keeps its item, and the
    # refused-file branch above kept the digest's own keys, so a symlink closes nothing. Silent,
    # never fatal, and a library without owed.sh does nothing.
    tick_gate_close() {
      local gkey
      declare -F owed_list >/dev/null 2>&1 || return 0
      declare -F owed_close >/dev/null 2>&1 || return 0
      for gkey in $(OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_list 2>/dev/null | cut -f1 | /usr/bin/grep '^gate:'); do
        case ",${TICK_GATE_KEYS}," in *",${gkey#gate:},"*) continue ;; esac
        OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_close "$gkey" "gate cleared" >/dev/null 2>&1
      done
      return 0
    }
    tick_gate_close
    # THE FIELD: how many requests this tick raises, then their categories sorted and once each,
    # `gate=2:credentials,leaves-the-machine`. The commands are on the GATE lines, not here.
    if [ -n "$TICK_GATE_NEW" ]; then
      TICK_GATE_FIELD="$(printf '%s\n' "$TICK_GATE_NEW" | awk -F'\t' '{ print $4 }' | LC_ALL=C sort -u \
        | awk -v n="$(printf '%s\n' "$TICK_GATE_NEW" | grep -c .)" '{ c = c (NR > 1 ? "," : "") $0 } END { printf "%d:%s", n, c }')"
    fi
    # THE GATE LINES, printed by whichever arm decides, after its tick_conclude: one sentence that
    # says what the turn owes, then one line per request this tick raises, asker, category and
    # command head. A request already raised prints nothing; the file still holds it.
    #
    # EACH GATE LINE IS OWED TO THE PERSON (wave-33 T11; REQ-2 AC-2.3, D2): the request opens
    # `gate:<key>` on the person's ledger, the key `gate_raised=` keeps, carrying the line printed,
    # and the tick sends the gate items it opened through the one sender, once each. The send is
    # silent and never fatal, so the lines above and the exit code are what they were.
    tick_gate_report() {
      local k st a c h
      [ -n "$TICK_GATE_NEW" ] || return 0
      say "gate act — ${TICK_GATE_FIELD%%:*} reserved request(s) bionic denied: put each GATE line below to the human once, through the human's own notify channel, and do not perform it."
      while IFS="$(printf '\t')" read -r k st a c h; do
        [ -n "$k" ] || continue
        say "GATE ${a} — ${c}: ${h}"
        if declare -F owed_open >/dev/null 2>&1; then
          OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_open "gate:$k" "gate act: ${c}" "poker: GATE ${a} — ${c}: ${h}" >/dev/null 2>&1
        fi
      done <<EOF
$TICK_GATE_NEW
EOF
      if declare -F owed_send >/dev/null 2>&1; then
        OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_send gate: >/dev/null 2>&1
      fi
      return 0
    }

    # THE BLIND-WALL CHECK IS GONE (bionic 1.4.0, spec AC-7). It compared main-thread
    # `Agent` tool_uses in the transcript against rows on the roster and raised a NOTIFY
    # when dispatches outnumbered them, on the reasoning that the dispatch wall lived in
    # the governing skill's frontmatter and therefore died with a `/clear`, a continue or
    # a `/reload-plugins`. Every wall is registered in hooks/hooks.json now and survives
    # all three, so the condition it detected cannot arise the way it did — while its
    # false positive could and did: the check had no "no active run" branch, so a session
    # that had simply not engaged a run read as a session whose wall had died (observed
    # 20:07Z, 2026-09-02). A diagnosis for a failure mode the registration change removes,
    # firing on sessions that have nothing wrong with them, is worth less than nothing.

    # EXACTLY ONE verdict read over the whole roster (no name argument), run from the repo
    # root exactly as landing-gate.sh runs it. `|| exit 9` keeps a failed `cd` out of the
    # exit-1 band, which is NOTIFY's alone.
    VERDICT_OUT=$( cd "$REPO_REAL" 2>/dev/null || exit 9
                   CLAUDE_CODE_SESSION_ID="$SESSION_ID" bash "$SWEEPER" verdict 2>&1 )
    VERDICT_RC=$?
    if [ "$VERDICT_RC" -eq 9 ]; then
      die "REFUSED — could not enter $REPO_REAL to read the roster."
      exit 2
    fi
    # 2 (a refusal the sweeper itself raised — a symlinked roster or ledger) and 3 (no
    # session key, unreachable here since SESSION_ID was already checked) propagate
    # verbatim: a tick that cannot trust its one read has nothing to decide from.
    if [ "$VERDICT_RC" -eq 2 ] || [ "$VERDICT_RC" -eq 3 ]; then
      die "REFUSED — the verdict read did not complete: $VERDICT_OUT"
      exit "$VERDICT_RC"
    fi

    TOTAL=0; OPEN=0; NOTIFY_ROWS=""; NOTIFY_DETAIL=""
    # THE CADENCE HALF OF THE NOTIFY DETAIL, kept apart from the duration half so each gets
    # the sentence that describes it and the machine line gets both (REQ-10 AC-10.1).
    QUIET_DETAIL=""
    # THE MET LINEAGES THIS SESSION HAS NOT CLOSED (T22, A-orch-33). `payload/scripts/lib/stop.sh`
    # used to refuse the end of a Patrol turn until the transcript showed a ListAgents call —
    # a chore demanded of the model before a gate would judge, which is the rule ADR-024
    # exists to end. The obligation behind it was real: eighteen finished agents once sat
    # idle on one panel because nobody stopped them. It is answered here instead, from the
    # roster, by the one process that already walks every row and every verdict.
    STANDDOWN_NAMES=""
    # THE NAMES THIS SESSION HAS ALREADY CLOSED, carried out of the walk (T1, D2). Two
    # readers below need it — the stand-down arm, which must not close a row twice, and the
    # DUPLICATE-START tell, which repeated for the life of the session because it applied no
    # ack filter at all. The verdict line this loop is already reading is the one place that
    # says so: the ack ledger has exactly ONE reader in the fleet and it is not this file
    # (hooks/session-sweeper.sh:817). `clean` has already folded `|` out of every name, so a
    # `|`-delimited blob cannot be forged by a roster value.
    TICK_ACKED_NAMES="|"
    # THE SWEPT SET IS READ ONCE, BEFORE THE WALK (Step-6 delta review P1). The membership
    # test below used to be `grep -F … "$ROSTER_FILE" | grep -qF …` INSIDE the per-row loop:
    # a whole-file read and two forks per MET row, on a file that grows monotonically for the
    # life of the session — O(MET x roster), and MET rows are the majority of a wave by its
    # close. One read, then an in-shell `case`, costs the same on the first row and nothing on
    # the rest. Adds no `jq` call and no transcript read: the §19i pin is untouched.
    #
    # THE MATCH STAYS LITERAL. `grep -qF` treated the name as a fixed string; a `case` pattern
    # does too as long as the variable is QUOTED inside it, which is what keeps a roster name
    # carrying `*` or `?` from globbing against this blob.
    SWEPT_ALL="$(grep -F "$SWEPT_SCHEMA|" "$ROSTER_FILE" 2>/dev/null)"
    # The names of the rows the verdict leaves open, kept so the live set can trim them
    # AFTER this walk rather than inside it: one transcript resolution per tick, not one
    # per row, and the roster count survives as its own number (S19).
    OPEN_NAMES=""
    # THE FILL'S OCCUPANCY IS THE STOP WALL'S PREDICATE (wave-19 REQ-5, ADR-034 d2; audit V-2,
    # T2d): every roster row of this session that is NOT ACKED. `OPEN` above is a different
    # number with a different job. It drops MET/WAIVED rows, it is trimmed by liveness, and it
    # decides `open=`, QUIET and DISARM. The fill used to be sized from it, and on the
    # end-of-batch shape (a MET row whose agent is still idle on the panel, so no ack yet) the
    # tick's gap was one wider than the wall's: writers=2, one such row, two ready rows, and the
    # tick filled two where payload/scripts/lib/stop.sh demands one. The names are collected
    # here, off the verdict line (which folds the roster by name and filters by session exactly
    # as the wall's awk does), and counted AFTER the stand-down arm below has written this
    # tick's own acks. So a MET row gone from a fresh panel is closed and not counted, and a
    # MET row still listed is counted until its ack.
    TICK_UNACKED_NAMES=""
    # THE NAMES A GONE-AGENT REPORT CAN NAME (wave-19 audit V-2 delta review R2-6). An UNMET,
    # STILL-LIVE or AMBIGUOUS row that is unacked and whose agent a fresh panel does not list
    # now holds a `TICK_OCCUPIED` slot (A-T2.13) with nothing pointing at the closer T1e
    # built. This is the candidate set the stand-down arm below checks against the panel it
    # already warms for `$STANDDOWN_NAMES`; it names MET rows only, so the two sets never
    # overlap. The report never acks: the tick has no authority over an UNMET verdict (ADR-003),
    # and closing one is `stop-orders.sh stopped`'s job alone (T1e).
    GONE_CANDIDATE_NAMES=""
    # THE STATE AND DETAIL RIDE ALONG (audit V3-2). `stopped` does not accept every row in
    # the candidate set above: it refuses AMBIGUOUS unconditionally and refuses a STILL-LIVE
    # row whose own detail names a claimed process pattern still matching a live process
    # (hooks/stop-orders.sh:618-663, T1g/A-T1.13 — not exposed as a sourceable function, so
    # its acceptance predicate is mirrored below rather than re-derived; A-T2.18). The report
    # line has to know which shape a row is BEFORE it prints, so `$RSTATE` and the row's
    # `detail=` are captured here, one newline-joined `name|state|detail` record per
    # candidate, in the same pass that already reads `$LINE` for this row — never a second
    # parse of `$VERDICT_OUT` later.
    GONE_CANDIDATE_INFO=""
    while IFS= read -r LINE; do
      case "$LINE" in "landing-verdict/v1|"*) : ;; *) continue ;; esac
      TOTAL=$((TOTAL + 1))
      RNAME="$(line_field "$LINE" name)"
      RSTATE="$(line_field "$LINE" state)"

      # THE ACK CLOSES THE ROW HERE TOO, before the state is looked at at all: excluded from
      # OPEN and therefore from DISARM's precondition, and excluded from NOTIFY eligibility.
      # Read per row off the verdict line this loop is already walking — never from the
      # ledger, whose one owner is the verb that prints this line (hooks/session-sweeper.sh,
      # S9) — and spelled exactly as the three consumers that already read it:
      # hooks/landing-gate.sh:214, hooks/stop-orders.sh:319, hooks/stop-guard.sh:491.
      # This is what makes the ack verb's own closing sentence true —
      #   hooks/session-sweeper.sh:817 "an acked row is closed for every reader"
      # — which it was not while this script was the fourth reader that ignored the field
      # (cs review C-4, epic-16 w2 Step-6 remediation R4). Two structural consequences were
      # riding on the omission, both worse than the noise: an acked-UNMET row is never MET
      # and never WAIVED, and its artifact was accounted for by a human rather than written
      # to disk, so it held OPEN above zero PERMANENTLY and DISARM — the end of the
      # self-wake — was unreachable by the ordinary path that closes an artifact-less row;
      # and every tick re-notified the same closed work, growing the NOTIFY set
      # monotonically across a wave. AC-7's contract moves with this (assumption 41), which
      # is why tests/session-poker.test.sh §3 re-authors the accelerated-clock cases rather
      # than re-running them.
      #
      # TOTAL still counts an acked row: it is on the roster, and "how many contracts does
      # this session carry" is not the question the ack answers. Only `open=` moves.
      if [ "$(line_field "$LINE" acked)" = "yes" ]; then
        TICK_ACKED_NAMES="${TICK_ACKED_NAMES}$(clean "$RNAME")|"
        continue
      fi
      TICK_UNACKED_NAMES="${TICK_UNACKED_NAMES}$(clean "$RNAME")
"

      case "$RSTATE" in
        MET|WAIVED)
          # EVERY MET ROW IS A CANDIDATE, SWEPT OR NOT (T10, A-orch-20). A `landing-swept/v1`
          # marker records that a landing was SEEN, not that the agent LEFT: for a teammate it
          # is written at its own SubagentStop — the moment it reports — while it is still on
          # the panel. Excluding a swept name here made the common shape at the end of a batch
          # (every writer landed, still idle on the panel) print nothing, which is the 1.7.1
          # pile-up this arm exists to end. Presence is the panel's fact alone (spec
          # §Assumptions), and the marker never closes a name either: only the ack does
          # (wave-19 T1, ADR-034 d1), which the close below writes when a fresh panel shows
          # the agent gone.
          if [ "$RSTATE" = "MET" ]; then
            STANDDOWN_NAMES="${STANDDOWN_NAMES}${STANDDOWN_NAMES:+ }$(clean "$RNAME")"
          fi
          ;;                                  # closed — not open
        *)          OPEN=$((OPEN + 1))        # STILL-LIVE, UNMET, AMBIGUOUS — open
                    OPEN_NAMES="${OPEN_NAMES}${RNAME}
"
                    # A candidate for the GONE report (R2-6): unacked (this branch is only
                    # reached past the acked-row `continue` above) and not MET/WAIVED, so a
                    # fresh panel showing it gone is a row nothing has ever named.
                    GONE_CANDIDATE_NAMES="${GONE_CANDIDATE_NAMES}${GONE_CANDIDATE_NAMES:+ }$(clean "$RNAME")"
                    # `$RSTATE` is one of STILL-LIVE/UNMET/AMBIGUOUS here (this branch's own
                    # `case`), never `|`-bearing. `clean` on the detail strips any `|` (and
                    # tab/newline) a brief's free text could otherwise smuggle in, which is
                    # what keeps this record's third field from being mistaken for a fourth.
                    GONE_CANDIDATE_INFO="${GONE_CANDIDATE_INFO}$(clean "$RNAME")|${RSTATE}|$(clean "$(line_field "$LINE" detail)")
"
                    ;;
      esac
      [ "$RSTATE" = "UNMET" ] || continue

      # Duration is a SECOND, ADVISORY-ONLY read of this one row — never a re-judgment of
      # MET/UNMET, which stays verdict's alone. The roster is append-only; the last line
      # carrying this name is its latest contract, the same row verdict itself just folded.
      # Filtered to the roster-state/v1 schema FIRST (t6-review.md F-1): a landing-swept/v1
      # marker for this same name also carries `|name=<name>|` and is appended AFTER the
      # roster rows, so an unfiltered `tail -1` takes the marker instead — it has no
      # duration=/launched_at=, and the row's overdue NOTIFY goes silent for the rest of the
      # session. Same schema-prefix discipline as every other roster reader in the fleet
      # (e.g. hooks/execution-recorder.sh's `roster-state/${ROSTER_VERSION}|` filters).
      ROW_LINE="$(grep -F "roster-state/v1|" "$ROSTER_FILE" 2>/dev/null \
        | grep -F "|name=${RNAME}|" | tail -1)"
      [ -n "$ROW_LINE" ] || continue

      # ---- A LIVE RUN COMES FIRST (wave-39 T22; REQ-16 AC-16.1; D21): a row whose landing carrier lives or for whose
      # agent the gate holds an open request is ACTIVE, and neither arm below reads its mtimes. Its row stays open above.
      row_live_run "$ROW_LINE" && continue

      # ---- ARM 1: past its declared DURATION. Unchanged arithmetic, restructured off
      # `continue` so that an unreadable duration no longer skips the row entirely — the
      # cadence read below is a second, independent question about the same row, and a row
      # whose `duration=` will not parse is exactly the row most worth asking it about.
      ROW_OVERDUE=no
      DUR_RAW="$(line_field "$ROW_LINE" duration)"
      LAUNCHED_RAW="$(line_field "$ROW_LINE" launched_at)"
      DUR_S="$(parse_seconds "$DUR_RAW")" || DUR_S=""
      LE="$(iso_epoch "$LAUNCHED_RAW")"
      if [ -n "$DUR_S" ] && [ -n "$LE" ]; then
        AGE=$(( $(now_epoch) - LE ))
        if [ "$AGE" -gt "$DUR_S" ]; then
          ROW_OVERDUE=yes
          NOTIFY_ROWS="${NOTIFY_ROWS}${NOTIFY_ROWS:+,}$(clean "$RNAME")"
          NOTIFY_DETAIL="${NOTIFY_DETAIL}${NOTIFY_DETAIL:+; }$(clean "$RNAME"): $(line_field "$LINE" detail) (elapsed ${AGE}s past declared duration \"$DUR_RAW\" (${DUR_S}s))"
        fi
      fi

      # ---- ARM 2: QUIETER THAN ITS OWN DECLARED CADENCE (REQ-10 AC-10.1; D9). The read the
      # Patrol prompt has promised since wave-01 and no code took: the row's `progress=` and
      # `cadence=` through `observe_class`, with the mtime that decided it printed beside the
      # verdict so the reader can check it. A row is named ONCE however many arms found it.
      if row_quiet "$ROW_LINE" "$(now_epoch)"; then
        [ "$ROW_OVERDUE" = yes ] \
          || NOTIFY_ROWS="${NOTIFY_ROWS}${NOTIFY_ROWS:+,}$(clean "$RNAME")"
        QUIET_DETAIL="${QUIET_DETAIL}${QUIET_DETAIL:+; }$(clean "$RNAME"): no line for ${TICK_QUIET_AGE}s against cadence ${TICK_QUIET_CAD}s (${TICK_QUIET_CHANNEL}, mtime ${TICK_QUIET_MTIME})"
      fi
    done <<EOF
$VERDICT_OUT
EOF

    # ---------- THE BACKSTOP: A RECORD ROW WHOSE AGENT ENDED WITHOUT LANDING IT (wave-33 T6; REQ-3 AC-3.1; D5) ----------
    #
    # A test, verify or review row lands by its own agent's last act, `deliver`. When the agent
    # ended without it, its roster row reads MET (the deliverable landed and the agent said so)
    # while its `## Tasks` row is still `active` under that name (launch-sync wrote the name into
    # the agent cell). The tick lands such a row through `deliver` itself, run as a child as
    # launch-sync is above, so the one landing writer and every check `deliver` makes stand: a row
    # whose artifact is absent is refused there, left active, and reported here with the refusal.
    # Only a row with no tree whose Files write nothing the head carries is asked; a row with a
    # tree lands through `ready`. MET is read off this tick's one verdict read, acked or not: the
    # ack closes the agent, never the row. A landed row is no longer `active`, so it is asked once.
    if [ "${POKER_RUN_OPEN:-}" = yes ] && [ -n "${POKER_RUN_PLAN:-}" ] && [ -f "$POKER_RUN_PLAN" ]; then
      TICK_MET="$(printf '%s\n' "$VERDICT_OUT" | awk -F'|' '$1 == "landing-verdict/v1" { n = ""; s = ""
          for (i = 2; i <= NF; i++) { if ($i ~ /^name=/) n = substr($i, 6); else if ($i ~ /^state=/) s = substr($i, 7) }
          if (s == "MET" && n != "") printf " %s", n }
        END { printf " " }')"
      if [ "$TICK_MET" != " " ]; then
        # An empty cell is printed `-`: a tab is white space to `read`, so two in a row would shift a field.
        while IFS=$'\t' read -r BS_ID BS_AGENT BS_FILES BS_WT; do
          [ -n "$BS_ID" ] || continue
          case "$BS_WT" in *[A-Za-z0-9]*) continue ;; esac
          ! units_writes_head "$BS_FILES" || continue
          # AN UNREAD RULING HOLDS THE ROW AND PAGES THE PERSON (wave-34 T4; REQ-3 AC-3.1, AC-3.2; D13, D4
          # option 1). The writer has ended, so a ruling it never read is read by nobody here: the backstop
          # reads the rulings of the row's writer (`row_writer`, `ready`'s answer) without stamping them
          # (lib/roster.sh `ruling_unread`), lands nothing, and opens `ruling:<id>` on the person's ledger,
          # which an open item keeps as it is, so one item and one send per ruling however many ticks hold
          # the row. The row holds until a writer reads the ruling, or the row is re-dispatched or dropped
          # (`tick_ruling_close` below). deliver's own guard stamps: it is the writer's, who reads it.
          if row_writer "$ROSTER_FILE" "$POKER_RUN_PLAN" "$BS_ID" "$BS_AGENT" \
             && BS_RULINGS="$(ruling_unread "$ROSTER_FILE" "$ROW_WRITER")" && [ -n "$BS_RULINGS" ]; then
            BS_IDS="$(printf '%s\n' "$BS_RULINGS" | sed -n 's/^bionic ruling \([^ ]*\) .*/\1/p')"
            BS_LINE="NOT-LANDED $BS_ID — $(clean "$ROW_WRITER") ended (MET) with an orchestrator ruling unread ($(printf '%s\n' "$BS_IDS" | paste -sd, - | sed 's/,/, /g')); the row holds until a writer reads it: re-dispatch the row, or drop it"
            say "$BS_LINE"
            if declare -F owed_open >/dev/null 2>&1; then
              for BS_RID in $BS_IDS; do
                OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_open "ruling:$BS_RID" "ruling unread: $BS_ID" "poker: $BS_LINE" >/dev/null 2>&1
              done
            fi
            continue
          fi
          BS_RC=0
          BS_OUT="$( cd "$REPO_REAL" && CLAUDE_CODE_SESSION_ID="$SESSION_ID" "${BASH:-bash}" "$HOOK_DIR/session-poker.sh" deliver "$BS_ID" 2>&1 )" || BS_RC=$?
          if [ "$BS_RC" -eq 0 ]; then
            say "LANDED $BS_ID — $(clean "$BS_AGENT") ended (MET) without deliver; the tick landed its row through deliver: $(clean "$(printf '%s\n' "$BS_OUT" | sed -n 's/^poker: deliver — [^:]*: //p' | head -1)")"
          else
            say "NOT-LANDED $BS_ID — $(clean "$BS_AGENT") ended (MET) without deliver, and deliver refused it: $(clean "$(printf '%s\n' "$BS_OUT" | /usr/bin/grep -m1 'REFUSED' | sed 's/^poker: //')")"
          fi
        done <<BACKSTOP_ROWS
$(units_rows "$POKER_RUN_PLAN" 2>/dev/null | awk -F'\t' -v met="$TICK_MET" '$10 == "active" && $5 != "" && index(met, " " $5 " ") { printf "%s\t%s\t%s\t%s\n", $1, $5, ($9 == "" ? "-" : $9), ($11 == "" ? "-" : $11) }')
BACKSTOP_ROWS
        if declare -F owed_send >/dev/null 2>&1; then
          OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_send ruling: >/dev/null 2>&1
        fi
      fi
      # THE PAGE CLOSES WHEN NO ROW WAITS ON IT (wave-34 T4; REQ-3 AC-3.1, D13). An open `ruling:<id>`
      # stands while its ruling is unread and some active row's writer (`row_writer`, the backstop's own
      # answer) is the ruling's writer. A ruling shown closes its item where it is stamped (lib/roster.sh
      # `ruling_page_close`); this closes the rest at the next tick: the row re-dispatched to another
      # writer, dropped, or landed. Silent, never fatal; nothing is read while no ruling item is open.
      tick_ruling_close() {
        local keys rk fold writers=" " r a rid w x1 x2 x3 s rest why
        declare -F owed_list >/dev/null 2>&1 && declare -F owed_close >/dev/null 2>&1 || return 0
        keys="$(OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_list 2>/dev/null | cut -f1 | /usr/bin/grep '^ruling:')" || return 0
        while IFS=$'\t' read -r r a; do
          [ -n "$r" ] || continue
          row_writer "$ROSTER_FILE" "$POKER_RUN_PLAN" "$r" "$a" && [ -n "$ROW_WRITER" ] && writers="${writers}${ROW_WRITER} "
        done <<TICK_RULING_ROWS
$(units_rows "$POKER_RUN_PLAN" 2>/dev/null | awk -F'\t' '$10 == "active" { print $1 "\t" $5 }')
TICK_RULING_ROWS
        fold="$(ruling_fold "$ROSTER_FILE")"
        for rk in $keys; do
          IFS="$RULING_US" read -r rid w x1 x2 x3 s rest <<< "$(printf '%s\n' "$fold" | awk -F"$RULING_US" -v id="${rk#ruling:}" '$1 == id { print; exit }')"
          [ -n "$rid" ] || continue
          if [ -n "$s" ]; then
            why="ruling read"
          else
            case "$writers" in *" $w "*) continue ;; esac
            why="no active row is $w's: re-dispatched, dropped or landed"
          fi
          OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_close "$rk" "$why" >/dev/null 2>&1
        done
        return 0
      }
      tick_ruling_close
    fi

    # ---------- THE PANEL IS REFRESHED FROM THE ROSTER, NOT FROM A TOOL CALL (T22) -------
    #
    # One line per MET lineage still on this session's register. It is a TELL: the tick holds
    # no authority (ADR-003), stops nothing, and refuses nothing. What it replaces is
    # `stop_patrol_duties`'s ListAgents duty, which asked the model to look at a panel so
    # that a gate would let the turn end — and never named a single thing to do about what
    # it saw.
    #
    # THE ARM MOVED DOWN (T1, D1/D2). It used to print here, from the roster alone, and say
    # `TASKSTOP <name>`. The roster alone cannot tell the two cases apart: a MET row whose
    # agent is STILL LISTED is somebody's TaskStop to make, and a MET row whose agent is GONE
    # is a row nothing will ever close — the adopted-MET case, named on every tick forever
    # until a human typed an `ack`. Both readings need the PANEL, which is warmed a few lines
    # below, so the decision is taken there and `$STANDDOWN_NAMES` is what carries the
    # candidates to it.

    # ---------- THE LIVE SET TRIMS `open=` AND THE FILL (S19, auditor F-14) ----------
    #
    # THE DEFECT. The spec's ownership table names this tick a rendering surface of the LIVE
    # AGENT SET; it read no such thing. It counted roster rows by sweeper verdict, while the
    # dispatch wall counts a row open only while the harness still calls its agent live
    # (AC-27). One row, two answers: a finished-but-unstopped teammate is NOT open to the
    # wall and WAS open here, so the Patrol could print a FILL the wall was about to refuse
    # — or withhold one it would have allowed. The number below is now the wall's number,
    # because both sides ask the same function.
    #
    # THE TICK DECIDES AND NEVER WRITES. No roster row, marker or verdict moves here: the
    # row stays exactly as the sweeper left it, still counted in `total=`, still eligible to
    # NOTIFY when it is overdue. Only the arithmetic this tick prints is trimmed. That is
    # what keeps the roster readable by every other consumer (D0: one owner per liveness
    # truth, and the ROSTER's owner is not this file).
    #
    # ONLY WHEN THERE IS SOMETHING TO TRIM. A roster with no open row has nothing whose
    # openness a live answer could settle — the same reasoning the dispatch wall's empty-
    # roster arm takes — so the reader is not called and no line is printed. A fallback
    # sentence on every quiet tick of every session is noise a reader learns to skip.
    #
    # ON A STALE OR MISSING ANSWER THE ROSTER COUNT STANDS, and this is deliberately NOT
    # the wall's refuse-and-name-the-fix behaviour. The Patrol's prompt runs this tick
    # BEFORE any ListAgents, so a refusal here would refuse the first tick of every session
    # — a wall that fires on the healthy path is not a wall. The tick holds no authority
    # (ADR-003): it prints a line and the operator acts. The ENFORCEMENT is the dispatch
    # wall, which does refuse on a stale read, so the honest thing here is to say which
    # number this is and point at the gate that will insist.
    OPEN_ROSTER="$OPEN"
    TICK_LIVE_STATE=""
    # RESOLVED AT MOST ONCE PER TICK, by whichever arm needs it first: the trim below, or the
    # stand-down arm after it. A tick with nothing open and nothing MET reads no transcript.
    TICK_TR=""
    if [ "$OPEN_ROSTER" -gt 0 ]; then
      TICK_TR="$(session_transcript "$SESSION_ID")" || TICK_TR=""
      if [ -z "$TICK_TR" ]; then
        TICK_LIVE_STATE="none"
      else
        TICK_OPEN_LIVE=0
        # PRIME THE READER'S PER-PROCESS PARSE, ONCE, IN THIS SHELL (Step-6 review P-4, the
        # tick half of the finding the budget wall's loop already answers). `live_agents`
        # memoizes its parse in shell variables keyed on the transcript's path, size and
        # mtime — but the per-row call below runs inside a command substitution, and a
        # subshell INHERITS its parent's variables while its own writes die with it. So the
        # first row would warm a cache nobody sees and every open row would pay a full
        # parse: two whole-file `jq` passes and nine spawns. Measured on this machine, one
        # tick over twelve open rows and a 4.1 MB transcript ran jq 24 times.
        #
        # LAZILY, INSIDE THE `OPEN_ROSTER > 0` ARM, for the same reason the wall does it
        # lazily: a roster with nothing open reads the transcript zero times. Its answer is
        # discarded — this line is a cache fill, and every row's verdict is the predicate's.
        live_agents "$TICK_TR" >/dev/null 2>&1 || :
        while IFS= read -r TICK_NAME; do
          [ -n "$TICK_NAME" ] || continue
          # The predicate prints nothing on stdout, so this capture is the reader's one
          # contract line — `live-agents: <state> age=<n|none>` — and nothing else.
          TICK_LRC=0
          TICK_LERR=$( { live_row_open "$TICK_TR" "$TICK_NAME"; } 2>&1 ) || TICK_LRC=$?
          case "$TICK_LRC" in
            0) TICK_OPEN_LIVE=$(( TICK_OPEN_LIVE + 1 )) ;;
            1) : ;;
            *) # 3 STALE / 4 NONE. Freshness is a property of the TRANSCRIPT, not of any
               # one name, so every remaining row would read the same way: stop asking.
               TICK_LIVE_STATE="${TICK_LERR#live-agents: }"
               TICK_LIVE_STATE="${TICK_LIVE_STATE%% *}"
               break ;;
          esac
        done <<EOF
$OPEN_NAMES
EOF
        [ -n "$TICK_LIVE_STATE" ] || OPEN="$TICK_OPEN_LIVE"

        # ---------- THE DUPLICATE-SESSION TELL (AC-4.3, T21) ----------
        #
        # THE CLAIM WAS PROSE ONLY. skills/canonical-sdlc/dispatch.md promises "A listed agent
        # with NO ledger row is surfaced as a duplicate-session tell, never silently stopped",
        # and nothing computed it. Chris, 2026-09-14 (A-orch-29): "Add a test" — the tell
        # becomes tick machinery, with its own test.
        #
        # THE QUESTION, for every name THIS session's ListAgents answer calls live: does ANY
        # roster under this PROJECT's `.bionic/tmp` — not only this session's own — carry a row
        # for it, by `name=` or `agent_id=` (payload/scripts/lib/roster.sh)? A live agent no
        # roster remembers is either another session's dispatch (never rostered here) or a
        # resumed copy of a finished one — either way this session cannot tell which, so it
        # NAMES the gap and stops there: no stop, no roster write, no effect on FILL, QUIET or
        # NOTIFY. `ANY roster`, not `open`: a landed/MET row still proves the wall once knew the
        # agent, so a closed row clears the name exactly as an open one would.
        #
        # THE ALREADY-WARMED SLOT, NOT A SECOND CALL (S19I's own pin, P-4). The priming line
        # above filled `agents.sh`'s one-process cache directly (no subshell), and the loop
        # that follows it only ever reads that cache through subshelled predicate calls whose
        # writes die with them — so the cache this process holds is still exactly what the
        # priming line put there. A second call to `live_agents "$TICK_TR"` here would normally
        # be a cache HIT and cost nothing — but S19I's own anti-vacuity arm proves the opposite
        # case by deleting the priming line and nothing else, and against THAT doctored copy a
        # second `live_agents` call would pay its own full parse (the row loop's cache writes
        # are already lost to their subshells, so nothing upstream would have warmed it either)
        # and move the "twelve, not two" pin it exists to hold. Reading the cache SLOT directly
        # copies neither cost: a real tick sees exactly what the priming line read (correct data,
        # zero extra jq calls), and a doctored one — where nothing ever warmed it — sees empty
        # (no tell, and still zero extra calls; S19I is not testing this feature).
        #
        # ONLY WHEN THE ANSWER CARRIES A SET. NONE reads as an empty set here exactly as it
        # does for the trim above (AC-4.1: the tick never demands a ListAgents call), and a
        # STALE answer still names a real — if possibly outdated — live set worth surfacing,
        # the same asymmetry `live_agents`'s own header documents.
        TICK_DUP_SET="$_LA_CACHE_OUT"
        if [ -n "$TICK_DUP_SET" ]; then
          while IFS='|' read -r TICK_DUP_NAME TICK_DUP_TYPE TICK_DUP_STATUS; do
            [ -n "$TICK_DUP_NAME" ] || continue
            TICK_DUP_FOUND=0
            for TICK_DUP_RF in "$REPO_REAL/.bionic/tmp"/roster-*.state; do
              [ -f "$TICK_DUP_RF" ] || continue
              # Symlinks are not followed, the same posture every other .bionic/tmp reader
              # in this file takes.
              [ -L "$TICK_DUP_RF" ] && continue
              if grep -qF "|name=${TICK_DUP_NAME}|" "$TICK_DUP_RF" 2>/dev/null \
                 || grep -qF "|agent_id=${TICK_DUP_NAME}|" "$TICK_DUP_RF" 2>/dev/null; then
                TICK_DUP_FOUND=1
                break
              fi
            done
            [ "$TICK_DUP_FOUND" -eq 1 ] \
              || say "DUPLICATE-SESSION ${TICK_DUP_NAME} — live here, on no roster of this project (another session's dispatch or a resumed copy); never stop it silently"
          done <<EOF
$TICK_DUP_SET
EOF
        fi
      fi
      if [ -n "$TICK_LIVE_STATE" ]; then
        say "live set $TICK_LIVE_STATE — open= counted from the roster"
      elif [ "$OPEN" -ne "$OPEN_ROSTER" ]; then
        # THE TRIM IS SAID OUT LOUD, or `open=0` over a roster carrying two unmet
        # contracts is a number with no story. Only when it actually moved: a tick whose
        # live set agrees with its roster has nothing to explain.
        say "live set fresh — ${OPEN_ROSTER} open row(s) on this roster, ${OPEN} still live; open= is sized from the live set, the fill from every row not yet acked"
      fi
    fi

    # ---------- THE DUPLICATE-START TELL (T22 row (d), delta review C2) ----------
    #
    # hooks/execution-recorder.sh journals `status=duplicate-start` when one agent id starts a
    # SECOND time in this session — a resumed copy working a contract the first process still
    # holds. That row was accepted as the answer BECAUSE a SubagentStart hook cannot block
    # (A-T22.4): the door that closes is the dispatch wall, one event earlier, and the record
    # exists so that somebody SEES the case the door was not asked about. Until this block
    # nothing read the field: the DUPLICATE-SESSION tell above asks a different question — a
    # live name NO roster of this project carries — and a duplicate start is carried by `name=`
    # AND by `agent_id=`, so that tell is silent on exactly this row.
    #
    # ROSTER-ONLY, AND OUTSIDE THE LIVE-SET ARM. The fact is on disk. A tell that needed a
    # ListAgents answer, or an open row to trim, would go quiet in precisely the degraded
    # session that produces the row — one that just lost its agent table across a `/clear`.
    #
    # ONE LINE PER ROW, NOT PER NAME: two duplicate starts are two events, and collapsing them
    # would hide the second. It is a TELL and nothing else — no stop, no roster write, no
    # effect on FILL, QUIET, NOTIFY or `open=`.
    #
    # THE TWO MARKS THAT CLOSE A ROW CLOSE THIS TELL TOO (T1, D2). Until 1.8.0 this loop
    # applied NO ack filter and NO swept filter, and the roster is append-only with nothing
    # that ever supersedes the row — so the tell repeated on every tick for the life of the
    # session, long after the duplicate process was gone, and no act available to the reader
    # could quiet it. It is the same closing rule the rest of this file already keeps
    # (session-poker.sh: "A ROW IS CLOSED BY A LANDED MARKER OR BY AN ACK, and by nothing
    # else"), applied here for the first time. The stand-down arm below writes that ack when
    # the panel shows the agent gone, so the ordinary life of a duplicate start is now: told
    # once, closed in the same tick, silent after it.
    DUP_START_NAMES="|"
    if [ -f "$ROSTER_FILE" ] && [ ! -L "$ROSTER_FILE" ]; then
      DUP_START_ROWS="$(grep -F "|status=duplicate-start|" "$ROSTER_FILE" 2>/dev/null)"
      if [ -n "$DUP_START_ROWS" ]; then
        while IFS= read -r DS_LINE; do
          # The schema prefix is checked here as every other roster reader in this file checks
          # it: `|status=` is not unique to a roster-state row by construction, only in practice.
          case "$DS_LINE" in "roster-state/v1|"*) : ;; *) continue ;; esac
          DS_NAME="$(clean "$(line_field "$DS_LINE" name)")"
          [ -n "$DS_NAME" ] || continue
          case "$TICK_ACKED_NAMES" in *"|${DS_NAME}|"*) continue ;; esac
          case "$SWEPT_ALL" in *"|name=${DS_NAME}|"*) continue ;; esac
          # ONE LINE PER ROW, NOT PER NAME (unchanged): two duplicate starts are two events.
          # The CANDIDATE set below is per NAME, because an ack closes a name and writing two
          # for one row would be two ledger lines saying the same thing.
          say "DUPLICATE-START ${DS_NAME} — a second start under an id that already has a live row; the dispatch wall is the door that closes"
          case "$DUP_START_NAMES" in
            *"|${DS_NAME}|"*) : ;;
            *) DUP_START_NAMES="${DUP_START_NAMES}${DS_NAME}|" ;;
          esac
        done <<EOF
$DUP_START_ROWS
EOF
      fi
    fi
    [ "$DUP_START_NAMES" = "|" ] && DUP_START_NAMES=""

    # ---- BEGIN a reader started without its checks (wave-27 T38; review pass 31 F2) ----
    # hooks/execution-recorder.sh appends `start-unchecked/v1|event=start|…` to the roster when a
    # reader's start could not be placed and its candidates carry different `questions=`: no
    # checks file was pushed, and its own log line is stderr nobody reads. The tick says so ONCE
    # per agent id and writes `event=told` beside it, so the orchestrator stops that reader and
    # dispatches it again. Nothing else: no stop, no ack.
    # THE LINE IS HASHED WHOLE, AND TOLD ONLY ONCE PRINTED (wave-27 T37; review pass 36 S1). Under
    # its kind alone every such line hashed as `NOTIFY — a`, so a second reader's line on a later
    # tick left the decision unchanged, was dropped, and was still marked told. Now `tick_conclude`
    # hashes the whole line and the agent ids in US_NOTIFY_IDS (two readers of one role and one
    # candidate set print the same words), and `event=told` waits in US_TOLD_PENDING for the exit
    # trap, which writes it only when it prints the buffer. Unbuffered, the line is out already.
    # A told line ends at its id, so the id is matched at a line end as well as before a `|`.
    US_NOTIFY_IDS=""; US_TOLD_PENDING=""
    if [ -f "$ROSTER_FILE" ] && [ ! -L "$ROSTER_FILE" ]; then
      US_TOLD="$(grep -F 'start-unchecked/v1|event=told|' "$ROSTER_FILE" 2>/dev/null)"$'\n'
      while IFS= read -r US_LINE; do
        case "$US_LINE" in "start-unchecked/v1|event=start|"*) : ;; *) continue ;; esac
        US_AID="$(line_field "$US_LINE" agent_id)"
        [ -n "$US_AID" ] || continue
        case "$US_TOLD" in *"|agent_id=${US_AID}|"*|*"|agent_id=${US_AID}"$'\n'*) continue ;; esac
        say "NOTIFY — a $(clean "$(line_field "$US_LINE" role)") started without its checks: candidates $(clean "$(line_field "$US_LINE" candidates)" | sed 's/,/, /g')"
        US_NOTIFY_IDS="${US_NOTIFY_IDS:+$US_NOTIFY_IDS,}${US_AID}"
        US_TOLD_LINE="$(printf 'start-unchecked/v1|event=told|at=%s|session=%s|agent_id=%s' "$(iso_now)" "$SESSION_ID" "$US_AID")"
        if [ -n "$TICK_BUF" ]; then
          US_TOLD_PENDING="${US_TOLD_PENDING}${US_TOLD_LINE}"$'\n'
        else
          printf '%s\n' "$US_TOLD_LINE" >> "$ROSTER_FILE" 2>/dev/null
        fi
        US_TOLD="${US_TOLD}|agent_id=${US_AID}|"
      done < <(grep -F 'start-unchecked/v1|event=start|' "$ROSTER_FILE" 2>/dev/null)
    fi
    # ---- END a reader started without its checks ----

    # ---------- THE STAND-DOWN: the tick names it, and writes the order (T1; D1, D2) ------
    #
    # THE DEFECT IT ENDS. `TASKSTOP <name>` was a tell and nothing else. The reader who acted
    # on it then met the stop gate, which refuses a stop of a live agent whose contract it
    # cannot see discharged — so the instruction the Patrol printed was routinely refused by
    # the wall one turn later, and the operator learned to ack rows by hand instead. Worse,
    # the tell could not tell a stoppable row from a moot one: an ADOPTED MET row is never
    # swept by anything (adopt_fold excludes MET names, the Stop-sweep skips teammate rows,
    # and the adopted agent's SubagentStop belongs to the session that launched it), so it
    # was named on every tick, forever, for an agent that had been gone for hours.
    #
    # THE PANEL IS WHAT SEPARATES THEM, and it is the fact this tick already holds — read
    # alone, never stood in for by the `landing-swept/v1` marker (T10, A-orch-20): that marker
    # records a landing SEEN, and for a teammate it is written at its own SubagentStop while it
    # is still on the panel, so "swept" is not "gone".
    #
    #   MET, STILL LISTED -> somebody has to stop it, swept marker or not. The tick says so by
    #     name AND writes the stop order (hooks/stop-orders.sh order <name> --by patrol), so the
    #     TaskStop that answers is not refused by the stop gate. `by=patrol` is the honest
    #     label: an order used to mean "a human said stop" and now means "a human or a
    #     verified landing said stop" (D1).
    #   MET, NOT LISTED, already carrying a `landing-swept/v1` marker -> the row is closed
    #     already; a second closing act would be a ledger line that says nothing new. Nothing
    #     is printed and nothing is acked (A-T1.9, extended: the predicate that matters is
    #     ABSENT, not unswept).
    #   MET, NOT LISTED, no marker, or a `duplicate-start` row whose agent is gone -> there is
    #     nobody to stop and no prior close on record. The row is moot and the world says so,
    #     so the tick closes it the way a human would: `session-sweeper.sh ack <name> --by
    #     patrol --reason moot-and-gone` (D2). Nothing is printed — a stand-down tell for an
    #     agent that does not exist is the noise this arm exists to remove — and the evidence
    #     is the ledger line, which names the author and what it was read off.
    #
    # THE TICK STILL STOPS NOTHING (ADR-003, unchanged). An order is a permission and an ack
    # is a bookkeeping fact; neither ends a process. The one act this arm performs on a
    # RUNNING agent is to make the operator's stop legal.
    #
    # AN UNKNOWN PANEL IS NOT AN EMPTY ONE. With no usable answer (`none` — the state of
    # every session before its first ListAgents) the tick does NEITHER thing: it neither
    # names a row for a stop it cannot justify nor closes one on evidence it does not have.
    #
    # FRESH ONLY (A-orch-31, T6). This arm used to take the same FRESH/STALE asymmetry the
    # read-only DUPLICATE-SESSION tell above takes — "a stale answer still names a real, if
    # slightly old, set of agents" — but that reasoning does not survive contact with a WRITE.
    # Measured 20:55Z: a STALE reading (the panel's last-known answer, not a fresh one) still
    # named a MET row and wrote a SECOND stop order for an agent the Patrol's own prior order
    # had already had stopped eighteen minutes earlier. A tell can afford to be a little old;
    # an order and an ack cannot — both are acts this arm cannot take back. So STALE now reads
    # the same as NONE: the arm defers rather than guesses, naming nothing, ordering nothing,
    # acking nothing, and saying once that the next tick's fresh ListAgents will decide.
    TICK_ACKED_NOW="|"
    if [ -n "$STANDDOWN_NAMES" ] || [ -n "$DUP_START_NAMES" ] || [ -n "$GONE_CANDIDATE_NAMES" ]; then
      # THE ALREADY-WARMED PARSE, or one read of our own — never a second parse of a
      # transcript this tick has already read. `live_agents` memoizes per process on the
      # transcript's path, size and mtime, and the trim above primes it IN THIS SHELL, so on
      # a roster with open rows the call below is a cache hit costing nothing. On a roster
      # whose every row is MET (`OPEN_ROSTER = 0`, the common shape at the end of a batch)
      # the trim never ran and this is the tick's one and only parse.
      [ -n "$TICK_TR" ] || TICK_TR="$(session_transcript "$SESSION_ID")" || TICK_TR=""
      SD_PANEL=""; SD_PANEL_KNOWN=0
      if [ -n "$TICK_TR" ]; then
        SD_LRC=0
        live_agents "$TICK_TR" >/dev/null 2>&1 || SD_LRC=$?
        case "$SD_LRC" in
          0)
            SD_PANEL_KNOWN=1
            # The cache SLOT, read directly for the reason the DUPLICATE-SESSION arm states
            # above it: a second call would be a hit on a real tick and a full parse against
            # §19i's doctored copy, which is not this arm's property to move.
            while IFS='|' read -r SD_PN SD_PT SD_PS; do
              [ -n "$SD_PN" ] || continue
              SD_PANEL="${SD_PANEL}${SD_PN}|"
            done <<EOF
$_LA_CACHE_OUT
EOF
            [ -n "$SD_PANEL" ] && SD_PANEL="|${SD_PANEL}"
            ;;
        esac
      fi

      if [ "$SD_PANEL_KNOWN" -eq 1 ]; then
        # ONE ACK PER NAME PER TICK. A name can be a MET candidate and a duplicate-start row
        # at once; two ledger lines would say the same thing twice.
        SD_CLOSED="|"
        for SD_NAME in $STANDDOWN_NAMES; do
          case "$SD_PANEL" in
            *"|${SD_NAME}|"*)
              # A HELD ROW IS ANSWERED ALREADY (wave-24 T7; D1, ADR-041 d1). Its latest row
              # carries the orchestrator's `held=<at> <reason> fp=<fingerprint>`; while the
              # fingerprint computed now is the one recorded, the tick prints the hold and writes
              # no order. A changed fingerprint falls through to the stand-down, writing nothing
              # to void it: the next `hold` is a new answer to new facts.
              SD_ROW="$(grep -F "roster-state/v1|" "$ROSTER_FILE" 2>/dev/null \
                | grep -F "|name=${SD_NAME}|" | tail -1)"
              SD_HELD="$(line_field "$SD_ROW" held)"
              if [ -n "$SD_HELD" ] && [ "${SD_HELD##* fp=}" != "$SD_HELD" ] \
                 && [ "${SD_HELD##* fp=}" = "$(hold_fingerprint "$SD_ROW" "$REPO_REAL" "$TICK_TR")" ]; then
                SD_HELD_REST="${SD_HELD#* }"
                say "held ${SD_NAME} since ${SD_HELD%% *} — ${SD_HELD_REST% fp=*}"
                continue
              fi
              say "STANDDOWN ${SD_NAME} — contract MET and the agent is still on the panel; TaskStop it (the order is written), or keep it up with: bash ${POKER_WORD} hold ${SD_NAME} ${HOLD_REASON_SLOT}"
              SD_ORDER_NAMES="${SD_ORDER_NAMES}${SD_ORDER_NAMES:+ }${SD_NAME}"
              ;;
            *)
              case "$SD_CLOSED" in *"|${SD_NAME}|"*) continue ;; esac
              SD_CLOSED="${SD_CLOSED}${SD_NAME}|"
              # THE ACK IS THE CLOSE (wave-19 T1; D2, ADR-034 d1). Skipped only for a name the
              # ledger already closed — the verdict walk records those in TICK_ACKED_NAMES —
              # never for a `landing-swept/v1` marker: the marker says a landing was SEEN, and
              # skipping on it left every writer that declared an artifact and reported open for
              # the life of the session (ideas row 16; R1 F1). This branch runs only under a
              # FRESH panel (SD_PANEL_KNOWN=1 above) that does not list the name.
              case "$TICK_ACKED_NAMES" in *"|${SD_NAME}|"*) continue ;; esac
              # THE REASON SAYS WHAT CLOSED IT. A row that declared a deliverable and met it
              # LANDED; a row that declared nothing stats MET for want of anything to hold it
              # to, and is closed only because it is moot and gone. Read off the row's latest
              # contract (schema-filtered: a marker also carries `|name=`), once per close —
              # a name reaches here at most once in its life, so this is no per-tick walk.
              SD_REASON=moot-and-gone
              SD_ROW="$(grep -F "roster-state/v1|" "$ROSTER_FILE" 2>/dev/null \
                | grep -F "|name=${SD_NAME}|" | tail -1)"
              [ -n "$(line_field "$SD_ROW" deliverable)" ] && SD_REASON=landed
              if SD_OUT=$( cd "$REPO_REAL" 2>/dev/null || exit 9
                           CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
                           bash "$SWEEPER" ack "$SD_NAME" --by patrol --reason "$SD_REASON" 2>&1 ); then
                TICK_ACKED_NOW="${TICK_ACKED_NOW}${SD_NAME}|"
              else
                say "NOTIFY ${SD_NAME} — contract MET, the agent is gone, and the row could NOT be closed: $(clean "$(printf '%s' "$SD_OUT" | head -1)")"
              fi
              ;;
          esac
        done
        SD_DUPS="${DUP_START_NAMES}"
        SD_DUPS="${SD_DUPS//|/ }"
        for SD_NAME in $SD_DUPS; do
          case "$SD_PANEL" in *"|${SD_NAME}|"*) continue ;; esac
          case "$SD_CLOSED" in *"|${SD_NAME}|"*) continue ;; esac
          SD_CLOSED="${SD_CLOSED}${SD_NAME}|"
          if SD_OUT=$( cd "$REPO_REAL" 2>/dev/null || exit 9
                       CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
                       bash "$SWEEPER" ack "$SD_NAME" --by patrol --reason moot-and-gone 2>&1 ); then
            TICK_ACKED_NOW="${TICK_ACKED_NOW}${SD_NAME}|"
          else
            say "NOTIFY ${SD_NAME} — a duplicate start whose agent is gone could NOT be closed: $(clean "$(printf '%s' "$SD_OUT" | head -1)")"
          fi
        done

        # THE GONE REPORT (wave-19 audit V-2 delta review R2-6). An unacked, not-MET/WAIVED
        # row whose agent this fresh panel does not list now holds a `TICK_OCCUPIED` slot
        # (A-T2.13) with nothing pointing at the fix: T1e's `stopped` close. This is a
        # NOTIFY-band report only — never an ack, never an order — because the tick has no
        # authority to decide an UNMET verdict is done (ADR-003); closing one is the human
        # verb's job alone. Printed in the same place the STANDDOWN lines print, so it never
        # changes what this tick decided (QUIET stays QUIET; a FILL sized before this point
        # is unaffected).
        #
        # THE LINE NAMES A VERB THAT WILL RUN (audit V3-2). `GONE_CANDIDATE_NAMES` covers
        # STILL-LIVE, UNMET and AMBIGUOUS alike, but `stopped` does not accept all three: it
        # refuses AMBIGUOUS unconditionally, and refuses a STILL-LIVE row whose own detail
        # names a claimed process pattern still matching a live process — a fact about a real
        # OS process the panel cannot speak to (hooks/stop-orders.sh:618-663, T1g/A-T1.13).
        # `stopped` is not exposed as a sourceable predicate (A-T2.18), so its acceptance
        # rule is mirrored here rather than re-derived, kept beside this comment so the two
        # copies are found together. A row the verb WILL close prints the verdict it actually
        # holds (never a hardcoded "UNMET") and the runnable command; a row the verb WILL
        # REFUSE prints `GONE?` instead, naming the verdict and the refusal reason, so the
        # operator is told rather than misdirected into a command that fails.
        while IFS='|' read -r SD_GNAME SD_GSTATE SD_GDETAIL; do
          [ -n "$SD_GNAME" ] || continue
          case "$SD_PANEL" in *"|${SD_GNAME}|"*) continue ;; esac
          SD_REFUSE=0
          SD_WHY=""
          SD_VERDICT="$SD_GSTATE"
          case "$SD_GSTATE" in
            UNMET)
              SD_VERDICT="UNMET"
              ;;
            FOLLOW-UP)
              # MET, with a message the agent never answered (wave-20 T9, Δ8): gone from a
              # fresh panel, the reply cannot come, and `stopped` closes it `landed`.
              SD_VERDICT="FOLLOW-UP (met; the follow-up went unanswered)"
              ;;
            STILL-LIVE)
              if grep -q 'claimed process pattern' <<< "$SD_GDETAIL"; then
                SD_REFUSE=1
                SD_WHY="a claimed process pattern still matches a live process; the panel showing it gone does not close this on its own"
              else
                SD_AGE="$(printf '%s' "$SD_GDETAIL" | grep -oE 'last changed [0-9]+s ago' | grep -oE '[0-9]+')"
                SD_CAD="$(printf '%s' "$SD_GDETAIL" | grep -oE '\([0-9]+s\)' | tr -d '()s')"
                SD_VERDICT="STILL-LIVE (progress ${SD_AGE:-?}s old, cadence ${SD_CAD:-?}s)"
              fi
              ;;
            *)
              # AMBIGUOUS — `stopped`'s verdict-state `case` refuses it unconditionally,
              # before it ever reads a panel (hooks/stop-orders.sh:618-630).
              SD_REFUSE=1
              SD_WHY="two or more contracts share this name; stopped always refuses ${SD_GSTATE}"
              ;;
          esac
          if [ "$SD_REFUSE" -eq 1 ]; then
            say "GONE? ${SD_GNAME} — ${SD_VERDICT} and absent from a fresh panel; stopped will refuse it: ${SD_WHY}"
          else
            say "GONE ${SD_GNAME} — ${SD_VERDICT} and absent from a fresh panel; close it with: bash ${ORDERS} stopped ${SD_GNAME}"
          fi
        done <<EOF
$GONE_CANDIDATE_INFO
EOF
      else
        # A-orch-31: something WOULD have been decided (a MET row, a duplicate start, or a
        # GONE report is sitting in the candidate sets above) but the panel reading is not
        # fresh enough to trust with a write or a report. One line, said once, never a
        # STANDDOWN, a GONE report, an order or an ack.
        # NAMED, AND TRUTHFUL ABOUT WHY (wave-20 T9, REQ-4, AC-4.5; consumer report #11). The
        # line names every row it held back — the union of the three candidate sets, once each
        # — so the operator knows which agent waits on a ListAgents. `stale` is a reading that
        # exists but predates the last prompt (`live_agents` rc 3); no answer at all (rc 4) or
        # no transcript is `absent`, and used to be called stale too.
        SD_DEFERRED="$(poker_union ' ' "$STANDDOWN_NAMES" "${DUP_START_NAMES//|/ }" "$GONE_CANDIDATE_NAMES")"
        SD_WHY=absent
        [ -n "$TICK_TR" ] && [ "${SD_LRC:-4}" -eq 3 ] && SD_WHY=stale
        note "stand-down deferred for ${SD_DEFERRED} — the panel reading is ${SD_WHY}; ListAgents and the next tick decides"
      fi
    fi

    # THE FILL'S OCCUPANCY, COUNTED NOW (T2d; the declaration above the verdict walk says why).
    # Every unacked name the walk saw, minus every name the arm above has just acked. Only an
    # ack that WROTE counts as a close: a refused `ack` left the row open, and the wall will
    # count it too.
    #
    # THE WRITERS AMONG THEM (wave-24 T10, REQ-7 AC-7.1, D11). A read-only role holds no writer
    # slot, so it is not occupancy: the names go through `budget_open_writers`
    # (payload/scripts/lib/roster.sh), the same function the dispatch wall counts its `open=`
    # with, and a Patrol that read a researcher as a full seat would hold a FILL the wall
    # would have admitted.
    TICK_OCC_NAMES=""
    while IFS= read -r OCC_NAME; do
      [ -n "$OCC_NAME" ] || continue
      case "$TICK_ACKED_NOW" in *"|${OCC_NAME}|"*) continue ;; esac
      TICK_OCC_NAMES="${TICK_OCC_NAMES}${OCC_NAME}
"
    done <<EOF
$TICK_UNACKED_NAMES
EOF
    TICK_OCCUPIED="$(printf '%s' "$TICK_OCC_NAMES" | budget_open_writers "$ROSTER_FILE")"
    case "$TICK_OCCUPIED" in ''|*[!0-9]*) TICK_OCCUPIED=0 ;; esac

    # ─────────────────────────────────────── the scheduler, defined once for two callers
    #
    # ONE SITE, TWO ARMS (wave-26 T59; REQ-6 AC-6.6). The gate line, the budget and the
    # scheduler's body below are what every tick that decides prints its
    # FILL, RANGE, WAIT and CHAIN lines from. The armed first tick (no roster yet, just below)
    # exits above the place this is called on every other tick, so it calls it too: the one tick
    # where every ready row is still unstarted names them, from this same code. Defined here,
    # ahead of both, and called once by whichever arm the tick takes.
    tick_scheduler() {
    # THE FILL THIS TICK ORDERED, empty until the scheduler names one — the FILL band's own
    # input to the ranked decision below (D5).
    SCHED_FILL=""
    SCHED_BEHIND=""

    # The plan and its budget, read once. Both may be absent — a project with no plan, or a
    # plan written before Step 0 ever probed — and the tick then fills nothing and says why.
    # The budget is a MEASUREMENT Step 0 writes (wave-19 REQ-3, ADR-035): the governing-skill
    # hook refuses a plan Write without it, so an absent key here is a backstop the note
    # below names, and the stop wall refuses the turn on the same absence.
    #
    # THE SAME RUN THE DECISION ABOVE WAS TAKEN ON. `resolve_run` answers once per tick, so
    # a session bound to its own plan fills from its own task table and quotes its own
    # ceiling — a tick that stood its ground correctly and then filled the neighbour's
    # tasks would be worse than either failure alone (AC-1).
    sched_budget_read "$REPO_REAL" "$SESSION_ID"

    # THE SCHEDULER'S BODY, RUN UNDER ONE PARSE OF THE TABLE (wave-21 T13; review-bed/perf).
    # The holds, the findings and the ready set are three questions of one table; asked bare
    # they parsed it four times a tick. Defined here and called once, just below its body, so
    # every assignment it makes is this shell's — nothing in it runs in a subshell.
    tick_schedule() {
    # THE REPORT, AND THE CEILINGS IT IS TAKEN AGAINST — both in `gate_report` above, which
    # the DISARM arm, exiting above this block, calls for itself (AC-17, Step-6 review C-5);
    # the armed first tick calls this whole scheduler instead (T59).
    # The budget read is memoized, so reaching it a second time here costs one plan read.
    gate_report "$REPO_REAL" "$SESSION_ID"

    # THE HOLDS AND THE LEDGER, BEFORE ANY ARM (wave-21 T13). Every arm below — no plan, an
    # unreadable `current:`, Step-3 approval pending, no budget, no room at the gate, a fill —
    # gets them once, here, and none prints them again.
    tick_plan_report

    # THE UNTRIMMED READY SET, ASKED ONCE FOR EVERY ARM (wave-26 T13; review-6 F3). The WAIT
    # lines read it, and so does the WAITING line below the decision: "nothing ready" is said
    # only when this is empty. A row that is ready and not offered — a full writer budget, a
    # machine HOLD — is not "nothing ready".
    SCHED_READY_ALL=""; SCHED_IDLE_AT=""; SCHED_IDLE_OWED=""
    if [ -n "${SCHED_PLAN:-}" ] && [ "$POKER_RUN_OPEN" != unreadable ]; then
      SCHED_READY_ALL="$(fill_ready_set "$SCHED_PLAN" 99999 0 2>/dev/null | tr '\n' ' ')"
    fi

    # ── FILL. gap = the GATE's width − RUNNING, ready = pending tasks whose deps all landed.
    #
    # RUNNING IS `open` (WALLS/2): the rows already counted above, on THIS session's
    # roster — a `status=intended` row with no `landing-swept/v1` marker and no ack. It is
    # the loop's own count rather than a second walk, because two definitions of "running"
    # in one file is the drift the count exists to prevent.
    #
    # THE APPROVAL GATE COMES FIRST, ahead of the budget/readiness checks below (AC-5). A
    # plan below `current: 4` has not passed Step 3, and no reading of the budget or the
    # task table changes that — so this is a wall in front of the rest of the arm, not one
    # more branch beside them.
    #
    # AN UNREADABLE `current:` WITHHOLDS TOO, UNCONDITIONALLY (Step-6 review-a C-5,
    # review-b finding (c)/N-2). An empty field, or a value that is not a step number (the
    # retired task-scale `T<n>` among them), is a case where this gate cannot tell which
    # step the run is on — and falling through to the readiness/budget checks on THAT basis
    # is DOUBT-then-FILL: the one shape this arm exists to prevent, measured live on a plan
    # whose `current:` carried a sub-step letter (`3b`) that the old digit-only read
    # rejected as unreadable and then filled anyway. So this differs from an unreadable
    # RUNG, which falls back to the ceiling — there is no safe fallback for "did Step 3
    # pass," only "no."
    #
    # ONE LEDGER SHAPE (wave-31 T5; D2): `fill_step_token` answers the step number or nothing,
    # at every scale, and the withhold above is that empty answer.
    # ONE READ OF THE FIELD FOR THE WHOLE TICK (wave-19 REQ-6, D7): loaded here, in this
    # shell, so every `$( )` reader below — the step, the approval gate, the unreadable
    # report, the ready set — inherits the answer instead of parsing the plan again.
    #
    # AN UNREADABLE BOUND PLAN FILLS NOTHING, AND SAYS WHICH PLAN (wave-20 T1, REQ-2). Its
    # `current:`, its approval and its task table are all unreadable, and no other plan is
    # read in its place; the three reads below are skipped so the line names the cause
    # rather than a symptom ("current: unreadable (none)").
    SCHED_CURRENT=""; SCHED_STEP=""
    if [ -n "$SCHED_PLAN" ] && [ "$POKER_RUN_OPEN" != unreadable ]; then
      _fill_current_load "$SCHED_PLAN"
      SCHED_CURRENT="$(sched_plan_current "$SCHED_PLAN")"
      SCHED_STEP="$(fill_step_token "$SCHED_PLAN")"
    fi
    if [ "$POKER_RUN_OPEN" = unreadable ]; then
      say "no FILL — bound plan unreadable — ${SCHED_PLAN}"
    elif [ -n "$SCHED_PLAN" ] && [ -z "$SCHED_STEP" ]; then
      SCHED_CURRENT_RAW="$(_sched_plan_current_field "$SCHED_PLAN")"
      say "no FILL — plan current: unreadable (${SCHED_CURRENT_RAW:-none})"
    elif [ -n "$SCHED_PLAN" ] && ! fill_plan_approved "$SCHED_PLAN"; then
      # THE APPROVAL LINE FIRST: the fact the dispatch wall keys on, and
      # one half of `fill_ledger_live`; the step, its other half, is the arm below. The step is
      # named because it is what a reader looks for; the line says which fact is missing.
      say "no FILL — plan at current: ${SCHED_CURRENT:-$(_sched_plan_current_field "$SCHED_PLAN")}, Step-3 approval pending: ## SDLC State carries no approved-by: line"
    elif [ -n "$SCHED_PLAN" ] && [ "$SCHED_STEP" -lt 4 ]; then
      # THE APPROVAL LINE ALONE READIES NOTHING. A plan approved and still at Step 2 or 3 holds a
      # table nobody has started: `fill_ledger_live` and the table reader's `approval:plan` both wait
      # for `current:` to reach 4, so the line names the step that holds the fill.
      say "no FILL — plan at current: ${SCHED_CURRENT:-$SCHED_STEP}; a row is ready only from Step 4, and approved-by: alone readies none"
    elif [ -n "$SCHED_PLAN" ] && SCHED_ORDER="$(fill_order_open "$SCHED_PLAN")"; then
      # THE USER'S ORDER HOLDS THE FILL (lib/fill.sh `fill_order_open`): no row is offered while it
      # stands, and the stop wall, reading the same order, asks for none. The WAIT lines still print.
      say "no FILL — an order of the user stands: $(clean_whole "$SCHED_ORDER"); order lift ends it"
      tick_wait_report
    elif [ -z "$SCHED_PLAN" ]; then
      note "no FILL — no plan carrying an unfenced \"## SDLC State\" to read a budget or a task table from."
    else
      # NO CAP IS NOT A FAULT (wave-28 T9; D15, REQ-2 AC-2.9). Until wave-28 a plan with no
      # `parallel-budget: writers=<n>` took a note here telling Step 0 to write one. No plan owes
      # the line now, and a probe's number is no cap: with no person's cap the width below is the
      # gate's alone (`fill_cap` answers nothing, so `fill_gate_width` runs uncapped).
      # THE HOLDS AND THE LEDGER were printed by `tick_plan_report` above, and `SCHED_HOLDS`
      # still carries the step holds for the no-FILL line below (wave-21 T13).
      SCHED_CAP="$(fill_cap "$SCHED_PLAN")"
      # THE WIDTH IS THE GATE'S. The writer rows ready are offered one
      # at a time: `fill_gate_width` asks `gate_room` once per row, with the open writers not yet showing plus the rows already
      # offered on this reading counted as owed, and stops at the first no or at a person's cap.
      # A gate line that read no room offers none, so the line and the fill never disagree.
      SCHED_READY_W="$(fill_ready_tagged "$SCHED_PLAN" 2>/dev/null | awk -F'\t' '$2 == "w" { n++ } END { print n + 0 }')"
      SCHED_WIDTH="$TICK_OCCUPIED"
      [ "${SCHED_GATE_ROOM:-}" = yes ] \
        && SCHED_WIDTH="$(fill_gate_width "$TICK_OCCUPIED" "$SCHED_OWED" "$SCHED_READY_W" "$SCHED_CAP")"
      case "$SCHED_WIDTH" in ''|*[!0-9]*) SCHED_WIDTH="$TICK_OCCUPIED" ;; esac
      SCHED_GAP=$(( SCHED_WIDTH - TICK_OCCUPIED ))
      [ "$SCHED_GAP" -lt 0 ] && SCHED_GAP=0
      # WIDTH MAY IDLE (wave-38 T7; D22, AC-6.5): the gate gave room, every ready writer row was offered, and the
      # cap is not reached. `tick_wait_report` then asks the gate once past the rows offered (SCHED_IDLE_OWED) and
      # prints the SPLIT decision only on its yes.
      if [ "${SCHED_GATE_ROOM:-}" = yes ] && [ "$SCHED_GAP" -ge "$SCHED_READY_W" ] \
         && { [ -z "$SCHED_CAP" ] || [ "$SCHED_WIDTH" -lt "$SCHED_CAP" ]; }; then
        case "$SCHED_OWED" in ''|*[!0-9]*) ;; *) SCHED_IDLE_AT="$SCHED_WIDTH"; SCHED_IDLE_OWED=$(( SCHED_OWED + SCHED_GAP )) ;; esac
      fi
      # A FULL WRITER BUDGET STILL OFFERS THE READ-ONLY ROWS (wave-26 T13; D9): a verify or
      # review row takes no writer slot, and `fill_ready_set` offers it whatever the gap. So
      # the set is asked at a closed gap too, and "the budget is full" is said only when it
      # offered nothing.
      SCHED_RO_READY=""
      [ "$SCHED_GAP" -eq 0 ] && SCHED_RO_READY="$(fill_ready_set "$SCHED_PLAN" "$SCHED_WIDTH" "$TICK_OCCUPIED")"
      if [ "$SCHED_GAP" -eq 0 ] && [ -z "$SCHED_RO_READY" ] && [ "$SCHED_READY_W" -gt 0 ]; then
        SCHED_READY=""
        if [ -n "$SCHED_CAP" ] && [ "$TICK_OCCUPIED" -ge "$SCHED_CAP" ]; then
          say "no FILL — the cap writers=${SCHED_CAP} is reached by ${TICK_OCCUPIED} unacked roster row(s); ${SCHED_READY_W} writer row(s) wait."
        else
          say "no FILL — the gate gives no room (its line above); ${SCHED_READY_W} writer row(s) wait."
        fi
      else
        # READY IS THE PREREQUISITE GRAPH (wave-20 REQ-5, Δ1, Δ6; ADR-036). Through
        # 1.8.6 ready was asked at the step the plan is on (REQ-1e, AC-1e.4), and a
        # Step-6 review whose deps had landed sat unfilled all through Verify. A work
        # row is now ready when it is pending and every dependency has landed, whatever
        # its step; only a gate act — an integrate or close row, or a doc row at Step 7
        # or later (the release; T10b) — still waits for `current:` to reach its step.
        # `SCHED_STEP` is still passed — it is what holds those gate acts — already read
        # and already proven readable by the approval gate above, which is why this needs
        # no second parse and no fallback: a `current:` that would not parse took the
        # withhold arm and never reached here.
        #
        # AND THE SET IS THE LIBRARY'S, TRIM INCLUDED (wave-18 REQ-3, D2; ADR-033
        # decision 2). `fill_ready_set` is what `payload/scripts/lib/stop.sh`'s fill
        # duty computes at the end of every turn, so the rows this tick ORDERS and the
        # rows that turn's end REFUSES to leave undispatched are one answer rather than
        # two. It takes the width and the occupancy this arm measured: the gate's width, and
        # the roster's unacked rows after this tick's own acks. The wall measures both the
        # same way (the width from `fill_gate_width`, the occupancy by the same predicate:
        # wave-19 audit V-2, T2d), so what it names is what this prints.
        SCHED_READY="${SCHED_RO_READY:-$(fill_ready_set "$SCHED_PLAN" "$SCHED_WIDTH" "$TICK_OCCUPIED")}"
        SCHED_IDS=""; SCHED_N=0; SCHED_OFFERED=""
        while IFS= read -r TASK_ID; do
          [ -n "$TASK_ID" ] || continue
          # THE LINE PRINTS THE AGENT NAME, NOT THE TASK ID (T22, A-orch-33). They are the
          # same string for a task that has never run, which is why every fixture and every
          # doc example still reads `FILL T1 T2`. They diverge when the id is already spent,
          # and then the ONLY safe token to print is the free one: see `fill_name` for why
          # the roster, and not the plan, is what "spent" is read from.
          SCHED_IDS="${SCHED_IDS}${SCHED_IDS:+ }$(fill_name "$ROSTER_FILE" "$(clean "$TASK_ID")")"
          SCHED_N=$((SCHED_N + 1)); SCHED_OFFERED="${SCHED_OFFERED} $(clean "$TASK_ID")"
        done <<EOF
$SCHED_READY
EOF
        if [ "$SCHED_N" -gt 0 ]; then
          # THE PRINTED LINE IS THE DUTY WALL'S (payload/scripts/lib/stop.sh reads
          # `poker: FILL ` out of this turn's raw tool result) and is unchanged to the byte.
          # WHAT CHANGES is that the ids are also carried to the decision line, so a tick
          # that ordered work stops reporting that nothing was wanted (REQ-10 AC-10.2, D5:
          # observed 19:00:46Z as `poker: FILL T13` above `decision=QUIET`).
          say "FILL ${SCHED_IDS}"
          SCHED_FILL="$SCHED_IDS"
          # THE RANGE AN OFFERED REVIEW READS (wave-26 T32; T14, AC-6.5): one line per offered
          # row that reads `live:head`, naming the difference past the last review proof, from
          # the head this tick already read (UNITS_LIVE_HEAD; no git here). Before the first
          # review proof there is no range, and no line: the review reads all the landed work.
          # THE RANGE IS THE ROW'S (wave-27 T10; D4): a read row's starts at the oldest last
          # reading among its own questions, so two rows offered at once can print two ranges;
          # a bare `live:head` row's is the one range 1.11.0 printed.
          # WHAT MOVED INSIDE IT (wave-27 T43; D10; A-orch-48, A-orch-71): once every question
          # the row reads has its whole reading, a `MOVED` line names each plan row whose landing
          # lies inside the range, with the matrix criteria it serves. A landing is a merge the
          # run's landing record (`landing-proofs.log`, written by land) gives a row.
          # THE LIST IS PRINTED ONLY WHEN IT IS THE WHOLE RANGE (wave-27 T34; review pass 30
          # should-fix 1 and 2, A-orch-86): this tick lists the range's first-parent commits with
          # ONE `git rev-list` per offered row and hands them to the library, which runs no git.
          # When every one is the merge of a header naming a row (`units_unrecorded` prints
          # none), the rows are named (`units_rows_in_range`); otherwise one `MOVED unknown` line
          # says how many are not, in place of every other, and the read is the whole range. A
          # header with `row=—`, a commit made straight on the working branch and a landed row
          # of any kind that left no header are all that case. `MOVED none` is an empty range.
          while IFS="$(printf '\t')" read -r LR_ID _; do
            [ -n "$LR_ID" ] || continue
            case "$SCHED_OFFERED " in *" $LR_ID "*) ;; *) continue ;; esac
            SCHED_RANGE="$(units_live_range "$SCHED_PLAN" "$LR_ID" 2>/dev/null)"
            [ -n "$SCHED_RANGE" ] && say "RANGE $LR_ID ${SCHED_RANGE} — the review reads what landed past the last review proof, and no more"
            [ -n "$SCHED_RANGE" ] && units_whole_read "$SCHED_PLAN" "$LR_ID" || continue
            LR_REC="$(docs_root "$REPO_REAL" 2>/dev/null)/record/$(proof_plan_slug "$SCHED_PLAN")/landing-proofs.log"
            if ! LR_IN="$(git -C "$REPO_REAL" rev-list --first-parent "$SCHED_RANGE" 2>/dev/null)"; then
              say "MOVED unknown — the range's commits cannot be listed"
              continue
            fi
            [ -n "$LR_IN" ] || { say "MOVED none"; continue; }
            LR_UNK="$(printf '%s\n' "$LR_IN" | units_unrecorded "$SCHED_PLAN" "$LR_REC" 2>/dev/null | awk 'NF { n++ } END { print n + 0 }')"
            LR_MOVED=""
            [ "$LR_UNK" = 0 ] && LR_MOVED="$(printf '%s\n' "$LR_IN" | units_rows_in_range "$SCHED_PLAN" "$SCHED_RANGE" "$LR_REC" 2>/dev/null)"
            if [ -z "$LR_MOVED" ]; then
              # A range every commit of which a header names, and no row's last landing among
              # them, cannot be listed whole either: said as the same one line.
              [ "$LR_UNK" = 0 ] && LR_UNK="$(printf '%s\n' "$LR_IN" | awk 'NF { n++ } END { print n + 0 }')"
              say "MOVED unknown — ${LR_UNK} commit(s) in the range are no recorded landing"
              continue
            fi
            while IFS="$(printf '\t')" read -r LM_ID _ LM_CRIT; do
              [ -n "$LM_ID" ] && say "MOVED $LM_ID — ${LM_CRIT:-no criterion in the matrix}"
            done <<EOF_MV
$LR_MOVED
EOF_MV
          done <<EOF
$(units_live_rows "$SCHED_PLAN" 2>/dev/null)
EOF
        else
          # THE REASONS ARE PER ROW NOW (wave-26 T13; D9, AC-6.6). Through 1.10 this line
          # carried one sentence for every waiting row and named only the step holds; each
          # waiting row is on its own WAIT line below, with the read it lacks and the row
          # that writes it, the step holds among them.
          say "no FILL — width=${SCHED_WIDTH} occupied=${TICK_OCCUPIED} gap=${SCHED_GAP}, and no pending task is ready."
        fi
      fi
      tick_wait_report
      tick_finding_report
    fi

    }
    tick_plan_memoised tick_schedule
    }

    # "No roster" and "empty roster" are different facts, and only the latter may DISARM
    # (ap review A-1, item 2). A roster with zero verdict lines because the file plain does
    # not exist is indistinguishable, from the arithmetic alone, from a roster that exists
    # and legitimately has nothing open yet — but the first case is usually the wrong project
    # root having been resolved, and DISARM is silent and terminal for the rest of the
    # session (doctrine, skills/canonical-sdlc/SKILL.md §Dispatch: "DISARM also ends the
    # Patrol"). Checked only on the TOTAL=0 path: any row at all on the roster proves the
    # file exists, so OPEN=0-with-TOTAL>0 can never be the absent-file case.
    if [ "$TOTAL" -eq 0 ] && [ ! -e "$ROSTER_FILE" ]; then
      # AC-38 (fold-in ratified 2026-09-03): THE ARM SPLITS. "No roster" was one refusal
      # covering two states that deserve opposite answers, and the wrong one was observed on
      # this wave's own Patrol tick #1 — an orchestrator that had armed at engagement, was
      # standing in the right project, and had simply not dispatched anything yet got
      # REFUSED with a wall of candidate paths describing a root that was perfectly correct.
      # Arming precedes dispatch by design (SKILL.md §Dispatch: "arm at engagement"), so the
      # first tick of every run reaches this line, and answering it with a refusal teaches
      # the reader to ignore the one message that also reports a mis-resolved root.
      #
      # THE TWO STATES, and the fact that tells them apart:
      #   armed here, and the walk CHOSE a real `.bionic`  -> QUIET. The Patrol is doing its
      #     job; there is simply nothing on the roster yet. Exit 0, stamp kept (it was
      #     written above), one line, and no candidate walk — the root is not in doubt.
      #   anything else                                     -> the refusal below, unchanged.
      #
      # THE ARMING RECORD IS THE LOAD-BEARING HALF. It is written only by `arm`, and its
      # path is resolved against the SAME root the roster's is, so a tick that resolved the
      # wrong root finds no arming record there either and refuses — which is exactly the
      # failure the refusal exists to report. The root tag is the second guard, and it is
      # read off the walk taken ABOVE the stamp write for the reason given there.
      TICK_ARMED="$(patrol_armed_file "$SESSION_ID")" || TICK_ARMED=""
      if [ -n "$TICK_ARMED" ] && [ -f "$TICK_ARMED" ] && [ ! -L "$TICK_ARMED" ] \
         && [ "$TICK_ROOT_TAG" = "chosen" ]; then
        # THE SCHEDULER, FROM ITS ONE SITE (wave-26 T59; REQ-6 AC-6.6), above the decision line.
        # The rung (AC-17: on EVERY tick); the holds and the ledger (wave-21 T13: no roster yet
        # is the reader's no-roster rule, the gate's own, so what prints is what the gate would
        # refuse a writer's first commit on); then the ready set, FILL, WAIT and CHAIN, or the
        # line saying why there is none, the approval gate first. This is the first tick of every
        # run, so it is the tick where the batch not yet sent is most worth naming. Through T58
        # this arm printed the first two and exited, and the batch went unnamed.
        tick_scheduler
        # THE SENTENCE FIRST, THE DECISION LINE LAST (REQ-10 AC-10.4). Every band in this
        # verb prints its explanation above its machine line, so the last line a tick prints
        # is always the answer — whichever arm answered.
        #
        # THE BAND IS THE ROSTER ARM'S, FROM THE SAME `tick_band` (wave-26 T59; D5): a FILL this
        # tick printed makes it FILL, with its `fill=` field, exit 0; nothing ready, or approval
        # pending, leaves it QUIET, exit 0, stamp kept; a gate request raises it to NOTIFY.
        tick_band
        if [ "$TICK_DECISION" = NOTIFY ]; then
          tick_gate_report
          tick_decision_line NOTIFY "$TOTAL" "$OPEN" "" "" "${SCHED_FILL:-}" "" "$TICK_GATE_FIELD"
          exit 1
        fi
        if [ "$TICK_DECISION" = FILL ]; then
          tick_fill_sentence
          tick_decision_line FILL "$TOTAL" "$OPEN" "" "" "$SCHED_FILL"
          exit 0
        fi
        say "QUIET — armed, nothing dispatched yet on this session"
        tick_decision_line QUIET "$TOTAL" "$OPEN"
        exit 0
      fi
      die "REFUSED — no roster at $ROSTER_FILE; this is not the same as an empty one."
      die "An armed session with nothing dispatched yet is QUIET, and was answered above — so"
      die "reaching this line means the Patrol never armed here, or the wrong project root was"
      die "resolved. Either way nothing was read to decide DISARM from, and DISARM ends the"
      die "Patrol for the rest of this session."
      # THE WALK, SHOWN (2.4, AC-13). The sentence above names the likely cause and then
      # leaves the reader with the one question they cannot answer from a message: WHICH
      # ancestor was taken, and what was passed over to get there. That answer is a property
      # of the filesystem above their cwd, so it is printed rather than described —
      # `project_root_candidates` is the same walk `project_root` just took, one line per
      # ancestor with the reason it was rejected, and the chosen one marked. A phantom
      # `.bionic` nested under a project, a symlinked one, a `.bionic` that only exists
      # inside $HOME: each shows up as its own line with its own tag.
      die "The root came from this walk over the ancestors of $PWD (path, then verdict):"
      printf '%s\n' "$TICK_ROOT_WALK" | while IFS= read -r ROOT_CAND; do
        die "  $ROOT_CAND"
      done
      exit 2
    fi

    # THE RUN-STATE READ, taken only where it can change the answer. `TOTAL == 0` implies
    # `OPEN == 0` — the loop that raises OPEN is the loop that raises TOTAL — so this single
    # test covers both arms of the old predicate, and a roster with open work never pays for
    # a find over the docs tree.
    RUN_STATE=open
    RUN_STATE_WHY="the roster still carries open work"
    # THE TERMINAL DECISION KEEPS THE ROSTER'S COUNT, never the live set's (S19). DISARM
    # removes the stamp and ends the Patrol for the rest of the session, and the state it
    # would fire on here is precisely the one that most needs supervising: a row whose
    # contract is UNMET and whose agent has finished without delivering. `open=` and the
    # fill are advisory arithmetic and may be trimmed; this may not.
    if [ "$OPEN_ROSTER" -eq 0 ]; then
      # RESOLVED HERE, IN THIS SHELL, FIRST: `run_state` below runs in a command substitution,
      # so a latch it sets dies with the subshell and `sched_budget_read` would resolve and
      # announce a second time. One resolution in the parent, one announcement.
      resolve_run "$REPO_REAL" "$SESSION_ID"
      RUN_STATE_RAW="$(run_state "$REPO_REAL" "$(patrol_armed_file "$SESSION_ID")" "$SESSION_ID")"
      RUN_STATE="${RUN_STATE_RAW%%|*}"
      RUN_STATE_WHY="${RUN_STATE_RAW#*|}"
    fi

    # DISARM — no open row AND a run that says it is delivered, in a delivery that POSTDATES
    # this Patrol's arming (R-13: an older one is the previous run's close-out, still newest
    # while the new run's plan does not exist yet). "No open row" alone was the whole
    # predicate until 1.3.2, and it is also exactly what a live wave looks like between two
    # batches: every writer of a task landed, the next not yet briefed. The tick ended the
    # Patrol there, terminally, and the rest of the wave ran unsupervised (epic-20 W1
    # dogfood, idea §B-4; R-4, AC-13/AC-14). The first conjunct still generalizes the spec's
    # literal "disarmed on empty roster" to a roster whose every row is MET/WAIVED/acked (S2
    # design decision, logged to the plan); the second is what tells a finish from a lull.
    #
    # An empty roster on a run that has not delivered falls through to QUIET below, and QUIET
    # KEEPS THE STAMP — which is the half that matters on disk. The clock keeps running, the
    # arming wall stays satisfied, and hooks/patrol-revive.sh has nothing to report.
    if [ "$OPEN_ROSTER" -eq 0 ] && [ "$RUN_STATE" = delivered ]; then
      # THE RUNG ON THE TERMINAL TICK TOO (AC-17). The number is moot to a Patrol that is
      # stopping, and that is not the point: the acceptance criterion is that every tick
      # reports it, and an operator reading the last tick of a run in a transcript should not
      # have to know which arm printed the line and which did not.
      gate_report "$REPO_REAL" "$SESSION_ID"
      # …AND THE PLAN REPORT, for the same reason (wave-21 T13): a delivered run whose ledger
      # still carries a finding is one the gate would refuse, and this is the last tick to say so.
      tick_plan_memoised tick_plan_report
      tick_conclude DISARM
      tick_gate_report
      say "DISARM — no open row on this roster and the run is delivered (${RUN_STATE_WHY}); the Patrol may stop."
      tick_decision_line DISARM "$TOTAL" "$OPEN" "" "" "" "" "$TICK_GATE_FIELD"
      # THE LAST ACT OF A DISARM TICK. The decision is terminal — "the Patrol may stop" —
      # so the stamp this very tick wrote before it decided has to stop claiming a live
      # clock, or hooks/patrol-revive.sh reads the stop this line just chose as a death and
      # blocks every remaining turn of the session demanding a re-arm nobody wants (critic
      # C-2, epic-19 w1). It is LAST so that nothing above it can be skipped by it: the
      # decision line is already printed, and a removal that fails costs a late notice
      # rather than a lost decision.
      remove_patrol_stamp "$SESSION_ID" \
        || die "WARN — the Patrol stamp could not be removed; the death notice may fire on later turns."
      exit 0
    fi

    # ─────────────────────────────────────── the lease overrun (spec AC-28)
    #
    # A spawned worktree is a leased slot bound to the ledger row that dispatched its
    # writer, and the lease ends when that row is fact-discharged (design ledger C1). A tree
    # still standing after that is a slot counted against the worktree budget that nobody
    # holds — and nothing else in the fleet walks `.worktrees` against the roster, so it
    # stays invisible until someone runs out of budget.
    #
    # READ OFF THE VERDICT THIS TICK ALREADY TOOK. `$VERDICT_OUT` is one
    # `session-sweeper.sh verdict` over the whole roster, and it is where the discharge
    # vocabulary lives: `state=MET`/`WAIVED`, and the `acked=` the sweeper folds in from its
    # own ledger. A roster read on its own would miss every acked row. The library takes a
    # FILE, so the lines this tick is already holding are spilled to a temporary one and
    # removed again — never into `.bionic/tmp`, which is state the operator reads.
    #
    # THE CONVENTION AND THE PREDICATE ARE THE LIBRARY'S, not a second copy here:
    # `.worktrees/<dir>` belongs to the row named `W-<DIR>` uppercased, and "discharged"
    # means acked or MET/CLOSED/WAIVED. Three callers share that definition
    # (payload/scripts/lib/worktree.sh's header names them); this is the third.
    #
    # PLACED AFTER DISARM, BEFORE THE SCHEDULER. A run that has DELIVERED exits above, and
    # its standing trees are the integration step's assertion to make rather than a Patrol
    # line nobody is left to read.
    #
    # IT REMOVES NOTHING. `spawn-worktree.sh land` is the act and the orchestrator runs it;
    # the tick says the tree is standing and stops there.
    #
    # AND IT IS A NOTE, NOT A BAND (REQ-10 AC-10.3; D5). This walk used to feed NOTIFY, so a
    # tree left standing after its row was discharged raised the exit-1 band on EVERY tick
    # for the life of the tree — nothing here is remembered between ticks — and buried the
    # decision the roster had actually reached. A standing tree is a fact about disk: it
    # prints as `poker: note:` and it rides the decision line in a `trees=` field of its own,
    # where a reader that wants to act on it can find it without the tick having claimed
    # something was wrong.
    LEASE_TREES=""
    LEASE_FILE="$(mktemp "${TMPDIR:-/tmp}/bionic-poker-verdict.XXXXXX" 2>/dev/null)" || LEASE_FILE=""
    if [ -n "$LEASE_FILE" ]; then
      printf '%s\n' "$VERDICT_OUT" > "$LEASE_FILE" 2>/dev/null
      while IFS= read -r LEASE_LINE; do
        [ -n "$LEASE_LINE" ] || continue
        LEASE_PATH="$(printf '%s' "$LEASE_LINE" | cut -f1)"
        LEASE_ROW="$(printf '%s' "$LEASE_LINE" | cut -f2)"
        [ -n "$LEASE_PATH" ] && [ -n "$LEASE_ROW" ] || continue
        note "tree stands $LEASE_PATH — row discharged; land or remove"
        LEASE_TREES="${LEASE_TREES}${LEASE_TREES:+,}$(clean "$LEASE_PATH")"
      done <<EOF
$(worktree_lease_overruns "$REPO_REAL" "$LEASE_FILE")
EOF
      rm -f "$LEASE_FILE" 2>/dev/null || :
    else
      die "WARN — no temporary file for the lease walk; standing worktrees were not checked."
    fi

    # ─────────────────────────────────────── the scheduler: pressure, then fills
    #
    # PLACED HERE, after DISARM and before NOTIFY/QUIET, and the placement is the contract.
    # DISARM exits above: a run that has DELIVERED gets no fills, because there is nothing
    # left to fill. Everything else — a live wave, a lull between batches, a roster with an
    # overdue row — gets both the pressure reading and the fill decision, and then the
    # decision line it was already going to get. A tick that filled instead of notifying
    # would trade a report the operator asked for against one they did not.
    #
    # PRESSURE FIRST, ALWAYS. See the block comment above `space_field` for why the order is
    # not negotiable and why nothing here re-derives the budget. The armed first tick exits
    # above this line and calls the same `tick_scheduler` there (wave-26 T59).
    tick_scheduler

    # ─────────────────────────────────────── the ranked decision (REQ-10 AC-10.2; D5)
    #
    # ONE NOTIFY BAND, TWO CONTRIBUTORS, AND THEY ARE BOTH ABOUT A ROW: past its declared
    # duration, or quieter than its declared cadence. The standing worktree was the third
    # until this wave and is not one any more — it is a fact, printed as a note above and
    # carried in `trees=` below (AC-10.3). The rows and details are concatenated rather than
    # given a field each, so no consumer of this schema has to learn a new key to see them.
    #
    # THE BAND IS THE RANKED MAXIMUM, ascending: QUIET is the floor, a stand-down raises it to
    # STANDDOWN, a fill to FILL, a row needing surfacing to NOTIFY. DISARM is terminal and has
    # already exited. Every lower band keeps its own field, so nothing this tick learned is lost
    # to the band that won — a NOTIFY tick still reports the fill it ordered.
    #
    # STANDDOWN JOINS THE BAND (wave-24 T7, REQ-4 AC-4.2; D4). It fed none, so a tick that had
    # just named an agent to stop printed `decision=QUIET` under the line that named it.
    #
    # ONE COPY: `tick_band`, defined beside `tick_conclude` above, which the armed first tick
    # calls too (wave-26 T59).
    tick_band

    if [ "$TICK_DECISION" = NOTIFY ]; then
      # THE SENTENCES FIRST, ONE PER ARM THAT HAS SOMETHING — a tick holding only the other
      # arm's finding must not print an empty one.
      tick_gate_report
      [ -n "$NOTIFY_DETAIL" ] && say "NOTIFY — past declared duration: $NOTIFY_DETAIL"
      [ -n "$QUIET_DETAIL" ] && say "NOTIFY — quieter than the declared cadence: $QUIET_DETAIL"
      tick_decision_line NOTIFY "$TOTAL" "$OPEN" "$NOTIFY_ROWS" \
        "$(clean "${NOTIFY_DETAIL}${NOTIFY_DETAIL:+${QUIET_DETAIL:+; }}${QUIET_DETAIL}")" \
        "$SCHED_FILL" "$LEASE_TREES" "$TICK_GATE_FIELD"
      exit 1
    fi

    # THE QUIET LINE HAS TWO READINGS NOW, and printing the wrong one is how this fix would
    # be mistaken for the bug it repairs. "0 open row(s), none past their declared duration"
    # over a mid-run lull says nothing about why the Patrol did not stop, and its reader is a
    # model deciding whether the Patrol is broken. So the empty-roster reading names the run
    # state it decided from — which plan, and where that plan says the run is.
    # KEYED ON THE ROSTER'S COUNT, not the live one (S19). `RUN_STATE_WHY` is read only on
    # the empty-roster path above, and — more to the point — "no open row on this roster" is
    # a statement about the roster, which a liveness reading does not get to make false. The
    # live number is `open=` on the decision line, and the trim line above says so
    # whenever the two differ.
    if [ "$TICK_DECISION" = FILL ]; then
      tick_fill_sentence
    elif [ "$TICK_DECISION" = STANDDOWN ]; then
      say "STANDDOWN — ${SD_ORDER_NAMES} met and still on the panel; TaskStop each, or hold it."
    elif [ "$OPEN_ROSTER" -eq 0 ]; then
      say "QUIET — no open row on this roster, but the run is not delivered (${RUN_STATE_WHY}); the Patrol keeps its stamp and its clock."
    else
      # NAMING BOTH READINGS, because both are now taken: a row can be inside its duration
      # and still have gone quiet, and a QUIET tick that named only the duration was the
      # sentence B5 reported as true-but-silent.
      say "QUIET — $OPEN_ROSTER open row(s) on this roster, none past their declared duration and none quieter than its declared cadence."
      # THE RUN IS WAITING ON ITS AGENTS (wave-26 T15, REQ-4 AC-4.5; D16, research-R2 §3 P5).
      # Nothing filled, nothing stands down, nothing needs surfacing, and a row is open: every
      # writer slot is taken or no row is ready. The Patrol prompt asks for nothing after this
      # line, and the duty above is none, so the turn ends here.
      #
      # ONLY WHEN NOTHING IS READY (wave-26 T13; review-6 F3). A QUIET tick can also be one
      # where a row IS ready and not offered: the writer budget is full. "nothing ready" is
      # false there, and each such row already
      # has its WAIT line saying why, so the line is left out.
      case "${SCHED_READY_ALL:-}" in
        *[!\ ]*) : ;;
        *) say "WAITING — ${OPEN_ROSTER} running, nothing ready" ;;
      esac
    fi
    tick_decision_line "$TICK_DECISION" "$TOTAL" "$OPEN" "" "" "$SCHED_FILL" "$LEASE_TREES"
    exit 0
  }
