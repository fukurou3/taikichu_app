import 'package:cloud_firestore/cloud_firestore.dart';

class Countdown {
  final String id;
  final String eventName;
  final DateTime eventDate;
  final String category;
  final String? imageUrl;
  final String creatorId;
  final int participantsCount;
  final int likesCount;
  final int commentsCount;
  final int viewsCount;
  final int recentCommentsCount; // 24時間以内のコメント数
  final int recentLikesCount;    // 24時間以内のいいね数
  final int recentViewsCount;    // 24時間以内の閲覧数
  final int? commentCount;       // 互換性のため追加

  Countdown({
    required this.id,
    required this.eventName,
    required this.eventDate,
    required this.category,
    this.imageUrl,
    required this.creatorId,
    this.participantsCount = 0,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.viewsCount = 0,
    this.recentCommentsCount = 0,
    this.recentLikesCount = 0,
    this.recentViewsCount = 0,
    this.commentCount,
  });

  factory Countdown.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data();
    return Countdown(
      id: snapshot.id,
      eventName: data?['eventName'] as String,
      eventDate: (data?['eventDate'] as Timestamp).toDate(),
      category: data?['category'] as String,
      imageUrl: data?['imageUrl'] as String?,
      creatorId: data?['creatorId'] as String,
      participantsCount: data?['participantsCount'] as int? ?? 0,
      likesCount: data?['likesCount'] as int? ?? 0,
      commentsCount: data?['commentsCount'] as int? ?? 0,
      viewsCount: data?['viewsCount'] as int? ?? 0,
      recentCommentsCount: data?['recentCommentsCount'] as int? ?? 0,
      recentLikesCount: data?['recentLikesCount'] as int? ?? 0,
      recentViewsCount: data?['recentViewsCount'] as int? ?? 0,
      commentCount: data?['commentCount'] as int? ?? data?['commentsCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      "eventName": eventName,
      "eventDate": Timestamp.fromDate(eventDate),
      "category": category,
      if (imageUrl != null) "imageUrl": imageUrl,
      "creatorId": creatorId,
      "participantsCount": participantsCount,
      "likesCount": likesCount,
      "commentsCount": commentsCount,
      "viewsCount": viewsCount,
      "recentCommentsCount": recentCommentsCount,
      "recentLikesCount": recentLikesCount,
      "recentViewsCount": recentViewsCount,
    };
  }
}