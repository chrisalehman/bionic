#!/bin/bash
# tests/brief-file.test.sh — `session-poker.sh brief <row> [<name>]`: the dispatch brief rendered whole.
#
# The brief is one file per dispatch, record/<wave>/briefs/<name>.md, rendered from the row, the task's own
# section of the plan (a heading whose first word is the row id) and the reader's answers. Nothing in it is
# typed into the brief: the judgment is the section's, the review range, the Questions and Lands-red are the
# reader's, and every verb the file names is one the verb listing holds.
#
#   §RENDER  a review brief's range starts at the last proof's head; the Questions and Lands-red are rendered;
#            a row's section is its judgment, and a row with none is marked absent in words; every verb the
#            file names is listed; a section naming no verb, or typing a contract label, is refused with
#            nothing written; a brief this verb did not render is never rewritten.
#   §NAMES   the dispatch wall: a dispatch that binds a plan row names its row's rendered brief file on the
#            prompt's first line, or is refused with the render to run; the file's path and sum go on the
#            roster row; a read-only dispatch that binds no row needs no file.
#   §PROSE   with one brief file, prose in the prompt naming other suites changes neither the verdict nor
#            the roster contract.
#   §SUM     a file edited after its render, or marked before sums existed, is refused; a roster row that
#            carries no brief path or sum is not refused by amend or hold.
#   §LIFT    the library carries one reader and no lift; a row dispatch's roster contract is its brief file's
#            as that reader reads it, and a label typed only in the prompt's prose changes nothing; amend,
#            hold and extend keep the row's brief path and sum.
#
# FIXTURE FIDELITY. The session-poker prelude's sandbox (an engaged, bound session in a scratch repository),
# a version-14 Tasks table, real commits on the working branch for the proof heads, and a planted run log the
# reader reads alone. SYNTHESIZED: the sections and the log lines. §NAMES to §SUM drive the real dispatch wall
# on a real-shaped Agent payload in an approved, bound and armed session; the attestation and the Patrol
# stamp are written in their writers' shapes, and each drive starts on an empty roster.
#
# ANTI-VACUITY. Every absence sits beside a positive read through the same extractor on the same file.

set -uo pipefail
. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"
POKER="${BIONIC_HOOKS_DIR}/session-poker.sh"
S46_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/proof.sh"
. "$(dirname "$0")/session-poker.prelude.sh"

section "§RENDER: the brief is the row, its section and the reader's answers, and nothing typed"
BR="$(make_repo brief-render)"; git -C "$BR" config user.name "Dana Fixture"; git -C "$BR" config user.email d@example.com
cm() { git -C "$BR" commit -q --allow-empty -m "$1" && git -C "$BR" rev-parse HEAD; }
( cd "$BR" && git checkout -q -b wave/01-fixture )
O="$(cm old)"; A="$(cm a)"; B="$(cm b)"; C="$(cm c)"; HD="$(cm head)"
REC="$BR/.bionic/docs/record/wave-01-fixture"; BD="$REC/briefs"; mkdir -p "$BD"
BP="$BR/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"; mkdir -p "${BP%/*}"
{ printf -- '---\nrigor: double\nscale: wave\nworking-branch: wave/01-fixture\nbase-sha: %s\n---\n\n# fixture\n\n' "${O:0:9}"
  printf '## SDLC State\n\ncurrent: 4\n\n## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | status | reads |\n|---|---|---|---|---|---|---|---|---|---|---|\n'
  printf '| T1 | 4 | build | the build with a section | — | — | 30 | REQ-1 | lib/a.sh, tests/a.test.sh | pending | — |\n'
  printf '| T2 | 4 | build | the build with none | — | — | 30 | REQ-1 | lib/b.sh, tests/b.test.sh | pending | — |\n'
  printf '| T3 | 4 | build | a section naming no verb | — | — | 30 | REQ-1 | lib/c.sh, tests/c.test.sh | pending | — |\n'
  printf '| T4 | 4 | build | a section typing a contract | — | — | 30 | REQ-1 | lib/d.sh, tests/d.test.sh | pending | — |\n'
  printf '| R1 | 6 | review | the critic reads it · questions: adversarial,structure | — | — | 30 | REQ-1 | record/wave-01-fixture/critic-adversarial.md, record/wave-01-fixture/critic-structure.md | pending | — |\n\n'
  printf '## T1 — the build with a section\n\nResearch to read: record/wave-01-fixture/research.md\nRulings: render again with bash /x/hooks/session-poker.sh brief T1 once this section changes.\n\nsuites: a.test.sh, shared.test.sh\n\n'
  printf '## T3 — naming no verb\n\nRun bash /x/hooks/session-poker.sh floor-run first.\n\n'
  printf '## T4 — typing a contract\n\nRe-executes: `cd /tmp/x && bash tests/d.test.sh`\n'
} > "$BP"
bind_marker "$BR" "$BP"
t=2026-11-01T00:00
cat > "$REC/run.log" <<EOF
run/v1|ev=proof|kind=review|head=$O|question=adversarial|result=pass|scope=piece|at=${t}:01Z
run/v1|ev=proof|kind=review|head=$A|question=adversarial|result=flag|scope=piece|at=${t}:02Z
run/v1|ev=proof|kind=review|head=$A|question=structure|result=pass|scope=piece|at=${t}:03Z
run/v1|ev=proof|kind=review|head=$B|question=evidence|result=pass|scope=piece|at=${t}:04Z
run/v1|ev=proof|kind=regression|head=$C|rc=0|at=${t}:05Z
run/v1|ev=admitted|id=d1|row=T1|suite=a.test.sh|token=ext:ci|at=${t}:06Z
EOF
printf '# typed by hand before the brief was rendered\n' > "$BD/T2.md"; cp "$BD/T2.md" "$TMPROOT/T2.before"

poke "$BR" brief R1 w01-R1
expect_eq "R0 the review brief is written under its dispatch name (exit 0)" "0" "$RC"
expect_eq "R1 AC-6.3 its range starts at the last proof's head of its questions and ends at the working head" \
  "Reviewed range: $A..$HD" "$(grep '^Reviewed range:' "$BD/w01-R1.md")"
expect_eq "R2 its Questions are the row's, rendered" "Questions: adversarial, structure" "$(grep '^Questions:' "$BD/w01-R1.md")"

poke "$BR" brief T1 w01-T1
expect_eq "R3 a build row with a section of its own renders (exit 0)" "0" "$RC"
judg() { awk '/^## Judgment/ { f = 1; next } f' "$BD/$1.md"; }
expect_contains "R3b …the section's words are its judgment" "Research to read: record/wave-01-fixture/research.md" "$(judg w01-T1)"
expect_absent "R3c …and its suites line is no judgment line" "suites:" "$(judg w01-T1)"
expect_eq "R3d …it is the contract's Suites, read from the section" "Suites: a.test.sh, shared.test.sh" "$(grep '^Suites:' "$BD/w01-T1.md")"
expect_eq "R4 the row's admitted red is its Lands-red, with the evidence the writer writes" \
  "Lands-red: a.test.sh until ext:ci|Red-evidence: .bionic/docs/record/wave-01-fixture/w01-T1-red.md" \
  "$(grep '^Lands-red:\|^Red-evidence:' "$BD/w01-T1.md" | tr '\n' '|' | sed 's/|$//')"
expect_absent "R4b …and a row with none has no Lands-red line (beside R4's, the same reader)" "Lands-red:" "$(cat "$BD/w01-R1.md")"

poke "$BR" brief T2
expect_eq "R5 a brief this verb did not render is not rewritten (exit 1)" "1" "$RC"
expect_true "R5b …it is byte for byte as it was" cmp -s "$TMPROOT/T2.before" "$BD/T2.md"
poke "$BR" brief T2 w01-T2
expect_eq "R6 a row with no section renders under its dispatch name (exit 0)" "0" "$RC"
expect_contains "R6b …its judgment marked absent, in words" "NO JUDGMENT: the plan has no section for T2" "$(judg w01-T2)"
expect_contains "R6c …beside the way to give it one" "brief T2 w01-T2" "$(judg w01-T2)"
poke "$BR" brief T2 w01-T2
expect_eq "R6d a second render of a row not yet dispatched replaces its own file (exit 0)" "0" "$RC"

VL="$(bash "$POKER" 2>&1 | sed -n 's/.*session-poker\.sh \([a-z][a-z-]*\).*/\1/p' | sort -u)"
NAMED="$(cat "$BD/w01-T1.md" "$BD/w01-T2.md" "$BD/w01-R1.md" | grep -o 'session-poker\.sh [a-z][a-z-]*' | sed 's/^session-poker\.sh //' | sort -u)"
expect_contains "R7 setup: the verb listing is read" "brief" "$VL"
expect_contains "R7b setup: the rendered briefs name a verb" "brief" "$NAMED"
expect_eq "R7c AC-6.3 every verb a rendered brief names is in the verb listing" "" "$(comm -23 <(printf '%s\n' "$NAMED") <(printf '%s\n' "$VL"))"

poke "$BR" brief T3 w01-T3
expect_eq "R8 a section naming a verb the listing lacks is refused (exit 1)" "1" "$RC"
expect_contains "R8b …the refusal names it" "floor-run" "$OUT"
expect_false "R8c …and nothing is written" test -e "$BD/w01-T3.md"
poke "$BR" brief T4 w01-T4
expect_eq "R9 a section typing a contract label is refused: the contract is rendered (exit 1)" "1" "$RC"
expect_contains "R9b …the refusal names the label" "Re-executes:" "$OUT"
expect_false "R9c …and nothing is written" test -e "$BD/w01-T4.md"
poke "$BR" brief T1 w01-T2
expect_eq "R10 a name another row's dispatch carries is refused (exit 1)" "1" "$RC"
expect_true "R10b …and the row's own file stands" test -s "$BD/w01-T1.md"

section "§NAMES: a dispatch that binds a plan row names its row's rendered brief file (AC-6.1)"
# The real dispatch wall over a bound, approved, armed session; each drive starts on an empty roster.
NR="$(make_repo wall-names)"; git -C "$NR" config user.name "Dana Fixture"; git -C "$NR" config user.email d@example.com
( cd "$NR" && git checkout -q -b wave/01-fixture && git commit -q --allow-empty -m base )
mkdir -p "$NR/tests" "$NR/lib"; printf '#!/bin/bash\n' > "$NR/tests/n.test.sh"
NREC="$NR/.bionic/docs/record/wave-01-fixture"; NBD="$NREC/briefs"; mkdir -p "$NBD"
NP="$NR/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"; mkdir -p "${NP%/*}"
{ printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nrigor: double\nscale: wave\nworking-branch: wave/01-fixture\n---\n\n# fixture\n\n'
  printf '## SDLC State\n\ncurrent: 4\napproved-by: fixture 2026-10-04T00:00Z "approved"\n\n## Tasks\n\n'
  printf '| id | step | kind | task | agent | deps | size | serves | Files | status | reads |\n|---|---|---|---|---|---|---|---|---|---|---|\n'
  printf '| N1 | 4 | build | the wall reads its brief | — | — | 30 | REQ-6 | lib/n.sh, tests/n.test.sh, record/wave-01-fixture/N1.md | pending | — |\n\n'
  printf '## N1 — the wall reads its brief\n\nRulings: the file is the contract.\n'
} > "$NP"
bind_marker "$NR" "$NP"
printf 'version=1\nkind=preflight-attestation\nsession_id=%s\nwritten_at=1785790000\nrepo=%s\n' "$SID" "$NR" > "$NR/.bionic/tmp/preflight-$SID.state"
printf 'patrol-stamp/v1|at=%s|session=%s|verb=arm\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SID" > "$(stamp_of "$NR")"
chmod 600 "$NR/.bionic/tmp/preflight-$SID.state" "$(stamp_of "$NR")"
: > "$TMPROOT/wall.jsonl"
WALL="${BIONIC_HOOKS_DIR}/dispatch-preflight.sh"
wall() {  # <name> <subagent type> <prompt> -> WV (allow|deny), WR (the deny reason), WROW (the roster row, its clock off)
  local p; rm -f "$(roster_of "$NR")"
  p="$(jq -n --arg s "$SID" --arg c "$NR" --arg t "$TMPROOT/wall.jsonl" --arg n "$1" --arg y "$2" --arg pr "$3" \
    '{session_id:$s, transcript_path:$t, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Agent", tool_use_id:"toolu_wall",
      tool_input:{description:"a dispatch", subagent_type:$y, prompt:$pr, name:$n, run_in_background:true}}')"
  WOUT="$(printf '%s' "$p" | ( cd "$NR" && env CLAUDE_CODE_SESSION_ID="$SID" bash "$WALL" 2>"$TMPROOT/wall.err" ))"; WST=$?
  WR="$(printf '%s' "$WOUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)"
  if [ -n "$WR" ]; then WV=deny; elif [ "$WST" -eq 0 ]; then WV=allow; else WV="exit$WST"; WR="$(cat "$TMPROOT/wall.err")"; fi
  WROW="$(grep -v '^#' "$(roster_of "$NR")" 2>/dev/null | tail -1 | tr '|' '\n' | grep -v '^launched_at=' | tr '\n' '|')"
}
said_as() {  # <the verdict a row expects> -> it, or the verdict given with the wall's own words
  if [ "$WV" = "$1" ]; then printf '%s' "$1"; else printf '%s — %s' "$WV" "$WR"; fi
}
poke "$NR" brief N1 w01-N1
NB=".bionic/docs/record/wave-01-fixture/briefs/w01-N1.md"
expect_eq "N0 setup: the row's brief renders (exit 0)" "0" "$RC"
wall w01-N1 bionic:implementor "$NB
Read the file whole before your first act."
expect_eq "N1 a row dispatch whose prompt names its rendered brief file is admitted" "allow" "$(said_as allow)"
expect_contains "N1b …and the roster row carries the brief's path" "|brief=$NB|" "|$WROW"
expect_regex "N1c …and its sum" '\|brief_sum=[0-9a-f]{64}\|' "|$WROW"
NCONTRACT="$WROW"
wall w01-N1 bionic:implementor "$(tail -n +2 "$NR/$NB")"
expect_eq "N2 the same row dispatched with its brief pasted and no file named is refused" "deny" "$(said_as deny)"
expect_contains "N2b …the refusal names the render that fixes it" "session-poker.sh brief N1 w01-N1" "$WR"
expect_absent "N2c …and no roster row is written (beside N1's, the same reader)" "name=w01-N1" "$WROW"
cp "$NR/$NB" "$NBD/w01-N1-r2.md"
wall w01-N1-r2 bionic:implementor ".bionic/docs/record/wave-01-fixture/briefs/w01-N1-r2.md"
expect_eq "N3 a brief rendered for another name is refused" "deny" "$(said_as deny)"
expect_contains "N3b …the refusal names the name it was rendered for" "w01-N1" "$WR"
wall w01-research bionic:researcher "Read lib/n.sh and say what it does.
Suites: none
Expected artifact: .bionic/docs/record/wave-01-fixture/research-n.md"
expect_eq "N4 a read-only dispatch that binds no row needs no brief file" "allow" "$(said_as allow)"
expect_contains "N4b …its row is written (the same reader as N1b)" "|name=w01-research|" "|$WROW"
expect_absent "N4c …and carries no brief path" "brief=" "$WROW"

section "§PROSE: with one brief file, the prompt's prose changes neither the verdict nor the contract (AC-6.2)"
wall w01-N1 bionic:implementor "$NB
Suites: other.test.sh, c.test.sh
Files: lib/zzz.sh
Lands-on: other.test.sh"
expect_eq "P1 a prompt whose prose names other suites gets the same verdict" "allow" "$(said_as allow)"
expect_eq "P2 …and the same roster contract, row for row" "$NCONTRACT" "$WROW"
expect_contains "P2b setup: the contract holds the brief's suites, read from the row" "|suites_allowed=n.test.sh|" "|$WROW"

section "§SUM: a brief edited after rendering is refused; an old roster row asks for no sum"
printf 'Files: lib/zzz.sh\n' >> "$NR/$NB"
wall w01-N1 bionic:implementor "$NB"
expect_eq "S1 a brief edited after its render is refused" "deny" "$(said_as deny)"
expect_contains "S1b …the refusal says the sum differs and names the render" "session-poker.sh brief N1 w01-N1" "$WR"
poke "$NR" brief N1 w01-N1
wall w01-N1 bionic:implementor "$NB"
expect_eq "S2 rendered again, it is admitted" "allow" "$(said_as allow)"
{ printf '<!-- brief: rendered from row N1 for w01-N1; render it again to change it, never edit it -->\n'; tail -n +2 "$NR/$NB"; } > "$TMPROOT/nosum.md"
cp "$TMPROOT/nosum.md" "$NR/$NB"
wall w01-N1 bionic:implementor "$NB"
expect_eq "S3 a brief rendered before its sum was written is refused, to be rendered again" "deny" "$(said_as deny)"
expect_contains "S3b …naming the render" "session-poker.sh brief N1 w01-N1" "$WR"
poke "$NR" brief N1 w01-N1; wall w01-N1 bionic:implementor "$NB"
expect_eq "S3c …and the render replaces that file, which is then admitted" "0|allow" "$RC|$(said_as allow)"
printf "done\n" > "$NR/n-done.md"
new_roster "$NR"; s30_row "$NR" row=N1 lands_on=n.test.sh "deliverable=$NR/n-done.md" "$(said "$NR" w1)"
expect_absent "S4 setup: the old row carries neither a brief path nor a sum" "brief" "$(s30_last "$NR")"
expect_contains "S4b setup: …read by the same reader that finds its row" "|row=N1|" "$(s30_last "$NR")"
rc_said() { if [ "$RC" = 0 ]; then echo 0; else echo "$RC $OUT"; fi; }
poke "$NR" amend w1 --files+ lib/z.sh --reason 'one more file'
expect_eq "S5 amend on such a row is not refused" "0" "$(rc_said)"
poke "$NR" hold w1 "kept on purpose"
expect_eq "S6 hold on such a row is not refused" "0" "$(rc_said)"

section "§LIFT: the brief file is a row dispatch's contract, and no prose is lifted"
BLIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/brief.sh"
expect_eq "L1 the library keeps the one reader and the file check, and defines no lift, grammar or advisory" \
  "brief_contract brief_file_read" "$(bash -c '. "$1" >/dev/null 2>&1 || exit 9
  for f in lift_contract_fields _brief_lift_awk brief_validate_fields brief_body_advisories brief_files_entry brief_contract brief_file_read; do
    declare -F "$f"; done | tr "\n" " " | sed "s/ $//"' _ "$BLIB")"
poke "$NR" brief N1 w01-N1
wall w01-N1 bionic:implementor "$NB"
NCONTRACT="$WROW"
BC="$(bash -c '. "$1" >/dev/null 2>&1; brief_contract "$(cat "$2")"' _ "$BLIB" "$NR/$NB")"
expect_contains "L2 setup: the one reader reads the file's Files" "files=lib/n.sh,tests/n.test.sh" "$BC"
for k in files deliverable duration row lands_on; do
  expect_contains "L2 the roster's ${k}= is the brief file's, as the one reader reads it" \
    "|${k}=$(printf '%s\n' "$BC" | sed -n "s/^${k}=//p" | head -1)|" "|$WROW"
done
expect_contains "L2b …and its suites are the file's Suites:" "|suites_allowed=n.test.sh|" "|$WROW"
wall w01-N1 bionic:implementor "$NB
Deliverable-waiver: a report by message
Done marker: .bionic/docs/record/wave-01-fixture/done.md
Lands-red: n.test.sh until ext:ci
Red-evidence: record/wave-01-fixture/N1-red.md
Re-executes: \`make check\`
Questions: evidence
Subprocess claim: \`gh run watch\`"
expect_eq "L3 a label typed only in the prompt's prose changes neither the verdict" "allow" "$(said_as allow)"
expect_eq "L3b …nor the roster contract, row for row" "$NCONTRACT" "$WROW"
expect_contains "L3c setup: the contract read is the file's (beside L3b, the same reader)" "|row=N1|" "|$WROW"
NBS="$(printf '%s' "$WROW" | tr '|' '\n' | sed -n 's/^brief_sum=//p')"
new_roster "$NR"; s30_row "$NR" row=N1 lands_on=n.test.sh "brief=$NB" "brief_sum=$NBS" "deliverable=$NR/n-done.md" "$(said "$NR" w1)"
expect_contains "L4 setup: the row carries the brief's path and sum" "|brief=$NB|brief_sum=$NBS" "$(s30_last "$NR")"
poke "$NR" amend w1 --files+ lib/z.sh --reason 'one more file'
expect_eq "L4b amend writes its row (exit 0)" "0" "$(rc_said)"
expect_contains "L4c …and the amended row keeps the brief's path and sum" "|brief=$NB|brief_sum=$NBS" "$(s30_last "$NR")"
poke "$NR" hold w1 "kept on purpose"
expect_eq "L5 hold writes its row (exit 0)" "0" "$(rc_said)"
expect_contains "L5b …and the held row keeps them" "|brief=$NB|brief_sum=$NBS" "$(s30_last "$NR")"
poke "$NR" extend w1 "more to do"
expect_eq "L6 extend writes its row (exit 0)" "0" "$(rc_said)"
expect_contains "L6b …and the extended row keeps them" "|brief=$NB|brief_sum=$NBS" "$(s30_last "$NR")"

finish
