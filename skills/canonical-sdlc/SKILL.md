---
name: canonical-sdlc
description: Use when starting a large-scale development effort (new feature, architectural change, multi-day project) or when picking the skill for the current SDLC step. Routes to the canonical skill per step and gates every commit on the current step's evidence.
layer: governance
needs:
  - agent-skills:context-engineering
  - agent-skills:source-driven-development
  - agent-skills:documentation-and-adrs
  - agent-skills:idea-refine
  - agent-skills:spec-driven-development
  - agent-skills:incremental-implementation
  - browser-verify
  - agent-skills:browser-testing-with-devtools
  - agent-skills:security-and-hardening
  - agent-skills:performance-optimization
  - agent-skills:git-workflow-and-versioning
  - agent-skills:shipping-and-launch
  - agent-skills:ci-cd-and-automation
  - agent-skills:frontend-ui-engineering
  - superpowers:systematic-debugging
  - superpowers:writing-plans
  - superpowers:executing-plans
  - superpowers:using-git-worktrees
  - superpowers:test-driven-development
  - superpowers:verification-before-completion
  - superpowers:finishing-a-development-branch
  - superpowers:dispatching-parallel-agents
  - impeccable
loading: deferred
---

<!-- GENERATED FILE — DO NOT EDIT. Rendered by agents-src/render.sh from agents-src/templates/skills/canonical-sdlc/SKILL.md.tmpl. -->

# Canonical SDLC

Governs non-trivial engineering work. Every run declares a triple — `<intent> · <rigor> · <scale>` — and walks the applicable steps, leaving evidence a hook can read.

**Only the `## Hooks` section names anything that blocks. Everything else here is judgment, and you own it.**

**No ceremony.** Do everything necessary, once. A task, check, review or approval earns its place only if it can fail in a way nothing already run can: never re-run a suite a gate already runs, never re-review a fix that carries its own red test. Read the record before you dispatch, and cite what is done.

**Decisions.** Every decision you put to the user, at any step and with no run open, goes through the `decision` skill: invoke it, never restate its shape or its rule. It says whose call it is, the short form it takes by default, and that one question goes in a message. The Step-1 and Step-2 interviews are its heaviest users. An ask that holds the run is recorded in the run's register by its verb before it is put to the user — a decision by `decisions put D<n> '<what is decided>'` — so the sitrep cannot miss it. Approvals wait for the release approval card (`release-approval`, answered by `reply`).

**Iron law.** No commit without evidence from the current step. The evidence gate reads the run's step from its log and asks that step's evidence only — it never re-checks earlier steps, so a skipped step is caught by review, not by code.

**Bulk reference.** Artifact shape and authoring detail live in `skills/canonical-sdlc/operational-rules.md`, beside this file, and the version history in the CHANGELOG. Read it when you need the detail this file compresses; nothing loads it for you.

## Load-time announcement

First user-facing action: run `bash <plugin-root>/scripts/card.sh opening [<rigor> [<intent> <scale>]]` with as much of the triple as you know, and show its print first, unaltered: the version line, the engaged line (`build · double rigor · wave`), the rigor line.

Triple not yet declared → say so and list the axes. Invoked as `help` → render the axis tables and stop.

## The triple

**intent** — what the deliverable is.

| Intent | Use when | Evidence delta |
|---|---|---|
| `build` | Capability that did not exist, or capability restored by ADDING machinery/interfaces/config (the machinery test). | RED→GREEN per task. When the build IS a verification instrument, prove it CATCHES planted failures — a check that never fails is not proven to work. |
| `bugfix` | Restore intended behavior WITHIN the existing design. A repair, not new machinery. | The RED test is the failing repro. |
| `refactor` | Change structure, preserve behavior. Covers upgrades, migrations, removals/deprecations. | `behavior-preservation:` in the row's record under `record/`; migrations add `compat-matrix:`/`revert-plan:` (or `n/a: not a migration`). No wall reads them. |
| `tune` | Move a NAMED measurement toward a target. If you cannot name the measurement, it is not tune. | `baseline:`/`target:`/`re-measure:` in the row's record under `record/`, all three. No wall reads them. |
| `spike` | Timeboxed research. **Ships no code at any rigor.** | Writeup only at `<docs-root>/spikes/spike-<slug>-<YYYYMMDD>.md`. No plan file, no spec, no ADR, no commits to the integration branch. |
| `incident-response` | A live deployed surface — production or tooling — is broken for its users. The clock matters. | RCA, not ADR. Minimum `double`. Monitoring-gap closure is part of Close-out. |

**Document and research deliverables — writeups, research reports — don't belong here.** Plain
plan mode serves them better than any row in this table, `spike` included: it ships no code at
any rigor, but its writeup is a timeboxed research artifact, not a general document-production
mode.

**rigor** — how many independent minds answer the questions: `single` (one) or `double` (two). A level sets four things, each the user's to set at Step 0: the reviewers, `review-cadence:`, `fix-policy:` and `fix-cap:`.

Every run that ships code answers four questions, at every rigor. The first, does it do what was asked, is answered by TDD RED→GREEN, the matrix discharged at each row's tier and the regression: one whole run plus the greens of what changed. The other three are read by independent minds: `evidence`, is the proof honest; `adversarial`, what is wrong that nobody asked about; `structure`, is it built from what exists, and shaped well.

Findings are classed by payment date, not by reviewer: harm (the user, now), evidence (the claim, now), debt (the next change). The reviewer roster follows from the classes, not the other way round.

Rigor follows one principle: the moment of a check is set by its cost model; machine checks run early and often, mind checks run once, on the settled whole. A fix row born of a registered review finding covers every question once it lands.

| | `single` | `double` |
|---|---|---|
| reviewers | one: the critic holds every question | two: the auditor takes `evidence` |
| when (`review-cadence:`) | once, at Step 6, on the settled whole | once, at Step 6 |
| becomes a row unasked (`fix-policy:`) | S1 + S2-on, in-diff | S1 + S2-on, in-diff |
| cap on review-born rows (`fix-cap:`) | 2 | 10% of the plan |

`steps/6.md` holds the review findings disposition and turns a review into a fact.

**scale** — the decomposition unit; rows are `lib/scale.sh`'s. At `pr`, close-out merges nothing and reads the host's merge; at `piece+whole`, each code question also owes `scope=whole`.

| Scale | Steps | Artifacts | Patrol | Rigor | Writers | Regression | Branch | Integrate | Dealing |
|---|---|---|---|---|---|---|---|---|---|
| `task` | 0–9 | one plan + `## Tasks` | no | single | 3 | no | any | pr | piece |
| `wave` | 0–9, the default | wave spec + plan | yes | double | uncapped | yes | `wave/<NN>-<slug>` | pr | piece+whole |
| `epic` | 0–3; carves waves | epic spec + plan | yes | double | uncapped | no | `epic/<NN>-<slug>` | pr | piece |

**Rigor minimums.** Default is the Rigor cell: at `task`, `single` unless a flag raises it; at `wave` and above, `double`. Effective rigor is the MAX of the default and four minimums — intent (`incident-response` is at least `double`, `spike` is CAPPED at `single`), flag (security-touching or privacy/vulnerable-population work is at least `double`), project (`rigor-minimum:` in `.bionic/config.yaml`), epic (`rigor-minimum:` in epic frontmatter). Provisional at Step 0, locked at Step 3. **Minimums advise; they never force.** Upgrades are free, and a rigor below the minimum is the user's to choose: advised against at Step 0, then accepted and recorded as `rigor-override:` (see the Override DSL).

Do not carve a sensitive concern into a tiny unflagged wave to dodge a minimum. The wave that owns the integration point carries the flag minimum.

## Artifact layout

```
<docs-root>/specs/epic-NN-<slug>/{epic.spec.md, wave-NN-<slug>.spec.md, wave-NN-<slug>.requirements.md}
<docs-root>/plans/epic-NN-<slug>/{epic.plan.md, wave-NN-<slug>.plan.md}
<docs-root>/adrs/epic-NN-<slug>/adr-NNN-<slug>.md
<docs-root>/incidents/NNNN-<slug>/{spec.md, NNNN-<slug>.plan.md, rca.md}
<docs-root>/spikes/spike-<slug>-<YYYYMMDD>.md
<docs-root>/record/               # operational record: session logs, rotated archives,
                                  # closed-wave handoffs, inert audits. Survives Step 8.
<docs-root>/ideas/                # deferred-work briefs awaiting a wave to adopt them
.bionic/tests/                    # validation protocols re-run by hand, not by tests/run.sh
.bionic/tmp/                      # ephemera only, wiped at Step 8 — NOT a home for evidence.
                                  # Session-keyed state survives while its owning session is
                                  # alive, never by class name
.bionic/.gitignore                # literally `*` — written on tree creation; this is what
                                  # keeps the whole tree out of git, not the project .gitignore
.bionic/config.yaml               # optional; `docs-root:` moves <docs-root> off the default;
                                  # `release-check:`, and `regression-command:`
                                  # when a project's regression is not tests/run.sh
```

The first five are lifecycle artifacts and are gated: the governing-skill hook enforces
frontmatter on them and blocks a canonical artifact written anywhere else. `record/` and
`ideas/` are **operational** — nothing loads them, nothing validates them, and they are reached
only by citing a path. That is the whole distinction, and it is the boundary test applied to
this tree: growth in the gated dirs is governed, growth in the operational ones is free.

**Three artifacts, three steps** — Steps 1–3 write exactly one
artifact apiece, chained requirement → criterion → design decision → test → evidence.
A test is deterministic: unit, integration, hermetic or end to end; an eval tests a model, which is not, so it passes by reaching a stated threshold a stated share of the time.
Step 1 writes `wave-NN-<slug>.requirements.md`: numbered requirements/user stories, each with
provenance and acceptance criteria written so a "fails when" is nameable, plus Not Doing. Step
2 writes `wave-NN-<slug>.spec.md`: the technical design (domain model, architecture, ownership
table, rejected alternatives), the Test design table, and ADR pointers. Step 3 writes
`wave-NN-<slug>.plan.md`: tasks, sequencing and one section per task; its criteria are Step 2's
Test design rows, read in place. Requirements live beside the spec, both under
`specs/epic-NN-<slug>/` — the governing-skill hook validates `*.requirements.md` frontmatter the
same way it validates `*.spec.md`, minus the design three-way rule (that stays spec-only). Each
of the three opens with a `## Goal` section — one concise paragraph, first after the title — and a governing-skill arm at `scale: wave` or `scale: epic` refuses a
write whose first section is not Goal, or whose Goal section is empty.

**Anything a proof cites as evidence goes in `record/`, never `tmp/`.** Auditor reports,
review records, test-run captures — the run's log names them by path, so
they must outlive the run that produced them. `tmp/` is wiped at Step 8 and takes its contents
with it — everything, that is, except a live session's own keyed state, which the wipe spares
by owner liveness, not file name. Give an agent a `record/` path in its brief.

Every artifact carries frontmatter with `governing-skill:`, `sdlc-step:`, `intent:`/`rigor:`/`scale:`, `canonical_sdlc_version: 15`, the 5 discriminator flags, the 2 opt-in flags, and `model_plan:`. A missing one blocks the write. Artifacts never declare `mode:`. Plan files additionally carry `walk: required | exempt` — Step 0's derivation, and the key the Verify gate reads — Step 0's `design-interview:` value beside it, `regression:` (`yes` or `no`, Step 0's setting) and, where it differs from the scale default, `regression-override:` beside those, and, where the run's rigor sits below its derived minimum, `rigor-override:`. None of these is required to write, but a `walk:` value outside the enum blocks.

**15 is the version a plan is written at.** A new plan at any other value is refused at the write, and so is a write that changes a plan at 15 to another value or takes its version line away (deleted, commented out, its key misspelled). At the commit the gate judges only the plan a session is bound to: once its run's log holds a step, a page that does not declare 15 is refused, whatever was done to its version line. With no step in its log the bound page reads as a closed run: a page with no version line, or at 14, is admitted, and one holding another value (an empty value, a typo, 13) is refused. A plan already on disk at 14 is an older run's document with no log: both hooks admit it with nothing judged, no session binds it, and its work comes forward as text a person or a model reads. With no bound session, no page meets the gate at the commit.

## Steps

| Step | File | Governing skill | Gate |
|---|---|---|---|
| 0 Configure | `steps/0.md` | `canonical-sdlc` | Frontmatter complete, matrix derived, user confirmed, task list created |
| 1 Scope | `steps/1.md` | `agent-skills:idea-refine` | Refined idea + explicit "Not Doing" + alternatives lens cites prior art; writes `wave-NN-<slug>.requirements.md` — numbered requirements/user stories with provenance and acceptance criteria, plus Not Doing |
| 2 Design | `steps/2.md` | `agent-skills:spec-driven-development` | Every requirement has an acceptance criterion; every criterion cites its `provenance:`; wave+ carries a governing design; writes `wave-NN-<slug>.spec.md` — the technical design, ownership table, and the Test design table |
| 3 Plan | `steps/3.md` | `superpowers:writing-plans` | No placeholders; `integration-branch:` present; wave shape locked; tasks tagged; user approved; writes `wave-NN-<slug>.plan.md` — its header, `## Goal`, `## Tasks` and a section per row |
| 4 Implement | `steps/4.md` | `agent-skills:incremental-implementation` | Every task RED before GREEN; assumptions logged |
| 5 Verify | `steps/5.md` | `superpowers:verification-before-completion` | Walk artifact in `record/`; every matrix row discharged at tier or waived; auditor CONFIRMED; regression run once |
| 6 Review | `steps/6.md` | `canonical-sdlc` | One fact per owed question at the head, or its waiver |
| 7 Document | `steps/7.md` | `agent-skills:documentation-and-adrs` | Every decision at medium significance or above is recorded |
| 8 Integrate | `steps/8.md` | `superpowers:finishing-a-development-branch` | Pull request merged; worktree removed; tmp ephemera wiped |
| 9 Close-out | `steps/9.md` | `agent-skills:shipping-and-launch` | Checklist + rollback; `continuation.md` written |

**Before any Step-N action, read `steps/N.md`. Before Step 4's first action and before the first dispatch, read `dispatch.md`. The load-time announcement names the file just read.**
<!-- BRIEF-SCAFFOLD-BEGIN -->
### Scaffold

```
Expected duration: <N> minutes
Expected artifact: <ONE path inside the repo, or a bare file name, e.g. .bionic/docs/record/<wave>/<name>.md>
Progress artifact: <path>  (tasks of 15 min or more)
Cadence: <N> min  (tasks of 15 min or more)
Done marker: <path>  # optional
Subprocess claim: <process pattern>   # a backgrounded watcher, e.g. gh run watch — optional
Files: <every path the task may create or edit>  # a reviewer lists its records here, one per question, its artifact among them; a researcher or test-runner omits it
Suites: none  # *.test.sh names or a path-qualified run.sh; other runners: Re-executes:; a reviewer dealt evidence names 1 to 3 runs across both labels
Re-executes: `<cmd>`
Questions: <q>[, <q>]  # reviewer roles only
Row: <id>  # the plan row a writer runs; the integrate row runs reviews-part <id>
Lands-on: <suite>[, <suite>] | none <reason>  # what ready proves, within Suites:
Lands-by: bash <plugin-root>/scripts/spawn-worktree.sh ready --within <seconds>
Lands-red: <suite> until <ext:slug | approval:name>  # optional
Red-evidence: <path under record/>  # with Lands-red:
Deliverable-waiver: <reason>  # only for a report returned by message
```
<!-- BRIEF-SCAFFOLD-END -->

Committing is a cross-cutting rhythm (~once per step), not a numbered step; the SHA lives in git.

**Engagement:** a clean run has five human stops: the configuration, requirements, design and plan cards, then the release approval card. Steps 4–9 are unattended within the stop-and-wake rules.

**Per-intent deltas.** `bugfix`: Step 4's failing test is the repro. `refactor`: the Step-2 spec is "behavior preserved"; a new acceptance criterion means reclassify as `build`. `tune`: Step 1 routes to the domain skill (`impeccable` for UX, `security-and-hardening`, `performance-optimization`) and Step 5 is the baseline→target→re-measure loop. `spike`: no plan file. `incident-response`: Step 1 compresses to triage, and triage asks first whether service can be restored NOW — if a revert restores it, revert and verify before debugging; Step 7 is an RCA (summary, timeline, root cause, contributing factors, the fix, prevention with commit links, monitoring-gap analysis); Step 9 is deploy with rollback → monitor ≥1 cycle → close the monitoring gap or prove there is none.

`scale: epic` short-circuits any intent after Step 3.

## Evidence shapes

A step's evidence is events in the run's log and the header a person wrote; `reader.sh <plan> step` answers the step. The gate asks the current step only.

| Step | What the gate asks |
|---|---|
| 1 | the requirements file the header's `epic:` and `wave:` name |
| 2, 3 | the approval of the step before |
| 4 | the header's `working-branch:` and `base-sha:` |
| 5 | the regression's proof, unless the header reads `regression: no`; every criterion discharged or waived; the walk proof (unless `walk: exempt`); the auditor's evidence review; the environments the walk proof covers. The whole run is Step 5's, once after the build; a red is a fix row's (`steps/5.md`) |
| 6 | one review proof per owed question at the head, or its waiver |
| 7 | the header's `adrs:` naming records that stand, or `none` with its reason |
| 8 | the integrate row's landing, every tree gone, and step 8's `cleanup`, `tmp-wiped`, `tasks-completed` from close-out |
| 9 | the delivery: step 9's `delivered` from close-out, closing the run, with `archived`; plus `deployed`, `verified`, `monitored` when `deploy_target` names a live surface |

**The matrix** is a view: a criterion is its Test design row, its state the log's (`reader.sh <plan> cell <AC>`).

**Placeholder ban.** These exact values are rejected anywhere evidence is required: `todo`, `pending`, `in progress`, `inprogress`, `xxx`, `tbd`, `placeholder`.

**Handoff.** A run spanning sessions hands off through `session-poker.sh handoff`, which writes `record/handoffs/<date>-<slug>.md` and one handoff event. Invoked with that file's path, run `session-poker.sh resume <path>` first and do what it prints. At Step 9 write `continuation.md` — wave completed, integration branch + merge SHA, next wave, open carry-overs.

## Hooks

**`engage.sh`** engages the session when this skill is invoked; no other hook acts before it.

**`bash-walls.sh`** (`PreToolUse|Bash`) fires only on a real `git commit` segment. It validates the session's bound run: the current step's evidence, the criteria, and the Tasks rows. **The gate reads the plan and the log as they are when the call starts, not as it will be once the rest of the command runs** — a Bash call that edits the plan and commits in the same invocation is judged on the pre-edit plan, so edit the plan in one call and commit in a separate one. Log-only (never blocks): the epic merge-target check. **A run changed around the tool** stops at the commit gate until the person rules in their own typed words, by `session-poker.sh accept '<their words>'` or `session-poker.sh abandon '<their words>'`; never type either for them.

**`canonical-sdlc-governing-skill.sh`** (`PreToolUse|Write,Edit`) blocks any artifact under `<docs-root>/{specs,plans,adrs,incidents}/` lacking `governing-skill:` frontmatter, and blocks a `mode:` line, a missing or non-enum triple, a missing flag or `model_plan`, a `walk:` value outside `required|exempt`, or a plan part no person wrote (`steps/3.md`). On a **spec** artifact at `scale: wave` or `scale: epic` it also blocks a write satisfying no arm of the three-way design rule: no flush-left `## Design` in place, no `design:` pointer resolving to a real file that itself carries a flush-left `## Design` (a dangling path, a target without the section, and a `..` component each fail the arm), and no `design-waived:` token. A `design:` pointer that is present is validated on the unwaived path whether or not the spec also carries its own section. On the same wave/epic **spec** it also blocks, from `sdlc-step ≥ 3` only, an `adrs:` frontmatter line naming a path (or several, joined by ` · `) that does not resolve to a real file — the momentous-ADR pointer D6 requires; below `sdlc-step 3` the arm is silent, since the ADR is drafted alongside the spec that names it. Plans and every task-scale artifact are untouched by it. Minimum-consistency checks are log-only, and log `user-overridden` in place of a minimum violation when frontmatter carries `rigor-override:` — presence only; the marker's fields are never validated, and it does not quiet a malformed `rigor-minimum:` value in `config.yaml`.

**Known holes — do not mistake these for enforcement.** Flag *values* are never checked, only presence. A proof names a record, so a record written for tests never run passes unseen. The fact gate knows who answered which question about which code, never that the answer is right, and a hand-typed `git merge` meets no gate: only the step advance, the integrate row and close-out ask it.

## Diagrams

`diagrams/lifecycle.svg` — the 10 steps, the two gates, and the commit rhythm. `diagrams/hook-chain.svg` — which hook fires on which tool event, and which arms block versus log. Neither is redrawn for version 15: read them for the hooks and the steps, not for what a gate reads.

**Format policy.** Composed SVG is the default for a diagram here; Excalidraw (`bionic:excalidraw-diagram`) is the backup, for a drawing whose layout is genuinely hand-arranged.
