import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:a_strange_loop/models/session.dart';
import 'package:a_strange_loop/models/message.dart';
import 'package:a_strange_loop/models/brain.dart';
import 'package:a_strange_loop/services/brain_parser.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<String> getBrain() async {
    final doc =
        await _firestore.collection('meta').doc('brain_json').get();
    if (!doc.exists) {
      throw Exception('Brain document not found at meta/brain_json');
    }
    return doc.data()?['content'] ?? '';
  }

  Future<void> uploadBrain(String jsonContent) async {
    final bookCount = _countBooks(jsonContent);
    await _firestore.collection('meta').doc('brain_json').set({
      'content': jsonContent,
      'updated_at': FieldValue.serverTimestamp(),
      'book_count': bookCount,
    });
  }

  int _countBooks(String jsonContent) {
    try {
      final brain =
          Brain.fromJson(jsonDecode(jsonContent) as Map<String, dynamic>);
      return brain.books.length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> updateBrain(
      String jsonContent, List<PatchLogEntry> patchLog) async {
    final brainRef = _firestore.collection('meta').doc('brain_json');
    final batch = _firestore.batch();

    batch.set(brainRef, {
      'content': jsonContent,
      'updated_at': FieldValue.serverTimestamp(),
      'book_count': _countBooks(jsonContent),
    }, SetOptions(merge: true));

    for (final entry in patchLog) {
      final docRef = brainRef.collection('patch_log').doc();
      batch.set(docRef, {
        ...entry.toMap(),
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  // ── Session CRUD ──────────────────────────────────────────────

  Future<void> createSession(Session session) async {
    await _firestore.collection('sessions').doc(session.id).set(
          session.toMap(),
        );
  }

  Future<List<Session>> loadSessions() async {
    final snapshot = await _firestore
        .collection('sessions')
        .orderBy('updated_at', descending: true)
        .get();
    final sessions = snapshot.docs
        .map((doc) => Session.fromMap(doc.id, doc.data()))
        .toList();
    sessions.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return sessions;
  }

  Future<void> updateSessionMeta(
      String sessionId, Map<String, dynamic> data) async {
    await _firestore.collection('sessions').doc(sessionId).set(data,
        SetOptions(merge: true));
  }

  Future<void> deleteSession(String sessionId) async {
    final messagesSnapshot = await _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('messages')
        .get();
    final batch = _firestore.batch();
    for (final doc in messagesSnapshot.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_firestore.collection('sessions').doc(sessionId));
    await batch.commit();
  }

  // ── Messages ──────────────────────────────────────────────────

  Future<List<Message>> loadMessages(String sessionId) async {
    final snapshot = await _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('messages')
        .orderBy('order')
        .get();
    return snapshot.docs
        .map((doc) => Message.fromMap(doc.data(), id: doc.id))
        .toList();
  }

  Future<String> saveMessage(String sessionId, Message message) async {
    final docRef = await _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('messages')
        .add(message.toMap());
    return docRef.id;
  }

  Future<void> updateMessageContent(
      String sessionId, String firestoreId, String newContent) async {
    await _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('messages')
        .doc(firestoreId)
        .update({
      'content': newContent,
      'timestamp': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> deleteMessagesAfterOrder(
      String sessionId, int afterOrder) async {
    final snapshot = await _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('messages')
        .where('order', isGreaterThan: afterOrder)
        .get();
    if (snapshot.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // ── Search ────────────────────────────────────────────────────

  Future<List<Session>> searchSessionsByTitle(String query) async {
    final snapshot = await _firestore
        .collection('sessions')
        .orderBy('title')
        .startAt([query])
        .endAt(['$query\uf8ff'])
        .get();
    return snapshot.docs
        .map((doc) => Session.fromMap(doc.id, doc.data()))
        .toList();
  }

  // ── Pin ───────────────────────────────────────────────────────

  Future<void> pinSession(String sessionId, bool pinned) async {
    await updateSessionMeta(sessionId, {
      'pinned': pinned,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  // ── Legacy (kept for compatibility) ───────────────────────────

  Future<void> saveSessionStats(
      String sessionId, int promptTokens, int completionTokens) async {
    await updateSessionMeta(sessionId, {
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'updated_at': FieldValue.serverTimestamp(),
      'created_at': FieldValue.serverTimestamp(),
    });
  }
}
