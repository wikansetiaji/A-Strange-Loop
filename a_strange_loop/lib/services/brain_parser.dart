import 'dart:convert';
import 'package:a_strange_loop/models/brain.dart';

enum BlockType { appendBook, updateBook, deleteBook, patch, observation }

class OperationBlock {
  final BlockType type;
  final String rawText;
  final Map<String, dynamic> jsonData;

  const OperationBlock({
    required this.type,
    required this.rawText,
    required this.jsonData,
  });
}

class PatchLogEntry {
  final String operation;
  final String target;
  final double? confidence;
  final String? reason;

  const PatchLogEntry({
    required this.operation,
    required this.target,
    this.confidence,
    this.reason,
  });

  Map<String, dynamic> toMap() => {
        'operation': operation,
        'target': target,
        if (confidence != null) 'confidence': confidence,
        if (reason != null) 'reason': reason,
      };
}

class BrainUpdate {
  final String brain;
  final List<PatchLogEntry> log;

  const BrainUpdate({required this.brain, required this.log});
}

class BrainParser {
  static Map<String, dynamic> normalizeToolArgs(
          Map<String, dynamic> args) =>
      _normalizeKeys(args);

  static BrainUpdate appendBook(
      String brainJson, Map<String, dynamic> data) {
    final log = <PatchLogEntry>[];
    Brain brain;
    try {
      brain = Brain.fromJson(jsonDecode(brainJson) as Map<String, dynamic>);
    } catch (_) {
      return BrainUpdate(brain: brainJson, log: log);
    }

    final book = Book.fromJson(_normalizeKeys(data));
    brain.books.add(book);
    log.add(PatchLogEntry(operation: 'APPEND_BOOK', target: book.title));

    brain.lastUpdated = _todayString();
    return BrainUpdate(
      brain: const JsonEncoder.withIndent('  ').convert(brain.toJson()),
      log: log,
    );
  }

  static BrainUpdate updateBook(
      String brainJson, String targetTitle, Map<String, dynamic> data) {
    final log = <PatchLogEntry>[];
    Brain brain;
    try {
      brain = Brain.fromJson(jsonDecode(brainJson) as Map<String, dynamic>);
    } catch (_) {
      return BrainUpdate(brain: brainJson, log: log);
    }

    final idx = brain.books.indexWhere((b) => b.title == targetTitle);
    if (idx != -1) {
      final existing = brain.books[idx];
      final merged = Book.fromJson({
        ...existing.toJson(),
        ..._normalizeKeys(data),
      });
      brain.books[idx] = merged;
      log.add(PatchLogEntry(
          operation: 'UPDATE_BOOK', target: targetTitle));
    }

    brain.lastUpdated = _todayString();
    return BrainUpdate(
      brain: const JsonEncoder.withIndent('  ').convert(brain.toJson()),
      log: log,
    );
  }

  static BrainUpdate deleteBook(String brainJson, String targetTitle) {
    final log = <PatchLogEntry>[];
    Brain brain;
    try {
      brain = Brain.fromJson(jsonDecode(brainJson) as Map<String, dynamic>);
    } catch (_) {
      return BrainUpdate(brain: brainJson, log: log);
    }

    brain.books.removeWhere((b) => b.title == targetTitle);
    log.add(PatchLogEntry(operation: 'DELETE_BOOK', target: targetTitle));

    brain.lastUpdated = _todayString();
    return BrainUpdate(
      brain: const JsonEncoder.withIndent('  ').convert(brain.toJson()),
      log: log,
    );
  }

  static BrainUpdate patchBrain(String brainJson, String targetSection,
      dynamic replacementContent,
      {String? reason, double? confidence}) {
    final log = <PatchLogEntry>[];
    Brain brain;
    try {
      brain = Brain.fromJson(jsonDecode(brainJson) as Map<String, dynamic>);
    } catch (_) {
      return BrainUpdate(brain: brainJson, log: log);
    }

    final applied = _applyJsonPatch(brain, targetSection, replacementContent);
    if (!applied) {
      return BrainUpdate(brain: brainJson, log: log);
    }
    log.add(PatchLogEntry(
      operation: 'PATCH',
      target: targetSection,
      reason: reason,
      confidence: confidence,
    ));

    brain.lastUpdated = _todayString();
    return BrainUpdate(
      brain: const JsonEncoder.withIndent('  ').convert(brain.toJson()),
      log: log,
    );
  }

  static BrainUpdate addObservation(
      String brainJson, Map<String, dynamic> data) {
    final log = <PatchLogEntry>[];
    Brain brain;
    try {
      brain = Brain.fromJson(jsonDecode(brainJson) as Map<String, dynamic>);
    } catch (_) {
      return BrainUpdate(brain: brainJson, log: log);
    }

    final normalizedData = _normalizeKeys(data);
    final evidence = normalizedData['evidence'] as String? ?? '';
    final hypothesis = normalizedData['hypothesis'] as String? ?? '';
    final confidence =
        (normalizedData['confidence'] as num?)?.toDouble() ?? 0.0;
    final logged = normalizedData['logged'] as String? ?? '';

    final matching = <int>[];
    for (var i = 0; i < brain.observations.length; i++) {
      if (_similarHypotheses(
          brain.observations[i].hypothesis, hypothesis)) {
        matching.add(i);
      }
    }

    if (matching.length >= 2) {
      for (final idx in matching.reversed) {
        brain.observations.removeAt(idx);
      }
      log.add(PatchLogEntry(
        operation: 'OBSERVATION_PROMOTION',
        target: hypothesis,
        confidence: confidence,
        reason: '${matching.length} matching observations cleaned up',
      ));
    } else {
      brain.observations.add(ObservationEntry(
        evidence: evidence,
        hypothesis: hypothesis,
        confidence: confidence,
        logged: logged,
      ));
      log.add(PatchLogEntry(
        operation: 'OBSERVATION',
        target: hypothesis,
        confidence: confidence,
      ));
    }

    brain.lastUpdated = _todayString();
    return BrainUpdate(
      brain: const JsonEncoder.withIndent('  ').convert(brain.toJson()),
      log: log,
    );
  }

  static BrainUpdate applyBlocks(
      String brainJson, List<OperationBlock> blocks) {
    final log = <PatchLogEntry>[];
    Brain brain;
    try {
      brain = Brain.fromJson(jsonDecode(brainJson) as Map<String, dynamic>);
    } catch (_) {
      return BrainUpdate(brain: brainJson, log: log);
    }

    for (final block in blocks) {
      final jsonData = _normalizeKeys(block.jsonData);
      switch (block.type) {
        case BlockType.appendBook:
          try {
            final book = Book.fromJson(jsonData);
            brain.books.add(book);
            log.add(PatchLogEntry(
                operation: 'APPEND_BOOK', target: book.title));
          } catch (_) {}
          break;

        case BlockType.updateBook:
          try {
            final targetTitle =
                jsonData['targetTitle'] as String? ?? '';
            final bookJson = jsonData['book'] as Map<String, dynamic>?;
            if (targetTitle.isEmpty || bookJson == null) break;
            final idx = brain.books
                .indexWhere((b) => b.title == targetTitle);
            if (idx != -1) {
              final existing = brain.books[idx];
              final merged = Book.fromJson({
                ...existing.toJson(),
                ...bookJson,
              });
              brain.books[idx] = merged;
              log.add(PatchLogEntry(
                  operation: 'UPDATE_BOOK', target: targetTitle));
            }
          } catch (_) {}
          break;

        case BlockType.deleteBook:
          try {
            final targetTitle =
                jsonData['targetTitle'] as String? ?? '';
            if (targetTitle.isEmpty) break;
            brain.books.removeWhere((b) => b.title == targetTitle);
            log.add(PatchLogEntry(
                operation: 'DELETE_BOOK', target: targetTitle));
          } catch (_) {}
          break;

        case BlockType.patch:
          try {
            final targetSection =
                (jsonData['targetSection'] ??
                        jsonData['target']) as String? ??
                    '';
            final replacementContent = jsonData['replacementContent'] ??
                jsonData['replace'];
            final reason = jsonData['reason'] as String?;
            final confidence =
                (jsonData['confidence'] as num?)?.toDouble();
            if (targetSection.isEmpty) break;
            if (replacementContent == null &&
                targetSection != 'CURRENT_READING') {
              break;
            }

            final applied = _applyJsonPatch(brain, targetSection, replacementContent);
            if (applied) {
              log.add(PatchLogEntry(
                operation: 'PATCH',
                target: targetSection,
                reason: reason,
                confidence: confidence,
              ));
            }
          } catch (_) {}
          break;

        case BlockType.observation:
          try {
            final evidence =
                jsonData['evidence'] as String? ?? '';
            final hypothesis =
                jsonData['hypothesis'] as String? ?? '';
            final confidence =
                (jsonData['confidence'] as num?)?.toDouble() ?? 0.0;
            final logged =
                jsonData['logged'] as String? ?? '';

            final matching = <int>[];
            for (var i = 0; i < brain.observations.length; i++) {
              if (_similarHypotheses(
                  brain.observations[i].hypothesis, hypothesis)) {
                matching.add(i);
              }
            }

            if (matching.length >= 2) {
              for (final idx in matching.reversed) {
                brain.observations.removeAt(idx);
              }
              log.add(PatchLogEntry(
                operation: 'OBSERVATION_PROMOTION',
                target: hypothesis,
                confidence: confidence,
                reason: '${matching.length} matching observations cleaned up',
              ));
            } else {
              brain.observations.add(ObservationEntry(
                evidence: evidence,
                hypothesis: hypothesis,
                confidence: confidence,
                logged: logged,
              ));
              log.add(PatchLogEntry(
                operation: 'OBSERVATION',
                target: hypothesis,
                confidence: confidence,
              ));
            }
          } catch (_) {}
          break;
      }
    }

    brain.lastUpdated = _todayString();

    return BrainUpdate(
      brain: const JsonEncoder.withIndent('  ').convert(brain.toJson()),
      log: log,
    );
  }

  static Map<String, dynamic> _deepMerge(
      Map<String, dynamic> base,
      Map<String, dynamic> overlay) {
    final result = Map<String, dynamic>.from(base);
    for (final entry in overlay.entries) {
      if (entry.value is Map<String, dynamic> &&
          result[entry.key] is Map<String, dynamic>) {
        result[entry.key] = _deepMerge(
          result[entry.key] as Map<String, dynamic>,
          entry.value as Map<String, dynamic>,
        );
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  static bool _applyJsonPatch(
      Brain brain, String targetSection, dynamic replacementContent) {
    if (replacementContent is String &&
        replacementContent.trim().isNotEmpty) {
      try {
        replacementContent = jsonDecode(replacementContent);
      } catch (_) {}
    }
    if (replacementContent is Map<String, dynamic>) {
      replacementContent = _normalizeKeys(replacementContent);
    }
    final parts = targetSection.split('.');
    final section = parts[0];
    final subsection = parts.length > 1 ? parts.sublist(1).join('_') : null;

    switch (section) {
      case 'META':
        if (subsection == null && replacementContent is Map<String, dynamic>) {
          brain.meta = BrainMeta.fromJson(replacementContent);
          return true;
        }
        break;

      case 'READER_PROFILE':
        if (subsection == null && replacementContent is Map<String, dynamic>) {
          final merged = _deepMerge(
              brain.readerProfile.toJson(), replacementContent);
          brain.readerProfile = ReaderProfile.fromJson(merged);
          return true;
        } else if (subsection == 'CORE_PHILOSOPHY' &&
            replacementContent is String) {
          brain.readerProfile.corePhilosophy = replacementContent;
          return true;
        } else if (subsection == 'THINGS_I_CONSISTENTLY_LOVE' &&
            replacementContent is List) {
          brain.readerProfile.thingsIConsistentlyLove =
              replacementContent.cast<String>();
          return true;
        } else if (subsection == 'NARRATIVE_PREFERENCES' &&
            replacementContent is Map<String, dynamic>) {
          final merged = _deepMerge(
              brain.readerProfile.narrativePreferences.toJson(),
              replacementContent);
          brain.readerProfile.narrativePreferences =
              NarrativePreferences.fromJson(merged);
          return true;
        } else if (subsection == null &&
            replacementContent is String) {
          brain.readerProfile.corePhilosophy = replacementContent;
          return true;
        }
        break;

      case 'READING_MODES':
        if (replacementContent is Map<String, dynamic>) {
          final merged = _deepMerge(
              Map<String, dynamic>.from(brain.readingModes),
              replacementContent);
          brain.readingModes =
              merged.map((k, v) => MapEntry(k, v as String));
          return true;
        }
        break;

      case 'VOCABULARY':
        if (replacementContent is Map<String, dynamic>) {
          final baseVocab = brain.vocabulary
              .map((k, v) => MapEntry(k, v.toJson()));
          final merged = _deepMerge(baseVocab, replacementContent);
          brain.vocabulary = merged.map(
              (k, v) => MapEntry(
                  k,
                  v is Map<String, dynamic>
                      ? VocabularyTerm.fromJson(v)
                      : VocabularyTerm(definition: v as String)));
          return true;
        }
        break;

      case 'FAVORITE_AUTHORS':
        if (replacementContent is Map<String, dynamic>) {
          final merged = _deepMerge(
              brain.favoriteAuthors.toJson(), replacementContent);
          brain.favoriteAuthors =
              FavoriteAuthors.fromJson(merged);
          return true;
        }
        break;

      case 'FAVORITE_BOOKS':
        if (replacementContent is Map<String, dynamic>) {
          final merged = _deepMerge(
              brain.favoriteBooks.toJson(), replacementContent);
          brain.favoriteBooks =
              FavoriteBooks.fromJson(merged);
          return true;
        }
        break;

      case 'READER_BLIND_SPOTS':
        if (subsection == null &&
            replacementContent is Map<String, dynamic>) {
          final merged = _deepMerge(
              brain.readerBlindSpots.toJson(), replacementContent);
          brain.readerBlindSpots =
              ReaderBlindSpots.fromJson(merged);
          return true;
        } else if (subsection == 'UNDERVALUED' &&
            replacementContent is String) {
          brain.readerBlindSpots.undervalued = replacementContent;
          return true;
        } else if (subsection == 'OVERVALUED' &&
            replacementContent is List) {
          brain.readerBlindSpots.overvalued =
              replacementContent.cast<String>();
          return true;
        } else if (subsection == 'BOOKS_THAT_CHANGED_MY_MIND' &&
            replacementContent is List) {
          brain.readerBlindSpots.booksThatChangedMyMind =
              replacementContent.cast<String>();
          return true;
        } else if (subsection == null &&
            replacementContent is String) {
          brain.readerBlindSpots.undervalued = replacementContent;
          return true;
        }
        break;

      case 'READING_EVOLUTION':
        if (replacementContent is List) {
          brain.readingEvolution = replacementContent
              .map((e) =>
                  EvolutionEntry.fromJson(e as Map<String, dynamic>))
              .toList();
          return true;
        }
        break;

      case 'ACTIVE_QUESTIONS':
        if (replacementContent is List) {
          brain.activeQuestions = replacementContent.cast<String>();
          return true;
        }
        break;

      case 'CURRENT_READING':
        if (replacementContent == null ||
            (replacementContent is Map && replacementContent.isEmpty)) {
          brain.currentReading = null;
          return true;
        } else if (replacementContent is Map<String, dynamic>) {
          final merged = _deepMerge(
              brain.currentReading?.toJson() ?? {}, replacementContent);
          brain.currentReading =
              CurrentReading.fromJson(merged);
          return true;
        }
        break;

      case 'RECOMMENDATION_QUEUE':
        if (replacementContent is Map<String, dynamic>) {
          final merged = _deepMerge(
              brain.recommendationQueue.toJson(), replacementContent);
          brain.recommendationQueue =
              RecommendationQueue.fromJson(merged);
          return true;
        }
        break;

      case 'OBSERVATIONS':
        if (replacementContent is List) {
          brain.observations = replacementContent
              .map((e) =>
                  ObservationEntry.fromJson(e as Map<String, dynamic>))
              .toList();
          return true;
        }
        break;
    }
    return false;
  }

  static const Map<String, String> _keyAliases = {
    'Name': 'name',
    'Started Reading Seriously': 'startedReadingSeriously',
    'Primary Goal': 'primaryGoal',
    'Core Philosophy': 'corePhilosophy',
    'Things I Consistently Love': 'thingsIConsistentlyLove',
    'Narrative Preferences': 'narrativePreferences',
    'Very High': 'veryHigh',
    'High': 'high',
    'Medium': 'medium',
    'Low': 'low',
    'Definition': 'definition',
    'Examples': 'examples',
    'Tier S': 'tierS',
    'Tier A': 'tierA',
    'Ranked': 'ranked',
    'Favorite Nonfiction': 'favoriteNonfiction',
    'Favorite Short Story Collection': 'favoriteShortStoryCollection',
    'Things I Probably Overvalue': 'overvalued',
    'Things I Probably Undervalue': 'undervalued',
    'Books That Changed My Mind': 'booksThatChangedMyMind',
    'Year': 'year',
    'Insight': 'insight',
    'Book': 'book',
    'Title': 'title',
    'Status': 'status',
    'Rating': 'rating',
    'Progress': 'progress',
    'Personal Significance': 'personalSignificance',
    'Why It Matters': 'whyItMatters',
    'Current Impression': 'currentImpression',
    'Reading Strategy': 'readingStrategy',
    'Current Reading Strategy': 'readingStrategy',
    'Current Notes': 'notes',
    'Notes': 'notes',
    'Abandonment Reason': 'abandonmentReason',
    'Hardcover ID': 'hardcoverId',
    'Author': 'author',
    'Cover': 'coverUrl',
    'Cover Url': 'coverUrl',
    'Pages': 'pages',
    'Hardcover URL': 'hardcoverUrl',
    'Hardcover Url': 'hardcoverUrl',
    'Date Added': 'dateAdded',
    'Date Read': 'dateRead',
    'Hardcover Status': 'hardcoverStatus',
    'Hardcover Review': 'hardcoverReview',
    'Hardcover Spoiler': 'hardcoverSpoiler',
    'Genres': 'genres',
    'Highest Priority': 'highestPriority',
    'High Confidence': 'highConfidence',
    'Future': 'future',
    'Reason': 'reason',
    'Evidence': 'evidence',
    'Hypothesis': 'hypothesis',
    'Confidence': 'confidence',
    'Logged': 'logged',
  };

  static Map<String, dynamic> _normalizeKeys(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    for (final entry in data.entries) {
      final alias = _keyAliases[entry.key];
      final key = alias ?? entry.key;
      if (alias != null && result.containsKey(key)) continue;
      result[key] = _normalizeValue(entry.value);
    }
    return result;
  }

  static dynamic _normalizeValue(dynamic value) {
    if (value is Map<String, dynamic>) return _normalizeKeys(value);
    if (value is List) return value.map(_normalizeValue).toList();
    return value;
  }

  static const _stopWords = {
    'i', 'me', 'my', 'we', 'our', 'you', 'your', 'he', 'she', 'they', 'them',
    'it', 'its', 'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to',
    'for', 'of', 'by', 'with', 'from', 'about', 'than', 'not', 'no', 'as', 'so',
    'if', 'then', 'just', 'also', 'very', 'too', 'only', 'still', 'already',
    'always', 'never', 'often', 'usually', 'really', 'actually', 'probably',
    'is', 'are', 'was', 'were', 'be', 'been', 'being', 'have', 'has', 'had',
    'do', 'does', 'did', 'will', 'would', 'could', 'should', 'may', 'might',
    'can', 'shall', 'this', 'that', 'these', 'those',
  };

  static bool _similarHypotheses(String a, String b) {
    final normA = a.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    final normB = b.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    if (normA == normB) return true;

    final rawA = normA.split(RegExp(r'\s+')).toSet();
    final rawB = normB.split(RegExp(r'\s+')).toSet();
    final wordsA = rawA.difference(_stopWords);
    final wordsB = rawB.difference(_stopWords);
    if (wordsA.length < 3 || wordsB.length < 3) return false;
    final intersection = wordsA.intersection(wordsB).length;
    final union = wordsA.union(wordsB).length;
    return intersection / union >= 0.35;
  }

  static String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';
  }
}
