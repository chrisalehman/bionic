# shellcheck shell=bash
# hooks/poker/line.sh — the landing line: a row lands itself, the run's numbers and hand-holds
# (the record row's landing by the tick, reviews-part, known-limits-part, release-note).
#
# A part of hooks/session-poker.sh, which sets every global and loads this file before any verb runs. A part
# defines functions only, and is never run by itself.

# ---------------------------------------------------------------- a record row lands itself
#
# THE RECORD ROW'S OWN LANDING. A test, verify or review row writes a record and no code, so it has no tree and no
# `ready`. It lands when its writer has ended with its contract met: the tick finds it so and runs `record_row_land`,
# which checks what the row owes (`deliver_check`) and appends one `published` event at the working head, of the
# record kind, naming the row's writer and its record. No verb lands one, and nothing is written to the row's cells.
#
# THE ROW'S WRITER (wave-34 T4; burns debt row-writer-name): `ready`'s answer, lib/line.sh
# `line_row_writer`, loaded here the first time it is asked, so the tick's landing of a record row holds
# it to the writer `ready` would. Sets ROW_WRITER (empty when the row names no one); 1 when the library
# cannot be loaded.
row_writer() {  # <roster> <plan> <row> <agent cell>
  ROW_WRITER=""
  declare -F line_row_writer >/dev/null 2>&1 || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1
  declare -F line_row_writer >/dev/null 2>&1 || return 1
  line_row_writer "$@"
  ROW_WRITER="$LINE_WRITER"
  return 0
}

# deliver_check -> for the row $PV_ID of the opened plan ($PV_PLAN, $PV_REPO), sets RL_COMMIT, RL_AT
# and RL_ARTIFACT, or exits: 0 with nothing written when the row is already landed, 2 on a refusal,
# each naming what is missing and the call that answers it. In order:
#   - the row is in `## Tasks`, `pending` or `active`;
#   - it has no tree of its own and its Files write nothing the head carries (`units_writes_head`):
#     a row with a tree lands through `ready`, from that tree;
#   - a live review row (`units_live_rows`) lands only when the judge reads every question it carries covered at
#     the working head (lib/units.sh `units_live_held`, over lib/proof.sh `facts_state`): until then a landing
#     past its reading owes it another pass, and the refusal names each question that is not covered;
#   - its artifact: the ledger line's `artifact` cell, else the row's own `## Tasks` artifact cell (a
#     task-scale plan carries no ledger), else the one record under `<docs-root>/record/` its Files
#     name (a `.progress.md` and `assumptions.md` are bookkeeping, not the artifact). The file exists,
#     is no symbolic link, and lies under the docs root's `record/`. A row naming none, or several,
#     is refused naming the cell to edit in the plan: artifact when the Tasks header has the column, else Files;
#   - a review row: a `proved: kind=review` line under `## SDLC State` names that record;
#   - the working head reads as a commit;
#   - no ruling for the row's writer is unread.
deliver_check() {
  local row kind files wt status art docs drel abs real rel e n=0 cands="" call fix wb head sid roster rulings live lrc pl
  call="bash $HOOK_DIR/session-poker.sh"
  if ! { declare -F proof_branch_head >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
     || ! declare -F proof_branch_head >/dev/null 2>&1; then
    die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
    exit 2
  fi
  row="$(units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' -v id="$PV_ID" '$1 == id { print; exit }')"
  if [ -z "$row" ]; then
    die "REFUSED — the ## Tasks table of $PV_PLAN carries no row $PV_ID; the plan is unchanged."
    exit 2
  fi
  kind="$(units_field "$row" kind)"; files="$(units_field "$row" Files)"
  wt="$(units_field "$row" worktree)"; status="$(units_field "$row" status)"
  case "$status" in
    landed) say "$PV_ID is already landed; nothing was written."; exit 0 ;;
    pending|active) : ;;
    *) die "REFUSED — $PV_ID reads $(clean "$status"), and only a pending or active row lands; the plan is unchanged."; exit 2 ;;
  esac
  case "$wt" in
    *[A-Za-z0-9]*)
      die "REFUSED — $PV_ID has a tree of its own ($(clean "$wt")), and a row with a tree lands through ready, from that tree: bash <plugin-root>/scripts/spawn-worktree.sh ready. The plan is unchanged."
      exit 2 ;;
  esac
  if units_writes_head "$files"; then
    die "REFUSED — the Files of $PV_ID ($(clean "$files")) write the head, and a row that writes the head lands through ready from its tree: bash <plugin-root>/scripts/spawn-worktree.sh ready. The plan is unchanged."
    exit 2
  fi
  if [ -n "$(units_live_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' -v id="$PV_ID" '$1 == id')" ]; then
    live="$(units_live_held "$PV_PLAN" "$PV_ID")"; lrc=$?
    if [ "$lrc" -ne 0 ]; then
      die "REFUSED — $PV_ID is a live review row (it reads live:head), and it lands only once the judge reads every question it carries covered at the working head; not covered there: $(printf '%s\n' "$live" | awk 'NF { printf "%s%s", (n++ ? ", " : ""), $0 }'). Register the review at the head (proof-add review), then deliver again. The plan is unchanged."
      exit 2
    fi
  fi
  docs="$(docs_root "$PV_REPO")"; docs="$(cd "$docs" 2>/dev/null && pwd -P)"
  drel=""; case "$docs" in "$PV_REPO"/*) drel="${docs#"$PV_REPO"/}" ;; esac
  art="$(poker_brief_cell "$PV_PLAN" Tasks "$PV_ID" artifact 2>/dev/null)" || art=""
  case "$art" in *[A-Za-z0-9]*) : ;; *) art="" ;; esac
  if [ -z "$art" ]; then
    while IFS= read -r e; do
      e="${e#"${e%%[![:space:]]*}"}"; e="${e%"${e##*[![:space:]]}"}"; e="${e#!}"; e="${e#./}"
      case "$e" in *[A-Za-z0-9]*) : ;; *) continue ;; esac
      case "$e" in *.progress.md|assumptions.md|*/assumptions.md) continue ;; esac
      case "$e" in record/*) : ;; "${drel:-/}"/record/*) : ;; *) continue ;; esac
      n=$((n + 1)); cands="${cands:+$cands, }$e"; art="$e"
    done <<DELIVER_FILES
$(printf '%s\n' "$files" | tr ',' '\n')
DELIVER_FILES
    if pv_header_cells "$PV_PLAN" tasks 2>/dev/null | /usr/bin/grep -ix artifact >/dev/null; then
      fix="edit the artifact cell of $PV_ID in the plan to <path>"
    else
      fix="edit the Files cell of $PV_ID in the plan to name <path>"
    fi
    if [ "$n" -eq 0 ]; then
      die "REFUSED — $PV_ID names no artifact: no artifact cell names one and its Files name no record under record/; name it: $fix; the next tick lands it."
      exit 2
    fi
    if [ "$n" -gt 1 ]; then
      die "REFUSED — $PV_ID names no artifact in an artifact cell and its Files name $n records ($(clean "$cands")); name the one it delivers: $fix; the next tick lands it."
      exit 2
    fi
  fi
  case "$art" in
    *[[:space:]]*|*'|'*)
      die "REFUSED — the artifact $(clean "$art") of $PV_ID carries a blank or a |, which no plan cell can hold; the plan is unchanged."
      exit 2 ;;
  esac
  # A path is read as the plan spells it: absolute, from the docs root (`record/…`, as proof lines and
  # older ledgers write it), or from the repository (`.bionic/docs/record/…`, as Files cells do).
  case "$art" in
    /*) abs="$art" ;;
    record/*) abs="$docs/$art" ;;
    *) abs="$PV_REPO/$art" ;;
  esac
  if [ -L "$abs" ]; then
    die "REFUSED — the artifact $(clean "$art") of $PV_ID is a symbolic link, and what it points at can change after the landing; copy the record to that path; the next tick lands it."
    exit 2
  fi
  if [ ! -f "$abs" ]; then
    die "REFUSED — the artifact of $PV_ID, $(clean "$art"), does not exist (read as $(clean "$abs")); write it, and the next tick lands it."
    exit 2
  fi
  real="$(cd "$(dirname "$abs")" 2>/dev/null && pwd -P)/$(basename "$abs")"
  case "$real" in
    "$docs"/record/*) rel="${real#"$docs"/}" ;;
    *)
      die "REFUSED — the artifact $(clean "$art") of $PV_ID is not under record/ of the docs root ($docs/record/), and a record row delivers a record; the plan is unchanged."
      exit 2 ;;
  esac
  # A ROW THAT OWES A REGISTRATION LANDS ON IT, never on its file standing: a walk row on the walk's proof naming its
  # record (proof-add walk), a regression row on the whole run's proof at the head it lands at (proof-add regression),
  # a review row on its review registered (proof-add review, below). RL_WALK names a walk row's record from the docs root.
  if [ "$kind" = verify ]; then
    case "$rel" in record/*/walk.md) case "${rel#record/}" in */*/*) : ;; *) RL_WALK="$rel" ;; esac ;; esac
  fi
  if [ "$kind" = review ] || [ -n "$RL_WALK" ] || [ "$kind" = test ]; then
    pl="$(proof_lines "$PV_PLAN")" \
      || { die "REFUSED — the run's facts cannot be read, so whether the registration $PV_ID owes stands is not known; the next tick asks again."; exit 2; }
  fi
  if [ "$kind" = review ]; then
    if [ -z "$(printf '%s\n' "$pl" | awk -v rec="$rel" "$(proof_awk)"'
        proof_fields($0) && PROOF_KIND == "review" && PROOF_EVIDENCE == rec { print "y"; exit }')" ]; then
      die "REFUSED — $PV_ID is a review row and no review proof of the run names its record $rel; register the review first: $call proof-add review $rel --question <q> --reader <name>; the next tick lands it."
      exit 2
    fi
  fi
  # THE HEAD IS THE WORKING BRANCH'S REF (wave-36 T12; D13, AC-7.4; C30): lib/proof.sh `proof_branch_head`, the
  # judge's one reading of the head, so a merged branch whose worktree is gone still lands its record rows.
  wb="$(plan_working_branch "$PV_PLAN")"
  head="$(proof_branch_head "$PV_PLAN" "$PV_REPO")" || head=""
  case "$head" in
    [0-9a-f]*) [ "${#head}" -eq 40 ] || head="" ;;
    *) head="" ;;
  esac
  if [ -z "$head" ]; then
    die "REFUSED — the plan's working-branch ${wb:-(none named)} names no commit in $PV_REPO, so there is no head to land $PV_ID at; name the branch under ## SDLC State (working-branch: <branch>); the next tick lands it."
    exit 2
  fi
  if [ -n "$RL_WALK" ] && [ -z "$(printf '%s\n' "$pl" | awk -v rec="$RL_WALK" "$(proof_awk)"'
      proof_fields($0) && PROOF_KIND == "walk" && PROOF_EVIDENCE == rec { print "y"; exit }')" ]; then
    die "REFUSED — $PV_ID is the walk row and no walk proof names its record $RL_WALK; register the walk: $call proof-add walk $RL_WALK, and the next tick lands it."
    exit 2
  fi
  if [ "$kind" = test ] && [ -z "$(printf '%s\n' "$pl" | awk -v h="$head" "$(proof_awk)"'
      proof_fields($0) && PROOF_KIND == "regression" && PROOF_HEAD == h { print "y"; exit }')" ]; then
    die "REFUSED — $PV_ID is a regression row and no whole run's proof stands at the working head ${head:0:12}; register the run: $call proof-add regression <its log>, and the next tick lands it."
    exit 2
  fi
  # THE INTEGRATE ROW LANDS WITH THE ENTRY'S REVIEWS LISTED: its pull request carries the branch to the integration
  # branch, so a part still to render there would never reach it. A part the renderer would change refuses, naming
  # the verb that renders it; nothing to render (no release, entry or registered review) holds nothing back.
  if [ "$kind" = integrate ]; then
    if ! { declare -F line_reviews_state >/dev/null 2>&1 || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; } \
       || ! declare -F line_reviews_state >/dev/null 2>&1 || ! e="$(mktemp "${TMPDIR:-/tmp}/deliver-reviews.XXXXXX")"; then
      die "REFUSED — $PV_ID is the integrate row, and whether the release entry lists the plan's reviews cannot be read (lib/line.sh from $BIONIC_LIB); the plan is unchanged."
      exit 2
    fi
    if ! line_reviews_state "$PV_PLAN" "$PV_REPO" "$head" "$wb" "$e"; then
      rm -f "$e"
      die "REFUSED — $PV_ID is the integrate row, and whether the release entry lists the plan's reviews cannot be read: $LINE_RV_SAID; the plan is unchanged."
      exit 2
    fi
    rm -f "$e"
    if [ "$LINE_RV_STATE" = renders ]; then
      die "REFUSED — $PV_ID is the integrate row, and the $LINE_RV_VER entry's ### The reviews on $wb does not list the plan's $LINE_RV_N review and waiver lines, so its pull request would carry the entry without them; render them before the pull request: $call reviews-part $PV_ID; the next tick lands it."
      exit 2
    fi
  fi
  # AN UNREAD RULING HOLDS THE LANDING, as at the commit wall and `ready`: a record row's artifact is gitignored and
  # never commits, so this is its only landing. The writer is `ready`'s (`row_writer`). The tick never reaches this
  # read with a ruling unread (it holds the row first, stamping nothing); a ruling met here is printed and stamped
  # shown (lib/roster.sh `ruling_take_unread`), and the row lands at the next tick.
  sid="$(session_id)" || sid=""
  roster="$PV_REPO/.bionic/tmp/roster-${sid}.state"
  if ! row_writer "$roster" "$PV_PLAN" "$PV_ID" "$(units_field "$row" agent)"; then
    die "REFUSED — the row's writer cannot be read: lib/line.sh cannot be loaded from $BIONIC_LIB; the plan is unchanged."
    exit 2
  fi
  if [ -n "$sid" ] && declare -F ruling_take_unread >/dev/null 2>&1 \
     && rulings="$(ruling_take_unread "$roster" "$ROW_WRITER" deliver)" && [ -n "$rulings" ]; then
    die "REFUSED — an orchestrator ruling for $(clean "$ROW_WRITER") is unread ($(printf '%s\n' "$rulings" | sed -n 's/^bionic ruling \([^ ]*\) .*/\1/p' | paste -sd, - | sed 's/,/, /g')); read it below, act on it; the next tick lands it."
    printf '%s\n' "$rulings" >&2
    exit 2
  fi
  RL_COMMIT="$head"; RL_AT="$(iso_now)"; RL_ARTIFACT="$art"
}

# ---------------------------------------------------------------- the run's numbers
#
# THE RUN'S NUMBERS ARE FOLDED FROM THE TWO RECORDS, AND ONLY PRINTED (wave-28 T14; D18, REQ-4).
# `landing_report` reads the landing record's `line/v1` events and the gate's request files, and prints
#
#   landings: queue=<n> hand=<n> git=<n> · ready-to-landed median=<m>m p75=<m>m max=<m>m · runs: green=<n> red=<n> none=<n> discarded=<n> red-then-green=<n> run=<n> reused=<n> absent=<n> · waited median=<s>s · killed=<n>
#
# and with rows, one line per landed row in the record's order:
#
#   <row> <kind> ready=<ISO|-> landed=<ISO> minutes=<m|-> runs=<n> waited=<s>s|- wait=<m|-> prove=<m|-> rework=<m|-> width=<J|->
#
#   and under a row, one line per counted run whose verdict carries promised= or actual= (wave-39 T8; D11, AC-4.2):
#
#     <suite> <result> promised=<s>s|- actual=<s>s|- ratio=<actual over promised, %.2f>|-
#
#   indented two spaces, in the record's order, `-` for a field the verdict holds as `-` or lacks, and the ratio `-`
#   then or over a promise of 0. A verdict written before wave 39 carries neither field and prints no line.
#
# THE REPORT READS ADMISSION (wave-38 T7; D22, REQ-6 AC-6.4; it replaces wave-37 T9's ready/candidate/verdict split,
# whose prove carried the queue time between a candidate and its runs' admission). Over a queue landing's window, the
# row's first `ready` since it last landed to its `published`, in minutes (%.1f):
#   prove   the union of the row's counted runs' admitted time: each verdict's `admitted=` (the gate's own admission,
#           which lib/line.sh writes after `log=`, wave-38 T6) to the verdict's `at=`, overlapping runs counted once;
#   rework  each `returned` (red, conflict, guard) to the row's next `ready`, less any admitted time inside it (a run
#           discarded after the return is still proving until it ends);
#   wait    the rest: the window less prove and rework, the time no run of the row was admitted. So wait + prove + rework
#           is minutes, and waited (wait in seconds) never exceeds it.
# They are read from the landing record ALONE, never from the gate's requests (A-orch-43, A-orch-51): the store's
# asked-to-admitted tallies, summed over a landing's parallel runs, printed waited above the row's wall time, and they are
# pruned after BIONIC_GATE_KEEP. A counted verdict with no `admitted=` (written before 1.21.0) leaves the row's wait and
# prove uncomputable, `-` and waited=-, its rework still read from its events; `admitted=-` (no admission on record: a
# judged red) adds no admitted time. width is the `width=` on the row's verdict lines (the drain's, the last one
# numeric), `-` for none: absent, never 0. A hand or a git landing, or a queue landing with no ready, prints `-` for all.
#
# NOTHING READS THESE NUMBERS TO DECIDE (D18). The tick prints the first line outside its digest, so a
# landing moves no decision; no hook or wall library names the report (tests/docs-pins.test.sh §W28-46).
#
# THE DEFINITIONS (the plan's T14). Ready-to-landed is a queue landing's `published` time less its row's
# FIRST `ready` since the row last landed; a hand or a git landing prints `-` and joins no figure. Median
# and p75 are linear interpolation over the sorted minutes, wave-27's baseline rule: an even set's median
# is the mean of its middle two, a set of one is that value; an empty set prints 0. Runs count `verdict`
# events by result, a ROW'S runs only, by INCLUSION (wave-28 T68): a verdict is the row's only at one of the
# row's own commits since its last landing (a `ready` commit= or a `candidate` commit=). The accepted head's
# own run, which `_line_red_owner` records under the row id at the head's commit, is at none of them and is
# counted nowhere; a row that landed before starts its own set again at its next `ready`, and a row with no
# candidate since its last landing has no commit of its own to include by, so every verdict under its id counts
# (T14's count). Red-then-green is a red then a green for one row,
# one commit and one suite with no `ready` for that row between (an unchanged tree), counted once per such pair. Run
# counts the record's `ev=run` lines, one per regression run floor-run or a detached booked.sh run recorded (wave-37
# T4; D7, AC-6.2). Reused counts the record's `ev=reused` lines, each a suite a candidate did not run because another
# candidate's verdict at the same read key proved it (lib/line.sh, wave-39 T1; a skip is one naming the head, T4): the
# saving, beside the runs (wave-39 T2; D5, AC-1.4). Absent counts the verdicts `result=absent` by the inclusion rule, a
# Lands-on suite the row removed (wave-39 T6): no run, so it adds nothing to a row's runs=, width= or promise lines, and
# it is never malformed (A-orch-20). A reuse line lacking its suite= is malformed, as a verdict lacking one is. The waited median is the median of the rows' waits (THE REPORT READS ADMISSION, above), over the
# rows that compute one, 0 when none does. Killed is the one figure read from the gate: a request admitted that ended
# with an exit over 128 (a signal: 137 from the reaper, 143
# from a TERMed suite) or whose holder is dead with no `ended` line, as D18 says (lib/gate.sh `_gate_open`'s
# state, read through `_gate_read`, not retyped here; wave-28 T68, T72).
# A request counts when its `tree=` is the project or under it and it was asked at or after the record's
# first `line/v1` event. Times are the events' own `at=`, never a message's.
#
# UNMEASURED. A run whose landings no line recorded (a version-14 record with `landed:` lines and no
# `line/v1` event, a run open across the upgrade) prints the one line `landings: unmeasured — the landing record
# holds no line/v1 events`, and no row.
#
# THE LINES ARE THE READER'S. The report folds a history, every ready, run and verdict in turn, which the reader's
# standing facts no longer hold, so it reads the reader's own line source (lib/reader.sh `reader_events`): the run's
# log, or a version-14 run's homes as the translation reads them. A landing carries the kind its writer gave it; one
# with none (a plan's ledger landing the record never held) is not the line's, and is not measured. A caller names
# the plan, or the landing record the plan owns, which is joined back to its plan by the reader's own rule.
#
# FAIL-SOFT. A run with no lines is the line with zeros. A line this fold reads (`ready`, `verdict`, `returned`,
# `published`) that lacks a field it needs is skipped and counted, and the count is one line on stderr; an event of
# another kind is not this fold's. A request line the fold does not know (`peak=`, anything newer) is ignored. The
# gate's lock is not taken: this is a read, and a request the gate is writing reads as it stands.
_lr_reader() {  # -> 0 once the reader (lib/reader.sh, through lib/proof.sh's loader) is loaded
  { declare -F _proof_reader_load >/dev/null 2>&1 || { [ -r "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; } >/dev/null 2>&1; } \
    && _proof_reader_load
}
_lr_plan() {  # <plan or landing record> -> the plan; a record is its plan's when the reader joins that plan to its directory
  local dir name docs c
  case "$1" in *.plan.md) [ -f "$1" ] && printf '%s\n' "$1"; return ;; esac
  _lr_reader || return 1
  dir="${1%/*}"; name="${dir##*/}"; docs="$(cd "${dir%/*}/.." 2>/dev/null && pwd -P)" || return 1
  for c in "$docs/plans/$name.plan.md" "$docs"/plans/*/"$name.plan.md" "$docs/incidents/$name.plan.md" "$docs"/incidents/*/"$name.plan.md"; do
    [ -f "$c" ] && [ "$(reader_record "$c" 2>/dev/null)" = "$docs/record/$name" ] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}
# A plan the reader cannot join to a record has no log, and so no line.
_lr_lines() { ! reader_log "$1" >/dev/null 2>&1 || reader_events "$1"; }
_lr_events() {  # <plan> [instant] -> the run's lines as the reader reads them, those written after <instant> left out
  local l
  _lr_reader || return 0
  l="$(_lr_lines "$1" 2>/dev/null)" || return 2
  printf '%s\n' "$l" | awk -F'|' -v t="${2:-}" "$_READER_AWK"'NF > 1 && (t == "" || line_kv("at") == "" || line_kv("at") <= t)'
}
landing_unmeasured() {  # <plan or landing record> -> rc 0 when its run holds landings and none the line recorded
  local plan
  _lr_reader || return 1
  plan="$(_lr_plan "$1")" || return 1
  _lr_events "$plan" | _lr_unmeasured
}
_lr_unmeasured() {  # stdin: the run's lines -> rc 0 when a landing stands and no line of the landing line's own does
  awk -F'|' "$_READER_AWK"'
    { e = ev() } e == "published" && (line_kv("kind") == "" || line_kv("kind") == "record" || line_kv("kind") == "close") { l = 1; next }
    e ~ /^(ready|candidate|verdict|returned|published|run|reused)$/ { m = 1 }
    END { exit !(l && !m) }'
}
landing_report() {  # <plan or landing record> <project root> <rows yes|no> [instant] -> the line [and rows]; rc 0
  local src="$1" root="$2" rows="$3" plan lines="" gd f dead reqs="" out mal
  _lr_reader || { die "landing-report — the reader (lib/reader.sh) cannot be loaded from $BIONIC_LIB"; return 0; }
  plan="$(_lr_plan "$src")" && lines="$(_lr_events "$plan" "${4:-}")"
  gd="${BIONIC_GATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/gate}"
  for f in "$gd"/requests/*; do
    case "${f##*/}" in ''|*[!0-9]*) continue ;; esac
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    # lib/gate.sh's reader and its one rule (`_gate_open`, T71), lock-free: a request is killed when it ended with
    # an exit over 128 (D18: the reaper writes 137, a TERMed suite's 143 reaches `gate_end`) or was admitted,
    # never ended and has no live holder. No gate library, no requests.
    _gate_read "$f" 2>/dev/null || continue
    _R_state=''; _gate_open 2>/dev/null
    dead=0
    case "$_R_state" in
      killed|dying) dead=1 ;;
      ended) case "${_R_rc:-}" in ''|*[!0-9]*) ;; *) [ "$_R_rc" -le 128 ] || dead=1 ;; esac ;;
    esac
    reqs="${reqs}${_R_asked}	${_R_admitted}	${_R_tree}	${dead}
"
  done
  if [ -n "$lines" ] && printf '%s\n' "$lines" | _lr_unmeasured; then
    printf 'landings: unmeasured — the landing record holds no line/v1 events\n'; return 0
  fi
  out="$(printf '%s' "$reqs" | awk -F'|' -v root="$root" -v rows="$rows" "$_PATROL_ISO_AWK${_READER_AWK:-}"'
    function num(s) { return s ~ /^[0-9]+$/ }
    # adm <row> <lo> <hi> -> how many intervals MS/ME now hold: the admitted runs of the row clipped to [lo, hi], merged.
    function adm(rk, lo, hi,   i, j, m, s, t) {
      m = 0
      for (i = 1; i <= nad[rk]; i++) {
        s = as[rk, i]; t = ae[rk, i]; if (s < lo) s = lo; if (t > hi) t = hi
        if (t > s) { m++; MS[m] = s; ME[m] = t }
      }
      for (i = 2; i <= m; i++) {
        s = MS[i]; t = ME[i]
        for (j = i - 1; j >= 1 && MS[j] > s; j--) { MS[j + 1] = MS[j]; ME[j + 1] = ME[j] }
        MS[j + 1] = s; ME[j + 1] = t
      }
      j = 0
      for (i = 1; i <= m; i++) {
        if (j && MS[i] <= ME[j]) { if (ME[i] > ME[j]) ME[j] = ME[i] }
        else { j++; MS[j] = MS[i]; ME[j] = ME[i] }
      }
      return j
    }
    # cov <a> <b> <m> -> the seconds of [a, b] the m merged admitted intervals cover.
    function cov(a, b, m,   i, s, t, c) {
      c = 0
      for (i = 1; i <= m; i++) { s = (MS[i] > a) ? MS[i] : a; t = (ME[i] < b) ? ME[i] : b; if (t > s) c += t - s }
      return c
    }
    function sortn(a, n,   i, j, t) { for (i = 2; i <= n; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t } }
    function pct(a, n, p,   pos, lo, fr) {
      if (n == 0) return 0
      sortn(a, n); pos = p * (n - 1); lo = int(pos); fr = pos - lo
      return (lo + 1 < n) ? a[lo + 1] + (a[lo + 2] - a[lo + 1]) * fr : a[lo + 1]
    }
    phase == 0 { split($0, q, "\t"); nq++
      qa[nq] = q[1]; qd[nq] = q[2]; qt[nq] = q[3]; qx[nq] = q[4]; next }
    (et = ev()) == "" { next }
    # the kinds the landing record holds alone: the first of them opens the window the gate requests are counted in
    et !~ /^(ready|candidate|verdict|returned|published|run|reused|standing|stalled|walk|hand|admitted|void)$/ { next }
    # a landing no line ran, a record row or close-out or an older plan line, is no line landing
    et == "published" && (line_kv("kind") == "" || line_kv("kind") == "record" || line_kv("kind") == "close") { next }
    {
      rk = line_kv("row"); e = iso2epoch(line_kv("at"))
      g = rk SUBSEP (gen[rk] + 0)
      if (et == "run") nrl++
      if (et == "verdict" && line_kv("kind") == "regression") next   # facts of the whole run, no row ran them
      if ((et == "candidate" || et == "ready") && line_kv("commit") != "") ownc[g SUBSEP line_kv("commit")] = 1
      if (et == "candidate") hasc[g] = 1
      if (et == "candidate" && e >= 0 && !(rk in fc)) fc[rk] = e
      if (et != "ready" && et != "verdict" && et != "returned" && et != "published" && et != "reused") { if (e >= 0 && t0 == "") t0 = e; next }
      if (rk == "" || e < 0) { mal++; next }
      if (et == "verdict" && (line_kv("suite") == "" || line_kv("result") !~ /^(green|red|none|discarded|absent)$/)) { mal++; next }
      if (et == "reused" && line_kv("suite") == "") { mal++; next }
      if (et == "published" && line_kv("kind") !~ /^(queue|hand|git)$/) { mal++; next }
      if (t0 == "") t0 = e
      iso[e] = line_kv("at")
      if (et == "verdict" && line_kv("result") != "absent" && line_kv("width") ~ /^[0-9]+$/) wd[rk] = line_kv("width")
    }
    # THE SAVING (wave-39 T2; D5, AC-1.4): a suite proved by the verdict of another candidate, no run of its own.
    et == "reused" { nru++; next }
    et == "returned" { if (e >= 0) { nrw[rk]++; rs[rk, nrw[rk]] = e; re[rk, nrw[rk]] = "" }; next }
    et == "ready" {
      if (!(rk in rdy)) rdy[rk] = e
      for (i = nrw[rk]; i >= 1 && re[rk, i] == ""; i--) re[rk, i] = e
      span[rk]++; next
    }
    et == "verdict" {
      if ((g in hasc) && !((g SUBSEP line_kv("commit")) in ownc)) next
      res = line_kv("result"); cnt[res]++
      if (res == "absent") next   # a suite the row removed: no run, counted beside the runs only (A-orch-20)
      nrun[rk]++
      # THE PROMISE AND THE ACTUAL (wave-39 T8; D11, AC-4.2): one line per counted run that carries either field.
      if (line_kv("promised") != "" || line_kv("actual") != "") {
        vp = (num(line_kv("promised")) ? line_kv("promised") : "-"); va = (num(line_kv("actual")) ? line_kv("actual") : "-")
        vr = ((vp != "-" && va != "-" && vp + 0 > 0) ? sprintf("%.2f", va / vp) : "-")
        sv[rk] = sv[rk] sprintf("  %s %s promised=%s actual=%s ratio=%s\n", line_kv("suite"), res, (vp == "-" ? "-" : vp "s"), (va == "-" ? "-" : va "s"), vr)
      }
      # THE ADMISSION (wave-38 T7): the run was admitted from admitted= to this verdict; no field at all makes the row uncomputable.
      if (line_kv("admitted") == "") noad[rk] = 1
      else if (num(line_kv("admitted"))) {
        nad[rk]++; as[rk, nad[rk]] = line_kv("admitted") + 0; ae[rk, nad[rk]] = e
      }
      vk = rk SUBSEP span[rk] SUBSEP line_kv("commit") SUBSEP line_kv("suite")
      if (res == "red") red[vk] = 1
      else if (res == "green" && (vk in red)) { rtg++; delete red[vk] }
      next
    }
    et == "published" {
      k = line_kv("kind"); kinds[k]++; n++
      prow[n] = rk; pk[n] = k; pat[n] = line_kv("at"); pruns[n] = nrun[rk] + 0
      psv[n] = sv[rk]
      pfrom[n] = ((rk in rdy) ? rdy[rk] : "")
      if (k == "queue" && pfrom[n] != "") { pmin[n] = (e - pfrom[n]) / 60; mins[++nm2] = pmin[n] }
      # THE REPORT READS ADMISSION (wave-38 T7; AC-6.4), over the window [first ready, published].
      pws[n] = pw[n] = pp[n] = prw[n] = pwd[n] = "-"
      if (k == "queue" && pfrom[n] != "") {
        m = adm(rk, pfrom[n], e); pv = cov(pfrom[n], e, m); rw = 0; lt = pfrom[n]
        for (i = 1; i <= nrw[rk]; i++) {
          s = rs[rk, i]; t = (re[rk, i] == "") ? e : re[rk, i]
          if (s < lt) s = lt; if (t > e) t = e
          if (t > s) { rw += (t - s) - cov(s, t, m); lt = t }
        }
        prw[n] = sprintf("%.1f", rw / 60)
        if (!(rk in noad)) {
          ws = (e - pfrom[n]) - pv - rw; if (ws < 0) ws = 0
          pws[n] = sprintf("%ds", ws); pw[n] = sprintf("%.1f", ws / 60); pp[n] = sprintf("%.1f", pv / 60)
          wts[++nw] = ws
        }
        if (rk in wd) pwd[n] = wd[rk]
      }
      delete rdy[rk]; nrun[rk] = 0; delete fc[rk]; delete wd[rk]; delete noad[rk]; nad[rk] = 0; nrw[rk] = 0
      delete sv[rk]
      gen[rk]++
    }
    END {
      for (i = 1; i <= nq; i++) {
        inq[i] = (t0 != "" && num(qa[i]) && qa[i] >= t0 && (qt[i] == root || index(qt[i], root "/") == 1))
        if (inq[i] && num(qd[i]) && qx[i] == 1) killed++
      }
      wm = pct(wts, nw, 0.5)
      printf "landings: queue=%d hand=%d git=%d · ready-to-landed median=%.1fm p75=%.1fm max=%.1fm · runs: green=%d red=%d none=%d discarded=%d red-then-green=%d run=%d reused=%d absent=%d · waited median=%ds · killed=%d\n",
        kinds["queue"], kinds["hand"], kinds["git"], pct(mins, nm2, 0.5), pct(mins, nm2, 0.75), pct(mins, nm2, 1),
        cnt["green"], cnt["red"], cnt["none"], cnt["discarded"], rtg, nrl, nru, cnt["absent"], int(wm + 0.5), killed
      if (rows == "yes") for (r = 1; r <= n; r++) {
        rd = "-"; mn = "-"
        if (r in pmin) { rd = iso[pfrom[r]]; mn = sprintf("%.1f", pmin[r]) }
        printf "%s %s ready=%s landed=%s minutes=%s runs=%d waited=%s wait=%s prove=%s rework=%s width=%s\n",
          prow[r], pk[r], rd, pat[r], mn, pruns[r], pws[r], pw[r], pp[r], prw[r], pwd[r]
        if (psv[r] != "") printf "%s", psv[r]
      }
      if (mal) printf "#malformed %d\n", mal
    }' phase=0 - phase=1 /dev/fd/3 3<<< "$lines")"
  mal="$(printf '%s\n' "$out" | sed -n 's/^#malformed //p')"
  printf '%s\n' "$out" | /usr/bin/grep -v '^#malformed '
  [ -z "$mal" ] || die "landing-report — $mal malformed landing line(s) skipped in the run of $src"
  return 0
}

# ---------------------------------------------------------------- the run's hand-holds
#
# THE HAND-HOLD COUNT IS FOLDED FROM THE LINES THE ESCAPE-HATCH VERBS WROTE (wave-35 T12; D17, REQ-8
# AC-8.1). `landing-report --hand-holds` prints, under the landings line,
#
#   hand-holds: total=<n> · by-hand=<n> · stop-runs=<n> · declines=<n> · lifts=<n> · amends=<n> · holds=<n> · extensions=<n> · waivers=<n> · second-regressions=<n> · adoptions=<n> · fixed=<n> · needs-you=<n>
#
# A hand-hold is a use of a verb that steps round the machine. Each kind is counted from the one line its
# verb wrote, and PROSE IS NEVER READ (D1): a line that says `by-hand` in a plan, a note or the orchestrator's
# own assumptions counts nothing, and so does anything the orchestrator did that no verb recorded.
#
#   by-hand        the record's `ev=published|…|kind=hand|…` (lib/line.sh), one per landing.
#   stop-runs      the run's log's `run/v1|ev=hand|what=stop-run|…`, one per `stop-run` that stopped a run or ended a
#                  gate request (wave-36 T11; D8, AC-2.3). A stop is a verb act: never counted as by-hand.
#   declines       the log's `stop` events with `state=decline` and `state=lift`, one per `decline` and per
#   lifts          `decline lift`. No verb has written either since 1.24.0; the Stop hook's `stop` event carries `state=ok` or `state=hold` only,
#                  so a `hold` there is the fill's wait and not the `hold` verb.
#   amends         the log's `run/v1|ev=hand|what=amend|…` (`amend`), `what=hold` (`hold`) and `what=extend` (`extend`),
#   holds          one per act, placed by its `at=`. The roster row each verb also writes is the agent's contract and
#   extensions     never a count: the rosters are session state a close wipes, and the run's log is not.
#   waivers        each waiver event `waive` writes, of a question or a criterion, and the plan's older `waived:
#                  question=…` line under `## SDLC State`. Fenced text is skipped, as every reader of the plan skips it.
#   second-regressions  a whole run a person started, past the first. The tick and the orchestrator start the whole
#                  run as the machine does, so only a person's start is a hand-hold: the landing record's regression
#                  run lines (`ev=run`, a log under `regression-run-`, or `kind=regression`) past the record's first
#                  whose `starter=person` (`regression-run --starter person`), each placed by its `at=`. A run line
#                  older than `starter=` names no starter, and its run is counted as it was before the field: by its
#                  `proved: kind=regression` line under `## SDLC State` past the first (lib/proof.sh `proof_fields`),
#                  unless that proof cites a log whose run line names a starter, which the run lines count.
#   adoptions      the log's `run/v1|ev=hand|what=adopt|…`, one per agent `adopt` took over, placed by its `at=`.
#                  A verb act: never counted as by-hand.
#   fixed          the plan's `moved: <record>#<n> to=fixed row=<T> …` line under `## SDLC State` (`finding-move …
#                  fixed`, wave-36 T8), one per line (wave-36 T14; AC-7.6). A verb act: never counted as by-hand.
#                  A move is placed by its time against the landing of the row it names, the row's first `published`
#                  event: typed at or before that landing it is the landing's own business and outside the count,
#                  typed after it a hand marked the fix, inside. A move naming a row with no landing is unplaced.
#                  A move the landing itself wrote (`by=landing`, lib/line.sh `line_settle`) is its settlement, never a hand.
#   needs-you      the log's `run/v1|ev=hand|what=refusal|needs=person|…`, a refusal that named a person as its exit, from
#                  the one line refuse() wrote, placed by its `at=`. A refusal the person had to answer is a hand-hold; a refusal
#                  that named another exit (`needs=` anything else) is the machine's own and counts nothing. It is printed last.
#
# THE WINDOW. `--since <ISO>` and `--until <ISO>` count a hand-hold only when its own line's time is after the start
# and at or before the end; either end may be absent, and absent is open. Each source is placed by the time its writer
# put on it: the landing record's and the log's `at=`, an older fill ledger's `at=`, the ISO on a `waived:` line, a
# `moved:` or regression proof line's `at=`, and the matrix waiver's time. An end written to the minute (`<date>T<hh>:<mm>Z`, the shape close-out writes `delivered:` in) reaches through
# that minute's last second, so an act in the minute an end names is inside it. A waiver of the date form is placed
# when its whole day falls on one side of each end. A line that cannot be
# placed (a line that carries no time, a date form a window end falls inside, a move naming a row with no landing) is
# not counted, and with either end set the line ends ` · unplaced=<n>`, so a windowed count never hides what it left
# out. With no end set every line counts and the line keeps its open shape, so a run with no window reads as it always has.
#
# READ-ONLY and FAIL-SOFT: an absent source counts zero. It decides nothing; nothing reads it but close-out's card and
# continuation, the release approval page and the goal that names landing-report (and a person).
_HH_PLACE_AWK='
  function hh_iso(t) { return t ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9](:[0-9][0-9])?Z$/ }
  function hh_day(t) { return t ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ }
  function hh_norm(t) { return (hh_iso(t) && length(t) == 17) ? substr(t, 1, 16) ":00Z" : t }
  # 1 inside the window, 0 outside it, -1 not placeable; HH_S and HH_U are the ends, empty when open
  function hh_place(t,   a, b) {
    if (HH_S == "" && HH_U == "") return 1
    if (hh_iso(t)) { t = hh_norm(t); return ((HH_S == "" || t > HH_S) && (HH_U == "" || t <= HH_U)) ? 1 : 0 }
    if (hh_day(t)) {
      a = t "T00:00:00Z"; b = t "T23:59:59Z"
      if ((HH_S != "" && b <= HH_S) || (HH_U != "" && a > HH_U)) return 0
      return ((HH_S == "" || a > HH_S) && (HH_U == "" || b <= HH_U)) ? 1 : -1
    }
    return -1
  }
  function hh_take(t,   p) { p = hh_place(t); if (p < 0) HH_UNPLACED++; return p > 0 }
  # a line placed against a landing l as well: inside only when inside the window and after l; with no landing to
  # place it against it cannot be placed. With the window open every line counts, as hh_place says.
  function hh_after(t, l,   p) {
    p = hh_place(t)
    if ((HH_S == "" && HH_U == "") || p <= 0) return p
    if (!hh_iso(l)) return -1
    return (hh_norm(t) > hh_norm(l)) ? 1 : 0
  }
  function hh_take_after(t, l,   p) { p = hh_after(t, l); if (p < 0) HH_UNPLACED++; return p > 0 }
  BEGIN { HH_S = hh_norm(HH_S); HH_U = (hh_iso(HH_U) && length(HH_U) == 17) ? substr(HH_U, 1, 16) ":59Z" : hh_norm(HH_U) }
'
hand_holds_report() {  # <landing record> <project root> <plan> [--since <ISO>] [--until <ISO>] -> the one hand-holds line; rc 0, 2 unread
  local plan="$3" hands="" lines="" hand=0 stp=0 dec=0 lif=0 amd=0 hld=0 ext=0 wv=0 fl=0 ado=0 fix=0
  local ney=0 since="" until="" u1=0
  shift 3
  while [ $# -ge 2 ]; do
    case "$1" in --since) since="$2" ;; --until) until="$2" ;; esac
    shift 2
  done
  if [ -f "$plan" ] && [ ! -L "$plan" ] && _lr_reader; then
    hands="$(_proof_ask "$plan" reader_q_hands "$plan" 2>/dev/null)" && lines="$(_lr_events "$plan")" || return 2
    read -r hand stp ney fl wv fix dec lif amd hld ext ado u1 <<< "$( { printf '%s\n\034\n' "$hands"; printf '%s\n' "$lines"; } \
      | awk -F'|' -v HH_S="$since" -v HH_U="$until" "$_READER_AWK$_HH_PLACE_AWK"'
      $0 == "\034" { part = 1; next }
      # the hands answer: a landing by hand, and each hand event by what its line was
      !part { e = ev(); w = line_kv("what"); t = line_kv("at")
        if (e == "published" && line_kv("kind") == "hand" && hh_take(t)) n++
        else if (e != "hand") next
        else if (w == "stop-run" && hh_take(t)) s++
        else if (w == "amend" && hh_take(t)) am++
        else if (w == "hold" && hh_take(t)) ho++
        else if (w == "extend" && hh_take(t)) ex++
        else if (w == "adopt" && hh_take(t)) ad++
        # a refusal that named a person as its exit is one the person had to answer
        else if (w == "refusal" && line_kv("needs") == "person" && hh_take(t)) y++
        next }
      { e = ev() }
      # the first landing of each row the line recorded: what a move to fixed is placed against
      e == "published" && line_kv("kind") != "" && !(line_kv("row") in LAND) { LAND[line_kv("row")] = line_kv("at") }
      # a whole run past the first is a hand-hold only when a person started it; a proof of one whose log a run line
      # names a starter for is counted by that run line
      e == "run" && line_kv("starter") != "" && line_kv("log") != "" { started[line_kv("log")] = 1 }
      e == "run" && (line_kv("kind") == "regression" || index(line_kv("log"), "regression-run-")) {
        if (++r > 1 && line_kv("starter") == "person" && hh_take(line_kv("at"))) f++
      }
      e == "proof" && line_kv("kind") == "regression" { pr[++np] = line_kv("evidence"); pa[np] = line_kv("at") }
      # a waiver is the event the waive verb writes, of a question or of a criterion
      e == "waiver" && (line_kv("question") != "" || line_kv("ac") != "") && hh_take(line_kv("at")) { v++ }
      e == "finding" && line_kv("to") == "fixed" && line_kv("by") != "landing" { fr[++nf] = line_kv("row"); fa[nf] = line_kv("at") }
      e == "stop" && line_kv("state") == "decline" && hh_take(line_kv("at")) { d++ }
      e == "stop" && line_kv("state") == "lift" && hh_take(line_kv("at")) { l++ }
      END {
        # the first regression proof is the floor itself; each one past it whose run names no starter is a hand-hold
        for (i = 2; i <= np; i++) { m = split(pr[i], ee, ","); st = 0; for (j = 1; j <= m; j++) if (ee[j] in started) st = 1; if (!st && hh_take(pa[i])) f++ }
        for (i = 1; i <= nf; i++) if (hh_take_after(fa[i], LAND[fr[i]])) x++
        print n + 0, s + 0, y + 0, f + 0, v + 0, x + 0, d + 0, l + 0, am + 0, ho + 0, ex + 0, ad + 0, HH_UNPLACED + 0 }')"
  fi
  printf 'hand-holds: total=%d · by-hand=%d · stop-runs=%d · declines=%d · lifts=%d · amends=%d · holds=%d · extensions=%d · waivers=%d · second-regressions=%d · adoptions=%d · fixed=%d · needs-you=%d' \
    $(( hand + stp + dec + lif + amd + hld + ext + wv + fl + ado + fix + ney )) "$hand" "$stp" "$dec" "$lif" "$amd" "$hld" "$ext" "$wv" "$fl" "$ado" "$fix" "$ney"
  if [ -n "$since" ] || [ -n "$until" ]; then printf ' · unplaced=%d' "${u1:-0}"; fi
  printf '\n'
  return 0
}

# THE WINDOW'S ENDS, FROM RECORDS. The measure runs from the last build landing to delivery: the start is the newest
# landing the reader holds (its `landed` answer) of a row whose kind is build in the plan's table, the end the plan's
# Step-9 `delivered:` time once the run reads closed (sitrep.sh `sitrep_delivered_at`), else now. A release approval
# page ends nothing: what is done after the card, close-out's own acts among them, is inside the window. An end of whole minutes is printed as the
# minute, the shape close-out writes, so the window reaches through it (_HH_PLACE_AWK).
# hand_holds_window <landing record> <project root> <plan> -> `<since|-><TAB><row|-><TAB><until|-><TAB><delivered|now>`
hand_holds_window() {
  # its own reads split on blanks, whatever IFS the caller set around the substitution it is called in
  local rec="$1" root="$2" plan="$3" builds s="-" row="-" u="-" st=now e l IFS=$' \t\n'
  builds="$(units_rows "$plan" 2>/dev/null | awk -F'\t' '$3 == "build" { printf "%s ", $1 }')"
  if [ -n "$builds" ] && [ -f "$plan" ] && _lr_reader; then
    l="$(_proof_ask "$plan" reader_q_landed "$plan" 2>/dev/null)" || return 2
    read -r s row <<< "$(printf '%s\n' "$l" | awk -F'|' -v B=" $builds" "$_READER_AWK$_HH_PLACE_AWK"'
      index(B, " " line_kv("row") " ") { a = hh_norm(line_kv("at")); if (hh_iso(a) && a > m) { m = a; r = line_kv("row") } }
      END { if (m != "") print m, r; else print "-", "-" }')"
  fi
  if declare -F sitrep_delivered_at >/dev/null 2>&1 && declare -F epoch_iso >/dev/null 2>&1; then
    e="$(sitrep_delivered_at "$plan" 2>/dev/null)" || return 2
    if [ -n "$e" ] && u="$(epoch_iso "$e")" && [ -n "$u" ]; then
      st=delivered
      case "$u" in *:00Z) u="${u%:00Z}Z" ;; esac
    else u="-"; fi
  fi
  printf '%s\t%s\t%s\t%s\n' "${s:--}" "${row:--}" "${u:--}" "$st"
}

# hand_holds_verb <landing record> <project root> <plan> <since> <until> -> `landing-report --hand-holds`'s two lines:
# the counts over the window, then the ends that bound it. With neither end named the ends are read from records
# (hand_holds_window); before the run is delivered the window runs to now and says so, printing no end it has not
# read from a record.
hand_holds_verb() {
  local rec="$1" root="$2" plan="$3" since="$4" until="$5" e s row u st sw uw no="hand-holds: not read — the run's facts could not be read"
  if [ -n "$since" ] || [ -n "$until" ]; then
    hand_holds_report "$rec" "$root" "$plan" ${since:+--since "$since"} ${until:+--until "$until"} || { printf '%s\n' "$no"; return 2; }
    printf 'hand-holds window: since %s · until %s\n' "${since:-the first line}" "${until:-now}"
    return 0
  fi
  e="$(hand_holds_window "$rec" "$root" "$plan")" || { printf '%s\n' "$no"; return 2; }
  IFS=$'\t' read -r s row u st <<< "$e"
  [ "$s" != - ] || s=""
  [ "$u" != - ] || u=""
  if [ -n "$s" ] || [ -n "$u" ]; then hand_holds_report "$rec" "$root" "$plan" ${s:+--since "$s"} ${u:+--until "$u"}
  else hand_holds_report "$rec" "$root" "$plan"; fi || { printf '%s\n' "$no"; return 2; }
  if [ -n "$s" ]; then sw="since $s (the last build landing, $row)"; else sw="since the first line (no build row has landed)"; fi
  if [ "$st" = delivered ]; then uw="until $u (delivered:)"; else uw="until now: the plan names no delivered: time"; fi
  printf 'hand-holds window: %s · %s\n' "$sw" "$uw"
  return 0
}

# record_row_land <row> -> the record row of the run's plan ($PV_PLAN, $PV_REPO) landed, in a subshell of the tick's:
# every check first (`deliver_check`, the registration a row's kind owes among them), then the one `published` event,
# then the landing's writes (lib/line.sh `line_landing_writes`). Nothing refuses after the event. Exits 0 landed or
# already landed, 2 refused with the reason on stderr, 1 not written.
record_row_land() {
  PV_ID="$1"; RL_WALK=""; ROW_WRITER=""
  plan_verb_id_ok "$PV_ID" || { die "REFUSED — '$(clean "$PV_ID")' is not one row id."; exit 2; }
  deliver_check
  # A row nobody launched is the orchestrator's own, and its landing says so.
  case "$ROW_WRITER" in ''|-|—) ROW_WRITER=orchestrator ;; esac
  line_published_event "$PV_PLAN" "row=$PV_ID" "commit=$RL_COMMIT" kind=record "by=$ROW_WRITER" "why=$RL_ARTIFACT" >/dev/null || {
    die "REFUSED — the run's log cannot take the landing of $PV_ID; nothing is landed."; exit 1; }
  line_landing_writes "$PV_PLAN" "$PV_ID" "$RL_COMMIT" "$RL_AT" \
    || say "UNSETTLED $PV_ID — landed at $RL_COMMIT; the findings it settles are not moved or their asks not closed"
  say "landed $PV_ID — its record $RL_ARTIFACT at the working head $RL_COMMIT"
  exit 0
}

# ---------------------------------------------------------------- the release entry's reviews, before the pull request
#
# THE INTEGRATE ROW RENDERS THE ENTRY'S REVIEWS PART BEFORE IT OPENS ITS PULL REQUEST. `reviews-part <row>` renders the
# release entry's `### The reviews` part from the plan (lib/line.sh `line_reviews_state`, close-out's renderer too) and
# commits it under the line's author where `part_target` says, the working branch when run from its checkout, so the
# branch the pull request is opened from carries it, and the merge brings it to the integration branch. Its last lines are the release reply's waivers, so in the release
# order it refuses until `approved: release` is written: a part rendered before the reply would miss them. The judge
# holds the commit covered by the release check and the approval at its parent while it is the fresh render (lib/proof.sh
# `proof_part_base`), so nothing is approved or checked again. The landing record gains
# `ev=integrate|row=<row>|part=reviews|commit=<c>|branch=<b>|tree=<t>`, so no branch holds a commit the record does not
# name. Nothing to render, or the part already listed: nothing is made, exit 0. The branch moves on this machine alone;
# it leaves it by the person's push. The record row's landing refuses the integrate row while the part would still render.
REVIEWS_PART_AUTHOR="bionic line"; REVIEWS_PART_EMAIL="line@bionic.invalid"

# THE PARTS RENDER IN THE CHECKOUT THE VERB RUNS FROM. A row's tree renders the part its own landing carries, so the
# working branch takes it by that landing and never twice. `part_target <plan> <root>` sets PT_TREE (the checkout that
# takes the commit, absolute), PT_BRANCH and PT_HEAD (the commit read and rendered on). The checkout's own top level,
# a linked worktree included, on a branch of its own takes the part on that branch at its HEAD; the plan's working
# branch moves only when that checkout holds it. A checkout on no branch, or on a protected one, can take no commit of
# its own, so the part goes to the working branch as it always did: in the checkout holding it, else by the ref alone
# in <root>. PT_HEAD empty, PT_SAID saying why, when there is no commit to read.
PT_TREE=""; PT_BRANCH=""; PT_HEAD=""; PT_SAID=""
part_target() {
  local plan="$1" root="$2" top br wb co
  PT_TREE=""; PT_BRANCH=""; PT_HEAD=""; PT_SAID=""
  wb="$(plan_working_branch "$plan")"
  top="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" && top="$(cd "$top" 2>/dev/null && pwd -P)" || top=""
  br=""; [ -z "$top" ] || br="$(git -C "$top" symbolic-ref --short -q HEAD 2>/dev/null)" || br=""
  if [ -n "$br" ] && [ "$br" != "$wb" ] && { _wt_branch_protected "$br"; [ $? -eq 1 ]; }; then
    PT_TREE="$top"; PT_BRANCH="$br"
    PT_HEAD="$(git -C "$top" rev-parse --verify -q HEAD 2>/dev/null)" || PT_HEAD=""
    [ -n "$PT_HEAD" ] || PT_SAID="$br in $top names no commit"
    return 0
  fi
  PT_BRANCH="$wb"
  PT_HEAD="$(proof_branch_head "$plan" "$root")" || PT_HEAD=""
  [ -n "$PT_HEAD" ] || PT_SAID="the plan's working-branch ${wb:-(none named)} names no commit in $root"
  co="$(worktree_checkout_of "$root" "$wb")" && PT_TREE="$co" || PT_TREE="$root"
}
# part_land <kind> <part> <message> <reflog words> <tmp dir holding new> -> the rendered file committed on PT_BRANCH at
# PT_HEAD, the branch moved in the checkout holding it, and the run's log naming the commit, branch and tree in a
# `published` line with the part and the row that published it as by=. It carries no row=: a part is no row's landing.
# <tmp dir> is removed. Every refusal exits, nothing moved before the move refuses.
part_land() {
  local why
  why="$(line_reviews_checkout "$PT_TREE" "$PT_BRANCH")"
  if [ -n "$why" ]; then
    rm -rf "$5"; die "REFUSED — $why; nothing was rendered."; exit 2
  fi
  if ! line_reviews_commit "$PT_TREE" "$PT_HEAD" "$5/new" "$REVIEWS_PART_AUTHOR" "$REVIEWS_PART_EMAIL" "$3"; then
    rm -rf "$5"; die "REFUSED — on $PT_BRANCH: $LINE_RV_SAID; nothing was rendered."; exit 2
  fi
  rm -rf "$5"
  if ! line_reviews_move "$PT_TREE" "$PT_BRANCH" "$LINE_RV_COMMIT" "$PT_HEAD" "$4"; then
    die "REFUSED — $PT_BRANCH could not be moved from ${PT_HEAD:0:12} to ${LINE_RV_COMMIT:0:12}; nothing was published."
    exit 2
  fi
  if ! line_published_event "$PV_PLAN" "part=$2" "commit=$LINE_RV_COMMIT" "branch=$PT_BRANCH" "tree=$PT_TREE" "by=$PV_ID"; then
    die "REFUSED — $PT_BRANCH moved to ${LINE_RV_COMMIT:0:12}, and the run's log could not be written: append ev=published|part=$2|commit=$LINE_RV_COMMIT|branch=$PT_BRANCH|tree=$PT_TREE|by=$PV_ID to $(line_log "$PV_PLAN" 2>/dev/null || printf 'the log')."
    exit 1
  fi
}
poker_verb_reviews_part() {
  local row kind status head ah tmp call="bash $HOOK_DIR/session-poker.sh"
  if ! plan_verb_id_ok "$PV_ID"; then
    die "REFUSED — '$(clean "$PV_ID")' is not one row id; nothing was rendered."
    exit 1
  fi
  plan_verb_open reviews-part
  if ! { declare -F line_reviews_state >/dev/null 2>&1 || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; } \
     || ! declare -F line_reviews_state >/dev/null 2>&1 || ! declare -F proof_branch_head >/dev/null 2>&1; then
    die "REFUSED — the renderer (lib/line.sh) or the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; nothing was rendered."
    exit 2
  fi
  row="$(units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' -v id="$PV_ID" '$1 == id { print; exit }')"
  if [ -z "$row" ]; then
    die "REFUSED — the ## Tasks table of $PV_PLAN carries no row $PV_ID; nothing was rendered."
    exit 2
  fi
  kind="$(units_field "$row" kind)"; status="$(units_field "$row" status)"
  if [ "$kind" != integrate ]; then
    die "REFUSED — $PV_ID is a $(clean "$kind") row, and the integrate row renders the entry's reviews before its pull request; nothing was rendered."
    exit 2
  fi
  case "$status" in
    pending|active) : ;;
    *) die "REFUSED — $PV_ID reads $(clean "$status"), and the part is rendered before the integrate row lands; nothing was rendered."; exit 2 ;;
  esac
  if units_order "$PV_PLAN" >/dev/null 2>&1; then
    ah="$(proof_approved_head "$PV_PLAN" release 2>/dev/null)" || ah=""
    if [ -z "$ah" ]; then
      die "REFUSED — the plan is in the release order and no approved: release line names a head, so the release reply's waivers may still come and the part would miss them; render it after the reply: $call reviews-part $PV_ID. Nothing was rendered."
      exit 2
    fi
  fi
  part_target "$PV_PLAN" "$PV_REPO"; head="$PT_HEAD"
  if [ -z "$head" ]; then
    die "REFUSED — $PT_SAID; nothing was rendered."
    exit 2
  fi
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/reviews-part.XXXXXX")" || { die "REFUSED — no temporary directory; nothing was rendered."; exit 2; }
  if ! line_reviews_state "$PV_PLAN" "$PT_TREE" "$head" "$PT_BRANCH" "$tmp/new"; then
    rm -rf "$tmp"; die "REFUSED — the part cannot be rendered: $LINE_RV_SAID. Nothing was rendered."; exit 2
  fi
  case "$LINE_RV_STATE" in
    none) rm -rf "$tmp"; say "reviews-part — nothing to render: $LINE_RV_SAID."; exit 0 ;;
    listed) rm -rf "$tmp"
      say "reviews-part — the $LINE_RV_VER entry's ### The reviews on $PT_BRANCH already lists the plan's $LINE_RV_N review and waiver lines; nothing was made."
      exit 0 ;;
  esac
  part_land integrate reviews "line: the $LINE_RV_VER entry's reviews, rendered from the plan before the pull request" \
    "reviews-part: $PV_ID" "$tmp"
  say "reviews-part — $LINE_RV_N review and waiver lines rendered under ### The reviews of the $LINE_RV_VER entry, committed ${LINE_RV_COMMIT:0:12} on $PT_BRANCH in $PT_TREE; open the pull request from the working branch once it carries it."
  exit 0
}

# ---------------------------------------------------------------- the release entry's Known limits, from the deferrals
#
# THE ENTRY'S KNOWN LIMITS ARE THE RUN'S DEFERRALS. `known-limits-part <row>` renders the release entry's
# `### Known limits` from the run's deferrals: one bullet per open deferral (lib/proof.sh `proof_findings_owed` rating it
# `defer`), its stated sentence (lib/proof.sh `proof_finding_stated`, unescaped), in the order the run deferred them. That is the
# release check's own reading of the deferrals (tests/lib/release-check.sh `lim_check`), so every sentence the check
# looks for stands in the part it scans. The part replaces the entry's own (its heading to the next heading; a doubled
# heading is one part), else goes in before `### The landing numbers`, else at the entry's end (lib/line.sh
# `line_entry_part`, the one rule that places a part of an entry), and nothing else in
# the file changes. It is committed under the line's author through the reviews part's commit path (`part_target`,
# `part_land`): in a row's tree on its branch, which its landing carries to the working branch the check judges, or on
# the working branch from its checkout, and the landing record gains
# `ev=<row kind>|row=<row>|part=known-limits|commit=<c>|branch=<b>|tree=<t>`.
# The rows that render it are the entry's own, the doc row that writes it and the integrate row that carries it, while
# pending or active. A deferral with no sentence is refused, naming the verb that states it: the check refuses a part
# without it. Nothing owed, or the part already as rendered: nothing is made, exit 0. The branch moves on this machine
# alone; it leaves it by the person's push. Nothing records a stated assumption, so the deferrals are the whole part.
KL_UNSTATED=""
known_limits_part() {  # <plan> -> the part, heading to its closing blank line; nothing when no deferral is owed.
  # rc 1, KL_UNSTATED naming it, at the first open deferral that states no sentence; rc 2 when the run's facts cannot
  # be read.
  local plan="$1" id s r p t st n=0 body="" owed
  KL_UNSTATED=""
  owed="$(proof_findings_owed "$plan" 2>/dev/null)" || return 2
  while read -r id s r p t; do
    [ "$p" = defer ] || continue
    st="$(proof_finding_stated "$plan" "$id")"; [ "$?" -ne 2 ] || return 2
    if [ -z "$st" ] || [ "$st" = - ]; then KL_UNSTATED="$id"; return 1; fi
    body="${body}- ${st}"$'\n'; n=$((n + 1))
  done <<KL_OWED
$owed
KL_OWED
  [ "$n" -gt 0 ] || return 0
  printf '### Known limits\n\n%s\n\n%s\n' \
    "Rendered from the plan's deferred findings, each its stated sentence, in the order they were registered." "$body"
}
poker_verb_known_limits_part() {
  local row kind status head ver tmp n call="bash $HOOK_DIR/session-poker.sh"
  if ! plan_verb_id_ok "$PV_ID"; then
    die "REFUSED — '$(clean "$PV_ID")' is not one row id; nothing was rendered."
    exit 1
  fi
  plan_verb_open known-limits-part
  if ! { declare -F line_reviews_commit >/dev/null 2>&1 || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; } \
     || ! declare -F line_reviews_commit >/dev/null 2>&1 || ! _line_load_proof || ! declare -F proof_findings_owed >/dev/null 2>&1; then
    die "REFUSED — the renderer (lib/line.sh) or the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; nothing was rendered."
    exit 2
  fi
  row="$(units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' -v id="$PV_ID" '$1 == id { print; exit }')"
  if [ -z "$row" ]; then
    die "REFUSED — the ## Tasks table of $PV_PLAN carries no row $PV_ID; nothing was rendered."
    exit 2
  fi
  kind="$(units_field "$row" kind)"; status="$(units_field "$row" status)"
  case "$kind" in
    doc|integrate) : ;;
    *) die "REFUSED — $PV_ID is a $(clean "$kind") row, and the entry's Known limits are rendered by the row that writes the entry or carries it (doc or integrate); nothing was rendered."
       exit 2 ;;
  esac
  case "$status" in
    pending|active) : ;;
    *) die "REFUSED — $PV_ID reads $(clean "$status"), and the part is rendered before its row lands; nothing was rendered."; exit 2 ;;
  esac
  ver="$(plan_frontmatter_get "$PV_PLAN" release)"
  if [ -z "$ver" ]; then
    say "known-limits-part — nothing to render: the plan names no release:."
    exit 0
  fi
  part_target "$PV_PLAN" "$PV_REPO"; head="$PT_HEAD"
  if [ -z "$head" ]; then
    die "REFUSED — $PT_SAID; nothing was rendered."
    exit 2
  fi
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/known-limits-part.XXXXXX")" || { die "REFUSED — no temporary directory; nothing was rendered."; exit 2; }
  known_limits_part "$PV_PLAN" > "$tmp/part"; n=$?
  if [ "$n" -eq 2 ]; then
    rm -rf "$tmp"
    die "REFUSED — the run's facts could not be read, so its deferrals are not known; nothing was rendered. Run again: $call known-limits-part $PV_ID"
    exit 2
  elif [ "$n" -ne 0 ]; then
    rm -rf "$tmp"
    die "REFUSED — $(clean "$KL_UNSTATED") is deferred with no stated sentence, and the release check refuses a deferral with none: state it on the person's words, bash ${HOOK_DIR}/session-poker.sh finding-move $(clean "$KL_UNSTATED") defer '<their words>' '<why>' '<sentence>', then render again. Nothing was rendered."
    exit 2
  fi
  n="$(/usr/bin/grep -c '^- ' "$tmp/part" | tr -d ' ')"
  if [ "${n:-0}" -eq 0 ]; then
    rm -rf "$tmp"; say "known-limits-part — nothing to render: the plan owes no deferral."
    exit 0
  fi
  if ! git -C "$PT_TREE" show "${head}:CHANGELOG.md" > "$tmp/old" 2>/dev/null || ! /usr/bin/grep -q "^## ${ver} " "$tmp/old"; then
    rm -rf "$tmp"
    die "REFUSED — CHANGELOG.md on $PT_BRANCH holds no ## $ver entry for the plan's $n deferred sentences; write the entry, then render. Nothing was rendered."
    exit 2
  fi
  line_entry_part "$tmp/old" "$ver" "$tmp/part" 'Known limits' 'The landing numbers' > "$tmp/new"
  if cmp -s "$tmp/old" "$tmp/new"; then
    rm -rf "$tmp"
    say "known-limits-part — the $ver entry's ### Known limits on $PT_BRANCH already lists the plan's $n deferred sentences; nothing was made."
    exit 0
  fi
  part_land "$kind" known-limits "line: the $ver entry's Known limits, rendered from the plan's deferrals" \
    "known-limits-part: $PV_ID" "$tmp"
  say "known-limits-part — $n deferred sentences rendered under ### Known limits of the $ver entry, committed ${LINE_RV_COMMIT:0:12} on $PT_BRANCH in $PT_TREE."
  exit 0
}

# ---------------------------------------------------------------- the release note
#
# A RELEASE ENTRY'S NUMBERS ARE RENDERED, NEVER TYPED. `release-note [--at <commit>] [--on <instant>] [<plan>]` prints
# the entry's `### The landing numbers` block as CHANGELOG.md carries it: one line naming the head and the instant,
# then `landing_report`'s line and rows in a fence. The report is folded over the run's lines written at or before
# the instant (a line's `at=`; a line with none is kept), so a block rendered for a head and an instant is the same
# block whenever it is rendered for them again, and nothing recorded later is in it. The head is the plan's working
# branch's (lib/proof.sh `proof_branch_head`), else the checkout's, or the commit --at names; the instant is now, or
# --on's. The release check renders the block again for the head and instant an entry names and holds the entry to it.
  poker_verb_release_note() {
    local at="" on="" arg="" plan root head body
    local use="release-note takes --at <commit> and --on <YYYY-MM-DDTHH:MM:SSZ> at most once each, and at most one plan."
    while [ $# -gt 0 ]; do
      case "$1" in
        --at) { [ $# -ge 2 ] && [ -z "$at" ]; } || usage "$use"; at="$2"; shift ;;
        --on) { [ $# -ge 2 ] && [ -z "$on" ]; } || usage "$use"; on="$2"; shift ;;
        -*) usage "$use" ;;
        *) [ -z "$arg" ] || usage "$use"; arg="$1" ;;
      esac
      shift
    done
    case "${on:-2000-01-01T00:00:00Z}" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
      *) usage "$use" ;;
    esac
    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    if [ -n "$arg" ]; then
      case "$arg" in
        /*) plan="$arg" ;;
        *)  plan="$REPO_REAL/$arg"
            [ -f "$plan" ] || plan="$(docs_root "$REPO_REAL")/$arg" ;;
      esac
      if [ ! -f "$plan" ] || [ -L "$plan" ]; then
        die "REFUSED — no plan file at $arg; name the plan whose landings the release describes."
        exit 2
      fi
    else
      SESSION_ID="$(session_id)" || SESSION_ID=""
      if [ -z "$SESSION_ID" ]; then
        die "REFUSED — no session key, and no plan named; a release note without an operand is for THIS session's run."
        exit 3
      fi
      resolve_run "$REPO_REAL" "$SESSION_ID"
      plan="$POKER_RUN_PLAN"
      if [ -z "$plan" ] || [ ! -f "$plan" ]; then
        die "REFUSED — this session has no run to render; bind its plan first, or name it: release-note <plan>."
        exit 2
      fi
    fi
    root="$(cd "$(project_root "${plan%/*}")" 2>/dev/null && pwd -P)"
    [ -n "$root" ] || root="$REPO_REAL"
    if [ -n "$at" ]; then head="$(git -C "$REPO_REAL" rev-parse --verify -q "$at^{commit}" 2>/dev/null)"
    else head="$(proof_branch_head "$plan" "$root")" || head="$(git -C "$REPO_REAL" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)"
    fi
    if [ -z "$head" ]; then
      die "REFUSED — ${at:-the working head} names no commit in $REPO_REAL; name the head the entry is written at."
      exit 2
    fi
    [ -n "$on" ] || on="$(iso_now)"
    body="$(landing_report "$plan" "$root" yes "$on")"
    printf '### The landing numbers\n\n`landing-report --rows` at %s on %s:\n\n```\n%s\n```\n' "$head" "$on" "$body"
    exit 0
  }
