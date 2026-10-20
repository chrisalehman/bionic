# shellcheck shell=bash
# hooks/poker/line.sh — the landing line: a row lands itself, its evidence, the run's numbers and hand-holds
# (row-landed, deliver).
#
# A part of hooks/session-poker.sh, which sets every global and loads this file before any verb runs. A part
# defines functions only, and is never run by itself.

# landing_evidence <plan in> <plan out> <row> <commit> <landing record> <docs root> <plan slug> -> prints the number of
# cells written; <plan out> holds the plan with them (and is left alone when none). rc 1 when the pass cannot run.
landing_evidence() {
  local in="$1" out="$2" row="$3" commit="$4" rec="$5" droot="$6" slug="$7" logs n side="$2.count"
  { [ -n "${_LINE_FIELDS_AWK:-}" ] || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; }
  logs="$( [ -f "$rec" ] && awk -F'|' -v row="$row" -v c="$commit" -v root="$droot/" "${_LINE_FIELDS_AWK:-}"'
    { e = line_ev() }
    e == "verdict" && line_kv("result") == "green" {
      s = line_kv("suite"); l = line_kv("log")
      gl[line_kv("commit") SUBSEP s SUBSEP line_kv("reads")] = l   # any row: a reuse line after it may name it as its proof
      if (line_kv("row") == row && line_kv("commit") == c && s != "" && index(l, root) == 1) last[s] = substr(l, length(root) + 1)
    }
    e == "reused" && line_kv("row") == row && line_kv("commit") == c {
      s = line_kv("suite"); k = line_kv("from") SUBSEP s SUBSEP line_kv("reads")
      if (s != "" && line_kv("reads") != "" && (k in gl) && index(gl[k], root) == 1) last[s] = substr(gl[k], length(root) + 1)
    }
    END { for (s in last) printf "%s\t%s\n", s, last[s] }' "$rec" 2>/dev/null )"
  if [ -z "$logs" ]; then printf '0'; return 0; fi
  LE_TASKS="$(serves_tasks "$in")" LE_ROW="$row" LE_LOGS="$logs" LE_SLUG="$slug" LE_COUNT="$side" \
    awk "$SERVES_AWK$LE_AWK" "$in" > "$out.le" 2>/dev/null || { rm -f "$out.le" "$side"; return 1; }
  n="$(cat "$side" 2>/dev/null)"; rm -f "$side"
  case "$n" in ''|*[!0-9]*) rm -f "$out.le"; return 1 ;; esac
  if [ "$n" -gt 0 ]; then mv -f "$out.le" "$out"; else rm -f "$out.le"; fi
  printf '%s' "$n"
}
# ---------------------------------------------------------------- a record row lands itself
#
# THE RECORD ROW'S OWN LANDING (wave-33 T6; REQ-3 AC-3.1, AC-3.2; D5). A test, verify or review row
# writes a record and no code, so it has no tree, no `ready` and no `published` event; wave-32 landed
# eight such rows by `row-landed --by-hand`. `deliver <row>` is its agent's last act, and the tick's
# backstop when the agent ended without it. It checks what the row owes, then lands it through the
# one landing writer, `row-landed`, in the same transaction, at the working head (the head of the
# checkout holding the plan's `working-branch:`), with the artifact written into the ledger line.
#
# THE ROW'S WRITER (wave-34 T4; burns debt row-writer-name): `ready`'s answer, lib/line.sh
# `line_row_writer`, loaded here the first time it is asked, so `deliver` and the tick's backstop hold a
# row to the writer `ready` would. Sets ROW_WRITER (empty when the row names no one); 1 when the library
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
#   - it is not a live review row (`units_live_rows`): `proof-add` returns that row to `pending` at
#     each reading and the next landing makes it ready again, so landing it would end its passes;
#   - its artifact: the ledger line's `artifact` cell, else the one record under `<docs-root>/record/`
#     its Files name (a `.progress.md` and `assumptions.md` are bookkeeping, not the artifact). The
#     file exists, is no symbolic link, and lies under the docs root's `record/`;
#   - a review row: a `proved: kind=review` line under `## SDLC State` names that record;
#   - the working head reads as a commit;
#   - no ruling for the row's writer is unread.
deliver_check() {
  local row kind files wt status art docs drel abs real rel e n=0 cands="" hasl=0 lverb=ledger-set call wb head sid roster rulings
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
    landed) say "deliver — $PV_ID is already landed; nothing was written."; exit 0 ;;
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
    die "REFUSED — $PV_ID is a live review row (it reads live:head): proof-add returns it to pending at each reading and the next landing makes it ready again, so deliver does not land it. The plan is unchanged."
    exit 2
  fi
  docs="$(docs_root "$PV_REPO")"; docs="$(cd "$docs" 2>/dev/null && pwd -P)"
  drel=""; case "$docs" in "$PV_REPO"/*) drel="${docs#"$PV_REPO"/}" ;; esac
  launch_sync_ledger "$PV_PLAN" >/dev/null && hasl=1
  art="$(awk -F'|' -v id="$PV_ID" '
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^##[ \t]/ { inl = ($0 ~ /^##[ \t]+Dispatch ledger[ \t]*$/); rows = 0; next }
    !inl || $0 !~ /^[ \t]*\|/ { next }
    { rows++ }
    rows == 1 { ac = 0; for (k = 2; k < NF; k++) { h = $k; gsub(/^[ \t]+|[ \t]+$/, "", h); if (h == "artifact") ac = k }; next }
    $0 ~ /^[ \t]*\|[ \t:|-]*$/ { next }
    { c = $2; gsub(/^[ \t]+|[ \t]+$/, "", c); if (c == id && ac) { v = $ac; gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit } }' "$PV_PLAN" 2>/dev/null)"
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
    [ "$hasl" = 1 ] && launch_sync_ledger "$PV_PLAN" | awk -F'\037' -v id="$PV_ID" '$1 == id { f = 1 } END { exit !f }' || lverb=ledger-add
    if [ "$n" -eq 0 ]; then
      die "REFUSED — $PV_ID names no artifact: its ledger line has no artifact cell and its Files name no record under record/; name it: $call $lverb $PV_ID artifact=<path>, then $call deliver $PV_ID. The plan is unchanged."
      exit 2
    fi
    if [ "$n" -gt 1 ]; then
      die "REFUSED — $PV_ID names no artifact in its ledger line and its Files name $n records ($(clean "$cands")); name the one it delivers: $call $lverb $PV_ID artifact=<path>, then $call deliver $PV_ID. The plan is unchanged."
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
    die "REFUSED — the artifact $(clean "$art") of $PV_ID is a symbolic link, and what it points at can change after the landing; copy the record to that path, then $call deliver $PV_ID. The plan is unchanged."
    exit 2
  fi
  if [ ! -f "$abs" ]; then
    die "REFUSED — the artifact of $PV_ID, $(clean "$art"), does not exist (read as $(clean "$abs")); write it, then run $call deliver $PV_ID. The plan is unchanged."
    exit 2
  fi
  real="$(cd "$(dirname "$abs")" 2>/dev/null && pwd -P)/$(basename "$abs")"
  case "$real" in
    "$docs"/record/*) rel="${real#"$docs"/}" ;;
    *)
      die "REFUSED — the artifact $(clean "$art") of $PV_ID is not under record/ of the docs root ($docs/record/), and a record row delivers a record; the plan is unchanged."
      exit 2 ;;
  esac
  if [ "$kind" = review ]; then
    if [ -z "$(awk -v rec="$rel" "$(proof_awk)"'
        /^[[:space:]]*```/ { fence = !fence; next }
        fence { next }
        /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
        insdlc && proof_fields($0) && PROOF_KIND == "review" && PROOF_EVIDENCE == rec { print "y"; exit }' "$PV_PLAN" 2>/dev/null)" ]; then
      die "REFUSED — $PV_ID is a review row and no proved: kind=review line names its record $rel; register the reading first: $call proof-add review $rel --question <q> --reader <name>, then $call deliver $PV_ID. The plan is unchanged."
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
    die "REFUSED — the plan's working-branch ${wb:-(none named)} names no commit in $PV_REPO, so there is no head to land $PV_ID at; name the branch under ## SDLC State (working-branch: <branch>), then $call deliver $PV_ID. The plan is unchanged."
    exit 2
  fi
  # AN UNREAD RULING HOLDS THE LANDING (wave-33 T34; Δ1, ADR-052), as at the commit wall and `ready`: a
  # record row's artifact is gitignored and never commits, so deliver is its only landing. The writer
  # is `ready`'s (`row_writer`). Each ruling of it not yet shown is printed and stamped shown
  # (lib/roster.sh `ruling_take_unread`), so the same call after this one lands: this is the writer's
  # own deliver. The tick's backstop never reaches this read with a ruling unread (it refuses first,
  # without stamping, wave-34 T4).
  sid="$(session_id)" || sid=""
  roster="$PV_REPO/.bionic/tmp/roster-${sid}.state"
  if ! row_writer "$roster" "$PV_PLAN" "$PV_ID" "$(units_field "$row" agent)"; then
    die "REFUSED — the row's writer cannot be read: lib/line.sh cannot be loaded from $BIONIC_LIB; the plan is unchanged."
    exit 2
  fi
  if [ -n "$sid" ] && declare -F ruling_take_unread >/dev/null 2>&1 \
     && rulings="$(ruling_take_unread "$roster" "$ROW_WRITER" deliver)" && [ -n "$rulings" ]; then
    die "REFUSED — an orchestrator ruling for $(clean "$ROW_WRITER") is unread ($(printf '%s\n' "$rulings" | sed -n 's/^bionic ruling \([^ ]*\) .*/\1/p' | paste -sd, - | sed 's/,/, /g')); read it below, act on it, then $call deliver $PV_ID. The plan is unchanged."
    printf '%s\n' "$rulings" >&2
    exit 2
  fi
  RL_COMMIT="$head"; RL_AT="$(iso_now)"; RL_ARTIFACT="$art"
}

# THE HAND LANDING'S SCAN (wave-39 T13; REQ-9 AC-9.1, AC-9.3; D14). `row-landed --by-hand` marks a landing no line
# made: wave 38 fast-forwarded fourteen rows by hand and marked each so, a route that ran no check, and the private
# name that reached history through it cost a rewrite of 99 commits (A-orch-71, A-orch-78; D32). With `release-check:`
# declared in `.bionic/config.yaml`, the mark is written only when the commit is held: by a passing `kind=check` proof
# at it or at a commit that holds it (lib/proof.sh `proof_check_passes`, the last check line at each head deciding
# it), else by the declared check itself, run as the release-check verb runs it (its words split on blanks, globbing
# off) over the release range, `release_base` to the commit, in the checkout of the plan's working branch (the
# project root when none holds it), with BIONIC_CHECK_BRANCH naming that branch for the rewrite a hit prints
# (tests/lib/name-scan.sh). A check that exits non-zero refuses: its output is printed, each hit with the commit and
# path that brought it and its fix, and the plan is unchanged. A commit the base already holds is in a release and
# is not scanned again. With no key nothing runs. The `line_publish` route ran the check over its own range before
# its fast-forward and then calls this verb, so a hand landing through `land --by-hand` meets it twice; the second
# run sees the whole release range, which the first did not. Exits on a refusal; returns when the mark may be written.
row_landed_scan() {
  local cmd wb co p out rc
  cmd="$(config_value "$PV_REPO" release-check "" 2>/dev/null)"
  [ -n "$cmd" ] || return 0
  if ! { declare -F proof_check_passes >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
     || ! declare -F proof_check_passes >/dev/null 2>&1; then
    die "REFUSED — row-landed --by-hand: the declared release-check cannot be judged, for the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
    exit 2
  fi
  wb="$(plan_working_branch "$PV_PLAN")"
  co=""; [ -z "$wb" ] || co="$(proof_checkout "$PV_REPO" "$wb")" || co=""
  [ -n "$co" ] || co="$PV_REPO"
  if ! git -C "$co" rev-parse --verify -q "$RL_COMMIT^{commit}" >/dev/null 2>&1; then
    die "REFUSED — row-landed --by-hand: $RL_COMMIT is no commit in $co, so the declared release-check has nothing to run over; the plan is unchanged."
    exit 1
  fi
  for p in $(proof_check_passes "$PV_PLAN" "$co"); do
    if git -C "$co" merge-base --is-ancestor "$RL_COMMIT" "$p" 2>/dev/null; then
      say "row-landed — release-check: ${RL_COMMIT:0:12} is held by the passing release check at ${p:0:12}; no scan was run."
      return 0
    fi
  done
  if ! release_base "$PV_PLAN" "$co" "$RL_COMMIT"; then
    die "REFUSED — row-landed --by-hand: the declared release-check ($(clean "$cmd")) has no range to run over: no tag reachable from the plan's integration-branch (${RB_IB:-none named}) is a proper ancestor of $RL_COMMIT and its base-sha (${RB_BS:-none}) is no commit here; name the last release as the plan's base-sha, or tag it. The plan is unchanged."
    exit 1
  fi
  if [ "$(git -C "$co" rev-list --count "$RB_BASE..$RL_COMMIT" 2>/dev/null)" = 0 ]; then
    say "row-landed — release-check: ${RL_COMMIT:0:12} is held by the release base ${RB_BASE:0:12} ($RB_FROM); no scan was run."
    return 0
  fi
  out="$(cd "$co" 2>/dev/null || exit 1
    set -f
    export BIONIC_CHECK_BASE="$RB_BASE" BIONIC_CHECK_HEAD="$RL_COMMIT" BIONIC_CHECK_TREE="$(pwd -P)" BIONIC_CHECK_BRANCH="$wb"
    # shellcheck disable=SC2086  # the configured command is meant to split on blanks
    exec $cmd </dev/null 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    [ -z "$out" ] || printf '%s\n' "$out"
    die "REFUSED — row-landed --by-hand: the declared release-check ($(clean "$cmd")) exited $rc over ${RB_BASE:0:12}..${RL_COMMIT:0:12} ($RB_FROM), and no passing kind=check proof stands at or past ${RL_COMMIT:0:12}. Its output is above: each hit, the commit and path that brought it, and its fix (a copy only history holds goes by the rewrite it prints). Take out what it names and mark the landing again, or run release-check to a pass at or past the commit; the plan is unchanged."
    exit 1
  fi
  say "row-landed — release-check: clean over ${RB_BASE:0:12}..${RL_COMMIT:0:12} ($RB_FROM)."
  return 0
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
# UNMEASURED (wave-28 T62). A record that holds `landed:` lines and no `line/v1` event (a run open across the
# upgrade) prints the one line `landings: unmeasured — the landing record holds no line/v1 events`, and no row.
#
# FAIL-SOFT. An absent or empty record is the line with zeros. A `line/v1` line this fold reads (`ready`,
# `verdict`, `returned`, `published`) that lacks a field it needs is skipped and counted, and the count is one line
# on stderr; an event of another kind, and every line that is not `line/v1`, is not this fold's. A
# request line the fold does not know (`peak=`, anything newer) is ignored. The gate's lock is not
# taken: this is a read, and a request the gate is writing reads as it stands.
landing_unmeasured() {  # <record> -> rc 0 when it holds `landed:` lines and no `line/v1` event
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  /usr/bin/grep -q '^landed:' "$1" 2>/dev/null || return 1
  ! /usr/bin/grep -q '^line/v1|' "$1" 2>/dev/null
}
landing_report() {  # <record> <project root> <rows yes|no> -> the line [and rows]; rc 0
  local rec="$1" root="$2" rows="$3" gd f dead reqs="" out mal
  { [ -n "${_LINE_FIELDS_AWK:-}" ] || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; }
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
  if landing_unmeasured "$rec"; then printf 'landings: unmeasured — the landing record holds no line/v1 events\n'; return 0; fi
  [ -f "$rec" ] && [ ! -L "$rec" ] || rec=/dev/null
  out="$(printf '%s' "$reqs" | awk -F'|' -v root="$root" -v rows="$rows" "$_PATROL_ISO_AWK${_LINE_FIELDS_AWK:-}"'
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
    (ev = line_ev()) == "" { next }
    {
      rk = line_kv("row"); e = iso2epoch(line_kv("at"))
      g = rk SUBSEP (gen[rk] + 0)
      if (ev == "run") nrl++
      if (ev == "verdict" && line_kv("kind") == "regression") next   # facts of the whole run, no row ran them
      if ((ev == "candidate" || ev == "ready") && line_kv("commit") != "") ownc[g SUBSEP line_kv("commit")] = 1
      if (ev == "candidate") hasc[g] = 1
      if (ev == "candidate" && e >= 0 && !(rk in fc)) fc[rk] = e
      if (ev != "ready" && ev != "verdict" && ev != "returned" && ev != "published" && ev != "reused") { if (e >= 0 && t0 == "") t0 = e; next }
      if (rk == "" || e < 0) { mal++; next }
      if (ev == "verdict" && (line_kv("suite") == "" || line_kv("result") !~ /^(green|red|none|discarded|absent)$/)) { mal++; next }
      if (ev == "reused" && line_kv("suite") == "") { mal++; next }
      if (ev == "published" && line_kv("kind") !~ /^(queue|hand|git)$/) { mal++; next }
      if (t0 == "") t0 = e
      iso[e] = line_kv("at")
      if (ev == "verdict" && line_kv("result") != "absent" && line_kv("width") ~ /^[0-9]+$/) wd[rk] = line_kv("width")
    }
    # THE SAVING (wave-39 T2; D5, AC-1.4): a suite proved by the verdict of another candidate, no run of its own.
    ev == "reused" { nru++; next }
    ev == "returned" { if (e >= 0) { nrw[rk]++; rs[rk, nrw[rk]] = e; re[rk, nrw[rk]] = "" }; next }
    ev == "ready" {
      if (!(rk in rdy)) rdy[rk] = e
      for (i = nrw[rk]; i >= 1 && re[rk, i] == ""; i--) re[rk, i] = e
      span[rk]++; next
    }
    ev == "verdict" {
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
    ev == "published" {
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
    }' phase=0 - phase=1 "$rec")"
  mal="$(printf '%s\n' "$out" | sed -n 's/^#malformed //p')"
  printf '%s\n' "$out" | /usr/bin/grep -v '^#malformed '
  [ -z "$mal" ] || die "landing-report — $mal malformed line/v1 line(s) skipped in $1"
  return 0
}

# ---------------------------------------------------------------- the run's hand-holds
#
# THE HAND-HOLD COUNT IS FOLDED FROM THE LINES THE ESCAPE-HATCH VERBS WROTE (wave-35 T12; D17, REQ-8
# AC-8.1). `landing-report --hand-holds` prints, under the landings line,
#
#   hand-holds: total=<n> · by-hand=<n> · stop-runs=<n> · declines=<n> · lifts=<n> · amends=<n> · holds=<n> · extensions=<n> · waivers=<n> · second-floors=<n> · adoptions=<n> · fixed=<n>
#
# A hand-hold is a use of a verb that steps round the machine. Each kind is counted from the one line its
# verb wrote, and PROSE IS NEVER READ (D1): a line that says `by-hand` in a plan, a note or the orchestrator's
# own assumptions counts nothing, and so does anything the orchestrator did that no verb recorded.
#
#   by-hand        the landing record's `line/v1|ev=published|…|kind=hand|…` (lib/line.sh), one per landing.
#   stop-runs      the landing record's `line/v1|ev=stop-run|…`, one per `stop-run` that stopped a run or ended a
#                  gate request (wave-36 T11; D8, AC-2.3). A stop is a verb act: never counted as by-hand.
#   declines       the run's fill ledger's `fill-ledger/v1|…|state=decline|…` lines, one per `decline`. The Stop hook
#   lifts          writes `state=ok` and `state=hold` only, so a `hold` there is the fill's wait and not the `hold` verb.
#                  `state=lift` is `decline lift`'s line.
#   amends         the roster's `amended=<iso> <reason>` (`amend`), `held=` (`hold`) and `extended=` (`extend`).
#   holds          A roster row is re-written on every status change and copies the field, so a kind is counted by
#   extensions     DISTINCT (name, value) over the rosters whose `plan=` is this run's plan (a row of another run, or of
#                  `plan=none`, is not this run's). The roster lives in `.bionic/tmp`, which close-out's act 3 wipes,
#                  so close-out reads this line BEFORE the wipe and carries it.
#   waivers        the plan's `waived: question=…` line under `## SDLC State` (`waive`) and an AC block's indented
#                  `waiver: <who> <YYYY-MM-DD> "<words>"` under `## Verification Matrix` (`waive-row`). Fenced text is
#                  skipped, as every reader of the plan skips it.
#   second-floors  `proved: kind=floor` lines under `## SDLC State` past the first (`proof-add floor`), read through
#                  lib/proof.sh's `proof_fields`, the one reading of a proof line.
#   adoptions      the roster row `adopt` files for each agent it adopts (`adopt_write_row`: `source=adopted`,
#                  `adopted_from=<sid>`), DISTINCT (agent_id, adopted_from) over the run's rosters, as the amends are
#                  (wave-36 T14; D13, AC-7.6). Its printed `poker-adopt/v1|…` report is kept in no file, so the row is
#                  the line the verb wrote. A verb act: never counted as by-hand.
#   fixed          the plan's `moved: <record>#<n> to=fixed row=<T> …` line under `## SDLC State` (`finding-move …
#                  fixed`, wave-36 T8), one per line (wave-36 T14; AC-7.6). A verb act: never counted as by-hand.
#
# READ-ONLY and FAIL-SOFT: an absent source counts zero. It decides nothing; nothing reads it but close-out's card and
# continuation (and a person).
hand_holds_report() {  # <landing record> <project root> <plan> -> the one hand-holds line; rc 0
  local rec="$1" root="$2" plan="$3" slug led rf hand=0 stp=0 dec=0 lif=0 amd=0 hld=0 ext=0 wv=0 fl=0 ado=0 fix=0 pl
  slug="$(proof_plan_slug "$plan")"
  if [ -f "$rec" ] && [ ! -L "$rec" ] && { [ -n "${_LINE_FIELDS_AWK:-}" ] || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; }; then
    read -r hand stp <<< "$(awk -F'|' "${_LINE_FIELDS_AWK:-}"'
      { ev = line_ev() }
      ev == "published" && line_kv("kind") == "hand" { n++ }
      ev == "stop-run" { s++ }
      END { print n + 0, s + 0 }' "$rec")"
  fi
  led="$(fill_ledger_path "$root" "$plan" 2>/dev/null)" || led=""
  if [ -n "$led" ] && [ -f "$led" ] && [ ! -L "$led" ]; then
    read -r dec lif <<< "$(awk -F'|' '
      index($0, "fill-ledger/v1|") == 1 {
        for (i = 2; i <= NF; i++) if (index($i, "state=") == 1) { s = substr($i, 7); if (s == "decline") d++; else if (s == "lift") l++ }
      }
      END { print d + 0, l + 0 }' "$led")"
  fi
  read -r amd hld ext ado <<< "$(for rf in "$root/.bionic/tmp"/roster-*.state; do
      [ -f "$rf" ] && [ ! -L "$rf" ] && cat "$rf"
    done 2>/dev/null | awk -F'|' -v want="/$slug.plan.md" '
      index($0, "roster-state/") == 1 {
        name = ""; plan = ""; a = ""; h = ""; x = ""; id = ""; src = ""; af = ""
        for (i = 2; i <= NF; i++) {
          if (index($i, "name=") == 1) name = substr($i, 6)
          else if (index($i, "agent_id=") == 1) id = substr($i, 10)
          else if (index($i, "source=") == 1) src = substr($i, 8)
          else if (index($i, "adopted_from=") == 1) af = substr($i, 14)
          else if (index($i, "plan=") == 1) plan = substr($i, 6)
          else if (index($i, "amended=") == 1) a = substr($i, 9)
          else if (index($i, "held=") == 1) h = substr($i, 6)
          else if (index($i, "extended=") == 1) x = substr($i, 10)
        }
        if (length(plan) < length(want) || substr(plan, length(plan) - length(want) + 1) != want) next
        if (a != "") A[name SUBSEP a] = 1
        if (h != "") H[name SUBSEP h] = 1
        if (x != "") X[name SUBSEP x] = 1
        if (src == "adopted" && af != "" && id != "") D[id SUBSEP af] = 1
      }
      END { for (k in A) na++; for (k in H) nh++; for (k in X) nx++; for (k in D) nd++; print na + 0, nh + 0, nx + 0, nd + 0 }')"
  if [ -f "$plan" ] && [ ! -L "$plan" ]; then
    if ! declare -F proof_awk >/dev/null 2>&1 && [ -f "$BIONIC_LIB/proof.sh" ]; then . "$BIONIC_LIB/proof.sh"; fi
    if declare -F proof_awk >/dev/null 2>&1; then
      read -r fl wv fix <<< "$(awk "$(proof_awk)"'
        /^[ \t]*```/ { fence = !fence; next }
        fence { next }
        /^##[ \t]/ { sec = ($0 ~ /^##[ \t]+SDLC State/) ? "sdlc" : (($0 ~ /^##[ \t]+Verification Matrix/) ? "mx" : ""); inb = 0; next }
        sec == "sdlc" {
          if (proof_fields($0) && PROOF_KIND == "regression") f++
          else if ($0 ~ /^waived:[ \t]+question=/) w++
          else if ($0 ~ /^moved:[ \t]+[^ \t]+[ \t]+to=fixed([ \t]|$)/) x++
          next
        }
        sec == "mx" {
          if ($0 ~ /^AC-[^ \t]*:[ \t]*$/) { inb = 1; next }
          if (inb && $0 ~ /^[ \t]+[^ \t]/) {
            if ($0 ~ /^[ \t]+waiver:[ \t]+[^"]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][ \t]+"/) w++
            next
          }
          inb = 0
        }
        END { print f + 0, w + 0, x + 0 }' "$plan")"
    fi
  fi
  [ "${fl:-0}" -gt 1 ] && fl=$((fl - 1)) || fl=0
  printf 'hand-holds: total=%d · by-hand=%d · stop-runs=%d · declines=%d · lifts=%d · amends=%d · holds=%d · extensions=%d · waivers=%d · second-regressions=%d · adoptions=%d · fixed=%d\n' \
    $(( hand + stp + dec + lif + amd + hld + ext + wv + fl + ado + fix )) "$hand" "$stp" "$dec" "$lif" "$amd" "$hld" "$ext" "$wv" "$fl" "$ado" "$fix"
  return 0
}

  # THE LANDING'S ROW (wave-28 T6; REQ-3 AC-3.2, D7; ruling A-orch-81). `line_publish`
  # (lib/line.sh) runs this verb, as a command, inside its publish lock once the fast-forward and
  # its `published` event are written: the row's status `landed` (`units_table_cells` on the tasks
  # table, judged by `units_validate` as `task-set` judges a status), its `- T<n>:` line
  # (`units_step_line`) and its dispatch-ledger row's `landed` cell (`units_table_cells` on the
  # ledger), onto ONE copy and through ONE `plan_verb_swap ... writer`: all three lines or none.
  # Writer mode is the point: past Step 4 the dry copy reads `current: 4`, so the declared debt the
  # publish has just written (T5) cannot refuse the publish's own bookkeeping, and the debt stays
  # in the bound plan's landing record for the gate to read at the next step move (wave-27 passes
  # 60 and 63: the dry copy is `plan_verb_open`'s own, so the gate resolves it to the real plan).
  # The step line gains ` landed <commit> <at>` after its own text (a hand landing: ` landed-by-hand:
  # <who> <at> "<why>"`, the hand landing's interface), once: a text already there is not added
  # again. The ledger cell reads `landed <at> <commit>`; a ledger with no row of that id gains one,
  # and a plan with no `## Dispatch ledger` table has no ledger line to write. A run again of the
  # same landing finds the plan already so and writes nothing.
  #
  # A PLACEHOLDER LEAD IS REPLACED, NOT KEPT (wave-33 T6; REQ-3 AC-3.3, D5). A line that opens
  # `pending dispatch` (the Step-3 template, `task-add`, `task-split`) gives that lead to the landing
  # text and keeps the rest of its words, a ` born: ` marker included (`units_born` reads it there):
  # `- T5: pending dispatch — .worktrees/01-T5` lands as `- T5: landed <commit> <at> — .worktrees/01-T5`.
  #
  # `deliver <row>` (wave-33 T6; D5) is this verb for a record row: `deliver_check` reads what the row
  # owes and sets the commit (the working head), the instant (now) and the artifact, which is
  # written into the ledger line's `artifact` cell beside the landed one, in this same write.
  poker_verb_row_landed() {
    if ! plan_verb_id_ok "$PV_ID"; then
      die "REFUSED — '$(clean "$PV_ID")' is not one row id; the plan is unchanged."
      exit 1
    fi
    if ! plan_verb_value_ok "$RL_BY" || ! plan_verb_value_ok "$RL_WHY"; then
      die "REFUSED — the hand landing's name or reason carries a |, a tab or a line break, which no plan line can hold; the plan is unchanged."
      exit 1
    fi
    plan_verb_open row-landed
    [ "$VERB" != deliver ] || deliver_check
    [ "$RL_HAND" -eq 0 ] || row_landed_scan
    PV_RC=0
    units_table_cells "$PV_PLAN" set tasks "$PV_ID" status=landed > "$PV_NEW" 2>/dev/null || PV_RC=$?
    case "$PV_RC" in
      0) : ;;
      1) die "REFUSED — $PV_PLAN carries no ## Tasks table; the plan is unchanged."; exit 1 ;;
      2) die "REFUSED — the ## Tasks table carries no row $PV_ID; the plan is unchanged."; exit 1 ;;
      5) die "REFUSED — the ## Tasks table carries more than one row $PV_ID; the plan is unchanged."; exit 1 ;;
      *) die "REFUSED — the ## Tasks row $PV_ID cannot take status landed; the plan is unchanged."; exit 1 ;;
    esac
    PV_VIOL="$(units_validate "$PV_NEW" 2>&1)"
    if [ -n "$PV_VIOL" ]; then
      die "REFUSED — with $PV_ID landed, the ## Tasks table breaks the Task invariants; the plan is unchanged:"
      printf '%s\n' "$PV_VIOL" >&2
      exit 1
    fi
    case "$PV_ID" in
      T[0-9]*)
        RL_TEXT="landed $RL_COMMIT $RL_AT"
        [ "$RL_HAND" -eq 0 ] || RL_TEXT="landed-by-hand: $RL_BY $RL_AT \"$RL_WHY\""
        RL_REST="$(units_step_text "$PV_NEW" "$PV_ID" 2>/dev/null)"
        case " $RL_REST " in
          *" $RL_TEXT "*) RL_LINE="$RL_REST" ;;
          " pending dispatch "*) RL_LINE="$RL_TEXT${RL_REST#pending dispatch}" ;;
          *) RL_LINE="${RL_REST:+$RL_REST }$RL_TEXT" ;;
        esac
        if ! units_step_line "$PV_NEW" "$PV_ID" "$RL_LINE" > "$PV_NEW.2" 2>/dev/null; then
          die "REFUSED — $PV_PLAN carries no ## SDLC State section for the $PV_ID line; the plan is unchanged."
          exit 1
        fi
        mv -f "$PV_NEW.2" "$PV_NEW" ;;
    esac
    PV_RC=0
    units_table_cells "$PV_NEW" set ledger "$PV_ID" "landed=landed $RL_AT $RL_COMMIT" > "$PV_NEW.2" 2>/dev/null || PV_RC=$?
    if [ "$PV_RC" -eq 2 ]; then
      PV_RC=0
      units_table_cells "$PV_NEW" add ledger "$PV_ID" "landed=landed $RL_AT $RL_COMMIT" > "$PV_NEW.2" 2>/dev/null || PV_RC=$?
    fi
    case "$PV_RC" in
      0) mv -f "$PV_NEW.2" "$PV_NEW" ;;
      1) rm -f "$PV_NEW.2" ;;
      3) die "REFUSED — the ## Dispatch ledger header carries no landed column; the plan is unchanged."; exit 1 ;;
      5) die "REFUSED — the ## Dispatch ledger table carries more than one row $PV_ID; the plan is unchanged."; exit 1 ;;
      *) die "REFUSED — the ledger row $PV_ID cannot take its landed cell; the plan is unchanged."; exit 1 ;;
    esac
    # A DELIVERED ROW'S LEDGER LINE NAMES ITS ARTIFACT (wave-33 T6; AC-3.1): the cell the artifact was
    # read from, or the empty one of a line this landing added. A ledger with no artifact column has
    # no cell to hold it, and the landing stands without one.
    if [ -n "$RL_ARTIFACT" ] && [ "$PV_RC" -eq 0 ]; then
      if units_table_cells "$PV_NEW" set ledger "$PV_ID" "artifact=$RL_ARTIFACT" > "$PV_NEW.2" 2>/dev/null; then
        mv -f "$PV_NEW.2" "$PV_NEW"
      else
        rm -f "$PV_NEW.2"
      fi
    fi
    # THE EVIDENCE CELLS (wave-31 T22; REQ-15 AC-15.1 to AC-15.3, D15): the criteria this row serves gain the log of
    # the suite their eval names, read off the landing record's verdicts for this row and commit (`landing_evidence`).
    # A hand landing's record carries no verdict, so it writes none. Same copy, same dry commit, same swap.
    RL_SLUG="$(proof_plan_slug "$PV_PLAN")"
    RL_N="$(landing_evidence "$PV_NEW" "$PV_NEW.2" "$PV_ID" "$RL_COMMIT" "$(_wt_proofs_path "$PV_REPO" "$PV_PLAN")" \
      "$(docs_root "$PV_REPO")" "$RL_SLUG")" || {
      die "REFUSED — the evidence cells of the criteria $PV_ID serves cannot be written; the plan is unchanged."
      exit 1
    }
    [ ! -f "$PV_NEW.2" ] || mv -f "$PV_NEW.2" "$PV_NEW"
    plan_verb_swap row-landed "$PV_ID landed at $RL_COMMIT" writer
    say "row-landed — $PV_ID landed at $RL_COMMIT: status, step line and ledger line written to $PV_PLAN in one write; dry-committed first."
    # A HAND LANDING IS RECORDED (wave-39 T10; D14, AC-6.2). The landing record gains the line the line's own hand
    # landing writes (lib/line.sh `line_publish`, field for field), at the landing's instant, so landing-report's
    # Landings list the row and `--hand-holds` counts it; a hand-marked landing used to reach the plan alone. Once:
    # the line's `land --by-hand` writes its published line before it runs this verb, and a run again of the same
    # landing finds it, so a published line for this row and commit already in the record is the landing recorded.
    # The plan is written first; a record that cannot be written refuses (1) after it, and the same call again
    # writes the record line alone.
    if [ "$RL_HAND" -eq 1 ]; then
      RL_REC="$(_wt_proofs_path "$PV_REPO" "$PV_PLAN")"
      { [ -n "${_LINE_FIELDS_AWK:-}" ] || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; }
      if ! awk -F'|' -v r="$PV_ID" -v c="$RL_COMMIT" "${_LINE_FIELDS_AWK:-}"'
        line_ev() == "published" && line_kv("row") == r && line_kv("commit") == c { f = 1 } END { exit !f }' "$RL_REC" 2>/dev/null; then
        mkdir -p "${RL_REC%/*}" 2>/dev/null
        if ! _wt_proofs_put "$RL_REC" "line/v1|ev=published|row=${PV_ID}|commit=${RL_COMMIT}|kind=hand|by=${RL_BY}|why=${RL_WHY}|at=${RL_AT}"; then
          die "REFUSED — the plan records $PV_ID landed by hand, but the landing record $RL_REC cannot take its published line; make it writable and run the same row-landed again."
          exit 1
        fi
        say "row-landed — $PV_ID landed by hand: ev=published kind=hand written to $RL_REC"
      fi
    fi
    say "evidence: $RL_N cell(s) written by landing"
    [ "$VERB" != deliver ] || say "deliver — $PV_ID: artifact $RL_ARTIFACT present; landed at the working head $RL_COMMIT."
    exit 0
  }
