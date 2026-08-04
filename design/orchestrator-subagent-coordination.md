# Orchestrator–Subagent Coordination — Technical Design Document

How one Claude session starts, listens to, believes, stops, and accounts for a fleet of
others — derived from what can actually be known, down to what must therefore be built.

STATUS: v4 — RATIFIED 2026-08-04. All six decisions (D-1…D-6) ratified by the user ("All
decisions are ratified"). This is the governing design for epic-15; wave specs reference this
file. The design outlives the epic; this is its canonical, source-controlled form, with a
rendered HTML version beside it. History: v1 rejected (thin derivation, script-centricity);
v2 rejected (undefined terminology, out-of-sequence structure); v3 restructured per review;
v3.1 added D-6/UC-7; v4 ratified.

## Design

### 1. Problem and goal

When the orchestrator runs a fleet of subagents, work is lost and trust breaks in the
interactions between them. Five documented ways, from three weeks of real usage (3,235
messages, 85 sessions): fleets launched into broken environments that die hours later;
finished work destroyed because silence was misread as death; agent claims believed without
proof; evidence destroyed by our own cleanup; unaccounted sessions writing to the repo while
the orchestrator blamed ghosts.

**Goal.** Every orchestrator–subagent interaction — starting, communicating, believing,
stopping, accounting — governed by checks that hold even when the orchestrator's judgment
doesn't. The recurring failure is not ignorance of the rules; it is a model drifting past
rules it knows. The design target: guarantees that survive a bad day.

**Non-goals.** No cross-session supervisor or auto-retry. No escalation detectors. No
auto-selected rigor. No protection against non-agent externalities (API overloads, network,
MCP health). No attempt to make subagents answer on a deadline — §2.2 shows that is
impossible rather than merely hard.

### 2. Constraints — platform facts and what can be known

Two kinds of constraint bound this design: facts about the platform, measured directly; and
what those facts imply about which knowledge is even reachable.

#### 2.1 Platform facts

Measured on Claude Code CLI 2.1.220; version skew is the standing re-check. Three terms used
precisely throughout:

- **Subagent** — a separate, complete Claude session the orchestrator launches to do one
  job. No shared memory with the orchestrator, no heartbeat between them.
- **Working log** (the platform's "transcript") — a file the platform itself writes to disk
  for EVERY session, including every subagent, recording everything that session does,
  continuously, as a built-in behavior. This design adds nothing to make it exist. It is the
  agent's activity record — distinct from any document the agent was asked to produce.
- **Exchange** — one round between user and orchestrator: the user sends a message, the
  orchestrator works (possibly launching a dozen subagents over half an hour), control
  returns. The platform stamps every tool call inside one exchange with a single shared
  identifier.

| # | Fact | What it forces |
|---|---|---|
| P1 | The platform's only enforcement primitive is intercepting a tool call before it runs: a deterministic script, seconds of budget, no model, no conversation access, verdict by exit code. Subagent starts and stops are both interceptable. | Enforcement can exist — but only at these two chokepoints, and only over what a fast script can read. |
| P2 | Nothing fires when an agent dies or is stopped. Natural completion emits an event; a stop emits nothing. | Death cannot be watched for. Guarantees must sit on the orchestrator's own actions. |
| P3 | A subagent reads messages only between its own actions. Inside a tool call it cannot see or answer anything. | Response deadlines are unenforceable by construction. Silence must carry zero evidential weight. |
| P4 | The exchange identifier covers everything in one user round — measured spanning 29+ minutes and a dozen subagents. No finer-grained shared clock exists. | "It happened in this exchange" says nothing about "it happened recently." |
| P5 | A stop request contains only the text the orchestrator typed — the name it gave the agent — not the agent's internal identity; the platform does not translate. Separately, every agent in a fleet shares the orchestrator's session identifier. | Any stop gate must translate name → identity itself. One environment check covers a fleet — but actors within it are indistinguishable by keys alone (until wave 3 adds identity). |
| P6 | Every subagent's working log and a small metadata record (name, type, model) are on disk, readable by scripts, updated as the agent works. | The one continuously-updated, machine-readable trace of real activity — the foundation of §2.2. |
| P7 | Stops initiated by the human (UI, process termination) bypass the tool pipeline. | The human's own actions stay outside every wall, honestly. |

#### 2.2 Derived constraints — what can be known about a subagent

From P1–P7, everything the orchestrator can learn arrives through five channels of unequal
trustworthiness. The split below is the design's first commitment: **evidence may ground an
action; a signal may only prompt evidence-gathering.**

Why the split is right: the distinguishing property is causal. The evidence tier consists of
artifacts produced BY the work itself (a byproduct log, a contracted output, the agent's own
words); signals are the platform's scheduling bookkeeping ABOUT the work. Bookkeeping about
attention was measured wrong in both directions in live operation; byproducts of work cannot
be wrong about whether work happened. Two refinements keep it honest: the task registry's
TERMINAL states (completed, stopped) are authoritative and count as evidence — only
"running" proves nothing; and an agent's message splits in two — its arrival is evidence of
life at send-time, while its content is only as good as the proof attached (the reporting
contract, §3.3, exists to fix that).

EVIDENCE — may ground action:

- **Working log.** Written continuously as a side effect of working — the agent cannot work
  without producing it, which makes it unfakeable. Last-write time = last real activity: a
  write 41 seconds ago means alive, definitively. Contains the agent's actual output,
  including work finished but never delivered. Cannot prove: that a quiet log means death —
  a ten-minute tool call writes nothing until it returns.
- **Contracted deliverable.** The output file the agent was told, at launch, to produce.
  Present and substantive = done, whatever else is true. Its meaning comes from the
  contract: we named it, so its existence answers exactly the question we care about.
  Cannot prove: failure, from absence; and it proves nothing if no deliverable was
  contracted — which is what makes the work contract load-bearing.
- **Message from the agent.** Alive at the moment of sending, plus content — the only
  channel carrying the agent's own account. Cannot prove: anything from its absence (P3);
  content is only as trustworthy as the attached proof.

SIGNALS — may only prompt a look at the evidence:

- **Task registry, while "running."** The runtime still schedules the task; "running"
  covers working and hung alike. (Terminal states are evidence.)
- **Idle notification.** The platform observed a pause. Not completion, not delivery, not
  death — measured wrong in both directions this session (idle before delivery ×4, after
  delivery ×5, mid-delivery ×1).

**The asymmetry that governs everything: a response proves alive; silence proves nothing
(P3).** Any rule built on silence is built on nothing. Every rule in this design is built on
the evidence tier only — and where evidence would be missing at decision time, the design's
job is to have created it in advance.

**What remains unknowable:** whether a silent agent is thinking or hung (the working log
goes quiet in both cases), and the moment of death (P2). The design treats the first with a
bounded procedure (§3.4) and the second by never depending on death detection at all.

### 3. Architecture — derived

#### 3.1 The derivation

- GIVEN: the failure mode is the orchestrator's own judgment lapsing mid-drift (§1). The
  guarantee cannot live in the orchestrator's context — instructions there are exactly what
  a drifting model ignores. It must live outside the model.
- AND: the only external enforcement point the platform offers is tool-call interception
  (P1) — fast, deterministic, no model, no conversation — at exactly the moments that
  matter: the start and the stop.
- BUT: such a script cannot gather evidence. It cannot probe an environment, read a fleet's
  working logs, or weigh a deliverable in its seconds-long window. It can only check facts
  already written down.
- SO: evidence must be gathered BEFORE the guarded moment — by the orchestrator, the only
  actor that can — and written into machine-readable state where the gate can read it.
  Evidence-gathering and enforcement are necessarily different actors at different times;
  state is the only possible interface between them.
- AND: whatever cannot be expressed as a fact-check at a chokepoint — composing a launch,
  handling a quiet agent, standards of belief — cannot be walled at all. It lands in
  procedure: pinned text, enforced by review and audit, honest about being the weakest
  layer.

**THE DESIGN THEOREM. A wall can only enforce what was written down before the moment it
must decide. Every guarantee is therefore a pair: an act of evidence-gathering that writes
state, and a gate that refuses the guarded action when that state is missing, foreign, or
stale.**

#### 3.2 The three layers

**Interception — the gates.** The chokepoints P1 provides. A gate reads state and the
active plan, never the conversation; its entire vocabulary is allow silently or refuse
loudly, naming the exact command that fixes it. Gates install machine-wide and must be
inert wherever no wave is running.

**State — the written-down evidence.** Small, per-repo, ephemeral files, each written by
exactly one producer and read by exactly one gate. Ephemerality is deliberate: operational
evidence has a natural lifetime, and the durable record is the copy mirrored into the plan.
The boundary rule that follows from the derivation: producers may think; gates may only
read. The moment a gate needs judgment, the design is wrong — that judgment belonged
upstream, in a producer, writing its conclusion down.

**Procedure — everything unwallable.** Launch composition, quiet-agent handling, standards
of belief — everything requiring judgment at a moment with no chokepoint. Pinned by span
tests so the text cannot drift silently; policed by review and audit; honestly the weakest
layer. The walls exist precisely to backstop its failures at the two irreversible moments.

#### 3.3 The entities

Each exists for one of two reasons: it makes an evidence channel usable, or it writes
evidence down in advance so a gate can read it later. Nothing else earns an entity.

| Entity | What it is | Why it must exist |
|---|---|---|
| **Work contract** | The launch-time agreement between orchestrator and subagent: the task, the named deliverable file at a durable path, the exit condition. For long-running tasks, also an expected duration and a progress-artifact path (D-6). This is the contract governing how the two work together. | Creates the deliverable channel. Without a contracted output, an agent's silence is uninterpretable forever — "is it done?" has no answer because "done" was never defined. Wave 1 carries it as procedure; wave 2 makes it checkable. |
| **Reporting contract** (wave 2) | The rule that any factual claim in an agent's report — "tests pass," "file exists" — must include the command that proves it and its output, or carry the explicit label `unverified`. | Makes the message channel trustworthy. Content is otherwise only as good as the agent's say-so, and unproven claims caused real incidents. The orchestrator re-verifies anything labeled unverified before acting. |
| **Environment attestation** | A small file recording that this session's environment checks passed — credential present, disk writable, git state captured — keyed to the session that ran them. | The theorem: gates read facts written in advance. "The environment works" must be checked while there is time to think and written where the start gate can read it in milliseconds. |
| **Subagent observation** | A machine-made record that the orchestrator examined a specific agent's evidence — and what it saw, including the agent's activity level at that moment. Recorded by machinery when the examination happens, never claimed from memory afterward. | The stop gate needs proof that a real examination preceded the stop. Self-reported diligence is exactly what fails under drift; the record makes "I checked" a fact rather than a claim. |
| **Session roster** (wave 3) | The session's own list of the agents it launched — name tags. Consulted when unexpected changes appear in the repo, and by future gates needing to know who an actor is. | "Who is working here" currently has no channel at all; the roster creates one. It doubles as the launch ledger, so accounting and identity are one artifact. |
| **Non-response procedure** | The fixed procedure for a quiet agent: examine its evidence first, then one class-appropriate round — read-only agents may get one follow-up message; writing agents are never resumed (two live writers collide on the same files) — ending, within two rounds, in exactly one of: work delivered, work taken over, or agent stopped-and-reported. | Thinking-versus-hung is undecidable (§2.2), so uncertainty needs a bounded procedure built only on evidence-tier reads — otherwise it stretches into destruction (the old failure) or waiting forever. |

#### 3.4 How the entities are used — the four interactions

**Starting — walled (wave 1).** An agent may be started when: the environment is proven
working THIS session (a fleet inherits its environment and dies collectively; the
attestation reifies the check); a work contract exists (the start is where the stop's future
evidence gets created — an agent launched without a contracted deliverable is undecidable by
construction); and the launch is ledgered the moment it happens.
Flow: environment check (producer, once/session) → attestation (state, session-keyed) →
start gate reads it on every subagent start → attestation present and mine: proceed; missing
or foreign: refused with the fix command named.

**Communicating and believing — procedure now, contract in wave 2.** Outbound, the work
contract tells the agent what to produce and where; inbound, the reporting contract makes
claims self-verifying. No tool chokepoint exists for believing, so this interaction can
never be walled — its enforcement is the audit chain, which is why the contracts must be
written artifacts rather than habits.

**Stopping — walled (wave 1).** An agent may be stopped when: its deliverable exists and is
substantive (finished — take the work; no timing judgment needed); or nothing new has
appeared in its working log since a recorded observation, no deliverable exists, and the
non-response procedure's round has run. Never on an idle notification, never on elapsed
silence, never without an observation newer than the agent's last activity.
Flow: observation (producer, per target) → recorded by machinery into state (target +
activity seen) → stop gate reads it on every stop request → observation fresh per D-1:
proceed; none, foreign, or stale: refused with the observation command named.

**Accounting — wave 3.** Every launch writes a roster row; every quiet agent resolves
through the non-response procedure to a recorded outcome; unexpected repo changes are
checked against the roster and surfaced instead of built upon. Wave 1 ships only the
warn-only detection of other live sessions.

### 4. Components

Contracts first; file names are the realization, listed last.

**The environment check** (producer, start). Verify what a fleet dies without — credential
present, repo writable, state directory writable — and record context that informs judgment
without blocking (git baseline; warn-only scan for other live sessions). Write the
attestation keyed to this session, atomically; on failure write nothing and destroy any
earlier attestation. May take seconds and think; runs once per session. Never: write an
unkeyed attestation; leave a stale pass standing. Named limit: proves the credential is
present, not valid — expiry detection needs a live API call (backlog).

**The start gate** (gate, start). On every subagent start, machine-wide: if a wave is
active and no attestation from this session exists — refuse, naming the exact fix command.
Otherwise pass in silence. Parses no check detail: the attestation's existence IS the
verdict, by the producer's contract. Never: print on the allow path; block where no wave is
active.

**The observation** (producer, stop). Given a target by name or identity, resolve it
against on-disk metadata (P5) and print that agent's evidence tier: working-log recency as
absolute time and age, last message, repo activity, each contracted deliverable's existence
and substance — and, for long-running tasks, the progress artifact's age (D-6). Decide
nothing. Its run is observed by machinery, which records the target and the activity level
seen — making "an examination happened" a fact rather than a memory. Never: stop anything,
judge anything.

**The stop gate** (gate, stop). On every stop request during an active wave: resolve the
typed name (P5), find an observation of that target from this session, check freshness
(D-1). Any failure — no record, foreign session, unresolvable or ambiguous name, staleness
— refuses, naming the observation command. Never: pass on ambiguity once a wave is active
(a stop is irreversible; the ambiguous case is the wall's purpose); wall a machine with no
wave running.

Realization: environment check → `hooks/preflight-probe.sh` · start gate →
`hooks/dispatch-preflight.sh` · observation → `hooks/stop-check.sh` · stop gate →
`hooks/stop-guard.sh` (one script, two registrations: records observations, gates stops) ·
state → `.bionic/tmp/{preflight,stop-check}.state`. Note: the two producers live in
`hooks/` for test-harness pairing but are not hooks — the component boundary is the
registration list, not the folder.

### 5. Decisions — ratified 2026-08-04

All six decisions below were ratified together on 2026-08-04. The RECOMMENDED lines are
preserved as the argument record; each is now binding design.

**D-1 — When is an observation still fresh?** An observation is a snapshot of the evidence
tier; it stops being true the moment the evidence changes — and the working log says
precisely when that is: the agent's next write. Every other rule is a failing proxy: clock
windows are arbitrary numbers that expire honest observations of dormant agents and admit
stale ones inside the window; keying on the exchange identifier was adopted and then
disproven by P4 (one exchange spans a 29-minute fleet, so the observation never expires
exactly where fleets are largest). THE RULE: a stop is permitted only if the target's last
activity is no later than what the observation recorded. Did something since you looked →
stale by definition. Dormant since you looked → valid, however old. RECOMMENDED: adopt, as
wave 1's corrective slice before merge. No clocks; completes the doctrine — session
boundary for environments, activity boundary for stops.

**D-2 — One observation, one stop.** An observation is evidence about one target at one
moment; letting the record ride for repeated stops re-admits staleness through the side
door. Consume it on use: every stop individually evidenced. RECOMMENDED: adopt with D-1.

**D-3 — Whose observation counts?** P5: every actor in a fleet shares one session key, so
today a SUBAGENT running the observation quietly lowers the wall for the orchestrator's
later stop of that target. The observer's identity isn't in the record because per-actor
identity doesn't exist yet — it is precisely wave 3's roster. RECOMMENDED: route to wave 3;
carry the interim exposure as a named limitation. (D-1 shrinks it: a borrowed observation
also goes stale on the target's next write.)

**D-4 — Does the wave carve survive this document?** The carve now has a derivation: wave 1
= the two walled interactions (start, stop) as producer→state→gate pairs; wave 2 = the
believing interaction's contracts (work contract made checkable; reporting contract —
audit-enforced, since no chokepoint exists for belief); wave 3 = the accounting
interaction's state (roster), which also closes D-3 and D-5. Each wave is one coherent
increment; none depends on a later one. RECOMMENDED: keep the three waves; wave 1 absorbs
the D-1/D-2 corrective slice before merging.

**D-5 — Concurrent sessions sharing one repo.** State files are one-slot-per-repo while
validity is per-session — two live sessions overwrite each other's attestation (observed
during this epic's own verification). Fail-closed, so safe; mutually annoying. Per-session
filenames are the fix and are identity work. RECOMMENDED: route to wave 3; until then a
collision costs one re-run of a three-second check.

**D-6 — How long do we wait? Time, contracts, and long-running work.** An hour-long test
suite silences the working log for the whole hour (one tool call, one result at the end),
so "no activity for 47 minutes" describes both a healthy suite and a wedged one. Two wrong
answers: a global kill-timer reads time as evidence and destroys the legitimate suite at
minute 59; pure discretion is unbounded. The resolution: (1) evidence has a level below the
agent — the TASK's own byproducts. We cannot make the platform update the working log, but
the work contract CAN require long commands to accrue output at a named path; the
observation then checks the progress artifact's age, and "working log quiet 47 minutes,
progress file grew 12 seconds ago" is alive, definitively. (2) Expected duration becomes a
contract field — declared per task, by the party holding the knowledge, at launch. Exceeding
it is A SIGNAL, NEVER EVIDENCE: it triggers the non-response procedure mechanically; it
never justifies a stop by itself. The eventual stop still requires the fresh observation
(D-1). THE BOUND: total wait ≤ declared duration + the procedure's two rounds. RECOMMENDED:
adopt — two contract fields (expected duration; progress-artifact path), the observation's
progress check, overdue-as-trigger semantics. The fields belong to wave 2; the practice is
adoptable immediately in every long-running brief.

### 6. Use cases, end to end

**UC-1 — Normal fleet launch.** Wave opens; environment check runs (~3s), attestation
written. Every start passes the gate silently; every launch carries a work contract and a
ledger row. Cost: one command per session, milliseconds per start.

**UC-2 — Launch into a broken environment.** Credential missing → check fails, writes no
attestation, deletes any old one → first start refused with the fix command. The failure
surfaces at minute zero, loudly — not hours later as dead agents and lost work.

**UC-3 — Quiet read-only agent holding finished work** (observed live). A review agent
idles without delivering. Idle is a signal — grounds nothing. Observation: working log
written 41 seconds ago; last message "I already completed this review — resending now."
Alive and finishing; the orchestrator recovers the review from the working log instead of
stopping the agent. As observed: the stop gate forced exactly this observation after the
orchestrator, acting on the idle signal, had already requested the stop. The wall caught
its own operator; the recovered review contained the wave's most important finding.

**UC-4 — Quiet writing agent, work complete but uncommitted** (observed live). An
implementor idles without committing. Writers are never messaged back to life (a resumed
second instance collides with the first on the same files). Evidence instead: the repo
shows its edits present and correct; the diff is read; the orchestrator commits the work
itself and stands the agent down with one final message. Outcome: taken over.

**UC-5 — Stop attempted on stale information** (observed live — the founding incident). An
agent is examined; minutes later — after it has committed its work — a stop is requested on
the strength of that earlier examination. Under D-1 the gate compares the observation's
recorded activity level against the working log now: the agent wrote AFTER the observation,
so it is stale by definition and the stop is refused until the orchestrator looks again —
at evidence that now includes the commit. The pre-epic version of this event destroyed
finished work; the v1 design (exchange-keyed freshness) provably re-permitted it.

**UC-6 — A second session on the same repo.** The environment check's scan finds another
live session's working log and warns with its identity (as it did, correctly, on its first
real run). Warn-only in wave 1; wave 3's roster upgrades "someone else is here" to "these
specific changes are not ours." Detection, never prevention.

**UC-7 — The hour-long test suite.** Contract: regression suite, expected ~60–75 minutes,
output accruing to a named progress file, verdict file as deliverable. Minute 30: idle
notification — a signal, correctly ignored. Minute 47: observation — working log quiet 47
minutes, but the progress file grew 12 seconds ago → alive, busy; no judgment call needed.
Minute 80: overdue → the non-response procedure triggers mechanically. Observation now
shows the progress file also stopped 25 minutes ago, no deliverable → one follow-up message
(read-only class), nothing arrives, re-observation shows no change at any level → stop
proceeds, fresh observation in hand per D-1, reported. Elapsed time appeared exactly once —
as the trigger. The healthy suite was never at risk; the wedged one was caught within one
declared duration plus two bounded rounds.

### 7. Failure model

One principle generates the table: the default direction follows the cost asymmetry of the
guarded action. A missed start-wall costs one unchecked launch; a false start-wall nags
every session on the machine — starts fail open. A missed stop-wall destroys unrecoverable
work; a false stop-wall costs one diagnostic re-run — stops fail closed. Where no wave is
active there is no decision to guard, so everything passes.

| Surface | Direction | Derived from |
|---|---|---|
| Start gate — any ambiguity, anywhere | OPEN, silent | cost(false block) ≫ cost(missed wall); machine-wide install |
| Stop gate — before the active-wave verdict | OPEN, silent | an unconfigured machine is not a stop decision |
| Stop gate — after the verdict | CLOSED, loud | irreversibility; the ambiguous case is the wall's purpose |
| Environment check — no session key | REFUSE | an unkeyed attestation validates nothing |
| Environment check — blocking probe fails | NO ATTESTATION + delete prior | a stale pass must not outlive the environment it described |
| Payload missing its session key | start: open / stop: closed | the same asymmetry; recorded inconsistency, accepted |

### 8. Security

Threat model: an untrusted repo — which controls its own plan files, `.bionic/` contents,
and ignore rules — meeting these gates installed machine-wide. The load-bearing property: a
hostile repo can CLOSE or AIM the walls but never OPEN them — opening requires the victim's
own session keys, which the repo cannot learn. Fixed during this epic's review: predictable
temporary filenames plus symlink-following redirects allowed an arbitrary file overwrite —
proven with a working exploit, closed with unpredictable names, regression-tested by
planting a symlink and proving nothing writes through it. Accepted and named: refusal
messages print a plan path into model context (bounded prompt-injection surface, no
execution); the docs-root setting can aim plan discovery and disclose filename existence;
the observation prints a slice of a subagent's working log — its purpose; the reader is the
defense. The prior credential-leak class (command text reaching logs) is verified not
reintroduced.

### 9. Verification strategy

Organized around the lesson this epic paid for: wave 1's test fixtures were single-exchange
while its claims were about long, multi-agent exchanges — and that gap is exactly where the
design flaw survived an audit.

- Every wall is a verification instrument: its tests must prove it CATCHES (planted
  violations go red against the pre-wall state) and PASSES the positive pair — a wall that
  refuses everything is equally broken.
- Mutation-and-restore is the durable proof: remove the guard, watch named checks fail,
  restore byte-identical, watch them pass. Red counts die at green; this survives
  integration.
- Deliberately duplicated logic (a shared library was rejected: a sourced file the
  installer misses is a silently inert wall) carries behavioral agreement tests driving
  every copy.
- The installed layer is verified live: fresh sessions after a real install, refusal and
  permission both observed semantically.
- Binding on waves 2–3: at least one verification scenario per wave must be long-exchange,
  multi-agent, against installed binaries — the configuration the epic exists for and v1
  never tested.

### 10. Rollout and operations

Bootstrap installs the scripts and registers the two gates; the user runs bootstrap —
always, never an agent. Gate registration takes effect for NEW sessions; a live session
keeps its start-time configuration (verify installed behavior in fresh sessions; upgrading
means bootstrap, then next session). A rename leaves the old file behind in the installed
directory until the manifest-driven cleanup runs — verify on the next bootstrap. State is
per-repo and ephemeral, wiped at wave close; anything evidence cites is mirrored into the
plan first. Uninstall runs through reset and the same manifest. Standing gap outside this
epic: path-scoped rule files do not distribute to other machines at all.

### 11. Decision register

One honest sentence each; superseded entries stay listed — the register is a history.

| Date | Decision | Status |
|---|---|---|
| 08-03 | The whole coordination problem is one epic: seven failure themes, walls preferred over procedure wherever the platform allows. | active |
| 08-03 | An environment check is trusted for exactly one session — a new session re-checks, no timers. | active |
| 08-03 | Agent reports bind by a rule (every claim carries its proof or says "unverified"), not by a required layout. | active · wave 2 |
| 08-03 | Quiet agents get two treatments: read-only agents may be messaged once and relaunched; writing agents are never resumed — their output is examined and taken over. | active |
| 08-03 | Each session keeps name tags — a roster of the agents it launched — so foreign work is detectable. | active · wave 3 |
| 08-03 | An observation before a stop was trusted for the length of one user exchange. | superseded → D-1 |
| 08-04 | Terminology: "stop," matching the tool's own name. | active |
| 08-04 | Examine-before-acting applies to BOTH agent classes — an undelivered review is as losable as an uncommitted commit. | active |
| 08-04 | Significant work requires a TDD; v1 rejected (thin derivation, script-centricity), v2 rejected (undefined terminology, out-of-sequence structure), v3 restructured, v3.1 adds D-6/UC-7. | active · process |
| 08-04 | All six design decisions (D-1 activity-boundary freshness · D-2 consume-on-stop · D-3 observer identity to wave 3 · D-4 wave carve stands · D-5 per-session state to wave 3 · D-6 contracted duration + progress artifacts) ratified together. | active |
