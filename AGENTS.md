# A Strange Loop — Agent Instructions

## Project layout
- Root: planning docs (`plans/`), shared assets (`assets/fonts/`), OpenCode config (`.opencode/`).
- **The Flutter app is `a_strange_loop/`** — all Flutter commands must run from that directory, not the root.

## Commands
```bash
# All from a_strange_loop/
flutter pub get          # install dependencies
flutter analyze          # static analysis / lint
flutter test             # run tests
flutter run -d chrome    # run on web locally
flutter build web        # production web build (output: build/web/)
firebase deploy --only hosting   # deploy to Firebase Hosting
```

## Architecture
- **Flutter web app** (SDK ^3.7.2). Firebase backend: Auth (Google sign-in, restricted to `wikansetiaji@gmail.com`), Firestore, Hosting.
- **State management**: single `ChatState` ChangeNotifier via `provider`. Passed as `ChangeNotifierProvider.value` from `main.dart` (no `MultiProvider` needed).
- **AI**: calls DeepSeek API (`deepseek-v4-flash`) directly via `http` package. Streaming support with tool calls in `ai_service.dart`.
- **Hardcover proxy**: a Cloudflare Worker at `workers/index.js` proxies GraphQL calls to `api.hardcover.app/v1/graphql`, adding CORS headers. The Flutter app talks to the worker.

## Core concept — "Reading Brain"
The app is a reading-companion chatbot. The AI operates against a structured JSON file called the "Reading Brain" stored in Firestore (`meta/brain_json`) and seeded from `assets/reading_brain.json`. The original markdown brain is kept at `meta/brain` as a backup.
- The **brain model** (`models/brain.dart`) defines typed Dart classes with `fromJson`/`toJson`/`toMarkdown()`.
- The **system prompt** (`constants/system_prompt.dart`) defines the AI's personality, write triggers, and JSON operation block syntax (~498 lines).
- The **brain parser** (`services/brain_parser.dart`) parses AI responses for JSON operation blocks (`BEGIN_JSON_APPEND_BOOK`…`END_JSON_APPEND_BOOK`, `BEGIN_JSON_PATCH`…`END_JSON_PATCH`, `BEGIN_JSON_OBSERVATION`…`END_JSON_OBSERVATION`), separates them from visible prose during streaming, and applies mutations to the Firestore brain document.
- Any change to `system_prompt.dart` or `brain_parser.dart` must keep them consistent — the parser's grammar mirrors the prompt's block syntax exactly.

## Hardcover integration
The app syncs reading activity to Hardcover.app via a two-way system:
- **Reconciliation** (`services/sync_service.dart`): at startup, fetches all Hardcover user books and enriches the brain's book entries with metadata (hardcoverId, author, coverUrl, genres, pages, ratings, etc.). Creates stubs for books on Hardcover but not in the brain.
- **Sync queue** (`models/sync_queue.dart`): when the AI emits brain mutations (APPEND_BOOK, PATCH CURRENT_READING), sync items are queued in Firestore (`meta/sync_queue/items`). A periodic timer (5 min) and a Firestore snapshot listener drain the queue, translating brain operations into Hardcover GraphQL mutations.
- **Hardcover API** (`services/hardcover_service.dart`): GraphQL client for search, fetch, upsert, and create operations against the Hardcover backend via the Cloudflare Worker proxy.
- **Book model hardcover fields**: `hardcoverId`, `author`, `coverUrl`, `genres`, `pages`, `hardcoverUrl`, `dateAdded`, `dateRead`, `hardcoverStatus`, `hardcoverRating`, `hardcoverReview`, `hardcoverSpoiler`.
- Rating resolution: `book.rating` is the brain's rating (source of truth). `book.hardcoverRating` is Hardcover's snapshot. `Book._resolveRating` prefers hardcoverRating when both exist and differ.

## Secrets (do not modify carelessly)
- `constants/api_config.dart` contains a **hardcoded DeepSeek API key**. This is intentional for a personal app but must never be exposed or committed to other repos.
- `constants/hardcover_config.dart` contains a **hardcoded Hardcover JWT** and user ID. Same treatment — never commit to other repos.
- `lib/firebase_options.dart` contains Firebase web credentials (expected for a web app).

## Key files
| File | Purpose |
|------|---------|
| `lib/main.dart` | Entry point, Firebase init, ChatState provider, auth gate, sync startup |
| `lib/providers/chat_state.dart` | Central state: sessions, messages, brain cache, AI call orchestration, tool call handling |
| `lib/models/brain.dart` | Typed brain model: Brain, Book (with hardcoverRating), Observation, etc. with `fromJson`/`toJson`/`toMarkdown` |
| `lib/models/message.dart` | Message model (user/assistant/system, order, firestoreId) |
| `lib/models/session.dart` | Session model (title, tokens, summary state, pinned) |
| `lib/models/hardcover_models.dart` | HardcoverBook, HardcoverUserBook, HardcoverSearchResult, etc. |
| `lib/models/sync_queue.dart` | SyncQueueItem model (action, payload, retryCount, status) |
| `lib/services/ai_service.dart` | DeepSeek API: summarize, generateTitle, sendMessageStream, sendMessageStreamWithTools |
| `lib/services/brain_parser.dart` | Parses AI JSON block responses and mutates the brain |
| `lib/services/firestore_service.dart` | All Firestore CRUD (brain_json, sessions, messages) |
| `lib/services/hardcover_service.dart` | Hardcover GraphQL client: search, fetch, upsert, create |
| `lib/services/sync_service.dart` | Two-way Hardcover sync: startup reconcile, queue drain, brain mutation → sync queue |
| `lib/constants/system_prompt.dart` | Full AI system prompt (~498 lines) |
| `lib/constants/api_config.dart` | DeepSeek endpoint, model, API key, token limits |
| `lib/constants/hardcover_config.dart` | Hardcover proxy endpoint, API JWT, user ID |
| `lib/theme/app_theme.dart` | Light/dark themes using Space Grotesk (body) + Syne (display) |
| `lib/widgets/animations.dart` | Custom animated widgets (PulsingLoop, FloatingDust, TypingBubble, etc.) |
| `lib/screens/brain_screen.dart` | Full-screen "Reading Brain" view — sectioned card render of the typed brain model |
| `lib/screens/settings_screen.dart` | Settings: manual Hardcover sync trigger, account info |
| `workers/index.js` | Cloudflare Worker — proxies Hardcover GraphQL with CORS |

## Conventions
- **No comments** in code unless absolutely necessary.
- Dart analysis powered by `package:flutter_lints/flutter.yaml` — no custom lint rules defined.
- Material 3 theming, zero-radius (sharp) borders everywhere.
- `FirebaseAuth` import uses `hide EmailAuthProvider` because `firebase_ui_auth` is not in the project and the name conflicts with `GoogleAuthProvider`.
- Session IDs are epoch milliseconds as strings.
- Message streaming: response blocks are hidden from the user during streaming and parsed after the stream completes. The UI shows only natural-language prose.
