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
    'APPEND_BOOK': BlockType.appendBook,
    'UPDATE_BOOK': BlockType.updateBook,
    'DELETE_BOOK': BlockType.deleteBook,
    'PATCH': BlockType.patch,
    'OBSERVATION': BlockType.observation,
  };

  static final _beginMarker = RegExp(
    r'(?:BEGIN_(?:JSON_)?)?(APPEND_BOOK|UPDATE_BOOK|DELETE_BOOK|PATCH|OBSERVATION)(?:\s+\w+)?',
  );

  static ParsedResponse parse(String rawResponse) {
    final blocks = <OperationBlock>[];
    final proseParts = <String>[];
    int lastEnd = 0;

    final lines = rawResponse.split('\n');
    var i = 0;
    while (i < lines.length) {
      final beginMatch = _beginMarker.firstMatch(lines[i]);
      if (beginMatch == null) {
        i++;
        continue;
      }

      final blockTypeStr = beginMatch.group(1)!;
      final blockType = _blockTypes[blockTypeStr];
      if (blockType == null) {
        i++;
        continue;
      }

      final endMarker = RegExp(
        r'END_(?:JSON_)?' + RegExp.escape(blockTypeStr) + r'\s*$',
      );

      final jsonLines = <String>[];
      var j = i + 1;
      var endFound = false;
      while (j < lines.length) {
        if (endMarker.hasMatch(lines[j])) {
          endFound = true;
          break;
        }
        jsonLines.add(lines[j]);
        j++;
      }

      if (!endFound) {
        i++;
        continue;
      }

      final body = jsonLines.join('\n').trim();
      Map<String, dynamic> jsonData;
      try {
        jsonData = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        i = j + 1;
        continue;
      }

      final blockStartLine = i;
      final blockEndLine = j;
      final rawText = lines.sublist(blockStartLine, blockEndLine + 1).join('\n');

      blocks.add(OperationBlock(
          type: blockType, rawText: rawText, jsonData: jsonData));

      final beforeLines = lastEnd < blockStartLine
          ? lines.sublist(lastEnd, blockStartLine).join('\n')
          : '';
      if (beforeLines.isNotEmpty) proseParts.add(beforeLines);
      lastEnd = blockEndLine + 1;
      i = j + 1;
    }

    if (lastEnd < lines.length) {
      proseParts.add(lines.sublist(lastEnd).join('\n'));
    }

    String prose = proseParts.join('\n');
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
                (block.jsonData['targetSection'] ??
                        block.jsonData['target']) as String? ??
                    '';
            final replacementContent = block.jsonData['replacementContent'] ??
                block.jsonData['replace'];
            final reason = block.jsonData['reason'] as String?;
            final confidence =
                (block.jsonData['confidence'] as num?)?.toDouble();
            if (targetSection.isEmpty) break;
            if (replacementContent == null &&
                targetSection != 'CURRENT_READING') {
              break;
            }

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
          final merged = _deepMerge(
              brain.readerProfile.toJson(), replacementContent);
          brain.readerProfile = ReaderProfile.fromJson(merged);
        } else if (subsection == 'CORE_PHILOSOPHY' &&
            replacementContent is String) {
          brain.readerProfile.corePhilosophy = replacementContent;
        } else if (subsection == 'THINGS_I_CONSISTENTLY_LOVE' &&
            replacementContent is List) {
          brain.readerProfile.thingsIConsistentlyLove =
              replacementContent.cast<String>();
        } else if (subsection == 'NARRATIVE_PREFERENCES' &&
            replacementContent is Map<String, dynamic>) {
          final merged = _deepMerge(
              brain.readerProfile.narrativePreferences.toJson(),
              replacementContent);
          brain.readerProfile.narrativePreferences =
              NarrativePreferences.fromJson(merged);
        }
        break;

      case 'READING_MODES':
        if (replacementContent is Map<String, dynamic>) {
          final merged = _deepMerge(
              Map<String, dynamic>.from(brain.readingModes),
              replacementContent);
          brain.readingModes =
              merged.map((k, v) => MapEntry(k, v as String));
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
        }
        break;

      case 'FAVORITE_AUTHORS':
        if (replacementContent is Map<String, dynamic>) {
          final merged = _deepMerge(
              brain.favoriteAuthors.toJson(), replacementContent);
          brain.favoriteAuthors =
              FavoriteAuthors.fromJson(merged);
        }
        break;

      case 'FAVORITE_BOOKS':
        if (replacementContent is Map<String, dynamic>) {
          final merged = _deepMerge(
              brain.favoriteBooks.toJson(), replacementContent);
          brain.favoriteBooks =
              FavoriteBooks.fromJson(merged);
        }
        break;

      case 'READER_BLIND_SPOTS':
        if (replacementContent is Map<String, dynamic>) {
          final merged = _deepMerge(
              brain.readerBlindSpots.toJson(), replacementContent);
          brain.readerBlindSpots =
              ReaderBlindSpots.fromJson(merged);
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
          final merged = _deepMerge(
              brain.currentReading?.toJson() ?? {}, replacementContent);
          brain.currentReading =
              CurrentReading.fromJson(merged);
        }
        break;

      case 'RECOMMENDATION_QUEUE':
        if (replacementContent is Map<String, dynamic>) {
          final merged = _deepMerge(
              brain.recommendationQueue.toJson(), replacementContent);
          brain.recommendationQueue =
              RecommendationQueue.fromJson(merged);
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
