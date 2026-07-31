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

class BrainParser {
  static const _blockTypes = {
    'JSON_APPEND_BOOK': BlockType.appendBook,
    'JSON_UPDATE_BOOK': BlockType.updateBook,
    'JSON_DELETE_BOOK': BlockType.deleteBook,
    'JSON_PATCH': BlockType.patch,
    'JSON_OBSERVATION': BlockType.observation,
  };

  static final _blockRegex = RegExp(
    r'BEGIN_(JSON_APPEND_BOOK|JSON_UPDATE_BOOK|JSON_DELETE_BOOK|JSON_PATCH|JSON_OBSERVATION)\n'
    r'(.*?)'
    r'\nEND_\1',
    dotAll: true,
  );

  static ParsedResponse parse(String rawResponse) {
    final blocks = <OperationBlock>[];
    final proseParts = <String>[];
    int lastEnd = 0;

    for (final match in _blockRegex.allMatches(rawResponse)) {
      final typeStr = match.group(1)!;
      final body = match.group(2)!.trim();
      final type = _blockTypes[typeStr]!;

      Map<String, dynamic> jsonData;
      try {
        jsonData = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        jsonData = <String, dynamic>{};
      }

      blocks.add(OperationBlock(
          type: type, rawText: match.group(0)!, jsonData: jsonData));

      final before = rawResponse.substring(lastEnd, match.start);
      proseParts.add(before);
      lastEnd = match.end;
    }

    if (lastEnd < rawResponse.length) {
      proseParts.add(rawResponse.substring(lastEnd));
    }

    String prose = proseParts.join();
    prose = prose.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    prose = prose.trim();

    return ParsedResponse(prose: prose, blocks: blocks);
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
      switch (block.type) {
        case BlockType.appendBook:
          try {
            final book =
                Book.fromJson(block.jsonData);
            brain.books.add(book);
            log.add(PatchLogEntry(
                operation: 'APPEND_BOOK', target: book.title));
          } catch (_) {}
          break;

        case BlockType.updateBook:
          try {
            final targetTitle =
                block.jsonData['targetTitle'] as String? ?? '';
            final bookJson = block.jsonData['book'] as Map<String, dynamic>?;
            if (targetTitle.isEmpty || bookJson == null) break;
            final book = Book.fromJson(bookJson);
            final idx = brain.books
                .indexWhere((b) => b.title == targetTitle);
            if (idx != -1) {
              brain.books[idx] = book;
              log.add(PatchLogEntry(
                  operation: 'UPDATE_BOOK', target: targetTitle));
            }
          } catch (_) {}
          break;

        case BlockType.deleteBook:
          try {
            final targetTitle =
                block.jsonData['targetTitle'] as String? ?? '';
            if (targetTitle.isEmpty) break;
            brain.books.removeWhere((b) => b.title == targetTitle);
            log.add(PatchLogEntry(
                operation: 'DELETE_BOOK', target: targetTitle));
          } catch (_) {}
          break;

        case BlockType.patch:
          try {
            final targetSection =
                block.jsonData['targetSection'] as String? ?? '';
            final replacementContent = block.jsonData['replacementContent'];
            final reason = block.jsonData['reason'] as String?;
            final confidence =
                (block.jsonData['confidence'] as num?)?.toDouble();
            if (targetSection.isEmpty || replacementContent == null) break;

            _applyJsonPatch(brain, targetSection, replacementContent);
            log.add(PatchLogEntry(
              operation: 'PATCH',
              target: targetSection,
              reason: reason,
              confidence: confidence,
            ));
          } catch (_) {}
          break;

        case BlockType.observation:
          try {
            final evidence =
                block.jsonData['evidence'] as String? ?? '';
            final hypothesis =
                block.jsonData['hypothesis'] as String? ?? '';
            final confidence =
                (block.jsonData['confidence'] as num?)?.toDouble() ?? 0.0;
            final logged =
                block.jsonData['logged'] as String? ?? '';

            final matching = brain.observations
                .where((o) => _similarHypotheses(o.hypothesis, hypothesis))
                .toList();

            if (matching.length >= 2) {
              final evidenceDates =
                  matching.map((o) => o.logged).toList();
              brain.observations
                  .removeWhere((o) => evidenceDates.contains(o.logged));
            } else {
              brain.observations.add(ObservationEntry(
                evidence: evidence,
                hypothesis: hypothesis,
                confidence: confidence,
                logged: logged,
              ));
            }

            log.add(PatchLogEntry(
              operation: 'OBSERVATION',
              target: hypothesis,
              confidence: confidence,
            ));
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

  static void _applyJsonPatch(
      Brain brain, String targetSection, dynamic replacementContent) {
    final parts = targetSection.split('.');
    final section = parts[0];
    final subsection = parts.length > 1 ? parts.sublist(1).join('_') : null;

    switch (section) {
      case 'META':
        if (subsection == null && replacementContent is Map<String, dynamic>) {
          brain.meta = BrainMeta.fromJson(replacementContent);
        }
        break;

      case 'READER_PROFILE':
        if (subsection == null && replacementContent is Map<String, dynamic>) {
          brain.readerProfile = ReaderProfile.fromJson(replacementContent);
        } else if (subsection == 'CORE_PHILOSOPHY' &&
            replacementContent is String) {
          brain.readerProfile.corePhilosophy = replacementContent;
        } else if (subsection == 'THINGS_I_CONSISTENTLY_LOVE' &&
            replacementContent is List) {
          brain.readerProfile.thingsIConsistentlyLove =
              replacementContent.cast<String>();
        } else if (subsection == 'NARRATIVE_PREFERENCES' &&
            replacementContent is Map<String, dynamic>) {
          brain.readerProfile.narrativePreferences =
              NarrativePreferences.fromJson(replacementContent);
        }
        break;

      case 'READING_MODES':
        if (replacementContent is Map<String, dynamic>) {
          brain.readingModes =
              replacementContent.map((k, v) => MapEntry(k, v as String));
        }
        break;

      case 'VOCABULARY':
        if (replacementContent is Map<String, dynamic>) {
          brain.vocabulary = replacementContent.map(
              (k, v) => MapEntry(
                  k,
                  v is Map<String, dynamic>
                      ? VocabularyTerm.fromJson(v)
                      : VocabularyTerm(definition: v as String)));
        }
        break;

      case 'FAVORITE_AUTHORS':
        if (replacementContent is Map<String, dynamic>) {
          brain.favoriteAuthors =
              FavoriteAuthors.fromJson(replacementContent);
        }
        break;

      case 'FAVORITE_BOOKS':
        if (replacementContent is Map<String, dynamic>) {
          brain.favoriteBooks =
              FavoriteBooks.fromJson(replacementContent);
        }
        break;

      case 'READER_BLIND_SPOTS':
        if (replacementContent is Map<String, dynamic>) {
          brain.readerBlindSpots =
              ReaderBlindSpots.fromJson(replacementContent);
        }
        break;

      case 'READING_EVOLUTION':
        if (replacementContent is List) {
          brain.readingEvolution = replacementContent
              .map((e) =>
                  EvolutionEntry.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        break;

      case 'ACTIVE_QUESTIONS':
        if (replacementContent is List) {
          brain.activeQuestions = replacementContent.cast<String>();
        }
        break;

      case 'CURRENT_READING':
        if (replacementContent == null ||
            (replacementContent is Map && replacementContent.isEmpty)) {
          brain.currentReading = null;
        } else if (replacementContent is Map<String, dynamic>) {
          brain.currentReading =
              CurrentReading.fromJson(replacementContent);
        }
        break;

      case 'RECOMMENDATION_QUEUE':
        if (replacementContent is Map<String, dynamic>) {
          brain.recommendationQueue =
              RecommendationQueue.fromJson(replacementContent);
        }
        break;

      case 'OBSERVATIONS':
        if (replacementContent is List) {
          brain.observations = replacementContent
              .map((e) =>
                  ObservationEntry.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        break;
    }
  }

  static bool _similarHypotheses(String a, String b) {
    final normA = a.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    final normB = b.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    if (normA == normB) return true;

    final wordsA = normA.split(RegExp(r'\s+')).toSet();
    final wordsB = normB.split(RegExp(r'\s+')).toSet();
    if (wordsA.length < 3 || wordsB.length < 3) return false;
    final intersection = wordsA.intersection(wordsB).length;
    final union = wordsA.union(wordsB).length;
    return intersection / union >= 0.7;
  }

  static String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';
  }
}

class ParsedResponse {
  final String prose;
  final List<OperationBlock> blocks;

  const ParsedResponse({required this.prose, required this.blocks});
}

class BrainUpdate {
  final String brain;
  final List<PatchLogEntry> log;

  const BrainUpdate({required this.brain, required this.log});
}
