# claude-setup

Personal Claude Code bootstrap. One script, one run, fully configured environment. Idempotent — safe to re-run anytime.

## Usage

```bash
git clone git@github.com:chrisalehman/claude-setup.git
cd claude-setup
./claude-bootstrap.sh        # install everything
./claude-reset.sh            # prompt to remove all, or item-by-item
./claude-reset.sh --all      # remove everything without prompting
```

## What's included

### Plugins

| Plugin | Source | Purpose |
|--------|--------|---------|
| superpowers | claude-plugins-official | SDLC workflow: brainstorm → plan → TDD → subagent execution → review |
| frontend-design | claude-plugins-official | Production-grade UI design that avoids generic AI aesthetics |
| document-skills | anthropic-agent-skills | docx, pdf, pptx, xlsx creation and manipulation |
| example-skills | anthropic-agent-skills | skill-creator, webapp-testing (Playwright), mcp-builder |

### Custom Skills (installed to ~/.claude/skills/)

| Skill | Source | Purpose |
|-------|--------|---------|
| excalidraw-diagram | [coleam00/excalidraw-diagram-skill](https://github.com/coleam00/excalidraw-diagram-skill) | Excalidraw diagram generation with PNG rendering via Playwright |

Skills are fetched from GitHub at bootstrap time, not stored in this repo.

## Repo structure

```
claude-setup/
├── claude-config.txt        # Shared config (plugins, skills, marketplaces)
├── claude-bootstrap.sh      # Install everything (idempotent)
├── claude-reset.sh          # Remove everything (interactive or --all)
└── README.md
```

## Prerequisites

- macOS (scripts and install instructions assume macOS + Homebrew)
- Claude Code CLI (`brew install claude-code`)
- Node.js (`brew install node`)
- Git (included with Xcode command line tools)
- Active Claude Max subscription

`uv` (Python package manager) is auto-installed by the bootstrap script if missing.

## Updating

```bash
# Update marketplace plugins
claude plugin update --all

# Update all skills and dependencies (re-run the script)
./claude-bootstrap.sh
```

## Adding new stuff

Everything is defined in `claude-config.txt` — one place, no sync issues:

- **New plugin:** Add a `plugin | name | source` line
- **New GitHub skill:** Add a `github-skill | name | owner/repo` line
- **New marketplace:** Add a `marketplace | name` line
