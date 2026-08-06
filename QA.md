# Manual QA Test Suite

Run `flutter run -d chrome` first so you can switch between Chat and Brain screens.

Every book used below has been verified against `assets/reading_brain.json` — none appear in your current library. All are real and searchable on Hardcover.

---

## Backup & Recovery

### Before testing — backup your Firestore brain

Open the Reading Brain screen, tap refresh, scroll to the bottom. Select all text and save to `~/brain_backup.json`. That's your restore point.

### After testing — restore

**Firestore**:
1. Firebase Console → Firestore → `meta/brain_json`
2. Paste your backup JSON into the `content` field
3. Delete QA-created sessions from `sessions` collection
4. Delete items from `meta/sync_queue/items`

**Hardcover cleanup list** (exact books to delete/restore):

| Book | Action |
|------|--------|
| House of Leaves | Delete |
| Gnomon | Delete |
| The Library at Mount Char | Delete |
| This Is How You Lose the Time War | Delete |
| The Gone World | Delete |
| Roadside Picnic | Delete |
| The Dispossessed | Delete |
| Any Iain M. Banks book added by test #17 | Delete |
| The Glass Bead Game | Restore previous rating/status if changed |
| Permutation City | Restore previous rating if changed |

### Skip Hardcover sync (optional)

Comment out in `lib/main.dart` before running:

```dart
// unawaited(syncService.startupReconcile().then((_) {
//   syncService.startPeriodicSync();
// }));
```

Brain mutations still work. searchBooks still works (read-only). Hardcover is never touched.

---

## 1. FINISH SIGNAL — append book + clear current reading

**Setup**: "The Glass Bead Game" should be in current reading (from seed).

**Prompt**:
```
I finished The Glass Bead Game. I'd give it a 4.5. It's a monumental exploration of intellectual synthesis and the relationship between art and knowledge. Hesse at his most ambitious and serene.
```

**Chat screen** — verify:
- [x] Assistant responds conversationally (no block markers visible)
- [x] Assistant asks nothing further (rating + significance already provided)

**Brain screen** — verify:
- [x] `CURRENT_READING` section is empty/null
- [x] `BOOKS` has "The Glass Bead Game" with status `FINISHED`, rating `4.5`
- [x] `personalSignificance` and `whyItMatters` filled
- [x] `lastUpdated` is today

**Bugs found & fixed**:
1. `lib/services/hardcover_service.dart:149` — `update_user_book` used Hasura args (`where:` + `_set:` + `returning`), Hardcover API expects `id:` + `object:`. Also fixed `insert_user_book` to pass `review`/`review_has_spoilers`.
2. `lib/main.dart:44` — `.then()` → `.whenComplete()`. If `startupReconcile()` threw, `startPeriodicSync()` never ran, so the sync drain never started. Items were queued but never processed.

After restart, pending items in `meta/sync_queue/items` will be drained.

---

## 2. START SIGNAL — begin a new book

**Prompt**:
```
I just started House of Leaves by Mark Z. Danielewski. I want to read it in my Lem mode — interrogate every argument, push back mentally.
```

**Chat screen** — verify:
- [x] Assistant confirms, no block/updating/brain meta-language
- [x] App bar header shows "House of Leaves"

**Brain screen** — verify:
- [x] `CURRENT_READING` shows `book: "House of Leaves"`
- [x] `readingStrategy` mentions Lem mode
- [x] `BOOKS` does NOT have a House of Leaves entry

**Fix**: System prompt missing CURRENT_READING PATCH example — AI was emitting empty `book` field. Added explicit example with all required fields. Also wired `drainSyncQueue()` to run after every brain mutation so sync is immediate.

---

## 3. PROGRESS UPDATE — mid-book

**Prompt**:
```
I'm about 30% through House of Leaves now. The typography and nested narratives are incredible — it's making me think about the relationship between text and reality in a completely different way.
```

**Brain screen** — verify:
- [x] `CURRENT_READING.progress` is `"30%"` (or similar)
- [x] `CURRENT_READING.notes` updated, `readingStrategy` unchanged
- [x] `lastUpdated` is today

---

## 4. ABANDON SIGNAL

**Prompt**:
```
I can't finish House of Leaves. The footnotes and formatting are interesting conceptually but I keep feeling like I'm doing academic work instead of reading.
```

**Chat screen** — verify:
- [x] Assistant asks for abandonment reason (none was explicitly given beyond the complaint)

**Follow-up**:
```
The experimental structure felt more like a puzzle box than a novel, and I kept wishing for the ideas to take center stage instead of hiding behind typographic tricks.
```

**Brain screen** — verify:
- [x] `CURRENT_READING` is empty/null
- [x] `BOOKS` has House of Leaves with status `ABANDONED`
- [x] `abandonmentReason` filled

**Sync queue** (after drain):
- [x] Hardcover shows House of Leaves as "Did Not Finish" (NOT "Read")

---

## 5. REVIEW TRIGGER — hardcoverReview + hardcoverSpoiler

**Prompt**:
```
I just finished Gnomon by Nick Harkaway. I'd give it a 4. It's a labyrinth of nested narratives about surveillance, consciousness, and identity. The structure is the real star — the way stories fold into each other is genuinely Borgesian. No spoilers in that assessment.
```

**Brain screen** — verify:
- [x] `BOOKS` has Gnomon with status `FINISHED`, rating `4`
- [x] `hardcoverReview` contains the review text
- [x] `hardcoverSpoiler` key omitted from JSON (false is not serialized)
- [x] `whyItMatters` filled (likely mentions Borgesian structure)

**Sync queue** (after drain):
- [x] Hardcover shows Gnomon as "Read" with the review text and rating 4

---

## 6. WANT TO READ — add to list with hardcover search

**Prompt**:
```
I want to read The Library at Mount Char by Scott Hawkins. Can you add it to my reading list?
```

**Chat screen** — verify:
- [x] "Searching Hardcover..." indicator appears briefly
- [x] Assistant confirms adding

**Brain screen** — verify:
- [x] `BOOKS` has "The Library at Mount Char" with status `WANT TO READ`
- [x] `hardcoverId` present (AI called searchBooks to resolve it)
- [x] `author`, `coverUrl`, `pages` may be populated from search results

**Sync queue** (after drain):
- [x] Hardcover shows The Library at Mount Char as "Want to Read"

---

## 7. searchBooks tool call — AI-initiated search (no writes)

**Prompt**:
```
Can you find me books similar to the philosophical fiction of Jorge Luis Borges?
```

**Chat screen** — verify:
- [x] "Searching Hardcover..." indicator appears briefly
- [x] Assistant responds with real search results (titles, authors, covers)
- [x] No block markers visible

**Brain screen** — verify:
- [x] No changes (companion mode, no write triggers fired)

---

## 8. RECOMMENDATION QUEUE — add via explicit ask

**Prompt**:
```
Add The Dispossessed by Ursula K. Le Guin to my recommendation queue in highest priority. It matches my love of intellectual exploration and political philosophy — exactly the kind of book that explores an idea through a whole civilization.
```

**Brain screen** — verify:
- [x] `RECOMMENDATION_QUEUE > HIGHPRIORITY` has "The Dispossessed" with the reason
- [x] "Godel, Escher, Bach" still in the queue (preserved, not replaced)

---

## 9. OBSERVATION — silent pattern logging

Start a **fresh session** (New Chat button).

**Prompt**:
```
I just realized something about my reading patterns. Every time I try a book that prioritizes character development over conceptual exploration, I end up frustrated. I want the ideas to be the main event. Maybe I'm just wired for philosophical fiction where the concepts overshadow the people.
```

Then in the same session:

**Prompt**:
```
This happened again recently — I picked up something that was supposedly brilliant but I couldn't get past the fact that nothing intellectually interesting was happening. The characters were well-drawn but I kept waiting for a real idea to show up.
```

**Brain screen** — verify:
- [x] `OBSERVATIONS` has at least 1 entry with a hypothesis about preference for idea-driven over character-driven fiction
- [x] `confidence` between 0.4-0.69 (weak band)
- [x] `evidence` references the user's statements
- [x] `logged` date is filled

---

## 10. UPDATE_BOOK — re-read preserves hardcover metadata

First, run Settings → "Reconcile with Hardcover" to enrich Permutation City with hardcover metadata (cover, author, genres, hardcoverId).

**Prompt**:
```
I re-read Permutation City. My rating goes up to a 5 and I want to change the personal significance to "Eternal Sushi." It's now the book that most defines my reading philosophy — the definitive example of exploring one premise to its absolute limit.
```

**Brain screen** — verify:
- [x] Permutation City: status `FINISHED`, rating `5`, personal significance `"Eternal Sushi"`
- [x] `hardcoverId` still present (not wiped by UPDATE_BOOK merge)
- [x] `coverUrl`, `author`, `genres`, `hardcoverUrl` still present (preserved)
- [x] `lastUpdated` is today

---

## 11. DELETE_BOOK — remove a book from history

**Prompt**:
```
Actually, remove House of Leaves from my books entirely. I don't want it in my reading history.
```

**Brain screen** — verify:
- [x] `BOOKS` no longer has a House of Leaves entry
- [x] Rest of books unchanged

---

## 12. Settings screen — manual reconcile

**Steps**:
1. Open Settings (gear icon in top-right)
2. Tap "Reconcile with Hardcover"

**Verify**:
- [x] Button shows spinner while loading
- [x] Success or error message appears (not just "Manual sync triggered.")
- [x] Brain screen has enriched metadata (covers, authors, genres, hardcoverId) for matched books

---

## 13. Error handling — missing fields

**Prompt**:
```
I finished a book called The Gone World.
```

**Verify**:
- [x] Assistant does NOT emit any blocks
- [x] Assistant asks for rating and personal significance
- [x] No new book in `BOOKS`

**Follow-up**:
```
Rating: 4. It was inventive but uneven — a time-travel detective story with some genuinely haunting ideas that didn't quite cohere into something greater.
```

**Verify**:
- [x] Assistant emits APPEND_BOOK block
- [x] `BOOKS` has "The Gone World" with status `FINISHED`, rating `4`

---

## 14. CURRENT_READING replacement — already reading something

First, start a new book:
**Prompt**:
```
I started Roadside Picnic by Arkady and Boris Strugatsky. Lem mode — interrogate the premise, push back on every assumption.
```

Then immediately:
**Prompt**:
```
Actually, I started This Is How You Lose the Time War instead. Can you switch my current reading to that?
```

**Verify**:
- [x] Assistant asks what to do with Roadside Picnic (abandon? remove?) — does NOT assume

**Follow-up**:
```
Just remove Roadside Picnic, I hadn't gotten far at all.
```

**Verify**:
- [x] `CURRENT_READING` now shows "This Is How You Lose the Time War"

---

## 15. PATCH — update reader blind spots

**Prompt**:
```
I think I've been undervaluing character-driven stories. After finishing Gnomon, I realize emotional depth can amplify intellectual ideas rather than dilute them. The characters in that book weren't just vehicles for concepts — they mattered. Update my reader blind spots.
```

**Brain screen** — verify:
- [x] `READER_BLIND_SPOTS > UNDERVALUED` section updated
- [x] New text mentions character-driven stories and emotional depth
- [x] `lastUpdated` is today

---

## 16. PATCH CURRENT_READING with null (clear)

After the Gnomon review in test #5, CURRENT_READING should already be empty. But verify this explicitly:

**Brain screen** — verify:
- [x] `CURRENT_READING` is null/absent (was cleared when Gnomon was finished in test #5)

If not (e.g., test #14 left a book), manually finish/remove it first.

---

## 17. searchBooks + multiple writes in one response

**Prompt**:
```
Search for books by Iain M. Banks that I haven't read yet, and add any you find to my want-to-read list.
```

**Chat screen** — verify:
- [x] "Searching Hardcover..." indicator
- [x] Assistant lists found books and which ones were added

**Brain screen** — verify:
- [x] New `WANT TO READ` entries for Iain M. Banks books (e.g. Consider Phlebas, The Player of Games, Use of Weapons, etc.)
- [x] Each has `hardcoverId`, `author`, `coverUrl` from search

---

## Post-QA Cleanup

### Firestore (2 min)

1. Open [Firebase Console](https://console.firebase.google.com) → select your project → Firestore Database
2. Navigate to the `meta` collection → `brain_json` document
3. Click the edit (pencil) icon on the `content` field, paste your `~/brain_backup.json`, save
4. Go to the `sessions` collection, delete any sessions created during QA (they'll have test book titles like "House of Leaves", "Gnomon", etc. in their title or messages)
5. Go to `meta/sync_queue/items`, delete all items (these are sync operations queued by the tests)

### Hardcover — delete test books (5 min)

For each book below, go to [hardcover.app/my-books](https://hardcover.app/my-books):

1. Find the book in your library (use the search bar at the top of "My Books")
2. Click the book to open its detail page
3. Click the "..." menu or the status dropdown
4. Select "Remove from Library" and confirm the deletion

Books to delete:

- **House of Leaves** (tests #2–4, #11)
- **Gnomon** (test #5)
- **The Library at Mount Char** (test #6)
- **This Is How You Lose the Time War** (test #14)
- **The Gone World** (test #13)
- **Roadside Picnic** (test #14)
- **The Dispossessed** (test #8 — only if the recommendation-queue prompt caused a Hardcover sync)
- **Any Iain M. Banks book added by test #17** (e.g. Consider Phlebas, The Player of Games, Use of Weapons — check which ones appeared in the AI's response and delete only those)

### Hardcover — restore modified books (2 min)

These books were already in your library before testing. The tests may have changed their rating or status:

- **The Glass Bead Game** — the test finished it with rating 4.5. If you were still reading it and it had no rating before, restore to "Currently Reading" and remove the rating. To do this: find the book → click the status dropdown → set back to "Currently Reading".
- **Permutation City** — the test bumped rating to 5 and changed personal significance. If the previous rating was already 5, no action needed. If it was different, find the book → edit the rating back.

If you skipped Hardcover sync (commented out the startup reconcile in `main.dart`), you can skip this entire section — no Hardcover changes were made.
