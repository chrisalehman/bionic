#!/bin/bash
# tests/rc-item-2.test.sh — the rc item (`claude()` as a setup-managed item), part 2 of 2: sections 19 through 22, "wave-27 T75" to "wave-27 T78".
#
# THE SUITE IS TWO PARTS (wave-39 T38; D1, D13, REQ-3 AC-3.3). One rc-item.test.sh promised more of the suite
# bar than it should, so it runs as two suites cut at a section boundary. What the suite owns, its rules
# (every negative has a positive beside it, no awk on the marker glyphs, hermetic homes), and the fixtures,
# extractors and drivers every part shares are in tests/rc-item.prelude.sh, sourced below after the framework.
#
# Usage: bash tests/rc-item-2.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

# expect_not_contains -> expect_absent, pure rename (S1b/A-17 mapping table): same
# `case` glob semantics.
expect_same_bytes() {  # <label> <file-a> <file-b>
  if cmp -s "$2" "$3"; then ok "$1"; else no "$1" "$(diff "$2" "$3" 2>&1 | head -20)"; fi
}
expect_diff_bytes() {  # <label> <file-a> <file-b>
  if cmp -s "$2" "$3"; then no "$1" "the two files are byte-identical and should not be"; else ok "$1"; fi
}

. "$(dirname "$0")/rc-item.prelude.sh"

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
  # Wait for the door's trap to remove the staged copy (bounded at the old fixed second, 1 s).
  T75_W=0; while [ -n "$(find "$T75_SB/.tmp" -name 'bionic-rc.*' 2>/dev/null)" ] && [ "$T75_W" -lt 10 ]; do sleep 0.1; T75_W=$((T75_W + 1)); done
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
  printf '%s\n' "alias claude='echo ALIAS'" "$RC_START_LIT" "$PROXY_LINE_118" "$RC_END_LIT" 'export AFTER=1' > "$T75_RC"
  T75_ST="$(t75p_source "$T75_SH" "$T75_SB" "$T75_RC")"
  expect_absent "T75 claude() (${T75_SH}, old body under an alias): the line after the block does not run" "AFTER=1 " "$T75_ST"
  expect_ne "T75 claude() (${T75_SH}, old body under an alias): …and the rc errors on stderr" "ERR=" "${T75_ST#*|}"
done

# BYTES. Setup on an rc holding the old block (where setup wrote it, at the end) writes
# exactly the new block and no other byte; setup twice is the same bytes; remove leaves
# the rc as it was before setup.
T66_SHELL=/bin/zsh
T75_SB="$(new_sandbox)"; T75_RC="$(t66_rc "$T75_SB")"
printf '%s\n' 'export A=1' "$RC_START_LIT" "$PROXY_LINE_118" "$RC_END_LIT" > "$T75_RC"
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
expect_eq "T75 rc_get: the old one-line body is not" "not" "$(t75p_get "$PROXY_LINE_118")"
expect_eq "T75 rc_get: the 1.18.0 two-line body is not (wave-36 T1)" "not" "$(t75p_get "$PROXY_UNALIAS" "$PROXY_LINE_118")"
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
    old2)        printf '%s\n' "$PROXY_LINE_118" ;;
    old3)        printf '%s\n' "$PROXY_UNALIAS" "$PROXY_LINE_118" ;;
    old1)        printf '%s\n' "$T77_OLD1" ;;
    empty)       ;;
    old-u-below) printf '%s\n' "$PROXY_LINE_118" "$T77_U" ;;
    old-u-above) printf '%s\n' "$T77_U" "$PROXY_LINE_118" ;;
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
t77_state() { case "$1" in cur|u-*) echo written ;; old1|old2|old3|empty) echo stale ;; none) echo no ;; *) echo changed ;; esac; }
t77_last() { local n; n="$(t77_body "$1" | wc -l)"; echo $(( 3 + ${n// /} )); }  # the end marker's line
T77_ALL="cur u-above u-between u-below old3 old2 old1 empty none old-u-below old-u-above swapped edited"

# THE ONE OWNER. env.sh `rc_state` answers every shape, and the fixture's shapes are
# what this section says they are (the extractor reads the block back non-empty).
expect_eq "T77 fixture: the u-between block holds the unalias line, the user's and the function" "$((2 + PROXY_N))" "$(t66_rc_tmp="$TMP/t77-fx"; t77_plant "$t66_rc_tmp" u-between; rc_block_lines "$t66_rc_tmp" | wc -l | tr -d ' ')"
expect_eq "T77 fixture: the swapped block ends after the function and the unalias line" "$((3 + PROXY_N + 1))" "$(t77_last swapped)"
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
        expect_contains "${T77_L}: …and bionic's second" "     claude() {" "$T77_OUT"
        expect_contains "${T77_L}: …through the call" "     ${PROXY_CALL}" "$T77_OUT"
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
    t77_place "$T77_RC" "$T77_W" "$PROXY_LINE_118"
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
  printf '%s\n' "$RC_START_LIT" "$PROXY_LINE_118" "$RC_END_LIT"
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
T78_OURS="cur old3 old2 old1 empty"
T78_CHANGED="u-above u-between u-below old-u-below old-u-above edited swapped"
t78_plant() {  # <file> <shape> — T77's shapes, and `two`: two marker pairs
  if [ "$2" = two ]; then
    printf '%s\n' 'export V1=1' "$RC_START_LIT" "$PROXY_UNALIAS" "$PROXY_CALL" "$RC_END_LIT" 'export V2=2' \
      "$RC_START_LIT" "$PROXY_UNALIAS" "$PROXY_CALL" "$RC_END_LIT" > "$1"
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
expect_eq "T78 fixture: the u-above block holds the user's line first, then bionic's" \
  "$(printf '%s\n' "$T77_U" "$PROXY_UNALIAS" "$PROXY_LINE" | tr '\n' '|')" "$(t78_plant "$TMP/t78-fx" u-above; rc_block_lines "$TMP/t78-fx" | tr '\n' '|')"
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
# A run that named the block never calls the machine clean (review pass 67 P2-1).
expect_contains "T78 remove --all, no page: nothing else to remove" "nothing for bionic to remove" "$T78_OUT"
expect_absent "T78 remove --all, no page: …and the machine is not called clean" "already clean" "$T78_OUT"
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
T78_END=$((1203 + PROXY_N + 1))
T78_LINE="$(report_row "$T78_OUT" "lines 1201 to ${T78_END} of ~/.bashrc")"
expect_nonempty "T78 width: the changed line at lines 1201 to ${T78_END} of ~/.bashrc was printed" "$T78_LINE"
expect_true "T78 width: …and fits 100 columns (${#T78_LINE})" test "${#T78_LINE}" -le 100
T78_SB="$(new_sandbox)"; T78_RC="$(t66_rc "$T78_SB")"; t78_plant "$T78_RC" cur
T78_LINE="$(report_row "$(t66_door "$T78_SB" rm-payload n claude-proxy)" "$T78_WARN")"
expect_nonempty "T78 width: the warning before the question was printed" "$T78_LINE"
expect_true "T78 width: …and fits 100 columns (${#T78_LINE})" test "${#T78_LINE}" -le 100
T66_SHELL=/bin/bash

finish
