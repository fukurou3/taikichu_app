import 'package:cloud_firestore/cloud_firestore.dart';
import 'countdown.dart';

class TrendRanking {
  final String countdownId;
  final String eventName;
  final String category;
  final DateTime eventDate;
  final int participantsCount;
  final int commentsCount;
  final int sharesCount;
  final double trendScore;
  final int rank;

  TrendRanking({
    required this.countdownId,
    required this.eventName,
    required this.category,
    required this.eventDate,
    required this.participantsCount,
    required this.commentsCount,
    required this.sharesCount,
    required this.trendScore,
    required this.rank,
  });

  factory TrendRanking.fromCountdown(
    Countdown countdown,
    int commentsCount,
    int sharesCount,
    double trendScore,
    int rank,
  ) {
    return TrendRanking(
      countdownId: countdown.id,
      eventName: countdown.eventName,
      category: countdown.category,
      eventDate: countdown.eventDate,
      participantsCount: countdown.participantsCount,
      commentsCount: commentsCount,
      sharesCount: sharesCount,
      trendScore: trendScore,
      rank: rank,
    );
  }
}

enum RankingType {
  overall,
  game,
  music,
  anime,
  live,
  oshi,
}

extension RankingTypeExtension on RankingType {
  String get displayName {
    switch (this) {
      case RankingType.overall:
        return '総合';
      case RankingType.game:
        return 'ゲーム';
      case RankingType.music:
        return '音楽';
      case RankingType.anime:
        return 'アニメ';
      case RankingType.live:
        return 'ライブ';
      case RankingType.oshi:
        return '推し活';
    }
  }

  String get categoryFilter {
    switch (this) {
      case RankingType.overall:
        return '';
      case RankingType.game:
        return 'ゲーム';
      case RankingType.music:
        return '音楽';
      case RankingType.anime:
        return 'アニメ';
      case RankingType.live:
        return 'ライブ';
      case RankingType.oshi:
        return '推し活';
    }
  }
}