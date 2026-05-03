# Canonical SDLC

Bionic's flagship engineering pattern. A 14-step autonomous software development lifecycle that runs unattended for hours and produces an auditable record at the end.

This document is the user-facing reference. The full design rationale lives in `docs/bionic/plans/canonical-sdlc-autonomous-redesign.md` (gitignored — local-only); the skill prose lives at `~/.claude/skills/canonical-sdlc/SKILL.md` after bootstrap.

---

## What it is

Three things working together:

1. **A skill** (`canonical-sdlc`) that Claude invokes at session start. It's a 14-step lifecycle: ideate → spec → plan → isolate → implement → browser-verify → verify-done → review → adversarial-critic → document → commit → external-review → finish → ship. With Step 0.5 (Configure) wedged between Step 0 (Prereqs) and Step 1 to confirm flag values, and Step 12.5 (Cleanup) between Step 12 and Step 13 for opt-in post-merge cruft removal.

2. **Three coordinating hooks** (registered globally by `claude-bootstrap.sh`):
   - `canonical-sdlc-governing-skill.sh` (`PreToolUse|Write,Edit`) — blocks plan/spec/adr file writes that lack valid frontmatter. v2 plans must declare 4 opt-in flags + 8 discriminator flags + `canonical_sdlc_version: 2`. v1 plans are grandfathered.
   - `canonical-sdlc-dispatch-gate.sh` (`PreToolUse|Agent`) — reads `.bionic/sdlc-dispatch-rules.json` + the active plan's frontmatter; routes Agent calls to the right specialist per phase. Default behavior is log-only; flip per-plan via `dispatch_enforce: true` to start blocking.
   - `canonical-sdlc-evidence-gate.sh` (`PreToolUse|Bash`) — blocks `git commit` when the current step's evidence is missing or shape-invalid. v2 plans get per-step required-field enforcement; legacy plans get presence-only checks.

3. **A rules JSON** (`.bionic/sdlc-dispatch-rules.json`) — pre-populated for all 14 phases plus 8b (adversarial). Edits take effect immediately; the hook reads fresh on every call.

---

## When to use it

- **Wave-sized work** (1–3 days, 5–15 commits, all 14 SDLC steps reachable). Default mode `autonomous`.
- **Multi-day epic** that needs to be carved into waves. Mode `epic-scope`.
- **Production incident** needing detection confirmation, diagnosis, fix, deploy, monitoring gap closure, postmortem RCA. Mode `incident-response`.
- **UX/visual refresh** on an existing feature. Mode `design-refresh`.
- **Timeboxed research / prototype, no code ships.** Mode `spike`.

For one-off changes (typo fix, single-file refactor), use `superpowers:writing-plans` directly without invoking canonical-sdlc — the audit trail isn't worth the overhead.

---

## v2 frontmatter schema

Every canonical-sdlc plan declares its configuration in YAML frontmatter at the top of the plan file. Step 0.5 (the wizard) writes this; the governing-skill hook enforces presence.

```yaml
---
# IDENTITY
governing-skill: canonical-sdlc
mode: autonomous              # autonomous | epic-scope | incident-response | design-refresh | spike
sdlc-step: 5                  # 0..13, or "8b"
canonical_sdlc_version: 2     # 1 = legacy (grandfathered); 2 = current
epic: epic-04-dispatch-hardening    # optional
wave: wave-02-rules-json            # optional
incident: null                # incident-response only

# DISPATCH DISCRIMINATORS (drives rules JSON predicate evaluation)
surface_type: api             # api | graphql | ui | system | realtime | mobile | ml | iac | none
language: typescript          # rust | typescript | javascript | go | python | java | csharp |
                              #   cpp | php | swift | kotlin | sql | other | none
perf_critical: false          # bool
security_boundary: false      # bool — touches authn/authz/secrets/PII
distributed: false            # bool — multi-service / queue / replication concerns
has_ui: false                 # bool — produces UI surface
multi_agent: false            # bool — work spans multiple agent specialties
deploy_target: none           # none | k8s | vercel | custom | migration

# V2 OPT-IN FLAGS (per-plan rollout control; all REQUIRED for autonomous)
narrative_verbose: false      # opt-in to narrative-tier evidence sections
dispatch_enforce: false       # when true, dispatch-gate hook blocks wrong agents
cleanup_on_finish: false      # when true, Step 12.5 runs post-merge cleanup
archived: false               # when true, Step 12.5 writes pre-cleanup snapshot to .bionic/evidence-archive/

# AUDIT
created: 2026-05-02           # ISO date
cleaned: null                 # ISO date — set by Step 12.5 when cleanup runs
evidence_schema: v2           # v2 = current shape-checked; legacy = pre-redesign presence-only
---
```

Plans with `canonical_sdlc_version: 1` are grandfathered: governing-skill hook skips v2 flag presence check, dispatch-gate hook skips entirely, evidence-gate uses presence-only path. The migration script (see below) sets `canonical_sdlc_version: 1` + `evidence_schema: legacy` on every existing plan automatically, so in-flight work is unaffected when v2 lands.

---

## Mode selector

| Mode | When | Steps applied | `narrative_verbose` default |
|---|---|---|---|
| `autonomous` (default) | Any wave-level build, fix, refactor, or user-facing work | 1–13; Step 8b adversarial mandatory; per-step checkpoint commits; full stop-and-wake | `false` (strip narrative — execution record, not deliverable) |
| `epic-scope` | Beginning a new epic; needs carving into waves | 1–3 only; produces `epic.spec.md` + `epic.plan.md` | `true` (synthesis IS the artifact) |
| `incident-response` | Live or recent production incident | Triage 1 → 2–8 → Step 9 produces RCA → 10 → 11 (waivable) → 12 → 13 includes monitoring verification | `true` (RCA narrative is the deliverable) |
| `design-refresh` | UX/visual refresh; no behavior change | `shape` prepended to Step 1; Step 5 uses `impeccable` family; Step 6 heavily weighted | `true` (rationale is part of the handoff to design reviewers) |
| `spike` | Timeboxed research/prototype; **no code ships** | Prereqs → woven source-driven → brief writeup. No worktree, no ADR, no commits to integration branch | `false` (timeboxed; no deliverable) |

---

## Step 0.5 — Configure (wizard)

Wedged between Step 0 (Prereqs) and Step 1 (Ideate). Mandatory for v2 plans; skipped for legacy.

The skill executes three substeps:

1. **Infer recommended values** from context: file signals (`package.json` / `Cargo.toml` / `tsconfig.json` etc. → `language`), conversation keywords (`"REST endpoint"` → `surface_type: api`; `"auth"` / `"PII"` → `security_boundary: true`; etc.).
2. **Present a single confirmation display** showing every flag + reasoning string. Not multiple `AskUserQuestion` calls — one structured screen.
3. **Block until explicit confirmation.** No timeout, no implicit acceptance.

The user replies with the override DSL: `confirm` to accept defaults, or `set <flag>=<value>, ..., confirm` to override.

Three-layer enforcement: this skill (soft), governing-skill hook (hard — blocks Write/Edit if v2 flags missing), backstop on first plan-file Write.

---

## Step 12.5 — Post-merge cleanup (opt-in)

Runs after Step 12 (merge) and before Step 13 (ship), only when `cleanup_on_finish: true`. The 9-step procedure:

1. Idempotency check — abort if `cleaned:` already set.
2. Identify keep-verbatim content (verification tier in full + frontmatter + acceptance-criteria approval lines).
3. Decide handoff fate: single-session plans drop `## Handoff`; multi-session plans keep it.
4. Strip narrative cruft (8-line approval paragraphs → one-line summaries; in-summary blocks deleted; navigation pointers deleted).
5. Consolidate `Phase N: N/A` rows into a single `Skipped: ...` line.
6. Optional archive when `archived: true` — write pre-cleanup snapshot to `.bionic/evidence-archive/<YYYY-MM-DD>-<slug>.md`.
7. Set frontmatter `cleaned: <today>`.
8. Append `Step 12.5: cleanup: ok, archived: ..., narrative-stripped: <count>, handoff: <kept|stripped>`.
9. Commit as a follow-up: `chore(plan): post-merge cleanup of <slug>`.

When `cleanup_on_finish: false` (default), Step 12.5 records `Step 12.5: n/a: cleanup_on_finish=false` and proceeds to Step 13.

---

## Three-tier evidence

Each plan carries evidence in three independent tiers:

| Tier | Always present? | Controlled by | Enforced by |
|---|---|---|---|
| **Verification** | Yes — mandatory | (no flag) | `canonical-sdlc-evidence-gate.sh` (presence + shape on v2 plans) |
| **Handoff** | Only when plan spans sessions | session-end trigger | Skill prose + Stop-hook checkpoint |
| **Narrative** | Optional | `narrative_verbose: true` | Skill prose (warns when off; never blocks) |

### Verification — per-step shape table

For v2 plans, the evidence-gate hook enforces these required fields under `Step N:` in the plan's `## SDLC State` section:

| Step | Required fields | Notes |
|------|-----------------|-------|
| 0 | `prereqs: ok` | Smoke-test |
| 1, 2, 3, 5, 8, 8b | Pointer to body section | Hook is presence-only for pointer steps |
| 4 | `worktree:`, `base-sha:`, `branch:` | Verifiable against `git worktree list` |
| 6 | `devtools-trace: <path>` OR `n/a: <reason>` | Pick one |
| 7 | `cmd:`, `pass:`, `total:`, `output:` | `pass == total` required to close the step |
| 9 | `adr: <path>` OR `rca: <path>` (incident-response) OR `n/a: <reason>` | Pick one |
| 10 | `commit:`, `subject:`, `files:` | Subject follows project commit convention |
| 11 | `pr: <url>` OR `n/a: <reason>` | `n/a: PR-less workflow` for local-merge |
| 12 | `merge:`, `worktree-removed:` | `git worktree list` confirms |
| 12.5 | `cleanup:`, `archived:`, `narrative-stripped:`, `handoff:` OR `n/a: cleanup_on_finish=false` | Only when `cleanup_on_finish: true` |
| 13 | `deploy:`, `verified-at:`, `monitor:` OR `n/a: <reason>` | `n/a` only valid when `deploy_target: none` |

Block format — multi-field evidence:

```
Step 7:
  cmd: bash test.sh
  pass: 332
  total: 332
  output: docs/bionic/plans/<slug>.plan.md#step-7
```

### Handoff — multi-session contract

A `## Handoff` section in the plan body, always preserved when the plan spans sessions regardless of `narrative_verbose`. Per-field caps total ~5000 chars (~1300 tokens). Persistence: `Resume point` overwritten each session; `Decisions ratified this session` resets each session; `Tried and rejected` / `Discovered surprises` persist with deduplication.

Triggered at: session end mid-plan, context-compaction risk (~90%), explicit user `/checkpoint`. The skill **rewrites the section in place** — never appends. A 3-session plan has the same handoff size as a 1-session plan.

### Narrative — opt-in

When `narrative_verbose: false` (autonomous default), these patterns trigger warnings (never blocks): navigation pointers, restated state outside frontmatter, repeated `Phase N: N/A` rows, "in summary" / "to recap" prose, approval-checkpoint paragraphs that don't reference acceptance criteria.

When `narrative_verbose: true` (epic-scope / incident-response / design-refresh defaults), all patterns are tolerated.

Independence: handoff is always preserved when multi-session, regardless of `narrative_verbose`.

---

## Dispatch routing

Per-phase rules in `.bionic/sdlc-dispatch-rules.json` (15 phase keys: 0–13 + 8b). Each rule is one of:

```json
{ "when": "<predicate>",  "agent": "<agent-id>" }
{ "when": "<predicate>",  "agents": ["...", "..."], "parallel": true }
{ "always": true,         "agent": "..." }
{ "default": true,        "agent": null | "..." }
```

Predicate grammar (subset implemented in v1): `<flag> == 'value'`, `<flag> == true|false`, `<atom1> && <atom2>`. Set membership and negation are reserved for future use.

Examples baked into the seed rules:

- Step 5, `language == 'typescript'` → `voltagent-lang:typescript-pro`
- Step 5, `surface_type == 'mobile' && language == 'swift'` → `voltagent-lang:swift-expert`
- Step 8 (always) → parallel `voltagent-qa-sec:code-reviewer` + `voltagent-qa-sec:security-auditor`
- Step 8 + `perf_critical == true && surface_type == 'system'` → 4-way parallel including architect-reviewer + performance-engineer
- Step 8b + `security_boundary == true` → `voltagent-qa-sec:penetration-tester`

`agent: null` means "no specialist required — main thread handles directly". Used for phases 0, 1, 4, 11 (and as default for 2/3/5/6/10/12/13 when no discriminator matches).

### Override

Include `dispatch_override: "<one-line reason>"` anywhere in the Agent call's prompt. The hook detects, logs to `.bionic/memory/dispatch-audit.md`, and allows the call regardless of subagent_type. Reviewed weekly during sprint-1; recurring overrides on the same expected→got pair signal a missing rule.

### Default behavior — log-only

`dispatch_enforce: false` is the sprint-1 default. Mismatches log to `.bionic/memory/dispatch-audit.md` with a `log-only` tag but never block. Flip to `true` per-plan once the audit log shows your rules are calibrated. Default flips to `true` after 2+ plans demonstrate value across at least one specialty discriminator.

---

## Migrating in-flight plans (legacy → v1-grandfathered)

When canonical-sdlc v2 first deploys via `./claude-bootstrap.sh`, every existing plan in your project's `docs/bionic/plans/` (and other plan-location conventions) needs `canonical_sdlc_version: 1` added to its frontmatter — otherwise the new governing-skill hook blocks the next `Write`/`Edit` because the version field is missing.

The migration script handles this:

```bash
# Per-file (recommended for one-by-one):
bash ~/.claude/skills/canonical-sdlc/migrate-frontmatter.sh path/to/plan.md

# Sweep an entire directory:
find docs/bionic/plans -type f -name '*.md' \
  -exec bash ~/.claude/skills/canonical-sdlc/migrate-frontmatter.sh {} \;
```

The script is idempotent — re-running on an already-migrated file is a no-op. It adds three fields if missing: `canonical_sdlc_version: 1`, `evidence_schema: legacy`, `created: <today>`. It only operates on files matching the canonical-sdlc artifact patterns (`*.plan.md`, `*.spec.md`, `adr-*.md`, `continuation*.md`); other files are silently skipped.

Files without YAML frontmatter at all are skipped with a stderr warning — they're either non-canonical-sdlc artifacts (which is fine) or malformed plans (which need manual frontmatter creation, not migration).

Your migrated plans run under v1 grandfathering forever (or until you choose to manually rewrite to v2 schema). The hook chain treats them as legacy: governing-skill checks only the `governing-skill:` field; dispatch-gate skips entirely; evidence-gate uses the pre-redesign presence-only path.

---

## Hook behavior matrix

| Plan state | governing-skill (`Write`/`Edit`) | dispatch-gate (`Agent`) | evidence-gate (`git commit`) |
|---|---|---|---|
| No frontmatter at all (non-canonical-sdlc plan) | Pass through if filename doesn't match enforcement patterns | Pass — no governing-skill | Pass — no `## SDLC State` |
| `governing-skill: canonical-sdlc` + `canonical_sdlc_version: 1` | Pass (legacy-skip) | Pass (legacy-skip) | Presence + placeholder check (legacy behavior) |
| `governing-skill: canonical-sdlc` + `canonical_sdlc_version: 2` + `mode: autonomous` + all v2 flags | Pass | Per phase rule (log-only by default) | Presence + shape (when `evidence_schema: v2`) |
| Same but missing one v2 flag | **Block** — error names missing flag | Pass (governing-skill catches first) | Block at commit time on shape if applicable |
| `governing-skill != canonical-sdlc` (e.g. `superpowers:writing-plans`) | Pass after governing-skill: presence check | Pass — not a canonical-sdlc plan | Presence-only (existing behavior) |

---

## Empirical validation status

The redesign ships with synthetic validation via the test suite (10 hook test files, 426 assertions total — 100% green on the chained branch):

- `canonical-sdlc-evidence-gate.test.sh` — 55 cases covering legacy + v2 shape paths, all per-step required-field combinations, n/a forms, deploy-target gating.
- `canonical-sdlc-governing-skill.test.sh` — 30 cases covering v1/v2/missing-marker branches, governing-skill presence, autonomous-mode flag enforcement.
- `canonical-sdlc-dispatch-gate.test.sh` — 35 cases covering all 16 design-doc test scenarios plus parallel-allow, audit-content checks, conjunction predicate (`mobile && swift`), Step 8b boundary, multi_agent ordering.

What synthetic validation **does not** prove: real-world calibration. Whether the rules JSON's predicate ordering is right for actual workflows. Whether the audit log accumulates noise that signals rule gaps. Whether `narrative_verbose: false` actually produces cleaner records without losing useful context. Whether `cleanup_on_finish: true` strips the right things and preserves the right things.

The deferred validation arm (originally Wave 6 of the design's migration plan):

1. Pick a wave-sized feature in this repo (or another project that opts in by copying `~/.claude/skills/canonical-sdlc/sdlc-dispatch-rules.json` into its own `.bionic/`).
2. Run with `dispatch_enforce: true`, `narrative_verbose: false`, `cleanup_on_finish: true`, `archived: true` in the plan frontmatter.
3. Watch `.bionic/memory/dispatch-audit.md` for mismatch entries. Categorize: rule wrong, flag missing, override legitimate.
4. After 2-3 plans complete cleanly, flip individual default flags (`dispatch_enforce` → `true`; `narrative_verbose` → `false` for autonomous; etc.) one at a time. Each flag has independent risk; don't flip in lockstep.
5. After a flag's default has flipped and 30+ days pass with no override usage, the flag becomes a candidate for retirement (hard-coded into the skill, removed from the Step 0.5 wizard).

The empirical arm calibrates and retires flags. The current ship is opt-in scaffolding designed to be temporary.

---

## Pointers

- **Skill prose** (post-bootstrap): `~/.claude/skills/canonical-sdlc/SKILL.md`
- **Hooks** (post-bootstrap): `~/.claude/hooks/canonical-sdlc-{evidence-gate,governing-skill,dispatch-gate}.sh`
- **Rules JSON template** (post-bootstrap): `~/.claude/skills/canonical-sdlc/sdlc-dispatch-rules.json`
- **Per-project rules JSON** (deployed by bootstrap on bionic itself; copy manually for other projects): `<project>/.bionic/sdlc-dispatch-rules.json`
- **Migration script**: `~/.claude/skills/canonical-sdlc/migrate-frontmatter.sh`
- **Audit log** (auto-created on first append): `<project>/.bionic/memory/dispatch-audit.md`
- **Source-of-truth design doc** (local-only): `docs/bionic/plans/canonical-sdlc-autonomous-redesign.md`
