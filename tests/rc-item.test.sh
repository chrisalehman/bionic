#!/bin/bash
# THE RC ITEM — epic-18 wave-03 task 4/7 (spec §R6, AC-5, AC-6, AC-7).
#
# WHAT THIS SUITE OWNS. The `claude()` shell proxy as a SETUP-MANAGED ITEM: the
# marker-delimited block bionic owns in the user's shell rc, the roster and the
# write/read/delete in payload/scripts/lib/env.sh, the consented step in
# setup.sh that offers it, the row doctor.sh renders for it, and the strip
# remove.sh performs through both of its doors.
#
# WHY A SHELL FUNCTION AND NOT A LINE SOMEONE PASTES. The launch flag has to
# reach the `claude` a person types, and the only place that can happen is
# their shell rc — no settings.json key is equivalent, because the CLI decides
# bypass availability from argv (epic-19 W1, record/epic-19/w1/s1-f2-probe.md).
# A line written there by hand is footprint doctor cannot report
# and remove cannot strip; inside bionic's markers it is an item with an owner —
# offered once with a why, reported present or absent, and taken back out on
# request. That is the whole reason this file exists (Chris 2026-08-23: "It may
# only be made if it is permanently added").
#
# EVERY NEGATIVE HERE HAS A POSITIVE BESIDE IT, ON THE SAME EXTRACTOR AND THE
# SAME FIXTURE (.claude/rules/test-harness.md,
# "Anti-vacuity"). `rc_block_lines` is asserted non-empty after
# a consented setup before it is asserted empty before one; the `type claude`
# readback is asserted to name a shell function after setup before it is
# asserted not to before setup. An extractor that returned the empty string for
# every input would fail the positive arm and take its negative twin with it.
#
# NO awk EQUALITY ON THE MARKER GLYPHS. The markers are box-drawing dashes, and
# an `awk '$0 == marker'` comparison on them is locale-dependent — it has
# silently matched nothing before. Every comparison below is bash's own `[ = ]`
# or a `case` pattern, in-process.
#
# ASSERTION-HELPER RACE. No `printf | grep -q` anywhere: containment is bash
# `case`, and the only reads of a file are bash `read` loops.
#
# HERMETIC. Every arm builds its own $HOME under $TMP, plants its own .zshrc,
# and points the payload at it with HOME/ZDOTDIR/SHELL/BIONIC_CLAUDE_HOME. The
# real ~/.zshrc is never read and never written. `claude` is a stub on a
# prepended PATH so no arm asks the live CLI anything.
#
# Usage: bash tests/rc-item.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
ENV_SH="${REPO}/payload/scripts/lib/env.sh"
DETECT_SH="${REPO}/payload/scripts/lib/detect.sh"
SETUP_SH="${REPO}/payload/scripts/setup.sh"
DOCTOR_SH="${REPO}/payload/scripts/doctor.sh"
REMOVE_SH="${REPO}/payload/scripts/remove.sh"

. "$(dirname "$0")/lib/assert.sh"

# expect_not_contains -> expect_absent, pure rename (S1b/A-17 mapping table): same
# `case` glob semantics.
expect_same_bytes() {  # <label> <file-a> <file-b>
  if cmp -s "$2" "$3"; then ok "$1"; else no "$1" "$(diff "$2" "$3" 2>&1 | head -20)"; fi
}
expect_diff_bytes() {  # <label> <file-a> <file-b>
  if cmp -s "$2" "$3"; then no "$1" "the two files are byte-identical and should not be"; else ok "$1"; fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

command -v zsh >/dev/null 2>&1 || { echo "rc-item.test.sh: zsh is required — the readback arm runs the rc"; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "rc-item.test.sh: jq is required"; exit 1; }

# ---------------------------------------------------------------------------
# The literals under test
#
# SPELLED HERE, AND PINNED TO THE PAYLOAD BELOW. The suite has to look for the
# markers to find the block, so it carries them; the pins that follow are what
# make that carriage a pin and not a second source of truth — env.sh's constants
# must equal these, and remove.sh's standalone copies must equal env.sh's.
# ---------------------------------------------------------------------------
RC_START_LIT='# ─── bionic:rc:start ───'
RC_END_LIT='# ─── bionic:rc:end ───'
PROXY_LINE='claude() { command claude --allow-dangerously-skip-permissions "$@"; }'
# The block's first line clears an alias named `claude`, which would otherwise expand
# into the function's definition line (wave-27 T75, A-orch-185). The body is both.
PROXY_UNALIAS='unalias claude 2>/dev/null || true'
PROXY_BODY="$(printf '%s\n%s' "$PROXY_UNALIAS" "$PROXY_LINE")"
DOCTOR_ROW_LABEL='claude() shell proxy'

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'STUB'
#!/bin/bash
case "$*" in
  "plugin list --json") echo '[]' ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$TMP/bin/claude"

# The rc every arm starts from: three lines that are not bionic's, and which
# every assertion below requires to come back byte-identical.
plant_rc() {  # <file>
  cat > "$1" <<'RC'
# a line that was here before bionic
export EDITOR=vim
alias ll='ls -la'
RC
}

# THE STALE-BLOCK FIXTURE. bionic's markers around an OLDER payload's proxy
# text, with non-bionic lines above AND below the block. Every install already
# on disk takes this shape the day `rc_default claude-proxy`'s text changes. The
# line is one bionic really wrote (env.sh `rc_earlier`): since wave-27 T77 a block
# holding a line bionic never wrote is the user's, changed, and left as it is.
STALE_LINE='claude() { command claude --dangerously-skip-permissions "$@"; }'
plant_stale_rc() {  # <file>
  {
    printf '%s\n' '# a line that was here before bionic'
    printf '%s\n' 'export EDITOR=vim'
    printf '%s\n' "$RC_START_LIT"
    printf '%s\n' "$STALE_LINE"
    printf '%s\n' "$RC_END_LIT"
    printf '%s\n' "alias ll='ls -la'"
    printf '%s\n' 'export PAGER=less'
  } > "$1"
}

# FRESH MEANS FRESH, AND A COUNTER COULD NOT DELIVER IT. Every call site is
# `SB="$(new_sandbox)"`, which runs this function in a COMMAND SUBSTITUTION —
# its own subshell — so a `SANDBOX_N=$((SANDBOX_N + 1))` here incremented a
# variable that died with the subshell and every sandbox in the suite was the
# same directory, re-planted in place. Arms that write and read in immediate
# succession never noticed; an arm that needs two fixtures alive AT ONCE (the
# agreement section below holds three) got one directory wearing three names.
# `mktemp -d` keeps no state to lose (epic-19 W1 S9).
new_sandbox() {  # -> prints a fresh $HOME with a planted .zshrc
  local sb
  sb="$(mktemp -d "$TMP/home-XXXXXX")"
  mkdir -p "$sb/.claude"
  plant_rc "$sb/.zshrc"
  printf '%s' "$sb"
}

new_stale_sandbox() {  # -> a fresh $HOME whose .zshrc already holds a stale block
  local sb
  sb="$(new_sandbox)"
  plant_stale_rc "$sb/.zshrc"
  printf '%s' "$sb"
}

# ---------------------------------------------------------------------------
# Extractors — every assertion below reads through one of these
# ---------------------------------------------------------------------------

# The lines BETWEEN bionic's markers, in order. Not "does the file contain the
# proxy line": a proxy line outside the markers is a line bionic does not own
# and this extractor must not see it.
rc_block_lines() {  # <file>
  local file="$1" line inside=0 out=""
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$RC_START_LIT" ]; then inside=1; continue; fi
    if [ "$line" = "$RC_END_LIT" ];   then inside=0; continue; fi
    [ "$inside" = "1" ] && out="${out}${line}"$'\n'
  done < "$file"
  printf '%s' "$out"
}

# Every line NOT between bionic's markers, in order, the markers themselves
# excluded. The other half of `rc_block_lines`: what the user's rc held before
# bionic ever touched it, and must still hold afterwards whatever bionic did to
# its own block.
rc_nonblock_lines() {  # <file>
  local file="$1" line inside=0 out=""
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$RC_START_LIT" ]; then inside=1; continue; fi
    if [ "$line" = "$RC_END_LIT" ];   then inside=0; continue; fi
    [ "$inside" = "0" ] && out="${out}${line}"$'\n'
  done < "$file"
  printf '%s' "$out"
}

# Does the SHELL agree the file is a shell script -- `ok`, or the parser's own
# complaint. An rc that no longer parses is the failure mode that locks a user
# out of their own login shell, and no assertion about bytes or blocks sees it.
zsh_syntax_rc() {  # <file>
  local out
  if out="$(zsh -n "$1" 2>&1)"; then printf 'ok'; else printf '%s' "${out:-nonzero}"; fi
}

# How many times a whole line equals <literal>. The idempotence arm reads this.
count_lines_equal() {  # <file> <literal>
  local file="$1" want="$2" line n=0
  [ -f "$file" ] || { printf '0'; return 0; }
  while IFS= read -r line || [ -n "$line" ]; do
    [ "$line" = "$want" ] && n=$((n + 1))
  done < "$file"
  printf '%s' "$n"
}

# A single-quoted shell constant's contents, read out of a script. Pure bash —
# the values are box-drawing glyphs and this must not go through awk or sed.
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

# The one line of a report that names the proxy row.
report_row() {  # <report text> <label>
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in *"$2"*) printf '%s' "$line"; return 0 ;; esac
  done <<< "$1"
  return 0
}

# What the SHELL says the name resolves to, from that HOME's own rc. This is the
# arm no file assertion can stand in for: a block written into a file the shell
# never reads is a block that changed nothing.
type_claude() {  # <sandbox>
  HOME="$1" ZDOTDIR="$1" SHELL=/bin/zsh PATH="$TMP/bin:$PATH" \
    zsh -ic 'type claude' 2>&1
}

# ---------------------------------------------------------------------------
# Drivers
# ---------------------------------------------------------------------------

setup_run() {  # <sandbox> <answer>
  local sb="$1" answer="$2"
  printf '%s\n' "$answer" | HOME="$sb" ZDOTDIR="$sb" SHELL=/bin/zsh \
    PATH="$TMP/bin:$PATH" BIONIC_CLAUDE_HOME="$sb/.claude" \
    bash "$SETUP_SH" --only claude-proxy 2>&1
}

doctor_run() {  # <sandbox>
  HOME="$1" ZDOTDIR="$1" SHELL=/bin/zsh \
    PATH="$TMP/bin:$PATH" BIONIC_CLAUDE_HOME="$1/.claude" \
    BIONIC_DOCTOR_PROBE_SECONDS=15 \
    bash "$DOCTOR_SH" </dev/null 2>&1
}

remove_run() {  # <sandbox> <answer> [script]
  local sb="$1" answer="$2" script="${3:-$REMOVE_SH}"
  printf '%s\n' "$answer" | HOME="$sb" ZDOTDIR="$sb" SHELL=/bin/zsh \
    PATH="$TMP/bin:$PATH" BIONIC_CLAUDE_HOME="$sb/.claude" \
    bash "$script" --only claude-proxy 2>&1
}

# One env.sh call in a fresh bash, against a fixture HOME.
env_run() {  # <sandbox> <shell-path> -- <function> [args...]
  local sb="$1" shell_path="$2"; shift 2
  [ "${1:-}" = "--" ] && shift
  HOME="$sb" SHELL="$shell_path" PATH="$TMP/bin:$PATH" \
    BIONIC_CLAUDE_HOME="$sb/.claude" \
    bash -c '
      set -uo pipefail
      . "$1" || exit 90
      shift
      "$@"
    ' _ "$ENV_SH" "$@"
}

# The same, for a snippet that has to READ a variable env.sh defines rather than
# call a function it defines.
env_eval() {  # <sandbox> <shell-path> <snippet>
  HOME="$1" SHELL="$2" PATH="$TMP/bin:$PATH" BIONIC_CLAUDE_HOME="$1/.claude" \
    bash -c '
      set -uo pipefail
      . "$1" || exit 90
      eval "$2"
    ' _ "$ENV_SH" "$3"
}

section "env.sh: the roster, the literals and the default"

SB_A="$(new_sandbox)"
expect_eq "env.sh RC_ITEMS names the proxy" \
  "claude-proxy" "$(env_eval "$SB_A" /bin/zsh 'printf "%s" "$RC_ITEMS"' 2>/dev/null)"

ENV_RC_START="$(const_from "$ENV_SH" RC_START)" || ENV_RC_START=""
ENV_RC_END="$(const_from "$ENV_SH" RC_END)"     || ENV_RC_END=""
expect_nonempty "env.sh carries an RC_START constant" "$ENV_RC_START"
expect_nonempty "env.sh carries an RC_END constant"   "$ENV_RC_END"
expect_eq "env.sh RC_START is the spec's literal" "$RC_START_LIT" "$ENV_RC_START"
expect_eq "env.sh RC_END is the spec's literal"   "$RC_END_LIT"   "$ENV_RC_END"

expect_eq "rc_default claude-proxy is the unalias line and the proxy function, exactly" \
  "$PROXY_BODY" "$(env_run "$SB_A" /bin/zsh -- rc_default claude-proxy)"
expect_empty "rc_default refuses a name that is not bionic's" \
  "$(env_run "$SB_A" /bin/zsh -- rc_default not-an-item 2>/dev/null)"

section "env.sh: rc_file picks the rc the shell reads"

SB_B="$(new_sandbox)"
expect_eq "rc_file under zsh is that HOME's .zshrc" \
  "${SB_B}/.zshrc" "$(env_run "$SB_B" /bin/zsh -- rc_file)"
expect_eq "rc_file under bash is that HOME's .bashrc" \
  "${SB_B}/.bashrc" "$(env_run "$SB_B" /bin/bash -- rc_file)"
RC_FISH_OUT="$(env_run "$SB_B" /usr/local/bin/fish -- rc_file 2>&1)"; RC_FISH_RC=$?
expect_ne "rc_file refuses a shell bionic writes no rc for" "0" "$RC_FISH_RC"
expect_contains "rc_file says which shell it declined" "fish" "$RC_FISH_OUT"

section "setup: consent yes writes the block, and the shell reads it"

SB_YES="$(new_sandbox)"
cp "$SB_YES/.zshrc" "$TMP/yes-before.zshrc"

# NEGATIVE AND POSITIVE ON THE SAME EXTRACTOR AND THE SAME FIXTURE. The block is
# read before and after one consented run; the "empty" assertion is only
# meaningful because the "non-empty" one below it passes on the same file.
BLOCK_BEFORE="$(rc_block_lines "$SB_YES/.zshrc")"
TYPE_BEFORE="$(type_claude "$SB_YES")"

SETUP_OUT="$(setup_run "$SB_YES" y)"
BLOCK_AFTER="$(rc_block_lines "$SB_YES/.zshrc")"
TYPE_AFTER="$(type_claude "$SB_YES")"

expect_nonempty "after a consented setup the marker block holds a line" "$BLOCK_AFTER"
expect_eq "the block holds exactly the unalias line and the proxy function" "$PROXY_BODY" "$BLOCK_AFTER"
expect_empty  "before setup the same file has no marker block" "$BLOCK_BEFORE"

expect_contains "after setup the shell reports claude as a function" "shell function" "$TYPE_AFTER"
expect_absent "before setup the same shell reports no function" "shell function" "$TYPE_BEFORE"

expect_contains "setup states the why before it asks" "bypass" "$SETUP_OUT"

# The rest of the rc is untouched: everything that is not the block is the
# planted file, byte for byte.
{
  printf '%s\n' "$RC_START_LIT"
  printf '%s\n' "$PROXY_UNALIAS"
  printf '%s\n' "$PROXY_LINE"
  printf '%s\n' "$RC_END_LIT"
} > "$TMP/expected-block"
cat "$TMP/yes-before.zshrc" "$TMP/expected-block" > "$TMP/yes-expected.zshrc"
expect_same_bytes "the rc is the planted file plus the block, byte for byte" \
  "$TMP/yes-expected.zshrc" "$SB_YES/.zshrc"

section "setup: a second run changes nothing"

cp "$SB_YES/.zshrc" "$TMP/idem-before.zshrc"
setup_run "$SB_YES" y >/dev/null 2>&1
expect_same_bytes "a second consented run leaves the rc byte-identical" \
  "$TMP/idem-before.zshrc" "$SB_YES/.zshrc"
expect_eq "exactly one start marker after two runs" "1" \
  "$(count_lines_equal "$SB_YES/.zshrc" "$RC_START_LIT")"
expect_eq "exactly one proxy line after two runs" "1" \
  "$(count_lines_equal "$SB_YES/.zshrc" "$PROXY_LINE")"

section "setup: consent no writes nothing"

SB_NO="$(new_sandbox)"
cp "$SB_NO/.zshrc" "$TMP/no-before.zshrc"
NO_OUT="$(setup_run "$SB_NO" n)"
expect_same_bytes "a declined setup leaves the rc byte-identical" \
  "$TMP/no-before.zshrc" "$SB_NO/.zshrc"
expect_empty "a declined setup leaves no marker block" "$(rc_block_lines "$SB_NO/.zshrc")"
# The positive twin for the two assertions above, on the same fixture and the
# same extractors: a yes on this very file does change it.
setup_run "$SB_NO" y >/dev/null 2>&1
expect_diff_bytes "a consented setup on the same fixture does change the rc" \
  "$TMP/no-before.zshrc" "$SB_NO/.zshrc"
expect_nonempty "a consented setup on the same fixture does write a block" \
  "$(rc_block_lines "$SB_NO/.zshrc")"

section "doctor: one row, absent before and present after"

SB_DOC="$(new_sandbox)"
ROW_ABSENT="$(report_row "$(doctor_run "$SB_DOC")" "$DOCTOR_ROW_LABEL")"
setup_run "$SB_DOC" y >/dev/null 2>&1
ROW_PRESENT="$(report_row "$(doctor_run "$SB_DOC")" "$DOCTOR_ROW_LABEL")"

expect_nonempty "doctor renders a proxy row when the block is present" "$ROW_PRESENT"
expect_nonempty "doctor renders a proxy row when the block is absent"  "$ROW_ABSENT"
expect_ne "the two rows differ" "$ROW_ABSENT" "$ROW_PRESENT"
expect_contains "the absent row routes the reader to setup" "/bionic:setup" "$ROW_ABSENT"
expect_absent "the present row does not route to setup" "/bionic:setup" "$ROW_PRESENT"

section "detect: the presence fact"

SB_DET="$(new_sandbox)"
detect_run() {  # <sandbox>
  HOME="$1" SHELL=/bin/zsh PATH="$TMP/bin:$PATH" BIONIC_CLAUDE_HOME="$1/.claude" \
    bash -c '. "$1" && detect_rc_claude_proxy' _ "$DETECT_SH" 2>&1
}
DET_ABSENT="$(detect_run "$SB_DET")"
setup_run "$SB_DET" y >/dev/null 2>&1
DET_PRESENT="$(detect_run "$SB_DET")"
expect_eq "detect_rc_claude_proxy reports present after setup" \
  "env:rc-claude-proxy present=yes" "$DET_PRESENT"
expect_eq "detect_rc_claude_proxy reports absent before setup" \
  "env:rc-claude-proxy present=no" "$DET_ABSENT"

section "the two doors answer the same question the same way"

# WHAT THIS SECTION OWNS. "Is bionic's `claude()` proxy in place" is asked by
# two doors — setup decides whether to offer the item (`rc_get`), doctor decides
# what to print (`detect_rc_claude_proxy`) — and one concept answered two ways is
# a concept that can disagree. The two arms above drive both predicates already,
# but only on the states where they cannot differ: a file with no block, and a
# file whose block holds exactly the current line.
#
# THE THIRD FIXTURE IS THE ONLY ONE THAT SEPARATES THEM: bionic's markers around
# an OLDER payload's proxy text, which is the state every install already on disk
# entered the day `rc_default`'s line changed (epic-19 W1 task 4/1 changed it).
# A marker-only predicate calls that machine done; a line-comparing predicate
# calls it pending. Whoever is wrong, they must not be wrong differently — this
# is the agreement pin the Step-6 DUPLICATION review found missing.

# Setup's own predicate, as setup consumes it (setup.sh:1194 `rc_get … && continue`).
setup_says() {  # <sandbox> -> in-place | pending
  if env_run "$1" /bin/zsh -- rc_get claude-proxy >/dev/null 2>&1
  then printf 'in-place'; else printf 'pending'; fi
}
# Doctor's, as doctor consumes it (doctor.sh: `[ "$RC_PROXY_STATE" = "yes" ]`).
doctor_says() {  # <sandbox> -> in-place | pending
  case "$(detect_run "$1")" in
    *present=yes) printf 'in-place' ;;
    *)            printf 'pending' ;;
  esac
}

SB_AG_ABSENT="$(new_sandbox)"
SB_AG_CURRENT="$(new_sandbox)"; setup_run "$SB_AG_CURRENT" y >/dev/null 2>&1
SB_AG_STALE="$(new_stale_sandbox)"

# The extractors are proved to discriminate before the third fixture is asked
# anything: each one answers both words, on the two fixtures where the answer is
# not in dispute. A predicate stuck on one value would fail here and take the
# stale arm's meaning with it.
expect_eq "setup's predicate says pending on an rc with no block" \
  "pending" "$(setup_says "$SB_AG_ABSENT")"
expect_eq "setup's predicate says in-place after a consented setup" \
  "in-place" "$(setup_says "$SB_AG_CURRENT")"
expect_eq "doctor's predicate says pending on an rc with no block" \
  "pending" "$(doctor_says "$SB_AG_ABSENT")"
expect_eq "doctor's predicate says in-place after a consented setup" \
  "in-place" "$(doctor_says "$SB_AG_CURRENT")"

expect_eq "the two predicates agree on an rc with no block" \
  "$(setup_says "$SB_AG_ABSENT")" "$(doctor_says "$SB_AG_ABSENT")"
expect_eq "the two predicates agree after a consented setup" \
  "$(setup_says "$SB_AG_CURRENT")" "$(doctor_says "$SB_AG_CURRENT")"
expect_eq "the two predicates agree on a STALE block — the state that separates them" \
  "$(setup_says "$SB_AG_STALE")" "$(doctor_says "$SB_AG_STALE")"

# The fixture is the stale one it claims to be, read through the same extractor
# the rebuild section uses — otherwise the agreement above could be agreement
# about a file that holds no block at all.
expect_eq "the stale fixture holds an older payload's line inside the markers" \
  "$STALE_LINE" "$(rc_block_lines "$SB_AG_STALE/.zshrc")"

# STALE IS ITS OWN ANSWER, not a second spelling of absent. Markers with a
# foreign line is a machine that consented and now carries a line bionic no
# longer writes; markers absent is a machine that was never asked or said no.
# Doctor routes the first to a rewrite and leaves the second alone, so the fact
# function has to tell them apart.
expect_eq "detect reports a stale block as stale" \
  "env:rc-claude-proxy present=stale" "$(detect_run "$SB_AG_STALE")"
expect_eq "detect still reports no block at all as absent" \
  "env:rc-claude-proxy present=no" "$(detect_run "$SB_AG_ABSENT")"

ROW_STALE="$(report_row "$(doctor_run "$SB_AG_STALE")" "$DOCTOR_ROW_LABEL")"
expect_nonempty "doctor renders a proxy row on a stale block" "$ROW_STALE"
expect_contains "the stale row says stale"                     "stale"         "$ROW_STALE"
expect_contains "the stale row routes the reader to setup"     "/bionic:setup" "$ROW_STALE"
expect_ne "the stale row is not the healthy row" "$ROW_PRESENT" "$ROW_STALE"

section "remove: the block goes, every other line stays"

SB_RM="$(new_sandbox)"
cp "$SB_RM/.zshrc" "$TMP/rm-before.zshrc"
setup_run "$SB_RM" y >/dev/null 2>&1
expect_nonempty "the block is there to remove" "$(rc_block_lines "$SB_RM/.zshrc")"
RM_OUT="$(remove_run "$SB_RM" y)"
expect_empty "after remove the block is gone" "$(rc_block_lines "$SB_RM/.zshrc")"
expect_eq "after remove no start marker survives" "0" \
  "$(count_lines_equal "$SB_RM/.zshrc" "$RC_START_LIT")"
expect_eq "after remove no end marker survives" "0" \
  "$(count_lines_equal "$SB_RM/.zshrc" "$RC_END_LIT")"
expect_same_bytes "after remove the rc is byte-identical to the planted file" \
  "$TMP/rm-before.zshrc" "$SB_RM/.zshrc"
expect_contains "remove names the file it changed" "${SB_RM}/.zshrc" "$RM_OUT"

section "remove: the standalone door does the same"

# The script alone, with no scripts/lib beside it — the curl-fetched shape.
mkdir -p "$TMP/standalone"
cp "$REMOVE_SH" "$TMP/standalone/remove.sh"

SB_SA="$(new_sandbox)"
cp "$SB_SA/.zshrc" "$TMP/sa-before.zshrc"
setup_run "$SB_SA" y >/dev/null 2>&1
expect_nonempty "the standalone arm has a block to remove" "$(rc_block_lines "$SB_SA/.zshrc")"
SA_OUT="$(remove_run "$SB_SA" y "$TMP/standalone/remove.sh")"
expect_empty "the standalone door strips the block too" "$(rc_block_lines "$SB_SA/.zshrc")"
expect_same_bytes "the standalone door leaves the rest of the rc byte-identical" \
  "$TMP/sa-before.zshrc" "$SB_SA/.zshrc"

# THE PIN. The standalone door cannot source env.sh, so it carries copies; a
# copy that drifts is a block setup writes and remove cannot find.
RM_RC_START_COPY="$(const_from "$REMOVE_SH" RM_RC_START)" || RM_RC_START_COPY=""
RM_RC_END_COPY="$(const_from "$REMOVE_SH" RM_RC_END)"     || RM_RC_END_COPY=""
expect_nonempty "remove.sh carries an RM_RC_START copy" "$RM_RC_START_COPY"
expect_nonempty "remove.sh carries an RM_RC_END copy"   "$RM_RC_END_COPY"
expect_eq "RM_RC_START is byte-equal to env.sh's RC_START" "$ENV_RC_START" "$RM_RC_START_COPY"
expect_eq "RM_RC_END is byte-equal to env.sh's RC_END"     "$ENV_RC_END"   "$RM_RC_END_COPY"

section "env.sh: rc_get sees the line only inside the markers"

SB_G="$(new_sandbox)"
setup_run "$SB_G" y >/dev/null 2>&1
env_run "$SB_G" /bin/zsh -- rc_get claude-proxy >/dev/null 2>&1
expect_eq "rc_get is 0 when the block holds the line" "0" "$?"

# The same file with the same proxy line OUTSIDE the markers: a line bionic does
# not own, which rc_get must not claim.
SB_H="$(new_sandbox)"
printf '%s\n' "$PROXY_LINE" >> "$SB_H/.zshrc"
env_run "$SB_H" /bin/zsh -- rc_get claude-proxy >/dev/null 2>&1
expect_ne "rc_get is non-zero for the same line outside the markers" "0" "$?"

section "a stale in-block line: the block is rebuilt, never filtered"

# WHAT THIS SECTION OWNS. What setup and remove do to a marker block that holds
# something other than the current `rc_default` line. Everything above this
# point runs on a block that is either empty or exactly that line, so nothing
# above it can see a rebuild go wrong (epic-18 wave-03 critic F1/F2).

# THE SYNTAX EXTRACTOR IS PROVED TO DISCRIMINATE BEFORE ANYTHING IS ASKED OF IT:
# it calls the planted fixture well-formed and a deliberately broken file
# broken, through the same function.
printf '%s\n' 'if [ 1 = 1 ]' > "$TMP/broken.zshrc"

SB_ST1="$(new_stale_sandbox)"
cp "$SB_ST1/.zshrc" "$TMP/stale-before.zshrc"
expect_eq "zsh -n calls the planted stale rc well-formed" \
  "ok" "$(zsh_syntax_rc "$TMP/stale-before.zshrc")"
expect_ne "zsh -n calls a deliberately broken rc broken" \
  "ok" "$(zsh_syntax_rc "$TMP/broken.zshrc")"

STALE_BLOCK_BEFORE="$(rc_block_lines "$SB_ST1/.zshrc")"
STALE_OUTSIDE_BEFORE="$(rc_nonblock_lines "$SB_ST1/.zshrc")"
env_run "$SB_ST1" /bin/zsh -- rc_get claude-proxy >/dev/null 2>&1
STALE_GET_BEFORE=$?

setup_run "$SB_ST1" y >/dev/null 2>&1
env_run "$SB_ST1" /bin/zsh -- rc_get claude-proxy >/dev/null 2>&1
STALE_GET_AFTER=$?

expect_eq "a consented setup over a stale block leaves the rc well-formed" \
  "ok" "$(zsh_syntax_rc "$SB_ST1/.zshrc")"
expect_nonempty "the stale fixture had a block before setup" "$STALE_BLOCK_BEFORE"
expect_eq "after setup the block holds exactly the unalias line and the proxy function" \
  "$PROXY_BODY" "$(rc_block_lines "$SB_ST1/.zshrc")"
expect_eq "after setup the proxy line appears exactly once" "1" \
  "$(count_lines_equal "$SB_ST1/.zshrc" "$PROXY_LINE")"
expect_eq "after setup the stale line is gone" "0" \
  "$(count_lines_equal "$SB_ST1/.zshrc" "$STALE_LINE")"
expect_eq "the stale line was in the fixture to go" "1" \
  "$(count_lines_equal "$TMP/stale-before.zshrc" "$STALE_LINE")"
expect_eq "rc_get sees the line setup wrote over the stale block" "0" "$STALE_GET_AFTER"
expect_ne "rc_get did not read the stale line as bionic's" "0" "$STALE_GET_BEFORE"
expect_nonempty "the stale fixture has lines outside the block" "$STALE_OUTSIDE_BEFORE"
expect_eq "setup leaves every line outside the block untouched" \
  "$STALE_OUTSIDE_BEFORE" "$(rc_nonblock_lines "$SB_ST1/.zshrc")"

# What the file must be once bionic's block is out of it: the four non-bionic
# lines, in the order they were planted, and nothing else.
{
  printf '%s\n' '# a line that was here before bionic'
  printf '%s\n' 'export EDITOR=vim'
  printf '%s\n' "alias ll='ls -la'"
  printf '%s\n' 'export PAGER=less'
} > "$TMP/stale-after-remove.zshrc"

SB_ST2="$(new_stale_sandbox)"
cp "$SB_ST2/.zshrc" "$TMP/stale2-before.zshrc"
STALE_BLOCK_BEFORE_RM="$(rc_block_lines "$SB_ST2/.zshrc")"
remove_run "$SB_ST2" y >/dev/null 2>&1

expect_nonempty "the stale block was there for remove to strip" "$STALE_BLOCK_BEFORE_RM"
expect_empty "after remove the stale block is gone" "$(rc_block_lines "$SB_ST2/.zshrc")"
expect_eq "after remove no start marker survives a stale block" "0" \
  "$(count_lines_equal "$SB_ST2/.zshrc" "$RC_START_LIT")"
expect_eq "after remove no end marker survives a stale block" "0" \
  "$(count_lines_equal "$SB_ST2/.zshrc" "$RC_END_LIT")"
expect_eq "the end marker was in the fixture to go" "1" \
  "$(count_lines_equal "$TMP/stale2-before.zshrc" "$RC_END_LIT")"
expect_same_bytes "remove leaves a stale rc as its non-bionic lines, byte for byte" \
  "$TMP/stale-after-remove.zshrc" "$SB_ST2/.zshrc"
expect_eq "remove over a stale block leaves the rc well-formed" \
  "ok" "$(zsh_syntax_rc "$SB_ST2/.zshrc")"

# The standalone door has no env.sh to call, so it strips the block with its own
# copy of the walk; on this fixture the two doors must land on the same bytes.
SB_ST3="$(new_stale_sandbox)"
remove_run "$SB_ST3" y "$TMP/standalone/remove.sh" >/dev/null 2>&1
expect_same_bytes "the standalone door strips a stale block to the same bytes" \
  "$TMP/stale-after-remove.zshrc" "$SB_ST3/.zshrc"

# ---------------------------------------------------------------------------
section "wave-27 T40: a cut-short write, an unwritable TMPDIR, the blank line above"
# ---------------------------------------------------------------------------
#
# New rows only; every row above is unchanged. Each sandbox here is pointed at
# by CLAUDE_CONFIG_DIR as well as HOME, so nothing can resolve a real home.

t40_env() {  # <sandbox> <snippet> — env.sh sourced against the sandbox, then <snippet>
  HOME="$1" ZDOTDIR="$1" SHELL=/bin/zsh PATH="$TMP/bin:$PATH" \
    CLAUDE_CONFIG_DIR="$1/.claude" BIONIC_CLAUDE_HOME="$1/.claude" \
    bash -c '. "$1" || exit 90; eval "$2"' _ "$ENV_SH" "$2" 2>&1
}

# A cut-short strip: `ulimit -f` with SIGXFSZ ignored, an rc larger than the limit.
SB_T40W="$(new_sandbox)"
for _i in $(seq 1 300); do printf 'export MY_VAR_%s=mine\n' "$_i"; done >> "$SB_T40W/.zshrc"
setup_run "$SB_T40W" y >/dev/null 2>&1
expect_nonempty "T40: the cut-short fixture holds the block" "$(rc_block_lines "$SB_T40W/.zshrc")"
cp "$SB_T40W/.zshrc" "$TMP/t40w-before.zshrc"
T40W_OUT="$(t40_env "$SB_T40W" 'trap "" XFSZ; ulimit -f 2; rc_unset claude-proxy; echo "rc=$?"')"
expect_contains "T40: rc_unset cut short reports the failed write" "rc=1" "$T40W_OUT"
expect_same_bytes "T40: …and the rc is byte-identical to before it" "$TMP/t40w-before.zshrc" "$SB_T40W/.zshrc"
T40W_RM="$(trap '' XFSZ; ulimit -f 2; remove_run "$SB_T40W" y "$TMP/standalone/remove.sh")"
expect_same_bytes "T40: the standalone door cut short leaves the rc byte-identical" "$TMP/t40w-before.zshrc" "$SB_T40W/.zshrc"
t40_env "$SB_T40W" 'rc_unset claude-proxy' >/dev/null
expect_empty "T40: with room to write, the same strip does take the block (the twin)" "$(rc_block_lines "$SB_T40W/.zshrc")"

# rc_set needs no writable TMPDIR: its body is staged beside the rc.
SB_T40T="$(new_sandbox)"
T40T_OUT="$(TMPDIR="$TMP/no-such-dir/x" t40_env "$SB_T40T" 'rc_set claude-proxy; echo "rc=$?"')"
expect_contains "T40: rc_set with an unwritable TMPDIR succeeds" "rc=0" "$T40T_OUT"
expect_contains "T40: …and the block holds the proxy line" "$PROXY_LINE" "$(rc_block_lines "$SB_T40T/.zshrc")"

# The blank line above the block: both doors give back the rc the user had.
SB_T40B="$(new_sandbox)"; printf '\n' >> "$SB_T40B/.zshrc"; cp "$SB_T40B/.zshrc" "$TMP/t40b-planted.zshrc"
SB_T40BS="$(new_sandbox)"; printf '\n' >> "$SB_T40BS/.zshrc"
setup_run "$SB_T40B" y >/dev/null 2>&1; setup_run "$SB_T40BS" y >/dev/null 2>&1
expect_nonempty "T40: the blank-line fixture holds the block" "$(rc_block_lines "$SB_T40BS/.zshrc")"
remove_run "$SB_T40B" y >/dev/null 2>&1
remove_run "$SB_T40BS" y "$TMP/standalone/remove.sh" >/dev/null 2>&1
expect_same_bytes "T40: the payload door keeps a blank line the user had above the block" "$TMP/t40b-planted.zshrc" "$SB_T40B/.zshrc"
expect_same_bytes "T40: …and so does the standalone door" "$TMP/t40b-planted.zshrc" "$SB_T40BS/.zshrc"

# ---------------------------------------------------------------------------
section "wave-27 T46: a malformed rc block is read by markers_check, and called malformed"
# ---------------------------------------------------------------------------
#
# Review pass 14 F2: the detector read `stale` from a substring of the start
# marker, so doctor sent a malformed rc to a setup that refuses it. Each shape is
# the user's rc (plant_rc's three lines first); the number is the line of the
# first fault markers_check names.

plant_rc_shape() {  # <file> <shape>
  plant_rc "$1"
  case "$2" in
    start-only) printf '%s\n' "$RC_START_LIT" "$PROXY_LINE" 'export MINE=1' >> "$1" ;;
    end-only)   printf '%s\n' "$RC_END_LIT" 'export MINE=1' >> "$1" ;;
    two-starts) printf '%s\n' "$RC_START_LIT" "$PROXY_LINE" "$RC_START_LIT" "$PROXY_LINE" "$RC_END_LIT" >> "$1" ;;
    two-blocks) printf '%s\n' "$RC_START_LIT" "$PROXY_LINE" "$RC_END_LIT" 'export MINE=1' \
                  "$RC_START_LIT" "$PROXY_LINE" "$RC_END_LIT" >> "$1" ;;
  esac
}
rc_shape_line() {
  case "$1" in start-only) echo 4 ;; end-only) echo 4 ;; two-starts) echo 6 ;; two-blocks) echo 8 ;; esac
}

# The twin first: on a well-formed rc with no block, setup asks.
SB_T46Q="$(new_sandbox)"
expect_contains "T46: setup asks on an rc with no block (the twin of the refusals below)" "[y/N]" "$(setup_run "$SB_T46Q" n)"

for RC_SHAPE in start-only end-only two-starts two-blocks; do
  SB_T46="$(new_sandbox)"; plant_rc_shape "$SB_T46/.zshrc" "$RC_SHAPE"
  cp "$SB_T46/.zshrc" "$TMP/t46-before.zshrc"
  L="$(rc_shape_line "$RC_SHAPE")"
  expect_eq "T46 ${RC_SHAPE}: detect reads it as malformed" \
    "env:rc-claude-proxy present=malformed" "$(detect_run "$SB_T46")"
  T46_DOC="$(doctor_run "$SB_T46")"
  T46_ROW="$(report_row "$T46_DOC" "$DOCTOR_ROW_LABEL")"
  expect_nonempty "T46 ${RC_SHAPE}: doctor renders a proxy row" "$T46_ROW"
  expect_contains "T46 ${RC_SHAPE}: doctor's row says malformed" "malformed" "$T46_ROW"
  expect_contains "T46 ${RC_SHAPE}: …and names the line" "line ${L}:" "$T46_ROW"
  expect_absent "T46 ${RC_SHAPE}: …never stale, sending it to a setup that refuses" "rewrites it" "$T46_ROW"
  expect_absent "T46 ${RC_SHAPE}: …never not set" "not set" "$T46_ROW"
  expect_contains "T46 ${RC_SHAPE}: doctor's fix line says to fix the markers by hand" "do not pair up" "$T46_DOC"
  T46_SET="$(setup_run "$SB_T46" y)"
  expect_same_bytes "T46 ${RC_SHAPE}: setup answered yes writes nothing" "$TMP/t46-before.zshrc" "$SB_T46/.zshrc"
  expect_contains "T46 ${RC_SHAPE}: setup prints the refusal with the line" "line ${L}:" "$T46_SET"
  expect_absent "T46 ${RC_SHAPE}: setup refuses before it asks" "[y/N]" "$T46_SET"
done

# A path that is no file: refused by setup, reported by doctor, nothing made in it.
SB_T46D="$(new_sandbox)"; rm -f "$SB_T46D/.zshrc"; mkdir "$SB_T46D/.zshrc"; printf 'mine\n' > "$SB_T46D/.zshrc/keep"
T46D_LS="$(ls -A "$SB_T46D/.zshrc")"
expect_nonempty "T46: the listing extractor reads the directory's contents" "$T46D_LS"
expect_eq "T46: detect reads an rc that is a directory as not-a-file" \
  "env:rc-claude-proxy present=not-a-file" "$(detect_run "$SB_T46D")"
T46D_SET="$(setup_run "$SB_T46D" y)"
expect_contains "T46: setup names the rc and that it is a directory" "${SB_T46D}/.zshrc is a directory" "$T46D_SET"
expect_eq "T46: …and makes nothing inside it" "$T46D_LS" "$(ls -A "$SB_T46D/.zshrc")"
T46D_ROW="$(report_row "$(doctor_run "$SB_T46D")" "$DOCTOR_ROW_LABEL")"
expect_contains "T46: doctor's row says the rc is not a file" "not a file" "$T46D_ROW"
expect_absent "T46: …and does not offer setup" "/bionic:setup" "$T46D_ROW"

# ---------------------------------------------------------------------------
section "wave-27 T46: the retired rc blocks read the same state, and say their refusal"
# ---------------------------------------------------------------------------
#
# Review pass 14 F3: a retired block with unpaired markers was refused with the
# generic "could not rewrite" line, and its pending test was a substring, so a
# marker quoted in a comment got "removed" with the rc unchanged.

remove_item() {  # <sandbox> <item> <answer> [script]
  local sb="$1" item="$2" answer="$3" script="${4:-$REMOVE_SH}"
  printf '%s\n' "$answer" | HOME="$sb" ZDOTDIR="$sb" SHELL=/bin/zsh \
    PATH="$TMP/bin:$PATH" BIONIC_CLAUDE_HOME="$sb/.claude" \
    bash "$script" --only "$item" 2>&1
}
ALIAS_START="$(const_from "$REMOVE_SH" RM_ALIAS_START)"; ALIAS_END="$(const_from "$REMOVE_SH" RM_ALIAS_END)"
ENVB_START="$(const_from "$REMOVE_SH" RM_ENV_START)";    ENVB_END="$(const_from "$REMOVE_SH" RM_ENV_END)"
expect_nonempty "T46: the retired alias markers read out of remove.sh" "${ALIAS_START}${ALIAS_END}"
expect_nonempty "T46: the retired env markers read out of remove.sh" "${ENVB_START}${ENVB_END}"

for RETIRED in legacy-alias environment; do
  case "$RETIRED" in
    legacy-alias) R_START="$ALIAS_START"; R_END="$ALIAS_END"; R_BODY="alias claude='claude --dangerously-skip-permissions'" ;;
    environment)  R_START="$ENVB_START";  R_END="$ENVB_END"; R_BODY="export CLAUDE_CODE_ENABLE_TODO_TOOLS=1" ;;
  esac
  # A start with no end: refused, with the refusal's own line, by both doors.
  SB_R="$(new_sandbox)"; printf '%s\n' "$R_START" 'export RETIRED=1' 'export MINE=1' >> "$SB_R/.zshrc"
  cp "$SB_R/.zshrc" "$TMP/r-before.zshrc"
  for R_DOOR in payload standalone; do
    if [ "$R_DOOR" = "payload" ]; then R_OUT="$(remove_item "$SB_R" "$RETIRED" y)"
    else R_OUT="$(remove_item "$SB_R" "$RETIRED" y "$TMP/standalone/remove.sh")"; fi
    expect_same_bytes "T46 ${RETIRED} (${R_DOOR}): a start with no end is left byte-identical" "$TMP/r-before.zshrc" "$SB_R/.zshrc"
    expect_contains "T46 ${RETIRED} (${R_DOOR}): …and remove names the line" "line 4:" "$R_OUT"
    expect_contains "T46 ${RETIRED} (${R_DOOR}): …says the markers do not pair up" "do not pair up" "$R_OUT"
    expect_absent "T46 ${RETIRED} (${R_DOOR}): …and not that it could not rewrite" "could not rewrite" "$R_OUT"
  done
  # A marker quoted inside a comment is not a marker: nothing pending.
  SB_RQ="$(new_sandbox)"; printf '%s\n' "# see the ${R_START} line" >> "$SB_RQ/.zshrc"
  cp "$SB_RQ/.zshrc" "$TMP/rq-before.zshrc"
  RQ_OUT="$(remove_item "$SB_RQ" "$RETIRED" y)"
  expect_absent "T46 ${RETIRED}: a quoted marker is not asked about" "[y/N]" "$RQ_OUT"
  expect_same_bytes "T46 ${RETIRED}: …and the rc is byte-identical" "$TMP/rq-before.zshrc" "$SB_RQ/.zshrc"
  # The twin: a whole, paired block of what bionic wrote is asked about and goes.
  SB_RW="$(new_sandbox)"; printf '%s\n' "$R_START" "$R_BODY" "$R_END" >> "$SB_RW/.zshrc"
  RW_OUT="$(remove_item "$SB_RW" "$RETIRED" y)"
  expect_contains "T46 ${RETIRED}: a whole block is asked about (the twin)" "[y/N]" "$RW_OUT"
  expect_eq "T46 ${RETIRED}: …and goes" "0" "$(count_lines_equal "$SB_RW/.zshrc" "$R_START")"
done

# ---------------------------------------------------------------------------
section "wave-27 T51: setup's retired alias step reads markers_check and strips with markers_strip"
# ---------------------------------------------------------------------------
#
# Review pass 21 F1 (blocker): setup's own awk walk started skipping at the
# retired start marker and stopped only at an end marker, so an rc holding a
# start with no end lost every line after it and setup printed "✓ removed".
# F2: the detector matched the marker as a substring, so a marker quoted in a
# comment was offered as a block. Every run here is under `env -i` with HOME,
# ZDOTDIR, CLAUDE_CONFIG_DIR and BIONIC_CLAUDE_HOME inside the sandbox, and a
# PATH that holds the claude stub and the system directories only: `setup --all`
# answered yes acts on every item, and nothing it can reach may leave $TMP.

T51_PATH="$TMP/bin:/usr/bin:/bin"
command -v jq >/dev/null 2>&1 && T51_PATH="${T51_PATH}:$(dirname "$(command -v jq)")"
t51_env() {  # <sandbox> <command...> — the one environment every T51 run gets
  local sb="$1"; shift
  mkdir -p "$sb/.tmp"
  env -i HOME="$sb" ZDOTDIR="$sb" CLAUDE_CONFIG_DIR="$sb/.claude" BIONIC_CLAUDE_HOME="$sb/.claude" \
    SHELL=/bin/zsh PATH="$T51_PATH" TMPDIR="$sb/.tmp" TERM=dumb BIONIC_DOCTOR_PROBE_SECONDS=15 "$@"
}
t51_setup() {  # <sandbox> <--only item | --all> <answer>
  local sb="$1" mode="$2" answer="$3"
  if [ "$mode" = "--all" ]; then
    printf '%s\n' "$answer" | t51_env "$sb" bash "$SETUP_SH" --all 2>&1
  else
    printf '%s\n' "$answer" | t51_env "$sb" bash "$SETUP_SH" --only "$mode" 2>&1
  fi
}
t51_doctor() { t51_env "$1" bash "$DOCTOR_SH" </dev/null 2>&1; }
t51_inode() { ls -i "$1" 2>/dev/null | { read -r n _; printf '%s' "$n"; }; }
# One `name=value` line out of `env`'s output.
t51_env_var() {  # <env output> <name>
  local line
  while IFS= read -r line; do
    case "$line" in "$2="*) printf '%s' "${line#*=}"; return 0 ;; esac
  done <<< "$1"
  return 0
}

# THE FIXTURE CANNOT REACH THE REAL HOME. Read back out of `env` as the scripts
# see it: each of the four roots is inside $TMP (the positive) and none is the
# home this suite was started from (the negative, on the same extractor).
SB_T51E="$(new_sandbox)"
T51_ENV_OUT="$(t51_env "$SB_T51E" env)"
for T51_VAR in HOME ZDOTDIR CLAUDE_CONFIG_DIR BIONIC_CLAUDE_HOME; do
  T51_VAL="$(t51_env_var "$T51_ENV_OUT" "$T51_VAR")"
  expect_nonempty "T51 fixture: ${T51_VAR} is set in the run's environment" "$T51_VAL"
  case "$T51_VAL" in "$TMP"/*) ok "T51 fixture: ${T51_VAR} is inside the throwaway home" ;;
    *) no "T51 fixture: ${T51_VAR} is inside the throwaway home" "got '${T51_VAL}'" ;; esac
  expect_ne "T51 fixture: ${T51_VAR} is not the real home" "$HOME" "$T51_VAL"
  expect_ne "T51 fixture: ${T51_VAR} is not the real claude home" "$HOME/.claude" "$T51_VAL"
done

# ONE PAIR OF RETIRED MARKERS. detect.sh's pair is what doctor and setup read;
# remove.sh's standalone copy must equal it, as the live rc markers are pinned.
DETECT_ALIAS_START="$(const_from "$DETECT_SH" BIONIC_ALIAS_START)" || DETECT_ALIAS_START=""
DETECT_ALIAS_END="$(const_from "$DETECT_SH" BIONIC_ALIAS_END)"     || DETECT_ALIAS_END=""
expect_nonempty "T51: detect.sh carries the retired alias markers" "${DETECT_ALIAS_START}${DETECT_ALIAS_END}"
expect_eq "T51: remove.sh's RM_ALIAS_START is detect.sh's BIONIC_ALIAS_START" "$DETECT_ALIAS_START" "$ALIAS_START"
expect_eq "T51: remove.sh's RM_ALIAS_END is detect.sh's BIONIC_ALIAS_END"     "$DETECT_ALIAS_END"   "$ALIAS_END"

# The review's rc: five lines, a retired start marker on line 2, no end marker.
plant_t51_five() {  # <file>
  printf '%s\n' 'export MINE_BEFORE=1' "$ALIAS_START" "alias claude='claude --dangerously-skip-permissions'" \
    'export MINE_AFTER=1' 'alias ll="ls -l"' > "$1"
}
T51_FAULT='line 2: a start marker with no end marker after it'

# setup --only legacy-alias, answered yes.
SB_T51="$(new_sandbox)"; plant_t51_five "$SB_T51/.zshrc"
cp "$SB_T51/.zshrc" "$TMP/t51-five.before"
T51_INODE="$(t51_inode "$SB_T51/.zshrc")"
expect_nonempty "T51 five-line rc: the inode extractor reads a number" "$T51_INODE"
# doctor first, on the rc as planted; its rows are read below.
T51_DOC="$(t51_doctor "$SB_T51")"
T51_SET="$(t51_setup "$SB_T51" legacy-alias y)"
expect_same_bytes "T51 five-line rc: setup --only legacy-alias answered yes leaves it byte-identical" \
  "$TMP/t51-five.before" "$SB_T51/.zshrc"
expect_eq "T51 five-line rc: …the user's last line is still there" "1" "$(count_lines_equal "$SB_T51/.zshrc" 'alias ll="ls -l"')"
expect_eq "T51 five-line rc: …and the same inode (nothing was renamed over it)" "$T51_INODE" "$(t51_inode "$SB_T51/.zshrc")"
expect_contains "T51 five-line rc: setup prints the fault with its line" "$T51_FAULT" "$T51_SET"
expect_absent "T51 five-line rc: setup refuses before it asks" "[y/N]" "$T51_SET"
expect_absent "T51 five-line rc: …and never says the block was removed" "removed" "$T51_SET"
expect_contains "T51 five-line rc: …the item is marked refused" "✗ legacy alias block" "$T51_SET"

# doctor read the same rc before setup ran (above): malformed with the line, a
# hand fix, no route to setup.
T51_ROW="$(report_row "$T51_DOC" "legacy .zshrc alias block")"
expect_nonempty "T51 five-line rc: doctor renders a retired-alias row" "$T51_ROW"
expect_contains "T51 five-line rc: doctor's row says malformed" "malformed" "$T51_ROW"
expect_contains "T51 five-line rc: …and names the line" "line 2:" "$T51_ROW"
expect_absent "T51 five-line rc: …and does not send the user to setup" "/bionic:setup" "$T51_ROW"
T51_FIX="$(report_row "$T51_DOC" "retired alias block")"
expect_contains "T51 five-line rc: doctor's fix line says to fix the markers by hand" "fix them by hand" "$T51_FIX"
expect_absent "T51 five-line rc: …the fix line does not route to setup either" "/bionic:setup" "$T51_FIX"

# setup --all, answered yes. The rc already carries bionic's own claude() block,
# so the one item on the page that would write this rc has nothing to do and the
# whole file can be compared (A-T51.3); the bare five lines follow.
SB_T51A="$(new_sandbox)"; plant_t51_five "$SB_T51A/.zshrc"
printf '%s\n' "$RC_START_LIT" "$PROXY_UNALIAS" "$PROXY_LINE" "$RC_END_LIT" >> "$SB_T51A/.zshrc"
cp "$SB_T51A/.zshrc" "$TMP/t51-all.before"
T51A_INODE="$(t51_inode "$SB_T51A/.zshrc")"
T51A_SET="$(t51_setup "$SB_T51A" --all y)"
expect_contains "T51 setup --all: the run reached the retired-alias step" "Legacy shell alias" "$T51A_SET"
expect_same_bytes "T51 setup --all answered yes: the rc is byte-identical" "$TMP/t51-all.before" "$SB_T51A/.zshrc"
expect_eq "T51 setup --all: …and the same inode" "$T51A_INODE" "$(t51_inode "$SB_T51A/.zshrc")"
expect_contains "T51 setup --all: the fault is printed with its line" "$T51_FAULT" "$T51A_SET"
expect_absent "T51 setup --all: …and nothing says the block was removed" "✓ legacy alias block" "$T51A_SET"
expect_absent "T51 setup --all: the page does not offer the retired-alias step" "remove the retired shell alias block" "$T51A_SET"
SB_T51B="$(new_sandbox)"; plant_t51_five "$SB_T51B/.zshrc"
T51B_SET="$(t51_setup "$SB_T51B" --all y)"
expect_eq "T51 setup --all, the bare five lines: every line of the user's is still there, in order" \
  "$(rc_nonblock_lines "$TMP/t51-five.before")" "$(rc_nonblock_lines "$SB_T51B/.zshrc")"
expect_contains "T51 setup --all, the bare five lines: the fault is printed" "$T51_FAULT" "$T51B_SET"

# The four malformed shapes of the retired alias block, through setup and doctor.
plant_t51_shape() {  # <file> <start> <end> <shape>
  plant_rc "$1"
  case "$4" in
    start-only) printf '%s\n' "$2" 'alias claude=x' 'export MINE=1' >> "$1" ;;
    end-only)   printf '%s\n' "$3" 'export MINE=1' >> "$1" ;;
    two-starts) printf '%s\n' "$2" 'alias claude=x' "$2" 'alias claude=x' "$3" >> "$1" ;;
    two-blocks) printf '%s\n' "$2" 'alias claude=x' "$3" 'export MINE=1' "$2" 'alias claude=x' "$3" >> "$1" ;;
  esac
}
for T51_SHAPE in start-only end-only two-starts two-blocks; do
  SB_T51S="$(new_sandbox)"; plant_t51_shape "$SB_T51S/.zshrc" "$ALIAS_START" "$ALIAS_END" "$T51_SHAPE"
  cp "$SB_T51S/.zshrc" "$TMP/t51s-before.zshrc"
  L="$(rc_shape_line "$T51_SHAPE")"
  T51S_DOC="$(t51_doctor "$SB_T51S")"
  T51S_SET="$(t51_setup "$SB_T51S" legacy-alias y)"
  expect_same_bytes "T51 alias ${T51_SHAPE}: setup answered yes writes nothing" "$TMP/t51s-before.zshrc" "$SB_T51S/.zshrc"
  expect_contains "T51 alias ${T51_SHAPE}: setup prints the fault with its line" "line ${L}:" "$T51S_SET"
  expect_absent "T51 alias ${T51_SHAPE}: setup refuses before it asks" "[y/N]" "$T51S_SET"
  T51S_ROW="$(report_row "$T51S_DOC" "legacy .zshrc alias block")"
  expect_contains "T51 alias ${T51_SHAPE}: doctor's row says malformed" "malformed" "$T51S_ROW"
  expect_contains "T51 alias ${T51_SHAPE}: …and names the line" "line ${L}:" "$T51S_ROW"
  expect_absent "T51 alias ${T51_SHAPE}: …and no route to setup" "/bionic:setup" "$T51S_ROW"
done

# The same four shapes of the retired ENVIRONMENT block, through the door that
# handles it: setup and doctor have no environment-block step (A-T51.1), remove
# does, and refuses every shape byte-identically with the line.
for T51_SHAPE in start-only end-only two-starts two-blocks; do
  SB_T51V="$(new_sandbox)"; plant_t51_shape "$SB_T51V/.zshrc" "$ENVB_START" "$ENVB_END" "$T51_SHAPE"
  cp "$SB_T51V/.zshrc" "$TMP/t51v-before.zshrc"
  L="$(rc_shape_line "$T51_SHAPE")"
  T51V_OUT="$(printf 'y\n' | t51_env "$SB_T51V" bash "$REMOVE_SH" --only environment 2>&1)"
  expect_same_bytes "T51 environment ${T51_SHAPE}: remove answered yes writes nothing" "$TMP/t51v-before.zshrc" "$SB_T51V/.zshrc"
  expect_contains "T51 environment ${T51_SHAPE}: remove names the line" "line ${L}:" "$T51V_OUT"
  T51V_SET="$(t51_setup "$SB_T51V" legacy-alias y)"
  expect_same_bytes "T51 environment ${T51_SHAPE}: setup's retired-alias step leaves it alone" "$TMP/t51v-before.zshrc" "$SB_T51V/.zshrc"
done

# A WELL-FORMED retired block goes exactly as it did: every other line, the blank
# lines that separated the block from the user's text included, byte for byte.
SB_T51W="$(new_sandbox)"
printf '%s\n' 'export MINE_BEFORE=1' '' "$ALIAS_START" "alias claude='claude --dangerously-skip-permissions'" \
  "$ALIAS_END" '' 'export MINE_AFTER=1' > "$SB_T51W/.zshrc"
printf '%s\n' 'export MINE_BEFORE=1' '' '' 'export MINE_AFTER=1' > "$TMP/t51w-expected"
T51W_SET="$(t51_setup "$SB_T51W" legacy-alias y)"
expect_contains "T51 well-formed block: setup asks (the twin of the refusals)" "[y/N]" "$T51W_SET"
expect_contains "T51 well-formed block: …and says it removed it" "removed" "$T51W_SET"
expect_same_bytes "T51 well-formed block: the user's lines come back byte for byte" "$TMP/t51w-expected" "$SB_T51W/.zshrc"
T51W_ROW="$(report_row "$(t51_doctor "$SB_T51W")" "legacy .zshrc alias block")"
expect_empty "T51 well-formed block: after the strip doctor has no retired-alias row" "$T51W_ROW"

# A MARKER QUOTED IN A COMMENT IS NOT A BLOCK (F2): doctor reports none, setup
# offers nothing, the rc keeps its bytes and its inode. The twin is the whole
# block above, on the same extractors: a row, a question, a page line.
SB_T51Q="$(new_sandbox)"; printf '%s\n' "# old installs wrote a '${ALIAS_START}' line here" >> "$SB_T51Q/.zshrc"
cp "$SB_T51Q/.zshrc" "$TMP/t51q-before.zshrc"
T51Q_INODE="$(t51_inode "$SB_T51Q/.zshrc")"
SB_T51QT="$(new_sandbox)"; printf '%s\n' "$ALIAS_START" "alias claude='claude --dangerously-skip-permissions'" "$ALIAS_END" >> "$SB_T51QT/.zshrc"
expect_contains "T51 quoted-marker twin: doctor reports a whole block" "present" \
  "$(report_row "$(t51_doctor "$SB_T51QT")" "legacy .zshrc alias block")"
expect_empty "T51 quoted marker: doctor reports no retired block" \
  "$(report_row "$(t51_doctor "$SB_T51Q")" "legacy .zshrc alias block")"
expect_contains "T51 quoted-marker twin: setup --all's page offers the step" "remove the retired shell alias block" \
  "$(t51_setup "$SB_T51QT" --all n)"
T51Q_PAGE="$(t51_setup "$SB_T51Q" --all n)"
expect_contains "T51 quoted marker: setup --all printed its page" "Do all of the above?" "$T51Q_PAGE"
expect_absent "T51 quoted marker: …and the page does not offer the step" "remove the retired shell alias block" "$T51Q_PAGE"
T51Q_SET="$(t51_setup "$SB_T51Q" legacy-alias y)"
expect_contains "T51 quoted marker: setup --only says there is none" "legacy alias block     none in" "$T51Q_SET"
expect_absent "T51 quoted marker: …and asks nothing" "[y/N]" "$T51Q_SET"
expect_same_bytes "T51 quoted marker: the rc is byte-identical" "$TMP/t51q-before.zshrc" "$SB_T51Q/.zshrc"
expect_eq "T51 quoted marker: …and keeps its inode" "$T51Q_INODE" "$(t51_inode "$SB_T51Q/.zshrc")"

# A NUL BYTE IN THE RC (F5): the rc is not text, and every door says so and
# writes nothing, under /bin/bash and under the bash on PATH. Two rcs: a whole
# retired block, and the unmarked alias line — each with a NUL in a user's line.
t51_has_nul() { if LC_ALL=C tr -d '\000' < "$1" | cmp -s - "$1"; then printf 'no'; else printf 'yes'; fi; }
for T51_SH in /bin/bash "$(command -v bash)"; do
  for T51_NSHAPE in block unmarked; do
    SB_T51N="$(new_sandbox)"
    case "$T51_NSHAPE" in
      block)    printf '%s\n' "$ALIAS_START" "alias claude=x" "$ALIAS_END" >> "$SB_T51N/.zshrc" ;;
      unmarked) printf '%s\n' "alias claude='claude --dangerously-skip-permissions'" >> "$SB_T51N/.zshrc" ;;
    esac
    printf 'export MINE=1\000tail\n' >> "$SB_T51N/.zshrc"
    cp "$SB_T51N/.zshrc" "$TMP/t51n-before"
    expect_eq "T51 NUL rc ${T51_NSHAPE} (${T51_SH}): the fixture holds a NUL" "yes" "$(t51_has_nul "$SB_T51N/.zshrc")"
    T51N_SET="$(printf 'y\n' | t51_env "$SB_T51N" "$T51_SH" "$SETUP_SH" --only legacy-alias 2>&1)"
    expect_same_bytes "T51 NUL rc ${T51_NSHAPE} (${T51_SH}): setup's retired-alias step writes nothing" "$TMP/t51n-before" "$SB_T51N/.zshrc"
    expect_contains "T51 NUL rc ${T51_NSHAPE} (${T51_SH}): …and says the rc is not text" "is not text: it holds a NUL byte" "$T51N_SET"
    expect_absent "T51 NUL rc ${T51_NSHAPE} (${T51_SH}): …before it asks" "[y/N]" "$T51N_SET"
    T51N_PX="$(printf 'y\n' | t51_env "$SB_T51N" "$T51_SH" "$SETUP_SH" --only claude-proxy 2>&1)"
    expect_same_bytes "T51 NUL rc ${T51_NSHAPE} (${T51_SH}): setup's claude() step writes nothing" "$TMP/t51n-before" "$SB_T51N/.zshrc"
    expect_contains "T51 NUL rc ${T51_NSHAPE} (${T51_SH}): …and says why" "is not text: it holds a NUL byte" "$T51N_PX"
    for T51_RITEM in legacy-alias environment claude-proxy; do
      T51N_RM="$(printf 'y\n' | t51_env "$SB_T51N" "$T51_SH" "$REMOVE_SH" --only "$T51_RITEM" 2>&1)"
      expect_same_bytes "T51 NUL rc ${T51_NSHAPE} (${T51_SH}): remove ${T51_RITEM} writes nothing" "$TMP/t51n-before" "$SB_T51N/.zshrc"
      expect_contains "T51 NUL rc ${T51_NSHAPE} (${T51_SH}): remove ${T51_RITEM} says why" "is not text: it holds a NUL byte" "$T51N_RM"
    done
  done
  T51N_ROW="$(report_row "$(t51_env "$SB_T51N" "$T51_SH" "$DOCTOR_SH" </dev/null 2>&1)" "$DOCTOR_ROW_LABEL")"
  expect_contains "T51 NUL rc (${T51_SH}): doctor's claude() row says not text" "not text" "$T51N_ROW"
done
# The twin: the same rc without the NUL is read, and bionic's line in it named (T75: a
# bare line is never taken out).
SB_T51NT="$(new_sandbox)"; printf '%s\n' "alias claude='claude --dangerously-skip-permissions'" 'export MINE=1' >> "$SB_T51NT/.zshrc"
T51NT_SET="$(t51_setup "$SB_T51NT" legacy-alias y)"
expect_contains "T51 NUL twin: the line with no NUL is read and named as bionic's" "outside bionic's markers" "$T51NT_SET"
expect_eq "T51 NUL twin: …and the user's line after it stays" "1" "$(count_lines_equal "$SB_T51NT/.zshrc" 'export MINE=1')"

# A DANGLING RC LINK names where it points (F3).
SB_T51L="$(new_sandbox)"; rm -f "$SB_T51L/.zshrc"; ln -s "$SB_T51L/dotfiles/zshrc" "$SB_T51L/.zshrc"
T51L_SET="$(t51_setup "$SB_T51L" claude-proxy y)"
expect_contains "T51 dangling rc: setup names where the link points" "a link to ${SB_T51L}/dotfiles/zshrc, which does not exist" "$T51L_SET"
expect_eq "T51 dangling rc: …and creates nothing there" "no" "$( [ -e "$SB_T51L/dotfiles/zshrc" ] && echo yes || echo no)"

# AN RC THAT IS NO FILE, UNDER remove --all (F7): the two retired-block items do
# not call it "already clean"; they say it was not checked, and why.
t51_item_lines() {  # <output> <item header> — the item's lines, header to the blank line after it
  local line inside=0
  while IFS= read -r line; do
    if [ "$inside" = "0" ]; then [ "$line" = "$2" ] && inside=1; continue; fi
    [ -z "$line" ] && return 0
    printf '%s\n' "$line"
  done <<< "$1"
}
# A PAGE ITEM OF ITS OWN (wave-27 T82). Each `--all` sandbox here carries the pre-plugin
# skill copy `legacy-skill-copy` offers, so the page prints and the items run under its
# consent as these rows mean them. The page used to be filled by the claude stub, whose exit 0
# made every MCP tool row read present; tool rows are never on the page now.
t51_page_item() { mkdir -p "$1/.claude/skills/canonical-sdlc"; printf -- '---\nname: canonical-sdlc\n---\n' > "$1/.claude/skills/canonical-sdlc/SKILL.md"; }
SB_T51D="$(new_sandbox)"; rm -f "$SB_T51D/.zshrc"; mkdir "$SB_T51D/.zshrc"; t51_page_item "$SB_T51D"
T51D_ALL="$(printf 'y\n' | t51_env "$SB_T51D" bash "$REMOVE_SH" --all 2>&1)"
for T51_HDR in "legacy shell alias block:" "bionic's environment settings:"; do
  T51D_ITEM="$(t51_item_lines "$T51D_ALL" "$T51_HDR")"
  expect_nonempty "T51 rc a directory, remove --all: the '${T51_HDR}' item printed lines" "$T51D_ITEM"
  expect_contains "T51 rc a directory, remove --all: '${T51_HDR}' says the rc was not checked" "not checked" "$T51D_ITEM"
  expect_absent "T51 rc a directory, remove --all: '${T51_HDR}' does not call it already clean" "already clean" "$T51D_ITEM"
done
# The twin: a regular rc with neither block is already clean, on the same extractor.
SB_T51DT="$(new_sandbox)"; t51_page_item "$SB_T51DT"
T51DT_ITEM="$(t51_item_lines "$(printf 'y\n' | t51_env "$SB_T51DT" bash "$REMOVE_SH" --all 2>&1)" "legacy shell alias block:")"
expect_contains "T51 rc a regular file, remove --all: the retired-alias item is already clean (the twin)" "already clean" "$T51DT_ITEM"

# ---------------------------------------------------------------------------
section "wave-27 T55: the unmarked step removes only a line bionic wrote, whole"
# ---------------------------------------------------------------------------
#
# Review pass 32 F1 (blocker, in 1.11.0): setup's and remove's unmarked retired-alias
# step deleted every line `alias claude=.*dangerously-skip-permissions` matched —
# a user's comment, a second command sharing the line, the user's own alias inside
# an `if` (a bash rc then fails `bash -n`). F4: it wrote through a read-only rc.
# Now a line goes only when the whole line, blanks and one trailing CR aside, is one
# bionic wrote (detect.sh's list); any other match is left byte for byte and named
# by its line NUMBER only, never its text. Every run below is `t51_env`'s: `env -i`
# with the four roots inside the sandbox, read back out of `env` here too.

T55_EXACT="alias claude='claude --dangerously-skip-permissions'"
SB_T55E="$(new_sandbox)"
T55_ENV_OUT="$(t51_env "$SB_T55E" env)"
for T55_VAR in HOME ZDOTDIR CLAUDE_CONFIG_DIR BIONIC_CLAUDE_HOME; do
  T55_VAL="$(t51_env_var "$T55_ENV_OUT" "$T55_VAR")"
  case "$T55_VAL" in "$SB_T55E"|"$SB_T55E"/*) ok "T55 fixture: ${T55_VAR} is inside the throwaway home" ;;
    *) no "T55 fixture: ${T55_VAR} is inside the throwaway home" "got '${T55_VAL}'" ;; esac
  expect_ne "T55 fixture: ${T55_VAR} is not the real home" "$HOME" "$T55_VAL"
done

# The five doors every shape goes through, answered <answer>.
t55_door() {  # <sandbox> <door> <answer>
  case "$2" in
    setup-only) printf '%s\n' "$3" | t51_env "$1" bash "$SETUP_SH" --only legacy-alias 2>&1 ;;
    setup-all)  printf '%s\n' "$3" | t51_env "$1" bash "$SETUP_SH" --all 2>&1 ;;
    rm-payload) printf '%s\n' "$3" | t51_env "$1" bash "$REMOVE_SH" --only legacy-alias 2>&1 ;;
    rm-standalone) printf '%s\n' "$3" | t51_env "$1" bash "$TMP/standalone/remove.sh" --only legacy-alias 2>&1 ;;
    rm-all)     printf '%s\n' "$3" | t51_env "$1" bash "$REMOVE_SH" --all 2>&1 ;;
  esac
}
# How many lines of <text> hold <needle>.
t55_count() {  # <text> <needle>
  local line n=0
  while IFS= read -r line; do case "$line" in *"$2"*) n=$((n + 1)) ;; esac; done <<< "$1"
  printf '%s' "$n"
}
# The rc for a shape; setup --all gets bionic's own claude() block appended, so the
# one other item on its page that writes this rc has nothing to do (A-T51.3).
t55_plant() {  # <file> <shape> <door>
  case "$2" in
    comment) printf '%s\n' 'export A=1' "# my note: never use ${T55_EXACT} again" 'export B=2' > "$1" ;;
    shared)  printf '%s\n' 'export A=1' "${T55_EXACT}; export MYTOKEN=abc" > "$1" ;;
    in-if)   printf '%s\n' 'if [ -n "$WORK" ]; then' "  alias claude='claude --dangerously-skip-permissions --model opus'" 'fi' > "$1" ;;
  esac
  [ "$3" = "setup-all" ] && printf '%s\n' "$RC_START_LIT" "$PROXY_UNALIAS" "$PROXY_LINE" "$RC_END_LIT" >> "$1"
  return 0
}

# THE THREE LOST-LINE SHAPES OF THE REVIEW: nothing offered, nothing removed, each
# named once by line number (2), its text never printed.
for T55_SHAPE in comment shared in-if; do
  for T55_DOOR in setup-only setup-all rm-payload rm-standalone rm-all; do
    SB_T55="$(new_sandbox)"; t55_plant "$SB_T55/.zshrc" "$T55_SHAPE" "$T55_DOOR"
    cp "$SB_T55/.zshrc" "$TMP/t55-before"; T55_INODE="$(t51_inode "$SB_T55/.zshrc")"
    T55_OUT="$(t55_door "$SB_T55" "$T55_DOOR" y)"
    T55_L="T55 ${T55_SHAPE} (${T55_DOOR})"
    expect_contains "${T55_L}: the run reached the machine (the rows below are not vacuous)" "bionic" "$T55_OUT"
    expect_same_bytes "${T55_L}: answered yes, the rc is byte-identical" "$TMP/t55-before" "$SB_T55/.zshrc"
    expect_eq "${T55_L}: …and keeps its inode" "$T55_INODE" "$(t51_inode "$SB_T55/.zshrc")"
    expect_eq "${T55_L}: the line is named as not in a form bionic wrote, once" "1" "$(t55_count "$T55_OUT" "not in a form bionic wrote")"
    expect_contains "${T55_L}: …by its number" "line 2 of" "$(report_row "$T55_OUT" "not in a form bionic wrote")"
    expect_absent "${T55_L}: …and never by its text" "my note" "$T55_OUT"
    expect_absent "${T55_L}: …nor the text of a line it shares" "MYTOKEN" "$T55_OUT"
    expect_absent "${T55_L}: …nor the user's own flags" "--model opus" "$T55_OUT"
    expect_absent "${T55_L}: …and never called not bionic's" "not bionic's:" "$T55_OUT"
    expect_absent "${T55_L}: no page offers a removal for it" "retired alias line" "$T55_OUT"
    expect_absent "${T55_L}: …nothing says it was removed" "(the unmarked spelling)" "$T55_OUT"
    case "$T55_DOOR" in setup-only|rm-payload|rm-standalone)
      expect_absent "${T55_L}: …and the narrowed run asks nothing" "[y/N]" "$T55_OUT" ;;
    esac
  done
done
# The `if` shape still parses as bash afterwards, as before (the review's lost `fi`).
SB_T55B="$(new_sandbox)"; t55_plant "$SB_T55B/.zshrc" in-if setup-only
expect_true "T55 in-if: the planted rc parses under bash -n (the positive)" bash -n "$SB_T55B/.zshrc"
t55_door "$SB_T55B" setup-only y >/dev/null
expect_true "T55 in-if: …and still parses after setup answered yes" bash -n "$SB_T55B/.zshrc"
# doctor on each shape: one row, the line number, a hand fix, no route to setup.
for T55_SHAPE in comment shared in-if; do
  SB_T55D="$(new_sandbox)"; t55_plant "$SB_T55D/.zshrc" "$T55_SHAPE" setup-only
  T55_DOC="$(t51_doctor "$SB_T55D")"
  T55_DROW="$(report_row "$T55_DOC" "not in a form bionic wrote")"
  expect_contains "T55 ${T55_SHAPE} (doctor): a row names the line as not in a form bionic wrote" "line 2 of" "$T55_DROW"
  expect_contains "T55 ${T55_SHAPE} (doctor): …and the file it is in, whole" "line 2 of ~/.zshrc" "$T55_DROW"
  expect_contains "T55 ${T55_SHAPE} (doctor): …and says to edit it by hand" "by hand" "$T55_DROW"
  expect_absent "T55 ${T55_SHAPE} (doctor): …with no route to setup" "/bionic:setup" "$T55_DROW"
  expect_eq "T55 ${T55_SHAPE} (doctor): said once" "1" "$(t55_count "$T55_DOC" "not in a form bionic wrote")"
  expect_absent "T55 ${T55_SHAPE} (doctor): the alias row does not call it present" "present →" "$(report_row "$T55_DOC" "legacy .zshrc alias block")"
  expect_absent "T55 ${T55_SHAPE} (doctor): …and the line's text is not printed" "MYTOKEN" "$T55_DOC"
done

# THE EXACT LINE, in each shape bionic's own line can take on disk, through every door:
# never taken out (wave-27 T75, A-orch-162: the markers are the whole rule). Answered
# yes, the rc is byte-identical and the line is named by its number as bionic's line
# outside its markers, never by its text, and nothing is asked.
t55_exact() {  # <file> <expected> <shape>
  case "$3" in
    line7)    printf '%s\n' 'export A=1' 'export B=2' '# three' 'export C=3' '' 'export D=4' "$T55_EXACT" 'export E=5' > "$1"
              printf '%s\n' 'export A=1' 'export B=2' '# three' 'export C=3' '' 'export D=4' 'export E=5' > "$2" ;;
    indented) printf 'export A=1\n  \t%s \t\nexport B=2\n' "$T55_EXACT" > "$1"; printf 'export A=1\nexport B=2\n' > "$2" ;;
    crlf)     printf 'export A=1\r\n%s\r\nexport B=2\r\n' "$T55_EXACT" > "$1"; printf 'export A=1\r\nexport B=2\r\n' > "$2" ;;
    nofinal)  printf '%s\nexport B=2' "$T55_EXACT" > "$1"; printf 'export B=2' > "$2" ;;
    lastline) printf 'export A=1\n%s' "$T55_EXACT" > "$1"; printf 'export A=1\n' > "$2" ;;
  esac
}
t55_exact_line() { case "$1" in line7) echo 7 ;; lastline) echo 2 ;; indented|crlf) echo 2 ;; nofinal) echo 1 ;; esac; }
for T55_SHAPE in line7 indented crlf nofinal lastline; do
  for T55_DOOR in setup-only setup-all rm-payload rm-standalone rm-all; do
    # setup --all appends its claude() block; on an rc with no final newline the
    # fixture's own append would fuse with bionic's line, so that pair is not a shape.
    [ "$T55_SHAPE:$T55_DOOR" = "lastline:setup-all" ] && continue
    SB_T55X="$(new_sandbox)"; t55_exact "$SB_T55X/.zshrc" "$TMP/t55x-unused" "$T55_SHAPE"
    [ "$T55_DOOR" = "setup-all" ] && printf '%s\n' "$RC_START_LIT" "$PROXY_UNALIAS" "$PROXY_LINE" "$RC_END_LIT" >> "$SB_T55X/.zshrc"
    cp "$SB_T55X/.zshrc" "$TMP/t55x-before"; T55_INODE="$(t51_inode "$SB_T55X/.zshrc")"
    T55_N="$(t55_exact_line "$T55_SHAPE")"
    T55_L="T55 exact ${T55_SHAPE} (${T55_DOOR})"
    T55_YES="$(t55_door "$SB_T55X" "$T55_DOOR" y)"
    expect_contains "${T55_L}: the run reached the machine" "bionic" "$T55_YES"
    expect_same_bytes "${T55_L}: answered yes, bionic's bare line stays and the rc is byte-identical" "$TMP/t55x-before" "$SB_T55X/.zshrc"
    expect_eq "${T55_L}: …and keeps its inode" "$T55_INODE" "$(t51_inode "$SB_T55X/.zshrc")"
    expect_eq "${T55_L}: the line is named as bionic's, outside its markers, once" "1" "$(t55_count "$T55_YES" "outside bionic's markers")"
    expect_contains "${T55_L}: …by its number" "line ${T55_N} of" "$(report_row "$T55_YES" "outside bionic's markers")"
    expect_absent "${T55_L}: …nothing offers to remove it" "retired alias line" "$T55_YES"
    expect_absent "${T55_L}: …nothing says it was removed" "(the unmarked spelling)" "$T55_YES"
    case "$T55_DOOR" in setup-only|rm-payload|rm-standalone) expect_absent "${T55_L}: …and nothing is asked" "[y/N]" "$T55_YES" ;; esac
  done
done

# A FILE HOLDING BOTH: both stay, each named by its number and in its own words.
for T55_DOOR in setup-only setup-all rm-payload rm-standalone rm-all; do
  SB_T55M="$(new_sandbox)"
  printf '%s\n' 'export A=1' "$T55_EXACT" 'export B=2' "${T55_EXACT}; export MYTOKEN=abc" > "$SB_T55M/.zshrc"
  cp "$SB_T55M/.zshrc" "$TMP/t55m-expected"
  if [ "$T55_DOOR" = "setup-all" ]; then
    printf '%s\n' "$RC_START_LIT" "$PROXY_UNALIAS" "$PROXY_LINE" "$RC_END_LIT" | tee -a "$SB_T55M/.zshrc" >> "$TMP/t55m-expected"
  fi
  T55M_OUT="$(t55_door "$SB_T55M" "$T55_DOOR" y)"
  expect_same_bytes "T55 both kinds (${T55_DOOR}): both lines stay, byte for byte" "$TMP/t55m-expected" "$SB_T55M/.zshrc"
  expect_contains "T55 both kinds (${T55_DOOR}): bionic's line is named by its number" "line 2 of" "$(report_row "$T55M_OUT" "outside bionic's markers")"
  expect_contains "T55 both kinds (${T55_DOOR}): the user's line is named as left, by its number" "line 4 of" "$(report_row "$T55M_OUT" "not in a form bionic wrote")"
  expect_absent "T55 both kinds (${T55_DOOR}): …never by its text" "MYTOKEN" "$T55M_OUT"
done

# A READ-ONLY RC: bionic's bare line is never taken out, so there is nothing to refuse:
# nothing written, the inode kept, the line named as on a writable rc (T75).
for T55_DOOR in setup-only rm-payload rm-standalone rm-all; do
  SB_T55R="$(new_sandbox)"; t55_exact "$SB_T55R/.zshrc" "$TMP/t55r-unused" line7
  cp "$SB_T55R/.zshrc" "$TMP/t55r-before"; chmod 444 "$SB_T55R/.zshrc"; T55R_INODE="$(t51_inode "$SB_T55R/.zshrc")"
  T55R_OUT="$(t55_door "$SB_T55R" "$T55_DOOR" y)"
  chmod 644 "$SB_T55R/.zshrc"
  expect_same_bytes "T55 read-only (${T55_DOOR}): nothing written" "$TMP/t55r-before" "$SB_T55R/.zshrc"
  expect_eq "T55 read-only (${T55_DOOR}): …the same inode" "$T55R_INODE" "$(t51_inode "$SB_T55R/.zshrc")"
  expect_contains "T55 read-only (${T55_DOOR}): the line is named by its number" "line 7 of" "$(report_row "$T55R_OUT" "outside bionic's markers")"
  expect_absent "T55 read-only (${T55_DOOR}): …never removed" "(the unmarked spelling)" "$T55R_OUT"
done

# THE FIRST INSTALLER'S LINE (A-orch-93): e178aecc wrote `alias claude='<P> …'` with
# P the path `command -v claude` gave on that machine, or empty. One template holds
# it: P empty, or absolute, ending in the component `claude`, holding no white
# space, quote, `$`, backquote or `;`. Anything else in its shape is left and named.
t55_tpl() {  # <shape> — the line at line 2
  case "$1" in
    homebrew)  printf '%s' "alias claude='/opt/homebrew/bin/claude --dangerously-skip-permissions'" ;;
    empty-p)   printf '%s' "alias claude=' --dangerously-skip-permissions'" ;;
    space)     printf '%s' "alias claude='/Users/a b/bin/claude --dangerously-skip-permissions'" ;;
    relative)  printf '%s' "alias claude='bin/claude --dangerously-skip-permissions'" ;;
    claude2)   printf '%s' "alias claude='/usr/local/bin/claude2 --dangerously-skip-permissions'" ;;
    dir-slash) printf '%s' "alias claude='/usr/local/bin/claude/ --dangerously-skip-permissions'" ;;
    dollar)    printf '%s' "alias claude='\$HOME/.local/bin/claude --dangerously-skip-permissions'" ;;
    flag)      printf '%s' "alias claude='/opt/homebrew/bin/claude --model opus --dangerously-skip-permissions'" ;;
    trailing)  printf '%s' "alias claude='/opt/homebrew/bin/claude --dangerously-skip-permissions' # mine" ;;
    dquote)    printf '%s' 'alias claude="/opt/homebrew/bin/claude --dangerously-skip-permissions"' ;;
  esac
}
for T55_SHAPE in homebrew empty-p space relative claude2 dir-slash dollar flag trailing dquote; do
  for T55_DOOR in setup-only rm-payload rm-standalone; do
    SB_T55T="$(new_sandbox)"
    printf '%s\n' 'export A=1' "$(t55_tpl "$T55_SHAPE")" 'export B=2' > "$SB_T55T/.zshrc"
    cp "$SB_T55T/.zshrc" "$TMP/t55t-before"; printf '%s\n' 'export A=1' 'export B=2' > "$TMP/t55t-removed"
    T55T_OUT="$(t55_door "$SB_T55T" "$T55_DOOR" y)"
    T55_L="T55 template ${T55_SHAPE} (${T55_DOOR})"
    case "$T55_SHAPE" in
      homebrew|empty-p)
        expect_same_bytes "${T55_L}: bionic's line, left byte for byte (T75: never taken out)" "$TMP/t55t-before" "$SB_T55T/.zshrc"
        expect_contains "${T55_L}: …named as bionic's line, by its number" "line 2 of" "$(report_row "$T55T_OUT" "outside bionic's markers")"
        expect_absent "${T55_L}: …and nothing asked" "[y/N]" "$T55T_OUT" ;;
      *)
        expect_same_bytes "${T55_L}: not a form bionic wrote, left byte for byte" "$TMP/t55t-before" "$SB_T55T/.zshrc"
        expect_contains "${T55_L}: …named by its number" "line 2 of" "$(report_row "$T55T_OUT" "not in a form bionic wrote")"
        expect_absent "${T55_L}: …and nothing asked" "[y/N]" "$T55T_OUT" ;;
    esac
  done
done

# THE LIST AND ITS STANDALONE COPY (F1): remove.sh carries detect.sh's functions
# whole, name and body, and its copy of the loose pattern; a one-line mutant moves it.
# A LATER DEFINITION SHADOWS THE PINNED ONE (wave-27 T66, review pass 40 S4): a
# second `name() {` appended to remove.sh wins at run time while the first still
# matches the library. So every definition is read, and two or more print a line
# no library text can equal: the pin goes red rather than reading the first.
fn_text() {  # <file> <name> — the function's lines, `name() {` through the first `}` alone
  local line inside=0 defs=0 text=""
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$inside" = "0" ]; then case "$line" in "$2() {"*) inside=1; defs=$((defs + 1)) ;; *) continue ;; esac; fi
    [ "$defs" = "1" ] && text="${text}${line}"$'\n'
    [ "$line" = "}" ] && inside=0
  done < "$1"
  if [ "$defs" -gt 1 ]; then printf 'fn_text: %s is defined %s times in %s\n' "$2" "$defs" "$1"; return 0; fi
  printf '%s' "$text"
  return 0
}
for T55_FN in bionic_legacy_alias_ours bionic_legacy_alias_lines bionic_line_numbers_words; do
  T55_LIB="$DETECT_SH"
  T55_A="$(fn_text "$T55_LIB" "$T55_FN")"
  expect_nonempty "T55 copies: ${T55_FN} reads out of its library" "$T55_A"
  expect_eq "T55 copies: remove.sh's ${T55_FN} is the library's, line for line" "$T55_A" "$(fn_text "$REMOVE_SH" "$T55_FN")"
done
T55_PAT="$(const_from "$DETECT_SH" BIONIC_LEGACY_ALIAS_PATTERN)" || T55_PAT=""
expect_nonempty "T55 copies: detect.sh carries the loose pattern" "$T55_PAT"
expect_eq "T55 copies: remove.sh's loose pattern is detect.sh's" "$T55_PAT" "$(const_from "$REMOVE_SH" BIONIC_LEGACY_ALIAS_PATTERN)"
sed "s/--dangerously-skip-permissions'\") return 0/--dangerously-skip-permissions --x'\") return 0/" "$REMOVE_SH" > "$TMP/t55-remove-mutant.sh"
expect_true "T55 copies: the list mutant still parses" bash -n "$TMP/t55-remove-mutant.sh"
expect_ne "T55 copies: …and its list no longer matches the library's (the pin can go red)" \
  "$(fn_text "$DETECT_SH" bionic_legacy_alias_ours)" "$(fn_text "$TMP/t55-remove-mutant.sh" bionic_legacy_alias_ours)"

# NOTE 8, THE PAGE: remove --all leaves a retired block whose markers do not pair
# up off its page, as setup's page does; the twin, a whole block, is on it.
SB_T55P="$(new_sandbox)"; printf '%s\n' "$ALIAS_START" 'export MINE=1' >> "$SB_T55P/.zshrc"
T55P_OUT="$(t55_door "$SB_T55P" rm-all n)"
expect_absent "T55 page: an unpaired retired block is not on remove --all's page" "remove the retired shell alias block" "$T55P_OUT"
SB_T55PT="$(new_sandbox)"; printf '%s\n' "$ALIAS_START" "$T55_EXACT" "$ALIAS_END" >> "$SB_T55PT/.zshrc"
expect_contains "T55 page: …a whole one is (the twin)" "remove the retired shell alias block" "$(t55_door "$SB_T55PT" rm-all n)"
expect_contains "T55 page: --only still refuses the unpaired block, naming why" "do not pair up" "$(t55_door "$SB_T55P" rm-payload y)"

section "wave-27 T66: bionic's own line goes only as a command of its own"
# ---------------------------------------------------------------------------
#
# Review pass 40 on T55. B1 (blocker): bionic's exact alias line was removed wherever
# it sat, so inside the user's `if` or function a bash rc no longer parsed, and inside a
# here-document the user's data changed. Now a line goes only when (a) the line before
# it does not continue onto it, (b) it is a command and not data (with the line replaced
# by `)` the rc no longer parses), and (c) the rc parses before and without it, each
# asked of the rc's OWN shell (`bash -n` for a .bashrc, `zsh -n` for a .zshrc) on staged
# copies; any other case is left byte for byte and named by number. B2 (in 1.11.0):
# remove's environment item deleted every line its loose filter matched; it gets the
# same rule whole. B3: the template's path is a whitelist. S1–S5 and N1 ride with them.
# Every run here is `t66_env`'s: `env -i`, the four roots inside the sandbox, read back
# out of `env` below; nothing of an rc is ever run, only parsed with `-n`.

T66_ALIAS="$T55_EXACT"
T66_TODO='export CLAUDE_CODE_ENABLE_TODO_TOOLS=1'
T66_SHELL=/bin/bash
T66_PATH="$T51_PATH"
t66_env() {  # <sandbox> <command...> — t51_env with this section's SHELL and PATH
  local sb="$1"; shift
  mkdir -p "$sb/.tmp"
  env -i HOME="$sb" ZDOTDIR="$sb" CLAUDE_CONFIG_DIR="$sb/.claude" BIONIC_CLAUDE_HOME="$sb/.claude" \
    SHELL="$T66_SHELL" PATH="$T66_PATH" TMPDIR="$sb/.tmp" TERM=dumb BIONIC_DOCTOR_PROBE_SECONDS=15 "$@"
}
t66_rc() { case "$T66_SHELL" in */zsh) printf '%s' "$1/.zshrc" ;; *) printf '%s' "$1/.bashrc" ;; esac; }
t66_parses() {  # <file> — the rc's own shell, -n only
  case "$T66_SHELL" in */zsh) zsh -f -n "$1" >/dev/null 2>&1 ;; *) BASH_ENV= /bin/bash -n "$1" >/dev/null 2>&1 ;; esac
}
t66_door() {  # <sandbox> <door> <answer> [item]
  local item="${4:-legacy-alias}"
  case "$2" in
    setup-only)    printf '%s\n' "$3" | t66_env "$1" bash "$SETUP_SH" --only "$item" 2>&1 ;;
    setup-all)     printf '%s\n' "$3" | t66_env "$1" bash "$SETUP_SH" --all 2>&1 ;;
    rm-payload)    printf '%s\n' "$3" | t66_env "$1" bash "$REMOVE_SH" --only "$item" 2>&1 ;;
    rm-standalone) printf '%s\n' "$3" | t66_env "$1" bash "$TMP/standalone/remove.sh" --only "$item" 2>&1 ;;
    rm-all)        printf '%s\n' "$3" | t66_env "$1" bash "$REMOVE_SH" --all 2>&1 ;;
    doctor)        t66_env "$1" bash "$DOCTOR_SH" </dev/null 2>&1 ;;
  esac
}
# The phrase each door names a line of bionic's that stays with (said once per door).
t66_phrase() { case "$1" in doctor) printf '%s' "bionic's old line" ;; *) printf '%s' "outside bionic's markers" ;; esac; }

# THE FIXTURE CANNOT REACH THE REAL HOME, with this section's SHELL.
SB_T66E="$(new_sandbox)"
T66_ENV_OUT="$(t66_env "$SB_T66E" env)"
for T66_VAR in HOME ZDOTDIR CLAUDE_CONFIG_DIR BIONIC_CLAUDE_HOME; do
  T66_VAL="$(t51_env_var "$T66_ENV_OUT" "$T66_VAR")"
  case "$T66_VAL" in "$SB_T66E"|"$SB_T66E"/*) ok "T66 fixture: ${T66_VAR} is inside the throwaway home" ;;
    *) no "T66 fixture: ${T66_VAR} is inside the throwaway home" "got '${T66_VAL}'" ;; esac
  expect_ne "T66 fixture: ${T66_VAR} is not the real home" "$HOME" "$T66_VAL"
done
expect_eq "T66 fixture: SHELL is the one this section sets" "/bin/bash" "$(t51_env_var "$T66_ENV_OUT" SHELL)"

# The shapes. <file> gets the rc, <expected> what a removal must leave (or the rc
# itself when the line stays). L is bionic's exact line; SECRETTOKEN is the user's
# text, which no door may print.
t66_plant() {  # <file> <expected> <shape> <line> [verdict]
  local L="$4"
  case "$3" in
    if-only)    printf '%s\n' 'if [ -n "$SECRETTOKEN" ]; then' "$L" 'fi' > "$1" ;;
    for-only)   printf '%s\n' 'for SECRETTOKEN in a b; do' "$L" 'done' > "$1" ;;
    fn-only)    printf '%s\n' 'SECRETTOKEN() {' "$L" '}' > "$1" ;;
    heredoc)    printf '%s\n' "cat > /dev/null <<'EOF'" "$L" 'EOF' 'export SECRETTOKEN=1' > "$1" ;;
    dquote)     printf '%s\n' 'export X="SECRETTOKEN' "$L" 'b"' > "$1" ;;
    backslash)  printf '%s\n' 'echo SECRETTOKEN \' "$L" 'echo two' > "$1" ;;
    andand)     printf '%s\n' 'test -n "$SECRETTOKEN" &&' "$L" 'export A=1' > "$1" ;;
    bs-comment) printf '%s\n' 'echo SECRETTOKEN \' '# a comment line between' "$L" 'echo two' > "$1" ;;
    case-arm)   printf '%s\n' 'case "$SECRETTOKEN" in' '  a)' "$L" '    ;;' 'esac' > "$1" ;;
    no-parse)   printf '%s\n' 'export SECRETTOKEN=1' "$L" 'fi' > "$1" ;;
    two-in-if)  printf '%s\n' 'if [ -n "$SECRETTOKEN" ]; then' '  export A=1' "$L" 'fi' > "$1"
                printf '%s\n' 'if [ -n "$SECRETTOKEN" ]; then' '  export A=1' 'fi' > "$2"; return 0 ;;
    top-and-if) printf '%s\n' 'if [ -n "$SECRETTOKEN" ]; then' "$L" 'fi' "$L" > "$1" ;;
    top)        printf '%s\n' 'export SECRETTOKEN=1' "$L" 'export B=2' > "$1"
                printf '%s\n' 'export SECRETTOKEN=1' 'export B=2' > "$2"; return 0 ;;
  esac
  if [ "${5:-left}" = "removed" ]; then awk -v l="$L" '$0 != l' "$1" > "$2"; else cp "$1" "$2"; fi
}
t66_pageblock() { printf '%s\n' "$RC_START_LIT" "$PROXY_UNALIAS" "$PROXY_LINE" "$RC_END_LIT"; }

# B1 THROUGH EVERY DOOR. <verdict> is what the rc's own shell rules: `left` keeps the
# rc byte for byte and names line 2 once by number; `removed` takes bionic's line and
# leaves every other byte. Shell answers for these shapes (bash 3.2 / zsh 5.9, -n on
# the rc without the line): an empty `then`, `do` or function body is a bash syntax
# error and zsh accepts it, so the zsh rows below remove what the bash rows leave.
t66_b1() {  # <shell> <shape> <verdict>
  local door sb rc out L
  T66_SHELL="$1"
  for door in setup-only setup-all rm-payload rm-standalone rm-all; do
    sb="$(new_sandbox)"; rc="$(t66_rc "$sb")"
    t66_plant "$rc" "$TMP/t66-expected" "$2" "$T66_ALIAS" "$3"
    [ "$door" = "setup-all" ] && t66_pageblock | tee -a "$rc" >> "$TMP/t66-expected"
    cp "$rc" "$TMP/t66-before"; T66_INODE="$(t51_inode "$rc")"
    L="T66 B1 ${2} (${1##*/}, ${door})"
    expect_true "${L}: the planted rc parses under its own shell (the positive)" t66_parses "$TMP/t66-before"
    out="$(t66_door "$sb" "$door" y)"
    expect_contains "${L}: the run reached the machine" "bionic" "$out"
    expect_true "${L}: the rc still parses under its own shell" t66_parses "$rc"
    expect_absent "${L}: the user's text is never printed" "SECRETTOKEN" "$out"
    case "$3" in
      left)
        expect_same_bytes "${L}: answered yes, the rc is byte-identical" "$TMP/t66-before" "$rc"
        expect_eq "${L}: …and keeps its inode" "$T66_INODE" "$(t51_inode "$rc")"
        expect_eq "${L}: the line is named as bionic's, inside your own code, once" "1" "$(t55_count "$out" "$(t66_phrase "$door")")"
        expect_contains "${L}: …by its number" "line ${T66_LINE:-2} of" "$(report_row "$out" "$(t66_phrase "$door")")"
        expect_absent "${L}: …and never by its text" "alias claude='claude" "$out"
        expect_absent "${L}: …nothing says it was removed" "(the unmarked spelling)" "$out"
        expect_absent "${L}: …no page offers it" "retired alias line" "$out"
        case "$door" in setup-only|rm-payload|rm-standalone)
          expect_absent "${L}: …and the narrowed run asks nothing" "[y/N]" "$out" ;;
        esac ;;
      removed)
        expect_same_bytes "${L}: answered yes, bionic's line goes and every other byte stays" "$TMP/t66-expected" "$rc"
        expect_absent "${L}: …and nothing is called inside your own code" "$(t66_phrase "$door")" "$out" ;;
    esac
  done
}
for T66_SHAPE in if-only for-only fn-only heredoc dquote backslash andand; do t66_b1 /bin/bash "$T66_SHAPE" left; done
# T75 (A-orch-162): the markers are the whole rule. Bionic's bare line is never taken out,
# wherever it stands and under either shell: each door leaves the rc byte-identical and
# names the line by number, as bionic's line outside its markers, for the user's hand.
T66_LINE=3 t66_b1 /bin/bash bs-comment left
t66_b1 /bin/bash top left
t66_b1 /bin/zsh top left
T66_LINE=3 t66_b1 /bin/bash two-in-if left
T66_LINE=3 t66_b1 /bin/bash case-arm left
T66_LINE=3 t66_b1 /bin/zsh case-arm left
for T66_SHAPE in if-only for-only fn-only; do t66_b1 /bin/zsh "$T66_SHAPE" left; done
for T66_SHAPE in heredoc dquote backslash andand; do t66_b1 /bin/zsh "$T66_SHAPE" left; done

# The line at top level in a file that also holds it inside an `if`: the top one goes,
# the other stays and is named (line 2 in the file before and after).
for T66_DOOR in setup-only setup-all rm-payload rm-standalone rm-all; do
  T66_SHELL=/bin/bash
  SB_T66T="$(new_sandbox)"; T66_RC="$(t66_rc "$SB_T66T")"
  t66_plant "$T66_RC" "$TMP/t66t-expected" top-and-if "$T66_ALIAS"
  [ "$T66_DOOR" = "setup-all" ] && t66_pageblock | tee -a "$T66_RC" >> "$TMP/t66t-expected"
  T66T_OUT="$(t66_door "$SB_T66T" "$T66_DOOR" y)"
  expect_same_bytes "T66 B1 top-and-if (${T66_DOOR}): both bare lines stay, the one inside the if and the one at the top" "$TMP/t66t-expected" "$T66_RC"
  expect_contains "T66 B1 top-and-if (${T66_DOOR}): …both named by number" "lines 2, 4 of" "$(report_row "$T66T_OUT" "$(t66_phrase "$T66_DOOR")")"
  expect_true "T66 B1 top-and-if (${T66_DOOR}): the rc parses after" t66_parses "$T66_RC"
done

# The reason a block stays is said in each door's words: an rc that did not parse
# before, and an rc whose shell is not installed (T75: a bare line is never asked about).
t75_npblock() {  # <file> <shape>
  case "$2" in
    no-parse) printf '%s\n' 'export SECRETTOKEN=1' "$ALIAS_START" "$T66_ALIAS" "$ALIAS_END" 'fi' > "$1" ;;
    top)      printf '%s\n' 'export SECRETTOKEN=1' "$ALIAS_START" "$T66_ALIAS" "$ALIAS_END" 'export B=2' > "$1" ;;
  esac
}
T66_SHELL=/bin/bash
for T66_DOOR in setup-only setup-all rm-payload rm-standalone rm-all doctor; do
  SB_T66NP="$(new_sandbox)"; T66_RC="$(t66_rc "$SB_T66NP")"
  t75_npblock "$T66_RC" no-parse
  [ "$T66_DOOR" = "setup-all" ] && t66_pageblock >> "$T66_RC"
  cp "$T66_RC" "$TMP/t66np-before"
  expect_false "T66 no-parse (${T66_DOOR}): the planted rc does not parse (the fixture holds)" t66_parses "$T66_RC"
  T66NP_OUT="$(t66_door "$SB_T66NP" "$T66_DOOR" y)"
  expect_same_bytes "T66 no-parse (${T66_DOOR}): bionic's block stays, the rc byte-identical" "$TMP/t66np-before" "$T66_RC"
  expect_contains "T66 no-parse (${T66_DOOR}): the door says the file does not parse, naming the block" "lines 2 to 4 of" "$(report_row "$T66NP_OUT" "does not parse")"
  expect_absent "T66 no-parse (${T66_DOOR}): …and nothing says it was removed" "(the unmarked spelling)" "$T66NP_OUT"
done

# NO zsh ON THE PATH, a .zshrc: bionic's block stays and the door says the shell that
# reads that file is not installed. The PATH is the system's with zsh taken out.
mkdir -p "$TMP/nozsh"
for T66_D in /bin /usr/bin "$(dirname "$(command -v jq)")"; do
  for T66_F in "$T66_D"/*; do
    case "${T66_F##*/}" in zsh|zsh-*) continue ;; esac
    [ -e "$TMP/nozsh/${T66_F##*/}" ] || ln -s "$T66_F" "$TMP/nozsh/${T66_F##*/}" 2>/dev/null
  done
done
T66_SHELL=/bin/zsh; T66_PATH="$TMP/bin:$TMP/nozsh"
expect_false "T66 no-zsh: the PATH holds no zsh (the fixture holds)" env -i PATH="$T66_PATH" /bin/bash -c 'command -v zsh'
expect_true "T66 no-zsh: …and does hold bash (its twin)" env -i PATH="$T66_PATH" /bin/bash -c 'command -v bash'
for T66_DOOR in setup-only setup-all rm-payload rm-standalone rm-all doctor; do
  SB_T66Z="$(new_sandbox)"; t75_npblock "$SB_T66Z/.zshrc" top
  [ "$T66_DOOR" = "setup-all" ] && t66_pageblock >> "$SB_T66Z/.zshrc"
  cp "$SB_T66Z/.zshrc" "$TMP/t66z-before"
  T66Z_OUT="$(t66_door "$SB_T66Z" "$T66_DOOR" y)"
  expect_same_bytes "T66 no-zsh (${T66_DOOR}): bionic's block stays, the rc byte-identical" "$TMP/t66z-before" "$SB_T66Z/.zshrc"
  case "$T66_DOOR" in doctor) T66_NEEDLE="zsh is not installed" ;; *) T66_NEEDLE="zsh, the shell that reads that file, is not installed" ;; esac
  expect_contains "T66 no-zsh (${T66_DOOR}): the door says the shell that reads it is not installed" "$T66_NEEDLE" "$T66Z_OUT"
  expect_contains "T66 no-zsh (${T66_DOOR}): …naming the block by its lines" "lines 2 to 4 of" "$(report_row "$T66Z_OUT" "$T66_NEEDLE")"
done
T66_PATH="$T51_PATH"
# Its twin: the same rc with zsh on the PATH, removed.
SB_T66ZT="$(new_sandbox)"; t75_npblock "$SB_T66ZT/.zshrc" top; printf '%s\n' 'export SECRETTOKEN=1' 'export B=2' > "$TMP/t66zt-expected"
t66_door "$SB_T66ZT" rm-payload y >/dev/null
expect_same_bytes "T66 no-zsh twin: with zsh there, the same block goes" "$TMP/t66zt-expected" "$SB_T66ZT/.zshrc"

# doctor over each shape: one `–` row in its own words, by number, no route to setup.
T66_SHELL=/bin/bash
for T66_SHAPE in if-only heredoc backslash; do
  SB_T66D="$(new_sandbox)"; t66_plant "$(t66_rc "$SB_T66D")" "$TMP/t66d-unused" "$T66_SHAPE" "$T66_ALIAS"
  cp "$(t66_rc "$SB_T66D")" "$TMP/t66d-before"
  T66_DOC="$(t66_door "$SB_T66D" doctor "")"
  T66_DROW="$(report_row "$T66_DOC" "bionic's old line")"
  expect_contains "T66 B1 ${T66_SHAPE} (doctor): a row names bionic's old line" "line 2 of ~/.bashrc" "$T66_DROW"
  expect_contains "T66 B1 ${T66_SHAPE} (doctor): …to edit by hand" "by hand" "$T66_DROW"
  expect_absent "T66 B1 ${T66_SHAPE} (doctor): …with no route to setup" "/bionic:setup" "$T66_DROW"
  expect_absent "T66 B1 ${T66_SHAPE} (doctor): the alias row does not call it present" "present →" "$(report_row "$T66_DOC" "legacy .zshrc alias block")"
  expect_same_bytes "T66 B1 ${T66_SHAPE} (doctor): doctor changes nothing" "$TMP/t66d-before" "$(t66_rc "$SB_T66D")"
done
SB_T66DT="$(new_sandbox)"; t75_npblock "$(t66_rc "$SB_T66DT")" top
expect_contains "T66 B1 block top (doctor): bionic's whole block is present → setup (the twin)" "present →" "$(report_row "$(t66_door "$SB_T66DT" doctor "")" "legacy .zshrc alias block")"

# THE RETIRED ALIAS BLOCK IS ONE UNIT (A-orch-119 (3)): setup's strip and remove's
# marked branch take it out only when, as a unit, it stands as commands of their own
# (markers.sh `markers_block_alone`, the one function at both call sites).
t66_ablock() {  # <file> <expected> <shape>
  case "$3" in
    top)     printf '%s\n' 'export SECRETTOKEN=1' "$ALIAS_START" "$T66_ALIAS" "$ALIAS_END" 'export B=2' > "$1"
             printf '%s\n' 'export SECRETTOKEN=1' 'export B=2' > "$2"; return 0 ;;
    in-if)   printf '%s\n' 'if [ -n "$SECRETTOKEN" ]; then' "$ALIAS_START" "$T66_ALIAS" "$ALIAS_END" 'fi' > "$1" ;;
    heredoc) printf '%s\n' "cat > /dev/null <<'EOF'" "$ALIAS_START" "$T66_ALIAS" "$ALIAS_END" 'EOF' 'export SECRETTOKEN=1' > "$1" ;;
  esac
  if [ "${4:-left}" = "removed" ]; then awk -v a="$ALIAS_START" -v l="$T66_ALIAS" -v e="$ALIAS_END" 'index($0, a) != 1 && $0 != l && index($0, e) != 1' "$1" > "$2"; else cp "$1" "$2"; fi
}
t66_ablock_doors() {  # <shell> <shape> <verdict>
  local door sb rc out L
  T66_SHELL="$1"
  for door in setup-only setup-all rm-payload rm-standalone rm-all; do
    sb="$(new_sandbox)"; rc="$(t66_rc "$sb")"
    t66_ablock "$rc" "$TMP/t66ab-expected" "$2" "$3"
    [ "$door" = "setup-all" ] && t66_pageblock | tee -a "$rc" >> "$TMP/t66ab-expected"
    cp "$rc" "$TMP/t66ab-before"
    L="T66 alias block ${2} (${1##*/}, ${door})"
    out="$(t66_door "$sb" "$door" y)"
    expect_true "${L}: the rc still parses under its own shell" t66_parses "$rc"
    expect_same_bytes "${L}: answered yes, the rc is as the rule says, byte for byte" "$TMP/t66ab-expected" "$rc"
    expect_absent "${L}: the user's text is never printed" "SECRETTOKEN" "$out"
    case "$3" in
      left)
        expect_eq "${L}: the block is named as inside your own code, once" "1" "$(t55_count "$out" "where removing it would change your own code")"
        expect_contains "${L}: …by its lines" "lines 2 to 4 of" "$(report_row "$out" "where removing it would change your own code")"
        case "$door" in setup-only|rm-payload|rm-standalone) expect_absent "${L}: …and nothing is asked" "[y/N]" "$out" ;; esac ;;
      removed)
        expect_absent "${L}: …and nothing is called inside your own code" "where removing it would change your own code" "$out" ;;
    esac
  done
}
t66_ablock_doors /bin/bash in-if left
t66_ablock_doors /bin/bash heredoc removed
t66_ablock_doors /bin/bash top removed
t66_ablock_doors /bin/zsh in-if removed
T66_SHELL=/bin/bash
SB_T66AD="$(new_sandbox)"; t66_ablock "$(t66_rc "$SB_T66AD")" "$TMP/t66ad-unused" in-if
T66AD_OUT="$(t66_door "$SB_T66AD" doctor "")"
expect_contains "T66 alias block in-if (doctor): a row names the block's lines inside your own code" "lines 2 to 4 of ~/.bashrc" "$(report_row "$T66AD_OUT" "in your own code")"
expect_absent "T66 alias block in-if (doctor): the alias row does not call it present" "present →" "$(report_row "$T66AD_OUT" "legacy .zshrc alias block")"
SB_T66ADT="$(new_sandbox)"; t66_ablock "$(t66_rc "$SB_T66ADT")" "$TMP/t66adt-unused" top
expect_contains "T66 alias block top (doctor): a block that stands alone is present → setup (the twin)" "present →" "$(report_row "$(t66_door "$SB_T66ADT" doctor "")" "legacy .zshrc alias block")"

# B2 — REMOVE'S ENVIRONMENT LINE (A-orch-119 (3)). bionic wrote `export
# CLAUDE_CODE_ENABLE_TODO_TOOLS=1` ONLY between its `bionic:env` markers (setup.sh
# 3e00ec84 until ba36f32c), so no bare line is bionic's: a line of that text outside
# the markers is left byte for byte and named by number as outside bionic's markers,
# every other mention as not in a form bionic wrote, and no page offers either. The
# marked block is one unit and obeys B1 as a unit.
t66_env_plant() {  # <file> <expected> <shape>
  case "$3" in
    exact)   printf '%s\n' 'export A=1' "$T66_TODO" 'export B=2' > "$1" ;;
    nofinal) printf 'export A=1\n%s' "$T66_TODO" > "$1" ;;
    crlf)    printf 'export A=1\r\n  %s\r\nexport B=2\r\n' "$T66_TODO" > "$1" ;;
    if-only) printf '%s\n' 'if [ -n "$SECRETTOKEN" ]; then' "$T66_TODO" 'fi' > "$1" ;;
    shared)  printf '%s\n' 'export A=1' "${T66_TODO}; export SECRETTOKEN=abc" > "$1" ;;
    ten)     printf '%s\n' 'export A=1' 'export CLAUDE_CODE_ENABLE_TODO_TOOLS=10' 'export SECRETTOKEN=1' > "$1" ;;
    suffix)  printf '%s\n' 'export A=1' 'export CLAUDE_CODE_ENABLE_TODO_TOOLS_X=1' 'export SECRETTOKEN=1' > "$1" ;;
    comment) printf '%s\n' 'export A=1' "# ${T66_TODO}  SECRETTOKEN" > "$1" ;;
    block-top)     printf '%s\n' 'export A=1' "$T66_ENV_START" "$T66_TODO" "$T66_ENV_END" 'export SECRETTOKEN=1' > "$1"
                   printf '%s\n' 'export A=1' 'export SECRETTOKEN=1' > "$2"; return 0 ;;
    block-two-if)  printf '%s\n' 'if [ -n "$SECRETTOKEN" ]; then' '  export A=1' "$T66_ENV_START" "$T66_TODO" "$T66_ENV_END" 'fi' > "$1"
                   printf '%s\n' 'if [ -n "$SECRETTOKEN" ]; then' '  export A=1' 'fi' > "$2"; return 0 ;;
    block-if)      printf '%s\n' 'if [ -n "$SECRETTOKEN" ]; then' "$T66_ENV_START" "$T66_TODO" "$T66_ENV_END" 'fi' > "$1" ;;
    block-heredoc) printf '%s\n' "cat > /dev/null <<'EOF'" "$T66_ENV_START" "$T66_TODO" "$T66_ENV_END" 'EOF' 'export SECRETTOKEN=1' > "$1"
                   printf '%s\n' "cat > /dev/null <<'EOF'" 'EOF' 'export SECRETTOKEN=1' > "$2"; return 0 ;;
    block-andand)  printf '%s\n' 'test -n "$SECRETTOKEN" &&' "$T66_ENV_START" "$T66_TODO" "$T66_ENV_END" 'export A=1' > "$1"
                   printf '%s\n' 'test -n "$SECRETTOKEN" &&' 'export A=1' > "$2"; return 0 ;;
  esac
  cp "$1" "$2"
}
T66_ENV_START="$(const_from "$REMOVE_SH" RM_ENV_START)"; T66_ENV_END="$(const_from "$REMOVE_SH" RM_ENV_END)"
expect_nonempty "T66 B2: remove.sh carries the env start marker" "$T66_ENV_START"
expect_eq "T66 B2: remove.sh's env start marker is detect.sh's" "$(const_from "$DETECT_SH" BIONIC_ENV_START)" "$T66_ENV_START"
expect_eq "T66 B2: remove.sh's env end marker is detect.sh's" "$(const_from "$DETECT_SH" BIONIC_ENV_END)" "$T66_ENV_END"
T66_SHELL=/bin/bash
for T66_SHAPE in exact nofinal crlf if-only shared ten suffix comment block-top block-two-if block-if block-heredoc block-andand; do
  for T66_DOOR in rm-payload rm-standalone rm-all; do
    SB_T66V="$(new_sandbox)"; T66_RC="$(t66_rc "$SB_T66V")"
    t66_env_plant "$T66_RC" "$TMP/t66v-expected" "$T66_SHAPE"
    cp "$T66_RC" "$TMP/t66v-before"; T66_INODE="$(t51_inode "$T66_RC")"
    T66V_OUT="$(t66_door "$SB_T66V" "$T66_DOOR" y environment)"
    T66_L="T66 B2 env ${T66_SHAPE} (${T66_DOOR})"
    expect_contains "${T66_L}: the run reached the machine" "bionic" "$T66V_OUT"
    expect_same_bytes "${T66_L}: answered yes, the rc is as the rule says, byte for byte" "$TMP/t66v-expected" "$T66_RC"
    expect_absent "${T66_L}: the user's text is never printed" "SECRETTOKEN" "$T66V_OUT"
    case "$T66_SHAPE" in
      block-top|block-two-if|block-heredoc|block-andand)
        # T75 (A-orch-162): bionic's whole block goes wherever it stands, the rc's own
        # shell's parse its only veto (the known limit, in the record).
        expect_contains "${T66_L}: the block goes as a unit" "retired environment block in" "$T66V_OUT" ;;
      block-*)
        expect_eq "${T66_L}: …and keeps its inode" "$T66_INODE" "$(t51_inode "$T66_RC")"
        expect_contains "${T66_L}: the block is named as inside your own code, by its lines" "lines 2 to 4 of" \
          "$(report_row "$T66V_OUT" "bionic's retired environment block, where removing it would change your own code")"
        case "$T66_DOOR" in rm-payload|rm-standalone) expect_absent "${T66_L}: …and nothing is asked" "[y/N]" "$T66V_OUT" ;; esac ;;
      exact|nofinal|crlf|if-only)
        expect_eq "${T66_L}: …and keeps its inode" "$T66_INODE" "$(t51_inode "$T66_RC")"
        expect_eq "${T66_L}: the line is named as outside bionic's markers, once" "1" "$(t55_count "$T66V_OUT" "outside bionic's markers")"
        expect_contains "${T66_L}: …by its number" "line 2 of" "$(report_row "$T66V_OUT" "outside bionic's markers")"
        case "$T66_DOOR" in rm-payload|rm-standalone) expect_absent "${T66_L}: …and nothing is asked" "[y/N]" "$T66V_OUT" ;; esac ;;
      *)
        expect_eq "${T66_L}: …and keeps its inode" "$T66_INODE" "$(t51_inode "$T66_RC")"
        expect_eq "${T66_L}: the line is named as not in a form bionic wrote, once" "1" "$(t55_count "$T66V_OUT" "not in a form bionic wrote")"
        expect_contains "${T66_L}: …by its number" "line 2 of" "$(report_row "$T66V_OUT" "not in a form bionic wrote")" ;;
    esac
  done
done
# A READ-ONLY RC is refused in the marked step's words, nothing written, the inode kept.
T66_SHELL=/bin/bash
for T66_DOOR in rm-payload rm-standalone; do
  SB_T66VR="$(new_sandbox)"; T66_RC="$(t66_rc "$SB_T66VR")"
  t66_env_plant "$T66_RC" "$TMP/t66vr-unused" block-top
  cp "$T66_RC" "$TMP/t66vr-before"; chmod 444 "$T66_RC"; T66_INODE="$(t51_inode "$T66_RC")"
  T66VR_OUT="$(t66_door "$SB_T66VR" "$T66_DOOR" y environment)"
  chmod 644 "$T66_RC"
  expect_same_bytes "T66 B2 env read-only (${T66_DOOR}): nothing written" "$TMP/t66vr-before" "$T66_RC"
  expect_eq "T66 B2 env read-only (${T66_DOOR}): …the same inode" "$T66_INODE" "$(t51_inode "$T66_RC")"
  expect_contains "T66 B2 env read-only (${T66_DOOR}): the marked step's words" \
    "is read-only, and bionic leaves a file you made read-only alone — the environment block is still there" "$T66VR_OUT"
done
# Half-uninstalled counts the export as bionic's footprint only between the markers.
t66_todo_fact() {  # <sandbox> — detect_env_todo_tools' line for that home
  t66_env "$1" bash -c '. "$1" >/dev/null 2>&1; detect_env_todo_tools' _ "$DETECT_SH"
}
SB_T66F="$(new_sandbox)"; t66_env_plant "$(t66_rc "$SB_T66F")" "$TMP/t66f-unused" block-top
expect_eq "T66 B2 footprint: the block's export is bionic's (the positive)" "env:todo-tools present=yes" "$(t66_todo_fact "$SB_T66F")"
t66_env_plant "$(t66_rc "$SB_T66F")" "$TMP/t66f-unused" exact
expect_eq "T66 B2 footprint: the same text outside the markers is not" "env:todo-tools present=no" "$(t66_todo_fact "$SB_T66F")"

# B3 — THE TEMPLATE'S PATH IS A WHITELIST. The flag in these lines is data: nothing
# here runs with it.
t66_tpl() {  # <shape>
  case "$1" in
    pipe)   printf '%s' "alias claude='/usr/bin/tee|/opt/homebrew/bin/claude --dangerously-skip-permissions'" ;;
    amp)    printf '%s' "alias claude='/opt/a&b/claude --dangerously-skip-permissions'" ;;
    lt)     printf '%s' "alias claude='/opt/a<b/claude --dangerously-skip-permissions'" ;;
    gt)     printf '%s' "alias claude='/opt/a>b/claude --dangerously-skip-permissions'" ;;
    lparen) printf '%s' "alias claude='/opt/a(b/claude --dangerously-skip-permissions'" ;;
    rparen) printf '%s' "alias claude='/opt/a)b/claude --dangerously-skip-permissions'" ;;
    brew)   printf '%s' "alias claude='/opt/homebrew/bin/claude --dangerously-skip-permissions'" ;;
    utf8)   printf '%s' "alias claude='/Users/josé/.local/bin/claude --dangerously-skip-permissions'" ;;
    punct)  printf '%s' "alias claude='/a.b/c_d-e+f@g%h,i:j=k~l/claude --dangerously-skip-permissions'" ;;
  esac
}
T66_SHELL=/bin/zsh
for T66_SHAPE in pipe amp lt gt lparen rparen brew utf8 punct; do
  for T66_DOOR in setup-only rm-payload rm-standalone; do
    SB_T66B="$(new_sandbox)"
    printf '%s\n' 'export A=1' "$(t66_tpl "$T66_SHAPE")" 'export B=2' > "$SB_T66B/.zshrc"
    cp "$SB_T66B/.zshrc" "$TMP/t66b-before"; printf '%s\n' 'export A=1' 'export B=2' > "$TMP/t66b-removed"
    T66B_OUT="$(t66_door "$SB_T66B" "$T66_DOOR" y)"
    T66_L="T66 B3 template ${T66_SHAPE} (${T66_DOOR})"
    case "$T66_SHAPE" in
      brew|utf8|punct)
        expect_same_bytes "${T66_L}: bionic's form, left byte for byte (T75: never taken out)" "$TMP/t66b-before" "$SB_T66B/.zshrc"
        expect_contains "${T66_L}: …named as bionic's line, by its number" "line 2 of" "$(report_row "$T66B_OUT" "outside bionic's markers")"
        expect_absent "${T66_L}: …and nothing asked" "[y/N]" "$T66B_OUT" ;;
      *)
        expect_same_bytes "${T66_L}: not a form bionic wrote, left byte for byte" "$TMP/t66b-before" "$SB_T66B/.zshrc"
        expect_contains "${T66_L}: …named by its number" "line 2 of" "$(report_row "$T66B_OUT" "not in a form bionic wrote")"
        expect_absent "${T66_L}: …and nothing asked" "[y/N]" "$T66B_OUT" ;;
    esac
  done
done
# The predicate answers the same under every locale (review pass 40 N6).
for T66_LOC in C en_US.UTF-8; do
  for T66_SHAPE in utf8 punct pipe; do
    T66_ANS="$(LC_ALL="$T66_LOC" bash -c '. "$1" >/dev/null 2>&1; bionic_legacy_alias_ours "$2" && echo ours || echo theirs' _ "$DETECT_SH" "$(t66_tpl "$T66_SHAPE")")"
    case "$T66_SHAPE" in pipe) T66_WANT=theirs ;; *) T66_WANT=ours ;; esac
    expect_eq "T66 B3 predicate ${T66_SHAPE} under LC_ALL=${T66_LOC}" "$T66_WANT" "$T66_ANS"
  done
done

# S1, S2 — THE RC CHANGED BETWEEN THE QUESTION AND THE WRITE. The question is answered
# through a FIFO only after the rc is edited (a line inserted above), so the write meets
# a file whose numbered line moved: nothing written, the user's newer file kept, the
# reason printed before the path.
t66_race() {  # <sandbox> <door> <item> [above|wrap] — the run's output; the rc is edited under the question
  local sb="$1" fifo="$1/.answer" out="$1/.out" i=0 pid rc
  rc="$(t66_rc "$sb")"
  mkfifo "$fifo"
  case "$2" in
    setup-only)    t66_env "$sb" bash "$SETUP_SH" --only "$3" < "$fifo" > "$out" 2>&1 & ;;
    rm-payload)    t66_env "$sb" bash "$REMOVE_SH" --only "$3" < "$fifo" > "$out" 2>&1 & ;;
    rm-standalone) t66_env "$sb" bash "$TMP/standalone/remove.sh" --only "$3" < "$fifo" > "$out" 2>&1 & ;;
  esac
  pid=$!
  exec 7> "$fifo"
  while [ "$i" -lt 600 ]; do
    case "$(cat "$out" 2>/dev/null)" in *"[y/N]"*) break ;; esac
    sleep 0.1; i=$((i + 1))
  done
  case "${4:-above}" in
    above) { printf '%s\n' 'export NEW=1'; cat "$rc"; } > "$rc.edit" ;;
    wrap)  { printf '%s\n' 'if [ -n "$NEW" ]; then'; cat "$rc"; printf '%s\n' 'fi'; } > "$rc.edit" ;;
  esac
  cat "$rc.edit" > "$rc" && rm -f "$rc.edit"
  cp "$rc" "$sb/.mutated"
  printf 'y\n' >&7; exec 7>&-
  wait "$pid"
  cat "$out"
}
T66_SHELL=/bin/bash
for T66_DOOR in setup-only rm-payload rm-standalone; do
  SB_T66RB="$(new_sandbox)"; printf '%s\n' "$ALIAS_START" "$T66_ALIAS" "$ALIAS_END" > "$(t66_rc "$SB_T66RB")"
  T66RB_OUT="$(t66_race "$SB_T66RB" "$T66_DOOR" legacy-alias wrap)"
  expect_contains "T66 S1 race alias block (${T66_DOOR}): the question was asked (the positive)" "[y/N]" "$T66RB_OUT"
  expect_same_bytes "T66 S1 race alias block (${T66_DOOR}): nothing written, the user's newer file kept" "$SB_T66RB/.mutated" "$(t66_rc "$SB_T66RB")"
  case "$T66_DOOR" in
    setup-only) expect_contains "T66 S1 race alias block (setup): the reason first" "changed while setup ran" "$(report_row "$T66RB_OUT" "legacy alias block  ")" ;;
    *)          expect_contains "T66 S1 race alias block (${T66_DOOR}): the reason first" "⚠ changed while remove ran" "$T66RB_OUT" ;;
  esac
done
for T66_DOOR in rm-payload rm-standalone; do
  SB_T66RV="$(new_sandbox)"; printf '%s\n' "$T66_ENV_START" "$T66_TODO" "$T66_ENV_END" > "$(t66_rc "$SB_T66RV")"
  T66RV_OUT="$(t66_race "$SB_T66RV" "$T66_DOOR" environment wrap)"
  expect_contains "T66 S1 race env (${T66_DOOR}): the question was asked (the positive)" "Remove bionic's environment settings?" "$T66RV_OUT"
  expect_same_bytes "T66 S1 race env (${T66_DOOR}): nothing written, the user's newer file kept" "$SB_T66RV/.mutated" "$(t66_rc "$SB_T66RV")"
  expect_contains "T66 S1 race env (${T66_DOOR}): the reason comes first" "⚠ changed while remove ran" "$T66RV_OUT"
done

# S3 — A TEMP FILE THIS RUN DID NOT STAGE IS NOT REMOVE'S TO DELETE. A read-only rc and
# the user's own file at `<rc>.bionic.tmp`: refused, and the user's file kept, through
# the marked branch (T75: no bare line is ever written). The twin: setup leaves it too.
T66_SHELL=/bin/zsh
for T66_KIND in marked; do
  for T66_DOOR in rm-payload rm-standalone setup-only; do
    SB_T66S="$(new_sandbox)"
    case "$T66_KIND" in
      unmarked) t66_plant "$SB_T66S/.zshrc" "$TMP/t66s-unused" top "$T66_ALIAS" ;;
      marked)   printf '%s\n' 'export A=1' "$ALIAS_START" "$T66_ALIAS" "$ALIAS_END" > "$SB_T66S/.zshrc" ;;
    esac
    printf 'USER FILE\n' > "$SB_T66S/.zshrc.bionic.tmp"; cp "$SB_T66S/.zshrc.bionic.tmp" "$TMP/t66s-tmp"
    chmod 444 "$SB_T66S/.zshrc"
    T66S_OUT="$(t66_door "$SB_T66S" "$T66_DOOR" y)"
    chmod 644 "$SB_T66S/.zshrc"
    expect_contains "T66 S3 ${T66_KIND} (${T66_DOOR}): the read-only rc is refused (the positive)" "read-only" "$T66S_OUT"
    expect_same_bytes "T66 S3 ${T66_KIND} (${T66_DOOR}): the user's own .bionic.tmp is left as it was" "$TMP/t66s-tmp" "$SB_T66S/.zshrc.bionic.tmp"
  done
done

# S5 — A READ-ONLY RC IS NOT OFFERED. setup's and remove's --all pages leave the
# block off and say the rc is read-only; doctor's row says so and sends no one to setup
# (T75: a bare line is never offered, read-only or not). The twin: the writable rc is
# offered.
T66_SHELL=/bin/zsh
for T66_KIND in marked; do
  for T66_DOOR in setup-all rm-all doctor; do
    SB_T66P="$(new_sandbox)"
    case "$T66_KIND" in
      unmarked) t66_plant "$SB_T66P/.zshrc" "$TMP/t66p-unused" top "$T66_ALIAS" ;;
      marked)   printf '%s\n' 'export A=1' "$ALIAS_START" "$T66_ALIAS" "$ALIAS_END" > "$SB_T66P/.zshrc" ;;
    esac
    [ "$T66_DOOR" = "setup-all" ] && t66_pageblock >> "$SB_T66P/.zshrc"
    cp "$SB_T66P/.zshrc" "$TMP/t66p-before"; chmod 444 "$SB_T66P/.zshrc"
    T66P_OUT="$(t66_door "$SB_T66P" "$T66_DOOR" n)"
    chmod 644 "$SB_T66P/.zshrc"
    T66_L="T66 S5 ${T66_KIND} read-only (${T66_DOOR})"
    expect_same_bytes "${T66_L}: nothing written" "$TMP/t66p-before" "$SB_T66P/.zshrc"
    case "$T66_DOOR" in
      doctor)
        expect_absent "${T66_L}: the alias row does not send anyone to setup" "present →" "$(report_row "$T66P_OUT" "legacy .zshrc alias block")"
        expect_contains "${T66_L}: …a row says the rc is read-only" "read-only" "$(report_row "$T66P_OUT" "legacy .zshrc alias block")" ;;
      *)
        expect_absent "${T66_L}: the page does not offer the line" "retired alias line bionic wrote" "$T66P_OUT"
        expect_absent "${T66_L}: …nor the block" "remove the retired shell alias block" "$T66P_OUT"
        expect_contains "${T66_L}: …and says the rc is read-only" "read-only" "$T66P_OUT" ;;
    esac
  done
done
# The twin for the marked block on setup's page: writable, it is offered.
SB_T66PT="$(new_sandbox)"
printf '%s\n' 'export A=1' "$ALIAS_START" "$T66_ALIAS" "$ALIAS_END" > "$SB_T66PT/.zshrc"; t66_pageblock >> "$SB_T66PT/.zshrc"
expect_contains "T66 S5 marked writable (setup-all): the page offers the block (the twin)" "remove the retired shell alias block" "$(t66_door "$SB_T66PT" setup-all n)"

# S4 — A LATE DEFINITION. A second definition appended to remove.sh turns every pin of
# that name red. (T75: `_rm_drop_lines` and `markers_drop_lines` are gone with the
# bare-line removal they served.)
t66_rm_names() {  # remove.sh's helper names, read as the library's
  sed -e 's/_rm_drop_lines/markers_drop_lines/g' -e 's/_rm_regular/markers_regular/g' \
      -e 's/_rm_stage_tmp/_markers_stage_tmp/g' -e 's/_rm_publish_tmp/_markers_publish_tmp/g' \
      -e 's/_rm_block_alone/markers_block_alone/g'
}
T66_A="$(fn_text "${REPO}/payload/scripts/lib/markers.sh" markers_block_alone)"
expect_nonempty "T66 copies: markers_block_alone reads out of markers.sh" "$T66_A"
expect_eq "T66 copies: remove.sh's _rm_block_alone is markers_block_alone, body for body" "$T66_A" "$(fn_text "$REMOVE_SH" _rm_block_alone | t66_rm_names)"
cp "$REMOVE_SH" "$TMP/t66-late.sh"
printf '%s\n' 'bionic_legacy_alias_ours() {  # <line> — rc 0 when bionic wrote it' '  return 0' '}' >> "$TMP/t66-late.sh"
expect_true "T66 S4: the late-definition mutant still parses" bash -n "$TMP/t66-late.sh"
expect_ne "T66 S4: …and the pin on bionic_legacy_alias_ours goes red on it" \
  "$(fn_text "$DETECT_SH" bionic_legacy_alias_ours)" "$(fn_text "$TMP/t66-late.sh" bionic_legacy_alias_ours)"

# THE NEW COPIES remove.sh carries for its standalone door, each pinned to its one
# library, and the environment line's loose pattern.
for T66_FN in bionic_rc_line_bare bionic_todo_export_ours bionic_todo_export_lines bionic_rc_left_reason bionic_rc_candidates bionic_rc_lines bionic_rc_staged bionic_rc_block_alone bionic_rc_block_staged bionic_rc_try bionic_rc_parses bionic_block_body bionic_rc_shell; do
  case "$T66_FN" in
    bionic_rc_candidates|bionic_rc_lines|bionic_rc_staged|bionic_rc_block_alone|bionic_rc_block_staged|bionic_rc_try|bionic_rc_parses) T66_LIB="${REPO}/payload/scripts/lib/markers.sh" ;;
    bionic_rc_shell) T66_LIB="${REPO}/payload/scripts/lib/shell.sh" ;;
    *) T66_LIB="$DETECT_SH" ;;
  esac
  T66_A="$(fn_text "$T66_LIB" "$T66_FN")"
  expect_nonempty "T66 copies: ${T66_FN} reads out of its library" "$T66_A"
  expect_eq "T66 copies: remove.sh's ${T66_FN} is the library's, line for line" "$T66_A" "$(fn_text "$REMOVE_SH" "$T66_FN")"
done
T66_PAT="$(const_from "$DETECT_SH" BIONIC_TODO_EXPORT_PATTERN)" || T66_PAT=""
expect_nonempty "T66 copies: detect.sh carries the environment line's loose pattern" "$T66_PAT"
expect_eq "T66 copies: remove.sh's is detect.sh's" "$T66_PAT" "$(const_from "$REMOVE_SH" BIONIC_TODO_EXPORT_PATTERN)"

# N1 — DECIDING A LINE IS LINEAR IN ITS LENGTH UNDER EVERY LOCALE. A 200,000-character
# line, in and out of bionic's form, through both predicates and the scan. The bound is
# the row's own measure: 0 s on this machine where T55's quadratic trims took 8–9 s.
T66_LONG="$(head -c 200000 /dev/zero | tr '\0' 'a')"
printf '%s\n' "alias claude='/${T66_LONG}/claude --dangerously-skip-permissions'" "export X=${T66_LONG}" \
  "${T66_TODO}$(printf '%*s' 2000 '')" > "$TMP/t66-long.rc"
for T66_LOC in en_US.UTF-8 C; do
  T66_T0="$(date +%s)"
  T66_SCAN="$(LC_ALL="$T66_LOC" SHELL=/bin/bash HOME="$TMP" bash -c '. "$1" >/dev/null 2>&1; bionic_legacy_alias_lines "$2"; bionic_todo_export_lines "$2"' _ "$DETECT_SH" "$TMP/t66-long.rc")"
  T66_T1="$(date +%s)"
  expect_contains "T66 N1 (LC_ALL=${T66_LOC}): the long line in bionic's form is bionic's" "bound=1 " "$T66_SCAN"
  expect_contains "T66 N1 (LC_ALL=${T66_LOC}): …and the export with trailing blanks is too" "cand=3 " "$T66_SCAN"
  T66_SECS=$((T66_T1 - T66_T0))
  if [ "$T66_SECS" -le 4 ]; then ok "T66 N1 (LC_ALL=${T66_LOC}): both scans over the 200,000-character lines inside 4 s"
  else no "T66 N1 (LC_ALL=${T66_LOC}): both scans over the 200,000-character lines inside 4 s" "took ${T66_SECS} s"; fi
done

# ---------------------------------------------------------------------------
section "wave-27 T75: the markers are the whole rule, proven by bytes"
# ---------------------------------------------------------------------------
#
# Review pass 54 on T66 found four blockers, each a change to what the user's own shell
# does, after four rows (T7, T51, T55, T66) that each said from the TEXT around bionic's
# bare alias line when taking it out was safe. A-orch-162 (Chris's ruling) ends that: the
# markers are the whole rule. No door takes a line outside a marker pair out of an rc;
# bionic's own bare line is named by number for the user's hand. A marked block goes as
# one unit only when its body is, byte for byte, the one bionic wrote, and only when the
# rc's own shell says (`-n` on a staged copy) the rc parsed before and still parses
# without it. THE GATE IS BYTES: the generator (tests/fixtures/rc-gen.pl) writes rc files
# out of this suite's own lines, with bionic's line or block in every position of review
# pass 54's 422 shapes, and writes beside each what every door must leave; every writing
# door is run on each in a throwaway home and the rc it leaves must be exactly that file.
# No rc is executed by the gate row (the one-time execution measurement is the record's).

T75_GEN="${REPO}/tests/fixtures/rc-gen.pl"
T75_CASES="$TMP/t75-cases"
perl "$T75_GEN" 75 "$T75_CASES"
T75_SAMPLE="${T75_SAMPLE:-6}"
# The named shapes, always in the sample: B1 to B4 and S3 of review pass 54, and the
# brief's worked answers.
T75_CORE=" a-andcomment-only a-pipecomment-only a-zshfn-only a-zshforshort-only a-hdcmdsub-only ab-hdcmdsub-only \
eb-hdcmdsub-only ab-andcomment-only a-top-sev a-if-sev x-two-if a-case-only k-ab-top k-ab-userline k-ab-useronly \
k-eb-ten k-eb-userline k-ab-nofinal k-eb-nofinal x-nofinal a-banglast-only a-bangtrue-only a-bang-only a-bslash-only \
a-bsthencomment-only a-bangthenours-only ab-banglast-only ab-if-only ab-if-sev ab-top-only eb-top-sev k-both \
k-both-nested k-ab-and-bare x-crlf x-three "

t75_exec() {  # <home> <shell> <rc> — the state the rc leaves when the rc's own shell runs it (S2's positive only)
  local h="$1"
  case "$h" in "$TMP"/home-*) ;; *) echo "T75 GUARD: home '$h' is not under this suite's throwaway root" >&2; exit 1 ;; esac
  rm -f "$h/log"
  case "$2" in
    zsh) env -i HOME="$h" PATH=/usr/bin:/bin /bin/zsh -f -c '. "$1" </dev/null >/dev/null 2>&1; env' t75 "$3" ;;
    *)   env -i HOME="$h" PATH=/usr/bin:/bin /bin/bash --norc --noprofile -c '. "$1" </dev/null >/dev/null 2>&1; env' t75 "$3" ;;
  esac 2>/dev/null | LC_ALL=C grep -a '^V[0-9]*=' | LC_ALL=C sort
  printf 'log:'; cat "$h/log" 2>/dev/null; rm -f "$h/log"
}
# The rc the door left is the expected file byte for byte; for setup --all, the
# claude() block it appends (bionic's other item) is set aside first, and with it the
# one newline it adds above that block where the rc ended without one. `ok` or what moved.
t75_same() {  # <expected> <after> <setup-all?>
  perl -e '
    my ($ef, $af, $all, $rs, $re) = @ARGV;
    local $/; open my $e, "<:raw", $ef or die; my $E = <$e>; open my $a, "<:raw", $af or die; my $A = <$a>;
    if ($all eq "yes") { my $i = index($A, "$rs\n");
      if ($i >= 0) { my $j = index($A, "$re\n", $i); $j = $j < 0 ? length($A) : $j + length("$re\n");
        substr($A, $i, $j - $i) = ""; $A =~ s/\n\z// if $E !~ /\n\z/ && $A eq "$E\n"; } }
    if ($A eq $E) { print "ok\n"; exit 0; }
    my $n = 0; $n++ while $n < length($A) && $n < length($E) && substr($A, $n, 1) eq substr($E, $n, 1);
    my $line = 1 + (substr($E, 0, $n) =~ tr/\n//);
    printf "the rc differs from what the rule leaves at byte %d (line %d): %d bytes left, %d expected\n", $n, $line, length($A), length($E);' \
    "$1" "$2" "$3" "$RC_START_LIT" "$RC_END_LIT"
}
t75_doors() {  # <family> — `<door> <item> <kind>` for each writing door that family goes through
  case "$1" in
    alias) printf '%s\n' "setup-only legacy-alias setup" "setup-all legacy-alias setup" "rm-payload legacy-alias rmalias" \
             "rm-standalone legacy-alias rmalias" "rm-all legacy-alias rmall" ;;
    env)   printf '%s\n' "rm-payload environment rmenv" "rm-standalone environment rmenv" "rm-all environment rmall" ;;
    both)  printf '%s\n' "setup-only legacy-alias setup" "setup-all legacy-alias setup" "rm-payload legacy-alias rmalias" \
             "rm-payload environment rmenv" "rm-standalone legacy-alias rmalias" "rm-all legacy-alias rmall" ;;
  esac
}

bionic_line_numbers_words_t75() { case "$1" in *,*) printf 'lines %s\n' "${1//,/, }" ;; *) printf 'line %s\n' "$1" ;; esac; }
T75_T0="$(date +%s)"; T75_RCS=0; T75_RUNS=0; T75_BAD=0; T75_N=0
: > "$TMP/t75-sample"
while read -r T75_ID T75_FAM T75_SH T75_BARE T75_BARE_RM; do
  T75_N=$((T75_N + 1))
  case "$T75_CORE" in *" $T75_ID "*) ;; *) [ "$T75_SAMPLE" = "all" ] || [ "$T75_N" -le "$T75_SAMPLE" ] || continue ;; esac
  printf '%s %s %s %s %s\n' "$T75_ID" "$T75_FAM" "$T75_SH" "$T75_BARE" "$T75_BARE_RM" >> "$TMP/t75-sample"
done < "$T75_CASES/index"
while read -r T75_ID T75_FAM T75_SH T75_BARE_SETUP T75_BARE_RM; do
  T75_RCS=$((T75_RCS + 1))
  T66_SHELL="/bin/$T75_SH"
  while read -r T75_DOOR T75_ITEM T75_KIND; do
    T75_RUNS=$((T75_RUNS + 1))
    T75_SB="$(new_sandbox)"; T75_RC="$(t66_rc "$T75_SB")"
    case "$T75_SB" in "$TMP"/home-*) ;; *) echo "T75 GUARD: HOME '$T75_SB' is not under the throwaway root" >&2; exit 1 ;; esac
    cp "$T75_CASES/$T75_ID.rc" "$T75_RC"
    T75_OUT="$(t66_door "$T75_SB" "$T75_DOOR" y "$T75_ITEM")"
    T75_L="T75 bytes ${T75_ID} (${T75_SH}, ${T75_DOOR} ${T75_ITEM})"
    T75_WHY="$(t75_same "$T75_CASES/$T75_ID.$T75_SH.$T75_KIND" "$T75_RC" "$( [ "$T75_DOOR" = setup-all ] && echo yes || echo no )")"
    [ "$T75_WHY" = "ok" ] && T75_WHY=""
    case "$T75_KIND" in setup) T75_BARE="$T75_BARE_SETUP" ;; *) T75_BARE="$T75_BARE_RM" ;; esac
    if [ -z "$T75_WHY" ] && [ "$T75_BARE" != "-" ] && [ "$T75_ITEM" = "legacy-alias" ]; then
      case "$T75_OUT" in *"$(bionic_line_numbers_words_t75 "$T75_BARE") of "*) ;;
        *) T75_WHY="bionic's bare line(s) ${T75_BARE} not named by number" ;; esac
    fi
    if [ -z "$T75_WHY" ]; then ok "$T75_L"; else no "$T75_L" "$T75_WHY"; T75_BAD=$((T75_BAD + 1)); fi
    rm -rf "$T75_SB"
  done < <(t75_doors "$T75_FAM")
done < "$TMP/t75-sample"
T75_SECS=$(( $(date +%s) - T75_T0 ))
echo "T75 bytes: $(wc -l < "$T75_CASES/index" | tr -d ' ') rc files generated, ${T75_RCS} driven (sample ${T75_SAMPLE}, seed 75, and the named shapes), ${T75_RUNS} door runs, ${T75_BAD} red, ${T75_SECS} s"
# The positives beside the counts: the gate ran, and its expectation moves.
expect_true "T75 bytes: at least 400 rc files are generated" test "$(wc -l < "$T75_CASES/index")" -ge 400
expect_true "T75 bytes: the drive ran doors" test "$T75_RUNS" -gt 0
expect_diff_bytes "T75 bytes: the rule takes an intact block out (k-ab-top's expected file is not the rc)" \
  "$T75_CASES/k-ab-top.rc" "$T75_CASES/k-ab-top.bash.setup"
expect_same_bytes "T75 bytes: …and leaves a bare line (a-top-sev's expected file is the rc)" \
  "$T75_CASES/a-top-sev.rc" "$T75_CASES/a-top-sev.bash.setup"

# B3 — A BLOCK IS BIONIC'S ONLY WHEN ITS BODY IS. The user's line between the alias
# markers, the env block with its value changed, a block holding only the user's line:
# left whole on every door, named by its lines as changed since bionic wrote it, never
# asked about, never on a page. The twin is k-ab-top in the oracle above (goes).
t75_b3_plant() {  # <file> <shape>
  case "$2" in
    userline) printf '%s\n' 'export A=1' "$ALIAS_START" "$T66_ALIAS" 'export SECRETTOKEN=x' "$ALIAS_END" 'export B=2' > "$1" ;;
    useronly) printf '%s\n' 'export A=1' "$ALIAS_START" 'export SECRETTOKEN=x' "$ALIAS_END" 'export B=2' > "$1" ;;
    envten)   printf '%s\n' 'export A=1' "$ENVB_START" 'export CLAUDE_CODE_ENABLE_TODO_TOOLS=10' "$ENVB_END" 'export SECRETTOKEN=1' > "$1" ;;
  esac
}
for T75_SHAPE in userline useronly envten; do
  case "$T75_SHAPE" in envten) T75_DL="rm-payload:environment rm-standalone:environment rm-all:environment" ;;
    *) T75_DL="setup-only:legacy-alias setup-all:legacy-alias rm-payload:legacy-alias rm-standalone:legacy-alias rm-all:legacy-alias" ;; esac
  for T75_SH in bash zsh; do
    T66_SHELL="/bin/$T75_SH"
    for T75_D in $T75_DL; do
      T75_SB="$(new_sandbox)"; T75_RC="$(t66_rc "$T75_SB")"
      t75_b3_plant "$T75_RC" "$T75_SHAPE"
      [ "${T75_D%%:*}" = "setup-all" ] && t66_pageblock >> "$T75_RC"
      cp "$T75_RC" "$TMP/t75b3-before"
      T75_OUT="$(t66_door "$T75_SB" "${T75_D%%:*}" y "${T75_D#*:}")"
      T75_L="T75 B3 ${T75_SHAPE} (${T75_SH}, ${T75_D%%:*})"
      expect_contains "${T75_L}: the run reached the machine" "bionic" "$T75_OUT"
      expect_same_bytes "${T75_L}: answered yes, the block is left whole, the rc byte-identical" "$TMP/t75b3-before" "$T75_RC"
      case "$T75_SHAPE" in userline) T75_LINES="lines 2 to 5 of" ;; *) T75_LINES="lines 2 to 4 of" ;; esac
      expect_contains "${T75_L}: …named by its lines as changed since bionic wrote it" "$T75_LINES" "$(report_row "$T75_OUT" "changed since bionic wrote it")"
      expect_absent "${T75_L}: …the user's text is never printed" "SECRETTOKEN" "$T75_OUT"
      case "${T75_D%%:*}" in
        setup-all) expect_absent "${T75_L}: …and the page does not offer it" "remove the retired shell alias block" "$T75_OUT" ;;
        rm-all) expect_absent "${T75_L}: …and the page does not offer it" "remove the retired shell alias block" "$T75_OUT" ;;
        *) expect_absent "${T75_L}: …and nothing is asked" "[y/N]" "$T75_OUT" ;;
      esac
    done
  done
done
T66_SHELL=/bin/bash
SB_T75DB="$(new_sandbox)"; t75_b3_plant "$(t66_rc "$SB_T75DB")" userline
T75_DOC="$(t66_door "$SB_T75DB" doctor "")"
expect_contains "T75 B3 userline (doctor): a row names the block's lines, changed since bionic wrote it" "lines 2 to 5 of ~/.bashrc" "$(report_row "$T75_DOC" "changed since written")"
expect_absent "T75 B3 userline (doctor): …and the alias row does not call it present" "present →" "$(report_row "$T75_DOC" "legacy .zshrc alias block")"
expect_eq "T75 B3: detect.sh lists the alias block's body" "alias claude='claude --dangerously-skip-permissions'" \
  "$(SHELL=/bin/bash HOME="$TMP" bash -c '. "$1" >/dev/null 2>&1; bionic_block_body "$BIONIC_ALIAS_START"' _ "$DETECT_SH")"
expect_eq "T75 B3: …and nothing for any other marker" "" \
  "$(SHELL=/bin/bash HOME="$TMP" bash -c '. "$1" >/dev/null 2>&1; bionic_block_body "# not a marker"' _ "$DETECT_SH")"

# S3 — "PARSES" NEVER DEPENDS ON THE RC'S LAST STATUS. zsh's -n exits 1 after a negated
# last pipeline with nothing on stderr. A .zshrc whose last line is `! true`, bionic's
# block above it: removed by setup --only AND --all (one answer), and never called an
# rc that does not parse.
T66_SHELL=/bin/zsh
for T75_D in setup-only setup-all; do
  T75_SB="$(new_sandbox)"; T75_RC="$(t66_rc "$T75_SB")"
  printf '%s\n' 'export SECRETTOKEN=1' "$ALIAS_START" "$T66_ALIAS" "$ALIAS_END" '! true' > "$T75_RC"
  printf '%s\n' 'export SECRETTOKEN=1' '! true' > "$TMP/t75s3-expected"
  [ "$T75_D" = "setup-all" ] && t66_pageblock | tee -a "$T75_RC" >> "$TMP/t75s3-expected"
  T75_OUT="$(t66_door "$T75_SB" "$T75_D" y)"
  expect_same_bytes "T75 S3 bang-last (zsh, ${T75_D}): bionic's block goes, every other byte stays" "$TMP/t75s3-expected" "$T75_RC"
  expect_absent "T75 S3 bang-last (zsh, ${T75_D}): …and the rc is never called one that does not parse" "does not parse" "$T75_OUT"
done

# S1 — THE STAGED COPY. A spy `bash` and `zsh` first on PATH records, for every `-n`
# call a decision makes, the staged copy's mode and its directory's; and sleeps, so a
# signal can reach the door mid-decision. Every copy is 0600 in a 0700 directory, and
# on HUP, INT and TERM sent to the door's process group nothing is left in TMPDIR.
mkdir -p "$TMP/spy"
for T75_S in bash zsh; do
  printf '#!/bin/bash\nfor a in "$@"; do f="$a"; done\ncase " $* " in *" -n "*) printf "%%s %%s\\n" "$(stat -f %%Lp "$f")" "$(stat -f %%Lp "${f%%/*}")" >> "${SPY_LOG:-%s}"; [ -n "${SPY_SLEEP:-}" ] && { : > "${SPY_LOG:-%s}.sleeping"; sleep "$SPY_SLEEP"; } ;; esac\nexec /bin/%s "$@"\n' "$TMP/spy.log" "$TMP/spy.log" "$T75_S" > "$TMP/spy/$T75_S"
  chmod +x "$TMP/spy/$T75_S"
done
T66_SHELL=/bin/bash
T75_SB="$(new_sandbox)"; T75_RC="$(t66_rc "$T75_SB")"
printf '%s\n' 'export A=1' "$ALIAS_START" "$T66_ALIAS" "$ALIAS_END" 'export B=2' > "$T75_RC"
: > "$TMP/spy.log"
T66_PATH="$TMP/spy:$T51_PATH" SPY_LOG="$TMP/spy.log" t66_door "$T75_SB" setup-only y >/dev/null
T66_PATH="$T51_PATH"
expect_nonempty "T75 S1: the spy saw the decision's -n calls" "$(cat "$TMP/spy.log")"
expect_eq "T75 S1: every staged copy is 0600 in a 0700 directory" "600 700" "$(sort -u "$TMP/spy.log")"
expect_eq "T75 S1: …bionic's block went (the decision ran to its end)" "0" "$(count_lines_equal "$T75_RC" "$T66_ALIAS")"
expect_empty "T75 S1: …and nothing is left in TMPDIR" "$(find "$T75_SB/.tmp" -name 'bionic-rc.*' 2>/dev/null)"
# S2's flag rows. Under `-n` neither shell runs a startup file, so a door that dropped
# zsh's `-f` or the emptied BASH_ENV and ENV would leave no marker (both mutants were
# run: .bionic/tmp/scratch/w27-T75/mut.log). So the spy reads the calls themselves:
# with BASH_ENV and ENV set in the door's own environment, every zsh call carries
# `-f`, and every decision shell gets BASH_ENV and ENV empty.
mkdir -p "$TMP/spyargs"
for T75_S in bash zsh; do
  printf '#!/bin/bash\ncase " $* " in *" -n "*) printf "%%s %%s BASH_ENV=[%%s] ENV=[%%s]\\n" "%s" "$*" "${BASH_ENV-unset}" "${ENV-unset}" >> "%s" ;; esac\nexec /bin/%s "$@"\n' "$T75_S" "$TMP/spyargs.log" "$T75_S" > "$TMP/spyargs/$T75_S"
  chmod +x "$TMP/spyargs/$T75_S"
done
for T75_SH in bash zsh; do
  T66_SHELL="/bin/$T75_SH"
  T75_SB="$(new_sandbox)"; T75_RC="$(t66_rc "$T75_SB")"; mkdir -p "$T75_SB/.tmp"
  printf '%s\n' 'export A=1' "$ALIAS_START" "$T66_ALIAS" "$ALIAS_END" 'export B=2' > "$T75_RC"
  printf ':\n' > "$T75_SB/benv.sh"; : > "$TMP/spyargs.log"
  printf 'y\n' | env -i HOME="$T75_SB" ZDOTDIR="$T75_SB" CLAUDE_CONFIG_DIR="$T75_SB/.claude" BIONIC_CLAUDE_HOME="$T75_SB/.claude" \
    SHELL="/bin/$T75_SH" PATH="$TMP/spyargs:$T51_PATH" TMPDIR="$T75_SB/.tmp" TERM=dumb BASH_ENV="$T75_SB/benv.sh" ENV="$T75_SB/benv.sh" \
    bash "$SETUP_SH" --only legacy-alias >/dev/null 2>&1
  T75_CALLS="$(grep -c . "$TMP/spyargs.log")"
  expect_true "T75 S2 flags (${T75_SH}): the spy saw the decision's ${T75_SH} -n calls" test "$(grep -c "^${T75_SH} " "$TMP/spyargs.log")" -gt 0
  expect_eq "T75 S2 flags (${T75_SH}): every decision shell got BASH_ENV and ENV empty, with both set in the door's" \
    "$T75_CALLS" "$(grep -c 'BASH_ENV=\[\] ENV=\[\]$' "$TMP/spyargs.log")"
  case "$T75_SH" in zsh)
    expect_eq "T75 S2 flags (zsh): every zsh call carries -f" "$(grep -c '^zsh ' "$TMP/spyargs.log")" "$(grep -c '^zsh -f -n ' "$TMP/spyargs.log")" ;;
  esac
done
T66_SHELL=/bin/bash

for T75_SIG in HUP INT TERM; do
  T75_SB="$(new_sandbox)"; T75_RC="$(t66_rc "$T75_SB")"; mkdir -p "$T75_SB/.tmp"
  printf '%s\n' 'export A=1' "$ALIAS_START" "$T66_ALIAS" "$ALIAS_END" 'export B=2' > "$T75_RC"
  rm -f "$TMP/spy.log" "$TMP/spy.log.sleeping"
  set -m
  ( printf 'y\n' | env -i HOME="$T75_SB" ZDOTDIR="$T75_SB" CLAUDE_CONFIG_DIR="$T75_SB/.claude" BIONIC_CLAUDE_HOME="$T75_SB/.claude" \
      SHELL=/bin/bash PATH="$TMP/spy:$T51_PATH" TMPDIR="$T75_SB/.tmp" TERM=dumb SPY_LOG="$TMP/spy.log" SPY_SLEEP=20 \
      bash "$SETUP_SH" --only legacy-alias >/dev/null 2>&1 ) &
  T75_PID=$!
  set +m
  T75_W=0; while [ ! -e "$TMP/spy.log.sleeping" ] && [ "$T75_W" -lt 1200 ]; do sleep 0.1; T75_W=$((T75_W + 1)); done
  expect_true "T75 S1 ${T75_SIG}: the door was stopped inside a decision (the spy was asleep)" test -e "$TMP/spy.log.sleeping"
  expect_nonempty "T75 S1 ${T75_SIG}: …with a staged copy in TMPDIR at that moment" "$(find "$T75_SB/.tmp" -name 'bionic-rc.*' 2>/dev/null)"
  kill -"$T75_SIG" -- "-$T75_PID" 2>/dev/null
  wait "$T75_PID" 2>/dev/null
  sleep 1
  expect_empty "T75 S1 ${T75_SIG}: after the signal nothing is left in TMPDIR" "$(find "$T75_SB/.tmp" -name 'bionic-rc.*' 2>/dev/null)"
done

# S2 — ROWS THAT CAN FAIL if a door ever ran an rc, kept a staged copy, dropped zsh's
# `-f` or the emptied BASH_ENV/ENV, or asked the wrong shell. A home whose every startup
# file, and a BASH_ENV and ENV, plant a marker; an rc whose first line plants one; each
# door run in it under its own shell; then no marker exists. The positive beside it:
# executing that rc (the oracle's executor) does plant the rc's marker. And a .zshrc with
# zsh's own syntax after bionic's block: zsh parses it, so the block goes; bash, the
# wrong shell, would call the rc unparseable and leave it.
t75_markers() {  # <home> — plant a marker in every file a shell could read at start
  local f
  mkdir -p "$1/zd"
  for f in .zshenv .zprofile .zlogin .bash_profile .profile .bash_login zd/.zshenv zd/.zshrc mark-benv.sh mark-env.sh; do
    # A BASH_ENV or ENV file is read by the door's own bash too: it plants its marker
    # only when the shell reading it was started on a staged copy.
    case "$f" in mark-*) printf 'case "$0" in *bionic-rc.*) touch "%s/MARK-%s" ;; esac\n' "$1" "$f" > "$1/$f" ;;
      *) printf 'touch "%s/MARK-%s"\n' "$1" "${f//\//_}" > "$1/$f" ;; esac
  done
}
for T75_SH in bash zsh; do
  T66_SHELL="/bin/$T75_SH"
  for T75_D in setup-only rm-payload doctor; do
    T75_SB="$(new_sandbox)"; T75_RC="$(t66_rc "$T75_SB")"; t75_markers "$T75_SB"; mkdir -p "$T75_SB/.tmp"
    printf '%s\n' 'touch "$HOME/MARK-rc"' 'export A=1' "$ALIAS_START" "$T66_ALIAS" "$ALIAS_END" 'export B=2' > "$T75_RC"
    case "$T75_D" in
      setup-only) T75_IN=y; T75_CMD=("$SETUP_SH" --only legacy-alias) ;;
      rm-payload) T75_IN=y; T75_CMD=("$REMOVE_SH" --only legacy-alias) ;;
      doctor)     T75_IN=""; T75_CMD=("$DOCTOR_SH") ;;
    esac
    printf '%s\n' "$T75_IN" | env -i HOME="$T75_SB" ZDOTDIR="$T75_SB/zd" CLAUDE_CONFIG_DIR="$T75_SB/.claude" BIONIC_CLAUDE_HOME="$T75_SB/.claude" \
      SHELL="/bin/$T75_SH" PATH="$T51_PATH" TMPDIR="$T75_SB/.tmp" TERM=dumb BASH_ENV="$T75_SB/mark-benv.sh" ENV="$T75_SB/mark-env.sh" \
      BIONIC_DOCTOR_PROBE_SECONDS=15 bash "${T75_CMD[@]}" > "$TMP/t75s2-out" 2>&1
    T75_L="T75 S2 (${T75_SH}, ${T75_D})"
    case "$T75_D" in
      doctor) expect_contains "${T75_L}: the door ran (its rows)" "legacy" "$(cat "$TMP/t75s2-out")" ;;
      *) expect_eq "${T75_L}: the door decided and removed bionic's block" "0" "$(count_lines_equal "$T75_RC" "$T66_ALIAS")" ;;
    esac
    expect_empty "${T75_L}: no line of the rc and no startup file ran (no marker)" "$(cd "$T75_SB" && ls MARK-* 2>/dev/null)"
    expect_empty "${T75_L}: …and no staged copy is left" "$(find "$T75_SB/.tmp" -name 'bionic-rc.*' 2>/dev/null)"
  done
  T75_SB="$(new_sandbox)"; printf '%s\n' 'touch "$HOME/MARK-rc"' > "$T75_SB/probe.rc"
  t75_exec "$T75_SB" "$T75_SH" "$T75_SB/probe.rc" >/dev/null
  expect_true "T75 S2 (${T75_SH}): executing the rc does plant its marker (the positive)" test -e "$T75_SB/MARK-rc"
done
T66_SHELL=/bin/zsh
T75_SB="$(new_sandbox)"; T75_RC="$(t66_rc "$T75_SB")"
printf '%s\n' 'export A=1' "$ALIAS_START" "$T66_ALIAS" "$ALIAS_END" 'for i (a b) export V$i=1' > "$T75_RC"
printf '%s\n' 'export A=1' 'for i (a b) export V$i=1' > "$TMP/t75ws-expected"
expect_false "T75 S2 wrong shell: bash cannot parse that .zshrc (the fixture holds)" bash -n "$T75_RC"
t66_door "$T75_SB" setup-only y >/dev/null
expect_same_bytes "T75 S2 wrong shell: zsh, the rc's own shell, decides, and bionic's block goes" "$TMP/t75ws-expected" "$T75_RC"

# S4 — a read-only rc holding the env block: remove --all's page does not offer it.
T66_SHELL=/bin/bash
T75_SB="$(new_sandbox)"; T75_RC="$(t66_rc "$T75_SB")"
printf '%s\n' 'export A=1' "$ENVB_START" "$T66_TODO" "$ENVB_END" > "$T75_RC"; chmod 444 "$T75_RC"; t51_page_item "$T75_SB"
T75_OUT="$(t66_door "$T75_SB" rm-all n)"
expect_contains "T75 S4: remove --all printed its page" "Do all of the above?" "$T75_OUT"
expect_absent "T75 S4: …and a read-only rc's env block is not on it" "delete bionic's environment settings" "$T75_OUT"
T75_SB="$(new_sandbox)"; T75_RC="$(t66_rc "$T75_SB")"
printf '%s\n' 'export A=1' "$ENVB_START" "$T66_TODO" "$ENVB_END" > "$T75_RC"
expect_contains "T75 S4: …a writable one's is (the twin)" "delete bionic's environment settings" "$(t66_door "$T75_SB" rm-all n)"

# S5 — the claude() item refused on a read-only rc keeps a `<rc>.bionic.tmp` it did
# not stage.
T75_SB="$(new_sandbox)"; T75_RC="$(t66_rc "$T75_SB")"
{ printf '%s\n' 'export A=1'; t66_pageblock; } > "$T75_RC"; chmod 444 "$T75_RC"
printf 'mine\n' > "$T75_RC.bionic.tmp"
T75_OUT="$(t66_door "$T75_SB" rm-payload y claude-proxy)"
expect_contains "T75 S5: the claude() item refused the read-only rc" "read-only" "$T75_OUT"
expect_eq "T75 S5: …and the user's own <rc>.bionic.tmp is kept" "mine" "$(cat "$T75_RC.bionic.tmp" 2>/dev/null)"


# ---------------------------------------------------------------------------
section "wave-27 T75: bionic's claude() block clears the name it defines (A-orch-185)"
# ---------------------------------------------------------------------------
#
# With an alias named `claude` standing above the block (bionic's retired bare alias,
# which no door removes any more, or the user's own), zsh and interactive bash expand
# the alias into the function's definition line: a syntax error at every shell start,
# nothing of the rc after it run, the alias still in force. `-n` cannot see it: no
# alias is expanded under `-n`. So the block's body opens with a line that clears the
# name and can never fail the rc, then the function line as before. BEHAVIOUR here is
# the rc SOURCED as each shell reads it, in a throwaway home, on the suite's own lines:
# zsh, and /bin/bash 3.2 interactive (`-i`, where aliases expand).
t75p_source() {  # <shell> <home> <rc> — `AFTER=<v> TYPE=<t>|ERR=<what the rc said on stderr>`
  local out err
  case "$2" in "$TMP"/home-*) ;; *) echo "T75 GUARD: home '$2' is not under the throwaway root" >&2; exit 1 ;; esac
  case "$1" in
    zsh) out="$(env -i HOME="$2" PATH=/usr/bin:/bin /bin/zsh -f -c '. "$1"; echo "AFTER=${AFTER:-}"; echo "TYPE=$(whence -w claude)"' t "$3" 2>"$2/.t75p-err" </dev/null)" ;;
    *)   out="$(env -i HOME="$2" PATH=/usr/bin:/bin /bin/bash --norc --noprofile -i -c '. "$1"; echo "AFTER=${AFTER:-}"; echo "TYPE=$(type -t claude)"' t "$3" 2>"$2/.t75p-err" </dev/null)" ;;
  esac
  # bash -i with no terminal says it has no job control: the harness's line, not the rc's.
  err="$(grep -v 'no job control in this shell' "$2/.t75p-err")"
  printf '%s|ERR=%s' "$(printf '%s' "$out" | tr '\n' ' ')" "$err"
}
for T75_SH in zsh bash; do
  T66_SHELL="/bin/$T75_SH"
  for T75_V in alias noalias sete-alias sete-noalias; do
    T75_SB="$(new_sandbox)"; T75_RC="$(t66_rc "$T75_SB")"
    {
      case "$T75_V" in sete-*) printf '%s\n' 'set -e' ;; esac
      case "$T75_V" in *noalias) ;; *) printf '%s\n' "alias claude='echo ALIAS'" ;; esac
      printf '%s\n' 'export BEFORE=1'
    } > "$T75_RC"
    T75_OUT="$(t66_door "$T75_SB" setup-only y claude-proxy)"
    printf '%s\n' 'export AFTER=1' >> "$T75_RC"
    T75_L="T75 claude() (${T75_SH}, ${T75_V})"
    expect_contains "${T75_L}: setup wrote the block (the rows below are not vacuous)" "$PROXY_BODY" "$(rc_block_lines "$T75_RC")"
    T75_ST="$(t75p_source "$T75_SH" "$T75_SB" "$T75_RC")"
    expect_contains "${T75_L}: the line after the block runs" "AFTER=1 " "$T75_ST"
    expect_contains "${T75_L}: …and claude is the function" "function" "${T75_ST%%|*}"
    expect_eq "${T75_L}: …and the rc says nothing on stderr" "ERR=" "${T75_ST#*|}"
  done
  # The old one-line body under the same alias: the error this row exists for (kept as
  # its mutant, so the rows above can fail).
  T75_SB="$(new_sandbox)"; T75_RC="$(t66_rc "$T75_SB")"
  printf '%s\n' "alias claude='echo ALIAS'" "$RC_START_LIT" "$PROXY_LINE" "$RC_END_LIT" 'export AFTER=1' > "$T75_RC"
  T75_ST="$(t75p_source "$T75_SH" "$T75_SB" "$T75_RC")"
  expect_absent "T75 claude() (${T75_SH}, old body under an alias): the line after the block does not run" "AFTER=1 " "$T75_ST"
  expect_ne "T75 claude() (${T75_SH}, old body under an alias): …and the rc errors on stderr" "ERR=" "${T75_ST#*|}"
done

# BYTES. Setup on an rc holding the old block (where setup wrote it, at the end) writes
# exactly the new block and no other byte; setup twice is the same bytes; remove leaves
# the rc as it was before setup.
T66_SHELL=/bin/zsh
T75_SB="$(new_sandbox)"; T75_RC="$(t66_rc "$T75_SB")"
printf '%s\n' 'export A=1' "$RC_START_LIT" "$PROXY_LINE" "$RC_END_LIT" > "$T75_RC"
printf '%s\n' 'export A=1' "$RC_START_LIT" "$PROXY_UNALIAS" "$PROXY_LINE" "$RC_END_LIT" > "$TMP/t75p-new"
T75_OUT="$(t66_door "$T75_SB" setup-only y claude-proxy)"
expect_contains "T75 claude() bytes: an old block is offered again (not written)" "[y/N]" "$T75_OUT"
expect_same_bytes "T75 claude() bytes: …and the yes writes exactly the new block, no other byte" "$TMP/t75p-new" "$T75_RC"
T75_OUT="$(t66_door "$T75_SB" setup-only y claude-proxy)"
expect_same_bytes "T75 claude() bytes: setup a second time is the same bytes" "$TMP/t75p-new" "$T75_RC"
expect_absent "T75 claude() bytes: …and asks nothing" "[y/N]" "$T75_OUT"
T75_SB="$(new_sandbox)"; T75_RC="$(t66_rc "$T75_SB")"
printf '%s\n' 'export A=1' 'alias ll=x' > "$T75_RC"; cp "$T75_RC" "$TMP/t75p-before"
t66_door "$T75_SB" setup-only y claude-proxy >/dev/null
expect_diff_bytes "T75 claude() bytes: setup on a fresh rc wrote the block (the twin)" "$TMP/t75p-before" "$T75_RC"
t66_door "$T75_SB" rm-payload y claude-proxy >/dev/null
expect_same_bytes "T75 claude() bytes: …and remove leaves the rc as it was before setup" "$TMP/t75p-before" "$T75_RC"

# THE ONE OWNER OF "IS IT WRITTEN". rc_get answers done for exactly the two lines.
t75p_get() {  # <body line…> — rc_get's answer on a block holding those lines
  local sb; sb="$(new_sandbox)"
  { printf '%s\n' "$RC_START_LIT"; printf '%s\n' "$@"; printf '%s\n' "$RC_END_LIT"; } > "$sb/.zshrc"
  if env_run "$sb" /bin/zsh -- rc_get claude-proxy >/dev/null 2>&1; then echo written; else echo not; fi
}
expect_eq "T75 rc_get: the new body is written" "written" "$(t75p_get "$PROXY_UNALIAS" "$PROXY_LINE")"
expect_eq "T75 rc_get: the old one-line body is not" "not" "$(t75p_get "$PROXY_LINE")"
expect_eq "T75 rc_get: the new body's lines swapped are not" "not" "$(t75p_get "$PROXY_LINE" "$PROXY_UNALIAS")"
T75_SB="$(new_sandbox)"; printf '%s\n' "$RC_START_LIT" "$PROXY_LINE" "$PROXY_UNALIAS" "$RC_END_LIT" > "$T75_SB/.zshrc"
expect_eq "T75 rc_state: …they are the changed state, never offered (T77)" "changed" \
  "$(env_run "$T75_SB" /bin/zsh -- rc_state claude-proxy 2>&1)"
# A user's line beside the new body reads written since wave-27 T77 (review pass 64): the
# block is left as it is, never rewritten without the user's line.
expect_eq "T75 rc_get: the new body plus a user's line is written (T77)" "written" "$(t75p_get "$PROXY_UNALIAS" "$PROXY_LINE" 'export MINE=1')"
T66_SHELL=/bin/bash

# ---------------------------------------------------------------------------
section "wave-27 T77: a claude() block the user changed is never rewritten (review pass 64)"
# ---------------------------------------------------------------------------
#
# Since T75 a block holding bionic's lines AND a line of the user's read "not written",
# and a yes rewrote it whole without the user's line. The rule now: a block is bionic's
# to rewrite only when its body is byte for byte a body bionic wrote (the current one,
# an earlier one, or nothing). The current lines in order with other lines among them
# read written and are left; anything else is changed: nothing asked, nothing written,
# named by its line range. Review pass 64's rows R1 to R12 are the model: every rc is
# `export V1=1`, the block (from line 2), `export V2=2`, in a throwaway home, under zsh
# and /bin/bash, through `--only` and `--all`.
T77_U='export V9=9'
T77_OLD1='claude() { command claude --dangerously-skip-permissions "$@"; }'
T77_EDIT='claude() { command claude --allow-dangerously-skip-permissions --verbose "$@"; }'
t77_body() {  # <shape> — the lines between the markers
  case "$1" in
    cur)         printf '%s\n' "$PROXY_UNALIAS" "$PROXY_LINE" ;;
    u-above)     printf '%s\n' "$T77_U" "$PROXY_UNALIAS" "$PROXY_LINE" ;;
    u-between)   printf '%s\n' "$PROXY_UNALIAS" "$T77_U" "$PROXY_LINE" ;;
    u-below)     printf '%s\n' "$PROXY_UNALIAS" "$PROXY_LINE" "$T77_U" ;;
    old2)        printf '%s\n' "$PROXY_LINE" ;;
    old1)        printf '%s\n' "$T77_OLD1" ;;
    empty)       ;;
    old-u-below) printf '%s\n' "$PROXY_LINE" "$T77_U" ;;
    old-u-above) printf '%s\n' "$T77_U" "$PROXY_LINE" ;;
    swapped)     printf '%s\n' "$PROXY_LINE" "$PROXY_UNALIAS" ;;
    edited)      printf '%s\n' "$PROXY_UNALIAS" "$T77_EDIT" ;;
  esac
}
t77_plant() {  # <file> <shape> — `none` plants no markers
  { printf '%s\n' 'export V1=1'
    if [ "$2" != none ]; then printf '%s\n' "$RC_START_LIT"; t77_body "$2"; printf '%s\n' "$RC_END_LIT"; fi
    printf '%s\n' 'export V2=2'; } > "$1"
}
# What a yes leaves: a stale block's body replaced where it stands, no other byte
# changed; no block, bionic's appended.
t77_after_yes() {  # <file> <shape>
  case "$2" in
    none) printf '%s\n' 'export V1=1' 'export V2=2' "$RC_START_LIT" "$PROXY_UNALIAS" "$PROXY_LINE" "$RC_END_LIT" > "$1" ;;
    *)    printf '%s\n' 'export V1=1' "$RC_START_LIT" "$PROXY_UNALIAS" "$PROXY_LINE" "$RC_END_LIT" 'export V2=2' > "$1" ;;
  esac
}
t77_state() { case "$1" in cur|u-*) echo written ;; old1|old2|empty) echo stale ;; none) echo no ;; *) echo changed ;; esac; }
t77_last() { local n; n="$(t77_body "$1" | wc -l)"; echo $(( 3 + ${n// /} )); }  # the end marker's line
T77_ALL="cur u-above u-between u-below old2 old1 empty none old-u-below old-u-above swapped edited"

# THE ONE OWNER. env.sh `rc_state` answers every shape, and the fixture's shapes are
# what this section says they are (the extractor reads the block back non-empty).
expect_eq "T77 fixture: the u-between block holds three lines" "3" "$(t66_rc_tmp="$TMP/t77-fx"; t77_plant "$t66_rc_tmp" u-between; rc_block_lines "$t66_rc_tmp" | wc -l | tr -d ' ')"
expect_eq "T77 fixture: the swapped block ends at line 5" "5" "$(t77_last swapped)"
for T77_S in $T77_ALL; do
  T77_SB="$(new_sandbox)"; t77_plant "$T77_SB/.zshrc" "$T77_S"
  expect_eq "T77 rc_state ${T77_S}: $(t77_state "$T77_S")" "$(t77_state "$T77_S")" \
    "$(env_run "$T77_SB" /bin/zsh -- rc_state claude-proxy 2>&1)"
done
T77_SB="$(new_sandbox)"; t77_plant "$T77_SB/.zshrc" old-u-below
expect_eq "T77 detect: a changed block is present=changed" "env:rc-claude-proxy present=changed" "$(detect_run "$T77_SB")"
T77_SB="$(new_sandbox)"; t77_plant "$T77_SB/.zshrc" u-between
expect_eq "T77 detect: the current lines beside a user's line are present=yes" "env:rc-claude-proxy present=yes" "$(detect_run "$T77_SB")"

# SETUP, --only, every shape, both shells, answered yes.
for T77_SH in zsh bash; do
  T66_SHELL="/bin/$T77_SH"
  for T77_S in $T77_ALL; do
    T77_SB="$(new_sandbox)"; T77_RC="$(t66_rc "$T77_SB")"
    t77_plant "$T77_RC" "$T77_S"; cp "$T77_RC" "$TMP/t77-before"
    T77_OUT="$(t66_door "$T77_SB" setup-only y claude-proxy)"
    T77_L="T77 setup --only (${T77_SH}, ${T77_S}, $(t77_state "$T77_S"))"
    case "$(t77_state "$T77_S")" in
      written)
        expect_contains "${T77_L}: already in" "already in" "$T77_OUT"
        expect_absent "${T77_L}: …nothing asked" "[y/N]" "$T77_OUT"
        expect_same_bytes "${T77_L}: …the rc byte for byte as it was" "$TMP/t77-before" "$T77_RC" ;;
      stale|no)
        t77_after_yes "$TMP/t77-want" "$T77_S"
        expect_contains "${T77_L}: offered" "[y/N]" "$T77_OUT"
        expect_same_bytes "${T77_L}: …and the yes leaves exactly bionic's body, no other byte changed" "$TMP/t77-want" "$T77_RC" ;;
      changed)
        expect_contains "${T77_L}: named by its line range" "lines 2 to $(t77_last "$T77_S") of" "$T77_OUT"
        expect_contains "${T77_L}: …with bionic's first line for the user's hand" "     ${PROXY_UNALIAS}" "$T77_OUT"
        expect_contains "${T77_L}: …and bionic's second" "     ${PROXY_LINE}" "$T77_OUT"
        expect_absent "${T77_L}: …nothing asked" "[y/N]" "$T77_OUT"
        expect_absent "${T77_L}: …no user's line printed" "V9=9" "$T77_OUT"
        expect_absent "${T77_L}: …nor the user's edit" "--verbose" "$T77_OUT"
        expect_same_bytes "${T77_L}: …the rc byte for byte as it was" "$TMP/t77-before" "$T77_RC" ;;
    esac
  done
done

# SETUP, --all, the four states and the three changed shapes, both shells, answered yes.
for T77_SH in zsh bash; do
  T66_SHELL="/bin/$T77_SH"
  for T77_S in cur u-between old2 old-u-below swapped edited; do
    T77_SB="$(new_sandbox)"; T77_RC="$(t66_rc "$T77_SB")"
    t77_plant "$T77_RC" "$T77_S"; cp "$T77_RC" "$TMP/t77-before"
    T77_OUT="$(t66_door "$T77_SB" setup-all y)"
    T77_L="T77 setup --all (${T77_SH}, ${T77_S}, $(t77_state "$T77_S"))"
    expect_contains "${T77_L}: the page was printed" "Do all of the above?" "$T77_OUT"
    case "$(t77_state "$T77_S")" in
      stale)
        t77_after_yes "$TMP/t77-want" "$T77_S"
        expect_contains "${T77_L}: the page offers it" "add bionic's claude() shell function" "$T77_OUT"
        expect_same_bytes "${T77_L}: …and the yes leaves exactly bionic's body, no other byte changed" "$TMP/t77-want" "$T77_RC" ;;
      *)
        expect_absent "${T77_L}: the page does not offer it" "add bionic's claude() shell function" "$T77_OUT"
        expect_same_bytes "${T77_L}: …the rc byte for byte as it was" "$TMP/t77-before" "$T77_RC" ;;
    esac
    case "$(t77_state "$T77_S")" in
      changed) expect_contains "${T77_L}: named by its line range" "lines 2 to $(t77_last "$T77_S") of" "$T77_OUT"
               expect_absent "${T77_L}: …no user's line printed" "V9=9" "$T77_OUT" ;;
      written) expect_contains "${T77_L}: already in" "already in" "$T77_OUT" ;;
    esac
  done
done

# THE WRITER REFUSES. rc_set on every changed shape: its own reason (not one of
# markers.sh's 0 to 4), the rc byte for byte as it was. Beside it, the stale body is
# written in place and the written block left as it is.
for T77_S in old-u-below old-u-above swapped edited; do
  T77_SB="$(new_sandbox)"; t77_plant "$T77_SB/.zshrc" "$T77_S"; cp "$T77_SB/.zshrc" "$TMP/t77-before"
  env_run "$T77_SB" /bin/zsh -- rc_set claude-proxy >/dev/null 2>&1; T77_RCS=$?
  expect_eq "T77 rc_set (${T77_S}): refused with its own reason" "5" "$T77_RCS"
  expect_same_bytes "T77 rc_set (${T77_S}): …the rc byte for byte as it was" "$TMP/t77-before" "$T77_SB/.zshrc"
done
T77_SB="$(new_sandbox)"; t77_plant "$T77_SB/.zshrc" old1
env_run "$T77_SB" /bin/zsh -- rc_set claude-proxy >/dev/null 2>&1; T77_RCS=$?
t77_after_yes "$TMP/t77-want" old1
expect_eq "T77 rc_set (old1): writes" "0" "$T77_RCS"
expect_same_bytes "T77 rc_set (old1): …the old rc with exactly the block's body replaced" "$TMP/t77-want" "$T77_SB/.zshrc"
T77_SB="$(new_sandbox)"; t77_plant "$T77_SB/.zshrc" u-between; cp "$T77_SB/.zshrc" "$TMP/t77-before"
env_run "$T77_SB" /bin/zsh -- rc_set claude-proxy >/dev/null 2>&1; T77_RCS=$?
expect_eq "T77 rc_set (u-between, written): succeeds" "0" "$T77_RCS"
expect_same_bytes "T77 rc_set (u-between, written): …and changes no byte" "$TMP/t77-before" "$T77_SB/.zshrc"

# A STALE BLOCK IS REPLACED WHERE IT STANDS (A-orch-193): `markers_set` would move it to
# the end of the rc, past the user's lines below it. First in the rc, last in it, between
# the user's lines, and with no final newline (after the end marker, or after the user's
# last line): the rc is the old rc with exactly the block's body replaced.
t77_place() {  # <file> <where> <body…> — the rc with that body at <where>
  local f="$1" w="$2"; shift 2
  case "$w" in
    first)   { printf '%s\n' "$RC_START_LIT" "$@" "$RC_END_LIT" 'export V1=1' 'export V2=2'; } > "$f" ;;
    last)    { printf '%s\n' 'export V1=1' 'export V2=2' "$RC_START_LIT" "$@" "$RC_END_LIT"; } > "$f" ;;
    between) { printf '%s\n' 'export V1=1' "$RC_START_LIT" "$@" "$RC_END_LIT" 'export V2=2'; } > "$f" ;;
    nonl)    { printf '%s\n' 'export V1=1' "$RC_START_LIT" "$@" "$RC_END_LIT"; printf '%s' 'export V2=2'; } > "$f" ;;
    endnonl) { printf '%s\n' 'export V1=1' "$RC_START_LIT" "$@"; printf '%s' "$RC_END_LIT"; } > "$f" ;;
  esac
}
for T77_SH in zsh bash; do
  T66_SHELL="/bin/$T77_SH"
  for T77_W in first last between nonl endnonl; do
    T77_SB="$(new_sandbox)"; T77_RC="$(t66_rc "$T77_SB")"
    t77_place "$T77_RC" "$T77_W" "$PROXY_LINE"
    t77_place "$TMP/t77-want" "$T77_W" "$PROXY_UNALIAS" "$PROXY_LINE"
    T77_OUT="$(t66_door "$T77_SB" setup-only y claude-proxy)"
    expect_contains "T77 in place (${T77_SH}, ${T77_W}): the stale block was offered" "[y/N]" "$T77_OUT"
    expect_same_bytes "T77 in place (${T77_SH}, ${T77_W}): …and the yes replaces its body where it stands, no other byte changed" \
      "$TMP/t77-want" "$T77_RC"
  done
done
T66_SHELL=/bin/zsh
# A cut-short write stages nothing and leaves the rc as it was; with room, the same
# call writes in place (the twin).
T77_SB="$(new_sandbox)"
{ for _i in $(seq 1 150); do printf 'export MY_VAR_%s=mine\n' "$_i"; done
  printf '%s\n' "$RC_START_LIT" "$PROXY_LINE" "$RC_END_LIT"
  for _i in $(seq 151 300); do printf 'export MY_VAR_%s=mine\n' "$_i"; done; } > "$T77_SB/.zshrc"
cp "$T77_SB/.zshrc" "$TMP/t77-before"; T77_LS="$(ls -A "$T77_SB")"
T77_OUT="$(t40_env "$T77_SB" 'trap "" XFSZ; ulimit -f 2; rc_set claude-proxy; echo "rc=$?"')"
expect_contains "T77 in place, cut short: rc_set reports the failed write" "rc=1" "$T77_OUT"
expect_same_bytes "T77 in place, cut short: …the rc byte for byte as it was" "$TMP/t77-before" "$T77_SB/.zshrc"
expect_nonempty "T77 in place, cut short: the home's listing was read" "$T77_LS"
expect_eq "T77 in place, cut short: …and nothing staged is left beside the rc" "$T77_LS" "$(ls -A "$T77_SB")"
T77_OUT="$(t40_env "$T77_SB" 'rc_set claude-proxy; echo "rc=$?"')"
expect_contains "T77 in place, with room: the same call writes" "rc=0" "$T77_OUT"
expect_eq "T77 in place, with room: …the block where it stood, after the user's 150th line" \
  "export MY_VAR_150=mine|${RC_START_LIT}|${PROXY_UNALIAS}" \
  "$(sed -n '150p;151p;152p' "$T77_SB/.zshrc" | paste -sd '|' -)"

# THE MUTANT. A copy of the library with the writer's guard line deleted loses the
# user's line on the same call; the copy is proved to run (it writes the stale twin).
rm -rf "$TMP/t77lib"; cp -R "$(dirname "$ENV_SH")" "$TMP/t77lib"
T77_GUARD="$(grep -c 'guard: a changed block is never written' "$TMP/t77lib/env.sh")"
expect_eq "T77 mutant: the guard line is in the library, once" "1" "$T77_GUARD"
grep -v 'guard: a changed block is never written' "$TMP/t77lib/env.sh" > "$TMP/t77lib/env.sh.m" && mv "$TMP/t77lib/env.sh.m" "$TMP/t77lib/env.sh"
t77_mut_set() {  # <sandbox>
  HOME="$1" SHELL=/bin/zsh PATH="$TMP/bin:$PATH" BIONIC_CLAUDE_HOME="$1/.claude" \
    bash -c '. "$1" || exit 90; rc_set claude-proxy' _ "$TMP/t77lib/env.sh" >/dev/null 2>&1
}
T77_SB="$(new_sandbox)"; t77_plant "$T77_SB/.zshrc" old2; t77_mut_set "$T77_SB"
t77_after_yes "$TMP/t77-want" old2
expect_same_bytes "T77 mutant: the guardless copy runs (it writes a stale block)" "$TMP/t77-want" "$T77_SB/.zshrc"
T77_SB="$(new_sandbox)"; t77_plant "$T77_SB/.zshrc" old-u-below; cp "$T77_SB/.zshrc" "$TMP/t77-before"; t77_mut_set "$T77_SB"
expect_diff_bytes "T77 mutant: …and without its guard rc_set rewrites a changed block" "$TMP/t77-before" "$T77_SB/.zshrc"
expect_eq "T77 mutant: …losing the user's line" "0" "$(count_lines_equal "$T77_SB/.zshrc" "$T77_U")"

# DOCTOR. A changed block is a row of its own, neutral, named by its line range, to edit
# by hand and not routed to setup; written reads on; stale keeps its row and route.
T66_SHELL=/bin/zsh
for T77_S in u-between old2 old-u-below edited; do
  T77_SB="$(new_sandbox)"; T77_RC="$(t66_rc "$T77_SB")"; t77_plant "$T77_RC" "$T77_S"
  T77_DOC="$(t66_door "$T77_SB" doctor)"
  T77_ROW="$(report_row "$T77_DOC" "$DOCTOR_ROW_LABEL")"
  T77_L="T77 doctor (${T77_S}, $(t77_state "$T77_S"))"
  expect_nonempty "${T77_L}: a proxy row" "$T77_ROW"
  case "$(t77_state "$T77_S")" in
    written) expect_contains "${T77_L}: on" " on " "$T77_ROW" ;;
    stale)   expect_contains "${T77_L}: stale, routed to setup" "/bionic:setup rewrites it" "$T77_ROW" ;;
    changed)
      expect_contains "${T77_L}: neutral, says changed" "– ${DOCTOR_ROW_LABEL}" "$T77_ROW"
      expect_contains "${T77_L}: …says changed" " changed " "$T77_ROW"
      expect_contains "${T77_L}: …names the lines" "lines 2 to $(t77_last "$T77_S") of ~/.zshrc" "$T77_ROW"
      expect_contains "${T77_L}: …to edit by hand" "edit it by hand" "$T77_ROW"
      expect_absent "${T77_L}: …not routed to setup" "/bionic:setup" "$T77_ROW"
      expect_absent "${T77_L}: …and no fix line for it" "claude() shell proxy is an older line" "$T77_DOC" ;;
  esac
done

# REMOVE is T78's, below: T77 drove it unchanged (a changed block went whole), and that
# answer is the one T78 retires.
T66_SHELL=/bin/bash

# ---------------------------------------------------------------------------
section "wave-27 T78: remove never deletes a line the user added inside bionic's claude() block"
# ---------------------------------------------------------------------------
#
# Remove stripped the live block whole on both doors whatever stood between its markers,
# and under `--all` the page never named the user's line it took. The rule is T77's for
# setup, applied to remove: the block goes only when its body is byte for byte the current
# body, an earlier one (`rc_earlier`), or nothing. Anything else is named by its line
# range, never asked about, never on the page, never stripped, on both doors and under
# both shells; two marker pairs are malformed, named by their faults and never asked
# about. The shapes are T77's (`t77_body`): `export V1=1`, the block from line 2,
# `export V2=2`.
T78_OURS="cur old2 old1 empty"
T78_CHANGED="u-above u-between u-below old-u-below old-u-above edited swapped"
t78_plant() {  # <file> <shape> — T77's shapes, and `two`: two marker pairs
  if [ "$2" = two ]; then
    printf '%s\n' 'export V1=1' "$RC_START_LIT" "$PROXY_UNALIAS" "$PROXY_LINE" "$RC_END_LIT" 'export V2=2' \
      "$RC_START_LIT" "$PROXY_UNALIAS" "$PROXY_LINE" "$RC_END_LIT" > "$1"
  else t77_plant "$1" "$2"; fi
}
t78_named() {  # <rc name> <shape> — the first line a changed block is named with
  printf "  lines 2 to %s of ~/%s are bionic's claude() block, changed since bionic wrote it:" "$(t77_last "$2")" "$1"
}
T78_HAND="    it is left as it is — edit it by hand"
T78_WARN="holds only bionic's lines; bionic would delete it."
printf '%s\n' 'export V1=1' 'export V2=2' > "$TMP/t78-stripped"
# The page under `--all`: everything before its question. Its items end at the last
# bullet; what follows them is the text from that bullet on.
t78_page() { printf '%s' "${1%%Do all of the above?*}"; }
t78_after_items() { local p; p="$(t78_page "$1")"; printf '%s' "${p##*  • }"; }

# THE FIXTURES ARE WHAT THEY SAY: the extractor reads each shape's block back non-empty.
expect_eq "T78 fixture: the u-above block holds three lines, the user's first" \
  "${T77_U}|${PROXY_UNALIAS}|${PROXY_LINE}|" "$(t78_plant "$TMP/t78-fx" u-above; rc_block_lines "$TMP/t78-fx" | tr '\n' '|')"
expect_eq "T78 fixture: two marker pairs hold four lines between them" "4" \
  "$(t78_plant "$TMP/t78-fx" two; rc_block_lines "$TMP/t78-fx" | wc -l | tr -d ' ')"

# --only, BOTH DOORS, BOTH SHELLS, EVERY SHAPE, answered yes.
for T78_SH in zsh bash; do
  T66_SHELL="/bin/$T78_SH"
  for T78_D in rm-payload rm-standalone; do
    for T78_S in $T78_OURS $T78_CHANGED two; do
      T78_SB="$(new_sandbox)"; T78_RC="$(t66_rc "$T78_SB")"
      t78_plant "$T78_RC" "$T78_S"; cp "$T78_RC" "$TMP/t78-before"
      T78_OUT="$(t66_door "$T78_SB" "$T78_D" y claude-proxy)"
      T78_L="T78 remove --only (${T78_D}, ${T78_SH}, ${T78_S})"
      case " $T78_OURS " in
        *" $T78_S "*)
          expect_contains "${T78_L}: the warning says the block holds only bionic's lines" "$T78_WARN" "$T78_OUT"
          expect_contains "${T78_L}: …asks" "[y/N]" "$T78_OUT"
          expect_contains "${T78_L}: …reports it removed" "1 removed" "$T78_OUT"
          expect_same_bytes "${T78_L}: …and the yes takes the block whole, the user's lines byte for byte" "$TMP/t78-stripped" "$T78_RC" ;;
        *)
          expect_absent "${T78_L}: nothing asked" "[y/N]" "$T78_OUT"
          expect_same_bytes "${T78_L}: …the rc byte for byte as it was" "$TMP/t78-before" "$T78_RC"
          expect_contains "${T78_L}: …not reported removed, nor clean" "0 removed · 0 already clean" "$T78_OUT"
          expect_absent "${T78_L}: …no user's line printed" "V9=9" "$T78_OUT"
          expect_absent "${T78_L}: …nor the user's edit" "--verbose" "$T78_OUT"
          if [ "$T78_S" = two ]; then
            expect_contains "${T78_L}: …named by its faults" "line 7: a second block (the first starts at line 2)" "$T78_OUT"
            expect_contains "${T78_L}: …which say the markers do not pair up" "do not pair up" "$T78_OUT"
          else
            expect_contains "${T78_L}: …named by its line range" "$(t78_named ".${T78_SH}rc" "$T78_S")" "$T78_OUT"
            expect_contains "${T78_L}: …to edit by hand" "$T78_HAND" "$T78_OUT"
          fi ;;
      esac
    done
  done
done

# --all, BOTH SHELLS. Plugin data stands in the home so the page is printed whatever the
# block is; the page's yes is the only answer.
for T78_SH in zsh bash; do
  T66_SHELL="/bin/$T78_SH"
  for T78_S in cur old2 empty u-between old-u-below swapped edited two; do
    T78_SB="$(new_sandbox)"; T78_RC="$(t66_rc "$T78_SB")"; mkdir -p "$T78_SB/.claude/plugins/data/bionic-t78"
    t78_plant "$T78_RC" "$T78_S"; cp "$T78_RC" "$TMP/t78-before"
    T78_OUT="$(t66_door "$T78_SB" rm-all y)"
    T78_L="T78 remove --all (${T78_SH}, ${T78_S})"
    expect_contains "${T78_L}: the page was printed with an item on it" "delete bionic's plugin data" "$(t78_page "$T78_OUT")"
    case "$T78_S" in
      cur|old2|empty)
        expect_contains "${T78_L}: the page offers the block" "remove bionic's claude() shell function" "$(t78_page "$T78_OUT")"
        expect_same_bytes "${T78_L}: …and the page's yes takes it whole" "$TMP/t78-stripped" "$T78_RC" ;;
      two)
        expect_absent "${T78_L}: the page does not offer the block" "remove bionic's claude() shell function" "$(t78_page "$T78_OUT")"
        expect_contains "${T78_L}: …names its faults after the page's items" "a second block" "$(t78_after_items "$T78_OUT")"
        expect_same_bytes "${T78_L}: …and the rc is byte for byte as it was" "$TMP/t78-before" "$T78_RC" ;;
      *)
        expect_absent "${T78_L}: the page does not offer the block" "remove bionic's claude() shell function" "$(t78_page "$T78_OUT")"
        expect_contains "${T78_L}: …names it by its lines after the page's items" "$(t78_named ".${T78_SH}rc" "$T78_S")" "$(t78_after_items "$T78_OUT")"
        expect_absent "${T78_L}: …no user's line printed" "V9=9" "$T78_OUT"
        expect_same_bytes "${T78_L}: …and the rc is byte for byte as it was" "$TMP/t78-before" "$T78_RC" ;;
    esac
  done
done
# With nothing else to remove there is no page: the changed block is still named. The
# suite's `claude` stub answers every `mcp get` present, so this run has one of its own that
# registers nothing, and a PATH with no tool bionic installs.
T66_SHELL=/bin/zsh
mkdir -p "$TMP/t78bin"
printf '%s\n' '#!/bin/bash' 'case "$*" in "plugin list --json") echo "[]" ;; "mcp get"*) exit 1 ;; esac' 'exit 0' > "$TMP/t78bin/claude"
chmod +x "$TMP/t78bin/claude"
T78_SB="$(new_sandbox)"; T78_RC="$(t66_rc "$T78_SB")"; t78_plant "$T78_RC" u-between; cp "$T78_RC" "$TMP/t78-before"
T78_PATH_WAS="$T66_PATH"; T66_PATH="$TMP/t78bin:/usr/bin:/bin"
T78_OUT="$(printf 'y\n' | t66_env "$T78_SB" bash "$REMOVE_SH" --all 2>&1)"
T66_PATH="$T78_PATH_WAS"
expect_contains "T78 remove --all, no page: nothing else to remove" "nothing to remove" "$T78_OUT"
expect_contains "T78 remove --all, no page: …and the changed block is named" "$(t78_named .zshrc u-between)" "$T78_OUT"
expect_same_bytes "T78 remove --all, no page: …the rc byte for byte as it was" "$TMP/t78-before" "$T78_RC"

# THE RETIRED ENVIRONMENT BLOCK WITH A USER'S LINE between its markers is left the same
# way (A-orch-201 (2)): every door, `--all` included, both shells. Green on the head it was
# cut from: its body test (`_rm_block_alone`) already leaves it, and a mutant that reads
# every block as alone loses the user's line on every door (the record's drive). The twin,
# bionic's line alone between the markers, goes on the page's yes.
for T78_SH in zsh bash; do
  T66_SHELL="/bin/$T78_SH"
  for T78_D in rm-payload rm-standalone rm-all; do
    for T78_S in user ours; do
      T78_SB="$(new_sandbox)"; T78_RC="$(t66_rc "$T78_SB")"; mkdir -p "$T78_SB/.claude/plugins/data/bionic-t78"
      case "$T78_S" in
        user) printf '%s\n' 'export V1=1' "$ENVB_START" "$T66_TODO" "$T77_U" "$ENVB_END" 'export V2=2' > "$T78_RC" ;;
        ours) printf '%s\n' 'export V1=1' "$ENVB_START" "$T66_TODO" "$ENVB_END" 'export V2=2' > "$T78_RC" ;;
      esac
      cp "$T78_RC" "$TMP/t78-before"
      T78_OUT="$(t66_door "$T78_SB" "$T78_D" y environment)"
      T78_L="T78 retired env block (${T78_D}, ${T78_SH}, ${T78_S})"
      if [ "$T78_S" = ours ]; then
        expect_same_bytes "${T78_L}: bionic's line alone goes with its block (the twin)" "$TMP/t78-stripped" "$T78_RC"
        [ "$T78_D" = rm-all ] && expect_contains "${T78_L}: …offered on the page" "delete bionic's environment settings" "$(t78_page "$T78_OUT")"
      else
        expect_contains "${T78_L}: named by its lines" \
          "lines 2 to 5 of ${T78_RC} are bionic's retired environment block, changed since bionic wrote it" "$T78_OUT"
        expect_absent "${T78_L}: …the user's line never printed" "V9=9" "$T78_OUT"
        expect_same_bytes "${T78_L}: …and the rc byte for byte as it was" "$TMP/t78-before" "$T78_RC"
        [ "$T78_D" = rm-all ] && expect_absent "${T78_L}: …and not on the page" "delete bionic's environment settings" "$(t78_page "$T78_OUT")"
      fi
    done
  done
done

# THE STRIP REFUSES ITSELF, both modes. env.sh's `rc_unset`, and remove.sh's own
# `_rm_rc_unset` called directly from its definitions (the script cut where its items are
# run, sourced with no arguments), standalone and with the payload's libraries beside it.
mkdir -p "$TMP/t78sa" "$TMP/t78pl"
sed '/^_rm_item_legacy_alias$/,$d' "$REMOVE_SH" > "$TMP/t78sa/remove-defs.sh"
cp "$TMP/t78sa/remove-defs.sh" "$TMP/t78pl/remove-defs.sh"; cp -R "$(dirname "$ENV_SH")" "$TMP/t78pl/lib"
t78_rm_unset() {  # <sandbox> <defs file> — `mode=<mode> rc=<n>`
  HOME="$1" ZDOTDIR="$1" SHELL=/bin/zsh PATH="$TMP/bin:/usr/bin:/bin" BIONIC_CLAUDE_HOME="$1/.claude" \
    bash -c 'f="$1"; set --; . "$f" >/dev/null 2>&1; _rm_rc_unset claude-proxy >/dev/null 2>&1; echo "mode=$RM_MODE rc=$?"' _ "$2" 2>&1
}
for T78_S in u-between old-u-below edited swapped; do
  T78_SB="$(new_sandbox)"; t78_plant "$T78_SB/.zshrc" "$T78_S"; cp "$T78_SB/.zshrc" "$TMP/t78-before"
  env_run "$T78_SB" /bin/zsh -- rc_unset claude-proxy >/dev/null 2>&1; T78_RCS=$?
  expect_eq "T78 rc_unset (${T78_S}): refused with its own reason" "5" "$T78_RCS"
  expect_same_bytes "T78 rc_unset (${T78_S}): …the rc byte for byte as it was" "$TMP/t78-before" "$T78_SB/.zshrc"
  for T78_M in sa pl; do
    T78_OUT="$(t78_rm_unset "$T78_SB" "$TMP/t78${T78_M}/remove-defs.sh")"
    case "$T78_M" in sa) T78_MODE=standalone ;; *) T78_MODE=payload ;; esac
    expect_eq "T78 _rm_rc_unset (${T78_MODE}, ${T78_S}): refused with its own reason" "mode=${T78_MODE} rc=5" "$T78_OUT"
    expect_same_bytes "T78 _rm_rc_unset (${T78_MODE}, ${T78_S}): …the rc byte for byte as it was" "$TMP/t78-before" "$T78_SB/.zshrc"
  done
done
# The twins: a block that is all bionic's is stripped by each of the three calls.
for T78_M in env sa pl; do
  T78_SB="$(new_sandbox)"; t78_plant "$T78_SB/.zshrc" old1
  case "$T78_M" in
    env) env_run "$T78_SB" /bin/zsh -- rc_unset claude-proxy >/dev/null 2>&1; T78_OUT="rc=$?"; T78_WANT="rc=0" ;;
    sa)  T78_OUT="$(t78_rm_unset "$T78_SB" "$TMP/t78sa/remove-defs.sh")"; T78_WANT="mode=standalone rc=0" ;;
    pl)  T78_OUT="$(t78_rm_unset "$T78_SB" "$TMP/t78pl/remove-defs.sh")"; T78_WANT="mode=payload rc=0" ;;
  esac
  expect_eq "T78 strip (${T78_M}, old1): an earlier body bionic wrote is stripped (the twin)" "$T78_WANT" "$T78_OUT"
  expect_same_bytes "T78 strip (${T78_M}, old1): …to the user's lines byte for byte" "$TMP/t78-stripped" "$T78_SB/.zshrc"
done

# THE MUTANTS. Each guard line deleted from a copy: the copy runs (it strips a block that
# is all bionic's) and then strips a changed block, losing the user's line.
T78_GUARD='guard: a changed claude() block is never stripped'
expect_eq "T78 mutant: the standalone guard is in remove.sh, once" "1" "$(grep -c "$T78_GUARD" "$TMP/t78sa/remove-defs.sh")"
expect_eq "T78 mutant: the payload guard is in env.sh, once" "1" "$(grep -c "$T78_GUARD" "$TMP/t78pl/lib/env.sh")"
mkdir -p "$TMP/t78msa" "$TMP/t78mpl"
grep -v "$T78_GUARD" "$TMP/t78sa/remove-defs.sh" > "$TMP/t78msa/remove-defs.sh"
cp "$TMP/t78pl/remove-defs.sh" "$TMP/t78mpl/remove-defs.sh"; cp -R "$TMP/t78pl/lib" "$TMP/t78mpl/lib"
grep -v "$T78_GUARD" "$TMP/t78pl/lib/env.sh" > "$TMP/t78mpl/lib/env.sh"
for T78_M in msa mpl; do
  case "$T78_M" in msa) T78_MODE=standalone ;; *) T78_MODE=payload ;; esac
  T78_SB="$(new_sandbox)"; t78_plant "$T78_SB/.zshrc" old2
  expect_eq "T78 mutant (${T78_MODE}): the guardless copy runs (it strips an earlier body)" "mode=${T78_MODE} rc=0" \
    "$(t78_rm_unset "$T78_SB" "$TMP/t78${T78_M}/remove-defs.sh")"
  T78_SB="$(new_sandbox)"; t78_plant "$T78_SB/.zshrc" old-u-below; cp "$T78_SB/.zshrc" "$TMP/t78-before"
  t78_rm_unset "$T78_SB" "$TMP/t78${T78_M}/remove-defs.sh" >/dev/null
  expect_diff_bytes "T78 mutant (${T78_MODE}): …and without its guard the strip takes a changed block" "$TMP/t78-before" "$T78_SB/.zshrc"
  expect_eq "T78 mutant (${T78_MODE}): …losing the user's line" "0" "$(count_lines_equal "$T78_SB/.zshrc" "$T77_U")"
done

# THE COPY. The standalone door decides by remove.sh's copy of the two body lists; each is
# env.sh's, line for line.
for T78_FN in rc_default rc_earlier; do
  T78_A="$(fn_text "$ENV_SH" "$T78_FN")"
  expect_nonempty "T78 copies: ${T78_FN} reads out of env.sh" "$T78_A"
  expect_eq "T78 copies: remove.sh's ${T78_FN} is env.sh's, line for line" "$T78_A" "$(fn_text "$REMOVE_SH" "$T78_FN")"
done

# THE DOOR LINES FIT 100 COLUMNS, at the longest rc name and a four-digit line range.
T66_SHELL=/bin/bash
T78_SB="$(new_sandbox)"; T78_RC="$(t66_rc "$T78_SB")"
{ for _i in $(seq 1 1200); do printf 'export MY_VAR_%s=mine\n' "$_i"; done
  printf '%s\n' "$RC_START_LIT" "$PROXY_UNALIAS" "$T77_U" "$PROXY_LINE" "$RC_END_LIT"; } > "$T78_RC"
T78_OUT="$(t66_door "$T78_SB" rm-payload y claude-proxy)"
T78_LINE="$(report_row "$T78_OUT" "lines 1201 to 1205 of ~/.bashrc")"
expect_nonempty "T78 width: the changed line at lines 1201 to 1205 of ~/.bashrc was printed" "$T78_LINE"
expect_true "T78 width: …and fits 100 columns (${#T78_LINE})" test "${#T78_LINE}" -le 100
T78_SB="$(new_sandbox)"; T78_RC="$(t66_rc "$T78_SB")"; t78_plant "$T78_RC" cur
T78_LINE="$(report_row "$(t66_door "$T78_SB" rm-payload n claude-proxy)" "$T78_WARN")"
expect_nonempty "T78 width: the warning before the question was printed" "$T78_LINE"
expect_true "T78 width: …and fits 100 columns (${#T78_LINE})" test "${#T78_LINE}" -le 100
T66_SHELL=/bin/bash

finish
