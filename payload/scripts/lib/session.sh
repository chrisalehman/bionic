# payload/scripts/lib/session.sh — the one session-id function (bionic 1.4.0
# wave, spec AC-2, plan slice L-SESSION; design-ledger S2).
#
# THE RULE. The environment value (`$CLAUDE_CODE_SESSION_ID`) is primary,
# every payload `session_id` field is a witness only. All twenty readers call
# this one function so a divergence is reported once, never silently chosen
# per-reader.
#
# `session_id [payload_sid]`
#   env set, no divergence (payload_sid empty, or equal to env) -> prints the
#     env value, exit 0, silent.
#   env set, payload_sid non-empty and different -> prints the env value,
#     exit 0, and one stderr line naming both:
#       session-id: payload <payload_sid> ≠ env <env_sid> — using env
#   env unset (empty), payload_sid non-empty -> prints payload_sid, exit 0,
#     and one stderr line:
#       session-id: env unset — using payload
#   env unset, payload_sid empty/absent -> prints nothing, exit 1, and one
#     stderr line:
#       session-id: no session id in env or payload
#
# Sourcing this file prints nothing and has no side effects — it only defines
# the function below.

session_id() {
  local payload_sid="${1:-}"
  local env_sid="${CLAUDE_CODE_SESSION_ID:-}"

  if [ -n "$env_sid" ]; then
    if [ -n "$payload_sid" ] && [ "$payload_sid" != "$env_sid" ]; then
      echo "session-id: payload ${payload_sid} ≠ env ${env_sid} — using env" >&2
    fi
    echo "$env_sid"
    return 0
  fi

  if [ -n "$payload_sid" ]; then
    echo "session-id: env unset — using payload" >&2
    echo "$payload_sid"
    return 0
  fi

  echo "session-id: no session id in env or payload" >&2
  return 1
}
