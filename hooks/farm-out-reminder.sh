#!/bin/bash
# FARM-OUT: tiered PreToolUse(Bash) enforcement — long-running main-thread
# commands DENY with a redirect to the right role; fuzzy production-shaped
# commands get ONE additionalContext nudge per class per session; every
# tier-1/tier-2 event logs one line to
# $HOME/.claude/logs/<project-slug>/sdlc-audit.md — outside every consuming
# project tree (incident 0001) — via audit_path() (log_finding() shape, own
# copy — deliberate per-hook duplication).
#
# Exit 0 on EVERY path. Enforcement lives in stdout JSON only:
#   deny  → hookSpecificOutput.permissionDecision "deny" + redirect reason
#   nudge → hookSpecificOutput.additionalContext
# Never "allow", never updatedInput, never exit 2 (epic-08 wave-04 ADR-002;
# amends D14 per user ratification 2026-07-20).
# [UNENFORCED]
#
# Thread discrimination (epic-08 Q1 spike + hooks docs): agent_type
# non-empty → subagent → silent. Missing keys classify as MAIN THREAD.
# Registered once in hooks/hooks.json, always on — and gated on an ON-DISK fact
# rather than on whether a skill happens to be armed: the hook asks `engaged_session`
# whether THIS session invoked canonical-sdlc in this tree and exits silently when it
# did not. That gate is not cosmetic: always-on registration without it would deny
# tier-1 Bash commands in every project on the machine, wave or no wave. Engagement is
# the whole of the scope — no plan is consulted (step-6 review R-1).

set -u

command -v jq >/dev/null 2>&1 || exit 0
BIONIC_INPUT=$(cat) || exit 0
[ -n "$BIONIC_INPUT" ] || exit 0

_jq() { printf '%s' "$BIONIC_INPUT" | jq -r "$1 // empty" 2>/dev/null || printf ''; }

AGENT_TYPE=$(_jq '.agent_type');   [ -n "$AGENT_TYPE" ] && exit 0
TOOL_NAME=$(_jq '.tool_name');     [ "$TOOL_NAME" = "Bash" ] || exit 0
CMD=$(_jq '.tool_input.command');  [ -n "$CMD" ] || exit 0

# ── the library ──────────────────────────────────────────────────────────────
# The command classifier, the root, the run predicate and the session id. One idiom,
# byte-identical in every hook; its source of truth is payload/scripts/lib/loader.sh.
#
# FAIL OPEN (design ledger S4). This wall guards a WORKFLOW PREFERENCE — where a
# long-running command runs — not irreversible damage. Refusing every Bash call in
# every project because a file is missing buys no safety and costs the session, so
# the hook prints one line and steps aside. Until 1.4.0 it denied instead, on the
# same reasoning the two irreversible-action walls still use; the cost of THAT
# mistake is what separates them.
BIONIC_LIB_WANT="cmd-class.sh context.sh refuse.sh root.sh run.sh session.sh"
# --- bionic-loader/v2 BEGIN
# Find the bionic library — pasted BYTE-IDENTICALLY into all 22 carriers, because a library
# cannot load itself. payload/scripts/lib/loader.sh owns this text and its header holds the
# long form; §N.1 of tests/cross-gate-agreement.test.sh pins and caps every copy, and
# tests/loader.test.sh drives the behaviour. BIONIC_LIB_WANT, set on the line above, names
# the basenames this hook sources; afterwards exactly one of BIONIC_LIB (a directory holding
# all of them) and BIONIC_LIB_MISSING is non-empty. CANDIDATES, each class reached only when
# the earlier one fails: (1) beside the hook in BOTH spellings, since `..` resolves after the
# payload/hooks symlink; (2) the marketplace source tree, read from the registry and never
# assumed; (3) the newest version in that marketplace's cache, by THREE-INTEGER compare —
# 1.10.0 beats 1.3.2, which a lexical sort gets backwards. (2) and (3) heal a partly damaged
# install, so one broken location cannot lock the user out of the repair (R-1 §(5)).
BIONIC_LIB=""; BIONIC_LIB_MISSING=""; BIONIC_LIB_CANDS=""
_bl_dir="$(dirname "$0")"; _bl_want="${BIONIC_LIB_WANT:-}"
_bl_try() {
  [ -n "${1:-}" ] || return 1
  if [ -z "$BIONIC_LIB_CANDS" ]; then BIONIC_LIB_CANDS="$1"; else BIONIC_LIB_CANDS="$BIONIC_LIB_CANDS, $1"; fi
  [ -d "$1" ] || return 1
  for _bl_f in $_bl_want; do [ -r "$1/$_bl_f" ] || return 1; done
  BIONIC_LIB="$1"
}
if ! _bl_try "$_bl_dir/../scripts/lib" && ! _bl_try "$_bl_dir/../payload/scripts/lib"; then
  _bl_pd="${BIONIC_PLUGINS_DIR:-${HOME:-/nonexistent}/.claude/plugins}"; _bl_mk=""
  if [ -r "$_bl_pd/installed_plugins.json" ]; then
    _bl_keys="$(jq -r '(.plugins // {}) | keys[] | select(startswith("bionic@"))' "$_bl_pd/installed_plugins.json" 2>/dev/null)"
    _bl_mk="${_bl_keys%%
*}"
    _bl_mk="${_bl_mk#bionic@}"
  fi
  if [ -n "$_bl_mk" ]; then
    _bl_src=""
    if [ -r "$_bl_pd/known_marketplaces.json" ]; then
      _bl_src="$(jq -r --arg mk "$_bl_mk" '.[$mk].source.path // empty' "$_bl_pd/known_marketplaces.json" 2>/dev/null)"
    fi
    if [ -n "$_bl_src" ]; then _bl_try "$_bl_src/payload/scripts/lib" || :; fi
    if [ -z "$BIONIC_LIB" ]; then
      _bl_best=""; _bl_bestk=""
      for _bl_v in "$_bl_pd/cache/$_bl_mk/bionic"/*; do
        [ -d "$_bl_v" ] || continue
        _bl_n="${_bl_v##*/}"
        case "$_bl_n" in ''|*[!0-9.]*) continue ;; esac
        _bl_x1=""; _bl_x2=""; _bl_x3=""
        IFS=. read -r _bl_x1 _bl_x2 _bl_x3 _bl_rest <<BIONIC_LOADER_VER
$_bl_n
BIONIC_LOADER_VER
        _bl_k="$(printf '%05d%05d%05d' "$((10#${_bl_x1:-0}))" "$((10#${_bl_x2:-0}))" "$((10#${_bl_x3:-0}))" 2>/dev/null)" || continue
        if [ -z "$_bl_bestk" ] || [ "$_bl_k" \> "$_bl_bestk" ]; then _bl_bestk="$_bl_k"; _bl_best="$_bl_n"; fi
      done
      if [ -n "$_bl_best" ]; then _bl_try "$_bl_pd/cache/$_bl_mk/bionic/$_bl_best/scripts/lib" || :; fi
    fi
  fi
fi
if [ -z "$BIONIC_LIB" ]; then
  BIONIC_LIB_MISSING="${_bl_want%% *}"
  [ -n "$BIONIC_LIB_MISSING" ] || BIONIC_LIB_MISSING="scripts/lib"
fi
loader_fail_open() {
  echo "$1: library ${BIONIC_LIB_MISSING:-the bionic library} not found at ${BIONIC_LIB_CANDS:-(no candidate)} — hook stepping aside; run /bionic:doctor" >&2
  exit 0
}
loader_fail_closed() {
  _bl_root="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)" || _bl_root=""
  [ -n "$_bl_root" ] || _bl_root="$(dirname "$0")/.."
  case "${2:-}" in
    "claude plugin update bionic@bionic"|\
    "claude plugin install bionic@bionic"|\
    "bash $_bl_root/scripts/doctor.sh"|\
    "bash $_bl_root/scripts/setup.sh") exit 0 ;;
  esac
  _bl_who="${1:-a bionic hook}"
  if [ "${#_bl_who}" -gt 25 ]; then _bl_who="${_bl_who:0:24}…"; fi
  printf 'bionic: load refused — %s cannot load the bionic library (run /bionic:doctor)\n' "$_bl_who" >&2
  if [ "${BIONIC_WALL_VERBOSE:-}" = "1" ]; then
    cat >&2 <<BIONIC_LOADER_REFUSE
A wall that cannot read a command refuses it rather than waving it through.

Wanted: ${BIONIC_LIB_MISSING:-the bionic library}
Looked in: ${BIONIC_LIB_CANDS:-(no candidate)}

Until the plugin is whole again this wall permits exactly four commands, each matched
as a whole string:

    claude plugin update bionic@bionic
    claude plugin install bionic@bionic
    bash $_bl_root/scripts/doctor.sh
    bash $_bl_root/scripts/setup.sh

Anything else is refused, including one of those four with another command chained
after it. Run one of them, or act from your own terminal.
BIONIC_LOADER_REFUSE
  fi
  exit 2
}
# --- bionic-loader/v2 END
if [ -n "$BIONIC_LIB_MISSING" ]; then loader_fail_open "farm-out-reminder"; fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/cmd-class.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/context.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/refuse.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/root.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/run.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/session.sh"

# THE ROOT AND THE SESSION ID, from their one owner (REQ-1f, lib/context.sh).
# `project_root` walks to the nearest real `.bionic` ancestor rather than trusting
# whatever directory invoked the hook — the audit file and the config below both hang
# off the answer, and a worktree that answered with its own tree would write a second
# audit stream for one project.
#
# THE `unknown` SUBSTITUTION IS GONE (REQ-1h). An empty session id used to become that
# literal and carry on to be refused by name one guard later; the library returns 1 and
# this hook exits, which is the same silence by a route that never forms a state path
# out of a value it has already judged unusable.
bionic_context 2>/dev/null || exit 0

# ---------- THE ENGAGEMENT GUARD (AC-6): is this session bionic's at all? ----------
#
# FIRST, above the run predicate and above the FARM_OUT_ALLOW override both. Chris,
# 2026-09-03: "all guardrails imposed by bionic should only apply when exercising
# bionic. Nothing should apply until bionic is triggered" — and the trigger is the
# canonical-sdlc skill, which writes `.bionic/tmp/engaged-<sid>.state` at the instant it
# is invoked. A session that never invoked it gets no nudge, no deny and no audit line:
# exit 0, no stdout, no stderr.
#
# ABOVE THE OVERRIDE for the same reason the run predicate is: FARM_OUT_ALLOW=1 exists
# to bypass a wall that is binding, and where the wall is inert there is nothing to
# bypass. An audit line recording an "override" of a wall that was never going to fire
# is noise in the one stream that has to stay readable.
#
# EVERY UNREADABLE STATE READS AS NOT ENGAGED — an absent marker, a symlink at the path,
# a foreign key — because the arming partition is the consent boundary (1.3.2 close-out).
# An unshaped key never reaches here at all: `bionic_context` refused it above.
# [WALL: tests/cmd-class.test.sh]
[ "$BIONIC_ENGAGED" = 1 ] || exit 0

# ── NO RUN PREDICATE HERE, DELIBERATELY (step-6 review R-1) ──────────────────
#
# This hook used to ask `active_run` for an open canonical-sdlc run and exit silently
# without one. That gate is gone. The nudge is PLAN-FREE: engagement decides whether a
# bionic wall speaks at all, and knowing that a suite command belongs in a subagent
# needs no plan — the sessions most in need of the reminder are the ones in Step 0
# through Step 3, which have not written one yet. Adding the predicate back would
# re-open the hole R-1 named.
# [WALL: tests/cmd-class.test.sh]



MODE="block"
if [ -f "$BIONIC_ROOT/.bionic/config.yaml" ]; then
  _cfg=$(grep -E '^farm-out-mode:' "$BIONIC_ROOT/.bionic/config.yaml" 2>/dev/null | head -1 \
    | sed 's/^farm-out-mode:[[:space:]]*//' | tr -d '\r' | sed 's/[[:space:]]*$//')
  case "$_cfg" in block|advisory|off) MODE="$_cfg" ;; esac
fi
[ "$MODE" = "off" ] && exit 0

# Normalized single-line form for matching + the scrubbed deny reason (CR translate).
FLAT=$(printf '%s' "$CMD" | awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' | tr '\n' ' ' \
  | sed 's/[[:space:]]\{1,\}/ /g; s/^ //; s/ $//')

# Incident 0001: the audit stream must live where a consuming project cannot
# commit it, regardless of that project's .gitignore. $HOME-rooted, per-project,
# durable — the same $HOME/.claude/ audit path the archived epic-10 poker used
# (that work is recoverable at tag archive/epic-10-never-die).
# Slug = <basename>-<cksum of the absolute path>: readable, deterministic, and
# collision-resistant across same-named projects under different parents.
# cksum and basename are POSIX — no new dependency.
# [INSTRUMENT]
audit_path() {  # $1=project root → absolute audit-file path; rc 1 if no $HOME
  [ -n "${HOME:-}" ] || return 1
  local base sum
  base=$(basename "$1" | sed 's/[^A-Za-z0-9._-]/-/g')
  sum=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  printf '%s/.claude/logs/%s-%s/sdlc-audit.md' "$HOME" "$base" "$sum"
}

log_event() {  # $1=event $2=class
  # No command-derived text: `class=<c> mode=<m>` is the complete payload.
  # A length bound is not a sanitizer — incident 0001 leaked a live credential
  # through the former `cut -c1-120` excerpt of the raw command.
  local f
  if f=$(audit_path "$BIONIC_ROOT"); then
    local line="- $(date -u +%Y-%m-%dT%H:%M:%SZ) farm-out $1: class=$2 mode=$MODE"
    mkdir -p "$(dirname "$f")" 2>/dev/null && printf '%s\n' "$line" >> "$f" 2>/dev/null
  fi
  echo "farm-out [$1] class=$2" >&2
  return 0
}

# [WALL: tests/farm-out-reminder.test.sh]
emit_deny() {  # $1=class $2=role
  # THROUGH THE ONE RENDERER (task 13, table row 106). `deny` is the mode this hook has
  # always used and the one the E1 measurement showed carries a model-only channel, so
  # the user gets the single line and the whole existing instruction rides the JSON
  # reason unchanged. `refuse` EXITS — with status 0 on this mode, which is what the
  # JSON verdict needs — so the caller's own `exit 0` after it is unreachable and gone.
  refuse deny run "this command belongs in a subagent" "dispatch it with the Agent tool" \
    "$(deny_reason "$1" "$2")"
}

emit_nudge() {  # $1=class $2=role
  jq -n --arg c "farm-out checkpoint: $1-class command on the main thread — production-shaped work belongs in a subagent. Fix: dispatch via Agent(subagent_type: $2) when you can. This protects your own context budget; a stuck orchestrator cannot process completions. Advisory only." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}' 2>/dev/null
  return 0
}

# Pattern scrub for command-derived text (incident 0001). Two shapes:
# a hex run of 32+ (API keys, tokens, hashes) and an explicit
# KEY=/TOKEN=/SECRET= assignment. This is deliberately farm-out-local —
# no other hook in this repo interpolates raw command text.
scrub_secrets() {  # stdin → stdout
  sed -E -e 's/[A-Fa-f0-9]{32,}/[REDACTED]/g' \
         -e 's/([A-Za-z0-9_]*(KEY|TOKEN|SECRET)=)[^[:space:]]+/\1[REDACTED]/g'
}

deny_reason() {  # $1=class $2=role
  # Scrub BEFORE truncating: truncating first can split a hex run below the
  # 32-char threshold and leak a prefix.
  local safe; safe=$(printf '%s' "$FLAT" | scrub_secrets | cut -c1-120)
  printf '%s' "farm-out checkpoint: this $1-class command doesn't belong on the orchestrator thread (a stuck orchestrator is unavailable and cannot process subagent completions — this protects your own context budget). Fix: dispatch it — Agent(subagent_type: $2, prompt carrying the command from this tool call): $safe — scrubbed and truncated for the log; the agent returns the result summary. If this genuinely cannot be dispatched (needs this session's state), re-run prefixed FARM_OUT_ALLOW=1 — the override is sanctioned and audited."
}

# ── classification (B-5: argv positions, read by scripts/lib/cmd-class.sh) ───────
# override check + wrapper unwrap precede classification.

# The sed twins that used to live here — strip_prefixes() and unwrap() — are
# GONE (review-b B-4a). They were hand-rolled copies of the library's
# strip_leading()/unwrap_runner() with their own smaller rule set: the prefix
# strip knew only `env`, `FARM_OUT_*=`, `nohup` and `timeout <n>`, so a `sudo`,
# a `time`, an `xargs` or an ordinary `FOO=1` left the wrapper sitting at
# argv[0] and the tier-2 matcher below never fired. Tier-2 now reads
# cmd_unwrap_head, which is the same reduction cmd_class itself performs — one
# reader, one set of rules, and the R-12 superset applies to the nudge tier too.
# [WALL: tests/cmd-class.test.sh]

role_for_class() {  # $1=class → the role a redirect names
  case "$1" in suite) printf 'test-runner' ;; *) printf 'implementor' ;; esac
}

classify_tier1() {  # $1=command text → sets CLASS ROLE, rc 0 on match
  # ONE READER, argv-positional (payload/scripts/lib/cmd-class.sh). The regex classifier
  # this replaced matched mid-string after any space, so `make( +[^ ]+)?` denied
  # `git commit -m "make the row green"` as class=build and a heredoc body carrying
  # `bash tests/run.sh` denied as class=suite — both measured, research-b3 §2. Prose,
  # quoted strings and heredoc bodies are never argv[0], so they no longer classify.
  # A short (<3-segment) chain that carries a tier-1 command still denies here on
  # purpose; the ≥3-segment chain is a separate arm (class=chain) reached only when
  # this one skips.
  # [WALL: tests/cmd-class.test.sh]
  local c
  c=$(cmd_class "$1")
  [ "$c" = "none" ] && return 1
  CLASS="$c"; ROLE=$(role_for_class "$c")
  return 0
}

emit_tier1() {  # $1=class $2=role — deny, or downgrade to a nudge under advisory
  if [ "$MODE" = "advisory" ]; then
    log_event "deny-downgraded" "$1"; emit_nudge "$1" "$2"; exit 0
  fi
  log_event "deny" "$1"; emit_deny "$1" "$2"
}

classify_tier2() {  # $1=flat cmd → sets CLASS ROLE, rc 0 on match
  local c="$1"
  if printf '%s' "$c" | grep -qE '^git +clone([;&| ]|$)'; then CLASS="clone"; ROLE="implementor"; return 0; fi
  if printf '%s' "$c" | grep -qE '^docker +(run|pull)([;&| ]|$)'; then CLASS="docker-run"; ROLE="implementor"; return 0; fi
  if printf '%s' "$c" | grep -qE '^(npx|uvx) +'; then CLASS="pkg-exec"; ROLE="implementor"; return 0; fi
  return 1
}

nudge_once() {  # $1=class $2=role — ONE nudge per (session, class); repeat = suppressed
  local state="$BIONIC_ROOT/.bionic/tmp/farm-out.state"
  mkdir -p "$BIONIC_ROOT/.bionic/tmp" 2>/dev/null
  if [ -f "$state" ] && grep -qF "$BIONIC_SID	$1" "$state" 2>/dev/null; then
    log_event "suppressed" "$1"; return 0
  fi
  printf '%s\t%s\n' "$BIONIC_SID" "$1" >> "$state" 2>/dev/null || true
  log_event "nudge" "$1"; emit_nudge "$1" "$2"; return 0
}

# ── main flow: override → unwrap → tier-1 deny → tier-2 nudge (single + chain) ──
# Chain-aware: the override token is honored ANYWHERE in the invocation —
# leading, after a separator (;/&/|), or as an env-prefix mid-chain
# (`cd x && FARM_OUT_ALLOW=1 bash tests/run.sh`) — not only in leading
# position. W4's false fire was exactly this shape: a 2-segment &&-chain hit
# the single-command tier-1 arm before the old leading-only case ever ran.
if printf '%s' "$FLAT" | grep -qE '(^|[;&| ])FARM_OUT_ALLOW=1([;&| ]|$)'; then
  log_event "override" "user-sanctioned"; exit 0
fi

# The heredoc-free form of the command. Chain segmentation and the tier-2 matcher read
# it rather than FLAT, so a `&&` or an `npx` inside a heredoc body cannot reshape the
# decision any more than it can classify.
SAFE_FLAT=$(cmd_strip_heredocs "$CMD" \
  | awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' | tr '\n' ' ' \
  | sed 's/[[:space:]]\{1,\}/ /g; s/^ //; s/ $//')

TARGET=$(cmd_unwrap_head "$SAFE_FLAT")
CLASS=""; ROLE=""

# Chain segmentation (≥3 &&-joined segments) feeds both chain arms below;
# compute the segment list once. Empty/0 when no `&&` is present.
CHAIN_SEGS=""; CHAIN_COUNT=0
case "$SAFE_FLAT" in
  *"&&"*)
    CHAIN_SEGS=$(printf '%s' "$SAFE_FLAT" | awk '{ gsub(/&&/, "\n"); print }')
    CHAIN_COUNT=$(printf '%s\n' "$CHAIN_SEGS" | grep -cE '[^[:space:]]')
    ;;
esac

# Tier-1 single command → deny (advisory-downgrades to a nudge inside emit_tier1).
# A ≥3-segment && chain defers to the chain tier-1 arm below so it keeps its
# class=chain label: now that install/build share the suite/bootstrap segment
# anchoring, an unguarded single-command match would relabel those chains.
if [ "${CHAIN_COUNT:-0}" -lt 3 ] && classify_tier1 "$CMD"; then
  emit_tier1 "$CLASS" "$ROLE"
fi

# Chain tier-1 arm: ANY stripped/unwrapped segment matches tier-1 → deny as
# class=chain, role taken from the matching segment.
if [ "${CHAIN_COUNT:-0}" -ge 3 ]; then
  CHAIN_ROLE=""
  while IFS= read -r _seg; do
    _seg=$(printf '%s' "$_seg" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$_seg" ] || continue
    if classify_tier1 "$_seg"; then
      CHAIN_ROLE="$ROLE"; break
    fi
  done <<EOF
$CHAIN_SEGS
EOF
  [ -n "$CHAIN_ROLE" ] && emit_tier1 "chain" "$CHAIN_ROLE"
fi

# Tier-2 single command → nudge once per (session, class).
if classify_tier2 "$TARGET"; then
  nudge_once "$CLASS" "$ROLE"; exit 0
fi

# Chain tier-2 arm: ≥3 segments, NO tier-1 segment (the tier-1 arm above would
# have exited otherwise), ≥1 non-exempt segment → nudge as class=chain.
if [ "${CHAIN_COUNT:-0}" -ge 3 ]; then
  _has_nonexempt=""
  while IFS= read -r _seg; do
    _seg=$(printf '%s' "$_seg" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$_seg" ] || continue
    printf '%s' "$_seg" | grep -qE '^(git|ls|cat|head|tail|wc|grep|rg|find|awk|sed|mkdir|cp|mv|rm|touch|echo|printf|test|cd|pwd|which|command|true|false) ' \
      || { _has_nonexempt=1; break; }
  done <<EOF
$CHAIN_SEGS
EOF
  [ -n "$_has_nonexempt" ] && { nudge_once "chain" "implementor"; exit 0; }
fi

exit 0
