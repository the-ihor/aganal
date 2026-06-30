# AGANAL

An analysis framework for code and Claude conversations.

It inspects sessions and source to surface insights such as tool usage,
conversation patterns, and how code evolves over a session.

## Scope

- **Conversations** — parse Claude conversation logs and extract metrics
  (tool calls, frequencies, sequences, errors/retries, timing).
- **Code** — analyze the source touched during those sessions.

## Architecture

A **provider** reads one assistant's on-disk session files and normalizes them
into a shared model, so every analysis runs against the same shape regardless of
source.

```
Sources/
├── main.swift                 # demo: discover + summarize the latest session
├── Model/
│   ├── ProviderKind.swift     # which assistant a session came from
│   ├── Session.swift          # Session, SessionRef, ModelInfo
│   └── Event.swift            # Event + Message/Reasoning/ToolCall/ToolResult/TokenUsage/Lifecycle
├── Providers/
│   ├── Provider.swift         # protocol: discover() + parse() → Session
│   ├── CodexProvider.swift    # ~/.codex/sessions/**/rollout-*.jsonl
│   └── ClaudeCodeProvider.swift  # ~/.claude/projects/**/<uuid>.jsonl
└── Support/
    ├── JSONValue.swift        # tolerant JSON for polymorphic records
    ├── JSONL.swift            # line-delimited JSON reader
    ├── Normalize.swift        # text + tool-result extraction
    ├── Timestamps.swift       # ISO 8601 parsing
    └── FileWalk.swift         # cheap session-file discovery
```

A normalized `Session` is provider metadata plus a flat, time-ordered list of
`Event`s. Each `Event` is one of: `message`, `reasoning`, `toolCall`,
`toolResult`, `tokenUsage`, `lifecycle`. Tool calls and results pair by id.

### Provider formats (verified against real data)

| | Codex | Claude Code |
|---|---|---|
| Location | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` | `~/.claude/projects/<encoded-cwd>/<uuid>.jsonl` |
| Line discriminator | `type`: `session_meta` / `response_item` / `event_msg` | `type`: `user` / `assistant` / … |
| Tool call | `response_item` → `function_call` (`name`, `call_id`, `arguments`) | `assistant` block `tool_use` (`name`, `id`, `input`) |
| Tool result | `response_item` → `function_call_output` (by `call_id`) | `user` block `tool_result` (by `tool_use_id`) |
| Tokens | `event_msg` → `token_count` (`info.last_token_usage`) | `assistant` → `message.usage` |

Adding a provider: add a `ProviderKind` case and a `Provider` conformance.

## Status

Early scaffold: normalized model + Codex and Claude Code providers, verified
against on-disk sessions. Token totals are per-turn and provider-dependent, so
cross-provider token sums are approximate for now.

## Build & Run

```bash
swift build   # compile
swift run     # build and run
```
