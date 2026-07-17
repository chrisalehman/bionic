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
for fn in do_install_brew_cask do_install_pnpm_store _pw_satisfied _pw_lock_preflight _playwright_install do_install_playwright_chromium _excalidraw_dry_run _excalidraw_setup do_setup_excalidraw_renderer _pw_link_demands _pw_component_dir _pw_link_missing _pw_heal_node _pw_heal_one do_heal_playwright_registry verify_playwright_registry; do
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

echo "========================================"
echo "Installer behavior: ${PASS} passed, ${FAIL} failed"
echo "========================================"
[ "$FAIL" -eq 0 ]
