import 'package:cloud_firestore/cloud_firestore.dart';

class Countdown {
  final String id;
  final String eventName;
  final String? description;     // 説明文（ハッシュタグを含む）
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
    this.description,
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
      description: data?['description'] as String?,
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
      if (description != null) "description": description,
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

  /// 説明文からハッシュタグを抽出
  List<String> get hashtags {
    if (description == null) {
      print('Countdown.hashtags - description is null');
      return [];
    }
    
    print('Countdown.hashtags - description: "$description"');
    final regex = RegExp(r'#[^\s#]+');
    final matches = regex.allMatches(description!);
    final hashtagList = matches.map((match) => match.group(0)!.substring(1)).toList();
    print('Countdown.hashtags - extracted hashtags: $hashtagList');
    return hashtagList;
  }
}