# bionic

Bionic is a Claude Code plugin that brings one engineering lifecycle into every project you
open. It ships a governed SDLC skill, two technique skills, six subagent roles Claude hands
work to, and a small set of walls that refuse commands you would have regretted. It travels
with you rather than with a repository: install it once and the same discipline applies
wherever you open Claude Code.

The centerpiece is `canonical-sdlc`, a ten-step lifecycle where every run declares up front
how hard its evidence has to try to lie, and where no commit lands without evidence for the
step the work is on. Reach for bionic when you run multi-day changes through Claude Code,
dispatch parallel agents, and want the record afterwards to say what was proven rather than
what was claimed. Skip it if your work is mostly single-file edits: the lifecycle spends
interactive turns before it writes any code, and its walls will refuse commands you meant.

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

## Your first session

Installing the plugin is enough to use it. Two walls go live immediately, refusing pushes to
main and destructive database commands, and the skills, commands and agent roles are all
available. Nothing else about your session changes until you ask for it.

`/bionic:help` prints what bionic is and the command roster. `/bionic:doctor` inspects this
machine and reports plugin integrity, which dependencies are present at which versions,
duplicate installs, your shell environment, and what degrades if
something is missing. It changes nothing, and its closing summary is a menu rather than a
to-do list.

The plugin install stands alone. `/bionic:setup` adds what it cannot: the tools bionic's
workflows shell out to, one shell export, and your default permission mode. Setup is idempotent, so
re-running it after six months is the normal way to catch up.

## The skills

### `canonical-sdlc` — the lifecycle

Governs non-trivial engineering. Every run opens by declaring a triple, `intent · rigor ·
scale`, and that triple decides which steps run, how much independent scrutiny the work gets,
and what it leaves behind.

- `intent` is what the deliverable is: `build`, `bugfix`, `refactor`, `tune`, `spike`, or
  `incident-response`.
- `rigor` is how hard the evidence has to try to lie. `tested` means test-driven, red before
  green, closing with a six-axis self-review. `peer-reviewed` adds a separate spec and an
  independent auditor over the evidence. `audited` adds an independent critic over the code.
  Each level contains the one below it.
- `scale` is the unit of decomposition: `task` for several small pieces inside one session,
  `wave` for a change with its own spec, plan and branch, `epic` for work that carves waves
  and runs only the first four steps itself.

The ten steps are configure, scope, design, plan, implement, verify, review, document,
integrate, close-out. Step 0 prints the entire configuration and waits for you to confirm it.
Steps 1 through 3 are conversational: scoping that has to produce an explicit "not doing"
list, a design interview run one question per turn, and a single approval covering the
design, the plan and the verification matrix together. Steps 4 onward run unattended and stop
at anything only you can decide.

Use it when the change is large enough that you would want a spec, a plan, and a record of
what was verified. Chores and documentation stay out — and so do document and research
deliverables like writeups and research reports, which plain plan mode serves better than any
intent here, `spike` included: it ships no code, but its writeup is a timeboxed research
artifact, not a document-production mode.

Start it by naming it with the work:

```
/bionic:canonical-sdlc add rate limiting to the public API
```

Describing work of that size loads it without being asked. `/bionic:canonical-sdlc help`
prints the axis tables and stops, which is the cheap way to read the options first.

Everything it writes lands under `.bionic/docs/` in your project: a spec whose every
acceptance criterion cites where its requirement came from; a plan carrying a matrix that
assigns each criterion an evidence tier, from static checks up to a walk you do with your own
hands; the evidence row by row; decision records for anything that will shape later work; and
a close-out report that gives every finding a disposition instead of a backlog. Two walls
hold it together. A plan, spec or decision record will not write without its frontmatter, and
a commit is refused while the plan carries no evidence for the step it says it is on.

### `browser-verify` — real-browser evidence

Drives a real browser through `playwright-cli` to prove a change behaves. Browser state stays
on disk and the commands return compact snapshots and file paths, so page dumps and
screenshots stay out of the context window unless you read them: roughly 27K tokens for a
task that costs about 114K through an MCP server.

Reach for it when a claim needs a running app behind it rather than a unit test's inference.
It owns the two evidence tiers that need a browser, and it holds a live observation to five
conditions: every origin in the serving path proven fresh, a cold client, the criterion's own
interaction driven with trusted input, the criterion's own value read back semantically, and
a health snapshot around the session so a crash mid-walk cannot pass for a green run.

`/bionic:browser-verify` starts it directly, and the lifecycle routes to it at the verify
step. For what the driver cannot do — Lighthouse, performance traces, heap and CPU profiling,
network throttling — it escalates to the Chrome DevTools MCP server and comes back.

### `map-instrument-narrow` — root cause before fix

Three phases in fixed order: map the architecture, instrument the boundaries, narrow to a
cause the data names. No fix code gets written until the third phase produces one.

Reach for it when a fix has already failed once, when the bug crosses async boundaries or
third-party internals, or when state is right at one point and wrong at another with no
visible path between them. It exists to stop "I'll just try one thing first," which mutates
the state you were about to measure.

`/bionic:map-instrument-narrow` starts it. It produces a written architectural model,
captured measurements, and a named root cause, each one written down before the next begins.

### `excalidraw-diagram` — diagrams that argue

Generates Excalidraw JSON for a picture that makes an argument — fan-out for one-to-many, a
timeline for a sequence, convergence for aggregation — rather than a grid of labelled boxes.
It then renders the diagram to PNG, looks at the render, and fixes what it sees, in a loop
until the picture matches the design.

Reach for it when a layout is genuinely hand-arranged. For a diagram whose structure can be
composed, canonical-sdlc's own format policy prefers SVG, which is simultaneously the source,
the shipped artifact and a test surface.

`/bionic:excalidraw-diagram` starts it. The renderer it drives — a Python environment and a
headless Chromium — is not installed with the plugin: the first render offers each half once,
on consent, and `/bionic:doctor` reports both.

## The commands

- `/bionic:help` — what bionic is, the command roster, where to start.
- `/bionic:setup` — set this machine up, one consented item at a time. Re-runnable.
- `/bionic:doctor` — diagnose this machine. Changes nothing.
- `/bionic:remove` — take the footprint back off, ending with the plugin uninstall.

## What runs in every session

Two walls are live from the moment the plugin is installed, in every project, whether or not
you are running a lifecycle:

| What fires | On | What it does |
|---|---|---|
| Push protection | any `git push` | Refuses a push to main or master, any force push, and any push at all while you are standing on main or master. Those are yours to run. |
| Database protection | `psql`, `mysql`, `sqlite3`, `mongosh` and friends | Refuses `DROP`, `TRUNCATE`, a `DELETE` with no `WHERE`, and `ALTER TABLE … DROP`. |

A second set arms with a lifecycle run and stands down with it, so nothing enforces a process
you are not using:

- A commit is refused while the plan carries no evidence for the step it says it is on.
- A plan, spec or decision record will not write without complete frontmatter, and a
  wave-sized spec will not write without a design behind it.
- Test suites, builds and long command chains are refused on your main session thread, and
  the refusal names which agent should run them instead. Put `FARM_OUT_ALLOW=1` in front of
  the command to override; the override is sanctioned and logged.
- A subagent will not launch until this session has passed its environment check, and its
  brief has to name the artifact it is contracted to produce.
- A subagent's completion is refused when the artifact it declared is not on disk, and
  stopping one requires having looked at it first.

Every wall has a matching test suite. `bash tests/run.sh` runs all of them.

## The agents bionic dispatches

During a lifecycle run your main session stays free. It keeps the shaping decisions and the
approvals, and hands the work to fresh agents. Six roles ship with the plugin, each with its
own standing duties and model:

| Role | Model | What it does |
|---|---|---|
| `researcher` | Opus | Reads code and docs, returns a summary with `file:line` citations. Cannot write. |
| `test-runner` | Haiku | Runs suites and reports every result. Never fixes, never re-runs to green. |
| `implementor` | Sonnet | Executes a slice mechanically. The plan is literal; ambiguity means stop and ask. |
| `senior-implementor` | Opus | Executes slices that need judgment, and root-cause debugging. Logs every call it made. |
| `auditor` | Opus | At the verify gate, tries to falsify the evidence, never the code. Cannot write. |
| `critic` | Opus | At the review gate, tries to falsify the code and the claim it is ready to merge. Cannot write. |

Each of them owes a report where every factual claim carries the command that proves it or
the word `unverified`.

## What setup asks you

Nothing installs without an explicit yes. There is no assume-yes flag, and a closed stdin
declines everything.

- Two plugins bionic depends on, `superpowers` and `agent-skills`. Claude Code installs these
  itself as declared dependencies; setup only checks they are enabled.
- The basics, one question each: `git`, `node`, `pnpm`, `gh`, `jq`, `rg`, `uv`, `docker`,
  `aws`. Bionic ensures these; it does not own them, and `/bionic:remove` never takes them
  away.
- Optional extras, each with a line of what it is and a default of no: a status line, a
  NotebookLM client, the Context7 documentation server, and the Pencil CLI.
- Your shell environment, which is one export written inside a marked block.
- Claude Code's default permission mode, offered as auto only if you say yes. Bionic does not
  exempt itself from whatever you choose: the mode you set governs bionic's own scripts and
  hooks exactly as it governs everything else. (Earlier versions applied a managed allow-list
  that pre-approved them. That is gone; if this machine still carries the block, setup and
  remove each offer once to take it back out.)

Tools that only some work needs — the Playwright CLI and a headless Chromium, the Chrome
DevTools server, the design skill, an animation package — are never asked about here. Each is
offered once, with one question, the first time something actually reaches for it, and
declining degrades that route rather than breaking the session.

## Removing it

`/bionic:remove` takes the footprint back off in one pass, announcing each item before asking
about it, and finishes with the plugin uninstall. Three things it will not remove even if you
say yes: your `.bionic/` trees, because the plans, specs and records in them are your work;
shared binaries like `git` and `docker`, because bionic ensured them and does not own them;
and the pnpm store, which other projects link out of.

The teardown also runs on a machine whose plugin is already gone, and `/bionic:doctor` prints
the one-liner for exactly that state.

## Requirements

macOS and Linux need the Claude Code CLI, plus `git` and `jq`. The walls parse their input
with `jq`, so on a machine without it they pass everything through in silence rather than
erroring. `/bionic:setup` installs the rest one consented item at a time and reports whatever
it could not do as a named action instead of stopping.

On Windows, use WSL2:

1. Open PowerShell as Administrator: `wsl --install`
2. Restart your computer
3. Open the Ubuntu terminal from the Start menu
4. Install the prerequisites, then the plugin:
   ```bash
   git clone https://github.com/chrisalehman/bionic.git
   cd bionic
   ./wsl-setup.sh
   ```

## Source

Everything the plugin ships lives under [`payload/`](payload/): the skills, the agent roles,
the four commands and the scripts behind them, and the dependency table in
[`payload/scripts/lib/deps.sh`](payload/scripts/lib/deps.sh) declaring each tool's class,
what uses it, and its version constraint. Tests run with `bash tests/run.sh`.

## License

MIT — see [`LICENSE`](LICENSE).
