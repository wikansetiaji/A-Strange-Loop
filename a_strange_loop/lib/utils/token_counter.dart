import 'package:tiktoken/tiktoken.dart';

class TokenCounter {
  static Tiktoken? _encoding;

  static Tiktoken get encoding {
    _encoding ??= getEncoding('cl100k_base');
    return _encoding!;
  }

  static int count(String text) => encoding.encodeOrdinary(text).length;
}
