# CLI Tool Installation & E2E Testing Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend claude-setup to install core CLI dev tools via Homebrew and enable Playwright-based E2E testing in Claude sessions.

**Architecture:** Config-driven (`claude-config.txt`) with new line types (`brew-dep`, `npm-global`, `mcp-server`). Bootstrap reads config and installs missing tools idempotently. Reset reverses npm/MCP changes but leaves brew packages.

**Tech Stack:** Bash, Homebrew, npm, Playwright, jq (for JSON manipulation of settings.json)

**Spec:** `docs/superpowers/specs/2026-03-14-cli-tools-e2e-testing-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `claude-config.txt` | Modify | Add `brew-dep`, `npm-global`, `mcp-server` entries and update header |
| `claude-bootstrap.sh` | Modify | Add Homebrew check, brew-dep loop, npm-global loop, Playwright browser install, MCP config; migrate hardcoded `uv` |
| `claude-reset.sh` | Modify | Add MCP server removal, npm-global removal, brew-dep notice |
| `README.md` | Modify | Document new tools, Playwright, MCP server |
| `.claude/settings.local.json` | Modify | Allow new commands (npm, npx, jq, brew) |

---

## Chunk 1: Config and Bootstrap — Brew Dependencies

### Task 1: Update `claude-config.txt` with new entry types and brew-dep entries

**Files:**
- Modify: `claude-config.txt:1-29`

- [ ] **Step 1: Update the format header comment**

Add the new line types to the header block at lines 5-9:

```
# Format: type|name|source
#   marketplace   |  name
#   plugin        |  name  |  source
#   github-skill  |  name  |  owner/repo
#   global-memory |  filename
#   brew-dep      |  binary              (package = binary)
#   brew-dep      |  binary  |  package  (when binary ≠ package)
#   npm-global    |  package
#   mcp-server    |  name   |  package
```

- [ ] **Step 2: Add brew-dep entries after the header, before marketplaces**

Insert after line 9 (end of header), before the marketplace lines:

```
brew-dep     | git
brew-dep     | node
brew-dep     | pnpm
brew-dep     | gh
brew-dep     | jq
brew-dep     | rg            | ripgrep
brew-dep     | uv
```

- [ ] **Step 3: Add npm-global and mcp-server entries at the end of the file**

Append after the `github-skill` line:

```
npm-global   | @playwright/test
mcp-server   | playwright    | @playwright/mcp
```

- [ ] **Step 4: Commit**

```bash
git add claude-config.txt
git commit -m "config: add brew-dep, npm-global, and mcp-server entries"
```

---

### Task 2: Add Homebrew check and brew-dep install loop to bootstrap

**Files:**
- Modify: `claude-bootstrap.sh:13-20` (prerequisite checks)
- Modify: `claude-bootstrap.sh:127-131` (dependencies section)

- [ ] **Step 1: Update file header comment (line 6)**

Change line 6 from:
```bash
# Requires: claude CLI, git (macOS + Homebrew)
```
to:
```bash
# Requires: claude CLI (macOS + Homebrew)
```

- [ ] **Step 2: Replace the prerequisite checks section (lines 13-23)**

Replace the current prerequisite checks with a version that only requires `claude` and checks/installs Homebrew:

```bash
# ─── Prerequisite checks ────────────────────────────────────────────────────

check_cmd() {
  if ! command -v "$1" &>/dev/null; then
    echo "ERROR: '$1' not found. $2" >&2
    exit 1
  fi
}

check_cmd claude  "Install with: brew install claude-code"

# ─── Homebrew ────────────────────────────────────────────────────────────────

if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
```

Note: The old `check_cmd git` is removed because git becomes a `brew-dep` entry.

- [ ] **Step 3: Update `ensure_cmd` to print status for already-present items**

Replace the current `ensure_cmd` function (in the `# ─── Helpers` section) with:

```bash
ensure_cmd() {
  local cmd="$1" pkg="${2:-$1}"
  echo -n "  ${cmd}... "
  if command -v "$cmd" &>/dev/null; then
    echo "✓ (already installed)"
    return 0
  fi
  brew install "$pkg" --quiet 2>/dev/null
  echo "✓"
}
```

This ensures both installed and newly-installed items print a status line, matching the output style of npm-global and mcp-server handlers.

- [ ] **Step 4: Replace the `# ─── Dependencies` section (lines 127-131)**

Replace the hardcoded `ensure_cmd uv` with a generic brew-dep loop:

```bash
# ─── Brew Dependencies ──────────────────────────────────────────────────────

echo "Brew dependencies:"
read_config "brew-dep" do_install_brew_dep
echo ""
```

- [ ] **Step 5: Add the `do_install_brew_dep` helper function**

Add after the `ensure_cmd` function in the `# ─── Helpers` section:

```bash
do_install_brew_dep() {
  local binary="$1" pkg="${2:-$1}"
  ensure_cmd "$binary" "$pkg"
}
```

- [ ] **Step 6: Test idempotency**

Run bootstrap twice. Second run should show all brew deps as "already installed" (no reinstalls):

```bash
./claude-bootstrap.sh
./claude-bootstrap.sh
```

- [ ] **Step 7: Commit**

```bash
git add claude-bootstrap.sh
git commit -m "feat: add Homebrew check and config-driven brew dependency installation"
```

---

## Chunk 2: Bootstrap — npm Globals, Playwright Browsers, MCP Server

### Task 3: Add npm-global install loop and Playwright browser install

**Files:**
- Modify: `claude-bootstrap.sh` (helpers section: add `do_install_npm_global` after `do_install_brew_dep`; add npm globals + Playwright browsers sections after `# ─── Brew Dependencies` section, before `# ─── Marketplaces`)

- [ ] **Step 1: Add the `do_install_npm_global` helper function**

Add after `do_install_brew_dep`:

```bash
do_install_npm_global() {
  local pkg="$1"
  echo -n "  ${pkg}... "
  if npm list -g --depth=0 "$pkg" &>/dev/null; then
    echo "✓ (already installed)"
  else
    npm install -g "$pkg" --silent 2>/dev/null
    echo "✓"
  fi
}
```

- [ ] **Step 2: Add the npm globals section and Playwright browser install**

Add after the brew dependencies section, before marketplaces:

```bash
# ─── npm Globals ─────────────────────────────────────────────────────────────

echo "npm globals:"
if ! command -v npm &>/dev/null; then
  echo "  ERROR: npm not found — install node first" >&2
  exit 1
fi
read_config "npm-global" do_install_npm_global
echo ""

# ─── Playwright Browsers ────────────────────────────────────────────────────

echo -n "Playwright browsers (chromium)... "
npx playwright install chromium --quiet 2>/dev/null || npx playwright install chromium 2>/dev/null
echo "✓"
echo ""
```

- [ ] **Step 3: Test**

Run bootstrap — should install `@playwright/test` globally and download Chromium:

```bash
./claude-bootstrap.sh
```

Verify:
```bash
npx playwright --version
```

- [ ] **Step 4: Commit**

```bash
git add claude-bootstrap.sh
git commit -m "feat: add npm global package installation and Playwright browser setup"
```

---

### Task 4: Add MCP server configuration to bootstrap

**Note:** `jq` must be installed (via brew-dep in Task 2) before this task runs.

**Files:**
- Modify: `claude-bootstrap.sh` (helpers section: add `do_configure_mcp_server`; add MCP servers section after `# ─── Skill Setup` section, before `# ─── Verification`)

- [ ] **Step 1: Add the `do_configure_mcp_server` helper function**

Add after the other helper functions:

```bash
do_configure_mcp_server() {
  local name="$1" pkg="$2"
  local settings=~/.claude/settings.json

  echo -n "  ${name} (${pkg})... "

  # Create settings file if it doesn't exist
  if [ ! -f "$settings" ]; then
    echo '{}' > "$settings"
  fi

  # Check if MCP server already configured
  if jq -e ".mcpServers.\"${name}\"" "$settings" &>/dev/null; then
    echo "✓ (already configured)"
    return 0
  fi

  # Merge new MCP server entry
  local tmp="${settings}.tmp"
  jq --arg name "$name" --arg pkg "$pkg" '
    .mcpServers //= {} |
    .mcpServers[$name] = { "command": "npx", "args": [$pkg] }
  ' "$settings" > "$tmp" && mv "$tmp" "$settings"

  echo "✓"
}
```

- [ ] **Step 2: Add the MCP servers section**

Add after the `# ─── Skill Setup` section, before `# ─── Verification`:

```bash
# ─── MCP Servers ─────────────────────────────────────────────────────────────

echo "MCP servers:"
read_config "mcp-server" do_configure_mcp_server
echo ""
```

- [ ] **Step 3: Test**

Run bootstrap, then verify the settings file:

```bash
./claude-bootstrap.sh
cat ~/.claude/settings.json | jq '.mcpServers'
```

Expected output:
```json
{
  "playwright": {
    "command": "npx",
    "args": ["@playwright/mcp"]
  }
}
```

- [ ] **Step 4: Test idempotency**

Run bootstrap again — should show "already configured":

```bash
./claude-bootstrap.sh
```

- [ ] **Step 5: Commit**

```bash
git add claude-bootstrap.sh
git commit -m "feat: add MCP server configuration to bootstrap"
```

---

## Chunk 3: Bootstrap Verification Updates

### Task 5: Update bootstrap verification to cover new sections

**Files:**
- Modify: `claude-bootstrap.sh` (`# ─── Verification` section — add new subsections and their helpers)

- [ ] **Step 1: Add brew dependencies verification**

Add at the start of the Verification section (after `echo "Verification:"`):

```bash
echo ""
echo "  Brew dependencies:"
read_config "brew-dep" verify_brew_dep
```

And add the helper:

```bash
verify_brew_dep() {
  local binary="$1"
  if command -v "$binary" &>/dev/null; then
    echo "    ${binary} ✓"
  else
    echo "    ${binary} — not found"
  fi
}
```

- [ ] **Step 2: Add npm globals verification**

```bash
echo ""
echo "  npm globals:"
read_config "npm-global" verify_npm_global
```

And add the helper:

```bash
verify_npm_global() {
  local pkg="$1"
  if npm list -g --depth=0 "$pkg" &>/dev/null; then
    echo "    ${pkg} ✓"
  else
    echo "    ${pkg} — not found"
  fi
}
```

- [ ] **Step 3: Add MCP servers verification**

```bash
echo ""
echo "  MCP servers:"
read_config "mcp-server" verify_mcp_server
```

And add the helper:

```bash
verify_mcp_server() {
  local name="$1"
  local settings=~/.claude/settings.json
  if [ -f "$settings" ] && jq -e ".mcpServers.\"${name}\"" "$settings" &>/dev/null; then
    echo "    ${name} ✓"
  else
    echo "    ${name} — not configured"
  fi
}
```

- [ ] **Step 4: Test full bootstrap**

```bash
./claude-bootstrap.sh
```

Verify all new sections appear in the output with checkmarks.

- [ ] **Step 5: Commit**

```bash
git add claude-bootstrap.sh
git commit -m "feat: add verification for brew deps, npm globals, and MCP servers"
```

---

## Chunk 4: Reset Script

### Task 6: Add MCP server removal to reset script

**Files:**
- Modify: `claude-reset.sh` (helpers section: add `do_remove_mcp_server`; add MCP servers removal at the top of the reset execution flow, before the existing `# ─── Custom Skills` section)

- [ ] **Step 1: Add `do_remove_mcp_server` helper**

Add after the existing helper functions:

```bash
do_remove_mcp_server() {
  local name="$1" pkg="$2"
  local settings=~/.claude/settings.json

  if ! confirm "MCP server: ${name}"; then
    echo "  ${name} — skipped"
    return 0
  fi

  echo -n "  ${name}... "

  if [ ! -f "$settings" ] || ! jq -e ".mcpServers.\"${name}\"" "$settings" &>/dev/null; then
    echo "✓ (already removed)"
    return 0
  fi

  local tmp="${settings}.tmp"
  jq --arg name "$name" 'del(.mcpServers[$name])' "$settings" > "$tmp" && mv "$tmp" "$settings"
  echo "✓"
}
```

- [ ] **Step 2: Add MCP servers removal section**

Add at the top of the reset execution flow, before the existing `# ─── Custom Skills` section:

```bash
# ─── MCP Servers ───────────────────────────────────────────────────────────

echo "MCP servers:"
read_config "mcp-server" do_remove_mcp_server
echo ""
```

- [ ] **Step 3: Commit**

```bash
git add claude-reset.sh
git commit -m "feat: add MCP server removal to reset script"
```

---

### Task 7: Add npm-global removal and brew-dep notice to reset script

**Files:**
- Modify: `claude-reset.sh` (add after MCP server removal, before custom skills)

- [ ] **Step 1: Add `do_remove_npm_global` helper**

```bash
do_remove_npm_global() {
  local pkg="$1"
  if ! confirm "npm global: ${pkg}"; then
    echo "  ${pkg} — skipped"
    return 0
  fi
  echo -n "  ${pkg}... "
  if npm list -g --depth=0 "$pkg" &>/dev/null; then
    npm uninstall -g "$pkg" --silent 2>/dev/null
    echo "✓"
  else
    echo "✓ (already removed)"
  fi
}
```

- [ ] **Step 2: Add npm globals removal section**

Add after MCP servers removal:

```bash
# ─── npm Globals ───────────────────────────────────────────────────────────

echo "npm globals:"
read_config "npm-global" do_remove_npm_global
echo ""
```

- [ ] **Step 3: Add brew dependencies notice**

Add after npm globals removal:

```bash
# ─── Brew Dependencies ────────────────────────────────────────────────────

echo "Brew dependencies:"
echo "  (not removed — system-level tools may be used by other software)"
echo ""
```

- [ ] **Step 4: Update reset verification to include new sections**

Add to the Verification section:

```bash
echo ""
echo "  npm globals:"
npm_global_found=false
read_config "npm-global" verify_npm_global_removed
if ! $npm_global_found; then
  echo "    (none installed) ✓"
fi

echo ""
echo "  MCP servers:"
mcp_found=false
read_config "mcp-server" verify_mcp_removed
if ! $mcp_found; then
  echo "    (all removed) ✓"
fi
```

With helpers:

```bash
verify_npm_global_removed() {
  local pkg="$1"
  if npm list -g --depth=0 "$pkg" &>/dev/null; then
    npm_global_found=true
    echo "    ${pkg} — still installed"
  fi
}

verify_mcp_removed() {
  local name="$1"
  local settings=~/.claude/settings.json
  if [ -f "$settings" ] && jq -e ".mcpServers.\"${name}\"" "$settings" &>/dev/null; then
    mcp_found=true
    echo "    ${name} — still configured"
  fi
}
```

- [ ] **Step 5: Test reset**

```bash
./claude-reset.sh --all
```

Verify MCP entry is removed from `~/.claude/settings.json` and npm global is uninstalled.

- [ ] **Step 6: Commit**

```bash
git add claude-reset.sh
git commit -m "feat: add npm global removal and brew dependency notice to reset"
```

---

## Chunk 5: README and Permissions

### Task 8: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the Prerequisites section**

Replace the prerequisites section with:

```markdown
## Prerequisites

- macOS (scripts assume macOS + Homebrew)
- Claude Code CLI (`brew install claude-code`)

The bootstrap script automatically installs Homebrew (if missing) and all other dependencies.
```

- [ ] **Step 2: Add a CLI Tools section after "What's included"**

Add before the Plugins table:

```markdown
### CLI Tools (installed via Homebrew)

| Tool | Purpose |
|------|---------|
| git | Version control |
| node | JavaScript runtime |
| pnpm | Node package manager |
| gh | GitHub CLI |
| jq | JSON processor |
| ripgrep (`rg`) | Fast text search |
| uv | Python package manager |
```

- [ ] **Step 3: Add an E2E Testing section**

Add after the Custom Skills section:

```markdown
### E2E Testing (Playwright)

The bootstrap installs Playwright for end-to-end browser testing:

- **Test runner:** `@playwright/test` (global npm package) — run tests in any project with `npx playwright test`
- **Browser:** Chromium (downloaded automatically)
- **MCP server:** `@playwright/mcp` — gives Claude live browser control for interactive debugging and visual verification

**Headless by default.** To see the browser UI during tests:

```bash
npx playwright test --headed
```

To initialize Playwright in a new project:

```bash
npm init playwright@latest
```
```

- [ ] **Step 4: Update the config format section**

Update the "Adding new stuff" section to show all line types:

```markdown
## Adding new stuff

Everything is defined in `claude-config.txt` — one place, no sync issues:

```
brew-dep      | binary              (package = binary)
brew-dep      | binary  | package   (when binary ≠ package name)
marketplace   | name
plugin        | name    | source
global-memory | filename
github-skill  | name    | owner/repo
npm-global    | package
mcp-server    | name    | package
```
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: update README with CLI tools, Playwright, and MCP server info"
```

---

### Task 9: Update `.claude/settings.local.json` permissions

**Files:**
- Modify: `.claude/settings.local.json`

- [ ] **Step 1: Add new commands to the allow list**

Add these to the `allow` array:

```json
"Bash(npm install -g *)",
"Bash(npm list -g *)",
"Bash(npm uninstall -g *)",
"Bash(npx playwright *)",
"Bash(jq *)",
"Bash(brew install *)",
"Bash(curl -fsSL *)"
```

- [ ] **Step 2: Commit**

```bash
git add .claude/settings.local.json
git commit -m "chore: add npm, npx, jq, and brew to permission allowlist"
```

---

## Chunk 6: End-to-End Validation

### Task 10: Full integration test

- [ ] **Step 1: Run a clean bootstrap**

```bash
./claude-bootstrap.sh
```

Verify all sections produce output with checkmarks.

- [ ] **Step 2: Verify each tool**

```bash
brew --version
git --version
node --version
pnpm --version
gh --version
jq --version
rg --version
uv --version
npx playwright --version
```

- [ ] **Step 3: Verify MCP config**

```bash
jq '.mcpServers' ~/.claude/settings.json
```

Expected: `playwright` entry with `npx` command and `@playwright/mcp` arg.

- [ ] **Step 4: Test idempotency — run bootstrap again**

```bash
./claude-bootstrap.sh
```

All items should show "already installed" / "already configured".

- [ ] **Step 5: Test reset**

```bash
./claude-reset.sh --all
```

Verify: MCP server removed, npm global removed, brew deps left with notice.

- [ ] **Step 6: Test re-bootstrap after reset**

```bash
./claude-bootstrap.sh
```

Everything reinstalls cleanly.

- [ ] **Step 7: Final commit (if any fixes needed)**

```bash
git add -A
git commit -m "fix: integration test fixes"
```
