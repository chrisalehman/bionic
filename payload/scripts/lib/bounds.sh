#!/bin/bash
# payload/scripts/lib/bounds.sh — THE DERIVATION BOUNDS, DEFINED ONCE.
# (epic-23 wave-14-tune-181, REQ-7; spec Design §1 "Derivation" and §3 ownership
# row "derivation bound"; design ledger D4.)
#
# WHAT IT OWNS. How long a leg of the fleet waits for the impacted-suite
# derivation (`tests/lib/impact.sh`, or whatever `impact-command:` names) before
# it stops waiting. Two files ask that question and neither can be the owner,
# because each runs without the other:
#
#   payload/hooks/dispatch-preflight.sh   once per dispatch, over the brief's Files:
#                                         -> IMPACT_BOUND_S
#   payload/scripts/lib/stop.sh           once per sweep, spent across its rows
#                                         -> LG_IMPACT_BOUND_S
#
# WHY IT IS ITS OWN FILE. Both carried their own `6`, in two files, under two
# headers that each explained the number and neither of which mentioned the other
# (R2 Q8 found the twin). Two copies of a constant do not disagree loudly; they
# disagree the next time a wave moves one of them, and what ships is a tree whose
# two legs mean different things by "bounded" while every message quotes its own
# half. A shared library is the smallest thing that cannot drift.
#
# TWO NAMES IS NOT TWO COPIES (wave-14 T15). The legs wait in different hosts, so
# one number cannot be right for both — but both numbers are chosen here, beside
# each other, where moving one means reading why the other differs.
#
# ── THEY ARE HANG GUARDS, NOT COST BUDGETS ───────────────────────────────────
#
# This is the whole reason these numbers are not tuned downward when a derivation
# feels slow, and the paragraph a future reader needs before touching either.
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
# that never returns. A hook killed on the CLI's own timeout does NOT exit 2, so
# the wait has to end on OUR terms; the only question is where, and the answer
# differs by host.
#
# ── IMPACT_BOUND_S = 20 — THE DISPATCH WALL'S ────────────────────────────────
#
# hooks/dispatch-preflight.sh is a PreToolUse hook. It has room to wait, and what
# it is guarding against is a dispatch that proceeds with no roster row and
# therefore no budget at all (dispatch-preflight.sh's own note). 20 s is chosen
# to sit far above any derivation that is merely slow and still well inside a
# wedged session's patience.
#
# ── LG_IMPACT_BOUND_S = 6 — THE LANDING GATE'S, AND WHY IT IS SHORTER ────────
#
# THIS ONE IS NOT A CHOICE ABOUT SLOWNESS. It is a ceiling its host imposes.
#
# The landing sweep runs inside hooks/stop.sh, which hooks/hooks.json registers
# at `"timeout": 10` on both Stop and SubagentStop. A bound at or above that
# window is never reached: the harness kills the hook at 10 s — the kill reads as
# exit 124, not the exit 2 a refusal spells — and the refusal the gate was in the
# middle of making silently becomes a PASS. That is the one thing this gate must
# never do, and tests/landing-gate.test.sh §16i drives it live to prove it does
# not. The sweep's whole budget is therefore spent strictly inside its own hook's
# registration, with headroom for the rest of the turn-end work beside it.
#
# SO THE TWO NUMBERS MOVE FOR DIFFERENT REASONS. IMPACT_BOUND_S moves when the
# judgment about a wedged session's patience changes. LG_IMPACT_BOUND_S moves
# only if hooks.json's registration for hooks/stop.sh moves, and never above it.
#
# WHAT WOULD BE WRONG. Lowering either because a derivation felt slow is treating
# it as a budget again: the answer to a slow derivation is the cache, or the
# impact command, never these numbers. Raising IMPACT_BOUND_S past the point
# where a stuck dispatch reads as a hung session is the opposite error. Raising
# LG_IMPACT_BOUND_S to match it — the shape wave-14 T9 shipped and §16i caught —
# buys nothing and costs the refusal.
#
# NO SHELL OPTIONS ARE SET HERE. This file is sourced into a caller's shell and
# defines two constants; `set -u`, `set -o pipefail` and traps belong to whoever
# sourced it.
#
# [WALL: tests/stop.test.sh]
# [WALL: tests/dispatch-preflight.test.sh]

IMPACT_BOUND_S=20
LG_IMPACT_BOUND_S=6
