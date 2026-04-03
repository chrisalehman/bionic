#!/usr/bin/env bash
#
# wsl-setup.sh
# One-time setup for WSL2 (Ubuntu). Installs prerequisites so that
# claude-bootstrap.sh can run. Idempotent — safe to run multiple times.
#
# Prerequisites: WSL2 with Ubuntu installed (wsl --install from PowerShell)
#
set -euo pipefail

# ─── Validate WSL Environment ──────────────────────────────────────────────

if ! grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
  echo "ERROR: This script is intended for WSL2 (Windows Subsystem for Linux)." >&2
  echo "       Run 'wsl --install' from PowerShell first, then open Ubuntu." >&2
  exit 1
fi

echo "WSL2 detected ✓"
echo ""

# ─── System Packages ───────────────────────────────────────────────────────

echo "System packages:"
echo -n "  build-essential, procps, curl, file, git... "
sudo apt-get update -qq
sudo apt-get install -y -qq build-essential procps curl file git > /dev/null 2>&1
echo "✓"
echo ""

# ─── Homebrew (Linuxbrew) ─────────────────────────────────────────────────

echo "Homebrew (Linuxbrew):"
if command -v brew &>/dev/null; then
  echo "  ✓ (already installed)"
else
  echo -n "  Installing... "
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  echo "  ✓"
fi

# Ensure brew is on PATH for this session
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Add brew to shell rc file if not already there
SHELL_NAME="$(basename "${SHELL:-/bin/bash}")"
case "$SHELL_NAME" in
  zsh)  RC_FILE=~/.zshrc ;;
  *)    RC_FILE=~/.bashrc ;;
esac

BREW_INIT='eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'
if ! grep -qF "$BREW_INIT" "$RC_FILE" 2>/dev/null; then
  echo "" >> "$RC_FILE"
  echo "# Homebrew (added by bionic wsl-setup)" >> "$RC_FILE"
  echo "$BREW_INIT" >> "$RC_FILE"
  echo "  Added brew to ~/${RC_FILE##*/}"
fi
echo ""

# ─── Claude CLI ────────────────────────────────────────────────────────────

echo "Claude CLI:"
if command -v claude &>/dev/null; then
  echo "  ✓ (already installed)"
else
  echo -n "  Installing via brew... "
  brew install claude-code --quiet
  echo "✓"
fi
echo ""

# ─── Verification ──────────────────────────────────────────────────────────

echo "Verification:"
errors=0

echo -n "  brew... "
if command -v brew &>/dev/null; then
  echo "✓"
else
  echo "FAILED"
  errors=$((errors + 1))
fi

echo -n "  claude... "
if command -v claude &>/dev/null; then
  echo "✓"
else
  echo "FAILED"
  errors=$((errors + 1))
fi

echo -n "  git... "
if command -v git &>/dev/null; then
  echo "✓"
else
  echo "FAILED"
  errors=$((errors + 1))
fi

echo ""
if [ "$errors" -gt 0 ]; then
  echo "Setup completed with ${errors} error(s). Fix the issues above and re-run."
  exit 1
else
  echo "Done ✓"
  echo ""
  echo "Next steps:"
  echo "  cd bionic"
  echo "  ./claude-bootstrap.sh"
fi
