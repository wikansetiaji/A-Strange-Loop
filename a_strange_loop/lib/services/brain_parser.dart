enum BlockType { appendBook, updateBook, deleteBook, patch, observation }

class OperationBlock {
  final BlockType type;
  final String rawText;
  final Map<String, String> fields;

  const OperationBlock({
    required this.type,
    required this.rawText,
    required this.fields,
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

  static final _blockRegex = RegExp(
    r'BEGIN_(APPEND_BOOK|UPDATE_BOOK|DELETE_BOOK|PATCH|OBSERVATION)\n'
    r'(.*?)'
    r'\nEND_\1',
    dotAll: true,
  );

  // ── Parse ────────────────────────────────────────────────────

  static ParsedResponse parse(String rawResponse) {
    final blocks = <OperationBlock>[];
    final proseParts = <String>[];
    int lastEnd = 0;

    for (final match in _blockRegex.allMatches(rawResponse)) {
      final typeStr = match.group(1)!;
      final body = match.group(2)!;
      final type = _blockTypes[typeStr]!;
      final fields = _parseBlockFields(type, body);
      blocks.add(OperationBlock(
          type: type, rawText: match.group(0)!, fields: fields));

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

  static Map<String, String> _parseBlockFields(BlockType type, String body) {
    switch (type) {
      case BlockType.appendBook:
        return _parseFields(body.replaceFirst('# BOOK', ''));

      case BlockType.updateBook:
        return _parseFields(body.replaceFirst('# BOOK', ''));

      case BlockType.deleteBook:
        return _parseFields(body);

      case BlockType.patch:
        return _parseFields(body, multiLineField: 'Replacement Content');

      case BlockType.observation:
        return _parseFields(body);
    }
  }

  static Map<String, String> _parseFields(String body,
      {String? multiLineField}) {
    final fields = <String, String>{};
    final lines = body.split('\n');

    String? currentKey;
    final currentValue = <String>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final inlineMatch =
          RegExp(r"^([A-Z][\w\s]+):\s+(.+)$").firstMatch(trimmed);
      if (inlineMatch != null) {
        if (currentKey != null && currentValue.isNotEmpty) {
          fields[currentKey] = currentValue.join('\n').trim();
          currentValue.clear();
        }
        final key = inlineMatch.group(1)!.trim();
        final value = inlineMatch.group(2)!.trim();

        if (key == multiLineField) {
          final remaining = <String>[];
          for (int j = i + 1; j < lines.length; j++) {
            remaining.add(lines[j]);
          }
          fields[key] = remaining.join('\n').trim();
          return fields;
        }

        fields[key] = value;
        currentKey = null;
        continue;
      }

      final keyOnlyMatch =
          RegExp(r"^([A-Z][\w\s]+):\s*$").firstMatch(trimmed);
      if (keyOnlyMatch != null) {
        if (currentKey != null && currentValue.isNotEmpty) {
          fields[currentKey] = currentValue.join('\n').trim();
          currentValue.clear();
        }
        currentKey = keyOnlyMatch.group(1)!.trim();

        if (currentKey == multiLineField) {
          final remaining = <String>[];
          for (int j = i + 1; j < lines.length; j++) {
            remaining.add(lines[j]);
          }
          fields[currentKey] = remaining.join('\n').trim();
          return fields;
        }
        continue;
      }

      if (currentKey != null) {
        currentValue.add(line);
      }
    }

    if (currentKey != null && currentValue.isNotEmpty) {
      fields[currentKey] = currentValue.join('\n').trim();
    }

    return fields;
  }

  // ── Apply ────────────────────────────────────────────────────

  static BrainUpdate applyBlocks(String brain, List<OperationBlock> blocks) {
    final log = <PatchLogEntry>[];
    String result = brain;
    final evidenceDates = <String>[];

    for (final block in blocks) {
      switch (block.type) {
        case BlockType.appendBook:
          result = _appendBook(result, block.fields);
          final title = block.fields['Title'] ?? 'Unknown';
          log.add(PatchLogEntry(operation: 'APPEND_BOOK', target: title));
          break;

        case BlockType.updateBook:
          final target = block.fields['Target Title'] ?? '';
          if (target.isEmpty) break;
          result = _updateBook(result, target, block.fields);
          log.add(PatchLogEntry(operation: 'UPDATE_BOOK', target: target));
          break;

        case BlockType.deleteBook:
          final target = block.fields['Target Title'] ?? '';
          if (target.isEmpty) break;
          result = _deleteBook(result, target);
          log.add(PatchLogEntry(operation: 'DELETE_BOOK', target: target));
          break;

        case BlockType.patch:
          final section = block.fields['Target Section'] ?? '';
          final content = block.fields['Replacement Content'] ?? '';
          final reason = block.fields['Reason'];
          final conf =
              double.tryParse(block.fields['Confidence'] ?? '');
          if (section.isEmpty || content.isEmpty) break;
          result = _applyPatch(result, section, content);
          final targetLabel = section.contains('.')
              ? section
              : _pascalToTitle(section);
          log.add(PatchLogEntry(
            operation: 'PATCH',
            target: targetLabel,
            reason: reason,
            confidence: conf,
          ));
          final evidence = block.fields['Evidence'] ?? '';
          _collectDates(evidence, evidenceDates);
          break;

        case BlockType.observation:
          result = _appendObservation(result, block.fields);
          final hypothesis = block.fields['Hypothesis'] ?? 'Unknown';
          final conf =
              double.tryParse(block.fields['Confidence'] ?? '');
          log.add(PatchLogEntry(
            operation: 'OBSERVATION',
            target: hypothesis,
            confidence: conf,
          ));
          break;
      }
    }

    if (evidenceDates.isNotEmpty) {
      result = _removeObservationsByDate(result, evidenceDates);
    }

    return BrainUpdate(brain: result, log: log);
  }

  // ── BOOK Operations ──────────────────────────────────────────

  static String _appendBook(String brain, Map<String, String> fields) {
    final booksIdx = brain.indexOf('## BOOKS\n');
    if (booksIdx == -1) return brain;

    final booksContent = brain.substring(booksIdx + '## BOOKS\n'.length);

    final entryRegex = RegExp(
      r'\n---\n# BOOK\n.*?(?=\n---\n# BOOK\n|$)',
      dotAll: true,
    );
    final matches = entryRegex.allMatches(booksContent).toList();
    final insertIdx = matches.isNotEmpty
        ? booksIdx + '## BOOKS\n'.length + matches.last.end
        : booksIdx + '## BOOKS\n'.length;

    final entry = _buildBookEntry(fields);
    return '${brain.substring(0, insertIdx)}'
        '\n---\n$entry\n'
        '${brain.substring(insertIdx)}';
  }

  static String _updateBook(
      String brain, String targetTitle, Map<String, String> fields) {
    final entry = _findBookEntry(brain, targetTitle);
    if (entry == null) return brain;

    final (start, end) = entry;
    final newEntry = _buildBookEntry(fields);
    return '${brain.substring(0, start)}\n---\n$newEntry${brain.substring(end)}';
  }

  static String _deleteBook(String brain, String targetTitle) {
    final entry = _findBookEntry(brain, targetTitle);
    if (entry == null) return brain;

    final (start, end) = entry;
    return '${brain.substring(0, start)}${brain.substring(end)}';
  }

  static (int, int)? _findBookEntry(String brain, String targetTitle) {
    final booksIdx = brain.indexOf('## BOOKS\n');
    if (booksIdx == -1) return null;

    final booksContent = brain.substring(booksIdx + '## BOOKS\n'.length);
    final entryRegex = RegExp(
      r'(\n---\n# BOOK\n)(.*?)(?=\n---\n# BOOK\n|$)',
      dotAll: true,
    );

    for (final match in entryRegex.allMatches(booksContent)) {
      final content = match.group(2) ?? '';
      final titleRegex = RegExp(r'Title:\s*\n+\s*(.+)');
      final titleMatch = titleRegex.firstMatch(content);
      if (titleMatch != null &&
          titleMatch.group(1)!.trim() == targetTitle) {
        final start = booksIdx + '## BOOKS\n'.length + match.start;
        final end = booksIdx + '## BOOKS\n'.length + match.end;
        return (start, end);
      }
    }

    return null;
  }

  static String _buildBookEntry(Map<String, String> fields) {
    final buf = StringBuffer();
    buf.writeln('# BOOK');
    buf.writeln();

    for (final entry in fields.entries) {
      if (entry.key == 'Target Title') continue;
      buf.writeln('${entry.key}:');
      buf.writeln();
      buf.writeln(entry.value);
      buf.writeln();
    }

    return buf.toString();
  }

  // ── PATCH Operation ──────────────────────────────────────────

  static String _applyPatch(
      String brain, String targetSection, String replacementContent) {
    if (targetSection.contains('.')) {
      final parts = targetSection.split('.');
      final sectionName = parts[0];
      final subsectionName = parts.sublist(1).join(' ');
      final subsectionSpaces =
          subsectionName.replaceAll('_', ' ');
      return _applySubsectionPatch(
          brain, sectionName, subsectionSpaces, replacementContent);
    }

    return _applySectionPatch(brain, targetSection, replacementContent);
  }

  static String _applySectionPatch(
      String brain, String sectionName, String content) {
    final header = '## $sectionName\n';
    final headerIdx = brain.indexOf(header);
    if (headerIdx == -1) return brain;

    final afterHeader = headerIdx + header.length;
    final rest = brain.substring(afterHeader);

    final nextHeaderRegex = RegExp(r'\n## |\n(?=---\n# BOOK)');
    final nextHeaderMatch = nextHeaderRegex.firstMatch(rest);
    final sectionEnd = nextHeaderMatch != null
        ? afterHeader + nextHeaderMatch.start
        : brain.length;

    return '${brain.substring(0, afterHeader)}\n'
        '${content.trim()}\n'
        '${brain.substring(sectionEnd)}';
  }

  static String _applySubsectionPatch(String brain, String sectionName,
      String subsectionName, String content) {
    final sectionHeader = '## $sectionName\n';
    final sectionIdx = brain.indexOf(sectionHeader);
    if (sectionIdx == -1) return brain;

    final afterSection = sectionIdx + sectionHeader.length;
    final rest = brain.substring(afterSection);

    final nextMajorHeader = RegExp(r'\n## |\n(?=---\n# BOOK)');
    final nextHeaderMatch = nextMajorHeader.firstMatch(rest);
    final sectionEnd = nextHeaderMatch != null
        ? afterSection + nextHeaderMatch.start
        : brain.length;

    final sectionBody = brain.substring(afterSection, sectionEnd);

    final subPattern =
        RegExp(r'###\s+' + RegExp.escape(subsectionName) + r'\b',
            caseSensitive: false);
    final subMatch = subPattern.firstMatch(sectionBody);
    if (subMatch == null) return brain;

    final subStart = afterSection + subMatch.end;

    final nextSubRegex = RegExp(r'\n### ');
    final nextSubMatch = nextSubRegex.firstMatch(
      sectionBody.substring(subMatch.end),
    );
    final subEnd = nextSubMatch != null
        ? afterSection + subMatch.end + nextSubMatch.start
        : sectionEnd;

    return '${brain.substring(0, subStart)}\n\n'
        '${content.trim()}\n'
        '${brain.substring(subEnd)}';
  }

  // ── OBSERVATION Operations ───────────────────────────────────

  static String _cleanSectionBody(String body) {
    body = body.replaceAll('(empty)', '');
    body = body.trimRight();
    if (body.endsWith('---')) {
      body = body.substring(0, body.lastIndexOf('---')).trimRight();
    }
    return body.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  static String _appendObservation(
      String brain, Map<String, String> fields) {
    final header = '## OBSERVATIONS\n';
    final headerIdx = brain.indexOf(header);
    if (headerIdx == -1) return brain;

    final afterHeader = headerIdx + header.length;
    final rest = brain.substring(afterHeader);

    final nextSection = RegExp(r'\n## |\n(?=---\n# BOOK)');
    final nextMatch = nextSection.firstMatch(rest);
    final sectionEnd =
        nextMatch != null ? afterHeader + nextMatch.start : brain.length;

    var sectionBody = brain.substring(afterHeader, sectionEnd);

    if (sectionBody.contains('(No observations logged yet')) {
      sectionBody = sectionBody
          .split('\n')
          .where((l) => !l.contains('(No observations logged yet'))
          .join('\n');
    }

    sectionBody = _cleanSectionBody(sectionBody);

    final entry = _buildObservationEntry(fields);
    if (sectionBody.isNotEmpty) {
      sectionBody = '$sectionBody\n\n---\n$entry\n\n(empty)';
    } else {
      sectionBody = '---\n$entry\n\n(empty)';
    }

    return '${brain.substring(0, afterHeader)}\n'
        '$sectionBody\n'
        '${brain.substring(sectionEnd)}';
  }

  static String _buildObservationEntry(Map<String, String> fields) {
    final buf = StringBuffer();
    for (final key in ['Evidence', 'Hypothesis', 'Confidence', 'Logged']) {
      final value = fields[key];
      if (value != null) {
        buf.writeln('$key:');
        buf.writeln();
        buf.writeln(value);
        buf.writeln();
      }
    }
    return buf.toString();
  }

  static void _collectDates(String evidence, List<String> dates) {
    final dateRegex = RegExp(r'\d{4}-\d{2}-\d{2}');
    for (final match in dateRegex.allMatches(evidence)) {
      final date = match.group(0)!;
      if (!dates.contains(date)) dates.add(date);
    }
  }

  static String _removeObservationsByDate(
      String brain, List<String> dates) {
    if (dates.isEmpty) return brain;

    final header = '## OBSERVATIONS\n';
    final headerIdx = brain.indexOf(header);
    if (headerIdx == -1) return brain;

    final afterHeader = headerIdx + header.length;
    final rest = brain.substring(afterHeader);

    final nextSection = RegExp(r'\n## |\n(?=---\n# BOOK)');
    final nextMatch = nextSection.firstMatch(rest);
    final sectionEnd =
        nextMatch != null ? afterHeader + nextMatch.start : brain.length;

    final sectionBody = brain.substring(afterHeader, sectionEnd);

    final entryRegex = RegExp(
      r'(\n---\n)(.*?)(?=\n---\n|\n\(empty\)|$)',
      dotAll: true,
    );

    String cleaned = sectionBody;
    for (final match
        in entryRegex.allMatches(sectionBody).toList().reversed) {
      final content = match.group(2) ?? '';
      final loggedRegex = RegExp(r'Logged:\s*\n+\s*(\d{4}-\d{2}-\d{2})');
      final loggedMatch = loggedRegex.firstMatch(content);
      if (loggedMatch != null &&
          dates.contains(loggedMatch.group(1)!.trim())) {
        cleaned = cleaned.replaceFirst(match.group(0)!, '');
      }
    }

    cleaned = _cleanSectionBody(cleaned);

    if (!cleaned.contains('---')) {
      cleaned = '(empty)';
    } else {
      cleaned = '$cleaned\n\n(empty)';
    }

    return '${brain.substring(0, afterHeader)}\n'
        '$cleaned\n'
        '${brain.substring(sectionEnd)}';
  }

  // ── Helpers ──────────────────────────────────────────────────

  static String _pascalToTitle(String pascal) {
    final words = pascal.split('_').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
    return words;
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
