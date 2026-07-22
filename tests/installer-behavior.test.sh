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
for fn in do_install_brew_cask do_install_pnpm_store _pw_satisfied _pw_lock_preflight _playwright_install do_install_playwright_chromium _excalidraw_dry_run _excalidraw_setup do_setup_excalidraw_renderer _pw_link_demands _pw_component_dir _pw_link_missing _pw_heal_node _pw_heal_one do_heal_playwright_registry verify_playwright_registry do_install_agents _cron_env_mode _gen_ntfy_topic _cron_shape_issues do_author_cron_env do_verify_cron_env do_register_poker_cron do_preflight_node _node_probe do_preflight_registry_tls do_preflight_claude_cli; do
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

# 18) Cron registration (C7) + cron.env verification (C6) + reset removal.
# The crontab is exercised against a PATH-shadowed stub that stores stdin to a
# file and serves `crontab -l` from it (exiting 1 on an absent store, exactly
# like a real empty crontab). No real crontab is ever touched. cron.env
# verification runs against a controlled fake $HOME so no real file is read or
# written.
CRONFILE="${SBX}/crontab.store"
CRONLOG="${SBX}/crontab.args.log"
cat > "${BIN}/crontab" <<EOF
#!/bin/bash
echo "crontab \$*" >> "$CRONLOG"
case "\$1" in
  -l) if [ -f "$CRONFILE" ]; then cat "$CRONFILE"; else exit 1; fi ;;
  -r) rm -f "$CRONFILE" ;;
  -)  cat > "$CRONFILE" ;;
  *)  exit 2 ;;
esac
EOF
chmod +x "${BIN}/crontab"
# A resolvable `claude` so the registration probe records a path (C7).
cat > "${BIN}/claude" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "${BIN}/claude"

# The exact entry C7 mandates — asserted byte-for-byte against what the
# installer writes. $HOME stays literal (cron expands it at run time).
EXPECTED_CRON='*/3 * * * * PATH=/opt/homebrew/bin:/usr/bin:/bin /bin/sh -c '\''. "$HOME/.claude/cron.env" && "$HOME/.claude/hooks/sdlc-poker.sh" >> "$HOME/.claude/sdlc-poker.log" 2>&1'\'' # BIONIC-SDLC-POKER'
CRON_MARKER="# BIONIC-SDLC-POKER"

# 18/9) 127-guard: every new function was actually extracted (a missing callee
# would `command not found` silently — this catches an omission from the
# `for fn in` list at the top of this file).
for fn in _cron_env_mode _gen_ntfy_topic _cron_shape_issues do_author_cron_env do_verify_cron_env do_register_poker_cron; do
  if declare -F "$fn" >/dev/null; then ok "extracted for test: ${fn}"; else no "127-guard: ${fn} not extracted (add it to the 'for fn in' list)"; fi
done

# 18/1) empty crontab (crontab -l exits 1) → entry installed, exit 0.
rm -f "$CRONFILE"; : > "$CRONLOG"; INSTALL_FAILURES=()
do_register_poker_cron >/dev/null; rc=$?
[ "$rc" -eq 0 ] && ok "register returns 0 on an empty crontab" || no "register non-zero on empty crontab (rc=$rc)"
grep -qxF "$EXPECTED_CRON" "$CRONFILE" && ok "18/1 empty crontab: exact C7 entry written" || no "18/1 entry mismatch: $(cat "$CRONFILE" 2>/dev/null)"
[ "$(grep -cF "$CRON_MARKER" "$CRONFILE")" -eq 1 ] && ok "18/1 exactly one marker line" || no "18/1 marker count wrong"
grep -qxF "crontab -l" "$CRONLOG" && ok "18/1 read the current crontab via crontab -l" || no "18/1 did not probe crontab -l"

# 18/1b) crontab binary absent on the host → skip (NOT fail): the poker relay
# degrades gracefully rather than failing a clean bootstrap. Run under a PATH
# with no crontab (only `date`, which step_start needs); the subshell writes
# its INSTALL_FAILURES count + last STEP_RECORDS entry out since neither
# propagates from a subshell.
CRONLESS="${SBX}/cronless"; mkdir -p "$CRONLESS"
ln -s "$(command -v date)" "${CRONLESS}/date" 2>/dev/null || true
_skip_out="${SBX}/cronless-skip.txt"
( PATH="$CRONLESS"; STEP_RECORDS=(); INSTALL_FAILURES=()
  do_register_poker_cron >/dev/null 2>&1
  printf '%s\n' "${#INSTALL_FAILURES[@]}" "${STEP_RECORDS[*]: -1}" > "$_skip_out" )
{ read -r _nfail; read -r _rec; } < "$_skip_out"
[ "$_nfail" = "0" ] && ok "18/1b crontab-absent host records no install failure" || no "18/1b crontab-absent recorded a failure (${_nfail})"
case "$_rec" in skip*) ok "18/1b crontab-absent → skip status (graceful degradation)";; *) no "18/1b crontab-absent status wrong: ${_rec}";; esac

# 18/2) double-bootstrap → still exactly one marker line (idempotent), and the
# second run detects no change (cached, no crontab write).
: > "$CRONLOG"; INSTALL_FAILURES=(); STEP_RECORDS=()
do_register_poker_cron >/dev/null
[ "$(grep -cF "$CRON_MARKER" "$CRONFILE")" -eq 1 ] && ok "18/2 double-bootstrap keeps exactly one marker line" || no "18/2 duplicate marker lines"
if grep -qxF "crontab -" "$CRONLOG"; then no "18/2 idempotent re-run must not rewrite the crontab"; else ok "18/2 idempotent re-run does not rewrite the crontab"; fi
[ "${STEP_RECORDS[*]: -1}" != "" ] && case "${STEP_RECORDS[${#STEP_RECORDS[@]}-1]}" in cached*) ok "18/2 re-run records a cached step";; *) no "18/2 re-run not cached: ${STEP_RECORDS[${#STEP_RECORDS[@]}-1]}";; esac

# 18/3) marker present but entry text differs → replaced in place.
printf 'OLD BROKEN POKER LINE # BIONIC-SDLC-POKER\n' > "$CRONFILE"
: > "$CRONLOG"; INSTALL_FAILURES=()
do_register_poker_cron >/dev/null
grep -qxF "$EXPECTED_CRON" "$CRONFILE" && ok "18/3 stale marker line replaced with the C7 entry" || no "18/3 entry not replaced: $(cat "$CRONFILE")"
grep -q "OLD BROKEN POKER LINE" "$CRONFILE" && no "18/3 stale entry must be gone" || ok "18/3 stale entry removed"
[ "$(grep -cF "$CRON_MARKER" "$CRONFILE")" -eq 1 ] && ok "18/3 replace leaves exactly one marker line" || no "18/3 marker count wrong after replace"

# 18/4) foreign entries survive install byte-identical.
FOREIGN_A='0 9 * * * /usr/bin/foreign-job --flag "arg with spaces"'
FOREIGN_B='@reboot /opt/thing/start.sh'
printf '%s\n%s\n' "$FOREIGN_A" "$FOREIGN_B" > "$CRONFILE"
: > "$CRONLOG"; INSTALL_FAILURES=()
do_register_poker_cron >/dev/null
grep -qxF "$FOREIGN_A" "$CRONFILE" && ok "18/4 foreign entry A survives install byte-identical" || no "18/4 foreign A mangled"
grep -qxF "$FOREIGN_B" "$CRONFILE" && ok "18/4 foreign entry B survives install byte-identical" || no "18/4 foreign B mangled"
grep -qxF "$EXPECTED_CRON" "$CRONFILE" && ok "18/4 poker entry appended alongside foreign entries" || no "18/4 poker entry missing"

# 18/8) errexit regression: bare `crontab -l` exits 1 on the no-crontab path;
# the register must not abort under `set -e` (subshell round-trip).
rm -f "$CRONFILE"
if (set -e; do_register_poker_cron >/dev/null); then ok "18/8 register survives set -e on the empty-crontab path" || true; else no "18/8 register aborted under set -e (unguarded crontab -l exit 1)"; fi
grep -qxF "$EXPECTED_CRON" "$CRONFILE" && ok "18/8 entry still installed on the set -e path" || no "18/8 entry not installed under set -e"

# 18/5) reset removes ONLY the marker line; foreign entries survive byte-
# identical. Extract do_remove_poker_cron from claude-reset.sh and stub its
# reset-only helpers (confirm/note_*) so it runs in this sandbox.
confirm() { return 0; }
note_removed() { :; }
note_clean() { :; }
note_skipped() { :; }
RESET_CODE="${SBX}/reset_code.sh"
awk '$0 ~ "^do_remove_poker_cron\\(\\) \\{"{f=1} f{print} f&&/^\}$/{exit}' "${REPO}/claude-reset.sh" > "$RESET_CODE"
if declare -F do_remove_poker_cron >/dev/null; then unset -f do_remove_poker_cron; fi
# shellcheck disable=SC1090
source "$RESET_CODE"
if declare -F do_remove_poker_cron >/dev/null; then ok "18/5 do_remove_poker_cron extracted from claude-reset.sh" || true; else no "18/5 do_remove_poker_cron not extracted from claude-reset.sh"; fi

# Install into a crontab that also carries foreign entries, then reset.
printf '%s\n%s\n' "$FOREIGN_A" "$FOREIGN_B" > "$CRONFILE"
do_register_poker_cron >/dev/null
: > "$CRONLOG"
do_remove_poker_cron >/dev/null
grep -qF "$CRON_MARKER" "$CRONFILE" && no "18/5 reset must remove the marker line" || ok "18/5 reset removes the marker line"
grep -qxF "$FOREIGN_A" "$CRONFILE" && ok "18/5 foreign entry A survives reset byte-identical" || no "18/5 reset mangled foreign A"
grep -qxF "$FOREIGN_B" "$CRONFILE" && ok "18/5 foreign entry B survives reset byte-identical" || no "18/5 reset mangled foreign B"

# 18/5b) reset on a crontab whose ONLY entry is the marker clears it entirely.
rm -f "$CRONFILE"
do_register_poker_cron >/dev/null
do_remove_poker_cron >/dev/null
if [ ! -f "$CRONFILE" ] || ! grep -qF "$CRON_MARKER" "${CRONFILE}"; then ok "18/5b reset of a poker-only crontab leaves no marker"; else no "18/5b marker survived reset"; fi

# 18/5c) reset when the marker is already absent → clean no-op (foreign intact).
printf '%s\n' "$FOREIGN_A" > "$CRONFILE"
: > "$CRONLOG"
do_remove_poker_cron >/dev/null
grep -qxF "$FOREIGN_A" "$CRONFILE" && ok "18/5c reset no-op leaves an unrelated crontab intact" || no "18/5c reset damaged an unrelated crontab"

# ---- cron.env verification (C6) under a controlled fake HOME ----
CRONHOME="${SBX}/cronhome"; mkdir -p "${CRONHOME}/.claude"
_OLD_HOME="$HOME"; export HOME="$CRONHOME"

# A well-shaped OAuth token used by the passing-shape fixtures: sk-ant prefix,
# in the 40–512 length band, no whitespace. The distinctive `VERIFYOK` marker
# doubles as a leak canary (grep it absent from any captured output).
VALID_TOK="sk-ant-oat01-VERIFYOK$(printf '0%.0s' {1..80})"

# 18/6) env file absent → skip (NOT fail): warning names `claude setup-token`
# and BOTH key names; no INSTALL_FAILURES; the file is never created.
rm -f "${CRONHOME}/.claude/cron.env"
STEP_RECORDS=(); INSTALL_FAILURES=()
do_verify_cron_env >/dev/null
rec="${STEP_RECORDS[*]: -1}"
IFS='|' read -r c_st c_cat c_sec c_name c_rem c_det <<< "$rec"
[ "$c_st" = "skip" ] && ok "18/6 absent cron.env → skip status (provisioning gap, not a failure)" || no "18/6 absent status wrong: $c_st"
[ "${#INSTALL_FAILURES[@]}" -eq 0 ] && ok "18/6 absent cron.env records no install failure (resilience)" || no "18/6 absent wrongly recorded a failure"
case "$c_rem" in *"claude setup-token"*) ok "18/6 warning names 'claude setup-token'";; *) no "18/6 remediation missing setup-token: $c_rem";; esac
case "$c_rem" in *CLAUDE_CODE_OAUTH_TOKEN*BIONIC_NTFY_TOPIC*) ok "18/6 warning names both key names";; *) no "18/6 remediation missing a key name: $c_rem";; esac
[ ! -f "${CRONHOME}/.claude/cron.env" ] && ok "18/6 verification never creates the env file" || no "18/6 env file was created (machinery must never write it)"

# 18/7a) mode 644 (both keys) → warn, no failure. Invoke directly (not in a
# command substitution) so the in-process STEP_RECORDS/INSTALL_FAILURES update.
printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\nBIONIC_NTFY_TOPIC=topic-secret-value\n' "$VALID_TOK" > "${CRONHOME}/.claude/cron.env"
chmod 644 "${CRONHOME}/.claude/cron.env"
STEP_RECORDS=(); INSTALL_FAILURES=()
do_verify_cron_env >/dev/null
rec="${STEP_RECORDS[*]: -1}"; IFS='|' read -r c_st c_cat c_sec c_name c_rem c_det <<< "$rec"
[ "$c_st" = "warn" ] && ok "18/7a mode 644 → warn status" || no "18/7a mode 644 status wrong: $c_st"
[ "${#INSTALL_FAILURES[@]}" -eq 0 ] && ok "18/7a mode 644 records no failure" || no "18/7a mode 644 wrongly failed"

# 18/7b) mode 600 + both keys → silent pass (step_ok), and NO secret value is
# ever printed to stdout/stderr (C6: values never printed). Status comes from a
# direct call; the leak check re-runs in a subshell purely to capture output.
chmod 600 "${CRONHOME}/.claude/cron.env"
STEP_RECORDS=(); INSTALL_FAILURES=()
do_verify_cron_env >/dev/null
rec="${STEP_RECORDS[*]: -1}"; IFS='|' read -r c_st c_cat c_sec c_name c_rem c_det <<< "$rec"
[ "$c_st" = "ok" ] && ok "18/7b mode 600 + both keys → ok status" || no "18/7b mode 600 status wrong: $c_st"
[ "${#INSTALL_FAILURES[@]}" -eq 0 ] && ok "18/7b mode 600 pass records no failure" || no "18/7b mode 600 wrongly failed"
verify_out="$(do_verify_cron_env 2>&1)"
if echo "$verify_out" | grep -q "VERIFYOK\|topic-secret-value"; then no "18/7b a secret VALUE leaked to output"; else ok "18/7b never prints a secret value"; fi

# 18/7c) mode 600 but a key missing → warn naming the missing key, no failure.
# (C6 amendment 3: in the LIVE flow do_author_cron_env runs BEFORE verify and
# ADDS a missing key line, so verify would see both keys. This case still
# exercises verify's own missing-key branch directly — author is not invoked.)
printf 'CLAUDE_CODE_OAUTH_TOKEN=tok-secret-value\n' > "${CRONHOME}/.claude/cron.env"
chmod 600 "${CRONHOME}/.claude/cron.env"
STEP_RECORDS=(); INSTALL_FAILURES=()
do_verify_cron_env >/dev/null
rec="${STEP_RECORDS[*]: -1}"; IFS='|' read -r c_st c_cat c_sec c_name c_rem c_det <<< "$rec"
[ "$c_st" = "warn" ] && ok "18/7c missing key → warn status" || no "18/7c missing-key status wrong: $c_st"
case "$c_det$c_rem" in *BIONIC_NTFY_TOPIC*) ok "18/7c warning names the missing key (BIONIC_NTFY_TOPIC)";; *) no "18/7c missing-key name absent: $c_det | $c_rem";; esac

# ---- token-shape verification (C6, walk-2 hardening) under the fake HOME ----
# do_verify_cron_env, having confirmed mode 600 + both key NAMES, now also
# vets the SHAPE of the values — WARN-only (never record_fail), and the value
# is NEVER printed. The raw KEY=VALUE line is parsed, never sourced, so a
# space-bearing value is DETECTED rather than word-split. A helper collects
# every recorded step so multi-warn cases can be asserted.
_shape_steps() { printf '%s\n' "${STEP_RECORDS[@]}"; }

# 18/7d) the walk-2 failure: a long (~2687-char) token carrying an EMBEDDED
# SPACE. Sourced, it word-splits and mangles the Bearer header. → a warn that
# names whitespace, NO step_ok, and the value never reaches stdout/stderr.
PLANTED_WS="sk-ant-oat01-LEAKCANARY7d $(printf 'z%.0s' {1..2650})"
printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\nBIONIC_NTFY_TOPIC=topic-ok\n' "$PLANTED_WS" > "${CRONHOME}/.claude/cron.env"
chmod 600 "${CRONHOME}/.claude/cron.env"
STEP_RECORDS=(); INSTALL_FAILURES=()
do_verify_cron_env >/dev/null
_shape_steps | grep -qi 'whitespace' && ok "18/7d space-bearing token → whitespace warn (naming the property)" || no "18/7d no whitespace warn recorded: $(_shape_steps)"
_shape_steps | grep -q '^ok|' && no "18/7d must not record step_ok on a malformed token" || ok "18/7d malformed token records no step_ok"
[ "${#INSTALL_FAILURES[@]}" -eq 0 ] && ok "18/7d shape warn records no install failure (warn-and-continue)" || no "18/7d wrongly recorded a failure"
_leak_out="$(do_verify_cron_env 2>&1)"
if printf '%s' "$_leak_out" | grep -qF "LEAKCANARY7d"; then no "18/7d token VALUE leaked to output"; else ok "18/7d space-bearing value absent from all captured output"; fi

# 18/7e) short garbage value ("hello"): wrong prefix AND out-of-band length →
# both properties warn, no step_ok.
printf 'CLAUDE_CODE_OAUTH_TOKEN=hello\nBIONIC_NTFY_TOPIC=topic-ok\n' > "${CRONHOME}/.claude/cron.env"
chmod 600 "${CRONHOME}/.claude/cron.env"
STEP_RECORDS=(); INSTALL_FAILURES=()
do_verify_cron_env >/dev/null
_shape_steps | grep -qi 'sk-ant' && ok "18/7e garbage token → prefix warn (names sk-ant expectation)" || no "18/7e no prefix warn: $(_shape_steps)"
_shape_steps | grep -qi 'length' && ok "18/7e garbage token → length warn" || no "18/7e no length warn: $(_shape_steps)"
_shape_steps | grep -q '^ok|' && no "18/7e must not record step_ok on a garbage token" || ok "18/7e garbage token records no step_ok"

# 18/7f) a valid-shaped token (sk-ant prefix, ~100 chars, no whitespace) →
# step_ok, exactly one record, NO shape warns. Regression guard so the added
# checks never bark on a well-formed credential (the prov/-era shape).
printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\nBIONIC_NTFY_TOPIC=topic-ok\n' "$VALID_TOK" > "${CRONHOME}/.claude/cron.env"
chmod 600 "${CRONHOME}/.claude/cron.env"
STEP_RECORDS=(); INSTALL_FAILURES=()
do_verify_cron_env >/dev/null
rec="${STEP_RECORDS[*]: -1}"; IFS='|' read -r c_st c_cat c_sec c_name c_rem c_det <<< "$rec"
[ "$c_st" = "ok" ] && ok "18/7f valid-shaped token → step_ok" || no "18/7f valid token status wrong: $c_st"
[ "${#STEP_RECORDS[@]}" -eq 1 ] && ok "18/7f valid token records no shape warn" || no "18/7f unexpected extra records: $(_shape_steps)"

# 18/7g) BIONIC_NTFY_TOPIC carrying whitespace (topics must be URL-path-safe) →
# warn naming the topic, no step_ok. The token itself is valid-shaped so the
# only complaint is the topic.
printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\nBIONIC_NTFY_TOPIC=has a space\n' "$VALID_TOK" > "${CRONHOME}/.claude/cron.env"
chmod 600 "${CRONHOME}/.claude/cron.env"
STEP_RECORDS=(); INSTALL_FAILURES=()
do_verify_cron_env >/dev/null
_shape_steps | grep -qi 'BIONIC_NTFY_TOPIC.*whitespace' && ok "18/7g whitespace in topic → warn naming BIONIC_NTFY_TOPIC" || no "18/7g no topic-whitespace warn: $(_shape_steps)"
_shape_steps | grep -q '^ok|' && no "18/7g must not record step_ok when the topic is malformed" || ok "18/7g malformed topic records no step_ok"

# 18/7h) errexit: the shape checks add grep in command-substitution; verify the
# function does not abort under set -e when the values are present and valid.
printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\nBIONIC_NTFY_TOPIC=topic-ok\n' "$VALID_TOK" > "${CRONHOME}/.claude/cron.env"
chmod 600 "${CRONHOME}/.claude/cron.env"
if (set -e; do_verify_cron_env >/dev/null 2>&1); then ok "18/7h shape verify survives set -e on the valid path" || true; else no "18/7h verify aborted under set -e"; fi

# ---- template authoring (C6 AMENDMENT 3 — FINAL) under the fake HOME ----
# Amendment 3 SUPERSEDES the interactive provision/repair flows entirely with a
# single NON-INTERACTIVE authoring pass — identical behavior attended,
# unattended, or in CI (no TTY checks, no CI checks, no prompts):
#   • file ABSENT  → author it (an EMPTY CLAUDE_CODE_OAUTH_TOKEN= slot the user
#     later pastes into, plus a machine-generated BIONIC_NTFY_TOPIC), mode 600,
#     atomic temp+mv under umask 077.
#   • file PRESENT → STRUCTURAL repair only: a MISSING key line is added; a line
#     that already exists is preserved BYTE-IDENTICAL, even if its value is
#     malformed (user-set values are never overwritten). Both keys present → a
#     no-op.
# Value SHAPE is never judged by authoring — that stays do_verify_cron_env's
# warn-only job, whose warns are the entire END-SUMMARY UX.
AUTH_F="${CRONHOME}/.claude/cron.env"
# The EXACT fill instruction the empty/malformed token warns carry as the →
# action line (spec §C6 amendment 3, verbatim).
FILL="run 'claude setup-token' and paste the value after CLAUDE_CODE_OAUTH_TOKEN= in ~/.claude/cron.env"
_auth_steps() { printf '%s\n' "${STEP_RECORDS[@]}"; }

# author/1) absent file → authored: exists, mode 600, the token slot line is
# EXACTLY `CLAUDE_CODE_OAUTH_TOKEN=` (empty — machinery writes no credential
# value), a generated bionic- topic, atomic (no temp file left behind).
rm -f "$AUTH_F" "${CRONHOME}/.claude/"cron.env.tmp.* 2>/dev/null || true
STEP_RECORDS=(); INSTALL_FAILURES=()
do_author_cron_env >/dev/null
[ -f "$AUTH_F" ] && ok "author/1 absent file → cron.env authored" || no "author/1 did not author the file"
[ "$(_cron_env_mode "$AUTH_F")" = "600" ] && ok "author/1 authored file is mode 600" || no "author/1 wrong mode: $(_cron_env_mode "$AUTH_F")"
grep -qxF 'CLAUDE_CODE_OAUTH_TOKEN=' "$AUTH_F" && ok "author/1 token slot authored EMPTY (no credential value written)" || no "author/1 token line not empty: $(sed 's/=.*/=<redacted>/' "$AUTH_F")"
_a1_topic="$(grep -m1 '^BIONIC_NTFY_TOPIC=' "$AUTH_F")"
case "$_a1_topic" in BIONIC_NTFY_TOPIC=bionic-?*) ok "author/1 topic generated (bionic- prefix, non-empty)";; *) no "author/1 topic wrong: $_a1_topic";; esac
_a1_leftover="$(find "${CRONHOME}/.claude" -maxdepth 1 -name 'cron.env.tmp.*' 2>/dev/null)"
[ -z "$_a1_leftover" ] && ok "author/1 atomic write leaves no temp file" || no "author/1 temp leftover: $_a1_leftover"
rec="${STEP_RECORDS[*]: -1}"; IFS='|' read -r a_st _ <<< "$rec"
[ "$a_st" = "ok" ] && ok "author/1 authoring records step_ok" || no "author/1 status wrong: $a_st ($rec)"
[ "${#INSTALL_FAILURES[@]}" -eq 0 ] && ok "author/1 authoring records no install failure" || no "author/1 wrongly recorded a failure"

# author/2) the authored file → do_verify_cron_env warns EMPTY-token (its own
# detected state, NOT length/prefix) with the EXACT fill instruction as the →
# action line; no step_ok, no install failure.
STEP_RECORDS=(); INSTALL_FAILURES=()
do_verify_cron_env >/dev/null
_auth_steps | grep -qi 'CLAUDE_CODE_OAUTH_TOKEN is empty' && ok "author/2 empty token → 'CLAUDE_CODE_OAUTH_TOKEN is empty' warn" || no "author/2 no empty-token warn: $(_auth_steps)"
_auth_steps | grep -qF "$FILL" && ok "author/2 empty-token warn carries the exact fill instruction" || no "author/2 fill instruction missing: $(_auth_steps)"
if _auth_steps | grep -qiE 'length|sk-ant'; then no "author/2 empty token must not also warn length/prefix (empty is its own state)"; else ok "author/2 empty token is its own state (no length/prefix warn)"; fi
if _auth_steps | grep -q '^ok|'; then no "author/2 must not record step_ok on an empty token"; else ok "author/2 empty token records no step_ok"; fi
[ "${#INSTALL_FAILURES[@]}" -eq 0 ] && ok "author/2 empty-token warn records no install failure" || no "author/2 wrongly recorded a failure"

# author/3) VALID user token + topic → author is a byte-identical no-op
# (structure complete), and verify → step_ok.
printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\nBIONIC_NTFY_TOPIC=bionic-keepme-abc123\n' "$VALID_TOK" > "$AUTH_F"
chmod 600 "$AUTH_F"
_a3_before="$(cat "$AUTH_F")"
STEP_RECORDS=(); INSTALL_FAILURES=()
do_author_cron_env >/dev/null
[ "$(cat "$AUTH_F")" = "$_a3_before" ] && ok "author/3 well-formed file → byte-identical no-op" || no "author/3 modified a well-formed file"
[ "${#STEP_RECORDS[@]}" -eq 0 ] && ok "author/3 no-op records no step" || no "author/3 recorded a step: ${STEP_RECORDS[*]}"
STEP_RECORDS=(); do_verify_cron_env >/dev/null
rec="${STEP_RECORDS[*]: -1}"; IFS='|' read -r v_st _ <<< "$rec"
[ "$v_st" = "ok" ] && ok "author/3 verify of a valid file → step_ok" || no "author/3 verify wrong: $v_st"

# author/4) token line MISSING but topic present → the empty token slot line is
# ADDED, the existing topic line survives BYTE-IDENTICAL, mode 600.
GOOD_TOPIC='BIONIC_NTFY_TOPIC=bionic-keepme-abcdef123456'
printf '%s\n' "$GOOD_TOPIC" > "$AUTH_F"
chmod 600 "$AUTH_F"
STEP_RECORDS=(); INSTALL_FAILURES=()
do_author_cron_env >/dev/null
grep -qxF 'CLAUDE_CODE_OAUTH_TOKEN=' "$AUTH_F" && ok "author/4 missing token slot added (empty)" || no "author/4 token slot not added: $(sed 's/=.*/=<redacted>/' "$AUTH_F")"
grep -qxF "$GOOD_TOPIC" "$AUTH_F" && ok "author/4 existing topic line preserved byte-identical" || no "author/4 topic mangled: $(grep '^BIONIC_NTFY_TOPIC=' "$AUTH_F")"
[ "$(_cron_env_mode "$AUTH_F")" = "600" ] && ok "author/4 repaired file is mode 600" || no "author/4 wrong mode: $(_cron_env_mode "$AUTH_F")"
[ "${#INSTALL_FAILURES[@]}" -eq 0 ] && ok "author/4 structural repair records no install failure" || no "author/4 wrongly recorded a failure"

# author/5) MALFORMED user token value (embedded spaces) → author does NOT touch
# it (the line exists, so its value is never overwritten): byte-identical. verify
# still WARNS on the bad shape (existing shape detection retained).
printf 'CLAUDE_CODE_OAUTH_TOKEN=bad token with spaces\n%s\n' "$GOOD_TOPIC" > "$AUTH_F"
chmod 600 "$AUTH_F"
_a5_before="$(cat "$AUTH_F")"
STEP_RECORDS=(); INSTALL_FAILURES=()
do_author_cron_env >/dev/null
[ "$(cat "$AUTH_F")" = "$_a5_before" ] && ok "author/5 malformed user value left byte-identical (never overwritten)" || no "author/5 overwrote a user value"
STEP_RECORDS=(); do_verify_cron_env >/dev/null
_auth_steps | grep -qi 'whitespace' && ok "author/5 verify still warns on the malformed token shape" || no "author/5 verify did not warn: $(_auth_steps)"

# author/6) double-run idempotence: authoring an already-authored file is a
# byte-identical no-op (second run produces identical bytes, records no step).
rm -f "$AUTH_F"
STEP_RECORDS=(); do_author_cron_env >/dev/null
_a6_first="$(cat "$AUTH_F")"
STEP_RECORDS=(); do_author_cron_env >/dev/null
[ "$(cat "$AUTH_F")" = "$_a6_first" ] && ok "author/6 second author run is byte-identical (idempotent)" || no "author/6 second run changed the file"
[ "${#STEP_RECORDS[@]}" -eq 0 ] && ok "author/6 idempotent re-run records no step" || no "author/6 re-run recorded a step: ${STEP_RECORDS[*]}"

# author/7) errexit: the author path (subshell temp+mv, command-substituted
# topic) must not abort under set -e — on BOTH the absent-file and the
# structural-repair branch.
rm -f "$AUTH_F"
if (set -e; do_author_cron_env >/dev/null 2>&1); then ok "author/7 author survives set -e on the absent-file path" || true; else no "author/7 author aborted under set -e (absent path)"; fi
printf '%s\n' "$GOOD_TOPIC" > "$AUTH_F"; chmod 600 "$AUTH_F"
if (set -e; do_author_cron_env >/dev/null 2>&1); then ok "author/7 author survives set -e on the structural-repair path" || true; else no "author/7 author aborted under set -e (repair path)"; fi

# author/8) no-interactivity proof: the interactive symbols are GONE from the
# live script, and the Cron section carries no `read -r` consent prompt.
[ "$(grep -c 'do_provision_cron_env' "$BOOTSTRAP")" -eq 0 ] && ok "author/8 do_provision_cron_env fully removed from the script" || no "author/8 do_provision_cron_env still present in the script"
[ "$(grep -c 'do_repair_cron_env' "$BOOTSTRAP")" -eq 0 ] && ok "author/8 do_repair_cron_env fully removed from the script" || no "author/8 do_repair_cron_env still present in the script"
[ "$(grep -c '_is_interactive' "$BOOTSTRAP")" -eq 0 ] && ok "author/8 _is_interactive fully removed from the script" || no "author/8 _is_interactive still present in the script"
_cron_src="$(awk '/^# ─── Cron \(sdlc-poker/{f=1} f{print} /^# ─── Account-mirror/{exit}' "$BOOTSTRAP")"
if printf '%s' "$_cron_src" | grep -q 'read -r'; then no "author/8 Cron section still contains a read -r consent prompt"; else ok "author/8 Cron section has no read -r consent prompt"; fi

# author/9) reset must still NOT reference cron.env — user-owned credential data,
# never deleted by a reset (unchanged by amendment 3).
if grep -q 'cron\.env' "${REPO}/claude-reset.sh"; then no "author/9 claude-reset.sh must not reference cron.env (user credential data)"; else ok "author/9 claude-reset.sh leaves cron.env untouched"; fi

# author/10) C6-am3 ADDENDUM — trailing-newline guard. A hand-authored file whose
# last byte is NOT a newline must never merge with the appended key line. Existing
# no-trailing-newline token line + MISSING topic → structural repair must emit a
# newline BEFORE appending, yielding two well-formed lines (both values intact);
# the pre-guard behavior produced ONE corrupt line destroying both values.
printf 'CLAUDE_CODE_OAUTH_TOKEN=%s' "$VALID_TOK" > "$AUTH_F"     # NO trailing newline
chmod 600 "$AUTH_F"
STEP_RECORDS=(); INSTALL_FAILURES=()
do_author_cron_env >/dev/null
grep -qxF "CLAUDE_CODE_OAUTH_TOKEN=$VALID_TOK" "$AUTH_F" && ok "author/10 no-trailing-newline token line preserved intact (not merged)" || no "author/10 token line corrupted by merge: $(sed 's/=.*/=<redacted>/' "$AUTH_F")"
case "$(grep -m1 '^BIONIC_NTFY_TOPIC=' "$AUTH_F")" in BIONIC_NTFY_TOPIC=bionic-?*) ok "author/10 topic added on its OWN line (newline guard held)";; *) no "author/10 topic line missing or merged: $(cat -A "$AUTH_F")";; esac
[ "$(grep -c '=' "$AUTH_F")" -eq 2 ] && ok "author/10 exactly two KEY=VALUE lines (no corrupt merge)" || no "author/10 wrong line count (merge corruption): $(cat -A "$AUTH_F")"
export HOME="$_OLD_HOME"

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
HOME="$_saved_home"; PATH="$_saved_path"
[ "$_rc" = "0" ] && ok "claude cli: native fallback succeeds" || no "claude cli: fallback rc=$_rc"
grep -q '^curl -fsSL https://claude.ai/install.sh' "$LOG" \
  && ok "claude cli: native installer invoked on npm failure" \
  || no "claude cli: native installer not invoked"
case "${STEP_RECORDS[0]:-}" in
  ok\|prereq\|*native\ installer*) ok "claude cli: channel named in record" ;;
  *) no "claude cli: expected native-installer note (got: ${STEP_RECORDS[0]:-none})" ;;
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

echo "========================================"
echo "Installer behavior: ${PASS} passed, ${FAIL} failed"
echo "========================================"
[ "$FAIL" -eq 0 ]
