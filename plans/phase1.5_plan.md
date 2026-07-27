# Phase 1.5: Chat History Compression via Summarization

**Goal:** Cap input token cost by summarizing older chat messages when the prompt exceeds a configurable token budget. Older messages are replaced with a compressed summary; recent messages stay verbatim.

**Date:** 2026-07-27

---

## Problem

Each API call sends the full prompt: system prompt (~3K tokens) + brain (~2K tokens) + **entire chat history (grows unbounded)**. DeepSeek v4 Flash has a 1M context window so it _always works_, but the per-request token cost grows linearly with chat length — you're repeatedly paying to send the same old messages.

## Solution

Before each API call, estimate the total input token count using `tiktoken`. If it exceeds `maxInputTokens`, call the **same DeepSeek model** with a summarization prompt to compress older messages. The compressed summary replaces those older messages in the prompt sent to the main API call. The UI message list is never truncated — the user always sees the full chat history.

---

## Configuration

**`lib/constants/api_config.dart`** — add:

```dart
const maxInputTokens = 32000;
const keepRecentMessages = 12;   // last 6 user+assistant pairs kept verbatim
```

### Token Budget Breakdown (32K limit)

| Component | Approx. tokens |
|-----------|---------------|
| System prompt | ~3,000 |
| Reading brain | ~2,000 |
| Reserved output (`max_tokens`) | 4,096 |
| **Budget for chat history** | **~22,900** |
| Estimated per exchange (pair) | ~300–600 tokens |
| Exchanges before compression kicks in | **~40–75** |

Most sessions won't hit compression at all. Long sessions (40+ exchanges) will, but still have 12 messages (6 pairs) of verbatim context.

---

## Dependencies

Add to `pubspec.yaml`:
```yaml
dependencies:
  tiktoken: ^1.0.0   # pure Dart, MIT license, cl100k_base encoding
```

---

## Step-by-Step Tasks

### 1. New File: Token Counter Utility

**`lib/utils/token_counter.dart`**

```dart
import 'package:tiktoken/tiktoken.dart';

class TokenCounter {
  static Encoding? _encoding;

  static Encoding get encoding {
    _encoding ??= getEncoding('cl100k_base');
    return _encoding!;
  }

  static int count(String text) => encoding.encode(text).length;
}
```

`cl100k_base` is GPT-4/Claude's encoding. DeepSeek uses its own BPE tokenizer but the count will be close enough for budget decisions (the actual token count from the API response remains the source of truth for the footer).

### 2. New Method: Summarization API Call

**`lib/services/ai_service.dart`** — add to `AIService`:

```dart
Future<String> summarize(String textToSummarize) async {
  final request = http.Request('POST', Uri.parse(deepseekApiEndpoint));
  request.headers.addAll({
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $deepseekApiKey',
  });
  request.body = jsonEncode({
    'model': deepseekModel,
    'messages': [
      {
        'role': 'system',
        'content': 'Summarize the following conversation concisely. '
            'Preserve:\n'
            '- Books discussed (titles, authors, key details)\n'
            '- Reading recommendations given or considered\n'
            '- User\'s expressed preferences, opinions, or shifts in taste\n'
            '- Key decisions or conclusions\n'
            '- Active questions or ongoing threads\n'
            'Output only the summary, no preamble.',
      },
      {'role': 'user', 'content': textToSummarize},
    ],
    'temperature': 0.3,
    'max_tokens': 2048,
    'stream': false,
  });

  final response = await _client.send(request);
  if (response.statusCode != 200) {
    final body = await response.stream.bytesToString();
    throw Exception('Summarization error ${response.statusCode}: $body');
  }

  final body = await response.stream.bytesToString();
  final json = jsonDecode(body) as Map<String, dynamic>;
  final choices = json['choices'] as List;
  return choices[0]['message']['content'] as String;
}
```

Non-streaming, temperature 0.3 for consistent summaries, max 2048 output tokens.

**Summarization prompt** is intentionally focused on the reading companion domain (books, recommendations, preferences, questions).

### 3. Compression Logic in ChatState

**`lib/providers/chat_state.dart`** — new fields:

```dart
String? _conversationSummary;     // accumulated compressed history
int _lastSummarizedIndex = 0;     // index of last message included in summary
bool isCompressing = false;       // UI flag for "Compressing..." indicator
```

New getter:
```dart
bool get isSummaryActive => _conversationSummary != null;
```

**Modified `sendMessage()` flow:**

```dart
Future<void> sendMessage(String text) async {
  final userMsg = Message(role: 'user', content: text);
  messages.add(userMsg);
  streamingContent = '';
  error = null;
  isLoading = true;
  notifyListeners();

  try {
    final brain = await _getBrain();

    // --- NEW: maybe compress ---
    final compressed = await _maybeCompress(brain);
    final prompt = _buildPrompt(brain, compressed);

    // ... rest is unchanged (streaming, etc.)
  } catch (e) {
    // ... unchanged
  }
}
```

**New method `_maybeCompress()`:**

```dart
/// Returns the list of messages to include in the prompt.
/// May be [messages] as-is, or [summary pseudo-message] + recent messages.
Future<List<Message>> _maybeCompress(String brain) async {
  final fullPrompt = _buildPrompt(brain, messages);
  final totalTokens = TokenCounter.count(fullPrompt);

  if (totalTokens <= maxInputTokens) {
    return messages; // no compression needed
  }

  final cutOff = (messages.length - keepRecentMessages)
      .clamp(0, messages.length);

  if (_lastSummarizedIndex >= cutOff && _conversationSummary != null) {
    // Already summarized up to this point; just use existing summary
    return [
      Message(role: 'system', content: _conversationSummary!),
      ...messages.sublist(cutOff),
    ];
  }

  isCompressing = true;
  notifyListeners();

  try {
    // Collect new messages to summarize
    final newMessages = messages.sublist(_lastSummarizedIndex, cutOff);
    final newText = newMessages
        .map((m) =>
            '${m.role == 'user' ? 'User' : 'Assistant'}: ${m.content}')
        .join('\n\n');

    final textToSummarize = _conversationSummary != null
        ? 'Existing summary:\n$_conversationSummary\n\n'
            'New messages to add:\n$newText'
        : newText;

    _conversationSummary = await _ai.summarize(textToSummarize);
    _lastSummarizedIndex = cutOff;
  } catch (e) {
    // Fallback: drop oldest messages, keep what fits
    _conversationSummary = null;
    _lastSummarizedIndex = cutOff;
  } finally {
    isCompressing = false;
  }

  return [
    if (_conversationSummary != null)
      Message(role: 'system', content: _conversationSummary!),
    ...messages.sublist(cutOff),
  ];
}
```

**Modified `_buildPrompt()`:**

```dart
String _buildPrompt(String brain, List<Message> msgs) {
  final historyParts = <String>[];

  for (final m in msgs) {
    if (m.role == 'system') {
      // Summary pseudo-message — placed in a "Conversation Summary" section
      historyParts.add('## Conversation Summary\n\n${m.content}');
    } else {
      historyParts
          .add('${m.role == 'user' ? 'User' : 'Assistant'}: ${m.content}');
    }
  }

  final history = historyParts.join('\n\n');

  return '$companionSystemPrompt\n\n---\n\n$brain\n\n---\n\n'
      '## Chat History\n\n$history';
}
```

This preserves the existing prompt format — summary goes under `## Chat History` as a `## Conversation Summary` subheading, followed by `User:`/`Assistant:` pairs for recent messages. The LLM treats it as natural context.

### 4. UI Updates

**`lib/screens/chat_screen.dart`**

**Typing indicator** (around line 240): Distinguish compression from thinking:

```dart
Widget _buildTypingIndicator() {
  return Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Consumer<ChatState>(
      builder: (context, state, _) {
        final label = state.isCompressing
            ? 'Compressing conversation history...'
            : 'Thinking...';
        return Row(
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withAlpha(60),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(120),
                  fontStyle: FontStyle.italic,
                )),
          ],
        );
      },
    ),
  );
}
```

**Token footer** (around line 267): Show when history is summarized:

```dart
Widget _buildTokenFooter() {
  return Consumer<ChatState>(
    builder: (context, state, _) {
      if (state.messages.isEmpty) return const SizedBox.shrink();
      final suffix = state.isSummaryActive ? ' (summarized)' : '';

      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Text(
          '${state.messages.length} messages$suffix · ${state.formattedSessionTokens}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withAlpha(100),
          ),
        ),
      );
    },
  );
}
```

**Input disable:** Already covered — the existing `state.isLoading` check also blocks input during compression since `isCompressing` keeps `isLoading = true`.

---

## Data Flow (with compression active)

```
User sends message
  → ChatState.sendMessage(text):
    1. Add user message to messages list (intact)
    2. Set isLoading = true, notify (UI shows typing indicator)
    3. Fetch brain
    4. Estimate token count via tiktoken (system + brain + all messages)
    5. OVER LIMIT:
       → isCompressing = true (UI shows "Compressing...")
       → Collect unsummarized older messages
       → Call ai.summarize() (separate API call, non-streaming)
       → Store _conversationSummary, update _lastSummarizedIndex
       → isCompressing = false
    6. Build compressed prompt:
       system + brain + "## Conversation Summary\n[summary]\n\nUser: ..."
    7. Call main AI → stream response → display
    8. Full messages list unchanged in UI
```

---

## Edge Cases

| Case | Behavior |
|------|----------|
| Summarization API fails | Drop oldest messages (truncation fallback). `_conversationSummary` set to null to avoid corrupt summary. |
| Even compressed prompt exceeds limit | Further trim `_conversationSummary` text (keep last N chars that fit under budget). Rare at 32K limit. |
| First message / few messages | No compression — `_maybeCompress()` returns messages as-is. |
| Very long single message (e.g., pasted book text) | Still gets summarized. If a single message alone exceeds budget, it's kept verbatim and older messages are dropped. |
| Conversation resets (page refresh) | All state lost — `_conversationSummary`, `_lastSummarizedIndex`, and `messages` are ephemeral (same as current behavior). |

---

## Files Changed

| File | Change |
|------|--------|
| `pubspec.yaml` | Add `tiktoken` dependency |
| `lib/utils/token_counter.dart` | **NEW** — `TokenCounter.count()` using `cl100k_base` |
| `lib/constants/api_config.dart` | Add `maxInputTokens = 32000`, `keepRecentMessages = 12` |
| `lib/services/ai_service.dart` | Add `summarize(String)` non-streaming method |
| `lib/providers/chat_state.dart` | Add `_conversationSummary`, `_lastSummarizedIndex`, `isCompressing`, `isSummaryActive`, `_maybeCompress()`, modify `_buildPrompt()` and `sendMessage()` |
| `lib/screens/chat_screen.dart` | Update typing indicator label, update token footer |

---

## What Phase 1.5 Does NOT Include

- Session persistence (Phase 2)
- Block parsing (Phase 3)
- Brain editing UI (Phase 3)
- Multi-turn API usage (still single user message with concatenated prompt)
- Persisting summaries across sessions (lost on refresh, same as messages)
- Manual "summarize this" button (automatic only)
- Model switching for summarization (same DeepSeek v4 Flash)

---

## Estimated Effort

| Task | Estimate |
|:---|:---|
| Add `tiktoken` dependency + token counter utility | 15 min |
| Add summarization method to AI service | 30 min |
| Implement compression logic in ChatState | 1 hour |
| Update UI (indicators, footer) | 30 min |
| Manual testing (short + long sessions) | 30 min |
| **Total** | **~2.5 hours** |

---

## Verification

After implementation, test:

1. **Short session (< 30 exchanges):** No compression triggered. Footer never shows "(summarized)."
2. **Long session (40+ exchanges):** Compression triggers automatically. Footer shows "(summarized)." User sees "Compressing..." briefly before response streams.
3. **Continuity check:** After compression, ask "what was that book you recommended earlier?" — the summary should preserve enough context for the LLM to answer.
4. **Fallback:** Temporarily set `maxInputTokens = 500` to force compression on every message. Verify it doesn't break.
5. **Token display:** Footer continues to show accurate cumulative token counts from API responses.
