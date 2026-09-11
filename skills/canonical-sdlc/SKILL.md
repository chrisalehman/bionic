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
  - agent-skills:code-review-and-quality
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
  - shape
  - impeccable
  - polish
  - critique
  - audit
  - harden
  - normalize
loading: deferred
---

<!-- GENERATED FILE — DO NOT EDIT.
     Rendered by agents-src/render.sh from agents-src/templates/skills/canonical-sdlc/SKILL.md.tmpl and the shared
     blocks in agents-src/blocks/. Edit those, then re-run `bash agents-src/render.sh`.
     tests/docs-pins.test.sh goes red whenever this file and its sources disagree. -->

# Canonical SDLC

Governs non-trivial engineering work. Every run declares a triple — `<intent> · <rigor> · <scale>` — and walks the applicable steps, leaving evidence a hook can read.

**Only the `## Hooks` section names anything that blocks. Everything else here is judgment, and you own it.**

**Iron law.** No commit without evidence from the current step. The evidence gate reads the plan's `current:` and validates that step's evidence only — it never re-checks earlier steps, so a skipped step is caught by review, not by code.

**Bulk reference.** Artifact shape, evidence-gating detail, intent-specific behaviors and the full version history live in `skills/canonical-sdlc/operational-rules.md`, beside this file. Read it when you need the detail this file compresses — it is copied with the skill, but nothing loads it for you.

## Load-time announcement

First user-facing action:

> **Canonical SDLC engaged — `<intent>` · `<rigor>` · `<scale>` (`<what that rigor buys>`).**

Triple not yet declared → say so and list the axes. Invoked as `help` → render the axis tables and stop.

## The triple

**intent** — what the deliverable is.

| Intent | Use when | Evidence delta |
|---|---|---|
| `build` | Capability that did not exist, or capability restored by ADDING machinery/interfaces/config (the machinery test). | RED→GREEN per slice. When the build IS a verification instrument, prove it CATCHES planted failures — a check that never fails is not proven to work. |
| `bugfix` | Restore intended behavior WITHIN the existing design. A repair, not new machinery. | The RED test is the failing repro. |
| `refactor` | Change structure, preserve behavior. Covers upgrades, migrations, removals/deprecations. | `behavior-preservation:` in the Step-5 block; migrations add `compat-matrix:`/`revert-plan:` (or `n/a: not a migration`). Log-only. |
| `tune` | Move a NAMED measurement toward a target. If you cannot name the measurement, it is not tune. | `baseline:`/`target:`/`re-measure:` in the Step-5 block, all three. Log-only. |
| `spike` | Timeboxed research. **Ships no code at any rigor.** | Writeup only at `<docs-root>/spikes/spike-<slug>-<YYYYMMDD>.md`. No plan file, no spec, no ADR, no commits to the integration branch. |
| `incident-response` | A live deployed surface — production or tooling — is broken for its users. The clock matters. | RCA, not ADR. Floors at `audited`. Monitoring-gap closure is part of Close-out. |

**Document and research deliverables — writeups, research reports — don't belong here.** Plain
plan mode serves them better than any row in this table, `spike` included: it ships no code at
any rigor, but its writeup is a timeboxed research artifact, not a general document-production
mode.

**rigor** — how hard the evidence tries to lie. Cumulative.

| Rigor | What you get | What you skip |
|---|---|---|
| `tested` | TDD RED→GREEN; matrix discharged at each row's tier; tests floor `pass == total`; 6-axis self-review. | Both independent assurance roles. Self-review only. |
| `peer-reviewed` | + a separate spec, + the INDEPENDENT Step-5 verification auditor on the evidence. At `scale: task` a ledger row must be proof-shaped and, once `done`, name an `auditor` verdict. | The mandatory adversarial critic. |
| `audited` | + the INDEPENDENT Step-6 adversarial critic, per-step checkpoint commits, expanded stop-and-wake. At `scale: task` a `done` row also names a `critic` verdict; at `scale: wave` an audited multi-agent plan must carry a `## Tasks` section at all. | Nothing. |

**scale** — the decomposition unit.

| Scale | Steps | Artifacts | Branch |
|---|---|---|---|
| `task` | Full set, compressed. Several per session. | ONE session plan with a `## Tasks` ledger; no per-task plan or spec. | The session's branch. |
| `wave` | Full set (0–9). Default. | One wave spec + plan; slices inside Step 4. | Wave branch off the epic integration branch; merges back at Step 8. |
| `epic` | 0–3 only. | `epic.spec.md` + `epic.plan.md`; carves waves. Does NOT run 4–9. | Owns `epic/NN-<slug>`; merges to mainline once, at close. |

**Rigor floors.** Default is scale-keyed: at `task`, `bugfix`→tested and `build`/`refactor`/`tune`→peer-reviewed; at `wave` and above, `audited`. Effective rigor is the MAX of the default and four floors — intent (`incident-response` floors at `audited`, `spike` is CAPPED at `tested`), flag (security-touching or privacy/vulnerable-population work floors at `audited`), project (`rigor-floor:` in `.bionic/config.yaml`), epic (`rigor-floor:` in epic frontmatter). Floors only push UP — the *derivation* is a MAX, never a subtraction. Provisional at Step 0, locked at Step 3. **Floors advise; they never force.** Upgrades are free, and a rigor below the derived floor is the user's to choose: advised against at Step 0, then accepted and recorded as `rigor-override:` (see the Override DSL). Nothing enforces the floors — the only check that reads them is log-only, and it logs `user-overridden` wherever that marker is present. One adjacent check does block, and it is not a floor: a task-ledger row whose rigor cell sits *below* the plan's own frontmatter `rigor:` is refused unless the row records a waiver. That is a consistency check against the value the plan declares — lower the frontmatter and the rows follow it down, so it never re-imposes a floor the user has overridden.

Do not carve a sensitive concern into a tiny unflagged wave to dodge a floor. The wave that owns the integration point carries the flag floor.

## Artifact layout

```
<docs-root>/specs/epic-NN-<slug>/{epic.spec.md, wave-NN-<slug>.spec.md, wave-NN-<slug>.requirements.md}
<docs-root>/plans/epic-NN-<slug>/{epic.plan.md, wave-NN-<slug>.plan.md}
<docs-root>/adrs/epic-NN-<slug>/adr-NNN-<slug>.md
<docs-root>/incidents/NNNN-<slug>/{spec.md, plan.md, rca.md}
<docs-root>/spikes/spike-<slug>-<YYYYMMDD>.md
<docs-root>/record/               # operational record: session logs, rotated archives,
                                  # closed-wave handoffs, inert audits. Survives Step 8.
<docs-root>/ideas/                # deferred-work briefs awaiting a wave to adopt them
.bionic/tests/                    # validation protocols re-run by hand, not by tests/run.sh
.bionic/tmp/                      # ephemera only, wiped at Step 8 — NOT a home for evidence.
                                  # Session-keyed state (engaged-/roster-/patrol-/preflight-/
                                  # sweeper-*.state) is NOT ephemera and survives that wipe
.bionic/.gitignore                # literally `*` — written on tree creation; this is what
                                  # keeps the whole tree out of git, not the project .gitignore
.bionic/config.yaml               # optional; `docs-root:` moves <docs-root> off the default
```

The first five are lifecycle artifacts and are gated: the governing-skill hook enforces
frontmatter on them and blocks a canonical artifact written anywhere else. `record/` and
`ideas/` are **operational** — nothing loads them, nothing validates them, and they are reached
only by citing a path. That is the whole distinction, and it is the boundary test applied to
this tree: growth in the gated dirs is governed, growth in the operational ones is free.

**Three artifacts, three steps** (design ledger K5; ADR-001) — Steps 1–3 write exactly one
artifact apiece, chained requirement → criterion → design decision → eval → evidence. Step 1
writes `wave-NN-<slug>.requirements.md`: numbered requirements/user stories, each with
provenance and acceptance criteria written so a "fails when" is nameable, plus Not Doing. Step
2 writes `wave-NN-<slug>.spec.md`: the technical design (domain model, architecture, ownership
table, rejected alternatives), the Eval design table, and ADR pointers. Step 3 writes
`wave-NN-<slug>.plan.md`: slices, sequencing, the dispatch ledger, and the verification matrix
rendered from Step 2's Eval design. Requirements live beside the spec, both under
`specs/epic-NN-<slug>/` — the governing-skill hook validates `*.requirements.md` frontmatter the
same way it validates `*.spec.md`, minus the design three-way rule (that stays spec-only). Each
of the three opens with a `## Goal` section — one concise paragraph, first after the title
(design ledger K5.4) — and a governing-skill arm at `scale: wave` or `scale: epic` refuses a
write whose first section is not Goal, or whose Goal section is empty.

**Anything the matrix cites as evidence goes in `record/`, never `tmp/`.** Auditor reports,
critic findings, review-axis artifacts, test-run captures — the matrix names them by path, so
they must outlive the run that produced them. `tmp/` is wiped at Step 8 and takes its contents
with it — everything, that is, except the session-keyed state the wipe spares by name, which is
live fleet state and not evidence either. Give an agent a `record/` path in its brief.

Every artifact carries frontmatter with `governing-skill:`, `sdlc-step:`, `intent:`/`rigor:`/`scale:`, `canonical_sdlc_version: 14`, the 5 discriminator flags, the 2 opt-in flags, and `model_plan:`. A missing one blocks the write. Artifacts never declare `mode:`. Plan files additionally carry `walk: required | exempt` — Step 0's derivation, and the key the Verify gate reads — Step 0's `design-interview:` value beside it, and, where the run's rigor sits below its derived floor, `rigor-override:` beside those. None of the three is required to write, but a `walk:` value outside the enum blocks. Spec files at `scale: wave` or `scale: epic` carry `design: <path>` or `design-waived: <user> <date> <reason>` unless the `## Design` section is in place — the three-way rule, Step 2.

**14 is the only supported version.** Any other value — an older number, an empty value, a typo — blocks at both hooks. There is one contract; an artifact either meets it or does not write. A run that predates it is brought forward to 14, not exempted.

## Steps

| Step | File | Governing skill | Gate |
|---|---|---|---|
| 0 Configure | `steps/0.md` | `canonical-sdlc` | Frontmatter complete, matrix derived, user confirmed, task list created |
| 1 Scope | `steps/1.md` | `agent-skills:idea-refine` | Refined idea + explicit "Not Doing" + alternatives lens cites prior art; writes `wave-NN-<slug>.requirements.md` — numbered requirements/user stories with provenance and acceptance criteria, plus Not Doing |
| 2 Design | `steps/2.md` | `agent-skills:spec-driven-development` | Every requirement has an acceptance criterion; every criterion cites its `provenance:`; wave+ carries a governing design; writes `wave-NN-<slug>.spec.md` — the technical design, ownership table, and the Eval design table |
| 3 Plan | `steps/3.md` | `superpowers:writing-plans` | No placeholders; `integration-branch:` present; matrix locked; slices tagged; user approved; writes `wave-NN-<slug>.plan.md` — slices, sequencing, and the verification matrix rendered from Step 2's Eval design |
| 4 Implement | `steps/4.md` | `agent-skills:incremental-implementation` | Every slice RED before GREEN; assumptions logged |
| 5 Verify | `steps/5.md` | `superpowers:verification-before-completion` | Walk artifact in `record/`; tests floor green; every matrix row discharged at tier or waived; auditor CONFIRMED |
| 6 Review | `steps/6.md` | `agent-skills:code-review-and-quality` | Every axis has a verdict; independent critic attached |
| 7 Document | `steps/7.md` | `agent-skills:documentation-and-adrs` | Every decision at medium significance or above is recorded |
| 8 Integrate | `steps/8.md` | `superpowers:finishing-a-development-branch` | Wave reachable from the integration branch; worktree removed; tmp ephemera wiped |
| 9 Close-out | `steps/9.md` | `agent-skills:shipping-and-launch` | Checklist + rollback; `continuation.md` written |

**Before any Step-N action, read `steps/N.md`. Before Step 4's first action and before the first dispatch, read `dispatch.md`. The load-time announcement names the file just read.**

Committing is a cross-cutting rhythm (~once per step), not a numbered step. Update `## SDLC State` **before staging** — the gate reads the file, not the diff. Do not add a `commit:` field; the SHA lives in git.

**Engagement:** Step 1 is interactive Q&A and is never skipped. Step 2 is semi-interactive, and its Design Interview is never skipped either — only the user may waive it. Step 3 ends at one approval checkpoint. Steps 4–9 are unattended within the stop-and-wake rules.

**Per-intent deltas.** `bugfix`: Step 4's failing test is the repro. `refactor`: the Step-2 spec is "behavior preserved"; a new acceptance criterion means reclassify as `build`. `tune`: Step 1 routes to the domain skill (`impeccable` for UX, `security-and-hardening`, `performance-optimization`) and Step 5 is the baseline→target→re-measure loop. `spike`: no plan file at all. `incident-response`: Step 1 compresses to triage, and triage asks first whether service can be restored NOW — if a revert restores it, revert and verify before debugging anything; Step 7 is an RCA (summary, timeline, root cause, contributing factors, the fix, prevention with commit links, monitoring-gap analysis); Step 9 is deploy with rollback → monitor ≥1 cycle → close the monitoring gap or prove there is none.

`scale: epic` short-circuits any intent after Step 3.

## Evidence shapes

One evidence artifact per step under `Step N:` in `## SDLC State`. The gate validates the current step only.

| Step | Required fields |
|---|---|
| 0 | `prereqs: ok` |
| 1, 2, 3 | pointer (presence only) |
| 4 | pointer; plus `worktree:`/`base-sha:`/`branch:` when `use_worktree: true` |
| 5 | `cmd:`/`pass:`/`total:`/`output:` with `pass == total`, a valid `## Verification Matrix`, `walk-artifact:` naming a real file under `<docs-root>/record/` once any row is `discharged` (unless `walk: exempt`), and — once no row is `pending`/`blocked` — a non-empty `auditor:` |
| 6 | pointer to the 6-axis body + critic findings; matrix re-validated here |
| 7 | `adr:` OR `rca:` OR `n/a:` |
| 8 | `merge:`, `worktree-removed:`, and (`cleanup:`, `tmp-wiped:`, `tasks-completed:` OR `cleanup: n/a`) |
| 9 | `delivered:` always, ON the `Step 9:` line itself — the run-closure predicate (`lib/run.sh`) greps that one line, so a `delivered:` written on a continuation line leaves the run open forever; `archived:` always, naming what `archive_run` moved or why nothing moved; plus `deployed:`, `verified:`, `monitored:` exactly when `deploy_target` names a live surface |

**Placeholder ban.** These exact values are rejected anywhere evidence is required: `todo`, `pending`, `in progress`, `inprogress`, `xxx`, `tbd`, `placeholder`.

**Handoff.** A plan spanning sessions carries a `## Handoff` section — resume point (step, sub-task, branch, last commit), decisions ratified this session (reset each time), tried-and-rejected and discovered surprises (persist), open blockers, uncommitted work, and a literal resume instruction. Rewritten in place, never appended. Nothing writes or checks it. At Step 9 write `continuation.md` — wave completed, integration branch + merge SHA, next wave, open carry-overs.

## Hooks

**`canonical-sdlc-evidence-gate.sh`** (`PreToolUse|Bash`) fires only on a real `git commit` segment. It finds the newest `*.md` under the plan dirs, and if it has a `## SDLC State` section, validates the current step's evidence, the matrix, and the task ledger. The `approved-by:` and `fails-when:` checks bind at every scale — a task-scale plan at `current: T<n>` is past Step 3. **From `current: 5` onward** it also blocks on `provenance: implementation` in any AC block — read flush left or as a flush-left list item (`AC-1:`, `- AC-1:`, `* AC-1:`, `+ AC-1:`; an indented header is not read) — and, once any row is `discharged` and the plan does not declare `walk: exempt`, on a missing `walk-artifact:` line, a path that does not resolve to a real file under `<docs-root>/record/`, or an AC identifier inside that file. **The gate reads the plan as it is when the call starts, not as it will be once the rest of the command runs** — a Bash call that edits the plan and commits in the same invocation is judged on the pre-edit plan, so edit the plan in one call and commit in a separate one. Log-only (never blocks): the epic merge-target check, and the `refactor`/`tune` intent-scoped Step-5 keys.

**`canonical-sdlc-governing-skill.sh`** (`PreToolUse|Write,Edit`) blocks any artifact under `<docs-root>/{specs,plans,adrs,incidents}/` lacking `governing-skill:` frontmatter, and blocks a `mode:` line, a missing or non-enum triple, a missing flag or `model_plan`, a `walk:` value outside `required|exempt`, or a missing `## Verification Matrix` at `sdlc-step ≥ 3`. On a **spec** artifact at `scale: wave` or `scale: epic` it also blocks a write satisfying no arm of the three-way design rule: no flush-left `## Design` in place, no `design:` pointer resolving to a real file that itself carries a flush-left `## Design` (a dangling path, a target without the section, and a `..` component each fail the arm), and no `design-waived:` token. A `design:` pointer that is present is validated on the unwaived path whether or not the spec also carries its own section. On the same wave/epic **spec** it also blocks, from `sdlc-step ≥ 3` only, an `adrs:` frontmatter line naming a path (or several, joined by ` · `) that does not resolve to a real file — the momentous-ADR pointer D6 requires; below `sdlc-step 3` the arm is silent, since the ADR is drafted alongside the spec that names it. Plans and every task-scale artifact are untouched by it. Floor-consistency checks are log-only, and log `user-overridden` in place of a floor violation when frontmatter carries `rigor-override:` — presence only; the marker's fields are never validated, and it does not quiet a malformed `rigor-floor:` value in `config.yaml`.

**Known holes — do not mistake these for enforcement.** The governing-skill hook validates `Write` content but not `Edit` content, so one valid write covers every later edit. Flag *values* are never checked, only presence. The evidence gate reads the plan file's text, so an `Edit` that writes evidence for tests never run passes unseen. Proof-shape is a heuristic: a digit plus a `/` satisfies it.

## Diagrams

`diagrams/lifecycle.svg` — the 10 steps, the two gates, and the commit rhythm. `diagrams/hook-chain.svg` — which hook fires on which tool event, and which arms block versus log. Each file is its own sole source: hand-composed text, no paired drawing file, no export step, and so nothing that can be stale relative to it. Because the text is greppable, `tests/cross-gate-agreement.test.sh` §V pins the four version renderings across both SVGs against the hooks' `SUPPORTED_SDLC_VERSION`, with a mutation arm that re-proves the pin against a doctored copy on each run. The six always-on entries against `hooks/hooks.json` and the ten steps and the armed hook set against this file are not pinned by anything yet — `tests/diagrams.test.sh`, the suite this paragraph used to cite for all of it, does not exist.

**Format policy.** Composed SVG is the default for a diagram here, because it is the only format that is simultaneously the editable source, the shipped artifact, and a test surface. Excalidraw (`bionic:excalidraw-diagram`) is the backup, for a drawing whose layout is genuinely hand-arranged rather than composed; it ships an export beside its source and re-accepts the is-that-current relationship, so reach for it when the picture is worth that cost. Any other format is a judgment call, argued at the time against one question: what will pin this picture to the truth after its author has moved on.
