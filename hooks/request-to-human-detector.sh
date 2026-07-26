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
#   options  — a menu handed over for selection: two or more `Option N` /
#              `Choice N` headings, OR a standalone `Options:` label line
#              governing a numbered list of two or more items
#   request  — an imperative aimed at the human ("can you run", "please push",
#              "let me know", "your call", "I need you"), including a BARE
#              imperative in sentence-initial position ("Confirm the items and
#              I'll write it up", "Reply with the scope you want")
#   blocked  — an ask phrased as a statement of pendency: the work is stopped
#              and the human is named as what it is stopped ON ("paused on your
#              call", "nothing pending except your ruling")
#
# Never "this paragraph feels decision-ish". Code is stripped before matching —
# a regex holding `?` and a comment holding "you" are not an ask — in all four
# forms CommonMark recognises: ``` fences, ~~~ fences, four-space indented
# blocks, and any of those inside a blockquote. Fence state is a CHARACTER and
# a LENGTH, not a boolean, so an inner ``` cannot close an outer ````; a plain
# toggle inverts on nesting and ends up scanning the code while skipping the
# prose, which is the worst of both directions.
#
# Direction is load-bearing and falls out of the phrase forms: "you can run it"
# is documentation, "can you run it" is a request. Only the second fires. The
# same discipline governs the pendency signal — "blocked ON your call" hands the
# work over, "blocked your push" reports something that happened to them — and
# the imperative signal, where sentence-initial position is what separates
# "Confirm the rollback path" from "Confirmed: 41/41 pass".
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
function reset() { fence = ""; flen = 0; fbq = 0; ind = 0; blank = 1
                   opts = 0; label = 0; num = 0; q = 0; r = 0; b = 0; started = 0 }
function flush(   sig) {
  if (!started) return
  sig = ""
  if (q) sig = sig " question"
  # A menu is either N labelled `Option` headings, or one standalone label line
  # governing a numbered list. The label line is the discriminator: numbered
  # lists are the most common shape in ordinary work turns, and only a menu
  # announces itself before enumerating.
  if (opts >= 2 || (label >= 1 && num >= 2)) sig = sig " options"
  if (r) sig = sig " request"
  if (b) sig = sig " blocked"
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

  # A bare imperative aimed at the human — no "please", no "can you", nothing
  # but the verb in sentence-initial position. The verb set is deliberately
  # narrow: verbs that only make sense addressed to someone who owes a call.
  # Generic imperatives (take, use, run, see, check) are excluded — they are
  # how documentation talks, and they would cost false positives.
  S_IMPERATIVE = "(^ |[.?!] )(confirm|reply|pick|choose|decide|approve|specify" \
    "|clarify|advise|acknowledge|ratify|weigh in|sign off) "

  # An ask phrased as a statement of pendency: the work is stopped and the
  # human is named as what it is stopped ON. Never a question, never an
  # imperative. The preposition is load-bearing and is why this is not simply
  # (pendency-word AND "your") — "blocked ON your call" hands the work over,
  # "blocked your push" is a report of something that happened to them.
  S_BLOCKED = " (blocked|paused|parked|stalled|waiting|pending|gated|stuck" \
    "|held|holding)[^.?!]* (on|for|upon) ([^.?!]* )?your "

  # An enumerated menu. Two or more, at line start, explicitly labelled.
  S_OPTIONS = "^ (option|choice) [0-9a-c] "
  # A standalone menu label: a line that is nothing but the word, so prose like
  # "both options work" cannot match.
  S_OPTLABEL = "^ (the |your |two |three |four |five |six )?(options|choices) $"
}
batch && substr($0, 1, 1) == SOH { flush(); id = substr($0, 2); started = 1; next }
{
  if (!batch) started = 1

  # ── code blocks, all four forms CommonMark recognises ────────────────────
  # A toggle that knows only ``` scans the contents of the other three, and
  # gets NESTING exactly backwards: an inner fence flips the flag off, so inner
  # code is scanned and the prose around it is skipped. Fence state is
  # therefore a CHARACTER and a LENGTH, not a boolean.

  # A `>` prefix is a blockquote CONTAINER, not content. Strip it before asking
  # whether the line opens or closes a block, so a quoted block is recognised
  # as a block. Matching below still runs on the RAW line — quoting an ask is
  # still asking, and norm() collapses the marker to a space anyway.
  line = $0
  inbq = 0
  while (line ~ /^ ? ? ?>/) { sub(/^ ? ? ?>[ \t]?/, "", line); inbq = 1 }

  # A fence opened inside a blockquote ends where the blockquote does —
  # CommonMark closes open containers at the end of their parent. Without this,
  # one unclosed quoted block would swallow every line after it.
  if (fence != "" && fbq && !inbq) { fence = ""; flen = 0; fbq = 0 }

  if (fence != "") {
    # Close only on the SAME character, a run at least as long as the opener,
    # and nothing else on the line. That is the CommonMark rule, and it is
    # precisely what stops an inner ``` from closing an outer ````.
    if (match(line, /^ ? ? ?(`+|~+)[ \t]*$/)) {
      mark = substr(line, RSTART, RLENGTH); sub(/^ +/, "", mark); sub(/[ \t]+$/, "", mark)
      if (substr(mark, 1, 1) == fence && length(mark) >= flen) {
        fence = ""; flen = 0; fbq = 0; blank = 1; next
      }
    }
    blank = 0
    next
  }

  # An indented code block runs until the first non-blank line indented under
  # four. Interior blank lines do not end it.
  if (ind) {
    if (line ~ /^[ \t]*$/) { blank = 1; next }
    if (line ~ /^(    |\t)/) { blank = 0; next }
    ind = 0
  }

  if (line ~ /^[ \t]*$/) { blank = 1; next }

  # An opening fence: three or more backticks or tildes, indented at most
  # three. The info string on a backtick fence may not itself contain a
  # backtick, which is what keeps an inline span from opening a block.
  if (match(line, /^ ? ? ?(`+|~+)/)) {
    mark = substr(line, RSTART, RLENGTH); sub(/^ +/, "", mark)
    if (length(mark) >= 3 && (substr(mark, 1, 1) == "~" || substr(line, RSTART + RLENGTH) !~ /`/)) {
      fence = substr(mark, 1, 1); flen = length(mark); fbq = inbq; blank = 0; next
    }
  }

  # An indented code block OPENS only on a line that follows a blank one —
  # the CommonMark rule that an indented chunk cannot interrupt a paragraph,
  # and what keeps wrapped prose and hanging indents out. The residual is
  # a deliberate trade: a deeply indented list continuation sitting after a
  # blank line is treated as code and goes unscanned. That is the CHEAP
  # direction for this detector — a miss costs what today already costs, a
  # false positive burns a turn.
  if (blank && line ~ /^(    |\t)/) { ind = 1; blank = 0; next }
  blank = 0

  # Numbered-list items are counted on the RAW line: normalisation spaces out
  # the terminator, so `1.` and a sentence-ending period become the same token.
  if ($0 ~ /^[ \t]*[0-9]+[.)][ \t]/) num++
  n = norm($0)
  if (n ~ S_OPTIONS) opts++
  if (n ~ S_OPTLABEL) label++
  if (n ~ S_QUESTION) q = 1
  if (n ~ S_REQUEST || n ~ S_IMPERATIVE) r = 1
  if (n ~ S_BLOCKED) b = 1
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
