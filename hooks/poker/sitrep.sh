# shellcheck shell=bash
# hooks/poker/sitrep.sh — the situation report: the blind wall, the scorecard, the report and the handoff
# (fill-report, landing-report, handoff, decisions, resume, sitrep).
#
# A part of hooks/session-poker.sh, which sets every global and loads this file before any verb runs. A part
# defines functions only, and is never run by itself.

# ---------------------------------------------------------------- the blind wall
#
# THE WALL THAT ROSTERS A DISPATCH IS REGISTERED ON THE SKILL CHANNEL, not in hooks.json:
# skills/canonical-sdlc/SKILL.md's own frontmatter registers hooks/dispatch-preflight.sh
# (that partition is deliberate — the wall is armed-scoped, not always-on). A skill-channel
# registration lives in the process's `sessionHooks` table and does NOT survive a session
# continue, a `/clear`+resume, or `/reload-plugins`. When it is gone, NOTHING SAYS SO:
# dispatches launch normally, no row is written, and the first symptom is a tick REFUSING
# with "no roster" — which reads as "nothing has been dispatched yet", the exact opposite of
# what happened. Measured live 2026-08-22; the same symptom is recorded unresolved at
# .bionic/docs/record/session-20260814-wave-detector-terminal-state/min-interactive-agent-hook.md
# §6, and the cure proven the same day is to re-invoke the skill in the same process.
#
# So the tick — which already runs inside the session and already holds its session id —
# compares TWO records of the same event:
#
#   the transcript, which the CLI writes whatever the hooks do:  every `Agent` tool_use
#   the roster,     which only the wall writes:                  every dispatch it saw
#
# A gap between them is the wall's absence, observed rather than assumed. This is a
# DIAGNOSIS, not a gate: it never refuses anything, and it never touches the roster.
#
# WHAT IS DELIBERATELY NOT COUNTED, each because counting it would make a live wall look
# blind: a tool_use inside an agent context (`isSidechain`, or an explicit agent key) — a
# teammate's dispatch never reaches this wall at all (record §5a), so it can never be
# rostered and its absence is not news; and a dispatch the wall REFUSED, which exits before
# the roster append and is therefore a wall doing its job, recognized by the CLI's own
# `PreToolUse:Agent hook error:` marker in the tool result.
#
# TWO HONEST LIMITS, both a false ALARM rather than a false silence, and both cheap because
# the cure is idempotent (re-invoking the skill changes nothing when the wall is live):
# a Step-8 cleanup that wipes `.bionic/tmp` mid-session leaves the transcript's dispatches
# with no rows to match; and a transcript that quotes the refusal marker verbatim (a record
# file read into context) inflates the refusal count, which suppresses rather than raises.
#
# The transcript is resolved EXACTLY as hooks/dispatch-preflight.sh resolves it for its own
# liveness question (`roster_session_live`): a session's transcript is `<sid>.jsonl` under
# some project directory of CLAUDE_CONFIG_DIR/projects. Not resolvable means SILENT — a
# detector that cannot read cannot report. lib/said.sh no longer mirrors this scan, on purpose
# (wave-37 T5; D9, A-T5-7): the words reader decides trust and opens only this project's own
# directory names, while this one finds an address and decides nothing.

# Occurrences, never lines: a parallel fan-out puts several `Agent` tool_uses in ONE
# assistant entry, and a line-counting read would report that batch as a single dispatch.
# The literal `"name":"Agent"` cannot be forged from prose quoting it, because inside a JSON
# string every quote is backslash-escaped and the escaped form does not contain it.
#
# <since> is the window's ISO instant, empty for "the whole transcript". Comparison is on the
# entry's own `timestamp` truncated to the second — the CLI writes fractional seconds and a
# raw string compare would sort `…:23.9Z` BEFORE `…:23Z` and drop an in-window entry.
count_main_thread_dispatches() {  # <transcript> [<since ISO>] -> count on stdout
  awk -v since="${2:-}" '
    function in_window(   t) {
      if (since == "") return 1
      if (match($0, /"timestamp"[[:space:]]*:[[:space:]]*"[^"]+"/) == 0) return 1
      t = substr($0, RSTART, RLENGTH)
      sub(/^.*:[[:space:]]*"/, "", t); sub(/"$/, "", t)
      return (substr(t, 1, 19) >= substr(since, 1, 19))
    }
    /"isSidechain"[[:space:]]*:[[:space:]]*true/          { next }
    /"agent_?[Ii][dD]"[[:space:]]*:[[:space:]]*"[^"]/     { next }
    {
      # THE CHEAP TEST FIRST. A line with no compact `"name":"Agent"` literal — the shape
      # every entry this partition can count is written in, the CLI own compact
      # serialization, never a hand-spaced one — cannot hold a dispatch, so a plain
      # substring index() runs before the per-line timestamp match() inside in_window()
      # ever does. `line` is `$0` SAVED FIRST, into its own variable, because the counting
      # `gsub` below mutates whatever it is pointed at — targeting `line` rather than the
      # bare (implicit-`$0`) form keeps `$0` intact for the match() inside in_window() to
      # test against the untouched record.
      line = $0
      if (index(line, "\"name\":\"Agent\"") == 0) next
      if (in_window()) n += gsub(/"name"[[:space:]]*:[[:space:]]*"Agent"/, "", line)
    }
    END { print n+0 }
  ' "$1" 2>/dev/null
}

# A REFUSAL IS A JOIN, NOT A LITERAL. `PreToolUse:Agent hook error:` is what the CLI writes
# into a refused dispatch's tool_result — and it is ordinary text everywhere else. The plan
# that specifies this check, the reviews of it and every brief that quotes it carry the
# literal, so reading one of those files puts the marker in a tool_result of THAT read, and
# a transcript-wide grep for it counted 19 refusals in the session that wrote this line
# against a truth of 1 — the detector inert in the repository that builds it. So the marker
# is credited only where it joins BY tool_use_id to an `Agent` tool_use of this thread: the
# refused dispatch's own result. payload/scripts/lib/patrol.sh applies the identical rule
# for doctor's reconstruction, and tests/cross-gate-agreement.test.sh §Q asks both copies
# the same fixture and compares their two answers to each other.
#
# TWO REGIONS OF THE LINE, and only one of them is the result. Beside `message` the CLI
# writes a sibling `toolUseResult` field restating the same result — and for a SPAWN it
# writes the whole brief there, so a brief that quotes the marker (this one does) plants
# one on a successful dispatch's own line. The scan therefore stops at that key: `message`
# precedes it on every entry this machine has written (34k records, 0 counterexamples), and
# a tool_result never appears twice in one entry, which is what lets one line credit at
# most one refusal. If the CLI ever reorders those keys this over-credits again rather than
# going quiet — §Q's spawn-echo fixture is what would say so.
#
# ONE PASS is enough: a result cannot be written before the call it answers, so every Agent
# id is already known by the time its tool_result is read.
#
# THE SAME WINDOW as the dispatch count, and for the same reason: a refusal from the wave
# before this roster would otherwise be subtracted from a gap in this one, turning a real
# blind wall silent.
count_refused_dispatches() {  # <transcript> [<since ISO>] -> count on stdout
  awk -v since="${2:-}" '
    function quoted_value(seg,   v) {     # `"key" : "value"` -> value
      v = seg; sub(/^.*:[[:space:]]*"/, "", v); sub(/"$/, "", v); return v
    }
    function in_window(   t) {
      if (since == "") return 1
      if (match($0, /"timestamp"[[:space:]]*:[[:space:]]*"[^"]+"/) == 0) return 1
      t = substr($0, RSTART, RLENGTH)
      sub(/^.*:[[:space:]]*"/, "", t); sub(/"$/, "", t)
      return (substr(t, 1, 19) >= substr(since, 1, 19))
    }
    /"isSidechain"[[:space:]]*:[[:space:]]*true/          { next }
    /"agent_?[Ii][dD]"[[:space:]]*:[[:space:]]*"[^"]/     { next }
    !in_window()                                          { next }
    {
      # Every `Agent` tool_use on this line, by id. The CLI writes a tool_use as
      # {"type","id","name","input",...}, so the id is the last one before the name.
      rest = $0
      while (match(rest, /"name"[[:space:]]*:[[:space:]]*"Agent"/)) {
        head = substr(rest, 1, RSTART - 1)
        rest = substr(rest, RSTART + RLENGTH)
        if (match(head, /.*"id"[[:space:]]*:[[:space:]]*"[^"]+"/))
          isagent[quoted_value(substr(head, RSTART, RLENGTH))] = 1
      }

      cut = index($0, "\"toolUseResult\"")
      region = (cut > 0) ? substr($0, 1, cut - 1) : $0
      if (index(region, "PreToolUse:Agent hook error:") > 0) {
        while (match(region, /"tool_use_id"[[:space:]]*:[[:space:]]*"[^"]+"/)) {
          if (quoted_value(substr(region, RSTART, RLENGTH)) in isagent) { n++; break }
          region = substr(region, RSTART + RLENGTH)
        }
      }
    }
    END { print n+0 }
  ' "$1" 2>/dev/null
}

# THE SAFE LINE (wave-38 T12; D23, AC-3.2). `safe to clear`, or `wait N minutes` while a `ready` of this plan is in
# flight: an open entry of lib/line.sh's fold (an ev=ready with no later published or returned for its row) whose
# carrier — the `<pid>:<start>` the `spawn-worktree.sh ready` subshell records — is alive by lib/slots.sh's rule.
# N is the landing's remaining measured time: the run's ready-to-landed median as landing_report prints it (the row
# itself has no landing while it is in flight; its declared size before any queue landing is measured), less the
# minutes since the entry's first ready, rounded up, at least 1 and at most the row's declared size. Several in
# flight give the largest N. Never `safe` while one runs: an unreadable record is no landing, a live carrier is one.
handoff_safe_line() {  # <plan> <root> -> the safe line
  local rec now lr med q row name com present base cand out sui car cbase cat br tr at e decl n best=0 who=""
  rec="$(_wt_proofs_path "$2" "$1" 2>/dev/null)" || rec=""
  if [ -z "$rec" ] || [ ! -f "$rec" ] || [ -L "$rec" ] || ! declare -F _line_entries >/dev/null 2>&1; then
    printf 'safe to clear\n'; return 0
  fi
  now="$(sitrep_now)"
  lr="$(landing_report "$rec" "$2" no 2>/dev/null | head -1)"
  q="$(printf '%s' "$lr" | sed -n 's/^landings: queue=\([0-9][0-9]*\).*/\1/p')"
  med="$(printf '%s' "$lr" | sed -n 's/.*ready-to-landed median=\([0-9.][0-9.]*\)m.*/\1/p')"
  while IFS="$(printf '\t')" read -r row name com present base cand out sui car cbase cat br tr; do
    [ -n "$row" ] && [ "$present" = yes ] || continue
    at="$(awk -F'|' -v r="row=$row" '
      $1 != "line/v1" || $3 != r { next }
      $2 == "ev=published" || $2 == "ev=returned" { a = ""; next }
      $2 == "ev=ready" && a == "" { for (i = 4; i <= NF; i++) if (index($i, "at=") == 1) a = substr($i, 4) }
      END { print a }' "$rec" 2>/dev/null)"
    e="$(iso_epoch "$at")"; [ -n "$e" ] || e="$now"
    decl="$(units_rows "$1" 2>/dev/null | awk -F'\t' -v r="$row" '$1 == r { s = $7; sub(/[^0-9].*$/, "", s); print s; exit }')"
    n="$(awk -v q="${q:-0}" -v m="${med:-0}" -v d="${decl:-0}" -v now="$now" -v e="$e" 'BEGIN {
      meas = (q + 0 > 0 && m + 0 > 0) ? m + 0 : d + 0
      r = meas - (now - e) / 60
      n = int(r); if (n < r) n++
      if (n < 1) n = 1
      if (d + 0 > 0 && n > d + 0) n = d + 0
      print n }')"
    if [ "$n" -gt "$best" ]; then
      best="$n"
      case "$tr" in "$2"/*) tr="${tr#"$2"/}" ;; esac
      who="$(clean "$row") is landing in $(clean "${tr:-—}"), ready since $(sitrep_clock "$e" "$now")"
    fi
  done <<EOF
$(_line_entries "$rec" "" 2>/dev/null)
EOF
  if [ "$best" -gt 0 ]; then printf 'wait %d minutes — %s\n' "$best" "$who"; else printf 'safe to clear\n'; fi
}
# THE FIVE HUMAN LINES (wave-38 T12; D23). Each is the flag's text when one is given (a line break making the next
# line a two-space continuation), else carried verbatim with its continuation lines from <src>, the previous file,
# else the stub `(to fill)`.
# Set in hooks/session-poker.sh, before any part loads: HANDOFF_HUMAN_KEYS.
handoff_human_line() {  # <key> <flag text, or empty> <src file, or empty> -> the line and its continuations
  local got=""
  if [ -n "$2" ]; then
    printf '%s\n' "$2" | awk -v k="$1" 'NR == 1 { print k ": " $0; next } { print "  " $0 }'
    return 0
  fi
  if [ -n "$3" ] && [ -f "$3" ] && [ ! -L "$3" ]; then
    got="$(awk -v k="$1: " 'f { if ($0 ~ /^[ \t]/) { print; next } exit } index($0, k) == 1 { f = 1; print }' "$3" 2>/dev/null)"
  fi
  if [ -n "$got" ]; then printf '%s\n' "$got"; else printf '%s: (to fill)\n' "$1"; fi
}
# THE REGISTER (wave-38 T13; D24, AC-3.4; wave-39 T11, D15, AC-7.1). Every ruling is a `## Δn — D<n> [qualifier] <verb>
# ["<reply>"] (<who> <date>)[: <title>]` heading in record/<wave>/design-ledger.md, or a `- D<n> …` bullet of that shape
# under a Δ (the Step-1 rulings folded in). The verbs are ruled, re-ruled, amended, amended again, ratified, final and
# withdrawn; the qualifier is one word between the number and the verb; the heading form `D<n> ruled: <title> (<who>
# <date>)` has no reply; a tail after the parenthesis that is not `: <title>` is the title. A `put (…)` proposal, a
# line of any other shape, a body line and a fenced example are not entries, so a ledger written before D24 reads as
# having none. ONE PARSER: `decisions` prints it and the resume recap's settled: lines are
# it, prefixed. The who is the parenthesis's words before its first date; a ruling with no `: <title>` after the
# parenthesis is `(untitled)`.
decisions_list() {  # <ledger> -> one line per entry: D<n> · "<reply>" · <who> <date> · <title>, in the ledger's order
  awk '
    function lead_verb(s,   i, n, vs, c) {  # the verb s opens with, followed by a space or a colon; "" when none
      n = split("amended again|amended|re-ruled|ruled|ratified|final|withdrawn", vs, "|")
      for (i = 1; i <= n; i++) {
        if (index(s, vs[i]) != 1) continue
        c = substr(s, length(vs[i]) + 1, 1)
        if (c == " " || c == ":") return vs[i]
      }
      return ""
    }
    function entry(s,   n, rest, verb, qual, reply, hasreply, q, i, depth, inq, ch, fin, c, paren, tail, title, who, date, field) {
      if (!match(s, /^D[0-9]+ /)) return
      n = substr(s, 1, RLENGTH - 1); rest = substr(s, RLENGTH + 1)
      verb = lead_verb(rest); qual = ""
      if (verb == "") {
        if (!match(rest, /^[A-Za-z][A-Za-z0-9_-]* /)) return
        qual = substr(rest, 1, RLENGTH - 1); rest = substr(rest, RLENGTH + 1)
        verb = lead_verb(rest); if (verb == "") return
      }
      rest = substr(rest, length(verb) + 1); hasreply = 0; reply = ""; paren = ""
      if (substr(rest, 1, 1) == ":") {
        rest = substr(rest, 2); sub(/^[ \t]+/, "", rest)
        if (substr(rest, length(rest)) != ")") return
        for (i = length(rest) - 1; i >= 1; i--) {
          if (substr(rest, i, 2) != " (") continue
          c = substr(rest, i + 2, length(rest) - i - 2)
          if (match(c, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) { paren = c; title = substr(rest, 1, i - 1); break }
        }
        if (paren == "") return
      } else {
        if (index(rest, " \"") == 1) {
          rest = substr(rest, 3); q = index(rest, "\""); if (q == 0) return
          reply = substr(rest, 1, q - 1); rest = substr(rest, q + 1); hasreply = 1
        }
        if (index(rest, " (") != 1) return
        rest = substr(rest, 3); depth = 1; inq = 0; fin = 0
        for (i = 1; i <= length(rest); i++) {
          ch = substr(rest, i, 1)
          if (ch == "\"") inq = !inq
          else if (!inq && ch == "(") depth++
          else if (!inq && ch == ")" && --depth == 0) { fin = i; break }
        }
        if (!fin) fin = index(rest, ")")
        if (!fin) return
        paren = substr(rest, 1, fin - 1); tail = substr(rest, fin + 1)
        if (index(tail, ": ") == 1) title = substr(tail, 3)
        else { title = tail; sub(/^[ \t:,;]+/, "", title) }
      }
      if (!match(paren, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) return
      date = substr(paren, RSTART, RLENGTH); who = substr(paren, 1, RSTART - 1)
      sub(/^[ \t]+/, "", who); sub(/[ \t,]+$/, "", who)
      if (who == "") return
      sub(/[ \t]+$/, "", title); if (title == "") title = "(untitled)"
      field = verb; if (qual != "") field = qual " " verb
      if (hasreply) field = (field == "ruled") ? "\"" reply "\"" : field " \"" reply "\""
      print n " · " field " · " who " " date " · " title
    }
    { sub(/\r$/, "") }
    /^[ \t]*```/ { f = !f; next }
    f { next }
    index($0, "## Δ") == 1 { s = $0; sub(/^## Δ[0-9]+ — /, "", s); if (s != $0) entry(s); next }
    /^- D[0-9]+ / { entry(substr($0, 3)) }' "$1" 2>/dev/null
}
# decisions_all <docs root> -> every run's entries, each line keyed `<wave> `, waves in slug order; a ledger with no
# entry in the grammar is named once; every ADR (adrs/*/adr-*.md) follows its wave's entries, keyed by its
# frontmatter `wave:` (its directory when it has none), as `ADR-<n> · <status> · <title>`.
decisions_all() {
  local docs="$1" f slug out tab
  tab="$(printf '\t')"
  {
    for f in "$docs"/record/*/design-ledger.md; do
      [ -f "$f" ] && [ ! -L "$f" ] || continue
      slug="${f%/design-ledger.md}"; slug="${slug##*/}"
      out="$(decisions_list "$f")"
      if [ -n "$out" ]; then
        printf '%s\n' "$out" | awk -v s="$slug" '{ printf "%s\t1\t%06d\t%s %s\n", s, NR, s, $0 }'
      else
        printf '%s\t1\t000000\t%s · no register entries (a ledger written before D24)\n' "$slug" "$slug"
      fi
    done
    find "$docs/adrs" -maxdepth 2 -type f -name 'adr-*.md' 2>/dev/null | while IFS= read -r f; do
      [ -L "$f" ] && continue
      awk -v d="$(basename "$(dirname "$f")")" '
        { sub(/\r$/, "") }
        NR == 1 && $0 == "---" { fm = 1; next }
        fm && $0 == "---" { fm = 0; next }
        fm && index($0, "wave:") == 1 { w = $0; sub(/^wave:[ \t]*/, "", w); next }
        fm && index($0, "status:") == 1 { st = $0; sub(/^status:[ \t]*/, "", st); next }
        !fm && h == "" && index($0, "# ") == 1 { h = substr($0, 3) }
        END {
          if (h == "") exit
          num = "ADR-?"; if (match(h, /^ADR-[0-9]+/)) num = substr(h, 1, RLENGTH)
          t = h; sub(/^ADR-[0-9]+[ \t]*(—|:)[ \t]*/, "", t)
          if (w == "") w = d; if (st == "") st = "(no status)"
          printf "%s\t2\t%s\t%s %s · %s · %s\n", w, num, w, num, st, t
        }' "$f" 2>/dev/null
    done
  } | LC_ALL=C sort -t "$tab" -k1,1 -k2,2n -k3,3 | cut -f4-
}
# ---------------------------------------------------------------- the run's scorecard
#
# THE SCORECARD (wave-38 T15; D26 "a release's efficiency claim is a printed scorecard; human time is always its own
# line"). `landing-report --scorecard [<plan>]` prints exactly four lines, each measured value beside its target,
#
#   human stops (autonomous half): <n> · target 1
#   agent minutes after the final reply: <n> · target 0
#   widest landing ready→landed: <row> <m> min · target < <LINE_LANDING_BAR, the landing bar: 15>
#   human-wait minutes: <n> · no target (the user's)
#
# then the sitrep's three indicator lines at close, schedule, correctness and waste, each folded line joined back to
# one, cut from `sitrep_render`'s Score (computed there, once). Every number is read from the record, and one the
# record cannot compute is
# `unverified` (D9), never a literal:
#   human stops     the plan's `approved: <name> by <who> <ISO> "<reply>"` lines under ## SDLC State (`approve`, the
#                   final card's replay) dated after its `approved-by:` instant, where the autonomous half starts; one
#                   stop per reply: in time order, a new stop when the reply's words differ from the line before or
#                   SCORECARD_STOP_GAP seconds passed (one replay writes release and merge a second apart).
#                   unverified when approved-by: names no instant.
#   agent minutes   the launches of this plan on the rosters after the `approved: merge` line's instant
#                   (`handoff_dispatches_since`, the dispatch wall's intended rows; AC-1.5's fact): minutes from that
#                   reply to the last such launch, rounded up, 0 when none. unverified with no `approved: merge` line or
#                   no launch of this plan on any roster.
#   widest landing  `landing_report`'s rows: the queue landing with the largest `minutes=`, as printed. unverified when
#                   no landing is measured.
#   human-wait      the review results records (review-results-*.md beside the run's records, and the final-card-*.md
#                   an older run wrote): each page's `at=` on its `review-results/v1|plan=` (or `final-card/v1|plan=`)
#                   line to its `replied: at=`, summed and rounded. unverified with no record, or a record with no reply.
# READ-ONLY. The rosters live in .bionic/tmp, which close-out's act 3 wipes, so close-out reads this before the wipe.
# Set in hooks/session-poker.sh, before any part loads: SCORECARD_STOP_GAP.
scorecard_report() {  # <plan> <project root> -> the seven lines; rc 0
  local plan="$1" root="$2" recdir appr stops merge_at agent="unverified" widest wait ind
  recdir="$(docs_root "$root")/record/$(proof_plan_slug "$plan")"
  # the plan's start instant and approvals, one line each: `S <epoch>` then `A <epoch> <name> <reply>` per approved: line
  appr="$(awk "$_PATROL_ISO_AWK"'
    function norm(s) { if (length(s) == 17 && substr(s, 17, 1) == "Z") return substr(s, 1, 16) ":00Z"; return s }
    function inst(l,   n, t, i, e) { n = split(l, t, /[ \t]+/); for (i = 1; i <= n; i++) { e = iso2epoch(norm(t[i])); if (e >= 0) return e } return -1 }
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^##[ \t]/ { s = ($0 ~ /^##[ \t]+SDLC State/); next }
    !s { next }
    /^approved-by:/ && !seen { seen = 1; print "S\t" inst($0); next }
    /^[ \t]*-?[ \t]*approved:[ \t]/ {
      e = inst($0); if (e < 0) next
      l = $0; sub(/^[ \t]*-?[ \t]*approved:[ \t]*/, "", l); split(l, w, /[ \t]+/)
      q = index($0, "\""); print "A\t" e "\t" w[1] "\t" (q ? substr($0, q) : "")
    }' "$plan" 2>/dev/null)"
  stops="$(printf '%s\n' "$appr" | sort -t "$(printf '\t')" -k1,1r -k2,2n | awk -F'\t' -v gap="$SCORECARD_STOP_GAP" '
    $1 == "S" { start = $2; next }
    $1 == "A" && start != "" && start >= 0 && $2 > start { if (pe == "" || $4 != pw || $2 - pe > gap) c++; pe = $2; pw = $4 }
    END { if (start == "" || start < 0) print "unverified"; else print c + 0 }')"
  merge_at="$(printf '%s\n' "$appr" | awk -F'\t' '$1 == "A" && $3 == "merge" { print $2; exit }')"
  if [ -n "$merge_at" ] && [ -n "$(handoff_dispatches_since "$plan" "$root/.bionic/tmp" "")" ]; then
    agent="$(handoff_dispatches_since "$plan" "$root/.bionic/tmp" "" | awk -F'\t' -v m="$merge_at" "$_PATROL_ISO_AWK"'
      { e = iso2epoch($2); if (e > m && e - m > d) d = e - m }
      END { printf "%d\n", (d % 60 ? int(d / 60) + 1 : d / 60) }')"
  fi
  widest="$(landing_report "$(_wt_proofs_path "$root" "$plan")" "$root" yes 2>/dev/null | awk '
    NR > 1 && $2 == "queue" { for (i = 3; i <= NF; i++) if (index($i, "minutes=") == 1) { m = substr($i, 9); if (m != "-" && (b == "" || m + 0 > b + 0)) { b = m; r = $1 } } }
    END { if (b != "") print r " " b " min" }')"
  wait="$(for f in "$recdir"/review-results-*.md "$recdir"/final-card-*.md; do [ -f "$f" ] && [ ! -L "$f" ] && printf '%s\n' "$f"; done | awk "$_PATROL_ISO_AWK"'
    { file = $0; a = ""; r = ""
      while ((getline l < file) > 0) {
        if (index(l, "review-results/v1|plan=") == 1 || index(l, "final-card/v1|plan=") == 1) { n = split(l, p, "|"); for (i = 2; i <= n; i++) if (index(p[i], "at=") == 1) a = substr(p[i], 4) }
        else if (index(l, "replied: at=") == 1) { r = substr(l, 13); sub(/ .*/, "", r) }
      }
      close(file); cards++; ea = iso2epoch(a); er = iso2epoch(r)
      if (ea < 0 || er < 0 || er < ea) bad = 1; else sum += er - ea }
    END { if (!cards || bad) print "unverified"; else printf "%d\n", int(sum / 60 + 0.5) }')"
  ind="$(sitrep_render "$plan" "$root" no 2>/dev/null | awk '
    /^Score: / { f = 1; next } f && NF == 0 { exit }
    f && /^ / { if (keep) { sub(/^ +/, ""); l = l " " $0 }; next }
    f { if (keep) print l; keep = ($2 == "schedule" || $2 == "correctness" || $2 == "waste"); l = $0 }
    END { if (keep) print l }')"
  printf 'human stops (autonomous half): %s · target 1\n' "${stops:-unverified}"
  printf 'agent minutes after the final reply: %s · target 0\n' "$agent"
  printf 'widest landing ready→landed: %s · target < %s\n' "${widest:-unverified}" "$(b="$(sitrep_bar)"; printf '%s' "${b:-unverified}")"
  printf "human-wait minutes: %s · no target (the user's)\n" "${wait:-unverified}"
  printf '%s\n' "${ind:-indicators: unverified — the sitrep could not be rendered for $plan}"
  return 0
}

# ---------------------------------------------------------------- the situation report
#
# THE SITUATION REPORT'S RENDERER. One verb prints the page and every fact on it; the one judgment, the grade and
# its rationale, is the /bionic:sitrep skill's, recorded through `sitrep grade` and printed back by the verb (a
# hook never judges). The page, in order, a blank line between sections, every line folded at 92 columns:
#
#   Sitrep · <project> <release> · <weekday> <H:MM AM/PM> · step <n> of 9 · <k> of <m> tasks done
#   Bottom line        four bullets: what you owe, what is next, what is done, when it closes
#   Task list          <glyph> <step>: <name> for steps 0 to 3 and each later step with no task of its own, and
#                      <glyph> <step>/<task>: <short description> for every task in execution order; a time in
#                      parentheses, a state after " — "
#   Score: <grade> (graded <time>), or Score: not graded yet
#                      <mark> schedule, correctness, waste, decisions, goals — what each measured, in words; then
#                      `- <rationale>` when graded
#   Blocked on you     one bullet per open approve:, waive:, finding: or gate: item of the plan's run
#   Completion         the steps done of nine; the tasks done of all, with the percent
#   Predicted close    the close and its basis, or why there is none
#
# and `--line` prints only `<schedule><correctness><waste marks> · owed: <n> · <the close>`.
#
# EVERY FACT IS ANOTHER READER'S, CALLED: the tasks and sizes are `units_rows`', the longest open chain
# `units_chain`'s over `units_edges`, the landings, runs and the median ready→landed `landing_report`'s, the idle
# minutes `fill-report`'s own line, the open items `owed_list_plan`'s (the sessions bound to the plan, never the
# caller's), the admitted count `gate_state`'s, the findings `proof_findings` at `proof_finding_rating` less
# `proof_fixed`. What no reader computes is computed here, once: the declared median of the done tasks, the pace
# ratio, the marks, a red not yet answered by a green, the close.
#
# THE MARKS ENCODE DEVIATION FROM A TOLERANCE, never a work state: a measurement held against its bar is ✅ within
# it, ➖ near it, ✖️ over it, or ❔ not measurable, and its line says the bar in words. The decisions and goals lines
# print their no-record form until a reader of rounds and one of goals exist.
#
# THE CLOSE: now + max(the longest open chain, all open work ÷ the admitted count) × the measured pace, so admitting
# more can shorten the work's share and never one chain. The pace is this run's median landing over its median
# declared size, else the newest delivered run's, else there is no forecast. A plan not approved at Step 3 prints
# the no-forecast sentence; a delivered one prints its delivery and no close. No typed number feeds it: the plan's
# own `forecast:` grades the schedule mark and nothing else.
#
# THE PLAN'S TABLE WORDS NEVER PRINT: no "rows", no status name, no cell value; a read prints in words.
#
# A value the record cannot compute prints `unverified` or its no-record sentence, and its mark is ❔. Local times
# are 12-hour on this machine's clock (`sitrep_clock`); a time on another local day than now's carries its date.
# Now is BIONIC_NOW_EPOCH when set, fill-report's seam.
# The four marks, from one place. ✖️ is U+2716 U+FE0F.
# Set in hooks/session-poker.sh, before any part loads: SITREP_MARK_WITHIN, SITREP_MARK_NEAR, SITREP_MARK_OVER,
# SITREP_MARK_NONE.

# sitrep_fold -> stdin's `<continuation indent><TAB><text>` lines, each folded at 92 display columns: a wider text
# breaks at its last space that fits, every continuation opening on that many spaces. Width is counted byte-wise so
# no locale decides it: a character is one column, a four-byte one two, the three-byte mark glyphs (✅ ⬜ ⛔ ❔ ➖ ✖)
# two, U+FE0F none. A word wider than the page prints whole.
sitrep_fold() {
  LC_ALL=C awk '
    function cw(s,   t, n, w) {
      t = s; n = gsub(/[\200-\277]/, "", t); w = length(s) - n
      t = s; w -= gsub(/\357\270\217/, "", t)
      t = s; w += gsub(/[\360-\364]/, "", t)
      t = s; w += gsub(/\342\234\205|\342\254\234|\342\233\224|\342\235\224|\342\236\226|\342\234\226/, "", t)
      return w
    }
    {
      i = index($0, "\t"); k = substr($0, 1, i - 1) + 0; s = substr($0, i + 1)
      if (cw(s) <= 92) { print s; next }
      match(s, /^ */); lead = substr(s, 1, RLENGTH); s = substr(s, RLENGTH + 1)
      pad = sprintf("%" k "s", ""); n = split(s, wd, / /); l = lead wd[1]
      for (j = 2; j <= n; j++) {
        if (cw(l " " wd[j]) <= 92) l = l " " wd[j]
        else { print l; l = pad wd[j] }
      }
      print l
    }'
}

# sitrep_dur <minutes> -> `<h> h <m> min`, `<h> h` or `<m> min`, to the whole minute
sitrep_dur() {
  awk -v m="$1" 'BEGIN { m = int(m + 0.5); h = int(m / 60); r = m - h * 60
    if (h == 0) printf "%d min\n", r; else if (r == 0) printf "%d h\n", h; else printf "%d h %d min\n", h, r }'
}

# sitrep_list <cap> <word>… -> the words as prose, `A`, `A and B`, `A, B and C`, the first <cap> named and the rest
# counted (`A, B, C and 6 more`); nothing for no word
sitrep_list() {
  local cap="$1"; shift
  awk -v cap="$cap" 'BEGIN {
    n = ARGC - 1; if (n < 1) exit
    m = (n > cap) ? cap : n
    for (i = 1; i <= m; i++) s = s ((i == 1) ? "" : ((i == m && n == m) ? " and " : ", ")) ARGV[i]
    if (n > m) s = s " and " (n - m) " more"
    print s }' "$@"
}

# sitrep_approved_at <plan> -> the epoch of its `approved-by:` instant under ## SDLC State, the Step-3 approval;
# nothing when it has none
sitrep_approved_at() {
  awk "$_PATROL_ISO_AWK"'
    function norm(s) { if (length(s) == 17 && substr(s, 17, 1) == "Z") return substr(s, 1, 16) ":00Z"; return s }
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^##[ \t]/ { s = ($0 ~ /^##[ \t]+SDLC State/); next }
    s && /^approved-by:/ { n = split($0, t, /[ \t]+/); for (i = 2; i <= n; i++) { e = iso2epoch(norm(t[i])); if (e >= 0) { print e; exit } } exit }' "$1" 2>/dev/null
}

# sitrep_delivered_at <plan> -> the epoch of its Step 9 line's `delivered: <ISO>` when `run_open` calls the run
# closed; nothing for a run still open, one that cannot be read, or a plan that names no delivery
sitrep_delivered_at() {
  local at rc=0
  run_open "$1" || rc=$?
  [ "$rc" -eq 1 ] || return 0
  at="$(awk '/^[[:space:]]*-?[[:space:]]*Step 9:.*delivered:/ && match($0, /delivered:[ \t]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:]+Z?/) {
               s = substr($0, RSTART, RLENGTH); sub(/^delivered:[ \t]*/, "", s); print s; exit }' "$1" 2>/dev/null)"
  [ -n "$at" ] || return 0
  case "$at" in *T[0-9][0-9]:[0-9][0-9]Z) at="${at%Z}:00Z" ;; *T[0-9][0-9]:[0-9][0-9]) at="$at:00Z" ;; *[0-9]) at="${at}Z" ;; esac
  iso_epoch "$at"
}

sitrep_ratio_fmt() {  # <ratio> -> two places, trailing zeros dropped: 1.2, 1.37, 2
  awk -v r="$1" 'BEGIN { s = sprintf("%.2f", r); sub(/0+$/, "", s); sub(/\.$/, "", s); print s }'
}

# sitrep_pace <plan> <root> -> `<median ready→landed, as landing_report prints it><TAB><median declared><TAB><ratio>`
# for the plan's queue landings, or nothing when it has none (or no row of them declares a size). The median is
# landing_report's own figure; the declared median is the same rule over the sizes of the rows it measured.
sitrep_pace() {
  local rep med
  rep="$(landing_report "$(_wt_proofs_path "$2" "$1")" "$2" yes 2>/dev/null)"
  case "$rep" in 'landings: queue='*) : ;; *) return 0 ;; esac
  med="${rep%%$'\n'*}"; med="${med#*ready-to-landed median=}"; med="${med%%m *}"
  { printf '%s\n' "$rep" | awk 'NR > 1 && $2 == "queue" { for (i = 3; i <= NF; i++) if (index($i, "minutes=") == 1 && $i != "minutes=-") print "L\t" $1 }'
    units_rows "$1" 2>/dev/null | awk -F'\t' '{ print "R\t" $1 "\t" $7 }'
  } | awk -F'\t' -v med="$med" '
    $1 == "R" { m = ""; if (match($3, /^[0-9]+/)) m = substr($3, RSTART, RLENGTH); size[$2] = m; next }
    $1 == "L" { want[++n] = $2 }
    END {
      for (i = 1; i <= n; i++) if (size[want[i]] != "") s[++k] = size[want[i]] + 0
      if (k == 0) exit
      for (i = 2; i <= k; i++) { t = s[i]; for (j = i - 1; j >= 1 && s[j] > t; j--) s[j + 1] = s[j]; s[j + 1] = t }
      d = (k % 2) ? s[(k + 1) / 2] : (s[k / 2] + s[k / 2 + 1]) / 2
      if (d <= 0) exit
      printf "%s\t%g\t%.6f\n", med, d, med / d
    }'
}

# sitrep_bar -> the landing bar in minutes, lib/line.sh's LINE_LANDING_BAR (wave-39 T9; D12), the one constant the
# schedule line and the scorecard's target read; loaded as the stop-run record loads line.sh; nothing when unread.
sitrep_bar() {
  [ -n "${LINE_LANDING_BAR:-}" ] || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1
  case "${LINE_LANDING_BAR:-}" in ''|*[!0-9]*) return 0 ;; esac
  printf '%s\n' "$LINE_LANDING_BAR"
}

# sitrep_schedule <plan> <done> <total> <now epoch> <median ready→landed | empty> -> `<mark><TAB><text>`, the
# schedule line after its mark. Two halves, each against a bar the run cannot set for itself:
#   the clock  tasks done in the time since the plan's `approved-by:` instant (the Step-3 approval) against the
#              tasks its frontmatter `forecast: <n>h|<n>m` needs by now, total × elapsed/forecast rounded, never
#              above total: done ≥ needed within, needed ≤ 1.25 × done near, else over; not graded with no
#              approval instant or no forecast.
#   the bar    the median landing against LINE_LANDING_BAR: ≤ bar within, ≤ 1.25 × bar near, else over;
#              unmeasured before the first landing.
# The mark is the worse half, ranked over ✖️ > ➖ > ❔ > ✅, so an unmeasured half never reads within.
sitrep_schedule() {
  local plan="$1" landed="$2" total="$3" now="$4" med="$5" appr fc bar clock cg bg bt k em
  appr="$(sitrep_approved_at "$plan")"
  fc="$(plan_frontmatter_get "$plan" forecast 2>/dev/null | awk '
    match($0, /^[0-9]+(\.[0-9]+)?[hm]?$/) { v = $0 + 0; if (v > 0) { if ($0 ~ /m$/) print v; else print v * 60 } }')"
  if [ -z "$appr" ]; then cg=n; clock="the clock cannot be graded, no Step 3 approval time"
  elif [ -z "$fc" ]; then cg=n; clock="the clock cannot be graded, the plan declares no forecast"
  else
    IFS='	' read -r cg k em <<< "$(awk -v now="$now" -v a="$appr" -v f="$fc" -v l="$landed" -v t="$total" 'BEGIN {
      e = now - a; if (e < 0) e = 0
      r = e / (f * 60); if (r > 1) r = 1
      k = int(t * r + 0.5)
      g = (l >= k) ? "w" : ((k <= 1.25 * l) ? "a" : "o")
      printf "%s\t%d\t%d\n", g, k, e / 60 }')"
    clock="$landed of $total tasks done in $(sitrep_dur "$em"), the forecast's pace needs $k"
  fi
  bar="$(sitrep_bar)"
  if [ -z "$med" ]; then bg=n; bt="no landing yet against the ${bar:-unverified} min bar"
  elif [ -z "$bar" ]; then bg=n; bt="the median landing takes $(sitrep_ratio_fmt "$med") min; the bar is unverified"
  else
    bg="$(awk -v m="$med" -v b="$bar" 'BEGIN { print (m <= b) ? "w" : ((m <= 1.25 * b) ? "a" : "o") }')"
    bt="the median landing takes $(sitrep_ratio_fmt "$med") min, $([ "$bg" = w ] && echo within || echo over) the ${bar} min bar"
  fi
  case "$cg$bg" in
    *o*) printf '%s' "$SITREP_MARK_OVER" ;;
    *a*) printf '%s' "$SITREP_MARK_NEAR" ;;
    *n*) printf '%s' "$SITREP_MARK_NONE" ;;
    *)   printf '%s' "$SITREP_MARK_WITHIN" ;;
  esac
  printf '\tschedule — %s; %s\n' "$clock" "$bt"
}

# sitrep_prev <root> <plan> -> `<slug><TAB><ratio>` of the newest delivered run under the docs root other than
# <plan> (its Step 9 line's `delivered:` instant, newest; `bind_delivered`'s test), measured by `sitrep_pace`
# over its own landing record; nothing when there is none or it measured no landing.
sitrep_prev() {
  local root="$1" self f c at best="" bestat="" pace
  declare -F _run_candidates >/dev/null 2>&1 && declare -F bind_delivered >/dev/null 2>&1 || return 0
  self="$(_bind_resolve "$2" 2>/dev/null)" || self="$2"
  while IFS= read -r -d '' f; do
    c="$(_bind_resolve "$f" 2>/dev/null)" || continue
    [ "$c" != "$self" ] || continue
    at="$(awk '/^[[:space:]]*-?[[:space:]]*Step 9:.*delivered:/ && match($0, /delivered:[ \t]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:]+Z?/) {
                 s = substr($0, RSTART, RLENGTH); sub(/^delivered:[ \t]*/, "", s); print s; exit }' "$f" 2>/dev/null)"
    [ -n "$at" ] || continue
    bind_delivered "$root" "$c" || continue
    if [ -z "$bestat" ] || [[ "$at" > "$bestat" ]]; then best="$f"; bestat="$at"; fi
  done < <(_run_candidates "$(docs_root "$root")" 2>/dev/null)
  [ -n "$best" ] || return 0
  pace="$(sitrep_pace "$best" "$root")"
  [ -n "$pace" ] || return 0
  printf '%s\t%s\n' "$(proof_plan_slug "$best")" "${pace##*$'\t'}"
}

# sitrep_open_s12 <plan> <root> -> the number of open S1 and S2 findings of the plan's registered readings: a
# finding `disposition` would print state=open (its effective priority fix, and no fix of it landed).
sitrep_open_s12() {
  local plan="$1" root="$2" docs fixed reads ev q h got num s r n=0
  declare -F proof_findings >/dev/null 2>&1 || { echo 0; return 0; }
  docs="$(docs_root "$root")"
  fixed="$(proof_fixed "$plan" "$root" 2>/dev/null)"
  reads="$(awk "$(proof_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && proof_fields($0) && PROOF_KIND == "review" && PROOF_QUESTION != "" && PROOF_EVIDENCE != "" {
      if (!(PROOF_EVIDENCE in q)) ord[++n] = PROOF_EVIDENCE
      q[PROOF_EVIDENCE] = PROOF_QUESTION; h[PROOF_EVIDENCE] = PROOF_HEAD
    }
    END { for (i = 1; i <= n; i++) printf "%s\t%s\t%s\n", ord[i], q[ord[i]], h[ord[i]] }' "$plan" 2>/dev/null)"
  while IFS='	' read -r ev q h; do
    [ -n "$ev" ] || continue
    got="$(proof_findings "$docs/$ev" 2>/dev/null)" || continue
    _proof_fixed_var "$fixed" "$ev" "$h" "$root"
    while IFS='	' read -r num s r _ _ _ _; do
      case "$num:$s" in debt:*|:*) continue ;; *:S1|*:S2) : ;; *) continue ;; esac
      case "$_PROOF_FIXED_IDS" in *$'\n'"$ev#$num"$'\n'*) continue ;; esac
      set -- $(proof_finding_rating "$plan" "$ev#$num" "$s" "$r")
      [ "${3:-}" != fix ] || n=$((n + 1))
    done <<SITREP_FINDINGS
$got
SITREP_FINDINGS
  done <<SITREP_READINGS
$reads
SITREP_READINGS
  echo "$n"
}

# sitrep_reds <landing record> -> one line per row holding a red at head (`R<TAB><row>`), then `N<TAB><count>`
# of red runs at head. A red is at head while it is its row and suite's newest verdict and the row has not been
# published since; a later green on that row and suite, or the row's landing, answers it.
sitrep_reds() {
  [ -f "$1" ] && [ ! -L "$1" ] || { printf 'N\t0\n'; return 0; }
  awk -F'|' '
    function fv(k,   i) { for (i = 2; i <= NF; i++) if (index($i, k "=") == 1) return substr($i, length(k) + 2); return "" }
    index($0, "line/v1|") != 1 { next }
    { ev = fv("ev"); rk = fv("row") }
    ev == "verdict" && fv("kind") == "regression" { next }   # facts of the whole run (wave-39 T24; D9): no row holds them
    ev == "verdict" && rk != "" { k = rk SUBSEP fv("suite"); if (!(k in seen)) { seen[k] = 1; ord[++n] = k }; last[k] = fv("result"); next }
    ev == "published" && rk != "" { for (i = 1; i <= n; i++) { split(ord[i], p, SUBSEP); if (p[1] == rk) last[ord[i]] = "landed" } }
    END {
      for (i = 1; i <= n; i++) if (last[ord[i]] == "red") { split(ord[i], p, SUBSEP); c++; if (!(p[1] in said)) { said[p[1]] = 1; printf "R\t%s\n", p[1] } }
      printf "N\t%d\n", c + 0
    }' "$1"
}

# sitrep_render <plan> <root> <line yes|no> -> the page, or with `yes` the one line; rc 0
sitrep_render() {
  local plan="$1" root="$2" line="$3" now slug recdir rec rows owed reds red_rows nred lr lr1 pace
  local s_mark s_text c_mark c_text w_mark w_text ty gl lab desc kind note glyph
  local idle_min elapsed i_pct d_pct prev ratio s_med s_decl width admitted chain cids cmins work
  local landed=0 active=0 pending=0 redn=0 total=0 approvals lmed="" appr_at dlv_at cur
  now="$(sitrep_now)"
  slug="$(proof_plan_slug "$plan")"
  recdir="$(docs_root "$root")/record/$slug"
  rec="$(_wt_proofs_path "$root" "$plan")"
  rows="$(units_rows "$plan" 2>/dev/null)"
  # What the person owes: the four kinds that are theirs, from the stores of the sessions bound to this plan.
  owed="$( { owed_list_plan "$plan" "$root" 2>/dev/null || :; } | awk -F'\t' '$1 ~ /^(approve|waive|finding|gate):/')"
  approvals="$(printf '%s\n' "$owed" | awk -F'\t' 'index($1, "approve:") == 1 { print substr($1, 9) }')"
  reds="$(sitrep_reds "$rec")"
  red_rows="$(printf '%s\n' "$reds" | awk -F'\t' '$1 == "R" { print $2 }')"
  nred="$(printf '%s\n' "$reds" | awk -F'\t' '$1 == "N" { print $2 }')"
  lr="$(landing_report "$rec" "$root" yes 2>/dev/null)"; lr1="${lr%%$'\n'*}"
  # the median ready→landed, landing_report's own figure, once a queue landing is measured (its lines say so)
  if printf '%s\n' "$lr" | awk 'NR > 1 && $2 == "queue" { for (i = 3; i <= NF; i++) if (index($i, "minutes=") == 1 && $i != "minutes=-") f = 1 } END { exit !f }'; then
    lmed="${lr1#*ready-to-landed median=}"; lmed="${lmed%%m *}"
  fi
  appr_at="$(sitrep_approved_at "$plan")"
  dlv_at="$(sitrep_delivered_at "$plan")"
  cur="$(awk '/^[[:space:]]*```/ { f = !f; next } !f && /^[[:space:]]*current[[:space:]]*:/ { s = $0; sub(/^[^:]*:[ \t]*/, "", s); sub(/[^0-9].*$/, "", s); print s; exit }' "$plan")"

  # ---- The Task list: the attended steps 0 to 3, each with its approval time, then every task in EXECUTION ORDER,
  # then each later step with no task of its own. One line each, `<glyph> <step>/<task>: <short>`, then a time in
  # parentheses or a state after " — ":
  #   done       by landing time, with it; the time is read from the task's `- T<n>:` line wherever it sits on it,
  #              `landed <sha> <ISO>` or `landed-by-hand: <who> <ISO> "<why>"` (`by hand` said), the earlier of the
  #              two when both appear, after any text; a done task whose line names no instant follows them, so said;
  #   in flight  by their place on the line, lib/line.sh's fold read as it stands (read-only: no git counting, no
  #              liveness), saying what each does: `in its landing, <n> of <m> suites green` (a candidate built),
  #              `queued on the line behind <task>` or `next on the line` (none built yet), or `building`;
  #   the rest   in dependency order over `units_edges` (a task after every open task it waits on, else table
  #              order), each saying what it `waits on` (`units_waiting`: the writer task, else the read in words;
  #              five named, the rest counted); a task not started is bare, a held one says so.
  # A task with a red at head or waiting on an approval the person owes is blocked (⛔); a red says so first.
  local sit lq="" lwait ledges
  if [ -f "$rec" ] && [ ! -L "$rec" ] \
     && { declare -F _line_fold >/dev/null 2>&1 || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; } \
     && declare -F _line_fold >/dev/null 2>&1; then
    lq="$(_line_fold "$rec" | awk -F'\t' 'NF >= 9 { m = 0; if ($9 != "none" && $9 != "") m = split($9, s, ","); printf "Q\t%s\t%s\t%s\t%d\t%d\n", $1, $5, $8, $12 + 0, m }')"
  fi
  lwait="$(units_waiting "$plan" "$(fill_step_token "$plan" 2>/dev/null)" 2>/dev/null | awk -F'\t' 'NF >= 3 { print "W\t" $1 "\t" $2 "\t" $3 }')"
  ledges="$(units_edges "$plan" 2>/dev/null | awk -F'\t' 'NF >= 2 { print "E\t" $1 "\t" $2 }')"
  sit="$( { printf '%s\n' "$red_rows" | awk 'NF { print "X\t" $1 }'
            printf '%s\n' "$approvals" | awk 'NF { print "A\t" $1 }'
            awk "$_PATROL_ISO_AWK"'
              function norm(s) { if (length(s) == 17 && substr(s, 17, 1) == "Z") return substr(s, 1, 16) ":00Z"; return s }
              function iso_in(s) {
                if (match(s, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9](:[0-9][0-9])?Z/)) return norm(substr(s, RSTART, RLENGTH))
                return ""
              }
              /^[ \t]*```/ { fence = !fence; next }
              fence { next }
              /^##[ \t]/ { s = ($0 ~ /^##[ \t]+SDLC State/); next }
              !s { next }
              /^current:/ { c = $0; sub(/^current:[ \t]*/, "", c); sub(/[^0-9].*$/, "", c); if (c != "") print "C\t" c; next }
              /^approved-by:/ { a = iso_in($0); if (a != "" && iso2epoch(a) >= 0) print "AB\t" iso2epoch(a); next }
              /^- Step [0-3]:/ {
                k = substr($0, 8, 1); if (k in sseen) next; sseen[k] = 1
                t = ""; i = index($0, "approved by "); if (i) t = iso_in(substr($0, i + 12))
                e = (t == "") ? -1 : iso2epoch(t)
                print "S\t" k "\t" ((e >= 0) ? e : "-"); next
              }
              /^- T[0-9A-Za-z._-]*:/ {
                id = $2; sub(/:$/, "", id); if (id in seen) next; seen[id] = 1
                l = " " substr($0, index($0, ":") + 1)
                pb = match(l, /[ \t]landed [0-9a-f]+ [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9](:[0-9][0-9])?Z/); bs = RSTART; bl = RLENGTH
                ph = match(l, /[ \t]landed-by-hand: /); hs = RSTART; hl = RLENGTH
                t = ""; h = 0
                if (pb && (!ph || bs < hs)) t = iso_in(substr(l, bs, bl))
                else if (ph) { t = iso_in(substr(l, hs + hl)); h = 1 }
                if (t != "") { e = iso2epoch(t); if (e >= 0) print "L\t" id "\t" e "\t" h }
              }' "$plan"
            printf '%s\n' "$lq" "$lwait" "$ledges" | awk 'NF'
            printf '%s\n' "$rows" | awk -F'\t' 'NF >= 10 { print "U\t" $0 }'
          } | awk -F'\t' -v dlv="${dlv_at:+yes}" "$_ROW_SHORT_AWK"'
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function words(r) {   # a read, in words: an approval is the person'"'"'s, a step its number
      sub(/^live:/, "", r)
      if (index(r, "approval:") == 1) return "your approval of " substr(r, 10)
      if (index(r, "step:") == 1) return "step " substr(r, 6)
      return r
    }
    function row(i, kind, note,   d) {
      d = tk[i]; if (d == "") d = "—"
      if (id[i] in red && st[i] != "landed") { kind = "s"; note = (note == "") ? "red at head" : "red at head, " note }
      printf "R\t%s\t%s/%s\t%s\t%s\t%s\n", g[i], stp[i], id[i], d, kind, note
    }
    $1 == "X" { red[$2] = 1; next }
    $1 == "A" { appr[$2] = 1; next }
    $1 == "L" { land[$2] = $3; hand[$2] = $4; next }
    $1 == "C" { cur = $2; next }
    $1 == "AB" { ab = $2; next }
    $1 == "S" { sap[$2] = $3; sline[$2] = 1; next }
    $1 == "Q" { nq++; qr[nq] = $2; qc[nq] = $3; qo[nq] = $4; qg[nq] = $5; qm[nq] = $6; next }
    $1 == "W" { w = ($4 != "" && $4 != "-") ? $4 : words($3); if (!(($2, w) in wseen)) { wseen[$2, w] = 1; wait[$2] = wait[$2] (wait[$2] == "" ? "" : ", ") w }; next }
    $1 == "E" { ne++; ef[ne] = $2; et[ne] = $3; next }
    $1 == "U" {
      s = tolower(trim($11)); if (s == "dropped") next
      n++; id[n] = trim($2); stp[n] = trim($3); tk[n] = row_short($5); rd[n] = $14; st[n] = s; at[id[n]] = n
      if (stp[n] ~ /^[0-9]+$/) hasstep[stp[n] + 0] = 1
      b = 0
      if (s != "landed") {
        if (id[n] in red) b = 1
        m = split(rd[n], a, ",")
        for (k = 1; k <= m; k++) { x = trim(a[k]); sub(/^live:/, "", x); if (index(x, "approval:") == 1 && (substr(x, 10) in appr)) b = 1 }
      }
      g[n] = (s == "landed") ? "L" : (b ? "X" : (s == "active" ? "A" : "P"))
    }
    END {
      split("Configure Scope Design Plan Implement Verify Review Document Integrate Close-out", nm, " ")
      for (k = 0; k <= 3; k++) {
        e = ((k in sap) && sap[k] != "-") ? sap[k] : ""
        if (e == "" && k == 3 && ab != "") e = ab
        if (e != "") printf "S\tL\t%d\t%s\tt\t%s\n", k, nm[k + 1], e
        else if (dlv == "yes" || (cur != "" && k < cur + 0)) printf "S\tL\t%d\t%s\ts\tdone, no time on record\n", k, nm[k + 1]
        else if (cur != "" && k == cur + 0) printf "S\tA\t%d\t%s\ts\tin progress\n", k, nm[k + 1]
        else printf "S\tP\t%d\t%s\tb\t\n", k, nm[k + 1]
      }
      # done: by landing time (a tie in table order), then those whose line names no instant
      nl = 0
      for (i = 1; i <= n; i++) if (st[i] == "landed" && (id[i] in land)) {
        for (j = nl; j >= 1 && (land[id[lo[j]]] + 0 > land[id[i]] + 0); j--) lo[j + 1] = lo[j]
        lo[j + 1] = i; nl++
      }
      for (j = 1; j <= nl; j++) { i = lo[j]; row(i, hand[id[i]] ? "th" : "t", land[id[i]]) }
      for (i = 1; i <= n; i++) if (st[i] == "landed" && !(id[i] in land)) row(i, "s", "done, no time on record")
      # in flight: by place on the line, then building
      prev = ""
      for (q = 1; q <= nq; q++) {
        i = at[qr[q]]; if (i == "" || st[i] != "active" || (i in placed)) continue
        placed[i] = 1
        if (qc[q] != "-" && qc[q] != "") note = ((qo[q] == "stalled") ? "stalled in its landing, " : "in its landing, ") ((qm[q] + 0 > 0) ? qg[q] " of " qm[q] " suites green" : "no suite to run")
        else note = (prev == "") ? "next on the line" : "queued on the line behind " prev
        row(i, "s", note); prev = qr[q]
      }
      for (i = 1; i <= n; i++) if (st[i] == "active" && !(i in placed)) row(i, "s", "building")
      # the rest: dependency order, the lowest table position first among the free
      for (k = 1; k <= ne; k++) {
        a1 = at[ef[k]]; b1 = at[et[k]]
        if (a1 == "" || b1 == "" || a1 == b1) continue
        if (st[a1] == "landed" || st[a1] == "active" || st[b1] == "landed" || st[b1] == "active") continue
        if ((a1, b1) in dep) continue
        dep[a1, b1] = 1; indeg[b1]++
      }
      np = 0; for (i = 1; i <= n; i++) if (st[i] != "landed" && st[i] != "active") np++
      for (done = 0; done < np; ) {
        pick = 0
        for (i = 1; i <= n; i++) if (st[i] != "landed" && st[i] != "active" && !(i in out) && indeg[i] + 0 == 0) { pick = i; break }
        if (!pick) for (i = 1; i <= n; i++) if (st[i] != "landed" && st[i] != "active" && !(i in out)) { pick = i; break }   # a cycle: table order
        out[pick] = 1; done++
        for (j = 1; j <= n; j++) if ((pick, j) in dep) indeg[j]--
        if (st[pick] == "held") { row(pick, "s", "on hold"); continue }
        if (st[pick] != "pending" || !(id[pick] in wait)) { row(pick, "b", ""); continue }
        m = split(wait[id[pick]], wl, ", "); note = "waits on " wl[1]   # five named, the rest counted
        for (k = 2; k <= m && k <= 5; k++) note = note ", " wl[k]
        if (m > 5) note = note " and " (m - 5) " more"
        row(pick, "s", note)
      }
      # each later step that has no task of its own
      for (k = 4; k <= 9; k++) {
        if (k in hasstep) continue
        if (dlv == "yes" || (cur != "" && k < cur + 0)) printf "S\tL\t%d\t%s\tb\t\n", k, nm[k + 1]
        else if (cur != "" && k == cur + 0) printf "S\tA\t%d\t%s\ts\tin progress\n", k, nm[k + 1]
        else printf "S\tP\t%d\t%s\tb\t\n", k, nm[k + 1]
      }
    }')"
  local inflight="" blocked="" nextup="" last_id="" last_at=""
  while IFS='	' read -r ty gl lab desc kind note; do
    [ "$ty" = R ] || continue
    total=$((total + 1))
    case "$gl" in
      L) landed=$((landed + 1)); case "$kind" in t|th) last_id="${lab#*/}"; last_at="$note" ;; esac ;;
      A) active=$((active + 1)); inflight="$inflight ${lab#*/}" ;;
      X) redn=$((redn + 1)); blocked="$blocked ${lab#*/}" ;;
      *) pending=$((pending + 1)); nextup="$nextup ${lab#*/}" ;;
    esac
  done <<SITREP_SIT
$sit
SITREP_SIT

  # ---- The Score's indicators
  # the schedule mark: the clock and the bar (sitrep_schedule); the declared-size pace feeds the close only
  pace="$(sitrep_pace "$plan" "$root")"
  [ -z "$pace" ] || IFS='	' read -r s_med s_decl ratio <<< "$pace"
  IFS='	' read -r s_mark s_text <<< "$(sitrep_schedule "$plan" "$landed" "$total" "$now" "$lmed")"
  s_text="$s_mark $s_text"
  local lred="${lr1#*· runs: green=}" s12 c_reds c_find
  case "$lr1" in *'· runs: green='*) lred="${lred#* red=}"; lred="${lred%% *}" ;; *) lred=0 ;; esac
  case "$lred" in ''|*[!0-9]*) lred=0 ;; esac
  s12="$(sitrep_open_s12 "$plan" "$root")"
  if [ "${nred:-0}" -gt 1 ]; then c_reds="$nred red suites at head"
  elif [ "${nred:-0}" -eq 1 ]; then c_reds="1 red suite at head"
  elif [ "$lred" -gt 1 ]; then c_reds="$lred red suite runs, each answered by a later green"
  elif [ "$lred" -eq 1 ]; then c_reds="1 red suite run, answered by a later green"
  else c_reds="no red suite at head"; fi
  if [ "${s12:-0}" -gt 1 ]; then c_find="$s12 open S1 or S2 findings"
  elif [ "${s12:-0}" -eq 1 ]; then c_find="1 open S1 or S2 finding"
  else c_find="no open S1 or S2 finding"; fi
  if [ "${nred:-0}" -gt 0 ] || [ "${s12:-0}" -gt 0 ]; then c_mark="$SITREP_MARK_OVER"
  elif [ "$lred" -gt 0 ]; then c_mark="$SITREP_MARK_NEAR"
  else c_mark="$SITREP_MARK_WITHIN"; fi
  c_text="$c_mark correctness — $c_reds; $c_find"
  # Waste: discarded runs over runs (landing_report's counts), idle-width minutes (fill-report's) over the
  # minutes the fill ledger spans (its first line to now while the run is open, else to its last line).
  local rg rr rn rd w_disc w_idle
  case "$lr1" in
    *'· runs: green='*)
      rg="${lr1#*runs: green=}"; rg="${rg%% *}"; rr="${lr1#* red=}"; rr="${rr%% *}"
      rn="${lr1#* none=}"; rn="${rn%% *}"; rd="${lr1#* discarded=}"; rd="${rd%% *}" ;;
    *) rg=0 rr=0 rn=0 rd=0 ;;
  esac
  d_pct="$(awk -v g="$rg" -v r="$rr" -v n="$rn" -v d="$rd" 'BEGIN { t = g + r + n + d; printf "%.4f\n", (t > 0) ? d * 100 / t : 0 }')"
  idle_min="$(cd "$root" 2>/dev/null && "${BASH:-bash}" "$HOOK_DIR/session-poker.sh" fill-report "$plan" 2>/dev/null | sed -n 's/^idle minutes: \([0-9][0-9]*\)$/\1/p' | head -n 1)"
  elapsed="$(awk -v now="$now" -v open="$(run_open "$plan" && echo yes)" "$_PATROL_ISO_AWK"'
    index($0, "fill-ledger/v1|") == 1 {
      n = split($0, p, "|"); for (i = 2; i <= n; i++) if (index(p[i], "at=") == 1) { e = iso2epoch(substr(p[i], 4)); if (e >= 0) { if (f == "" || e < f) f = e; if (l == "" || e > l) l = e } }
    }
    END { if (f == "") exit; end = (open == "yes") ? now : l; if (end > f) printf "%d\n", (end - f + 30) / 60 }' "$(fill_ledger_path "$root" "$plan" 2>/dev/null)" 2>/dev/null)"
  i_pct=""
  case "$idle_min:$elapsed" in *[!0-9:]*|:*|*:) : ;; *) [ "$elapsed" -gt 0 ] && i_pct="$(awk -v i="$idle_min" -v e="$elapsed" 'BEGIN { printf "%.4f\n", i * 100 / e }')" ;; esac
  w_mark="$(awk -v d="$d_pct" -v i="${i_pct:--1}" -v w="$SITREP_MARK_WITHIN" -v n="$SITREP_MARK_NEAR" -v o="$SITREP_MARK_OVER" 'BEGIN {
    if (d < 5 && i < 10) print w; else if (d < 15 && i < 15) print n; else print o }')"
  w_disc="$(awk -v d="$d_pct" 'BEGIN { r = int(d + 0.5); if (d + 0 == 0) print "nothing discarded"; else if (r == 0) print "under 1% of suite runs discarded"; else printf "%d%% of suite runs discarded\n", r }')"
  if [ -z "$i_pct" ]; then w_idle="idle time unverified"
  else w_idle="$(awk -v i="$i_pct" 'BEGIN { r = int(i + 0.5); if (i + 0 == 0) print "no writer slot sat idle"; else if (r == 0) print "a writer slot sat idle under 1% of the time"; else printf "a writer slot sat idle %d%% of the time\n", r }')"; fi
  w_text="$w_mark waste — $w_disc; $w_idle"

  # ---- The close: the longest open chain (the tick's CHAIN) and all open work, the pace, the admitted count
  local nodes larger per wtxt cmin_txt ctext ltext btext pace_txt closes cl
  nodes="$(printf '%s\n' "$rows" | awk -F'\t' '{ s = tolower($10); gsub(/[ \t]/, "", s) } s == "pending" || s == "active" {
             m = 0; if (match($7, /^[0-9]+/)) m = substr($7, RSTART, RLENGTH); printf "N\t%s\t%d\n", $1, m }')"
  work="$(printf '%s\n' "$nodes" | awk -F'\t' '$1 == "N" { s += $3 } END { print s + 0 }')"
  chain="$( { printf '%s\n' "$nodes"
              units_edges "$plan" 2>/dev/null | awk -F'\t' 'NF >= 2 { printf "E\t%s\t%s\n", $1, $2 }'
            } | units_chain "$(printf '%s\n' "$rows" | grep -c . | awk '{ print ($1 > 0) ? $1 : 1 }')" 2>/dev/null \
            | awk -F'\t' '$1 == "chain" { print $2 "\t" $3; exit }')"
  cids="${chain%%$'\t'*}"; cmins="${chain##*$'\t'}"
  admitted="$(gate_state 2>/dev/null | sed -n 's/.* admitted=\([0-9][0-9]*\) .*/\1/p')"
  case "$admitted" in ''|*[!0-9]*) admitted=0 ;; esac
  width="$admitted"; [ "$width" -gt 0 ] || width=1
  if [ -n "$pace" ]; then
    pace_txt="the median landing takes $(sitrep_ratio_fmt "$s_med") min against $(sitrep_ratio_fmt "$s_decl") min planned, $(sitrep_ratio_fmt "$ratio")×"
  else
    prev="$(sitrep_prev "$root" "$plan")"
    if [ -n "$prev" ]; then
      ratio="${prev##*$'\t'}"
      pace_txt="$(printf '%s' "${prev%%$'\t'*}" | awk -F- '$1 == "wave" && NF >= 2 { print $1 "-" $2; next } { print }')'s measured $(sitrep_ratio_fmt "$ratio")×; no landing yet on this run"
    else
      ratio=""
    fi
  fi
  set --
  if [ -n "$dlv_at" ]; then
    cl="$(sitrep_clock "$dlv_at" "$now")"
    set -- "Delivered at $cl; nothing is left to forecast."
    btext="delivered at $cl"; ltext="delivered"
  elif [ -z "$appr_at" ]; then
    set -- "No forecast until the plan is approved at Step 3." \
           "The forecast will be the plan's chain at the line's measured pace, never a typed number."
    btext="no forecast until the plan is approved at Step 3"; ltext="no forecast until approved"
  elif [ -z "$cids" ]; then
    set -- "No task is open, so nothing is left to forecast."
    btext="nothing left to forecast; no task is open"; ltext="closes — no task open"
  elif [ -z "$ratio" ]; then
    set -- "No forecast: no pace is measured on this run or a delivered one."
    btext="no forecast; no pace is measured on this run or a delivered one"; ltext="closes unverified"
  else
    IFS='	' read -r per larger closes <<< "$(awk -v now="$now" -v c="$cmins" -v t="$work" -v w="$width" -v r="$ratio" 'BEGIN {
      p = t / w; l = (p > c) ? p : c; s = now + l * r * 60
      printf "%d\t%d\t%d\n", p + 0.5, l + 0.5, int(s / 60 + 0.5) * 60 }')"
    cl="$(sitrep_clock "$closes" "$now")"
    if [ "$admitted" -eq 0 ]; then wtxt="over 1 suite run, none admitted now"
    elif [ "$admitted" -eq 1 ]; then wtxt="over the 1 suite run the gate admits"
    else wtxt="over the $admitted suite runs the gate admits"; fi
    cmin_txt="$(awk -v c="$cmins" -v t="$work" -v w="$width" -v r="$ratio" 'BEGIN { p = t / w; l = (p > c) ? p : c; printf "%.4f\n", l * r }')"
    set -- "About $cl." \
           "The work left is $work min as planned, $per min $wtxt; the longest chain left, $(printf '%s' "$cids" | sed 's/,/ → /g'), is $cmins min; the larger, $larger min, at the pace below is $(sitrep_dur "$cmin_txt")." \
           "The pace: $pace_txt." \
           "It assumes what you owe is answered now."
    btext="about $cl"; ltext="closes ~$cl"
  fi

  # ---- What is owed, in words: what to do, then what waits on it
  local blk="" whats="" nown=0 k sent ttl rep what det wids
  while IFS='	' read -r k sent ttl rep; do
    [ -n "$k" ] || continue
    rep="${rep#poker: }"; [ -n "$rep" ] || rep="$ttl"
    det="$rep"
    case "$k" in
      approve:step[0-9]*) what="approve the Step ${k#approve:step} card" ;;
      approve:*) what="approve ${k#approve:}" ;;
      waive:*) what="waive or read ${k#waive:}" ;;
      *) what="$(printf '%s' "$ttl" | awk '{ print tolower(substr($0, 1, 1)) substr($0, 2) }')" ;;
    esac
    case "$k" in
      approve:*)
        wids="$(printf '%s\n' "$rows" | awk -F'\t' -v want="approval:${k#approve:}" '
          { s = tolower($10); gsub(/[ \t]/, "", s); if (s == "landed" || s == "dropped") next
            n = split($13, a, ","); for (i = 1; i <= n; i++) { x = a[i]; gsub(/^[ \t]+|[ \t]+$/, "", x); sub(/^live:/, "", x); if (x == want) { print $1; next } } }')"
        if [ -n "$wids" ]; then
          # shellcheck disable=SC2086
          det="$(sitrep_list 5 $wids) $([ "$(printf '%s\n' "$wids" | grep -c .)" -gt 1 ] && echo wait || echo waits) on it"
        fi ;;
    esac
    nown=$((nown + 1))
    blk="${blk}2	- $what: $det"$'\n'
    whats="${whats}${what}"$'\n'
  done <<SITREP_OWED
$owed
SITREP_OWED

  if [ "$line" = yes ]; then
    printf '%s%s%s · owed: %s · %s\n' "$s_mark" "$c_mark" "$w_mark" "$nown" "$ltext"
    return 0
  fi

  # ---- The Bottom line: owe, next, done, close
  local b_owe b_next b_done parts sp tp
  if [ "$nown" -eq 0 ]; then b_owe="You owe nothing now."
  else b_owe="You owe $nown: $(printf '%s' "$whats" | awk 'NF { n++; w[n] = $0 } END { for (i = 1; i <= n; i++) s = s ((i == 1) ? "" : ((i == n) ? " and " : ", ")) w[i]; print s }')."; fi
  parts=""
  # shellcheck disable=SC2086
  [ -z "$inflight" ] || parts="$(sitrep_list 5 $inflight) in flight"
  # shellcheck disable=SC2086
  [ -z "$blocked" ] || parts="${parts:+$parts; }$(sitrep_list 5 $blocked) blocked"
  # shellcheck disable=SC2086
  if [ -n "$nextup" ]; then
    if [ -n "$parts" ]; then parts="$parts; then $(sitrep_list 3 $nextup)"; else parts="$(sitrep_list 3 $nextup)"; fi
  fi
  if [ -n "$parts" ]; then b_next="Next: $parts."
  elif [ -n "$dlv_at" ]; then b_next="Next: nothing; the run is delivered."
  else
    b_next="Next: step ${cur:-0}, $(printf '%s' "${cur:-0}" | awk '{ split("Configure Scope Design Plan Implement Verify Review Document Integrate Close-out", nm, " "); print nm[$1 + 1] }')."
  fi
  if [ -n "$dlv_at" ]; then sp="steps 0 to 9"
  elif [ "${cur:-0}" -ge 2 ]; then sp="steps 0 to $((cur - 1))"
  elif [ "${cur:-0}" -eq 1 ]; then sp="step 0"
  else sp=""; fi
  if [ "$total" -eq 0 ]; then tp=""
  elif [ "$landed" -eq 0 ]; then tp="no task yet"
  elif [ -n "$last_id" ]; then tp="$landed of $total tasks, the last $last_id at $(sitrep_clock "$last_at" "$now")"
  else tp="$landed of $total tasks"; fi
  b_done="${sp}${sp:+${tp:+; }}${tp}"; b_done="Done: ${b_done:-nothing yet}."

  # ---- the page, each line with its continuation indent, folded at 92 columns
  local proj title_rel steps_done gh grade_at grade_g grade_why gline
  proj="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  case "$proj" in */.git) proj="${proj%/.git}"; proj="${proj##*/}" ;; *) proj="${root##*/}" ;; esac
  title_rel="$(plan_frontmatter_get "$plan" release 2>/dev/null)"
  steps_done="${cur:-0}"; [ -z "$dlv_at" ] || steps_done=9; [ "$steps_done" -le 9 ] || steps_done=9
  gline=""
  if [ -f "$recdir/sitrep.log" ] && [ ! -L "$recdir/sitrep.log" ]; then
    gline="$(awk 'index($0, "sitrep-grade/v1|at=") == 1 { l = $0 } END { print l }' "$recdir/sitrep.log")"
  fi
  if [ -n "$gline" ]; then
    grade_at="${gline#*|at=}"; grade_at="${grade_at%%|*}"
    grade_g="${gline#*|grade=}"; grade_g="${grade_g%%|*}"
    grade_why="${gline#*|why=}"
    gh="Score: $grade_g (graded $(sitrep_clock "$(iso_epoch "$grade_at")" "$now"))"
  else
    gh="Score: not graded yet"
  fi
  {
    printf '0\tSitrep · %s%s · %s · step %s of 9%s\n' "$proj" "${title_rel:+ $title_rel}" "$(sitrep_date "$now" '%A %-I:%M %p')" \
      "${cur:--}" "$([ "$total" -gt 0 ] && printf ' · %d of %d tasks done' "$landed" "$total")"
    printf '0\t\n0\tBottom line\n'
    printf '2\t- %s\n' "$b_owe" "$b_next" "$b_done" "Close: $btext."
    printf '0\t\n0\tTask list\n'
    while IFS='	' read -r ty gl lab desc kind note; do
      [ -n "$ty" ] || continue
      case "$gl" in L) glyph="✅" ;; A) glyph="🔄" ;; X) glyph="⛔" ;; *) glyph="⬜" ;; esac
      case "$kind" in
        t)  printf '5\t%s %s: %s (%s)\n' "$glyph" "$lab" "$desc" "$(sitrep_clock "$note" "$now")" ;;
        th) printf '5\t%s %s: %s (%s, by hand)\n' "$glyph" "$lab" "$desc" "$(sitrep_clock "$note" "$now")" ;;
        s)  printf '5\t%s %s: %s — %s\n' "$glyph" "$lab" "$desc" "$note" ;;
        *)  printf '5\t%s %s: %s\n' "$glyph" "$lab" "$desc" ;;
      esac
    done <<SITREP_SIT
$sit
SITREP_SIT
    printf '0\t\n0\t%s\n' "$gh"
    printf '3\t%s\n' "$s_text" "$c_text" "$w_text" "$SITREP_MARK_NONE decisions — rounds not counted yet" "$SITREP_MARK_NONE goals — not measured yet"
    [ -z "$gline" ] || printf '2\t- %s\n' "$grade_why"
    printf '0\t\n0\tBlocked on you\n'
    if [ -n "$blk" ]; then printf '%s' "$blk"; else printf '2\t- Nothing: no decision or action is owed by you.\n'; fi
    printf '0\t\n0\tCompletion\n2\t- %s of 9 steps.\n' "$steps_done"
    if [ "$total" -gt 0 ]; then printf '2\t- %d of %d tasks done (%d%%).\n' "$landed" "$total" $(( (landed * 200 + total) / (total * 2) ))
    else printf '2\t- No tasks defined yet; the plan is not written.\n'; fi
    printf '0\t\n0\tPredicted close\n'
    for k in "$@"; do printf '2\t- %s\n' "$k"; done
  } | sitrep_fold
  return 0
}

# sitrep_tick_line <plan> -> `poker: sitrep <the --line output>`, the tick's one-line form (wave-38 T11; D13, AC-2.8):
# the same `sitrep_render` the `--line` arm calls, at the plan's own root, so the two are byte-equal by construction.
# Silent when there is no plan to report on or the proof record cannot load; the tick is unaffected either way.
sitrep_tick_line() {
  local plan="${1:-}" root l
  { [ -n "$plan" ] && [ -f "$plan" ] && [ ! -L "$plan" ]; } || return 0
  declare -F proof_plan_slug >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; } >/dev/null 2>&1
  declare -F proof_plan_slug >/dev/null 2>&1 || return 0
  root="$(cd "$(project_root "${plan%/*}")" 2>/dev/null && pwd -P)"
  [ -n "$root" ] || return 0
  l="$(sitrep_render "$plan" "$root" yes 2>/dev/null)"
  [ -z "$l" ] || say "sitrep $l"
}

# sitrep_grade <plan> <root> <letter> <rationale> -> records one `sitrep-grade/v1|at=<ISO-UTC>|grade=<letter>|why=<text>`
# line in the run's sitrep.log, which the next page prints under its Score; rc 1, nothing written, when the letter
# is not one of A to F, or the rationale is empty, holds a `|` or a line break, or names no indicator line
# (schedule, correctness, waste, decisions or goals, as a word in any case).
sitrep_grade() {
  local plan="$1" root="$2" g="$3" why="$4" at dir log lc re='(^|[^a-z])(schedule|correctness|waste|decisions?|goals?)([^a-z]|$)'
  case "$g" in
    [A-F]) : ;;
    *) die "REFUSED — the grade '$(clean "$g")' is not one of A to F; nothing is recorded."; return 1 ;;
  esac
  case "$why" in
    *'|'*|*$'\n'*|*$'\r'*) die "REFUSED — the rationale '$(clean "$why")' holds a | or a line break, which the record cannot carry; nothing is recorded."; return 1 ;;
  esac
  [ -n "${why//[[:space:]]/}" ] || { die "REFUSED — an empty rationale; nothing is recorded."; return 1; }
  lc="$(printf '%s' "$why" | tr '[:upper:]' '[:lower:]')"
  if ! [[ "$lc" =~ $re ]]; then
    die "REFUSED — the rationale '$(clean "$why")' names no indicator line (schedule, correctness, waste, decisions or goals); nothing is recorded."
    return 1
  fi
  at="$(sitrep_now)"
  at="$(date -u -r "$at" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$at" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  [ -n "$at" ] || { die "REFUSED — no clock to stamp the grade with; nothing is recorded."; return 1; }
  dir="$(docs_root "$root")/record/$(proof_plan_slug "$plan")"; log="$dir/sitrep.log"
  { mkdir -p "$dir" && [ ! -L "$log" ] && printf 'sitrep-grade/v1|at=%s|grade=%s|why=%s\n' "$at" "$g" "$why" >> "$log"; } 2>/dev/null \
    || { die "REFUSED — the record $log cannot be written; nothing is recorded."; return 1; }
  say "sitrep grade $g — recorded at $(sitrep_clock "$(iso_epoch "$at")" "$(sitrep_now)") in $log; the next sitrep prints it"
  return 0
}

  # THE FILL'S MEASURE (wave-20 REQ-5, AC-5.6; Δ2; ADR-036 decision 4). The stop library appends
  # one `fill-ledger/v1` line per Stop of an engaged run; this folds them into the run's
  # missed-opportunity minutes (a free slot, a ready row, nothing launched — target zero), with
  # HOLD and declines listed separately with their idle cost. The path and the fold are
  # lib/patrol.sh's (`fill_ledger_path`, `fill_ledger_report`), the ones the recorder writes by.
  #
  # THE PLAN: the operand — absolute, project-root-relative or docs-root-relative, `bind`'s
  # three spellings — or, without one, the session's own run as `resolve_run` names it. OPEN is
  # `run_open`'s answer: an open run's last line owns the interval to now, a closed one's owns
  # nothing. READ-ONLY and outside the engagement gate, like `window`.
  poker_verb_fill_report() {
    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    FR_PLAN=""
    if [ -n "$FILL_REPORT_ARG" ]; then
      case "$FILL_REPORT_ARG" in
        /*) FR_PLAN="$FILL_REPORT_ARG" ;;
        *)  FR_PLAN="$REPO_REAL/$FILL_REPORT_ARG"
            [ -f "$FR_PLAN" ] || FR_PLAN="$(docs_root "$REPO_REAL")/$FILL_REPORT_ARG" ;;
      esac
      if [ ! -f "$FR_PLAN" ] || [ -L "$FR_PLAN" ]; then
        die "REFUSED — no plan file at $FILL_REPORT_ARG; name the plan whose fill ledger to read."
        exit 2
      fi
    else
      SESSION_ID="$(session_id)" || SESSION_ID=""
      if [ -z "$SESSION_ID" ]; then
        die "REFUSED — no session key, and no plan named; a report without an operand is for THIS session's run."
        exit 3
      fi
      resolve_run "$REPO_REAL" "$SESSION_ID"
      FR_PLAN="$POKER_RUN_PLAN"
      if [ -z "$FR_PLAN" ] || [ ! -f "$FR_PLAN" ]; then
        die "REFUSED — this session has no run to report on; name the plan: fill-report <plan>."
        exit 2
      fi
    fi
    FR_SLUG="$(proof_plan_slug "$FR_PLAN")"
    FR_OPEN=no
    run_open "$FR_PLAN" && FR_OPEN=yes
    FR_FILE="$(fill_ledger_path "$REPO_REAL" "$FR_PLAN")"
    if [ ! -f "$FR_FILE" ] || [ -L "$FR_FILE" ]; then
      say "fill-report — no fill ledger yet for ${FR_SLUG}: ${FR_FILE} (the stop hook writes it from the first Stop past Step 3)"
    fi
    FR_OUT="$(fill_ledger_report "$FR_FILE" "$FR_SLUG" "$FR_OPEN" "${BIONIC_NOW_EPOCH:-}")"
    printf '%s\n' "$FR_OUT"
    # IDLE MINUTES AND PEAK WIDTH (wave-26 T16, D17). Both are read from times code wrote with the
    # clock and never from the plan's text: the ledger's `at=` and `idle=`, the roster's
    # `launched_at=` and the sweeper ledger's ack stamps, through the roster lib's own close rule.
    FR_NOW="${BIONIC_NOW_EPOCH:-}"
    case "$FR_NOW" in ''|*[!0-9]*) FR_NOW="$(date -u +%s)" ;; esac
    FR_LED_IN=/dev/null
    [ -f "$FR_FILE" ] && [ ! -L "$FR_FILE" ] && FR_LED_IN="$FR_FILE"
    # Idle: the lines are folded by turn (the last of a turn wins, as the report above folds them),
    # ordered by `at`, and a line whose idle= is non-empty owns the interval to the next line; the
    # last one owns the interval to now only while the run is open. An interval counts once, however
    # many rows idled in it.
    FR_IDLE_S="$(awk -v open="$FR_OPEN" -v now="$FR_NOW" "$_PATROL_ISO_AWK"'
      function fr_field(line, key,   i, n, parts) {
        n = split(line, parts, "|")
        for (i = 2; i <= n; i++) if (index(parts[i], key "=") == 1) return substr(parts[i], length(key) + 2)
        return ""
      }
      index($0, "fill-ledger/v1|") == 1 {
        e = iso2epoch(fr_field($0, "at"))
        if (e < 0) next
        k = fr_field($0, "turn")
        if (k != "" && (k in slot)) { i = slot[k] } else { i = ++n; if (k != "") slot[k] = i }
        ep[i] = e; id[i] = fr_field($0, "idle")
      }
      END {
        for (i = 1; i <= n; i++) ord[i] = i
        for (i = 2; i <= n; i++) {
          v = ord[i]; j = i - 1
          while (j >= 1 && ep[ord[j]] > ep[v]) { ord[j + 1] = ord[j]; j-- }
          ord[j + 1] = v
        }
        idle = 0
        for (x = 1; x <= n; x++) {
          i = ord[x]
          if (id[i] == "") continue
          if (x < n) end = ep[ord[x + 1]]
          else end = (open == "yes" ? now : ep[i])
          if (end > ep[i]) idle += end - ep[i]
        }
        printf "%d\n", idle
      }' "$FR_LED_IN")"
    case "$FR_IDLE_S" in ''|*[!0-9]*) FR_IDLE_S=0 ;; esac
    # Width: every session the ledger names (and this one) has a roster; each live row is open from
    # its occupancy stamp to the ack that closes its name (`_roster_acks`, `_roster_discharged`:
    # an ack strictly later than the launch), or to now. A row's `intended`, `confirmed` and
    # `identified` lines share a name and a stamp, so (name, stamp) is one interval.
    FR_SIDS="$(awk -F'|' '
      index($0, "fill-ledger/v1|") == 1 {
        for (i = 2; i <= NF; i++) if (index($i, "session=") == 1) print substr($i, 9)
      }' "$FR_LED_IN" | sort -u)"
    FR_SID_NOW="$(session_id 2>/dev/null)" || FR_SID_NOW=""
    FR_SIDS="$(printf '%s\n%s\n' "$FR_SIDS" "$FR_SID_NOW" | sort -u)"
    FR_SPANS=""
    for FR_S in $FR_SIDS; do
      case "$FR_S" in ''|*[!A-Za-z0-9_-]*) continue ;; esac
      FR_RF="$REPO_REAL/.bionic/tmp/roster-${FR_S}.state"
      FR_AF="$REPO_REAL/.bionic/tmp/sweeper-${FR_S}.state"
      { [ -f "$FR_RF" ] && [ ! -L "$FR_RF" ] && [ -r "$FR_RF" ]; } || continue
      { [ -f "$FR_AF" ] && [ ! -L "$FR_AF" ] && [ -r "$FR_AF" ]; } || FR_AF=""
      FR_SPANS="${FR_SPANS}$(FR_RF="$FR_RF" FR_AF="$FR_AF" awk -v now="$FR_NOW" \
        -v rpfx="roster-state/${ROSTER_VERSION:-$ROSTER_SCHEMA_VERSION}|" "$_PATROL_ISO_AWK$_ROSTER_OPEN_AWK"'
        BEGIN {
          _roster_acks(ENVIRON["FR_AF"], ACK)
          f = ENVIRON["FR_RF"]
          while ((getline line < f) > 0) {
            if (index(line, rpfx) != 1) continue
            if (!_roster_live(_roster_kv(line, "status"))) continue
            nm = _roster_kv(line, "name"); if (nm == "") nm = "(unnamed)"
            st = _roster_occupied_at(line); if (!_roster_stamp_ok(st)) continue
            key = nm SUBSEP st; if (key in seen) continue
            seen[key] = 1
            b = iso2epoch(st); en = now
            if ((nm in ACK) && _roster_discharged(st, ACK[nm])) en = iso2epoch(ACK[nm])
            if (en < b) en = b
            printf "%d %d\n", b, en
          }
          close(f)
        }' </dev/null)
"
    done
    FR_PEAK="$(printf '%s' "$FR_SPANS" | awk '
      NF == 2 { n++; s[n] = $1; e[n] = $2 }
      END {
        peak = 0
        for (i = 1; i <= n; i++) {
          c = 0
          for (j = 1; j <= n; j++) if (s[j] <= s[i] && (s[i] < e[j] || j == i)) c++
          if (c > peak) peak = c
        }
        printf "%d\n", peak
      }')"
    case "$FR_PEAK" in ''|*[!0-9]*) FR_PEAK=0 ;; esac
    printf 'idle minutes: %d\n' "$(( (FR_IDLE_S + 30) / 60 ))"
    printf 'peak width: %d\n' "$FR_PEAK"
    FR_HEAD="$(printf '%s\n' "$FR_OUT" | head -n 1)"
    FR_M="${FR_HEAD#*|missed=}"; FR_M="${FR_M%%|*}"
    FR_H="${FR_HEAD#*|hold=}"; FR_H="${FR_H%%|*}"
    FR_D="${FR_HEAD#*|declined=}"; FR_D="${FR_D%%|*}"
    say "fill-report ${FR_SLUG}: missed opportunity ${FR_M} min (a free slot, a ready row, nothing launched) · HOLD ${FR_H} min · declined ${FR_D} min$( [ "$FR_OPEN" = yes ] && printf ' · run open, last interval to now')"
    exit 0
  }

  # THE HANDOFF FILE (wave-38 T12; D23, D4, D13; AC-3.1, AC-3.2, AC-3.5; was wave-30 T15's in-place section). A run's
  # portable state lives in a record file and the plan carries a pointer. The verb writes record/<wave>/handoff.md
  # (or <path>, under the docs root) whole, and never by hand, one line per fact in this order:
  #   bionic-handoff/v1                          the kind line
  #   sitrep head: Bottom line                   the sitrep page's own Bottom line and its four bullets, or
  #   - <item>                                   `sitrep head: (none recorded)`; then `sitrep line: <sitrep --line>`.
  #   sitrep line: <…>                           Both come from sitrep_render, never a second reader (D13).
  #   written: <date -u>                         the instant adopt and launch-sync judge a later dispatch against
  #   plan: <path>  branch: <b> @ <sha>  integration: <b> @ <sha>  step: <current:>
  #   open rows (<n>):  last landed:  live writers (<n>): <verified | unverified — why>  last proof:  patrol:
  #   mid-flight: order: rulings: lessons: risks:  each a flag's text, else carried from the previous file, else (to fill)
  #   safe to clear | wait N minutes — …         handoff_safe_line
  #   /bionic:canonical-sdlc <path>              the one door (D4), and nothing after it
  # The machine facts are the readers they always were: heads by git in the bound checkout, open rows and trees by
  # `units_rows`, the newest `landed` line and `proved:` line of ## SDLC State, the live writers the harness's newest
  # ListAgents answer names (the roster's open rows, marked unverified, when no fresh answer can say) with the run
  # state the tick prints. The plan's `## Handoff` becomes the heading and one line `handoff: <path> written <local
  # time>`, through the plan transaction every plan verb takes (copy, dry commit through the real gate, checksum,
  # swap), placed before `## Not Doing` when the plan has none. A closed plan (a `delivered:` Step-9 line) gets the
  # closed form instead, its `resume point:` line 2 and its `branch:` line printed by close-out.sh closed-form, the one
  # writer of both (PARKED on a parked run, NONE — DELIVERED otherwise), the human lines kept, the door last. REFUSED (1), nothing written: no `## Tasks`, no `## SDLC State`, a closed run that
  # records no delivery; (2): a path that is no .md under the docs root, lib/proof.sh or lib/line.sh unreadable.
  poker_verb_handoff() {
    plan_verb_open handoff closed-ok
    HO_CLOSED=no
    case "$(session_run "$PV_REPO" "$(session_id)")" in
      'bound-closed '*)
        if /usr/bin/grep -qE '^[[:space:]]*-?[[:space:]]*Step[[:space:]]+9[[:space:]]*:.*delivered:' "$PV_PLAN"; then
          HO_CLOSED=yes
        else
          die "REFUSED — handoff writes the plan this session is bound to, and it has no bound open run (bound-closed $PV_PLAN), nor a delivered one."
          exit 1
        fi ;;
    esac
    if ! /usr/bin/grep -qE '^##[[:space:]]+Tasks([[:space:]]|$)' "$PV_PLAN"; then
      die "REFUSED — the plan has no ## Tasks section, so there are no open rows to hand off; the plan is unchanged."
      exit 1
    fi
    if ! /usr/bin/grep -qE '^##[[:space:]]+SDLC State([[:space:]]|$)' "$PV_PLAN"; then
      die "REFUSED — the plan has no ## SDLC State section, so there is no landing or proof to hand off; the plan is unchanged."
      exit 1
    fi
    if ! { declare -F proof_awk >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_awk >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    if ! { declare -F _line_entries >/dev/null 2>&1 || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; } \
       || ! declare -F _line_entries >/dev/null 2>&1; then
      die "REFUSED — the landing record's reader (lib/line.sh) cannot be loaded from $BIONIC_LIB, so whether a landing is in flight cannot be said; the plan is unchanged."
      exit 2
    fi
    # WHERE THE FILE GOES: <path> absolute or project-root-relative, a .md under the docs root; else the default.
    HO_DOCS="$(docs_root "$PV_REPO")"
    HO_PTR_FILE="$(handoff_pointer_of "$PV_PLAN")"
    if [ -n "$HO_ARG_PATH" ]; then
      case "$HO_ARG_PATH" in /*) HO_FILE="$HO_ARG_PATH" ;; *) HO_FILE="$PV_REPO/${HO_ARG_PATH#./}" ;; esac
    else
      HO_FILE="$(handoff_default_of "$PV_PLAN" "$PV_REPO")"
    fi
    HO_OK=yes
    case "$HO_FILE" in *.md) : ;; *) HO_OK=no ;; esac
    case "$HO_FILE/" in */../*|*/./*|*//*) HO_OK=no ;; esac
    case "$HO_FILE" in "$HO_DOCS"/*) : ;; *) HO_OK=no ;; esac
    [ ! -L "$HO_FILE" ] && [ ! -d "$HO_FILE" ] || HO_OK=no
    if [ "$HO_OK" = no ]; then
      die "REFUSED — handoff writes its file under the docs root ($HO_DOCS), a .md path: '$(printf '%s' "${HO_ARG_PATH:0:120}" | tr -d '[:cntrl:]')' is not one; nothing was written."
      exit 2
    fi
    HO_REL="${HO_FILE#"$PV_REPO"/}"
    HO_SRC=""
    if [ -f "$HO_FILE" ]; then HO_SRC="$HO_FILE"; elif [ -n "$HO_PTR_FILE" ] && [ -f "$HO_PTR_FILE" ]; then HO_SRC="$HO_PTR_FILE"; fi
    HO_HUMAN=""
    for HO_K in $HANDOFF_HUMAN_KEYS; do
      case "$HO_K" in mid-flight) HO_V="$HO_F_MID" ;; order) HO_V="$HO_F_ORDER" ;; rulings) HO_V="$HO_F_RULINGS" ;; lessons) HO_V="$HO_F_LESSONS" ;; risks) HO_V="$HO_F_RISKS" ;; esac
      HO_HUMAN="${HO_HUMAN:+$HO_HUMAN
}$(handoff_human_line "$HO_K" "$HO_V" "$HO_SRC")"
    done
    HO_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    HO_WB="$(plan_working_branch "$PV_PLAN")"
    HO_IB="$(plan_integration_branch "$PV_PLAN")"
    HO_HEADS=""
    for HO_B in "$HO_WB" "$HO_IB"; do
      HO_H=""
      [ -z "$HO_B" ] || HO_H="$(git -C "$PV_REPO" rev-parse --verify -q "refs/heads/$HO_B^{commit}" 2>/dev/null)" || HO_H=""
      HO_HEADS="${HO_HEADS:+$HO_HEADS · }$([ -n "$HO_B" ] && printf '%s' "$(clean "$HO_B")" || printf '(none named)') @ ${HO_H:-(no such branch)}"
    done
    HO_ROWS="$(units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' '
      { st = $10; wt = $11; ag = $5
        if (ag == "") ag = "—"
        has = (wt != "" && wt != "—" && wt != "-")
        if (st == "active" || (st == "pending" && has)) print $1 " · " ag " · " (has ? wt : "—") " · " st }')"
    HO_N_ROWS=0; [ -z "$HO_ROWS" ] || HO_N_ROWS="$(printf '%s\n' "$HO_ROWS" | wc -l | tr -d ' ')"
    HO_TREES="$(units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' '$5 != "" && $5 != "—" && $5 != "-" && $11 != "" && $11 != "—" && $11 != "-" { print $5 "\t" $11 }')"
    HO_LANDED="$(awk '
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc && /^- T[0-9]+:/ && match($0, /landed [0-9a-f]+ [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z/) {
        split(substr($0, RSTART, RLENGTH), f, " "); id = $2; sub(/:$/, "", id)
        if (length(f[2]) >= 7 && (best == "" || f[3] >= bat)) { best = id " " f[2] " " f[3]; bat = f[3] } }
      END { print best }' "$PV_PLAN")"
    HO_PROOF="$(awk "$(proof_awk)"'
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc && proof_fields($0) {
        at = ""; if (match($0, /[ \t]at=[^ \t]+/)) at = substr($0, RSTART + 4, RLENGTH - 4)
        last = "kind=" PROOF_KIND " head=" PROOF_HEAD (at != "" ? " at=" at : "") }
      END { print last }' "$PV_PLAN")"
    HO_RF="$PV_REPO/.bionic/tmp/roster-$(session_id).state"
    # THE LIVE AGENTS ARE THE HARNESS'S, NOT THE ROSTER'S (wave-34 T6; REQ-14 AC-14.2, D23). The roster
    # records that a dispatch happened, never that an agent is alive, and reading its open rows listed two
    # researchers as live after TaskStop (field report 2026-10-11, item 2). So the list is the newest
    # ListAgents answer in this session's transcript (lib/agents.sh, the one parser of it): every agent it
    # names that is not `idle` — the one word the harness uses for "finished its turn", the rule
    # `live_row_open` keeps — less every agent a TaskStop after the answer ended. An answer a later
    # dispatch outdates, a stale one, or none at all cannot say who is live: the roster's open rows are
    # listed in its place and the live-writers line says unverified (D23: it no longer decides the safe line).
    HO_TR="$(session_transcript "$(session_id)")" || HO_TR=""
    HO_LRC=4; HO_SET=""; HO_SINCE=""
    if [ -n "$HO_TR" ]; then
      _la_ensure "$HO_TR" 2>/dev/null; HO_LRC=$?
      HO_SET="$_LA_CACHE_OUT"
      [ "$HO_LRC" -ne 0 ] || HO_SINCE="$(live_agents_since_answer "$HO_TR" 2>/dev/null)"
    fi
    HO_WHY=""
    case "$HO_LRC" in
      0) HO_DISP="$(printf '%s\n' "$HO_SINCE" | awk -F'\t' '$1 == "dispatched" { print $2; exit }')"
         [ -z "$HO_DISP" ] || HO_WHY="a dispatch at $HO_DISP postdates the newest ListAgents answer" ;;
      3) HO_WHY="the newest ListAgents answer predates the last prompt" ;;
      *) HO_WHY="no ListAgents answer in this session's transcript" ;;
    esac
    if [ -z "$HO_WHY" ]; then
      HO_NAMES="$(printf '%s\n' "$HO_SET" | HO_GONE="$(printf '%s\n' "$HO_SINCE" | awk -F'\t' '$1 == "stopped" { print $2 }')" \
        awk -F'|' -v idle="$_LA_ROW_CLOSED_STATUS" '
          BEGIN { n = split(ENVIRON["HO_GONE"], g, "\n"); for (i = 1; i <= n; i++) if (g[i] != "") gone[g[i]] = 1 }
          $1 != "" && $3 != idle && !($1 in gone) && !($1 in seen) { seen[$1] = 1; print $1 }')"
    else
      HO_NAMES="$(roster_open_names "$HO_RF" "$PV_REPO/.bionic/tmp/sweeper-$(session_id).state" "$(session_id)")"
    fi
    HO_AGENTS=""; HO_N_AG=0
    while IFS= read -r HO_NAME; do
      [ -n "$HO_NAME" ] || continue
      HO_ST="no run"
      if run_load_row "$(run_row_of "$HO_RF" "$HO_NAME")" "$HO_RF"; then run_read; HO_ST="$(run_state_words)"; fi
      HO_TREE="$(printf '%s\n' "$HO_TREES" | awk -F'\t' -v n="$HO_NAME" '$1 == n { print $2; exit }')"
      HO_AGENTS="${HO_AGENTS:+$HO_AGENTS
}  - $(clean "$HO_NAME") · $(clean "${HO_TREE:-—}") · $HO_ST"
      HO_N_AG=$((HO_N_AG + 1))
    done <<< "$HO_NAMES"
    HO_PLAN_REL="${PV_PLAN#"$PV_REPO"/}"
    HO_PATROL="not armed"
    HO_STAMP="$(patrol_stamp_file "$(session_id)")" || HO_STAMP=""
    if [ -n "$HO_STAMP" ] && [ -f "$HO_STAMP" ] && [ ! -L "$HO_STAMP" ]; then
      HO_PATROL="armed — stamp $(( ( $(now_epoch) - $(file_mtime "$HO_STAMP") ) / 60 ))m old"
    fi
    HO_SAFE="$(handoff_safe_line "$PV_PLAN" "$PV_REPO")"
    mkdir -p "${HO_FILE%/*}" 2>/dev/null
    HO_TMP="$PV_NEW.2"
    if [ "$HO_CLOSED" = yes ]; then
      # THE CLOSED FORM'S TWO STATE LINES ARE CLOSE-OUT'S (wave-38 T37; D23): close-out.sh decides parked, delivered and
      # a pull request owed, and its read-only `closed-form` prints the `resume point:` and `branch:` lines it writes.
      HO_CO="$(cd "$BIONIC_LIB" 2>/dev/null && pwd -P)/../close-out.sh"
      HO_STATE="$(bash "$HO_CO" "$PV_PLAN" closed-form 2>/dev/null)" || HO_STATE=""
      case "$HO_STATE" in
        'resume point: '*$'\n''branch: '*) : ;;
        *) die "REFUSED — the closed form's two lines are close-out.sh's to say, and its closed-form did not print them ($HO_CO); nothing was written."
           exit 2 ;;
      esac
      HO_RESUME="${HO_STATE%%$'\n'*}"
      case "$HO_RESUME" in 'resume point: PARKED on '*) HO_KIND=parked ;; *) HO_KIND=delivered ;; esac
      {
        printf 'bionic-handoff/v1\n'
        printf '%s\n' "$HO_RESUME"
        printf 'written: %s\n' "$HO_NOW"
        printf 'plan: %s\n' "$HO_PLAN_REL"
        printf '%s\n' "${HO_STATE#*$'\n'}"
        printf 'patrol: %s\n' "$HO_PATROL"
        printf 'continuation: record/%s/continuation.md\n' "$(proof_plan_slug "$PV_PLAN")"
        printf '%s\n' "$HO_HUMAN"
        printf '%s\n' "$HO_SAFE"
        printf '/bionic:canonical-sdlc %s\n' "$HO_REL"
      } > "$HO_TMP" 2>/dev/null || { die "REFUSED — the handoff file cannot be written at $HO_FILE; the plan is unchanged."; exit 2; }
    else
      # THE SITREP HEAD: the verb's page, its Bottom line block cut out whole, and its one-line form (D13).
      HO_BL="$(sitrep_render "$PV_PLAN" "$PV_REPO" no 2>/dev/null | awk 'index($0, "Bottom line") == 1 { f = 1; print; next } f && /^(- |  )/ { print; next } f { exit }')"
      case "$HO_BL" in
        'Bottom line'*) HO_HEAD="sitrep head: $HO_BL" ;;
        *) HO_HEAD="sitrep head: (none recorded)" ;;
      esac
      HO_SLINE="$(sitrep_render "$PV_PLAN" "$PV_REPO" yes 2>/dev/null | head -1)"
      if [ -z "$HO_WHY" ]; then HO_VER="verified by the newest ListAgents answer"
      else HO_VER="unverified — $HO_WHY; the roster's open rows"; fi
      {
        printf 'bionic-handoff/v1\n'
        printf '%s\n' "$HO_HEAD"
        printf 'sitrep line: %s\n' "${HO_SLINE:-unverified}"
        printf 'written: %s\n' "$HO_NOW"
        printf 'plan: %s\n' "$HO_PLAN_REL"
        printf 'branch: %s\n' "$(printf '%s' "$HO_HEADS" | awk -F' · ' '{ print $1 }')"
        printf 'integration: %s\n' "$(printf '%s' "$HO_HEADS" | awk -F' · ' '{ print $2 }')"
        printf 'step: %s\n' "${PV_CUR:--}"
        printf 'open rows (%s):\n' "$HO_N_ROWS"
        [ -z "$HO_ROWS" ] || printf '%s\n' "$HO_ROWS" | sed 's/^/  - /'
        printf 'last landed: %s\n' "${HO_LANDED:-none yet}"
        printf 'live writers (%s): %s\n' "$HO_N_AG" "$HO_VER"
        [ -z "$HO_AGENTS" ] || printf '%s\n' "$HO_AGENTS"
        printf 'last proof: %s\n' "${HO_PROOF:-none yet}"
        printf 'patrol: %s\n' "$HO_PATROL"
        printf '%s\n' "$HO_HUMAN"
        printf '%s\n' "$HO_SAFE"
        printf '/bionic:canonical-sdlc %s\n' "$HO_REL"
      } > "$HO_TMP" 2>/dev/null || { die "REFUSED — the handoff file cannot be written at $HO_FILE; the plan is unchanged."; exit 2; }
    fi
    # THE POINTER: the section's whole body is one line, rewritten in place or created before ## Not Doing.
    HO_PTR="handoff: $HO_REL written $(handoff_local_time "$HO_NOW")"
    PV_RC=0
    HO_PTR="$HO_PTR" awk "$_HANDOFF_SEC_AWK"'
      function emit() { print ""; print ENVIRON["HO_PTR"]; print "" }
      FNR == NR {
        if ($0 ~ /^[ \t]*```/) { f1 = !f1; next }
        if (f1) next
        if ($0 ~ /^##[ \t]+Handoff[ \t]*$/) have = 1
        if ($0 ~ /^##[ \t]+Not Doing/) nd = 1
        next
      }
      {
        ho_track($0)
        if (_hs && $0 ~ /^##[ \t]+Handoff[ \t]*$/) { if (!wrote) { print; emit(); wrote = 1 }; next }
        if (_hs) next
        if (!have && !wrote && !_hf && ((nd && $0 ~ /^##[ \t]+Not Doing/) || (!nd && $0 ~ /^##[ \t]+SDLC State/))) {
          print "## Handoff"; emit(); wrote = 1
        }
        print
      }' "$PV_PLAN" "$PV_PLAN" > "$PV_NEW" 2>/dev/null || PV_RC=$?
    if [ "$PV_RC" -ne 0 ]; then
      die "REFUSED — the handoff cannot be written (awk exit $PV_RC); the plan is unchanged."
      exit 2
    fi
    HO_ABS="$(cd "${HO_FILE%/*}" 2>/dev/null && pwd -P)/${HO_FILE##*/}"
    if [ "$HO_CLOSED" = yes ]; then
      HO_SAY="handoff — the closed form written to $HO_ABS at $HO_NOW (the plan is $HO_KIND); the plan's ## Handoff points to it, dry-committed first."
      HO_DRY=as-is
    else
      HO_SAY="handoff — written to $HO_ABS at $HO_NOW ($HO_N_ROWS open rows, $HO_N_AG live writers; ${HO_SAFE%% — *}); the plan's ## Handoff points to it, dry-committed first."
      HO_DRY=writer
    fi
    # The plan first, then the file: a refused plan leaves no file pointing nowhere. A pointer the plan already
    # carries (the same path, the same minute) needs no transaction, and the file is still rewritten.
    cmp -s "$PV_NEW" "$PV_PLAN" || plan_verb_swap handoff "the handoff pointed at $HO_REL" "$HO_DRY"
    if ! mv -f "$HO_TMP" "$HO_FILE" 2>/dev/null; then
      die "REFUSED — the handoff file cannot be moved into place at $HO_FILE."
      exit 2
    fi
    say "$HO_SAY"
    exit 0
  }

  poker_verb_landing_report() {
    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    LR_PLAN=""
    if [ -n "$LR_ARG" ]; then
      case "$LR_ARG" in
        /*) LR_PLAN="$LR_ARG" ;;
        *)  LR_PLAN="$REPO_REAL/$LR_ARG"
            [ -f "$LR_PLAN" ] || LR_PLAN="$(docs_root "$REPO_REAL")/$LR_ARG" ;;
      esac
      if [ ! -f "$LR_PLAN" ] || [ -L "$LR_PLAN" ]; then
        die "REFUSED — no plan file at $LR_ARG; name the plan whose landings to report."
        exit 2
      fi
    else
      SESSION_ID="$(session_id)" || SESSION_ID=""
      if [ -z "$SESSION_ID" ]; then
        die "REFUSED — no session key, and no plan named; a report without an operand is for THIS session's run."
        exit 3
      fi
      resolve_run "$REPO_REAL" "$SESSION_ID"
      LR_PLAN="$POKER_RUN_PLAN"
      if [ -z "$LR_PLAN" ] || [ ! -f "$LR_PLAN" ]; then
        die "REFUSED — this session has no run to report on; bind its plan first."
        exit 2
      fi
    fi
    LR_ROOT="$(cd "$(project_root "${LR_PLAN%/*}")" 2>/dev/null && pwd -P)"
    [ -n "$LR_ROOT" ] || LR_ROOT="$REPO_REAL"
    # THE SCORECARD (wave-38 T15; D26): its reasoning is beside `scorecard_report`. It renders the sitrep's indicators,
    # which read the proof record, loaded as the sitrep verb loads it.
    if [ "$LR_SC" = yes ]; then
      if ! { declare -F proof_plan_slug >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
         || ! declare -F proof_plan_slug >/dev/null 2>&1; then
        die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB."
        exit 2
      fi
      scorecard_report "$LR_PLAN" "$LR_ROOT"
      exit 0
    fi
    if [ "$LR_HH" = no ]; then
      landing_report "$(_wt_proofs_path "$LR_ROOT" "$LR_PLAN")" "$LR_ROOT" "$LR_ROWS"
      exit 0
    fi
    # THE HAND-HOLDS LINE sits under the landings line, above the rows (D17).
    LR_TEXT="$(landing_report "$(_wt_proofs_path "$LR_ROOT" "$LR_PLAN")" "$LR_ROOT" "$LR_ROWS")"
    printf '%s\n' "${LR_TEXT%%$'\n'*}"
    hand_holds_report "$(_wt_proofs_path "$LR_ROOT" "$LR_PLAN")" "$LR_ROOT" "$LR_PLAN"
    case "$LR_TEXT" in *$'\n'*) printf '%s\n' "${LR_TEXT#*$'\n'}" ;; esac
    exit 0
  }
  # THE REGISTER (wave-38 T13; D24, AC-3.4). Read-only. `decisions` is the bound run's ledger through `decisions_list`;
  # `--all` is every run's under the docs root, keyed by wave, with the ADRs (`decisions_all`). Exit 1 in one line
  # naming the path when the run's ledger is absent; 2 when there is no run to read.
  poker_verb_decisions() {
    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    DC_DOCS="$(docs_root "$REPO_REAL")"
    if [ "$DC_ALL" = yes ]; then
      decisions_all "$DC_DOCS"
      exit 0
    fi
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key; decisions without --all reads THIS session's run."
      exit 3
    fi
    resolve_run "$REPO_REAL" "$SESSION_ID"
    DC_PLAN="$POKER_RUN_PLAN"
    if [ -z "$DC_PLAN" ] || [ ! -f "$DC_PLAN" ]; then
      die "REFUSED — this session has no run to read; bind its plan first, or read every run's: decisions --all."
      exit 2
    fi
    if ! { declare -F proof_plan_slug >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_plan_slug >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB."
      exit 2
    fi
    DC_LEDGER="$DC_DOCS/record/$(proof_plan_slug "$DC_PLAN")/design-ledger.md"
    if [ ! -f "$DC_LEDGER" ] || [ -L "$DC_LEDGER" ]; then
      say "no design ledger at ${DC_LEDGER#"$REPO_REAL"/} — this run has recorded no ruling"
      exit 1
    fi
    decisions_list "$DC_LEDGER"
    exit 0
  }

  # THE ONE DOOR (wave-38 T13; D4, D24, D13; AC-3.3). /bionic:canonical-sdlc <handoff.md> runs this first and does
  # what it prints. A /clear leaves a new session the skill's invocation has engaged and nothing else: no binding,
  # no stamp, no roster, no task list, no memory of the run. This does every step of the resume ritual a script
  # can do, in the ritual's order, each through its one implementation — `bind`, `arm`, `adopt`, `interval`,
  # `prompt` and `tick` are this script's own verbs, run as this session — and prints the two only the model can
  # do: the task list to create (the harness task list is unreadable by script, design ledger line 11) and the
  # CronCreate. In between, the recap: the run's settled rulings (the register's parser), the decisions still open
  # in any session the plan recorded (each one's owed ledger), what only the user can give (those of the person's
  # four kinds, and every approval a waiting row reads), the file's branch and plan lines, the checkout, and the
  # step file. A file whose line 2 is the closed form resumes nothing and says so; a safe line launch-sync marked
  # STALE is said before the binding (adopt then lists what runs now). The arm comes before the CronCreate here, as
  # at engagement (hooks/engage.sh arms at the marker's write): the stamp says the session asked for its Patrol.
  # Refusals name the fix and change nothing: no file or no kind line (2), a session the skill did not engage or a
  # plan that is not there (1); a sub-verb's refusal stops the ritual with that verb's code.
  poker_verb_resume() {
    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    RS_DOCS="$(docs_root "$REPO_REAL")"
    case "$RS_ARG" in
      /*) RS_FILE="$RS_ARG" ;;
      *)  RS_FILE="$REPO_REAL/${RS_ARG#./}"
          [ -f "$RS_FILE" ] || { [ -f "$RS_DOCS/$RS_ARG" ] && RS_FILE="$RS_DOCS/$RS_ARG"; } ;;
    esac
    RS_SHOWN="$(printf '%s' "${RS_ARG:0:160}" | tr -d '[:cntrl:]')"
    if [ ! -f "$RS_FILE" ] || [ -L "$RS_FILE" ]; then
      die "REFUSED — no handoff file at '$RS_SHOWN'; write one with: bash ${HOOK_DIR}/session-poker.sh handoff, and resume from the path its last line names. Nothing was bound or armed."
      exit 2
    fi
    if [ "$(sed -n 1p "$RS_FILE" 2>/dev/null)" != "bionic-handoff/v1" ]; then
      die "REFUSED — '$RS_SHOWN' is not a handoff file: its first line is not bionic-handoff/v1. Write one with: bash ${HOOK_DIR}/session-poker.sh handoff. Nothing was bound or armed."
      exit 2
    fi
    RS_L2="$(sed -n 2p "$RS_FILE")"
    case "$RS_L2" in
      'resume point: NONE — DELIVERED'*)
        say "resume — '$RS_SHOWN' is the closed form: the run is delivered, so there is nothing to resume; nothing was bound, armed or adopted."
        printf '%s\n' "$RS_L2"
        awk 'index($0, "plan: ") == 1 || index($0, "branch: ") == 1 || index($0, "continuation: ") == 1 { print }' "$RS_FILE"
        exit 0 ;;
      # A PARKED RUN IS CLOSED, AND ITS WORK IS LEFT (wave-38 T37; T15's note to T13). close-out performed its tail
      # without the merge and disarmed its Patrol, so nothing is bound or armed; the recap says where the work waits.
      'resume point: PARKED on '*)
        say "resume — '$RS_SHOWN' is the closed form, and the run is parked: its work is kept on its branch, not merged; the plan's Wake Note says what it waits on. Nothing was bound, armed or adopted."
        printf '%s\n' "$RS_L2"
        awk 'index($0, "plan: ") == 1 || index($0, "branch: ") == 1 || index($0, "continuation: ") == 1 { print }' "$RS_FILE"
        exit 0 ;;
    esac
    RS_PLAN_REL="$(awk 'index($0, "plan: ") == 1 { print substr($0, 7); exit }' "$RS_FILE")"
    if [ -z "$RS_PLAN_REL" ]; then
      die "REFUSED — '$RS_SHOWN' names no plan (it has no plan: line); rewrite it with: bash ${HOOK_DIR}/session-poker.sh handoff. Nothing was bound or armed."
      exit 2
    fi
    case "$RS_PLAN_REL" in /*) RS_PLAN="$RS_PLAN_REL" ;; *) RS_PLAN="$REPO_REAL/$RS_PLAN_REL" ;; esac
    if [ ! -f "$RS_PLAN" ] || [ -L "$RS_PLAN" ]; then
      die "REFUSED — the plan '$RS_SHOWN' names is missing: $RS_PLAN. Check out the branch that holds it, or bind the run by hand (bash ${HOOK_DIR}/session-poker.sh bind <plan>). Nothing was bound or armed."
      exit 1
    fi
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty); a resume binds and arms ONE session."
      exit 3
    fi
    if ! engaged_session "$REPO_REAL" "$SESSION_ID"; then
      die "REFUSED — this session has not invoked /bionic:canonical-sdlc; resume through the door, /bionic:canonical-sdlc $RS_SHOWN, which engages the session and runs this verb. Nothing was bound or armed."
      exit 1
    fi
    if ! { declare -F proof_plan_slug >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_plan_slug >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; nothing was bound or armed."
      exit 2
    fi
    rs_sub() { ( cd "$REPO_REAL" && CLAUDE_CODE_SESSION_ID="$SESSION_ID" "${BASH:-bash}" "$HOOK_DIR/session-poker.sh" "$@" ); }
    rs_step() {  # <codes it may exit with, comma-joined> <verb> [args] -> runs it; any other code stops the ritual with it
      local ok="$1" rc=0; shift
      rs_sub "$@" || rc=$?
      case ",$ok," in *",$rc,"*) return 0 ;; esac
      die "resume stopped at $1 (exit $rc): the lines above say why; the steps after it did not run."
      exit "$rc"
    }
    say "resume — $RS_SHOWN ($(awk 'index($0, "written: ") == 1 { print substr($0, 10); exit }' "$RS_FILE")): bind, arm and adopt, then the task list, the recap, the step file, the patrol and the tick"
    RS_SAFE="$(tail -2 "$RS_FILE" | head -1)"
    case "$RS_SAFE" in
      'STALE — '*) printf 'stale: %s\n' "$RS_SAFE" ;;
    esac
    rs_step 0 bind "$RS_PLAN"
    rs_step 0 arm
    rs_step 0,1 adopt    # 1 is adopt's "open rows found", its NOTIFY, never a refusal
    # The task list: every step with its status from current:, then every row of ## Tasks with its table status.
    RS_CUR="$(_fill_current_field "$RS_PLAN")"; RS_CURN="${RS_CUR%%[!0-9]*}"
    awk -v cur="$RS_CURN" 'BEGIN {
      n = split("Configure Scope Design Plan Implement Verify Review Document Integrate Close-out", nm, " ")
      for (i = 0; i < n; i++)
        printf "task-list: %d: %s · %s\n", i, nm[i + 1], (cur == "" || i > cur + 0) ? "pending" : ((i < cur + 0) ? "completed" : "in_progress") }'
    units_rows "$RS_PLAN" 2>/dev/null | awk -F'\t' "$_ROW_SHORT_AWK"'
      function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
      NF >= 10 { st = tolower(trim($10)); if (st == "dropped") next
                 printf "task-list: %s/%s: %s · %s\n", trim($2), trim($1), row_short($4), (st == "landed") ? "completed" : ((st == "active") ? "in_progress" : "pending") }'
    # The recap.
    RS_LEDGER="$RS_DOCS/record/$(proof_plan_slug "$RS_PLAN")/design-ledger.md"
    RS_SET=""
    [ ! -f "$RS_LEDGER" ] || [ -L "$RS_LEDGER" ] || RS_SET="$(decisions_list "$RS_LEDGER")"
    if [ -n "$RS_SET" ]; then printf '%s\n' "$RS_SET" | sed 's/^/settled: /'
    else printf 'settled: none — no ruling in %s\n' "${RS_LEDGER#"$REPO_REAL"/}"; fi
    RS_OWED="$( { bind_sessions "$RS_PLAN" 2>/dev/null; printf '%s\n' "$SESSION_ID"; } | awk 'NF && !s[$0]++' \
      | while IFS= read -r RS_S; do OWED_ROOT="$REPO_REAL" OWED_SID="$RS_S" owed_list 2>/dev/null; done | awk -F'\t' 'NF && !k[$1]++')"
    RS_OPEN="$(printf '%s\n' "$RS_OWED" | awk -F'\t' 'NF && $1 != "" { r = $4; sub(/^poker: /, "", r); if (r == "") r = $3; print "open: " $1 " — " r }')"
    if [ -n "$RS_OPEN" ]; then printf '%s\n' "$RS_OPEN"; else printf 'open: none — no decision is open\n'; fi
    RS_OWN="$(printf '%s\n' "$RS_OPEN" | awk '{ k = $2 } k ~ /^(approve|waive|finding|gate):/ { sub(/^open: /, "owned-by-user: "); print }')"
    RS_APPR="$(units_waiting "$RS_PLAN" "$(fill_step_token "$RS_PLAN" 2>/dev/null)" 2>/dev/null | awk -F'\t' -v have="$(printf '%s\n' "$RS_OWED" | cut -f1 | tr '\n' ' ')" '
      { r = $2; sub(/^live:/, "", r); if (r !~ /^approval:[A-Za-z0-9][A-Za-z0-9._-]*$/) next
        nmv = substr(r, 10); if (index(" " have, " approve:" nmv " ")) next
        if (!(nmv in ids)) { ord[++n] = nmv; ids[nmv] = $1 } else if (index(", " ids[nmv] ", ", ", " $1 ", ") == 0) ids[nmv] = ids[nmv] ", " $1 }
      END { for (i = 1; i <= n; i++) print "owned-by-user: approval:" ord[i] " — " ids[ord[i]] " wait on it; record it: approve " ord[i] " '"'"'<the user'"'"'s words>'"'"'" }')"
    RS_OWN="$(printf '%s\n%s\n' "$RS_OWN" "$RS_APPR" | awk 'NF')"
    if [ -n "$RS_OWN" ]; then printf '%s\n' "$RS_OWN"; else printf 'owned-by-user: none — nothing waits on you\n'; fi
    # The user's standing orders (wave-38 T18; REQ-7 AC-7.1, D17): every item of config.yaml's standing-orders:,
    # in config order, through its one reader (lib/roots.sh `config_section`); none printed when there are none.
    while IFS= read -r RS_ORDER; do
      [ -z "$RS_ORDER" ] || printf 'standing-order: %s\n' "$RS_ORDER"
    done <<< "$(config_section "$REPO_REAL" standing-orders 2>/dev/null)"
    RS_BR="$(awk 'index($0, "branch: ") == 1 { print; exit }' "$RS_FILE")"
    printf '%s\n' "${RS_BR:-branch: (the file names none)}"
    printf 'plan: %s\n' "$RS_PLAN_REL"
    RS_HEAD="$(git -C "$REPO_REAL" symbolic-ref --short -q HEAD 2>/dev/null)" || RS_HEAD=""
    printf 'tree: %s (checked out: %s)\n' "$REPO_REAL" "${RS_HEAD:-a detached HEAD}"
    RS_PROOT="$(cd "$HOOK_DIR/.." 2>/dev/null && pwd -P)"
    case "$RS_CURN" in
      [0-9]|[0-9][0-9]) printf 'step-file: %s/skills/canonical-sdlc/steps/%s.md\n' "$RS_PROOT" "$RS_CURN" ;;
      *) printf 'step-file: none — the plan'"'"'s current: (%s) names no step\n' "${RS_CUR:-unset}" ;;
    esac
    # The patrol: the model's one act left, in the ritual's order, the interval as the arm line prints it.
    RS_INT="$(rs_sub interval 2>/dev/null)" || RS_INT=""
    RS_EVERY="every ${RS_INT:-?}s"
    case "$RS_INT" in
      ''|*[!0-9]*) ;;
      *) if [ $((RS_INT % 60)) -eq 0 ]; then
           RS_M=$((RS_INT / 60))
           if [ "$RS_M" -ge 1 ] && [ "$RS_M" -le 30 ] && [ $((60 % RS_M)) -eq 0 ]; then RS_EVERY="$RS_EVERY (cron */$RS_M * * * *)"; fi
         fi ;;
    esac
    RS_PROMPT="$(rs_sub prompt 2>/dev/null)" || RS_PROMPT=""
    printf 'patrol-interval: %s — CronList, CronDelete every job whose prompt begins with bionic-patrol session=, then CronCreate recurring %s with the patrol: line'"'"'s text as its prompt (the stamp is armed)\n' "$RS_EVERY" "${RS_EVERY%% (*}"
    printf 'patrol: %s\n' "${RS_PROMPT:-(the prompt verb printed nothing: run bash ${HOOK_DIR}/session-poker.sh prompt)}"
    RS_RC=0
    rs_sub tick || RS_RC=$?
    case "$RS_RC" in
      0|1) : ;;
      *) die "resume stopped at tick (exit $RS_RC): the lines above say why."; exit "$RS_RC" ;;
    esac
    say "resume — done: bound, armed, adopted, ticked. Yours now: rebuild the task list from the task-list: lines (TaskList first), read the step-file:, and create the Patrol job from the patrol: line."
    exit 0
  }

  # THE SITUATION REPORT (wave-38 T10). Its reasoning is above the verbs, beside `sitrep_render`. The plan is
  # resolved as landing-report resolves its own: a named one first, else the session's bound run.
  poker_verb_sitrep() {
    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    SR_PLAN=""
    if [ -n "$SR_ARG" ]; then
      case "$SR_ARG" in
        /*) SR_PLAN="$SR_ARG" ;;
        *)  SR_PLAN="$REPO_REAL/$SR_ARG"
            [ -f "$SR_PLAN" ] || SR_PLAN="$(docs_root "$REPO_REAL")/$SR_ARG" ;;
      esac
      if [ ! -f "$SR_PLAN" ] || [ -L "$SR_PLAN" ]; then
        die "REFUSED — no plan file at $SR_ARG; name the plan whose situation to report."
        exit 2
      fi
    else
      SESSION_ID="$(session_id)" || SESSION_ID=""
      if [ -z "$SESSION_ID" ]; then
        die "REFUSED — no session key, and no plan named; a report without an operand is for THIS session's run."
        exit 3
      fi
      resolve_run "$REPO_REAL" "$SESSION_ID"
      SR_PLAN="$POKER_RUN_PLAN"
      if [ -z "$SR_PLAN" ] || [ ! -f "$SR_PLAN" ]; then
        die "REFUSED — this session has no run to report on; bind its plan first, or name it: sitrep <plan>."
        exit 2
      fi
    fi
    if ! { declare -F proof_plan_slug >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_plan_slug >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB."
      exit 2
    fi
    SR_ROOT="$(cd "$(project_root "${SR_PLAN%/*}")" 2>/dev/null && pwd -P)"
    [ -n "$SR_ROOT" ] || SR_ROOT="$REPO_REAL"
    if [ "${SR_GRADE:-no}" = yes ]; then
      sitrep_grade "$SR_PLAN" "$SR_ROOT" "${SR_LETTER:-}" "${SR_WHY:-}"
      exit $?
    fi
    sitrep_render "$SR_PLAN" "$SR_ROOT" "$SR_LINE"
    exit 0
  }
