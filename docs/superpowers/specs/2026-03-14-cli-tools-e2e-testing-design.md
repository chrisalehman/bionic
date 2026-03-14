# CLI Tool Installation & E2E Testing Design

## Overview

Extend `claude-setup` to (1) install core CLI development tools via Homebrew and (2) enable end-to-end testing in Claude sessions via Playwright with headless-by-default, headed-on-demand operation.

## Goals

- Bootstrap a complete dev environment with a single script run
- Enable Claude sessions to run and interact with E2E browser tests
- Maintain idempotency — safe to run multiple times
- Keep configuration centralized in `claude-config.txt`

## Non-Goals

- Per-project test scaffolding or templates (projects use `npm init playwright`)
- Docker installation (Playwright runs browsers natively)
- Python version management (uv handles Python tooling)
- Uninstalling Homebrew-managed tools on reset (too risky for shared system deps)

---

## 1. CLI Tool Installation

### Tools

| Tool     | Binary   | Install method       | Purpose                |
|----------|----------|----------------------|------------------------|
| Homebrew | `brew`   | Official install script | Package manager (prerequisite) |
| git      | `git`    | `brew install git`   | Version control        |
| node     | `node`   | `brew install node`  | JavaScript runtime     |
| pnpm     | `pnpm`   | `brew install pnpm`  | Node package manager   |
| gh       | `gh`     | `brew install gh`    | GitHub CLI             |
| jq       | `jq`     | `brew install jq`    | JSON processor         |
| ripgrep  | `rg`     | `brew install ripgrep` | Fast text search     |
| uv       | `uv`     | `brew install uv`    | Python package manager (already handled) |

### Config format

New line type in `claude-config.txt`:

```
brew-dep     | git
brew-dep     | node
brew-dep     | pnpm
brew-dep     | gh
brew-dep     | jq
brew-dep     | rg            | ripgrep
brew-dep     | uv
```

Format: `brew-dep | binary_name | package_name`. When binary and package names match, the third field is omitted.

**Migration note:** The existing hardcoded `ensure_cmd uv` call in `claude-bootstrap.sh` (line ~129) must be removed and replaced by the generic `brew-dep` loop. The `uv` entry in config replaces it.

### Install logic

1. Check for Homebrew; install via official script if missing
2. Read `brew-dep` lines from `claude-config.txt`
3. For each: extract binary name (field 2) and package name (field 3, defaults to binary name). Check if binary exists (`command -v $binary`), install package if missing, skip if present
4. Print summary of what was installed vs. already present

### Reset behavior

`claude-reset.sh` will **not** uninstall Homebrew packages. These are system-level tools that other software may depend on. A message will note that brew dependencies were left in place.

---

## 2. Playwright & E2E Testing

### Components

**a) Playwright test runner (global npm package)**
- Install: `npm install -g @playwright/test`
- Provides `npx playwright test` command in any project
- Headless by default; pass `--headed` flag for UI-visible runs

**b) Playwright browser binaries**
- Install: `npx playwright install chromium`
- Downloads Chromium to Playwright's managed cache (`~/Library/Caches/ms-playwright/`)
- Only Chromium — Firefox/WebKit can be added later if needed

**c) Playwright MCP server**
- Package: `@playwright/mcp`
- Configured in Claude's global settings (`~/.claude/settings.json`) under the `mcpServers` key
- Gives Claude live browser control: navigation, clicking, screenshots, console logs
- Enables interactive debugging and visual verification during Claude sessions

**Note:** The correct config location is `~/.claude/settings.json` (not a standalone `mcp_servers.json`). MCP servers are configured under the `mcpServers` key in this file.

### Config format

New line types in `claude-config.txt`:

```
npm-global   | @playwright/test
mcp-server   | playwright           | @playwright/mcp
```

### Install logic

1. Verify `npm` is available (`command -v npm`) — prerequisite from CLI tools section
2. Read `npm-global` lines; install each via `npm install -g` if not present (check with `npm list -g --depth=0`)
3. Run `npx playwright install chromium` for browser binaries (Playwright handles idempotency internally)
4. Read `mcp-server` lines; configure each in `~/.claude/settings.json` under `mcpServers`
   - Create file with `{ "mcpServers": {} }` if it doesn't exist
   - Merge entry if file exists using `jq` (don't overwrite other MCP servers)
   - Entry format: `{ "mcpServers": { "playwright": { "command": "npx", "args": ["@playwright/mcp"] } } }`

### Reset behavior (in reverse-dependency order)

1. Remove the MCP server entry from `~/.claude/settings.json` `mcpServers` key (depends on npm package)
2. Uninstall the global npm package (`npm uninstall -g @playwright/test`)
3. Leave browser binaries in cache (harmless, managed by Playwright)

---

## 3. Changes to Existing Files

### `claude-config.txt`

Add new entries:

```
brew-dep     | git
brew-dep     | node
brew-dep     | pnpm
brew-dep     | gh
brew-dep     | jq
brew-dep     | rg            | ripgrep
brew-dep     | uv
npm-global   | @playwright/test
mcp-server   | playwright           | @playwright/mcp
```

Update the format header comment to document all line types including `brew-dep`, `npm-global`, and `mcp-server`.

Remove the hardcoded `ensure_cmd uv` call — `uv` is now handled by the `brew-dep` loop.

### `claude-bootstrap.sh`

New sections added in order:

1. **Homebrew check/install** (before any `brew install` calls)
2. **Brew dependencies** (parse `brew-dep` lines, install missing)
3. **npm globals** (parse `npm-global` lines, install missing)
4. **Playwright browsers** (install chromium after npm globals)
5. **MCP server config** (parse `mcp-server` lines, configure in Claude settings)

Existing hardcoded `ensure_cmd uv` call removed — replaced by the generic `brew-dep` handler.

**Note:** The excalidraw-diagram skill's `uv run playwright install chromium` (existing lines ~174-178) is a separate, Python/uv-managed Playwright installation local to that skill's virtualenv. It is independent from the global Node.js Playwright installed here and must not be removed.

### `claude-reset.sh`

New sections:

1. **MCP server removal** (remove entries from `~/.claude/settings.json`)
2. **npm global removal** (uninstall global packages)
3. **Brew dependency notice** (print message that brew packages were left in place)

### `README.md`

Update to document:
- New CLI tools being installed
- Playwright E2E testing capability
- How to use headed mode
- MCP server for interactive browser control

---

## 4. Execution Order (Full Bootstrap)

1. Check/install Homebrew
2. Install brew dependencies (git, node, pnpm, gh, jq, ripgrep, uv)
3. Install npm global packages (@playwright/test)
4. Install Playwright browser binaries (chromium)
5. Install marketplaces (existing)
6. Install plugins (existing)
7. Install global memory (existing)
8. Install shell alias (existing)
9. Install custom skills (existing)
10. Configure MCP servers (playwright)
11. Verification summary

---

## 5. Testing the Changes

Manual verification checklist after running bootstrap:

- [ ] `brew --version` works
- [ ] `git --version`, `node --version`, `pnpm --version`, `gh --version`, `jq --version`, `rg --version` all work
- [ ] `npx playwright --version` works
- [ ] `npx playwright test --headed` launches a visible browser (in a project with tests)
- [ ] `~/.claude/settings.json` contains the playwright entry
- [ ] Running bootstrap a second time makes no changes (idempotent)
- [ ] Running reset removes MCP config and npm globals but leaves brew packages
