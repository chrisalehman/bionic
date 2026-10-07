# transcript-move — the entry shapes `user_said` reads (wave-28 T42; REQ-8 AC-8.9, D34)

One file per kind of entry a session transcript (`<config>/projects/<slug>/<session-id>.jsonl`)
carries, cut to the keys that tell the kinds apart. The key sets were measured on CLI 2.1.291
transcripts on 2026-10-07; every value — ids, paths, names and every word of text — is invented.
`tests/session-poker.test.sh` §MOVE assembles a transcript from these files.

| file | kind | what marks it |
|---|---|---|
| `frame.jsonl` | a typed prompt with other words, and the orchestrator's reply | the base of every assembled transcript |
| `typed.jsonl` | a prompt the user typed | `type: user`, top-level `origin.kind: human` |
| `queued.jsonl` | a prompt the user typed while a turn ran | `type: attachment`, `attachment.type: queued_command`, `attachment.origin.kind: human` |
| `tool-result.jsonl` | a tool's result | `type: user`, `content` an array of `tool_result`, no `origin` |
| `teammate.jsonl` | a teammate's message | `type: user`, text `Another Claude session sent a message:` + `<teammate-message …>`, no `origin` |
| `peer.jsonl` | another session's message | `type: user`, `origin.kind: peer`, `isMeta: true` |
| `peer-queued.jsonl` | another session's message, delivered mid-turn | `queued_command` with `attachment.origin.kind: peer` |
| `hook-context.jsonl` | a hook's added context | `hook_additional_context` attachment; `isMeta` stop feedback and system reminder; `stop_hook_summary` |
| `orchestrator.jsonl` | the orchestrator's own text | `type: assistant` |
| `compact.jsonl` | a compaction summary | `isCompactSummary: true`, no `origin` |
| `pasted.jsonl` | a typed prompt whose words are pasted | `origin.kind: human`, the words inside `<pasted_content …>` |
| `sidechain.jsonl` | a dispatched agent's prompt | `isSidechain: true`, no `origin` |

Every decoy carries the words `typed.jsonl` carries (`defer the flag wording until the next
wave, it can wait`), single-spaced, so a reader that counted it would find them.
