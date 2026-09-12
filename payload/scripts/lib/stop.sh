#!/bin/bash
# payload/scripts/lib/stop.sh — THE FOUR TURN-END VERDICTS, AS FUNCTIONS
# (epic-23 wave-11-lean-spine, REQ-1f (iv); spec Design §2 D4, §3 ownership row
# "turn-end verdict"; ADR-004.)
#
# WHAT IT OWNS. The bodies of the four hooks that used to fire on Stop, one
# function each, in the order hooks.json listed them:
#
#   stop_context_spend   the instrument — one audit line per SDLC step boundary
#   stop_landing_gate    the sweep and the teammate landing verdict
#   stop_patrol_duties   the tick's three duties, and the resume ritual
#   stop_patrol_revive   the Patrol stamp's self-heal
#
# NO BEHAVIOUR MOVED (R2). Each function is the corresponding hook's body after
# its preamble, carried over verbatim — its own arms, its own reads, its own
# refusal object — with four mechanical changes and no fifth:
#
#   1. `exit 0`            -> `return "$_adv"`, the function's own verdict
#   2. `refuse <mode> …`   -> `fold_block <mode> …` + `return 2`
#   3. an advisory `echo … >&2` -> `fold_advise …` + `_adv=1`
#   4. every variable the body assigns is `local`
#
# (1)–(3) exist because a folded function must not exit and must not render:
# payload/scripts/lib/fold.sh runs these in the CALLER'S shell and composes what
# they stage. (4) exists because they now share one shell: `LINE`, `STATE`,
# `PLAN`, `VERDICT` and `REASON` are each assigned by more than one of the four,
# and a global would let one verdict read another's half-finished value.
#
# THE VALUES COME FROM `bionic_context`, ONCE, IN THE CALLER (REQ-1h, lib/context.sh).
# Every function below reads BIONIC_INPUT, BIONIC_ROOT, BIONIC_SID, BIONIC_ENGAGED,
# BIONIC_RUN_WORD and BIONIC_RUN_PLAN as values it did not fetch. That is what
# collapses four identical preambles into one and it is also what makes the four
# agree: four hooks each spelling the cwd ladder their own way could attribute one
# session's stop to two different roots.
#
# ── THE EVENT IS AN ARGUMENT, AND EVERY FUNCTION READS IT ─────────────────────
#
# `hooks/stop.sh` is registered on Stop AND SubagentStop, so each function is
# handed the event name and answers for itself:
#
#   stop_landing_gate    Stop -> the sweep; SubagentStop -> the landing verdict.
#                        Its own `case` moved here unchanged; it is the only one of
#                        the four with a SubagentStop arm at all.
#   stop_patrol_duties   Stop only. A subagent has no Patrol duties.
#   stop_patrol_revive   Stop only. A subagent arms no Patrol.
#   stop_context_spend   Stop only — AND THIS GUARD IS NEW, which is a change worth
#                        naming rather than burying. hooks/context-spend.sh read no
#                        `hook_event_name` at all (`grep -n hook_event_name
#                        hooks/context-spend.sh` printed nothing); it never needed
#                        to, because the manifest registered it on Stop alone. The
#                        merged process is also on SubagentStop, so without this
#                        line the instrument would start recording step boundaries
#                        on every teammate landing — a behaviour it never had. The
#                        guard preserves what it did, it does not add a rule.
#                        tests/context-spend.test.sh §1b pins the before and after.
#
# THE RE-ENTRANCY GUARD IS NOT HERE. `stop_hook_active` is read ONCE, in
# hooks/stop.sh, ahead of all four — three of the four carried an identical copy of
# it and the fourth (context-spend, again) carried none. One reading of one field is
# the point of the merge.
#
# BASH 3.2. No associative arrays, no `mapfile`.
#
# SOURCED, NEVER EXECUTED, AND SILENT AT SOURCE TIME.
#
# [WALL: tests/stop.test.sh]
# [WALL: tests/context-spend.test.sh]
# [WALL: tests/landing-gate.test.sh]
# [WALL: tests/patrol-duties-gate.test.sh]
# [WALL: tests/patrol-revive.test.sh]

_stop_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}
_STOP_LIB_DIR="$(cd "$(_stop_self_dir)" && pwd -P)"

if ! declare -F bionic_fold >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$_STOP_LIB_DIR/fold.sh"
fi

# ─── FILE SCOPE: hooks/context-spend.sh's audit path ─────────────────────────
#
# Carried over at COLUMN ZERO and byte-identical to the copies in
# farm-out-reminder.sh, canonical-sdlc-governing-skill.sh and
# canonical-sdlc-evidence-gate.sh — divergence would give one project two audit
# files, which is the whole reason those four copies are deliberate rather than
# shared.


# Incident 0001: the audit stream must live where a consuming project cannot
# commit it, regardless of that project's .gitignore. $HOME-rooted, per-project,
# durable — the same $HOME/.claude/ audit path the archived epic-10 poker used
# (that work is recoverable at tag archive/epic-10-never-die).
# Slug = <basename>-<cksum of the absolute path>: readable, deterministic, and
# collision-resistant across same-named projects under different parents.
# cksum and basename are POSIX — no new dependency.
# Byte-identical to the copies in farm-out-reminder.sh,
# canonical-sdlc-governing-skill.sh and canonical-sdlc-evidence-gate.sh —
# divergence would give one project two audit files. Deliberate per-hook
# duplication (no shared lib).
# [INSTRUMENT]
audit_path() {  # $1=project root → absolute audit-file path; rc 1 if no $HOME
  [ -n "${HOME:-}" ] || return 1
  local base sum
  base=$(basename "$1" | sed 's/[^A-Za-z0-9._-]/-/g')
  sum=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  printf '%s/.claude/logs/%s-%s/sdlc-audit.md' "$HOME" "$base" "$sum"
}

# ─── FILE SCOPE: hooks/landing-gate.sh's constants and helpers ───────────────
#
# AT COLUMN ZERO, DELIBERATELY. `SWEPT_SCHEMA` and `swept_marker_write` are read
# out of this file by extraction — tests/cross-gate-agreement.test.sh §S15 pins the
# writer against a captured marker with `awk '/^swept_marker_write\(\)/,/^}/'` and
# §S15b pins the constant's assignment line with `grep -m1 '^SWEPT_SCHEMA='`. Both
# anchor at the start of a line, so these keep their margin; indenting them into a
# function would make the pin go quietly vacuous rather than red.


SWEPT_SCHEMA="landing-swept/v1"
# Reader copy of hooks/dispatch-preflight.sh's roster constant, on the same precedent
# hooks/session-sweeper.sh states for its copy: a prefix drift here is a mislabeled scan.
ROSTER_VERSION="v1"

# THE ONE WRITER (S15, AC-26; research-code-map §2.c). Defined here, not sourced from a
# shared lib file: this hook's own `BIONIC_LIB_WANT` stays "root.sh run.sh session.sh"
# unchanged, and a copy of this file (as tests/landing-gate.test.sh's own mutation-arm
# fixtures make) carries the writer with it rather than depending on a lib file resolving
# through the loader's registry/cache fallback to whatever was last landed there.
# hooks/session-poker.sh's `adopt_copy_marker` never calls this function — its job is to
# relay a line this one already wrote, verbatim — but it DOES share the `SWEPT_SCHEMA`
# constant above, spelled identically (byte-pinned, tests/cross-gate-agreement.test.sh),
# never as a second literal the way `grep -rn SWEPT_SCHEMA hooks/*.sh` could miss.
swept_marker_write() {  # <roster file> <at> <session> <name> <agent id> <state> -> 0/1
  local f="$1" at="$2" sid="$3" name="$4" aid="$5" state="$6"
  [ -n "$f" ] || return 1
  printf '%s|at=%s|session=%s|name=%s|agent_id=%s|state=%s\n' \
    "$SWEPT_SCHEMA" "$at" "$sid" "$name" "$aid" "$state" >> "$f" 2>/dev/null
  return 0
}

# ---------------------------------------------------------- FILES: RECONCILIATION (S18, AC-22)
#
# DECLARE -> DERIVE -> RECONCILE (design ledger D2). `hooks/dispatch-preflight.sh` derives a
# BUDGET from a brief's `Files:` at dispatch; these two functions are the third leg — asking,
# once a row is landed, whether the diff the agent actually produced stayed inside that same
# declared set. Called from the per-candidate loop below, never from the sweeper: the
# sweeper answers about the DELIVERABLE, this answers about the DIFF, and the two questions
# share a candidate line but not a verdict.

# The row's worktree, by the ONE mapping the fleet has for "which tree belongs to whom"
# (payload/scripts/lib/worktree.sh's `worktree_for_row`, sourced above as `BIONIC_LIB_WANT`
# declares). That function only builds a path string — it lowercases the row name and never
# stats anything — which a case-INSENSITIVE filesystem (macOS, this wave's covered
# environment) resolves against a mixed-case directory for free. A case-SENSITIVE one
# (Linux, fog) would not, so the fallback below scans the farm by lowercased basename before
# giving up; it is the one place this file re-derives any part of the mapping, and it does
# so only to absorb a filesystem property `worktree_for_row` does not, never to re-decide
# which directory a row's name means.
_lg_worktree_for_name() {  # <repo> <row name> -> abs worktree path on stdout, or nothing
  local repo="$1" name="$2" cand d base lc
  if declare -f worktree_for_row >/dev/null 2>&1; then
    cand=$(worktree_for_row "$repo" "$name" 2>/dev/null)
    if [ -n "$cand" ] && [ -d "$cand" ]; then printf '%s' "$cand"; return 0; fi
  fi
  lc=$(printf '%s' "${name#W-}" | tr '[:upper:]' '[:lower:]')
  [ -n "$lc" ] && [ -d "$repo/.worktrees" ] || return 1
  for d in "$repo"/.worktrees/*/; do
    [ -d "$d" ] || continue
    base=$(basename "$d")
    if [ "$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')" = "$lc" ]; then
      printf '%s' "${d%/}"
      return 0
    fi
  done
  return 1
}

# Is a path the diff touched inside the declared set? Exact match, or under a declared
# DIRECTORY — "a declared directory covers its files" (S18 brief) — checked without caring
# whether the author spelled the directory with a trailing slash.
_lg_path_declared() {  # <diff path> <comma-joined declared files>
  local p="$1" list="$2" old_ifs entry
  old_ifs="$IFS"; IFS=','; set -f
  # shellcheck disable=SC2086
  set -- $list
  set +f; IFS="$old_ifs"
  for entry in "$@"; do
    entry="${entry%/}"
    [ -n "$entry" ] || continue
    [ "$p" = "$entry" ] && return 0
    case "$p" in "$entry"/*) return 0 ;; esac
  done
  return 1
}


# ─── THE BODIES KEEP THEIR MARGIN ────────────────────────────────────────────
#
# Every carried-over body below sits at COLUMN ZERO inside its function, which is
# not a style slip. Three things depend on it:
#
#   the diff        an indented copy is a changed copy, and this merge's whole
#                   claim is that the bodies did not change. `git show <base>:hooks/
#                   <h>.sh` and the corresponding span here differ only in the four
#                   mechanical edits the header names.
#   heredocs        `<<LGDIFF` and `<<EOF` in the sweep, and `<<BIONIC_LOADER_VER`
#                   in what they call, terminate on a line that is the tag and
#                   nothing else. Indenting the terminator makes the heredoc run to
#                   end-of-file, which is how this file first failed to parse.
#   the extractions tests/cross-gate-agreement.test.sh reads `_field()`,
#                   `swept_marker_write()` and `SWEPT_SCHEMA=` out of the source with
#                   `^`-anchored patterns.
#
# The `local` blocks that open each function are this file's own lines and are
# indented normally, so the margin change marks exactly where the new text stops and
# the carried-over text starts.


# ─── stop_context_spend ───
#
# THE HOOK'S OWN HEADER, CARRIED OVER WHOLE. It is the design record for this
# verdict — every ruling, incident and measurement that shaped it — and it
# travels with the code rather than being left behind in a deleted file.
# Where it says "this hook" it now means this function, and where it names a
# registration it means hooks/stop.sh's.
#
# CONTEXT-SPEND: advisory Stop hook — appends ONE context-spend line per
# SDLC step boundary to $HOME/.claude/logs/<project-slug>/sdlc-audit.md —
# outside every consuming project tree (incident 0001), via audit_path() —
# reusing the log_v11_finding() line format (source: context-spend).
#
# Mechanism (epic-08 A7 / Q2 spike): Stop = trigger + transcript_path;
# last assistant message.usage (TOP-LEVEL, never iterations[]) = occupancy
# (input + cache_creation + cache_read); the active plan's `current:` line
# = step attribution; .bionic/tmp/context-spend.state = boundary detector.
# [INSTRUMENT]
#
# Failure mode: silence. Missing jq/transcript/usage/plan/current →
# exit 0, nothing appended, state untouched. NEVER blocks, NEVER writes
# stdout (a Stop hook's stdout could carry a block payload).
# [INSTRUMENT]
#
# Registered once in hooks/hooks.json, always on, and scoped by an on-disk fact rather
# than by whether a skill is armed: it asks `session_run` (which was `active_run` until
# wave-session-bound-run made run identity per-session) whether THIS SESSION has an open run
# and exits silently when it does not.
#
# hooks/context-spend.sh's body. NEVER refuses and NEVER writes stdout — a Stop
# hook's stdout can carry a block payload — so its only verdicts are 0 and 1.

stop_context_spend() {  # <event> -> 0 nothing · 1 advisory · 2 block
  local _ev="${1:-}" _adv=0
  local TRANSCRIPT PLAN STEP _row MODEL OCCUPIED STATE_DIR STATE
  local s_plan s_sess s_step s_occ DELTA LINE AUDIT_FILE

  # THE EVENT GUARD THE HOOK NEVER HAD — see this file's header. Stop only, and an
  # absent field is not a mismatch, so a hand-run payload still measures.
  case "$_ev" in ""|Stop) : ;; *) return 0 ;; esac

  TRANSCRIPT=$(bionic_jq .transcript_path)
  [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || return 0

# ---------- THE ENGAGEMENT SWITCH — asked before anything else ----------
#
# task-engaged-session: bionic's walls are the RUN's, not the repo's, and a run is entered
# by invoking canonical-sdlc. A session that never did is a bystander here and must not see
# a refusal, an advisory, or a state write from this hook. `engaged_session` (lib/run.sh) is
# true only for a REGULAR file at `.bionic/tmp/engaged-<sid>.state`; every unreadable state —
# absent, symlink, foreign sid — reads as NOT engaged. Silent, return "$_adv": the direction §7
# gives every start-side ambiguity, and here it is the consent boundary itself (1.3.2
# close-out ruling). `bionic_context` asked the question above; this is the answer.
[ "$BIONIC_ENGAGED" = 1 ] || return "$_adv"

# ---------- THE RUN PREDICATE (AC-7, AC-8) ----------
#
# The plan AND the arming question, from one reader. This hook used to answer "which
# plan" with its own `ls -t` over three glob depths — a fourth spelling of a question
# five hooks were each answering differently, and the one that ignored the
# `## SDLC State` marker entirely, so any newest .md under plans/ could become the file
# it attributed a step boundary to.
#
# PLAN-BOUND, WHOLLY (task-engaged-session). Engagement decides WHETHER this hook acts and
# has decided yes above; what remains is the plan deciding WHAT, and every line below
# measures against it — the step boundary comes from the plan's `current:`, the state file
# is keyed by (plan, session), and the audit line names the plan. An engaged session with no
# plan on disk has no step boundary to record, so this arm skips rather than the hook being
# out of scope. The exit is an arm skip now, not the scoping decision it used to be.
#
# wave-session-bound-run S5: `active_run` (no session input) is now `session_run`
# (lib/run.sh) — a session BOUND to a plan is attributed against THAT plan alone,
# whatever else is open in the root (AC-1); UNBOUND falls back to the newest plan
# exactly as before, and this hook says so once on its advisory channel (stderr —
# this hook NEVER writes stdout, see the header) (AC-3); bound to a plan that has
# since closed takes exactly this line's existing branch — the hard exit — after
# announcing the closure (AC-6).
PLAN="$BIONIC_RUN_PLAN"
case "$BIONIC_RUN_WORD" in
  bound-open) : ;;
  fallback)
    fold_advise "context-spend: run resolved by newest-plan fallback (session unbound) — $PLAN"; _adv=1
    ;;
  bound-closed)
    fold_advise "context-spend: bound plan closed — $PLAN; this session has no open run"; _adv=1
    return "$_adv"
    ;;
  none|*)
    return "$_adv"
    ;;
esac
[ -n "$PLAN" ] && [ -f "$PLAN" ] || return "$_adv"

# current: from ## SDLC State — CR-normalized, fence-aware (the evidence-gate
# defect class: fenced skeletons quoting `current:` must stay invisible).
# [INSTRUMENT]
STEP=$(awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$PLAN" | awk '
  /^```/ { fence = !fence; next }
  fence { next }
  /^## SDLC State/ { insec = 1; next }
  insec && /^## / { insec = 0 }
  insec && /^current:[[:space:]]*/ { sub(/^current:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit }
')
[ -n "$STEP" ] || return "$_adv"

# Last assistant entry with usage, from a bounded tail. fromjson? swallows
# malformed lines. Emits "model<TAB>occupied" for the last qualifying entry.
_row=$(tail -n 400 "$TRANSCRIPT" 2>/dev/null | jq -Rr '
  fromjson? | select(.type == "assistant") | .message | select(.usage != null) |
  [(.model // "unknown"),
   ((.usage.input_tokens // 0) + (.usage.cache_creation_input_tokens // 0) + (.usage.cache_read_input_tokens // 0))] | @tsv
' 2>/dev/null | tail -1) || _row=""
[ -n "$_row" ] || return "$_adv"
MODEL=${_row%	*}
OCCUPIED=${_row##*	}
case "$OCCUPIED" in ''|*[!0-9]*) return "$_adv" ;; esac
[ "$OCCUPIED" -gt 0 ] || return "$_adv"

STATE_DIR="$BIONIC_ROOT/.bionic/tmp"
STATE="$STATE_DIR/context-spend.state"
mkdir -p "$STATE_DIR" 2>/dev/null || return "$_adv"

s_plan=""; s_sess=""; s_step=""; s_occ=""
if [ -f "$STATE" ]; then
  IFS='	' read -r s_plan s_sess s_step s_occ < "$STATE" 2>/dev/null || true
fi

# First-seen, plan switch, or session switch: seed silently. Two
# concurrent sessions on the same plan must never diff against each
# other's occupancy — a session change re-seeds, same as a plan change.
# [INSTRUMENT]
if [ "$s_plan" != "$PLAN" ] || [ "$s_sess" != "$BIONIC_SID" ] || [ -z "$s_step" ]; then
  printf '%s\t%s\t%s\t%s\n' "$PLAN" "$BIONIC_SID" "$STEP" "$OCCUPIED" > "$STATE" 2>/dev/null || true
  return "$_adv"
fi

# Same step: nothing to do (state deliberately untouched — it records the
# occupancy at the step's START boundary, so delta spans the whole step).
[ "$s_step" = "$STEP" ] && return "$_adv"

# Boundary: emit one line for the ENDED step.
case "$s_occ" in ''|*[!0-9]*) s_occ="$OCCUPIED" ;; esac
DELTA=$((OCCUPIED - s_occ))
if [ "$DELTA" -ge 0 ]; then DELTA="+$DELTA"; fi
LINE="- $(date -u +%Y-%m-%dT%H:%M:%SZ) context-spend step-$s_step: occupied=$OCCUPIED delta=$DELTA model=$MODEL ($PLAN)"
if AUDIT_FILE=$(audit_path "$BIONIC_ROOT"); then
  mkdir -p "$(dirname "$AUDIT_FILE")" 2>/dev/null && printf '%s\n' "$LINE" >> "$AUDIT_FILE" 2>/dev/null
fi
printf '%s\t%s\t%s\t%s\n' "$PLAN" "$BIONIC_SID" "$STEP" "$OCCUPIED" > "$STATE" 2>/dev/null || true
return "$_adv"
}


# ─── stop_landing_gate ───
#
# THE HOOK'S OWN HEADER, CARRIED OVER WHOLE. It is the design record for this
# verdict — every ruling, incident and measurement that shaped it — and it
# travels with the code rather than being left behind in a deleted file.
# Where it says "this hook" it now means this function, and where it names a
# registration it means hooks/stop.sh's.
#
# THE LANDING SWEEP — epic-16 wave-01 (the gate), wave-03 task T4c (the sweep).
#
# Stop. On every orchestrator turn end, during an active wave: read this session's roster,
# take a landing verdict for every contract that has LANDED since the last sweep, and refuse
# the stop once if any of them named artifacts that are not on disk. Outside an active wave,
# or on any ambiguity along the way, the stop passes through untouched.
#
# WHY A SWEEP, AND WHY ON THIS EVENT. Until wave-03 this ran on the subagent's own stop and
# judged the one agent that stopped. That event cannot reach it any more, and not by
# accident: skill-frontmatter hooks live in the harness's `appState.sessionHooks`, keyed by
# SESSION id, and the subagent-stop path looks them up under `agentId ?? session.id` — the
# subagent's id, which has no entry. Every event dispatched in a subagent context is
# therefore structurally invisible to a skill-registered hook, so a wall registered there is
# installed, syntactically fine, green in its own suite, and never runs
# (record/session-20260814-wave-detector-terminal-state/t4b-probe-report.md §3, read out of
# the shipped binary and confirmed by an eleven-session dual-channel A/B).
#
# `Stop` is delivered to that channel, fires once per orchestrator turn, keeps firing on
# turns the skill was not re-invoked on — and, the fact that makes the latency a non-issue,
# is GENERATED BY a background agent's landing: the completion wakes a fresh turn, which
# closes 2.5–3.7 s later and delivers a Stop nobody asked for (§2.3, §4, two independent
# replications). So a sweep here runs both when the orchestrator pauses and shortly after
# each landing, which is exactly the two moments a landing contract cares about.
#
# HOW A LANDING IS RECOGNISED. The payload carries `background_tasks[]`, one row per
# subagent that is STILL RUNNING, keyed by the same `id` the roster's `agent_id=` holds —
# `tool_response.agentId` at dispatch, `agent_id` on SubagentStart, `background_tasks[].id`
# here, one string across all three (§2.2, §4, measured on one dispatch). A roster row whose
# id is ABSENT from that list has landed; a row still on it is skipped in silence. Nothing
# on this path reads `agent_type`, which carries the subagent TYPE and never the dispatch
# name — the join defect t4-probes-report.md §5.1 found open and this task closes.
#
# ONCE PER ROW, EVER. Stop fires every turn and a landed row stays landed, so a sweep that
# re-verdicted would refuse every turn end for the rest of the session over one agent's
# failure — the false-alarm shape this machinery exists to end. Each verdicted row is
# journalled as a `landing-swept/v1|` line in the roster file it belongs to. That is the one
# thing this script writes, and it rides IN the roster because the promise it keeps must not
# outlive the rows it is about. Inertness to the rest of the fleet is NOT a blanket property
# of every roster reader — it holds per reader, for one of two separate reasons, and both
# must be true or the marker leaks into a reader's answer (t6-review.md F-1, reproduced live:
# `hooks/session-poker.sh` read the roster with no schema filter and the marker silenced its
# overdue NOTIFY for the swept row). `hooks/execution-recorder.sh`, `hooks/session-sweeper.sh`,
# `hooks/stop-guard.sh`, `hooks/stop-check.sh` and `hooks/stop-orders.sh` filter on the
# `roster-state/v1|` prefix before reading a row, so the marker's `landing-swept/v1|` prefix
# never matches. `hooks/dispatch-preflight.sh` does NOT filter on that prefix and is immune
# only by accident: its `owning_row_for` skips any row with no `deliverable=`, a field the
# marker never carries. That second immunity is undeclared to its own reader and untested —
# one added field to the marker's schema would turn it into a second instance of this bug.
#
# IT OWNS NO PREDICATE. The question "did this contract land" is answered by
# `hooks/session-sweeper.sh verdict <name>`, and this script parses that verb's machine line
# for `state=`, `acked=` and `detail=`. It never stats a deliverable and never forms an
# opinion about staleness, waivers or liveness-by-progress. It reads exactly two fields of
# the roster for itself — `agent_id`, which is the join key above, and `name`, which is what
# the verb must be asked about — plus `deliverable` as a pure PREFILTER: a row declaring
# nothing is MET vacuously by the verb's own rule, so skipping it cannot change an answer,
# only the cost of getting one.
#
# THE SECOND ARM: TEAMMATES LAND AT SubagentStop (session-20260815, T2; design D2).
# Everything above is true of an async subagent and false of a named teammate. A teammate
# carries THREE id namespaces that do not join — the addressing form at dispatch
# (`mate@session-7b7a693c`), the transcript form on SubagentStart/Stop
# (`amate-fdaa80c4b3cb703f`), and an opaque nine-character token in `background_tasks[]` that
# appears in no dispatch-time payload at all — and its row NEVER LEAVES that array: measured
# `status:"running"` on the last Stop of the session, 2 m 41 s after the teammate had
# delivered its own SubagentStop (t1-probe-report.md §2.1–§2.3, CLI 2.1.233). So the sweep
# predicate is not merely unjoinable for teammates, it is wrong in both directions: today
# every teammate row is skipped for want of an id, and the moment a writer fills one, every
# teammate reads as LANDED 2.8 s after dispatch, while it is still working.
#
# `SubagentStop` is the transition itself rather than a reconstruction of it, and it carries
# the id, the name and the moment in one payload. This arm therefore takes the SAME verdict
# from the SAME verb, writes the SAME marker through the SAME append, and speaks the SAME
# refusal — what differs is only which row is judged and when. It reads no live set (the
# stopping teammate is still in it), joins by `agent_id` first and by `agent_type` — which
# carries the dispatch NAME for a teammate — second, and both joins are scoped to rows
# carrying a non-empty `teammate_id=`.
#
# THAT SCOPE CUTS BOTH WAYS, and the sweep half of it is in the fold below: teammate rows are
# skipped there, with the one exception the next paragraph names. An async subagent stopping on this event is passed over in silence, because
# the sweep is the arm that owns it and the marker written here is exactly what would tell
# the sweep the row is already answered for — verdicting an async row here would not
# duplicate the sweep, it would silently replace the refusal the orchestrator sees with one
# delivered somewhere else.
#
# THE SUPERSESSION RECHECK (session-20260815-landing-cleanup, T3; ruling: supersede). The one
# thing the sweep does with a teammate row, and it is not a verdict. A refused teammate is
# told inside its own sidechain at the one moment it can still act, and it acts: measured
# live, the teammate read the feedback, wrote the promised artifact, and the roster still read
# `state=UNMET` when the session ended (record/session-20260815-landing-supervision/
# live-verify.md §B2). The refusal was correct and its record was a false statement about the
# world. So on any later Stop, a teammate row whose LATEST marker says UNMET and whose
# deliverable the verb now finds gets a SECOND marker appended, saying MET. Both persist, in
# order: the stream is history plus current state, and nothing is ever rewritten. It never
# refuses, it never writes a FIRST verdict for a teammate (an unmarked row stays the
# SubagentStop arm's, delivered or not), it costs nothing once the answer is MET, and it needs
# no clock of its own — Stop already fires on every turn end and shortly after every landing.
#
# WHERE THE REFUSAL GOES, stated because it differs from the sweep and the difference is not
# ours to change: a blocking Stop-hook exit on the main thread reaches the orchestrator,
# while on SubagentStop the harness delivers the feedback TO THE SUBAGENT and lets it
# continue so it can act on it (read out of the shipped CLI 2.1.233 binary:
# "additionalContext is non-error feedback delivered to the subagent; the subagent continues
# so it can act on it", beside the block-cap guidance "For Stop/SubagentStop hooks, check
# stop_hook_active in the input and return success while it is true"). So the agent that
# broke its contract is the one told about it, at the one moment it can still fix it, and the
# orchestrator-facing record is the roster marker plus the poker overdue NOTIFY that reads
# the same rows. `stop_hook_active` is honoured here for the reason the binary gives.
#
# FAIL DIRECTIONS (pinned by tests/landing-gate.test.sh):
#   - not a Stop or SubagentStop payload                 -> pass, silent (relevance hoist)
#   - SubagentStop with no agent_id, or one carrying
#     field separators                                   -> pass, silent
#   - SubagentStop matching no teammate row (a phantom
#     harness agent, or an async subagent the sweep
#     owns)                                              -> pass, silent
#   - no `background_tasks` key: nothing to tell landed
#     from live                                          -> pass, silent (ambiguity)
#   - stop_hook_active true                              -> pass, silent (blocks ONCE)
#   - cwd/repo unresolvable, or no session_id, or a
#     session_id that is not shaped like one             -> pass, silent (ambiguity)
#   - no roster for this session, or a symlinked one     -> pass, silent
#   - no active wave                                     -> pass, silent
#   - the sweeper is absent                              -> pass, silent
#   - a row with an EMPTY agent_id: it cannot be placed
#     on either side of the landed/live line             -> skip, unmarked (ambiguity)
#   - the verdict exits anything but 0 or 1, or prints
#     no line at all                                     -> skip, UNMARKED (no answer, so
#                                                          the row is still owed one)
#   - the verdict says anything but UNMET, or says UNMET
#     over an acked row                                  -> mark swept, pass
#   - the verdict says UNMET on a landed row             -> REFUSE, quoting its detail
#   - a swept teammate row, latest marker UNMET, and the
#     verdict now says MET                               -> append a superseding marker, pass
#   - the same row, verdict still anything but MET       -> nothing appended, pass, silent
#   - a teammate row with NO marker at all               -> skip, unmarked (never a first
#                                                          verdict from this event)
#
# THE Files: RECONCILIATION (S18, AC-22) rides the same per-candidate loop, once per row, on
# a "verdict" candidate only — a recheck never speaks (belt-on-belt with "supersession never
# speaks" above) and a row with no `deliverable=` never becomes a candidate at all, so it is
# out of reach of this check too, on the same "declares nothing" reasoning the deliverable
# checks already use:
#   - the row's `files=` is empty (a Suites:-only brief,
#     or a row that predates the wall)                    -> not reconciled, silent, pass
#   - the row's worktree cannot be located or is gone,
#     or its branch has no merge-base with the main
#     checkout's current branch                            -> not reconciled, silent (ambiguity)
#   - the diff has no path outside the declared `files=`   -> pass, silent
#   - the diff touches a path outside the declared
#     `files=`                                              -> REFUSE, naming the file(s) and
#                                                          (impact-command configured) the
#                                                          suites `impact` derives for them
#
# Exit code 2 = block the stop in Claude Code hooks; stderr goes back to the orchestrator,
# which is why the refusal must name the row and its artifacts rather than the rule.
# [WALL: tests/landing-gate.test.sh]
#
# Registered on both channels: hooks/hooks.json (agent contexts, behind agent-context-guard.sh) and skills/canonical-sdlc/SKILL.md frontmatter (main thread).
#
# hooks/landing-gate.sh's body — the ONE function of the four with a SubagentStop
# arm. Its `case "$EVENT"` is carried over unchanged; what changed is where the
# event comes from (an argument, not a payload read).

stop_landing_gate() {  # <event> -> 0 nothing · 1 advisory · 2 block
  local _ev="${1:-}" _adv=0
  local EVENT MODE STOP_AGENT_ID STOP_AGENT_NAME LIVE_IDS ROSTER_FILE SWEEPER
  local CANDIDATES LINE REFUSALS REFUSE_KIND NOW AID NAME KIND CFILES
  local VERDICT VERDICT_RC STATE
  local LG_IMPACT_BOUND_S LG_IMPACT_TICKS_LEFT LG_WT LG_MAIN_BRANCH LG_BASE LG_WHY
  local LG_OUTSIDE LG_DF LG_IMPACT_CMD LG_SUITES LG_SUITES_NOTE LG_IMPACT_TMP
  local LG_IMPACT_PID LG_TICKS LG_OVERRAN

# ---------- relevance first: the cheapest checks, before any git resolution ----------

# TWO EVENTS, TWO ARMS, ONE ROSTER SPLIT BETWEEN THEM. `Stop` is the sweep (below);
# `SubagentStop` is the teammate landing verdict, and it arrives on the settings channel
# behind hooks/agent-context-guard.sh because no subagent-context event reaches the skill
# frontmatter at all. An absent field is not treated as a mismatch, so a hand-run payload
# still sweeps.
EVENT="$_ev"
case "$EVENT" in
  ""|Stop)      MODE=sweep ;;
  SubagentStop) MODE=landing ;;
  *)            return "$_adv" ;;
esac

# Read on BOTH paths, so neither is a variable bound on only some of them (`set -u`), and
# read here rather than at the join so the shape checks sit beside every other one.
STOP_AGENT_ID=""
STOP_AGENT_NAME=""
LIVE_IDS=""

if [ "$MODE" = "sweep" ]; then
  # THE LIVE SET, and the whole of the landed/live discrimination. Its ABSENCE is not an empty
  # set: an empty array means every dispatch has finished (the payload says so on every turn
  # where nothing is running), while a missing key means this is not a payload that can tell
  # us, and judging on it would hold running agents to contracts they are still working on.
  [ "$(printf '%s' "$BIONIC_INPUT" | jq -r 'if has("background_tasks") then "yes" else empty end' 2>/dev/null)" = "yes" ] || return "$_adv"
  LIVE_IDS="|$(printf '%s' "$BIONIC_INPUT" \
    | jq -r '[.background_tasks[]?.id // empty] | join("|")' 2>/dev/null | tr -d '\n')|"
else
  # THE LANDING ARM READS NO LIVE SET, and that is the point of it rather than an omission.
  # This payload carries `background_tasks[]` too, and the stopping teammate is STILL IN IT —
  # measured `status:"running"` on the last Stop of the session, 2 m 41 s after its own
  # SubagentStop, because an in-process teammate stays addressable until the session ends
  # (t1-probe-report.md §2.3). Landing-by-disappearance is a subagent-only signal; here the
  # EVENT is the landing, delivered with the id, the name and the moment in one payload.
  STOP_AGENT_ID=$(bionic_jq .agent_id)
  [ -n "$STOP_AGENT_ID" ] || return "$_adv"
  # SHAPE-CHECKED BEFORE IT BECOMES A FIELD, on the same reasoning the session key gets: this
  # value is written into a `landing-swept/v1|…|agent_id=` marker line, and a `|` or a newline
  # in it would forge a field or a whole row on the roster. The transcript form is
  # `a<name>-<16 hex>` and names are alphanumeric, so this silences nothing real.
  case "$STOP_AGENT_ID" in *[!A-Za-z0-9_.@-]*) return "$_adv" ;; esac
  # The NAME, for the fallback join, and only if it is shaped like one. `agent_type` carries
  # the dispatch name for a teammate and the subagent type for an async dispatch (t1 §2.1);
  # the harness's own phantom agents send it empty. An unusable value drops the fallback
  # rather than the whole arm — the id join above may still place the row.
  STOP_AGENT_NAME=$(bionic_jq .agent_type)
  case "$STOP_AGENT_NAME" in *[!A-Za-z0-9_-]*) STOP_AGENT_NAME="" ;; esac
fi
[ -d "$BIONIC_ROOT" ] || return "$_adv"

# ---------- THE ENGAGEMENT SWITCH — asked before anything else ----------
#
# task-engaged-session: bionic's walls are the RUN's, not the repo's, and a run is entered
# by invoking canonical-sdlc. A session that never did is a bystander here and must not see
# a refusal, an advisory, or a state write from this hook. `engaged_session` (lib/run.sh) is
# true only for a REGULAR file at `.bionic/tmp/engaged-<sid>.state`; every unreadable state —
# absent, symlink, foreign sid, `unknown` — reads as NOT engaged. Silent, return "$_adv": the
# direction §7 gives every start-side ambiguity, and here it is the consent boundary itself
# (1.3.2 close-out ruling — the arming partition IS the consent boundary).
[ "$BIONIC_ENGAGED" = 1 ] || return "$_adv"

ROSTER_FILE="$BIONIC_ROOT/.bionic/tmp/roster-${BIONIC_SID}.state"
# Existence first, so a session that has dispatched nothing costs one stat. The symlink
# guard is the write half of TDD §8: a repo controls its own .bionic/, and a link at any
# level redirects this script's marker append outside the repo.
[ -e "$ROSTER_FILE" ] || return "$_adv"
[ -L "$BIONIC_ROOT/.bionic" ] && return "$_adv"
[ -L "$BIONIC_ROOT/.bionic/tmp" ] && return "$_adv"
[ -L "$ROSTER_FILE" ] && return "$_adv"

# ---------- THE RUN PREDICATE IS GONE — ENGAGEMENT SCOPES THIS HOOK (task-engaged-session) --
#
# It used to take the run predicate here — `PLAN=$(active_run <repo>)`, return "$_adv" on false —
# and nothing below ever consulted
# the value: the contract this gate enforces is a roster row this
# session's own dispatch wall wrote, and the verdict is hooks/session-sweeper.sh's.
# The plan answered WHETHER, which is now engagement's question and is answered above.
#
# WHY THIS HOOK MOVES WITH THE DISPATCH WALL RATHER THAN KEEPING A RUN GATE. The four
# members of the roster lifecycle — hooks/dispatch-preflight.sh writes an `intended` row,
# this family confirms it, the landing gate takes its verdict, the stop gate polices the
# stop — have to share one scope or the lifecycle splits: the dispatch wall runs for an
# engaged session with no plan yet (AC-23, a fresh run's Step 0 precedes its plan), and a
# recorder or a gate that stayed silent for want of a plan would leave rows nothing ever
# answers for. A landing contract also OUTLIVES the run that created it — engagement does
# not end when `current:` reaches 9 (plan §Lifecycle) — and a verdict owed on an agent this
# session launched is owed after the run closes too.

# ---------- this session is engaged: sweep ----------

# The sweeper is this script's SIBLING — the payload ships every hooks/*.sh in one
# directory, so the same resolution holds in the repo and under the mounted plugin's
# hooks/ that hooks/hooks.json roots at ${CLAUDE_PLUGIN_ROOT}. No PATH
# lookup (a hook's PATH is not ours to trust) and no environment override (a seam on the
# path under test would leave the production path unverified).
SWEEPER="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/session-sweeper.sh"
[ -f "$SWEEPER" ] || return "$_adv"

# ONE PASS OVER THE ROSTER, and it is the only cost this script pays on a turn where nothing
# landed. The fold rule is hooks/session-sweeper.sh's own (`latest_rows`), because the verb
# is what will be asked and a reader that folded differently would ask about a row the verb
# never answers for: rows of THIS session only, keyed by name, FIRST field of a key wins
# within a row, latest row wins across them, an empty name folds to `(unnamed)`.
#
# `agent_id` is taken from the latest row that CARRIES one rather than from the latest row
# outright. The field starts empty on the `intended` row the dispatch wall writes and is
# filled by hooks/execution-recorder.sh at confirmation; it never goes back to empty, so
# this is monotone rather than a preference, and it keeps a row joinable if a future writer
# ever appends without copying it forward.
#
# The output is TAB-delimited `<agent_id> <name> <kind>`, one line per unswept, joinable,
# contract-bearing row. A tab cannot appear inside a field — every writer on this roster runs
# its values through a sanitizer that turns one into a space — and the name is folded the
# same way the verb folds it. `kind` is `verdict` for a row being answered for the first (and
# only) time, and `recheck` for the supersession arm below, which is the one caller that may
# write a SECOND marker for a row and the one that never refuses.
CANDIDATES=$(awk -v pfx="roster-state/${ROSTER_VERSION}|" -v spfx="${SWEPT_SCHEMA}|" -v sid="$BIONIC_SID" \
                 -v mode="$MODE" -v pid="$STOP_AGENT_ID" -v atype="$STOP_AGENT_NAME" '
  index($0, spfx) == 1 {
    nf = split($0, f, "|"); a = ""; mn = ""; ms = ""
    for (i = 1; i <= nf; i++) {
      if (a  == "" && substr(f[i], 1,  9) == "agent_id=") a  = substr(f[i], 10)
      if (mn == "" && substr(f[i], 1,  5) == "name=")     mn = substr(f[i], 6)
      if (ms == "" && substr(f[i], 1,  6) == "state=")    ms = substr(f[i], 7)
    }
    if (a != "") swept[a] = 1
    # THE LATEST ANSWER, PER ROW, and latest means LAST IN THE FILE: this is an append-only
    # journal, so file order is chronological and an unconditional assignment leaves the most
    # recent marker standing. The recheck arm below reads exactly these two facts — what the
    # last answer said, and which id it was keyed by — and asks for nothing the marker does
    # not already carry.
    if (mn != "") { mstate[mn] = ms; if (a != "") magent[mn] = a }
    next
  }
  index($0, pfx) != 1 { next }
  {
    name = ""; rsession = ""; aid = ""; deliv = ""; tid = ""; fls = ""
    nf = split($0, f, "|")
    for (i = 1; i <= nf; i++) {
      if (name == ""     && substr(f[i], 1, 5)  == "name=")        name     = substr(f[i], 6)
      if (rsession == "" && substr(f[i], 1, 8)  == "session=")     rsession = substr(f[i], 9)
      if (aid == ""      && substr(f[i], 1, 9)  == "agent_id=")    aid      = substr(f[i], 10)
      if (deliv == ""    && substr(f[i], 1, 12) == "deliverable=") deliv    = substr(f[i], 13)
      if (tid == ""      && substr(f[i], 1, 12) == "teammate_id=") tid      = substr(f[i], 13)
      if (fls == ""      && substr(f[i], 1, 6)  == "files=")       fls      = substr(f[i], 7)
    }
    # The roster file is already per-session; this only fires on a hand-edited or copied
    # file, and it costs one comparison to keep the sweep honest about whose promises it is
    # answering for.
    if (rsession != "" && rsession != sid) next
    if (name == "") name = "(unnamed)"
    gsub(/\t/, " ", name)
    if (!(name in seen)) { seen[name] = 1; order[++n] = name }
    if (aid != "") agent[name] = aid
    # `teammate_id` is monotone the way `agent_id` is — the launch wall never writes it and
    # the completion arm fills it once — so the latest row that CARRIES one wins, and a row
    # appended without copying it forward cannot un-teammate a contract.
    if (tid != "") tm[name] = tid
    dl[name] = deliv
    # `files=` (S18, AC-22) is read the same way `deliverable=` is: the LATEST row value,
    # whatever it is. Post-S13 every row dispatch-preflight writes carries the key (empty
    # string for a Suites:-only brief); a pre-S13 row carries no key at all and parses to the
    # same empty value either way, so one predicate downstream (non-empty or not) covers both.
    # (No apostrophes in this paragraph: it lives inside a single-quoted awk program.)
    gsub(/\t/, " ", fls)
    fl[name] = fls
  }
  END {
    # ---------- the landing arm: ONE row, the one that just stopped ----------
    if (mode == "landing") {
      nm = ""
      # BY ID FIRST. The transcript form is filled onto the row by the recorder at
      # SubagentStart, and it is the same string this payload carries — the strongest key
      # available, and the one that survives two dispatches sharing a name.
      for (i = 1; i <= n; i++) {
        k = order[i]
        if (tm[k] == "") continue
        if ((k in agent) && agent[k] != "" && agent[k] == pid) nm = k
      }
      # BY NAME SECOND, and only over teammate rows. For a teammate `agent_type` carries the
      # dispatch name; for an async dispatch it carries the subagent type, which names no row
      # and is the join wave-03 removed for cause. The scope reads the statement the row
      # writer made about dispatch mode, never a guess at the shape of an id.
      if (nm == "" && atype != "" && (atype in seen) && tm[atype] != "") nm = atype
      # A stop we cannot place is not ours to answer for: the harness sends its own internal
      # agents through this event, and their ids are on no row of ours.
      if (nm == "") exit
      if (dl[nm] == "") exit                # declares nothing; MET vacuously either way
      a = ((nm in agent) && agent[nm] != "") ? agent[nm] : pid
      if (a == "") exit
      # Both keys, because the marker may have been written under either: the row id when the
      # identification arm ran, the payload id when it did not.
      if ((a in swept) || (pid in swept)) exit
      printf "%s\t%s\t%s\t%s\n", a, nm, "verdict", fl[nm]
      exit
    }

    # ---------- the sweep: every row the payload says has landed ----------
    for (i = 1; i <= n; i++) {
      nm = order[i]
      # TEAMMATES BELONG TO THE OTHER ARM, and this skip is load-bearing rather than tidy.
      # A teammate is keyed in `background_tasks[]` under a namespace its `agent_id` is not
      # in, and it NEVER LEAVES that array anyway (t1 §2.3) — so the moment the recorder
      # fills the row id, the landed/live predicate here reads every teammate as landed on
      # the first Stop after dispatch, 2.8 s in, and refuses a contract the agent is still
      # working on. The sweep judges what it can place; the SubagentStop arm judges the rest.
      #
      # ONE EXCEPTION, AND IT IS NOT A VERDICT (session-20260815-landing-cleanup T3, AC-5).
      # A teammate refused at SubagentStop is told so INSIDE its own sidechain, at the one
      # moment it can still act — and it does: measured live, the refused teammate read the
      # feedback and wrote the promised artifact, while the roster still said UNMET when the
      # session ended (live-verify.md B2). The refusal was right and its record was a lie
      # about the world. So a teammate row whose LATEST marker says UNMET, and whose
      # contracted deliverable the verb now finds, gets a SUPERSEDING marker appended: the
      # stream carries history plus current state, nothing is rewritten, and the block-once
      # promise is untouched because a supersession never speaks. The Stop cadence is the
      # clock; no timer is added for it.
      #
      # NEVER A FIRST VERDICT. A teammate row with no marker at all is left exactly where the
      # skip above leaves it, delivered or not — the sweep cannot tell a working teammate
      # from a finished one, and answering here is the 2.8-second false refusal this whole
      # partition exists to prevent. The recheck can only ever change an answer that the
      # SubagentStop arm already gave.
      if (tm[nm] != "") {
        if (!(nm in mstate)) continue       # unanswered: not this arm to answer
        if (mstate[nm] != "UNMET") continue # the current answer is no failure; nothing to supersede
        if (dl[nm] == "") continue          # declares nothing; MET vacuously either way
        ra = ""
        # The id off the MARKER first, and the row only as a fallback: in teammate mode a row
        # carries no `agent_id=` at all (the addressing form lives in `teammate_id=`), and the
        # marker was keyed by the transcript form off the stopping payload. Superseding under
        # a different key would leave two markers no reader could tell were about one answer.
        if ((nm in magent) && magent[nm] != "") ra = magent[nm]
        # UNREACHABLE, AND THE REASON IS NO LONGER "ONE WRITER". Two files append
        # `landing-swept/v1` lines: this one ORIGINATES them (below, off `$SWEPT_SCHEMA`),
        # and the `adopt_copy_marker` in hooks/session-poker.sh COPIES one verbatim onto the
        # successor roster when a session adopts a predecessor row — it never computes a
        # verdict, so every marker in the fleet still carries the `agent_id=` that the
        # write path below refuses to append without. That, not the writer count, is
        # what keeps `magent[nm]` populated whenever `mstate[nm]` exists.
        #
        # THE GREP THIS USED TO CITE WAS A GUARANTEED FALSE NEGATIVE: `grep -rn SWEPT_SCHEMA
        # hooks/*.sh` still returns only this file, because the poker spells the schema as a
        # literal rather than through the constant. The grep that finds both writers is
        # `grep -rn landing-swept/v1 hooks/*.sh`.
        # Kept as belt-on-belt against a future writer that COMPUTES rather than copies.
        # (No apostrophes in this paragraph: it lives inside a single-quoted awk program.)
        else if ((nm in agent) && agent[nm] != "") ra = agent[nm]
        if (ra == "") continue
        printf "%s\t%s\t%s\n", ra, nm, "recheck"
        continue
      }
      if (!(nm in agent)) continue          # never confirmed: cannot be placed
      if (dl[nm] == "") continue            # declares nothing; MET vacuously either way
      if (agent[nm] in swept) continue      # already answered for, once and for all
      printf "%s\t%s\t%s\t%s\n", agent[nm], nm, "verdict", fl[nm]
    }
  }
' "$ROSTER_FILE" 2>/dev/null)

[ -n "$CANDIDATES" ] || return "$_adv"

LINE=""
_field() {  # <key> — by key, never by position, as every reader of these lines does
  printf '%s' "$LINE" | tr '|' '\n' | grep "^$1=" | head -1 | cut -d= -f2-
}

REFUSALS=""
# WHICH FACT THE ONE LINE CARRIES when a sweep finds both kinds (task 13, table rows
# 107 and 108). The gate accumulates a paragraph per failing row and prints them all;
# ruling D-1 gives the reader ONE line, so the FIRST kind found names it and every
# accumulated paragraph rides `detail`. The alternative — a third, summarising fact —
# would be user-facing text the ruled table does not carry.
REFUSE_KIND=""

# ONE DERIVATION BUDGET FOR THE WHOLE SWEEP (review-c C-17). The impact command below is
# the same call hooks/dispatch-preflight.sh makes and costs the same ~2.6-6.5 s, but it
# sits inside this per-candidate loop, and this hook is registered at "timeout": 10 on both
# Stop and SubagentStop. N offending rows would pay N x that. So the budget is spent across
# the loop rather than granted per row: whatever is left when a row asks, and nothing once
# it is gone. A row that gets no derivation still REFUSES — it names its files and says the
# suites were not derived. The one thing this must never become is a silent pass.
#
# BUILT, NOT BORROWED, for the same reason as the dispatch site: bionic's command discipline
# forbids a `timeout`/`gtimeout` binary and macOS ships neither.
LG_IMPACT_BOUND_S=6
LG_IMPACT_TICKS_LEFT=60          # 60 x 0.1s, shared by every candidate in this sweep
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

while IFS=$'\t' read -r AID NAME KIND CFILES; do
  [ -n "$AID" ] && [ -n "$NAME" ] || continue
  # STILL IN FLIGHT — the payload says so, and an agent that is visibly still working has
  # not failed to land. No verdict, and no marker: its one answer is still owed.
  case "$LIVE_IDS" in *"|$AID|"*) continue ;; esac

  # Run from the repo, because the sweeper resolves its own state directory from the working
  # directory, and with the payload's session key. `|| exit 9` keeps a failed `cd` out of the
  # exit-1 band: exit 1 is the verb's "at least one UNMET row", and nothing else may be
  # allowed to spell it.
  VERDICT=$( cd "$BIONIC_ROOT" 2>/dev/null || exit 9
             CLAUDE_CODE_SESSION_ID="$BIONIC_SID" bash "$SWEEPER" verdict "$NAME" 2>/dev/null )
  VERDICT_RC=$?

  # AN ANSWER WE DID NOT GET IS NOT AN ANSWER. Exit 2 is a refusal (the verb was redirected
  # away from the roster and says so), 3 is no session key, anything else is an error — and
  # none of them may mark a row closed, because the row has not been judged.
  case "$VERDICT_RC" in 0|1) : ;; *) continue ;; esac

  # THE LINE THE SCOPED VERB RETURNED, and no second lookup by name. `verdict <name>`
  # answers for that name alone and folds the roster to one row per name, so its output
  # carries at most one machine line and taking the first IS taking this contract's.
  LINE=$(printf '%s\n' "$VERDICT" | grep -F 'landing-verdict/v1|' | head -1)
  [ -n "$LINE" ] || continue

  STATE=$(_field state)

  # A RECHECK SPENDS A MARKER ONLY ON A CHANGED ANSWER. The row already has one saying UNMET;
  # a second saying the same thing records nothing and would be appended on every turn end
  # for the rest of the session — the marker-spam shape. Only MET supersedes: STILL-LIVE,
  # WAIVED and AMBIGUOUS are not the recovery this arm exists to record, and UNMET is the
  # answer already standing.
  if [ "$KIND" = "recheck" ] && [ "$STATE" != "MET" ]; then
    continue
  fi

  # APPENDED HERE, PER ROW, THE MOMENT ITS VERDICT IS DECIDED — not accumulated across the
  # whole loop and written once at the end (t6-review.md F-2, measured: a sweep killed 5s
  # into a 200-candidate run, ~60 already verdicted, banked ZERO marks under the old single
  # trailing append). This is the same lock-free discipline the trailing append relied on —
  # one line, well under a pipe buffer, O_APPEND — just paid once per row instead of once
  # per sweep, so a sweep killed mid-loop still banks every verdict already decided.
  #
  # THE ONE WRITER (S15, AC-26): `swept_marker_write`, defined above, owns this printf;
  # hooks/session-poker.sh's `adopt_copy_marker` never re-spells it.
  swept_marker_write "$ROSTER_FILE" "$NOW" "$BIONIC_SID" "$NAME" "$AID" "$STATE"

  # AND A SUPERSESSION NEVER SPEAKS. Its marker is MET by construction, so nothing below
  # would fire anyway — but the reason it must not is stronger than the arithmetic: the row
  # has already been refused once, the agent has already acted on that refusal, and the whole
  # promise of this gate is that it blocks once. Recording the recovery is the entire job.
  [ "$KIND" = "recheck" ] && continue

  # ---------------------------------------------------------- Files: RECONCILIATION (S18, AC-22)
  #
  # INDEPENDENT OF THE DELIVERABLE VERDICT ABOVE, and run exactly once — this row reaches
  # this line only as a first-time "verdict" candidate (recheck already continued above,
  # and a row with no `deliverable=` never became a candidate at all — see the awk END
  # block's own "declares nothing" skips, which this check inherits rather than re-states).
  if [ -n "$CFILES" ]; then
    LG_WT=$(_lg_worktree_for_name "$BIONIC_ROOT" "$NAME")
    if [ -n "$LG_WT" ] && [ -d "$LG_WT" ]; then
      # THE BASE IS THE MERGE-BASE WITH THE MAIN CHECKOUT'S CURRENT BRANCH, recomputed here
      # rather than read off a stored value: no roster field records the sha a worktree
      # spawned from, and `worktree.sh`'s own `land` verb does not need one either — it
      # counts commits `HEAD..branch` from the main checkout. A merge-base is exactly
      # "everything this branch has added since it diverged", which is what a `Files:`
      # declaration is a promise ABOUT, and recomputing it survives the ordinary case where
      # the main branch has moved on since the tree was spawned — a stored base sha would not.
      LG_MAIN_BRANCH=$(git -C "$BIONIC_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
      LG_BASE=""
      # A DETACHED MAIN CHECKOUT IS NOT A BRANCH NAME (review-a A-5). `rev-parse
      # --abbrev-ref HEAD` prints the literal string `HEAD` there, and `HEAD` resolves
      # INSIDE the worktree to the worktree's own tip — so the merge-base comes back
      # non-empty, the diff comes back EMPTY, and every landing reconciles clean with no
      # refusal and no diagnostic. `git bisect`, `git checkout <tag>` and a checkout parked
      # on a sha are all ordinary states for this repository during an integration.
      case "$LG_MAIN_BRANCH" in HEAD) LG_MAIN_BRANCH="" ;; esac
      [ -n "$LG_MAIN_BRANCH" ] && LG_BASE=$(git -C "$LG_WT" merge-base "$LG_MAIN_BRANCH" HEAD 2>/dev/null)
      if [ -z "$LG_BASE" ]; then
        # ANNOUNCED INERT, the standard tests/run.sh:267-272 sets for the adoption wall:
        # "a wall that is off and quiet is indistinguishable from a wall that is passing
        # everything". Unrelated histories, a worktree with no commits and any other
        # merge-base failure land here too, and each says so rather than passing silently.
        if [ -z "$LG_MAIN_BRANCH" ]; then
          LG_WHY="the main checkout is on no branch (detached HEAD), so there is no branch to take a merge-base from"
        else
          LG_WHY="no merge-base between ${LG_MAIN_BRANCH} and this tree"
        fi
        fold_advise "landing-gate: ${LG_WHY} — the Files: reconciliation is INERT for row ${NAME}; its diff was NOT checked against '${CFILES}'"; _adv=1
      fi
      if [ -n "$LG_BASE" ]; then
        LG_OUTSIDE=""
        while IFS= read -r LG_DF; do
          [ -n "$LG_DF" ] || continue
          _lg_path_declared "$LG_DF" "$CFILES" && continue
          LG_OUTSIDE="${LG_OUTSIDE}${LG_OUTSIDE:+ }${LG_DF}"
        done <<LGDIFF
$(git -C "$LG_WT" diff --name-only "${LG_BASE}..HEAD" 2>/dev/null)
LGDIFF
        if [ -n "$LG_OUTSIDE" ]; then
          # THE SAME COMMAND, THE SAME CONFIG KEY hooks/dispatch-preflight.sh reads (S13),
          # re-asked of the offending files alone (spec AC-22: "naming the files and the
          # suites they imply"). Absent command -> name the files only, exactly as the
          # dispatch wall itself falls back when nothing is configured.
          LG_IMPACT_CMD=$(config_value "$BIONIC_ROOT" "impact-command" "")
          LG_SUITES=""
          LG_SUITES_NOTE=""
          if [ -n "$LG_IMPACT_CMD" ]; then
            if [ "$LG_IMPACT_TICKS_LEFT" -le 0 ]; then
              LG_SUITES_NOTE=" (this sweep's ${LG_IMPACT_BOUND_S}s derivation budget was spent on earlier rows, so the suites these files imply are NOT named here — derive them by hand)"
            else
              LG_IMPACT_TMP="${TMPDIR:-/tmp}/bionic-lg-impact-$$-${RANDOM}.out"
              # `set -f` AROUND THE SPLIT (review-a A-11). `$LG_OUTSIDE` is built from `git
              # diff --name-only`, and a committed path carrying `*`, `?` or `[` would
              # otherwise be pathname-expanded against $BIONIC_ROOT and hand the command files
              # that were never in the diff. The dispatch site guards the identical
              # construction; this one did not.
              set -f
              # shellcheck disable=SC2086  # the COMMAND is configuration and is meant to split
              ( cd "$BIONIC_ROOT" 2>/dev/null && $LG_IMPACT_CMD $LG_OUTSIDE >"$LG_IMPACT_TMP" 2>/dev/null ) &
              LG_IMPACT_PID=$!
              set +f
              LG_TICKS=0
              LG_OVERRAN=0
              while kill -0 "$LG_IMPACT_PID" 2>/dev/null; do
                if [ "$LG_TICKS" -ge "$LG_IMPACT_TICKS_LEFT" ]; then
                  kill -TERM "$LG_IMPACT_PID" 2>/dev/null
                  LG_OVERRAN=1
                  break
                fi
                sleep 0.1
                LG_TICKS=$((LG_TICKS + 1))
              done
              wait "$LG_IMPACT_PID" 2>/dev/null
              LG_IMPACT_TICKS_LEFT=$((LG_IMPACT_TICKS_LEFT - LG_TICKS))
              if [ "$LG_OVERRAN" -eq 1 ]; then
                LG_SUITES_NOTE=" (the impact command did not answer within this sweep's ${LG_IMPACT_BOUND_S}s derivation budget, so the suites these files imply are NOT named here — derive them by hand)"
              else
                LG_SUITES=$(awk -F'\t' '$1 != "" { print $1 }' "$LG_IMPACT_TMP" 2>/dev/null | sort -u | tr '\n' ' ')
                LG_SUITES="${LG_SUITES% }"
              fi
              rm -f "$LG_IMPACT_TMP"
            fi
          fi
          [ -n "$REFUSE_KIND" ] || REFUSE_KIND=undeclared
  REFUSALS="${REFUSALS}LANDING DIFF OUTSIDE Files: — ${NAME} touched: ${LG_OUTSIDE}${LG_SUITES:+ (suites: ${LG_SUITES})}${LG_SUITES_NOTE} — not declared. Add the file(s) to Files: and re-derive, or revert them before landing.
"
        fi
      fi
    fi
  fi
  # A Suites:-only brief (AC-20's other half), or a pre-S13 row, declared no Files: at all,
  # so there is no declared set to reconcile the diff against. SILENT, on the same footing
  # as every other "cannot judge this" path in this file: this is the ordinary case for most
  # of the fleet today (Files: is the newer of AC-20's two labels), and a stderr line on
  # every such landing would turn the common case into noise on every turn end — the exact
  # false-alarm shape the rest of this gate exists to end. The disposition is documented
  # once, above, in the FAIL DIRECTIONS table; it is not re-announced per row.

  [ "$VERDICT_RC" -eq 1 ] || continue
  [ "$STATE" = "UNMET" ] || continue

  # AN ACKED ROW IS CLOSED FOR EVERY READER (epic-16 wave-02 task S3, R2). The orchestrator
  # verified this agent's completion and made that durable; reporting it again over artifacts
  # a human has already accounted for is the false alarm this wave exists to end. Read off
  # the verdict line, which is where the one reader of that ledger publishes it (S9).
  [ "$(_field acked)" = "yes" ] && continue

  # The refusal is the verb's own detail, unedited, prefixed by the row it is about. It names
  # every failing conjunct — `missing=`, `empty=`, `stale=` with both stamps — because a
  # reader told only "unmet" has nothing to act on. The ROW NAME is what the sweep adds and
  # the per-agent gate did not need: a sweep answers about contracts rather than about
  # whoever is stopping, so without it the reader cannot tell which dispatch to chase.
  [ -n "$REFUSE_KIND" ] || REFUSE_KIND=unmet
  REFUSALS="${REFUSALS}LANDING CONTRACT UNMET — ${NAME}: $(_field detail). Land the contract (write the named artifacts), or stop again to pass — this gate blocks once.
"
done <<EOF
$CANDIDATES
EOF

[ -n "$REFUSALS" ] || return "$_adv"
case "$REFUSE_KIND" in
  undeclared) fold_block exit2 stop "this branch touched undeclared files" "declare them, or revert them" "$REFUSALS" ;;
  *)          fold_block exit2 stop "a dispatched agent's contract is unmet" "write the named artifacts" "$REFUSALS" ;;
esac
return 2
}


# ─── stop_patrol_duties ───
#
# THE HOOK'S OWN HEADER, CARRIED OVER WHOLE. It is the design record for this
# verdict — every ruling, incident and measurement that shaped it — and it
# travels with the code rather than being left behind in a deleted file.
# Where it says "this hook" it now means this function, and where it names a
# registration it means hooks/stop.sh's.
#
# THE PATROL-DUTIES WALL — task-dispatch-wall-channel-loss, T5.
#
# Stop. On every orchestrator turn end: if the turn was started by a PATROL TICK,
# refuse the stop once unless the tick's THREE standing duties were performed
# inside it — a subagent-panel refresh (`ListAgents`), a task-list refresh
# (`TaskList`, or a write naming the active plan file), and an ANSWER to any
# `poker: FILL` line the tick printed (the named dispatches, or an explicit
# `fill-declined: <reason>`). Any other turn passes untouched, as does any
# ambiguity along the way.
#
# WHY A WALL AND NOT BETTER WORDING. The duties live in the Patrol prompt today,
# and a prompt is text: it asks. Every rule in this repo that actually binds is a
# wall (memory/rules-are-walls-not-wishes), and the only event that can express
# "this must have happened before the turn ends" is the turn's END. A PreToolUse
# arm cannot say it — at the moment any single tool runs, the turn is not over
# and nothing has been skipped yet. So the predicate is retrospective by
# construction, and Stop is the one channel that can ask it.
#
# WHY ALWAYS-ON, AND WHAT SCOPES IT INSTEAD. This gate was registered in the governing
# skill's frontmatter so that it would be live exactly while that skill was — the duty
# it binds is the skill's own Patrol's. That coupling was the defect, not the design:
# a skill's registrations are looked up per session, so a `/clear`, a compaction or a
# session the skill was never invoked in left the wall installed, green in its own
# suite, and not running. The duty did not stop existing in those sessions; only the
# wall did.
#
# It is registered once in hooks/hooks.json now, on `Stop` — which still fires once per
# orchestrator turn and keeps firing on turns nothing was re-invoked. What scopes it is
# an ON-DISK fact: `session_run` (which was `active_run` until wave-session-bound-run made
# run identity per-session) under the payload's project root. A run is active while
# its plan says so, and that is the same fact that says a Patrol should be ticking.
#
# WHAT A "PATROL TICK" IS, STRUCTURALLY. The tick prompt is composed per session
# by a model and its wording is therefore not a fact anything may key on. What IS
# a fact is the command SKILL.md's Dispatch section makes the first of the
# prompt's reads: `session-poker.sh tick`. That literal in the turn's opening
# user message is the marker — the same structural-not-textual identification
# payload/scripts/lib/patrol.sh uses to recognise a Patrol cron job (T2 judgment
# call (b)), reached independently and agreeing.
#
# WHAT COUNTS, AND WHEN. Only AFTER the tick's own prompt: duties performed in
# some earlier turn are stale by exactly the interval the tick exists to cover.
# Only on the MAIN THREAD: a tool_use inside an agent context (`isSidechain`, or
# a non-empty agent key) belongs to a subagent, and a subagent's ListAgents did
# not refresh the orchestrator's panel — the mirror image of the exclusion
# hooks/session-poker.sh:399-406 makes for the same reason.
#
# THE TASK-LIST FALLBACK IS NOT A CONVENIENCE. The task tools are absent from
# some model/CLI combinations (memory/task-tools-tengu-gate: removed for fable-5
# in CLI 2.1.228–2.1.233), and in those sessions the plan's own ledger IS the
# task list. A wall that demanded `TaskList` there would be unsatisfiable, which
# is the one failure mode a blocking gate must not have. So an Edit/Write/
# NotebookEdit/Bash tool_use whose input names the active plan file discharges
# the same duty.
#
# A SECOND ARM, ADDED FOR bionic 1.4.0 (spec AC-3, plan task STOPGATES). A `/clear`
# rewrites the session id in place but does not kill a predecessor's cron job — it
# survives and keeps firing into the new conversation (probe A-probe-4). The new
# transcript's very first turn is the literal `<command-name>/clear</command-name>`
# (record/wave-1.4.0-probe.md); a resume is announced the same way, by the literal
# substring `source: resume` this gate's SessionStart sibling
# (hooks/session-start.sh) prints into the title line of its own report, which the
# model reads as context. Either is "a transcript record whose content contains" the
# marker — read as RAW TEXT, not one JSON shape, so this arm does not care whether
# the marker lands on a user prompt, a system entry, or anything else. It does care
# WHO WROTE THE ROW: a `tool_result` is how the content of every file the agent reads
# enters the transcript, and a file is not the CLI announcing a resume, so the marker
# is read off the orchestrator's own rows only (review F2, see $auth below).
#
# THE RULE: since the MOST RECENT such marker, a `CronCreate` tool_use must be
# preceded by a `CronList` tool_use, or the turn refuses — creating a job before
# listing and deleting the stray one leaves two clocks on one project (S5, the
# resume ritual). The scan resets at every marker, so only the ritual for the
# LATEST clear/resume is judged; a Cron call before the marker is not "since" it.
# Agent-context tool_uses are excluded, the same exclusion the tick-duties arm
# already makes, for the same reason. BLOCKS ONCE: this reuses the exact
# `stop_hook_active` mechanism above, unchanged — no new bookkeeping for it.
#
# FAIL DIRECTIONS (pinned by tests/patrol-duties-gate.test.sh):
#   - jq absent                                          -> pass, silent
#   - not a Stop payload (SubagentStop included)          -> pass, silent
#   - stop_hook_active true                               -> pass, silent (blocks ONCE)
#   - no cwd, or it is not a directory                    -> pass, silent
#   - no transcript_path, or no file there, or a symlink  -> pass, silent
#   - a marker older than the scan window (2000 records)  -> pass, silent (fail-open, below)
#   - no user prompt in the transcript at all             -> pass, silent
#   - the last user prompt is not a Patrol tick           -> pass, silent
#   - both duties done since that prompt                  -> pass, silent
#   - either duty missing                                 -> REFUSE, naming which
#   - no `poker: FILL` line in the turn                   -> pass, silent (fill arm inert)
#   - every named task dispatched, or a decline present  -> pass, silent
#   - a named task neither dispatched nor declined       -> REFUSE, naming that task
#   - a marker or a decline read out of a TOOL RESULT      -> ignored (not the orchestrator's)
#   - no clear/resume marker anywhere in the transcript   -> pass, silent (ritual arm inert)
#   - CronList precedes any CronCreate since the marker   -> pass, silent (ritual arm inert)
#   - a CronCreate since the marker with no prior CronList-> REFUSE, naming the ritual
#
# TWO ACCEPTED LIMITS, both a false BLOCK rather than a false silence, and both
# cheap because the refusal is once-only (stop again and the turn ends). First,
# the Stop-time transcript "isn't guaranteed to include the final message ... on
# all versions" (hooks reference, Stop input), so a duty discharged as the very
# last act of the turn may not be on disk when this reads it. Second, a Patrol
# tick that legitimately has nothing to do still owes both duties under this
# gate — which is the contract SKILL.md states, not an accident of the read.
#
# AND THERE IS NO BACKSTOP ABOVE OURS. This used to cite the hooks reference —
# "Claude Code overrides the hook and ends the turn after 8 consecutive blocks"
# — as the net under both limits. It is not one, for the same reason the same
# claim was struck from hooks/patrol-revive.sh (critic C-2, epic-19 w1): this
# gate blocks ONCE PER TURN by design (`stop_hook_active` → pass, below), and
# blocks one per turn are never consecutive, so that override can never engage
# above a hook shaped like this one. What bounds the refusal is the thing
# the reason line already names — do the two duties and stop again — not a
# counter in the CLI.
#
# IT WRITES NOTHING AND DECIDES NOTHING ELSE. No state file, no roster append, no
# stamp: this is a gate, and gates may only read (TDD §3.2). It takes no view on
# whether the tick's WORK was right, only on whether the two duties happened.
#
# Registered once on the Stop channel in hooks/hooks.json, and scoped by ENGAGEMENT — this
# session having invoked canonical-sdlc — not by the repo merely holding an open plan
# (task-engaged-session). The plan still answers "which plan", never "whether".
# [WALL: tests/patrol-duties-gate.test.sh]
#
# hooks/patrol-duties-gate.sh's body. Stop only: a subagent has no Patrol duties,
# and a wall that refused its stop would hold a worker hostage to its
# orchestrator's obligations.

stop_patrol_duties() {  # <event> -> 0 nothing · 1 advisory · 2 block
  local _ev="${1:-}" _adv=0
  local TRANSCRIPT HOOK_DIR PLAN PLAN_NAME SCAN_WINDOW_LINES STREAM
  local RITUAL RITUAL_REASON TICK_MARK VERDICT FILL_MISSING FILL_REASON
  local FACT FIX REASON

  case "$_ev" in Stop) : ;; *) return 0 ;; esac

TRANSCRIPT=$(bionic_jq .transcript_path)
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && [ ! -L "$TRANSCRIPT" ] || return "$_adv"

# THIS SCRIPT'S OWN DIRECTORY, so the poker the ritual message names is the same
# file a model would actually run — resolved the way hooks/patrol-revive.sh
# resolves its sibling, never through PATH and never a placeholder.
HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -n "$HOOK_DIR" ] || HOOK_DIR="$(dirname "$0")"
# ---------- THE ENGAGEMENT SWITCH — asked before anything else ----------
#
# task-engaged-session: bionic's walls are the RUN's, not the repo's, and a run is entered
# by invoking canonical-sdlc. A session that never did is a bystander here and must not see
# a refusal, an advisory, or a state write from this hook. `engaged_session` (lib/run.sh) is
# true only for a REGULAR file at `.bionic/tmp/engaged-<sid>.state`; every unreadable state —
# absent, symlink, foreign sid, `unknown` — reads as NOT engaged. Silent, return "$_adv": the
# direction §7 gives every start-side ambiguity, and here it is the consent boundary itself
# (1.3.2 close-out ruling — the arming partition IS the consent boundary). It is also what
# ends this gate's largest cost on a bystander turn: the full-transcript jq pass below never
# starts.
[ "$BIONIC_ENGAGED" = 1 ] || return "$_adv"

# ---------- THE RUN PREDICATE (AC-7, AC-8) ----------
#
# Before the transcript is parsed, and that placement is the point. The full-transcript
# jq pass below is this hook's whole cost, and it used to run on every Stop in every
# session on the machine — 32.5ms with no transcript, 44.7ms over a 601-line one, scaling
# with the transcript, to answer a question that is only ever asked inside a run (R-2
# §(c)). Now a project with no open run pays one directory walk.
#
# It also answers "which plan" — the same reader, so this gate and the tick it polices
# cannot disagree about which file the duty is owed against.
#
# IT NO LONGER DECIDES WHETHER THIS GATE ACTS — engagement does (above). Both of this
# gate's duties are owed to a TICK, not to a plan: the ritual arm reads clear/resume
# markers, and the duties and FILL arms fold the tick's own output out of the transcript.
# The plan contributes one thing, a basename that lets a write to the plan file count as
# the task-list refresh, and the fold below already treats an empty name as matching
# nothing. So an engaged session with no plan is policed exactly as one with a plan, minus
# that one alternative way to discharge the refresh.
#
# wave-session-bound-run S5: `active_run` (no session input) is now `session_run`
# (lib/run.sh) — a session BOUND to a plan is policed against THAT plan's basename
# alone, whatever else is open in the root (AC-1); UNBOUND falls back to the
# newest plan exactly as before, and this gate says so once on stderr (AC-3);
# bound to a plan that has since closed is policed exactly as engaged-with-no-plan
# (AC-6) — the basename discharge is the only thing a missing plan costs.
PLAN="$BIONIC_RUN_PLAN"
case "$BIONIC_RUN_WORD" in
  bound-open) : ;;
  fallback)
    fold_advise "patrol-duties-gate: run resolved by newest-plan fallback (session unbound) — $PLAN"; _adv=1
    ;;
  bound-closed)
    fold_advise "patrol-duties-gate: bound plan closed — $PLAN; this session has no open run"; _adv=1
    PLAN=""
    ;;
  none|*)
    PLAN=""
    ;;
esac
PLAN_NAME=""
[ -n "$PLAN" ] && [ -f "$PLAN" ] && PLAN_NAME="$(basename "$PLAN")"

# ---------- the plan's BASENAME ----------
#
# Only the basename is kept. The path a tool_use carries may be absolute, repo-relative
# or cwd-relative depending on which tool wrote it, and the basename is the one form all
# three contain. An empty name matches nothing — guarded at the awk boundary, because an
# empty needle would otherwise make every write in the turn discharge the duty.

# ---------- reading the turn ----------
#
# One pass, two stages. jq flattens each transcript line into at most one record
# per event we care about; awk then folds that stream, resetting at every user
# PROMPT so that what survives to END describes the LAST turn only.
#
# A user-typed entry is a PROMPT only if it carries text. The `user` type is also
# how the CLI records every TOOL RESULT, and treating those as prompts would end
# the tick's turn at its first tool call — the wall would then be permanently
# silent, passing every tick in the fleet while looking installed and green.
#
# Newlines and tabs are squashed inside values because the stream is
# line-and-tab delimited; a prompt is many lines long and would otherwise forge
# records. Nothing downstream reads a value except by substring, so squashing
# costs no fidelity.
# A MARK line is emitted for EITHER marker, and a DECLINE line for the fill duty's
# explicit decline, on any record the ORCHESTRATOR AUTHORED whose text contains it —
# independent of the USER/TOOL typing below, and independent of the record's `type`,
# because the marker is a literal substring search over "a transcript record whose
# content contains" it, not a field read (STOPGATES/1).
#
# WHICH ROWS ARE THE ORCHESTRATOR'S (review F2). Every file the agent reads enters the
# transcript as a `tool_result` element of a `user` record. Read raw, that made a README,
# a fixture or a code comment carrying the literal `fill-declined:` discharge the AC-29
# fill duty nobody had declined — fail-open on the exact wall AC-29 is — and made a file
# carrying the /clear or resume marker force a spurious ritual refusal. So `$auth` below
# is the row's AUTHORED text and these two markers are read only out of it:
#   assistant, or any other type   -> the whole raw line. An assistant record's content is
#                                     the model's own — text, thinking, tool_use inputs —
#                                     and no other type carries a tool result. A
#                                     SessionStart report reaches the transcript as one of
#                                     those other types, which is how `source: resume`
#                                     still arrives (pinned by tests §53).
#   user                           -> the content when it is a STRING (the CLI's own
#                                     command records, the operator's own typing), else
#                                     ONLY the `text` elements of the array. Never a
#                                     `tool_result` element.
#   sidechain / agent-context      -> nothing. A subagent's decline is not the
#                                     orchestrator's, the same exclusion every other arm
#                                     of this gate makes.
#   unparsable                     -> nothing. A line that is not JSON has no author.
# The type-agnostic substring read is unchanged WITHIN a qualifying row; what is scoped is
# which rows qualify.
#
# ONE MORE RAW-TEXT RECORD, DELIBERATELY NOT SCOPED, for the fill duty (AC-29). The tick's
# `poker: FILL <ids>` line arrives as the CONTENT of a Bash tool result — a `user`-typed
# entry whose content is an array, which the prompt rule below deliberately does not treat
# as a prompt, and which the scoping above excludes — so it is read off the RAW line. That
# is the one direction where a planted marker costs a false BLOCK rather than a false
# silence, and this gate blocks once.
#
# The ids are cut at the first `\n` or `"` in the RAW line, which are the escaped newline and
# the closing quote of the JSON string the line is embedded in — so the record carries the
# FILL line and nothing that followed it.
#
# THE WINDOW (review, performance finding 1). This used to read the whole transcript on
# every Stop of an open run — one jq pass from byte zero, ~85 ms of CPU per MB, 4.3 s over
# the 50 MB a long wave session reaches, rising monotonically for the life of the run. Every
# fact this scan needs is a "since the most recent X" fact — the last user prompt, the last
# clear/resume marker, the last FILL line — so a window suffices provided it holds a whole
# orchestrator turn. 2000 lines does: the largest single turn in this repo's own two busiest
# wave transcripts (494cf1b6, b1a850c1, measured 2026-09-03) is 264 records, so the window
# carries ~7.5x the worst turn observed, and 5x hooks/context-spend.sh's `tail -n 400` for a
# scan that must reach further back than that hook's does.
#
# WHAT SCROLLING OUT COSTS, named rather than left to be discovered: when the clear/resume
# marker is older than the window, the ritual arm reads "no marker" and goes INERT — it does
# not refuse. That is FAIL-OPEN, and it is the right direction for a marker whose whole
# purpose is to catch the FIRST stop after a resume: by the time 2000 records have gone by,
# the ritual is either long done or long moot. Same for the tick-duties and fill arms, which
# reset at the last user prompt anyway and can only lose a turn that is 2000 records old.
SCAN_WINDOW_LINES=2000
STREAM=$(tail -n "$SCAN_WINDOW_LINES" "$TRANSCRIPT" 2>/dev/null | jq -Rr '
  . as $line
  | (($line | fromjson?) // null) as $r
  | (
      if $r == null then ""
      elif (($r.isSidechain // false) == true) then ""
      elif (((($r.agentId // $r.agent_id) // "") | tostring) != "") then ""
      elif $r.type == "user" then
        ( if ($r.message.content | type) == "string" then $r.message.content
          else ([$r.message.content[]? | select(.type == "text") | .text] | join(" "))
          end )
      else $line
      end
    ) as $auth
  | (if (($auth // "") | contains("<command-name>/clear</command-name>")) then "MARK\tclear" else empty end),
    (if (($auth // "") | contains("source: resume")) then "MARK\tresume" else empty end),
    (if ($line | contains("poker: FILL ")) then
       "FILL\t" + (($line | split("poker: FILL ")[1] | split("\\n")[0] | split("\"")[0]))
     else empty end),
    (if (($auth // "") | contains("fill-declined:")) then "DECLINE\t1" else empty end),
    (
      ($r // empty)
      | select((.isSidechain // false) != true)
      | select((((.agentId // .agent_id) // "") | tostring) == "")
      | if .type == "user" then
          ( if (.message.content | type) == "string" then .message.content
            else ([.message.content[]? | select(.type == "text") | .text] | join(" "))
            end ) as $t
          | select(($t // "") != "")
          | "USER\t" + ($t | gsub("[\n\t\r]"; " "))
        elif .type == "assistant" then
          .message.content[]?
          | select(.type == "tool_use")
          | "TOOL\t" + (.name // "")
            + "\t" + (((.input.file_path // .input.path // .input.command // "") | tostring) | gsub("[\n\t\r]"; " "))
            + "\t" + (([.input.name?, .input.description?, .input.subagent_type?, .input.prompt?]
                       | map(select(. != null) | tostring) | join(" ")) | gsub("[\n\t\r]"; " "))
        else empty
        end
    )
' 2>/dev/null) || STREAM=""
[ -n "$STREAM" ] || return "$_adv"

# ---------- THE RESUME/CLEAR RITUAL (AC-3), judged FIRST ----------
#
# Folded over the same stream, resetting at every marker so only the ritual for
# the LATEST clear/resume is judged — a Cron call before the marker is not "since"
# it. TOOL rows here are already main-thread-only (the select() above excludes
# sidechain and agentId-carrying entries), the same exclusion the tick-duties fold
# below relies on.
RITUAL=$(printf '%s\n' "$STREAM" | awk -F'\t' '
  BEGIN { marker = 0; listed = 0; violated = 0 }
  $1 == "MARK" { marker = 1; listed = 0; violated = 0; next }
  $1 == "TOOL" {
    if (!marker) next
    if ($2 == "CronList") { listed = 1; next }
    if ($2 == "CronCreate" && !listed) { violated = 1; next }
    next
  }
  END { if (marker && violated) print "block"; else print "quiet" }
')

if [ "$RITUAL" = "block" ]; then
  RITUAL_REASON="This is the first Stop after a /clear or a resume, and the transcript shows a CronCreate with no CronList before it since then. A predecessor Patrol cron survives a /clear and keeps firing into the new conversation — creating a job before listing and deleting the stray one leaves two clocks on one project.

Do the resume ritual, in order, then stop again — this gate blocks once:
  1. CronList
  2. delete every bionic-patrol session=<other> job it lists
  3. CronCreate
  4. bash ${HOOK_DIR}/session-poker.sh arm
  5. … adopt"
  fold_block block stop "a cron was created with no CronList first" "list and delete stray jobs first" \
    "$RITUAL_REASON"
  return 2
fi

# ---------- WHAT COUNTS AS A TICK (AC-22) ----------
#
# THE MARKER, NOT THE COMMAND. This gate used to call a turn a tick when the last USER row
# CONTAINED the substring `session-poker.sh tick`. The canonical-sdlc SKILL.md body contains
# that literal (it is the line telling the reader to run it), and the body is injected into
# the transcript as a USER row — so invoking the skill WAS a Patrol tick as far as this gate
# could tell, and the gate then refused the invoking turn for duties no tick had asked for
# (observed twice on session 14dcbee3, 2026-09-03; research-refusal.md §sibling defect).
#
# A tick is now what the patrol prompt was designed to announce: a USER row whose FIRST
# TOKEN is `bionic-patrol session=<session-id[0:8]>` (SKILL.md §The patrol prompt), for THIS
# session. That makes the test positional and session-scoped rather than a substring search,
# so a row that merely quotes the tick command is not a tick, and a predecessor's job still
# firing into this conversation after a /clear is not this session's tick either.
TICK_MARK="bionic-patrol session=${BIONIC_SID:0:8}"

# TICK / LISTAGENTS / TASKLIST, folded over the last turn.
VERDICT=$(printf '%s\n' "$STREAM" | awk -F'\t' -v plan="$PLAN_NAME" -v mark="$TICK_MARK" '
  $1 == "USER" {
    t = $2; sub(/^[ \t]+/, "", t)
    tick = (index(t, mark) == 1)
    la = 0; tl = 0
    next
  }
  $1 == "TOOL" {
    if ($2 == "ListAgents") { la = 1; next }
    if ($2 == "TaskList")   { tl = 1; next }
    if (plan != "" && index($3, plan) > 0) {
      if ($2 == "Edit" || $2 == "Write" || $2 == "NotebookEdit" || $2 == "Bash") tl = 1
    }
    next
  }
  END {
    if (!tick) { print "quiet"; exit }
    if (la && tl) { print "quiet"; exit }
    if (!la && !tl) { print "both"; exit }
    if (!la) { print "listagents"; exit }
    print "tasklist"
  }
')

# ---------- THE THIRD DUTY: a printed FILL is answered before the turn ends (AC-29) ----
#
# WHY THIS IS A WALL AND NOT A LINE IN THE PROMPT. The tick can compute the gap between the
# budget and the roster, and it can name the tasks that are ready — but it cannot dispatch,
# and a recommendation nobody is obliged to answer is how this repo's own 1.4.0 wave ran six
# writers against a budget of twenty-two. The turn's END is the only moment at which
# "the FILL went unanswered" is a fact, so it is the moment this asks.
#
# ANSWERED MEANS EITHER: an `Agent` tool_use naming the task, or an explicit
# `fill-declined: <reason>` anywhere in the turn. The decline is not a loophole — it is the
# point. There are good reasons not to fill (a dependency landing this minute, peers not yet
# idle, a merge in flight), and every one of them is worth one line in the record. What is
# refused is SILENCE.
#
# NAMED, not counted: a turn that dispatched two of three named tasks is missing one, and
# the reason says which. An id is matched on a WORD BOUNDARY inside the dispatch's own
# fields — its name, description, subagent_type and prompt — so `ONE` is not found inside
# `PHONE`, and only ids shaped like task ids (letters, digits, `_`, `.`, `-`) are ever
# echoed back into the refusal. A `.` in an id is a LITERAL dot in that boundary test, not
# the regex wildcard it would otherwise be — see the escape in the fold below.
#
# Folded over the same stream, resetting at every user PROMPT exactly as the duties fold
# above it does, and inert on every turn with no FILL line in it — which is every turn in
# every project whose tick prints none.
FILL_MISSING=$(printf '%s\n' "$STREAM" | awk -F'\t' -v mark="$TICK_MARK" '
  $1 == "USER" {
    t = $2; sub(/^[ \t]+/, "", t)
    tick = (index(t, mark) == 1)
    fills = ""; declined = 0; agents = " "
    next
  }
  $1 == "FILL"    { fills = $2; next }
  $1 == "DECLINE" { declined = 1; next }
  $1 == "TOOL" {
    if ($2 == "Agent") agents = agents $3 " " $4 " "
    next
  }
  END {
    if (!tick || fills == "" || declined) exit
    n = split(fills, ids, /[ \t]+/)
    missing = ""
    for (i = 1; i <= n; i++) {
      id = ids[i]
      if (id !~ /^[A-Za-z0-9_.-]+$/) continue
      # THE ID IS DATA, THE PATTERN IS CODE. The boundary test below is a DYNAMIC regex
      # and the id is spliced into it, so every metacharacter the validity filter above
      # admits has to be neutralised first or it reads as syntax. `.` is the whole class:
      # `-` is special only inside a bracket expression and is spliced outside one, `_`
      # is never special. Unescaped, a FILL for `a.b` was answered by a dispatch naming
      # `axb` — a false negative on the wall, the fail-open direction (review F1).
      pat = id
      gsub(/\./, "[.]", pat)
      if (agents ~ ("(^|[^A-Za-z0-9_.-])" pat "([^A-Za-z0-9_.-]|$)")) continue
      missing = missing (missing == "" ? "" : " ") id
    }
    if (missing != "") print missing
  }
')

if [ -n "$FILL_MISSING" ]; then
  FILL_REASON="Patrol fill unanswered: the tick printed FILL and this turn neither dispatched nor declined ${FILL_MISSING}. Dispatch each named task, or write a line \"fill-declined: <reason>\" saying why not, then stop again — this gate blocks once."
else
  FILL_REASON=""
fi

# The two folds are judged TOGETHER, so a turn that skipped a duty AND left a FILL
# unanswered is told both things once. Blocking on one and staying silent about the other
# would hide the second behind the one-shot: the next stop passes by design.
if [ "$VERDICT" = "quiet" ] || [ -z "$VERDICT" ]; then
  if [ -n "$FILL_REASON" ]; then
    fold_block block stop "the tick printed FILL and nothing answered" "dispatch each task, or decline" \
      "$FILL_REASON"
    return 2
  fi
  return "$_adv"
fi

# ---------- the refusal ----------
#
# THE REASON NAMES WHAT IS MISSING AND NOTHING ELSE. A reason that recites both
# duties whichever one was skipped makes the reader re-derive the answer the gate
# already knows, and a gate that fires on every tick with the same paragraph is
# read as noise inside two ticks. The three duty strings are LITERALS: no payload
# value and no path is interpolated into them. The fill clause is the one
# exception and it carries task ids read out of the transcript — filtered in the
# fold above to `[A-Za-z0-9_.-]+` and handed to jq through `--arg`, so neither a
# shell nor a JSON quoting surface is opened by them.
# THE FACT AND THE FIX COME FROM THE VERDICT, one row per duty missed (table rows
# 111-113); the existing paragraph stays whole as `detail`.
case "$VERDICT" in
  both)
    FACT='no ListAgents and no task-list refresh'; FIX='do both, then stop again'
    REASON='Patrol duties incomplete: no ListAgents call, and no task-list refresh — TaskList or a plan-ledger write. Do both, then stop again — this gate blocks once.' ;;
  listagents)
    FACT='no ListAgents call since this Patrol tick'; FIX='call ListAgents, then stop'
    REASON='Patrol duties incomplete: no ListAgents call since this Patrol tick. Refresh the subagent panel, then stop again — this gate blocks once.' ;;
  tasklist)
    FACT='no task-list refresh since this tick'; FIX='refresh it, then stop again'
    REASON='Patrol duties incomplete: no task-list refresh since this Patrol tick — TaskList or a plan-ledger write. Do one, then stop again — this gate blocks once.' ;;
  *)
    return "$_adv" ;;
esac
[ -n "$FILL_REASON" ] && REASON="$REASON $FILL_REASON"

# The JSON decision payload on STDOUT with return "$_adv", the form Design (T5) names.
# (hooks/landing-gate.sh refuses through exit 2 + stderr instead; both are live
# Stop-hook block channels in this CLI, and the two gates deliberately do not
# share a mechanism they never share a code path with.)
fold_block block stop "$FACT" "$FIX" "$REASON"
return 2
}


# ─── stop_patrol_revive ───
#
# THE HOOK'S OWN HEADER, CARRIED OVER WHOLE. It is the design record for this
# verdict — every ruling, incident and measurement that shaped it — and it
# travels with the code rather than being left behind in a deleted file.
# Where it says "this hook" it now means this function, and where it names a
# registration it means hooks/stop.sh's.
#
# THE PATROL SELF-HEAL — epic-19 wave-01, spec AC-F6; design ledger D4, ratified
# 2026-08-27 ("Simply update the user in the terminal of the issue, and reload the
# Patrol").
#
# WHAT IT IS FOR. The CLI holds its cron table in PROCESS MEMORY, with no file
# behind it (payload/scripts/lib/patrol.sh's own honest limit, and doctor's). A
# `claude plugin update`, a `/reload-plugins`, a session continue or a
# `/clear`+resume can therefore delete the Patrol job and leave nothing that says
# so: the run keeps working, the poker never ticks again, no row is ever judged
# against its declared duration, and the fleet dies quiet. The stamp goes stale one
# window later — but only where somebody LOOKS, and until this hook existed the
# only two places that looked were a dispatch attempt (hooks/dispatch-preflight.sh's
# arming wall) and a hand-run `/bionic:doctor`. Between them, nothing observed it
# and nothing told anyone. This hook is the thing that looks, every turn.
#
# WHY THE STOP CHANNEL, and not one of the stop hooks that already exist. The
# detection has to fire on the run's own rhythm rather than on a dispatch — that is
# the whole gap. `Stop` is the only recurring orchestrator event there is: it fires
# once per turn, whatever the turn contained, and it keeps firing on turns the skill
# was not re-invoked on (hooks/landing-gate.sh depends on and documents those exact
# properties). hooks/stop-guard.sh is `PreToolUse|TaskStop` — it fires when the
# orchestrator stops an AGENT, which is neither recurring nor about the session's
# clock; hooks/stop-check.sh is not registered on any channel at all. So the choice
# was Stop or nothing.
#
# WHY A BLOCK AND NOT A PRINT. A shell hook cannot call `CronCreate` — that is a
# model tool, and re-creating the cron job is half of what "reload the Patrol"
# means. What a Stop hook CAN do is refuse the stop once with a `reason`, which the
# CLI renders into the operator's terminal and hands to the model as the next thing
# to act on. One mechanism therefore carries both halves of AC-F6: the reason IS the
# terminal notice, and it is also the instruction that gets the Patrol re-armed. The
# pattern is hooks/patrol-duties-gate.sh's, registered beside it on the same channel.
#
# IT MUST NEVER ARM THE STAMP ITSELF, and this is the sharpest edge in the file. A
# hook that ran `session-poker.sh arm` would freshen the stamp over a cron table
# that still holds nothing — buying a Patrol that reads alive to the arming wall,
# to doctor and to this hook, and that never fires again. That is strictly worse
# than the death it was meant to heal, because the death is at least detectable.
# So this gate READS, exactly like every other gate (TDD §3.2), and the re-arm is
# named in the reason with its cron half FIRST. tests/patrol-revive.test.sh Group 5
# pins the stamp's mtime across a firing.
#
# THE THREE STAMP STATES, and why only one of them speaks:
#   absent  -> silent. Never armed, OR deliberately disarmed — `session-poker.sh
#              disarm` removes the stamp, which is how a run says its Patrol was
#              ended on purpose. Never-armed is a real finding, but it is the ARMING
#              WALL's to make at the moment a dispatch is attempted; raised here it
#              would nag every session that has the skill armed and has not engaged
#              a run yet, which is the first turn of every run.
#   fresh   -> silent. Firings are landing; a monitor with nothing to say says so
#              by saying nothing.
#   stale   -> THE NOTICE. Something armed a Patrol on THIS session and the clock
#              has stopped.
#
# SCOPE — WHAT "AN ACTIVE RUN" IS HERE. Two conditions, and no third. First, this
# project has an OPEN RUN: `session_run` (which was `active_run` until
# wave-session-bound-run made run identity per-session) under the payload's project root,
# the same fact every other governance hook is scoped by since bionic 1.4.0. Second, a stamp
# EXISTS for this session, which by doctrine (SKILL.md §Dispatch) happens at the
# Step-0 confirmation of a new run or the resume ritual of an open one, and at no
# other moment. An armed-then-stale stamp is therefore already the statement "a run
# engaged on this session and its clock died".
#
# THE FIRST CONDITION USED TO BE "the governing skill is armed", and reading the plan
# was REJECTED on two grounds. Both are answered now. It would have been a fifth
# hand-copy of the active-wave block — there is one reader, `lib/run.sh`, and no copy
# to drift. And it would have imported a measured silent-inert mode: a marker-less
# `*.md` winning the newest-file race disarmed the dispatch wall repo-wide for ~15
# minutes on 2026-08-15 (record/session-20260815-landing-supervision/
# t8-forensic-read.md). That mode lived in the copies' selection rule, not in the
# question; `active_plan` requires an unfenced `## SDLC State` heading, which is
# exactly the filter whose absence caused it. A monitor whose job is to notice
# silence must not acquire a new way to go silent — and the alternative it now
# replaces was a worse one, because a skill registration goes quiet without leaving
# anything on disk to notice.
#
# A SECOND ARM, ADDED FOR bionic 1.4.0 (spec AC-3, plan task STOPGATES): ONE CLOCK
# PER RUN. This session having a stamp of its own says a Patrol was armed here; a
# second FRESH `patrol-<other-sid>.state` in the SAME project's `.bionic/tmp` says
# another one is ALSO alive right now — the duplicate-clock shape S5's ritual
# exists to prevent, caught here even when it happens without a /clear or resume in
# between (a stray `CronCreate` run twice, or two sessions racing an `arm`). This is
# a FINDING, not a block: it is a stderr diagnostic line, exactly `loader_fail_open`'s
# voice, because a sibling's live clock is not this session's stop to refuse — only
# its own dead one is. Read AFTER the threshold is known (so it shares the same
# staleness measurement) and BEFORE this session's own stale/fresh decision, so it
# fires whichever way that decision goes.
#   - the other stamp is this session's own                    -> not counted
#   - the other stamp is a symlink                              -> not counted, never followed
#   - the other stamp's mtime is unreadable                     -> not counted
#   - the other stamp is STALE (past the same 2x limit)          -> not counted, silent
#   - the other stamp is FRESH                                   -> one stderr finding line, naming its session
#   - exactly one live stamp (this session's own, no others)     -> silent on this arm
#
# FAIL DIRECTIONS (pinned by tests/patrol-revive.test.sh):
#   - jq absent                                       -> pass, silent
#   - not a Stop payload (SubagentStop included)      -> pass, silent
#   - stop_hook_active true                           -> pass, silent (ONE block per
#                                                        turn, not one per session)
#   - no session_id, or one not shaped like one       -> pass, silent
#   - no cwd, or no resolvable project root           -> pass, silent
#   - no stamp, or a symlink where the stamp goes     -> pass, silent (never armed,
#                                                        or deliberately disarmed)
#   - no poker on either lane, or no readable interval-> pass, silent (no threshold)
#   - the stamp's mtime unreadable                    -> pass, silent
#   - stamp age within 2x the poker-interval          -> pass, silent
#   - stamp age past it                               -> BLOCK, naming the re-arm
#
# THREE ACCEPTED LIMITS. First, inherited from the stamp and shared with the arming
# wall: this attests that Patrol FIRINGS ARE LANDING and cannot see the cron table,
# so a job deleted moments ago still looks alive for up to one stale window — the
# notice is late by design rather than wrong. Second, and now CLOSED where it
# used to be unbounded: a deliberate stop was indistinguishable from a death.
# Nothing in production removed a stamp, so a Patrol the run ended on purpose —
# the run-close `CronDelete`, or the poker's own DISARM decision, which is reached
# on every quiet stretch between dispatch batches — left an aging stamp behind and
# was reported dead here on EVERY remaining turn of the session. This notice does
# not "block once" in the sense that matters: `stop_hook_active` suppresses only
# the second stop WITHIN one turn and resets at the next, so the blocks are one
# per turn, forever, and the CLI's own override after 8 CONSECUTIVE blocks can
# never engage above us because one-per-turn blocks are never consecutive. There
# is no backstop; the stamp going away is the whole of the exit (critic C-2,
# epic-19 w1). `session-poker.sh disarm` is what makes it go away: the run-close
# ritual (SKILL.md §Dispatch) and a DISARM tick both take it, and an ABSENT stamp
# is silent here by design. WHAT REMAINS is a disarm that FORGOT the verb — a
# `CronDelete` with no `disarm` beside it — which still reads as a death; its cost
# is one re-armed clock on a run that was nearly over, against a fleet nobody is
# waiting on for the opposite error.
#
# Third, THIS HOOK NO LONGER SHARES THE FAILURE MODE IT MONITORS — and that reversal
# is the point of bionic 1.4.0's always-on registration. It used to be registered in
# the governing skill's own frontmatter, where a skill's hooks die with the
# conversation that armed them: three of the four events that kill a Patrol — a
# session continue, a `/clear` + resume, a `/reload-plugins` — deregistered this hook
# itself, silently and at the same moment, so the monitor died with the thing it
# monitors and its real coverage was the one remaining event, a `claude plugin update`
# mid-session. It is registered once in hooks/hooks.json now and survives all four.
# What remains outside its reach is narrower and structural: an event that stops the
# CLI from delivering `Stop` at all.
#
# Registered once on the Stop channel in hooks/hooks.json, always on, and scoped by
# `session_run` (which was `active_run` until wave-session-bound-run made run identity
# per-session) plus this session's own stamp — both facts on disk.
# [WALL: tests/patrol-revive.test.sh]
#
# hooks/patrol-revive.sh's body. Stop only: a subagent arms no Patrol — SKILL.md
# §Dispatch, "subagents stay timerless" — so a worker's turn end can prove nothing
# about the orchestrator's clock.

stop_patrol_revive() {  # <event> -> 0 nothing · 1 advisory · 2 block
  local _ev="${1:-}" _adv=0
  local HOOK_DIR _RUN_PLAN STAMP_FILE POKER INTERVAL LIMIT MTIME AGE REASON
  local _rival_now _rival_sf _rival_sid _rival_mt _rival_age

  case "$_ev" in Stop) : ;; *) return 0 ;; esac

# THIS SCRIPT'S OWN DIRECTORY, so the poker it measures against and the poker it
# NAMES are the same file — resolved the way hooks/dispatch-preflight.sh resolves
# its sibling, never through PATH (a hook's PATH is not ours to trust) and never
# through an env seam (a seam on the path under test leaves the production path
# unverified).
HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -n "$HOOK_DIR" ] || HOOK_DIR="$(dirname "$0")"
[ -d "$BIONIC_ROOT" ] || return "$_adv"

# ---------- THE ENGAGEMENT SWITCH — asked before anything else ----------
#
# task-engaged-session: bionic's walls are the RUN's, not the repo's, and a run is entered
# by invoking canonical-sdlc. A session that never did is a bystander here and must not see
# a refusal, an advisory, or a state write from this hook. `engaged_session` (lib/run.sh) is
# true only for a REGULAR file at `.bionic/tmp/engaged-<sid>.state`; every unreadable state —
# absent, symlink, foreign sid, `unknown` — reads as NOT engaged. Silent, return "$_adv": the
# direction §7 gives every start-side ambiguity, and here it is the consent boundary itself
# (1.3.2 close-out ruling — the arming partition IS the consent boundary).
[ "$BIONIC_ENGAGED" = 1 ] || return "$_adv"

# ---------- THE RUN PREDICATE (AC-7, AC-8) ----------
#
# The first of this hook's two scope conditions (see SCOPE in the header). No open run,
# no Patrol to be dead, and nothing for a monitor to say.
#
# PLAN-BOUND AND KEPT (task-engaged-session). This hook has exactly one arm and its whole
# subject is a Patrol serving a run: the duties a revived Patrol would resume — FILL, the
# task-list refresh, the roster read — are the run's, so a session engaged with no plan yet
# has nothing for this monitor to be about. Engagement decides WHETHER; here the plan still
# decides WHAT, and there is only the one thing.
#
# wave-session-bound-run S5: `active_run` (no session input) is now `session_run`
# (lib/run.sh) — a session BOUND to a plan proceeds on THAT plan alone, whatever
# else is open in the root (AC-1); UNBOUND falls back to the newest plan exactly
# as before, and this hook says so once on stderr (AC-3); bound to a plan that
# has since closed takes exactly this line's existing branch — return "$_adv" — after
# announcing the closure (AC-6).
_RUN_PLAN="$BIONIC_RUN_PLAN"
case "$BIONIC_RUN_WORD" in
  bound-open) : ;;
  fallback)
    fold_advise "patrol-revive: run resolved by newest-plan fallback (session unbound) — $_RUN_PLAN"; _adv=1
    ;;
  bound-closed)
    fold_advise "patrol-revive: bound plan closed — $_RUN_PLAN; this session has no open run"; _adv=1
    return "$_adv"
    ;;
  none|*)
    return "$_adv"
    ;;
esac

# ---------- was a Patrol ever armed on this session ----------
#
# The filename is hooks/session-poker.sh's, and the two spellings are held together
# by tests/cross-gate-agreement.test.sh §P so a rename on one side cannot go quiet
# on the other. A symlink is not a stamp: it reads as ABSENT rather than being
# followed, which is the posture every other .bionic/tmp reader takes and the
# direction §8 requires — a hostile repo may CLOSE a wall and must never OPEN one.
STAMP_FILE="$BIONIC_ROOT/.bionic/tmp/patrol-${BIONIC_SID}.state"
[ -L "$STAMP_FILE" ] && return "$_adv"
[ -f "$STAMP_FILE" ] || return "$_adv"

# ---------- the threshold ----------
#
# THE INTERVAL IS THE POKER'S OWN, obtained by invoking its `interval` verb rather
# than by re-reading `poker-interval:` here: one knob, one reader. A malformed
# override makes the poker refuse, and the fallback is its own built-in default
# asked for through `interval-default` — never a constant retyped here, which would
# drift the first time either side moved and leave this hook measuring against a
# threshold nobody configured.
#
# NO NUMBER MEANS NO FINDING. Where hooks/dispatch-preflight.sh still has a
# never-armed arm to run without a threshold, this hook's only question IS the
# threshold — so an unreadable interval leaves it with an ambiguity rather than a
# finding, and it takes the direction every start-side ambiguity in this fleet
# takes: pass, silent. A per-turn gate is also the worst possible place to be loud
# about a condition it cannot measure.
POKER="${HOOK_DIR}/session-poker.sh"
[ -f "$POKER" ] || POKER="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/session-poker.sh"
[ -f "$POKER" ] || return "$_adv"

INTERVAL=$( cd "$BIONIC_ROOT" 2>/dev/null && bash "$POKER" interval 2>/dev/null )
case "$INTERVAL" in ''|*[!0-9]*) INTERVAL="" ;; esac
if [ -z "$INTERVAL" ] || [ "$INTERVAL" -le 0 ]; then
  INTERVAL=$( bash "$POKER" interval-default 2>/dev/null )
  case "$INTERVAL" in ''|*[!0-9]*) INTERVAL="" ;; esac
fi
[ -n "$INTERVAL" ] && [ "$INTERVAL" -gt 0 ] || return "$_adv"

# 2x, exactly as the arming wall measures it: a Patrol firing on its interval is,
# at any random instant, up to one whole interval stale while perfectly healthy.
LIMIT=$(( INTERVAL * 2 ))

# ---------- the second-stamp finding (AC-3): one clock per run ----------
#
# Every OTHER patrol-*.state beside this session's own, in the same .bionic/tmp,
# judged against the SAME limit — a fresh one is a live duplicate clock, worth a
# finding whether or not THIS session's own clock turns out to be stale or fine.
_rival_now="$(date -u +%s 2>/dev/null || echo 0)"
for _rival_sf in "$BIONIC_ROOT"/.bionic/tmp/patrol-*.state; do
  [ -e "$_rival_sf" ] || [ -L "$_rival_sf" ] || continue
  [ "$_rival_sf" = "$STAMP_FILE" ] && continue
  [ -L "$_rival_sf" ] && continue
  _rival_sid="${_rival_sf##*/}"; _rival_sid="${_rival_sid#patrol-}"; _rival_sid="${_rival_sid%.state}"
  [ -n "$_rival_sid" ] || continue
  [ "$_rival_sid" = "$BIONIC_SID" ] && continue
  _rival_mt=$(stat -f %m "$_rival_sf" 2>/dev/null || stat -c %Y "$_rival_sf" 2>/dev/null)
  case "$_rival_mt" in ''|*[!0-9]*) continue ;; esac
  _rival_age=$(( _rival_now - _rival_mt ))
  [ "$_rival_age" -lt 0 ] && _rival_age=0
  if [ "$_rival_age" -le "$LIMIT" ]; then
    fold_advise "patrol-revive: a second live Patrol stamp for session $(printf '%.8s' "$_rival_sid") exists here — one clock per run; delete the stray job and stamp"; _adv=1
  fi
done

MTIME=$(stat -f %m "$STAMP_FILE" 2>/dev/null || stat -c %Y "$STAMP_FILE" 2>/dev/null)
case "$MTIME" in ''|*[!0-9]*) return "$_adv" ;; esac
AGE=$(( $(date -u +%s) - MTIME ))
[ "$AGE" -lt 0 ] && AGE=0
[ "$AGE" -gt "$LIMIT" ] || return "$_adv"

# ---------- the notice ----------
#
# WHAT IT OWES THE READER, in order: the fact, the measurement it rests on, the
# cause they can recognise, and the two commands that fix it. The path, the age and
# both numbers are interpolated through `jq --arg`, so nothing here has a
# JSON-quoting surface. The poker is named at its RESOLVED ABSOLUTE path, never as
# `<plugin-root>/...`: this text is read by a model that will type it into its own
# shell, where `${CLAUDE_PLUGIN_ROOT}` is unset, and a cron job carrying a
# placeholder fires into a `command not found` every interval and reports nothing
# (SKILL.md §Dispatch states the rule; this is the same rule obeyed by a hook that
# already knows the answer).
#
# THE CRON HALF IS FIRST because the order is a safety property, not a style: `arm`
# alone freshens the stamp and buys a Patrol that reads alive and never fires. And
# FIRST IS NOT ENOUGH, because step 1 is the refusable half — `CronCreate` is measured
# non-deterministically refused by the auto-mode classifier
# (.bionic/docs/record/epic-19/w1/t3-probes.md finding 1) — so the conditional is stated
# in the text a model acts on, not only in this header a model never reads. A step 2 run
# after a refused step 1 produces the exact state the header above argues is worse than
# the death: an undetectably dead Patrol. The way OUT is named too, because a notice that
# offers only "re-arm" to a run that meant to stop is the loop critic C-2 found.
REASON="The Patrol died mid-run and nothing said so.

Its last stamp is ${AGE}s old — past the ${LIMIT}s limit, which is 2x the ${INTERVAL}s poker-interval in force for this project:
    ${STAMP_FILE}

The CLI holds its cron table in process memory with no file behind it, so a plugin update, a /reload-plugins, a session continue or a /clear+resume deletes the job and leaves the stamp as the only trace. Nothing is ticking the poker now: no dispatched row is being judged against its declared duration, and anything this run launched is waiting on a clock that stopped.

Re-arm it — both halves, the clock FIRST, because arming the stamp over an empty cron table buys a Patrol that reads alive and never fires:
  1. CronCreate a RECURRING session job at the interval \`bash ${POKER} interval\` reports, carrying the patrol prompt (the canonical-sdlc skill's Dispatch section).
  2. ONLY IF step 1 succeeded and returned a job: bash ${POKER} arm

If step 1 is refused or fails, do NOT run step 2 — a fresh stamp over an empty cron table reads ALIVE to this hook, to the dispatch wall and to /bionic:doctor while nothing fires again, which is worse than the death this notice is reporting. Tell the user the Patrol is down and that CronCreate was refused, and leave the stamp stale.

If this Patrol was stopped ON PURPOSE, record that instead of re-arming: \`bash ${POKER} disarm\` removes the stamp, and this notice goes with it.

Then stop again — this notice blocks once per turn, and it returns on the next turn until the stamp is re-armed or removed."

# The JSON decision payload on STDOUT with return "$_adv" — the same Stop-hook block
# channel hooks/patrol-duties-gate.sh uses. (hooks/landing-gate.sh refuses through
# exit 2 + stderr instead; both are live in this CLI, and gates that share no code
# path deliberately do not share a mechanism either.)
fold_block block stop "the Patrol died mid-run and nothing said so" "re-arm it, the clock first" \
  "$REASON"
return 2
}
