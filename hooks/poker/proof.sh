# shellcheck shell=bash
# hooks/poker/proof.sh — the proof record: deferrals, findings, approvals, waivers, confirmations, the regression
# and the debt ledger (approve, proof-add, waive, waive-row, confirm-row, finding-stated, finding-move, disposition,
# release-check, regression, regression-run, debt).
#
# A part of hooks/session-poker.sh, which sets every global and loads this file before any verb runs. A part
# defines functions only, and is never run by itself.

# ---------------------------------------------------------------- the deferral's sentence
#
# A DEFERRED FINDING'S ONE CHANGELOG SENTENCE (wave-28 T17; D21, AC-8.7). Registering a record writes
# `deferred: <record>#<n> <S> <reach> "<title>"` (lib/proof.sh `proof_finding_lines`); `finding-stated`
# appends ` stated="<sentence>"` to it, the last field of the line. The sentence is folded to one line
# of single spaces (`deferral_fold`, lib/said.sh's `said_fold`, the one fold the changelog is read through as well), and a `\` or a `"` in it is written `\\` or `\"`, so the
# quoted field ends where the line does and a title, which never holds a `"`, is still the line's
# first quoted string (`proof_findings_owed` reads it so). The other half of the debt is the changelog:
# `release-check` prints each deferral stated (the sentence is in `CHANGELOG.md`) or unstated.
deferral_fold() {  # <text> -> its white space and control characters folded to single spaces, trimmed: lib/said.sh's one fold
  declare -F said_fold >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/said.sh" ] && . "$BIONIC_LIB/said.sh"; }
  said_fold "$1"
}
deferral_escape() {  # <folded sentence> -> as the plan holds it: \ for a backslash, \" for a quote
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
deferral_line() {  # <plan> <record>#<n> -> the first deferred: line of ## SDLC State naming it (exit 1: none)
  awk -v id="$2" '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && !found && /^deferred:[ \t]/ { split($0, f, /[ \t]+/); if (f[2] == id) { found = 1; line = $0 } }
    END { if (found) print line; exit (found ? 0 : 1) }' "$1"
}
# waive_owed_findings <plan> <repo> <question> -> always 0, prints nothing: the waiver of a question is the person's
# answer to every finding of its readings ("fix it, defer it, or waive <question>", `disposition`), so it closes each
# open `finding:<record>#<n>` item of every reading the plan registers under that question (wave-34 T5; REQ-4 AC-4.2,
# D14). The readings are `disposition`'s own: `proved: kind=review` lines under ## SDLC State naming the question.
waive_owed_findings() {
  local ev pre key
  declare -F owed_list >/dev/null 2>&1 && declare -F proof_awk >/dev/null 2>&1 || return 0
  while IFS= read -r ev; do
    [ -n "$ev" ] || continue
    pre="$(finding_owed_key "$ev#")"
    for key in $(OWED_ROOT="$2" owed_list 2>/dev/null | cut -f1); do
      case "${key#"$pre"}" in "$key"|''|*[!0-9]*) continue ;; esac
      poker_owed_close "$2" "$key" "waive"
    done
  done <<< "$(awk -v q="$3" "$(proof_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && proof_fields($0) && PROOF_KIND == "review" && PROOF_QUESTION == q && PROOF_EVIDENCE != "" { print PROOF_EVIDENCE }' "$1" | sort -u)"
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

deferral_sentence() {  # <plan> <record>#<n> -> the stated sentence, unescaped (nothing when none); exit 1: no deferred: line
  local l
  l="$(deferral_line "$1" "$2")" || return 1
  printf '%s\n' "$l" | sed -n 's/^.* stated="\(.*\)"[[:space:]]*$/\1/p' | sed -e 's/\\\(.\)/\1/g'
}
# release_deferrals <plan> <changelog file> -> a line `release-check — deferral <id>: stated|unstated`
# for each open deferral (a finding with a deferred: line whose effective priority is defer), in the
# order the plan wrote them. Refuses nothing: the caller's exit is not read from it.
release_deferrals() {
  local plan="$1" cl="$2" DS_CL="" _id _s _r _p _t DS_ST DS_ANS
  [ -f "$cl" ] && DS_CL="$(deferral_fold "$(cat "$cl")")"
  proof_findings_owed "$plan" 2>/dev/null | while read -r _id _s _r _p _t; do
    [ "$_p" = defer ] || continue
    DS_ST="$(deferral_sentence "$plan" "$_id")" || continue
    DS_ANS=unstated
    [ -n "$DS_ST" ] && case "$DS_CL" in *"$DS_ST"*) DS_ANS=stated ;; esac
    say "release-check — deferral $(clean "$_id"): $DS_ANS"
  done
}

  # THE REGRESSION SETTING (wave-31 T27; REQ-12 AC-12.1, AC-12.2; D4). Whether the run runs the
  # regression is a Step-0 setting, written once into the plan's frontmatter as `regression: <v>`,
  # which lib/walls.sh `validate_tests_block` (Step 5), lib/proof.sh `facts_owed` (Step 8) and the
  # integrate row's kind default (lib/units.sh) read. THE SCALE DEFAULT is task no, wave yes, epic no;
  # a value against it is the user's override, recorded beside the key as
  # `regression-override: <git user.name> <date> derived=<default> chosen=<v>`, budget-override:'s
  # form above and the sibling of `rigor-override:`. A value AT the default removes any override
  # line, and the one key and the one override line are rewritten, never doubled. It goes through
  # the plan transaction every plan verb takes. REFUSED: a value that is not exactly yes or no (1);
  # a reply with a line break (1); a plan whose scale: is not task, wave or epic, so there is no
  # default to record against (1); no usable git user name when an override is owed (1); a plan
  # with no leading frontmatter (1). The value in force asked again is the transaction's no-op (0).
  poker_verb_regression() {
    case "$RG_V" in
      yes|no) : ;;
      *)
        die "REFUSED — regression $(clean "$RG_V") is not yes or no; the plan is unchanged."
        exit 1 ;;
    esac
    case "$RG_REPLY" in
      *$'\n'*|*$'\r'*)
        die "REFUSED — the user's reply carries a line break; give it on one line. The plan is unchanged."
        exit 1 ;;
    esac
    plan_verb_open regression
    RG_SCALE="$(plan_frontmatter_get "$PV_PLAN" scale)"
    case "$RG_SCALE" in
      task|epic) RG_DEF=no ;;
      wave) RG_DEF=yes ;;
      *)
        die "REFUSED — the plan's scale: is '$(clean "${RG_SCALE:-none}")', not task, wave or epic, so the regression has no default to record against; the plan is unchanged."
        exit 1 ;;
    esac
    RG_OVR=""
    if [ "$RG_V" != "$RG_DEF" ]; then
      RG_WHO="$(git -C "$PV_REPO" config user.name 2>/dev/null)"
      if [ -z "$RG_WHO" ] || ! plan_verb_value_ok "$RG_WHO"; then
        die "REFUSED — the project has no usable git user name (git config user.name) to record as the one who overrode the $RG_SCALE default; the plan is unchanged."
        exit 1
      fi
      RG_OVR="regression-override: $RG_WHO $(date -u +%Y-%m-%d) derived=$RG_DEF chosen=$RG_V"
    fi
    # THE VALUES GO IN THROUGH THE ENVIRONMENT, as budget's do. The key is rewritten where it stands,
    # its override directly after it; with no key the pair goes in above the closing `---`.
    if ! RG_V="$RG_V" RG_OVR="$RG_OVR" awk '
      function pair() { print "regression: " ENVIRON["RG_V"]; if (ENVIRON["RG_OVR"] != "") print ENVIRON["RG_OVR"]; done = 1 }
      NR == 1 && $0 == "---" { f = 1; print; next }
      f && $0 == "---" { if (!done) pair(); f = 0; closed = 1; print; next }
      f && /^regression-override:/ { next }
      f && /^regression:/ { if (!done) pair(); next }
      { print }
      END { if (!closed) exit 1 }' "$PV_PLAN" > "$PV_NEW" 2>/dev/null; then
      die "REFUSED — $PV_PLAN has no leading frontmatter to write the regression setting into; the plan is unchanged."
      exit 1
    fi
    plan_verb_swap regression "regression: $RG_V" writer
    say "regression — regression: $RG_V${RG_OVR:+ and $RG_OVR} written to $PV_PLAN; dry-committed first. The Step-5 gate reads the key$([ "$RG_V" = no ] && printf ': its block owes regression: no (Step 0, <user>) — <where it runs> in place of the full regression')."
    exit 0
  }

  # THE ROW WAIVER (wave-33 T7; REQ-4 AC-4.1, D8). Wave-32's four row waivers were typed by hand (A-orch-49):
  # the AC block's `  waiver: <who> <ISO-UTC> "<the user's words>" — <why>` line, which the gate reads as the
  # row's waiver (walls.sh `row_is_waived`), and the status cell `waived`. The words are held to the rule a
  # finding's move is (finding-move): lib/said.sh `user_said` finds them, as whole words and at least SAID_MIN_WORDS (three)
  # of them unless they are a whole prompt, in a prompt the user typed in this session. Who is git
  # user.name, the time ISO-UTC, so the hand-holds window can place it. A second waiver of the row
  # replaces the first line. REFUSED (1), the plan unchanged: an AC with no row or no block, no git
  # user.name, words the user did not type, too few words.
  poker_verb_waive_row() {
    if ! declare -F user_said >/dev/null 2>&1 && [ -f "$BIONIC_LIB/said.sh" ]; then
      . "$BIONIC_LIB/said.sh"
    fi
    if ! declare -F user_said >/dev/null 2>&1; then
      die "REFUSED — what the user typed is read by lib/said.sh, which cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    WR_WORDS="$(said_fold "$WR_RAW")"; WR_WHY="$(deferral_fold "$WR_WHY_RAW")"
    plan_verb_open waive-row
    if [ -z "$(matrix_row_cell "$PV_PLAN" "$WR_AC" 1)" ]; then
      die "REFUSED — the matrix table has no row $WR_AC; the plan is unchanged."
      exit 1
    fi
    WR_WHO="$(deferral_fold "$(git -C "$PV_REPO" config user.name 2>/dev/null)")"
    if [ -z "$WR_WHO" ]; then
      die "REFUSED — no git user.name is set for $PV_REPO, and a waiver records who made it; set it, then waive again. The plan is unchanged."
      exit 1
    fi
    user_said "$WR_RAW" "$PV_PLAN"; WR_SAID=$?
    if [ "$WR_SAID" -ne 0 ]; then
      said_refuse "$WR_SAID" "$WR_WORDS" "a waiver"
      exit 1
    fi
    WR_LINE="$WR_WHO $(date -u +%Y-%m-%dT%H:%M:%SZ) \"$(deferral_escape "$WR_WORDS")\" — $WR_WHY"
    PV_RC=0
    matrix_row_cells "$PV_PLAN" "$WR_AC" 3=waived > "$PV_NEW" 2>/dev/null || PV_RC=$?
    if [ "$PV_RC" -eq 0 ]; then
      matrix_block_key "$PV_NEW" "$WR_AC" waiver "$WR_LINE" > "$PV_NEW.2" 2>/dev/null || PV_RC=$((10 + $?))
      [ "$PV_RC" -ne 0 ] || mv -f "$PV_NEW.2" "$PV_NEW"
    fi
    case "$PV_RC" in
      0) : ;;
      4) die "REFUSED — the matrix row $WR_AC does not have five cells, so its status cannot be found; the plan is unchanged."
         exit 1 ;;
      13) die "REFUSED — the matrix has no $WR_AC: block to hold the waiver; matrix-render writes it. The plan is unchanged."
          pv_next matrix-render
          exit 1 ;;
      *) die "REFUSED — the waiver cannot be written (exit $PV_RC); the plan is unchanged."
         exit 2 ;;
    esac
    plan_verb_swap waive-row "the waiver of $WR_AC" writer
    poker_owed_close "$PV_REPO" "waive-row:$WR_AC" "waive-row"
    say "waive-row — $WR_AC waived on the user's words, by $(clean "$WR_WHO"): its waiver: line and status are on $PV_PLAN; dry-committed first."
    exit 0
  }

  # THE USER'S CONFIRMATION OF A T4 ROW. A T4 criterion's check is the user's own, and the gate rules such a row on
  # its block's attributed confirmation under an empty-like auditor cell (walls.sh `matrix_row_ruled`). This verb
  # writes that line from the user's words, so it is never typed by hand:
  #
  #   <key>: <user> <YYYY-MM-DD> "<the user's words>"[ — <why>]
  #
  # <user> is git user.name, as approve and waive-row record it, folded to the one word the attributed form takes:
  # each run of characters outside [A-Za-z0-9._-] becomes one '-'. The date is UTC, as a waiver's is. The line
  # replaces the block's pending stub where it stands. The value is held to walls.sh `user_confirmed_attributed`,
  # the one form test, before it is written, so the verb never writes a line the gate would not rule on. The words
  # are held to lib/said.sh `user_said` as a waiver's are. The key is spelled once, on CR_KEY's line: every reader
  # of it lives in walls.sh, and bash-walls.test.sh allows that one line and nothing else outside it.
  # REFUSED (1), the plan unchanged: no such row, a row that is not T4, no block, no git user.name, a name that
  # folds to no attributed form, words the user did not type. (2): lib/said.sh or walls.sh cannot be loaded.
  poker_verb_confirm_row() {
    CR_KEY=user-confirmed
    if ! declare -F user_said >/dev/null 2>&1 && [ -f "$BIONIC_LIB/said.sh" ]; then
      . "$BIONIC_LIB/said.sh"
    fi
    if ! declare -F user_said >/dev/null 2>&1; then
      die "REFUSED — what the user typed is read by lib/said.sh, which cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    CR_WORDS="$(said_fold "$CR_RAW")"; CR_WHY="$(deferral_fold "$CR_WHY_RAW")"
    plan_verb_open confirm-row
    if [ -z "$(matrix_row_cell "$PV_PLAN" "$CR_AC" 1)" ]; then
      die "REFUSED — the matrix table has no row $CR_AC; the plan is unchanged."
      exit 1
    fi
    CR_TIER="$(matrix_row_cell "$PV_PLAN" "$CR_AC" 2)"
    if [ "$CR_TIER" != T4 ]; then
      die "REFUSED — $CR_AC is a ${CR_TIER:-tierless} row, and only a T4 row's check is the user's own to confirm; the auditor or a waiver rules it. The plan is unchanged."
      exit 1
    fi
    CR_WHO="$(git -C "$PV_REPO" config user.name 2>/dev/null \
      | LC_ALL=C sed -e 's/[^A-Za-z0-9._-][^A-Za-z0-9._-]*/-/g' -e 's/^-*//' -e 's/-*$//')"
    if [ -z "$CR_WHO" ]; then
      die "REFUSED — no git user.name is set for $PV_REPO, and a confirmation records who made it; set it, then confirm again. The plan is unchanged."
      exit 1
    fi
    user_said "$CR_RAW" "$PV_PLAN"; CR_SAID=$?
    if [ "$CR_SAID" -ne 0 ]; then
      said_refuse "$CR_SAID" "$CR_WORDS" "a confirmation"
      exit 1
    fi
    CR_VALUE="$CR_WHO $(date -u +%Y-%m-%d) \"$(deferral_escape "$CR_WORDS")\"${CR_WHY:+ — $CR_WHY}"
    ( . "$BIONIC_LIB/walls.sh" >/dev/null 2>&1 && declare -F user_confirmed_attributed >/dev/null 2>&1 || exit 2
      user_confirmed_attributed "$CR_VALUE" ); CR_FORM=$?
    case "$CR_FORM" in
      0) : ;;
      1) die "REFUSED — git user.name folds to '$(clean "$CR_WHO")', which is not the one word, starting with a letter, that the gate reads as who confirmed; set user.name so it does. The plan is unchanged."
         exit 1 ;;
      *) die "REFUSED — the confirmation's form is walls.sh's to judge, and $BIONIC_LIB/walls.sh cannot be loaded; the plan is unchanged."
         exit 2 ;;
    esac
    PV_RC=0
    matrix_block_key "$PV_PLAN" "$CR_AC" "$CR_KEY" "$CR_VALUE" > "$PV_NEW" 2>/dev/null || PV_RC=$?
    case "$PV_RC" in
      0) : ;;
      3) die "REFUSED — the matrix has no $CR_AC: block to hold the confirmation; matrix-render writes it. The plan is unchanged."
         pv_next matrix-render
         exit 1 ;;
      *) die "REFUSED — the confirmation cannot be written (exit $PV_RC); the plan is unchanged."
         exit 2 ;;
    esac
    plan_verb_swap confirm-row "the confirmation of $CR_AC" writer
    say "confirm-row — $CR_AC confirmed on the user's words: $CR_KEY: $(clean "$CR_VALUE") is in its block on $PV_PLAN; dry-committed first."
    exit 0
  }

  # THE APPROVAL (wave-26 T13; D3, AC-6.2). A row that reads `approval:<name>` is not ready, and
  # the dispatch wall refuses it, until `## SDLC State` carries
  #
  #   approved: <name> by <who> <ISO-UTC> head=<40-hex> "<reply>"
  #
  # written here on the user's reply and nowhere else: `<who>` is the project's git user name,
  # the instant is `date -u`, the head is the working branch's (lib/proof.sh `proof_branch_head`;
  # no head= when the plan names no branch with a commit), the reply is the user's own words. It
  # goes through the plan transaction every row verb takes (copy, dry commit through the real gate,
  # checksum, swap), beside the approval lines already there — after the last `approved:` or
  # `approved-by:` line, else after `current:`. An approval is recorded once: a second `approve` of
  # a name the plan already carries is refused, so the first reply stands, except `release` at a
  # head its newest line does not name: the release is approved per head. `plan` is refused
  # by name: the plan's approval is the `approved-by:` line Step 3 writes, which `approval:plan` reads.
  poker_verb_approve() {
    if [ "$AP_NAME" = plan ]; then
      die "REFUSED — approval:plan is the plan's approved-by: line, written at Step 3 when the user approves the plan card; approve records any other approval a row reads (approval:<name>). The plan is unchanged."
      exit 1
    fi
    case "$AP_REPLY" in
      *$'\n'*|*$'\r'*)
        die "REFUSED — an approval line is one line, and the reply carries a line break; the plan is unchanged."
        exit 1 ;;
    esac
    plan_verb_open approve
    # A NAME NO ROW READS IS REFUSED (wave-26 T46; review 10 F6). `approve relase` used to be
    # recorded "once" while the release kept waiting in silence; the names the rows read, as
    # `approval:<name>` or `live:approval:<name>` (units.sh `units_approval_names`), are the only
    # names an approval can satisfy. Exact match, case included, as readiness keys it.
    AP_READ="$(units_approval_names "$PV_PLAN" | /usr/bin/grep -v '^plan$' | tr '\n' ' ' | sed 's/ $//')"
    case " $AP_READ " in
      *" $AP_NAME "*) : ;;
      *)
        die "REFUSED — no row in $PV_PLAN reads approval:$AP_NAME, so recording it would satisfy nothing; the rows read: ${AP_READ:-(no named approval)}. Approve one of those names exactly; the plan is unchanged."
        exit 1 ;;
    esac
    AP_HAVE="$(awk -v want="$AP_NAME" '
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc {
        l = $0; sub(/^[ \t]*-?[ \t]*/, "", l)
        if (l !~ /^approved[ \t]*:/) next
        sub(/^approved[ \t]*:[ \t]*/, "", l); split(l, w, /[ \t]+/)
        if (w[1] == want) { print $0; exit }
      }' "$PV_PLAN")"
    AP_HEAD="$(proof_branch_head "$PV_PLAN" "$PV_REPO" 2>/dev/null)" || AP_HEAD=""
    case "$AP_HEAD" in *[!0-9a-f]*|'') AP_HEAD="" ;; esac
    if [ -n "$AP_HAVE" ]; then
      AP_WAS="$(proof_approved_head "$PV_PLAN" "$AP_NAME" 2>/dev/null)" || AP_WAS=""
      if [ "$AP_NAME" != release ] || [ -z "$AP_HEAD" ] || [ "$AP_WAS" = "$AP_HEAD" ]; then
        die "REFUSED — $PV_PLAN already records this approval: $(clean "$AP_HAVE"). An approval is recorded once; the plan is unchanged."
        exit 1
      fi
    fi
    AP_WHO="$(git -C "$PV_REPO" config user.name 2>/dev/null)"
    if [ -z "$AP_WHO" ] || ! plan_verb_value_ok "$AP_WHO"; then
      die "REFUSED — the project has no usable git user name (git config user.name) to record as the approver; the plan is unchanged."
      exit 1
    fi
    AP_LINE="approved: $AP_NAME by $AP_WHO $(date -u +%Y-%m-%dT%H:%M:%SZ)${AP_HEAD:+ head=$AP_HEAD} \"$AP_REPLY\""
    # THE LINE GOES IN THROUGH THE ENVIRONMENT, not `-v`, which would read a backslash in the
    # user's reply as an escape and write a different reply than the one given.
    if ! AP_LINE="$AP_LINE" awk '
      { L[++n] = $0 }
      END {
        for (i = 1; i <= n; i++) {
          if (L[i] ~ /^[[:space:]]*```/) { fence = !fence; continue }
          if (fence) continue
          if (L[i] ~ /^##[[:space:]]/) { if (insdlc) break; insdlc = (L[i] ~ /^##[[:space:]]+SDLC State/); continue }
          if (!insdlc) continue
          if (L[i] ~ /^[[:space:]]*approved(-by)?[[:space:]]*:/) at = i
          else if (!at && !cur && L[i] ~ /^[[:space:]]*current[[:space:]]*:/) cur = i
        }
        if (!at) at = cur
        if (!at) exit 1
        for (i = 1; i <= n; i++) { print L[i]; if (i == at) print ENVIRON["AP_LINE"] }
      }' "$PV_PLAN" > "$PV_NEW" 2>/dev/null; then
      die "REFUSED — $PV_PLAN carries no current: line under ## SDLC State to write the approval beside; the plan is unchanged."
      exit 1
    fi
    plan_verb_swap approve "approved: $AP_NAME" writer
    poker_owed_close "$PV_REPO" "approve:$AP_NAME" "approve"
    say "approve — $AP_NAME: approved: $AP_NAME by $AP_WHO written to $PV_PLAN; dry-committed first."
    exit 0
  }

  # THE PROOF VERB (wave-26 T4; REQ-3 AC-3.2, D5). Nothing recorded which code state a test pass
  # or a review read, so the same code was proved again and again. A proof is one line under
  # `## SDLC State` — `proved: kind=<kind> head=<40-hex> at=<ISO-UTC> evidence=<record/ path>`
  # (payload/scripts/lib/proof.sh owns its shape and its reader, `proof_last`) — and what is
  # unproved is the difference since the head it names. The head is the one the evidence attests
  # (its run header or its reviewed: range, held against the working branch's ref; T14, wave-36 T12),
  # never an operand. The line goes in through the shared transaction; every refusal below
  # leaves the plan byte-identical and names its fix. proof.sh is loaded here, for this verb alone, as brief.sh is for task-add and amend:
  # the tick never reads it, so it is not one of the libraries every verb needs.
  poker_verb_proof_add() {
    if ! { declare -F proof_last >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_add_line >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    # INHERITED DEBT (wave-35 T9; D8, AC-1.6; ADR-054). A suite the floor's whole run left red that is ALSO red
    # at the run's base commit is debt the run inherited, not a regression it made. This verb asks the base
    # itself: it makes a scratch tree at `base-sha:` through spawn-worktree.sh, runs the suite there (the
    # project's tests/run.sh --only <suite> when the base has one, else the suite file), keeps the run's
    # log in the record, and removes the tree and its branch. Red there, it writes
    #
    #     inherited: <suite> base=<base> head=<the floor's head> at=<ISO-UTC> evidence=record/<wave>/<log>
    #
    # under `## SDLC State` through the plan transaction, and the judge (lib/proof.sh `_proof_floor_judge`)
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
      PF_LINE="inherited: $PF_SUITE base=$PF_BASEH head=$PF_FHEAD at=$(iso_now) evidence=$PF_REL"
      if ! proof_add_line "$PV_PLAN" "$PF_LINE" > "$PV_NEW" 2>/dev/null || [ ! -s "$PV_NEW" ]; then
        die "REFUSED — $PV_PLAN carries no ## SDLC State section to hold the line; the plan is unchanged."
        exit 1
      fi
      plan_verb_swap proof-add "$PF_SUITE inherited at ${PF_BASEH:0:12}" writer
      say "proof-add — inherited: $PF_SUITE red at the base ${PF_BASEH:0:12} (rc=$PF_RC) and at the regression's head ${PF_FHEAD:0:12}; written to $PV_PLAN, its log $PF_REL; the regression stands on the rest."
      exit 0
    fi
    if ! proof_kind_ok "$PF_KIND"; then
      die "REFUSED — '$(clean "$PF_KIND")' is not a proof kind: name regression, review or task (or proof-add inherited <suite>). The plan is unchanged."
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
        case "$_pf_c" in '') continue ;; /*) _pf_p="$_pf_c" ;; *) _pf_p="$PV_REPO/${_pf_c#./}" ;; esac
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
          case "$_pf_c" in '') continue ;; /*) _pf_p="$_pf_c" ;; *) _pf_p="$PV_REPO/${_pf_c#./}" ;; esac
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
      die "REFUSED — $PV_PLAN names no working-branch:, so there is no checkout to read the head from; add 'working-branch: <branch>' under ## SDLC State. The plan is unchanged."
      exit 1
    fi
    # THE WORKING HEAD IS THE BRANCH'S REF (wave-36 T12; D13, AC-7.4; C30): lib/proof.sh `proof_branch_head`, as the
    # judge reads it, so a reading of a merged branch whose worktree is gone still registers.
    PF_HEAD="$(proof_branch_head "$PV_PLAN" "$PV_REPO")" || PF_HEAD=""
    case "$PF_HEAD" in
      [0-9a-f]*) : ;;
      *)
        die "REFUSED — working-branch $(clean "$PF_WB") names no commit in $PV_REPO, so its head cannot be read; name a branch that exists under ## SDLC State and run proof-add again. The plan is unchanged."
        exit 1 ;;
    esac
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
    # ONE RECORD PATH IS ONE PASS (wave-28 T60; REQ-8 AC-8.6, D33). A `deferred:` or `moved:` line is
    # keyed `<record>#<n>`, so a second pass registered on the path of a first would inherit its deferral
    # or its move (a #1 moved to defer defers the new pass's fix). A reading's path whose proof line names
    # another head is refused, and so is one such a line already names (lib/proof.sh `proof_bind_awk` is
    # the one predicate, T72); a relaunched reader re-registering a record no such line names (the same
    # head) is admitted as before. A `check:` line binds nothing (wave-31 T32; D6).
    if [ -n "$PF_QUESTION" ]; then
      PF_PASS="$(proof_pass_conflict "$PV_PLAN" "$PF_REL" "$PF_HEAD")"
      case "$PF_PASS" in
        head\ *)
          die "REFUSED — $(clean "$PF_REL") is already registered at $(clean "${PF_PASS#head }" | cut -c1-12), not ${PF_HEAD:0:12}: write the pass to a new record path. The plan is unchanged."
          exit 1 ;;
        settled\ *)
          die "REFUSED — $(clean "$PF_REL") at ${PF_HEAD:0:12} already has a deferred: or moved: line: write the pass to a new record path. The plan is unchanged."
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
    PF_LINE="$(proof_line "$PF_KIND" "$PF_HEAD" "$(iso_now)" "$PF_REL" "$PF_QUESTION" "$PF_READER" "$PF_RESULT" "$PF_SCOPE")"
    # A RED WHOLE RUN'S REDS RIDE ON ITS LINE (wave-35 T9; D8, AC-1.3): proof_attested took each log and every red
    # named; the line lists them as owed, and the judge reads them there. Its evidence= is the logs, comma-joined (T35).
    if [ "$PF_KIND" = regression ]; then
      PF_LINE="$(proof_floor_line "$PF_HEAD" "$(iso_now)" "$PF_REL" "$PF_OWED" "run=$PF_RUNAT head=$PF_HEAD rc=$PF_RUNRC")"
    fi
    # A RATED READING WRITES ITS PLAN LINES (wave-28 T15; D19, D21): one `deferred:` line per finding
    # the table defers, right after its proof line, in the same write (lib/proof.sh
    # `proof_finding_lines`). No `check:` line: a reader's rating is final (wave-31 T32; D6).
    PF_PLANL=""
    [ "$PF_SEV" = 1 ] && PF_PLANL="$(proof_finding_lines "$PF_REL" "$(proof_findings "$PF_REAL")")"
    [ -z "$PF_PLANL" ] || PF_LINE="$PF_LINE
$PF_PLANL"
    if ! proof_add_line "$PV_PLAN" "$PF_LINE" > "$PV_NEW" 2>/dev/null || [ ! -s "$PV_NEW" ]; then
      die "REFUSED — $PV_PLAN carries no ## SDLC State section to hold the proof; the plan is unchanged."
      exit 1
    fi
    # A REVIEW THAT FOLLOWS THE BUILD GOES BACK TO WAITING (wave-26 T14; D10). The active review
    # row reading `live:head` (`units_live_rows`, the kind default included) whose `Files` hold
    # this evidence returns to `pending` in the same write — that row alone: the proof of another
    # review, the settled final one among them, leaves a live pass still running where it is
    # (wave-26 T46; review 10 F3). A READING RETURNS THE ROW CARRYING ITS QUESTION (wave-27 T10;
    # D4): handed --question, `units_live_rows` finds a read row by the question it read, not by
    # its Files, so a second pass written under a new name still returns its row, and that row
    # alone; a bare row is still found by its Files. The evidence is handed in both spellings, from the docs root
    # (`record/…`) and from the repository, so a Files cell in either matches. It returns with
    # its agent, worktree and base cells cleared: the row is one row across every pass, each pass
    # its own launch — the launch recorder sets it active again and adds that pass's ledger line,
    # so the ledger is not touched here (A-T14.4). The next landing past this proof makes it
    # ready again (units.sh `live_head`).
    # A READ ROW RETURNS ONLY TO ITS OWN READER, AND ONLY WHOLE (wave-27 T43; review pass 17 F3):
    # handed --reader, `units_live_rows` names a read row only when its agent cell is this reader
    # and every question it carries now has a reading at this head; until then it stays active and
    # is not offered, and PF_HELD names it. A row abandoned part-way is returned by task-set.
    PF_BACK=""; PF_HELD=""
    if [ "$PF_KIND" = review ]; then
      PF_DOCREL="$(docs_root "$PV_REPO")"
      case "$PF_DOCREL" in "$PV_REPO"/*) PF_DOCREL="${PF_DOCREL#"$PV_REPO"/}/$PF_REL" ;; *) PF_DOCREL="" ;; esac
      [ -z "$PF_QUESTION" ] || PF_HELD="$(units_live_rows "$PV_NEW" --question "$PF_QUESTION" 2>/dev/null \
        | awk -F'\t' '$2 == "review" && $3 == "active" { printf "%s%s", (n++ ? " " : ""), $1 }')"
      for _pf_id in $(units_live_rows "$PV_NEW" ${PF_QUESTION:+--question "$PF_QUESTION" --reader "$PF_READER"} "$PF_REL" $PF_DOCREL 2>/dev/null | awk -F'\t' '$2 == "review" && $3 == "active" { print $1 }'); do
        _pf_cells=(status=pending agent=—)
        units_has_column "$PV_NEW" worktree && _pf_cells+=(worktree=—)
        units_has_column "$PV_NEW" base && _pf_cells+=(base=—)
        if ! units_table_cells "$PV_NEW" set tasks "$_pf_id" "${_pf_cells[@]}" > "$PV_NEW.back" 2>/dev/null || [ ! -s "$PV_NEW.back" ]; then
          rm -f "$PV_NEW.back"
          die "REFUSED — review row $_pf_id could not be returned to pending in $PV_PLAN; the plan is unchanged."
          exit 1
        fi
        mv "$PV_NEW.back" "$PV_NEW"
        PF_BACK="${PF_BACK:+$PF_BACK }$_pf_id"
        PF_HELD=" $PF_HELD "; PF_HELD="${PF_HELD/ $_pf_id / }"; PF_HELD="${PF_HELD# }"; PF_HELD="${PF_HELD% }"
      done
      [ -z "$PF_HELD" ] || PF_HELD="$(units_rows "$PV_NEW" 2>/dev/null | awk -F'\t' -v ids=" $PF_HELD " -v r="$PF_READER" \
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
      _pf_live=" $(units_live_rows "$PV_NEW" 2>/dev/null | awk -F'\t' '$2 == "review" && $3 == "active" { printf "%s ", $1 }')"
      [ "$_pf_live" = " " ] || PF_NONE="$(units_rows "$PV_NEW" 2>/dev/null | awk -F'\t' -v ids="$_pf_live" '
        index(ids, " " $1 " ") { printf "%s%s (%s)", (n++ ? ", " : ""), $1, $9 }')"
    fi
    plan_verb_swap proof-add "the $PF_KIND proof at $PF_HEAD" writer
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
    say "proof-add — kind=$PF_KIND head=$PF_HEAD evidence=$PF_REL$PF_FIELDS${PF_OWED:+ owed=$PF_OWED}: written to $PV_PLAN${PF_BACK:+; $PF_BACK back to pending}; dry-committed first."
    [ -z "$PF_OWED" ] || say "proof-add — the whole run left $PF_OWED red: each is owed until a later landing runs it green (a fix row), or proof-add inherited <suite> finds it red at the base too."
    [ -z "$PF_PLANL" ] || printf '%s\n' "$PF_PLANL" | while IFS= read -r _pf_l; do say "proof-add — $_pf_l"; done
    [ -n "$PF_HELD" ] && say "proof-add — $PF_HELD stays active until every question it carries is read at ${PF_HEAD:0:12}; it returns to pending on that review."
    [ -n "$PF_NONE" ] && say "proof-add — no active live review row holds $PF_REL in its Files: $PF_NONE stays active, nothing was returned to pending. If this record is that pass, its Files name another record: write the record under that name, or amend the row's Files."
    exit 0
  }

  # THE WAIVER (wave-27 T9; D2). The user's act, on their reply: one line under `## SDLC State`,
  #
  #   waived: question=<q> head=<working head> by <git user.name> <ISO-UTC> "<reply>"
  #
  # covering that question up to the head the plan's working branch's ref names, the head the judge
  # (lib/proof.sh `facts_state`) is asked about. It goes in through the plan transaction, placed
  # with the proof lines by `proof_add_line`, so a fact written after it is newer than it.
  # `waive all` writes three, evidence, adversarial and structure, in that order, in one transaction. The regression
  # is never waived: it runs once after the build.
  poker_verb_waive() {
    if ! { declare -F proof_waiver_line >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_waiver_line >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    if ! proof_question_ok "$WV_Q" waive; then
      die "REFUSED — '$(clean "$WV_Q")' is not a question to waive: name evidence, adversarial, structure or all. The plan is unchanged."
      exit 1
    fi
    WV_QS="$WV_Q"; [ "$WV_Q" != all ] || WV_QS="$PROOF_QUESTIONS"
    case "$WV_REPLY" in
      *$'\n'*|*$'\r'*)
        die "REFUSED — a waiver line is one line, and the reply carries a line break; the plan is unchanged."
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
    WV_AT="$(iso_now)"; WV_LINE=""
    for _wv_q in $WV_QS; do
      WV_LINE="${WV_LINE}${WV_LINE:+$'\n'}$(proof_waiver_line "$_wv_q" "$WV_HEAD" "$WV_WHO" "$WV_AT" "$WV_REPLY")"
    done
    if ! proof_add_line "$PV_PLAN" "$WV_LINE" > "$PV_NEW" 2>/dev/null || [ ! -s "$PV_NEW" ]; then
      die "REFUSED — $PV_PLAN carries no ## SDLC State section to hold the waiver; the plan is unchanged."
      exit 1
    fi
    plan_verb_swap waive "the $WV_Q waiver at $WV_HEAD" writer
    for _wv_q in $WV_QS; do
      poker_owed_close "$PV_REPO" "waive:$_wv_q" "waive"
      waive_owed_findings "$PV_PLAN" "$PV_REPO" "$_wv_q"
      say "waive — question=$_wv_q head=$WV_HEAD by $WV_WHO: written to $PV_PLAN; dry-committed first."
    done
    exit 0
  }

  # THE DEFERRAL'S SENTENCE (wave-28 T17; D21, AC-8.7). Stores the one changelog sentence of a deferred
  # finding on its `deferred:` line, through the plan transaction, as ` stated="<sentence>"` (the
  # helpers above hold the form). Stating twice replaces; the line is never given a second field.
  # A finding with no `deferred:` line (a note, a fix, a check owed) is not stated: the verb refuses
  # it. A sentence of `-` is refused, for `-` is what the continuation writes for no sentence.
  poker_verb_finding_stated() {
    FS_SENT="$(deferral_fold "$FS_RAW")"
    if [ -z "$FS_SENT" ]; then
      die "REFUSED — the sentence is empty once its white space is folded; the plan is unchanged."
      exit 1
    fi
    if [ "$FS_SENT" = "-" ]; then
      die "REFUSED — '-' is what the continuation writes for a deferral with no sentence, so it cannot be one; the plan is unchanged."
      exit 1
    fi
    plan_verb_open finding-stated
    if ! deferral_line "$PV_PLAN" "$FS_ID" >/dev/null; then
      die "REFUSED — $PV_PLAN carries no deferred: line for $(clean "$FS_ID") under ## SDLC State, and only a deferral is stated; the plan is unchanged."
      exit 1
    fi
    FS_TAIL=" stated=\"$(deferral_escape "$FS_SENT")\""
    FS_TAIL="$FS_TAIL" awk -v id="$FS_ID" '
      /^[[:space:]]*```/ { fence = !fence; print; next }
      fence { print; next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); print; next }
      insdlc && !done && /^deferred:[ \t]/ {
        split($0, f, /[ \t]+/)
        if (f[2] == id) {
          done = 1; l = $0; i = index(l, " stated=\"")
          if (i) l = substr(l, 1, i - 1)
          sub(/[ \t]+$/, "", l); print l ENVIRON["FS_TAIL"]; next
        }
      }
      { print }' "$PV_PLAN" > "$PV_NEW"
    plan_verb_swap finding-stated "the sentence of $FS_ID" writer
    say "finding-stated — $(clean "$FS_ID"): its sentence is on the deferred: line of $PV_PLAN; dry-committed first."
    exit 0
  }

  # A MOVE IS THE USER'S PROVEN WORD (wave-28 T42; REQ-8 AC-8.9, D34). A registered finding — one whose
  # record a `proved:` line names as its evidence — is moved across the line, to defer or to fix, only
  # on words lib/said.sh `user_said` finds in a prompt the user typed in this session's transcript (a
  # tool's result, a teammate's or another session's message, a hook's context and the orchestrator's
  # own text never count; rc 2, no transcript, refuses too; the words stand as WHOLE WORDS and are at
  # least SAID_MIN_WORDS (three) of them unless they are a whole typed prompt, rc 3 refusing the short ones, T66). An S1, at the rating every read gives it
  # (lib/proof.sh `proof_finding_rating`), is never deferred. The move is written in place after the
  # finding's last line, through the plan transaction:
  #
  #   moved: <record>#<n> to=<defer|fix> by=<git user.name> at=<ISO-UTC> words="<words>" session=<sid> why="<why>"
  #
  # the words are looked for in every session the plan records, then this one (wave-36 T9; D10), and
  # session= names the one whose transcript holds them (lib/said.sh SAID_SESSION);
  #
  # the words folded to one line by lib/said.sh's own fold (`said_fold`, the rule the check is made
  # through; the verb passes the raw words to `user_said`), the why by `deferral_fold` (the same fold), both escaped as a
  # deferral's sentence is (`deferral_escape`); a move to defer first writes the finding's `deferred:`
  # line when the plan holds none (placed by `proof_add_line`). Every read then takes the priority the last move gave it.
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
  # owed item closes, as `task-add --born` closes it.
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
    plan_verb_open finding-move
    FM_REC="${FM_ID%#*}"; FM_N="${FM_ID##*#}"
    if ! awk -v ev="$FM_REC" '
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc && /^proved:[ \t]/ { m = split($0, f, /[ \t]+/); for (i = 2; i <= m; i++) if (f[i] == "evidence=" ev) hit = 1 }
      END { exit !hit }' "$PV_PLAN"; then
      die "REFUSED — $(clean "$FM_REC") is no review registered under ## SDLC State (no proved: line names it as its evidence), and only a registered finding is moved; the plan is unchanged."
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
    set -- $(proof_finding_rating "$PV_PLAN" "$FM_ID" "$FM_S" "$FM_R")
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
    if [ -z "$FM_ROW" ]; then
      user_said "$FM_RAW" "$PV_PLAN"; FM_SAID=$?
      if [ "$FM_SAID" -ne 0 ]; then
        said_refuse "$FM_SAID" "$FM_WORDS" "a move"
        exit 1
      fi
    fi
    cp "$PV_PLAN" "$PV_NEW"
    FM_DEF=""
    if [ "$FM_TO" = defer ] && ! deferral_line "$PV_PLAN" "$FM_ID" >/dev/null; then
      FM_DEF="deferred: $FM_ID $FM_S $FM_R \"$(printf '%s' "$FM_TITLE" | tr '"' "'")\""
      if ! proof_add_line "$PV_NEW" "$FM_DEF" > "$PV_NEW.2" 2>/dev/null || [ ! -s "$PV_NEW.2" ]; then
        die "REFUSED — the deferred: line for $(clean "$FM_ID") could not be placed under ## SDLC State; the plan is unchanged."
        exit 1
      fi
      mv -f "$PV_NEW.2" "$PV_NEW"
    fi
    if [ -n "$FM_ROW" ]; then
      FM_LINE="moved: $FM_ID to=$FM_TO row=$FM_ROW by=$FM_WHO at=$(iso_now)"
    else
      FM_LINE="moved: $FM_ID to=$FM_TO by=$FM_WHO at=$(iso_now) words=\"$(deferral_escape "$FM_WORDS")\" session=$SAID_SESSION why=\"$(deferral_escape "$FM_WHY")\""
    fi
    # IN PLACE: after the last line of the block naming the finding (its deferred:, check: or an earlier
    # moved: line), else after the last proof line naming its record; else where proof_add_line puts it.
    FM_LINE="$FM_LINE" awk -v id="$FM_ID" -v ev="$FM_REC" '
      BEGIN { L = ENVIRON["FM_LINE"] }
      { row[NR] = $0 }
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc && /^(deferred|check|moved):[ \t]/ { split($0, f, /[ \t]+/); if (f[2] == id) own = NR }
      insdlc && /^proved:[ \t]/ { m = split($0, f, /[ \t]+/); for (i = 2; i <= m; i++) if (f[i] == "evidence=" ev) pr = NR }
      END {
        at = own ? own : pr
        if (!at) exit 1
        for (i = 1; i <= NR; i++) { print row[i]; if (i == at) print L }
      }' "$PV_NEW" > "$PV_NEW.2" && [ -s "$PV_NEW.2" ] || {
      die "REFUSED — the moved: line for $(clean "$FM_ID") could not be placed under ## SDLC State; the plan is unchanged."
      exit 1
    }
    mv -f "$PV_NEW.2" "$PV_NEW"
    plan_verb_swap finding-move "the move of $FM_ID" writer
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
      say "finding-move — $(clean "$FM_ID") carried to $FM_ROW, by $(clean "$FM_WHO"): its moved: line is on $PV_PLAN; dry-committed first. The finding stays open and closes when $FM_ROW lands."
      exit 0
    fi
    if [ -n "$FM_ROW" ]; then
      poker_owed_close "$PV_REPO" "$(finding_owed_key "$FM_ID")" "finding-move fixed $FM_ROW"
      [ "$FM_ROW_ST" != landed ] || say "finding-move — $(clean "$FM_ID") carried to $FM_ROW, which has landed: the carry is that row's fix, written as a move to fixed, and its ask is closed now."
      say "finding-move — $(clean "$FM_ID") fixed by $FM_ROW, by $(clean "$FM_WHO"): its moved: line is on $PV_PLAN; dry-committed first. It reads fixed once $FM_ROW has landed green, and counts against no fix-cap."
      exit 0
    fi
    say "finding-move — $(clean "$FM_ID") to $FM_TO on the user's words, by $(clean "$FM_WHO"): its moved: line is on $PV_PLAN; dry-committed first."
    [ -z "$FM_DEF" ] || say "finding-move — $(clean "$FM_DEF")"
    exit 0
  }

  # THE REVIEW DISPOSITION (wave-33 T13; REQ-5 AC-5.1, D6). One pass over every registered reading (each record a
  # `proved: kind=review` line with a question names as its evidence, its last such line giving its question and
  # head) prints one line per finding:
  #
  #   finding <record>#<n> <S> user-facing=<on|off> record=<record> at=<path:line|-> row=<T<k>[,…]|—>
  #           state=<open|fixed|deferred|accepted> decision="<what it needs>" [stated="<sentence>"|stated=-] title="<title>"
  #
  # the state read as the judge reads it: fixed when a row born of it landed green at or after the reading's head,
  # or the row its newest move names (`moved: … to=fixed row=<T>`, wave-36 T8) landed green whatever its ancestry
  # (lib/proof.sh `proof_fixed`), decision="none: fixed by <row>, landed green at <commit>"; else by the priority
  # the plan's moves give it (`proof_finding_rating`): fix is open, defer is deferred, note is accepted. row= names
  # the rows born of it and the row a move to fixed names. An open finding no row answers and no ruling has moved
  # needs the person, and gets one owed item, `finding_owed_key` (lib/owed.sh; opening is idempotent per key). A reading's
  # debt: lines go to the run's debt ledger through `debt add`, run as a child. Nothing in the plan is written.
  #
  # A RULING (four or five operands) is the person's word on one finding, recorded through finding-move (their
  # words, typed, at least SAID_MIN_WORDS whole words; an S1 is never deferred) and, for a deferral given a sentence,
  # finding-stated, each run as a child so each keeps its own transaction; then a fix closes the finding's owed item,
  # and a deferral leaves it open, answered carry, until the release approval card's reply.
  poker_verb_disposition() {
    if ! { declare -F proof_fixed >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_fixed >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    plan_verb_open disposition
    if [ -n "$DSP_ID" ] && ! finding_read "$PV_PLAN" "$PV_REPO" "$DSP_ID"; then
      die "REFUSED — $FR_WHY; the plan is unchanged."
      exit 1
    fi
    if [ -n "$DSP_ID" ]; then
      DSP_OUT="$( cd "$PV_REPO" && "${BASH:-bash}" "$HOOK_DIR/session-poker.sh" finding-move "$DSP_ID" "$DSP_TO" "$DSP_RAW" "$DSP_WHY" 2>&1 )"; DSP_RC=$?
      [ -z "$DSP_OUT" ] || printf '%s\n' "$DSP_OUT"
      [ "$DSP_RC" = 0 ] || exit "$DSP_RC"
      if [ -n "$DSP_SENT" ]; then
        DSP_OUT="$( cd "$PV_REPO" && "${BASH:-bash}" "$HOOK_DIR/session-poker.sh" finding-stated "$DSP_ID" "$DSP_SENT" 2>&1 )"; DSP_RC=$?
        [ -z "$DSP_OUT" ] || printf '%s\n' "$DSP_OUT"
        [ "$DSP_RC" = 0 ] || { die "disposition — the move of $(clean "$DSP_ID") is written; its sentence is not: run finding-stated $(clean "$DSP_ID") '<sentence>' again."; exit "$DSP_RC"; }
      fi
      # A fix ends the ask: a row born of it answers the finding. A deferral was answered carry by finding-move and
      # its item stays open until the event it waits on.
      if [ "$DSP_TO" = defer ]; then
        say "disposition — $(clean "$DSP_ID") ruled defer on the person's words; its owed item stays open, answered carry: it waits on the release approval card."
        exit 0
      fi
      poker_owed_close "$PV_REPO" "$(finding_owed_key "$DSP_ID")" "disposition"
      say "disposition — $(clean "$DSP_ID") ruled $DSP_TO on the person's words; its owed item is closed."
      exit 0
    fi
    DSP_DOCS="$(docs_root "$PV_REPO")"
    DSP_FIXED="$(proof_fixed "$PV_PLAN" "$PV_REPO")"
    DSP_REC="$(proof_debt_record "$PV_PLAN" "$PV_REPO")" || DSP_REC=""
    DSP_BORN="$(units_born_findings "$PV_PLAN" 2>/dev/null)" || DSP_BORN=""
    DSP_READS="$(awk "$(proof_awk)"'
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc && proof_fields($0) && PROOF_KIND == "review" && PROOF_QUESTION != "" && PROOF_EVIDENCE != "" {
        if (!(PROOF_EVIDENCE in q)) ord[++n] = PROOF_EVIDENCE
        q[PROOF_EVIDENCE] = PROOF_QUESTION; h[PROOF_EVIDENCE] = PROOF_HEAD
      }
      END { for (i = 1; i <= n; i++) printf "%s\t%s\t%s\n", ord[i], q[ord[i]], h[ord[i]] }' "$PV_PLAN")"
    DSP_NF=0; DSP_NR=0; DSP_NP=0
    while IFS='	' read -r DSP_EV DSP_Q DSP_H; do
      [ -n "$DSP_EV" ] || continue
      DSP_NR=$((DSP_NR + 1))
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
        DSP_NF=$((DSP_NF + 1))
        set -- $(proof_finding_rating "$PV_PLAN" "$DSP_FID" "$DSP_S" "$DSP_R")
        DSP_P="${3:-}"
        DSP_ROWS="$(printf '%s\n' "$DSP_BORN" | awk -F'\t' -v id="$DSP_FID" '$3 == id { printf "%s%s", (k++ ? "," : ""), $1 }')"
        if [ "$(_proof_moved_to "$PV_PLAN" "$DSP_FID")" = fixed ]; then
          DSP_MV="$(proof_move_line "$PV_PLAN" "$DSP_FID" | awk '{ sub(/^row=/, "", $4); print $4 }')"
          case ",$DSP_ROWS," in *",$DSP_MV,"*) : ;; *) DSP_ROWS="${DSP_ROWS:+$DSP_ROWS,}$DSP_MV" ;; esac
        fi
        DSP_STATED=""
        case "$_PROOF_FIXED_IDS" in
          *$'\n'"$DSP_FID"$'\n'*)
            DSP_STATE=fixed
            DSP_FROW="$(printf '%s\n' "$DSP_FIXED" | awk -F'\t' -v id="$DSP_FID" '$1 == id { print $2 "\t" $3; exit }')"
            DSP_DEC="none: fixed by ${DSP_FROW%%	*}, landed green at $(printf '%.12s' "${DSP_FROW#*	}")"
            # A landing no green verdict names is fixed by the first green whole run that descends from it.
            if ! { [ -f "$DSP_REC" ] && /usr/bin/grep -F "|row=${DSP_FROW%%	*}|commit=${DSP_FROW#*	}|" "$DSP_REC" | /usr/bin/grep -qF "|result=green|"; }; then
              for DSP_RH in $(_proof_regression_heads "$PV_PLAN" "$DSP_REC"); do
                git -C "$PV_REPO" merge-base --is-ancestor "${DSP_FROW#*	}" "$DSP_RH" 2>/dev/null || continue
                DSP_DEC="none: ${DSP_FROW%%	*} landed on no suite; fixed by the regression at $(printf '%.12s' "$DSP_RH")"; break
              done
            fi ;;
          *)
            case "$DSP_P" in
              fix)
                DSP_STATE=open
                if [ -n "$DSP_ROWS" ]; then
                  DSP_DEC="none: waits on $DSP_ROWS landing green"
                elif [ -n "$(_proof_moved_to "$PV_PLAN" "$DSP_FID")" ]; then
                  DSP_DEC="a row born of it: task-add <id> … --born $DSP_FID"
                else
                  if [ "$DSP_S" = S1 ]; then DSP_DEC="the person's: fix it or waive $DSP_Q (an S1 is never deferred)"
                  else DSP_DEC="the person's: fix it, defer it, or waive $DSP_Q"; fi
                  DSP_NP=$((DSP_NP + 1))
                  if declare -F owed_open >/dev/null 2>&1; then
                    OWED_ROOT="$PV_REPO" owed_open "$(finding_owed_key "$DSP_FID")" "Finding $DSP_S needs a ruling" \
                      "$(clean "$DSP_FID") $DSP_S $DSP_R: $(clean "$DSP_T") — $DSP_DEC" >/dev/null 2>&1 || :
                  fi
                fi ;;
              defer)
                DSP_STATE=deferred
                # A DEFERRAL NO PERSON RULED IS A CARRY THE RUN CHOSE: the reader's rating deferred it and the run carries
                # it on, so it is an ask until the release approval card rules it. A move to defer is the person's own
                # ruling (finding-move takes their words), and owes nothing more.
                [ -n "$(_proof_moved_to "$PV_PLAN" "$DSP_FID")" ] \
                  || proof_owed open "$(carry_owed_key "$DSP_FID")" "Carried $DSP_S finding" \
                       "$(clean "$DSP_FID") $DSP_S $DSP_R: $(clean "$DSP_T") — carried, not fixed; the release approval card rules it"
                DSP_STATED="$(deferral_sentence "$PV_PLAN" "$DSP_FID" 2>/dev/null)" || DSP_STATED=""
                if [ -n "$DSP_STATED" ]; then DSP_DEC="none: stated"
                else DSP_DEC="its changelog sentence: finding-stated $DSP_FID '<sentence>'"; fi ;;
              *) DSP_STATE=accepted; DSP_DEC="none" ;;
            esac ;;
        esac
        DSP_LINE="finding $DSP_FID $DSP_S user-facing=$DSP_R record=$DSP_EV at=$DSP_W row=${DSP_ROWS:-—} state=$DSP_STATE decision=\"$DSP_DEC\""
        if [ "$DSP_STATE" = deferred ]; then
          if [ -n "$DSP_STATED" ]; then DSP_LINE="$DSP_LINE stated=\"$DSP_STATED\""; else DSP_LINE="$DSP_LINE stated=-"; fi
        fi
        say "$DSP_LINE title=\"$DSP_T\""
      done <<DSP_FINDINGS
$DSP_GOT
DSP_FINDINGS
      if [ "$DSP_DEBT" = 1 ]; then
        ( cd "$PV_REPO" && "${BASH:-bash}" "$HOOK_DIR/session-poker.sh" debt add "$DSP_EV" "$PV_PLAN" 2>&1 ) || :
      fi
    done <<DSP_READINGS
$DSP_READS
DSP_READINGS
    say "disposition — $DSP_NF findings in $DSP_NR registered reviews; $DSP_NP need the person's ruling (disposition <record>#<n> fix|defer '<their words>' '<why>' ['<changelog sentence>'])."
    exit 0
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
    if ! { declare -F proof_line >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_add_line >/dev/null 2>&1; then
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
      if ! proof_add_line "$PV_PLAN" "$(proof_line check "$RC_HEAD" "$(iso_now)" "$RC_REL") result=fail" > "$PV_NEW" 2>/dev/null || [ ! -s "$PV_NEW" ]; then
        die "REFUSED — the declared release-check ($(clean "$RC_CMD")) exited $RC_RC over ${RC_BASE:0:12}..${RC_HEAD:0:12} ($RC_FROM), and $PV_PLAN carries no ## SDLC State section to hold its failing fact; its log is $RC_LOG.$RC_SAID"
        exit 1
      fi
      plan_verb_swap release-check "the failing check at $RC_HEAD" writer
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
    if ! proof_add_line "$PV_PLAN" "$(proof_line check "$RC_AT" "$(iso_now)" "$RC_REL")" > "$PV_NEW" 2>/dev/null || [ ! -s "$PV_NEW" ]; then
      die "REFUSED — $PV_PLAN carries no ## SDLC State section to hold the check proof; the plan is unchanged."
      exit 1
    fi
    plan_verb_swap release-check "the check proof at $RC_AT" writer
    say "release-check — kind=check head=$RC_AT base=$RC_BASE ($RC_FROM) evidence=$RC_REL: written to $PV_PLAN; dry-committed first.$RC_SAID"
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
  # THE ONE PATH A RUNNER IS GIVEN THE WHOLE RUN BY, asked before anything runs: `regression: no` refuses it
  # (`plan_regression`); a row the regression waits on that still writes the head refuses it (`units_floor_holds`); a
  # covered head refuses it (`proof_state`); and a head that already has a whole-run log refuses it. The bash wall's
  # full-tree refusal names this verb as the whole run's path (lib/walls.sh).
  poker_verb_regression_run() {
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
      # RULE 3. A proved head owes no run.
      FR_STATE="$(proof_state "$PV_PLAN" "$PV_REPO" 2>/dev/null)"
      case "$FR_STATE" in
        covered*)
          die "REFUSED — the working head ${FR_HEAD:0:12} is already proved: the plan's regression covers it ($(clean "$(proof_last_line "$PV_PLAN" regression)")); a change landed after it is proved by the suites its row names. Nothing was run."
          exit 1 ;;
      esac
      # ONE WHOLE RUN AT A HEAD. A log of tests/run.sh at this head refuses another: a red is a fix row's, its own
      # suites plus the red one, and no second whole run is asked.
      for _fr_l in "$FR_DOCS/record/$FR_WAVE/regression-run-$FR_HEAD"*.log; do
        [ -f "$_fr_l" ] && [ "$(sed -n 2p "$_fr_l" 2>/dev/null)" = "command: tests/run.sh" ] || continue
        die "REFUSED — the whole run runs once at a head, and ${FR_HEAD:0:12} has it: ${_fr_l#"$FR_DOCS"/}. A red suite is a fix row's: its own suites plus the red one, green at a later head. Nothing was run."
        exit 1
      done
    fi
    # THE WHOLE RUN COMES ONCE, AND A HEAD PAST IT IS A FIX ROW'S TO PROVE. Whatever the regression is (tests/run.sh or
    # the declared command), a record that already holds a whole run at a commit behind the working head refuses another
    # before anything runs: a red suite is closed by the landing of the fix row that runs it, never by a second
    # run, so a second run would only move the head the plan proves. A run at this very head is not behind it, and a
    # run on a history that does not hold this head proves nothing here.
    if FR_PAST="$(proof_whole_run_behind "$PV_PLAN" "$PV_REPO" "$FR_CO" "$FR_HEAD")"; then
      die "REFUSED — the whole run runs once, and ${FR_PAST:0:12} has it (${FR_PAST#*$'\t'}): a red suite is a fix row's, and a fix row's landing proves the head ${FR_HEAD:0:12}. Nothing was run."
      exit 1
    fi
    FR_DIRT="$(_wt_piece_dirt "$FR_CO")"
    FR_DIRTY="$(printf '%s' "$FR_DIRT" | awk 'END { print NR + 0 }')"
    # A DIRTY TREE IS REFUSED BEFORE THE RUN, NOT LOGGED AFTER IT (wave-35 T32; D20, A-orch-32). The log of a dirty
    # whole run counted as the first whole run (rule 4) while proof-add floor refuses it, so the re-run its own message
    # asked for was refused as a second whole run and the one allowed run was spent on nothing. The after-the-run
    # comparison below stays: it guards a run that dirtied a clean tree.
    if [ -n "$FR_WHOLE" ] && [ "$FR_DIRTY" -ne 0 ]; then
      FR_PATHS="$(printf '%s\n' "$FR_DIRT" | sed -n '1,5p' | awk '{ printf "%s%s", (NR > 1 ? ", " : ""), $0 }')"
      FR_MORE=""; [ "$FR_DIRTY" -le 5 ] || FR_MORE=", and $((FR_DIRTY - 5)) more"
      die "REFUSED — the working checkout $(cd "$FR_CO" 2>/dev/null && pwd -P) is dirty (dirty=$FR_DIRTY): $(clean "$FR_PATHS")$FR_MORE. The whole run proves a committed head, and a log of a dirty tree is refused by proof-add regression yet would be the head's one whole run; nothing was run and no log was written; commit or stash it and run regression-run again."
      exit 1
    fi
    FR_TMP="$(mktemp "${TMPDIR:-/tmp}/bionic-regression-run.XXXXXX")" || {
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
    # landing record (lib/line.sh `line_event`, through `_wt_proofs_put`), the log by its record path, the head and
    # dirty count read before the run, its exit, and the log's sha256 (lib/proof.sh `_proof_sha256`), so `proof-add
    # floor` accepts this log, and this log as it is now, and no hand-written one.
    FR_SHA="$(_proof_sha256 "$FR_LOG")" || FR_SHA=""
    declare -F line_event >/dev/null 2>&1 || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1
    if [ -z "$FR_SHA" ] || ! declare -F line_event >/dev/null 2>&1 \
       || ! line_event "$PV_PLAN" run "log=$FR_REL" "head=$FR_HEAD" "dirty=$FR_DIRTY" "rc=$FR_RC" "sha256=$FR_SHA" 2>/dev/null; then
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
  # above the verbs. The plan is the one named, resolved as fill-report resolves its operand (a path
  # from the project root, else from the docs root), or else this session's bound run; the record is
  # that plan's landing record, under the plan's own project. It writes nothing and exits 0 whatever
  # the record holds.
  # THE DEBT LEDGER (wave-30 T22; D2, P2, AC-11.2, AC-11.3). `record/<run>/debt.md` (lib/proof.sh
  # `proof_debt_ledger_path`, whose comment holds the line's shape) has this verb as its one writer, under
  # a lock beside the file (`launch_sync_lock`, the plan writer's own). `add` reads a record's `debt:`
  # lines, a reading's or any other's (`proof_record_debts`, the registering verb's debt arm; wave-36
  # T13), holds each to the one grammar (lib/debt.sh `debt_line_ok`), and writes a line per concept
  # and kind it does not hold yet; `touched` adds one to the touches of every unburned item of the
  # concept (the dispatch wall's advisory calls it); `burn` writes `burned <row>` in their last cell; `adopt`
  # reads the `debt:` lines close-out carried under `## Deferrals` of a continuation (AC-11.2's read-back,
  # wave-30 T32) and writes each as an item with its touches and raised-by kept, none burned.
  # Exit 0 done; 1 refused, the ledger unchanged; 2 the run or the record cannot be found; 75 another
  # writer held the lock for the whole wait.
  poker_verb_debt() {
    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    DEBT_PLAN=""
    if [ -n "$DEBT_PLAN_ARG" ]; then
      case "$DEBT_PLAN_ARG" in
        /*) DEBT_PLAN="$DEBT_PLAN_ARG" ;;
        *)  DEBT_PLAN="$REPO_REAL/$DEBT_PLAN_ARG"
            [ -f "$DEBT_PLAN" ] || DEBT_PLAN="$(docs_root "$REPO_REAL")/$DEBT_PLAN_ARG" ;;
      esac
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
    DEBT_FILE="$(proof_debt_ledger_path "$DEBT_ROOT" "$DEBT_PLAN")"
    DEBT_REL="${DEBT_FILE#"$DEBT_DOCS"/}"
    if [ "$DEBT_SUB" = list ]; then
      if [ ! -f "$DEBT_FILE" ]; then
        say "debt list — no ledger yet at $DEBT_REL"
        exit 0
      fi
      awk '!/^#/ && NF' "$DEBT_FILE"
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
      mkdir -p "${DEBT_FILE%/*}" 2>/dev/null
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
      mkdir -p "${DEBT_FILE%/*}" 2>/dev/null
    fi
    if [ ! -d "${DEBT_FILE%/*}" ] || { [ "$DEBT_SUB" != add ] && [ "$DEBT_SUB" != adopt ] && [ ! -f "$DEBT_FILE" ]; }; then
      die "REFUSED — no debt ledger at $DEBT_REL; debt add writes it from a review's debt: lines."
      exit 1
    fi
    launch_sync_lock "$DEBT_FILE.lock" yes; DEBT_LRC=$?
    if [ "$DEBT_LRC" != 0 ]; then
      die "WAITING — another writer held the debt ledger's lock ($DEBT_FILE.lock) for the whole wait; run the same command again."
      exit 75
    fi
    trap 'launch_sync_unlock; rm -f "$DEBT_FILE.new.$$"' EXIT
    DEBT_NEW="$DEBT_FILE.new.$$"
    case "$DEBT_SUB" in
      add)
        DEBT_SAID="$(PROOF_HAVE="$(proof_debt_items "$DEBT_FILE")" DEBT_RECREL="$DEBT_RECREL" DEBT_HEAD="$PROOF_DEBT_HEADER" awk -F'\t' -v out="$DEBT_NEW" '
          BEGIN { n = split(ENVIRON["PROOF_HAVE"], h, "\n"); for (i = 1; i <= n; i++) { split(h[i], c, "\t"); have[c[1] "\t" c[2]] = 1 } }
          { k = $3 "\t" $2
            if (k in have) { there++; print $3 " " $2 " already in the ledger"; next }
            have[k] = 1; added++
            line[added] = $3 " | " $2 " | " $4 " | raised-by " ENVIRON["DEBT_RECREL"] " | touches 0 | —"
            print $3 " " $2 " " $4 }
          END { for (i = 1; i <= added; i++) print line[i] > out; printf "%d added, %d already there", added, there }' <<< "$DEBT_ROWS")"
        if [ -f "$DEBT_FILE" ]; then cat "$DEBT_FILE"; else printf '%s\n' "$PROOF_DEBT_HEADER"; fi > "$DEBT_NEW.all" 2>/dev/null \
          && { [ ! -f "$DEBT_NEW" ] || cat "$DEBT_NEW" >> "$DEBT_NEW.all"; } && mv "$DEBT_NEW.all" "$DEBT_FILE" 2>/dev/null \
          || { rm -f "$DEBT_NEW.all"; die "REFUSED — the debt ledger at $DEBT_REL cannot be written."; exit 1; }
        printf '%s\n' "$DEBT_SAID" | while IFS= read -r _dl; do
          case "$_dl" in *' added, '*' already there') say "debt add — $_dl: $DEBT_REL" ;; *) say "debt add — $_dl" ;; esac
        done
        exit 0
        ;;
      adopt)
        # Rows are `debt <kind> <concept> <sites> <touches> <raised-by>`. The ledger keeps what it holds:
        # an item on concept and kind is there already and is not rewritten (A-T22.5), its touches its own.
        DEBT_SAID="$(PROOF_HAVE="$(proof_debt_items "$DEBT_FILE")" awk -F'\t' -v out="$DEBT_NEW" '
          BEGIN { n = split(ENVIRON["PROOF_HAVE"], h, "\n"); for (i = 1; i <= n; i++) { split(h[i], c, "\t"); have[c[1] "\t" c[2]] = 1 } }
          { k = $3 "\t" $2
            if (k in have) { there++; next }
            have[k] = 1; added++
            line[added] = $3 " | " $2 " | " $4 " | raised-by " $6 " | touches " $5 " | —" }
          END { for (i = 1; i <= added; i++) print line[i] > out; printf "%d adopted, %d already there", added, there }' <<< "$DEBT_ROWS")"
        if [ -f "$DEBT_FILE" ]; then cat "$DEBT_FILE"; else printf '%s\n' "$PROOF_DEBT_HEADER"; fi > "$DEBT_NEW.all" 2>/dev/null \
          && { [ ! -f "$DEBT_NEW" ] || cat "$DEBT_NEW" >> "$DEBT_NEW.all"; } && mv "$DEBT_NEW.all" "$DEBT_FILE" 2>/dev/null \
          || { rm -f "$DEBT_NEW.all"; die "REFUSED — the debt ledger at $DEBT_REL cannot be written."; exit 1; }
        say "debt adopt — $DEBT_SAID: $DEBT_REL"
        exit 0
        ;;
      touched|burn)
        DEBT_SAID="$(awk -v c="$DEBT_A" -v r="$DEBT_B" -v sub_="$DEBT_SUB" -v out="$DEBT_NEW" '
          { l = $0 }
          !/^#/ && NF && split($0, f, / \| /) == 6 && f[1] == c && index(f[6], "burned ") != 1 && f[5] ~ /^touches [0-9]+$/ {
            if (sub_ == "touched") { f[5] = "touches " (substr(f[5], 9) + 1); said = f[1] " " f[2] " " f[5] }
            else { f[6] = "burned " r; said = f[1] " " f[2] " burned " r }
            l = f[1]; for (i = 2; i <= 6; i++) l = l " | " f[i]
            print said
          }
          { print l > out }' "$DEBT_FILE")"
        if [ -z "$DEBT_SAID" ]; then
          die "REFUSED — no unburned item of the debt ledger at $DEBT_REL names $DEBT_A; debt list prints what it holds."
          exit 1
        fi
        mv "$DEBT_NEW" "$DEBT_FILE" 2>/dev/null \
          || { die "REFUSED — the debt ledger at $DEBT_REL cannot be written."; exit 1; }
        printf '%s\n' "$DEBT_SAID" | while IFS= read -r _dl; do say "debt $DEBT_SUB — $_dl"; done
        exit 0
        ;;
    esac
  }
