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
created: 2026-11-19
---
# ADR-081 — The pull request is the road

## Status

**Proposed** (Step 7, 2026-11-20). Written as built, checked against the settled head of wave 51 and its reviews, and written before this run's own pull request. It rests on calls in wave 51's log that the orchestrator made under the person's standing order to decide what can be reverted: D5 and D10 (2026-11-18). The design's defaults D24 to D27 were approved at the design card. It changes step 8's integrate act at every scale, and it supersedes the local merge of a wave's working branch.

## Context

In 2.0.0 the integrate act depended on the scale:
- at wave scale, the working branch was merged into the integration branch locally, and pushing was the person's gate;
- at task scale, close-out printed `gh pr create` for someone to type, recorded it as the integrate act, merged nothing and closed the run.

Either way, the push and the request were commands an agent or the person typed. No check of the person's consent stood in front of them, since a wall sees only the command it is shown.

Close-out read the merge from the local integration branch. So a run learned of a merge only after someone pulled. A squash merge leaves the working head off the integration branch for good, so it could never be read as merged.

## Decision

**A run reaches its integration branch by a pull request: on the person's release approval one command of the tool pushes and opens it, the person merges it on the host, and the run reads the merge from the remote.**

1. The integrate act is a pull request at every scale. No path of the tool merges into the integration branch or moves its ref, and a static section of the lint refuses a product line that would (D5).
2. `session-poker.sh publish` is the one command that pushes and opens the request (D10). It is on the walls' list of contract verbs, so a dispatched writer's call is refused and only the orchestrator's own call runs. Nobody types the push or the create.
3. Its first acts come before anything leaves the machine (D25). It compares the run with its seal, and a changed run is refused as the commit gate refuses it (ADR-079). It then checks consent: the newest release approval, folded from the verified log, must name the working head, or a head past which only prose landed, by the same two functions the step-8 advance asks. Refused, it exits having pushed and called nothing. No wall sees a push made inside a command, so these checks are the whole of the consent.
4. With consent it makes three outward acts:
   - It pushes the working head to the working branch on `origin`. It never forces, never sets an upstream and never touches the local integration branch.
   - It opens the request against the integration branch through the host's command line tool, `gh`, with prompts off.
   - It records the request in the run's log as a published event of its own part, carrying its address, branch, head and base (D26).

   Run again at the same head, it does nothing. At a new head it pushes again and records the same request at that head, with no second create.
5. A failed outward act exits 4 with its cause, records no request, and opens an ask on the person. The failures are no `origin`, no `gh`, a push refused, a create refused, and no address in the host's answer. The next publish that succeeds closes the ask.
6. One function reads whether the working branch is merged (D24).
   - It fetches the integration branch into the remote-tracking ref alone, so the fetch can move nothing under the local branches, and reads that ref, never the local one.
   - The run is merged when the working head is reachable from that ref.
   - For a squash or rebase merge, the run is merged when the host says merged, names a merge commit the fetched branch holds, and the request the log holds carries the working head itself.
   - A request the host closed unmerged opens an ask on the person.

   Close-out, step 8's gate and the watcher all ask this one function.
7. While the request is open, the run does not wait only on the person (D27, ADR-080).
   - The situation report names the request as what the run waits on, and offers no ready row.
   - The watcher fetches on each pass and stays quiet.
   - The pass that reaches the merge runs close-out, which lands the integrate row at the merge read and closes the run. The pass then wakes the model once with what close-out left for it to do.
   - A close that holds is told once.
8. An integrate row takes no worktree: a tree asked for one is refused, naming the kind. A removed tree is a tree event with an empty path, read by the reader, rather than a new event type (D26).

## Alternatives rejected

- **Publish as an agent's typed commands** (D10 option 2): a push the consent check cannot stand in front of.
- **New event types for the pull request and for a removed tree**: the published and tree events already carry both.
- **Moving the local integration branch by fetch**: forbidden by AC-13.3, and refused by git when that branch is checked out.

## Consequences

- The person's release approval is the consent for everything that leaves the machine, and the merge is theirs, on the host. The local integration branch is where it was before the route.
- A release approval appended to the log by hand, or written into the kept facts file, pushes nothing.
- A squash or rebase merge is read as merged without anyone pulling.
- Publish needs a remote named `origin`, and `gh` installed and signed in. Without them it fails to the person with the cause, and the run waits on that ask.
- Step 8's gate and close-out now reach git, and on the squash path they reach the host too. A project with no `origin` is read from its local integration branch, and has no road to publish by.
- Close-out runs inside the watcher when the merge is seen. Like every close, it wipes the session's state in the tmp folder and disengages the session; the wake follows.
- At task scale a branch that is not merged no longer closes: close-out holds until the merge can be read.

## What it does not do

- It has not been driven end to end against a real host. Every push, request and merge was made against a bare remote and a stand-in `gh` in the suites. This run's own pull request, the first real one, is the integrate row's. That the woken turn reads close-out's account and does the close's model acts is still to be shown.
- The step-8 page still says the integrate row runs the push and `gh pr create`, beside the sentence that gives both to publish.
- The close replay still pulls the merge into the local integration branch as the person's own act. So the rehearsed run end to end does not yet prove the merge is seen with no local move; the pull-request suite does.
- A request the person reopens on the host is read open again only by the next fetch. While the ask on a request closed unmerged is open, the watcher rests and fetches nothing.
- While the request is open, each of the watcher's passes is a whole tick, and on a large record a pass costs most of its interval (ADR-080).
- The situation report's ready set leaves out the integrate row while a request is open, and the fill's own ready set does not, so the two can disagree about that row.
- It does not merge for the person, and it does not choose a merge method.
