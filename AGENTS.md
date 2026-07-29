# A Strange Loop — Agent Instructions

## Project layout
- Root: planning docs (`plans/`), shared assets (`assets/fonts/`), OpenCode config (`.opencode/`).
- **The Flutter app is `a_strange_loop/`** — all Flutter commands must run from that directory, not the root.

## Commands
```bash
# All from a_strange_loop/
flutter pub get          # install dependencies
flutter analyze          # static analysis / lint
flutter test             # run tests (currently a placeholder smoke test)
flutter run -d chrome    # run on web locally
flutter build web        # production web build (output: build/web/)
firebase deploy --only hosting   # deploy to Firebase Hosting
```

## Architecture
- **Flutter web app** (SDK ^3.7.2). Firebase backend: Auth (Google sign-in, restricted to `wikansetiaji@gmail.com`), Firestore, Hosting.
- **State management**: single `ChatState` ChangeNotifier via `provider`. Passed as `ChangeNotifierProvider.value` from `main.dart` (no `MultiProvider` needed).
- **AI**: calls DeepSeek API (`deepseek-v4-flash`) directly via `http` package. Streaming support in `ai_service.dart`.

## Core concept — "Reading Brain"
The app is a reading-companion chatbot. The AI operates against a structured markdown file called the "Reading Brain" stored in Firestore (`meta/brain`) and seeded from `assets/reading_brain.md`.
- The **system prompt** (`constants/system_prompt.dart`) defines the AI's personality, write triggers, and operation block syntax.
- The **brain parser** (`services/brain_parser.dart`) parses AI responses for operation blocks (`BEGIN_APPEND_BOOK`…`END_APPEND_BOOK`, `BEGIN_PATCH`…`END_PATCH`, `BEGIN_OBSERVATION`…`END_OBSERVATION`), separates them from visible prose during streaming, and applies mutations to the Firestore brain document.
- Any change to `system_prompt.dart` or `brain_parser.dart` must keep them consistent — the parser's grammar mirrors the prompt's block syntax exactly.

## Secrets (do not modify carelessly)
- `constants/api_config.dart` contains a **hardcoded DeepSeek API key**. This is intentional for a personal app but must never be exposed or committed to other repos.
- `lib/firebase_options.dart` contains Firebase web credentials (expected for a web app).

## Key files
| File | Purpose |
|------|---------|
| `lib/main.dart` | Entry point, Firebase init, ChatState provider, auth gate |
| `lib/providers/chat_state.dart` | Central state: sessions, messages, brain cache, AI call orchestration |
| `lib/services/ai_service.dart` | DeepSeek API: summarize, generateTitle, sendMessageStream |
| `lib/services/brain_parser.dart` | Parses AI block responses and mutates the brain markdown |
| `lib/services/firestore_service.dart` | All Firestore CRUD (brain, sessions, messages) |
| `lib/constants/system_prompt.dart` | Full AI system prompt (~360 lines) |
| `lib/constants/api_config.dart` | DeepSeek endpoint, model, API key, token limits |
| `lib/theme/app_theme.dart` | Light/dark themes using Space Grotesk (body) + Syne (display) |
| `lib/widgets/animations.dart` | Custom animated widgets (PulsingLoop, FloatingDust, TypingBubble, etc.) |

## Conventions
- **No comments** in code unless absolutely necessary.
- Dart analysis powered by `package:flutter_lints/flutter.yaml` — no custom lint rules defined.
- Material 3 theming, zero-radius (sharp) borders everywhere.
- `FirebaseAuth` import uses `hide EmailAuthProvider` because `firebase_ui_auth` is not in the project and the name conflicts with `GoogleAuthProvider`.
- Session IDs are epoch milliseconds as strings.
- Message streaming: response blocks are hidden from the user during streaming and parsed after the stream completes. The UI shows only natural-language prose.
