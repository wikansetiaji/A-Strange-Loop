import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:a_strange_loop/constants/api_config.dart';

class AIService {
  final http.Client _client = http.Client();

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
