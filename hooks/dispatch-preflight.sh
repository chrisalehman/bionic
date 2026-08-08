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
#   - payload carries no session_id                      -> pass, silent (§7 table: start=open)
#   - attestation missing, unreadable, symlinked, or
#     keyed to a different session (foreign)              -> REFUSE, naming the fix command
#   - attestation present and keyed to THIS session_id    -> pass, silent
#   - brief names no deliverable and carries no waiver    -> REFUSE, naming both
#     (the absent-deliverable wall, user-directed post-w4)   the fix and the waiver
#
# Exit code 2 = block the tool call entirely in Claude Code hooks.
# [WALL: hooks/dispatch-preflight.test.sh]
#
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

set -uo pipefail

PREFLIGHT_CMD="bash ~/.claude/hooks/preflight-probe.sh"
SWEEPER_ARM_CMD="bash ~/.claude/hooks/session-sweeper.sh arm"

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
REPO=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$REPO" ] || exit 0

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

deny() {  # <reason line>...
  echo "BLOCKED: this subagent start needs a this-session environment attestation — a wave is active." >&2
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
# are the same three. Treated the same as "missing": refuse.
if [ -L "$REPO/.bionic" ] || [ -L "$REPO/.bionic/tmp" ] \
   || [ -L "$STATE_FILE" ] || [ ! -f "$STATE_FILE" ]; then
  deny "No environment attestation was found for this repo."
fi

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
ATTESTED_SID=$(grep -m1 '^session_id=' "$STATE_FILE" 2>/dev/null | cut -d= -f2-)
if [ -z "$ATTESTED_SID" ] || [ "$ATTESTED_SID" != "$PAYLOAD_SID" ]; then
  deny "The attestation on disk is not this session's (foreign, or not a valid attestation record)." \
       "It may have been written by a different session, or the record could not be read."
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
  printf '%s' "$1" | awk -v LEAD="$LEAD_CHARS" -v TRAIL="$TRAIL_CHARS" -v QUOTES="$QUOTE_CHARS" -v DOCSROOT="$DOCS_ROOT" '
    # <sep> is the regex between the label and its value; the default is the
    # colon every labeled brief field uses.
    function addlabel(txt, kind, sep) {
      NL++; LTXT[NL] = txt; LKIND[NL] = kind
      LSEP[NL] = (sep == "" ? "[ \t]*:" : sep)
    }
    function trimtok(t,   ch) {
      while (length(t) > 0) { ch = substr(t, 1, 1);         if (index(LEAD,  ch) > 0) t = substr(t, 2);                    else break }
      while (length(t) > 0) { ch = substr(t, length(t), 1); if (index(TRAIL, ch) > 0) t = substr(t, 1, length(t) - 1);     else break }
      return t
    }
    function ispath(t) {
      if (length(t) < 3)        return 0
      if (index(t, "/") == 0)   return 0
      if (t !~ /[A-Za-z]/)      return 0
      if (substr(t, 1, 1) == "-") return 0
      return 1
    }
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
      return 0
    }
    # Scans the WHOLE brief, not one label span — inference has no label to
    # bound it. First path-shaped, record-prefixed, non-tmp token wins.
    function scan_inferred(s,   n, arr, i, t) {
      n = split(s, arr, /[ \t\r\n]+/)
      for (i = 1; i <= n; i++) {
        t = trimtok(arr[i])
        if (!ispath(t)) continue
        if (is_record_path(t)) return t
      }
      return ""
    }
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
    BEGIN {
      NL = 0
      # LONGEST FIRST — see the nesting note above. `-` marks a label that only
      # BOUNDS a span; it is a real brief field, just not one the roster lifts.
      #
      # `deliverable-waiver` heads the table because it is the longest label AND
      # because it nests the shortest-but-one: a brief line reading
      # `Deliverable-waiver: <reason>` must never lift as a `deliverable`. The
      # separator rule already keeps them apart (`deliverable` requires a colon,
      # and the next character here is a hyphen), but the ordering makes the
      # intent structural rather than incidental.
      addlabel("deliverable-waiver", "waiver")
      addlabel("subprocess claims", "claims")
      addlabel("subprocess claim",  "claims")
      addlabel("expected artifacts", "deliverable")
      addlabel("expected artifact",  "deliverable")
      addlabel("progress artifact",  "progress")
      addlabel("expected duration",  "duration")
      addlabel("scope constraint",   "-")
      addlabel("exit condition",     "-")
      addlabel("progress path",      "progress")
      addlabel("deliverables",       "deliverable")
      addlabel("current step",       "-")
      addlabel("deliverable",        "deliverable")
      addlabel("constraints",        "-")
      addlabel("your slice",         "-")
      addlabel("read first",         "-")
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
      h = firsthit("deliverable")
      v = ""
      if (h > 0) { v = paths(spanof(h), 4) }
      if (v != "") { print "deliverable=" v }
      else         { v = scan_inferred(text); if (v != "") print "inferred=" v }
      h = firsthit("duration");    if (h > 0) { v = collapse(spanof(h));      if (v != "") print "duration=" v }
      h = firsthit("progress");    if (h > 0) { v = paths(spanof(h), 1);      if (v != "") print "progress=" v }
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
      h = firsthit("waiver");      if (h > 0) { v = collapse(spanof(h));      if (v != "") print "waiver=" v }
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

# record/-inference (slice 4/4, AC-8): a labeled deliverable always wins and is
# recorded `source=declared`; only when the brief named none does an unlabeled
# record/-prefixed path (never a tmp one — the awk side excludes it) step in,
# recorded `source=inferred`. An inferred path satisfies the absent-deliverable
# wall below the same way a labeled one always has, because by this point
# C_DELIVERABLE is simply non-empty either way — the wall does not know or care
# which kind it is looking at.
C_SOURCE=""
if [ -n "$C_DELIVERABLE" ]; then
  C_SOURCE="declared"
elif [ -n "$C_INFERRED" ]; then
  C_DELIVERABLE="$C_INFERRED"
  C_SOURCE="inferred"
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

# ======================================================= THE ABSENT-DELIVERABLE WALL
# (user-directed, epic-15 post-wave-04: "A wall. It should be a wall.")
#
# THE ONE PLACE below the verdict where this file changes the verdict, and it is
# deliberately narrow: exactly one absent field refuses, and only when the brief
# offers no waiver. Everything else on this path stays advisory — an absent
# progress path warns, an absent duration warns, an unarmed sweeper nags.
#
# Why this field and not the others: every downstream check the wave built is
# keyed on a durable artifact. The sweeper's delivered / not-delivered predicate
# stats the deliverable path; the stop gate asks whether the thing the agent was
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
fi

# ========================================================== UNARMED-SWEEPER NAG (slice 4/3)
#
# Warn-only, AC-6: no live sweeper watching this session's roster names the arm command;
# a live one is silent. NEVER blocks either way (ratified: no new walls) — this is a nag,
# not a wall, and it runs only on a launch that is actually about to happen (the gate has
# already decided to allow it by this point).
#
# Liveness is read by invoking the SIBLING hooks/session-sweeper.sh's own `status` verb,
# dirname-relative to THIS script, rather than a second hand-rolled ledger parser — so this
# nag and the sweeper's own arm-refusal read the identical ledger through the identical
# code and can never disagree (spec ownership table row "live-arming state"). `status`
# exits 1 for "not live" and 0 for "live"; any other exit (missing sibling, usage error) is
# an ambiguity this nag stays silent on, the same fail-open direction as the rest of §7.
_hooks_dir="$(cd "$(dirname "$0")" && pwd)"
_sweeper_status_rc=""
if [ -f "$_hooks_dir/session-sweeper.sh" ]; then
  ( cd "$REPO" && env CLAUDE_CODE_SESSION_ID="$PAYLOAD_SID" bash "$_hooks_dir/session-sweeper.sh" status ) \
    >/dev/null 2>/dev/null
  _sweeper_status_rc=$?
fi
[ "$_sweeper_status_rc" = "1" ] && \
  warn "no session sweeper is armed for this session; arm one with: ${SWEEPER_ARM_CMD}"

# Present and mine: pass in silence — the allow path prints NOTHING about the check it
# just passed, which is what §4 "The start gate" bans ("Parses no check detail... Never:
# print on the allow path"). The invariant is narrower than the quote reads: what may
# never appear here is check DETAIL, the gate narrating its own reasoning. Three warn-only
# lines above do print on this path, all ratified and none a check detail — the
# absent-brief-fields warning (a fact about the row just journalled), the waiver echo (the
# reason a brief gave for producing nothing durable), and the unarmed-sweeper nag (a fact
# about this session's watching). All three are advisory, all three leave the exit status
# untouched, and a silent pass is still the common case.
exit 0
