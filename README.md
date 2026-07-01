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

## Requirements

macOS 14 or later. AGANAL is a native Swift 6 / SwiftUI app and is macOS-only —
there is no cross-platform port.

## Build & run from source

```bash
swift build   # compile
swift run     # build and run
```

## Install as an app

Wrap the binary in a proper `.app` bundle (Dock icon, Finder-launchable):

```bash
scripts/make-app.sh          # → build/AGANAL.app
scripts/install.sh           # build, sign, and install into /Applications
```

`install.sh` ad-hoc signs by default; pass `SIGN_ID="Developer ID Application: …"`
to sign with a real identity.

## Distribution

AGANAL ships like a normal Mac app: a universal, Developer ID–signed, **notarized
`.dmg`** published on GitHub Releases, with the website linking to the latest one.

```bash
scripts/make-dmg.sh          # universal build → signed + notarized AGANAL.dmg → docs/version.json
gh release create v0.1 build/dist/AGANAL.dmg -t "AGANAL v0.1"
```

`make-dmg.sh` needs a *Developer ID Application* certificate and notarization
credentials (a `notarytool` keychain profile via `NOTARY_PROFILE`, an app-specific
password stored as `AGANAL-ASC`, or `AC_PASS` in the environment). App metadata
lives in `Resources/Info.plist`; the icon is `Sources/Resources/AppIcon.icns`.

## Command-line tool

AGANAL is also a self-documenting CLI, so an agent (or you) can just shell out to
it — no server to configure. It prints JSON to stdout:

```bash
swift run AGANAL --help                                 # from source
/Applications/AGANAL.app/Contents/MacOS/AGANAL --help   # from an installed build
```

Commands: `sources`, `sessions`, `search <query>`, `analytics <path>`,
`events <path>`, `overview` — run `aganal <command> --help` for options. The
usual flow is to find a session and analyze it; the provider is inferred from the
path:

```bash
aganal sessions --limit 1       # newest session — note its "path"
aganal analytics <path>         # full analytics for it
aganal search "auth" --content  # find sessions mentioning "auth"
```

## MCP server

The same operations are available over the
[Model Context Protocol](https://modelcontextprotocol.io), so an MCP client can
query your session analytics directly. Run it with the `mcp` subcommand — it
speaks JSON-RPC over stdio and reuses the same providers and analysis as the app:

```bash
swift run AGANAL mcp                                   # from source
/Applications/AGANAL.app/Contents/MacOS/AGANAL mcp     # from an installed build
```

Register it with a client (e.g. Claude Desktop / Claude Code):

```json
{
  "mcpServers": {
    "aganal": {
      "command": "/Applications/AGANAL.app/Contents/MacOS/AGANAL",
      "args": ["mcp"]
    }
  }
}
```

Tools: `list_sources`, `list_sessions`, `search_sessions`, `session_analytics`,
`session_events`, `overview`. Every session a tool returns carries its absolute
`path`, and the same file is exposed as the resource `aganal://session/<path>` —
so the AI can use these tools or open the raw log directly.
