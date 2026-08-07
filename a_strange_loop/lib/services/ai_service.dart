import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:a_strange_loop/constants/api_config.dart';
import 'package:a_strange_loop/models/model_settings.dart';

class TextChunk {
  final String content;
  final String? reasoningContent;
  final bool isComplete;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
  final int? cacheHitTokens;
  final int? cacheMissTokens;

  const TextChunk({
    required this.content,
    this.reasoningContent,
    this.isComplete = false,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.cacheHitTokens,
    this.cacheMissTokens,
  });
}

class ToolCallRequest {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  const ToolCallRequest({
    required this.id,
    required this.name,
    required this.arguments,
  });
}

class _ToolCallAccumulator {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}

class AIService {
  final http.Client _client = http.Client();

  String _model;
  Map<String, dynamic> _thinking;
  String? _reasoningEffort;

  AIService({String? model, String? thinkingEffort})
      : _model = model ?? ModelSettings.defaultModel,
        _thinking = _buildThinkingParam(thinkingEffort ?? ModelSettings.defaultThinking),
        _reasoningEffort = _buildEffort(thinkingEffort ?? ModelSettings.defaultThinking);

  String get model => _model;
  Map<String, dynamic> get thinking => _thinking;

  void updateSettings(String model, String thinkingEffort) {
    _model = model;
    _thinking = _buildThinkingParam(thinkingEffort);
    _reasoningEffort = _buildEffort(thinkingEffort);
  }

  static Map<String, dynamic> _buildThinkingParam(String effort) {
    if (effort == 'disabled') return {'type': 'disabled'};
    return {'type': 'enabled'};
  }

  static String? _buildEffort(String effort) {
    if (effort == 'disabled') return null;
    return effort;
  }

  static const _thinkingDisabled = {'type': 'disabled'};

  Future<String> summarize(String textToSummarize) async {
    final request = http.Request('POST', Uri.parse(deepseekApiEndpoint));
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $deepseekApiKey',
    });
    request.body = jsonEncode({
      'model': _model,
      'messages': [
        {
          'role': 'system',
          'content': 'Summarize the following conversation concisely. '
              'Preserve:\n'
              '- Books discussed (titles, authors, key details)\n'
              '- Reading recommendations given or considered\n'
              "- User's expressed preferences, opinions, or shifts in taste\n"
              '- Key decisions or conclusions\n'
              '- Active questions or ongoing threads\n'
              'Output only the summary, no preamble.'
        },
        {'role': 'user', 'content': textToSummarize},
      ],
      'temperature': 0.3,
      'max_tokens': 2048,
      'stream': false,
      'thinking': _thinking,
      if (_reasoningEffort != null) 'reasoning_effort': _reasoningEffort,
    });

    final response = await _client.send(request);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('Summarization error ${response.statusCode}: $body');
    }

    final body = await response.stream.bytesToString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final choices = json['choices'] as List;
    return choices[0]['message']['content'] as String;
  }

  Future<String?> generateTitle(
      String firstUserMsg, String firstAssistantMsg) async {
    try {
      final request = http.Request('POST', Uri.parse(deepseekApiEndpoint));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $deepseekApiKey',
      });
      request.body = jsonEncode({
        'model': _model,
        'messages': [
          {
            'role': 'system',
            'content': 'Generate a short title (max 6 words) for this '
                'conversation. Output ONLY the title, no quotes, no '
                'punctuation, no explanation.'
          },
          {
            'role': 'user',
            'content': 'User: $firstUserMsg\n\nAssistant: $firstAssistantMsg',
          },
        ],
        'max_tokens': 64,
        'temperature': 0.3,
        'stream': false,
        'thinking': _thinkingDisabled,
      });

      final response = await _client.send(request);
      if (response.statusCode != 200) return null;

      final body = await response.stream.bytesToString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final choices = json['choices'] as List;
      final message = choices[0]['message'] as Map<String, dynamic>;

      final title = (message['content'] as String?)?.trim();
      if (title != null && title.isNotEmpty) {
        return title;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Stream<String> sendMessageStream(String prompt) async* {
    final request = http.Request('POST', Uri.parse(deepseekApiEndpoint));
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $deepseekApiKey',
    });
    request.body = jsonEncode({
      'model': _model,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'temperature': 0.7,
      'max_tokens': 4096,
      'stream': true,
      'thinking': _thinking,
      if (_reasoningEffort != null) 'reasoning_effort': _reasoningEffort,
    });

    final response = await _client.send(request);

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('API error ${response.statusCode}: $body');
    }

    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6);
      if (data == '[DONE]') break;

      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final choices = json['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;

        final delta = choices[0]['delta'] as Map<String, dynamic>?;
        final content = delta?['content'] as String?;
        if (content != null) {
          yield content;
        }

        final finishReason = choices[0]['finish_reason'] as String?;
        if (finishReason != null) {
          final usage = json['usage'] as Map<String, dynamic>?;
          if (usage != null) {
            yield '[USAGE:${usage['prompt_tokens'] ?? 0}'
                ':${usage['completion_tokens'] ?? 0}'
                ':${usage['total_tokens'] ?? 0}]';
          }
        }
      } catch (_) {
        continue;
      }
    }
  }

  Stream<Object> sendMessageStreamWithTools(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async* {
    final request = http.Request('POST', Uri.parse(deepseekApiEndpoint));
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $deepseekApiKey',
    });

    final body = <String, dynamic>{
      'model': _model,
      'messages': messages,
      'temperature': 0.7,
      'max_tokens': 8192,
      'stream': true,
      'thinking': _thinking,
      if (_reasoningEffort != null) 'reasoning_effort': _reasoningEffort,
    };
    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools;
    }
    request.body = jsonEncode(body);

    final response = await _client.send(request);

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      throw Exception('API error ${response.statusCode}: $errorBody');
    }

    final toolAccumulators = <int, _ToolCallAccumulator>{};
    String finishReason = '';

    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6);
      if (data == '[DONE]') break;

      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final choices = json['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;

        finishReason =
            choices[0]['finish_reason'] as String? ?? finishReason;

        final delta = choices[0]['delta'] as Map<String, dynamic>?;
        if (delta == null) continue;

        final content = delta['content'] as String?;
        if (content != null) {
          yield TextChunk(content: content);
        }

        final reasoningContent = delta['reasoning_content'] as String?;
        if (reasoningContent != null) {
          yield TextChunk(content: '', reasoningContent: reasoningContent);
        }

        final toolCalls = delta['tool_calls'] as List<dynamic>?;
        if (toolCalls != null) {
          for (final tc in toolCalls) {
            final tcMap = tc as Map<String, dynamic>;
            final index = (tcMap['index'] as num?)?.toInt() ?? 0;
            final acc = toolAccumulators.putIfAbsent(
                index, () => _ToolCallAccumulator());
            if (tcMap.containsKey('id')) {
              acc.id = tcMap['id'] as String?;
            }
            if (tcMap.containsKey('function')) {
              final func = tcMap['function'] as Map<String, dynamic>?;
              if (func != null) {
                if (func.containsKey('name')) {
                  acc.name = func['name'] as String?;
                }
                if (func['arguments'] != null) {
                  acc.arguments.write(func['arguments'] as String);
                }
              }
            }
          }
        }

        final usage = json['usage'] as Map<String, dynamic>?;
        if (usage != null) {
          yield TextChunk(
            content: '',
            promptTokens: usage['prompt_tokens'] as int? ?? 0,
            completionTokens: usage['completion_tokens'] as int? ?? 0,
            totalTokens: usage['total_tokens'] as int? ?? 0,
            cacheHitTokens: usage['prompt_cache_hit_tokens'] as int? ?? 0,
            cacheMissTokens: usage['prompt_cache_miss_tokens'] as int? ?? 0,
          );
        }
      } catch (_) {
        continue;
      }
    }

    if (finishReason == 'tool_calls' && toolAccumulators.isNotEmpty) {
      for (final acc in toolAccumulators.values) {
        if (acc.id != null && acc.name != null) {
          try {
            final args = jsonDecode(acc.arguments.toString())
                as Map<String, dynamic>;
            yield ToolCallRequest(id: acc.id!, name: acc.name!, arguments: args);
          } catch (_) {
            continue;
          }
        }
      }
    }

    yield TextChunk(content: '', isComplete: true);
  }

  void dispose() {
    _client.close();
  }
}
