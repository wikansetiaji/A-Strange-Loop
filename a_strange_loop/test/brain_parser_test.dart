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

  group('BrainParser.parse', () {
    test('splits prose and blocks', () {
      const response = '''
Hey! Let me add that book to your reading brain.

BEGIN_JSON_APPEND_BOOK
{
  "title": "Test Book",
  "status": "Finished",
  "rating": 4.5,
  "personalSignificance": "Good",
  "whyItMatters": "It mattered.",
  "hardcoverReview": "Great read",
  "hardcoverSpoiler": false
}
END_JSON_APPEND_BOOK

I also have an observation about this.

BEGIN_JSON_OBSERVATION
{
  "evidence": "User mentioned enjoying short chapters",
  "hypothesis": "User prefers concise writing",
  "confidence": 0.6,
  "logged": "2026-08-01"
}
END_JSON_OBSERVATION
''';

      final parsed = BrainParser.parse(response);

      expect(parsed.prose,
          contains('Hey! Let me add that book'));
      expect(parsed.prose,
          contains('I also have an observation about this.'));
      expect(parsed.blocks.length, 2);
      expect(parsed.blocks[0].type, BlockType.appendBook);
      expect(parsed.blocks[0].jsonData['title'], 'Test Book');
      expect(parsed.blocks[0].jsonData['rating'], 4.5);
      expect(parsed.blocks[0].jsonData['hardcoverReview'], 'Great read');
      expect(parsed.blocks[0].jsonData['hardcoverSpoiler'], false);
      expect(parsed.blocks[1].type, BlockType.observation);
      expect(parsed.blocks[1].jsonData['confidence'], 0.6);
    });

    test('parses bare markers without BEGIN_JSON_ prefix', () {
      const response = '''
ADDING...

APPEND_BOOK
{
  "title": "Bare Marker Book",
  "status": "Want to Read"
}
END_APPEND_BOOK
''';

      final parsed = BrainParser.parse(response);
      expect(parsed.blocks.length, 1);
      expect(parsed.blocks[0].type, BlockType.appendBook);
      expect(parsed.blocks[0].jsonData['title'], 'Bare Marker Book');
    });

    test('handles PATCH blocks', () {
      const response = '''
BEGIN_JSON_PATCH
{
  "reason": "User asked",
  "evidence": "User asked",
  "confidence": 1.0,
  "targetSection": "ACTIVE_QUESTIONS",
  "replacementContent": ["What is meaning?"]
}
END_JSON_PATCH
''';

      final parsed = BrainParser.parse(response);
      expect(parsed.blocks.length, 1);
      expect(parsed.blocks[0].type, BlockType.patch);
      expect(parsed.blocks[0].jsonData['targetSection'],
          'ACTIVE_QUESTIONS');
      expect(parsed.blocks[0].jsonData['replacementContent'],
          ['What is meaning?']);
    });

    test('ignores malformed JSON inside block', () {
      const response = '''
BEGIN_JSON_APPEND_BOOK
{not valid json}
END_JSON_APPEND_BOOK
''';
      final parsed = BrainParser.parse(response);
      expect(parsed.blocks.length, 0);
    });
  });

  group('BrainParser.applyBlocks', () {
    test('APPEND_BOOK adds book to books array', () {
      final brainJson = minimalBrainJson();
      final blocks = [
        OperationBlock(
          type: BlockType.appendBook,
          rawText: '',
          jsonData: {
            'title': 'New Book',
            'status': 'Finished',
            'rating': 4,
            'personalSignificance': 'Test',
            'whyItMatters': 'Testing',
            'hardcoverReview': 'Loved it',
            'hardcoverSpoiler': false,
          },
        ),
      ];

      final result = BrainParser.applyBlocks(brainJson, blocks);

      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      final books = updated['books'] as List;
      expect(books.length, 1);
      expect(books[0]['title'], 'New Book');
      expect(books[0]['status'], 'Finished');
      expect(books[0]['rating'], 4);
      expect(books[0]['hardcoverReview'], 'Loved it');
      // BUG: false is omitted from JSON — key doesn't exist
      expect(books[0].containsKey('hardcoverSpoiler'), isFalse);
    });

    test('UPDATE_BOOK replaces existing book', () {
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

      final blocks = [
        OperationBlock(
          type: BlockType.updateBook,
          rawText: '',
          jsonData: {
            'targetTitle': 'Old Book',
            'book': {
              'title': 'Old Book',
              'status': 'Finished',
              'rating': 5,
              'personalSignificance': 'Sushi',
              'whyItMatters': 'Life changing',
            },
          },
        ),
      ];

      final result = BrainParser.applyBlocks(enrichedJson, blocks);
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

    test('DELETE_BOOK removes book', () {
      final brainJson = minimalBrainJson();
      final brain = jsonDecode(brainJson) as Map<String, dynamic>;
      brain['books'] = [
        {'title': 'To Delete', 'status': 'Want to Read'},
        {'title': 'Keep', 'status': 'Finished', 'rating': 4},
      ];
      final withBooks = jsonEncode(brain);

      final blocks = [
        OperationBlock(
          type: BlockType.deleteBook,
          rawText: '',
          jsonData: {'targetTitle': 'To Delete'},
        ),
      ];

      final result = BrainParser.applyBlocks(withBooks, blocks);
      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      final books = updated['books'] as List;
      expect(books.length, 1);
      expect(books[0]['title'], 'Keep');
    });

    test('PATCH CURRENT_READING sets book in progress', () {
      final brainJson = minimalBrainJson();

      final blocks = [
        OperationBlock(
          type: BlockType.patch,
          rawText: '',
          jsonData: {
            'reason': 'User started a book',
            'evidence': 'User said they started',
            'confidence': 1.0,
            'targetSection': 'CURRENT_READING',
            'replacementContent': {
              'book': 'New Read',
              'progress': '10%',
              'readingStrategy': 'Slow',
              'notes': 'Interesting so far',
              'hardcoverId': '42',
            },
          },
        ),
      ];

      final result = BrainParser.applyBlocks(brainJson, blocks);
      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      final cr = updated['currentReading'] as Map<String, dynamic>;
      expect(cr['book'], 'New Read');
      expect(cr['progress'], '10%');
      expect(cr['hardcoverId'], '42');
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

      const response = '''
BEGIN_JSON_PATCH
{
  "reason": "Book finished",
  "evidence": "User finished",
  "confidence": 1.0,
  "targetSection": "CURRENT_READING",
  "replacementContent": null
}
END_JSON_PATCH
''';

      final parsed = BrainParser.parse(response);
      final result = BrainParser.applyBlocks(withCr, parsed.blocks);
      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      expect(updated['currentReading'], isNull);
    });

    test('PATCH ACTIVE_QUESTIONS replaces questions', () {
      final brainJson = minimalBrainJson();

      final blocks = [
        OperationBlock(
          type: BlockType.patch,
          rawText: '',
          jsonData: {
            'reason': 'Discovery',
            'evidence': 'Pattern observed',
            'confidence': 0.85,
            'targetSection': 'ACTIVE_QUESTIONS',
            'replacementContent': [
              'What is the nature of reality?',
              'How does consciousness emerge?',
            ],
          },
        ),
      ];

      final result = BrainParser.applyBlocks(brainJson, blocks);
      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      final questions = updated['activeQuestions'] as List;
      expect(questions.length, 2);
      expect(questions[0], 'What is the nature of reality?');
    });

    test('OBSERVATION promotion: 3 similar hypotheses remove first 2', () {
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

      final blocks = [
        OperationBlock(
          type: BlockType.observation,
          rawText: '',
          jsonData: {
            'evidence': 'Ev 3',
            'hypothesis': 'user values conciseness over emotional depth always',
            'confidence': 0.55,
            'logged': '2026-08-01',
          },
        ),
      ];

      final result = BrainParser.applyBlocks(withObs, blocks);
      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      final obs = updated['observations'] as List;

      expect(obs.length, 0);
    });

    test('updates lastUpdated after applying blocks', () {
      final brainJson = minimalBrainJson();
      final blocks = [
        OperationBlock(
          type: BlockType.appendBook,
          rawText: '',
          jsonData: {'title': 'X', 'status': 'Want to Read'},
        ),
      ];

      final result = BrainParser.applyBlocks(brainJson, blocks);
      final updated = jsonDecode(result.brain) as Map<String, dynamic>;
      expect(updated['lastUpdated'], isNot('2026-08-01'));
      expect(updated['lastUpdated'], matches(RegExp(r'\d{4}-\d{2}-\d{2}')));
    });

    test('generates patch log entries', () {
      final brainJson = minimalBrainJson();
      final blocks = [
        OperationBlock(
          type: BlockType.appendBook,
          rawText: '',
          jsonData: {'title': 'Logged Book', 'status': 'Finished'},
        ),
        OperationBlock(
          type: BlockType.patch,
          rawText: '',
          jsonData: {
            'reason': 'Test',
            'evidence': 'Test',
            'confidence': 0.9,
            'targetSection': 'ACTIVE_QUESTIONS',
            'replacementContent': ['Q'],
          },
        ),
      ];

      final result = BrainParser.applyBlocks(brainJson, blocks);
      expect(result.log.length, 2);
      expect(result.log[0].operation, 'APPEND_BOOK');
      expect(result.log[0].target, 'Logged Book');
      expect(result.log[1].operation, 'PATCH');
      expect(result.log[1].target, 'ACTIVE_QUESTIONS');
      expect(result.log[1].confidence, 0.9);
      expect(result.log[1].reason, 'Test');
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

      // Count BOOK section headers
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

  group('Full pipeline integration', () {
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

      const response = '''
Congratulations on finishing! What a journey.

BEGIN_JSON_APPEND_BOOK
{
  "title": "The Glass Bead Game",
  "status": "Finished",
  "rating": 4.5,
  "personalSignificance": "Sushi",
  "whyItMatters": "A monumental exploration of intellectual synthesis.",
  "hardcoverReview": "Hesse at his most ambitious.",
  "hardcoverSpoiler": false
}
END_JSON_APPEND_BOOK

BEGIN_JSON_PATCH
{
  "reason": "User finished the book",
  "evidence": "FINISH SIGNAL",
  "confidence": 1.0,
  "targetSection": "CURRENT_READING",
  "replacementContent": null
}
END_JSON_PATCH
''';

      final parsed = BrainParser.parse(response);
      expect(parsed.prose, contains('Congratulations'));
      expect(parsed.blocks.length, 2);

      final result = BrainParser.applyBlocks(withCr, parsed.blocks);
      final updated = jsonDecode(result.brain) as Map<String, dynamic>;

      expect(updated['currentReading'], isNull);

      final books = updated['books'] as List;
      expect(books.length, 1);
      expect(books[0]['title'], 'The Glass Bead Game');
      expect(books[0]['status'], 'Finished');
      expect(books[0]['rating'], 4.5);
      expect(books[0]['personalSignificance'], 'Sushi');
      expect(books[0]['hardcoverReview'], 'Hesse at his most ambitious.');
      // BUG: false is omitted from JSON (Book.toJson only writes when true)
      expect(books[0].containsKey('hardcoverSpoiler'), isFalse);
    });

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
