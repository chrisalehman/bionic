---
governing-skill: agent-skills:documentation-and-adrs
sdlc-step: 7
epic: epic-23-bionic-tech-debt
wave: wave-51-gaps-closed
intent: build
rigor: double
scale: wave
canonical_sdlc_version: 15
surface_type: cli-plugin
language: bash
has_ui: false
multi_agent: true
deploy_target: n/a
cleanup_on_finish: true
use_worktree: false
walk: required
design-interview: true
model_plan: orchestrator=claude-fable-5-2; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=haiku-high; auditor=opus-high; critic=opus-high
status: Proposed (Step 7, 2026-11-20)
created: 2026-11-18
---
# ADR-079 — A run is vouched for

## Status

**Proposed** (Step 7, 2026-11-20). Drafted at Step 2 on 2026-11-18, and brought to what was built at the settled head of wave 51, after the walks and the reviews of the whole. It rests on calls in wave 51's log that the orchestrator made under the person's standing order to decide what can be reverted: D2, D3, D7, D8 and D11 (2026-11-18). The design's defaults D13 to D21 were approved at the design card. The person's ruling D36 (2026-11-19) took the run as it stood after an honest write of the plan was caught, and the repair of that catch is item 2 below. It extends ADR-078 and supersedes nothing.

## Context

ADR-078 made a run's log and plan the only homes of its facts, and the commit gate judges a session's commits against them. 2.0.0 shipped with the gate trusting those files as it finds them. Six roads round it were found before the release and more after (record/wave-51-gaps-closed/research-guard.md):
- the plan removed or renamed reads as a closed run;
- the log removed or emptied reads as a run at step 0;
- a line appended by hand closes the run or stands as a proof;
- the session's engaged file removed or rewritten lifts every wall;
- a kept answer rewritten outside the project changes the verdict;
- each of these can be done with the file-writing tools as well as with the shell.

After any one of them, every later commit is admitted unjudged.

## Decision

**A run's files are vouched for by a seal the tool keeps outside the project's tree, and a run that no longer matches its seal stops at the commit gate until the person rules.**

1. The seal is a plain record in the repository's common git directory, under `bionic-seal/`, one file per open run (D7). It holds:
   - the plan's path and digest;
   - the log's path, length and digest;
   - a state, clean or changed, with what changed (plan or log) and how (gone, changed, shortened or added to).

   A changed seal also keeps the length and digest of the log as it was last sealed clean. Every worktree of the repository reads the same home, and no wipe of the project's own state touches it.
2. Only the tool's own code writes the seal, inside a hook or a verb, under a lock with a wait of about two seconds.
   - The log's one appender checks the run against the seal, writes its line and seals again. Whatever the check caught is kept as changed, and an honest line after a change cannot vouch for it (D13).
   - The write hook's after-arm now fires for Edit as well as Write. It seals the plan it admitted from the file on disk, so a write that was denied or failed seals nothing (D19).
   - The write hook's before-arm leaves a note of the digest of the exact bytes the tool will write, at its admit of a plan write: a Write's content, or an Edit's one replacement applied to the file as it stands. The after-arm pays that note when it seals. A check that runs between the tool's write and its after-arm, such as an append to the log or a commit's gate, reads the tool's own bytes as owed and not as a change.
   - The gate keeps a caught change in the seal before it opens the ask.
   - Accept seals the run anew. Abandon and close-out remove the seal, close-out before the archive moves the plan.
   - A writer that waits out the lock leaves a note of its exact line beside the seal, so honest writers that append at once are not caught.
3. The commit gate compares the bound run with its seal before the engagement test and before any costly read (D8, D18). It does so for a `git commit` in the project whose bound plan can be read and whose seal stands. On a difference it refuses, names what changed and how, names the log from the seal so the refusal stands with the plan gone, and names both replies. The change opens one ask on the log the seal names, so the situation report lists it even when the plan is gone (D2, D15). `session-poker.sh publish` makes the same comparison before it reads the release approval, judged by the gate's own function:
   - a changed run is refused (exit 1), its catch kept and the ask opened;
   - a seal held past the wait is refused (exit 2), to be run again;
   - where the gate steps aside because the seal library cannot be loaded, publish refuses, since no wall sees the push it makes.
4. Only the person's word clears a caught change, and both answers are verbs (D21). `session-poker.sh accept '<words>'` takes a changed run whose plan is on disk: it records the person's word and what it accepted, closes the ask and seals the run as it stands. `session-poker.sh abandon '<words>'` takes any open run the session is bound to, the plan gone or not: it closes the ask, writes the abandon line and removes the seal. Each is refused unless the words stand in a prompt the person typed in a session the log bound as it was last sealed clean, so a bind line forged into the log cannot widen whose words count. Neither can be run by a dispatched writer.
5. The session's binding is a record beside the seal, written by the one bind function on every binding it makes (D14). The commit gate believes it over the engaged file, so a session bound to an open run keeps its commits judged whatever happens to that file (D3). A session with no binding record is judged by its engaged file, as before.
6. A caller that decides on the run's facts folds them fresh from the verified log. It never reads the kept facts file and never writes it (D17). These callers are:
   - the commit gate's whole body, and the readings handed to it;
   - the step advance's dry commit and its facts judge at steps 7 and 8;
   - every read of the release approval's head, publish's among them;
   - close-out's facts judge;
   - the approve verb's check that an approval already stands.

   A memo a reader filled from the kept file in the same process is not served to a caller that decides. The readers that decide nothing, such as the tick, the cards and the situation report, keep the kept file and its speed.
7. A Write, an Edit, or a shell command whose effects the wall can read as a write or a delete in the seal's home, or as a delete of a directory that holds it, is refused, whether or not the session is engaged (D8, D20). Nothing else is refused at the wall for the seal's sake: a change is caught by state, at the commit.
8. A run found open with no seal, as every run is at the upgrade, is sealed as found at the first append to its log, and the sealing is logged as a hand act (D11). Nothing done to the run before that first sealing is judged.

## Alternatives rejected

- **A changed run that is only reported** (D2): a report nobody has to answer admits every later commit, which is the defect.
- **Closing only the six roads named** (D3 option 1): the file-writing tools and a hand-written line reach the same end by other roads.
- **Judging commits that never meet the gate** (D3 option 3): a different mechanism, older than 2.0.0, and a wave of its own.
- **A keyed seal** (D7): it needs a secret and a place to keep it from the same agent it guards against.
- **A seal inside the project's tree or its state folder** (D7): writable by any tool call and wiped at step 8.
- **Refusing every shell write to a run's files at the wall** (D8 option 1): the wall cannot read every command, and honest writers put records beside the log all day.
- **Refusing nothing at the wall** (D8 option 2): it leaves the seal itself one tool call from removal.
- **A bind event on every change as the binding's record**: sessions already hold bind events in more than one open run, and the log is the thing being verified.
- **A raw scan of the log for the step**: faster, and not proved equal to the reader's fold.
- **Making the after-arm vouch only for the bytes it predicted**: any byte the hook predicts wrong would then be a catch only the person can clear.

## Consequences

- The six roads and their file-tool forms end at a refusal that names the change. The honest acts that move or rewrite a run's files go through the tool's writers and are not caught:
  - close-out's archive;
  - step 8's wipe;
  - the bind verb;
  - a cleared session engaging again;
  - the step verb's move down;
  - a writer's record put into the record folder;
  - a plan write through the tool with a check landing inside it.

  A run driven end to end by its verbs alone never reads as changed.
- In this run's own use an honest Edit of the plan was caught once, by a log append that checked the run inside the Edit's two seconds, before the before-arm's note existed. Every commit was refused until the person ruled.
- A line written by hand into the kept facts file moves no judgment: the commit stays refused word for word, publish pushes nothing, and the step advance and the close refuse as before.
- The 1.3.2 rule that a session with no engaged file is never judged is narrowed: it holds only for a session the seal does not bind.
- Every test fixture that writes a log or a plan by hand seals what it wrote through the seal library. This was the largest change to the suites, made before the gate began to refuse.
- The costs, each measured on copies:
  - a seal check takes about 0.03 s on a log of 2.8 MB;
  - a sealed append costs about 80 ms more than before;
  - the facts fold from the log takes 0.19 to 0.21 s on this run's log;
  - a commit on a copy of this run's log took 4.27 to 4.28 s against 5.47 to 5.57 s before the gate stopped reading the kept facts, since it now folds once where it read and wrote the kept file three or four times.
- A script of the person's own that edits a run's plan or log by hand now meets the refusal at the next commit.

## What it does not do

- It is a trail, not a lock. The seal and the notes beside it are plain files, so a process that sets out to rewrite them can. A shell command the wall cannot read, a glob among them, can still remove the seal, and the run is then sealed as found again at the next append. It catches a change made around the tool, which is what happened in every case recorded.
- It does not judge a commit that never meets the gate: one made by a merge, a cherry-pick, an alias or a script (D3, a Known limit of 2.1.0).
- It does not refuse a shell command whose effects the wall cannot read. Such a command can still change a run's files, and the change is caught at the next commit.
- It does not compare a run whose seal does not stand yet, and the gate seals nothing as found. The write hook's after-arm seals a run found with no seal and logs no line, where the appender logs one. Of two plans that share one record, only the first is sealed.
- The step advance does not compare. Its dry commit asks the gate's judge in its own process, and the comparison lives only in the commit hook, so a changed run advances as a clean one. Its commits and its publish are still refused. The comparison and its refusal are written twice, in the commit hook and in publish, and are a registered debt.
- The before-arm's note covers only the bytes it can predict. A write the tool makes in other bytes than the posted content or the literal one-match splice leaves no note. A note is also swept after a minute, so a plan write whose permission prompt is held longer leaves none. Either write has the old window back, and a check inside it is a catch only the person can clear: it fails closed, never open. A hand change between the tool's write and its after-arm, with no check between them, is sealed with the write.
- Only the commit gate believes the binding. The write hook acts on the engaged file alone, so for a bound session whose engaged file is gone its plan edits leave no note and are not sealed, and the next commit reads them as changed. The dispatch wall, the turn-end walls and the watcher also act on the engaged file alone.
- Two readers that decide no commit still read the kept facts: the release approval verb's check for a stale approval, and the dispatch wall's check of an approval.
