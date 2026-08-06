import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:a_strange_loop/models/message.dart';
import 'package:a_strange_loop/models/session.dart';
import 'package:a_strange_loop/models/brain.dart';
import 'package:a_strange_loop/services/firestore_service.dart';
import 'package:a_strange_loop/services/ai_service.dart';
import 'package:a_strange_loop/services/brain_parser.dart';
import 'package:a_strange_loop/services/hardcover_service.dart';
import 'package:a_strange_loop/services/sync_service.dart';
import 'package:a_strange_loop/constants/system_prompt.dart';
import 'package:a_strange_loop/constants/api_config.dart';
import 'package:a_strange_loop/models/model_settings.dart';

class ChatState extends ChangeNotifier {
  final FirestoreService _firestore = FirestoreService();
  final AIService _ai = AIService();
  late final HardcoverService _hardcover;
  late final SyncService _sync;

  String? currentSessionId;
  List<Session> sessions = [];

  List<Message> messages = [];
  String? streamingContent;
  String? streamingThinking;
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

  ModelSettings _modelSettings = const ModelSettings();
  ModelSettings get modelSettings => _modelSettings;

  String? get brainContent => _brainCache;

  Future<String> loadBrain({bool forceRefresh = false}) =>
      _getBrain(forceRefresh: forceRefresh);

  Timer? _searchDebounce;
  bool isSearching = false;

  void initServices({
    required HardcoverService hardcoverService,
    required SyncService syncService,
  }) {
    _hardcover = hardcoverService;
    _sync = syncService;
  }

  int get syncPendingCount => _sync.pendingCount;

  Future<void> reconcileHardcover() => _sync.startupReconcile();

  Future<void> loadModelSettings() async {
    _modelSettings = await _firestore.getModelSettings();
    _ai.updateSettings(_modelSettings.model, _modelSettings.thinkingEffort);
  }

  Future<void> updateModelSettings(ModelSettings settings) async {
    _modelSettings = settings;
    _ai.updateSettings(settings.model, settings.thinkingEffort);
    await _firestore.saveModelSettings(settings);
    notifyListeners();
  }

  Future<void> seedBrainIfNeeded() async {
    try {
      await _firestore.getBrain();
    } catch (_) {
      final brain = await rootBundle.loadString('assets/reading_brain.json');
      await _firestore.uploadBrain(brain);
    }
  }

  // ── Session lifecycle ─────────────────────────────────────────

  Future<void> initializeSessions() async {
    final loaded = await _firestore.loadSessions();
    sessions = loaded;
    await loadModelSettings();
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
    streamingThinking = null;
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
    streamingThinking = null;
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

    final lastRealMsg = messages
        .lastWhere((m) => m.role == 'user' || m.role == 'assistant',
            orElse: () => messages.last);
    if (lastRealMsg.role == 'user') {
      streamingContent = '';
      streamingThinking = null;
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

    int toolCallRounds = 0;
    List<Map<String, dynamic>> apiMessages = _buildApiMessages(
        brain, compressed);
    final tools = [_hardcover.searchBooksTool];

    fullResponse:
    while (toolCallRounds <= maxToolCallRounds) {
      final buffer = StringBuffer();
      bool blocksDetected = false;
      final blockBuffer = StringBuffer();
      String visibleBuffer = '';
      final toolRequests = <ToolCallRequest>[];

      await for (final event in _ai.sendMessageStreamWithTools(
        apiMessages,
        tools: tools,
      )) {
        if (event is ToolCallRequest) {
          toolRequests.add(event);
        } else if (event is TextChunk) {
          if (event.promptTokens != null) {
            sessionPromptTokens += event.promptTokens!;
            sessionCompletionTokens += event.completionTokens ?? 0;
          } else if (event.reasoningContent != null) {
            streamingThinking =
                (streamingThinking ?? '') + event.reasoningContent!;
            _throttledNotify();
          } else if (event.content.isNotEmpty) {
            final chunk = event.content;
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
      }

      if (toolRequests.isNotEmpty && toolCallRounds < maxToolCallRounds) {
        final fullContent = buffer.toString();
        final isBlockResponse =
            blocksDetected && _containsBlockMarker(fullContent);
        final parsed =
            isBlockResponse ? BrainParser.parse(fullContent) : null;
        final prose = parsed?.prose ?? fullContent;

        if (prose.isNotEmpty) {
          final intermediateMsg = Message(
            role: 'assistant',
            content: prose,
            order: messages.length,
          );
          messages.add(intermediateMsg);
          await _firestore.saveMessage(currentSessionId!, intermediateMsg);
        }

        streamingThinking = null;
        streamingContent = 'Searching Hardcover...';
        notifyListeners();

        final assistantMsg = <String, dynamic>{
          'role': 'assistant',
          'content': prose.isNotEmpty ? prose : null,
          'tool_calls': toolRequests.map((tc) => {
            'id': tc.id,
            'type': 'function',
            'function': {
              'name': tc.name,
              'arguments': jsonEncode(tc.arguments),
            },
          }).toList(),
        };
        apiMessages.add(assistantMsg);

        for (final tc in toolRequests) {
          if (tc.name == 'searchBooks') {
            final query = tc.arguments['query'] as String? ?? '';
            try {
              final results = await _hardcover.searchBooks(query);
              final minimalResults = results
                  .take(3)
                  .map((r) => {
                        'id': r.id,
                        'title': r.title,
                        'author': r.author ?? '',
                        if (r.rating != null) 'rating': r.rating,
                      })
                  .toList();
              apiMessages.add({
                'role': 'tool',
                'tool_call_id': tc.id,
                'content': jsonEncode(minimalResults),
              });
              final searchDoneMsg = Message(
                role: 'status',
                content: '{"t":"searchDone","q":${jsonEncode(query)}}',
                order: messages.length,
              );
              messages.add(searchDoneMsg);
              _firestore.saveMessage(currentSessionId!, searchDoneMsg);
            } catch (e) {
              apiMessages.add({
                'role': 'tool',
                'tool_call_id': tc.id,
                'content': jsonEncode({'error': e.toString()}),
              });
            }
          } else {
            apiMessages.add({
              'role': 'tool',
              'tool_call_id': tc.id,
              'content': jsonEncode({'error': 'Unknown tool: ${tc.name}'}),
            });
          }
        }

        toolCallRounds++;
        continue fullResponse;
      }

      final fullContent = buffer.toString();
      final isBlockResponse =
          blocksDetected && _containsBlockMarker(fullContent);
      final parsed =
          isBlockResponse ? BrainParser.parse(fullContent) : null;
      final rawProse = parsed?.prose ?? fullContent;
      final prose = rawProse.trim().isEmpty
          ? "I got lost in thought and ran out of space. Could you rephrase or try again?"
          : rawProse;

      final assistantMsg = Message(
        role: 'assistant',
        content: prose,
        order: messages.length,
      );
      messages.add(assistantMsg);
      streamingContent = null;
      streamingThinking = null;
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

      final realMsgs = messages
          .where((m) => m.role == 'user' || m.role == 'assistant')
          .toList();
      final wasFirstExchange =
          realMsgs.length == 2 && meta.title == null;
      if (wasFirstExchange) {
        _generateTitle(realMsgs[0].content, realMsgs[1].content);
      }

      if (parsed != null && parsed.blocks.isNotEmpty) {
        try {
          final previousBrain = await _getBrain();
          final freshBrain = await _firestore.getBrain();
          final update =
              BrainParser.applyBlocks(freshBrain, parsed.blocks);
          await _firestore.updateBrain(update.brain, update.log);
          _brainCache = update.brain;
          _brainFetchedAt = DateTime.now();
          _parseCurrentReading(update.brain);
          _sync.enqueueFromBrainMutation(
              parsed.blocks, previousBrain);
          _sync.drainSyncQueue();
          final brainMsg = Message(
            role: 'status',
            content: '{"t":"brainUpdated"}',
            order: messages.length,
          );
          messages.add(brainMsg);
          _firestore.saveMessage(currentSessionId!, brainMsg);
          final hardcoverMsg = Message(
            role: 'status',
            content: '{"t":"hardcoverUpdated"}',
            order: messages.length,
          );
          messages.add(hardcoverMsg);
          _firestore.saveMessage(currentSessionId!, hardcoverMsg);
        } catch (e) {
          debugPrint('BrainParser error: $e');
        }
      }

      notifyListeners();
      break;
    }

    if (toolCallRounds > maxToolCallRounds &&
        streamingContent == 'Searching Hardcover...') {
      streamingContent = null;
      isLoading = false;
      error = 'Tool call limit reached. Please try again.';
      notifyListeners();
    }
  }

  static int _findBlockMarker(String text) {
    final regex = RegExp(
      r'(?:^|\n)(?:BEGIN_(?:JSON_)?)?(?:APPEND_BOOK|UPDATE_BOOK|DELETE_BOOK|PATCH(?:\s+\w+)?|OBSERVATION)',
    );
    final match = regex.firstMatch(text);
    return match?.start ?? -1;
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
    final fullMessages = _buildApiMessages(brain, messages);
    final fullPrompt = fullMessages
        .map((m) => m['content']?.toString() ?? '')
        .join();
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

  Future<String> _getBrain({bool forceRefresh = false}) async {
    if (!forceRefresh && _brainCache != null && _brainFetchedAt != null) {
      return _brainCache!;
    }
    final brain = await _firestore.getBrain();
    _brainCache = brain;
    _brainFetchedAt = DateTime.now();
    _parseCurrentReading(brain);
    return brain;
  }

  void _parseCurrentReading(String brainJson) {
    try {
      final brain = Brain.fromJson(
          jsonDecode(brainJson) as Map<String, dynamic>);
      final cr = brain.currentReading;
      if (cr != null && cr.isNotEmpty) {
        currentBookTitle = cr.book;
        currentBookProgress = cr.progress.isNotEmpty ? cr.progress : null;
      } else {
        currentBookTitle = null;
        currentBookProgress = null;
      }
    } catch (_) {
      currentBookTitle = null;
      currentBookProgress = null;
    }
  }

  String _buildBrainContext(String brainJson) {
    try {
      final brain = Brain.fromJson(
          jsonDecode(brainJson) as Map<String, dynamic>);
      return brain.toMarkdownForContext(maxBooks: maxBrainBooks);
    } catch (_) {
      return brainJson;
    }
  }

  List<Map<String, dynamic>> _buildApiMessages(
      String brain, List<Message> msgs) {
    final brainContext = _buildBrainContext(brain);
    final result = <Map<String, dynamic>>[
      {'role': 'system', 'content': companionSystemPrompt},
      {'role': 'system', 'content': brainContext},
    ];

    for (final m in msgs) {
      if (m.role == 'status') continue;
      if (m.role == 'system') {
        result.add({
          'role': 'system',
          'content': '## Conversation Summary\n\n${m.content}',
        });
      } else {
        result.add({
          'role': m.role,
          'content': m.content,
        });
      }
    }

    return result;
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
    final realMessages =
        messages.where((m) => m.role == 'user' || m.role == 'assistant').toList();
    final lastMsg = realMessages.isNotEmpty ? realMessages.last : null;
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
      messageCount: realMessages.length,
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
