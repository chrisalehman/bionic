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
# THE FOUR INSTRUMENT FIELDS (wave-01 S13, spec AC-20; `re_executes=` epic-23 wave-16,
# REQ-1) ARE OPTIONAL FOR THE SAME REASON. `files=`, `suites_allowed=`, `suites_source=` and
# `re_executes=` say how wide the dispatched agent's instrument may be: the files its brief
# declared, the suite basenames it may run, whether that set was DERIVED from the tree by the
# configured impact command or DECLARED by the brief, and — for a repository whose tests are
# not shell suites at all — the author-marked commands the brief declared it will re-run,
# marks kept, space-joined, at most three (hooks/dispatch-preflight.sh lifts them from the
# brief text under `Re-executes:`). `re_executes=` is the LAST of the four and TRAILS them,
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
# THE MEMBERS: the four bionic roles whose role files disallow Write and Edit, plugin-qualified
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
  local files="" suites_allowed="" suites_source="" re_executes=""
  local has_teammate_id=0 has_adopted_from=0
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
  out="$out|tool_use_id=$tool_use_id|plan=$plan"
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
# row's `launched_at=` (`_roster_discharged`). So a name acked and dispatched again names only
# the id launched after the ack, and a MET marker discharges nothing. The ledger is the
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
        if ((want in ACK) && _roster_discharged(_roster_kv(line, "launched_at"), ACK[want])) continue
        seen[id] = 1
        print id
      }
      close(f)
    }' </dev/null 2>/dev/null
  return 0
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
  # The open names of one roster, each followed by a newline, in first-seen order.
  function _roster_open_of(f, ledger, sid, rpfx,   ACK, seen, order, born, n, line, rs, nm, i, out) {
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
      born[nm] = _roster_kv(line, "launched_at")
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
# `identified`) was launched, and by nothing else:
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
