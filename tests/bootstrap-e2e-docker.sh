#!/usr/bin/env bash
#
# bootstrap-e2e-docker.sh
# Fresh-system end-to-end check for claude-bootstrap.sh in a disposable Linux
# container. Lightweight alternative to a macOS VM — the only macOS-only step
# (the `gcloud-cli` Homebrew cask) is covered separately by the live Homebrew
# cask API + tests/installer-behavior.test.sh, so no VM is needed here.
#
# Two modes:
#
#   (default) MOCK — runs the WHOLE claude-bootstrap.sh in a ~30 MB debian-slim
#       with every external tool mocked. Proves the script completes on a fresh
#       OS WITHOUT ABORTING ("Done", 0 install failures) and issues the correct
#       commands (gcloud cask, pnpm motion, agent-skills marketplace+plugin).
#       Seconds. No real installs, no network beyond the base image, no auth.
#
#   --real     REAL — installs the real claude CLI (npm) + pnpm/uv/git and runs
#       the bootstrap for real, validating the OS-agnostic installs incl.
#       agent-skills. Homebrew is mocked (casks are macOS-only; brew formulae
#       aren't the concern). Plugin/marketplace installs need auth:
#         --copy-auth   copy host ~/.claude/.credentials.json + ~/.claude.json
#         --api-key K   export ANTHROPIC_API_KEY=K in the container
#       Without auth, plugin steps are reported as (auth-related) failures.
#
# Requires: docker.
# Usage:
#   bash tests/bootstrap-e2e-docker.sh
#   bash tests/bootstrap-e2e-docker.sh --real --copy-auth
#   bash tests/bootstrap-e2e-docker.sh --real --api-key sk-ant-...
#
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MODE="mock"; AUTH="none"; API_KEY=""; IMAGE=""
die() { echo "ERROR: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --real) MODE="real" ;;
    --copy-auth) AUTH="copy" ;;
    --api-key) AUTH="api"; API_KEY="${2:-}"; shift ;;
    --image) IMAGE="${2:-}"; shift ;;
    -h|--help) sed -n '2,34p' "$0"; exit 0 ;;
    *) die "unknown arg: $1 (try --help)" ;;
  esac
  shift
done

command -v docker >/dev/null || die "docker not found (install Docker Desktop or colima)."
[ "$AUTH" = "api" ] && [ -z "$API_KEY" ] && die "--api-key needs a value"
if [ -z "$IMAGE" ]; then
  [ "$MODE" = "mock" ] && IMAGE="debian:stable-slim" || IMAGE="node:bookworm-slim"
fi

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
MOCKS="$WORK/mocks"; mkdir -p "$MOCKS"

# ── mocks ───────────────────────────────────────────────────────────────────
# brew is mocked in BOTH modes: casks are macOS-only and brew formulae are not
# what this harness validates. (cask state probe → "not installed" → install path.)
cat > "$MOCKS/brew" <<'EOF'
#!/bin/bash
echo "brew $*" >> /tmp/calls.log
[ "$1 $2" = "list --cask" ] && exit 1
exit 0
EOF
cat > "$MOCKS/notebooklm" <<'EOF'
#!/bin/bash
exit 0
EOF
if [ "$MODE" = "mock" ]; then
  # Mock everything network/system so the full script runs offline in seconds.
  cat > "$MOCKS/claude" <<'EOF'
#!/bin/bash
echo "claude $*" >> /tmp/calls.log
case "$1 $2" in
  "plugin list") echo "no plugins installed"; exit 0 ;;
  "mcp get") exit 1 ;;
esac
exit 0
EOF
  cat > "$MOCKS/npm" <<'EOF'
#!/bin/bash
echo "npm $*" >> /tmp/calls.log
[ "$1" = "list" ] && exit 1
exit 0
EOF
  cat > "$MOCKS/uv" <<'EOF'
#!/bin/bash
echo "uv $*" >> /tmp/calls.log
[ "$1 $2" = "tool dir" ] && { echo "$HOME/.local/bin"; exit 0; }
exit 0
EOF
  cat > "$MOCKS/git" <<'EOF'
#!/bin/bash
echo "git $*" >> /tmp/calls.log
if [ "$1" = "clone" ]; then
  d="${@: -1}"
  mkdir -p "$d/.claude/skills/mock"
  printf -- '---\nname: mock\n---\n' > "$d/.claude/skills/mock/SKILL.md"
  printf -- '---\nname: single\n---\n' > "$d/SKILL.md"
fi
exit 0
EOF
  for t in npx pnpm curl; do
    printf '#!/bin/bash\necho "%s $*" >> /tmp/calls.log\nexit 0\n' "$t" > "$MOCKS/$t"
  done
fi
chmod +x "$MOCKS"/*

# ── auth material for --real --copy-auth ────────────────────────────────────
mkdir -p "$WORK/auth"
if [ "$MODE" = "real" ] && [ "$AUTH" = "copy" ]; then
  [ -f "$HOME/.claude/.credentials.json" ] && cp "$HOME/.claude/.credentials.json" "$WORK/auth/" 2>/dev/null || true
  [ -f "$HOME/.claude.json" ] && cp "$HOME/.claude.json" "$WORK/auth/dotclaude.json" 2>/dev/null || true
fi

# ── in-container runner ─────────────────────────────────────────────────────
cat > "$WORK/runner.sh" <<RUNNER
#!/bin/bash
set -uo pipefail
export PATH="/host/mocks:\$PATH" HOME=/root SHELL=/bin/bash
: > /tmp/calls.log
if [ "$MODE" = "mock" ]; then
  apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq --no-install-recommends jq ca-certificates >/dev/null 2>&1
else
  apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq --no-install-recommends jq git python3 curl ca-certificates >/dev/null 2>&1
  npm install -g @anthropic-ai/claude-code pnpm >/dev/null 2>&1
  curl -LsSf https://astral.sh/uv/install.sh 2>/dev/null | sh >/dev/null 2>&1 || true
  export PATH="\$HOME/.local/bin:\$PATH"
  if [ "$AUTH" = "copy" ]; then
    mkdir -p ~/.claude
    cp /host/auth/.credentials.json ~/.claude/ 2>/dev/null || true
    cp /host/auth/dotclaude.json ~/.claude.json 2>/dev/null || true
  fi
  [ "$AUTH" = "api" ] && export ANTHROPIC_API_KEY="$API_KEY"
fi
cp -r /bionic /root/bionic && cd /root/bionic
bash claude-bootstrap.sh > /tmp/out.log 2>&1; rc=\$?
echo "===OUT_START==="; cat /tmp/out.log; echo "===OUT_END==="
echo "BOOTSTRAP_EXIT=\$rc"
echo "===CALLS_START==="; cat /tmp/calls.log 2>/dev/null; echo "===CALLS_END==="
RUNNER

# ── run ─────────────────────────────────────────────────────────────────────
echo "→ Mode: ${MODE}   Image: ${IMAGE}"
[ "$MODE" = "real" ] && echo "→ (real install run — pulls node image + claude CLI; a few minutes)"
OUT="$WORK/captured.log"
docker run --rm -v "$REPO":/bionic:ro -v "$WORK":/host:ro "$IMAGE" bash /host/runner.sh > "$OUT" 2>&1 || true

# ── parse + assert ──────────────────────────────────────────────────────────
done_line="$(grep -E '^Done' "$OUT" | tail -1)"
calls="$(awk '/===CALLS_START===/{f=1;next}/===CALLS_END===/{f=0}f' "$OUT")"
install_fails="$(awk '/Install failures/{f=1;next}/Verification errors|Warnings/{f=0}f' "$OUT" | grep -E '✗' || true)"

PASS=0; FAIL=0
ok() { echo "PASS: $1"; PASS=$((PASS+1)); }
no() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
has_call() { echo "$calls" | grep -qF "$1"; }

echo "──────────────────────────────────────────────"
if [ -z "$done_line" ]; then
  no "script reached the end-of-run summary"
  echo "    (no 'Done' line — last 15 lines of container output:)"
  tail -15 "$OUT" | sed 's/^/      /'
else
  ok "script ran to completion on a fresh OS — ${done_line}"
fi

if [ "$MODE" = "mock" ]; then
  echo "$done_line" | grep -q '0 install failure' \
    && ok "install phase completed with 0 failures (no mid-run abort)" \
    || no "install phase reported failures (mock mode expects 0): ${done_line:-<none>}"
  has_call "brew install --cask gcloud-cli --quiet"            && ok "issued: brew install --cask gcloud-cli (the gcloud fix)" || no "missing gcloud cask command"
  has_call "pnpm store add motion@latest"                      && ok "issued: pnpm store add motion@latest"                   || no "missing pnpm motion command"
  has_call "claude plugin marketplace add addyosmani/agent-skills" && ok "issued: agent-skills marketplace add"               || no "missing marketplace add"
  has_call "claude plugin install agent-skills@addy-agent-skills"  && ok "issued: agent-skills plugin install"                || no "missing plugin install"
  echo
  echo "Note: in mock mode the verification phase reports tools 'not found' — expected,"
  echo "since nothing is really installed. The signal is '0 install failures' + the"
  echo "correct commands above. For REAL install validation, run with --real."
else
  # Real mode: separate genuine failures from auth-dependent plugin/marketplace ones.
  realf="$(echo "$install_fails" | grep -vE 'marketplace |plugin ' || true)"
  authf="$(echo "$install_fails" | grep -E 'marketplace |plugin ' || true)"
  if [ -z "$realf" ]; then
    ok "no REAL (non-auth) install failures"
  else
    no "REAL install failures present:"; echo "$realf" | sed 's/^/      /'
  fi
  if [ -n "$authf" ]; then
    echo
    echo "⚠ marketplace/plugin steps failed — need an authenticated claude CLI in the"
    echo "  container. Re-run with --copy-auth or --api-key for a zero-failure check:"
    echo "$authf" | sed 's/^/      /'
  fi
fi

echo "──────────────────────────────────────────────"
echo "Docker E2E (${MODE}): ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
