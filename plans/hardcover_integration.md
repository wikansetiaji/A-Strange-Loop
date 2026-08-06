# Hardcover.app Integration Plan

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         Chat AI                                   │
│   (reads merged brain, emits JSON blocks, uses tools)             │
└──────┬───────────────┬─────────────────────────────┬─────────────┘
       │               │                             │
       │ tool calls    │ writes immediately           │ review push
       ▼               ▼                             │
┌──────────────┐ ┌──────────────────────────────┐    │
│ searchBooks  │ │ Reading Brain (Firestore)    │ ◄──┤
│ (Hardcover)  │ │ meta/brain_json              │    │
└──────┬───────┘ │ (includes hardcoverId)        │    │
       │         └──────┬───────────────────────┘    │
       │                │ on brain mutation           │
       │                ▼                             │
       │         ┌──────────────────────────────┐    │
       │         │ Sync Queue (Firestore)       │    │
       │         │ meta/sync_queue/{id}         │    │
       │         │ { action, payload,           │    │
       │         │   retryCount, status }       │    │
       │         └──────┬───────────────────────┘    │
       │                │ periodic + on startup       │
       │                ▼                             │
       │         ┌──────────────────────────────┐    │
       │         │ Hardcover API                │ ◄──┘
       └────────►│ GraphQL POST                 │
  (search results)│ status, rating, review,       │
                  │ metadata, covers, genres      │
                  └──────┬───────────────────────┘
                         │ on startup (pull)
                         ▼
                  ┌──────────────────────────────┐
                  │ Reconciliation               │
                  │ Hardcover → Brain merge      │
                  │ (attach hardcoverId,         │
                  │  add stub entries,           │
                  │  enrich metadata)            │
                  └──────────────────────────────┘
```

**Key principles:**
- **Firestore brain is source of truth** — all writes land there first
- **Hardcover is a best-effort mirror** — sync queue pushes to it, startup reconciliation pulls from it
- **Tool calling is autonomous** — the AI decides when to search Hardcover, no keyword detection
- **Brain annotations are never overwritten** by sync or reconciliation

## Detailed Flow

### 1. App Startup
```
main()
  ├─ Firebase init
  ├─ seedBrainIfNeeded()
  ├─ syncService.startupReconcile()
  │   ├─ Fetch all user_books from Hardcover (paginated if needed)
  │   │   (status in [Want to Read, Reading, Read, Did Not Finish, Paused])
  │   │
  │   ├─ For each Hardcover user_book:
  │   │   ├─ Find match in brain by hardcoverId → ensure hardcoverId is attached
  │   │   ├─ Find match in brain by title (normalized: lowercase, strip punctuation)
  │   │   │   → attach hardcoverId, enrich with author, coverUrl, genres, pages
  │   │   └─ No match → create stub Book entry:
  │   │       { title, hardcoverId, author, coverUrl, genres, pages,
  │   │         status, rating, hardcoverUrl, dateAdded, dateRead }
  │   │       (Wikan-model fields stay null — this is a stub)
  │   │
  │   ├─ For each brain book WITH hardcoverId but NOT in Hardcover response:
  │   │   → Enqueue sync action to push it to Hardcover
  │   │
  │   └─ Save updated brain to Firestore (only if changes were made)
  │
  ├─ syncService.startPeriodicSync()
  │   ├─ Timer.periodic(5 minutes)
  │   │   ├─ Drain sync queue (Firestore → Hardcover)
  │   │   │   For each pending item:
  │   │   │     Set status → "in_progress" (prevents re-processing if crash)
  │   │   │     Try Hardcover mutation:
  │   │   │       Success → delete item from queue
  │   │   │       Failure → status → "failed", retryCount++, store lastError
  │   │   │
  │   │   └─ If queue > 10: set chat_state.syncPendingCount (subtle UI indicator)
  │   │
  │   └─ First drain immediately after startup reconcile
  │
  └─ Firestore listener on meta/sync_queue
      → if new items appear while app is open, drain them (real-time sync)
```

### 2. After AI Brain Mutation
```
ChatState._generateResponse()
  ├─ BrainParser.applyBlocks() → updated brain with blocks list
  ├─ FirestoreService.updateBrain() ✓ (immediate, always)
  │
  └─ syncService.enqueueFromBrainMutation(blocks, previousBrain)
      For each block:
        APPEND_BOOK:
          → { action: "upsert_user_book",
              payload: { title, status, rating, hardcoverReview?, hardcoverSpoiler?, hardcoverId? } }
        UPDATE_BOOK:
          → Same as APPEND_BOOK (pull data from the updated book entry)
        DELETE_BOOK:
          → If book has hardcoverId:
              { action: "delete_user_book", payload: { hardcoverId } }
          → If no hardcoverId: skip (brain-only book, nothing to delete on Hardcover)
        PATCH (currentReading cleared):
          → Look up the book title from previousBrain.currentReading.book
          → { action: "upsert_user_book",
              payload: { title: <from previous BR>, status: "Read" } }
          → If no hardcoverId: still enqueue (Hardcover might have the book)
        PATCH (other sections):
          → No sync action needed (only book mutations sync to Hardcover)
```

### 3. Hardcover Linkage (writing hardcoverId back to brain)
```
When sync queue drains an upsert for a book without hardcoverId:
  1. Sync service calls hardcover_service.searchBooks(title)
     → If match found: use that book ID for the upsert
     → If no match: call hardcover_service.createBook(title) → get new book ID
  2. Perform the upsert or delete mutation with the obtained hardcoverId
  3. On success: write hardcoverId back to the brain entry
     (FirestoreService.updateBookHardcoverId(bookTitle, hardcoverId))
  4. Next reconciliation will enrich with full metadata (cover, genres, etc.)
```

### 4. Review Flow

The `hardcoverReview` field is the public-facing review text synced to Hardcover.
The `whyItMatters` field is the private Wikan-model annotation about how the book affected you.
They serve different purposes and can co-exist independently.

```
User finishes a book with review-worthy thoughts:
  User: "I finished Exhalation, 5 stars. It's a quiet masterpiece about
         free will and parenthood. Every story earns its twist."
  AI detects FINISH SIGNAL + review content
  AI emits APPEND_BOOK block:
    {
      "title": "Exhalation",
      "status": "Finished",
      "rating": 5,
      "personalSignificance": "Permanent Sushi",
      "whyItMatters": "The title story reframed how I think about free will. Chiang makes determinism feel warm.",
      "hardcoverReview": "A quiet masterpiece about free will and parenthood. Every story earns its twist.",
      "hardcoverSpoiler": false
    }
  Brain stores both fields (whyItMatters for the Wikan model, hardcoverReview for syncing)
  Sync queue enqueues upsert → Hardcover gets rating + review text + spoiler flag

User writes a review for a book already in the brain:
  User: "Write a review for Permutation City on Hardcover"
  AI reads existing brain entry, may ask for more thoughts
  User provides review text
  AI emits UPDATE_BOOK block:
    { "targetTitle": "Permutation City",
      "book": { "hardcoverReview": "...", "hardcoverSpoiler": false, "rating": 5 } }
  Sync queue pushes updated review to Hardcover

User wants to update an existing review:
  Same flow as "write a review" — UPDATE_BOOK with new hardcoverReview text
```

### 5. Tool Calling — Book Search

DeepSeek supports OpenAI-compatible function calling (`tools` parameter in chat completion).
The AI autonomously decides when to search Hardcover — no keyword detection needed.

**UX handling during tool calls:**
- When the AI emits `tool_calls` instead of text, ChatState sets `streamingContent = "Searching Hardcover..."`
- The tool executes (searchBooks, typically < 1s)
- The tool result is appended to messages, and the API is called again
- The second call streams prose normally (with search results in context)
- Max 3 tool call rounds; if exceeded, show error and return whatever the AI last said

**Tool definition** (custom type passed only when search-relevant):
```dart
// Defined in hardcover_service.dart, injected into ChatState
final searchBooksTool = {
  'type': 'function',
  'function': {
    'name': 'searchBooks',
    'description': 'Search for books on Hardcover.app. Use this to find book metadata, '
        'discover similar books, or look up books by title/author/topic. '
        'Returns up to 5 results with id, title, author, cover, rating, and description.',
    'parameters': {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': 'The search query — book title, author name, or topic keywords'
        }
      },
      'required': ['query']
    }
  }
};
```

**When to pass tools:** only when the conversation context suggests search could be useful.
Heuristic: if any message in the session mentions "search", "find", "look up", "discover",
recommendation requests, or unknown book titles. Otherwise omit to save tokens.

**Tool call loop** (in ChatState._generateResponse()):
```
1. Set streamingContent = "Searching Hardcover..." (if tool calls detected)
2. Send messages + tools to DeepSeek (streaming)
3. During streaming, detect mode transitions:
   a. Normal mode: accumulate prose chunks → yield to UI
   b. Block mode (BEGIN_JSON_* detected): buffer silently
   c. Tool call mode: accumulate tool_call deltas in a buffer
      (detected via finish_reason == "tool_calls" or presence of tool_calls in delta)
4. After stream completes:
   a. If finish_reason == "tool_calls":
      - Parse accumulated tool_call arguments (function name + args JSON)
      - Execute hardcover_service.searchBooks(query)
        → On error: return { "error": "..." } as tool response content
      - Append assistant message (with tool_calls) + tool result message to conversation
      - Go to step 1 (re-invoke with updated messages)
   b. If finish_reason == "stop":
      - Process blocks (BrainParser) if any
      - Set streamingContent to prose text
      - Continue normal flow
```

**Search result format** (passed to AI as tool response):
```json
[
  {
    "id": 123,
    "title": "Permutation City",
    "author": "Greg Egan",
    "rating": 4.2,
    "pages": 310,
    "description": "A man undergoes digital resurrection...",
    "coverUrl": "https://...",
    "url": "https://hardcover.app/books/permutation-city"
  }
]
```

**Streaming tool delta handling in AIService:**
```
AIService.sendMessageStreamWithTools(messages, tools) yields:
  - TextChunk(content) — normal prose for UI streaming
  - ToolCallRequest(id, name, arguments) — after stream completes, AI wants a tool executed

Implementation: the streaming parser watches delta.tool_calls alongside delta.content.
Tool call deltas arrive with incremental function arguments (partial JSON).
The parser accumulates arguments per tool call index until the stream ends.
At that point, finish_reason determines the outcome:
  "stop" → all accumulated tool calls are ignored (AI chose not to use them)
  "tool_calls" → yield ToolCallRequest objects for ChatState to execute
```

## Data Model Changes

### Brain Book model (extended)
```dart
class Book {
  String title;
  String status;              // "Reading", "Read", "Did Not Finish", "Paused"

  // Hardcover-sourced fields (pulled during reconciliation, pushed during sync):
  String? hardcoverId;        // Hardcover's book ID
  String? author;             // Primary author name
  String? coverUrl;           // Cover image URL
  List<String> genres;        // Genre names
  int? pages;                 // Page count
  String? hardcoverUrl;       // Link to hardcover.app/books/{slug}
  String? dateAdded;          // From Hardcover user_book.date_added
  String? dateRead;           // From Hardcover user_book.last_read_date
  String? hardcoverStatus;    // Status from Hardcover (for divergence detection)
  double? hardcoverRating;    // Rating from Hardcover (for divergence detection)

  // Review fields (pushed to Hardcover):
  String? hardcoverReview;    // Public review text synced to Hardcover
  bool hardcoverSpoiler;      // Does the review contain spoilers?

  // Brain-only fields (never touched by sync/reconciliation):
  double? rating;             // The user's rating (brain is source of truth)
  String? personalSignificance;  // Vocabulary term: "Permanent Sushi", etc.
  String? whyItMatters;       // Private annotation: how the book affected the user
  String? progress;           // Reading progress (e.g., "33%")
  String? currentImpression;  // Current thoughts while reading
  String? readingStrategy;    // Per-book reading approach
  String? abandonmentReason;  // Why DNF'd
}
```

**Key distinction:**
- `status` / `rating` — brain's version (source of truth, set by AI)
- `hardcoverStatus` / `hardcoverRating` — Hardcover's version (pulled during reconciliation, for divergence detection)
- When both are set and differ, the AI sees the conflict and surfaces it organically

### Sync Queue model (Firestore: meta/sync_queue/{autoId})
```dart
class SyncQueueItem {
  String? id;                // Firestore doc ID
  String action;             // "upsert_user_book" | "delete_user_book"
  Map<String, dynamic> payload;  // Fields to sync
  int retryCount;            // Incremented on failure
  String status;             // "pending" | "in_progress" | "failed"
  String? lastError;         // Error message from last attempt
  DateTime createdAt;
  String? bookTitle;         // For easy querying/debugging
}
```

**Status transitions:**
```
pending → in_progress (when drain picks it up)
in_progress → deleted (on success)
in_progress → failed (on error, retryCount++)
failed → in_progress (when drain retries)
failed → deleted (after 10 retries, abandoned)
```

### Firestore schema additions
```
meta/
  brain_json            — existing
  sync_queue/           — NEW
    {autoId}: { action, payload, retryCount, status, lastError, createdAt, bookTitle }
```

## Files to Create/Modify

### New files
| File | Purpose |
|------|---------|
| `lib/constants/hardcover_config.dart` | API endpoint, API key |
| `lib/models/hardcover_models.dart` | HardcoverBook, UserBook, SearchResult — GraphQL response models |
| `lib/models/sync_queue.dart` | SyncQueueItem model with toMap/fromMap |
| `lib/services/hardcover_service.dart` | GraphQL client: fetchUserBooks(), searchBooks(), upsertUserBook(), createBook(), searchBookTool definition |
| `lib/services/sync_service.dart` | Reconciliation logic, periodic sync, queue management, hardcoverId write-back |
| `lib/screens/settings_screen.dart` | Settings page: Hardcover API key input, sync status, manual sync trigger |

### Modified files
| File | Change |
|------|--------|
| `lib/models/brain.dart` | Add `hardcoverId`, `author`, `coverUrl`, `genres`, `pages`, `hardcoverUrl`, `dateAdded`, `dateRead`, `hardcoverStatus`, `hardcoverRating`, `hardcoverReview`, `hardcoverSpoiler` to `Book`. Add optional `hardcoverId` to `CurrentReading`. Update `fromJson`, `toJson`, `toMarkdown`. |
| `lib/providers/chat_state.dart` | Inject `HardcoverService` + `SyncService`. After `BrainParser.applyBlocks()`, call `syncService.enqueueFromBrainMutation(blocks, previousBrain)`. Add tool call loop in `_generateResponse()`: show "Searching Hardcover..." during tool execution, detect mode transitions (prose/block/tool), re-invoke AI after tool results, max 3 rounds. Expose `syncPendingCount` for UI indicator. |
| `lib/services/ai_service.dart` | New method `sendMessageStreamWithTools(messages, tools)` that yields `TextChunk` or `ToolCallRequest` objects. Streaming parser handles `delta.tool_calls` accumulation (incremental arguments). |
| `lib/services/brain_parser.dart` | Ensure new Book fields survive through append/update operations. No structural changes needed since `fromJson` handles optional fields. |
| `lib/main.dart` | After auth gate, create `HardcoverService` + `SyncService`, inject into ChatState, call `syncService.startupReconcile()` + `syncService.startPeriodicSync()`. |
| `lib/screens/chat_screen.dart` | Add settings icon → navigate to SettingsScreen. Show "Syncing to Hardcover..." indicator when `syncPendingCount > 10`. Show "Searching Hardcover..." while tool calls execute. |
| `lib/constants/api_config.dart` | Add `hardcoverApiKey` and `hardcoverApiEndpoint`. |
| `lib/constants/system_prompt.dart` | Add review write trigger: when user describes thoughts/rating for a finished book, include `hardcoverReview` + `hardcoverSpoiler`. Update book JSON examples to include new fields. Add Hardcover awareness: the AI knows `hardcoverStatus`/`hardcoverRating` vs brain's `status`/`rating`, and surfaces divergence. |
| `assets/reading_brain.json` | Add `hardcoverId`, `author`, `coverUrl`, `genres`, `pages`, `hardcoverUrl`, `dateAdded`, `dateRead`, `hardcoverStatus`, `hardcoverRating`, `hardcoverReview`, `hardcoverSpoiler` (all null/missing) to existing book entries. |

## GraphQL Queries & Mutations

### Fetch user books — metadata only (depth: 2)
First query to get user_book status/rating/review + book IDs. Run this first.
```graphql
query GetUserBooks {
  user_books(where: { status: { _in: ["Want to Read", "Reading", "Read", "Did Not Finish", "Paused"] } }) {
    id
    status
    rating
    review
    spoiler
    date_added
    first_read_date
    last_read_date
    reads_count
    book_id
    book {
      id
      title
    }
  }
}
```

### Fetch book details by IDs (depth: 2)
Second query, using book IDs from the first query (batch by 20).
```graphql
query GetBookDetails($ids: [Int!]!) {
  books(where: { id: { _in: $ids } }) {
    id
    title
    subtitle
    description
    pages
    rating
    ratings_count
    release_date
    slug
    cover { url }
    book_genres { genre { name } }
    book_authors { author { id, name } }
  }
}
```

**Why split queries:** Hasura imposes a max query depth of 3. Nesting `user_books → book → book_genres → genre → name` exceeds this. Splitting into two depth-2 queries stays within limits while fetching all needed data.

### Search books
```graphql
query SearchBooks($term: String!) {
  search(term: $term, types: "book", per_page: 5) {
    hits {
      id
      title
      description
      pages
      rating
      cover { url }
      book_authors { author { name } }
      slug
    }
  }
}
```

### Upsert user book (create or update reading status + review)
```graphql
mutation UpsertUserBook($bookId: Int!, $status: String!, $rating: numeric, $review: String, $spoiler: Boolean) {
  insert_user_books_one(
    object: { book_id: $bookId, status: $status, rating: $rating, review: $review, spoiler: $spoiler }
    on_conflict: { constraint: user_books_user_book_key, update_columns: [status, rating, review, spoiler] }
  ) {
    id
  }
}
```

### Create a book (when book doesn't exist in Hardcover)
```graphql
mutation CreateBook($title: String!, $pages: Int, $releaseDate: date) {
  createBook(title: $title, pages: $pages, release_date: $releaseDate) {
    id
  }
}
```

## What Happens When Hardcover Fails

```
Hardcover down / rate limited / token expired:
  → Queue items stay in Firestore with retryCount++
  → Chat still works, brain still updates normally
  → Next periodic tick retries
  → After 10 retries: item deleted from queue (abandoned)
  → If queue size > 10: ChatScreen shows subtle indicator
  → Tool calling (searchBooks) returns error to AI as tool response content
    → AI says something like "I couldn't search Hardcover right now — let me work with what's in your brain"

Token expired (Jan 1st or early reset):
  → All requests fail with 401
  → Sync queue builds up, retries exhausting
  → Settings screen shows "Hardcover sync paused — update API key"
  → User updates key in settings → manual trigger drains queue immediately
```

## Conflict Resolution

### 1. Reconciliation is additive only — never overwrites brain annotations

| Scenario | Behavior |
|----------|----------|
| Book in Hardcover, NOT in brain | Create a **stub** brain entry with Hardcover metadata (`hardcoverId`, `author`, `coverUrl`, `genres`, `pages`, `hardcoverStatus`, `hardcoverRating`, `dateAdded`, `dateRead`). Wikan-model fields stay null. |
| Book in brain, NOT in Hardcover | Keep as-is. Enqueue a push to Hardcover. If all Wikan-model fields are null (bare stub) and push fails 10 times, prune the entry. |
| Book in BOTH, same status/rating | Enrich brain with missing Hardcover metadata. No other changes. |
| Book in BOTH, different status/rating | **Do nothing to status/rating.** Store Hardcover's version in `hardcoverStatus`/`hardcoverRating`. The AI sees both and can surface divergence naturally. |

### 2. Ownership boundaries

| Layer | Owned by | Fields |
|-------|----------|--------|
| Metadata | **Hardcover** (pull-only) | `hardcoverId`, `author`, `coverUrl`, `genres`, `pages`, `hardcoverUrl`, `description`, `dateAdded`, `dateRead` |
| Status & rating | **Brain** (source of truth) | `status`, `rating` |
| Hardcover snapshot | **Hardcover** (pull-only, for divergence) | `hardcoverStatus`, `hardcoverRating` |
| Reviews | **Brain → Hardcover** (push-only) | `hardcoverReview`, `hardcoverSpoiler` |
| Wikan model | **Brain** (never touched by sync) | `personalSignificance`, `whyItMatters`, `readingStrategy`, `currentImpression`, `abandonmentReason` |

### 3. How the AI sees divergence

Each Book entry stores both the brain's version (`status`, `rating`) and a snapshot of Hardcover's last-known version (`hardcoverStatus`, `hardcoverRating`). These are both visible in the reading brain JSON injected into every prompt.

When they disagree, the AI naturally surfaces it in conversation:
> *"I notice Hardcover has this marked as Read but your brain still says Reading — did you finish it without telling me?"*

No mechanical alerts, no forced resolution. The user tells the AI which is correct, and the AI updates the brain accordingly. The sync queue then pushes the correction to Hardcover.

### Stub cleanup rule

A book entry is a "stub" if ALL of these are null/empty: `personalSignificance`, `whyItMatters`, `readingStrategy`, `abandonmentReason`, `currentImpression`. Stubs that fail to sync to Hardcover after 10 retries are removed from the brain. Annotated books are never deleted by sync.

## Implementation Order

1. **Models first** — Extend `Book` with all Hardcover fields, create `hardcover_models.dart`, `sync_queue.dart`
2. **Hardcover config** — API endpoint, API key in `hardcover_config.dart` + `api_config.dart`
3. **Hardcover service** — GraphQL client with `fetchUserBooks()`, `fetchBookDetails()`, `searchBooks()`, `upsertUserBook()`, `createBook()`, tool definition
4. **AIService tool calling** — New `sendMessageStreamWithTools()` method, streaming tool delta accumulation, `TextChunk`/`ToolCallRequest` yield types
5. **Sync service** — Reconciliation (two-query fetch + merge), periodic queue drain, `enqueueFromBrainMutation()`, hardcoverId write-back, stub cleanup
6. **ChatState integration** — Inject `HardcoverService` + `SyncService`, tool call loop in `_generateResponse()`, enqueue after brain mutations, expose `syncPendingCount`
7. **Brain parser** — Verify new fields survive appending/updating (should be automatic via `fromJson`)
8. **Main.dart wiring** — Create services, inject into ChatState, start reconciliation + periodic sync after auth gate
9. **ChatScreen UI** — Settings icon, "Searching Hardcover..." state, "Syncing..." indicator
10. **Settings screen** — API key input, sync status display, manual reconcile + drain triggers
11. **Update system prompt** — Review write trigger, Hardcover awareness, updated book JSON examples
12. **Update seed data** — Add all new Hardcover fields (null) to existing book entries in `assets/reading_brain.json`

## Risks / Open Questions

- **Beta instability**: tokens may reset, schema may change. Mitigated by: Firestore is source of truth, queue absorbs failures, 10-retry abandonment prevents infinite loops.
- **GraphQL query depth limit of 3**: resolved by splitting user_books fetch into two queries (metadata first, then book details by IDs).
- **Book title matching during reconciliation**: normalize both sides (lowercase, strip punctuation) for exact matching. For fuzzy matching, use the Hardcover search API as a fallback if exact match fails on a notable title.
- **Hardcover's `user_books` connection constraint**: the constraint name `user_books_user_book_key` is assumed from standard Hasura naming. Fallback: query `user_books` by `book_id` first; if exists, update; if not, insert.
- **Review text length**: Hardcover may have a character limit. The AI should default to concise reviews (~500 chars). If the user explicitly wants longer, it's on them.
- **DeepSeek tool calling with streaming**: tool call deltas arrive interleaved with content deltas in streaming mode. The implementation must handle the edge case where the AI emits both a partial tool_call and a content delta in the same streaming block. In practice, DeepSeek sends tool_call deltas first (without content), but the parser should be defensive.
