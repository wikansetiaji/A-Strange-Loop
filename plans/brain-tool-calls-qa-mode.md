# Plan: Brain Updates as Tool Calls + QA Mode

## Summary

Migrate brain mutations from regex-parsed JSON text blocks to OpenAI-style function calling, and add a QA mode that uses separate Firestore collections (`meta_qa`/`sessions_qa`) and separate Hardcover credentials.

**Brain structure stays the same.** `models/brain.dart` is untouched. No UI changes — the user sees only visible prose, same as today.

---

## Phase A: QA Mode Infrastructure

### A1. Add `shared_preferences` dependency

Not currently present. Used to persist QA mode toggle across restarts.

```
flutter pub add shared_preferences
```

### A2. `lib/constants/hardcover_config_qa.dart` (new file)

Mirrors `hardcover_config.dart` but with QA credentials. Same proxy URL, different JWT/user ID.

```dart
const hardcoverApiKeyQa = 'eyJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJIYXJkY292ZXIiLCJ2ZXJzaW9uIjoiOCIsImp0aSI6IjQzZTFkNTg2LThiMmItNDFmMC1hYjNlLTI2ZTA5MTA1Njg0ZCIsImFwcGxpY2F0aW9uSWQiOjIsInN1YiI6IjE0MjU1MiIsImF1ZCI6IjEiLCJpZCI6IjE0MjU1MiIsImxvZ2dlZEluIjp0cnVlLCJpYXQiOjE3ODYwMTA1MDUsImV4cCI6MTgxNzU0NjUwNSwiaHR0cHM6Ly9oYXN1cmEuaW8vand0L2NsYWltcyI6eyJ4LWhhc3VyYS1hbGxvd2VkLXJvbGVzIjpbInVzZXIiXSwieC1oYXN1cmEtZGVmYXVsdC1yb2xlIjoidXNlciIsIngtaGFzdXJhLXJvbGUiOiJ1c2VyIiwiWC1oYXN1cmEtdXNlci1pZCI6IjE0MjU1MiJ9LCJ1c2VyIjp7ImlkIjoxNDI1NTJ9fQ.lzReFUELafOYZFry14YMsG9Zg_urUavBz7yIT68HTmg';
const hardcoverUserIdQa = '142552';
```

### A3. `lib/services/app_config.dart` (new file)

Singleton that controls QA vs production mode. Reads/writes flag to SharedPreferences.

```dart
class AppConfig {
  static final AppConfig _instance = AppConfig._();
  factory AppConfig() => _instance;

  bool isQaMode = false;

  String get metaColl     => isQaMode ? 'meta_qa'     : 'meta';
  String get sessionsColl => isQaMode ? 'sessions_qa' : 'sessions';

  String get hardcoverApiKey    => isQaMode ? hardcoverApiKeyQa  : hardcoverApiKey;
  String get hardcoverUserId    => isQaMode ? hardcoverUserIdQa  : hardcoverUserId;
  String get hardcoverEndpoint  => hardcoverApiEndpoint; // shared across both modes

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    isQaMode = prefs.getBool('qa_mode') ?? false;
  }

  Future<void> setQaMode(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('qa_mode', v);
    isQaMode = v;
  }
}
```

### A4. Parameterize `FirestoreService`

Add `collectionPrefix` parameter (default `''` for backward compat).

```dart
class FirestoreService {
  final String _collPrefix;

  FirestoreService({String collectionPrefix = ''}) : _collPrefix = collectionPrefix;

  String get _meta     => 'meta$_collPrefix';
  String get _sessions => 'sessions$_collPrefix';
}
```

Replace all 17 hardcoded `'meta'`/`'sessions'` string literals with `_meta`/`_sessions` getter calls.

**Affected paths:**
| Current | New |
|---------|-----|
| `meta/brain_json` | `$_meta/brain_json` |
| `meta/brain_json/patch_log/*` | `$_meta/brain_json/patch_log/*` |
| `meta/model_settings` | `$_meta/model_settings` |
| `sessions/{id}` | `$_sessions/{id}` |
| `sessions/{id}/messages/*` | `$_sessions/{id}/messages/*` |

### A5. Parameterize `HardcoverService`

Change from reading hardcoded top-level constants to accepting constructor injection:

```dart
class HardcoverService {
  final String apiKey;
  final String userId;
  final String apiEndpoint;

  HardcoverService({
    String? apiKey,
    String? userId,
    String? apiEndpoint,
  })  : apiKey = apiKey ?? hardcoverApiKey,
       userId = userId ?? hardcoverUserId,
       apiEndpoint = apiEndpoint ?? hardcoverApiEndpoint;
}
```

### A6. Parameterize `SyncService`

Same collection prefix treatment for its 4 Firestore paths:
- `meta/sync_queue` → `$_meta/sync_queue`
- `meta/sync_queue/items/*` → `$_meta/sync_queue/items/*`

### A7. Update `main.dart` wiring

```dart
void main() async {
  await AppConfig().load();

  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);

  final firestoreService = FirestoreService(
    collectionPrefix: AppConfig().isQaMode ? '_qa' : '',
  );
  final hardcoverService = HardcoverService(
    apiKey: AppConfig().hardcoverApiKey,
    userId: AppConfig().hardcoverUserId,
  );

  final chatState = ChatState(firestore: firestoreService);
  chatState.seedBrainIfNeeded();

  final syncService = SyncService(
    firestore: firestoreService,
    hardcover: hardcoverService,
  );
  chatState.initServices(
    hardcoverService: hardcoverService,
    syncService: syncService,
  );

  unawaited(syncService.startupReconcile().whenComplete(() {
    syncService.startPeriodicSync();
  }));

  runApp(ASLApp(chatState: chatState));
}
```

### A8. `ChatState` — accept `FirestoreService` via constructor

```dart
class ChatState extends ChangeNotifier {
  FirestoreService _firestore;
  // Remove: final FirestoreService _firestore = FirestoreService();

  ChatState({FirestoreService? firestore})
      : _firestore = firestore ?? FirestoreService();
```

Add `reloadWithQaMode()` method that:
1. Cancels old sync timer + listener
2. Creates new `FirestoreService`, `HardcoverService`, `SyncService` with QA credentials
3. Clears `_brainCache`, sessions, messages
4. Seeds QA brain from `assets/reading_brain.json` if `meta_qa/brain_json` doesn't exist
5. Runs startup reconcile + periodic sync for QA
6. Reloads sessions from `sessions_qa`
7. Notifies UI

### A9. Settings screen — QA toggle

- Wrapped in `if (kDebugMode)` — never appears in production builds
- `SwitchListTile` labeled "QA Mode"
- On toggle: confirmation dialog warning that sessions will reload
- On confirm: sets `AppConfig().setQaMode(v)`, then calls `chatState.reloadWithQaMode()`

---

## Phase B: Brain Tool Schemas

### B1. `lib/constants/brain_tools.dart` (new file)

Six tool definitions. All follow OpenAI function-calling format. Move `searchBooks` here from `hardcover_service.dart`.

#### 1. `searchBooks`
Unchanged — moved from `hardcover_service.dart` for consolidation.

#### 2. `appendBook`
```json
{
  "name": "appendBook",
  "description": "Add a new book to the Reading Brain. For Finished books, rating, personalSignificance, and whyItMatters are required by the handler.",
  "parameters": {
    "type": "object",
    "properties": {
      "title": {"type": "string"},
      "status": {"type": "string", "enum": ["Finished", "Reading", "Abandoned", "Want to Read"]},
      "rating": {"type": "number", "description": "0-5 with half-points"},
      "personalSignificance": {"type": "string", "description": "Vocabulary term"},
      "whyItMatters": {"type": "string", "description": "Why this book matters to the reader"},
      "hardcoverReview": {"type": "string", "description": "Public review, max ~500 chars"},
      "hardcoverSpoiler": {"type": "boolean"},
      "hardcoverId": {"type": "string"},
      "author": {"type": "string"},
      "coverUrl": {"type": "string"},
      "genres": {"type": "array", "items": {"type": "string"}},
      "pages": {"type": "integer"},
      "hardcoverUrl": {"type": "string"},
      "dateAdded": {"type": "string"},
      "dateRead": {"type": "string"},
      "hardcoverStatus": {"type": "string"},
      "progress": {"type": "string", "description": "e.g. '30%'"},
      "currentImpression": {"type": "string"},
      "readingStrategy": {"type": "string"},
      "abandonmentReason": {"type": "string"}
    },
    "required": ["title", "status"]
  }
}
```

#### 3. `updateBook`
```json
{
  "name": "updateBook",
  "description": "Replace an existing book entry by exact title match (targetTitle). The book object must contain the complete new state.",
  "parameters": {
    "type": "object",
    "properties": {
      "targetTitle": {"type": "string", "description": "Exact title of the book to replace"},
      "book": {
        "type": "object",
        "properties": { /* same as appendBook properties */ },
        "required": ["title", "status"]
      }
    },
    "required": ["targetTitle", "book"]
  }
}
```

#### 4. `deleteBook`
```json
{
  "name": "deleteBook",
  "description": "Remove a book from the Reading Brain by exact title match.",
  "parameters": {
    "type": "object",
    "properties": {
      "targetTitle": {"type": "string", "description": "Exact title of the book to delete"}
    },
    "required": ["targetTitle"]
  }
}
```

#### 5. `patchBrain`
```json
{
  "name": "patchBrain",
  "description": "Modify any section of the Reading Brain EXCEPT the book list. For book operations use appendBook/updateBook/deleteBook. replacementContent must be the COMPLETE new value — not a diff. Copy forward every existing value you are not intentionally changing.",
  "parameters": {
    "type": "object",
    "properties": {
      "targetSection": {
        "type": "string",
        "enum": [
          "META", "READER_PROFILE", "READER_PROFILE.CORE_PHILOSOPHY",
          "READER_PROFILE.THINGS_I_CONSISTENTLY_LOVE", "READER_PROFILE.NARRATIVE_PREFERENCES",
          "READING_MODES", "VOCABULARY", "FAVORITE_AUTHORS", "FAVORITE_BOOKS",
          "READER_BLIND_SPOTS", "READING_EVOLUTION", "ACTIVE_QUESTIONS",
          "CURRENT_READING", "RECOMMENDATION_QUEUE", "OBSERVATIONS"
        ]
      },
      "replacementContent": {
        "description": "Complete new value. Type depends on targetSection:\n- Object: META, READER_PROFILE, READER_PROFILE.NARRATIVE_PREFERENCES, READING_MODES, VOCABULARY, FAVORITE_AUTHORS, FAVORITE_BOOKS, READER_BLIND_SPOTS, RECOMMENDATION_QUEUE\n- Array: ACTIVE_QUESTIONS, READING_EVOLUTION, OBSERVATIONS\n- String: READER_PROFILE.CORE_PHILOSOPHY\n- Array of strings: READER_PROFILE.THINGS_I_CONSISTENTLY_LOVE\n- null: CURRENT_READING (to clear), or {book: {title, hardcoverId?}, progress: '30%'} to set"
      },
      "reason": {"type": "string"},
      "evidence": {"type": "string"},
      "confidence": {"type": "number", "description": "0.9-1.0:Certain, 0.7-0.89:Strong (>=0.8 required for PATCH). 0.4-0.69:Weak. <0.4: do not log."}
    },
    "required": ["targetSection", "replacementContent", "reason", "evidence", "confidence"]
  }
}
```

#### 6. `logObservation`
```json
{
  "name": "logObservation",
  "description": "Silently log a hypothesis about the reader. Not shown to the user. If 3 observations converge on the same hypothesis, call patchBrain instead (promotion rule).",
  "parameters": {
    "type": "object",
    "properties": {
      "evidence": {"type": "string"},
      "hypothesis": {"type": "string"},
      "confidence": {"type": "number", "description": "0.4-0.69 Weak, 0.7-0.89 Strong. Below 0.4 do not log."},
      "logged": {"type": "string", "description": "ISO date e.g. 2026-08-06"}
    },
    "required": ["evidence", "hypothesis", "confidence", "logged"]
  }
}
```

---

## Phase C: Tool Call Handlers in `chat_state.dart`

### C1. Five new handler methods

Each handler:
1. Fetches fresh brain from Firestore
2. Calls the corresponding static method on `BrainParser` (see Phase F)
3. Saves updated brain + log to Firestore
4. Updates `_brainCache` and calls `_parseCurrentReading`
5. Enqueues Hardcover sync items via `_sync.enqueueFromBrainMutation`
6. Drains sync queue
7. Returns **natural-language confirmation** string (not JSON)

```dart
Future<String> _handleAppendBook(Map<String, dynamic> args) async {
  // ... mutation via BrainParser.appendBook(...)
  // on success: return "Added 'Blindsight' to your brain. (Finished)"
  // on error:   return "Couldn't add that book: <reason>"
}
```

### C2. Refactor `_generateResponse` tool execution loop

Replace the single `searchBooks` dispatch with a switch handling all 6 tools:

```dart
for (final tc in toolRequests) {
  String toolResult;
  switch (tc.name) {
    case 'searchBooks':     toolResult = await _handleSearchBooks(tc.arguments); break;
    case 'appendBook':      toolResult = await _handleAppendBook(tc.arguments); break;
    case 'updateBook':      toolResult = await _handleUpdateBook(tc.arguments); break;
    case 'deleteBook':      toolResult = await _handleDeleteBook(tc.arguments); break;
    case 'patchBrain':      toolResult = await _handlePatchBrain(tc.arguments); break;
    case 'logObservation':  toolResult = await _handleLogObservation(tc.arguments); break;
    default:                toolResult = "Unknown tool: ${tc.name}";
  }
  apiMessages.add({
    'role': 'tool',
    'tool_call_id': tc.id,
    'content': toolResult,
  });
}
```

### C3. Tool execution UX indicator

When brain tools are called, show `'Updating brain...'` in `streamingContent` (same pattern as existing `'Searching Hardcover...'`).

### C4. Track whether mutations occurred this turn

Add boolean `_mutationsAppliedThisTurn` flag. Set by brain tool handlers. Checked in the final round to decide whether to emit `brainUpdated`/`hardcoverUpdated` status messages.

---

## Phase D: System Prompt Rewrite

### Remove (~200 lines)
- Block markers list (lines 338-344)
- APPEND_BOOK format & examples (354-391)
- UPDATE_BOOK format (393-408)
- DELETE_BOOK format (410-416)
- PATCH format & replacementContent type table (418-468)
- OBSERVATION format (470-479)
- Response shape rules (481-499)
- JSON validity / exact field rules (501-515)

### Add (~80 lines)
New `## TOOLS` section explaining:
- Available tools and when to call each
- Multiple tools in one response allowed
- Tool results fed back invisibly (acknowledge in prose when relevant)
- User never sees tool calls

### Rewrite (~40 lines)
- Write triggers (87-134): "emit block" → "call tool"
- Missing fields rule (192-207): "hold the block" → "don't call the tool, ask user"
- Observation promotion (305-335): "don't emit 4th observation" → "call patchBrain instead of logObservation"

### Keep (unchanged, ~300 lines)
- Opener, core philosophy (1-10)
- PERSONALITY & TONE (11-44)
- COMPANION MODE (45-79)
- Trigger semantics (87-180 — same intent, different mechanism)
- Non-triggers (182-190)
- Hardcover awareness (221-239)
- Static/Dynamic model semantics (241-267)
- Valid target sections (268-286)
- Confidence bands (290-299)
- Observation natural-language surfacing (209-219)
- Recommendation queue tiers (136-158)
- Guiding principle (518-519)

---

## Phase E: `chat_state.dart` Refactor

| Change | Lines affected |
|--------|---------------|
| Constructor accepts `FirestoreService` | ~17 |
| Remove `_findBlockMarker` + `_containsBlockMarker` | 554-563 |
| Remove block detection from streaming loop | 362-377 |
| Remove `BrainParser.parse()` call in final round | 467-471 |
| Register `BrainTools.all` instead of `[_hardcover.searchBooksTool]` | 335 |
| Tool execution loop — switch dispatch for 6 tools | 385-464 |
| Add 5 tool handler methods | new |
| Add `_mutationsAppliedThisTurn` flag logic | 509-538 |
| Add `reloadWithQaMode()` method | new |
| UI indicator for brain tool execution | in tool loop |

---

## Phase F: `BrainParser` Refactor

**Keep:** `OperationBlock`, `BrainUpdate`, `PatchLogEntry` classes, all mutation methods (`_applyJsonPatch`, `_deepMerge`, `_similarHypotheses`, `_todayString`).

**Remove:** `parse()` method (52-127), `_beginMarker` regex (48-49), `_blockTypes` map (40-46), `ParsedResponse` class (431-436).

**Add individual static methods** (called by both tool handlers and the existing `applyBlocks` wrapper):

```dart
static BrainUpdate appendBook(String brainJson, Map<String, dynamic> data)
static BrainUpdate updateBook(String brainJson, String targetTitle, Map<String, dynamic> data)
static BrainUpdate deleteBook(String brainJson, String targetTitle)
static BrainUpdate patchBrain(String brainJson, String section, dynamic content, {String? reason, double? confidence})
static BrainUpdate addObservation(String brainJson, Map<String, dynamic> data)
```

`applyBlocks(List<OperationBlock>)` becomes a thin wrapper calling these methods — kept for `sync_service.dart` compatibility.

---

## Phase G: Cleanup

- `brain_parser.dart`: remove `parse()`, `ParsedResponse`, marker regex/constants
- `system_prompt.dart`: remove block syntax sections, add tool usage section
- `chat_state.dart`: remove `_findBlockMarker`, `_containsBlockMarker`, block-buffer logic
- `hardcover_service.dart`: remove `searchBooksTool` getter (moved to `brain_tools.dart`)

---

## Phase H: Verification

```bash
cd a_strange_loop
flutter pub get
flutter analyze
flutter test
```

Manual QA checklist (in QA mode):
1. "I finished Blindsight. Rating 5, Permanent Sushi." → `appendBook` called with Finished + rating + personalSignificance, `patchBrain` clears CURRENT_READING
2. "I started Children of Time." → `patchBrain` sets CURRENT_READING, no book created
3. "I'm at 30%." → `patchBrain` updates CURRENT_READING.progress only
4. "I want to read Permutation City." → `appendBook` called with Want to Read
5. "DNF'd Foundation." → `appendBook` called with Abandoned, `patchBrain` clears CURRENT_READING
6. Multi-tool response: "I finished Book A and started Book B" → 2+ tools in one turn
7. Observation promotion: 3 logObservations with similar hypothesis → patchBrain called instead of 4th observation
8. Verify all data goes to `meta_qa` / `sessions_qa` collections
9. Toggle QA off → production collections work as before
10. Verify no UI regressions — prose looks exactly the same as before

---

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|-----------|
| AI behavior drift — tool calls produce different mutations than text blocks | **High** | QA mode lets you A/B test before deploying to production |
| `replacementContent` type mismatch in `patchBrain` (typed as `object` in schema) | Medium | Handler validates type; returns error message; AI retries next turn |
| Multiple brain tools exceed 3-round tool call limit | Low | `maxToolCallRounds` can be increased to 5 if needed |
| QA toggle reinitialization fails partway through | Medium | Wrap in try/catch; revert QA flag on failure |
| Token overhead from 6 tool schemas | Low | Removed block syntax ~3-4K tokens vs. tool schemas ~2-3K tokens (net neutral) |

---

## Files Changed

| File | Change Type |
|------|------------|
| `pubspec.yaml` | Add `shared_preferences` |
| `lib/main.dart` | Wire AppConfig, inject services |
| `lib/constants/hardcover_config_qa.dart` | **New** |
| `lib/services/app_config.dart` | **New** |
| `lib/constants/brain_tools.dart` | **New** |
| `lib/services/firestore_service.dart` | Collection prefix parameter |
| `lib/services/hardcover_service.dart` | Constructor injection |
| `lib/services/sync_service.dart` | Collection prefix |
| `lib/services/brain_parser.dart` | Extract individual methods, remove `parse()` |
| `lib/providers/chat_state.dart` | Constructor, tool handlers, `_generateResponse` refactor, `reloadWithQaMode` |
| `lib/constants/system_prompt.dart` | Remove block syntax, add tool usage section |
| `lib/screens/settings_screen.dart` | QA toggle (debug only) |
