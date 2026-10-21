# The test census

One line per section of every suite under tests/, read against tests/RUBRIC.md, in the rubric's record shape. The cull deletes by this file and never by the shape of a line. `## Culled` at the end lists every section the census culls.

rubric: 98b11b131 · head: 67b5f3cd0 · suites: 114 · sections: 1034 · keep: 840 · duplicate: 158 · prose pin: 18 · tally: 1 · vacuous: 17 · no section: 3 suites

The section-list command counts 1064 calls. The census leaves out 22 that sit inside heredoc bodies (framework.test.sh 17 sections and 1 setup, runner-roster.test.sh 4 sections), which write scratch suites and are fixture text, and 8 fixture setup_sections, which build what a later section reads. 1064 - 22 - 8 = 1034.

## agent-context-guard.test.sh

agent-context-guard.test.sh | §G0 | duplicate | hooks/agent-context-guard.sh: a syntax error planted, so bash -n fails (G0) and every drive of the guard exits 2 | agent-context-guard.test.sh §G1
agent-context-guard.test.sh | §G1 | keep | hooks/agent-context-guard.sh: the agent_id test line (`[ -n "$(_jq .agent_id)" ]`, or exit 0) deleted, so the main thread of an armed session is walled (G1.2); also the guard never execs the target (G1.1), caught by §G3, §G8 | agent-context-guard.test.sh §G7 (one-catcher rule: its anchor row goes red on the deletion and it is culled)
agent-context-guard.test.sh | §G2 | keep | hooks/agent-context-guard.sh: the closing `exit $?` made `exit 0`, so the artifact wall's exit-2 refusal is swallowed (G2.1); every dispatch-wall row refuses on stdout with exit 0 and stays green | none (searched 'agent-context-guard' in tests/)
agent-context-guard.test.sh | §G3 | keep | hooks/agent-context-guard.sh: ROSTER_FILE no longer keyed by ${BIONIC_SID} (any roster-*.state under .bionic/tmp arms), so a foreign session's roster arms this one (G3.1); G3.2 is §G1's G1.1 and G3.3 the session-key guard hook-adoption.test.sh §5d drives | none (searched 'roster-' and 'agent-context-guard' in tests/)
agent-context-guard.test.sh | §G4 | keep | hooks/agent-context-guard.sh: the `[ -f "$TARGET" ]` or-exit-0 line deleted, so a target not on disk is run by bash and exits 127 with noise (G4.2) | none (searched 'agent-context-guard' and 'no-such-hook' in tests/)
agent-context-guard.test.sh | §G5 | keep | hooks/agent-context-guard.sh: the `BIONIC_HOOK_CHANNEL=agent-context` prefix dropped from the exec line, so the dispatch wall journals a nested dispatch's roster row (G5.2) | none (searched 'HOOK_CHANNEL' in tests/)
agent-context-guard.test.sh | §G6 | keep | rule: lint — a private resolve_project_root() planted in hooks/agent-context-guard.sh, so the awk over the guard finds it (G6.1); G6.3's worktree mapping in payload/scripts/lib/root.sh project_root is root.test.sh §2's (unverified) | none (searched 'resolve_project_root' in tests/)
agent-context-guard.test.sh | §G7 | duplicate | hooks/agent-context-guard.sh: the agent_id line or the roster line deleted, so the anchor rows go red; the mutant rows fail only on a guard broken in a way §G1 already sees | agent-context-guard.test.sh §G1
agent-context-guard.test.sh | §G8 | keep | hooks/agent-context-guard.sh: the `[ "$BIONIC_ENGAGED" = 1 ]` or-exit-0 line deleted, so an unengaged armed session's nested dispatch is refused (G8.1, G8.2) | none (searched 'agent-context-guard' and 'unengage' in tests/)
agent-context-guard.test.sh | §G9 | duplicate | payload/scripts/lib/walls.sh wall_background_suite_guard: the agent_id, roster or engagement predicate deleted, or the off-budget refusal dropped (G9.1-G9.4); the booking wrap rows are the compound's | background-suite-guard.test.sh §B6 (unverified), background-suite-guard.test.sh §B4 (unverified)

## archive.test.sh

archive.test.sh | §0 | duplicate | payload/scripts/lib/archive.sh: the file does not parse or loses archive_run, so every later call_archive fails | archive.test.sh §1
archive.test.sh | §1 | keep | payload/scripts/lib/archive.sh archive_run: `mv` made a copy, so the source plans/epic-01 stays behind (1g); or the origin-file write deleted (1i) | none (searched '/origin' and 'archive_run' in tests/; close-out-1 §1's fixture sits in an open epic and never moves)
archive.test.sh | §2 | keep | payload/scripts/lib/archive.sh archive_run: the open-run skip line drops the sibling plan's path, so 2e no longer names wave-02.plan.md | none (searched 'still has an open run' in tests/; close-out-1.test.sh §1 1ai catches the scan deleted, not the name)
archive.test.sh | §3 | keep | payload/scripts/lib/archive.sh archive_run: the occupied-slot loop deleted, so mv nests the source inside the occupant and 3a's exit 1 becomes 0 | none (searched 'occupied slot' and 'archive_run' in tests/)
archive.test.sh | §3f | keep | payload/scripts/lib/archive.sh archive_run: the `2>/dev/null` on `mkdir -p "$dest_base"` dropped, so mkdir's diagnostic prints ahead of the refusal (3f.2, 3f.3) | none (searched 'could not create' in tests/)
archive.test.sh | §binding | keep | payload/scripts/lib/archive.sh archive_run: the archive_binding_check call deleted, so a drifted archive-root moves instead of exit 1 (b1) | none (searched 'archive_binding_check' and 'archive-root drifted' in tests/; close-out.prelude.sh fixtures keep the roots equal)
archive.test.sh | §4 | keep | payload/scripts/lib/archive.sh archive_run: the origin comparison deleted, so a basename collision moves instead of exit 1 (4a) | none (searched 'origin mismatch' in tests/)
archive.test.sh | §5 | duplicate | payload/scripts/lib/archive.sh archive_run: the archive-on-close false arm deleted, so the run moves (5b); "5d: the printed line names the opt-out" is a prose pin carried by exit 0 with the source in place | close-out-4.test.sh §ONE-WRITER (unverified; OW-3 reads the plan still in place under archive-on-close: false)
archive.test.sh | §6 | duplicate | payload/scripts/lib/roots.sh archive_root: the $HOME/bionic-archive default changed (6a); archive_run's aroot stops reading archive_root (6b) | roots.test.sh §1a (unverified), archive.test.sh §1
archive.test.sh | §7 | vacuous | its one assertion is that the tracked skill file steps/9.md exists, a document no program reads by a field; the two spans it extracts are never asserted | none (searched 'steps/9.md' in tests/)

## background-suite-guard.test.sh

background-suite-guard.test.sh | §B0 | duplicate | payload/hooks/bash-walls.sh made not to parse or removed, so (B0) goes red | background-suite-guard.test.sh §B1
background-suite-guard.test.sh | §B1 | keep | payload/scripts/lib/walls.sh wall_background_suite_guard: the budget compare reads only the first suite the command names, so `alpha && gamma` passes (B1e); also the runner form `pytest` outside the set admitted (B1h) | none (searched 'BUDGET' and 'suites_allowed' in tests/; agent-context-guard.test.sh §G9 drives a single off-budget suite only)
background-suite-guard.test.sh | §B2 | keep | payload/scripts/lib/walls.sh wall_background_suite_guard: the full-tree arm stops requiring run.sh in the row's set, so `bash tests/run.sh` passes a narrow budget (B2a) | none (searched 'suites_allowed=run.sh' and 'bash tests/run.sh' in tests/; cmd-class.test.sh §C4 rows carry run.sh)
background-suite-guard.test.sh | §B3 | duplicate | payload/scripts/lib/cmd-class.sh: the FARM_OUT_*= prefix no longer comes off before the class reading, so the prefixed suite reads as no suite and is admitted (B3a, B3b); B3c and B3d assert an env read the arm never had, B3e repeats B1a | cmd-class.test.sh §C1
background-suite-guard.test.sh | §B4 | keep | payload/scripts/lib/walls.sh wall_background_suite_guard: the no-recorded-set arm (BUDGET_STATED=no) lets the suite run instead of refusing, so a pre-wall row's suite is admitted (B4c); also the printed amend line no longer admits the unplaced agent (B4e5-B4e7) | none (searched 'no set was recorded' and 'suites+' in tests/)
background-suite-guard.test.sh | §B5 | duplicate | payload/scripts/lib/roster.sh roster_row_for_id: the first row carrying the id picked instead of the last, so the later row's delta.test.sh is refused (B5a) | roster.test.sh §R11
background-suite-guard.test.sh | §B5c | keep | payload/scripts/lib/walls.sh wall_background_suite_guard: the RE_EXECUTES compare dropped, so the run a successor row declares is still refused (B5c second row) | none (searched 're_executes' in tests/; cross-gate-agreement-2.test.sh §S13b and dispatch-preflight-4a.test.sh read the lift, never the wall)
background-suite-guard.test.sh | §B6 | keep | payload/scripts/lib/walls.sh wall_background_suite_guard: the agent_id, engagement or roster-present partition deleted, so a main-thread, unengaged or unarmed call is refused (B6a-B6d) | agent-context-guard.test.sh §G9, bash-walls.test.sh §7 (reopened by the merge: every named catcher is culled, so it keeps its defect)
background-suite-guard.test.sh | §B7 | duplicate | payload/scripts/lib/walls.sh wall_background_suite_guard: the backgrounded-suite arm (ARM 1) deleted, or run_in_background false read as true, so an on-budget backgrounded suite is admitted (B7a) or a false flag refused (B7c) | cmd-class.test.sh §C4
background-suite-guard.test.sh | §B8 | keep | payload/scripts/lib/walls.sh wall_background_suite_guard: the `set -f` around the target split removed, so `bash tests/*.test.sh` expands in the hook's cwd to two on-budget names and passes (B8f); also the repo scoping of a suite path outside the tree (B8c, B8d) | none (searched 'set -f', 'scratch-probe' and '\*.test.sh' in tests/)
background-suite-guard.test.sh | §B9 | keep | payload/scripts/lib/cmd-class.sh: the literal `for s in` list no longer resolved into the suites it names, so a loop over two on-budget suites is refused (B9a0) | none (searched 'for s in' and 'unexpanded name' in tests/)
background-suite-guard.test.sh | §B10 | duplicate | payload/scripts/lib/context.sh bionic_context: the `[!A-Za-z0-9_-]` shape case deleted (regex row); payload/hooks/bash-walls.sh stops calling bionic_context ahead of bionic_fold, so no wall runs (call and order rows) | context.test.sh §3, background-suite-guard.test.sh §B1, agent-context-guard.test.sh §G1, execution-recorder.test.sh §Section 1
background-suite-guard.test.sh | §B11 | duplicate | payload/scripts/lib/refuse.sh: exit2's detail_to_user cell made no, so the recorded set and its detail leave the default stream (B11e1, B11e3); b11_line is defined and never called, so the four guarded calls above B11e assert nothing, and the "On the budget:" absence on the verdict line pins wording | refuse.test.sh §1, background-suite-guard.test.sh §B1
background-suite-guard.test.sh | §B12 | keep | payload/scripts/lib/cmd-class.sh cmd_backgrounded: the quote-aware scan dropped, so an & inside quotes reads as backgrounding and the on-budget foreground suite is refused (B12f); B12a and B12b are refused by the budget arm whatever ARM 1 does | none (searched 'cmd_backgrounded' and 'a & b' in tests/)

## bash-walls-egd.test.sh

bash-walls-egd.test.sh | §EG-DERIVE | keep | payload/scripts/lib/walls.sh: the derived-result line `r[PROOF_QUESTION] = ((ev SUBSEP PROOF_RESULT) in D) ? … : PROOF_RESULT` made the written result, so a reading whose only finding moved to defer is still refused (EGD-2, EGD-mut2) | none (searched '_proof_reading_result' and 'moved: record' in tests/; release-approval.test.sh and close-out-4.test.sh drive the judge, not the wall)
bash-walls-egd.test.sh | §EG-DERIVE (T72) | keep | payload/scripts/lib/walls.sh: the guard that sets handed=1 only when BIONIC_DEBTS_PLAN names the judged plan made unconditional, so lines derived for another plan admit the moved reading (EGD-10b, EGD-mut8); also hooks/bash-walls.sh's eg_plan_reads_readings gate dropped (EGD-7b) | none (searched 'BIONIC_DEBTS_PLAN' and 'eg_plan_reads_readings' in tests/)
bash-walls-egd.test.sh | §JURIS | keep | payload/scripts/lib/walls.sh _bsg_commit_outside: the placement-reader answer ignored, so a read-only role's commit in a scratch repository named by absolute cds is refused instead of exempt with one boundary line (JURIS-9) | none (searched 'outside the engaged repository' and 'moving-form' in tests/)

## bash-walls.test.sh

bash-walls.test.sh | §1 | duplicate | hooks/bash-walls.sh: the engagement guard deleted, so an unengaged session's suite command is denied (1h, 1i); the malformed-payload step-aside lost (1f); a loaded library writes on the quiet path (1c) | protect-database.test.sh §Section 8, farm-out-reminder.test.sh §1 (unverified), farm-out-reminder.test.sh §2 (unverified)
bash-walls.test.sh | §2 | keep | payload/scripts/lib/walls.sh _wall_mentions_git: the backslash-newline continuation no longer joined, so the screen calls `g\<newline>it push origin main` not-git and protect-main passes it (2b1) | none (searched '_wall_mentions_git' and "printf 'g" in tests/)
bash-walls.test.sh | §3 | keep | hooks/bash-walls.sh: protect-database's wall listed ahead of protect-main in the fold call, so the sql refusal prints above the push refusal (3d) | none (searched 'sql refused' and 'manifest order' in tests/)
bash-walls.test.sh | §4 | keep | payload/scripts/lib/fold.sh: farm-out's stdout nudge dropped when an exit2 wall blocks the same payload, so stdout carries no JSON document (4c) | bash-walls.test.sh §5 (one-catcher rule: §5 catches it too and is culled)
bash-walls.test.sh | §5 | duplicate | payload/scripts/lib/fold.sh: the nudge dropped beside an exit2 block (5c, 5d); the evidence gate's refusal words on the user stream (5b) | bash-walls.test.sh §4, canonical-sdlc-evidence-gate.test.sh §Section 2 (unverified)
bash-walls.test.sh | §6 | duplicate | payload/scripts/lib/fold.sh: the exit2 mode chosen over deny when both wires block, so the deny JSON and the farm-out reason are lost (6a, 6c, 6d) | fold.test.sh §12 (unverified), fold.test.sh §13 (unverified)
bash-walls.test.sh | §7 | duplicate | payload/scripts/lib/walls.sh wall_background_suite_guard: the agent_id or roster predicate deleted, so a main-thread or unarmed backgrounded suite is refused (7a, 7c, 7d); protect-main gated by the roster (7e) | background-suite-guard.test.sh §B6 (unverified), protect-main.test.sh §Section 1 (unverified)
bash-walls.test.sh | §8 | duplicate | payload/scripts/lib/fold.sh: the composed refusal not rendered, or a line printed above it on stderr (8a, 8b) | bash-walls.test.sh §3, farm-out-reminder.test.sh §1 (unverified)
bash-walls.test.sh | §9 | keep | hooks/bash-walls.sh loader_fail_closed: the whole-string match of the four repair commands loosened to a prefix match, so `bash .../doctor.sh; git push origin main` passes with no library (9g) | none (searched 'plugin update bionic@bionic' and 'loader_fail_closed' in tests/; loader.test.sh has no section)
bash-walls.test.sh | §10 | keep | hooks/bash-walls.sh: BIONIC_LIB_WANT made the union of the five walls' lists, so a missing cmd-class.sh fails the compound closed and `ls` is refused (10b-10l) | cmd-class.test.sh §C5 (unverified) (reopened by the merge: every named catcher is culled, so it keeps its defect)
bash-walls.test.sh | §11 | duplicate | payload/scripts/lib/walls.sh wall_evidence_gate or fold.sh: the stubbed refusal not rendered through the fold, or exit 2 lost (11a, 11b, 11h); the symlink, fabricated-file and rm rows read a stage no shipped line makes, so no mutation of code that is there turns them red | bash-walls.test.sh §STAGE
bash-walls.test.sh | §STAGE | keep | payload/scripts/lib/walls.sh wall_evidence_gate: what the body prints on stdout dropped instead of passed to the hook's stdout, so STAGE-n8 and STAGE-n11 go red; also the pipe-fallback line (STAGE-j1) | none (searched 'BODY-LINE' and 'could not stage its refusal' in tests/)
bash-walls.test.sh | §12 | duplicate | payload/scripts/lib/context.sh bionic_context: rung 1 takes CLAUDE_PROJECT_DIR on `-d` alone, so a launch directory that is no project disarms the walls (12b, 12d, 12g) | context.test.sh §2 (unverified)
bash-walls.test.sh | §13 | keep | payload/scripts/lib/walls.sh protect-main: `-C` dropped from the `git symbolic-ref --short HEAD` call, so the hook process's own branch is judged and a push from a payload on main passes (13c) | none (searched 'symbolic-ref' in tests/; protect-main.test.sh stubs it with a shim that strips -C)
bash-walls.test.sh | §VERDICT / §RULED | keep | payload/scripts/lib/walls.sh matrix_row_ruled: a REFUTED row with no waiver counted ruled, so `current 8 --check` passes and no row:AC-2 item opens (RULED-1, RULED-1e); also: RULED-ONE is a lint on a second definition | none (searched 'matrix_row_ruled' and 'row:AC' in tests/)

## binding.test.sh

binding.test.sh | §1 | duplicate | payload/scripts/lib/binding.sh bind_plan: the marker's plan= line written wrong; the none arm refused; BIND_REFUSAL initialised non-empty on entry; a line writes to stderr on the success path | binding.test.sh §7, engage.test.sh §E8 (unverified)
binding.test.sh | §2 | keep | payload/scripts/lib/binding.sh bind_plan:179 the marker-symlink arm sets BIND_REFUSAL=marker-dir-symlink, so "…and names the marker" goes red while every exit stays 1 | none (searched 'BIND_REFUSAL' and 'marker-symlink' in tests/; engage.test.sh §E8 pins only the exit 1)
binding.test.sh | §3 | keep | payload/scripts/lib/binding.sh bind_plan:242 the write-failed arm returns 1 instead of 2, so a broken tree reads as a refusal (exit 2 row) | none (searched 'write-failed' and 'BIND_RC' in tests/)
binding.test.sh | §4 | duplicate | payload/scripts/lib/binding.sh bind_plan:161 BIND_REFUSAL initialised to a word instead of empty, so a success names a reason | binding.test.sh §7
binding.test.sh | §5 | keep | payload/scripts/lib/binding.sh bind_holders: the symlinked-marker skip deleted, so a linked marker naming the plan holds it (exit 0 instead of 1) | none (searched 'bind_holders' and 'BIND_HOLDERS' in tests/)
binding.test.sh | §7 | keep | payload/scripts/lib/binding.sh bind_delivered: the abandoned: test deleted, so the bind verb's act binds an abandoned plan (7c) | none (searched 'bind_delivered' and 'abandoned' in tests/)

## booked.test.sh

booked.test.sh | §DETACH | keep | payload/scripts/booked.sh --detach: the detached side started in the caller's process group instead of a session of its own, so the SIGKILL of the group takes the run and its log never ends rc=0 (DT.5, DT.10, DT.11) | none (searched '\-\-detach' and 'run_pid=' in tests/; farm-out-reminder, cmd-class and agent-context-guard read only the wall's wrap text)
booked.test.sh | §LOG2 | keep | payload/scripts/booked.sh: the attempt number dropped from a re-run's log name, so the second attempt truncates the first log instead of writing …-2.log (L2.1, L2.4) | none (searched '\-2\.log' in tests/; the other hits are lib/line.sh's and proof logs)
booked.test.sh | §WAIT-CALLER | keep | payload/scripts/booked.sh --detach: the live-run attach test deleted, so a second caller of the same run starts it again (AT.1, AT.3); or the LOST arm's exit 70 dropped (LS.1) | none (searched 'booked: attached' and 'booked: LOST' in tests/)
booked.test.sh | §DETACH-CEILING | keep | payload/scripts/booked.sh --detach: the detached side's gate ask loses --within BIONIC_SETTLE_MAX_WAIT, so an unadmitted run waits forever instead of exit 75 (DC.4, DC.6, DC.7) | none (searched 'SETTLE_MAX_WAIT' in tests/; runner-width and slots drive the foreground shim)
booked.test.sh | §WALL | duplicate | hooks/bash-walls.sh: the suite wrap drops --detach or gains --max-wait (WL.1, WL.2); booked.sh's detach dropped (WL.3 to WL.5) | farm-out-reminder.test.sh §1 (unverified), booked.test.sh §DETACH
booked.test.sh | §RUNLINE | keep | payload/scripts/booked.sh: the run close's line/v1 ev=run append deleted, so the bound plan's landing record holds no run line (BR-2, BR-3) | none (searched 'ev=run' in tests/; lib/regression-fixture.sh plants the line by hand)
booked.test.sh | §SIGNALS | keep | payload/scripts/booked.sh --detach: the perl reset of HUP, INT and QUIT before exec dropped, so a command launched under an ignoring parent sees none of them (SG-1) | none (searched 'trap "" HUP' in tests/; lib/name-scan.sh only resets for itself)

## canonical-sdlc-evidence-gate-2.test.sh

canonical-sdlc-evidence-gate-2.test.sh | §Section 29 | keep | payload/scripts/lib/walls.sh:3833 the deploy-trio loop under a named deploy_target deleted, so a Step 9 at deploy_target: local-harness with delivered: alone commits; (29d) goes red. also: 29b/29f/29g read the delivered refusal | none (searched '"deployed"' and 'deploy_target' in tests/; shard 1 holds Sections 1-8 only)
canonical-sdlc-evidence-gate-2.test.sh | §Section 30 | keep | payload/scripts/lib/walls.sh:1715 user_confirmed_attributed returns 0 on any non-empty value, so the agent-shaped T4 confirmation with an empty auditor cell commits at current 8; (30b) goes red | none (searched 'user_confirmed_attributed' and 'user-confirmed' in tests/)
canonical-sdlc-evidence-gate-2.test.sh | §Section 31 | keep | payload/scripts/lib/walls.sh:1478 plan_write_note's case arm widened to `*)`, so every refused commit carries the also-writes-the-plan note; (31c) goes red. also: 31a's AC-2 refusal is the pending-row arm many sections read | none (searched 'also writes the plan' in tests/ payload/)
canonical-sdlc-evidence-gate-2.test.sh | §Section 32 | keep | payload/scripts/lib/walls.sh:1661 matrix_auditor_required's `single) return 1` arm deleted, so a single-rigor plan with empty auditor cells is refused at current 6-9; (32a)-(32d) go red | none (searched 'matrix_auditor_required' and 'rigor single' in tests/; close-out-1 and scale-profile hold single plans but no empty-auditor matrix past Step 5)
canonical-sdlc-evidence-gate-2.test.sh | §Section 33 | keep | payload/scripts/lib/walls.sh:4070 the waiver test ahead of the task: 9 mis-tag refusal deleted, so a waived T1 row carrying task: 9 is refused; (33a) goes red | none (searched 'task: 9' in tests/)
canonical-sdlc-evidence-gate-2.test.sh | §Section 34 | keep | payload/scripts/lib/walls.sh: the evidence gate's misplacement sweep deleted, so an engaged session committing with a marked plan under docs/bionic/plans/ is allowed; (34c control) goes red. also: the silent rows need both engagement guards (hooks/bash-walls.sh:231 and walls.sh:1952) gone at once, and a lib/context.sh marker mutation is the remaining defect | none (searched 's24_marked_plan' and 'misplaced' in tests/; hook-adoption and governing-skill read the write hook's misplacement, not the commit gate's)
canonical-sdlc-evidence-gate-2.test.sh | §ORDER-VERB, §WHOLE-RUN, §FIX-ROW, §APPROVED-HEAD | keep | hooks/poker/proof.sh:1340 the runs-once-at-a-head refusal deleted, so a second whole run at the same green head runs and writes a second log; (WR-3) goes red. also: AH-3/AH-4/WR-3b/FX-4b read refusal words beside the exit | none (searched 'runs once at a head' and 'regression-run' in tests/)

## canonical-sdlc-evidence-gate.test.sh

canonical-sdlc-evidence-gate.test.sh | §Section 1 | keep | payload/scripts/lib/walls.sh _eg_commit_count: the filter that skips a segment whose git subcommand is not commit deleted, so `git status` and `git push` under a placeholder plan are judged as commits and refused | none (searched '_eg_commit_count' and 'not a commit' in tests/; bash-walls.test.sh §1 runs ls on a repo with no blocking plan)
canonical-sdlc-evidence-gate.test.sh | §Section 2 | keep | its one row drives an unengaged bare directory, so only the walls' engagement short-circuit inverted, or load-time stderr from a library bash-walls.sh loads, turns it red | bash-walls.test.sh §12, bash-walls.test.sh §1 (reopened by the merge: every named catcher is culled, so it keeps its defect)
canonical-sdlc-evidence-gate.test.sh | §Section 3 | duplicate | payload/scripts/lib/walls.sh: the current reader loses the lettered step, so 8b reads as missing (3b); the Step-line reader loses the optional bullet (3c) | cross-gate-agreement-1.test.sh §A1 (unverified; its current-8b fixture drives the gate), close-out-1.test.sh §1 (unverified; 1ag commits through the real bash-walls.sh on bulleted Step lines)
canonical-sdlc-evidence-gate.test.sh | §Section 4 | duplicate | payload/scripts/lib/walls.sh: the missing-current arm or the no-Step-N arm deleted, so a plan without either is allowed | cross-gate-agreement-1.test.sh §A1 (unverified; its battery reads the gate's "has no 'Step N:' line" and "missing a valid 'current: N'" answers)
canonical-sdlc-evidence-gate.test.sh | §Section 5 | keep | payload/scripts/lib/walls.sh: the placeholder token list loses `tbd` or `xxx`, or the value stops being trimmed and lowercased before the whole-value compare, so "placeholder 'TBD'" or "padded mixed-case 'readback:   Pending  '" is allowed | none (searched 'placeholder' and 'TBD' in tests/; bash-walls.test.sh §2 2e reads only a bare TODO)
canonical-sdlc-evidence-gate.test.sh | §Section 6 | duplicate | payload/scripts/lib/git-argv.sh: a commit in a later && segment not found, or a quoted "git commit" in an echo read as one | bash-walls.test.sh §5 (unverified), git-argv.test.sh §Section 1 (unverified)
canonical-sdlc-evidence-gate.test.sh | §Section 7 | duplicate | payload/scripts/lib/run.sh active_run: the newest open plan no longer chosen, or a marker-less newer file shields the older plan | cross-gate-agreement-1.test.sh §A1 (unverified; newest-plan-wins and marker-less-newest-loses fixtures)
canonical-sdlc-evidence-gate.test.sh | §Section 8 | duplicate | its blocks and allows on a project plan read the same placeholder arm §Section 5 reads; the global and superpowers rows drive unengaged directories, and ignoring those trees is code absent from the program, so no defect there is code that is there | canonical-sdlc-evidence-gate.test.sh §Section 5

## canonical-sdlc-governing-skill.test.sh

canonical-sdlc-governing-skill.test.sh | §walk | keep | hooks/canonical-sdlc-governing-skill.sh: the walk: enum check deleted, so a plan with walk: rquired is written; (walk_typo exit 2) goes red. also: the CRLF, spike-cap and intent-minimum rows below it in the section | none (searched 'rquired', 'walk_typo' and 'spike-cap' in tests/)
canonical-sdlc-governing-skill.test.sh | §rigor-override | keep | hooks/canonical-sdlc-governing-skill.sh: the rigor-override: presence test deleted, so a project-minimum violation with the marker logs the violation instead of user-overridden; (rigor_override_present) goes red, and the audit line is the hook's only carrier | none (searched 'rigor-override' and 'user-overridden' in tests/)
canonical-sdlc-governing-skill.test.sh | §AC-10 | keep | payload/scripts/lib/root.sh:226 the older-git rev-parse arm without --path-format deleted, so under git < 2.31 the root falls back to the cwd and a correctly placed plan is refused as misplaced; (ac10_e2e_oldgit valid artifact allowed) goes red | none (searched 'path-format' in tests/)
canonical-sdlc-governing-skill.test.sh | §THEMES | keep | hooks/canonical-sdlc-governing-skill.sh: the theme arm's count test deleted, so a wave requirements write of two theme sections is written; (THEMES-3 two theme sections are refused) goes red, and a flat ## Requirements list writes too (THEMES-2) | none (searched 'theme rule' and 'theme sections' in tests/)

## card.test.sh

card.test.sh | §Section 1 | keep | payload/scripts/card.sh: the unknown-kind arm falls through to a render and exits 0, so `card.sh not-a-kind` no longer exits 64 (3) | none (searched 'card.sh' and 'not-a-kind' in tests/)
card.test.sh | §Section 2 | keep | payload/scripts/card.sh: the decision kind's serves column narrowed from 14 columns, so the ADR cell starts left of its header (7) | none (searched 'card.sh decision' and 'card decision' in tests/)
card.test.sh | §Section 3 | keep | payload/scripts/card.sh: a folded free cell's continuation line indented to column 1 instead of the cell's start column 9 (14) | none (searched 'continuation' and 'card.sh' in tests/)
card.test.sh | §Section 4 | keep | payload/scripts/card.sh: the free cell cut at its column width instead of folded, so the long cell renders on one line (21-25) | none (searched 'card.sh' in tests/; width.test.sh §Section 5 drives bionic_wrap alone)
card.test.sh | §Section 5 | keep | payload/scripts/card.sh: cells padded by byte length instead of bionic_cols, so the em-dash row's trailing column starts two columns early (27, 27a) | none (searched 'card.sh' and 'em dash' in tests/)
card.test.sh | §Section 6 | keep | payload/scripts/card.sh: the ownership owner column fixed instead of sized per batch, so surfaces starts on different columns for the two owner widths (40, 41) | none (searched 'per-batch' and 'card.sh' in tests/)
card.test.sh | §Section 7 | keep | payload/scripts/card.sh step1: the missing-provenance refusal deleted, so a REQ heading with no provenance line renders a card at exit 0 (64, 64b) | none (searched 'provenance' and 'card.sh step1' in tests/)

## close-out-1.test.sh

close-out-1.test.sh | §0 | keep | payload/scripts/close-out.sh: the census takes every wt/* branch the repository holds instead of the `## Tasks` worktree cells, so the foreign wt/99-x is named (0j) and the empty-register line is lost (0m). also: 0e-0g read the suite's own in_fixture | none (searched 'registered tree' and 'census: no registered' in tests/)
close-out-1.test.sh | §0n | duplicate | payload/scripts/close-out.sh: the census sweeps an unregistered wt/* branch (0n2b), or wt_unreached's refusal on a registered unreached branch dropped (0n3) | close-out-1.test.sh §0, close-out-1.test.sh §2
close-out-1.test.sh | §0o | keep | payload/scripts/close-out.sh wt_unreached: the no-worktree-column fallback census deleted, so a column-less plan's unreached wt/01-T1 closes rc 0 (0o4) | none (searched 'WOULD REFUSE' and 'mk_census_fixture_nowt' in tests/)
close-out-1.test.sh | §0q | keep | payload/scripts/close-out.sh wt_unreached: the fallback's `wt/<NN>-*` scope widened to `wt/*`, so a foreign wave's wt/07-z refuses the run (0q4) | none (searched 'add_foreign_unreached_branch' and 'wt/07-z' in tests/)
close-out-1.test.sh | §0r | keep | payload/scripts/close-out.sh: the wave-number refusal for a column-less wave-scale plan on a non-wave branch deleted, so check exits 0 (0r1) | none (searched 'mk_census_fixture_nowt' and 'not-a-wave-branch' in tests/)
close-out-1.test.sh | §ANY-BRANCH | keep | payload/scripts/close-out.sh: the task row's pr act no longer writes the `gh pr create` command into the continuation (PR5) | none (searched 'gh pr create' in tests/; scale-profile.test.sh §TASK reads check's merge line only and names this suite for the record)
close-out-1.test.sh | §1 | keep | payload/scripts/close-out.sh: the Step-8 block's tasks-completed: joined onto the previous line instead of its own continuation line (1y); also cleanup: done (1w) and the patrol: CronDelete act line (1p) | none (searched 'tasks-completed', 'cleanup: done' and 'patrol: CronDelete' in tests/)
close-out-1.test.sh | §2 | keep | payload/scripts/close-out.sh wt_unreached: the refusal over a registered unreached wt/01-y dropped, so run deletes branches and wipes tmp (2a-2e) | none (searched 'add_unreached_branch' in tests/; close-out-4.test.sh §PARKED plants one on a parked plan, where nothing refuses)
close-out-1.test.sh | §3 | duplicate | payload/scripts/close-out.sh:361 the already-closed early return deleted, so a second run writes a second epic row (3c, 3e) | close-out-4.test.sh §PARKED
close-out-1.test.sh | §4 | keep | payload/scripts/close-out.sh check: the diagnosis guard on act 2 or act 3 dropped, so check deletes wt/01-x or wipes .bionic/tmp (4i, 4j) | none (searched 'tmp_entries' and 'check' with branch_exists in tests/close-out-*.test.sh)
close-out-1.test.sh | §4b | duplicate | payload/scripts/close-out.sh run: the gate pre-flight asked after the Step-9 flip, so a refused plan reads delivered (4l, 4p) | close-out-1.test.sh §4c
close-out-1.test.sh | §4c | keep | payload/scripts/close-out.sh run: the gate pre-flight moved after acts 1-6, so a refused plan's wt/01-x is swept and its epic row written (4y, 4ab); also the scratch preflight copy left beside the plan (4u, 4ad) | none (searched 'preflight' in tests/close-out-*.test.sh)
close-out-1.test.sh | §4d | keep | payload/scripts/close-out.sh run: the current: 8 check deleted, so a plan at current 7 or 4 has its tail performed (4aj.7, 4al.7) | none (searched 'advance_to .* 7' and 'current: 8' in tests/close-out-*.test.sh)
close-out-1.test.sh | §4e | keep | payload/scripts/close-out.sh: the Step 9 line appended instead of replacing a hand-written `- Step 9: (pending)`, so the plan carries two (q1.6f) | none (searched 'Step 9: (pending)' in tests/)
close-out-1.test.sh | §VER | keep | payload/scripts/close-out.sh: the delivered line, epic row and continuation header take VERSION from plugin.json instead of the plan's release: field (VER4, VER6, VER7) | none (searched 'release: ' and 'epic_version_cell' in tests/)
close-out-1.test.sh | §FIX-SHAPE | vacuous | FS1-FS5 run the suite's own builder_plants over tests/close-out.prelude.sh and doctored copies of it, which reads only suite code | none (searched 'builder_plants' in tests/)
close-out-1.test.sh | §E2E | keep | payload/scripts/close-out.sh: the refusal of a release: value holding a pipe character deleted, so run splits the epic row's cell and closes (E2E14) | none (searched 'A-orch-28' and 'release: 1.2' in tests/)
close-out-1.test.sh | §BRANCH-AGREE | keep | rule: lint — a second reader of integration-branch planted in hooks/ or payload/scripts/, so the sweep finds it beside lib/plan.sh (BA5) | none (searched 'plan_integration_branch' and 'integration-branch' in tests/; handoff-file.test.sh §BRANCH-AGREE asks the verbs, not the tree)

## close-out-2.test.sh

close-out-2.test.sh | §4f | keep | payload/scripts/close-out.sh: the shipped-table locator takes the first wave header instead of the one with a shipped cell, so the wave-01 row lands in the planned table; (78.1d) goes red. also: 86.1-86.4 read the ADR cell close-out-3 also reads | none (searched 'rows_with_wave' and 'already listed' in tests/)
close-out-2.test.sh | §5 | keep | payload/scripts/close-out.sh act_tmp: TMP_LINE built from the removed count instead of `before`, so a close that spares B's five files says tmp-wiped: 8; (5.5) goes red while close-out-1.test.sh 1f, whose fixture removes all it scans, stays green. also: 5.2 and 5.8 are caught by notify.test.sh §SOURCES W2/W3a | none (searched 'tmp-wiped' and 'plant_tmp_session' in tests/)
close-out-2.test.sh | §CARRY | keep | payload/scripts/close-out.sh: the inherited-line filter matching again or open made to match nothing, so an inherited deferral deferred again is not carried; (CARRY-18) goes red | none (searched 'carry_section' and 'again: ' in tests/; close-out-3 reads only debt: lines under the heading)
close-out-2.test.sh | §LANDINGS | keep | hooks/poker/line.sh:355 landing_unmeasured answers yes for a missing record, so a run with no landing record carries the unmeasured line instead of the zero line; (LAND-7) goes red. also: LAND-3's template line is caught by close-out-3.test.sh HH-7b | none (searched 'queue=0' and 'landing-report' in tests/)
close-out-2.test.sh | §CLOSED | keep | payload/scripts/close-out.sh:308 co_pr_owed's branch-exists test deleted, so a merged and deleted branch reads as owed and the closed form says to be pulled into main; (CLOSED-7) goes red | none (searched 'closed-form' and 'merged into main' in tests/)

## close-out-3.test.sh

close-out-3.test.sh | §HAND-HOLDS | keep | hooks/poker/line.sh: the hand-holds fold stops counting ev=stop-run lines, so the card reads stop-runs=0 (HH-1, HH-13); §HAND-HOLDS-KINDS plants no stop-run | none (searched 'stop-runs=' and 'hand-holds: ' in tests/)
close-out-3.test.sh | §FLOOR-DECLARED (wave-28 T75; REQ-17 AC-17.1, D36) | keep | payload/scripts/close-out.sh: the regression proof required to carry kind=regression from the shipped floor's log only, so a declared `regression-command:` floor's attested log is refused and run exits 2 (FL4, FL8) | none (searched 'regression-command' and 'floor-declared' in tests/)
close-out-3.test.sh | §DEBT-CARD | keep | payload/scripts/close-out.sh co_debt_card: the burned count added to the touched sum, so the card prints a wrong `debt: touched N · burned M` (DEBT-CARD-2); co_deferrals carries the burned item (DEBT-CARD-7) | none (searched 'debt: touched' in tests/)
close-out-3.test.sh | §DEBT-RECARRY | keep | payload/scripts/close-out.sh co_carried_debts: the concept-and-kind match against the ledger dropped, so an inherited debt line the ledger holds is carried twice (DEBT-RECARRY-3) | none (searched 'inherited-debt' and 'co_carried_debts' in tests/)
close-out-3.test.sh | §DEBT-LINES | keep | payload/scripts/close-out.sh co_debt_refusal: the source-cell parse check dropped, so a debt.md line with a space in its source cell is carried and run exits 0 (DEBT-LINES-2) | none (searched 'co_debt_refusal' and 'source cell' in tests/)
close-out-3.test.sh | §RUNS | keep | payload/scripts/close-out.sh co_orphans: the TERM on a live detached run removed, so the orphan's process survives run (RUNS.7); the regression-runs count line (RUNS.1) | none (searched 'regression-runs: ' and 'orphan: ' in tests/)
close-out-3.test.sh | §INSERT | keep | payload/scripts/close-out.sh: the Step-8 line inserted at the end of the SDLC block instead of after the Step-7 block's last continuation line, so the step order reads 7 9 8 (INSERT.5, INSERT.11) | none (searched 'Step-8 line' and 'step_order' in tests/)
close-out-3.test.sh | §FILL | keep | payload/scripts/close-out.sh: the missing-adrs refusal before the first act dropped, so a plan with no adrs: line is closed with a `<fill:` ADR cell (FILL.13, FILL.2) | none (searched '<fill:' and 'adrs:' in tests/; close-out-2.test.sh reads the cell only in a comment)
close-out-3.test.sh | §REF | keep | payload/scripts/close-out.sh: the working branch's ref read with `git rev-parse <name>` instead of the one reader, so a tag of the branch's name covers a deleted branch and facts pass (REF-3b, REF-4) | none (searched 'facts: WOULD REFUSE' and 'ref_head' in tests/)

## close-out-4.test.sh

close-out-4.test.sh | §INHERITED-CONT | keep | payload/scripts/close-out.sh co_inherited_section: the code-fence skip dropped, so the fenced inherited: line is carried into the continuation (INH-2b); a second run adds the lines again (INH-6) | none (searched 'inherited:' and 'co_inherited_section' in tests/)
close-out-4.test.sh | §GOVERNED | keep | payload/scripts/close-out.sh co_window_start: the window opened at the approval instead of the Step-4 instant, so the record from before Step 4 governs (GOV-1b, GOV-5a) | none (searched 'governed-by: ' in tests/; close-out-2.test.sh reads only the installed line's shape)
close-out-4.test.sh | §HAND-HOLDS-KINDS | keep | hooks/poker/line.sh: an adopt re-write counted under by-hand instead of adoptions, so the line reads adoptions=0 · by-hand=1 (HK-1, HK-2) | none (searched 'adoptions=' and 'fixed=' in tests/)
close-out-4.test.sh | §FENCE | keep | payload/scripts/close-out.sh co_cont_write: an owed line appended after a section that is one fenced list instead of inside the fence (FENCE-1) | none (searched 'co_cont_write' and 'inside the fence' in tests/)
close-out-4.test.sh | §LANDS | keep | payload/scripts/close-out.sh act_lands: the open integrate and close rows not landed by row-landed, so the delivered plan reads them pending (LANDS-2, LANDS-4) | none (searched 'rows-landed' and 'act_lands' in tests/)
close-out-4.test.sh | §PARKED | keep | payload/scripts/close-out.sh: the parked arm of act_merge removed, so a parked plan's unreached working branch makes run refuse on the merge (PK-2, PK-1b) | none (searched 'delivered: parked' in tests/; handoff-file.test.sh plants that line itself)
close-out-4.test.sh | §ONE-WRITER | keep | payload/scripts/close-out.sh: the handoff document written in its own shape instead of the handoff verb's sections, so the verb's closed lines differ from close-out's (OW-2d, OW-4d) | none (searched 'ow_lines' and 'one document' in tests/)
close-out-4.test.sh | §TOLERANT | keep | payload/scripts/close-out.sh co_debt_notes: a prose line in the debt ledger refused instead of skipped with one note, so run exits 2 (TL-2) | none (searched 'prose line in the debt' in tests/)
close-out-4.test.sh | §SCORECARD | keep | payload/scripts/close-out.sh co_scorecard: the scorecard read after the wipe instead of before it, so the roster's launch is not counted and the section differs from the verb's seven lines (SC-2) | none (searched 'co_scorecard' and 'scorecard' in tests/)
close-out-4.test.sh | §APPROVED-HEAD | duplicate | the facts judge's approved-head check deleted, so a working head past the approved head closes (AH-C1) and a missing approved: release line passes (AH-C2) | canonical-sdlc-evidence-gate-2.test.sh §ORDER-VERB (unverified; full title "ORDER-VERB, §WHOLE-RUN, §FIX-ROW, §APPROVED-HEAD")
close-out-4.test.sh | §ASKS-NOTHING | keep | rule: lint — a `read -p` or a read of /dev/tty planted in payload/scripts/close-out.sh, so the sweep of its reads finds it (AN-1, AN-2) | none (searched '/dev/tty' and 'read -p' in tests/)

## cmd-class.test.sh

cmd-class.test.sh | §C0 | duplicate | payload/scripts/lib/cmd-class.sh deleted or made unparseable; hooks/bash-walls.sh made unparseable | cmd-class.test.sh §C1, bash-walls.test.sh §2
cmd-class.test.sh | §C1 | keep | payload/scripts/lib/cmd-class.sh: the runner arm's tests/ path requirement (T24) dropped, so `bash scripts/run.sh` classifies suite; ("none: bash scripts/run.sh") goes red. also: the cmd_unwrap_head rows, read nowhere else | none (searched 'scripts/run.sh' and 'cmd_unwrap_head' in tests/)
cmd-class.test.sh | §C2/C3 | duplicate | payload/scripts/lib/cmd-class.sh classification arms; walls.sh wall_farm_out_reminder's agent_type test, deny, tier-2 unwrap through sudo, FARM_OUT_ALLOW wrap and advisory downgrade each deleted | cmd-class.test.sh §C1, farm-out-reminder.test.sh §1, farm-out-reminder.test.sh §3, farm-out-reminder.test.sh §4b, farm-out-reminder.test.sh §5
cmd-class.test.sh | §C4 | keep | payload/scripts/lib/walls.sh wall_background_suite_guard: its suite-class test deleted, so a backgrounded `git status --short` from an agent of an armed session is refused; ("AC-24 …silently") goes red. also: AC-23's refusal is caught by background-suite-guard.test.sh §B7, and the three AC-24 exit-0 rows are vacuous on the deny wire | none (searched '" true)' backgrounded payloads in background-suite-guard.test.sh: every one is suite-class)
cmd-class.test.sh | §C5 | duplicate | payload/scripts/lib/walls.sh: the per-wall step-aside when cmd-class.sh will not load deleted or made to refuse; the closed walls' WANT widened to the classifier | bash-walls.test.sh §10
cmd-class.test.sh | §C6 | keep | rule: lint — a hook in payload/hooks/ gains a `$(dirname "$0")/` source, or a WANT or per-wall table basename, that resolves nowhere or outside the checkout, so the sweep's SRC_BAD names it | none (searched 'SRC_LITERALS' and 'lexnorm' in tests/)
cmd-class.test.sh | §C6 — the session never invoked the skill: neither hook is there (AC-6, AC-20) | duplicate | hooks/bash-walls.sh:231 the engagement guard deleted, so farm-out denies and audits an unengaged suite command and the compound refuses an unengaged push; payload/scripts/lib/run.sh:860 the symlink refusal deleted, so a linked marker engages | bash-walls.test.sh §1, canonical-sdlc-evidence-gate-2.test.sh §Section 34
cmd-class.test.sh | §C7 | keep | payload/scripts/lib/cmd-class.sh cmd_suite_targets: a chain answers its first suite only, so `bash tests/a.test.sh && bash tests/b.test.sh` names a.test.sh alone; (targets [bash tests/a.test.sh && …]) goes red while cross-gate-agreement-2.test.sh S13.3's single-suite round trip stays green | none (searched 'cmd_suite_targets' in tests/)

## command-relay.test.sh

command-relay.test.sh | — | — | no section | —

## commands.test.sh

commands.test.sh | §Section 1 | keep | payload/scripts/version.sh: the closing printf drops ` (installed)` or a field, so the one line no longer matches the format when run through payload/commands/version.md's own bash fence (3) | none (searched 'commands/version.md' and 'version.sh' in tests/)
commands.test.sh | §Section 2 | duplicate | payload/scripts/lib/detect.sh detect_checkout_verdict: the OTHER checkout arm returns another word; version.sh's line format | doctor-version.test.sh §Section 7, commands.test.sh §Section 1
commands.test.sh | §Section 3 | duplicate | payload/scripts/lib/detect.sh detect_checkout_verdict: the unregistered arm returns another word; version.sh's line format | detect.test.sh §LOADED — a live session's record is read before the registry (unverified), commands.test.sh §Section 1
commands.test.sh | §Section GH | keep | payload/scripts/version.sh: the case arm for the not-in-repo and registry-only states made `unknown`, so a GitHub-feed cache with a registry sha prints unknown instead of 01234567 (GH2) | none (searched 'registry-only' and '01234567' in tests/; doctor-version.test.sh §Section GH reads doctor.sh's header, not version.sh)
commands.test.sh | §Section GH-none | duplicate | payload/scripts/lib/detect.sh detect_registry_sha_lag: a sha invented when the registry records none; version.sh's own arms both fall back to unknown, so no single version.sh mutation flips GHN2 | doctor-version.test.sh §Section GH
commands.test.sh | §Section 5 | duplicate | a rendered final left stale against its template, so render.sh --check exits non-zero | render.test.sh §Section 1 (unverified)
commands.test.sh | §DECISION | keep | rule: lint — the retired name bionic:reframe planted in a shipped file under payload/, so the sweep finds it (D8b). also: D1, D2 pin the payload/skills/decision symlink | none (searched 'bionic:reframe' in tests/)
commands.test.sh | §HANDOFF | keep | payload/skills/handoff: the symlink deleted, so the plugin ships no /bionic:handoff skill (HO1, HO2); or the description field the CLI routes on loses "stepping away" (HO6b) | none (searched 'skills/handoff' in tests/)
commands.test.sh | §SITREP | keep | payload/skills/sitrep: the symlink deleted, so the plugin ships no /bionic:sitrep skill (SR1, SR2); or the description field loses "where are we" (SR6b) | none (searched 'skills/sitrep' in tests/)

## context-spend.test.sh

context-spend.test.sh | §Group 1 | keep | payload/scripts/lib/stop.sh stop_context_spend: the hook_event_name guard deleted, so a SubagentStop at a step boundary appends a line; (1b) goes red | none (searched 'context-spend' and 'SubagentStop' in tests/; stop.test.sh drives the instrument on Stop only)
context-spend.test.sh | §Group 2 | keep | payload/scripts/lib/stop.sh stop_context_spend: its engagement check deleted, so a bystander's Stop seeds a state file; (2a …and no state file was written) goes red. also: 2b's stop_hook_active guard is caught by landing-gate.test.sh §Section 1 | none (searched 'context-spend.state' in tests/; stop.test.sh §3 names this section as its catcher)
context-spend.test.sh | §Group 3 | keep | payload/scripts/lib/stop.sh stop_context_spend: the line attributed to the step entered instead of the step that ended, so it reads step-5; ("3: the line is attributed to the step that ENDED") goes red | none (searched 'context-spend step-' in tests/)
context-spend.test.sh | §Group 4 | keep | payload/scripts/lib/stop.sh stop_context_spend: the state keyed by plan alone, so a second session at a boundary takes a delta against the first session's occupancy and appends; (6) goes red | none (searched 'context-spend.state' and 're-seeds' in tests/)
context-spend.test.sh | §Group 5 | duplicate | payload/scripts/lib/stop.sh stop_context_spend writes stdout; hooks/stop.sh:194 the exit 0 after a failed bionic_context made a non-zero exit, so a payload with no or a malformed session key exits 1; every other row is a first Stop, which seeds silently whatever the program does | context-spend.test.sh §Group 3, landing-gate.test.sh §Section 11
context-spend.test.sh | §Group 6 | keep | payload/scripts/lib/stop.sh stop_context_spend: the newest-plan fallback acted on for an unbound session, so the spend across a step boundary is recorded; (13b) goes red | none (searched 'unbound_marker' and 'context-spend' in tests/)

## context.test.sh

context.test.sh | §1 | duplicate | payload/scripts/lib/context.sh: the cwd, root, engagement, run word or worktree value assigned wrong on a well-formed payload | context.test.sh §2, context.test.sh §4, bash-walls.test.sh §2, root.test.sh §10
context.test.sh | §2 | keep | payload/scripts/lib/context.sh: rung 1 tests CLAUDE_PROJECT_DIR with `-n` and drops `-d`, so a CLAUDE_PROJECT_DIR naming a missing directory wins the ladder; ("CLAUDE_PROJECT_DIR set to a non-directory falls through to the payload") goes red. also: the project half is also read by bash-walls.test.sh §12 | none (searched 'no-such-dir' in tests/)
context.test.sh | §3 | keep | payload/scripts/lib/context.sh:365 the session-id shape case deleted, so `bad/../id` returns 0 and is kept as BIONIC_SID; ("a session id carrying a path separator returns 1") goes red | none (searched 'bad/../id' in tests/; hook-adoption.test.sh §5d reads only the hooks' exit 0)
context.test.sh | §4 | keep | payload/scripts/lib/context.sh: the BIONIC_CONTEXT_WANT_RUN test made `-n` instead of `= 1`, so WANT_RUN=0 computes the verdict; ("BIONIC_CONTEXT_WANT_RUN=0 is not an ask") goes red | none (searched 'BIONIC_CONTEXT_WANT_RUN' in tests/)
context.test.sh | §5 | duplicate | payload/scripts/lib/run.sh:860 engaged_session's `[ -L "$f" ] && return 1` deleted, so a symlinked marker engages; payload/scripts/lib/context.sh returns 1 on an unengaged session, so session-start loses its bystander line | canonical-sdlc-evidence-gate-2.test.sh §Section 34, session-start.test.sh §8
context.test.sh | §6 | keep | payload/scripts/lib/context.sh:290 the `${BIONIC_INPUT+x}` adoption test made `-n`, so an empty adopted payload is re-read from stdin; ("BIONIC_INPUT set to the empty string is adopted as empty, never re-read") goes red | none (searched 'BIONIC_INPUT=' in tests/)
context.test.sh | §7 | keep | payload/scripts/lib/context.sh:291 the `[ -t 0 ]` guard deleted, so a terminal on stdin is read and the forwarded payload identifies the session; ("with stdin a terminal the payload is NOT read") goes red | none (searched 'script -q' in tests/)
context.test.sh | §8 | keep | payload/scripts/lib/context.sh bionic_jq: the `${BIONIC_INPUT-}` default dropped, so a read with BIONIC_INPUT unset under set -u aborts; ("bionic_jq with BIONIC_INPUT unset is empty") goes red, and every hook sets the variable before reading | none (searched 'bionic_jq' in tests/)
context.test.sh | §9 | keep | payload/scripts/lib/context.sh:140 the self-dir source of run.sh deleted, so context.sh sourced alone leaves engaged_session and session_run undefined while hooks that load run.sh themselves still work; ("sourcing context.sh alone defines every function") goes red | none (searched 'declare -F' and 'context.sh' in tests/)

## cross-gate-agreement-1.test.sh

cross-gate-agreement-1.test.sh | §A1 | keep | payload/scripts/lib/walls.sh evidence gate: the derived current: read off the plan's first `current:` line instead of the run.sh reader's answer, so a fenced or misplaced plan shape in the battery derives a different step at the real hook | none (searched 'run_battery' and 'verdict_eg' in tests/; run-predicate.test.sh §R2-§R5 call the reader directly and never see the hook's call)
cross-gate-agreement-1.test.sh | §A2 | duplicate | payload/scripts/lib/run.sh or lib/roots.sh: any of the seven listed rules broken in the shipped library (fence skip, marker skip, depth 2, CR translate, current anchor, docs_root head -1, quote strip), which turns the battery red with the shipped fixtures; the "applies" rows go red only when the library text moves | cross-gate-agreement-1.test.sh §A1
cross-gate-agreement-1.test.sh | §A3 | duplicate | payload/scripts/lib/walls.sh evidence gate: the numeric check on current: dropped, so `current: T4` reads as a step | canonical-sdlc-evidence-gate-2.test.sh §Section 32
cross-gate-agreement-1.test.sh | §B | keep | payload/hooks/dispatch-preflight.sh: the attestation's session_id compared by prefix instead of exactly, so a one-character-different session passes the start gate | none (searched 'one-character-different' and '%?}0' in tests/)
cross-gate-agreement-1.test.sh | §C | duplicate | payload/hooks/stop-check.sh: a typed target resolved off the metadata root or the roster's wrong row, a mistyped or =-joined flag taken as a deliverable, or the printed size apart from the machine line's (C1, C4-C6); payload/hooks/stop-guard.sh: the more-than-one-live-row arm dropped, so the gate permits the twice-rostered name (C2) | stop-check.test.sh §Section 1, stop-check.test.sh §Section 6, stop-check.test.sh §Section 7, fail-direction-table.test.sh §the ambiguity row says WHICH fault it is (T29)
cross-gate-agreement-1.test.sh | §D | keep | payload/hooks/dispatch-preflight.sh: a file written into .bionic/tmp beside the attestation and the roster row on a dispatch, so the quiet repo's find differs (the start-gate row); also a mktemp without an X-template planted in one of the five hooks. also: the LEAKS count is computed and never asserted | none (searched 'writes ONLY the attestation' and 'LEAKCANARY' in tests/)
cross-gate-agreement-1.test.sh | §E | keep | payload/hooks/stop-check.sh: with neither an argument nor a roster deliverable, the machine line's source fields left blank instead of none, so deliverable_source=none and progress_source=none go red; also an unrostered target under this session's own directory not classified ours (E3) | none (searched 'deliverable_source=none' in tests/; stop-check.test.sh §Section 8 reads the roster and args sources only)

## cross-gate-agreement-2.test.sh

cross-gate-agreement-2.test.sh | §CG | keep | hooks/poker/tick.sh sched_plan_current: the `step="${current%[ab]}"` strip deleted, so current: 3a and 3b read as no step while run_open calls them open (CG.1) | none (searched 'current%[ab]' and 'sched_plan_current' in tests/)
cross-gate-agreement-2.test.sh | §S15 | keep | payload/scripts/lib/stop.sh swept_marker_write: two fields of the landing-swept/v1 line written in another order, so the writer no longer reproduces the captured marker byte for byte (S15); readers that parse by key stay green | none (searched 'landing-swept.captured' and 'swept_marker_write' in tests/)
cross-gate-agreement-2.test.sh | §S13 | keep | rule: lint — a second reconciler of a row's files= against a --name-status diff planted in payload/scripts/lib/, so the S18.1 sweep reads 2 (S18.1); also brief_validate_fields stops de-duplicating the Suites: set (S13.2) | none (searched 'brief_validate_fields' and 's18_reconcilers' in tests/)
cross-gate-agreement-2.test.sh | §S13b | keep | payload/scripts/lib/cmd-class.sh cmd_suite_claims: a trailing `2>&1` piped to tee no longer stripped from the claimed run, so the claim differs from the run the lift stored (S13b loop) | none (searched 'cmd_runs_norm' and 'cmd_suite_claims' in tests/)
cross-gate-agreement-2.test.sh | §S13c | duplicate | hooks/dispatch-preflight.sh: the deny render keeps only the first grammar finding the library raised, so a brief with two faults names one (S13c cases); a library mutation moves both sides and leaves the agreement green | dispatch-preflight-3.test.sh §combined
cross-gate-agreement-2.test.sh | §S19 | keep | rule: lint — an unanchored doctoring site (a sed into a mutant copy with no anchor call above it) planted in tests/landing-gate.test.sh, so the site sweep counts one bare site (S19.4) | none (searched 'anchor' sites and 's19_block_sites' in tests/)

## decision-skill.test.sh

decision-skill.test.sh | §PIN | keep | rule: lint — a script, hook or other non-markdown file planted in skills/decision/, so the directory sweep lists it (17b). also: 12-16 run the suite's own predicates on doctored copies | none (searched 'skills/decision' in tests/)
decision-skill.test.sh | §REACH | prose pin | "27c: the doctored copy's plant landed" reads the skill description's wording through a copy derived from it; 27d runs the suite's own reach_ok on that copy — carried by the commit that holds skills/decision/SKILL.md | none (searched 'reach_ok' in tests/)
decision-skill.test.sh | §NUMBER | prose pin | "28b: the number-dropped copy lost the heading" and "28e: the step-heading copy carries the plant" read the skill's `**D<n> · …**` wording through derived copies; 28d and 28f run the suite's own number_ok — carried by the commit that holds skills/decision/SKILL.md | none (searched 'number_ok' in tests/)
decision-skill.test.sh | §GOAL | prose pin | "29b: the capped-goal copy carries the plant" reads the Goal sentence's wording through a derived copy; 29c runs the suite's own goal_ok — carried by the commit that holds skills/decision/SKILL.md | none (searched 'goal_ok' in tests/)
decision-skill.test.sh | §BATCH | prose pin | "30: … lets small decisions share a turn, a momentous one alone, and never says one per turn" reads the wording of the core skill, Step 2 and their templates; 31-32 run batch_ok on doctored copies — carried by the commit that holds those pages | none (searched 'batch_ok' and 'momentous' in tests/)
decision-skill.test.sh | §ALTITUDE | prose pin | "34b.<i>: the copy without clause <i> carries the plant" reads the four Altitude clauses' wording through derived copies; 34c runs the suite's own altitude2_ok — carried by the commit that holds skills/decision/SKILL.md | none (searched 'altitude2_ok' in tests/)
decision-skill.test.sh | §EXAMPLES | prose pin | "37a: the same-kind copy carries the enforced kind twice" and "38a: the moved-out copy points elsewhere" read the worked pairs' wording through derived copies; 36b-39b run the suite's own pairs_ok — carried by the commit that holds skills/decision/SKILL.md | none (searched 'pairs_ok' in tests/)
decision-skill.test.sh | §CLIMB | prose pin | "41a: the no-reframe copy lost the climb-first sentence" and "45b: …and has lost the contrast" read the Altitude section's wording through derived copies; 41c-45c run the suite's own climb_ok — carried by the commit that holds skills/decision/SKILL.md | none (searched 'climb_ok' in tests/)

## detect-probes.test.sh

detect-probes.test.sh | §Group 1 | duplicate | payload/scripts/lib/detect.sh: the file stops parsing, so every probe call fails; the three fixture-content rows read only the suite's own fixture files | detect-probes.test.sh §Group 2
detect-probes.test.sh | §Group 2 | keep | payload/scripts/lib/detect.sh detect_plugin_load_state: the block-format arm (id alone on the ❯ line, Status: beneath it) dropped, so the measured healthy listing reads bionic@bionic absent | none (searched 'detect_plugin_load_state' and 'load-state=' in tests/)
detect-probes.test.sh | §Group 2b | keep | payload/scripts/lib/detect.sh detect_plugin_load_state: the one-line rendering arm dropped, so the report's listing reads loaded as absent | none (searched 'load-state=' in tests/)
detect-probes.test.sh | §Group 3 | keep | payload/scripts/lib/detect.sh detect_plugin_load_state: an unrecognised status word mapped to loaded instead of unknown ("an unrecognized status word is unknown, never loaded") | none (searched 'load-state=unknown' in tests/)
detect-probes.test.sh | §Group 4 | keep | payload/scripts/lib/detect.sh detect_plugin_load_state: the failed arm returns non-zero, so "exit 0 even for plugin-list-dep-broken.txt" goes red | none (searched 'detect_plugin_load_state' in tests/)
detect-probes.test.sh | §Group 5 | keep | payload/scripts/lib/detect.sh detect_plugin_duplicates: the loser choice inverted, so fix= names bionic@bionic instead of the foreign copy | none (searched 'dup=' and 'claude plugin uninstall' in tests/; doctor-version.test.sh §Section 11 reads only "registered twice")
detect-probes.test.sh | §Group 6 | keep | payload/scripts/lib/detect.sh detect_plugin_duplicates: the unparseable-registry arm deleted, so a malformed registry prints nothing instead of dup=unknown | none (searched 'dup=unknown' in tests/)
detect-probes.test.sh | §Group 6b | keep | payload/scripts/lib/detect.sh detect_plugin_duplicates: the probe called directly instead of through detect_bounded, so a stalled jq wedges the caller past 10 s | none (searched 'detect_plugin_duplicates' and 'detect_bounded' in tests/)
detect-probes.test.sh | §Group 6c | keep | payload/scripts/lib/detect.sh:1045 detect_marketplace_source_path: the empty-or-null arm's return 1 made return 0, so a registry naming no entry for the resolved name exits 0 | none (searched 'detect_marketplace_source_path' in tests/; doctor-version.test.sh §Section 7 renders the path, not the status)
detect-probes.test.sh | §Group 6d | keep | payload/scripts/lib/detect.sh _detect_bound_kill: the no-group fallback signals only the direct child, so the grandchild survives the bound ("…the bound reaps its grandchild there anyway") | none (searched '_detect_bound_kill' and 'grandchild' in tests/)
detect-probes.test.sh | §Group 6d2 | keep | payload/scripts/lib/detect.sh detect_bounded: the probe's own exit code replaced by 0, so "…and its own exit code is the bound's exit code" reads 0 not 7 | none (searched 'detect_bounded' in tests/)
detect-probes.test.sh | §Group 6d3 | keep | payload/scripts/lib/detect.sh detect_bounded: the micro-sleep counter starts at 4, so the first tenth is not split and the best instant call costs 0.1 s (ceiling 0.08) | none (searched 'micro=' in tests/)
detect-probes.test.sh | §Group 6e | keep | payload/scripts/lib/detect.sh detect_auto_memory: settings.local.json no longer outranks settings.json, so "a local \"1\" over a shared \"0\" is no override" goes red | none (searched 'detect_auto_memory' and 'env:auto-memory' in tests/)
detect-probes.test.sh | §Group 6f | duplicate | payload/scripts/lib/env.sh rc_state: a stale or changed block read as yes, as detect_rc_claude_proxy passes it through | rc-item-2.test.sh §wave-27 T77, rc-item-1.test.sh §the two doors answer the same question the same way
detect-probes.test.sh | §Group 7 | vacuous | no probe in detect.sh writes to a file it reads, so the fingerprints cannot move under any mutation of a line that exists | none (searched '> "\$' in payload/scripts/lib/detect.sh's probe bodies)

## detect.test.sh

detect.test.sh | §LOADED — a live session's record is read before the registry | keep | payload/scripts/lib/detect.sh detect_checkout_verdict: the loaded record no longer read ahead of the registry, so a live session running in place reads unregistered (L2) | none (searched 'detect_checkout_verdict' and 'detect_loaded_record' in tests/; doctor-restart.test.sh drives the restart reader, not the verdict)
detect.test.sh | §LOADED — a record is not a live session's | keep | payload/scripts/lib/detect.sh detect_loaded_record: the live-session check on the asking id dropped, so a dead session's or a neighbour's record is read (L5, L8) | none (searched 'detect_loaded_record' in tests/)
detect.test.sh | §LOADED — no session id: the newest live record | keep | payload/scripts/lib/detect.sh detect_loaded_record: the no-id walk takes the newest record whatever its session, so a dead session's record is read from a terminal (L10) | none (searched 'detect_loaded_record' in tests/)
detect.test.sh | §LOADED — only a checkout is in place | keep | payload/scripts/lib/detect.sh detect_checkout_verdict: the commit= requirement for in place dropped, so a cache record reads in place (L12, L13) | none (searched 'detect_loaded_line' in tests/)
detect.test.sh | §LOADED — a link is no record | keep | payload/scripts/lib/detect.sh detect_loaded_record: the `[ ! -L ]` refusal at the record path deleted, so a link is followed (L14) | none (searched 'detect_loaded_record' and 'ln -s' in tests/detect*.test.sh tests/doctor*.test.sh)
detect.test.sh | §LOADED — the field reader | duplicate | payload/scripts/lib/detect.sh detect_loaded_field: a key misread, or an absent key answered with a value, so the in-place line loses the commit's eight or a cache record grows one | detect.test.sh §LOADED — a live session's record is read before the registry, detect.test.sh §LOADED — only a checkout is in place

## dispatch-preflight-2.test.sh

dispatch-preflight-2.test.sh | §S1 | keep | hooks/dispatch-preflight.sh: the `[ "$TOOL_NAME" = "Agent" ]` relevance check moved below the bionic_context call, so every Bash call pays the root, session and run resolution; ("relevance check precedes the context resolution") goes red. also: the behavioural rows are caught by fail-direction-table.test.sh §7 rows driven as behaviour (AC-10) | none (searched 'TOOL_NAME" = "Agent' in tests/)
dispatch-preflight-2.test.sh | §S2 | duplicate | payload/scripts/lib/root.sh: the .bionic walk from a non-git cwd deleted; hooks/dispatch-preflight.sh: the Patrol arming refusal deleted, so the non-git cwd inside a project passes | fail-direction-table.test.sh §7 rows driven as behaviour (AC-10), root.test.sh §1
dispatch-preflight-2.test.sh | §S3 | duplicate | hooks/dispatch-preflight.sh: the engagement check deleted, so an unengaged session with no Patrol stamp meets the arming wall | fail-direction-table.test.sh §7 rows driven as behaviour (AC-10), cross-gate-agreement-1.test.sh §A1
dispatch-preflight-2.test.sh | §S4 | duplicate | hooks/dispatch-preflight.sh: the exit 0 after a failed bionic_context made non-zero, so a payload with no session key is refused | fail-direction-table.test.sh §7 rows driven as behaviour (AC-10), hook-adoption.test.sh §5d
dispatch-preflight-2.test.sh | §S5 | keep | hooks/dispatch-preflight.sh: the probe-failure fix command spelled `bash hooks/preflight-probe.sh` instead of the install path, so ("a probe-failure refusal still names the install-path fix command") goes red; kept by the one-catcher rule over §S9, which runs the same line. also: the auto-probe itself is caught by fail-direction-table.test.sh §7 rows driven as behaviour (AC-10) | dispatch-preflight-2.test.sh §S9
dispatch-preflight-2.test.sh | §S6 | duplicate | hooks/dispatch-preflight.sh: the auto-probe on a missing own attestation deleted; hooks/preflight-probe.sh: a live foreign attestation pruned | fail-direction-table.test.sh §7 rows driven as behaviour (AC-10), preflight-probe.test.sh §S6b
dispatch-preflight-2.test.sh | §S6b | duplicate | hooks/dispatch-preflight.sh prints on its allow path; a gate reading one shared attestation still auto-probes and passes, so no other defect turns the rows red | dispatch-preflight-2.test.sh §S10
dispatch-preflight-2.test.sh | §S6c | duplicate | hooks/preflight-probe.sh: the legacy preflight.state prune deleted, so the slot survives the gate's auto-probe | preflight-probe.test.sh §S6b
dispatch-preflight-2.test.sh | §S7 | duplicate | hooks/dispatch-preflight.sh prints on its allow path; a positional attestation reader re-takes the record and still passes, so the reorder row cannot go red | dispatch-preflight-2.test.sh §S10
dispatch-preflight-2.test.sh | §S8 | keep | hooks/dispatch-preflight.sh: the symlink refusal on the attestation path deleted, so a link to a decoy carrying this session's id admits the dispatch; ("attestation path is a symlink -> refuse, not followed") goes red | none (searched 'decoy-attestation' in tests/; preflight-probe.test.sh §S4 drives the probe's write side)
dispatch-preflight-2.test.sh | §S9 | duplicate | hooks/dispatch-preflight.sh: the probe-failure fix command spelled repo-relative, so it exits 127 from a non-repo cwd | dispatch-preflight-2.test.sh §S5
dispatch-preflight-2.test.sh | §S10 | keep | hooks/dispatch-preflight.sh: the roster row's model= not lifted from tool_input, so ("row carries the model from tool_input") goes red | none (searched 'claude-sonnet-5-high' and 'launched_at' rows read from a gate-written roster in tests/)
dispatch-preflight-2.test.sh | §S10b | keep | payload/scripts/lib/brief.sh: a label's value span ends at the newline instead of the next label, so the compact brief's duration swallows "Progress: …"; ("compact grammar: the duration value stops at the next label") goes red | none (searched 'BRIEF_COMPACT' and 'next label' in tests/; stop-check.test.sh §8 reads only progress and cadence off its gate-written row)
dispatch-preflight-2.test.sh | §S10c | keep | hooks/dispatch-preflight.sh: the absent= field left unwritten for a near-fieldless brief, so ("the row records the duration absence") goes red | none (searched 'field "$ROW" absent' in tests/)
dispatch-preflight-2.test.sh | §S10W | keep | payload/scripts/lib/brief.sh: the Deliverable-waiver value span runs past the next label, so the roster's waiver= carries "10 minutes"; ("the waiver reason does not swallow the field after it") goes red. also: the no-deliverable refusal is caught by dispatch-preflight-3.test.sh §combined | none (searched 'roster_field "$ROW" waiver' in tests/)
dispatch-preflight-2.test.sh | §S10L | keep | payload/scripts/lib/brief.sh: the cadence label matched anywhere in the brief instead of beside the progress path, so "keep a steady cadence" lifts a cadence; ("the word 'cadence' in ordinary prose declares no cadence") goes red | none (searched 'roster_field "$ROW" cadence' in tests/)
dispatch-preflight-2.test.sh | §S10d | duplicate | hooks/dispatch-preflight.sh: the roster written with `>` instead of `>>`, so a second dispatch overwrites the first row | dispatch-preflight.test.sh §WHOLE-RUN-ADMITTED
dispatch-preflight-2.test.sh | §S10e | keep | hooks/dispatch-preflight.sh: the roster path built without the session key, so two sessions' launches land in one file; ("session A's roster holds only A's launch") goes red | none (searched 'roster.state"' in tests/; cross-gate-agreement-1.test.sh §B plants its rows by hand)
dispatch-preflight-2.test.sh | §S10f | keep | hooks/dispatch-preflight.sh: the roster prune's liveness test deleted, so a live foreign session's roster is pruned with the dead one; ("a LIVE foreign session's roster is left untouched") goes red | none (searched 'SID_DEAD' in tests/; session-sweep prunes through its own verb)
dispatch-preflight-2.test.sh | §S10g | keep | hooks/dispatch-preflight.sh: the roster append failure admitted instead of refused, so an unwritable state dir spawns an unjournalled agent; ("an unwritable state dir REFUSES the dispatch") goes red | none (searched 'Permission denied' in tests/; dispatch-preflight-4b.test.sh §RECORDER RC2 asserts only its own literal's width)

## dispatch-preflight-3.test.sh

dispatch-preflight-3.test.sh | §combined | keep | hooks/dispatch-preflight.sh: a single-fault refusal's detail rendered without its Fix: block, so rcomb4 counts 0 (the last row); also the three faults stacked as three refusals in the detail | none (searched 'Fix: ' and 'BRIEF_THREE_FAULTS' in tests/)
dispatch-preflight-3.test.sh | §scaffold-marks | keep | hooks/dispatch-preflight.sh: the Deliverable-waiver: scaffold line marked <ADD> whenever the waiver is absent, even beside a declared artifact, so (b) goes red | none (searched '<ADD>' and 'scaffold_raw_line' in tests/; dispatch-preflight-2, -4a and -4b mark other lines)
dispatch-preflight-3.test.sh | §combined-deny | keep | hooks/dispatch-preflight.sh: a lone state fault (the unarmed Patrol) refused on exit2 instead of the deny wire, so the verdict reads exit2 and stdout is empty (rcombdeny3) | none (searched 'deny wire' and 's21_stamp_path' in tests/)
dispatch-preflight-3.test.sh | §scaffold-verbatim | keep | skills/canonical-sdlc/dispatch.md: a label of the brief scaffold respelled so the wall no longer reads it, so the filled scaffold is refused (scaffold rows 58, 77, 98) | none (searched 'SCAFFOLD_SUITES' and 'scaffold' in tests/)
dispatch-preflight-3.test.sh | §a3-text | keep | hooks/dispatch-preflight.sh: the never-armed Patrol fix line names CronCreate with no CronList before it, so "Fix: CronList, then CronCreate" goes red; the fix is the only carrier of which Patrol state refused and moves with it (§a3 rows) | none (searched 'CronList' and 'stopped firing' in tests/)

## dispatch-preflight-4a.test.sh

dispatch-preflight-4a.test.sh | §S10h | keep | hooks/dispatch-preflight.sh: the file-level -L check on the roster path deleted, so the dispatch appends through the link and is allowed instead of denied | none (searched 'symlinked roster' and 'roster-${SID_A}.state' in tests/; dispatch-preflight-2.test.sh §S8 drives the directory-level links)
dispatch-preflight-4a.test.sh | §Q | keep | hooks/dispatch-preflight.sh: the Questions: set no longer held to facts_owed's dealing, so "Q2 double: an auditor with Questions: evidence, structure" is allowed | none (searched 'names no Questions' and 'deals auditor' in tests/)
dispatch-preflight-4a.test.sh | §scaffold-walk | keep | hooks/session-poker.sh proof-add review: a reader's record taken whether or not its roster row's files= lists it, so the old one-artifact brief gets both records registered (the walk2 discriminator) | none (searched 'proof-add review' in tests/; session-poker-3.test.sh not read to verdict)
dispatch-preflight-4a.test.sh | §AC-E1.3/E1.5 | keep | hooks/dispatch-preflight.sh: one refusal site (the Questions: count or the symlinked roster) printed raw instead of through lib/refuse.sh, so the sweep over this shard's refusals finds a line outside the `bionic: <verb> refused — <fact> (<fix>)` shape | none (searched 'DP_E1_BAD_SHAPE' in tests/; only this shard asserts the sweep)
dispatch-preflight-4a.test.sh | §brief-lib | keep | payload/scripts/lib/brief.sh lift_contract_fields: a Re-executes: line inside a ``` fence joins the union, so the fenced example lifts beside the real run (C2 case A) | none (searched 'lift_contract_fields' and 'fenced' in tests/; cross-gate-agreement-2, dispatch-preflight-5, landing-line-2 and stop lift unfenced briefs)

## dispatch-preflight-4b.test.sh

dispatch-preflight-4b.test.sh | §T72 | keep | hooks/dispatch-preflight.sh _dp_rec_place: the 1,024-byte bound on a record path dropped, so a 1,025-byte path counts as a record (T72-S2); also the record count disagreeing with the fact verb on a shape (T72-S1). also: 2 prose pins on the placing's comment (T72-S3) | none (searched '_dp_rec_place' and '1,025' in tests/)
dispatch-preflight-4b.test.sh | §LANDS-ON | keep | hooks/dispatch-preflight.sh: the bound-writer arm that refuses a missing Lands-on: line deleted, so w99-T23 with no Lands-on: is admitted (LO1); also `Lands-on: none` with no reason admitted (LO4) | none (searched 'Lands-on: none gives no reason' in tests/; dispatch-preflight.test.sh §LANDS-ON reads only the outside-Suites arm)
dispatch-preflight-4b.test.sh | §ROW-LABEL | keep | hooks/dispatch-preflight.sh: the check that a Row: label names a row of the bound plan deleted, so Row: T99 is admitted (RL2) | none (searched 'names no plan row' in tests/)
dispatch-preflight-4b.test.sh | §ONE-ROW | keep | hooks/dispatch-preflight.sh: the ambiguity check on a name matching two rows removed, so x-A-T1 is admitted on its first match (AN1, the AN8b mutant row) | none (searched 'matches rows' and 'is not the name' in tests/)
dispatch-preflight-4b.test.sh | §BARE | keep | payload/scripts/lib/brief.sh: the deliverable reader requires a slash, so `Expected artifact: notes.md` names no deliverable and is refused (BARE1) | none (searched 'Expected artifact: notes.md' in tests/)
dispatch-preflight-4b.test.sh | §RIGOR | duplicate | payload/scripts/lib/brief.sh: a role's dealt set at single or double changed, so the RV1 table's verdicts flip (RV1-RV4); RV5's 99 columns reads the refusal's wording, whose fact the deny verdict carries | dispatch-preflight-4a.test.sh §Q (unverified)
dispatch-preflight-4b.test.sh | §RET | keep | hooks/dispatch-preflight.sh: the retired-role arm for bionic:reviewer deleted, so the brief is refused as dealt nothing and the detail no longer says "structure is the critic's question" (RET) | none (searched 'structure is the critic' in tests/)
dispatch-preflight-4b.test.sh | §RECORDER | keep | hooks/dispatch-preflight.sh: the launch row's build failure ignored, so a dispatch whose row cannot be journalled is admitted (RC3); also the wall's deadline arm (RC5) | none (searched 'launch row that does not build' and 'RC_DEADLINE' in tests/)

## dispatch-preflight-5.test.sh

dispatch-preflight-5.test.sh | §AGREE | keep | hooks/dispatch-preflight.sh: the --admitted-before-approval export's `kind:prototype` line deleted, so ("AGREE.1 the wall exports its admitted pre-approval set: the prototype kind") goes red. also: AGREE.3 is a document pin on steps 0-2 through the suite's own grammar, and AGREE.4-4f run that grammar on doctored copies | none (searched 'admitted-before-approval' in tests/)
dispatch-preflight-5.test.sh | §PROTOTYPE | keep | hooks/dispatch-preflight.sh: the Kind: prototype admission arm before approved-by: deleted, so a confined prototype brief is refused at Step 2; (PT.1) goes red. also: PT.10 is the only driver of walls.sh's prototype-row arm | none (searched 'Kind: prototype' and 'is outside both' in tests/)
dispatch-preflight-5.test.sh | §LANDS-CMD | keep | payload/scripts/lib/suite.sh lands_cmd: the pipe character left unencoded, so the lifted lands_on= entry splits at the pipe and bionic_lands_cmd no longer gives the declared command back; (LC.1c) goes red | none (searched 'lands_cmd' and 'is not under Re-executes' in tests/)
dispatch-preflight-5.test.sh | §WAIVER-NONE | keep | payload/scripts/lib/brief.sh: the `Deliverable-waiver: none` exception deleted, so the row carries waiver=none beside its artifact; (WN.2) goes red | none (searched 'Deliverable-waiver: none' and 'waiver disregarded' in tests/)

## dispatch-preflight.test.sh

dispatch-preflight.test.sh | §CAP | keep | payload/scripts/lib/run.sh budget_cap: the source=user or source=override test dropped, so a probe's writers=1 caps and the third dispatch is refused (§CAP.u3, §CAP.1) | none (searched 'budget_cap' and 'source=probe' in tests/)
dispatch-preflight.test.sh | §CAP-USER | keep | payload/hooks/dispatch-preflight.sh: the cap's source sentence names the scale cell for a person's line, so "That cap is a person's" goes red (§CAP-USER.1c); the page is the only carrier of which source capped | none (searched 'a person' and 'writers: budget=' in tests/; scale-profile.test.sh §TASK reads the scale-cell sentence only)
dispatch-preflight.test.sh | §S22b | duplicate | payload/hooks/dispatch-preflight.sh: a row absent from a fresh live answer still counted open, so r1's dispatch is refused at budget 1 (r22ja) | dispatch-preflight.test.sh §CAP, dispatch-preflight.test.sh §S22b-nla
dispatch-preflight.test.sh | §S22b-nla | keep | payload/hooks/dispatch-preflight.sh: the no-answer fallback counts zero instead of the open roster rows, so two rows against a ceiling of 2 are admitted (r22nlb) | none (searched 'live-agents: none' and 'call ListAgents' in tests/; live-agents.test.sh reads the library alone)
dispatch-preflight.test.sh | §budget-markers | duplicate | payload/scripts/lib/roster.sh roster_open_names: an ack dated before the row's launch closes it, or a name re-dispatched after its ack stays closed (r22mke, r22mkf) | roster.test.sh §R6
dispatch-preflight.test.sh | §budget-markers-pipe | keep | payload/scripts/lib/roster.sh roster_open_names: the ledger read through a pipe whose reader quits early, so a closed name past the pipe buffer is still counted open and six thousand acked rows refuse at writers=1 (r22mkh) | none (searched 'pipe buffer' and 'roster_open_names' in tests/)
dispatch-preflight.test.sh | §budget-roster-one-pass | keep | payload/hooks/dispatch-preflight.sh: the open-name count prints the names in ledger order instead of roster order, so brc-a1's bytes differ | none (searched 'brc-a' and 'roster_open_names' in tests/)
dispatch-preflight.test.sh | §WHOLE-RUN-ADMITTED | keep | payload/scripts/lib/brief.sh lift_contract_fields: a whole-run brief's Suites: tests/run.sh lifted to a set without run.sh, so the row a second dispatch follows holds no run.sh (WA.1) | none (searched 'suites_allowed.*run.sh' in tests/dispatch-preflight-*.test.sh)
dispatch-preflight.test.sh | §LANDS-ON | keep | payload/hooks/dispatch-preflight.sh: the readers-of-Files demand applied to Lands-on, so a Lands-on within Suites is refused for reader.test.sh (LO-1) | none (searched 'lands_on' and 'is outside Suites' in tests/; dispatch-preflight-4b.test.sh holds the outside-Suites half)

## doctor-fleet.test.sh

doctor-fleet.test.sh | §Section 1 | keep | payload/scripts/doctor.sh: the RESOURCES section's machine line no longer printed, so "*core*GB*free*load*" finds nothing (1, 2); the page is the probe's only carrier | none (searched 'RESOURCES' in tests/; resources.test.sh drives the probe library, not the page)
doctor-fleet.test.sh | §Section 2 | keep | payload/scripts/doctor.sh: a version-2 attestation's budget re-derived from the probe instead of printed as recorded, so "writers=22 suites=18 worktrees=32 test_jobs=18" is gone (4) | none (searched 'writers=22' and 'attestation_v2' in tests/)
doctor-fleet.test.sh | §Section 3 | keep | payload/scripts/doctor.sh: a version-1 attestation rendered with the v2 budget arm, so it shows writers= zeroes instead of "no budget recorded" (7, 8) | none (searched 'no budget recorded' in tests/)
doctor-fleet.test.sh | §Section 4 | keep | payload/scripts/doctor.sh: the active-run row reads the newest plan instead of the run predicate, so a closed run is quoted as current: 9 (11, 12) | none (searched 'active run' in tests/; permission-answer.test.sh §A21 on and off are one reading reads only the permission-answers row's on and off)
doctor-fleet.test.sh | §Section 5 | keep | payload/scripts/doctor.sh: a MET marker counted as closing a predecessor's open row, so the count reads 1 instead of 2 (14b) | none (searched 'predecessor roster' and 'MET marker' in tests/)
doctor-fleet.test.sh | §Section 6 | keep | payload/scripts/doctor.sh: the legacy-symlink row loop over worktree_legacy_links deleted, so the mis-pointed alpha link is not listed and the row carries no repair (16, 18) | none (searched 'legacy .bionic symlink' in tests/; session-start.test.sh §5 reads the banner, another entry point)
doctor-fleet.test.sh | §Section 6b | keep | payload/scripts/doctor.sh: the attestation set read machine-wide instead of under this project, so another project's writers=99 budget reaches the page (18c, 18d) | none (searched 'writers=99' and 'attestation' in tests/)
doctor-fleet.test.sh | §Section 7 | keep | payload/scripts/doctor.sh: a predecessor or legacy-symlink row printed with its path unelided, so a line of the fullest run passes 100 columns (20) | none (searched 'fits 100 columns' in tests/ suites that run doctor on this fixture)
doctor-fleet.test.sh | §Section 8 | keep | payload/scripts/doctor.sh: the CLI-absent cause dropped from the MCP rows, so chrome-devtools no longer reads "the claude CLI is not on PATH" (21.1) | doctor-version.test.sh §Section 12 (unverified), doctor-walls.test.sh §Section 5 (unverified) (one-catcher rule: the same three rows, first in census order)

## doctor-patrol.test.sh

doctor-patrol.test.sh | §Section 1 | keep | payload/scripts/doctor.sh: the npm row's absent arm prints "not installed" instead of naming that npm is not on PATH, so T37's whole-run read of the page goes red; "1: the fallback line prints" is caught by §Section 4 and §Section 5 too | none (searched 'npm is not on PATH' in tests/)
doctor-patrol.test.sh | §Section 2 | keep | payload/scripts/doctor.sh: the singular/plural choice on the Patrol row dropped, so one open dispatch prints "1 open dispatches" (4); the other sections' `*1 open dispatch*` globs match either | none (searched 'open dispatch' in tests/)
doctor-patrol.test.sh | §Section 3 | keep | payload/scripts/doctor.sh: the duplicate-Patrol fix line names the newer job instead of the older, so "13: …names the OLDER job for deletion" goes red | none (searched 'Patrol jobs armed' and 'CronDelete' in tests/)
doctor-patrol.test.sh | §Section 4 | keep | payload/scripts/doctor.sh _patrol_flush: the stamp-and-idle-gap gate deleted, so a dead Patrol still prints ✓ session (17, 18) | none (searched 'none running' and '_patrol_flush' in tests/; patrol-stale and patrol-revive read lib/patrol.sh's fields, not the page)
doctor-patrol.test.sh | §Section 5 | keep | payload/scripts/doctor.sh: an absent stamp read as firing, so a never-armed session prints a running row (23) | none (searched 'never-armed' and 'none running' in tests/)
doctor-patrol.test.sh | §Section 7 | keep | payload/scripts/doctor.sh: present=no rendered as the number zero again, so an absent roster prints "0 open dispatches" instead of "roster absent — launches unrecorded" (27, 28) | none (searched 'roster absent' in tests/)
doctor-patrol.test.sh | §Section 8 | duplicate | payload/scripts/lib/patrol.sh: blind stops subtracting the rostered launches (32); payload/scripts/doctor.sh: the absent row gated on blind alone, so a present roster renders absent (31) | doctor-patrol.test.sh §Section 12
doctor-patrol.test.sh | §Section 9 | keep | payload/scripts/doctor.sh: under BIONIC_DOCTOR_ONLY=PATROL,PROJECT,FIXES the Patrol gather's fix line not raised, so the filtered page lacks the launches-unrostered line the whole page carries (36d); 33, 33b and 34 read source text; 36h to 36k are also caught by doctor-version.test.sh §Section 11 | none (searched 'BIONIC_DOCTOR_ONLY' in tests/; doctor-version.test.sh drives only the NATIVE filter)
doctor-patrol.test.sh | §Section 10 | keep | payload/scripts/doctor.sh: the absent row gated on present=no instead of blind > 0, so a healthy session that dispatched nothing reads "roster absent" (37, 38) | none (searched 'roster absent' and 'true zero' in tests/)
doctor-patrol.test.sh | §Section 11 | keep | payload/scripts/doctor.sh: the parse loop stops reading here= (or resolving cwd through project_root), so another project's session and its CronDelete line reach this page (41, 42) | none (searched 'here=' and 'two projects' in tests/)
doctor-patrol.test.sh | §Section 12 | keep | payload/scripts/lib/patrol.sh: agents counted over the transcript's whole life instead of from the roster's birth, so 12a earns a 4-launch fix line (76) and 12b reads 6 not 2 (78) | none (searched 'roster_window' and 'launches unrostered' in tests/)

## doctor-restart.test.sh

doctor-restart.test.sh | §Section 1 | keep | payload/scripts/doctor.sh restart row: the fix line's load time taken from somewhere other than the record's started=, so "pid … loaded hooks at 2026-08-27 14:00Z" goes red (4); the page is the only carrier of that time. also: 1 prose pin on the exit-and-restart fix line | none (searched 'loaded hooks at' and 'restart needed' in tests/)
doctor-restart.test.sh | §Section 2 | duplicate | payload/scripts/doctor.sh restart row: the manifest compare made to fire whatever the content, so an unmoved tree prints restart needed (5) | doctor-restart.test.sh §Section 5 §MANIFEST
doctor-restart.test.sh | §Section 3 | keep | payload/scripts/doctor.sh restart row: the session-file lookup for this cwd dropped, so a record with no live session file fires the row (7) | none (searched 'restart needed' and 'sessions/' in tests/doctor*.test.sh)
doctor-restart.test.sh | §Section 4 | keep | payload/scripts/doctor.sh restart row: the cwd match on the session file dropped, so a session in another directory fires this project's row (8) | none (searched 'restart needed' in tests/)
doctor-restart.test.sh | §Section 5 §MANIFEST | keep | payload/scripts/doctor.sh restart row: the content compare made an mtime compare, so a touch alone prints restart needed (MAN-1, MAN-1d) | none (searched 'restart needed' and 'changed since load' in tests/)

## doctor-version.test.sh

doctor-version.test.sh | §Section 1 | keep | payload/scripts/doctor.sh: the current arm of the version row prints the update command or a ✗, so "1: the row is a quiet checkmark" or 2 goes red | none (searched 'up to date' in tests/)
doctor-version.test.sh | §Section 2 | keep | payload/scripts/doctor.sh: the lag arm's FIX_LINES_OTHER entry dropped, so no "bionic X installed, 9.9.9 available … claude plugin update bionic@bionic" fix line (5) | none (searched 'claude plugin update bionic@bionic' in tests/)
doctor-version.test.sh | §Section 3 | duplicate | payload/scripts/doctor.sh: the directory-feed arm renders a remote compare instead of "tree matches the registered cache" | doctor-version.test.sh §Section 8, doctor-version.test.sh §Section 9
doctor-version.test.sh | §Section 4 | keep | payload/scripts/doctor.sh: the feed-kind-unknown arm prints a ✓ or "up to date" instead of "– version … unknown —" (8, 9) | none (searched '– version' and 'unknown —' in tests/)
doctor-version.test.sh | §Section 5 | keep | payload/scripts/doctor.sh: the version row's cause no longer passed through bionic_line, so the long clone path prints whole past 100 columns (13, 18); also the teardown exemption and the rc row's elision (20 to 25) | none (searched 'expect_all_lines_fit' and 'BIONIC_LINE_WIDTH' in tests/; command-relay.test.sh walls setup.sh, doctor-patrol.test.sh only Patrol rows)
doctor-version.test.sh | §Section 6 | keep | payload/scripts/lib/detect.sh detect_plugin_latest: the version-shape guard deleted, so a crafted version carries its own ✗ line onto the page (27) | none (searched 'version is not' and 'fabricated' in tests/)
doctor-version.test.sh | §Section 7 | keep | payload/scripts/doctor.sh: the unregistered arm of the plugin source line prints a path instead of "plugin source: unregistered" (31e); or the bracket verdict dropped (31, 31f) | none (searched 'plugin source:' in tests/; commands.test.sh reads version.sh's line, not doctor.sh's)
doctor-version.test.sh | §Section GH | keep | payload/scripts/doctor.sh: the header's sha read from the plugin root's git HEAD instead of the registry's gitCommitSha, so a no-.git cache prints "@ unknown" (GH1, GH2) | none (searched 'Bionic Doctor — payload' and '01234567' in tests/)
doctor-version.test.sh | §Section 8 | keep | payload/scripts/lib/detect.sh _detect_marketplace_name: the name read from installed_plugins.json's bionic@<name> key replaced by the literal bionic, so a bionic@my-fork registry reads unknown (32) | none (searched 'my-fork' in tests/)
doctor-version.test.sh | §Section 9 | keep | payload/scripts/doctor.sh: detect_registry_sha_lag called with no argument, so the row and header read the cwd's repository (34, 35, 36, 37) | none (searched 'registered build not in this tree' and 'installPath' in tests/)
doctor-version.test.sh | §Section 10 | keep | payload/scripts/doctor.sh: the ahead state rendered as lag, so an install newer than the marketplace prints an update command (38 to 42) | none (searched 'newer than the marketplace' in tests/; version-compare.test.sh drives version_compare alone)
doctor-version.test.sh | §Section 11 | keep | payload/scripts/doctor.sh: under BIONIC_DOCTOR_ONLY=NATIVE the duplicate-registration gather skipped, so the filtered page carries no duplicates row (73); or the filtered NATIVE table differs from the whole page's (66) | none (searched 'registered twice' and 'BIONIC_DOCTOR_ONLY' in tests/)
doctor-version.test.sh | §Section 12 | duplicate | payload/scripts/doctor.sh: the MCP row's CLI-absent cause dropped, or its fix line no longer elided past 100 columns | doctor-fleet.test.sh §Section 8 (unverified; rows 21.1 and 21.2 are the same pair)

## doctor-walls.test.sh

doctor-walls.test.sh | §Section 1 | duplicate | payload/scripts/lib/checks.sh bionic_check_wall_state: an intact wall reads unloadable, so the page names it; "1: …six of six" also pins the current count of walls, a tally | doctor-walls.test.sh §Section 6
doctor-walls.test.sh | §Section 2 | keep | payload/scripts/doctor.sh: the wall-library fix line drops the route read from lib/checks.sh's wall-library row, so "8: the FIX section carries the repair-phrased line" goes red | none (searched 'bionic_check_hint' and 'cannot load' in tests/)
doctor-walls.test.sh | §Section 3 | keep | payload/scripts/lib/walls.sh: cmd-class.sh dropped from farm-out-reminder's wants in the wall table, so the deleted library no longer names that wall (10) | none (searched 'farm-out-reminder*cmd-class' and 'bionic_check_wall_want' in tests/)
doctor-walls.test.sh | §Section 3b | keep | payload/scripts/lib/checks.sh: the roster stops appending permission-answer to the five walls, so a missing roster.sh draws no row (3b.1, 3b.2) | none (searched 'permission-answer' with 'cannot load' in tests/)
doctor-walls.test.sh | §Section 4 | duplicate | payload/scripts/doctor.sh: a rendered line no longer passed through the width truncation, so a long path line passes 100 columns | doctor-version.test.sh §Section 5
doctor-walls.test.sh | §Section 5 | duplicate | payload/scripts/doctor.sh: the MCP row's CLI-absent cause dropped, or its fix line no longer elided | doctor-fleet.test.sh §Section 8 (unverified; rows 21.1 and 21.2 are the same pair)
doctor-walls.test.sh | §Section 6 | keep | payload/scripts/lib/checks.sh bionic_check_wall_state: the missing arm folded into unloadable, so a deleted hook file reads unloadable instead of missing (14.10, 14.11) | none (searched 'bionic_check_wall_state' and 'not in this payload' in tests/)
doctor-walls.test.sh | §Section 7 | keep | payload/scripts/doctor.sh: the source-guard over its libraries deleted, so a payload without lib/checks.sh prints interpreter traces and no reinstall route (17.5, 17.7) | none (searched 'payload looks incomplete' in tests/)
doctor-walls.test.sh | §Section 8 | keep | payload/scripts/setup.sh: lib/checks.sh dropped from the payload guard's list, so --list on a copy without it exits 0 with an empty roster (18.4, 18.8) | none (searched 'payload looks incomplete' and 'setup.sh" --list' in tests/)

## doctor.test.sh

doctor.test.sh | §LOADED — no record: the registry's line | duplicate | payload/scripts/lib/detect.sh: the registry fallback loses the registry's sha, so version.sh's installed line and doctor's header no longer read 01234567 (LV1, LD1) | doctor-version.test.sh §Section GH (unverified), detect.test.sh §LOADED — a record is not a live session's (unverified)
doctor.test.sh | §LOADED | keep | payload/scripts/version.sh: the line built from the registry instead of detect_loaded_line, so a live record's "(in place) · C · R" is not printed (LV3); doctor.sh's header the same (LD2) | none (searched '(in place)' in tests/; detect.test.sh drives detect_loaded_line alone)
doctor.test.sh | §LOADED — a record that is not a live session's, or names no checkout | duplicate | payload/scripts/lib/detect.sh detect_loaded_line: a dead session's record or a record naming no commit read as in place (LV5, LV6, LD4) | detect.test.sh §LOADED — a record is not a live session's (unverified), detect.test.sh §LOADED — only a checkout is in place (unverified)

## door-cover.test.sh

door-cover.test.sh | §REAL | keep | rule: check pin — payload/scripts/lib/proof.sh _proof_release_path: the arm that admits tests/release-check.test.sh deleted, so the judge's cover of each real release merge, a check passing at it, reads owes, not release (r1-r3) | door-cover.test.sh §MUTANT, units.test.sh §JUDGE, units.test.sh §WALK
door-cover.test.sh | §MUTANT | keep | rule: check pin — payload/scripts/lib/proof.sh facts_cover: the cover reader admits a real release merge as release with a release-set arm removed (the check suite's or the promoted records'), which §REAL alone cannot show at the real merges without the planted mutant (m2 to m4b) | door-cover.test.sh §REAL, door-landing.test.sh §COVER

## door-landing.test.sh

door-landing.test.sh | §WORLD: the fixture carries the check's closure, the real changelog and a relative declaration | vacuous | the first of the two sections with this title, at line 54: its one assertion (w0) runs only when door_world built no fixture, a branch the suite as written never takes | none (searched 'door_world' in tests/)
door-landing.test.sh | §WORLD: the fixture carries the check's closure, the real changelog and a relative declaration | tally | "(w1b) …and larger than a pipe's buffer, 65536 bytes" pins the size of the live CHANGELOG.md and "(w6) the world is built in under two minutes" pins the machine's build time, and every other row compares the fixture builder's output with the tree it copied from; DL_DECL and DL_LIST, set in this section, are read by the two sections after it | none (searched 'door_world' and 'DOOR_NAME' in tests/)
door-landing.test.sh | §LAND | keep | hooks/poker/line.sh row_landed_scan: the declared check's run over the release range dropped (the held-by-base arm always taken), so a hand landing meets the check once and not twice (l5); also: the quitting-reader mutant of the carrier test (lm rows) is caught by release-check.test.sh §LAST | none (searched 'row_landed_scan' and 'PLAN-UNWRITTEN' in tests/)
door-landing.test.sh | §COPY | keep | rule: door refusal — payload/scripts/lib/worktree.sh _wt_release_check: `cd "$co"` made `cd "$wt_abs"`, so a piece that rewrites the declared check is judged by its own copy and publishes instead of REFUSED reason=check-failed (cdm) | none (searched '_wt_release_check' and 'check-failed' in tests/)
door-landing.test.sh | §NAMED | keep | rule: door refusal — payload/scripts/lib/worktree.sh _wt_release_check: the judged-by arm deleted (nm1), or changed-here read over the writer's head instead of the candidate (nm2), so a landing that changes the check which judges it is refused with the advice to fix it on its own branch and no judge named | none (searched 'judged-by=' and 'changed-here=' in tests/)
door-landing.test.sh | §JUDGED | keep | hooks/poker/line.sh poker_verb_row_landed: the judged-by field dropped from the hand line, so a person's merge of a fix to the check is marked with no word that the landed copy judged it (j2) | none (searched 'judged-by=candidate' in tests/)
door-landing.test.sh | §HAND | keep | rule: door refusal — payload/scripts/lib/line.sh line_publish: the _wt_release_check call deleted, so a planted listed name lands by hand instead of REFUSED reason=check-failed (hm1) | none (searched 'DOOR_MUTANT_FN' and 'line_publish' mutants in tests/)
door-landing.test.sh | §COVER | keep | payload/scripts/lib/proof.sh proof_door_cover: the loop that names each path outside the release set deleted, so the release row's landing prints `COVER T2 <merge> owes` with no outside path (v2) | none (searched 'proof_door_cover' in tests/)

## engage.test.sh

engage.test.sh | §E0 | keep | hooks/engage.sh loses its exec bit, so ("engage.sh carries the exec bit") goes red; every suite drives it through `bash`. also: the parse row is caught by §E1 | none (searched 'exec bit' and 'test -x' in tests/)
engage.test.sh | §E1 (AC-1) | keep | hooks/engage.sh: the marker written without plan= naming the root's one open plan, so ("the marker names the open plan") goes red | none (searched 'engage.sh' and 'plan=' marker reads in tests/; the other suites plant markers by hand)
engage.test.sh | §E2 (AC-2) | keep | hooks/engage.sh: the skill-name match unanchored at its end, so `canonical-sdlc-v2` engages the session; ("the near-miss skill name [canonical-sdlc-v2] writes NO marker") goes red | none (searched 'canonical-sdlc-v2' in tests/)
engage.test.sh | §E3 (AC-3) | keep | hooks/engage.sh: the UserPromptExpansion command_name branch deleted, so a typed /bionic:canonical-sdlc engages nothing; ("…and engages the session") goes red | none (searched 'UserPromptExpansion' in tests/)
engage.test.sh | §E4 (AC-4) | duplicate | payload/scripts/lib/run.sh:850-851 the unknown and shape refusals deleted; run.sh:860-861 the symlink refusal deleted or `-f` made `-e`; payload/scripts/lib/binding.sh: the write-side symlink refusal deleted | run-predicate.test.sh §R7, canonical-sdlc-evidence-gate-2.test.sh §Section 34, binding.test.sh §2
engage.test.sh | §E5 (AC-17) | keep | hooks/hooks.json: the UserPromptExpansion registration of engage.sh deleted, so a typed command never reaches the hook; ("hooks.json registers engage.sh on UserPromptExpansion") goes red. also: the loader-block row is caught by hook-adoption.test.sh §1, and "registered exactly twice" is a tally of hooks.json | none (searched 'UserPromptExpansion' and 'engage.sh' in tests/)
engage.test.sh | §E6 (AC-18) | keep | hooks/engage.sh: the `.bionic/.gitignore` written as `*` on tree creation deleted, so a fresh project's state tree is committable; ("…and .bionic/.gitignore is exactly '*'") goes red | none (searched 'gitignore is exactly' in tests/)
engage.test.sh | §E7 | duplicate | payload/scripts/lib/session.sh: the payload id taken over the environment id, so the marker is keyed to the witness; the no-sid and non-JSON rows hold on any program, since engaged_marker_path refuses an empty key | session-start.test.sh §4
engage.test.sh | §E8 (wave-session-bound-run, AC-7/AC-8/AC-9) | keep | payload/scripts/lib/binding.sh bind_plan: the existing engaged_at read dropped, so a rewrite stamps a fresh time; ("a rewrite preserves the existing engaged_at") goes red. also: the five refusals are caught by binding.test.sh §2 | none (searched 'engaged_at' preservation rows in tests/)
engage.test.sh | §E9 (AC-7) | keep | hooks/engage.sh: the leave-an-existing-binding arm deleted, so re-engagement re-runs the count rule and drops a live binding; ("…and the ORIGINAL binding is preserved, not the newest plan") goes red | none (searched 're-engag' and 'session_plan' in tests/)

## env.test.sh

env.test.sh | §Group 1 | keep | payload/scripts/remove.sh: RM_ENV_KEYS loses CLAUDE_CODE_DISABLE_AUTO_MEMORY, so remove's standalone door leaves a name setup wrote and "remove.sh's RM_ENV_KEYS is byte-equal to env.sh's ENV_KEYS" goes red; or env_default's auto-memory value changed from 1. also: "ENV_KEYS is exactly the four names" pins the live roster, a tally | none (searched 'RM_ENV_KEYS' and 'env_default' in tests/)
env.test.sh | §Group 2 | keep | payload/scripts/lib/env.sh env_set: the jq program assigns .env instead of merging into it, so the foreign OTHER name is lost ("…the foreign env name is untouched") | none (searched 'env_set' in tests/)
env.test.sh | §Group 3 | keep | payload/scripts/lib/env.sh env_set: the no-file arm returns an error instead of creating settings.json ("env_set on a machine with no settings file creates it") | none (searched 'env_set' in tests/)
env.test.sh | §Group 4 | keep | payload/scripts/lib/env.sh env_get: falls back to the process environment, so "a name live in the process is still absent from the file" goes red | none (searched 'env_get' in tests/)
env.test.sh | §Group 5 | keep | payload/scripts/lib/env.sh env_unset: the delete of an emptied env object dropped, so `"env": {}` is left behind ("the env object is deleted once bionic's last name leaves it") | none (searched 'env_unset' in tests/)
env.test.sh | §Group 6 | keep | payload/scripts/lib/env.sh env_live: a set-but-empty name read as absent, so "a name exported empty is live" goes red | none (searched 'env_live' in tests/)
env.test.sh | §Group 7 | keep | payload/scripts/lib/deps.sh _dep_settings_write_jq: the chmod back to the file's own mode dropped, so a 0600 settings.json comes back 0644; or the write renames over the link instead of its target | none (searched '_dep_settings_write_jq' in tests/)
env.test.sh | §Group 8 | keep | rule: lint — a second reader of .env (`.env.` or `.env[` in a jq of its own) planted in setup.sh or doctor.sh, so the sweep finds it | none (searched '\.env\[' and 'env_set' in tests/)

## execution-recorder.test.sh

execution-recorder.test.sh | §Section 1 | keep | hooks/execution-recorder.sh: the Bash early exit moved below the STATE_DIR resolution, so every unrelated Bash call pays for the state paths and the roster read ("the early exit PRECEDES the state paths…") | none (searched 'IS_START' and 'STATE_DIR=' in tests/)
execution-recorder.test.sh | §Sections 2-5 | vacuous | a setup_section tombstone for the deleted observation record: it builds nothing a later section reads and asserts nothing | none (searched 'Sections 2-5' in tests/)
execution-recorder.test.sh | §Section 6 | keep | hooks/execution-recorder.sh: the teammate arm writes the addressing id into agent_id instead of teammate_id, so "agent_id stays EMPTY — a confirmed row never carries a wrong-namespace id" goes red | none (searched 'teammate_spawned' and 'teammate_id=' in tests/; cross-gate-agreement.prelude.sh drives the shape but was not read to its verdict)
execution-recorder.test.sh | §Section 7 | keep | hooks/execution-recorder.sh: the -L check on the roster file deleted, so a symlinked roster is appended through and the victim gains status=confirmed | none (searched 'symlinked ROSTER' and 'execution-recorder.sh' in tests/)
execution-recorder.test.sh | §Section 8 | keep | hooks/execution-recorder.sh: the payload parse's fail-open exit dropped, so 'not json at all' exits non-zero from a PostToolUse hook | none (searched 'not json' with 'execution-recorder' in tests/)
execution-recorder.test.sh | §Section 9 | keep | hooks/execution-recorder.sh: the agent id sanitized for the pipe character alone, not newlines, so a newline in the id splits the roster row ("…the id is normalized into the row instead") | none (searched 'ROSTER_ROW_SCHEMA' with 'aevil' in tests/)

## fail-direction-table.test.sh

fail-direction-table.test.sh | §7 rows driven as behaviour (AC-10) | keep | hooks/dispatch-preflight.sh: a non-git cwd resolved by the git-toplevel precondition again, so a non-git cwd inside a project with an open run is open and silent instead of reaching the arming wall (start/non-git-cwd-with-bionic) | none (searched 'non-git-cwd-with-bionic' in tests/)
fail-direction-table.test.sh | §the ambiguity row says WHICH fault it is (T29) | keep | hooks/stop-guard.sh: two live rows for one target refused for want of an observation instead of for the ambiguity, so the refusal no longer says "more than one live row" | cross-gate-agreement-1.test.sh §C (unverified) (reopened by the merge: every named catcher is culled, so it keeps its defect)
fail-direction-table.test.sh | §the missing session key | duplicate | hooks/dispatch-preflight.sh: a keyless payload refused or announced at the start gate | fail-direction-table.test.sh §7 rows driven as behaviour (AC-10)
fail-direction-table.test.sh | §the producer's two rows (§7 rows 4 and 5) | duplicate | hooks/preflight-probe.sh: the no-session-key refusal (exit 3) lost, or an attestation written after a failing blocking probe | preflight-probe.test.sh §S3 (unverified), preflight-probe.test.sh §S2 (unverified)

## farm-out-reminder.test.sh

farm-out-reminder.test.sh | §0 | duplicate | payload/scripts/lib/walls.sh wall_farm_out_reminder: the tier-1 deny deleted, or the hook missing at the seam | farm-out-reminder.test.sh §3
farm-out-reminder.test.sh | §1 | keep | payload/scripts/lib/walls.sh:4865 wall_farm_out_reminder's TOOL_NAME = Bash test deleted, so a Read payload carrying `bash tests/run.sh` is denied; (1a) goes red while bash-walls.test.sh §1 1d asks about `ls -la`, which no wall refuses | none (searched 'non-Bash payload' in tests/)
farm-out-reminder.test.sh | §2 | keep | hooks/bash-walls.sh:231 the engagement guard deleted, so a bystander's suite command is denied and audited | bash-walls.test.sh §1 (reopened by the merge: every named catcher is culled, so it keeps its defect)
farm-out-reminder.test.sh | §3 | keep | payload/scripts/lib/walls.sh wall_farm_out_reminder: the class-keyed role names test-runner for every class, so an install-class deny redirects to the test-runner; (3k) goes red | none (searched 'subagent_type: implementor' in tests/)
farm-out-reminder.test.sh | §4 | keep | payload/scripts/lib/walls.sh wall_farm_out_reminder: the nudge-once state keyed by class alone, so a second session's first docker run is suppressed; (4l) goes red | none (searched 'farm-out.state' and 'second session gets its own first nudge' in tests/)
farm-out-reminder.test.sh | §4b | keep | payload/scripts/lib/walls.sh wall_farm_out_reminder: the case fold of the head word removed, so `GIT clone` draws no clone nudge; (4z) goes red | none (searched 'GIT clone' in tests/)
farm-out-reminder.test.sh | §5 | keep | payload/scripts/lib/walls.sh wall_farm_out_reminder: the farm-out-mode: off arm deleted, so a suite command under off is denied; (5h) goes red. also: 5d advisory is caught by cmd-class.test.sh §C2/C3 | none (searched 'farm-out-mode: off' in tests/)
farm-out-reminder.test.sh | §SHORT | keep | payload/scripts/lib/walls.sh wall_farm_out_reminder: the short-timeout pass deleted, so a one-file suite call with timeout 60000 is denied instead of wrapped with --kill-after 55; (S1b) goes red | none (searched 'kill-after' in tests/; gate.test.sh and slots.test.sh drive booked.sh's flag, not the wall)
farm-out-reminder.test.sh | §CHAIN-NL | keep | payload/scripts/lib/walls.sh wall_farm_out_reminder: the whole-raw-command fallback when no flattened segment classifies deleted, so a suite on the line after a 3-segment chain is not refused; (NL3) goes red | none (searched 'class=chain' in tests/)
farm-out-reminder.test.sh | §6 | keep | payload/scripts/lib/walls.sh wall_farm_out_reminder: the token redaction on the deny reason deleted, so a --token= value reaches the wire; (6f) goes red | none (searched 'REDACTED' in tests/)

## fold.test.sh

fold.test.sh | §1 | keep | payload/scripts/lib/fold.sh prints or exits non-zero when no function spoke | bash-walls.test.sh §1 (reopened by the merge: every named catcher is culled, so it keeps its defect)
fold.test.sh | §2 | duplicate | payload/scripts/lib/fold.sh: the composition keeps the first blocker alone, so the second blocker's reason and line are lost | bash-walls.test.sh §3
fold.test.sh | §3 | keep | payload/scripts/lib/fold.sh: advisories rendered ahead of the refusal on the user stream | bash-walls.test.sh §8 (reopened by the merge: every named catcher is culled, so it keeps its defect)
fold.test.sh | §4 | duplicate | payload/scripts/lib/fold.sh: the loop stops at the first blocker, so a later blocker never stages | bash-walls.test.sh §3
fold.test.sh | §5 | duplicate | payload/scripts/lib/fold.sh: each function run in a subshell, so staged verdicts and state are lost and no block composes | bash-walls.test.sh §3
fold.test.sh | §6 | duplicate | payload/scripts/lib/fold.sh: each function run in a subshell, so an exit returns and no staged block survives; no other change to the fold moves 6a or 6b | bash-walls.test.sh §3
fold.test.sh | §7 | keep | payload/scripts/lib/fold.sh: the verdict read from staged text instead of the function's return code, so a function that stages a block and returns 0 blocks; (7a) goes red | none (searched 'STAGED-BUT-UNCLAIMED' and 'fold_block' stubs in tests/; no shipped wall stages and returns 0)
fold.test.sh | §8 | duplicate | payload/scripts/lib/fold.sh: the process status forced to 2 for a lone block-channel blocker, so a Stop refusal on the block channel exits 2 instead of 0 | patrol-duties-gate.test.sh §Section 1, patrol-revive.test.sh §Group 7
fold.test.sh | §9 | keep | payload/scripts/lib/fold.sh: the composed verdict rides the first blocker's channel instead of the first whose model_only cell says yes | bash-walls.test.sh §6 (reopened by the merge: every named catcher is culled, so it keeps its defect)
fold.test.sh | §10 | keep | payload/scripts/lib/fold.sh: staged advisories printed in reverse, so ("10e: …in the order the functions were named") goes red | none (searched 'fold_advise' in tests/; no driven hook stages two user advisories on one event)
fold.test.sh | §11 | keep | payload/scripts/lib/fold.sh: the event dropped from each function's call, so ("11a: the event reaches the function verbatim") goes red | none (searched 'NotAnEventAnyoneRegistered' and 'fold' drivers in tests/)
fold.test.sh | §12 | keep | payload/scripts/lib/fold.sh fold_context: the accumulator overwritten by each speaker instead of joined, so two model-facing advisories keep only the second; ("12f: …carrying the first speaker's text") goes red. also: 12n-12p are caught by bash-walls.test.sh §4 | none (searched 'fold_context' in tests/; production has one emitter)
fold.test.sh | §13 | keep | payload/scripts/lib/fold.sh: the extra-lines branch not standing down under BIONIC_WALL_VERBOSE=1, so the second exit2 blocker's sentence prints twice; (13k) goes red. also: 13a-13f2 are caught by bash-walls.test.sh §3 | none (searched 'BIONIC_WALL_VERBOSE=1' with two blockers in tests/)
fold.test.sh | §14 | keep | payload/scripts/lib/fold.sh: the stderr capture made by the shell's `2>` at a pid-and-RANDOM name instead of mktemp, so a planted symlink at that name is truncated; (14c) goes red | none (searched 'bionic-fold' in tests/; bash-walls.test.sh §11 owns the gate's own staging file)
fold.test.sh | §15 | keep | payload/scripts/lib/fold.sh: the mktemp-failure fallback sends the render's stdout to /dev/null, so a deny under an unwritable TMPDIR carries no JSON; (15d) goes red | none (searched 'TMPDIR=/nonexistent' and 'fold-t71' in tests/)

## framework.test.sh

framework.test.sh | §1 | keep | tests/lib/assert.sh finish: the section floor deleted, so a section that asserts nothing passes and p-empty exits 0 | none (searched 'section asserted nothing' in tests/)
framework.test.sh | §2 | keep | tests/lib/assert.sh setup_section: counted as a section, so the tally reads sections=2 setup=0 | none (searched 'setup=' in tests/)
framework.test.sh | §3 | keep | tests/lib/assert.sh: the called-but-undefined derivation at load deleted, so p-undefined runs to its own tally (3) | none (searched 'helper called but never defined' in tests/)
framework.test.sh | §4 | keep | tests/lib/assert.sh: the derivation's heredoc-body skip deleted, so a helper name inside a heredoc refuses p-heredoc at load (4) | none (searched 'p-heredoc' and 'heredoc body' in tests/)
framework.test.sh | §5 | keep | tests/lib/assert.sh finish: the exit made 0 whatever FAIL holds, so a suite with a failing row exits 0 (5) | none (searched 'finish' exit checks in tests/framework.test.sh and tests/run*.test.sh)
framework.test.sh | §6 | keep | tests/lib/assert.sh ok: the TF_ROW_GUARD arm deleted, so a row under a speaking guard passes and p-guard tallies 5/5 (6g) | none (searched 'TF_ROW_GUARD' in tests/)
framework.test.sh | §6b | keep | rule: lint — a private ok() or no() definition planted in a tests/*.test.sh suite, so _tf_adoption_refusal names it and the refused count is 1. also: 3 prose pins on the docblock | none (searched '_tf_adoption_refusal' in tests/)
framework.test.sh | §8 | prose pin | "8: the header points at the live width knob" and its two siblings read the wording of tests/run.sh's header comment — carried by the commit that holds tests/run.sh | none (searched 'BIONIC_TEST_JOBS_CEILING` is there' in tests/)
framework.test.sh | §9 | keep | tests/lib/assert.sh expect_true: the command's output no longer sent to /dev/null, so NOISE-ON-STDOUT reaches the suite output (9). also: 3 prose pins on the mapping table | none (searched 'NOISE-ON-STDOUT' in tests/)
framework.test.sh | §10 | keep | tests/lib/assert.sh expect_regex: implemented as a printf piped into grep -qE, so a value past the pipe buffer reports no match (10, the large value); also rule: lint — a producer-into-grep -q planted in assert.sh's code. also: PIPE_SMALL and PIPE_BIG measure bash and grep only | none (searched 'expect_regex' and 'F10_BANNED' in tests/)
framework.test.sh | §PIN-REL | prose pin | "PIN-REL the shipped file states the ban" reads the wording of assert.sh's comments — carried by the commit that holds tests/lib/assert.sh; the two copy rows run the suite's own f10_stated and f10_code_hits on doctored copies | none (searched 'f10_stated' in tests/)

## fresh-home.test.sh

fresh-home.test.sh | §Group 1 | keep | payload/scripts/doctor.sh: DOCTOR_NIL given DOCTOR_OK's glyph, so doctor's present and absent rows read alike; ("the OK and NIL verdict glyphs are different characters") goes red. also: the file-exists rows are caught by §Group 2 and the suites that run doctor.sh and remove.sh, the package-map rows pin current deps.sh values, and the empty-HOME and zsh -n rows read only the suite's own fixture | none (searched 'DOCTOR_OK' in tests/)
fresh-home.test.sh | §Group 2 | keep | payload/scripts/setup.sh: the `claude plugin install bionic@bionic` step of --all deleted, so ("the plugin install reached the CLI") goes red while principles-item and rc-item-1, which also run setup --all, read only their own items | none (searched 'plugin install bionic@bionic' in tests/; doctor-walls and loader name it in a fix line, not as setup's call)

## gate.test.sh

gate.test.sh | §SHARE | keep | payload/scripts/lib/gate.sh gate_share: a project's .bionic/config.yaml share: read ahead of the machine's share file, so project A reads 90 and the ask at 55 is admitted (S.3, S.5) | none (searched 'gate_share' and 'bionic/share' in tests/; the other suites plant a share and never a project line)
gate.test.sh | §WIDTH | keep | payload/scripts/lib/gate.sh gate_width: the floor of 1 dropped, so share 1 on 8 cores answers 0 (WD.4); also the core count taken as 8, so 64 cores answers 7 (WD.5) | none (searched 'gate_width' in tests/; runner-width.test.sh §Section 6 reads 8 cores at shares 92 and 50 only)
gate.test.sh | §WIDTH-ASK | keep | payload/scripts/lib/gate.sh gate_width_ask: the oldest-landing rule dropped, so the younger LB is answered by the count while LA is active (WA.6, WA.9) | none (searched 'gate_width_ask' in tests/; landing-line-1.test.sh and landing-line-2.test.sh replace it with a stub)
gate.test.sh | §LEASE | keep | payload/scripts/lib/gate.sh gate_width_ask: the lease file unread, so LB is answered 4 in LA's gap between runs (LE.4, LE.27) | none (searched 'gate_landing_open' and 'leases/' in tests/)
gate.test.sh | §HARD | keep | payload/scripts/lib/gate.sh: the memory ceiling `fits(u, share)` made `fits(u, 100)`, so 85% used under a share of 80 is admitted (H.1, H.11) | none (searched 'fits(u, share)' and 'BIONIC_PROBE_USED_PCT' in tests/)
gate.test.sh | §NOCONST | keep | payload/scripts/lib/gate.sh: the admission room's core count taken as 8 instead of the probe's, so the 6-core machine's third ask is refused (C.1) | none (searched 'BIONIC_PROBE_CORES' with gate_ask in tests/; §HARD and §TWO run on 8 cores)
gate.test.sh | §TWO | keep | payload/scripts/lib/gate.sh _gate_steal: a lock with no pid never taken over past its bound, so the ask is undecided (T.8) | none (searched 'lock/pid' and '_gate_steal' in tests/)
gate.test.sh | §NUMBER | keep | payload/scripts/lib/gate.sh gate_ask: the resume of a handed-back request by the same who and key dropped, so the re-ask takes a fresh number and the later one is served first (N.9, N.11) | none (searched 'asked=' and 'resumed' in tests/gate.test.sh tests/booked.test.sh tests/slots.test.sh)
gate.test.sh | §RESUME-KIND | keep | payload/scripts/lib/gate.sh gate_ask: the `[ "$_R_kind" = "$1" ]` test on resume deleted, so a work ask resumes the cleared whole request (N.12j, N.12s) | none (searched 'rc=gone' and '_R_kind' in tests/)
gate.test.sh | §TERM | keep | payload/scripts/lib/gate.sh gate_ask: the `trap '_GATE_TERMED=1' TERM` line deleted, so a TERMed waiter's next ask ends it rc=gone and takes a fresh number (TM.3, TM.7) | none (searched '_GATE_TERMED' in tests/)

## git-argv.test.sh

git-argv.test.sh | §Section 1 | keep | payload/scripts/lib/git-argv.sh git_argv_segments: an operator inside double quotes taken as a segment boundary, so `echo "a && b"` splits in two | none (searched 'git_argv_segments' in tests/)
git-argv.test.sh | §Section 1d | duplicate | payload/scripts/lib/git-argv.sh or payload/scripts/lib/cmd-class.sh: one library's heredoc terminator rule changed, so the two read a heredoc body differently | git-argv.test.sh §Section 1, cmd-class.test.sh §C2/C3 (unverified)
git-argv.test.sh | §Section 1b | keep | payload/scripts/lib/git-argv.sh: the global-option skip loses `-C <dir>`'s argument, so `git -C dir commit` reads subcommand dir | none (searched 'GIT_SUB' and 'global option' in tests/)
git-argv.test.sh | §Section 1e | keep | payload/scripts/lib/git-argv.sh: GIT_ARGV_ENV_CHDIR not set from `env -C <dir>`, so the evidence gate loses the directory (1e rows) | none (searched 'GIT_ARGV_ENV_CHDIR' in tests/)
git-argv.test.sh | §Section 1f | keep | payload/scripts/lib/git-argv.sh git_argv_has_any_sub: the loop returns after the first segment, so a verb in a later segment answers no | none (searched 'git_argv_has_any_sub' in tests/)
git-argv.test.sh | §Section 1g | keep | payload/scripts/lib/git-argv.sh: the program word read before quote removal, so a quoted program word is misread (1g rows) | none (searched 'read as the machine resolves it' and 'git_argv' in tests/)
git-argv.test.sh | §Section 1h | keep | payload/scripts/lib/git-argv.sh: the prefix-word skip matches sudo case-sensitively, so `SUDO git push origin main` is not a push (1h, its mutant row) | none (searched 'SUDO git push' in tests/)
git-argv.test.sh | §Section 1c | keep | payload/scripts/lib/git-argv.sh git_push_targets: a `+refspec` no longer reported as force (1c force rows) | none (searched 'git_push_targets' in tests/)
git-argv.test.sh | §Section 2 | keep | hooks/bash-walls.sh loader_fail_closed: the detail drops the candidate paths it looked in, so the refusal no longer names the library path (the naming-the-path rows, both layouts) | none (searched 'renamed away' and 'Looked in' in tests/; bash-walls.test.sh §9 reads the exit only)
git-argv.test.sh | §Section 3 | keep | rule: lint — a hook source line naming a library path that is not hook-relative or not in the shipped tree, planted in hooks/, so the sweep reports it | none (searched 'hook-relative' in tests/)
git-argv.test.sh | §Section 4 | keep | payload/scripts/lib/walls.sh wall_evidence_gate: IS_COMMIT read from the raw command instead of git_argv, so `git -C . commit` and `git -c x=y commit` pass the gate silently | none (searched 'gate_fires' and 'global-option commit' in tests/)
git-argv.test.sh | §Section 4b | keep | payload/scripts/lib/git-argv.sh git_argv_expand: a `-c` string's command not expanded, so the push inside `bash -c "git push"` is missed (has_push rows) | none (searched 'git_argv_expand' in tests/)
git-argv.test.sh | §Section 5 | keep | payload/scripts/lib/git-argv.sh git_branch_protected: the master arm deleted, so master answers no | none (searched 'git_branch_protected' in tests/)
git-argv.test.sh | §Section 6 | keep | payload/scripts/lib/walls.sh _wall_mentions_git: a recognised form (env-prefixed or quoted git) screened out, so the screen short-circuits before the parser for that fixture | none (searched '_wall_mentions_git' in tests/; bash-walls.test.sh §2 drives only the backslash-newline form)

## grant.test.sh

grant.test.sh | §G0 purity | keep | payload/scripts/lib/grant.sh grant_reserved: a credential shape read against $HOME instead of by its own form, so the same command is reserved under one HOME and not another; (G0.5) goes red. also: G0.11 sweeps the lib's own function bodies | none (searched 'grant_reserved' in tests/; permission-answer.test.sh drives the hook under one HOME)
grant.test.sh | §G1 a writer inside its recorded tree is allowed; a sibling or the main checkout is not | keep | payload/scripts/lib/grant.sh grant_decide: containment tested as a string prefix instead of by path components, so /x/25-T1 contains /x/25-T10/f; (G1.4) goes red | none (searched '25-T10' and 'T1-old' in tests/)
grant.test.sh | §G2 the lead is allowed inside what the run created, and nowhere else | keep | payload/scripts/lib/grant.sh grant_roots: the lead given every tree under .worktrees instead of the trees this session recorded, so another session's tree allows; (G2.6) goes red | none (searched 'grant_roots' in tests/)
grant.test.sh | §G3 a read-only agent has the scratch and its declared report | keep | payload/scripts/lib/grant.sh grant_decide: the report fact granted as a root rather than as one file, so a file beside it allows; (G3.9) goes red | none (searched 'REPORT.bak' and 'grant_decide reader' in tests/)
grant.test.sh | §G4 the record is add-only for agents; the lead may delete there | keep | payload/scripts/lib/grant.sh grant_decide: the record's add-only rule deleted, so a writer's delete under the record dir allows; (G4.2) goes red | none (searched 'not delete' in tests/)
grant.test.sh | §G5 a path that resolves outside is outside | keep | payload/scripts/lib/grant.sh grant_resolve: a relative symlink not followed, so tree/out/f resolves inside the tree; (G5.3) goes red | none (searched 'grant_resolve' in tests/; permission-effects.test.sh resolves one plain path)
grant.test.sh | §G6 bionic's own state files are in no grant, the lead's included | keep | payload/scripts/lib/grant.sh grant_decide: the state-file rule deleted, so a lead whose checkout holds .bionic/tmp writes a roster; (G6.lead.roster) goes red | none (searched "bionic's own state" in tests/)
grant.test.sh | §G7 every deny-fix carries the target or reason, the roots and one next step | keep | payload/scripts/lib/grant.sh grant_decide: the deny-fix reason built without the asker's roots, so ("G7.outside-write.2 the message names the root …") goes red; the verdict line is the only carrier of which roots the asker holds | none (searched 'grant_decide' in tests/)
grant.test.sh | §G8 a reserved action is never allowed; a table miss is denied with a fix | keep | payload/scripts/lib/grant.sh grant_reserved: the command matched as raw text instead of as dequoted words, so a push spelled g'i't p"u"sh is not reserved; (G8.obf1) goes red | none (searched 'grant_reserved' and 'leaves-the-machine' in tests/; permission-answer.test.sh drives plain spellings)
grant.test.sh | §G9 a reserved denial names the category and the human, and carries no file route | duplicate | payload/scripts/lib/grant.sh grant_decide: a reserved action not decided deny-reserved with its category in field 2 (G9.0); the "human" and "report it to the lead" rows read the same words for every category, a prose pin carried by field 2 | grant.test.sh §G8 a reserved action is never allowed; a table miss is denied with a fix
grant.test.sh | §G10 the answer log is in no workspace | keep | payload/scripts/lib/grant.sh grant_decide: the answer-log exclusion deleted, so a lead whose checkout is the main checkout may write the log under .bionic; (G10.main) goes red | none (searched 'permission-answers.log' in tests/)
grant.test.sh | §G11 the project's shared directories are no checkout's, and the main root is no one's to delete | keep | payload/scripts/lib/grant.sh grant_decide: the main-root shared-directory rule deleted, so a lead in the main checkout deletes .bionic/docs/x; (G11.3) goes red | none (searched 'main=' facts in tests/)
grant.test.sh | §G12 a write to a device sink is no effect; a delete of one, or any other device, is judged | keep | payload/scripts/lib/grant.sh grant_decide: the device-sink exemption applied to D lines too, so a delete of /dev/null allows; (G12.lead.4) goes red | none (searched 'W /dev/null' effect lines in tests/)
grant.test.sh | §G13 a delete outside the delete roots | keep | payload/scripts/lib/grant.sh grant_decide: rule 6's fix names the lead for the lead class too, so the lead is not sent to the human; ("G13.lead.2 …and the fix sends it to the human") goes red, and the fix field is the only carrier of who is next | none (searched 'report it to the human' in tests/)
grant.test.sh | §G14 which program a word runs is the shared reader's; a match made to refuse stays case-blind | keep | payload/scripts/lib/grant.sh grant_reserved: the program word compared case-sensitively, so GH pr create is not reserved; the G14.prog row for a capitalised program goes red | none (searched 'grant_reserved' in tests/)
grant.test.sh | §G15 every fix line sends the asker to the one above its own class | keep | payload/scripts/lib/grant.sh grant_decide: the outside-write arm's fix names the asker's own class instead of the one above, so ("G15 … the fix sends it to the lead") goes red for a writer; §G13 reads only the delete arm | none (searched 'fld 3' escalation rows in tests/)
grant.test.sh | §G16 every common credential store is refused by any spelling of its path | keep | payload/scripts/lib/grant.sh grant_reserved: one store dropped from the credential table (~/.gnupg), so ("G16.list … is credentials") goes red while permission-answer.test.sh's ~/.ssh rows stay green | none (searched '.gnupg' and 'credentials' in tests/)
grant.test.sh | §G17 a read changes nothing about the roots; a read that reaches a credential store is reserved | keep | payload/scripts/lib/grant.sh grant_reserved_effects: a recursive read judged by its own path only, so RR of the home directory is no category; (G17.r4) goes red | none (searched 'grant_reserved_effects' in tests/)
grant.test.sh | §G18 a read-only agent's report is a root only inside what the lead holds | keep | payload/scripts/lib/grant.sh grant_roots: the report bound by the lead's roots dropped, so a reader's report in the main checkout allows; (G18.4) goes red | none (searched 'report=' facts in tests/)

## handoff-file.test.sh

handoff-file.test.sh | §NO-RUN | keep | payload/scripts/lib/handoff.sh: the .bionic folder created without its `*` ignore file, so git status lists the handoff (N2, N2d) | none (searched 'check-ignore' and 'handoffs folder' in tests/)
handoff-file.test.sh | §SECTIONS | keep | payload/scripts/lib/handoff.sh: an empty section written as a bare heading instead of its one "- none." line (S4, S5) | none (searched 'hf_bare' and 'bionic-handoff/v1' in tests/)
handoff-file.test.sh | §STATE | keep | payload/scripts/lib/handoff.sh: the open-tasks list keeps a pending row with no worktree, so "  - T5 ·" is printed (T6h); also the uncommitted files' count (T3c) | none (searched 'open tasks (' in tests/)
handoff-file.test.sh | §PORTABLE | keep | payload/scripts/lib/handoff.sh: the cloud-key pattern dropped from the redaction, so the AWS key's text stays in the file (P2e) | none (searched 'address redacted' and 'redact' in tests/)
handoff-file.test.sh | §POINTER | keep | payload/scripts/lib/handoff.sh: the ## Handoff section appended at the plan's end instead of before ## Not Doing (PT2b) | none (searched '## Handoff' in tests/)
handoff-file.test.sh | §CLOSED | keep | payload/scripts/lib/handoff.sh: a delivered plan's State written without its continuation: line (D2c); resume on it offers a task list (RC3b) | none (searched 'continuation: record/' and 'nothing to resume' in tests/)
handoff-file.test.sh | §READERS | keep | hooks/session-poker.sh launch-sync: a safe-to-clear line marked into the handoff document, so it is no longer byte-identical (R2b) | none (searched 'launch-sync' in tests/)
handoff-file.test.sh | §RESUME | keep | hooks/session-poker.sh resume: the arm step skipped at wave scale, so no Patrol stamp exists after resume (RS3, RS3b) | none (searched 'resume <file>' and 'poker: armed' in tests/)
handoff-file.test.sh | §BRANCH-AGREE | duplicate | payload/scripts/lib/plan.sh plan_integration_branch: the frontmatter read before ## SDLC State, so the verb and close-out name trunk (BR1b) | close-out-1.test.sh §BRANCH-AGREE (unverified)
handoff-file.test.sh | §POINTER-AGREE | keep | payload/scripts/lib/handoff.sh handoff_file_of: a tab-led ## Handoff heading not read, so close-out check falls back to today's file (PA3) | none (searched 'handoff_file_of' in tests/)

## hook-adoption.test.sh

hook-adoption.test.sh | §0 | duplicate | payload/scripts/lib/loader.sh bionic_loader_pin prints a short or empty block, so no hook's block matches it | hook-adoption.test.sh §1
hook-adoption.test.sh | §1 | keep | hooks/stop-orders.sh: one line of its loader block hand-edited, so ("stop-orders carries the canonical loader block byte for byte") goes red; engage.test.sh §E5 compares engage.sh alone | none (searched 'bionic_loader_pin' in tests/; loader.test.sh drives the pin in a throwaway hook)
hook-adoption.test.sh | §2 | keep | rule: lint — a `resolve_project_root()` definition planted in a file under hooks/, so the straggler row names it | none (searched 'resolve_project_root()' in tests/)
hook-adoption.test.sh | §3 | keep | rule: lint — a hook under hooks/ reading its session id from the payload without `session_id "` or bionic_context (hooks/stop-orders.sh's call replaced by a jq read), so the derived direct-reader roster differs from the hand list | none (searched 'SID_DIRECT' and 'session_id "' in tests/)
hook-adoption.test.sh | §4 | keep | rule: lint — a third caller of `active_run "` planted in hooks/ or payload/scripts/lib/, so ("the evidence gate's AC-3 fallback arm is the ONLY caller of active_run") names it | none (searched 'AR_CALLERS' and 'active_run "' in tests/)
hook-adoption.test.sh | §5 | duplicate | payload/scripts/lib/run.sh run_open: the delivered: test deleted, so a closed run reads open and the evidence gate refuses a commit on it; the no-.bionic row is the quiet-path row | run-predicate.test.sh §R5, bash-walls.test.sh §1
hook-adoption.test.sh | §5c | duplicate | each listed hook's engagement check deleted; payload/scripts/lib/run.sh:860 the symlink refusal deleted | cross-gate-agreement-1.test.sh §A1, permission-answer.test.sh §A10 a session with no engagement marker gets no answer, context-spend.test.sh §Group 2, canonical-sdlc-evidence-gate-2.test.sh §Section 34
hook-adoption.test.sh | §5b | keep | hooks/canonical-sdlc-governing-skill.sh: the content clause arming the gate on a declared canonical_sdlc_version deleted, so a misplaced plan declaring it is written; ("…but the same write DECLARING canonical_sdlc_version is refused as misplaced") goes red | none (searched 'canonical_sdlc_version: 14\\n' write payloads in tests/; the governing-skill suite's frontmatter rows sit above its first section)
hook-adoption.test.sh | §5d | keep | hooks/permission-answer.sh: its exit 0 after a failed bionic_context made non-zero, so an empty session key exits 1; ("permission-answer: an empty session id -> exit 0") goes red | none (searched empty-session rows in tests/permission-answer.test.sh: none)

## hook-latency.test.sh

hook-latency.test.sh | §1 | keep | payload/scripts/lib/walls.sh: a parameter expansion on the quiet `ls -la` path replaced by forks (a printf piped to sed per wall), so bash-walls.sh passes 12 external commands (1a) | none (searched 'forks at most' and 'bash -x' in tests/)
hook-latency.test.sh | §2 | keep | payload/scripts/lib/stop.sh: a builtin read on the Stop path replaced by `$(jq ...)` calls, so stop.sh passes 6 external commands (2a) | none (searched 'forks at most' in tests/)
hook-latency.test.sh | §3 | vacuous | it plants a jq call into a doctored copy and reads the suite's own fork counter, so it reads only suite code | none (searched 'planted jq' in tests/)
hook-latency.test.sh | §4 | keep | hooks/bash-walls.sh: the run verdict (session_run, a plan-directory scan) computed ahead of the walls though none reads it, so 4c and 4d count one | none (searched 'plan-directory scan' and 'session_run' in tests/)
hook-latency.test.sh | §5 | keep | payload/scripts/lib/walls.sh: the suite command classified once per ask instead of once, so cmd_class_lines runs twice on a wrapped suite call (5e) | none (searched 'cmd_class_lines' in tests/)
hook-latency.test.sh | §6 | keep | hooks/canonical-sdlc-governing-skill.sh: the plans directory walked a second time for the run verdict (6a) | none (searched 'plan-directory walk' in tests/)
hook-latency.test.sh | §7 | vacuous | the rows read tests/bench/hook-latency.sh, test tooling that is not code the plugin runs, the runner or a declared check, so no program mutation turns them red | none (searched 'BENCH_EXTRA_CANDIDATES' in tests/)
hook-latency.test.sh | §8 | vacuous | the rows read the bench's own interpreter header, tests/bench/hook-latency.sh, which is not the program | none (searched 'interpreter header' in tests/)
hook-latency.test.sh | §9 | keep | hooks/execution-recorder.sh: a builtin field read on the Bash path replaced by per-field jq forks, so the count passes 10 (9a) | none (searched 'execution-recorder.sh (Bash path)' in tests/)
hook-latency.test.sh | §10 | keep | hooks/ruling-push.sh: the one file test ahead of the fast path removed, so the fast path forks (10b) | none (searched 'ruling-push' in tests/)
hook-latency.test.sh | §11 | keep | payload/scripts/lib/walls.sh: the booking wrap applied to every call of an agent with a budget row, so its plain `ls -la` comes back staged (11a, 11c) | none (searched 'left as typed' in tests/)
hook-latency.test.sh | §PLACE | keep | payload/scripts/lib/placement.sh: the reader walks the command text instead of its segments, so a 200 KB quoted body costs more commands than a 2 KB one (PL-d) | none (searched 'placement' cost rows in tests/; placement.test.sh reads where, not cost)

## hook-timeout.test.sh

hook-timeout.test.sh | §1 | keep | payload/hooks/canonical-sdlc-governing-skill.sh: the plan text after `CONTENT=$(printf` read by a bash loop over its lines instead of whole, so a2's 200 KB plan runs more commands than its 64 KB one | none (searched 'canonical-sdlc-governing-skill' with a size pair in tests/; hook-latency.test.sh times the hooks on one input)
hook-timeout.test.sh | §2 | keep | payload/scripts/lib/cmd-class.sh: the segment split of a long chain done by a bash loop per segment character, so d's and d2's large input runs more commands than the small one | none (searched 'HTCOUNT' and 'as many commands' in tests/)
hook-timeout.test.sh | §2b | keep | payload/scripts/lib/cmd-class.sh: a quoted python3 -c body walked a line at a time instead of read whole as one word, so e's 200 KB command counts more than its 50 KB one | none (searched 'HTCOUNT' in tests/)
hook-timeout.test.sh | §2c | keep | payload/scripts/lib/walls.sh: the leading cd's target found by walking the heredoc after it line by line, so b3-l counts more than b3; also cmd_effects walking g's body | none (searched 'HTCOUNT' in tests/)
hook-timeout.test.sh | §3 | duplicate | the shipped hook's input read never reached (the planted line sits on the hook's empty-input exit), so neither the planted copy nor the shipped hook reaches its witness; the planted-walk rows otherwise read the suite's own inserted loop | hook-timeout.test.sh §1, hook-timeout.test.sh §2
hook-timeout.test.sh | §3b | keep | payload/scripts/lib/cmd-class.sh cmd_effects: the body after a redirect read a line at a time, so g-l runs more commands than g when called directly | none (searched 'cmd_effects' with a size pair in tests/)
hook-timeout.test.sh | §3c | keep | payload/hooks/permission-answer.sh: the question body walked before the push is reached, so the 64 KB question runs more commands than the 16 KB one | none (searched 'permission-answer' with 'HTCOUNT' in tests/)
hook-timeout.test.sh | §4 | keep | payload/hooks/session-poker.sh: a plan-row verb (task-set or current) reads the plan once per row instead of in one pass, so the 200 KB plan runs more commands than the 66 KB one | none (searched '§VERB' and 'as many commands on the 200 KB plan' in tests/)

## inbox.test.sh

inbox.test.sh | §PUSH | keep | hooks/ruling-push.sh: the pushed= claim before printing deleted, so the writer's next call carries the same ruling again; ("(p4) across both calls the ruling appears exactly once") goes red | none (searched 'ruling-push' in tests/; hook-latency.test.sh times the fast path only)
inbox.test.sh | §STATE | keep | hooks/session-poker.sh ruling-ack: the shown= line not written to the roster, so ("(s3) …rulings reads shown=<epoch>") goes red | none (searched 'ruling-ack' and 'ruling/v1' in tests/)
inbox.test.sh | §SCOPE | keep | hooks/ruling-push.sh: the named-writer match dropped, so every rostered writer's call carries the ruling; ("(c1) …the second live writer's call did not") goes red | none (searched 'ruling-push' in tests/)
inbox.test.sh | §ACK | keep | hooks/session-poker.sh ruling-ack: the pending flag left up after the last unread ruling is acknowledged, so ("(k3) both acknowledged … the flag is down") goes red | none (searched 'ruling-pending' in tests/; hook-latency.test.sh reads the flag only to take its fast path)
inbox.test.sh | §GUARD | keep | rule: door refusal — payload/scripts/lib/line.sh:838 line_ready's ruling-unread refusal dropped, so a row with an unread ruling publishes instead of exit 2 reason=ruling-unread; (g6) goes red | none (searched 'ruling-unread' in tests/)
inbox.test.sh | §ROOT | keep | payload/scripts/lib/walls.sh: the commit wall's acknowledgement call built from its own library directory instead of the shared plugin-root helper, so ("(rt2) the commit wall's refusal names the same root") goes red | none (searched 'acknowledge with: bash' in tests/)

## interpreter-pin.test.sh

interpreter-pin.test.sh | §1 the pin | keep | tests/run.sh: the call that puts the /bin/bash launch directory first on a suite's PATH dropped, so a probe suite under a foreign bash reports that bash's version (1.2, 1.3, 1.4) | none (searched 'BIONIC_TEST_INTERPRETER_PINNED' and 'first_path_entry' in tests/)
interpreter-pin.test.sh | §2 hand-run parity | keep | tests/lib/resolve-roots.sh: the re-exec guard trusts the inherited BIONIC_TEST_INTERPRETER_PINNED marker instead of $BASH, so "2.4a an inherited pin marker does not defeat the pin" goes red | none (searched 'BIONIC_TEST_INTERPRETER_PINNED' in tests/)
interpreter-pin.test.sh | §2b hand-run parity reaches the children | keep | tests/lib/resolve-roots.sh: the pin function not called on the hand-run path that starts under /bin/bash, so a child `bash -c` and a hook copy report the foreign version (2.8, 2.9) | none (searched 'resolve-roots.sh' with 'child=' in tests/)
interpreter-pin.test.sh | §3 the planted 3.2 incompatibilities | duplicate | tests/run.sh: the pin dropped, so the two planted divergences run green under the foreign bash (3.1); the runner's Failed: list stops naming a red suite (3.3, 3.4) | interpreter-pin.test.sh §1 the pin, interpreter-pin.test.sh §5 stderr-strict
interpreter-pin.test.sh | §4 the environment stamp | keep | tests/run.sh: the env: stamp printed only in the header, not beside Gating:, so "4.1 the stamp is printed exactly twice" goes red | none (searched 'env: os=' in tests/)
interpreter-pin.test.sh | §5 stderr-strict | keep | tests/run.sh: the scan of a passing suite's captured output for the interpreter's `command not found` shape deleted, so a green suite that lost a helper passes (5.1, 5.2, 5.3) | none (searched 'command not found' in tests/; framework.test.sh and runner-roster.test.sh read other halves)
interpreter-pin.test.sh | §6 one pin, one owner | vacuous | RUN_LN and SEAM_LN are computed and never asserted; every other row reads a mutant the suite builds by deleting one line of resolve-roots.sh, and only a second pin added to run.sh, code that is not there, changes how that mutant behaves | none (searched 'ln -sf /bin/bash' in tests/)

## jit.test.sh

jit.test.sh | §Group 1 | duplicate | payload/scripts/lib/jit.sh: the self-source of deps.sh deleted, so check_dep is undefined and jit_check fails on a present rg | jit.test.sh §Group 2
jit.test.sh | §Group 2 | keep | payload/scripts/lib/jit.sh jit_check: an unknown dep answered 0, so jit_check no-such-dep exits 0 | none (searched 'jit_check' in tests/)
jit.test.sh | §Group 3 | duplicate | payload/scripts/lib/jit.sh jit_offer: the install_dep call deleted on consent, so nothing is installed | jit.test.sh §Group 4
jit.test.sh | §Group 4 | keep | payload/scripts/lib/jit.sh jit_offer: the name handed to install_dep on consent changed, so the yes path never reaches `brew install ripgrep` | none (searched 'jit_offer' in tests/; fresh-home.test.sh drives setup's install, not jit_offer)
jit.test.sh | §Group 5 | keep | payload/scripts/lib/jit.sh jit_offer: the decline arm runs the install anyway, so a no-answer stdin records brew in the call log | none (searched 'jit_offer' in tests/)
jit.test.sh | §Group 6 | keep | rule: lint — a private `read` planted in payload/scripts/lib/jit.sh, so the sweep for a stdin read outside install_dep finds it | none (searched 'jit.sh' in tests/)
jit.test.sh | §Group 7 | duplicate | payload/scripts/lib/jit.sh jit_offer: the decline arm runs the install, so the call log is not empty (both routes); the fingerprints FP1/FP2 are computed and never asserted | jit.test.sh §Group 5
jit.test.sh | §Group 8 | keep | payload/scripts/lib/jit.sh jit_check: the absent npm-package arm prints no fix, so "npm install -g @playwright/cli" goes red; the page is the only carrier of the fix | none (searched '@playwright/cli' with jit_check in tests/)
jit.test.sh | §Group 9b | keep | payload/scripts/lib/jit.sh jit_offer: the native row's install_plugin_native call made to name the bare plugin, so `plugin install impeccable@bionic` goes red | none (searched 'install_plugin_native' and 'impeccable@bionic' in tests/)
jit.test.sh | §Group 12 | keep | payload/scripts/card.sh step0: a role render.sh renders left out of the Models block, so models_missing names it | none (searched 'Models' with card.sh step0 in tests/)
jit.test.sh | §Group 13 | keep | agents-src/templates/<role>.md.tmpl: the model: frontmatter line deleted and the role files rendered again, so render.sh --check stays green and "agents/<role>.md declares a model" goes red; the README compare this section is named for is gone (readme_row is read and never asserted) | none (searched 'model:' with agents/ in tests/; render.test.sh §Section 1 sees only the --check half)

## landing-gate.test.sh

landing-gate.test.sh | §Section 1 | keep | payload/scripts/lib/stop.sh stop_landing_gate: the landing-swept marker check deleted, so the same UNMET row refuses every later Stop (1b); also the real hook's empty stdout and stderr on the quiet path (1a, 1b) | none (searched 'landing-swept' and 'stop_landing_gate' in tests/; the other hits plant or read the marker, none re-drives the sweep)
landing-gate.test.sh | §Section 2 | keep | payload/scripts/lib/stop.sh stop_landing_gate: a MET verdict raised as a refusal, so "2a: a landed MET contract passes" goes red | none (searched 'state=MET' with 'stop.sh' in tests/)
landing-gate.test.sh | §Section 3 | keep | payload/scripts/lib/stop.sh stop_landing_gate: the background_tasks skip deleted, so a still-running agent is judged and refused (3a) | none (searched 'background_tasks' in tests/; stop.test.sh and cross-gate-agreement.prelude.sh not read to verdict on this arm)
landing-gate.test.sh | §Section 4 | keep | payload/scripts/lib/stop.sh: `if (aid != "") agent[name] = aid` inverted, so intended-then-identified takes the empty row's id and the UNMET contract passes (4i) | none (searched 'agent\[name\]' in tests/)
landing-gate.test.sh | §Section 5 | duplicate | payload/scripts/lib/stop.sh: the landing arm's engaged_session call deleted, so an unengaged session's unmet roster refuses (5a-neg); payload/scripts/lib/run.sh engaged_session: a symlinked or foreign marker read as engaged (5a-sym, 5a-foreign); 5a-back compares two identical fixtures | cross-gate-agreement-1.test.sh §A1 (unverified; "unengaged: the landing gate takes no verdict"), engage.test.sh §E8 (unverified)
landing-gate.test.sh | §Section 6 | keep | payload/scripts/lib/stop.sh stop_landing_gate: a sweeper that exits 7 read as a refusal instead of a verdict it could not take, so 6b blocks the stop | none (searched 'hooks-badsweeper' and 'session-sweeper.sh' with 'exit 7' in tests/)
landing-gate.test.sh | §Section 7 | keep | payload/scripts/lib/stop.sh stop_landing_gate: the landed-or-live join keyed on name instead of agent_id, so an unnamed dispatch is never judged (7a) | none (searched 'name= agent_id' in tests/)
landing-gate.test.sh | §Section 8 | keep | payload/scripts/lib/stop.sh stop_landing_gate: an AMBIGUOUS verdict refused like UNMET, so two contracts under one name block the stop (8c); 8a asserts nothing | none (searched 'ambiguous name' in tests/; session-sweeper.test.sh pins the verb's state, not the gate's answer)
landing-gate.test.sh | §Section 9 | keep | payload/scripts/lib/stop.sh stop_landing_gate: the sweeper ack no longer closes a row, so an acked UNMET contract still refuses (9b) | none (searched 'ack_row' and 'once acked' in tests/)
landing-gate.test.sh | §Section 10 | duplicate | payload/scripts/lib/stop.sh: the swept marker written to a state file of its own instead of the roster (10a); R10_VERDICT is computed and never asserted | landing-gate.test.sh §Section 1
landing-gate.test.sh | §Section 11 | keep | payload/scripts/lib/stop.sh stop_landing_gate: the session-key shape check deleted, so a key with path separators reaches the planted roster and a marker is written into it (11d) | none (searched 'path separators' in tests/; patrol-revive.test.sh checks its own arm)

## landing-line-1.test.sh

landing-line-1.test.sh | §EVENTS | keep | payload/scripts/lib/line.sh line_event's refusal of a value holding a pipe or a line break deleted, so "(e4) a value holding a pipe is refused" goes red | none (searched 'line_event' in tests/: gate, landing-line-2, session-poker-5 and time write only clean values)
landing-line-1.test.sh | §FOLD | keep | payload/scripts/lib/line.sh line_state's base rule takes the candidate of an absent entry, so "(f4) …and holds nothing: the next entry's base is the accepted head" goes red | none (searched 'line_state' in tests/: landing-line-2 §GRAMMAR reads one entry's outcome)
landing-line-1.test.sh | §ONE-READER | keep | rule: lint — a second parser of the landing record planted in hooks/, so the sweep finds it beside lib/line.sh (o2) | none (searched 'line_kv' and 'ev=verdict' in tests/)
landing-line-1.test.sh | §TREES | keep | payload/scripts/lib/line.sh landing_tree_take treats any `.held` file as taken, whether its holder lives or not, so "(t5) a hold whose holder is not alive is free" goes red | none (searched 'landing_tree_take' in tests/: landing-line-1 alone)
landing-line-1.test.sh | §SAME | keep | rule: door refusal — payload/scripts/lib/line.sh the publish's check that the working branch still stands at the candidate's base deleted, so a candidate proved before a later hand commit publishes; "(s2) … rc 3, rebuild" goes red | none (searched 'REBUILD' in tests/)
landing-line-1.test.sh | §PAIR | keep | rule: door refusal — payload/scripts/lib/line.sh the publish's `_line_first_in_line` call deleted, so T2 publishes ahead of a present T1; "(p3) an entry behind a present one does not publish" goes red (the section's own p3m mutant) | none (searched '_line_first_in_line' in tests/: §STALLED t4 stays green on it)
landing-line-1.test.sh | §BUSY | keep | rule: door refusal — payload/scripts/lib/line.sh the publish's live-run check over the checkout that holds the branch deleted, so it publishes under an admitted run; "(b1) … holds the publish (rc 4)" goes red | none (searched 'HELD T1' in tests/)
landing-line-1.test.sh | §MOVED | keep | rule: door refusal — payload/scripts/lib/line.sh the publish's moved-checkout check deleted, so a run that moved the main checkout's branch is followed by a publish; "(m1) the publish stops (rc 5)" goes red | none (searched 'MOVED ' and 'rc 5' in tests/)
landing-line-1.test.sh | §GIT | keep | payload/scripts/lib/line.sh _line_count_git's `_line_cut_at` check deleted, so a row tree cut at the head with no commit is counted landed by git; "(g4) a row tree with no commit of its own is not counted landed by git" goes red (the section's own g5m mutant) | none (searched '_line_count_git' and 'kind=git' in tests/: close-out-2 plants a kind=git line as input)
landing-line-1.test.sh | §GUARD | keep | rule: door refusal — payload/scripts/lib/line.sh the publish's `_line_guard` call deleted, so a candidate committing .bionic is published; "(d1) the publish is refused by the guard (rc 6)" goes red (the section's own d2m mutant) | none (searched '_line_guard' and 'why=guard' in tests/)
landing-line-1.test.sh | §READY | keep | rule: door refusal — payload/scripts/lib/line.sh _line_lands's absence arm (the `return 3` when the key is not lands_on) removed, so a 1.12.0 row with suites_allowed=none lands with no run; "(r6d2) … refused (exit 2)" goes red (the section's own r6dm mutant). also: r6g2, r6d, r6i assert refusal words beside their exit 2 | landing-line-1.test.sh §ALONE
landing-line-1.test.sh | §GATE | keep | payload/scripts/lib/line.sh line_ready runs the project's declared `floor:` command beside the suites the row names, so "(g3) x, which no brief names, never ran" goes red | none (searched 'floor: bash' in tests/; landing-line-2 §ASK holds the ask-per-start half, not the floor)
landing-line-1.test.sh | §PROOF | keep | rule: door refusal — payload/scripts/lib/line.sh line_ready takes a clean `bionic-stamps` line at the row's head as proof instead of running the suite, so a red candidate beside a green stamp publishes; "(q1) a green stamp beside a red candidate: red (exit 1)" goes red | none (searched 'bionic-stamps' and '_wt_stale_proof' in tests/)
landing-line-1.test.sh | §RED | keep | rule: door refusal — payload/scripts/lib/line.sh line_ready's standing-order arm deleted, so ready runs and lands while `order: given` stands; "(x5) an order standing: ready exits 1" goes red | none (searched 'order stands' in tests/)
landing-line-1.test.sh | §AHEAD-RED | keep | rule: door refusal — payload/scripts/lib/line.sh line_ready: T2's candidate built on returned T1's published without a rebuild, so T1's red commit reaches the branch (a2) | none (searched 'line_ready' and 'why=red' in tests/)
landing-line-1.test.sh | §SIDE | keep | payload/scripts/lib/line.sh line_ready: T2's candidate built on T1's rebuilt once T1 publishes, so T2 runs twice (w2) | none (searched 'one run each' in tests/)
landing-line-1.test.sh | §ALONE | duplicate | payload/scripts/lib/line.sh line_ready: a second spawn-worktree.sh verb called between ready and published, so the verb log holds more than ready (l1) | landing-line-1.test.sh §READY
landing-line-1.test.sh | §WITHIN | keep | rule: door refusal — payload/scripts/lib/line.sh _line_time_for: exit 1 made exit 0, so a suite promising 600 s starts with 60 s left instead of WAITING exit 75 (n1) | none (searched '_line_time_for' in tests/)
landing-line-1.test.sh | §TOO-LONG | keep | rule: door refusal — payload/scripts/lib/line.sh line_ready's suite-bar check on a Lands-on command deleted, so a command promising 700 s enters the line; "(tl1) … refused, exit 1, nothing entered the line" goes red | none (searched 'too-long' in tests/)
landing-line-1.test.sh | §GUARD (ready half) | keep | payload/scripts/lib/line.sh line_ready: the _wt_bionic_committed check removed, so a landing tree is built before the publish guard refuses (u1) | none (searched '_wt_bionic_committed' in tests/)
landing-line-1.test.sh | §ANCHORS | keep | rule: door refusal — payload/scripts/lib/line.sh line_ready: the anchors check over the candidate dropped, so a row that rewords another suite's anchor publishes instead of exit 2 reason=anchor-moved (an1) | none (searched 'anchor-moved' in tests/)
landing-line-1.test.sh | §NOVERDICT | keep | rule: door refusal — payload/scripts/lib/line.sh the verdict reader takes a run that exits 0 with no end line as green, so an unproved candidate publishes; "(v2) a run that exits 0 with no end line is no verdict, not green" goes red | none (searched 'result=none' in tests/)
landing-line-1.test.sh | §STALLED | keep | rule: door refusal — payload/scripts/lib/line.sh _line_first_in_line counts a stalled entry ahead as present, so T2 behind it is refused; "(t4) the publish passes over the stalled entry: T2 is published (rc 0)" goes red. also: t6m reads a mutant's absence | none (searched 'ev=stalled' and '_line_first_in_line' in tests/)
landing-line-1.test.sh | §RELEASE-ROW | duplicate | payload/scripts/lib/line.sh line_ready: every tests/*.test.sh run instead of the Lands-on suites, so other.test.sh gets a verdict beside the release check (rr1) | landing-line-1.test.sh §GATE
landing-line-1.test.sh | §WINDOW | keep | hooks/poker/line.sh hand_holds_report: the fill ledger's `at=` no longer placed in the window, so a decline before the window counts and "WINDOW-1d …the window 11:00 to 13:00 reads one of each" goes red; also hand_holds_ends prints an end with no release approval page (WINDOW-3a) | none (searched 'hand-holds' and '--since' in tests/; close-out-3 §HAND-HOLDS reads the default window only)

## landing-line-2.test.sh

landing-line-2.test.sh | §INPUTS | keep | rule: door refusal — payload/scripts/lib/line.sh: --within read without forcing base 10, so `--within 08` is an octal error and a row whose 5 s suite fits is not run and published (i2) | none (searched 'within 08' and 'LINE_POLL' in tests/)
landing-line-2.test.sh | §LABELS | duplicate | payload/scripts/lib/line.sh _line_suites: a path-qualified Lands-on entry decoded to its bare name; payload/scripts/lib/brief.sh: Lands-on: none lifted as a suite | landing-line-2.test.sh §PATH, dispatch-preflight-4b.test.sh §LANDS-ON (unverified)
landing-line-2.test.sh | §DEBT-LINE | duplicate | its two rows read only that ready over a ledger world exits 0 with a candidate built; _line_debt runs before a fixed `return 0`, so only ready never publishing turns them red | landing-line-1.test.sh §READY (unverified)
landing-line-2.test.sh | §REVIEW-BORN | duplicate | its two rows read only that ready exits 0 with a candidate built; _line_review_born runs before a fixed `return 0`, so only ready never publishing turns them red | landing-line-1.test.sh §READY (unverified)
landing-line-2.test.sh | §SIGNALS | keep | rule: door refusal — payload/scripts/lib/line.sh: the carrier's spawn of the runner made a plain `&` instead of bionic_job, so the K6 suite's INT trap row fails at the landing and ready returns a row it must publish (sig6) | none (searched 'bionic_job' and 'K6' in tests/; slots.test.sh drives the gate's foreground shim)
landing-line-2.test.sh | §CAUSE | keep | payload/scripts/lib/line.sh: the standing event's cause read as code whatever the door run's stamp on the candidate's tree says, so cause1 and cause2 lose cause=environment against=stamp:… | none (searched 'cause=environment' in tests/)
landing-line-2.test.sh | §KEY | keep | payload/scripts/lib/line.sh: the standing red compares the stamp's suite with the declared path whole instead of its file name, so Lands-on: tests/a.test.sh stays cause=code (key1) | none (searched 'cause=environment' and 'suite-key' in tests/)
landing-line-2.test.sh | §CAUSE-TREE | keep | payload/scripts/booked.sh: the --unplaced arm stamps where the shim stands anyway, so a dirty-tree green lands as a record at the main head (ct2) | none (searched '\-\-unplaced' in tests/)
landing-line-2.test.sh | §PATH | keep | rule: door refusal — payload/scripts/lib/line.sh: the declared path replaced by tests/<name> when that file exists, so a red declared suite beside a green tests/x.test.sh publishes instead of exit 1 (pa4) | none (searched 'scripts/deploy/__tests__' in tests/)
landing-line-2.test.sh | §DRAIN | keep | payload/scripts/lib/line.sh _line_red_owner: the red judge re-points the candidate's landing tree at the head mid-drain, so a sibling runs on the head while its verdict names the candidate (dr3, dr4) | none (searched '_line_red_owner' and 'landing_tree_point' in tests/)
landing-line-2.test.sh | §GRAMMAR | keep | payload/scripts/lib/line.sh _line_verdict_put: admitted= and width= written before log=, so "(g1) the writer puts admitted=, width=, then promised= and actual= after log=" goes red | none (searched 'admitted=' with 'log=' in tests/; landing-line-1.test.sh §WITHIN reads only the order after width=)
landing-line-2.test.sh | §ASK | keep | payload/scripts/lib/line.sh: the drain stops asking gate_width_ask again as each run ends, so p5 never starts after p1 ends (k2) | none (searched 'gate_width_ask' in tests/; gate.test.sh drives the gate's answer alone)
landing-line-2.test.sh | §ADMITTED | keep | payload/scripts/lib/line.sh _line_verdict_put: admitted= given the verdict's write instant instead of the run's admission, so p1's verdict reads 50 s late (ad2, ad3) | none (searched 'admitted=' in landing tests/)
landing-line-2.test.sh | §FIELDS | duplicate | payload/scripts/lib/line.sh: promised= or actual= read from somewhere other than the run's request | landing-line-1.test.sh §WITHIN
landing-line-2.test.sh | §STALL | keep | payload/scripts/lib/line.sh _line_none_logs: the none count reset at every ev=ready, so three bounded readies say WAITING forever and never STALLED (st1) | none (searched '_line_none_logs' and 'STALLED T1' in tests/; landing-line-1.test.sh §STALLED stalls within one call)
landing-line-2.test.sh | §GAP | keep | rule: door refusal — payload/scripts/lib/gate.sh: an open landing lease that holds no request no longer counts as active, so T1's run starts in the older landing's gap instead of WAITING exit 75 (g1, g2) | none (searched 'gate_landing_open' in tests/; gate.test.sh not read to verdict on the gap)
landing-line-2.test.sh | §ORDER | keep | rule: door refusal — payload/scripts/lib/line.sh line_ready: a new entry takes the kept lease's age, so T1 is the gate's oldest behind T2 in the line and neither publishes (o2) | none (searched 'gate_landing_leave' and 'age=' in tests/)
landing-line-2.test.sh | §LINT | keep | payload/scripts/lib/line.sh _line_comment_lint: the wave shape dropped, so a comment naming wave-39 is not refused at its line (ln1) | none (searched '_line_comment_lint' in tests/)

## live-agents.test.sh

live-agents.test.sh | §A | duplicate | payload/scripts/lib/agents.sh: the file stops parsing, loses live_agents or live_agents_has, or writes to stderr when sourced | live-agents.test.sh §B
live-agents.test.sh | §B | keep | payload/scripts/lib/agents.sh live_agents: a tool_result whose content is an array of text blocks no longer read, so "array-shaped tool_result content -> same one line" goes red | none (searched 'entry_tool_result_array' and 'live_agents' in tests/)
live-agents.test.sh | §C | keep | payload/scripts/lib/agents.sh live_agents: the STALE path prints no teammates, so "STALE still prints the newest answer's teammates" goes red | none (searched 'stale age=' in tests/)
live-agents.test.sh | §D | keep | payload/scripts/lib/agents.sh live_agents: an answer with no Teammates block read as unrecognised, so it exits 4 instead of FRESH with zero lines | live-agents.test.sh §G (kept here by the one-catcher rule, first in census order)
live-agents.test.sh | §E | keep | payload/scripts/lib/agents.sh live_agents: the NONE path writes a second stderr line or another one, so "NONE -> stderr says none with no age" reads otherwise; the missing and empty transcripts are also caught by §J and §N | live-agents.test.sh §F, live-agents.test.sh §M (kept here by the one-catcher rule: only these three read the NONE line by equality, and §P and §N match it by a line regex)
live-agents.test.sh | §F | duplicate | payload/scripts/lib/agents.sh live_agents: an unrecognised answer body read as FRESH with zero teammates instead of NONE exit 4; the NONE line read by equality | live-agents.test.sh §L, live-agents.test.sh §E
live-agents.test.sh | §G | duplicate | payload/scripts/lib/agents.sh live_agents: an older answer read instead of the newest; an answer with no Teammates block read as unrecognised | live-agents.test.sh §P, live-agents.test.sh §D
live-agents.test.sh | §H | keep | payload/scripts/lib/agents.sh live_agents: freshness measured against the first prompt instead of the last, so "…one more prompt appended -> exit 3 (STALE)" reads 0 | none (searched 'last user prompt' and 'live_agents' in tests/)
live-agents.test.sh | §J | keep | payload/scripts/lib/agents.sh live_agents: the answer located by its body text instead of the tool_use_id join, so a Bash result echoing a real answer is adopted (exit 0 instead of 4) | none (searched 'tool_use_id join' and 'forged' in tests/)
live-agents.test.sh | §K | keep | payload/scripts/lib/agents.sh live_agents: the transcript parsed whole by one jq, so a torn last line or a non-JSON line costs the answer ("malformed and untimestamped lines -> the answer is still read") | none (searched 'not json at all' with 'live_agents' in tests/)
live-agents.test.sh | §L | keep | payload/scripts/lib/agents.sh live_agents_has: the name matched as a prefix, so "a prefix of a live name is absent -> exit 1" reads 0 | none (searched 'live_agents_has' in tests/)
live-agents.test.sh | §M | duplicate | payload/scripts/lib/agents.sh live_agents: a path writes a second stderr line or none | live-agents.test.sh §B, live-agents.test.sh §C, live-agents.test.sh §E
live-agents.test.sh | §N | keep | payload/scripts/lib/agents.sh live_agents: an inner pipeline left to fail under a caller's set -e, so STALE aborts the caller instead of returning 3 ("set -e caller: STALE returns 3") | none (searched 'set -euo pipefail' with 'live_agents' in tests/)
live-agents.test.sh | §P | keep | payload/scripts/lib/agents.sh live_row_open: open read as `status = running` again, so an unknown third status word frees the slot ("an UNKNOWN third status word keeps the slot — fail-closed") | none (searched 'live_row_open' and 'live_agents_status' in tests/)

## loader.test.sh

loader.test.sh | — | — | no section | —

## notify.test.sh

notify.test.sh | §ONCE | keep | payload/scripts/lib/notify.sh: the item not marked sent after a send, so a later Stop on the same unresolved block sends again; (N3) goes red | none (searched 'owed_unsent' and 'ntfy' in tests/)
notify.test.sh | §SOURCES | keep | hooks/session-poker.sh tick: the gate-item closer deleted, so a request that left the gate file stays open on the ledger; (C2) goes red. also: W2/W3a are the catchers named for close-out-2.test.sh §5 | none (searched 'gate:' owed items in tests/)
notify.test.sh | §ASKS | keep | hooks/dispatch-preflight.sh: the refusal's approve:<name> opener deleted, so a dispatch refused for an approval leaves nothing on the ledger; (AK6b) goes red; kept by the one-catcher rule over §ASKS mutants, whose anchor rows also go red when an opener is gone | notify.test.sh §ASKS mutants
notify.test.sh | §ASKS mutants | duplicate | an opener or closer deleted from the shipped program, so the sed anchor finds no line and ("… the doctored opener is one line") goes red; every MA row past the anchor reads a suite-made mutant | notify.test.sh §ASKS
notify.test.sh | §QUIET | keep | hooks/session-poker.sh tick: the send called for every unsent ledger item instead of the GATE it raised, so a quiet tick sends the card's item; (Q1a) goes red while §SOURCES S3, whose ledger holds only sent items, stays green | none (searched 'nt_calls' and 'QUIET' in tests/)

## patrol-duties-gate.test.sh

patrol-duties-gate.test.sh | §Section 1 | duplicate | payload/scripts/lib/stop.sh stop_patrol_duties: the ran-the-tick test inverted, so a tick turn that ran the tick is refused (1, 4); the stop_hook_active pass lost (6) | patrol-duties-gate.test.sh §Section 2, patrol-duties-gate.test.sh §Section 4
patrol-duties-gate.test.sh | §Section 2 | keep | payload/scripts/lib/stop.sh stop_patrol_duties: a tool_result user entry taken as the start of a new turn, so the marker turn that ran no tick is allowed (14b) | none (searched 'tool_result' and 'Patrol tick not run' in tests/)
patrol-duties-gate.test.sh | §Section 3 | keep | payload/scripts/lib/stop.sh stop_patrol_duties: the engagement check deleted, so an unengaged session's unticked marker turn is refused (21b); also hooks/hooks.json loses the Stop registration (25). also: 2 prose pins on the hook header's comment (26, 26b) | none (searched 'stop_patrol_duties' and 'engagement marker it is silent' in tests/)
patrol-duties-gate.test.sh | §Section 4 | keep | payload/scripts/lib/stop.sh: the resume/clear ritual arm counts a CronList before an earlier marker, so a CronList before a later marker discharges the new window (35c) | none (searched 'RITUAL_CRONLIST' and 'no prior CronList' in tests/)
patrol-duties-gate.test.sh | §Section 5 | duplicate | payload/scripts/lib/stop.sh stop_patrol_duties: the ran-the-tick test inverted, so FILL-printing tick turns are refused (36, 37, 41); the unticked marker turn allowed (37b) | patrol-duties-gate.test.sh §Section 2
patrol-duties-gate.test.sh | §Section 5b | keep | payload/scripts/lib/stop.sh: a TaskStop of one ordered agent taken as answering every stand-down, so the half-answered stand-down names no one (51) | none (searched 'stand-down' and 'standdown-declined' in tests/)

## patrol-marker.test.sh

patrol-marker.test.sh | — | — | no section | —

## patrol-revive.test.sh

patrol-revive.test.sh | §Group 1 | duplicate | payload/scripts/lib/stop.sh stop_patrol_revive: the stale-stamp block deleted; payload/scripts/lib/patrol.sh: the fire window computed wrong; the absent and fresh stamps blocking | stop.test.sh §1, patrol-stale.test.sh §Section 2, landing-gate.test.sh §Section 2
patrol-revive.test.sh | §Group 2 | keep | payload/scripts/lib/stop.sh stop_patrol_revive: the `-L` refusal on the stamp deleted, so a symlink backdated with touch -h reads as a stale stamp and blocks; (10) goes red. also: the SubagentStop row is also read by stop.test.sh §4 | none (searched 'touch -h' and 'symlinked stamp' in tests/)
patrol-revive.test.sh | §Group 3 | keep | payload/scripts/lib/stop.sh stop_patrol_revive: the stamp read under the worktree's own root instead of the main repository's, so a stale main stamp seen from a worktree cwd is silent; (16) goes red | none (searched 'pr-wt' and worktree stamp rows in tests/)
patrol-revive.test.sh | §Group 4 | keep | payload/scripts/lib/stop.sh stop_patrol_revive: the notice quotes twice the interval instead of patrol_fire_window, so ("22b: …against the fire window this project's interval sets") goes red; the reason is the hook's only carrier of the limit it judged. also: 19, 20, 23 and 24 pin fixed words, prose pins carried by the block decision | none (searched 'fire window' in tests/; patrol-stale.test.sh reads the predicate, not the notice)
patrol-revive.test.sh | §Group 5 | duplicate | payload/scripts/lib/stop.sh: the Stop process's one write, the fill ledger, sent to a path outside the run's record; no line in the revive arm writes or stamps, so 25 can turn red on no change to code that is there | stop.test.sh §9
patrol-revive.test.sh | §Group 6 | keep | hooks/stop.sh loses its exec bit, so the manifest's bare-path invocation gets 126; (29) goes red while every other suite runs the hook through `bash` | none (searched 'sh -c "$HOOK"' in tests/)
patrol-revive.test.sh | §Group 7 | keep | hooks/session-poker.sh tick: the DISARM decision's stamp removal deleted, so the stamp outlives the decision and the death notice fires one window later; (33) goes red. also: 39 and 39b pin a source comment no program reads | none (searched 'decision=DISARM' in tests/; session-poker.test.sh reads only the decision line)

## patrol-stale.test.sh

patrol-stale.test.sh | §Section 1 | duplicate | payload/scripts/lib/patrol.sh patrol_fire_window: the tenth-of-the-interval jitter term changed (1c); patrol_verdict's record loses a field (1d) | patrol-stale.test.sh §Section 2, patrol-revive.test.sh §Group 2 (unverified)
patrol-stale.test.sh | §Section 2 | keep | payload/scripts/lib/patrol.sh patrol_stamp_state: limit computed as twice the interval instead of patrol_fire_window, so "5: limit = patrol_fire_window(interval)" and 6's 1320 go red | none (searched 'patrol_stamp_state' and 'limit=' in tests/)
patrol-stale.test.sh | §Section 3 | keep | hooks/dispatch-preflight.sh: the staleness half grades the stamp's age itself instead of calling patrol_verdict, so "12: …it calls patrol_verdict" goes red; 8 to 10 read source text that §Section 2 and session-start.test.sh §6 also exercise | none (searched 'patrol_verdict' in tests/; the other hits are comments, and dispatch-preflight-2.test.sh drives only an unarmed stamp)
patrol-stale.test.sh | §Section 4 | keep | payload/scripts/close-out.sh _co_tmp_owner: the owner read past the first dot, so a per-start clock file parses to `<sid>.<id>` and close-out spares it for ever (OW4) | none (searched '_co_tmp_owner' and 'PATROL_STATE_CLASSES' in tests/; session-sweep.test.sh not read to verdict)

## permission-answer.test.sh

permission-answer.test.sh | §A1 the lead's question is answered | duplicate | hooks/permission-answer.sh: the decision printed twice or the answer line not written, or the unread rm target allowed (A1.2, A1.5, A1.6) | permission-answer.test.sh §A2 a subagent's and a teammate's question are answered for THAT asker's workspace, permission-answer.test.sh §A12 every answer leaves one line, with the seven fields, outside the project, grant.test.sh §G7 every deny-fix carries the target or reason, the roots and one next step (unverified)
permission-answer.test.sh | §A2 a subagent's and a teammate's question are answered for THAT asker's workspace | keep | hooks/permission-answer.sh: the asker resolved as the lead whatever the payload's agent_id, so a teammate writing outside its own tree but inside the lead's checkout is allowed (A2.2, A2.3b) | none (searched 'This writer may write under' and 'agent_id' asker rows in tests/)
permission-answer.test.sh | §A2b a forged workspace line never widens a grant | keep | hooks/permission-answer.sh: the workspace record's path= line trusted without asking git worktree list, so a forged path=<main> lets the writer write <main>/hooks (A2b.1, A2b.lead.1) | none (searched 'forged path' in tests/)
permission-answer.test.sh | §A4 tools that collect human input are never answered | keep | hooks/permission-answer.sh: the human-input tool filter deleted, so AskUserQuestion is answered on stdout (A4.*.2) | none (searched 'AskUserQuestion' in tests/)
permission-answer.test.sh | §A5 after engagement, a failure answers deny naming the fault | keep | hooks/permission-answer.sh: the EXIT trap's deny removed, so an unplanned exit after the trap answers nothing (A5.g1, A5.g2) | none (searched 'could not read the question' and 'unplanned exit' in tests/)
permission-answer.test.sh | §A6 an unbound session has the scratch only, whatever plan is newest | keep | hooks/permission-answer.sh: an unbound session given the newest open plan's record as a root, so a target there is allowed (A6.3) | none (searched 'This session' and 'plan=none' in tests/)
permission-answer.test.sh | §A7 the incident command is denied with a fix naming the unread target | duplicate | the deny-fix message built without the unread target or the effect count, or without a script-file next step (A7.2, A7.2b, A7.3) | grant.test.sh §G7 every deny-fix carries the target or reason, the roots and one next step (unverified)
permission-answer.test.sh | §A10 a session with no engagement marker gets no answer | keep | hooks/permission-answer.sh: the engagement marker read through a symlink, so a symlinked marker answers (A10.4) | none (searched 'symlinked marker' in tests/)
permission-answer.test.sh | §A11 a project can turn the boundary off; only the literal false does | keep | hooks/permission-answer.sh: the off switch matched case-insensitively against several words, so `permission-answers: no` turns the boundary off (A11.4) | none (searched 'only the literal false' in tests/; §A21 drives false, False and unset only)
permission-answer.test.sh | §A12 every answer leaves one line, with the seven fields, outside the project | keep | hooks/permission-answer.sh: the answer line written with the decision field before the tool, so the seven fields read out of order (A12.6, A12.7) | none (searched 'answers_path' and 'deny-fix' line rows in tests/)
permission-answer.test.sh | §A13 main= is passed for every class | keep | hooks/permission-answer.sh: main= passed only for the lead's class, so a writer deleting .git inside its tree is allowed (A13.writer.1) | none (searched 'main=' and 'shared directories' in tests/; grant.test.sh §G11 hands main= to the library itself)
permission-answer.test.sh | §A14 allow paths end to end, and the same paths through .. denied | keep | hooks/permission-answer.sh: MultiEdit's file_path not read as a target, so a MultiEdit in the main checkout is allowed (A14.12) | none (searched 'MultiEdit' in tests/)
permission-answer.test.sh | §A15 a reserved question writes one gate line, once, and offers no file route | keep | hooks/permission-answer.sh: the gate/v1 line written on every ask of the same reserved question instead of once (A15.6, A15.7) | none (searched 'gate/v1' in tests/)
permission-answer.test.sh | §A16 a command too large to read is denied, quickly | keep | hooks/permission-answer.sh: the 64 KB size check deleted, so a 70 KB command is parsed and not refused as too large to read (A16.1, A16.2) | none (searched 'too large to read' in tests/; hook-timeout.test.sh §3c answers 16 and 64 KB questions)
permission-answer.test.sh | §A17 a credential store is refused through any path that reaches it | keep | hooks/permission-answer.sh: a target's link not resolved before the credentials test, so a Read through a link into ~/.ssh is allowed as ordinary (A17.1, A17.2) | none (searched 'touches credentials' in tests/)
permission-answer.test.sh | §A18 a read-only agent's report is a root only inside what the lead holds | keep | hooks/permission-answer.sh: a read-only agent's declared report taken as a root wherever it names, so a report naming the main checkout's src lets it write there (A18.1) | none (searched 'declared report' in tests/)
permission-answer.test.sh | §A19 a delete of a workspace root itself is denied; beneath it is allowed | duplicate | the delete rule allows deleting a workspace root itself, or sends the lead to ask the lead (A19.1-A19.6) | grant.test.sh §G11 the project's shared directories are no checkout's, and the main root is no one's to delete (unverified), grant.test.sh §G13 a delete outside the delete roots (unverified)
permission-answer.test.sh | §A20 a command with more targets than the hook reads is denied at once | keep | hooks/permission-answer.sh: the effects ceiling check deleted, so a command one effect past the number is read and not refused as too many targets (A20.1, A20.2) | none (searched 'too many targets to read' in tests/)
permission-answer.test.sh | §A21 on and off are one reading | keep | payload/scripts/doctor.sh: the permission-answers row reads `False` as off while the hook reads it on, so the two disagree (A21.False.1) | none (searched 'permission answers' in tests/; doctor-fleet.test.sh §Section 4 reads the doctor alone)
permission-answer.test.sh | §A22 a read that reaches a credential store is refused, by the path it takes or the tree it walks | keep | hooks/permission-answer.sh: a recursive read's walked tree not checked for a credential store, so `grep -r` over a tree holding ~/.ssh is allowed (A22 tree rows) | none (searched 'the tree it walks' and 'credentials:' in tests/)

## permission-effects.test.sh

permission-effects.test.sh | §E0 the fixture | duplicate | payload/hooks/permission-answer.sh: the workspace-root containment test inverted, so a write inside the tree is denied or one outside allowed (E0.3, E0.4); E0.0-E0.2 are the fixture's preconditions | permission-answer.test.sh §A14 allow paths end to end, and the same paths through .. denied
permission-effects.test.sh | §E1 B1 | keep | payload/scripts/lib/cmd-class.sh: a `..` after a link folded lexically instead of resolved by the kernel, so `echo x > tree/link/../escape` is allowed (E1.1-E1.3) | none (searched 'link/\.\.' and 'ln -s' in tests/permission-answer.test.sh)
permission-effects.test.sh | §E2 B2 | keep | payload/hooks/permission-answer.sh: a path beneath a link the same command makes with ln -s, or a cp or mv destination, resolved early against the disk, so `ln -s OUT nl1 && rm -rf nl1/victim` is allowed (E2.1-E2.8) | none (searched 'ln -s \$OUT' and 'cp -R' in tests/permission-answer.test.sh)
permission-effects.test.sh | §E3 T19 | keep | payload/hooks/permission-answer.sh: after a cp or mv, a later path that reaches the destination through an existing link not treated as unknown, so `cp -R evil rb && rm -rf rl/evil/sub/victim` is allowed (E3.1-E3.3) | none (searched 'rl/evil' in tests/)

## placement.test.sh

placement.test.sh | §P0 | duplicate | payload/scripts/lib/placement.sh: a syntax error, or cmd_place renamed, so the library defines no cmd_place (P0b, P0c) | placement.test.sh §FORMS
placement.test.sh | §FORMS | keep | payload/scripts/lib/placement.sh cmd_place: a parenthesis inside double quotes read as a subshell, so `echo "red run done (7 BM FAIL…)"` makes the suite moving instead of placed at the tree (F1) | none (searched 'cmd_place' in tests/)
placement.test.sh | §CHAIN | keep | payload/scripts/lib/placement.sh cmd_place: a relative cd not joined to the previous cd's directory, so `cd trees; cd t1` places at the cwd's t1 (C6, C26) | none (searched 'cmd_place' in tests/)
placement.test.sh | §MOVING | keep | payload/scripts/lib/placement.sh cmd_place: a cd on the right of an or-list followed as if it ran, so M4 (true, or cd T, then the suite) is placed at T instead of moving (M4) | none (searched 'cmd_place' and 'moving cd' in tests/)
placement.test.sh | §INVISIBLE | keep | payload/scripts/lib/placement.sh cmd_place: a heredoc body's lines read as commands, so its cd moves the suite (I2) | none (searched 'cmd_place' in tests/; hook-latency.test.sh §PLACE places only the python3 -c body)
placement.test.sh | §TARGET | keep | payload/scripts/lib/placement.sh cmd_place: a named target no segment carries answered with the end of the command and exit 0 instead of nothing and exit 3 (G6) | none (searched 'cmd_place' in tests/)
placement.test.sh | §ARGS | keep | payload/scripts/lib/placement.sh cmd_place: the absolute-cwd check deleted, so a relative cwd is accepted with exit 0 (A2) | none (searched 'cmd_place' in tests/)

## preflight-probe.test.sh

preflight-probe.test.sh | §S1 | keep | hooks/preflight-probe.sh: the chmod 600 on the attestation dropped, so the record is world-readable; ("attestation mode is 0600") goes red | none (searched '.preflight.lock' and "'%OLp'" in tests/)
preflight-probe.test.sh | §S2 | keep | hooks/preflight-probe.sh: the unwritable-state-dir branch leaves the prior attestation readable, so the gate passes on a stale record; ("an unwritable state dir leaves NO usable prior attestation (C2)") goes red. also: the credential-failure delete is caught by fail-direction-table.test.sh §the producer's two rows (§7 rows 4 and 5) | none (searched 'preflight-' prior-record rows in tests/)
preflight-probe.test.sh | §S3 | keep | hooks/preflight-probe.sh: the empty-session-key exit 3 deleted, or the refusal touching existing state | fail-direction-table.test.sh §the producer's two rows (§7 rows 4 and 5) (reopened by the merge: every named catcher is culled, so it keeps its defect)
preflight-probe.test.sh | §S4 | keep | hooks/preflight-probe.sh: the component -L check on .bionic/tmp deleted, so an in-repo directory symlink is written through; ("in-repo dir symlink is refused (exit 2)") goes red | none (searched 'decoy' in tests/; dispatch-preflight-2.test.sh §S8 drives the gate's read side)
preflight-probe.test.sh | §S5 | keep | hooks/preflight-probe.sh: the held-lock exit 4 deleted, so a racing writer writes past a held lock; ("a held lock yields exit 4") goes red | none (searched '.preflight.lock' in tests/)
preflight-probe.test.sh | §S6 | keep | hooks/preflight-probe.sh: the other-session scan's freshness test deleted, so an old transcript is warned as a live session; ("stale transcript raises no live-session warning") goes red | none (searched 'WARN.*' live-session rows in tests/)
preflight-probe.test.sh | §S6b | keep | hooks/preflight-probe.sh: the dead-session attestation prune deleted, so a leftover with no transcript survives; ("the dead session's attestation … is pruned") goes red. also: the legacy prune and live-foreign rows are also read by dispatch-preflight-2.test.sh §S6c and §S6 | none (searched 'SESSION_C' and 'preflight-' prune rows in tests/)
preflight-probe.test.sh | §S6c | keep | hooks/preflight-probe.sh: the agent_id cross-check against every roster dropped, so a covered subagent is flagged UNROSTERED; ("a rostered subagent is NOT flagged UNROSTERED") goes red, and the probe's page is the only carrier | none (searched 'UNROSTERED' and 'roster: present' in tests/)
preflight-probe.test.sh | §S7 | keep | hooks/preflight-probe.sh: the mv-failure branch stops deleting the prior record, so the failmv mutant (which carries that branch) leaves a stale stamp; ("write failure leaves NO stale stamp (A5)") goes red | none (searched 'failmv' in tests/)
preflight-probe.test.sh | §S8 | keep | rule: lint — `docs/plans` or an undocumented `exit <n>` planted in hooks/preflight-probe.sh, so the plan-walk sweep or the documented-vs-reachable exit-code set goes red | none (searched '_doc_codes' and 'docs/plans' pins in tests/)
preflight-probe.test.sh | §S9 | keep | hooks/preflight-probe.sh: the PAYLOAD_SHAPE_VALIDATED_CLI comparison deleted, so a drifted CLI draws no warning; ("mismatched pin warns, naming the installed version") goes red | none (searched 'unvalidated' in tests/)
preflight-probe.test.sh | §S10 — the sweeper arm line is GONE (epic-16 w2 task S1) | duplicate | hooks/preflight-probe.sh exits non-zero on a clean run; the three source greps are a tombstone for a deleted verb, which no change to code that is there can plant | preflight-probe.test.sh §S1
preflight-probe.test.sh | §S11 | keep | hooks/preflight-probe.sh: the project_root call replaced by the working directory, so a run inside a linked worktree writes the attestation under the worktree; ("…the attestation lands under the MAIN repository's .bionic") goes red | none (searched 'probe-wt' in tests/)
preflight-probe.test.sh | §S10 | keep | hooks/preflight-probe.sh:171 the --read absent-file `exit 5` made `exit 1`, so ("--read on an absent file exits 5") goes red while resources.test.sh, which asks only for non-zero, stays green. also: the version-literal pins are tallies of the current schema | none (searched '--read' in tests/)

## principles-item.test.sh

principles-item.test.sh | §the shipped text and the extractor | duplicate | payload/context/working-principles.md deleted or emptied, so setup has no block to write | principles-item.test.sh §SET
principles-item.test.sh | §SET | keep | payload/scripts/lib/env.sh: the working-principles write appends a second block when one is already there, so a second run adds a start marker (SET idempotence rows) | none (searched 'working-principles' in tests/)
principles-item.test.sh | §DOCTOR | keep | payload/scripts/lib/markers.sh: an edited block read as present, so doctor's edited and present rows are the same (DOCTOR edited rows) | none (searched 'state=edited' in tests/)
principles-item.test.sh | §REMOVE | keep | payload/scripts/remove.sh: the block's trailing blank line not stripped with it, so CLAUDE.md does not come back to its pre-setup bytes (REMOVE pre-setup rows); also RM_PRINCIPLES_START drifting from env.sh's | none (searched 'RM_PRINCIPLES_START' in tests/)
principles-item.test.sh | §EDITED | keep | payload/scripts/lib/env.sh: an edited span offered with a [y/N] question instead of replaced, so an n on the input keeps the edit (EDITED n rows) | none (searched 'working-principles' edited rows in tests/)
principles-item.test.sh | §CUT-SHORT | keep | payload/scripts/lib/markers.sh: the strip writes in place instead of to a staged copy moved over, so a write cut short changes the file (CUT-SHORT rows) | none (searched 'staged copy' in tests/)
principles-item.test.sh | §MALFORMED | keep | payload/scripts/lib/markers.sh markers_check: a second start marker before the end no longer a fault, so setup writes into a file with two blocks (MALFORMED two-blocks) | none (searched 'markers_check' in tests/)
principles-item.test.sh | §REMOVE-EDITED | keep | payload/scripts/remove.sh: an edited block stripped without showing the unified diff, so "@@" is not printed before the question | none (searched 'REMOVE-EDITED' and 'unified diff' in tests/)
principles-item.test.sh | §DELETE | keep | payload/scripts/remove.sh: a file holding the user's text beside the block announced as a deletion and removed (DELETE user's-text rows) | none (searched 'delete the file' in tests/)
principles-item.test.sh | §READ-ONLY | keep | payload/scripts/lib/env.sh: the writability check before the write deleted, so setup answered yes overwrites a read-only CLAUDE.md (READ-ONLY rows) | none (searched 'read-only' principles rows in tests/)
principles-item.test.sh | §EDITED-STATE | keep | payload/scripts/doctor.sh: the edited state rendered as a fault row (✗), so an edited span reads as a finding (EDITED-STATE ✗ row) | none (searched 'EDITED-STATE' in tests/)
principles-item.test.sh | §CONSENT | keep | payload/scripts/lib/env.sh: the shipped text printed after the question instead of before it (CONSENT before-the-question row) | none (searched 'CONSENT' and 'Decide what is yours' in tests/)
principles-item.test.sh | §T46-ALL | keep | payload/scripts/remove.sh: under --all the block-alone file stripped to 0 bytes but kept, so no "✓ deleted" line and the file stays (ALL rows) | none (searched '✓ deleted' in tests/)
principles-item.test.sh | §T46-NOT-A-FILE | keep | payload/scripts/lib/markers.sh: a directory at CLAUDE.md's path read as an absent file, so setup creates a file inside it (NOT-A-FILE rows) | none (searched 'is a directory' in tests/)
principles-item.test.sh | §T46-SHOWN | keep | payload/scripts/remove.sh: the block re-read after the answer and stripped whatever it now holds, so a block changed while the question waited is written (SHOWN rows) | none (searched 'changed since it was shown' in tests/)
principles-item.test.sh | §T51-NUL | keep | payload/scripts/lib/markers.sh markers_regular: the NUL test deleted, so a file holding a NUL is read as the block alone and deleted (NUL rows) | none (searched 'has_nul' in tests/)
principles-item.test.sh | §T51-COPIES | keep | payload/scripts/remove.sh _rm_regular: its body drifts from markers.sh markers_regular, so the body-for-body pin goes red. also: the doctored-copy rows read only suite code | none (searched '_rm_regular' in tests/)
principles-item.test.sh | §T51-UNREADABLE | keep | payload/scripts/doctor.sh: an unreadable regular CLAUDE.md read as absent and routed to setup (UNREADABLE rows) | none (searched 'is unreadable' in tests/)
principles-item.test.sh | §T51-PAGE | keep | payload/scripts/remove.sh: the --all page line for a block-alone file loses its "will be deleted" wording, so the page does not say the file goes (PAGE rows); the page is the only carrier of that plan | none (searched 'Do all of the above' in tests/)

## protect-database.test.sh

protect-database.test.sh | §Section 1 | keep | payload/scripts/lib/walls.sh protect-database: the DROP pattern made case-sensitive, so the lowercase form of the table statement is allowed ("lowercase drop table") | none (searched 'DROP' rows in tests/; bash-walls.test.sh §2 drives the uppercase form only)
protect-database.test.sh | §Section 2 | keep | payload/scripts/lib/walls.sh protect-database: the TRUNCATE arm deleted, so `psql -c 'TRUNCATE users'` is allowed | none (searched 'TRUNCATE' in tests/)
protect-database.test.sh | §Section 3 | keep | payload/scripts/lib/walls.sh protect-database: the DELETE arm judges the first statement only, so a WHERE-qualified statement followed by an unqualified one is allowed ("multi-stmt DELETE bypass") | none (searched 'DELETE FROM' in tests/)
protect-database.test.sh | §Section 4 | keep | payload/scripts/lib/walls.sh protect-database: the ALTER TABLE … DROP arm deleted, so a column removal is allowed | none (searched 'ALTER TABLE' in tests/)
protect-database.test.sh | §Section 5 | keep | payload/scripts/lib/walls.sh protect-database: the mongo arm deleted, so `db.dropDatabase()` is allowed | none (searched 'dropDatabase' in tests/)
protect-database.test.sh | §Section 6 | keep | payload/scripts/lib/walls.sh protect-database: SQL piped into psql not read, so an echoed table statement piped to psql is allowed | none (searched 'piped to psql' in tests/)
protect-database.test.sh | §Section 7 | keep | payload/scripts/lib/walls.sh protect-database: the DROP pattern loses its word boundary, so `echo 'The table was dropped yesterday'` is refused | none (searched 'dropped yesterday' in tests/)
protect-database.test.sh | §Section 8 | keep | payload/scripts/lib/context.sh: the engagement marker matched as any engaged-*.state under .bionic/tmp, so another session's marker engages this one and the statement is refused ("another session's marker is not engagement") | none (searched 'another session' marker rows in tests/)
protect-database.test.sh | §AC-E1.3/E1.5 | keep | payload/scripts/lib/walls.sh protect-database: the matched pattern written on the verdict line instead of the detail beneath it (AC-E1.5 rows); the page is the only carrier of which pattern matched | none (searched 'The matched pattern' in tests/)

## protect-main.test.sh

protect-main.test.sh | §Section 1 | keep | payload/scripts/lib/walls.sh wall_protect_main: the any-push-while-on-main block deleted, so a bare `git push` or `git push origin HEAD` on main is allowed ("bare push", "push origin HEAD") | none (searched 'FAKE_BRANCH' and 'bare push' in tests/; bash-walls.test.sh §2 drives only an explicit push to main)
protect-main.test.sh | §Section 2 | keep | payload/scripts/lib/walls.sh wall_protect_main: master dropped from the protected current branches, so a bare push on master is allowed ("master: bare push") | none (searched 'FAKE_BRANCH="master"' in tests/)
protect-main.test.sh | §Section 3 | keep | payload/scripts/lib/walls.sh wall_protect_main: the on-main block reads any current branch, so a bare push from a feature branch is refused ("feature: bare push"); or the destination compared as a substring, so feat/maintain-state is refused | none (searched 'feat/maintain' and 'feat/cool-thing' in tests/)
protect-main.test.sh | §Section 4 | duplicate | payload/scripts/lib/git-argv.sh: a non-push subcommand or a GIT_* prefixed commit read as a push | git-argv.test.sh §Section 1b (unverified), git-argv.test.sh §Section 1 (unverified)
protect-main.test.sh | §Section 5 | duplicate | payload/scripts/lib/git-argv.sh: a global option, a quoted branch, or a refs/heads/, + or : refspec no longer resolves to main; walls.sh: the force block deleted | git-argv.test.sh §Section 1c (unverified), protect-main.test.sh §Section 3
protect-main.test.sh | §Section 6 | duplicate | payload/scripts/lib/git-argv.sh: a topic/main branch, an echo or a heredoc body read as a push to main, or a heredoc swallowing the push after it | git-argv.test.sh §Section 1c (unverified), git-argv.test.sh §Section 1 (unverified)
protect-main.test.sh | §Section 7 | duplicate | payload/scripts/lib/git-argv.sh: an opener, a command-taking prefix (sudo, time, timeout, env -C, xargs, find -exec, ssh) or a runner string no longer skipped to the push it carries | git-argv.test.sh §Section 1h (unverified), git-argv.test.sh §Section 4b (unverified)
protect-main.test.sh | §the unengaged session | duplicate | hooks/bash-walls.sh: the engagement question asked once for all five walls inverted or deleted, so an unengaged push is refused; payload/scripts/lib/run.sh engaged_session: a symlinked marker read as engaged | bash-walls.test.sh §1, bash-walls.test.sh §12, engage.test.sh §E8 (unverified)
protect-main.test.sh | §AC-E1.3/E1.5 | keep | payload/scripts/lib/walls.sh wall_protect_main: the detail naming the current branch dropped from the refusal's stream, so "…it is beneath it, with no knob set at all" goes red; pm_one_line is defined and never called | none (searched 'The current branch is' in tests/)

## rc-item-1.test.sh

rc-item-1.test.sh | §env.sh: the roster, the literals and the default | keep | payload/scripts/lib/env.sh rc_default: the unknown-name arm falls through to the proxy body, so "rc_default refuses a name that is not bionic's" prints a block; RC_START and rc_default's body are also read by §setup: consent yes … byte compare | none (searched 'rc_default' in tests/)
rc-item-1.test.sh | §env.sh: rc_file picks the rc the shell reads | keep | payload/scripts/lib/env.sh rc_file: the declined-shell arm stops naming the shell, so "rc_file says which shell it declined" reads no fish | none (searched 'rc_file' in tests/; shell-rc.test.sh's agreement check covers zsh and bash, not the refusal)
rc-item-1.test.sh | §setup: consent yes writes the block, and the shell reads it | keep | payload/scripts/setup.sh: the claude-proxy step writes the block somewhere other than the end of the rc, so "the rc is the planted file plus the block, byte for byte" goes red | none (searched 'yes-expected' and 'rc_set' in tests/)
rc-item-1.test.sh | §setup: a second run changes nothing | keep | payload/scripts/setup.sh: the rc_get in-place test skipped, so a second consented run appends a second block (two start markers) | none (searched 'idem-before' and 'rc_get' in tests/)
rc-item-1.test.sh | §setup: consent no writes nothing | keep | payload/scripts/setup.sh: the claude-proxy step writes before reading the answer, so a declined run changes the rc | none (searched 'consent no' in tests/)
rc-item-1.test.sh | §doctor | keep | payload/scripts/doctor.sh: the proxy row's absent arm drops the /bionic:setup route, so "the absent row routes the reader to setup" goes red | none (searched 'claude() shell proxy' in tests/)
rc-item-1.test.sh | §detect | duplicate | payload/scripts/lib/detect.sh detect_rc_claude_proxy: present=yes or present=no misreported | rc-item-1.test.sh §the two doors answer the same question the same way
rc-item-1.test.sh | §the two doors answer the same question the same way | keep | payload/scripts/doctor.sh: the stale arm of the proxy row drops "stale" or its /bionic:setup route ("the stale row routes the reader to setup"); the stale-as-yes defect in detect is also caught by detect-probes.test.sh §Group 6f | none (searched 'present=stale' and 'claude() shell proxy' in tests/)
rc-item-1.test.sh | §remove: the block goes, every other line stays | keep | payload/scripts/remove.sh: the claude-proxy strip leaves the end marker, so "after remove no end marker survives" goes red | none (searched 'rm-before' and 'rc_unset' in tests/)
rc-item-1.test.sh | §remove: the standalone door does the same | keep | payload/scripts/remove.sh: RM_RC_START drifts from env.sh's RC_START, so "RM_RC_START is byte-equal to env.sh's RC_START" goes red and the standalone door cannot find setup's block | none (searched 'RM_RC_START' in tests/)
rc-item-1.test.sh | §env.sh: rc_get sees the line only inside the markers | keep | payload/scripts/lib/env.sh rc_get: the line looked for anywhere in the file, so the proxy line outside the markers reads 0 | none (searched 'rc_get' in tests/; rc-item-2.test.sh drives rc_get through setup, not this row's outside line)
rc-item-1.test.sh | §a stale in-block line | keep | payload/scripts/lib/env.sh rc_set: the stale block filtered instead of rebuilt, so the stale line survives setup ("after setup the stale line is gone") | none (searched 'STALE_LINE' in tests/)
rc-item-1.test.sh | §wave-27 T40 | keep | payload/scripts/lib/env.sh rc_unset: the strip written in place instead of staged and renamed, so a write cut short by ulimit leaves a truncated rc ("…and the rc is byte-identical to before it") | none (searched 'ulimit -f' with 'rc_unset' in tests/)
rc-item-1.test.sh | §wave-27 T46: a malformed rc block is read by markers_check, and called malformed | keep | payload/scripts/lib/detect.sh detect_rc_claude_proxy: a start marker with no end read as stale instead of malformed, so doctor sends the rc to a setup that refuses it | none (searched 'present=malformed' and 'markers_check' in tests/)
rc-item-1.test.sh | §wave-27 T46: the retired rc blocks read the same state, and say their refusal | keep | payload/scripts/remove.sh: the retired block's pending test reads the marker as a substring, so a marker quoted in a comment is asked about | none (searched 'ALIAS_START' and 'do not pair up' in tests/)
rc-item-1.test.sh | §wave-27 T51 | keep | payload/scripts/setup.sh: the retired-alias step strips from a start marker to end of file, so a start with no end loses every line after it (the five-line rc) | none (searched 'plant_t51_five' and 'markers_strip' in tests/)
rc-item-1.test.sh | §wave-27 T55 | keep | payload/scripts/remove.sh: its copy of bionic_legacy_alias_ours drifts from detect.sh's, so "T55 copies: remove.sh's bionic_legacy_alias_ours is the library's" goes red | none (searched 'bionic_legacy_alias_ours' in tests/)

## rc-item-2.test.sh

rc-item-2.test.sh | §wave-27 T75 | keep | payload/scripts/setup.sh: the retired-alias step takes bionic's bare alias line outside any marker pair, so the a-top-sev rc is not left byte for byte (the generated oracle rows) | none (searched 'rc-gen.pl' and 'outside bionic's markers' in tests/)
rc-item-2.test.sh | §wave-27 T75: bionic's claude() block clears the name it defines (A-orch-185) | duplicate | payload/scripts/lib/env.sh rc_default: the unalias line dropped or changed, so the function line errors under an alias; rc_get reads an earlier or swapped body as written | rc-item-1.test.sh §env.sh: the roster, the literals and the default, rc-item-2.test.sh §wave-27 T77
rc-item-2.test.sh | §wave-27 T77 | keep | payload/scripts/lib/env.sh rc_set: the line guarding a changed block deleted, so a block holding a user's line is rewritten and the line lost ("T77 rc_set (old-u-below): refused with its own reason" reads 0) | none (searched 'rc_state' and 'a changed block is never written' in tests/)
rc-item-2.test.sh | §wave-27 T78 | keep | payload/scripts/remove.sh _rm_rc_unset: the line guarding a changed claude() block deleted, so remove strips a block holding a user's line (rc=5 becomes 0, the rc changes) | none (searched '_rm_rc_unset' and 'never stripped' in tests/)

## refuse.test.sh

refuse.test.sh | §1 | keep | payload/scripts/lib/refuse.sh refuse_modes: every table row listed instead of the refusal=yes rows, so systemmessage and additionalcontext are named (1f); also an unknown field answered rc 0 (1t). also: 1k1-1k7 prose pins on the measurement cells | none (searched 'refuse_modes' and 'refuse_channel' in tests/)
refuse.test.sh | §2 | keep | payload/scripts/lib/refuse.sh refuse: the six-word fix check `"$fix_words" -gt` made `0 -gt`, so a seven-word fix is printed instead of refused on refuse-call (2n, 2ag2) | none (searched 'fix_words' and 'refuse-call' in tests/)
refuse.test.sh | §3 | keep | payload/scripts/lib/refuse.sh refuse: BIONIC_WALL_VERBOSE no longer read, so deny's detail never reaches the user with the knob set (3a, 3h) | none (searched 'BIONIC_WALL_VERBOSE' with refuse.sh in tests/)
refuse.test.sh | §4 | keep | payload/scripts/lib/refuse.sh: the JSON escaper leaves control bytes raw, so deny's wire carries a raw control byte and does not parse (4n, 4p) | none (searched 'refuse' JSON escaper rows in tests/)
refuse.test.sh | §5 | keep | payload/scripts/lib/refuse.sh refuse: an authoring-error arm returns instead of exiting 2, so FELL-THROUGH prints and the wall waves the action past (5b, 5c) | none (searched 'FELL-THROUGH' in tests/)
refuse.test.sh | §6 | keep | payload/scripts/lib/refuse.sh refuse: `_refuse_fold_detail "$detail"` made a plain printf, so a thirty-line exit2 detail prints whole with no +18 more (6e-6i, 6w) | none (searched '_refuse_fold_detail' and '+18 more' in tests/)
refuse.test.sh | §T47 | keep | payload/scripts/lib/refuse.sh refuse: an over-wide fact cut by bytes instead of columns, so a UTF-8 fact's printed line ends in half a character (T47-d4) or the fact is lost from the detail (T47-b5) | none (searched 'T47' and 'bionic_cols' with refuse in tests/)

## regression-rename.test.sh

regression-rename.test.sh | §ALIAS-MAP | keep | payload/scripts/lib/alias.sh alias_spellings: the born row answers the old spelling first, so the born reader's alternation leads with floor; (AM-5) goes red. also: the four map rows are also read by §ALIAS-PLAN and §AGREE-ONE | none (searched 'alias_spellings' in tests/)
regression-rename.test.sh | §GONE | keep | payload/scripts/lib/alias.sh alias_gone_text: the rigor-key row deleted, so a text carrying rigor-floor: is kept; (GO-rigor-1) goes red. also: the verb, config, proof-kind, born and reads rows are also driven through the verbs by §GONE-VERB and §GONE-BORN | none (searched 'rigor-floor' in tests/; the governing-skill suite holds no §MINIMUM section)
regression-rename.test.sh | §GONE-VERB | keep | hooks/session-poker.sh: the alias_gone check at the verb dispatch deleted, so floor-run falls through to the unknown-verb answer without naming regression-run; (GV-2b) goes red | none (searched 'floor-run' in tests/)
regression-rename.test.sh | §GONE-BORN | keep | hooks/session-poker.sh task-add: the alias_gone check on the --born operand deleted, so --born floor:b.test.sh writes a row; (GB-2) goes red | none (searched 'born floor:' and '--born' in tests/)
regression-rename.test.sh | §GONE-LOG | keep | hooks/poker/proof.sh regression-run: the one-run glob widened to read floor-run-<sha>.log, so a 1.20.0-named log refuses the whole run; (GL-2) goes red. also: GL-1 and GL-3 are also read by canonical-sdlc-evidence-gate-2.test.sh §ORDER-VERB WR-3 | none (searched 'floor-run-' in tests/)
regression-rename.test.sh | §ALIAS-PLAN | keep | payload/scripts/lib/units.sh: the born-marker reader's floor alternation dropped, so a 1.20.0 born marker reads as no born row; (AP-4) goes red | none (searched 'units_born_marks' in tests/)
regression-rename.test.sh | §AGREE-ONE | duplicate | payload/scripts/lib/proof.sh proof_fields: kind=floor not read as regression; payload/scripts/lib/alias.sh alias_awk_norm: a reads, kind or born token not normalised | regression-rename.test.sh §ALIAS-PLAN, regression-rename.test.sh §ALIAS-MAP
regression-rename.test.sh | §AGREE-SCAN | keep | rule: lint — a production line spelling an old token (`kind=floor`) planted in payload/scripts/lib/proof.sh, so the scan names it; (AS-1) goes red. also: AS-0b's count of seven poker parts is a tally of hooks/poker/, and AS-2/AS-3 build plants no row reads | none (searched 'SCAN_ERE' in tests/)
regression-rename.test.sh | §ALLOWLIST | keep | rule: lint — a prose line spelling floor planted in skills/ or hooks/ outside the allowlist's identifiers, so the AC-9.3 grep prints it; (AL-2) goes red. also: AL-3 to AL-6g run the suite's own grep and guard on doctored copies | none (searched 'floor-allowlist' in tests/)

## release-approval.test.sh

release-approval.test.sh | §NAME | keep | rule: lint — the card's pre-rename name (built from parts in the suite) planted in a file under payload, hooks, tests, skills or agents-src, so the sweep finds a spelling beside the alias constant RR_OLD_VERB in hooks/session-poker.sh (NAME-3); the alias that stops saying the new name once on stderr (NAME-5) | none (searched 'RR_OLD_VERB' in tests/)
release-approval.test.sh | §SHAPE | keep | hooks/session-poker.sh release-approval: the replay table's line for an unproved row written without its default and recommendation, so ("SHAPE-12d …each with its default, its other choice and the recommendation") goes red; session-poker-4.test.sh plants that row shape by hand and names this section as its pin. also: SHAPE-14b is a tombstone grep for card.sh final | none (searched 'release-approval/v1' dec= rows at 05b5b9dec in tests/)
release-approval.test.sh | §TRIGGERS | keep | hooks/session-poker.sh release-approval: a carried S3 finding put under Decisions, so ("TRIG-2 …and the carried S3 is no decision") goes red | none (searched '--against' and 'Findings — ' at 05b5b9dec in tests/)
release-approval.test.sh | §NO-WAIVER | keep | hooks/session-poker.sh release-approval: the waive:regression filter on the owed items deleted, so an open regression waiver becomes a decision; (NW-2b) goes red | none (searched 'waive:regression' at 05b5b9dec in tests/; session-poker-5.test.sh §WORD drives the waive verb, not the page)
release-approval.test.sh | §EARLY | keep | payload/scripts/card.sh early: the open-reader fact deleted, so an open critic row no longer refuses the page; ("EARLY-1 an open critic row on the roster: release-approval exits 1") goes red. also: EARLY-5's tick advice is also read by session-poker-5.test.sh §EARLY-TICK | none (searched 'CARD-EARLY — reader' at 05b5b9dec in tests/)
release-approval.test.sh | §PREVIEW | keep | hooks/session-poker.sh release-approval: --preview still writes the page to the record, so ("PREV-5 …no page written, no approval opened") goes red | none (searched 'release-approval --preview' at 05b5b9dec in tests/)
release-approval.test.sh | §AGREE | keep | hooks/session-poker.sh release-approval: an owed waive: item left out of Decisions, so the record's keys differ from the sources'; (AGREE-2) goes red. also: AGREE-3 and AGREE-3b run the suite's own comparer on doctored copies | none (searched 'release-approval' at 05b5b9dec in tests/)
release-approval.test.sh | §REPLY | keep | hooks/session-poker.sh reply: `all recommended` replays a withheld approval as its default, so the release is approved against the recommendation; (REPLY-3b) goes red | none (searched 'reply' with 'all recommended' at 05b5b9dec in tests/)
release-approval.test.sh | §T4 | keep | hooks/poker/plan.sh the release approval verb: a T4 row the auditor found UNVERIFIABLE counted ruled, so it leaves Decisions and counts proved instead of "the auditor's finding stands" (T4-3) | none (searched 'finding stands' and 'matrix_row_ruled' in tests/; release-approval.test.sh §CONFIRM reads the pending arm and the confirmed count, not this one)
release-approval.test.sh | §CONFIRM | keep | hooks/poker/proof.sh poker_verb_confirm_row: the T4 tier test deleted, so confirm-row writes an attributed confirmation on a T1 row instead of exit 1 (CONFIRM-2) | none (searched 'confirm-row' in tests/; bash-walls.test.sh §RULED-ONE reads the key line, not the verb)
release-approval.test.sh | §LEGACY | keep | hooks/poker/plan.sh poker_verb_reply: RP_CARD no longer lists the old-stem pages beside the new ones, so a reply over a page written before the rename finds no card (LEGACY-3) | none (searched 'RR_OLD_VERB' in tests/; sitrep.test.sh §NEXT-STOPS NX3 reads the Next line, not reply)
release-approval.test.sh | §BORN | keep | payload/scripts/card.sh early: the born-row excuse for commits past the readings deleted, so two fix rows born of findings demand a re-read; (BORN-1) goes red | none (searched 'Fixed by T' and 'born: review' at 05b5b9dec in tests/)
release-approval.test.sh | §JUDGE | keep | hooks/session-poker.sh release-approval: the Tests line built from the whole run's owed list instead of the floor judge, so a suite a later landing greened still reads red; (JUDGE-1) goes red | none (searched 'regression — ' Tests lines at 05b5b9dec in tests/; canonical-sdlc-evidence-gate-2 reads the judge, not the page)
release-approval.test.sh | §POST | keep | payload/scripts/card.sh early: the check of a reader row placed after the landed release dropped, so the card renders while that row's reading is unregistered instead of CARD-EARLY naming the row (POST-1, POST-1b) | none (searched 'reads what landed after the release' in tests/; units.test.sh §POST reads the validator's admission, not the card)
release-approval.test.sh | §STEP0 | keep | payload/scripts/card.sh step0: the approve:step0 opener deleted, so rendering the session's own configuration card owes nothing; (STEP0-6) goes red | none (searched 'approve:step0' at 05b5b9dec in tests/)
release-approval.test.sh | §HANDHOLDS | keep | hooks/poker/plan.sh the release approval verb: the hand-holds line read with no --since, so the decline before the last build landing counts and "HANDHOLDS-2 the page prints the windowed line" goes red; also proof.sh waive-row writes the date alone (WINDOW-2a) | none (searched 'hand-holds:' and 'waiver: ' in tests/)

## release-check.test.sh

release-check.test.sh | §VERSION-PAIR | keep | rule: check pin — tests/lib/release-check.sh:78 the version-mismatch arm deleted, so a newest CHANGELOG heading that disagrees with plugin.json's .version passes | none (searched 'release-check.sh' and 'version mismatch' in tests/)
release-check.test.sh | §REFUSE | keep | rule: check pin — tests/lib/release-check.sh:77 `refusals=1` dropped from the no-version arm, so a plugin.json with no .version exits 0 | none (searched 'release-check.sh' and 'no version in payload' in tests/)
release-check.test.sh | §SCAN | keep | rule: check pin — tests/lib/release-check.sh:226 the name-scan call deleted, so a listed entry planted in a committed file passes the release check | none (searched 'release-check.sh' in tests/; other suites run the poker's release-check verb against a stub command, not this file)
release-check.test.sh | §LIMITS | keep | rule: check pin — tests/lib/release-check.sh:139 lim_check's `case "$kl" in *"$st"*` arm made to match always, so a deferred sentence omitted from Known limits passes | none (searched 'release-check.sh' and 'omit the deferred sentence' in tests/)
release-check.test.sh | §FROM-REPORT | keep | rule: check pin — tests/lib/release-check.sh:197 nums_check's `bad=1` fallback after the field-for-field awk dropped, so a typed landing number that disagrees with release-note at the entry's head passes | none (searched 'release-check.sh' and 'landing-numbers' in tests/)
release-check.test.sh | §LAST | keep | rule: check pin — tests/lib/release-check.sh:204-205 the later-landing loop's `bad=1` dropped, so a row landed after the entry's head passes without the entry rendered again | none (searched 'release-check.sh' and 'landed after them' in tests/)
release-check.test.sh | §STRIKE | prose pin | "(s3a) strike: (4) is on 0 bullets" and the doctored-copy setups read the released 1.17.0 block through the suite's own strike_check — carried by the 1.17.0 release commit | none (searched 'strike_check' in tests/)
release-check.test.sh | §ENTRY-1.18.0 | prose pin | "(e2g) entry: the count says 99" and "(e2i) entry: no 1.18.0 block" with the doctor setups read the 1.18.0 block's wording through the suite's own entry_check — carried by the 1.18.0 release commit that holds the block | none (searched 'entry_check' and '1.18.0' in tests/)
release-check.test.sh | §CORR | keep | agents-src/templates/commands/help.md.tmpl: the bionic @@PLUGIN_VERSION@@ (installed) line deleted and the pages rendered again, so render.sh --check stays green and (c1) goes red. also: 4 prose pins on the 1.19.0 block | none (searched '(installed)' and 'PLUGIN_VERSION' in tests/)
release-check.test.sh | §ADR | prose pin | "(a2) the repository's ADR-053 and ADR-054 keep every rule" reads the status lines of ADRs under an ignored tree — carried by the release commits that accepted them | none (searched 'adr_status' in tests/)
release-check.test.sh | §REL-1.20.0 | prose pin | "(r2b) rel: no Known limits section", "(r2c) rel: no landing numbers section", "(r2e) rel: no section for D7" read the 1.20.0 block's wording through the suite's own rel_check — carried by the 1.20.0 release commit | none (searched 'rel_check' and '1.20.0' in tests/)
release-check.test.sh | §REVERSE | prose pin | "(v2d) rev: no 1.21.0 block" and the doctor setups read the 1.21.0 summary's wording — carried by the 1.21.0 release commit | none (searched 'rev_check' and 'until bionic2' in tests/)
release-check.test.sh | §REL-1.23.0 | prose pin | "(n2) …name the head and instant" and "(n4) …states the amended rule" read the released 1.23.0 block and ADR prose — carried by the 1.23.0 release commit; "(n1) the newest CHANGELOG heading is 1.23.0" is a tally of the newest release | release-check.test.sh §VERSION-PAIR

## render.test.sh

render.test.sh | §Section 1 | keep | agents-src/templates/<role>.md.tmpl edited without a render, so the committed agents/<role>.md no longer matches a fresh render and --check exits 1 (1a) | none (searched 'render.sh --check' and 'every rendered final matches' in tests/)
render.test.sh | §Section 2 | duplicate | agents-src/render.sh: the archive arm refuses an honestly committed tree, so the control fixture's archive arm goes red (2c) | render.test.sh §Section 8
render.test.sh | §Section 3 | keep | agents-src/render.sh --archive: the render inputs read from disk instead of HEAD, so a gitignored block HEAD lacks leaves the arm green (3e, 3f) | none (searched '--archive' in tests/)
render.test.sh | §Section 4 | keep | agents-src/render.sh --archive: the arm reports missing files only, with no diff of a final HEAD does not reproduce (4c-4e) | none (searched '--archive' in tests/)
render.test.sh | §Section 5 | keep | agents-src/render.sh --archive: the manifest digests not compared, so a doctored payload/integrity/rendered.sha256 row passes (5c, 5d); also --archive writing the manifest (5e) | none (searched 'rendered.sha256' in tests/)
render.test.sh | §Section 6 | keep | agents-src/render.sh --archive: outside a git work tree the arm exits 0 instead of refusing (6a). also: 6c prose pin on the usage block | none (searched 'git work tree' in tests/)
render.test.sh | §Section 7 | keep | agents-src/render.sh: a template under the role unit rendered whatever ROLES says, so a stray template writes a phantom agents/ file and enters the manifest (7c, 7d) | none (searched 'not-a-role' and 'phantom' in tests/)
render.test.sh | §Section 8 | keep | agents-src/render.sh --archive: render.sh itself left out of the inputs compared to HEAD, so an uncommitted edit to the renderer passes (8c, 8d) | none (searched '--archive' in tests/)
render.test.sh | §Section 9 | keep | skills/browser-verify/SKILL.md: the description's quotes dropped, so its frontmatter carries an unquoted colon the harness cannot parse (9b). also: 9c-9d run the suite's own reader on a doctored copy | none (searched 'browser-verify/SKILL.md' in tests/)
render.test.sh | §Section 10 | vacuous | the per-role loops read rt_disallowed into a variable and assert nothing; 10c runs the suite's own reader on a file the suite wrote | none (searched 'disallowedTools' in tests/)
render.test.sh | §Section 11 | prose pin | "11a: … has a reader list its records on Files: …" and 11c-11d read the brief scaffold's wording in skills/canonical-sdlc/SKILL.md and dispatch.md — carried by the commit that holds agents-src/blocks/brief-scaffold.md | none (searched 'a reader lists its records here' in tests/)
render.test.sh | §Section 12 | duplicate | agents-src/blocks/dispatch-rules.md deleted, so render.sh cannot render the role files and --check exits non-zero (12a); the per-role loop asserts nothing | render.test.sh §Section 1
render.test.sh | §Section 13 | duplicate | agents-src/render.sh: the manifest writer drops agents/critic.md, so a fresh render disagrees with the committed manifest (13g); "13c: agents/ holds the six role files" and "13d: render.sh's ROLES list is the six roles" are tallies of the role set; 13a, 13b, 13h assert the absence of retired files | render.test.sh §Section 1
render.test.sh | §Section 14 | prose pin | "14ac: … its doc default reads the plan" ('doc `approval:plan, head`') and 14ad-14ae read the kind-defaults row's wording in skills/canonical-sdlc/operational-rules.md — carried by the commit that holds that page; the other paragraph reads are never asserted | none (searched 'kind defaults' in tests/)
render.test.sh | §Section 15 | vacuous | 15i and 15j run the suite's own rt_last_para on a file the suite wrote, which reads only suite code; the step-6 line reads are never asserted | none (searched 'rt_last_para' in tests/)
render.test.sh | §Section 17 | keep | agents-src/templates/implementor.md.tmpl: the COMMENT-RULE block marker deleted and the pages rendered again, so --check stays green and "17d: …between the block's own markers" goes red for agents/implementor.md | none (searched 'COMMENT-RULE' in tests/; setup.test.sh reads the rule in the installed principles file only)

## resources.test.sh

resources.test.sh | §A | keep | payload/scripts/lib/resources.sh: MEM_PER_SUITE_GB or MEM_RESERVE_GB changed, which no §B fixture reaches because the compute term binds in all of them ("MEM_PER_SUITE_GB" 1.2); the datum-comment and measurement greps read comments no program reads | none (searched 'MEM_PER_SUITE_GB' and 'MEM_RESERVE_GB' in tests/)
resources.test.sh | §B | keep | payload/scripts/lib/resources.sh resources_budget: the compute term floor(cores / CORES_PER_SUITE) dropped, so 8c/8GB/100GB answers suites 5 instead of 4; the two Step-0 doc rows read a document | none (searched 'resources_budget' in tests/)
resources.test.sh | §C | keep | payload/scripts/lib/resources.sh resources_probe: cores read from a sysctl other than hw.ncpu, so "cores agrees with sysctl hw.ncpu" goes red | none (searched 'resources_probe' in tests/)
resources.test.sh | §D | keep | payload/scripts/lib/resources.sh resources_pressure: the load arm made at-or-above, so "load exactly 27.0 on 18 cores is not hold" reads hold | none (searched 'resources_pressure' in tests/)
resources.test.sh | §E | keep | hooks/preflight-probe.sh: the attestation's budget derived from other values than the recorded machine's, so "the recorded budget is what the library derives from the recorded machine" goes red | none (searched 'budget=' in tests/; preflight-probe.test.sh pins only the budget line's shape)
resources.test.sh | §F | keep | hooks/preflight-probe.sh --read: the unknown-version refusal deleted, so a version=9 record is accepted | none (searched 'version=9' and '\-\-read' in tests/; preflight-probe.test.sh drives accept, absent and read-only)
resources.test.sh | §G | keep | hooks/preflight-probe.sh: with resources.sh missing the attestation still declares version 2 with empty fields instead of falling to version 1 | none (searched 'degraded attestation' and 'version=' in tests/)
resources.test.sh | §H | keep | payload/scripts/lib/resources.sh: the free-percentage parse takes the first matching line, so the stub with a historic 99% reads 99 not 44 ("the LAST matching percentage line is the reading") | none (searched 'memory_pressure' and 'free_pct' in tests/)
resources.test.sh | §I | keep | payload/scripts/lib/resources.sh pressure_band: the free edge made inclusive, so "free exactly 25 is clear, not warning" reads warning | none (searched 'pressure_band' in tests/)
resources.test.sh | §J | keep | payload/scripts/lib/resources.sh pressure_sample: the prune's temp path made `${ring}.tmp.$$` again, so concurrent samplers of one shell lose lines ("12 concurrent samplers … leave 12 lines") | none (searched 'pressure_sample' in tests/; runner-width.test.sh seeds a ring, it does not sample concurrently)

## root.test.sh

root.test.sh | §0 | duplicate | payload/scripts/lib/root.sh: a top-level line writes to stdout or stderr when sourced, or the file does not parse, or loses project_root | landing-gate.test.sh §Section 1, root.test.sh §1
root.test.sh | §1 | keep | payload/scripts/lib/root.sh project_root: the git toplevel taken before the walk finds a .bionic above it, so a repo nested under a non-git workspace answers the repo (1) | none (searched 'project_root' and 'project_root_candidates' in tests/)
root.test.sh | §2 | keep | payload/scripts/lib/root.sh project_root: the linked-worktree map onto the main repository dropped, so a .bionic inside the worktree wins (2b) | none (searched 'project_root' with 'worktree add' in tests/)
root.test.sh | §3 | keep | payload/scripts/lib/root.sh project_root: the walk starts at the git root instead of the cwd, so the nearer phantom .bionic below it loses (3) | none (searched 'project_root_candidates' in tests/)
root.test.sh | §4 | keep | payload/scripts/lib/root.sh project_root: the `[ ! -L ]` test on a candidate .bionic dropped, so a symlinked .bionic that passes -d is chosen (4) | none (searched 'skipped-symlink' in tests/)
root.test.sh | §5 | keep | payload/scripts/lib/root.sh project_root: the $HOME exclusion dropped, so a .bionic inside HOME is chosen over the git toplevel (5) | none (searched 'above-home' in tests/)
root.test.sh | §6 | keep | payload/scripts/lib/root.sh project_root: the git-toplevel fallback dropped, so a repo with no .bionic answers its cwd (6) | none (searched 'git-toplevel-fallback' in tests/)
root.test.sh | §7 | keep | payload/scripts/lib/root.sh project_root: the cwd fallback dropped, so outside any repo with no .bionic the answer is empty (7) | none (searched 'cwd-fallback' in tests/)
root.test.sh | §8 | keep | payload/scripts/lib/root.sh project_root: the bare-repository exception to the worktree map dropped, so a bare repo's checkout maps to dirname(bare.git) (8, 8b) | none (searched 'bare.git' in tests/)
root.test.sh | §10 | keep | payload/scripts/lib/root.sh project_root: BIONIC_WORKTREE published from the branch name instead of the directory, so a branch named apart from its directory publishes the branch (10b); also the single rev-parse split in two (10c) | none (searched 'BIONIC_WORKTREE' in tests/)

## roots.test.sh

roots.test.sh | §1 | duplicate | payload/scripts/lib/roots.sh: a top-level line writes to stdout or stderr when sourced, or the file does not parse, or a resolver is lost | landing-gate.test.sh §Section 1, roots.test.sh §1a
roots.test.sh | §1a | keep | payload/scripts/lib/roots.sh config_value: the closing quote kept only when no trailing space follows it, so `docs-root: "alt4" ` comes back without its quote handling (the trailing-space row); also archive_root's relative value not joined onto the project | none (searched 'docs_root' with quoted values and 'archive_root' in tests/; run-predicate.test.sh §R1 holds the plain relative and absolute rows)
roots.test.sh | §1b | keep | payload/scripts/lib/roots.sh worktree_root: --show-toplevel answered from inside a linked worktree, so the worktree path comes back instead of the main checkout | none (searched 'worktree_root' in tests/)
roots.test.sh | §1d | keep | payload/scripts/lib/roots.sh plugin_root: computed at call time from a relative BASH_SOURCE, so a cd after a relative source answers the wrong directory | none (searched 'plugin_root' with a relative source in tests/)
roots.test.sh | §1c | keep | payload/scripts/lib/roots.sh config_value: a missing key answered empty instead of the caller's default (the 7d row) | none (searched 'config_value' in tests/; cross-gate-agreement-2.test.sh §S13 counts its call sites)
roots.test.sh | §1e | keep | payload/scripts/lib/roots.sh promote_target: the refusal of a tracked home under .bionic/ dropped, so a record is promoted into an ignored tree | none (searched 'promote_target' in tests/)
roots.test.sh | §2a | duplicate | payload/scripts/lib/run.sh active_plan: the plan search hard-codes .bionic/docs instead of docs_root, so a docs-root: project's plan is not found | cross-gate-agreement-1.test.sh §A1
roots.test.sh | §2b | keep | payload/hooks/stop-check.sh: `DOCS_ROOT="$(docs_root "$PROJECT_DIR")"` made the literal .bionic/docs, so record/s99.md under alt/ reads absent | none (searched 'docs-root' in tests/stop-check.test.sh)
roots.test.sh | §2c | keep | payload/hooks/canonical-sdlc-governing-skill.sh: the scaffold writes $PROJECT/.bionic/docs/{specs,plans,adrs,incidents} by literal, so the configured alt/ tree is never created | none (searched 'docs-root' in tests/canonical-sdlc-governing-skill.test.sh)
roots.test.sh | §2d | keep | payload/scripts/doctor.sh: the active-run row searches .bionic/docs instead of docs_root, so it names the decoy | none (searched 'docs-root' in tests/doctor*.test.sh)
roots.test.sh | §3 | keep | payload/hooks/session-poker.sh promote: a plan promoted instead of refused with exit 1 | none (searched 'promote' in tests/)

## roster.test.sh

roster.test.sh | §R0 | duplicate | payload/scripts/lib/roster.sh: roster_row, roster_pipe_escape or roster_pipe_unescape undefined | roster.test.sh §R1, roster.test.sh §R2
roster.test.sh | §R1 | keep | payload/scripts/lib/roster.sh roster_pipe_escape: the percent sign itself no longer escaped, so a literal %7C decodes into a pipe ("R1d …and a literal %7C in the command survives as itself") | none (searched 'roster_pipe_escape' and '%7C' in tests/; dispatch-preflight-5.test.sh reads an encoded row, not the bijection)
roster.test.sh | §R2 | keep | payload/scripts/lib/roster.sh roster_row: re_executes= folded like the other fields instead of percent-escaped, so a pipe in the command becomes a space and no longer decodes back (R2c, R2d) | none (searched 're_executes=' with '%7C' in tests/)
roster.test.sh | §R3 | keep | payload/scripts/lib/roster.sh roster_row: the pipe fold dropped for prose fields, so a pipe in deliverable= forges a status=landed segment (R3b) | none (searched 'status=landed name=ghost' in tests/)
roster.test.sh | §R4 | keep | payload/scripts/lib/roster.sh roster_row: the bare-word refusal deleted, so "R4b a bare word is still a refusal" exits 0; the unknown-key refusal is also caught by §R5h and §R13 | none (searched 'barewordarg' in tests/)
roster.test.sh | §R5 | keep | payload/scripts/lib/roster.sh roster_row: extended= written without the pipe fold, so "R5c extended= is written when passed, its pipe folded" goes red | none (searched 'extended=' in tests/)
roster.test.sh | §R5h | keep | payload/scripts/lib/roster.sh roster_row: held= written without the pipe fold, so "R5h-a held= is written when passed, its pipe folded" goes red | none (searched 'held=' in tests/; session-poker-2, close-out-3 and landing-line-1 read held= rows, not the fold)
roster.test.sh | §R6 | keep | payload/scripts/lib/roster.sh live_ids_of_name: a MET marker discharges an id again, so "R6a a MET marker with no ack discharges nothing" reads empty | none (searched 'live_ids_of_name' in tests/)
roster.test.sh | §R7 | keep | payload/scripts/lib/roster.sh _roster_open_of: born[nm] taken from the last live row in file order, so an older adopted row lets an ack close a name whose latest launch is open (R7a) | none (searched 'roster_open_names' with 'outoforder' in tests/)
roster.test.sh | §R8 | keep | payload/scripts/lib/roster.sh _roster_open_of: an unreadable stamp displaced by a well-formed one, so an ack closes the name (R8a, R8b) | none (searched 'unreadable stamp' in tests/)
roster.test.sh | §R9 | keep | payload/scripts/lib/roster.sh roster_open_names: restarted_at= ignored, so a restart after an ack reads closed (R9a) | none (searched 'restarted_at' in tests/)
roster.test.sh | §R10 | keep | payload/scripts/lib/roster.sh live_ids_of_name: the discharge read from launched_at alone, so a restarted id reads discharged (R10a, R10b) | none (searched 'restarted_at' in tests/)
roster.test.sh | §R11 | keep | payload/scripts/lib/roster.sh roster_row_for_id: the id matched in any segment instead of the first agent_id=, so a forged second agent_id= picks the row (R11f) | none (searched 'roster_row_for_id' in tests/; landing-line-1.test.sh reads one row by id)
roster.test.sh | §R12 | prose pin | "R12b no file carries the old sentence" and "R12c … cites roster_row_for_id or ADR-039 at least once" read comment wording in six files — carried by roster_row_for_id's behaviour, which §R11 drives | none (searched 'ADR-039' in tests/)
roster.test.sh | §R13 | keep | payload/scripts/lib/roster.sh roster_row: questions= written before plan= instead of trailing it, so "R13a questions= is written when passed, after plan=" goes red | none (searched 'questions=' with 'plan=none' in tests/; dispatch-preflight-4a.test.sh §Q reads questions= by key only)
roster.test.sh | §R14 | keep | payload/scripts/lib/roster.sh roster_row: lands_red= or red_evidence= dropped from the key list, so "R14a … are written when passed, after questions=" goes red | none (searched 'red_evidence=' in tests/)
roster.test.sh | §R15 | keep | payload/scripts/lib/roster.sh roster_row: pushed= not accepted back, so a row carrying it, fed back key by key, is refused (R15d) | none (searched 'pushed=' in tests/)
roster.test.sh | §R16 | keep | payload/scripts/lib/roster.sh roster_landed: a later launch line no longer clears the mark, so "R16h a later launch line of the name clears the mark" reads the old commit | none (searched 'roster_landed' and 'roster_mark_landed' in tests/; stop-orders.test.sh reads a mark, not its clearing)
roster.test.sh | §R17 | keep | payload/scripts/lib/roster.sh roster_mark_landed: the copied row drops row= or lands_on=, so "R17j the marked row keeps row= and lands_on=, the mark last" goes red | none (searched 'lands_on=' with 'roster_mark_landed' in tests/)
roster.test.sh | §R18 | keep | payload/scripts/lib/roster.sh roster_row: reason= written without the pipe fold, so a pipe forges a two=three segment (R18e) | none (searched 'reason=one' in tests/)
roster.test.sh | §R19 | keep | payload/scripts/lib/roster.sh roster_sessions_with_name: a symlinked roster followed, or the first name= of a row not the one matched (R19b, R19c) | none (searched 'roster_sessions_with_name' in tests/)

## run-predicate.test.sh

run-predicate.test.sh | §R0 | duplicate | payload/scripts/lib/run.sh deleted, unparseable, or printing when sourced | run-predicate.test.sh §R5, bash-walls.test.sh §1
run-predicate.test.sh | §R1 | duplicate | payload/scripts/lib/roots.sh docs_root: the docs-root: override ignored, or an absolute override joined onto the project | roots.test.sh §1a
run-predicate.test.sh | §R2 | duplicate | payload/scripts/lib/run.sh run_open: a delivered, abandoned or T<n> verdict changed; active_plan picks other than the newest by mtime | run-predicate.test.sh §R5, run-predicate.test.sh §R6
run-predicate.test.sh | §R3 | duplicate | payload/scripts/lib/run.sh:386 the walk's `find -maxdepth 2` widened to 3, so a depth-3 plan is a member; the walk is shared, so open_runs sees it too | run-predicate.test.sh §R6
run-predicate.test.sh | §R4 | keep | payload/scripts/lib/run.sh run_open: the delivered: test piped into a quitting `grep -q` under pipefail, so a >64 KB delivered plan reads open; (r4a) goes red while every other fixture is too small to reach the SIGPIPE window | none (searched 'FILLER_TARGET' and '64 KB' in tests/)
run-predicate.test.sh | §R5 | keep | payload/scripts/lib/run.sh run_open: the sub-step letter strip deleted, so current: 8b is out of range and reads closed; ("run_open: current: 8b -> exit 0") goes red | none (searched 'run_open' in tests/)
run-predicate.test.sh | §R6 | keep | payload/scripts/lib/run.sh open_runs: the ordering keyed on the discovery index instead of the mtime, so three open plans print in walk order; (R6g) goes red | none (searched 'open_runs' in tests/; engage.test.sh §E9 reads only the count and line 1 of two)
run-predicate.test.sh | §R7 | keep | payload/scripts/lib/run.sh session_plan: the `none` arm deleted, so plan=none is reported as a binding to a plan named none; ("session_plan: plan=none -> exit 1") goes red | none (searched 'session_plan' in tests/; hook-adoption.test.sh greps engage.sh for the call)

## run.test.sh

run.test.sh | §ORDER | keep | tests/run.sh: the check that asks the gate for the bound plan's open order deleted, so a suite starts with an order: given line standing (O2, O3) | none (searched 'order: given' and 'order lift' in tests/; landing-line-1.test.sh drives the landing door's order, not the runner's)

## runner-roster.test.sh

runner-roster.test.sh | §1 the roster is the directory | duplicate | tests/run.sh: the roster derived from anything but the tests/*.test.sh glob, so a suite in the directory gets no label, no run or no tally | runner-roster.test.sh §2 a suite dropped into tests/ gates on the next invocation (a)
runner-roster.test.sh | §2 a suite dropped into tests/ gates on the next invocation (a) | keep | tests/run.sh: the --serial path reading its own roster instead of the derived one, so a dropped-in suite is missing under --serial; (2.6) goes red | none (searched 'rr_glob' and '--serial' roster rows in tests/)
runner-roster.test.sh | §3 a file in the glob that is not a suite is REFUSED, by name (b) | keep | tests/run.sh: the framework half of the roster wall deleted, so a tests/ file that sources no framework is run; (3.3) goes red | none (searched 'does not source the framework' in tests/)
runner-roster.test.sh | §4 an empty tests/ refuses rather than reporting green over nothing (c) | keep | tests/run.sh: the empty-roster refusal deleted, so a tree with no suites reports green; (4.1) goes red | none (searched 'no suites under tests' in tests/)
runner-roster.test.sh | §5 the shipped tree | keep | rule: lint — a tests/*.test.sh planted in the tracked tree with a first line other than #!/bin/bash or no framework source, so (5.2)'s count of offenders goes red. also: 5.3's floor of forty suites and 5.7's exam file pin the current tree | none (searched 'RR_BAD' in tests/)
runner-roster.test.sh | §6 a glob match that is not a plain, plainly-named file is REFUSED | keep | tests/run.sh: the regular-file test in the roster wall deleted, so a symlink matching the glob is followed and its outside body runs green; (6.3) goes red | none (searched 'not a regular file' with the runner in tests/)
runner-roster.test.sh | §7 the runner refuses when its own width oracle is absent (walk F-9) | keep | tests/run.sh: the refusal when resources.sh will not load deleted, so the run falls back to a width and reports green; (7.3) goes red | none (searched 'pressure_level' in tests/; runner-width.test.sh drives a bad ceiling, not a missing library)
runner-roster.test.sh | §9 the progress knob | keep | tests/run.sh: the progress line written before the worker's .rc instead of after it, so a killed suite still names itself in the file; (9.16) goes red | none (searched 'BIONIC_TEST_PROGRESS' in tests/; booked.test.sh reads only the variable the shim exports)
runner-roster.test.sh | §PROGRESS a section boundary inside a running suite writes a line (wave-30 T8; Δ5a, AC-3.8) | keep | tests/lib/assert.sh section(): the append to the runner's progress file deleted, so a running suite writes no §section line; (PR.2) goes red | none (searched '_BIONIC_TEST_PROGRESS_FILE' in tests/)
runner-roster.test.sh | §10 the header names the head and the dirt of the tree under test (wave-26 T4; D5) | keep | tests/run.sh: the header's dirty= count taken from tracked changes only, so an untracked file reads dirty=0; (10.2) goes red | none (searched '^head=' header rows in tests/)
runner-roster.test.sh | §ASK a whole run asks the gate once; --serial asks per suite (T12; AC-2.12; wave-32 T2, D1, AC-1.1) | keep | tests/run.sh: the whole-run ask dropped so each worker asks for itself, so the store holds one request per suite; (ASK.2) goes red | none (searched 'key=tests/run.sh' in tests/; close-out-3.test.sh plants that key in a record)
runner-roster.test.sh | §SCRUB a suite never sees the runner's store (wave-30 T9; REQ-4 AC-4.2; D8) | keep | tests/run.sh: the BIONIC_GATE_DIR scrub on the suite a worker starts deleted, so a suite reads the run's store; (SCRUB.2) goes red | none (searched 'BIONIC_GATE_DIR=unset' in tests/)

## runner-width.test.sh

runner-width.test.sh | §Section 1 | keep | tests/run.sh: the pressure_level rung skipped, so a critical ring at ceiling 8 prints JOBS=8 instead of 2 (1a) | none (searched 'JOBS=' in tests/; runner-roster.test.sh reads only that a width is printed)
runner-width.test.sh | §Section 2 | keep | tests/run.sh: pressure_sample called before the --dry-run exit, so a dry run appends a line to the ring (2a) | none (searched '\-\-dry-run' with 'ring_fingerprint' in tests/)
runner-width.test.sh | §Section 3 | keep | tests/run.sh: the one-line notice for a set BIONIC_TEST_JOBS deleted, so "3a a caller who still sets BIONIC_TEST_JOBS is told once, on stderr" goes red | none (searched 'BIONIC_TEST_JOBS is retired' in tests/)
runner-width.test.sh | §Section 5 | keep | tests/run.sh: the fallback when pressure_level refuses a ceiling deleted, so JOBS comes out empty and a garbage ceiling kills the run (5) | none (searched 'need <ceiling>' in tests/)
runner-width.test.sh | §Section 6 | keep | tests/run.sh: the width taken from a literal 8 instead of gate_width, so share 92 on 8 cores prints JOBS=8 not 7 (6b, 6c) | none (searched 'gate_width' with '\-\-dry-run' in tests/; gate.test.sh drives gate_width alone)
runner-width.test.sh | §NO-VOID nothing passes or fails by the clock | keep | payload/scripts/booked.sh: the unknown-option arm made to pass an option through, so `--quiet` runs the command instead of usage exit 2 (NV.11) | none (searched 'booked: usage' in tests/)
runner-width.test.sh | §NO-RETRY a suite red once stays red in the log, run once (wave-35 T2; D11, AC-2.4) | duplicate | tests/run.sh: a red suite's verdict, its Gating count or its Failed: entry misreported | interpreter-pin.test.sh §5 stderr-strict

## scale-profile.test.sh

scale-profile.test.sh | §CELL | keep | payload/scripts/lib/scale.sh scale_cell: the unknown-scale arm exits 0, so "C.u1 a scale the table does not hold exits 1" goes red; a changed cell is also caught by §TASK's writer cap | none (searched 'scale_cell' and 'use task, wave or epic' in tests/)
scale-profile.test.sh | §TASK | keep | payload/scripts/lib/walls.sh: the budget wall's cap read from a default instead of the task scale's cell, so the fourth writer is admitted and the refusal no longer names "the task scale's writer cap" (T.w2, T.w4); or hooks/engage.sh arms a Patrol stamp at task scale (T.e2) | none (searched "task scale's writer cap" and 'scale: task' in tests/; close-out-1.test.sh records the PR command on run, not check)
scale-profile.test.sh | §TABLE | duplicate | payload/scripts/lib/scale.sh: a cell changed, so the doctrine's table no longer matches the library; an edit to SKILL.md's table is a document, not the program; SP_BYTES is computed and never asserted | scale-profile.test.sh §CELL

## seam-resolution.test.sh

seam-resolution.test.sh | §Group 1 | duplicate | tests/lib/resolve-roots.sh: a class's default directory derived wrong (hooks, skills or the repository), so every suite reading that variable reads the wrong tree | hook-timeout.test.sh §1, jit.test.sh §Group 12, session-poker-5.test.sh §DECISIONS
seam-resolution.test.sh | §Group 2 | keep | tests/lib/resolve-roots.sh: the repository derived from the caller's cwd instead of the helper's own path, so an absolute source from cwd=/ resolves no hooks directory (Group 2 rows); the runner starts suites from the repository root, where both readings agree | none (searched 'resolve-roots.sh' with a foreign cwd in tests/)
seam-resolution.test.sh | §Group 3 | keep | tests/lib/resolve-roots.sh: a set BIONIC_HOOKS_DIR overwritten by the default, so the named check reads the repository's walls.sh, not the doctored copy | none (searched 'BIONIC_HOOKS_DIR=' overrides in tests/)
seam-resolution.test.sh | §Group 4 | duplicate | tests/lib/resolve-roots.sh: an unset class read from somewhere other than the repository; "no override: named check reads the repo constant" (SUPPORTED_SDLC_VERSION=14) is also a tally of the current SDLC version | hook-timeout.test.sh §1, jit.test.sh §Group 12, session-poker-5.test.sh §DECISIONS
seam-resolution.test.sh | §Group 5 | keep | tests/lib/resolve-roots.sh: the skills and scripts defaults derived from BIONIC_HOOKS_DIR, so a hooks override drags the other two along (Group 5 rows) | none (searched 'BIONIC_SKILLS_DIR' and 'BIONIC_SCRIPTS_DIR' overrides in tests/)
seam-resolution.test.sh | §Group 6 | keep | rule: lint — a tests/*.test.sh that resolves its paths privately, without the seam or with the legacy `$(cd "$(dirname "$0")/.." && pwd)` offset, so the sweep names it | none (searched 'resolve-roots' sweeps in tests/)

## session-poker-2.test.sh

session-poker-2.test.sh | §Section 35 | keep | hooks/session-poker.sh fill-report: the fold by turn key deleted, so a superseded line inside one turn is summed; ("35f …six turns, not seven") goes red | none (searched 'fill-report' in tests/; sitrep and time read its output only in passing)
session-poker-2.test.sh | §Section 36 | keep | hooks/session-poker.sh prompt: the bionic-patrol session marker dropped from the front of the printed prompt, so ("36b AC-6.1 the prompt starts with this session's marker") goes red | none (searched ' prompt' verb drives in tests/; handoff-file and session-start name the verb in text)
session-poker-2.test.sh | §Section 37 | keep | payload/scripts/lib/units.sh: the step hold for a gate-act row deleted from the ready program, so the Step-7 release row fills at current: 5; (37a) goes red | none (searched 'Release 1.8.7' and 'held for their step' in tests/)
session-poker-2.test.sh | §Section 38 | keep | hooks/session-poker.sh tick: the poker: HELD line for an ext:-held row deleted, so ("38a AC-3.3 the ext:-held row prints its HELD line") goes red | none (searched 'poker: HELD' in tests/)
session-poker-2.test.sh | §Section 39 | keep | hooks/session-poker.sh tick: the LEDGER print of units_findings deleted, so ("39a AC-4.2 a landed row with no line ticks a LEDGER line") goes red | none (searched 'poker: LEDGER' in tests/)
session-poker-2.test.sh | §Section 40 | keep | hooks/session-poker.sh tick: the no-roster QUIET exit placed above the HELD and LEDGER prints, so the first tick of a run prints neither; (40a) goes red while §Section 38 and §Section 39, which hold rosters, stay green | none (searched 'poker: HELD' in tests/)
session-poker-2.test.sh | §Section 41 | keep | hooks/session-poker.sh tick: the held row's fingerprint comparison deleted, so a held agent whose launch changed is still held; ("41d-… AC-4.4 after the change the row is stood down again") goes red | none (searched 'held=' and 'fp=' in tests/; roster.test.sh and landing-line-1 read held= as a field only)

## session-poker-3.test.sh

session-poker-3.test.sh | §Section 56 §FACT | keep | payload/hooks/session-poker.sh proof-add review: the reader-role check dropped, so a bionic:implementor row's reading registers as a review proof (56f8, 56f9) | none (searched 'question=evidence reader=' and 'proof-add review' in tests/; session-poker-4.test.sh and dispatch-preflight-4a.test.sh drive other arms of the verb)
session-poker-3.test.sh | §Section 57 §JUDGE §WHOLE §WAIVE | keep | payload/scripts/lib/proof.sh facts_state: a waiver read by presence instead of by its head, so a failing fact newer than the waiver stays covered (57e2, 57v7) | none (searched 'waived: question=' and 'facts_state' in tests/; close-out and sitrep read facts_state with no waiver)
session-poker-3.test.sh | §Section 58 §READING | keep | payload/hooks/session-poker.sh proof-add review: a record holding two passes registered instead of refused, so one record carries two readings (58a2) | none (searched 'holds 2 passes' in tests/)
session-poker-3.test.sh | §Section 59 §RANGE-Q | keep | payload/hooks/session-poker.sh proof-add review: the returned row taken as the first read row instead of the one carrying the reading's question, so the evidence row T3 is returned for an adversarial reading (59c4) | none (searched 'RANGE-Q' and 'back to pending' in tests/)

## session-poker-4.test.sh

session-poker-4.test.sh | §SEV §FACT-rate §FACT-table §FACT-derive §FACT-shown §FACT-old §CUR8-sev | keep | payload/scripts/lib/proof.sh: the table's S2:off cell made fix instead of defer, so the S2 off reading is refused as a fix shown nowhere and writes no deferred: line (SEV-pri S2 off, SEV-table) | none (searched 'proof_priority' and 'deferred: record' in tests/)
session-poker-4.test.sh | §DEBT-PARSE §DEBT-LEDGER §DEBT-ADVISORY (the verb half) | keep | payload/scripts/lib/proof.sh proof_findings: the /^debt:/ arm read as no line, so a debt-only pass reads findings-free and DEBT-P1's flag is refused; or the debt verb's unbound adopt takes the newest plan (DEBT-U1) | none (searched 'proof_findings' and 'debt adopt' in tests/; close-out-3, close-out-4 and release-check drive the ledger from the close)
session-poker-4.test.sh | §LINE-TELL | keep | hooks/session-poker.sh tick: the memory of events already told deleted, so a second tick over the same record tells the standing red and the stall again (LT3) | none (searched 'note: standing' and 'note: stalled' in tests/)
session-poker-4.test.sh | §RC-DEFER §RC-STATED §RC-PARSE | keep | hooks/session-poker.sh release-check: the changelog match for a stated deferral inverted, so a sentence present in CHANGELOG.md reads unstated (RD-6, RD-8b) | none (searched 'finding-stated' in tests/; close-out-2 and release-check carry the stated field, not the match)
session-poker-4.test.sh | §STEP-FIELD §COPIED-LOG §REVIEW-RANGE §CUR7-COVERED | keep | hooks/session-poker.sh step-field: the auditor= field written under the named step rather than the Step 5 block alone, so "VG-1b … so Step 4's is" refused nothing; or a copied log matched by name instead of sha256 (VG-3) | none (searched 'step-field' and 'whole-copy.log' in tests/)
session-poker-4.test.sh | §REPLY-SEQ | keep | hooks/session-poker.sh reply: an item naming a decision the page does not hold applied up to it instead of refusing the whole reply (RS-1, RS-1b) | none (searched 'release-approval/v1' with ' reply ' in tests/; release-approval.test.sh not read to its verdict)

## session-poker-5.test.sh

session-poker-5.test.sh | §CHECK | keep | hooks/session-poker.sh current: the --check flag accepted at step 4, so `current 4 --check` runs instead of the usage error (CK-u1); also a check that writes a file (the cksum row) | none (searched 'current 4 --check' and '--check' usage rows in tests/)
session-poker-5.test.sh | §WORD | duplicate | hooks/session-poker.sh waive: `waive regression` admitted, `waive all` writing other than the three question lines, or a word outside the four admitted (WD-1, WD-5b, WD-8) | session-poker-3.test.sh §Section 57 §JUDGE §WHOLE §WAIVE (unverified), session-poker-4.test.sh §STEP-FIELD §COPIED-LOG §REVIEW-RANGE §CUR7-COVERED (unverified)
session-poker-5.test.sh | §DECISIONS | keep | hooks/session-poker.sh decisions: a fenced example heading read as a register entry, so D9 is listed (DC-1c); an absent ledger not exit 1 (DC-4) | none (searched 'decisions --all' and 'design-ledger.md' in tests/)
session-poker-5.test.sh | §ROUNDS | keep | hooks/session-poker.sh decisions put: the put line not written to the run's ledger, so the round count reads none (RD-1b, RD-2) | none (searched 'decisions put' in tests/; decision-skill.test.sh reads the skill's text)
session-poker-5.test.sh | §EARLY-TICK | keep | hooks/poker/tick.sh: the CARD-EARLY advice printed whether or not an integrate row is open, so the tick with no open integrate row says it (ET-3b) | none (searched 'CARD-EARLY' in tests/; release-approval.test.sh reads card.sh early alone)
session-poker-5.test.sh | §ORDER | keep | hooks/poker/tick.sh: FILL ordered by table position instead of the longest remaining chain, so it names T1 first (OR-1, OR-4) | none (searched 'widths: ' and 'poker: FILL' order rows in tests/)
session-poker-5.test.sh | §QUIET-LANDING | keep | hooks/poker/tick.sh: the row's live landing carrier not read before the mtimes, so a row with a live ready carrier is NOTIFY (QL-2b, QL-5c) | none (searched 'past declared duration' and 'no line for' in tests/)

## session-poker.test.sh

session-poker.test.sh | §Section 1 | keep | payload/hooks/session-poker.sh: an unknown verb falls to the tick instead of the usage arm, so nonsense-verb does not exit 2 | none (searched 'nonsense-verb' and 'usage error' with session-poker.sh in tests/)
session-poker.test.sh | §Section 2 | keep | payload/hooks/session-poker.sh interval: a malformed override silently defaulted to 20m instead of refusing exit 2; also interval-default reading the live config instead of the constant | none (searched 'interval-default' in tests/; session-sweep.test.sh reads the sweeper's default)
session-poker.test.sh | §Section 3 | keep | payload/hooks/session-poker.sh tick: an unacked UNMET row past its duration decided QUIET instead of NOTIFY, so rows=overdue-agent is never named | none (searched 'decision=NOTIFY' in tests/)
session-poker.test.sh | §Section 4 | keep | payload/hooks/session-poker.sh tick: the sweeper's refusal on a symlinked state directory swallowed, so the tick decides DISARM instead of exit 2 | none (searched 'REFUSED' with session-poker.sh tick in tests/)
session-poker.test.sh | §Section 5 | keep | payload/hooks/session-poker.sh: the root taken from the cwd's git toplevel instead of project_root, so a tick from a linked worktree finds no roster and refuses (the worktree-cwd NOTIFY row) | none (searched 'worktree' with session-poker.sh tick in tests/; root.test.sh §2 drives project_root alone)
session-poker.test.sh | §Section 6 | keep | payload/hooks/session-poker.sh tick: the Patrol stamp written after the decision, so a refused pre-roster tick leaves no verb=tick stamp | none (searched 'verb=tick' and 'patrol-stamp/v1' in tests/)
session-poker.test.sh | §Section 7 | keep | payload/hooks/session-poker.sh window: the roster's mtime printed instead of its birth instant, so a roster touched a day ahead moves the window (7d) | none (searched 'window' with session-poker.sh in tests/; doctor-patrol.test.sh reads the window it prints)

## session-start.test.sh

session-start.test.sh | §1 | keep | hooks/session-start.sh: a predecessor's status rows counted per line instead of per agent, so three rows for W-ALPHA read 3 open rows (1.3) | none (searched '1 open row' and 'predecessor roster' in tests/)
session-start.test.sh | §2 | keep | hooks/session-start.sh: the predecessor block's header printed with nothing under it, so a startup with nothing to report is not silent | none (searched 'nothing to report' in tests/)
session-start.test.sh | §3 | keep | hooks/session-start.sh: the root falls back to the cwd when no .bionic is above it, so a non-project cwd gets the notice | none (searched 'no .bionic anywhere' in tests/)
session-start.test.sh | §4 | keep | hooks/session-start.sh: the triple's verdict computed from env and payload only, so a disagreeing pidfile still reads agree and is not named (4.2, 4.5) | none (searched 'DIVERGE' and 'pidfile=' in tests/)
session-start.test.sh | §5 | keep | hooks/session-start.sh: the legacy-links block over worktree_legacy_links not printed, so "legacy .bionic symlinks:" and the wt-one path are missing (5.2, 5.3) | none (searched 'legacy .bionic symlinks:' in tests/; doctor-fleet.test.sh §Section 6 reads doctor's page)
session-start.test.sh | §6 | keep | hooks/session-start.sh: a dead predecessor's stamp younger than the fire window swept with the old one, so it is not deferred (6.8) | none (searched 'predecessor stamps:' and 'fire window' in tests/)
session-start.test.sh | §7 | keep | hooks/session-start.sh: an unparsable payload exits non-zero instead of 0 (7.3); 7.1 and 7.2 are hook-adoption.test.sh §5d's empty-key rows | none (searched 'unparsable payload' in tests/)
session-start.test.sh | §8 | keep | hooks/session-start.sh: an unengaged session over an open run gets the engaged block (re-arm, adopt) instead of the one-line notice (8.4-8.8) | none (searched 'one-line notice' in tests/)
session-start.test.sh | §9 | keep | hooks/session-start.sh: the bystander notice printed beside the engaged block when the marker is present (9.5) | none (searched 'bystander notice' in tests/)
session-start.test.sh | §10 | duplicate | payload/scripts/lib/context.sh: a symlink at the engagement marker's path read as engagement (10.2-10.4) | permission-answer.test.sh §A10 a session with no engagement marker gets no answer
session-start.test.sh | §11 | keep | hooks/session-start.sh: the marker read when no run is open, so a marked session with no open run prints more than the arm line (11.5) | none (searched 'no open run at all' in tests/)
session-start.test.sh | §12 | keep | hooks/session-start.sh: the open-run listing's header counts the capped list, so ten open plans read 8 (12e.2) | none (searched 'open runs exist here' in tests/)
session-start.test.sh | §13 | keep | hooks/session-start.sh: quiet open runs listed instead of folded into the quiet-count line (13a.4, 13a.5) | none (searched 'quiet open run(s)' in tests/)
session-start.test.sh | §14 | keep | hooks/session-start.sh: the bound line's step-file pointer built from step 1 instead of the plan's current step (14a.3b) | none (searched 'bionic: bound to' in tests/)
session-start.test.sh | §15 | keep | hooks/session-start.sh: the bind line not printed for an engaged unbound session over one live run, so "not bound to it" and the poker's bind verb are missing (15.7, 15.8) | none (searched 'not bound to it' in tests/)
session-start.test.sh | §15h | keep | hooks/session-start.sh: the holder of a run held by a live session not named on the bind line (15h holder rows) | none (searched 'holds it' in tests/)

## session-sweep.test.sh

session-sweep.test.sh | §1. --report-only lists exactly the dead sessions' files, and writes nothing | keep | hooks/session-poker.sh sweep: the --report-only branch falls through to the removal pass, so a report deletes the dead sessions' files; (1.20) goes red | none (searched 'report-only' in tests/; handoff-file.test.sh names the flag in text)
session-sweep.test.sh | §2. sweep removes the dead sessions' files and leaves everything else | keep | hooks/session-poker.sh sweep: the patrol stamp's .armed sibling left out of a dead session's files, so it survives the sweep; (2.10) goes red | none (searched '.armed' in tests/; patrol-stale and patrol-revive read the sibling, not the sweep)
session-sweep.test.sh | §3. a live session is refused | keep | hooks/session-poker.sh sweep: the caller's own id not passed as also-live to patrol_dead_sessions, so with no claude-home entry for it the caller's own state is swept; (3.12) goes red | none (searched 'SID_SELF' and 'live, kept' in tests/)
session-sweep.test.sh | §4. a symlink at a target path is refused, not followed | keep | hooks/session-poker.sh sweep: the -L refusal on a target deleted, so a symlinked roster is unlinked or followed; (4.3) goes red | none (searched 'refused (symlink' in tests/)
session-sweep.test.sh | §5. every session-keyed class, and only those | keep | hooks/session-poker.sh sweep: the no-session-keyed-state answer made the live-only refusal, so a tmp of unkeyed files exits 1; (5.6) goes red. also: the class rows are also read by close-out-2.test.sh §5 and the clock owner rule by patrol-stale.test.sh §Section 4 | none (searched 'no session-keyed state' in tests/)
session-sweep.test.sh | §6. the surface | keep | hooks/session-poker.sh sweep: the session-key requirement the other verbs carry applied to sweep, so a sweep with no key exits 3; (6.12) goes red | none (searched 'session=none' and 'sweep' surface rows in tests/)
session-sweep.test.sh | §7. session-start.sh's own silent auto-sweep (R2, ticket-30, AC-R2.1/2.2/2.3) | duplicate | hooks/session-start.sh deleted, so its one existence row and every later drive fail | session-sweep.test.sh §7a. AC-R2.1
session-sweep.test.sh | §7a. AC-R2.1 | keep | hooks/session-start.sh: the auto-sweep call deleted, so a dead session aged past the interval survives a session start; (7a.2) goes red | none (searched 'sweep-failed' and session-start sweep drives in tests/)
session-sweep.test.sh | §7b. AC-R2.2 | duplicate | payload/scripts/lib/patrol.sh patrol_dead_sessions: a live session read dead, so its files are swept through session-start's call | session-sweep.test.sh §3. a live session is refused
session-sweep.test.sh | §7c. AC-R2.3 | keep | hooks/session-start.sh: the age gate deleted, so a dead session's seconds-old files are swept at the next start; (7c.2) goes red | none (searched 'age gate' and 'poker-interval: 3600s' in tests/)
session-sweep.test.sh | §7d. the failure path | keep | hooks/session-start.sh: the sweep-failed marker write on a non-0/1 sweep deleted, so a refused sweep leaves nothing behind; (7d.4) goes red | none (searched 'sweep-failed' in tests/)
session-sweep.test.sh | §7g. the age gate's COST | keep | hooks/session-start.sh: the young test reads the oldest mtime of the batch instead of the newest, so one fresh file among sixty aged sessions no longer defers the batch; (7h.2) goes red while §7c's all-fresh fixture stays green | none (searched 'ss_plant_dead_many' in tests/)
session-sweep.test.sh | §7i. the gate reads mtimes on a GNU machine too, not only on a BSD one | keep | hooks/session-start.sh: the stat flavour chosen by whether `stat -f %m` printed anything, so a GNU stat's file-system dump is taken as mtimes and fresh state is swept; (7i.2) goes red while §7c stays green on BSD | none (searched 'gnu-shim' in tests/)

## session-sweeper.test.sh

session-sweeper.test.sh | §Section 1 | keep | hooks/session-sweeper.sh: the no-session-key refusal deleted, so verdict with no key answers instead of exiting 3; ("no session key REFUSES with exit 3") goes red | none (searched 'SWEEPER" verdict' and 'sweeper.sh verdict' in tests/; landing-gate, stop-orders and dispatch-preflight-5 drive it keyed)
session-sweeper.test.sh | §Section 2 | keep | hooks/session-sweeper.sh:470 parse_seconds: a range read at its strict end, so a 35-minute-old artifact under "30–40 minutes" reads UNMET; (cadence "30–40 minutes" at 2100s reads STILL-LIVE) goes red; the poker and lib/observe.sh carry their own parse_seconds | none (searched 'parse_seconds' in tests/)
session-sweeper.test.sh | §Section 3 | keep | hooks/session-sweeper.sh: the symlinked-roster refusal in verdict deleted, so a redirected roster yields a clean verdict; ("verdict over a symlinked roster REFUSES (exit 2)") goes red | none (searched 'elsewhere-s3' and symlinked roster rows in tests/)
session-sweeper.test.sh | §Section 4 | keep | hooks/session-sweeper.sh ack: the pipe fold in clean deleted, so an acked name writes its own by= field onto the ledger line; ("…so the name writes no by= field of its own") goes red | none (searched 'by=forged' and 'row(s) acked' in tests/)
session-sweeper.test.sh | §Section 5 | keep | hooks/session-sweeper.sh verdict: the `..` refusal for a relative deliverable deleted, so record/../../escaped.md is normalised and reads MET; ("..: a path that climbs out is UNMET") goes red. also: the missing and empty conjuncts are also read through stop.sh by landing-gate.test.sh | none (searched 'refused=record' in tests/)
session-sweeper.test.sh | §Section 6 | keep | hooks/session-sweeper.sh ack: the verdict= and detail= fields on an ack over an UNMET row deleted, so the ledger loses the overridden verdict; ("the ledger line carries verdict=UNMET") goes red | none (searched 'verdict=UNMET' in tests/)

## session.test.sh

session.test.sh | §Group 0 | duplicate | payload/scripts/lib/session.sh: a top-level line writes to stdout or stderr when sourced | agent-context-guard.test.sh §G1
session.test.sh | §Group 1 | keep | payload/scripts/lib/session.sh session_id: the divergence warning written whatever the two channels say, so agreement is not silent on stderr | none (searched 'session_id' and 'session.sh' in tests/; the hooks that load it suppress its stderr)
session.test.sh | §Group 2 | keep | payload/scripts/lib/session.sh session_id: the payload preferred over the environment on divergence, so stdout is sess-pay | none (searched 'session_id' in tests/; hook-adoption.test.sh §5d drives malformed keys, not the preference)
session.test.sh | §Group 3 | keep | payload/scripts/lib/session.sh session_id: an unset environment not falling back to the payload, so stdout is empty and exit 1 | none (searched 'env unset' in tests/)
session.test.sh | §Group 4 | keep | payload/scripts/lib/session.sh session_id: both channels absent returns 0 with an empty answer instead of exit 1 | none (searched 'session_id' in tests/)

## setup.test.sh

setup.test.sh | §PROXY — the line setup writes | keep | payload/scripts/lib/env.sh: the claude proxy written as `claude --allow…` instead of `command claude`, so the function calls itself (P3); also no block written to .bashrc for bash (P2) | none (searched 'bionic:rc:start' in tests/)
setup.test.sh | §PROXY — $SH: inside a bionic checkout, the checkout's payload | keep | payload/scripts/lib/env.sh: the proxy's root walk reads the cwd only, so two directories down no --plugin-dir is added (P5) | none (searched '--plugin-dir' in tests/)
setup.test.sh | §PROXY — $SH: anywhere else, nothing added | keep | payload/scripts/lib/env.sh: the proxy adds --plugin-dir for any checkout with a payload/, so a payload naming another plugin gets the flag (P8) | none (searched 'not-bionic' in tests/)
setup.test.sh | §PROXY — cheap: a shell start runs nothing, a call runs git once | keep | payload/scripts/lib/env.sh: the root resolved when the rc file is sourced instead of at call time, so a shell start runs git (P11) | none (searched 'GITLOG' and 'runs git' in tests/)
setup.test.sh | §PROXY — the consent says what the line now does | keep | payload/scripts/lib/env.sh: the consent page no longer prints the function body it will write, so the then-set line is absent (P19); also a page line past 100 columns (P18) | none (searched 'claude-proxy' consent rows in tests/)
setup.test.sh | §PROXY — the line setup wrote before this one is stale, and setup rewrites it | keep | payload/scripts/lib/detect.sh detect_rc_claude_proxy: the 1.18.0 block read as present=yes instead of stale (P12) | none (searched 'present=stale' in tests/)
setup.test.sh | §PRINCIPLES | keep | payload/context/working-principles.md: the comment rule's line deleted, so the written span and the consent screen lack "never names a wave" (R3, R4); principles-item.test.sh compares the span to whatever the shipped file holds | none (searched 'never names a wave' in tests/)

## shell-lint.test.sh

shell-lint.test.sh | §LEXER | keep | rule: lint — a hook planted with a brace depth that goes below zero, which parses under /bin/bash -n and loses its later functions, so the lexer names the file and its line | none (searched 'braces=' and 'lost-brace' in tests/; §PARSE and §LOAD cannot see a hook that parses and is never sourced)
shell-lint.test.sh | §PARSE | keep | rule: lint — a shell file that does not parse under /bin/bash planted under hooks/, payload/scripts or tests/, so the sweep's FAIL row names it | none (searched '/bin/bash -n' sweeps in tests/)
shell-lint.test.sh | §LOAD | keep | rule: lint — a library under payload/scripts/lib that writes to stderr or leaves a function undefined when loaded by a bare /bin/bash, planted, so the sweep names it | none (searched 'env -i' library loads in tests/)
shell-lint.test.sh | §CASE | keep | rule: lint — a case arm with no opening paren inside `$( … )` planted in a hook, so the sweep names the file and line | none (searched '\$(case' in tests/)
shell-lint.test.sh | §HEREDOC | keep | rule: lint — a heredoc inside `$( … )` whose body holds a lone `)`, or a paren-less case arm in an unquoted heredoc body, planted, so the sweep names it | none (searched 'HEREDOC-PAREN' and 'HEREDOC-CASE' in tests/)
shell-lint.test.sh | §CENSUS-COMPLETE-1 | keep | rule: lint — shell-lint.test.sh census_refusals loses its no-verdict arm, so a scratch census missing x's second section's line passes (also: the no-heading and no-line arms) | none (searched 'census_refusals' in tests/)
shell-lint.test.sh | §CENSUS-COMPLETE-2 | keep | rule: lint — shell-lint.test.sh census_refusals loses its bad-verdict arm, so a record line whose verdict reads maybe passes (also: the rule-mark-on-a-cull arm) | none (searched 'census_refusals' in tests/)
shell-lint.test.sh | §CENSUS-COMPLETE-3 | keep | rule: lint — a section call added to a suite under tests/ with no record line under its key, or a suite with no heading, planted in the tree, so the sweep over the real tests tree names it | none (searched 'CENSUS.md' in tests/)
shell-lint.test.sh | §CENSUS-1 | keep | rule: lint — a section whose only census line is a cull left called in a suite, planted in a scratch tree (also a shared key's culled half, read by whole title), so census_cull_refusals names the suite and the key | none (searched 'census_cull_refusals' and 'culled section present' in tests/)
shell-lint.test.sh | §CENSUS-2 | keep | rule: lint — a section whose census line is a keep deleted from its suite, or its whole suite deleted, planted in a scratch tree, so census_cull_refusals names the suite and the key | none (searched 'census_cull_refusals' and 'kept section absent' in tests/)
shell-lint.test.sh | §CENSUS-3 | keep | rule: lint — a `## Culled` line naming a record whose defect carries a rule: prefix, or whose verdict is keep, planted in a scratch census, so census_cull_refusals names it | none (searched 'census_cull_refusals' and 'rule pin culled' in tests/)
shell-lint.test.sh | §CENSUS-4 | keep | rule: lint — a section the census culls left in, or a kept section deleted, in the real tests tree, so the sweep over tests/ with tests/CENSUS.md names it | none (searched 'census_cull_refusals' and '## Culled' in tests/)

## shell-rc.test.sh

shell-rc.test.sh | §Section 1 | keep | payload/scripts/lib/shell.sh shell_rc_file: the unrecognised-shell fallback to ~/.bashrc dropped, so fish resolves to nothing (3, 4); also BIONIC_SHELL_RC no longer overriding (5) | none (searched 'shell_rc_file' in tests/)
shell-rc.test.sh | §Section 2 | keep | rule: lint — a second rc resolver, a .zshrc/.bashrc split, planted in detect.sh's _detect_shell_rc, so row 10 names it while the two callers still agree | none (searched '_detect_shell_rc' and '_rm_shell_rc' in tests/)
shell-rc.test.sh | §Section 3 | keep | payload/scripts/lib/detect.sh _detect_shell_rc: shell_rc_file's answer printed through a transform (its directory), so detect and remove disagree for every shell (12/*) while the body still calls the resolver | none (searched '_detect_shell_rc' in tests/)

## sitrep.test.sh

sitrep.test.sh | §ROWS | keep | hooks/poker/sitrep.sh:1206 the title's percent truncates (landed * 100 / total) instead of rounding, so "R2b the title's task count carries its percent, rounded" reads 23% and goes red | none (searched 'tasks done (' in tests/: sitrep.test.sh alone)
sitrep.test.sh | §SHAPES | keep | hooks/poker/sitrep.sh sitrep_render's step-line time reader (lines 850-900) takes the first ` landed ` clause without its 40-hex sha, so T28's "landed with no sha after it" reason is read as its landing; "SH6 … T28 at its landing's time" goes red | none (searched 'landed-by-hand' and 'sitrep' in tests/)
sitrep.test.sh | §ORDER | keep | hooks/poker/sitrep.sh:883 the step-approval reader matches `approved` instead of `approved by `, so Step 2 reads its earlier "frame approved at" instant; "ORD1 the Task list opens on steps 0 to 3, each with its approval time" goes red | none (searched 'approved by ' and 'sitrep' in tests/)
sitrep.test.sh | §MARKS | keep | hooks/poker/sitrep.sh:1039 the landing report's killed count is no longer added to discarded, so "M4 a killed run counts as discarded on the waste line" goes red | none (searched 'killed' and 'discarded' in tests/: close-out-4 §SCORECARD reads the waste line with no killed run)
sitrep.test.sh | §CLOCK | keep | hooks/poker/sitrep.sh sitrep_schedule (line 709) truncates the needed count instead of rounding it, so 17.9 reads 17; "CK3 the clock half says done against needed with the forecast" goes red | none (searched 'forecast needs' in tests/)
sitrep.test.sh | §BAR-PLANT | keep | hooks/poker/sitrep.sh scorecard_report prints `target < 15` as a literal instead of reading LINE_LANDING_BAR, so the mutant tree's bar of 25 does not reach it; "BP6 …and the scorecard's target reads it too" goes red | none (searched 'LINE_LANDING_BAR' and 'target < ' in tests/)
sitrep.test.sh | §SHAPE | keep | hooks/poker/sitrep.sh sitrep_render prints the Bottom line's Next bullet before You owe, so "H4 the Bottom line's four bullets answer owe, next, done and close, in that order" goes red. also: H5a proves only the suite's own width measure | none (searched 'Bottom line' in tests/: close-out-4 and handoff-file read the head line only)
sitrep.test.sh | §GRADE | keep | hooks/poker/sitrep.sh:1265 sitrep_grade's names-no-indicator refusal deleted, so a rationale naming no indicator line is recorded; "SL1 … one citing none exits 1, and the page still shows the first grade's letter" goes red | none (searched 'sitrep grade' and 'names no indicator' in tests/)
sitrep.test.sh | §SCOPE | keep | hooks/poker/sitrep.sh sitrep_render reads the owed store of the session running the verb (CLAUDE_CODE_SESSION_ID) instead of the sessions bound to the named plan, so "SC2 …and the same when the verb runs in the other run's session" goes red | none (searched 'owed-' and 'sitrep' in tests/)
sitrep.test.sh | §FORECAST | keep | hooks/poker/sitrep.sh sitrep_close drops the longest-chain term and uses the work over the admitted count alone, so admitting 4 shortens one chain; "FC12 admitted 2 then 4 on one chain: the close does not move" goes red | none (searched 'not before' and 'longest chain' in tests/)
sitrep.test.sh | §LINE | keep | hooks/poker/sitrep.sh:1092-1093 the unapproved plan's ltext reads `closes unverified` instead of `no forecast until approved`, so "L5 an unapproved plan: no forecast, said" goes red | none (searched 'no forecast until approved' in tests/)
sitrep.test.sh | §PACE | keep | hooks/poker/sitrep.sh sitrep_pace divides the queue's ready-to-landed median by the median declared size instead of landed less dispatched over the planned minutes, so "PA1 --basis names this run's pace, 1.5×" reads 0.08× and goes red | none (searched 'dispatch to landing' and 'sitrep_pace' in tests/)
sitrep.test.sh | §FLOOR | keep | hooks/poker/sitrep.sh sitrep_prev drops its same-scale test and lends the newest delivered run at any scale, so "FL1c a delivered run at another scale lends nothing" goes red | none (searched 'not before' and 'sitrep_prev' in tests/)
sitrep.test.sh | §ARGS | keep | hooks/poker/sitrep.sh the verb's operand parser accepts a second --line, so "A1 --line twice is the usage error (2)" goes red. also: A2's 'no plan file at' count is a prose pin beside its exit 2 | none (searched 'sitrep --line' in tests/)
sitrep.test.sh | §SKILL | keep | hooks/poker/sitrep.sh sitrep_render's Score heading drops ` (graded <local time>)` after the letter, so "O4 the verb's page after a grade … the Score heading carrying the letter and time" goes red. also: O2, O3, O3b are prose pins on skills/sitrep/SKILL.md, O6-O9 exercise only the suite's own sr_check | none (searched 'graded ' in tests/)
sitrep.test.sh | §FACTS | duplicate | hooks/poker/sitrep.sh: a page heading renamed, so FA1 goes red | sitrep.test.sh §SKILL
sitrep.test.sh | §SURFACES | keep | hooks/session-poker.sh tick: the poker: sitrep line printed after the decision line, so the tick's last line is no longer decision= (S1) | none (searched 'poker: sitrep' in tests/)
sitrep.test.sh | §GOALS | keep | hooks/poker/sitrep.sh sitrep_goals (line 808) prints a line for a reached goal as well, so "G2 …the reached one is in the count only" goes red | none (searched 'goals — ' in tests/: release-approval reads the goals reader on the card, not the page)
sitrep.test.sh | §REQ-GOALS-1 | keep | payload/scripts/lib/plan.sh plan_goals_read: the theme reader deleted, so a wave plan with no goals: line prints "goals — none declared" ❔; (RG1-1) goes red, and a theme pending past step 6 read ➖ fails RG1-3 | none (searched 'criteria discharged' in tests/)
sitrep.test.sh | §REQ-GOALS-2 | keep | hooks/poker/sitrep.sh sitrep_goals: the measured goals dropped when themes are read, so the unreached handoff line is lost after the theme lines; (RG2-2) goes red, and the Step-1 requirements: pointer unread fails RG2-1 | none (searched 'criteria discharged' in tests/)
sitrep.test.sh | §REQ-GOALS-3 | keep | payload/scripts/lib/plan.sh plan_goals_read: the hand-holds arm deleted, so the landing-report reader asks the measure for minutes and reads unmeasured ❔; (RG3-1) goes red, and a count over the whole record instead of the window fails RG3-3's wording | none (searched 'hand-hold' in tests/sitrep.test.sh; release-approval.test.sh §HANDHOLDS reads the card's line, not the goal)
sitrep.test.sh | §GOAL-MISS | keep | hooks/poker/tick.sh the goal-miss arm never closes decide:goal:<theme> once the goal reads reached, so "GM4 … the tick closes its open decision" goes red | none (searched 'decide:goal' in tests/)
sitrep.test.sh | §ONE-FILE | keep | hooks/poker/sitrep.sh sitrep_render (line 840) hands sitrep_schedule the median over every landing instead of the one-file landings, so "OF1 … the schedule mark reads 10 min" goes red | none (searched 'one-file' and 'sitrep' in tests/)
sitrep.test.sh | §WAIT-WORDS | keep | hooks/poker/sitrep.sh sitrep_render: a proof:review dependency printed as the judge's facts string and record path instead of its words (WW1) | none (searched 'review facts' in tests/)
sitrep.test.sh | §NEXT-STOPS | keep | hooks/poker/sitrep.sh:1156-1168 the stops-ahead arm ignores the release approval card's `replied:` line, so "NX2 …the card replied: Next is still there, and names no stop" goes red | none (searched 'release approval card' in tests/)
sitrep.test.sh | §OPEN-DECISION | keep | hooks/poker/sitrep.sh pages_open (line 340) ignores a `ruled` entry, so the ruled D19 stays owed and "OD4 the same decision ruled: the page owes nothing and says so" goes red | none (searched 'pages_open' and 'reply to D' in tests/: session-poker-5 §ROUNDS reads the decisions line, not the owed list)
sitrep.test.sh | §DECISIONS | keep | hooks/poker/sitrep.sh sitrep_render, the Score: the pages_readings loop deleted, so a landed reading prints no `reading —` line (DE2, DE3); DE1's wait line is also read by sitrep.test.sh §OPEN-DECISION (OD2) | none (searched 'reading — ' in tests/)
sitrep.test.sh | §RECAP | keep | hooks/poker/sitrep.sh poker_verb_resume: the pages_readings loop dropped from the recap, so it prints no `reading:` line for a landed reading (RC2) | none (searched 'reading: ' and 'resume-recap' in tests/)
sitrep.test.sh | §ONCE | keep | payload/scripts/lib/owed.sh owed_key: the `approve:D<n>` fold onto `decide:D<n>` deleted, so the tick's item and the page's decision are two and You owe counts D21 twice (ON1), and the approve verb leaves the tick's item open (ON5) | none (searched 'owed_key' and 'approve:D' in tests/)
sitrep.test.sh | §TITLE | keep | hooks/poker/sitrep.sh sitrep_render: the `work at step` clause of the title deleted, so a plan at step 5 with an active step 7 task names step 5 alone (TI1) | none (searched 'work at step' in tests/)
sitrep.test.sh | §ONE-LINE | keep | hooks/poker/sitrep.sh sitrep_task_lines: the clip's width test `cw(head nm tail) > 92` made unreachable, so a 300-character cell prints whole and the fold continues it onto a second line; "ONE1 a 300-character cell in each state prints one line each" and "ONE5 a 40-task plan … 44 lines" go red | none (searched 'sitrep_task_lines' and 'Task list' in tests/: session-poker-4 reads the recap's task-list: lines, not the page)

## slots.test.sh

slots.test.sh | §RUN | keep | payload/scripts/booked.sh: words after `--` joined into one command instead of refused, so the second word runs as a command (B13.1, B13.2) | none (searched 'one word' and 'SECOND-COMMAND-RAN' in tests/)
slots.test.sh | §LIVE | keep | payload/scripts/lib/slots.sh _slots_live: the start-time comparison dropped, so a reused pid with another start reads live (L1.4) | none (searched '_slots_live' in tests/)
slots.test.sh | §TAKING | keep | payload/scripts/lib/slots.sh: a claim with no pid read as taking whatever its age, so a lock a killed claimer left is never stolen (TK4, TK4a) | none (searched 'taking' and 'orphan' claim rows in tests/)
slots.test.sh | §STAMP | keep | payload/scripts/booked.sh: the dirty count includes the tree's own .bionic link, so a tree whose only untracked path is that link stamps dirty=1 (S7.2) | none (searched 'dirty=0' and 'stamp-dir' stamp rows in tests/)
slots.test.sh | §NESTED-ENV | keep | payload/scripts/booked.sh: BIONIC_GATE_ADMIT not honoured, so a booked command nested in one asks the gate and waits on its parent (N3.2, N3.3) | none (searched 'BIONIC_GATE_ADMIT' nested rows in tests/)
slots.test.sh | §SHELL | keep | payload/scripts/booked.sh: the stamp's cmd= written from the --shell form instead of the original command, so it carries eval (H3.3, H3.4) | none (searched '--shell' stamp rows in tests/)

## spawn-worktree.test.sh

spawn-worktree.test.sh | §Group 1 | duplicate | payload/scripts/spawn-worktree.sh made not to parse, so create exits non-zero and no tree is made | spawn-worktree.test.sh §Group 3
spawn-worktree.test.sh | §Group 2 | duplicate | payload/scripts/spawn-worktree.sh create: exits non-zero on a valid base and branch, so no tree is made | spawn-worktree.test.sh §Group 3
spawn-worktree.test.sh | §Group 3 | keep | payload/scripts/spawn-worktree.sh create: the .bionic alias not planted, so a relative record write from inside the tree lands in the tree, not the main checkout | none (searched 'alias=' and '.bionic symlink' with spawn-worktree.sh create in tests/)
spawn-worktree.test.sh | §Group 4 | keep | payload/scripts/spawn-worktree.sh create: the tree checked out at HEAD instead of the requested older base | none (searched 'create "\$OLD' in tests/)
spawn-worktree.test.sh | §Group 5 | keep | payload/scripts/spawn-worktree.sh create: a relative parent resolved against the caller's cwd instead of the repository root, so the tree lands under sub/custom-trees | none (searched 'custom-trees' and 'rel-parent' in tests/)
spawn-worktree.test.sh | §Group 6 | keep | payload/scripts/spawn-worktree.sh create: the main root taken from the cwd's toplevel, so a create from inside a worktree nests a .worktrees directory there | none (searched 'SIBLING' and 'nested .worktrees' in tests/)
spawn-worktree.test.sh | §Group 7 | keep | payload/scripts/spawn-worktree.sh create: the `..` component check on the parent dropped, so `../outside` is created outside the repository | none (searched 'escapee' and 'reason=' refusals of create in tests/)
spawn-worktree.test.sh | §DISK | keep | payload/scripts/spawn-worktree.sh create: the disk-low refusal dropped, so free 5 KB under a 9 KB tree makes a tree (DISK.1) | none (searched 'disk-low' and 'BIONIC_PROBE_DISK_FREE_KB' in tests/)
spawn-worktree.test.sh | §Group 8 | keep | payload/scripts/spawn-worktree.sh create: the alias planted over a branch's tracked .bionic, so the branch's own state file is clobbered by a link | none (searched 'tracked-state' and 'mispointed' in tests/)
spawn-worktree.test.sh | §Group 9 | keep | payload/scripts/spawn-worktree.sh remove: the branch deleted with the tree, so wt work is no longer reachable | none (searched 'spawn-worktree.sh remove' and 'REMOVED' in tests/)
spawn-worktree.test.sh | §Group 10 | keep | payload/scripts/spawn-worktree.sh create: `cleanup_partial` dropped on a failed HEAD readback, so the unattested tree and its branch survive the refusal (live build and mutation 3); also the head read from the argument | none (searched 'cleanup_partial' and 'attested-blindly' in tests/)
spawn-worktree.test.sh | §Group 11 | duplicate | payload/scripts/spawn-worktree.sh create: `wt="${parent_abs}/${branch##*/}"` built from anything but the branch's last segment, so path= and branch= part | spawn-worktree.test.sh §Group 5
spawn-worktree.test.sh | §Group 12 | keep | rule: door refusal — payload/scripts/spawn-worktree.sh land: the check for a tests/run.sh floor in the checkout holding the working branch dropped, so wt/20-T2 lands instead of HELD exit 2 with no ref moved | none (searched 'HELD wt/' and 'land .* --by-hand' in tests/; tests/worktree.test.sh drives the library arms)
spawn-worktree.test.sh | §WS | keep | payload/scripts/spawn-worktree.sh create: the workspace/v1 line not appended on `--for`, so workspace_for_name answers no tree for w25-T1 | none (searched 'workspace/v1' writes by create in tests/; permission-answer.test.sh plants the line by hand)

## stop-check.test.sh

stop-check.test.sh | §Section 1 | keep | payload/hooks/stop-check.sh: a typed agent id resolved to the roster's last row of that name, so the first twin's machine line records the second twin's id (target=$AIDA row) | none (searched 'twin' and 'target=' in tests/; cross-gate-agreement-1.test.sh §C resolves names only)
stop-check.test.sh | §Section 2 | keep | payload/hooks/stop-check.sh: the agent's last assistant message no longer read from its working log, so "I already completed this review" is not printed; the page is the only carrier and the words change with the log | none (searched 'I already completed this review' in tests/)
stop-check.test.sh | §Section 4 | keep | payload/hooks/stop-check.sh: the projects root taken from a seam instead of derived from claude_home, so an agent found only outside this project's slug does not resolve | none (searched 'projects root' with stop-check.sh in tests/)
stop-check.test.sh | §Section 5 | keep | payload/hooks/stop-check.sh: the typed target expanded unquoted in the transcript search, so a glob target `*` resolves (the glob row) | none (searched 'glob target' in tests/)
stop-check.test.sh | §Section 6 | keep | payload/hooks/stop-check.sh: a record/-led progress path resolved against the repository root, so a root copy answers for it (the record/-led row) | none (searched 'progress_state=' in tests/; cross-gate-agreement-1.test.sh §C reads flag forms only)
stop-check.test.sh | §Section 7 | keep | payload/hooks/stop-check.sh: a deliverable path carrying a pipe written raw into the machine line, so it forges a field (the pipe row) | none (searched 'forge a field' and 'stop-check-observation/' in tests/)
stop-check.test.sh | §Section 8 | keep | payload/hooks/stop-check.sh: the roster row's deliverable not read when no argument names one, so deliverable_source=roster goes red (OURS rows); also P2's claimed pattern ignored, so a live matching process reads live: no | none (searched 'deliverable_source=roster' and 'live:     yes' in tests/)
stop-check.test.sh | §Section 9 | keep | payload/hooks/stop-check.sh: records left on disk under this session taken as evidence an agent runs, so the D3 target resolves (exit 0) | none (searched 'records on disk are not evidence' in tests/; cross-gate-agreement-1.test.sh §E reads an unconfirmed row's name, not on-disk records)

## stop-guard.test.sh

stop-guard.test.sh | §Section 1 | keep | hooks/stop-guard.sh: the TOOL_NAME = TaskStop relevance test moved below the bionic_context call, so every PreToolUse pays the context resolution; ("relevance check precedes the context resolution in source order") goes red. also: the unrelated-tool rows are caught by fail-direction-table.test.sh §7 rows driven as behaviour (AC-10) | none (searched 'TOOL_NAME" = "TaskStop' in tests/)
stop-guard.test.sh | §Section 2 | vacuous | a setup_section tombstone for the writing that moved to execution-recorder.sh: it builds nothing a later section reads and asserts nothing | none (searched 'WRITING moved out' in tests/)
stop-guard.test.sh | §Section 3 | vacuous | a setup_section tombstone for the retired observation record: it builds nothing a later section reads and asserts nothing | none (searched 'THE OBSERVATION RECORD IS GONE' in tests/)
stop-guard.test.sh | §Section 4 | duplicate | hooks/stop-guard.sh: the empty-target and no-standing refusals deleted; its engagement check deleted; payload/scripts/lib/run.sh:860 the symlinked-marker refusal deleted; a quiet target refused | fail-direction-table.test.sh §7 rows driven as behaviour (AC-10), cross-gate-agreement-1.test.sh §A1, canonical-sdlc-evidence-gate-2.test.sh §Section 34, stop-guard.test.sh §Section 5
stop-guard.test.sh | §Section 4a | duplicate | hooks/stop-guard.sh: the bash-task passthrough refused or left unlogged; an address-shaped target waved through | stop-guard.test.sh §BID, fail-direction-table.test.sh §7 rows driven as behaviour (AC-10)
stop-guard.test.sh | §BID | keep | hooks/stop-guard.sh: the transcript's backgroundTaskId lookup deleted, so an off-shape id the harness recorded is refused; ("bid2b …and once the transcript records backgroundTaskId xq7mkd2wx: PASSES THROUGH") goes red | none (searched 'backgroundTaskId' in tests/)
stop-guard.test.sh | §Section 5 | keep | hooks/stop-guard.sh: the row's own cadence ignored for a fixed window, so a minute of quiet against a one-second cadence still reads alive; ("AC-2.2 control: a minute of quiet against a one-second cadence is IDLE: PERMITTED") goes red | none (searched 'inside the declared cadence' in tests/)
stop-guard.test.sh | §Section 6a | keep | hooks/stop-guard.sh: the refusal's Fix line printed with bracketed placeholders, so running it as printed reports absent deliverables; ("running the fix line as printed produces no usage error") goes red | none (searched 'stop-check.sh' fix-line execution in tests/)
stop-guard.test.sh | §Section 6b | vacuous | a setup_section tombstone for the retired consume: it builds nothing a later section reads and asserts nothing | none (searched 'THE CONSUME IS GONE' in tests/)
stop-guard.test.sh | §Section 7 | keep | hooks/stop-guard.sh: the readable test on the roster deleted, so a mode-000 roster leaves a bare-name stop unguarded; ("an UNREADABLE roster refuses the stop, exactly as a symlinked one does") goes red. also: the mktemp and $$ source greps are tombstones | none (searched 'chmod 000' roster rows in tests/)
stop-guard.test.sh | §Sections 8 and 9 | vacuous | a setup_section tombstone for D-3 and D-6: it builds nothing a later section reads and asserts nothing | none (searched 'D-3 AND D-6 ARE GONE' in tests/)

## stop-orders.test.sh

stop-orders.test.sh | §Section 1 | keep | payload/hooks/stop-orders.sh: the `[ ! -L ]` refusal of a symlinked orders file dropped, so the order is written through the link instead of exit 2 | none (searched 'orders' symlink rows in tests/)
stop-orders.test.sh | §Section 2 | keep | payload/hooks/stop-orders.sh order: the --by value check dropped, so `--by robot` is recorded instead of refused exit 2, and a refused order writes its target line | none (searched 'by=patrol' and '--by' with stop-orders.sh in tests/)
stop-orders.test.sh | §Section 3 | keep | payload/hooks/stop-orders.sh standdown: a contract-less row's vacuous MET taken as a landing, so declares-nothing enters the batch without an ack | none (searched 'row(s) have landed' and 'declares-nothing' in tests/)
stop-orders.test.sh | §Section 3b | keep | payload/hooks/stop-orders.sh standdown: an adopted row's carried waiver not read, so the freshly adopted waived row is left out of the batch after a /clear | none (searched 'CARRIED waiver' and 'adopted' with standdown in tests/)
stop-orders.test.sh | §Section 4 | keep | payload/hooks/stop-orders.sh: the root taken from the worktree cwd's toplevel instead of project_root, so standdown from a linked worktree reads no roster | none (searched 'worktree' with stop-orders.sh in tests/)
stop-orders.test.sh | §Section 6 | keep | payload/hooks/stop-orders.sh standdown: the roster mark no longer makes a row stoppable, so a marked row whose deliverable is absent is not listed to stop | none (searched 'roster mark' and 'LANDED branch=' with standdown in tests/)
stop-orders.test.sh | §Section 7 | keep | payload/hooks/stop-orders.sh standdown: a held row's name matched against the panel as a regex, so a name carrying a metacharacter is annotated live off its neighbour | none (searched '\[live\]' and '\[not live\]' in tests/)
stop-orders.test.sh | §Section 8 | keep | payload/hooks/stop-orders.sh stopped: an UNMET row a fresh panel still lists acked instead of refused exit 2 (C4) | none (searched 'stopped' and 'reason abandoned' in tests/)
stop-orders.test.sh | §Section 9 | keep | payload/hooks/stop-orders.sh stopped: a claimed-process STILL-LIVE row acked once the panel shows it gone, instead of refused naming the claim | none (searched 'claimed process pattern' in tests/)

## stop.test.sh

stop.test.sh | §1 | keep | hooks/stop.sh's bionic_fold manifest lists stop_patrol_revive ahead of stop_landing_gate, so "1d: …and in the manifest's order, landing before patrol, by offset" goes red | none (searched 'bionic_fold' and 'LANDING CONTRACT UNMET' in tests/: fold.test.sh drives stubs, landing-gate and patrol-revive one arm each)
stop.test.sh | §2 | keep | payload/scripts/lib/stop.sh: the unbound advisory written straight to stderr instead of staged through the fold, so it prints ahead of the landing refusal (2e) | none (searched 'newest-plan fallback' in tests/)
stop.test.sh | §3 | duplicate | each arm's engagement check deleted, so a bystander's turn end speaks; a library on the Stop path writes to stderr when loaded (3c) | context-spend.test.sh §Group 2, patrol-duties-gate.test.sh §Section 3, landing-gate.test.sh §Section 5, landing-gate.test.sh §Section 1
stop.test.sh | §4 | keep | payload/scripts/lib/stop.sh stop_patrol_duties: the session's run resolved, announcing the unbound advisory, before its SubagentStop return, so the advisory prints on a worker's stop (4b) | none (searched 'session unbound' in tests/)
stop.test.sh | §5 | duplicate | hooks/stop.sh: the stop_hook_active guard ahead of the fold deleted, so the landing arm, which carries no guard of its own, refuses the re-entry (5a) | landing-gate.test.sh §Section 1
stop.test.sh | §7 | keep | payload/scripts/lib/stop.sh stop_patrol_duties: a row ledgered active still counts as ready, so the turn that dispatched T13 is refused for the fill (7f) | none (searched 'ready with room' in tests/)
stop.test.sh | §8 | keep | payload/scripts/lib/stop.sh stop_landing_gate prints its `session-poker.sh … amend` fix line with the script path unquoted, so a plugin root holding a space splits it; "8b2: critic I2 the pasted line's script is one argument" goes red | none (searched 'my plugin' and 'amend' in tests/landing-gate.test.sh and tests/)
stop.test.sh | §9 | keep | payload/scripts/lib/stop.sh the fill refusal stops subtracting the turn's launches by dispatch name, so the launched T13 is named as missed; "9e: T11b the row this turn launched is never named as missed" goes red | none (searched 'ready with room' and 'idle=' in tests/)
stop.test.sh | §GAP | keep | payload/scripts/lib/stop.sh the fill refusal names min(free, ready) rows instead of every unanswered ready row, so one free slot names T13 alone; "GAP2h meta: the reason is the refusal's" and "GAP2f … decline for all three" go red | none (searched 'ready with room' and 'decline T13,T14' in tests/: §9's fixtures have room for every row)
stop.test.sh | §UB | keep | payload/scripts/lib/stop.sh the fill duty charges a session whose run is the newest-plan fallback as if it were bound, so B is refused for p1's T5; "UB1: B (plan=none) ends its turn — exit 0" goes red | none (searched 'newest-plan fallback' and 'ready with room' in tests/)
stop.test.sh | §SD | keep | payload/scripts/lib/stop.sh the ledger's decline reader takes any non-empty `declined=` as an answer, so a pre-upgrade `declined=—` stands; "SD7: C4 a pre-upgrade declined=— does not stand" goes red | none (searched 'declined=' and 'fill-declined' in tests/)

## time.test.sh

time.test.sh | §AGREE | keep | payload/scripts/lib/time.sh iso_epoch: the trailing-Z check loosened, so `2026-10-18T15:07:33Zx` reads an epoch on all four callers instead of nothing (AG.8) | none (searched 'iso_epoch' in tests/)
time.test.sh | §TRANSCRIPT | keep | payload/scripts/lib/patrol.sh patrol_verdict: a millisecond timestamp not cut to the whole second, so the fractional turns read unreadable instead of dead with gap 600 (TR.1) | none (searched 'patrol_verdict' fractional rows in tests/)

## units.test.sh

units.test.sh | §0 | duplicate | payload/scripts/lib/units.sh: a top-level line writes to stderr or stdout when sourced; the file does not parse, or loses units_rows | landing-gate.test.sh §Section 1, units.test.sh §1
units.test.sh | §1 | keep | payload/scripts/lib/units.sh units_rows (line 397) pipes its rows through sort, so they come out in id order; "rows come out in TABLE order — T22 is 21st and T21 is 22nd" goes red while §2 and §3 compare two sorted outputs and stay green | none (searched 'units_rows' in tests/: units.test.sh alone)
units.test.sh | §2 | keep | payload/scripts/lib/units.sh units_field_v (line 370) maps `rigor` to slot 3 again (the retired A-39 alias), so "…and refuses rigor, a name the contract no longer carries (rc 1)" goes red | none (searched 'units_field' in tests/: units.test.sh alone)
units.test.sh | §3 | keep | payload/scripts/lib/units.sh _units_read takes the first table with an id header without requiring it under `## Tasks`, so the retired `## Slices` decoy above it is read as the table and "…over 22 real rows" goes red | none (searched 'units_rows' and 'Slices' in tests/)
units.test.sh | §4 | keep | payload/scripts/lib/units.sh the ready program's no-dependency test stops treating a bare `-` cell as empty, so T2 of ready-dashes.md is never ready; "an em dash, a hyphen and an empty cell all mean no dependency" goes red | none (searched 'units_ready' and 'a bare hyphen deps cell' in tests/)
units.test.sh | §5 | keep | payload/scripts/lib/units.sh:1983 units_validate's status list loses `active`, so the live specimen's two active rows draw violations; "the live table breaks no invariant — zero lines" goes red | none (searched 'units_validate' in tests/: regression-rename and refuse fixtures hold no active row)
units.test.sh | §6 | keep | payload/scripts/lib/units.sh:1996 units_validate's duplicate-id printf deleted, so "an id used twice is named once, as a duplicate" goes red | none (searched 'duplicate id' and 'units_validate' in tests/)
units.test.sh | §6b | duplicate | payload/scripts/lib/units.sh units_validate gains back the retired every-Step-4-row transitive rule, so 6b.1's Step-5 row reaching one Step-4 row of two is refused | units.test.sh §6
units.test.sh | §7 | keep | payload/scripts/lib/units.sh units_validate's `## Tasks: missing column <name>` line deleted, so "a schema with no step column is refused, naming the column" goes red | none (searched 'missing column' in tests/)
units.test.sh | §8 | keep | payload/scripts/lib/units.sh:1702 the gate test drops `knd[i] == "integrate"`, so the Step-8 integrate row is ready at Step 4; "…units_ready at Step 4 does not: a gate act waits for its step" goes red | none (searched 'gate act' and 'integrate' in tests/: session-poker-2 §Section 37 holds only a Step-7 doc row)
units.test.sh | §9 | keep | payload/scripts/lib/units.sh _units_read's trim() restores only the first escaped pipe of a cell (sub for gsub), so "a cell carrying two escaped pipes reads back with both" goes red | none (searched 'units_rows' in tests/: units.test.sh alone; session-poker-2 §Section 37 carries one escaped pipe per cell)
units.test.sh | §ORDER | keep | payload/scripts/lib/units.sh units_order drops `$2 + 0 <= 5`, so a regression row at Step 7 is read as the order; "ORD-2b …and units_order reads no order" goes red | none (searched 'units_order' in tests/: canonical-sdlc-evidence-gate-2 §AH and session-poker-4 assert only an ordered plan)
units.test.sh | §POST | keep | payload/scripts/lib/units.sh units_validate: the release-landed test dropped from the post-release admission, so a reader past a release that is still open is admitted instead of refused with the order text (POST-2) | none (searched 'the release row comes ahead' and 'units_add_row' in tests/)
units.test.sh | §JUDGE | keep | payload/scripts/lib/line.sh _line_proved matches its commit argument against a verdict's reads= key as well as commit=, so "…and a reads key in its place is refused" goes red | none (searched '_line_proved' and '_proof_floor_judge' in tests/: landing-line-2 §GRAMMAR reads field order only)
units.test.sh | §WALK | keep | payload/scripts/lib/proof.sh _proof_past_f: the release-set question asked through the docs class again, so CHANGELOG.md reads as prose and a real release merge with a check passing at it is named not proved (WALK-0, WALK-1b to WALK-3b) | none (searched '_proof_past_f' in tests/)

## version-compare.test.sh

version-compare.test.sh | §Section 1 | keep | payload/scripts/lib/detect.sh version_compare: the comparison made lexical, so "4: 1.10.0 vs 1.9.0 -> ahead (numeric, not lexical)" reads lag | none (searched 'version_compare' in tests/; doctor-version.test.sh §Section 10 compares a version against 0.0.1, where lexical and numeric agree)
version-compare.test.sh | §Section 2 | duplicate | payload/scripts/lib/detect.sh detect_plugin_latest: the ahead, current or lag state word misreported, which doctor's version row renders | doctor-version.test.sh §Section 10, doctor-version.test.sh §Section 1, doctor-version.test.sh §Section 2

## width.test.sh

width.test.sh | §Section 1 | keep | payload/scripts/lib/width.sh bionic_cols: '×' left out of the closed set, so it measures 2 under LC_ALL=C (1c.×) | none (searched 'bionic_cols' in tests/; refuse.test.sh §T47 measures é and 日, which are outside the set)
width.test.sh | §Section 2 | keep | rule: lint — a glyph outside width.sh's closed set planted in a printed row of doctor.sh, setup.sh or card.sh, so the sweep names it with its width | none (searched 'row_glyphs' and 'closed set' in tests/)
width.test.sh | §Section 3 | duplicate | payload/scripts/lib/width.sh bionic_trunc: the cut made by bytes under LC_ALL=C, so a cut through a multi-byte character leaves invalid UTF-8 and passes its budget | refuse.test.sh §T47
width.test.sh | §Section 3b | keep | payload/scripts/lib/width.sh bionic_trunc: a budget of 0 or less read as zero columns instead of unbounded, so "abc" cuts to "…" (7p6, 7p7) | none (searched 'bionic_trunc' in tests/; refuse.sh checks its own floor before the call)
width.test.sh | §Section 4 | keep | payload/scripts/lib/width.sh bionic_line: the cut taken from the instruction instead of the label, so " → run /bionic:setup" does not survive (9) | none (searched 'bionic_line' in tests/)
width.test.sh | §Section 5 | keep | payload/scripts/lib/width.sh bionic_wrap: an over-long word dropped instead of split at the budget (13) | none (searched 'bionic_wrap' in tests/; doctor-version.test.sh reads doctor's rows, not the fold)

## worktree.test.sh

worktree.test.sh | §Group 1 | duplicate | payload/scripts/lib/worktree.sh: worktree_land_for_session, worktree_checkout_of or worktree_lease_overruns renamed or the file made unparseable | worktree.test.sh §Group 3
worktree.test.sh | §Group 2 | keep | payload/scripts/lib/worktree.sh worktree_legacy_links: a link whose target is gone skipped, so the two stale and broken links list one (the two-listed row) | none (searched 'worktree_legacy_links' in tests/; doctor-fleet.test.sh §Section 6 and session-start.test.sh §5 plant no broken link)
worktree.test.sh | §Group 3 | keep | payload/scripts/lib/worktree.sh worktree_land: the merge made with --ff, so the landing is no two-parent merge commit (the --no-ff row) | none (searched 'merge alpha (land)' in tests/)
worktree.test.sh | §Group 3b | keep | payload/scripts/lib/worktree.sh worktree_land: the .bionic alias counted as an untracked entry, so a tree whose only untracked entry is the alias is refused dirty | none (searched 'land-with-alias' in tests/)
worktree.test.sh | §Group 4 | keep | rule: door refusal — payload/scripts/lib/worktree.sh worktree_land: untracked files no longer counted dirty, so a tree with an untracked file lands instead of REFUSED reason=dirty-tree | none (searched 'reason=dirty-tree' in tests/)
worktree.test.sh | §Group 4b | keep | rule: door refusal — payload/scripts/lib/worktree.sh worktree_land: the master arm of the protected-branch check deleted, so landing onto master merges instead of REFUSED reason=protected-branch | none (searched 'reason=protected-branch' in tests/)
worktree.test.sh | §Group 5 | keep | rule: door refusal — payload/scripts/lib/worktree.sh _wt_runner_script: an interpreter option before tests/run.sh not skipped, so `bash -o pipefail tests/run.sh` in the root no longer refuses the land | none (searched '_wt_runner_script' in tests/)
worktree.test.sh | §LAND-BUSY-GATE | keep | rule: door refusal — payload/scripts/lib/worktree.sh: the gate's admitted requests not read, so an admitted run in the main checkout lets the land through (the request=7 row) | none (searched 'request=7 key=' in tests/)
worktree.test.sh | §Group 6 | keep | payload/scripts/lib/worktree.sh worktree_land: the worktree prune after the removal dropped, so a stale administrative entry survives the landing | none (searched 'stale administrative entry' in tests/)
worktree.test.sh | §Group 7 | keep | rule: door refusal — payload/scripts/spawn-worktree.sh land: the bound-session check dropped, so the verb from an unbound session lands instead of refusing (the unbound row, no ref moved) | none (searched 'spawn-worktree.sh land' unbound rows in tests/)
worktree.test.sh | §BY-HAND | keep | rule: door refusal — payload/scripts/spawn-worktree.sh land: --by-hand with no --reason admitted, so a hand landing records nothing of why instead of REFUSED reason=no-reason (h1) | none (searched 'reason=no-reason' in tests/)
worktree.test.sh | §HAND | keep | rule: door refusal — payload/scripts/lib/line.sh: the comment lint skipped on a hand landing, so an added comment citing the run lands instead of exit 2 with ready's LINT line (hl1) | none (searched 'LINT wt/' in tests/)
worktree.test.sh | §CLOSURE | keep | payload/scripts/lib/worktree.sh _wt_check_loads: a for-loop word list or a $HERE assignment left unread, so a library the check sources is no member of its closure and a landing that changes it names no changed-here (cl1) | none (searched '_wt_check_closure' in tests/)

## Culled

agent-context-guard.test.sh §G0 — duplicate
agent-context-guard.test.sh §G7 — duplicate
agent-context-guard.test.sh §G9 — duplicate
archive.test.sh §0 — duplicate
archive.test.sh §5 — duplicate
archive.test.sh §6 — duplicate
archive.test.sh §7 — vacuous
background-suite-guard.test.sh §B0 — duplicate
background-suite-guard.test.sh §B3 — duplicate
background-suite-guard.test.sh §B5 — duplicate
background-suite-guard.test.sh §B7 — duplicate
background-suite-guard.test.sh §B10 — duplicate
background-suite-guard.test.sh §B11 — duplicate
bash-walls.test.sh §1 — duplicate
bash-walls.test.sh §5 — duplicate
bash-walls.test.sh §6 — duplicate
bash-walls.test.sh §7 — duplicate
bash-walls.test.sh §8 — duplicate
bash-walls.test.sh §11 — duplicate
bash-walls.test.sh §12 — duplicate
binding.test.sh §1 — duplicate
binding.test.sh §4 — duplicate
booked.test.sh §WALL — duplicate
canonical-sdlc-evidence-gate.test.sh §Section 3 — duplicate
canonical-sdlc-evidence-gate.test.sh §Section 4 — duplicate
canonical-sdlc-evidence-gate.test.sh §Section 6 — duplicate
canonical-sdlc-evidence-gate.test.sh §Section 7 — duplicate
canonical-sdlc-evidence-gate.test.sh §Section 8 — duplicate
close-out-1.test.sh §0n — duplicate
close-out-1.test.sh §3 — duplicate
close-out-1.test.sh §4b — duplicate
close-out-1.test.sh §FIX-SHAPE — vacuous
close-out-4.test.sh §APPROVED-HEAD — duplicate
cmd-class.test.sh §C0 — duplicate
cmd-class.test.sh §C2/C3 — duplicate
cmd-class.test.sh §C5 — duplicate
cmd-class.test.sh §C6 — the session never invoked the skill: neither hook is there (AC-6, AC-20) — duplicate
commands.test.sh §Section 2 — duplicate
commands.test.sh §Section 3 — duplicate
commands.test.sh §Section GH-none — duplicate
commands.test.sh §Section 5 — duplicate
context-spend.test.sh §Group 5 — duplicate
context.test.sh §1 — duplicate
context.test.sh §5 — duplicate
cross-gate-agreement-1.test.sh §A2 — duplicate
cross-gate-agreement-1.test.sh §A3 — duplicate
cross-gate-agreement-1.test.sh §C — duplicate
cross-gate-agreement-2.test.sh §S13c — duplicate
decision-skill.test.sh §REACH — prose pin
decision-skill.test.sh §NUMBER — prose pin
decision-skill.test.sh §GOAL — prose pin
decision-skill.test.sh §BATCH — prose pin
decision-skill.test.sh §ALTITUDE — prose pin
decision-skill.test.sh §EXAMPLES — prose pin
decision-skill.test.sh §CLIMB — prose pin
detect-probes.test.sh §Group 1 — duplicate
detect-probes.test.sh §Group 6f — duplicate
detect-probes.test.sh §Group 7 — vacuous
detect.test.sh §LOADED — the field reader — duplicate
dispatch-preflight-2.test.sh §S2 — duplicate
dispatch-preflight-2.test.sh §S3 — duplicate
dispatch-preflight-2.test.sh §S4 — duplicate
dispatch-preflight-2.test.sh §S6 — duplicate
dispatch-preflight-2.test.sh §S6b — duplicate
dispatch-preflight-2.test.sh §S6c — duplicate
dispatch-preflight-2.test.sh §S7 — duplicate
dispatch-preflight-2.test.sh §S9 — duplicate
dispatch-preflight-2.test.sh §S10d — duplicate
dispatch-preflight-4b.test.sh §RIGOR — duplicate
dispatch-preflight.test.sh §S22b — duplicate
dispatch-preflight.test.sh §budget-markers — duplicate
doctor-patrol.test.sh §Section 8 — duplicate
doctor-restart.test.sh §Section 2 — duplicate
doctor-version.test.sh §Section 3 — duplicate
doctor-version.test.sh §Section 12 — duplicate
doctor-walls.test.sh §Section 1 — duplicate
doctor-walls.test.sh §Section 4 — duplicate
doctor-walls.test.sh §Section 5 — duplicate
doctor.test.sh §LOADED — no record: the registry's line — duplicate
doctor.test.sh §LOADED — a record that is not a live session's, or names no checkout — duplicate
door-landing.test.sh §WORLD: the fixture carries the check's closure, the real changelog and a relative declaration — vacuous
door-landing.test.sh §WORLD: the fixture carries the check's closure, the real changelog and a relative declaration — tally
engage.test.sh §E4 (AC-4) — duplicate
engage.test.sh §E7 — duplicate
execution-recorder.test.sh §Sections 2-5 — vacuous
fail-direction-table.test.sh §the missing session key — duplicate
fail-direction-table.test.sh §the producer's two rows (§7 rows 4 and 5) — duplicate
farm-out-reminder.test.sh §0 — duplicate
fold.test.sh §2 — duplicate
fold.test.sh §4 — duplicate
fold.test.sh §5 — duplicate
fold.test.sh §6 — duplicate
fold.test.sh §8 — duplicate
framework.test.sh §8 — prose pin
framework.test.sh §PIN-REL — prose pin
git-argv.test.sh §Section 1d — duplicate
grant.test.sh §G9 a reserved denial names the category and the human, and carries no file route — duplicate
handoff-file.test.sh §BRANCH-AGREE — duplicate
hook-adoption.test.sh §0 — duplicate
hook-adoption.test.sh §5 — duplicate
hook-adoption.test.sh §5c — duplicate
hook-latency.test.sh §3 — vacuous
hook-latency.test.sh §7 — vacuous
hook-latency.test.sh §8 — vacuous
hook-timeout.test.sh §3 — duplicate
interpreter-pin.test.sh §3 the planted 3.2 incompatibilities — duplicate
interpreter-pin.test.sh §6 one pin, one owner — vacuous
jit.test.sh §Group 1 — duplicate
jit.test.sh §Group 3 — duplicate
jit.test.sh §Group 7 — duplicate
landing-gate.test.sh §Section 5 — duplicate
landing-gate.test.sh §Section 10 — duplicate
landing-line-1.test.sh §ALONE — duplicate
landing-line-1.test.sh §RELEASE-ROW — duplicate
landing-line-2.test.sh §LABELS — duplicate
landing-line-2.test.sh §DEBT-LINE — duplicate
landing-line-2.test.sh §REVIEW-BORN — duplicate
landing-line-2.test.sh §FIELDS — duplicate
live-agents.test.sh §A — duplicate
live-agents.test.sh §F — duplicate
live-agents.test.sh §G — duplicate
live-agents.test.sh §M — duplicate
notify.test.sh §ASKS mutants — duplicate
patrol-duties-gate.test.sh §Section 1 — duplicate
patrol-duties-gate.test.sh §Section 5 — duplicate
patrol-revive.test.sh §Group 1 — duplicate
patrol-revive.test.sh §Group 5 — duplicate
patrol-stale.test.sh §Section 1 — duplicate
permission-answer.test.sh §A1 the lead's question is answered — duplicate
permission-answer.test.sh §A7 the incident command is denied with a fix naming the unread target — duplicate
permission-answer.test.sh §A19 a delete of a workspace root itself is denied; beneath it is allowed — duplicate
permission-effects.test.sh §E0 the fixture — duplicate
placement.test.sh §P0 — duplicate
preflight-probe.test.sh §S10 — the sweeper arm line is GONE (epic-16 w2 task S1) — duplicate
principles-item.test.sh §the shipped text and the extractor — duplicate
protect-main.test.sh §Section 4 — duplicate
protect-main.test.sh §Section 5 — duplicate
protect-main.test.sh §Section 6 — duplicate
protect-main.test.sh §Section 7 — duplicate
protect-main.test.sh §the unengaged session — duplicate
rc-item-1.test.sh §detect — duplicate
rc-item-2.test.sh §wave-27 T75: bionic's claude() block clears the name it defines (A-orch-185) — duplicate
regression-rename.test.sh §AGREE-ONE — duplicate
release-check.test.sh §STRIKE — prose pin
release-check.test.sh §ENTRY-1.18.0 — prose pin
release-check.test.sh §ADR — prose pin
release-check.test.sh §REL-1.20.0 — prose pin
release-check.test.sh §REVERSE — prose pin
release-check.test.sh §REL-1.23.0 — prose pin
render.test.sh §Section 2 — duplicate
render.test.sh §Section 10 — vacuous
render.test.sh §Section 11 — prose pin
render.test.sh §Section 12 — duplicate
render.test.sh §Section 13 — duplicate
render.test.sh §Section 14 — prose pin
render.test.sh §Section 15 — vacuous
root.test.sh §0 — duplicate
roots.test.sh §1 — duplicate
roots.test.sh §2a — duplicate
roster.test.sh §R0 — duplicate
roster.test.sh §R12 — prose pin
run-predicate.test.sh §R0 — duplicate
run-predicate.test.sh §R1 — duplicate
run-predicate.test.sh §R2 — duplicate
run-predicate.test.sh §R3 — duplicate
runner-roster.test.sh §1 the roster is the directory — duplicate
runner-width.test.sh §NO-RETRY a suite red once stays red in the log, run once (wave-35 T2; D11, AC-2.4) — duplicate
scale-profile.test.sh §TABLE — duplicate
seam-resolution.test.sh §Group 1 — duplicate
seam-resolution.test.sh §Group 4 — duplicate
session-poker-5.test.sh §WORD — duplicate
session-start.test.sh §10 — duplicate
session-sweep.test.sh §7. session-start.sh's own silent auto-sweep (R2, ticket-30, AC-R2.1/2.2/2.3) — duplicate
session-sweep.test.sh §7b. AC-R2.2 — duplicate
session.test.sh §Group 0 — duplicate
sitrep.test.sh §FACTS — duplicate
spawn-worktree.test.sh §Group 1 — duplicate
spawn-worktree.test.sh §Group 2 — duplicate
spawn-worktree.test.sh §Group 11 — duplicate
stop-guard.test.sh §Section 2 — vacuous
stop-guard.test.sh §Section 3 — vacuous
stop-guard.test.sh §Section 4 — duplicate
stop-guard.test.sh §Section 4a — duplicate
stop-guard.test.sh §Section 6b — vacuous
stop-guard.test.sh §Sections 8 and 9 — vacuous
stop.test.sh §3 — duplicate
stop.test.sh §5 — duplicate
units.test.sh §0 — duplicate
units.test.sh §6b — duplicate
version-compare.test.sh §Section 2 — duplicate
width.test.sh §Section 3 — duplicate
worktree.test.sh §Group 1 — duplicate
