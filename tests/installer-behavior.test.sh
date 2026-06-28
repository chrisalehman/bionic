#!/bin/bash
# Behavioral tests for claude-bootstrap.sh installer functions.
#
# Unlike scripts.test.sh (pure static/parsing checks, never executes bootstrap),
# this RUNS the real installer functions in a sandbox: a throwaway PATH of mock
# tools that only LOG their arguments. It installs nothing, touches no real
# ~/.claude, and hits no network — so it is safe to run anywhere, including CI.
#
# It proves the install COMMANDS are correct (the gcloud cask fix, the pnpm
# store warm) and the RESILIENCE contract (retry + record-and-continue, never
# abort) — the parts a macOS VM would otherwise be needed to observe.
#
# The functions under test are EXTRACTED from the live script at run time, so
# this test stays in lockstep with the real code (no copy to drift).
#
# Usage: bash tests/installer-behavior.test.sh

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP="${REPO}/claude-bootstrap.sh"
SBX="$(mktemp -d)"
BIN="${SBX}/bin"; LOG="${SBX}/calls.log"; CODE="${SBX}/code.sh"
mkdir -p "$BIN"; : > "$LOG"
trap 'rm -rf "$SBX"' EXIT

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
no()  { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
logged()    { grep -qxF "$1" "$LOG"; }
expect_log(){ if logged "$1"; then ok "$2"; else no "$2 (expected log line: '$1')"; fi; }

# ---------- mock tools (log args; simulate "not yet installed") ----------
cat > "${BIN}/brew" <<EOF
#!/bin/bash
echo "brew \$*" >> "$LOG"
[ "\$1 \$2" = "list --cask" ] && exit 1   # cask not yet installed → take install path
exit 0
EOF
cat > "${BIN}/pnpm" <<EOF
#!/bin/bash
echo "pnpm \$*" >> "$LOG"
exit 0
EOF
# A deliberately-failing tool to prove non-fatal handling.
cat > "${BIN}/brokenbrew" <<EOF
#!/bin/bash
echo "brokenbrew \$*" >> "$LOG"
echo "simulated failure" >&2
exit 1
EOF
chmod +x "${BIN}"/*

# ---------- extract the REAL resilience block + installer functions ----------
awk '/^# ─── Resilience ───/{f=1} f{print} /^# ─── Helpers ───/{if(f)exit}' "$BOOTSTRAP" > "$CODE"
for fn in do_install_brew_cask do_install_pnpm_store; do
  awk -v fn="$fn" '$0 ~ "^"fn"\\(\\) \\{"{f=1} f{print} f&&/^\}$/{exit}' "$BOOTSTRAP" >> "$CODE"
done

# ---------- run under a restricted PATH (mock bin + core dirs only) ----------
# Excludes /opt/homebrew & any google-cloud-sdk so `command -v gcloud` fails and
# the install path is genuinely exercised.
export PATH="${BIN}:/usr/bin:/bin"
export RETRY_MAX=2
# shellcheck disable=SC1090
source "$CODE"

# 1) brew-cask: idempotency probe then the corrected cask install command.
: > "$LOG"
do_install_brew_cask gcloud gcloud-cli >/dev/null
expect_log "brew list --cask gcloud-cli"           "brew-cask checks cask state first (idempotent)"
expect_log "brew install --cask gcloud-cli --quiet" "brew-cask installs via 'brew install --cask gcloud-cli' (the gcloud fix)"
[ "${#INSTALL_FAILURES[@]}" -eq 0 ] && ok "brew-cask success records no failure" || no "brew-cask should not record a failure on success"

# 2) pnpm-store: warms @latest into the store.
: > "$LOG"; INSTALL_FAILURES=()
do_install_pnpm_store motion >/dev/null
expect_log "pnpm store add motion@latest" "pnpm-store warms 'pnpm store add motion@latest'"

# 3) run_retry: retries up to RETRY_MAX, returns non-zero, captures stderr.
: > "$LOG"; INSTALL_FAILURES=()
cnt="${SBX}/cnt"; : > "$cnt"
flaky(){ echo x >> "$cnt"; echo "err-$(wc -l < "$cnt" | tr -d ' ')" >&2; return 1; }
if run_retry flaky; then no "run_retry should fail when the command always fails"; else ok "run_retry returns non-zero after exhausting retries"; fi
[ "$(wc -l < "$cnt" | tr -d ' ')" = "2" ] && ok "run_retry made exactly RETRY_MAX (2) attempts" || no "run_retry attempt count wrong"
[ "$RUN_ERR" = "err-2" ] && ok "run_retry captured last stderr into RUN_ERR" || no "run_retry did not capture stderr (got '$RUN_ERR')"

# 4) resilience contract: a failing installer records and CONTINUES (returns 0).
: > "$LOG"; INSTALL_FAILURES=()
demo(){ if run_retry brokenbrew install x; then echo ok; else record_fail "demo: $RUN_ERR"; fi; return 0; }
demo >/dev/null; rc=$?
[ "$rc" -eq 0 ] && ok "failing installer returns 0 (run never aborts mid-way)" || no "installer aborted (rc=$rc)"
[ "${#INSTALL_FAILURES[@]}" -eq 1 ] && ok "the failure was recorded for the end-of-run summary" || no "failure not recorded"

echo "========================================"
echo "Installer behavior: ${PASS} passed, ${FAIL} failed"
echo "========================================"
[ "$FAIL" -eq 0 ]
