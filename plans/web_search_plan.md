# Plan: Web Search for the Reading Companion

## Overview

Add model-initiated web search to the Reading Brain companion. When the user asks a factual book question or wants new-release discovery, the companion searches the live web, grounds its answer, and weaves facts in conversationally. Search fires **only when the model decides** (`tool_choice: auto`), never automatically.

**Architecture**: Keep DeepSeek `/v1/chat/completions` streaming. Implement a manual function-call tool loop where the model emits a `web_search` function call, the app executes it against **Tavily (keyless mode)** from the browser, feeds results back as a `role: tool` message, and the model answers. CORS verified working (`access-control-allow-origin` returned on preflight). No new API key, no backend, no provider SDK.

---

## Why this shape

| Considered | Chosen? | Reason |
|---|---|---|
| DeepSeek Responses API native `web_search` | No | Cleaner, but migrates the entire chat stream to a new SSE format. User chose to keep chat completions. |
| Tavily tool loop (this plan) | **Yes** | Stays on existing streaming path; search is app-orchestrated. |
| Keyless Tavily | **Yes** | No new secret in client code. Rate-limited but ample for a personal app. |

---

## New Files

### `lib/services/tavily_service.dart`

```dart
class TavilyService {
  Future<String> search(String query) async { ... }
}
```

- POST to `https://api.tavily.com/search`
- Headers: `Content-Type: application/json`, `X-Tavily-Access-Mode: keyless`
- Body: `{ query, search_depth: 'basic', max_results: 5 }`
- Returns a compact, LLM-ready string of top results (title, url, content snippet each), formatted like:
  ```
  [1] Title — url
      snippet
  ```
- Throws on non-200 (caller converts failure into a graceful tool error result)

---

## Modified Files

### `lib/constants/api_config.dart`

Add:

```dart
const tavilySearchEndpoint = 'https://api.tavily.com/search';
const tavilyMaxResults = 5;
const tavilySearchDepth = 'basic';
```

No key constant.

### `lib/services/ai_service.dart` — rework `sendMessageStream`

Current: single streaming request of one user message (`ai_service.dart:97`). New: a stream that internally runs the tool loop and yields the same chunks the caller already understands (`content` + `[USAGE:...]` sentinel), plus new `[SEARCHING:query]` / `[SEARCHED]` markers.

Request body gains:

```json
"tools": [{
  "type": "function",
  "function": {
    "name": "web_search",
    "description": "Search the live web for up-to-date factual information about books, authors, editions, publication dates, awards, or newly released titles. Use when the user asks a factual question you cannot answer reliably from memory, or wants book recommendations/announcements that may be newer than your knowledge cutoff.",
    "parameters": {
      "type": "object",
      "properties": {
        "query": { "type": "string", "description": "A concise, specific search query, e.g. \"Permutation City Greg Egan publication date\"" },
        "search_depth": { "type": "string", "enum": ["basic", "advanced"] },
        "max_results": { "type": "integer", "minimum": 1, "maximum": 5 }
      },
      "required": ["query"]
    }
  }
}]
```

Stream loop additions:
- While streaming, accumulate `delta.tool_calls` (arguments arrive fragmented across chunks: `index`, `id`, `function.name`, `function.arguments`).
- On `finish_reason == 'tool_calls'`: yield `[SEARCHING:<query>]`, execute Tavily search(es), append `{role: 'assistant', content: null, tool_calls: [...]}` + `{role: 'tool', tool_call_id, content: results}` to the messages array, send a **follow-up streaming request**, then yield `[SEARCHED]`.
- Handle **parallel tool calls** (iterate all calls) and **search failure** (feed a tool result like `"Search failed: <error>. Politely tell the user you couldn't look it up."` instead of crashing).
- Preserve existing `[USAGE:...]` emission on `finish_reason` in the final request.

Signature stays `Stream<String> sendMessageStream(String prompt)` — `chat_state` doesn't change its call shape.

### `lib/constants/system_prompt.dart` — add a `WEB SEARCH` section

New section, inserted before `## OPERATIONS` (persona rules only — no grammar change, `brain_parser.dart` untouched):

- **When to search**: factual book details (publication dates, editions, translators, award winners, author facts, correct spellings), and new-release / "what's coming out that fits my taste" discovery past the knowledge cutoff.
- **When not to search**: subjective taste/impressions, thematic cross-book discussion, anything answerable from the Reading Brain. If unsure, answer from memory first; only search when facts are at stake or recency matters.
- **Guardrail (critical)**: search results are **conversational grounding only — never evidence for OBSERVATION or PATCH blocks**. The confidence bands key exclusively off the user's own statements. Search-sourced facts must never be written into `CURRENT_READING` impression, `books`, or any profile field. A write trigger still fires only from what the *user* says.
- **Persona**: weave found facts in naturally, like a well-read friend who just double-checked — no "according to my search," no URL dumps. Mention a source lightly only when it genuinely strengthens the point (e.g., "the publisher's page says…").

### `lib/providers/chat_state.dart`

- Add `bool isWebSearching = false`.
- In `_generateResponse`'s stream loop (`chat_state.dart:299`), recognize `[SEARCHING:` / `[SEARCHED]` chunks before the block-detection branch: set the flag, call `notifyListeners()`, and **do not write them to the buffer**. On `[SEARCHING:...]`, `streamingContent` stays empty (so the UI shows the indicator, not the bare `TypingBubble`).
- Block-marker splitting, brain parsing, and `[USAGE:...]` token accounting are untouched.

### `lib/screens/chat_screen.dart`

At the streaming branch (`chat_screen.dart:218-226`): when `state.streamingContent` is empty **and** `state.isWebSearching`, render a subtle "looking that up…" line (styled with `AppTextStyles` body, muted color) instead of the bare `TypingBubble`. Keep `TypingBubble` for the pre-tool "thinking" phase.

---

## Verification

1. `flutter analyze` — no new warnings.
2. `flutter test` — placeholder smoke test still passes.
3. Manual on Chrome (`flutter run -d chrome`):
   - **Fact**: "When was *Permutation City* first published?" → indicator shows "looking that up…", answer states a date with natural phrasing, no URL dump.
   - **Discovery**: "What literary sci-fi came out in 2026 that fits my taste?" → search fires, answer ties new titles back to the Reader Profile.
   - **Non-trigger**: "Why did I like Borges so much?" → **no** search, pure brain conversation.
   - **Integrity**: ask a factual question, then check the Firestore brain document — no OBSERVATION/PATCH written from search-sourced facts.
   - **Failure path**: temporarily break the Tavily endpoint and confirm the companion responds gracefully.

---

## Risks & Mitigations

- **Keyless rate limits** → low for personal use; if exhausted, upgrade to an embedded Tavily key in `api_config.dart` (documented in `AGENTS.md` secrets note).
- **Model emits malformed tool args** → `max_results`/`search_depth` validated client-side with safe defaults; bad JSON → fallback query.
- **Search-sourced brain writes** → the system prompt guardrail + manual integrity check in Verification step 4.
- **Tool-loop streaming complexity** → the loop is confined to `ai_service.dart`; `chat_state` only learns two new markers.

---

## Not in Scope

- Always-on / user-toggled search UI (model-initiated only for now).
- Rendering search citations/links as clickable UI.
- Migrating to the Responses API native `web_search`.
- Server-side key proxying.
