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
import 'package:a_strange_loop/services/app_config.dart';
import 'package:a_strange_loop/constants/system_prompt.dart';
import 'package:a_strange_loop/constants/api_config.dart';
import 'package:a_strange_loop/constants/brain_tools.dart';
import 'package:a_strange_loop/models/model_settings.dart';

class ChatState extends ChangeNotifier {
  FirestoreService _firestore;
  final AIService _ai = AIService();
  late HardcoverService _hardcover;
  late SyncService _sync;

  String? currentSessionId;
  List<Session> sessions = [];

  List<Message> messages = [];
  String? streamingContent;
  String? streamingThinking;
  bool isLoading = false;
  String? error;

  int sessionPromptTokens = 0;
  int sessionCompletionTokens = 0;
  int sessionCacheHitTokens = 0;
  int sessionCacheMissTokens = 0;

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

  bool _mutationsAppliedThisTurn = false;

  SyncService get sync => _sync;

  Future<String> loadBrain({bool forceRefresh = false}) =>
      _getBrain(forceRefresh: forceRefresh);

  Timer? _searchDebounce;
  bool isSearching = false;

  ChatState({FirestoreService? firestore})
      : _firestore = firestore ?? FirestoreService();

  void initServices({
    required HardcoverService hardcoverService,
    required SyncService syncService,
  }) {
    _hardcover = hardcoverService;
    _sync = syncService;
  }

  int get syncPendingCount => _sync.pendingCount;

  Future<void> reconcileHardcover() => _sync.startupReconcile();

  Future<void> reloadWithQaMode() async {
    final qaMode = AppConfig().isQaMode;
    _sync.dispose();
    _sync = SyncService(
      firestore: FirestoreService(
        collectionPrefix: qaMode ? '_qa' : '',
      ),
      hardcover: HardcoverService(
        apiKey: AppConfig().hardcoverApiKey,
        userId: AppConfig().hardcoverUserId,
        apiEndpoint: AppConfig().hardcoverEndpoint,
      ),
      collectionPrefix: qaMode ? '_qa' : '',
    );
    _hardcover = HardcoverService(
      apiKey: AppConfig().hardcoverApiKey,
      userId: AppConfig().hardcoverUserId,
      apiEndpoint: AppConfig().hardcoverEndpoint,
    );
    _firestore = FirestoreService(
      collectionPrefix: qaMode ? '_qa' : '',
    );

    _brainCache = null;
    _brainFetchedAt = null;
    currentSessionId = null;
    sessions = [];
    messages = [];
    streamingContent = null;
    streamingThinking = null;
    error = null;
    _conversationSummary = null;
    _lastSummarizedIndex = 0;
    sessionPromptTokens = 0;
    sessionCompletionTokens = 0;
    sessionCacheHitTokens = 0;
    sessionCacheMissTokens = 0;
    notifyListeners();

    try {
      await seedBrainIfNeeded();
    } catch (e) {
      debugPrint('QA seed skipped: $e');
    }

    unawaited(_sync.startupReconcile().whenComplete(() {
      _sync.startPeriodicSync();
    }));

    await initializeSessions();
  }

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
    sessionCacheHitTokens = target.cacheHitTokens;
    sessionCacheMissTokens = target.cacheMissTokens;
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
    _mutationsAppliedThisTurn = false;
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
    _mutationsAppliedThisTurn = false;
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
      _mutationsAppliedThisTurn = false;
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
    final tools = BrainTools.all;

    fullResponse:
    while (toolCallRounds <= maxToolCallRounds) {
      final buffer = StringBuffer();
      String visibleBuffer = '';
      String streamingIndicator = '';
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
            sessionCacheHitTokens += event.cacheHitTokens ?? 0;
            sessionCacheMissTokens += event.cacheMissTokens ?? 0;
          } else if (event.reasoningContent != null) {
            streamingThinking =
                (streamingThinking ?? '') + event.reasoningContent!;
            _throttledNotify();
          } else if (event.content.isNotEmpty) {
            final chunk = event.content;
            buffer.write(chunk);
            visibleBuffer += chunk;

            streamingContent = visibleBuffer;
            _throttledNotify();
          }
        }
      }

      if (toolRequests.isNotEmpty && toolCallRounds < maxToolCallRounds) {
        final fullContent = buffer.toString();
        final prose = fullContent.trim();

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

        final hasBrainTools = toolRequests.any((tc) => tc.name != 'searchBooks');
        streamingIndicator = hasBrainTools ? 'Updating brain...' : 'Searching Hardcover...';
        streamingContent = streamingIndicator;
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
          String toolResult;
          switch (tc.name) {
            case 'searchBooks':
              toolResult = await _handleSearchBooks(tc.arguments);
              break;
            case 'appendBook':
              toolResult = await _handleAppendBook(tc.arguments);
              break;
            case 'updateBook':
              toolResult = await _handleUpdateBook(tc.arguments);
              break;
            case 'deleteBook':
              toolResult = await _handleDeleteBook(tc.arguments);
              break;
            case 'patchBrain':
              toolResult = await _handlePatchBrain(tc.arguments);
              break;
            case 'logObservation':
              toolResult = await _handleLogObservation(tc.arguments);
              break;
            default:
              toolResult = jsonEncode({'error': 'Unknown tool: ${tc.name}'});
          }
          apiMessages.add({
            'role': 'tool',
            'tool_call_id': tc.id,
            'content': toolResult,
          });
        }

        toolCallRounds++;
        continue fullResponse;
      }

      final fullContent = buffer.toString();
      final prose = fullContent.trim().isEmpty
          ? "I got lost in thought and ran out of space. Could you rephrase or try again?"
          : fullContent.trim();

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

      if (_mutationsAppliedThisTurn) {
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
      }

      notifyListeners();
      break;
    }

    if (toolCallRounds > maxToolCallRounds &&
        streamingContent != null &&
        streamingContent!.isNotEmpty) {
      streamingContent = null;
      isLoading = false;
      error = 'Tool call limit reached. Please try again.';
      notifyListeners();
    }
  }

  // ── Tool handlers ─────────────────────────────────────────────

  Future<String> _handleSearchBooks(Map<String, dynamic> args) async {
    final query = args['query'] as String? ?? '';
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
      final searchDoneMsg = Message(
        role: 'status',
        content: '{"t":"searchDone","q":${jsonEncode(query)}}',
        order: messages.length,
      );
      messages.add(searchDoneMsg);
      _firestore.saveMessage(currentSessionId!, searchDoneMsg);
      return jsonEncode(minimalResults);
    } catch (e) {
      return jsonEncode({'error': e.toString()});
    }
  }

  Future<String> _handleAppendBook(Map<String, dynamic> args) async {
    try {
      final previousBrain = await _getBrain();
      final brain = await _firestore.getBrain();
      final update = BrainParser.appendBook(brain, args);
      await _firestore.updateBrain(update.brain, update.log);
      _brainCache = update.brain;
      _brainFetchedAt = DateTime.now();
      _parseCurrentReading(update.brain);
      _sync.enqueueFromBrainMutation(
        [
          OperationBlock(
            type: BlockType.appendBook,
            rawText: jsonEncode(args),
            jsonData: args,
          )
        ],
        previousBrain,
      );
      _sync.drainSyncQueue();
      _mutationsAppliedThisTurn = true;
      final title = args['title'] as String? ?? 'Unknown';
      final status = args['status'] as String? ?? '';
      return "Added '$title' to your brain. ($status)";
    } catch (e) {
      return "Couldn't add that book: $e";
    }
  }

  Future<String> _handleUpdateBook(Map<String, dynamic> args) async {
    try {
      final targetTitle = args['targetTitle'] as String? ?? '';
      final bookJson = args['book'] as Map<String, dynamic>?;
      if (targetTitle.isEmpty || bookJson == null) {
        return "Error: targetTitle and book are required";
      }
      final previousBrain = await _getBrain();
      final brain = await _firestore.getBrain();
      final update = BrainParser.updateBook(brain, targetTitle, bookJson);
      await _firestore.updateBrain(update.brain, update.log);
      _brainCache = update.brain;
      _brainFetchedAt = DateTime.now();
      _parseCurrentReading(update.brain);
      _sync.enqueueFromBrainMutation(
        [
          OperationBlock(
            type: BlockType.updateBook,
            rawText: jsonEncode(args),
            jsonData: args,
          )
        ],
        previousBrain,
      );
      _sync.drainSyncQueue();
      _mutationsAppliedThisTurn = true;
      return "Updated '$targetTitle' in your brain.";
    } catch (e) {
      return "Couldn't update that book: $e";
    }
  }

  Future<String> _handleDeleteBook(Map<String, dynamic> args) async {
    try {
      final targetTitle = args['targetTitle'] as String? ?? '';
      if (targetTitle.isEmpty) {
        return "Error: targetTitle is required";
      }
      final previousBrain = await _getBrain();
      final brain = await _firestore.getBrain();
      final update = BrainParser.deleteBook(brain, targetTitle);
      await _firestore.updateBrain(update.brain, update.log);
      _brainCache = update.brain;
      _brainFetchedAt = DateTime.now();
      _parseCurrentReading(update.brain);
      _sync.enqueueFromBrainMutation(
        [
          OperationBlock(
            type: BlockType.deleteBook,
            rawText: jsonEncode(args),
            jsonData: args,
          )
        ],
        previousBrain,
      );
      _sync.drainSyncQueue();
      _mutationsAppliedThisTurn = true;
      return "Removed '$targetTitle' from your brain.";
    } catch (e) {
      return "Couldn't delete that book: $e";
    }
  }

  Future<String> _handlePatchBrain(Map<String, dynamic> args) async {
    try {
      final targetSection = args['targetSection'] as String? ?? '';
      final replacementContent = args['replacementContent'];
      if (targetSection.isEmpty ||
          (replacementContent == null &&
              targetSection != 'CURRENT_READING')) {
        return "Error: targetSection is required, and replacementContent must not be null (except for clearing CURRENT_READING)";
      }
      final reason = args['reason'] as String?;
      final confidence = (args['confidence'] as num?)?.toDouble();
      final previousBrain = await _getBrain();
      final brain = await _firestore.getBrain();
      final update = BrainParser.patchBrain(
        brain,
        targetSection,
        replacementContent,
        reason: reason,
        confidence: confidence,
      );
      if (update.log.isEmpty) {
        return "Error: Could not apply patch to $targetSection — "
            "the section name or replacement type may be incorrect. "
            "Try using a subsection target (e.g., READER_BLIND_SPOTS.UNDERVALUED with a string, "
            "READER_BLIND_SPOTS with a full object).";
      }
      await _firestore.updateBrain(update.brain, update.log);
      _brainCache = update.brain;
      _brainFetchedAt = DateTime.now();
      _parseCurrentReading(update.brain);
      _sync.enqueueFromBrainMutation(
        [
          OperationBlock(
            type: BlockType.patch,
            rawText: jsonEncode(args),
            jsonData: args,
          )
        ],
        previousBrain,
      );
      _sync.drainSyncQueue();
      _mutationsAppliedThisTurn = true;
      return "Patched $targetSection.";
    } catch (e) {
      return "Couldn't patch brain: $e";
    }
  }

  Future<String> _handleLogObservation(Map<String, dynamic> args) async {
    try {
      final brain = await _firestore.getBrain();
      final update = BrainParser.addObservation(brain, args);
      await _firestore.updateBrain(update.brain, update.log);
      _brainCache = update.brain;
      _brainFetchedAt = DateTime.now();
      _mutationsAppliedThisTurn = true;
      final isPromotion = update.log.any(
        (e) => e.operation == 'OBSERVATION_PROMOTION');
      if (isPromotion) {
        return "Observation promoted: ${update.log.length} matching entries cleaned up. "
            "Now call patchBrain to solidify the insight into the appropriate section.";
      }
      return "Observation logged.";
    } catch (e) {
      return "Couldn't log observation: $e";
    }
  }

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
    final cache = sessionCacheHitTokens + sessionCacheMissTokens;
    final totalStr =
        total >= 1000 ? '${(total / 1000).toStringAsFixed(1)}K' : '$total';
    if (cache <= 0 || sessionCacheHitTokens <= 0) {
      return '$totalStr tokens this session';
    }
    final pct =
        (sessionCacheHitTokens / cache * 100).clamp(0, 100).toStringAsFixed(0);
    final hitStr = sessionCacheHitTokens >= 1000
        ? (sessionCacheHitTokens / 1000).toStringAsFixed(1)
        : sessionCacheHitTokens.toString();
    return '$totalStr tokens this session \u00b7 ${hitStr}K cached ($pct%)';
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
      cacheHitTokens: sessionCacheHitTokens,
      cacheMissTokens: sessionCacheMissTokens,
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
    sessionCacheHitTokens = 0;
    sessionCacheMissTokens = 0;
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
