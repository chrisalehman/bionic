# payload/scripts/lib/roster.sh — THE ONE WRITER OF THE `roster-state/v1` ROW
# (wave-01 verification-cannot-lie, S14; spec AC-25; design ledger D3).
#
#     BIONIC_LIB_WANT="… roster.sh"
#     . "$BIONIC_LIB/roster.sh"
#
# WHAT IT REPLACES. Two hooks each built this row from their own format string:
# `hooks/dispatch-preflight.sh` at launch (`status=intended`) and
# `hooks/session-poker.sh`'s `adopt_write_row` at resume (`status=identified`, plus the
# two fields only it writes). They agreed by assertion — `tests/cross-gate-agreement.test.sh`
# §RA.2 scraped both source files and compared the key names it found — and that
# comparison could only ever catch the two DISAGREEING WITH EACH OTHER. Both drifting
# together, away from the shape the fleet's dozen readers parse, was invisible to it. D3
# ruled that the shape gets one code path and one pin against a row nobody in this repo
# wrote; this file is the code path.
#
# A BAG OF `key=value`, NOT A POSITIONAL SIGNATURE. Twenty-two fields, six of them
# routinely empty and five of them optional, is exactly the argument list where a positional call
# silently shifts every value one place left the first time a caller omits one — and the
# roster's readers are BY KEY, so a shifted row parses cleanly and lies. Naming each field
# at the call site also makes the two call sites diffable against each other by eye, which
# is what the old key-set test was trying to buy with a scraper.
#
# AN UNRECOGNISED KEY IS A REFUSAL, not a passed-through field. A field name no reader in
# the fleet knows is indistinguishable, on disk, from a field every reader expects and
# nobody writes; `tests/doctor-patrol.test.sh` has carried a fixture with an invented `ts=`
# for exactly as long as nothing checked. The caller gets a non-zero status and no row.
#
# THE DELIMITER IS THIS FUNCTION'S TO DEFEND. The row is pipe-delimited on one line, so a
# value carrying `|` or a newline forges a segment, and every by-key reader in the fleet
# takes the FIRST match — a forged `name=` ahead of the real one wins outright. Both
# callers already filter their values (`sanitize` in dispatch-preflight, `clean` in
# session-poker, the same body at different caps), and both filters begin with exactly this
# translation, so re-applying it here changes no byte either caller has ever written. It is
# here anyway, because "the one writer" that can still be handed a forged value is not one
# writer of anything. Done with parameter expansion, not `tr`: this runs on the dispatch
# path, once per field, and four subprocesses a field is a real cost for a guard that is a
# no-op on every value in practice.
#
# WHAT STAYS AT THE CALL SITES: the per-field LENGTH CAPS (200 for a name, 300 for a
# deliverable, 80 for a duration, 400 for a plan). Those encode what each field MEANS, not
# what the row IS, and a single cap applied here would either truncate fields the callers
# deliberately allow longer or wave through ones they deliberately hold shorter.
#
# FIELD ORDER IS THE ORDER ALREADY ON DISK. Readers are by key and never by position
# (`hooks/dispatch-preflight.sh`: "read BY KEY and never by position"), so order is not a
# contract for them — but a captured row is the only independent record of this schema that
# exists, and holding the writer to it byte for byte is what makes the pin able to fail.
# The two optional fields sit where `adopt_write_row` has always put them, between
# `waiver=` and `tool_use_id=`.
#
# PRESENT-IF-PASSED, NOT PRESENT-IF-NON-EMPTY. `teammate_id=` and `adopted_from=` appear on
# the row when the caller NAMES them, even empty. An adopt with no teammate address still
# writes `teammate_id=` empty today, and a reader distinguishing "no address" from "not an
# adopted row" would break if the field vanished with its value.
#
# THE TWO AUDIT KEYS OF A SUCCESSOR ROW (wave-20 T9, REQ-4) follow `adopted_from=` on the
# same terms. `amended=<iso> <reason>` is written by `session-poker.sh amend`, which widens a
# live contract; `extended=<iso> <reason>` by `session-poker.sh extend`, which re-opens a MET
# one. Each says when and why that row was appended, so the history is the row sequence. The
# extend reason used to ride `claims=`, which the sweeper hands to `pgrep -f` as a process
# pattern — a reason carrying `.*` then matched half the machine and held the row live. A row
# that names neither is byte-identical to the rows written before them.
#
# TWO ANSWER KEYS ride on the same terms (wave-24, REQ-4; ADR-041). `held=<iso> <reason>
# fp=<launch>:<deliverable mtime>:<completion-message count>` is written by `session-poker.sh
# hold`: the orchestrator's standing answer to a stand-down, honoured by the tick while the
# fingerprint is unchanged. `done=<path>` is the brief's `Done marker:`, lifted at dispatch.
# `held=` is never copied to a successor row: a new contract answers for itself. `done=` is
# copied by `hold` and `amend`, whose row is the same contract, and dropped by `extend`, whose
# re-opened row is new work (`row_copy_args` in hooks/session-poker.sh, `drop-done`).
#
# A READER'S QUESTIONS (wave-27 T15; REQ-5, D5). `questions=<q>[,<q>]` is the dispatch wall's
# record of a reader brief's `Questions:` line, in the order evidence, adversarial, structure;
# `hooks/execution-recorder.sh` pushes the checks file of each at agent start, and `proof-add
# review` reads it to hold a reading to the question its reader was dealt. Present-if-passed, and
# it TRAILS `plan=`: a row that names none is byte-identical to the rows before it.
#
# A DECLARED DEBT (wave-27 T31; REQ-14, D23). `lands_red=<suite> until <token>` and
# `red_evidence=<path under record/>` are the dispatch wall's record of a brief's `Lands-red:` and
# `Red-evidence:` lines; `land` honours a red last run of exactly that suite on a row that carries
# them. The dispatch wall is their one writer (`amend` refuses to add them), so a row carries them
# only from its launch. Present-if-passed, and they TRAIL `questions=`.
#
# WHAT A READER WAS PUSHED (wave-28 T16; REQ-8, D20). `pushed=<name>[,<name>]` names the context
# files `hooks/execution-recorder.sh`'s question registrations push at start, by file name
# without `.md` (`checks-adversarial,severity`); the recorder writes it on the row it identifies.
# A reading from a reader whose row carries `severity` there owes the finding lines. Present-if-
# passed: a row 1.12.0 wrote has none, and reads by every key it does carry.
#
# THE ROW AND THE SUITES IT LANDS ON (wave-28 T7; REQ-1, REQ-3, D4, D17). `row=<id>` is a brief's
# `Row:` label, the plan row the dispatch binds, read before the name match by the launch record,
# the fill and the stop wall; `lands_on=<a.test.sh,b.test.sh|none>` its `Lands-on:` line, the suites
# `ready` runs (lib/line.sh `_line_suites` decodes it). The dispatch wall writes both; `amend`, `hold`
# and `extend` copy them. Present-if-passed and they TRAIL `pushed=`: a row 1.12.0 wrote has neither.
#
# THE LANDING'S MARK (wave-28 T6; REQ-3, D7). `landed=<40-hex> landed_at=<ISO-UTC>` are written by
# `roster_mark_landed` (below), the landing's one act on the roster, and read by `roster_landed`:
# `stop-orders.sh stopped` removes the writer's tree only for a marked row. Present-if-passed and
# LAST, after `pushed=` and T7's `row=`/`lands_on=`: an unmarked row is byte-identical to the rows
# before them.
#
# THE RUN RECORD (wave-30 T8; REQ-3, D6). `run_pid= run_log= run_head= run_cmd= run_started_at=` are
# written by `roster_mark_run` (below) when `booked.sh --detach` starts a run for the name, and
# `run_rc= run_ended_at=` when that run ends: the run's detached process, its log (whose last line is
# `rc=<n>` once it ends), the head it ran on, its command (first 120 characters) and when. A row
# carries at most one run, its name's latest. Present-if-passed, in that order, after `lands_on=` and
# BEFORE `landed=`/`landed_at=`, which stay last: a row with no run is byte-identical to the rows
# before them.
#
# THE FOUR INSTRUMENT FIELDS (wave-01 S13, spec AC-20; `re_executes=` epic-23 wave-16,
# REQ-1) ARE OPTIONAL FOR THE SAME REASON. `files=`, `suites_allowed=`, `suites_source=` and
# `re_executes=` say how wide the dispatched agent's instrument may be: the files its brief
# declared, the suite basenames it may run, whether that set was DECLARED by the brief (a row
# 1.14.0 wrote may still say DERIVED, from the map deleted at wave-31), and — for a repository whose tests are
# not shell suites at all — the author-marked commands the brief declared it will re-run,
# marks kept, space-joined, capped per brief since T4 (wave-20, REQ-7) — three suite runs for
# a reader of the evidence question, DP_SUITES_MAX for every other (dp_runs_cap in lib/brief.sh;
# hooks/dispatch-preflight.sh lifts them from the brief text under `Re-executes:`).
# `re_executes=` is the LAST of the four and TRAILS them,
# so a row written before the field existed reproduces byte for byte through this writer. They are present-if-passed rather than always-emitted so that the captured
# rows in `tests/fixtures/roster-row.captured` — real rows written before this task
# existed — still reproduce byte for byte through this writer. A row from before the wall
# carries none of the three, and that absence is a THIRD state the readers partition on:
# an empty `suites_allowed=` is "no budget was stated", the literal token `none` is "this
# brief waived every suite", and neither is the same as a set of basenames.
#
# THEY SIT BETWEEN `waiver=` AND `teammate_id=` because they are CONTRACT fields — what the
# brief declared — and the contract fields are already grouped there. `hooks/execution-
# recorder.sh` rewrites an existing row field-wise with `RS = "|"` and reproduces every
# field in the order it read it, so a row that grows three fields anywhere still comes back
# out of the recorder unchanged; only its own appended `teammate_id=` is positional, and it
# appends at the END either way.

# THE STOP'S REASON IS A ROW KEY OF ITS OWN (wave-28 T77; A-orch-239 2a). `reason=<why>` rides the closed
# row `hooks/stop-guard.sh` appends when it honours the orchestrator's recorded stop of an agent the
# roster never saw: the sentence the orchestrator gave, so the sweeper and the Patrol see WHY the row is
# closed. Present-if-passed, after `done=` and before `tool_use_id=`, so a row 1.12.0 wrote is unmoved.
# It is prose like the rest (the `|` fold applies; nothing compares it back to something a human typed).
# It is NOT `source=` (the writer's word for where a deliverable's path came from; a stop has none) and
# NOT `waiver=` (the sweeper reads a waiver as a WAIVED contract, which would discharge the name's next
# stop: A-T70.7).

ROSTER_SCHEMA_VERSION="v1"

# ---------- THE READ-ONLY ROLE SET (wave-20 T7, REQ-9, D9, Δ12) ------------------------
#
# ONE DEFINITION OF "READ-ONLY", asked by every reader that has to tell a writer from a
# reader: the dispatch approval checkpoint (before Step-3 approval only these launch), the
# nested-dispatch arm (a subagent may launch only these), and the read-only commit arm
# (`payload/scripts/lib/walls.sh` ARM C). It lives here because the role is a roster field and
# this library owns the row.
#
# AN ALLOW-LIST, NOT A DENY-LIST. The approval arm used to name the two writer roles, so every
# type it had never heard of — `fork`, `general-purpose`, `claude`, a consumer's own agent —
# was admitted as if it were a reader (triage-B D2a). Here the unknown answers "writer".
#
# THE MEMBERS: the bionic roles whose role files disallow Write and Edit, plugin-qualified
# as the harness sends them, plus the harness's two no-write types `Explore` and `Plan`, bare
# as the harness sends them. A bare `researcher` is NOT a member: a consumer's own agent of
# that name may carry Write, and ARM C has always read the plugin-qualified spelling only.
# tests/cross-gate-agreement.test.sh §RC holds this constant equal to the role files.
#
# A CONSTANT, NOT A READ OF agents/*.md: ARM C runs on every Bash call in an agent context,
# and a file read there would be paid by every command (research D3-7).
ROLE_READONLY_SET="bionic:researcher bionic:test-runner bionic:auditor bionic:critic Explore Plan"

# A WHOLE-WORD MATCH WITHOUT WORD SPLITTING: the callers include walls.sh, which moves IFS
# around its argv readers, so a `for r in $SET` loop here would answer by whatever IFS it
# inherited. A type holding whitespace is never one name, and a quoted `$want` inside the
# pattern is literal text, so `*` or `?` in a type cannot match as a glob.
role_is_readonly() {  # <subagent_type> -> 0 a read-only role · 1 anything else, empty included
  local want="${1-}"
  case "$want" in ''|*[[:space:]]*) return 1 ;; esac
  case " $ROLE_READONLY_SET " in *" $want "*) return 0 ;; esac
  return 1
}

# ---------- WHAT A ROW COSTS (wave-24 T10, REQ-7 AC-7.1/7.2, D11; research R4 §1) -----------
#
# ONE CEILING, ONE ROLE FIELD. A writer slot is held by a role that can write the tree; a
# read-only role holds none, so the dispatch wall must neither count its open row nor ask a
# slot for its incoming dispatch, and the Patrol's fill must not read it as occupancy either.
# (A second rule lived here until wave-26 T8: a row holding a SUITE slot, for the hand-out
# suites ceiling. That ceiling is gone — a suite run books a machine-wide place as it starts,
# payload/scripts/lib/slots.sh — and so is its predicate.)
# The row carries its role as `subagent_type=` (no schema change), and this file owns
# `role_is_readonly`, so the question is answered here and nowhere else:
# `hooks/dispatch-preflight.sh` and `hooks/session-poker.sh`'s tick both call
# `budget_open_writers`, which is what keeps the open count the one refuses on and the
# occupancy the other fills against the SAME number.
#
# FAIL-CLOSED ON WHAT IT CANNOT READ. A name with no roster row, an empty `subagent_type=` and
# a type outside the allow-list all count as a writer (`role_is_readonly` answers "writer" for
# the unknown), and a roster that cannot be read counts every name — spending a slot on a row
# that might be a writer is the direction that refuses more, never less.
budget_open_writers() {  # <roster file>; stdin: the open names, one per line -> the writers among them
  local f="${1:-}" names types type nn n=0 ver="${ROSTER_VERSION:-$ROSTER_SCHEMA_VERSION}"
  names="$(cat)"
  [ -n "$names" ] || { printf '0'; return 0; }
  nn="$(printf '%s\n' "$names" | awk 'NF { c++ } END { printf "%d", c + 0 }')"
  if [ -z "$f" ] || [ ! -f "$f" ] || [ -L "$f" ] || [ ! -r "$f" ]; then
    printf '%s' "$nn"
    return 0
  fi
  # THE LATEST ROW OF EACH NAME carries the role the name runs as. One pass over the file; one
  # `T:<type>` line comes back per name asked for, in the order asked, the type empty when no
  # row names it. A reply that is not one line per name is not read: every name is a writer.
  types="$(ROSTER_BOW_NAMES="$names" ROSTER_BOW_F="$f" awk -v rpfx="roster-state/${ver}|" '
    BEGIN {
      nn = split(ENVIRON["ROSTER_BOW_NAMES"], ask, "\n")
      for (i = 1; i <= nn; i++) want[ask[i]] = 1
      f = ENVIRON["ROSTER_BOW_F"]
      while ((getline line < f) > 0) {
        if (index(line, rpfx) != 1) continue
        np = split(line, p, "|"); nm = ""; st = ""
        for (i = 1; i <= np; i++) {
          if (substr(p[i], 1, 5) == "name=") nm = substr(p[i], 6)
          else if (substr(p[i], 1, 14) == "subagent_type=") st = substr(p[i], 15)
        }
        if (nm in want) last[nm] = st
      }
      close(f)
      for (i = 1; i <= nn; i++) if (ask[i] != "") print "T:" ((ask[i] in last) ? last[ask[i]] : "")
    }' </dev/null 2>/dev/null)"
  if [ "$(printf '%s\n' "$types" | awk 'NF { c++ } END { printf "%d", c + 0 }')" != "$nn" ]; then
    printf '%s' "$nn"
    return 0
  fi
  while IFS= read -r type; do
    [ -n "$type" ] || continue
    role_is_readonly "${type#T:}" || n=$(( n + 1 ))
  done <<< "$types"
  printf '%s' "$n"
}

# The header comment line every roster file opens with. Both writers emit it when the file
# is absent; it carries the schema version, so it belongs beside the row that carries the
# same one rather than in two format strings that can disagree about which version this is.
roster_header() {  # -> the roster file's first line
  printf '# bionic session roster — schema roster-state/%s — machine-local, safe to delete\n' \
    "$ROSTER_SCHEMA_VERSION"
}

# ---------- THE DELIMITER, ESCAPED RATHER THAN LOST (T4, REQ-7, D4) ---------------------
#
# WHAT THE FOLD COSTS. Every value on this row used to have its `|` replaced by a space,
# and for prose and paths that is the right answer: nothing reads them back and compares
# them to something a human typed, so a forged segment is the only risk worth pricing.
# `re_executes=` is different in kind. Its value is a COMMAND, and
# `payload/scripts/lib/walls.sh`'s `_run_is_declared` compares it to the agent's own argv
# text character for character — so a fold there does not merely disfigure the value, it
# breaks the contract the field exists to carry. A jest or pytest brief declaring
# `--testPathPattern='(a|b)...'` was admitted at dispatch and then refused at run time for
# the very run its brief had declared (wave-16 T25's failure, through a different door).
#
# THE FORM IS PERCENT-ENCODING, and the choice is between three candidates:
#   * `%7C` (this one). `%` is rare in a test command, so a row stays readable by eye, and
#     the encoding is the one a reader already knows on sight from a URL.
#   * `\|`. Rejected: the commands that carry a pipe are regex commands, and regexes are
#     made of backslashes — `'(a|b)\.spec\.ts$'` would have to double every one of them,
#     turning the row into something no reader can check against the brief.
#   * a private sentinel (`<PIPE>`, `\x7c`). Rejected: a spelling nobody recognises, that
#     a command could contain by accident with no way to say it meant it.
#
# THE ESCAPE CHARACTER IS ESCAPED TOO (`%` -> `%25`, applied FIRST), which is what makes
# the pair a bijection rather than a one-way fold with better manners. Without it a command
# holding the literal text `%7C` would decode into a different command holding a pipe, and
# be admitted under the first one's name. Decoding reverses the order for the same reason.
#
# THE DELIMITER IS STILL DEFENDED. `%7C` holds no `|`, so an encoded value cannot forge a
# segment on a line every reader in the fleet parses BY KEY — the property the fold bought,
# kept, and now reversible.
#
# PLAIN IN MEMORY, ENCODED ON DISK — the rule every caller follows. `roster_row` encodes as
# it writes, so what is handed to it is always the command as the brief spelled it; every
# reader of the field decodes before it compares or prints. The one caller that is both,
# `adopt_write_row` in `hooks/session-poker.sh`, decodes what it lifted so this writer can
# encode it again, and the row it appends is byte-identical to the row it read.
#
# THE READER THAT CANNOT SOURCE THIS FILE. `payload/scripts/lib/walls.sh` runs inside
# `hooks/bash-walls.sh`, whose `BIONIC_LIB_WANT` does not carry `roster.sh` and whose wall
# table would have to grow a library for two parameter expansions. It spells the decode
# twin inline beside its one read of the field, with a comment naming this pair as the
# definition — the same posture `sanitize`/`clean` and `parse_seconds` already hold.
roster_pipe_escape() {  # <plain value> -> the value as the row stores it
  local v="${1//%/%25}"
  printf '%s' "${v//|/%7C}"
}

roster_pipe_unescape() {  # <stored value> -> the value as its author typed it
  local v="${1//\%7C/|}"
  printf '%s' "${v//\%25/%}"
}

roster_row() {  # <key>=<value> ... -> the row on stdout; 2 on an unknown key or a bare word
  local status="" session="" name="" agent_id="" launched_at="" subagent_type=""
  local model="" deliverable="" source="" duration="" progress="" claims=""
  local cadence="" absent="" waiver="" teammate_id="" adopted_from="" tool_use_id="" plan=""
  local files="" suites_allowed="" suites_source="" re_executes="" amended="" extended=""
  local held="" done_marker="" questions="" lands_red="" red_evidence="" pushed="" row="" lands_on="" reason=""
  local landed="" landed_at="" has_landed=0 has_landed_at=0
  local run_pid="" run_log="" run_head="" run_cmd="" run_started_at="" run_rc="" run_ended_at=""
  local has_run_pid=0 has_run_log=0 has_run_head=0 has_run_cmd=0 has_run_started_at=0 has_run_rc=0 has_run_ended_at=0
  local has_teammate_id=0 has_adopted_from=0 has_amended=0 has_extended=0
  local has_reason=0
  local has_held=0 has_done=0 has_questions=0 has_lands_red=0 has_red_evidence=0 has_pushed=0
  local has_row=0 has_lands_on=0
  local has_files=0 has_suites_allowed=0 has_suites_source=0 has_re_executes=0
  local arg key val out

  for arg in "$@"; do
    case "$arg" in
      *=*) : ;;
      *) return 2 ;;
    esac
    key="${arg%%=*}"
    val="${arg#*=}"
    # ONE FIELD ESCAPES, THE REST FOLD — see the pair above for why the two answers are
    # different answers. A subshell on one field of one row is a cost the dispatch path
    # does not feel; four of them on every field, which is what the fold's own comment
    # refused, is a different bill.
    case "$key" in
      re_executes) val="$(roster_pipe_escape "$val")" ;;
      *)           val="${val//|/ }" ;;
    esac
    val="${val//$'\n'/ }"
    val="${val//$'\r'/ }"
    val="${val//$'\t'/ }"
    case "$key" in
      status)        status="$val" ;;
      session)       session="$val" ;;
      name)          name="$val" ;;
      agent_id)      agent_id="$val" ;;
      launched_at)   launched_at="$val" ;;
      subagent_type) subagent_type="$val" ;;
      model)         model="$val" ;;
      deliverable)   deliverable="$val" ;;
      source)        source="$val" ;;
      duration)      duration="$val" ;;
      progress)      progress="$val" ;;
      claims)        claims="$val" ;;
      cadence)       cadence="$val" ;;
      absent)        absent="$val" ;;
      waiver)        waiver="$val" ;;
      tool_use_id)   tool_use_id="$val" ;;
      plan)          plan="$val" ;;
      teammate_id)   teammate_id="$val"; has_teammate_id=1 ;;
      adopted_from)  adopted_from="$val"; has_adopted_from=1 ;;
      amended)       amended="$val";      has_amended=1 ;;
      extended)      extended="$val";     has_extended=1 ;;
      held)          held="$val";         has_held=1 ;;
      done)          done_marker="$val";  has_done=1 ;;
      reason)        reason="$val";       has_reason=1 ;;
      questions)     questions="$val";    has_questions=1 ;;
      lands_red)     lands_red="$val";    has_lands_red=1 ;;
      red_evidence)  red_evidence="$val"; has_red_evidence=1 ;;
      pushed)        pushed="$val";       has_pushed=1 ;;
      row)           row="$val";          has_row=1 ;;
      lands_on)      lands_on="$val";     has_lands_on=1 ;;
      landed)        landed="$val";       has_landed=1 ;;
      landed_at)     landed_at="$val";    has_landed_at=1 ;;
      run_pid)        run_pid="$val";        has_run_pid=1 ;;
      run_log)        run_log="$val";        has_run_log=1 ;;
      run_head)       run_head="$val";       has_run_head=1 ;;
      run_cmd)        run_cmd="$val";        has_run_cmd=1 ;;
      run_started_at) run_started_at="$val"; has_run_started_at=1 ;;
      run_rc)         run_rc="$val";         has_run_rc=1 ;;
      run_ended_at)   run_ended_at="$val";   has_run_ended_at=1 ;;
      files)          files="$val";          has_files=1 ;;
      suites_allowed) suites_allowed="$val"; has_suites_allowed=1 ;;
      suites_source)  suites_source="$val";  has_suites_source=1 ;;
      re_executes)    re_executes="$val";    has_re_executes=1 ;;
      *) return 2 ;;
    esac
  done

  out="roster-state/${ROSTER_SCHEMA_VERSION}"
  out="$out|status=$status|session=$session|name=$name|agent_id=$agent_id"
  out="$out|launched_at=$launched_at|subagent_type=$subagent_type|model=$model"
  out="$out|deliverable=$deliverable|source=$source|duration=$duration"
  out="$out|progress=$progress|claims=$claims|cadence=$cadence"
  out="$out|absent=$absent|waiver=$waiver"
  if [ "$has_files" -eq 1 ]; then          out="$out|files=$files"; fi
  if [ "$has_suites_allowed" -eq 1 ]; then out="$out|suites_allowed=$suites_allowed"; fi
  if [ "$has_suites_source" -eq 1 ]; then  out="$out|suites_source=$suites_source"; fi
  if [ "$has_re_executes" -eq 1 ]; then    out="$out|re_executes=$re_executes"; fi
  if [ "$has_teammate_id" -eq 1 ]; then out="$out|teammate_id=$teammate_id"; fi
  if [ "$has_adopted_from" -eq 1 ]; then out="$out|adopted_from=$adopted_from"; fi
  if [ "$has_amended" -eq 1 ]; then  out="$out|amended=$amended"; fi
  if [ "$has_extended" -eq 1 ]; then out="$out|extended=$extended"; fi
  if [ "$has_held" -eq 1 ]; then     out="$out|held=$held"; fi
  if [ "$has_done" -eq 1 ]; then     out="$out|done=$done_marker"; fi
  if [ "$has_reason" -eq 1 ]; then   out="$out|reason=$reason"; fi
  out="$out|tool_use_id=$tool_use_id|plan=$plan"
  if [ "$has_questions" -eq 1 ]; then out="$out|questions=$questions"; fi
  if [ "$has_lands_red" -eq 1 ]; then out="$out|lands_red=$lands_red"; fi
  if [ "$has_red_evidence" -eq 1 ]; then out="$out|red_evidence=$red_evidence"; fi
  if [ "$has_pushed" -eq 1 ]; then out="$out|pushed=$pushed"; fi
  if [ "$has_row" -eq 1 ]; then      out="$out|row=$row"; fi
  if [ "$has_lands_on" -eq 1 ]; then out="$out|lands_on=$lands_on"; fi
  if [ "$has_run_pid" -eq 1 ]; then        out="$out|run_pid=$run_pid"; fi
  if [ "$has_run_log" -eq 1 ]; then        out="$out|run_log=$run_log"; fi
  if [ "$has_run_head" -eq 1 ]; then       out="$out|run_head=$run_head"; fi
  if [ "$has_run_cmd" -eq 1 ]; then        out="$out|run_cmd=$run_cmd"; fi
  if [ "$has_run_started_at" -eq 1 ]; then out="$out|run_started_at=$run_started_at"; fi
  if [ "$has_run_rc" -eq 1 ]; then         out="$out|run_rc=$run_rc"; fi
  if [ "$has_run_ended_at" -eq 1 ]; then   out="$out|run_ended_at=$run_ended_at"; fi
  if [ "$has_landed" -eq 1 ]; then out="$out|landed=$landed"; fi
  if [ "$has_landed_at" -eq 1 ]; then out="$out|landed_at=$landed_at"; fi
  printf '%s\n' "$out"
  return 0
}

# ---------- THE ONE READER OF "IS THIS NAME LIVE" (moved from hooks/stop-guard.sh, T6, ----
# ---------- A-orch-32; research R1 §5) --------------------------------------------------
#
# MOVED, NOT RE-SPELLED. `hooks/stop-guard.sh`'s own stop-ambiguity refusal (T29 §7) and
# `hooks/session-poker.sh`'s `adopt_write_row` (T6, AC-6.1) both need the identical answer to
# "does this name already name an open contract on this roster" — the first to refuse a stop
# that could not tell which of two live rows it meant, the second to keep an adopt from ever
# putting two live rows under one name in the first place. Two copies of this awk agreeing by
# construction is the same defect `roster_row` above already ends for the ROW's shape; this
# is that fix for the QUESTION asked of one.
#
# THE QUESTION, IN THE REGISTER'S OWN TERMS. Two rows of one name are an ambiguity — "this
# name is live twice" — when BOTH are under an open contract and carry DIFFERENT agent ids.
# An `intended` row carries no id yet — the recorder writes it one state later — and a
# lifecycle (intended -> confirmed -> identified) is ONE identity, so ids are counted
# DISTINCT: neither an unidentified row nor a re-stated one is a second agent.
#
# OPEN IS THE ONE CLOSE PREDICATE'S (epic-23 wave-20 T17, D10; T2's carry-over). This reader
# used to discharge a name's ids on a `landing-swept/v1|…|state=MET` marker and never read the
# sweeper's ledger, so it could call a name gone that every wall held open, and the reverse.
# Now nothing is live unless `roster_open_names` (below) answers the name open, and within an
# open name an id is discharged the way a name is: by an ack stamped strictly later than that
# row's OCCUPANCY STAMP (`_roster_occupied_at`: `restarted_at=` when the row carries one, else
# `launched_at=`; `_roster_discharged`) (T20d, review R3-1: was `launched_at=` alone, which
# left a restarted id discharged even while `roster_open_names` read its name open). So a name
# acked and dispatched again names only the id launched after the ack, a restarted id reads
# live again exactly as its name does, and a MET marker discharges nothing. The ledger is the
# roster's sibling, `sweeper-<sid>.state` — the path the sweeper writes it to — so neither
# caller grows an argument.
#
# READS `$ROSTER_FILE` (required, caller-set — every hook in the fleet already sets it
# before touching its own roster) and `$ROSTER_VERSION` (optional; defaults to this
# library's own `$ROSTER_SCHEMA_VERSION` above, so a caller that has never had reason to
# declare its own roster-schema constant, e.g. `adopt_write_row`, does not need to grow one
# just to call this).
live_ids_of_name() {  # <name> -> the agent ids currently under an open contract, one per line
  local f="$ROSTER_FILE" ver="${ROSTER_VERSION:-$ROSTER_SCHEMA_VERSION}" base ledger="" open nl='
'
  [ -f "$f" ] || return 0
  [ -L "$f" ] && return 0
  [ -r "$f" ] || return 0
  base="${f##*/}"
  case "$base" in
    roster-*.state) case "$f" in */*) ledger="${f%/*}/" ;; esac
                    ledger="${ledger}sweeper-${base#roster-}" ;;
  esac
  { [ -n "$ledger" ] && [ -f "$ledger" ] && [ ! -L "$ledger" ] && [ -r "$ledger" ]; } || ledger=""
  open="$(roster_open_names "$f" "$ledger")"
  case "$nl$open$nl" in *"$nl$1$nl"*) : ;; *) return 0 ;; esac
  ROSTER_OPEN_F="$f" ROSTER_OPEN_LEDGER="$ledger" \
  awk -v want="$1" -v rpfx="roster-state/${ver}|" "$_ROSTER_OPEN_AWK"'
    BEGIN {
      _roster_acks(ENVIRON["ROSTER_OPEN_LEDGER"], ACK)
      f = ENVIRON["ROSTER_OPEN_F"]
      while ((getline line < f) > 0) {
        if (index(line, rpfx) != 1) continue
        if (_roster_kv(line, "name") != want) continue
        if (!_roster_live(_roster_kv(line, "status"))) continue
        id = _roster_kv(line, "agent_id")
        if (id == "" || (id in seen)) continue
        if ((want in ACK) && _roster_discharged(_roster_occupied_at(line), ACK[want])) continue
        seen[id] = 1
        print id
      }
      close(f)
    }' </dev/null 2>/dev/null
  return 0
}

# ---------- THE ROW THE WALLS READ FOR AN ID (epic-23 wave-22 T1; REQ-1 AC-1.1/AC-1.6, D2) ----
#
# Every successor row written after an agent's id is known carries that id,
# and the status the id was learned under — so a row `amend` or `extend` writes is the row every
# reader with no status filter picks. The recorder's teammate `confirmed` copy carries no id by
# design, so an un-amended roster can still show an id-less latest row for a name; a reader that
# needs the id takes it from the latest row that carries one, within the dispatch cycle (the same
# tool_use_id; ADR-039 Δ1).
#
# The first sentence is the roster's one rule for successor rows, and this function is the half of
# it a reader can call. The suite-budget wall (payload/scripts/lib/walls.sh, the budget arm)
# keys on the transcript id the hook payload carries, so its contract for an agent is the LAST
# `roster-state/` row whose `agent_id=` is that id — no status filter, because a widened
# successor is as much the current statement as the row it copied. `session-poker.sh amend`
# asks the same question of the row it just wrote, so the verb's success line and the wall's
# reading cannot be two implementations that drift (wave-22 seed: `poker: amended` printed
# while the wall still read the pre-amend row). The verbs that append successors
# (`amend`, `extend`) hold the rule by copying the identity — `status=`, `agent_id=`,
# `teammate_id=` — from the agent's latest identified row; this reader only states it.
#
# FIRST OCCURRENCE OF A KEY WINS, as `line_field` and every by-key reader in the fleet take it
# (the writer refuses a forged second field; see THE DELIMITER above). The budget arm's inline
# awk this replaces matched `agent_id=<id>` in any segment and took the LAST `suites_allowed=`;
# only a forged row tells the two apart, and one reader settles which wins.
#
# EMPTY ID -> NOTHING, rc 1: an unidentified row carries `agent_id=` empty, and an empty key
# is not a key — matching it would hand every unidentified row to a caller with no id. A
# missing, unreadable or symlinked roster is rc 1 as well; a found row is printed, rc 0.
roster_row_for_id() {  # <roster> <id> -> the last roster-state/ row whose agent_id= is <id>; 1 when none
  local f="$1" id="$2"
  [ -n "$id" ] || return 1
  { [ -f "$f" ] && [ ! -L "$f" ] && [ -r "$f" ]; } || return 1
  ROSTER_FOR_ID_F="$f" ROSTER_FOR_ID="$id" \
  awk "$_ROSTER_OPEN_AWK"'
    BEGIN {
      f = ENVIRON["ROSTER_FOR_ID_F"]; want = ENVIRON["ROSTER_FOR_ID"]; found = 0
      while ((getline line < f) > 0) {
        if (index(line, "roster-state/") != 1) continue
        if (_roster_kv(line, "agent_id") != want) continue
        last = line; found = 1
      }
      close(f)
      if (!found) exit 1
      print last
      exit 0
    }' </dev/null 2>/dev/null
}

# ---------- THE PREDICATE'S ONE AWK TEXT (epic-23 wave-20 T17, D10) ----------------------
#
# `roster_open_names`, `roster_open_counts` and `live_ids_of_name` each run an awk program that
# BEGINS with this text, so the rule below (THE ONE READER OF "IS THIS NAME CLOSED") is spelled
# once and three readers cannot drift apart. It defines functions only; each caller adds its own
# driver. File paths reach it through ENVIRON or a field, never `-v`, which would read the
# backslashes in a path as escapes. Local arrays (`ACK`, `seen`, …) are fresh per call — that is
# how a function resets its sets without `delete arr`, which the one-true-awk this machine runs
# as `/usr/bin/awk` does not promise.
# shellcheck disable=SC2016  # awk source, expanded by awk and never by the shell
_ROSTER_OPEN_AWK='
  function _roster_kv(line, key,   i, n, parts) {
    n = split(line, parts, "|")
    for (i = 1; i <= n; i++) if (index(parts[i], key "=") == 1) return substr(parts[i], length(key) + 2)
    return ""
  }
  function _roster_live(st) { return (st == "intended" || st == "confirmed" || st == "identified") }
  # The one stamp shape both writers produce, spelled without an interval expression:
  # /usr/bin/awk here is the one-true-awk, and `{4}` is not a repetition count there.
  function _roster_stamp_ok(s) {
    return (s ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/)
  }
  # ACK[name] = the latest well-stamped ack of that name in the ledger ("" reads nothing).
  function _roster_acks(ledger, ACK,   aline, anm, aat) {
    if (ledger == "") return
    while ((getline aline < ledger) > 0) {
      if (index(aline, "sweeper-ledger/v1|") != 1) continue
      if (_roster_kv(aline, "event") != "ack") continue
      anm = _roster_kv(aline, "name"); if (anm == "") continue
      aat = _roster_kv(aline, "at");   if (!_roster_stamp_ok(aat)) continue
      if (!(anm in ACK) || aat "" > ACK[anm] "") ACK[anm] = aat
    }
    close(ledger)
  }
  # An ack discharges a launch only when both stamps are readable and the ack is strictly later.
  function _roster_discharged(born, ack) {
    return (_roster_stamp_ok(born) && _roster_stamp_ok(ack) && ack "" > born "")
  }
  # THE OCCUPANCY STAMP OF ONE ROW: its `restarted_at` when it carries one, else its
  # `launched_at` (epic-23 wave-20 T20c, critic C2-2; ONE FUNCTION as of T20d, review R3-1).
  # `hooks/execution-recorder.sh` writes `restarted_at=` on the one row that re-identifies an
  # id whose lineage an ack closed — the agent restarted, and holds a slot again — and keeps
  # `launched_at` as the launch of the contract, the clock the sweeper dates the deliverable
  # against. EVERY reader that answers whether a row is occupancy-discharged calls this, so a
  # restart re-opens what it should everywhere at once: the per-NAME answer `_roster_open_of`
  # gives AND the per-ID answer `live_ids_of_name` gives below. Before T20d each spelled its
  # own inline `restarted_at`-else-`launched_at` read (or, for `live_ids_of_name`, none at
  # all), and they drifted apart within the same commit that introduced the field — the file
  # design note two functions below ("three readers cannot drift apart") did not reach a
  # fourth call site, for want of a shared function for it to be a call site of.
  function _roster_occupied_at(line,   cand) {
    cand = _roster_kv(line, "restarted_at")
    if (cand == "") cand = _roster_kv(line, "launched_at")
    return cand
  }
  # The open names of one roster, each followed by a newline, in first-seen order.
  function _roster_open_of(f, ledger, sid, rpfx,   ACK, seen, order, born, n, line, rs, nm, i, out, cand) {
    _roster_acks(ledger, ACK)
    n = 0
    while ((getline line < f) > 0) {
      if (index(line, rpfx) != 1) continue
      if (!_roster_live(_roster_kv(line, "status"))) continue
      rs = _roster_kv(line, "session")
      if (sid != "" && rs != "" && rs != sid) continue
      nm = _roster_kv(line, "name"); if (nm == "") nm = "(unnamed)"
      gsub(/\t/, " ", nm)
      if (!(nm in seen)) { seen[nm] = 1; order[++n] = nm }
      # THE OCCUPANCY STAMP, the one shared function above (T20d) — restarted_at when the
      # row carries one, else launched_at — so the restart re-opens the NAME here without
      # re-opening the CONTRACT there.
      cand = _roster_occupied_at(line)
      # THE MAXIMUM STAMP, not whichever row happens to be LAST in file order (critic C7,
      # epic-23 wave-20 T20b). Adoption can append a predecessor row, carrying its own
      # earlier launched_at, after a fresher live row for the same name already on the file;
      # born[nm] must still read as the LATEST launch, or an ack taken between the two stamps
      # closes a name whose real latest launch is still open. The comparison is lexical (the
      # one stamp shape every writer emits).
      # AN UNREADABLE STAMP ON ANY LIVE ROW STICKS (T20c, review R2-2). A stamp that cannot be
      # ordered might be the latest launch, so once one is seen born[nm] stays unreadable and
      # _roster_discharged closes nothing, whatever order the rows sit in. The T20b rule let an
      # older well-formed stamp displace it, and an ack between them closed the name — the
      # rule below read backwards (fail-closed-constants: spending a slot on a row that might
      # still be working is the safe direction).
      if (!(nm in born) || (_roster_stamp_ok(born[nm]) && (!_roster_stamp_ok(cand) || cand "" > born[nm] ""))) born[nm] = cand
    }
    close(f)
    out = ""
    for (i = 1; i <= n; i++) {
      nm = order[i]
      if ((nm in ACK) && _roster_discharged(born[nm], ACK[nm])) continue
      out = out nm "\n"
    }
    return out
  }
'

# ---------- THE ONE READER OF "IS THIS NAME CLOSED" (epic-23 wave-20 T2, REQ-10, D10) ----
#
# FOUR SPELLINGS, FOUR ANSWERS. Until this wave four readers each carried their own rule:
# dispatch preflight closed a name on a `landing-swept/v1|state=MET` marker OR an ack taken
# after the row launched; the sweeper's `row_acked` and the stop wall's occupancy pass closed
# it on ANY ack of the name, ever; the tick's `adopt_fold` closed it on any ack or any MET
# marker. Driven both ways (triage-C claim 4): a name acked and dispatched again read open to
# preflight and closed to the rest, and a MET-but-unacked row read closed to preflight and to
# adopt and open to the sweeper and the stop wall. So the Patrol offered a FILL the dispatch
# wall refused, and the dispatch wall admitted a row the stop wall then counted over budget.
#
# THE RULE, IN ADR-034's TERMS: the ack is the one terminal state of a name. A name is closed
# when an ack for it was taken AFTER its latest live row (`intended`, `confirmed` or
# `identified`) was launched, and by nothing else. A row's launch, for this question, is its
# `restarted_at` when it carries one (a restart after an ack, T20c), else its `launched_at`:
#   * A MET MARKER CLOSES NOTHING. It records that a landing was seen, not that the agent
#     left; the Patrol acks the row once a fresh panel shows the agent gone.
#   * AN ACK OLDER THAN A RELAUNCH CLOSES NOTHING. The ledger holds no ordering against the
#     roster, so the comparison is by time: a name re-dispatched after its ack is open again.
#     The stamps compare lexically, which is exact for the one shape both writers stamp —
#     `date -u +%Y-%m-%dT%H:%M:%SZ` — and the ack is strictly later: an ack in the same
#     second as a launch cannot say which came first, and the safe direction is open.
#   * AN UNREADABLE STAMP ON EITHER SIDE CLOSES NOTHING. A stamp that is not that shape
#     (hand-written, truncated, empty) cannot be ordered, and spending a slot on a row that
#     might still be working is the fail-closed direction (rule fail-closed-constants).
#   * A NAME WITH NO LIVE ROW IS NOT ANSWERED. There is no contract to hold open, so it is
#     neither printed here nor counted; a reader that needs "was it ever acked" asks the
#     ledger itself (the sweeper's `acked=` does, for such a row).
#
# OUTPUT: the open names, one per line, in the order they first appear on the roster. An
# unnamed row answers as `(unnamed)`, the spelling the sweeper's verdict gives it, so an ack
# of that name can close it. `[session id]` keeps only rows of that session (a row with no
# `session=` is kept — the file is per-session by construction, and the filter only guards a
# hand-copied file); omit it for a predecessor's roster, whose rows carry its own id.
#
# A ROSTER THAT IS ABSENT, UNREADABLE OR A SYMLINK answers nothing, as `live_ids_of_name`
# does; a caller that must not read "nothing" as "all closed" checks for that first (the
# stop wall does). A LEDGER that is absent, unreadable or a symlink is read as empty — no ack
# — which leaves every live name open: the generous direction for occupancy.
roster_open_names() {  # <roster> [ack ledger] [session id] -> the open names, one per line
  local f="${1:-}" ledger="${2:-}" sid="${3:-}" ver="${ROSTER_VERSION:-$ROSTER_SCHEMA_VERSION}"
  [ -n "$f" ] && [ -f "$f" ] && [ ! -L "$f" ] && [ -r "$f" ] || return 0
  if [ -n "$ledger" ]; then
    { [ -f "$ledger" ] && [ ! -L "$ledger" ] && [ -r "$ledger" ]; } || ledger=""
  fi
  ROSTER_OPEN_F="$f" ROSTER_OPEN_LEDGER="$ledger" \
  awk -v sid="$sid" -v rpfx="roster-state/${ver}|" "$_ROSTER_OPEN_AWK"'
    BEGIN { printf "%s", _roster_open_of(ENVIRON["ROSTER_OPEN_F"], ENVIRON["ROSTER_OPEN_LEDGER"], sid, rpfx) }
  ' </dev/null 2>/dev/null
  return 0
}

# ---------- THE SAME PREDICATE OVER MANY ROSTERS, IN ONE PROCESS (epic-23 wave-20 T17) --------
#
# `hooks/session-start.sh` counts the open rows of EVERY predecessor roster under `.bionic/tmp`,
# and that count is bounded to one awk process however many files have piled up (REQ-6,
# carry-over P9: an awk per file measured ~10.4s at 400 dead sessions against the CLI's 10s hook
# timeout). So it cannot call `roster_open_names` once per file. It calls this, which runs the
# SAME awk text — `_ROSTER_OPEN_AWK`'s `_roster_open_of` — once per manifest line, so the
# post-/clear block and every wall close a name the same way (it used to close one on a MET
# marker or on any ack ever, D10's defect in a fifth place).
#
# INPUT on stdin, one line per roster: `<key>TAB<roster>TAB<ledger>` (ledger may be empty).
# The CALLER has already filtered each path — regular file, not a symlink — as the hook's
# loop does with builtins; a file that cannot be read answers no names here.
# OUTPUT: `<key>TAB<open-name count>TAB<roster>` for each roster with at least one open name.
# No session filter: a predecessor's rows carry its own id (see `roster_open_names`).
roster_open_counts() {  # stdin: key<TAB>roster<TAB>ledger -> key<TAB>count<TAB>roster
  local ver="${ROSTER_VERSION:-$ROSTER_SCHEMA_VERSION}"
  awk -F'\t' -v rpfx="roster-state/${ver}|" "$_ROSTER_OPEN_AWK"'
    $2 != "" {
      s = _roster_open_of($2, $3, "", rpfx)
      c = gsub(/\n/, "", s)
      if (c > 0) printf "%s\t%d\t%s\n", $1, c, $2
    }
  ' 2>/dev/null
  return 0
}

# ---------- THE LANDING'S MARK (wave-28 T6; REQ-3 AC-3.2, D7) ------------------------------
#
# `line_publish` marks a landed row once its fast-forward is published: the name's LATEST row,
# copied byte for byte, gaining `landed=<40-hex> landed_at=<ISO-UTC>` last, appended by one write
# (the append idiom every roster writer keeps: one `printf` of one line, no lock, no rewrite). The
# copy is the row `roster_row` would write if handed that row's keys and the two (the two are its
# last keys), so a by-key reader of the latest row sees the contract and the mark together.
# A second mark of the same commit appends nothing. rc 0 marked · 1 no row of that name · 2 refused.
roster_mark_landed() {  # <roster> <name> <40-hex commit> <ISO-UTC> -> 0 · 1 · 2
  local f="${1:-}" name="${2:-}" c="${3:-}" at="${4:-}" last
  case "$c" in *[!0-9a-f]*|'') return 2 ;; esac
  [ "${#c}" -eq 40 ] || return 2
  case "$at" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;; *) return 2 ;; esac
  case "$name" in ''|*'|'*|*$'\n'*) return 2 ;; esac
  { [ -f "$f" ] && [ ! -L "$f" ] && [ -r "$f" ]; } || return 1
  last="$(awk -v k="|name=${name}|" 'index($0, "roster-state/") == 1 && index($0 "|", k) { l = $0 } END { print l }' "$f" 2>/dev/null)"
  [ -n "$last" ] || return 1
  case "${last}|" in *"|landed=${c}|"*) return 0 ;; esac
  last="$(printf '%s\n' "$last" | awk -F'|' '{ o = $1; for (i = 2; i <= NF; i++) if (index($i, "landed=") != 1 && index($i, "landed_at=") != 1) o = o "|" $i; print o }')"
  printf '%s|landed=%s|landed_at=%s\n' "$last" "$c" "$at" >> "$f"
}

# THE RUN RECORD'S ONE WRITER (wave-30 T8; REQ-3, D6). `booked.sh --detach` marks the name's row
# when a run starts and again when it ends, by the append idiom `roster_mark_landed` keeps: the name's
# LATEST row, copied, its run fields replaced, appended by one `printf` of one line. The copy keeps
# every other field where it was, the run fields go where `roster_row` puts them (after the rest,
# before `landed=`/`landed_at=`, which are moved back to the end), so a by-key reader of the latest row
# sees the contract and the run together.
#
#   roster_mark_run <roster> <name> <run_log> run_<key>=<value>...
#
# A START names `run_pid=`: the row's old run fields are dropped and the given ones written. AN END
# names no `run_pid=`: the row must still name <run_log> as its run (a later start by the same name
# supersedes this one, and an end must never overwrite that newer record), and the given fields are
# added to the ones it has. A value is folded as `roster_row` folds one (`|`, line breaks and tabs
# become spaces). rc 0 marked · 1 no row of that name, or (an end) its run is another one · 2 refused:
# an unknown key, a bare word, a name or log that cannot be one field.
_ROSTER_RUN_KEYS="run_pid run_log run_head run_cmd run_started_at run_rc run_ended_at"
roster_mark_run() {  # <roster> <name> <run_log> run_<key>=<value>... -> 0 · 1 · 2
  local f="${1:-}" name="${2:-}" log="${3:-}" last arg key val start=0 given="" k cur
  case "$name" in ''|*'|'*|*$'\n'*) return 2 ;; esac
  case "$log" in ''|*'|'*|*$'\n'*) return 2 ;; esac
  shift 3 2>/dev/null || return 2
  for arg in "$@"; do
    case "$arg" in *=*) : ;; *) return 2 ;; esac
    key="${arg%%=*}"
    case " $_ROSTER_RUN_KEYS " in *" $key "*) : ;; *) return 2 ;; esac
    [ "$key" != run_pid ] || start=1
  done
  { [ -f "$f" ] && [ ! -L "$f" ] && [ -r "$f" ]; } || return 1
  last="$(awk -v k="|name=${name}|" 'index($0, "roster-state/") == 1 && index($0 "|", k) { l = $0 } END { print l }' "$f" 2>/dev/null)"
  [ -n "$last" ] || return 1
  if [ "$start" -eq 0 ]; then
    case "${last}|" in *"|run_log=${log}|"*) : ;; *) return 1 ;; esac
  fi
  # The given fields, folded, as one `key=value` per line; on an end, the row's own run fields first,
  # so a given one replaces them by coming later.
  if [ "$start" -eq 0 ]; then
    given="$(printf '%s\n' "$last" | awk -F'|' '{ for (i = 2; i <= NF; i++) if (index($i, "run_") == 1) print $i }')"
  fi
  given="${given:+$given
}run_log=${log}"
  for arg in "$@"; do
    val="${arg#*=}"; val="${val//|/ }"; val="${val//$'\n'/ }"; val="${val//$'\r'/ }"; val="${val//$'\t'/ }"
    given="$given
${arg%%=*}=$val"
  done
  # The row without its run fields and its landing's mark; then the run fields in their order (the
  # last value given for a key wins); then the mark, as it was.
  printf '%s\n' "$last" | ROSTER_RUN_GIVEN="$given" ROSTER_RUN_KEYS="$_ROSTER_RUN_KEYS" awk -F'|' '
    BEGIN {
      n = split(ENVIRON["ROSTER_RUN_GIVEN"], g, "\n")
      for (i = 1; i <= n; i++) { p = index(g[i], "="); if (p > 1) v[substr(g[i], 1, p - 1)] = substr(g[i], p + 1) }
      nk = split(ENVIRON["ROSTER_RUN_KEYS"], keys, " ")
    }
    {
      o = $1; m = ""
      for (i = 2; i <= NF; i++) {
        if (index($i, "run_") == 1) continue
        if (index($i, "landed=") == 1 || index($i, "landed_at=") == 1) { m = m "|" $i; continue }
        o = o "|" $i
      }
      for (j = 1; j <= nk; j++) if (keys[j] in v) o = o "|" keys[j] "=" v[keys[j]]
      print o m
    }' >> "$f"
}

# The mark of <name>'s CURRENT work: `<commit><TAB><at>` from the latest row carrying `landed=` since
# the name's latest launch line (a `status=intended` row no verb copied) and since its latest
# `extend` row (re-opened work is new work), whatever amend or hold rows came between. A mark written on a
# re-opened row keeps that row's `extended=` and is read as the mark it is (wave-28 T21, A-orch-105 #2); an extend
# row carrying a commit already seen has only copied an earlier landing's keys, and clears the mark. rc 1 when none.
roster_landed() {  # <roster> <name> -> commit<TAB>at; 1 when the current work carries no mark
  local f="${1:-}" name="${2:-}"
  [ -n "$name" ] || return 1
  { [ -f "$f" ] && [ ! -L "$f" ] && [ -r "$f" ]; } || return 1
  awk -F'|' -v k="|name=${name}|" '
    function kv(key,   i) { for (i = 2; i <= NF; i++) if (index($i, key "=") == 1) return substr($i, length(key) + 2); return "" }
    index($0, "roster-state/") != 1 || !index($0 "|", k) { next }
    { c = kv("landed") }
    c != "" && !index($0, "|extended=") { m = c "\t" kv("landed_at"); seen[c] = 1; next }
    c != "" && !(c in seen) { m = c "\t" kv("landed_at"); seen[c] = 1; next }
    c != "" { seen[c] = 1 }
    index($0, "|extended=") || (index($0, "|status=intended|") && !index($0, "|amended=") && !index($0, "|held=") && !index($0, "|adopted_from=")) { m = "" }
    END { if (m == "") exit 1; print m }' "$f" 2>/dev/null
}

# ---------- WHICH ROSTERS OF THE PROJECT HOLD A NAME (wave-28 T77; A-orch-239, A-orch-241) ----------
#
# ONE READ OVER EVERY `roster-*.state` OF A STATE DIRECTORY, asked "does any roster hold a row of this
# name". `stop-orders.sh unrostered` and the stop guard's unrostered branch used to answer "the roster never
# saw this agent" from THIS session's file alone, so a writer a predecessor's roster still held (the state
# every `/clear` leaves until `adopt` copies the rows) was recorded as unrostered and its stop passed. Both
# now ask this function; the guard's `accepted_addresses` is the same walk and calls it too.
#
# The walk is `adopt`'s own (`hooks/session-poker.sh`, its `for ADOPT_RF in … roster-*.state` loop, which is
# inline there and not callable): a regular file, never a link, the session id off the file name. Unlike
# `adopt` it does NOT skip this session's roster, and it does not ask whether the session is alive: a dead
# session's roster counts, because a row is a row until the sweeper removes the file.
#
# AN ANSWER PER ROSTER: `<session-id>|<status>`, the status of the LAST row of the name on that roster (the
# row `adopt` and the guard would read), one line per roster that holds one. Nothing printed, rc 0, when no
# roster does. A file this process cannot open holds nothing it can read, like every other reader here.
roster_sessions_with_name() {  # <state dir> <name> -> "<session-id>|<status>" per roster holding a row of the name
  local dir="$1" name="$2" f sid st
  [ -n "$name" ] || return 0
  for f in "$dir"/roster-*.state; do
    [ -f "$f" ] || continue
    [ -L "$f" ] && continue
    sid="${f##*/}"; sid="${sid#roster-}"; sid="${sid%.state}"
    [ -n "$sid" ] || continue
    st="$(ROSTER_WN="$name" awk "$_ROSTER_OPEN_AWK"'
      index($0, "roster-state/") == 1 && _roster_kv($0, "name") == ENVIRON["ROSTER_WN"] { found = 1; last = _roster_kv($0, "status") }
      END { if (found) print "=" last }' "$f" 2>/dev/null)"
    case "$st" in "="*) printf '%s|%s\n' "$sid" "${st#=}" ;; esac
  done
  return 0
}
