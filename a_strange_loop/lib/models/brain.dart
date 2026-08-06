class Brain {
  String version;
  String lastUpdated;
  BrainMeta meta;
  ReaderProfile readerProfile;
  Map<String, String> readingModes;
  Map<String, VocabularyTerm> vocabulary;
  FavoriteAuthors favoriteAuthors;
  FavoriteBooks favoriteBooks;
  ReaderBlindSpots readerBlindSpots;
  List<EvolutionEntry> readingEvolution;
  List<String> activeQuestions;
  CurrentReading? currentReading;
  RecommendationQueue recommendationQueue;
  List<ObservationEntry> observations;
  List<Book> books;

  Brain({
    this.version = '1.2',
    this.lastUpdated = '',
    required this.meta,
    required this.readerProfile,
    this.readingModes = const {},
    this.vocabulary = const {},
    required this.favoriteAuthors,
    required this.favoriteBooks,
    required this.readerBlindSpots,
    this.readingEvolution = const [],
    this.activeQuestions = const [],
    this.currentReading,
    required this.recommendationQueue,
    this.observations = const [],
    this.books = const [],
  });

  factory Brain.fromJson(Map<String, dynamic> json) {
    return Brain(
      version: json['version'] as String? ?? '1.2',
      lastUpdated: json['lastUpdated'] as String? ?? '',
      meta: BrainMeta.fromJson(json['meta'] as Map<String, dynamic>),
      readerProfile: ReaderProfile.fromJson(
          json['readerProfile'] as Map<String, dynamic>),
      readingModes: (json['readingModes'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          {},
      vocabulary: (json['vocabulary'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(
                  k, VocabularyTerm.fromJson(v as Map<String, dynamic>))) ??
          {},
      favoriteAuthors: FavoriteAuthors.fromJson(
          json['favoriteAuthors'] as Map<String, dynamic>),
      favoriteBooks: FavoriteBooks.fromJson(
          json['favoriteBooks'] as Map<String, dynamic>),
      readerBlindSpots: ReaderBlindSpots.fromJson(
          json['readerBlindSpots'] as Map<String, dynamic>),
      readingEvolution: (json['readingEvolution'] as List<dynamic>?)
              ?.map((e) =>
                  EvolutionEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      activeQuestions: (json['activeQuestions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      currentReading: json['currentReading'] != null
          ? CurrentReading.fromJson(
              json['currentReading'] as Map<String, dynamic>)
          : null,
      recommendationQueue: RecommendationQueue.fromJson(
          json['recommendationQueue'] as Map<String, dynamic>),
      observations: (json['observations'] as List<dynamic>?)
              ?.map((e) =>
                  ObservationEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      books: (json['books'] as List<dynamic>?)
              ?.map((e) => Book.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'lastUpdated': lastUpdated,
      'meta': meta.toJson(),
      'readerProfile': readerProfile.toJson(),
      'readingModes': readingModes,
      'vocabulary': vocabulary.map((k, v) => MapEntry(k, v.toJson())),
      'favoriteAuthors': favoriteAuthors.toJson(),
      'favoriteBooks': favoriteBooks.toJson(),
      'readerBlindSpots': readerBlindSpots.toJson(),
      'readingEvolution':
          readingEvolution.map((e) => e.toJson()).toList(),
      'activeQuestions': activeQuestions,
      'currentReading': currentReading?.toJson(),
      'recommendationQueue': recommendationQueue.toJson(),
      'observations': observations.map((e) => e.toJson()).toList(),
      'books': books.map((e) => e.toJson()).toList(),
    };
  }

  static int _statusPriority(String status) {
    final s = status.trim().toLowerCase();
    if (s == 'reading') return 0;
    if (s == 'want to read') return 1;
    return 2;
  }

  void sortBooksByRecent() {
    books.sort((a, b) {
      final aPrio = _statusPriority(a.status);
      final bPrio = _statusPriority(b.status);
      if (aPrio != bPrio) return aPrio.compareTo(bPrio);

      final aDate = a.dateRead ?? a.dateAdded ?? '';
      final bDate = b.dateRead ?? b.dateAdded ?? '';
      if (aDate.isNotEmpty && bDate.isNotEmpty) {
        return bDate.compareTo(aDate);
      }
      if (aDate.isNotEmpty) return -1;
      if (bDate.isNotEmpty) return 1;
      return a.title.compareTo(b.title);
    });
  }

  String toMarkdownForContext({int maxBooks = 10}) {
    sortBooksByRecent();
    final trimmed = List<Book>.from(books).take(maxBooks).toList();
    final original = books;
    books = trimmed;
    final md = toMarkdown();
    books = original;
    return md;
  }

  String toMarkdown() {
    final buf = StringBuffer();
    buf.writeln('# READING_BRAIN');
    buf.writeln('Version: $version');
    buf.writeln('Last Updated: $lastUpdated');
    buf.writeln();
    buf.writeln('---');
    buf.writeln();
    buf.writeln('## META');
    buf.writeln();
    buf.writeln('Name: ${meta.name}');
    buf.writeln();
    buf.writeln('Started Reading Seriously:');
    buf.writeln(meta.startedReadingSeriously);
    buf.writeln();
    buf.writeln('Primary Goal:');
    buf.writeln();
    buf.writeln(meta.primaryGoal);
    buf.writeln();
    buf.writeln('---');
    buf.writeln();
    buf.writeln('## READER_PROFILE');
    buf.writeln();
    buf.writeln('### Core Philosophy');
    buf.writeln();
    buf.writeln(readerProfile.corePhilosophy);
    buf.writeln();
    buf.writeln('### Things I Consistently Love');
    buf.writeln();
    for (final item in readerProfile.thingsIConsistentlyLove) {
      buf.writeln('- $item');
    }
    buf.writeln();
    buf.writeln('### Narrative Preferences');
    buf.writeln();
    _writePrefs(buf, 'Very High',
        readerProfile.narrativePreferences.veryHigh);
    _writePrefs(
        buf, 'High', readerProfile.narrativePreferences.high);
    _writePrefs(
        buf, 'Medium', readerProfile.narrativePreferences.medium);
    _writePrefs(buf, 'Low', readerProfile.narrativePreferences.low);
    buf.writeln();
    buf.writeln('---');
    buf.writeln();
    buf.writeln('## READING_MODES');
    buf.writeln();
    for (final entry in readingModes.entries) {
      buf.writeln('### ${entry.key}');
      buf.writeln();
      buf.writeln(entry.value);
      buf.writeln();
    }
    buf.writeln('---');
    buf.writeln();
    buf.writeln('## VOCABULARY');
    buf.writeln();
    for (final entry in vocabulary.entries) {
      buf.writeln('### ${entry.key}');
      buf.writeln();
      buf.writeln(entry.value.definition);
      if (entry.value.examples.isNotEmpty) {
        buf.writeln();
        buf.writeln('Examples:');
        buf.writeln();
        for (final ex in entry.value.examples) {
          buf.writeln('- $ex');
        }
      }
      buf.writeln();
    }
    buf.writeln('---');
    buf.writeln();
    buf.writeln('## FAVORITE_AUTHORS');
    buf.writeln();
    _writeAuthTier(buf, 'Tier S', favoriteAuthors.tierS);
    _writeAuthTier(buf, 'Tier A', favoriteAuthors.tierA);
    buf.writeln('---');
    buf.writeln();
    buf.writeln('## FAVORITE_BOOKS');
    buf.writeln();
    for (var i = 0; i < favoriteBooks.ranked.length; i++) {
      buf.writeln('${i + 1}. ${favoriteBooks.ranked[i]}');
    }
    buf.writeln();
    buf.writeln('Favorite Nonfiction');
    buf.writeln();
    for (final b in favoriteBooks.favoriteNonfiction) {
      buf.writeln('- $b');
    }
    buf.writeln();
    buf.writeln('Favorite Short Story Collection');
    buf.writeln();
    for (var i = 0;
        i < favoriteBooks.favoriteShortStoryCollection.length;
        i++) {
      buf.writeln(
          '${i + 1}. ${favoriteBooks.favoriteShortStoryCollection[i]}');
    }
    buf.writeln();
    buf.writeln('---');
    buf.writeln();
    buf.writeln('## READER_BLIND_SPOTS');
    buf.writeln();
    buf.writeln('Things I Probably Overvalue');
    buf.writeln();
    for (final item in readerBlindSpots.overvalued) {
      buf.writeln('- $item');
    }
    buf.writeln();
    buf.writeln('Things I Probably Undervalue');
    buf.writeln();
    buf.writeln(readerBlindSpots.undervalued);
    buf.writeln();
    buf.writeln('Books That Changed My Mind');
    buf.writeln();
    if (readerBlindSpots.booksThatChangedMyMind.isEmpty) {
      buf.writeln('(empty)');
    } else {
      for (final b in readerBlindSpots.booksThatChangedMyMind) {
        buf.writeln('- $b');
      }
    }
    buf.writeln();
    buf.writeln('---');
    buf.writeln();
    buf.writeln('## READING_EVOLUTION');
    buf.writeln();
    for (final entry in readingEvolution) {
      buf.writeln(entry.year);
      buf.writeln();
      buf.writeln(entry.insight);
      buf.writeln();
    }
    buf.writeln('---');
    buf.writeln();
    buf.writeln('## ACTIVE_QUESTIONS');
    buf.writeln();
    for (final q in activeQuestions) {
      buf.writeln('- $q');
      buf.writeln();
    }
    buf.writeln('---');
    buf.writeln();
    buf.writeln('## CURRENT_READING');
    buf.writeln();
    if (currentReading != null && currentReading!.isNotEmpty) {
      buf.writeln('Book:');
      buf.writeln();
      buf.writeln(currentReading!.book);
      buf.writeln();
      buf.writeln('Progress:');
      buf.writeln();
      buf.writeln(currentReading!.progress);
      buf.writeln();
      if (currentReading!.readingStrategy.isNotEmpty) {
        buf.writeln('Current Reading Strategy:');
        buf.writeln();
        buf.writeln(currentReading!.readingStrategy);
        buf.writeln();
      }
      if (currentReading!.notes.isNotEmpty) {
        buf.writeln('Current Notes:');
        buf.writeln();
        buf.writeln(currentReading!.notes);
        buf.writeln();
      }
      if (currentReading!.hardcoverId != null) {
        buf.writeln('Hardcover ID:');
        buf.writeln();
        buf.writeln(currentReading!.hardcoverId);
        buf.writeln();
      }
    } else {
      buf.writeln('(empty)');
      buf.writeln();
    }
    buf.writeln('---');
    buf.writeln();
    buf.writeln('## RECOMMENDATION_QUEUE');
    buf.writeln();
    _writeQueueTier(
        buf, 'Highest Priority', recommendationQueue.highestPriority);
    _writeQueueTier(
        buf, 'High Confidence', recommendationQueue.highConfidence);
    _writeQueueTier(buf, 'Future', recommendationQueue.future);
    buf.writeln('---');
    buf.writeln();
    buf.writeln('## OBSERVATIONS');
    buf.writeln();
    if (observations.isEmpty) {
      buf.writeln('(empty)');
    } else {
      for (final obs in observations) {
        buf.writeln('Evidence:');
        buf.writeln();
        buf.writeln(obs.evidence);
        buf.writeln();
        buf.writeln('Hypothesis:');
        buf.writeln();
        buf.writeln(obs.hypothesis);
        buf.writeln();
        buf.writeln('Confidence: ${obs.confidence}');
        buf.writeln();
        buf.writeln('Logged: ${obs.logged}');
        buf.writeln();
      }
    }
    buf.writeln();
    buf.writeln('---');
    buf.writeln();
    buf.writeln('## BOOKS');
    buf.writeln();
    for (final book in books) {
      buf.writeln('---');
      buf.writeln('# BOOK');
      buf.writeln();
      buf.writeln('Title:');
      buf.writeln();
      buf.writeln(book.title);
      buf.writeln();
      buf.writeln('Status:');
      buf.writeln();
      buf.writeln(book.status);
      buf.writeln();
      if (book.rating != null) {
        buf.writeln('Rating:');
        buf.writeln();
        buf.writeln('${book.rating}');
        buf.writeln();
      }
      if (book.personalSignificance != null) {
        buf.writeln('Personal Significance:');
        buf.writeln();
        buf.writeln(book.personalSignificance);
        buf.writeln();
      }
      if (book.whyItMatters != null) {
        buf.writeln('Why It Matters:');
        buf.writeln();
        buf.writeln(book.whyItMatters);
        buf.writeln();
      }
      if (book.progress != null) {
        buf.writeln('Progress:');
        buf.writeln();
        buf.writeln(book.progress);
        buf.writeln();
      }
      if (book.currentImpression != null) {
        buf.writeln('Current Impression:');
        buf.writeln();
        buf.writeln(book.currentImpression);
        buf.writeln();
      }
      if (book.readingStrategy != null) {
        buf.writeln('Reading Strategy:');
        buf.writeln();
        buf.writeln(book.readingStrategy);
        buf.writeln();
      }
      if (book.abandonmentReason != null) {
        buf.writeln('Abandonment Reason:');
        buf.writeln();
        buf.writeln(book.abandonmentReason);
        buf.writeln();
      }
      if (book.hardcoverId != null) {
        buf.writeln('Hardcover ID:');
        buf.writeln();
        buf.writeln(book.hardcoverId);
        buf.writeln();
      }
      if (book.author != null) {
        buf.writeln('Author:');
        buf.writeln();
        buf.writeln(book.author);
        buf.writeln();
      }
      if (book.coverUrl != null) {
        buf.writeln('Cover:');
        buf.writeln();
        buf.writeln(book.coverUrl);
        buf.writeln();
      }
      if (book.genres.isNotEmpty) {
        buf.writeln('Genres:');
        buf.writeln();
        for (final genre in book.genres) {
          buf.writeln('- $genre');
        }
        buf.writeln();
      }
      if (book.pages != null) {
        buf.writeln('Pages:');
        buf.writeln();
        buf.writeln('${book.pages}');
        buf.writeln();
      }
      if (book.hardcoverUrl != null) {
        buf.writeln('Hardcover URL:');
        buf.writeln();
        buf.writeln(book.hardcoverUrl);
        buf.writeln();
      }
      if (book.dateAdded != null) {
        buf.writeln('Date Added:');
        buf.writeln();
        buf.writeln(book.dateAdded);
        buf.writeln();
      }
      if (book.dateRead != null) {
        buf.writeln('Date Read:');
        buf.writeln();
        buf.writeln(book.dateRead);
        buf.writeln();
      }
      if (book.hardcoverStatus != null) {
        buf.writeln('Hardcover Status:');
        buf.writeln();
        buf.writeln(book.hardcoverStatus);
        buf.writeln();
      }
      if (book.hardcoverReview != null) {
        buf.writeln('Hardcover Review:');
        buf.writeln();
        buf.writeln(book.hardcoverReview);
        buf.writeln();
      }
      if (book.hardcoverSpoiler) {
        buf.writeln('Hardcover Spoiler:');
        buf.writeln();
        buf.writeln('true');
        buf.writeln();
      }
    }
    return buf.toString();
  }

  void _writePrefs(
      StringBuffer buf, String label, List<String> items) {
    buf.writeln(label);
    buf.writeln();
    for (final item in items) {
      buf.writeln('- $item');
    }
    buf.writeln();
  }

  void _writeAuthTier(StringBuffer buf, String label, List<String> authors) {
    buf.writeln(label);
    buf.writeln();
    for (final a in authors) {
      buf.writeln('- $a');
    }
    buf.writeln();
  }

  void _writeQueueTier(StringBuffer buf, String label,
      List<QueueEntry> entries) {
    buf.writeln(label);
    buf.writeln();
    if (entries.isEmpty) {
      buf.writeln('(empty)');
    } else {
      for (final entry in entries) {
        buf.writeln('- ${entry.book}');
        buf.writeln();
        buf.writeln('Reason');
        buf.writeln();
        buf.writeln(entry.reason);
        buf.writeln();
      }
    }
    buf.writeln('---');
    buf.writeln();
  }
}

class BrainMeta {
  String name;
  String startedReadingSeriously;
  String primaryGoal;

  BrainMeta({
    required this.name,
    required this.startedReadingSeriously,
    required this.primaryGoal,
  });

  factory BrainMeta.fromJson(Map<String, dynamic> json) {
    return BrainMeta(
      name: json['name'] as String,
      startedReadingSeriously: json['startedReadingSeriously'] as String,
      primaryGoal: json['primaryGoal'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'startedReadingSeriously': startedReadingSeriously,
        'primaryGoal': primaryGoal,
      };
}

class ReaderProfile {
  String corePhilosophy;
  List<String> thingsIConsistentlyLove;
  NarrativePreferences narrativePreferences;

  ReaderProfile({
    required this.corePhilosophy,
    this.thingsIConsistentlyLove = const [],
    required this.narrativePreferences,
  });

  factory ReaderProfile.fromJson(Map<String, dynamic> json) {
    return ReaderProfile(
      corePhilosophy: json['corePhilosophy'] as String,
      thingsIConsistentlyLove:
          (json['thingsIConsistentlyLove'] as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toList() ??
              [],
      narrativePreferences: NarrativePreferences.fromJson(
          json['narrativePreferences'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
        'corePhilosophy': corePhilosophy,
        'thingsIConsistentlyLove': thingsIConsistentlyLove,
        'narrativePreferences': narrativePreferences.toJson(),
      };
}

class NarrativePreferences {
  List<String> veryHigh;
  List<String> high;
  List<String> medium;
  List<String> low;

  NarrativePreferences({
    this.veryHigh = const [],
    this.high = const [],
    this.medium = const [],
    this.low = const [],
  });

  factory NarrativePreferences.fromJson(Map<String, dynamic> json) {
    return NarrativePreferences(
      veryHigh: (json['veryHigh'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      high: (json['high'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      medium: (json['medium'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      low: (json['low'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'veryHigh': veryHigh,
        'high': high,
        'medium': medium,
        'low': low,
      };
}

class VocabularyTerm {
  String definition;
  List<String> examples;

  VocabularyTerm({required this.definition, this.examples = const []});

  factory VocabularyTerm.fromJson(Map<String, dynamic> json) {
    return VocabularyTerm(
      definition: json['definition'] as String,
      examples: (json['examples'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'definition': definition,
        'examples': examples,
      };
}

class FavoriteAuthors {
  List<String> tierS;
  List<String> tierA;

  FavoriteAuthors({this.tierS = const [], this.tierA = const []});

  factory FavoriteAuthors.fromJson(Map<String, dynamic> json) {
    return FavoriteAuthors(
      tierS: (json['tierS'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      tierA: (json['tierA'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'tierS': tierS,
        'tierA': tierA,
      };
}

class FavoriteBooks {
  List<String> ranked;
  List<String> favoriteNonfiction;
  List<String> favoriteShortStoryCollection;

  FavoriteBooks({
    this.ranked = const [],
    this.favoriteNonfiction = const [],
    this.favoriteShortStoryCollection = const [],
  });

  factory FavoriteBooks.fromJson(Map<String, dynamic> json) {
    return FavoriteBooks(
      ranked: (json['ranked'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      favoriteNonfiction:
          (json['favoriteNonfiction'] as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toList() ??
              [],
      favoriteShortStoryCollection:
          (json['favoriteShortStoryCollection'] as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toList() ??
              [],
    );
  }

  Map<String, dynamic> toJson() => {
        'ranked': ranked,
        'favoriteNonfiction': favoriteNonfiction,
        'favoriteShortStoryCollection': favoriteShortStoryCollection,
      };
}

class ReaderBlindSpots {
  List<String> overvalued;
  String undervalued;
  List<String> booksThatChangedMyMind;

  ReaderBlindSpots({
    this.overvalued = const [],
    this.undervalued = '',
    this.booksThatChangedMyMind = const [],
  });

  factory ReaderBlindSpots.fromJson(Map<String, dynamic> json) {
    return ReaderBlindSpots(
      overvalued: (json['overvalued'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      undervalued: json['undervalued'] as String? ?? '',
      booksThatChangedMyMind:
          (json['booksThatChangedMyMind'] as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toList() ??
              [],
    );
  }

  Map<String, dynamic> toJson() => {
        'overvalued': overvalued,
        'undervalued': undervalued,
        'booksThatChangedMyMind': booksThatChangedMyMind,
      };
}

class EvolutionEntry {
  String year;
  String insight;

  EvolutionEntry({required this.year, required this.insight});

  factory EvolutionEntry.fromJson(Map<String, dynamic> json) {
    return EvolutionEntry(
      year: json['year'] as String,
      insight: json['insight'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'year': year,
        'insight': insight,
      };
}

String _coerceString(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

class CurrentReading {
  String book;
  String progress;
  String readingStrategy;
  String notes;
  String? hardcoverId;

  CurrentReading({
    this.book = '',
    this.progress = '',
    this.readingStrategy = '',
    this.notes = '',
    this.hardcoverId,
  });

  bool get isNotEmpty =>
      book.isNotEmpty ||
      progress.isNotEmpty ||
      readingStrategy.isNotEmpty ||
      notes.isNotEmpty;

  factory CurrentReading.fromJson(Map<String, dynamic> json) {
    return CurrentReading(
      book: _coerceString(json['book']),
      progress: _coerceString(json['progress']),
      readingStrategy: _coerceString(json['readingStrategy']),
      notes: _coerceString(json['notes']),
      hardcoverId: json['hardcoverId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'book': book,
      'progress': progress,
      'readingStrategy': readingStrategy,
      'notes': notes,
    };
    if (hardcoverId != null) map['hardcoverId'] = hardcoverId;
    return map;
  }
}

class RecommendationQueue {
  List<QueueEntry> highestPriority;
  List<QueueEntry> highConfidence;
  List<QueueEntry> future;

  RecommendationQueue({
    this.highestPriority = const [],
    this.highConfidence = const [],
    this.future = const [],
  });

  factory RecommendationQueue.fromJson(Map<String, dynamic> json) {
    return RecommendationQueue(
      highestPriority: (json['highestPriority'] as List<dynamic>?)
              ?.map((e) =>
                  QueueEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      highConfidence: (json['highConfidence'] as List<dynamic>?)
              ?.map((e) =>
                  QueueEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      future: (json['future'] as List<dynamic>?)
              ?.map((e) =>
                  QueueEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'highestPriority':
            highestPriority.map((e) => e.toJson()).toList(),
        'highConfidence':
            highConfidence.map((e) => e.toJson()).toList(),
        'future': future.map((e) => e.toJson()).toList(),
      };
}

class QueueEntry {
  String book;
  String reason;

  QueueEntry({required this.book, required this.reason});

  factory QueueEntry.fromJson(Map<String, dynamic> json) {
    return QueueEntry(
      book: (json['book'] ?? json['title'] ?? '') as String,
      reason: json['reason'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'book': book,
        'reason': reason,
      };
}

class ObservationEntry {
  String evidence;
  String hypothesis;
  double confidence;
  String logged;

  ObservationEntry({
    required this.evidence,
    required this.hypothesis,
    required this.confidence,
    required this.logged,
  });

  factory ObservationEntry.fromJson(Map<String, dynamic> json) {
    return ObservationEntry(
      evidence: json['evidence'] as String,
      hypothesis: json['hypothesis'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      logged: json['logged'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'evidence': evidence,
        'hypothesis': hypothesis,
        'confidence': confidence,
        'logged': logged,
      };
}

class Book {
  String title;
  String status;
  double? rating;
  double? hardcoverRating;
  String? personalSignificance;
  String? whyItMatters;
  String? progress;
  String? currentImpression;
  String? readingStrategy;
  String? abandonmentReason;

  String? hardcoverId;
  String? author;
  String? coverUrl;
  List<String> genres;
  int? pages;
  String? hardcoverUrl;
  String? dateAdded;
  String? dateRead;
  String? hardcoverStatus;
  String? hardcoverReview;
  bool hardcoverSpoiler;

  Book({
    required this.title,
    required this.status,
    this.rating,
    this.hardcoverRating,
    this.personalSignificance,
    this.whyItMatters,
    this.progress,
    this.currentImpression,
    this.readingStrategy,
    this.abandonmentReason,
    this.hardcoverId,
    this.author,
    this.coverUrl,
    this.genres = const [],
    this.pages,
    this.hardcoverUrl,
    this.dateAdded,
    this.dateRead,
    this.hardcoverStatus,
    this.hardcoverReview,
    this.hardcoverSpoiler = false,
  });

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      title: json['title'] as String,
      status: json['status'] as String,
      rating: _resolveRating(json),
      hardcoverRating: (json['hardcoverRating'] as num?)?.toDouble(),
      personalSignificance: json['personalSignificance'] as String?,
      whyItMatters: json['whyItMatters'] as String?,
      progress: json['progress'] as String?,
      currentImpression: json['currentImpression'] as String?,
      readingStrategy: json['readingStrategy'] as String?,
      abandonmentReason: json['abandonmentReason'] as String?,
      hardcoverId: json['hardcoverId'] as String?,
      author: json['author'] as String?,
      coverUrl: json['coverUrl'] as String?,
      genres: (json['genres'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      pages: json['pages'] as int?,
      hardcoverUrl: json['hardcoverUrl'] as String?,
      dateAdded: json['dateAdded'] as String?,
      dateRead: json['dateRead'] as String?,
      hardcoverStatus: json['hardcoverStatus'] as String?,
      hardcoverReview: json['hardcoverReview'] as String?,
      hardcoverSpoiler: json['hardcoverSpoiler'] as bool? ?? false,
    );
  }

  static double? _resolveRating(Map<String, dynamic> json) {
    final r = (json['rating'] as num?)?.toDouble();
    final hr = (json['hardcoverRating'] as num?)?.toDouble();
    if (hr != null && r != hr) return hr;
    if (r != null) return r;
    return hr;
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'title': title,
      'status': status,
    };
    if (rating != null) map['rating'] = rating;
    if (hardcoverRating != null) map['hardcoverRating'] = hardcoverRating;
    if (personalSignificance != null) {
      map['personalSignificance'] = personalSignificance;
    }
    if (whyItMatters != null) map['whyItMatters'] = whyItMatters;
    if (progress != null) map['progress'] = progress;
    if (currentImpression != null) {
      map['currentImpression'] = currentImpression;
    }
    if (readingStrategy != null) {
      map['readingStrategy'] = readingStrategy;
    }
    if (abandonmentReason != null) {
      map['abandonmentReason'] = abandonmentReason;
    }
    if (hardcoverId != null) map['hardcoverId'] = hardcoverId;
    if (author != null) map['author'] = author;
    if (coverUrl != null) map['coverUrl'] = coverUrl;
    if (genres.isNotEmpty) map['genres'] = genres;
    if (pages != null) map['pages'] = pages;
    if (hardcoverUrl != null) map['hardcoverUrl'] = hardcoverUrl;
    if (dateAdded != null) map['dateAdded'] = dateAdded;
    if (dateRead != null) map['dateRead'] = dateRead;
    if (hardcoverStatus != null) map['hardcoverStatus'] = hardcoverStatus;
    if (hardcoverReview != null) map['hardcoverReview'] = hardcoverReview;
    if (hardcoverSpoiler) map['hardcoverSpoiler'] = hardcoverSpoiler;
    return map;
  }

  bool get isStub =>
      personalSignificance == null &&
      whyItMatters == null &&
      readingStrategy == null &&
      abandonmentReason == null &&
      currentImpression == null &&
      progress == null;
}
