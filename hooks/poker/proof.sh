# shellcheck shell=bash
# hooks/poker/proof.sh — the proof record: deferrals, findings, approvals, waivers, confirmations, the regression
# and the debt ledger (approve, accept, abandon, proof-add, waive, finding-move, release-check,
# regression-run, debt).
#
# A part of hooks/session-poker.sh, which sets every global and loads this file before any verb runs. A part
# defines functions only, and is never run by itself.

# ---------------------------------------------------------------- the deferral's sentence
#
# A DEFERRED FINDING'S ONE CHANGELOG SENTENCE. Registering a record appends a deferral
# event per finding the table defers (lib/proof.sh `proof_finding_deferrals`); the person's move to defer carries the
# sentence as its `stated=` field (`finding-move … defer '<words>' '<why>' '<sentence>'`). The sentence is folded to
# one line of single spaces (`deferral_fold`, lib/said.sh's `said_fold`, the one fold the changelog is read through as
# well), and a `\` or a `"` in it is written `\\` or `\"`. The other half
# of the debt is the changelog: `release-check` prints each deferral stated (the sentence is in `CHANGELOG.md`) or
# unstated.
deferral_fold() {  # <text> -> its white space and control characters folded to single spaces, trimmed: lib/said.sh's one fold
  declare -F said_fold >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/said.sh" ] && . "$BIONIC_LIB/said.sh"; }
  said_fold "$1"
}
# A PERSON'S MESSAGE QUOTED WHOLE is one field of the run's log only once its line breaks are gone, and lib/said.sh
# matches it through that same fold, so a verb taking the person's words folds a quote that carries a CR or LF before
# its shape check, which still refuses a `|`. A text with neither is printed as given; when the fold cannot be made (no
# jq) or leaves nothing, the text is printed as given, so the caller's line-break refusal still stands.
poker_one_line() {  # <text> -> the text, its line breaks folded by lib/said.sh's one fold
  local f
  case "${1:-}" in *$'\n'*|*$'\r'*) ;; *) printf '%s' "${1:-}"; return 0 ;; esac
  f="$(deferral_fold "$1")" && [ -n "$f" ] || f="$1"
  printf '%s' "$f"
}
deferral_escape() {  # <folded sentence> -> as the plan holds it: \ for a backslash, \" for a quote
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
# review_readings <plan> -> `<record><TAB><question><TAB><head>` per record a standing review proof names as its
# evidence, in the order the run first registered it, the question and head of its newest proof: the reader's
# `reviews` answer (payload/scripts/reader.sh), asked once per call, so a run whose review proofs its log alone
# holds is read as one whose plan holds them. The waivers that answer lists are no reading, and are left out.
# Prints nothing when the reader cannot be loaded or refuses the plan, and exits 2 then, or when the fold fails: no
# reading is no answer, so a waiver or a ruling over them is refused, never applied to none.
review_readings() {
  local r
  { [ -n "${_LINE_FIELDS_AWK:-}" ] || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; } || return 0
  r="$( { . "$BIONIC_LIB/reader.sh" >/dev/null 2>&1 && reader_main "$1" reviews; } 2>/dev/null )" || return 2
  printf '%s\n' "$r" | awk -F'|' "$_LINE_FIELDS_AWK"'
    line_kv("ev") == "proof" && line_kv("question") != "" && (e = line_kv("evidence")) != "" {
      if (!(e in q)) o[++n] = e
      q[e] = line_kv("question"); h[e] = line_kv("head")
    }
    END { for (i = 1; i <= n; i++) printf "%s\t%s\t%s\n", o[i], q[o[i]], h[o[i]] }'
}

# waive_owed_findings <plan> <repo> <question> -> always 0, prints nothing: the waiver of a question is the person's
# answer to every finding of its readings ("fix it, defer it, or waive <question>", the item `finding_disposition`
# opens), so it closes each open `finding:<record>#<n>` item of every reading the run registers under that question.
# The readings are `finding_disposition`'s own, `review_readings`.
waive_owed_findings() {  # [<readings, review_readings' answer read before the waiver was written>]
  local ev q pre key
  declare -F owed_list >/dev/null 2>&1 || return 0
  while IFS='	' read -r ev q _; do
    [ -n "$ev" ] && [ "$q" = "$3" ] || continue
    pre="$(finding_owed_key "$ev#")"
    for key in $(OWED_ROOT="$2" owed_list 2>/dev/null | cut -f1); do
      case "${key#"$pre"}" in "$key"|''|*[!0-9]*) continue ;; esac
      poker_owed_close "$2" "$key" "waive"
    done
  done <<< "${4-$(review_readings "$1")}"
  return 0
}

# proof_owed <open|close|answer> <key> <title, closer or answer> [<reply or event>] -> always 0, prints nothing: the item
# opened, closed or answered on the register of the run this verb writes (PV_PLAN), never a session file, whichever
# session runs the verb.
proof_owed() {
  declare -F owed_open >/dev/null 2>&1 || return 0
  case "$1" in
    open)   OWED_ROOT="$PV_REPO" OWED_PLAN="$PV_PLAN" owed_open "$2" "$3" "${4:-}" >/dev/null 2>&1 ;;
    close)  OWED_ROOT="$PV_REPO" OWED_PLAN="$PV_PLAN" owed_close "$2" "$3" >/dev/null 2>&1 ;;
    answer) declare -F owed_answer >/dev/null 2>&1 && OWED_ROOT="$PV_REPO" OWED_PLAN="$PV_PLAN" owed_answer "$2" "$3" "${4:-}" >/dev/null 2>&1 ;;
  esac
  return 0
}
# carry_owed_key <record>#<n> -> the register's key of a carry no person ruled: `finding_owed_key`'s identity under
# `carry:`, so the finding's own ruling item and its carry are two needs, never one key.
carry_owed_key() {
  local k; k="$(finding_owed_key "$1")"
  printf 'carry:%s' "${k#finding:}"
}

# release_deferrals <plan> <changelog file> -> a line `release-check — deferral <id>: stated|unstated`
# for each open deferral (a deferred finding whose effective priority is defer), in the order the run
# deferred them. Refuses nothing: the caller's exit is not read from it.
release_deferrals() {
  local plan="$1" cl="$2" DS_CL="" _id _s _r _p _t DS_ST DS_ANS
  [ -f "$cl" ] && DS_CL="$(deferral_fold "$(cat "$cl")")"
  proof_findings_owed "$plan" 2>/dev/null | while read -r _id _s _r _p _t; do
    [ "$_p" = defer ] || continue
    DS_ST="$(proof_finding_stated "$plan" "$_id")" || continue
    DS_ANS=unstated
    [ -n "$DS_ST" ] && case "$DS_CL" in *"$DS_ST"*) DS_ANS=stated ;; esac
    say "release-check — deferral $(clean "$_id"): $DS_ANS"
  done
}

# THE CRITIC'S VERDICTS, AS ITS EVIDENCE RECORD WRITES THEM. At single rigor no auditor is sent, so the evidence record
# is where each criterion's verdict and the wave's are learned, and its registration writes them into the matrix: no
# verdict is copied by hand. The grammar, outside fences:
#   the row verdicts  the record's first markdown table whose header names the columns `AC` and `verdict` (any case,
#                     other columns allowed, `| AC | verdict | why |` the usual shape); each row below its separator
#                     gives one criterion, spelled as the matrix table spells it, and its verdict: CONFIRMED, REFUTED,
#                     UNVERIFIABLE, or any words, written to the cell as given. The table ends at its first non-| line.
#   the wave verdict  exactly one flush-left `verdict: <VERDICT>[ — <coverage finding>]` line.
# proof_verdicts <record> -> `wave<TAB><the verdict: value>`, then `<AC><TAB><verdict>` per row, exit 0; or the
# refusal's sentence, exit 1. A row with an empty cell, a criterion given twice, a table with no row, no verdict: line
# or two of them is refused, so a half-read record cannot write half a matrix.
proof_verdicts() {
  local out
  out="$(awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^verdict:/ { nv++; w = $0; sub(/^verdict:/, "", w); if (nv == 1) wv = trim(w); next }
    /^[ \t]*\|/ {
      if (done) next
      n = split($0, c, "|")
      if (!hdr) {
        ca = 0; cv = 0
        for (j = 2; j < n; j++) { h = tolower(trim(c[j])); if (h == "ac" && !ca) ca = j; if (h == "verdict" && !cv) cv = j }
        if (ca && cv) hdr = 1
        next
      }
      if ($0 ~ /^[ \t]*\|[-|: \t]*$/) next
      a = trim(c[ca]); v = trim(c[cv])
      if (a == "" || v == "") { if (bad == "") bad = "empty\t" (a == "" ? "(no criterion)" : a); next }
      if (a in seen) { if (bad == "") bad = "twice\t" a; next }
      seen[a] = 1; rows = rows a "\t" v "\n"; nr++
      next
    }
    hdr && !done { done = 1 }
    END {
      if (!hdr) { print "E\tnotable"; exit }
      if (bad != "") { print "E\t" bad; exit }
      if (!nr) { print "E\tnorows"; exit }
      if (nv == 0 || wv == "") { print "E\tnowave"; exit }
      if (nv > 1) { print "E\twavetwice\t" nv; exit }
      printf "wave\t%s\n%s", wv, rows
    }' "$1" 2>/dev/null)"
  case "$out" in
    E$'\t'notable*) printf 'the evidence record %s carries no row-verdict table: a markdown table whose header row names the columns AC and verdict, one row per criterion' "$1"; return 1 ;;
    E$'\t'empty$'\t'*) printf 'the evidence record %s gives %s an empty cell in its row-verdict table; give each row its criterion and its verdict' "$1" "${out##*$'\t'}"; return 1 ;;
    E$'\t'twice$'\t'*) printf 'the evidence record %s gives %s twice in its row-verdict table; give each criterion one verdict' "$1" "${out##*$'\t'}"; return 1 ;;
    E$'\t'norows*) printf 'the evidence record %s has a verdict table, its header naming AC and verdict, with no row; give one row per criterion' "$1"; return 1 ;;
    E$'\t'nowave*) printf 'the evidence record %s carries no verdict: line; write the wave verdict on one flush-left line, verdict: <VERDICT> — <coverage finding>' "$1"; return 1 ;;
    E$'\t'wavetwice$'\t'*) printf 'the evidence record %s gives %s verdict: lines; the wave has one verdict, so keep the line the reviewer meant' "$1" "${out##*$'\t'}"; return 1 ;;
    E*|'') printf 'the evidence record %s cannot be read for its verdicts' "$1"; return 1 ;;
  esac
  printf '%s\n' "$out"
}

# THE WALK'S HEAD. A walk reads cards at one head; a record that names it on a flush-left `head: <sha>` line, outside
# fences, is held to it, and the head must be a commit on the working branch's history, as a review's range end is.
# A record that names none read the working head, which is the head the proof names.
# walk_head <record> <repository> <working head> -> the 40-hex head; exit 1 printing the refusal's sentence.
walk_head() {
  local h hh
  h="$(awk '/^[ \t]*```/ { f = !f; next } !f && /^head:[ \t]/ { sub(/^head:[ \t]+/, ""); sub(/[ \t].*$/, ""); print; exit }' "$1" 2>/dev/null)"
  if [ -z "$h" ]; then printf '%s' "$3"; return 0; fi
  hh=""
  case "$h" in *[!0-9a-fA-F]*) : ;; ?????*) hh="$(git -C "$2" rev-parse --verify -q "$h^{commit}" 2>/dev/null)" ;; esac
  if [ -z "$hh" ] || ! git -C "$2" merge-base --is-ancestor "$hh" "$3" 2>/dev/null; then
    printf 'the walk record %s says head: %s, which is no commit on the working branch (at %s); write the head the walk read, or no head: line for the working head' \
      "$1" "$h" "${3:0:12}"
    return 1
  fi
  printf '%s' "$hh"
}

# THE WALK DISCHARGES WHAT IT CONFIRMS, AND A RUN HAS ONE WALK RECORD THAT ONLY GROWS. Each row of the walk's verdict
# table (proof_verdicts output on stdin) must name a criterion the plan names (lib/reader.sh `reader_criteria`); a
# CONFIRMED row is one proof naming the criterion, the record as its evidence, the shape the cell answer reads as
# discharged with no read of its own; any other verdict leaves the criterion
# as it stands. The record must hold a row for every criterion whose standing proof names a walk's record (the run's
# walk proofs, at any head), so the record the walk gate reads is the one every walked criterion names: a later record
# that leaves one out would take the walk from under it. The standing facts are read before the new walk is pending,
# since a walk at the same head replaces the one before it in the fold.
# walk_settle <plan> <evidence> < verdicts -> sets WALK_DONE and WALK_LEFT (space-joined ids) and WALK_WAVE; exit 1 with
# the refusal's sentence in WALK_WHY. It runs in the caller's shell, never a command substitution, so the ids it sets
# reach the caller.
walk_settle() {
  local plan="$1" ev="$2" ac v known facts walked named=" " left=""
  WALK_DONE=""; WALK_LEFT=""; WALK_WAVE=""; WALK_WHY=""
  _proof_reader_load && known="$(reader_criteria "$plan" 2>/dev/null)" || known=""
  proof_facts_at "$(proof_run_plan "$plan")" || { WALK_WHY="the run's facts cannot be read, so the standing walk cannot be judged"; return 1; }
  walked="$(_proof_facts_awk -F'|' "$(proof_fact_awk)"'ev() == "proof" { k = line_kv("kind"); e = line_kv("evidence"); a = line_kv("ac")
      if (k == "walk") w[e] = 1; else if (k == "" && a != "") by[a] = e }
    END { for (a in by) if (by[a] in w) print a }')"
  while IFS='	' read -r ac v; do
    [ -n "$ac" ] || continue
    if [ "$ac" = wave ]; then WALK_WAVE="$v"; continue; fi
    case $'\n'"$known"$'\n' in
      *$'\n'"$ac"$'\n'*) : ;;
      *) WALK_WHY="the walk record gives a verdict for $ac, and the plan names no criterion $ac; give verdicts for the criteria as the plan spells them"
         return 1 ;;
    esac
    named="$named$ac "
    if [ "$v" = CONFIRMED ]; then WALK_DONE="${WALK_DONE:+$WALK_DONE }$ac"; else WALK_LEFT="${WALK_LEFT:+$WALK_LEFT }$ac"; fi
  done
  for ac in $walked; do case "$named" in *" $ac "*) : ;; *) left="${left:+$left, }$ac" ;; esac; done
  if [ -n "$left" ]; then
    WALK_WHY="the walk record $ev leaves out $left, which the standing walk confirms; a run has one walk record and it only grows: put each such criterion's row in the walk's own record and register the whole record again"
    return 1
  fi
  return 0
}

# THE WALK'S REGISTRATION: the record read as the critic's (proof_verdicts), its head (walk_head) and the criteria it
# discharges (walk_settle), with its proof, one `proof kind=walk` event, pending in every read that follows, and the
# criteria's proofs appended by `walk_append` once nothing is left to refuse. The plan is not written. proof-add walk
# runs it; the tick's landing of a record row lands the walk row on the proof it leaves.
# walk_register <plan> <record real path> <record docs-relative> <working head> <repository> -> 0 with WALK_HEAD,
# WALK_N and walk_settle's ids set; 1 with the refusal's sentence in WALK_WHY.
walk_register() {
  local plan="$1" real="$2" rel="$3" v
  WALK_WHY=""; WALK_HEAD=""; WALK_N=0; WALK_PLAN="$plan"; WALK_REL="$rel"
  if ! v="$(proof_verdicts "$real")"; then
    WALK_WHY="$v; a walk record carries the critic's shape, a | AC | verdict | why | table and one verdict: line"
    return 1
  fi
  if ! WALK_HEAD="$(walk_head "$real" "$5" "$4")"; then WALK_WHY="$WALK_HEAD"; WALK_HEAD=""; return 1; fi
  walk_settle "$plan" "$rel" <<< "$v" || return 1
  WALK_EV=("kind=walk" "head=$WALK_HEAD" "evidence=$rel")
  [ -z "${PF_ENVS:-}" ] || WALK_EV+=("environments=$PF_ENVS")
  proof_pending "${WALK_EV[@]}" || { WALK_WHY="the walk record's path $rel holds a | or a line break, which the run's log cannot hold"; return 1; }
  WALK_N="$(printf '%s\n' $WALK_DONE | awk 'NF { n++ } END { print n + 0 }')"
  return 0
}
# walk_append -> the walk's proof, then one proof per criterion it confirms, appended to the run's log by the proof
# library's one writer; 1 when the walk's own proof could not be.
walk_append() {
  local ac
  if ! proof_event "$WALK_PLAN" "${WALK_EV[@]}"; then
    die "REFUSED — the walk proof at ${WALK_HEAD:0:12} could not be appended to the run's log of $WALK_PLAN; the plan is unchanged."
    return 1
  fi
  for ac in $WALK_DONE; do
    proof_event "$WALK_PLAN" "ac=$ac" "evidence=$WALK_REL" \
      || say "the walk is registered, but the proof of $ac could not be appended to the run's log: register the walk again."
  done
  proof_pending
}
# THE WALK'S ACT IS RECORDED, AND IS NO HAND-HOLD: one `ev=walk` line naming the record and how many criteria it
# discharged, appended once the proofs are in. The hand-holds fold reads this line as nothing: the walk's verdicts are
# a reader's, registered as the critic's are.
walk_recorded() {  # <plan> <record docs-relative>
  { declare -F line_event >/dev/null 2>&1 || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; } \
    && line_event "$1" walk "record=$2" "discharged=${WALK_N:-0}" >/dev/null 2>&1 \
    || say "the walk is registered, but the ev=walk line could not be appended to the landing record."
}
walk_said() {  # <record docs-relative> -> what the registration discharged, one line
  printf 'the walk discharged %s (%s); left as they stood: %s; record: %s; verdict: %s' \
    "${WALK_DONE:-no criterion}" "${WALK_N:-0}" "${WALK_LEFT:-none}" "$1" "$WALK_WAVE"
}

# ONE WHOLE RUN AT A HEAD, ONE READER FOR ITS TWO ASKERS: the tick, before it starts one, and regression-run's rule 3.
# whole_run_at_head <docs> <wave> <head> <checkout> [<command>] -> rc 0 when the head has its whole run or one is
# running: WRA_LOG the docs-relative path of a regression-run log at <head> (of <command> alone when one is named, its
# line 2), else, WRA_LOG empty, an open whole request at the gate for <checkout> (lib/gate.sh `gate_whole_open`), since
# a running whole run has written no log yet. rc 1 when neither holds.
whole_run_at_head() {
  local l
  WRA_LOG=""
  for l in "$1/record/$2/regression-run-$3"*.log; do
    [ -f "$l" ] || continue
    [ -z "${5:-}" ] || [ "$(sed -n 2p "$l" 2>/dev/null)" = "command: $5" ] || continue
    WRA_LOG="${l#"$1"/}"; return 0
  done
  declare -F gate_whole_open >/dev/null 2>&1 && gate_whole_open "$4"
}

  # THE APPROVAL. A person's approval is one event in the run's log, appended by its one writer (lib/proof.sh
  # `proof_approval_event`) and never written into the plan, so the plan's bytes are the same before and after and no
  # copy of it is judged: an approval can only let the gate admit more, never refuse.
  #
  #   approval  key=<name> by=<who> [head=<40-hex>] said=<the reply> [why=<why>]
  #
  # <who> is the project's git user name, the reply the user's own words; each is one field of the log, so a `|` is
  # refused and the reply's line breaks are folded away (`poker_one_line`). Four kinds of name:
  #   plan         the plan's approval at Step 3, keyed step3; given once, a
  #                placeholder refused. Its instant is the one the plan's and the step cards' asks close at: a step card
  #                left open until a later card or the Stop closed it would read as a stop the run made after its approval.
  #   step0 step1 step2  the approval of the step before the plan's that the commit gate at 15 asks at Steps 1, 2 and 3,
  #                under the key it asks; given once, in the user's words, a placeholder refused, and its own ask closed
  #                at its instant. No order among them: the gate asks each only at the step after it.
  #   a criterion  a person's confirmation of a criterion whose check is theirs, admitted only where the reader's cells
  #                give it tier T4 (any other tier is refused, naming it); the reader reads it as that criterion's
  #                confirmation.
  #   any other    a name an open row reads as `approval:<name>` (units.sh `units_approval_names`, exact, case kept), and
  #                merge-unproved where there is a release to approve: a name no row reads would be recorded while the
  #                row it was meant for waits. It is recorded once at a head: given again only once the working head
  #                (lib/proof.sh `proof_branch_head`) moved past the one the standing approval names, so the newest is
  #                read. An approval of a decision D<n> is also its ruling, by the one ruling writer (sitrep.sh
  #                `decisions_rule`), before the approval's own ask closes; a ruling already in the ledger stands beside it.
  # Every kind is recorded only on words lib/said.sh `user_said` finds in a prompt the person typed in a session the run
  # recorded; nothing is appended on a miss.
  poker_verb_approve() {
    # Whether an approval already stands is read from the run's log, never the kept facts (lib/proof.sh `_PROOF_FRESH`).
    local _PROOF_FRESH=1
    AP_REPLY="$(poker_one_line "$AP_REPLY")"
    case "$AP_REPLY$AP_WHY" in
      *$'\n'*|*$'\r'*|*'|'*)
        die "REFUSED — an approval is one field of the run's log, and the reply carries a line break or a '|'; give it without one. Nothing was appended."
        exit 1 ;;
    esac
    plan_verb_open approve
    AP_WHO="$(git -C "$PV_REPO" config user.name 2>/dev/null)"
    if [ -z "$AP_WHO" ] || ! plan_verb_value_ok "$AP_WHO"; then
      die "REFUSED — the project has no usable git user name (git config user.name) to record as the approver; nothing was appended."
      exit 1
    fi
    AP_KEY="$AP_NAME"; AP_HEAD=""; AP_AT=""
    AP_CELLS="$(_proof_ask "$PV_PLAN" reader_cells "$PV_PLAN" 2>/dev/null)"; AP_RC=$?
    if [ "$AP_RC" -gt 1 ]; then
      die "REFUSED — the run's facts could not be read, so whether $AP_NAME is a criterion is not known; nothing was appended. run again: session-poker.sh approve $AP_NAME '<reply>'"
      exit 2
    fi
    AP_TIER="$(printf '%s\n' "$AP_CELLS" | awk -F'\037' -v c="$AP_NAME" '$1 == c { print ($4 == "" ? "-" : $4); exit }')"
    case "$AP_NAME" in plan|step0|step1|step2)
      # The gate's own placeholder test, asked of its library in a subshell as close-out asks it.
      ( . "$BIONIC_LIB/walls.sh" >/dev/null 2>&1 && declare -F is_placeholder_value >/dev/null 2>&1 || exit 9
        is_placeholder_value "$AP_REPLY" ); AP_RC=$?
      case "$AP_RC" in
        0) die "REFUSED — '$AP_REPLY' is a placeholder, not the user's reply; nothing was appended. Give their words verbatim: session-poker.sh approve $AP_NAME '<the user's reply>'"; exit 1 ;;
        9) die "REFUSED — whether the reply is a placeholder is read by lib/walls.sh, which cannot be loaded from $BIONIC_LIB; nothing was appended. run again: session-poker.sh approve $AP_NAME '<the user's reply>'"; exit 2 ;;
      esac ;;
    esac
    if [ "$AP_NAME" = plan ]; then
      AP_KEY=step3
      if proof_approved "$PV_PLAN" step3; then
        die "REFUSED — the run of $PV_PLAN already holds the plan's approval. An approval is recorded once; nothing was appended."
        exit 1
      fi
      AP_AT="$(owed_now 2>/dev/null)" || AP_AT=""
    elif [ "$AP_NAME" = step0 ] || [ "$AP_NAME" = step1 ] || [ "$AP_NAME" = step2 ]; then
      if proof_approved "$PV_PLAN" "$AP_NAME"; then
        die "REFUSED — the run of $PV_PLAN already holds the approval $AP_NAME. An approval is recorded once; nothing was appended. Fix: none; it stands, and the gate reads it at Step $(( ${AP_NAME#step} + 1 ))."
        exit 1
      fi
      AP_AT="$(owed_now 2>/dev/null)" || AP_AT=""
    elif [ -n "$AP_TIER" ]; then
      if [ "$AP_TIER" != T4 ]; then
        die "REFUSED — $AP_NAME is a $AP_TIER criterion, and only a T4 criterion's check is the user's own to confirm; the auditor or a waiver rules it. Nothing was appended."
        exit 1
      fi
    else
      AP_READ="$(units_approval_names "$PV_PLAN" | /usr/bin/grep -v '^plan$' | tr '\n' ' ' | sed 's/ $//')"
      case " $AP_READ " in *" release "*) AP_READ="$AP_READ merge-unproved" ;; esac
      case " $AP_READ " in
        *" $AP_NAME "*) : ;;
        *)
          die "REFUSED — no row in $PV_PLAN reads approval:$AP_NAME, so recording it would satisfy nothing; the rows read: ${AP_READ:-(no named approval)}. Approve one of those names exactly; nothing was appended."
          exit 1 ;;
      esac
      AP_HEAD="$(proof_branch_head "$PV_PLAN" "$PV_REPO" 2>/dev/null)" || AP_HEAD=""
      case "$AP_HEAD" in *[!0-9a-f]*|'') AP_HEAD="" ;; esac
      if proof_approved "$PV_PLAN" "$AP_NAME"; then
        AP_WAS="$(proof_approved_head "$PV_PLAN" "$AP_NAME" 2>/dev/null)" || AP_WAS=""
        if [ -z "$AP_HEAD" ] || [ "$AP_WAS" = "$AP_HEAD" ]; then
          die "REFUSED — the run of $PV_PLAN already holds the approval $AP_NAME. An approval is recorded once at a head, and ${AP_HEAD:+the working head ${AP_HEAD:0:12} is the one it names}${AP_HEAD:-the plan names no working-branch head to give it again at}; nothing was appended."
          exit 1
        fi
      fi
    fi
    # EVERY APPROVAL IS THE PERSON'S TYPED WORD, whatever it names: held to lib/said.sh `user_said` as a reply to the release
    # card, a waiver and a move are, so an agent cannot record one alone and a prompt a program sent (no human origin) is
    # none. Asked last, so a reply refused for its shape or its name is refused for that.
    if ! declare -F user_said >/dev/null 2>&1 && [ -f "$BIONIC_LIB/said.sh" ]; then . "$BIONIC_LIB/said.sh"; fi
    if ! declare -F user_said >/dev/null 2>&1; then
      die "REFUSED — what the user typed is read by lib/said.sh, which cannot be loaded from $BIONIC_LIB; nothing was appended."
      exit 2
    fi
    # A SHORT WORD AFTER ITS ASK. The person often answers an ask with one word and goes on ("approved — and …"). Too
    # short as the rule with no instant reads it (rc 3), it is asked again with the instant the ask's open round names
    # in the run's log (lib/owed.sh `owed_rounds`): typed after the ask was opened, the word is theirs on it. A whole
    # prompt stays their word as it was, and a name with no open ask keeps the rule with none.
    user_said "$AP_REPLY" "$PV_PLAN"; AP_SAID=$?
    AP_AFTER=""
    if [ "$AP_SAID" -eq 3 ] && declare -F owed_rounds >/dev/null 2>&1 && declare -F owed_key >/dev/null 2>&1; then
      AP_OK="$(owed_key "approve:$AP_NAME" 2>/dev/null)" || AP_OK=""
      [ -z "$AP_OK" ] || AP_AFTER="$(owed_rounds "${AP_OK//./\\.}" "$PV_PLAN" "$PV_REPO" 2>/dev/null \
        | awk -F'\t' '$3 == "open" { a = $4 } END { print a }')"
    fi
    case "$AP_AFTER" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;; *) AP_AFTER="" ;; esac
    [ -z "$AP_AFTER" ] || { user_said "$AP_REPLY" "$PV_PLAN" "$AP_AFTER"; AP_SAID=$?; }
    AP_ACT="an approval"; [ -z "$AP_TIER" ] || AP_ACT="a confirmation"
    [ "$AP_SAID" -eq 0 ] || { said_refuse "$AP_SAID" "$(said_fold "$AP_REPLY")" "$AP_ACT"; exit 1; }
    if ! LOG_AT="$AP_AT" proof_approval_event "$PV_PLAN" "$AP_KEY" "by=$AP_WHO" ${AP_HEAD:+"head=$AP_HEAD"} "said=$AP_REPLY" ${AP_WHY:+"why=$AP_WHY"}; then
      die "REFUSED — the approval $AP_NAME could not be appended to the run's log of $PV_PLAN (no record directory beside the plan, or the log cannot be written)."
      exit 2
    fi
    AP_RC=-; AP_RULED=""
    case "$AP_NAME" in
      plan)
        poker_owed_close "$PV_REPO" "approve:plan" "approve"
        if declare -F owed_close >/dev/null 2>&1; then
          for AP_K in approve:step0 approve:step1 approve:step2 approve:step3; do
            OWED_ROOT="$PV_REPO" OWED_PLAN="$PV_PLAN" owed_close "$AP_K" "approve plan" "${AP_AT:-}" >/dev/null 2>&1
          done
        fi
        say "approve — plan: approved by $AP_WHO, appended to the run's log of $PV_PLAN, which is unchanged. The commit gate reads it from Step 4."
        exit 0 ;;
      step[012])
        if declare -F owed_close >/dev/null 2>&1; then
          OWED_ROOT="$PV_REPO" OWED_PLAN="$PV_PLAN" owed_close "approve:$AP_NAME" "approve $AP_NAME" "${AP_AT:-}" >/dev/null 2>&1
        fi
        say "approve — $AP_NAME: approved by $AP_WHO, appended to the run's log of $PV_PLAN, which is unchanged. The commit gate reads it at Step $(( ${AP_NAME#step} + 1 ))."
        exit 0 ;;
      D[1-9]*) case "${AP_NAME#D}" in
          *[!0-9]*) : ;;
          *) AP_RULED="$(decisions_rule "$PV_PLAN" "$PV_REPO" "$AP_NAME" "$AP_REPLY" 2>&1)"; AP_RC=$? ;;
        esac ;;
    esac
    poker_owed_close "$PV_REPO" "approve:$AP_NAME" "approve"
    say "approve — $AP_NAME: approved by $AP_WHO, appended to the run's log of $PV_PLAN, which is unchanged."
    case "$AP_RC" in
      -) : ;;
      0) printf '%s\n' "$AP_RULED" ;;
      3) say "approve — $AP_NAME: the design ledger already rules it; that ruling stands beside the approval." ;;
      *) die "approve — $AP_NAME is approved in the run's log, but its ruling is not in the design ledger: ${AP_RULED#poker: }; rule it with: bash ${HOOK_DIR}/session-poker.sh decisions rule $AP_NAME '<the reply>'."
         exit 1 ;;
    esac
    exit 0
  }

  # THE PERSON'S WORD ON A CHANGED RUN. A run whose plan or log no longer matches its seal (lib/seal.sh) admits no
  # commit until the person rules, by one of two verbs, each on words they typed (lib/said.sh `user_said`):
  #   accept '<their words>'   the run as it now stands is theirs. One approval line, `key=seal`, names the words, the
  #                            session that typed them and what was accepted (`what=` and `how=`, as the seal names
  #                            the change); the ask the change opened is closed; then the run is sealed again, clean.
  #                            A run that matches its seal has nothing to accept, and one whose plan is gone cannot be
  #                            sealed: its plan is put back, or the run is abandoned.
  #   abandon '<their words>'  the run ends. One abandon line, the type the reader reads as abandoned, names the words
  #                            and the session; the ask is closed and the seal removed. Any open run the session is
  #                            bound to, changed or not; with its plan gone the line goes to the log the seal names.
  # WHOSE WORDS COUNT. A changed log can hold a bind line no binding act wrote, so the run's sessions read are those
  # the log bound as it was last sealed: the reader reads the log's vouched bytes (`seal_vouched`) from a scratch copy
  # beside a stub of the plan, and lib/said.sh is handed them in SAID_BOUND. When those bytes no longer stand, no
  # session of the plan is read, and the words must stand in this session's own transcript. The run is the one the
  # session's binding names (lib/run.sh `session_plan`), which outlives a plan that is gone.
  seal_word_open() {  # <verb> -> SW_ROOT SW_PLAN SW_LOG SW_SEAL SW_WHO, or the refusal and its exit
    local sid rc
    case "$SW_WORDS" in *$'\n'*|*$'\r'*|*'|'*)
      die "REFUSED — the words are one field of the run's log, and they carry a line break or a '|'; nothing was written. Fix: give them without one."
      exit 1 ;;
    esac
    sid="$(session_id)" || sid=""
    SW_ROOT="$(cd "$(project_root "$PWD")" 2>/dev/null && pwd -P)"
    SW_PLAN=""; [ -z "$sid" ] || [ -z "$SW_ROOT" ] || SW_PLAN="$(session_plan "$SW_ROOT" "$sid" 2>/dev/null)" || SW_PLAN=""
    if [ -z "$SW_PLAN" ]; then
      die "REFUSED — this session (${sid:-no session key}) is bound to no run, so there is none to $1; nothing was written. Fix: run it in the session bound to the run."
      exit 1
    fi
    if ! { declare -F seal_vouched >/dev/null 2>&1 || . "$BIONIC_LIB/seal.sh"; } 2>/dev/null || ! _proof_event_load \
       || ! { declare -F user_said >/dev/null 2>&1 || . "$BIONIC_LIB/said.sh"; } 2>/dev/null; then
      die "REFUSED — the seal, lib/reader.sh, the appender or lib/said.sh cannot be loaded from $BIONIC_LIB; nothing was written. Fix: reinstall the plugin."
      exit 2
    fi
    seal_verify "$SW_PLAN" >/dev/null; rc=$?
    SW_SEAL="$SEAL_LINE"; SW_LOG="$SEAL_LOG"
    if [ "$rc" -eq 75 ]; then
      die "REFUSED — the run's seal was held by another writer past the wait; nothing was written. run again: the same call."
      exit 75
    fi
    [ -n "$SW_LOG" ] || SW_LOG="$(reader_log "$SW_PLAN" 2>/dev/null)" || SW_LOG=""
    SW_WHO="$(git -C "$SW_ROOT" config user.name 2>/dev/null)"
    if [ -z "$SW_WHO" ] || ! plan_verb_value_ok "$SW_WHO"; then
      die "REFUSED — the project has no usable git user name to record as the one who ruled; nothing was written. Fix: git config user.name '<name>'."
      exit 1
    fi
  }
  seal_word_said() {  # <act> -> 0 when the words stand in a session the sealed log binds, or this one; else the refusal, exit 1
    local tmp stub rec ans rc
    SAID_BOUND=""
    tmp="$(mktemp -d 2>/dev/null)" || tmp=""
    if [ -n "$tmp" ]; then
      stub="$tmp/plans/${SW_PLAN##*/}"; mkdir -p "$tmp/plans" && : > "$stub"
      # A fold that fails, like bytes that no longer stand, binds no session: the words must then be this session's.
      ans=""
      rec="$(reader_log "$stub" 2>/dev/null)" && mkdir -p "${rec%/*}" && seal_vouched "$SW_PLAN" > "$rec" \
        && { ans="$(reader_main "$stub" sessions 2>/dev/null)" || ans=""; }
      SAID_BOUND="$(printf '%s\n' "$ans" | awk -F'|' '{ for (i = 2; i <= NF; i++) if (index($i, "session=") == 1) printf "%s ", substr($i, 9) }')"
      rm -rf "$tmp"
    fi
    user_said "$SW_WORDS" "$SW_PLAN"; rc=$?
    unset SAID_BOUND
    [ "$rc" -eq 0 ] || { said_refuse "$rc" "$(said_fold "$SW_WORDS")" "$1"; exit 1; }
  }
  poker_verb_accept() {
    local rc
    seal_word_open accept
    case "$SW_SEAL" in
      changed*) ;;
      *) die "REFUSED — the run of $SW_PLAN matches its seal (${SW_SEAL:-none}), so there is no change to accept; nothing was written. Fix: none; commit as the run stands."
         exit 1 ;;
    esac
    if [ ! -f "$SW_PLAN" ]; then
      die "REFUSED — the run's plan $SW_PLAN is gone, and a run with no plan cannot be sealed again; nothing was written. Fix: put the plan back, or end the run: session-poker.sh abandon '<their words>'."
      exit 1
    fi
    seal_word_said "an acceptance"
    SW_W="${SW_SEAL#*what=}"
    if ! proof_approval_event "$SW_PLAN" seal "by=$SW_WHO" "said=$SW_WORDS" "session=$SAID_SESSION" "what=${SW_W%% *}" "how=${SW_SEAL##*how=}"; then
      die "REFUSED — the acceptance could not be written to the run's log $SW_LOG; the run stays changed. run again: session-poker.sh accept '<their words>'."
      exit 2
    fi
    declare -F owed_close >/dev/null 2>&1 && OWED_ROOT="$SW_ROOT" OWED_PLAN="$SW_PLAN" owed_close seal:changed accept >/dev/null 2>&1
    seal_write --vouch run "$SW_PLAN" "$SW_LOG"; rc=$?
    if [ "$rc" -ne 0 ]; then
      die "REFUSED — the acceptance is in the run's log, but the run could not be sealed again (exit $rc). run again: session-poker.sh accept '<their words>'."
      exit 2
    fi
    say "accept — the run of $SW_PLAN is sealed again as it stands, on the word of $SW_WHO in session $SAID_SESSION; it accepted the $SW_W ${SW_SEAL##*how=}."
    exit 0
  }
  poker_verb_abandon() {
    local rc=0
    seal_word_open abandon
    [ ! -f "$SW_PLAN" ] || run_open "$SW_PLAN" || rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$SW_LOG" ]; then
      die "REFUSED — the run of $SW_PLAN is not open (or has no log to write to), so there is nothing to abandon; nothing was written. Fix: none; a closed run stays closed."
      exit 1
    fi
    seal_word_said "an abandonment"
    declare -F owed_close >/dev/null 2>&1 && OWED_ROOT="$SW_ROOT" OWED_PLAN="$SW_PLAN" owed_close seal:changed abandon >/dev/null 2>&1
    if ! RUN_LOG="$SW_LOG" log_append abandon "by=$SW_WHO" "said=$SW_WORDS" "session=$SAID_SESSION"; then
      die "REFUSED — the abandonment could not be written to the run's log $SW_LOG; the run is open. run again: session-poker.sh abandon '<their words>'."
      exit 2
    fi
    seal_remove "$SW_PLAN"; rc=$?
    if [ "$rc" -eq 75 ]; then
      die "REFUSED — the run is abandoned in its log, but its seal was held past the wait and still stands. run again: session-poker.sh abandon '<their words>'."
      exit 75
    fi
    say "abandon — the run of $SW_PLAN is ended on the word of $SW_WHO in session $SAID_SESSION; its seal is removed."
    exit 0
  }

  # THE PROOF VERB (wave-26 T4; REQ-3 AC-3.2, D5). Nothing recorded which code state a test pass
  # or a review read, so the same code was proved again and again. A proof is one `proof` event in
  # the run's log, `kind= head= evidence=` (payload/scripts/lib/proof.sh owns its shape and its
  # reader, `proof_last`), and what is
  # unproved is the difference since the head it names. The head is the one the evidence attests
  # (its run header or its reviewed: range, held against the working branch's ref; T14, wave-36 T12),
  # never an operand. The verb never writes the plan; every refusal below names its fix. proof.sh is loaded here, for this verb alone, as brief.sh is for task-add and amend:
  # the tick never reads it, so it is not one of the libraries every verb needs.
  # pf_append -> the proof the verb registers (PF_EV), appended to the run's log by the proof library's one writer once
  # nothing is left to refuse; the pending proof every read before it took is cleared. 1 when it could not be.
  pf_append() {
    if ! proof_event "$PV_PLAN" "${PF_EV[@]}"; then
      die "REFUSED — the ${PF_EV[0]#kind=} proof could not be appended to the run's log of $PV_PLAN; the plan is unchanged. Run proof-add again."
      return 1
    fi
    proof_pending
  }
  poker_verb_proof_add() {
    if ! { declare -F proof_last >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_event >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    # INHERITED DEBT (wave-35 T9; D8, AC-1.6; ADR-054). A suite the floor's whole run left red that is ALSO red
    # at the run's base commit is debt the run inherited, not a regression it made. This verb asks the base
    # itself: it makes a scratch tree at `base-sha:` through spawn-worktree.sh, runs the suite there (the
    # project's tests/run.sh --only <suite> when the base has one, else the suite file), keeps the run's
    # log in the record, and removes the tree and its branch. Red there, it writes
    #
    #     proof kind=inherited head=<the floor's head> evidence=record/<wave>/<log> suite=<suite> base=<base>
    #
    # to the run's log (lib/proof.sh `proof_event`), and the judge (lib/proof.sh `_proof_floor_judge`)
    # owes the floor nothing for that suite and stands on the rest. Green there, it is a regression, and the
    # verb refuses to carry it. Only a suite the floor's proof line lists as owed can be inherited: the line
    # is the whole run's own word that the suite is red at its head.
    if [ "$PF_KIND" = inherited ]; then
      PF_SUITE="${PF_EVID##*/}"
      plan_verb_open proof-add
      PF_FHEAD="$(proof_last "$PV_PLAN" regression)"
      if [ -z "$PF_FHEAD" ]; then
        die "REFUSED — $PV_PLAN carries no regression proof, so no whole run says $PF_SUITE is red at the head; run the regression and proof-add regression first. The plan is unchanged."
        exit 1
      fi
      PF_OWED="$(_proof_last_read "$PV_PLAN" regression owed)"
      case ",$PF_OWED," in
        *",$PF_SUITE,"*) : ;;
        *)
          die "REFUSED — $PF_SUITE is not red in the regression's whole run (the proof at ${PF_FHEAD:0:12} owes ${PF_OWED:-nothing}); only a suite that run left red can be inherited debt. The plan is unchanged."
          exit 1 ;;
      esac
      PF_BASE="$(proof_plan_base "$PV_PLAN" "$PV_REPO")"; PF_BASEH=""
      proof_base_id "$PF_BASE" && PF_BASEH="$(git -C "$PV_REPO" rev-parse --verify -q "${PF_BASE}^{commit}" 2>/dev/null)"
      if [ -z "$PF_BASEH" ]; then
        die "REFUSED — $PV_PLAN names no base-sha: that is a commit here${PF_BASE:+ (it says $(clean "$PF_BASE"))}, so there is no base to run $PF_SUITE at; add base-sha: <the commit the work started from>. The plan is unchanged."
        exit 1
      fi
      PF_RECD="$(proof_debt_record "$PV_PLAN" "$PV_REPO" 2>/dev/null)"; PF_RECD="${PF_RECD%/*}"
      PF_DOCS="$(cd "$(docs_root "$PV_REPO")" 2>/dev/null && pwd -P)"
      case "$PF_RECD" in
        "$PF_DOCS"/record/?*) : ;;
        *) die "REFUSED — the plan's record directory cannot be resolved under $PF_DOCS/record/; the plan is unchanged."; exit 2 ;;
      esac
      mkdir -p "$PF_RECD" 2>/dev/null
      PF_LOG="$PF_RECD/inherited-$PF_SUITE-${PF_BASEH:0:12}.log"; PF_REL="${PF_LOG#"$PF_DOCS"/}"
      PF_SW="$(cd "$BIONIC_LIB/.." 2>/dev/null && pwd -P)/spawn-worktree.sh"
      PF_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/bionic-inherited.XXXXXX" 2>/dev/null)" || PF_PARENT=""
      PF_BR="bionic-inherited/${PF_SUITE%.sh}-${PF_BASEH:0:12}-$$"
      PF_OK=""; [ -z "$PF_PARENT" ] || PF_OK="$(cd "$PV_REPO" && bash "$PF_SW" create "$PF_BASEH" "$PF_BR" "$PF_PARENT" 2>&1)"
      PF_WT="$(printf '%s
' "$PF_OK" | awk '/^spawn-worktree: OK / { for (i = 3; i <= NF; i++) if (index($i, "path=") == 1) { print substr($i, 6); exit } }')"
      _pf_drop() {
        [ -z "$PF_WT" ] || ( cd "$PV_REPO" && bash "$PF_SW" remove "$PF_WT" ) >/dev/null 2>&1
        git -C "$PV_REPO" branch -q -D "$PF_BR" >/dev/null 2>&1
        [ -z "$PF_PARENT" ] || rm -rf "$PF_PARENT"
      }
      if [ -z "$PF_WT" ] || [ ! -d "$PF_WT" ]; then
        _pf_drop
        die "REFUSED — spawn-worktree.sh could not make a scratch tree at the base ${PF_BASEH:0:12}: $(clean "$(printf '%s' "$PF_OK" | tail -n 1)"). The plan is unchanged."
        exit 2
      fi
      if [ ! -f "$PF_WT/tests/$PF_SUITE" ]; then
        _pf_drop
        die "REFUSED — $PF_SUITE is not at the base ${PF_BASEH:0:12}, so its red is this run's own, not inherited; fix it on a fix row. The plan is unchanged."
        exit 1
      fi
      if [ -f "$PF_WT/tests/run.sh" ]; then PF_CMD="bash tests/run.sh --only $PF_SUITE"; else PF_CMD="bash tests/$PF_SUITE"; fi
      ( cd "$PF_WT" && bash -c "$PF_CMD" ) > "$PF_LOG.out" 2>&1; PF_RC=$?
      { printf 'head=%s suite=%s rc=%s
command: %s
' "$PF_BASEH" "$PF_SUITE" "$PF_RC" "$PF_CMD"; cat "$PF_LOG.out" 2>/dev/null; } > "$PF_LOG"
      rm -f "$PF_LOG.out"; _pf_drop
      case "$PF_RC" in
        0)
          die "REFUSED — $PF_SUITE is green at the base ${PF_BASEH:0:12} (its log: $PF_REL): a regression, not debt; a fix row closes it. The plan is unchanged."
          exit 1 ;;
        75|69)
          die "REFUSED — $PF_SUITE did not run at the base (exit $PF_RC: the gate never admitted it; its log: $PF_REL); run proof-add inherited again. The plan is unchanged."
          exit 1 ;;
      esac
      if ! proof_event "$PV_PLAN" kind=inherited "head=$PF_FHEAD" "evidence=$PF_REL" "suite=$PF_SUITE" "base=$PF_BASEH"; then
        die "REFUSED — $PF_SUITE is red at the base ${PF_BASEH:0:12} (its log: $PF_REL), and its proof could not be appended to the run's log of $PV_PLAN; run proof-add inherited again. The plan is unchanged."
        exit 1
      fi
      say "proof-add — inherited: $PF_SUITE red at the base ${PF_BASEH:0:12} (rc=$PF_RC) and at the regression's head ${PF_FHEAD:0:12}; written to the run's log, its log $PF_REL; the regression stands on the rest."
      exit 0
    fi
    if ! proof_kind_ok "$PF_KIND"; then
      die "REFUSED — '$(clean "$PF_KIND")' is not a proof kind: name regression, review, task or walk (or proof-add inherited <suite>). The plan is unchanged."
      exit 1
    fi
    # A CHECK FACT IS WRITTEN BY THE VERB THAT RAN THE CHECK (wave-27 T16; D12): a log handed in
    # here was written by nobody's run.
    if [ "$PF_KIND" = check ]; then
      die "REFUSED — a check proof is written by release-check, which runs the project's declared command and keeps its log; run release-check. The plan is unchanged."
      exit 1
    fi
    if [ -n "$PF_QUESTION" ] && ! proof_question_ok "$PF_QUESTION"; then
      die "REFUSED — '$(clean "$PF_QUESTION")' is not a review question: name evidence, adversarial or structure. The plan is unchanged."
      exit 1
    fi
    # THE READER'S NAME IS MATCHED AS TYPED (wave-27 T41; review pass 10 F3): letters, digits, `_`
    # and `-`, spelled out (PV_ID_ALNUM: a range is a collation range under a UTF-8 locale), so no
    # escape a reader of it might decode, and no character the space-separated line cannot hold.
    case "$PF_READER" in
      *[!"$PV_ID_ALNUM"_-]*)
        die "REFUSED — the reviewer name '$(clean "$PF_READER")' carries a character outside A-Z, a-z, 0-9, _ and -, and a reviewer name is matched byte for byte against its roster row; name the reviewer as its roster row does. The plan is unchanged."
        exit 1 ;;
    esac
    plan_verb_open proof-add
    PF_DOCS="$(docs_root "$PV_REPO")"
    PF_DOCS="$(cd "$PF_DOCS" 2>/dev/null && pwd -P)"
    # EACH LOG IS HELD TO THE SAME RECORD RULES (wave-36 T35; AC-7.10): a floor's several logs are read one by one, and
    # PF_PAIRS keeps each one's real path and its path under the docs root, tab-joined; PF_REAL and PF_REL name the
    # first, which is the evidence of every other kind.
    PF_PAIRS=""; PF_REAL=""; PF_REL=""
    while IFS= read -r PF_EVID; do
      case "$PF_EVID" in
        *[[:space:]]*|*'|'*)
          die "REFUSED — the evidence path '$(clean "$PF_EVID")' carries a space, a tab, a line break or a |, which the space-separated proof line cannot hold; rename the file. The plan is unchanged."
          exit 1 ;;
        *,*)
          if [ "$PF_KIND" = regression ] && [ "$PF_EVIDS" != "$PF_EVID" ]; then
            die "REFUSED — the evidence path '$(clean "$PF_EVID")' carries a comma, and a regression proof of several logs names them comma-joined on one evidence= field; rename the file. The plan is unchanged."
            exit 1
          fi ;;
      esac
      case "$PF_EVID" in
        /*) PF_ABS="$PF_EVID" ;;
        *)  PF_ABS="$PF_DOCS/$PF_EVID" ;;
      esac
      # A SYMLINK IS NOT A RECORD (wave-26 T46; review 10 F7). The check below resolves the
      # directory, not the file, so a link under record/ to a log elsewhere would be admitted and the
      # evidence it cites could change after the proof. Refused by name, before it is read.
      if [ -L "$PF_ABS" ]; then
        die "REFUSED — the evidence $(clean "$PF_EVID") is a symbolic link (to $(clean "$(readlink "$PF_ABS")")), and what it points at can change after the proof; copy the log into the record (cp it to that path) and run proof-add again. The plan is unchanged."
        exit 1
      fi
      _pf_real=""
      [ -n "$PF_DOCS" ] && [ -f "$PF_ABS" ] \
        && _pf_real="$(cd "$(dirname "$PF_ABS")" 2>/dev/null && pwd -P)/$(basename "$PF_ABS")"
      if [ -z "$_pf_real" ]; then
        die "REFUSED — the evidence file $(clean "$PF_EVID") does not exist (read as $(clean "$PF_ABS")); write the record first, then add its proof. The plan is unchanged."
        exit 1
      fi
      case "$_pf_real" in
        "$PF_DOCS"/record/*) _pf_rel="${_pf_real#"$PF_DOCS"/}" ;;
        *)
          die "REFUSED — the evidence $(clean "$PF_EVID") is not under record/ of the docs root ($PF_DOCS/record/); a proof cites a record. The plan is unchanged."
          exit 1 ;;
      esac
      [ -n "$PF_REAL" ] || { PF_REAL="$_pf_real"; PF_REL="$_pf_rel"; }
      PF_PAIRS="$PF_PAIRS$_pf_real	$_pf_rel
"
    done <<PF_EVIDS_LIST
$PF_EVIDS
PF_EVIDS_LIST
    # A READING CARRIES ITS QUESTION, ITS RESULT AND ITS SCOPE (wave-27 T2; D1, AC-2.1). The record's
    # own flush-left lines say them, and for `structure` it answers every check id the shipped
    # checks file names, the file resolved through this hook's own lib root, as execution-recorder
    # resolves survival.md (lib/proof.sh `proof_reading`). A reading record holds exactly one pass and
    # a second is refused (T45), each value whole, and a structure result is one its checks bear out
    # (T41; review pass 10 F1, F2, F6); the start of its range comes back too, for the whole-read check below.
    PF_RESULT=""; PF_SCOPE=""; PF_FROM=""; PF_ROLE=""; PF_SEV=""
    if [ -n "$PF_QUESTION" ]; then
      # THE READER WAS PUSHED THE SEVERITY SCALE (wave-28 T15; D19, AC-8.1, AC-8.8): the `pushed=` of
      # the last row naming this reader, dealt this question and past `intended`, on any roster of the
      # project, read by key as `questions=` is. When it names `severity` (lib/proof.sh
      # `proof_pushed_severity`) the record must carry its findings and its result is the one they
      # derive; otherwise it is read as 1.12.0 read it. The row checks themselves follow below.
      PF_PUSHED=""
      for _pf_rf in "$PV_REPO/.bionic/tmp"/roster-*.state; do
        [ -f "$_pf_rf" ] && [ ! -L "$_pf_rf" ] || continue
        _pf_p="$(PF_WANT="$PF_READER" PF_Q="$PF_QUESTION" awk "$_ROSTER_OPEN_AWK"'
          index($0, "roster-state/") == 1 && (_roster_kv($0, "name") "") == (ENVIRON["PF_WANT"] "") {
            s = _roster_kv($0, "status"); if (s == "" || s == "intended") next
            m = split(_roster_kv($0, "questions"), qs, ","); d = 0
            for (i = 1; i <= m; i++) if (qs[i] == ENVIRON["PF_Q"]) d = 1
            if (d) { p = _roster_kv($0, "pushed"); f = 1 } }
          END { if (f) print "=" p }' "$_pf_rf" 2>/dev/null)"
        [ -z "$_pf_p" ] || PF_PUSHED="${_pf_p#=}"
      done
      proof_pushed_severity "$PF_PUSHED" && PF_SEV=1
      if ! PF_RS="$(proof_reading "$PF_REAL" "$PF_QUESTION" "$BIONIC_LIB/../../context/checks-structure.md" "$PF_SEV")"; then
        die "REFUSED — $(clean "$PF_RS"). The plan is unchanged."
        exit 1
      fi
      PF_RESULT="${PF_RS%% *}"; PF_FROM="${PF_RS#* }"; PF_SCOPE="${PF_FROM%% *}"; PF_FROM="${PF_FROM#* }"
      # THE READER IS A ROW THE DISPATCH RECORDED (wave-27 T2; D7, AC-1.4). Every roster of this
      # project is read, every session's, for a reader whose session has ended still has its row
      # there until close-out; each row naming the reader must be a reader role, and one of them
      # must have been dealt the question (`questions=`). A name no row carries is refused, so the
      # orchestrator cannot register a reading in a reader's name, and a name any writer row
      # carries is refused, so a writer cannot read its own code under it. The name is compared
      # byte for byte, handed to awk through its environment, never `-v`, which decodes escapes
      # (T41; review pass 10 F3).
      # THE RECORD IS THE READER'S OWN (T41; review pass 10 F4). A row dealt the question that got
      # past `intended` (its agent started) must name this record as its `deliverable=` or among its
      # `files=`, each entry read from the project root unless absolute and compared by its real
      # path, so no record is registered under the name of a reader that never wrote it. The roster
      # files themselves take any write; that residual is the walls' known one (walls.sh, "habit,
      # not an adversary").
      PF_ROWS=""
      for _pf_rf in "$PV_REPO/.bionic/tmp"/roster-*.state; do
        [ -f "$_pf_rf" ] && [ ! -L "$_pf_rf" ] || continue
        PF_ROWS="$PF_ROWS$(PF_WANT="$PF_READER" awk "$_ROSTER_OPEN_AWK"'
          index($0, "roster-state/") == 1 && (_roster_kv($0, "name") "") == (ENVIRON["PF_WANT"] "") {
            t = _roster_kv($0, "subagent_type"); if (t == "") t = "(none)"
            print t "\t" _roster_kv($0, "questions") "\t" _roster_kv($0, "status") "\t" _roster_kv($0, "deliverable") "\t" _roster_kv($0, "files") "\t" _roster_kv($0, "name") }' "$_pf_rf" 2>/dev/null)
"
      done
      PF_LOOK="$(printf '%s' "$PF_ROWS" | PROOF_ROLES="$PROOF_READER_ROLES" PF_Q="$PF_QUESTION" awk -F'\t' '
        BEGIN { n = split(ENVIRON["PROOF_ROLES"], r, " "); for (i = 1; i <= n; i++) ok[r[i]] = 1; q = ENVIRON["PF_Q"] }
        NF { rows++
             if (!($1 in ok)) { if (bad == "") bad = $1; next }
             d = 0; m = split($2, qs, ","); for (i = 1; i <= m; i++) if (qs[i] == q) d = 1
             if (!d) next
             dealt = 1; role = $1; name = $6
             if ($3 == "" || $3 == "intended") next
             past = 1
             if ($4 != "" && !($4 in seen)) { seen[$4] = 1; own[++c] = $4 }
             m = split($5, fs, ","); for (i = 1; i <= m; i++) if (fs[i] != "" && !(fs[i] in seen)) { seen[fs[i]] = 1; own[++c] = fs[i] } }
        END {
          if (!rows) { print "none"; exit }
          if (bad != "") { print "writer\t" bad; exit }
          if (!dealt) { print "undealt"; exit }
          if (!past) { print "intended"; exit }
          print "ok\t" role "\t" name
          for (i = 1; i <= c; i++) print own[i] }')"
      PF_ROLE="${PF_LOOK%%
*}"
      case "$PF_ROLE" in
        none)
          die "REFUSED — no roster row on this machine names the reviewer $(clean "$PF_READER"), so nothing records it as a reviewer; register a review under the name its dispatch recorded. The plan is unchanged."
          exit 1 ;;
        writer*)
          die "REFUSED — the reviewer $(clean "$PF_READER") has a roster row of role $(clean "${PF_ROLE#*	}"), which is not a reviewer role ($PROOF_READER_ROLES); a review is registered for a reviewer, never a writer. The plan is unchanged."
          exit 1 ;;
        undealt)
          die "REFUSED — the reviewer $(clean "$PF_READER") was not dealt the $PF_QUESTION question (the questions= of its roster row does not name it); register the review for the reviewer dealt it. The plan is unchanged."
          exit 1 ;;
        intended)
          die "REFUSED — the reviewer $(clean "$PF_READER") dealt the $PF_QUESTION question has no roster row past status=intended: its launch was recorded and never started, so it read nothing; register the review once its agent has run. The plan is unchanged."
          exit 1 ;;
      esac
      PF_OWN=""
      while IFS= read -r _pf_c; do
        [ -n "$_pf_c" ] || continue; _pf_p="$(docs_path "$PV_REPO" "$_pf_c")"
        [ -f "$_pf_p" ] || continue
        if [ "$(cd "$(dirname "$_pf_p")" 2>/dev/null && pwd -P)/$(basename "$_pf_p")" = "$PF_REAL" ]; then PF_OWN=1; break; fi
      done <<PF_OWN_LIST
$(printf '%s\n' "$PF_LOOK" | sed 1d)
PF_OWN_LIST
      if [ -z "$PF_OWN" ]; then
        die "REFUSED — the record $(clean "$PF_REL") was not written by the reviewer $(clean "$PF_READER"): no roster row of that reviewer names it as its deliverable= or among its files=, and a review is the record its reviewer was dispatched to write; register it under the reviewer whose row names it. The plan is unchanged."
        exit 1
      fi
      # A RECORD IS ONE READER'S (wave-27 T45; review pass 16 finding 2). A pass carries no reader of
      # its own, so a record that another roster row also names as its deliverable= or among its
      # files= could be registered under either name; it is refused, naming that row, whichever
      # reader is typed. Each entry is compared by real path, as above.
      # ONLY A ROW THAT CAN STILL WRITE IT COUNTS (wave-27 T14; review pass 20 F3): a row of a
      # DIFFERENT name, past `intended` (confirmed or identified) and still open by the one reader
      # of "is this name closed" (`roster_open_names`, its roster's ack ledger beside it). An
      # `intended` launch read nothing, a closed or acked one reads no more, and a row of the
      # reader's own name is its own relaunch, so a reader dispatched again to the record of an
      # earlier launch can register what it read.
      PF_OTHER=""
      for _pf_rf in "$PV_REPO/.bionic/tmp"/roster-*.state; do
        [ -f "$_pf_rf" ] && [ ! -L "$_pf_rf" ] && [ -z "$PF_OTHER" ] || continue
        _pf_rs="${_pf_rf##*/roster-}"; _pf_rs="${_pf_rs%.state}"
        _pf_open=" $(roster_open_names "$_pf_rf" "${_pf_rf%/*}/sweeper-${_pf_rs}.state" 2>/dev/null | tr '\n' ' ')"
        while IFS=$'\037' read -r _pf_on _pf_ot _pf_c; do
          [ -n "$_pf_c" ] || continue; _pf_p="$(docs_path "$PV_REPO" "$_pf_c")"
          [ -f "$_pf_p" ] || continue
          if [ "$(cd "$(dirname "$_pf_p")" 2>/dev/null && pwd -P)/$(basename "$_pf_p")" = "$PF_REAL" ]; then
            PF_OTHER="$_pf_on (${_pf_ot:-no subagent_type})"; break
          fi
        done <<PF_OTHER_LIST
$(PF_WANT="$PF_READER" PF_OPEN="$_pf_open" awk "$_ROSTER_OPEN_AWK"'
  index($0, "roster-state/") == 1 && (_roster_kv($0, "name") "") != (ENVIRON["PF_WANT"] "") &&
    (_roster_kv($0, "status") == "confirmed" || _roster_kv($0, "status") == "identified") &&
    index(ENVIRON["PF_OPEN"], " " _roster_kv($0, "name") " ") {
    o = _roster_kv($0, "name") "\037" _roster_kv($0, "subagent_type") "\037"
    m = split(_roster_kv($0, "deliverable") "," _roster_kv($0, "files"), e, ",")
    for (i = 1; i <= m; i++) if (e[i] != "") print o e[i] }' "$_pf_rf" 2>/dev/null)
PF_OTHER_LIST
      done
      if [ -n "$PF_OTHER" ]; then
        die "REFUSED — the record $(clean "$PF_REL") is also named by the roster row $(clean "$PF_OTHER") as its deliverable= or among its files=; a review record is one reviewer's, so each reviewer writes a record of its own. The plan is unchanged."
        exit 1
      fi
      PF_ROLE="${PF_ROLE#*	}"; PF_READER="${PF_ROLE#*	}"; PF_ROLE="${PF_ROLE%%	*}"
    fi
    PF_WB="$(plan_working_branch "$PV_PLAN")"
    if [ -z "$PF_WB" ]; then
      die "REFUSED — $PV_PLAN names no working-branch:, so there is no checkout to read the head from; add 'working-branch: <branch>' to the plan's header. The plan is unchanged."
      exit 1
    fi
    # THE WORKING HEAD IS THE BRANCH'S REF (wave-36 T12; D13, AC-7.4; C30): lib/proof.sh `proof_branch_head`, as the
    # judge reads it, so a reading of a merged branch whose worktree is gone still registers.
    PF_HEAD="$(proof_branch_head "$PV_PLAN" "$PV_REPO")" || PF_HEAD=""
    case "$PF_HEAD" in
      [0-9a-f]*) : ;;
      *)
        die "REFUSED — working-branch $(clean "$PF_WB") names no commit in $PV_REPO, so its head cannot be read; name a branch that exists as working-branch: in the plan's header and run proof-add again. The plan is unchanged."
        exit 1 ;;
    esac
    # A WALK IS REGISTERED WHOLE BY walk_register: its verdicts read as the critic's, its proof and one proof per
    # criterion it confirms; the plan is not written. The tick's landing of a record row lands the walk row on it.
    if [ "$PF_KIND" = walk ]; then
      if ! walk_register "$PV_PLAN" "$PF_REAL" "$PF_REL" "$PF_HEAD" "$PV_REPO"; then
        die "REFUSED — $(clean_whole "$WALK_WHY"), then proof-add walk again. The plan is unchanged."
        exit 1
      fi
      walk_append || exit 2
      walk_recorded "$PV_PLAN" "$PF_REL"
      say "proof-add — kind=walk head=$WALK_HEAD evidence=$PF_REL: written to the run's log."
      say "proof-add — $(walk_said "$PF_REL")"
      exit 0
    fi
    # THE HEAD IS THE ONE THE EVIDENCE READ (wave-26 T14; review 7 F1). The working head only
    # bounds it: a run's log must have read exactly that head on a clean tree, a review a commit
    # on its history, and the proof names what the evidence attests (lib/proof.sh
    # `proof_attested`). A task landed between the run and this verb is not proved by it.
    # The plan goes too: a review's range must start at or before its last review proof (T62).
    # A reading's range starts at or before the last proof of its own question (wave-27 T2; D1).
    # The project root goes too: a config still carrying the removed floor-attestation: key is refused by name (T35).
    # The repository reads the objects and the ref's head bounds the evidence: no checkout is asked (T12).
    # A FLOOR'S LOGS ARE EACH READ, AND SHARE ONE HEAD (wave-36 T35; D13, AC-7.10): every log is judged by the floor's one
    # grammar (lib/proof.sh `_proof_floor_log`), the first refusal is the verb's, and logs that read different heads
    # are refused naming each, for a floor is the runs of one head. The owed reds are the union of each log's.
    PF_OWED=""
    if [ "$PF_KIND" = regression ]; then
      PF_FH=""; PF_FHEADS=""; PF_FRELS=""; PF_SPLIT=""; PF_RUNAT=""; PF_RUNRC=""
      while IFS='	' read -r _pf_real _pf_rel; do
        [ -n "$_pf_real" ] || continue
        if ! _pf_h="$(proof_attested regression "$_pf_real" "$PV_REPO" "$PV_PLAN" "" "$PV_REPO" "$PF_HEAD")"; then
          die "REFUSED — $(clean_whole "$_pf_h"). The plan is unchanged."
          exit 1
        fi
        # THE PROOF NAMES THE RUN IT READ (wave-37 T4; AC-6.2): the recorded run the judge matched the log to.
        _pf_run="$(proof_floor_run "$_pf_real" "$PV_PLAN" "$PV_REPO")" || _pf_run=""
        PF_RUNAT="${PF_RUNAT:+$PF_RUNAT,}$(printf '%s' "$_pf_run" | cut -d' ' -f1)"
        PF_RUNRC="${PF_RUNRC:+$PF_RUNRC,}$(printf '%s' "$_pf_run" | cut -d' ' -f3)"
        [ -z "$PF_FH" ] || [ "$_pf_h" = "$PF_FH" ] || PF_SPLIT=1
        PF_FH="${PF_FH:-$_pf_h}"
        PF_FHEADS="${PF_FHEADS:+$PF_FHEADS, }$_pf_rel read ${_pf_h:0:12}"
        PF_FRELS="${PF_FRELS:+$PF_FRELS,}$_pf_rel"
        PF_OWED="$(printf '%s,%s\n' "$PF_OWED" "$(proof_floor_owed "$_pf_real")" | awk -F, '
          { for (i = 1; i <= NF; i++) if ($i != "" && !($i in s)) { s[$i] = 1; o = o (o == "" ? "" : ",") $i } }
          END { print o }')"
      done <<PF_PAIRS_LIST
$PF_PAIRS
PF_PAIRS_LIST
      if [ -n "$PF_SPLIT" ]; then
        die "REFUSED — the logs read different heads: $(clean "$PF_FHEADS"); a regression is the runs of one head, so run each at one head and cite those logs together. The plan is unchanged."
        exit 1
      fi
      PF_HEAD="$PF_FH"; PF_REL="$PF_FRELS"
    elif ! PF_HEAD="$(proof_attested "$PF_KIND" "$PF_REAL" "$PV_REPO" "$PV_PLAN" "$PF_QUESTION" "$PV_REPO" "$PF_HEAD")"; then
      die "REFUSED — $(clean_whole "$PF_HEAD"). The plan is unchanged."
      exit 1
    fi
    # ONE RECORD PATH IS ONE PASS. A finding event (a deferral or a move) is
    # keyed `<record>#<n>`, so a second pass registered on the path of a first would inherit its deferral
    # or its move (a #1 moved to defer defers the new pass's fix). A reading's path whose proof line names
    # another head is refused, and so is one such an event already names (lib/proof.sh `proof_bind_awk` is
    # the one predicate); a relaunched reader re-registering a record no such event names (the same
    # head) is admitted as before.
    if [ -n "$PF_QUESTION" ]; then
      PF_PASS="$(proof_pass_conflict "$PV_PLAN" "$PF_REL" "$PF_HEAD")" \
        || { die "REFUSED — the run's facts could not be read, so whether $(clean "$PF_REL") is already a settled pass is not known; the plan is unchanged."; exit 2; }
      case "$PF_PASS" in
        head\ *)
          die "REFUSED — $(clean "$PF_REL") is already registered at $(clean "${PF_PASS#head }" | cut -c1-12), not ${PF_HEAD:0:12}: write the pass to a new record path. The plan is unchanged."
          exit 1 ;;
        settled\ *)
          die "REFUSED — $(clean "$PF_REL") at ${PF_HEAD:0:12} already has a deferral or a move of one of its findings: write the pass to a new record path. The plan is unchanged."
          exit 1 ;;
      esac
    fi
    # A WHOLE READ STARTS AT THE RUN'S BASE (wave-27 T41; review pass 10 F5). The line carries the
    # head and not the start, so `scope: whole` over a tail would read to the judge as a read of
    # everything; it is accepted only when the range starts at the plan's base-sha: or an ancestor
    # of it (proof_attested has already resolved the start, so here it is a commit).
    if [ "$PF_SCOPE" = whole ]; then
      PF_BASE="$(proof_plan_base "$PV_PLAN" "$PV_REPO")"; PF_BASEH=""
      proof_base_id "$PF_BASE" && PF_BASEH="$(git -C "$PV_REPO" rev-parse --verify -q "$PF_BASE^{commit}" 2>/dev/null)"
      if [ -z "$PF_BASEH" ]; then
        # THE SAME PLACE THE FIRST-READING REFUSAL NAMES (wave-27 T14; review pass 20 F4), and a word
        # such as HEAD is said to be no commit id (F1).
        PF_BASEWHY="it names no base-sha:"
        if [ -n "$PF_BASE" ] && ! proof_base_id "$PF_BASE"; then PF_BASEWHY="its base-sha: $(clean "$PF_BASE") is not a commit id"
        elif [ -n "$PF_BASE" ]; then PF_BASEWHY="its base-sha: $(clean "$PF_BASE") is no commit here"; fi
        die "REFUSED — the review $(clean "$PF_REL") says scope: whole, but $PF_BASEWHY, so nothing shows it read from the start of the run; add base-sha: <the commit the work started from> to the frontmatter of $PV_PLAN, or write scope: piece. The plan is unchanged."
        exit 1
      fi
      PF_FROMH="$(git -C "$PV_REPO" rev-parse --verify -q "$PF_FROM^{commit}" 2>/dev/null)"
      if [ -z "$PF_FROMH" ] || ! git -C "$PV_REPO" merge-base --is-ancestor "$PF_FROMH" "$PF_BASEH" 2>/dev/null; then
        die "REFUSED — the review $(clean "$PF_REL") says scope: whole, but its range starts at $(clean "$(printf '%s' "${PF_FROMH:-$PF_FROM}" | cut -c1-12)"), past the plan's base ${PF_BASEH:0:12}; a whole review reads from the base, so write reviewed: ${PF_BASEH:0:12}..<b>, or scope: piece. The plan is unchanged."
        exit 1
      fi
    fi
    # A READING REGISTERS AT THE HEAD IT NAMES, OPEN BUILD ROWS OR NONE (wave-36 T28; D9, AC-3.1). Through wave-35
    # a whole read was refused while a build row was open (D10), because the judge covered a whole line with any
    # whole reading whatever its head. The judge now reaches only as far as the question's chain (wave-36 T7;
    # A-T7-5), so what lands after the reading is the cover rule's to judge, and the verb holds nothing.
    PF_EV=("kind=$PF_KIND" "head=$PF_HEAD" "evidence=$PF_REL")
    [ -z "$PF_QUESTION" ] || PF_EV+=("question=$PF_QUESTION" "reader=$PF_READER" "result=$PF_RESULT" "scope=$PF_SCOPE")
    # A RED WHOLE RUN'S REDS RIDE ON ITS PROOF: proof_attested took each log and every red
    # named; the proof lists them as owed, and the judge reads them there. Its evidence= is the logs, comma-joined (T35),
    # and it names the recorded run it read.
    if [ "$PF_KIND" = regression ]; then
      [ -z "$PF_OWED" ] || PF_EV+=("owed=$PF_OWED")
      [ -z "$PF_RUNAT" ] || PF_EV+=("run=$PF_RUNAT")
      [ -z "$PF_RUNRC" ] || PF_EV+=("rc=$PF_RUNRC")
    fi
    # THE PROOF IS READ AS STANDING BY EVERY READ BELOW, and appended only once nothing is left to refuse.
    if ! proof_pending "${PF_EV[@]}"; then
      die "REFUSED — the proof's fields hold a | or a line break, which the run's log cannot hold; the plan is unchanged."
      exit 1
    fi
    # A RATED READING DEFERS WHAT THE TABLE DEFERS: one deferral event per finding the table
    # defers, appended to the run's log once the proof is (lib/proof.sh `proof_finding_deferrals`).
    # No `check:`: a reader's rating is final.
    PF_FINDS=""; PF_PLANL=""
    if [ "$PF_SEV" = 1 ]; then
      PF_FINDS="$(proof_findings "$PF_REAL")"; PF_PLANL="$(proof_finding_lines "$PF_REL" "$PF_FINDS")"
    fi
    # A REVIEW THAT FOLLOWS THE BUILD GOES BACK TO WAITING. The active review row reading `live:head` (`units_live_rows`,
    # the kind default included) whose `Files` hold this evidence returns to pending: that row alone, so the proof of
    # another review leaves a live pass running where it is. A READING RETURNS THE ROW CARRYING ITS QUESTION: handed
    # --question, `units_live_rows` finds a read row by the question it read, not by its Files; a bare row is still found
    # by its Files, the evidence handed in both spellings, from the docs root and from the repository. The row is one row
    # across every pass, each pass its own launch, and a launch is returned by its one cancel in the run's log
    # (lib/units.sh `units_dispatch_back`), appended after the proof; the plan is never written, so a row whose launch the
    # log does not hold is not returned here. The next landing past this proof makes it ready again (units.sh `live_head`).
    # A READ ROW RETURNS ONLY TO ITS OWN READER, AND ONLY WHOLE (wave-27 T43; review pass 17 F3):
    # handed --reader, `units_live_rows` names a read row only when its agent cell is this reader
    # and every question it carries now has a reading at this head; until then it stays active and
    # is not offered, and PF_HELD names it. A row abandoned part-way is returned when its agent is stopped.
    PF_BACK=""; PF_HELD=""
    PF_LIVE=""; [ "$PF_KIND" != review ] || PF_LIVE="$(_units_live "$PV_PLAN")" \
      || { die "REFUSED — the run's facts cannot be read, so a review row's launch cannot be taken back; the plan is unchanged; run again: the same proof-add."; exit 1; }
    if [ "$PF_KIND" = review ]; then
      PF_DOCREL="$(docs_root "$PV_REPO")"
      case "$PF_DOCREL" in "$PV_REPO"/*) PF_DOCREL="${PF_DOCREL#"$PV_REPO"/}/$PF_REL" ;; *) PF_DOCREL="" ;; esac
      [ -z "$PF_QUESTION" ] || PF_HELD="$(units_live_rows "$PV_PLAN" --question "$PF_QUESTION" 2>/dev/null \
        | awk -F'\t' '$2 == "review" && $3 == "active" { printf "%s%s", (n++ ? " " : ""), $1 }')"
      for _pf_id in $(units_live_rows "$PV_PLAN" ${PF_QUESTION:+--question "$PF_QUESTION" --reader "$PF_READER"} "$PF_REL" $PF_DOCREL 2>/dev/null | awk -F'\t' '$2 == "review" && $3 == "active" { print $1 }'); do
        PF_BACK="${PF_BACK:+$PF_BACK }$_pf_id"
        PF_HELD=" $PF_HELD "; PF_HELD="${PF_HELD/ $_pf_id / }"; PF_HELD="${PF_HELD# }"; PF_HELD="${PF_HELD% }"
      done
      [ -z "$PF_HELD" ] || PF_HELD="$(units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' -v ids=" $PF_HELD " -v r="$PF_READER" \
        'index(ids, " " $1 " ") && $5 == r { printf "%s%s", (n++ ? " " : ""), $1 }')"
    fi
    # A REVIEW PROOF THAT RETURNS NO LIVE ROW WHILE ONE IS ACTIVE SAYS SO (wave-26 T51; review 14
    # S4). The record of a live pass written under another name than its row's Files returns
    # nothing, rightly, and the pass is then never offered again; through T46 the success line
    # said nothing of it. The active live review rows are named with their Files, so the mismatch
    # is seen at once. None is reset: a proof moves only the row whose Files hold it (T46, review
    # 10 F3), and the final review's proof is one such. With no live review active it says nothing.
    PF_NONE=""
    if [ "$PF_KIND" = review ] && [ -z "$PF_BACK" ] && [ -z "$PF_HELD" ]; then
      _pf_live=" $(units_live_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' '$2 == "review" && $3 == "active" { printf "%s ", $1 }')"
      [ "$_pf_live" = " " ] || PF_NONE="$(units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' -v ids="$_pf_live" '
        index(ids, " " $1 " ") { printf "%s%s (%s)", (n++ ? ", " : ""), $1, $9 }')"
    fi
    pf_append || exit 2
    if [ -n "$PF_PLANL" ] && ! proof_finding_deferrals "$PV_PLAN" "$PF_REL" "$PF_FINDS"; then
      die "proof-add — the $PF_KIND proof at $PF_HEAD is written, and its deferrals could not be appended to the run's log of $PV_PLAN: the findings the table defers are not deferred."
      exit 2
    fi
    _pf_ids="$PF_BACK"; PF_BACK=""
    for _pf_id in $_pf_ids; do
      _pf_nm="$(printf '%s\n' "$PF_LIVE" | awk -F'\t' -v id="$_pf_id" '$1 == id && $2 == "active" { print $3 }')"
      [ -n "$_pf_nm" ] || continue
      if units_dispatch_back "$PV_PLAN" "$_pf_id" "$_pf_nm"; then PF_BACK="${PF_BACK:+$PF_BACK }$_pf_id"
      else say "proof-add — $_pf_id still reads running: its launch as $_pf_nm could not be taken back in the run's log; once $_pf_nm is stopped, bash ${HOOK_DIR}/stop-orders.sh stopped $_pf_nm takes it back."; fi
    done
    # A FAILING READING IS THE PERSON'S TO WAIVE FROM THE MOMENT IT IS RECORDED: fix it, or waive the question. The ask
    # opens here, under the key the judge and the waive verb use, rather than waiting for an advance or a commit to be
    # refused on it; a passing reading of the same question closes it, as the judge closes a question no longer failing.
    if [ "$PF_KIND" = review ] && [ -n "$PF_QUESTION" ]; then
      case "$PF_RESULT" in
        fail) proof_owed open "waive:$PF_QUESTION" "waiver: $PF_QUESTION" \
                "proof-add: the $PF_QUESTION review $PF_REL failed at ${PF_HEAD:0:12}: fix it, or waive $PF_QUESTION" ;;
        pass) proof_owed close "waive:$PF_QUESTION" "passing reading" ;;
      esac
    fi
    PF_FIELDS=""; [ -z "$PF_QUESTION" ] || PF_FIELDS=" question=$PF_QUESTION reader=$PF_READER result=$PF_RESULT scope=$PF_SCOPE ($PF_ROLE)"
    say "proof-add — kind=$PF_KIND head=$PF_HEAD evidence=$PF_REL$PF_FIELDS${PF_OWED:+ owed=$PF_OWED}: written to the run's log${PF_BACK:+; $PF_BACK back to pending, its launch taken back there}."
    [ -z "$PF_OWED" ] || say "proof-add — the whole run left $PF_OWED red: each is owed until a later landing runs it green (a fix row), or proof-add inherited <suite> finds it red at the base too."
    [ -z "$PF_PLANL" ] || printf '%s\n' "$PF_PLANL" | while IFS= read -r _pf_l; do say "proof-add — $_pf_l (in the run's log)"; done
    [ -n "$PF_HELD" ] && say "proof-add — $PF_HELD stays active until every question it carries is read at ${PF_HEAD:0:12}; it returns to pending on that review."
    [ -n "$PF_NONE" ] && say "proof-add — no active live review row holds $PF_REL in its Files: $PF_NONE stays active, nothing was returned to pending. If this record is that pass, its Files name another record: write the record under that name, or amend the row's Files."
    exit 0
  }

  # waive_criterion -> the criterion WV_Q waived on WV_REPLY's words (and WV_WHY_RAW's why): 0 written, 1 refused, 2
  # when the libraries or the run's log cannot be reached.
  waive_criterion() {
    local who head why known ac="$WV_Q"
    if ! declare -F user_said >/dev/null 2>&1 && [ -f "$BIONIC_LIB/said.sh" ]; then . "$BIONIC_LIB/said.sh"; fi
    _proof_reader_load
    if ! declare -F user_said >/dev/null 2>&1 || ! declare -F reader_criteria >/dev/null 2>&1; then
      die "REFUSED — a criterion's waiver needs lib/said.sh and lib/reader.sh, which cannot be loaded from $BIONIC_LIB; nothing is written."
      return 2
    fi
    plan_verb_open waive
    known="$(reader_criteria "$PV_PLAN" 2>/dev/null)"
    case $'\n'"$known"$'\n' in
      *$'\n'"$ac"$'\n'*) : ;;
      *) die "REFUSED — '$(clean "$ac")' is neither a question to waive (evidence, adversarial, structure or all) nor a criterion $PV_PLAN names; nothing is written."
         return 1 ;;
    esac
    who="$(git -C "$PV_REPO" config user.name 2>/dev/null)"
    if [ -z "$who" ] || ! plan_verb_value_ok "$who"; then
      die "REFUSED — the project has no usable git user name (git config user.name) to record as the one who waived; nothing is written."
      return 1
    fi
    why="$(deferral_fold "$WV_WHY_RAW")"
    WV_REPLY="$(poker_one_line "$WV_REPLY")"
    case "$WV_REPLY$why" in
      *'|'*|*$'\n'*|*$'\r'*)
        die "REFUSED — a waiver's words and why are fields of the run's log, which a '|' or a line break would split; give them without one. Nothing is written."
        return 1 ;;
    esac
    user_said "$WV_REPLY" "$PV_PLAN"; WV_SAID=$?
    if [ "$WV_SAID" -ne 0 ]; then
      said_refuse "$WV_SAID" "$(said_fold "$WV_REPLY")" "a waiver"
      return 1
    fi
    head="$(proof_branch_head "$PV_PLAN" "$PV_REPO" 2>/dev/null)" || head=""
    case "$head" in *[!0-9a-f]*) head="" ;; esac
    proof_waiver_event "$PV_PLAN" "ac=$ac" ${head:+"head=$head"} "by=$who" "said=$(said_fold "$WV_REPLY")" ${why:+"why=$why"} \
      || { die "REFUSED — the waiver of $ac could not be written to the run's log of $PV_PLAN (no record directory beside the plan, or the log cannot be written)."; return 2; }
    poker_owed_close "$PV_REPO" "waive:$ac" "waive"
    say "waive — $ac waived on the user's words, by $(clean "$who"): one waiver event in the run's log."
  }

  # THE WAIVER. The user's act, on their reply: one waiver event in the run's log,
  #
  #   waiver question=<q> head=<working head> by=<git user.name> said=<reply>
  #
  # covering that question up to the head the plan's working branch's ref names, the head the judge
  # (lib/proof.sh `facts_state`) is asked about. The log's own order makes a fact written after it newer than it.
  # `waive all` writes three, evidence, adversarial and structure, in that order, on words lib/said.sh `user_said` finds
  # the person typed. The plan is not written. The regression is never waived: it runs once after the build.
  #
  # A CRITERION IS WAIVED BY THE SAME ONE WRITER, its event naming it where a question's names the question:
  #
  #   waiver ac=<criterion> [head=<working head>] by=<git user.name> said=<the words> [why=<why>]
  #
  # which the reader's cell answer reads as the criterion discharged by a waiver. The criterion is one the plan names
  # (reader_criteria), and the words are held to lib/said.sh `user_said` as a move's are, since nobody but the user lets
  # a criterion go; the head is written when the working branch names one and is not required, for a criterion is not
  # judged at a head. Its ask, `waive:<criterion>`, the gate's matrix arm opens, closes as a question's does.
  poker_verb_waive() {
    if ! { declare -F proof_waiver_event >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_waiver_event >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    if ! proof_question_ok "$WV_Q" waive; then
      waive_criterion
      exit $?
    fi
    WV_QS="$WV_Q"; [ "$WV_Q" != all ] || WV_QS="$PROOF_QUESTIONS"
    WV_REPLY="$(poker_one_line "$WV_REPLY")"
    case "$WV_REPLY" in
      *$'\n'*|*$'\r'*)
        die "REFUSED — a waiver is one line, and the reply carries a line break; nothing is written."
        exit 1 ;;
    esac
    plan_verb_open waive
    WV_WHO="$(git -C "$PV_REPO" config user.name 2>/dev/null)"
    if [ -z "$WV_WHO" ] || ! plan_verb_value_ok "$WV_WHO"; then
      die "REFUSED — the project has no usable git user name (git config user.name) to record as the one who waived; the plan is unchanged."
      exit 1
    fi
    # THE HEAD IS THE WORKING BRANCH'S REF (wave-36 T12; D13, AC-7.4; C30): lib/proof.sh `proof_branch_head`, the head
    # the judge reads the waiver against.
    WV_WB="$(plan_working_branch "$PV_PLAN")"
    WV_HEAD="$(proof_branch_head "$PV_PLAN" "$PV_REPO")" || WV_HEAD=""
    case "$WV_HEAD" in
      [0-9a-f]*) : ;;
      *)
        die "REFUSED — the plan's working-branch ${WV_WB:-(none named)} names no commit in $PV_REPO, so there is no head to waive at; the plan is unchanged."
        exit 1 ;;
    esac
    case "$WV_REPLY" in
      *'|'*)
        die "REFUSED — a waiver's reply is one field of the run's log, which a '|' would split; give it without one. Nothing is written."
        exit 1 ;;
    esac
    # A QUESTION'S WAIVER LETS A FAILED REVIEW THROUGH ON THE PERSON'S WORD, held to lib/said.sh `user_said` as a criterion's is.
    if ! declare -F user_said >/dev/null 2>&1 && [ -f "$BIONIC_LIB/said.sh" ]; then . "$BIONIC_LIB/said.sh"; fi
    if ! declare -F user_said >/dev/null 2>&1; then
      die "REFUSED — what the user typed is read by lib/said.sh, which cannot be loaded from $BIONIC_LIB; nothing is written. run again: session-poker.sh waive $WV_Q '<the user's words>'"
      exit 2
    fi
    user_said "$WV_REPLY" "$PV_PLAN"; WV_SAID=$?
    [ "$WV_SAID" -eq 0 ] || { said_refuse "$WV_SAID" "$(said_fold "$WV_REPLY")" "a waiver"; exit 1; }
    WV_READS="$(review_readings "$PV_PLAN")" \
      || { die "REFUSED — the run's facts could not be read, so the findings a waiver closes are not known; nothing is written. Run again: bash ${HOOK_DIR}/session-poker.sh waive $WV_Q"; exit 2; }
    for _wv_q in $WV_QS; do
      proof_waiver_event "$PV_PLAN" "question=$_wv_q" "head=$WV_HEAD" "by=$WV_WHO" "said=$WV_REPLY" \
        || { die "REFUSED — the $_wv_q waiver could not be written to the run's log of $PV_PLAN (no record directory beside the plan, or the log cannot be written)."; exit 2; }
      poker_owed_close "$PV_REPO" "waive:$_wv_q" "waive"
      waive_owed_findings "$PV_PLAN" "$PV_REPO" "$_wv_q" "$WV_READS"
      say "waive — question=$_wv_q head=$WV_HEAD by $WV_WHO: written to the run's log."
    done
    exit 0
  }

  # A MOVE IS THE USER'S PROVEN WORD (wave-28 T42; REQ-8 AC-8.9, D34). A registered finding — one whose
  # record a `proved:` line names as its evidence — is moved across the line, to defer or to fix, only
  # on words lib/said.sh `user_said` finds in a prompt the user typed in this session's transcript (a
  # tool's result, a teammate's or another session's message, a hook's context and the orchestrator's
  # own text never count; rc 2, no transcript, refuses too; the words stand as WHOLE WORDS and are at
  # least SAID_MIN_WORDS (three) of them unless they are a whole typed prompt, rc 3 refusing the short ones, T66). An S1, at the rating every read gives it
  # (lib/proof.sh `proof_finding_rating`), is never deferred. The move is one finding event in the run's log; the plan
  # is not written:
  #
  #   finding ref=<record>#<n> to=<defer|fix> by=<git user.name> words=<words> session=<sid> why=<why>
  #           [severity=<S> reach=<reach> title=<title> stated=<sentence>]          (the bracketed fields: a deferral)
  #
  # the words are looked for in every session the plan records, then this one (wave-36 T9; D10), and
  # session= names the one whose transcript holds them (lib/said.sh SAID_SESSION);
  #
  # the words folded to one line by lib/said.sh's own fold (`said_fold`, the rule the check is made
  # through; the verb passes the raw words to `user_said`), the why by `deferral_fold` (the same fold), both escaped as a
  # deferral's sentence is (`deferral_escape`); a move to defer carries the finding's rating and title, so it is the
  # finding's deferral as well, and its changelog sentence when one is given. Every read then takes the priority the
  # last move gave it. A `|` in the words, the why or the sentence would split the event's field, and is refused.
  #
  # THE THIRD MOVE (wave-36 T8; REQ-3 AC-3.4, D9; ADR-056). `finding-move <record>#<n> fixed <row>` says a row of the
  # plan's `## Tasks` table fixed the finding: landed before the reading, beside it, or still to land. It is a fact
  # about the table, not a ruling across the line, so it takes no words; the row must be one the table carries. It
  # writes, in the same place:
  #
  #   moved: <record>#<n> to=fixed row=<T> by=<git user.name> at=<ISO-UTC>
  #
  # The finding reads fix until the row lands green, and then fixed (lib/proof.sh `proof_fixed`, whatever the row's
  # ancestry); the row needs no born marker, so it counts against no fix-cap. A row now answers the finding, so its
  # owed item closes, as `task-add --born` closes it. Its event is `finding ref=<record>#<n> to=fixed row=<T> by=<who>`.
  # Main thread only, by the existing arm's list (lib/walls.sh `_wall_poker_contract_verb`).
  poker_verb_finding_move() {
    if ! { declare -F proof_finding_rating >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F _proof_moved_to >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    if ! declare -F user_said >/dev/null 2>&1 && [ -f "$BIONIC_LIB/said.sh" ]; then
      . "$BIONIC_LIB/said.sh"
    fi
    if [ -z "$FM_ROW" ] && ! declare -F user_said >/dev/null 2>&1; then
      die "REFUSED — what the user typed is read by lib/said.sh, which cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    if [ -z "$FM_ROW" ]; then FM_WORDS="$(said_fold "$FM_RAW")"; FM_WHY="$(deferral_fold "$FM_WHY_RAW")"; fi
    FM_SENT=""; [ -z "$FM_SENT_RAW" ] || FM_SENT="$(deferral_fold "$FM_SENT_RAW")"
    case "${FM_WORDS:-}${FM_WHY:-}$FM_SENT" in
      *'|'*)
        die "REFUSED — the words, the why or the sentence hold a '|', which would split the move's field in the run's log; give them without one. Nothing is written."
        exit 1 ;;
    esac
    if [ "$FM_SENT" = "-" ]; then
      die "REFUSED — '-' is what the continuation writes for a deferral with no sentence, so it cannot be one; nothing is written."
      exit 1
    fi
    plan_verb_open finding-move
    FM_REC="${FM_ID%#*}"; FM_N="${FM_ID##*#}"
    FM_READS="$(review_readings "$PV_PLAN")" \
      || { die "REFUSED — the run's facts could not be read, so the reviews it registers are not known; the plan is unchanged. Run again: bash ${HOOK_DIR}/session-poker.sh finding-move with the same words"; exit 2; }
    if ! printf '%s\n' "$FM_READS" | awk -F'\t' -v ev="$FM_REC" '$1 == ev { hit = 1 } END { exit !hit }'; then
      die "REFUSED — $(clean "$FM_REC") is no review the run registered (no review proof names it as its evidence), and only a registered finding is moved; the plan is unchanged."
      exit 1
    fi
    FM_DOCS="$(docs_root "$PV_REPO")"
    FM_F="$(proof_findings "$FM_DOCS/$FM_REC" 2>/dev/null | awk -F'\t' -v n="$FM_N" '$1 == n { print; exit }')"
    if [ -z "$FM_F" ]; then
      die "REFUSED — the review $(clean "$FM_REC") holds no finding $FM_N (read as $(clean "$FM_DOCS/$FM_REC")); the plan is unchanged."
      exit 1
    fi
    IFS='	' read -r _ FM_S FM_R _ _ _ FM_TITLE <<FM_FINDING
$FM_F
FM_FINDING
    FM_RATED="$(proof_finding_rating "$PV_PLAN" "$FM_ID" "$FM_S" "$FM_R")" \
      || { die "REFUSED — the run's facts could not be read, so the finding's moves are not known; nothing is written. Run again: bash ${HOOK_DIR}/session-poker.sh finding-move with the same words"; exit 2; }
    set -- $FM_RATED
    FM_S="$1"; FM_R="$2"
    if [ "$FM_TO" = defer ] && [ "$FM_S" = S1 ]; then
      die "REFUSED — $(clean "$FM_ID") is rated S1 $FM_R, and an S1 is never deferred, whoever asks; the plan is unchanged."
      exit 1
    fi
    if [ -n "$FM_ROW" ] && ! units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' -v r="$FM_ROW" '$1 == r { f = 1 } END { exit !f }'; then
      die "REFUSED — $FM_ROW is no row of the ## Tasks table of $PV_PLAN, and a finding is $([ "$FM_TO" = carried ] && echo carried || echo fixed) only by a row the plan carries; the plan is unchanged."
      exit 1
    fi
    # A FINDING A LANDING SETTLED IS THE LANDING'S (lib/line.sh `line_settle`): the move is a correction of a cell the
    # landing wrote, and is refused naming that landing.
    { [ -n "${_LINE_FIELDS_AWK:-}" ] || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1; }
    if declare -F line_settled_by >/dev/null 2>&1 && FM_BY_LANDING="$(line_settled_by "$PV_PLAN" findings "$FM_ID")"; then
      die "REFUSED — $(clean "$FM_ID") was settled by the landing of ${FM_BY_LANDING% *} at ${FM_BY_LANDING#* }: that landing wrote it fixed and closed its ask, so no move corrects it; the plan is unchanged."
      exit 1
    fi
    # A CARRY TO A ROW THAT WILL NOT LAND AGAIN closes at once: to a landed row it is that row's fix, written as a move
    # to fixed; to a dropped row nothing will land, so only its ask closes and the line records the person's choice.
    FM_ROW_ST=""
    [ "$FM_TO" != carried ] || FM_ROW_ST="$(units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' -v r="$FM_ROW" '$1 == r { print $10; exit }')"
    [ "$FM_ROW_ST" != landed ] || FM_TO=fixed
    FM_WHO="$(deferral_fold "$(git -C "$PV_REPO" config user.name 2>/dev/null)")"
    if [ -z "$FM_WHO" ]; then
      die "REFUSED — no git user.name is set for $PV_REPO, and a move records who made it; set it, then move again. The plan is unchanged."
      exit 1
    fi
    # A SENTENCE MOVES NOTHING: it is the orchestrator's, given before the release card, so it asks for no words. Its
    # event restates where the finding stands (its newest `to=`, which the reader's standing fact keeps): none, the
    # registration's deferral or a person's defer. A finding moved to fix or to a row is no carry, and is refused.
    if [ "$FM_TO" = stated ]; then
      _proof_findings_load "$PV_PLAN" || { die "REFUSED — the run's facts could not be read; nothing is written. Run again: bash ${HOOK_DIR}/session-poker.sh finding-move with the same sentence"; exit 2; }
      FM_STAND="$(printf '%s\n' "$_PROOF_FINDINGS" | awk -v id="$FM_ID" "$(proof_bind_awk)"'proof_bound($0) == id { t = proof_fkv($0, "to") } END { print t }')"
      case "$FM_STAND" in
        ''|deferred|defer) : ;;
        *) die "REFUSED — $(clean "$FM_ID") stands moved to $FM_STAND, and a Known-limits sentence is a carried finding's; nothing is written. A move to fix or to a row is no carry: state the sentence of a deferred finding, or move this one again with finding-move."; exit 1 ;;
      esac
      proof_finding_event "$PV_PLAN" "ref=$FM_ID" ${FM_STAND:+"to=$FM_STAND"} "stated=$(deferral_escape "$FM_SENT")" "by=$FM_WHO" \
        || { die "REFUSED — the sentence of $(clean "$FM_ID") could not be written to the run's log of $PV_PLAN; nothing is written. Run again: bash ${HOOK_DIR}/session-poker.sh finding-move with the same sentence"; exit 2; }
      say "finding-move — $(clean "$FM_ID") states its Known-limits sentence, by $(clean "$FM_WHO"); it stands where it stood${FM_STAND:+ ($FM_STAND)}, and the release card draws it."
      exit 0
    fi
    if [ -z "$FM_ROW" ]; then
      user_said "$FM_RAW" "$PV_PLAN"; FM_SAID=$?
      if [ "$FM_SAID" -ne 0 ]; then
        said_refuse "$FM_SAID" "$FM_WORDS" "a move"
        exit 1
      fi
    fi
    if [ -n "$FM_ROW" ]; then
      FM_EV="to=$FM_TO row=$FM_ROW by=$FM_WHO"
      proof_finding_event "$PV_PLAN" "ref=$FM_ID" "to=$FM_TO" "row=$FM_ROW" "by=$FM_WHO"
    elif [ "$FM_TO" = defer ]; then
      FM_EV="to=defer by=$FM_WHO, its deferral${FM_SENT:+ and its sentence}"
      proof_finding_event "$PV_PLAN" "ref=$FM_ID" to=defer "by=$FM_WHO" "words=$(deferral_escape "$FM_WORDS")" "session=$SAID_SESSION" \
        "why=$(deferral_escape "$FM_WHY")" "severity=$FM_S" "reach=$FM_R" "title=$(printf '%s' "$FM_TITLE" | tr '"' "'")" \
        ${FM_SENT:+"stated=$(deferral_escape "$FM_SENT")"}
    else
      FM_EV="to=$FM_TO by=$FM_WHO"
      proof_finding_event "$PV_PLAN" "ref=$FM_ID" "to=$FM_TO" "by=$FM_WHO" "words=$(deferral_escape "$FM_WORDS")" "session=$SAID_SESSION" \
        "why=$(deferral_escape "$FM_WHY")"
    fi || { die "REFUSED — the move of $(clean "$FM_ID") could not be written to the run's log of $PV_PLAN (no record directory beside the plan, or the log cannot be written)."; exit 2; }
    proof_owed close "$(carry_owed_key "$FM_ID")" "finding-move $FM_TO"
    # A DEFERRAL IS THE USER'S ANSWER, NOT THE END OF THE ASK: the finding is carried, so its item stays open answered
    # carry and waits on the release approval card, whose reply closes it.
    [ "$FM_TO" != defer ] || proof_owed answer "$(finding_owed_key "$FM_ID")" carry "release card"
    # A CARRY TO A ROW IS AN ANSWER, NOT AN END: the item stays open answered carry with the row named, and the
    # landing of that row closes it. The line is a record of the person's choice only; it is no move to fixed, so
    # the finding reads as before until the row lands.
    if [ "$FM_TO" = carried ] && [ "$FM_ROW_ST" = dropped ]; then
      poker_owed_close "$PV_REPO" "$(finding_owed_key "$FM_ID")" "finding-move carried $FM_ROW, dropped"
      say "finding-move — $(clean "$FM_ID") carried to $FM_ROW, by $(clean "$FM_WHO"): $FM_ROW is dropped and will not land, so its ask is closed now; the finding reads as before."
      exit 0
    fi
    if [ "$FM_TO" = carried ]; then
      proof_owed answer "$(finding_owed_key "$FM_ID")" carry "$FM_ROW lands"
      say "finding-move — $(clean "$FM_ID") carried to $FM_ROW, by $(clean "$FM_WHO"): its move is in the run's log. The finding stays open and closes when $FM_ROW lands."
      exit 0
    fi
    if [ -n "$FM_ROW" ]; then
      poker_owed_close "$PV_REPO" "$(finding_owed_key "$FM_ID")" "finding-move fixed $FM_ROW"
      [ "$FM_ROW_ST" != landed ] || say "finding-move — $(clean "$FM_ID") carried to $FM_ROW, which has landed: the carry is that row's fix, written as a move to fixed, and its ask is closed now."
      say "finding-move — $(clean "$FM_ID") fixed by $FM_ROW, by $(clean "$FM_WHO"): its move is in the run's log. It reads fixed once $FM_ROW has landed green, and counts against no fix-cap."
      exit 0
    fi
    say "finding-move — $(clean "$FM_ID") to $FM_TO on the user's words, by $(clean "$FM_WHO"): its move is in the run's log ($(clean "$FM_EV"))."
    exit 0
  }

  # THE FINDINGS THE RELEASE APPROVAL CARD READS. One pass over every registered reading (each record a review proof
  # with a question names as its evidence, its last such proof giving its question and head) prints one line per finding:
  #
  #   finding <record>#<n> <S> user-facing=<on|off> record=<record> at=<path:line|-> row=<T<k>[,…]|—>
  #           state=<open|fixed|deferred|accepted> [stated="<sentence>"|stated=-] title="<title>"
  #
  # the state read as the judge reads it: fixed when a row born of it landed green at or after the reading's head, or
  # the row its newest move to fixed names landed green whatever its ancestry (lib/proof.sh `proof_fixed`); else by the
  # priority the moves give it (`proof_finding_rating`): fix is open, defer is deferred, note is accepted. row= names
  # the rows born of it and the row a move to fixed names. An open finding no row answers and no ruling has moved
  # needs the person, and gets one owed item, `finding_owed_key` (lib/owed.sh; opening is idempotent per key); a
  # deferral no person ruled is a carry, and gets its carry item. A reading's debt: lines go to the run's debt ledger
  # through `debt add`, run as a child. Nothing in the plan is written. The plan and the checkout are the caller's
  # (PV_PLAN, PV_REPO, from plan_verb_open). Facts that cannot be read are said on stderr, and the return is 2.
  finding_disposition() {
    { declare -F proof_fixed >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
      && declare -F proof_fixed >/dev/null 2>&1 \
      || { die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; no finding is read."; return 2; }
    DSP_DOCS="$(docs_root "$PV_REPO")"
    _proof_findings_load "$PV_PLAN" && DSP_FEV="$_PROOF_FINDINGS" && DSP_FIXED="$(proof_fixed "$PV_PLAN" "$PV_REPO")" \
      || { die "REFUSED — the run's facts could not be read, so no finding is read or opened. Run again: bash ${HOOK_DIR}/session-poker.sh release-approval"; return 2; }
    DSP_BORN="$(units_born_findings "$PV_PLAN" 2>/dev/null)" || DSP_BORN=""
    DSP_READS="$(review_readings "$PV_PLAN")" \
      || { die "REFUSED — the run's facts could not be read, so no finding is read or opened. Run again: bash ${HOOK_DIR}/session-poker.sh release-approval"; return 2; }
    # EVERY FINDING'S EVENTS READ IN ONE PASS, and the rows born of each in one more: `<id> TAB <newest move> TAB <the row a
    # move to fixed names> TAB <1 when the run deferred it> TAB <its newest stated sentence, unescaped>` and `<id> TAB
    # <rows>`, so a finding is answered from the two by its id with no process started. Each field is what the one-finding
    # reads give (the move's newest word and row, proof_finding_stated's sentence and exit, the born rows comma-joined).
    DSP_FMOVES="$(printf '%s\n' "$DSP_FEV" | awk "$(proof_bind_awk)"'
  function unesc(s,   o, i, c) { o = ""; for (i = 1; i <= length(s); i++) { c = substr(s, i, 1); if (c == "\\" && i < length(s)) { i++; c = substr(s, i, 1) } o = o c }; return o }
  { b = proof_bound($0); if (b == "") next
    if (!(b in seen)) { seen[b] = 1; ord[++n] = b }
    m = proof_move_of($0); if (m != "") { to[b] = m; r[b] = proof_move_row($0) }
    if (proof_defers($0)) d[b] = 1
    v = proof_fkv($0, "stated"); if (v != "") st[b] = v }
  END { for (i = 1; i <= n; i++) { b = ord[i]; print b "\t" to[b] "\t" r[b] "\t" ((b in d) ? 1 : 0) "\t" unesc(st[b]) } }')"
    DSP_BROWS="$(printf '%s\n' "$DSP_BORN" | awk -F'\t' '$3 != "" { if ($3 in v) v[$3] = v[$3] "," $1; else { v[$3] = $1; ord[++n] = $3 } }
  END { for (i = 1; i <= n; i++) print ord[i] "\t" v[ord[i]] }')"
    while IFS='	' read -r DSP_EV DSP_Q DSP_H; do
      [ -n "$DSP_EV" ] || continue
      if ! DSP_GOT="$(proof_findings "$DSP_DOCS/$DSP_EV" 2>&1)"; then
        say "review $(clean "$DSP_EV") ($DSP_Q) cannot be read: $(clean "$DSP_GOT")"
        continue
      fi
      _proof_fixed_var "$DSP_FIXED" "$DSP_EV" "$DSP_H" "$PV_REPO"
      DSP_DEBT=0
      while IFS='	' read -r DSP_N DSP_S DSP_R DSP_W _ _ DSP_T; do
        [ -n "$DSP_N" ] || continue
        [ "$DSP_N" != debt ] || { DSP_DEBT=1; continue; }
        DSP_FID="$DSP_EV#$DSP_N"
        # The finding's newest whole move, the row a move to fixed names and its stated sentence, from the one pass above.
        DSP_MOVED=""; DSP_MV=""; DSP_DEF=0; DSP_ST=""; DSP_ROWS=""
        case $'\n'"$DSP_FMOVES" in
          *$'\n'"$DSP_FID"$'\t'*)
            DSP_RX=$'\n'"$DSP_FMOVES"; DSP_RX="${DSP_RX#*$'\n'"$DSP_FID"$'\t'}"; DSP_RX="${DSP_RX%%$'\n'*}"
            DSP_MOVED="${DSP_RX%%$'\t'*}"; DSP_RX="${DSP_RX#*$'\t'}"; DSP_MV="${DSP_RX%%$'\t'*}"; DSP_RX="${DSP_RX#*$'\t'}"
            DSP_DEF="${DSP_RX%%$'\t'*}"; DSP_ST="${DSP_RX#*$'\t'}" ;;
        esac
        case $'\n'"$DSP_BROWS" in
          *$'\n'"$DSP_FID"$'\t'*) DSP_RX=$'\n'"$DSP_BROWS"; DSP_RX="${DSP_RX#*$'\n'"$DSP_FID"$'\t'}"; DSP_ROWS="${DSP_RX%%$'\n'*}" ;;
        esac
        _proof_rating_apply "$DSP_MOVED" "$DSP_S" "$DSP_R"
        set -- $_PROOF_RATING
        DSP_P="${3:-}"
        if [ "$DSP_MOVED" = fixed ]; then
          case ",$DSP_ROWS," in *",$DSP_MV,"*) : ;; *) DSP_ROWS="${DSP_ROWS:+$DSP_ROWS,}$DSP_MV" ;; esac
        fi
        DSP_STATED=""
        case "$_PROOF_FIXED_IDS" in
          *$'\n'"$DSP_FID"$'\n'*) DSP_STATE=fixed ;;
          *)
            case "$DSP_P" in
              fix)
                DSP_STATE=open
                if [ -z "$DSP_ROWS" ] && [ -z "$DSP_MOVED" ] && declare -F owed_open >/dev/null 2>&1; then
                  if [ "$DSP_S" = S1 ]; then DSP_DEC="the person's: fix it or waive $DSP_Q (an S1 is never deferred)"
                  else DSP_DEC="the person's: fix it, defer it, or waive $DSP_Q"; fi
                  OWED_ROOT="$PV_REPO" owed_open "$(finding_owed_key "$DSP_FID")" "Finding $DSP_S needs a ruling" \
                    "$(clean "$DSP_FID") $DSP_S $DSP_R: $(clean "$DSP_T") — $DSP_DEC" >/dev/null 2>&1 || :
                fi ;;
              defer)
                DSP_STATE=deferred
                # A DEFERRAL NO PERSON RULED IS A CARRY THE RUN CHOSE: the reader's rating deferred it and the run carries
                # it on, so it is an ask until the release approval card rules it. A move to defer is the person's own
                # ruling (finding-move takes their words), and owes nothing more.
                [ -n "$DSP_MOVED" ] \
                  || proof_owed open "$(carry_owed_key "$DSP_FID")" "Carried $DSP_S finding" \
                       "$(clean "$DSP_FID") $DSP_S $DSP_R: $(clean "$DSP_T") — carried, not fixed; the release approval card rules it"
                [ "$DSP_DEF" != 1 ] || DSP_STATED="$DSP_ST" ;;
              *) DSP_STATE=accepted ;;
            esac ;;
        esac
        DSP_LINE="finding $DSP_FID $DSP_S user-facing=$DSP_R record=$DSP_EV at=$DSP_W row=${DSP_ROWS:-—} state=$DSP_STATE"
        if [ "$DSP_STATE" = deferred ]; then
          if [ -n "$DSP_STATED" ]; then DSP_LINE="$DSP_LINE stated=\"$DSP_STATED\""; else DSP_LINE="$DSP_LINE stated=-"; fi
        fi
        say "$DSP_LINE title=\"$DSP_T\""
      done <<DSP_FINDINGS
$DSP_GOT
DSP_FINDINGS
      # A RECORD'S DEBT LINES ARE ADDED BY THE DEBT VERB ITSELF, run in a subshell of this one with the operands the
      # command line would hand it, so the ledger is written as `debt add <record> <plan>` writes it, over the facts this
      # command already holds, and no poker process is started for it.
      if [ "$DSP_DEBT" = 1 ]; then
        ( cd "$PV_REPO" || exit 2
          DEBT_SUB=add DEBT_A="$DSP_EV" DEBT_B="" DEBT_C="" DEBT_PLAN_ARG="$PV_PLAN" poker_verb_debt ) 2>&1 || :
      fi
    done <<DSP_READINGS
$DSP_READS
DSP_READINGS
    return 0
  }

  # THE RELEASE CHECK (wave-27 T16; D12). A project may name one command in `.bionic/config.yaml`
  # under `release-check:`. This verb runs it as the last release holds it, through the one runner
  # (lib/worktree.sh `worktree_check_run`), with BIONIC_CHECK_BASE at the last release and
  # BIONIC_CHECK_HEAD at the head of the checkout of the plan's working branch.
  # THE LAST RELEASE is the nearest tag reachable from the plan's `integration-branch:` that is a
  # PROPER ancestor of the working head (the fewest commits from it to the head): a tag on the head,
  # or on a commit that is not on the head's history, is no base, for the range it opens would hold
  # nothing or the wrong thing (wave-27 T31; review pass 22 S2). With none, the plan's `base-sha:`.
  # A range holding no commit is refused, never judged.
  # EVERY RUN KEEPS ITS LOG AND ITS FACT (T31; S3): `record/<wave>/release-check-<head>.log`, the
  # n-th run at one head `release-check-<head>-<n>.log`, so no run overwrites another's; it opens
  # with a `check-changed: <path>` line per tracked path the command names as a word and the range
  # changes (B1: the check's own files are covered code, and the user is told when they moved), then
  # `head=<40-hex> rc=<exit>`. On exit 0 the `kind=check` proof line names it (lib/proof.sh
  # `proof_attested` holds the log against the checkout); on any other exit the command's output is
  # printed and the line carries ` result=fail`, which the judge reads as the head's last word. With
  # no key it runs, writes and prints nothing.
  poker_verb_release_check() {
    RC_CMD="$(config_value "$(project_root "$PWD")" release-check "" 2>/dev/null)"
    [ -n "$RC_CMD" ] || exit 0
    if ! { declare -F proof_event >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_event >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; nothing was run and the plan is unchanged."
      exit 2
    fi
    plan_verb_open release-check
    RC_WB="$(plan_working_branch "$PV_PLAN")"
    RC_CO=""; [ -z "$RC_WB" ] || RC_CO="$(proof_checkout "$PV_REPO" "$RC_WB")" || RC_CO=""
    RC_HEAD=""; [ -z "$RC_CO" ] || RC_HEAD="$(git -C "$RC_CO" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)"
    case "$RC_HEAD" in
      [0-9a-f]*) : ;;
      *)
        die "REFUSED — no checkout of $PV_REPO has the plan's working-branch ${RC_WB:-(none named)} checked out, so there is no head to check; nothing was run and the plan is unchanged."
        exit 1 ;;
    esac
    # THE COMMAND RUNS ON THE HEAD ALONE: the log says it ran at that head, and a command that reads
    # the working files would read uncommitted changes as the head's. The index is refreshed first,
    # so a file whose stat moved and whose content did not is not called a change (T31; S4).
    git -C "$RC_CO" update-index -q --refresh >/dev/null 2>&1
    if ! git -C "$RC_CO" diff-index --quiet HEAD -- 2>/dev/null \
       || [ -n "$(git -C "$RC_CO" ls-files --others --exclude-standard 2>/dev/null)" ]; then
      die "REFUSED — the working checkout $RC_CO has uncommitted changes, so the check would not read the head $RC_HEAD alone; commit them and run release-check again. Nothing was run and the plan is unchanged."
      exit 1
    fi
    release_base "$PV_PLAN" "$RC_CO" "$RC_HEAD"
    RC_IB="$RB_IB"; RC_BASE="$RB_BASE"; RC_FROM="$RB_FROM"; RC_BS="$RB_BS"
    if [ -z "$RC_BASE" ]; then
      die "REFUSED — no tag reachable from the plan's integration-branch (${RC_IB:-none named}) is a proper ancestor of the working head and its base-sha (${RC_BS:-none}) is no commit here, so the release range has no start; nothing was run and the plan is unchanged."
      exit 1
    fi
    if [ "$(git -C "$RC_CO" rev-list --count "$RC_BASE..$RC_HEAD" 2>/dev/null)" = 0 ]; then
      die "REFUSED — the release range ${RC_BASE:0:12}..${RC_HEAD:0:12} ($RC_FROM) holds no commit, so there is nothing for the check to judge; name the last release as the plan's base-sha, or tag it. Nothing was run and the plan is unchanged."
      exit 1
    fi
    # THE CHECK'S OWN FILES (T31; review pass 22 B1). Each word of the command that names one tracked
    # file, read literally (no glob, no shell parsing), and that the range changes. The case arm
    # opens with `(`: bash 3.2, the shebang's interpreter, reads an unopened arm's `)` inside a
    # `$( )` as the substitution's end (T80).
    RC_CHG="$(set -f
      for RC_W in $RC_CMD; do
        RC_P="$(git --literal-pathspecs -C "$RC_CO" ls-files --full-name --error-unmatch -- "$RC_W" 2>/dev/null)" || continue
        case "$RC_P" in (''|*"
"*) continue ;; esac
        git --literal-pathspecs -C "$RC_CO" diff --quiet "$RC_BASE" "$RC_HEAD" -- "$RC_P" >/dev/null 2>&1 \
          || printf 'check-changed: %s\n' "$RC_P"
      done | awk '!seen[$0]++')"
    # THE JUDGE IS THE RELEASE BASE (lib/worktree.sh `worktree_check_run`): the command runs as the range's start
    # holds it, never as the head being judged holds it, so a head cannot pass by rewriting its own check.
    worktree_check_run "$PV_REPO" "$PV_PLAN" "$RC_BASE" "$RC_BASE" "$RC_HEAD" "$RC_CO"; RC_RUN=$?
    [ "$RC_RUN" -ne 1 ] || exit 0
    if [ "$RC_RUN" -ne 0 ]; then
      die "REFUSED — the declared release-check ($(clean "$RC_CMD")) cannot be run as the release base ${RC_BASE:0:12} ($RC_FROM) holds it: $(clean "$WT_CHECK_OUT"). Nothing was run and the plan is unchanged."
      exit 1
    fi
    RC_OUT="$WT_CHECK_OUT"; RC_RC="$WT_CHECK_RC"; RC_JUDGED="judged-by=${WT_CHECK_JUDGE:0:12}"
    # WHAT THE CHECK LEFT (wave-27 T67; review pass 46 N7), looked at as `land` looks after its own run
    # (lib/worktree.sh `_wt_check_left`): the checkout's HEAD where it was, and no tracked file changed
    # (the index refreshed first). A check that moved either is refused as a failing check is: its log,
    # and a result=fail check fact at the head it ran on.
    git -C "$RC_CO" update-index -q --refresh >/dev/null 2>&1
    RC_LEFT=""; RC_NOW="$(git -C "$RC_CO" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)"
    [ "$RC_NOW" = "$RC_HEAD" ] || RC_LEFT="moved the head of $RC_CO from ${RC_HEAD:0:12} to ${RC_NOW:-<none>}"
    git -C "$RC_CO" diff-index --quiet HEAD -- 2>/dev/null \
      || RC_LEFT="${RC_LEFT:+$RC_LEFT and }left tracked files changed in $RC_CO (git -C $RC_CO status)"
    RC_WAVE="$(proof_plan_slug "$PV_PLAN")"
    RC_DOCS="$(docs_root "$PV_REPO")"
    RC_REL="record/$RC_WAVE/release-check-$RC_HEAD.log"; RC_NTH=1
    while [ -e "$RC_DOCS/$RC_REL" ]; do RC_NTH=$((RC_NTH + 1)); RC_REL="record/$RC_WAVE/release-check-$RC_HEAD-$RC_NTH.log"; done
    RC_LOG="$RC_DOCS/$RC_REL"
    RC_SAID=""; [ -z "$RC_CHG" ] || RC_SAID=" $(printf '%s\n' "$RC_CHG" | tr '\n' ' ' | sed 's/ $//')"
    if [ "$RC_RC" -ne 0 ]; then
      [ -z "$RC_OUT" ] || printf '%s\n' "$RC_OUT"
    fi
    if ! mkdir -p "${RC_LOG%/*}" 2>/dev/null \
       || ! { [ -z "$RC_CHG" ] || printf '%s\n' "$RC_CHG"
              printf 'head=%s rc=%s\nbase=%s (%s)\njudged-by=%s (%s)\ncommand: %s\n' "$RC_HEAD" "$RC_RC" "$RC_BASE" "$RC_FROM" "$WT_CHECK_JUDGE" "$RC_FROM" "$RC_CMD"
              [ -z "$RC_LEFT" ] || printf 'check-dirtied: the check %s\n' "$RC_LEFT"
              printf '\n'
              [ -z "$RC_OUT" ] || printf '%s\n' "$RC_OUT"; } > "$RC_LOG" 2>/dev/null; then
      die "REFUSED — the check exited $RC_RC, but its log $RC_LOG cannot be written; the plan is unchanged.$RC_SAID"
      exit 1
    fi
    if [ "$RC_RC" -ne 0 ] || [ -n "$RC_LEFT" ]; then
      if ! proof_event "$PV_PLAN" kind=check "head=$RC_HEAD" "evidence=$RC_REL" result=fail; then
        die "REFUSED — the declared release-check ($(clean "$RC_CMD")) exited $RC_RC over ${RC_BASE:0:12}..${RC_HEAD:0:12} ($RC_FROM), and its failing fact could not be appended to the run's log of $PV_PLAN; its log is $RC_LOG.$RC_SAID"
        exit 1
      fi
      if [ -n "$RC_LEFT" ]; then
        die "REFUSED — check-dirtied: the declared release-check ($(clean "$RC_CMD")) $RC_LEFT, as land refuses a check that does; its log $RC_REL and a result=fail check fact at ${RC_HEAD:0:12} were written. Put back what it changed, make the check change nothing, and run release-check again.$RC_SAID"
        exit 1
      fi
      die "REFUSED — the declared release-check ($(clean "$RC_CMD")), $RC_JUDGED, exited $RC_RC over ${RC_BASE:0:12}..${RC_HEAD:0:12} ($RC_FROM); its log $RC_REL and a result=fail check fact at that head were written. Fix what it names, commit, and run release-check again.$RC_SAID"
      exit 1
    fi
    if ! RC_AT="$(proof_attested check "$RC_LOG" "$RC_CO")"; then
      die "REFUSED — $(clean "$RC_AT"). The plan is unchanged."
      exit 1
    fi
    if ! proof_event "$PV_PLAN" kind=check "head=$RC_AT" "evidence=$RC_REL"; then
      die "REFUSED — the check proof at ${RC_AT:0:12} could not be appended to the run's log of $PV_PLAN; its log is $RC_LOG. Run release-check again."
      exit 1
    fi
    say "release-check — kind=check head=$RC_AT base=$RC_BASE ($RC_FROM) evidence=$RC_REL: written to the run's log.$RC_SAID"
    # THE PRIORITY A RECORD NEVER STATES (wave-28 T15; D19): each finding the plan defers or owes a
    # check for, with the table's priority (lib/proof.sh `proof_findings_owed`, the tick's own line).
    proof_findings_owed "$PV_PLAN" 2>/dev/null | while IFS= read -r _rc_f; do say "release-check — finding $(clean "$_rc_f")"; done
    # THE DEFERRALS' OTHER DEBT (wave-28 T17; D21): each says whether its sentence is in the head's CHANGELOG.md.
    # It refuses nothing, and the exit below is the check's own.
    release_deferrals "$PV_PLAN" "$RC_CO/CHANGELOG.md"
    # THE RUN'S NUMBERS (wave-28 T14; D18): the report's line and each landed row, read and printed only.
    landing_report "$(_wt_proofs_path "$PV_REPO" "$PV_PLAN")" "$(cd "$PV_REPO" 2>/dev/null && pwd -P)" yes \
      | while IFS= read -r _rc_l; do say "release-check — $_rc_l"; done
    exit 0
  }

  # THE DECLARED REGRESSION'S RUN (wave-28 T75; REQ-17 AC-17.1, D36). A project whose regression is not tests/run.sh
  # names it in `.bionic/config.yaml` under `floor:`, split on blanks with globbing off as `release-check:`
  # is. This verb runs it in the checkout of the plan's working branch, reading the head and the dirty
  # count (`_wt_piece_dirt`, land's reading: untracked files count, the record link does not) before the
  # run and again after it: a run that moved either is not a run of the head it read, so it is refused
  # and no log is written. Otherwise every run keeps its log, `record/<wave>/floor-run-<head>.log`, the
  # n-th at one head `floor-run-<head>-<n>.log`, in the floor's one grammar (wave-36 T35; D13, AC-7.10): opening
  # `head=<40-hex> dirty=<n>`, then `command: <cmd>`, then the output, and closing `rc=<n>`, its last line; the
  # verb exits with the command's code.
  # IT RUNS AND LOGS; IT WRITES NO PROOF. `release-check` writes its own fact because a check is a run the
  # verb owns; a regression is evidence the run cites, and `proof-add floor` stays the one writer of its line
  # (lib/proof.sh `_proof_floor_log` judges the log there as it judges any log: `floor:` is a convenience, never
  # a privilege, and a project may run its regression itself and cite that log).
  #
  # WITH NO floor: KEY THE REGRESSION IS THE PROJECT'S tests/run.sh (wave-35 T10; D10, REQ-1 AC-1.8). The verb runs
  # it, whole, in the same checkout at the same head and logs it the same way, `command: tests/run.sh`; the runner
  # asks the machine's gate itself, kind whole (tests/run.sh THE ONE ADMISSION; ADR-051). Its log is the evidence
  # `proof-add floor` judges by the runner's own report (lib/proof.sh `proof_attested`): a red whole run is the
  # floor's candidate, its reds owed (wave-35 T9), so the record line is printed red or green. A run the gate never
  # admitted (exit 75, no verdict) ran nothing and writes no log. With neither key nor runner it refuses, naming the
  # other way: run the regression and cite its log. A config carrying `floor-attestation:`, a key removed in wave-36
  # (T35), is refused first, naming it (lib/proof.sh `proof_floor_retired`).
  # THE ONE PATH A RUNNER IS GIVEN THE WHOLE RUN BY, asked before anything runs, and three rules refuse it:
  # `regression: no` (`plan_regression`); a row the regression waits on that still writes the head
  # (`units_floor_holds`); and a head that already has a whole-run log. A head is green only where the whole run ran
  # green, so a head past the last run, however its landings proved it, is run again: nothing reads a later head as
  # proved here. The bash wall's full-tree refusal names this verb as the whole run's path (lib/walls.sh).
  # WHO STARTED IT is written on the run line as `starter=`: the tick or the orchestrator (the default) is the machine,
  # and a person is a hand-hold, so `--starter person` carries the person's `--reason`, kept on the same line; the
  # hand-holds count reads it (hooks/poker/line.sh `hand_holds_report`).
  poker_verb_regression_run() {
    FR_STARTER=orchestrator; FR_REASON="";
    while [ $# -gt 0 ]; do
      case "$1" in
        --starter) [ $# -ge 2 ] || usage "regression-run --starter takes one of tick, orchestrator or person."
          FR_STARTER="$2"; shift 2 ;;
        --reason) [ $# -ge 2 ] || usage "regression-run --reason takes the person's reason, in quotes."
          FR_REASON="$2"; shift 2 ;;
        *) usage "regression-run takes only --starter <tick|orchestrator|person> and, with person, --reason '<why>': it runs .bionic/config.yaml's regression-command: command, else tests/run.sh, at the working branch's head." ;;
      esac
    done
    case "$FR_STARTER" in
      tick|orchestrator|person) : ;;
      *) die "REFUSED — --starter $(clean "$FR_STARTER") is none of the three starters: tick, orchestrator or person. Nothing was run."
         exit 1 ;;
    esac
    # The reason rides on one landing-record field, so it holds no field separator and no line break.
    case "$FR_REASON" in
      *'|'*|*$'\n'*|*$'\r'*)
        die "REFUSED — --reason holds a '|' or a line break, and the run line keeps it as one field; say it on one line without '|'. Nothing was run."
        exit 1 ;;
    esac
    if [ "$FR_STARTER" = person ] && [ -z "${FR_REASON//[[:space:]]/}" ]; then
      die "REFUSED — --starter person needs --reason '<why>': a person's whole run is a hand-hold, and its reason is kept on its run line. Nothing was run."
      exit 1
    fi
    FR_ROOT="$(project_root "$PWD")"
    # THE COMMAND'S KEY IS regression-command: and no other (wave-39 T18; REQ-13 AC-13.1, D2): the old key is refused, naming it
    # (lib/alias.sh `alias_gone_text config`), even beside the new one, never read past.
    if declare -F alias_gone_text >/dev/null 2>&1 && alias_gone_text config "$(cat "$FR_ROOT/.bionic/config.yaml" 2>/dev/null)"; then
      die "REFUSED — $ALIAS_GONE_SAID. Nothing was run."
      exit 1
    fi
    FR_CMD="$(config_value "$FR_ROOT" regression-command "" 2>/dev/null)"
    if ! { declare -F proof_state >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_state >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; nothing was run."
      exit 2
    fi
    if FR_RETIRED="$(proof_floor_retired "$FR_ROOT")"; then
      die "REFUSED — $(clean "$FR_RETIRED"). Nothing was run."
      exit 1
    fi
    plan_verb_open regression-run
    FR_WB="$(plan_working_branch "$PV_PLAN")"
    FR_CO=""; [ -z "$FR_WB" ] || FR_CO="$(proof_checkout "$PV_REPO" "$FR_WB")" || FR_CO=""
    FR_HEAD=""; [ -z "$FR_CO" ] || FR_HEAD="$(git -C "$FR_CO" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)"
    case "$FR_HEAD" in
      [0-9a-f]*) : ;;
      *)
        die "REFUSED — no checkout of $PV_REPO has the plan's working-branch ${FR_WB:-(none named)} checked out, so there is no head to run the regression at; nothing was run."
        exit 1 ;;
    esac
    FR_WAVE="$(proof_plan_slug "$PV_PLAN")"
    FR_DOCS="$(docs_root "$PV_REPO")"
    FR_WHOLE=""
    FR_RUNNING="REFUSED — a whole run is running in the working checkout $(cd "$FR_CO" 2>/dev/null && pwd -P) now: the gate holds an open whole request for it (gate_list names it), and its log is this head's whole run once it ends. Nothing was run; if it ends 75, the gate never admitted it: run regression-run again then."
    if [ -z "$FR_CMD" ]; then
      if [ ! -f "$FR_CO/tests/run.sh" ]; then
        die "REFUSED — this project declares no regression-command: in .bionic/config.yaml, and the working checkout $(cd "$FR_CO" 2>/dev/null && pwd -P) holds no tests/run.sh to run as its regression; declare regression-command: <command> there, or run the regression yourself and cite its log (its first head= line head=<40-hex> dirty=0, its last line rc=0) with proof-add regression <log> [<log>…]. Nothing was run."
        exit 1
      fi
      FR_WHOLE=yes; FR_CMD="tests/run.sh"
      # RULE 1. The setting, not a run.
      if [ "$(plan_regression "$PV_PLAN")" = no ]; then
        die "REFUSED — the plan declares regression: no (Step 0), so it owes no whole run, and no approval overrides the setting; put it to the user and change it with: bash ${HOOK_DIR}/session-poker.sh regression yes '<the user's reply>'. Nothing was run."
        exit 1
      fi
      # RULE 2. A row the regression waits on still writes the head.
      FR_OPEN="$(units_floor_holds "$PV_PLAN" "" 2>/dev/null | awk -F'\t' 'NF { printf "%s%s (step %s, %s)", (n++ ? ", " : ""), $1, $2, $3 }')"
      if [ -n "$FR_OPEN" ]; then
        die "REFUSED — rows the regression waits on still write tracked files: $FR_OPEN; the whole run comes once, after the last of them lands, or it proves a head that does not survive their landing. Nothing was run."
        exit 1
      fi
      # RULE 3. ONE WHOLE RUN AT A HEAD. A log of tests/run.sh at this head refuses another: a red is a fix row's, its
      # own suites plus the red one, and the next whole run is at the head its landing makes. A whole run still running
      # in the checkout refuses one too: a second would wait behind it at the gate to prove the same head.
      if whole_run_at_head "$FR_DOCS" "$FR_WAVE" "$FR_HEAD" "$FR_CO" tests/run.sh; then
        if [ -n "$WRA_LOG" ]; then
          die "REFUSED — the whole run runs once at a head, and ${FR_HEAD:0:12} has it: $WRA_LOG. A red suite is a fix row's: its own suites plus the red one, green at a later head. Nothing was run."
        else
          die "$FR_RUNNING"
        fi
        exit 1
      fi
      # A head the last full pass still proves is not run again: nothing a suite runs differs from the pass, so a run here
      # proves what is proved, and the next whole run is at the head a landing of code makes. The printer is the one reader.
      FR_GREEN="$(proof_whole_text "$PV_PLAN" "$FR_CO" "$FR_HEAD" 2>/dev/null)"
      case "$FR_GREEN" in
        "green at "*", "*)
          FR_PASS="record/$FR_WAVE/regression-run-$(proof_last "$PV_PLAN" regression 2>/dev/null).log"
          for _fr_l in "$FR_DOCS/${FR_PASS%.log}"*.log; do [ -f "$_fr_l" ] && { FR_PASS="${_fr_l#"$FR_DOCS"/}"; break; }; done
          die "REFUSED — the full pass already proves ${FR_HEAD:0:12}: $(clean "$FR_GREEN"), its log $FR_PASS. A pass runs where code lands, and the next whole run is at the head a landing of code makes: land it with spawn-worktree.sh ready. Nothing was run and no log was written."
          exit 1 ;;
      esac
    elif declare -F gate_whole_open >/dev/null 2>&1 && gate_whole_open "$FR_CO"; then
      # A configured command is refused beside a running whole run as tests/run.sh is. Its log at a head refuses no
      # second run of it: that half of rule 3 is tests/run.sh's alone.
      die "$FR_RUNNING"
      exit 1
    fi
    FR_DIRT="$(_wt_piece_dirt "$FR_CO")"
    FR_DIRTY="$(printf '%s' "$FR_DIRT" | awk 'END { print NR + 0 }')"
    # A DIRTY TREE IS REFUSED BEFORE THE RUN, NOT LOGGED AFTER IT (wave-35 T32; D20, A-orch-32). The log of a dirty
    # whole run counted as the head's whole run (rule 3) while proof-add floor refuses it, so the re-run its own message
    # asked for was refused as a second whole run and the one allowed run was spent on nothing. The after-the-run
    # comparison below stays: it guards a run that dirtied a clean tree.
    if [ -n "$FR_WHOLE" ] && [ "$FR_DIRTY" -ne 0 ]; then
      FR_PATHS="$(printf '%s\n' "$FR_DIRT" | sed -n '1,5p' | awk '{ printf "%s%s", (NR > 1 ? ", " : ""), $0 }')"
      FR_MORE=""; [ "$FR_DIRTY" -le 5 ] || FR_MORE=", and $((FR_DIRTY - 5)) more"
      die "REFUSED — the working checkout $(cd "$FR_CO" 2>/dev/null && pwd -P) is dirty (dirty=$FR_DIRTY): $(clean "$FR_PATHS")$FR_MORE. The whole run proves a committed head, and a log of a dirty tree is refused by proof-add regression yet would be the head's one whole run; nothing was run and no log was written; commit or stash it and run regression-run again."
      exit 1
    fi
    # THE VERB BOOKS ITS WHOLE RUN, for any command. The tick and a second regression-run know a whole run is running in
    # a checkout only by an open whole request at the gate for it (`whole_run_at_head`), and a command other than this
    # repository's runner files none, so the verb files it: kind whole, asked from the checkout (its tree=), keyed by
    # the command, before the command starts, and ended with the command's code once it returns. The command runs with
    # BIONIC_GATE_ADMIT naming the request, so a runner beneath that asks (tests/run.sh) is believed under it and files
    # nothing of its own. A verb killed while its command runs leaves a request whose holder is dead, which the gate
    # reads as no longer open. A verb started inside another admission is believed under it and files nothing, as any
    # nested asker is. The cost: a configured command waits, as tests/run.sh does, until nothing else admitted on the
    # machine is unfinished. Asked in this shell, the id read back through a file, since the gate's holder and the
    # `times` gate_end reads are this shell's.
    FR_GATE=""; FR_GATE_OWN=0
    if declare -F gate_ask >/dev/null 2>&1 && FR_IDF="$(mktemp "${TMPDIR:-/tmp}/bionic-regression-gate.XXXXXX")"; then
      FR_HERE="$PWD"; FR_ASK=2
      if cd "$FR_CO" 2>/dev/null; then
        gate_ask whole "${FR_CMD:0:60}" > "$FR_IDF"; FR_ASK=$?
        cd "$FR_HERE" 2>/dev/null || :
      fi
      { read -r FR_GATE < "$FR_IDF"; } 2>/dev/null; rm -f "$FR_IDF"
      case "$FR_ASK" in
        0)
          case "$(sed -n 's/^holder=//p' "$(gate_dir)/requests/$FR_GATE" 2>/dev/null | tail -n 1)" in "$$:"*) FR_GATE_OWN=1 ;; esac
          export BIONIC_GATE_ADMIT="$FR_GATE" ;;
        75)
          die "regression-run — the gate did not admit the whole run (exit 75), so nothing ran and no log was written; run regression-run again."
          exit 75 ;;
        *)
          FR_GATE=""
          say "regression-run — the gate's store $(gate_dir) cannot be written, so this whole run runs unbooked, and neither the tick nor a second regression-run can see it running." ;;
      esac
    fi
    FR_TMP="$(mktemp "${TMPDIR:-/tmp}/bionic-regression-run.XXXXXX")" || {
      [ "$FR_GATE_OWN" -ne 1 ] || gate_end "$FR_GATE" 1 >/dev/null 2>&1 || :
      die "REFUSED — no scratch file for the regression's output can be made under ${TMPDIR:-/tmp}; nothing was run."
      exit 1
    }
    # THE LAUNCH RESETS HUP, INT AND QUIT (wave-39 T14; D17, AC-10.1; A-orch-69). A verb started with a signal ignored (a nohup'd or
    # backgrounded session) hands the ignored state to the whole run below it, where no bash can trap or be ended by it; a bash cannot
    # un-ignore a signal, perl can. Both arms exec through one perl that sets the three to their defaults and execs the command
    # unchanged: no argument, no environment variable and no exit code differs (a command it cannot exec ends 127, or 126, as bash's
    # own exec ends). No perl on PATH: the command is launched as it was.
    FR_SIGDFL=()
    command -v perl >/dev/null 2>&1 && FR_SIGDFL=(perl -e '$SIG{$_} = "DEFAULT" for qw(HUP INT QUIT); exec { $ARGV[0] } @ARGV; exit($!{ENOENT} ? 127 : 126)' --)
    if [ -n "$FR_WHOLE" ]; then
      ( cd "$FR_CO" 2>/dev/null || exit 1
        exec ${FR_SIGDFL[@]+"${FR_SIGDFL[@]}"} bash tests/run.sh ) </dev/null > "$FR_TMP" 2>&1
    else
      ( cd "$FR_CO" 2>/dev/null || exit 1
        set -f
        # shellcheck disable=SC2086  # the configured command splits on blanks, as release-check's does
        exec ${FR_SIGDFL[@]+"${FR_SIGDFL[@]}"} $FR_CMD ) </dev/null > "$FR_TMP" 2>&1
    fi
    FR_RC=$?
    if [ "$FR_GATE_OWN" -eq 1 ]; then gate_end "$FR_GATE" "$FR_RC" >/dev/null 2>&1 || :; unset BIONIC_GATE_ADMIT; fi
    # A WHOLE RUN THE GATE NEVER ADMITTED RAN NOTHING (tests/run.sh: exit 75 before any suite, no verdict), so
    # there is no run of the head to log.
    if [ -n "$FR_WHOLE" ] && [ "$FR_RC" -eq 75 ] && ! /usr/bin/grep -q '^Gating: ' "$FR_TMP" 2>/dev/null; then
      cat "$FR_TMP"; rm -f "$FR_TMP"
      die "regression-run — the gate did not admit the whole run (exit 75), so nothing ran and no log was written; run regression-run again."
      exit 75
    fi
    FR_NOW="$(git -C "$FR_CO" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)"
    FR_DIRTY2="$(_wt_piece_dirt "$FR_CO" | awk 'END { print NR + 0 }')"
    FR_MOVED=""
    [ "$FR_NOW" = "$FR_HEAD" ] || FR_MOVED="head ${FR_HEAD:0:12} to ${FR_NOW:-<none>}"
    [ "$FR_DIRTY2" = "$FR_DIRTY" ] || FR_MOVED="${FR_MOVED:+$FR_MOVED, }dirty=$FR_DIRTY to dirty=$FR_DIRTY2"
    if [ -n "$FR_MOVED" ]; then
      cat "$FR_TMP"; rm -f "$FR_TMP"
      die "REFUSED — the regression ($(clean "$FR_CMD")) moved the working checkout $FR_CO while it ran ($FR_MOVED); no log was written. Put back what it changed and run regression-run again."
      exit 1
    fi
    FR_REL="record/$FR_WAVE/regression-run-$FR_HEAD.log"; FR_NTH=1
    while [ -e "$FR_DOCS/$FR_REL" ]; do FR_NTH=$((FR_NTH + 1)); FR_REL="record/$FR_WAVE/regression-run-$FR_HEAD-$FR_NTH.log"; done
    FR_LOG="$FR_DOCS/$FR_REL"
    if ! mkdir -p "${FR_LOG%/*}" 2>/dev/null \
       || ! { printf 'head=%s dirty=%s\ncommand: %s\n' "$FR_HEAD" "$FR_DIRTY" "$FR_CMD"; awk '{ print }' "$FR_TMP"; printf 'rc=%s\n' "$FR_RC"; } > "$FR_LOG" 2>/dev/null; then
      cat "$FR_TMP"; rm -f "$FR_TMP"
      die "REFUSED — the regression exited $FR_RC, but its log $FR_LOG cannot be written."
      exit 1
    fi
    # THE RUN IS RECORDED WHERE ITS PROOF WILL LOOK (wave-37 T4; D7, AC-6.1; ADR-057): one `ev=run` line in the plan's
    # run log (lib/line.sh `line_run_event`, through the log's appender), the log by its record path, the head and
    # dirty count read before the run, its exit, and the log's sha256 (lib/proof.sh `_proof_sha256`), so `proof-add
    # floor` accepts this log, and this log as it is now, and no hand-written one.
    FR_SHA="$(_proof_sha256 "$FR_LOG")" || FR_SHA=""
    declare -F line_event >/dev/null 2>&1 || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1
    if [ -z "$FR_SHA" ] || ! declare -F line_event >/dev/null 2>&1 \
       || ! line_run_event "$(line_log "$PV_PLAN")" "log=$FR_REL" "head=$FR_HEAD" "dirty=$FR_DIRTY" "rc=$FR_RC" "sha256=$FR_SHA" \
              "starter=$FR_STARTER" ${FR_REASON:+"reason=$FR_REASON"} 2>/dev/null; then
      die "regression-run — the run line for $FR_REL could not be written to the plan's landing record$([ -n "$FR_SHA" ] || printf ' (no sha256 tool answered)'), so proof-add regression will refuse this log as no recorded run."
    fi
    # THE REGRESSION'S FACTS (wave-39 T24; D9; ADR-061): a clean whole run folds into one verdict per suite at its head,
    # each keyed by the commit it ran at (lib/proof.sh `proof_regression_fold`). A run the gate never admitted returned
    # above; a dirty run proves no commit and folds nothing.
    if [ -n "$FR_WHOLE" ] && [ "$FR_DIRTY" -eq 0 ] && ! proof_regression_fold "$PV_PLAN" "$FR_CO" "$FR_HEAD" "$FR_LOG" "$FR_REL" 2>/dev/null; then
      say "regression-run — this run's per-suite facts could not be written to the plan's landing record; the judge reads the run's proof line at ${FR_HEAD:0:12} alone."
    fi
    if [ -n "$FR_WHOLE" ]; then
      FR_VERDICT="$(/usr/bin/grep '^Gating: ' "$FR_TMP" 2>/dev/null | tail -n 1)"
      rm -f "$FR_TMP"
      say "regression-run — the whole run (tests/run.sh) at ${FR_HEAD:0:12} exited $FR_RC${FR_VERDICT:+ ($FR_VERDICT)}: head=$FR_HEAD dirty=$FR_DIRTY rc=$FR_RC evidence=$FR_REL"
      if [ "$FR_DIRTY" -ne 0 ]; then
        say "regression-run — the tree was dirty (dirty=$FR_DIRTY), so proof-add regression refuses this log; commit and run regression-run again."
      else
        [ "$FR_RC" -eq 0 ] || say "regression-run — a red whole run is the regression's candidate: proof-add regression records it with its red suites owed, each closed by a later landing that runs it green (a fix row)."
        say "regression-run — record it: bash ${HOOK_DIR}/session-poker.sh proof-add regression $FR_REL"
      fi
      exit "$FR_RC"
    fi
    if [ "$FR_RC" -ne 0 ]; then
      cat "$FR_TMP"; rm -f "$FR_TMP"
      die "regression-run — the regression ($(clean "$FR_CMD")) exited $FR_RC at ${FR_HEAD:0:12}; its log is $FR_REL. Fix what it names, commit, and run regression-run again."
      exit "$FR_RC"
    fi
    rm -f "$FR_TMP"
    say "regression-run — head=$FR_HEAD dirty=$FR_DIRTY rc=0 evidence=$FR_REL"
    if [ "$FR_DIRTY" -ne 0 ]; then
      say "regression-run — the tree was dirty (dirty=$FR_DIRTY), so proof-add regression refuses this log; commit and run regression-run again."
    else
      say "regression-run — record it: bash ${HOOK_DIR}/session-poker.sh proof-add regression $FR_REL"
    fi
    exit 0
  }

  # THE RUN'S NUMBERS (wave-28 T14; D18, REQ-4). The fold and its definitions are `landing_report`'s,
  # above the verbs. The plan is the one named, resolved as a path from the project root, else from the docs root, or else this session's bound run; the record is
  # that plan's landing record, under the plan's own project. It writes nothing and exits 0 whatever
  # the record holds.
  # THE RUN'S DEBTS. Each act is one `debt` event in the run's log through the
  # type's one writer (lib/proof.sh `proof_debt_event`, whose comment holds the fields), its state the newest event of
  # its concept and kind, read back through the reader (`proof_debt_items`). `add` reads a record's `debt:` lines, a reading's or any other's
  # (`proof_record_debts`, the registering verb's debt arm), holds each to the one grammar (lib/debt.sh
  # `debt_line_ok`), and writes a debt per concept and kind the run does not hold yet; `touched` adds one to the
  # touches of every unburned debt of each concept its one operand names, blank-separated, the run read once for all
  # of them (the dispatch wall's advisory calls it once a launch); `burn` writes it burned by
  # <row>; `adopt` reads the `debt:` lines close-out carried under `## Deferrals` of a continuation, the next
  # run's read-back, and writes each with its touches and raised-by kept, none burned; `sites` says again where the
  # unburned item of one concept and kind stands, its sites replaced and every other field kept, each site a line of a
  # file under the project's root. Whether that line holds the concept is the reader's to judge, not the verb's.
  # Exit 0 done; 1 refused, nothing written; 2 the run, the record or its log cannot be found or written.
  poker_verb_debt() {
    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    DEBT_PLAN=""
    if [ -n "$DEBT_PLAN_ARG" ]; then
      DEBT_PLAN="$(docs_path "$REPO_REAL" "$DEBT_PLAN_ARG")"
      if [ ! -f "$DEBT_PLAN" ] || [ -L "$DEBT_PLAN" ]; then
        die "REFUSED — no plan file at $DEBT_PLAN_ARG; name the plan whose debt ledger this is."
        exit 2
      fi
    else
      SESSION_ID="$(session_id)" || SESSION_ID=""
      if [ -z "$SESSION_ID" ]; then
        die "REFUSED — no session key, and no plan named; name the plan: debt $DEBT_SUB … <plan>."
        exit 3
      fi
      # A WRITER TAKES ONLY THE PLAN IT IS BOUND TO (wave-36 T13; D13, REQ-7 AC-7.3, census C25, A-orch-2).
      # `resolve_run`'s `none` arm hands an unbound session the root's newest plan by mtime, closed or
      # not, so the tick can DISARM; through it `debt adopt` at Step 1 wrote the predecessor's ledger.
      # The verb asks the binding itself: a `bound-*` verdict names this session's plan, anything else
      # refuses naming `bind`, and nothing is written.
      DEBT_BIND="$(session_run "$REPO_REAL" "$SESSION_ID" 2>/dev/null)" || :  # exit 2 is bound-closed, still bound
      case "$DEBT_BIND" in bound-*' '*) DEBT_PLAN="${DEBT_BIND#* }" ;; *) DEBT_PLAN="" ;; esac
      if [ -z "$DEBT_PLAN" ] || [ ! -f "$DEBT_PLAN" ]; then
        die "REFUSED — this session is bound to no plan, so debt $DEBT_SUB has no ledger of its own to write; bind its plan first (session-poker.sh bind <plan>), or name it: debt $DEBT_SUB … <plan>."
        exit 2
      fi
    fi
    if ! { declare -F proof_debt_items >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh" 2>/dev/null; }; } \
       || ! declare -F proof_debt_items >/dev/null 2>&1; then
      die "REFUSED — lib/proof.sh cannot be loaded, so the debt ledger cannot be read; reinstall the plugin."
      exit 2
    fi
    # THE ONE DEBT-LINE GRAMMAR (wave-36 T13; D13, AC-7.8): lib/debt.sh, which close-out and card.sh source too.
    if ! { declare -F debt_line_ok >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/debt.sh" ] && . "$BIONIC_LIB/debt.sh" 2>/dev/null; }; } \
       || ! declare -F debt_line_ok >/dev/null 2>&1; then
      die "REFUSED — lib/debt.sh cannot be loaded, so no debt line can be held to its grammar; reinstall the plugin."
      exit 2
    fi
    DEBT_ROOT="$(cd "$(project_root "${DEBT_PLAN%/*}")" 2>/dev/null && pwd -P)"
    [ -n "$DEBT_ROOT" ] || DEBT_ROOT="$REPO_REAL"
    DEBT_DOCS="$(docs_root "$DEBT_ROOT")"
    _proof_reader_load || { die "REFUSED — lib/reader.sh cannot be loaded, so the run's log cannot be named. Fix: reinstall the plugin."; exit 2; }
    DEBT_REL="$(reader_log_in "record/$(proof_plan_slug "$DEBT_PLAN")")"
    DEBT_HAVE="$(proof_debt_items "$DEBT_PLAN")"
    if [ "$DEBT_SUB" = list ]; then
      [ -n "$DEBT_HAVE" ] || { say "debt list — the run holds no debt"; exit 0; }
      printf '%s\n' "$DEBT_HAVE" | awk -F'\t' '{ printf "%s %s \"%s\" touches=%s raised-by=%s%s\n", $1, $2, $3, $5, $4, ($6 == "-" ? "" : " burned=" $6) }'
      exit 0
    fi
    DEBT_ROWS=""; DEBT_RECREL=""
    if [ "$DEBT_SUB" = add ]; then
      case "$DEBT_A" in
        /*) DEBT_REC="$DEBT_A" ;;
        *)  DEBT_REC="$DEBT_DOCS/$DEBT_A"; [ -f "$DEBT_REC" ] || DEBT_REC="$REPO_REAL/$DEBT_A" ;;
      esac
      if [ ! -f "$DEBT_REC" ]; then
        die "REFUSED — no record at $DEBT_A; name it as proof-add does, record/<wave>/<file>."
        exit 2
      fi
      DEBT_RECREL="$DEBT_A"
      case "$DEBT_REC" in "$DEBT_DOCS"/*) DEBT_RECREL="${DEBT_REC#"$DEBT_DOCS"/}" ;; esac
      # ANY RECORD, A `reviewed:` LINE OR NOT (wave-36 T13; AC-7.2, C24): a reading's, a writer's, the
      # orchestrator's assumptions.md hole line, each read by the reading's own debt arm, `hole` a kind.
      if ! DEBT_ROWS="$(PROOF_DEBT_KINDS="$DEBT_KINDS" proof_record_debts "$DEBT_REC")"; then
        die "REFUSED — $DEBT_ROWS"
        exit 1
      fi
      DEBT_ROWS="$(printf '%s\n' "$DEBT_ROWS" | awk -F'\t' '$1 == "debt"')"
      if [ -z "$DEBT_ROWS" ]; then
        say "debt add — the record $DEBT_RECREL carries no debt: line; nothing added"
        exit 0
      fi
      # EACH LINE IS HELD TO THE GRAMMAR BEFORE ANY IS WRITTEN (AC-7.8): the line close-out would carry
      # for it, raised by this record, must parse, or the lot is refused naming it — a raised-by with a
      # space (A-orch-1's shape) is refused here, where it is written, and never reaches a continuation.
      DEBT_FROM="$(proof_plan_slug "$DEBT_PLAN")"
      DEBT_BADL="$(printf '%s\n' "$DEBT_ROWS" | while IFS="$(printf '\t')" read -r _dk _dkind _dcon _dsites _ddisp; do
        _dl="debt: $_dcon $_dkind \"$_dsites\" touches=0 raised-by=$DEBT_RECREL from=$DEBT_FROM"
        debt_line_ok "$_dl" || { printf '%s\n' "$_dl"; break; }
      done)"
      if [ -n "$DEBT_BADL" ]; then
        die "REFUSED — a debt: line of $DEBT_RECREL does not parse as a debt line: $DEBT_BADL; nothing added."
        exit 1
      fi
    fi
    if [ "$DEBT_SUB" = adopt ]; then
      case "$DEBT_A" in
        /*) DEBT_REC="$DEBT_A" ;;
        *)  DEBT_REC="$DEBT_DOCS/$DEBT_A"
            [ -f "$DEBT_REC" ] || DEBT_REC="$REPO_REAL/$DEBT_A"
            [ -f "$DEBT_REC" ] || DEBT_REC="$PWD/$DEBT_A" ;;
      esac
      if [ ! -f "$DEBT_REC" ] || [ ! -r "$DEBT_REC" ]; then
        die "REFUSED — no readable continuation at $DEBT_A; name the file whose ## Deferrals carry the debt."
        exit 2
      fi
      # The carry shape (close-out's co_debts), read under the first `## Deferrals` outside a fence. A
      # `debt:` line there that the one grammar (lib/debt.sh `DEBT_LINE_ERE`, wave-36 T13) does not parse
      # is a BAD row, and one BAD row refuses the lot.
      DEBT_ROWS="$(DEBT_LINE_ERE="$DEBT_LINE_ERE" awk '
        { sub(/\r$/, "") }
        /^[ \t]*```/ { fence = !fence; next }
        fence { next }
        /^## / { s = ($0 ~ /^## Deferrals[ \t]*$/); next }
        s && /^debt:[ \t]/ {
          if ($0 !~ ENVIRON["DEBT_LINE_ERE"]) { print "BAD\t" $0; next }
          split($0, w, /[ \t]+/)
          q = index($0, "\""); r = substr($0, q + 1); e = index(r, "\""); sites = substr(r, 1, e - 1)
          split(substr(r, e + 1), t, /[ \t]+/)
          printf "debt\t%s\t%s\t%s\t%s\t%s\n", w[3], w[2], sites, substr(t[2], 9), substr(t[3], 11)
        }' "$DEBT_REC")"
      DEBT_BAD="$(printf '%s\n' "$DEBT_ROWS" | awk -F'\t' '$1 == "BAD" { print $2; exit }')"
      if [ -n "$DEBT_BAD" ]; then
        die "REFUSED — $DEBT_A carries a debt: line that does not parse; nothing adopted: $DEBT_BAD"
        exit 1
      fi
      if [ -z "$DEBT_ROWS" ]; then
        say "debt adopt — the continuation $DEBT_A carries no debt: line; nothing adopted"
        exit 0
      fi
    fi
    # An item is `<concept><TAB><kind><TAB><sites><TAB><raised-by><TAB><touches>`. Each is marked new or old before any
    # is written: old when the run, or an item above it, holds its concept and kind already, so it is written once.
    debt_sort() {
      PROOF_HAVE="$DEBT_HAVE" awk -F'\t' 'BEGIN { n = split(ENVIRON["PROOF_HAVE"], h, "\n"); for (i = 1; i <= n; i++) { split(h[i], c, "\t"); have[c[1] "\t" c[2]] = 1 } }
        NF { k = $1 "\t" $2; print ((k in have) ? "old" : "new") "\t" $0; have[k] = 1 }'
    }
    debt_refuse() { die "REFUSED — the run's log at $DEBT_REL cannot be written; nothing more is written."; exit 2; }
    case "$DEBT_SUB" in
      add|adopt)
        # add's rows are `debt <kind> <concept> <sites> <disposition>`, raised by the record; adopt's are
        # `debt <kind> <concept> <sites> <touches> <raised-by>`, their touches and raised-by kept.
        if [ "$DEBT_SUB" = add ]; then DEBT_ITEMS="$(printf '%s\n' "$DEBT_ROWS" | awk -F'\t' -v r="$DEBT_RECREL" '{ print $3 "\t" $2 "\t" $4 "\t" r "\t0" }' | debt_sort)"
        else DEBT_ITEMS="$(printf '%s\n' "$DEBT_ROWS" | awk -F'\t' '{ print $3 "\t" $2 "\t" $4 "\t" $6 "\t" $5 }' | debt_sort)"; fi
        DEBT_N=0; DEBT_OLD=0
        while IFS='	' read -r _dn _dc _dk _ds _dr _dt; do
          if [ "$_dn" = old ]; then DEBT_OLD=$((DEBT_OLD + 1)); [ "$DEBT_SUB" = adopt ] || say "debt add — $_dc $_dk already there"; continue; fi
          proof_debt_event "$DEBT_PLAN" "concept=$_dc" "kind=$_dk" "sites=$_ds" "raised-by=$_dr" "touches=$_dt" || debt_refuse
          DEBT_N=$((DEBT_N + 1)); [ "$DEBT_SUB" = adopt ] || say "debt add — $_dc $_dk $_ds"
        done <<< "$DEBT_ITEMS"
        [ "$DEBT_SUB" = adopt ] && say "debt adopt — $DEBT_N adopted, $DEBT_OLD already there: $DEBT_REL" || say "debt add — $DEBT_N added, $DEBT_OLD already there: $DEBT_REL"
        exit 0
        ;;
      touched|burn)
        # Every concept named is held to the ledger before any item is written: one that holds no unburned item
        # refuses the lot, so a touch is never half written.
        DEBT_MISS="$(printf '%s\n' "$DEBT_HAVE" | awk -F'\t' -v cs="$DEBT_A" '
          BEGIN { n = split(cs, c, / +/) }
          $6 == "-" { held[$1] = 1 }
          END { for (i = 1; i <= n; i++) if (c[i] != "" && !(c[i] in held) && !(c[i] in said)) { said[c[i]] = 1; printf "%s%s", (m++ ? " " : ""), c[i] } }')"
        if [ -n "$DEBT_MISS" ]; then
          die "REFUSED — no unburned debt of the run names $DEBT_MISS; debt list prints what it holds."
          exit 1
        fi
        DEBT_HIT="$(printf '%s\n' "$DEBT_HAVE" | awk -F'\t' -v cs="$DEBT_A" '
          BEGIN { n = split(cs, c, / +/); for (i = 1; i <= n; i++) want[c[i]] = 1 }
          $1 != "" && ($1 in want) && $6 == "-"')"
        while IFS='	' read -r _dc _dk _ds _dr _dt _; do
          if [ "$DEBT_SUB" = touched ]; then
            _dt=$((_dt + 1)); proof_debt_event "$DEBT_PLAN" "concept=$_dc" "kind=$_dk" "sites=$_ds" "raised-by=$_dr" "touches=$_dt" || debt_refuse
            say "debt touched — $_dc $_dk touches $_dt"
          else
            proof_debt_event "$DEBT_PLAN" "concept=$_dc" "kind=$_dk" "sites=$_ds" "raised-by=$_dr" "touches=$_dt" "burned=$DEBT_B" || debt_refuse
            say "debt burn — $_dc $_dk burned $DEBT_B"
          fi
        done <<< "$DEBT_HIT"
        exit 0
        ;;
      sites)
        # Every check reads the register or the disk before the one event is written, so a refusal writes nothing. The
        # sites are held to the one grammar as the line close-out would carry for the item.
        DEBT_ITEM="$(printf '%s\n' "$DEBT_HAVE" | awk -F'\t' -v c="$DEBT_A" -v k="$DEBT_B" '$1 == c && $2 == k' | tail -1)"
        if [ -z "$DEBT_ITEM" ]; then
          die "REFUSED — the run holds no debt $DEBT_A $DEBT_B, so it has no sites to say again; session-poker.sh debt list prints each concept and kind it holds."
          exit 1
        fi
        IFS='	' read -r _dc _dk _ds _dr _dt _db <<< "$DEBT_ITEM"
        if [ "$_db" != - ]; then
          die "REFUSED — debt $_dc $_dk is burned by $_db, and a burned debt's sites stand as they were. Fix: name an unburned debt; session-poker.sh debt list prints each."
          exit 1
        fi
        _dl="debt: $_dc $_dk \"$DEBT_C\" touches=$_dt raised-by=$_dr from=$(proof_plan_slug "$DEBT_PLAN")"
        if ! debt_line_ok "$_dl"; then
          die "REFUSED — the sites \"$DEBT_C\" are not <path>:<line>, joined by \", \", so the item's carried line would not parse: $_dl. Fix: say each site as <path>:<line>."
          exit 1
        fi
        if [ "$DEBT_C" = "$_ds" ]; then
          die "REFUSED — debt $_dc $_dk already stands at \"$_ds\", so nothing would change. Fix: name the sites where the concept stands now."
          exit 1
        fi
        # A path is read from the project's root and stays under it: an absolute path or a `..` segment names no file there.
        DEBT_SBAD="$(printf '%s\n' "$DEBT_C" | tr ',' '\n' | while read -r _st; do
          _sp="${_st%:*}"; _sl="${_st##*:}"
          [[ "/$_sp/" != //* && "/$_sp/" != */../* && -f "$DEBT_ROOT/$_sp" ]] || { printf '%s names no file under the project root %s' "$_sp" "$DEBT_ROOT"; break; }
          _sn="$(awk 'END { print NR }' "$DEBT_ROOT/$_sp")"
          [ "$_sl" -ge 1 ] && [ "$_sl" -le "$_sn" ] || { printf 'the site %s names line %s, and %s has %s' "$_st" "$_sl" "$_sp" "$_sn"; break; }
        done)"
        if [ -n "$DEBT_SBAD" ]; then
          die "REFUSED — $DEBT_SBAD; nothing is written. Fix: name a line of a file under the project's root, by its path from that root."
          exit 1
        fi
        proof_debt_event "$DEBT_PLAN" "concept=$_dc" "kind=$_dk" "sites=$DEBT_C" "raised-by=$_dr" "touches=$_dt" || debt_refuse
        say "debt sites — $_dc $_dk \"$DEBT_C\", was \"$_ds\""
        exit 0
        ;;
    esac
  }
