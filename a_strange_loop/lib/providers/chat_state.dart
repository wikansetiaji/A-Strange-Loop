import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:a_strange_loop/models/message.dart';
import 'package:a_strange_loop/services/firestore_service.dart';
import 'package:a_strange_loop/services/ai_service.dart';
import 'package:a_strange_loop/constants/system_prompt.dart';
import 'package:a_strange_loop/constants/api_config.dart';
import 'package:a_strange_loop/utils/token_counter.dart';

class ChatState extends ChangeNotifier {
  final FirestoreService _firestore = FirestoreService();
  final AIService _ai = AIService();

  final String sessionId = DateTime.now()
      .millisecondsSinceEpoch
      .toString();

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

  Future<void> seedBrainIfNeeded() async {
    try {
      await _firestore.getBrain();
    } catch (_) {
      final brain = await rootBundle.loadString('assets/reading_brain.md');
      await _firestore.uploadBrain(brain);
    }
  }

  Future<void> sendMessage(String text) async {
    final userMsg = Message(role: 'user', content: text);
    messages.add(userMsg);
    streamingContent = '';
    error = null;
    isLoading = true;
    notifyListeners();

    try {
      final brain = await _getBrain();

      final compressed = await _maybeCompress(brain);
      final prompt = _buildPrompt(brain, compressed);

      final buffer = StringBuffer();

      await for (final chunk in _ai.sendMessageStream(prompt)) {
        if (chunk.startsWith('[USAGE:')) {
          final parts = chunk
              .substring(7, chunk.length - 1)
              .split(':');
          sessionPromptTokens += int.parse(parts[0]);
          sessionCompletionTokens += int.parse(parts[1]);
        } else {
          buffer.write(chunk);
          streamingContent = buffer.toString();
          _throttledNotify();
        }
      }

      final content = buffer.toString();
      final assistantMsg = Message(role: 'assistant', content: content);
      messages.add(assistantMsg);
      streamingContent = null;
      isLoading = false;

      await _firestore.saveSessionStats(
          sessionId, sessionPromptTokens, sessionCompletionTokens);

      notifyListeners();
    } catch (e) {
      streamingContent = null;
      isLoading = false;
      error = e.toString();
      notifyListeners();
    }
  }

  void _throttledNotify() {
    final now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds >= 50) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  Future<List<Message>> _maybeCompress(String brain) async {
    final fullPrompt = _buildPrompt(brain, messages);
    final totalTokens = TokenCounter.count(fullPrompt);

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
}
