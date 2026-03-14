# claude-setup

Personal Claude Code bootstrap. Two scripts, one config, fully configured environment. Idempotent — safe to re-run anytime.

## Usage

```bash
git clone git@github.com:chrisalehman/claude-setup.git
cd claude-setup
./claude-bootstrap.sh        # install everything
./claude-reset.sh            # prompts "Remove all?" first, then item-by-item if declined
./claude-reset.sh --all      # remove everything without prompting
```

## What's included

### Plugins (from official marketplaces)

| Plugin | Source | Purpose |
|--------|--------|---------|
| superpowers | claude-plugins-official | SDLC workflow: brainstorm → plan → TDD → subagent execution → review |
| frontend-design | claude-plugins-official | Production-grade UI design that avoids generic AI aesthetics |
| document-skills | anthropic-agent-skills | docx, pdf, pptx, xlsx creation and manipulation |
| example-skills | anthropic-agent-skills | skill-creator, webapp-testing (Playwright), mcp-builder |

### Subagent Plugins (from VoltAgent marketplace)

| Plugin | Purpose |
|--------|---------|
| voltagent-core-dev | API design, backend, frontend, fullstack, mobile, WebSocket |
| voltagent-lang | Language specialists: TypeScript, Python, React, Next.js, SQL, Go, Rust, Java + 18 more |
| voltagent-infra | DevOps, cloud, deployment: Kubernetes, Terraform, Docker, AWS/Azure/GCP, SRE |
| voltagent-qa-sec | Testing, security, code quality: code review, debugging, penetration testing, a11y |
| voltagent-data-ai | Data/ML/AI: Postgres, prompt engineering, LLM architecture, data pipelines, MLOps |
| voltagent-dev-exp | Developer productivity: refactoring, documentation, CLI tools, Git workflows, MCP |
| voltagent-meta | Multi-agent orchestration, workflow automation, task distribution |

### Global Memory (installed to ~/.claude/CLAUDE.md)

Curated behavioral rules applied to every Claude Code session across all projects.

| Rule | Purpose |
|------|---------|
| Code Review Before Push | Always invoke code review before `git push` |
| Don't Start Duplicate Dev Servers | Check for running servers before starting another |
| Don't Delete Generated Outputs | Never delete PDFs, diagrams, images without confirmation |
| Clean Working Directory | Scripts must not leave intermediary files |
| Reviews Must Check Conventions | Code reviews must check file placement, not just correctness |

Edit `claude-global.md` to add or remove rules. To disable entirely, comment out or remove the `global-memory` line in `claude-config.txt`.

The bootstrap installs these rules into a managed section of `~/.claude/CLAUDE.md` (between `<!-- claude-setup:start -->` and `<!-- claude-setup:end -->` markers). Any personal content you add outside these markers is preserved across bootstrap runs and resets.

### Custom Skills (fetched from GitHub, installed to ~/.claude/skills/)

| Skill | Source | Purpose |
|-------|--------|---------|
| excalidraw-diagram | [coleam00/excalidraw-diagram-skill](https://github.com/coleam00/excalidraw-diagram-skill) | Excalidraw diagram generation with PNG rendering via Playwright |

Custom skills are fetched from GitHub at bootstrap time, not stored in this repo.

## Repo structure

```
claude-setup/
├── .gitignore
├── claude-config.txt        # Shared config (plugins, skills, marketplaces)
├── claude-global.md         # Global behavioral rules (installed to ~/.claude/CLAUDE.md)
├── claude-bootstrap.sh      # Install everything (idempotent)
├── claude-reset.sh          # Remove everything (interactive or --all)
└── README.md
```

## Prerequisites

- macOS (scripts and install instructions assume macOS + Homebrew)
- Claude Code CLI (`brew install claude-code`)
- Git (included with Xcode command line tools)

`uv` (Python package manager) is auto-installed by the bootstrap script if missing.

## Updating

Re-running the bootstrap script updates all custom skills to their latest versions from GitHub:

```bash
./claude-bootstrap.sh
```

## Adding new stuff

Everything is defined in `claude-config.txt` — one place, no sync issues:

```
marketplace   | name
plugin        | name       | source
global-memory | filename
github-skill  | name       | owner/repo
```
