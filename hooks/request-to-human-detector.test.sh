#!/bin/bash
# Tests for request-to-human-detector.sh
#
# The detector answers ONE question about an assistant turn: does this turn ask
# the human for something? Both categories the design recognises — an action and
# a decision — are one signal. Classification into action-vs-decision is the
# model's job at runtime, never the detector's.
#
# Strategy: a planted-positive / planted-negative fixture pair, each fixture
# authored here (synthetic, never copied from a transcript) and realistic in
# SHAPE. Every fixture is then MUTATED and RESTORED: the mutation removes (or,
# for a negative, adds) the load-bearing element and the verdict must flip. A
# fixture that passes without a demonstrated flip proves nothing — it could be
# passing for an unrelated reason, and RED evidence is perishable once the
# implementation is green. The restore is verified byte-for-byte with cmp, so a
# mutation cannot leak into a later case.
#
# Batch mode is asserted to agree with single mode on every fixture. The corpus
# baseline scores 282MB through --batch while the Stop hook uses single mode;
# if they ever disagreed the baseline would be measuring a different detector
# than the one that ships.
#
# Usage: bash hooks/request-to-human-detector.test.sh

set -uo pipefail

DET="$(cd "$(dirname "$0")" && pwd)/request-to-human-detector.sh"
PASS=0; FAIL=0; TOTAL=0

FIXDIR=$(mktemp -d)
trap 'rm -rf "$FIXDIR"' EXIT

pass() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); printf '  PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); printf '  FAIL  %s%s\n' "$1" "${2:+ ($2)}"; }

# detect <file> → sets DET_RC (0 = fired) and DET_SIG (signal names)
detect() {
  DET_SIG=$(bash "$DET" < "$1" 2>/dev/null)
  DET_RC=$?
}

assert_fires() {  # $1=label $2=file
  detect "$2"
  if [ "$DET_RC" -eq 0 ]; then pass "$1 [$DET_SIG]"; else fail "$1" "did not fire"; fi
}

assert_silent() {  # $1=label $2=file
  detect "$2"
  if [ "$DET_RC" -ne 0 ]; then pass "$1"; else fail "$1" "fired: $DET_SIG"; fi
}

# ---------- fixtures ----------
# name | mutation (sed expr applied in place) | text
POS_NAMES=(); POS_MUT=()
NEG_NAMES=(); NEG_MUT=()

add_pos() { POS_NAMES+=("$1"); POS_MUT+=("$2"); printf '%s\n' "$3" > "$FIXDIR/pos-$1.txt"; }
add_neg() { NEG_NAMES+=("$1"); NEG_MUT+=("$2"); printf '%s\n' "$3" > "$FIXDIR/neg-$1.txt"; }

# --- positives: ACTION-shaped (the agent wants the human to DO something) ---

read -r -d '' T <<'EOF' || true
The suite is green here but this machine has no Docker daemon.

Can you run `bash tests/run.sh` on your box and paste the container-suite
output? Everything else is already covered.
EOF
add_pos action-can-you 's/Can you run/I ran/' "$T"

read -r -d '' T <<'EOF' || true
Migration written and verified against a scratch database. It is additive
only — one new column, nullable, no backfill.

Please push this to the release branch when the window opens.
EOF
add_pos action-please-push 's/Please push this/I pushed this/' "$T"

read -r -d '' T <<'EOF' || true
The upload step fails at auth. The token in the environment is expired and
rotating it is on the approval list, so I stopped rather than reaching for it.

I need you to mint a fresh token before I can finish this.
EOF
add_pos action-i-need-you 's/I need you to mint/I minted/' "$T"

read -r -d '' T <<'EOF' || true
Every hermetic suite passes. The container e2e is the only gap.

Want me to skip it and mark the row unproven, or start the daemon first?
EOF
add_pos action-want-me-to 's/Want me to skip it and mark the row unproven, or start the daemon first?/I skipped it and marked the row unproven./' "$T"

read -r -d '' T <<'EOF' || true
Record updated. Propagation is out of my hands from here.

Let me know once it resolves and I will re-run the health check.
EOF
add_pos action-let-me-know 's/Let me know once it resolves and I will re-run/I will re-run/' "$T"

# --- positives: DECISION-shaped (the agent wants the human to CHOOSE) ---

read -r -d '' T <<'EOF' || true
The parser is called twice per invocation and the config file is small.

Should we cache the parsed result, or re-read it every time?
EOF
add_pos decision-should-we 's/Should we cache the parsed result, or re-read it every time?/I cached the parsed result./' "$T"

read -r -d '' T <<'EOF' || true
Two shapes fit the constraint.

**Option 1** — inline the helper at both call sites. Less indirection, one
duplicated block.

**Option 2** — extract a module. One definition, one more file to install.

Which do you prefer?
EOF
add_pos decision-options-and-question 's/^\*\*Option \([12]\)\*\*/Approach \1/; s/Which do you prefer?/I took the second./' "$T"

read -r -d '' T <<'EOF' || true
Both paths reach the same end state and cost about the same.

Which approach do you want me to take?
EOF
add_pos decision-which-approach 's/Which approach do you want me to take?/I took the first./' "$T"

read -r -d '' T <<'EOF' || true
Widening this to the sibling package would fix the same defect in three more
places, but it is outside what was asked.

That is a scope question — your call.
EOF
add_pos decision-your-call 's/your call/my call, and I kept the scope narrow/' "$T"

# Blockquoted PROSE, not blockquoted code. The blockquote marker is stripped
# when deciding whether a line opens or closes a code block, and this fixture is
# the guard on that: stripping it must not turn quoted prose into skipped
# content. Quoting an ask is still asking.
read -r -d '' T <<'EOF' || true
Pulling the open thread out of the review so it does not get lost:

> Should we cache the parsed result, or re-read it every time?

Everything else in the review is closed.
EOF
add_pos decision-blockquoted-ask 's/Should we cache the parsed result, or re-read it every time?/I cached the parsed result./' "$T"

# Options WITHOUT a question — the enumerated-options signal must stand alone.
read -r -d '' T <<'EOF' || true
Three ways to shape the retry policy.

**Option A** — fixed backoff. Predictable, slow under load.

**Option B** — exponential with jitter. Fast recovery, harder to reason about.

**Option C** — no retry, fail fast to the caller.
EOF
add_pos decision-options-only 's/^\*\*Option \([ABC]\)\*\*/Shape \1/' "$T"

# --- positives: a labelled menu whose items are an ordinary numbered list ---
# The `Option N` heading is one way to write a menu; a standalone `Options:`
# label governing a numbered list is the same FORM. The label line is what
# distinguishes a menu from the numbered lists that fill ordinary work turns.

read -r -d '' T <<'EOF' || true
Three ways to land this.

**Options:**
1. **Inline the helper** (Recommended) — less indirection, one duplicated block.
2. **Extract a module** — one definition, one more file to install.
3. **Leave it** — the duplication is two lines and the sites never change together.

I would take 1.
EOF
add_pos decision-options-label '/^\*\*Options:\*\*$/d' "$T"

read -r -d '' T <<'EOF' || true
The retry policy needs a call before the client ships.

Choices:
1. Fixed backoff — predictable, slow under load.
2. Exponential with jitter — fast recovery, harder to reason about.
EOF
add_pos decision-choices-label '/^Choices:$/d' "$T"

# --- positives: blocked-on-you, an ask phrased as a statement of pendency ---
# Never a question, never an imperative — it names the human as the thing the
# work is waiting on. The preposition is load-bearing: "blocked ON your call"
# is an ask, "blocked your push" is a report. See the negative below.

read -r -d '' T <<'EOF' || true
Reviewer idle — its report is already banked. The suite is green and nothing
else is outstanding.

The branch remains paused on your read of the migration window.
EOF
add_pos action-paused-on-your 's/paused on your read of the migration window/paused until the migration window closes/' "$T"

read -r -d '' T <<'EOF' || true
Nothing pending on my side except your ruling on the retry policy.
EOF
add_pos action-pending-your-ruling 's/except your ruling on the retry policy/except the nightly run of the retry suite/' "$T"

# --- positives: a bare imperative aimed at the human ---
# No "please", no "can you" — just the verb. The direction markers the other
# request forms rely on are absent, and the sentence position carries it.

read -r -d '' T <<'EOF' || true
The one-pager is drafted and the three closeout items are listed above.

Confirm the closeout items and I will write it up.
EOF
add_pos action-bare-confirm 's/Confirm the closeout items and I will write it up./I confirmed the closeout items and wrote it up./' "$T"

read -r -d '' T <<'EOF' || true
Both scopes are viable and the tradeoff is stated above. The narrow one costs a
day, the wide one costs a week and covers two more call sites.

Reply with the scope you want and I will start on it.
EOF
add_pos action-bare-reply 's/Reply with the scope you want and I will start on it./I started on the narrow scope./' "$T"

# --- negatives: ordinary work turns ---

read -r -d '' T <<'EOF' || true
Wired the parser into the loader. Three files touched, all 41 tests pass.

The cache key now includes the file mtime, which is what fixed the stale-read
on the second invocation.
EOF
add_neg progress-report '$a\
Should I keep going?' "$T"

read -r -d '' T <<'EOF' || true
    bash tests/run.sh
    Gating: 5 passed, 0 failed, 1 skipped
    All gating suites green

Results: 41/41 passed, 0 failed. Commit 4f2a91c, 3 files, +118/-22.
EOF
add_neg evidence-block '$a\
Can you confirm this is enough?' "$T"

# Code-only turn. The fence carries a `?` inside a regex AND the word "you" in a
# comment — both would trip the detector if fenced code were not stripped.
read -r -d '' T <<'EOF' || true
Here is the guard as it now stands.

```bash
# you must call this before the first read, or the mtime is unset
key=$(printf '%s' "$path" | cksum | cut -d' ' -f1)
case "$key" in
  ''|*[!0-9]*) return 1 ;;
esac
grep -qE 'colou?r' "$path" && echo matched
```

It exits non-zero on a malformed key instead of defaulting to zero.
EOF
add_neg code-only '$a\
Should we ship it?' "$T"

# The other three code-block forms CommonMark recognises, plus nesting. A
# stripper that knows only ``` scans the contents of all of them, and the
# request-shaped comment inside each is what a real turn pastes. One shared
# payload line (`# can you run this ...`) so the fixtures differ only in the
# block FORM, which is the thing under test.

read -r -d '' T <<'EOF' || true
Here is the guard as it now stands, pasted straight from the terminal.

    # can you run this before the first read, or the mtime is unset
    key=$(printf '%s' "$path" | cksum | cut -d' ' -f1)

It exits non-zero on a malformed key instead of defaulting to zero.
EOF
add_neg indented-code '$a\
Can you confirm this is enough?' "$T"

read -r -d '' T <<'EOF' || true
Here is the guard as it now stands.

~~~bash
# can you run this before the first read, or the mtime is unset
grep -qE 'colou?r' "$path" && echo matched
~~~

It exits non-zero on a malformed key instead of defaulting to zero.
EOF
add_neg tilde-fence '$a\
Can you confirm this is enough?' "$T"

read -r -d '' T <<'EOF' || true
The reviewer quoted the guard back at me.

> ```bash
> # can you run this before the first read, or the mtime is unset
> grep -qE 'colou?r' "$path" && echo matched
> ```

Their point was that anchoring to the line start is the whole fix.
EOF
add_neg blockquoted-fence '$a\
Can you confirm this is enough?' "$T"

# Nesting is the case a naive toggle gets exactly backwards: the inner fence
# flips the flag OFF, so the inner code is SCANNED and the prose around it is
# SKIPPED. Closing only on a marker of the same char and at least the opening
# length — the CommonMark rule — is what kills the inversion.
read -r -d '' T <<'EOF' || true
Here is the README block, wrapped so the inner fence survives verbatim.

````markdown
Install the guard, then run it:

```bash
# can you run this before the first read?
grep -qE 'colou?r' "$path"
```
````

The outer fence is four backticks, so the inner three do not close it.
EOF
add_neg nested-fence '$a\
Can you confirm this is enough?' "$T"

# The other half of the same inversion. The wrapped fragment shows an OPENING
# fence only, so a toggle is left inverted and every line after the block is
# skipped — including a real ask. Baseline silence here is not evidence; the
# MUTATION is, because it fires only if the outer fence actually closed.
read -r -d '' T <<'EOF' || true
Here is the README fragment that documents how to open a block.

````markdown
Start the block like this:

```bash
````

The fragment is deliberately unbalanced — that is what it documents.
EOF
add_neg nested-fence-unbalanced '$a\
Should we ship it as written, or trim the fragment first?' "$T"

read -r -d '' T <<'EOF' || true
Why does the cache miss on every second call? Because the key includes a
timestamp that is regenerated per invocation.

Dropping the timestamp from the key fixes it without touching the eviction
policy.
EOF
add_neg rhetorical-question '$a\
Do you want me to drop it?' "$T"

read -r -d '' T <<'EOF' || true
Done, in four steps:

1. Extracted the boundary check into its own function.
2. Replaced the three call sites.
3. Added the malformed-input case to the suite.
4. Re-ran the full suite — 41/41.

Nothing outside those three files changed.
EOF
add_neg numbered-summary '$a\
Which of those should I revisit?' "$T"

# Second person, but pointed at the reader as documentation — not an ask.
read -r -d '' T <<'EOF' || true
You can reproduce this with `bash tests/run.sh` from a clean tree. The failure
is deterministic once the fixture directory exists.

If you delete the fixture directory first, the suite skips the case silently,
which is the behaviour this change removes.
EOF
add_neg second-person-docs '$a\
Would you like me to remove it?' "$T"

# The receipt shape: a decision already made and reported. Must NOT fire, or the
# hook would refuse the very behaviour it exists to produce.
read -r -d '' T <<'EOF' || true
Took the simpler shape — one detector, not two. Rationale: overlapping
per-category detectors misfire, since a technical decision is also
decision-shaped.

The classification stays where the judgement is.
EOF
add_neg receipt-line '$a\
Was that the right call for you?' "$T"

read -r -d '' T <<'EOF' || true
Both options work. I took the second because it costs one fewer process per
turn and the first has no advantage at this size.

Benchmarked at 41ms versus 78ms over 200 turns.
EOF
add_neg options-in-prose '$a\
Should we revisit that?' "$T"

read -r -d '' T <<'EOF' || true
The pattern `[a-z]?` makes the character optional, which is why the empty
string matched. Anchoring it to the line start is enough.

That anchor is the whole fix.
EOF
add_neg question-mark-in-prose '$a\
Can you sanity-check the anchor?' "$T"

read -r -d '' T <<'EOF' || true
Retry storm has not recurred since the jitter landed. I will let you know if it
does — the alarm is still armed.

Logs are clean for 6 hours.
EOF
add_neg let-you-know '$a\
Should I disarm the alarm?' "$T"

# The preposition is what separates an ask from a report. "blocked ON your
# call" hands the work to the human; "blocked your push" is something that
# happened TO them. A pendency signal that grabbed any (blocked, your) pair
# would fire here, so this fixture is the guard on that generalisation.
read -r -d '' T <<'EOF' || true
The pre-commit hook blocked your push because the branch is protected. Re-run
after rebasing and it will go through.

Nothing else in the tree changed.
EOF
add_neg blocked-your-push 's/blocked your push because/blocked on your push decision because/' "$T"

# Past-tense reports of decisions already made. The bare-imperative signal keys
# on the verb in sentence-initial position; "Confirmed", "Approved", "Decided"
# are receipts, and the hook must never refuse the behaviour it exists to
# produce.
read -r -d '' T <<'EOF' || true
Confirmed: 41/41 pass. Approved the migration in staging earlier today, and the
rollback path is tested.

Decided against the wider refactor — it is outside what was asked.
EOF
add_neg past-tense-reports '$a\
Confirm the rollback path.' "$T"

# ---------- 1. baseline: every positive fires, every negative is silent ----------

echo "Planted positives fire (AC-2, catch direction)"
for n in "${POS_NAMES[@]}"; do
  assert_fires "positive $n fires" "$FIXDIR/pos-$n.txt"
done

echo
echo "Planted negatives stay silent (AC-2, false-positive direction)"
for n in "${NEG_NAMES[@]}"; do
  assert_silent "negative $n silent" "$FIXDIR/neg-$n.txt"
done

# ---------- 2. mutation-and-restore ----------
# Each fixture is mutated IN PLACE, the verdict must flip, and the original is
# restored and re-verified byte-for-byte. This is the durable proof that the
# fixture discriminates on the element it claims to.

mutate_and_restore() {  # $1=file $2=sed-expr $3=label $4=expect-after-mutation(fire|silent)
  local f="$1" expr="$2" label="$3" want="$4"
  cp "$f" "$f.orig"
  sed "$expr" "$f.orig" > "$f"
  if cmp -s "$f" "$f.orig"; then
    fail "$label mutation changed the fixture" "sed was a no-op"
    cp "$f.orig" "$f"; return
  fi
  if [ "$want" = "silent" ]; then
    assert_silent "$label mutation flips verdict to silent" "$f"
  else
    assert_fires "$label mutation flips verdict to fire" "$f"
  fi
  cp "$f.orig" "$f"
  if cmp -s "$f" "$f.orig"; then pass "$label restored byte-identical"
  else fail "$label restored byte-identical" "restore did not match"; fi
}

echo
echo "Mutation-and-restore: positives lose the ask and go silent"
i=0
for n in "${POS_NAMES[@]}"; do
  mutate_and_restore "$FIXDIR/pos-$n.txt" "${POS_MUT[$i]}" "positive $n" silent
  assert_fires "positive $n fires again after restore" "$FIXDIR/pos-$n.txt"
  i=$((i + 1))
done

echo
echo "Mutation-and-restore: negatives gain an ask and fire"
i=0
for n in "${NEG_NAMES[@]}"; do
  mutate_and_restore "$FIXDIR/neg-$n.txt" "${NEG_MUT[$i]}" "negative $n" fire
  assert_silent "negative $n silent again after restore" "$FIXDIR/neg-$n.txt"
  i=$((i + 1))
done

# ---------- 3. batch mode agrees with single mode ----------
# The corpus baseline scores through --batch; the Stop hook uses single mode.
# Divergence would mean the measured detector is not the shipped detector.

echo
echo "Batch mode agrees with single mode on every fixture"
BATCH_IN="$FIXDIR/batch.in"
: > "$BATCH_IN"
EXPECT="$FIXDIR/batch.expect"
: > "$EXPECT"
for n in "${POS_NAMES[@]}"; do
  printf '\001pos-%s\n' "$n" >> "$BATCH_IN"; cat "$FIXDIR/pos-$n.txt" >> "$BATCH_IN"
  printf 'pos-%s\t1\n' "$n" >> "$EXPECT"
done
for n in "${NEG_NAMES[@]}"; do
  printf '\001neg-%s\n' "$n" >> "$BATCH_IN"; cat "$FIXDIR/neg-$n.txt" >> "$BATCH_IN"
  printf 'neg-%s\t0\n' "$n" >> "$EXPECT"
done
bash "$DET" --batch < "$BATCH_IN" | cut -f1,2 > "$FIXDIR/batch.actual"
TOTAL=$((TOTAL + 1))
if diff -u "$EXPECT" "$FIXDIR/batch.actual" >"$FIXDIR/batch.diff" 2>&1; then
  PASS=$((PASS + 1)); printf '  PASS  batch verdicts match single-mode verdicts (%d records)\n' \
    "$(( ${#POS_NAMES[@]} + ${#NEG_NAMES[@]} ))"
else
  FAIL=$((FAIL + 1)); printf '  FAIL  batch verdicts match single-mode verdicts\n'
  sed 's/^/        /' "$FIXDIR/batch.diff"
fi

# ---------- 4. degenerate input ----------

echo
echo "Degenerate input is silent, never an error"
: > "$FIXDIR/empty.txt"
assert_silent "empty turn silent" "$FIXDIR/empty.txt"
printf '\n\n   \n' > "$FIXDIR/blank.txt"
assert_silent "whitespace-only turn silent" "$FIXDIR/blank.txt"

echo
printf 'Results: %d/%d passed, %d failed\n' "$PASS" "$TOTAL" "$FAIL"
[ "$FAIL" -eq 0 ]
