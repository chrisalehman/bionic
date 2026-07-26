#!/bin/bash
# REQUEST-TO-HUMAN DETECTOR: does this assistant turn ask the human for
# something? ONE question, ONE signal.
#
# Both categories the design recognises — an ACTION and a DECISION — are the
# same signal here. Classification into action-vs-decision is the MODEL's job at
# runtime, via the injected prompt. Never the detector's: a technical decision
# is also decision-shaped, so competing per-category detectors overlap and
# misfire. Detection is mechanical, judgement is not.
#
# CONSERVATIVE BY CONSTRUCTION. False positives are the expensive failure: a
# missed reframe costs what today already costs, a spurious refusal burns a turn
# and trains distrust. Only strong signals fire —
#
#   question — a `?`-terminated sentence carrying a marker that aims it at the
#              human ("should we", "do you want", "which approach", "your")
#   options  — two or more enumerated `Option N` / `Choice N` headings, the
#              shape of a menu handed over for selection
#   request  — an explicit imperative aimed at the human ("can you run",
#              "please push", "let me know", "your call", "I need you")
#
# Never "this paragraph feels decision-ish". Fenced code is stripped before
# matching: a regex holding `?` and a comment holding "you" are not an ask.
#
# Direction is load-bearing and falls out of the phrase forms: "you can run it"
# is documentation, "can you run it" is a request. Only the second fires.
#
# Two modes, ONE matching core, so the corpus baseline cannot drift from the
# hook that ships:
#   single (default) — stdin is one turn. Prints the signal names; exit 0 when
#                      a request is present, 1 when it is not (grep semantics).
#   --batch          — stdin is many turns, each introduced by a line whose
#                      first byte is SOH (\001) followed by an id. Emits
#                      `id<TAB>fired<TAB>signals` per turn. Always exit 0.
#
# Also sourceable: `. request-to-human-detector.sh` defines
# detect_request_to_human() without running anything, for the Stop hook.
#
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/ alongside the
# hook that consumes it. It is a detector, not an event hook — deliberately
# absent from MANAGED_HOOKS.

# Matching core. Every line is normalised to lowercase with punctuation other
# than sentence terminators collapsed to spaces, so word boundaries are plain
# spaces (POSIX awk has no \b) and `sign-off`, `you're`, `**Option 1**` all
# reduce to their word forms. Terminators are spaced out so a marker sitting
# immediately before a `?` still ends with a boundary.
_RTH_AWK='
function norm(s,   t) {
  t = tolower(s)
  gsub(/[^a-z0-9.?!]+/, " ", t)
  gsub(/[.?!]/, " & ", t)
  gsub(/  +/, " ", t)
  sub(/^ /, "", t); sub(/ $/, "", t)
  return " " t " "
}
function reset() { fence = 0; opts = 0; q = 0; r = 0; started = 0 }
function flush(   sig) {
  if (!started) return
  sig = ""
  if (q) sig = sig " question"
  if (opts >= 2) sig = sig " options"
  if (r) sig = sig " request"
  sub(/^ /, "", sig)
  if (batch) printf "%s\t%d\t%s\n", id, (sig != "" ? 1 : 0), (sig != "" ? sig : "-")
  else if (sig != "") { print sig; hit = 1 }
  reset()
}
BEGIN {
  SOH = sprintf("%c", 1)
  batch = (mode == "batch")
  hit = 0
  id = "-"
  reset()

  # A `?`-terminated sentence, aimed at the human by one of these markers.
  Q = "( (you|your|yours) | (should|shall|can|could|do|may|would) (i|we) " \
      "| want me to | which (option|approach|one|path|choice) | prefer )"
  S_QUESTION = Q "[^.?!]*[?]"

  # An explicit request aimed at the human. No `?` required — "let me know once
  # it resolves" is an ask however it is punctuated.
  S_REQUEST = "( (can|could|would|will) you " \
    "| please (run|push|confirm|approve|review|tell|let|paste|share|provide" \
      "|decide|pick|choose|sign|check|verify|clarify|advise|specify|say) " \
    "| let me know | up to you | say the word | (pick|choose) one " \
    "| your (call|approval|sign off|decision|preference|input|guidance|verdict) " \
    "| waiting (on|for) (you|your) | awaiting (your|approval|sign off|confirmation) " \
    "| i need (you|your) | (tell|let) me (which|what|whether|if|how) " \
    "| (should|shall) (i|we) | (do|did) you want | would you like | want me to )"

  # An enumerated menu. Two or more, at line start, explicitly labelled.
  S_OPTIONS = "^ (option|choice) [0-9a-c] "
}
batch && substr($0, 1, 1) == SOH { flush(); id = substr($0, 2); started = 1; next }
{
  if (!batch) started = 1
  if ($0 ~ /^[ \t]*```/) { fence = !fence; next }
  if (fence) next
  n = norm($0)
  if (n ~ S_OPTIONS) opts++
  if (n ~ S_QUESTION) q = 1
  if (n ~ S_REQUEST) r = 1
}
END { flush(); if (!batch) exit (hit ? 0 : 1) }
'

# stdin = one turn. stdout = signal names. rc 0 = a request is present.
detect_request_to_human() { awk -v mode=single "$_RTH_AWK"; }

# stdin = SOH-delimited turns. stdout = id<TAB>fired<TAB>signals.
detect_request_to_human_batch() { awk -v mode=batch "$_RTH_AWK"; }

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    --batch) detect_request_to_human_batch ;;
    *)       detect_request_to_human ;;
  esac
fi
