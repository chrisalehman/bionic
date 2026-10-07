#!/bin/bash
# tests/interpreter-pin.test.sh — the interpreter pin, the environment stamp, and the
# runner's stderr-strict arm (wave-01 verification-cannot-lie, task S2; spec AC-1, AC-2,
# AC-3, AC-10, and the runner half of AC-14).
#
# WHAT THE PIN IS. Every payload script and hook pins `#!/bin/bash` — bash 3.2 on a Mac —
# and the CLI runs a hook by path, so the shebang chooses the interpreter. The suites,
# though, type `bash "$HOOK"`, which picks up whatever `bash` is first on PATH: Homebrew
# 5.3 on this machine. A green run the default way therefore proved the payload under an
# interpreter it is never executed with (ADR-001, "one interpreter: the shebang is the
# contract"). `tests/run.sh` now launches every child with a one-entry LAUNCH DIRECTORY
# first on PATH whose only entry is `bash -> /bin/bash`; the rest of PATH is the caller's
# own, so `jq`, `git` and `claude` still resolve exactly where they did.
#
# ITS NAME IS "THE INTERPRETER PIN", never "the PATH shim" (design ledger now-4: v1 wave 0
# deletes an unrelated omnigent piece by that name, and two mechanisms sharing one name is
# how a reader ends up reading the wrong file).
#
# WHY A SUITE OF ITS OWN. A verification instrument must be proven to CATCH what it exists
# to catch. §3 plants two constructs that are MEASURED divergences between 3.2 and 5.x —
# not guesses:
#
#   (a) the quoted-`$( )`-inside-`case` leak: 3.2's parser ends the command substitution at
#       the first `)` of a `case` pattern and leaks the remainder as literal text, so the
#       function returns garbage and exits 0 — a green for the wrong reason;
#   (b) the here-string temporary-assignment divergence (research-code-map §4.e, measured
#       there for the first time): in `VAR=x cmd <<< "$(f)"` the temporary assignment IS in
#       effect while the here-string's command substitution expands under 3.2 and is NOT
#       under 5.3, so `f` runs under the stripped PATH and the here-string arrives empty.
#       This is the live defect behind `jq: command not found` in the recorded 3.2 baseline
#       and behind tests/patrol-revive.test.sh:264.
#
# Each planted suite asserts the 5.x answer. Driven through the pinned runner both go RED;
# run directly under the machine's other interpreter both go GREEN. A pin that stopped
# pinning would show up here as two suites that quietly started passing.
#
# THE SECOND INTERPRETER IS DISCOVERED, NOT ASSUMED. Rows that need a bash whose version
# differs from /bin/bash's are SKIPPED, loudly and by name, on a host that has only one —
# a Linux box where /bin/bash is 5.x has nothing to compare against, and a row that cannot
# be driven must say so rather than pass.
#
# HERMETIC. Every runner drive below is against a SCRATCH TREE (the shipped tests/run.sh,
# byte for byte, over a tests/ directory holding only this suite's own probe files — the
# roster is derived from the directory, so nothing needs rewriting) under this suite's own
# mktemp root, with the pressure ring and clock pinned. Nothing here runs the real roster —
# that would recurse into this very file.
#
# Usage: bash tests/interpreter-pin.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
REPO="$BIONIC_SCRIPTS_DIR"

SKIPPED=0
skip() { SKIPPED=$((SKIPPED + 1)); echo "SKIP: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/interpreter-pin-test.XXXXXX")"
trap 'chmod -R -N "$TMPROOT" 2>/dev/null; rm -rf "$TMPROOT"' EXIT   # an ACL row's entry never outlives the run (T57)

SYS_BASH="/bin/bash"
SYS_VER="$("$SYS_BASH" -c 'echo "$BASH_VERSION"' 2>/dev/null)"

# The other interpreter, if this host has one: any bash whose $BASH_VERSION differs from
# /bin/bash's. Homebrew's is looked at first because that is what this machine has; the
# rest of the search is whatever `type -ap` can see.
find_alt_bash() {
  local c v
  for c in /opt/homebrew/bin/bash /usr/local/bin/bash $(type -ap bash 2>/dev/null); do
    [ -x "$c" ] || continue
    v="$("$c" -c 'echo "$BASH_VERSION"' 2>/dev/null)"
    [ -n "$v" ] || continue
    if [ "$v" != "$SYS_VER" ]; then printf '%s' "$c"; return 0; fi
  done
  return 1
}
ALT_BASH="$(find_alt_bash)" || ALT_BASH=""
ALT_VER=""
ALT_DIR="$TMPROOT/alt-bin"
mkdir -p "$ALT_DIR"
if [ -n "$ALT_BASH" ]; then
  ALT_VER="$("$ALT_BASH" -c 'echo "$BASH_VERSION"')"
  ln -sf "$ALT_BASH" "$ALT_DIR/bash"
fi

echo "=== interpreter-pin: /bin/bash is ${SYS_VER:-unknown}; other interpreter: ${ALT_BASH:-none} ${ALT_VER}"
echo ""

# ── the scratch tree ─────────────────────────────────────────────────────────
# The shipped runner, byte for byte. Same layout the runner resolves against: it derives
# $REPO from its own path and sources $REPO/payload/scripts/lib/resources.sh, and
# tests/lib/resolve-roots.sh sits beside it.
#
# THE ROSTER IS THE TREE (fixit 1.5.1). The runner derives its roster from the tests/
# directory it is run in, so a drive's roster is exactly the probe files planted below
# and no rewrite is needed — the copy is the shipped file, unedited. These trees carry
# no tests/lib/assert.sh, so the roster wall's framework half is inert here and the
# probes are raw interpreter probes rather than framework clients, which is what they
# have to be: §3 runs two of them directly under a second interpreter.
mk_tree() {  # mk_tree <dir>
  local dir="$1"
  mkdir -p "$dir/tests/lib" "$dir/payload/scripts/lib"
  cp "$REPO/tests/run.sh" "$dir/tests/run.sh"
  cp "$REPO/tests/lib/resolve-roots.sh" "$dir/tests/lib/resolve-roots.sh"
  cp "$REPO"/payload/scripts/lib/*.sh "$dir/payload/scripts/lib/" 2>/dev/null
}

# drive <tree> <mode|""> — run the scratch runner with the ALTERNATE interpreter first on
# PATH (the hostile case: a foreign `bash` is what `bash tests/…` would otherwise pick),
# leaving DRV_OUT and DRV_RC behind. The pin marker is unset first: this very suite may be
# running under the real runner, which exports it, and an inherited marker would make the
# hand-run rows below vacuous.
DRV_OUT=""; DRV_RC=0
drive() {
  local tree="$1" mode="${2:-}"
  DRV_OUT="$( cd "$tree" && \
    unset BIONIC_TEST_INTERPRETER_PINNED && \
    PATH="$ALT_DIR:$PATH" \
    BIONIC_PRESSURE_RING="$TMPROOT/ring" \
    BIONIC_NOW_EPOCH="1700000000" \
    BIONIC_TEST_JOBS_CEILING="2" \
    BIONIC_PROBE_OUT="$TMPROOT/probe.out" \
    bash tests/run.sh ${mode:+"$mode"} 2>&1 )"
  DRV_RC=$?
}

section "§1 the pin: every child of the runner is /bin/bash, and the rest of PATH is intact (AC-1)"
#
# The probe is a real suite in the roster. It cannot report through stdout — the runner
# prints a passing suite's captured output nowhere — so it writes the facts it reads to
# $BIONIC_PROBE_OUT, which the runner passes through by inheriting this suite's environment.

PROBE_TREE="$TMPROOT/probe-tree"
mk_tree "$PROBE_TREE"
cat > "$PROBE_TREE/tests/probe.test.sh" <<'PROBE_EOF'
#!/bin/bash
{ echo "BASH_VERSION=$BASH_VERSION"
  echo "bash=$(command -v bash 2>/dev/null || echo MISSING)"
  echo "git=$(command -v git 2>/dev/null || echo MISSING)"
  echo "first_path_entry=${PATH%%:*}"
  echo "bash_target=$(readlink "$(command -v bash 2>/dev/null)" 2>/dev/null || echo NONE)"
} > "$BIONIC_PROBE_OUT"
exit 0
PROBE_EOF

HOST_GIT="$(command -v git 2>/dev/null || echo MISSING)"

for MODE in "--serial" ""; do
  MODE_NAME="parallel"; [ -n "$MODE" ] && MODE_NAME="serial"
  : > "$TMPROOT/probe.out"
  drive "$PROBE_TREE" "$MODE"
  P_OUT="$(cat "$TMPROOT/probe.out" 2>/dev/null)"
  P_VER="$(printf '%s\n' "$P_OUT" | sed -n 's/^BASH_VERSION=//p')"
  P_BASH="$(printf '%s\n' "$P_OUT" | sed -n 's/^bash=//p')"
  P_GIT="$(printf '%s\n' "$P_OUT" | sed -n 's/^git=//p')"
  P_FIRST="$(printf '%s\n' "$P_OUT" | sed -n 's/^first_path_entry=//p')"

  expect_eq "1.1 ($MODE_NAME) the probe suite ran at all (not vacuous)" "0" "$DRV_RC"
  expect_eq "1.2 ($MODE_NAME) the suite's interpreter is the system one" "$SYS_VER" "$P_VER"
  expect_eq "1.3 ($MODE_NAME) \`bash\` inside a suite resolves through the launch directory" \
    "$P_FIRST/bash" "$P_BASH"
  if [ -n "$ALT_BASH" ]; then
    expect_ne "1.3b ($MODE_NAME) …a directory the RUNNER put ahead of the caller's own PATH" \
      "$ALT_DIR" "$P_FIRST"
  else
    skip "1.3b ($MODE_NAME) the launch directory is the runner's, not the caller's" "this host has only one bash"
  fi
  expect_eq "1.4 ($MODE_NAME) …and that entry is /bin/bash" "$SYS_BASH" \
    "$(printf '%s\n' "$P_OUT" | sed -n 's/^bash_target=//p')"
  expect_eq "1.5 ($MODE_NAME) the rest of PATH is the caller's own: git resolves where it did" \
    "$HOST_GIT" "$P_GIT"
  # NON-VACUITY: the drive really did put a foreign interpreter first, so 1.2 is the pin
  # answering and not "there is only one bash on this machine".
  if [ -n "$ALT_BASH" ]; then
    expect_ne "1.6 ($MODE_NAME) …and the interpreter the drive offered was NOT the system one" \
      "$SYS_VER" "$ALT_VER"
  else
    skip "1.6 ($MODE_NAME) the drive offered a foreign interpreter" "this host has only one bash"
  fi
done
echo ""

section "§2 hand-run parity: a suite invoked by hand re-execs once under /bin/bash (AC-2)"
#
# The seam every suite already sources does the work, so a suite typed at a prompt under
# another interpreter lands on the same one the runner would have given it. The guard is the
# RUNNING INTERPRETER, not a marker: after `exec /bin/bash "$0"`, `$BASH` is `/bin/bash`, so
# the re-exec happens exactly once and can never loop (critic K-4, Step 6).

# THE CHILDREN, NOT ONLY THE SUITE (wave-27 T81). The seam once re-executed the suite and
# pinned nothing for what it starts, so a hand-run suite was 3.2 while every `bash "$HOOK"`
# it ran took PATH's 5.3 — the world tests/run.sh never gives a suite. The probe therefore
# also records what a child `bash -c` and a child `bash <a hook copy>` report, and the PATH
# its children are handed. The hook copy is a real hook with one line put after its shebang
# that prints the interpreter and exits.
HOOK_COPY="$TMPROOT/hook-copy.sh"
{ head -1 "$BIONIC_HOOKS_DIR/session-poker.sh"
  printf 'printf "%%s\\n" "$BASH_VERSION"; exit 0\n'
  tail -n +2 "$BIONIC_HOOKS_DIR/session-poker.sh"
} > "$HOOK_COPY"

mk_hand() {  # mk_hand <seam> <file> — a hand-run suite that sources <seam>
  { printf '#!/bin/bash\n'
    printf 'echo start >> "$HAND_COUNT"\n'
    printf '. "%s"\n' "$1"
    cat <<'HAND_EOF'
echo "BASH_VERSION=$BASH_VERSION" > "$HAND_OUT"
echo "argv=$*" >> "$HAND_OUT"
echo "roots=$BIONIC_HOOKS_DIR" >> "$HAND_OUT"
echo "child=$(bash -c 'echo "$BASH_VERSION"' 2>/dev/null)" >> "$HAND_OUT"
echo "hook=$(bash "$HAND_HOOK" 2>/dev/null)" >> "$HAND_OUT"
echo "first_target=$(readlink "${PATH%%:*}/bash" 2>/dev/null || echo NONE)" >> "$HAND_OUT"
echo "rest=${PATH#*:}" >> "$HAND_OUT"
echo "git=$(command -v git 2>/dev/null || echo MISSING)" >> "$HAND_OUT"
echo "jq=$(command -v jq 2>/dev/null || echo MISSING)" >> "$HAND_OUT"
HAND_EOF
  } > "$2"
  chmod +x "$2"
}
HAND="$TMPROOT/hand.test.sh"
mk_hand "$REPO/tests/lib/resolve-roots.sh" "$HAND"

# The PATH a hand-run is given: the foreign interpreter first, then this suite's own.
HAND_GIVEN_PATH="$ALT_DIR:$PATH"

hand_run() {  # hand_run <interpreter> [marker] [suite] — leaves HAND_VER / HAND_STARTS / HAND_ARGV / HAND_CHILD …
  : > "$TMPROOT/hand.count"; : > "$TMPROOT/hand.out"
  ( if [ -n "${2:-}" ]; then
      BIONIC_TEST_INTERPRETER_PINNED="$2"; export BIONIC_TEST_INTERPRETER_PINNED
    else
      unset BIONIC_TEST_INTERPRETER_PINNED
    fi
    PATH="$HAND_GIVEN_PATH" \
    HAND_COUNT="$TMPROOT/hand.count" HAND_OUT="$TMPROOT/hand.out" HAND_HOOK="$HOOK_COPY" \
    "$1" "${3:-$HAND}" one two ) >/dev/null 2>&1
  HAND_VER="$(sed -n 's/^BASH_VERSION=//p' "$TMPROOT/hand.out")"
  HAND_ARGV="$(sed -n 's/^argv=//p' "$TMPROOT/hand.out")"
  HAND_ROOTS="$(sed -n 's/^roots=//p' "$TMPROOT/hand.out")"
  HAND_CHILD="$(sed -n 's/^child=//p' "$TMPROOT/hand.out")"
  HAND_HOOKVER="$(sed -n 's/^hook=//p' "$TMPROOT/hand.out")"
  HAND_FIRST_TARGET="$(sed -n 's/^first_target=//p' "$TMPROOT/hand.out")"
  HAND_REST="$(sed -n 's/^rest=//p' "$TMPROOT/hand.out")"
  HAND_GIT="$(sed -n 's/^git=//p' "$TMPROOT/hand.out")"
  HAND_JQ="$(sed -n 's/^jq=//p' "$TMPROOT/hand.out")"
  HAND_STARTS="$(wc -l < "$TMPROOT/hand.count" | tr -d ' ')"
}

# The hook copy is a real reader of its interpreter, proved under each before any row uses it.
expect_eq "2.0 the hook copy reports the interpreter it is run with (/bin/bash)" \
  "$SYS_VER" "$("$SYS_BASH" "$HOOK_COPY" 2>/dev/null)"
if [ -n "$ALT_BASH" ]; then
  expect_eq "2.0b …and the other one under the other interpreter" \
    "$ALT_VER" "$("$ALT_BASH" "$HOOK_COPY" 2>/dev/null)"
else
  skip "2.0b the hook copy under the other interpreter" "this host has only one bash"
fi

if [ -n "$ALT_BASH" ]; then
  hand_run "$ALT_BASH"
  expect_eq "2.1 a hand-run suite under the other interpreter reports the system version" \
    "$SYS_VER" "$HAND_VER"
  expect_eq "2.2 …by re-executing exactly once (the marker cannot loop)" "2" "$HAND_STARTS"
  expect_eq "2.3 …with its arguments intact across the re-exec" "one two" "$HAND_ARGV"
  expect_eq "2.4 …and the seam still answers the question it exists for" \
    "$REPO/hooks" "$HAND_ROOTS"

  # --- THE MARKER IS NOT THE TEST (critic K-4) ------------------------------
  # `tests/run.sh` exports BIONIC_TEST_INTERPRETER_PINNED to every descendant of
  # a run, so a hand-run started from inside a suite, a debugger, or a shell that
  # had once run the runner INHERITS it. While the guard trusted that marker the
  # pin was skipped and nothing said so: the suite reported bash 5.3 and there is
  # no stamp on the hand-run path to record which interpreter made the log.
  hand_run "$ALT_BASH" "1"
  expect_eq "2.4a an inherited pin marker does not defeat the pin" "$SYS_VER" "$HAND_VER"
  expect_eq "2.4b …and the re-exec still happens exactly once" "2" "$HAND_STARTS"
  expect_eq "2.4c …with its arguments still intact" "one two" "$HAND_ARGV"
  # PAIRED, so 2.4a is not a row that would pass under any interpreter: the same
  # marker with the SYSTEM bash must not provoke a second start.
  hand_run "$SYS_BASH" "1"
  expect_eq "2.4d …and a suite already under /bin/bash still does not re-exec" "1" "$HAND_STARTS"
else
  skip "2.1–2.4d hand-run parity under a foreign interpreter" "this host has only one bash"
fi

hand_run "$SYS_BASH"
expect_eq "2.5 a hand-run suite ALREADY under /bin/bash does not re-exec" "1" "$HAND_STARTS"
expect_eq "2.6 …and reports the system version" "$SYS_VER" "$HAND_VER"
echo ""

section "§2b hand-run parity reaches the children: the suite and all it starts get /bin/bash (T81)"
#
# The world tests/run.sh gives a suite is the pin first on PATH for the suite AND every process
# it starts. A suite typed at a prompt now gets the same world from the same function, which the
# seam calls on the hand-run path. Both ways a suite starts by hand are driven: under the other
# interpreter (the seam re-executes it) and already under /bin/bash (no re-exec; this second
# shape is the one that hid a 5.x-only `case` arm for weeks — the suite was 3.2 and every hook it
# spawned was not).
HAND_EXP_GIT="$(PATH="$HAND_GIVEN_PATH" command -v git 2>/dev/null || echo MISSING)"
HAND_EXP_JQ="$(PATH="$HAND_GIVEN_PATH" command -v jq 2>/dev/null || echo MISSING)"
for HAND_IN in "$ALT_BASH" "$SYS_BASH"; do
  [ -n "$HAND_IN" ] || continue
  HAND_SHAPE="started under /bin/bash"; [ "$HAND_IN" = "$SYS_BASH" ] || HAND_SHAPE="re-executed"
  hand_run "$HAND_IN"
  expect_eq "2.7 ($HAND_SHAPE) the suite itself reports the system version" "$SYS_VER" "$HAND_VER"
  if [ -n "$ALT_BASH" ]; then
    expect_eq "2.8 ($HAND_SHAPE) a child \`bash -c\` reports the system version" "$SYS_VER" "$HAND_CHILD"
    expect_eq "2.9 ($HAND_SHAPE) a child \`bash <a hook copy>\` reports the system version" \
      "$SYS_VER" "$HAND_HOOKVER"
  else
    skip "2.8–2.9 ($HAND_SHAPE) a child under a foreign interpreter first on PATH" "this host has only one bash"
  fi
  expect_eq "2.10 ($HAND_SHAPE) the first PATH entry the children get is the pin: bash -> /bin/bash" \
    "$SYS_BASH" "$HAND_FIRST_TARGET"
  expect_eq "2.11 ($HAND_SHAPE) …and the rest of PATH is the PATH the suite was given, unchanged" \
    "$HAND_GIVEN_PATH" "$HAND_REST"
  expect_eq "2.12 ($HAND_SHAPE) git resolves where it did" "$HAND_EXP_GIT" "$HAND_GIT"
  expect_eq "2.13 ($HAND_SHAPE) jq resolves where it did" "$HAND_EXP_JQ" "$HAND_JQ"
done
# NOT VACUOUS: git is on this host, so 2.12 compared two real paths.
expect_ne "2.14 git was found at all on the PATH the hand-run was given" "MISSING" "$HAND_EXP_GIT"
echo ""

section "§3 the planted 3.2 incompatibilities: the pin catches what it exists to catch (AC-10)"

PLANT_TREE="$TMPROOT/plant-tree"
mk_tree "$PLANT_TREE"

# (a) 3.2 ends the command substitution at the first `)` of the case pattern and leaks the
#     rest as text. Measured: 3.2.57 prints a parse error and garbage, exit 0; 5.3.15 prints A.
#
#     THE CONSTRUCT IS ASSEMBLED, NOT TYPED. tests/cross-gate-agreement.test.sh §BP forbids
#     the one-line `case` inside a command substitution anywhere under tests/ — the idiom is
#     banned in this tree precisely because `bash -n` cannot see it — and that lint reads
#     source text, so a planted copy typed literally here would trip the rule it is meant to
#     demonstrate. The same file's own mutation arm builds its copy through printf for the
#     same reason; this follows it.
PLANT_DOLLAR='$'
{ printf '#!/bin/bash\n'
  printf 'f() { echo "%s(case "%s1" in a) echo A;; *) echo other;; esac)"; }\n' \
    "$PLANT_DOLLAR" "$PLANT_DOLLAR"
  cat <<'PLANT_A_EOF'
got="$(f a 2>/dev/null)"
if [ "$got" = "A" ]; then echo "planted-case-leak: OK"; exit 0; fi
echo "planted-case-leak: expected [A], got [$got]"
exit 1
PLANT_A_EOF
} > "$PLANT_TREE/tests/planted-case-leak.test.sh"

# (b) the here-string temporary-assignment divergence (research-code-map §4.e). Hermetic:
#     the command the here-string's substitution needs is this file's own marker script, so
#     the row does not depend on jq being installed.
cat > "$PLANT_TREE/tests/planted-herestring.test.sh" <<'PLANT_B_EOF'
#!/bin/bash
BIN="$(mktemp -d)"; STRIP="$(mktemp -d)"
trap 'rm -rf "$BIN" "$STRIP"' EXIT
printf '#!/bin/bash\necho MARKER-OK\n' > "$BIN/probe_marker"; chmod +x "$BIN/probe_marker"
PATH="$BIN:$PATH"; export PATH
f() { probe_marker; }
for b in bash cat; do ln -sf "$(command -v "$b")" "$STRIP/$b"; done
got="$(PATH="$STRIP" cat <<< "$(f)" 2>/dev/null)"
if [ "$got" = "MARKER-OK" ]; then echo "planted-herestring: OK"; exit 0; fi
echo "planted-herestring: expected [MARKER-OK], got [$got]"
exit 1
PLANT_B_EOF

drive "$PLANT_TREE" "--serial"
expect_eq "3.1 the runner fails the run when a planted incompatibility is present" "1" "$DRV_RC"
expect_contains "3.2 …and reports both planted suites red" "Gating: 0 passed, 2 failed" "$DRV_OUT"
expect_contains "3.3 the quoted-\$( ) case leak is named" "- planted-case-leak.test.sh" "$DRV_OUT"
expect_contains "3.4 the here-string divergence is named" "- planted-herestring.test.sh" "$DRV_OUT"

# …and the same two files, unchanged, under the other interpreter: green. The planted
# constructs are 3.2/5.x DIVERGENCES, not broken scripts — which is the whole claim.
if [ -n "$ALT_BASH" ]; then
  ALT_A_OUT="$("$ALT_BASH" "$PLANT_TREE/tests/planted-case-leak.test.sh" 2>&1)"; ALT_A_RC=$?
  ALT_B_OUT="$("$ALT_BASH" "$PLANT_TREE/tests/planted-herestring.test.sh" 2>&1)"; ALT_B_RC=$?
  expect_eq "3.5 the case-leak file is GREEN under the other interpreter" "0" "$ALT_A_RC"
  expect_contains "3.6 …reporting the 5.x answer" "planted-case-leak: OK" "$ALT_A_OUT"
  expect_eq "3.7 the here-string file is GREEN under the other interpreter" "0" "$ALT_B_RC"
  expect_contains "3.8 …reporting the 5.x answer" "planted-herestring: OK" "$ALT_B_OUT"
else
  skip "3.5–3.8 the planted files are green under the other interpreter" "this host has only one bash"
fi
echo ""

section "§4 the environment stamp: the run says which environment it ran in (AC-3)"
#
# One line, twice: in the header, where a reader meets the run, and beside `Gating:`, where
# they read its verdict — a tail -5 of a captured log carries the environment with it.

drive "$PROBE_TREE" "--serial"
STAMPS="$(printf '%s\n' "$DRV_OUT" | grep -c '^env: ')"
expect_eq "4.1 the stamp is printed exactly twice" "2" "$STAMPS"
expect_regex "4.2 …with all four fields, in order" \
  '^env: os=[a-z]+ bash=[^ ]+ locale=[^ ]+ path=/' "$DRV_OUT"
STAMP_LINE="$(printf '%s\n' "$DRV_OUT" | grep '^env: ' | head -1)"
STAMP_TAIL="$(printf '%s\n' "$DRV_OUT" | grep '^env: ' | tail -1)"
expect_eq "4.3 the header stamp and the Gating stamp are the same line" "yes" \
  "$( [ -n "$STAMP_LINE" ] && [ "$STAMP_LINE" = "$STAMP_TAIL" ] && echo yes || echo no )"
expect_contains "4.4 the version it names is the interpreter the suites actually got" \
  "bash=$SYS_VER" "$STAMP_LINE"
expect_eq "4.5 the os field is this machine's" \
  "$(uname -s | tr '[:upper:]' '[:lower:]')" \
  "$(printf '%s\n' "$STAMP_LINE" | sed -n 's/^env: os=\([^ ]*\).*/\1/p')"
expect_eq "4.6 the locale field is the one the run inherited" \
  "${LC_ALL:-${LANG:-unset}}" \
  "$(printf '%s\n' "$STAMP_LINE" | sed -n 's/.* locale=\([^ ]*\).*/\1/p')"
# The path field names the launch directory the pin was built in — the same directory the
# probe suite saw first on its own PATH, so the stamp is reporting the mechanism and not a
# label somebody typed.
STAMP_PATH="$(printf '%s\n' "$STAMP_LINE" | sed -n 's/.* path=\(.*\)$/\1/p')"
expect_eq "4.7 the path field is the launch directory the suites were given" \
  "$(sed -n 's/^first_path_entry=//p' "$TMPROOT/probe.out")" "$STAMP_PATH"
# The Gating line still says what it always said, in the shape every reader and every
# close-out log greps for.
expect_contains "4.8 the Gating line is unchanged in shape" "Gating: 1 passed, 0 failed" "$DRV_OUT"
echo ""

section "§5 stderr-strict: a green suite that lost a command is red (the runner half of AC-14)"
#
# `set -uo pipefail` with no `-e` is this repo's suite convention, so a call to a helper
# that vanished is a `command not found` on stderr and nothing else — the suite finishes,
# its own tally never notices, and the runner prints ✓ PASS. The runner now reads the
# captured output of a suite that exited 0 and refuses it if the interpreter told it a
# command was missing.
#
# THE FALSE-POSITIVE GUARD is the second suite: several suites in the real roster PRINT the
# phrase in an assertion label (tests/dispatch-preflight.test.sh:771 asserts a fix command
# produces no 'command not found'). The arm matches the interpreter's own diagnostic shape,
# not the words, so a suite that merely quotes them stays green.

STRICT_TREE="$TMPROOT/strict-tree"
mk_tree "$STRICT_TREE"
cat > "$STRICT_TREE/tests/noisy.test.sh" <<'NOISY_EOF'
#!/bin/bash
set -uo pipefail
echo "PASS: 1: a helper that still exists"
bionic_helper_that_vanished "argument"
echo "PASS: 2: and the suite finished, none the wiser"
exit 0
NOISY_EOF
cat > "$STRICT_TREE/tests/quoting.test.sh" <<'QUOTING_EOF'
#!/bin/bash
set -uo pipefail
echo "PASS: fix-command run produces no 'command not found'"
echo "PASS: and no 'command not found' anywhere else either"
exit 0
QUOTING_EOF

drive "$STRICT_TREE" "--serial"
expect_eq "5.1 the run fails when a green suite lost a command" "1" "$DRV_RC"
expect_contains "5.2 …and the tally counts it failed" "Gating: 1 passed, 1 failed" "$DRV_OUT"
expect_contains "5.3 …naming the suite and why" "- noisy.test.sh" "$DRV_OUT"
expect_contains "5.4 …in words that send the reader to the missing command" "command not found" "$DRV_OUT"
expect_regex "5.5 a suite that only QUOTES the phrase stays green" \
  '^  quoting\.test\.sh +✓ PASS' "$DRV_OUT"
echo ""

section "§6 one pin, one owner: the runner and the seam pin through the same function (T81)"
#
# Two copies of the pin are two worlds: the runner's own pin code once gave a suite and its
# children /bin/bash while the seam, for a hand-run, gave the suite alone. The seam now owns
# the one function and the runner calls it. Proved both ways: the runner carries no pin code of
# its own, and a mutant of the seam's function — its PATH line removed, nothing else — takes
# the pin away from a suite the RUNNER launches and from the children of a suite run by HAND.
RUN_LN="$(grep -cE 'ln -sf? /bin/bash' "$REPO/tests/run.sh")"
SEAM_LN="$(grep -cE 'ln -sf? /bin/bash' "$REPO/tests/lib/resolve-roots.sh")"
expect_eq "6.1 the seam builds the pin (the extractor finds it there)" "1" "$SEAM_LN"
expect_eq "6.2 …and the runner builds none of its own" "0" "$RUN_LN"

MUT_TREE="$TMPROOT/mut-tree"
mk_tree "$MUT_TREE"
cp "$PROBE_TREE/tests/probe.test.sh" "$MUT_TREE/tests/probe.test.sh"
MUT_SEAM="$MUT_TREE/tests/lib/resolve-roots.sh"
anchor -E "$MUT_SEAM" '^  PATH="\$dir:\$PATH"$' 1
grep -vE '^  PATH="\$dir:\$PATH"$' "$REPO/tests/lib/resolve-roots.sh" > "$MUT_SEAM"
expect_eq "6.3 the mutant seam still parses" "0" "$(bash -n "$MUT_SEAM" >/dev/null 2>&1; echo $?)"
if [ -n "$ALT_BASH" ]; then
  : > "$TMPROOT/probe.out"
  drive "$MUT_TREE" "--serial"
  expect_eq "6.4 the mutant tree's runner still ran its probe (not vacuous)" "0" "$DRV_RC"
  expect_eq "6.5 the mutant takes the pin from a suite the RUNNER launches" "$ALT_VER" \
    "$(sed -n 's/^BASH_VERSION=//p' "$TMPROOT/probe.out")"
  mk_hand "$MUT_SEAM" "$TMPROOT/hand-mut.test.sh"
  hand_run "$SYS_BASH" "" "$TMPROOT/hand-mut.test.sh"
  expect_eq "6.6 …and from the children of a suite run by HAND" "$ALT_VER" "$HAND_CHILD"
  expect_eq "6.7 …while the mutant hand-run itself still ran (not vacuous)" "$SYS_VER" "$HAND_VER"
else
  skip "6.4–6.7 the seam mutant breaks the runner and the hand-run alike" "this host has only one bash"
fi
echo ""

section "§7 the pin's root is judged by the path itself, never by what a link points at (T87)"
#
# A hand-run's root is one predictable directory per user under the temp directory. The owner test
# `-O` follows a link, so a link planted at that path to any directory this user owns once passed,
# PATH carried the link's path, and repointing the link mid-run made a child `bash` run another
# script (review pass 75, drive e1b). Each state below is planted in a directory of this suite's
# own and handed to the function by path — never the real per-user root. A refusal returns
# non-zero, pins nothing, leaves PATH as it was and prints the seam's line naming the check, once.
T87_DIR="$TMPROOT/t87"
mkdir -p "$T87_DIR"; chmod 0755 "$T87_DIR"   # a parent no other user can write (T36; AC-10.6)
PIN_GIVEN="$HAND_GIVEN_PATH"

# pin_call <seam> <root> — call the seam's function in a fresh /bin/bash, leaving PIN_RC, PIN_PATH
# (PATH after the call) and PIN_ERR (the function's own stderr).
pin_call() {
  local out
  out="$(PATH="$PIN_GIVEN" /bin/bash -c '. "$1" >/dev/null 2>&1 || exit 9
    bionic_interpreter_pin "$2" 2>"$3"; echo "rc=$?"; echo "path=$PATH"' \
    pin-call "$1" "$2" "$TMPROOT/pin.err" 2>/dev/null)"
  PIN_RC="$(printf '%s\n' "$out" | sed -n 's/^rc=//p')"
  PIN_PATH="$(printf '%s\n' "$out" | sed -n 's/^path=//p')"
  PIN_ERR="$(cat "$TMPROOT/pin.err" 2>/dev/null)"
}
# pin_plant <state> <base> — plant one state under <base>; prints the root to hand the function.
pin_plant() {
  local base="$2"
  rm -rf "$base"; mkdir -p "$base/owned"; chmod 0755 "$base"; chmod 0700 "$base/owned"
  case "$1" in
    fresh)      ;;
    reuse)      mkdir -m 0700 "$base/root" "$base/root/pin"; ln -s /bin/bash "$base/root/pin/bash" ;;
    link-root)  ln -s "$base/owned" "$base/root" ;;
    link-pin)   mkdir -m 0700 "$base/root"; ln -s "$base/owned" "$base/root/pin" ;;
    mode-0777)  mkdir "$base/root"; chmod 0777 "$base/root" ;;
    mode-0770)  mkdir "$base/root"; chmod 0770 "$base/root" ;;
    file-root)  : > "$base/root" ;;
    bash-other) mkdir -m 0700 "$base/root" "$base/root/pin"; ln -s /bin/sh "$base/root/pin/bash" ;;
    runner)     printf '%s' "$(mktemp -d "$base/run.XXXXXX")"; return 0 ;;
  esac
  printf '%s' "$base/root"
}
there() { if [ -e "$1" ] || [ -L "$1" ]; then echo present; else echo absent; fi; }
inode() { ls -di "$1" 2>/dev/null | awk '{print $1}'; }
SEAM="$REPO/tests/lib/resolve-roots.sh"

# THE ACCEPTED STATES. Positives first, so every negative below has its extractor proven here.
R="$(pin_plant fresh "$T87_DIR/fresh")"
pin_call "$SEAM" "$R"
expect_eq "7.1 nothing at the root path: the function builds the pin and returns 0" "0" "$PIN_RC"
expect_eq "7.2 …PATH's first entry is <root>/pin and the rest of PATH is unchanged" \
  "$R/pin:$PIN_GIVEN" "$PIN_PATH"
expect_match "7.3 …the root it created is mode 0700" 'drwx------*' "$(ls -ld "$R" 2>/dev/null)"
expect_eq "7.4 …and pin/bash is a link to exactly /bin/bash" "/bin/bash" "$(readlink "$R/pin/bash")"
expect_eq "7.5 …with nothing printed" "" "$PIN_ERR"
expect_eq "7.5b …and the presence extractor the refusals read finds the pin it built" "present" "$(there "$R/pin")"

R="$(pin_plant reuse "$T87_DIR/reuse")"
T87_ROOT_INO="$(inode "$R")"; T87_LINK_INO="$(inode "$R/pin/bash")"
expect_nonempty "7.6 the inode extractor reads the planted link" "$T87_LINK_INO"
pin_call "$SEAM" "$R"
expect_eq "7.7 a plain 0700 root holding pin/bash -> /bin/bash is reused: returns 0" "0" "$PIN_RC"
expect_eq "7.8 …PATH's first entry is <root>/pin" "$R/pin:$PIN_GIVEN" "$PIN_PATH"
expect_eq "7.9 …the root is the same directory" "$T87_ROOT_INO" "$(inode "$R")"
expect_eq "7.10 …and the bash link is untouched, never replaced" "$T87_LINK_INO" "$(inode "$R/pin/bash")"

R="$(pin_plant runner "$T87_DIR/runner")"
pin_call "$SEAM" "$R"
expect_eq "7.11 tests/run.sh's kind of root (its run's mktemp -d) passes every check" "0" "$PIN_RC"
expect_eq "7.12 …and the runner's pin is what it was: <root>/pin first" "$R/pin:$PIN_GIVEN" "$PIN_PATH"

# THE REFUSED STATES. Each: non-zero, PATH as given, nothing built, the seam's line once, naming
# the check that failed.
t87_refused() {  # t87_refused <n> <state> <what the line names> [a path that must stay absent]
  pin_call "$SEAM" "$R"
  expect_ne "$1a $2: refused (non-zero)" "0" "$PIN_RC"
  expect_eq "$1b $2: …PATH is the PATH the call was given" "$PIN_GIVEN" "$PIN_PATH"
  [ -z "${4:-}" ] || expect_eq "$1c $2: …nothing was built (${4##*/t87/})" "absent" "$(there "$4")"
  expect_contains "$1d $2: …the seam's own line" \
    "resolve-roots.sh: cannot build the interpreter pin under $R" "$PIN_ERR"
  expect_contains "$1e $2: …naming the check that failed" "$3" "$PIN_ERR"
  expect_eq "$1f $2: …printed once" "1" "$(printf '%s\n' "$PIN_ERR" | grep -c 'cannot build the interpreter pin')"
}
R="$(pin_plant link-root "$T87_DIR/link-root")"
t87_refused 7.13 "a symlink at the root path, to a directory this user owns" \
  "$R is a symlink" "$T87_DIR/link-root/owned/pin"
R="$(pin_plant link-pin "$T87_DIR/link-pin")"
t87_refused 7.14 "a plain root with a symlink at <root>/pin" \
  "$R/pin is a symlink" "$T87_DIR/link-pin/owned/bash"
R="$(pin_plant mode-0777 "$T87_DIR/mode-0777")"
t87_refused 7.15 "a plain root writable by others (0777)" \
  "$R is writable by group or others" "$R/pin"
R="$(pin_plant mode-0770 "$T87_DIR/mode-0770")"
t87_refused 7.16 "a plain root writable by its group (0770)" \
  "$R is writable by group or others" "$R/pin"
R="$(pin_plant file-root "$T87_DIR/file-root")"
t87_refused 7.17 "a file at the root path" "$R is not a directory"
R="$(pin_plant bash-other "$T87_DIR/bash-other")"
t87_refused 7.18 "pin/bash a link to something other than /bin/bash" \
  "$R/pin/bash is not a link to /bin/bash"
expect_eq "7.18g …and the foreign link is left as it was, not replaced" "/bin/sh" "$(readlink "$R/pin/bash")"
# A root owned by another user cannot be made in a suite run without privileges (chown needs
# root), so the owner arm is not driven here; the mode arm (7.15, 7.16) is the test of that rule.
skip "7.19 a root owned by another user" "unprivileged: chown to another uid needs root; the mode arm 7.15-7.16 stands in"

# THE MUTANT: the root's -L test removed from a copy of the seam, nothing else. It must turn the
# symlink-root state and that state alone from refused to accepted — the other checks do not
# lean on it, and it is what stands between a planted link and PATH.
T87_MUT="$TMPROOT/t87-mutant-seam.sh"
anchor -E "$SEAM" '^  \[ ! -L "\$root" \] \|\| why=' 1
grep -vE '^  \[ ! -L "\$root" \] \|\| why=' "$SEAM" > "$T87_MUT"
expect_eq "7.20 the mutant seam still parses" "0" "$(bash -n "$T87_MUT" >/dev/null 2>&1; echo $?)"
T87_FLIPS=""
for T87_STATE in fresh reuse runner link-root link-pin mode-0777 mode-0770 file-root bash-other; do
  R="$(pin_plant "$T87_STATE" "$T87_DIR/real-$T87_STATE")"; pin_call "$SEAM" "$R"; T87_REAL="$PIN_RC"
  R="$(pin_plant "$T87_STATE" "$T87_DIR/mut-$T87_STATE")"; pin_call "$T87_MUT" "$R"
  [ "$T87_REAL" = "$PIN_RC" ] || T87_FLIPS="$T87_FLIPS $T87_STATE"
  [ "$T87_STATE" != link-root ] || T87_MUT_PATH="$PIN_PATH" T87_MUT_R="$R"
done
expect_eq "7.21 the mutant turns the symlink-root state, and that state alone, from refused to accepted" \
  " link-root" "$T87_FLIPS"
expect_eq "7.22 …and under the mutant PATH carries the link's path (the defect it guards)" \
  "$T87_MUT_R/pin:$PIN_GIVEN" "$T87_MUT_PATH"

# A REFUSED PIN STOPS A HAND RUN (wave-28 T36; AC-10.5), AND AN OPEN PARENT IS REFUSED (AC-10.6).
# The hand path used to call the function with `|| :`, so a refused pin printed its line and the
# suite ran on, unpinned. Now the suite stops before any check: the interfaces' line, the pin
# marker unset, exit 2. The hand-run's root is `$TMPDIR/bionic-interpreter-pin.<uid>`, so each
# drive points TMPDIR at a directory of this suite's own; the real per-user root is never touched.
# The parent rule: a root whose parent group or other can write, with no sticky bit, is refused,
# since anyone who can write the parent can rename the root away and plant their own.
mk_stop() {  # mk_stop <seam> <file> — a hand-run suite: one line before the seam, one check after
  { printf '#!/bin/bash\n'
    printf 'trap '\''echo "pinned=${BIONIC_TEST_INTERPRETER_PINNED:-unset}" >> "$STOP_OUT"'\'' EXIT\n'
    printf 'echo start >> "$STOP_OUT"\n'
    printf '. "%s"\n' "$1"
    printf 'echo "check ran" >> "$STOP_OUT"\n'
  } > "$2"
  chmod +x "$2"
}
# stop_run <suite> <tmpdir> — a hand run under /bin/bash; leaves STOP_RC, STOP_ERR, STOP_LOG
stop_run() {
  : > "$TMPROOT/stop.out"
  ( unset BIONIC_TEST_INTERPRETER_PINNED
    PATH="${STOP_PATH:-$HAND_GIVEN_PATH}" TMPDIR="$2" STOP_OUT="$TMPROOT/stop.out" \
    /bin/bash "$1" 2>"$TMPROOT/stop.err" >/dev/null )
  STOP_RC=$?
  STOP_ERR="$(cat "$TMPROOT/stop.err" 2>/dev/null)"
  STOP_LOG="$(cat "$TMPROOT/stop.out" 2>/dev/null)"
}
STOP_SUITE="$TMPROOT/stop.test.sh"
mk_stop "$SEAM" "$STOP_SUITE"
STOP_UID="$(id -u)"

# The positive first: a clean temp directory, the pin built, the check runs.
T36_OK="$T87_DIR/t36-ok"; mkdir -p "$T36_OK"; chmod 0700 "$T36_OK"
stop_run "$STOP_SUITE" "$T36_OK"
expect_eq "7.23 a hand run whose pin can be built exits 0" "0" "$STOP_RC"
expect_contains "7.23b …runs its check (the log extractor reads it)" "check ran" "$STOP_LOG"
expect_contains "7.23c …with the pin marker set" "pinned=1" "$STOP_LOG"
expect_eq "7.23d …and builds the pin under the temp directory it was given" "/bin/bash" \
  "$(readlink "$T36_OK/bionic-interpreter-pin.$STOP_UID/pin/bash" 2>/dev/null)"

# A planted symlink at the per-user root: the pin is refused, so the run stops.
T36_LINK="$T87_DIR/t36-link"; mkdir -p "$T36_LINK/owned"; chmod 0700 "$T36_LINK" "$T36_LINK/owned"
ln -s "$T36_LINK/owned" "$T36_LINK/bionic-interpreter-pin.$STOP_UID"
T36_ROOT="$T36_LINK/bionic-interpreter-pin.$STOP_UID"
stop_run "$STOP_SUITE" "$T36_LINK"
expect_eq "7.24 a hand run whose pin is refused exits 2" "2" "$STOP_RC"
expect_contains "7.24b …it started (the line before the seam is there)" "start" "$STOP_LOG"
expect_absent "7.24c …and ran no check" "check ran" "$STOP_LOG"
expect_contains "7.24d …the pin marker is unset" "pinned=unset" "$STOP_LOG"
expect_contains "7.24e …the line names the pin's path and the reason, as the interfaces give it" \
  "resolve-roots.sh: no interpreter pin at $T36_ROOT — $T36_ROOT is a symlink; remove $T36_ROOT or set TMPDIR, then run again" \
  "$STOP_ERR"
expect_eq "7.24f …printed once, and nothing else on stderr" "1" "$(printf '%s\n' "$STOP_ERR" | grep -c .)"

# The parent: open to others with no sticky bit is refused; the same mode with the sticky bit is not.
T36_OPEN="$T87_DIR/t36-open"; mkdir -p "$T36_OPEN"; chmod 0777 "$T36_OPEN"
T36_OPEN_ROOT="$T36_OPEN/bionic-interpreter-pin.$STOP_UID"
stop_run "$STOP_SUITE" "$T36_OPEN"
expect_eq "7.25 a temp directory others can write, with no sticky bit: the hand run exits 2" "2" "$STOP_RC"
expect_absent "7.25b …and runs no check" "check ran" "$STOP_LOG"
expect_contains "7.25c …naming the open parent" \
  "resolve-roots.sh: no interpreter pin at $T36_OPEN_ROOT — $T36_OPEN is writable by group or others and has no sticky bit; set TMPDIR to a directory only you can write, then run again" \
  "$STOP_ERR"
expect_eq "7.25d …and builds nothing there" "absent" "$(there "$T36_OPEN_ROOT")"
T36_GRP="$T87_DIR/t36-group"; mkdir -p "$T36_GRP"; chmod 0770 "$T36_GRP"
stop_run "$STOP_SUITE" "$T36_GRP"
expect_eq "7.26 a temp directory its group can write, with no sticky bit: exits 2" "2" "$STOP_RC"
expect_contains "7.26b …naming the open parent" "$T36_GRP is writable by group or others and has no sticky bit" "$STOP_ERR"
T36_STICKY="$T87_DIR/t36-sticky"; mkdir -p "$T36_STICKY"; chmod 1777 "$T36_STICKY"
stop_run "$STOP_SUITE" "$T36_STICKY"
expect_eq "7.27 a temp directory others can write WITH the sticky bit (/tmp's mode): exits 0" "0" "$STOP_RC"
expect_contains "7.27b …and runs its check" "check ran" "$STOP_LOG"
expect_eq "7.27c …with the pin built under it" "/bin/bash" \
  "$(readlink "$T36_STICKY/bionic-interpreter-pin.$STOP_UID/pin/bash" 2>/dev/null)"
# The function itself, as tests/run.sh calls it: an open parent is refused with the seam's line.
R="$T36_OPEN/fn-root"; pin_call "$SEAM" "$R"
expect_ne "7.28 the function refuses a root under an open parent (non-zero)" "0" "$PIN_RC"
expect_eq "7.28b …PATH is as given" "$PIN_GIVEN" "$PIN_PATH"
expect_contains "7.28c …naming the parent" "$T36_OPEN is writable by group or others and has no sticky bit" "$PIN_ERR"
R="$T36_STICKY/fn-root"; pin_call "$SEAM" "$R"
expect_eq "7.28d …and builds one under a sticky parent" "0" "$PIN_RC"

# A PARENT REACHED THROUGH A SYMLINK IS JUDGED BY WHERE IT LEADS (wave-28 T54; pass 25 adversarial #2).
# A link's own mode is always open (lrwxr-xr-x on macOS, lrwxrwxrwx on Linux), so `ls -ld` read the
# link and not the directory: a TMPDIR that is a link to an open, non-sticky directory built its pin
# there. The positive beside it: a link to a directory no other user can write still builds one.
T36_LNK_OPEN="$T87_DIR/t36-lnk-open"; ln -s "$T36_OPEN" "$T36_LNK_OPEN"
T36_LNK_OPEN_ROOT="$T36_LNK_OPEN/bionic-interpreter-pin.$STOP_UID"
stop_run "$STOP_SUITE" "$T36_LNK_OPEN"
expect_eq "7.31 a temp directory that is a link to an open, non-sticky directory: the hand run exits 2" "2" "$STOP_RC"
expect_absent "7.31b …and runs no check" "check ran" "$STOP_LOG"
expect_contains "7.31c …naming the link as the open parent, with the pin's existing line" \
  "resolve-roots.sh: no interpreter pin at $T36_LNK_OPEN_ROOT — $T36_LNK_OPEN is writable by group or others and has no sticky bit; set TMPDIR to a directory only you can write, then run again" \
  "$STOP_ERR"
expect_eq "7.31d …and builds nothing in the directory it leads to" "absent" "$(there "$T36_OPEN/bionic-interpreter-pin.$STOP_UID")"
T36_LNK_OK="$T87_DIR/t36-lnk-ok"; ln -s "$T36_OK" "$T36_LNK_OK"
stop_run "$STOP_SUITE" "$T36_LNK_OK"
expect_eq "7.32 a link to a directory only this user can write builds its pin (the refusal is the mode, not the link)" "0" "$STOP_RC"
expect_contains "7.32b …and runs its check" "check ran" "$STOP_LOG"
T36_LNK_STICKY="$T87_DIR/t36-lnk-sticky"; ln -s "$T36_STICKY" "$T36_LNK_STICKY"
stop_run "$STOP_SUITE" "$T36_LNK_STICKY"
expect_eq "7.32c a link to an open directory WITH the sticky bit builds its pin too" "0" "$STOP_RC"
# The mutant: the link followed no more (`ls -ld`, in the one predicate of an open directory, which
# reads the directory with `ls -ldLe` and, where ls has no -e, with `ls -ldL`: both lines are turned).
# The open-parent link is then accepted.
T36_MUT3="$TMPROOT/t36-mut-nolink.sh"
anchor "$SEAM" 'out="$(ls -ldLe "$1" 2>/dev/null)"' 1
anchor "$SEAM" '[ -n "$out" ] || out="$(ls -ldL "$1" 2>/dev/null)"' 1
sed -e 's|out="$(ls -ldLe "$1"|out="$(ls -lde "$1"|' -e 's|out="$(ls -ldL "$1"|out="$(ls -ld "$1"|' "$SEAM" > "$T36_MUT3"
expect_eq "7.33 the no-link mutant parses" "0" "$(bash -n "$T36_MUT3" >/dev/null 2>&1; echo $?)"
R="$T36_LNK_OK/mut-ok-root"; pin_call "$T36_MUT3" "$R"
expect_eq "7.33b …and builds a pin under a link to a closed directory (not vacuous)" "0" "$PIN_RC"
R="$T36_LNK_OPEN/mut-root"; pin_call "$T36_MUT3" "$R"
expect_eq "7.33c under the no-link mutant the open parent behind a link is accepted (the defect 7.31 guards)" "0" "$PIN_RC"
R="$T36_LNK_OPEN/fn-root"; pin_call "$SEAM" "$R"
expect_ne "7.33d control: the shipped function refuses that same root" "0" "$PIN_RC"

# A LINK ON THE PARENT'S PATH IS JUDGED BY THE DIRECTORY THAT HOLDS IT (wave-28 T56; AC-10.6; pass 27).
# T54 read where a parent link LEADS and never the directory the link sits in: a link held in a
# directory others can write, with no sticky bit, is replaced by whoever can write that directory, and
# the pin's `bash` is then theirs. The walk judges every link on the parent's path by its holder.
# Holders and targets are explicit modes, never the umask's.
T56_TGT="$T87_DIR/t56-tgt"; mkdir -p "$T56_TGT"; chmod 0700 "$T56_TGT"
T56_HOLD="$T87_DIR/t56-hold-open"; mkdir -p "$T56_HOLD"; chmod 0777 "$T56_HOLD"
ln -s "$T56_TGT" "$T56_HOLD/lnk"
T56_ROOT="$T56_HOLD/lnk/bionic-interpreter-pin.$STOP_UID"
stop_run "$STOP_SUITE" "$T56_HOLD/lnk"
expect_eq "7.34 a temp directory that is a link held in an open, non-sticky directory: the hand run exits 2" "2" "$STOP_RC"
expect_absent "7.34b …and runs no check" "check ran" "$STOP_LOG"
expect_contains "7.34c …naming the link and the directory that holds it, with the pin's existing line" \
  "resolve-roots.sh: no interpreter pin at $T56_ROOT — $T56_HOLD/lnk is a symlink held in $T56_HOLD, which is writable by group or others and has no sticky bit; set TMPDIR to a directory only you can write, then run again" \
  "$STOP_ERR"
expect_eq "7.34d …and builds nothing in the directory it leads to" "absent" "$(there "$T56_TGT/bionic-interpreter-pin.$STOP_UID")"
T56_STK="$T87_DIR/t56-hold-sticky"; mkdir -p "$T56_STK"; chmod 1777 "$T56_STK"
ln -s "$T56_TGT" "$T56_STK/lnk"
stop_run "$STOP_SUITE" "$T56_STK/lnk"
expect_eq "7.35 the same link held in an open directory WITH the sticky bit builds its pin" "0" "$STOP_RC"
expect_eq "7.35b …in the directory the link leads to" "/bin/bash" \
  "$(readlink "$T56_TGT/bionic-interpreter-pin.$STOP_UID/pin/bash" 2>/dev/null)"
T56_CLOSED="$T87_DIR/t56-hold-closed"; mkdir -p "$T56_CLOSED"; chmod 0700 "$T56_CLOSED"
ln -s "$T36_OPEN" "$T56_CLOSED/lnk"
stop_run "$STOP_SUITE" "$T56_CLOSED/lnk"
expect_eq "7.36 a link held in a closed directory that leads to an open one is still refused (7.31's case)" "2" "$STOP_RC"
expect_contains "7.36b …by where it leads" "$T56_CLOSED/lnk is writable by group or others and has no sticky bit" "$STOP_ERR"
# Two links in a chain. Outer: the open holder is the outer link's. Inner: the outer link is held
# in a closed directory and leads through a link that an open directory holds.
T56_MID="$T87_DIR/t56-mid"; mkdir -p "$T56_MID"; chmod 0700 "$T56_MID"
ln -s "$T56_TGT" "$T56_MID/inner"
ln -s "$T56_MID/inner" "$T56_HOLD/outer"
stop_run "$STOP_SUITE" "$T56_HOLD/outer"
expect_eq "7.37 two links in a chain, the outer one held in an open directory: exits 2" "2" "$STOP_RC"
expect_contains "7.37b …naming the outer link and its holder" "$T56_HOLD/outer is a symlink held in $T56_HOLD, which is writable" "$STOP_ERR"
ln -s "$T56_HOLD/lnk" "$T56_MID/outer2"
stop_run "$STOP_SUITE" "$T56_MID/outer2"
expect_eq "7.37c two links in a chain, the outer one held closed, the inner one in an open directory: exits 2" "2" "$STOP_RC"
expect_contains "7.37d …naming the inner link and its holder" "$T56_HOLD/lnk is a symlink held in $T56_HOLD, which is writable" "$STOP_ERR"
ln -s "$T56_HOLD" "$T56_MID/holder-link"; ln -s "$T56_TGT" "$T56_HOLD/lnk2"
stop_run "$STOP_SUITE" "$T56_MID/holder-link/lnk2"
expect_eq "7.37e a holder that is itself a link is judged where it leads, and that directory is open: exits 2" "2" "$STOP_RC"
expect_contains "7.37f …naming the link and the holder as the path spells it" \
  "$T56_MID/holder-link/lnk2 is a symlink held in $T56_MID/holder-link, which is writable" "$STOP_ERR"
# A cycle of links ends in a refusal, never a hang.
T56_CYC="$T87_DIR/t56-cycle"; mkdir -p "$T56_CYC"; chmod 0700 "$T56_CYC"; ln -s "$T56_CYC/a" "$T56_CYC/a"
stop_run "$STOP_SUITE" "$T56_CYC/a"
expect_eq "7.38 a link that leads back to itself is refused" "2" "$STOP_RC"
expect_contains "7.38b …naming the links" "$T56_CYC/a leads through more than 16 links" "$STOP_ERR"
# The mutants. (1) The walk's call removed: the open holder is accepted. (2) The holder judged with
# no sticky exemption: the sticky holder is refused. Each is proved to run before its claim is read.
T56_MUT1="$TMPROOT/t56-mut-walk.sh"
anchor "$SEAM" '_bionic_pin_links "$parent" 0' 1
grep -vF '_bionic_pin_links "$parent" 0' "$SEAM" > "$T56_MUT1"
expect_eq "7.39 the no-walk mutant parses" "0" "$(bash -n "$T56_MUT1" >/dev/null 2>&1; echo $?)"
R="$T56_CLOSED/lnk/mut-closed-root"; pin_call "$T56_MUT1" "$R"
expect_ne "7.39b …and still refuses the open parent behind a closed holder (not vacuous)" "0" "$PIN_RC"
R="$T56_HOLD/lnk/mut-root"; pin_call "$T56_MUT1" "$R"
expect_eq "7.39c under the no-walk mutant the link held in an open directory is accepted (the defect 7.34 guards)" "0" "$PIN_RC"
R="$T56_HOLD/lnk/fn-root"; pin_call "$SEAM" "$R"
expect_ne "7.39d control: the shipped function refuses that same root" "0" "$PIN_RC"
T56_MUT2="$TMPROOT/t56-mut-sticky.sh"
anchor "$SEAM" '    ?????????[tT]*) sticky=1 ;;' 1
grep -vF '    ?????????[tT]*) sticky=1 ;;' "$SEAM" > "$T56_MUT2"
expect_eq "7.40 the no-sticky mutant parses" "0" "$(bash -n "$T56_MUT2" >/dev/null 2>&1; echo $?)"
R="$T36_LNK_OK/mut-nosticky-root"; pin_call "$T56_MUT2" "$R"
expect_eq "7.40b …and builds a pin under a link held in a closed directory (not vacuous)" "0" "$PIN_RC"
R="$T56_STK/lnk/mut-root"; pin_call "$T56_MUT2" "$R"
expect_ne "7.40c under the no-sticky mutant the link held in a sticky directory is refused (the row 7.35 guards)" "0" "$PIN_RC"
R="$T56_STK/lnk/fn-root"; pin_call "$SEAM" "$R"
expect_eq "7.40d control: the shipped function builds under that same root" "0" "$PIN_RC"

# EVERY DIRECTORY ON THE PARENT'S PATH IS JUDGED, AND AN ACL COUNTS AS OPEN (wave-28 T57; AC-10.6; pass 29).
# T56 judged a component's holder only when the component was a link: `TMPDIR=<0777>/sub` with `sub`
# at 0700 still built a pin, and `sub` can be renamed away mid-run. And "open" was read from the mode
# string alone, so a macOS ACL letting everyone add and delete entries in a 0700 parent passed, and the
# root and pin the function makes inherited it. Mutants first (their anchors, then the rows that use them).
T57_MUT1="$TMPROOT/t57-mut-ancestor.sh"
anchor -E "$SEAM" '^    cur="\$cur/\$part"$' 1
awk '{print} $0 == "    cur=\"$cur/$part\"" {print "    [ -L \"$cur\" ] || continue"}' "$SEAM" > "$T57_MUT1"
T57_MUT2="$TMPROOT/t57-mut-acl.sh"
anchor "$SEAM" '  _bionic_pin_acl "$1" "$out"' 1
grep -vF '  _bionic_pin_acl "$1" "$out"' "$SEAM" > "$T57_MUT2"
# t57_line <tmpdir> <why> <remedy> — the hand run's one stderr line, as the seam prints it
t57_line() { printf 'resolve-roots.sh: no interpreter pin at %s — %s; %s, then run again' \
  "$1/bionic-interpreter-pin.$STOP_UID" "$2" "$3"; }
T57_FIX="set TMPDIR to a directory only you can write"
# Case A: a closed leaf inside an open, non-sticky directory, no link anywhere.
T57_OPEN="$T87_DIR/t57-open"; mkdir -p "$T57_OPEN/sub"; chmod 0700 "$T57_OPEN/sub"; chmod 0777 "$T57_OPEN"
T57_SUB="$T57_OPEN/sub"
stop_run "$STOP_SUITE" "$T57_SUB"
expect_eq "7.41 a temp directory that is closed but sits in an open, non-sticky directory: the hand run exits 2" "2" "$STOP_RC"
expect_absent "7.41b …and runs no check" "check ran" "$STOP_LOG"
expect_contains "7.41c …naming the open ancestor, and the remedy that helps" \
  "$(t57_line "$T57_SUB" "$T57_OPEN is writable by group or others and has no sticky bit" "$T57_FIX")" "$STOP_ERR"
expect_eq "7.41d …and builds nothing there" "absent" "$(there "$T57_SUB/bionic-interpreter-pin.$STOP_UID")"
R="$T57_SUB/fn-root"; pin_call "$SEAM" "$R"
expect_ne "7.41e the function refuses a root under that path (non-zero)" "0" "$PIN_RC"
expect_eq "7.41f …PATH is as given" "$PIN_GIVEN" "$PIN_PATH"
expect_contains "7.41g …naming the ancestor" "$T57_OPEN is writable by group or others and has no sticky bit" "$PIN_ERR"
# Case A2: the open directory is three levels above the parent.
T57_OPEN2="$T87_DIR/t57-open2"; mkdir -p "$T57_OPEN2/s1/s2/s3"; chmod 0777 "$T57_OPEN2"
chmod 0700 "$T57_OPEN2/s1" "$T57_OPEN2/s1/s2" "$T57_OPEN2/s1/s2/s3"
stop_run "$STOP_SUITE" "$T57_OPEN2/s1/s2/s3"
expect_eq "7.42 the same, three levels above the temp directory: exits 2" "2" "$STOP_RC"
expect_contains "7.42b …naming the open directory" \
  "$(t57_line "$T57_OPEN2/s1/s2/s3" "$T57_OPEN2 is writable by group or others and has no sticky bit" "$T57_FIX")" "$STOP_ERR"
# The same shape with the sticky bit builds (a shared /tmp over a private directory).
T57_STK="$T87_DIR/t57-sticky"; mkdir -p "$T57_STK/sub"; chmod 0700 "$T57_STK/sub"; chmod 1777 "$T57_STK"
stop_run "$STOP_SUITE" "$T57_STK/sub"
expect_eq "7.43 a closed temp directory in an open directory WITH the sticky bit builds its pin" "0" "$STOP_RC"
expect_eq "7.43b …in that directory" "/bin/bash" \
  "$(readlink "$T57_STK/sub/bionic-interpreter-pin.$STOP_UID/pin/bash" 2>/dev/null)"
R="$T57_STK/sub/mut-root"; pin_call "$T56_MUT2" "$R"
expect_ne "7.43c under the no-sticky mutant the sticky ancestor is refused (the row 7.43 guards)" "0" "$PIN_RC"
# The mutant for this half: the link-only short-circuit restored.
expect_eq "7.44 the no-ancestor mutant parses" "0" "$(bash -n "$T57_MUT1" >/dev/null 2>&1; echo $?)"
R="$T57_STK/sub/mut-ok-root"; pin_call "$T57_MUT1" "$R"
expect_eq "7.44b …and builds under a sticky ancestor (not vacuous)" "0" "$PIN_RC"
R="$T57_SUB/mut-root"; pin_call "$T57_MUT1" "$R"
expect_eq "7.44c under the no-ancestor mutant the open ancestor is accepted (the defect 7.41 guards)" "0" "$PIN_RC"
expect_eq "7.44d …and the pin is built there" "present" "$(there "$R/pin")"
R="$T57_SUB/fn-root2"; pin_call "$SEAM" "$R"
expect_ne "7.44e control: the shipped function refuses that same path" "0" "$PIN_RC"
# The ACL reader, on macOS. The rows skip with their reason where `chmod +a` is not there.
T57_ACLP="$T87_DIR/t57-aclprobe"; mkdir -p "$T57_ACLP"; chmod 0700 "$T57_ACLP"
T57_ACL=0
if chmod +a "everyone allow add_file,add_subdirectory,delete_child" "$T57_ACLP" 2>/dev/null \
   && [ "$(ls -lde "$T57_ACLP" 2>/dev/null | grep -c 'group:everyone allow add_file,add_subdirectory,delete_child')" = 1 ]; then
  T57_ACL=1
fi
if [ "$T57_ACL" = 1 ]; then
  T57_WHY_ACL="$T57_ACLP carries an ACL letting group:everyone add_file,add_subdirectory,delete_child"
  stop_run "$STOP_SUITE" "$T57_ACLP"
  expect_eq "7.45 a 0700 temp directory whose ACL lets everyone add and delete entries: the hand run exits 2" "2" "$STOP_RC"
  expect_absent "7.45b …and runs no check" "check ran" "$STOP_LOG"
  expect_contains "7.45c …naming the entry" "$(t57_line "$T57_ACLP" "$T57_WHY_ACL" "$T57_FIX")" "$STOP_ERR"
  expect_eq "7.45d …and builds nothing there" "absent" "$(there "$T57_ACLP/bionic-interpreter-pin.$STOP_UID")"
  # The same entry on an ancestor of a closed temp directory.
  mkdir -p "$T57_ACLP/up/sub"; chmod 0700 "$T57_ACLP/up" "$T57_ACLP/up/sub"; chmod -N "$T57_ACLP"
  chmod +a "everyone allow add_file,add_subdirectory,delete_child" "$T57_ACLP/up"
  stop_run "$STOP_SUITE" "$T57_ACLP/up/sub"
  expect_eq "7.45e the entry on an ancestor of the temp directory: exits 2" "2" "$STOP_RC"
  expect_contains "7.45f …naming the ancestor" \
    "$(t57_line "$T57_ACLP/up/sub" "$T57_ACLP/up carries an ACL letting group:everyone add_file,add_subdirectory,delete_child" "$T57_FIX")" "$STOP_ERR"
  R="$T57_ACLP/up/sub/mut-root"; pin_call "$T57_MUT2" "$R"
  expect_eq "7.45g under the no-ACL mutant the entry is accepted (the defect 7.45 guards)" "0" "$PIN_RC"
  expect_eq "7.45h …and the pin is built there" "present" "$(there "$R/pin")"
  R="$T57_ACLP/up/sub/fn-root"; pin_call "$SEAM" "$R"
  expect_ne "7.45i control: the shipped function refuses that same path" "0" "$PIN_RC"
  chmod -N "$T57_ACLP/up"
  # Entries that grant no one else the power to replace anything build: a deny, a read, the owner's own.
  T57_NO1="$T87_DIR/t57-acl-deny"; mkdir -p "$T57_NO1"; chmod 0700 "$T57_NO1"; chmod +a "everyone deny add_file,delete_child" "$T57_NO1"
  stop_run "$STOP_SUITE" "$T57_NO1"
  expect_eq "7.46 a 0700 temp directory whose ACL only DENIES builds its pin" "0" "$STOP_RC"
  chmod -N "$T57_NO1"
  T57_NO2="$T87_DIR/t57-acl-read"; mkdir -p "$T57_NO2"; chmod 0700 "$T57_NO2"; chmod +a "everyone allow read" "$T57_NO2"
  expect_eq "7.46b the ACL extractor reads the read-only entry" "1" "$(ls -lde "$T57_NO2" | grep -c 'group:everyone allow list')"
  stop_run "$STOP_SUITE" "$T57_NO2"
  expect_eq "7.46c …a read-only entry for everyone builds its pin" "0" "$STOP_RC"
  chmod -N "$T57_NO2"
  T57_NO3="$T87_DIR/t57-acl-owner"; mkdir -p "$T57_NO3"; chmod 0700 "$T57_NO3"
  chmod +a "$(id -un) allow add_file,add_subdirectory,delete_child" "$T57_NO3"
  expect_eq "7.46d the ACL extractor reads the owner's entry" "1" "$(ls -lde "$T57_NO3" | grep -c "user:$(id -un) allow add_file")"
  stop_run "$STOP_SUITE" "$T57_NO3"
  expect_eq "7.46e …an entry for the owner alone builds its pin" "0" "$STOP_RC"
  chmod -N "$T57_NO3"
  # An inheritable entry that does not apply to the parent itself: the root the function makes inherits it.
  T57_INH="$T87_DIR/t57-acl-inherit"; mkdir -p "$T57_INH"; chmod 0700 "$T57_INH"
  chmod +a "everyone allow add_file,add_subdirectory,delete_child,file_inherit,directory_inherit,only_inherit" "$T57_INH"
  T57_INH_ROOT="$T57_INH/bionic-interpreter-pin.$STOP_UID"
  stop_run "$STOP_SUITE" "$T57_INH"
  expect_eq "7.47 an inheritable entry on a 0700 temp directory: the made root inherits it, the hand run exits 2" "2" "$STOP_RC"
  expect_contains "7.47b …naming the root and the entry, with the root's own remedy" \
    "resolve-roots.sh: no interpreter pin at $T57_INH_ROOT — $T57_INH_ROOT carries an ACL letting group:everyone add_file,add_subdirectory,delete_child; remove $T57_INH_ROOT or set TMPDIR, then run again" \
    "$STOP_ERR"
  expect_eq "7.47c …and the root it made is removed" "absent" "$(there "$T57_INH_ROOT")"
  R="$T57_INH/fn-root"; pin_call "$SEAM" "$R"
  expect_ne "7.47d the function refuses it too" "0" "$PIN_RC"
  expect_eq "7.47e …PATH is as given" "$PIN_GIVEN" "$PIN_PATH"
  expect_eq "7.47f …and removes the root it made" "absent" "$(there "$R")"
  R="$T57_INH/mut-root"; pin_call "$T57_MUT2" "$R"
  expect_eq "7.47g under the no-ACL mutant the inheriting root is accepted (the defect 7.47 guards)" "0" "$PIN_RC"
  expect_eq "7.47h …and stays, with its pin" "present" "$(there "$R/pin")"
  chmod -N "$T57_INH" "$R" "$R/pin" 2>/dev/null
else
  skip "7.45 the ACL reader (macOS: a 0700 directory whose ACL lets everyone add and delete entries)" \
    "chmod +a is not available on this host, or ls -lde does not list the entry it made"
  skip "7.47 an inheritable ACL entry on the temp directory: the made root is refused and removed" \
    "chmod +a is not available on this host"
fi
chmod -N "$T57_ACLP" 2>/dev/null
# The reader for a host with getfacl (Linux), driven by a stub that answers for one directory only.
T57_STUB="$TMPROOT/t57-stub"; mkdir -p "$T57_STUB"
cat > "$T57_STUB/getfacl" <<'STUB'
#!/bin/sh
for d; do :; done
case "$d" in
  */t57-lx) cat "$T57_GETFACL_OUT" ;;
  *) if [ -f "$T59_GETFACL_DIR/${d##*/}" ]; then cat "$T59_GETFACL_DIR/${d##*/}"
     else printf 'user::rwx\ngroup::r-x\nother::r-x\n'
     fi ;;
esac
STUB
chmod +x "$T57_STUB/getfacl"
T57_LX="$T87_DIR/t57-lx"; mkdir -p "$T57_LX"; chmod 0700 "$T57_LX"
T57_GETFACL_OUT="$TMPROOT/t57-getfacl.out"; export T57_GETFACL_OUT
T59_GETFACL_DIR="$TMPROOT/t59-getfacl"; mkdir -p "$T59_GETFACL_DIR"; export T59_GETFACL_DIR  # answers by the directory's own name
t57_lx() {  # t57_lx <seam> <root-name> <acl text> — pin_call with the stub's answer for the parent
  printf '%b' "$3" > "$T57_GETFACL_OUT"
  PIN_GIVEN="$T57_STUB:$HAND_GIVEN_PATH"; pin_call "$1" "$T57_LX/$2"; PIN_GIVEN="$HAND_GIVEN_PATH"
}
t57_lx "$SEAM" lx-plain '# file: x\nuser::rwx\ngroup::---\nother::---\n'
expect_eq "7.48 getfacl lists only the owner's and the base entries: the pin is built" "0" "$PIN_RC"
expect_eq "7.48b …and is there" "present" "$(there "$T57_LX/lx-plain/pin")"
t57_lx "$SEAM" lx-named 'user::rwx\nuser:mallory:rw-\ngroup::---\nmask::rw-\nother::---\n'
expect_ne "7.48c a named user with w: the function refuses (non-zero)" "0" "$PIN_RC"
expect_contains "7.48d …naming the entry" "$T57_LX carries an ACL letting user:mallory write" "$PIN_ERR"
t57_lx "$SEAM" lx-group 'user::rwx\ngroup:wheel:-w-\nmask::rwx\nother::---\n'
expect_contains "7.48e a named group with w: refused, naming it" "$T57_LX carries an ACL letting group:wheel write" "$PIN_ERR"
t57_lx "$SEAM" lx-masked 'user::rwx\nuser:mallory:rwx\t#effective:r--\ngroup::---\nmask::r--\nother::---\n'
expect_eq "7.48f a named user whose effective rights lack w: the pin is built" "0" "$PIN_RC"
t57_lx "$SEAM" lx-default 'user::rwx\ngroup::---\nother::---\ndefault:user:mallory:rwx\n'
expect_eq "7.48g a default entry (it applies to what is made inside, not to the directory): the pin is built" "0" "$PIN_RC"
expect_eq "7.48h …and is there" "present" "$(there "$T57_LX/lx-default/pin")"
t57_lx "$T57_MUT2" lx-mut 'user::rwx\nuser:mallory:rw-\ngroup::---\nmask::rw-\nother::---\n'
expect_eq "7.48i under the no-ACL mutant the named user is accepted (the defect 7.48c guards)" "0" "$PIN_RC"
expect_eq "7.48j …and the pin is built there" "present" "$(there "$T57_LX/lx-mut/pin")"

# THE PREDICATE READS THE ACL'S BASE ENTRIES AS THE MODE, THE OWNER, AND THE RIGHTS THAT GRANT RIGHTS
# (wave-28 T59; AC-10.6; pass 32). Linux `getfacl -p` prints the base entries `user::`, `group::`,
# `other::` and `mask::` for EVERY directory: they repeat the mode and are not grants, so a sticky
# 1777 /tmp, which the mode check lets through, must not be refused for them. A default: entry is
# what CHILDREN inherit; a made root and pin are judged after they are made, where an inherited entry
# is an access entry, so default: entries are never counted (the macOS only_inherit rule). Whose
# directory it is can only be stubbed (no hermetic row can plant another uid's directory): the owner
# reader is `stat`, and the stub answers for one directory name and passes every other call through.
T59_ME="$(id -un)"
T59_MUT_BASE="$TMPROOT/t59-mut-base.sh"
anchor "$SEAM" '[ -n "$name" ] || continue' 1
sed 's/\[ -n "\$name" \] || continue.*/case "$line" in user::*|mask::*) continue ;; esac/' "$SEAM" > "$T59_MUT_BASE"  # the reader as T57 shipped it
t59_lx() {  # t59_lx <seam> <name> <mode> <getfacl text> [<root>] — a directory of this row's own, the stub's answer for it, pin_call under it
  local d="$T87_DIR/t59-lx-$2"
  mkdir -p "$d"; chmod "$3" "$d"
  printf '%b' "$4" > "$T59_GETFACL_DIR/t59-lx-$2"
  PIN_GIVEN="$T57_STUB:$HAND_GIVEN_PATH"; pin_call "$1" "$d/${5:-root}"; PIN_GIVEN="$HAND_GIVEN_PATH"
}
T59_BASE="# file: tmp\\n# owner: $T59_ME\\n# group: wheel\\n# flags: --t\\nuser::rwx\\ngroup::rwx\\nother::rwx\\n"
t59_lx "$SEAM" sticky 1777 "$T59_BASE"
expect_eq "7.49 a sticky 1777 directory whose getfacl lists only the base entries (a Linux /tmp): the pin is built" "0" "$PIN_RC"
expect_eq "7.49b …and is there" "present" "$(there "$T87_DIR/t59-lx-sticky/root/pin")"
expect_eq "7.49c the fixture is open by mode and sticky (the extractor reads the t)" "t" "$(ls -ld "$T87_DIR/t59-lx-sticky" | cut -c10)"
t59_lx "$T59_MUT_BASE" sticky-mut 1777 "$T59_BASE"
expect_ne "7.49d under the base-entries mutant the same directory is refused (the defect 7.49 guards)" "0" "$PIN_RC"
expect_contains "7.49e …naming the base entry" "$T87_DIR/t59-lx-sticky-mut carries an ACL letting group write" "$PIN_ERR"
t59_lx "$T59_MUT_BASE" closed 0700 "# file: d\\n# owner: $T59_ME\\nuser::rwx\\ngroup::---\\nother::---\\n"
expect_eq "7.49f …and builds a closed directory whose base entries hold no w (not vacuous)" "0" "$PIN_RC"
t59_lx "$SEAM" named 0700 "# file: d\\n# owner: $T59_ME\\n# group: wheel\\nuser::rwx\\nuser:bob:rwx\\ngroup::---\\nmask::rwx\\nother::---\\n"
expect_ne "7.50 a full getfacl listing with a named user holding w: refused" "0" "$PIN_RC"
expect_contains "7.50b …naming the entry" "$T87_DIR/t59-lx-named carries an ACL letting user:bob write" "$PIN_ERR"
t59_lx "$SEAM" named-me 0700 "# file: d\\n# owner: $T59_ME\\nuser::rwx\\nuser:$T59_ME:rwx\\ngroup::---\\nmask::rwx\\nother::---\\n"
expect_eq "7.50c the same entry naming the directory's own owner is the owner's: built" "0" "$PIN_RC"
t59_lx "$SEAM" named-me2 0700 "# file: d\\n# owner: someone-else\\nuser::rwx\\nuser:$T59_ME:rwx\\ngroup::---\\nmask::rwx\\nother::---\\n"
expect_contains "7.50d …and when the owner is another it is a grant" "$T87_DIR/t59-lx-named-me2 carries an ACL letting user:$T59_ME write" "$PIN_ERR"
t59_lx "$SEAM" default 0700 "# file: d\\n# owner: $T59_ME\\nuser::rwx\\ngroup::---\\nother::---\\ndefault:user::rwx\\ndefault:group::rwx\\ndefault:other::---\\n"
expect_eq "7.51 default entries on the parent are what children inherit, not a grant on the parent: built" "0" "$PIN_RC"
expect_eq "7.51b …and is there" "present" "$(there "$T87_DIR/t59-lx-default/root/pin")"
printf '%b' "user::rwx\\nuser:bob:rwx\\ngroup::---\\nmask::rwx\\nother::---\\n" > "$T59_GETFACL_DIR/inhroot"
t59_lx "$SEAM" inherit 0700 "user::rwx\\ngroup::---\\nother::---\\ndefault:user:bob:rwx\\n" inhroot
expect_ne "7.51c the made root carries what it inherited, as an access entry: refused" "0" "$PIN_RC"
expect_contains "7.51d …naming the root and the entry" "$T87_DIR/t59-lx-inherit/inhroot carries an ACL letting user:bob write" "$PIN_ERR"
expect_eq "7.51e …and the root it made is removed" "absent" "$(there "$T87_DIR/t59-lx-inherit/inhroot")"
# The owner. A directory on the path owned by neither this user nor root can rename what it holds.
T59_STUB="$TMPROOT/t59-stub"; mkdir -p "$T59_STUB"
cat > "$T59_STUB/stat" <<'STUB'
#!/bin/sh
for d; do :; done
if [ -f "$T59_STAT_DIR/${d##*/}" ]; then cat "$T59_STAT_DIR/${d##*/}"
else PATH=/usr/bin:/bin exec stat "$@"
fi
STUB
chmod +x "$T59_STUB/stat"
T59_STAT_DIR="$TMPROOT/t59-stat"; mkdir -p "$T59_STAT_DIR"; export T59_STAT_DIR
t59_own() {  # t59_own <seam> <root> — pin_call with the stat stub first on PATH
  PIN_GIVEN="$T59_STUB:$HAND_GIVEN_PATH"; pin_call "$1" "$2"; PIN_GIVEN="$HAND_GIVEN_PATH"
}
T59_OWN="$T87_DIR/t59-own"; mkdir -p "$T59_OWN/t59-anc/t59-sub"
chmod 0755 "$T59_OWN" "$T59_OWN/t59-anc"; chmod 0700 "$T59_OWN/t59-anc/t59-sub"
T59_ANC="$T59_OWN/t59-anc"; T59_SUB="$T59_ANC/t59-sub"
T59_OTHER=54321; [ "$T59_OTHER" != "$(id -u)" ] || T59_OTHER=54322
T59_WHY_OWN="is owned by uid $T59_OTHER, who is neither you nor root"
t59_own "$SEAM" "$T59_SUB/r1"
expect_eq "7.52 under the stub with no answer set, the real reader passes this user's own directories: built" "0" "$PIN_RC"
printf '%s\n' "$T59_OTHER" > "$T59_STAT_DIR/t59-anc"
t59_own "$SEAM" "$T59_SUB/r2"
expect_ne "7.52b an ancestor owned by another user, closed by mode: refused" "0" "$PIN_RC"
expect_contains "7.52c …naming the directory and its owner" "$T59_ANC $T59_WHY_OWN" "$PIN_ERR"
expect_eq "7.52d …PATH is as given" "$T59_STUB:$HAND_GIVEN_PATH" "$PIN_PATH"
expect_eq "7.52e …and nothing is built there" "absent" "$(there "$T59_SUB/r2")"
STOP_PATH="$T59_STUB:$HAND_GIVEN_PATH" stop_run "$STOP_SUITE" "$T59_SUB"; unset STOP_PATH
expect_eq "7.52f the hand run exits 2" "2" "$STOP_RC"
expect_contains "7.52g …naming the directory and its owner, with the path remedy" \
  "$(t57_line "$T59_SUB" "$T59_ANC $T59_WHY_OWN" "$T57_FIX")" "$STOP_ERR"
printf '0\n' > "$T59_STAT_DIR/t59-anc"
t59_own "$SEAM" "$T59_SUB/r3"
expect_eq "7.52h the same ancestor owned by root: built" "0" "$PIN_RC"
expect_eq "7.52i …and is there" "present" "$(there "$T59_SUB/r3/pin")"
rm -f "$T59_STAT_DIR/t59-anc"; printf '%s\n' "$T59_OTHER" > "$T59_STAT_DIR/t59-sub"
t59_own "$SEAM" "$T59_SUB/r4"
expect_contains "7.52j the parent itself owned by another user: refused, naming it" "$T59_SUB $T59_WHY_OWN" "$PIN_ERR"
rm -f "$T59_STAT_DIR/t59-sub"
T59_MUT_OWN="$TMPROOT/t59-mut-owner.sh"
anchor "$SEAM" 'case "$owner" in 0|"$UID") ;;' 1
grep -vF 'case "$owner" in 0|"$UID") ;;' "$SEAM" > "$T59_MUT_OWN"
expect_eq "7.53 the no-owner mutant parses" "0" "$(bash -n "$T59_MUT_OWN" >/dev/null 2>&1; echo $?)"
t59_own "$T59_MUT_OWN" "$T57_SUB/mut-owner-ctl"
expect_ne "7.53b …and still refuses an open ancestor (not vacuous)" "0" "$PIN_RC"
printf '%s\n' "$T59_OTHER" > "$T59_STAT_DIR/t59-anc"
t59_own "$T59_MUT_OWN" "$T59_SUB/mut-owner"
expect_eq "7.53c under the no-owner mutant the other user's ancestor is accepted (the defect 7.52b guards)" "0" "$PIN_RC"
expect_eq "7.53d …and the pin is built there" "present" "$(there "$T59_SUB/mut-owner/pin")"
t59_own "$SEAM" "$T59_SUB/r5"
expect_ne "7.53e control: the shipped function refuses that same path" "0" "$PIN_RC"
rm -f "$T59_STAT_DIR/t59-anc"
# The rights that grant rights, on macOS: writesecurity and chown let their holder grant itself the rest.
if [ "$T57_ACL" = 1 ]; then
  T59_MUT_WS="$TMPROOT/t59-mut-ws.sh"; T59_MUT_CH="$TMPROOT/t59-mut-chown.sh"
  anchor "$SEAM" ' writesecurity chown; do' 1
  sed 's/ writesecurity chown; do/ chown; do/' "$SEAM" > "$T59_MUT_WS"
  sed 's/ writesecurity chown; do/ writesecurity; do/' "$SEAM" > "$T59_MUT_CH"
  expect_eq "7.54 the two rights mutants parse" "0" "$(bash -n "$T59_MUT_WS" >/dev/null 2>&1 && bash -n "$T59_MUT_CH" >/dev/null 2>&1; echo $?)"
  for t59_right in writesecurity chown; do
    T59_RD="$T87_DIR/t59-right-$t59_right"; mkdir -p "$T59_RD"; chmod 0700 "$T59_RD"
    chmod +a "everyone allow $t59_right" "$T59_RD"
    expect_eq "7.55 [$t59_right] the ACL extractor reads the entry" "1" "$(ls -lde "$T59_RD" | grep -c "group:everyone allow $t59_right")"
    stop_run "$STOP_SUITE" "$T59_RD"
    expect_eq "7.55b [$t59_right] a 0700 temp directory whose ACL lets everyone have it: the hand run exits 2" "2" "$STOP_RC"
    expect_contains "7.55c [$t59_right] …naming the entry" \
      "$(t57_line "$T59_RD" "$T59_RD carries an ACL letting group:everyone $t59_right" "$T57_FIX")" "$STOP_ERR"
    expect_eq "7.55d [$t59_right] …and builds nothing there" "absent" "$(there "$T59_RD/bionic-interpreter-pin.$STOP_UID")"
    case "$t59_right" in writesecurity) t59_mut="$T59_MUT_WS" t59_ctl="$T59_MUT_CH" ;; *) t59_mut="$T59_MUT_CH" t59_ctl="$T59_MUT_WS" ;; esac
    pin_call "$t59_mut" "$T59_RD/mut-root"
    expect_eq "7.55e [$t59_right] with that right dropped from the list the entry is accepted (the defect 7.55b guards)" "0" "$PIN_RC"
    pin_call "$t59_ctl" "$T59_RD/ctl-root"
    expect_ne "7.55f [$t59_right] …and the other mutant still refuses it (not vacuous)" "0" "$PIN_RC"
    chmod -N "$T59_RD" 2>/dev/null
  done
else
  skip "7.54 the rights that grant rights (macOS: writesecurity and chown on a 0700 directory)" \
    "chmod +a is not available on this host"
fi

# THE MUTANTS. (1) The hand path's refusal turned back into `|| :`: the refused run goes on and
# runs its check. (2) The parent check removed: the open parent is accepted. Each mutant is proved
# to run before its claim is read.
T36_MUT1="$TMPROOT/t36-mut-runon.sh"
anchor "$SEAM" 'if ! bionic_interpreter_pin "$_bionic_pin_root" 2>/dev/null; then' 1
sed 's|if ! bionic_interpreter_pin "$_bionic_pin_root" 2>/dev/null; then|if ! { bionic_interpreter_pin "$_bionic_pin_root" \|\| :; }; then|' \
  "$SEAM" > "$T36_MUT1"
expect_eq "7.29 the run-on mutant parses" "0" "$(bash -n "$T36_MUT1" >/dev/null 2>&1; echo $?)"
mk_stop "$T36_MUT1" "$TMPROOT/stop-mut1.test.sh"
stop_run "$TMPROOT/stop-mut1.test.sh" "$T36_OK"
expect_eq "7.29b …and runs a hand suite whose pin is fine (not vacuous)" "0" "$STOP_RC"
stop_run "$TMPROOT/stop-mut1.test.sh" "$T36_LINK"
expect_contains "7.29c under the run-on mutant a refused pin runs its check (the defect 7.24c guards)" \
  "check ran" "$STOP_LOG"
T36_MUT2="$TMPROOT/t36-mut-parent.sh"
anchor "$SEAM" '[ -n "$why" ] || why="$(_bionic_pin_parent "$root")"' 1
grep -vF '[ -n "$why" ] || why="$(_bionic_pin_parent "$root")"' "$SEAM" > "$T36_MUT2"
expect_eq "7.30 the parent mutant parses" "0" "$(bash -n "$T36_MUT2" >/dev/null 2>&1; echo $?)"
R="$T87_DIR/t36-mut-sticky-root"; pin_call "$T36_MUT2" "$R"
expect_eq "7.30b …and builds a pin in a plain directory (not vacuous)" "0" "$PIN_RC"
R="$T36_OPEN/mut-root"; pin_call "$T36_MUT2" "$R"
expect_eq "7.30c under the parent mutant the open parent is accepted (the defect 7.28 guards)" "0" "$PIN_RC"
echo ""

echo "interpreter-pin: ${SKIPPED} skipped (see SKIP: rows above)"
finish
