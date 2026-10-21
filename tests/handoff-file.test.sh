#!/bin/bash
# Tests for `hooks/session-poker.sh handoff [<purpose>]` and `resume <file>`: the handoff document.
#
# ONE DOCUMENT, WITH OR WITHOUT A RUN. `handoff` writes one self-contained file, <date>-<slug>.md in the
# handoffs folder of the project's docs record, whether or not the session is bound to a run, and creates the
# project's bionic folder with its ignore file (the literal `*`) when the project has none. The kind line, then
# the title line, then ten sections in order: Summary (doing, learned, open, first), Goal, State, Findings,
# Decisions, Ruled out, Open, Suggested skills, Next, Resume. State is computed: branch, head, uncommitted files,
# running processes with their logs, live agents with their briefs and progress files, and, bound, the plan, step,
# open tasks and Patrol. Every other section is composed by the session and read on the verb's stdin: a Finding
# with no source gets `unverified`, a secret is redacted, a copied block is left out, and an empty section is one
# line. There is no safe-to-clear line: the source session is disposable. Bound, the plan's `## Handoff` points at
# the file and the last line is `/bionic:canonical-sdlc <path>`; with no run, it says to read the file and do Next 1.
#
# Sections: §NO-RUN §ONE-LINE §SECTIONS §STATE §PORTABLE §POINTER §CLOSED §READERS §RESUME §POINTER-AGREE.
#
# FIXTURE FIDELITY (HERMETIC). The session-poker prelude's sandbox, pins and gate-admitted plan (`s42_plan`), one
# repository per world; a no-run world is a bare `git init` with no bionic folder at all. A running process is a
# real process whose command line is the detached shim's (`booked.sh --run-log <log>`), the rule `run_live`
# reads; a landing in flight is a real process carried by a `ready` event, the rule lib/slots.sh reads. The
# composed sections are a file on the verb's stdin, as the handoff skill pipes them.
#
# THE CLOCK IS PINNED. Now is BIONIC_NOW_EPOCH, the poker's seam (sitrep_now): the file's date, its title and its
# `written:` instant all read it.
#
# ANTI-VACUITY. Every absence sits beside a positive read through the same extractor on the same file.
#
# THE SEAM, for RED evidence against a mutated copy without touching the shipped file:
#   HANDOFF_POKER_UNDER_TEST=/path/to/mutant.sh bash tests/handoff-file.test.sh
#
# Usage: bash tests/handoff-file.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/lib/live-answer.sh"

POKER="${HANDOFF_POKER_UNDER_TEST:-${BIONIC_HOOKS_DIR}/session-poker.sh}"
S46_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/proof.sh"
. "$(dirname "$0")/session-poker.prelude.sh"
POKE_BOUND=180
export TZ=America/Los_Angeles

HF_PIDS=""
trap 'for _p in $HF_PIDS; do kill "$_p" 2>/dev/null; done; cleanup' EXIT

HF_NOW=1791324000     # 2026-10-06T22:00:00Z = Tuesday 3:00 PM PDT, the pinned now
export BIONIC_NOW_EPOCH="$HF_NOW"
HF_ISO="2026-10-06T22:00:00Z"
HF_HOME=".bionic/docs/record/handoffs"
HF_DOOR="$HF_HOME/2026-10-06-wave-01-fixture.md"
HF_PLAN_REL=".bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
HF_LEDGER_REL=".bionic/docs/record/wave-01-fixture/design-ledger.md"
HF_HEADS="Summary,Goal,State,Findings,Decisions,Ruled out,Open,Suggested skills,Next,Resume"

# ---------- extractors ----------
HF_HEAD_AWK='BEGIN { n = split("Summary,Goal,State,Findings,Decisions,Ruled out,Open,Suggested skills,Next,Resume", h, ",")
                     for (i = 1; i <= n; i++) H[h[i]] = 1 }'
hf_heads() {  # <file> -> the section headings it holds, in order, comma-joined
  awk "$HF_HEAD_AWK"' ($0 in H) { out = out (out == "" ? "" : ",") $0 } END { print out }' "$1" 2>/dev/null
}
hf_bare() {  # <file> -> how many headings stand over nothing (a blank line, another heading or the end next)
  awk "$HF_HEAD_AWK"' { l[NR] = $0 } END { c = 0
    for (i = 1; i <= NR; i++) if ((l[i] in H) && (i == NR || l[i + 1] == "" || (l[i + 1] in H))) c++
    print c }' "$1" 2>/dev/null
}
hf_unfold() {  # <file> -> its lines with every fold joined back: a line opening on spaces that is no `  - ` item continues the one above
  awk 'NR > 1 && /^ / && !/^  - / { t = $0; sub(/^ +/, "", t); buf = buf " " t; next } { if (NR > 1) print buf; buf = $0 } END { if (NR) print buf }' "$1" 2>/dev/null
}
hf_sec() {  # <file> <heading> -> the lines under that heading, unfolded, up to the blank line that ends it
  hf_unfold "$1" | awk -v h="$2" '$0 == h { f = 1; next } f && $0 == "" { exit } f { print }'
}
hf_label() {  # <file> <label> -> the first line that starts `<label>: `, unfolded
  hf_unfold "$1" | awk -v k="$2: " 'index($0, k) == 1 { print; exit }'
}
hf_wide() {  # <file> -> how many of its lines are wider than 92 columns (a UTF-8 character is one)
  LC_ALL=C awk '{ t = $0; n = gsub(/[\200-\277]/, "", t); if (length($0) - n > 92) c++ } END { print c + 0 }' "$1" 2>/dev/null
}
hf_section() {  # <plan> -> the lines of ## Handoff, the heading excluded
  awk '/^```/ { f = !f } !f && /^## / { h = ($0 ~ /^## Handoff[ \t]*$/); next } h { print }' "$1"
}
hf_outside() {  # <plan> -> every line outside ## Handoff
  awk '/^```/ { f = !f } !f && /^## / { h = ($0 ~ /^## Handoff[ \t]*$/) } !h { print }' "$1"
}
hf_iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
hf_ev() { mkdir -p "${HF_REC%/*}"; printf 'line/v1|%s\n' "$1" >> "$HF_REC"; }
hf_live() {  # -> HF_CARRIER, a live process's `<pid>:<start>` (lib/slots.sh's rule); its pid in HF_PID
  tail -f /dev/null & HF_PID=$!
  HF_PIDS="$HF_PIDS $HF_PID"
  local s; s="$(LC_ALL=C TZ=UTC0 ps -o lstart= -p "$HF_PID" 2>/dev/null)"
  # shellcheck disable=SC2086
  set -- $s
  HF_CARRIER="$HF_PID:$*"
}
hf_shim() {  # <repo> <run id> -> a live process the runs folder records as running, as the detached shim leaves it; HF_SHIM its pid
  local d; d="$(cd "$1" && pwd -P)/.bionic/tmp/runs"
  mkdir -p "$d"; : > "$d/$2.log"
  ( exec -a "booked.sh --run-log $d/$2.log" sleep 600 ) &
  HF_SHIM=$!; HF_PIDS="$HF_PIDS $HF_SHIM"
  printf '%s\n' "$HF_SHIM" > "$d/$2.log.pid"
}
hf_poke() {  # <repo> <stdin file> <args...> -> OUT, RC: the poker with that file on its stdin; HF_NOKEY=1 drops the session key
  local repo="$1" in="$2" p i=0; shift 2
  if [ "${HF_NOKEY:-0}" = 1 ]; then
    ( cd "$repo" && exec env -u CLAUDE_CODE_SESSION_ID "${POKE_BASH:-bash}" "$POKER" "$@" ) < "$in" > "$TMPROOT/hf-poke.out" 2>&1 &
  else
    ( cd "$repo" && exec env CLAUDE_CODE_SESSION_ID="$SID" "${POKE_BASH:-bash}" "$POKER" "$@" ) < "$in" > "$TMPROOT/hf-poke.out" 2>&1 &
  fi
  p=$!
  while kill -0 "$p" 2>/dev/null && [ "$i" -lt $(( POKE_BOUND * 10 )) ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$p" 2>/dev/null; then kill -9 "$p" 2>/dev/null; wait "$p" 2>/dev/null; RC=124
  else wait "$p" 2>/dev/null; RC=$?; fi
  OUT="$(cat "$TMPROOT/hf-poke.out")"
}

# ---------- the composed sections, as the skill pipes them ----------
HF_LONG="The closed index is never cached, so a warm call still pays for the whole scan of the tree text and the declarations on every call, twelve seconds of it measured warm — time-keys-head.log"
HF_C="$TMPROOT/hf-compose.md"
cat > "$HF_C" <<COMPOSE
Summary
- Doing: finding out why the judge takes 52 s on a one-line change.
- Learned: it derives the same closure three times per call.
- Open: whether an incremental owed test is sound.
- First: rerun the timing script against a cached closure.

Goal
- "Why does current 7 take 52 s on a one-line library change, and what would under 5 s take?" (Dana Fixture, 3:19 PM)

State
- typed by hand: this line is not computed

Findings
- The walk is _proof_walk — payload/scripts/lib/proof.sh:1248
- Each key derivation runs the closed scan three times per cold call
- $HF_LONG
- Deriving once per commit saves about 22 s — unverified

Decisions
- Dana Fixture ruled "a reading, not a change" (2026-10-06 3:20 PM)

Ruled out

Open
- hypothesis: caching the closed index per commit brings a warm call under 1 s. Not tried.

Suggested skills
- bionic:map-instrument-narrow, before instrumenting the judge

Next
- \`bash scratch/time-keys.sh\` after caching the closure
- read judge-1.log beside it
COMPOSE
HF_EMPTY="$TMPROOT/hf-empty.md"; : > "$HF_EMPTY"

# ---------- the bound world ----------
#
# hf_world <label> [roster yes|no] -> HF_R (repo), HF_P (plan), HF_F (the handoff file), HF_REC (its landing record),
# HF_INT/HF_WORK (the two heads). The frontmatter branch keys over real branches, two landed lines, two proof lines,
# active rows T2 and T3 and a pending T6 with a worktree, a Not Doing; the bionic folder excluded from git, as a
# project ignores it; with `roster yes`, w-T2's finished run, its progress file named and its brief on disk.
hf_world() {
  local label="$1" roster="${2:-yes}" rd
  HF_R="$(make_repo "hf-$label")"; ( cd "$HF_R" && git commit -q --allow-empty -m init )
  printf '.bionic/\n' >> "$HF_R/.git/info/exclude"
  git -C "$HF_R" config user.name "Dana Fixture"
  git -C "$HF_R" branch -f trunk HEAD
  git -C "$HF_R" commit -q --allow-empty -m "work"
  git -C "$HF_R" branch -f wave/01-fixture HEAD
  HF_INT="$(git -C "$HF_R" rev-parse trunk)"
  HF_WORK="$(git -C "$HF_R" rev-parse wave/01-fixture)"
  HF_P="$(s42_plan "$HF_R" 4)"
  awk -v w="$HF_WORK" '
    NR == 1 && $0 == "---" { print; print "working-branch: wave/01-fixture"; print "integration-branch: trunk"; next }
    /^approved-by:/ { print; print "proved: kind=floor head=" w " at=2026-10-08T11:00:00Z evidence=record/old-floor.log"
                      print "proved: kind=review head=" w " at=2026-10-08T12:30:00Z evidence=record/last-review.md"; next }
    /^- T5: pending dispatch/ { print "- T4: landed 2222222222222222222222222222222222222222 2026-10-08T10:30:00Z"
                                print "- T3: landed 1111111111111111111111111111111111111111 2026-10-08T09:00:00Z"; print; next }
    /^\| T2 \| 4 \| build \|/ { sub(/\| implementor \|/, "| w-T2 |"); print
                               print "| T3 | 4 | build | the third build | — | — | 30 | REQ-1 | c.sh | .worktrees/01-T3 | abc1234 | active |"
                               print "| T6 | 4 | build | the sixth build | — | — | 30 | REQ-1 | d.sh | .worktrees/01-T6 | abc1234 | pending |"; next }
    { print }
    END { print "\n## Not Doing\n\n- nothing, in this fixture" }' "$HF_P" > "$HF_P.hf" && mv "$HF_P.hf" "$HF_P"
  if [ "$roster" = yes ]; then
    rd="$HF_R/.bionic/tmp/runs"; mkdir -p "$rd"; : > "$rd/w-T2-x.test.sh.log"
    roster_row_fixture session="$SID" name=w-T2 agent_id=a-w-T2 subagent_type=implementor \
      progress=.bionic/docs/record/wave-01-fixture/T2.progress.md \
      run_log="$rd/w-T2-x.test.sh.log" run_cmd='tests/run.sh --only x.test.sh' run_rc=0 >> "$(roster_of "$HF_R")"
    mkdir -p "$HF_R/.bionic/docs/record/wave-01-fixture/briefs"
    printf '# the brief for T2\n' > "$HF_R/.bionic/docs/record/wave-01-fixture/briefs/T2.md"
  fi
  HF_F="$HF_R/$HF_DOOR"
  HF_REC="$HF_R/.bionic/docs/record/wave-01-fixture/landing-proofs.log"
  s42_snap "$HF_R" "$HF_P"
}

# ============================================================
section "§NO-RUN: with no run bound, handoff writes the document under the handoffs folder, creating the bionic folder and its ignore file; it never refuses for want of a plan"
# ============================================================
HF_NR="$TMPROOT/hf-norun"; mkdir -p "$HF_NR"
( cd "$HF_NR" && git init -q . && git config user.name "Dana Fixture" && git config user.email d@example.com \
  && printf 'one\n' > a.txt && git add a.txt && git commit -qm "the first file" && printf 'two\n' >> a.txt && : > notes.txt )
HF_NR_BR="$(git -C "$HF_NR" symbolic-ref --short HEAD)"
HF_NR_F="$HF_NR/$HF_HOME/2026-10-06-$HF_NR_BR.md"
expect_false "N0 precondition: the project has no bionic folder" test -e "$HF_NR/.bionic"
HF_NOKEY=1 hf_poke "$HF_NR" "$HF_C" handoff
expect_eq "N1 handoff with no session key and no bionic folder exits 0" "0" "$RC"
expect_absent "N1b …and refuses nothing" "REFUSED" "$OUT"
expect_true "N1c …writing <date>-<branch>.md under the handoffs folder" test -s "$HF_NR_F"
expect_eq "N2 the bionic folder it created carries the ignore file, the literal *" "*" "$(cat "$HF_NR/.bionic/.gitignore" 2>/dev/null)"
expect_true "N2b …so git ignores the handoff" git -C "$HF_NR" check-ignore -q "$HF_NR_F"
HF_NR_ST="$(git -C "$HF_NR" status --porcelain)"
expect_contains "N2c precondition: git status lists the project's own change" "a.txt" "$HF_NR_ST"
expect_absent "N2d …and nothing of the bionic folder (N2c read the same status)" ".bionic" "$HF_NR_ST"
expect_absent "N3 it prints no line naming the file it wrote (N3b reads the resume line through the same output)" "written to" "$OUT"
expect_eq "N3b …the last line says how to resume with no run: read the file, then Next 1" \
  "Read $HF_HOME/2026-10-06-$HF_NR_BR.md whole, then do Next 1." "$(tail -1 "$HF_NR_F")"
expect_eq "N3c …and prints only the resume line" "1|$(tail -1 "$HF_NR_F")" \
  "$(printf '%s\n' "$OUT" | grep -c . | tr -d ' ')|$(printf '%s\n' "$OUT" | tail -1)"
rm -rf "$HF_NR/.bionic"
hf_poke "$HF_NR" "$HF_C" handoff
expect_eq "N4 with a session key the project never engaged: exits 0" "0" "$RC"
expect_absent "N4b …and is not the NOT-ENGAGED no-op" "NOT-ENGAGED" "$OUT"
expect_true "N4c …the file is written" test -s "$HF_NR_F"
HF_EU="$(make_repo hf-engaged-unbound)"; ( cd "$HF_EU" && git commit -q --allow-empty -m init )
HF_EU_F="$HF_EU/$HF_HOME/2026-10-06-$(git -C "$HF_EU" symbolic-ref --short HEAD).md"
hf_poke "$HF_EU" "$HF_C" handoff
expect_eq "N5 an engaged session bound to no run: exits 0" "0" "$RC"
expect_absent "N5b …and is not refused for want of a plan" "REFUSED" "$OUT"
expect_true "N5c …the file is written" test -s "$HF_EU_F"
expect_true "N6 a bionic folder git does not ignore: the handoffs folder gets its own ignore file, so the file is ignored" \
  git -C "$HF_EU" check-ignore -q "$HF_EU_F"
expect_eq "N6b …the literal *" "*" "$(cat "$HF_EU/$HF_HOME/.gitignore" 2>/dev/null)"

# ============================================================
section "§ONE-LINE: on success the verb prints the resume line alone and nothing on stderr; the handoff skill ends on that line in a fence and quotes nothing"
# ============================================================
# A reader sees one line. The verb's stdout and stderr are captured apart here, so a second line on either stream is
# caught where hf_poke's merged capture would only count it.
hf_split() {  # <repo> <stdin file> <args...> -> OL_OUT, OL_ERR, OL_RC: the poker's stdout and stderr, apart
  local repo="$1" in="$2"; shift 2
  OL_OUT="$( cd "$repo" && env CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" "$@" < "$in" 2> "$TMPROOT/hf-ol.err" )"; OL_RC=$?
  OL_ERR="$(cat "$TMPROOT/hf-ol.err")"
}
hf_world one-line no
hf_split "$HF_R" "$HF_C" handoff
expect_eq "OL-1 bound: the verb exits 0 and its stdout is exactly the resume line, the file's last line, with nothing on stderr" \
  "0|/bionic:canonical-sdlc $HF_DOOR|" "$OL_RC|$OL_OUT|$OL_ERR"
expect_eq "OL-1b …the line is the written file's last line (the read is not empty)" "/bionic:canonical-sdlc $HF_DOOR" "$(tail -1 "$HF_F")"
expect_eq "OL-1c …and stdout holds that one line only" "1" "$(printf '%s\n' "$OL_OUT" | grep -c . | tr -d ' ')"
HF_OL_NR="$TMPROOT/hf-ol-norun"; mkdir -p "$HF_OL_NR"
( cd "$HF_OL_NR" && git init -q . && git config user.name "Dana Fixture" && git config user.email d@example.com \
  && printf 'one\n' > a.txt && git add a.txt && git commit -qm "the first file" )
HF_OL_BR="$(git -C "$HF_OL_NR" symbolic-ref --short HEAD)"
HF_OL_F="$HF_OL_NR/$HF_HOME/2026-10-06-$HF_OL_BR.md"
hf_split "$HF_OL_NR" "$HF_C" handoff
expect_eq "OL-2 unbound: stdout is exactly Read <path> whole, then do Next 1., with nothing on stderr" \
  "0|Read $HF_HOME/2026-10-06-$HF_OL_BR.md whole, then do Next 1.|" "$OL_RC|$OL_OUT|$OL_ERR"
expect_eq "OL-2b …the line is the written file's last line (the read is not empty)" \
  "Read $HF_HOME/2026-10-06-$HF_OL_BR.md whole, then do Next 1." "$(tail -1 "$HF_OL_F")"
expect_eq "OL-2c …and stdout holds that one line only" "1" "$(printf '%s\n' "$OL_OUT" | grep -c . | tr -d ' ')"
# The skill is read where it ships: the real file, which payload/skills/handoff links to.
OL_SKILL="${BIONIC_HOOKS_DIR}/../skills/handoff/SKILL.md"
# ol_last_step <skill> -> the lines of the last numbered step under ## The steps, up to the next heading.
ol_last_step() {
  awk '/^## The steps/ { s = 1; next } s && /^## / { exit } s && /^[0-9]+\. / { buf = ""; } s { buf = buf $0 "\n" } END { printf "%s", buf }' "$1"
}
# ol_fence_body <text on stdin> -> the lines inside the first fenced block.
ol_fence_body() { awk '/^[ \t]*```/ { f = !f; if (!f) exit; next } f { print }'; }
expect_true "OL-3 precondition: the skill is read and holds its steps" /usr/bin/grep -q '^## The steps' "$OL_SKILL"
expect_eq "OL-3 no step tells the model to quote the verb" "0" "$(/usr/bin/grep -c 'Quote the verb' "$OL_SKILL")"
expect_eq "OL-3b …nor names the written-to line the verb no longer prints" "0" "$(/usr/bin/grep -c 'written to' "$OL_SKILL")"
OL_LASTSTEP="$(ol_last_step "$OL_SKILL")"
expect_contains "OL-3c precondition: the last step is read (it is the one that ends the session)" "/bionic:canonical-sdlc" "$OL_LASTSTEP"
expect_eq "OL-3d the last step ends on a fenced block holding the resume line" "/bionic:canonical-sdlc <path>" \
  "$(printf '%s' "$OL_LASTSTEP" | ol_fence_body | /usr/bin/grep -F '/bionic:canonical-sdlc' | sed 's/^[[:space:]]*//' | head -1)"
expect_eq "OL-3e …and the step's last non-blank line closes that fence" '```' "$(printf '%s' "$OL_LASTSTEP" | /usr/bin/grep . | tail -1 | tr -d ' ')"


# ============================================================
section "§SECTIONS: the kind line, the title, then the ten sections in order; an empty section is one line; the page folds at 92 columns"
# ============================================================
expect_eq "S1 line 1 is the kind line" "bionic-handoff/v1" "$(sed -n 1p "$HF_NR_F")"
expect_eq "S3 the sections, in order" "$HF_HEADS" "$(hf_heads "$HF_NR_F")"
expect_eq "S4 no heading stands over nothing (S3 read every heading)" "0" "$(hf_bare "$HF_NR_F")"
grep -v '^- none\.$' "$HF_NR_F" > "$TMPROOT/hf-cut"
expect_ne "S4b anti-vacuity: the bare-heading count tells a file with the empty section's line cut" "0" "$(hf_bare "$TMPROOT/hf-cut")"
expect_eq "S5 an empty Ruled out is one line" "- none." "$(hf_sec "$HF_NR_F" "Ruled out")"
expect_eq "S9 Resume is the last section and the last line" "Read $HF_HOME/2026-10-06-$HF_NR_BR.md whole, then do Next 1." \
  "$(hf_sec "$HF_NR_F" Resume)"
expect_contains "S10 precondition: the long finding's last words are in the file" "time-keys-head.log" "$(cat "$HF_NR_F")"
expect_eq "S11 State is computed: its written: line is the instant" "written: $HF_ISO" "$(hf_label "$HF_NR_F" written)"
expect_absent "S11b …and a composed State line is not in the file (S11 read the same file)" "not computed" "$(cat "$HF_NR_F")"
expect_eq "S11c State: the branch" "branch: $HF_NR_BR" "$(hf_label "$HF_NR_F" branch)"
expect_eq "S11d State: the head and its subject" "head: $(git -C "$HF_NR" rev-parse HEAD) the first file" "$(hf_label "$HF_NR_F" head)"
expect_eq "S11e State: the uncommitted files by name" "uncommitted (2):
  - a.txt · modified
  - notes.txt · untracked" "$(hf_sec "$HF_NR_F" State | awk '/^uncommitted/ { f = 1 } f && /^[a-z]/ && !/^uncommitted/ { exit } f')"
expect_eq "S11f State: nothing running" "running: none" "$(hf_label "$HF_NR_F" running)"
expect_absent "S11g …and no plan line with no run (S11c read the same extractor)" "plan: " "$(hf_label "$HF_NR_F" plan)"
hf_poke "$HF_NR" "$HF_EMPTY" handoff
expect_eq "S12 a handoff with nothing composed exits 0" "0" "$RC"
expect_eq "S12b …every section still stands, in order" "$HF_HEADS" "$(hf_heads "$HF_NR_F")"
expect_eq "S12c …none of them bare" "0" "$(hf_bare "$HF_NR_F")"

# ============================================================
section "§STATE: bound, every State fact is computed: the tree, what runs, the agents with their briefs and progress files, the plan, step, open tasks and Patrol; a Finding with no source says unverified"
# ============================================================
hf_world state
( cd "$HF_R" && printf 'one\n' > tracked.txt && git add tracked.txt && git commit -qm "the tracked file" \
  && printf 'two\n' >> tracked.txt && : > dirty.txt )
mkdir -p "${HF_R}/${HF_LEDGER_REL%/*}"
printf '# design ledger — wave-01-fixture\n\n## Δ0 — D1 ruled "1" (Dana Fixture 2026-10-05): the frame holds\n' > "$HF_R/$HF_LEDGER_REL"
hf_shim "$HF_R" w-main-x.test.sh
hf_poke "$HF_R" "$HF_C" handoff
expect_eq "T1 handoff on a bound run exits 0" "0" "$RC"
expect_true "T1b …writing <date>-<the run's slug>.md under the handoffs folder" test -s "$HF_F"
expect_eq "T1c the title names the run" "Handoff · hf-state · Tuesday 3:00 PM · wave-01-fixture" "$(sed -n 2p "$HF_F")"
expect_eq "T1d the sections, in order" "$HF_HEADS" "$(hf_heads "$HF_F")"
expect_eq "T2 branch: the branch checked out" "branch: $(git -C "$HF_R" symbolic-ref --short HEAD)" "$(hf_label "$HF_F" branch)"
expect_eq "T2b head: its commit and subject" "head: $(git -C "$HF_R" rev-parse HEAD) the tracked file" "$(hf_label "$HF_F" head)"
expect_contains "T3 uncommitted: the modified file by name" "  - tracked.txt · modified" "$(hf_sec "$HF_F" State)"
expect_contains "T3b …and the untracked one" "  - dirty.txt · untracked" "$(hf_sec "$HF_F" State)"
expect_eq "T3c …counted" "uncommitted (2):" "$(hf_sec "$HF_F" State | grep '^uncommitted')"
expect_contains "T4 running: the live run with its pid and its log" \
  "  - w-main-x.test.sh · pid $HF_SHIM · log .bionic/tmp/runs/w-main-x.test.sh.log" "$(hf_sec "$HF_F" State)"
expect_regex "T5 agents: counted, with how the count was verified" '^agents \(1\): ' "$(hf_sec "$HF_F" State | grep '^agents ')"
expect_contains "T5b …each with its type, its run, its brief and its progress file" \
  "  - w-T2 · implementor · FINISHED rc=0 run=w-T2-x.test.sh · brief .bionic/docs/record/wave-01-fixture/briefs/T2.md · progress .bionic/docs/record/wave-01-fixture/T2.progress.md" \
  "$(hf_sec "$HF_F" State)"
expect_eq "T6 plan: the bound plan, project-root-relative" "plan: $HF_PLAN_REL" "$(hf_label "$HF_F" plan)"
expect_eq "T6b step: the plan's current:" "step: 4" "$(hf_label "$HF_F" step)"
expect_eq "T6c working branch: the run's branch and its head" "working branch: wave/01-fixture @ $HF_WORK" "$(hf_label "$HF_F" 'working branch')"
expect_eq "T6d integration: the integration branch and its head" "integration: trunk @ $HF_INT" "$(hf_label "$HF_F" integration)"
expect_eq "T6e open tasks: the count" "open tasks (3):" "$(hf_sec "$HF_F" State | grep '^open tasks')"
expect_contains "T6f …the active row with its agent, worktree and status" "  - T2 · w-T2 · 01-T2 · active" "$(hf_sec "$HF_F" State)"
expect_contains "T6g …a pending row with a worktree" "  - T6 · — · .worktrees/01-T6 · pending" "$(hf_sec "$HF_F" State)"
expect_absent "T6h …not a pending row with none (T6f read the same section)" "  - T5 ·" "$(hf_sec "$HF_F" State)"
expect_eq "T6i patrol: not armed (no stamp for this session)" "patrol: not armed" "$(hf_label "$HF_F" patrol)"
HF_FD="$(hf_sec "$HF_F" Findings)"
expect_contains "T7 a Finding with its source keeps it" "- The walk is _proof_walk — payload/scripts/lib/proof.sh:1248" "$HF_FD"
expect_absent "T7d …never twice (T7c read the same section)" "unverified — unverified" "$HF_FD"
expect_eq "T9 the last line is the door that resumes the run" "/bionic:canonical-sdlc $HF_DOOR" "$(tail -1 "$HF_F")"
kill "$HF_SHIM" 2>/dev/null; wait "$HF_SHIM" 2>/dev/null
# A landing in flight is a fact the next session acts on, never a wait: its ready carrier is a live process.
hf_live
hf_ev "ev=ready|row=T2|name=w-T2|commit=$HF_WORK|branch=wt/01-T2|tree=$(cd "$HF_R" && pwd -P)/01-T2|suites=a.test.sh|debt=-|carrier=$HF_CARRIER|at=$(hf_iso $((HF_NOW - 720)))"
hf_poke "$HF_R" "$HF_C" handoff
expect_eq "T10 a landing in flight: handoff exits 0" "0" "$RC"
expect_eq "T10c …and the run that ended is no longer running (T4's extractor)" "running (1):" "$(hf_sec "$HF_F" State | grep '^running')"
expect_absent "T10d …no wait line (T10b read the same file)" "wait " "$(grep -E '^wait [0-9]+ minutes' "$HF_F")"
kill "$HF_PID" 2>/dev/null; wait "$HF_PID" 2>/dev/null

# ============================================================
section "§HEAD: the head is the title, bound the run's status line, then Blocked on you: yes or no and one line per open ask with what it holds"
# ============================================================
# The asks are the run's register, opened through lib/owed.sh's own opener; the status line is `sitrep --line`'s.
# fails-when: an ask open on the run is missing from the head, or the head says nothing is blocked while one is.
hf_poke "$HF_R" "$HF_C" handoff
expect_eq "HD1 bound, nothing owed: the title, the run's status line, Blocked on you: no, then the blank line" "yes|Blocked on you: no|" \
  "$(sed -n 3p "$HF_F" | /usr/bin/grep -qE '^[0-9]+ of [0-9]+ tasks · owed: 0 · close ' && echo yes)|$(sed -n 4p "$HF_F")|$(sed -n 5p "$HF_F")"
( . "${S46_LIB%/*}/owed.sh" && OWED_ROOT="$HF_R" OWED_SID="$SID" OWED_PLAN="$HF_P" \
    owed_open approve:release "Approve release" "poker: approve release — reply with your words" )
hf_poke "$HF_R" "$HF_C" handoff
expect_eq "HD2 an ask open on the run: owed counts it, Blocked on you: yes, and its line says what it is and what it holds" \
  "owed: 1|Blocked on you: yes|yes" \
  "$(sed -n 3p "$HF_F" | /usr/bin/grep -oE 'owed: [0-9]+')|$(sed -n 4p "$HF_F")|$(sed -n 5p "$HF_F" | /usr/bin/grep -qE '^- Approve release — holds [^ ]' && echo yes)"
expect_eq "HD3 with no run, the head is the title and Blocked on you: no" "Blocked on you: no|" "$(sed -n 3p "$HF_NR_F")|$(sed -n 4p "$HF_NR_F")"

# ============================================================
section "§PORTABLE: an argument tailors the document; secrets and addresses are redacted; a copied block is left out for its path; no safe-to-clear line exists"
# ============================================================
HF_NOKEY=1 hf_poke "$HF_NR" "$HF_C" handoff 'measure the judge cold and warm'
HF_PF="$HF_NR/$HF_HOME/2026-10-06-measure-the-judge-cold-and-warm.md"
expect_eq "P1 handoff <purpose> exits 0" "0" "$RC"
expect_true "P1b …the file is named for the purpose" test -s "$HF_PF"
HF_TOK_GH="ghp_$(printf 'A%.0s' 1 2 3 4 5 6 7 8 9 10)0123456789abcdefghij"
HF_TOK_AN="sk-ant-api03-$(printf 'Bx%.0s' 1 2 3 4 5 6 7 8 9 10 11 12)"
HF_TOK_AWS="AKIA$(printf 'Q%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)"
HF_SPEC_LINE="One handoff shape from two sources, the machine facts plus the human lines."
HF_C2="$TMPROOT/hf-compose-secrets.md"
{ cat "$HF_C"
  printf '\nFindings\n'
  printf -- '- The key %s opened the API — payload/x.sh\n' "$HF_TOK_GH"
  printf -- '- The model key was %s and the cloud key %s — unverified\n' "$HF_TOK_AN" "$HF_TOK_AWS"
  printf -- '- The fixture logs in with password=hunter2hunter2 as dana@example.com — tests/x.sh\n'
  printf -- '- The spec says how the shape is settled — .bionic/docs/specs/x.requirements.md\n'
  printf '```text\nREQ-11 — A handoff for any session\n%s\n```\n' "$HF_SPEC_LINE"
} > "$HF_C2"
HF_NOKEY=1 hf_poke "$HF_NR" "$HF_C2" handoff 'measure the judge cold and warm'
HF_PALL="$(cat "$HF_PF")"
expect_eq "P2 precondition: handoff exits 0" "0" "$RC"
expect_absent "P2c …its text is gone (P2b read the same file)" "$HF_TOK_GH" "$HF_PALL"
expect_absent "P2d …the model key's too" "$HF_TOK_AN" "$HF_PALL"
expect_absent "P2e …the cloud key's too" "$HF_TOK_AWS" "$HF_PALL"
expect_absent "P2f …a password's" "hunter2hunter2" "$HF_PALL"
expect_absent "P2g …and a mail address" "dana@example.com" "$HF_PALL"
expect_contains "P2h …the address said as redacted" "[address redacted]" "$HF_PALL"
expect_eq "P3d a second Findings block joins the first: one heading, in order" "$HF_HEADS" "$(hf_heads "$HF_PF")"
expect_eq "P4 precondition: the last line is the Resume line" "Read $HF_HOME/2026-10-06-measure-the-judge-cold-and-warm.md whole, then do Next 1." \
  "$(tail -1 "$HF_PF")"
expect_absent "P4b no safe-to-clear line (P4 read the same file)" "safe to clear" "$HF_PALL"
expect_absent "P4c …and no wait line" "minutes —" "$HF_PALL"
HF_NFILES="$(ls "$HF_NR/$HF_HOME" | wc -l | tr -d ' ')"
HF_NOKEY=1 hf_poke "$HF_NR" "$HF_C" handoff --mid-flight 'the old human line'
expect_eq "P5 a retired human-line flag is the usage error, exit 2" "2" "$RC"
expect_contains "P5b …the usage error names stdin for the sections" "stdin" "$OUT"
expect_eq "P5c …and nothing is written" "$HF_NFILES" "$(ls "$HF_NR/$HF_HOME" | wc -l | tr -d ' ')"

# ============================================================
section "§POINTER: bound, the plan's ## Handoff is the heading and one line handoff: <path> written <local time>"
# ============================================================
HF_SEC="$(hf_section "$HF_P")"
expect_regex "PT1b …the pointer to the handoffs file, in handoff_local_time's format" \
  "^handoff: $(printf '%s' "$HF_DOOR" | sed 's/\./\\./g') written [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} P[DS]T$" \
  "$(printf '%s\n' "$HF_SEC" | grep .)"
expect_eq "PT2b …placed before ## Not Doing" "## Not Doing" "$(awk '/^## Handoff[ \t]*$/ { f = 1; next } f && /^## / { print; exit }' "$HF_P")"
s34_gate "$HF_R"
expect_eq "PT3 the plan with the pointer is admitted by the real gate" "0" "$GATE_RC"
s42_snap "$HF_R" "$HF_P"
hf_poke "$HF_R" "$HF_C" handoff 'the next session reviews T2'
expect_eq "PT4 a bound handoff with a purpose exits 0" "0" "$RC"
expect_eq "PT4d …the rest of the plan is as it was" "$(hf_outside "$TMPROOT/s42-before")" "$(hf_outside "$HF_P")"
# The document first, always: a plan the gate refuses (its requirements file gone) costs the pointer, never the file.
hf_world pointer-refused no
rm -f "$HF_R/.bionic/docs/specs/epic-99-fixture/wave-01-fixture.requirements.md"
hf_poke "$HF_R" "$HF_C" handoff
expect_eq "PT5 a plan the gate refuses: exit 0, the document written whole, the resume line then one line saying the pointer was not written, the plan unchanged" \
  "0|$HF_HEADS|/bionic:canonical-sdlc $HF_DOOR|2|yes|yes" \
  "$RC|$(hf_heads "$HF_F")|$(tail -1 "$HF_F")|$(printf '%s\n' "$OUT" | grep -c . | tr -d ' ')|$(printf '%s\n' "$OUT" | tail -1 | grep -q "pointer was not written" && echo yes || echo no)|$(cmp -s "$TMPROOT/s42-before" "$HF_P" && echo yes || echo no)"

# ============================================================
section "§CLOSED: handoff on a delivered or parked plan writes the same document, its State saying where the run closed; the pointer stays"
# ============================================================
hf_close() {  # <step-9 line> -> the plan at current: 9 with that line, snapped
  HF_S9="$1" awk '
    /^current: 4$/ { print "current: 9"; next }
    /^- T1: landed at record\/T1.md$/ { print ENVIRON["HF_S9"]; print; next }
    { print }' "$HF_P" > "$HF_P.d" && mv "$HF_P.d" "$HF_P"
  s42_snap "$HF_R" "$HF_P"
}
hf_world closed
poke "$HF_R" handoff
expect_eq "D0 precondition: the open handoff is written" "0" "$RC"
hf_close "- Step 9: delivered: 2026-10-08T13:00Z wave-01-fixture 9.9.9 — closed by close-out.sh"
hf_poke "$HF_R" "$HF_C" handoff
expect_eq "D1 handoff on a delivered plan exits 0" "0" "$RC"
expect_absent "D1b …and does not refuse" "REFUSED" "$OUT"
expect_eq "D2 the sections, in order" "$HF_HEADS" "$(hf_heads "$HF_F")"
expect_eq "D2c …and where its continuation is" "continuation: record/wave-01-fixture/continuation.md" "$(hf_label "$HF_F" continuation)"
expect_eq "D2e the last line is still the door" "/bionic:canonical-sdlc $HF_DOOR" "$(tail -1 "$HF_F")"
expect_contains "D3 the plan keeps the pointer" "handoff: $HF_DOOR written " "$(hf_section "$HF_P")"

# The closed lines are close-out.sh's: the verb prints what `close-out.sh <plan> closed-form` prints, a parked run's
# `PARKED on` and its branch kept, a task-scale run's branch to be pulled, then merged once the integration branch
# holds the work. fails-when: the verb reads a parked or pull-request plan's `delivered:` line as a merge.
HF_WHY="The release waits on a hand test on the user's machine."
hf_world closed-parked no
poke "$HF_R" handoff
HF_WS="$(git -C "$HF_R" rev-parse --short wave/01-fixture)"
expect_eq "OW0 precondition: the working branch is not merged into trunk (a parked run's branch is kept)" "no" \
  "$(git -C "$HF_R" merge-base --is-ancestor wave/01-fixture trunk && echo yes || echo no)"
printf '\n## Wake Note\n\n%s\n' "$HF_WHY" >> "$HF_P"
hf_close "- Step 9: delivered: parked on wave/01-fixture @ $HF_WS — $HF_WHY (2026-10-08T13:00Z wave-01-fixture); the Step 8/9 tail was performed by close-out.sh without the merge act and attested against the commit gate; continuation at record/wave-01-fixture/continuation.md"
poke "$HF_R" handoff
expect_eq "OW1 handoff on a parked plan exits 0" "0" "$RC"
expect_eq "OW1d …in the document's order" "$HF_HEADS" "$(hf_heads "$HF_F")"
expect_absent "OW1e …never DELIVERED (OW1b read the same file)" "NONE — DELIVERED" "$(cat "$HF_F")"
hf_resume_new_session() {  # -> this session engaged and unbound, with no stamp, armed marker or digest
  engage "$HF_R"
  rm -f "$(stamp_of "$HF_R")" "$(armed_of "$HF_R")" "$(digest_of "$HF_R")"
}
hf_marker_plans() { grep -c '^plan=' "$(marker_of "${1:-$HF_R}")" 2>/dev/null; }  # [<repo>] -> how many plan= lines the marker holds
hf_resume_new_session
poke "$HF_R" resume "$HF_DOOR"
expect_eq "OW2 resume on the parked document exits 0" "0" "$RC"
expect_contains "OW2b …and prints its resume point verbatim" "$(hf_label "$HF_F" 'resume point')" "$OUT"
expect_absent "OW2d …and never that there is nothing to resume (OW2c read the same output)" "nothing to resume" "$OUT"
expect_false "OW2f …and arms nothing" test -e "$(stamp_of "$HF_R")"
hf_world closed-pr no
sed 's/^scale: wave$/scale: task/' "$HF_P" > "$HF_P.s" && mv "$HF_P.s" "$HF_P"
s42_snap "$HF_R" "$HF_P"
poke "$HF_R" handoff
hf_close "- Step 9: delivered: 2026-10-08T13:00Z wave-01-fixture 9.9.9 — closed by close-out.sh"
poke "$HF_R" handoff
expect_eq "OW3 handoff on a task-scale plan whose pull request is owed exits 0" "0" "$RC"
git -C "$HF_R" branch -f trunk wave/01-fixture
poke "$HF_R" handoff
expect_eq "OW3d …and merged into, once trunk holds the work (the same extractor)" "working branch: wave/01-fixture merged into trunk." \
  "$(hf_label "$HF_F" 'working branch')"
HF_CO_OUT="$(cd "$HF_R" && bash "$BIONIC_HOOKS_DIR/../payload/scripts/close-out.sh" "$HF_P" closed-form 2>&1)"
expect_eq "OW4 close-out.sh closed-form prints the two lines the document carries: one writer" \
  "$(hf_label "$HF_F" 'resume point')|$(hf_label "$HF_F" 'working branch' | sed 's/^working branch: /branch: /')" \
  "$(printf '%s\n' "$HF_CO_OUT" | paste -sd'|' -)"
hf_resume_new_session
poke "$HF_R" resume "$HF_DOOR"
expect_eq "RC1 resume on the delivered document exits 0" "0" "$RC"
expect_contains "RC2 …and prints its resume point verbatim" "$(hf_label "$HF_F" 'resume point')" "$OUT"
expect_contains "RC2b …saying nothing is resumed" "nothing to resume" "$OUT"
expect_absent "RC3b …and no task list is offered" "task-list: " "$OUT"

# ============================================================
section "§READERS: adopt's STALE note reads the document's written instant through the pointer; launch-sync has no safe line to mark; a wave-37 plan's in-place section reads as before"
# ============================================================
hf_world readers no
poke "$HF_R" handoff
expect_eq "R0 precondition: the handoff is written" "0" "$RC"
expect_eq "R0b precondition: …its written: line is the instant adopt reads" "written: $HF_ISO" "$(hf_label "$HF_F" written)"
sed 's/^written: .*/written: 2026-01-01T00:00:00Z/' "$HF_F" > "$HF_F.e" && mv "$HF_F.e" "$HF_F"
new_roster "$HF_R"
add_row "$HF_R" name=w-after status=intended agent_id= plan="$HF_P" launched_at=2026-06-01T00:00:00Z
poke "$HF_R" adopt --report-only
s42_snap "$HF_R" "$HF_P"
cp "$HF_F" "$TMPROOT/hf-unmarked"
poke "$HF_R" launch-sync
expect_eq "R2 launch-sync exits 0 with a later dispatch" "0" "$RC"
expect_true "R2b …the document is byte-identical: it has no safe line to mark (cmp)" cmp -s "$TMPROOT/hf-unmarked" "$HF_F"
expect_true "R2c …and the plan is byte-identical: the pointer stands (cmp)" cmp -s "$TMPROOT/s42-before" "$HF_P"
sed 's/^written: .*/written: 2027-01-01T00:00:00Z/' "$HF_F" > "$HF_F.e" && mv "$HF_F.e" "$HF_F"
poke "$HF_R" adopt --report-only
expect_absent "R3b …not STALE (R1 read STALE through the same verb)" "STALE" "$OUT"
awk '
  /^## Handoff[ \t]*$/ { print; print ""; print "written: 2026-01-01T00:00:00Z"; print "- safe to exit: yes"; print "- safe to /clear: yes"; print ""; h = 1; next }
  h && /^## / { h = 0 }
  h { next }
  { print }' "$HF_P" > "$HF_P.o" && mv "$HF_P.o" "$HF_P"
s42_snap "$HF_R" "$HF_P"
poke "$HF_R" adopt --report-only
poke "$HF_R" launch-sync

# ============================================================
section "§RESUME: /bionic:canonical-sdlc <file> runs session-poker.sh resume <file>: bind, arm (at a scale with a Patrol), adopt, the task list, the recap, the step file, the patrol, the tick; a no-run document binds nothing; no resume command ships"
# ============================================================
# The door is a verb the governing skill runs first when it is invoked with a handoff file's path; a /clear leaves a
# new session that is engaged but unbound and unarmed. FIXTURE FIDELITY: §STATE's world; the document written by the
# real verb while bound; then the session made new beside a predecessor session's roster holding a planted open row
# of this plan and an open owed item, the predecessor recorded on the plan as bind records it; the run's design
# ledger in the register's grammar. fails-when: a ritual step is skipped, out of order, a task-scale resume prints
# the cron line, or a resume command ships.
hf_first() {  # <text> <prefix>... -> the first line number of each prefix in <text>, space-joined ('-' when absent)
  local text="$1" p n out=""; shift
  for p in "$@"; do
    n="$(printf '%s\n' "$text" | awk -v p="$p" 'index($0, p) == 1 { print NR; exit }')"
    out="${out:+$out }${n:--}"
  done
  printf '%s' "$out"
}
hf_world resume no
HF_PRED="5f0e2d1c-7a6b-4c3d-9e8f-0a1b2c3d4e5f"
HF_LEDGER="$HF_R/$HF_LEDGER_REL"
mkdir -p "${HF_LEDGER%/*}"
cat > "$HF_LEDGER" <<'LEDGER'
# design ledger — wave-01-fixture

## Δ0 — D1 ruled "1" (Dana Fixture 2026-10-05): the frame holds

## Δ1 — D2 ruled "Option 2" (Dana Fixture 2026-10-06): one door
LEDGER
hf_poke "$HF_R" "$HF_C" handoff
expect_eq "RS0 precondition: the document is written by the real verb while bound" "0" "$RC"
expect_eq "RS0b precondition: …its last line is the door" "/bionic:canonical-sdlc $HF_DOOR" "$(tail -1 "$HF_F")"
awk -v s="$HF_PRED" '/^approved-by:/ { print; print "- session: " s " bound 2026-10-08T09:00:00Z by bind"; next } { print }' \
  "$HF_P" > "$HF_P.p" && mv "$HF_P.p" "$HF_P"
HF_PRED_ROSTER="$(roster_of "$HF_R" "$HF_PRED")"
roster_header > "$HF_PRED_ROSTER"
roster_row_fixture session="$HF_PRED" status=identified name=w-pred agent_id=a-w-pred-3800000000000001 \
  subagent_type=implementor launched_at="$(iso_ago 60)" deliverable="$HF_R/.bionic/docs/record/w-pred.md" \
  duration="45 minutes" cadence="10 minutes" plan="$HF_P" >> "$HF_PRED_ROSTER"
( . "${S46_LIB%/*}/owed.sh" && OWED_ROOT="$HF_R" OWED_SID="$HF_PRED" OWED_PLAN="$HF_P" \
    owed_open approve:release "Approve release" "poker: approve release — reply with your words" )
hf_resume_new_session
expect_false "RS0d precondition: …and unarmed (no stamp)" test -e "$(stamp_of "$HF_R")"
poke "$HF_R" prompt; HF_PROMPT="$OUT"
expect_nonempty "RS0e precondition: the prompt verb prints this session's Patrol prompt" "$HF_PROMPT"
poke "$HF_R" resume "$HF_DOOR"
HF_RS_TERM="$OUT"
expect_eq "RS1 resume <file> exits 0" "0" "$RC"
hf_recap() {  # <terminal output> -> the recap file it names
  printf '%s/%s' "$HF_R" "$(printf '%s\n' "$1" | sed -n 's/^recap: \([^ ]*\) — .*$/\1/p')"
}
HF_RECAP="$(hf_recap "$HF_RS_TERM")"
expect_true "RS1b …naming its recap file, under the run's record" test -s "$HF_RECAP"
HF_RS="$(cat "$HF_RECAP")"
hf_labels() {  # <text> -> the labels of its unindented lines, comma-joined
  printf '%s\n' "$1" | awk '!/^  / && NF { l = $0; sub(/:.*$/, "", l); sub(/ \(.*$/, "", l); printf "%s%s", (n++ ? "," : ""), l } END { print "" }'
}
expect_eq "RS1c the terminal is the short page: bound, step, running, landed since, owed now, patrol, the recap" \
  "poker,step,running,landed since the handoff,owed now,patrol,recap" "$(hf_labels "$HF_RS_TERM")"
expect_eq "RS1d …the step" "step: 4 Implement" "$(printf '%s\n' "$HF_RS_TERM" | grep '^step: ')"
expect_regex "RS1e …each open agent with what it does and for how long" '^  - w-pred · implementor · for [0-9]+ min$' \
  "$(printf '%s\n' "$HF_RS_TERM" | grep '^  - ')"
expect_eq "RS1f …what landed after the handoff was written" "landed since the handoff: T4, T3" \
  "$(printf '%s\n' "$HF_RS_TERM" | grep '^landed since')"
expect_absent "RS1h …the adopt verdicts and the task list stay in the recap (RS4 and RS5 read them there)" "task-list: " "$HF_RS_TERM"
expect_contains "RS2b …saying so (bind's own line)" "poker: bound " "$HF_RS"
expect_true "RS3 it arms at the wave scale: the Patrol stamp exists" test -f "$(stamp_of "$HF_R")"
expect_contains "RS3b …saying so (arm's own line)" "poker: armed — " "$HF_RS"
expect_contains "RS4 it adopts: the predecessor's planted row is listed" "|name=w-pred|" "$HF_RS"
expect_contains "RS4b …and written onto this session's roster as an adoption" "|adopted_from=$HF_PRED|" \
  "$(grep -F '|name=w-pred|' "$(roster_of "$HF_R")" 2>/dev/null | tail -1)"
expect_eq "RS8 working branch: the document's line, verbatim" "working branch: wave/01-fixture @ $HF_WORK" \
  "$(printf '%s\n' "$HF_RS" | grep '^working branch: ')"
expect_eq "RS8b plan: the document's plan line" "plan: $HF_PLAN_REL" "$(printf '%s\n' "$HF_RS" | grep '^plan: ')"
expect_eq "RS8c tree: the checkout's physical path and the branch it has out" \
  "tree: $(cd "$HF_R" && pwd -P) (checked out: $(git -C "$HF_R" symbolic-ref --short HEAD))" "$(printf '%s\n' "$HF_RS" | grep '^tree: ')"
HF_STEP_FILE="$(cd "$(dirname "$POKER")/.." && pwd -P)/skills/canonical-sdlc/steps/4.md"
expect_eq "RS9 step-file: the current step's file, in the plugin that runs" "step-file: $HF_STEP_FILE" \
  "$(printf '%s\n' "$HF_RS" | grep '^step-file: ')"
expect_true "RS9b …a file that exists" test -f "$HF_STEP_FILE"
expect_eq "RS10 patrol: the CronCreate prompt, byte-equal to the prompt verb's" "patrol: $HF_PROMPT" \
  "$(printf '%s\n' "$HF_RS" | grep '^patrol: ')"
expect_regex "RS10b patrol-interval: the interval, and the ritual's order (CronList, the stray jobs deleted, CronCreate)" \
  '^patrol-interval: every [0-9]+s.*CronList.*bionic-patrol session=.*CronCreate' "$(printf '%s\n' "$HF_RS" | grep '^patrol-interval: ')"
expect_regex "RS11 it ticks: the tick's decision line, for this session" \
  "^poker-tick/v1\|at=[^|]*\|session=$SID\|decision=" "$(printf '%s\n' "$HF_RS" | grep '^poker-tick/v1|')"
HF_ORDER="$(hf_first "$HF_RS" "poker: bound " "poker: armed" "poker: w-pred (" "task-list: " "settled: " "open: " "owned-by-user: " \
  "working branch: " "plan: " "tree: " "step-file: " "patrol-interval: " "patrol: " "poker-tick/v1|")"
expect_eq "RS12 every step is present and in the ritual's order" "yes" \
  "$(printf '%s\n' "$HF_ORDER" | awk '{ ok = "yes"; for (i = 1; i <= NF; i++) { if ($i == "-" || (i > 1 && $i + 0 <= p)) ok = "no: field " i " of " $0; p = $i + 0 } print ok }')"
# Typing the resume is the consent: a session with no engagement marker is engaged by the door itself.
hf_resume_new_session
rm -f "$(marker_of "$HF_R")"
poke "$HF_R" resume "$HF_DOOR"

# A task-scale run has no Patrol: resume binds and adopts, and arms nothing, and removes the stamp engagement left.
hf_world resume-task no
sed 's/^scale: wave$/scale: task/' "$HF_P" > "$HF_P.s" && mv "$HF_P.s" "$HF_P"
s42_snap "$HF_R" "$HF_P"
hf_poke "$HF_R" "$HF_C" handoff
expect_eq "RT0 precondition: the task-scale document is written" "0" "$RC"
hf_resume_new_session
poke "$HF_R" arm
expect_true "RT0b precondition: the stamp an unbound engagement arms is there" test -f "$(stamp_of "$HF_R")"
poke "$HF_R" resume "$HF_DOOR"
expect_eq "RT1 resume on a task-scale run exits 0" "0" "$RC"
HF_RT_TERM="$OUT"; OUT="$(cat "$(hf_recap "$HF_RT_TERM")" 2>/dev/null)"
expect_contains "RT1b …it binds" "poker: bound " "$OUT"
expect_eq "RT2b …the task-scale resume prints none" "0" "$(printf '%s\n' "$OUT" | grep -c 'CronCreate recurring')"
expect_eq "RT2c …nor a patrol: prompt line (RS10's extractor)" "" "$(printf '%s\n' "$OUT" | grep '^patrol: ')"
expect_false "RT3b …and the stamp is gone" test -e "$(stamp_of "$HF_R")"
expect_absent "RT3c …nor does it arm (RS3b's line)" "poker: armed — " "$OUT"
expect_eq "RT4 …and nothing ticks: no Patrol, no tick (RS11's extractor)" "" "$(printf '%s\n' "$OUT" | grep '^poker-tick/v1|')"

# A no-run document: resume binds nothing and points at Next 1.
poke "$HF_EU" resume "$HF_EU_F"
expect_eq "RN1 resume on a no-run document exits 0" "0" "$RC"
expect_contains "RN1b …saying there is no run to bind" "no run bound" "$OUT"
expect_contains "RN1c …and printing Next" '1. `bash scratch/time-keys.sh` after caching the closure' "$OUT"
expect_absent "RN1e …and no task list is offered" "task-list: " "$OUT"

# Refusals, each naming the fix.
mkdir -p "$HF_R/.bionic/docs/record/wave-01-fixture"
printf 'not a handoff\n/bionic:canonical-sdlc x.md\n' > "$HF_R/.bionic/docs/record/wave-01-fixture/plain.md"
poke "$HF_R" resume .bionic/docs/record/wave-01-fixture/plain.md
expect_eq "RX1 a file whose first line is not the kind line is refused, exit 2" "2" "$RC"
expect_contains "RX1b …naming the kind line it lacks" "bionic-handoff/v1" "$OUT"
expect_contains "RX1c …and the writer" "session-poker.sh handoff" "$OUT"
printf 'bionic-handoff/v1\nsitrep head: (none recorded)\nplan: .bionic/docs/plans/epic-99-fixture/gone.plan.md\nbranch: wave/01-fixture @ x\nstep: 4\nsafe to clear\n/bionic:canonical-sdlc .bionic/docs/record/wave-01-fixture/gone.md\n' \
  > "$HF_R/.bionic/docs/record/wave-01-fixture/gone.md"
hf_resume_new_session
poke "$HF_R" resume .bionic/docs/record/wave-01-fixture/gone.md
expect_eq "RX2 a file naming a plan that is missing is refused, exit 1" "1" "$RC"
expect_contains "RX2b …naming the missing plan" "gone.plan.md" "$OUT"
poke "$HF_R" resume .bionic/docs/record/wave-01-fixture/nowhere.md
expect_eq "RX3 no file at the path is refused, exit 2" "2" "$RC"
poke "$HF_R" resume
expect_eq "RX4 no path is the usage error" "2" "$RC"
HF_PAYLOAD="${BIONIC_SCRIPTS_DIR}/payload"
expect_eq "RX5 precondition: the listing reads the shipped commands and skills (the decision skill is found)" "1" \
  "$(ls "$HF_PAYLOAD/commands" "$HF_PAYLOAD/skills" 2>/dev/null | grep -c '^decision$')"
expect_eq "RX5b ls payload/commands payload/skills has no resume" "0" \
  "$(ls "$HF_PAYLOAD/commands" "$HF_PAYLOAD/skills" 2>/dev/null | grep -c resume)"

# ============================================================
section "§POINTER-AGREE: one reader of the ## Handoff pointer, lib/handoff.sh handoff_file_of; with no pointer the default is today's handoffs file; a tab-led heading reads alike to close-out and the verb"
# ============================================================
# Each door is asked on one plan: close-out `check` names the file its closed form would be written to; the verb
# rewrites the pointer it finds under the heading. FIXTURE FIDELITY: the plan's ## SDLC State naming its integration
# branch as Step 0 writes it, so check reads the plan through; the pointer moved by hand to an older file, then its
# heading re-spelled with a tab after `##`, as an editor leaves it. fails-when: a door reads the tab-led heading as
# no pointer.
hf_co() { ( cd "$HF_R" && bash "$BIONIC_HOOKS_DIR/../payload/scripts/close-out.sh" "$HF_P" "$1" 2>&1 ); }  # <verb> -> close-out's output on the plan

pa_check_file() {  # -> the file close-out check says its closed form would be written to
  hf_co check | sed -n 's/^handoff: would write the closed form .* to \([^ ;]*\); the plan.*$/\1/p'
}
HF_OLD="$HF_HOME/2026-10-05-wave-01-fixture.md"
hf_world pointer-agree no
awk '/^## SDLC State/ { s = 1 } s && /^current:/ { print "integration-branch: trunk"; s = 0 } { print }' "$HF_P" > "$HF_P.pa" \
  && mv "$HF_P.pa" "$HF_P"
s42_snap "$HF_R" "$HF_P"
expect_eq "PA0 with no pointer, close-out check names today's handoffs file, the one the verb writes" "$HF_DOOR" "$(pa_check_file)"
poke "$HF_R" handoff
cp "$HF_F" "$HF_R/$HF_OLD"
awk -v o="$HF_OLD" '$0 == "## Handoff" { print "##\tHandoff"; next } index($0, "handoff: ") == 1 { print "handoff: " o " written 2026-10-05 15:00 PDT"; next } { print }' \
  "$HF_P" > "$HF_P.pa" && mv "$HF_P.pa" "$HF_P"
s42_snap "$HF_R" "$HF_P"
expect_eq "PA3 close-out check names the file the tab-led pointer names" "$HF_OLD" "$(pa_check_file)"
poke "$HF_R" handoff
expect_eq "PA4 the verb exits 0" "0" "$RC"


finish
