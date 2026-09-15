#!/bin/bash
# payload/scripts/lib/bounds.sh — THE DERIVATION BOUND, DEFINED ONCE.
# (epic-23 wave-14-tune-181, REQ-7; spec Design §1 "Derivation" and §3 ownership
# row "derivation bound"; design ledger D4.)
#
# WHAT IT OWNS. `IMPACT_BOUND_S` — how long either leg of the fleet waits for the
# impacted-suite derivation (`tests/lib/impact.sh`, or whatever `impact-command:`
# names) before it stops waiting. Two files ask that question and neither can be
# the owner, because each runs without the other:
#
#   payload/hooks/dispatch-preflight.sh   once per dispatch, over the brief's Files:
#   payload/scripts/lib/stop.sh           once per sweep, spent across its rows
#
# WHY IT IS ITS OWN FILE. Both carried their own `6`, in two files, under two
# headers that each explained the number and neither of which mentioned the other
# (R2 Q8 found the twin). Two copies of a constant do not disagree loudly; they
# disagree the next time a wave moves one of them, and what ships is a tree whose
# two legs mean different things by "bounded" while every message quotes its own
# half. A shared library is the smallest thing that cannot drift.
#
# ── IT IS A HANG GUARD, NOT A COST BUDGET ────────────────────────────────────
#
# This is the whole reason the number is 20 and not 6, and the sentence a future
# reader needs before touching it.
#
# The bound used to be doing two jobs. `tests/lib/impact.sh` rebuilt its entire
# suite-to-file edge graph on EVERY invocation — 4.2 s at quiet load, and
# argument-independent to 13 ms, because the graph is a pure function of the tree
# and only the last two blocks ever looked at the query (R2 Q8). Against a 6 s
# bound that left 1.8 s of headroom, so an ordinary dispatch under load 8-12 took
# 5.6 s and was REFUSED for the cost of asking its own question (A-orch-46). The
# operator's fault was nothing; the machine was busy.
#
# The cost is gone: impact.sh caches that graph per tree state, so the second and
# every later call at one tree state answers in well under a second. What is left
# for a bound to do is the thing no cache can fix — a configured impact command
# that never returns. Both hooks are registered at `"timeout": 10` in
# hooks/hooks.json, and a hook killed on the CLI's own timeout does NOT exit 2:
# the dispatch would proceed with no roster row and therefore no budget at all
# (dispatch-preflight.sh's own note). So the wait has to end on OUR terms, and the
# only question is where. 20 s is chosen to sit far above any derivation that is
# merely slow and still well inside a wedged session's patience.
#
# WHAT WOULD BE WRONG. Lowering this because a derivation felt slow is treating
# it as a budget again: the answer to a slow derivation is the cache, or the
# impact command, never this number. Raising it past the point where a stuck
# dispatch reads as a hung session is the opposite error.
#
# NO SHELL OPTIONS ARE SET HERE. This file is sourced into a caller's shell and
# defines one constant; `set -u`, `set -o pipefail` and traps belong to whoever
# sourced it.
#
# [WALL: tests/stop.test.sh]
# [WALL: tests/dispatch-preflight.test.sh]

IMPACT_BOUND_S=20
