#!/bin/bash
# THE START GATE — epic-15 wave-01R.
#
# PreToolUse|Agent. On every subagent dispatch, during an active wave: refuse
# unless a this-session environment attestation is present, naming the exact
# fix command. Outside an active wave, or on any ambiguity along the way,
# the dispatch passes through untouched — this gate never blocks a machine
# that isn't running a wave, and never blocks on a question it cannot
# answer cleanly.
#
# Why a gate at all: the environment check (hooks/preflight-probe.sh) proves,
# once per session, that a fleet has what it needs to survive — a
# credential, a writable repo, a writable state directory. A fleet inherits
# its environment and dies collectively if that proof never happened
# (design/orchestrator-subagent-coordination.md §3.4 "Starting"). This
# gate's entire vocabulary is: read the attestation, allow silently or
# refuse loudly naming the fix. It parses no check detail — the
# attestation's EXISTENCE, keyed to THIS session, is the whole verdict
# (§4 "The start gate"); this gate never re-derives or second-guesses what
# the producer already decided.
#
# Attestation filename is per-session (design D-5, slice 4/2):
#     .bionic/tmp/preflight-<this session's session_id>.state
# A foreign session's attestation — however fresh — simply is not this file, so it is
# never read at all; only THIS session's own filename is ever consulted, and the legacy
# shared .bionic/tmp/preflight.state slot is not consulted either.
#
# FAIL DIRECTIONS (TDD §7, pinned by hooks/dispatch-preflight.test.sh):
#   - not an Agent-tool call                            -> pass, silent  (A7 relevance hoist)
#   - cwd/repo unresolvable                              -> pass, silent (ambiguity)
#   - no active wave                                     -> pass, silent (nothing to decide)
#   - payload carries no session_id, or one that is not
#     shaped like one (anything outside [A-Za-z0-9_-])    -> pass, silent (§7 table: start=open)
#   - attestation present and keyed to THIS session_id    -> pass, silent
#   - attestation missing, unreadable, symlinked, or
#     keyed to a different session (foreign)              -> AUTO-RUN the probe, then
#     (the combined preflight, epic-16 wave-02 R5)           pass on what it finds
#   - the auto-run probe REFUSES                          -> REFUSE, quoting the probe
#     (the environment is genuinely broken; fail closed)     and naming the fix command
#   - brief names no deliverable and carries no waiver    -> REFUSE, naming both
#     (the absent-deliverable wall, user-directed post-w4)   the fix and the waiver
#   - brief names a deliverable only as an unfilled       -> pass, WARN, and infer the
#     template (epic-16 wave-02 R4)                          row from the agent name
#   - brief names a deliverable that resolves OUTSIDE the -> REFUSE, naming the
#     repo root (the containment wall, Step-6 review S-2)    path and where it lands
#
# TWO ROOTS THIS FILE NEVER RE-DERIVES (epic-16 wave-02 R9): the project root comes
# from `resolve_project_root` (the main repository, never a worktree or the shell's
# cwd), and every state path hangs off it — so the probe on the other side of the
# combined preflight writes where this gate reads.
#
# Exit code 2 = block the tool call entirely in Claude Code hooks.
# [WALL: hooks/dispatch-preflight.test.sh]
#
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

set -uo pipefail

PREFLIGHT_CMD="bash ~/.claude/hooks/preflight-probe.sh"

INPUT=$(cat)
_jq() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

# ---------- relevance first (checklist A7): the cheapest possible check,
# before any git resolution or plan-directory walk. Anything that isn't a
# subagent dispatch is none of this gate's business. ----------
TOOL_NAME=$(_jq '.tool_name')
[ "$TOOL_NAME" = "Agent" ] || exit 0

# ---------- ambiguity: cannot even locate the repo -> OPEN, silent ----------
CWD=$(_jq '.cwd')
[ -n "$CWD" ] || exit 0
git -C "$CWD" rev-parse --show-toplevel >/dev/null 2>&1 || exit 0

# ---------- the PINNED root (epic-16 wave-02, R5/R9) ----------
#
# DELIBERATELY DUPLICATED, byte for byte, from hooks/canonical-sdlc-governing-skill.sh —
# which holds the origin, with a second twin in the evidence gate. Same reason as
# resolve_docs_root below: a sourced library the installer misses is a silently inert
# wall, so these hooks carry copies and an agreement suite holds them together.
#
# WHY IT REPLACED `rev-parse --show-toplevel` HERE. That answers with the WORKTREE root,
# and every path this gate owns hangs off the answer: the attestation it reads, the
# roster it appends, the containment wall it measures deliverables against. The probe on
# the other side of the combined preflight below resolves its root the same way, and two
# scripts that disagree about which `.bionic` is real produce the exact failure R9 names
# — a probe writing an attestation the gate then cannot find, and a roster that dies with
# the worktree. `--git-common-dir` maps a worktree back onto the main repository, so both
# sides land on one address space. On an ordinary checkout the two answers are identical,
# which is why nothing outside a worktree changes.
resolve_project_root() {  # $1=a path whose repo we want; $2=fallback (default pwd)
  local d common root
  d=$(dirname "$1")
  while [ ! -d "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ] && [ -n "$d" ]; do
    d=$(dirname "$d")
  done
  if common=$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
    dirname "$common"
    return
  fi
  if common=$(git -C "$d" rev-parse --git-common-dir 2>/dev/null); then
    case "$common" in
      /*) root=$(dirname "$common") ;;
      *)  root=$(cd "$d" 2>/dev/null && cd "$(dirname "$common")" 2>/dev/null && pwd -P) ;;
    esac
    if [ -n "$root" ]; then
      printf '%s\n' "$root"
      return
    fi
  fi
  printf '%s\n' "${2:-$(pwd)}"
}

REPO=$(resolve_project_root "$CWD/." "$CWD")
[ -n "$REPO" ] && [ -d "$REPO" ] || exit 0

# ---------- active-wave detection ----------
# DELIBERATELY DUPLICATED, byte for byte where the logic overlaps, from
# hooks/stop-guard.sh's copy (stop-guard and the evidence gate hold the
# others). A shared library is rejected by design (TDD §9): a sourced file
# the installer misses is a silently inert wall. The copies are held
# together by the N-way agreement suite (slice 4/6), which drives all three
# including the evidence gate as the origin.
resolve_docs_root() {
  local proj="$1" config="$1/.bionic/config.yaml" override
  if [ -f "$config" ]; then
    override=$(grep -E '^[[:space:]]*docs-root[[:space:]]*:' "$config" 2>/dev/null \
      | head -1 \
      | sed -E 's/^[[:space:]]*docs-root[[:space:]]*:[[:space:]]*//' \
      | sed -E "s/^['\"]//;s/['\"]\$//" \
      | sed -E 's/[[:space:]]+$//')
    if [ -n "$override" ]; then
      case "$override" in
        /*) echo "$override" ;;
        *)  echo "$proj/$override" ;;
      esac
      return
    fi
  fi
  echo "$proj/.bionic/docs"
}

DOCS_ROOT=$(resolve_docs_root "$REPO")
# The docs root as a BRIEF would spell it. `resolve_docs_root` always answers with
# an absolute path, and the record/-inference below compares it against tokens
# lifted verbatim out of dispatch prose — where a path under this repo is written
# repo-relative essentially always. Without this form the `<docs-root>/record/`
# prefix (slice 4/4's third accepted form) matched nothing a real brief contains
# whenever `docs-root:` was overridden: the wall refused briefs naming a perfectly
# good record/ artifact, and the branch was inert rather than wrong-looking. With
# no override this is exactly `.bionic/docs`, so the default path is unchanged.
case "$DOCS_ROOT" in
  "$REPO"/*) DOCS_ROOT_REL="${DOCS_ROOT#"$REPO"/}" ;;
  *)         DOCS_ROOT_REL="" ;;
esac
PLAN=""
for d in "$DOCS_ROOT/plans" "$DOCS_ROOT/incidents"; do
  [ -d "$d" ] || continue
  while IFS= read -r -d '' f; do
    if [ -z "$PLAN" ] || [ "$f" -nt "$PLAN" ]; then PLAN="$f"; fi
  done < <(find "$d" -maxdepth 2 -type f -name '*.md' -print0 2>/dev/null)
done
[ -n "$PLAN" ] && [ -f "$PLAN" ] || exit 0

# The run-state marker, read exactly as the evidence gate and stop-guard read
# it: the fence-aware ## SDLC State section, then its `current:` value.
# Line endings TRANSLATED, never deleted — see .claude/rules/hook-authoring.md
# (a CR-only file deleted by `tr -d '\r'` collapses to one line and every
# line-anchored match misses, going silently inert with a wave live).
CURRENT=$(awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$PLAN" 2>/dev/null | awk '
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  /^## SDLC State/ { flag=1; next }
  /^## / { flag=0 }
  flag' \
  | grep -E '^[[:space:]]*current[[:space:]]*:' \
  | head -1 \
  | sed -E 's/^[[:space:]]*current[[:space:]]*:[[:space:]]*//' \
  | tr -d '[:space:]')
echo "$CURRENT" | grep -qE '^([0-9]+[ab]?|T[0-9]+)$' || exit 0

# ---------- a wave is active: this IS a decision ----------

# Payload missing its session key: the §7 fail-direction table names this
# exact ambiguity and pins the start-side direction as open, silent — we
# cannot prove whose dispatch this is, so we cannot refuse it as foreign.
PAYLOAD_SID=$(_jq '.session_id')
[ -n "$PAYLOAD_SID" ] || exit 0

# ...and the same direction for a session key that is not SHAPED like one. Every
# state path this gate reads or writes is built by interpolating this value —
# preflight-<sid>.state, roster-<sid>.state — and the symlink guards below check
# $STATE_DIR and those exact filenames, so a key carrying a path separator leaves
# the guarded directory entirely rather than tripping a guard (Step-6 review S-4).
# Session ids are harness-minted UUIDs, so this refuses nothing real; it is the
# belt every other payload value on these paths already wears via sanitize(),
# taken in the one direction §7 assigns an unreadable session key — pass, silent.
case "$PAYLOAD_SID" in *[!A-Za-z0-9_-]*) exit 0 ;; esac

deny() {  # <reason line>...
  echo "BLOCKED: this subagent start needs a working environment — a wave is active." >&2
  echo "" >&2
  local line
  for line in "$@"; do echo "$line" >&2; done
  echo "" >&2
  echo "Fix: ${PREFLIGHT_CMD}" >&2
  echo "Then retry the dispatch." >&2
  exit 2
}

STATE_FILE="$REPO/.bionic/tmp/preflight-${PAYLOAD_SID}.state"

# A symlink ANYWHERE on the attestation path is never followed — a hostile repo
# can AIM or CLOSE this wall but must not be able to OPEN it by planting content
# at a path it controls (design §8). The DIRECTORY levels matter as much as the
# file: `.bionic/tmp` pointed at a tree holding a valid same-session attestation
# (one session working across a repo and its `.worktrees/` siblings produces
# exactly that) would otherwise admit a dispatch on an environment proof taken
# for a different tree — and this gate deliberately parses no check detail (§4),
# so the record's own `repo=` field never exposes the mismatch. Checklist A3
# names this class; it was discharged for the WRITE path only. The sibling stop
# gate refuses at all three levels (hooks/stop-guard.sh's state_paths()); these
# are the same three.
#
# Read by KEY, never by position (checklist A6) — mirrors the producer's own
# readback. This gate parses no check detail beyond the session key: the
# attestation's existence, keyed to THIS session, is the whole verdict
# (§4 "The start gate").
#
# So the record's `version=` line is written and never read here, while the
# observation schema's version IS enforced by its reader, which refuses loudly on
# an unknown one. The asymmetry is deliberate, not drift (Step-6 review D5): each
# side follows the direction §7 assigns it. A start gate that refused an
# unrecognised attestation version would be a false block on every session after
# a schema bump — the expensive direction here — while an unreadable observation
# record must refuse a stop, because that side's ambiguity is what the wall is
# for. Recorded in the spec's ownership table beside both schema rows.
attested() {
  [ ! -L "$REPO/.bionic" ] && [ ! -L "$REPO/.bionic/tmp" ] \
    && [ ! -L "$STATE_FILE" ] && [ -f "$STATE_FILE" ] || return 1
  local sid
  sid=$(grep -m1 '^session_id=' "$STATE_FILE" 2>/dev/null | cut -d= -f2-)
  [ -n "$sid" ] && [ "$sid" = "$PAYLOAD_SID" ]
}

# ==================================================== THE COMBINED PREFLIGHT
# (epic-16 wave-02, R5/AC-4; Synthesis field report §3.)
#
# WHAT THIS REPLACED. Every branch above used to end in `deny`, and the fix it
# named was a command the operator ran by hand: refused, run the probe, retry,
# dispatch. Five serialized minutes between deciding to dispatch and the agent
# existing, paid per session and again after every /clear — which re-fires the
# this-session demand mid-wave, when nothing about the machine has changed.
#
# THE ASYMMETRY THAT MAKES IT SAFE. A missing attestation is not evidence of a
# broken environment; it is the absence of evidence either way, and the way to
# turn an absent fact into a present one is to go and read it. That costs a second
# and cannot go stale, which is the whole argument against carrying a claim across
# sessions. So an absent, foreign, or unreadable attestation AUTO-RUNS the probe
# and the dispatch proceeds on what it finds.
#
# BLOCKING SURVIVES IN EXACTLY ONE PLACE ON THIS PATH: the probe REFUSING. That is
# a positive finding — no credential, an unwritable repo, an unwritable or
# redirected state directory — and it is the finding a fleet dies of collectively.
# Fail closed on it. The hostile-repo posture is unchanged and now enforced by the
# producer rather than restated here: the probe refuses on a symlinked `.bionic`,
# `.bionic/tmp`, or attestation path, so a repo can still CLOSE this wall and
# still cannot OPEN it — the planted content is never read, before or after.
if ! attested; then
  # The probe next to this script, so a test drives the real producer and an
  # installed gate finds its installed sibling. `$0` is the gate's own path on
  # both; the config-dir form is the fallback for an exotic invocation.
  PROBE_SCRIPT="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/preflight-probe.sh"
  [ -f "$PROBE_SCRIPT" ] || PROBE_SCRIPT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/preflight-probe.sh"

  if [ ! -f "$PROBE_SCRIPT" ]; then
    deny "No environment attestation was found for this repo, and the probe that writes one" \
         "could not be located (looked beside this gate and under the Claude config directory)."
  fi

  # Run it AT THE PINNED ROOT and with THIS dispatch's session key, rather than
  # letting it inherit the shell. Both are the Synthesis field case read directly:
  # the attestation that had to be redone was taken against a root derived from the
  # working directory, and an attestation keyed to anything but the session whose
  # dispatch this is would be one this gate then refuses to read.
  PROBE_OUT=$(cd "$REPO" 2>/dev/null && CLAUDE_CODE_SESSION_ID="$PAYLOAD_SID" \
                bash "$PROBE_SCRIPT" 2>&1)
  PROBE_ST=$?

  if [ "$PROBE_ST" -ne 0 ] || ! attested; then
    # The probe's own words, not a paraphrase of them: it is the component that
    # knows WHICH check failed, and an operator handed "something went wrong" has
    # to run it again by hand to learn anything. Indented so the quotation is
    # visibly the probe speaking.
    {
      echo "BLOCKED: the environment check refused, so this dispatch would launch into a broken environment." >&2
      echo "" >&2
      echo "The check was run automatically for this session and did not pass:" >&2
      printf '%s\n' "$PROBE_OUT" | sed 's/^/    /' >&2
      echo "" >&2
      echo "A fleet inherits this environment and dies collectively if it is wrong." >&2
      echo "Fix the failure above, then retry the dispatch (or re-run by hand: ${PREFLIGHT_CMD})." >&2
    }
    exit 2
  fi

  # Announced, never silent. §4 bans printing CHECK DETAIL on the allow path; this
  # is not detail, it is the gate reporting an action it took on the operator's
  # behalf — the same class as the roster's absence warning, and the operator has
  # to be able to see that a probe ran without being asked.
  printf 'dispatch-preflight: no this-session attestation was present; the environment check was run automatically and passed (%s)\n' \
    "$STATE_FILE" >&2
fi

# ================================================================== THE ROSTER
# (design D-5 + spec §Design "Roster"; slice 4/3 — the LAUNCH half of AC-1.)
#
# The attestation gate has decided. Everything below is a LEDGER — it appends one
# row describing the launch that is about to happen — with exactly ONE exception,
# marked as such where it sits: the absent-deliverable wall (user-directed,
# post-wave-04). Apart from that field, starts fail open (TDD §7), so every
# failure here — an unwritable directory, a hostile path, a brief missing its
# duration or progress path — warns and lets the dispatch through. A gate that
# refused a dispatch because it could not JOURNAL it would be a new failure mode,
# not a safety property; refusing one that gave itself nothing to be checked
# against is the property the wave was built to have.
#
# WHY THIS LIVES IN THE START GATE and not in a fresh hook: the row must exist
# BEFORE the agent does. PostToolUse fires after the spawn, and the epic's whole
# warrant is that an orchestrator's memory of what it launched is the thing that
# fails. Slice 4/4 completes the row from the tool response (full agent id,
# status `confirmed`); `tool_use_id` below is the key it correlates on.
#
# On printing: §4 forbids this gate from printing on the ALLOW path, and that
# still holds for its verdict — a pass says nothing. The absence warning is not
# the verdict; it is the roster reporting that a brief arrived malformed, which
# the wave design ratified as "warns and records absence" (spec §Component
# boundaries). A contract-complete brief — the ordinary case — is silent, which
# is what keeps the §7 positive-pair row ("pass in silence") true in
# tests/fail-direction-table.test.sh.
#
# Schema roster-state/v1 — one `#` header line plus one line per row, each
# `<version>|key=value|...`, read BY KEY and never by position (checklist A6),
# mirroring the observation record in hooks/stop-guard.sh so both machine
# artifacts in .bionic/tmp/ parse the same way. Per-session filename from birth
# (D-5): .bionic/tmp/roster-<session_id>.state.

ROSTER_VERSION="v1"
ROSTER_PREFIX="roster-"
ROSTER_SUFFIX=".state"
STATE_DIR="$REPO/.bionic/tmp"
ROSTER_FILE="$STATE_DIR/${ROSTER_PREFIX}${PAYLOAD_SID}${ROSTER_SUFFIX}"

warn() { printf 'dispatch-preflight: WARN %s\n' "$1" >&2; }

# Values are pipe-delimited on one line, so a field carrying a newline or a `|`
# would forge a row. Never a refusal — the ledger normalizes and records.
sanitize() {  # <value> <max-chars>
  printf '%s' "$1" \
    | tr '\n\r\t|' '    ' \
    | sed -e 's/[[:cntrl:]]/ /g' -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//' \
    | cut -c "1-$2"
}

# ---------- contract-state extraction ----------
#
# The anchors are the labeled fields the dispatch brief already carries — the
# seven-field sentence in skills/canonical-sdlc/SKILL.md §Dispatch, span-pinned
# by tests/dispatch-spans.test.sh §5d, with the exemplar brief recorded at
# .bionic/docs/record/w2-ac3-run.md. This lifts the BRIEF's reading, never the
# orchestrator's restatement (spec §Design invariant).
#
# Two properties earn the awk pass over a line-oriented grep:
#   * a value span ends at the NEXT LABEL, not at the newline — real briefs put
#     two fields on one line ("Expected duration: ~35 minutes. Progress: <path>")
#     and a line-scoped reader swallows the second into the first;
#   * labels nest ("progress" inside "progress artifact", "duration" inside
#     "expected duration"), so labels are matched longest-first and a shorter
#     one overlapping an accepted longer one is discarded. Without that, the
#     inner match becomes a terminator for its own outer span and every value
#     lifts empty.
# Deliverable and progress values are reduced to path-shaped tokens, because
# their consumers (slices 4/5, 4/6) stat them; a slash-bearing token with no
# letter is a fraction ("slice 4/3"), not a path.
#
# THE LIVENESS FIELDS (`cadence`, `claims`) join the same table, because slice
# 4/7 shipped them into the same §Dispatch prose the labels above anchor on:
# "The progress-artifact path carries a `cadence` alongside it" and "A subprocess
# claim — a process pattern plus its output file — is conditional-required". They
# were prose-only for one slice — hooks/stop-check.sh read `claims=` off a row no
# writer could produce, which the Step-6 six-axis review called for what it was
# (axis-3 FAIL: a shipped reader with no producer, its only test hand-writing an
# impossible row). Two grammar notes, both forced by that ratified sentence:
#
#   * `cadence` may be introduced by whitespace instead of a colon, because the
#     contract puts it ALONGSIDE the progress path inside one sentence
#     ("Progress: <path>, cadence ~6m") rather than on a labeled line of its own.
#     It is the only label with a relaxed separator, and the separator still has
#     to be there — `cadences` is not a hit. That relaxation is also why the hit
#     is POSITIONAL: a lexical match alone turned every prose use of the word
#     into a declaration (Step-6 critic F-2), so END additionally requires the
#     hit to fall inside the span the progress label owns — which is exactly
#     where the sentence above puts it.
#   * the subprocess claim is spelled in the contract's own words — "A subprocess
#     claim" — and those are the only two labels that lift it. A bare `claims`
#     label was tried and withdrawn: it matched "verify every claim the report
#     claims:" in an ordinary review brief and invented a subprocess for it,
#     which the P2 display then reports as `live: no`, the alarm direction.
#   * the subprocess claim declares two things in one span, and only one of them
#     has a consumer: the PATTERN, which hooks/stop-check.sh existence-checks.
#     So the pattern is what the row carries — the backticked or quoted run when
#     the author marks one, else the text up to the first comma or arrow.
LEAD_CHARS="(\"[<\`$(printf '\047')"
TRAIL_CHARS=")\"]>\`,;:!?.$(printf '\047')"
QUOTE_CHARS="\`\"$(printf '\047')"

lift_contract_fields() {  # <brief text> -> `kind=value` lines, absent kinds omitted
  printf '%s' "$1" | awk -v LEAD="$LEAD_CHARS" -v TRAIL="$TRAIL_CHARS" -v QUOTES="$QUOTE_CHARS" -v DOCSROOT="$DOCS_ROOT" -v DOCSROOTREL="$DOCS_ROOT_REL" '
    # <sep> is the regex between the label and its value; the default is the
    # colon every labeled brief field uses. <bol> marks a label that only counts
    # at the START of a line — see the waiver note in BEGIN.
    function addlabel(txt, kind, sep, bol) {
      NL++; LTXT[NL] = txt; LKIND[NL] = kind
      LSEP[NL] = (sep == "" ? "[ \t]*:" : sep)
      LBOL[NL] = (bol == "" ? 0 : 1)
    }
    # True iff position p is the first non-blank thing on its line. Leading
    # whitespace still counts as a line start (an indented brief field is a
    # field); anything else before it on the line does not.
    function at_line_start(p,   k, ch) {
      k = p - 1
      while (k >= 1) {
        ch = substr(lc, k, 1)
        if (ch == " " || ch == "\t") { k--; continue }
        return (ch == "\n")
      }
      return 1
    }
    function trimtok(t,   ch) {
      while (length(t) > 0) { ch = substr(t, 1, 1);         if (index(LEAD,  ch) > 0) t = substr(t, 2);                    else break }
      while (length(t) > 0) { ch = substr(t, length(t), 1); if (index(TRAIL, ch) > 0) t = substr(t, 1, length(t) - 1);     else break }
      return t
    }
    # A token carrying an unfilled `<...>` slot is a TEMPLATE, not a path — the
    # wall message below hands the author exactly one
    # (`Expected artifact: .bionic/docs/record/<name>.md`) and briefs in this repo
    # quote that text constantly, so the slot lifted as a real contract and
    # nothing could ever satisfy it (Step-6 review C-1, second shape). The rule
    # lives HERE, in the predicate both the labeled lift and the inference scan
    # run every token through, so the two can never disagree about what a
    # template is.
    #
    # WHAT FOLLOWS FROM REJECTING IT CHANGED in epic-16 wave-02 (R4). Wave-01 let
    # the rejection fall through to the absent-deliverable wall and REFUSE, so the
    # author was told at dispatch while the brief was still editable. Ship day
    # 2026-08-08 then spent that refusal twice on briefs with nothing wrong in
    # substance, and the wave charter named both as grammar corners. A template is
    # not an absence: it names the LOCATION and leaves the NAME open, and the
    # dispatch itself carries a name. So templates are still not paths — they lift
    # SEPARATELY, under their own kind, and the shell side fills the slot. The
    # separation is the point: a filled path can never be mistaken for one the
    # author wrote, and it is recorded `source=inferred` for exactly that reason.
    #
    # The unterminated form (`<name` after trimtok has eaten a trailing `>`) counts
    # as a template too. Without that clause `.bionic/tmp/<name>` passed the four
    # shape checks and lifted as a literal path — a contract with a bracket in its
    # basename, which nothing would ever satisfy.
    # The unterminated forms are counted too, in BOTH directions, because trimtok
    # runs first and its LEAD/TRAIL sets contain both brackets: `<name>` alone comes
    # out as `name`, and `<somewhere>/out.md` comes out as `somewhere>/out.md`,
    # which passes all four shape checks and would lift as a literal path with a
    # bracket in it. An orphaned bracket on either side is the residue of a slot,
    # never a filename anyone typed.
    function istemplate(t) {
      if (t ~ /<[^<>]*>/)  return 1     # a whole slot
      if (t ~ /<[^<>]*$/)  return 1     # opening bracket, closer eaten by trimtok
      if (t ~ /^[^<>]*>/)  return 1     # closing bracket, opener eaten by trimtok
      return 0
    }
    function pathshaped(t) {
      if (length(t) < 3)        return 0
      if (index(t, "/") == 0)   return 0
      if (t !~ /[A-Za-z]/)      return 0
      if (substr(t, 1, 1) == "-") return 0
      return 1
    }
    function ispath(t) { return (pathshaped(t) && !istemplate(t)) }
    function collapse(s) { gsub(/[ \t\r\n]+/, " ", s); sub(/^ +/, "", s); sub(/ +$/, "", s); return s }
    # The claimed PROCESS PATTERN out of a subprocess-claim span. Author-marked
    # first (a backticked or quoted run is unambiguous), then the punctuation the
    # sentence uses to separate the pattern from its output file.
    function claimpat(s,   i, q, a, b) {
      s = collapse(s)
      for (i = 1; i <= length(QUOTES); i++) {
        q = substr(QUOTES, i, 1)
        a = index(s, q)
        if (a == 0) continue
        b = index(substr(s, a + 1), q)
        if (b > 1) return substr(s, a + 1, b - 1)
      }
      a = index(s, ",");  if (a > 0) s = substr(s, 1, a - 1)
      a = index(s, "->"); if (a > 0) s = substr(s, 1, a - 1)
      a = index(s, "→");  if (a > 0) s = substr(s, 1, a - 1)
      return collapse(s)
    }
    function firsthit(kind,   j, best) {
      best = 0
      for (j = 1; j <= nh; j++) if (HK[j] == kind && (best == 0 || HLS[j] < HLS[best])) best = j
      return best
    }
    # The last character index of the span belonging to hit h. `skip` names one
    # hit to IGNORE when looking for the terminator, which the cadence rule in
    # END needs: it asks where the PROGRESS span would end if the cadence label
    # were not sitting inside it, and without the skip that span would end at the
    # very label whose membership is the question. (No apostrophes in here — the
    # whole program is one single-quoted shell word.)
    function spanend(h, skip,   j, e, s, bl) {
      e = length(text)
      for (j = 1; j <= nh; j++) if (j != skip && HLS[j] > HLS[h] && HLS[j] - 1 < e) e = HLS[j] - 1
      s = substr(text, HVS[h], e - HVS[h] + 1)
      bl = index(s, "\n\n")            # a blank line ends a field, whatever follows
      if (bl > 0) e = HVS[h] + bl - 2
      return e
    }
    function spanof(h) { return substr(text, HVS[h], spanend(h, 0) - HVS[h] + 1) }
    # record/-inference (slice 4/4, AC-8): a path token nobody labeled can still
    # satisfy the deliverable wall, but only under the three prefixes the plan
    # names, and NEVER under a tmp prefix — a scratch path is never durable,
    # labeled or not, and the exclusion is checked first so a token cannot
    # sneak past it by also happening to contain "record/" somewhere past the
    # tmp prefix.
    function is_tmp_path(t) {
      if (substr(t, 1, length(".bionic/tmp/")) == ".bionic/tmp/") return 1
      if (substr(t, 1, length("/tmp/")) == "/tmp/") return 1
      return 0
    }
    function is_record_path(t,   dr) {
      if (is_tmp_path(t)) return 0
      if (substr(t, 1, length("record/")) == "record/") return 1
      if (substr(t, 1, length(".bionic/docs/record/")) == ".bionic/docs/record/") return 1
      if (DOCSROOT != "") {
        dr = DOCSROOT "/record/"
        if (substr(t, 1, length(dr)) == dr) return 1
      }
      # The same root as a brief spells it. DOCSROOT is absolute and a brief is
      # repo-relative, so without this the overridden form never fired at all.
      if (DOCSROOTREL != "") {
        dr = DOCSROOTREL "/record/"
        if (substr(t, 1, length(dr)) == dr) return 1
      }
      return 0
    }
    # True iff position p falls inside the span of an INPUT-designating label
    # (`read first`, `scope constraint`). See the kind note in BEGIN: those spans
    # name what the agent must CONSULT or must NOT TOUCH, so a path inside one is
    # never a thing the agent produces.
    function in_input_span(p,   j) {
      for (j = 1; j <= nh; j++) {
        if (HK[j] != "input") continue
        if (p >= HLS[j] && p <= spanend(j, 0)) return 1
      }
      return 0
    }
    # Scans the WHOLE brief, not one label span — inference has no label to
    # bound it. First path-shaped, record-prefixed, non-tmp token OUTSIDE every
    # input span wins.
    #
    # Why this walks positions instead of split()ing on whitespace: the input-span
    # exclusion is positional, and a token divorced from its offset cannot be
    # asked which span it came from. Step-6 review C-1 — a `Read first:` path
    # became the declared deliverable and the landing gate then ordered the agent
    # to overwrite the file it was sent to read.
    function scan_inferred(   pos, t, start, rest) {
      pos = 1
      while (pos <= length(text)) {
        rest = substr(text, pos)
        if (match(rest, /[^ \t\r\n]+/) == 0) break
        start = pos + RSTART - 1
        t = substr(text, start, RLENGTH)
        pos = start + RLENGTH
        if (in_input_span(start)) continue
        t = trimtok(t)
        if (!ispath(t)) continue
        if (is_record_path(t)) return t
      }
      return ""
    }
    # scan_inferred()`s twin for templates, and it keeps BOTH of that scan`s
    # restraints rather than relaxing them for a weaker kind of evidence: never out
    # of an input span (the C-1 finding — the agent must not be contracted to a file
    # it was sent to read, and a slot in that path does not make it any more its
    # output), and never a tmp path (a scratch file is not durable, filled or not).
    function scan_templated(   pos, t, start, rest) {
      pos = 1
      while (pos <= length(text)) {
        rest = substr(text, pos)
        if (match(rest, /[^ \t\r\n]+/) == 0) break
        start = pos + RSTART - 1
        t = substr(text, start, RLENGTH)
        pos = start + RLENGTH
        if (in_input_span(start)) continue
        t = trimtok(t)
        if (!pathshaped(t) || !istemplate(t)) continue
        if (is_record_path(t)) return t
      }
      return ""
    }
    # A waiver REASON that is the angle-bracketed slot out of the wall message,
    # copied rather than filled in. A real reason never opens with one.
    function isplaceholder(v) { return (v ~ /^<[^<>]*>/) }
    function paths(s, maxn,   n, arr, i, t, out, seen, c) {
      n = split(s, arr, /[ \t\r\n]+/); out = ""; c = 0
      for (i = 1; i <= n; i++) {
        t = trimtok(arr[i])
        if (!ispath(t) || seen[t]) continue
        seen[t] = 1
        out = (out == "" ? t : out "," t)
        if (++c >= maxn) break
      }
      return out
    }
    # paths()`s twin for the template kind — same span, same trimming, the one
    # predicate inverted. One token only: a filled path is a GUESS, and guessing a
    # conjunction of them would multiply one uncertainty into several.
    function templates(s, maxn,   n, arr, i, t, out, seen, c) {
      n = split(s, arr, /[ \t\r\n]+/); out = ""; c = 0
      for (i = 1; i <= n; i++) {
        t = trimtok(arr[i])
        if (!pathshaped(t) || !istemplate(t) || seen[t]) continue
        seen[t] = 1
        out = (out == "" ? t : out "," t)
        if (++c >= maxn) break
      }
      return out
    }
    BEGIN {
      NL = 0
      # LONGEST FIRST — see the nesting note above. `-` marks a label that only
      # BOUNDS a span; it is a real brief field, just not one the roster lifts.
      #
      # `input` is a second non-lifting kind, and it bounds spans identically —
      # the difference is that the record/-inference scan REFUSES to take a path
      # out of one (Step-6 review C-1). These two labels are the ones that name
      # files the agent must read, or must leave alone; every other `-` label
      # heads ordinary prose, where an unlabeled record/ path is exactly the
      # deliverable the inference exists to find (S12, and the `Your slice:`
      # spans those cases sit inside).
      #
      # `deliverable-waiver` heads the table because it is the longest label AND
      # because it nests the shortest-but-one: a brief line reading
      # `Deliverable-waiver: <reason>` must never lift as a `deliverable`. The
      # separator rule already keeps them apart (`deliverable` requires a colon,
      # and the next character here is a hyphen), but the ordering makes the
      # intent structural rather than incidental.
      #
      # It is also the one label pinned to LINE START. It is the only label that
      # OPENS a wall rather than filling a field, and briefs in this repo quote
      # the wall message that names it constantly — so a mid-sentence occurrence
      # is documentation, not a declaration (Step-6 review S-1: one quoted line
      # silenced the landing contract for the whole dispatch).
      addlabel("deliverable-waiver", "waiver", "", 1)
      addlabel("subprocess claims", "claims")
      addlabel("subprocess claim",  "claims")
      addlabel("expected artifacts", "deliverable")
      addlabel("expected artifact",  "deliverable")
      addlabel("progress artifact",  "progress")
      addlabel("expected duration",  "duration")
      addlabel("scope constraint",   "input")
      addlabel("exit condition",     "-")
      addlabel("progress path",      "progress")
      addlabel("deliverables",       "deliverable")
      addlabel("current step",       "-")
      addlabel("deliverable",        "deliverable")
      addlabel("constraints",        "-")
      addlabel("your slice",         "-")
      addlabel("read first",         "input")
      addlabel("artifacts",          "deliverable")
      addlabel("artifact",           "deliverable")
      addlabel("progress",           "progress")
      addlabel("duration",           "duration")
      addlabel("cadence",            "cadence", "([ \t]*:|[ \t])[ \t]*")
      addlabel("scope",              "-")
      addlabel("model",              "-")
      addlabel("exit",               "-")
    }
    { text = text $0 "\n" }
    END {
      lc = tolower(text); nh = 0
      for (i = 1; i <= NL; i++) {
        lab = LTXT[i]; from = 1
        while (from <= length(lc)) {
          rest = substr(lc, from)
          if (match(rest, "(^|[^a-z])" lab LSEP[i]) == 0) break
          p = from + RSTART - 1
          vend = p + RLENGTH                                  # first char AFTER the colon
          ls = p
          if (substr(lc, ls, length(lab)) != lab) ls = p + 1  # the guard char matched too
          from = vend
          if (LBOL[i] && !at_line_start(ls)) continue
          clash = 0
          for (j = 1; j <= nh; j++) if (ls <= HVS[j] - 1 && vend - 1 >= HLS[j]) { clash = 1; break }
          if (clash) continue
          nh++; HLS[nh] = ls; HVS[nh] = vend; HK[nh] = LKIND[i]
        }
      }
      # The fallback to the whole-brief inference scan triggers on an EMPTY VALUE
      # (v == ""), not merely on the ABSENCE of a deliverable-kind hit (h == 0) —
      # an earlier, pathless label hit (e.g. quoted landing-verdict prose reading
      # "...per deliverable:") can win the firsthit position race over a later,
      # real labeled deliverable and still yield nothing from its own span. Gating
      # on h == 0 alone left that shadowed case refused despite a real record/
      # path sitting later in the same brief; v == "" catches both shapes with
      # the one scan (post-landing addendum, live specimen).
      #
      # THE LADDER, strongest evidence first (epic-16 wave-02, R4). Each rung is
      # tried only when every rung above it found nothing, so a path the author
      # actually wrote can never be demoted by a guess sitting earlier in the text:
      #   1. a labeled, slot-free path            -> deliverable= (source=declared)
      #   2. an unlabeled record/ path            -> inferred=    (source=inferred)
      #   3. a labeled template, then an unlabeled record/ template
      #                                           -> templated=   (shell fills it)
      # Nothing below rung 3 exists: a brief offering none of the three has named no
      # location at all, and that is the substance the wall still refuses on.
      h = firsthit("deliverable")
      v = ""
      if (h > 0) { v = paths(spanof(h), 4) }
      if (v != "") { print "deliverable=" v }
      else {
        v = scan_inferred()
        if (v != "") { print "inferred=" v }
        else {
          tv = ""
          if (h > 0) { tv = templates(spanof(h), 1) }
          if (tv == "") { tv = scan_templated() }
          if (tv != "") { print "templated=" tv }
        }
      }
      h = firsthit("duration");    if (h > 0) { v = collapse(spanof(h));      if (v != "") print "duration=" v }
      # The progress field takes the same two rungs, because `ispath` is the one
      # predicate both fields run through and a rule that filled one spelling but
      # not the other is how two fields come to disagree about what a template is.
      h = firsthit("progress")
      if (h > 0) {
        v = paths(spanof(h), 1)
        if (v != "") { print "progress=" v }
        else { v = templates(spanof(h), 1); if (v != "") print "progress_templated=" v }
      }
      # CADENCE IS POSITIONAL, not merely lexical (Step-6 critic F-2). It is the
      # one label with a relaxed separator — whitespace will do, because the
      # contract writes it inside the progress sentence rather than on a line of
      # its own — and that relaxation made every prose occurrence of the word a
      # declaration. "Scope constraint: keep a steady cadence and do not batch the
      # sections" lifted `cadence=and do not batch the sections.`, and a
      # fabricated liveness field is not inert: field presence is the shape key
      # the watcher arms off. So the hit must fall where the contract puts it —
      # after the progress label, inside the span that label owns.
      h = firsthit("cadence")
      if (h > 0) {
        ph = firsthit("progress")
        if (ph > 0 && HLS[h] > HLS[ph] && HLS[h] <= spanend(ph, h)) {
          v = collapse(spanof(h)); if (v != "") print "cadence=" v
        }
      }
      h = firsthit("claims");      if (h > 0) { v = claimpat(spanof(h));      if (v != "") print "claims=" v }
      # The waiver is free text — a REASON, never a path — so it lifts collapsed
      # and whole, ending where the next labelled field begins. An EMPTY value is
      # not printed, which is the whole of the "a reasonless waiver is not a
      # waiver" rule: the wall below reads presence, and presence means a reason.
      # A PLACEHOLDER value is not printed for the same reason read one step
      # further: the wall message hands the author a slot to fill, and a brief
      # that quotes the slot back unfilled has given no reason at all (S-1).
      h = firsthit("waiver")
      if (h > 0) { v = collapse(spanof(h)); if (v != "" && !isplaceholder(v)) print "waiver=" v }
    }
  ' 2>/dev/null
}

# ---------- D-5 pruning ----------
#
# The same liveness rule slice 4/2 established for the attestation
# (hooks/preflight-probe.sh): a session is live iff its transcript still exists
# under CLAUDE_CONFIG_DIR/projects. A LIVE foreign session's roster is never
# touched — that concurrency is the point of D-5 — and a dead session's is
# reclaimed so a stale fleet cannot answer as "ours" (the bb20f616 class). There
# is no legacy single-slot file to prune: this artifact is per-session from
# birth.
ROSTER_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

roster_session_live() {  # <session id>
  local sid="$1" d
  [ -n "$sid" ] || return 1
  [ -d "$ROSTER_CONFIG_DIR/projects" ] || return 1
  for d in "$ROSTER_CONFIG_DIR"/projects/*/; do
    [ -f "${d}${sid}.jsonl" ] && return 0
  done
  return 1
}

prune_stale_rosters() {
  local f base sid
  for f in "$STATE_DIR"/"$ROSTER_PREFIX"*"$ROSTER_SUFFIX"; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    sid="${base#"$ROSTER_PREFIX"}"
    sid="${sid%"$ROSTER_SUFFIX"}"
    [ "$sid" = "$PAYLOAD_SID" ] && continue
    roster_session_live "$sid" || rm -f "$f" 2>/dev/null
  done
}

# ---------- the row ----------

AGENT_NAME=$(sanitize "$(_jq '.tool_input.name')" 200)
SUBAGENT_TYPE=$(sanitize "$(_jq '.tool_input.subagent_type')" 200)
AGENT_MODEL=$(sanitize "$(_jq '.tool_input.model')" 200)
TOOL_USE_ID=$(sanitize "$(_jq '.tool_use_id')" 200)
LIFTED=$(lift_contract_fields "$(_jq '.tool_input.prompt')")

field_of() {  # <kind>
  printf '%s\n' "$LIFTED" | grep -m1 "^$1=" | cut -d= -f2-
}
C_DELIVERABLE=$(sanitize "$(field_of deliverable)" 300)
C_DURATION=$(sanitize "$(field_of duration)" 80)
C_PROGRESS=$(sanitize "$(field_of progress)" 300)
C_CADENCE=$(sanitize "$(field_of cadence)" 80)
C_CLAIMS=$(sanitize "$(field_of claims)" 300)
C_WAIVER=$(sanitize "$(field_of waiver)" 300)
C_INFERRED=$(sanitize "$(field_of inferred)" 300)
C_TEMPLATED=$(sanitize "$(field_of templated)" 300)
C_PROGRESS_TEMPLATED=$(sanitize "$(field_of progress_templated)" 300)

# ---------- filling a template (epic-16 wave-02, R4) ----------
#
# The slot's own word for what belongs in it is `<name>`, and a dispatch carries
# exactly one name — the agent's. So the fill is not a heuristic about this repo's
# file-naming habits; it is reading the template the way its author wrote it. The
# result is a real, satisfiable, falsifiable path, which is the property the
# absent-deliverable wall exists to guarantee and the one a raw slot destroys.
#
# The name is reduced to a filename alphabet first. It reaches here through
# `sanitize`, which already removed the row-forging characters, but this value goes
# somewhere sanitize does not care about — INTO A PATH, and into a sed replacement
# on the way. A `/` would silently redirect the contract into a subdirectory and a
# `&` would duplicate the match; both are folded to `-` rather than escaped, because
# a contract path is going to be a filename either way.
SLOT_NAME=$(printf '%s' "$AGENT_NAME" | tr -c 'A-Za-z0-9._-' '-' | sed -e 's/^-*//' -e 's/-*$//')

fill_name() {  # <templated path> -> slot-filled path, or "" when it cannot be filled
  local out
  [ -n "$SLOT_NAME" ] || return 0
  out=$(printf '%s' "$1" | sed -e "s|<[^<>]*>|$SLOT_NAME|g" -e "s|<[^<>]*\$|$SLOT_NAME|")
  # A surviving bracket means the fill did not close the shape, and a half-filled
  # path is worse than none: it looks like a contract and can never be one.
  case "$out" in *'<'*|*'>'*|'') return 0 ;; esac
  printf '%s' "$out"
}

slotfree_ancestor() {  # <templated path> -> deepest slot-free ancestor dir, or ""
  # The fallback when there is no name to fill with — the Agent tool does not
  # require one. The LOCATION is still evidence even when the name is not, and the
  # landing check already understands a directory contract (it lands when a file
  # appears inside). Deliberately weaker than a filename; still a fact something can
  # be stat'd against, which an unfilled slot never was. A template whose slot sits
  # in the FIRST component leaves nothing here, and that is the honest answer:
  # `<somewhere>/out.md` names no location at all.
  #
  # The cut takes the first bracket of EITHER kind, matching istemplate: trimtok may
  # already have eaten one side, and cutting only at `<` would keep an orphaned `>`
  # inside the surviving directory name.
  local head="${1%%[<>]*}"
  case "$head" in
    */*) printf '%s' "${head%/*}" ;;
    *)   : ;;   # no slash before the slot: no directory was named, so nothing here
  esac
}

# record/-inference (slice 4/4, AC-8): a labeled deliverable always wins and is
# recorded `source=declared`; only when the brief named none does an unlabeled
# record/-prefixed path (never a tmp one — the awk side excludes it) step in,
# recorded `source=inferred`. An inferred path satisfies the absent-deliverable
# wall below the same way a labeled one always has, because by this point
# C_DELIVERABLE is simply non-empty either way — the wall does not know or care
# which kind it is looking at.
#
# THE THIRD RUNG (epic-16 wave-02, R4) sits below both: a template, filled. It is
# recorded `source=inferred` rather than under a word of its own, and that is a
# decision with a consumer behind it — hooks/session-sweeper.sh reads this field to
# resolve a brief that both declares an artifact and waives it, and treats
# ANYTHING BUT `inferred` as declared. A new third value would therefore be read as
# "the author declared this", which is precisely what a filled slot is not. One
# reader, two values, no drift.
C_SOURCE=""
C_TEMPLATE_ORIGIN=""
if [ -n "$C_DELIVERABLE" ]; then
  C_SOURCE="declared"
elif [ -n "$C_INFERRED" ]; then
  C_DELIVERABLE="$C_INFERRED"
  C_SOURCE="inferred"
elif [ -n "$C_TEMPLATED" ]; then
  C_DELIVERABLE=$(fill_name "$C_TEMPLATED")
  [ -n "$C_DELIVERABLE" ] || C_DELIVERABLE=$(slotfree_ancestor "$C_TEMPLATED")
  if [ -n "$C_DELIVERABLE" ]; then
    C_SOURCE="inferred"
    C_TEMPLATE_ORIGIN="$C_TEMPLATED"
  fi
fi

# The progress path takes the same fill. It has no wall behind it — an absent
# progress path warns and passes — so the only question is whether the row carries a
# path something could be stat'd against, and a slot never was one. The fallback
# directory is not useful here (liveness is read off ONE file's mtime), so a
# progress template with no name to fill it is left absent and warned, exactly as a
# missing one is.
if [ -z "$C_PROGRESS" ] && [ -n "$C_PROGRESS_TEMPLATED" ]; then
  C_PROGRESS=$(fill_name "$C_PROGRESS_TEMPLATED")
fi

# What is ABSENT is recorded as a field of its own, so a consumer never has to
# guess whether an empty value means "the brief did not say" or "the brief said
# nothing". `model` is deliberately not on this list: the Agent tool inherits
# the orchestrator's model when a dispatch names none, so warning on it would
# fire on the ordinary case and train the reader past the real findings.
#
# NEITHER LIVENESS FIELD IS ON IT EITHER, for the same reason read the other way.
# The subprocess claim is CONDITIONAL-required — declared iff the task backgrounds
# a long command — so its absence is the ordinary case and carries no finding.
# `cadence` is required WITH a progress path, which makes its absence a
# conditional judgment rather than the flat fact this field records; the roster
# reports what the brief said and leaves that reading to the watcher (P3).
ABSENT=""
add_absent() { ABSENT="${ABSENT:+$ABSENT,}$1"; }
[ -n "$AGENT_NAME" ]    || add_absent name
[ -n "$C_DELIVERABLE" ] || add_absent deliverable
[ -n "$C_DURATION" ]    || add_absent duration
[ -n "$C_PROGRESS" ]    || add_absent progress

# ========================================================= THE CONTAINMENT WALL
# (Step-6 review S-2.)
#
# A deliverable is a path this repo's machinery will later STAT, and — on the
# directory branch — WALK. Nothing downstream checks where it points: `abs_path`
# in hooks/session-sweeper.sh prefixes the repo root for a relative path and
# passes an absolute one straight through, so `Expected artifact: /usr/share`
# stats and walks /usr/share on every subagent stop, and the refusal text hands
# the stopping agent the mtime of whatever it found. Both halves are fixed HERE
# rather than there, because dispatch is the moment the path is still editable by
# the author who wrote it: at stop time the only available answer is to refuse an
# agent for a brief it did not write.
#
# Resolution is LEXICAL for the part that does not exist yet — the deliverable is
# by definition not on disk, so there is nothing there to realpath — and PHYSICAL
# for the ancestor that does. Both halves are needed, and the second one is not
# decoration: `git rev-parse --show-toplevel` reports the repo root with symlinks
# resolved, so on a machine where a path component is a link (macOS `/var` ->
# `/private/var`, `/tmp` -> `/private/tmp`) a brief spelling a perfectly good
# in-repo absolute path compares against a root it can never match, and the wall
# false-blocks. Resolving the existing prefix puts both sides in the same terms.
#
# It also means a symlinked ancestor INSIDE the repo that points out of it is
# caught, which is the right answer rather than a bonus: what the landing check
# will stat is where the link lands. An ancestor that cannot be entered at all is
# an ambiguity, and takes §7 direction — fall back to the lexical answer rather
# than refuse on a question this gate cannot answer.
resolve_in_repo() {  # <path> -> absolute, `.`/`..` folded, existing prefix physical
  local p="$1" abs out part had_f head rest phys
  case "$p" in
    /*) abs="$p" ;;
    *)  abs="$REPO/$p" ;;
  esac
  case "$-" in *f*) had_f=1 ;; *) had_f=0 ;; esac
  set -f   # a `*` inside a brief-supplied path is a character, never a glob
  out=""
  local IFS=/
  for part in $abs; do
    case "$part" in
      ''|.) ;;
      ..)   out="${out%/*}" ;;
      *)    out="$out/$part" ;;
    esac
  done
  unset IFS
  [ "$had_f" -eq 1 ] || set +f
  out="${out:-/}"

  head="$out"; rest=""
  while [ -n "$head" ] && [ ! -d "$head" ]; do
    rest="${head##*/}${rest:+/$rest}"
    head="${head%/*}"
  done
  if [ -n "$head" ]; then
    phys=$(cd "$head" 2>/dev/null && pwd -P)
  else
    phys="/"
  fi
  [ -n "$phys" ] || { printf '%s' "$out"; return; }
  case "$phys" in
    /) printf '%s' "/$rest" ;;
    *) printf '%s' "${phys}${rest:+/$rest}" ;;
  esac
}

if [ -n "$C_DELIVERABLE" ]; then
  D_ABS=$(resolve_in_repo "$C_DELIVERABLE")
  case "$D_ABS" in
    "$REPO"/*) : ;;
    *)
      echo "BLOCKED: this dispatch names a deliverable outside the repository — a wave is active." >&2
      echo "" >&2
      echo "    ${C_DELIVERABLE}" >&2
      echo "  resolves to ${D_ABS}, which is not under ${REPO}." >&2
      echo "" >&2
      echo "The landing check stats — and, for a directory, walks — whatever this names," >&2
      echo "on every stop of the agent that owns it. It must be a path inside this repo." >&2
      echo "" >&2
      echo "Fix: name a repo-relative artifact path in the brief —" >&2
      echo "    Expected artifact: .bionic/docs/record/<name>.md" >&2
      echo "" >&2
      echo "Then retry the dispatch." >&2
      exit 2
      ;;
  esac
fi

# ======================================================= THE ABSENT-DELIVERABLE WALL
# (user-directed, epic-15 post-wave-04: "A wall. It should be a wall.")
#
# THE ONE PLACE below the verdict where this file changes the verdict, and it is
# deliberately narrow: exactly one absent field refuses, and only when the brief
# offers no waiver. Everything else on this path stays advisory — an absent
# progress path warns, an absent duration warns.
#
# Why this field and not the others: every downstream check the wave built is
# keyed on a durable artifact. The sweeper's landing verdict stats the
# deliverable path; the stop gate asks whether the thing the agent was
# sent to produce exists. A dispatch that names none is unfalsifiable by
# construction — nothing to stat when it reports done, nothing left behind when
# it dies quietly — and a warning was never going to fix that, because the
# warning arrives in the same breath as the launch it failed to prevent.
#
# THE WAIVER IS THE ESCAPE, and it is deliberately IN THE BRIEF rather than an
# environment variable or a flag: a waiver written into the dispatch text is
# lifted by the same extractor as every other contract field, lands in the roster
# row beside the absence it excuses, and is echoed on stderr as it passes. There
# is no way to take it that leaves no record — which is the property that makes
# refusing safe to live with. A waiver with no reason is not a waiver (the
# extractor prints nothing for an empty span), so the escape always costs a
# sentence.
#
# THIS SITS ABOVE the symlink and prune housekeeping on purpose. A hostile or
# merely broken roster path must not be able to OPEN this wall by making the
# journal step bail early — the same reasoning §8 applies to the attestation
# path, read here in the refuse direction.
if [ -z "$C_DELIVERABLE" ] && [ -z "$C_WAIVER" ]; then
  echo "BLOCKED: this dispatch brief names no deliverable — a wave is active." >&2
  echo "" >&2
  echo "An agent with nothing durable to produce cannot be checked on: there is no" >&2
  echo "path to stat when it reports done, and nothing left behind if it dies quietly." >&2
  echo "" >&2
  echo "Fix: name a durable artifact path in the brief —" >&2
  echo "    Expected artifact: .bionic/docs/record/<name>.md" >&2
  echo "  Any of these labels lifts one: Expected artifact(s), Deliverable(s), Artifact(s)." >&2
  echo "  An unlabeled record/ mention is inferred automatically — .bionic/tmp/ or /tmp/ paths never are." >&2
  echo "" >&2
  echo "Or waive it — the reason is recorded on the session roster either way:" >&2
  echo "    Deliverable-waiver: <why this dispatch produces nothing durable>" >&2
  echo "" >&2
  echo "Then retry the dispatch." >&2
  exit 2
fi

# The directory levels of this path were already discharged: the attestation
# check above refuses outright if `.bionic` or `.bionic/tmp` is a symlink, so
# reaching here means both are real directories. The roster FILE is its own
# path and gets its own check — a hostile repo may make this gate fail to
# journal, but must not gain an append to a file it points at (§8).
if [ -L "$ROSTER_FILE" ]; then
  warn "the roster path is a symbolic link; nothing was written through it: $ROSTER_FILE"
  exit 0
fi

prune_stale_rosters

# ---------- same-path contention (epic-16 wave-02, R8/AC-12) ----------
#
# Read BEFORE the append, or the row about to be written answers for itself. Two
# dispatches contracted to one file is not an error and is never refused — it is
# how a takeover, a retry, or a deliberately split task legitimately looks — but it
# is the shape behind a whole class of confusing verdicts: whichever agent stops
# second inherits a contract the first one landed, so the landing gate says MET on
# work this agent did not do. Naming the owning row at dispatch is the cheapest
# moment to notice, and the operator is the one who knows which case it is.
#
# "OWNS" IS READ AS "IS ON THIS SESSION'S ROSTER", and that is a deliberately wide
# reading. Closure is not a fact any hook writes — no writer ever sets a status
# meaning `done`, because whether a contract is discharged is computed from disk by
# the verdict, which this gate is forbidden to re-implement or even to invoke. So
# the alternatives were a wide warning or no warning at all. A warning is the tier
# where a false positive costs a sentence, which is the right side to be wrong on.
owning_row_for() {  # <deliverable path> -> the owning row's name, or ""
  [ -n "$1" ] && [ -f "$ROSTER_FILE" ] || return 0
  awk -F'|' -v want="$1" '
    /^#/ { next }
    {
      name = ""; deliv = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^name=/)        name  = substr($i, 6)
        else if ($i ~ /^deliverable=/) deliv = substr($i, 13)
      }
      if (deliv == "") next
      n = split(deliv, parts, ",")
      for (j = 1; j <= n; j++) {
        p = parts[j]; gsub(/^ +| +$/, "", p)
        if (p != "" && p == want) { print name; exit }
      }
    }
  ' "$ROSTER_FILE" 2>/dev/null
}

CONTENDED_OWNER=""
CONTENDED_PATH=""
if [ -n "$C_DELIVERABLE" ]; then
  _old_ifs="$IFS"; IFS=','; set -f
  # shellcheck disable=SC2086
  set -- $C_DELIVERABLE
  set +f; IFS="$_old_ifs"
  for _d in "$@"; do
    _d="${_d# }"; _d="${_d% }"
    [ -n "$_d" ] || continue
    CONTENDED_OWNER=$(owning_row_for "$_d")
    if [ -n "$CONTENDED_OWNER" ]; then CONTENDED_PATH="$_d"; break; fi
  done
fi

ROW="roster-state/${ROSTER_VERSION}|status=intended|session=${PAYLOAD_SID}|name=${AGENT_NAME}|agent_id=|launched_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)|subagent_type=${SUBAGENT_TYPE}|model=${AGENT_MODEL}|deliverable=${C_DELIVERABLE}|source=${C_SOURCE}|duration=${C_DURATION}|progress=${C_PROGRESS}|claims=${C_CLAIMS}|cadence=${C_CADENCE}|absent=${ABSENT}|waiver=${C_WAIVER}|tool_use_id=${TOOL_USE_ID}"

WROTE=1
if [ ! -e "$ROSTER_FILE" ]; then
  # A concurrent dispatch in the same session can lose this race and write the
  # header twice; both are comment lines and every reader skips them. The ROWS
  # are what must not interleave, and each is a single short append.
  printf '# bionic session roster — schema roster-state/%s — machine-local, safe to delete\n' \
    "$ROSTER_VERSION" >> "$ROSTER_FILE" 2>/dev/null && chmod 600 "$ROSTER_FILE" 2>/dev/null
fi
printf '%s\n' "$ROW" >> "$ROSTER_FILE" 2>/dev/null || WROTE=0

# No lock, unlike the observation record: that one is a read-modify-write of the
# whole file, this one is a single O_APPEND write of well under a pipe buffer,
# which the kernel does not interleave. A lock here would put a failure mode
# (a wedged lock directory) in front of a dispatch, on the fail-open side.
if [ "$WROTE" -eq 0 ]; then
  warn "the launch could not be journalled to the roster (the dispatch is unaffected): $ROSTER_FILE"
else
  if [ -n "$ABSENT" ]; then
    warn "roster row for \"${AGENT_NAME:-(unnamed)}\" records absent brief field(s): ${ABSENT//,/, }"
  fi
  # The waiver echo. A dispatch that took the escape says so out loud as it
  # passes, with the reason it gave — so the operator reads the waiver at the
  # moment it is spent, not only later off the roster row that also holds it.
  if [ -n "$C_WAIVER" ]; then
    warn "the absent-deliverable wall was waived by the brief: ${C_WAIVER}"
  fi
  # The inference echo. A filled slot is this gate's reading of the brief, not the
  # brief's own words, so it says both — what the brief spelled and what the row now
  # holds — at the one moment the brief is still editable. Silence here would leave
  # an author believing they had named a contract they had only sketched.
  if [ -n "$C_TEMPLATE_ORIGIN" ]; then
    warn "the brief spelled its deliverable as a template (${C_TEMPLATE_ORIGIN}); the row was inferred as ${C_DELIVERABLE} — name it exactly, or re-dispatch with the slot filled in"
  fi
  if [ -n "$CONTENDED_OWNER" ]; then
    warn "the deliverable ${CONTENDED_PATH} is already owned by an open roster row: \"${CONTENDED_OWNER}\" — two rows on one artifact make the second landing verdict unfalsifiable"
  fi
fi

# Present and mine: pass in silence — the allow path prints NOTHING about the check it
# just passed, which is what §4 "The start gate" bans ("Parses no check detail... Never:
# print on the allow path"). The invariant is narrower than the quote reads: what may
# never appear here is check DETAIL, the gate narrating its own reasoning. Two warn-only
# lines above do print on this path, both ratified and neither a check detail — the
# absent-brief-fields warning (a fact about the row just journalled) and the waiver echo
# (the reason a brief gave for producing nothing durable). Both are advisory, both leave
# the exit status untouched, and a silent pass is still the common case.
#
# A THIRD warn-only line stood here until epic-16 wave-02: the unarmed-sweeper nag, which
# asked a resident watcher whether it was alive and named the command to arm one. The
# watcher is deleted — supervision reads facts at the moment of decision instead of
# depending on a process staying up — so there is no arming left to nag about.
exit 0
