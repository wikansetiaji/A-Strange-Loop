import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<String> getBrain() async {
    final doc =
        await _firestore.collection('meta').doc('brain').get();
    if (!doc.exists) {
      throw Exception('Brain document not found at meta/brain');
    }
    return doc.data()?['markdown_content'] ?? '';
  }

  Future<void> uploadBrain(String markdownContent) async {
    await _firestore.collection('meta').doc('brain').set({
      'markdown_content': markdownContent,
      'updated_at': FieldValue.serverTimestamp(),
      'book_count': _countBooks(markdownContent),
    });
  }

  Future<void> saveSessionStats(
      String sessionId, int promptTokens, int completionTokens) async {
    await _firestore.collection('sessions').doc(sessionId).set({
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'total_tokens': promptTokens + completionTokens,
      'updated_at': FieldValue.serverTimestamp(),
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  int _countBooks(String markdown) {
    final matches = RegExp(r'^# BOOK$', multiLine: true).allMatches(markdown);
    return matches.length;
  }
}
