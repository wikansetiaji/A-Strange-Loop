import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:a_strange_loop/models/message.dart';
import 'package:a_strange_loop/models/session.dart';
import 'package:a_strange_loop/services/firestore_service.dart';
import 'package:a_strange_loop/services/ai_service.dart';
import 'package:a_strange_loop/services/brain_parser.dart';
import 'package:a_strange_loop/constants/system_prompt.dart';
import 'package:a_strange_loop/constants/api_config.dart';

class ChatState extends ChangeNotifier {
  final FirestoreService _firestore = FirestoreService();
  final AIService _ai = AIService();

  String? currentSessionId;
  List<Session> sessions = [];

  List<Message> messages = [];
  String? streamingContent;
  bool isLoading = false;
  String? error;

  int sessionPromptTokens = 0;
  int sessionCompletionTokens = 0;

  String? _conversationSummary;
  int _lastSummarizedIndex = 0;
  bool isCompressing = false;

  bool get isSummaryActive => _conversationSummary != null;

  String? currentBookTitle;
  String? currentBookProgress;

  String? _brainCache;
  DateTime? _brainFetchedAt;
  DateTime _lastNotify = DateTime.now();

  String? get brainContent => _brainCache;

  Future<String> loadBrain() async => _getBrain();

  Timer? _searchDebounce;
  bool isSearching = false;

  Future<void> seedBrainIfNeeded() async {
    try {
      await _firestore.getBrain();
    } catch (_) {
      final brain = await rootBundle.loadString('assets/reading_brain.md');
      await _firestore.uploadBrain(brain);
    }
  }

  // ── Session lifecycle ─────────────────────────────────────────

  Future<void> initializeSessions() async {
    final loaded = await _firestore.loadSessions();
    sessions = loaded;
    if (sessions.isNotEmpty) {
      await switchSession(sessions.first.id);
    } else {
      _createNewSessionId();
      sessions = [_currentSessionMeta()];
      notifyListeners();
    }
  }

  Future<void> fallbackToEmptySession() async {
    _createNewSessionId();
    messages = [];
    sessions = [_currentSessionMeta()];
    notifyListeners();
  }

  Future<void> createNewSession() async {
    if (currentSessionId != null &&
        _currentSessionMeta().messageCount == 0) {
      sessions.removeWhere((s) => s.id == currentSessionId);
    }

    _saveCurrentSessionState();
    _resetSessionState();
    _createNewSessionId();
    sessions.insert(0, _currentSessionMeta());
    notifyListeners();
  }

  Future<void> switchSession(String sessionId) async {
    if (sessionId == currentSessionId) return;

    _saveCurrentSessionState();

    final messagesDocs = await _firestore.loadMessages(sessionId);
    final target = sessions.firstWhere((s) => s.id == sessionId);

    currentSessionId = sessionId;
    messages = messagesDocs;
    sessionPromptTokens = target.promptTokens;
    sessionCompletionTokens = target.completionTokens;
    _conversationSummary = target.conversationSummary;
    _lastSummarizedIndex = target.lastSummarizedIndex;
    streamingContent = null;
    error = null;
    notifyListeners();
  }

  Future<void> deleteSession(String sessionId) async {
    await _firestore.deleteSession(sessionId);
    sessions.removeWhere((s) => s.id == sessionId);

    if (currentSessionId == sessionId) {
      if (sessions.isNotEmpty) {
        await switchSession(sessions.first.id);
      } else {
        _resetSessionState();
        _createNewSessionId();
        sessions.add(_currentSessionMeta());
        notifyListeners();
      }
    } else {
      notifyListeners();
    }
  }

  Future<void> pinSession(String sessionId) async {
    final idx = sessions.indexWhere((s) => s.id == sessionId);
    if (idx == -1) return;

    final session = sessions[idx];
    final newPinned = !session.pinned;
    await _firestore.pinSession(sessionId, newPinned);

    sessions[idx] = session.copyWith(pinned: newPinned);
    _sortSessions();
    notifyListeners();
  }

  // ── Search ────────────────────────────────────────────────────

  void searchSessions(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (query.isEmpty) {
        sessions = await _firestore.loadSessions();
      } else {
        final results = await _firestore.searchSessionsByTitle(query);
        sessions = results;
      }
      isSearching = query.isNotEmpty;
      notifyListeners();
    });
  }

  void clearSearch() {
    _searchDebounce?.cancel();
    isSearching = false;
    loadSessions();
  }

  Future<void> loadSessions() async {
    sessions = await _firestore.loadSessions();
    notifyListeners();
  }

  // ── Messaging ─────────────────────────────────────────────────

  Future<void> sendMessage(String text) async {
    assert(currentSessionId != null, 'No active session');
    if (isLoading) return;

    final userMsg = Message(
      role: 'user',
      content: text,
      order: messages.length,
    );
    messages.add(userMsg);
    streamingContent = '';
    error = null;
    isLoading = true;
    notifyListeners();

    try {
      await _firestore.saveMessage(currentSessionId!, userMsg);
      await _generateResponse();
    } catch (e) {
      streamingContent = null;
      isLoading = false;
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> editMessage(int index, String newContent) async {
    assert(currentSessionId != null, 'No active session');
    if (isLoading) return;
    if (index < 0 || index >= messages.length) return;
    if (messages[index].role != 'user') return;

    final oldOrder = messages[index].order;
    final oldTimestamp = messages[index].timestamp;
    final firestoreId = messages[index].firestoreId;

    messages = messages.sublist(0, index + 1);
    messages[index] = Message(
      role: 'user',
      content: newContent,
      order: oldOrder,
      firestoreId: firestoreId,
      timestamp: oldTimestamp,
    );

    if (_lastSummarizedIndex > messages.length) {
      _lastSummarizedIndex = 0;
      _conversationSummary = null;
    }

    streamingContent = '';
    error = null;
    isLoading = true;
    notifyListeners();

    try {
      if (firestoreId != null) {
        await _firestore.updateMessageContent(
            currentSessionId!, firestoreId, newContent);
      }
      await _firestore.deleteMessagesAfterOrder(
          currentSessionId!, oldOrder);
      await _generateResponse();
    } catch (e) {
      streamingContent = null;
      isLoading = false;
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> resetToMessage(int index) async {
    assert(currentSessionId != null, 'No active session');
    if (isLoading) return;
    if (index < 0 || index >= messages.length) return;

    final cutoffOrder = messages[index].order;

    messages = messages.sublist(0, index + 1);

    if (_lastSummarizedIndex > messages.length) {
      _lastSummarizedIndex = 0;
      _conversationSummary = null;
    }

    await _firestore.deleteMessagesAfterOrder(
        currentSessionId!, cutoffOrder);

    final meta = _currentSessionMeta();
    await _firestore.updateSessionMeta(currentSessionId!, meta.toMap());

    final idx = sessions.indexWhere((s) => s.id == currentSessionId);
    if (idx != -1) {
      sessions[idx] = meta;
    }
    _sortSessions();

    final lastMsg = messages.last;
    if (lastMsg.role == 'user') {
      streamingContent = '';
      error = null;
      isLoading = true;
      notifyListeners();

      try {
        await _generateResponse();
      } catch (e) {
        streamingContent = null;
        isLoading = false;
        error = e.toString();
        notifyListeners();
      }
    } else {
      notifyListeners();
    }
  }

  Future<void> _generateResponse() async {
    final brain = await _getBrain();

    final compressed = await _maybeCompress(brain);
    final prompt = _buildPrompt(brain, compressed);

    final buffer = StringBuffer();
    bool blocksDetected = false;
    final blockBuffer = StringBuffer();
    String visibleBuffer = '';

    await for (final chunk in _ai.sendMessageStream(prompt)) {
      if (chunk.startsWith('[USAGE:')) {
        final parts = chunk
            .substring(7, chunk.length - 1)
            .split(':');
        sessionPromptTokens += int.parse(parts[0]);
        sessionCompletionTokens += int.parse(parts[1]);
      } else {
        buffer.write(chunk);

        if (blocksDetected) {
          blockBuffer.write(chunk);
          continue;
        }

        final combined = visibleBuffer + chunk;
        final markerIdx = _findBlockMarker(combined);
        if (markerIdx != -1) {
          visibleBuffer = combined.substring(0, markerIdx);
          final remaining = combined.substring(markerIdx);
          blockBuffer.write(remaining);
          blocksDetected = true;
        } else {
          visibleBuffer = combined;
        }

        streamingContent = visibleBuffer;
        _throttledNotify();
      }
    }

    final fullContent = buffer.toString();
    final isBlockResponse =
        blocksDetected && _containsBlockMarker(fullContent);
    final parsed =
        isBlockResponse ? BrainParser.parse(fullContent) : null;
    final prose = parsed?.prose ?? fullContent;

    final assistantMsg = Message(
      role: 'assistant',
      content: prose,
      order: messages.length,
    );
    messages.add(assistantMsg);
    streamingContent = null;
    isLoading = false;

    await _firestore.saveMessage(currentSessionId!, assistantMsg);

    final meta = _currentSessionMeta();
    await _firestore.updateSessionMeta(currentSessionId!, meta.toMap());

    final idx = sessions.indexWhere((s) => s.id == currentSessionId);
    if (idx != -1) {
      sessions[idx] = meta;
    } else {
      sessions.insert(0, meta);
    }
    _sortSessions();

    final wasFirstExchange = messages.length == 2 && meta.title == null;
    if (wasFirstExchange) {
      _generateTitle(messages[0].content, messages[1].content);
    }

    if (parsed != null && parsed.blocks.isNotEmpty) {
      try {
        final freshBrain = await _firestore.getBrain();
        final update =
            BrainParser.applyBlocks(freshBrain, parsed.blocks);
        await _firestore.updateBrain(update.brain, update.log);
        _brainCache = update.brain;
        _brainFetchedAt = DateTime.now();
        _parseCurrentReading(update.brain);
      } catch (e) {
        debugPrint('BrainParser error: $e');
      }
    }

    notifyListeners();
  }

  static int _findBlockMarker(String text) {
    const markers = [
      'BEGIN_APPEND_BOOK',
      'BEGIN_UPDATE_BOOK',
      'BEGIN_DELETE_BOOK',
      'BEGIN_PATCH',
      'BEGIN_OBSERVATION',
    ];
    for (final marker in markers) {
      final idx = text.length >= marker.length
          ? text.indexOf(marker)
          : -1;
      if (idx >= 0) return idx;
    }
    return -1;
  }

  static bool _containsBlockMarker(String text) =>
      _findBlockMarker(text) != -1;

  void _throttledNotify() {
    final now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds >= 50) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  Future<void> _generateTitle(
      String firstUserMsg, String firstAssistantMsg) async {
    final title = await _ai.generateTitle(firstUserMsg, firstAssistantMsg);
    if (title == null) return;

    final sid = currentSessionId!;
    await _firestore.updateSessionMeta(sid, {'title': title});

    final idx = sessions.indexWhere((s) => s.id == sid);
    if (idx != -1) {
      sessions[idx] = sessions[idx].copyWith(title: title);
    } else {
      sessions.insert(0, _currentSessionMeta());
    }
    _sortSessions();
    notifyListeners();
  }

  // ── Compression ───────────────────────────────────────────────

  Future<List<Message>> _maybeCompress(String brain) async {
    final fullPrompt = _buildPrompt(brain, messages);
    final totalTokens = fullPrompt.length ~/ 4;

    if (totalTokens <= maxInputTokens) {
      return messages;
    }

    final cutOff = (messages.length - keepRecentMessages)
        .clamp(0, messages.length);

    if (_lastSummarizedIndex >= cutOff && _conversationSummary != null) {
      return [
        Message(role: 'system', content: _conversationSummary!),
        ...messages.sublist(cutOff),
      ];
    }

    isCompressing = true;
    notifyListeners();

    try {
      final newMessages = messages.sublist(_lastSummarizedIndex, cutOff);
      final newText = newMessages
          .map((m) =>
              '${m.role == 'user' ? 'User' : 'Assistant'}: ${m.content}')
          .join('\n\n');

      final textToSummarize = _conversationSummary != null
          ? 'Existing summary:\n$_conversationSummary\n\n'
              'New messages to add:\n$newText'
          : newText;

      _conversationSummary = await _ai.summarize(textToSummarize);
      _lastSummarizedIndex = cutOff;
    } catch (_) {
      _conversationSummary = null;
      _lastSummarizedIndex = cutOff;
    } finally {
      isCompressing = false;
    }

    return [
      if (_conversationSummary != null)
        Message(role: 'system', content: _conversationSummary!),
      ...messages.sublist(cutOff),
    ];
  }

  // ── Brain ─────────────────────────────────────────────────────

  Future<String> _getBrain() async {
    if (_brainCache != null && _brainFetchedAt != null) {
      return _brainCache!;
    }
    final brain = await _firestore.getBrain();
    _brainCache = brain;
    _brainFetchedAt = DateTime.now();
    _parseCurrentReading(brain);
    return brain;
  }

  void _parseCurrentReading(String brain) {
    final section = RegExp(
      r'## CURRENT_READING\n((?:.|\n)*?)(?=\n## |\Z)',
    ).firstMatch(brain)?.group(1);
    if (section == null) {
      currentBookTitle = null;
      currentBookProgress = null;
      return;
    }

    final titleMatch =
        RegExp(r'^Book:\s*\n\s*(.+)$', multiLine: true).firstMatch(section);
    currentBookTitle = titleMatch?.group(1)?.trim();

    final progressMatch =
        RegExp(r'^Progress:\s*\n\s*(.+)$', multiLine: true)
            .firstMatch(section);
    currentBookProgress = progressMatch?.group(1)?.trim();
  }

  String _buildPrompt(String brain, List<Message> msgs) {
    final historyParts = <String>[];

    for (final m in msgs) {
      if (m.role == 'system') {
        historyParts.add('## Conversation Summary\n\n${m.content}');
      } else {
        historyParts.add(
            '${m.role == 'user' ? 'User' : 'Assistant'}: ${m.content}');
      }
    }

    final history = historyParts.join('\n\n');

    return '$companionSystemPrompt\n\n---\n\n$brain\n\n---\n\n'
        '## Chat History\n\n$history';
  }

  // ── Helpers ───────────────────────────────────────────────────

  String get formattedSessionTokens {
    final total = sessionPromptTokens + sessionCompletionTokens;
    if (total >= 1000) {
      return '${(total / 1000).toStringAsFixed(1)}K tokens this session';
    }
    return '$total tokens this session';
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  void _createNewSessionId() {
    currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
  }

  Session _currentSessionMeta() {
    final lastMsg = messages.isNotEmpty ? messages.last : null;
    return Session(
      id: currentSessionId!,
      title: sessions
          .where((s) => s.id == currentSessionId)
          .map((s) => s.title)
          .firstOrNull,
      pinned: sessions
          .where((s) => s.id == currentSessionId)
          .map((s) => s.pinned)
          .firstOrNull ??
          false,
      lastMessage: lastMsg != null
          ? (lastMsg.content.length > 100
              ? '${lastMsg.content.substring(0, 100)}...'
              : lastMsg.content)
          : '',
      createdAt: sessions
              .where((s) => s.id == currentSessionId)
              .map((s) => s.createdAt)
              .firstOrNull ??
          DateTime.now(),
      updatedAt: DateTime.now(),
      promptTokens: sessionPromptTokens,
      completionTokens: sessionCompletionTokens,
      messageCount: messages.length,
      conversationSummary: _conversationSummary,
      lastSummarizedIndex: _lastSummarizedIndex,
    );
  }

  void _saveCurrentSessionState() {
    if (currentSessionId == null) return;
    final idx = sessions.indexWhere((s) => s.id == currentSessionId);
    if (idx == -1) return;
    sessions[idx] = _currentSessionMeta();
  }

  void _resetSessionState() {
    messages = [];
    sessionPromptTokens = 0;
    sessionCompletionTokens = 0;
    _conversationSummary = null;
    _lastSummarizedIndex = 0;
    streamingContent = null;
    isLoading = false;
    error = null;
  }

  void _sortSessions() {
    sessions.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }
}
