export function formatHelpMessage(): string {
  return [
    "Available commands:",
    "",
    "/status — What's Claude working on?",
    "/quiet — Manage quiet hours",
    "/help — Show this message",
  ].join("\n");
}
