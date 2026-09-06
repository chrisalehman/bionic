# tests/lib/roster-row.sh — the one `roster-state/v1` fixture builder
# (wave-01 verification-cannot-lie, S14; spec AC-25; design ledger D3).
#
#     . "$(dirname "$0")/lib/resolve-roots.sh"      # first, so BIONIC_SCRIPTS_DIR is set
#     . "$(dirname "$0")/lib/roster-row.sh"
#
# WHAT IT REPLACES. Sixteen suites hand-wrote this row at sixty-three `printf` sites, and
# the code map (§2.b) measured what that bought: one fixture inventing a `ts=` field no
# production writer has ever emitted, one writing four fields, one writing two, several
# omitting `source=`/`claims=`/`cadence=`/`waiver=`/`plan=`. Every one of them stayed green,
# because the fleet's readers are BY KEY — which is also why the drift could go on for as
# long as it liked without a single test noticing. This file ends the family. S14 converts
# `tests/dispatch-preflight.test.sh` and `tests/session-poker.test.sh`; the remaining
# fourteen suites are S17's sweep.
#
# IT DELEGATES, IT DOES NOT RE-SPELL. `roster_row` (payload/scripts/lib/roster.sh) is the
# one production writer of this shape and every function here goes through it. A fixture
# builder that carried its own format string would be the sixty-fourth copy — the one with
# a test-suite's name on it — and the first shape the real writer stopped producing would
# still be sitting in every fixture, green.
#
# THE NEGATIVE SHAPES ARE DERIVED FROM THE REAL ROW, NOT TYPED OUT. D3 gives negative
# shapes a named function each with the reason recorded, and the honest way to express
# "the row, but damaged" is to build the real row and then damage it — a truncation reads
# on disk exactly as a truncation, and the undamaged part of it still tracks the writer.
#
# DEFAULTS. `roster_row_fixture` fills every field a suite did not name, so a case that
# cares about `claims=` says so and says nothing else. They are deliberately RECOGNISABLE
# (`toolu_01FIXTURE`, `2026-09-02T00:00:00Z`) so a value that escapes into a diff or a
# failure message announces where it came from. A suite with its own house defaults passes
# them explicitly; later arguments win, so `roster_row_fixture status=intended name=x` is
# the whole call.

# roster_row_fixture <key=value>... -> one complete row, through the production writer.
# Unknown keys are refused by `roster_row` itself, which is the point: a fixture cannot
# invent a field the fleet has no reader for.
roster_row_fixture() {  # <key=value>...
  roster_row \
    status=confirmed \
    session=fixturesession \
    name=agent \
    agent_id=a000 \
    launched_at=2026-09-02T00:00:00Z \
    subagent_type=implementor \
    model=opus \
    deliverable= \
    source=declared \
    duration= \
    progress= \
    claims= \
    cadence= \
    absent= \
    waiver= \
    tool_use_id=toolu_01FIXTURE \
    plan=none \
    "$@"
}

# roster_row_no_plan <key=value>... -> the row as bionic wrote it BEFORE `plan=` existed.
#
# NOT A DAMAGED ROW — A HISTORICAL ONE, which is why it is here rather than being fixed.
# `plan=` was appended to this schema by wave-session-bound-run (S5); every roster written
# before that carries none, `adopt`'s partition still has to answer for those files, and
# `tests/session-poker.test.sh`'s cases about a pre-wave roster are the only place that
# behaviour is exercised. No writer produces this shape today and none ever will again, so
# it cannot be obtained from `roster_row` — it is obtained by removing from a real row the
# one field that did not exist yet, which is what the passage of time did to it.
roster_row_no_plan() {  # <key=value>...
  roster_row_fixture "$@" | sed 's/|plan=[^|]*$//'
}

# roster_row_prefix_only <key=value>... -> the schema token and the first three fields.
#
# THE SHAPE A PREFIX-MATCHING READER IS ENOUGH FOR. Two readers in the fleet select rows
# with a literal prefix test — `hooks/dispatch-preflight.sh`'s roster prune
# (`"roster-state/${ROSTER_VERSION}|status=intended|"*`) and `patrol_roster_state`'s
# `grep '^roster-state/v1|status=intended|'` — and a fixture aimed at one of those is
# testing the SELECTION, not the row. Writing a complete row there would say the reader
# needs the other fifteen fields when it demonstrably does not, and writing a hand-typed
# stub would put a fourth spelling of the prefix in the tree. This truncates a real row,
# so the prefix under test is the writer's own.
roster_row_prefix_only() {  # <key=value>...
  roster_row_fixture "$@" | cut -d'|' -f1-4
}

if ! type -t roster_row >/dev/null 2>&1; then
  . "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/roster.sh"
fi

# roster_row_schema -> the row's schema token (`roster-state/<version>`), taken off a row
# the production writer just wrote rather than spelled out here.
#
# FOR THE READERS, NOT THE WRITERS. A dozen assertions in the fleet's suites SELECT rows
# with a literal prefix — `grep -c '^roster-state/v1|'`, `grep "^roster-state/v1|status=…"`.
# Those are not builders and converting them to `roster_row_fixture` would be nonsense, but
# a hand-typed schema token in a reader drifts exactly as far as one in a writer: the day
# the schema goes to v2 the grep matches nothing and the assertion counts zero of zero and
# passes. This gives a reader the writer's own answer.
roster_row_schema() {
  roster_row status= | cut -d'|' -f1
}

# Resolved once at source time so a reader can say `"^${ROSTER_ROW_SCHEMA}|"` without paying
# a subshell per assertion.
ROSTER_ROW_SCHEMA="$(roster_row_schema)"
