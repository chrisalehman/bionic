#!/bin/bash
# THE PRINCIPLES ITEM — wave-27 task T7 (spec D16, REQ-9, AC-9.1 to AC-9.4).
#
# WHAT THIS SUITE OWNS. The `working-principles` setup item end to end: the
# marker block bionic owns in the user's own `<claude home>/CLAUDE.md`, the
# consented step in setup.sh that writes it, the row doctor.sh renders for it
# in three states, and the strip remove.sh performs through both of its doors.
# The text itself is shipped in payload/context/working-principles.md, between
# the same two markers, and every assertion here reads the shipped block out of
# that file rather than restating it — tests/docs-pins.test.sh §W27-95/96 owns
# what the text may say.
#
# THE FILE BELONGS TO THE USER. Every arm plants a CLAUDE.md of the user's own
# (or none at all) and asserts that every byte outside bionic's markers comes
# back exactly as planted: after a decline, after a closed input, after a yes,
# after a second yes, after an edit is kept, and after remove.
#
# FIXTURE FIDELITY (.claude/rules/test-harness.md, "Fixture fidelity"). Every
# fixture is SYNTHESIZED, and each pins one thing:
#   - the planted CLAUDE.md ends in a BLANK LINE, which is the shape a hand-kept
#     markdown file most often has and the one a strip that eats "the separator
#     above the block" gets wrong by one byte (AC-9.3's failure mode);
#   - the no-file home pins "created only on a yes", and "gone again after
#     remove", which a planted file cannot;
#   - the edited fixture is a consented block with one line added INSIDE the
#     markers, the state a user reaches by editing their own copy.
# The payload under test is the repo's own (BIONIC_PLUGIN_ROOT), read exactly as
# an installed plugin's scripts read theirs.
#
# ANTI-VACUITY (.claude/rules/test-harness.md, "Anti-vacuity"). The block
# extractor is proved non-empty on the shipped file before any arm reads an
# empty answer through it; every "unchanged" byte comparison sits beside a
# "changed" one on the same fixture; every doctor row is asserted non-empty
# before it is compared. No awk equality on the marker text: comparisons are
# bash `[ = ]` and `case`, in-process.
#
# HERMETIC. Every arm builds its own $HOME under $TMP and points the payload at
# it through HOME/BIONIC_CLAUDE_HOME. The real ~/.claude is never read or
# written. `claude` is a stub on a prepended PATH.
#
# Usage: bash tests/principles-item.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PAYLOAD="${REPO}/payload"
ENV_SH="${PAYLOAD}/scripts/lib/env.sh"
DETECT_SH="${PAYLOAD}/scripts/lib/detect.sh"
SETUP_SH="${PAYLOAD}/scripts/setup.sh"
DOCTOR_SH="${PAYLOAD}/scripts/doctor.sh"
REMOVE_SH="${PAYLOAD}/scripts/remove.sh"
SHIPPED="${PAYLOAD}/context/working-principles.md"

expect_same_bytes() {  # <label> <file-a> <file-b>
  if cmp -s "$2" "$3"; then ok "$1"; else no "$1" "$(diff "$2" "$3" 2>&1 | head -20)"; fi
}
expect_diff_bytes() {  # <label> <file-a> <file-b>
  if cmp -s "$2" "$3"; then no "$1" "the two files are byte-identical and should not be"; else ok "$1"; fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# The literals under test — spelled here, pinned to the payload below.
# ---------------------------------------------------------------------------
START_LIT='<!-- bionic:principles:start -->'
END_LIT='<!-- bionic:principles:end -->'
DOCTOR_ROW_LABEL='working principles'
ITEM='working-principles'

mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'STUB'
#!/bin/bash
case "$*" in
  "plugin list --json") echo '[]' ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$TMP/bin/claude"

# The user's own CLAUDE.md: a heading, a blank, a rule, and a TRAILING BLANK LINE.
plant_memory() {  # <file>
  mkdir -p "${1%/*}"
  printf '%s\n' '# My own notes' '' '- prefer small commits' '' > "$1"
}

new_home() {  # -> a fresh $HOME whose ~/.claude/CLAUDE.md is the planted file
  local sb
  sb="$(mktemp -d "$TMP/home-XXXXXX")"
  plant_memory "$sb/.claude/CLAUDE.md"
  printf '%s' "$sb"
}

new_bare_home() {  # -> a fresh $HOME with an empty ~/.claude and no CLAUDE.md
  local sb
  sb="$(mktemp -d "$TMP/bare-XXXXXX")"
  mkdir -p "$sb/.claude"
  printf '%s' "$sb"
}

# ---------------------------------------------------------------------------
# Extractors
# ---------------------------------------------------------------------------

# The lines BETWEEN the principles markers, written to <out>, one per line.
block_to() {  # <file> <out>
  local file="$1" out="$2" line inside=0
  : > "$out"
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$START_LIT" ]; then inside=1; continue; fi
    if [ "$line" = "$END_LIT" ];   then inside=0; continue; fi
    [ "$inside" = "1" ] && printf '%s\n' "$line" >> "$out"
  done < "$file"
  return 0
}

# Every line NOT between the markers, the markers excluded, written to <out>.
nonblock_to() {  # <file> <out>
  local file="$1" out="$2" line inside=0
  : > "$out"
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$START_LIT" ]; then inside=1; continue; fi
    if [ "$line" = "$END_LIT" ];   then inside=0; continue; fi
    [ "$inside" = "0" ] && printf '%s\n' "$line" >> "$out"
  done < "$file"
  return 0
}

count_lines_equal() {  # <file> <literal>
  local file="$1" want="$2" line n=0
  [ -f "$file" ] || { printf '0'; return 0; }
  while IFS= read -r line || [ -n "$line" ]; do
    [ "$line" = "$want" ] && n=$((n + 1))
  done < "$file"
  printf '%s' "$n"
}

# A single-quoted shell constant's contents, read out of a script in pure bash.
const_from() {  # <file> <name>
  local file="$1" name="$2" line v
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "${name}='"*)
        v="${line#${name}=\'}"; v="${v%\'}"
        printf '%s' "$v"; return 0 ;;
    esac
  done < "$file"
  return 1
}

report_row() {  # <report text> <label>
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in *"$2"*) printf '%s' "$line"; return 0 ;; esac
  done <<< "$1"
  return 0
}

sum_of() {  # <file> -> its cksum, or "absent"
  if [ -f "$1" ]; then cksum < "$1"; else printf 'absent'; fi
}

path_exists() {  # <path> -> yes|no
  if [ -e "$1" ]; then printf 'yes'; else printf 'no'; fi
}

# ---------------------------------------------------------------------------
# Drivers
# ---------------------------------------------------------------------------

# BOTH homes point at the sandbox in every driver: HOME, and CLAUDE_CONFIG_DIR as
# well as BIONIC_CLAUDE_HOME, so no resolution order can reach a real CLAUDE.md.
setup_run() {  # <home> <stdin text> — one narrowed setup, answers on stdin
  printf '%s' "$2" | HOME="$1" ZDOTDIR="$1" SHELL=/bin/zsh PATH="$TMP/bin:$PATH" \
    CLAUDE_CONFIG_DIR="$1/.claude" BIONIC_CLAUDE_HOME="$1/.claude" BIONIC_PLUGIN_ROOT="$PAYLOAD" \
    bash "$SETUP_SH" --only "$ITEM" 2>&1
}

setup_closed() {  # <home> — the same, with the answer channel closed
  HOME="$1" ZDOTDIR="$1" SHELL=/bin/zsh PATH="$TMP/bin:$PATH" \
    CLAUDE_CONFIG_DIR="$1/.claude" BIONIC_CLAUDE_HOME="$1/.claude" BIONIC_PLUGIN_ROOT="$PAYLOAD" \
    bash "$SETUP_SH" --only "$ITEM" </dev/null 2>&1
}

setup_plan() {  # <home> — the `--all` page, answer channel closed: printed, nothing done
  HOME="$1" ZDOTDIR="$1" SHELL=/bin/zsh PATH="$TMP/bin:$PATH" \
    CLAUDE_CONFIG_DIR="$1/.claude" BIONIC_CLAUDE_HOME="$1/.claude" BIONIC_PLUGIN_ROOT="$PAYLOAD" \
    bash "$SETUP_SH" --all </dev/null 2>&1
}

doctor_run() {  # <home>
  HOME="$1" ZDOTDIR="$1" SHELL=/bin/zsh PATH="$TMP/bin:$PATH" \
    CLAUDE_CONFIG_DIR="$1/.claude" BIONIC_CLAUDE_HOME="$1/.claude" BIONIC_PLUGIN_ROOT="$PAYLOAD" \
    BIONIC_DOCTOR_PROBE_SECONDS=15 \
    bash "$DOCTOR_SH" </dev/null 2>&1
}

remove_run() {  # <home> <answer> [script]
  local script="${3:-$REMOVE_SH}"
  printf '%s\n' "$2" | HOME="$1" ZDOTDIR="$1" SHELL=/bin/zsh PATH="$TMP/bin:$PATH" \
    CLAUDE_CONFIG_DIR="$1/.claude" BIONIC_CLAUDE_HOME="$1/.claude" \
    bash "$script" --only "$ITEM" 2>&1
}

detect_run() {  # <home> -> the detector's one fact line
  HOME="$1" SHELL=/bin/zsh PATH="$TMP/bin:$PATH" \
    CLAUDE_CONFIG_DIR="$1/.claude" BIONIC_CLAUDE_HOME="$1/.claude" BIONIC_PLUGIN_ROOT="$PAYLOAD" \
    bash -c '. "$1" && detect_working_principles' _ "$DETECT_SH" 2>&1
}

# env.sh sourced against the sandbox, then <snippet>. The snippet runs AFTER the
# source, so a `ulimit` in it limits the walk and not the read of the library.
lib_run() {  # <home> <snippet>
  HOME="$1" SHELL=/bin/zsh PATH="$TMP/bin:$PATH" \
    CLAUDE_CONFIG_DIR="$1/.claude" BIONIC_CLAUDE_HOME="$1/.claude" BIONIC_PLUGIN_ROOT="$PAYLOAD" \
    bash -c '. "$1"; eval "$2"' _ "$ENV_SH" "$2" 2>&1
}

# The memory file with <line> added as the last line INSIDE the markers.
edit_block() {  # <file> <line>
  local file="$1" add="$2" line
  : > "$file.edit"
  while IFS= read -r line || [ -n "$line" ]; do
    [ "$line" = "$END_LIT" ] && printf '%s\n' "$add" >> "$file.edit"
    printf '%s\n' "$line" >> "$file.edit"
  done < "$file"
  mv "$file.edit" "$file"
}

# ---------------------------------------------------------------------------
section "the shipped text and the extractor"
# ---------------------------------------------------------------------------

expect_true "the payload ships payload/context/working-principles.md" test -f "$SHIPPED"
block_to "$SHIPPED" "$TMP/shipped-block"
expect_true "the block extractor reads a non-empty block out of the shipped file" \
  test -s "$TMP/shipped-block"
expect_eq "the shipped file carries exactly one start marker" "1" "$(count_lines_equal "$SHIPPED" "$START_LIT")"
expect_eq "the shipped file carries exactly one end marker" "1" "$(count_lines_equal "$SHIPPED" "$END_LIT")"

# What a consented write must leave: the user's file, then the block.
{ printf '%s\n' "$START_LIT"; cat "$TMP/shipped-block"; printf '%s\n' "$END_LIT"; } > "$TMP/expected-block"

# ---------------------------------------------------------------------------
section "§SET: written only on a yes, inside the markers (AC-9.1)"
# ---------------------------------------------------------------------------

SB_NO="$(new_home)"; cp "$SB_NO/.claude/CLAUDE.md" "$TMP/planted.md"
NO_OUT="$(setup_run "$SB_NO" $'n\n')"
expect_same_bytes "SET: a declined offer leaves CLAUDE.md byte-identical" \
  "$TMP/planted.md" "$SB_NO/.claude/CLAUDE.md"
expect_contains "SET: the offer names the file it would change" "$SB_NO/.claude/CLAUDE.md" "$NO_OUT"

SB_EOF="$(new_home)"
setup_closed "$SB_EOF" >/dev/null 2>&1
expect_same_bytes "SET: a closed input writes nothing" "$TMP/planted.md" "$SB_EOF/.claude/CLAUDE.md"

SB_YES="$(new_home)"
YES_OUT="$(setup_run "$SB_YES" $'y\n')"
expect_diff_bytes "SET: an accepted offer does change CLAUDE.md (the twin of the two above)" \
  "$TMP/planted.md" "$SB_YES/.claude/CLAUDE.md"
block_to "$SB_YES/.claude/CLAUDE.md" "$TMP/yes-block"
expect_same_bytes "SET: the block holds exactly the shipped text" "$TMP/shipped-block" "$TMP/yes-block"
nonblock_to "$SB_YES/.claude/CLAUDE.md" "$TMP/yes-outside"
expect_same_bytes "SET: every line outside the block is the user's, in order" "$TMP/planted.md" "$TMP/yes-outside"
cat "$TMP/planted.md" "$TMP/expected-block" > "$TMP/yes-expected.md"
expect_same_bytes "SET: CLAUDE.md is the planted file plus the block, byte for byte" \
  "$TMP/yes-expected.md" "$SB_YES/.claude/CLAUDE.md"

cp "$SB_YES/.claude/CLAUDE.md" "$TMP/idem-before.md"
IDEM_OUT="$(setup_run "$SB_YES" $'y\n')"
expect_same_bytes "SET: a second run leaves CLAUDE.md byte-identical" "$TMP/idem-before.md" "$SB_YES/.claude/CLAUDE.md"
expect_eq "SET: one start marker after two runs" "1" "$(count_lines_equal "$SB_YES/.claude/CLAUDE.md" "$START_LIT")"
expect_absent "SET: a second run asks nothing" "[y/N]" "$IDEM_OUT"
expect_contains "SET: the first run did ask (the twin of the row above)" "[y/N]" "$YES_OUT"

# No file before: none after a no, one holding only the block after a yes.
SB_BARE="$(new_bare_home)"
setup_run "$SB_BARE" $'n\n' >/dev/null 2>&1
expect_eq "SET: a declined offer on a home with no CLAUDE.md creates none" "no" \
  "$(path_exists "$SB_BARE/.claude/CLAUDE.md")"
setup_run "$SB_BARE" $'y\n' >/dev/null 2>&1
expect_eq "SET: an accepted offer on the same home creates it" "yes" "$(path_exists "$SB_BARE/.claude/CLAUDE.md")"
expect_same_bytes "SET: a created CLAUDE.md holds exactly the block" \
  "$TMP/expected-block" "$SB_BARE/.claude/CLAUDE.md"

# ---------------------------------------------------------------------------
section "§DOCTOR: three states, each its own line, nothing changed (AC-9.2)"
# ---------------------------------------------------------------------------

SB_DA="$(new_home)"
SB_DP="$(new_home)"; setup_run "$SB_DP" $'y\n' >/dev/null 2>&1
SB_DE="$(new_home)"; setup_run "$SB_DE" $'y\n' >/dev/null 2>&1
edit_block "$SB_DE/.claude/CLAUDE.md" '- my own rule'

expect_eq "DOCTOR: detect reads the planted file as absent" \
  "env:working-principles state=absent" "$(detect_run "$SB_DA")"
expect_eq "DOCTOR: detect reads a consented block as present" \
  "env:working-principles state=present" "$(detect_run "$SB_DP")"
expect_eq "DOCTOR: detect reads an edited block as edited" \
  "env:working-principles state=edited" "$(detect_run "$SB_DE")"

SUM_A="$(sum_of "$SB_DA/.claude/CLAUDE.md")"
SUM_P="$(sum_of "$SB_DP/.claude/CLAUDE.md")"
SUM_E="$(sum_of "$SB_DE/.claude/CLAUDE.md")"
ROW_A="$(report_row "$(doctor_run "$SB_DA")" "$DOCTOR_ROW_LABEL")"
ROW_P="$(report_row "$(doctor_run "$SB_DP")" "$DOCTOR_ROW_LABEL")"
ROW_E="$(report_row "$(doctor_run "$SB_DE")" "$DOCTOR_ROW_LABEL")"

expect_nonempty "DOCTOR: a row is rendered when the block is absent" "$ROW_A"
expect_nonempty "DOCTOR: a row is rendered when the block is present" "$ROW_P"
expect_nonempty "DOCTOR: a row is rendered when the block is edited" "$ROW_E"
expect_ne "DOCTOR: the absent and present rows differ" "$ROW_A" "$ROW_P"
expect_ne "DOCTOR: the edited and present rows differ — an edit never reads as present" "$ROW_P" "$ROW_E"
expect_ne "DOCTOR: the edited and absent rows differ" "$ROW_A" "$ROW_E"
expect_contains "DOCTOR: the edited row says edited" "edited" "$ROW_E"
expect_contains "DOCTOR: the absent row routes the reader to setup" "/bionic:setup" "$ROW_A"
expect_absent "DOCTOR: the present row does not route to setup" "/bionic:setup" "$ROW_P"
expect_eq "DOCTOR: doctor left the absent-state file unchanged" "$SUM_A" "$(sum_of "$SB_DA/.claude/CLAUDE.md")"
expect_eq "DOCTOR: doctor left the present-state file unchanged" "$SUM_P" "$(sum_of "$SB_DP/.claude/CLAUDE.md")"
expect_eq "DOCTOR: doctor left the edited-state file unchanged" "$SUM_E" "$(sum_of "$SB_DE/.claude/CLAUDE.md")"
expect_ne "DOCTOR: the checksum discriminates (the edited file is not the present one)" "$SUM_P" "$SUM_E"

# ---------------------------------------------------------------------------
section "§REMOVE: the file comes back to its pre-setup bytes (AC-9.3)"
# ---------------------------------------------------------------------------

ENV_START="$(const_from "$ENV_SH" PRINCIPLES_START)" || ENV_START=""
ENV_END="$(const_from "$ENV_SH" PRINCIPLES_END)"     || ENV_END=""
RM_START="$(const_from "$REMOVE_SH" RM_PRINCIPLES_START)" || RM_START=""
RM_END="$(const_from "$REMOVE_SH" RM_PRINCIPLES_END)"     || RM_END=""
expect_nonempty "REMOVE: env.sh carries a PRINCIPLES_START constant" "$ENV_START"
expect_nonempty "REMOVE: remove.sh carries an RM_PRINCIPLES_START copy" "$RM_START"
expect_eq "REMOVE: env.sh's start marker is the interface's literal" "$START_LIT" "$ENV_START"
expect_eq "REMOVE: env.sh's end marker is the interface's literal" "$END_LIT" "$ENV_END"
expect_eq "REMOVE: remove.sh's start copy equals the library's" "$ENV_START" "$RM_START"
expect_eq "REMOVE: remove.sh's end copy equals the library's" "$ENV_END" "$RM_END"

SB_R="$(new_home)"
setup_run "$SB_R" $'y\n' >/dev/null 2>&1
block_to "$SB_R/.claude/CLAUDE.md" "$TMP/r-block"
expect_true "REMOVE: the block is there to remove" test -s "$TMP/r-block"
remove_run "$SB_R" n >/dev/null 2>&1
expect_eq "REMOVE: a declined remove keeps the block" "1" "$(count_lines_equal "$SB_R/.claude/CLAUDE.md" "$START_LIT")"
R_OUT="$(remove_run "$SB_R" y)"
expect_same_bytes "REMOVE: after remove CLAUDE.md equals its pre-setup bytes, trailing blank line included" \
  "$TMP/planted.md" "$SB_R/.claude/CLAUDE.md"
expect_eq "REMOVE: no start marker survives" "0" "$(count_lines_equal "$SB_R/.claude/CLAUDE.md" "$START_LIT")"
expect_contains "REMOVE: remove names the file it changed" "$SB_R/.claude/CLAUDE.md" "$R_OUT"

# The standalone door: the script alone, no scripts/lib beside it.
mkdir -p "$TMP/standalone"; cp "$REMOVE_SH" "$TMP/standalone/remove.sh"
SB_RS="$(new_home)"
setup_run "$SB_RS" $'y\n' >/dev/null 2>&1
expect_eq "REMOVE: the standalone arm has a block to remove" "1" "$(count_lines_equal "$SB_RS/.claude/CLAUDE.md" "$START_LIT")"
remove_run "$SB_RS" y "$TMP/standalone/remove.sh" >/dev/null 2>&1
expect_same_bytes "REMOVE: the standalone door restores the same pre-setup bytes" \
  "$TMP/planted.md" "$SB_RS/.claude/CLAUDE.md"

# A CLAUDE.md setup created is taken back off entirely, by both doors.
SB_RB="$(new_bare_home)"; setup_run "$SB_RB" $'y\n' >/dev/null 2>&1
SB_RBS="$(new_bare_home)"; setup_run "$SB_RBS" $'y\n' >/dev/null 2>&1
expect_eq "REMOVE: setup created the file on the bare home" "yes" "$(path_exists "$SB_RB/.claude/CLAUDE.md")"
remove_run "$SB_RB" y >/dev/null 2>&1
remove_run "$SB_RBS" y "$TMP/standalone/remove.sh" >/dev/null 2>&1
expect_eq "REMOVE: a CLAUDE.md that held only the block is gone after remove" "no" \
  "$(path_exists "$SB_RB/.claude/CLAUDE.md")"
# The standalone door has no shipped text, so it cannot tell the block is
# unedited, and the deletion rule needs that (wave-27 T40): the file stays, empty.
expect_eq "REMOVE: …while the standalone door leaves it in place, emptied" "yes 0" \
  "$(path_exists "$SB_RBS/.claude/CLAUDE.md") $(wc -c < "$SB_RBS/.claude/CLAUDE.md" 2>/dev/null | tr -d ' ')"
expect_eq "REMOVE: the claude home itself survives" "yes" "$(path_exists "$SB_RB/.claude")"

# ---------------------------------------------------------------------------
section "§EDITED: an edit is never discarded silently (AC-9.4)"
# ---------------------------------------------------------------------------

SB_E="$(new_home)"
setup_run "$SB_E" $'y\n' >/dev/null 2>&1
edit_block "$SB_E/.claude/CLAUDE.md" '- my own rule'
cp "$SB_E/.claude/CLAUDE.md" "$TMP/edited.md"
expect_diff_bytes "EDITED: the fixture really is edited" "$TMP/idem-before.md" "$TMP/edited.md"

E_NO_OUT="$(setup_run "$SB_E" $'n\n')"
expect_contains "EDITED: setup prints the difference as a unified diff" "@@" "$E_NO_OUT"
expect_contains "EDITED: the difference names the user's own line" "my own rule" "$E_NO_OUT"
expect_same_bytes "EDITED: a no keeps the edit, byte for byte" "$TMP/edited.md" "$SB_E/.claude/CLAUDE.md"

setup_closed "$SB_E" >/dev/null 2>&1
expect_same_bytes "EDITED: a closed input keeps the edit" "$TMP/edited.md" "$SB_E/.claude/CLAUDE.md"

E_YES_OUT="$(setup_run "$SB_E" $'y\n')"
expect_contains "EDITED: the yes arm also showed the difference before asking" "my own rule" "$E_YES_OUT"
block_to "$SB_E/.claude/CLAUDE.md" "$TMP/e-block"
expect_same_bytes "EDITED: a yes replaces the block with the shipped text" "$TMP/shipped-block" "$TMP/e-block"
nonblock_to "$SB_E/.claude/CLAUDE.md" "$TMP/e-outside"
expect_same_bytes "EDITED: …and leaves every line outside it as it was" "$TMP/planted.md" "$TMP/e-outside"

# ---------------------------------------------------------------------------
section "§CUT-SHORT: a write that fails partway changes nothing (wave-27 T40)"
# ---------------------------------------------------------------------------
#
# `ulimit -f` in the child, with SIGXFSZ ignored so the write FAILS rather than
# killing the process: the shape a full disk takes. The user's file is larger
# than the limit, so the staged copy is cut short partway through it.

plant_big() {  # <file> — 300 lines of the user's own, about 4 KB
  local i
  mkdir -p "${1%/*}"
  for i in $(seq 1 300); do printf 'user line %s of my own notes\n' "$i"; done > "$1"
}

SB_W="$(new_bare_home)"; plant_big "$SB_W/.claude/CLAUDE.md"
setup_run "$SB_W" $'y\n' >/dev/null 2>&1
expect_eq "CUT-SHORT: the fixture holds the block" "1" "$(count_lines_equal "$SB_W/.claude/CLAUDE.md" "$START_LIT")"
cp "$SB_W/.claude/CLAUDE.md" "$TMP/w-before.md"
W_LIB="$(lib_run "$SB_W" 'trap "" XFSZ; ulimit -f 2; principles_unset; echo "rc=$?"')"
expect_contains "CUT-SHORT: the library's strip reports the failed write" "rc=1" "$W_LIB"
expect_same_bytes "CUT-SHORT: …and the file is byte-identical to before it" "$TMP/w-before.md" "$SB_W/.claude/CLAUDE.md"
expect_eq "CUT-SHORT: …and no staged copy is left beside it" "no" \
  "$(path_exists "$SB_W/.claude/CLAUDE.md.bionic.tmp")"
W_RM="$(trap '' XFSZ; ulimit -f 2; remove_run "$SB_W" y)"
expect_same_bytes "CUT-SHORT: remove's payload door leaves the file byte-identical" "$TMP/w-before.md" "$SB_W/.claude/CLAUDE.md"
expect_contains "CUT-SHORT: …and says it could not" "could not" "$W_RM"
mkdir -p "$TMP/standalone"; cp "$REMOVE_SH" "$TMP/standalone/remove.sh"
W_RS="$(trap '' XFSZ; ulimit -f 2; remove_run "$SB_W" y "$TMP/standalone/remove.sh")"
expect_same_bytes "CUT-SHORT: the standalone door leaves the file byte-identical" "$TMP/w-before.md" "$SB_W/.claude/CLAUDE.md"
expect_contains "CUT-SHORT: …and says it could not" "could not" "$W_RS"
remove_run "$SB_W" y >/dev/null 2>&1
expect_eq "CUT-SHORT: the same remove with room to write does strip the block (the twin)" "0" \
  "$(count_lines_equal "$SB_W/.claude/CLAUDE.md" "$START_LIT")"

SB_WS="$(new_bare_home)"; plant_big "$SB_WS/.claude/CLAUDE.md"; cp "$SB_WS/.claude/CLAUDE.md" "$TMP/ws-before.md"
WS_OUT="$(trap '' XFSZ; ulimit -f 2; setup_run "$SB_WS" $'y\n')"
expect_same_bytes "CUT-SHORT: a setup write cut short leaves the file byte-identical" "$TMP/ws-before.md" "$SB_WS/.claude/CLAUDE.md"
expect_contains "CUT-SHORT: …and setup says it could not write it" "could not write" "$WS_OUT"

# ---------------------------------------------------------------------------
section "§MALFORMED: markers that do not pair up are refused by every door (wave-27 T40)"
# ---------------------------------------------------------------------------
#
# Each shape is the user's file; each door is answered yes; each must write
# nothing and name the line it found. Probe shapes from review pass 9 (probe-lib
# cases 3, 4, 5, 6).

plant_shape() {  # <file> <shape>
  mkdir -p "${1%/*}"
  case "$2" in
    start-only)   printf '%s\n' 'top' "$START_LIT" 'my body' '## My own notes' 'keep me' > "$1" ;;
    end-only)     printf '%s\n' 'top' "$END_LIT" 'mine after it' > "$1" ;;
    out-of-order) printf '%s\n' 'top' "$END_LIT" 'middle mine' "$START_LIT" 'bottom mine' > "$1" ;;
    two-blocks)   { printf '%s\n' 'top'; cat "$TMP/expected-block"; printf '%s\n' 'between mine'; cat "$TMP/expected-block"; printf '%s\n' 'bottom mine'; } > "$1" ;;
    fenced-start) printf '%s\n' '# notes' '```' "$START_LIT" '```' 'after fence mine' > "$1" ;;
  esac
}
# The line each shape's first fault is on.
shape_line() {
  case "$1" in
    start-only) echo 2 ;; end-only) echo 2 ;; out-of-order) echo 2 ;; fenced-start) echo 3 ;;
    two-blocks) echo "$(( $(wc -l < "$TMP/expected-block") + 3 ))" ;;  # top, the block, a line, then the second start
  esac
}

for SHAPE in start-only end-only out-of-order two-blocks fenced-start; do
  SB_M="$(new_bare_home)"; plant_shape "$SB_M/.claude/CLAUDE.md" "$SHAPE"
  cp "$SB_M/.claude/CLAUDE.md" "$TMP/m-before.md"
  L="$(shape_line "$SHAPE")"
  expect_eq "MALFORMED ${SHAPE}: detect reads it as malformed" \
    "env:working-principles state=malformed" "$(detect_run "$SB_M")"
  M_SET="$(setup_run "$SB_M" $'y\ny\n')"
  expect_same_bytes "MALFORMED ${SHAPE}: setup answered yes writes nothing" "$TMP/m-before.md" "$SB_M/.claude/CLAUDE.md"
  expect_contains "MALFORMED ${SHAPE}: setup names the line it found" "line ${L}:" "$M_SET"
  M_RM="$(remove_run "$SB_M" y)"
  expect_same_bytes "MALFORMED ${SHAPE}: remove answered yes writes nothing" "$TMP/m-before.md" "$SB_M/.claude/CLAUDE.md"
  expect_contains "MALFORMED ${SHAPE}: remove names the line it found" "line ${L}:" "$M_RM"
  # The library's walk (setup) and remove.sh's copy name the same faults, word for word.
  M_SET_F="$(printf '%s\n' "$M_SET" | sed -n 's/^ *\(line [0-9][0-9]*: \)/\1/p')"
  M_RM_F="$(printf '%s\n' "$M_RM" | sed -n 's/^ *\(line [0-9][0-9]*: \)/\1/p')"
  expect_nonempty "MALFORMED ${SHAPE}: the fault extractor reads setup's lines" "$M_SET_F"
  expect_eq "MALFORMED ${SHAPE}: remove.sh's copy of the walk names the same faults as the library" "$M_SET_F" "$M_RM_F"
  M_RS="$(remove_run "$SB_M" y "$TMP/standalone/remove.sh")"
  expect_same_bytes "MALFORMED ${SHAPE}: the standalone door writes nothing" "$TMP/m-before.md" "$SB_M/.claude/CLAUDE.md"
  expect_contains "MALFORMED ${SHAPE}: the standalone door names the line it found" "line ${L}:" "$M_RS"
done

SB_MD="$(new_bare_home)"; plant_shape "$SB_MD/.claude/CLAUDE.md" start-only
ROW_M="$(report_row "$(doctor_run "$SB_MD")" "$DOCTOR_ROW_LABEL")"
expect_nonempty "MALFORMED: doctor renders a row" "$ROW_M"
expect_contains "MALFORMED: doctor's row is a fault" "✗" "$ROW_M"
expect_contains "MALFORMED: doctor's row says malformed" "malformed" "$ROW_M"

# A marker QUOTED in prose is not a marker: only a whole line is.
SB_Q="$(new_bare_home)"
printf '%s\n' "Mark it with \`${START_LIT}\` and an end line." 'more of mine' > "$SB_Q/.claude/CLAUDE.md"
cp "$SB_Q/.claude/CLAUDE.md" "$TMP/q-before.md"
expect_eq "QUOTED: a marker quoted in prose reads as no block" \
  "env:working-principles state=absent" "$(detect_run "$SB_Q")"
Q_RM="$(remove_run "$SB_Q" y)"
expect_absent "QUOTED: remove does not ask about a quoted marker" "[y/N]" "$Q_RM"
expect_same_bytes "QUOTED: …and leaves the file byte-identical" "$TMP/q-before.md" "$SB_Q/.claude/CLAUDE.md"
setup_run "$SB_Q" $'y\n' >/dev/null 2>&1
Q_RM2="$(remove_run "$SB_Q" n)"
expect_contains "QUOTED: with a real block beside it, remove does ask (the twin)" "[y/N]" "$Q_RM2"
nonblock_to "$SB_Q/.claude/CLAUDE.md" "$TMP/q-outside"
expect_same_bytes "QUOTED: setup kept the quoting line as the user's own" "$TMP/q-before.md" "$TMP/q-outside"

# A well-formed pair inside a code fence IS a block, like any other.
SB_F="$(new_bare_home)"
printf '%s\n' '```' "$START_LIT" 'an example body' "$END_LIT" '```' > "$SB_F/.claude/CLAUDE.md"
expect_eq "FENCED: a whole pair inside a fence reads as a block (edited)" \
  "env:working-principles state=edited" "$(detect_run "$SB_F")"

# ---------------------------------------------------------------------------
section "§REMOVE-EDITED: remove shows an edit and deletes it only on a yes (AC-9.4)"
# ---------------------------------------------------------------------------

SB_RE="$(new_home)"; setup_run "$SB_RE" $'y\n' >/dev/null 2>&1
edit_block "$SB_RE/.claude/CLAUDE.md" '- my own rule'
cp "$SB_RE/.claude/CLAUDE.md" "$TMP/re-before.md"
RE_NO="$(remove_run "$SB_RE" n)"
expect_contains "REMOVE-EDITED: remove prints the difference as a unified diff" "@@" "$RE_NO"
expect_contains "REMOVE-EDITED: …naming the user's own line" "my own rule" "$RE_NO"
expect_same_bytes "REMOVE-EDITED: a no keeps the edit, byte for byte" "$TMP/re-before.md" "$SB_RE/.claude/CLAUDE.md"
RE_YES="$(remove_run "$SB_RE" y)"
expect_contains "REMOVE-EDITED: the yes arm showed the difference too" "my own rule" "$RE_YES"
expect_same_bytes "REMOVE-EDITED: a yes strips the edited block and keeps the rest" "$TMP/planted.md" "$SB_RE/.claude/CLAUDE.md"
SB_RES="$(new_home)"; setup_run "$SB_RES" $'y\n' >/dev/null 2>&1
edit_block "$SB_RES/.claude/CLAUDE.md" '- my own rule'
cp "$SB_RES/.claude/CLAUDE.md" "$TMP/res-before.md"
RES_NO="$(remove_run "$SB_RES" n "$TMP/standalone/remove.sh")"
expect_contains "REMOVE-EDITED: the standalone door shows the block's lines before asking" "my own rule" "$RES_NO"
expect_same_bytes "REMOVE-EDITED: …and a no keeps them" "$TMP/res-before.md" "$SB_RES/.claude/CLAUDE.md"

# ---------------------------------------------------------------------------
section "§DELETE: the file goes only when it held the unedited block and nothing else"
# ---------------------------------------------------------------------------
#
# The rule (wave-27 T40, the orchestrator's ruling on A-T40.2): remove deletes
# CLAUDE.md when, and only when, the strip succeeded, the block was `present`,
# and nothing else is left. Who created the file is not asked. A file with no
# block is never touched; an edited block's emptied file stays; the standalone
# door, which cannot prove `present`, keeps an emptied file (§REMOVE above).

# 1. A file setup created, holding the unedited block alone: gone, and announced.
SB_D1="$(new_bare_home)"; setup_run "$SB_D1" $'y\n' >/dev/null 2>&1
D1_OUT="$(remove_run "$SB_D1" y)"
expect_contains "DELETE: the question says the file will be deleted" "delete the file" "$D1_OUT"
expect_eq "DELETE: a file holding the unedited block alone is gone" "no" "$(path_exists "$SB_D1/.claude/CLAUDE.md")"

# 1b. A 0-byte file the user made BEFORE setup, then the block: the same bytes as
# case 1, so the same answer — restored to absent, which loses nothing.
SB_D3="$(new_bare_home)"; : > "$SB_D3/.claude/CLAUDE.md"; setup_run "$SB_D3" $'y\n' >/dev/null 2>&1
expect_eq "DELETE: setup wrote into the user's 0-byte file" "1" "$(count_lines_equal "$SB_D3/.claude/CLAUDE.md" "$START_LIT")"
D3_OUT="$(remove_run "$SB_D3" y)"
expect_contains "DELETE: a once-empty file holding the unedited block alone is announced as a deletion" "delete the file" "$D3_OUT"
expect_eq "DELETE: …and is gone" "no" "$(path_exists "$SB_D3/.claude/CLAUDE.md")"

# 2. A file with NO block, 0 bytes (review probe-lib case 12): never touched.
SB_D0="$(new_bare_home)"; : > "$SB_D0/.claude/CLAUDE.md"
D0_OUT="$(remove_run "$SB_D0" y)"
expect_absent "DELETE: a 0-byte file with no block is not asked about" "[y/N]" "$D0_OUT"
expect_eq "DELETE: …and stays, at 0 bytes" "yes 0" \
  "$(path_exists "$SB_D0/.claude/CLAUDE.md") $(wc -c < "$SB_D0/.claude/CLAUDE.md" 2>/dev/null | tr -d ' ')"

# 3. An EDITED block alone: the difference is shown, a yes strips it, the file stays.
SB_D2="$(new_bare_home)"; setup_run "$SB_D2" $'y\n' >/dev/null 2>&1
edit_block "$SB_D2/.claude/CLAUDE.md" 'MY OWN RULES'
D2_OUT="$(remove_run "$SB_D2" y)"
expect_contains "DELETE: an edited block alone shows its difference first" "MY OWN RULES" "$D2_OUT"
expect_absent "DELETE: …is not announced as a file deletion" "delete the file" "$D2_OUT"
expect_eq "DELETE: …and the emptied file stays" "yes 0" \
  "$(path_exists "$SB_D2/.claude/CLAUDE.md") $(wc -c < "$SB_D2/.claude/CLAUDE.md" 2>/dev/null | tr -d ' ')"

# 4. The user's text besides the block: their bytes come back, the file stays.
SB_D4="$(new_home)"; setup_run "$SB_D4" $'y\n' >/dev/null 2>&1
D4_OUT="$(remove_run "$SB_D4" y)"
expect_absent "DELETE: a file with the user's text besides the block is not announced as a deletion" "delete the file" "$D4_OUT"
expect_same_bytes "DELETE: …and comes back as the user's bytes" "$TMP/planted.md" "$SB_D4/.claude/CLAUDE.md"

# ---------------------------------------------------------------------------
section "§READ-ONLY: a file the user made read-only is refused, never overwritten"
# ---------------------------------------------------------------------------

SB_RO="$(new_home)"; chmod 444 "$SB_RO/.claude/CLAUDE.md"
RO_OUT="$(setup_run "$SB_RO" $'y\n')"
expect_same_bytes "READ-ONLY: setup answered yes leaves the file byte-identical" "$TMP/planted.md" "$SB_RO/.claude/CLAUDE.md"
expect_contains "READ-ONLY: …and says why" "read-only" "$RO_OUT"
chmod 644 "$SB_RO/.claude/CLAUDE.md"; setup_run "$SB_RO" $'y\n' >/dev/null 2>&1
expect_eq "READ-ONLY: the same yes on a writable file writes (the twin)" "1" "$(count_lines_equal "$SB_RO/.claude/CLAUDE.md" "$START_LIT")"
cp "$SB_RO/.claude/CLAUDE.md" "$TMP/ro-before.md"; chmod 444 "$SB_RO/.claude/CLAUDE.md"
RO_RM="$(remove_run "$SB_RO" y)"
expect_same_bytes "READ-ONLY: remove answered yes leaves it byte-identical" "$TMP/ro-before.md" "$SB_RO/.claude/CLAUDE.md"
expect_contains "READ-ONLY: …and says why" "read-only" "$RO_RM"
chmod 644 "$SB_RO/.claude/CLAUDE.md"

# ---------------------------------------------------------------------------
section "§EDITED-IS-THE-USER'S: an edit is a state, not a finding"
# ---------------------------------------------------------------------------

expect_absent "EDITED-STATE: doctor's edited row is not a fault" "✗" "$ROW_E"
expect_absent "EDITED-STATE: doctor's edited row does not call the difference the user's own edit" "your own edit" "$ROW_E"
PLAN_E="$(setup_plan "$SB_DE")"
PLAN_A="$(setup_plan "$SB_DA")"
expect_contains "EDITED-STATE: the --all page offers the principles on an absent block" "working principles" "$PLAN_A"
expect_absent "EDITED-STATE: the --all page leaves an edited block off" "working principles" "$PLAN_E"

# ---------------------------------------------------------------------------
section "§CONSENT: the path and the full text are on screen before the question"
# ---------------------------------------------------------------------------

C_OUT="$(setup_run "$(new_home)" $'n\n')"
# The screen folds the text to the page's width at spaces, keeping each space, so
# the printed lines joined back up are the shipped text joined up, byte for byte.
C_TEXT="$(printf '%s\n' "$C_OUT" | sed -n '/between its markers:/,/seven short rules/p' | sed '1d;$d' | sed 's/^     //' | tr -d '\n')"
C_WANT="$(tr -d '\n' < "$TMP/shipped-block")"
expect_nonempty "CONSENT: the screen's text extractor reads something" "$C_TEXT"
expect_eq "CONSENT: the full shipped text is printed before the question" "$C_WANT" "$C_TEXT"
expect_contains "CONSENT: the summary names the rule that lets an agent act without asking" "without asking" "$C_OUT"
C_BEFORE_Q="${C_OUT%%\[y/N\]*}"
expect_contains "CONSENT: the text is printed BEFORE the question, not after" "Decide what is yours" "$C_BEFORE_Q"

finish
