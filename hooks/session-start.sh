#!/bin/bash
# SESSION-START — what the previous conversation left on this project, and nothing
# else (bionic 1.4.0, spec AC-1; AC-4's "the SessionStart block runs the report";
# AC-11's legacy-symlink listing; plan task SSTART).
#
# WHAT `/clear` ACTUALLY DOES, measured (probe record, .bionic/docs/record/
# wave-1.4.0-probe.md). The process does not restart: same pid, same
# `sessions/<pid>.json` rewritten in place, and the session id re-keyed in every
# channel at once — env, hook payload and pid file all move together (A-probe-1/2/3).
# So the old conversation's state does not go anywhere either. What is left beside
# the new session's own files is:
#
#   a ROSTER with open rows       agents the predecessor dispatched, still running,
#                                 filed under a session id nothing now answers to.
#                                 `/clear` does not kill agents.
#   a WATCH RECORD under the old sid — the predecessor's watcher, which sees the
#                                 clear and rests, or died without a word.
#   a LEGACY `.bionic` SYMLINK    `<repo>/.worktrees/<x>/.bionic -> <repo>/.bionic`,
#                                 planted by older spawn-worktree.sh runs. Design
#                                 ledger C2 retired it: a second path to one state.
#
# None of that announces itself, and every one of them reads as normal until a
# dispatch or a stop goes to the wrong address. This hook is the announcement.
#
# IT IS A DETECTOR THAT ALSO SWEEPS, AND NOTHING ELSE (REQ-R2, ticket-30, amended
# 2026-09-07 — this paragraph described a stricter contract before that wave). It
# arms nothing, adopts nothing, and never deletes a file itself: the one write it
# can make is calling `session-poker.sh sweep`, silently, once, near the end of
# every run — see "the silent auto-sweep" below for the whole story, including the
# age gate and why REQ-R2 is a deliberate reversal of session-poker.sh's own D-5.
# The second write (wave-36 T1, D7) is this session's own load record,
# `.bionic/tmp/loaded-<sid>.state`, written only when the CLI handed the hook a
# CLAUDE_PLUGIN_ROOT — see "the load record" below. Every OTHER byte in this file is
# still pure detection: the report above is built
# from reads alone. `tests/session-start.test.sh`'s `.bionic`-subtree fingerprint
# expects the sweep's own deletions and, on a genuine failure, one marker file
# — never a roster row, or anything this hook wrote for itself.
#
# FAIL OPEN, ALWAYS EXIT 0. A SessionStart hook that refuses would block the start
# of every conversation on this machine, and what it is protecting is a report.
# A missing library, no jq, an unparsable payload, no session key, no project root:
# each of those is a silent exit 0. `.claude/rules/hook-authoring.md` — a detector
# never arms and never blocks.
#
# STDOUT IS THE DELIVERY MECHANISM. A SessionStart hook's stdout is added to the
# new conversation's context, so the block below is written to be read by the model
# that is about to act, not by a terminal. It prints ONLY when there is something
# to report: a clean start on a project with no predecessor state produces no output
# at all, because a block that prints every session is a block nobody reads.
#
# Registered once, in hooks/hooks.json, on SessionStart with matcher
# `startup|clear|resume|compact` — pinned by tests/cross-gate-agreement.test.sh §L.

set -u

BIONIC_LIB_WANT="context.sh root.sh session.sh patrol.sh run.sh roster.sh binding.sh"
# Find the library through lib/loader.sh beside this hook; payload/scripts/lib/loader.sh says how.
_bl_dir="$(dirname "$0")"; _bl_l="$_bl_dir/../scripts/lib/loader.sh"; [ -r "$_bl_l" ] || _bl_l="$_bl_dir/../payload/scripts/lib/loader.sh"
# shellcheck source=/dev/null
if [ -r "$_bl_l" ]; then . "$_bl_l"; bionic_load; else
  BIONIC_LIB=""; BIONIC_LIB_MISSING="${BIONIC_LIB_WANT%% *}"; BIONIC_LIB_CANDS="$_bl_dir/../scripts/lib, $_bl_dir/../payload/scripts/lib"
  loader_fail_open() { echo "$1: library $BIONIC_LIB_MISSING not found at $BIONIC_LIB_CANDS — hook stepping aside; run /bionic:doctor" >&2; exit 0; }
  loader_fail_closed() { set -- "$1"; [ "${#1}" -le 25 ] || set -- "${1:0:24}…"; echo "bionic: load refused — $1 cannot load the bionic library (run /bionic:doctor)" >&2; exit 2; }
fi

# The library, or nothing. `loader_fail_open` prints one stderr line and exits 0 —
# a detector that cannot read the disk reports nothing rather than guessing.
[ -n "$BIONIC_LIB" ] || loader_fail_open "session-start"
. "$BIONIC_LIB/context.sh"  || exit 0   # bionic_context, bionic_jq
. "$BIONIC_LIB/root.sh"     || exit 0   # project_root
. "$BIONIC_LIB/session.sh"  || exit 0   # session_id, and its one divergence warning
. "$BIONIC_LIB/patrol.sh"   || exit 0   # watch_state, patrol_dead_sessions
. "$BIONIC_LIB/run.sh"      || exit 0   # active_run, engaged_session
. "$BIONIC_LIB/roster.sh"   || exit 0   # roster_open_counts — the one close predicate (T17, D10)
. "$BIONIC_LIB/binding.sh"  || exit 0   # bind_holders — who else's marker names the one run (T15)
. "$BIONIC_LIB/worktree.sh" || exit 0   # worktree_legacy_links (AC-11/AC-7.1, A-orch-24)
# The clock's one home, asked by name: patrol.sh loads it only softly.
bionic_need time.sh _time_epoch

# THE STANDING DECISION LINE (wave-33 T27, AC-11.2). One line, printed first in every session this
# hook runs in: engaged or not, a run open or not, a `.bionic` present or not. The rule that sends
# a decision through the `decision` skill sits in canonical-sdlc, which loads only inside a run, so
# a session with no run open answered a choice between approaches in prose (T19's live check). A
# SessionStart hook's stdout is context in every session; this is the one place that reaches them
# all. It sits above every early exit below, so none of them can swallow it.
printf 'bionic: any decision or choice between approaches you put to the user goes through the bionic:decision skill — invoke it.\n'

# THE RUN VERDICT IS ASKED FOR (epic-23 wave-14 REQ-4, spec D5). `bionic_context`
# computes it only for a caller that sets this, because the plan scan behind it is
# the preamble's most expensive value and most hooks never read the answer. The greeting prints the bound
# line from it (:353-354, :365-366).
BIONIC_CONTEXT_WANT_RUN=1

# The tree this hook was launched from — printed absolute in the step file and adopt lines.
# `$(dirname "$0")/..` and `pwd -P`
# rather than `realpath`, which stock macOS does not ship (L-LOADER/5, L-BIONIC_ROOT/2).
HOOK_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)" || HOOK_ROOT=""
[ -n "$HOOK_ROOT" ] || HOOK_ROOT="$(dirname "$0")/.."

# ------------------------------------------------- the payload, and the context
#
# ONE CALL (REQ-1f, lib/context.sh): the payload read at most once and only when
# stdin is not a terminal, the cwd by the ONE ladder, the root from it, the session
# id past the ONE guard, engagement and the run verdict as VALUES.
#
# THE REDIRECTION IS NOT HERE, and that is this hook's one deviation from the shape
# the other fourteen use. lib/session.sh prints a line when the payload and the
# environment disagree about the session id, and this hook is the single reader that
# must SHOW that line — the L-SESSION contract, pinned at
# tests/cross-gate-agreement.test.sh §P2. Suppression belongs at the call site, so
# the other fourteen write `bionic_context 2>/dev/null || exit 0` and this one does
# not.
#
# THE LADDER USED TO BE REVERSED HERE, and REQ-1h ended that: this hook is on the
# library's one ladder now, in the library's order, like every other hook. The rungs
# are named once, in lib/context.sh, and deliberately not restated here — a comment
# naming a channel its file no longer reads is how the next reader learns the wrong
# thing.
bionic_context || exit 0

pfield() {  # <jq path> -> the field, or empty
  command -v jq >/dev/null 2>&1 || return 0
  bionic_jq "$1"
}
SOURCE="$(pfield .source)"

# ---------------------------------------------------------------- the project
# A `.bionic` that is a SYMLINK is never a root (ledger C2) — which is exactly the
# legacy link this hook reports further down, so a worktree carrying one resolves to
# the main checkout and reports the main checkout's state, not a second copy of it.
[ -d "$BIONIC_ROOT/.bionic" ] && [ ! -L "$BIONIC_ROOT/.bionic" ] || exit 0
TMP="$BIONIC_ROOT/.bionic/tmp"

# ---------------------------------------------------------------- the load record
#
# WHAT THIS SESSION LOADED (wave-36 T1, spec D7, ADR-055). A session started with
# `--plugin-dir <checkout>/payload` runs the checkout, and this hook is the one bionic
# code that runs at load, so it writes down what was loaded, keyed by the session id:
#
#   .bionic/tmp/loaded-<sid>.state
#     root=<CLAUDE_PLUGIN_ROOT, physical>
#     commit=<HEAD>                      only when the root is a checkout of the plugin
#     started=<ISO-8601 UTC>
#     cwd=<the start directory, physical> (wave-37 T5; D9) the name its transcript is filed under
#     <sha256> <path under root>         one line per hooks/hooks.json, skills/**/*.md,
#                                        agents/**/*.md, commands/*.md
#
# Those four sets are what the CLI snapshots at start; hook SCRIPTS are read per call,
# so they are not in it. `detect.sh` reads the record before the registry, so version
# and doctor name the root that runs, and the restart reader compares content against
# these lines rather than file times.
#
# EVERY START WRITES IT: startup, clear (a new id), resume and compact (the same id,
# rewritten with what is on disk now). No CLAUDE_PLUGIN_ROOT means the CLI did not
# launch this hook and there is no load to record. The record outlives its session on
# purpose: close-out reads the records of a run's sessions after they end, so it is not
# a sweep class. Written to a sibling and moved into place, so a link planted at the
# path is replaced, never written through, and a reader never sees half a record.
# Fails open like everything here: any step that cannot be done writes nothing.
ss_load_record() {
  local root top commit="" rec tmpf f cwd
  local -a files=()
  [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -n "${BIONIC_SID:-}" ] || return 0
  root="$(cd "$CLAUDE_PLUGIN_ROOT" 2>/dev/null && pwd -P)" || return 0
  [ -n "$root" ] && [ -d "$TMP" ] || return 0
  # A checkout of the plugin is a work tree whose top is the root or the root's parent
  # (`--plugin-dir <checkout>/payload`). A root merely inside some other repository —
  # a claude-home kept in git — is no checkout and lends the record no commit.
  top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" && top="$(cd "$top" 2>/dev/null && pwd -P)" || top=""
  if [ -n "$top" ] && { [ "$top" = "$root" ] || [ "$top/payload" = "$root" ]; }; then
    commit="$(git -C "$root" rev-parse HEAD 2>/dev/null)" || commit=""
  fi
  while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done <<SS_LOADED_FILES
$(cd "$root" 2>/dev/null && {
    [ -f hooks/hooks.json ] && printf '%s\n' hooks/hooks.json
    for d in skills agents; do [ -d "$d" ] && find -L "$d" -type f -name '*.md' 2>/dev/null; done
    [ -d commands ] && find -L commands -maxdepth 1 -type f -name '*.md' 2>/dev/null
  } | LC_ALL=C sort)
SS_LOADED_FILES
  # THE START CWD (wave-37 T5; D9, ADR-058): the physical directory the session started in, which
  # names the directory the CLI files its transcript under (lib/detect.sh `project_slug`). A session
  # started in a subdirectory or a worktree files it under a name other than the root's, and the words
  # reader (lib/said.sh) looks under this one too. After started=, so a header reader that stops at a
  # key it does not know (close-out.sh) has read root=, commit= and started= first.
  cwd="$(cd "${BIONIC_CWD:-$PWD}" 2>/dev/null && pwd -P)" || cwd=""
  rec="$TMP/loaded-$BIONIC_SID.state"
  tmpf="$TMP/.loaded-$BIONIC_SID.$$"
  {
    printf 'root=%s\n' "$root"
    [ -n "$commit" ] && printf 'commit=%s\n' "$commit"
    printf 'started=%s\n' "$(iso_now)"
    [ -n "$cwd" ] && printf 'cwd=%s\n' "$cwd"
    if [ "${#files[@]}" -gt 0 ]; then
      ( cd "$root" && if command -v shasum >/dev/null 2>&1; then shasum -a 256 -- "${files[@]}"; else sha256sum -- "${files[@]}"; fi ) 2>/dev/null \
        | while read -r h p; do printf '%s %s\n' "$h" "$p"; done
    fi
  } > "$tmpf" 2>/dev/null && mv -f "$tmpf" "$rec" 2>/dev/null || rm -f "$tmpf" 2>/dev/null
  return 0
}
ss_load_record

# ---------------------------------------------------------------- the three channels
#
# The env value is primary and the other two are witnesses (lib/session.sh, ledger
# S2). All three are PRINTED regardless, because the whole reason this line exists
# is that a reader cannot otherwise tell an agreement from a coincidence — and the
# probe's finding that they agree on a plain `/clear` is a measurement of one CLI
# build, not a guarantee.
ENV_SID="${CLAUDE_CODE_SESSION_ID:-}"
# THE PAYLOAD'S OWN VALUE, read here rather than taken from `BIONIC_SID`. They are
# different questions: `BIONIC_SID` is the RESOLVED id — the environment's, with the
# payload as a witness — and this is the witness itself, printed beside the other two
# so a reader can tell an agreement from a coincidence. Reading the resolved value
# into this slot would make the three channels agree by construction and report
# nothing.
PAYLOAD_SID="$(pfield .session_id)"
PID_SID=""
PIDFILE="$(claude_home)/sessions/$PPID.json"
if [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ] && command -v jq >/dev/null 2>&1; then
  PID_SID="$(jq -r '.sessionId // empty' "$PIDFILE" 2>/dev/null)"
fi

# ---------------------------------------------------------------- engagement
#
# An open run gates the whole roster/watch block behind this session's
# own consent to enter bionic (lib/run.sh `engaged_session`, T4/AC-11/AC-12).
# A session that never invoked canonical-sdlc gets exactly one line naming the
# plan and the skill — no roster dump, no watch report
# — because none of that operational detail is addressed to a bystander. A sid
# this hook cannot read is, like every other unreadable state here, NOT
# engaged: the safe direction is the quieter one.
#
# THE OPEN-RUN SET, not the single newest file (wave-session-bound-run S7,
# AC-5). `RUNS`/`N` decide the shape below: N=0 says nothing about runs; N=1
# names the run to a bystander and, since wave-23 T13 (critic C-4), prints the bind
# line to an engaged session that is not bound to it. N>=2 means a scan
# can no longer guess which run a session means, so a bystander gets the set
# (capped for display by `print_runs` below) plus the bind verb instead of one
# path picked by mtime, and an engaged
# session whose own binding does not resolve to one of them (unbound, or
# bound to a run that has since closed) gets the same listing prepended to
# today's engaged block rather than a silent guess — it is not exited early,
# because the roster/watch report still belongs to an engaged reader.
RUNS="$(open_runs "$BIONIC_ROOT")" || RUNS=""
N=$(printf '%s\n' "$RUNS" | grep -c '.')

# LIVE VS OPEN (spec AC-1/AC-3, S3). `live_runs` is a FILTER over `open_runs` — see
# scripts/lib/run.sh — so the header above still names the true OPEN count (`$N`,
# unchanged) while the listing itself shows only the LIVE subset; the quiet remainder is
# reported as one count, not a second listing, because a bystander acts on a live plan by
# name and on a quiet one only by knowing it exists at all. The filter is handed the open set
# read above, so every candidate is asked once per start, not once for each listing.
LIVE="$(live_runs "$BIONIC_ROOT" "$RUNS")" || LIVE=""
LIVE_N=$(printf '%s\n' "$LIVE" | grep -c '.')
QUIET=$((N - LIVE_N))

# ONE RENDERER FOR BOTH LISTINGS (review duplication D8b, S10b). The not-engaged block and
# the engaged-but-unbound block below print the same set for the same reason, and they were
# two copies of one `while read` loop inside one file — the shape that drifts.
#
# THE DISPLAY IS CAPPED; THE SET IS NOT (review performance P3, security F4). `open_runs`
# stays uncapped because it is a membership predicate with three callers, two of which need
# every member. What is bounded is what this hook PRINTS. A SessionStart hook's stdout is
# added to the new conversation's context on `startup`, `clear`, `resume` AND `compact`, and
# this repository's own tree already renders 60 paths — ~6.8 KB, roughly 1,700 tokens — of a
# list the reader acts on at most one line of. The set is newest-mtime-first, so the eight
# shown are the eight a session is most likely to mean, and the trailer says the rest are
# still reachable: `bind` takes any open plan by name, listed or not. The HEADER above each
# call still names the true count, so the cap never understates what is here.
#
# PATHS ARE RELATIVE TO THE DOCS BIONIC_ROOT. Every one of them shares the same long prefix (47
# characters here), and a listed line PASTES STRAIGHT INTO THE BIND VERB named on the header
# line above it: `bind` takes an operand that is absolute, project-root-relative or
# docs-root-relative, trying the project root first and the docs root when that misses
# (hooks/session-poker.sh, the `bind` arm, S10b phase 2). If the docs root cannot be read the
# paths are printed whole rather than mangled by a prefix strip that would eat a leading
# slash.
RUN_LIST_CAP=8
DOCS="$(docs_root "$BIONIC_ROOT" 2>/dev/null)" || DOCS=""
print_runs() {  # <newline-separated runs> -> the capped, docs-root-relative listing
  local runs="$1" total shown=0 _p
  total=$(printf '%s\n' "$runs" | grep -c '.')
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    shown=$((shown + 1))
    [ "$shown" -le "$RUN_LIST_CAP" ] || continue
    if [ -n "$DOCS" ]; then
      printf '  %s\n' "${_p#"$DOCS"/}"
    else
      printf '  %s\n' "$_p"
    fi
  done <<EOF
$runs
EOF
  if [ "$total" -gt "$RUN_LIST_CAP" ]; then
    printf '  … and %s more — bind names any open plan\n' "$((total - RUN_LIST_CAP))"
  fi
  return 0
}

# THE QUIET-COUNT LINE (AC-3). Printed right after whichever listing just ran, and only
# when the open/live difference is non-zero — a zero-quiet fixture must stay silent on
# this line (anti-vacuity, §13c of the suite).
print_quiet_line() {
  [ "$QUIET" -gt 0 ] || return 0
  printf 'bionic: %s quiet open run(s) — bind names any of them\n' "$QUIET"
}

# THE RUN'S FACTS, ONE FOLD PER START. The bound line's step and the resume door's pointer are
# the reader's `step` and `handoff` answers (lib/reader.sh) over lib/proof.sh's kept fold, so a
# step or a handoff only the run's log holds is the one printed, and a start after another pays
# no fold while the run's files are unchanged. At most one plan is asked: the bound run, or on a
# resume the newest open run. proof.sh is sourced here rather than wanted by the loader, so a
# library without it prints no step and no door and the rest of the report stands. A fold that failed is held as
# nothing and answers 2, and the line says the facts could not be read where the step or the door would stand.
SS_FACTS_PLAN=""; SS_FACTS=""; SS_ANSWER=""; SS_UNREAD="not read — the run's facts could not be read"
ss_ask() {  # <plan> <reader question function> -> SS_ANSWER, its answer over the plan's facts; 2 when they cannot be read
  SS_ANSWER=""
  if [ "$SS_FACTS_PLAN" != "$1" ]; then
    bionic_need proof.sh _proof_facts && _proof_reader_load || return 1
    SS_FACTS="$(_proof_facts "$1")" || { SS_FACTS=""; return 2; }
    SS_FACTS_PLAN="$1"
  fi
  SS_ANSWER="$( reader_facts() { printf '%s' "$SS_FACTS"; }; "$2" "$1" 2>/dev/null )"
}

# THE BOUND-RUN LINE (AC-21). `session_run` already resolved "this session's binding
# is to an open plan"; this only formats it. The plan path comes off the marker
# `session_run` read, not off `$RUNS`/`$LIVE`, because a bound plan is named by the
# ONE binding fact regardless of how many other runs are open. The step is the run's
# (`ss_ask` above), digits and `T` only, as the poker's own step display prints it.
print_bound_line() {  # <verdict "bound-open <plan>">
  local verdict="$1" bplan step relplan
  bplan="${verdict#bound-open }"
  if [ -n "$DOCS" ]; then relplan="${bplan#"$DOCS"/}"; else relplan="$bplan"; fi
  ss_ask "$bplan" reader_q_step
  [ $? -ne 2 ] || { printf 'bionic: bound to %s — current: %s\n' "$relplan" "$SS_UNREAD"; return 0; }
  step="$(printf '%s\n' "$SS_ANSWER" | sed -n 's/^n=//p' | tr -dc '0-9T')"
  printf 'bionic: bound to %s — current: %s\n' "$relplan" "$step"
  # THE STEP FILE, NAMED RATHER THAN INJECTED (wave-11 row 1b, design D1). The governing
  # skill is a core plus one file per step, and the core's own rule is to read `steps/N.md`
  # before acting at step N. Nothing enforces that — no hook can see whether a model read a
  # file — so this line does the one thing a hook honestly can: it puts the path in front of
  # the session at the moment the step is known, so the read is a glance away rather than a
  # lookup. `$HOOK_ROOT` is the tree this hook was launched from, the same root the adopt
  # line prints, so the path names a file
  # in the plugin that is actually running rather than in whichever one is installed.
  #
  # ONLY FOR A NUMERIC STEP. A non-numeric `current:` is refused (`NOT-RECORDED`, D2) and names no
  # step file, and a plan with no readable `current:` leaves `$step` empty; printing
  # `steps/T3.md` or `steps/.md` would send a reader at a path that does not exist.
  case "$step" in
    [0-9]|[0-9][0-9]) printf '  step file: %s/skills/canonical-sdlc/steps/%s.md\n' "$HOOK_ROOT" "$step" ;;
  esac
}

# THE ONE DOOR (wave-38 T13; D4, AC-3.3). The plan's ## Handoff is one pointer line, `handoff: <path> written <local
# time>` (T12, D23), to a file whose last line is `/bionic:canonical-sdlc <path>`: the command that binds, arms,
# adopts and recaps (`session-poker.sh resume`). After a clear, resume or compact, the bound plan's pointer, or
# unbound the newest open plan's, to a file whose first line is the kind line is printed where the engage or bind
# advice stood (and after the bound line). A startup has nothing to resume; a pointer to no file, or to a file
# without the kind line, is no door. The pointer is the run's latest handoff, the reader's `handoff` answer (`ss_ask`
# above): the plan's ## Handoff line, or a handoff the run's log holds.
SS_DOOR=""
case "${SOURCE:-}" in
  clear|resume|compact)
    if [ "${BIONIC_RUN_WORD:-}" = bound-open ] && [ -n "${BIONIC_RUN_PLAN:-}" ]; then SS_DOOR_PLAN="$BIONIC_RUN_PLAN"
    else SS_DOOR_PLAN="$(printf '%s\n' "$RUNS" | head -n 1)"; fi
    if [ -n "$SS_DOOR_PLAN" ] && [ -f "$SS_DOOR_PLAN" ]; then
      ss_ask "$SS_DOOR_PLAN" reader_q_handoff
      [ $? -ne 2 ] || SS_DOOR="bionic: the resume door is $SS_UNREAD; start again to be offered it"
      SS_DOOR_REL="$(printf '%s\n' "$SS_ANSWER" | sed -n 's/^path=//p')"
      case "$SS_DOOR_REL" in
        '') SS_DOOR_FILE="" ;;
        /*) SS_DOOR_FILE="$SS_DOOR_REL" ;;
        *)  SS_DOOR_FILE="$BIONIC_ROOT/$SS_DOOR_REL" ;;
      esac
      if [ -n "$SS_DOOR_FILE" ] && [ -f "$SS_DOOR_FILE" ] && [ ! -L "$SS_DOOR_FILE" ] \
         && [ "$(head -n 1 "$SS_DOOR_FILE" 2>/dev/null)" = "bionic-handoff/v1" ]; then
        SS_DOOR="bionic: resume with /bionic:canonical-sdlc $SS_DOOR_REL"
      fi
    fi ;;
esac

if [ "$N" -eq 1 ]; then
  PLAN="$RUNS"
  if [ "$BIONIC_ENGAGED" != 1 ]; then
    if [ -n "$SS_DOOR" ]; then printf '%s\n' "$SS_DOOR"
    else printf 'bionic: an open run exists here (%s) — invoke /bionic:canonical-sdlc to engage it\n' "$PLAN"; fi
    exit 0
  else
    case "$BIONIC_RUN_WORD" in
      bound-open) print_bound_line "$BIONIC_RUN_WORD $BIONIC_RUN_PLAN"; [ -z "$SS_DOOR" ] || printf '%s\n' "$SS_DOOR" ;;
      # THE BIND LINE FOR ONE RUN TOO (wave-23-fixit-1810 T13, critic C-4). This arm printed
      # nothing, on the S7 reasoning that "a lone open run is unambiguous, bound or not". D1
      # ended that: an unbound session's gates are inert, and engagement now leaves a session
      # unbound beside a run another live session holds (engage.sh, THE HELD RUN). So the
      # engaged-but-not-bound session is told here exactly what the N>=2 arm tells it — a
      # header line and one line per run — on stdout, the channel this hook's model reads.
      # The one run is listed whether live or quiet (`$RUNS`, not `$LIVE`): with a single
      # candidate there is no listing to keep short, and the bystander line above names it
      # the same way.
      #
      # THE HOLDER IS NAMED WHEN THERE IS ONE (wave-23-fixit-1810 T15, critic N-2). engage.sh
      # leaves a session unbound BECAUSE another live session holds the sole run, and tells it
      # so with a line naming the holder (A-T13.4) — that line is what keeps the offered bind
      # from being taken by reflex. On a resume or compaction the engagement-time context has
      # been summarized away and this line is all the model sees, so the bare verb here would
      # reproduce C-3 by hand. So the same question engage.sh asks is asked here, the same way:
      # `bind_holders` for the other markers naming this plan, intersected with the sweeper's
      # live set (`patrol_live_session_ids`, newline containment so a prefix id is not taken for
      # a live one). Asked only in this arm, and the live set only when a holder exists. Held:
      # one header line naming the holder's id prefix and binding only on resume of that run.
      # Unheld (no holder, or every holder dead): T13's line, unchanged.
      *)
        SS_HELD_BY=""
        if [ -n "$BIONIC_SID" ] && bind_holders "$BIONIC_ROOT" "$BIONIC_SID" "$PLAN" 2>/dev/null; then
          SS_LIVE=$(patrol_live_session_ids 2>/dev/null) || SS_LIVE=""
          while IFS= read -r _h; do
            [ -n "$_h" ] || continue
            case "
$SS_LIVE
" in
              *"
$_h
"*) SS_HELD_BY="$_h"; break ;;
            esac
          done <<< "$BIND_HOLDERS"
        fi
        if [ -n "$SS_DOOR" ]; then
          printf '%s\n' "$SS_DOOR"
        elif [ -n "$SS_HELD_BY" ]; then
          printf 'bionic: 1 open run exists here and live session %s holds it; this session is not bound to it — bind with: bash %s/hooks/session-poker.sh bind <plan> only if this session is resuming that run\n' \
            "${SS_HELD_BY:0:8}" "$HOOK_ROOT"
        else
          printf 'bionic: 1 open run exists here and this session is not bound to it — bind with: bash %s/hooks/session-poker.sh bind <plan>\n' \
            "$HOOK_ROOT"
        fi
        print_runs "$RUNS"
        ;;
    esac
  fi
elif [ "$N" -ge 2 ]; then
  if [ "$BIONIC_ENGAGED" != 1 ]; then
    if [ -n "$SS_DOOR" ]; then printf '%s\n' "$SS_DOOR"
    else printf 'bionic: %s open runs exist here — invoke /bionic:canonical-sdlc, then bind the one you mean with: bash %s/hooks/session-poker.sh bind <plan>\n' \
      "$N" "$HOOK_ROOT"; fi
    print_runs "$LIVE"
    print_quiet_line
    exit 0
  else
    case "$BIONIC_RUN_WORD" in
      bound-open) print_bound_line "$BIONIC_RUN_WORD $BIONIC_RUN_PLAN"; [ -z "$SS_DOOR" ] || printf '%s\n' "$SS_DOOR" ;;
      *)
        if [ -n "$SS_DOOR" ]; then printf '%s\n' "$SS_DOOR"
        else printf 'bionic: %s open runs exist here and this session is not bound to one — bind with: bash %s/hooks/session-poker.sh bind <plan>\n' \
          "$N" "$HOOK_ROOT"; fi
        print_runs "$LIVE"
        print_quiet_line
        ;;
    esac
  fi
fi

AGREE="agree"
_first=""
for _v in "$ENV_SID" "$PAYLOAD_SID" "$PID_SID"; do
  [ -n "$_v" ] || continue
  if [ -z "$_first" ]; then _first="$_v"; continue; fi
  [ "$_v" = "$_first" ] || AGREE="DIVERGE"
done

# ---------------------------------------------------------------- predecessor rosters
#
# OPEN ROWS ARE COUNTED BY NAME, not by line: the roster is append-only and one
# dispatch writes a row per status transition (`intended`, `identified`,
# `confirmed`), so counting lines would multiply every agent by however far it got.
# A name is CLOSED only by the one close predicate every wall asks (epic-23 wave-20
# T17, D10; T2's carry-over): an `ack` in that session's sweeper ledger stamped after
# the name's latest launch. This block used to close a name on a
# `landing-swept/v1|…|state=MET` marker, or on any ack of it ever, so after a /clear
# it could tell the operator a predecessor held nothing open while the dispatch wall
# still refused its names — or the reverse, for a name acked and dispatched again.
# The count is `roster_open_counts` (lib/roster.sh), which runs `roster_open_names`'
# own awk text over every roster in the manifest below.
#
# ONE AWK PROCESS FOR EVERY PREDECESSOR ROSTER, not one per file (REQ-6, carry-over
# P9). The per-file shape below — `for RF in …; do N="$(open_rows "$RF" …)"; done` —
# forked an `awk` per roster file with no bound on how many can accumulate under
# `.bionic/tmp`: measured ~10.4s at 400 dead sessions against the CLI's 10s hook
# timeout (2,041ms already at 14 files — subprocess-per-file cost dominates well
# before any file count a real project ever carries deliberately). The FILTERING
# loop below stays pure bash builtins (glob + `[ -f ]`/`[ -L ]`, no fork), and
# builds a tab-separated manifest of every SURVIVING (osid, roster, ledger) triple;
# ONE awk invocation (`roster_open_counts`) then walks the manifest and, for each
# row, reads that roster file and its ledger with `getline < file` (awk's own
# multi-file idiom, not a subprocess), its per-file sets local to one function call —
# the exact per-file reset the old per-invocation `awk` got for free by exiting.
# Output is unchanged: one `osid<TAB>count<TAB>roster-path` line per roster with at
# least one open row, read back below into the same `ROSTERS` text as today.
# A PARAMETER EXPANSION, NOT A FUNCTION CALLED THROUGH `$(...)` (T16, follow-up
# to T6, AC-6.1). `sid8` used to be invoked as `$(sid8 "$OSID")` at both its
# call sites below, each inside a loop that runs once per predecessor — a COMMAND
# SUBSTITUTION forks a subshell to capture ANY command's stdout, even a plain shell
# function doing one `printf`. Measured (a synthetic 401-iteration loop, `time`):
# ~0.20s forking per call vs ~0.003s for the equivalent `${var:0:8}` substring — a
# ~70x difference that, at 401 predecessors across the two loops below, accounted for
# a real chunk of AC-6.1's remaining latency once the sweep-side costs were fixed.
# `${1:0:8}` is `sid8`'s own body in expansion form: a substring never errors short
# (an id under 8 chars returns however many it has, exactly like `printf '%.8s'`), so
# nothing about the OUTPUT changes — only the fork is gone. Kept as a function (never
# called through this file's two hot loops) for any future one-off caller that wants
# the name.
sid8() { printf '%.8s' "${1:-}"; }

ROSTER_MANIFEST=""
for RF in "$TMP"/roster-*.state; do
  [ -f "$RF" ] || continue
  [ -L "$RF" ] && continue        # symlinks are not followed, as everywhere in tmp
  OSID="${RF##*/}"; OSID="${OSID#roster-}"; OSID="${OSID%.state}"
  [ -n "$OSID" ] || continue
  if [ -n "$BIONIC_SID" ] && [ "$OSID" = "$BIONIC_SID" ]; then continue; fi
  LEDGER="$TMP/sweeper-$OSID.state"
  if [ ! -f "$LEDGER" ] || [ -L "$LEDGER" ]; then LEDGER=""; fi
  ROSTER_MANIFEST="${ROSTER_MANIFEST}${OSID}	${RF}	${LEDGER}
"
done

ROSTERS=""
if [ -n "$ROSTER_MANIFEST" ]; then
  ROSTER_RAW="$(printf '%s' "$ROSTER_MANIFEST" | roster_open_counts)"
  if [ -n "$ROSTER_RAW" ]; then
    # `$'\t'`, NOT `$(printf '\t')` (wave-35 T11): a `while` re-runs its condition every
    # step, so the substitution forked once per predecessor roster — the T16 class above,
    # counted by tests/session-start.test.sh 16.2b at 8 and at 400.
    while IFS=$'\t' read -r OSID N RF; do
      [ -n "$OSID" ] || continue
      ROSTERS="${ROSTERS}  ${OSID:0:8} — $N open row(s) — ${RF##*/}
"
    done <<EOF
$ROSTER_RAW
EOF
  fi
fi

# THE GROUP IS CHECKED, NEVER ASSUMED (T23, the same fix detect.sh took at T22).
# A DELIBERATE DUPLICATE of `_detect_bound_kill` / `_detect_bound_kill_tree` in
# payload/scripts/lib/detect.sh, which is the ORIGINAL and carries the full
# reasoning and the measurements. Copied rather than sourced for the reason the
# header below already gives for the runner itself: this hook's loader wants
# only the libraries its report reads (BIONIC_LIB_WANT), and one more required
# library would fail the whole DETECTOR closed on a machine that lacks it, to buy a kill
# only the one `sweep` call needs. The two copies are meant to stay in step —
# change one and change the other.
#
# WHY THE CHECK EXISTS. `set -m` ASKS the kernel for a new process group; where
# that is refused the job stays in THIS HOOK's group, and `kill -TERM -$pid` then
# names a group that does not exist. Measured on a stand-in for that state (T22):
# the group kill fails, the old `|| kill -TERM $pid` fallback TERMs the direct
# child only, and the grandchild the group signal exists to reach goes on running.
# `sweep` is `bash session-poker.sh`, which forks, so that grandchild is not
# hypothetical. Both helpers run on the TIMEOUT path only: the ordinary sweep
# finishes and never reaches an external `ps`.
ss_bound_kill_tree() {  # <pid> — TERM <pid> and every descendant of it
  local root="$1" table frontier next generations=0 victims victim
  # `-A` is the POSIX spelling both BSD and procps answer; one snapshot is walked
  # generation by generation rather than one `ps` per level. The generation cap is
  # a safety rail on a table read from outside this script, not a depth anyone
  # reaches.
  table="$(ps -Ao pid=,ppid= 2>/dev/null)"
  victims="$root"; frontier="$root"
  while [ -n "$frontier" ] && [ "$generations" -lt 16 ]; do
    next="$(printf '%s\n' "$table" | awk -v parents="$frontier" \
      'BEGIN { n = split(parents, a, " "); for (i = 1; i <= n; i++) P[a[i]] = 1 }
       P[$2] { print $1 }')"
    [ -n "$next" ] || break
    victims="$victims $next"
    frontier="$next"
    generations=$((generations + 1))
  done
  # The root first, so a job still spawning cannot outrun the sweep.
  for victim in $victims; do kill -TERM "$victim" 2>/dev/null; done
  return 0
}

ss_bound_kill() {  # <pid> — stop the bounded sweep and its children, group or no group
  local pid="${1:-}" pgid
  [ -n "$pid" ] || return 0
  pgid="$(ps -o pgid= -p "$pid" 2>/dev/null)"
  pgid="${pgid//[!0-9]/}"
  # EMPTY means `ps` could not answer, not that there is no group — on a machine
  # without it the group signal is still the right first move, and a failure there
  # is itself the evidence that no group was ever created.
  if [ -z "$pgid" ] || [ "$pgid" = "$pid" ]; then
    kill -TERM "-${pid}" 2>/dev/null && return 0
  fi
  ss_bound_kill_tree "$pid"
  return 0
}

# BOUNDED, THE SAME MECHANISM detect_bounded USES (payload/scripts/lib/detect.sh):
# a background job of its own process group, a poll that signals the whole
# DESCENDANT SET when the bound is up (never just the direct child — a grandchild
# inherits the caller's own stdout pipe otherwise; `ss_bound_kill` above signals
# the group where the job really leads one and walks the process tree where it
# does not), and stdout captured to a file this shell alone reads
# afterwards so a run that outlives its bound can never hold this hook's own
# stdout open. Kept LOCAL rather than sourced from detect.sh: this hook's loader
# wants only the libraries its report reads (BIONIC_LIB_WANT above), and one more
# required library would fail the whole DETECTOR closed on a machine that lacks it, to buy
# a bound only the one `sweep` call below needs.
# POLL GRANULARITY IS 0.1s, NOT 1s (T16, follow-up to T6, AC-6.1). The
# bound (`limit`, whole seconds — the external contract `BIONIC_SWEEP_BOUND_SECONDS`
# keeps) used to be measured by a `sleep 1`-per-tick counter: a sweep that actually
# finishes in, say, 1.1s is invisible to a `kill -0` check that only runs once a
# second, so this loop waited out a full SECOND boundary it happened to straddle —
# up to ~1s of pure polling latency added on top of the sweep's own real duration,
# confirmed by `EPOCHREALTIME` checkpoints either side of each `sleep` (a 400-dead
# fixture: the sweep itself measured ~1s once REQ-6/T16's other fixes landed, but
# this loop still cost ~2s end to end). `SS_POLL_TICKS_PER_SEC` scales the SAME
# `limit` into finer ticks so the bound is still honoured in whole seconds
# (tests/session-sweep.test.sh §7e's hang case only asserts "well under 30s", never a
# specific tick count) while completion is now detected within one 0.1s window
# instead of one whole second.
SS_POLL_TICKS_PER_SEC=10
ss_bounded_sweep() {  # <poker path> <bound seconds> [sweep flag...] -> stdout; rc mirrors sweep, 124 on timeout
  local poker="$1" limit="$2" pid ticks=0 max_ticks rc out had_monitor
  shift 2
  max_ticks=$(( limit * SS_POLL_TICKS_PER_SEC ))
  out="${TMPDIR:-/tmp}/bionic-sweep.$$.out"
  : > "$out" 2>/dev/null || out="/dev/null"
  case "$-" in *m*) had_monitor=yes ;; *) had_monitor=no ;; esac
  # THE FORK'S OWN DIAGNOSTICS ARE NOT THIS HOOK'S OUTPUT (T23, detect.sh's T22 fix
  # one layer up). `set -m` asks the kernel for a new process group, and where that
  # is refused bash prints its own `child setpgid (N to N): Operation not permitted`
  # from inside the fork. That line is bash's, not this repo's — and this is a
  # SessionStart hook, whose stderr is the user's screen at the top of a session, so
  # it would land in front of the user with nothing on the page to explain it.
  #
  # SO THE FORK GETS ITS OWN STDERR AND THE HOOK KEEPS ITS REAL ONE. The braces run
  # with stderr on /dev/null — the only writer there is the shell's job-control
  # machinery, measured at 0 bytes otherwise under both bash 3.2 and bash 5 (T22) —
  # while fd 9 keeps this hook's REAL stderr reachable inside the compound. That is
  # what makes the discard SURGICAL rather than a blanket `exec 2>/dev/null`, which
  # would also swallow lib/session.sh's divergence warning and every other line this
  # hook legitimately writes to the user.
  #
  # ONE DELIBERATE DIFFERENCE FROM detect.sh. There the probe's own stderr is carried
  # into the child on fd 9 (`2>&9`), because a probe's error text belongs to its
  # caller. Here the sweep's stderr has always been discarded at the job itself and
  # it STAYS discarded: putting a `sweep` subprocess's stderr onto a SessionStart
  # hook's stderr is the very class of noise this change removes, and the sweep
  # already reports failure the way this hook reads it — through the exit status
  # below and the sweep-failed marker. fd 9 is CLOSED in the child for the same
  # reason the out-file exists: a sweep that outlives its bound must not be left
  # holding any of this hook's own streams open.
  { set -m
    ( cd "$BIONIC_ROOT" 2>/dev/null && bash "$poker" sweep "$@" ) </dev/null >"$out" 2>/dev/null 9>&- &
    pid=$!
    [ "$had_monitor" = "yes" ] || set +m
  } 9>&2 2>/dev/null
  if command -v sleep >/dev/null 2>&1; then
    while kill -0 "$pid" 2>/dev/null; do
      if [ "$ticks" -ge "$max_ticks" ]; then
        ss_bound_kill "$pid"
        wait "$pid" 2>/dev/null
        [ -s "$out" ] && cat "$out"
        rm -f "$out" 2>/dev/null
        return 124
      fi
      sleep 0.1
      ticks=$((ticks + 1))
    done
  fi
  wait "$pid"; rc=$?
  [ -s "$out" ] && cat "$out"
  rm -f "$out" 2>/dev/null
  return "$rc"
}

# ---------------------------------------------------------------- predecessor watches
#
# THE WATCH RECORD. hooks/watch.sh keeps `watch-<sid>.state` for each session it watches, and
# `watch_state` (lib/patrol.sh) reads it by the one alive rule: a predecessor still watching runs passes over a
# conversation that is gone until it sees the clear, one that stopped died without a word, and one resting ended on
# purpose. This session's own record is not listed: its watcher starts beside this hook.
WATCHES=""
for WF in "$TMP"/watch-*.state; do
  [ -f "$WF" ] && [ ! -L "$WF" ] || continue
  OSID="${WF##*/}"; OSID="${OSID#watch-}"; OSID="${OSID%.state}"
  [ -n "$OSID" ] || continue
  if [ -n "$BIONIC_SID" ] && [ "$OSID" = "$BIONIC_SID" ]; then continue; fi
  WS="$(watch_state "$BIONIC_ROOT" "$OSID" 2>/dev/null)" || continue
  case "$WS" in
    watching\ *) WS="watching (pid $(printf '%s' "${WS#watching }" | cut -d' ' -f1))" ;;
    stopped\ *)  WS="stopped without a word (pid ${WS#stopped })" ;;
    resting\ *)  WS="resting (${WS#resting })" ;;
  esac
  WATCHES="${WATCHES}  ${OSID:0:8} — watch ${WS}
"
done

# ---------------------------------------------------------------- legacy symlinks
#
# NARROWED (AC-11/AC-7.1, A-orch-24, wave-13-fixit-180). D7 brought `.bionic`
# aliasing back on purpose: `spawn-worktree.sh create` now plants
# `<wt>/.bionic -> <main-root>/.bionic` so a plain relative write from inside a
# worktree lands in the one project memory. A link is worth reporting here only
# when it resolves somewhere OTHER than that main root — `worktree_legacy_links`
# (lib/worktree.sh) is the one predicate that tells the two apart, the same one
# doctor.sh's own report now calls, so neither surface keeps a second copy of
# the comparison.
LINKS=""
while IFS= read -r LN; do
  [ -n "$LN" ] || continue
  LINKS="${LINKS}  ${LN#"$BIONIC_ROOT"/} -> $(readlink "$LN" 2>/dev/null)
"
done < <(worktree_legacy_links "$BIONIC_ROOT")

# ---------------------------------------------------------------- the silent auto-sweep
#
# THE ONE WRITE THIS HOOK NOW MAKES (REQ-R2, ticket-30, ratified 2026-09-07). Every
# comment above this point still describes the DETECTOR half faithfully — the
# roster/stamp/symlink report above reads nothing differently for this — but
# "arms nothing, deletes nothing, adopts nothing and writes nothing" (this file's
# own header, above) is no longer the whole of what runs here. session-poker.sh's
# sweep verb carries a 1.5.1 decision that auto-sweeping was REJECTED (D-5): "a
# hook that cleared [residue] at engagement would delete the evidence of the
# thing it was helping with." REQ-R2 reverses that ruling for THIS ONE HOOK, on
# THIS ONE TRIGGER — SessionStart, never engagement — because the field defect
# (ticket-30) is the opposite failure: nothing ever swept the residue at all,
# doctor could prove a project's predecessor sessions dead and name no way to
# clear them, and setup offered nothing for it. `sweep`'s own deletion logic is
# untouched (A-5) — this hook only ever decides WHETHER to invoke it; it never
# deletes a file itself.
#
# THE AGE GRACE IS THE VERB'S, AND IT IS PER SESSION (epic-23 wave-16 REQ-8, AC-8.1/8.2).
# `sweep` judges liveness alone by default — a session dead one second after `/clear` re-keys
# its pid file is exactly as dead as one a week stale — which is right for a verb a human runs
# on purpose. A hook that fires on every conversation start is not that: the predecessor
# roster this same run just reported above would be deleted before anyone could act on it. So
# the call asks for `--window`, and the verb defers a dead session whose own newest file is
# younger than one Patrol interval — that session alone.
#
# THIS HOOK USED TO ASK THE QUESTION ITSELF, AND ASKED IT OF THE WHOLE DIRECTORY. It stat-ed
# every dead session's every file and, if ANY of them was younger than the interval, skipped
# calling `sweep` AT ALL that run — so one five-minute-old corpse kept every other dead
# session's residue, however ancient, for the NEXT session start, which had the same corpse
# problem. On a project that `/clear`s every few minutes there is always a file under one
# interval old: measured in this repo on 2026-09-19 as sixteen `engaged-*` and fifteen
# `roster-*` files beside one live session, the oldest two days stale (seed B, item B9). The
# verb has always had the finer answer and this hook simply never asked for it.
#
# SO THE GATE IS GONE, NOT REPLACED. One reader of "who is young" instead of two, in the
# process that does the deleting. tests/session-sweep.test.sh §7j builds the mixed batch the
# old shape failed — ancient dead, young dead, live, in one directory — and §7c holds the
# per-session deferral from the other side.
#
# SILENT ON SUCCESS, ONE LINE ON FAILURE (AC-R2.4, scope constraint). `sweep`'s
# own exit codes: 0 is swept-or-nothing-to-sweep, 1 is "every session here is
# LIVE" — an ordinary, frequent, entirely healthy answer and not a fault — and 2
# is a refusal (a `.bionic/tmp` sweep will not delete inside, or a usage error
# this hook cannot cause). Only 2, or this wrapper's own 124 on a bounded
# timeout, counts as failure: a marker is left and this one line prints. 0 and 1
# are silent and clear any marker a PAST failure left, so a transient problem
# stops being reported the moment sweeping actually works again.
SWEEP_FAIL_LINE=""
if [ -d "$TMP" ] && [ ! -L "$TMP" ]; then
  SS_POKER="$HOOK_ROOT/hooks/session-poker.sh"
  if [ -f "$SS_POKER" ]; then
    SS_BOUND="${BIONIC_SWEEP_BOUND_SECONDS:-10}"
    # `--window` IS THE WHOLE OF THIS HOOK'S AGE POLICY NOW (REQ-8): everything the gate
    # above used to compute for itself is one flag to the verb that does the deleting.
    ss_bounded_sweep "$SS_POKER" "$SS_BOUND" --window >/dev/null
    SS_RC=$?
    SWEEP_MARKER="$TMP/sweep-failed.state"
    case "$SS_RC" in
      0|1)
        rm -f "$SWEEP_MARKER" 2>/dev/null
        ;;
      *)
        printf 'sweep-failed/v1|at=%s|rc=%s\n' \
          "$(iso_now)" "$SS_RC" > "$SWEEP_MARKER" 2>/dev/null
        SWEEP_FAIL_LINE="bionic: the automatic dead-session sweep failed (rc=${SS_RC}) — run /bionic:doctor for the fix"
        ;;
    esac
  fi
fi

# ---------------------------------------------------------------- the block
#
# SILENCE IS THE DEFAULT. Three findings and one verdict; if every finding is empty and the
# three channels agree, there is nothing to act on and the hook says nothing at all. A sweep
# failure is worth one line on any start: it is the one write this hook can make, and
# a write that fails silently is worse than the noise of saying so.
if [ -z "$ROSTERS" ] && [ -z "$WATCHES" ] && [ -z "$LINKS" ] && [ "$AGREE" = "agree" ]; then
  [ -n "$SWEEP_FAIL_LINE" ] && printf '%s\n' "$SWEEP_FAIL_LINE"
  exit 0
fi

# The title line names the subject and the source, because this text lands in a
# context window with no attribution: without it the model sees a bare `session-id:`
# line and cannot tell which tool said it or why.
printf 'bionic session-start (source: %s) — state the previous conversation left on this project.\n' \
  "${SOURCE:-unknown}"
printf 'session-id: env=%s payload=%s pidfile=%s — %s\n' \
  "${ENV_SID:-absent}" "${PAYLOAD_SID:-absent}" "${PID_SID:-absent}" "$AGREE"
if [ -n "$ROSTERS" ]; then
  printf 'predecessor rosters:\n%s' "$ROSTERS"
fi
if [ -n "$WATCHES" ]; then
  printf 'predecessor watches:\n%s' "$WATCHES"
fi
if [ -n "$LINKS" ]; then
  printf 'legacy .bionic symlinks:\n%s' "$LINKS"
fi
# THE PREDECESSOR BLOCK'S ONE STEP: `adopt` takes the rows listed above onto this session before
# its first dispatch.
printf 'adopt: bash %s/hooks/session-poker.sh adopt — before the first dispatch\n' "$HOOK_ROOT"
[ -n "$SWEEP_FAIL_LINE" ] && printf '%s\n' "$SWEEP_FAIL_LINE"

exit 0
