# bionic

One engineer, mass-augmented. Bionic is a Claude Code plugin that turns the CLI into a structured engineering practice — parallel specialist teams, an enforced SDLC, and guardrails that block the commands you'd regret.

## Installation (30-second setup)

### 1. Get bionic

```bash
claude plugin marketplace add chrisalehman/bionic
claude plugin install bionic
```

The first tells Claude Code where bionic lives; the second installs it.

<details>
<summary>From inside a session</summary>

```
/plugin marketplace add chrisalehman/bionic
/plugin install bionic
```

</details>

### 2. Run `/bionic:setup`

It will ask about:

- Tools bionic's skills use, one at a time
- Optional extras, each with a one-line why — default no
- Whether to set Claude Code's permission mode to auto (recommended)

### 3. Done.

`/bionic:help` for the tour, `/bionic:doctor` if anything looks off. If `/bionic:doctor`
isn't recognized, run `claude plugin list` — the Error line says why.

## Patterns That Change How You Ship

Most AI tooling demos show one agent completing one task. These patterns are what happens when you treat agents like an engineering organization instead — specialization, parallelism, feedback loops, async coordination.

**Agentic Teams** — Dispatch parallel specialists instead of feeding everything through one context window. Audits, refactors, migrations, incident investigations get decomposed across concurrent agents and synthesized. No serious org assigns one engineer to do the security review, perf analysis, and accessibility audit in one sitting.

**Canonical SDLC** — Bionic's flagship pattern, and the reason most of this repo exists. A 10-step lifecycle (configure → scope → design → plan → implement → verify → review → document → integrate-&-close → ship) built around two gates: Verify ("does it work?") and Review ("is it well-made?"). Every run declares an `intent · rigor · scale` triple that sets how hard the evidence has to try to lie. Two hooks enforce it — one rejects malformed plans on write, the other blocks commits lacking evidence for the current step. Steps 1–3 are interactive; 4–9 run unattended and leave an auditable record. → [`skills/canonical-sdlc/SKILL.md`](skills/canonical-sdlc/SKILL.md)

**Subagent SDLC Pipeline** — A lighter lifecycle from the superpowers plugin: brainstorm → design decisions with explicit tradeoffs → plan → TDD → parallel execution → review. Use it for one-off changes; use canonical-sdlc when the work is wave-sized and worth the audit trail.

**Autonomous Debug Cycles** — A closed loop: test → analyze → hypothesize → fix → rebuild → validate against a running app via Playwright. The agent doesn't propose a fix and wait; it executes, observes, and iterates until green or until it needs you. You come back to a resolved issue, not a diagnostic report.

**Agentic QA** — When the system under test contains agents, deterministic assertions break immediately. Agentic QA uses agent-based tests that observe outputs, adapt to variation, and validate *intent* rather than exact values. Most teams haven't hit this problem yet, and will the moment they ship agents.

**Remote Control** — Claude Code from your phone. The value isn't mobile access, it's async engineering: launch a refactor, get notified when the agent needs an architectural decision, approve it, move on. Throughput decouples from whether you're at a terminal.

## First Session

Try this in any project:

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

| Category | What |
|---|---|
| **Skills** | **bionic:canonical-sdlc** *(flagship)*, bionic:browser-verify, bionic:map-instrument-narrow |
| **Subagent roles** | implementor, senior-implementor, researcher, auditor, critic, test-runner — hand-written, carrying the invariant duties canonical-sdlc dispatches against |
| **Hooks** | Six always-on walls plus the armed-session fleet — see below |
| **Plugin dependencies** | superpowers *(TDD, debugging, planning, worktrees)* and agent-skills *(ideation, review rubrics, git workflow)*, installed by the CLI as bionic's declared dependencies |
| **Tier-2 dependencies** | What `/bionic:setup` offers to install: git, node, pnpm, gh, jq, rg, uv, docker, yq, aws, gcloud, `@playwright/cli`, `@pencil.dev/cli`, notebooklm, motion, the context7 and chrome-devtools MCP servers, the Playwright browser cache, and ccstatusline. The dependency table in [`payload/scripts/lib/deps.sh`](payload/scripts/lib/deps.sh) is the single place a version constraint is declared, and `/bionic:doctor` reports every row against it |

**Why Playwright CLI and not the Playwright MCP server:** the MCP server injects full page snapshots into the context window on every turn; the CLI keeps browser state on disk and returns compact snapshots and file paths. Bionic still installs the Chrome DevTools MCP for the inspection side — traces, Lighthouse, throttling — because that fires once per investigation rather than once per turn. Driving and inspection are separate lanes, and the [`browser-verify`](skills/browser-verify/SKILL.md) skill routes between them.

## What Blocks You

Five walls are registered by the plugin itself and are live in every session (six registrations — the plan/spec guard covers Write and Edit both):

| Hook | Event | Blocks? | What it does |
|---|---|---|---|
| `protect-main.sh` | Bash | **yes** | Rejects pushes to main/master and force-pushes |
| `protect-database.sh` | Bash | **yes** | Rejects destructive SQL — DROP, TRUNCATE, DELETE without WHERE |
| `canonical-sdlc-governing-skill.sh` | Write, Edit | **yes** | Rejects plan/spec/ADR files with malformed frontmatter |
| `dispatch-preflight.sh` | Agent | **yes** | Rejects subagent briefs that skip the dispatch contract |
| `landing-gate.sh` | SubagentStop | **yes** | Refuses a subagent's completion when its declared deliverable is not there |

A further fleet arms itself when the canonical-sdlc skill is invoked and stands down with it: `canonical-sdlc-evidence-gate.sh` blocks a commit that carries no evidence for the plan's current step, `canonical-sdlc-governing-skill.sh` guards the artifacts themselves on both channels, and alongside them ride the farm-out reminder, the execution recorder, the stop guard, and the context-spend meter. Registrations are the skill's own frontmatter, so nothing enforces a lifecycle you are not running.

**If a command gets denied and you meant it:** `farm-out-reminder.sh` blocks test suites, builds, installs, and long `&&` chains on the main thread to protect your context budget. Prefix with `FARM_OUT_ALLOW=1` to override — it must be in command position, so `FARM_OUT_ALLOW=1 npm test`, not `cd foo && FARM_OUT_ALLOW=1 npm test`.

Every hook has a paired `*.test.sh` suite under [`tests/`](tests/). Run all of them with `bash tests/run.sh`.

## Safety

Hooks are the hard layer — they intercept tool calls and block what you'd regret. Bionic's operating philosophy is the judgment layer, teaching Claude when to act, when to pause, and when to escalate, plus the operations that always require your approval: secrets and credentials, anything touching billing, and production infrastructure.

`/bionic:setup` offers a permission profile scoped to bionic's own scripts and hooks. It goes into your `settings.json` inside a marker block; nothing outside that block is read or changed, and `/bionic:remove` takes it back out. Every mutation any bionic script makes is gated on an explicit `y` — there is no assume-yes flag, so a closed stdin declines everything.

## Requirements

**macOS and Linux:** the Claude Code CLI, and Node if you do not have it. `/bionic:setup` installs the rest, one consented item at a time, and reports anything it could not do as a named action rather than stopping.

**Windows (WSL2):**

1. Open PowerShell as Administrator: `wsl --install`
2. Restart your computer
3. Open the Ubuntu terminal from the Start menu
4. Install the prerequisites, then the plugin:
   ```bash
   git clone https://github.com/chrisalehman/bionic.git
   cd bionic
   ./wsl-setup.sh
   ```

## Where Things Live

| What | Where |
|---|---|
| The plugin payload — what the CLI mounts | [`payload/`](payload/) |
| Skills | [`skills/`](skills/) — each has its own `SKILL.md` |
| Hooks | [`hooks/`](hooks/) — each has a paired `.test.sh` under [`tests/`](tests/) |
| Subagent roles | [`agents/`](agents/), rendered from [`agents-src/`](agents-src/) |
| Setup, doctor and remove | [`payload/scripts/`](payload/scripts/) |
| Dependency table and version constraints | [`payload/scripts/lib/deps.sh`](payload/scripts/lib/deps.sh) |
| Operating philosophy *(a repo document; the plugin does not install it)* | [`claude-global.md`](claude-global.md) |
| Tests | [`tests/run.sh`](tests/run.sh) |

## License

MIT — see [`LICENSE`](LICENSE).
