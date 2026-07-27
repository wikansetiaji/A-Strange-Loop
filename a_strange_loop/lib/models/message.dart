import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  final String role;
  final String content;
  final DateTime timestamp;
  final int order;

  Message({
    required this.role,
    required this.content,
    this.order = 0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      role: map['role'] as String,
      content: map['content'] as String? ?? '',
      order: map['order'] as int? ?? 0,
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'role': role,
      'content': content,
      'order': order,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}
