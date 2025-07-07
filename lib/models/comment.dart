import 'package:cloud_firestore/cloud_firestore.dart';

class Comment {
  final String id;
  final String countdownId;
  final String content;
  final String authorId;
  final String authorName;
  final DateTime createdAt;
  final int likesCount;
  final int repliesCount;
  final String status;           // visible, hidden_by_moderator, deleted_by_user
  final Map<String, dynamic>? moderationInfo; // 運営操作情報

  Comment({
    required this.id,
    required this.countdownId,
    required this.content,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
    this.likesCount = 0,
    this.repliesCount = 0,
    this.status = 'visible',
    this.moderationInfo,
  });

  factory Comment.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data();
    return Comment(
      id: snapshot.id,
      countdownId: data?['countdownId'] as String,
      content: data?['content'] as String,
      authorId: data?['authorId'] as String,
      authorName: data?['authorName'] as String? ?? 'ユーザー',
      createdAt: (data?['createdAt'] as Timestamp).toDate(),
      likesCount: data?['likesCount'] as int? ?? 0,
      repliesCount: data?['repliesCount'] as int? ?? 0,
      status: data?['status'] as String? ?? 'visible',
      moderationInfo: data?['moderationInfo'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      "countdownId": countdownId,
      "content": content,
      "authorId": authorId,
      "authorName": authorName,
      "createdAt": Timestamp.fromDate(createdAt),
      "likesCount": likesCount,
      "repliesCount": repliesCount,
      "status": status,
      if (moderationInfo != null) "moderationInfo": moderationInfo,
    };
  }
}