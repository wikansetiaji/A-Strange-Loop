import 'package:cloud_firestore/cloud_firestore.dart';

class Session {
  final String id;
  final String? title;
  final bool pinned;
  final String lastMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int promptTokens;
  final int completionTokens;
  final int messageCount;
  final String? conversationSummary;
  final int lastSummarizedIndex;

  Session({
    required this.id,
    this.title,
    this.pinned = false,
    this.lastMessage = '',
    required this.createdAt,
    required this.updatedAt,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.messageCount = 0,
    this.conversationSummary,
    this.lastSummarizedIndex = 0,
  });

  factory Session.fromMap(String id, Map<String, dynamic> map) {
    return Session(
      id: id,
      title: map['title'] as String?,
      pinned: map['pinned'] as bool? ?? false,
      lastMessage: map['last_message'] as String? ?? '',
      createdAt: (map['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      promptTokens: map['prompt_tokens'] as int? ?? 0,
      completionTokens: map['completion_tokens'] as int? ?? 0,
      messageCount: map['message_count'] as int? ?? 0,
      conversationSummary: map['conversation_summary'] as String?,
      lastSummarizedIndex: map['last_summarized_index'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'pinned': pinned,
      'last_message': lastMessage,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'message_count': messageCount,
      'conversation_summary': conversationSummary,
      'last_summarized_index': lastSummarizedIndex,
    };
  }

  int get totalTokens => promptTokens + completionTokens;

  String get displayTitle {
    if (title != null && title!.isNotEmpty) return title!;
    final date = createdAt;
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final amPm = date.hour >= 12 ? 'PM' : 'AM';
    final min = date.minute.toString().padLeft(2, '0');
    final day = date.day;
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final month = months[date.month - 1];
    return 'Chat \u00b7 $month $day, $hour:$min $amPm';
  }

  Session copyWith({
    String? title,
    bool? pinned,
    String? lastMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? promptTokens,
    int? completionTokens,
    int? messageCount,
    String? conversationSummary,
    int? lastSummarizedIndex,
  }) {
    return Session(
      id: id,
      title: title ?? this.title,
      pinned: pinned ?? this.pinned,
      lastMessage: lastMessage ?? this.lastMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      promptTokens: promptTokens ?? this.promptTokens,
      completionTokens: completionTokens ?? this.completionTokens,
      messageCount: messageCount ?? this.messageCount,
      conversationSummary: conversationSummary ?? this.conversationSummary,
      lastSummarizedIndex: lastSummarizedIndex ?? this.lastSummarizedIndex,
    );
  }
}
