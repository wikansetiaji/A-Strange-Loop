# Phase 3: Block Parsing & Brain Mutations

## Overview

The AI companion already emits structured operation blocks (`BEGIN_APPEND_BOOK`, `BEGIN_UPDATE_BOOK`, `BEGIN_PATCH`, etc.) — but they're displayed verbatim to the user and the brain is never updated. Phase 3 parses and strips these blocks from the visible response, applies the corresponding mutations to `reading_brain.md` in Firestore, and logs the changes to an audit trail.

---

## Architecture

### Response Flow

```
Streaming response arrives chunk-by-chunk from DeepSeek
         │
         ▼
┌─ Check accumulated content for BEGIN_ marker
│    ├── Not found: yield chunk to UI as normal (prose)
│    └── Found: trim visible content, suppress remainder into buffer
│
▼ (stream complete)
│
┌─ BrainParser.parse(fullResponse)
│    └── (String prose, List<Block> blocks)
│
├── blocks.isEmpty?
│    └── Yes: proceed as before (save prose, display, done)
│
├── blocks.isNotEmpty:
│    ├── BrainParser.applyBlocks(brain, blocks) → (updatedBrain, logEntries)
│    ├── FirestoreService.updateBrain(updatedBrain)
│    ├── FirestoreService.writePatchLog(logEntries) → meta/brain/patch_log/
│    ├── Invalidate _brainCache + re-parse CURRENT_READING
│    ├── Save prose-only as assistant message to Firestore
│    └── Display prose to user (blocks never shown)
```

### Streaming Suppression

The system prompt enforces: **prose first, blocks last**, with no interleaving. So detection is a one-way transition:

1. Stream chunks normally, yielding each to the UI
2. Maintain a trailing buffer of the last ~30 chars of accumulated content
3. Before yielding a chunk, check if `(trailing buffer + new chunk)` contains a known `BEGIN_` marker (`BEGIN_APPEND_BOOK`, `BEGIN_UPDATE_BOOK`, `BEGIN_DELETE_BOOK`, `BEGIN_PATCH`, `BEGIN_OBSERVATION`)
4. When detected → trim the partial marker from visible text, suppress all subsequent chunks
5. After stream ends → parse blocks from the full buffered response

**Edge case accepted**: if a chunk boundary splits the word `BEGIN_UPDATE_BOOK` (e.g., chunk 1 yields `BEG`, chunk 2 yields `IN_UPDATE_BOOK`), the user briefly sees `BEG` before the next chunk triggers detection and trimming.

---

## Data Model

### patch_log Subcollection

Each brain mutation logs a new document under `meta/brain/patch_log/{autoId}`:

| Field | Type | Notes |
|---|---|---|
| `timestamp` | `Timestamp` | `serverTimestamp` |
| `operation` | `String` | `"APPEND_BOOK"` \| `"UPDATE_BOOK"` \| `"DELETE_BOOK"` \| `"PATCH"` \| `"OBSERVATION"` |
| `target` | `String` | Book title (for BOOK ops) or section name (for PATCH) |
| `reason` | `String?` | From the block's `Reason` field (PATCH only) |
| `confidence` | `double?` | From the block's `Confidence` field (PATCH/OBSERVATION only) |

### Existing Brain Doc (`meta/brain`) — Unchanged

No new fields. The `markdown_content` field holds the updated brain. `patch_log` lives as a separate subcollection.

---

## New File: `lib/services/brain_parser.dart`

### `class OperationBlock`

```dart
enum BlockType { appendBook, updateBook, deleteBook, patch, observation }

class OperationBlock {
  final BlockType type;
  final Map<String, String> fields;  // key-value pairs from the block
  final String rawText;              // full block text (start to end markers)
}
```

### `class ParsedResponse`

```dart
class ParsedResponse {
  final String prose;                 // everything outside blocks
  final List<OperationBlock> blocks;
}
```

### `class PatchLogEntry`

```dart
class PatchLogEntry {
  final String operation;
  final String target;
  final String? reason;
  final double? confidence;
  // toMap() for Firestore serialization
}
```

### Static Methods

#### `ParsedResponse parse(String rawResponse)`

1. Use a single regex pattern that matches all five block types:
   ```
   (BEGIN_APPEND_BOOK\n.*?\nEND_APPEND_BOOK|
    BEGIN_UPDATE_BOOK\n.*?\nEND_UPDATE_BOOK|
    BEGIN_DELETE_BOOK\n.*?\nEND_DELETE_BOOK|
    BEGIN_PATCH\n.*?\nEND_PATCH|
    BEGIN_OBSERVATION\n.*?\nEND_OBSERVATION)
   ```
   With `dotAll: true` (`s` flag) since blocks span multiple lines.

2. Extract prose: remove all block matches from the raw response, trim whitespace, collapse double newlines within the prose.

3. Parse each block into an `OperationBlock`:
   - **BOOK blocks** (`APPEND`, `UPDATE`, `DELETE`): parse `# BOOK` section into key-value pairs (`Title:`, `Status:`, `Rating:`, etc.) by splitting on `\n` and matching `^Key:\s*\n\s*Value`. For UPDATE/DELETE, also extract `Target Title:`.
   - **PATCH blocks**: parse `Reason:`, `Evidence:`, `Confidence:`, `Target Section:`, and `Replacement Content:` (the body after `Replacement Content:` up to `END_PATCH`).
   - **OBSERVATION blocks**: parse `Evidence:`, `Hypothesis:`, `Confidence:`, `Logged:`.

4. Return `ParsedResponse(prose, blocks)`.

#### `(String updatedBrain, List<PatchLogEntry> log) applyBlocks(String brain, List<OperationBlock> blocks)`

Apply blocks sequentially to a mutable copy of the brain. For each block:

**APPEND_BOOK**:
- Locate the `## BOOKS` header
- Find the insertion point: after the last `# BOOK` entry (or after the CRUD-territory comment line if no entries exist)
- Insert the new `# BOOK` entry with a `---` separator above it
- Log: `PatchLogEntry("APPEND_BOOK", title)`

**UPDATE_BOOK**:
- Extract `Target Title` from fields
- Find the `# BOOK` entry whose `Title:` field matches exactly (case-sensitive, trimming whitespace)
- If not found → skip (log nothing, but note warning for debugging)
- Replace the entire entry (from `# BOOK` line to the next `---` or end of BOOKS section)
- Log: `PatchLogEntry("UPDATE_BOOK", title)`

**DELETE_BOOK**:
- Extract `Target Title`, find matching entry → remove entire entry including its `---` separator
- If not found → skip
- Log: `PatchLogEntry("DELETE_BOOK", title)`

**PATCH**:
- Parse `Target Section`; handle dotted targets: `SECTION.SUBSECTION` → locate `## SECTION`, then `### Subsection` within it. Non-dotted: locate `## SECTION` directly.
- If target header not found → skip
- Find the section body: everything between the target header and the next same-or-higher-level header (next `## ` or `# `) or end of document
- Replace with `Replacement Content`
- If `Evidence` field cites specific OBSERVATION entries (detect by `Logged:` dates in the evidence text), remove those entries from the `## OBSERVATIONS` section
- Log: `PatchLogEntry("PATCH", targetSection, reason, confidence)`

**OBSERVATION**:
- Locate `## OBSERVATIONS` header
- If section contains the placeholder text `(No observations logged yet. ...)`, replace it with the observation entry
- Otherwise, append as a new `---` separated entry at the end of the section (before any `(empty)` marker)
- Log: `PatchLogEntry("OBSERVATION", hypothesis, null, confidence)`

**Return**: the fully mutated brain string + list of log entries.

---

## File Changes

### `lib/services/firestore_service.dart` — Two New Methods

```dart
/// Writes updated brain + patch log entries in a single batch.
Future<void> updateBrain(
    String markdownContent,
    List<Map<String, dynamic>> patchLogEntries) async {
  final batch = _firestore.batch();
  final brainRef = _firestore.collection('meta').doc('brain');

  batch.set(brainRef, {
    'markdown_content': markdownContent,
    'updated_at': FieldValue.serverTimestamp(),
    'book_count': _countBooks(markdownContent),
  }, SetOptions(merge: true));

  for (final entry in patchLogEntries) {
    final docRef = brainRef.collection('patch_log').doc();
    batch.set(docRef, {
      ...entry,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  await batch.commit();
}
```

```dart
/// Fetch patch log entries (for optional debug/audit display).
Future<List<Map<String, dynamic>>> getPatchLog() async { ... }
```

### `lib/providers/chat_state.dart` — Integration

#### New imports

```dart
import 'package:a_strange_loop/services/brain_parser.dart';
```

#### Modified `sendMessage()` method

In the streaming section (around line 199), add suppression logic:

```dart
bool _blocksDetected = false;
StringBuffer _blockBuffer = StringBuffer();
String _visibleBuffer = '';   // what the user sees
String _trailingWindow = '';  // last ~30 chars for BEGIN_ detection

await for (final chunk in _ai.sendMessageStream(prompt)) {
  if (chunk.startsWith('[USAGE:')) {
    // ... existing usage parsing ...
  } else {
    if (_blocksDetected) {
      _blockBuffer.write(chunk);  // silently buffer
      continue;
    }

    _trailingWindow += chunk;
    if ((_trailingWindow + chunk).contains('BEGIN_') &&
        _matchesBlockMarker(_trailingWindow)) {
      // Detect which marker and trim
      final beforeBlock = _extractProseBeforeBlock(_trailingWindow);
      _visibleBuffer += beforeBlock;
      _blockBuffer.write(_trailingWindow.substring(beforeBlock.length));
      _blocksDetected = true;
    } else {
      _visibleBuffer += chunk;
    }
    streamingContent = _visibleBuffer;
    _throttledNotify();
  }
}
```

#### After stream completes (replace the existing `_persistAfterResponse` logic):

```dart
final content = buffer.toString();
final parsed = BrainParser.parse(content);
final prose = parsed.prose.isNotEmpty ? parsed.prose : content;

// Save the prose-only version as the assistant message
final assistantMsg = Message(
  role: 'assistant',
  content: prose,
  order: messages.length,
);
messages.add(assistantMsg);
streamingContent = null;
isLoading = false;

await _persistAfterResponse(userMsg, assistantMsg);

// Apply blocks if any
if (parsed.blocks.isNotEmpty) {
  try {
    final brain = await _getBrain();  // re-read fresh from Firestore
    final (updatedBrain, logEntries) = BrainParser.applyBlocks(brain, parsed.blocks);
    await _firestore.updateBrain(updatedBrain, logEntries);
    _brainCache = updatedBrain;
    _brainFetchedAt = DateTime.now();
    _parseCurrentReading(updatedBrain);
  } catch (e) {
    // Log error but don't block the UI — prose was already displayed
    debugPrint('BrainParser error: $e');
  }
}

notifyListeners();
```

#### Helper methods to add:

```dart
static final _blockMarkers = [
  'BEGIN_APPEND_BOOK',
  'BEGIN_UPDATE_BOOK',
  'BEGIN_DELETE_BOOK',
  'BEGIN_PATCH',
  'BEGIN_OBSERVATION',
];

bool _matchesBlockMarker(String text) =>
    _blockMarkers.any((m) => text.contains(m));

String _extractProseBeforeBlock(String text) {
  int? earliestIndex;
  for (final marker in _blockMarkers) {
    final idx = text.indexOf(marker);
    if (idx != -1 && (earliestIndex == null || idx < earliestIndex)) {
      earliestIndex = idx;
    }
  }
  return earliestIndex != null ? text.substring(0, earliestIndex) : text;
}
```

### `lib/constants/api_config.dart`

No changes needed.

---

## Block Format Reference

### APPEND_BOOK
```
BEGIN_APPEND_BOOK
# BOOK
Title:
Permutation City
Status:
Finished
Rating:
5
Personal Significance:
Permanent Sushi
Why It Matters:
Relentless exploration of one premise.
END_APPEND_BOOK
```

### UPDATE_BOOK
```
BEGIN_UPDATE_BOOK
Target Title: The Glass Bead Game
# BOOK
Title:
The Glass Bead Game
Status:
Reading
Progress:
40%
Current Impression:
Starting to see the shape.
Reading Strategy:
Trust accumulation.
END_UPDATE_BOOK
```

### DELETE_BOOK
```
BEGIN_DELETE_BOOK
Target Title: The City & the City
END_DELETE_BOOK
```

### PATCH
```
BEGIN_PATCH
Reason: Progress update per sync rule.
Evidence: User reports 20% progress.
Confidence: 0.95
Target Section: CURRENT_READING
Replacement Content:
Book:
The Glass Bead Game
Progress:
20%
Current Reading Strategy:
Dreamy flow. Still ask questions.
END_PATCH
```

### OBSERVATION
```
BEGIN_OBSERVATION
Evidence: User wanted more character depth in a premise-driven novel.
Hypothesis: Undervalues character-driven stories blind spot may be softening.
Confidence: 0.55
Logged: 2026-07-27
END_OBSERVATION
```

---

## Task Breakdown (Implementation Order)

### Task 1: `brain_parser.dart` — Core Parser
- `ParsedResponse parse(String)` — regex extraction of all five block types
- Block type detection and field parsing for each block format
- Unit-testable: pure functions, no side effects

### Task 2: `brain_parser.dart` — Mutation Engine
- `applyBlocks(String brain, List<Block>)` — apply all block types sequentially
- `### BOOK` section manipulation (append/update/delete)
- `## SECTION` header-scoped replacement for PATCH
- Dotted target support (`SECTION.SUBSECTION` → `### Subsection` lookup)
- OBSERVATION append + consumption on PATCH
- Return `(updatedBrain, List<PatchLogEntry>)`

### Task 3: `firestore_service.dart` — Brain Write
- `updateBrain(markdownContent, patchLogEntries)` method
- Batch write to `meta/brain` + `meta/brain/patch_log/{autoId}` subcollection

### Task 4: `chat_state.dart` — Streaming Suppression
- Add `_blocksDetected`, `_blockBuffer`, trailing-window detection
- `_matchesBlockMarker()` and `_extractProseBeforeBlock()` helpers
- Trim visible content mid-stream when block marker detected

### Task 5: `chat_state.dart` — Post-Stream Block Application
- Call `BrainParser.parse()` after stream completes
- Apply blocks via `BrainParser.applyBlocks()`
- Write brain via `FirestoreService.updateBrain()`
- Invalidate `_brainCache` + re-parse `CURRENT_READING`
- Save prose-only to Firestore as assistant message

### Task 6: Edge Cases & Error Handling
- Blocks present but no prose → still display something (fallback or empty confirmation)
- Malformed block (missing end tag) → skip that block, continue with others
- PATCH to nonexistent section → skip, log warning
- Firestore write fails → log, don't crash, prose was already displayed
- Multiple blocks of same type in one response → process all in order
- Empty book title → skip

### Task 7: Testing
- Test `BrainParser.parse()` with known-good responses containing all block types
- Test `BrainParser.applyBlocks()` against the current `reading_brain.md`
- Manual test: send "i just reached 20%" in chat, verify brain updated + prose displayed without blocks

---

## Not in Scope (Future Phases / Iterations)

- Length-delta guard (skipped per discussion)
- Displaying `patch_log` entries in the UI (auditable but not yet surfaced)
- Diff viewer for brain changes
- Block confidence validation (trust the LLM for now)
- Session-scoped brain snapshots (tracking which session caused which brain change)
