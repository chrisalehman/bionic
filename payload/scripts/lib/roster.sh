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
# THE THREE INSTRUMENT FIELDS (wave-01 S13, spec AC-20) ARE OPTIONAL FOR THE SAME REASON.
# `files=`, `suites_allowed=` and `suites-source=` say how wide the dispatched agent's
# instrument may be: the files its brief declared, the suite basenames it may run, and
# whether that set was DERIVED from the tree by the configured impact command or DECLARED
# by the brief. They are present-if-passed rather than always-emitted so that the captured
# rows in `tests/fixtures/roster-row.captured` — real rows written before this slice
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

# The header comment line every roster file opens with. Both writers emit it when the file
# is absent; it carries the schema version, so it belongs beside the row that carries the
# same one rather than in two format strings that can disagree about which version this is.
roster_header() {  # -> the roster file's first line
  printf '# bionic session roster — schema roster-state/%s — machine-local, safe to delete\n' \
    "$ROSTER_SCHEMA_VERSION"
}

roster_row() {  # <key>=<value> ... -> the row on stdout; 2 on an unknown key or a bare word
  local status="" session="" name="" agent_id="" launched_at="" subagent_type=""
  local model="" deliverable="" source="" duration="" progress="" claims=""
  local cadence="" absent="" waiver="" teammate_id="" adopted_from="" tool_use_id="" plan=""
  local files="" suites_allowed="" suites_source=""
  local has_teammate_id=0 has_adopted_from=0
  local has_files=0 has_suites_allowed=0 has_suites_source=0
  local arg key val out

  for arg in "$@"; do
    case "$arg" in
      *=*) : ;;
      *) return 2 ;;
    esac
    key="${arg%%=*}"
    val="${arg#*=}"
    val="${val//|/ }"
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
      suites-source)  suites_source="$val";  has_suites_source=1 ;;
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
  if [ "$has_suites_source" -eq 1 ]; then  out="$out|suites-source=$suites_source"; fi
  if [ "$has_teammate_id" -eq 1 ]; then out="$out|teammate_id=$teammate_id"; fi
  if [ "$has_adopted_from" -eq 1 ]; then out="$out|adopted_from=$adopted_from"; fi
  out="$out|tool_use_id=$tool_use_id|plan=$plan"
  printf '%s\n' "$out"
  return 0
}
