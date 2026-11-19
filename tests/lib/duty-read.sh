# tests/lib/duty-read.sh — a turn-end refusal, read on whichever channel it rides
#
#     . "$(dirname "$0")/lib/duty-read.sh"
#
# A refusal whose fix is the person's is a JSON block, its reason on stdout. One whose fix is the agent's is a duty:
# exit 0, the fixed line in a Stop context, and the whole refusal in the session's duty file, which the model reads
# through `session-poker.sh duty`. A suite that asserted a refused turn reads it through these, so the row still
# asserts the refusal on the channel it now rides.
DUTY_LINE="bionic: a duty is owed; run session-poker.sh duty"
duty_ctx() { printf '%s' "${1:-}" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }  # <stdout>
duty_path() { printf '%s/.bionic/tmp/duty-%s.state' "$1" "$2"; }  # <root> <sid> -> the session's duty file
duty_channel() {  # <stdout> -> block, duty, or nothing for a turn that ends
  local d; d="$(printf '%s' "${1:-}" | jq -r '.decision // ""' 2>/dev/null)"
  if [ -n "$d" ]; then printf '%s' "$d"; return 0; fi
  [ -z "$(duty_ctx "${1:-}")" ] || printf 'duty'
}
duty_reason() {  # <stdout> <duty file> -> the whole refusal the agent receives
  case "$(duty_channel "${1:-}")" in
    block) printf '%s' "$1" | jq -r '.reason // ""' 2>/dev/null ;;
    duty)  if [ "$(duty_ctx "$1")" = "$DUTY_LINE" ]; then cat "$2" 2>/dev/null; else duty_ctx "$1"; fi ;;
  esac
}
