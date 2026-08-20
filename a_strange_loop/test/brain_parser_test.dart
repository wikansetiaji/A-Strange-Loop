import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:a_strange_loop/models/brain.dart';
import 'package:a_strange_loop/services/brain_parser.dart';

void main() {
  String minimalBrainJson() => const JsonEncoder.withIndent('  ').convert({
        'version': '1.2',
        'lastUpdated': '2026-08-01',
        'meta': {
          'name': 'Test',
          'startedReadingSeriously': '2020',
          'primaryGoal': 'Read',
        },
        'readerProfile': {
          'corePhilosophy': 'Test',
          'thingsIConsistentlyLove': ['A'],
          'narrativePreferences': {
            'veryHigh': ['VH'],
            'high': ['H'],
            'medium': ['M'],
            'low': ['L'],
          },
        },
        'readingModes': {},
        'vocabulary': {},
        'favoriteAuthors': {'tierS': [], 'tierA': []},
        'favoriteBooks': {
          'ranked': [],
          'favoriteNonfiction': [],
          'favoriteShortStoryCollection': [],
        },
        'readerBlindSpots': {
          'overvalued': [],
          'undervalued': '',
          'booksThatChangedMyMind': [],
        },
        'readingEvolution': [],
        'activeQuestions': [],
        'currentReading': null,
        'recommendationQueue': {
          'highestPriority': [],
          'highConfidence': [],
          'future': [],
        },
        'observations': [],
        'books': [],
      });

  group('BrainParser static methods', () {
    test('appendBook adds book to books array', () {
      final result = BrainParser.appendBook(minimalBrainJson(), {
        'title': 'New Book',
        'status': 'Finished',
        'rating': 4,
        'personalSignificance': 'Test',
        'whyItMatters': 'Testing',
        'hardcoverReview': 'Loved it',
        'hardcoverSpoiler': false,
      });

      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      final books = updated['books'] as List;
      expect(books.length, 1);
      expect(books[0]['title'], 'New Book');
      expect(books[0]['status'], 'Finished');
      expect(books[0]['rating'], 4);
      expect(books[0]['hardcoverReview'], 'Loved it');
    });

    test('updateBook replaces existing book', () {
      final brainJson = minimalBrainJson();
      final brain = jsonDecode(brainJson) as Map<String, dynamic>;
      brain['books'] = [
        {
          'title': 'Old Book',
          'status': 'Reading',
          'hardcoverId': '123',
          'author': 'Some Author',
          'coverUrl': 'http://example.com/cover.jpg',
          'genres': ['Sci-Fi'],
          'pages': 300,
          'hardcoverUrl': 'http://example.com/book',
          'dateAdded': '2026-01-01',
          'dateRead': null,
        }
      ];
      final enrichedJson = jsonEncode(brain);

      final result = BrainParser.updateBook(enrichedJson, 'Old Book', {
        'title': 'Old Book',
        'status': 'Finished',
        'rating': 5,
        'personalSignificance': 'Sushi',
        'whyItMatters': 'Life changing',
      });

      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      final books = updated['books'] as List;
      expect(books.length, 1);
      expect(books[0]['status'], 'Finished');
      expect(books[0]['rating'], 5);
      expect(books[0]['hardcoverId'], '123');
      expect(books[0]['author'], 'Some Author');
      expect(books[0]['coverUrl'], 'http://example.com/cover.jpg');
      expect(books[0]['genres'], ['Sci-Fi']);
      expect(books[0]['pages'], 300);
      expect(books[0]['hardcoverUrl'], 'http://example.com/book');
      expect(books[0]['dateAdded'], '2026-01-01');
    });

    test('deleteBook removes book', () {
      final brainJson = minimalBrainJson();
      final brain = jsonDecode(brainJson) as Map<String, dynamic>;
      brain['books'] = [
        {'title': 'To Delete', 'status': 'Want to Read'},
        {'title': 'Keep', 'status': 'Finished', 'rating': 4},
      ];
      final withBooks = jsonEncode(brain);

      final result = BrainParser.deleteBook(withBooks, 'To Delete');
      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      final books = updated['books'] as List;
      expect(books.length, 1);
      expect(books[0]['title'], 'Keep');
    });

    test('patchBrain sets CURRENT_READING', () {
      final result = BrainParser.patchBrain(
        minimalBrainJson(),
        'CURRENT_READING',
        {
          'book': 'New Read',
          'progress': '10%',
          'readingStrategy': 'Slow',
          'notes': 'Interesting so far',
          'hardcoverId': '42',
        },
        reason: 'User started a book',
        confidence: 1.0,
      );

      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      final cr = updated['currentReading'] as Map<String, dynamic>;
      expect(cr['book'], 'New Read');
      expect(cr['progress'], '10%');
      expect(cr['hardcoverId'], '42');
    });

    test('patchBrain with null clears CURRENT_READING', () {
      final brainJson = minimalBrainJson();
      final brain = jsonDecode(brainJson) as Map<String, dynamic>;
      brain['currentReading'] = {
        'book': 'Old Read',
        'progress': '50%',
        'readingStrategy': '',
        'notes': '',
      };
      final withCr = jsonEncode(brain);

      final result = BrainParser.patchBrain(
        withCr,
        'CURRENT_READING',
        null,
        reason: 'Book finished',
        confidence: 1.0,
      );

      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      expect(updated['currentReading'], isNull);
    });

    test('patchBrain ACTIVE_QUESTIONS replaces questions', () {
      final result = BrainParser.patchBrain(
        minimalBrainJson(),
        'ACTIVE_QUESTIONS',
        [
          'What is the nature of reality?',
          'How does consciousness emerge?',
        ],
        reason: 'Discovery',
        confidence: 0.85,
      );

      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      final questions = updated['activeQuestions'] as List;
      expect(questions.length, 2);
      expect(questions[0], 'What is the nature of reality?');
    });

    test('addObservation: 3 similar hypotheses remove first 2', () {
      final brainJson = minimalBrainJson();
      final brain = jsonDecode(brainJson) as Map<String, dynamic>;
      brain['observations'] = [
        {
          'evidence': 'Ev 1',
          'hypothesis': 'user values conciseness over emotional depth',
          'confidence': 0.5,
          'logged': '2026-07-01',
        },
        {
          'evidence': 'Ev 2',
          'hypothesis': 'user conciseness over emotional depth values',
          'confidence': 0.6,
          'logged': '2026-07-15',
        },
      ];
      final withObs = jsonEncode(brain);

      final result = BrainParser.addObservation(withObs, {
        'evidence': 'Ev 3',
        'hypothesis': 'user values conciseness over emotional depth always',
        'confidence': 0.55,
        'logged': '2026-08-01',
      });

      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      final obs = updated['observations'] as List;
      expect(obs.length, 0);
    });

    test('addObservation adds observation normally', () {
      final result = BrainParser.addObservation(minimalBrainJson(), {
        'evidence': 'User mentioned enjoying short chapters',
        'hypothesis': 'User prefers concise writing',
        'confidence': 0.6,
        'logged': '2026-08-01',
      });

      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      final obs = updated['observations'] as List;
      expect(obs.length, 1);
      expect(obs[0]['hypothesis'], 'User prefers concise writing');
      expect(obs[0]['confidence'], 0.6);
    });

    test('updates lastUpdated after mutation', () {
      final result = BrainParser.appendBook(minimalBrainJson(), {
        'title': 'X',
        'status': 'Want to Read',
      });

      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      expect(updated['lastUpdated'], isNot('2026-08-01'));
      expect(updated['lastUpdated'], matches(RegExp(r'\d{4}-\d{2}-\d{2}')));
    });

    test('generates patch log entries', () {
      final brainJson = minimalBrainJson();
      final brain = jsonDecode(brainJson) as Map<String, dynamic>;
      brain['books'] = [{'title': 'To Delete', 'status': 'Want to Read'}];
      final withBooks = jsonEncode(brain);

      final result = BrainParser.deleteBook(withBooks, 'To Delete');
      expect(result.log.length, 1);
      expect(result.log[0].operation, 'DELETE_BOOK');
      expect(result.log[0].target, 'To Delete');
    });

    test('patchBrain generates log with confidence and reason', () {
      final result = BrainParser.patchBrain(
        minimalBrainJson(),
        'ACTIVE_QUESTIONS',
        ['Q'],
        reason: 'Test',
        confidence: 0.9,
      );

      expect(result.log.length, 1);
      expect(result.log[0].operation, 'PATCH');
      expect(result.log[0].target, 'ACTIVE_QUESTIONS');
      expect(result.log[0].confidence, 0.9);
      expect(result.log[0].reason, 'Test');
    });
  });

  group('markdown-style key normalization', () {
    test('patchBrain CURRENT_READING with MiMo capitalized keys updates progress', () {
      final brainJson = minimalBrainJson();
      final brain = jsonDecode(brainJson) as Map<String, dynamic>;
      brain['currentReading'] = {
        'book': 'Luminous',
        'progress': '25%',
        'readingStrategy': 'Egan mode: build the model, follow logical consequences',
        'notes': 'Collection from peak era',
        'hardcoverId': '635023',
      };
      final withCr = jsonEncode(brain);

      final result = BrainParser.patchBrain(
        withCr,
        'CURRENT_READING',
        {
          'Book': 'Luminous',
          'Progress': '30%',
        },
        reason: 'User reported reading progress update',
        confidence: 1.0,
      );

      expect(result.log.length, 1);
      expect(result.log[0].operation, 'PATCH');
      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      final cr = updated['currentReading'] as Map<String, dynamic>;
      expect(cr['progress'], '30%');
      expect(cr['book'], 'Luminous');
      expect(cr['readingStrategy'],
          'Egan mode: build the model, follow logical consequences');
      expect(cr['hardcoverId'], '635023');
    });

    test('appendBook with markdown-style keys adds book', () {
      final result = BrainParser.appendBook(minimalBrainJson(), {
        'Title': 'The Dispossessed',
        'Status': 'Finished',
        'Rating': 5,
        'Personal Significance': 'Sushi',
        'Why It Matters': 'Political philosophy built as a civilization.',
        'Hardcover Review': 'Ursula Le Guin at her most ambitious.',
        'Hardcover Spoiler': false,
      });

      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      final books = updated['books'] as List;
      expect(books.length, 1);
      expect(books[0]['title'], 'The Dispossessed');
      expect(books[0]['status'], 'Finished');
      expect(books[0]['rating'], 5);
      expect(books[0]['personalSignificance'], 'Sushi');
      expect(books[0]['whyItMatters'],
          'Political philosophy built as a civilization.');
      expect(books[0]['hardcoverReview'],
          'Ursula Le Guin at her most ambitious.');
    });

    test('updateBook with markdown-style nested book keys replaces entry', () {
      final brainJson = minimalBrainJson();
      final brain = jsonDecode(brainJson) as Map<String, dynamic>;
      brain['books'] = [
        {
          'title': 'Old Book',
          'status': 'Reading',
          'hardcoverId': '123',
          'author': 'Some Author',
        }
      ];
      final withBooks = jsonEncode(brain);

      final result = BrainParser.updateBook(withBooks, 'Old Book', {
        'Title': 'Old Book',
        'Status': 'Finished',
        'Rating': 5,
        'Personal Significance': 'Sushi',
      });

      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      final books = updated['books'] as List;
      expect(books.length, 1);
      expect(books[0]['status'], 'Finished');
      expect(books[0]['rating'], 5);
      expect(books[0]['personalSignificance'], 'Sushi');
      expect(books[0]['hardcoverId'], '123');
    });

    test('addObservation with markdown-style keys adds observation', () {
      final result = BrainParser.addObservation(minimalBrainJson(), {
        'Evidence': 'User mentioned enjoying short chapters',
        'Hypothesis': 'User prefers concise writing',
        'Confidence': 0.6,
        'Logged': '2026-08-01',
      });

      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      final obs = updated['observations'] as List;
      expect(obs.length, 1);
      expect(obs[0]['hypothesis'], 'User prefers concise writing');
      expect(obs[0]['confidence'], 0.6);
      expect(obs[0]['logged'], '2026-08-01');
    });

    test('patchBrain RECOMMENDATION_QUEUE with markdown keys', () {
      final brainJson = minimalBrainJson();
      final brain = jsonDecode(brainJson) as Map<String, dynamic>;
      brain['recommendationQueue'] = {
        'highestPriority': [
          {'book': 'The Dispossessed', 'reason': 'Old reason'},
        ],
        'highConfidence': [],
        'future': [],
      };
      final withQueue = jsonEncode(brain);

      final result = BrainParser.patchBrain(
        withQueue,
        'RECOMMENDATION_QUEUE',
        {
          'Highest Priority': [
            {'Book': 'The Dispossessed', 'Reason': 'New reason'},
          ],
          'High Confidence': [],
          'Future': [],
        },
        reason: 'User requested',
        confidence: 1.0,
      );

      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      final queue = updated['recommendationQueue'] as Map<String, dynamic>;
      final hp = queue['highestPriority'] as List;
      expect(hp.length, 1);
      expect(hp[0]['book'], 'The Dispossessed');
      expect(hp[0]['reason'], 'New reason');
    });

    test('patchBrain CURRENT_READING with JSON-string replacementContent', () {
      final brainJson = minimalBrainJson();
      final brain = jsonDecode(brainJson) as Map<String, dynamic>;
      brain['currentReading'] = {
        'book': 'Luminous',
        'progress': '25%',
        'readingStrategy': 'Egan mode: build the model, follow logical consequences',
        'notes': 'Collection from peak era',
        'hardcoverId': '635023',
      };
      final withCr = jsonEncode(brain);

      final result = BrainParser.patchBrain(
        withCr,
        'CURRENT_READING',
        jsonEncode({
          'book': 'Luminous',
          'hardcoverId': '635023',
          'progress': '30%',
          'readingStrategy':
              'Egan mode: build the model, follow logical consequences',
          'notes': 'Collection from peak era',
        }),
        reason: 'Progress update from 25% to 30% on Luminous',
        confidence: 1.0,
      );

      expect(result.log.length, 1);
      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      final cr = updated['currentReading'] as Map<String, dynamic>;
      expect(cr['progress'], '30%');
      expect(cr['book'], 'Luminous');
      expect(cr['hardcoverId'], '635023');
    });

    test('patchBrain CURRENT_READING with JSON-string null clears it', () {
      final brainJson = minimalBrainJson();
      final brain = jsonDecode(brainJson) as Map<String, dynamic>;
      brain['currentReading'] = {
        'book': 'Old Read',
        'progress': '50%',
        'readingStrategy': '',
        'notes': '',
      };
      final withCr = jsonEncode(brain);

      final result = BrainParser.patchBrain(
        withCr,
        'CURRENT_READING',
        jsonEncode(null),
        reason: 'Book finished',
        confidence: 1.0,
      );

      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      expect(updated['currentReading'], isNull);
    });

    test('normalizeToolArgs returns canonical keys recursively', () {
      final normalized = BrainParser.normalizeToolArgs({
        'targetSection': 'CURRENT_READING',
        'replacementContent': {
          'Book': 'X',
          'Progress': '10%',
          'Hardcover ID': '42',
        },
        'reason': 'Test',
        'confidence': 1.0,
      });

      expect(normalized['targetSection'], 'CURRENT_READING');
      expect(normalized['reason'], 'Test');
      final rc = normalized['replacementContent'] as Map<String, dynamic>;
      expect(rc['book'], 'X');
      expect(rc['progress'], '10%');
      expect(rc['hardcoverId'], '42');
    });
  });

  group('BrainParser.applyBlocks (legacy)', () {
    test('APPEND_BOOK adds book', () {
      final result = BrainParser.applyBlocks(minimalBrainJson(), [
        OperationBlock(
          type: BlockType.appendBook,
          rawText: '',
          jsonData: {
            'title': 'New Book',
            'status': 'Finished',
            'rating': 4,
            'hardcoverReview': 'Loved it',
            'hardcoverSpoiler': false,
          },
        ),
      ]);

      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      final books = updated['books'] as List;
      expect(books.length, 1);
      expect(books[0]['title'], 'New Book');
    });

    test('PATCH CURRENT_READING with null clears it', () {
      final brainJson = minimalBrainJson();
      final brain = jsonDecode(brainJson) as Map<String, dynamic>;
      brain['currentReading'] = {
        'book': 'Old Read',
        'progress': '50%',
        'readingStrategy': '',
        'notes': '',
      };
      final withCr = jsonEncode(brain);

      final result = BrainParser.applyBlocks(withCr, [
        OperationBlock(
          type: BlockType.patch,
          rawText: '',
          jsonData: {
            'reason': 'Book finished',
            'evidence': 'User finished',
            'confidence': 1.0,
            'targetSection': 'CURRENT_READING',
            'replacementContent': null,
          },
        ),
      ]);

      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      expect(updated['currentReading'], isNull);
    });

    test('FINISH SIGNAL: APPEND_BOOK + clear CURRENT_READING', () {
      final brainJson = minimalBrainJson();
      final brain = jsonDecode(brainJson) as Map<String, dynamic>;
      brain['currentReading'] = {
        'book': 'The Glass Bead Game',
        'progress': '33%',
        'readingStrategy': 'Dreamy',
        'notes': 'Fascinating',
      };
      final withCr = jsonEncode(brain);

      final result = BrainParser.applyBlocks(withCr, [
        OperationBlock(
          type: BlockType.appendBook,
          rawText: '',
          jsonData: {
            'title': 'The Glass Bead Game',
            'status': 'Finished',
            'rating': 4.5,
            'personalSignificance': 'Sushi',
            'whyItMatters': 'A monumental exploration of intellectual synthesis.',
            'hardcoverReview': 'Hesse at his most ambitious.',
            'hardcoverSpoiler': false,
          },
        ),
        OperationBlock(
          type: BlockType.patch,
          rawText: '',
          jsonData: {
            'reason': 'User finished the book',
            'evidence': 'FINISH SIGNAL',
            'confidence': 1.0,
            'targetSection': 'CURRENT_READING',
            'replacementContent': null,
          },
        ),
      ]);

      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      expect(updated['currentReading'], isNull);

      final books = updated['books'] as List;
      expect(books.length, 1);
      expect(books[0]['title'], 'The Glass Bead Game');
      expect(books[0]['status'], 'Finished');
      expect(books[0]['rating'], 4.5);
      expect(books[0]['personalSignificance'], 'Sushi');
      expect(books[0]['hardcoverReview'], 'Hesse at his most ambitious.');
    });
  });

  group('Brain model toMarkdownForContext', () {
    test('limits books to maxBooks', () {
      final brain = Brain.fromJson({
        ...jsonDecode(minimalBrainJson()) as Map<String, dynamic>,
        'books': [
          for (var i = 0; i < 15; i++)
            {'title': 'Book $i', 'status': 'Finished'},
        ],
      });

      final ctx = brain.toMarkdownForContext(maxBooks: 5);
      final bookCount = '# BOOK\n'.allMatches(ctx).length;
      expect(bookCount, 5);
    });
  });

  group('Book._resolveRating', () {
    test('prefers hardcoverRating when both differ', () {
      final b = Book.fromJson({
        'title': 'T',
        'status': 'Finished',
        'rating': 4,
        'hardcoverRating': 5,
      });
      expect(b.rating, 5);
    });

    test('uses rating when hardcoverRating absent', () {
      final b = Book.fromJson({
        'title': 'T',
        'status': 'Finished',
        'rating': 3.5,
      });
      expect(b.rating, 3.5);
    });

    test('returns hardcoverRating when rating absent', () {
      final b = Book.fromJson({
        'title': 'T',
        'status': 'Finished',
        'hardcoverRating': 2,
      });
      expect(b.rating, 2);
    });

    test('returns null when both absent', () {
      final b = Book.fromJson({
        'title': 'T',
        'status': 'Finished',
      });
      expect(b.rating, isNull);
    });
  });

  group('QueueEntry fromJson', () {
    test('reads "book" key', () {
      final entry = QueueEntry.fromJson({
        'book': 'Test Book',
        'reason': 'Because',
      });
      expect(entry.book, 'Test Book');
      expect(entry.reason, 'Because');
    });

    test('falls back to "title" key', () {
      final entry = QueueEntry.fromJson({
        'title': 'Title Book',
        'reason': 'Title reason',
      });
      expect(entry.book, 'Title Book');
      expect(entry.reason, 'Title reason');
    });
  });

  group('Book hardcoverRating', () {
    test('hardcoverRating round-trips through JSON', () {
      final book = Book(
        title: 'T',
        status: 'Finished',
        rating: 4,
        hardcoverRating: 5,
      );
      final json = book.toJson();
      expect(json['rating'], 4);
      expect(json['hardcoverRating'], 5);

      final roundtripped = Book.fromJson(json);
      expect(roundtripped.rating, 5);
      expect(roundtripped.hardcoverRating, 5);
    });

    test('hardcoverRating null is omitted from JSON', () {
      final book = Book(
        title: 'T',
        status: 'Finished',
        rating: 4,
      );
      final json = book.toJson();
      expect(json.containsKey('hardcoverRating'), isFalse);
    });
  });

  group('Book isStub', () {
    test('bare book from Hardcover is a stub', () {
      final b = Book(
          title: 'T', status: 'Finished', hardcoverId: '1');
      expect(b.isStub, isTrue);
    });

    test('book with personalSignificance is not a stub', () {
      final b = Book(
          title: 'T',
          status: 'Finished',
          personalSignificance: 'Sushi');
      expect(b.isStub, isFalse);
    });

    test('book with whyItMatters is not a stub', () {
      final b = Book(
          title: 'T',
          status: 'Finished',
          whyItMatters: 'Important');
      expect(b.isStub, isFalse);
    });
  });

  group('hardcoverReview and hardcoverSpoiler', () {
    test('hardcoverReview and hardcoverSpoiler are preserved in toJson', () {
      final book = Book(
        title: 'Test',
        status: 'Finished',
        rating: 4,
        hardcoverReview: 'Amazing book!',
        hardcoverSpoiler: true,
      );

      final json = book.toJson();
      expect(json['hardcoverReview'], 'Amazing book!');
      expect(json['hardcoverSpoiler'], true);
    });

    test('hardcoverSpoiler false is omitted from JSON', () {
      final book = Book(
        title: 'Test',
        status: 'Finished',
        hardcoverSpoiler: false,
      );

      final json = book.toJson();
      expect(json.containsKey('hardcoverSpoiler'), isFalse);
    });

    test('book roundtrips through full json cycle', () {
      final original = Book(
        title: 'Roundtrip',
        status: 'Finished',
        rating: 3.5,
        personalSignificance: 'Test',
        whyItMatters: 'Testing',
        hardcoverId: '42',
        author: 'Author Name',
        coverUrl: 'http://example.com/cover.jpg',
        genres: ['Sci-Fi', 'Philosophy'],
        pages: 350,
        hardcoverUrl: 'http://example.com/book',
        dateAdded: '2026-01-01',
        dateRead: '2026-06-15',
        hardcoverStatus: 'Read',
        hardcoverReview: 'Good book',
        hardcoverSpoiler: true,
      );

      final json = original.toJson();
      final roundtripped = Book.fromJson(json);

      expect(roundtripped.title, original.title);
      expect(roundtripped.status, original.status);
      expect(roundtripped.rating, original.rating);
      expect(roundtripped.personalSignificance,
          original.personalSignificance);
      expect(roundtripped.whyItMatters, original.whyItMatters);
      expect(roundtripped.hardcoverId, original.hardcoverId);
      expect(roundtripped.author, original.author);
      expect(roundtripped.coverUrl, original.coverUrl);
      expect(roundtripped.genres, original.genres);
      expect(roundtripped.pages, original.pages);
      expect(roundtripped.hardcoverUrl, original.hardcoverUrl);
      expect(roundtripped.dateAdded, original.dateAdded);
      expect(roundtripped.dateRead, original.dateRead);
      expect(roundtripped.hardcoverStatus, original.hardcoverStatus);
      expect(roundtripped.hardcoverReview, original.hardcoverReview);
      expect(roundtripped.hardcoverSpoiler, original.hardcoverSpoiler);
    });
  });
}
