#!/bin/bash
# tests/loader.test.sh — the one loader idiom (bionic 1.4.0, wave-bionic-1.4.0-update
# slice L-LOADER, spec AC-16, plan §L-LOADER; design ledger S4; R-1 §(4) and §(5)).
#
# WHAT IS UNDER TEST. payload/scripts/lib/loader.sh carries the canonical idiom text
# between the exact marker lines `# --- bionic-loader/v2 BEGIN` and
# `# --- bionic-loader/v2 END`, and exposes `bionic_loader_pin`, which prints that
# block (markers inclusive). Slice ADOPT pastes the printed block byte-identically
# into every hook; the byte-identity pin lives in the cross-gate suite. This suite
# tests the BEHAVIOUR of the block, and it tests it the only honest way: by pasting
# `bionic_loader_pin`'s output into a throwaway hook and running that hook. A library
# cannot load itself, so `$0` — the hook's own path — is the block's first input, and
# nothing that sources loader.sh directly could observe that.
#
# WHY THE BLOCK IS NOT EXECUTABLE AT loader.sh's TOP LEVEL. loader.sh is a carrier,
# not a loader: sourcing it must define `bionic_loader_pin` and do nothing else. The
# canonical text therefore sits inside a QUOTED heredoc, so the marker lines and every
# line between them are literal bytes in the file and extraction by marker works
# identically on loader.sh and on any hook ADOPT has written.
#
# THE THREE CANDIDATE CLASSES (plan §L-LOADER, spec AC-16), later ones evaluated only
# when the earlier ones fail:
#   (1) beside the hook. Two spellings of ONE directory, because the shipped tree has
#       two real shapes: `../scripts/lib` (installed plugin root, hooks/ and scripts/
#       siblings) and `../payload/scripts/lib` (this repo, where payload/hooks is a
#       symlink to the top-level hooks/ and `$0` is textual). The four loaders this
#       supersedes all carried both spellings (hooks/protect-main.sh:31-33 and its
#       three twins); dropping one would refuse every command in a directory-source
#       session. Both are class (1): neither costs jq, neither reads the registry.
#   (2) the marketplace source tree named for this plugin in the CLI's install
#       registry — `installed_plugins.json` gives the marketplace, and that
#       marketplace's `source.path` in `known_marketplaces.json` gives the tree.
#   (3) the newest version directory under that marketplace's plugin cache, chosen by
#       three-integer compare (1.10.0 beats 1.3.2; a lexical sort gets this wrong,
#       which is why §C fixtures exactly that pair).
#
# HERMETIC. Every run overrides HOME and BIONIC_PLUGINS_DIR into a per-run `mktemp -d`
# root. Nothing in this suite reads or writes the real ~/.claude — the machine's own
# registry is read-only truth for the DESIGN, never an input to an assertion.
#
# ANTI-VACUITY (memory/no-vacuous-tests-at-authoring). Three guards, each of which
# would go red on a suite that had quietly stopped testing anything:
#   - §0 proves the block exists, is marker-delimited, and parses as bash before any
#     behavioural assertion runs.
#   - §A's "jq was never called" claim is only worth something if the jq shim can
#     actually be reached, so §A3 runs a fixture that MUST consult the registry and
#     asserts the shim fired.
#   - §C carries an unmutated control (a cache holding 1.3.2 alone must select 1.3.2),
#     so "picked 1.10.0" cannot pass by hardcoding.
#
# Usage: bash tests/loader.test.sh
#   BIONIC_LOADER_LIB_UNDER_TEST=/tmp/mutant/loader.sh bash tests/loader.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PAYLOAD="${REPO}/payload"
LOADER_LIB="${BIONIC_LOADER_LIB_UNDER_TEST:-${PAYLOAD}/scripts/lib/loader.sh}"

MARK_BEGIN='# --- bionic-loader/v2 BEGIN'
MARK_END='# --- bionic-loader/v2 END'

PASS=0; FAIL=0; TOTAL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo "FAIL: $1"; [ -n "${2:-}" ] && echo "  $2"; FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); }
eq()   { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "want [$3] got [$2]"; fi; }

# ── The subject must exist before anything claims to have tested it ──────────
if [ ! -r "$LOADER_LIB" ]; then
  echo "FAIL: loader library not readable at $LOADER_LIB"
  echo "Gating: 0/1 passed"
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bionic-loader.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT
FAKE_HOME="$WORK/nohome"; mkdir -p "$FAKE_HOME"

# ── §0 — the block extracts, is marker-delimited, and parses ─────────────────
BLOCK="$WORK/block.txt"
( set +u; . "$LOADER_LIB" && bionic_loader_pin ) > "$BLOCK" 2>"$WORK/pin.err"
if [ ! -s "$BLOCK" ]; then
  fail "0.1 bionic_loader_pin prints the canonical block" "empty; stderr: $(cat "$WORK/pin.err")"
else
  pass "0.1 bionic_loader_pin prints the canonical block"
fi
eq "0.2 first line is the BEGIN marker"  "$(head -1 "$BLOCK")" "$MARK_BEGIN"
eq "0.3 last line is the END marker"     "$(tail -1 "$BLOCK")" "$MARK_END"
if [ "$(grep -c -- "^${MARK_BEGIN}\$" "$BLOCK")" = "1" ] && [ "$(grep -c -- "^${MARK_END}\$" "$BLOCK")" = "1" ]; then
  pass "0.4 exactly one marker pair in the block"
else
  fail "0.4 exactly one marker pair in the block"
fi
if [ "$(grep -c -- "^${MARK_BEGIN}\$" "$LOADER_LIB")" = "1" ]; then
  pass "0.5 loader.sh carries the marker literally, once"
else
  fail "0.5 loader.sh carries the marker literally, once"
fi
# Sourcing the carrier must define the function and do nothing else — in
# particular it must not set BIONIC_LIB, which would mean the block ran.
if ( set +u; . "$LOADER_LIB" >/dev/null 2>&1; [ -z "${BIONIC_LIB:-}" ] && [ -z "${BIONIC_LIB_MISSING:-}" ] ); then
  pass "0.6 sourcing loader.sh does not execute the block"
else
  fail "0.6 sourcing loader.sh does not execute the block" "BIONIC_LIB/BIONIC_LIB_MISSING set on source"
fi

# ── fixture builder ─────────────────────────────────────────────────────────
# Writes <root>/hooks/probe.sh: a hook whose body is the canonical block
# verbatim, preceded by the BIONIC_LIB_WANT declaration ADOPT will write and
# followed by whatever tail the case needs. `$0` is <root>/hooks/probe.sh, so
# candidate (1) resolves relative to <root> exactly as it does in a real install.
REPORT_TAIL='echo "LIB=${BIONIC_LIB}"; echo "MISSING=${BIONIC_LIB_MISSING}"; echo "CANDS=${BIONIC_LIB_CANDS}"'
mkhook() { # mkhook <root> <tail>
  mkdir -p "$1/hooks"
  {
    echo '#!/bin/bash'
    echo 'set -u'
    echo 'BIONIC_LIB_WANT="git-argv.sh"'
    cat "$BLOCK"
    printf '%s\n' "$2"
  } > "$1/hooks/probe.sh"
  chmod +x "$1/hooks/probe.sh"
}
runhook() { # runhook <root> <plugins-dir> <extra-PATH-prefix-or-empty> [argv...]
  _r="$1"; _pd="$2"; _pp="$3"; shift 3
  if [ -n "$_pp" ]; then
    env HOME="$FAKE_HOME" BIONIC_PLUGINS_DIR="$_pd" PATH="$_pp:$PATH" bash "$_r/hooks/probe.sh" "$@"
  else
    env HOME="$FAKE_HOME" BIONIC_PLUGINS_DIR="$_pd" bash "$_r/hooks/probe.sh" "$@"
  fi
}
field() { grep "^$2=" "$1" | head -1 | sed "s/^$2=//"; }

# The loud jq shim: any call to jq writes a marker and dies with 99.
SHIM_BIN="$WORK/shim-bin"; mkdir -p "$SHIM_BIN"
JQ_MARK="$WORK/jq-was-called"
cat > "$SHIM_BIN/jq" <<SHIM
#!/bin/sh
echo "jq called with: \$*" >> "$JQ_MARK"
echo "LOADER TEST: jq must not run on the candidate-(1) path" >&2
exit 99
SHIM
chmod +x "$SHIM_BIN/jq"

# `bash -n` on a built hook — the block must parse where it is actually pasted.
mkhook "$WORK/parse" "$REPORT_TAIL"
if bash -n "$WORK/parse/hooks/probe.sh" 2>"$WORK/parse.err"; then
  pass "0.7 the block parses as bash inside a hook"
else
  fail "0.7 the block parses as bash inside a hook" "$(cat "$WORK/parse.err")"
fi

# ── §A — candidate (1) wins, and (2)/(3) are never evaluated ────────────────
A1="$WORK/a1"; mkdir -p "$A1/scripts/lib"; : > "$A1/scripts/lib/git-argv.sh"
mkhook "$A1" "$REPORT_TAIL"
rm -f "$JQ_MARK"
runhook "$A1" "$WORK/a1-plugins" "$SHIM_BIN" > "$WORK/a1.out" 2>"$WORK/a1.err"; A1RC=$?
eq "A1.1 installed spelling: hook exits 0"     "$A1RC" "0"
eq "A1.2 installed spelling: BIONIC_LIB"       "$(field "$WORK/a1.out" LIB)" "$A1/hooks/../scripts/lib"
eq "A1.3 installed spelling: nothing missing"  "$(field "$WORK/a1.out" MISSING)" ""
if [ -f "$JQ_MARK" ]; then
  fail "A1.4 candidates (2)/(3) never evaluated" "jq ran: $(cat "$JQ_MARK")"
else
  pass "A1.4 candidates (2)/(3) never evaluated"
fi

A2="$WORK/a2"; mkdir -p "$A2/payload/scripts/lib"; : > "$A2/payload/scripts/lib/git-argv.sh"
mkhook "$A2" "$REPORT_TAIL"
rm -f "$JQ_MARK"
runhook "$A2" "$WORK/a2-plugins" "$SHIM_BIN" > "$WORK/a2.out" 2>"$WORK/a2.err"; A2RC=$?
eq "A2.1 repo spelling: hook exits 0"    "$A2RC" "0"
eq "A2.2 repo spelling: BIONIC_LIB"      "$(field "$WORK/a2.out" LIB)" "$A2/hooks/../payload/scripts/lib"
if [ -f "$JQ_MARK" ]; then
  fail "A2.3 repo spelling is still class (1) — no jq" "jq ran: $(cat "$JQ_MARK")"
else
  pass "A2.3 repo spelling is still class (1) — no jq"
fi

# A3 — the shim is reachable. Without this, A1.4/A2.3 could pass on a block that
# never consults the registry at all, or on a PATH the hook does not inherit.
A3="$WORK/a3"; mkhook "$A3" "$REPORT_TAIL"
A3PD="$WORK/a3-plugins"; mkdir -p "$A3PD"
printf '%s\n' '{"plugins":{"bionic@bionic":[{"installPath":"/nowhere"}]}}' > "$A3PD/installed_plugins.json"
rm -f "$JQ_MARK"
runhook "$A3" "$A3PD" "$SHIM_BIN" > "$WORK/a3.out" 2>"$WORK/a3.err"
if [ -f "$JQ_MARK" ]; then
  pass "A3.1 the jq shim is reachable when the registry IS consulted"
else
  fail "A3.1 the jq shim is reachable when the registry IS consulted" "shim never fired — A1.4/A2.3 prove nothing"
fi

# ── §B — candidate (2): the marketplace source tree from the registry ───────
# The marketplace is READ from installed_plugins.json, not assumed to be "bionic":
# this fixture names it `bionic-fork`, so a hardcoded marketplace fails here.
B="$WORK/b"; mkhook "$B" "$REPORT_TAIL"
BPD="$WORK/b-plugins"; mkdir -p "$BPD"
BSRC="$WORK/b-src"; mkdir -p "$BSRC/payload/scripts/lib"; : > "$BSRC/payload/scripts/lib/git-argv.sh"
printf '%s\n' '{"plugins":{"bionic@bionic-fork":[{"installPath":"/nowhere"}],"other@elsewhere":[{}]}}' > "$BPD/installed_plugins.json"
jq -n --arg p "$BSRC" '{"bionic-fork":{"source":{"source":"directory","path":$p}},"elsewhere":{"source":{"source":"github","repo":"x/y"}}}' > "$BPD/known_marketplaces.json"
runhook "$B" "$BPD" "" > "$WORK/b.out" 2>"$WORK/b.err"; BRC=$?
eq "B.1 registry source path: hook exits 0" "$BRC" "0"
eq "B.2 registry source path chosen"        "$(field "$WORK/b.out" LIB)" "$BSRC/payload/scripts/lib"
eq "B.3 nothing missing"                    "$(field "$WORK/b.out" MISSING)" ""

# ── §C — candidate (3): newest cache version dir, three-int compare ─────────
C="$WORK/c"; mkhook "$C" "$REPORT_TAIL"
CPD="$WORK/c-plugins"; mkdir -p "$CPD"
printf '%s\n' '{"plugins":{"bionic@bionic-fork":[{"installPath":"/nowhere"}]}}' > "$CPD/installed_plugins.json"
# A registry entry whose source tree does NOT exist: candidate (2) must fail, not
# throw, before (3) is reached.
jq -n --arg p "$WORK/c-absent" '{"bionic-fork":{"source":{"source":"directory","path":$p}}}' > "$CPD/known_marketplaces.json"
for v in 1.3.2 1.10.0; do mkdir -p "$CPD/cache/bionic-fork/bionic/$v/scripts/lib"; : > "$CPD/cache/bionic-fork/bionic/$v/scripts/lib/git-argv.sh"; done
mkdir -p "$CPD/cache/bionic-fork/bionic/not-a-version"
runhook "$C" "$CPD" "" > "$WORK/c.out" 2>"$WORK/c.err"; CRC=$?
eq "C.1 cache fallback: hook exits 0" "$CRC" "0"
eq "C.2 1.10.0 beats 1.3.2 (three-int, not lexical)" \
   "$(field "$WORK/c.out" LIB)" "$CPD/cache/bionic-fork/bionic/1.10.0/scripts/lib"

# Control: the same code path with 1.3.2 alone must select 1.3.2 — "picked 1.10.0"
# cannot be a hardcoded string.
C2="$WORK/c2"; mkhook "$C2" "$REPORT_TAIL"
C2PD="$WORK/c2-plugins"; mkdir -p "$C2PD"
printf '%s\n' '{"plugins":{"bionic@bionic-fork":[{"installPath":"/nowhere"}]}}' > "$C2PD/installed_plugins.json"
jq -n --arg p "$WORK/c-absent" '{"bionic-fork":{"source":{"source":"directory","path":$p}}}' > "$C2PD/known_marketplaces.json"
mkdir -p "$C2PD/cache/bionic-fork/bionic/1.3.2/scripts/lib"; : > "$C2PD/cache/bionic-fork/bionic/1.3.2/scripts/lib/git-argv.sh"
runhook "$C2" "$C2PD" "" > "$WORK/c2.out" 2>"$WORK/c2.err"
eq "C.3 control: a lone 1.3.2 is selected" \
   "$(field "$WORK/c2.out" LIB)" "$C2PD/cache/bionic-fork/bionic/1.3.2/scripts/lib"

# ── §D — every candidate fails ─────────────────────────────────────────────
D="$WORK/d"; mkhook "$D" "$REPORT_TAIL"
DPD="$WORK/d-plugins"; mkdir -p "$DPD"
runhook "$D" "$DPD" "" > "$WORK/d.out" 2>"$WORK/d.err"; DRC=$?
eq "D.1 all candidates missing: block does not exit"  "$DRC" "0"
eq "D.2 BIONIC_LIB empty"                             "$(field "$WORK/d.out" LIB)" ""
eq "D.3 BIONIC_LIB_MISSING names the wanted library"  "$(field "$WORK/d.out" MISSING)" "git-argv.sh"
DCANDS="$(field "$WORK/d.out" CANDS)"
case "$DCANDS" in
  *"$D/hooks/../scripts/lib"*) pass "D.4 candidate list records what was tried" ;;
  *) fail "D.4 candidate list records what was tried" "CANDS=[$DCANDS]" ;;
esac

# ── §E — loader_fail_open: one stderr line, exit 0 ─────────────────────────
E="$WORK/e"; mkhook "$E" 'loader_fail_open "farm-out-reminder"; echo "REACHED-PAST-FAIL-OPEN"'
runhook "$E" "$WORK/e-plugins" "" > "$WORK/e.out" 2>"$WORK/e.err"; ERC=$?
eq "E.1 fail_open exits 0"                "$ERC" "0"
eq "E.2 fail_open writes nothing to stdout" "$(cat "$WORK/e.out")" ""
eq "E.3 fail_open prints exactly one stderr line" "$(wc -l < "$WORK/e.err" | tr -d ' ')" "1"
EMSG="$(cat "$WORK/e.err")"
for needle in "farm-out-reminder" "git-argv.sh" "$E/hooks/../scripts/lib" "/bionic:doctor"; do
  case "$EMSG" in
    *"$needle"*) pass "E.4 fail_open line names: $needle" ;;
    *) fail "E.4 fail_open line names: $needle" "line=[$EMSG]" ;;
  esac
done

# ── §F — loader_fail_closed: the four repair commands, and nothing else ────
F="$WORK/f"; mkhook "$F" 'loader_fail_closed "protect-main" "$1"; echo "REACHED-PAST-FAIL-CLOSED"'
FROOT="$(cd "$F" && pwd -P)"
FPD="$WORK/f-plugins"; mkdir -p "$FPD"
allow() { # allow <label> <command>
  runhook "$F" "$FPD" "" "$2" > "$WORK/f.out" 2>"$WORK/f.err"
  _rc=$?
  eq "F.$1 permitted (exit 0): $2" "$_rc" "0"
}
deny() { # deny <label> <command>
  runhook "$F" "$FPD" "" "$2" > "$WORK/f.out" 2>"$WORK/f.err"
  _rc=$?
  eq "F.$1 refused (exit 2): $2" "$_rc" "2"
}
allow 1 "claude plugin update bionic@bionic"
allow 2 "claude plugin install bionic@bionic"
allow 3 "bash $FROOT/scripts/doctor.sh"
allow 4 "bash $FROOT/scripts/setup.sh"
deny  5 "claude plugin update bionic@bionic; git push origin main"
deny  6 "git push"
deny  7 "claude plugin update bionic@bionic && git push"
deny  8 "echo claude plugin update bionic@bionic"
deny  9 "bash $FROOT/scripts/doctor.sh --fix"

# The refusal message must name the missing file and all four repair commands.
runhook "$F" "$FPD" "" "git push" > "$WORK/f6.out" 2>"$WORK/f6.err"
FMSG="$(cat "$WORK/f6.err")"
for needle in \
  "git-argv.sh" \
  "claude plugin update bionic@bionic" \
  "claude plugin install bionic@bionic" \
  "bash $FROOT/scripts/doctor.sh" \
  "bash $FROOT/scripts/setup.sh"; do
  case "$FMSG" in
    *"$needle"*) pass "F.10 refusal names: $needle" ;;
    *) fail "F.10 refusal names: $needle" ;;
  esac
done
case "$(cat "$WORK/f6.out")" in
  *REACHED-PAST-FAIL-CLOSED*) fail "F.11 a refusal does not fall through to the hook body" ;;
  *) pass "F.11 a refusal does not fall through to the hook body" ;;
esac

# A permitted command must not reach the hook body either — the wall has no
# library, so permitting means standing aside, not proceeding half-loaded.
runhook "$F" "$FPD" "" "claude plugin update bionic@bionic" > "$WORK/f1.out" 2>"$WORK/f1.err"
case "$(cat "$WORK/f1.out")" in
  *REACHED-PAST-FAIL-CLOSED*) fail "F.12 a permit stands aside rather than proceeding" ;;
  *) pass "F.12 a permit stands aside rather than proceeding" ;;
esac

# ── §G — the allowlist is checked before any sourcing ──────────────────────
# A hook written the ADOPT way calls loader_fail_closed on the missing-library
# path; the library is never sourced there because both branches exit. Prove it
# by planting a booby-trapped library that would be found if the block tried to
# source anything after the candidate walk.
G="$WORK/g"; mkdir -p "$G/scripts/lib"
printf '%s\n' 'echo "SOURCED-THE-LIBRARY"' > "$G/scripts/lib/git-argv.sh"
mkhook "$G" 'loader_fail_closed "protect-main" "$1"'
runhook "$G" "$WORK/g-plugins" "" "git push" > "$WORK/g.out" 2>"$WORK/g.err"; GRC=$?
eq "G.1 the block itself never sources the library" "$(cat "$WORK/g.out")" ""
eq "G.2 with a library present, fail_closed is the caller's choice, still exact-match" "$GRC" "2"

echo
echo "Gating: $PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
