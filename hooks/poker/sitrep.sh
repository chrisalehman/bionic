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
# `handoff_compose` read them; `handoff_render <composed> <section>` prints the section's lines as sitrep_fold takes
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
# under a Δ (the Step-1 rulings folded in). The verbs are ruled, re-ruled, amended, amended again, ratified, final and
# withdrawn; the qualifier is one word between the number and the verb; the heading form `D<n> ruled: <title> (<who>
# <date>)` has no reply; a tail after the parenthesis that is not `: <title>` is the title. A `put (…)` proposal, a
# line of any other shape, a body line and a fenced example are not entries, so a ledger written before D24 reads as
# having none. ONE PARSER: `decisions` prints it and the resume recap's settled: lines are
# it, prefixed. The who is the parenthesis's words before its first date; a ruling with no `: <title>` after the
# parenthesis is `(untitled)`. With `puts`, a put is an entry too, `D<n> · put · <who> <date> · <title>`: the line
# `decisions put` writes, read only by the rounds count, never by the register.
decisions_list() {  # <ledger> [puts] -> one line per entry: D<n> · "<reply>" · <who> <date> · <title>, in the ledger's order
  awk -v puts="${2:-}" '
    function lead_verb(s,   i, n, vs, c) {  # the verb s opens with, followed by a space or a colon; "" when none
      n = split("amended again|amended|re-ruled|ruled|ratified|final|withdrawn" (puts == "puts" ? "|put" : ""), vs, "|")
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

# THE OPEN DECISIONS AND THE LANDED READINGS, ONE READER FOR BOTH PAGES. The sitrep and the resume recap each show
# every decision put to the user and not yet ruled and every reading that landed with its result, and both read them
# here, so the two pages cannot disagree on what is open.
# pages_open <plan> <ledger> ->
#   `D<TAB>D<n><TAB><title><TAB><wait line>` per open decision, in order of first entry: open is `decisions_rounds`'
#     word, the title the newest put's, the wait line the first line under that put's heading (what `decisions put`
#     wrote there), empty when it has none;
#   `R<TAB><question><TAB><scope><TAB><result><TAB><at>` per reading line of the plan's unfenced ## SDLC State
#     (`proof_fields`: kind review with a question and a record), in the plan's order, a repeated record and result once.
pages_open() {
  local plan="$1" led="$2" open
  if [ -f "$led" ] && [ ! -L "$led" ]; then
    open="$(decisions_rounds "$led" | awk -F'\t' '$3 == "open" { printf "%s ", $1 }')"
    if [ -n "$open" ]; then
      { decisions_list "$led" puts | awk -F' · ' '$2 == "put" { t = $4; for (i = 5; i <= NF; i++) t = t " · " $i; print "T\t" $1 "\t" t }'
        awk '{ sub(/\r$/, "") }
          /^[ \t]*```/ { f = !f; next }
          f { next }
          index($0, "## ") == 1 { d = ""
            if (match($0, /^## Δ[0-9]+ — D[0-9]+ put /)) { d = $0; sub(/^## Δ[0-9]+ — /, "", d); sub(/ .*$/, "", d); print "W\t" d "\t" }
            next }
          d != "" && NF { print "W\t" d "\t" $0; d = "" }' "$led" 2>/dev/null
      } | awk -F'\t' -v open="$open" '
        $1 == "T" { t[$2] = $3; next }
        $1 == "W" { w[$2] = $3 }
        END { n = split(open, a, " "); for (i = 1; i <= n; i++) printf "D\t%s\t%s\t%s\n", a[i], t[a[i]], w[a[i]] }'
    fi
  fi
  { [ -f "$plan" ] && [ ! -L "$plan" ] && declare -F proof_awk >/dev/null 2>&1; } || return 0
  awk "$(proof_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    !insdlc { next }
    proof_fields($0) && PROOF_KIND == "review" && PROOF_QUESTION != "" && PROOF_EVIDENCE != "" && !((PROOF_EVIDENCE SUBSEP PROOF_RESULT) in seen) {
      seen[PROOF_EVIDENCE SUBSEP PROOF_RESULT] = 1; at = ""
      if (match($0, /[ \t]at=[^ \t]+/)) at = substr($0, RSTART + 4, RLENGTH - 4)
      printf "R\t%s\t%s\t%s\t%s\n", PROOF_QUESTION, PROOF_SCOPE, PROOF_RESULT, at
    }' "$plan" 2>/dev/null
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

# pages_readings <pages_open output> <now epoch> -> `<mark><TAB><question>[ on the whole| on a piece]: <passed|flagged|
# failed> at <clock>` per landed reading. The mark holds the result against a pass: within, near for a flag, over for a
# fail, not measurable for any other word.
pages_readings() {
  local l q sc res at mark word where e when tab=$'\t'
  while IFS= read -r l; do
    case "$l" in "R$tab"*) ;; *) continue ;; esac
    l="${l#R$tab}"; q="${l%%$tab*}"; l="${l#*$tab}"; sc="${l%%$tab*}"; l="${l#*$tab}"; res="${l%%$tab*}"; at="${l#*$tab}"
    case "$res" in
      pass) mark="$SITREP_MARK_WITHIN"; word=passed ;;
      flag) mark="$SITREP_MARK_NEAR"; word=flagged ;;
      fail) mark="$SITREP_MARK_OVER"; word=failed ;;
      *) mark="$SITREP_MARK_NONE"; word="no result" ;;
    esac
    case "$sc" in whole) where=" on the whole" ;; piece) where=" on a piece" ;; *) where="" ;; esac
    e="$(iso_epoch "$at" 2>/dev/null)"; when=""
    case "$e" in ''|*[!0-9]*) ;; *) when=" at $(sitrep_clock "$e" "$2")" ;; esac
    printf '%s\t%s%s: %s%s\n' "$mark" "$q" "$where" "$word" "$when"
  done <<PAGES_READINGS
$1
PAGES_READINGS
}

# sitrep_decisions <ledger> <record dir> -> the decisions indicator line. Each release approval page the run put is a
# round of the release approval card, ruled once the newest is replied; a page written under the card's old stem
# (`$RR_OLD_VERB`, set in session-poker.sh) counts as a round too. The mark is the most rounds any one decision took:
# one within the bar, two near it, three or more over it; with nothing put or ruled, the no-record form.
sitrep_decisions() {
  local f rr=""
  for f in "$2"/release-approval-*.md "$2/$RR_OLD_VERB"-*.md; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    rr="$rr$(awk -v OLD="$RR_OLD_VERB/v1|plan=" '
      (index($0, "release-approval/v1|plan=") == 1 || index($0, OLD) == 1) && match($0, /\|at=[^|]*/) { a = substr($0, RSTART + 4, RLENGTH - 4) }
      index($0, "replied: ") == 1 { y = 1 }
      END { printf "%s\t%s\n", a, y ? "ruled" : "open" }' "$f" 2>/dev/null)
"
  done
  { [ -f "$1" ] && [ ! -L "$1" ] && decisions_rounds "$1"
    [ -z "$rr" ] || printf '%s' "$rr" | awk -F'\t' 'NF { n++; if ($1 >= a) { a = $1; s = $2 } } END { if (n) printf "the release approval card\t%d\t%s\n", n, s }'
  } | awk -F'\t' -v W="$SITREP_MARK_WITHIN" -v R="$SITREP_MARK_NEAR" -v O="$SITREP_MARK_OVER" -v N="$SITREP_MARK_NONE" '
    function word(k,   w) { split("one two three four five six seven eight nine ten", w, " "); return (k >= 1 && k <= 10) ? w[k] : k }
    function list(a, m,   i, s, c) {  # the first six, then how many more
      c = (m > 6) ? 6 : m
      for (i = 1; i <= c; i++) s = s ((i == 1) ? "" : ((i == c && m == c) ? " and " : ", ")) a[i]
      return (m > c) ? s " and " (m - c) " more" : s }
    NF >= 3 { n++; id[n] = $1; r[n] = $2 + 0; st[n] = $3; t += $2; if ($3 == "ruled") ok++; if ($2 + 0 > mx) mx = $2 + 0 }
    END {
      if (n == 0) { printf "3\t%s decisions — rounds not counted yet\n", N; exit }
      for (k = 1; k <= mx; k++) {
        m = 0; for (i = 1; i <= n; i++) if (r[i] == k) g[++m] = id[i]
        if (m) gs = gs (gs == "" ? "" : ", ") list(g, m) " " word(k) (m > 1 ? " each" : "")
      }
      for (k = 1; k <= 2; k++) {
        m = 0; for (i = 1; i <= n; i++) if (st[i] == (k == 1 ? "open" : "withdrawn")) g[++m] = id[i]
        if (m) gs = gs "; " list(g, m) (k == 1 ? " open" : " withdrawn")
      }
      printf "3\t%s decisions — %d ruled in %d round%s; %s\n", (mx <= 1) ? W : ((mx == 2) ? R : O), ok, t, (t == 1) ? "" : "s", gs
    }'
}

# sitrep_chain <plan> <units_rows output> -> `<ids, comma-joined><TAB><minutes>`: the longest chain of open tasks,
# `units_chain`'s over `units_edges`, as wide as the plan has tasks
sitrep_chain() {
  { printf '%s\n' "$2" | awk -F'\t' '{ s = tolower($10); gsub(/[ \t]/, "", s) } s == "pending" || s == "active" {
      m = 0; if (match($7, /^[0-9]+/)) m = substr($7, RSTART, RLENGTH); printf "N\t%s\t%d\n", $1, m }'
    units_edges "$1" 2>/dev/null | awk -F'\t' 'NF >= 2 { printf "E\t%s\t%s\n", $1, $2 }'
  } | units_chain "$(printf '%s\n' "$2" | grep -c . | awk '{ print ($1 > 0) ? $1 : 1 }')" 2>/dev/null \
    | awk -F'\t' '$1 == "chain" { print $2 "\t" $3; exit }'
}

# THE WAIT LINE: what changes if a decision is answered in an hour rather than now. The tasks that wait on it are the
# pending ones whose reads name it as an approval, `approval:D<n>`; one of them on the longest open chain moves the
# predicted close an hour, and off it they start an hour later while the close holds.
decision_wait() {  # <plan> <D<n>> -> one sentence
  local rows chain cids
  rows="$(units_rows "$1" 2>/dev/null)"
  if [ -z "$rows" ]; then printf 'Answered now or in an hour, no task moves: the plan has no task yet.\n'; return 0; fi
  chain="$(sitrep_chain "$1" "$rows")"; cids="${chain%%$'\t'*}"
  printf '%s\n' "$rows" | awk -F'\t' -v k="approval:$2" -v c=",$cids," '
    function list(a, m,   i, s) { for (i = 1; i <= m; i++) s = s ((i == 1) ? "" : ((i == m) ? " and " : ", ")) a[i]; return s }
    { s = tolower($10); gsub(/[ \t]/, "", s) } s != "pending" { next }
    { n = split($13, t, ","); for (i = 1; i <= n; i++) { x = t[i]; gsub(/^[ \t]+|[ \t]+$/, "", x); sub(/^live:/, "", x)
        if (x == k) { if (index(c, "," $1 ",")) on[++a] = $1; else off[++b] = $1; break } } }
    END {
      if (a) { printf "Answered in an hour rather than now, the predicted close moves an hour later: %s %s on the longest chain and %s on it", list(on, a), (a > 1) ? "are" : "is", (a > 1) ? "wait" : "waits"
               if (b) printf "; %s also %s on it", list(off, b), (b > 1) ? "wait" : "waits"; printf ".\n" }
      else if (b) printf "Answered in an hour rather than now, %s %s an hour later and the predicted close holds: %s off the longest chain.\n", list(off, b), (b > 1) ? "start" : "starts", (b > 1) ? "they are" : "it is"
      else printf "Answered now or in an hour, nothing moves: no task waits on it.\n" }'
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
#   human-wait      the release approval records (release-approval-*.md beside the run's records, and the pages an
#                   older run wrote under the old stem or as final-card-*.md): each page's `at=` on its
#                   `release-approval/v1|plan=` (or the old tags')
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
  wait="$(for f in "$recdir"/release-approval-*.md "$recdir/$RR_OLD_VERB"-*.md "$recdir"/final-card-*.md; do [ -f "$f" ] && [ ! -L "$f" ] && printf '%s\n' "$f"; done | awk -v OLD="$RR_OLD_VERB/v1|plan=" "$_PATROL_ISO_AWK"'
    { file = $0; a = ""; r = ""
      while ((getline l < file) > 0) {
        if (index(l, "release-approval/v1|plan=") == 1 || index(l, OLD) == 1 || index(l, "final-card/v1|plan=") == 1) { n = split(l, p, "|"); for (i = 2; i <= n; i++) if (index(p[i], "at=") == 1) a = substr(p[i], 4) }
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
#   Sitrep · <project> <release> · <weekday> <H:MM AM/PM> · step <n> of 9[ · work at step <w> (<tasks>)] · <k> of <m>
#                      tasks done (<p>%), the clause when a landed or active task stands at a step past current:
#   Bottom line        four bullets: what you owe, what is next, what is done, when it closes
#   Task list          <glyph> <step>: <name> for steps 0 to 3, and <glyph> <step>/<task>: <name> for every task in
#                      execution order, ONE line each and never continued: the name is the task's cell up to its first
#                      " (", ": ", ". " or " · ", clipped at a word with "…" when the line would pass 92 columns; a
#                      time in parentheses or a short state after " — " (`building`, `waits on T1 +8`, `held`, `red`)
#                      always prints whole
#   Score: <grade> (graded <time>), or Score: not graded yet
#                      <mark> schedule, correctness, waste, decisions, goals — what each measured, in words; then
#                      `<mark> reading — …` per landed reading with its result (`pages_readings`); then
#                      `- <rationale>` when graded
#   Blocked on you     one bullet per open approve:, waive:, finding:, gate: or decide: item of the plan's run, one sentence each,
#                      every decision put and not ruled among them with its wait line (`pages_owed`), each once
#
# The close is stated once, on the Bottom line. `--line` prints only `<schedule><correctness><waste marks> · owed: <n> ·
# <the close>`, and `--basis` prints the close's line and its arithmetic: the work left, the chain, the width, the
# pace and whose it is, the floor and the likely instants.
#
# EVERY FACT IS ANOTHER READER'S, CALLED: the tasks and sizes are `units_rows`', the longest open chain
# `units_chain`'s over `units_edges`, the landings, runs and the median ready→landed `landing_report`'s, the idle
# minutes `fill-report`'s own line, the open items `owed_list_plan`'s (the sessions bound to the plan, never the
# caller's), the admitted count `gate_state`'s, the findings `proof_findings` at `proof_finding_rating` less
# `proof_fixed`, the dispatch instants `launch_sync_ledger`'s. What no reader computes is computed here, once: the
# pace, the marks, a red not yet answered by a green, the close.
#
# THE MARKS ENCODE DEVIATION FROM A TOLERANCE, never a work state: a measurement held against its bar is ✅ within
# it, ➖ near it, ✖️ over it, or ❔ not measurable, and its line says the bar in words. The decisions line is
# `sitrep_decisions`', the goals line `sitrep_goals`'.
#
# THE CLOSE IS A FLOOR OR A FORECAST, NEVER NOW. L = max(the longest open chain, all open work ÷ the admitted count) in
# the plan's own minutes, so admitting more can shorten the work's share and never one chain. The floor is now + L at
# 1×; the likely close is now + L × the pace, printed only when it falls after now. The pace is the median of a
# landing's dispatched-to-landed minutes over its planned minutes, this run's, else the newest delivered run's at the
# same scale on the same project, named; with neither the floor stands alone. The queue's ready-to-landed time is a
# wait at the gate and feeds nothing. A plan not approved at Step 3 prints the no-forecast sentence; a delivered one
# prints its delivery and no close. No typed number feeds it: the plan's own `forecast:` grades the schedule mark.
#
# THE PLAN'S TABLE WORDS NEVER PRINT: no "rows", no status name, no cell value; a read prints in words.
#
# A value the record cannot compute prints `unverified` or its no-record sentence, and its mark is ❔. Local times
# are 12-hour on this machine's clock (`sitrep_clock`); a time on another local day than now's carries its date.
# Now is BIONIC_NOW_EPOCH when set, fill-report's seam.
# The four marks, from one place. ✖️ is U+2716 U+FE0F.
# Set in hooks/session-poker.sh, before any part loads: SITREP_MARK_WITHIN, SITREP_MARK_NEAR, SITREP_MARK_OVER,
# SITREP_MARK_NONE.

# _sitrep_cw_awk -> the awk source of `cw(s)`, a text's display columns, counted byte-wise so no locale decides it: a
# character is one column, a four-byte one two, the three-byte mark glyphs (✅ ⬜ ⛔ ❔ ➖ ✖) two, U+FE0F none. The one
# measure, read by the fold and by the Task list's clip alike, so a line the clip fits is a line the fold passes.
_sitrep_cw_awk() {
  printf '%s' '
    function cw(s,   t, n, w) {
      t = s; n = gsub(/[\200-\277]/, "", t); w = length(s) - n
      t = s; w -= gsub(/\357\270\217/, "", t)
      t = s; w += gsub(/[\360-\364]/, "", t)
      t = s; w += gsub(/\342\234\205|\342\254\234|\342\233\224|\342\235\224|\342\236\226|\342\234\226/, "", t)
      return w
    }'
}

# sitrep_fold -> stdin's `<continuation indent><TAB><text>` lines, each folded at 92 display columns: a wider text
# breaks at its last space that fits, every continuation opening on that many spaces. A word wider than the page
# prints whole. A Task list line is clipped to fit before it reaches the fold (`sitrep_task_lines`), so the fold
# passes it and never continues it.
sitrep_fold() {
  LC_ALL=C awk "$(_sitrep_cw_awk)"'
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

# _sitrep_name_awk -> the awk source of `task_name(cell)`: the task's cell up to the first of " (", ": ", ". " or " · ",
# trimmed, a closing "." dropped; a cell that opens on one of them keeps its whole trimmed text, so no task prints
# nameless. Index-based, so the cut is byte-exact under any locale.
_sitrep_name_awk() {
  printf '%s' '
    function task_name(t,   c, i, k, d, w) {
      d[1] = " ("; d[2] = ": "; d[3] = ". "; d[4] = " · "
      w = t; c = length(t) + 1
      for (k = 1; k <= 4; k++) { i = index(t, d[k]); if (i && i < c) c = i }
      t = substr(t, 1, c - 1); sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t); sub(/\.$/, "", t)
      if (t == "") { t = w; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t) }
      return t
    }'
}

# sitrep_task_name <cell> -> the task's name: the cell up to its first " (", ": ", ". " or " · ".
sitrep_task_name() { printf '%s\n' "$1" | LC_ALL=C awk "$(_sitrep_name_awk)"'{ print task_name($0) }'; }

# sitrep_task_lines -> stdin's `<glyph><TAB><label><TAB><cell><TAB><state>` rows as page lines, `5<TAB><glyph> <label>:
# <name> <state>`, each ONE line of at most 92 display columns. THE CLIP, before the fold: the glyph, the label and the
# state print whole, and only the name gives way. A name that does not fit ends at the last whole word that does,
# then "…" (a word wider than the room is cut inside the room, on a character boundary). A line never continues.
sitrep_task_lines() {
  LC_ALL=C awk -F'\t' "$(_sitrep_cw_awk)$(_sitrep_name_awk)"'
    {
      head = $1 " " $2 ": "; nm = task_name($3); tail = ($4 == "") ? "" : " " $4
      if (cw(head nm tail) > 92) {
        n = split(nm, wd, " "); out = ""
        for (j = 1; j <= n; j++) {
          c = (out == "") ? wd[j] : out " " wd[j]
          if (cw(head c "…" tail) > 92) break
          out = c
        }
        if (out == "") {
          L = length(wd[1])
          while (L > 0 && (cw(head substr(wd[1], 1, L) "…" tail) > 92 || substr(wd[1], L + 1, 1) ~ /[\200-\277]/)) L--
          out = substr(wd[1], 1, L)
        }
        sub(/[ ,;:(-]+$/, "", out); nm = out "…"
      }
      print "5\t" head nm tail
    }'
}

# sitrep_dur <minutes> -> `<h> h <m> min`, `<h> h` or `<m> min`, to the whole minute
sitrep_dur() {
  awk -v m="$1" 'BEGIN { m = int(m + 0.5); h = int(m / 60); r = m - h * 60
    if (h == 0) printf "%d min\n", r; else if (r == 0) printf "%d h\n", h; else printf "%d h %d min\n", h, r }'
}

# sitrep_count_word <n> -> one to ten in words, else the digits
sitrep_count_word() {
  case "$1" in 1) echo one ;; 2) echo two ;; 3) echo three ;; 4) echo four ;; 5) echo five ;; 6) echo six ;; 7) echo seven ;; 8) echo eight ;; 9) echo nine ;; 10) echo ten ;; *) echo "$1" ;; esac
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

sitrep_ratio_fmt() {  # <ratio> -> two places, trailing zeros dropped: 1.2, 1.37, 2; below 0.01, one significant digit: 0.001
  awk -v r="$1" 'BEGIN { s = (r > 0 && r < 0.01) ? sprintf("%.1g", r) : sprintf("%.2f", r); if (index(s, ".") && s !~ /e/) { sub(/0+$/, "", s); sub(/\.$/, "", s) }; print s }'
}

# sitrep_pace <plan> <root> -> `<landings><TAB><ratio>`: over the plan's queue landings whose dispatch ledger row
# carries a `dispatched` instant and whose task declares a size, the median of (landed − dispatched) in minutes over
# the declared minutes; nothing when no landing qualifies or the median is not a positive number. A row's landing
# is its earliest queue `published` at or after its dispatch. The queue's ready-to-landed time is a wait at the
# gate, not the work's own time, so it feeds nothing here.
sitrep_pace() {
  local rec
  rec="$(_wt_proofs_path "$2" "$1")"
  [ -f "$rec" ] && [ ! -L "$rec" ] || return 0
  { [ -n "${_LINE_FIELDS_AWK:-}" ] || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; }
  [ -n "${_LINE_FIELDS_AWK:-}" ] || return 0
  { launch_sync_ledger "$1" | awk -F'\037' '{ print "D\t" $1 "\t" $3 }'
    units_rows "$1" 2>/dev/null | awk -F'\t' '{ print "R\t" $1 "\t" $7 }'
    awk -F'|' "$_LINE_FIELDS_AWK"'line_ev() == "published" && line_kv("kind") == "queue" { print "P\t" line_kv("row") "\t" line_kv("at") }' "$rec"
  } | awk -F'\t' "$_PATROL_ISO_AWK"'
    function norm(s) { if (length(s) == 17 && substr(s, 17, 1) == "Z") return substr(s, 1, 16) ":00Z"; return s }
    $1 == "D" { e = iso2epoch(norm($3)); if (e >= 0) disp[$2] = e; next }
    $1 == "R" { if (match($3, /^[0-9]+/) && substr($3, RSTART, RLENGTH) + 0 > 0) size[$2] = substr($3, RSTART, RLENGTH) + 0; next }
    $1 == "P" { e = iso2epoch(norm($3)); if (e >= 0) { np++; pr[np] = $2; pe[np] = e } }
    END {
      for (i = 1; i <= np; i++) {
        r = pr[i]
        if (!(r in disp) || !(r in size) || pe[i] < disp[r]) continue
        if (!(r in land) || pe[i] < land[r]) land[r] = pe[i]
      }
      for (r in land) v[++k] = (land[r] - disp[r]) / 60 / size[r]
      if (k == 0) exit
      for (i = 2; i <= k; i++) { t = v[i]; for (j = i - 1; j >= 1 && v[j] > t; j--) v[j + 1] = v[j]; v[j + 1] = t }
      d = (k % 2) ? v[(k + 1) / 2] : (v[k / 2] + v[k / 2 + 1]) / 2
      if (!(d > 0)) exit
      printf "%d\t%.6f\n", k, d
    }'
}

# sitrep_bar -> the landing bar in minutes, lib/line.sh's LINE_LANDING_BAR (wave-39 T9; D12), the one constant the
# schedule line and the scorecard's target read; loaded as the stop-run record loads line.sh; nothing when unread.
sitrep_bar() {
  [ -n "${LINE_LANDING_BAR:-}" ] || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1
  case "${LINE_LANDING_BAR:-}" in ''|*[!0-9]*) return 0 ;; esac
  printf '%s\n' "$LINE_LANDING_BAR"
}

# sitrep_schedule <plan> <done> <total> <now epoch> <median one-file ready→landed | empty> -> `<mark><TAB><text>`, the
# schedule line after its mark. Two halves, each against a bar the run cannot set for itself:
#   the clock  tasks done in the time since the plan's `approved-by:` instant (the Step-3 approval) against the
#              tasks its frontmatter `forecast: <n>h|<n>m` needs by now, total × elapsed/forecast rounded, never
#              above total: done ≥ needed within, needed ≤ 1.25 × done near, else over; not graded with no
#              approval instant or no forecast.
#   the bar    the median one-file landing against LINE_LANDING_BAR: ≤ bar within, ≤ 1.25 × bar near, else
#              over; unmeasured before the first one-file landing. A landing of more files is not graded here.
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
    clock="$landed of $total tasks done in $(sitrep_dur "$em"); the $(sitrep_dur "$fc") forecast needs $k by now, $([ "$landed" -gt "$k" ] && echo ahead || { [ "$landed" -eq "$k" ] && echo on pace || echo behind; })"
  fi
  bar="$(sitrep_bar)"
  if [ -z "$med" ]; then bg=n; bt="no one-file landing yet against the ${bar:-unverified} min bar"
  elif [ -z "$bar" ]; then bg=n; bt="the median one-file landing takes $(sitrep_ratio_fmt "$med") min; the bar is unverified"
  else
    bg="$(awk -v m="$med" -v b="$bar" 'BEGIN { print (m <= b) ? "w" : ((m <= 1.25 * b) ? "a" : "o") }')"
    bt="the median one-file landing takes $(sitrep_ratio_fmt "$med") min, $([ "$bg" = w ] && echo within || echo over) the ${bar} min bar"
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
# <plan> that declares the same `scale:` as <plan> (its Step 9 line's `delivered:` instant, newest;
# `bind_delivered`'s test), measured by `sitrep_pace` over its own record; nothing when there is none, it measured
# no pace, or <plan> declares no scale. A run of another size is no measure of this one's pace.
sitrep_prev() {
  local root="$1" self f c at best="" bestat="" pace scale
  declare -F _run_candidates >/dev/null 2>&1 && declare -F bind_delivered >/dev/null 2>&1 || return 0
  scale="$(plan_frontmatter_get "$2" scale 2>/dev/null)"
  [ -n "$scale" ] || return 0
  self="$(_bind_resolve "$2" 2>/dev/null)" || self="$2"
  while IFS= read -r -d '' f; do
    c="$(_bind_resolve "$f" 2>/dev/null)" || continue
    [ "$c" != "$self" ] || continue
    at="$(awk '/^[[:space:]]*-?[[:space:]]*Step 9:.*delivered:/ && match($0, /delivered:[ \t]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:]+Z?/) {
                 s = substr($0, RSTART, RLENGTH); sub(/^delivered:[ \t]*/, "", s); print s; exit }' "$f" 2>/dev/null)"
    [ -n "$at" ] || continue
    [ "$(plan_frontmatter_get "$f" scale 2>/dev/null)" = "$scale" ] || continue
    bind_delivered "$root" "$c" || continue
    if [ -z "$bestat" ] || [[ "$at" > "$bestat" ]]; then best="$f"; bestat="$at"; fi
  done < <(_run_candidates "$(docs_root "$root")" 2>/dev/null)
  [ -n "$best" ] || return 0
  pace="$(sitrep_pace "$best" "$root")"
  [ -n "$pace" ] || return 0
  printf '%s\t%s\n' "$(proof_plan_slug "$best")" "${pace##*$'\t'}"
}

# sitrep_close <plan> <root> <now epoch> [<units_rows output>] -> the close, one tab-separated line, for every reader
# of it (the page, its basis, the schedule mark); nothing when no task is open. The fields, `-` where none:
#   1 floor     now + L minutes at 1×, rounded to the minute, and always after now: L is the larger of the longest
#               open chain and all open work over the admitted count, in the plan's own minutes
#   2 likely    now + L × the pace, rounded to the minute; `-` with no pace or when it falls at or before now. A pace
#               under 1× puts it before the floor, and it still prints: it is the estimate, the floor the plan's own
#   3 ratio     the pace: this run's (`sitrep_pace`), else the newest same-scale delivered run's (`sitrep_prev`)
#   4 whose     `this run`, or the lending run's short name, a wave slug's first two words
#   5 landings  how many of this run's landings the pace is the median of (`-` when borrowed)
#   6 work · 7 per · 8 larger   the open minutes, those over the admitted count, and L, each rounded
#   9 chain · 10 chain min · 11 admitted   the chain's ids comma-joined, its minutes, the gate's admitted count
# Admitting more can shorten the work's share and never one chain.
sitrep_close() {
  local plan="$1" root="$2" now="$3" rows="${4:-}" chain cids cmins work admitted width pace ratio="-" whose="-" n="-"
  [ -n "$rows" ] || rows="$(units_rows "$plan" 2>/dev/null)"
  chain="$(sitrep_chain "$plan" "$rows")"
  cids="${chain%%$'\t'*}"; cmins="${chain##*$'\t'}"
  [ -n "$cids" ] || return 0
  work="$(printf '%s\n' "$rows" | awk -F'\t' '{ s = tolower($10); gsub(/[ \t]/, "", s) } s == "pending" || s == "active" {
            if (match($7, /^[0-9]+/)) t += substr($7, RSTART, RLENGTH) } END { print t + 0 }')"
  admitted="$(gate_state 2>/dev/null | sed -n 's/.* admitted=\([0-9][0-9]*\) .*/\1/p')"
  case "$admitted" in ''|*[!0-9]*) admitted=0 ;; esac
  width="$admitted"; [ "$width" -gt 0 ] || width=1
  pace="$(sitrep_pace "$plan" "$root")"
  if [ -n "$pace" ]; then
    n="${pace%%$'\t'*}"; ratio="${pace##*$'\t'}"; whose="this run"
  else
    pace="$(sitrep_prev "$root" "$plan")"
    if [ -n "$pace" ]; then
      ratio="${pace##*$'\t'}"
      whose="$(printf '%s' "${pace%%$'\t'*}" | awk -F- '$1 == "wave" && NF >= 2 { print $1 "-" $2; next } { print }')"
    fi
  fi
  awk -v now="$now" -v c="$cmins" -v t="$work" -v w="$width" -v r="$ratio" 'BEGIN {
    p = t / w; l = (p > c) ? p : c
    f = int((now + l * 60) / 60 + 0.5) * 60; if (f <= now) f = (int(now / 60) + 1) * 60
    y = 0; if (r != "-" && r + 0 > 0) y = int((now + l * r * 60) / 60 + 0.5) * 60
    if (y > now) printf "%d\t%d\t", f, y; else printf "%d\t-\t", f }'
  printf '%s\t%s\t%s\t' "$ratio" "$whose" "$n"
  awk -v c="$cmins" -v t="$work" -v w="$width" 'BEGIN { p = t / w; l = (p > c) ? p : c; printf "%d\t%d\t%d\t", t, p + 0.5, l + 0.5 }'
  printf '%s\t%s\t%s\n' "$cids" "$cmins" "$admitted"
}

# sitrep_open_s12 <plan> <root> -> `<open S1 count> <open S2 count>` over the plan's registered readings: a
# finding `disposition` would print state=open (its effective priority fix, and no fix of it landed).
sitrep_open_s12() {
  local plan="$1" root="$2" docs fixed reads ev q h got num s r n1=0 n2=0
  declare -F proof_findings >/dev/null 2>&1 || { echo "0 0"; return 0; }
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
      [ "${3:-}" != fix ] || { [ "$s" = S1 ] && n1=$((n1 + 1)) || n2=$((n2 + 1)); }
    done <<SITREP_FINDINGS
$got
SITREP_FINDINGS
  done <<SITREP_READINGS
$reads
SITREP_READINGS
  echo "$n1 $n2"
}

# sitrep_reds <landing record> -> one line per row holding a red at head (`R<TAB><row>`), then `N<TAB><count>`
# of red runs at head. A red is at head while it is its row and suite's newest verdict and the row has not been
# published since; a later green on that row and suite, or the row's landing, answers it.
sitrep_reds() {
  [ -f "$1" ] && [ ! -L "$1" ] || { printf 'N\t0\n'; return 0; }
  { [ -n "${_LINE_FIELDS_AWK:-}" ] || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; }
  awk -F'|' "${_LINE_FIELDS_AWK:-}"'
    (ev = line_ev()) == "" { next }
    { rk = line_kv("row") }
    ev == "verdict" && line_kv("kind") == "regression" { next }   # facts of the whole run: no row holds them
    ev == "verdict" && rk != "" { k = rk SUBSEP line_kv("suite"); if (!(k in seen)) { seen[k] = 1; ord[++n] = k }; last[k] = line_kv("result"); next }
    ev == "published" && rk != "" { for (i = 1; i <= n; i++) { split(ord[i], p, SUBSEP); if (p[1] == rk) last[ord[i]] = "landed" } }
    END {
      for (i = 1; i <= n; i++) if (last[ord[i]] == "red") { split(ord[i], p, SUBSEP); c++; if (!(p[1] in said)) { said[p[1]] = 1; printf "R\t%s\n", p[1] } }
      printf "N\t%d\n", c + 0
    }' "$1"
}

# sitrep_render <plan> <root> <line yes|no> -> the page, or with `yes` the one line; rc 0
# sitrep_goals <plan> <landing record> <landing report with rows> -> the goals indicator as fold lines: `goals — <r> of
# <n> reached`, ✅ when all are, ✖️ when one is missed or overdue, else ❔ when one is unmeasured, else ➖; then one line
# per requirements theme, reached or not, `<mark> <theme> — <d> of <n> criteria discharged; open: …` (lib/plan.sh
# `plan_goals_read`, whose theme rows come first), then one line per measured goal not reached, its mark, theme,
# measure and reading, so a reached measured goal is in the count only. With nothing to read, a task-scale plan says
# `goals — none declared`; a wave or epic plan says which half of its requirements is missing, never "none declared".
sitrep_goals() {
  local g k
  g="$(plan_goals_read "$1" "$2" "$3")"
  if [ -z "$g" ]; then
    case "$(plan_scale "$1")" in
      wave|epic)
        if [ -n "$(plan_requirements_file "$1")" ]; then printf '3\t%s goals — the requirements hold no theme\n' "$SITREP_MARK_NONE"
        else printf '3\t%s goals — no requirements file found for the plan\n' "$SITREP_MARK_NONE"; fi ;;
      *) printf '3\t%s goals — none declared\n' "$SITREP_MARK_NONE" ;;
    esac
    return 0
  fi
  k="$(plan_themes "$1" | awk 'NF { n++ } END { print n + 0 }')"
  printf '%s\n' "$g" | awk -F'\t' -v k="$k" -v W="$SITREP_MARK_WITHIN" -v E="$SITREP_MARK_NEAR" -v O="$SITREP_MARK_OVER" -v N="$SITREP_MARK_NONE" '
    { n++
      if ($1 == "reached") { r++; mk = W } else if ($1 == "missed" || $1 == "overdue") { miss = 1; mk = O }
      else if ($1 == "pending") { pend = 1; mk = E } else { unk = 1; mk = N }
      if (n <= k) l[++j] = "6\t   " mk " " $2 " — " $3 (($1 == "reached") ? "" : "; " $4)
      else if ($1 != "reached") l[++j] = "6\t   " mk " " $2 ": " $3 " — " $4 }
    END { printf "3\t%s goals — %d of %d reached\n", miss ? O : (unk ? N : (pend ? E : W)), r, n; for (i = 1; i <= j; i++) print l[i] }'
}

sitrep_render() {
  local plan="$1" root="$2" line="$3" now slug recdir rec rows owed reds red_rows nred lr lr1
  local s_mark s_text c_mark c_text w_mark w_text ty gl lab desc kind note glyph
  local idle_min elapsed i_pct d_pct ratio admitted cids cmins work
  local landed=0 active=0 pending=0 redn=0 total=0 approvals lmed="" appr_at dlv_at cur pages ahead
  now="$(sitrep_now)"
  slug="$(proof_plan_slug "$plan")"
  recdir="$(docs_root "$root")/record/$slug"
  rec="$(_wt_proofs_path "$root" "$plan")"
  rows="$(units_rows "$plan" 2>/dev/null)"
  # What the person owes: the four kinds that are theirs, from the stores of the sessions bound to this plan.
  owed="$( { owed_list_plan "$plan" "$root" 2>/dev/null || :; } | awk -F'\t' '$1 ~ /^(approve|waive|finding|gate|decide):/')"
  reds="$(sitrep_reds "$rec")"
  red_rows="$(printf '%s\n' "$reds" | awk -F'\t' '$1 == "R" { print $2 }')"
  nred="$(printf '%s\n' "$reds" | awk -F'\t' '$1 == "N" { print $2 }')"
  lr="$(landing_report "$rec" "$root" yes 2>/dev/null)"; lr1="${lr%%$'\n'*}"
  # a goal decision whose goal now reads reached is closed in fact, whether or not the tick has closed it yet
  local gk gt
  gk="$(plan_goals_read "$plan" "$rec" "$lr" | awk -F'\t' '$1 == "reached" { print $2 }' | while IFS= read -r gt; do printf 'decide:goal:%s ' "$(plan_goal_slug "$gt")"; done)"
  [ -z "$gk" ] || owed="$(printf '%s\n' "$owed" | awk -F'\t' -v ks="$gk" 'BEGIN { n = split(ks, a, " "); for (i = 1; i <= n; i++) drop[a[i]] = 1 } !($1 in drop)')"
  # a decision put to the user and not yet ruled is owed by them as much as an item of the owed store is, and once
  pages="$(pages_open "$plan" "$recdir/design-ledger.md")"
  owed="$(printf '%s\n' "$owed" | pages_owed "$pages")"
  # an approval the person owes, a numbered decision a row reads as approval:D<n> among them, blocks the rows that read it
  approvals="$(printf '%s\n' "$owed" | awk -F'\t' 'index($1, "approve:") == 1 { print substr($1, 9) } $1 ~ /^decide:D[0-9]+$/ { print substr($1, 8) }')"
  # the schedule's bar half reads the one-file landings alone (lib/plan.sh), so a landing of many files moves it not
  lmed="$(plan_one_file_median "$plan" "$lr")"; lmed="${lmed%%	*}"
  appr_at="$(sitrep_approved_at "$plan")"
  dlv_at="$(sitrep_delivered_at "$plan")"
  cur="$(awk '/^[[:space:]]*```/ { f = !f; next } !f && /^[[:space:]]*current[[:space:]]*:/ { s = $0; sub(/^[^:]*:[ \t]*/, "", s); sub(/[^0-9].*$/, "", s); print s; exit }' "$plan")"
  # THE WORK'S OWN STEP: current: moves only by its advance, which may wait on a gate while later tasks already run, so
  # the title says the furthest step a landed or active task stands at, and the tasks there, when it is ahead.
  ahead="$(printf '%s\n' "$rows" | awk -F'\t' -v cur="$cur" '
    { s = tolower($10); gsub(/[ \t]/, "", s); st = $2; gsub(/[ \t]/, "", st); id = $1; gsub(/[ \t]/, "", id) }
    (s == "landed" || s == "active") && st ~ /^[0-9]+$/ { if (st + 0 > mx) { mx = st + 0; ids = id } else if (st + 0 == mx) ids = ids " " id }
    END { if (cur ~ /^[0-9]+$/ && mx > cur + 0) print mx " " ids }')"

  # ---- The Task list: the attended steps 0 to 3, each with its approval time, then every task in EXECUTION ORDER,
  # and nothing else. One line each, `<glyph> <step>/<task>: <name>`, then a time in parentheses or a short state after
  # " — " (`sitrep_task_lines` fits the line to the page, the name alone giving way):
  #   done       by landing time, with it; the time is read from the task's `- T<n>:` line wherever it sits on it,
  #              `landed <sha> <ISO>` or `landed-by-hand: <who> <ISO> "<why>"` (`by hand` said), the earlier of the
  #              two when both appear, after any text; a done task whose line names no instant follows them, so said;
  #   in flight  by their place on the line, lib/line.sh's fold read as it stands (read-only: no git counting, no
  #              liveness), saying what each does: `in its landing, <n> of <m> suites green` (a candidate built),
  #              `queued behind <task>` or `next on the line` (none built yet), or `building`;
  #   the rest   in dependency order over `units_edges` (a task after every open task it waits on, else table
  #              order), each saying what it `waits on` (`units_waiting`: the writer task, else the read in words;
  #              the first named and the others counted, `waits on T1 +8`); a task not started is bare, a held one
  #              says `held`.
  # A task with a red at head or waiting on an approval the person owes is blocked (⛔); a red says `red`.
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
          } | awk -F'\t' -v dlv="${dlv_at:+yes}" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function words(r) {   # a read, in words: an approval is the person'"'"'s, a step its number, a proof its facts
      sub(/^live:/, "", r)
      if (index(r, "proof:") == 1) { sub(/: .*$/, "", r); return "the " substr(r, 7) " facts at the head" }
      if (index(r, "approval:") == 1) return "your approval of " substr(r, 10)
      if (index(r, "step:") == 1) return "step " substr(r, 6)
      return r
    }
    function row(i, kind, note,   d) {
      d = tk[i]; if (d == "") d = "—"
      if (id[i] in red && st[i] != "landed") { kind = "s"; note = "red" }
      printf "R\t%s\t%s/%s\t%s\t%s\t%s\n", g[i], stp[i], id[i], d, kind, note
    }
    $1 == "X" { red[$2] = 1; next }
    $1 == "A" { appr[$2] = 1; next }
    $1 == "L" { land[$2] = $3; hand[$2] = $4; next }
    $1 == "C" { cur = $2; next }
    $1 == "AB" { ab = $2; next }
    $1 == "S" { sap[$2] = $3; sline[$2] = 1; next }
    $1 == "Q" { nq++; qr[nq] = $2; qc[nq] = $3; qo[nq] = $4; qg[nq] = $5; qm[nq] = $6; next }
    $1 == "W" { w = ($4 != "" && $4 != "-") ? $4 : words($3); if (!(($2, w) in wseen)) { wseen[$2, w] = 1; if (!($2 in wfirst)) wfirst[$2] = w; wcount[$2]++ }; next }
    $1 == "E" { ne++; ef[ne] = $2; et[ne] = $3; next }
    $1 == "U" {
      s = tolower(trim($11)); if (s == "dropped") next
      n++; id[n] = trim($2); stp[n] = trim($3); tk[n] = trim($5); rd[n] = $14; st[n] = s; at[id[n]] = n
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
        else note = (prev == "") ? "next on the line" : "queued behind " prev
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
        if (st[pick] == "held") { row(pick, "s", "held"); continue }
        if (st[pick] != "pending" || !(id[pick] in wfirst)) { row(pick, "b", ""); continue }
        note = "waits on " wfirst[id[pick]]   # the first blocker, the others counted
        if (wcount[id[pick]] > 1) note = note " +" (wcount[id[pick]] - 1)
        row(pick, "s", note)
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
  # the schedule mark: the clock and the bar (sitrep_schedule); the pace feeds the close only
  IFS='	' read -r s_mark s_text <<< "$(sitrep_schedule "$plan" "$landed" "$total" "$now" "$lmed")"
  s_text="$s_mark $s_text"
  local lred="${lr1#*· runs: green=}" s12 s1n s2n c_reds c_find
  case "$lr1" in *'· runs: green='*) lred="${lred#* red=}"; lred="${lred%% *}" ;; *) lred=0 ;; esac
  case "$lred" in ''|*[!0-9]*) lred=0 ;; esac
  s12="$(sitrep_open_s12 "$plan" "$root")"; s1n="${s12% *}"; s2n="${s12#* }"; s12=$((s1n + s2n))
  if [ "${nred:-0}" -gt 1 ]; then c_reds="$nred red suites at head"
  elif [ "${nred:-0}" -eq 1 ]; then c_reds="1 red suite at head"
  elif [ "$lred" -gt 1 ]; then c_reds="$lred red suite runs, each answered by a later green"
  elif [ "$lred" -eq 1 ]; then c_reds="1 red suite run, answered by a later green"
  else c_reds="no red suite at head"; fi
  # each open finding is named by its class: one class reads `2 open S2 findings`, both `2 open findings, one S1 and one S2`
  if [ "$s12" -eq 0 ]; then c_find="no open S1 or S2 finding"
  elif [ "$s1n" -eq 0 ] || [ "$s2n" -eq 0 ]; then
    c_find="$s12 open $([ "$s1n" -gt 0 ] && echo S1 || echo S2) finding$([ "$s12" -gt 1 ] && echo s)"
  else c_find="$s12 open findings, $(sitrep_count_word "$s1n") S1 and $(sitrep_count_word "$s2n") S2"; fi
  if [ "${nred:-0}" -gt 0 ] || [ "${s12:-0}" -gt 0 ]; then c_mark="$SITREP_MARK_OVER"
  elif [ "$lred" -gt 0 ]; then c_mark="$SITREP_MARK_NEAR"
  else c_mark="$SITREP_MARK_WITHIN"; fi
  c_text="$c_mark correctness — $c_reds; $c_find"
  # Waste: discarded runs over runs (landing_report's counts), idle-width minutes (fill-report's) over the
  # minutes the fill ledger spans (its first line to now while the run is open, else to its last line).
  local rg rr rn rd rk w_disc w_idle
  case "$lr1" in
    *'· runs: green='*)
      rg="${lr1#*runs: green=}"; rg="${rg%% *}"; rr="${lr1#* red=}"; rr="${rr%% *}"
      rn="${lr1#* none=}"; rn="${rn%% *}"; rd="${lr1#* discarded=}"; rd="${rd%% *}" ;;
    *) rg=0 rr=0 rn=0 rd=0 ;;
  esac
  # a run killed at the gate (rc over 128) is a wasted run, so the report's killed count is discarded too
  rk="${lr1##*killed=}"; case "$rk" in ''|*[!0-9]*) rk=0 ;; esac
  rd=$((rd + rk))
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

  # ---- The close: sitrep_close's floor and likely instants on one line; their arithmetic is the basis's
  local fl lk whose nland per larger wtxt ltext btext pace_txt lk_txt pt cl lkc
  set --
  if [ -n "$dlv_at" ]; then
    cl="$(sitrep_clock "$dlv_at" "$now")"
    set -- "Nothing is left to forecast."
    btext="delivered at $cl"; ltext="delivered"
  elif [ -z "$appr_at" ]; then
    set -- "The close will be the plan's chain from now, at 1× for its floor and at the measured pace for its likely close, never a typed number."
    btext="no forecast until the plan is approved at Step 3"; ltext="no forecast until approved"
  else
    IFS='	' read -r fl lk ratio whose nland work per larger cids cmins admitted <<< "$(sitrep_close "$plan" "$root" "$now" "$rows")"
  fi
  if [ -n "$dlv_at" ] || [ -z "$appr_at" ]; then :
  elif [ -z "$fl" ]; then
    btext="nothing left to forecast; no task is open"; ltext="closes — no task open"
  else
    cl="$(sitrep_clock "$fl" "$now")"
    if [ "$ratio" = - ]; then
      btext="not before $cl (no pace yet)"; ltext="closes ≥$cl"
      pace_txt="none yet; no landing on this run measures one, and no delivered run at the same scale lends one"
      lk_txt="no likely close without a pace"
    else
      pt="$whose's $(sitrep_ratio_fmt "$ratio")×"
      if [ "$whose" = "this run" ]; then
        pace_txt="$(sitrep_ratio_fmt "$ratio")×, the median over $nland landing$([ "$nland" = 1 ] || echo s) of the minutes from dispatch to landing over the minutes planned"
      else
        pace_txt="$pt measured; no landing on this run measures one yet"
      fi
      if [ "$lk" != - ]; then
        lkc="$(sitrep_clock "$lk" "$now")"
        btext="not before $cl · likely $lkc ($pt)"; ltext="closes ≥$cl ~$lkc"
        lk_txt="the likely close: $(awk -v l="$larger" -v r="$ratio" 'BEGIN { printf "%d", l * r + 0.5 }') min at $(sitrep_ratio_fmt "$ratio")×, $lkc"
      else
        btext="not before $cl ($pt)"; ltext="closes ≥$cl"
        lk_txt="at $(sitrep_ratio_fmt "$ratio")× the likely close falls at or before now, so the floor stands alone"
      fi
    fi
    if [ "$admitted" -eq 0 ]; then wtxt="over 1 suite run, none admitted now"
    elif [ "$admitted" -eq 1 ]; then wtxt="over the 1 suite run the gate admits"
    else wtxt="over the $admitted suite runs the gate admits"; fi
    set -- "The work left is $work min as planned, $per min $wtxt; the longest chain left, $(printf '%s' "$cids" | sed 's/,/ → /g'), is $cmins min; the larger is $larger min." \
           "The pace: $pace_txt." \
           "The floor: $larger min at 1× from now, $cl; $lk_txt." \
           "It assumes what you owe is answered now."
  fi
  if [ "$line" = basis ]; then
    printf '2\t- %s\n' "Close: $btext." "$@" | sitrep_fold
    return 0
  fi

  # ---- What is owed, in words: what to do, then what waits on it
  local blk="" whats="" nown=0 k sent ttl rep what det wids pair
  while IFS='	' read -r k sent ttl rep; do
    [ -n "$k" ] || continue
    rep="${rep#poker: }"; [ -n "$rep" ] || rep="$ttl"
    det="$rep"
    case "$k" in
      approve:step[0-9]*) what="approve the Step ${k#approve:step} card" ;;
      approve:*) what="approve ${k#approve:}" ;;
      decide:D[0-9]*) what="reply to ${k#decide:}" ;;
      waive:*) what="waive or read ${k#waive:}" ;;
      *) what="$(printf '%s' "$ttl" | awk '{ print tolower(substr($0, 1, 1)) substr($0, 2) }')" ;;
    esac
    # a decision's own item carries its sentence and its wait line; one a row's approval read opened, with no put
    # open on the ledger, says who waits on it as an approval does
    pair=no
    case "$k" in approve:*|waive:*) pair=yes ;; decide:D[0-9]*) [ "$ttl" = "$what" ] || pair=yes ;; esac
    case "$k" in
      approve:*|decide:D[0-9]*)
        wids="$(printf '%s\n' "$rows" | awk -F'\t' -v want="approval:${k#*:}" '
          { s = tolower($10); gsub(/[ \t]/, "", s); if (s == "landed" || s == "dropped") next
            n = split($13, a, ","); for (i = 1; i <= n; i++) { x = a[i]; gsub(/^[ \t]+|[ \t]+$/, "", x); sub(/^live:/, "", x); if (x == want) { print $1; next } } }')"
        if [ "$pair" = yes ] && [ -n "$wids" ]; then
          # shellcheck disable=SC2086
          det="$(sitrep_list 5 $wids) $([ "$(printf '%s\n' "$wids" | grep -c .)" -gt 1 ] && echo wait || echo waits) on it"
        fi ;;
    esac
    nown=$((nown + 1))
    if [ "$pair" = yes ]; then blk="${blk}2	- $what: $det"$'\n'
    else blk="${blk}2	- $det"$'\n'; fi   # a decision, finding or gate: the item's own sentence, never its title beside it
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
  # THE STOPS AHEAD ARE NAMED, IN ORDER: while the release approval card has no reply and an integrate row still
  # waits, the card to the user stands between the tasks before that row and the row itself.
  local intids nbefore="" nafter="" t seq
  intids=" $(printf '%s\n' "$rows" | awk -F'\t' '{ s = tolower($10); gsub(/[ \t]/, "", s) } $3 == "integrate" && s == "pending" { printf "%s ", $1 }')"
  if [ -n "$nextup" ] && ! /usr/bin/grep -qs '^replied: at=' "$recdir"/release-approval-*.md "$recdir/$RR_OLD_VERB"-*.md; then
    for t in $nextup; do
      if [ -n "$nafter" ] || { [ "$intids" != " " ] && case "$intids" in *" $t "*) true ;; *) false ;; esac; }; then nafter="$nafter $t"; else nbefore="$nbefore $t"; fi
    done
  fi
  # shellcheck disable=SC2086
  if [ -n "$nextup" ]; then
    if [ -n "$nafter" ]; then
      seq="${nbefore:+$(sitrep_list 3 $nbefore), then }the release approval card to you, then $(sitrep_list 3 $nafter)"
    else seq="$(sitrep_list 3 $nextup)"; fi
    if [ -n "$parts" ]; then parts="$parts; then $seq"; else parts="$seq"; fi
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
  local proj title_rel gh grade_at grade_g grade_why gline
  proj="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  case "$proj" in */.git) proj="${proj%/.git}"; proj="${proj##*/}" ;; *) proj="${root##*/}" ;; esac
  title_rel="$(plan_frontmatter_get "$plan" release 2>/dev/null)"
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
    # shellcheck disable=SC2086
    printf '0\tSitrep · %s%s · %s · step %s of 9%s%s\n' "$proj" "${title_rel:+ $title_rel}" "$(sitrep_date "$now" '%A %-I:%M %p')" \
      "${cur:--}" "${ahead:+ · work at step ${ahead%% *} ($(sitrep_list 3 ${ahead#* }))}" \
      "$([ "$total" -gt 0 ] && printf ' · %d of %d tasks done (%d%%)' "$landed" "$total" $(( (landed * 200 + total) / (total * 2) )))"
    printf '0\t\n0\tBottom line\n'
    printf '2\t- %s\n' "$b_owe" "$b_next" "$b_done" "Close: $btext."
    printf '0\t\n0\tTask list\n'
    while IFS='	' read -r ty gl lab desc kind note; do
      [ -n "$ty" ] || continue
      case "$gl" in L) glyph="✅" ;; A) glyph="🔄" ;; X) glyph="⛔" ;; *) glyph="⬜" ;; esac
      case "$kind" in
        t)  state="($(sitrep_clock "$note" "$now"))" ;;
        th) state="($(sitrep_clock "$note" "$now"), by hand)" ;;
        s)  state="— $note" ;;
        *)  state="" ;;
      esac
      printf '%s\t%s\t%s\t%s\n' "$glyph" "$lab" "$desc" "$state"
    done <<SITREP_SIT | sitrep_task_lines
$sit
SITREP_SIT
    printf '0\t\n0\t%s\n' "$gh"
    printf '3\t%s\n' "$s_text" "$c_text" "$w_text"
    sitrep_decisions "$recdir/design-ledger.md" "$recdir"
    pages_readings "$pages" "$now" | awk -F'\t' 'NF >= 2 { print "3\t" $1 " reading — " $2 }'
    sitrep_goals "$plan" "$rec" "$lr"
    [ -z "$gline" ] || printf '2\t- %s\n' "$grade_why"
    printf '0\t\n0\tBlocked on you\n'
    if [ -n "$blk" ]; then printf '%s' "$blk"; else printf '2\t- Nothing: no decision or action is owed by you.\n'; fi
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

  # THE HANDOFF DOCUMENT. One self-contained file a fresh session continues from, written whole by this verb and never
  # by hand, with or without a bound run, to lib/handoff.sh `handoff_home_file`: the run's slug when one is bound, else
  # the purpose's, else the branch's. The project's bionic folder is created with its ignore file (the literal `*`)
  # when the project has none, and a handoffs folder git would track gets one of its own, so the file is never in
  # source control. The kind line, then the title (the project, the local day and time, the run or `no run bound`, and
  # `for <purpose>` when the one argument names it), then the sections in order:
  #   Summary · Goal · State · Findings · Decisions · Ruled out · Open · Suggested skills · Next · Resume
  # State is this verb's alone: `written:`, the tree (handoff_tree_lines), what runs (handoff_running_lines and, bound,
  # handoff_landing_lines), the agents (the harness's newest ListAgents answer, else the roster's open rows marked
  # unverified) with each one's type, run, brief and progress file, and, bound, the plan, step, working and
  # integration branches, open tasks and Patrol; a closed run's resume point and branch lines are close-out.sh's
  # (`closed-form`, the one writer of both). Every other section is composed by the session and read on stdin
  # (lib/handoff.sh `handoff_compose`); a composed State or Resume is dropped. The whole page passes the redaction
  # (lib/handoff.sh `handoff_redact`) and folds at 92 columns (sitrep_fold); the last line is never folded: bound,
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
      HO_ROWS="$(units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' '
        { st = $10; wt = $11; ag = $5
          if (ag == "") ag = "—"
          has = (wt != "" && wt != "—" && wt != "-")
          if (st == "active" || (st == "pending" && has)) print "  - " $1 " · " ag " · " (has ? wt : "—") " · " st }')"
    fi
    # THE PAGE: every line `<continuation indent> TAB <text>`, redacted, then folded; the last line after the fold.
    HO_TITLE="Handoff · $(clean "${HO_ROOT##*/}") · $(sitrep_date "$HO_E" '%A %-I:%M %p') · $HO_RUNWORD"
    [ -z "$HO_PURPOSE" ] || HO_TITLE="$HO_TITLE · for $(clean "$HO_PURPOSE")"
    if [ "$HO_MODE" = none ]; then HO_LAST="Read $HO_REL whole, then do Next 1."; else HO_LAST="/bionic:canonical-sdlc $HO_REL"; fi
    HO_TMP="$HO_FILE.tmp.$$"; [ "$HO_MODE" = none ] || HO_TMP="$PV_NEW.2"
    ho_state() {  # -> the State section's lines, each with its fold indent
      printf '2\twritten: %s\n' "$HO_NOW"
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
        printf '0\t%s\n0\t\n' "$HO_TITLE"
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
      } | handoff_redact "$HO_CF" | sitrep_fold
      printf '%s\n' "$HO_LAST"
    } > "$HO_TMP" 2>/dev/null || { die "REFUSED — the handoff cannot be written at $HO_FILE; nothing was written."; exit 2; }
    # WHAT IT SAYS IS WHERE THE FILE IS AND HOW THE NEXT SESSION RESUMES, and nothing more: the counts, the
    # redactions and the blocks left out are in the file for whoever reads it.
    HO_SAY="handoff — written to $(cd "${HO_FILE%/*}" 2>/dev/null && pwd -P)/${HO_FILE##*/}"
    if [ "$HO_MODE" = none ]; then
      if ! mv -f "$HO_TMP" "$HO_FILE" 2>/dev/null; then
        die "REFUSED — the handoff file cannot be moved into place at $HO_FILE."
        exit 2
      fi
      say "$HO_SAY"
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
    say "$HO_SAY"
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
  # THE PUT. A decision put during a run is one ledger entry before it is shown, `## Δ<k> — D<n> put (orchestrator
  # <date> <time>): <title>`, Δ one past the ledger's highest, its body the wait line; the ledger is begun when the run
  # has none. It prints the round the put opens and the wait line, which ends the decision's Significance as printed.
  # REFUSED (1), nothing written: a number that is not D<n>, a title that is empty or more than one line, a ledger that
  # is a symlink.
  decisions_put() {  # <plan> <ledger> <D<n>> <title>
    local plan="$1" led="$2" d="$3" title="$4" wait k at r
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
    wait="$(decision_wait "$plan" "$d")"
    k="$(sed -n 's/^## Δ\([0-9][0-9]*\).*/\1/p' "$led" 2>/dev/null | sort -n | tail -1)"; k=$(( ${k:--1} + 1 ))
    at="$(date '+%Y-%m-%d %-I:%M %p %Z')"
    mkdir -p "${led%/*}" 2>/dev/null
    { if [ -f "$led" ]; then cat "$led"; else printf '# Design ledger — %s\n' "$(proof_plan_slug "$plan")"; fi
      printf '\n## Δ%s — %s put (orchestrator %s): %s\n\n%s\n' "$k" "$d" "$at" "$title" "$wait"
    } > "$led.new.$$" 2>/dev/null && mv -f "$led.new.$$" "$led" 2>/dev/null || {
      rm -f "$led.new.$$" 2>/dev/null
      die "REFUSED — ${led#"$REPO_REAL"/} cannot be written; nothing is written."
      exit 1
    }
    r="$(decisions_rounds "$led" | awk -F'\t' -v d="$d" '$1 == d { print $2 }')"
    printf 'put: %s · round %s · %s\n' "$d" "${r:-1}" "$title"
    printf 'wait: %s\n' "$wait"
    exit 0
  }

  # THE REGISTER (wave-38 T13; D24, AC-3.4). Read-only. `decisions` is the bound run's ledger through `decisions_list`;
  # `--all` is every run's under the docs root, keyed by wave, with the ADRs (`decisions_all`). Exit 1 in one line
  # naming the path when the run's ledger is absent; 2 when there is no run to read. `decisions put` is the one writer.
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
    [ -z "${DC_PUT:-}" ] || decisions_put "$DC_PLAN" "$DC_LEDGER" "$DC_PUT" "${DC_TITLE:-}"
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
    # the page's own reader of the open decisions and the readings: a decision put and not ruled is open here as there,
    # and owed once whether or not a row's approval read opened it too
    RS_PAGES="$(pages_open "$RS_PLAN" "$RS_LEDGER")"
    RS_OWED="$(printf '%s\n' "$RS_OWED" | pages_owed "$RS_PAGES")"
    RS_OPEN="$(printf '%s\n' "$RS_OWED" | awk -F'\t' 'NF && $1 != "" { k = $1; r = $4; sub(/^poker: /, "", r); if (r == "") r = $3
      if (k ~ /^decide:D[0-9]+$/ && $3 == "reply to " substr(k, 8)) { k = substr(k, 8); sub(/^D[0-9]+ · /, "", r) }
      print "open: " k " — " r }')"
    if [ -n "$RS_OPEN" ]; then printf '%s\n' "$RS_OPEN"; else printf 'open: none — no decision is open\n'; fi
    pages_readings "$RS_PAGES" "$(sitrep_now)" | awk -F'\t' 'NF >= 2 { print "reading: " $2 }'
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
    RS_AT="$(handoff_line "$RS_FILE" written)"; RS_AT="${RS_AT#written: }"
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
