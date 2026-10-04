# Refusal inventory — wave-24-fixit-1811 (T13, D10, AC-6.6)

Every refusal site in `payload/scripts/lib/walls.sh`, `payload/scripts/lib/stop.sh`,
`hooks/dispatch-preflight.sh` and `hooks/stop-guard.sh`, with the fix line it prints or the
reason no line exists. `tests/refuse.test.sh` §INV reads each file's call sites (a
`fold_block`, `refuse`, `dp_finding`, `budget_deny` or `deny` call at the start of a statement)
and requires each site's first source line, trimmed, to appear here inside a bullet that carries
`— fix:` or `— none:`. A site whose first line is shared (three budget-arm `fold_block exit2
suite-run \` calls) appears once per occurrence. A `<root>` or `<hooks>` in a fix below is the
real plugin root or hooks directory in the printed line; the placeholders here only stand for it.


## payload/scripts/lib/walls.sh

- `fold_block exit2 push "main is a protected branch here" "push from your own terminal" \` — protect-main, push to main — none: the push belongs to the human at their own terminal; no line the agent could paste is the fix
- `fold_block exit2 push "this is a force push" "push from your own terminal" \` — protect-main, force push — none: the same, a force push is the human's own act
- `fold_block exit2 push "the current branch is protected" "switch to a feature branch" \` — protect-main, commit on a protected branch — none: the fix is a branch whose name is the reader's choice (`git switch -c <branch>` would print a placeholder)
- `fold_block exit2 sql "this command DROPs a database object" "run the migration yourself" \` — protect-database, DROP — none: a destructive migration is a human act on a database, and the wall exists so an agent does not run it
- `fold_block exit2 sql "this command TRUNCATEs a table" "run the migration yourself" \` — protect-database, TRUNCATE — none: a destructive migration is a human act on a database, and the wall exists so an agent does not run it
- `fold_block exit2 sql "this DELETE has no WHERE clause" "add a WHERE clause" \` — protect-database, DELETE without WHERE — none: a destructive migration is a human act on a database, and the wall exists so an agent does not run it
- `fold_block exit2 sql "this ALTER TABLE drops a column or key" "run the migration yourself" \` — protect-database, ALTER TABLE drop — none: a destructive migration is a human act on a database, and the wall exists so an agent does not run it
- `fold_block exit2 sql "this drops or wipes a MongoDB collection" "run it from your own terminal" \` — protect-database, MongoDB drop — none: a destructive migration is a human act on a database, and the wall exists so an agent does not run it
- `fold_block exit2 sql "destructive SQL is piped to a db client" "run the migration yourself" \` — protect-database, SQL piped to a db client — none: a destructive migration is a human act on a database, and the wall exists so an agent does not run it
- `fold_block "$(cat "$_eg_stage/1" 2>/dev/null)" "$(cat "$_eg_stage/2" 2>/dev/null)" \` — evidence gate, staged refusal forwarder — none: a forwarder; fact, fix and detail are the staged arm's own
- `fold_block exit2 commit "the evidence gate's own refusal is malformed" "run /bionic:doctor" \` — evidence gate, malformed own refusal — fix: `/bionic:doctor`
- `refuse exit2 commit "the bound plan cannot be read" "restore read access to the plan" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "a plan sits outside the docs root" "move the plan under docs root" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "this plan declares an unsupported sdlc version" "set the supported version" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "that task's evidence is prose" "record the command and counts" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "that task is done with no auditor verdict" "record the auditor's verdict" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "that task is done with no critic verdict" "record the critic's verdict" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "that task lowers rigor below the floor" "raise the rigor, or waive it" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "$1" "$2" "canonical-sdlc task-ledger: $3` — evidence gate, task-ledger forwarder — none: a forwarder; each caller's fix is a line of the task ledger the detail names
- `refuse exit2 commit "$verdict" "add one '- T<id>:' per row" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "$verdict" "write the roster name as agent" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "that task's rigor value is not valid" "use tested, peer-reviewed or audited" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "that task's evidence line is a placeholder" "replace it with real evidence" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "that task has no row in '## Tasks'" "add the task's registration row" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "'## SDLC State' is empty" "add current: and the step lines" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "'## SDLC State' has no 'approved-by:' line" "record the literal approval" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "that matrix row names no 'fails-when:'" "add a 'fails-when:' line" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "that row's task ships nothing" "point it at a shipping task" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "'## SDLC State' has no valid 'current:' line" "add a 'current: N' line" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "two directories are named before the commit" "name one directory" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "that worktree's task is ahead of the run" "advance the run first" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "the plan has no line for the current step" "add the step's evidence line" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "this step's evidence line is empty" "record the step's evidence" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "this step's evidence line is a placeholder" "replace it with real evidence" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "Step 1's evidence names no requirements file" "add a 'requirements:' field" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "the requirements path climbs out with '..'" "name it under the docs root" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "the named requirements file does not exist" "write the requirements file" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "this plan's body is not at contract version ${SUPPORTED_SDLC_VERSION}" "bring the plan forward" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "this step's evidence is missing fields" "add the fields the step owes" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "'pass:' and 'total:' are not both integers" "write both as integers" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "the suite is not fully green" "make pass equal total" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "this step names no adr, rca or n/a" "add adr:, rca: or n/a:" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "the close-out owes the deploy trio" "add deployed:, verified:, monitored:" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "$1" "$2" "canonical-sdlc step ${CURRENT} — $3` — evidence gate, step forwarder — none: a forwarder; each caller's fix is a line of the step's evidence the detail names
- `refuse exit2 commit "this wave plan has no '## Tasks' ledger" "add a '## Tasks' section" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "that dispatched task's row is invalid" "fix the row the detail names" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "the dispatched task's evidence is a placeholder" "replace it with evidence" "$_eg_detail"` — evidence gate — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "this step's evidence names no head" "add head: <sha the run read>" "$_eg_detail"` — evidence gate, proof head — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "the Step-5 head: is not a commit here" "record the sha the run read" "$_eg_detail"` — evidence gate, proof head — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `refuse exit2 commit "the release head does not contain head:" "re-run the floor on release head" "$_eg_detail"` — evidence gate, proof head — none: an evidence-gate commit refusal; the fix is a line of plan text the detail names, and no command can write the reader's evidence for them
- `fold_block deny run "this command belongs in a subagent" "$_fix" \` — farm-out, main-thread suite or build that is not short — none: the fix is the Bash call's own `timeout` parameter (at most `farm-out-short-ms:`) or an Agent tool call, and no shell line can stand in for either
- `fold_block exit2 commit "$_bsg_role: a read-only role never commits" "send your report" \` — read-only role commit — none: the fix is a SendMessage report, a tool call, not a command
- `fold_block exit2 "$_WALL_POKER_VERB" \` — subagent poker verb — none: the verb is the orchestrator's alone, so the fix is a message to it
- `fold_block exit2 suite-run "a backgrounded suite's result is never read" "run it in the foreground" \` — backgrounded suite — fix: the same command run in the foreground, printed from the refused text (`_bg_fix`)
- `fold_block exit2 suite-run \` — budget arm, unexpanded suite name — fix: the loop header's words as `bash tests/<w>.test.sh` lines, from `cmd_suite_loop_lines`; none when the text gives no literal list, or when a loop's body reassigns its variable so the header is not what runs (T26), and the detail says so
- `fold_block exit2 suite-run \` — budget arm, suite or run off the budget — fix: `bash <root>/hooks/session-poker.sh amend <name> --suites+ <suite> --reason '<why>'` (`_budget_remedy_line`)
- `fold_block exit2 suite-run \` — budget arm, the full tree — fix: `bash tests/<first budgeted suite>`
- `fold_block exit2 write "this writes the memory store" "use record/<wave>/assumptions.md" \` — memory wall — none: the fix is to write record/<wave>/assumptions.md or a rule proposal instead, content only the writer has

## payload/scripts/lib/stop.sh

- `undeclared) fold_block exit2 stop "this branch touched undeclared files" "declare them, or revert them" "$REFUSALS" ;;` — landing sweep, undeclared files — fix: `bash <root>/hooks/session-poker.sh amend '<name>' --files+ '<path>'… --reason '…'` per row (`LG_FIX`); revert is the other way out and has no single command
- `*)          fold_block exit2 stop "a dispatched agent's contract is unmet" "write the named artifacts" "$REFUSALS" ;;` — landing sweep, unmet contract — none: the fix is the named artifacts themselves, which only the agent can write
- `fold_block block stop "the bound plan cannot be read" "restore read access to the plan" \` — stop, bound plan unreadable — fix: `chmod u+r` on the plan, named in the detail
- `fold_block block stop "a cron was created with no CronList first" "list and delete stray jobs first" \` — stop, cron created without CronList — none: the fix is the CronList and CronDelete tool calls, not a shell command
- `fold_block block stop "no parallel-budget: key, and a STANDDOWN unanswered" \` — patrol duties, no budget key and a stand-down — none: the budget line is Step 0's measurement; the stand-down half prints `session-poker.sh hold NAME 'why it stays up'` with each stood-down name in NAME
- `fold_block block stop "a FILL and a STANDDOWN went unanswered" \` — patrol duties, fill and stand-down — fix: `bash <hooks>/session-poker.sh hold NAME 'why it stays up'`, one per stood-down name in NAME, for the stand-down half; the fill half is an Agent dispatch or a `fill-declined:` line, neither a command
- `fold_block block stop "$FILL_FACT" "$FILL_FIX" \` — patrol duties, fill alone — none: the fix is an Agent dispatch of the named rows or a `fill-declined:` line, neither a shell command
- `fold_block block stop "a STANDDOWN went unanswered" "stop each agent, or decline" \` — patrol duties, stand-down — fix: `bash <hooks>/session-poker.sh hold NAME 'why it stays up'`, one per stood-down name in NAME (STANDDOWN_REASON)
- `fold_block block stop "a launch is not recorded in the plan" "run the commands it prints" \` — patrol duties, a launch the plan lacks — fix: the task-set and ledger-add commands that `session-poker.sh launch-sync` prints (LAUNCH_REASON)
- `fold_block block stop "a Patrol marker turn ran no tick" "run the tick, then stop again" \` — patrol duties, marker turn ran no tick — fix: `bash <hooks>/session-poker.sh tick` (NOTICK_REASON)
- `fold_block block stop "$FACT" "$FIX" "$REASON"` — patrol duties, verdict forwarder — none: a forwarder; FACT/FIX/REASON come from the duty that was missed (a TaskList or ListAgents call, tool calls)
- `fold_block block stop "the Patrol fires but never ticks" "run the tick; replace the job" \` — patrol revive, fires but never ticks — fix: `bash <hooks>/session-poker.sh tick`, and the job replaced with `session-poker.sh prompt`'s text
- `fold_block block stop "the Patrol died mid-run and nothing said so" "re-arm it, the clock first" \` — patrol revive, Patrol died — fix: CronList, CronCreate, then `bash <hooks>/session-poker.sh arm` (or `disarm`)

## hooks/dispatch-preflight.sh

- `refuse exit2 dispatch "$fact" "$fix" "${reasons}` — preflight probe deny() forwarder — fix: `${PREFLIGHT_CMD}`, the probe command printed whole
- `dp_finding "the bound plan cannot be read" "restore read access to the plan" \` — bound plan unreadable — fix: `chmod u+r` on the plan, named in the detail
- `deny "this repo has no environment attestation" "run the preflight probe" \` — no environment attestation — fix: `${PREFLIGHT_CMD}`, via deny()
- `refuse exit2 dispatch "the environment check ran and did not pass" "fix what the probe named" \` — probe ran and failed — fix: `${PREFLIGHT_CMD}` once the named failure is fixed
- `dp_finding "$fact" "$fix" "${reasons}` — Patrol stamp forwarder — fix: `bash <hooks>/session-poker.sh arm` or the CronCreate steps, from the arm that called it
- `dp_finding "the Patrol fires but never ticks" "run the tick; replace the job" \` — Patrol fires but never ticks — fix: `bash ${POKER_SCRIPT} tick`, then the job replaced
- `dp_finding "the approval reader lib/fill.sh cannot be loaded" "reinstall the plugin" \` — plan approval unreadable (wave-26 T56, final review N2) — fix: `claude plugin install bionic@bionic`, named in the detail
- `dp_finding "the plan this writer builds is unapproved" "get the Step-3 plan approved" \` — unapproved plan — none: approval is the user's literal word, which no command supplies
- `dp_finding "this session is bound to no run" "bind it, or write its plan" \` — session bound to no run — none: the run to bind is the reader's choice among open runs; `session-poker.sh bind <plan>` needs that plan
- `dp_finding "row ${DP_AW_ID} waits for approval:${DP_AW_NAME}" \` — row reads an approval nobody gave — none: the approval is the user's reply, which no command supplies; once given, `session-poker.sh approve <name> '<reply>'` records it
- `dp_finding "a subagent may launch only read-only roles" "ask the orchestrator" \` — subagent dispatching a writer — none: only the orchestrator dispatches writers, so the fix is a message to it
- `dp_finding "this dispatch came from a worktree" "dispatch from the main checkout" \` — dispatch from a worktree — none: the fix is to dispatch from the main checkout, a change of where, not a command
- `dp_finding "$1" "land or stand down a row" \` — budget_deny forwarder — fix: `bash ${HOOK_DIR}/stop-orders.sh standdown`, rooted at the real hooks directory
- `[ $(( BUDGET_OPEN + BUDGET_ASK )) -gt "$B_WRITERS" ] && budget_deny \` — writer budget — fix: each counted open row with `bash <hooks>/session-sweeper.sh ack '<name>'` (`budget_writer_rows`)
- `[ $(( BUDGET_LIVE + BUDGET_TREE_ASK )) -gt "$B_TREES" ] && budget_deny \` — worktree budget — fix: `bash ${HOOK_DIR}/stop-orders.sh standdown`, through budget_deny
- `dp_finding "that name is in flight" "use the FILL line's name" \` — name in flight — none: the fix is the name the tick's FILL line printed, which only that tick output carries
- `refuse deny dispatch "$DP_FIRST_FACT" "$DP_FIRST_FIX" "$DP_FIRST_DETAIL"` — single-finding refusal — none: a forwarder; the fix is the one finding's own
- `refuse deny dispatch "$DP_FIRST_FACT" "$DP_FIRST_FIX" \` — several-finding refusal — none: a forwarder; one line per fault, and the marked scaffold only when a line is missing
- `dp_finding "the deliverable label names several paths" "name exactly one deliverable" "$_dp_detail"` — deliverable names several paths — none: which path is the deliverable is the author's choice
- `dp_finding "the deliverable is outside this repository" "name a path inside the repo" "$_dp_detail"` — deliverable outside the repo — none: the in-repo path is the author's choice
- `dp_finding "this brief names no deliverable" "add an Expected artifact: line" "$_dp_detail"` — no deliverable — none: the artifact path is the author's choice
- `finding) dp_finding "$2" "$3" "$4" ;;` — brief.sh sink forwarder — none: a forwarder; brief.sh findings carry their own fix (the impact timeout names Suites:/Files:)
- `dp_finding "head ${_fr_short} is already proved" "keep the floor proof; run nothing" "$_dp_detail" ;;` — full run on the proved head — none: the head is proved and there is nothing to run; the detail names the proof line and its evidence
- `dp_finding "bounded: ${_fr_names}" "run those suites, not the tree" "$_dp_detail" ;;` — full run over a bounded change — fix: `Suites: tests/<suite> …`, printed whole in the detail, every suite the map named
- `dp_finding "rows write tracked files: ${_fr_ids}" "land them, then dispatch it" "$_dp_detail"` — full run while rows write the head — none: the fix is landing or dropping those rows, acts not commands

## hooks/stop-guard.sh

- `refuse exit2 stop "$fact" "$fix" "${reasons}A stop is irreversible, and a wave is active.` — stop-guard deny() forwarder — fix: `${OBSERVE_CMD} <target>` (`bash <hooks>/stop-check.sh <target>`), printed runnable
- `[ -n "$RAW" ] || deny "this stop names no target" "name the agent to stop" "The stop names no target: tool_input.task_id is empty."` — stop names no target — fix: the observe command, through deny()
- `|| deny "this stop carries no transcript path" "run /bionic:doctor" "This stop request carries no usable transcript path, so its session's agents cannot be resolved."` — no transcript path — fix: `/bionic:doctor`
- `|| deny "the state directory is a symlink" "remove that symlink" "This repo's .bionic state directory is a symlink; nothing here will read through it."` — state directory is a symlink — none: which symlink to remove and why is the human's judgment; the detail names the path
- `deny "this target is on no roster row of this session" "name a rostered agent or id" \` — target on no roster row — fix: the observe command, through deny()
- `deny "that name has more than one live row" "name the full agent id" \` — name with several live rows — fix: the observe command with the full id, through deny()
- `deny "that alias is not accepted for this agent" "use the agent's own name" "Target '${RAW}' is not an accepted alias for '${BASE}'." \` — alias not accepted — fix: the observe command with the agent's own name, through deny()
- `deny "the session roster carries no id for it" "stop it yourself or order it" "Target '${RAW}' is not on this session's register: the roster carries no agent id for '${AGENT_NAME}'." \` — no agent id on the roster — fix: the observe command, through deny(); or the human's own stop
- `deny "it is still working, nothing delivered" "let it finish, or order it" \` — still working, nothing delivered — fix: the observe command, through deny(); or an order recorded by the human
