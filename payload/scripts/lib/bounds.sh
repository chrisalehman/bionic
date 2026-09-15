#!/bin/bash
# payload/scripts/lib/bounds.sh — THE DERIVATION BOUNDS, DEFINED ONCE.
# (epic-23 wave-14-tune-181, REQ-7; spec Design §1 "Derivation" and §3 ownership
# row "derivation bound"; design ledger D4, and D1/D2 for the invariant below.)
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
# ── THE RULE THAT GOVERNS BOTH NUMBERS ───────────────────────────────────────
#
# EVERY INNER BOUND SITS STRICTLY UNDER ITS HOOK'S REGISTRATION, MARGIN NAMED.
#
#   IMPACT_BOUND_S    = 10   under hooks/dispatch-preflight.sh's  15   margin 5
#   LG_IMPACT_BOUND_S =  6   under hooks/stop.sh's  "timeout": 10       margin 4
#
# The registrations are hooks/hooks.json's, one per hook, and the margin is what
# the hook has left for everything it does that is not waiting.
#
# WHY STRICTLY UNDER, AND NOT AT. A bound at or above its registration can never
# fire: the CLI kills the hook at the registration, and a killed hook exits 124 —
# not the exit 2 a refusal spells — so the refusal that was in flight silently
# becomes a PASS. That is the one thing either of these gates must never do, and
# it is exactly what a bound above its registration guarantees.
#
# AND NO SUITE THAT DRIVES A GATE DIRECTLY CAN SEE IT. A suite has no CLI
# timeout, so both numbers can be wrong together while every arm that drives the
# refusal stays green — which is what happened: a 20 s bound sat under a 10 s
# registration for the whole of wave-14, refusing hundreds of times in
# tests/dispatch-preflight.test.sh and never once in production (A-T6.5,
# confirmed by four reviewers). The pair is therefore pinned where the two files
# meet, both sides read rather than transcribed:
# tests/cross-gate-agreement.test.sh §L.4c. tests/stop.test.sh 6e/6f pins the
# sweep's half against hooks.json too.
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
# that never returns. The wait has to end on OUR terms, before the CLI ends it on
# its own; the only question is where, and the answer differs by host.
#
# ── IMPACT_BOUND_S = 10 — THE DISPATCH WALL'S, UNDER A 15 s REGISTRATION ─────
#
# hooks/dispatch-preflight.sh is a PreToolUse hook, and what it is guarding
# against is a dispatch that proceeds with no roster row and therefore no budget
# at all (dispatch-preflight.sh's own note).
#
# IT DOES NOT HAVE ROOM TO WAIT AS LONG AS IT LIKES, which is what this paragraph
# used to say. It has exactly its registration, and the shipped 20 s sat above
# it: on the machine the CLI killed the hook at 10 s, the refusal became a pass,
# and the wall was defeated by the cost of the wall — the precise failure the
# bound was written to prevent. Both numbers moved to close that (D1): the
# registration to 15 s, because a wedged session's patience will carry it, and
# the bound to 10 s, which is far above any derivation that is merely slow and
# five seconds clear of the kill.
#
# ── LG_IMPACT_BOUND_S = 6 — THE LANDING GATE'S, AND WHY IT IS SHORTER ────────
#
# THIS ONE IS NOT A CHOICE ABOUT SLOWNESS. It is a ceiling its host imposes.
#
# The landing sweep runs inside hooks/stop.sh, which hooks/hooks.json registers
# at `"timeout": 10` on both Stop and SubagentStop — and unlike the wall's, that
# registration is not this wave's to raise: it bounds four verdicts, of which the
# sweep is one. Six seconds is the sweep's whole derivation budget spent strictly
# inside it, with four seconds left for the rest of the turn-end work.
# tests/landing-gate.test.sh §16i drives it live.
#
# SO THE TWO NUMBERS MOVE FOR DIFFERENT REASONS, UNDER ONE RULE. IMPACT_BOUND_S
# moves when the judgment about a wedged session's patience changes — and then
# its registration moves with it, or it does not move. LG_IMPACT_BOUND_S moves
# only if hooks.json's registration for hooks/stop.sh moves, and never above it.
#
# WHAT WOULD BE WRONG. Lowering either because a derivation felt slow is treating
# it as a budget again: the answer to a slow derivation is the cache, or the
# impact command, never these numbers. Raising either past the point where a
# stuck hook reads as a hung session is the opposite error. Raising one to meet
# its registration — the shape wave-14 T9 shipped and §16i caught — buys nothing
# and costs the refusal.
#
# NO SHELL OPTIONS ARE SET HERE. This file is sourced into a caller's shell and
# defines two constants; `set -u`, `set -o pipefail` and traps belong to whoever
# sourced it.
#
# [WALL: tests/stop.test.sh]
# [WALL: tests/dispatch-preflight.test.sh]
# [WALL: tests/cross-gate-agreement.test.sh §L.4c]

IMPACT_BOUND_S=10
LG_IMPACT_BOUND_S=6
