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

# THE LANDINGS IN FLIGHT. A landing whose `ready` has no later published or returned, and whose carrier (the
# `<pid>:<start>` the ready subshell records) is alive by lib/slots.sh's rule, as lib/line.sh's fold reads it: one
# State line each, the row, the tree it lands from, when it went ready and the carrier's pid. The source session is
# disposable, so the line is a fact the next session acts on; nothing here estimates when the landing ends.
handoff_landing_lines() {  # <plan> <root> -> `  - <row> landing from <tree> · ready since <time> · pid <pid>`, one per landing
  local rec now row car tr at e
  rec="$(_wt_proofs_path "$2" "$1" 2>/dev/null)" || return 0
  [ -n "$rec" ] && [ -f "$rec" ] && [ ! -L "$rec" ] && declare -F _line_entries >/dev/null 2>&1 || return 0
  now="$(sitrep_now)"
  while IFS='|' read -r row car tr; do
    [ -n "$row" ] || continue
    at="$(awk -F'|' -v r="$row" "${_LINE_FIELDS_AWK:-}"'
      { e = line_ev() } e == "" || line_kv("row") != r { next }
      e == "published" || e == "returned" { a = ""; next }
      e == "ready" && a == "" { a = line_kv("at") }
      END { print a }' "$rec" 2>/dev/null)"
    e="$(iso_epoch "$at")"; [ -n "$e" ] || e="$now"
    case "$tr" in "$2"/*) tr="${tr#"$2"/}" ;; esac
    printf '  - %s landing from %s · ready since %s · pid %s\n' "$(clean "$row")" "$(clean "${tr:-—}")" \
      "$(sitrep_clock "$e" "$now")" "$(clean "${car%%:*}")"
  done <<EOF2
$(_line_entries "$rec" "" 2>/dev/null | awk -F'\t' '$1 != "" && $4 == "yes" { print $1 "|" $9 "|" $13 }')
EOF2
}
# THE TREE, COMPUTED: the branch checked out, the head with its subject, and every uncommitted path by name with what
# happened to it, from git's porcelain (lib/worktree.sh `_wt_piece_dirt`, untracked files included). A directory git
# does not track says so on each line, so no State line is ever left to be typed.
handoff_tree_lines() {  # <root> -> the branch:, head: and uncommitted lines
  local br h dirt
  if ! git -C "$1" rev-parse --git-dir >/dev/null 2>&1; then
    printf 'branch: none — not a git repository\nhead: none — not a git repository\n'
    printf 'uncommitted: unverified — not a git repository\n'
    return 0
  fi
  br="$(git -C "$1" symbolic-ref --short -q HEAD 2>/dev/null)" || br=""
  printf 'branch: %s\n' "${br:-none — a detached HEAD}"
  h="$(git -C "$1" log -1 --format='%H %s' 2>/dev/null)" || h=""
  printf 'head: %s\n' "${h:-none — no commit yet}"
  dirt="$(_wt_piece_dirt "$1")"
  if [ -z "$dirt" ]; then printf 'uncommitted: none\n'; return 0; fi
  printf 'uncommitted (%s):\n' "$(printf '%s\n' "$dirt" | grep -c .)"
  printf '%s\n' "$dirt" | awk 'NF {
    xy = substr($0, 1, 2); p = substr($0, 4); w = "modified"
    if (xy == "??") w = "untracked"
    else if (xy ~ /U/ || xy == "AA" || xy == "DD") w = "in conflict"
    else if (xy ~ /R/) w = "renamed"
    else if (xy ~ /D/) w = "deleted"
    else if (xy ~ /A/) w = "added"
    print "  - " p " · " w }'
}
# THE RUNS IN FLIGHT: every log of the project's runs folder with a pid and no exit code whose pid is still that log's
# detached shim (`run_live`, the rule adopt and the tick read), with its pid and its log, project-root-relative.
handoff_running_lines() {  # <root> -> `  - <run id> · pid <pid> · log <path>`, one per live run
  local log pid id
  for log in "$1"/.bionic/tmp/runs/*.log; do
    [ -f "$log" ] && [ ! -L "$log" ] && [ ! -e "$log.rc" ] || continue
    pid=""; { read -r pid < "$log.pid"; } 2>/dev/null
    run_live "$pid" "$log" || continue
    id="${log##*/}"; id="${id%.log}"
    printf '  - %s · pid %s · log %s\n' "$(clean "$id")" "$pid" "$(clean "${log#"$1"/}")"
  done
}
# THE COMPOSED SECTIONS, RENDERED. `handoff_items <composed> <section>` is that section's items as lib/handoff.sh
# `handoff_compose` read them; `handoff_render <composed> <section>` prints the section's lines as card.sh's fold takes
# them (`<continuation indent> TAB <text>`). Summary is its four labelled lines in their order, a missing one
# `(not given)`; Next is numbered; a Finding that names no source (a path, a file with its line, a URL or a commit) and
# does not say `unverified` is marked `unverified` on its line; any other section is its items as bullets. An empty
# section is one line, `- none.`, so no heading stands over nothing.
handoff_items() {  # <composed> <section>
  printf '%s\n' "$1" | awk -F'\t' -v s="$2" '$1 == s { sub(/^[^\t]*\t/, ""); print }'
}
handoff_render() {  # <composed> <section>
  handoff_items "$1" "$2" | awk -v sec="$2" '
    function sourced(s,   n, w, i, t) {
      if (s ~ /unverified/ || index(s, "(a copied block of ") == 1) return 1
      n = split(s, w, /[ \t]+/)
      for (i = 1; i <= n; i++) {
        t = w[i]; gsub(/^[("'"'"'`<\[]+/, "", t); gsub(/[)"'"'"'`>\],.;:]+$/, "", t)
        if (t ~ /^https?:\/\//) return 1
        if (t ~ /[A-Za-z0-9_.~-]\/[A-Za-z0-9_.-]/) return 1
        if (t ~ /^[A-Za-z0-9_.-]+\.(sh|md|log|json|jsonl|yaml|yml|txt|tsv|csv|py|js|ts|go|rs|toml|state)(:[0-9]+(-[0-9]+)?)?$/) return 1
        if (length(t) >= 7 && length(t) <= 40 && t ~ /^[0-9a-f]+$/ && t ~ /[0-9]/ && t ~ /[a-f]/) return 1
      }
      return 0
    }
    BEGIN { nk = split("Doing Learned Open First", K, " ") }
    sec == "Summary" {
      l = tolower($0)
      for (i = 1; i <= nk; i++) {
        k = tolower(K[i])
        if (index(l, k) == 1 && match(substr($0, length(k) + 1), /^[ \t]*:[ \t]*/) && !(i in V)) V[i] = substr($0, length(k) + RLENGTH + 1)
      }
      next
    }
    sec == "Next" { printf "3\t%d. %s\n", ++n, $0; next }
    sec == "Findings" && !sourced($0) { printf "2\t- %s — unverified\n", $0; n++; next }
    { printf "2\t- %s\n", $0; n++ }
    END {
      if (sec == "Summary") { for (i = 1; i <= nk; i++) printf "2\t- %s: %s\n", K[i], ((i in V) && V[i] != "") ? V[i] : "(not given)"; exit }
      if (n == 0) printf "2\t- none.\n" }'
}
# THE REGISTER (wave-38 T13; D24, AC-3.4; wave-39 T11, D15, AC-7.1). Every ruling is a `## Δn — D<n> [qualifier] <verb>
# ["<reply>"] (<who> <date>)[: <title>]` heading in record/<wave>/design-ledger.md, or a `- D<n> …` bullet of that shape
# under a Δ (the Step-1 rulings folded in). The verbs are ruled, re-ruled, amended, amended again, ratified, settled,
# final and withdrawn; the qualifier is one word between the number and the verb; the heading form `D<n> ruled: <title> (<who>
# <date>)` has no reply; a tail after the parenthesis that is not `: <title>` is the title. A `put (…)` proposal, a
# line of any other shape, a body line and a fenced example are not entries, so a ledger written before D24 reads as
# having none. ONE PARSER: `decisions` prints it and the resume recap's settled: lines are
# it, prefixed. With `times`, the entries are put and ruling alike, one tab-separated line each, `D<n> verb date
# clock ampm line title` (clock and ampm empty when the parenthesis names none): the one reader of the ledger's
# headings that the clock readers (`sitrep_ledger_times`, `pages_open`) read through, so no program of the sheet
# parses a heading beside this one. The who is the parenthesis's words before its first date; a ruling with no `: <title>` after the
# parenthesis is `(untitled)`. A go a person gave is ledgered as `D<n> settled by <what> (<who> <date> [<clock>]): "<reply>"`,
# the reply after the parenthesis: it is the entry `D<n> · settled "<reply>" · <who> <date> · <what>`, its clock the
# parenthesis's, so the decision reads ruled and the span from its put is kept. With `puts`, a put is an entry too, `D<n> · put · <who> <date> · <title>`: the line
# `decisions put` writes, read only by the rounds count, never by the register.
decisions_list() {  # <ledger> [puts] -> one line per entry: D<n> · "<reply>" · <who> <date> · <title>, in the ledger's order
  awk -v puts="${2:-}" '
    function lead_verb(s,   i, n, vs, c) {  # the verb s opens with, followed by a space or a colon; "" when none
      n = split("amended again|amended|re-ruled|ruled|ratified|settled|final|withdrawn" (puts != "" ? "|put" : ""), vs, "|")
      for (i = 1; i <= n; i++) {
        if (index(s, vs[i]) != 1) continue
        c = substr(s, length(vs[i]) + 1, 1)
        if (c == " " || c == ":") return vs[i]
      }
      return ""
    }
    function entry(s,   n, rest, verb, qual, reply, hasreply, q, i, depth, inq, ch, fin, c, paren, tail, title, who, date, field, after, clock, ap, w, by) {
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
        by = ""
        if (verb == "settled" && index(rest, " by ") == 1) {
          q = index(substr(rest, 5), " ("); if (q == 0) return
          by = substr(rest, 5, q - 1); rest = substr(rest, q + 4)
        }
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
        if (by != "") {
          if (!hasreply && match(title, /^"[^"]*"[ \t]*$/)) { reply = substr(title, 2, index(substr(title, 2), "\"") - 1); hasreply = 1 }
          title = by
        }
      }
      if (!match(paren, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) return
      date = substr(paren, RSTART, RLENGTH); who = substr(paren, 1, RSTART - 1); after = substr(paren, RSTART + RLENGTH)
      sub(/^[ \t]+/, "", who); sub(/[ \t,]+$/, "", who)
      if (who == "") return
      sub(/[ \t]+$/, "", title); if (title == "") title = "(untitled)"
      if (puts == "times") {
        clock = ""; ap = ""
        if (match(after, /^ [0-9][0-9]?:[0-9][0-9] [AP]M/)) { split(substr(after, 2, RLENGTH - 1), w, " "); clock = w[1]; ap = w[2] }
        print n "\t" verb "\t" date "\t" clock "\t" ap "\t" NR "\t" title
        return
      }
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
# ROUNDS. A put opens a round of its decision and the next ruling of the same number closes it; a second put before
# the ruling is a second round; a ruling with no put open is a round of its own, as every ruling of a ledger written
# before puts is. A decision is open while its last put has no ruling after it, withdrawn when its last ruling is.
decisions_rounds() {  # <ledger> -> `D<n><TAB><rounds><TAB><ruled|withdrawn|open>` per decision, in order of first entry
  decisions_list "$1" puts | awk -F' · ' '
    { d = $1; if (!(d in r)) { o[++n] = d; r[d] = 0 } }
    $2 == "put" { r[d]++; st[d] = "open"; next }
    { if (st[d] != "open") r[d]++; st[d] = ($2 ~ /^([A-Za-z][A-Za-z0-9_-]* )?withdrawn( |$)/) ? "withdrawn" : "ruled" }
    END { for (i = 1; i <= n; i++) printf "%s\t%d\t%s\n", o[i], r[o[i]], st[o[i]] }'
}

# THE OPEN DECISIONS, ONE READER FOR THE SHEET AND THE RECAP. Both carry every decision put to the user and not yet
# ruled, and both read them here, so the two cannot disagree on what is open.
# pages_open <plan> <ledger> -> `D<TAB>D<n><TAB><title><TAB><wait line><TAB><put clock>` per open decision, in order of
#   first entry: open is `decisions_rounds`' word, the title the newest put's, the wait line the first line under that
#   put's heading (what `decisions put` wrote there), empty when it has none, the clock the newest put's heading
#   names (`h:mm AM|PM`), empty when it names none. <plan> is not read; the callers name it beside its ledger.
pages_open() {
  local led="$2" open pm
  [ -f "$led" ] && [ ! -L "$led" ] || return 0
  open="$(decisions_rounds "$led" | awk -F'\t' '$3 == "open" { printf "%s ", $1 }')"
  [ -n "$open" ] || return 0
  pm="$(decisions_list "$led" times | awk -F'\t' '$2 == "put" { printf "%s:%s ", $6, $1 }')"
  { decisions_list "$led" times | awk -F'\t' '$2 == "put" { print "T\t" $1 "\t" $7; print "K\t" $1 "\t" ($4 == "" ? "" : $4 " " $5) }'
    # the wait line: the first line under a put's heading, whichever lines `decisions_list` named as the puts
    awk -v pm="$pm" 'BEGIN { n = split(pm, a, " "); for (i = 1; i <= n; i++) { split(a[i], b, ":"); at[b[1]] = b[2] } }
      { sub(/\r$/, "") }
      /^[ \t]*```/ { f = !f; next }
      f { next }
      index($0, "## ") == 1 { d = (NR in at) ? at[NR] : ""; if (d != "") print "W\t" d "\t"; next }
      d != "" && NF { print "W\t" d "\t" $0; d = "" }' "$led" 2>/dev/null
  } | awk -F'\t' -v open="$open" '
    $1 == "T" { t[$2] = $3; next }
    $1 == "K" { k[$2] = $3; next }
    $1 == "W" { w[$2] = $3 }
    END { n = split(open, a, " "); for (i = 1; i <= n; i++) printf "D\t%s\t%s\t%s\t%s\n", a[i], t[a[i]], w[a[i]], k[a[i]] }'
}

# pages_owed <pages_open output> -> stdin's owed items (owed_list's field order) with each open decision as the item the
# person owes, `decide:D<n><TAB>-<TAB>reply to D<n><TAB>D<n> · <title>: reply with the option number. <wait line>`. A
# store item on the same key, a row's approval of that decision (lib/owed.sh `owed_key`), is the same need: the
# decision's item takes its place, so one reply is owed once. The rest keep the store's order, each key once.
pages_owed() {
  PAGES_OPEN="$1" awk -F'\t' '
    BEGIN { n = split(ENVIRON["PAGES_OPEN"], L, "\n")
      for (i = 1; i <= n; i++) {
        if (split(L[i], f, "\t") < 2 || f[1] != "D") continue
        k = "decide:" f[2]; ord[++m] = k
        item[k] = k "\t-\treply to " f[2] "\t" f[2] " · " f[3] ": reply with the option number" ((f[4] != "") ? ". " f[4] : "")
      } }
    NF && $1 != "" { if ($1 in item) { if (!done[$1]++) print item[$1]; next } if (!seen[$1]++) print }
    END { for (i = 1; i <= m; i++) if (!done[ord[i]]++) print item[ord[i]] }'
}

# sitrep_chain <plan> <units_rows output> [<weights>] -> `<ids, comma-joined><TAB><minutes>`: the heaviest chain of open
# tasks, `units_chain`'s over `units_edges`, as wide as the plan has tasks. A task weighs its sized minutes, or the
# minutes its `W<TAB><id><TAB><minutes>` line in <weights> gives it. A verify task is upstream of every integrate task
# whether or not a read says so: the integrate task cannot close the run while a verify task is open, so the edge is
# added here, in the chain's input only, unless the two already wait on each other the other way round, which an edge
# the plan has not written must never turn into a cycle.
sitrep_chain() {
  { printf '%s\n' "$2" | awk -F'\t' '{ s = tolower($10); gsub(/[ \t]/, "", s); k = tolower($3); gsub(/[ \t]/, "", k) } s == "pending" || s == "active" {
      m = 0; if (match($7, /^[0-9]+/)) m = substr($7, RSTART, RLENGTH); printf "U\t%s\t%d\t%s\n", $1, m, k }'
    printf '%s\n' "${3:-}"
    units_edges "$1" 2>/dev/null | awk -F'\t' 'NF >= 2 { printf "E\t%s\t%s\n", $1, $2 }'
  } | awk -F'\t' '
      function reach(a, b,   st, n, x, m, t, i) {
        delete seen; n = 1; st[1] = a; seen[a] = 1
        while (n > 0) {
          x = st[n--]; if (x == b) return 1
          m = split(adj[x], t, " ")
          for (i = 1; i <= m; i++) if (!(t[i] in seen)) { seen[t[i]] = 1; st[++n] = t[i] }
        }
        return 0
      }
      $1 == "U" { n++; id[n] = $2; sz[$2] = $3; kd[$2] = $4; next }
      $1 == "W" { wt[$2] = $3; next }
      $1 == "E" { ne++; ef[ne] = $2; et[ne] = $3; adj[$2] = adj[$2] " " $3; has[$2 SUBSEP $3] = 1; next }
      END {
        for (i = 1; i <= n; i++) printf "N\t%s\t%d\n", id[i], (id[i] in wt) ? wt[id[i]] : sz[id[i]]
        for (i = 1; i <= ne; i++) printf "E\t%s\t%s\n", ef[i], et[i]
        for (i = 1; i <= n; i++) if (kd[id[i]] == "verify")
          for (j = 1; j <= n; j++) if (kd[id[j]] == "integrate") {
            v = id[i]; g = id[j]
            if (v == g || (v SUBSEP g) in has || reach(g, v)) continue
            printf "E\t%s\t%s\n", v, g; adj[v] = adj[v] " " g; has[v SUBSEP g] = 1
          }
      }' | units_chain "$(printf '%s\n' "$2" | grep -c . | awk '{ print ($1 > 0) ? $1 : 1 }')" 2>/dev/null \
    | awk -F'\t' '$1 == "chain" { print $2 "\t" $3; exit }'
}

# sitrep_close_weights <units_rows output> <now epoch> <ratio n/d> <held tokens> <launches> -> one `W<TAB><id><TAB><min>`
# per open task, then `A<TAB><min><TAB><id>` (the longest remaining time of any running task, 0 and no id with none) and
# `H<TAB><id>` per open task held on you. The weight of a task is its sized minutes scaled by its kind: a build task by
# the ratio, every other kind at face value, and a task held on you, one whose label an open ask names among
# <held tokens>, at face value whatever its kind. A running task weighs what it has left, its scaled size less the
# minutes since its first launch (none known, none elapsed), never under its cadence, the one its roster row holds, else
# 15 min. <launches> is `sitrep_launches`' output. Whole minutes, half up, as `units_chain` takes only whole minutes.
sitrep_close_weights() {
  { printf '%s\n' "$1" | awk -F'\t' 'NF >= 10 { s = tolower($10); gsub(/[ \t]/, "", s); k = tolower($3); gsub(/[ \t]/, "", k); z = 0
      if (match($7, /^[0-9]+/)) z = substr($7, RSTART, RLENGTH); t = $2; gsub(/^[ \t]+|[ \t]+$/, "", t); print "U\t" $1 "\t" t "\t" k "\t" z "\t" s }'
    printf '%s\n' "$4" | awk 'NF { print "L\t" $0 }'
    printf '%s\n' "$5" | awk -F'\t' 'NF >= 2 { print "N\t" $1 "\t" $2 "\t" $3 }'
  } | awk -F'\t' -v now="$2" -v ratio="$3" "$(_sitrep_label_awk)"'
      BEGIN { split(ratio, r, "/"); sc = (r[2] + 0 > 0) ? r[1] / r[2] : 1 }
      $1 == "U" { n++; id[n] = $2; stp[n] = $3; kd[n] = $4; sz[n] = $5 + 0; st[n] = $6; at[$2] = n; next }
      $1 == "L" { held[$2] = 1; next }
      $1 == "N" { la[$2] = $3 + 0; if ($4 != "") cad[$2] = $4 + 0; next }
      END {
        a = 0; aid = ""
        for (i = 1; i <= n; i++) {
          if (st[i] != "pending" && st[i] != "active") continue
          h = (label(id[i]) in held)
          w = sz[i] * ((kd[i] == "build" && !h) ? sc : 1)
          if (st[i] == "active") {
            el = ((id[i] in la) && la[id[i]] <= now) ? (now - la[id[i]]) / 60 : 0
            c = ((id[i] in cad) && cad[id[i]] > 0) ? cad[id[i]] / 60 : 15
            w -= el; if (w < c) w = c
          }
          w = int(w + 0.5)
          printf "W\t%s\t%d\n", id[i], w
          if (h) hl = hl id[i] "\n"
          if (st[i] == "active" && w > a) { a = w; aid = id[i] }
        }
        printf "A\t%d\t%s\n", a, aid
        n = split(hl, hh, "\n"); for (i = 1; i <= n; i++) if (hh[i] != "") printf "H\t%s\n", hh[i]
      }'
}

# THE WAIT LINE: what changes if a decision is answered in an hour rather than now, rendered from `decision_waiters`, the
# one reader of what waits on a decision, so the line and the fact sheet cannot disagree. A task on the longest open
# chain, the release or the merge moves the predicted close an hour; a task off the chain starts an hour later while the
# close holds. The line says nothing moves only when nothing waits.
decision_wait() {  # <plan> <D<n>> [<root>] -> one sentence
  local rows waits chain cids
  rows="$(units_rows "$1" 2>/dev/null)"
  waits="$(decision_waiters "$1" "$2" "${3:-}")"
  if [ -z "$rows" ] && [ -z "$waits" ]; then printf 'Answered now or in an hour, no task moves: the plan has no task yet.\n'; return 0; fi
  chain="$(sitrep_chain "$1" "$rows")"; cids="${chain%%$'\t'*}"
  printf '%s\n' "$waits" | awk -v c=",$cids," '
    function list(a, m,   i, s) { for (i = 1; i <= m; i++) s = s ((i == 1) ? "" : ((i == m) ? " and " : ", ")) a[i]; return s }
    $0 == "release" || $0 == "merge" { hd[++hn] = "the " $0; next }
    NF { if (index(c, "," $0 ",")) on[++a] = $0; else off[++b] = $0 }
    END {
      if (a) { printf "Answered in an hour rather than now, the predicted close moves an hour later: %s %s on the longest chain and %s on it", list(on, a), (a > 1) ? "are" : "is", (a > 1) ? "wait" : "waits"
               m = 0; for (i = 1; i <= hn; i++) also[++m] = hd[i]; for (i = 1; i <= b; i++) also[++m] = off[i]
               if (m) printf "; %s also %s on it", list(also, m), (m > 1) ? "wait" : "waits"; printf ".\n" }
      else if (hn) { printf "Answered in an hour rather than now, the predicted close moves an hour later: %s %s on it", list(hd, hn), (hn > 1) ? "wait" : "waits"
               if (b) printf "; %s also %s on it", list(off, b), (b > 1) ? "wait" : "waits"; printf ".\n" }
      else if (b) printf "Answered in an hour rather than now, %s %s an hour later and the predicted close holds: %s off the longest chain.\n", list(off, b), (b > 1) ? "start" : "starts", (b > 1) ? "they are" : "it is"
      else printf "Answered now or in an hour, nothing moves: no task waits on it.\n" }'
}

# WHAT WAITS ON A DECISION, the one reader the wait line and the fact sheet share. Three things wait on D<n>: every task
# not landed or dropped whose reads name it as an approval, `approval:D<n>`, whatever its state; the release, while the
# newest release approval page puts D<n> as one of its decisions; and the merge, while a held merge on the run's register
# names D<n> as a whole word (the third decision is not the thirtieth) in its reason or its line.
decision_waiters() {  # <plan> <D<n>> [<root>] -> one line per waiter: a task id, in the plan's order, then `release`, then `merge`
  local root dir page
  units_rows "$1" 2>/dev/null | awk -F'\t' -v k="approval:$2" '
    { s = tolower($10); gsub(/[ \t]/, "", s) } s == "landed" || s == "dropped" { next }
    { n = split($13, t, ","); for (i = 1; i <= n; i++) { x = t[i]; gsub(/^[ \t]+|[ \t]+$/, "", x); sub(/^live:/, "", x)
        if (x == k) { print $1; break } } }'
  root="${3:-}"; [ -n "$root" ] || root="$(project_root "${1%/*}" 2>/dev/null)"
  [ -n "$root" ] || return 0
  if declare -F docs_root >/dev/null 2>&1 && declare -F proof_plan_slug >/dev/null 2>&1; then
    dir="$(docs_root "$root")/record/$(proof_plan_slug "$1")"
    # The newest page by its time of writing, as the reply verb finds it.
    # shellcheck disable=SC2012  # page names are release-approval-<hex>[-<n>].md, or the old stem's, no blank or line break in any
    page="$(ls -t "$dir"/release-approval-*.md "$dir/$RR_OLD_VERB"-*.md 2>/dev/null | head -1)"
    if [ -n "$page" ] && [ ! -L "$page" ] && awk -v d="$2" -v old="$RR_OLD_VERB/v1|dec=" '
        index($0, "release-approval/v1|dec=") == 1 || index($0, old) == 1 { k = $0; sub(/^.*\|key=/, "", k); sub(/\|.*$/, "", k); sub(/^[^:]*:/, "", k)
          if (k == d) { y = 1; exit } }
        END { exit !y }' "$page" 2>/dev/null; then
      printf 'release\n'
    fi
  fi
  if declare -F owed_list_plan >/dev/null 2>&1 && owed_list_plan "$1" "$root" 2>/dev/null | awk -F'\t' -v d="$2" '
      function names(s,   r) { r = "(^|[^A-Za-z0-9])" d "([^0-9]|$)"; return s ~ r }
      $1 == "hold:merge" && (names($3) || names($4)) { y = 1 } END { exit !y }'; then
    printf 'merge\n'
  fi
  return 0
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
# then the sheet's pace, correctness and waste at close, `pace: …`, `correctness: …` and `waste: …`, each said from the
# sheet's measurements, read through `sitrep_gather` (computed there, once). Every number is read from the record,
# and one the record cannot compute is `unverified`, never a literal:
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
#   human-wait      the release approval records (release-approval-*.md beside the run's records, and the pages an
#                   older run wrote under the old stem or as final-card-*.md): each page's `at=` on its
#                   `release-approval/v1|plan=` (or the old tags')
#                   line to its `replied: at=`, summed and rounded. unverified with no record, or a record with no reply.
# READ-ONLY. The rosters live in .bionic/tmp, which close-out's act 3 wipes, so close-out reads this before the wipe.
# Set in hooks/session-poker.sh, before any part loads: SCORECARD_STOP_GAP.
scorecard_report() {  # <plan> <project root> -> the seven lines; rc 0
  local plan="$1" root="$2" recdir appr stops merge_at agent="unverified" widest wait
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
  wait="$(for f in "$recdir"/release-approval-*.md "$recdir/$RR_OLD_VERB"-*.md "$recdir"/final-card-*.md; do [ -f "$f" ] && [ ! -L "$f" ] && printf '%s\n' "$f"; done | awk -v OLD="$RR_OLD_VERB/v1|plan=" "$_PATROL_ISO_AWK"'
    { file = $0; a = ""; r = ""
      while ((getline l < file) > 0) {
        if (index(l, "release-approval/v1|plan=") == 1 || index(l, OLD) == 1 || index(l, "final-card/v1|plan=") == 1) { n = split(l, p, "|"); for (i = 2; i <= n; i++) if (index(p[i], "at=") == 1) a = substr(p[i], 4) }
        else if (index(l, "replied: at=") == 1) { r = substr(l, 13); sub(/ .*/, "", r) }
      }
      close(file); cards++; ea = iso2epoch(a); er = iso2epoch(r)
      if (ea < 0 || er < 0 || er < ea) bad = 1; else sum += er - ea }
    END { if (!cards || bad) print "unverified"; else printf "%d\n", int(sum / 60 + 0.5) }')"
  sitrep_gather "$plan" "$root" sheet 2>/dev/null
  printf 'human stops (autonomous half): %s · target 1\n' "${stops:-unverified}"
  printf 'agent minutes after the final reply: %s · target 0\n' "$agent"
  printf 'widest landing ready→landed: %s · target < %s\n' "${widest:-unverified}" "$(b="$(sitrep_bar)"; printf '%s' "${b:-unverified}")"
  printf "human-wait minutes: %s · no target (the user's)\n" "${wait:-unverified}"
  printf 'pace: %s\ncorrectness: %s\nwaste: %s\n' "${SG_PACE:-unverified}" "${SG_CORRECT:-unverified}" "${SG_WASTE:-unverified}"
  return 0
}

# ---------------------------------------------------------------- the situation report
#
# THE FACT SHEET. `sitrep [<plan>]` prints every fact the sitrep card and the model need, and nothing that judges:
# the model reads the sheet and writes the judgment, the card is drawn from both, and the user sees the card, never
# the sheet. A first line says so; then one fact per line, `<key>: <value>`, in this order:
#
#   run.release · run.name · run.wave · run.now · run.step · run.project · run.started · run.last-landing · run.goal
#   step: n=<0-9> name=<name> state=<done|running|pending> tasks=<k>          one line per step, 0 to 9
#   task: id=<Tn> step=<n> state=<done|running|held|failed|pending> desc=<short description> note=<few words or ->
#                      one line per task not dropped, in execution order
#   clock.now · clock.approved · clock.forecast · clock.elapsed · clock.elapsed-share
#   work.planned · work.added · work.dropped · work.landed · work.left · work.width · work.task-time
#   pace.time-used · pace.work-landed · close.chain · close.predicted · close.unscaled · close.waits-on-you
#   tests.suites-run · tests.suites-total · tests.whole-run · reviews · findings.open
#   waste.dropped · waste.runs-discarded · waste.ready-unstarted · waste.waiting-on-you
#   goal: name=<goal> status=<met|on course|not measured|not met|unreadable> measure=<what measures it — what it read, or -> for=<the theme's opening sentence>
#   ask: key=<kind:id> holds=<what waits on it, or nothing> title=<title> raised=<clock or -> blocks=<yes|no> waits=<user|event <what>>
#   review: question=<q> scope=<piece|whole> result=<pass|flag|fail|running> at=<clock or -> open-findings=<n> record=<path or ->
#
# `run.goal:` is the plan's `## Goal` first paragraph, one line, as the Step-1 card prints it; a plan with no Goal prints
# no such line. A goal line's `for=` stands last and is present only for a theme that opens on a sentence, a measured
# goal of the `goals:` line carrying none; the fields before it keep their names and their order.
# A list line's fields stand in that fixed order and a value runs to the next field's ` <name>=`, so a value may hold
# spaces. A measured line (clock. to waste.) is `<key>: <value> — <what it measures> · unit: <unit> · source: <source>`,
# the close's `basis:` in place of its source, so the model reads what each number measures before it compares two.
# `--line` prints the Patrol's status from the same facts, `<k> of <m> tasks · owed: <n> on you · <m> on events · close <time>`, and
# the tick prints it as `poker: sitrep <the status>`; the handoff's head and the resume recap read the same asks.
#
# EVERY FACT IS ANOTHER READER'S, CALLED: the tasks and sizes are `units_rows`', the longest open chain
# `units_chain`'s over `units_edges`, the landings, runs and the line `landing_report`'s and lib/line.sh's fold, the
# idle minutes `fill-report`'s own line, the asks the run's register's (`owed_list_plan`, never the caller's
# session), the launches the rosters', the findings `proof_findings` at `proof_finding_rating` less
# `proof_fixed`, the landings the landing record's `landed:` headers, a goal's status lib/plan.sh `plan_goal_status`'s, the
# one the release approval card reads too. What no reader computes is computed here, once: the work's counts, its
# width and own time, the minutes waiting on the user, a red not yet
# answered by a green, each suite by its last run, the whole run's newest verdict, a review by its latest result per
# question and scope, the close.
#
# THE TASKS, IN EXECUTION ORDER. Done by landing time, the time read from the task's `- T<n>:` line wherever it sits on
# it, `landed <sha> <ISO>` or `landed-by-hand: <who> <ISO> "<why>"` (said `by hand`), the earlier of the two when both
# appear; a done task whose line names no instant follows them, so said. In flight by place on the line, read as it
# stands (read-only: no git counting, no liveness), saying what each does: `in its landing, <n> of <m> suites green`,
# `queued behind <task>`, `next on the line`, or `building`. The rest in dependency order over `units_edges`, each
# saying everything it `waits on`, in the order its reads are read (`units_waiting`), joined `A, B and C`, never a
# count of the rest: `step N`, `your approval of D<n>`, `your approval of the <name>`, `the reviews`, `the last build
# row landing`, `the merge`, and any other read another task writes as that task, named by the label its card row
# prints, its step, a slash and its id without the T, as `queued behind <label>` names one. A task with a red at head
# is failed (`red`); one waiting on an approval the user owes, or whose status is held, is held, a started one naming
# each approval it waits on. The description is the task's title, lib/plan.sh `plan_task_title`'s, as the plan's card
# prints it.
#
# THE MEASUREMENTS. Sized minutes are the size cells, summed as if the tasks ran one after another, so they are never
# set against wall clock; the sheet compares only measurements of one unit and leaves every judgment to the model.
# Planned are the rows in the plan at the Step-3 approval: a row whose own `- T<n>:` line says task-add added it, or a
# split made it, after the approval was added. A task's own time runs from its first launch on the rosters to its
# `landed:` header. Pace is the share of the live work's sized minutes landed against the share of the forecast's
# hours used. The predicted close is now plus the longer of two spans: the longest remaining time of any running
# task, its size less the minutes since its first launch and never under its cadence (the one its roster row holds, else
# 15 min), and the longest open chain, a running task on it counted at that remaining time. Tasks are scaled by kind:
# a build task by the landed build tasks' own time over their size once 3 or more of them have both a launch and a
# landing, else at 1×; a verify, review, doc, integrate or close task at face value; a task held on an ask that names it
# unscaled whatever its kind, its ask named in close.waits-on-you. A verify task is upstream of the integrate task
# whether or not a read says so. close.unscaled is the same basis at 1×. The forecast end is the approval plus the plan's
# own `forecast:`, else plus its sized minutes. A plan not approved at Step 3 predicts nothing; a delivered one predicts
# its delivery; one with no task open, now. No typed number moves the predicted close, and admitting more work to the
# gate never shortens one chain.
#
# THE ASKS ARE THE RUN'S REGISTER. Every item open on it, of every kind, is an ask, and so is every decision put on the
# design ledger and not ruled (`pages_owed`, once per key); a goal decision whose goal now reads met, and a decision the
# ledger reads ruled or withdrawn, are closed in fact, whether or not their asks have been closed yet. What an ask holds
# is what waits on it: for an approval, the open tasks that read it; for a decision, `decision_waiters` (the tasks, the
# release and the merge); for a waiver, a finding, a matrix row or a held merge, the open integrate tasks; for a gate
# act, the task its line names; for a step card, the next step.
#
# A value the record cannot compute prints `-` or says so in words. Clock times are local and 12-hour on this
# machine's clock (`sitrep_clock`); a time on another local day than now's carries its date. Now is BIONIC_NOW_EPOCH
# when set, fill-report's seam.
SITREP_SHEET_HEAD="sheet/v1 — facts for the model; the user sees the card, never this sheet"
SITREP_STEP_NAMES="Configure Scope Design Plan Implement Verify Review Document Integrate Close-out"

# _sitrep_label_awk -> the awk source of `label(id)`: a task is named by the label its row prints on the card, its step,
# a slash and its id without the T. It reads `at[id]` (the row's index) and `stp[index]` (its step); an id no row carries
# is named as it stands. Every place that names a task to the user takes its name from here, so no two disagree.
_sitrep_label_awk() {
  printf '%s' '
    function label(w) {
      if (!(w in at)) return w
      return (stp[at[w]] == "" ? "-" : stp[at[w]]) "/" ((substr(w, 1, 1) == "T") ? substr(w, 2) : w)
    }'
}

# sitrep_task_label <units_rows output> <id> -> the label of that task, as the notes and the card's rows name it
sitrep_task_label() {
  printf '%s\n' "$1" | LC_ALL=C awk -F'\t' -v w="$2" "$(_sitrep_label_awk)"'
    { x = $1; gsub(/^[ \t]+|[ \t]+$/, "", x); if (x != "") { at[x] = NR; s = $2; gsub(/^[ \t]+|[ \t]+$/, "", s); stp[NR] = s } }
    END { print label(w) }'
}


# sitrep_dur <minutes> -> `<h> h <m> min`, `<h> h` or `<m> min`, to the whole minute
sitrep_dur() {
  awk -v m="$1" 'BEGIN { m = int(m + 0.5); h = int(m / 60); r = m - h * 60
    if (h == 0) printf "%d min\n", r; else if (r == 0) printf "%d h\n", h; else printf "%d h %d min\n", h, r }'
}

# sitrep_noun <n> <singular> <plural> -> the word that agrees with <n>: one task, two tasks
sitrep_noun() { if [ "$1" = 1 ]; then printf '%s' "$2"; else printf '%s' "$3"; fi; }

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

# sitrep_local_epoch <YYYY-MM-DD> <h:mm> <AM|PM> -> the epoch of that clock on this machine's zone, BSD date then GNU;
# nothing when neither reads it. The design ledger writes its puts and rulings on the local clock.
sitrep_local_epoch() {
  date -j -f '%Y-%m-%d %I:%M:%S %p' "$1 $2:00 $3" +%s 2>/dev/null || date -d "$1 $2 $3" +%s 2>/dev/null
}

# sitrep_added <plan> -> `<id><TAB><epoch>` per task whose own `- T<n>:` line under ## SDLC State says when it joined
# the plan, `added by <who> at <ISO>` (task-add) or `split from <id> at <ISO>`. A task whose line says neither was in
# the plan from its writing.
sitrep_added() {
  awk "$_PATROL_ISO_AWK"'
    function norm(s) { if (length(s) == 17 && substr(s, 17, 1) == "Z") return substr(s, 1, 16) ":00Z"; return s }
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^##[ \t]/ { s = ($0 ~ /^##[ \t]+SDLC State/); next }
    !s || !/^- T[0-9A-Za-z._-]*:/ { next }
    match($0, /(added by [^ ]+|split from [^ ]+) at [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9](:[0-9][0-9])?Z/) {
      id = $2; sub(/:$/, "", id); t = substr($0, RSTART, RLENGTH); sub(/.* at /, "", t)
      e = iso2epoch(norm(t)); if (e >= 0) print id "\t" e
    }' "$1" 2>/dev/null
}

# sitrep_launches <plan> <root> -> `<row><TAB><epoch><TAB><cadence seconds or empty>` per row of the plan the project's
# rosters launched, its first launch. The roster is the dispatch wall's record of every launch, the one record of when a
# task started and of the cadence its brief declared. A row relaunched (a second writer, a re-run) keeps its first
# launch, and that launch's cadence: its own time runs from when it was first sent.
sitrep_launches() {
  local key="" p r a c cs seen="" pk=""
  declare -F adopt_plan_key >/dev/null 2>&1 && key="$(adopt_plan_key "$1")"
  { [ -n "${_LINE_FIELDS_AWK:-}" ] || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; }
  while IFS='	' read -r p r a c; do
    [ -n "$r" ] || continue
    case "$seen" in *"|$p|"*) ;; *) seen="$seen|$p|"; pk="$p"; declare -F adopt_plan_key >/dev/null 2>&1 && pk="$(adopt_plan_key "$p")" ;; esac
    [ "$pk" = "${key:-$1}" ] || [ "$p" = "$1" ] || continue
    cs=""; [ -z "$c" ] || cs="$(parse_seconds "$c" 2>/dev/null)" || cs=""
    printf '%s\t%s\t%s\n' "$r" "$a" "$cs"
  done <<SITREP_LAUNCHES
$(for f in "$2"/.bionic/tmp/roster-*.state; do [ -f "$f" ] && [ ! -L "$f" ] && cat "$f"; done 2>/dev/null | awk -F'|' "$_PATROL_ISO_AWK$_LINE_FIELDS_AWK"'
    index($0, "roster-state/") != 1 { next }
    { p = line_kv("plan"); r = line_kv("row"); e = iso2epoch(line_kv("launched_at")); c = line_kv("cadence") }
    p == "" || p == "none" || r == "" || e < 0 { next }
    { k = p "\t" r; if (!(k in first) || e < first[k]) { first[k] = e; cad[k] = c } }
    END { for (k in first) print k "\t" first[k] "\t" cad[k] }' | LC_ALL=C sort)
SITREP_LAUNCHES
}

# sitrep_work <plan> <rec> <root> <units_rows output> <now> <approval epoch or empty> -> one tab-separated line, the
# work's measurements in sized minutes (a row's size cell) and its own minutes (launch to landing):
#   1-2 planned   rows in the plan at the approval: every row whose own line names no joining after it
#   3-4 added     rows that joined after the approval        5-6 dropped   rows dropped, whenever they joined
#   7-8 landed    rows landed                                9 live        the sized minutes of every row not dropped
#   10-11 left    rows neither landed nor dropped
#   12-14 task-time   landed rows with a launch and a `landed:` header: how many, their own minutes, their sized
#                     minutes; 15 the landed rows with no launch on record
#   16-17 width   tasks running at once over the minutes any task ran, launch to landing (or now, while active):
#                 the median, minute-weighted, and the peak; `-` with no launch on record
#   18-20 build-time   12-14 over the landed rows of kind build alone: how many, their own minutes, their sized minutes
# Every count and minute is rounded to the whole minute; a row with no number in its size cell is 0 minutes.
sitrep_work() {
  local plan="$1" rec="$2" root="$3" rows="$4" now="$5" appr="$6"
  { printf '%s\n' "$rows" | awk -F'\t' 'NF >= 10 { s = tolower($10); gsub(/[ \t]/, "", s); z = 0; if (match($7, /^[0-9]+/)) z = substr($7, RSTART, RLENGTH); k = tolower($3); gsub(/[ \t]/, "", k); print "U\t" $1 "\t" z "\t" s "\t" k }'
    sitrep_added "$plan" | awk -F'\t' '{ print "J\t" $1 "\t" $2 }'
    sitrep_launches "$plan" "$root" | awk -F'\t' '{ print "N\t" $1 "\t" $2 }'
    { [ -f "$rec" ] && [ ! -L "$rec" ] && awk '/^landed: row=/ && match($0, / at=[0-9T:Z-]+/) { r = $2; sub(/^row=/, "", r); print "L\t" r "\t" substr($0, RSTART + 4, RLENGTH - 4) }' "$rec"; } 2>/dev/null
  } | awk -F'\t' -v now="$now" -v appr="$appr" "$_PATROL_ISO_AWK"'
    function norm(s) { if (length(s) == 17 && substr(s, 17, 1) == "Z") return substr(s, 1, 16) ":00Z"; return s }
    $1 == "U" { n++; id[n] = $2; sz[n] = $3 + 0; st[n] = $4; kd[n] = $5; next }
    $1 == "J" { join[$2] = $3; next }
    $1 == "N" { launch[$2] = $3; next }
    $1 == "L" { e = iso2epoch(norm($3)); if (e >= 0 && (!($2 in land) || e > land[$2])) land[$2] = e; next }
    END {
      for (i = 1; i <= n; i++) {
        r = id[i]; m = sz[i]
        if (appr != "" && (r in join) && join[r] > appr) { an++; am += m } else { pn++; pm += m }
        if (st[i] == "dropped") { dn++; dm += m; continue }
        live += m
        if (st[i] == "landed") {
          ln++; lm += m
          if ((r in launch) && (r in land) && land[r] >= launch[r]) {
            tn++; to += (land[r] - launch[r]) / 60; ts += m
            if (kd[i] == "build") { bn++; bo += (land[r] - launch[r]) / 60; bs += m }
          } else nolaunch++
          if ((r in launch) && (r in land) && land[r] >= launch[r]) { k++; ev[k] = launch[r] SUBSEP 1; k++; ev[k] = land[r] SUBSEP "-1" }
        } else {
          fn++; fm += m
          if (st[i] == "active" && (r in launch) && launch[r] <= now) { k++; ev[k] = launch[r] SUBSEP 1; k++; ev[k] = now SUBSEP "-1" }
        }
      }
      # the width: events in time order, an end before a start at the same instant, each span weighted by its minutes
      for (i = 2; i <= k; i++) {
        x = ev[i]; split(x, a, SUBSEP)
        for (j = i - 1; j >= 1; j--) { split(ev[j], b, SUBSEP); if (b[1] + 0 < a[1] + 0 || (b[1] + 0 == a[1] + 0 && b[2] + 0 <= a[2] + 0)) break; ev[j + 1] = ev[j] }
        ev[j + 1] = x
      }
      c = 0; peak = 0; prev = ""; run = 0
      for (i = 1; i <= k; i++) {
        split(ev[i], a, SUBSEP)
        if (prev != "" && c > 0 && a[1] > prev) { w[c] += a[1] - prev; run += a[1] - prev }
        c += a[2]; if (c > peak) peak = c; prev = a[1]
      }
      med = "-"
      if (run > 0) { acc = 0; for (c = 1; c <= peak; c++) { acc += w[c]; if (acc * 2 >= run) { med = c; break } } }
      printf "%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%s\t%d\t%d\t%d\n", pn, pm, an, am, dn, dm, ln, lm, live, fn, fm,
        tn, to + 0.5, ts, nolaunch, med, (run > 0) ? peak : "-", bn, bo + 0.5, bs
    }'
}

# sitrep_ledger_times <ledger> -> `<D<n>><TAB><put epoch><TAB><ruling epoch or ->` per decision the design ledger puts:
# its first put that names a clock, and the first entry after it that rules it (any verb but put), each read from
# `decisions_list`'s records on the local clock; a ruling that names no clock is `-`. A put naming no clock starts no
# span; a later put of the same decision does not move the start.
sitrep_ledger_times() {
  local d pd pc pa rd rc ra k e
  [ -f "$1" ] && [ ! -L "$1" ] || return 0
  decisions_list "$1" times | awk -F'\t' '
    $2 == "put" { if (!($1 in put) && $4 != "") { put[$1] = $3 "\t" $4 "\t" $5; ord[++m] = $1 }; next }
    ($1 in put) && !($1 in rul) { rul[$1] = ($4 == "") ? "-" : $3 "\t" $4 "\t" $5 }
    END { for (i = 1; i <= m; i++) print ord[i] "\t" put[ord[i]] "\t" ((ord[i] in rul) ? rul[ord[i]] : "") }' \
  | while IFS='	' read -r d pd pc pa rd rc ra; do
      k="$(sitrep_local_epoch "$pd" "$pc" "$pa")"; [ -n "$k" ] || continue
      e="-"; [ -z "$rc" ] || e="$(sitrep_local_epoch "$rd" "$rc" "$ra")"
      printf '%s\t%s\t%s\n' "$d" "$k" "${e:--}"
    done
}

# sitrep_record_spans <plan> -> `<key><TAB><start ISO><TAB><end ISO or empty>` per ask the plan's `## SDLC State` times,
# for the asks the register closed with no `opened=`: a review waiver (`waive:<question>`) runs from the failing
# review's `at=` to the `waived:` line's instant, the last waiver of the question and the fail that began the failing
# state it answers (a passing reading, or a waiver, ends that state); a carry (`carry:<record>#<n>`, the register's
# key writing each character a key may not hold as `:`) runs from the `at=` of the review that registered its record,
# the reading `proof-add` wrote the `deferred:` line beside, to its ruling, which only the register holds (no end here).
# A `deferred:` line names no instant of its own. Fields are read by name through lib/line.sh's `line_kv`.
sitrep_record_spans() {
  { [ -n "${_LINE_FIELDS_AWK:-}" ] || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; }
  [ -n "${_LINE_FIELDS_AWK:-}" ] && [ -f "$1" ] && [ ! -L "$1" ] || return 0
  plan_lines "$1" | awk "$_LINE_FIELDS_AWK"'
    function ckey(id) { gsub(/[^A-Za-z0-9._-]/, ":", id); return "carry:" id }
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^##[ \t]/ { sdlc = ($0 ~ /^##[ \t]+SDLC State/); next }
    !sdlc { next }
    $1 == "proved:" && line_kv("kind") == "review" {
      q = line_kv("question"); r = line_kv("result"); a = line_kv("at"); ev = line_kv("evidence")
      if (ev != "" && !(ev in rat)) rat[ev] = a
      if (q == "") next
      if (r == "fail") { if (!(q in fail)) fail[q] = a } else delete fail[q]
      next }
    $1 == "deferred:" && !($2 in dseen) { dseen[$2] = 1; ev = $2; sub(/#[0-9]+$/, "", ev); if (ev in rat) cs[ckey($2)] = rat[ev]; next }
    $1 == "waived:" {
      q = line_kv("question"); w = ""
      for (i = 2; i <= NF && $i != "by"; i++) ;
      for (i++; i <= NF && substr($i, 1, 1) != "\""; i++) if ($i ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:]+Z$/) { w = $i; break }
      if (q != "" && w != "") { if (q in fail) { ws["waive:" q] = fail[q]; we["waive:" q] = w } else { delete ws["waive:" q]; delete we["waive:" q] } ; delete fail[q] }
      next }
    END {
      for (k in ws) printf "%s\t%s\t%s\n", k, ws[k], we[k]
      for (k in cs) printf "%s\t%s\t\n", k, cs[k] }'
}

# sitrep_waiting <plan> <root> <units_rows output> <now> <sitrep_asks output> -> `<minutes><TAB><keys>`: the minutes a
# task waited on an ask, every ask's span joined so an overlap counts once, and the keys whose span counted, in the
# order they opened. A span runs from the ask's opening (an open line's at=, a closed line's opened=) to its close (the
# closed line's at=), or to now while it is open. A decision with no opening on the register runs from its first put in
# the design ledger, and one the register never closed to its ruling's clock there; a waiver or a carry with none runs
# from the plan's own record of it (`sitrep_record_spans`). An open ask held a task when its holds are not nothing; a
# closed one when a row not dropped reads it as approval:<id>, it was a step card or a gate act, or it was a waiver,
# finding, carry, matrix row or held merge in a plan with an integrate row (what each holds while open, `sitrep_holds`).
# An ask no record can start counts no minute, and the minutes are printed `partial` with how many asks went untimed.
# Only the minutes an ask waits on the user count (lib/owed.sh `ask_waits_on`, open or closed): one answered so that it
# waits on an event counts to its answer, and one that never waits on the user (a carry, a delivery) counts none.
sitrep_waiting() {
  local plan="$1" root="$2" rows="$3" now="$4" asks="$5" reg="" led out m k spans waits
  reg="$(owed_register "$root" "$plan" 2>/dev/null)" || reg=""
  led="$(docs_root "$root")/record/$(proof_plan_slug "$plan")/design-ledger.md"
  spans="$(sitrep_record_spans "$plan")"
  # what each ask no longer open waits on; an open one's is the asks' own fifth field
  waits="$( { printf '%s\n' "$spans" | cut -f1
      { [ -n "$reg" ] && [ -f "$reg" ] && [ ! -L "$reg" ] && awk "$_OWED_AWK_FIELD"'
          index($0, "owed/v1|") == 1 && fld($0, "state") != "open" { print key_of($0) }' "$reg"; } 2>/dev/null
    } | awk 'NF && !s[$0]++' | while IFS= read -r k; do printf 'W\t%s\t%s\n' "$k" "$(ask_waits_on "$k" "$plan" "$root")"; done)"
  out="$( { printf '%s\n' "$asks" | awk -F'\t' 'NF >= 2 && $1 != "" { print "O\t" $1 "\t" $2 "\t" $5 }'
      printf '%s\n' "$rows" | awk -F'\t' 'NF >= 10 { s = tolower($10); gsub(/[ \t]/, "", s); k = $3; gsub(/[ \t]/, "", k)
        if (s == "dropped") next
        if (k == "integrate") print "I"
        n = split($13, t, ","); for (i = 1; i <= n; i++) { x = t[i]; gsub(/^[ \t]+|[ \t]+$/, "", x); sub(/^live:/, "", x); if (index(x, "approval:") == 1) print "A\t" substr(x, 10) } }'
      sitrep_ledger_times "$led" | awk -F'\t' '{ print "D\tdecide:" $1 "\t" $2 "\t" $3 }'
      printf '%s\n' "$spans" | awk -F'\t' 'NF { print "S\t" $1 "\t" $2 "\t" $3 }'
      printf '%s\n' "$waits" | awk 'NF'
      { [ -n "$reg" ] && [ -f "$reg" ] && [ ! -L "$reg" ] && awk "$_OWED_AWK_FIELD"'
          index($0, "owed/v1|") == 1 { print "R\t" key_of($0) "\t" fld($0, "state") "\t" fld($0, "at") "\t" fld($0, "opened") "\t" fld($0, "answered") }' "$reg"; } 2>/dev/null
    } | awk -F'\t' -v now="$now" "$_PATROL_ISO_AWK"'
      function norm(s) { if (length(s) == 17 && substr(s, 17, 1) == "Z") return substr(s, 1, 16) ":00Z"; return s }
      function ep(s) { if (s == "" || s == "-") return -1; return iso2epoch(norm(s)) }
      function want(k) { if (!(k in seen)) { seen[k] = 1; ord[++nk] = k } }
      function held(k,   x) {
        if (k in open) return open[k] != "nothing"
        if (k ~ /^approve:step[0-9]+$/ || index(k, "gate:") == 1) return 1
        if (k ~ /^(waive|finding|carry|row|hold):/) return integ
        if (index(k, "approve:") == 1) return ("approval:" substr(k, 9)) in rd
        if (k ~ /^decide:D[0-9]+$/) return ("approval:" substr(k, 8)) in rd
        return 0
      }
      $1 == "O" { open[$2] = $3; wt[$2] = $4; want($2); next }
      $1 == "W" { if (!($2 in wt)) wt[$2] = $3; next }
      $1 == "I" { integ = 1; next }
      $1 == "A" { rd["approval:" $2] = 1; next }
      $1 == "D" { put[$2] = $3; rul[$2] = $4; want($2); next }
      $1 == "R" { rs[$2] = $3; ra[$2] = $4; ro[$2] = $5; rn[$2] = $6; want($2); next }
      $1 == "S" { sp[$2] = $3; se[$2] = $4; next }
      END {
        for (i = 1; i <= nk; i++) {
          k = ord[i]; if (!held(k)) continue
          s = -1; e = -1; fromrec = 0
          if (k in rs) s = ep(rs[k] == "open" ? ra[k] : ro[k])
          if (s < 0 && (k in put)) s = put[k] + 0
          if (s < 0 && (k in sp)) { s = ep(sp[k]); fromrec = 1 }
          if (k in open) e = now + 0
          else if (fromrec && ep(se[k]) >= 0) e = ep(se[k])
          else if ((k in rs) && rs[k] == "closed") e = ep(ra[k])
          else if ((k in rul) && rul[k] != "-") e = rul[k] + 0
          # an ask waiting on an event waited on the user only until its answer, and never without one
          if ((k in wt) && wt[k] != "user") { x = (k in rn) ? ep(rn[k]) : -1; if (x < 0) continue; if (x < e) e = x }
          if (s < 0) { lost++; continue }
          if (e <= s) continue
          n++; bs[n] = s; be[n] = e; bk[n] = k
        }
        # the spans by their opening, joined where they overlap
        for (i = 2; i <= n; i++) { x = bs[i]; y = be[i]; z = bk[i]; for (j = i - 1; j >= 1 && bs[j] > x; j--) { bs[j + 1] = bs[j]; be[j + 1] = be[j]; bk[j + 1] = bk[j] } bs[j + 1] = x; be[j + 1] = y; bk[j + 1] = z }
        t = 0; ce = -1; keys = ""
        for (i = 1; i <= n; i++) {
          if (bs[i] > ce) { t += be[i] - bs[i]; ce = be[i] } else if (be[i] > ce) { t += be[i] - ce; ce = be[i] }
          keys = keys (keys == "" ? "" : " ") bk[i]
        }
        printf "%d\t%d\t%s\n", t / 60 + 0.5, lost, keys
      }')"
  IFS='	' read -r m u k <<SITREP_WAITING
$out
SITREP_WAITING
  m="${m:-0}"; u="${u:-0}"
  if [ "$u" -gt 0 ]; then
    m="$m min partial, $u $(sitrep_noun "$u" ask asks) not timed"
  else
    m="$m min"
  fi
  if [ -z "$k" ]; then printf '%s\n' "$m"
  else
    # shellcheck disable=SC2086
    printf '%s: %s\n' "$m" "$(sitrep_list 99 $k)"
  fi
}

# sitrep_bar -> the landing bar in minutes, lib/line.sh's LINE_LANDING_BAR, the one constant the scorecard's target
# reads; loaded as the stop-run record loads line.sh; nothing when unread.
sitrep_bar() {
  [ -n "${LINE_LANDING_BAR:-}" ] || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1
  case "${LINE_LANDING_BAR:-}" in ''|*[!0-9]*) return 0 ;; esac
  printf '%s\n' "$LINE_LANDING_BAR"
}

# sitrep_reds <landing record> -> one line per row holding a red at head (`R<TAB><row>`). A row's red is at head while
# it is its row and suite's newest verdict and the row has not been published since; a later green on that row and
# suite, or the row's landing, answers it. The suites red at their last run are `sitrep_suites`'.
sitrep_reds() {
  [ -f "$1" ] && [ ! -L "$1" ] || return 0
  { [ -n "${_LINE_FIELDS_AWK:-}" ] || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; }
  awk -F'|' "${_LINE_FIELDS_AWK:-}"'
    (ev = line_ev()) == "" { next }
    { rk = line_kv("row") }
    ev == "verdict" && line_kv("kind") == "regression" { next }   # facts of the whole run: no row holds them
    ev == "verdict" && rk != "" {
      k = rk SUBSEP line_kv("suite"); if (!(k in seen)) { seen[k] = 1; ord[++n] = k }; last[k] = line_kv("result")
      next
    }
    ev == "published" && rk != "" { for (i = 1; i <= n; i++) { split(ord[i], p, SUBSEP); if (p[1] == rk) last[ord[i]] = "landed" } }
    END {
      for (i = 1; i <= n; i++) if (last[ord[i]] == "red") {
        split(ord[i], p, SUBSEP)
        if (!(p[1] in said)) { said[p[1]] = 1; printf "R\t%s\n", p[1] }
      }
    }' "$1"
}

# sitrep_suites <landing record> -> `<suites><TAB><green><TAB><red>`: every suite the line ran for a row, by its last run,
# green or red. A `standing` event is the line's own red run of the suite at the head; a discarded run, or one that
# ran nothing, is no verdict on it. A suite named by a path is the suite its file name is. The whole run's verdicts
# (`kind=regression`) are no row's and are read by `sitrep_whole`.
sitrep_suites() {
  [ -f "$1" ] && [ ! -L "$1" ] || { printf '0\t0\t0\n'; return 0; }
  { [ -n "${_LINE_FIELDS_AWK:-}" ] || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; }
  awk -F'|' "${_LINE_FIELDS_AWK:-}"'
    (ev = line_ev()) == "" { next }
    ev == "verdict" && line_kv("kind") == "regression" { next }
    ev == "verdict" { r = line_kv("result"); if (r != "green" && r != "red") next }
    ev == "standing" { r = "red" }
    ev == "verdict" || ev == "standing" { st = line_kv("suite"); sub(/.*\//, "", st); if (st != "") last[st] = r }
    END { for (st in last) { n++; if (last[st] == "green") g++; else rd++ }; printf "%d\t%d\t%d\n", n, g, rd }' "$1"
}

# sitrep_whole <plan> <landing record> -> the whole run in words: `not run (regression: no, Step 0)` when the plan owes
# none; else the newer of the plan's last whole-run proof line (green at its head) and the record's last whole-run head
# (red when a suite's last verdict at it is red, else green), `green at <head8>` or `red at <head8>`; else `not run yet`.
sitrep_whole() {
  local plan="$1" rec="$2" line ph pa
  if declare -F plan_regression >/dev/null 2>&1 && [ "$(plan_regression "$plan" 2>/dev/null)" = no ]; then
    printf 'not run (regression: no, Step 0)\n'; return 0
  fi
  declare -F proof_last_line >/dev/null 2>&1 && line="$(proof_last_line "$plan" regression 2>/dev/null)"
  ph="$(printf '%s\n' "${line:-}" | tr ' ' '\n' | sed -n 's/^head=//p' | head -1)"
  pa="$(printf '%s\n' "${line:-}" | tr ' ' '\n' | sed -n 's/^at=//p' | head -1)"
  { [ -n "${_LINE_FIELDS_AWK:-}" ] || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; }
  { [ -f "$rec" ] && [ ! -L "$rec" ] && cat "$rec"; } 2>/dev/null | awk -F'|' -v ph="$ph" -v pa="$pa" "${_LINE_FIELDS_AWK:-}"'
    function norm(s) { if (length(s) == 17 && substr(s, 17, 1) == "Z") return substr(s, 1, 16) ":00Z"; return s }
    line_ev() == "verdict" && line_kv("kind") == "regression" && line_kv("commit") != "" {
      c = line_kv("commit"); r = line_kv("result"); if (r != "green" && r != "red") next
      if (c != h) { h = c; delete w }
      w[line_kv("suite")] = r; at = norm(line_kv("at"))
    }
    END {
      if (h != "" && (ph == "" || at > norm(pa))) { s = "green"; for (k in w) if (w[k] == "red") s = "red"; print s " at " substr(h, 1, 8); exit }
      if (ph != "") { print "green at " substr(ph, 1, 8); exit }
      print "not run yet" }'
}

# sitrep_test_ratio <plan> <root> -> `<tests> <code> <head>`: the two counts of shell lines the plan's newest release
# check printed, and the head it ran at; nothing when no check has run or its log holds no count. The check prints its
# count into the log it writes (`test-ratio: <tests>/<code>` on a pass, `release-check: test-ratio <tests>/<code> — …` on
# a refusal), so the release card quotes the check and never counts a tree again, and a project whose declared check
# prints no such line shows none. The evidence is a path under the docs root and never leaves it.
sitrep_test_ratio() {
  local line ev h log r
  line="$(proof_last_line "$1" check 2>/dev/null)"
  [ -n "$line" ] || return 0
  ev="${line#* evidence=}"; [ "$ev" != "$line" ] || return 0; ev="${ev%% *}"
  h="${line#* head=}"; h="${h%% *}"
  case "$ev" in ''|/*|*..*) return 0 ;; esac
  log="$(docs_root "$2")/$ev"
  [ -f "$log" ] && [ ! -L "$log" ] || return 0
  r="$(awk 'match($0, /^(release-check: )?test-ratio:? [0-9]+\/[0-9]+/) {
    s = substr($0, RSTART, RLENGTH); sub(/^(release-check: )?test-ratio:? /, "", s); split(s, a, "/"); print a[1] " " a[2]; exit }' "$log" 2>/dev/null)"
  [ -z "$r" ] || printf '%s %s\n' "$r" "$h"
}

# sitrep_forecast_end <plan> <units_rows output> -> `<epoch><TAB><words>`: the Step-3 approval (`approved-by:`) plus the
# plan's typed `forecast: <n>h|<n>m`, said `the <duration> forecast`, else plus the plan's own minutes (the size cells
# of every task not dropped), said `the plan's <n> min`; nothing before the approval.
sitrep_forecast_end() {
  local appr fc span which
  appr="$(sitrep_approved_at "$1")"
  [ -n "$appr" ] || return 0
  fc="$(plan_frontmatter_get "$1" forecast 2>/dev/null | awk '
    match($0, /^[0-9]+(\.[0-9]+)?[hm]?$/) { v = $0 + 0; if (v > 0) { if ($0 ~ /m$/) print v; else print v * 60 } }')"
  if [ -n "$fc" ]; then span="$fc"; which="the $(sitrep_dur "$fc") forecast"
  else
    span="$(printf '%s\n' "$2" | awk -F'\t' '{ s = tolower($10); gsub(/[ \t]/, "", s) } s != "dropped" && match($7, /^[0-9]+/) { t += substr($7, RSTART, RLENGTH) } END { print t + 0 }')"
    which="the plan's $span min"
  fi
  printf '%s\t%s\n' "$(awk -v a="$appr" -v s="$span" 'BEGIN { printf "%d", a + s * 60 }')" "$which"
}

# sitrep_reviews <plan> <root> -> `<question><TAB><scope><TAB><result><TAB><at ISO or -><TAB><record><TAB><open>` per
# review line of the plan's unfenced ## SDLC State (`proof_fields`: kind review with a question and a record), in the
# plan's order, a repeated record and result once. <open> counts the record's findings `disposition` would print
# open: S1 or S2, rated fix (`proof_finding_rating`), with no fix of it landed (`proof_fixed`).
sitrep_reviews() {
  local plan="$1" root="$2" docs fixed reads q sc res at ev h got num s r n
  { [ -f "$plan" ] && [ ! -L "$plan" ] && declare -F proof_awk >/dev/null 2>&1; } || return 0
  docs="$(docs_root "$root")"
  fixed="$(proof_fixed "$plan" "$root" 2>/dev/null)"
  reads="$(awk "$(proof_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && proof_fields($0) && PROOF_KIND == "review" && PROOF_QUESTION != "" && PROOF_EVIDENCE != "" && !((PROOF_EVIDENCE SUBSEP PROOF_RESULT) in seen) {
      seen[PROOF_EVIDENCE SUBSEP PROOF_RESULT] = 1; at = "-"
      if (match($0, /[ \t]at=[^ \t]+/)) at = substr($0, RSTART + 4, RLENGTH - 4)
      printf "%s\t%s\t%s\t%s\t%s\t%s\n", PROOF_QUESTION, (PROOF_SCOPE == "") ? "-" : PROOF_SCOPE, PROOF_RESULT, at, PROOF_EVIDENCE, PROOF_HEAD
    }' "$plan" 2>/dev/null)"
  while IFS='	' read -r q sc res at ev h; do
    [ -n "$q" ] || continue
    n=0
    if declare -F proof_findings >/dev/null 2>&1 && got="$(proof_findings "$docs/$ev" 2>/dev/null)"; then
      _proof_fixed_var "$fixed" "$ev" "$h" "$root"
      while IFS='	' read -r num s r _ _ _ _; do
        case "$num:$s" in debt:*|:*) continue ;; *:S1|*:S2) : ;; *) continue ;; esac
        case "$_PROOF_FIXED_IDS" in *$'\n'"$ev#$num"$'\n'*) continue ;; esac
        # shellcheck disable=SC2046
        set -- $(proof_finding_rating "$plan" "$ev#$num" "$s" "$r")
        [ "${3:-}" != fix ] || n=$((n + 1))
      done <<SITREP_FINDINGS
$got
SITREP_FINDINGS
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$q" "$sc" "$res" "$at" "$ev" "$n"
  done <<SITREP_REVIEWS
$reads
SITREP_REVIEWS
}

# sitrep_holds <plan> <root> <units_rows output> <key> <reply> -> what waits on the ask, in words: task labels, the release
# and the merge (the first five named, the rest counted), `step <n>` for a step card, or `nothing`. An approval holds
# the open tasks that read it; a decision what `decision_waiters` names; a waiver, a finding, a matrix row or a held
# merge the open integrate tasks, the merge they make; a gate act the task its line names; an unread ruling the row its
# reply says holds until a writer reads it.
sitrep_holds() {
  local plan="$1" root="$2" rows="$3" key="$4" ids="" w
  local -a words=()
  case "$key" in
    decide:D[0-9]*) ids="$(decision_waiters "$plan" "${key#decide:}" "$root")" ;;
    approve:step[0-9]|approve:step[0-9][0-9]) printf 'step %s\n' "$(( ${key#approve:step} + 1 ))"; return 0 ;;
    approve:*)
      ids="$(printf '%s\n' "$rows" | awk -F'\t' -v k="approval:${key#approve:}" '
        { s = tolower($10); gsub(/[ \t]/, "", s) } s == "landed" || s == "dropped" { next }
        { n = split($13, t, ","); for (i = 1; i <= n; i++) { x = t[i]; gsub(/^[ \t]+|[ \t]+$/, "", x); sub(/^live:/, "", x); if (x == k) { print $1; next } } }')" ;;
    waive:*|finding:*|row:*|hold:*)
      ids="$(printf '%s\n' "$rows" | awk -F'\t' '{ s = tolower($10); gsub(/[ \t]/, "", s); k = $3; gsub(/[ \t]/, "", k) }
        k == "integrate" && s != "landed" && s != "dropped" { print $1 }')" ;;
    gate:*) ids="$(printf '%s\n' "$5" | sed -n 's/.*GATE \(T[0-9A-Za-z._-]*\).*/\1/p' | head -n 1)" ;;
    ruling:*) ids="$(printf '%s\n' "$5" | sed -n 's/.*NOT-LANDED \(T[0-9A-Za-z._-]*\).*/\1/p' | head -n 1)" ;;
  esac
  while IFS= read -r w; do
    case "$w" in '') ;; release|merge) words[${#words[@]}]="the $w" ;; *) words[${#words[@]}]="$(sitrep_task_label "$rows" "$w")" ;; esac
  done <<SITREP_HOLDS
$ids
SITREP_HOLDS
  if [ "${#words[@]}" -gt 0 ]; then sitrep_list 5 "${words[@]}"; else printf 'nothing\n'; fi
}

# sitrep_asks <plan> <root> <units_rows output> <plan_goals_read output> <now epoch> ->
# `<key><TAB><holds><TAB><title><TAB><raised><TAB><waits>` per ask, `waits` what `ask_waits_on` says the ask waits on,
# `user` or `event <what>`, so the sheet, the handoff, the Patrol and the card read one answer: every item open on the run's register, in its order, with
# each decision put and not ruled in the place of its key or after them (`pages_owed`), a goal decision whose goal
# reads reached and a decision the ledger reads ruled or withdrawn dropped. Raised is the item's opening instant on the local clock, else a decision's put clock as its
# heading wrote it, else `-`; a decision's title is its number and the put's title.
sitrep_asks() {
  local plan="$1" root="$2" rows="$3" goals="$4" now="$5" owed gk gt led pages reg ats k sent ttl rep raised e d c
  owed="$( { owed_list_plan "$plan" "$root" 2>/dev/null || :; } )"
  gk="$(printf '%s\n' "$goals" | awk -F'\t' '$1 == "reached" { print $2 }' | while IFS= read -r gt; do printf 'decide:goal:%s ' "$(plan_goal_slug "$gt")"; done)"
  led="$(docs_root "$root")/record/$(proof_plan_slug "$plan")/design-ledger.md"
  # a decision the ledger reads ruled or withdrawn is closed in fact, whether or not `decisions` has settled its ask yet
  [ ! -f "$led" ] || [ -L "$led" ] || gk="$gk$(decisions_rounds "$led" | awk -F'\t' '$3 != "open" { printf "decide:%s ", $1 }')"
  [ -z "$gk" ] || owed="$(printf '%s\n' "$owed" | awk -F'\t' -v ks="$gk" 'BEGIN { n = split(ks, a, " "); for (i = 1; i <= n; i++) drop[a[i]] = 1 } !($1 in drop)')"
  pages="$(pages_open "$plan" "$led")"
  owed="$(printf '%s\n' "$owed" | pages_owed "$pages")"
  ats=""
  if reg="$(owed_register "$root" "$plan" 2>/dev/null)" && [ -f "$reg" ] && [ ! -L "$reg" ]; then
    ats="$(awk 'index($0, "owed/v1|") == 1 && index($0, "|state=open|") {
      k = ""; a = ""; n = split($0, p, "|")
      for (i = 2; i <= n; i++) { if (index(p[i], "key=") == 1) k = substr(p[i], 5); else if (index(p[i], "at=") == 1) a = substr(p[i], 4) }
      if (k != "") print k "\t" a }' "$reg" 2>/dev/null)"
  fi
  while IFS='	' read -r k sent ttl rep; do
    [ -n "$k" ] || continue
    raised="-"
    e="$(iso_epoch "$(printf '%s\n' "$ats" | awk -F'\t' -v k="$k" '$1 == k { a = $2 } END { print a }')" 2>/dev/null)"
    case "$e" in ''|*[!0-9]*) ;; *) raised="$(sitrep_clock "$e" "$now")" ;; esac
    case "$k" in
      decide:D[0-9]*)
        d="$(printf '%s\n' "$pages" | awk -F'\t' -v d="${k#decide:}" '$1 == "D" && $2 == d { print $3 "\t" $5; exit }')"
        if [ -n "$d" ]; then
          [ -z "${d%%	*}" ] || ttl="${k#decide:} · ${d%%	*}"
          c="${d#*	}"; [ "$raised" != - ] || [ -z "$c" ] || raised="$c"
        fi ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\n' "$k" "$(sitrep_holds "$plan" "$root" "$rows" "$k" "$rep")" "${ttl:-$k}" "$raised" "$(ask_waits_on "$k" "$plan" "$root")"
  done <<SITREP_ASKS
$owed
SITREP_ASKS
}

# sitrep_gather <plan> <root> <sheet|line> -> every fact of the sheet in the SG_* variables, rc 0; with `line`, only
# what the Patrol's status and the asks need (no reviews, no idle minutes, no suite runs).
sitrep_gather() {
  local plan="$1" root="$2" mode="$3" now rec rows reds red_rows lr lr1 approvals appr_at dlv_at cur lq lwait ledges
  local sit ty gl lab desc kind note id stp state landed=0 total=0 last_id="" last_at="" proj
  now="$(sitrep_now)"
  rec="$(_wt_proofs_path "$root" "$plan")"
  rows="$(units_rows "$plan" 2>/dev/null)"
  reds="$(sitrep_reds "$rec")"
  red_rows="$(printf '%s\n' "$reds" | awk -F'\t' '$1 == "R" { print $2 }')"
  lr="$(landing_report "$rec" "$root" yes 2>/dev/null)"; lr1="${lr%%$'\n'*}"
  SG_GOALS_READ="$(plan_goals_read "$plan" "$rec" "$lr")"
  SG_ASKS="$(sitrep_asks "$plan" "$root" "$rows" "$SG_GOALS_READ" "$now")"
  # an approval the user owes, a numbered decision a task reads as approval:D<n> among them, holds the tasks that read it
  approvals="$(printf '%s\n' "$SG_ASKS" | awk -F'\t' 'index($1, "approve:") == 1 { print substr($1, 9) } $1 ~ /^decide:D[0-9]+$/ { print substr($1, 8) }')"
  appr_at="$(sitrep_approved_at "$plan")"
  dlv_at="$(sitrep_delivered_at "$plan")"
  cur="$(awk '/^[[:space:]]*```/ { f = !f; next } !f && /^[[:space:]]*current[[:space:]]*:/ { s = $0; sub(/^[^:]*:[ \t]*/, "", s); sub(/[^0-9].*$/, "", s); print s; exit }' "$plan")"

  # ---- the tasks, in execution order (THE TASKS, IN EXECUTION ORDER, above)
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
            # each title is the one reading lib/plan.sh plan_task_title gives, as the plan card prints it
            printf '%s\n' "$rows" | awk -F'\t' 'NF >= 10 { x = $1; gsub(/^[ \t]+|[ \t]+$/, "", x); if (x != "") print x "\t" $4 }' \
              | while IFS='	' read -r id desc; do printf 'N\t%s\t%s\n' "$id" "$(plan_task_title "$desc")"; done
            printf '%s\n' "$rows" | awk -F'\t' 'NF >= 10 { print "U\t" $0 }'
          } | LC_ALL=C awk -F'\t' "$(_sitrep_label_awk)"'
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function words(r,   t) {   # a read, in words: the step, the user'"'"'s approval, the reviews, the build, the merge
      sub(/^live:/, "", r); t = r; sub(/: .*$/, "", t)
      if (index(t, "step:") == 1) return "step " substr(t, 6)
      if (t ~ /^approval:D[0-9]+$/) return "your approval of " substr(t, 10)
      if (index(t, "approval:") == 1) return "your approval of the " substr(t, 10)
      if (t == "proof:review") return "the reviews"
      if (index(t, "proof:") == 1) return "the " substr(t, 7) " facts at the head"
      if (r == "head") return "the last build row landing"
      if (r == "merge") return "the merge"
      return r
    }
    function wait_on(i, e) {   # one thing task i waits on, once: words, or "@" and the writer task named at the end
      if ((i, e) in wseen) return
      wseen[i, e] = 1; wn[i]++; we[i, wn[i]] = e
    }
    function waits(i,   k, e, s) {   # everything task i waits on, joined: "A", "A and B", "A, B and C"
      s = ""
      for (k = 1; k <= wn[i]; k++) {
        e = we[i, k]; if (substr(e, 1, 1) == "@") e = label(substr(e, 2))
        s = s ((k == 1) ? "" : (k == wn[i]) ? " and " : ", ") e
      }
      return "waits on " s
    }
    function row(i, kind, note,   d) {
      if (id[i] in red && st[i] != "landed") { kind = "s"; note = "red" }
      d = ttl[id[i]]; if (d == "") d = "-"
      printf "R\t%s\t%s\t%s\t%s\t%s\t%s\n", g[i], (stp[i] == "") ? "-" : stp[i], id[i], d, kind, note
    }
    $1 == "N" { ttl[$2] = $3; next }
    $1 == "X" { red[$2] = 1; next }
    $1 == "A" { appr[$2] = 1; next }
    $1 == "L" { land[$2] = $3; hand[$2] = $4; next }
    $1 == "Q" { nq++; qr[nq] = $2; qc[nq] = $3; qo[nq] = $4; qg[nq] = $5; qm[nq] = $6; next }
    # a read another task writes is that task, by its label; the step, an approval, the reviews, the build and the merge
    # are said in words whoever writes them
    $1 == "W" { t = $3; sub(/^live:/, "", t); sub(/: .*$/, "", t)
      w = ($4 != "" && $4 != "-" && t !~ /^(step:|approval:|proof:review$|head$|merge$)/) ? "@" $4 : words($3)
      wait_on($2, w); next }
    $1 == "E" { ne++; ef[ne] = $2; et[ne] = $3; next }
    $1 == "U" {
      s = tolower(trim($11)); if (s == "dropped") next
      n++; id[n] = trim($2); stp[n] = trim($3); rd[n] = $14; st[n] = s; at[id[n]] = n
      b = 0
      if (s != "landed") {
        if (id[n] in red) b = 1
        m = split(rd[n], a, ",")
        for (k = 1; k <= m; k++) {
          x = trim(a[k]); sub(/^live:/, "", x)
          if (index(x, "approval:") == 1 && (substr(x, 10) in appr)) { b = 1; nb[n]++; wait_on("held:" id[n], words(x)) }
        }
      }
      g[n] = (s == "landed") ? "L" : (b ? "X" : (s == "active" ? "A" : "P"))
    }
    END {
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
        if (qc[q] != "-" && qc[q] != "") note = ((qo[q] == "stalled") ? "stalled in its landing, " : "in its landing, ") ((qm[q] + 0 > 0) ? qg[q] " of " qm[q] ((qm[q] + 0 == 1) ? " suite" : " suites") " green" : "no suite to run")
        else note = (prev == "") ? "next on the line" : "queued behind " label(prev)
        row(i, "s", note); prev = qr[q]
      }
      # an active task reading an approval still owed is held on it, and says so rather than building
      for (i = 1; i <= n; i++) if (st[i] == "active" && !(i in placed)) {
        note = "building"
        if (g[i] == "X" && nb[i] > 0) note = waits("held:" id[i])
        row(i, "s", note)
      }
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
        if (st[pick] == "held") { row(pick, "s", "held"); continue }
        if (st[pick] != "pending" || !wn[id[pick]]) { row(pick, "b", ""); continue }
        row(pick, "s", waits(id[pick]))
      }
    }')"
  SG_TASKS=""
  while IFS='	' read -r ty gl stp id desc kind note; do
    [ "$ty" = R ] || continue
    total=$((total + 1))
    case "$gl" in
      L) state=done; landed=$((landed + 1))
         case "$kind" in
           t|th) last_id="$id"; last_at="$note"
                 note="landed $(sitrep_clock "$note" "$now")"; [ "$kind" = t ] || note="$note by hand" ;;
         esac ;;
      A) state=running ;;
      X) if [ "$note" = red ]; then state=failed; else state=held; fi ;;
      *) if [ "$note" = held ]; then state=held; else state=pending; fi ;;
    esac
    SG_TASKS="${SG_TASKS}task: id=$id step=$stp state=$state desc=$desc note=${note:--}"$'\n'
  done <<SITREP_SIT
$sit
SITREP_SIT
  SG_TASKCOUNT="$landed of $total $(sitrep_noun "$total" task tasks)"
  SG_LAST="-"; [ -z "$last_id" ] || SG_LAST="$last_id at $(sitrep_clock "$last_at" "$now")"

  # ---- the steps: before current: done, current: and any later step a landed or active task stands at running
  SG_STEPS="$(printf '%s\n' "$rows" | awk -F'\t' -v cur="$cur" -v dlv="${dlv_at:+yes}" -v names="$SITREP_STEP_NAMES" '
    { s = tolower($10); gsub(/[ \t]/, "", s); st = $2; gsub(/[ \t]/, "", st) }
    s == "dropped" || st !~ /^[0-9]+$/ { next }
    { n[st + 0]++; if (s == "landed" || s == "active") work[st + 0] = 1 }
    END {
      split(names, nm, " ")
      for (k = 0; k <= 9; k++) {
        if (dlv == "yes" || (cur != "" && k < cur + 0)) w = "done"
        else if ((cur != "" && k == cur + 0) || (k in work)) w = "running"
        else w = "pending"
        printf "step: n=%d name=%s state=%s tasks=%d\n", k, nm[k + 1], w, n[k] + 0
      }
    }')"

  # ---- the run
  SG_NOWW="$(sitrep_date "$now" '%A %-I:%M %p')"
  SG_STEP="${cur:--}"
  SG_NAME="$(proof_plan_slug "$plan")"
  SG_RELEASE="$(plan_frontmatter_get "$plan" release 2>/dev/null)"; SG_RELEASE="${SG_RELEASE:--}"
  SG_WAVE="$(printf '%s\n' "$SG_NAME" | awk 'match($0, /(^|-)wave-[0-9]+/) { s = substr($0, RSTART, RLENGTH); sub(/^.*wave-0*/, "", s); print (s == "") ? 0 : s; exit }')"
  SG_WAVE="${SG_WAVE:--}"
  proj="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  case "$proj" in */.git) proj="${proj%/.git}"; proj="${proj##*/}" ;; *) proj="${root##*/}" ;; esac
  SG_PROJECT="$proj"
  SG_STARTED="$(awk "$_PATROL_ISO_AWK"'
    function norm(s) { if (length(s) == 17 && substr(s, 17, 1) == "Z") return substr(s, 1, 16) ":00Z"; return s }
    function first(s) { if (match(s, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9](:[0-9][0-9])?Z/)) return iso2epoch(norm(substr(s, RSTART, RLENGTH))); return -1 }
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^##[ \t]/ { s = ($0 ~ /^##[ \t]+SDLC State/); next }
    s && /^- Step 0:/ && z == "" { e = first($0); if (e >= 0) z = e }
    s && /^approved-by:/ && a == "" { e = first($0); if (e >= 0) a = e }
    END { if (z != "") print z; else if (a != "") print a }' "$plan" 2>/dev/null)"
  case "$SG_STARTED" in ''|*[!0-9]*) SG_STARTED="-" ;; *) SG_STARTED="$(sitrep_clock "$SG_STARTED" "$now")" ;; esac

  # ---- the clock, the work, the pace and the close (THE MEASUREMENTS, above)
  local fe span wk pn pm an am dn dm ln lm live fn fm tn to ts nol wmed wpeak bn bo bs chain cids cmins clab ratio cl mins el
  local held launches wts wun chain1 cmins1 amin aid atop top top1 csz hrow
  SG_C_NOW="$(sitrep_clock "$now" "$now")"
  SG_C_APPR="-"; SG_C_FC="-"; SG_C_FCW="the plan's forecast:"; SG_C_EL="-"; SG_C_SHARE="-"; span=""
  if [ -n "$appr_at" ]; then
    SG_C_APPR="$(sitrep_clock "$appr_at" "$now")"
    fe="$(sitrep_forecast_end "$plan" "$rows")"
    if [ -n "$fe" ]; then
      span=$(( (${fe%%	*} - appr_at) / 60 ))
      SG_C_FC="$(sitrep_dur "$span"), ends $(sitrep_clock "${fe%%	*}" "$now")"
      case "${fe#*	}" in "the plan's"*) SG_C_FCW="the plan's sized minutes, as it declares no forecast:" ;; esac
    fi
    el=$(( (now - appr_at) / 60 )); [ "$el" -ge 0 ] || el=0
    SG_C_EL="$(sitrep_dur "$el")"
    [ -z "$span" ] || [ "$span" -le 0 ] || SG_C_SHARE="$(( (el * 200 + span) / (span * 2) ))%"
  fi
  wk="$(sitrep_work "$plan" "$rec" "$root" "$rows" "$now" "$appr_at")"
  IFS='	' read -r pn pm an am dn dm ln lm live fn fm tn to ts nol wmed wpeak bn bo bs <<< "$wk"
  SG_W_PLANNED="$pn $(sitrep_noun "$pn" task tasks), $pm min"
  SG_W_ADDED="$an $(sitrep_noun "$an" task tasks), $am min"
  SG_W_DROPPED="$dn $(sitrep_noun "$dn" task tasks), $dm min"
  SG_W_SHARE="-"; [ "${live:-0}" -le 0 ] || SG_W_SHARE="$(( (lm * 200 + live) / (live * 2) ))%"
  SG_W_LANDED="$ln $(sitrep_noun "$ln" task tasks), $lm of $live min, $SG_W_SHARE"
  SG_W_LEFT="$fn $(sitrep_noun "$fn" task tasks), $fm min"
  if [ "$wmed" = - ]; then SG_W_WIDTH="not measured: no launch of this plan on the rosters"
  else SG_W_WIDTH="median $wmed, peak $wpeak"; fi
  if [ "${ln:-0}" -eq 0 ]; then SG_W_TT="0 tasks: none has landed"
  elif [ "${tn:-0}" -eq 0 ]; then SG_W_TT="0 tasks: none of the $ln landed has both a launch and a landing on record"
  else
    SG_W_TT="$tn $(sitrep_noun "$tn" task tasks), $to min against $ts sized min"
    [ "${nol:-0}" -eq 0 ] || SG_W_TT="$SG_W_TT; $nol landed $(sitrep_noun "$nol" task tasks) with no launch or landing on record"
  fi
  # the chain: the open tasks that must run one after another, by label. Each is weighed by its kind and, running, by what
  # it has left (sitrep_close_weights), and the chain is the heaviest by that weight; its sized minutes are what the
  # line prints. Build tasks are scaled by the landed build tasks' own time over their size once 3 or more have
  # landed, else 1×; every other kind sits at face value, as does a task held on an ask that names it.
  if [ "${bn:-0}" -ge 3 ] && [ "${bs:-0}" -gt 0 ]; then ratio="$bo/$bs"; else ratio="1/1"; fi
  # only an ask that waits on the user holds a task on you: one answered, waiting on an event, scales as any other
  held="$(printf '%s\n' "$SG_ASKS" | awk -F'\t' 'NF >= 2 && $1 != "" && $5 == "user" { h = $2; gsub(/,| and /, " ", h); m = split(h, w, " "); for (i = 1; i <= m; i++) print w[i] }')"
  launches="$(sitrep_launches "$plan" "$root")"
  wts="$(sitrep_close_weights "$rows" "$now" "$ratio" "$held" "$launches")"
  chain="$(sitrep_chain "$plan" "$rows" "$wts")"; cids="${chain%%$'\t'*}"; cmins="${chain##*$'\t'}"
  amin="$(printf '%s\n' "$wts" | awk -F'\t' '$1 == "A" { print $2 }')"; aid="$(printf '%s\n' "$wts" | awk -F'\t' '$1 == "A" { print $3 }')"
  hrow="$(printf '%s\n' "$wts" | awk -F'\t' '$1 == "H" { print $2 }')"
  clab=""
  if [ -n "$cids" ]; then
    clab="$(printf '%s\n' "$cids" | tr ',' '\n' | while IFS= read -r k; do [ -z "$k" ] || sitrep_task_label "$rows" "$k"; done | awk 'NF' | paste -sd' ' - | sed 's/ / → /g')"
    csz="$(printf '%s\n' "$rows" | awk -F'\t' -v c=",$cids," 'index(c, "," $1 ",") { m = 0; if (match($7, /^[0-9]+/)) m = substr($7, RSTART, RLENGTH); t += m } END { print t + 0 }')"
    SG_K_CHAIN="$clab, $csz min"
  else SG_K_CHAIN="none: no task is open"; fi
  # the close: now plus the longer of the longest remaining time of a running task and the chain
  SG_K_UNSCALED="-"; SG_K_WAITS="no"
  SG_BASIS="clock.now plus the longer of close.chain and the longest remaining time of a running task, a running task at its size less its elapsed, build tasks"
  if [ "${bn:-0}" -ge 3 ] && [ "${bs:-0}" -gt 0 ]; then
    SG_BASIS="$SG_BASIS scaled by the $bn landed build tasks' own time over their size, $bo min over $bs sized min, every other task at face value"
  else
    SG_BASIS="$SG_BASIS at 1×: $([ "${bn:-0}" -eq 1 ] && echo "1 landed build task has" || echo "${bn:-0} landed build tasks have") a launch and a landing on record, under 3, every other task at face value"
  fi
  [ -z "$hrow" ] || SG_BASIS="$SG_BASIS; a task held on you is unscaled"
  if [ -n "$dlv_at" ]; then
    cl="$(sitrep_clock "$dlv_at" "$now")"; SG_PREDICTED="$cl"; SG_BASIS="delivered at $cl; nothing is left to forecast"
  elif [ -z "$appr_at" ]; then
    SG_PREDICTED="-"; SG_BASIS="no forecast until the plan is approved at Step 3"
  elif [ -z "$cids" ]; then
    SG_PREDICTED="$SG_C_NOW"; SG_BASIS="no task is open; nothing is left to forecast"
  else
    top="$cmins"; [ "${amin:-0}" -le "$top" ] || top="$amin"
    SG_PREDICTED="$(sitrep_clock "$(awk -v n="$now" -v m="$top" 'BEGIN { printf "%d", int((n + m * 60) / 60 + 0.5) * 60 }')" "$now")"
    # the same basis with no scaling: every task at its sized minutes, a running one still at what it has left
    wun="$(sitrep_close_weights "$rows" "$now" "1/1" "" "$launches")"
    chain1="$(sitrep_chain "$plan" "$rows" "$wun")"; cmins1="${chain1##*$'\t'}"
    top1="$cmins1"; atop="$(printf '%s\n' "$wun" | awk -F'\t' '$1 == "A" { print $2 }')"; [ "${atop:-0}" -le "$top1" ] || top1="$atop"
    SG_K_UNSCALED="$(sitrep_clock "$(( (now + top1 * 60 + 30) / 60 * 60 ))" "$now")"
    # an ask that waits on the user and holds a task the prediction rests on (the chain or the longest-running task), the
    # release or the merge: the prediction assumes it is answered now
    k="$(printf '%s\n' "$SG_ASKS" | awk -F'\t' -v labs="$(printf '%s' "$clab" | sed 's/ → / /g') $([ -z "$aid" ] || sitrep_task_label "$rows" "$aid")" '
      BEGIN { n = split(labs, l, " "); for (i = 1; i <= n; i++) on[l[i]] = 1 }
      NF >= 2 && $1 != "" && $5 == "user" { h = $2; gsub(/,| and /, " ", h); m = split(h, w, " "); hit = 0
        for (i = 1; i <= m; i++) if ((w[i] in on) || w[i] == "release" || w[i] == "merge") hit = 1
        if (hit) printf "%s%s", (c++ ? " " : ""), $1 }')"
    # shellcheck disable=SC2086
    [ -z "$k" ] || SG_K_WAITS="yes: $(sitrep_list 99 $k)"
  fi
  SG_LINE_CLOSE="$SG_PREDICTED"; [ "$SG_PREDICTED" != - ] || SG_LINE_CLOSE="not forecast"
  SG_FORECAST="$SG_C_FC"
  SG_P_TIME="$SG_C_SHARE"; SG_P_WORK="$SG_W_SHARE"
  [ "$mode" = sheet ] || return 0

  # ---- correctness and waste
  local k rv q sc res at ev nf passed=0 failed=0 running=0 jhead jv jrc open idle_min rg rr rn rd rk g m st t md rdg fr u sn sg sr nsu
  rv="$(sitrep_reviews "$plan" "$root")"
  SG_REVIEWS=""
  # THE COUNT IS THE JUDGE'S, as the release card's Reviews lines are: each question the rigor deals, failed only while
  # lib/proof.sh `facts_reviews` reads it failing at the working branch's head, so a failed reading its fix landing
  # answered counts passed here exactly when the card reads it covered. A question nobody has read is not counted.
  # A plan the judge cannot deal (no rigor and scale, no base, no head) has no coverage to read: there each question
  # and scope counts once by its latest recorded result, a pass a later fail supersedes being no pass.
  jhead="$(proof_branch_head "$plan" "$root" 2>/dev/null)" || jhead=""
  jv=""; jrc=2
  if [ -n "$jhead" ] && declare -F facts_reviews >/dev/null 2>&1; then jv="$(facts_reviews "$plan" "$jhead" 2>/dev/null)"; jrc=$?; fi
  if [ "$jrc" -ne 2 ]; then
    SG_T_REVIEWS_WHAT="the reviews, each question once as the judge reads it at the head"
    read -r passed failed <<< "$(printf '%s\n' "$jv" | awk -F'\t' 'NF >= 3 && $3 != "absent" { if ($3 == "failing") f++; else p++ } END { print p + 0, f + 0 }')"
  else
    SG_T_REVIEWS_WHAT="the reviews, each question and scope once by its latest result"
    read -r passed failed <<< "$(printf '%s\n' "$rv" | awk -F'\t' '
      function norm(s) { if (length(s) == 17 && substr(s, 17, 1) == "Z") return substr(s, 1, 16) ":00Z"; return s }
      NF >= 6 { k = $1 SUBSEP $2; a = norm($4); if (!(k in r) || a == "-" || t[k] == "-" || a >= t[k]) { r[k] = $3; t[k] = a } }
      END { for (k in r) { if (r[k] == "pass" || r[k] == "flag") p++; else if (r[k] == "fail") f++ }; print p + 0, f + 0 }')"
  fi
  while IFS='	' read -r q sc res at ev nf; do
    [ -n "$q" ] || continue
    k="$(iso_epoch "$at" 2>/dev/null)"
    case "$k" in ''|*[!0-9]*) at="-" ;; *) at="$(sitrep_clock "$k" "$now")" ;; esac
    SG_REVIEWS="${SG_REVIEWS}review: question=$q scope=$sc result=$res at=$at open-findings=$nf record=$ev"$'\n'
  done <<SITREP_RV
$rv
SITREP_RV
  # a review task in flight is a review running, its result not yet recorded
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    running=$((running + 1))
    SG_REVIEWS="${SG_REVIEWS}review: question=$k scope=whole result=running at=- open-findings=0 record=-"$'\n'
  done <<SITREP_RUNNING
$(printf '%s\n' "$rows" | awk -F'\t' '{ s = tolower($10); gsub(/[ \t]/, "", s); k = $3; gsub(/[ \t]/, "", k) } k == "review" && s == "active" { print $1 }')
SITREP_RUNNING
  # a record read twice (a re-run's result beside the first) counts its findings once, as it stands now
  open="$(printf '%s\n' "$rv" | awk -F'\t' 'NF >= 6 { o[$5] = $6 } END { for (e in o) t += o[e]; print t + 0 }')"
  SG_T_REVIEWS="$passed passed, $failed failed, $running running"; SG_T_FINDINGS="$open"
  IFS='	' read -r sn sg sr <<< "$(sitrep_suites "$rec")"
  SG_T_RUN="${sn:-0}: ${sg:-0} green, ${sr:-0} red"
  nsu="$(for k in "$root"/tests/*.test.sh; do [ -f "$k" ] && printf '%s\n' "$k"; done | awk 'END { print NR }')"
  SG_T_TOTAL="$nsu"; [ "$nsu" -gt 0 ] || SG_T_TOTAL="-"
  SG_T_WHOLE="$(sitrep_whole "$plan" "$rec")"
  idle_min="$(cd "$root" 2>/dev/null && "${BASH:-bash}" "$HOOK_DIR/session-poker.sh" fill-report "$plan" 2>/dev/null | sed -n 's/^idle minutes: \([0-9][0-9]*\)$/\1/p' | head -n 1)"
  # the landing report's run counts; a run killed at the gate (rc over 128) is a discarded run
  case "$lr1" in
    *'· runs: green='*)
      rg="${lr1#*runs: green=}"; rg="${rg%% *}"; rr="${lr1#* red=}"; rr="${rr%% *}"
      rn="${lr1#* none=}"; rn="${rn%% *}"; rd="${lr1#* discarded=}"; rd="${rd%% *}" ;;
    *) rg=0 rr=0 rn=0 rd=0 ;;
  esac
  rk="${lr1##*killed=}"; case "$rk" in ''|*[!0-9]*) rk=0 ;; esac
  SG_X_RUNS="$((rd + rk)) of $((rg + rr + rn + rd + rk))"
  if [ -n "$idle_min" ]; then SG_X_IDLE="$idle_min min"; else SG_X_IDLE="not measured: the fill record gave no idle minutes"; fi
  SG_X_WAIT="$(sitrep_waiting "$plan" "$root" "$rows" "$now" "$SG_ASKS")"
  # the scorecard's three lines at close, each from the measurements above, never a ratio of unlike units
  SG_PACE="$SG_P_WORK of the live work's sized minutes landed, in $SG_P_TIME of the forecast time"
  SG_CORRECT="suites run $SG_T_RUN; whole run $SG_T_WHOLE; reviews $SG_T_REVIEWS; $SG_T_FINDINGS open $(sitrep_noun "$SG_T_FINDINGS" finding findings)"
  SG_WASTE="dropped $SG_W_DROPPED; $SG_X_RUNS suite runs discarded; $SG_X_IDLE ready and unstarted; $SG_X_WAIT waiting on you"
  # the goals, each status the one function's
  SG_GOAL="$(plan_goal_paragraph "$plan")"
  SG_GOAL_LINES=""; g=0; m=0; k=0; u=0
  # split by hand: a goal with no measure has an empty field, which a tab-split read would close up
  while IFS= read -r st; do
    t="${st#*	}"; md="${t#*	}"; rdg="${md#*	}"; st="${st%%	*}"; t="${t%%	*}"; md="${md%%	*}"
    [ -n "$t" ] || continue
    # a theme's row ends in its opener, a fifth tab-separated field; a measured goal's has none
    fr=""; case "$rdg" in *'	'*) fr="${rdg#*	}"; rdg="${rdg%%	*}" ;; esac
    g=$((g + 1))
    st="$(plan_goal_status "$st")"
    case "$st" in met) m=$((m + 1)) ;; 'not measured') k=$((k + 1)) ;; unreadable) u=$((u + 1)) ;; esac
    # the measure and what it read, joined by lib/plan.sh's grammar, which the card reads back
    md="$(plan_goal_measure "$md" "$rdg")"
    SG_GOAL_LINES="${SG_GOAL_LINES}goal: name=$t status=$st measure=$md${fr:+ for=$fr}"$'\n'
  done <<SITREP_GOALS
$SG_GOALS_READ
SITREP_GOALS
  return 0
}

# sitrep_ask_lines -> one `ask:` line per ask of sitrep_gather's facts, the sheet's asks. `blocks=` is the fact the card
# places the ask from: yes only when the ask holds a task, the release or the merge AND waits on the user, since an ask
# that waits on an event blocks nobody; `waits=` is what the ask waits on, `user` or `event <what>`, and stands last.
# The handoff's head reads this same rule, so no reader decides what blocks. The model never decides either field.
sitrep_ask_lines() {
  local k h t r w b
  while IFS='	' read -r k h t r w; do
    [ -n "$k" ] || continue
    [ -n "$w" ] || w=user
    if [ "$h" != nothing ] && [ "$w" = user ]; then b=yes; else b=no; fi
    printf 'ask: key=%s holds=%s title=%s raised=%s blocks=%s waits=%s\n' "$k" "$h" "$t" "$r" "$b" "$w"
  done <<SITREP_SHEET_ASKS
$SG_ASKS
SITREP_SHEET_ASKS
}

# sitrep_m <key> <value> <what it measures> <unit> <source: … or basis: …> -> one measured line of the sheet
sitrep_m() { printf '%s: %s — %s · unit: %s · %s\n' "$1" "$2" "$3" "$4" "$5"; }

# sitrep_sheet -> the sheet from sitrep_gather's SG_* facts, in its order
sitrep_sheet() {
  printf '%s\n' "$SITREP_SHEET_HEAD"
  printf 'run.release: %s\nrun.name: %s\nrun.wave: %s\nrun.now: %s\nrun.step: %s\n' "$SG_RELEASE" "$SG_NAME" "$SG_WAVE" "$SG_NOWW" "$SG_STEP"
  printf 'run.project: %s\nrun.started: %s\nrun.last-landing: %s\n' "$SG_PROJECT" "$SG_STARTED" "$SG_LAST"
  [ -z "$SG_GOAL" ] || printf 'run.goal: %s\n' "$SG_GOAL"
  printf '%s\n' "$SG_STEPS"
  printf '%s' "$SG_TASKS"
  sitrep_m clock.now "$SG_C_NOW" "when this sheet was printed" "local time" "source: the verb's clock"
  sitrep_m clock.approved "$SG_C_APPR" "when you approved the plan at Step 3" "local time" "source: the plan's approved-by: line"
  sitrep_m clock.forecast "$SG_C_FC" "how long the plan said the run would take, and when that ends" "wall-clock hours, local time" "source: $SG_C_FCW plus clock.approved"
  sitrep_m clock.elapsed "$SG_C_EL" "wall clock since the approval" "h min" "source: clock.now less clock.approved"
  sitrep_m clock.elapsed-share "$SG_C_SHARE" "the forecast used so far" "% of clock.forecast" "source: clock.elapsed over the forecast's hours"
  sitrep_m work.planned "$SG_W_PLANNED" "the tasks in the plan at the approval" "count, sized minutes" "source: the Tasks rows whose own line names no joining after the approval"
  sitrep_m work.added "$SG_W_ADDED" "the tasks added since the approval" "count, sized minutes" "source: the Tasks rows whose own line says task-add added them, or a split made them, after the approval"
  sitrep_m work.dropped "$SG_W_DROPPED" "the tasks dropped" "count, sized minutes" "source: the rows with status dropped"
  sitrep_m work.landed "$SG_W_LANDED" "the tasks landed" "count, sized minutes of the live work's sized minutes, % of them" "source: the rows with status landed"
  sitrep_m work.left "$SG_W_LEFT" "the tasks neither landed nor dropped" "count, sized minutes" "source: the remaining rows"
  sitrep_m work.width "$SG_W_WIDTH" "how many tasks ran at once, launch to landing or to now" "tasks, the median over the minutes any task ran and the peak" "source: the rosters' launches and the landing record's landed: lines"
  sitrep_m work.task-time "$SG_W_TT" "the landed tasks' own time, launch to landing, against their size" "minutes against sized minutes" "source: the rosters' first launch of each row and the landing record's landed: lines"
  sitrep_m pace.time-used "$SG_P_TIME" "the share of the forecast time used, as clock.elapsed-share" "%" "source: clock.elapsed over the forecast's hours"
  sitrep_m pace.work-landed "$SG_P_WORK" "the share of the live work landed, as in work.landed" "% of the live work's sized minutes" "source: work.landed"
  sitrep_m close.chain "$SG_K_CHAIN" "the longest run of tasks left that must go one after another" "task labels, sized minutes" "source: the open rows' reads, a verify row ahead of the integrate row"
  sitrep_m close.predicted "$SG_PREDICTED" "when the run is expected to end" "local time" "basis: $SG_BASIS"
  sitrep_m close.unscaled "$SG_K_UNSCALED" "the same, with no scaling" "local time" "source: clock.now plus the same spans, every task at its sized minutes"
  sitrep_m close.waits-on-you "$SG_K_WAITS" "whether the prediction assumes you answer now" "yes or no, and which asks" "source: the open asks that hold a task on close.chain or the longest-running task, the release or the merge"
  sitrep_m tests.suites-run "$SG_T_RUN" "the suites run this wave, each by its last run" "count run: count green, count red" "source: the landing record's verdicts"
  sitrep_m tests.suites-total "$SG_T_TOTAL" "the suites in the project" "count" "source: the project's tests/*.test.sh, every suite tests/run.sh runs"
  sitrep_m tests.whole-run "$SG_T_WHOLE" "the whole regression" "not run (and why), or green or red at a commit" "source: the plan's regression: and its proof"
  sitrep_m reviews "$SG_T_REVIEWS" "${SG_T_REVIEWS_WHAT:-the reviews, each question and scope once by its latest result}" "count passed, failed, running" "source: the review proofs and the review tasks in flight"
  sitrep_m findings.open "$SG_T_FINDINGS" "the review findings not yet closed" "count" "source: the review records"
  sitrep_m waste.dropped "$SG_W_DROPPED" "the tasks dropped, as work.dropped" "count, sized minutes" "source: the rows with status dropped"
  sitrep_m waste.runs-discarded "$SG_X_RUNS" "the suite runs thrown away" "count of all suite runs" "source: the landing record and the gate"
  sitrep_m waste.ready-unstarted "$SG_X_IDLE" "the minutes a ready task sat while the machine had room" "minutes" "source: the fill record"
  sitrep_m waste.waiting-on-you "$SG_X_WAIT" "the minutes a task waited on an ask, overlaps counted once" "minutes, and which asks" "source: the register's opened and closed times; a decision with no opened time, its first put in the design ledger"
  printf '%s' "$SG_GOAL_LINES"
  sitrep_ask_lines
  printf '%s' "$SG_REVIEWS"
}

# THE SHEET THE JUDGMENT IS WRITTEN FROM. `sitrep` saves the sheet it prints beside a stamp, `<epoch><TAB><plan's real
# path>`, under the project's .bionic/tmp; `sitrep card` checks and draws the judgment against that sheet while it is
# under SITREP_SAVED_MAX seconds old, because the sheet's clock and its predicted close move while the model writes and
# a true judgment must not be refused for a minute's drift. The stamp sits beside the sheet, never in it: card.sh reads
# every run of digits in the sheet as a number the metrics may state. The asks are never the saved ones: a card is
# drawn with the register's asks as they stand, so an ask opened since the sheet was read is still owed.
SITREP_SAVED_MAX=600

sitrep_saved() {  # <root> <plan> -> the path of the plan's saved sheet
  local b="${2##*/}"
  b="${b%.md}"; b="${b%.plan}"
  printf '%s/.bionic/tmp/sitrep/%s.sheet\n' "$1" "$b"
}

sitrep_plan_real() { printf '%s/%s\n' "$(cd "${1%/*}" 2>/dev/null && pwd -P)" "${1##*/}"; }   # <plan> -> its real path

# sitrep_save <root> <plan> -> the sheet on stdout; saved with its stamp when .bionic/tmp takes a write, else printed
# alone, and the card verb then finds no sheet to draw from
sitrep_save() {
  local f
  f="$(sitrep_saved "$1" "$2")"
  if tmp_dir_ok "$1/.bionic/tmp" && mkdir -p "${f%/*}" 2>/dev/null && [ ! -L "${f%/*}" ] \
     && sitrep_sheet > "$f.$$" 2>/dev/null && mv -f "$f.$$" "$f" \
     && printf '%s\t%s\n' "$(sitrep_now)" "$(sitrep_plan_real "$2")" > "$f.at" 2>/dev/null; then
    cat "$f"
  else
    rm -f "$f.$$" 2>/dev/null
    sitrep_sheet
  fi
}

# sitrep_saved_age <root> <plan> -> the saved sheet's age in seconds, or `missing` when there is none for this plan
sitrep_saved_age() {
  local f at plan now
  f="$(sitrep_saved "$1" "$2")"
  [ -f "$f" ] && [ ! -L "$f" ] && [ -f "$f.at" ] && [ ! -L "$f.at" ] || { printf 'missing\n'; return 0; }
  IFS='	' read -r at plan < "$f.at"
  case "$at" in ''|*[!0-9]*) printf 'missing\n'; return 0 ;; esac
  [ "$plan" = "$(sitrep_plan_real "$2")" ] || { printf 'missing\n'; return 0; }
  now="$(sitrep_now)"
  if [ "$now" -gt "$at" ]; then printf '%s\n' "$((now - at))"; else printf '0\n'; fi
}

# sitrep_status -> the Patrol's status from sitrep_gather's facts:
# `<k> of <m> tasks · owed: <n> on you · <m> on events · close <time>`, <n> the asks that wait on the user and <m> the
# rest; an ask whose wait is not read as an event is the user's, since doubt is the user's.
sitrep_status() {
  local on ev
  read -r on ev <<SITREP_COUNT
$(printf '%s\n' "$SG_ASKS" | awk -F'\t' 'NF && $1 != "" { if (index($5, "event ") == 1) e++; else n++ } END { print n + 0, e + 0 }')
SITREP_COUNT
  printf '%s · owed: %s on you · %s on events · close %s\n' "$SG_TASKCOUNT" "$on" "$ev" "$SG_LINE_CLOSE"
}

# sitrep_blocked_on_you -> yes when some ask of sitrep_gather's facts blocks the user, else no: the sheet's own
# `blocks=` lines, so the handoff's head says what the sheet says. The lines are read whole into a variable before
# they are matched, so no reader quits early on a writer still feeding it and the answer cannot flip under pipefail.
sitrep_blocked_on_you() {
  local lines
  lines="$(sitrep_ask_lines)"
  case "$lines" in
    *' blocks=yes waits='*) printf 'yes\n' ;;
    *) printf 'no\n' ;;
  esac
}

# sitrep_ask_words -> one `<title> — holds <what>` line per ask of sitrep_gather's facts, ` · waits on <what>` ending
# the line of an ask that waits on an event; the asks the handoff's head and the resume recap carry
sitrep_ask_words() {
  printf '%s\n' "$SG_ASKS" | awk -F'\t' 'NF >= 3 && $1 != "" { w = ""; if (index($5, "event ") == 1) w = " · waits on " substr($5, 7); print $3 " — holds " $2 w }'
}

# sitrep_tick_line <plan> -> `poker: sitrep <the Patrol's status>`, the tick's one-line form: the same facts the `--line`
# arm reads, at the plan's own root, so the two are byte-equal by construction. Silent when there is no plan to report
# on or the proof record cannot load; the tick is unaffected either way.
sitrep_tick_line() {
  local plan="${1:-}" root
  { [ -n "$plan" ] && [ -f "$plan" ] && [ ! -L "$plan" ]; } || return 0
  declare -F proof_plan_slug >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; } >/dev/null 2>&1
  declare -F proof_plan_slug >/dev/null 2>&1 || return 0
  root="$(cd "$(project_root "${plan%/*}")" 2>/dev/null && pwd -P)"
  [ -n "$root" ] || return 0
  sitrep_gather "$plan" "$root" line 2>/dev/null
  say "sitrep $(sitrep_status)"
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

  # THE HANDOFF DOCUMENT. One self-contained file a fresh session continues from, written whole by this verb and never
  # by hand, with or without a bound run, to lib/handoff.sh `handoff_home_file`: the run's slug when one is bound, else
  # the purpose's, else the branch's. The project's bionic folder is created with its ignore file (the literal `*`)
  # when the project has none, and a handoffs folder git would track gets one of its own, so the file is never in
  # source control. The kind line, then the head: the title (the project, the local day and time, the run or `no run
  # bound`, and `for <purpose>` when the one argument names it), bound the run's status line (`sitrep --line`'s),
  # `Blocked on you: yes|no` and one `- <title> — holds <what>` line per open ask; then the sections in order:
  #   Summary · Goal · State · Findings · Decisions · Ruled out · Open · Suggested skills · Next · Resume
  # State is this verb's alone: `written:` (the local clock) and `instant:` (the ISO instant readers compare), the tree (handoff_tree_lines), what runs (handoff_running_lines and, bound,
  # handoff_landing_lines), the agents (the harness's newest ListAgents answer, else the roster's open rows marked
  # unverified) with each one's type, run, brief and progress file, and, bound, the plan, step, working and
  # integration branches, open tasks (the sheet's: every task it does not read as done) and Patrol; a closed run's resume point and branch lines are close-out.sh's
  # (`closed-form`, the one writer of both). Every other section is composed by the session and read on stdin
  # (lib/handoff.sh `handoff_compose`); a composed State or Resume is dropped. The whole page passes the redaction
  # (lib/handoff.sh `handoff_redact`) and folds at the shared width (card.sh fold); the last line is never folded: bound,
  # `/bionic:canonical-sdlc <path>`, the door that rebinds the run; with no run, `Read <path> whole, then do Next 1.`
  # There is no safe-to-clear line: the source session is disposable, and anything in flight is in State.
  # Bound, the plan's `## Handoff` then becomes the heading and one pointer line, through the plan transaction,
  # best-effort: the document is in place first. REFUSED (2), nothing written: the file's path a link or a directory;
  # (1) a bound open plan with no `## Tasks` or no `## SDLC State`.
  poker_verb_handoff() {
    HO_IN=""; [ -t 0 ] || HO_IN="$(cat)"
    HO_E="$(sitrep_now)"
    HO_NOW="$(epoch_iso "$HO_E")"
    HO_CF="$(mktemp "${TMPDIR:-/tmp}/bionic-handoff.XXXXXX")" || HO_CF=/dev/null
    HO_SID="$(session_id 2>/dev/null)" || HO_SID=""
    HO_MODE=none; HO_ROOT=""
    if [ -n "$HO_SID" ] && engaged_session "$(project_root "$PWD")" "$HO_SID"; then
      case "$(session_run "$(cd "$(project_root "$PWD")" 2>/dev/null && pwd -P)" "$HO_SID")" in
        'bound-open '*) HO_MODE=open ;;
        'bound-closed '*)
          HO_RUN="$(session_run "$(cd "$(project_root "$PWD")" 2>/dev/null && pwd -P)" "$HO_SID")"
          if /usr/bin/grep -qE '^[[:space:]]*-?[[:space:]]*Step[[:space:]]+9[[:space:]]*:.*delivered:' "${HO_RUN#bound-closed }" 2>/dev/null; then
            HO_MODE=closed
          fi ;;
      esac
    fi
    if [ "$HO_MODE" != none ]; then
      plan_verb_open handoff closed-ok
      HO_ROOT="$PV_REPO"
      trap 'rm -f "$PV_NEW" "$PV_NEW.2" "$PV_DRY" ${PV_MARK:+"$PV_MARK"} "$HO_CF"' EXIT
      if [ "$HO_MODE" = open ]; then
        if ! /usr/bin/grep -qE '^##[[:space:]]+Tasks([[:space:]]|$)' "$PV_PLAN"; then
          die "REFUSED — the plan has no ## Tasks section, so there are no open tasks to hand off; the plan is unchanged."
          exit 1
        fi
        if ! /usr/bin/grep -qE '^##[[:space:]]+SDLC State([[:space:]]|$)' "$PV_PLAN"; then
          die "REFUSED — the plan has no ## SDLC State section, so its step cannot be handed off; the plan is unchanged."
          exit 1
        fi
      fi
      if ! { declare -F proof_plan_slug >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
         || ! declare -F proof_plan_slug >/dev/null 2>&1; then
        die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
        exit 2
      fi
      { declare -F _line_entries >/dev/null 2>&1 || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; } || :
      HO_SLUG="$(proof_plan_slug "$PV_PLAN")"
      HO_RUNWORD="$HO_SLUG"
    else
      HO_ROOT="$(cd "$(project_root "$PWD")" 2>/dev/null && pwd -P)"
      if [ -z "$HO_ROOT" ]; then
        die "REFUSED — cannot resolve the working directory."
        exit 2
      fi
      trap 'rm -f "$HO_FILE.tmp.$$" "$HO_CF"' EXIT
      HO_RUNWORD="no run bound"
    fi
    HO_PURPOSE="$(printf '%s' "$HO_ARG_PATH" | tr -d '[:cntrl:]' | handoff_redact /dev/null)"
    if [ "$HO_MODE" = none ]; then
      HO_SLUG="$(handoff_slug "$HO_PURPOSE")"
      [ -n "$HO_SLUG" ] || HO_SLUG="$(handoff_slug "$(git -C "$HO_ROOT" symbolic-ref --short -q HEAD 2>/dev/null)")"
      [ -n "$HO_SLUG" ] || HO_SLUG=session
    fi
    HO_FILE="$(handoff_home_file "$HO_ROOT" "$HO_SLUG")"
    HO_REL="${HO_FILE#"$HO_ROOT"/}"
    if [ -L "$HO_FILE" ] || [ -d "$HO_FILE" ] || [ -L "${HO_FILE%/*}" ]; then
      die "REFUSED — the handoff's path is a link or a directory ($HO_REL); nothing was written."
      exit 2
    fi
    # WHERE IT GOES IS NEVER TRACKED: the bionic folder made with its ignore file, else the handoffs folder given one.
    HO_HAD_HOME=yes; [ -d "$HO_ROOT/.bionic" ] || HO_HAD_HOME=no
    if ! mkdir -p "${HO_FILE%/*}" 2>/dev/null; then
      die "REFUSED — the handoffs folder cannot be made at ${HO_FILE%/*}; nothing was written."
      exit 2
    fi
    [ "$HO_HAD_HOME" = yes ] || printf '*\n' > "$HO_ROOT/.bionic/.gitignore"
    if git -C "$HO_ROOT" rev-parse --git-dir >/dev/null 2>&1 && ! git -C "$HO_ROOT" check-ignore -q "$HO_FILE" 2>/dev/null; then
      [ -e "${HO_FILE%/*}/.gitignore" ] || printf '*\n' > "${HO_FILE%/*}/.gitignore"
    fi
    # THE COMPOSED HALF.
    HO_COMP="$(printf '%s\n' "$HO_IN" | handoff_compose)"
    # THE STATE.
    HO_TREE="$(handoff_tree_lines "$HO_ROOT")"
    HO_RUNS="$(handoff_running_lines "$HO_ROOT")"
    [ "$HO_MODE" != open ] || HO_RUNS="$(printf '%s\n%s\n' "$HO_RUNS" "$(handoff_landing_lines "$PV_PLAN" "$HO_ROOT")" | awk 'NF')"
    HO_N_RUN=0; [ -z "$HO_RUNS" ] || HO_N_RUN="$(printf '%s\n' "$HO_RUNS" | grep -c .)"
    # THE LIVE AGENTS ARE THE HARNESS'S, NOT THE ROSTER'S. The roster records that a dispatch happened, never that an
    # agent is alive, so the list is the newest ListAgents answer in this session's transcript (lib/agents.sh, the one
    # parser of it): every agent it names that is not `idle`, less every agent a TaskStop after the answer ended. An
    # answer a later dispatch outdates, a stale one, or none at all cannot say who is live: the roster's open rows are
    # listed in its place, marked unverified. With no session key there is no roster or transcript to read.
    HO_AGENTS=""; HO_N_AG=0; HO_VER=""
    if [ -z "$HO_SID" ]; then
      HO_VER="unverified — no session key, so this session's agents cannot be read"
    else
      HO_RF="$HO_ROOT/.bionic/tmp/roster-$HO_SID.state"
      HO_TR="$(session_transcript "$HO_SID")" || HO_TR=""
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
        HO_VER="verified by the newest ListAgents answer"
        HO_NAMES="$(printf '%s\n' "$HO_SET" | HO_GONE="$(printf '%s\n' "$HO_SINCE" | awk -F'\t' '$1 == "stopped" { print $2 }')" \
          awk -F'|' -v idle="$_LA_ROW_CLOSED_STATUS" '
            BEGIN { n = split(ENVIRON["HO_GONE"], g, "\n"); for (i = 1; i <= n; i++) if (g[i] != "") gone[g[i]] = 1 }
            $1 != "" && $3 != idle && !($1 in gone) && !($1 in seen) { seen[$1] = 1; print $1 }')"
      else
        HO_VER="unverified — $HO_WHY; the roster's open rows"
        HO_NAMES="$(roster_open_names "$HO_RF" "$HO_ROOT/.bionic/tmp/sweeper-$HO_SID.state" "$HO_SID")"
      fi
      HO_UROWS=""; [ "$HO_MODE" = none ] || HO_UROWS="$(units_rows "$PV_PLAN" 2>/dev/null)"
      while IFS= read -r HO_NAME; do
        [ -n "$HO_NAME" ] || continue
        HO_ROW="$(awk -v k="|name=$HO_NAME|" 'index($0 "|", k) { l = $0 } END { print l }' "$HO_RF" 2>/dev/null)"
        HO_TYPE="$(line_field "$HO_ROW" subagent_type)"
        HO_PROG="$(line_field "$HO_ROW" progress)"
        HO_ST="no run"
        if run_load_row "$(run_row_of "$HO_RF" "$HO_NAME")" "$HO_RF"; then run_read; HO_ST="$(run_state_words)"; fi
        HO_BRIEF="in its dispatch"
        HO_ID="$(printf '%s\n' "$HO_UROWS" | awk -F'\t' -v n="$HO_NAME" '$5 == n { print $1; exit }')"
        if [ -n "$HO_ID" ] && [ -f "$(docs_root "$HO_ROOT")/record/$HO_SLUG/briefs/$HO_ID.md" ]; then
          HO_BRIEF="$(docs_root "$HO_ROOT")/record/$HO_SLUG/briefs/$HO_ID.md"; HO_BRIEF="${HO_BRIEF#"$HO_ROOT"/}"
        fi
        HO_AGENTS="${HO_AGENTS:+$HO_AGENTS
}  - $(clean "$HO_NAME") · $(clean "${HO_TYPE:-agent}") · $HO_ST · brief $(clean "$HO_BRIEF") · progress $(clean "${HO_PROG:-none named}")"
        HO_N_AG=$((HO_N_AG + 1))
      done <<< "$HO_NAMES"
    fi
    if [ "$HO_MODE" != none ]; then
      HO_PLAN_REL="${PV_PLAN#"$PV_REPO"/}"
      HO_PATROL="not armed"
      HO_STAMP="$(patrol_stamp_file "$HO_SID")" || HO_STAMP=""
      if [ -n "$HO_STAMP" ] && [ -f "$HO_STAMP" ] && [ ! -L "$HO_STAMP" ]; then
        HO_PATROL="armed — stamp $(( ( $(now_epoch) - $(file_mtime "$HO_STAMP") ) / 60 ))m old"
      fi
      { declare -F scale_cell >/dev/null 2>&1 || { [ -r "$BIONIC_LIB/scale.sh" ] && . "$BIONIC_LIB/scale.sh"; }; } >/dev/null 2>&1
      if declare -F scale_cell >/dev/null 2>&1 \
         && [ "$(scale_cell "$(plan_frontmatter_get "$PV_PLAN" scale 2>/dev/null)" patrol 2>/dev/null)" = no ]; then
        HO_PATROL="none — a task-scale run has no Patrol"
      fi
      HO_LEDGER="$(docs_root "$HO_ROOT")/record/$HO_SLUG/design-ledger.md"
    fi
    if [ "$HO_MODE" = closed ]; then
      HO_CO="$(cd "$BIONIC_LIB" 2>/dev/null && pwd -P)/../close-out.sh"
      HO_CLOSED="$(bash "$HO_CO" "$PV_PLAN" closed-form 2>/dev/null)" || HO_CLOSED=""
      case "$HO_CLOSED" in
        'resume point: '*$'\n''branch: '*) : ;;
        *) die "REFUSED — a closed run's resume point is close-out.sh's to say, and its closed-form did not print it ($HO_CO); nothing was written."
           exit 2 ;;
      esac
      case "$HO_CLOSED" in 'resume point: PARKED on '*) HO_KIND=parked ;; *) HO_KIND=delivered ;; esac
    elif [ "$HO_MODE" = open ]; then
      HO_HEADS=""
      for HO_B in "$(plan_working_branch "$PV_PLAN")" "$(plan_integration_branch "$PV_PLAN")"; do
        HO_H=""
        [ -z "$HO_B" ] || HO_H="$(git -C "$PV_REPO" rev-parse --verify -q "refs/heads/$HO_B^{commit}" 2>/dev/null)" || HO_H=""
        HO_HEADS="${HO_HEADS:+$HO_HEADS
}$([ -n "$HO_B" ] && printf '%s' "$(clean "$HO_B")" || printf '(none named)') @ ${HO_H:-(no such branch)}"
      done
      HO_ROWS=""
    fi
    # THE HEAD: bound, the run's status line and one `<title> — holds <what>` line per open ask, the sheet's own facts
    # (sitrep_gather), so the head and the sitrep cannot disagree on what is owed; with no run, the session's own
    # open asks, which no plan says anything waits on.
    HO_RUNLINE=""; HO_ASKS=""; HO_BLOCKED=no
    if [ "$HO_MODE" != none ]; then
      { declare -F proof_plan_slug >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } >/dev/null 2>&1
      HO_SRR="$(cd "$(project_root "${PV_PLAN%/*}")" 2>/dev/null && pwd -P)"
      if declare -F proof_plan_slug >/dev/null 2>&1 && [ -n "$HO_SRR" ]; then
        sitrep_gather "$PV_PLAN" "$HO_SRR" line 2>/dev/null
        HO_RUNLINE="$(sitrep_status)"; HO_ASKS="$(sitrep_ask_words)"; HO_BLOCKED="$(sitrep_blocked_on_you)"
        # The open tasks are the sheet's: every task it does not read as done, so the list is the run line's own
        # `m` less its `k`; each is joined to its row for the agent and the worktree it names.
        HO_ROWS="$( { printf '%s\n' "$SG_TASKS" | awk '/^task: id=/ { id = $2; sub(/^id=/, "", id)
                          st = $4; sub(/^state=/, "", st); if (st != "done") print "S\t" id "\t" st }'
                      units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' 'NF >= 11 { print "U\t" $1 "\t" $5 "\t" $11 }'
                    } | awk -F'\t' '
          $1 == "U" { ag[$2] = ($3 == "") ? "—" : $3; wt[$2] = ($4 == "" || $4 == "-") ? "—" : $4; next }
          $1 == "S" { n++; id[n] = $2; st[n] = $3 }
          END { for (i = 1; i <= n; i++) print "  - " id[i] " · " ((id[i] in ag) ? ag[id[i]] : "—") " · " ((id[i] in wt) ? wt[id[i]] : "—") " · " st[i] }')"
      fi
    elif [ -n "$HO_SID" ] && declare -F owed_list >/dev/null 2>&1; then
      HO_ASKS="$(OWED_ROOT="$HO_ROOT" OWED_SID="$HO_SID" owed_list 2>/dev/null | awk -F'\t' 'NF >= 3 && $1 != "" { print (($3 != "") ? $3 : $1) " — holds nothing" }')"
    fi
    # THE PAGE: every line `<continuation indent> TAB <text>`, redacted, then folded; the last line after the fold.
    HO_TITLE="Handoff · $(clean "${HO_ROOT##*/}") · $(sitrep_date "$HO_E" '%A %-I:%M %p') · $HO_RUNWORD"
    [ -z "$HO_PURPOSE" ] || HO_TITLE="$HO_TITLE · for $(clean "$HO_PURPOSE")"
    if [ "$HO_MODE" = none ]; then HO_LAST="Read $HO_REL whole, then do Next 1."; else HO_LAST="/bionic:canonical-sdlc $HO_REL"; fi
    HO_TMP="$HO_FILE.tmp.$$"; [ "$HO_MODE" = none ] || HO_TMP="$PV_NEW.2"
    ho_state() {  # -> the State section's lines, each with its fold indent
      printf '2\twritten: %s\n' "$(sitrep_clock "$HO_E" "$HO_E")"
      printf '2\tinstant: %s\n' "$HO_NOW"
      printf '%s\n' "$HO_TREE" | awk '{ print (/^  - / ? "4" : "2") "\t" $0 }'
      if [ -n "$HO_RUNS" ]; then printf '2\trunning (%s):\n' "$HO_N_RUN"; printf '%s\n' "$HO_RUNS" | awk '{ print "4\t" $0 }'
      else printf '2\trunning: none\n'; fi
      if [ "$HO_N_AG" -gt 0 ]; then printf '2\tagents (%s): %s\n' "$HO_N_AG" "$HO_VER"; printf '%s\n' "$HO_AGENTS" | awk '{ print "4\t" $0 }'
      else printf '2\tagents: none (%s)\n' "$HO_VER"; fi
      [ "$HO_MODE" != none ] || return 0
      printf '2\tplan: %s\n' "$HO_PLAN_REL"
      if [ "$HO_MODE" = closed ]; then
        printf '2\t%s\n' "${HO_CLOSED%%$'\n'*}"
        printf '2\tworking branch: %s\n' "${HO_CLOSED#*$'\n'branch: }"
        printf '2\tcontinuation: record/%s/continuation.md\n' "$HO_SLUG"
      else
        printf '2\tstep: %s\n' "${PV_CUR:--}"
        printf '2\tworking branch: %s\n' "${HO_HEADS%%$'\n'*}"
        printf '2\tintegration: %s\n' "${HO_HEADS#*$'\n'}"
        if [ -n "$HO_ROWS" ]; then printf '2\topen tasks (%s):\n' "$(printf '%s\n' "$HO_ROWS" | grep -c .)"; printf '%s\n' "$HO_ROWS" | awk '{ print "4\t" $0 }'
        else printf '2\topen tasks: none\n'; fi
      fi
      printf '2\tpatrol: %s\n' "$HO_PATROL"
    }
    {
      printf 'bionic-handoff/v1\n'
      {
        printf '0\t%s\n' "$HO_TITLE"
        [ -z "$HO_RUNLINE" ] || printf '0\t%s\n' "$HO_RUNLINE"
        printf '0\tBlocked on you: %s\n' "$HO_BLOCKED"
        printf '%s\n' "$HO_ASKS" | awk 'NF { print "2\t- " $0 }'
        printf '0\t\n'
        for HO_S in Summary Goal State Findings Decisions "Ruled out" Open "Suggested skills" Next; do
          printf '0\t%s\n' "$HO_S"
          case "$HO_S" in
            State) ho_state ;;
            Decisions)
              if [ "$HO_MODE" != none ] && [ -f "$HO_LEDGER" ] && [ ! -L "$HO_LEDGER" ]; then
                handoff_render "$HO_COMP" Decisions | awk -F'\t' '$2 != "- none."'
                printf '2\t- every ruling of this run: %s\n' "${HO_LEDGER#"$HO_ROOT"/}"
              else
                handoff_render "$HO_COMP" Decisions
              fi ;;
            *) handoff_render "$HO_COMP" "$HO_S" ;;
          esac
          printf '0\t\n'
        done
        printf '0\tResume\n'
      } | handoff_redact "$HO_CF" | "${BASH:-bash}" "$(cd "$BIONIC_LIB/.." 2>/dev/null && pwd -P)/card.sh" fold
      printf '%s\n' "$HO_LAST"
    } > "$HO_TMP" 2>/dev/null || { die "REFUSED — the handoff cannot be written at $HO_FILE; nothing was written."; exit 2; }
    # WHAT IT SAYS IS HOW THE NEXT SESSION RESUMES, and nothing more: the resume line carries the file's path as its
    # operand, so no second line names it, and the counts, the redactions and the blocks left out are in the file
    # for whoever reads it. On success stdout is that one line and stderr is empty.
    if [ "$HO_MODE" = none ]; then
      if ! mv -f "$HO_TMP" "$HO_FILE" 2>/dev/null; then
        die "REFUSED — the handoff file cannot be moved into place at $HO_FILE."
        exit 2
      fi
      printf '%s\n' "$HO_LAST"
      exit 0
    fi
    # THE DOCUMENT FIRST, ALWAYS; THE POINTER AFTER, AND ONLY IF THE PLAN TAKES IT. The source session may be dying,
    # so nothing about the plan may cost it the document: the file is moved into place before the plan is touched.
    # The plan's `## Handoff` then becomes one line, rewritten in place or created before ## Not Doing, through the
    # plan transaction (its dry commit through the real gate); when the gate or the rewrite refuses, one line says the
    # pointer was not written and why, the plan is left as it was, and the verb still exits 0.
    if ! mv -f "$HO_TMP" "$HO_FILE" 2>/dev/null; then
      die "REFUSED — the handoff file cannot be moved into place at $HO_FILE."
      exit 2
    fi
    printf '%s\n' "$HO_LAST"
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
    HO_DRY=writer; [ "$HO_MODE" != closed ] || HO_DRY=as-is
    HO_NOPTR=""
    if [ "$PV_RC" -ne 0 ]; then
      HO_NOPTR="its rewrite failed (awk exit $PV_RC)"
    elif ! cmp -s "$PV_NEW" "$PV_PLAN"; then
      HO_SWAP="$( ( plan_verb_swap handoff "the handoff pointed at $HO_REL" "$HO_DRY" ) 2>&1 )" || {
        HO_NOPTR="$(printf '%s\n' "$HO_SWAP" | sed -n 's/^poker: //p' | awk 'NF { print; exit }')"
        [ -n "$HO_NOPTR" ] || HO_NOPTR="the plan transaction refused it"
      }
    fi
    [ -z "$HO_NOPTR" ] || say "handoff — the plan's ## Handoff pointer was not written: $(clean "${HO_NOPTR:0:240}")"
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
    # The counts over the window, then its two ends (line.sh `hand_holds_verb`): --since and --until when named, else
    # the last build landing and the release approval page.
    hand_holds_verb "$(_wt_proofs_path "$LR_ROOT" "$LR_PLAN")" "$LR_ROOT" "$LR_PLAN" "$LR_SINCE" "$LR_UNTIL"
    case "$LR_TEXT" in *$'\n'*) printf '%s\n' "${LR_TEXT#*$'\n'}" ;; esac
    exit 0
  }
  # decisions_settle <plan> <ledger> -> always 0, prints nothing: the ask of every decision the ledger reads ruled or
  # withdrawn is closed on the run's register. A ruling is the ledger's own entry, written in the person's words with no
  # verb of its own, so every `decisions` call settles the register against the ledger before it reads or puts.
  decisions_settle() {
    local d st
    declare -F owed_close >/dev/null 2>&1 || return 0
    [ -f "$2" ] && [ ! -L "$2" ] || return 0
    decisions_rounds "$2" | while IFS='	' read -r d _ st; do
      [ "$st" = open ] || OWED_ROOT="$REPO_REAL" OWED_PLAN="$1" owed_close "decide:$d" "$st" >/dev/null 2>&1
    done
    return 0
  }
  # THE LEDGER'S ONE WRITE, for the put and the ruling alike: one entry appended as `## Δ<k> — <heading>`, k one past
  # the ledger's highest Δ, its body under a blank line when it has one, through a copy swapped in whole, so a reader
  # never sees half an entry and both writers number alike; the ledger is begun when the run has none. 1, with the
  # refusal said, when the ledger cannot be written. The clock is the local one every heading of the ledger names.
  decisions_clock() { date '+%Y-%m-%d %-I:%M %p %Z'; }
  decisions_append() {  # <plan> <ledger> <root> <heading> [<body>]
    local plan="$1" led="$2" root="$3" k
    k="$(sed -n 's/^## Δ\([0-9][0-9]*\).*/\1/p' "$led" 2>/dev/null | sort -n | tail -1)"; k=$(( ${k:--1} + 1 ))
    mkdir -p "${led%/*}" 2>/dev/null
    { if [ -f "$led" ]; then cat "$led"; else printf '# Design ledger — %s\n' "$(proof_plan_slug "$plan")"; fi
      printf '\n## Δ%s — %s\n' "$k" "$4"
      [ -z "${5:-}" ] || printf '\n%s\n' "$5"
    } > "$led.new.$$" 2>/dev/null && mv -f "$led.new.$$" "$led" 2>/dev/null && return 0
    rm -f "$led.new.$$" 2>/dev/null
    die "REFUSED — ${led#"$root"/} cannot be written; nothing is written."
    return 1
  }
  # THE PUT. A decision put during a run is one ledger entry before it is shown, `## Δ<k> — D<n> put (orchestrator
  # <date> <time>): <title>`, Δ one past the ledger's highest, its body the wait line; the ledger is begun when the run
  # has none. It prints the round the put opens and the wait line, which ends the decision's Significance as printed.
  # REFUSED (1), nothing written: a number that is not D<n>, a title that is empty or more than one line, a ledger that
  # is a symlink.
  decisions_put() {  # <plan> <ledger> <D<n>> <title>
    local plan="$1" led="$2" d="$3" title="$4" wait r
    case "$d" in D[1-9]*) case "${d#D}" in *[!0-9]*) d="" ;; esac ;; *) d="" ;; esac
    if [ -z "$d" ]; then
      die "REFUSED — '$(clean "$3")' is not a decision's number: name it D<n>, as in D7; nothing is written."
      exit 1
    fi
    case "$title" in ''|*$'\n'*) die "REFUSED — the title is one line saying what is decided; nothing is written."; exit 1 ;; esac
    if [ -L "$led" ]; then
      die "REFUSED — ${led#"$REPO_REAL"/} is a symlink; nothing is written."
      exit 1
    fi
    wait="$(decision_wait "$plan" "$d" "$REPO_REAL")"
    decisions_append "$plan" "$led" "$REPO_REAL" "$d put (orchestrator $(decisions_clock)): $title" "$wait" || exit 1
    # THE PUT IS AN ASK ON THE RUN'S REGISTER, in the words the pages owe it in (`pages_owed`), so a decision put and
    # not yet ruled is owed wherever the register is read; the ledger's ruling closes it (`decisions_settle`).
    if declare -F owed_open >/dev/null 2>&1; then
      OWED_ROOT="$REPO_REAL" OWED_PLAN="$plan" owed_open "decide:$d" "reply to $d" "$d · $title: reply with the option number. $wait" >/dev/null 2>&1 || :
    fi
    r="$(decisions_rounds "$led" | awk -F'\t' -v d="$d" '$1 == d { print $2 }')"
    printf 'put: %s · round %s · %s\n' "$d" "${r:-1}" "$title"
    printf 'wait: %s\n' "$wait"
    exit 0
  }

  # THE RULING. However the reply arrives, typed to `decisions rule`, given by `approve D<n>`, or replayed from the
  # release approval card (whose reply runs `approve`), it is this one function, so a decision ruled anywhere has its
  # ledger entry and its closed ask. It writes `## Δ<k> — D<n> ruled "<reply>" (<who> <date> <clock>): <title>`, the
  # heading `decisions_list` reads as an entry, through the put's own numbering (`decisions_append`), the title the
  # newest put's and none when the decision was never put, the who the project's git user name; then it settles the
  # register against the ledger, which closes `decide:D<n>`. A double quote in the reply is written as a single one: the
  # parser ends the reply at the next double quote. 0 ruled, printing `ruled: D<n> · "<reply>" · <title>`; 1 refused,
  # nothing written (a number that is not D<n>, a reply empty or of more than one line, a ledger that is a symlink, no
  # git user name); 3 refused, nothing written, the decision's last round already closed by a ruling or a withdrawal.
  decisions_rule() {  # <plan> <root> <D<n>> <reply>
    local plan="$1" root="$2" d="$3" reply="$4" led who title st sq
    case "$d" in D[1-9]*) case "${d#D}" in *[!0-9]*) d="" ;; esac ;; *) d="" ;; esac
    if [ -z "$d" ]; then
      die "REFUSED — '$(clean "$3")' is not a decision's number: name it D<n>, as in D7; nothing is written."
      return 1
    fi
    case "$reply" in
      ''|*$'\n'*|*$'\r'*) die "REFUSED — the reply is the user's words on one line; nothing is written."; return 1 ;;
    esac
    sq="'"; reply="${reply//\"/$sq}"
    led="$(docs_root "$root")/record/$(proof_plan_slug "$plan")/design-ledger.md"
    if [ -L "$led" ]; then
      die "REFUSED — ${led#"$root"/} is a symlink; nothing is written."
      return 1
    fi
    st="$(decisions_rounds "$led" | awk -F'\t' -v d="$d" '$1 == d { print $3 }')"
    case "$st" in
      ruled|withdrawn)
        die "REFUSED — $d is already $st: $(decisions_list "$led" | awk -F' · ' -v d="$d" '$1 == d { l = $0 } END { print l }'); put it again to open a new round; nothing is written."
        return 3 ;;
    esac
    who="$(git -C "$root" config user.name 2>/dev/null)"
    case "$who" in
      ''|*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*|*'('*|*')'*)
        die "REFUSED — the project has no usable git user name (git config user.name) to record as the one who ruled; nothing is written."
        return 1 ;;
    esac
    title="$(decisions_list "$led" puts | awk -F' · ' -v d="$d" '$1 == d && $2 == "put" {
      t = $0; for (i = 0; i < 3; i++) t = substr(t, index(t, " · ") + length(" · ")) } END { print t }')"
    decisions_append "$plan" "$led" "$root" "$d ruled \"$reply\" ($who $(decisions_clock))${title:+: $title}" || return 1
    REPO_REAL="$root" decisions_settle "$plan" "$led"
    printf 'ruled: %s · "%s" · %s\n' "$d" "$reply" "${title:-(untitled)}"
    return 0
  }

  # THE REGISTER (wave-38 T13; D24, AC-3.4). Read-only. `decisions` is the bound run's ledger through `decisions_list`;
  # `--all` is every run's under the docs root, keyed by wave, with the ADRs (`decisions_all`). Exit 1 in one line
  # naming the path when the run's ledger is absent; 2 when there is no run to read. `decisions put` and `decisions rule`
  # are its writers, each one entry (`decisions_append`).
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
    decisions_settle "$DC_PLAN" "$DC_LEDGER"
    [ -z "${DC_PUT:-}" ] || decisions_put "$DC_PLAN" "$DC_LEDGER" "$DC_PUT" "${DC_TITLE:-}"
    if [ -n "${DC_RULE:-}" ]; then
      decisions_rule "$DC_PLAN" "$REPO_REAL" "$DC_RULE" "${DC_REPLY:-}" && exit 0
      exit 1
    fi
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
  # step file. A file whose resume point says the run closed resumes nothing and says so, and a file that names no
  # plan, written with no run bound, binds nothing and prints its Next. The arm comes before the CronCreate here, as
  # at engagement (hooks/engage.sh arms at the marker's write): the stamp says the session asked for its Patrol.
  # Refusals name the fix and change nothing: no file or no kind line (2), a plan that is not there or a session that
  # cannot be engaged (1); a sub-verb's refusal stops the ritual with that verb's code.
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
    RS_L2="$(handoff_line "$RS_FILE" "resume point")"
    case "$RS_L2" in
      'resume point: NONE — DELIVERED'*)
        say "resume — '$RS_SHOWN' is the closed form: the run is delivered, so there is nothing to resume; nothing was bound, armed or adopted."
        printf '%s\n' "$RS_L2"
        for RS_K in plan branch "working branch" continuation; do handoff_line "$RS_FILE" "$RS_K"; done
        exit 0 ;;
      # A PARKED RUN IS CLOSED, AND ITS WORK IS LEFT (wave-38 T37; T15's note to T13). close-out performed its tail
      # without the merge and disarmed its Patrol, so nothing is bound or armed; the recap says where the work waits.
      'resume point: PARKED on '*)
        say "resume — '$RS_SHOWN' is the closed form, and the run is parked: its work is kept on its branch, not merged; the plan's Wake Note says what it waits on. Nothing was bound, armed or adopted."
        printf '%s\n' "$RS_L2"
        for RS_K in plan branch "working branch" continuation; do handoff_line "$RS_FILE" "$RS_K"; done
        exit 0 ;;
    esac
    RS_PLAN_REL="$(handoff_line "$RS_FILE" plan)"; RS_PLAN_REL="${RS_PLAN_REL#plan: }"
    # A DOCUMENT WRITTEN WITH NO RUN names no plan: there is nothing to bind, arm or adopt, and the document is the
    # whole of what the next session needs. Its Next section is printed, the first command first.
    if [ -z "$RS_PLAN_REL" ]; then
      say "resume — '$RS_SHOWN' was written with no run bound: nothing to bind, arm or adopt. Read it whole, then do Next 1:"
      awk '$0 == "Next" { f = 1; next } f && $0 == "" { exit } f { print }' "$RS_FILE"
      exit 0
    fi
    case "$RS_PLAN_REL" in /*) RS_PLAN="$RS_PLAN_REL" ;; *) RS_PLAN="$REPO_REAL/$RS_PLAN_REL" ;; esac
    if [ ! -f "$RS_PLAN" ] || [ -L "$RS_PLAN" ]; then
      die "REFUSED — the plan '$RS_SHOWN' names is missing: $RS_PLAN. Check out the branch that holds it, or bind the run by hand (bash ${HOOK_DIR}/session-poker.sh bind <plan>). Nothing was bound or armed."
      exit 1
    fi
    SESSION_ID="$(session_id 2>/dev/null)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty); a resume binds and arms ONE session."
      exit 3
    fi
    if ! { declare -F proof_plan_slug >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_plan_slug >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; nothing was bound or armed."
      exit 2
    fi
    # THE TERMINAL GETS WHAT A PERSON READS; THE RECAP FILE GETS THE REST. From here every line the ritual prints, the
    # sub-verbs' own included (bind, arm, adopt's verdicts, the tick's rows), goes to one file in the run's record,
    # rewritten each resume; the terminal gets about a dozen lines at the end and that file's path. A refusal is
    # still said on stderr, naming the file that holds the lines before it.
    RS_RECAP="$RS_DOCS/record/$(proof_plan_slug "$RS_PLAN")/resume-recap.md"
    RS_RECAP_REL="${RS_RECAP#"$REPO_REAL"/}"
    if ! mkdir -p "${RS_RECAP%/*}" 2>/dev/null || [ -L "$RS_RECAP" ] || ! : > "$RS_RECAP" 2>/dev/null; then
      die "REFUSED — the recap file cannot be written at $RS_RECAP_REL; nothing was bound or armed."
      exit 2
    fi
    exec 3>&1 >> "$RS_RECAP"
    rs_sub() { ( cd "$REPO_REAL" && CLAUDE_CODE_SESSION_ID="$SESSION_ID" "${BASH:-bash}" "$HOOK_DIR/session-poker.sh" "$@" ) 2>&1; }
    rs_step() {  # <codes it may exit with, comma-joined> <verb> [args] -> runs it; any other code stops the ritual with it
      local ok="$1" rc=0; shift
      rs_sub "$@" || rc=$?
      case ",$ok," in *",$rc,"*) return 0 ;; esac
      die "resume stopped at $1 (exit $rc): its lines are in $RS_RECAP_REL; the steps after it did not run."
      tail -n 3 "$RS_RECAP" >&2
      exit "$rc"
    }
    say "resume — $RS_SHOWN ($(handoff_line "$RS_FILE" written | sed 's/^written: //')): engage, bind, arm and adopt, then the task list, the recap, the step file, the patrol and the tick"
    # TYPING THE RESUME IS THE CONSENT. A session the slash command's hook did not engage is engaged here, through the
    # one verb that does it (hooks/engage.sh --root), before the binding; an engaged session is left as it is.
    RS_ENGAGED=already
    if ! engaged_session "$REPO_REAL" "$SESSION_ID"; then
      ( cd "$REPO_REAL" && CLAUDE_CODE_SESSION_ID="$SESSION_ID" "${BASH:-bash}" "$HOOK_DIR/engage.sh" --root "$REPO_REAL" ) 2>&1
      if ! engaged_session "$REPO_REAL" "$SESSION_ID"; then
        die "REFUSED — this session could not be engaged: hooks/engage.sh --root $REPO_REAL left no marker (its lines are in $RS_RECAP_REL). Nothing was bound or armed."
        exit 1
      fi
      RS_ENGAGED=now
    fi
    # THE PATROL IS THE SCALE'S CELL (lib/scale.sh): a scale whose profile has none, the task row, is never armed here,
    # and a stamp an unbound engagement armed before this binding is removed. A plan with no `scale:` arms as before.
    RS_PATROL=yes
    { declare -F scale_cell >/dev/null 2>&1 || { [ -r "$BIONIC_LIB/scale.sh" ] && . "$BIONIC_LIB/scale.sh"; }; } >/dev/null 2>&1
    if declare -F scale_cell >/dev/null 2>&1 \
       && [ "$(scale_cell "$(plan_frontmatter_get "$RS_PLAN" scale 2>/dev/null)" patrol 2>/dev/null)" = no ]; then
      RS_PATROL=no
    fi
    rs_step 0 bind "$RS_PLAN"
    [ "$RS_PATROL" = no ] || rs_step 0 arm
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
    # the sheet's own reader of the open decisions: a decision put and not ruled is open here as there, and owed once
    # whether or not a row's approval read opened it too
    RS_PAGES="$(pages_open "$RS_PLAN" "$RS_LEDGER")"
    RS_OWED="$(printf '%s\n' "$RS_OWED" | pages_owed "$RS_PAGES")"
    RS_OPEN="$(printf '%s\n' "$RS_OWED" | awk -F'\t' 'NF && $1 != "" { k = $1; r = $4; sub(/^poker: /, "", r); if (r == "") r = $3
      if (k ~ /^decide:D[0-9]+$/ && $3 == "reply to " substr(k, 8)) { k = substr(k, 8); sub(/^D[0-9]+ · /, "", r) }
      print "open: " k " — " r }')"
    if [ -n "$RS_OPEN" ]; then printf '%s\n' "$RS_OPEN"; else printf 'open: none — no decision is open\n'; fi
    # the run's status line and each open ask with what it holds, the sheet's own facts (sitrep_gather)
    sitrep_gather "$RS_PLAN" "$(cd "$(project_root "${RS_PLAN%/*}")" 2>/dev/null && pwd -P)" line 2>/dev/null
    printf 'run: %s\n' "$(sitrep_status)"
    RS_ASKW="$(sitrep_ask_words)"
    if [ -n "$RS_ASKW" ]; then printf '%s\n' "$RS_ASKW" | sed 's/^/ask: /'; else printf 'ask: none — nothing holds on you\n'; fi
    RS_OWN="$(printf '%s\n' "$RS_OPEN" | awk '{ k = $2 } k ~ /^(approve|waive|finding|gate):/ { sub(/^open: /, "owned-by-user: "); print }')"
    RS_APPR="$(units_waiting "$RS_PLAN" "$(fill_step_token "$RS_PLAN" 2>/dev/null)" 2>/dev/null | awk -F'\t' -v have="$(printf '%s\n' "$RS_OWED" | cut -f1 | tr '\n' ' ')" '
      { r = $2; sub(/^live:/, "", r); if (r !~ /^approval:[A-Za-z0-9][A-Za-z0-9._-]*$/) next
        nmv = substr(r, 10); if (index(" " have, " approve:" nmv " ") || index(" " have, " decide:" nmv " ")) next
        if (!(nmv in ids)) { ord[++n] = nmv; ids[nmv] = $1 } else if (index(", " ids[nmv] ", ", ", " $1 ", ") == 0) ids[nmv] = ids[nmv] ", " $1 }
      END { for (i = 1; i <= n; i++) print "owned-by-user: approval:" ord[i] " — " ids[ord[i]] " wait on it; record it: approve " ord[i] " '"'"'<the user'"'"'s words>'"'"'" }')"
    RS_OWN="$(printf '%s\n%s\n' "$RS_OWN" "$RS_APPR" | awk 'NF')"
    if [ -n "$RS_OWN" ]; then printf '%s\n' "$RS_OWN"; else printf 'owned-by-user: none — nothing waits on you\n'; fi
    RS_BR="$(handoff_line "$RS_FILE" "working branch")"
    [ -n "$RS_BR" ] || RS_BR="$(handoff_line "$RS_FILE" branch)"
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
    if [ "$RS_PATROL" = no ]; then
      RS_GONE=""
      if [ -f "$(patrol_stamp_file "$SESSION_ID" 2>/dev/null)" ]; then
        rs_sub disarm >/dev/null 2>&1 && RS_GONE="; the stamp an earlier arm left is removed"
      fi
      printf 'patrol-interval: none — a task-scale run has no Patrol, so no job is made%s\n' "$RS_GONE"
    else
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
    fi
    if [ "$RS_PATROL" = yes ]; then
      RS_RC=0
      rs_sub tick || RS_RC=$?
      case "$RS_RC" in
        0|1) : ;;
        *) die "resume stopped at tick (exit $RS_RC): its lines are in $RS_RECAP_REL."; exit "$RS_RC" ;;
      esac
      say "resume — done: bound, armed, adopted, ticked. Yours now: rebuild the task list from the task-list: lines (TaskList first), read the step-file:, and create the Patrol job from the patrol: line."
    else
      say "resume — done: bound and adopted; a task-scale run has no Patrol, so nothing ticks. Yours now: rebuild the task list from the task-list: lines (TaskList first) and read the step-file:."
    fi
    exec 1>&3 3>&-
    # THE TERMINAL: bound (and engaged, when it was not), the step, the agents still open with what each does and for
    # how long, what landed since the handoff was written, the one thing owed now, the Patrol, and the recap's path.
    RS_NOW="$(now_epoch)"
    if [ "$RS_ENGAGED" = now ]; then say "resume — engaged this session and bound it to $RS_PLAN_REL"
    else say "resume — bound this session to $RS_PLAN_REL"; fi
    printf 'step: %s\n' "$(awk -v cur="$RS_CURN" 'BEGIN { split("Configure Scope Design Plan Implement Verify Review Document Integrate Close-out", nm, " ")
      if (cur == "") print "none named"; else print cur " " nm[cur + 1] }')"
    RS_RF="$REPO_REAL/.bionic/tmp/roster-$SESSION_ID.state"
    RS_UROWS="$(units_rows "$RS_PLAN" 2>/dev/null)"
    RS_AG=""
    while IFS= read -r RS_NAME; do
      [ -n "$RS_NAME" ] || continue
      RS_ROW="$(awk -v k="|name=$RS_NAME|" 'index($0 "|", k) { l = $0 } END { print l }' "$RS_RF" 2>/dev/null)"
      RS_WHAT="$(printf '%s\n' "$RS_UROWS" | awk -F'\t' -v n="$RS_NAME" "$_ROW_SHORT_AWK"'$5 == n { print $1 " " row_short($4); exit }')"
      [ -n "$RS_WHAT" ] || RS_WHAT="$(line_field "$RS_ROW" subagent_type)"
      RS_E="$(iso_epoch "$(line_field "$RS_ROW" launched_at)")"
      RS_FOR="for an unrecorded time"
      [ -z "$RS_E" ] || RS_FOR="for $(sitrep_dur $(( (RS_NOW - RS_E) / 60 )))"
      RS_AG="${RS_AG:+$RS_AG
}  - $(clean "$RS_NAME") · $(clean "${RS_WHAT:-agent}") · $RS_FOR"
    done <<< "$(roster_open_names "$RS_RF" "$REPO_REAL/.bionic/tmp/sweeper-$SESSION_ID.state" "$SESSION_ID")"
    if [ -n "$RS_AG" ]; then printf 'running (%s):\n%s\n' "$(printf '%s\n' "$RS_AG" | grep -c .)" "$RS_AG"
    else printf 'running: none\n'; fi
    RS_AT="$(handoff_line "$RS_FILE" instant)"; RS_AT="${RS_AT#instant: }"
    [ -n "$RS_AT" ] || { RS_AT="$(handoff_line "$RS_FILE" written)"; RS_AT="${RS_AT#written: }"; }
    RS_LANDED="$(awk -v at="$RS_AT" '
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { s = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      s && /^- T[0-9]+:/ && match($0, /landed [0-9a-f]+ [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:]+Z/) {
        split(substr($0, RSTART, RLENGTH), f, " "); id = $2; sub(/:$/, "", id)
        if (at == "" || f[3] > at) out = out (out == "" ? "" : ", ") id }
      END { print out }' "$RS_PLAN")"
    printf 'landed since the handoff: %s\n' "${RS_LANDED:-none}"
    RS_FIRST="$(printf '%s\n' "$RS_OWN" | awk 'NF { sub(/^owned-by-user: /, ""); print; exit }')"
    [ -n "$RS_FIRST" ] || RS_FIRST="$(printf '%s\n' "$RS_OPEN" | awk 'NF { sub(/^open: /, ""); print; exit }')"
    printf 'owed now: %s\n' "${RS_FIRST:-nothing waits on you}"
    if [ "$RS_PATROL" = yes ]; then printf 'patrol: armed — create its job from the patrol: line in the recap\n'
    else printf 'patrol: none — a task-scale run has no Patrol\n'; fi
    printf 'recap: %s — the task list, the rulings and open decisions, the step file, the Patrol job and the tick\n' "$RS_RECAP_REL"
    exit 0
  }

  # THE SITUATION REPORT. Its reasoning is above the verbs, beside `sitrep_gather`: the sheet, or with --line the
  # Patrol's status, or with `card` the card payload/scripts/card.sh draws from the judgment on stdin and the sheet
  # `sitrep` last saved for the plan (THE SHEET THE JUDGMENT IS WRITTEN FROM), its asks read fresh.
  # The plan is resolved as landing-report resolves its own: a named one first, else the session's bound run. Before
  # the sheet or the card is gathered, the register is settled against the ledger (`decisions_settle`), so a decision
  # ruled there is never shown as owed and never left open for the next reader. The card prints only when card.sh
  # draws it (exit 0); a card it refuses prints nothing, card.sh's reasons reach stderr, and the verb exits 1.
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
    REPO_REAL="$SR_ROOT" decisions_settle "$SR_PLAN" "$(docs_root "$SR_ROOT")/record/$(proof_plan_slug "$SR_PLAN")/design-ledger.md"
    if [ "$SR_LINE" = yes ]; then
      sitrep_gather "$SR_PLAN" "$SR_ROOT" line
      sitrep_status
      exit 0
    fi
    if [ "$SR_CARD" = no ]; then
      sitrep_gather "$SR_PLAN" "$SR_ROOT" sheet
      sitrep_save "$SR_ROOT" "$SR_PLAN"
      exit 0
    fi
    SR_AGE="$(sitrep_saved_age "$SR_ROOT" "$SR_PLAN")"
    if [ "$SR_AGE" = missing ]; then
      die "REFUSED — the sheet you wrote from is missing: run sitrep again."
      exit 1
    elif [ "$SR_AGE" -ge "$SITREP_SAVED_MAX" ]; then
      die "REFUSED — the sheet you wrote from is $((SR_AGE / 60)) min old: run sitrep again."
      exit 1
    fi
    SR_SHEET="$(mktemp "${TMPDIR:-/tmp}/bionic-sheet.XXXXXX")" || { die "REFUSED — no temporary file for the sheet; no card is drawn."; exit 2; }
    # The saved sheet is the facts; only its asks are read again, from the register alone, so a card is never the cost
    # of a second gather. The goals a reached theme drops asks for are the saved sheet's own met goals.
    SR_SAVED="$(sitrep_saved "$SR_ROOT" "$SR_PLAN")"
    SR_GOALS_MET="$(plan_goal_sheet "$SR_SAVED" | awk -F'\t' -v met="$(plan_goal_status reached)" '$3 == met { print "reached\t" $2 }')"
    SG_ASKS="$(sitrep_asks "$SR_PLAN" "$SR_ROOT" "$(units_rows "$SR_PLAN" 2>/dev/null)" "$SR_GOALS_MET" "$(sitrep_now)")"
    { awk 'index($0, "ask: ") != 1' "$SR_SAVED"; sitrep_ask_lines; } > "$SR_SHEET"
    SR_RC=0
    SR_CARD_TEXT="$("${BASH:-bash}" "$(cd "$BIONIC_LIB/.." 2>/dev/null && pwd -P)/card.sh" sitrep "$SR_SHEET")" || SR_RC=$?
    rm -f "$SR_SHEET"
    case "$SR_RC" in
      0) printf '%s\n' "$SR_CARD_TEXT"; exit 0 ;;
      1) die "REFUSED — the sitrep card failed its check, so nothing of it is shown: write the judgment again for the reasons above."; exit 1 ;;
      *) die "REFUSED — card.sh sitrep could not draw the card (exit $SR_RC); nothing is shown."; exit 2 ;;
    esac
  }
