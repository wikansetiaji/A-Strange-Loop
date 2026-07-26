# Phase 1: MVP — Chat with Your Reading Brain

**Goal:** A working Flutter Web app where you can chat with an LLM that has your full reading brain in context. The brain is served from Firestore. Chat is ephemeral (no session persistence yet — that's Phase 2).

**Target:** End of Week 1
**Depends on:** Nothing. This is the first phase.

---

## Step-by-Step Tasks

### 1. Prerequisites (Tooling)

- [ ] **Install Flutter SDK** (if not already)
  ```bash
  # macOS
  brew install --cask flutter
  flutter doctor
  ```
- [ ] **Install Firebase CLI**
  ```bash
  npm install -g firebase-tools
  firebase login
  ```
  Or: `brew install firebase-cli`
- [ ] **Pick AI Provider & API Key**
  - Gemini 1.5 Pro (free tier: 15 RPM, 1M token context) — recommended for cost
  - or Claude Sonnet via Anthropic API
  - or OpenAI-compatible endpoint for any model with 1M+ context
  - Store the API key securely (env variable or Flutter config — not in source)

### 2. Firebase Project Setup

- [ ] **Create Firebase project**
  ```bash
  firebase projects:create a-strange-loop
  # Or through Firebase Console: console.firebase.google.com
  ```
- [ ] **Enable Firestore** (Native mode)
  - Firebase Console → Firestore → Create Database → Start in production mode
  - Pick a location close to you (e.g., `asia-southeast1` for Indonesia)
- [ ] **Enable Firebase Hosting**
  - Firebase Console → Hosting → Get Started
- [ ] **Set Firestore Security Rules** (permissive, personal use)
  ```
  rules_version = '2';
  service cloud.firestore {
    match /databases/{database}/documents {
      match /{document=**} {
        allow read, write: if true;  // Personal use. Lock down in Phase 4.
      }
    }
  }
  ```
- [ ] **Register a Web App** in Firebase Console → Project Settings → Your Apps → Web App
  - Copy the Firebase config object (apiKey, authDomain, projectId, etc.)

### 3. Flutter Project Init

- [ ] **Create Flutter project**
  ```bash
  flutter create a_strange_loop
  cd a_strange_loop
  ```
  Target platform: Web (Android/iOS optional, can add later per tech plan)
- [ ] **Add dependencies** to `pubspec.yaml`:
  ```yaml
  dependencies:
    flutter:
      sdk: flutter
    firebase_core: ^3.0.0
    cloud_firestore: ^5.0.0
    http: ^1.2.0
    provider: ^6.0.0
    flutter_markdown: ^0.7.0
  ```
  Run: `flutter pub get`
- [ ] **Initialize Firebase** in `lib/main.dart`:
  ```dart
  void main() async {
    WidgetsFlutterBinding.ensureInitialized();

    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'YOUR_API_KEY',
        authDomain: 'YOUR_PROJECT.firebaseapp.com',
        projectId: 'YOUR_PROJECT_ID',
        storageBucket: 'YOUR_PROJECT.appspot.com',
        messagingSenderId: 'YOUR_SENDER_ID',
        appId: 'YOUR_APP_ID',
      ),
    );

    runApp(const ASLApp());
  }
  ```
  **Note:** Keep the Firebase config out of git. Use a separate config file or environment variables. Create `lib/firebase_options.dart` (gitignored) with the config.

### 4. Upload Reading Brain to Firestore

- [ ] **Create a Firestore service** (`lib/services/firestore_service.dart`)
  - Method `uploadBrain(String markdownContent)` → writes to `meta/brain`
  - Method `getBrain()` → reads from `meta/brain`, returns `String`
- [ ] **One-time upload script** (or run on first app launch):
  - Read `assets/reading_brain.md` (copy from `plans/reading_brain.md`)
  - Upload to `meta/brain` document
  - Verify it can be read back and the content matches
- [ ] **Move `reading_brain.md` into Flutter assets:**
  ```bash
  mkdir -p assets
  cp ../plans/reading_brain.md assets/
  ```
  Register in `pubspec.yaml`:
  ```yaml
  flutter:
    assets:
      - assets/reading_brain.md
  ```

### 5. Build Chat UI

- [ ] **Chat screen** (`lib/screens/chat_screen.dart`)
  - **Top bar:** "A Strange Loop" title + subtitle "Reading Companion"
  - **Message list:** `ListView.builder` with user/assistant bubbles
    - User: right-aligned, accent color background
    - Assistant: left-aligned, surface color background
    - Support markdown rendering in assistant messages (use `flutter_markdown`)
    - Auto-scroll to bottom on new message
  - **Input bar (bottom):**
    - `TextField` with "Ask about your reading brain..." hint
    - Send button (icon: `Icons.send` or `Icons.arrow_upward`)
    - Send on Enter, dismiss keyboard on tap outside
  - **Empty state:** Show a brief intro message when no messages yet
    > "I'm A Strange Loop. I've am your reading brain. Ask me anything; what to read next, how your taste has evolved, or just talk about books."

- [ ] **Message model** (`lib/models/message.dart`)
  ```dart
  class Message {
    final String role; // 'user' or 'assistant'
    final String content;
    final DateTime timestamp;
  }
  ```

- [ ] **State management** — keep it simple. Use `ChangeNotifier` + `Provider` for the chat state:
  ```dart
  class ChatState extends ChangeNotifier {
    List<Message> messages = [];
    bool isLoading = false;

    Future<void> sendMessage(String text) async { ... }
  }
  ```

### 6. Implement API Call to LLM

- [ ] **AI service** (`lib/services/ai_service.dart`)
  - Method `sendMessage(String prompt)` → POST to the LLM API
  - Parse JSON response, extract text content
  - Return the assistant's response string

- [ ] **Provider selection & endpoint:**
  - **Option A (recommended): Gemini 1.5 Pro** — free tier, 1M context
    ```
    POST https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent?key=YOUR_API_KEY
    ```
  - **Option B: Claude (Anthropic API)**
    ```
    POST https://api.anthropic.com/v1/messages
    Headers: x-api-key, anthropic-version: 2023-06-01
    ```
  - **Option C: OpenAI-compatible** (for other providers)

- [ ] **Handle loading/error states:**
  - Show typing indicator while waiting for response
  - Show error message if API call fails (with retry button)
  - Timeout at 60 seconds

- [ ] **Important:** The raw LLM response is shown to the user. Phase 3 will add block parsing (BEGIN_APPEND_BOOK, BEGIN_PATCH, etc.) — for now, the companion mode responses (plain prose) work out of the box.

### 7. Construct the Full Prompt

Every time the user sends a message:

1. **Fetch the latest reading brain** from Firestore (`meta/brain`)
2. **Assemble the prompt:**
   ```
   [Companion System Prompt — the full text from tech_plan.md lines 143-452]
   [reading_brain.md — full markdown from Firestore]
   [Chat history — last N messages, formatted as role/content pairs]
   [User query — the latest message]
   ```
3. **Send to LLM**
4. **Display response** in the chat UI

**Prompt assembly pseudocode:**
```dart
String buildPrompt(String brain, List<Message> history, String query) {
  final systemPrompt = companionSystemPrompt; // stored as a const
  final historyText = history.map((m) =>
    '${m.role == 'user' ? 'User' : 'Assistant'}: ${m.content}'
  ).join('\n\n');

  return '''
$systemPrompt

---

$brain

---

## Chat History

$historyText

---

User: $query
''';
}
```

**Note on context window management:** With a 1M token context and a ~5K token brain, you can fit 100+ turns before hitting limits. For Phase 1, send the full history. Trimming can come later if needed. The companion system prompt is ~3K tokens, the brain is ~2K tokens — you have ~995K tokens left for conversation.

### 8. Wire It All Together

The full flow when the user sends a message:

```
User types message + taps Send
  ↓
ChatState.sendMessage(text):
  1. Add user Message to messages list (role: 'user')
  2. Set isLoading = true, notifyListeners()
  3. Fetch reading_brain.md from Firestore
  4. Build full prompt: system prompt + brain + history + query
  5. Call AI service → get response text
  6. Add assistant Message to messages list (role: 'assistant')
  7. Set isLoading = false, notifyListeners()
  ↓
UI rebuilds, shows the new messages
```

### 9. Test Locally

- [ ] **Run on web:**
  ```bash
  flutter run -d chrome
  ```
- [ ] **Manual test scenarios:**
  - Send: "What's your reading brain say about me?" → Should respond from the brain
  - Send: "What should I read next?" → Should reference the recommendation queue + reader profile
  - Send: "What's my current reading?" → Should mention The Glass Bead Game
  - Send: "What are my active questions?" → Should list them
  - Send: "I loved Permutation City" → Should NOT emit any blocks (companion mode, no trigger fired)
  - Send: "I finished The Glass Bead Game" → Should trigger but will emit raw blocks (parsing comes in Phase 3 — acceptable for MVP)

---

## Phase 1 Deliverables

- [ ] Firebase project with Firestore + Hosting enabled
- [ ] Flutter Web project with Firebase initialized
- [ ] `reading_brain.md` uploaded to Firestore at `meta/brain`
- [ ] Working chat UI with send/receive
- [ ] LLM responds with full brain context
- [ ] App runs in Chrome locally (`flutter run -d chrome`)

## What Phase 1 Does NOT Include

- Session persistence (Phase 2)
- Block parsing (BEGIN_APPEND_BOOK, BEGIN_PATCH, etc.) — Phase 3
- Brain editing UI (Phase 3)
- "New Chat" button (Phase 2)
- Auth (deferred per tech plan — personal use)
- Firebase Hosting deploy (Phase 4)
- Multiple chats/sessions (Phase 2)
- Observation system (companion will emit raw blocks — Phase 3 parses them)

---

## Estimated Effort

| Task | Estimate |
|:---|:---|
| Firebase setup | 30 min |
| Flutter project init + deps | 20 min |
| Firestore read/write service | 30 min |
| Upload brain | 10 min |
| Chat UI | 2 hours |
| AI service + prompt construction | 1.5 hours |
| Wire together + testing | 1 hour |
| **Total** | **~6 hours** |

---

## Key Files to Create

```
a_strange_loop/
├── lib/
│   ├── main.dart                    # Firebase init + app entry
│   ├── app.dart                     # MaterialApp + Provider setup
│   ├── firebase_options.dart        # (gitignored) Firebase config
│   ├── models/
│   │   └── message.dart             # Message data class
│   ├── services/
│   │   ├── firestore_service.dart   # Read/write meta/brain
│   │   └── ai_service.dart          # LLM API calls
│   ├── providers/
│   │   └── chat_state.dart          # Chat state management
│   ├── screens/
│   │   └── chat_screen.dart         # Main chat UI
│   └── constants/
│       └── system_prompt.dart       # Companion system prompt text
├── assets/
│   └── reading_brain.md             # Initial brain file (for seeding)
└── pubspec.yaml
```

---

## Go / No-Go Check

After Phase 1, before moving to Phase 2:

- Can you have a conversation with the companion about your reading brain?
- Does the companion correctly reference your profile, vocabulary, and queue?
- Does it stay in companion mode for casual questions (no unintended blocks)?
- Is the chat UI usable and responsive?

If all four are "yes" → proceed to Phase 2.

---

## Phase 1 Extension — Polish & Streaming

**Date added:** 2026-07-26

### 1. Streaming Responses
- `ai_service.dart`: SSE streaming via `http.Client().send()` + `StreamedResponse`, parses `data:` lines, yields content chunks + `[USAGE]` token on finish
- `chat_state.dart`: `streamingContent` accumulates chunks live; throttled `notifyListeners()` at ~50ms; finalized into `Message` on stream close
- `chat_screen.dart`: Live `MarkdownBody` renders streaming content in place of typing indicator

### 2. Session Token Persistence
- `firestore_service.dart`: `saveSessionStats(sessionId, promptTokens, completionTokens)` writes to `sessions/{sessionId}` with `SetOptions(merge: true)`
- `chat_state.dart`: UUID-based `sessionId`, cumulative `sessionPromptTokens`/`sessionCompletionTokens`, persisted after each response
- `chat_screen.dart`: Thin footer: `"14 messages · 4.2K tokens this session"`

### 3. Full-Text AI Rendering (No Bubble)
- Assistant messages: full-width `MarkdownBody` with 3px `primary.withAlpha(60)` left accent bar, no background
- User messages: stay as right-aligned bubbles (`primaryContainer`)
- Typing indicator: `"Thinking..."` italic text with accent bar

### 4. Current Reading in AppBar
- `chat_state.dart`: Regex parses `CURRENT_READING` → extracts `Book:` and `Progress:` fields; updated on each brain fetch
- `chat_screen.dart`: AppBar subtitle `"Reading: The Glass Bead Game · 15%"`, dynamic, hides when no current reading

### 5. Witty AI Personality
- `system_prompt.dart`: Updated PERSONALITY & TONE section — warm curiosity as default, cleverness as baseline, combativeness as rare spice (~10%)
- Builds on responses, teases patterns lightly, feels like a sharp friend not a coach
