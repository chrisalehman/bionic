# shellcheck shell=bash
# hooks/poker/plan.sh — the plan verbs: the contract grammar, the matrix and the rows of the plan (budget,
# amend, task-add, task-set, ledger-add, ledger-set, step-line, step-field, matrix-render, discharge,
# matrix-set, tasks-prose, epic-row, continuation-fill, brief, task-split, release-approval, reply).
#
# A part of hooks/session-poker.sh, which sets every global and loads this file before any verb runs. A part
# defines functions only, and is never run by itself.

# ---------------------------------------------------------------- the contract grammar
#
# THE DISPATCH WALL'S GRAMMAR, AT THIS FILE'S TWO DOORS (wave-20 T9; spec D4, ledger Δ10).
# `amend` widens a live contract and `task-add` writes a Files cell a brief is later built
# from; both hand what they were given to payload/scripts/lib/brief.sh's
# `brief_validate_fields`, so a contract that enters here is held to exactly a fresh
# dispatch's standard. Loaded on first use, never at the top: the tick runs every Patrol
# interval and needs none of it.
poker_brief_load() {
  declare -F brief_validate_fields >/dev/null 2>&1 && return 0
  [ -f "$BIONIC_LIB/brief.sh" ] || return 1
  # shellcheck source=/dev/null
  . "$BIONIC_LIB/brief.sh"
  declare -F brief_validate_fields >/dev/null 2>&1
}

# The sink `brief_validate_fields` calls: a finding is collected — its fact alone, and its
# fact, fix and detail as the words a refusal prints — and a loud pass is a note.
# Set in hooks/session-poker.sh, before any part loads: POKER_BRIEF_FACTS, POKER_BRIEF_WORDS.
poker_brief_sink() {  # finding <fact> <fix> <detail> | warn <line>
  case "$1" in
    finding)
      POKER_BRIEF_FACTS="${POKER_BRIEF_FACTS}$2"$'\n'
      POKER_BRIEF_WORDS="${POKER_BRIEF_WORDS}  $2 — $3"$'\n'"$(printf '%s\n' "$4" | sed 's/^/    /')"$'\n\n'
      ;;
    warn) note "$2" ;;
  esac
}

# born_floor_backing <plan> <repo> <suite> -> BFB_OF (`floor` or `standing@<12-hex>`) and rc 0 when a red the machine
# recorded backs a floor-born marker for <suite>; rc 1 otherwise, BFB_OWED and BFB_BRANCH set for the refusal's words
# (wave-36 T42; D9, design-ledger Δ8, born of critic-adversarial #1). THE TWO FACTS, asked in this order: (a) the
# plan's newest floor proof owes the suite (lib/proof.sh `_proof_last_read` floor owed, the reader `proof-add
# inherited` asks), or (b) the run's landing record (`proof_debt_record`) holds an `ev=standing` event for the suite
# whose head is a commit on the working branch's ref (`proof_branch_head`), the newest such event first. A marker the
# judge holds every chain by is no declaration. No library gives a standing event a reader; this is the one awk, over
# the file, and it reads the fields as lib/line.sh's fold does (`fv`, a suite by its file name).
# Set in hooks/session-poker.sh, before any part loads: BFB_OF, BFB_OWED, BFB_BRANCH.
born_floor_backing() {
  local plan="$1" repo="$2" suite="$3" rec bh h
  BFB_OF=""; BFB_OWED="$(_proof_last_read "$plan" regression owed)"; BFB_BRANCH="$(plan_working_branch "$plan" 2>/dev/null)"
  case ",$BFB_OWED," in *",$suite,"*) BFB_OF=regression; return 0 ;; esac
  rec="$(proof_debt_record "$plan" "$repo" 2>/dev/null)" && [ -f "$rec" ] || return 1
  bh="$(proof_branch_head "$plan" "$repo")" || return 1
  { [ -n "${_LINE_FIELDS_AWK:-}" ] || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; }
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    h="$(git -C "$repo" rev-parse --verify -q "${h}^{commit}" 2>/dev/null)" || continue
    git -C "$repo" merge-base --is-ancestor "$h" "$bh" 2>/dev/null || continue
    BFB_OF="standing@${h:0:12}"; return 0
  done <<BFB_STANDING
$(awk -F'|' -v want="$suite" "${_LINE_FIELDS_AWK:-}"'
    line_ev() == "standing" { s = line_kv("suite"); sub(/.*\//, "", s); if (s == want && line_kv("head") != "") h[++n] = line_kv("head") }
    END { for (i = n; i >= 1; i--) print h[i] }' "$rec" 2>/dev/null)
BFB_STANDING
  return 1
}

# poker_files_cell <id> <kind> <agent> <Files cell> <repo> <plan> -> PFC_OUT (the cell to write) and PFC_ART (the
# record artifact a reader row gained, or empty); returns 0, or 1 / 2 with the refusal printed. THE ONE JUDGE OF A
# ROW'S FILES CELL (wave-36 T41; REQ-7 AC-7.1, AC-10.2; D13): `task-add` writes a row's cell and `task-set files=`
# corrects a pending row's, and both are held to it. A reader row (verify, test, review) whose cell names no record
# gains <record dir>/<id>.md, the artifact `brief` gives it; the cell is then read as the dispatch wall will read it
# (`lift_contract_fields` and `brief_validate_fields`), a cell the lift reads as no path being refused now in the
# grammar's words. `—`, `-` and empty declare nothing to judge. ONE FACT IS THE BRIEF'S, NOT THE CELL'S: a `Files:`
# line alone names no suite, and here that is a note, the row going in.
# Set in hooks/session-poker.sh, before any part loads: PFC_OUT, PFC_ART.
poker_files_cell() {
  local id="$1" kind="$2" agent="$3" files="$4" repo="$5" plan="$6" fact cell_facts=""
  PFC_OUT="$files"; PFC_ART=""
  if poker_reader_kind "$kind" && [ -z "$(poker_brief_record_entry "$files" artifact "$id")" ]; then
    PFC_ART="$(docs_root "$repo")/record/$(proof_plan_slug "$plan")/$id.md"
    case "$PFC_ART" in "$repo"/*) PFC_ART="${PFC_ART#"$repo"/}" ;; esac
    case "$files" in ''|'—'|'-') PFC_OUT="$PFC_ART" ;; *) PFC_OUT="$files, $PFC_ART" ;; esac
  fi
  case "$PFC_OUT" in
    ''|'—'|'-') return 0 ;;
  esac
  if ! poker_brief_load; then
    die "REFUSED — the contract grammar (lib/brief.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
    return 2
  fi
  POKER_BRIEF_FACTS=""; POKER_BRIEF_WORDS=""
  brief_validate_fields "$(lift_contract_fields "Files: $PFC_OUT" "$agent")" \
    "$agent" "$repo" poker_brief_sink || :
  while IFS= read -r fact; do
    [ -n "$fact" ] || continue
    case "$fact" in
      'Files: alone names no suite')
        note "$fact — a dispatch of $id will need a Suites: or Re-executes: line" ;;
      *) cell_facts="${cell_facts}${fact}"$'\n' ;;
    esac
  done <<EOF
$POKER_BRIEF_FACTS
EOF
  if [ -n "$cell_facts" ]; then
    die "REFUSED — a dispatch of $id with Files: $PFC_OUT would be refused by the dispatch grammar; the plan is unchanged:"
    printf '%s' "$POKER_BRIEF_WORDS" >&2
    return 1
  fi
  return 0
}

# A brief span out of newline-joined additions: `Files:` and `Suites:` take the words as
# they are, `Re-executes:` marks each run with backticks, the one spelling the lift reads a
# run from. <runs, marked> is text already in that shape (a row's stored value).
poker_brief_span() {  # <files lines> <suites lines> <runs, marked> <runs lines> -> brief text
  local f s r="$3" line
  # Files: is a comma-separated list (wave-27 T42), so its lines join with commas: two
  # additions joined by a space would read as one item holding white space, which is prose.
  f="$(printf '%s\n' "$1" | awk 'NF { printf "%s%s", (n++ ? ", " : ""), $0 }')"
  s="$(printf '%s' "$2" | tr '\n,' '  ')"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    r="${r:+$r }\`${line}\`"
  done <<EOF
$4
EOF
  case "$f" in *[![:space:]]*) printf 'Files: %s\n' "$f" ;; esac
  case "$s" in *[![:space:]]*) printf 'Suites: %s\n' "$s" ;; esac
  [ -n "$r" ] && printf 'Re-executes: %s\n' "$r"
  return 0
}

# The marked runs of a stored `re_executes=` value, one per line: the text between each pair
# of backticks. The same reading the budget arm takes of the field.
poker_marked_runs() {  # <runs, marked> -> one run per line
  printf '%s' "$1" | awk -F'`' '{ for (i = 2; i <= NF; i += 2) if ($i != "") print $i }'
}

# ---- BEGIN the brief rendered from its row (wave-33 T9; REQ-4 AC-4.4; D8) ----
# `brief <row>` writes the dispatch brief a plan row can carry, so the orchestrator writes only the judgment the
# row cannot. THE SCAFFOLD'S LABELS ARE THE SHIPPED ONES, read out of skills/canonical-sdlc/dispatch.md's
# `### Scaffold` fence with the extractor hooks/dispatch-preflight.sh `dp_scaffold_marked` reads the same fence
# with, never a second list: a label the verb fills from the row is written, every other label is named on the
# verb's own line as the orchestrator's. THE RULES, each the row's own cell or a function of it:
#   Expected duration   the row's size, in minutes
#   Expected artifact   the dispatch ledger's artifact cell for the row; else the first Files entry under record/
#                       that is neither a progress file nor assumptions.md; else the first record path the
#                       row's task names; else, for a reader row (verify, test, review), <record dir>/<row>.md,
#                       which its Files line then carries (wave-35 T8; AC-6.1); else the slot, marked
#   Progress artifact   the Files entry that ends .progress.md, else <record dir>/<row>.progress.md; Cadence is
#                       the 15-minute rule's own number. Both only for a size of 15 or more
#   Files               the row's Files cell, verbatim; no line for a row whose cell is empty or a dash
#   Suites, Lands-on    the row's `suites` / `lands-on` cells when the table has them and the row fills them;
#                       else the *.test.sh entries of Files by file name; else, for a row whose Files write
#                       code, the suites `anchors index` names for those files at the working head, or the
#                       slot marked for the orchestrator, never none (wave-35 T8; AC-6.3); `Suites: none`
#                       and `Lands-on: none <reason>` only for a row that writes no code
#   Row                 the row's id
# The file starts with the scaffold lines, so no prose after them is a label's first hit (lib/brief.sh reads the
# first hit of an unpinned label). A re-render keeps everything from `## Judgment` on: that section is the
# orchestrator's, and the verb never writes anything into it but the two marked slots of a first render.

# poker_brief_cell <plan> <section heading> <row id> <header> -> that cell of the row, trimmed; rc 1 when the
# section, the column or the row is not there. For the cells units.sh's fixed columns do not carry.
poker_brief_cell() {
  awk -v sect="$2" -v id="$3" -v want="$4" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    BEGIN { SEP = sprintf("%c", 1) }
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insec = (tolower(trim(substr($0, 3))) == tolower(sect)); hdr = 0; col = 0; next }
    !insec || $0 !~ /^[[:space:]]*\|/ { next }
    {
      # AN ESCAPED PIPE IS TEXT, NOT A CELL EDGE (wave-39 T23; D22): units.sh reads `\|` so, and a task cell carrying
      # a case label `(a\|b)` shifted every cell after it one to the left here, so the suites cell of a row read as its status.
      line = $0; gsub(/\\\|/, SEP, line)
      n = split(line, c, "|")
      if (!hdr) { hdr = 1; for (i = 2; i < n; i++) if (tolower(trim(c[i])) == tolower(want)) col = i; next }
      if (c[2] ~ /^[ \t]*:?-+:?[ \t]*$/) next
      if (col && trim(c[2]) == id) { v = trim(c[col]); gsub(SEP, "|", v); print v; found = 1; exit }
    }
    END { exit !found }' "$1"
}

# poker_brief_labels -> the shipped scaffold's label names, one per line, in its order. rc 1 when the file is not there.
poker_brief_labels() {
  local file="${HOOK_DIR}/../skills/canonical-sdlc/dispatch.md"
  [ -r "$file" ] || return 1
  /usr/bin/awk '
    /^### Scaffold/            { inb = 1; next }
    inb && /^```/              { fence++; if (fence == 2) exit; next }
    inb && fence == 1          { sub(/:.*$/, ""); print }
  ' "$file"
}

# poker_brief_none <cell> -> 0 when a table cell says nothing: empty, or a dash.
poker_brief_none() {
  case "$1" in ''|'—'|'-'|'–') return 0 ;; esac
  return 1
}

# poker_brief_suites <Files cell> -> the suites its *.test.sh entries name, by file name, in order, once each, comma-joined.
poker_brief_suites() {
  printf '%s' "$1" | awk -F',' '{
    for (i = 1; i <= NF; i++) {
      e = $i; gsub(/`/, "", e); sub(/^[ \t]+/, "", e); sub(/[ \t]+$/, "", e)
      if (e == "" || e ~ /[ \t]/ || index(e, "*") || index(e, "?") || index(e, "[")) continue
      n = split(e, p, "/"); b = p[n]
      if (length(b) <= 8 || substr(b, length(b) - 7) != ".test.sh") continue
      if (!(b in seen)) { seen[b] = 1; out = out (out == "" ? "" : ", ") b }
    }
    print out }'
}

# poker_brief_record_entry <Files cell> <artifact|progress|named> <row id> -> an entry under record/ for the row; nothing
# when none. THE ONE RULE FOR A ROW'S RECORD (wave-37 T6; REQ-7 AC-7.1, AC-7.2; D10), read by `brief` and judged by
# `task-set files=`: `named` is the entry whose basename is <row>.md or starts <row>- (never a progress file);
# `artifact` is the named entry, else the first entry that is neither a progress file nor assumptions.md; `progress`
# is the first entry ending .progress.md.
poker_brief_record_entry() {
  printf '%s' "$1" | awk -F',' -v kind="$2" -v row="$3" '{
    for (i = 1; i <= NF; i++) {
      e = $i; gsub(/`/, "", e); sub(/^[ \t]+/, "", e); sub(/[ \t]+$/, "", e)
      if (e == "" || e ~ /[ \t]/ || index(e, "record/") == 0 || substr(e, length(e) - 2) != ".md") continue
      n = split(e, p, "/"); b = p[n]
      isprog = (length(b) > 12 && substr(b, length(b) - 11) == ".progress.md")
      if (kind == "progress") { if (isprog) { print e; exit } continue }
      if (isprog || b == "assumptions.md") continue
      if (row != "" && (b == row ".md" || index(b, row "-") == 1)) { print e; hit = 1; exit }
      if (fb == "") fb = e
    }
  } END { if (!hit && kind == "artifact" && fb != "") print fb }'
}

# poker_brief_task_record <task text> -> the first record path the text names (a token holding record/ and ending .md); nothing when none.
poker_brief_task_record() {
  printf '%s\n' "$1" | awk '{
    n = split($0, w, /[ \t,;()"\047`]+/)
    for (i = 1; i <= n; i++) if (index(w[i], "record/") > 0 && w[i] ~ /\.md$/) { print w[i]; exit }
  }'
}

# poker_brief_index_suites <root> <at> <Files cell> -> lib/anchors.sh `reads_suites`, comma-joined: the suites the reads
# index names, at <at> (a commit, or - for the files under <root>), for any file an entry of the cell covers. Nothing
# when no suite reads such a file, or the library cannot be loaded (wave-35 T8; REQ-6 AC-6.3; D15, D9). THE ONE
# READER (wave-37 T3; D4): the dispatch wall's Lands-on arm calls the same `reads_suites`, and the floor's cover rule
# reads the same index.
poker_brief_index_suites() {
  declare -F reads_suites >/dev/null 2>&1 \
    || { [ -n "$BIONIC_LIB" ] && [ -r "$BIONIC_LIB/anchors.sh" ] && . "$BIONIC_LIB/anchors.sh"; } || return 0
  declare -F reads_suites >/dev/null 2>&1 || return 0
  reads_suites "$1" "$2" "$3" | awk 'NF { o = o (o == "" ? "" : ", ") $0 } END { printf "%s", o }'
}

# poker_brief_union <list>... -> the suites of every list (each comma-separated), in the order given, once each by file
# name (a spelling `tests/x.test.sh` and `x.test.sh` is one suite), comma-joined. The one fold of a row's own cells and
# the reads index (wave-39 T23; REQ-17 AC-17.1; D22).
poker_brief_union() {
  printf '%s\n' "$@" | awk '{
    n = split($0, s, /[ \t]*,[ \t]*/)
    for (i = 1; i <= n; i++) {
      t = s[i]; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
      b = t; sub(/^.*\//, "", b)
      if (b != "" && !(b in seen)) { seen[b] = 1; o = o (o == "" ? "" : ", ") t }
    } }
    END { printf "%s", o }'
}

# poker_reader_kind <kind> -> 0 for a reader row's kind (verify, test, review): its artifact is a record it writes.
poker_reader_kind() { case "$1" in verify|test|review) return 0 ;; esac; return 1; }
# ---- END the brief rendered from its row ----

# ---- BEGIN the set of an agent its start did not place (wave-27 T38; review pass 8 F3) ----
# `amend <agent id>` for an id no named row carries: see the verb. The row is the budget wall's
# alone. Its name is the id, so it shadows no other name's latest row; `status=unplaced` is no
# status a reader of live rows counts; the waiver keeps the verdict from judging a deliverable
# nobody owes. The additions are judged by the dispatch grammar, as every amend's are. The set is
# the union of the id's current one and the additions.
# A READER IS HELD TO THREE (wave-27 T74; review pass 53 B1). The role is the one the agent's start
# recorded: the `role=` of the id's last `start-unchecked/v1|event=start|` line, the line the tick's
# NOTIFY is built from. A reader there (auditor, critic, reviewer: `dp_is_reader`) is judged with
# its role and `Questions: evidence`, so the dispatch wall's own count in brief.sh holds it to three
# in total, suites and runs together: the door cannot know which candidate launch was the agent's,
# so it takes the strict side. A start that recorded no role is judged with none, as before.
amend_unplaced() {  # <agent id> <the last row carrying it, or empty> -> the verb's exit status
  local aid="$1" prior="$2" tr sub old_sa="" old_runs="" decl lift rc=0 sa new_runs r row pick
  local role="" span us
  case "$aid" in
    ''|*[!A-Za-z0-9._@-]*)
      die "REFUSED — no row is named $(clean "$aid"), and it is not an agent id; nothing was written."
      return 1 ;;
  esac
  if [ -z "$prior" ]; then
    tr="$(session_transcript "$SESSION_ID")" || tr=""
    if [ -z "$tr" ]; then
      die "REFUSED — no row is named or carries the agent id $aid, and this session's transcript cannot be found to check it is one of its agents; nothing was written."
      return 1
    fi
    sub="${tr%.jsonl}/subagents/agent-${aid}.jsonl"
    if [ ! -f "$sub" ] || [ -L "$sub" ]; then
      die "REFUSED — no row is named or carries the agent id $aid, and no agent $aid ran in this session (no transcript at $sub); nothing was written."
      return 1
    fi
  fi
  if [ -n "$AMEND_FILES" ]; then
    die "REFUSED — $aid is an agent its start did not place, and a Files: contract belongs to its dispatched row; add suites or runs here, or amend that row by name. Nothing was written."
    return 1
  fi
  if ! poker_brief_load; then
    die "REFUSED — the contract grammar (lib/brief.sh) cannot be loaded from $BIONIC_LIB; nothing was written."
    return 2
  fi
  if [ -n "$prior" ]; then
    old_sa="$(line_field "$prior" suites_allowed)"
    row_has_key "$prior" re_executes && old_runs="$(clean "$(line_field "$prior" re_executes)" re_executes)"
  fi
  [ "$old_sa" = none ] && old_sa=""
  decl="$(poker_union ' ' "$old_sa" "$(printf '%s' "$AMEND_SUITES" | tr '\n,' '  ')")"
  us="$(grep -F 'start-unchecked/v1|event=start|' "$ROSTER_FILE" 2>/dev/null | grep -F "|agent_id=${aid}|" | tail -1)"
  [ -n "$us" ] && role="$(clean "$(line_field "$us" role)")"
  span="$(poker_brief_span "" "$decl" "$old_runs" "$AMEND_RUNS")"
  dp_is_reader "$role" && span="${span}"$'\n'"Questions: evidence"
  lift="$(lift_contract_fields "$span" "$role")"
  POKER_BRIEF_FACTS=""; POKER_BRIEF_WORDS=""
  brief_validate_fields "$lift" "$role" "$REPO_REAL" poker_brief_sink || rc=$?
  if [ "$rc" -ne 0 ]; then
    die "REFUSED — a dispatch carrying these additions for $aid would be refused; nothing was written:"
    printf '%s' "$POKER_BRIEF_WORDS" >&2
    case "$POKER_BRIEF_FACTS" in
      *-run\ cap*) dp_is_reader "$role" \
        && die "A reviewer its start did not place is held to three in all: stop it and dispatch it again." \
        && die "($aid started as $role; the NOTIFY line asks the same.)" ;;
    esac
    return 1
  fi
  sa="${BRIEF_SUITES_ALLOWED:-$old_sa}"
  new_runs="$old_runs"
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    grep -qxF -- "$r" <<< "$(poker_marked_runs "$old_runs")" && continue
    new_runs="${new_runs:+$new_runs }\`${r}\`"
  done <<EOF
$(poker_marked_runs "$(brief_field "$lift" re_executes)")
EOF
  if [ "$sa" = "$old_sa" ] && [ "$new_runs" = "$old_runs" ]; then
    die "REFUSED — this amend changes nothing: every addition is already on the set recorded for $aid, or is not a suite or run the dispatch grammar reads. Nothing was written."
    return 1
  fi
  row="$(roster_row status=unplaced "session=$SESSION_ID" "name=$aid" "agent_id=$aid" \
    "launched_at=$(iso_now)" "waiver=the suite set of an agent its start did not place; no contract" \
    "suites_allowed=$sa" suites_source=declared ${new_runs:+"re_executes=$new_runs"} \
    "amended=$(iso_now) $(clean "$AMEND_REASON")")" || row=""
  if [ -z "$row" ]; then
    die "REFUSED — could not build the row for $aid."
    return 2
  fi
  printf '%s\n' "$row" >> "$ROSTER_FILE" 2>/dev/null || {
    die "REFUSED — could not write to $ROSTER_FILE."
    return 2
  }
  pick="$(roster_row_for_id "$ROSTER_FILE" "$aid")" || pick=""
  if [ "$pick" != "$row" ]; then
    die "amend written, but the budget wall reads another row for $aid — a later row carrying that id was written after it"
    return 1
  fi
  say "amended — $aid, an agent its start did not place: suites=${sa:-(none)}${new_runs:+ runs=$new_runs}; the budget wall reads this row from now on."
  return 0
}
# ---- END the set of an agent its start did not place ----

# ---------------------------------------------------------------- the call a refusal names

# pv_fold <name> -> its letters and digits, lower-cased: the form two column names are compared in.
pv_fold() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]'; }

# pv_column_guess <name> <column>... -> the one column <name> was meant as, or nothing: the column
# whose folded name equals the name's, else the ONE column whose folded name is a prefix of the
# name's or has it as a prefix (`artifacts` is `artifact`, `sizes` is `size`). Two are no guess.
pv_column_guess() {
  local want c f n=0 hit=""
  want="$(pv_fold "$1")"; shift
  [ -n "$want" ] || return 0
  for c in "$@"; do [ "$(pv_fold "$c")" = "$want" ] && { printf '%s' "$c"; return 0; }; done
  for c in "$@"; do
    f="$(pv_fold "$c")"
    [ -n "$f" ] || continue
    case "$want" in "$f"*) n=$((n + 1)); hit="$c"; continue ;; esac
    case "$f" in "$want"*) n=$((n + 1)); hit="$c" ;; esac
  done
  [ "$n" -eq 1 ] && printf '%s' "$hit"
  return 0
}

# pv_fix_pairs <columns, one per line> <name=value>... -> PV_FIXED, the pairs with each name the
# columns do not carry (compared case-blind) replaced by its one guess, and PV_UNKNOWN, the names no
# column was guessed for (comma-joined), which the corrected call leaves out.
pv_fix_pairs() {
  local cols="$1" kv n g c known
  local -a list
  list=(); PV_FIXED=(); PV_UNKNOWN=""
  shift
  while IFS= read -r c; do [ -n "$c" ] && list+=("$c"); done <<< "$cols"
  for kv in "$@"; do
    n="${kv%%=*}"; known=""
    for c in ${list[@]+"${list[@]}"}; do
      [ "$(printf '%s' "$c" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$n" | tr '[:upper:]' '[:lower:]')" ] && known=1
    done
    if [ -n "$known" ]; then PV_FIXED+=("$kv"); continue; fi
    g="$(pv_column_guess "$n" ${list[@]+"${list[@]}"})"
    if [ -n "$g" ]; then PV_FIXED+=("$g=${kv#*=}"); else PV_UNKNOWN="${PV_UNKNOWN:+$PV_UNKNOWN, }$n"; fi
  done
}

# pv_header_cells <plan> <tasks|ledger> -> the header cells of the table `units_table_cells` edits (the
# first table under the heading whose header carries an id cell), trimmed, one per line.
pv_header_cells() {
  PH_SECT="$2" awk '
    function trim(v) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); return v }
    BEGIN { sect = ENVIRON["PH_SECT"] }
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^[ \t]*#/ {
      if (st) exit
      if (sect == "tasks" && $0 ~ /^##[ \t]+[Tt]asks([ \t].*)?$/) st = 1
      if (sect == "ledger" && $0 ~ /^##[ \t]+[Dd]ispatch[ \t]+[Ll]edger([ \t].*)?$/) st = 1
      next
    }
    st && /^[ \t]*\|/ {
      n = split($0, c, "|"); ok = 0
      for (i = 2; i < n; i++) if (tolower(trim(c[i])) == "id") ok = 1
      if (!ok) next
      for (i = 2; i < n; i++) if (trim(c[i]) != "") print trim(c[i])
      exit
    }' "$1" 2>/dev/null
}

# matrix_block_has <plan> <AC> <key> -> 0 when the AC block carries that key.
matrix_block_has() {
  MB_AC="$2" MB_KEY="$3" awk "$(units_ac_head_awk)"'
    BEGIN { a = ENVIRON["MB_AC"]; k = ENVIRON["MB_KEY"] ":" }
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^## / { inm = ($0 ~ /^## Verification Matrix/); inb = 0; next }
    !inm { next }
    { y = $0; sub(/[ \t]+$/, "", y) }
    ac_head($0, a) { inb = 1; next }
    inb && /^[ \t]+[^ \t]/ { sub(/^[ \t]+/, "", y); if (index(y, k) == 1) { hit = 1; exit } next }
    { inb = 0 }
    END { exit !hit }' "$1"
}

# THE FILES BESIDE THE PLAN (wave-33 T7; REQ-3 AC-3.3, D8). `epic-row` and `continuation-fill` write the
# epic plan and the run's continuation, which close-out writes after act 3 has wiped this session's
# binding (A-orch-145), so their run is the `--plan` operand when given, else the session's own run, open
# or closed. Neither file is a run plan: the commit gate reads neither, so their transaction is the
# copy, the checksum taken before the projection, the compare and the move, with no dry commit.
# pv_file_open <verb> <operand>... -> PV_REPO, PV_RPLAN, and the cleanup armed; every refusal exits.
pv_file_open() {
  local verb="$1" sid run cand="" p
  shift
  sid="$(session_id)" || sid=""
  if [ -z "$sid" ]; then
    die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
    exit 3
  fi
  if ! engaged_session "$(project_root "$PWD")" "$sid"; then
    say "NOT-ENGAGED — this session has not invoked /bionic:canonical-sdlc; nothing decided"
    exit 0
  fi
  PV_REPO="$(cd "$(project_root "$PWD")" 2>/dev/null && pwd -P)"
  if [ -z "$PV_REPO" ]; then
    die "REFUSED — cannot resolve the working directory."
    exit 2
  fi
  PV_NEW=""
  trap 'rm -f ${PV_NEW:+"$PV_NEW" "$PV_NEW.2"}' EXIT
  if [ -n "${PV_PLAN_ARG:-}" ]; then
    for p in "$PV_PLAN_ARG" "$PV_REPO/$PV_PLAN_ARG"; do
      case "$p" in /*) : ;; *) p="$PWD/$p" ;; esac
      [ -f "$p" ] && { PV_RPLAN="$p"; return 0; }
    done
    die "REFUSED — --plan $(clean "$PV_PLAN_ARG") is no file (read from $PWD and from $PV_REPO); nothing was written."
    exit 1
  fi
  run="$(session_run "$PV_REPO" "$sid" 2>/dev/null)" || :
  case "$run" in
    'bound-open '*) PV_RPLAN="${run#bound-open }"; return 0 ;;
    'bound-closed '*) PV_RPLAN="${run#bound-closed }"; [ -f "$PV_RPLAN" ] && return 0 ;;
    'fallback '*) cand="${run#fallback }" ;;
  esac
  case "$cand" in "$PV_REPO"/*) cand="${cand#"$PV_REPO"/}" ;; esac
  die "REFUSED — $verb writes for this session's run, and the session is bound to none (${run%% *}); close-out wipes the binding, so name the run's plan. Nothing was written."
  pv_next "$verb" "$@" --plan "${cand:-<plan>}"
  exit 1
}

# pv_file_swap <verb> <file> <checksum before> <what> -> moves $PV_NEW over the file when the file still
# reads as it did; exits 0 with nothing written when the projection is the file.
pv_file_swap() {
  local verb="$1" file="$2" sum="$3" what="$4"
  if cmp -s "$PV_NEW" "$file"; then
    say "$verb — $what: the file already reads so; nothing was written."
    exit 0
  fi
  if [ "$(cksum < "$file" 2>/dev/null)" != "$sum" ]; then
    die "REFUSED — $file changed while $what was being written; nothing was written. Run $verb again."
    exit 1
  fi
  if ! mv -f "$PV_NEW" "$file"; then
    die "REFUSED — could not move the copy over $file; it is unchanged."
    exit 2
  fi
}

# mr_tier_keys -> one `<tier><TAB><keys>` line for each of T0..T4, the keys walls.sh `keys_for_tier` names (wave-30
# T14; D9). The list is the gate's own, read by sourcing walls.sh in a subshell, so the stubs matrix-render writes and
# the keys the Verify gate demands cannot drift apart; nothing walls.sh defines outlives the subshell. rc 1 when the
# library or the function cannot be had.
mr_tier_keys() {
  [ -f "$BIONIC_LIB/walls.sh" ] || return 1
  ( . "$BIONIC_LIB/walls.sh" >/dev/null 2>&1 || exit 1
    declare -F keys_for_tier >/dev/null 2>&1 || exit 1
    for _mr_t in T0 T1 T2 T3 T4; do printf '%s\t%s\n' "$_mr_t" "$(keys_for_tier "$_mr_t")"; done )
}

# SERVES_AWK / serves_tasks — THE ONE READ OF "WHICH CRITERIA A ROW SERVES" (wave-31 T22; REQ-15 AC-15.1, D15,
# A-orch-51). A row serves a criterion when its `serves` cell names the criterion's AC id or the REQ id in the
# Eval design's Requirement column; that two-way read is `serves_hit`, and two verbs call it, never a second reader:
# matrix-render (a criterion's `task:` cell is the one row serving it) and row-landed (the evidence a landing writes
# into every criterion its row serves). The awk functions are concatenated ahead of each verb's program
# (`awk "$SERVES_AWK$MR_AWK"`); they own these globals: nt tid[] serves[] (serves_load), and evh col[] eseen[] ne ec[]
# ereq[] eapp[] eev[] efw[] (eval_row), which the program's own pass resets as its headings go by (evh = 0).
#   serves_load(spec)  spec = `<id><TAB><serves>` per `## Tasks` row, newline-joined (serves_tasks prints it)
#   serves_hit(t, cr)  1 when row index t serves criterion cr (its AC id, or its Requirement in ereq[])
#   eval_row(line)     one `## Eval design` table line: the header row names the columns, a data row fills ereq[] etc.
#   trim(v), cells(line, out)  the table-cell reads both programs share
# Set in hooks/session-poker.sh, before any part loads: SERVES_AWK.

# mr_requirements_file <plan> <repo> -> the requirements file the plan names, when it is a readable file: its
# `requirements:` frontmatter key, else the Step-1 evidence line's `requirements:` field (walls.sh K5's pointer),
# resolved as the gate resolves it (walls.sh resolve_requirements_path: absolute stands, `specs/` is under the docs
# root, anything else under the project root); nothing when neither names a readable file (wave-35 T8; AC-6.4).
mr_requirements_file() {
  local raw abs
  raw="$(plan_frontmatter_get "$1" requirements 2>/dev/null)"
  if [ -z "$raw" ]; then
    raw="$(awk '
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc && /^[[:space:]]*-?[[:space:]]*Step[[:space:]]+1[[:space:]]*:/ {
        if (match($0, /(^|[^-_[:alnum:]])requirements[[:space:]]*:[[:space:]]*/)) {
          v = substr($0, RSTART + RLENGTH); sub(/;.*$/, "", v); sub(/[[:space:]]+$/, "", v); print v
        }
        exit
      }' "$1")"
  fi
  [ -n "$raw" ] || return 0
  case "$raw" in
    /*)      abs="$raw" ;;
    specs/*) abs="$(docs_root "$2")/$raw" ;;
    *)       abs="$2/$raw" ;;
  esac
  [ -f "$abs" ] && [ -r "$abs" ] && printf '%s' "$abs"
  return 0
}

# MR_AWK — matrix-render's one pass over the plan (wave-30 T14; D9). ENVIRON: MR_KEYS (mr_tier_keys), MR_TASKS
# (`<id><TAB><serves>` per ## Tasks row), MR_WALK (the frontmatter walk: value), MR_REQFILE (the requirements file the
# plan names, mr_requirements_file; empty when none), MR_COUNT (the side file: on success
# `<blocks written><TAB><keys added><TAB><blocks unchanged>`, on a refusal `<why><TAB><ids>`). Prints the rendered
# plan; exits 3 no Eval design criteria, 4 no matrix table, 5 a criterion with no matrix row, 6 a tier with no keys.
# The reads follow the gate's: fences skipped, a table cell trimmed, an AC block a flush-left `AC-<id>:` (a list
# bullet tolerated) and the indented lines under it until the next flush-left line (walls.sh `matrix_block`).
# Set in hooks/session-poker.sh, before any part loads: MR_AWK.

# LE_AWK / landing_evidence — A LANDING WRITES ITS CRITERIA'S EVIDENCE (wave-31 T22; REQ-15 AC-15.1 to AC-15.3, D15,
# A-orch-51 ruling 3). `row-landed` is the one writer both landings call (`ready`'s publish and the hand landing), and
# it calls this once the status, the step line and the ledger line are in its copy. The copy gains, in each AC block of
# `## Verification Matrix` that the landed row SERVES (`serves_hit`, the relation matrix-render's `task:` reads; never
# the block's `task:` cell, which names split parents and is corrected by hand at Step 5), an `evidence:` cell reading
# the docs-root-relative path of the row's green log for the suite the block's `eval:` names (`<suite>.test.sh` in
# backticks). The rules, as the pass below keeps them:
#   · the log is the one the landing's own verdict names: the landing record's last `ev=verdict` line for this row,
#     this commit, this suite, `result=green` (LE_LOGS, built by landing_evidence); for a suite the landing REUSED
#     (an `ev=reused` line for this row and commit, lib/line.sh, wave-39 T1; a skip is one, T4), the log of the green
#     verdict its `from=` names for that suite at its `reads=` key, whichever row ran it: the row's green for that
#     suite, so a criterion only such a row serves does not stay pending (wave-39 T2; D5, A-orch-11);
#   · an eval naming a suite the landing did not run, or no suite (a T0 grep), writes nothing;
#   · the cell is written when it reads `pending` or is already a path under `record/<plan>/line/` (which only a
#     landing writes: the newer landing replaces it, AC-15.2); any other value is a hand fill and stays;
#   · a block with no `evidence:` line is left alone: the verb replaces a cell, it adds no key.
# ENVIRON: LE_TASKS (serves_tasks), LE_ROW, LE_LOGS (`<suite><TAB><docs-root-relative path>` per line), LE_SLUG (the
# plan's name), LE_COUNT (a side file: the number of cells written). Prints the plan; the fences, the section
# headings and the AC blocks are read as MR_AWK reads them.
# Set in hooks/session-poker.sh, before any part loads: LE_AWK.

# pv_roster_names_row <row id> -> 0 when a roster of this project holds a launch of the row for this plan, else 1: a
# `roster-state/` row carrying `row=<id>` whose `plan=` is this plan's, or that carries no `plan=` (the rows written
# before it existed). The one question a pending row's Files cell asks before it is the table's (wave-36 T41): a
# launch in flight has a contract, and amend is its verb. Reads the files itself, never through a quitting pipe.
pv_roster_names_row() {
  local rf pb
  pb="$(basename "$PV_PLAN")"
  for rf in "$PV_REPO"/.bionic/tmp/roster-*.state; do
    [ -f "$rf" ] && [ ! -L "$rf" ] || continue
    awk -F'|' -v id="$1" -v pb="$pb" '
      index($0, "roster-state/") == 1 {
        row = ""; plan = ""; has = 0
        for (i = 2; i <= NF; i++) {
          if (index($i, "row=") == 1) row = substr($i, 5)
          else if (index($i, "plan=") == 1) { plan = substr($i, 6); has = 1 }
        }
        n = split(plan, seg, "/"); base = seg[n]
        if (row == id && (!has || base == pb)) found = 1
      }
      END { exit found ? 0 : 1 }' "$rf" && return 0
  done
  return 1
}

  # THE USER'S WRITER CAP (wave-27 T34; REQ-15 AC-15.4; D24; design ledger Δ10). A cap the user
  # chose is a fact, not a reason to repeat on every turn: it is written once into the plan header
  # every reader of the ceiling already reads (`plan_budget_line`, `budget_field` in lib/run.sh: the
  # dispatch wall, the tick and the turn-end wall). `parallel-budget:` keeps its other fields, its
  # `writers=` becomes the user's and its `source=` reads `user`; the frontmatter gains
  # `budget-override: <git user.name> <date> derived=<n> chosen=<n>`, the sibling of
  # `rigor-override:`. `derived=` is the probe's value, read from an override already there so a
  # second cap keeps it, and the one override line is rewritten, never doubled.
  # THE VERB ONLY LOWERS (wave-27 T37; review pass 42 N2, A-orch-112). It takes a reply nothing can
  # verify, so it must not be a way for a model to raise its own cap: a value above the derived
  # ceiling is refused, and raising it is the user's own edit of the plan's `parallel-budget:` line.
  # (T74 narrowed "the derived ceiling" to the cap in force; see below.)
  # A PLAN WITH NO LINE GETS ONE (wave-28 T9; D15, REQ-2 AC-2.10). No plan owes a budget line, so
  # the verb no longer refuses a plan without one: it writes `parallel-budget: writers=<n>
  # source=user` directly below the opening `---`, and `budget-override: <who> <date> chosen=<n>`
  # under it, with no `derived=` because nothing was derived.
  # It goes through the plan transaction every plan verb takes. REFUSED: a value that is not a
  # whole number, or 0 (1); one above the cap in force (1); a reply with a line break (1); a
  # `writers=`/`derived=` on the plan's lines that is not 1 to 4 digits, or a plan with no
  # leading frontmatter to write into (1).
  # The cap in force asked again is the plan transaction's no-op: "already reads so" (0).
  poker_verb_budget() {
    case "$BG_N" in
      ''|*[!0-9]*)
        die "REFUSED — writers=$(clean "$BG_N") is not a whole number of writers; the plan is unchanged."
        exit 1 ;;
    esac
    if [ "${#BG_N}" -gt 9 ]; then
      die "REFUSED — writers=$BG_N is past any machine's budget; the plan is unchanged."
      exit 1
    fi
    BG_N=$((10#$BG_N))
    if [ "$BG_N" -eq 0 ]; then
      die "REFUSED — writers=0 is no budget: a run with no writer slot fills nothing. Name one or more; the plan is unchanged."
      exit 1
    fi
    case "$BG_REPLY" in
      *$'\n'*|*$'\r'*)
        die "REFUSED — the user's reply carries a line break; give it on one line. The plan is unchanged."
        exit 1 ;;
    esac
    plan_verb_open budget
    # THE CAP IN FORCE IS THE PLAN'S OWN (wave-27 T74; review pass 53 N4 ruled, A-orch-145). "At or
    # below the ceiling the machine derived" let a reply undo the user's 3 back up to the probe's 8.
    # The verb now records n only at or below the cap the plan states NOW: the `parallel-budget:`
    # line's `writers=`, the one value every reader of the ceiling reads, which the verb's own
    # override writes and a user's hand edit sets. A raise, by any amount, is the user's own edit.
    # A CEILING THAT IS NOT A NUMBER REFUSES (N5): each `writers=` and `derived=` the verb reads off
    # the frontmatter is one to four digits, or the verb names the line and records nothing; it
    # never compares as "not greater". `derived=` is the probe's value, carried as a record.
    BG_LINES="$(awk '
      NR == 1 && $0 == "---" { f = 1; next }
      f && $0 == "---" { exit }
      f && /^(parallel-budget|budget-override):/ { print }' "$PV_PLAN")"
    BG_HAVE=""; BG_DERIVED=""
    for BG_KF in parallel-budget:writers budget-override:derived; do
      BG_K="${BG_KF%%:*}"; BG_F="${BG_KF#*:}"
      BG_L="$(printf '%s\n' "$BG_LINES" | grep -m1 "^${BG_K}:")" || BG_L=""
      [ -n "$BG_L" ] || continue
      BG_S=" ${BG_L#*:} "; BG_S="${BG_S//$'\t'/ }"
      case "$BG_S" in
        *" ${BG_F}="*) BG_V="${BG_S#* "${BG_F}"=}"; BG_V="${BG_V%% *}" ;;
        *) continue ;;
      esac
      case "$BG_V" in
        [0-9]|[0-9][0-9]|[0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]) : ;;
        *)
          die "REFUSED — the plan's ${BG_K}: line holds a ${BG_F}= that is not one to four digits."
          die "Nothing was recorded; the plan is unchanged. The line: $(clean "$BG_L" | cut -c1-160) (in $PV_PLAN)"
          exit 1 ;;
      esac
      if [ "$BG_F" = writers ]; then BG_HAVE=$((10#$BG_V)); else BG_DERIVED=$((10#$BG_V)); fi
    done
    # THE CAP IN FORCE IS A PERSON'S (wave-28 T9; D15): `budget_cap`, which answers only from a
    # `source=user` or `source=override` line. A probe's `writers=` caps nothing, so the verb
    # records any n over it; the probe's figure is still carried as `derived=`.
    BG_CAP="$(budget_cap "$PV_PLAN")"; BG_CAP="${BG_CAP#writers=}"
    [ -n "$BG_DERIVED" ] || BG_DERIVED="$BG_HAVE"
    if [ -n "$BG_CAP" ] && [ "$BG_N" -gt "$BG_CAP" ]; then
      die "REFUSED — writers=$BG_N is above the cap in force ($BG_CAP): budget only lowers it."
      die "Raising it is the user's own edit of the plan's parallel-budget: line in $PV_PLAN; the plan is unchanged."
      exit 1
    fi
    BG_LINE=1
    case "$BG_LINES" in 'parallel-budget:'*|*$'\n''parallel-budget:'*) : ;; *) BG_LINE=0 ;; esac
    BG_WHO="$(git -C "$PV_REPO" config user.name 2>/dev/null)"
    if [ -z "$BG_WHO" ] || ! plan_verb_value_ok "$BG_WHO"; then
      die "REFUSED — the project has no usable git user name (git config user.name) to record as the one who capped it; the plan is unchanged."
      exit 1
    fi
    BG_OVR="budget-override: $BG_WHO $(date -u +%Y-%m-%d)${BG_DERIVED:+ derived=$BG_DERIVED} chosen=$BG_N"
    # THE VALUES GO IN THROUGH THE ENVIRONMENT, as approve's line does: `-v` would read a backslash
    # in a user name as an escape.
    if ! BG_OVR="$BG_OVR" BG_N="$BG_N" BG_LINE="$BG_LINE" awk '
      NR == 1 && $0 == "---" {
        f = 1; print
        if (ENVIRON["BG_LINE"] == "0") {
          print "parallel-budget: writers=" ENVIRON["BG_N"] " source=user"
          print ENVIRON["BG_OVR"]; done = 1
        }
        next
      }
      f && $0 == "---" { f = 0; print; next }
      f && /^budget-override:/ { next }
      f && !done && /^parallel-budget:/ {
        v = $0; sub(/^parallel-budget:[ \t]*/, "", v)
        n = split(v, w, /[ \t]+/); out = ""; wr = 0; src = 0
        for (i = 1; i <= n; i++) {
          if (w[i] == "") continue
          if (!wr && w[i] ~ /^writers=/) { w[i] = "writers=" ENVIRON["BG_N"]; wr = 1 }
          else if (!src && w[i] ~ /^source=/) { w[i] = "source=user"; src = 1 }
          out = out (out == "" ? "" : " ") w[i]
        }
        if (!wr) out = "writers=" ENVIRON["BG_N"] (out == "" ? "" : " ") out
        if (!src) out = out " source=user"
        print "parallel-budget: " out
        print ENVIRON["BG_OVR"]
        done = 1; next
      }
      { print }
      END { if (!done) exit 1 }' "$PV_PLAN" > "$PV_NEW" 2>/dev/null; then
      die "REFUSED — $PV_PLAN has no leading frontmatter to write the cap into; the plan is unchanged."
      exit 1
    fi
    plan_verb_swap budget "writers=$BG_N (source=user)" writer
    say "budget — writers=$BG_N source=user and $BG_OVR written to $PV_PLAN; dry-committed first. The dispatch wall, the tick and the turn-end wall read it from the header."
    exit 0
  }

  # THE CONTRACT CHANGE (wave-20 T9; REQ-4, AC-4.1/4.2; spec D4, ledger Δ10). A writer's
  # Files:, Suites: and Re-executes: are read from its roster row, captured at dispatch —
  # editing the plan row changes nothing — and until this verb the only way to widen one was
  # a re-dispatch. `amend` appends a SUCCESSOR row, copied from the name's latest
  # (`row_copy_args`, the copy `extend` takes), with each addition merged in: a union, old
  # members first, never a narrowing. `launched_at=` and `tool_use_id=` are the copy's; the
  # identity — `status=`, `agent_id=`, `teammate_id=` — is the agent's latest identified
  # self (`identity_args`, wave-22 T1, D1), because the budget wall keys on the id, NOT the
  # name, and a teammate's latest row can carry none. The one rule is
  # payload/scripts/lib/roster.sh's, above `roster_row_for_id`; the success line asks that
  # function whether the wall will read the row just written (D3) before it says so.
  # `amended=<iso> <reason>` records when and why; `session=` who.
  #
  # THE MERGED FIELDS ARE JUDGED BY THE DISPATCH WALL'S GRAMMAR (Δ10). The verb builds the
  # span a brief carrying the merged contract would hold — `Files:`, `Suites:`,
  # `Re-executes:` — and hands it to `brief_validate_fields` with the row's own role and its
  # `questions=` as a `Questions:` line, so the three-run cap binds a reader holding the
  # `evidence` question here as it does at dispatch (`dp_reads_evidence`, lib/brief.sh). The old
  # set plus the added suites is the budget, as the brief named it. A row 1.14.0's map DERIVED is
  # read the same way: nothing re-derives it (the map is deleted, wave-31 T23, REQ-4 AC-4.2), and
  # it keeps its `suites_source=` label.
  #
  # THE TARGET is a name, or an agent id (wave-27 T38): an id a named row carries amends that
  # row; an id no row carries, of an agent of this session, is recorded by `amend_unplaced`.
  #
  # REFUSED: no session key (3), an unengaged session (decides nothing, 0), no row of the
  # name and no agent of the id, a CLOSED row — `roster_open_names`, the one close predicate: an ack later than the
  # latest launch — and a change the row already carries (1), and anything the grammar
  # refuses (1). A subagent cannot reach this verb at all: the Bash wall refuses `amend`,
  # `extend` and `task-add` in any payload carrying an `agent_id` (payload/scripts/lib/walls.sh).
  poker_verb_amend() {
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "An amendment answers for ONE session's roster, so without the key there is nothing to write."
      exit 3
    fi
    if ! engaged_session "$(project_root "$PWD")" "$SESSION_ID"; then
      say "NOT-ENGAGED — this session has not invoked /bionic:canonical-sdlc; nothing decided"
      exit 0
    fi
    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    ROSTER_FILE="$REPO_REAL/.bionic/tmp/roster-${SESSION_ID}.state"
    if [ ! -f "$ROSTER_FILE" ] || [ -L "$ROSTER_FILE" ]; then
      die "REFUSED — no row named $AMEND_NAME: this session has no roster at $ROSTER_FILE."
      exit 1
    fi
    # Any `roster-state/` row, as `identity_args` reads (wave-22 T13; critic-3598752 I4).
    AM_ROW="$(grep '^roster-state/' "$ROSTER_FILE" 2>/dev/null \
      | grep -F "|name=${AMEND_NAME}|" | tail -1)"
    # ---- BEGIN amend by agent id (wave-27 T38; review pass 8 F3) ----
    # THE TARGET A BUDGET REFUSAL PRINTS FOR AN AGENT NO ROW CARRIES is its agent id: a start the
    # recorder could not place (two launches of its type, or a type that is not a bionic: role) has
    # no row until its launch call returns, and a foreground call returns when it has finished. So
    # `amend` reads its target as a name first and as an agent id second. An id a named row carries
    # amends that row. An id no row carries, that ran as an agent of this session (its transcript
    # is on disk), gets a row of its own: `status=unplaced`, named by the id, carrying the added
    # suites and runs and no contract (a waiver says so, so no verdict judges it, and no reader of
    # live rows counts it). The budget wall keys on the id, so it reads that row from the next call.
    # An id that is neither is refused, saying why; this verb never exits 0 having changed nothing.
    # AFTER THE PLACING (wave-27 T37; review pass 36 N2): an `unplaced` row named by the id, written
    # before the agent was placed, is not the id's row any more once a placed row carries the id
    # after it. The amend goes to the placed row, and the set the unplaced row recorded goes with
    # it as additions, so one row speaks for the agent and holds both; no second unplaced row is
    # written to shadow the placed one.
    if [ -z "$AM_ROW" ] || [ "$(line_field "$AM_ROW" status)" = unplaced ]; then
      AM_IDROW="$(roster_row_for_id "$ROSTER_FILE" "$AMEND_NAME")" || AM_IDROW=""
      AM_IDNAME="$(line_field "$AM_IDROW" name)"
      if [ -n "$AM_IDNAME" ] && [ "$(line_field "$AM_IDROW" status)" != unplaced ] \
         && { [ -z "$AM_ROW" ] || [ "$AM_IDNAME" != "$AMEND_NAME" ]; }; then
        if [ -n "$AM_ROW" ]; then
          AM_UP_SA="$(line_field "$AM_ROW" suites_allowed)"
          [ "$AM_UP_SA" = none ] || AMEND_SUITES="${AMEND_SUITES}${AM_UP_SA}"$'\n'
          if row_has_key "$AM_ROW" re_executes; then
            AMEND_RUNS="${AMEND_RUNS}$(poker_marked_runs "$(clean "$(line_field "$AM_ROW" re_executes)" re_executes)")"$'\n'
          fi
        fi
        AMEND_NAME="$AM_IDNAME"
        AM_ROW="$(grep '^roster-state/' "$ROSTER_FILE" 2>/dev/null \
          | grep -F "|name=${AMEND_NAME}|" | tail -1)"
      else
        amend_unplaced "$AMEND_NAME" "$AM_IDROW"
        exit $?
      fi
    fi
    # ---- END amend by agent id ----
    if [ -z "$AM_ROW" ]; then
      die "REFUSED — no row named $AMEND_NAME on this session's roster ($ROSTER_FILE)."
      exit 1
    fi
    AM_OPEN="$(roster_open_names "$ROSTER_FILE" "$REPO_REAL/.bionic/tmp/sweeper-${SESSION_ID}.state" "$SESSION_ID")"
    if ! grep -qxF -- "$AMEND_NAME" <<< "$AM_OPEN"; then
      die "REFUSED — $AMEND_NAME is closed: it was acked after its latest launch, or holds no live row. A closed contract is not amended; dispatch the work again."
      exit 1
    fi
    if ! poker_brief_load; then
      die "REFUSED — the contract grammar (lib/brief.sh) cannot be loaded from $BIONIC_LIB; nothing was written."
      exit 2
    fi

    AM_ROLE="$(line_field "$AM_ROW" subagent_type)"
    AM_OLD_FILES="$(line_field "$AM_ROW" files)"
    AM_OLD_SA="$(line_field "$AM_ROW" suites_allowed)"
    AM_OLD_SRC="$(line_field "$AM_ROW" suites_source)"
    AM_OLD_RUNS=""
    row_has_key "$AM_ROW" re_executes && AM_OLD_RUNS="$(clean "$(line_field "$AM_ROW" re_executes)" re_executes)"

    # THE ADDITIONS AS THE GRAMMAR READS THEM, alone: what each flag contributes once lifted.
    # The Files: reader is the dispatch wall's (wave-27 T29, T42; REQ-12, D21), so
    # `--files+ CONTEXT.md` is the path a dispatch would have recorded.
    # EACH --files+ VALUE ON ITS OWN (wave-27 T34; review pass 19 should-fix 2, A-orch-70), as the
    # dispatch wall reads one line: joined into one Files: line, a ` #` note in one value hid every
    # later one. A value the reader records nothing from goes to the grammar as typed, below.
    AM_ADD="$(lift_contract_fields "$(poker_brief_span "" "$AMEND_SUITES" "" "$AMEND_RUNS")" "$AM_ROLE")"
    AM_ADD_FILES=""; AM_TYPED=""
    while IFS= read -r AM_F; do
      [ -n "$AM_F" ] || continue
      AM_FL="$(brief_field "$(lift_contract_fields "Files: $AM_F" "$AM_ROLE")" files)"
      AM_ADD_FILES="$(poker_union , "$AM_ADD_FILES" "$AM_FL")"
      if [ -n "$AM_FL" ]; then AM_TYPED="${AM_TYPED}$(printf '%s' "$AM_FL" | tr ',' '\n')"$'\n'
      else AM_TYPED="${AM_TYPED}${AM_F}"$'\n'; fi
    done <<< "$AMEND_FILES"
    AM_NEW_FILES="$(poker_union , "$AM_OLD_FILES" "$AM_ADD_FILES")"
    AM_Q="$(line_field "$AM_ROW" questions)"

    # THE BUDGET IS THE OLD SET PLUS THE ADDED SUITES, carried into the span as declared, whatever
    # the row's label. `none` is a waiver, and it yields to the first suite actually added.
    AM_DECL="$(poker_union ' ' "$AM_OLD_SA" "$(printf '%s' "$AMEND_SUITES" | tr '\n,' '  ')")"
    case " $AM_DECL " in
      *" none "*) [ "$AM_DECL" = none ] \
                    || AM_DECL="$(printf '%s' "$AM_DECL" | tr ' ' '\n' | awk '$0 != "none" && $0 != ""' | tr '\n' ' ')"
                  AM_DECL="${AM_DECL% }" ;;
    esac

    # The additions go into the span as typed, beside the merged set, so an entry the reader
    # does not read as a path reaches the grammar and is refused by name, never dropped.
    AM_SPAN="$(poker_brief_span "$(printf '%s' "$AM_NEW_FILES" | tr ',' '\n')"$'\n'"$AM_TYPED" "$AM_DECL" "$AM_OLD_RUNS" "$AMEND_RUNS")"
    # THE ROW'S QUESTIONS GO WITH IT (wave-27 T34; T15's report item 1, A-orch-73), so a reader
    # holding `evidence` meets the cap a dispatch of it would.
    [ -n "$AM_Q" ] && AM_SPAN="${AM_SPAN}"$'\n'"Questions: ${AM_Q//,/, }"
    AM_LIFT="$(lift_contract_fields "$AM_SPAN" "$AM_ROLE")"
    POKER_BRIEF_FACTS=""; POKER_BRIEF_WORDS=""
    AM_RC=0
    brief_validate_fields "$AM_LIFT" "$AM_ROLE" "$REPO_REAL" poker_brief_sink || AM_RC=$?
    AM_SA="$BRIEF_SUITES_ALLOWED"; AM_SRC="$BRIEF_SUITES_SOURCE"
    if [ "$AM_RC" -ne 0 ]; then
      die "REFUSED — a dispatch carrying $AMEND_NAME's amended contract would be refused; nothing was written:"
      printf '%s' "$POKER_BRIEF_WORDS" >&2
      exit 1
    fi

    # A waiver that nothing replaced stays the waiver.
    [ -n "$AM_SA" ] || AM_SA="$AM_OLD_SA"
    AM_SRC="${AM_OLD_SRC:-$AM_SRC}"
    AM_NEW_RUNS="$AM_OLD_RUNS"
    AM_OLD_RUN_SET="$(poker_marked_runs "$AM_OLD_RUNS")"
    while IFS= read -r AM_R; do
      [ -n "$AM_R" ] || continue
      grep -qxF -- "$AM_R" <<< "$AM_OLD_RUN_SET" && continue
      AM_NEW_RUNS="${AM_NEW_RUNS:+$AM_NEW_RUNS }\`${AM_R}\`"
    done <<EOF
$(poker_marked_runs "$(brief_field "$AM_ADD" re_executes)")
EOF

    if [ "$AM_NEW_FILES" = "$AM_OLD_FILES" ] && [ "$AM_SA" = "$AM_OLD_SA" ] \
       && [ "$AM_NEW_RUNS" = "$AM_OLD_RUNS" ]; then
      die "REFUSED — this amend changes nothing: every addition is already on $AMEND_NAME's row, or is not a path, suite or run the dispatch grammar reads. Nothing was written."
      exit 1
    fi

    row_copy_args "$AM_ROW" "$SESSION_ID"
    identity_args "$ROSTER_FILE" "$AMEND_NAME" "$AM_ROW"
    AM_ARGS=("${ROW_COPY_ARGS[@]}")
    AM_ARGS+=(${POKER_ID_ARGS[@]+"${POKER_ID_ARGS[@]}"})
    { [ -n "$AM_NEW_FILES" ] || row_has_key "$AM_ROW" files; } && AM_ARGS+=("files=$AM_NEW_FILES")
    if [ -n "$AM_SA" ] || row_has_key "$AM_ROW" suites_allowed; then
      AM_ARGS+=("suites_allowed=$AM_SA")
      [ -n "$AM_SRC" ] && AM_ARGS+=("suites_source=$AM_SRC")
    fi
    { [ -n "$AM_NEW_RUNS" ] || row_has_key "$AM_ROW" re_executes; } && AM_ARGS+=("re_executes=$AM_NEW_RUNS")
    AM_ARGS+=("amended=$(iso_now) ${AMEND_BY:+widened-by: $AMEND_BY }$(clean "$AMEND_REASON")")
    AM_NEW_ROW="$(roster_row "${AM_ARGS[@]}")" || AM_NEW_ROW=""
    if [ -z "$AM_NEW_ROW" ]; then
      die "REFUSED — could not build the amended row for $AMEND_NAME."
      exit 2
    fi
    printf '%s\n' "$AM_NEW_ROW" >> "$ROSTER_FILE" 2>/dev/null || {
      die "REFUSED — could not write to $ROSTER_FILE."
      exit 2
    }
    # THE SUCCESS LINE CHECKS ITSELF (wave-22 T1; REQ-1 AC-1.6, D3). It used to print
    # unconditionally, and the wall it promised went on reading the pre-amend row (wave-22
    # seed). Now the verb asks `roster_row_for_id` — the budget wall's own pick, one function
    # in payload/scripts/lib/roster.sh — whether the row it just wrote is the row the wall
    # reads for this agent's id. No id yet: no wall keys on this agent before it is
    # identified (the budget arm's actor is the transcript id), and the recorder's
    # `identified` row inherits this successor whole, so the line says when, not now.
    # AN ID-LESS ROW (wave-27 T38): the set is recorded, on the row the identification copies — the
    # recorder's start join, or its launch call's return (ARM 2 copies the launch's last row). An
    # agent of it already running unplaced is not that row's until then; its refusal prints its id.
    if [ -z "$POKER_ID" ]; then
      say "amended — the walls read this row once $AMEND_NAME is identified, at its start or its launch call's return; an agent already running unplaced is amended by the agent id its refusal prints"
      exit 0
    fi
    AM_PICK="$(roster_row_for_id "$ROSTER_FILE" "$POKER_ID")" || AM_PICK=""
    if [ "$AM_PICK" != "$AM_NEW_ROW" ]; then
      AM_WROTE_ID="$(line_field "$AM_NEW_ROW" agent_id)"
      if [ -z "$AM_PICK" ]; then
        AM_WHY="no row carries that id"
      elif [ "$AM_WROTE_ID" != "$POKER_ID" ]; then
        AM_WHY="the row amend wrote carries agent_id=${AM_WROTE_ID:-(empty)}, so a wall keyed on $POKER_ID never reaches it"
      else
        AM_WHY="a later row carrying that id was written after it"
      fi
      die "amend written, but the budget wall reads $(line_field "$AM_PICK" status) row for $POKER_ID — $AM_WHY"
      exit 1
    fi
    # The stop wall and observe pick an id's row from `confirmed|identified` rows only
    # (stop-guard.sh), so a successor that copied a `duplicate-start` row is read by the budget
    # wall alone — the line names only the walls that read it (wave-22 T10; review 4).
    case "$(line_field "$AM_NEW_ROW" status)" in
      confirmed|identified) AM_WALLS="the stop and budget walls read" ;;
      *)                    AM_WALLS="the budget wall reads" ;;
    esac
    say "amended — $AMEND_NAME: files=${AM_NEW_FILES:-(none)} suites=${AM_SA:-(none)}${AM_NEW_RUNS:+ runs=$AM_NEW_RUNS}; $AM_WALLS this row from now on."
    exit 0
  }

  # THE ROW-ADD VERB (wave-20 REQ-5, AC-5.3; Δ5, research D1 §3). A schedule change is a
  # TRANSACTION: `units_add_row` projects the row onto a COPY of the bound plan (the row and its
  # `- <id>:` line, and no other row), the copy is
  # judged twice — by `units_validate`, and by a dry `git commit` through the REAL
  # hooks/bash-walls.sh — and only a copy both admit is moved over the plan. On any refusal
  # the plan is byte-identical and the words that refused it print. The precedent is
  # close-out.sh's D5: a script writes a lifecycle artifact only where a gate validates what
  # it wrote. Nothing else judges a Bash write of the plan: the governing-skill hook sees
  # Write and Edit only.
  #
  # THE TRANSACTION IS SHARED (wave-24 T15): `plan_verb_open` and `plan_verb_swap`, above the
  # verbs, carry the dry commit — a writer's, judged by the task arms, so the dry copy carries
  # `current: 4` when the run is past it and the copy swapped in keeps the run's own
  # `current:` — the copy's own engagement marker, the checksum and the swap. What is task-add's
  # alone is below: a run below Step 4 is refused, the Files cell is judged by the dispatch
  # grammar, and the projection is `units_add_row`, judged by `units_validate` before the gate.
  poker_verb_task_add() {
    plan_verb_open task-add
    TA_PLAN="$PV_PLAN"; REPO_REAL="$PV_REPO"
    TA_CUR="${PV_CUR%[ab]}"
    case "$TA_CUR" in
      ''|*[!0-9]*)
        die "REFUSED — $TA_PLAN has current: ${TA_CUR:-(none)}; task-add changes a wave plan past Step-3 approval, whose current: is a step number."
        exit 1 ;;
    esac
    if [ "$TA_CUR" -lt 4 ]; then
      die "REFUSED — $TA_PLAN is at current: $TA_CUR; before Step-3 approval the plan is written by hand and reviewed, not added to."
      exit 1
    fi

    # A READ NEEDS A COLUMN TO GO IN (wave-26 T59; REQ-5 AC-5.4). The projection drops a value
    # its table has no column for, so a reads operand on a table without one would be accepted
    # and lost, and the row would wait on nothing it declared. Refused instead, in one line.
    # `—` (or `-`, or empty) declares nothing and is the nine-operand form; in a reads table it
    # is the cell `—`, which the readiness program reads as the kind's default (lib/units.sh).
    case "$TA_READS" in
      ''|'—'|'-') : ;;
      *)
        if ! units_has_column "$TA_PLAN" reads; then
          die "REFUSED — the ## Tasks table of $TA_PLAN has no reads column, so the reads operand '$(clean "$TA_READS")' has nowhere to go; add the column, or name what $TA_ID waits for in its deps. The plan is unchanged."
          exit 1
        fi
        ;;
    esac

    # A READER ROW WRITES ITS RECORD (wave-35 T8; REQ-6 AC-6.1; D15). A verify, test or review row whose Files
    # name no record artifact gets <record dir>/<id>.md in its cell, the artifact `brief` gives it, so a row that
    # reads that record waits on this one (the validator refuses a record read no row's Files cover).
    # THE FILES CELL IS JUDGED BY THE DISPATCH GRAMMAR (wave-20 T9; D4, Δ10; T6 carry-over).
    # The cell becomes a brief's `Files:` line at dispatch, so it is read here exactly as the
    # dispatch wall will read it: a cell the lift reads as no path — a template slot, a bare
    # word — is refused now, in the grammar's words, rather than forty minutes later at the
    # dispatch of a row nobody can fix from the table. `—` is the table's "none" and declares
    # nothing to judge. ONE FACT IS THE BRIEF'S, NOT THE CELL'S: a `Files:` line alone names
    # no suite. A dispatch answers it with a `Suites:` or `Re-executes:` line, which the plan
    # row has no column for, so here it is a note and the row goes in.
    poker_files_cell "$TA_ID" "$TA_KIND" "$TA_AGENT" "$TA_FILES" "$REPO_REAL" "$TA_PLAN" || exit $?
    TA_FILES="$PFC_OUT"; TA_ART="$PFC_ART"

    # A ROW REVIEW MADE UNASKED (wave-30 T21; REQ-10 AC-10.1, AC-10.2; D4, Δ3). Three guards, whatever the
    # policy says, each a refusal with the plan byte-identical: (1) the rating is inside the plan's
    # fix-policy:, read verbatim (lib/run.sh `fix_policy_covers`; S1,S2-on when absent); (2) the row is
    # under fix-cap: (lib/units.sh `units_fix_cap`, the level's default when absent), counted off the
    # ledger lines' born: markers (`units_born`, the one place the count reads); (3) no Files path outside
    # the record already carries three review-born rows: the fourth fix on one component stops the run.
    # In-diff is the orchestrator's judgment and "never re-read" the proof's; neither is this verb's.
    # THE FINDINGS A ROW ANSWERS (wave-33 T13; REQ-5, D6): each is a finding of a reading the plan registered,
    # read from its record (`finding_read`); the row's rating is the gravest of them, the lowest S and then on
    # before off, and the guards below hold it as they hold a typed rating.
    # A FINDING THE PERSON MOVED TO FIX IS ASKED, NOT UNASKED (wave-35 T34; A-orch-48): its effective priority
    # (`finding_read`'s FR_P, a `moved:` line) is fix, and `disposition` tells the orchestrator to born a row of
    # it, so the policy guard holds each finding to the policy OR to the person's move, the first that is
    # neither refused with the remedy. The marker keeps the reader's rating, never re-rated.
    TA_BORN_MARK=""; TA_OFF=""; TA_OFF_RATING=""
    TA_POL="$(plan_frontmatter_get "$TA_PLAN" fix-policy)"
    if [ -z "$TA_POL" ] && ! grep -qE '^[[:space:]]*fix-policy[[:space:]]*:' "$TA_PLAN" 2>/dev/null; then
      TA_POL="$FIX_POLICY_DEFAULT"
    fi
    # A FINDING THE PERSON MOVED TO DEFER IS BORN NO ROW (wave-36 T8; REQ-4 AC-4.5, D10): its newest move
    # (lib/proof.sh `proof_move_line`) is the person's last word, whatever its reader's rating, so an S2 on the
    # fix-policy admits is refused as an S3 off is, naming the move, before the policy is asked.
    if [ -n "$TA_BORN_IDS" ]; then
      TA_BEST=""
      for TA_BID in $(printf '%s' "$TA_BORN_IDS" | tr ',' ' '); do
        if ! finding_read "$TA_PLAN" "$REPO_REAL" "$TA_BID"; then
          die "task-add refused — $FR_WHY; the plan is unchanged."
          exit 1
        fi
        if [ "$(_proof_moved_to "$TA_PLAN" "$TA_BID")" = defer ]; then
          die "task-add refused — $(clean "$TA_BID") was moved to defer, and its newest move stands: $(clean "$(proof_move_line "$TA_PLAN" "$TA_BID")"); the plan is unchanged. To fix it after all: disposition $(clean "$TA_BID") fix '<their words>' '<why>', then task-add again."
          exit 1
        fi
        TA_RANK="${FR_S#S}$( [ "$FR_R" = on ] && printf 0 || printf 1 )"
        if [ -z "$TA_BEST" ] || [ "$TA_RANK" -lt "$TA_BEST" ]; then TA_BEST="$TA_RANK"; TA_BORN="review $FR_S $FR_R"; fi
        if [ -z "$TA_OFF" ] && [ "$FR_P" != fix ] && ! fix_policy_covers "$TA_POL" "$FR_S" "$FR_R"; then
          TA_OFF="$TA_BID"; TA_OFF_RATING="review $FR_S $FR_R"
        fi
      done
      TA_BORN_MARK=" of=$TA_BORN_IDS"
      if [ -n "$TA_OFF" ]; then
        die "task-add refused — born: $TA_OFF_RATING is outside fix-policy: $TA_POL; the plan is unchanged; the finding goes to the review findings disposition (AC-10.3). To fix $(clean "$TA_OFF") anyway: disposition $(clean "$TA_OFF") fix '<their words>' '<why>', then task-add again."
        exit 1
      fi
    fi
    TA_CELL_TASK="$TA_TASK"
    if [ -n "$TA_BORN" ]; then
      TA_RATING="${TA_BORN#review }"
      if [ -z "$TA_BORN_IDS" ] && ! fix_policy_covers "$TA_POL" "${TA_RATING% *}" "${TA_RATING#* }"; then
        die "task-add refused — born: $TA_BORN is outside fix-policy: $TA_POL; the plan is unchanged; the finding goes to the review findings disposition (AC-10.3)."
        exit 1
      fi
      if ! TA_CAP="$(units_fix_cap "$TA_PLAN")"; then
        die "task-add refused — born: $TA_BORN has no cap to count against: fix-cap: '$(plan_frontmatter_get "$TA_PLAN" fix-cap)' is no count, or the plan names no rigor: to default it from; the plan is unchanged."
        exit 1
      fi
      TA_BORN_ROWS="$(units_born "$TA_PLAN")"
      TA_NBORN="$(printf '%s' "$TA_BORN_ROWS" | awk 'NF { n++ } END { print n + 0 }')"
      if [ "$TA_NBORN" -ge "$TA_CAP" ]; then
        die "task-add refused — review-born rows: $TA_NBORN of cap $TA_CAP; this finding goes to the review findings disposition (AC-10.3)."
        exit 1
      fi
      while IFS= read -r TA_PATH; do
        [ -n "$TA_PATH" ] || continue
        case "$TA_PATH" in .bionic/*|record/*) continue ;; esac
        TA_FIXERS="$(printf '%s\n' "$TA_BORN_ROWS" | while IFS=$'\t' read -r TA_BID _ TA_BFILES; do
            [ -n "$TA_BID" ] || continue
            _units_split_tokens "$TA_BFILES" | grep -Fx -- "$TA_PATH" >/dev/null && printf '%s\n' "$TA_BID"
          done)"
        if [ "$(printf '%s' "$TA_FIXERS" | awk 'NF { n++ } END { print n + 0 }')" -ge 3 ]; then
          die "task-add refused — a fourth fix on $TA_PATH: $(printf '%s' "$TA_FIXERS" | paste -sd, - | sed 's/,/, /g') already fix it; stop the run (AC-10.2)"
          exit 1
        fi
      done <<EOF
$(_units_split_tokens "$TA_FILES")
EOF
      TA_CELL_TASK="$TA_TASK · born: review"
    fi
    # A FLOOR-BORN MARKER NAMES ITS RED (wave-36 T42; D9, Δ8): the marker is admitted only with a red the machine
    # recorded behind it (`born_floor_backing`), and it records which, ` of=floor` or ` of=standing@<12-hex>`.
    TA_BORN_OF=""
    if [ -n "$TA_BORN_SUITE" ]; then
      if ! born_floor_backing "$TA_PLAN" "$REPO_REAL" "$TA_BORN_SUITE"; then
        die "task-add refused — born: regression $TA_BORN_SUITE names no red the machine recorded; it is admitted when the plan's regression proof owes $TA_BORN_SUITE (it owes ${BFB_OWED:-nothing}; proof-add regression, from a whole run that left it red) or when the landing record holds a standing event for $TA_BORN_SUITE at a commit on ${BFB_BRANCH:-the working branch}; the plan is unchanged."
        exit 1
      fi
      TA_BORN_OF="$BFB_OF"; TA_CELL_TASK="$TA_TASK · born: regression"
    fi

    if ! units_add_row "$TA_PLAN" "$TA_ID" "$TA_STEP" "$TA_KIND" "$TA_CELL_TASK" "$TA_AGENT" \
         "$TA_DEPS" "$TA_SIZE" "$TA_SERVES" "$TA_FILES" "$TA_READS" "${TA_BORN:+$TA_BORN$TA_BORN_MARK}${TA_BORN_SUITE:+regression $TA_BORN_SUITE of=$TA_BORN_OF}" > "$PV_NEW" 2>/dev/null || [ ! -s "$PV_NEW" ]; then
      die "REFUSED — $TA_PLAN carries no ## Tasks table or no ## SDLC State section to add $TA_ID to; the plan is unchanged."
      exit 1
    fi

    TA_VIOL="$(units_validate "$PV_NEW" 2>&1)"
    if [ -n "$TA_VIOL" ]; then
      die "REFUSED — with $TA_ID added, the ## Tasks table breaks the Task invariants; the plan is unchanged:"
      printf '%s\n' "$TA_VIOL" >&2
      # A STEP-7 DOC ROW IS NO LONGER REFUSED FOR ITS APPROVAL READ (wave-35 T5; D13): the release
      # approval is the integrate row's read, so the one-retry wave-33 T7 printed here is gone with it.
      exit 1
    fi

    plan_verb_swap task-add "$TA_ID added" writer
    say "task-add — $TA_ID added to $TA_PLAN: the row and its - $TA_ID: line; validated and dry-committed first."
    [ -z "$TA_ART" ] || say "task-add — $TA_ID is a $TA_KIND row: its Files carry its record artifact, $TA_ART."
    [ -z "$TA_BORN" ] || say "task-add — $TA_ID is review-born ($TA_BORN): review-born rows: $((TA_NBORN + 1)) of cap $TA_CAP; say so in the review findings disposition (AC-10.2)."
    [ -z "$TA_BORN_SUITE" ] || say "task-add — $TA_ID is regression-born ($TA_BORN_SUITE), backed by of=$TA_BORN_OF: its landing holds every review's cover (D9), and it counts against no fix-cap."
    # A ROW NOW ANSWERS EACH FINDING IT NAMES, so the person owes no ruling on it: its owed item closes.
    for TA_BID in $(printf '%s' "$TA_BORN_IDS" | tr ',' ' '); do
      poker_owed_close "$REPO_REAL" "$(finding_owed_key "$TA_BID")" "task-add $TA_ID"
      say "task-add — $TA_ID answers $(clean "$TA_BID")"
    done
    # A ROW THAT LANDS ON NOTHING IS FIXED BY THE REGRESSION (wave-39 T19; REQ-14 AC-14.2, D9): a row whose lands-on cell is
    # none or absent writes no verdict at its landing, so lib/proof.sh `proof_fixed` counts its findings fixed only once a
    # green regression stands at a head past its landing. Said at the row's birth, where the author can still name a suite.
    if [ -n "$TA_BORN_IDS" ]; then
      TA_LANDS="$(poker_brief_cell "$TA_PLAN" Tasks "$TA_ID" lands-on)" || TA_LANDS=""
      case "$TA_LANDS" in none|none[[:space:]]*) TA_LANDS="" ;; esac
      ! poker_brief_none "$TA_LANDS" \
        || say "task-add — $TA_ID lands none — counts on the next green regression: no landing verdict will name it, so its findings are fixed once a green regression stands at a head past its landing (D9)."
    fi
    # THE SUSPECT TEST AT AUTHORING (wave-30 T16; REQ-12 AC-12.2, D14a): the row is in; a dependency
    # that shares no file with its holder is named, with the line that would loosen it, never run.
    suspect_lines "$TA_PLAN" "$TA_ID" | while IFS=$'\t' read -r _ _ TA_SUSPECT; do say "$(clean_whole "$TA_SUSPECT")"; done
    exit 0
  }

  # THE ROW-CELL VERBS (wave-24 T15; REQ-9 AC-9.1/9.2, D14). `task-set` sets cells of a
  # `## Tasks` row, `ledger-set` of a `## Dispatch ledger` row, and `ledger-add` appends a ledger
  # row; each through `units_table_cells`, on the shared transaction. A `## Tasks` column is any
  # the header carries by `units_has_column`, except `id`, the key the row is found by, and, for a row with a
  # launch behind it, `Files`: a dispatched agent's CONTRACT once it is on the roster (editing the plan row
  # changes nothing a wall reads), so the refusal names `amend`, the verb that widens it. A PENDING row no
  # roster names has no contract, and `files=<list>` is the table's to set (wave-36 T41; the pre-pass below). `task-set` is judged by `units_validate` before the
  # gate, as `task-add` is: a status, step or deps cell is a schedule change.
  #
  # `<col>+=<token>` APPENDS, for the two cells that list what a row waits on, `reads` and `deps`: the
  # token goes after what the cell holds, an empty reads cell standing for its kind's default (units.sh
  # `units_cell_append`), and a cell already naming it is left as it is. It is how a ready row is made to
  # wait, by a read of the record of the row it waits on or of a decision nobody has ruled, without
  # dropping the reads that already hold it. Any other column takes `=`.
  poker_verb_task_set() {
    # THE ROWS A CALL SETS (wave-33 T7). One entry per row: its id and its pairs, joined by the unit
    # separator. A ledger verb names one row; task-set's groups name many, each id with its group's pairs.
    PV_SETS=()
    if [ "$VERB" = task-set ]; then
      for _pv_g in "${PV_GROUPS[@]}"; do
        _pv_ids="${_pv_g%%$'\037'*}"; _pv_rest="${_pv_g#*$'\037'}"
        while [ -n "$_pv_ids" ]; do
          _pv_i="${_pv_ids%%,*}"
          case "$_pv_ids" in *,*) _pv_ids="${_pv_ids#*,}" ;; *) _pv_ids="" ;; esac
          _pv_i="$(printf '%s' "$_pv_i" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
          PV_SETS+=("$_pv_i"$'\037'"$_pv_rest")
        done
      done
    else
      _pv_rest=""
      for _pv_a in ${PV_PAIRS[@]+"${PV_PAIRS[@]}"}; do _pv_rest="${_pv_rest:+$_pv_rest$'\037'}$_pv_a"; done
      PV_SETS=("$PV_ID"$'\037'"$_pv_rest")
    fi
    # pv_set_pairs <set> -> PV_SET_ID and PV_SET_PAIRS, the set taken apart.
    pv_set_pairs() {
      local r="${1#*$'\037'}" p
      PV_SET_ID="${1%%$'\037'*}"; PV_SET_PAIRS=()
      while [ -n "$r" ]; do
        p="${r%%$'\037'*}"
        case "$r" in *$'\037'*) r="${r#*$'\037'}" ;; *) r="" ;; esac
        PV_SET_PAIRS+=("$p")
      done
    }
    # THE ID AND THE COLUMN NAME ARE OPERANDS TOO (wave-24 T27; Step-6 review C1). `ledger-add`
    # writes its id into the new row's first cell, and a line break there forged a plan line
    # the commit gate admitted. The id is one token of the grammar every ledger row already
    # carries (`T7`, `T22b`, `T17-critic`); a name is held to the values' own rule.
    for _pv_s in "${PV_SETS[@]}"; do
      pv_set_pairs "$_pv_s"
      if ! plan_verb_id_ok "$PV_SET_ID"; then
        die "REFUSED — '$(clean "$PV_SET_ID")' is not one row id: an id is one token of letters, digits, '.', '_' or '-', beginning with a letter or a digit. The plan is unchanged."
        exit 1
      fi
      for _pv_a in ${PV_SET_PAIRS[@]+"${PV_SET_PAIRS[@]}"}; do
        _pv_n="${_pv_a%%=*}"
        if ! plan_verb_value_ok "$_pv_n"; then
          die "REFUSED — the column name '$(clean "$_pv_n")' carries a |, a tab or a line break, which no table header can hold; the plan is unchanged."
          exit 1
        fi
        if ! plan_verb_value_ok "${_pv_a#*=}"; then
          die "REFUSED — the value for $_pv_n carries a |, a tab or a line break, which no table cell can hold; the plan is unchanged."
          exit 1
        fi
        [ "$VERB" = task-set ] || continue
        _pv_l="$(printf '%s' "$_pv_n" | tr '[:upper:]' '[:lower:]')"
        case "$_pv_l" in
          reads+|deps+) _pv_l="${_pv_l%+}"; PV_APPEND_ASKED=1 ;;
          *+)
            die "REFUSED — += appends to a cell that lists what a row waits on, reads or deps; ${_pv_l%+} takes =. The plan is unchanged."
            exit 1 ;;
        esac
        case "$_pv_l" in
          files) PV_FILES_ASKED=1; continue ;;  # a fixed column, judged after the plan is open, not an optional one the header lists
          id)
            die "REFUSED — id is the key task-set finds $PV_SET_ID by, not a cell to set; the plan is unchanged."
            exit 1 ;;
          rigor) _pv_l=kind ;;
        esac
        PV_COLS="${PV_COLS:-} $_pv_l"
      done
    done
    if [ -n "${PV_REASON:-}" ]; then
      if ! plan_verb_value_ok "$PV_REASON"; then
        die "REFUSED — the reason carries a |, a tab or a line break, which no step line can hold; the plan is unchanged."
        exit 1
      fi
      for _pv_s in "${PV_SETS[@]}"; do
        pv_set_pairs "$_pv_s"
        case "$PV_SET_ID" in
          T[0-9]*) : ;;
          *) die "REFUSED — a reason is recorded on the row's - T<n>: line, and $PV_SET_ID has none; the plan is unchanged."
             exit 1 ;;
        esac
      done
    fi
    plan_verb_open "$VERB" ${PV_REASON:+closed-ok}
    PV_TABLE="## Tasks"; [ "$VERB" = task-set ] || PV_TABLE="## Dispatch ledger"
    # AN UNKNOWN COLUMN NAMES THE CALL THAT SUCCEEDS (wave-33 T7; REQ-4 AC-4.3). The header's columns are
    # listed, and the call is printed again with each unknown name replaced by the one column it was
    # meant as (`pv_column_guess`); a name with no such column is left out of it, and said so.
    pv_cols_refuse() {  # <columns, one per line>
      local cols="$1" t want=1 out
      local -a call
      call=()
      for t in "${PV_ARGS[@]}"; do
        if [ "$want" = 1 ]; then call+=("$t"); want=0; continue; fi
        case "$t" in
          --) call+=("$t"); want=1; continue ;;
        esac
        pv_fix_pairs "$cols" "$t"
        [ "${#PV_FIXED[@]}" -eq 0 ] || call+=("${PV_FIXED[0]}")
        [ -z "$PV_UNKNOWN" ] || out="${out:+$out, }$PV_UNKNOWN"
      done
      [ -z "${PV_REASON:-}" ] || call+=(--reason "$PV_REASON")
      die "The $PV_TABLE columns: $(printf '%s\n' "$cols" | paste -sd, - | sed 's/,/, /g')."
      [ -z "${out:-}" ] || die "No column is like: ${out}; the call below leaves it out."
      pv_next "$VERB" "${call[@]}"
    }
    if [ "$VERB" = task-set ]; then
      PV_BAD=""
      for _pv_l in ${PV_COLS:-}; do
        # `artifact` is the row's record cell (wave-37 T6; D10): the refusal below names `artifact=<path>` as the remedy, so the
        # header's own cell takes it, though the units control line lists only the contract columns.
        units_has_column "$PV_PLAN" "$_pv_l" \
          || { [ "$_pv_l" = artifact ] && pv_header_cells "$PV_PLAN" tasks | /usr/bin/grep -ix artifact >/dev/null; } \
          || PV_BAD="${PV_BAD:+$PV_BAD, }$_pv_l"
      done
      if [ -n "$PV_BAD" ]; then
        die "REFUSED — the ## Tasks header of $PV_PLAN carries no column $PV_BAD; the plan is unchanged."
        pv_cols_refuse "$(pv_header_cells "$PV_PLAN" tasks | awk '{ l = tolower($0) } l != "id" && l != "files" { print l }')"
        exit 1
      fi
    fi
    # THE APPENDS, WRITTEN OUT: each `reads+=` or `deps+=` pair becomes `<col>=<the cell with the token after
    # it>`, read from the plan as it stands, so the write below is the one transaction it always was. Two
    # appends to one cell in one group build on each other.
    if [ "$VERB" = task-set ] && [ -n "${PV_APPEND_ASKED:-}" ]; then
      PV_JUDGED=()
      for _pv_s in "${PV_SETS[@]}"; do
        pv_set_pairs "$_pv_s"
        _pv_new="$PV_SET_ID"; _pv_rv=""; _pv_dv=""
        for _pv_a in ${PV_SET_PAIRS[@]+"${PV_SET_PAIRS[@]}"}; do
          _pv_c="$(printf '%s' "${_pv_a%%=*}" | tr '[:upper:]' '[:lower:]')"
          case "$_pv_c" in
            reads+|deps+)
              _pv_c="${_pv_c%+}"; _pv_tok="$(printf '%s' "${_pv_a#*=}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
              if [ -z "$_pv_tok" ]; then
                die "REFUSED — ${_pv_c}+= names nothing to append for $PV_SET_ID; the plan is unchanged."
                exit 1
              fi
              if [ "$_pv_c" = reads ]; then _pv_v="$_pv_rv"; else _pv_v="$_pv_dv"; fi
              if [ -z "$_pv_v" ]; then
                _pv_v="$(units_cell_append "$PV_PLAN" "$PV_SET_ID" "$_pv_c" "$_pv_tok")" || {
                  die "REFUSED — $PV_PLAN carries no ## Tasks row $PV_SET_ID; the plan is unchanged."
                  exit 1
                }
              else
                case ", $_pv_v, " in *", $_pv_tok, "*) ;; *) _pv_v="$_pv_v, $_pv_tok" ;; esac
              fi
              if [ "$_pv_c" = reads ]; then _pv_rv="$_pv_v"; else _pv_dv="$_pv_v"; fi
              continue ;;
          esac
          _pv_new="$_pv_new"$'\037'"$_pv_a"
        done
        [ -z "$_pv_rv" ] || _pv_new="$_pv_new"$'\037'"reads=$_pv_rv"
        [ -z "$_pv_dv" ] || _pv_new="$_pv_new"$'\037'"deps=$_pv_dv"
        PV_JUDGED+=("$_pv_new")
      done
      PV_SETS=("${PV_JUDGED[@]}")
    fi
    # A PENDING ROW'S FILES CELL IS THE TABLE'S, A LAUNCHED ROW'S IS A CONTRACT (wave-36 T41; REQ-7 AC-7.1, AC-10.2;
    # D13; A-orch-5, A-orch-6, A-orch-9, A-orch-10). One rule: a row `pending` with no roster row naming it has no
    # launch behind it, so `files=<list>` replaces its cell whole and the list is judged as task-add judges a cell
    # (`poker_files_cell`); a row with a launch has a contract on a roster, which only `amend` widens, so an active,
    # landed or roster-named row (or one this same call sets to another status) is refused as it always was, naming
    # amend. The judged value takes the place of the operand in its set, so the write below is the one transaction.
    if [ "$VERB" = task-set ] && [ -n "${PV_FILES_ASKED:-}" ]; then
      PV_JUDGED=()
      for _pv_s in "${PV_SETS[@]}"; do
        pv_set_pairs "$_pv_s"
        _pv_row="$(units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' -v id="$PV_SET_ID" '$1 == id { print; exit }')"
        _pv_new="$PV_SET_ID"
        for _pv_a in ${PV_SET_PAIRS[@]+"${PV_SET_PAIRS[@]}"}; do
          _pv_l="$(printf '%s' "${_pv_a%%=*}" | tr '[:upper:]' '[:lower:]')"
          if [ "$_pv_l" = files ] && [ -n "$_pv_row" ]; then
            _pv_status="$(printf '%s\n' "$_pv_row" | awk -F'\t' '{ print $10 }')"
            _pv_moved=""
            for _pv_b in ${PV_SET_PAIRS[@]+"${PV_SET_PAIRS[@]}"}; do
              case "$(printf '%s' "${_pv_b%%=*}" | tr '[:upper:]' '[:lower:]')" in
                status) [ "${_pv_b#*=}" = pending ] || _pv_moved=1 ;;
              esac
            done
            if [ "$_pv_status" != pending ] || [ -n "$_pv_moved" ] || pv_roster_names_row "$PV_SET_ID"; then
              die "REFUSED — task-set does not write Files — widen a dispatched contract with amend: bash ${HOOK_DIR}/session-poker.sh amend <name> --files+ <path> --reason <why>. The plan is unchanged."
              exit 1
            fi
            poker_files_cell "$PV_SET_ID" "$(printf '%s\n' "$_pv_row" | awk -F'\t' '{ print $3 }')" \
              "$(printf '%s\n' "$_pv_row" | awk -F'\t' '{ print $5 }')" "${_pv_a#*=}" "$PV_REPO" "$PV_PLAN" || exit $?
            # A RECORD ROW KEEPS ITS ARTIFACT (wave-37 T6; REQ-7 AC-7.3; D10; A-T6-1): a row whose cell names an entry for
            # it, or which carries an `artifact` cell, is not left with neither, by the one rule `brief` reads.
            _pv_art="$(poker_brief_cell "$PV_PLAN" Tasks "$PV_SET_ID" artifact)" || _pv_art=""
            _pv_had="$_pv_art"
            for _pv_b in ${PV_SET_PAIRS[@]+"${PV_SET_PAIRS[@]}"}; do
              case "$(printf '%s' "${_pv_b%%=*}" | tr '[:upper:]' '[:lower:]')" in artifact) _pv_art="${_pv_b#*=}" ;; esac
            done
            if { ! poker_brief_none "$_pv_had" || [ -n "$(poker_brief_record_entry "$(units_field "$_pv_row" Files)" named "$PV_SET_ID")" ]; } \
               && poker_brief_none "$_pv_art" && [ -z "$(poker_brief_record_entry "$PFC_OUT" named "$PV_SET_ID")" ]; then
              die "task-set refused — Files leaves $PV_SET_ID with no artifact: name a record $PV_SET_ID-<name>.md in Files or set artifact=<path>"
              exit 1
            fi
            _pv_a="${_pv_a%%=*}=$PFC_OUT"
          fi
          _pv_new="$_pv_new"$'\037'"$_pv_a"
        done
        PV_JUDGED+=("$_pv_new")
      done
      PV_SETS=("${PV_JUDGED[@]}")
    fi
    case "$VERB" in
      task-set)   PV_MODE=set; PV_SECT=tasks ;;
      ledger-set) PV_MODE=set; PV_SECT=ledger ;;
      ledger-add) PV_MODE=add; PV_SECT=ledger ;;
    esac
    cp "$PV_PLAN" "$PV_NEW"
    PV_WHAT=""
    for _pv_s in "${PV_SETS[@]}"; do
      pv_set_pairs "$_pv_s"
      PV_RC=0
      units_table_cells "$PV_NEW" "$PV_MODE" "$PV_SECT" "$PV_SET_ID" "${PV_SET_PAIRS[@]}" > "$PV_NEW.2" 2>/dev/null || PV_RC=$?
      case "$PV_RC" in
        0) mv -f "$PV_NEW.2" "$PV_NEW" ;;
        1) die "REFUSED — $PV_PLAN carries no $PV_TABLE table; the plan is unchanged."; exit 1 ;;
        2) if [ "$PV_MODE" = add ]; then die "REFUSED — the $PV_TABLE table already carries a row $PV_SET_ID; set its cells with ledger-set. The plan is unchanged."
           else die "REFUSED — the $PV_TABLE table carries no row $PV_SET_ID; the plan is unchanged."; fi
           exit 1 ;;
        3) die "REFUSED — the $PV_TABLE header carries no column named in: ${PV_SET_PAIRS[*]%%=*}; the plan is unchanged."
           pv_cols_refuse "$(pv_header_cells "$PV_PLAN" "$PV_SECT")"
           exit 1 ;;
        5) die "REFUSED — the $PV_TABLE table carries more than one row $PV_SET_ID; which one is meant is not the verb's to guess. The plan is unchanged."; exit 1 ;;
        *) die "REFUSED — the value cannot be written as a table cell; the plan is unchanged."; exit 1 ;;
      esac
      PV_WHAT="${PV_WHAT:+$PV_WHAT; }$PV_SET_ID ${PV_SET_PAIRS[*]}"
    done
    if [ "$VERB" = task-set ]; then
      PV_VIOL="$(units_validate "$PV_NEW" 2>&1)"
      if [ -n "$PV_VIOL" ]; then
        die "REFUSED — with that change, the ## Tasks table breaks the Task invariants; the plan is unchanged:"
        printf '%s\n' "$PV_VIOL" >&2
        exit 1
      fi
    fi
    # THE REASON ON THE STEP LINE (wave-36 T14; AC-7.7): ` reason: <why>` after each named row's own text, once (a
    # line that already ends so is left), in the same copy, so the cells and the reason are one write.
    if [ -n "${PV_REASON:-}" ]; then
      for _pv_s in "${PV_SETS[@]}"; do
        pv_set_pairs "$_pv_s"
        _pv_rest="$(units_step_text "$PV_NEW" "$PV_SET_ID" 2>/dev/null)"
        case "$_pv_rest " in *" reason: $PV_REASON "|"reason: $PV_REASON ") continue ;; esac
        if ! units_step_line "$PV_NEW" "$PV_SET_ID" "${_pv_rest:+$_pv_rest }reason: $PV_REASON" > "$PV_NEW.2" 2>/dev/null; then
          die "REFUSED — $PV_PLAN carries no ## SDLC State section for the $PV_SET_ID line; the plan is unchanged."
          exit 1
        fi
        mv -f "$PV_NEW.2" "$PV_NEW"
      done
      PV_WHAT="$PV_WHAT; reason: $PV_REASON"
    fi
    [ "$PV_MODE" = add ] && PV_WHAT="$PV_ID added to the dispatch ledger"
    plan_verb_swap "$VERB" "$PV_WHAT" writer
    say "$VERB — $PV_WHAT: written to $PV_PLAN; dry-committed first."
    # THE SUSPECT TEST AT EVERY RE-AUTHORING (wave-30 T16; AC-12.2): task-set prints it as task-add does.
    if [ "$VERB" = task-set ]; then
      for _pv_s in "${PV_SETS[@]}"; do
        pv_set_pairs "$_pv_s"
        suspect_lines "$PV_PLAN" "$PV_SET_ID" | while IFS=$'\t' read -r _ _ PV_SUSPECT; do say "$(clean_whole "$PV_SUSPECT")"; done
      done
    fi
    exit 0
  }

  # THE STEP-LINE VERB (wave-24 T15; REQ-9 AC-9.6, D14). The `- Step N:` and `- T<n>:` lines
  # under `## SDLC State` are the run's evidence, and the gate reads them; `units_step_line`
  # rewrites one line's text (or adds the line, after its kind's last), and never the block
  # under it. Step 9 is close-out's, as `current: 9` is (payload/scripts/close-out.sh), except on a PARKED plan
  # (wave-38 T15; AC-4.3), read by lib/run.sh `plan_parked_why`, the reader close-out asks. The plan is read once the
  # session's binding names it, so the refusal follows the binding's own.
  poker_verb_step_line() {
    case "$PV_TEXT" in
      *$'\n'*|*$'\r'*)
        die "REFUSED — a step line is one line, and the text carries a line break; the plan is unchanged."
        exit 1 ;;
    esac
    plan_verb_open step-line
    case "$PV_KEY" in
      9|9a|9b)
        if ! plan_parked_why "$PV_PLAN" >/dev/null; then
          die "REFUSED — the Step 9 line is close-out's to write, with current: 9 (bash <plugin-root>/scripts/close-out.sh); the plan is unchanged."
          exit 1
        fi ;;
    esac
    if ! units_step_line "$PV_PLAN" "$PV_KEY" "$PV_TEXT" "$PV_APPEND" > "$PV_NEW" 2>/dev/null; then
      die "REFUSED — $PV_PLAN carries no ## SDLC State section; the plan is unchanged."
      exit 1
    fi
    PV_LABEL="$PV_KEY"; case "$PV_KEY" in T*) : ;; *) PV_LABEL="Step $PV_KEY" ;; esac
    plan_verb_swap step-line "the $PV_LABEL line written" writer
    say "step-line — $PV_LABEL: written to $PV_PLAN${PV_APPEND:+ (appended)}; dry-committed first."
    exit 0
  }

  # THE STEP-FIELD VERB (wave-28 T8; REQ-3 AC-3.5, D17). A `- Step N:` block is the evidence the gate reads, and
  # the fields it reads were hand edits: `units_step_fields --replace` writes one `  <key>: <value>` line under
  # the step line, after the block last line, or replaces the line where it stands (the gate reads the first
  # line of a key, so a second could not win); the rest of the plan is the same bytes. Eleven keys, the ones the
  # gate reads at Steps 4, 5, 7 and 8: head cmd pass total output (the regression run), merge worktree-removed (the
  # integration), adr (the document step), share (the Step-4 fact), auditor (the Verify gate's verdict, Step 5 alone),
  # walk-artifact (the walk gate's pointer, Step 5
  # alone; wave-33 T7). It takes the plan transaction every row verb
  # takes (copy, dry commit through the real gate, checksum, swap), so a plan the gate would refuse is not
  # written. REFUSED (1), the plan unchanged: a key outside the eleven, a value with a line break, a step with no
  # line (step-line writes it), a key the step line itself carries (step-line owns that text), and Step 9
  # (close-out writes that block). The refusals are this verb family die lines, not refuse.sh refusals.
  poker_verb_step_field() {
    case "$PV_KEY" in
      9|9a|9b)
        die "REFUSED — the Step 9 block is close-out's to write (scripts/close-out.sh)."
        exit 1 ;;
    esac
    case "$PV_FKEY" in
      head|cmd|pass|total|output|merge|worktree-removed|adr|share|walk-artifact|auditor) : ;;
      *)
        die "REFUSED — '$(clean "${PV_FKEY:0:20}")' is not a step field; the plan is unchanged."
        die "The fields: head, cmd, pass, total, output, merge, worktree-removed, adr, share, walk-artifact and auditor (Step 5)."
        exit 1 ;;
    esac
    # THE WALK POINTER (wave-33 T7; REQ-4 AC-4.1, D8; A-orch-42). The walk gate reads `walk-artifact:`
    # from the Step-5 block alone (walls.sh `step5_evidence_block`), so the key is written there and at no
    # other step; and it refuses a path that climbs out with `..`, so the verb refuses it first.
    if [ "$PV_FKEY" = walk-artifact ]; then
      if [ "$PV_KEY" != 5 ]; then
        die "REFUSED — walk-artifact is read from the Step 5 block only (the walk gate's), not Step $PV_KEY's; the plan is unchanged."
        pv_next step-field 5 "walk-artifact=$PV_FVAL"
        exit 1
      fi
      case "/$PV_FVAL/" in
        */../*)
          die "REFUSED — the walk artifact '$(clean "$PV_FVAL")' has a '..' component, which the walk gate refuses: name it under record/. The plan is unchanged."
          exit 1 ;;
      esac
    fi
    # THE AUDITOR'S VERDICT is read by the Verify gate from the Step 5 block alone (walls.sh `validate_verify_step`), so
    # the key is written there and at no other step.
    if [ "$PV_FKEY" = auditor ] && [ "$PV_KEY" != 5 ]; then
      die "REFUSED — auditor is read from the Step 5 block only (the Verify gate's), not Step $PV_KEY's; the plan is unchanged."
      pv_next step-field 5 "auditor=$PV_FVAL"
      exit 1
    fi
    case "$PV_FVAL" in
      *$'\n'*|*$'\r'*)
        die "REFUSED — a step field is one line, and the value has a line break; the plan is unchanged."
        exit 1 ;;
    esac
    plan_verb_open step-field
    PV_RC=0
    units_step_fields --replace "$PV_PLAN" "$PV_KEY" "$PV_FKEY=$PV_FVAL" > "$PV_NEW" 2>/dev/null || PV_RC=$?
    case "$PV_RC" in
      0) : ;;
      1) die "REFUSED — the plan has no Step $PV_KEY line; step-line writes it first. The plan is unchanged."
         exit 1 ;;
      5) die "REFUSED — the Step $PV_KEY line itself carries '$PV_FKEY:'; step-line writes that text."
         die "The plan is unchanged."
         exit 1 ;;
      *) die "REFUSED — the field cannot be written (units_step_fields exit $PV_RC); the plan is unchanged."
         exit 1 ;;
    esac
    # THE POINTER HAS ONE WRITER (wave-36 T44; REQ-7 AC-7.1, AC-10.2; D13). matrix-render writes a matrix-level
    # `walk-artifact: pending` stub that the gate refuses as a placeholder once every row is discharged, and no verb filled
    # it: the fix was a hand edit. The Step 5 block stays the walk gate's one reader; the matrix line, when the plan has
    # one, takes the same value in the same transaction. A matrix with no such line gains none.
    if [ "$PV_FKEY" = walk-artifact ]; then
      PV_RC=0
      SF_WV="$PV_FVAL" awk '
        { if ($0 ~ /^[ \t]*```/) fence = !fence }
        /^## / { m = ($0 ~ /^## Verification Matrix/) }
        !fence && m && !done && /^[ \t]*walk-artifact[ \t]*:/ {
          ind = $0; sub(/[^ \t].*$/, "", ind); print ind "walk-artifact: " ENVIRON["SF_WV"]; done = 1; next }
        { print }' "$PV_NEW" > "$PV_NEW.m" 2>/dev/null || PV_RC=$?
      if [ "$PV_RC" -ne 0 ]; then
        die "REFUSED — the matrix walk-artifact: line cannot be written (awk exit $PV_RC); the plan is unchanged."
        exit 1
      fi
      mv "$PV_NEW.m" "$PV_NEW"
    fi
    plan_verb_swap step-field "Step $PV_KEY $PV_FKEY" writer
    say "step-field — Step $PV_KEY $PV_FKEY: written to $PV_PLAN; dry-committed first."
    exit 0
  }

  # THE MATRIX RENDER (wave-30 T14; REQ-6 AC-6.1, D9, Δ12a). Step 3 writes the matrix and Step 5 fills it: the
  # verb reads the bound plan's `## Eval design` table and writes, under `## Verification Matrix`, one AC block per
  # criterion, in the shape the gate reads — its `AC-<n>:` line carrying the criterion's text from its `- AC-<n>`
  # bullet, `provenance:` (the requirement's `provenance:` line under its `### REQ-<n>` heading in the requirements
  # file the plan names, else in the plan, else `pending`; never the Approach: wave-35 T8, AC-6.4), `fails-when:`
  # and `eval:` (`<tier> — <Eval>`) from the table,
  # `task:` (the one `## Tasks` row whose serves cell names the criterion or its requirement, else `pending`), then
  # `evidence:` (and `user-confirmed:` at T4), the keys walls.sh `keys_for_tier` names for the tier the matrix
  # table gives the criterion, each `pending`. The matrix head gains `stack-health: pending`, and `walk-artifact: pending` unless the
  # plan is `walk: exempt`, where it has none. `pending` is the stub token (Δ12a): the gate refuses it wherever it
  # judges evidence and reads nothing of it before Step 5.
  #
  # ADDITIVE, SO IT CAN BE RUN AGAIN. A block that exists gains only the keys it lacks, after its last line; a key
  # that is there is never rewritten, whatever it says. The one line it prints counts the three outcomes: new
  # blocks, keys added (to existing blocks and the matrix head), and blocks left as they were. When there is nothing
  # to add it writes nothing. It takes the transaction every plan verb takes (copy, dry commit, checksum, swap).
  # REFUSED (1), the plan unchanged: no `## Eval design` with criteria, no matrix table, a criterion with no matrix
  # row (its tier is unknown, and a guessed tier owes the wrong keys), a tier walls.sh does not know.
  poker_verb_matrix_render() {
    plan_verb_open matrix-render
    MR_KEYS="$(mr_tier_keys)" || MR_KEYS=""
    if [ -z "$MR_KEYS" ]; then
      die "REFUSED — the per-tier keys are walls.sh keys_for_tier's, and $BIONIC_LIB/walls.sh cannot be loaded; the plan is unchanged."
      exit 2
    fi
    MR_TASKS="$(serves_tasks "$PV_PLAN")"
    PV_RC=0
    MR_KEYS="$MR_KEYS" MR_TASKS="$MR_TASKS" MR_WALK="$(plan_frontmatter_get "$PV_PLAN" walk)" MR_COUNT="$PV_NEW.2" \
      MR_REQFILE="$(mr_requirements_file "$PV_PLAN" "$PV_REPO")" \
      awk "$SERVES_AWK$MR_AWK" "$PV_PLAN" > "$PV_NEW" 2>/dev/null || PV_RC=$?
    MR_WHY="$(cut -f2 "$PV_NEW.2" 2>/dev/null)"
    case "$PV_RC" in
      0) : ;;
      3) die "REFUSED — the plan has no ## Eval design table with a Criterion column and rows; matrix-render reads the criteria from it. The plan is unchanged."
         exit 1 ;;
      4) die "REFUSED — the plan's ## Verification Matrix has no AC tier table (| AC | tier | status | evidence | auditor |); each criterion's tier is read from it. The plan is unchanged."
         exit 1 ;;
      5) die "REFUSED — the matrix table has no row for $MR_WHY, so the tier and the keys it owes are unknown; add the row, then render. The plan is unchanged."
         exit 1 ;;
      6) die "REFUSED — no tier walls.sh knows for $MR_WHY: the tier cell is T0 to T4. The plan is unchanged."
         exit 1 ;;
      *) die "REFUSED — the matrix cannot be rendered (awk exit $PV_RC); the plan is unchanged."
         exit 2 ;;
    esac
    IFS="$(printf '\t')" read -r MR_N MR_M MR_K < "$PV_NEW.2"
    MR_LINE="matrix-render — ${MR_N:-0} blocks written, ${MR_M:-0} keys added, ${MR_K:-0} unchanged"
    if [ "$(( ${MR_N:-0} + ${MR_M:-0} ))" -eq 0 ]; then
      say "$MR_LINE; the plan already reads so, nothing was written."
      exit 0
    fi
    plan_verb_swap matrix-render "the matrix rendered" writer
    say "$MR_LINE; written to $PV_PLAN, dry-committed first."
    exit 0
  }

  # THE AUDITOR CELL'S ONE WRITER (wave-30 T14; REQ-6 AC-6.2, D9). The gate compares the matrix `auditor` cell with
  # the bare token `CONFIRMED` past the Verify gate and refuses anything after it; wave-28's scratch scripts wrote
  # `CONFIRMED <date>` there by hand. This verb sets the row's fifth cell to exactly `CONFIRMED` — whatever it held,
  # a dated token among them — and leaves every other byte of the plan as it was; the audit's own path belongs in the
  # row's `evidence:` key, not in this cell. A row already CONFIRMED is nothing to write. REFUSED (1), the plan
  # unchanged: an AC id the matrix table has no row for (the id is compared whole, so AC-1 is not AC-1.1), a row
  # that does not have five cells. The plan transaction, as every plan verb.
  poker_verb_discharge() {
    plan_verb_open discharge
    PV_RC=0
    matrix_row_cells "$PV_PLAN" "$DS_AC" 5=CONFIRMED > "$PV_NEW" 2>/dev/null || PV_RC=$?
    case "$PV_RC" in
      0) : ;;
      3) die "REFUSED — the matrix table has no row $DS_AC; the plan is unchanged."
         exit 1 ;;
      4) die "REFUSED — the matrix row $DS_AC does not have five cells, so its auditor cell cannot be found; the plan is unchanged."
         exit 1 ;;
      *) die "REFUSED — the auditor cell cannot be written (awk exit $PV_RC); the plan is unchanged."
         exit 2 ;;
    esac
    plan_verb_swap discharge "$DS_AC's auditor cell CONFIRMED" writer
    say "discharge — $DS_AC: auditor CONFIRMED, written to $PV_PLAN; dry-committed first."
    exit 0
  }

  # THE MATRIX ROW'S CELLS AND BLOCK KEYS (wave-33 T7; REQ-4 AC-4.1, D8). Wave-32 moved its matrix by hand:
  # statuses to waived and discharged, evidence to the fix rows' records, multi-row task keys (A-orch-38, 40,
  # 41, 47). `status=` writes the table's status cell; `evidence=` the evidence cell AND the AC block's
  # `evidence:` key, so the table and the block name the same path (research G3); `task=` the block's `task:`
  # key, each id a `## Tasks` row, joined `, `. The tier cell is the plan's, set at Step 3; the auditor cell
  # is discharge's. `status=waived` stands only beside the block's `waiver:` line, which waive-row writes on
  # the user's words. Every key is judged before any is written, and the call is one plan transaction.
  # REFUSED (1), the plan unchanged: a key outside the three, a status outside the gate's four, an evidence
  # path outside record/ or with a `..`, a task id no row carries, an AC with no row, a block key on an AC
  # with no block.
  poker_verb_matrix_set() {
    MS_HAS_S=0; MS_HAS_E=0; MS_HAS_T=0; MS_STATUS=""; MS_EV=""; MS_TASK=""
    for _pv_a in "${MS_PAIRS[@]}"; do
      _pv_k="${_pv_a%%=*}"; _pv_v="${_pv_a#*=}"
      if ! plan_verb_value_ok "$_pv_v"; then
        die "REFUSED — the value for $(clean "$_pv_k") carries a |, a tab or a line break, which no matrix cell can hold; the plan is unchanged."
        exit 1
      fi
      case "$_pv_k" in
        status)   MS_HAS_S=1; MS_STATUS="$_pv_v" ;;
        evidence) MS_HAS_E=1; MS_EV="$_pv_v" ;;
        task)     MS_HAS_T=1; MS_TASK="$_pv_v" ;;
        tier)
          die "REFUSED — the tier cell is the plan's, set at Step 3 with the criterion's eval; matrix-set never writes it. The plan is unchanged."
          exit 1 ;;
        auditor)
          die "REFUSED — the auditor cell is discharge's, and it holds the bare token CONFIRMED; the plan is unchanged."
          pv_next discharge "$MS_AC"
          exit 1 ;;
        *)
          die "REFUSED — '$(clean "$_pv_k")' is no key matrix-set writes: status, evidence or task. The plan is unchanged."
          pv_fix_pairs "$(printf 'status\nevidence\ntask\n')" "${MS_PAIRS[@]}"
          [ "${#PV_FIXED[@]}" -eq 0 ] || pv_next matrix-set "$MS_AC" "${PV_FIXED[@]}"
          exit 1 ;;
      esac
    done
    if [ "$MS_HAS_S" = 1 ]; then
      case "$MS_STATUS" in
        pending|blocked|discharged|waived) : ;;
        *)
          die "REFUSED — '$(clean "$MS_STATUS")' is no matrix status; the gate reads pending, blocked, discharged, waived. The plan is unchanged."
          exit 1 ;;
      esac
    fi
    if [ "$MS_HAS_E" = 1 ]; then
      case "$MS_EV" in
        record/?*) : ;;
        *)
          die "REFUSED — the evidence '$(clean "$MS_EV")' is not under record/: a matrix path is docs-root relative, record/<…>. The plan is unchanged."
          case "$MS_EV" in
            */record/?*) pv_fix_pairs "$(printf 'status\nevidence\ntask\n')" "${MS_PAIRS[@]/#evidence=*/evidence=record/${MS_EV#*/record/}}"
                         pv_next matrix-set "$MS_AC" "${PV_FIXED[@]}" ;;
          esac
          exit 1 ;;
      esac
      case "/$MS_EV/" in
        */../*)
          die "REFUSED — the evidence '$(clean "$MS_EV")' has a '..' component; name it under record/. The plan is unchanged."
          exit 1 ;;
      esac
    fi
    plan_verb_open matrix-set
    if [ -z "$(matrix_row_cell "$PV_PLAN" "$MS_AC" 1)" ]; then
      die "REFUSED — the matrix table has no row $MS_AC; the plan is unchanged."
      exit 1
    fi
    if [ "$MS_HAS_T" = 1 ]; then
      MS_ROWS=" $(units_rows "$PV_PLAN" 2>/dev/null | cut -f1 | tr '\n' ' ')"
      MS_IDS=""; MS_MISS=""
      for _pv_i in $(printf '%s' "$MS_TASK" | tr ',' ' '); do
        case "$MS_ROWS" in
          *" $_pv_i "*) MS_IDS="${MS_IDS:+$MS_IDS, }$_pv_i" ;;
          *) MS_MISS="${MS_MISS:+$MS_MISS, }$(clean "$_pv_i")" ;;
        esac
      done
      if [ -n "$MS_MISS" ] || [ -z "$MS_IDS" ]; then
        die "REFUSED — task=$(clean "$MS_TASK") names ${MS_MISS:-no id}, no row of the ## Tasks table; the plan is unchanged."
        exit 1
      fi
    fi
    if [ "$MS_STATUS" = waived ] && ! matrix_block_has "$PV_PLAN" "$MS_AC" waiver; then
      die "REFUSED — $MS_AC has no waiver: line, and a waived row is one the user waived in their own words; waive-row writes both. The plan is unchanged."
      pv_next waive-row "$MS_AC" "<the user's words>" "<why>"
      exit 1
    fi
    cp "$PV_PLAN" "$PV_NEW"
    MS_CELLS=()
    [ "$MS_HAS_S" = 0 ] || MS_CELLS+=("3=$MS_STATUS")
    [ "$MS_HAS_E" = 0 ] || MS_CELLS+=("4=$MS_EV")
    PV_RC=0
    if [ "${#MS_CELLS[@]}" -gt 0 ]; then
      matrix_row_cells "$PV_NEW" "$MS_AC" "${MS_CELLS[@]}" > "$PV_NEW.2" 2>/dev/null || PV_RC=$?
      [ "$PV_RC" -ne 0 ] || mv -f "$PV_NEW.2" "$PV_NEW"
    fi
    if [ "$PV_RC" -eq 0 ] && [ "$MS_HAS_E" = 1 ]; then
      matrix_block_key "$PV_NEW" "$MS_AC" evidence "$MS_EV" > "$PV_NEW.2" 2>/dev/null || PV_RC=$((10 + $?))
      [ "$PV_RC" -ne 0 ] || mv -f "$PV_NEW.2" "$PV_NEW"
    fi
    if [ "$PV_RC" -eq 0 ] && [ "$MS_HAS_T" = 1 ]; then
      matrix_block_key "$PV_NEW" "$MS_AC" task "$MS_IDS" > "$PV_NEW.2" 2>/dev/null || PV_RC=$((10 + $?))
      [ "$PV_RC" -ne 0 ] || mv -f "$PV_NEW.2" "$PV_NEW"
    fi
    case "$PV_RC" in
      0) : ;;
      4) die "REFUSED — the matrix row $MS_AC does not have five cells, so its cells cannot be found; the plan is unchanged."
         exit 1 ;;
      13) die "REFUSED — the matrix has no $MS_AC: block to hold the key; matrix-render writes it. The plan is unchanged."
          pv_next matrix-render
          exit 1 ;;
      *) die "REFUSED — the matrix cannot be written (exit $PV_RC); the plan is unchanged."
         exit 2 ;;
    esac
    plan_verb_swap matrix-set "$MS_AC ${MS_PAIRS[*]}" writer
    say "matrix-set — $MS_AC: ${MS_PAIRS[*]} written to $PV_PLAN; dry-committed first."
    exit 0
  }

  # A PROSE PARAGRAPH UNDER ## Tasks (wave-33 T7; REQ-4 AC-4.1, D8). Wave-32's shard-table paragraph was copied
  # in and rewritten by hand (A-orch-24, 25). The paragraph is one line, written after the section's last
  # paragraph below the table (after the table, a blank line between); `--replace '<first words>'` rewrites
  # the one paragraph whose first line opens with those words, in place. A paragraph that is already there is
  # nothing to write. REFUSED (1), the plan unchanged: a line break, a text that opens with | or # (a table
  # row or a heading), no table under ## Tasks, --replace naming no paragraph or more than one.
  poker_verb_tasks_prose() {
    case "$TP_TEXT" in
      *$'\n'*|*$'\r'*)
        die "REFUSED — a paragraph here is one line, and the text carries a line break; the plan is unchanged."
        exit 1 ;;
    esac
    TP_TEXT="$(printf '%s' "$TP_TEXT" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    TP_REPLACE="$(printf '%s' "$TP_REPLACE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    case "$TP_TEXT" in
      '|'*|'#'*)
        die "REFUSED — a paragraph that opens with | or # reads as a table row or a heading; the plan is unchanged."
        exit 1 ;;
    esac
    plan_verb_open tasks-prose
    PV_RC=0
    TP_TEXT="$TP_TEXT" TP_REPLACE="$TP_REPLACE" TP_HASREP="$TP_HASREP" TP_LIST="$PV_NEW.2" awk '
      BEGIN { text = ENVIRON["TP_TEXT"]; rep = ENVIRON["TP_REPLACE"]; hasrep = (ENVIRON["TP_HASREP"] == 1); list = ENVIRON["TP_LIST"] }
      { L[++nl] = $0 }
      END {
        for (i = 1; i <= nl; i++) {
          x = L[i]
          if (x ~ /^[ \t]*```/) fence = !fence
          if (!fence && x ~ /^##[ \t]/) { if (st) break; if (x ~ /^##[ \t]+Tasks([ \t].*)?$/) st = 1; continue }
          if (st == 1) { if (x ~ /^[ \t]*\|/) { st = 2; tend = i }; continue }
          if (st == 2) { if (x ~ /^[ \t]*\|/) { tend = i; continue }; st = 3; last = tend }
          if (st == 3) {
            if (x ~ /[^ \t]/) { last = i; if (!inp) { np++; ps[np] = i; inp = 1 }; pe[np] = i } else inp = 0
          }
        }
        if (!tend) exit 4
        if (st == 2) last = tend
        if (hasrep) {
          for (p = 1; p <= np; p++) { y = L[ps[p]]; sub(/^[ \t]+/, "", y); if (index(y, rep) == 1) { hit++; hp = p } }
          if (hit != 1) { for (p = 1; p <= np; p++) print L[ps[p]] > list; exit (hit ? 5 : 3) }
          for (i = 1; i <= nl; i++) {
            if (i == ps[hp]) { print text; continue }
            if (i > ps[hp] && i <= pe[hp]) continue
            print L[i]
          }
          exit 0
        }
        for (p = 1; p <= np; p++) if (ps[p] == pe[p] && L[ps[p]] == text) same = 1
        for (i = 1; i <= nl; i++) {
          print L[i]
          if (!same && i == last) { print ""; print text; if (i < nl && L[i + 1] ~ /[^ \t]/) print "" }
        }
      }' "$PV_PLAN" > "$PV_NEW" 2>/dev/null || PV_RC=$?
    case "$PV_RC" in
      0) : ;;
      4) die "REFUSED — the plan has no table under ## Tasks for the paragraph to follow; the plan is unchanged."
         exit 1 ;;
      3|5)
         if [ "$PV_RC" = 3 ]; then
           die "REFUSED — no paragraph under ## Tasks opens with '$(clean "$TP_REPLACE")'; the plan is unchanged."
         else
           die "REFUSED — more than one paragraph under ## Tasks opens with '$(clean "$TP_REPLACE")'; name more of its first words. The plan is unchanged."
         fi
         if [ -s "$PV_NEW.2" ]; then
           while IFS= read -r TP_P; do
             pv_next tasks-prose "$TP_TEXT" --replace "$(printf '%s' "$TP_P" | awk '{ print $1, $2, $3 }' | sed 's/[[:space:]]*$//')"
           done < "$PV_NEW.2"
         else
           pv_next tasks-prose "$TP_TEXT"
         fi
         exit 1 ;;
      *) die "REFUSED — the paragraph cannot be written (awk exit $PV_RC); the plan is unchanged."
         exit 2 ;;
    esac
    plan_verb_swap tasks-prose "the paragraph under ## Tasks" writer
    say "tasks-prose — the paragraph under ## Tasks: written to $PV_PLAN${TP_REPLACE:+ (replacing the one opening '$TP_REPLACE')}; dry-committed first."
    exit 0
  }

  # THE EPIC'S SHIPPED ROW (wave-33 T7; REQ-3 AC-3.3, D8). close-out.sh writes the row whole when it appends
  # it and never edits a row that is there (`act_epic`), so a `<fill: ADRs>` it left (wave-30's) could be
  # filled by no code. This verb sets cells of the row whose wave cell is <wave>, in the shipped table
  # close-out finds (the table whose header opens `wave` and carries `shipped`) of the `epic.plan.md` beside
  # the run's plan. A column is named by its header cell or that cell's first word, case-blind (`ADRs`,
  # `plan`, `spec`). The file transaction (`pv_file_open`, `pv_file_swap`). REFUSED (1), the file unchanged:
  # no epic plan, no shipped table, a column it does not carry (the columns listed, the corrected call
  # printed), the wave cell, a value with a |, a line break or a fill mark, no row for the wave.
  poker_verb_epic_row() {
    pv_file_open epic-row "$EP_WAVE" "${EP_PAIRS[@]}"
    EP_FILE="${PV_RPLAN%/*}/epic.plan.md"
    if [ ! -f "$EP_FILE" ] || [ -L "$EP_FILE" ]; then
      die "REFUSED — no epic.plan.md beside $PV_RPLAN (or it is a link); nothing was written."
      exit 1
    fi
    EP_AWK='
      function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
      function shipped_header(line,   n, a, i) {
        n = split(line, a, "|")
        if (tolower(trim(a[2])) != "wave") return 0
        for (i = 3; i <= n; i++) if (tolower(trim(a[i])) == "shipped") return 1
        return 0
      }
      BEGIN {
        mode = ENVIRON["EP_MODE"]; w = ENVIRON["EP_WAVE"] + 0; m = split(ENVIRON["EP_SET"], s, "\n")
        for (k = 1; k <= m; k++) if ((t = index(s[k], "\t")) > 0) v[substr(s[k], 1, t - 1) + 1] = " " substr(s[k], t + 1) " "
      }
      /^[ \t]*```/ { fence = !fence; if (mode == "set") print; next }
      fence { if (mode == "set") print; next }
      !seen && /^\|/ && shipped_header($0) {
        intable = 1; seen = 1
        if (mode == "head") { n = split($0, a, "|"); for (i = 2; i < n; i++) print trim(a[i]); exit }
        print; next
      }
      intable && !/^\|/ { intable = 0 }
      intable && mode == "set" {
        n = split($0, c, "|"); x = trim(c[2])
        if (x ~ /^[0-9]+$/ && x + 0 == w) {
          hits++
          if (hits == 1) { for (j in v) c[j] = v[j]; out = c[1]; for (j = 2; j <= n; j++) out = out "|" c[j]; print out; next }
        }
      }
      mode == "set" { print }
      END { if (mode == "set") { if (!seen) exit 3; if (!hits) exit 4; if (hits > 1) exit 5 } }'
    EP_COLS="$(EP_MODE=head awk "$EP_AWK" "$EP_FILE" 2>/dev/null)"
    if [ -z "$EP_COLS" ]; then
      die "REFUSED — $EP_FILE carries no shipped table (a header whose first cell is wave and which has a shipped cell); nothing was written."
      exit 1
    fi
    EP_SET=""; EP_BAD=""; EP_FIRST=""
    for _pv_a in "${EP_PAIRS[@]}"; do
      _pv_k="${_pv_a%%=*}"; _pv_v="${_pv_a#*=}"
      _pv_f="$(pv_fold "$_pv_k")"; _pv_n=0; _pv_at=""
      while IFS= read -r _pv_c; do
        _pv_n=$((_pv_n + 1))
        if [ "$(pv_fold "$_pv_c")" = "$_pv_f" ] || [ "$(pv_fold "${_pv_c%% *}")" = "$_pv_f" ]; then _pv_at="$_pv_n"; break; fi
      done <<< "$EP_COLS"
      if [ -z "$_pv_at" ]; then EP_BAD="${EP_BAD:+$EP_BAD, }$(clean "$_pv_k")"; continue; fi
      if [ "$_pv_at" = 1 ]; then
        die "REFUSED — the wave cell is the key epic-row finds the row by, not a cell to set; nothing was written."
        exit 1
      fi
      if ! plan_verb_value_ok "$_pv_v"; then
        die "REFUSED — the value for $(clean "$_pv_k") carries a |, a tab or a line break, which no table cell can hold; nothing was written."
        exit 1
      fi
      case "$_pv_v" in
        *'<fill:'*)
          die "REFUSED — the value for $(clean "$_pv_k") is itself a fill mark; write the fact. Nothing was written."
          exit 1 ;;
      esac
      EP_SET="${EP_SET}${_pv_at}	${_pv_v}
"
    done
    if [ -n "$EP_BAD" ]; then
      die "REFUSED — the shipped table of $EP_FILE carries no column $EP_BAD; nothing was written."
      die "The columns: $(printf '%s\n' "$EP_COLS" | paste -sd, - | sed 's/,/, /g')."
      pv_fix_pairs "$(printf '%s\n' "$EP_COLS" | sed 's/ .*//')" "${EP_PAIRS[@]}"
      if [ "${#PV_FIXED[@]}" -gt 0 ]; then
        if [ -n "$PV_PLAN_ARG" ]; then pv_next epic-row "$EP_WAVE" "${PV_FIXED[@]}" --plan "$PV_PLAN_ARG"
        else pv_next epic-row "$EP_WAVE" "${PV_FIXED[@]}"; fi
      fi
      exit 1
    fi
    EP_SUM="$(cksum < "$EP_FILE" 2>/dev/null)"
    PV_NEW="$EP_FILE.epic-row.$$"
    PV_RC=0
    EP_MODE=set EP_WAVE="$EP_WAVE" EP_SET="$EP_SET" awk "$EP_AWK" "$EP_FILE" > "$PV_NEW" 2>/dev/null || PV_RC=$?
    case "$PV_RC" in
      0) : ;;
      4) die "REFUSED — the shipped table of $EP_FILE has no row for wave $EP_WAVE; close-out appends it. Nothing was written."
         exit 1 ;;
      5) die "REFUSED — the shipped table of $EP_FILE has more than one row for wave $EP_WAVE; which one is meant is not the verb's to guess. Nothing was written."
         exit 1 ;;
      *) die "REFUSED — the row cannot be written (awk exit $PV_RC); nothing was written."
         exit 2 ;;
    esac
    pv_file_swap epic-row "$EP_FILE" "$EP_SUM" "wave $EP_WAVE's row"
    EP_LEFT="$(awk -v w="$EP_WAVE" -F'|' '{ x = $2; gsub(/^[ \t]+|[ \t]+$/, "", x) } x ~ /^[0-9]+$/ && x + 0 == w + 0 && /<fill:/ { n++ } END { print n + 0 }' "$EP_FILE")"
    say "epic-row — wave $EP_WAVE: ${EP_PAIRS[*]} written to $EP_FILE; fill marks left in the row: $EP_LEFT."
    exit 0
  }

  # THE CONTINUATION'S FILL MARKS (wave-33 T7; REQ-3 AC-3.3, D8). close-out.sh writes the run's continuation
  # (`record/<run>/continuation.md`, under the docs root its plan sits in) with a `<fill: …>` mark wherever
  # only the orchestrator knows the fact; wave-32 completed its marks by hand (A-orch-50). This verb replaces
  # the mark whose label is <field>, or opens with it before a character that is no letter or digit
  # (`the first decision` for `<fill: the first decision, or "none">`); every copy of that mark is filled,
  # and the marks left are counted. The text may span lines. The file transaction. REFUSED (1), the file
  # unchanged: no continuation, a field naming no mark or more than one (the fields left listed), a text
  # that is itself a fill mark.
  poker_verb_continuation_fill() {
    pv_file_open continuation-fill "$CF_FIELD=$CF_TEXT"
    CF_DOCS="$(docs_root "$PV_REPO")"
    case "$PV_RPLAN" in */plans/*) CF_DOCS="${PV_RPLAN%/plans/*}" ;; esac
    CF_SLUG="$(proof_plan_slug "$PV_RPLAN")"
    CF_FILE="$CF_DOCS/record/$CF_SLUG/continuation.md"
    if [ ! -f "$CF_FILE" ] || [ -L "$CF_FILE" ]; then
      die "REFUSED — no continuation at $CF_FILE (close-out writes it at close); nothing was written."
      exit 1
    fi
    case "$CF_TEXT" in
      *'<fill:'*)
        die "REFUSED — the text is itself a fill mark; write the fact. Nothing was written."
        exit 1 ;;
    esac
    CF_SUM="$(cksum < "$CF_FILE" 2>/dev/null)"
    PV_NEW="$CF_FILE.continuation-fill.$$"
    PV_RC=0
    CF_FIELD="$CF_FIELD" CF_TEXT="$CF_TEXT" CF_LIST="$PV_NEW.2" awk '
      BEGIN { f = ENVIRON["CF_FIELD"]; text = ENVIRON["CF_TEXT"]; list = ENVIRON["CF_LIST"] }
      { L[++nl] = $0 }
      END {
        for (i = 1; i <= nl; i++) {
          x = L[i]
          while ((p = index(x, "<fill: ")) > 0) {
            x = substr(x, p + 7); q = index(x, ">"); if (!q) break
            lab = substr(x, 1, q - 1); x = substr(x, q + 1)
            if (!(lab in seen)) { seen[lab] = 1; labs[++nlab] = lab }
          }
        }
        for (k = 1; k <= nlab; k++) if (labs[k] == f) { exact = labs[k] }
        if (exact != "") { hit = exact; nhit = 1 }
        else for (k = 1; k <= nlab; k++) {
          lab = labs[k]
          if (index(lab, f) == 1 && substr(lab, length(f) + 1, 1) !~ /[A-Za-z0-9]/) { nhit++; hit = lab }
        }
        if (nhit != 1) { for (k = 1; k <= nlab; k++) print labs[k] > list; exit (nhit ? 5 : 3) }
        mark = "<fill: " hit ">"
        for (i = 1; i <= nl; i++) {
          x = L[i]; out = ""
          while ((p = index(x, mark)) > 0) { out = out substr(x, 1, p - 1) text; x = substr(x, p + length(mark)) }
          print out x
        }
        print hit > list
      }' "$CF_FILE" > "$PV_NEW" 2>/dev/null || PV_RC=$?
    case "$PV_RC" in
      0) : ;;
      3|5)
         if [ "$PV_RC" = 3 ]; then die "REFUSED — no fill mark of $CF_FILE is named '$(clean "$CF_FIELD")'; nothing was written."
         else die "REFUSED — more than one fill mark of $CF_FILE opens with '$(clean "$CF_FIELD")'; name more of it. Nothing was written."; fi
         if [ -s "$PV_NEW.2" ]; then die "The fields left: $(paste -sd'|' - < "$PV_NEW.2" | sed 's/|/; /g')."
         else die "The continuation carries no fill mark."; fi
         exit 1 ;;
      *) die "REFUSED — the mark cannot be filled (awk exit $PV_RC); nothing was written."
         exit 2 ;;
    esac
    CF_HIT="$(cat "$PV_NEW.2" 2>/dev/null)"
    pv_file_swap continuation-fill "$CF_FILE" "$CF_SUM" "the mark <fill: $CF_HIT>"
    CF_LEFT="$(/usr/bin/grep -o '<fill:' "$CF_FILE" | wc -l | tr -d ' ')"
    CF_W=marks; [ "$CF_LEFT" = 1 ] && CF_W=mark
    say "continuation-fill — <fill: $(clean "$CF_HIT")> filled in $CF_FILE; $CF_LEFT fill $CF_W left."
    exit 0
  }

  # THE BRIEF, RENDERED FROM ITS ROW (wave-33 T9; REQ-4 AC-4.4, D8). The rules are written above the helpers
  # (`poker_brief_cell`). It reads the bound plan and writes one file under record/<wave>/briefs/, so it takes
  # no plan transaction: the plan is never changed. REFUSED (1), nothing written: an id that is no row id, a
  # plan with no ## Tasks table, a row the table does not have (the refusal names the rows and a corrected
  # call), a row the table carries twice. REFUSED (2): the shipped scaffold or lib/proof.sh cannot be read.
  # A row the table fills badly is not a refusal: its slot is written as `<ORCHESTRATOR: …>`, which the dispatch
  # wall reads as an unfilled slot and marks, so a brief typed over it is the only way past.
  poker_verb_brief() {
    plan_verb_open brief
    if ! plan_verb_id_ok "$BRF_ID"; then
      die "REFUSED — '$(clean "$BRF_ID")' is not one row id: an id is one token of letters, digits, '.', '_' or '-', beginning with a letter or a digit. Nothing was written."
      exit 1
    fi
    BRF_ROWS="$(units_rows "$PV_PLAN" 2>/dev/null)" || BRF_ROWS=""
    if [ -z "$BRF_ROWS" ]; then
      die "REFUSED — $PV_PLAN carries no ## Tasks table with a row, so there is nothing to render. Nothing was written."
      exit 1
    fi
    BRF_ROW="$(printf '%s\n' "$BRF_ROWS" | awk -F'\t' -v id="$BRF_ID" '$1 == id')"
    BRF_N=0; [ -z "$BRF_ROW" ] || BRF_N="$(printf '%s\n' "$BRF_ROW" | wc -l | tr -d ' ')"
    if [ "$BRF_N" -ne 1 ]; then
      BRF_IDS="$(printf '%s\n' "$BRF_ROWS" | awk -F'\t' '{ printf "%s%s", (n++ ? ", " : ""), $1 }')"
      BRF_EG="$(printf '%s\n' "$BRF_ROWS" | awk -F'\t' '$10 == "pending" { print $1; exit }')"
      [ -n "$BRF_EG" ] || BRF_EG="$(printf '%s\n' "$BRF_ROWS" | awk -F'\t' 'NR == 1 { print $1 }')"
      if [ "$BRF_N" -eq 0 ]; then
        die "REFUSED — the plan has no row $(clean "$BRF_ID"). Its rows: $BRF_IDS. Write: bash ${HOOK_DIR}/session-poker.sh brief $BRF_EG. Nothing was written."
      else
        die "REFUSED — the ## Tasks table carries the row $BRF_ID $BRF_N times; which one is meant is not the verb's to guess. Nothing was written."
      fi
      exit 1
    fi
    BRF_LABELS="$(poker_brief_labels)" || BRF_LABELS=""
    if [ -z "$BRF_LABELS" ]; then
      die "REFUSED — the shipped scaffold cannot be read (${HOOK_DIR}/../skills/canonical-sdlc/dispatch.md, its ### Scaffold fence); a brief is rendered from it, never from a copy. Nothing was written."
      exit 2
    fi
    BRF_TASK="$(units_field "$BRF_ROW" task)"
    BRF_KIND="$(units_field "$BRF_ROW" kind)"
    BRF_STEP="$(units_field "$BRF_ROW" step)"
    BRF_SIZE="$(units_field "$BRF_ROW" size)"
    BRF_FILES="$(units_field "$BRF_ROW" Files)"
    BRF_STATUS="$(units_field "$BRF_ROW" status)"
    BRF_SERVES="$(units_field "$BRF_ROW" serves)"
    BRF_DEPS="$(units_field "$BRF_ROW" deps)"
    BRF_WAVE="$(proof_plan_slug "$PV_PLAN")"
    BRF_DOCS="$(docs_root "$PV_REPO")"
    BRF_RECDIR="$BRF_DOCS/record/$BRF_WAVE"
    case "$BRF_RECDIR" in "$PV_REPO"/*) BRF_RECREL="${BRF_RECDIR#"$PV_REPO"/}" ;; *) BRF_RECREL="$BRF_RECDIR" ;; esac
    BRF_OUT="$BRF_RECDIR/briefs/$BRF_ID.md"

    # THE ARTIFACT (wave-37 T6; REQ-7 AC-7.1; D10): the row's own `artifact` Tasks cell, the ledger's cell for the
    # row, the Files entry named for the row, the first record entry, then the record the task names. One path or nothing.
    BRF_ART=""
    BRF_ACELL="$(poker_brief_cell "$PV_PLAN" Tasks "$BRF_ID" artifact)" || BRF_ACELL=""
    if ! poker_brief_none "$BRF_ACELL"; then
      case "$BRF_ACELL" in *[[:space:],]*) : ;; *) BRF_ART="$BRF_ACELL" ;; esac
    fi
    BRF_LEDGER="$(poker_brief_cell "$PV_PLAN" "Dispatch ledger" "$BRF_ID" artifact)" || BRF_LEDGER=""
    if [ -z "$BRF_ART" ] && ! poker_brief_none "$BRF_LEDGER"; then
      case "$BRF_LEDGER" in *[[:space:],]*) : ;; *) BRF_ART="$BRF_LEDGER" ;; esac
    fi
    [ -n "$BRF_ART" ] || BRF_ART="$(poker_brief_record_entry "$BRF_FILES" artifact "$BRF_ID")"
    [ -n "$BRF_ART" ] || BRF_ART="$(poker_brief_task_record "$BRF_TASK")"
    # A READER ROW'S ARTIFACT IS ITS RECORD (wave-35 T8; REQ-6 AC-6.1; D15): a verify, test or review row that
    # names none writes <record dir>/<row>.md, the progress artifact's convention, and its Files line carries it.
    BRF_FILES_LINE="$BRF_FILES"
    if [ -z "$BRF_ART" ] && poker_reader_kind "$BRF_KIND"; then
      BRF_ART="$BRF_RECREL/$BRF_ID.md"
      if poker_brief_none "$BRF_FILES"; then BRF_FILES_LINE="$BRF_ART"; else BRF_FILES_LINE="$BRF_FILES, $BRF_ART"; fi
    fi

    # THE HEAD: the working branch's own tip, or what is missing, in words. Never a guess.
    BRF_WB="$(plan_working_branch "$PV_PLAN")"; BRF_SHA=""
    if [ -z "$BRF_WB" ]; then
      BRF_HEAD="(the plan names no working branch)"
    else
      BRF_SHA="$(git -C "$PV_REPO" rev-parse --verify -q "refs/heads/$BRF_WB^{commit}" 2>/dev/null)" || BRF_SHA=""
      if [ -n "$BRF_SHA" ]; then BRF_HEAD="$BRF_SHA ($(clean "$BRF_WB"))"; else BRF_HEAD="(no branch $(clean "$BRF_WB") in this repository)"; fi
    fi

    # THE SUITES AND WHAT THE ROW LANDS ON: its own cells when it has them, else its Files' *.test.sh entries, in
    # order, and then (a row whose Files write the head) every further suite that reads those files at the working
    # head (wave-35 T8; wave-36 T27, REQ-6 AC-6.1, D12: the reads index, the fact the dispatch wall holds Lands-on:
    # to), sorted, once each; else the slot: `none` is a waiver nobody chose for a row that writes code.
    BRF_SUITES="$(poker_brief_cell "$PV_PLAN" Tasks "$BRF_ID" suites)" || BRF_SUITES=""
    BRF_SUITE_SLOT=""
    BRF_LANDS="$(poker_brief_cell "$PV_PLAN" Tasks "$BRF_ID" lands-on)" || BRF_LANDS=""
    poker_brief_none "$BRF_SUITES" && BRF_SUITES="$(poker_brief_suites "$BRF_FILES")"
    BRF_IDX=""
    if units_writes_head "$BRF_FILES"; then
      # THE INDEX IS UNIONED WHETHER OR NOT THE ROW HAS CELLS (wave-39 T23; REQ-17 AC-17.1; D22): the dispatch wall
      # refuses a Lands-on: that omits a suite the index names for the Files, and one outside Suites:, so a row's own
      # cells end nothing: Suites: is them with the index's suites after, and Lands-on: is its cell (else the Suites)
      # with the same after. A `none` Lands-on cell is the wall's refusal for a row that writes code, so it is not carried.
      BRF_IDX="$(poker_brief_index_suites "$PV_REPO" "${BRF_SHA:--}" "$BRF_FILES")"
      BRF_SUITES="$(poker_brief_union "$BRF_SUITES" "$BRF_IDX")"
      [ -n "$BRF_SUITES" ] || BRF_SUITE_SLOT="<ORCHESTRATOR: no suite reads these Files (reads index); write the suites that pin them>"
      case "$BRF_LANDS" in none|none[[:space:]]*) BRF_LANDS="" ;; esac
    fi
    if poker_brief_none "$BRF_LANDS"; then
      BRF_LANDS="$BRF_SUITES"
      [ -n "$BRF_LANDS" ] || BRF_LANDS="$BRF_SUITE_SLOT"
      [ -n "$BRF_LANDS" ] || BRF_LANDS="none the row's Files name no suite"
    else
      BRF_LANDS="$(poker_brief_union "$BRF_LANDS" "$BRF_IDX")"
    fi
    [ -n "$BRF_SUITES" ] || BRF_SUITES="${BRF_SUITE_SLOT:-none}"

    # THE SCAFFOLD, in the shipped order. A label the verb has no value for is the orchestrator's: it is named, not written.
    BRF_SLOT="<ORCHESTRATOR: the row has none; write it>"
    BRF_BODY="$(mktemp "${TMPDIR:-/tmp}/brief.XXXXXX")" || { die "REFUSED — no scratch file can be made. Nothing was written."; exit 2; }
    BRF_LEFT=""
    case "$BRF_SIZE" in ''|*[!0-9]*) BRF_BIG=no ;; *) if [ "$BRF_SIZE" -ge 15 ]; then BRF_BIG=yes; else BRF_BIG=no; fi ;; esac
    BRF_PROG="$(poker_brief_record_entry "$BRF_FILES" progress "$BRF_ID")"
    [ -n "$BRF_PROG" ] || BRF_PROG="$BRF_RECREL/$BRF_ID.progress.md"
    while IFS= read -r BRF_L; do
      case "$BRF_L" in
        "Expected duration")
          case "$BRF_SIZE" in
            ''|*[!0-9]*) printf '%s: <ORCHESTRATOR: the row'"'"'s size is %s; write the minutes>\n' "$BRF_L" "${BRF_SIZE:-empty}" ;;
            *) printf '%s: %s minutes\n' "$BRF_L" "$BRF_SIZE" ;;
          esac ;;
        "Expected artifact") printf '%s: %s\n' "$BRF_L" "${BRF_ART:-$BRF_SLOT}" ;;
        "Progress artifact") [ "$BRF_BIG" = yes ] && printf '%s: %s\n' "$BRF_L" "$BRF_PROG" ;;
        "Cadence")           [ "$BRF_BIG" = yes ] && printf '%s: 15 min\n' "$BRF_L" ;;
        "Files")             poker_brief_none "$BRF_FILES_LINE" || printf '%s: %s\n' "$BRF_L" "$BRF_FILES_LINE" ;;
        "Suites")            printf '%s: %s\n' "$BRF_L" "$BRF_SUITES" ;;
        "Row")               printf '%s: %s\n' "$BRF_L" "$BRF_ID" ;;
        "Lands-on")          printf '%s: %s\n' "$BRF_L" "$BRF_LANDS" ;;
        *)                   BRF_LEFT="${BRF_LEFT:+$BRF_LEFT, }$BRF_L" ;;
      esac
    done > "$BRF_BODY" <<BRF_EOF
$BRF_LABELS
BRF_EOF
    {
      cat "$BRF_BODY"
      printf '\n## The row\n\n%s\n\n' "$BRF_TASK"
      printf 'Row %s: kind %s, step %s, serves %s, waits on %s, status %s.\n' "$BRF_ID" "$BRF_KIND" "$BRF_STEP" "$BRF_SERVES" "$BRF_DEPS" "$BRF_STATUS"
      printf 'Working head: %s\n' "$BRF_HEAD"
      printf 'Plan: %s\n\n' "$(clean "${PV_PLAN#"$PV_REPO"/}")"
      # THE ORCHESTRATOR'S SECTION: kept whole from a brief already there, else the two marked slots.
      if [ -f "$BRF_OUT" ] && /usr/bin/grep -q '^## Judgment[[:space:]]*$' "$BRF_OUT"; then
        awk '/^## Judgment[[:space:]]*$/ { f = 1 } f { print }' "$BRF_OUT"
      else
        printf '## Judgment\n\n'
        printf 'Research to read: <ORCHESTRATOR: the record files this row reads, or none>\n'
        printf 'Rulings: <ORCHESTRATOR: the rulings that bind this row, by assumption id, or none>\n'
      fi
    } > "$BRF_BODY.new"
    mkdir -p "${BRF_OUT%/*}" 2>/dev/null
    if ! mv -f "$BRF_BODY.new" "$BRF_OUT" 2>/dev/null; then
      rm -f "$BRF_BODY" "$BRF_BODY.new"
      die "REFUSED — $BRF_OUT cannot be written. The plan is unchanged."
      exit 2
    fi
    rm -f "$BRF_BODY"
    say "brief — $BRF_ID: written to ${BRF_OUT#"$PV_REPO"/}. Scaffold lines left to the orchestrator: ${BRF_LEFT:-none}. Under ## Judgment: the research to read and the rulings."
    exit 0
  }

  # THE SPLIT (wave-30 T17; REQ-12 AC-12.6, D14d-3, design-ledger Δ11: "the machine finds and records
  # a split; the mind decides it"). Which row to split and where to cut it are the orchestrator's
  # (steps/4.md, "Splitting a row"); this verb performs the cut it is handed, as task-add's
  # transaction: refused below Step 4 as task-add is, on a parent that is not `pending` (an active
  # row's writer is in its tree), and on children whose Files are not a cover of the parent's
  # (`units_split_check`); then `units_split_row` projects the split onto the copy, `units_validate`
  # judges the whole plan, the copy is held to its own claim — no row waits on the dropped parent, and
  # each open row that did waits on a child (`units_split_dependents`, `units_edges`) — and only then
  # the dry commit and the swap. Any refusal leaves the plan byte-identical.
  poker_verb_task_split() {
    plan_verb_open task-split
    TS_CUR="${PV_CUR%[ab]}"
    case "$TS_CUR" in
      ''|*[!0-9]*)
        die "REFUSED — $PV_PLAN has current: ${TS_CUR:-(none)}; task-split changes a wave plan past Step-3 approval, whose current: is a step number."
        exit 1 ;;
    esac
    if [ "$TS_CUR" -lt 4 ]; then
      die "REFUSED — $PV_PLAN is at current: $TS_CUR; before Step-3 approval the plan is written by hand and reviewed, not split."
      exit 1
    fi
    TS_REC="$(units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' -v p="$TS_ID" '$1 == p')"
    case "$(printf '%s' "$TS_REC" | /usr/bin/grep -c .)" in
      1) : ;;
      0) die "REFUSED — the ## Tasks table of $PV_PLAN carries no row $(clean "$TS_ID"); the plan is unchanged."; exit 1 ;;
      *) die "REFUSED — the ## Tasks table carries more than one row $TS_ID; which one is meant is not the verb's to guess. The plan is unchanged."; exit 1 ;;
    esac
    TS_ST="$(units_field "$TS_REC" status)"
    if [ "$TS_ST" != pending ]; then
      die "REFUSED — $TS_ID is ${TS_ST:-(no status)}; task-split rewrites a pending row only. The plan is unchanged."
      exit 1
    fi
    TS_VIOL="$(units_split_check "$TS_ID" "$(units_field "$TS_REC" Files)" "${TS_CHECK[@]}")"
    if [ -n "$TS_VIOL" ]; then
      die "REFUSED — the children's Files are not a partition of $TS_ID's; the plan is unchanged:"
      printf '%s\n' "$TS_VIOL" >&2
      exit 1
    fi
    TS_WAITERS="$(units_split_dependents "$PV_PLAN" "$TS_ID")"
    PV_RC=0
    units_split_row "$PV_PLAN" "$TS_ID" "$(iso_now)" "${TS_ARGS[@]}" > "$PV_NEW" 2>/dev/null || PV_RC=$?
    if [ "$PV_RC" -ne 0 ] || [ ! -s "$PV_NEW" ]; then
      die "REFUSED — the split of $TS_ID cannot be written (units_split_row exit $PV_RC: a value no table cell can hold, or no ## SDLC State); the plan is unchanged."
      exit 1
    fi
    TS_VIOL="$(units_validate "$PV_NEW" 2>&1)"
    if [ -n "$TS_VIOL" ]; then
      die "REFUSED — with $TS_ID split into $TS_IDS, the ## Tasks table breaks the Task invariants; the plan is unchanged:"
      printf '%s\n' "$TS_VIOL" >&2
      exit 1
    fi
    TS_LEFT="$(units_split_dependents "$PV_NEW" "$TS_ID")"
    TS_EDGES="$(units_edges "$PV_NEW" 2>/dev/null)"
    TS_OPEN="$(units_rows "$PV_NEW" 2>/dev/null | awk -F'\t' '$10 == "pending" || $10 == "active" { print $1 }')"
    for _ts_w in $TS_WAITERS; do
      /usr/bin/grep -Fxq -- "$_ts_w" <<<"$TS_OPEN" || continue
      printf '%s\n' "$TS_EDGES" | awk -F'\t' -v w="$_ts_w" -v k=", $TS_IDS," '$2 == w && index(k, ", " $1 ",") { f = 1 } END { exit !f }' \
        || TS_LEFT="${TS_LEFT:+$TS_LEFT }$_ts_w"
    done
    if [ -n "$TS_LEFT" ]; then
      die "REFUSED — after the split these rows would still wait on $TS_ID, or on no child of it: $(printf '%s' "$TS_LEFT" | tr '\n' ' ' | sed 's/ $//'); the plan is unchanged."
      exit 1
    fi
    TS_K="$(printf '%s' "$TS_WAITERS" | /usr/bin/grep -c .)"
    plan_verb_swap task-split "$TS_ID split into $TS_IDS" writer
    say "task-split — $TS_ID → $TS_IDS; $TS_K dependent(s) re-pointed; written to $PV_PLAN, dry-committed first."
    exit 0
  }

  # ---------------------------------------------------------------- the release approval card
  #
  # THE PAGE THE AUTONOMOUS HALF WAITS ON. `release-approval [--preview] [--against <key>]... [<plan>]` renders, from
  # the record and nothing else, what the run reached, what the machine proved, what the readers judged and what is
  # the user's, in that order, a blank line between sections. The verb gathers the facts and `card.sh release` draws
  # the page from them, each line folded at the shared width as every card is:
  #
  #   Release approval · <project> <release> · <weekday> <H:MM AM/PM> · head <8> · <k> of <m> tasks landed
  #   Bottom line   whether every check holds, what the release changes of its own check, the criteria not proved,
  #                 what is owed, the recommendation
  #   Goals         each goal the plan declares, its mark and its reading, reached ones included
  #   hand-holds    one line, landing-report's counts over the window from the last build landing to this render
  #   test-ratio    one line beside it, the release check's count of shell lines under tests/ against the rest
  #   Tests         acceptance (the matrix) and regression (the last whole run's proof line): two claims
  #   Reviews       evidence, adversarial, structure: each question's newest reading, by the role that holds it
  #   Findings      a count, then one sentence each, the severity code first: fixed / awaiting your decision / carried
  #   Decisions     numbered, the recommendation first and the default second, then the reply line
  #
  # WHAT IS A DECISION. Every approval an open row reads that is not yet given; every question waiver the person
  # owes; every matrix row neither proved nor waived (only the user waives a criterion, or confirms a T4 row's own
  # check); and a finding only when the orchestrator recommends against the policy's default,
  # `--against finding:<record>#<n>`. Every other finding follows the policy by severity and is a line under
  # Findings; one that names a criterion put as a decision waits on that decision. A decision has two choices, its
  # default and the other one; the recommendation is the default unless `--against <key>` names it. The regression
  # is never a decision: a head without a green whole run is early.
  #
  # THE ACTING RENDER. On the session's bound run, when `card.sh early` holds, the page is printed, each approval and
  # waiver it puts is opened on the person's ledger, and the page is written beside the run's records as
  # `release-approval-<head8>.md` with its replay table, which `reply` reads:
  #
  #   release-approval/v1|plan=<plan>|head=<40-hex>|at=<ISO>|decisions=<n>
  #   release-approval/v1|dec=<k>|key=<key>|default=<verb args…|->|other=<verb args…|->|pick=<default|other>|choices=<word>/<word>|why=<why|->
  #
  # `choices=` holds the word a reply names each choice by, the default's then the other's: the first word of its label.
  #
  # Early, it prints `CARD-EARLY — <reason>` on stderr, exit 1, and writes nothing. `--preview` renders the page
  # whatever the facts, the reason first when it is early, and records no page and opens no item. REFUSED (1),
  # nothing written: a plan that is not the bound run, a branch naming no commit, an `--against` naming nothing the
  # page holds. A page written under the card's old name (`$RR_OLD_VERB`, set in session-poker.sh) is read all the same, by
  # `reply` and the situation report, and is never written again: only the new stem and tag are written.
  rr_field() {  # <disposition line> <name> -> the value of name="…" or of name=<word>
    local l="$1" n="$2" v
    case "$l" in
      *" $n=\""*) v="${l#* "$n"=\"}"; if [ "$n" = title ]; then v="${v%\"}"; else v="${v%%\"*}"; fi ;;
      *" $n="*) v="${l#* "$n"=}"; v="${v%% *}" ;;
      *) v="" ;;
    esac
    printf '%s' "$v"
  }

  # rr_rows <plan> -> `<AC>\037<tier>\037<status>\037<auditor>\037<ruled 1|0>` per five-cell matrix row, table order.
  # THE RULING IS walls.sh's: each row is read by its readers (`matrix_section`, `matrix_block`, `user_confirmed_value`,
  # `matrix_row_waiver`) and judged by `matrix_row_ruled`, sourced in a subshell as the facts judge sources it, so the
  # card and the gate cannot answer one row two ways. The auditor cell is printed as `placeholder_cell` folds it, `-`
  # when it means none, so `—`, `-`, `n/a` and an empty cell read alike. Exit 2 when walls.sh cannot be loaded: the
  # card never guesses a ruling.
  rr_rows() {
    [ -f "$BIONIC_LIB/walls.sh" ] || return 2
    ( . "$BIONIC_LIB/walls.sh" >/dev/null 2>&1 && declare -F matrix_row_ruled >/dev/null 2>&1 || exit 2
      PLAN="$1"; MATRIX="$(matrix_section)"
      while IFS=$'\037' read -r ac tier status ev aud; do
        [ -n "$ac" ] || continue
        block="$(matrix_block "$ac")"
        waiver=0; matrix_row_waiver "$ev" "$block" && waiver=1
        ruled=0; matrix_row_ruled "$tier" "$status" "$aud" "$(user_confirmed_value "$block")" "$waiver" && ruled=1
        aud="$(placeholder_cell "$aud")"
        printf '%s\037%s\037%s\037%s\037%s\n' "$ac" "$tier" "$status" "${aud:--}" "$ruled"
      done <<RR_MATRIX
$(awk -F'|' '/^[[:space:]]*\|/ && NF == 7 {
    for (i = 2; i <= 6; i++) gsub(/^[ \t]+|[ \t]+$/, "", $i)
    if ($2 == "" || $2 == "AC" || $2 ~ /^[-:]+$/) next
    printf "%s\037%s\037%s\037%s\037%s\n", $2, $3, $4, $5, $6
  }' <<< "$MATRIX")
RR_MATRIX
    )
  }

  rr_block_key() {  # <plan> <AC> <key> -> the first value of <key>: in the AC's block, or nothing
    RR_AC="$2" RR_BK="$3" awk "$(units_ac_head_awk)"'
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^## / { inm = ($0 ~ /^## Verification Matrix/); inb = 0; next }
      !inm { next }
      ac_head($0, ENVIRON["RR_AC"]) { inb = 1; next }
      inb && /^[^[:space:]]/ { inb = 0 }
      inb {
        l = $0; sub(/^[ \t]+/, "", l); k = ENVIRON["RR_BK"] ":"
        if (index(l, k) == 1) { v = substr(l, length(k) + 1); sub(/^[ \t]+/, "", v); print v; exit }
      }' "$1"
  }

  rr_approved() {  # <plan> <name> -> the plan's approved: line for it, or nothing
    RR_NM="$2" awk '
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc && /^approved:[ \t]/ { split($0, w, /[ \t]+/); if (w[2] == ENVIRON["RR_NM"] && w[3] == "by") { print; exit } }' "$1"
  }

  rr_sdlc_value() {  # <plan> <field> -> the value of `<field>:` under ## SDLC State, or nothing
    RR_F="$2" awk '
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc && index($0, ENVIRON["RR_F"] ":") == 1 { v = substr($0, length(ENVIRON["RR_F"]) + 2); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); print v; exit }' "$1"
  }

  rr_proof_field() {  # <proof line> <name> -> the value of name=<word> on it, or nothing
    case " $1 " in *" $2="*) local v="${1#* "$2"=}"; [ "$v" != "$1" ] || v="${1#"$2"=}"; printf '%s' "${v%% *}" ;; esac
  }

  rr_question_of() {  # <plan> <evidence> -> the question of the newest reading that cites it
    RR_EV="$2" awk "$(proof_awk)"'
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc && proof_fields($0) && PROOF_KIND == "review" && PROOF_EVIDENCE == ENVIRON["RR_EV"] { q = PROOF_QUESTION }
      END { print q }' "$1"
  }

  rr_carried() {  # <record dir> <finding id> -> 0 when a replied page of this run applied its carry
    local f
    for f in "$1"/release-approval-*.md "$1/$RR_OLD_VERB"-*.md; do
      [ -f "$f" ] || continue
      /usr/bin/grep -qxF "applied: finding:$2 carried" "$f" 2>/dev/null && return 0
    done
    return 1
  }

  rr_add() {  # <kind> <key> <default verb> <other verb> <why> <subject> <default label> <other label> <default phrase> <other phrase>
    RR_KIND[RR_N]="$1"; RR_KEY[RR_N]="$2"; RR_DO[RR_N]="$3"; RR_ELSE[RR_N]="$4"; RR_WHYS[RR_N]="$5"
    RR_SUBJ[RR_N]="$6"; RR_DLAB[RR_N]="$7"; RR_OLAB[RR_N]="$8"; RR_DPH[RR_N]="$9"; RR_OPH[RR_N]="${10}"
    RR_PICK[RR_N]=default
    printf '%s' "$RR_AGAINST" | /usr/bin/grep -qxF -- "$2" && RR_PICK[RR_N]=other
    RR_N=$((RR_N + 1))
  }

  rr_dec_of() {  # <key> -> the decision number the page gives it, or nothing
    local i
    for ((i = 0; i < RR_N; i++)); do [ "${RR_KEY[$i]}" != "$1" ] || { printf '%s' "$((i + 1))"; return 0; }; done
    return 1
  }

  rr_word() {  # <label> -> the one word a reply names that choice by: its first, in lower case
    local w="${1%% *}"; w="${w%,}"
    printf '%s' "$w" | tr '[:upper:]' '[:lower:]'
  }

  rr_plural() {  # <n> <singular> <plural> -> `<n> <word>`
    if [ "$1" -eq 1 ]; then printf '1 %s' "$2"; else printf '%s %s' "$1" "$3"; fi
  }

  rr_fact() {  # <tag> <field>... -> one fact line, its fields tab-separated; a tab or newline inside a field is a space
    local f out="$1"; shift
    for f in "$@"; do f="${f//$'\t'/ }"; out="$out"$'\t'"${f//$'\n'/ }"; done
    printf '%s\n' "$out"
  }

  rr_facts() {  # -> the RR_* facts the verb gathered, in the tagged lines `card.sh release` draws the page from
    local i l
    rr_fact title "$RR_PROJ" "$RR_REL" "$(sitrep_date "$(sitrep_now)" '%A %-I:%M %p')" "$RR_H8" "$RR_LANDED" "$RR_TOTAL"
    [ -z "$RR_EARLY" ] || rr_fact early "${RR_EARLY#CARD-EARLY — }"
    [ "$RR_PREVIEW" != yes ] || rr_fact preview
    rr_fact criteria "$RR_ACT" "$RR_ACW"
    for l in $RR_MISS; do rr_fact miss "$l"; done
    printf '%s\n' "$RR_CHG" | tr ',' '\n' | while IFS= read -r l; do [ -z "$l" ] || rr_fact check "$l"; done
    printf '%s\n' "$RR_ASIDE" | while IFS= read -r l; do [ -z "$l" ] || rr_fact aside "$l"; done
    for ((i = 0; i < RR_N; i++)); do
      rr_fact decision "${RR_KIND[$i]}" "${RR_KEY[$i]}" "${RR_PICK[$i]}" "${RR_SUBJ[$i]}" "${RR_DLAB[$i]}" "${RR_OLAB[$i]}" \
        "${RR_DPH[$i]}" "${RR_OPH[$i]}"
    done
    [ "$RR_N" -eq 0 ] || rr_fact reply "$(rr_word "${RR_OLAB[0]}")"
    # each goal's mark is its status, lib/plan.sh plan_goal_status's, the one the sitrep's sheet prints
    [ -z "$RR_GOALS" ] || printf '%s\n' "$RR_GOALS" | while IFS= read -r l; do
      [ -n "$l" ] || continue
      case "$(plan_goal_status "${l%%	*}")" in
        met) m="$SITREP_MARK_WITHIN" ;;
        'not met') m="$SITREP_MARK_OVER" ;;
        *) m="$SITREP_MARK_NONE" ;;
      esac
      printf 'goal\t%s\t%s\t%s\n' "${l%%	*}" "$m" "${l#*	}"
    done
    [ -z "${RR_HH:-}" ] || rr_fact handholds "$RR_HH"
    [ -z "${RR_TR:-}" ] || rr_fact ratio "$RR_TR"
    rr_fact acceptance "$RR_TACC"
    rr_fact regression "$RR_TREG"
    printf '%s\n' "$RR_REVIEWS" | while IFS= read -r l; do [ -z "$l" ] || rr_fact review "$l"; done
    rr_fact findings "$RR_FN" "$RR_FNF" "$RR_FNA" "$RR_FNC" "$RR_FROWS"
    printf '%s\n' "$RR_FLINES" | awk 'NF { print "finding\t" $0 }'
  }

  rr_record() {  # <page text> -> writes the page and its replay table beside the run's records; prints nothing
    local f n=2 i
    f="$RR_DIR/release-approval-$RR_H8.md"
    while [ -f "$f" ] && /usr/bin/grep -q '^replied: ' "$f" 2>/dev/null; do
      f="$RR_DIR/release-approval-$RR_H8-$n.md"; n=$((n + 1))
    done
    mkdir -p "$RR_DIR" 2>/dev/null || return 0
    [ ! -L "$f" ] || return 0
    {
      printf '%s\n\n## Replay\n\n' "$1"
      printf 'release-approval/v1|plan=%s|head=%s|at=%s|decisions=%s\n' "$PV_PLAN" "$RR_HEAD" "${RR_AT:-$(iso_now)}" "$RR_N"
      for ((i = 0; i < RR_N; i++)); do
        printf 'release-approval/v1|dec=%s|key=%s|default=%s|other=%s|pick=%s|choices=%s/%s|why=%s\n' "$((i + 1))" "${RR_KEY[$i]}" \
          "${RR_DO[$i]}" "${RR_ELSE[$i]}" "${RR_PICK[$i]}" "$(rr_word "${RR_DLAB[$i]}")" "$(rr_word "${RR_OLAB[$i]}")" "${RR_WHYS[$i]}"
      done
      # THE CARRIES THE PAGE PUTS: every finding it shows deferred, so the reply that answers the page rules each.
      printf '%s' "$RR_CARRY" | while IFS= read -r i; do [ -z "$i" ] || printf 'carried: %s\n' "$i"; done
    } > "$f.new.$$" 2>/dev/null && mv -f "$f.new.$$" "$f" 2>/dev/null
    rm -f "$f.new.$$" 2>/dev/null
    return 0
  }

  poker_verb_release_approval() {
    local nm line key reply ac tier st au ruled why fid sev reach state rows stated ttl sent ev q num dec grp h r role behind
    if ! { declare -F proof_branch_head >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_last_line >/dev/null 2>&1; then
      die "REFUSED — the release approval card is read through lib/proof.sh, which cannot be loaded from $BIONIC_LIB; nothing is written."
      exit 2
    fi
    plan_verb_open release-approval
    if [ -n "$RR_ARG" ]; then
      nm="$(cd "$(dirname "$RR_ARG")" 2>/dev/null && pwd -P)/$(basename "$RR_ARG")"
      line="$(cd "$(dirname "$PV_PLAN")" 2>/dev/null && pwd -P)/$(basename "$PV_PLAN")"
      if [ "$nm" != "$line" ]; then
        die "REFUSED — '$(clean "$RR_ARG")' is not the run this session is bound to ($PV_PLAN); the release approval card is the bound run's, and nothing is written."
        exit 1
      fi
    fi
    RR_HEAD="$(proof_branch_head "$PV_PLAN" "$PV_REPO")" || RR_HEAD=""
    case "$RR_HEAD" in
      [0-9a-f]*) : ;;
      *) die "REFUSED — the plan's working branch names no commit, so there is no head to render the release approval card at; nothing is written."; exit 1 ;;
    esac
    RR_H8="${RR_HEAD:0:8}"
    RR_DIR="$(docs_root "$PV_REPO")/record/$(proof_plan_slug "$PV_PLAN")"
    # THE THREE FACTS ARE card.sh's (`early`), asked as this session in the run's root.
    RR_EOUT="$( cd "$PV_REPO" && "${BASH:-bash}" "$(cd "$BIONIC_LIB/.." 2>/dev/null && pwd -P)/card.sh" early "$PV_PLAN" 2>&1 )"; RR_ERC=$?
    RR_EARLY=""
    if [ "$RR_ERC" -ne 0 ]; then
      RR_EARLY="$(printf '%s\n' "$RR_EOUT" | awk '!/^settles: / && NF { print; exit }')"
      RR_EARLY="${RR_EARLY:-card.sh early exited $RR_ERC}"
      if [ "$RR_PREVIEW" != yes ]; then printf '%s\n' "$RR_EARLY" >&2; exit 1; fi
    fi
    RR_SETTLE="$(printf '%s\n' "$RR_EOUT" | sed -n 's/^settles: //p')"

    # THE TITLE'S FACTS: the project, the release, the tasks landed.
    RR_PROJ="$(git -C "$PV_REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
    case "$RR_PROJ" in */.git) RR_PROJ="${RR_PROJ%/.git}"; RR_PROJ="${RR_PROJ##*/}" ;; *) RR_PROJ="${PV_REPO##*/}" ;; esac
    RR_REL="$(plan_frontmatter_get "$PV_PLAN" release 2>/dev/null)"
    RR_UROWS="$(units_rows "$PV_PLAN" 2>/dev/null)"
    set -- $(printf '%s\n' "$RR_UROWS" | awk -F'\t' 'NF >= 10 { t++; if ($10 == "landed") l++ } END { print t + 0, l + 0 }')
    RR_TOTAL="${1:-0}"; RR_LANDED="${2:-0}"
    RR_LANDED_IDS=" $(printf '%s\n' "$RR_UROWS" | awk -F'\t' 'NF >= 10 && $10 == "landed" { printf "%s ", $1 }')"

    RR_N=0; RR_ASIDE=""
    RR_KIND=(); RR_KEY=(); RR_DO=(); RR_ELSE=(); RR_WHYS=(); RR_SUBJ=(); RR_DLAB=(); RR_OLAB=(); RR_DPH=(); RR_OPH=(); RR_PICK=()

    # WAIVERS: the run's open waive: items, then the ones the red check owes, each once; never the regression. The asks
    # are read from the run's register (lib/owed.sh `owed_list_plan`), never the caller's session alone: a waiver a
    # close-out preflight or another session of the run raised is owed here as well.
    RR_WAIVE=""
    while IFS='	' read -r key _ _ reply; do
      case "$key" in
        waive:regression) : ;;
        waive:?*) RR_WAIVE="${RR_WAIVE}${key}"$'\n' ;;
        gate:?*) RR_ASIDE="${RR_ASIDE}${reply#poker: }"$'\n' ;;
      esac
    done <<RR_OWED
$(owed_list_plan "$PV_PLAN" "$PV_REPO" 2>/dev/null)
RR_OWED
    RR_WAIVE="$(printf '%s%s\n' "$RR_WAIVE" "$(printf '%s\n' "$RR_SETTLE" | /usr/bin/grep '^waive:' | /usr/bin/grep -vx 'waive:regression')" | awk 'NF && !seen[$0]++')"
    while IFS= read -r key; do
      [ -n "$key" ] || continue
      q="${key#waive:}"
      line="$(proof_last_line "$PV_PLAN" review "$q" 2>/dev/null)"
      if [ "$(rr_proof_field "$line" result)" = fail ]; then why="failing at this head"; else why="not held at this head"; fi
      rr_add waive "$key" "waive $q" "-" "-" "The $q review, $why" waive withhold "waive the $q review" "hold the $q waiver"
    done <<RR_WAIVES
$RR_WAIVE
RR_WAIVES

    # ROWS: every matrix row, ruled or not as walls.sh rules it (rr_rows). Proved when discharged and ruled, and a T4 row
    # so ruled under an empty-like auditor cell is one the user confirmed; waived when ruled with status waived. Every
    # other row is a decision: a discharged T4 row under an empty-like cell is the user's own check, to confirm
    # (confirm-row) or waive; any other is waived or run, a T4 row's standing finding said in the gate's words.
    RR_ACT=0; RR_ACP=0; RR_ACY=0; RR_ACW=0; RR_ACU=0; RR_ACA=0; RR_ACR=0; RR_MISS=""
    if ! RR_ROWS="$(rr_rows "$PV_PLAN")"; then
      die "REFUSED — the release approval card asks walls.sh for each matrix row's ruling, and $BIONIC_LIB/walls.sh cannot be loaded; nothing is written."
      exit 2
    fi
    while IFS=$'\037' read -r ac tier st au ruled; do
      [ -n "$ac" ] || continue
      RR_ACT=$((RR_ACT + 1))
      if [ "$ruled" = 1 ] && [ "$st" = discharged ]; then
        RR_ACP=$((RR_ACP + 1))
        [ "$tier" != T4 ] || [ "$au" != - ] || RR_ACY=$((RR_ACY + 1))
        continue
      fi
      if [ "$ruled" = 1 ] && [ "$st" = waived ]; then RR_ACW=$((RR_ACW + 1)); continue; fi
      RR_MISS="${RR_MISS:+$RR_MISS }$ac"
      if [ "$tier" = T4 ] && [ "$au" = - ] && [ "$st" = discharged ]; then
        RR_ACA=$((RR_ACA + 1))
        rr_add row "row:$ac" "confirm-row $ac" "waive-row $ac" "a T4 criterion, the user's own check" \
          "$ac, your own check, not confirmed yet" confirm waive "confirm $ac" "waive $ac"
        continue
      fi
      if [ "$st" = discharged ]; then RR_ACU=$((RR_ACU + 1)); else RR_ACR=$((RR_ACR + 1)); fi
      why="$(rr_block_key "$PV_PLAN" "$ac" reason)"
      if [ -z "$why" ]; then
        if [ "$st" != discharged ]; then why="not run on this release"
        elif [ "$tier" = T4 ] && [ "$au" != - ]; then why="the auditor's finding stands ($au)"
        else why="not confirmed by the auditor on this release"; fi
      fi
      rr_add row "row:$ac" "waive-row $ac" "-" "$why" "$ac, $why" waive "run it" "waive $ac" "run $ac"
    done <<RR_ROWS_EOF
$RR_ROWS
RR_ROWS_EOF
    if [ "$RR_ACT" -eq 0 ]; then
      RR_TACC="❔ acceptance — the matrix holds no criterion"
    else
      line=""
      [ "$RR_ACY" -eq 0 ] || line="$RR_ACY confirmed by you"
      [ "$RR_ACW" -eq 0 ] || line="${line:+$line, }$RR_ACW waived by you"
      [ "$RR_ACU" -eq 0 ] || line="${line:+$line, }$RR_ACU not confirmed by the auditor"
      [ "$RR_ACA" -eq 0 ] || line="${line:+$line, }$RR_ACA awaiting your confirmation"
      [ "$RR_ACR" -eq 0 ] || line="${line:+$line, }$RR_ACR not run"
      if [ -z "$RR_MISS" ]; then RR_TACC="✅"; else RR_TACC="✖️"; fi
      RR_TACC="$RR_TACC acceptance — $RR_ACP of $(rr_plural "$RR_ACT" criterion criteria) proved${line:+; $line}"
    fi

    # FINDINGS: the disposition's one reading, one sentence each; a decision only when recommended against.
    RR_FN=0; RR_FNF=0; RR_FNA=0; RR_FNC=0; RR_FLINES=""; RR_FROWS=""; RR_FIDS=""; RR_CARRY=""
    # A PREVIEW OPENS NOTHING: the disposition it reads is handed a ledger key no file can carry, so the person's
    # items the disposition opens on any other run are left unopened here.
    if [ "$RR_PREVIEW" = yes ]; then
      RR_DISP="$( cd "$PV_REPO" && OWED_SID="preview/none" "${BASH:-bash}" "$HOOK_DIR/session-poker.sh" disposition 2>&1 )"
    else
      RR_DISP="$( cd "$PV_REPO" && "${BASH:-bash}" "$HOOK_DIR/session-poker.sh" disposition 2>&1 )"
    fi
    while IFS= read -r line; do
      case "$line" in "poker: finding "*) : ;; *) continue ;; esac
      line="${line#poker: }"
      fid="$(printf '%s' "$line" | awk '{ print $2 }')"; sev="$(printf '%s' "$line" | awk '{ print $3 }')"
      state="$(rr_field "$line" state)"; rows="$(rr_field "$line" row)"; ev="$(rr_field "$line" record)"
      stated="$(rr_field "$line" stated)"; ttl="$(rr_field "$line" title)"
      sent="${stated:-$ttl}"; [ "$sent" != - ] || sent="$ttl"; sent="${sent%.}"
      q="$(rr_question_of "$PV_PLAN" "$ev")"; num="${fid##*#}"
      RR_FN=$((RR_FN + 1)); RR_FIDS="${RR_FIDS}finding:$fid"$'\n'
      [ "$state" != deferred ] || RR_CARRY="${RR_CARRY}$fid"$'\n'
      dec=""; grp=C
      [ "$rows" != "—" ] || rows=""
      if [ "$state" = fixed ] || [ -n "$rows" ]; then
        # FIXED BY ITS ROWS: the disposition's own fixed, or a row born of it or moved to fix it; not landed yet, said.
        grp=F; dec=""
        for ac in $(printf '%s' "$rows" | tr ',' ' '); do
          RR_FROWS="$RR_FROWS $ac"
          case "$RR_LANDED_IDS" in *" $ac "*) : ;; *) dec=open ;; esac
        done
        [ "$state" = fixed ] || [ -z "$dec" ] || sent="$sent (not landed yet)"
        dec=""
      elif printf '%s' "$RR_AGAINST" | /usr/bin/grep -qxF -- "finding:$fid" && ! rr_carried "$RR_DIR" "$fid"; then
        rr_add finding "finding:$fid" "-" "finding-move $fid fix" "the release approval card: fixed instead of carried" \
          "$sent (${q:-a review} #$num)" carry "fix now, one row" "carry ${q:-a} finding $num" "fix ${q:-a} finding $num"
        grp=A; dec="$RR_N"
      else
        for ac in $(printf '%s' "$sent" | /usr/bin/grep -oE 'AC-[0-9]+\.[0-9]+'); do
          dec="$(rr_dec_of "row:$ac")" && { grp=A; break; }
        done
        if [ "$grp" = C ] && [ "$state" = open ]; then grp=A; dec="$(rr_dec_of "waive:$q")" || dec=""; fi
      fi
      case "$grp" in F) RR_FNF=$((RR_FNF + 1)) ;; A) RR_FNA=$((RR_FNA + 1)) ;; C) RR_FNC=$((RR_FNC + 1)) ;; esac
      RR_FLINES="${RR_FLINES}${grp}	${sev}	${sent}${dec:+ (decision $dec)}"$'\n'
    done <<RR_DISP_EOF
$RR_DISP
RR_DISP_EOF
    RR_FROWS="$(printf '%s\n' $RR_FROWS | awk 'NF && !seen[$0]++' | tr '\n' ' ' | sed 's/ $//')"

    # APPROVALS: every name an open row reads, release and merge first, each not yet given.
    RR_NAMES=""
    RR_INTO="$(plan_integration_branch "$PV_PLAN")"
    for nm in release merge $(units_approval_names "$PV_PLAN" 2>/dev/null); do
      [ "$nm" != plan ] || continue
      case " $RR_NAMES " in *" $nm "*) continue ;; esac
      units_approval_names "$PV_PLAN" 2>/dev/null | /usr/bin/grep -qxF "$nm" || continue
      RR_NAMES="$RR_NAMES $nm"
      [ -z "$(rr_approved "$PV_PLAN" "$nm")" ] || continue
      case "$nm" in
        release) line="Release${RR_REL:+ $RR_REL}" ;;
        merge) line="Merge${RR_INTO:+ into $RR_INTO}" ;;
        *) line="Approval $nm" ;;
      esac
      rr_add approve "approve:$nm" "approve $nm" "-" "-" "$line" approve withhold "$nm" "hold the $nm"
    done

    # AN --against THAT NAMES NOTHING ON THE PAGE is refused before anything is written.
    while IFS= read -r key; do
      [ -n "$key" ] || continue
      rr_dec_of "$key" >/dev/null && continue
      printf '%s' "$RR_FIDS" | /usr/bin/grep -qxF -- "$key" && continue
      die "REFUSED — --against $(clean "$key") names nothing the release approval card holds; nothing is written."
      exit 1
    done <<RR_AGAINST_EOF
$RR_AGAINST
RR_AGAINST_EOF

    # GOALS: each goal the plan declares, read by lib/plan.sh `plan_goals_read`, the reader the sitrep reads too.
    RR_GOALS="$(plan_goals_read "$PV_PLAN" "$(_wt_proofs_path "$PV_REPO" "$PV_PLAN")" \
      "$(landing_report "$(_wt_proofs_path "$PV_REPO" "$PV_PLAN")" "$PV_REPO" yes 2>/dev/null)")"

    # THE REGRESSION is the floor judge's answer at the head (`proof_state`), never the whole run's own
    # red list, which a later green landing does not shorten.
    line="$(proof_last_line "$PV_PLAN" regression 2>/dev/null)"
    if [ -z "$line" ]; then
      RR_TREG="✖️ regression — no whole run on record"
    else
      h="$(rr_proof_field "$line" head)"; r="$(rr_proof_field "$line" owed)"
      ev="$(rr_proof_field "$line" evidence)"
      st="$(awk '/^Gating: [0-9]+ passed, [0-9]+ failed$/ { p = $2; f = $4 } END { if (p != "") print p, f }' "$(docs_root "$PV_REPO")/$ev" 2>/dev/null)"
      jv="$(proof_state "$PV_PLAN" "$PV_REPO" 2>/dev/null | awk 'NR == 1')"
      case "$jv" in
        covered"	"*)
          if [ "$h" = "$RR_HEAD" ]; then
            RR_TREG="✅ regression — whole run green at this head"
            [ -z "$st" ] || RR_TREG="$RR_TREG, ${st%% *} of $(( ${st%% *} + ${st##* } )) suites"
          else
            RR_TREG="✅ regression — covered at this head by the whole run at ${h:0:8} and the landings since"
            [ -z "$r" ] || RR_TREG="$RR_TREG, which greened its $(rr_plural "$(printf '%s' "$r" | tr ',' '\n' | /usr/bin/grep -c .)" "failing suite" "failing suites")"
          fi ;;
        owed"	"*) RR_TREG="✖️ regression — still owed at this head: $(printf '%s' "${jv#owed	}" | sed 's/,/, /g')" ;;
        uncovered"	"*) RR_TREG="✖️ regression — not covered at this head: ${jv#uncovered	}" ;;
        *) RR_TREG="✖️ regression — not covered at this head" ;;
      esac
    fi

    # THE REVIEWS: each question's newest reading, by the role the rigor deals it.
    RR_REVIEWS=""
    for q in evidence adversarial structure; do
      role=critic
      [ "$q" != evidence ] || [ "$(plan_frontmatter_get "$PV_PLAN" rigor 2>/dev/null)" != double ] || role=auditor
      line="$(proof_last_line "$PV_PLAN" review "$q" 2>/dev/null)"
      if [ -z "$line" ]; then RR_REVIEWS="${RR_REVIEWS}❔ $q — not read yet"$'\n'; continue; fi
      h="$(rr_proof_field "$line" head)"; r="$(rr_proof_field "$line" result)"
      behind="$(git -C "$PV_REPO" rev-list --count "$h..$RR_HEAD" 2>/dev/null)" || behind=""
      if [ "$h" = "$RR_HEAD" ] || [ "$behind" = 0 ]; then nm="$role at this head"
      elif [ -n "$behind" ]; then nm="$role at ${h:0:8}, $(rr_plural "$behind" commit commits) behind"
      else nm="$role at ${h:0:8}"; fi
      case "$r" in
        pass) RR_REVIEWS="${RR_REVIEWS}✅ $q — $nm"$'\n' ;;
        fail) RR_REVIEWS="${RR_REVIEWS}✖️ $q — $nm, failing"$'\n' ;;
        *) RR_REVIEWS="${RR_REVIEWS}➖ $q — $nm, ${r:-no result}"$'\n' ;;
      esac
    done

    # THE HAND-HOLDS, over the window from the last build landing to this render (line.sh `hand_holds_ends`). The
    # render's own instant is the end and the replay line's `at=`, so landing-report read after the page over the
    # same ends prints this same line.
    RR_AT="$(iso_now)"
    IFS=$'\t' read -r RR_HHS _ _ _ <<< "$(hand_holds_ends "$(_wt_proofs_path "$PV_REPO" "$PV_PLAN")" "$PV_REPO" "$PV_PLAN")"
    [ "${RR_HHS:--}" != - ] || RR_HHS=""
    RR_HH="$(hand_holds_report "$(_wt_proofs_path "$PV_REPO" "$PV_PLAN")" "$PV_REPO" "$PV_PLAN" ${RR_HHS:+--since "$RR_HHS"} --until "$RR_AT")"

    # THE CAP ON TESTS, as the release check printed it: the line is read from the log of the newest check proof
    # (`sitrep_test_ratio`, the reader the situation report's waste line uses), so the page quotes the check and
    # counts nothing. A check that ran at an earlier head says which, and no check says nothing.
    RR_TR=""
    read -r _rr_t _rr_c _rr_h <<< "$(sitrep_test_ratio "$PV_PLAN" "$PV_REPO")"
    if [ -n "${_rr_c:-}" ]; then
      RR_TR="test-ratio: $_rr_t/$_rr_c"
      [ "${_rr_h:-}" = "$RR_HEAD" ] || RR_TR="$RR_TR at ${_rr_h:0:8}"
    fi

    # WHAT THE RELEASE CHANGES OF ITS OWN CHECK: the files of the declared release check's closure that the range from
    # the last release (`release_base`, the release check's own start) to the head changes, read by the door's own
    # reading (lib/worktree.sh `_wt_check_judge`), so the user approving the release knows the check it passed was
    # changed in it.
    RR_CHG=""
    line="$(config_value "$PV_REPO" release-check "" 2>/dev/null)"
    if [ -n "$line" ] && release_base "$PV_PLAN" "$PV_REPO" "$RR_HEAD"; then
      RR_CHG="$(_wt_check_judge "$PV_REPO" "$RB_BASE" "$RR_HEAD" "$line")" && RR_CHG="${RR_CHG#* }" || RR_CHG=""
    fi

    # THE PAGE IS card.sh's (`release`), the renderer every card is drawn by; a page it refuses is never written.
    if ! RR_TEXT="$(rr_facts | "${BASH:-bash}" "$(cd "$BIONIC_LIB/.." 2>/dev/null && pwd -P)/card.sh" release)"; then
      die "REFUSED — card.sh release could not draw the release approval card from its facts; nothing is written."
      exit 2
    fi
    printf '%s\n' "$RR_TEXT"
    [ "$RR_PREVIEW" != yes ] || exit 0
    # THE ACTING RENDER OPENS WHAT IT PUTS on the person's ledger, so the ledger and the page agree, and records it.
    for ((num = 0; num < RR_N; num++)); do
      key="${RR_KEY[$num]}"
      case "$key" in
        approve:*|waive:*) OWED_ROOT="$PV_REPO" OWED_PLAN="$PV_PLAN" owed_open "$key" "${RR_KIND[$num]}: ${key#*:}" \
          "poker: ${key#*:} is decision $((num + 1)) on the release approval card at $RR_H8" >/dev/null 2>&1 || : ;;
      esac
    done
    [ "$RR_N" -eq 0 ] || rr_record "$RR_TEXT"
    exit 0
  }

  # THE REPLY TO THE RELEASE APPROVAL CARD, REPLAYED. `release-approval` writes the page with its replay table, one line per
  # decision with its default, its other choice and the recommendation (`pick=`); the user answers it once, and
  # this verb replays that answer into the record with the user's words. `all default` takes every default, `all
  # recommended` every recommendation. Or the reply orders the decisions by number, items split by commas: `<n>
  # <choice>`, the choice one of the decision's two words (`choices=`), `default` or `recommended`, and a last item
  # `rest default` or `rest recommended` for every decision not named ("1 run, 3 fix, rest default"). Every item is
  # read before anything is applied: one naming no decision on the page, a choice its decision does not offer, a
  # decision twice, or a reply leaving a decision unnamed with no `rest`, refuses the whole reply, naming the item.
  # The decisions are then applied in the page's order. A verb is run as `<verb> <args…> '<the reply>' ['<why>']`; a `-` default is
  # applied as carried (a deferral needs no verb) and a `-` other choice is withheld. Each decision applied is
  # written to the page's record (`applied: <key> …`), a re-run skipping those, and the reply last (`replied: …`),
  # so a page is answered once.
  # REFUSED (1), the plan unchanged: no page for the bound run, a page rendered at another head than the working one
  # (render it again), a page already answered, a reply it cannot read as above, and words the user did not type
  # (lib/said.sh, asked once before any verb runs, so a reply that is not the user's writes nothing).
  rp_items() {  # <normalised reply> -> RP_PICKS (` <n>=<default|other|recommended>` per item) and RP_REST, from RP_TABLE; 1 refused
    local it n c row w dw ow last="" i=0 all left="" k
    local -a items
    RP_PICKS=" "; RP_REST=""
    k="$(printf '%s\n' "$RP_TABLE" | /usr/bin/grep -c .)"
    IFS=',' read -r -a items <<< "$1"
    for it in "${items[@]}"; do
      i=$((i + 1)); it="${it# }"; it="${it% }"
      [ "$i" -lt "${#items[@]}" ] || last=yes
      case "$it" in
        'rest default'|'rest defaults'|'rest recommended')
          if [ -z "$last" ]; then
            die "REFUSED — the reply's item \"$it\" comes before other items, and rest answers what is left once every other item is read: put it last; nothing is applied and the plan is unchanged."
            return 1
          fi
          RP_REST="${it#rest }"; RP_REST="${RP_REST%s}"; continue ;;
      esac
      n="${it%% *}"; c="${it#* }"
      case "$n" in ''|*[!0-9]*) n="" ;; esac
      if [ -z "$n" ] || [ "$c" = "$it" ] || [ "$c" != "${c%% *}" ]; then
        die "REFUSED — the reply's item \"$(clean "$it")\" is not a decision number and a choice: reply \"all recommended\", \"all default\", or by number, as \"1 run, rest default\"; nothing is applied and the plan is unchanged."
        return 1
      fi
      row="$(printf '%s\n' "$RP_TABLE" | /usr/bin/grep -m1 -F "|dec=$n|")"
      if [ -z "$row" ]; then
        die "REFUSED — the reply's item \"$it\" names decision $n, and the release approval card holds decisions 1 to $k; nothing is applied and the plan is unchanged."
        return 1
      fi
      case "$RP_PICKS" in *" $n="*)
        die "REFUSED — the reply names decision $n twice (\"$it\" is the second); nothing is applied and the plan is unchanged."
        return 1 ;;
      esac
      dw=""; ow=""
      case "$row" in *"|choices="*) w="${row#*|choices=}"; w="${w%%|*}"; dw="${w%%/*}"; ow="${w#*/}" ;; esac
      case "$c" in
        default|recommended) : ;;
        *) if [ -n "$dw" ] && [ "$c" = "$dw" ]; then c=default
           elif [ -n "$ow" ] && [ "$c" = "$ow" ]; then c=other
           else
             all="${dw:+$dw or }${ow:+$ow, or }default or recommended"
             die "REFUSED — the reply's item \"$(clean "$it")\" names a choice decision $n does not offer: it offers $all; nothing is applied and the plan is unchanged."
             return 1
           fi ;;
      esac
      RP_PICKS="$RP_PICKS$n=$c "
    done
    [ -z "$RP_REST" ] || return 0
    for ((i = 1; i <= k; i++)); do case "$RP_PICKS" in *" $i="*) : ;; *) left="${left:+$left, }$i" ;; esac; done
    if [ -n "$left" ]; then
      die "REFUSED — the reply leaves decision(s) $left unanswered: name each, or end on rest default or rest recommended; nothing is applied and the plan is unchanged."
      return 1
    fi
    return 0
  }

  poker_verb_reply() {
    case "$RP_TEXT" in
      *$'\n'*|*$'\r'*) die "REFUSED — a reply is one line, and this one carries a line break; the plan is unchanged."; exit 1 ;;
    esac
    if ! declare -F user_said >/dev/null 2>&1 && [ -f "$BIONIC_LIB/said.sh" ]; then . "$BIONIC_LIB/said.sh"; fi
    if ! { declare -F proof_branch_head >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F user_said >/dev/null 2>&1; then
      die "REFUSED — the reply is read through lib/said.sh and lib/proof.sh, which cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    plan_verb_open reply
    RP_DIR="$(docs_root "$PV_REPO")/record/$(proof_plan_slug "$PV_PLAN")"
    # The newest page by its time of writing: a re-render at a head writes over that head's page, a later head's is newer.
    # shellcheck disable=SC2012  # page names are release-approval-<hex>[-<n>].md, or the old stem's, no blank or line break in any
    RP_CARD="$(ls -t "$RP_DIR"/release-approval-*.md "$RP_DIR/$RR_OLD_VERB"-*.md 2>/dev/null | head -1)"
    if [ -z "$RP_CARD" ] || [ ! -f "$RP_CARD" ] || [ -L "$RP_CARD" ]; then
      die "REFUSED — no release approval card is recorded for $PV_PLAN: render it with release-approval, show the page to the user, and replay their reply; the plan is unchanged."
      exit 1
    fi
    RP_HDR="$(/usr/bin/grep -m1 -E "^(release-approval|$RR_OLD_VERB)/v1\|plan=" "$RP_CARD" 2>/dev/null)"
    RP_RHEAD="${RP_HDR#*|head=}"; RP_RHEAD="${RP_RHEAD%%|*}"
    RP_HEAD="$(proof_branch_head "$PV_PLAN" "$PV_REPO")" || RP_HEAD=""
    if [ -z "$RP_HDR" ] || [ "$RP_RHEAD" != "$RP_HEAD" ]; then
      die "REFUSED — the release approval card $RP_CARD was rendered at $(printf '%.8s' "${RP_RHEAD:-(no head)}") and the working head is $(printf '%.8s' "${RP_HEAD:-(none)}") now: render it again with release-approval and show that page to the user; the plan is unchanged."
      exit 1
    fi
    if /usr/bin/grep -q '^replied: ' "$RP_CARD" 2>/dev/null; then
      die "REFUSED — the release approval card $RP_CARD is already answered ($(clean "$(/usr/bin/grep -m1 '^replied: ' "$RP_CARD")")); render it again for what is still open; the plan is unchanged."
      exit 1
    fi
    RP_NORM="$(printf '%s' "$RP_TEXT" | tr '[:upper:]' '[:lower:]' | sed -e 's/^[[:space:]"]*//' -e 's/[[:space:]".!]*$//' -e 's/[[:space:]][[:space:]]*/ /g')"
    RP_TABLE="$(/usr/bin/grep -E "^(release-approval|$RR_OLD_VERB)/v1\|dec=" "$RP_CARD" 2>/dev/null)"
    case "$RP_NORM" in
      'all default'|'all defaults') RP_HOW=all-default; RP_REST=default; RP_PICKS=" " ;;
      'all recommended') RP_HOW=all-recommended; RP_REST=recommended; RP_PICKS=" " ;;
      *) RP_HOW=by-number; rp_items "$RP_NORM" || exit 1 ;;
    esac
    user_said "$RP_TEXT" "$PV_PLAN"; RP_SAID=$?
    if [ "$RP_SAID" -ne 0 ]; then
      said_refuse "$RP_SAID" "$(said_fold "$RP_TEXT")" "a reply to the release approval card"
      exit 1
    fi
    RP_DONE=0; RP_HELD=0
    while IFS= read -r RP_L; do
      [ -n "$RP_L" ] || continue
      RP_KEY=""; RP_DO=""; RP_ELSE=""; RP_PICK=default; RP_WHY=""
      IFS='|' read -r -a RP_F <<< "$RP_L"
      for RP_X in "${RP_F[@]}"; do
        case "$RP_X" in
          key=*) RP_KEY="${RP_X#key=}" ;; default=*) RP_DO="${RP_X#default=}" ;; other=*) RP_ELSE="${RP_X#other=}" ;;
          pick=*) RP_PICK="${RP_X#pick=}" ;; why=*) RP_WHY="${RP_X#why=}" ;;
        esac
      done
      [ -n "$RP_KEY" ] || continue
      RP_N="${RP_L#*|dec=}"; RP_N="${RP_N%%|*}"
      case "$RP_PICKS" in *" $RP_N="*) RP_S="${RP_PICKS#* "$RP_N"=}"; RP_S="${RP_S%% *}" ;; *) RP_S="$RP_REST" ;; esac
      [ "$RP_S" != recommended ] || RP_S="$RP_PICK"
      # A DECISION ALREADY REPLAYED FROM THIS PAGE is skipped: a reply that stopped on a refusal is finished by the same reply.
      RP_KEY="$RP_KEY" awk 'index($0, "applied: " ENVIRON["RP_KEY"] " ") == 1 || $0 == "withheld: " ENVIRON["RP_KEY"] { f = 1 }
        END { exit !f }' "$RP_CARD" 2>/dev/null && continue
      if [ "$RP_S" = other ]; then RP_CMD="$RP_ELSE"; RP_SIDE=other; else RP_CMD="$RP_DO"; RP_SIDE=default; fi
      if [ "$RP_CMD" = - ]; then
        if [ "$RP_SIDE" = default ]; then RP_REC="applied: $RP_KEY carried"; RP_DONE=$((RP_DONE + 1))
        else RP_REC="withheld: $RP_KEY"; RP_HELD=$((RP_HELD + 1)); fi
        printf '%s\n' "$RP_REC" >> "$RP_CARD"; say "reply — $RP_REC"
        continue
      fi
      read -r -a RP_ARGV <<< "$RP_CMD"
      RP_ARGV+=("$RP_TEXT")
      [ "$RP_WHY" = - ] || RP_ARGV+=("$RP_WHY")
      RP_OUT="$( cd "$PV_REPO" && "${BASH:-bash}" "$HOOK_DIR/session-poker.sh" "${RP_ARGV[@]}" 2>&1 )"; RP_RC=$?
      [ -z "$RP_OUT" ] || printf '%s\n' "$RP_OUT"
      if [ "$RP_RC" -ne 0 ]; then
        die "reply — $(clean "$RP_KEY"): ${RP_ARGV[0]} refused (exit $RP_RC), and the reply stops there; $RP_DONE decision(s) applied before it are kept in $RP_CARD, and the same reply again replays the rest."
        exit "$RP_RC"
      fi
      printf 'applied: %s %s rc=0\n' "$RP_KEY" "${RP_ARGV[0]}" >> "$RP_CARD"
      RP_DONE=$((RP_DONE + 1))
    done <<RP_TABLE
$RP_TABLE
RP_TABLE
    printf 'replied: at=%s reply=%s words="%s"\n' "$(iso_now)" "$RP_HOW" "$(clean "$RP_TEXT")" >> "$RP_CARD"
    # THE REPLY IS THE RULING ON EVERY CARRY THE PAGE PUT: carried as shown, or moved by the decision the reply took (whose
    # finding-move closed it already), so the carry's ask on the run's register closes here.
    if declare -F owed_close >/dev/null 2>&1 && declare -F carry_owed_key >/dev/null 2>&1; then
      sed -n 's/^carried: //p' "$RP_CARD" 2>/dev/null | while IFS= read -r RP_X; do
        [ -z "$RP_X" ] || OWED_ROOT="$PV_REPO" OWED_PLAN="$PV_PLAN" owed_close "$(carry_owed_key "$RP_X")" "release approval reply" >/dev/null 2>&1
      done
    fi
    if [ "$RP_HELD" -gt 0 ]; then
      say "reply — \"$(clean "$RP_TEXT")\" replayed from $RP_CARD on the user's words: $RP_DONE decision(s) recorded, $RP_HELD held back; render the release approval card again once what is held is settled."
    else
      say "reply — \"$(clean "$RP_TEXT")\" replayed from $RP_CARD on the user's words: $RP_DONE decision(s) recorded; nothing on the page is left open."
    fi
    exit 0
  }

  # THE USER'S ORDER. `order '<words>'` records what the user said as an order every suite obeys;
  # `order lift` ends the open one. Each is one line with the time and the words:
  #
  #   order: given <ISO-UTC> "<words>"
  #   order: lifted <ISO-UTC> "<the words of the order it ends>"
  #
  # With a bound open run the line goes under the plan's `## SDLC State`, after its last order: line,
  # else after its last approved: or approved-by: line, else after current:, through the plan
  # transaction every row verb takes. With no run bound it is appended to record/orders.log under the
  # docs root, made when absent. tests/run.sh asks lib/gate.sh `gate_order`, the one reader of both,
  # and refuses every suite while an order is open. A newer order replaces the open one; the newest
  # line decides.
  #
  # REFUSED (1), nothing written: words that hold a line break, a lift with no open order, a plan
  # with no current: line under ## SDLC State, the log a link. (2): the order reader cannot be loaded,
  # or the log cannot be written.
  poker_verb_order() {
    local sid mode=log root log open line
    if ! declare -F gate_order_of >/dev/null 2>&1; then
      die "REFUSED — the order lookup (lib/gate.sh gate_order_of) cannot be loaded from $BIONIC_LIB; nothing was written."
      exit 2
    fi
    case "$OR_WORDS" in
      *$'\n'*|*$'\r'*)
        die "REFUSED — an order is one line, and the words carry a line break; nothing was written."
        exit 1 ;;
    esac
    sid="$(session_id 2>/dev/null)" || sid=""
    root="$(cd "$(project_root "$PWD")" 2>/dev/null && pwd -P)"
    if [ -z "$root" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    if [ -n "$sid" ] && engaged_session "$root" "$sid"; then
      case "$(session_run "$root" "$sid")" in 'bound-open '*) mode=plan ;; esac
    fi
    if [ "$mode" = plan ]; then
      plan_verb_open order
      open="$(gate_order_of "$PV_PLAN" plan)" || open=""
    else
      log="$(docs_root "$root")/record/orders.log"
      if [ -L "$log" ]; then
        die "REFUSED — $log is a link, and an order is not written through one; nothing was written."
        exit 1
      fi
      open="$(gate_order_of "$log")" || open=""
    fi
    if [ -n "$OR_LIFT" ]; then
      if [ -z "$open" ]; then
        die "REFUSED — no order is open$([ "$mode" = plan ] && printf ' in %s' "$PV_PLAN" || printf ' in %s' "$log"), so there is nothing to lift; nothing was written."
        exit 1
      fi
      OR_WORDS="${open#*\"}"; OR_WORDS="${OR_WORDS%\"}"
      line="order: lifted $(iso_now) \"$OR_WORDS\""
    else
      line="order: given $(iso_now) \"$OR_WORDS\""
    fi
    if [ "$mode" = log ]; then
      # A bionic folder made here gets its ignore file, as the handoff's does: the log is never tracked.
      [ -d "$root/.bionic" ] || { mkdir -p "$root/.bionic" 2>/dev/null && printf '*\n' > "$root/.bionic/.gitignore"; }
      if ! mkdir -p "${log%/*}" 2>/dev/null || ! printf '%s\n' "$line" >> "$log" 2>/dev/null; then
        die "REFUSED — $log cannot be written; nothing was written."
        exit 2
      fi
      say "order — $line, in $log (no run is bound)."
      exit 0
    fi
    # THE LINE GOES IN THROUGH THE ENVIRONMENT, not `-v`, which would read a backslash in the
    # user's words as an escape.
    if ! OR_LINE="$line" awk '
      { L[++n] = $0 }
      END {
        for (i = 1; i <= n; i++) {
          if (L[i] ~ /^[[:space:]]*```/) { fence = !fence; continue }
          if (fence) continue
          if (L[i] ~ /^##[[:space:]]/) { if (insdlc) break; insdlc = (L[i] ~ /^##[[:space:]]+SDLC State/); continue }
          if (!insdlc) continue
          if (L[i] ~ /^order:/) ord = i
          else if (L[i] ~ /^[[:space:]]*approved(-by)?[[:space:]]*:/) ap = i
          else if (!cur && L[i] ~ /^[[:space:]]*current[[:space:]]*:/) cur = i
        }
        at = ord ? ord : (ap ? ap : cur)
        if (!at) exit 1
        for (i = 1; i <= n; i++) { print L[i]; if (i == at) print ENVIRON["OR_LINE"] }
      }' "$PV_PLAN" > "$PV_NEW" 2>/dev/null; then
      die "REFUSED — $PV_PLAN carries no current: line under ## SDLC State to write the order beside; the plan is unchanged."
      exit 1
    fi
    plan_verb_swap order "the order" writer
    say "order — $line, under ## SDLC State of $PV_PLAN; dry-committed first."
    exit 0
  }

  # THE PROMOTION. One durable record, an adr, a design or a requirement, copied into the project's tracked
  # home under its kind with a stable name (lib/roots.sh `promote_target`, which owns the destination and every
  # refusal). It reads no plan and writes none: a promotion is a copy of a record the project keeps, so the
  # project root of the working directory is its only operand beside the two it is given. The source is an
  # absolute path, else project-root-relative, else docs-root-relative. A second promotion of the same record
  # lands at the same path and replaces it, so an amended record is promoted again by the same call.
  # REFUSED (1), nothing copied: no such file, or anything promote_target refuses. REFUSED (2): no project root.
  poker_verb_promote() {
    local root src to err
    root="$(cd "$(project_root "$PWD")" 2>/dev/null && pwd -P)"
    if [ -z "$root" ]; then
      die "REFUSED — cannot resolve the project root from the working directory. Nothing was copied."
      exit 2
    fi
    case "$PR_ARG" in
      /*) src="$PR_ARG" ;;
      *) if [ -f "$root/$PR_ARG" ]; then src="$root/$PR_ARG"; else src="$(docs_root "$root")/$PR_ARG"; fi ;;
    esac
    if [ ! -f "$src" ]; then
      die "REFUSED — no file $(clean "$PR_ARG") (read as $src). Nothing was copied."
      exit 1
    fi
    src="$(cd "${src%/*}" 2>/dev/null && pwd -P)/${src##*/}"
    err="$(mktemp "${TMPDIR:-/tmp}/bionic-promote.XXXXXX")" || err=/dev/null
    if ! to="$(promote_target "$root" "$PR_KIND" "$src" 2>"$err")"; then
      die "REFUSED — $(sed 's/^promote: //' "$err" 2>/dev/null). Nothing was copied."
      rm -f "$err"
      exit 1
    fi
    rm -f "$err"
    if [ -f "$to" ] && cmp -s "$src" "$to"; then
      say "promote — ${to#"$root"/} already holds ${src#"$root"/}; nothing changed."
      exit 0
    fi
    if ! { mkdir -p "${to%/*}" && cp "$src" "$to.promote.$$" && mv -f "$to.promote.$$" "$to"; }; then
      rm -f "$to.promote.$$"
      die "REFUSED — cannot write $to. Nothing was copied."
      exit 2
    fi
    say "promote — ${src#"$root"/} is promoted to ${to#"$root"/}."
    exit 0
  }
