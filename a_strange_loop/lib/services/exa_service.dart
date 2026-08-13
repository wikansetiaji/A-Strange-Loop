import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:a_strange_loop/constants/api_config.dart';

class ExaService {
  final http.Client _client = http.Client();

  Future<String> search({
    required String query,
    required String type,
    int numResults = 5,
    String? category,
  }) async {
    final body = <String, dynamic>{
      'query': query,
      'type': type,
      'numResults': numResults,
      if (category != null) 'category': category,
      if (type == 'deep')
        ...{
          'contents': {
            'summary': {'query': query},
          },
          'outputSchema': {
            'type': 'text',
            'description': 'Synthesize a concise cited answer to: $query',
          },
        }
      else
        ...{
          'contents': {
            'highlights': true,
          },
        },
    };

    final response = await _client.post(
      Uri.parse(exaApiEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': exaApiKey,
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('Exa error ${response.statusCode}: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (json['results'] as List? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();

    if (type == 'deep') {
      return _shapeDeepResult(json, results);
    }
    return jsonEncode(results.map(_shapeAutoResult).toList());
  }

  Map<String, dynamic> _shapeAutoResult(Map<String, dynamic> r) {
    final highlights = (r['highlights'] as List? ?? [])
        .map((h) => h.toString())
        .where((h) => h.trim().isNotEmpty)
        .take(2)
        .map((h) => _truncate(h, 250))
        .toList();
    return {
      'title': r['title'],
      'url': r['url'],
      if (r['publishedDate'] != null) 'publishedDate': r['publishedDate'],
      if (highlights.isNotEmpty) 'highlights': highlights,
    };
  }

  String _shapeDeepResult(
      Map<String, dynamic> json, List<Map<String, dynamic>> results) {
    final output = json['output'] as Map<String, dynamic>?;
    final content = output?['content'];
    if (content is String && content.trim().isNotEmpty) {
      final grounding = output?['grounding'] as List? ?? [];
      final citations = grounding
          .expand((g) {
            final gMap = g as Map<String, dynamic>;
            return (gMap['citations'] as List? ?? [])
                .map((c) => c as Map<String, dynamic>);
          })
          .map((c) => {
                'url': c['url'],
                if (c['title'] != null) 'title': c['title'],
              })
          .toList();
      return jsonEncode({
        'answer': _truncate(content, 3000),
        'citations': citations,
      });
    }
    final sources = results
        .map((r) => {
              'title': r['title'],
              'url': r['url'],
              if (r['summary'] is String)
                'summary': _truncate(r['summary'] as String, 800),
            })
        .toList();
    return jsonEncode({'sources': sources});
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}...';

  void dispose() {
    _client.close();
  }
}
