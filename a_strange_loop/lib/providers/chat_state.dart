import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:a_strange_loop/models/message.dart';
import 'package:a_strange_loop/services/firestore_service.dart';
import 'package:a_strange_loop/services/ai_service.dart';
import 'package:a_strange_loop/constants/system_prompt.dart';

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

      final prompt = _buildPrompt(brain, messages);

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
    final history = msgs
        .map((m) =>
            '${m.role == 'user' ? 'User' : 'Assistant'}: ${m.content}')
        .join('\n\n');

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
