# bionic

One engineer, mass-augmented. A single bootstrap turns Claude Code into a structured engineering practice — parallel specialist teams, an enforced SDLC, and guardrails that block the commands you'd regret.

```bash
git clone https://github.com/chrisalehman/bionic.git
cd bionic
./claude-bootstrap.sh                                # core profile
./claude-bootstrap.sh claude-config.everything.txt   # core + full catalog
```

Re-run anytime to update — it's idempotent. Reset with `./claude-reset.sh` (same profile arguments).

**Exit codes:** `0` success (env-gated skips and warnings included) · `1` ran to completion but some steps failed — fix the cause and re-run · `2` preflight hard-fail (no network, or Homebrew / the claude CLI couldn't be installed).

**Fresh Mac note:** the first run may ask for your macOS password and open the Xcode Command Line Tools dialog (Homebrew needs them) — expected; everything else is unattended.

## Patterns That Change How You Ship

Most AI tooling demos show one agent completing one task. These patterns are what happens when you treat agents like an engineering organization instead — specialization, parallelism, feedback loops, async coordination.

**Agentic Teams** — Dispatch parallel specialists instead of feeding everything through one context window. Audits, refactors, migrations, incident investigations get decomposed across concurrent agents and synthesized. No serious org assigns one engineer to do the security review, perf analysis, and accessibility audit in one sitting.

**Canonical SDLC** — Bionic's flagship pattern, and the reason most of this repo exists. A 10-step lifecycle (configure → scope → design → plan → implement → verify → review → document → integrate-&-close → ship) built around two gates: Verify ("does it work?") and Review ("is it well-made?"). Every run declares an `intent · rigor · scale` triple that sets how hard the evidence has to try to lie. Two hooks enforce it — one rejects malformed plans on write, the other blocks commits lacking evidence for the current step. Steps 1–3 are interactive; 4–9 run unattended and leave an auditable record. → [`skills/canonical-sdlc/SKILL.md`](skills/canonical-sdlc/SKILL.md)

**Subagent SDLC Pipeline** — A lighter lifecycle from the superpowers plugin: brainstorm → design decisions with explicit tradeoffs → plan → TDD → parallel execution → review. Use it for one-off changes; use canonical-sdlc when the work is wave-sized and worth the audit trail.

**Autonomous Debug Cycles** — A closed loop: test → analyze → hypothesize → fix → rebuild → validate against a running app via Playwright. The agent doesn't propose a fix and wait; it executes, observes, and iterates until green or until it needs you. You come back to a resolved issue, not a diagnostic report.

**Agentic QA** — When the system under test contains agents, deterministic assertions break immediately. Agentic QA uses agent-based tests that observe outputs, adapt to variation, and validate *intent* rather than exact values. Most teams haven't hit this problem yet, and will the moment they ship agents.

**Domain Specialists on Demand** *(opt-in)* — 100+ VoltAgent specialists: Kubernetes debugger, PostgreSQL optimizer, Terraform engineer, Rust systems programmer. They live in the catalog profile rather than core because their descriptions cost ~5k tokens of context every session. Core ships six hand-written roles instead, carrying the duties canonical-sdlc dispatches against.

**Remote Control** — Claude Code from your phone. The value isn't mobile access, it's async engineering: launch a refactor, get notified when the agent needs an architectural decision, approve it, move on. Throughput decouples from whether you're at a terminal.

## First Session

After bootstrap, try this in any project:

```
Audit this codebase — dispatch an Agent Team. Security, performance, and
architecture reviewed in parallel. Synthesize findings.
```

Watch Claude decompose the request across concurrent specialists — one surfaces a vulnerability, another flags a query bottleneck, a third challenges a layering boundary. Results arrive synthesized, not sequential.

Other things to try on day one:

- `Fix this failing test. Run it. Iterate until green. Show me the result.`
- `Refactor this module — full SDLC: design decision first, then implement.`
- `Optimize this query. Measure before and after.`

## What You Get

The core profile is [`claude-config.txt`](claude-config.txt) — the authoritative list. Edit it and re-run the bootstrap.

| Category | What |
|---|---|
| **CLI tools** | git, node, pnpm, gh, jq, ripgrep, uv, docker, yq, aws, gcloud *(cask)*, @playwright/cli, @pencil.dev/cli, notebooklm *(via uv)* |
| **Plugins** | superpowers *(TDD, debugging, planning, worktrees)*, agent-skills *(ideation, review rubrics, git workflow)*, document-skills *(xlsx, docx, pptx, pdf)*, example-skills, frontend-design |
| **Subagent roles** | implementor, senior-implementor, researcher, auditor, critic, test-runner — hand-written, carrying the invariant duties canonical-sdlc dispatches against |
| **MCP servers** | context7, chrome-devtools *(Pencil's server self-registers whenever the Pencil app is running)* |
| **Skills** | **bionic:canonical-sdlc** *(flagship)*, bionic:browser-verify, bionic:map-instrument-narrow, bionic:excalidraw-diagram, humanizer, notebooklm, impeccable |
| **Hooks** | Global: protect-main, protect-database, plus agent-context-guard wrappers for depth coverage. Armed-session only (registered by the canonical-sdlc skill on invocation): farm-out-reminder, the evidence/governing-skill gates, context-spend, and the landing/supervision fleet |
| **Philosophy** | Operating principles and approval boundaries → [`claude-global.md`](claude-global.md), installed to `~/.claude/CLAUDE.md` |
| **Shell alias** | `claude` → `claude --dangerously-skip-permissions` |

**Why Playwright CLI and not the Playwright MCP server:** the MCP server injects full page snapshots into the context window on every turn; the CLI keeps browser state on disk and returns compact snapshots and file paths. Bionic still installs the Chrome DevTools MCP for the inspection side — traces, Lighthouse, throttling — because that fires once per investigation rather than once per turn. Driving and inspection are separate lanes, and the [`browser-verify`](skills/browser-verify/SKILL.md) skill routes between them.

**Optional catalog.** [`claude-config.everything.txt`](claude-config.everything.txt) layers on deployment platforms (stripe, vercel, supabase, fastlane, eas-cli), API tooling (httpie, grpcurl, protoc), observability (Sentry CLI + MCP), Trello, and the 100+ VoltAgent specialist packs. Entries needing credentials skip with a warning when the env vars are absent. Kubernetes, database, and Firebase sections ship commented out — uncomment to enable. Profiles are additive and layered as positional arguments; teams can add their own `claude-config.<team>.txt`.

## What Blocks You

Bionic installs six hooks. Five can stop a tool call before it runs; one only emits advice.

| Hook | Event | Blocks? | What it does |
|---|---|---|---|
| `protect-main.sh` | Bash | **yes** | Rejects pushes to main/master and force-pushes |
| `protect-database.sh` | Bash | **yes** | Rejects destructive SQL — DROP, TRUNCATE, DELETE without WHERE |
| `farm-out-reminder.sh` | Bash | **yes** | Pushes heavy commands off the main thread into subagents |
| `canonical-sdlc-governing-skill.sh` | Write, Edit | **yes** | Rejects plan/spec/ADR files with malformed frontmatter |
| `canonical-sdlc-evidence-gate.sh` | Bash | **yes** | Rejects commits lacking evidence for the plan's current step |
| `context-spend.sh` | Stop | no | Records per-session context spend |

**If a command gets denied and you meant it:** `farm-out-reminder.sh` blocks test suites, builds, installs, and long `&&` chains on the main thread to protect your context budget. Prefix with `FARM_OUT_ALLOW=1` to override — it must be in command position, so `FARM_OUT_ALLOW=1 npm test`, not `cd foo && FARM_OUT_ALLOW=1 npm test`.

Every hook has a paired `*.test.sh` suite. Run all of them with `./test.sh`.

## Safety

Hooks are the hard layer — they intercept tool calls and block what you'd regret. [`claude-global.md`](claude-global.md) is the judgment layer, teaching Claude when to act, when to pause, and when to escalate, plus the operations that always require your approval: secrets and credentials, anything touching billing, and production infrastructure.

The shell alias runs Claude with `--dangerously-skip-permissions`. That removes the per-call approval prompt, not the guardrails — the hooks still hard-block the dangerous operations, and they run regardless of the alias.

## Requirements

**macOS:** none. The preflight installs Homebrew and the Claude Code CLI (`npm install -g @anthropic-ai/claude-code@latest` — the npm channel; the Homebrew cask lags versions behind) if they're missing. Expect one password prompt on a fresh Mac.

**Windows (WSL2):**

1. Open PowerShell as Administrator: `wsl --install`
2. Restart your computer
3. Open the Ubuntu terminal from the Start menu
4. Clone this repo and run the one-time setup:
   ```bash
   git clone https://github.com/chrisalehman/bionic.git
   cd bionic
   ./wsl-setup.sh
   ```
5. Then run the bootstrap: `./claude-bootstrap.sh`

## Where Things Live

| What | Where |
|---|---|
| What gets installed | [`claude-config.txt`](claude-config.txt) · [`claude-config.everything.txt`](claude-config.everything.txt) |
| Operating philosophy | [`claude-global.md`](claude-global.md) |
| Skills | [`skills/`](skills/) — each has its own `SKILL.md` |
| Hooks | [`hooks/`](hooks/) — each has a paired `.test.sh` |
| Subagent roles | [`agents/`](agents/) |
| Tests | `./test.sh` → [`tests/run.sh`](tests/run.sh) |
