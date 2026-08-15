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
for fn in do_install_brew_cask do_install_pnpm_store _pw_satisfied _pw_lock_preflight _playwright_install do_install_playwright_chromium _excalidraw_dry_run _excalidraw_setup do_setup_excalidraw_renderer _pw_link_demands _pw_component_dir _pw_link_missing _pw_heal_node _pw_heal_one do_heal_playwright_registry verify_playwright_registry do_install_agents do_preflight_node _node_probe do_preflight_registry_tls do_preflight_claude_cli; do
  awk -v fn="$fn" '$0 ~ "^"fn"\\(\\) \\{"{f=1} f{print} f&&/^\}$/{exit}' "$BOOTSTRAP" >> "$CODE"
done

# ---------- run under a restricted PATH (mock bin + core dirs only) ----------
# Excludes /opt/homebrew & any google-cloud-sdk so `command -v gcloud` fails and
# the install path is genuinely exercised. jq is symlinked in for real (the
# registry-heal helpers need the real jq; Homebrew's jq may be excluded below).
ln -s "$(command -v jq)" "${BIN}/jq"
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

# 5) run_retry detaches the child's stdin (tap-install stdin-theft defense):
# a command that drains stdin must see EOF immediately, not the caller's input.
stdin_probe(){ drained="$(cat)"; [ -z "$drained" ]; }
if echo "should-not-be-seen" | { run_retry stdin_probe; } ; then
  ok "run_retry runs children with stdin detached (</dev/null)"
else
  no "run_retry leaked caller stdin into the child"
fi

# 6) step_fail: prints the failure line, records a well-formed STEP_RECORDS
# entry (status|category|section|name|remediation|detail, detail last), and
# feeds INSTALL_FAILURES.
INSTALL_FAILURES=(); STEP_RECORDS=(); CURRENT_SECTION="TestSection"
step_start "demo-step" >/dev/null
step_fail network "boom|with pipe" "do the thing" > "$SBX/sf.out" 2>&1
out="$(cat "$SBX/sf.out")"
echo "$out" | grep -q "✗ failed (continuing)" && ok "step_fail prints '✗ failed (continuing)'" || no "step_fail output wrong: $out"
[ "${#STEP_RECORDS[@]}" -eq 1 ] && ok "step_fail appended one STEP_RECORDS entry" || no "STEP_RECORDS length ${#STEP_RECORDS[@]}"
IFS='|' read -r r_st r_cat r_sec r_name r_rem r_det <<< "${STEP_RECORDS[0]}"
[ "$r_st" = "fail" ] && [ "$r_cat" = "network" ] && [ "$r_sec" = "TestSection" ] && [ "$r_name" = "demo-step" ] && [ "$r_rem" = "do the thing" ] \
  && ok "step_fail record fields parse correctly" \
  || no "step_fail record malformed: ${STEP_RECORDS[0]}"
[ "$r_det" = "boom|with pipe" ] && ok "detail-last keeps embedded pipes intact" || no "detail mangled: '$r_det'"
[ "${#INSTALL_FAILURES[@]}" -eq 1 ] && ok "step_fail feeds legacy INSTALL_FAILURES" || no "step_fail did not record_fail"

# 7) step_ok after a retried success notes the attempt count.
STEP_RECORDS=()
flaky2_cnt="${SBX}/cnt2"; : > "$flaky2_cnt"
flaky2(){ echo x >> "$flaky2_cnt"; [ "$(wc -l < "$flaky2_cnt" | tr -d ' ')" -ge 2 ]; }
step_start "retry-step" >/dev/null
if run_retry flaky2; then
  step_ok network > "$SBX/so.out" 2>&1
  out="$(cat "$SBX/so.out")"
  echo "$out" | grep -q "succeeded on retry 2" && ok "step_ok reports retry count" || no "retry note missing: $out"
else
  no "flaky2 should succeed on attempt 2"
fi

# 8) Playwright guard helpers.
# _pw_satisfied: parses 'Install location:' lines; 0 iff all carry the marker.
PWSBX="${SBX}/pw"; mkdir -p "${PWSBX}/loc-a" "${PWSBX}/loc-b"
touch "${PWSBX}/loc-a/INSTALLATION_COMPLETE" "${PWSBX}/loc-b/INSTALLATION_COMPLETE"
dry_ok(){ printf '  Install location:    %s\n  Install location:    %s\n' "${PWSBX}/loc-a" "${PWSBX}/loc-b"; }
if _pw_satisfied dry_ok; then ok "satisfied when all locations carry INSTALLATION_COMPLETE"; else no "should be satisfied (all markers present)"; fi

rm "${PWSBX}/loc-b/INSTALLATION_COMPLETE"
if _pw_satisfied dry_ok; then no "must not skip when a marker is missing"; else ok "unsatisfied when any marker is missing"; fi

dry_fail(){ return 1; }
if _pw_satisfied dry_fail; then no "must not skip when dry-run fails"; else ok "unsatisfied when dry-run exits non-zero (fail-open to install)"; fi

dry_empty(){ echo "no locations here"; }
if _pw_satisfied dry_empty; then no "must not skip on zero parsed locations"; else ok "unsatisfied on zero 'Install location:' lines (fail-open to install)"; fi

# _pw_lock_preflight: stale lock removed; held lock refused.
export PLAYWRIGHT_CACHE="${PWSBX}/cache"; mkdir -p "${PLAYWRIGHT_CACHE}/__dirlock"
cat > "${BIN}/pgrep" <<'EOF'
#!/bin/bash
exit 0   # simulate: a live playwright install exists
EOF
chmod +x "${BIN}/pgrep"
if _pw_lock_preflight; then no "held lock must refuse install"; else ok "lock + live installer → preflight refuses"; fi
[ -d "${PLAYWRIGHT_CACHE}/__dirlock" ] && ok "held lock is not removed" || no "held lock must be left in place"

cat > "${BIN}/pgrep" <<'EOF'
#!/bin/bash
exit 1   # simulate: no playwright install running
EOF
chmod +x "${BIN}/pgrep"
if _pw_lock_preflight; then ok "stale lock → preflight clears"; else no "stale lock should clear"; fi
[ -d "${PLAYWRIGHT_CACHE}/__dirlock" ] && no "stale lock must be removed" || ok "stale lock removed"

if _pw_lock_preflight; then ok "no lock → preflight passes"; else no "no lock should pass"; fi

# 9) chromium step wiring: skip / fail-fast / install branches.
cat > "${BIN}/npx" <<EOF
#!/bin/bash
echo "npx \$*" >> "$LOG"
case "\$*" in
  *--dry-run*) cat "${PWSBX}/dryrun.txt" ;;
esac
exit 0
EOF
chmod +x "${BIN}/npx"

# 9a) warm cache → cached, real install never invoked
mkdir -p "${PWSBX}/loc-c"; touch "${PWSBX}/loc-c/INSTALLATION_COMPLETE"
printf '  Install location:    %s\n' "${PWSBX}/loc-c" > "${PWSBX}/dryrun.txt"
rm -rf "${PLAYWRIGHT_CACHE}/__dirlock"
: > "$LOG"; INSTALL_FAILURES=()
do_install_playwright_chromium >/dev/null
expect_log "npx --yes playwright@latest install chromium --dry-run" "chromium step probes via --dry-run"
if logged "npx --yes playwright@latest install chromium"; then no "warm cache must not run the real install"; else ok "warm cache skips the real install"; fi

# 9b) cold cache, no lock → real install runs
rm "${PWSBX}/loc-c/INSTALLATION_COMPLETE"
: > "$LOG"; INSTALL_FAILURES=()
do_install_playwright_chromium >/dev/null
expect_log "npx --yes playwright@latest install chromium" "cold cache runs the real install"

# 9c) cold cache + held lock → fail fast, no real install, failure recorded
mkdir -p "${PLAYWRIGHT_CACHE}/__dirlock"
cat > "${BIN}/pgrep" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "${BIN}/pgrep"
: > "$LOG"; INSTALL_FAILURES=()
do_install_playwright_chromium >/dev/null
if logged "npx --yes playwright@latest install chromium"; then no "held lock must not attempt the real install"; else ok "held lock skips the real install attempt"; fi
[ "${#INSTALL_FAILURES[@]}" -eq 1 ] && ok "held lock records exactly one failure" || no "held lock should record a failure (got ${#INSTALL_FAILURES[@]})"
case "${INSTALL_FAILURES[0]:-}" in *"second Claude session"*) ok "failure names the second-session cause";; *) no "failure text should name the second-session cause";; esac
rm -rf "${PLAYWRIGHT_CACHE}/__dirlock"
cat > "${BIN}/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "${BIN}/pgrep"

# 10) excalidraw renderer wiring: same guard against the python playwright CLI.
cat > "${BIN}/uv" <<EOF
#!/bin/bash
echo "uv \$*" >> "$LOG"
case "\$*" in
  *--dry-run*) cat "${PWSBX}/dryrun.txt" ;;
esac
exit 0
EOF
chmod +x "${BIN}/uv"
REFS="${PWSBX}/refs"; mkdir -p "$REFS"

# 10a) warm → dry-run probed, real install not invoked
mkdir -p "${PWSBX}/loc-d"; touch "${PWSBX}/loc-d/INSTALLATION_COMPLETE"
printf '  Install location:    %s\n' "${PWSBX}/loc-d" > "${PWSBX}/dryrun.txt"
: > "$LOG"; INSTALL_FAILURES=()
do_setup_excalidraw_renderer "$REFS" >/dev/null
expect_log "uv run playwright install chromium --dry-run" "renderer probes via the python CLI's --dry-run"
if logged "uv run playwright install chromium"; then no "warm cache must not run the renderer install"; else ok "warm cache skips the renderer install"; fi

# 10b) cold → real setup runs (uv sync + install via _excalidraw_setup)
rm "${PWSBX}/loc-d/INSTALLATION_COMPLETE"
: > "$LOG"; INSTALL_FAILURES=()
do_setup_excalidraw_renderer "$REFS" >/dev/null
expect_log "uv sync --quiet" "cold cache syncs the venv"
expect_log "uv run playwright install chromium" "cold cache runs the renderer install"

# 10c) cold + held lock → fail fast, recorded
mkdir -p "${PLAYWRIGHT_CACHE}/__dirlock"
cat > "${BIN}/pgrep" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "${BIN}/pgrep"
: > "$LOG"; INSTALL_FAILURES=()
do_setup_excalidraw_renderer "$REFS" >/dev/null
if logged "uv run playwright install chromium"; then no "held lock must not attempt the renderer install"; else ok "held lock skips the renderer install attempt"; fi
[ "${#INSTALL_FAILURES[@]}" -eq 1 ] && ok "renderer held-lock failure recorded" || no "renderer held-lock failure missing"
rm -rf "${PLAYWRIGHT_CACHE}/__dirlock"
cat > "${BIN}/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "${BIN}/pgrep"

# 11) Registry-heal helpers: demand parse, dir mapping, missing detection.
REG="${SBX}/registry"; export PLAYWRIGHT_CACHE="${REG}/cache"
mkdir -p "${PLAYWRIGHT_CACHE}/.links"

# mk_pw_install <dir> <version> <chromium-rev> — fabricate a playwright-core
# package dir with a realistic browsers.json (ffmpeg on its own revision;
# firefox present to prove the chromium-set filter).
mk_pw_install() {
  mkdir -p "$1"
  printf '{"version":"%s"}\n' "$2" > "$1/package.json"
  cat > "$1/browsers.json" <<JSON
{"browsers":[
  {"name":"chromium","revision":"$3","installByDefault":true},
  {"name":"chromium-headless-shell","revision":"$3","installByDefault":true},
  {"name":"ffmpeg","revision":"9999","revisionOverrides":{"mac12":"8888"},"installByDefault":true},
  {"name":"firefox","revision":"7777","installByDefault":true}
]}
JSON
}
satisfy_component() {  # <name> <rev>
  local d; d="$(_pw_component_dir "$1" "$2")"
  mkdir -p "$d"; touch "$d/INSTALLATION_COMPLETE"
}

PROJ_A="${REG}/proj-a/node_modules/playwright-core"
mk_pw_install "$PROJ_A" "1.59.1" "1217"

# 11a) demands: chromium set only, name+revision pairs
d="$(_pw_link_demands "$PROJ_A")"
echo "$d" | grep -qx "chromium 1217" && ok "demands include chromium 1217" || no "chromium demand missing: $d"
echo "$d" | grep -qx "chromium-headless-shell 1217" && ok "demands include headless shell" || no "shell demand missing"
echo "$d" | grep -qx "ffmpeg 9999 8888" && ok "demands include ffmpeg with override candidates" || no "ffmpeg demand missing/wrong: $d"
echo "$d" | grep -q "firefox" && no "firefox must be filtered out" || ok "firefox filtered from demands"

# 11b) dir mapping: dashes become underscores
[ "$(_pw_component_dir chromium-headless-shell 1217)" = "${PLAYWRIGHT_CACHE}/chromium_headless_shell-1217" ] \
  && ok "component dir maps dashes to underscores" || no "dir mapping wrong: $(_pw_component_dir chromium-headless-shell 1217)"
[ "$(_pw_component_dir chromium 1217)" = "${PLAYWRIGHT_CACHE}/chromium-1217" ] \
  && ok "chromium dir mapping" || no "chromium dir mapping wrong"

# 11c) missing detection: all missing → three names; marker required
m="$(_pw_link_missing "$PROJ_A")"
[ "$(echo "$m" | wc -l | tr -d ' ')" = "3" ] && ok "all three components reported missing" || no "missing list wrong: $m"
satisfy_component chromium 1217
mkdir -p "$(_pw_component_dir chromium-headless-shell 1217)"   # dir but NO marker
m="$(_pw_link_missing "$PROJ_A")"
echo "$m" | grep -qx "chromium" && no "satisfied chromium must not be listed" || ok "satisfied component not listed"
echo "$m" | grep -qx "chromium-headless-shell" && ok "marker-less dir still counts missing" || no "marker-less dir must count missing"

# 11d) fully satisfied → empty output, rc 0
satisfy_component chromium-headless-shell 1217
satisfy_component ffmpeg 9999
m="$(_pw_link_missing "$PROJ_A")"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$m" ] && ok "fully satisfied → empty, rc 0" || no "satisfied walk wrong (rc=$rc, m='$m')"

# 11e) unreadable browsers.json → rc 1 (fail-open signal)
NOJSON="${REG}/proj-b/node_modules/playwright-core"; mkdir -p "$NOJSON"
if _pw_link_missing "$NOJSON" >/dev/null; then no "missing browsers.json must rc 1"; else ok "missing browsers.json → rc 1"; fi
printf 'not json' > "$NOJSON/browsers.json"
if _pw_link_missing "$NOJSON" >/dev/null; then no "corrupt browsers.json must rc 1"; else ok "corrupt browsers.json → rc 1"; fi

export PLAYWRIGHT_HEAL_NODE=node   # hermetic: resolver must pick the PATH mock, not a real brew node@22
# 12) Registry heal wiring: heal / warm no-op / dangling / unreadable / lock.
cat > "${BIN}/node" <<EOF
#!/bin/bash
echo "node \$*" >> "$LOG"
case "\$1" in -e) echo 22; exit 0 ;; esac
exit 0
EOF
chmod +x "${BIN}/node"

# 12a) missing build → heals via THAT installation's own CLI
rm -rf "${PLAYWRIGHT_CACHE}"; mkdir -p "${PLAYWRIGHT_CACHE}/.links"
mk_pw_install "$PROJ_A" "1.59.1" "1217"
echo "$PROJ_A" > "${PLAYWRIGHT_CACHE}/.links/aaa"
satisfy_component chromium 1217; satisfy_component ffmpeg 9999   # shell missing
: > "$LOG"; INSTALL_FAILURES=()
do_heal_playwright_registry >/dev/null
expect_log "node ${PROJ_A}/cli.js install chromium" "heal invokes the installation's own cli.js"
[ "${#INSTALL_FAILURES[@]}" -eq 0 ] && ok "successful heal records no failure" || no "heal recorded spurious failure"

# 12b) fully satisfied → no node invocation, satisfied line printed
satisfy_component chromium-headless-shell 1217
: > "$LOG"; INSTALL_FAILURES=()
out="$(do_heal_playwright_registry)"
if logged "node ${PROJ_A}/cli.js install chromium"; then no "warm registry must not invoke cli.js"; else ok "warm registry skips the install"; fi
echo "$out" | grep -q "pinned builds present" && ok "satisfied link prints presence line" || no "presence line missing: $out"

# 12c) dangling link → loud skip, no node, no failure
echo "${REG}/gone/node_modules/playwright-core" > "${PLAYWRIGHT_CACHE}/.links/bbb"
: > "$LOG"; INSTALL_FAILURES=()
out="$(do_heal_playwright_registry)"
echo "$out" | grep -q "dangling registry link" && ok "dangling link skips loudly" || no "dangling skip line missing: $out"
[ "${#INSTALL_FAILURES[@]}" -eq 0 ] && ok "dangling link records no failure" || no "dangling link must not record a failure"
rm "${PLAYWRIGHT_CACHE}/.links/bbb"

# 12d) unreadable browsers.json → loud skip, no node, no failure
mkdir -p "$NOJSON"; printf 'not json' > "$NOJSON/browsers.json"
echo "$NOJSON" > "${PLAYWRIGHT_CACHE}/.links/ccc"
: > "$LOG"; INSTALL_FAILURES=()
out="$(do_heal_playwright_registry)"
echo "$out" | grep -q "unreadable browsers.json" && ok "unreadable demands skip loudly" || no "unreadable skip line missing: $out"
if logged "node ${NOJSON}/cli.js install chromium"; then no "unreadable demands must not heal"; else ok "unreadable demands do not invoke cli.js"; fi
rm "${PLAYWRIGHT_CACHE}/.links/ccc"

# 12e) held lock → fail fast, no node, one named failure
rm "$(_pw_component_dir chromium-headless-shell 1217)/INSTALLATION_COMPLETE"
mkdir -p "${PLAYWRIGHT_CACHE}/__dirlock"
cat > "${BIN}/pgrep" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "${BIN}/pgrep"
: > "$LOG"; INSTALL_FAILURES=()
do_heal_playwright_registry >/dev/null
if logged "node ${PROJ_A}/cli.js install chromium"; then no "held lock must not heal"; else ok "held lock skips the heal attempt"; fi
[ "${#INSTALL_FAILURES[@]}" -eq 1 ] && ok "held-lock heal records one failure" || no "held-lock failure count ${#INSTALL_FAILURES[@]}"
case "${INSTALL_FAILURES[0]:-}" in *"second Claude session"*) ok "heal failure names the second-session cause";; *) no "heal failure text wrong";; esac
rm -rf "${PLAYWRIGHT_CACHE}/__dirlock"
cat > "${BIN}/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "${BIN}/pgrep"

# 12f) empty/absent registry → quiet no-op, rc 0
rm -f "${PLAYWRIGHT_CACHE}/.links/aaa"
if do_heal_playwright_registry >/dev/null; then ok "empty registry no-ops (rc 0)"; else no "empty registry must rc 0"; fi
rm -rf "${PLAYWRIGHT_CACHE}/.links"
out="$(do_heal_playwright_registry)"; rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q "no installation registry" && ok "absent .links skips loudly, rc 0" || no "absent .links handling wrong (rc=$rc): $out"
mkdir -p "${PLAYWRIGHT_CACHE}/.links"

# 12g) AC-4: a heal whose underlying node invocation FAILS records exactly one
# failure and does NOT abort the walk — it continues to heal a subsequent link.
PROJ_C="${REG}/proj-c/node_modules/playwright-core"
mk_pw_install "$PROJ_C" "1.59.1" "1217"
rm -rf "${PLAYWRIGHT_CACHE}"; mkdir -p "${PLAYWRIGHT_CACHE}/.links"
echo "$PROJ_A" > "${PLAYWRIGHT_CACHE}/.links/aaa"
echo "$PROJ_C" > "${PLAYWRIGHT_CACHE}/.links/ccc"
satisfy_component chromium 1217; satisfy_component ffmpeg 9999   # both links missing only the shell build
cat > "${BIN}/node" <<EOF
#!/bin/bash
echo "node \$*" >> "$LOG"
case "\$1" in -e) echo 22; exit 0 ;; esac
case "\$*" in
  *proj-a*) exit 1 ;;
esac
exit 0
EOF
chmod +x "${BIN}/node"
: > "$LOG"; INSTALL_FAILURES=()
do_heal_playwright_registry >/dev/null; rc=$?
[ "$rc" -eq 0 ] && ok "heal walk returns 0 even when one link's underlying install fails" || no "heal walk aborted (rc=$rc)"
expect_log "node ${PROJ_A}/cli.js install chromium" "failing heal still invokes proj-a's own cli.js"
expect_log "node ${PROJ_C}/cli.js install chromium" "walk continues to heal proj-c after proj-a's failure"
[ "${#INSTALL_FAILURES[@]}" -eq 1 ] && ok "exactly one failure recorded for the failing heal" || no "failure count wrong (got ${#INSTALL_FAILURES[@]})"

# restore the standard exit-0 node mock so later sections are unaffected
cat > "${BIN}/node" <<EOF
#!/bin/bash
echo "node \$*" >> "$LOG"
case "\$1" in -e) echo 22; exit 0 ;; esac
exit 0
EOF
chmod +x "${BIN}/node"

# 13) Verification walk: per-link status lines + named verify errors.
# 13a) satisfied link → ✓ line, no errors
rm -rf "${PLAYWRIGHT_CACHE}"; mkdir -p "${PLAYWRIGHT_CACHE}/.links"
mk_pw_install "$PROJ_A" "1.59.1" "1217"
echo "$PROJ_A" > "${PLAYWRIGHT_CACHE}/.links/aaa"
satisfy_component chromium 1217; satisfy_component chromium-headless-shell 1217; satisfy_component ffmpeg 9999
verify_errors=()
out="$(verify_playwright_registry)"
echo "$out" | grep -q "playwright 1.59.1" && echo "$out" | grep -q "✓" && ok "satisfied link prints ✓ with version" || no "✓ line wrong: $out"
[ "${#verify_errors[@]}" -eq 0 ] && ok "satisfied link adds no verify error" || no "spurious verify error: ${verify_errors[*]}"

# 13b) missing build → named error naming the component
rm "$(_pw_component_dir chromium-headless-shell 1217)/INSTALLATION_COMPLETE"
verify_errors=()
pw13b_out="$(mktemp)"; verify_playwright_registry > "$pw13b_out"; out="$(cat "$pw13b_out")"; rm -f "$pw13b_out"
echo "$out" | grep -q "missing" && ok "missing build printed" || no "missing line absent: $out"
[ "${#verify_errors[@]}" -eq 1 ] && ok "missing build adds one verify error" || no "verify_errors count ${#verify_errors[@]}"
case "${verify_errors[0]:-}" in *chromium-headless-shell*) ok "verify error names the component";; *) no "component name missing: ${verify_errors[0]:-}";; esac

# 13c) dangling + unreadable links → silently skipped, no errors
echo "${REG}/gone2/node_modules/playwright-core" > "${PLAYWRIGHT_CACHE}/.links/ddd"
printf 'not json' > "$NOJSON/browsers.json"; echo "$NOJSON" > "${PLAYWRIGHT_CACHE}/.links/eee"
satisfy_component chromium-headless-shell 1217
verify_errors=()
verify_playwright_registry >/dev/null
[ "${#verify_errors[@]}" -eq 0 ] && ok "dangling/unreadable links add no verify errors" || no "skips must not error: ${verify_errors[*]}"

# 14) Review-fix regressions: revisionOverrides + set -e fail-open.
# 14a) component satisfied via an override revision only → not missing
rm -rf "${PLAYWRIGHT_CACHE}"; mkdir -p "${PLAYWRIGHT_CACHE}/.links"
mk_pw_install "$PROJ_A" "1.59.1" "1217"
satisfy_component chromium 1217; satisfy_component chromium-headless-shell 1217
satisfy_component ffmpeg 8888          # only the override build present
m="$(_pw_link_missing "$PROJ_A")"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$m" ] && ok "override revision satisfies the component" || no "override not accepted (rc=$rc, m='$m')"

# 14b) heal walk survives set -e with a subdirectory + unreadable file in .links
echo "$PROJ_A" > "${PLAYWRIGHT_CACHE}/.links/good"
mkdir -p "${PLAYWRIGHT_CACHE}/.links/stray-dir"
echo "$PROJ_A" > "${PLAYWRIGHT_CACHE}/.links/unreadable"; chmod 000 "${PLAYWRIGHT_CACHE}/.links/unreadable"
: > "$LOG"; INSTALL_FAILURES=()
if (set -e; do_heal_playwright_registry >/dev/null); then ok "heal survives dir+unreadable under set -e"; else no "heal aborted under set -e"; fi

# 14c) verify walk too, and the good link still gets its ✓ alongside bad entries
verify_errors=()
if (set -e; verify_playwright_registry > "${SBX}/v14.out"); then ok "verify survives dir+unreadable under set -e"; else no "verify aborted under set -e"; fi
grep -q "✓" "${SBX}/v14.out" && ok "good link still verified alongside bad entries" || no "good link not processed: $(cat "${SBX}/v14.out")"
chmod 700 "${PLAYWRIGHT_CACHE}/.links/unreadable"

# 15) Heal-node resolver: version-pair safety (node >=23 deadlocks playwright <=1.59).
# 15a) modern CLI → system node fast path
nb="$(_pw_heal_node 1.61.1)" && [ "$nb" = "node" ] && ok "1.61+ resolves to system node" || no "fast path wrong: ${nb:-rc1}"
nb="$(_pw_heal_node 1.62.0-alpha-1783623505000)" && [ "$nb" = "node" ] && ok "1.62-alpha resolves to system node" || no "alpha fast path wrong: ${nb:-rc1}"
# 15b) old CLI + override probing 26 → override rejected, some <=22 runtime wins
cat > "${BIN}/node26bad" <<'MOCK'
#!/bin/bash
case "$1" in -e) echo 26; exit 0 ;; esac
exit 0
MOCK
chmod +x "${BIN}/node26bad"
nb="$(PLAYWRIGHT_HEAL_NODE="${BIN}/node26bad" _pw_heal_node 1.59.1)"; rc=$?
[ "$rc" -eq 0 ] && [ "$nb" != "${BIN}/node26bad" ] && ok "old CLI rejects node-26 override, picks a <=22 runtime" || no "resolver accepted unsafe runtime: ${nb:-rc1}"
# 15c) no safe runtime anywhere → heal skips loudly, never invokes the CLI
rm -rf "${PLAYWRIGHT_CACHE}"; mkdir -p "${PLAYWRIGHT_CACHE}/.links"
mk_pw_install "$PROJ_A" "1.59.1" "1217"
echo "$PROJ_A" > "${PLAYWRIGHT_CACHE}/.links/aaa"
: > "$LOG"
out="$(_pw_heal_node(){ return 1; }; do_heal_playwright_registry)"
echo "$out" | grep -q "needs node" && echo "$out" | grep -q "PLAYWRIGHT_HEAL_NODE" && ok "no-safe-node skips loudly with remediation" || no "skip/remediation line missing: $out"
if logged "node ${PROJ_A}/cli.js install chromium"; then no "no-safe-node must not invoke the CLI"; else ok "no CLI invocation without a safe runtime"; fi

# 16) Verify-error hint: names the real fix when this machine can't heal.
# 16a) resolver fails → error carries the node<=22 / upgrade hint
rm -rf "${PLAYWRIGHT_CACHE}"; mkdir -p "${PLAYWRIGHT_CACHE}/.links"
mk_pw_install "$PROJ_A" "1.59.1" "1217"
echo "$PROJ_A" > "${PLAYWRIGHT_CACHE}/.links/aaa"
_pw_heal_node_saved="$(declare -f _pw_heal_node)"
_pw_heal_node() { return 1; }
verify_errors=()
verify_playwright_registry > /dev/null
case "${verify_errors[0]:-}" in *"heal skipped"*node*) ok "unhealable install's verify error names node<=22/upgrade fix";; *) no "hint missing: ${verify_errors[0]:-none}";; esac
eval "$_pw_heal_node_saved"
# 16b) resolver succeeds → no hint (generic re-run advice is then correct)
verify_errors=()
verify_playwright_registry > /dev/null
case "${verify_errors[0]:-}" in *"heal skipped"*) no "healable install must not carry the hint: ${verify_errors[0]:-}";; "") no "expected a verify error (builds are missing)";; *) ok "healable install's verify error stays generic";; esac

# 17) Global agents install (Pattern B: mirrors the hooks install — glob copy,
# manifest-scoped orphan-prune). Sandboxed via SCRIPT_DIR (fixture repo with a
# fake agents/ dir, same convention the hooks block uses for its source glob)
# and HOME (fake ~/.claude/agents) — no real ~/.claude is touched.
#
# ~/.claude/agents/ is Claude Code's standard USER subagent directory, so the
# prune must be scoped to MANIFEST-TRACKED orphans only: a hand-authored file
# that bionic never installed (never listed in .bionic-manifest) must never
# be deleted, even though it isn't in the repo either.
AGSBX="${SBX}/agents-sandbox"
mkdir -p "${AGSBX}/repo/agents" "${AGSBX}/home/.claude/agents"
printf -- '---\nname: alpha\n---\nalpha body\n' > "${AGSBX}/repo/agents/alpha.md"
printf -- '---\nname: beta\n---\nbeta body\n' > "${AGSBX}/repo/agents/beta.md"
printf -- '---\nname: gamma\n---\ngamma body\n' > "${AGSBX}/repo/agents/gamma.md"
echo "hand-authored, not from bionic" > "${AGSBX}/home/.claude/agents/user-custom.md"
echo "pre-existing stray, no manifest yet" > "${AGSBX}/home/.claude/agents/stray.md"

# --- Run 1: no manifest exists yet ---
: > "$LOG"; INSTALL_FAILURES=()
( export SCRIPT_DIR="${AGSBX}/repo" HOME="${AGSBX}/home"; do_install_agents >/dev/null )
rc=$?
[ "$rc" -eq 0 ] && ok "do_install_agents returns 0" || no "do_install_agents failed (rc=$rc)"

[ -f "${AGSBX}/home/.claude/agents/alpha.md" ] && [ -f "${AGSBX}/home/.claude/agents/beta.md" ] \
  && [ -f "${AGSBX}/home/.claude/agents/gamma.md" ] \
  && ok "all 3 fixture role files copied to ~/.claude/agents" \
  || no "role files not copied"
diff -q "${AGSBX}/repo/agents/alpha.md" "${AGSBX}/home/.claude/agents/alpha.md" >/dev/null 2>&1 \
  && ok "copied file content matches source" || no "copied content mismatch"

[ -f "${AGSBX}/home/.claude/agents/user-custom.md" ] \
  && ok "user-authored file (never manifest-tracked) survives run 1" \
  || no "user-authored file was deleted on run 1"
[ -f "${AGSBX}/home/.claude/agents/stray.md" ] \
  && ok "first-run-no-manifest: pre-existing stray file survives (nothing pruned)" \
  || no "first-run-no-manifest incorrectly pruned a file"

manifest="${AGSBX}/home/.claude/agents/.bionic-manifest"
if [ -f "$manifest" ]; then
  ok "manifest written"
  sort "$manifest" > "${SBX}/manifest.sorted"
  printf 'alpha.md\nbeta.md\ngamma.md\n' | sort > "${SBX}/manifest.expected"
  diff -q "${SBX}/manifest.sorted" "${SBX}/manifest.expected" >/dev/null 2>&1 \
    && ok "manifest lists exactly the 3 installed basenames" \
    || no "manifest content wrong: $(cat "$manifest")"
else
  no "manifest missing"
  no "manifest content check skipped (no manifest)"
fi

# --- Run 2: repo drops gamma.md; manifest from run 1 still lists it ---
# gamma.md is manifest-tracked (run 1 wrote it) and now absent from repo, so
# it must be pruned. alpha/beta stay (still in repo). user-custom.md and
# stray.md must still survive — proving survival isn't a first-run
# coincidence; it holds even once a manifest exists.
rm -f "${AGSBX}/repo/agents/gamma.md"
: > "$LOG"; INSTALL_FAILURES=()
if ( set -e; export SCRIPT_DIR="${AGSBX}/repo" HOME="${AGSBX}/home"; do_install_agents >/dev/null ); then
  ok "do_install_agents survives under set -e (subshell exits 0)"
else
  no "do_install_agents aborted under set -e"
fi

[ ! -f "${AGSBX}/home/.claude/agents/gamma.md" ] \
  && ok "manifest-tracked orphan (gamma.md, dropped from repo) is pruned" \
  || no "manifest-tracked orphan not pruned"
[ -f "${AGSBX}/home/.claude/agents/alpha.md" ] && [ -f "${AGSBX}/home/.claude/agents/beta.md" ] \
  && ok "still-in-repo role files remain after run 2" \
  || no "still-in-repo role files missing after run 2"
[ -f "${AGSBX}/home/.claude/agents/user-custom.md" ] \
  && ok "user-authored file survives run 2 (still never manifest-tracked)" \
  || no "user-authored file was deleted on run 2"
[ -f "${AGSBX}/home/.claude/agents/stray.md" ] \
  && ok "pre-existing stray file survives run 2 (never manifest-tracked)" \
  || no "pre-existing stray file was deleted on run 2"

sort "$manifest" > "${SBX}/manifest2.sorted"
printf 'alpha.md\nbeta.md\n' | sort > "${SBX}/manifest2.expected"
diff -q "${SBX}/manifest2.sorted" "${SBX}/manifest2.expected" >/dev/null 2>&1 \
  && ok "manifest after run 2 lists exactly alpha.md and beta.md" \
  || no "manifest after run 2 wrong: $(cat "$manifest")"

# --- Run 3: collision — repo introduces delta.md; home already has a
# hand-authored delta.md (never bionic-installed, never manifest-tracked).
# User-territory guarantee: a collision with an untracked file must SKIP
# (not overwrite), record a step failure naming the remediation, and never
# enter the new manifest (bionic did not install it). alpha.md (manifest-
# tracked from runs 1-2) must still overwrite normally — proving the skip is
# collision-specific, not a general "existing file" freeze.
printf -- '---\nname: alpha\n---\nalpha body v2\n' > "${AGSBX}/repo/agents/alpha.md"
printf -- '---\nname: delta\n---\ndelta body\n' > "${AGSBX}/repo/agents/delta.md"
echo "hand-authored delta, never installed by bionic" > "${AGSBX}/home/.claude/agents/delta.md"

: > "$LOG"; INSTALL_FAILURES=()
# INSTALL_FAILURES mutations happen in the subshell's own memory (needed here
# to sandbox SCRIPT_DIR/HOME per-run) and don't propagate back — write the
# array out from inside the subshell instead of reading it from the parent.
_collision_out="${SBX}/collision-failures.txt"
( export SCRIPT_DIR="${AGSBX}/repo" HOME="${AGSBX}/home"
  do_install_agents >/dev/null
  printf '%s\n' ${INSTALL_FAILURES[@]+"${INSTALL_FAILURES[@]}"} > "$_collision_out" )
rc=$?
[ "$rc" -eq 0 ] && ok "do_install_agents (collision run) returns 0" || no "do_install_agents (collision run) failed (rc=$rc)"

diff -q "${AGSBX}/repo/agents/alpha.md" "${AGSBX}/home/.claude/agents/alpha.md" >/dev/null 2>&1 \
  && ok "manifest-tracked target (alpha.md) still overwritten normally" \
  || no "manifest-tracked target (alpha.md) was not updated"

grep -qxF "hand-authored delta, never installed by bionic" "${AGSBX}/home/.claude/agents/delta.md" \
  && ok "colliding user-authored file (delta.md, untracked) survives — not overwritten" \
  || no "colliding user-authored file was overwritten"

declare -a _collision_failures=()
if [ -f "$_collision_out" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && _collision_failures+=("$line")
  done < "$_collision_out"
fi
[ "${#_collision_failures[@]}" -ge 1 ] && ok "collision records at least one install failure" || no "collision recorded no failure"
_delta_fail_found=0
for f in ${_collision_failures[@]+"${_collision_failures[@]}"}; do
  case "$f" in *"user-authored"*"delta.md"*) _delta_fail_found=1;; esac
done
[ "$_delta_fail_found" -eq 1 ] \
  && ok "collision failure names delta.md and user-authored, with rename remediation" \
  || no "collision failure message missing delta.md/user-authored wording (failures: ${_collision_failures[*]:-none})"

sort "$manifest" > "${SBX}/manifest3.sorted"
printf 'alpha.md\nbeta.md\n' | sort > "${SBX}/manifest3.expected"
diff -q "${SBX}/manifest3.sorted" "${SBX}/manifest3.expected" >/dev/null 2>&1 \
  && ok "manifest after collision run still lists exactly alpha.md and beta.md (delta.md excluded)" \
  || no "manifest after collision run wrong: $(cat "$manifest")"

# ---------- F4: classify_err + deterministic short-circuit ----------
CERT_HINT="run 'brew postinstall openssl@3', then re-run ./claude-bootstrap.sh"
[ "$(classify_err 'npm error code UNABLE_TO_GET_ISSUER_CERT_LOCALLY')" = "cert|${CERT_HINT}" ] \
  && ok "classify: UNABLE_TO_GET_ISSUER_CERT_LOCALLY → cert" || no "classify: cert code"
[ "$(classify_err 'reason: unable to get local issuer certificate')" = "cert|${CERT_HINT}" ] \
  && ok "classify: issuer-cert prose → cert" || no "classify: cert prose"
[ "$(classify_err 'Error: SELF_SIGNED_CERT_IN_CHAIN')" = "cert|${CERT_HINT}" ] \
  && ok "classify: SELF_SIGNED_CERT_IN_CHAIN → cert" || no "classify: self-signed"
case "$(classify_err 'npm ERR! Error: EACCES: permission denied')" in
  perms\|*) ok "classify: EACCES → perms" ;; *) no "classify: EACCES → perms" ;; esac
case "$(classify_err 'getaddrinfo ENOTFOUND registry.npmjs.org')" in
  net\|*) ok "classify: ENOTFOUND → net" ;; *) no "classify: ENOTFOUND → net" ;; esac
[ "$(classify_err 'some totally novel failure')" = "unknown|" ] \
  && ok "classify: unknown → empty hint" || no "classify: unknown"

# step_fail consults the classifier: cert-class detail overrides canned remediation
STEP_RECORDS=(); INSTALL_FAILURES=(); STEP_NAME="npm pkg"; STEP_T0="$(date +%s)"
step_fail network 'npm error UNABLE_TO_GET_ISSUER_CERT_LOCALLY' \
  "run 'npm install -g x' by hand (EACCES → fix npm's global prefix)" >/dev/null
case "${STEP_RECORDS[0]}" in
  *"brew postinstall openssl@3"*) ok "step_fail: cert hint overrides canned EACCES hint" ;;
  *) no "step_fail: cert hint overrides (got: ${STEP_RECORDS[0]})" ;;
esac
STEP_RECORDS=(); step_fail network 'some novel failure' 'my canned hint' >/dev/null
case "${STEP_RECORDS[0]}" in
  *"my canned hint"*) ok "step_fail: unknown class keeps caller hint" ;;
  *) no "step_fail: unknown keeps caller hint" ;;
esac

# run_retry short-circuits deterministic classes: exactly ONE attempt logged
cat > "${BIN}/certfail" <<EOF
#!/bin/bash
echo "certfail \$*" >> "$LOG"
echo "npm error code UNABLE_TO_GET_ISSUER_CERT_LOCALLY" >&2
exit 1
EOF
chmod +x "${BIN}/certfail"
: > "$LOG"; RETRY_MAX=3
run_retry certfail install && no "run_retry: certfail should fail" || true
[ "$(grep -c '^certfail' "$LOG")" = "1" ] \
  && ok "run_retry: cert class short-circuits after attempt 1" \
  || no "run_retry: cert short-circuit (attempts: $(grep -c '^certfail' "$LOG"))"
: > "$LOG"; RETRY_MAX=2
run_retry brokenbrew install && no "run_retry: brokenbrew should fail" || true
[ "$(grep -c '^brokenbrew' "$LOG")" = "2" ] \
  && ok "run_retry: unknown class keeps full retries" \
  || no "run_retry: unknown retries (attempts: $(grep -c '^brokenbrew' "$LOG"))"

# ---------- F3: node hoisted, failure surfaces as node failure ----------
# Earlier sections (playwright heal) leave a mock ${BIN}/node behind; hide it
# so "node absent" actually holds (same pattern as brew.real below).
[ -e "${BIN}/node" ] && mv "${BIN}/node" "${BIN}/node.hidden"

# node absent + brew succeeds → brew install node attempted, step ok
: > "$LOG"; STEP_RECORDS=(); INSTALL_FAILURES=()
_saved_path="$PATH"; PATH="$BIN:/usr/bin:/bin"   # sandbox: no real node
step_start "node" >/dev/null
do_preflight_node >/dev/null
PATH="$_saved_path"
expect_log "brew install node --quiet" "node hoist: brew install node attempted when absent"
case "${STEP_RECORDS[0]:-}" in
  ok\|prereq\|*) ok "node hoist: success recorded as prereq ok" ;;
  *) no "node hoist: expected ok|prereq record (got: ${STEP_RECORDS[0]:-none})" ;;
esac

# node absent + brew FAILS → step_fail with brew detail; NO abort, NO claude-CLI wording
: > "$LOG"; STEP_RECORDS=(); INSTALL_FAILURES=()
_saved_path="$PATH"; PATH="$BIN:/usr/bin:/bin"
mv "${BIN}/brew" "${BIN}/brew.real"; cp "${BIN}/brokenbrew" "${BIN}/brew"
step_start "node" >/dev/null
RETRY_MAX=1 do_preflight_node >/dev/null; _rc=$?
mv "${BIN}/brew.real" "${BIN}/brew"; PATH="$_saved_path"
[ "$_rc" = "0" ] && ok "node hoist: brew failure does not abort" || no "node hoist: rc=$_rc, want 0"
case "${STEP_RECORDS[0]:-}" in
  fail\|prereq\|*\|node\|*)   # record_step: status|category|section|name|remediation|detail
    ok "node hoist: failure recorded against node step" ;;
  *) no "node hoist: expected fail|prereq|…|node record (got: ${STEP_RECORDS[0]:-none})" ;;
esac
case "${INSTALL_FAILURES[0]:-}" in
  *"claude CLI"*) no "node hoist: failure must not mention claude CLI" ;;
  node:*) ok "node hoist: failure names node, not claude CLI" ;;
  *) no "node hoist: unexpected failure record (${INSTALL_FAILURES[0]:-none})" ;;
esac

# restore the hidden mock for later sections
[ -e "${BIN}/node.hidden" ] && mv "${BIN}/node.hidden" "${BIN}/node"

# ---------- F1: registry TLS probe + auto-remediation ----------
# Probe OK → step ok, no brew call
cat > "${BIN}/node" <<EOF
#!/bin/bash
echo "node \$*" >> "$LOG"
exit 0
EOF
chmod +x "${BIN}/node"
: > "$LOG"; STEP_RECORDS=()
_saved_path="$PATH"; PATH="$BIN:/usr/bin:/bin"
step_start "registry TLS (node)" >/dev/null
do_preflight_registry_tls >/dev/null; _rc=$?
PATH="$_saved_path"
[ "$_rc" = "0" ] && ok "tls probe: healthy store passes" || no "tls probe: healthy rc=$_rc"
grep -q '^brew postinstall' "$LOG" && no "tls probe: healthy must not postinstall" \
  || ok "tls probe: no postinstall on healthy store"

# Cert failure, repair works: node fails once with cert error, succeeds after
# brew postinstall ran (stateful mock via marker file)
cat > "${BIN}/node" <<EOF
#!/bin/bash
echo "node \$*" >> "$LOG"
if [ -f "$SBX/repaired" ]; then exit 0; fi
echo "UNABLE_TO_GET_ISSUER_CERT_LOCALLY" >&2
exit 1
EOF
cat > "${BIN}/brew" <<EOF
#!/bin/bash
echo "brew \$*" >> "$LOG"
[ "\$1" = "postinstall" ] && touch "$SBX/repaired"
[ "\$1 \$2" = "list --cask" ] && exit 1
exit 0
EOF
chmod +x "${BIN}/node" "${BIN}/brew"
rm -f "$SBX/repaired"; : > "$LOG"; STEP_RECORDS=()
_saved_path="$PATH"; PATH="$BIN:/usr/bin:/bin"
step_start "registry TLS (node)" >/dev/null
do_preflight_registry_tls >/dev/null; _rc=$?
PATH="$_saved_path"
[ "$_rc" = "0" ] && ok "tls probe: auto-repair path continues" || no "tls probe: repair rc=$_rc"
expect_log "brew postinstall openssl@3" "tls probe: brew postinstall openssl@3 invoked"
case "${STEP_RECORDS[0]:-}" in
  warn\|prereq\|*auto-repaired*) ok "tls probe: repair recorded as warn note" ;;
  *) no "tls probe: expected warn/auto-repaired (got: ${STEP_RECORDS[0]:-none})" ;;
esac

# Cert failure, repair does NOT work → hard exit 2 (subshell)
rm -f "$SBX/repaired"
cat > "${BIN}/node" <<EOF
#!/bin/bash
echo "node \$*" >> "$LOG"
echo "UNABLE_TO_GET_ISSUER_CERT_LOCALLY" >&2
exit 1
EOF
chmod +x "${BIN}/node"
: > "$LOG"
_saved_path="$PATH"; PATH="$BIN:/usr/bin:/bin"
( step_start "registry TLS (node)" >/dev/null; do_preflight_registry_tls >/dev/null 2>&1 ); _rc=$?
PATH="$_saved_path"
[ "$_rc" = "2" ] && ok "tls probe: unrepaired cert store exits 2" || no "tls probe: want exit 2, got $_rc"

# Non-cert probe failure (DNS) → warn and continue
cat > "${BIN}/node" <<EOF
#!/bin/bash
echo "node \$*" >> "$LOG"
echo "getaddrinfo ENOTFOUND registry.npmjs.org" >&2
exit 1
EOF
chmod +x "${BIN}/node"
: > "$LOG"; STEP_RECORDS=()
_saved_path="$PATH"; PATH="$BIN:/usr/bin:/bin"
step_start "registry TLS (node)" >/dev/null
do_preflight_registry_tls >/dev/null; _rc=$?
PATH="$_saved_path"
[ "$_rc" = "0" ] && ok "tls probe: net-class failure continues" || no "tls probe: net rc=$_rc"
grep -q '^brew postinstall' "$LOG" && no "tls probe: net class must not postinstall" \
  || ok "tls probe: no postinstall on net class"

# ---------- F2: native-installer fallback ----------
# npm succeeds → curl never called
cat > "${BIN}/npm" <<EOF
#!/bin/bash
echo "npm \$*" >> "$LOG"
exit 0
EOF
cat > "${BIN}/curl" <<EOF
#!/bin/bash
echo "curl \$*" >> "$LOG"
exit 0
EOF
cat > "${BIN}/claude" <<EOF
#!/bin/bash
echo "2.0.0 (mock)"
EOF
chmod +x "${BIN}/npm" "${BIN}/curl" "${BIN}/claude"
: > "$LOG"; STEP_RECORDS=()
# claude "absent" first: run with claude mock removed, npm present
mv "${BIN}/claude" "${BIN}/claude.hidden"
_saved_path="$PATH"; PATH="$BIN:/usr/bin:/bin"; _saved_home="$HOME"; HOME="$SBX"
step_start "claude CLI" >/dev/null
RETRY_MAX=1 do_preflight_claude_cli >/dev/null; _rc=$?
HOME="$_saved_home"; PATH="$_saved_path"
[ "$_rc" = "0" ] && ok "claude cli: npm channel ok" || no "claude cli: npm rc=$_rc"
expect_log "npm install -g @anthropic-ai/claude-code@latest" "claude cli: npm channel attempted"
grep -q '^curl' "$LOG" && no "claude cli: curl must not run when npm succeeds" \
  || ok "claude cli: native not invoked on npm success"

# npm fails → native invoked; native "succeeds" by dropping ~/.local/bin/claude
cat > "${BIN}/npm" <<EOF
#!/bin/bash
echo "npm \$*" >> "$LOG"
echo "npm error code UNABLE_TO_GET_ISSUER_CERT_LOCALLY" >&2
exit 1
EOF
cat > "${BIN}/curl" <<EOF
#!/bin/bash
echo "curl \$*" >> "$LOG"
mkdir -p "$SBX/.local/bin"
printf '#!/bin/bash\necho 2.0.0\n' > "$SBX/.local/bin/claude"
chmod +x "$SBX/.local/bin/claude"
echo "echo native-installer-ran"
EOF
chmod +x "${BIN}/npm" "${BIN}/curl"
rm -rf "$SBX/.local"; : > "$LOG"; STEP_RECORDS=()
_saved_path="$PATH"; PATH="$BIN:/usr/bin:/bin"; _saved_home="$HOME"; HOME="$SBX"
step_start "claude CLI" >/dev/null
RETRY_MAX=1 do_preflight_claude_cli >/dev/null; _rc=$?
_path_after_call="$PATH"
HOME="$_saved_home"; PATH="$_saved_path"
[ "$_rc" = "0" ] && ok "claude cli: native fallback succeeds" || no "claude cli: fallback rc=$_rc"
grep -q '^curl -fsSL https://claude.ai/install.sh' "$LOG" \
  && ok "claude cli: native installer invoked on npm failure" \
  || no "claude cli: native installer not invoked"
case "${STEP_RECORDS[0]:-}" in
  ok\|prereq\|*native\ installer*) ok "claude cli: channel named in record" ;;
  *) no "claude cli: expected native-installer note (got: ${STEP_RECORDS[0]:-none})" ;;
esac
# D1: downstream steps (plugin/MCP registration) invoke `claude` by name, so a
# native-only success must leave ~/.local/bin on PATH, not just pass -x.
case ":$_path_after_call:" in
  *":$SBX/.local/bin:"*) ok "claude cli: PATH gains ~/.local/bin after native-only success (D1)" ;;
  *) no "claude cli: PATH missing ~/.local/bin after native-only success (D1): $_path_after_call" ;;
esac

# both fail → exit 2, message names both channels + cert hint
cat > "${BIN}/curl" <<EOF
#!/bin/bash
echo "curl \$*" >> "$LOG"
exit 1
EOF
chmod +x "${BIN}/curl"
rm -rf "$SBX/.local"; : > "$LOG"
_saved_path="$PATH"; PATH="$BIN:/usr/bin:/bin"; _saved_home="$HOME"; HOME="$SBX"
_out="$( step_start "claude CLI" >/dev/null; RETRY_MAX=1 do_preflight_claude_cli 2>&1 )"; _rc=$?
HOME="$_saved_home"; PATH="$_saved_path"
[ "$_rc" = "2" ] && ok "claude cli: both channels dead exits 2" || no "claude cli: want 2, got $_rc"
printf '%s' "$_out" | grep -q 'npm install -g @anthropic-ai/claude-code@latest' \
  && ok "claude cli: exit message names npm path" || no "claude cli: npm path missing from message"
printf '%s' "$_out" | grep -q 'claude.ai/install.sh' \
  && ok "claude cli: exit message names native path" || no "claude cli: native path missing"
printf '%s' "$_out" | grep -q 'brew postinstall openssl@3' \
  && ok "claude cli: exit message carries classified cert hint" || no "claude cli: cert hint missing"

# D2: npm absent — a stale global RUN_ERR left over from an unrelated prior
# run_retry (e.g. node's brew install) must not be misattributed as the
# npm-channel failure reason when npm was never invoked at all.
mv "${BIN}/npm" "${BIN}/npm.hidden"
rm -rf "$SBX/.local"; : > "$LOG"
RUN_ERR="stale brew noise"
_saved_path="$PATH"; PATH="$BIN:/usr/bin:/bin"; _saved_home="$HOME"; HOME="$SBX"
_out="$( step_start "claude CLI" >/dev/null; RETRY_MAX=1 do_preflight_claude_cli 2>&1 )"; _rc=$?
HOME="$_saved_home"; PATH="$_saved_path"
mv "${BIN}/npm.hidden" "${BIN}/npm"
[ "$_rc" = "2" ] && ok "claude cli: npm-absent both-channels-dead exits 2 (D2)" || no "claude cli: want 2, got $_rc (D2)"
printf '%s' "$_out" | grep -q 'stale brew noise' \
  && no "claude cli: exit message misattributed stale RUN_ERR as npm-channel reason (D2)" \
  || ok "claude cli: exit message does not leak stale RUN_ERR (D2)"
printf '%s' "$_out" | grep -qi 'npm unavailable' \
  && ok "claude cli: npm-channel line honestly reflects unavailability (D2)" \
  || no "claude cli: exit message does not say npm is unavailable (D2): $_out"

# ---------- F6: run log init + rotation ----------
_saved_home="$HOME"; HOME="$SBX"
rm -rf "$SBX/.claude"
( set -euo pipefail; _init_run_log; echo "hello ${C_RED}red${C_RESET} world"; echo "survived-rotation" >> "$SBX/marker"; sleep 0.2 ) >/dev/null 2>&1
[ -f "$SBX/marker" ] && ok "runlog: survives empty log dir under set -euo pipefail" || no "runlog: died in rotation pipeline (set -e)"
_logfile="$(ls "$SBX/.claude/logs"/bootstrap-*.log 2>/dev/null | head -1)"
[ -n "$_logfile" ] && ok "runlog: log file created under ~/.claude/logs" || no "runlog: no log file"
grep -q 'hello red world' "$_logfile" 2>/dev/null \
  && ok "runlog: content captured with ANSI stripped" || no "runlog: content/strip failed"

# rotation: 7 pre-existing logs + this run → 5 remain
rm -rf "$SBX/.claude/logs"; mkdir -p "$SBX/.claude/logs"
for i in 1 2 3 4 5 6 7; do
  touch -t "2026010${i}0000" "$SBX/.claude/logs/bootstrap-2026010${i}T000000Z.log"
done
( set -euo pipefail; _init_run_log; sleep 0.2 ) >/dev/null 2>&1
_count="$(ls "$SBX/.claude/logs"/bootstrap-*.log | wc -l | tr -d ' ')"
[ "$_count" = "5" ] && ok "runlog: rotation keeps 5" || no "runlog: rotation kept $_count, want 5"

# unwritable dir → disabled, no crash
rm -rf "$SBX/.claude"; mkdir -p "$SBX/.claude"; chmod a-w "$SBX/.claude"
( _init_run_log ) >/dev/null 2>&1; _rc=$?
chmod u+w "$SBX/.claude"
[ "$_rc" = "0" ] && ok "runlog: unwritable dir degrades gracefully" || no "runlog: rc=$_rc"
HOME="$_saved_home"

# ---------- AC-7: Global hooks — MANAGED_HOOKS registration + old-name cleanup ----------
# do_install_hooks (file management: install / orphan-removal / manifest) and
# wire_managed_hooks (settings.json registration) are extracted fresh from the
# real script — same convention as the Resilience block above — so this stays
# in lockstep with the real code. The orphan-removal is generic (driven by
# "what's in the repo's hooks/ dir", not by name): epic-15's rename from
# kill-guard.sh/kill-check.sh to stop-guard.sh/stop-check.sh needs no
# special-case code, only proof that the generic mechanism actually removes
# the old names once planted (restart-handoff's named open question).
HOOKS_CODE="${SBX}/hooks_code.sh"
: > "$HOOKS_CODE"
for fn in do_install_hooks wire_managed_hooks; do
  awk -v fn="$fn" '$0 ~ "^"fn"\\(\\) \\{"{f=1} f{print} f&&/^\}$/{exit}' "$BOOTSTRAP" >> "$HOOKS_CODE"
done
awk '/^MANAGED_HOOKS=\(/{f=1} f{print} f&&/^\)$/{exit}' "$BOOTSTRAP" >> "$HOOKS_CODE"
# shellcheck disable=SC1090
source "$HOOKS_CODE"

HOOKSBX="${SBX}/hooks-sandbox"
mkdir -p "${HOOKSBX}/home/.claude/hooks"
# Plant old-name files simulating a real prior install.
printf '#!/bin/bash\necho old-kill-guard\n' > "${HOOKSBX}/home/.claude/hooks/kill-guard.sh"
printf '#!/bin/bash\necho old-kill-check\n' > "${HOOKSBX}/home/.claude/hooks/kill-check.sh"
chmod +x "${HOOKSBX}/home/.claude/hooks/kill-guard.sh" "${HOOKSBX}/home/.claude/hooks/kill-check.sh"

HOOKS_SETTINGS="${HOOKSBX}/home/.claude/settings.json"
echo '{}' > "$HOOKS_SETTINGS"

( export SCRIPT_DIR="$REPO" HOME="${HOOKSBX}/home"
  settings="$HOOKS_SETTINGS"
  do_install_hooks
  wire_managed_hooks ) >/dev/null
_hooks_rc=$?
[ "$_hooks_rc" -eq 0 ] && ok "AC-7: do_install_hooks + wire_managed_hooks run cleanly against a sandboxed HOME" \
  || no "AC-7: hook install run failed (rc=$_hooks_rc)"

# Old-name orphans removed.
[ ! -f "${HOOKSBX}/home/.claude/hooks/kill-guard.sh" ] && ok "AC-7: old-name kill-guard.sh removed" || no "AC-7: kill-guard.sh still present"
[ ! -f "${HOOKSBX}/home/.claude/hooks/kill-check.sh" ] && ok "AC-7: old-name kill-check.sh removed" || no "AC-7: kill-check.sh still present"

# New-name files present, executable, byte-identical to the repo copies.
for h in dispatch-preflight.sh preflight-probe.sh stop-check.sh stop-guard.sh execution-recorder.sh; do
  installed="${HOOKSBX}/home/.claude/hooks/${h}"
  [ -f "$installed" ] && ok "AC-7: ${h} installed" || no "AC-7: ${h} not installed"
  [ -x "$installed" ] && ok "AC-7: ${h} is executable" || no "AC-7: ${h} not executable"
  diff -q "${REPO}/hooks/${h}" "$installed" >/dev/null 2>&1 \
    && ok "AC-7: ${h} byte-identical to repo copy" || no "AC-7: ${h} differs from repo copy"
done

# dispatch-preflight.sh (PreToolUse|Agent), stop-guard.sh (PreToolUse|TaskStop)
# and execution-recorder.sh (PostToolUse|Bash + PostToolUse|Agent) moved out of
# MANAGED_HOOKS into skills/canonical-sdlc/SKILL.md's `hooks:` frontmatter
# (session-20260814-wave-detector-terminal-state, R1): wire_managed_hooks no
# longer writes any of these four registrations into settings.json at all —
# they now bind only for the duration of a session that invokes
# /canonical-sdlc. The four checks below assert both sides: absent from the
# wired settings this sandboxed run produces (that's the point of the move),
# present in the SKILL.md frontmatter block.
# stop-guard.sh's PreToolUse|Bash registration was separately RETIRED at
# wave-03 slice 4/4 when the recorder moved to its own PostToolUse script; the
# negative row below pins that unrelated retirement, because MANAGED_HOOKS is
# convergent and a leftover entry would put a second writer back in front of
# the same state file.
_matcher_has_cmd() {  # <event> <matcher> <cmd>
  jq -e --arg ev "$1" --arg m "$2" --arg c "$3" \
    '(.hooks[$ev] // []) | any(.matcher == $m and (.hooks | any(.command == $c)))' \
    "$HOOKS_SETTINGS" >/dev/null
}
SKILL_MD="${REPO}/skills/canonical-sdlc/SKILL.md"
_skill_frontmatter_has() {  # <event> <matcher> <cmd>
  awk -v want_event="$1" -v want_matcher="$2" -v want_cmd="$3" '
    /^hooks:$/ { active=1; next }
    active && /^---$/ { active=0 }
    active && /^[A-Za-z]/ { active=0 }
    !active { next }
    /^  [A-Za-z]+:$/ { event=$0; sub(/^  /,"",event); sub(/:$/,"",event); matcher=""; next }
    /^    - matcher: "/ { matcher=$0; sub(/^    - matcher: "/,"",matcher); sub(/"$/,"",matcher); next }
    /^          command: / {
      cmd=$0; sub(/^          command: /,"",cmd)
      if (event == want_event && matcher == want_matcher && cmd == want_cmd) found=1
    }
    END { exit !found }
  ' "$SKILL_MD"
}
_matcher_has_cmd PreToolUse Bash "~/.claude/hooks/stop-guard.sh" \
  && no "AC-7: stop-guard.sh still registered on PreToolUse|Bash (retired at 4/4)" \
  || ok "AC-7: stop-guard.sh is NOT registered on PreToolUse|Bash (recorder arm retired)"

_matcher_has_cmd PostToolUse Bash "~/.claude/hooks/execution-recorder.sh" \
  && no "AC-7: execution-recorder.sh still wired to PostToolUse|Bash (should have moved to SKILL.md frontmatter)" \
  || ok "AC-7: execution-recorder.sh NOT wired to PostToolUse|Bash (sdlc-scoped, frontmatter-only now)"
_skill_frontmatter_has PostToolUse Bash "~/.claude/hooks/execution-recorder.sh" \
  && ok "AC-7: SKILL.md frontmatter registers execution-recorder.sh on PostToolUse|Bash" \
  || no "AC-7: SKILL.md frontmatter missing execution-recorder.sh on PostToolUse|Bash"

_matcher_has_cmd PostToolUse Agent "~/.claude/hooks/execution-recorder.sh" \
  && no "AC-7: execution-recorder.sh still wired to PostToolUse|Agent (should have moved to SKILL.md frontmatter)" \
  || ok "AC-7: execution-recorder.sh NOT wired to PostToolUse|Agent (sdlc-scoped, frontmatter-only now)"
_skill_frontmatter_has PostToolUse Agent "~/.claude/hooks/execution-recorder.sh" \
  && ok "AC-7: SKILL.md frontmatter registers execution-recorder.sh on PostToolUse|Agent" \
  || no "AC-7: SKILL.md frontmatter missing execution-recorder.sh on PostToolUse|Agent"

_matcher_has_cmd PreToolUse TaskStop "~/.claude/hooks/stop-guard.sh" \
  && no "AC-7: stop-guard.sh still wired to PreToolUse|TaskStop (should have moved to SKILL.md frontmatter)" \
  || ok "AC-7: stop-guard.sh NOT wired to PreToolUse|TaskStop (sdlc-scoped, frontmatter-only now)"
_skill_frontmatter_has PreToolUse TaskStop "~/.claude/hooks/stop-guard.sh" \
  && ok "AC-7: SKILL.md frontmatter registers stop-guard.sh on PreToolUse|TaskStop" \
  || no "AC-7: SKILL.md frontmatter missing stop-guard.sh on PreToolUse|TaskStop"

_matcher_has_cmd PreToolUse Agent "~/.claude/hooks/dispatch-preflight.sh" \
  && no "AC-7: dispatch-preflight.sh still wired to PreToolUse|Agent (should have moved to SKILL.md frontmatter)" \
  || ok "AC-7: dispatch-preflight.sh NOT wired to PreToolUse|Agent (sdlc-scoped, frontmatter-only now)"
_skill_frontmatter_has PreToolUse Agent "~/.claude/hooks/dispatch-preflight.sh" \
  && ok "AC-7: SKILL.md frontmatter registers dispatch-preflight.sh on PreToolUse|Agent" \
  || no "AC-7: SKILL.md frontmatter missing dispatch-preflight.sh on PreToolUse|Agent"

# farm-out-reminder.sh (PreToolUse|Bash) moved out of MANAGED_HOOKS into the SKILL.md
# frontmatter at session-20260815-landing-supervision T5 (AC-6): unlike the four
# checks above, it does NOT come back guarded — it guards a workflow preference
# rather than irreversible damage, so armed-session-only coverage is the whole
# story, no agent-context twin needed.
_matcher_has_cmd PreToolUse Bash "~/.claude/hooks/farm-out-reminder.sh" \
  && no "AC-7: farm-out-reminder.sh still wired to PreToolUse|Bash (should have moved to SKILL.md frontmatter)" \
  || ok "AC-7: farm-out-reminder.sh NOT wired to PreToolUse|Bash (armed-session-scoped, frontmatter-only now)"
_skill_frontmatter_has PreToolUse Bash "~/.claude/hooks/farm-out-reminder.sh" \
  && ok "AC-7: SKILL.md frontmatter registers farm-out-reminder.sh on PreToolUse|Bash" \
  || no "AC-7: SKILL.md frontmatter missing farm-out-reminder.sh on PreToolUse|Bash"

# preflight-probe.sh and stop-check.sh are installed but stay UNREGISTERED
# (companion scripts, run by hand — never appear as a hooks[].command anywhere).
for companion in preflight-probe.sh stop-check.sh; do
  cnt="$(jq --arg c "~/.claude/hooks/${companion}" '[.hooks[]? | .[] | .hooks[]? | select(.command == $c)] | length' "$HOOKS_SETTINGS")"
  [ "$cnt" = "0" ] && ok "AC-7: ${companion} installed unregistered (companion script)" || no "AC-7: ${companion} unexpectedly registered (${cnt} entries)"
done

# Registration count matches MANAGED_HOOKS exactly — nothing dropped, nothing
# duplicated.
_total_registered="$(jq '[.hooks[]? | .[] | .hooks[]?] | length' "$HOOKS_SETTINGS")"
[ "$_total_registered" = "${#MANAGED_HOOKS[@]}" ] \
  && ok "AC-7: settings.json registration count matches MANAGED_HOOKS (${#MANAGED_HOOKS[@]})" \
  || no "AC-7: registration count ${_total_registered}, want ${#MANAGED_HOOKS[@]}"

# Manifest lists the new names and excludes the removed old names.
manifest="${HOOKSBX}/home/.claude/hooks/.bionic-manifest"
for h in dispatch-preflight.sh preflight-probe.sh stop-check.sh stop-guard.sh execution-recorder.sh; do
  grep -qxF "$h" "$manifest" 2>/dev/null && ok "AC-7: manifest lists ${h}" || no "AC-7: manifest missing ${h}"
done
grep -qxF "kill-guard.sh" "$manifest" 2>/dev/null && no "AC-7: manifest must not list removed old name kill-guard.sh" || ok "AC-7: manifest excludes kill-guard.sh"
grep -qxF "kill-check.sh" "$manifest" 2>/dev/null && no "AC-7: manifest must not list removed old name kill-check.sh" || ok "AC-7: manifest excludes kill-check.sh"

echo "========================================"
echo "Installer behavior: ${PASS} passed, ${FAIL} failed"
echo "========================================"
[ "$FAIL" -eq 0 ]
