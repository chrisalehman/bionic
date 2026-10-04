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

setup_run() {  # <home> <stdin text> — one narrowed setup, answers on stdin
  printf '%s' "$2" | HOME="$1" ZDOTDIR="$1" SHELL=/bin/zsh PATH="$TMP/bin:$PATH" \
    BIONIC_CLAUDE_HOME="$1/.claude" BIONIC_PLUGIN_ROOT="$PAYLOAD" \
    bash "$SETUP_SH" --only "$ITEM" 2>&1
}

setup_closed() {  # <home> — the same, with the answer channel closed
  HOME="$1" ZDOTDIR="$1" SHELL=/bin/zsh PATH="$TMP/bin:$PATH" \
    BIONIC_CLAUDE_HOME="$1/.claude" BIONIC_PLUGIN_ROOT="$PAYLOAD" \
    bash "$SETUP_SH" --only "$ITEM" </dev/null 2>&1
}

doctor_run() {  # <home>
  HOME="$1" ZDOTDIR="$1" SHELL=/bin/zsh PATH="$TMP/bin:$PATH" \
    BIONIC_CLAUDE_HOME="$1/.claude" BIONIC_PLUGIN_ROOT="$PAYLOAD" \
    BIONIC_DOCTOR_PROBE_SECONDS=15 \
    bash "$DOCTOR_SH" </dev/null 2>&1
}

remove_run() {  # <home> <answer> [script]
  local script="${3:-$REMOVE_SH}"
  printf '%s\n' "$2" | HOME="$1" ZDOTDIR="$1" SHELL=/bin/zsh PATH="$TMP/bin:$PATH" \
    BIONIC_CLAUDE_HOME="$1/.claude" \
    bash "$script" --only "$ITEM" 2>&1
}

detect_run() {  # <home> -> the detector's one fact line
  HOME="$1" SHELL=/bin/zsh PATH="$TMP/bin:$PATH" BIONIC_CLAUDE_HOME="$1/.claude" \
    BIONIC_PLUGIN_ROOT="$PAYLOAD" \
    bash -c '. "$1" && detect_working_principles' _ "$DETECT_SH" 2>&1
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
expect_eq "REMOVE: …and after the standalone door's remove" "no" \
  "$(path_exists "$SB_RBS/.claude/CLAUDE.md")"
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

finish
