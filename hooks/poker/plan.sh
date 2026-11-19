# shellcheck shell=bash
# hooks/poker/plan.sh — the plan verbs: the contract grammar and the rows of the plan
# (amend, task-add, brief, release-approval, reply).
#
# A part of hooks/session-poker.sh, which sets every global and loads this file before any verb runs. A part
# defines functions only, and is never run by itself.

# ---------------------------------------------------------------- the contract's reader
#
# `amend` widens a live contract and `task-add` judges a Files cell a brief is later rendered from; both
# read what they were given with payload/scripts/lib/brief.sh's `brief_contract`, the one reader of a
# brief's lines, so a value is recorded exactly as a dispatch carrying it would record it. Loaded on first
# use, never at the top: the tick runs every Patrol interval and needs none of it.
# poker_fold_ask <var> <verb and arguments to run again> <plan> <reader question's function> [args] -> <var> set to the
# question's answer over the run's facts (lib/proof.sh `_proof_ask`), its own no (exit 1) an answer. A fold that failed
# is the verb's refusal, exit 2 and nothing written: a page drawn or a file rendered over no facts reads as a run with none.
poker_fold_ask() {
  local _pfa_v="$1" _pfa_run="$2" _pfa_a _pfa_rc=0; shift 2
  _pfa_a="$(_proof_ask "$1" "$2" "$1" "${@:3}")" || _pfa_rc=$?
  [ "$_pfa_rc" -lt 2 ] || poker_fold_unread "$_pfa_run"
  printf -v "$_pfa_v" '%s' "$_pfa_a"
}
poker_fold_unread() {  # <verb and arguments to run again> -> the refusal, exit 2
  die "REFUSED — the run's facts could not be read, so nothing is written from them; run again: bash ${HOOK_DIR}/session-poker.sh $1"
  exit 2
}
poker_fold_all() { reader_facts "$1"; }  # <plan> -> every standing fact, a question for poker_fold_ask

poker_brief_load() {
  declare -F brief_contract >/dev/null 2>&1 && return 0
  [ -f "$BIONIC_LIB/brief.sh" ] || return 1
  # shellcheck source=/dev/null
  . "$BIONIC_LIB/brief.sh"
  declare -F brief_contract >/dev/null 2>&1
}

# poker_additions_judged <files lines> <suites lines> <runs lines> <root> <held suites> <files held> -> rc 0, or
# rc 1 with POKER_BRIEF_WORDS one line per addition no contract could carry: a Files value the reader reads no
# path from, a suite that is no `<name>.test.sh`, a suite no file under <root>/tests carries (unless the row
# holds it, or its Files name it), and a run the reader keeps nothing of. Each is named as it was typed.
# Set in hooks/session-poker.sh, before any part loads: POKER_BRIEF_WORDS.
poker_additions_judged() {
  local fl="$1" sl="$2" rl="$3" root="$4" held="$5" fh="$6" v t listed
  POKER_BRIEF_WORDS=""
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    [ -n "$(brief_field "$(brief_contract "Files: $v")" files)" ] \
      || POKER_BRIEF_WORDS="${POKER_BRIEF_WORDS}  Files: $(clean "$v") — not a path"$'\n'
  done <<< "$fl"
  listed="$(poker_suites_listed "$root" "$held")"
  for t in $(printf '%s' "$sl" | tr '\n,' '  '); do
    if [ -z "$(brief_field "$(brief_contract "Suites: $t")" suites)" ]; then
      POKER_BRIEF_WORDS="${POKER_BRIEF_WORDS}  Suites: $(clean "$t") — not a <name>.test.sh suite"$'\n'
    elif [ -n "$listed" ] && case " $listed " in *" ${t##*/} "*) false ;; *) true ;; esac \
         && case ",$fh," in *"/${t##*/},"*|*",${t##*/},"*) false ;; *) true ;; esac; then
      POKER_BRIEF_WORDS="${POKER_BRIEF_WORDS}  Suites: $(clean "$t") — no file in tests/ carries it"$'\n'
    fi
  done
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    [ -n "$(brief_field "$(brief_contract "Re-executes: \`$v\`")" re_executes)" ] \
      || POKER_BRIEF_WORDS="${POKER_BRIEF_WORDS}  Re-executes: $(clean "$v") — not a run"$'\n'
  done <<< "$rl"
  [ -z "$POKER_BRIEF_WORDS" ]
}

# born_floor_backing <plan> <repo> <suite> -> BFB_OF (`regression`, `standing@<12-hex>` or `run@<12-hex>`) and rc 0 when a
# red the machine recorded backs a floor-born marker for <suite>; rc 1 otherwise, BFB_OWED and BFB_BRANCH set for the
# refusal's words. THE THREE FACTS, asked in this order: (a) the plan's newest regression proof owes the suite (lib/proof.sh
# `_proof_last_read` regression owed, the reader `proof-add inherited` asks), (b) the run's landing record
# (`proof_debt_record`) holds an `ev=standing` event for the suite whose head is a commit on the working branch's ref
# (`proof_branch_head`), the newest such event first, or (c) it holds the `ev=verdict row=regression result=red` line a
# whole run left for the suite at such a commit, which `regression-run` writes before any proof-add: a run the machine
# recorded red backs the marker before its log is cited. A marker the judge holds every chain by is no declaration. No
# library gives these events a reader; `_bfb_newest` is the one awk, over the record and the run's log read as one
# (lib/line.sh `line_lines`), and it reads the fields as lib/line.sh's fold does (`fv`, a suite by its file name).
# Set in hooks/session-poker.sh, before any part loads: BFB_OF, BFB_OWED, BFB_BRANCH.
born_floor_backing() {
  local plan="$1" repo="$2" suite="$3" rec bh h
  BFB_OF=""; BFB_OWED="$(_proof_last_read "$plan" regression owed)"; BFB_BRANCH="$(plan_working_branch "$plan" 2>/dev/null)"
  case ",$BFB_OWED," in *",$suite,"*) BFB_OF=regression; return 0 ;; esac
  { [ -n "${_LINE_FIELDS_AWK:-}" ] || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; }
  rec="$(proof_debt_record "$plan" "$repo" 2>/dev/null)" && line_held "$rec" 2>/dev/null || return 1
  bh="$(proof_branch_head "$plan" "$repo")" || return 1
  h="$(_bfb_newest "$rec" "$repo" "$bh" "$suite" standing head)" && { BFB_OF="standing@${h:0:12}"; return 0; }
  h="$(_bfb_newest "$rec" "$repo" "$bh" "$suite" verdict commit)" && { BFB_OF="run@${h:0:12}"; return 0; }
  return 1
}

# _bfb_newest <record> <repo> <branch head> <suite> <ev> <field> -> the newest commit named by <field> of an <ev> line for
# <suite> that is an ancestor of the branch head, and rc 0; rc 1 and nothing when no line names one. A verdict counts only
# as the regression's own and red; the newest line is the last in the file.
_bfb_newest() {
  local rec="$1" repo="$2" bh="$3" suite="$4" ev="$5" field="$6" h
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    h="$(git -C "$repo" rev-parse --verify -q "${h}^{commit}" 2>/dev/null)" || continue
    git -C "$repo" merge-base --is-ancestor "$h" "$bh" 2>/dev/null || continue
    printf '%s' "$h"; return 0
  done <<BFB_EVENTS
$(line_lines "$rec" | awk -F'|' -v want="$suite" -v ev="$ev" -v fld="$field" "${_LINE_FIELDS_AWK:-}"'
    line_ev() == ev && (ev != "verdict" || (line_kv("row") == "regression" && line_kv("result") == "red")) {
      s = line_kv("suite"); sub(/.*\//, "", s); if (s == want && line_kv(fld) != "") h[++n] = line_kv(fld) }
    END { for (i = n; i >= 1; i--) print h[i] }' 2>/dev/null)
BFB_EVENTS
  return 1
}

# born_red_log <plan> <repo> -> BFB_LOG, the docs-root-relative path of the newest `regression-run-*.log` in the plan's
# record directory whose header reads a clean head (`dirty=0`) that is a commit on the working branch and whose last line
# is a non-zero `rc=`, the red a proof-add of it would record; rc 1 and BFB_LOG empty when none stands. The two ends of
# the log are `_proof_floor_ends`, the reader proof-add's own grammar uses.
born_red_log() {
  local plan="$1" repo="$2" rec dir bh f ends hdr last sha
  BFB_LOG=""
  rec="$(proof_debt_record "$plan" "$repo" 2>/dev/null)" || return 1
  dir="$(dirname "$rec")"; [ -d "$dir" ] || return 1
  bh="$(proof_branch_head "$plan" "$repo")" || return 1
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    ends="$(_proof_floor_ends "$f")"; hdr="${ends%%$'\n'*}"; last="${ends#*$'\n'}"
    case "$hdr" in *\ 0) ;; *) continue ;; esac
    case "$last" in rc=0|rc=) continue ;; rc=[0-9]*) ;; *) continue ;; esac
    sha="${hdr%% *}"
    git -C "$repo" merge-base --is-ancestor "$sha" "$bh" 2>/dev/null || continue
    BFB_LOG="record/$(basename "$dir")/${f##*/}"; return 0
  done <<BFB_LOGS
$(ls -t "$dir"/regression-run-*.log 2>/dev/null)
BFB_LOGS
  return 1
}

# poker_review_records <plan> <repo> [<questions>] -> the records a review row's Files name, comma-joined: one
# `<record dir>/critic-<q>.md` per question the row owes, in the dealing's order, a question dealt a piece and a whole
# read named once, since its reader writes one record for it. The questions a row owes are the ones it declares
# (<questions>, comma-joined, from the task cell's ` · questions:` tag) and, with none declared, the rigor's full deal (lib/proof.sh
# `facts_owed`). Nothing and rc 1 when the plan's rigor or scale deals no question and none is declared, and the
# caller keeps the one-record rule of a reader row.
poker_review_records() {
  local plan="$1" repo="$2" decl="${3:-}" qs dir q out=""
  if [ -n "$decl" ]; then
    qs="${decl//,/ }"
  else
    if ! declare -F facts_owed >/dev/null 2>&1; then
      [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh" >/dev/null 2>&1
    fi
    declare -F facts_owed >/dev/null 2>&1 || return 1
    qs="$(facts_owed "$(plan_frontmatter_get "$plan" rigor)" "$(plan_frontmatter_get "$plan" scale)" 2>/dev/null \
      | awk -F'\t' '$1 == "review" && !seen[$2]++ { print $2 }')"
  fi
  [ -n "$qs" ] || return 1
  dir="$(docs_root "$repo")/record/$(proof_plan_slug "$plan")"
  case "$dir" in "$repo"/*) dir="${dir#"$repo"/}" ;; esac
  for q in $qs; do out="${out:+$out, }$dir/critic-$q.md"; done
  printf '%s\n' "$out"
}

# poker_questions_dealt <plan> <questions> -> rc 0 when the declared questions (comma-joined) are one reader's at the
# plan's rigor and scale, else rc 1 with PQD_SAID the reason. A review row is one reader's: at double the auditor
# holds `evidence` and the critic the other two, so a declaration across them has no reader, and the reason names the
# deal. At single the critic holds all three, so any subset is one reader's. Set: PQD_SAID.
poker_questions_dealt() {
  local plan="$1" decl="$2" rigor scale lvl owed role q deal fix="" r qs first="" mixed=""
  PQD_SAID=""
  if ! declare -F facts_owed >/dev/null 2>&1; then
    [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh" >/dev/null 2>&1
  fi
  rigor="$(plan_frontmatter_get "$plan" rigor)"; scale="$(plan_frontmatter_get "$plan" scale)"
  lvl="$(rigor_level "$rigor" 2>/dev/null)" || lvl="${rigor:-none}"
  if ! declare -F facts_owed >/dev/null 2>&1 || ! owed="$(facts_owed "$rigor" "$scale" 2>/dev/null)" || [ -z "$owed" ]; then
    PQD_SAID="the plan's rigor (${rigor:-none}) and scale (${scale:-none}) deal no question, so there is none to declare"
    return 1
  fi
  # THE DEAL, one reader a line, `<role>:<its questions>` in the dealing's order; the piece read is the one that
  # writes the record.
  deal="$(printf '%s\n' "$owed" | awk -F'\t' '$1 == "review" && $4 == "piece" {
    r = $3; sub(/^bionic:/, "", r)
    if (!(r in a)) ord[++k] = r
    a[r] = a[r] (a[r] == "" ? "" : ",") $2 }
    END { for (i = 1; i <= k; i++) print ord[i] ":" a[ord[i]] }')"
  for q in ${decl//,/ }; do
    role="$(printf '%s\n' "$deal" | awk -F: -v q="$q" '{ n = split($2, w, ","); for (i = 1; i <= n; i++) if (w[i] == q) { print $1; exit } }')"
    if [ -z "$role" ]; then
      PQD_SAID="$q is dealt to no role at $lvl rigor, scale ${scale:-none}"
      return 1
    fi
    [ -n "$first" ] || first="$role"
    [ "$role" = "$first" ] || mixed=1
  done
  if [ -n "$mixed" ]; then
    while IFS=: read -r r qs; do
      [ -n "$r" ] || continue
      fix="${fix:+$fix, }${qs//,/ and } the $r's"
    done <<EOF
$deal
EOF
    PQD_SAID="${decl//,/ and } are dealt to different roles at $lvl rigor ($fix), and a review row is one role's"
    return 1
  fi
  return 0
}

# poker_files_cell <id> <kind> <agent> <Files cell> <repo> <plan> -> PFC_OUT (the cell to write) and PFC_ART (the
# record artifact a reader row gained, or empty); returns 0, or 1 / 2 with the refusal printed. THE ONE JUDGE OF A
# ROW'S FILES CELL: `task-add` reads a row's cell and judges it. A reader row (verify, test, review) whose cell names no record
# owes <record dir>/<id>.md, the artifact `brief` gives it; each entry of the cell is then read as the dispatch
# wall reads the brief's `Files:` line (`brief_contract`), and an entry it reads no path from is refused now, named.
# `—`, `-` and empty declare nothing to judge.
# Set in hooks/session-poker.sh, before any part loads: PFC_OUT, PFC_ART.
poker_files_cell() {
  local id="$1" kind="$2" files="$4" repo="$5" plan="$6"
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
    die "REFUSED — the brief library (lib/brief.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
    return 2
  fi
  if ! poker_additions_judged "$(printf '%s' "$PFC_OUT" | tr ',' '\n')" "" "" "$repo" "" ""; then
    die "REFUSED — a dispatch of $id with Files: $PFC_OUT would carry an entry that is no path; the plan is unchanged:"
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
# `### Scaffold` fence, never a second list: a label the verb fills from the row is written, every other label is named on the
# verb's own line as the orchestrator's. THE RULES, each the row's own cell or a function of it:
#   Expected duration   the row's size, in minutes
#   Expected artifact   the dispatch ledger's artifact cell for the row; else the first Files entry under record/
#                       that is neither a progress file nor assumptions.md; else the first record path the
#                       row's task names; else, for a reader row (verify, test, review), <record dir>/<row>.md,
#                       which its Files line then carries (wave-35 T8; AC-6.1); else the slot, marked
#   Progress artifact   the Files entry that ends .progress.md, else <record dir>/<row>.progress.md; Cadence is
#                       the 15-minute rule's own number. Both only for a size of 15 or more
#   Files               the row's Files cell, verbatim, then each path the row's Suites declare they pin (their
#                       `# pins:` header line), one to a line and marked `(pinned by <suite>)`; no line for a row
#                       whose cell is empty or a dash and whose suites pin nothing
#   Suites, Lands-on    the row's `suites` / `lands-on` cells when the table has them and the row fills them;
#                       else the *.test.sh entries of Files by file name; else, for a row whose Files write
#                       code, the slot marked for the orchestrator, never none; `Suites: none` and
#                       `Lands-on: none <reason>` only for a row that writes no code
#   Row                 the row's id
# The file starts with the scaffold lines, so no prose after them is a label's first hit (lib/brief.sh
# `brief_contract` reads a label's first line). A re-render keeps everything from `## Judgment` on: that section is the
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

# poker_verbs_listed -> the verbs this script's usage lists, one per line: the listing every verb a rendered brief
# names is held to, read from the usage itself so a verb added or retired moves both at once.
poker_verbs_listed() {
  ( usage ) 2>&1 | sed -n 's/.*session-poker\.sh \([a-z][a-z0-9-]*\).*/\1/p'
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
# when none. THE ONE RULE FOR A ROW'S RECORD, read by `brief`: `named` is the entry whose basename is <row>.md or starts <row>- (never a progress file);
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

# poker_brief_pins <root> <at> <suite> -> the paths the suite's header declares it pins, one per line: every
# `# pins: <path> [<path>…]` line of the comment block that opens the file, paths from the repository root. The suite
# is read at <at> (a commit) when one is given, else under <root>; a suite that cannot be read, or declares none,
# yields nothing. Declared, never inferred: the header is the only place it looks, so a line of the suite's body that
# quotes the shape is not a declaration.
poker_brief_pins() {
  { if [ -n "$2" ]; then git -C "$1" show "$2:tests/${3##*/}" 2>/dev/null
    else cat "$1/tests/${3##*/}" 2>/dev/null; fi; } | awk '
    /^[ \t]*$/ { next }
    /^#/ { if ($0 ~ /^# pins:[ \t]/) { sub(/^# pins:[ \t]+/, ""); for (i = 1; i <= NF; i++) print $i } next }
    { exit }'
}

# poker_brief_pinned <root> <at> <Files cell> <suites, comma-joined> -> one line per path the suites pin that the Files
# cell does not already name: `<path>  # (pinned by <suite>[, <suite>])`, first-seen order, a path two suites pin once.
# The mark is a trailing comment, which the Files reader strips, so the path is the entry and the mark never is.
poker_brief_pinned() {
  local s
  printf '%s\n' "$4" | tr ',' '\n' | sed 's/^[ \t]*//; s/[ \t]*$//' | while IFS= read -r s; do
    case "$s" in ''|*[[:space:]]*|*'<'*) continue ;; esac
    poker_brief_pins "$1" "$2" "$s" | awk -v s="${s##*/}" '{ print $0 "\t" s }'
  done | awk -F'\t' -v files="$3" '
    BEGIN {
      n = split(files, f, ",")
      for (i = 1; i <= n; i++) { e = f[i]; gsub(/`/, "", e); gsub(/^[ \t]+|[ \t]+$/, "", e); if (e != "") held[e] = 1 }
    }
    ($1 in held) { next }
    { if (!($1 in by)) order[++m] = $1
      if (index(", " by[$1] ",", ", " $2 ",") == 0) by[$1] = by[$1] (by[$1] == "" ? "" : ", ") $2 }
    END { for (i = 1; i <= m; i++) print order[i] "  # (pinned by " by[order[i]] ")" }'
}

# poker_reader_kind <kind> -> 0 for a reader row's kind (verify, test, review): its artifact is a record it writes.
poker_reader_kind() { case "$1" in verify|test|review) return 0 ;; esac; return 1; }
# ---- END the brief rendered from its row ----

# ---- BEGIN the set of an agent its start did not place (wave-27 T38; review pass 8 F3) ----
# `amend <agent id>` for an id no named row carries: see the verb. The row is the budget wall's
# alone. Its name is the id, so it shadows no other name's latest row; `status=unplaced` is no
# status a reader of live rows counts; the waiver keeps the verdict from judging a deliverable
# nobody owes. The additions are judged as every amend's are (`poker_additions_judged`). The set is
# the union of the id's current one and the additions.
# THE SUITES THAT EXIST, LISTED ONCE PER CALL: the `*.test.sh` basenames under <root>/tests, space-separated, an added
# suite's name is held to. This listing is the one the plan verbs make; a root with no suite lists nothing, and then
# no membership is judged.
# THE ROW'S OWN OLD MEMBERS COUNT AS EXISTING (<held>, when the listing found any suite): they were admitted at its
# dispatch, and a suite since renamed or deleted must not block an amend that adds a file or a run.
poker_suites_listed() {  # <root> [<held suites>] -> the names on stdout
  local f out=""
  for f in "$1"/tests/*.test.sh; do
    [ -f "$f" ] && out="${out:+$out }${f##*/}"
  done
  [ -z "$out" ] || out="$out ${2:-}"
  printf '%s' "$out"
}

amend_unplaced() {  # <agent id> <the last row carrying it, or empty> -> the verb's exit status
  local aid="$1" prior="$2" tr sub old_sa="" old_runs="" decl add sa new_runs r row pick
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
  if [ -n "${AMEND_NARROW:-}" ]; then
    die "REFUSED — $aid is an agent its start did not place, and it holds no suite set to narrow; add suites with --suites+ here, or amend its dispatched row by name. Nothing was written."
    return 1
  fi
  if [ -n "$AMEND_FILES" ]; then
    die "REFUSED — $aid is an agent its start did not place, and a Files: contract belongs to its dispatched row; add suites or runs here, or amend that row by name. Nothing was written."
    return 1
  fi
  if ! poker_brief_load; then
    die "REFUSED — the brief library (lib/brief.sh) cannot be loaded from $BIONIC_LIB; nothing was written."
    return 2
  fi
  if [ -n "$prior" ]; then
    old_sa="$(line_field "$prior" suites_allowed)"
    row_has_key "$prior" re_executes && old_runs="$(clean "$(line_field "$prior" re_executes)" re_executes)"
  fi
  [ "$old_sa" = none ] && old_sa=""
  decl="$(poker_union ' ' "$old_sa" "$(printf '%s' "$AMEND_SUITES" | tr '\n,' '  ')")"
  if ! poker_additions_judged "" "$AMEND_SUITES" "$AMEND_RUNS" "$REPO_REAL" "$old_sa" ""; then
    die "REFUSED — no contract could carry these additions for $aid; nothing was written:"
    printf '%s' "$POKER_BRIEF_WORDS" >&2
    return 1
  fi
  add="$(brief_contract "$(poker_brief_span "" "$decl" "" "$AMEND_RUNS")")"
  sa="$(brief_field "$add" suites)"; [ -n "$sa" ] || sa="$old_sa"
  new_runs="$old_runs"
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    grep -qxF -- "$r" <<< "$(poker_marked_runs "$old_runs")" && continue
    new_runs="${new_runs:+$new_runs }\`${r}\`"
  done <<EOF
$(poker_marked_runs "$(brief_field "$add" re_executes)")
EOF
  if [ "$sa" = "$old_sa" ] && [ "$new_runs" = "$old_runs" ]; then
    die "REFUSED — this amend changes nothing: every addition is already on the set recorded for $aid, or is not a suite or run a brief's contract records. Nothing was written."
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
  poker_hand amend "$AMEND_REASON" "name=$aid" 2>/dev/null || :
  pick="$(roster_row_for_id "$ROSTER_FILE" "$aid")" || pick=""
  if [ "$pick" != "$row" ]; then
    die "amend written, but the budget wall reads another row for $aid — a later row carrying that id was written after it"
    return 1
  fi
  say "amended — $aid, an agent its start did not place: suites=${sa:-(none)}${new_runs:+ runs=$new_runs}; the budget wall reads this row from now on."
  return 0
}
# ---- END the set of an agent its start did not place ----

# ---------------------------------------------------------------- a table's header cells

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
  # THE ADDITIONS ARE READ AS A BRIEF'S LINES ARE. Each is judged by `poker_additions_judged`, and the
  # merged set is read back through `brief_contract`, the one reader of a brief's `Files:`, `Suites:` and
  # `Re-executes:` lines, so the row records what a dispatch carrying the merged contract would. The old
  # set plus the added suites is the budget. A row whose set an older release derived keeps its
  # `suites_source=` label: nothing re-derives it.
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
    # A CLOSED CONTRACT HOLDS NO CELL: once acked, the row's Files are the plan's again, so the refusal names the
    # edit of the plan that writes them, on the row the contract held.
    if ! grep -qxF -- "$AMEND_NAME" <<< "$AM_OPEN"; then
      AM_CROW="$(line_field "$AM_ROW" row)"
      plan_verb_id_ok "$AM_CROW" || AM_CROW="<row>"
      die "REFUSED — $AMEND_NAME is closed: it was acked after its latest launch, or holds no live row. A closed contract is not amended; its row's Files are the plan's cell: edit the Files cell of $AM_CROW in the plan. Nothing was written."
      exit 1
    fi
    if ! poker_brief_load; then
      die "REFUSED — the brief library (lib/brief.sh) cannot be loaded from $BIONIC_LIB; nothing was written."
      exit 2
    fi

    AM_ROLE="$(line_field "$AM_ROW" subagent_type)"
    AM_OLD_FILES="$(line_field "$AM_ROW" files)"
    AM_OLD_SA="$(line_field "$AM_ROW" suites_allowed)"
    AM_OLD_SRC="$(line_field "$AM_ROW" suites_source)"
    AM_OLD_RUNS=""
    row_has_key "$AM_ROW" re_executes && AM_OLD_RUNS="$(clean "$(line_field "$AM_ROW" re_executes)" re_executes)"

    # THE ADDITIONS, EACH JUDGED ALONE, then read as a brief's lines: each `--files+` value on its own, as the
    # wall reads one line, so a ` #` note in one value hides no later one.
    if ! poker_additions_judged "$AMEND_FILES" "$AMEND_SUITES" "$AMEND_RUNS" "$REPO_REAL" "$AM_OLD_SA" \
         "$(poker_union , "$AM_OLD_FILES" "$(printf '%s' "$AMEND_FILES" | tr '\n' ',')")"; then
      die "REFUSED — no contract could carry $AMEND_NAME's additions; nothing was written:"
      printf '%s' "$POKER_BRIEF_WORDS" >&2
      exit 1
    fi
    AM_ADD="$(brief_contract "$(poker_brief_span "" "" "" "$AMEND_RUNS")")"
    AM_ADD_FILES=""
    while IFS= read -r AM_F; do
      [ -n "$AM_F" ] || continue
      AM_ADD_FILES="$(poker_union , "$AM_ADD_FILES" "$(brief_field "$(brief_contract "Files: $AM_F")" files)")"
    done <<< "$AMEND_FILES"
    AM_NEW_FILES="$(poker_union , "$AM_OLD_FILES" "$AM_ADD_FILES")"

    # THE BUDGET IS THE OLD SET PLUS THE ADDED SUITES, carried into the span as declared, whatever
    # the row's label. `none` is a waiver, and it yields to the first suite actually added.
    AM_DECL="$(poker_union ' ' "$AM_OLD_SA" "$(printf '%s' "$AMEND_SUITES" | tr '\n,' '  ')")"
    # A NARROWING (`--suites=<a,b>`) SETS THE BUDGET TO EXACTLY THOSE, and only members the row holds: a name it does
    # not hold is a widening, which `--suites+` does. The row's `lands_on=` follows, because a row may land only on
    # suites it may run (the dispatch wall's own rule), and a narrowing that leaves it landing on none of them is
    # refused, so a contract is never narrowed into one the wall would have refused at dispatch.
    AM_NEW_LO=""; AM_OLD_LO=""
    row_has_key "$AM_ROW" lands_on && AM_OLD_LO="$(line_field "$AM_ROW" lands_on)"
    if [ -n "${AMEND_NARROW:-}" ]; then
      AM_NARROW="$(printf '%s' "${AMEND_NARROW:-}" | tr '\n,' '  ')"
      for AM_N in $AM_NARROW; do
        case " $AM_OLD_SA " in
          *" $AM_N "*|*" ${AM_N##*/} "*) : ;;
          *) die "REFUSED — $AMEND_NAME's row does not hold the suite $(clean "$AM_N"), so naming it would widen the set, and --suites= only narrows; add it with --suites+ $(clean "$AM_N"). Nothing was written."
             exit 1 ;;
        esac
      done
      AM_DECL="$(poker_union ' ' "$(printf '%s' "$AM_NARROW" | tr ' ' '\n' | sed 's#.*/##' | tr '\n' ' ')")"
      AM_NEW_LO=""
      for AM_E in $(printf '%s' "$AM_OLD_LO" | tr ',' ' '); do
        if bionic_lands_cmd "$AM_E" >/dev/null 2>&1 || [ "$AM_E" = none ]; then
          AM_NEW_LO="${AM_NEW_LO:+$AM_NEW_LO,}$AM_E"; continue
        fi
        case " $AM_DECL " in *" ${AM_E##*/} "*) AM_NEW_LO="${AM_NEW_LO:+$AM_NEW_LO,}$AM_E" ;; esac
      done
      if [ -n "$AM_OLD_LO" ] && [ -z "$AM_NEW_LO" ]; then
        die "REFUSED — this narrowing would leave $AMEND_NAME landing on none of its suites (lands_on=$AM_OLD_LO is outside $AM_DECL); keep one of them in --suites=. Nothing was written."
        exit 1
      fi
    fi
    case " $AM_DECL " in
      *" none "*) [ "$AM_DECL" = none ] \
                    || AM_DECL="$(printf '%s' "$AM_DECL" | tr ' ' '\n' | awk '$0 != "none" && $0 != ""' | tr '\n' ' ')"
                  AM_DECL="${AM_DECL% }" ;;
    esac

    AM_SA=""; AM_SRC=""
    if [ -n "$AM_DECL" ]; then
      AM_SA="$(brief_field "$(brief_contract "Suites: $AM_DECL")" suites)"
      [ -z "$AM_SA" ] || AM_SRC=declared
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
      die "REFUSED — this amend changes nothing: every addition is already on $AMEND_NAME's row, or is not a path, suite or run a brief's contract records. Nothing was written."
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
    [ -n "${AMEND_NARROW:-}" ] && row_has_key "$AM_ROW" lands_on && AM_ARGS+=("lands_on=$AM_NEW_LO")
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
    # The roster row is the walls' contract; the hand event is the act, in the run's log.
    poker_hand amend "$AMEND_REASON" "name=$AMEND_NAME" 2>/dev/null || :
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
    # (`_sg_roster_walk`, payload/scripts/lib/stop.sh), so a successor that copied a `duplicate-start` row is read by the budget
    # wall alone — the line names only the walls that read it (wave-22 T10; review 4).
    case "$(line_field "$AM_NEW_ROW" status)" in
      confirmed|identified) AM_WALLS="the stop and budget walls read" ;;
      *)                    AM_WALLS="the budget wall reads" ;;
    esac
    say "amended — $AMEND_NAME: files=${AM_NEW_FILES:-(none)} suites=${AM_SA:-(none)}${AM_NEW_RUNS:+ runs=$AM_NEW_RUNS}; $AM_WALLS this row from now on."
    exit 0
  }

  # A TASKS CELL IS HELD TO THE STEP-3 CARD'S TITLE CAP AND SENTENCE RULE WHERE IT IS TYPED: a cell the card would refuse is
  # refused here, before anything is written, by the card's own check (`card.sh task-cell`), so the words are the
  # card's and there is one rule. Every refused cell of the call is named in the one refusal.
  pv_task_cells_or_refuse() {  # <id> <cell> [<id> <cell>]... -> returns when the card would draw every cell, else exits 1
    local card out
    card="$(cd "$BIONIC_LIB/.." 2>/dev/null && pwd -P)/card.sh"
    if [ ! -f "$card" ]; then
      die "REFUSED — the Step-3 card's check ($card) cannot be found to judge the Tasks cell; the plan is unchanged."
      exit 1
    fi
    out="$("${BASH:-bash}" "$card" task-cell "$@" 2>&1 >/dev/null)" && return 0
    while IFS= read -r PV_TC_LINE; do
      [ -n "$PV_TC_LINE" ] && die "$PV_TC_LINE"
    done <<EOF
$out
EOF
    die "The Tasks cell opens on its title, then one plain sentence saying what the row makes true; the plan is unchanged."
    exit 1
  }

  # ta_line <id> [<column>=<value>]... -> the ## Tasks line of row <id> as the plan holds it, each named cell replaced
  # and a bar in a cell escaped as the table writes it, so the line pastes over the row it names.
  ta_line() {
    local id="$1" kv k v o out="|"; shift
    while IFS= read -r kv; do
      [ -n "$kv" ] || continue
      k="${kv%%=*}"; v="${kv#*=}"
      for o in "$@"; do [ "${o%%=*}" != "$k" ] || v="${o#*=}"; done
      out="$out ${v//|/\\|} |"
    done <<EOF
$(plan_read_row "$TA_PLAN" Tasks id "$id")
EOF
    printf '%s\n' "$out"
  }

  # A ROW'S WORK NO LONGER OWED IS SAID BY THE BIRTH DOOR'S DROP FORM, task-add <id> --drop '<the person's words>': one
  # drop event through its one writer (lib/units.sh `units_drop_event`), the plan unwritten, so the row stays as the person
  # wrote it and the reader and the fill read it dropped. Only a pending row is dropped, past Step-3 approval: a landed
  # row's work is done, a row in flight has a writer to stand down first (its dispatch's cancel returns it to pending),
  # and before the approval a row is taken out by an edit. A row dropped already takes the new words.
  poker_verb_task_drop() {
    local st
    [ -z "$TA_BORN$TA_BORN_IDS$TA_BORN_SUITE" ] || { die "task-add: --drop and --born are two acts; name one."; exit 2; }
    plan_verb_open task-add
    TA_PLAN="$PV_PLAN"; TA_CUR="${PV_CUR%[ab]}"
    case "$TA_CUR" in ''|*[!0-9]*) TA_CUR=0 ;; esac
    if [ "$TA_CUR" -lt 4 ]; then
      die "REFUSED — $TA_PLAN is at current: ${PV_CUR:-(none)}; before Step-3 approval a row is taken out by an edit of the plan. Nothing is dropped; needs: the person — that edit."; exit 1
    fi
    plan_read_row "$TA_PLAN" Tasks id "$TA_ID" >/dev/null 2>&1 \
      || { die "REFUSED — $TA_PLAN holds no row $TA_ID in its ## Tasks table. Nothing is dropped; name a row it holds: task-add <id> --drop '<words>'."; exit 1; }
    # Its state is the fill's, the run's log over the cells (`units_rows`), so in flight is what holds a slot: an older
    # table's agent cell names who would write the row, not that anyone does.
    st="$(units_rows "$TA_PLAN" 2>/dev/null)" || poker_fold_unread "task-add $TA_ID --drop '<words>'"
    st="$(printf '%s\n' "$st" | awk -F'\t' -v r="$TA_ID" '$1 == r { print $10; exit }')"
    case "$st" in
      pending|dropped) ;;
      landed) die "REFUSED — $TA_ID has landed: its work is done, not dropped. Nothing is dropped; work owed again is a new row, written by an edit and born by task-add <id>."; exit 1 ;;
      *) die "REFUSED — $TA_ID is ${st:-unread}: a writer holds it. Stand it down first (its dispatch's cancel returns it to pending), then task-add $TA_ID --drop again. Nothing is dropped."; exit 1 ;;
    esac
    units_drop_event "$TA_PLAN" "$TA_ID" "$TA_DROP" \
      || { die "task-add — the drop of $TA_ID could not be appended to the run's log; it reads $st until it is. Run task-add $TA_ID --drop again."; exit 1; }
    say "task-add — $TA_ID is dropped: its drop is in the run's log with the words given, and $TA_PLAN is unchanged."
    say "task-add — owed: mark the task-list entry of $TA_ID deleted."
    exit 0
  }

  # A ROW IS ADDED BY AN EDIT OF THE PLAN, AND THIS VERB RECORDS ITS BIRTH. Only a person, or the orchestrator as their
  # hand through an edit, changes a plan file, so the verb writes none: it reads the row back from the plan, judges it as
  # a row born mid-run is judged, appends its one born event and closes the asks its findings held. Its order is fixed: a
  # row the plan does not hold is refused, so no birth stands for a row never written; a row short of a cell the verb
  # would have written (a reader row's record, a review row's records and artifact, the task cell's born and questions
  # tags, another row's deps in a table with no reads column) is refused with the lines it would accept, ready to paste,
  # and nothing is born; a row refused for its birth stands in the plan unborn, the person's to remove.
  poker_verb_task_add() {
    [ -z "${TA_DROP:-}" ] || poker_verb_task_drop
    plan_verb_open task-add
    TA_PLAN="$PV_PLAN"; REPO_REAL="$PV_REPO"
    TA_CUR="${PV_CUR%[ab]}"
    case "$TA_CUR" in
      ''|*[!0-9]*)
        die "REFUSED — $TA_PLAN has current: ${TA_CUR:-(none)}; task-add records a row born past Step-3 approval, whose current: is a step number."
        exit 1 ;;
    esac
    if [ "$TA_CUR" -lt 4 ]; then
      die "REFUSED — $TA_PLAN is at current: $TA_CUR; before Step-3 approval the plan is written by hand and reviewed, and no row is born."
      exit 1
    fi
    if ! TA_ROW="$(plan_read_row "$TA_PLAN" Tasks id "$TA_ID" 2>/dev/null)"; then
      die "REFUSED — $TA_PLAN holds no row $TA_ID in its ## Tasks table. A row is added by an edit of the plan, then task-add $TA_ID records its birth: write the row first. Nothing is born."
      exit 1
    fi
    ta_cell() { printf '%s\n' "$TA_ROW" | sed -n "s/^$1=//p" | head -1; }
    TA_STEP="$(ta_cell step)"; TA_KIND="$(ta_cell kind)"; TA_CELL="$(ta_cell task)"; TA_AGENT="$(ta_cell agent)"
    TA_FILES="$(ta_cell files)"; TA_READ_FILES="$TA_FILES"
    # THE TASK CELL CARRIES TWO TAGS THE VERB WROTE AND AN EDIT NOW WRITES: ` · born: review|regression` and
    # ` · questions: <q>[,<q>]`. Each is lifted off wherever it stands; the cell the verb accepts ends on them in that order.
    TA_TASK="$TA_CELL"; TA_QUESTIONS=""; TA_TAG=""
    for TA_T in " · born: review" " · born: regression"; do
      case "$TA_TASK" in *"$TA_T"|*"$TA_T · "*) TA_TAG="${TA_T# · }"; TA_TASK="${TA_TASK/"$TA_T"/}" ;; esac
    done
    case "$TA_TASK" in
      *" · questions: "*)
        TA_QUESTIONS="${TA_TASK#*" · questions: "}"; TA_QUESTIONS="${TA_QUESTIONS%%" · "*}"
        TA_TASK="${TA_TASK/" · questions: $TA_QUESTIONS"/}" ;;
    esac
    case "$TA_TAG:${TA_BORN}${TA_BORN_IDS}:$TA_BORN_SUITE" in
      'born: '*'::')
        die "REFUSED — the task cell of $TA_ID says $TA_TAG, and task-add names no --born: name what it was born of (--born <record>#<n>, 'review S<n> <on|off>' or regression:<suite>), or take the tag out of the cell. Nothing is born."
        exit 1 ;;
    esac
    if [ -n "$TA_QUESTIONS" ]; then
      [ "$TA_KIND" = review ] || { die "REFUSED — the task cell of $TA_ID declares questions: $TA_QUESTIONS, and only a review row is dealt questions; $TA_ID is a $TA_KIND row. Nothing is born."; exit 1; }
      TA_QSEEN=""
      for TA_QW in $(printf '%s' "$TA_QUESTIONS" | tr ',' ' '); do
        case " evidence adversarial structure " in *" $TA_QW "*) : ;; *) TA_QSEEN=bad; break ;; esac
        case " $TA_QSEEN " in *" $TA_QW "*) TA_QSEEN=bad; break ;; esac
        TA_QSEEN="$TA_QSEEN $TA_QW"
      done
      case "$TA_QUESTIONS" in *[!a-z,]*|,*|*,|*,,*) TA_QSEEN=bad ;; esac
      if [ "$TA_QSEEN" = bad ]; then
        die "REFUSED — the task cell of $TA_ID declares questions: $TA_QUESTIONS, which is no list of questions: write evidence, adversarial or structure, each once, comma-separated with no space. Nothing is born."
        exit 1
      fi
      TA_QUESTIONS=""
      for TA_QW in evidence adversarial structure; do
        case " $TA_QSEEN " in *" $TA_QW "*) TA_QUESTIONS="${TA_QUESTIONS:+$TA_QUESTIONS,}$TA_QW" ;; esac
      done
    fi

    # A READER ROW WRITES ITS RECORD. A verify, test or review row whose Files
    # name no record artifact owes <record dir>/<id>.md in its cell, the artifact `brief` gives it, so a row that
    # reads that record waits on this one (the validator refuses a record read no row's Files cover).
    # THE FILES CELL IS JUDGED BY THE DISPATCH GRAMMAR.
    # The cell becomes a brief's `Files:` line at dispatch, so it is read here exactly as the
    # dispatch wall will read it: a cell the lift reads as no path — a template slot, a bare
    # word — is refused now, in the grammar's words, rather than forty minutes later at the
    # dispatch of a row nobody can fix from the table. `—` is the table's "none" and declares
    # nothing to judge.
    # A REVIEW ROW'S FILES ARE ITS QUESTIONS' RECORDS. Its reader writes one record per question the rigor deals and
    # registers each, so a cell naming fewer leaves deliver a record no proof names, or several and no way to choose.
    # A cell naming no record owes the rendered list (`poker_review_records`). A cell that already names a record
    # for every question keeps the names it wrote. A cell naming some records but fewer than the questions is refused
    # with the rendered list. The first record the cell names is the one deliver takes, the row's artifact cell when
    # the table has one.
    TA_REV_ART=""
    # A DECLARED QUESTION IS ONE A READER IS DEALT (`--questions`): judged before the records are rendered, so a row no
    # single reader could answer is refused in the deal's words with the plan unchanged.
    if [ -n "$TA_QUESTIONS" ] && ! poker_questions_dealt "$TA_PLAN" "$TA_QUESTIONS"; then
      die "REFUSED — $TA_ID declares questions: $TA_QUESTIONS, which is not dealt: $PQD_SAID. Edit its task cell to the questions one role holds, then task-add $TA_ID again. Nothing is born."
      exit 1
    fi
    if [ "$TA_KIND" = review ] && TA_REVIEW="$(poker_review_records "$TA_PLAN" "$REPO_REAL" "$TA_QUESTIONS")"; then
      TA_HAVE="$(printf '%s\n' "$TA_FILES" | tr ',' '\n' | awk '
        { gsub(/`/, ""); sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }
        index($0, "record/") && /\.md$/ { n = split($0, p, "/"); b = p[n]; if (b !~ /\.progress\.md$/ && b != "assumptions.md" && !seen[$0]++) print $0 }')"
      if [ -z "$TA_HAVE" ]; then
        case "$TA_FILES" in ''|'—'|'-') TA_FILES="$TA_REVIEW" ;; *) TA_FILES="$TA_FILES, $TA_REVIEW" ;; esac
        TA_REV_ART="${TA_REVIEW%%,*}"
      else
        TA_QOWES="the plan's rigor deals"
        [ -z "$TA_QUESTIONS" ] || TA_QOWES="it declares (${TA_QUESTIONS//,/, })"
        TA_NHAVE="$(printf '%s\n' "$TA_HAVE" | awk 'NF' | wc -l | tr -d ' ')"
        TA_NWANT="$(printf '%s' "$TA_REVIEW" | tr ',' '\n' | awk 'NF' | wc -l | tr -d ' ')"
        if [ "$TA_NHAVE" -lt "$TA_NWANT" ]; then
          die "REFUSED — $TA_ID is a review row, whose Files name one record per question $TA_QOWES:$TA_NWANT, and its Files name $TA_NHAVE; its Files are: $TA_REVIEW (write that list in its Files cell, or name a record of your own for each question). Nothing is born."
          exit 1
        fi
        TA_REV_ART="$(printf '%s\n' "$TA_HAVE" | sed -n 1p)"
      fi
    fi
    poker_files_cell "$TA_ID" "$TA_KIND" "$TA_AGENT" "$TA_FILES" "$REPO_REAL" "$TA_PLAN" || exit $?
    TA_FILES="$PFC_OUT"; TA_ART="$PFC_ART"

    # A ROW REVIEW MADE UNASKED (wave-30 T21; REQ-10 AC-10.1, AC-10.2; D4, Δ3). Three guards, whatever the
    # policy says, each a refusal with the plan byte-identical: (1) the rating is inside the plan's
    # fix-policy:, read verbatim (lib/run.sh `fix_policy_covers`; S1,S2-on when absent); (2) a counted row is
    # under fix-cap: (lib/units.sh `units_fix_cap`, the level's default when absent), counted off the
    # ledger lines' born: markers (`units_born_counted`, the one place the count reads): a row inside the
    # policy whose findings are this plan's own is the review's own defect and exempt, while a promoted or a
    # carried one counts, so the cap bounds only the scope a review adds; (3) no Files path outside
    # the record or the registry files (lib/units.sh REGISTRY_FILES) already carries three review-born rows: the
    # fourth fix on one component stops the run.
    # In-diff is the orchestrator's judgment and "never re-read" the proof's; neither is this verb's.
    # THE FINDINGS A ROW ANSWERS (wave-33 T13; REQ-5, D6): each is a finding of a reading the plan registered,
    # read from its record (`finding_read`); the row's rating is the gravest of them, the lowest S and then on
    # before off, and the guards below hold it as they hold a typed rating.
    # A FINDING THE PERSON MOVED TO FIX IS ASKED, NOT UNASKED (wave-35 T34; A-orch-48): its effective priority
    # (`finding_read`'s FR_P, a `moved:` line) is fix, and a fix is answered by a row born of
    # it, so the policy guard holds each finding to the policy OR to the person's move, the first that is
    # neither refused with the remedy. The marker keeps the reader's rating, never re-rated.
    TA_BORN_MARK=""; TA_OFF=""; TA_OFF_RATING=""; TA_CLASS=""; TA_COUNT_SAID=""
    TA_POL="$(units_fix_policy "$TA_PLAN")" || TA_POL=""
    # A FINDING THE PERSON MOVED TO DEFER IS BORN NO ROW (wave-36 T8; REQ-4 AC-4.5, D10): its newest move
    # (lib/proof.sh `proof_move_line`) is the person's last word, whatever its reader's rating, so an S2 on the
    # fix-policy admits is refused as an S3 off is, naming the move, before the policy is asked.
    if [ -n "$TA_BORN_IDS" ]; then
      TA_BEST=""
      for TA_BID in $(printf '%s' "$TA_BORN_IDS" | tr ',' ' '); do
        if ! finding_read "$TA_PLAN" "$REPO_REAL" "$TA_BID"; then
          die "task-add refused — $FR_WHY; nothing is born."
          exit 1
        fi
        TA_MV="$(_proof_moved_to "$TA_PLAN" "$TA_BID")" \
          || { die "task-add refused — the run's facts could not be read, so the moves of $(clean "$TA_BID") are not known; nothing is born. Run again: bash ${HOOK_DIR}/session-poker.sh task-add $TA_ID with the same operands"; exit 2; }
        if [ "$TA_MV" = defer ]; then
          die "task-add refused — $(clean "$TA_BID") was moved to defer, and its newest move stands: $(clean "$(proof_move_line "$TA_PLAN" "$TA_BID")"); $TA_ID stands in the plan unborn, the person's to remove. To fix it after all: finding-move $(clean "$TA_BID") fix '<their words>' '<why>', then task-add again."
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
        die "task-add refused — born: $TA_OFF_RATING is outside fix-policy: $TA_POL; $TA_ID stands in the plan unborn, the person's to remove; the finding goes to the review findings disposition (AC-10.3). To fix $(clean "$TA_OFF") anyway: disposition $(clean "$TA_OFF") fix '<their words>' '<why>', then task-add again."
        exit 1
      fi
      # A gravest rating outside the policy got here only by the person's move to fix: the marker says so, and
      # the row counts against fix-cap: whatever the policy later becomes.
      TA_RATING="${TA_BORN#review }"
      fix_policy_covers "$TA_POL" "${TA_RATING% *}" "${TA_RATING#* }" || TA_BORN_MARK="$TA_BORN_MARK promoted"
    fi
    TA_CELL_TASK="$TA_TASK"
    if [ -n "$TA_BORN" ]; then
      TA_RATING="${TA_BORN#review }"
      if [ -z "$TA_BORN_IDS" ] && ! fix_policy_covers "$TA_POL" "${TA_RATING% *}" "${TA_RATING#* }"; then
        die "task-add refused — born: $TA_BORN is outside fix-policy: $TA_POL; $TA_ID stands in the plan unborn, the person's to remove; the finding goes to the review findings disposition (AC-10.3)."
        exit 1
      fi
      if ! TA_COUNTED="$(units_born_counted "$TA_PLAN")"; then
        die "task-add refused — the review-born rows of $TA_PLAN cannot be counted against fix-cap: (lib/run.sh, which reads fix-policy:, is not loaded); nothing is born. Run /bionic:doctor to see which library answered."
        exit 1
      fi
      TA_NCOUNT="$(printf '%s\n' "$TA_COUNTED" | awk -F'\t' '$3 == "counted" { n++ } END { print n + 0 }')"
      TA_NEXEMPT="$(printf '%s\n' "$TA_COUNTED" | awk -F'\t' '$3 == "exempt" { n++ } END { print n + 0 }')"
      TA_CLASS="$(units_born_class "$TA_PLAN" "$TA_POL" "$TA_RATING" "${TA_BORN_MARK# }")"
      TA_COUNT_SAID="exempt under fix-policy: $TA_POL"
      if [ "$TA_CLASS" = counted ]; then
        if ! TA_CAP="$(units_fix_cap "$TA_PLAN")"; then
          die "task-add refused — born: $TA_BORN has no cap to count against: fix-cap: '$(plan_frontmatter_get "$TA_PLAN" fix-cap)' is no count, or the plan names no rigor: to default it from; $TA_ID stands in the plan unborn, the person's to remove."
          exit 1
        fi
        if [ "$TA_NCOUNT" -ge "$TA_CAP" ]; then
          die "task-add refused — review-born rows: $TA_NCOUNT of cap $TA_CAP are counted ($TA_NEXEMPT exempt under fix-policy: $TA_POL); $TA_ID stands in the plan unborn, the person's to remove; this finding goes to the review findings disposition, or the person raises the cap: set fix-cap=$((TA_NCOUNT + 1)) at the card."
          exit 1
        fi
        TA_COUNT_SAID="counted $((TA_NCOUNT + 1)) of $TA_CAP"
      fi
      TA_BORN_ROWS="$(units_born "$TA_PLAN")"
      while IFS= read -r TA_PATH; do
        [ -n "$TA_PATH" ] || continue
        case "$TA_PATH" in .bionic/*|record/*) continue ;; esac
        case " $REGISTRY_FILES " in *" $TA_PATH "*) continue ;; esac
        TA_FIXERS="$(printf '%s\n' "$TA_BORN_ROWS" | while IFS=$'\t' read -r TA_BID _ TA_BFILES; do
            [ -n "$TA_BID" ] || continue
            _units_files_tokens "$TA_BFILES" | grep -Fx -- "$TA_PATH" >/dev/null && printf '%s\n' "$TA_BID"
          done)"
        if [ "$(printf '%s' "$TA_FIXERS" | awk 'NF { n++ } END { print n + 0 }')" -ge 3 ]; then
          die "task-add refused — a fourth fix on $TA_PATH: $(printf '%s' "$TA_FIXERS" | paste -sd, - | sed 's/,/, /g') already fix it; $TA_ID stands in the plan unborn, the person's to remove; stop the run (AC-10.2)"
          exit 1
        fi
      done <<EOF
$(_units_files_tokens "$TA_FILES")
EOF
      TA_CELL_TASK="$TA_CELL_TASK · born: review"
    fi
    # A FLOOR-BORN MARKER NAMES ITS RED: the marker is admitted only with a red the machine recorded behind it
    # (`born_floor_backing`), and it records which, ` of=regression`, ` of=standing@<12-hex>` or ` of=run@<12-hex>`.
    TA_BORN_OF=""
    if [ -n "$TA_BORN_SUITE" ]; then
      if ! born_floor_backing "$TA_PLAN" "$REPO_REAL" "$TA_BORN_SUITE"; then
        if born_red_log "$TA_PLAN" "$REPO_REAL"; then
          die "task-add refused — born: regression $TA_BORN_SUITE names no red the machine recorded; proof-add the red run's log first: bash ${HOOK_DIR}/session-poker.sh proof-add regression $BFB_LOG; $TA_ID stands in the plan unborn, the person's to remove."
        else
          die "task-add refused — born: regression $TA_BORN_SUITE names no red the machine recorded; it is admitted when the plan's regression proof owes $TA_BORN_SUITE (it owes ${BFB_OWED:-nothing}; proof-add regression, from a whole run that left it red) or when the landing record holds a standing event or a red verdict for $TA_BORN_SUITE at a commit on ${BFB_BRANCH:-the working branch}; $TA_ID stands in the plan unborn, the person's to remove."
        fi
        exit 1
      fi
      TA_BORN_OF="$BFB_OF"; TA_CELL_TASK="$TA_CELL_TASK · born: regression"
    fi

    # THE DECLARATION RIDES THE TASK CELL beside the born tag, in its style, where `units_questions` lifts it.
    [ -z "$TA_QUESTIONS" ] || TA_CELL_TASK="$TA_CELL_TASK · questions: $TA_QUESTIONS"
    pv_task_cells_or_refuse "$TA_ID" "$TA_CELL_TASK"
    TA_ART_CELL=""
    if [ -n "$TA_REV_ART" ] && pv_header_cells "$TA_PLAN" tasks | /usr/bin/grep -ix artifact >/dev/null; then TA_ART_CELL="$TA_REV_ART"; fi
    ta_none() { case "$1" in ''|'—'|'-') printf '—' ;; *) printf '%s' "$1" ;; esac; }
    TA_SHORT=""
    [ "$(ta_none "$TA_FILES")" = "$(ta_none "$TA_READ_FILES")" ] || TA_SHORT="${TA_SHORT}, its Files"
    [ "$TA_CELL_TASK" = "$TA_CELL" ] || TA_SHORT="${TA_SHORT}, its task cell's tags"
    [ -z "$TA_ART_CELL" ] || [ "$TA_ART_CELL" = "$(ta_cell artifact)" ] || TA_SHORT="${TA_SHORT}, its artifact"
    if [ -n "$TA_SHORT" ]; then
      die "REFUSED — $TA_ID is short of the row task-add accepts: ${TA_SHORT#, }. The plan is unchanged and nothing is born. Edit the ## Tasks table to these lines, $TA_ID first, then task-add $TA_ID again:"
      ta_line "$TA_ID" files="$(ta_none "$TA_FILES")" task="$TA_CELL_TASK" ${TA_ART_CELL:+artifact="$TA_ART_CELL"} >&2
      exit 1
    fi
    TA_VIOL="$(units_validate "$TA_PLAN" 2>&1)"
    if [ -n "$TA_VIOL" ]; then
      die "REFUSED — the ## Tasks table holding $TA_ID breaks the Task invariants; nothing is born:"
      printf '%s\n' "$TA_VIOL" >&2
      exit 1
    fi

    # THE BIRTH IS THE LOG'S: one born event, through the one writer, carrying what a born marker carried (the rating and
    # its findings, or the regression and its record).
    case "$TA_BORN_MARK" in *" promoted") TA_PROMOTED=1 ;; *) TA_PROMOTED="" ;; esac
    if ! units_born_event "$TA_PLAN" "$TA_ID" "${TA_BORN}${TA_BORN_SUITE:+regression $TA_BORN_SUITE}" \
         "${TA_BORN_IDS}${TA_BORN_SUITE:+$TA_BORN_OF}" "$TA_PROMOTED"; then
      die "task-add — the born event of $TA_ID could not be appended to the run's log; the row reads as born by no review or regression until it is. Run task-add $TA_ID again."
      exit 1
    fi
    say "task-add — $TA_ID is born: its born event is in the run's log, and $TA_PLAN is unchanged."
    [ -z "$TA_ART" ] || say "task-add — $TA_ID is a $TA_KIND row: its Files carry its record artifact, $TA_ART."
    [ -z "$TA_REV_ART" ] || say "task-add — $TA_ID is a review row: its Files carry one record per question it is dealt${TA_ART_CELL:+, its artifact cell the first, $TA_ART_CELL}."
    [ -z "$TA_BORN" ] || say "task-add — $TA_ID is review-born ($TA_BORN); say so in the review findings disposition · $TA_COUNT_SAID"
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
    # WHAT THE TURN NOW OWES, SAID AT THE ACT: the harness's task list lacks the row, and the entries after it are
    # recreated to keep the order. The entry is named as the task list names it, by the row's title, and the line is
    # the verb's last so the rule is read where it fires and no step text has to carry it.
    say "task-add — owed: create the task-list entry $TA_STEP/$TA_ID: $(clean_whole "$(plan_task_title "$TA_CELL_TASK")"), and recreate the entries after it to keep the order."
    exit 0
  }

  # THE BRIEF, RENDERED WHOLE. One file per dispatch, record/<wave>/briefs/<name>.md, where <name> is the agent's
  # name (given, else the one the fill hands this row on this session's roster). Everything in it is rendered: the
  # scaffold from the row's cells, the judgment from the task's own section of the plan (plan-read.sh's
  # `plan_read_section`), and the review range, Questions and Lands-red from the reader. Nothing is typed into the
  # file, so a judgment the plan lacks is said in words, never left blank, and the way to supply it is to write the
  # section and render again. The plan is never changed. REFUSED (1), nothing written: an id that is no row id, a plan
  # with no Tasks table, a row the table lacks or carries twice, a name that is not this row's, a file of that name
  # this verb did not render (the run's record keeps it as written), a section typing a contract label (the contract
  # is rendered, and a typed Re-executes: is a declared command the wall may not match), a review row whose declared
  # questions are not one reader's, and a file naming a session-poker verb the listing lacks. REFUSED (2): the
  # shipped scaffold, the plan parser or a scratch file cannot be had.
  poker_verb_brief() {
    plan_verb_open brief
    if ! plan_verb_id_ok "$BRF_ID"; then
      die "REFUSED — '$(clean "$BRF_ID")' is not one row id: an id is one token of letters, digits, '.', '_' or '-', beginning with a letter or a digit. Nothing was written."
      exit 1
    fi
    if ! declare -F plan_read_section >/dev/null 2>&1 && ! . "$BIONIC_LIB/plan-read.sh" 2>/dev/null; then
      die "REFUSED — the plan parser (lib/plan-read.sh) cannot be loaded from $BIONIC_LIB. Nothing was written. Fix: reinstall the plugin, then run again: bash ${HOOK_DIR}/session-poker.sh brief $BRF_ID"
      exit 2
    fi
    BRF_ROWS="$(plan_read_rows "$PV_PLAN" Tasks 2>/dev/null)" || BRF_ROWS=""
    if [ -z "$BRF_ROWS" ]; then
      die "REFUSED — $PV_PLAN carries no ## Tasks table with a row, so there is nothing to render. Nothing was written."
      exit 1
    fi
    BRF_N="$(printf '%s\n' "$BRF_ROWS" | awk -F'\t' -v k="id=$BRF_ID" '$1 == k' | wc -l | tr -d ' ')"
    if [ "$BRF_N" -ne 1 ]; then
      BRF_IDS="$(printf '%s\n' "$BRF_ROWS" | awk -F'\t' '{ sub(/^id=/, "", $1); printf "%s%s", (n++ ? ", " : ""), $1 }')"
      BRF_EG="$(printf '%s\n' "$BRF_ROWS" | awk -F'\t' '{ for (i = 2; i <= NF; i++) if ($i == "status=pending") { sub(/^id=/, "", $1); print $1; exit } }')"
      [ -n "$BRF_EG" ] || BRF_EG="$(printf '%s\n' "$BRF_ROWS" | awk -F'\t' 'NR == 1 { sub(/^id=/, "", $1); print $1 }')"
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
    # THE CELLS ARE NAMED BY THE TABLE'S HEADER, the row's nine authored cells; a cell the table lacks is empty.
    BRF_CELLS="$(plan_read_row "$PV_PLAN" Tasks id "$BRF_ID")"
    brf_cell() { printf '%s\n' "$BRF_CELLS" | awk -v k="$1=" 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }'; }
    BRF_TASK="$(brf_cell task)"; BRF_KIND="$(brf_cell kind)"; BRF_STEP="$(brf_cell step)"; BRF_SIZE="$(brf_cell size)"
    BRF_FILES="$(brf_cell files)"; BRF_SERVES="$(brf_cell serves)"; BRF_DEPS="$(brf_cell deps)"
    BRF_WAVE="$(proof_plan_slug "$PV_PLAN")"
    BRF_DOCS="$(docs_root "$PV_REPO")"
    BRF_RECDIR="$BRF_DOCS/record/$BRF_WAVE"
    case "$BRF_RECDIR" in "$PV_REPO"/*) BRF_RECREL="${BRF_RECDIR#"$PV_REPO"/}" ;; *) BRF_RECREL="$BRF_RECDIR" ;; esac
    { [ -n "${_LINE_FIELDS_AWK:-}" ] || . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1

    # THE NAME IS THE DISPATCH'S: a re-dispatch gets its own file beside the first, so the record keeps what each
    # agent was given. It must be a name the dispatch wall binds to this row (the id, or the id behind a prefix).
    [ -n "${BRF_NAME:-}" ] || BRF_NAME="$(fill_name "$PV_REPO/.bionic/tmp/roster-$(session_id).state" "$BRF_ID")"
    if ! plan_verb_id_ok "$BRF_NAME" || ! fill_row_launched "$BRF_ID" "$BRF_NAME"; then
      die "REFUSED — '$(clean "$BRF_NAME")' is not a name of row $BRF_ID: the dispatch wall binds a name to the row it ends with (the id, or <prefix>-$BRF_ID, with -r<n> for a re-dispatch). Nothing was written. Run again: bash ${HOOK_DIR}/session-poker.sh brief $BRF_ID <prefix>-$BRF_ID"
      exit 1
    fi
    BRF_OUT="$BRF_RECDIR/briefs/$BRF_NAME.md"
    if ! poker_brief_load || ! declare -F brief_mark >/dev/null 2>&1; then
      die "REFUSED — the brief's mark (lib/brief.sh) cannot be loaded from $BIONIC_LIB. Nothing was written. Fix: reinstall the plugin, then run again: bash ${HOOK_DIR}/session-poker.sh brief $BRF_ID $BRF_NAME"
      exit 2
    fi
    # THE MARK NAMES THE ROW AND THE NAME; its sum is of the file as rendered now, so a file this verb wrote is
    # known by the mark's opening words whatever its sum was.
    BRF_MARKED="<!-- brief: rendered from row $BRF_ID for $BRF_NAME;"
    if [ -e "$BRF_OUT" ] && case "$(head -1 "$BRF_OUT" 2>/dev/null)" in "$BRF_MARKED"*) false ;; *) true ;; esac; then
      die "REFUSED — ${BRF_OUT#"$PV_REPO"/} was not rendered by this verb for row $BRF_ID: it is part of the run's record and is kept as written. Render the row under the name its agent is dispatched as: bash ${HOOK_DIR}/session-poker.sh brief $BRF_ID <name>. Nothing was written."
      exit 1
    fi

    # THE TASK'S OWN SECTION: its suites: and lands-on: lines are the row's suites and what it lands on, and every
    # other line is the judgment. A contract label typed there would give the agent a second answer to the rendered one.
    BRF_SEC="$(plan_read_section "$PV_PLAN" "$BRF_ID")" && BRF_HASSEC=1 || BRF_HASSEC=""
    BRF_JUDG="$(printf '%s\n' "$BRF_SEC" | awk '!/^(suites|lands-on):/' | awk 'NF { n++ } n')"
    BRF_TYPED="$(printf '%s\n' "$BRF_JUDG" | awk -v labs="$(printf '%s\n' "$BRF_LABELS" | tr '\n' '|')" '
      BEGIN { n = split(labs, L, "|"); for (i = 1; i <= n; i++) if (L[i] != "") lab[tolower(L[i])] = L[i] }
      { s = $0; sub(/^[ \t]*/, "", s); e = index(s, ":"); if (e > 1 && (tolower(substr(s, 1, e - 1)) in lab)) { print substr(s, 1, e); exit } }')"
    if [ -n "$BRF_TYPED" ]; then
      die "REFUSED — the plan's section for $BRF_ID types the contract label $BRF_TYPED, and a brief's contract is rendered, never typed: take the line out of the section (suites: and lands-on: are the section's own keys; widen a live dispatch with amend <name>). Nothing was written. Then run again: bash ${HOOK_DIR}/session-poker.sh brief $BRF_ID $BRF_NAME"
      exit 1
    fi

    # THE ARTIFACT: the row's own `artifact` cell, the ledger's cell for the row, the Files entry named for the row, the
    # first record entry, then the record the task names. One path or nothing.
    BRF_ART=""
    BRF_ACELL="$(brf_cell artifact)"
    if ! poker_brief_none "$BRF_ACELL"; then
      case "$BRF_ACELL" in *[[:space:],]*) : ;; *) BRF_ART="$BRF_ACELL" ;; esac
    fi
    BRF_LEDGER="$(plan_read_row "$PV_PLAN" "Dispatch ledger" id "$BRF_ID" 2>/dev/null | sed -n 's/^artifact=//p')"
    if [ -z "$BRF_ART" ] && ! poker_brief_none "$BRF_LEDGER"; then
      case "$BRF_LEDGER" in *[[:space:],]*) : ;; *) BRF_ART="$BRF_LEDGER" ;; esac
    fi
    [ -n "$BRF_ART" ] || BRF_ART="$(poker_brief_record_entry "$BRF_FILES" artifact "$BRF_ID")"
    [ -n "$BRF_ART" ] || BRF_ART="$(poker_brief_task_record "$BRF_TASK")"
    # A READER ROW'S ARTIFACT IS ITS RECORD: a verify, test or review row that names none writes <record dir>/<row>.md,
    # the progress artifact's convention, and its Files line carries it.
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

    # THE SUITES AND WHAT THE ROW LANDS ON: its section's lines, else its Files' *.test.sh entries, in order; else, for
    # a row that writes code, the slot: `none` is a waiver nobody chose for it.
    BRF_SUITES="$(plan_read_section "$PV_PLAN" "$BRF_ID" suites)"
    BRF_LANDS="$(plan_read_section "$PV_PLAN" "$BRF_ID" lands-on)"
    BRF_SUITE_SLOT=""
    poker_brief_none "$BRF_SUITES" && BRF_SUITES="$(poker_brief_suites "$BRF_FILES")"
    if units_writes_head "$BRF_FILES"; then
      # A ROW THAT WRITES CODE NAMES ITS SUITES: `none` is a waiver nobody chose, so the slot is the orchestrator's to
      # fill. A `none` Lands-on cell is the dispatch wall's refusal for such a row, so it is not carried.
      [ -n "$BRF_SUITES" ] || BRF_SUITE_SLOT="<ORCHESTRATOR: the row names no suite; write the suites that pin its Files>"
      case "$BRF_LANDS" in none|none[[:space:]]*) BRF_LANDS="" ;; esac
    fi
    if poker_brief_none "$BRF_LANDS"; then
      BRF_LANDS="$BRF_SUITES"
      [ -n "$BRF_LANDS" ] || BRF_LANDS="$BRF_SUITE_SLOT"
      [ -n "$BRF_LANDS" ] || BRF_LANDS="none the row's Files name no suite"
    fi
    [ -n "$BRF_SUITES" ] || BRF_SUITES="${BRF_SUITE_SLOT:-none}"

    # THE PINS OF THE SUITES: each suite in Suites declares the files it pins in its own header, and they follow the
    # row's Files on lines of their own, each marked with the suite that pins it (a suite with no header adds nothing).
    # The Files reader takes a line's trailing comment off, so the mark is read by people and never as a path.
    BRF_PINNED="$(poker_brief_pinned "$PV_REPO" "$BRF_SHA" "$BRF_FILES" "$BRF_SUITES")"
    if [ -n "$BRF_PINNED" ]; then
      if poker_brief_none "$BRF_FILES_LINE"; then BRF_FILES_LINE="$BRF_PINNED"; else BRF_FILES_LINE="$BRF_FILES_LINE
$BRF_PINNED"; fi
    fi

    # A REVIEW ROW'S QUESTIONS are the ones its task declares, held to the rigor's deal by the one reading of it that
    # task-add uses; its range starts, per question, at the head of the last review proof the reader holds for it (the
    # chain a review continues), else at the run's base, and ends at the working head.
    BRF_QS=""; BRF_QLINE=""; BRF_RANGE=""
    if [ "$BRF_KIND" = review ]; then
      BRF_QS="$(units_questions "$(printf '%s\t%s\t%s\t%s' "$BRF_ID" "$BRF_STEP" "$BRF_KIND" "$BRF_TASK")")"
      if [ -n "$BRF_QS" ] && ! poker_questions_dealt "$PV_PLAN" "$BRF_QS"; then
        die "REFUSED — row $BRF_ID declares the questions $BRF_QS, which are not dealt: $PQD_SAID. Nothing was written. Fix: make the row's questions one reviewer's, then run again: bash ${HOOK_DIR}/session-poker.sh brief $BRF_ID $BRF_NAME"
        exit 1
      fi
      BRF_QLINE="${BRF_QS//,/, }"
      poker_fold_ask BRF_ANS "brief $BRF_ID $BRF_NAME" "$PV_PLAN" reader_q_header base-sha; BRF_BASE="$(printf '%s\n' "$BRF_ANS" | sed -n 's/^base-sha=//p')"
      poker_fold_ask BRF_ANS "brief $BRF_ID $BRF_NAME" "$PV_PLAN" reader_q_reviews
      BRF_RANGE="$(printf '%s\n' "$BRF_ANS" | awk -F'|' -v qs=",$BRF_QS," -v base="${BRF_BASE:-(no review proof and no base-sha)}" \
        -v end="${BRF_SHA:-$BRF_HEAD}" "$_LINE_FIELDS_AWK"'
        line_kv("ev") == "proof" && index(qs, "," line_kv("question") ",") { last[line_kv("question")] = line_kv("head") }
        END {
          n = split(substr(qs, 2, length(qs) - 2), q, ",")
          for (i = 1; i <= n; i++) { a[i] = (q[i] in last) ? last[q[i]] : base; if (a[i] != a[1]) mixed = 1 }
          if (!mixed) print "Reviewed range: " a[1] ".." end
          else for (i = 1; i <= n; i++) print "Reviewed range (" q[i] "): " a[i] ".." end
        }')"
    fi
    # A RED THE ROW MAY LAND WITH is a red admitted for it that the reader still holds open; the evidence is the
    # writer's to write, at a path the brief names.
    poker_fold_ask BRF_ANS "brief $BRF_ID $BRF_NAME" "$PV_PLAN" reader_q_debts
    BRF_RED="$(printf '%s\n' "$BRF_ANS" | awk -F'|' -v r="$BRF_ID" "$_LINE_FIELDS_AWK"'
      line_kv("ev") == "admitted" && line_kv("row") == r { l = line_kv("suite") " until " line_kv("token") } END { if (l != "") print l }')"

    # THE SCAFFOLD, in the shipped order. A label with no source on this row is not written.
    poker_fold_ask BRF_ANS "brief $BRF_ID $BRF_NAME" "$PV_PLAN" reader_q_status "$BRF_ID"; BRF_STATUS="$(printf '%s\n' "$BRF_ANS" | sed -n 's/^state=//p')"
    BRF_BODY="$(mktemp "${TMPDIR:-/tmp}/brief.XXXXXX")" || { die "REFUSED — no scratch file can be made. Nothing was written."; exit 2; }
    case "$BRF_SIZE" in ''|*[!0-9]*) BRF_BIG=no ;; *) if [ "$BRF_SIZE" -ge 15 ]; then BRF_BIG=yes; else BRF_BIG=no; fi ;; esac
    BRF_PROG="$(poker_brief_record_entry "$BRF_FILES" progress "$BRF_ID")"
    [ -n "$BRF_PROG" ] || BRF_PROG="$BRF_RECREL/$BRF_ID.progress.md"
    {
      printf '<!-- brief -->\n'
      while IFS= read -r BRF_L; do
        case "$BRF_L" in
          "Expected duration")
            case "$BRF_SIZE" in
              ''|*[!0-9]*) printf '%s: <ORCHESTRATOR: the row'"'"'s size is %s; write the minutes>\n' "$BRF_L" "${BRF_SIZE:-empty}" ;;
              *) printf '%s: %s minutes\n' "$BRF_L" "$BRF_SIZE" ;;
            esac ;;
          "Expected artifact") printf '%s: %s\n' "$BRF_L" "${BRF_ART:-<ORCHESTRATOR: the row has none; write it>}" ;;
          "Progress artifact") [ "$BRF_BIG" = yes ] && printf '%s: %s\n' "$BRF_L" "$BRF_PROG" ;;
          "Cadence")           [ "$BRF_BIG" = yes ] && printf '%s: 15 min\n' "$BRF_L" ;;
          "Files")             poker_brief_none "$BRF_FILES_LINE" || printf '%s: %s\n' "$BRF_L" "$BRF_FILES_LINE" ;;
          "Suites")            printf '%s: %s\n' "$BRF_L" "$BRF_SUITES" ;;
          "Questions")         [ "$BRF_KIND" != review ] || printf '%s: %s\n' "$BRF_L" "${BRF_QLINE:-<ORCHESTRATOR: the row declares no questions>}" ;;
          "Row")               printf '%s: %s\n' "$BRF_L" "$BRF_ID" ;;
          "Lands-on")          printf '%s: %s\n' "$BRF_L" "$BRF_LANDS" ;;
          "Lands-red")         [ -z "$BRF_RED" ] || printf '%s: %s\n' "$BRF_L" "$BRF_RED" ;;
          "Red-evidence")      [ -z "$BRF_RED" ] || printf '%s: %s/%s-red.md\n' "$BRF_L" "$BRF_RECREL" "$BRF_NAME" ;;
        esac
      done <<BRF_EOF
$BRF_LABELS
BRF_EOF
      printf '\n## The row\n\n%s\n\n' "$BRF_TASK"
      printf 'Row %s: kind %s, step %s, serves %s, waits on %s, status %s.\n' "$BRF_ID" "$BRF_KIND" "$BRF_STEP" "$BRF_SERVES" "${BRF_DEPS:-—}" "${BRF_STATUS:-pending}"
      printf 'Working head: %s\n' "$BRF_HEAD"
      [ -z "$BRF_RANGE" ] || printf '%s\n' "$BRF_RANGE"
      printf 'Plan: %s\n\n## Judgment\n\n' "$(clean "${PV_PLAN#"$PV_REPO"/}")"
      if [ -n "$BRF_JUDG" ]; then
        printf '%s\n' "$BRF_JUDG"
      else
        if [ -n "$BRF_HASSEC" ]; then printf 'NO JUDGMENT: the plan'"'"'s section for %s holds nothing but its suites' "$BRF_ID"
        else printf 'NO JUDGMENT: the plan has no section for %s' "$BRF_ID"; fi
        printf ', so this brief carries no research to read and no rulings. Write them into the plan under a heading whose first word is %s (## %s — <title>), then render again: bash %s/session-poker.sh brief %s %s\n' \
          "$BRF_ID" "$BRF_ID" "$HOOK_DIR" "$BRF_ID" "$BRF_NAME"
      fi
    } > "$BRF_BODY"

    # EVERY VERB THE FILE NAMES IS ONE THE LISTING HOLDS: a brief that sends its agent to a verb that does not exist is
    # refused here, where the section can still be fixed.
    BRF_UNKNOWN="$(comm -23 <(grep -o 'session-poker\.sh[[:space:]][[:space:]]*[a-z][a-z0-9-]*' "$BRF_BODY" | awk '{ print $2 }' | LC_ALL=C sort -u) \
      <(poker_verbs_listed | LC_ALL=C sort -u) | paste -sd, - | sed 's/,/, /g')"
    if [ -n "$BRF_UNKNOWN" ]; then
      rm -f "$BRF_BODY"
      die "REFUSED — the brief for $BRF_ID would name session-poker.sh $BRF_UNKNOWN, which the verb listing does not hold; correct the plan's section for $BRF_ID. Nothing was written. Then run again: bash ${HOOK_DIR}/session-poker.sh brief $BRF_ID $BRF_NAME"
      exit 1
    fi
    # THE SUM IS OF EVERY LINE BELOW THE MARK, which takes its place on the first line last.
    BRF_SUMV="$(brief_sum "$BRF_BODY")" || BRF_SUMV=""
    if [ -z "$BRF_SUMV" ] || ! { brief_mark "$BRF_ID" "$BRF_NAME" "$BRF_SUMV"; printf '\n'; tail -n +2 "$BRF_BODY"; } > "$BRF_BODY.m" 2>/dev/null; then
      rm -f "$BRF_BODY" "$BRF_BODY.m"
      die "REFUSED — the brief's sum cannot be taken (neither shasum nor sha256sum answers). Nothing was written. Install one, then run again: bash ${HOOK_DIR}/session-poker.sh brief $BRF_ID $BRF_NAME"
      exit 2
    fi
    mv -f "$BRF_BODY.m" "$BRF_BODY"
    mkdir -p "${BRF_OUT%/*}" 2>/dev/null
    if ! mv -f "$BRF_BODY" "$BRF_OUT" 2>/dev/null; then
      rm -f "$BRF_BODY"
      die "REFUSED — $BRF_OUT cannot be written. The plan is unchanged."
      exit 2
    fi
    if [ -n "$BRF_JUDG" ]; then BRF_SAID="the plan's section for $BRF_ID"; else BRF_SAID="NONE — the plan has no words for $BRF_ID; write its section and render again"; fi
    say "brief — $BRF_ID: written to ${BRF_OUT#"$PV_REPO"/} for the dispatch named $BRF_NAME; the dispatch prompt's first line names that file. Its judgment: $BRF_SAID."
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
  #   run.so-far    one line, the reader's acts taken by hand and open asks over the run, the sheet's line word for word
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

  # rr_rows <plan> <current> [head] -> `<AC>\037<tier>\037<status>\037<auditor>\037<ruled 1|0|owed:<step>>\037<person>\037<reason>`
  # per criterion, the reader's order. THE RULING IS THE GATE'S: each criterion is read through its readers (`matrix_load`,
  # the reader's answer, and `matrix_table_rows`), and it is unruled exactly when the gate at 8 asks something of it:
  # walls.sh `matrix_unruled` names it (the ruling the advance asks, at double rigor), or `matrix_row_awaits` holds (the
  # person's confirmation the commit at 8 asks at any rigor), sourced in a subshell as the facts judge sources them, so
  # the card and the gate cannot answer one row two ways: at single rigor no auditor's word is owed, so no row waits on one. A
  # WAIVER IS A FACT OF THE RUN: the reader's status says waived only where a waiver event names the criterion. A row the
  # gate defers at <current> (`matrix_row_deferred`: owed at the later step whose task proves it) is `owed:<step>`, not
  # ruled and not unruled, whatever verdict a passed evidence review gives it, as the gate asks the deferral first:
  # nothing has run that could prove it, and the step that runs it writes it. A row `matrix_unruled` defers at 8 is
  # deferred at every step before it, so it reads owed here. The auditor is printed as
  # `placeholder_cell` folds it, `-` when it means none. THE PERSON'S PART is `confirmed` for a T4 row holding an attributed
  # confirmation, `awaits` for a T4 row holding none that one would rule (the same `matrix_row_ruled` asked of the row
  # with a confirmation in its attributed shape), and `-` otherwise. Its auditor cell never answers this alone, since
  # at 15 that cell is the run's evidence review, which no person gave. The reason is empty: a page at 15 holds no block. Exit 2 when
  # walls.sh cannot be loaded or the run's facts could not be read: the card never guesses a ruling.
  rr_rows() {
    [ -f "$BIONIC_LIB/walls.sh" ] || return 2
    ( . "$BIONIC_LIB/walls.sh" >/dev/null 2>&1 && declare -F matrix_unruled >/dev/null 2>&1 \
        && declare -F matrix_row_awaits >/dev/null 2>&1 && declare -F matrix_row_deferred >/dev/null 2>&1 || exit 2
      PLAN="$1"; unruled="$(matrix_unruled "$PLAN" 8 "${3:-}")" || exit 2
      matrix_load "$PLAN" "${3:-}" || exit 2
      while IFS=$'\037' read -r ac tier status ev aud conf waiver; do
        [ -n "$ac" ] || continue
        ruled=1; case $'\n'"$unruled"$'\n' in *$'\n'"$ac"$'\n'*) ruled=0 ;; esac
        ! matrix_row_awaits "$tier" "$status" "$aud" "$conf" "$waiver" || ruled=0
        person=-
        if [ "$tier" = T4 ]; then
          if user_confirmed_attributed "$conf"; then person=confirmed
          elif matrix_row_ruled "$tier" "$status" "$aud" "you 1970-01-01 confirmed" "$waiver"; then person=awaits; fi
        fi
        owe="$(matrix_owing_step "$PLAN" "$ac")"
        ! matrix_row_deferred "$PLAN" "$owe" "$2" "$status" "$(matrix_owing_open "$PLAN" "$ac")" || ruled="owed:$owe"
        aud="$(placeholder_cell "$aud")"
        printf '%s\037%s\037%s\037%s\037%s\037%s\037\n' "$ac" "$tier" "$status" "${aud:--}" "$ruled" "$person"
      done <<RR_MATRIX
$(matrix_table_rows)
RR_MATRIX
    )
  }

  rr_since() {  # <approved head> -> `approved at <head8>, <n> commit(s) landed since[ (<rows>)]`, the rows from the landing record
    local n rows
    n="$(git -C "$PV_REPO" rev-list --first-parent --count "$1..$RR_HEAD" 2>/dev/null)" || n=""
    rows="$(git -C "$PV_REPO" rev-list --first-parent "$1..$RR_HEAD" 2>/dev/null \
      | units_rows_in_range "$PV_PLAN" "$1..$RR_HEAD" "$(proof_debt_record "$PV_PLAN" "$PV_REPO" 2>/dev/null)" 2>/dev/null | cut -f1 | paste -sd' ' -)"
    printf 'approved at %s' "${1:0:8}"
    [ -z "$n" ] || printf ', %s landed since' "$(rr_plural "$n" commit commits)"
    [ -z "$rows" ] || printf ' (%s)' "$rows"
  }

  rr_proof_field() {  # <proof line> <name> -> the value of name=<word> on it, or nothing
    case " $1 " in *" $2="*) local v="${1#* "$2"=}"; [ "$v" != "$1" ] || v="${1#"$2"=}"; printf '%s' "${v%% *}" ;; esac
  }

  # A carry the person answered on a replied page is read from that page, the card's own replay record: the reply
  # writes no fact of its own for a carried decision, so no reader question holds it.
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
    # each goal's mark is its status, lib/plan.sh plan_goal_status's, the one the sitrep's sheet prints; a theme's row
    # carries its opener as a fifth field the page does not draw, so the row is cut to its four before it is sent
    [ -z "$RR_GOALS" ] || printf '%s\n' "$RR_GOALS" | while IFS= read -r l; do
      [ -n "$l" ] || continue
      [ "${l%%	*}" != mapping ] || continue
      case "$(plan_goal_status "${l%%	*}")" in
        met) m="$SITREP_MARK_WITHIN" ;;
        'not met') m="$SITREP_MARK_OVER" ;;
        'on course') m="${SITREP_MARK_COURSE:-⬜}" ;;
        *) m="$SITREP_MARK_NONE" ;;
      esac
      printf 'goal\t%s\t%s\t%s\n' "${l%%	*}" "$m" "$(printf '%s\n' "${l#*	}" | cut -f1-3)"
    done
    [ -z "${RR_SOFAR:-}" ] || rr_fact sofar "$RR_SOFAR"
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
    local nm line key reply ac tier st au ruled person why fid sev reach state rows stated ttl sent ev q num dec grp h r role behind again
    if ! { declare -F proof_branch_head >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_last_line >/dev/null 2>&1 || ! _proof_reader_load; then
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

    # THE TITLE'S FACTS: the project, the release, the tasks landed. Every fact of the run is a reader answer over the
    # kept fold (lib/proof.sh `_proof_ask`), so the page says what the log holds at this instant, and the plan's rows
    # are the scheduler's (`units_rows`).
    RR_PROJ="$(git -C "$PV_REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
    case "$RR_PROJ" in */.git) RR_PROJ="${RR_PROJ%/.git}"; RR_PROJ="${RR_PROJ##*/}" ;; *) RR_PROJ="${PV_REPO##*/}" ;; esac
    RR_AGAIN="release-approval$([ "$RR_PREVIEW" != yes ] || printf ' --preview') $PV_PLAN"
    poker_fold_ask RR_ANS "$RR_AGAIN" "$PV_PLAN" reader_q_header release; RR_REL="$(printf '%s\n' "$RR_ANS" | sed -n 's/^release=//p')"
    poker_fold_ask RR_ANS "$RR_AGAIN" "$PV_PLAN" reader_q_landed; RR_LANDED_IDS=" $(printf '%s\n' "$RR_ANS" | sed -n 's/.*|row=\([^|]*\)|.*/\1/p' | tr '\n' ' ')"
    set -- $(units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' -v l="$RR_LANDED_IDS" 'NF >= 10 { t++; if (index(l, " " $1 " ")) n++ } END { print t + 0, n + 0 }')
    RR_TOTAL="${1:-0}"; RR_LANDED="${2:-0}"

    RR_N=0; RR_ASIDE=""
    RR_KIND=(); RR_KEY=(); RR_DO=(); RR_ELSE=(); RR_WHYS=(); RR_SUBJ=(); RR_DLAB=(); RR_OLAB=(); RR_DPH=(); RR_OPH=(); RR_PICK=()

    # WAIVERS: the run's open waive: asks (the reader's `asks`), then the ones the red check owes, each once; never the
    # regression. A waiver a close-out preflight or another session of the run raised is owed here as well. A gate's
    # ask is an aside in its own words, which only the run's register (lib/owed.sh `owed_list_plan`) keeps.
    poker_fold_ask RR_ANS "$RR_AGAIN" "$PV_PLAN" reader_q_asks
    RR_WAIVE="$(printf '%s\n' "$RR_ANS" | sed -n 's/.*|key=\(waive:[^|]*\)|.*/\1/p' | /usr/bin/grep -vx 'waive:regression')"
    while IFS='	' read -r key _ _ reply; do
      case "$key" in gate:?*) RR_ASIDE="${RR_ASIDE}${reply#poker: }"$'\n' ;; esac
    done <<RR_OWED
$(owed_list_plan "$PV_PLAN" "$PV_REPO" 2>/dev/null)
RR_OWED
    RR_WAIVE="$(printf '%s\n%s\n' "$RR_WAIVE" "$(printf '%s\n' "$RR_SETTLE" | /usr/bin/grep '^waive:' | /usr/bin/grep -vx 'waive:regression')" | awk 'NF && !seen[$0]++')"
    while IFS= read -r key; do
      [ -n "$key" ] || continue
      q="${key#waive:}"
      line="$(proof_last_line "$PV_PLAN" review "$q" 2>/dev/null)"
      if [ "$(rr_proof_field "$line" result)" = fail ]; then why="failing at this head"; else why="not held at this head"; fi
      rr_add waive "$key" "waive $q" "-" "-" "The $q review, $why" waive withhold "waive the $q review" "hold the $q waiver"
    done <<RR_WAIVES
$RR_WAIVE
RR_WAIVES

    # ROWS: every matrix row, ruled or not as walls.sh rules it (rr_rows). Proved when discharged and ruled, and one whose
    # person's part is `confirmed` is one the user confirmed; waived when ruled with status waived. Every
    # other row is a decision: a discharged row whose person's part is `awaits` is the user's own check, to confirm
    # (approve <AC>) or waive; any other is waived or run, a T4 row's standing finding said in the gate's words. The
    # step a row is owed against is the run's (the reader's `step`), the plan's `current:` only where the log has none.
    RR_ACT=0; RR_ACP=0; RR_ACY=0; RR_ACW=0; RR_ACU=0; RR_ACA=0; RR_ACR=0; RR_ACC=0; RR_ACL=0; RR_MISS=""
    poker_fold_ask RR_ANS "$RR_AGAIN" "$PV_PLAN" reader_q_step; RR_CUR="$(printf '%s\n' "$RR_ANS" | sed -n 's/^n=//p')"
    if ! RR_ROWS="$(rr_rows "$PV_PLAN" "${RR_CUR:-$PV_CUR}" "$RR_HEAD")"; then
      die "REFUSED — the release approval card asks walls.sh for each matrix row's ruling, and $BIONIC_LIB/walls.sh cannot be loaded or the run's facts could not be read; nothing is written. Run again: bash ${HOOK_DIR}/session-poker.sh $RR_AGAIN"
      exit 2
    fi
    while IFS=$'\037' read -r ac tier st au ruled person reason; do
      [ -n "$ac" ] || continue
      RR_ACT=$((RR_ACT + 1))
      if [ "$ruled" = 1 ] && [ "$st" = discharged ]; then
        RR_ACP=$((RR_ACP + 1))
        [ "$person" != confirmed ] || RR_ACY=$((RR_ACY + 1))
        continue
      fi
      if [ "$ruled" = 1 ] && [ "$st" = waived ]; then RR_ACW=$((RR_ACW + 1)); continue; fi
      # A ROW OWED AT A LATER STEP IS NO DECISION: the step that proves it writes it, the close for a row owed at 9.
      case "$ruled" in owed:9) RR_ACC=$((RR_ACC + 1)); continue ;; owed:*) RR_ACL=$((RR_ACL + 1)); continue ;; esac
      RR_MISS="${RR_MISS:+$RR_MISS }$ac"
      if [ "$person" = awaits ] && [ "$st" = discharged ]; then
        RR_ACA=$((RR_ACA + 1))
        rr_add row "row:$ac" "approve $ac" "waive $ac" "a T4 criterion, the user's own check" \
          "$ac, your own check, not confirmed yet" confirm waive "confirm $ac" "waive $ac"
        continue
      fi
      if [ "$st" = discharged ]; then RR_ACU=$((RR_ACU + 1)); else RR_ACR=$((RR_ACR + 1)); fi
      why="$reason"
      if [ -z "$why" ]; then
        if [ "$st" != discharged ]; then why="not run on this release"
        elif [ "$tier" = T4 ] && [ "$au" != - ]; then why="the auditor's finding stands ($au)"
        else why="not confirmed by the auditor on this release"; fi
      fi
      rr_add row "row:$ac" "waive $ac" "-" "$why" "$ac, $why" waive "run it" "waive $ac" "run $ac"
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
      [ "$RR_ACC" -eq 0 ] || line="${line:+$line, }$RR_ACC owed by the close"
      [ "$RR_ACL" -eq 0 ] || line="${line:+$line, }$RR_ACL owed at a later step"
      if [ -z "$RR_MISS" ]; then RR_TACC="✅"; else RR_TACC="✖️"; fi
      RR_TACC="$RR_TACC acceptance — $RR_ACP of $(rr_plural "$RR_ACT" criterion criteria) proved${line:+; $line}"
    fi

    # FINDINGS: the disposition's one reading, one sentence each; a decision only when recommended against. A FINDING'S
    # STANDING WORD IS A FACT OF THE RUN: where the reader holds the finding, its `findings` answer gives the state (a
    # deferral carried; a move to fixed fixed once its row landed, open with that row before), and the question is
    # the reader's newest review proof citing its record. The disposition's own state stands for a finding the
    # reader holds no line of, a review's unlined flag.
    RR_FN=0; RR_FNF=0; RR_FNA=0; RR_FNC=0; RR_FLINES=""; RR_FROWS=""; RR_FIDS=""; RR_CARRY=""
    poker_fold_ask RR_ANS "$RR_AGAIN" "$PV_PLAN" reader_q_findings
    RR_RFIND="$(printf '%s\n' "$RR_ANS" | awk -F'|' "$_LINE_FIELDS_AWK"'
      NF > 1 { print line_kv("ref") "\t" line_kv("to") "\t" line_kv("row") }')"
    poker_fold_ask RR_ANS "$RR_AGAIN" "$PV_PLAN" reader_q_reviews
    RR_QOF="$(printf '%s\n' "$RR_ANS" | awk -F'|' "$_LINE_FIELDS_AWK"'
      line_kv("ev") == "proof" { print line_kv("evidence") "\t" line_kv("question") }')"
    # A PREVIEW OPENS NOTHING: the findings' reader is handed a ledger key no file can carry, so the person's
    # items it opens on any other run are left unopened here.
    if [ "$RR_PREVIEW" = yes ]; then
      RR_DISP="$( cd "$PV_REPO" && OWED_SID="preview/none" finding_disposition 2>&1 )"
    else
      RR_DISP="$( cd "$PV_REPO" && finding_disposition 2>&1 )"
    fi
    while IFS= read -r line; do
      case "$line" in "poker: finding "*) : ;; *) continue ;; esac
      line="${line#poker: }"
      fid="$(printf '%s' "$line" | awk '{ print $2 }')"; sev="$(printf '%s' "$line" | awk '{ print $3 }')"
      state="$(rr_field "$line" state)"; rows="$(rr_field "$line" row)"; ev="$(rr_field "$line" record)"
      stated="$(rr_field "$line" stated)"; ttl="$(rr_field "$line" title)"
      sent="${stated:-$ttl}"; [ "$sent" != - ] || sent="$ttl"; sent="${sent%.}"
      IFS='	' read -r _ to h <<< "$(printf '%s\n' "$RR_RFIND" | awk -F'\t' -v f="$fid" '$1 == f { l = $0 } END { print l }')"
      case "${to:-}" in
        deferred) state=deferred; rows="" ;;
        fixed) rows="${h:-$rows}"; case "$RR_LANDED_IDS" in *" ${h:-?} "*) state=fixed ;; *) state=open ;; esac ;;
      esac
      q="$(printf '%s\n' "$RR_QOF" | awk -F'\t' -v e="$ev" '$1 == e { q = $2 } END { print q }')"; num="${fid##*#}"
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

    # APPROVALS: every name an open row reads, release and merge first, each not yet given. A release approval the head
    # has moved past is put again: the advance to 8 refuses on it as on a missing one, and `card.sh early` settles that
    # refusal as this page's decision (`settles: approve:release`), so the user gives it at the new head, and the reply
    # writes a second line beside the first. Only the judge says the release is stale: its refusal, or, where the advance
    # refuses first on facts this page settles, its own test of the approved head (judge.sh `cur8_release_holds`). The merge is given with the
    # release as a pair, so beside a release put again it is put again too when its own newest line names another head
    # than this one (`proof_approved_head`, the head the approval was given at); a merge given at this head stands.
    RR_NAMES=""; RR_RELAGAIN=""
    RR_INTO="$(plan_integration_branch "$PV_PLAN")"
    for nm in release merge $(units_approval_names "$PV_PLAN" 2>/dev/null); do
      [ "$nm" != plan ] || continue
      case " $RR_NAMES " in *" $nm "*) continue ;; esac
      units_approval_names "$PV_PLAN" 2>/dev/null | /usr/bin/grep -qxF "$nm" || continue
      RR_NAMES="$RR_NAMES $nm"
      again=""
      if proof_approved "$PV_PLAN" "$nm"; then
        h="$(proof_approved_head "$PV_PLAN" "$nm" 2>/dev/null)" || h=""
        case "$nm" in
          release)
            case $'\n'"$RR_SETTLE"$'\n' in
              *$'\n'approve:release$'\n'*) RR_RELAGAIN=yes ;;
              *) { [ -n "$h" ] && ! cur8_release_holds "$h" "$RR_HEAD"; } || continue; RR_RELAGAIN=yes ;;
            esac ;;
          merge) [ -n "$RR_RELAGAIN" ] && [ "$h" != "$RR_HEAD" ] || continue ;;
          *) continue ;;
        esac
        again="again at this head${h:+: $(rr_since "$h")}"
      fi
      case "$nm" in
        release) line="Release${RR_REL:+ $RR_REL}${again:+ $again}" ;;
        merge) line="Merge${RR_INTO:+ into $RR_INTO}${again:+ $again}" ;;
        *) line="Approval $nm" ;;
      esac
      rr_add approve "approve:$nm" "approve $nm" "-" "-" "$line" approve withhold "$nm" "hold the $nm"
    done

    # THE MERGE WITHOUT A PASS AT THIS HEAD is the person's own decision, put beside the release and the merge while the
    # whole suite did not run green here and no word was given at this head, by the one rule the gate at 8 honours the
    # word on (lib/proof.sh `proof_merge_ask`, `facts_state`'s unproved): a floor covered or uncovered, never owed.
    # Waiting for the pass is recommended and taking the default records nothing, so only the person's own `merge`
    # writes the line. A floor the whole run left red draws no decision: the Tests line names its suites and their exit.
    # A plan that owes no whole run, or holds no proof of one, has no pass to wait for and is asked nothing here.
    RR_WHOLE="$(proof_whole_text "$PV_PLAN" "$PV_REPO" 2>/dev/null)"
    RR_REDS=""
    case "$RR_WHOLE" in
      none|'') : ;;
      *) if [ "$(proof_regression "$PV_PLAN")" != no ]; then
           line="$(proof_merge_ask "$PV_PLAN" "$PV_REPO" "$RR_HEAD" 2>/dev/null)"
           case $? in
             0) rr_add unproved approve:merge-unproved "-" "approve merge-unproved" "-" \
                  "Merge without a whole run at this head — $line" "wait for the pass" "merge without it" \
                  "wait for the pass" "merge without a whole run at this head" ;;
             2) RR_REDS="$line" ;;
           esac
         fi ;;
    esac

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
    # A MATRIX ROW NO THEME CAN READ refuses the page, preview or not, before anything is written: a row with no
    # serves: and no dotted id is in no theme's count, so the Goals block would print a theme short, `0 of N reached`
    # over criteria discharged. The Requirement cell of the criterion's Eval design row names it, and the page then reads it.
    RR_UNMAPPED="$(printf '%s\n' "$RR_GOALS" | awk -F'\t' '$1 == "mapping" && index($2, "not mapped: ") == 1 {
      n = split($3, a, " "); s = ""; for (i = 1; i <= n && i <= 5; i++) s = s (i > 1 ? ", " : "") a[i]
      if (n > 5) s = s " and " (n - 5) " more"
      print n "\t" s; exit }')"
    if [ -n "$RR_UNMAPPED" ]; then
      die "release-approval refused — ${RR_UNMAPPED%%	*} criteria map to no requirement (none named, and no dotted id): write each one's requirement in the Requirement cell of its row under ## Eval design (${RR_UNMAPPED#*	})"
      exit 1
    fi

    # THE REGRESSION is the full pass's state at the head, drawn from the one printer over the floor judge (lib/proof.sh
    # `proof_whole_text`), never worded here: green only where the whole suite ran green at this head, so a whole run
    # behind the head that later landings covered reads red with the landings since it counted.
    RR_TREG="$RR_WHOLE"
    case "$RR_TREG" in
      "green at "*) RR_TREG="✅ whole suite: $RR_TREG" ;;
      *) RR_TREG="✖️ whole suite: ${RR_TREG:-none}" ;;
    esac
    [ -z "$RR_REDS" ] || RR_TREG="$RR_TREG · $(proof_owed_needs "$RR_REDS")"

    # THE REVIEWS: each question's newest reading, by the role the rigor deals it, covered or failing as the judge
    # reads it at the head (lib/proof.sh `facts_reviews`, the one reading the situation report's count shares): a
    # failed reading its fix landings answered reads covered, naming them, and failing stays only while it is
    # uncovered. Only a newest reading that passed draws the pass mark. A plan the judge cannot deal has no coverage
    # to read, so its lines say the recorded result.
    RR_REVIEWS=""
    RR_COV="$(facts_reviews "$PV_PLAN" "$RR_HEAD" --landings 2>/dev/null)"
    poker_fold_ask RR_ANS "$RR_AGAIN" "$PV_PLAN" reader_q_header rigor; RR_RIGOR="$(printf '%s\n' "$RR_ANS" | sed -n 's/^rigor=//p')"
    for q in evidence adversarial structure; do
      role=critic
      [ "$q" != evidence ] || [ "$RR_RIGOR" != double ] || role=auditor
      line="$(proof_last_line "$PV_PLAN" review "$q" 2>/dev/null)"
      if [ -z "$line" ]; then RR_REVIEWS="${RR_REVIEWS}❔ $q — not read yet"$'\n'; continue; fi
      h="$(rr_proof_field "$line" head)"; r="$(rr_proof_field "$line" result)"
      behind="$(git -C "$PV_REPO" rev-list --count "$h..$RR_HEAD" 2>/dev/null)" || behind=""
      if [ "$h" = "$RR_HEAD" ] || [ "$behind" = 0 ]; then nm="$role at this head"
      elif [ -n "$behind" ]; then nm="$role at ${h:0:8}, $(rr_plural "$behind" commit commits) behind"
      else nm="$role at ${h:0:8}"; fi
      IFS=$'\t' read -r _ _ cst clands <<< "$(printf '%s\n' "$RR_COV" | awk -F'\t' -v q="$q" '$1 == q { print; exit }')"
      case "${clands:--}" in
        -) clands="" ;;
        *) clands="$(printf '%s' "$clands" | tr ',' '\n' | awk -F'@' 'NF == 2 { printf "%s%s", (n++ ? ", " : ""), ($1 == "-" ? "" : $1 " at ") substr($2, 1, 8) }')" ;;
      esac
      case "${cst:-}:$r" in
        failing:*) RR_REVIEWS="${RR_REVIEWS}✖️ $q — $nm, failing"$'\n' ;;
        # THE PASS MARK IS THE NEWEST READING'S PASS: the cover holds the range, never the result, so a covered reading
        # that flagged or failed says its result beside the cover and draws no pass mark.
        covered:pass) RR_REVIEWS="${RR_REVIEWS}✅ $q — $nm${clands:+, covered at this head by $clands}"$'\n' ;;
        covered:*) RR_REVIEWS="${RR_REVIEWS}➖ $q — $nm, result ${r:-none}, covered at this head${clands:+ by $clands}"$'\n' ;;
        uncovered:*) RR_REVIEWS="${RR_REVIEWS}➖ $q — $nm, not covered at this head"$'\n' ;;
        absent:*) RR_REVIEWS="${RR_REVIEWS}➖ $q — $nm, a review still owed at this head"$'\n' ;;
        :pass) RR_REVIEWS="${RR_REVIEWS}✅ $q — $nm"$'\n' ;;
        :fail) RR_REVIEWS="${RR_REVIEWS}✖️ $q — $nm, failing"$'\n' ;;
        *) RR_REVIEWS="${RR_REVIEWS}➖ $q — $nm, ${r:-no result}"$'\n' ;;
      esac
    done

    # THE HAND-HOLDS, from the last build landing (line.sh `hand_holds_window`'s start) to this render. The render's
    # own instant is the page's end and the replay line's `at=`: the page counts what was done before it, while
    # landing-report's window runs on to delivery, so acts after the card are counted there and not here.
    RR_AT="$(iso_now)"
    RR_ANS="$(hand_holds_window "$(_wt_proofs_path "$PV_REPO" "$PV_PLAN")" "$PV_REPO" "$PV_PLAN")" || poker_fold_unread "$RR_AGAIN"
    IFS=$'\t' read -r RR_HHS _ _ _ <<< "$RR_ANS"
    [ "${RR_HHS:--}" != - ] || RR_HHS=""
    RR_HH="$(hand_holds_report "$(_wt_proofs_path "$PV_REPO" "$PV_PLAN")" "$PV_REPO" "$PV_PLAN" ${RR_HHS:+--since "$RR_HHS"} --until "$RR_AT")" \
      || poker_fold_unread "$RR_AGAIN"
    # THE RUN SO FAR, the sheet's own line (`sitrep_so_far`): the reader's acts taken by hand and open asks over the
    # log this render reads, asked before the render opens anything, so the page and the sheet count at one log.
    RR_SOFAR="$(sitrep_so_far "$PV_PLAN")"

    # THE CAP ON TESTS, as the release check printed it: the line is read from the log of the newest check proof
    # (`sitrep_test_ratio`, the reader the situation report's waste line uses), so the page quotes the check and
    # counts nothing. A check that ran at an earlier head says which, and no check says nothing.
    RR_TR=""
    read -r _rr_t _rr_c _rr_h <<< "$(sitrep_test_ratio "$PV_PLAN" "$PV_REPO")"
    if [ -n "${_rr_c:-}" ]; then
      RR_TR="test-ratio: $_rr_t/$_rr_c"
      [ "${_rr_h:-}" = "$RR_HEAD" ] || RR_TR="$RR_TR at ${_rr_h:0:8}"
    fi

    # WHAT THE RELEASE CHANGES OF ITS OWN CHECK: the check's declared files (`release-check-files:`) that the range
    # from the last release (`release_base`, the release check's own start) to the head changes, read by the one
    # reading the hand landing's line uses (lib/worktree.sh `_wt_check_judge`), so the user approving the release
    # knows the check it passed was changed in it.
    RR_CHG=""
    line="$(config_value "$PV_REPO" release-check "" 2>/dev/null)"
    if [ -n "$line" ] && release_base "$PV_PLAN" "$PV_REPO" "$RR_HEAD"; then
      RR_CHG="$(_wt_check_judge "$PV_REPO" "$RB_BASE" "$RR_HEAD")" || RR_CHG=""
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
        approve:*|waive:*) OWED_ROOT="$PV_REPO" OWED_PLAN="$PV_PLAN" owed_open "$key" "${key%%:*}: ${key#*:}" \
          "poker: ${key#*:} is decision $((num + 1)) on the release approval card at $RR_H8" >/dev/null 2>&1 || : ;;
      esac
    done
    # A card with no decision still records its page while it carries a finding whose carry is still an open ask (the
    # reader's `asks`), so the reply that answers it rules the carry; one whose carries were all ruled writes nothing.
    RR_CARRY_OPEN=""
    poker_fold_ask RR_ANS "$RR_AGAIN" "$PV_PLAN" reader_q_asks; RR_OPEN_ASKS="$(printf '%s\n' "$RR_ANS" | sed -n 's/.*|key=\([^|]*\)|.*/\1/p')"
    while IFS= read -r fid; do
      [ -n "$fid" ] || continue
      case $'\n'"$RR_OPEN_ASKS"$'\n' in *$'\n'"$(carry_owed_key "$fid")"$'\n'*) RR_CARRY_OPEN=yes ;; esac
    done <<< "$RR_CARRY"
    { [ "$RR_N" -eq 0 ] && [ -z "$RR_CARRY_OPEN" ]; } || rr_record "$RR_TEXT"
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
        # A WAIVER HELD BACK IS ANSWERED NO: the register keeps the ask open and stores the answer, so every reader sees
        # it waits on the review's next run and not on the user.
        case "$RP_SIDE|$RP_KEY" in
          other\|waive:?*) declare -F owed_answer >/dev/null 2>&1 \
            && OWED_ROOT="$PV_REPO" OWED_PLAN="$PV_PLAN" owed_answer "$RP_KEY" no "review ${RP_KEY#waive:} re-run" >/dev/null 2>&1 ;;
        esac
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
    # finding-move closed it already), so the carry's ask on the run's register closes here, and so does a finding the
    # user answered carry with no row named, which waits on this card (lib/owed.sh `ask_waits_on`).
    if declare -F owed_close >/dev/null 2>&1 && declare -F carry_owed_key >/dev/null 2>&1; then
      sed -n 's/^carried: //p' "$RP_CARD" 2>/dev/null | while IFS= read -r RP_X; do
        [ -n "$RP_X" ] || continue
        OWED_ROOT="$PV_REPO" OWED_PLAN="$PV_PLAN" owed_close "$(carry_owed_key "$RP_X")" "release approval reply" >/dev/null 2>&1
        declare -F ask_waits_on >/dev/null 2>&1 && declare -F finding_owed_key >/dev/null 2>&1 || continue
        RP_FK="$(finding_owed_key "$RP_X")"
        [ "$(ask_waits_on "$RP_FK" "$PV_PLAN" "$PV_REPO")" = "event release card" ] \
          && OWED_ROOT="$PV_REPO" OWED_PLAN="$PV_PLAN" owed_close "$RP_FK" "release approval reply" >/dev/null 2>&1
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
  # `order lift` ends the open one. With a bound open run each is one order event in the run's log
  # (lib/proof.sh `proof_order_event`: act=given or lifted, said=<the words, of the order it ends for a
  # lift>), and the plan is left as it was. With no run bound it is one line of record/orders.log under
  # the docs root, made when absent, since there is no run's log to hold it:
  #
  #   order: given <ISO-UTC> "<words>"
  #   order: lifted <ISO-UTC> "<the words of the order it ends>"
  #
  # tests/run.sh asks lib/gate.sh `gate_order`, the one reader of both, and refuses every suite while an
  # order is open. A newer order replaces the open one; the newest fact decides.
  #
  # REFUSED (1), nothing written: words that hold a line break, or a `|` in a bound run (an event's field
  # cannot carry one), a lift with no open order, the log a link. (2): the order reader or writer cannot be
  # loaded, or the order cannot be written.
  poker_verb_order() {
    local sid mode=log root log open plan="" run line
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
      run="$(session_run "$root" "$sid")"
      case "$run" in 'bound-open '*) mode=plan; plan="${run#bound-open }" ;; esac
    fi
    if [ "$mode" = plan ]; then
      open="$(gate_order_plan "$plan")" || open=""
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
        die "REFUSED — no order is open$([ "$mode" = plan ] && printf ' in the run of %s' "$plan" || printf ' in %s' "$log"), so there is nothing to lift; nothing was written."
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
    case "$OR_WORDS" in *'|'*)
      die "REFUSED — an order's words are one field of the run's log, which cannot carry a |; nothing was written. run again: session-poker.sh order '<the words without it>'"
      exit 1 ;;
    esac
    declare -F proof_order_event >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh" >/dev/null 2>&1; }
    if ! declare -F proof_order_event >/dev/null 2>&1 \
       || ! proof_order_event "$plan" "$([ -n "$OR_LIFT" ] && echo lifted || echo given)" "$OR_WORDS"; then
      die "REFUSED — the order cannot be appended to the run's log of $plan (lib/proof.sh proof_order_event from $BIONIC_LIB); nothing was written. run again: session-poker.sh order"
      exit 2
    fi
    say "order — ${line#order: }, in the run's log of $plan; the plan is unchanged."
    exit 0
  }

  # THE PROMOTION. One durable record, an adr, a design or a requirement, copied into the project's tracked
  # home under its kind with a stable name (lib/roots.sh `promote_target`, which owns the destination and every
  # refusal). It reads no plan and writes none: a promotion is a copy of a record the project keeps, so the
  # project root of the working directory is its only operand beside the two it is given. The source is an
  # absolute path, else project-root-relative, else docs-root-relative, all read against the state home, which a
  # linked worktree shares. The copy is written under the top level of the checkout the verb runs in, the way a
  # part renders there, so a promotion run from a row's tree lands in that tree and never in the main checkout.
  # A second promotion of the same record lands at the same path and replaces it, so an amended record is
  # promoted again by the same call.
  # REFUSED (1), nothing copied: no such file, or anything promote_target refuses. REFUSED (2): no project root.
  poker_verb_promote() {
    local root top src to err
    root="$(cd "$(project_root "$PWD")" 2>/dev/null && pwd -P)"
    if [ -z "$root" ]; then
      die "REFUSED — cannot resolve the project root from the working directory. Nothing was copied."
      exit 2
    fi
    top="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" && top="$(cd "$top" 2>/dev/null && pwd -P)" || top=""
    [ -n "$top" ] || top="$root"
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
    if ! to="$(promote_target "$top" "$PR_KIND" "$src" 2>"$err")"; then
      die "REFUSED — $(sed 's/^promote: //' "$err" 2>/dev/null). Nothing was copied."
      rm -f "$err"
      exit 1
    fi
    rm -f "$err"
    if [ -f "$to" ] && cmp -s "$src" "$to"; then
      say "promote — ${to#"$top"/} already holds ${src#"$root"/}; nothing changed.$([ "$top" = "$root" ] || printf ' The tree is %s.' "$top")"
      exit 0
    fi
    if ! { mkdir -p "${to%/*}" && cp "$src" "$to.promote.$$" && mv -f "$to.promote.$$" "$to"; }; then
      rm -f "$to.promote.$$"
      die "REFUSED — cannot write $to. Nothing was copied."
      exit 2
    fi
    if [ "$top" = "$root" ]; then
      say "promote — ${src#"$root"/} is promoted to ${to#"$root"/}."
    else
      say "promote — ${src#"$root"/} is promoted to ${to#"$top"/} in $top."
    fi
    exit 0
  }
