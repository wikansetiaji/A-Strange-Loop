import 'package:cloud_firestore/cloud_firestore.dart';

class SyncQueueItem {
  String? id;
  String action;
  Map<String, dynamic> payload;
  int retryCount;
  String status;
  String? lastError;
  DateTime createdAt;
  String? bookTitle;

  static const int maxRetries = 10;

  SyncQueueItem({
    this.id,
    required this.action,
    required this.payload,
    this.retryCount = 0,
    this.status = 'pending',
    this.lastError,
    DateTime? createdAt,
    this.bookTitle,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isAbandoned => retryCount >= maxRetries;

  factory SyncQueueItem.fromMap(String id, Map<String, dynamic> map) {
    return SyncQueueItem(
      id: id,
      action: map['action'] as String? ?? '',
      payload: Map<String, dynamic>.from(map['payload'] as Map? ?? {}),
      retryCount: map['retryCount'] as int? ?? 0,
      status: map['status'] as String? ?? 'pending',
      lastError: map['lastError'] as String?,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      bookTitle: map['bookTitle'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'action': action,
        'payload': payload,
        'retryCount': retryCount,
        'status': status,
        'lastError': lastError,
        'createdAt': Timestamp.fromDate(createdAt),
        if (bookTitle != null) 'bookTitle': bookTitle,
      };

  SyncQueueItem copyWith({
    String? id,
    String? action,
    Map<String, dynamic>? payload,
    int? retryCount,
    String? status,
    String? lastError,
    DateTime? createdAt,
    String? bookTitle,
  }) {
    return SyncQueueItem(
      id: id ?? this.id,
      action: action ?? this.action,
      payload: payload ?? Map<String, dynamic>.from(this.payload),
      retryCount: retryCount ?? this.retryCount,
      status: status ?? this.status,
      lastError: lastError,
      createdAt: createdAt ?? this.createdAt,
      bookTitle: bookTitle ?? this.bookTitle,
    );
  }
}
