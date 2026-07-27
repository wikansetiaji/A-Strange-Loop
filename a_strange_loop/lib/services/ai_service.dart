import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:a_strange_loop/constants/api_config.dart';

class AIService {
  final http.Client _client = http.Client();

  Future<String> summarize(String textToSummarize) async {
    final request = http.Request('POST', Uri.parse(deepseekApiEndpoint));
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $deepseekApiKey',
    });
    request.body = jsonEncode({
      'model': deepseekModel,
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
        'model': deepseekModel,
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
        'max_tokens': 256,
        'temperature': 0.3,
        'stream': false,
      });

      final response = await _client.send(request);
      if (response.statusCode != 200) return null;

      final body = await response.stream.bytesToString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final choices = json['choices'] as List;
      final message = choices[0]['message'] as Map<String, dynamic>;

      String? title = (message['content'] as String?)?.trim();
      if (title == null || title.isEmpty) {
        title = (message['reasoning_content'] as String?)?.trim();
      }
      if (title != null && title.isNotEmpty) {
        final lastLine = title.split('\n').last.trim();
        return lastLine;
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
      'model': deepseekModel,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'temperature': 0.7,
      'max_tokens': 4096,
      'stream': true,
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
}
